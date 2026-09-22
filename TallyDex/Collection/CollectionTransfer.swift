import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let tallyDexCollection = UTType(
        exportedAs: PortableCollectionDocument.formatIdentifier,
        conformingTo: .json
    )
}

struct PortableCollectionDocument: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.miranoverhoef.tallydex.collection"
    static let currentSchemaVersion = 6

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let ownership: [OwnershipRecord]
    let setPreferences: [SetPreferenceRecord]
    let folders: [FolderRecord]
    let cardMetadata: [CardMetadataRecord]
    let exactOwnership: [ExactOwnershipRecord]
    let binderPlans: [BinderPlan]
    let priceChartingMappings: [PriceChartingProductMapping]

    init(
        format: String,
        schemaVersion: Int,
        exportedAt: Date,
        appVersion: String,
        ownership: [OwnershipRecord],
        setPreferences: [SetPreferenceRecord],
        folders: [FolderRecord],
        cardMetadata: [CardMetadataRecord],
        exactOwnership: [ExactOwnershipRecord] = [],
        binderPlans: [BinderPlan] = [],
        priceChartingMappings: [PriceChartingProductMapping] = []
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.ownership = ownership
        self.setPreferences = setPreferences
        self.folders = folders
        self.cardMetadata = cardMetadata
        self.exactOwnership = exactOwnership
        self.binderPlans = binderPlans
        self.priceChartingMappings = priceChartingMappings
    }

    private enum CodingKeys: String, CodingKey {
        case format, schemaVersion, exportedAt, appVersion, ownership
        case setPreferences, folders, cardMetadata, exactOwnership, binderPlans, priceChartingMappings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        ownership = try values.decode([OwnershipRecord].self, forKey: .ownership)
        setPreferences = try values.decode([SetPreferenceRecord].self, forKey: .setPreferences)
        folders = try values.decode([FolderRecord].self, forKey: .folders)
        cardMetadata = try values.decode([CardMetadataRecord].self, forKey: .cardMetadata)
        exactOwnership = try values.decodeIfPresent([ExactOwnershipRecord].self, forKey: .exactOwnership) ?? []
        binderPlans = try values.decodeIfPresent([BinderPlan].self, forKey: .binderPlans) ?? []
        priceChartingMappings = try values.decodeIfPresent([PriceChartingProductMapping].self, forKey: .priceChartingMappings) ?? []
    }

    struct OwnershipRecord: Codable, Equatable, Sendable {
        let cardID: String
        let variant: CatalogVariantKind
        let quantity: Int
        let updatedAt: Date
    }

    struct ExactOwnershipRecord: Codable, Equatable, Sendable {
        let cardID: String
        let printingID: String
        let variant: CatalogVariantKind
        let quantity: Int
        let updatedAt: Date
    }

    struct SetPreferenceRecord: Codable, Equatable, Sendable {
        let setID: String
        let status: SetTrackingStatus
        let goal: CollectionGoal
        let includedVariants: [CatalogVariantKind]
        let includesSecretCards: Bool
        let updatedAt: Date
    }

    struct FolderRecord: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let cardNameQuery: String
        let pokemonName: String?
        let pokemonRules: [PokemonCollectionRule]?
        let displayMode: CustomCollectionFolderDisplayMode
        let iconName: String?
        let coverCardID: String?
        let createdAt: Date
        let updatedAt: Date

        init(
            id: UUID,
            name: String,
            cardNameQuery: String,
            pokemonName: String? = nil,
            pokemonRules: [PokemonCollectionRule]? = nil,
            displayMode: CustomCollectionFolderDisplayMode,
            iconName: String? = nil,
            coverCardID: String? = nil,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.cardNameQuery = cardNameQuery
            self.pokemonName = pokemonName
            self.pokemonRules = pokemonRules
            self.displayMode = displayMode
            self.iconName = iconName
            self.coverCardID = coverCardID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    struct CardMetadataRecord: Codable, Equatable, Sendable {
        let cardID: String
        let isWishlisted: Bool
        let notes: String
        let updatedAt: Date
    }
}

struct PriceChartingProductMapping: Codable, Equatable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    /// Columns from a user-supplied PriceCharting collection export, in its documented order.
    let fields: [String]
    let updatedAt: Date

    var productID: String { fields.first ?? "" }
    var key: String { "\(cardID)|\(variant.rawValue)" }
}

