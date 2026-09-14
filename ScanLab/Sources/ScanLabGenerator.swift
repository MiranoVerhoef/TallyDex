import SwiftUI
import CoreImage
import ImageIO

@MainActor final class ExampleGenerator: ObservableObject {
    @Published var running = false
    @Published var completed = 0
    @Published var error: String?
    private var task: Task<Void, Never>?
    private let context = CIContext()
    func cancel() { task?.cancel() }
    func generate(count: Int, store: DatasetStore) {
        guard !running else { return }
        running = true; completed = 0; error = nil
        task = Task { @MainActor in
            defer { running = false }
            do {
                guard let artRoot = Bundle.main.resourceURL?.appendingPathComponent("BundledCardThumbnails/images"),
                      let enumerator = FileManager.default.enumerator(at: artRoot, includingPropertiesForKeys: nil) else { throw LabError.invalid("Bundled front artwork not found.") }
                let artwork = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "webp" }
                guard !artwork.isEmpty else { throw LabError.invalid("No bundled card artwork is available.") }
                // NEVER derive training images from validation or test camera photos.
                let backgrounds = store.samples.filter { $0.exportable && $0.source == .camera && $0.kind == .background && $0.split == .training }
                let session = UUID()
                for _ in 0..<min(200, max(1, count)) {
                    try Task.checkCancellation()
                    try autoreleasepool {
                        guard let art = artwork.randomElement(), let source = CGImageSourceCreateWithURL(art as CFURL, nil), let card = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw LabError.invalid("Cannot decode bundled artwork.") }
                        let background = backgrounds.randomElement().flatMap { UIImage(contentsOfFile: store.imageURL($0).path) }
                        let result = try render(card: card, background: background)
                        try store.add(jpeg: result.jpeg, width: result.width, height: result.height, goal: CaptureGoal.all[0], session: session, region: result.region, source: .synthetic, parent: art.lastPathComponent)
                    }
                    completed += 1
                    await Task.yield()
                }
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func render(card: CGImage, background: UIImage?) throws -> CameraPhoto {
        let size = CGSize(width: 960, height: 1280)
        let width = Double.random(in: 240...480), height = width * Double(card.height) / Double(card.width)
        let x = Double.random(in: 80...(880 - width)), y = Double.random(in: 120...(1160 - height))
        let skew = width * Double.random(in: -0.2...0.2), tilt = width * Double.random(in: -0.2...0.2)
        let tl = CGPoint(x: x + max(0, skew), y: y)
        let tr = CGPoint(x: x + width + min(0, skew), y: y + tilt)
        let bl = CGPoint(x: x, y: y + height)
        let br = CGPoint(x: x + width, y: y + height - tilt)
        let points = [tl, tr, bl, br]
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let box = CardRegion(x: minX / size.width, y: minY / size.height, width: (maxX - minX) / size.width, height: (maxY - minY) / size.height)
        guard box.valid else { throw LabError.invalid("Generated outline exceeded the canvas.") }
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true; return f }())
        let base = renderer.image { drawing in
            if let background {
                let scale = max(size.width / background.size.width, size.height / background.size.height)
                let rect = CGRect(x: (size.width - background.size.width * scale) / 2, y: (size.height - background.size.height * scale) / 2, width: background.size.width * scale, height: background.size.height * scale)
                background.draw(in: rect)
            } else {
                UIColor(hue: .random(in: 0...1), saturation: .random(in: 0.05...0.35), brightness: .random(in: 0.25...0.85), alpha: 1).setFill()
                drawing.fill(CGRect(origin: .zero, size: size))
                for _ in 0..<12 {
                    drawing.cgContext.setFillColor(UIColor.white.withAlphaComponent(.random(in: 0.02...0.1)).cgColor)
                    drawing.cgContext.fill(CGRect(x: CGFloat.random(in: 0...960), y: CGFloat.random(in: 0...1280), width: CGFloat.random(in: 30...200), height: CGFloat.random(in: 10...80)))
                }
            }
            let path = UIBezierPath(); path.move(to: tl); path.addLine(to: tr); path.addLine(to: br); path.addLine(to: bl); path.close()
            drawing.cgContext.setShadow(offset: CGSize(width: 10, height: 16), blur: 18, color: UIColor.black.withAlphaComponent(0.4).cgColor)
            UIColor.black.setFill(); path.fill()
        }
        guard let baseCG = base.cgImage else { throw LabError.invalid("Cannot render generated background.") }
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: size.height - p.y) }
        let warped = CIImage(cgImage: card).applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": vector(tl), "inputTopRight": vector(tr), "inputBottomLeft": vector(bl), "inputBottomRight": vector(br)
        ]).applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: Double.random(in: -0.1...0.1), kCIInputContrastKey: Double.random(in: 0.8...1.2)])
        let composite = warped.composited(over: CIImage(cgImage: baseCG)).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Double.random(in: 0...1.1)]).cropped(to: CGRect(origin: .zero, size: size))
        guard let cg = context.createCGImage(composite, from: composite.extent), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { throw LabError.invalid("Cannot encode generated example.") }
        return CameraPhoto(jpeg: jpeg, width: cg.width, height: cg.height, region: box)
    }
}
struct GenerateScreen: View {
    @Bindable var store: DatasetStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var generator = ExampleGenerator()
    @State private var count = 50
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Label("Supplementary examples", systemImage: "sparkles").font(.title2.bold())
                Text("Create varied perspectives, lighting, blur, and backgrounds from bundled card fronts. Outlines are known from the transform. Generated photos are training-only and do NOT count toward your real-camera goals.").foregroundStyle(.secondary)
                Text("Approved training backgrounds can be reused. Validation and test photos are never used as backgrounds. Low-resolution artwork cannot replace real camera photos.").font(.subheadline).foregroundStyle(.secondary)
                Stepper("\(count) examples", value: $count, in: 10...200, step: 10).disabled(generator.running)
                Text("Allow roughly 10–50 MB for 200 images. You can stop a batch; completed examples are kept.").font(.caption).foregroundStyle(.secondary)
                if generator.running {
                    ProgressView(value: Double(generator.completed), total: Double(count))
                    Text("\(generator.completed) / \(count)").font(.headline.monospacedDigit())
                    Button("Stop generation") { generator.cancel() }.buttonStyle(.bordered)
                } else {
                    Button("Generate training extras") { generator.generate(count: count, store: store) }.buttonStyle(.borderedProminent).controlSize(.large)
                    if generator.completed > 0 { Text("\(generator.completed) generated examples saved.").foregroundStyle(.mint) }
                }
                if let error = generator.error { Text(error).foregroundStyle(.orange) }
                Spacer()
            }.padding(24).navigationTitle("Generate extras").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { generator.cancel(); dismiss() } } }
                .onDisappear { generator.cancel() }
        }
    }
}
