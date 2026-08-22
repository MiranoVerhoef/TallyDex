import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate_rarity_metadata.swift <tcgdex-data-directory> <output.json>")
}

let fileManager = FileManager.default
let dataDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let setIDPattern = try NSRegularExpression(pattern: #"\bid:\s*["']([^"']+)["']"#)
let rarityPattern = try NSRegularExpression(pattern: #"\brarity:\s*["']([^"']+)["']"#)

func firstCapture(_ pattern: NSRegularExpression, in source: String) -> String? {
    let range = NSRange(source.startIndex..., in: source)
    guard let match = pattern.firstMatch(in: source, range: range),
          let captureRange = Range(match.range(at: 1), in: source) else {
        return nil
    }
    return String(source[captureRange])
}

var metadata: [String: [[String: Any]]] = [:]
guard let enumerator = fileManager.enumerator(
    at: dataDirectory,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    fatalError("Could not enumerate \(dataDirectory.path)")
}

for case let setFile as URL in enumerator where setFile.pathExtension == "ts" {
    let cardDirectory = setFile.deletingPathExtension()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: cardDirectory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        continue
    }

    let source = try String(contentsOf: setFile, encoding: .utf8)
    guard source.contains(": Set = {"),
          let setID = firstCapture(setIDPattern, in: source) else {
        continue
    }

    let cardFiles = try fileManager.contentsOfDirectory(
        at: cardDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    var counts: [String: Int] = [:]
    for cardFile in cardFiles where cardFile.pathExtension == "ts" {
        let cardSource = try String(contentsOf: cardFile, encoding: .utf8)
        if let rarity = firstCapture(rarityPattern, in: cardSource) {
            counts[rarity, default: 0] += 1
        }
    }

    metadata[setID] = counts
        .map { ["rarity": $0.key, "count": $0.value] as [String: Any] }
        .sorted {
            ($0["rarity"] as? String ?? "") < ($1["rarity"] as? String ?? "")
        }
}

let data = try JSONSerialization.data(
    withJSONObject: metadata,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
try data.write(to: outputURL, options: .atomic)
print("Wrote rarity metadata for \(metadata.count) sets to \(outputURL.path)")
