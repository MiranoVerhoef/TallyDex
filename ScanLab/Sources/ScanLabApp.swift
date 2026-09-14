import SwiftUI
import UIKit
import ImageIO

@main struct ScanLabApp: App {
    @State private var store = DatasetStore(root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ScanLab"))
    var body: some Scene {
        WindowGroup { LabHome(store: store).tint(.indigo).preferredColorScheme(.dark) }
    }
}
struct LabHome: View {
    @Bindable var store: DatasetStore
    @State private var captureGoal: CaptureGoal?
    @State private var showGenerate = false
    @State private var exportItem: ExportItem?
    @State private var exporting = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("TRAIN A BETTER SCANNER", systemImage: "viewfinder").font(.caption.weight(.bold)).foregroundStyle(.mint)
                        Text("Show a card.\nPause. Keep the good shots.").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("Capture is automatic. Labels are suggestions until you review them. All photos stay on your iPhone.").foregroundStyle(.secondary)
                        HStack { stat("\(store.approvedCount)", "Approved"); Spacer(); stat("\(store.pending.count)", "To review"); Spacer(); stat("\(realTotal) / 180", "Real goals") }.padding(.top, 8)
                    }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    if let error = store.loadError { Label("Saved dataset is locked: " + error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    if !store.pending.isEmpty {
                        NavigationLink { ReviewQueue(store: store) } label: {
                            HStack { Label("Review \(store.pending.count) photos", systemImage: "checkmark.rectangle.stack"); Spacer(); Image(systemName: "chevron.right") }.font(.headline).padding(18).background(.indigo.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Your next goal").font(.title2.bold()); Spacer(); Text("\(completedGoals)/9 done").font(.caption).foregroundStyle(.secondary) }
                        let next = store.nextGoal
                        Text(next.title).font(.headline)
                        Text(next.instruction).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { captureGoal = next } label: { Label("Start automatic capture", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(store.loadError != nil)
                    }.padding(20).background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Collection goals").font(.title2.bold())
                        Text("180 reviewed real photos is a starter dataset, not a guarantee of a reliable model. Variety matters more than duplicates.").font(.caption).foregroundStyle(.secondary)
                        ForEach(CaptureGoal.all) { goal in
                            Button { captureGoal = goal } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text(goal.title).font(.headline); Spacer(); Text("\(store.count(goal))/\(goal.target)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                                    ProgressView(value: Double(min(store.count(goal), goal.target)), total: Double(goal.target))
                                    HStack { Text(goal.kind.title); Spacer(); Text(goal.split.rawValue.capitalized) }.font(.caption).foregroundStyle(.secondary)
                                }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).disabled(store.loadError != nil)
                        }
                    }
                    HStack(spacing: 12) {
                        Button { showGenerate = true } label: { Label("Generate extras", systemImage: "sparkles").frame(maxWidth: .infinity) }.disabled(store.loadError != nil)
                        Button { export() } label: { Label(exporting ? "Exporting…" : "Export ZIP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.disabled(store.approvedCount == 0 || exporting)
                    }.buttonStyle(.bordered).controlSize(.large)
                    NavigationLink("Browse all samples") { SampleLibrary(store: store) }.font(.subheadline)
                    Text("This lab proposes card-shaped outlines; it does not yet know whether an object is a Pokémon card. Use ONE card per photo, with all corners visible. Exclude photos with multiple cards or an unrecognizable card.").font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("Scan Lab").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $captureGoal) { goal in CaptureScreen(store: store, goal: goal) }
                .sheet(isPresented: $showGenerate) { GenerateScreen(store: store) }
                .sheet(item: $exportItem) { ShareSheet(url: $0.url) }
                .alert("Scan Lab", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) { Button("OK") { store.lastError = nil } } message: { Text(store.lastError ?? "") }
        }
    }
    private var realTotal: Int { CaptureGoal.all.reduce(0) { $0 + min(store.count($1), $1.target) } }
    private var completedGoals: Int { CaptureGoal.all.filter { store.count($0) >= $0.target }.count }
    private func stat(_ number: String, _ title: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(number).font(.title3.bold().monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) } }
    private func export() {
        exporting = true
        // Yield to show export state. JPEG entries are streamed one at a time.
        Task { @MainActor in
            await Task.yield()
            let samples = store.samples, root = store.root
            do { exportItem = ExportItem(url: try await Task.detached(priority: .userInitiated) { try DatasetStore.export(samples: samples, root: root) }.value) } catch { store.lastError = error.localizedDescription }
            exporting = false
        }
    }
}
struct ExportItem: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct CaptureScreen: View {
    @Bindable var store: DatasetStore
    let goal: CaptureGoal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = ScanCamera()
    @State private var automatic = true
    @State private var sessionID = UUID()
    @State private var saved = 0
    @State private var error: String?
    @State private var reviewing = false
    @State private var recordingKind: SampleKind
    init(store: DatasetStore, goal: CaptureGoal) { self.store = store; self.goal = goal; _recordingKind = State(initialValue: goal.kind) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(goal.instruction).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal)
                if goal.split != .training {
                    Picker("Capture type", selection: $recordingKind) { ForEach(SampleKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                }
                GeometryReader { geo in
                    ZStack {
                        Color.black
                        CameraPreview(session: camera.session)
                        if let box = camera.region {
                            let frame = fittedFrame(in: geo.size, aspect: camera.aspect)
                            RoundedRectangle(cornerRadius: 10).stroke(.mint, lineWidth: 3)
                                .frame(width: frame.width * box.width, height: frame.height * box.height)
                                .position(x: frame.minX + frame.width * box.centerX, y: frame.minY + frame.height * box.centerY)
                        }
                        if camera.permissionDenied {
                            Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(.borderedProminent)
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 20))
                }.padding(.horizontal)
                Text(camera.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack { Toggle("Auto capture", isOn: $automatic); Spacer(); VStack(alignment: .trailing) { Text("\(saved) saved").font(.subheadline.monospacedDigit()); Text("\(store.count(goal))/\(goal.target) reviewed").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal)
                HStack(spacing: 22) {
                    Button { sessionID = UUID(); camera.newCard() } label: { Label(recordingKind == .background ? "New scene" : "New card", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                    Button { camera.shutter() } label: { Image(systemName: "camera.fill").font(.title2).frame(width: 68, height: 60).background(.white, in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(.black) }.accessibilityLabel("Capture now")
                    Button { camera.stop(); reviewing = true } label: { Label("Review", systemImage: "checkmark.rectangle.stack").font(.caption) }.disabled(store.pending.isEmpty)
                }.padding(.bottom, 14)
                if store.pending.count >= 60 { Text("Auto paused: review your queue before collecting more.").font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if store.count(goal) >= goal.target { Text("Goal complete! Tap Done for your next goal.").font(.caption).foregroundStyle(.mint) }
                Text("One card · full outline · suggestions need approval").font(.caption2).foregroundStyle(.secondary).padding(.bottom, 8)
            }.navigationTitle(goal.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .onAppear { start() }
                .onDisappear { camera.stop() }
                .onChange(of: scenePhase) { _, phase in if phase == .active && !reviewing { start() } else { camera.stop() } }
                .onChange(of: automatic) { _, enabled in camera.setAuto(enabled) }
                .onChange(of: recordingKind) { _, _ in sessionID = UUID(); camera.newCard(); start() }
                .sheet(isPresented: $reviewing, onDismiss: { automatic = store.pending.count < 60 && store.count(goal) < goal.target; start() }) { NavigationStack { ReviewQueue(store: store).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { reviewing = false } } } } }
                .alert("Photo not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func start() {
        camera.onCapture = { photo in
            do {
                guard store.pending.count < 60 else { automatic = false; camera.setAuto(false); return }
                var captureGoal = goal; captureGoal.kind = recordingKind
                try store.add(jpeg: photo.jpeg, width: photo.width, height: photo.height, goal: captureGoal, session: sessionID, region: photo.region)
                saved += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if store.pending.count >= 60 { automatic = false; camera.setAuto(false) }
            } catch { automatic = false; camera.setAuto(false); self.error = error.localizedDescription }
        }
        if store.pending.count >= 60 { automatic = false }
        camera.setAuto(automatic)
        camera.start(negative: recordingKind == .background)
    }
}

func fittedFrame(in size: CGSize, aspect: CGFloat) -> CGRect {
    let width = min(size.width, size.height * aspect), height = min(size.height, size.width / aspect)
    return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
}

struct ReviewQueue: View {
    @Bindable var store: DatasetStore
    var body: some View {
        Group {
            if let sample = store.pending.first { SampleReview(store: store, sample: sample).id(sample.id) }
            else { ContentUnavailableView("All reviewed", systemImage: "checkmark.seal", description: Text("Approved examples count toward goals. Excluded photos remain on your phone but are not exported.")) }
        }.navigationTitle("Review photos").navigationBarTitleDisplayMode(.inline)
    }
}
struct SampleReview: View {
    @Bindable var store: DatasetStore
    let sample: ScanSample
    @State private var kind: SampleKind
    @State private var region: CardRegion
    @State private var error: String?
    @State private var image: UIImage?
    init(store: DatasetStore, sample: ScanSample) {
        self.store = store; self.sample = sample
        _kind = State(initialValue: sample.kind)
        _region = State(initialValue: sample.region.flatMap { $0.valid ? $0 : nil } ?? CardRegion(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        _image = State(initialValue: UIImage(contentsOfFile: store.imageURL(sample).path))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack { Text("\(store.pending.count) to review"); Spacer(); Text(sample.split.rawValue.capitalized).foregroundStyle(.secondary) }.font(.caption)
                if let image {
                    EditablePhoto(image: image, region: $region, showBox: kind != .background)
                        .frame(height: 390).background(.black, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
                } else { Label("Photo could not load. Exclude it; do not approve unseen images.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Picker("What is in the photo?", selection: $kind) { ForEach(SampleKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu).frame(maxWidth: .infinity)
                Text(kind == .background ? "Approve only if NO Pokémon card appears anywhere in this photo." : "Drag the two handles to tightly enclose the actual card. One card only; all corners must be visible. Exclude incomplete, multi-card, or ambiguous photos.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Exclude") { review(exclude: true) }.buttonStyle(.bordered).tint(.orange)
                    Button("Approve") { review(exclude: false) }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(image == nil || (kind != .background && !region.valid))
                }.controlSize(.large)
                Text("Excluding does not delete the original. Suggested labels are not automatically verified.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.alert("Cannot approve", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func review(exclude: Bool) { do { try store.review(id: sample.id, kind: kind, region: region, exclude: exclude) } catch { self.error = error.localizedDescription } }
}
struct EditablePhoto: View {
    let image: UIImage
    @Binding var region: CardRegion
    let showBox: Bool
    var body: some View {
        GeometryReader { geo in
            let frame = fittedFrame(in: geo.size, aspect: image.size.width / image.size.height)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                if showBox {
                    Rectangle().stroke(.mint, lineWidth: 2).frame(width: frame.width * region.width, height: frame.height * region.height).position(x: frame.minX + frame.width * region.centerX, y: frame.minY + frame.height * region.centerY)
                    handle(topLeft: true, frame: frame)
                    handle(topLeft: false, frame: frame)
                }
            }.coordinateSpace(name: "photo")
        }
    }
    private func handle(topLeft: Bool, frame: CGRect) -> some View {
        Circle().fill(.mint).frame(width: 22, height: 22).overlay(Circle().stroke(.black, lineWidth: 2))
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: frame.minX + frame.width * (topLeft ? region.x : region.x + region.width), y: frame.minY + frame.height * (topLeft ? region.y : region.y + region.height))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("photo")).onChanged { value in
                let x = min(1, max(0, (value.location.x - frame.minX) / frame.width))
                let y = min(1, max(0, (value.location.y - frame.minY) / frame.height))
                if topLeft {
                    let right = region.x + region.width, bottom = region.y + region.height
                    region.x = min(x, right - 0.04); region.y = min(y, bottom - 0.04)
                    region.width = right - region.x; region.height = bottom - region.y
                } else { region.width = max(0.04, x - region.x); region.height = max(0.04, y - region.y) }
            })
            .accessibilityLabel(topLeft ? "Top-left card outline handle" : "Bottom-right card outline handle")
    }
}
struct SampleLibrary: View {
    @Bindable var store: DatasetStore
    var body: some View {
        List {
            ForEach(store.samples.reversed()) { sample in
                NavigationLink { SampleReview(store: store, sample: sample) } label: {
                    HStack(spacing: 12) {
                        SampleThumbnail(url: store.imageURL(sample)).frame(width: 50, height: 65).clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(sample.kind.title).font(.headline)
                            Text(sample.excluded ? "Excluded" : sample.approved ? "Approved" : "Needs review").foregroundStyle(sample.excluded ? .orange : .secondary)
                            Text("\(sample.source.rawValue.capitalized) · \(sample.split.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("All samples")
    }
}
struct SampleThumbnail: View {
    let url: URL
    @State private var thumbnail: UIImage?
    var body: some View { Group { if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() } else { Color.gray.opacity(0.2) } }.task(id: url) {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 150, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { thumbnail = UIImage(cgImage: cg) }
    } }
}
