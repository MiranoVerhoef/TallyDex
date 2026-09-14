import Foundation
import Observation

enum SampleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case front, back, background
    var id: String { rawValue }
    var title: String { switch self { case .front: "Pokémon card front"; case .back: "Pokémon card back"; case .background: "No Pokémon card" } }
    var label: String { self == .back ? "pokemon_card_back" : "pokemon_card_front" }
}
enum DatasetSplit: String, Codable, Sendable { case training, validation, test }
enum SampleSource: String, Codable, Sendable { case camera, synthetic }
struct CardRegion: Codable, Equatable, Sendable {
    // Upright-image coordinates, normalized, origin at top-left.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0.02 && height > 0.02 && x + width <= 1.00001 && y + height <= 1.00001 }
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
    func distance(to other: Self) -> Double { abs(centerX - other.centerX) + abs(centerY - other.centerY) + abs(width - other.width) + abs(height - other.height) }
}
struct CaptureGoal: Identifiable, Codable {
    var id: String
    var title: String
    var instruction: String
    var target: Int
    var kind: SampleKind = .front
    var split: DatasetSplit = .training
    static let all: [Self] = [
        .init(id: "clear", title: "Clear fronts", instruction: "One card at a time. Use different Pokémon, eras, and layouts. Change the card after a few views.", target: 30),
        .init(id: "sleeves", title: "Sleeves & top loaders", instruction: "Try clear sleeves, colored sleeves, and top loaders. Outline the actual card, not its holder.", target: 20),
        .init(id: "glare", title: "Glare & lighting", instruction: "Try holo glare, window light, and dim rooms. Keep the card recognizable; use the shutter if detection misses.", target: 15),
        .init(id: "angles", title: "Different angles", instruction: "Tilt and rotate the card, then pause. Include near and far views with all four corners visible.", target: 20),
        .init(id: "backgrounds", title: "Busy backgrounds", instruction: "Use desks, playmats, patterned fabric, and objects behind ONE card. Keep all four corners visible.", target: 20),
        .init(id: "negatives", title: "Things that are not cards", instruction: "Capture phones, books, boxes, other trading cards, and empty scenes. Confirm there is NO Pokémon card anywhere in the image.", target: 30, kind: .background),
        .init(id: "backs", title: "Card backs", instruction: "Show one Pokémon card back in different scenes. These have their own label, separate from fronts.", target: 10, kind: .back),
        .init(id: "validation", title: "Validation session", instruction: "Use NEW cards and a new scene: 10 fronts, 2 backs, 3 non-card scenes. Change capture type below. No generated photos.", target: 15, split: .validation),
        .init(id: "test", title: "Unseen test session", instruction: "Use NEW cards and a different scene: 14 fronts, 3 backs, 3 non-card scenes. Change capture type below. Save these for final evaluation.", target: 20, split: .test)
    ]
}
struct ScanSample: Codable, Identifiable, Sendable {
    var id: UUID
    var created: Date
    var goalID: String
    var sessionID: UUID
    var split: DatasetSplit
    var source: SampleSource
    var kind: SampleKind
    var region: CardRegion?
    var imageWidth: Int
    var imageHeight: Int
    var approved: Bool = false
    var excluded: Bool = false
    var parentID: String? = nil
    var filename: String { id.uuidString + ".jpg" }
    var exportable: Bool { approved && !excluded && imageWidth > 0 && imageHeight > 0 && (kind == .background || region?.valid == true) && (source == .camera || split == .training) }
}
enum LabError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

