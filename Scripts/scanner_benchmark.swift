import Foundation
import Vision
import ImageIO
import CoreGraphics

struct BenchmarkImage: Decodable {
    let id: String
    let image: String?
    let split: String?
}

@main struct ScannerBenchmark {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let enhanced = CommandLine.arguments.contains("--enhanced")
        let visual = CommandLine.arguments.contains("--visual")
        let prefix = enhanced ? "enhanced" : "baseline"
        let decoder = JSONDecoder()
        let references = try decoder.decode([CardScanReference].self, from: Data(contentsOf: root.appendingPathComponent("references.json")))
        let manifest = try decoder.decode([BenchmarkImage].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json"))).filter { $0.image != nil }
        let cacheURL = root.appendingPathComponent("ocr-\(prefix).json")
        var cache = (try? decoder.decode([String: [String]].self, from: Data(contentsOf: cacheURL))) ?? [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (index, record) in manifest.enumerated() where cache[record.id] == nil {
            let lines: [String] = try autoreleasepool {
                let path = root.appendingPathComponent(record.image!)
                guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
                if enhanced { return try CardScanOCR.recognize(image) }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }
            cache[record.id] = lines
            if index % 10 == 0 || index == manifest.count - 1 {
                try encoder.encode(cache).write(to: cacheURL, options: .atomic)
                print("OCR \(index + 1)/\(manifest.count)")
                fflush(stdout)
            }
        }
        var rows: [[String: Any]] = []
        for record in manifest {
            let lines = cache[record.id] ?? []
            let names = CardTextRecognizer.nameCandidates(in: lines)
            var candidates: [CardScanReference] = []
            if let fraction = CardTextRecognizer.collectorNumber(in: lines) {
                let parts = fraction.split(separator: "/")
                candidates = references.filter { Int($0.localID) == Int(parts[0]) && $0.officialCount == Int(parts[1]) }
                    .filter { CardTextRecognizer.nameLooksLikeCard($0.name, candidates: names) }
            }
            if candidates.isEmpty {
                for name in names.prefix(8) {
                    candidates = references.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                    if !candidates.isEmpty { break }
                }
            }
            let ids = candidates.map(\.id)
            rows.append(["id": record.id, "split": record.split ?? "", "candidates": ids,
                         "correct": ids.count == 1 && ids.first == record.id, "ambiguous": ids.count > 1,
                         "number": CardTextRecognizer.collectorNumber(in: lines) ?? "", "names": names])
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: root.appendingPathComponent("\(prefix)-results.json"))
        print("BASELINE clean \(rows.count); exact single correct \(rows.filter { $0["correct"] as? Bool == true }.count); ambiguous \(rows.filter { $0["ambiguous"] as? Bool == true }.count)")
        var rankedRows: [[String: Any]] = []
        let referenceIndex = CardScanReferenceIndex(references)
        let rawReferences = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("references.json"))) as! [[String: Any]]
        let imageURLs = Dictionary(uniqueKeysWithValues: rawReferences.compactMap { row -> (String, String)? in
            guard let id = row["id"] as? String, let image = row["image"] as? String else { return nil }
            return (id, image)
        })
        for (index, record) in manifest.enumerated() {
            let lines = cache[record.id] ?? []
            var ranked = CardScanRanking.rank(referenceIndex.candidates(lines: lines), lines: lines, limit: 16)
            if visual && CardScanVisualComparison.isUseful(ranked) {
                try autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent(record.image!) as CFURL, nil),
                          let query = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
                    var images: [(id: String, image: CGImage)] = []
                    for match in ranked {
                        let path = root.appendingPathComponent("images/" + match.id + ".webp")
                        if !FileManager.default.fileExists(atPath: path.path), let address = imageURLs[match.id],
                           let url = URL(string: address + "/high.webp"), let data = try? Data(contentsOf: url) {
                            try data.write(to: path, options: .atomic)
                        }
                        if let source = CGImageSourceCreateWithURL(path as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                            images.append((match.id, image))
                        }
                    }
                    ranked = try CardScanVisualComparison.rerank(ranked, query: query, references: images)
                }
            }
            let position = ranked.firstIndex { $0.id == record.id }.map { $0 + 1 } ?? 0
            rankedRows.append(["id": record.id, "split": record.split ?? "", "rank": position,
                "candidates": ranked.map { ["id": $0.id, "score": $0.percentage] }])
            if index % 30 == 0 { print("Ranked \(index + 1)/\(manifest.count)"); fflush(stdout) }
        }
        try JSONSerialization.data(withJSONObject: rankedRows, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent("\(visual ? "visual" : prefix)-ranked-results.json"))
        for split in ["development", "holdout"] {
            let group = rankedRows.filter { $0["split"] as? String == split }
            let top1 = group.filter { $0["rank"] as? Int == 1 }.count
            let top3 = group.filter { (1...3).contains($0["rank"] as? Int ?? 0) }.count
            print("\(split): \(group.count), top1 \(top1), top3 \(top3)")
        }
    }
}