enum CollectionImportMode: String, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .merge: "Merge"
        case .replace: "Replace"
        }
    }
}

struct CollectionImportPreview: Equatable, Sendable {
    let additions: Int
    let changes: Int
    let conflicts: Int
    let skipped: Int
    let removals: Int
    let items: [CollectionImportPreviewItem]

    var importedCount: Int { additions + changes }
    var hasChanges: Bool { importedCount + removals > 0 }
}

struct CollectionImportPreviewItem: Identifiable, Equatable, Sendable {
    enum Action: String, Equatable, Sendable {
        case addition
        case change
        case conflict
        case removal
    }

    let id: String
    let action: Action
    let category: String
    let title: String
    let detail: String
}

struct PreparedCollectionImport: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let document: PortableCollectionDocument
    let mergePreview: CollectionImportPreview
    let replacePreview: CollectionImportPreview
}

struct PriceChartingCSVRow: Equatable, Identifiable, Sendable {
    let rowNumber: Int
    let productID: String
    let productName: String
    let consoleName: String
    let quantity: Int
    let fields: [String]

    var includeString: String { fields[4] }
    var gradingCompany: String { fields[13] }

    var id: Int { rowNumber }
}

struct PriceChartingImportIssue: Equatable, Identifiable, Sendable {
    let rowNumber: Int
    let productName: String
    let consoleName: String
    let reason: String

    var id: String { "\(rowNumber)|\(productName)|\(reason)" }
}

struct PriceChartingResolvedMatch: Equatable, Sendable {
    let card: CatalogCard
    let setName: String
    let variant: CatalogVariantKind
    let quantity: Int
    let sourceFields: [String]
}

struct PreparedPriceChartingImport: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let sourceRowCount: Int
    let matches: [PriceChartingResolvedMatch]
    let issues: [PriceChartingImportIssue]
    let document: PortableCollectionDocument
    let preview: CollectionImportPreview
}

enum PriceChartingTransferError: Error, Equatable {
    case invalidCSV
    case missingColumns([String])
    case tooManyRows(maximum: Int)
    case noRows
}

enum PriceChartingTransferCodec {
    static let maximumRowCount = 5_000
    static let headers = [
        "id", "product-name", "console-name", "price-in-pennies", "include-string",
        "condition-string", "condition-id", "sku", "notes", "cost-basis-in-pennies",
        "quantity", "date-entered", "date-purchased", "grading-company",
        "grading-cert-id", "folder",
    ]