@MainActor @Observable final class DatasetStore {
    private(set) var samples: [ScanSample] = []
    private(set) var loadError: String?
    var lastError: String?
    let root: URL
    private var metadata: URL { root.appendingPathComponent("samples.json") }
    var pending: [ScanSample] { samples.filter { !$0.approved && !$0.excluded }.reversed() }
    var approvedCount: Int { samples.filter(\.exportable).count }
    init(root: URL) {
        self.root = root
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: metadata.path) {
                samples = try JSONDecoder().decode([ScanSample].self, from: Data(contentsOf: metadata))
                guard Set(samples.map(\.id)).count == samples.count else { throw LabError.invalid("Duplicate sample IDs in saved dataset.") }
            }
        } catch { loadError = error.localizedDescription; lastError = "Dataset could not load. Existing files have not been overwritten: " + error.localizedDescription }
    }
    func imageURL(_ sample: ScanSample) -> URL { root.appendingPathComponent("images").appendingPathComponent(sample.filename) }
    func count(_ goal: CaptureGoal) -> Int { samples.filter { $0.goalID == goal.id && $0.source == .camera && ($0.kind == goal.kind || goal.split != .training) && $0.exportable }.count }
    var nextGoal: CaptureGoal { CaptureGoal.all.first { count($0) < $0.target } ?? CaptureGoal.all[0] }
    private func persist(_ updated: [ScanSample]) throws {
        guard loadError == nil else { throw LabError.invalid("Dataset is locked because its saved metadata could not load.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: metadata, options: .atomic)
        samples = updated
    }
    func add(jpeg: Data, width: Int, height: Int, goal: CaptureGoal, session: UUID, region: CardRegion?, source: SampleSource = .camera, parent: String? = nil) throws {
        guard loadError == nil else { throw LabError.invalid("Cannot save until the dataset loading error is resolved.") }
        guard !jpeg.isEmpty, width > 0, height > 0 else { throw LabError.invalid("The camera did not produce a valid image.") }
        let sample = ScanSample(id: UUID(), created: Date(), goalID: goal.id, sessionID: session, split: source == .synthetic ? .training : goal.split, source: source, kind: goal.kind, region: region, imageWidth: width, imageHeight: height, approved: source == .synthetic, parentID: parent)
        // Write the photo first. If metadata fails, an orphan remains recoverable rather than falsely counted.
        try jpeg.write(to: imageURL(sample), options: .atomic)
        try persist(samples + [sample])
    }
    func review(id: UUID, kind: SampleKind, region: CardRegion?, exclude: Bool = false) throws {
        guard let index = samples.firstIndex(where: { $0.id == id }) else { throw LabError.invalid("Sample not found.") }
        guard exclude || kind == .background || region?.valid == true else { throw LabError.invalid("Mark the full card outline before approving.") }
        var updated = samples
        updated[index].kind = kind
        updated[index].region = kind == .background ? nil : region
        updated[index].approved = !exclude
        updated[index].excluded = exclude
        try persist(updated)
    }
    func export() throws -> URL {
        try Self.export(samples: samples, root: root)
    }
    nonisolated static func export(samples: [ScanSample], root: URL) throws -> URL {
        let selected = samples.filter(\.exportable)
        guard !selected.isEmpty else { throw LabError.invalid("Approve some examples before exporting.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScanLab-" + UUID().uuidString + ".zip")
        var entries: [StoredZIP.Entry] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for split in [DatasetSplit.training, .validation, .test] {
            let group = selected.filter { $0.split == split }
            let annotations = group.map { sample -> AnnotationImage in
                let boxes: [AnnotationBox]
                if sample.kind == .background { boxes = [] }
                else if let region = sample.region {
                    boxes = [.init(label: sample.kind.label, coordinates: .init(x: region.centerX * Double(sample.imageWidth), y: region.centerY * Double(sample.imageHeight), width: region.width * Double(sample.imageWidth), height: region.height * Double(sample.imageHeight)))]
                } else { boxes = [] }
                return .init(image: "images/" + sample.filename, annotations: boxes)
            }
            entries.append(.data(split.rawValue + "/annotations.json", try encoder.encode(annotations)))
            for sample in group { entries.append(.file(split.rawValue + "/images/" + sample.filename, root.appendingPathComponent("images").appendingPathComponent(sample.filename))) }
        }
        entries.append(.data("manifest.json", try encoder.encode(selected)))
        entries.append(.data("README.txt", Data("""
        TallyDex Scan Lab: reviewed examples only.
        Labels: pokemon_card_front, pokemon_card_back. Empty annotations mean no Pokémon card.
        Bounding boxes use upright-image pixel coordinates: center x,y,width,height.
        Synthetic images are training-only. Goals count real, approved camera photos.
        Keep all views of the same physical card and scene in ONE split. Session IDs record capture batches,
        not verified card identity: manually check for duplicates between splits before training.
        Unreviewed and excluded photos are not exported. No photos have been uploaded.
        See ScanLab/README.md and Tools/train.swift in the TallyDex repository.
        """.utf8)))
        try StoredZIP.write(entries: entries, to: url)
        return url
    }
}
struct AnnotationImage: Codable { var image: String; var annotations: [AnnotationBox] }
struct AnnotationBox: Codable { var label: String; var coordinates: PixelBox }
struct PixelBox: Codable { var x: Double; var y: Double; var width: Double; var height: Double }

// Hysteresis: several consistent observations are required, then a materially new pose
// or sustained absence is needed before saving again. Small detector jitter cannot rearm.
struct CaptureGate {
    private var anchor: CardRegion?
    private var stableSince: TimeInterval?
    private var captured: CardRegion?
    private var missingSince: TimeInterval?
    private var lastCapture: TimeInterval = -.infinity
    mutating func reset() { self = Self() }
    mutating func markCaptured(_ region: CardRegion, at time: TimeInterval) {
        captured = region; lastCapture = time; anchor = nil; stableSince = nil
    }
    mutating func observe(_ region: CardRegion?, at time: TimeInterval) -> Bool {
        guard let region, region.valid else {
            if missingSince == nil { missingSince = time }
            if time - (missingSince ?? time) > 1.2 { anchor = nil; stableSince = nil; captured = nil }
            return false
        }
        missingSince = nil
        if let captured, region.distance(to: captured) < 0.18 { return false }
        if let anchor, region.distance(to: anchor) < 0.07 {
            if time - (stableSince ?? time) >= 0.8 && time - lastCapture >= 2.5 {
                captured = region; lastCapture = time; self.anchor = nil; stableSince = nil
                return true
            }
        } else { anchor = region; stableSince = time }
        return false
    }
}

// Rearm even if a replacement card occupies the same rectangle. This checks stable
// visual change, NOT verified card identity. Lighting changes can also qualify.
struct ContentChangeGate {
    private var saved: [Double]?
    private var candidate: [Double]?
    private var stableSince: TimeInterval = 0
    private var lastSaved: TimeInterval = -.infinity
    private var rearmed = false
    mutating func reset() { self = Self() }
    mutating func markSaved(_ values: [Double], at time: TimeInterval) {
        saved = values; candidate = nil; lastSaved = time; rearmed = false
    }
    mutating func observe(_ values: [Double], at time: TimeInterval) -> Bool {
        guard let saved, !values.isEmpty, values.count == saved.count else { return false }
        guard distance(saved, values) > 0.10 else { candidate = nil; rearmed = false; return false }
        guard !rearmed else { return false }
        if let candidate, distance(candidate, values) < 0.035 {
            if time - stableSince >= 0.7 && time - lastSaved >= 2.5 { rearmed = true; return true }
        } else { candidate = values; stableSince = time }
        return false
    }
    private func distance(_ lhs: [Double], _ rhs: [Double]) -> Double { zip(lhs,rhs).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(lhs.count) }
}
