import AVFoundation
import Vision
import CoreImage
import SwiftUI

struct CameraPhoto {
    let jpeg: Data
    let width: Int
    let height: Int
    let region: CardRegion?
}

final class ScanCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var region: CardRegion?
    @Published var status = "Preparing camera…"
    @Published var aspect: CGFloat = 9.0 / 16.0
    @Published var permissionDenied = false
    @Published var captures = 0
    var onCapture: ((CameraPhoto) -> Void)?
    private let queue = DispatchQueue(label: "nl.tallydex.scanlab.camera", qos: .userInitiated)
    private let context = CIContext()
    private var latest: CVPixelBuffer?
    private var latestRegion: CardRegion?
    private var gate = CaptureGate()
    private var contentGate = ContentChangeGate()
    private var lastFrame: TimeInterval = 0
    private var autoCapture = true
    private var negativeMode = false
    private var active = true
    private var configured = false
    private var lockedBox: CardRegion?
    private var missingFrames = 0
    private var lastNegative: [Double]?
    private var stableNegative: [Double]?
    private var negativeSince: TimeInterval = 0
    private var lastNegativeCapture: TimeInterval = -.infinity

    func setAuto(_ enabled: Bool) { queue.async { self.autoCapture = enabled } }
    func start(negative: Bool) {
        queue.async { self.negativeMode = negative; self.active = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                if allowed { self.configureAndRun() } else { self.deny() }
            }
        default: deny()
        }
    }
    private func deny() { DispatchQueue.main.async { self.permissionDenied = true; self.status = "Camera access is off. Enable it in iPhone Settings." } }
    private func configureAndRun() {
        queue.async {
            guard self.active else { return }
            do {
                if !self.configured {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = .hd1920x1080
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw LabError.invalid("A real iPhone camera is required; the simulator cannot capture cards.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { throw LabError.invalid("Camera input unavailable.") }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { throw LabError.invalid("Camera output unavailable.") }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    try device.lockForConfiguration()
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    device.unlockForConfiguration()
                    self.configured = true
                }
                self.session.startRunning()
                DispatchQueue.main.async { self.status = self.negativeMode ? "Pause on a new scene to auto-save" : "Show one card and pause" }
            } catch { DispatchQueue.main.async { self.status = error.localizedDescription } }
        }
    }
    func stop() { queue.async { self.active = false; if self.session.isRunning { self.session.stopRunning() }; self.latest = nil } }
    func shutter() { queue.async { self.saveCurrent() } }
    func newCard() {
        queue.async { self.gate.reset(); self.contentGate.reset(); self.lockedBox = nil; self.lastNegative = nil; self.stableNegative = nil }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latest = buffer
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.25 else { return }
        lastFrame = now
        let aspect = CGFloat(CVPixelBufferGetWidth(buffer)) / CGFloat(CVPixelBufferGetHeight(buffer))
        if negativeMode {
            latestRegion = nil
            DispatchQueue.main.async { self.region = nil; self.aspect = aspect }
            guard autoCapture else { return }
            let fingerprint = fingerprint(buffer)
            if let stableNegative, difference(stableNegative, fingerprint) < 0.035 {
                if now - negativeSince >= 0.9, now - lastNegativeCapture >= 3,
                   lastNegative == nil || difference(lastNegative!, fingerprint) > 0.07 {
                    lastNegative = fingerprint; lastNegativeCapture = now; saveCurrent()
                }
            } else { stableNegative = fingerprint; negativeSince = now }
            return
        }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.65
        request.minimumSize = 0.12
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 0.85
        request.quadratureTolerance = 35
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let candidates = (request.results ?? []).map { observation -> CardRegion in
                let box = observation.boundingBox
                return CardRegion(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }.filter(\.valid)
            // Prefer the existing tracked card, not whichever rectangle is largest this frame.
            var chosen: CardRegion?
            if let lockedBox {
                if let nearest = candidates.min(by: { $0.distance(to: lockedBox) < $1.distance(to: lockedBox) }), nearest.distance(to: lockedBox) < 0.35 {
                    chosen = CardRegion(x: lockedBox.x * 0.4 + nearest.x * 0.6, y: lockedBox.y * 0.4 + nearest.y * 0.6, width: lockedBox.width * 0.4 + nearest.width * 0.6, height: lockedBox.height * 0.4 + nearest.height * 0.6)
                    missingFrames = 0
                } else {
                    missingFrames += 1
                    if missingFrames >= 5 { self.lockedBox = nil }
                }
            } else { chosen = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }); missingFrames = 0 }
            if let chosen { lockedBox = chosen }
            latestRegion = chosen
            if autoCapture, let chosen, contentGate.observe(fingerprint(buffer, region: chosen), at: now) { gate.reset() }
            let shouldSave = autoCapture && gate.observe(chosen, at: now)
            DispatchQueue.main.async {
                self.region = chosen; self.aspect = aspect
                self.status = chosen == nil ? "Show one card · manual shutter also works" : "Suggested outline · review required"
            }
            if autoCapture && shouldSave { saveCurrent() }
        } catch { DispatchQueue.main.async { self.status = "Outline unavailable · use manual shutter" } }
    }
    private func saveCurrent() {
        guard active, let latest else { DispatchQueue.main.async { self.status = "Waiting for a camera frame…" }; return }
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: latest)
            let scale = min(1, 1440 / max(image.extent.width, image.extent.height))
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(scaled, from: scaled.extent), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { return }
            let photo = CameraPhoto(jpeg: jpeg, width: cg.width, height: cg.height, region: latestRegion)
            let now = ProcessInfo.processInfo.systemUptime
            if !negativeMode, let region = latestRegion {
                gate.markCaptured(region, at: now)
                contentGate.markSaved(fingerprint(latest, region: region), at: now)
            } else if negativeMode { lastNegative = fingerprint(latest); lastNegativeCapture = now }
            DispatchQueue.main.async { self.onCapture?(photo); self.captures += 1 }
        }
    }
    private func fingerprint(_ buffer: CVPixelBuffer, region: CardRegion? = nil) -> [Double] {
        var image = CIImage(cvPixelBuffer: buffer)
        if let region {
            let extent = image.extent
            let rect = CGRect(x: region.x * extent.width, y: (1 - region.y - region.height) * extent.height, width: region.width * extent.width, height: region.height * extent.height)
            image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        let small = image.transformed(by: CGAffineTransform(scaleX: 8 / image.extent.width, y: 8 / image.extent.height))
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        context.render(small, toBitmap: &bytes, rowBytes: 32, bounds: CGRect(x: 0, y: 0, width: 8, height: 8), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var result: [Double] = []
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = Double(bytes[index]), green = Double(bytes[index + 1]), blue = Double(bytes[index + 2])
            result.append((red + green + blue) / 765.0)
        }
        return result
    }
    private func difference(_ lhs: [Double], _ rhs: [Double]) -> Double { zip(lhs, rhs).map { abs($0 - $1) }.reduce(0, +) / Double(max(1, lhs.count)) }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewSurface { let view = PreviewSurface(); view.layerView.session = session; view.layerView.videoGravity = .resizeAspect; return view }
    func updateUIView(_ uiView: PreviewSurface, context: Context) { uiView.setNeedsLayout() }
}
final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = layerView.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