    static func decode(_ data: Data) throws -> [PriceChartingCSVRow] {
        guard data.count <= CollectionTransferCodec.maximumImportByteCount,
              let source = String(data: data, encoding: .utf8),
              !source.contains("\0") else {
            throw PriceChartingTransferError.invalidCSV
        }
        // Swift treats CRLF as one Character; normalize it before the character parser.
        let table = try parseCSV(source.replacingOccurrences(of: "\r\n", with: "\n"))
        guard let rawHeader = table.first else { throw PriceChartingTransferError.noRows }
        let header = rawHeader.enumerated().reduce(into: [String: Int]()) { result, value in
            let cleaned = value.element
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{feff}", with: "")
                .lowercased()
            if !cleaned.isEmpty, result[cleaned] == nil { result[cleaned] = value.offset }
        }
        let required = ["id", "product-name", "console-name", "quantity"]
        let missing = required.filter { header[$0] == nil }
        guard missing.isEmpty else { throw PriceChartingTransferError.missingColumns(missing) }

        let body = table.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard !body.isEmpty else { throw PriceChartingTransferError.noRows }
        guard body.count <= maximumRowCount else {
            throw PriceChartingTransferError.tooManyRows(maximum: maximumRowCount)
        }

        func value(_ key: String, in row: [String]) -> String {
            guard let index = header[key], row.indices.contains(index) else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return body.enumerated().map { offset, row in
            PriceChartingCSVRow(
                rowNumber: offset + 2,
                productID: value("id", in: row),
                productName: value("product-name", in: row),
                consoleName: value("console-name", in: row),
                quantity: Int(value("quantity", in: row)) ?? 0,
                fields: headers.map { value($0, in: row) }
            )
        }
    }

    static func csvExport(
        ownership: [CollectionVariantEntry],
        mappings: [PriceChartingProductMapping]
    ) -> (data: Data, mapped: Int, unmapped: Int) {
        let mappingByKey = Dictionary(uniqueKeysWithValues: mappings.map { ($0.key, $0) })
        var rows = [headers]
        var unmatched = 0
        for entry in ownership.sorted(by: ownershipOrder) where entry.quantity > 0 {
            let key = "\(entry.cardID)|\(entry.variant.rawValue)"
            guard let mapping = mappingByKey[key], mapping.fields.count == headers.count else {
                unmatched += 1
                continue
            }
            var fields = mapping.fields
            fields[10] = String(entry.quantity)
            rows.append(fields)
        }
        let output = rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return (Data(output.utf8), rows.count - 1, unmatched)
    }

    static func textImport(
        ownership: [CollectionVariantEntry],
        cards: [CatalogCardSearchResult]
    ) -> Data {
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.card.id, $0) })
        var lines: [String] = []
        for entry in ownership.sorted(by: ownershipOrder) {
            guard entry.quantity > 0, let result = cardsByID[entry.cardID] else { continue }
            let variant = exportVariantLabel(entry.variant).map { " [\($0)]" } ?? ""
            let line = "\(result.card.name)\(variant) #\(result.card.localID) Pokemon \(result.setName)"
            lines.append(contentsOf: repeatElement(line, count: entry.quantity))
        }
        return Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
    }

    static func productComponents(_ value: String) -> (name: String, number: String, variant: String?)? {
        guard let numberSeparator = value.range(of: " #", options: .backwards) else { return nil }
        var namePart = String(value[..<numberSeparator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let number = String(value[numberSeparator.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !namePart.isEmpty, !number.isEmpty else { return nil }

        var variant: String?
        if namePart.hasSuffix("]"),
           let opening = namePart.range(of: " [", options: .backwards) {
            variant = String(namePart[opening.upperBound..<namePart.index(before: namePart.endIndex)])
            namePart = String(namePart[..<opening.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (namePart, number, variant)
    }

    static func variant(named value: String) -> CatalogVariantKind? {
        switch normalized(value) {
        case "normal", "unlimited": .normal
        case "holo", "holofoil": .holo
        case "reverseholo", "reverseholofoil": .reverseHolo
        case "1stedition", "firstedition": .firstEdition
        case "prerelease", "pre release": .prerelease
        case "staff", "prereleasestaff": .prereleaseStaff
        case "jumbo", "oversized": .jumbo
        default: nil
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func normalizedSetName(_ value: String) -> String {
        var result = normalized(value)
        if result.hasPrefix("pokemontcg") { result.removeFirst("pokemontcg".count) }
        else if result.hasPrefix("pokemon") { result.removeFirst("pokemon".count) }
        return result
    }

    static func normalizedCollectorNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let value = Int(trimmed) { return String(value) }
        return normalized(trimmed)
    }

    private static func exportVariantLabel(_ variant: CatalogVariantKind) -> String? {
        switch variant {
        case .normal: nil
        case .reverseHolo: "Reverse Holo"
        case .holo: "Holo"
        case .firstEdition: "1st Edition"
        case .watermarkedPromo: "Promo"
        case .prerelease: "Prerelease"
        case .prereleaseStaff: "Prerelease Staff"
        case .trickOrTrade: "Trick or Trade"
        case .jumbo: "Jumbo"
        }
    }

    private static func ownershipOrder(_ left: CollectionVariantEntry, _ right: CollectionVariantEntry) -> Bool {
        if left.cardID != right.cardID { return left.cardID.localizedStandardCompare(right.cardID) == .orderedAscending }
        return left.variant.rawValue < right.variant.rawValue
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ source: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = source.startIndex

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < source.endIndex {
            let character = source[index]
            if quoted {
                if character == "\"" {
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    quoted = true
                case ",":
                    finishField()
                case "\n":
                    finishRow()
                case "\r":
                    let next = source.index(after: index)
                    if next >= source.endIndex || source[next] != "\n" { finishRow() }
                default:
                    field.append(character)
                }
            }
            index = source.index(after: index)
        }
        guard !quoted else { throw PriceChartingTransferError.invalidCSV }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }
}

@MainActor
enum PriceChartingImportResolver {
    static func prepare(
        data: Data,
        filename: String,
        catalogStore: CatalogStore,
        collectionStore: CollectionStore
    ) async throws -> PreparedPriceChartingImport {
        let rows = try PriceChartingTransferCodec.decode(data)
        let sets = catalogStore.groups.flatMap(\.sets)
        var cardsBySetID: [String: [CatalogCard]] = [:]
        var provisional: [(PriceChartingCSVRow, CatalogCard, String, String?)] = []
        var issues: [PriceChartingImportIssue] = []

        for row in rows {
            guard row.quantity > 0 else {
                issues.append(issue(row, "Quantity must be at least 1."))
                continue
            }
            guard !row.productID.isEmpty,
                  row.productID.allSatisfy(\.isNumber) else {
                issues.append(issue(row, "A PriceCharting product ID is required."))
                continue
            }
            guard PriceChartingTransferCodec.normalized(row.includeString) == "ungraded",
                  row.gradingCompany.isEmpty else {
                issues.append(issue(row, "Graded cards need manual review because TallyDex does not track grades."))
                continue
            }
            guard let product = PriceChartingTransferCodec.productComponents(row.productName) else {
                issues.append(issue(row, "The product name has no usable collector number."))
                continue
            }
            let setKey = PriceChartingTransferCodec.normalizedSetName(row.consoleName)
            let candidateSets = sets.filter { set in
                PriceChartingTransferCodec.normalizedSetName(set.name) == setKey
                    || PriceChartingTransferCodec.normalized(set.id) == setKey
                    || set.abbreviation.map(PriceChartingTransferCodec.normalizedSetName) == setKey
            }
            guard !candidateSets.isEmpty else {
                issues.append(issue(row, "No exact TCGdex set match was found."))
                continue
            }

            var cardMatches: [(CatalogCard, String)] = []
            for set in candidateSets {
                let cards: [CatalogCard]
                if let cached = cardsBySetID[set.id] {
                    cards = cached
                } else {
                    cards = try await catalogStore.cards(for: set)
                    cardsBySetID[set.id] = cards
                }
                cardMatches.append(contentsOf: cards.compactMap { card in
                    guard PriceChartingTransferCodec.normalizedCollectorNumber(card.localID)
                            == PriceChartingTransferCodec.normalizedCollectorNumber(product.number),
                          PriceChartingTransferCodec.normalized(card.name)
                            == PriceChartingTransferCodec.normalized(product.name) else { return nil }
                    return (card, set.name)
                })
            }
            guard cardMatches.count == 1, let match = cardMatches.first else {
                issues.append(issue(
                    row,
                    cardMatches.isEmpty
                        ? "No exact card name and collector-number match was found."
                        : "More than one exact card match was found."
                ))
                continue
            }
            provisional.append((row, match.0, match.1, product.variant))
        }

        let uniqueCards = Dictionary(
            provisional.map { ($0.1.id, $0.1) },
            uniquingKeysWith: { first, _ in first }
        ).values.map { $0 }
        let variantsByCardID = await catalogStore.prepareVariants(for: uniqueCards)
        var grouped: [String: PriceChartingResolvedMatch] = [:]

        for (row, card, setName, variantName) in provisional {
            let available = variantsByCardID[card.id] ?? []
            let variant: CatalogVariantKind?
            if let variantName {
                guard let parsed = PriceChartingTransferCodec.variant(named: variantName) else {
                    issues.append(issue(row, "The printing label “\(variantName)” is not supported."))
                    continue
                }
                variant = available.contains(parsed) ? parsed : nil
            } else if available.contains(.normal) {
                variant = .normal
            } else if available.contains(.holo) {
                // PriceCharting uses the unsuffixed product as the primary
                // printing. For holo-only cards, that primary printing is Holo.
                variant = .holo
            } else if available.count == 1 {
                variant = available.first
            } else {
                variant = nil
            }

            guard let variant else {
                let reason = available.isEmpty
                    ? "TCGdex has no printing information for this card yet."
                    : "The PriceCharting printing does not match a TCGdex printing."
                issues.append(issue(row, reason))
                continue
            }
            let key = "\(card.id)|\(variant.rawValue)"
            if let saved = grouped[key] {
                guard saved.sourceFields.first == row.productID else {
                    issues.append(issue(row, "A different PriceCharting ID maps to the same TallyDex printing."))
                    continue
                }
                grouped[key] = PriceChartingResolvedMatch(
                    card: card,
                    setName: setName,
                    variant: variant,
                    quantity: saved.quantity + row.quantity,
                    sourceFields: saved.sourceFields
                )
            } else {
                grouped[key] = PriceChartingResolvedMatch(
                    card: card,
                    setName: setName,
                    variant: variant,
                    quantity: row.quantity,
                    sourceFields: row.fields
                )
            }
        }

        return try await collectionStore.preparePriceChartingImport(
            filename: filename,
            sourceRowCount: rows.count,
            matches: grouped.values.sorted {
                if $0.setName != $1.setName { return $0.setName < $1.setName }
                return $0.card.localID.localizedStandardCompare($1.card.localID) == .orderedAscending
            },
            issues: issues.sorted { $0.rowNumber < $1.rowNumber }
        )
    }

    private static func issue(_ row: PriceChartingCSVRow, _ reason: String) -> PriceChartingImportIssue {
        PriceChartingImportIssue(
            rowNumber: row.rowNumber,
            productName: row.productName,
            consoleName: row.consoleName,
            reason: reason
        )
    }
}

enum CollectionTransferCodec {
    static let maximumImportByteCount = 25 * 1_024 * 1_024

    static func readImportData(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CollectionRepositoryError.invalidImport
        }
        if let fileSize = values.fileSize, fileSize > maximumImportByteCount {
            throw CollectionRepositoryError.importTooLarge(
                maximumByteCount: maximumImportByteCount
            )
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumImportByteCount else {
            throw CollectionRepositoryError.importTooLarge(
                maximumByteCount: maximumImportByteCount
            )
        }
        return data
    }

    static func encode(_ document: PortableCollectionDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> PortableCollectionDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortableCollectionDocument.self, from: data)
    }

    static func csv(_ document: PortableCollectionDocument) -> Data {
        var rows = [[
            "record_type", "card_id", "variant", "quantity", "set_id", "status", "goal",
            "included_variants", "includes_secret_cards", "folder_id", "folder_name",
            "card_name_query", "pokemon_name", "display_mode", "cover_card_id", "wishlisted", "notes",
            "printing_id", "created_at", "updated_at", "pokemon_rules",
        ]]
        let formatter = ISO8601DateFormatter()

        for item in document.ownership {
            rows.append(["ownership", item.cardID, item.variant.rawValue, String(item.quantity)]
                + Array(repeating: "", count: 15)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.exactOwnership {
            rows.append(["exact_ownership", item.cardID, item.variant.rawValue, String(item.quantity)]
                + Array(repeating: "", count: 13)
                + [item.printingID, "", formatter.string(from: item.updatedAt)])
        }
        for item in document.setPreferences {
            rows.append(["set_preference", "", "", "", item.setID, item.status.rawValue,
                         item.goal.rawValue, item.includedVariants.map(\.rawValue).sorted().joined(separator: "|"),
                         String(item.includesSecretCards)]
                + Array(repeating: "", count: 10)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.folders {
            rows.append(["folder", "", "", "", "", "", "", "", "", item.id.uuidString,
                         item.name, item.cardNameQuery, item.pokemonName ?? "", item.displayMode.rawValue,
                         item.coverCardID ?? "", "", "",
                         "", formatter.string(from: item.createdAt), formatter.string(from: item.updatedAt)])
        }
        for item in document.cardMetadata {
            rows.append(["card_metadata", item.cardID, "", "", "", "", "", "", "", "", "", "", "", "", "",
                         String(item.isWishlisted), item.notes, "", "", formatter.string(from: item.updatedAt)])
        }

        // Append a lossless rules column without changing existing column positions.
        let folderRules = Dictionary(uniqueKeysWithValues: document.folders.map {
            ($0.id.uuidString, (try? PokemonCollectionRule.encode($0.pokemonRules)) ?? "")
        })
        for index in rows.indices.dropFirst() {
            rows[index].append(rows[index][0] == "folder" ? folderRules[rows[index][9]] ?? "" : "")
        }
        let csv = rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
