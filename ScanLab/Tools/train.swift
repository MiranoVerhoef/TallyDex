import Foundation
import CreateML
import CryptoKit
import ImageIO

// Run on a Mac with Xcode installed. No training or writes occur with --check.
struct Record: Decodable {
    let id: UUID
    let sessionID: UUID
    let split: String
    let source: String
    let kind: String
    let approved: Bool
    let excluded: Bool
    let imageWidth: Int
    let imageHeight: Int
}
struct Annotation: Decodable {
    let image: String
    let annotations: [Box]
    struct Box: Decodable { let label: String; let coordinates: Coordinates }
    struct Coordinates: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "ScanLab", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
do {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.count == 2, "Usage: swift ScanLab/Tools/train.swift /absolute/path/to/unzipped-dataset --check\n   or: swift ScanLab/Tools/train.swift /absolute/path/to/unzipped-dataset /absolute/path/to/NEW-CardDetector.mlmodel")
    let root = URL(fileURLWithPath: args[0]).standardizedFileURL
    let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
    try require(!records.isEmpty, "Dataset is empty.")
    try require(Set(records.map(\.id)).count == records.count, "Duplicate sample IDs.")
    var hashes: [String: String] = [:], sessions: [UUID: String] = [:]
    for record in records {
        try require(record.approved && !record.excluded, "Unreviewed/excluded image in manifest.")
        try require(["training", "validation", "test"].contains(record.split), "Unknown split.")
        try require(["camera", "synthetic"].contains(record.source), "Unknown image source.")
        try require(record.source == "camera" || record.split == "training", "Synthetic images leaked into validation/test.")
        if let split = sessions[record.sessionID] { try require(split == record.split, "Capture session crosses splits.") }
        sessions[record.sessionID] = record.split
        let url = root.appendingPathComponent(record.split + "/images/" + record.id.uuidString + ".jpg")
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if let split = hashes[hash] { try require(split == record.split, "Identical image appears in multiple splits.") }
        hashes[hash] = record.split
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "ScanLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unreadable JPEG: " + url.lastPathComponent]) }
        try require(image.width == record.imageWidth && image.height == record.imageHeight, "Image dimensions do not match metadata.")
    }
    func dataSource(_ split: String) -> MLObjectDetector.DataSource {
        .directoryWithImages(at: root.appendingPathComponent(split), annotationFile: root.appendingPathComponent(split + "/annotations.json"))
    }
    for split in ["training", "validation", "test"] {
        let group = records.filter { $0.split == split }
        let annotations = try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: root.appendingPathComponent(split + "/annotations.json")))
        try require(Set(annotations.map(\.image)).count == annotations.count, "Duplicate annotation image.")
        try require(Set(annotations.map(\.image)) == Set(group.map { "images/" + $0.id.uuidString + ".jpg" }), "Annotation/manifest images differ.")
        let byFilename = Dictionary(uniqueKeysWithValues: group.map { ("images/" + $0.id.uuidString + ".jpg", $0) })
        for annotation in annotations {
            guard let record = byFilename[annotation.image] else { continue }
            if record.kind == "background" { try require(annotation.annotations.isEmpty, "Negative example has a card box.") }
            else {
                try require(annotation.annotations.count == 1, "Each positive image must have exactly one annotated card.")
                let box = annotation.annotations[0], c = box.coordinates
                let expected = record.kind == "back" ? "pokemon_card_back" : "pokemon_card_front"
                try require(["front", "back"].contains(record.kind) && box.label == expected, "Incorrect card class.")
                try require([c.x,c.y,c.width,c.height].allSatisfy(\.isFinite) && c.width > 0 && c.height > 0 && c.x - c.width/2 >= -0.01 && c.y - c.height/2 >= -0.01 && c.x + c.width/2 <= Double(record.imageWidth) + 0.01 && c.y + c.height/2 <= Double(record.imageHeight) + 0.01, "Invalid pixel box.")
            }
        }
        let real = group.filter { $0.source == "camera" }
        print("\(split): \(real.count) real, \(group.count - real.count) generated; fronts \(real.filter { $0.kind == "front" }.count), backs \(real.filter { $0.kind == "back" }.count), non-card scenes \(real.filter { $0.kind == "background" }.count)")
        if !group.isEmpty {
            let frame = try dataSource(split).gatherAnnotatedFileNames()
            try require(frame.rows.count == group.count, "Create ML did not load all \(split) images.")
        }
    }
    print("Integrity checks passed. Manually check that the SAME physical card/scene never crosses splits; a session ID and file hash cannot prove card identity.")
    if args[1] != "--check" {
        for split in ["training", "validation", "test"] {
            let real = records.filter { $0.split == split && $0.source == "camera" }
            for kind in ["front", "back", "background"] {
                try require(real.contains { $0.kind == kind }, "Collect reviewed REAL \(kind) examples for \(split) before training.")
            }
        }
        let output = URL(fileURLWithPath: args[1]).standardizedFileURL
        try require(output.pathExtension == "mlmodel" && !FileManager.default.fileExists(atPath: output.path), "Choose a NEW .mlmodel path; existing files are not overwritten.")
        let parameters = MLObjectDetector.ModelParameters(validation: .dataSource(dataSource("validation")), maxIterations: 2000, algorithm: .transferLearning(.objectPrint(revision: 1)))
        let detector = try MLObjectDetector(trainingData: dataSource("training"), parameters: parameters, annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center))
        print("Validation: " + detector.validationMetrics.description)
        let metrics = detector.evaluation(on: dataSource("test"))
        try require(metrics.isValid, "Test evaluation failed: " + (metrics.error?.localizedDescription ?? "invalid metrics"))
        print("UNSEEN test: " + metrics.description)
        let negatives = records.filter { $0.split == "test" && $0.kind == "background" }
        var falsePositiveScenes = 0
        for record in negatives {
            let detections = try detector.prediction(from: root.appendingPathComponent("test/images/" + record.id.uuidString + ".jpg"))
            if detections.contains(where: { $0.confidence >= 0.7 }) { falsePositiveScenes += 1 }
        }
        print("Test non-card scenes with a false detection at confidence >= 0.70: \(falsePositiveScenes)/\(negatives.count)")
        try detector.write(to: output)
        print("Saved \(output.path). This is NOT automatically installed in TallyDex. Validate on real iPhone video before integration.")
    }
} catch {
    FileHandle.standardError.write(Data(("ScanLab: " + error.localizedDescription + "\n").utf8))
    exit(1)
}
