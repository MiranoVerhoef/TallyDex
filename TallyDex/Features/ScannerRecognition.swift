import Foundation
import Vision
import ImageIO
import CoreML

enum CardScanOCR {
    static func looksLikeCardFront(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ").uppercased()
        let number = !CardScanRanking.fractions(in: lines).isEmpty
        let heading = text.range(of: #"\b(BASIC|STAGE|TRAINER|ENERGY|HP)\b"#, options: .regularExpression) != nil
            || text.range(of: #"\bHP\s*\d{2,3}\b"#, options: .regularExpression) != nil
            || text.range(of: #"\b\d{2,3}\s*HP\b"#, options: .regularExpression) != nil
        let attribution = text.contains("POKÉMON") || text.contains("POKEMON") || text.contains("GAME FREAK") || text.contains("GAMEFREAK")
        return (number && (heading || attribution)) || (heading && attribution)
    }

    static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [String] {
        // Read small collector marks separately instead of letting attack text
        // dominate recognition. Region crops are used only on upright bitmaps.
        var images = [image]
        if orientation == .up {
            for (y, height) in [(0.0, 0.23), (0.75, 0.25)] {
                let rect = CGRect(x: 0, y: Double(image.height) * y,
                                  width: Double(image.width), height: Double(image.height) * height).integral
                if let crop = image.cropping(to: rect), let enlarged = enlarge(crop, width: 1600) { images.append(enlarged) }
            }
        }
        var lines: [String] = []
        for source in images {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.002
            try VNImageRequestHandler(cgImage: source, orientation: orientation).perform([request])
            for observation in request.results ?? [] {
                guard let value = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty, !lines.contains(value) else { continue }
                lines.append(value)
            }
        }
        return lines
    }

    private static func enlarge(_ image: CGImage, width: Int) -> CGImage? {
        let height = max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

struct CardScanGuide: Sendable {
    let viewport: CGSize
    let rectangle: CGRect

    func region(in image: CGSize) -> CGRect {
        guard viewport.width > 0, viewport.height > 0, image.width > 0, image.height > 0 else { return .zero }
        let scale = max(viewport.width / image.width, viewport.height / image.height)
        let width = image.width * scale, height = image.height * scale
        let x = (viewport.width - width) / 2, y = (viewport.height - height) / 2
        return CGRect(x: (rectangle.minX - x) / width, y: 1 - (rectangle.maxY - y) / height,
                      width: rectangle.width / width, height: rectangle.height / height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func contains(_ card: CGRect, in region: CGRect) -> Bool {
        guard card.width > 0, card.height > 0, !region.isEmpty else { return false }
        let overlap = card.intersection(region.insetBy(dx: -0.015, dy: -0.015))
        return !overlap.isNull && overlap.width * overlap.height / (card.width * card.height) >= 0.95
    }
}

struct CardScanReference: Codable, Sendable {
    let id: String
    let name: String
    let localID: String
    let setID: String
    let setName: String
    let officialCount: Int
    let codes: [String]
    let releaseYear: Int?

    init(id: String, name: String, localID: String, setID: String, setName: String,
         officialCount: Int, codes: [String], releaseYear: Int? = nil) {
        self.id = id; self.name = name; self.localID = localID; self.setID = setID; self.setName = setName
        self.officialCount = officialCount; self.codes = codes; self.releaseYear = releaseYear
    }
}

struct CardScanRankedMatch: Equatable, Sendable {
    let id: String
    let score: Double
    var percentage: Int { min(99, max(1, Int((score * 100).rounded()))) }
}

struct CardScanReferenceIndex: Sendable {
    private var byNumber: [String: [CardScanReference]] = [:]
    private var byName: [String: [CardScanReference]] = [:]
    private var energies: [CardScanReference] = []

    init(_ references: [CardScanReference]) {
        for reference in references {
            if reference.name.localizedCaseInsensitiveContains("energy") { energies.append(reference) }
            byNumber[CardScanRanking.numberKey(reference.localID), default: []].append(reference)
            if let first = Self.words(reference.name).first { byName[first, default: []].append(reference) }
        }
    }

    func candidates(lines: [String]) -> [CardScanReference] {
        var candidates: [String: CardScanReference] = [:]
        if CardScanRanking.numbers(in: lines).isEmpty && lines.contains(where: { $0.uppercased().trimmingCharacters(in: .whitespaces).hasPrefix("ENERGY") }) {
            for reference in energies { candidates[reference.id] = reference }
        }
        for number in CardScanRanking.numbers(in: lines) {
            for reference in byNumber[number] ?? [] { candidates[reference.id] = reference }
        }
        for name in CardTextRecognizer.nameCandidates(in: lines) {
            // A name may include a leading OCR artefact. Consider its first few
            // words, while matching still checks the complete recognised name.
            for word in Self.words(name).prefix(3) {
                for reference in byName[word] ?? [] { candidates[reference.id] = reference }
            }
        }
        return Array(candidates.values)
    }

    private static func words(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

enum CardScanRanking {
    static func numberKey(_ value: String) -> String {
        let clean = value.uppercased().filter { $0.isLetter || $0.isNumber }
        let letters = clean.prefix(while: \.isLetter)
        let rest = clean.dropFirst(letters.count)
        let digits = rest.prefix(while: \.isNumber)
        return String(letters) + (Int(digits).map(String.init) ?? String(digits)) + rest.dropFirst(digits.count)
    }

    static func fractions(in lines: [String]) -> [(number: String, total: String)] {
        let expression = try! NSRegularExpression(pattern: #"\b([A-Z]{0,3}\d{1,3}[A-Z]?)\s*/\s*([A-Z]{0,3}\d{1,3})\b"#)
        return lines.flatMap { line in
            let text = line.uppercased()
                .replacingOccurrences(of: #"\b5V(?=\d)"#, with: "SV", options: .regularExpression)
            return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> (number: String, total: String)? in
                guard let left = Range(match.range(at: 1), in: text), let right = Range(match.range(at: 2), in: text) else { return nil }
                return (numberKey(String(text[left])), numberKey(String(text[right])))
            }
        }
    }

    static func numbers(in lines: [String]) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"\b(?:SV|SH|TG|GG|RC|BW|XY|SM|SWSH)\d{1,3}\b"#)
        return fractions(in: lines).map(\.number) + lines.flatMap { line in
            let text = line.uppercased()
            return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range, in: text).map { numberKey(String(text[$0])) }
            }
        }
    }

    static func rank(_ references: [CardScanReference], lines: [String], limit: Int = 10) -> [CardScanRankedMatch] {
        let names = CardTextRecognizer.nameCandidates(in: lines)
        let normalizedNames = names.map(CardTextRecognizer.normalizedName)
        let numbers = fractions(in: lines)
        let localNumbers = Set(self.numbers(in: lines))
        let text = lines.joined(separator: " ")
        let expression = try! NSRegularExpression(pattern: #"(?:19|20)\d{2}"#)
        let years = Set(expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).flatMap { Int(text[$0]) }
        })
        let identifiers = Set(CardTextRecognizer.setAndCollectorCandidates(in: lines).map { $0.uppercased() })
        let unnamedEnergy = localNumbers.isEmpty && lines.contains { $0.uppercased().trimmingCharacters(in: .whitespaces).hasPrefix("ENERGY") }
        var scored: [String: CardScanRankedMatch] = [:]
        for reference in references {
            let key = numberKey(reference.localID)
            let localMatch = localNumbers.contains(key)
            let exactFraction = numbers.contains {
                $0.number == key && Int($0.total.filter(\.isNumber)) == reference.officialCount
            }
            let codeMatch = reference.codes.contains { code in
                identifiers.contains { identifier in
                    let parts = identifier.split(separator: " ")
                    return parts.count == 2 && parts[0] == code.uppercased() && numberKey(String(parts[1])) == key
                }
            }
            // Cheap lexical prefilter before edit-distance matching across the index.
            let normalizedName = CardTextRecognizer.normalizedName(reference.name)
            let firstWord = normalizedName.split(separator: " ").first.map(String.init) ?? normalizedName
            if !localMatch && !codeMatch && !(unnamedEnergy && reference.name.localizedCaseInsensitiveContains("energy")) && !normalizedNames.contains(where: { normalized in
                return normalized.contains(firstWord) || normalizedName.contains(normalized)
            }) { continue }
            let nameScore = CardTextRecognizer.nameMatchScore(reference.name, normalizedCandidates: normalizedNames)
            let score: Double
            if codeMatch && (nameScore >= 0.65 || names.isEmpty) {
                score = 0.82 + 0.16 * nameScore
            } else if exactFraction && nameScore >= 0.70 {
                score = 0.76 + 0.20 * nameScore
            } else if exactFraction {
                score = 0.65
            } else if localMatch && nameScore >= 0.85 {
                score = 0.46 + 0.22 * nameScore
            } else if nameScore >= 0.72 {
                score = 0.20 + 0.40 * nameScore
            } else if unnamedEnergy && reference.name.localizedCaseInsensitiveContains("energy") {
                score = 0.28
            } else { continue }
            let adjusted = min(0.99, score + (reference.releaseYear.map { years.contains($0) ? 0.08 : 0 } ?? 0))
            let match = CardScanRankedMatch(id: reference.id, score: adjusted)
            if adjusted > (scored[reference.id]?.score ?? 0) { scored[reference.id] = match }
        }
        return Array(scored.values.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }.prefix(max(0, limit)))
    }
}

enum CardScanVisualComparison {
    static func featurePrint(_ image: CGImage) throws -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        #if targetEnvironment(simulator)
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        guard let result = request.results?.first, result.data.contains(where: { $0 != 0 }) else { return nil }
        return result
    }

    static func rerank(_ matches: [CardScanRankedMatch], query: CGImage,
                       references: [(id: String, image: CGImage)]) throws -> [CardScanRankedMatch] {
        let queryPrint = try? featurePrint(query)
        let queryPixels = pixels(query)
        var similarities: [String: Double] = [:]
        var exactArtwork = Set<String>()
        for reference in references {
            guard let queryPixels, let otherPixels = pixels(reference.image) else { continue }
            let difference = zip(queryPixels, otherPixels).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(queryPixels.count)
            let pixelSimilarity = 1 / (1 + difference * 5)
            var similarity = pixelSimilarity
            if let queryPrint, let other = try? featurePrint(reference.image), queryPrint.data != other.data {
                var distance: Float = 0
                if (try? queryPrint.computeDistance(&distance, to: other)) != nil, distance.isFinite, distance >= 0 {
                    similarity = 0.7 / (1 + Double(distance)) + 0.3 * pixelSimilarity
                }
            }
            // A coarse thumbnail cannot prove which reprint it is. Only
            // identical decoded artwork receives the exact-reference boost.
            if query.width == reference.image.width, query.height == reference.image.height,
               let left = query.dataProvider?.data, let right = reference.image.dataProvider?.data,
               CFEqual(left, right) { exactArtwork.insert(reference.id) }
            similarities[reference.id] = similarity
        }
        return matches.map { match in
            guard let visual = similarities[match.id] else { return match }
            return CardScanRankedMatch(id: match.id, score: exactArtwork.contains(match.id)
                ? 0.99 : min(0.99, match.score * 0.65 + visual * 0.35))
        }.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }

    private static func pixels(_ image: CGImage) -> [Double]? {
        let width = 24, height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return bytes.enumerated().compactMap { $0.offset % 4 == 3 ? nil : Double($0.element) / 255 }
    }

    static func isUseful(_ matches: [CardScanRankedMatch]) -> Bool {
        guard let first = matches.first else { return false }
        return first.score < 0.85 || matches.dropFirst().contains(where: { $0.score >= 0.65 })
            || (matches.count > 1 && first.score - matches[1].score < 0.06)
    }
}

// Shared by the app and the reproducible scanner benchmark.
enum CardTextRecognizer {
    static func collectorNumber(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
            .uppercased()
            .replacingOccurrences(of: "O", with: "0")
        guard let match = joined.range(of: #"\b\d{1,3}\s*/\s*\d{1,3}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(joined[match]).replacingOccurrences(of: " ", with: "")
    }

    static func setAndCollectorCandidates(in lines: [String]) -> [String] {
        let pattern = #"\b([A-Z0-9.]{2,8})\s+(?:EN\s+|US\s+)?(\d{1,3})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let adjacentPairs = zip(lines, lines.dropFirst()).map { "\($0.0) \($0.1)" }
        let segments = (lines + adjacentPairs)
            .sorted { left, right in
                (left.contains("/") ? 0 : 1) < (right.contains("/") ? 0 : 1)
            }
        var candidates: [String] = []
        for segment in segments {
            let text = segment.uppercased()
                .replacingOccurrences(of: #"[^A-Z0-9.]+"#, with: " ", options: .regularExpression)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in expression.matches(in: text, range: range) {
                guard let codeRange = Range(match.range(at: 1), in: text),
                      let numberRange = Range(match.range(at: 2), in: text) else { continue }
                let scannedCode = String(text[codeRange])
                let number = String(text[numberRange])
                // Set marks often print the language directly beside the code, such
                // as "SVE EN". Vision can collapse that to "SVEEN".
                var possibleCodes = [scannedCode]
                if scannedCode.count > 4,
                   scannedCode.hasSuffix("EN") || scannedCode.hasSuffix("US") {
                    possibleCodes.append(String(scannedCode.dropLast(2)))
                } else if scannedCode.count == 4 {
                    // On tiny set marks Vision can turn the adjacent EN language
                    // mark into one arbitrary letter (for example CRI EN → CRIM).
                    possibleCodes.append(String(scannedCode.dropLast()))
                }
                for code in possibleCodes where code.filter(\.isLetter).count >= 2
                    || (code.contains(where: \.isLetter) && code.contains(where: \.isNumber) && code.count <= 5) {
                    guard !["BASIC", "STAGE", "TRAINER", "ENERGY", "POKEMON", "ILLUS"].contains(code) else {
                        continue
                    }
                    let candidate = "\(code) \(number)"
                    if !candidates.contains(candidate) { candidates.append(candidate) }
                }
            }
        }
        return candidates
    }

    static func nameCandidates(in lines: [String]) -> [String] {
        let ignored = [
            "basic", "stage", "trainer", "supporter", "energy", "pokemon",
            "weakness", "resistance", "retreat", "illus", "hp",
        ]
        return lines.compactMap { line in
            var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = candidate.replacingOccurrences(
                of: #"^(?:BASIC|STAGE\s*\d+)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            candidate = candidate.replacingOccurrences(
                of: #"\s+HP\s*\d+.*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            candidate = candidate.replacingOccurrences(
                of: #"\s+[-–—•·]?\s*(?:HP\s*)?\d{2,3}\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = candidate.lowercased()
            guard candidate.count >= 3,
                  candidate.count <= 45,
                  candidate.split(whereSeparator: \Character.isWhitespace).count <= 7,
                  candidate.rangeOfCharacter(from: .letters) != nil,
                  !ignored.contains(where: { lowercased == $0 || lowercased.hasPrefix("\($0) ") }) else {
                return nil
            }
            return candidate
        }
    }

    static func nameLooksLikeCard(_ cardName: String, candidates: [String]) -> Bool {
        nameMatchScore(cardName, candidates: candidates) >= 0.72
    }

    static func nameMatchScore(_ cardName: String, candidates: [String]) -> Double {
        nameMatchScore(cardName, normalizedCandidates: candidates.map(searchableName))
    }

    static func normalizedName(_ value: String) -> String { searchableName(value) }

    static func nameMatchScore(_ cardName: String, normalizedCandidates: [String]) -> Double {
        let expected = searchableName(cardName)
        guard expected.count >= 3 else { return 0 }
        return normalizedCandidates.reduce(0) { best, recognized in
            if best == 1 { return best }
            guard recognized.count >= 3 else { return best }
            if recognized == expected
                || recognized.hasPrefix(expected + " ")
                || recognized.hasSuffix(" " + expected)
                || recognized.contains(" " + expected + " ") {
                return 1
            }
            let distance = levenshteinDistance(Array(expected), Array(recognized))
            let length = max(expected.count, recognized.count)
            let characterScore = length == 0 ? 0 : 1 - Double(distance) / Double(length)

            let expectedWords = expected.split(separator: " ").map(String.init)
            let recognizedWords = recognized.split(separator: " ").map(String.init)
            let matchedWords = expectedWords.filter { expectedWord in
                recognizedWords.contains { recognizedWord in
                    let wordDistance = levenshteinDistance(Array(expectedWord), Array(recognizedWord))
                    let wordLength = max(expectedWord.count, recognizedWord.count)
                    return wordLength > 0 && 1 - Double(wordDistance) / Double(wordLength) >= 0.67
                }
            }.count
            let wordScore = Double(matchedWords) / Double(max(1, expectedWords.count))
            return max(best, characterScore * 0.72 + wordScore * 0.28)
        }
    }

    static func fallbackNameQueries(in lines: [String]) -> [String] {
        let ignoredWords: Set<String> = [
            "ability", "attack", "basic", "during", "energy", "evolves", "flip",
            "heads", "illus", "once", "pokemon", "resistance", "retreat", "search",
            "stage", "trainer", "weakness", "your",
        ]
        var queries: [String] = []
        for candidate in nameCandidates(in: lines).prefix(8) {
            guard let word = candidate.split(whereSeparator: \Character.isWhitespace).first else { continue }
            let cleaned = String(word)
                .replacingOccurrences(of: #"[^A-Za-z0-9'’-]+"#, with: "", options: .regularExpression)
            let normalized = searchableName(cleaned)
            guard normalized.count >= 4, !ignoredWords.contains(normalized),
                  !queries.contains(where: { searchableName($0) == normalized }) else { continue }
            queries.append(cleaned)
        }
        return queries
    }

    private static func levenshteinDistance(_ left: [Character], _ right: [Character]) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func searchableName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
