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
    static let currentSchemaVersion = 2

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let ownership: [OwnershipRecord]
    let setPreferences: [SetPreferenceRecord]
    let folders: [FolderRecord]
    let cardMetadata: [CardMetadataRecord]
    let exactOwnership: [ExactOwnershipRecord]

    init(
        format: String,
        schemaVersion: Int,
        exportedAt: Date,
        appVersion: String,
        ownership: [OwnershipRecord],
        setPreferences: [SetPreferenceRecord],
        folders: [FolderRecord],
        cardMetadata: [CardMetadataRecord],
        exactOwnership: [ExactOwnershipRecord] = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case format, schemaVersion, exportedAt, appVersion, ownership
        case setPreferences, folders, cardMetadata, exactOwnership
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
        let displayMode: CustomCollectionFolderDisplayMode
        let iconName: String?
        let coverCardID: String?
        let createdAt: Date
        let updatedAt: Date

        init(
            id: UUID,
            name: String,
            cardNameQuery: String,
            displayMode: CustomCollectionFolderDisplayMode,
            iconName: String? = nil,
            coverCardID: String? = nil,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.cardNameQuery = cardNameQuery
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
            "card_name_query", "display_mode", "cover_card_id", "wishlisted", "notes",
            "printing_id", "created_at", "updated_at",
        ]]
        let formatter = ISO8601DateFormatter()

        for item in document.ownership {
            rows.append(["ownership", item.cardID, item.variant.rawValue, String(item.quantity)]
                + Array(repeating: "", count: 14)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.exactOwnership {
            rows.append(["exact_ownership", item.cardID, item.variant.rawValue, String(item.quantity)]
                + Array(repeating: "", count: 12)
                + [item.printingID, "", formatter.string(from: item.updatedAt)])
        }
        for item in document.setPreferences {
            rows.append(["set_preference", "", "", "", item.setID, item.status.rawValue,
                         item.goal.rawValue, item.includedVariants.map(\.rawValue).sorted().joined(separator: "|"),
                         String(item.includesSecretCards)]
                + Array(repeating: "", count: 9)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.folders {
            rows.append(["folder", "", "", "", "", "", "", "", "", item.id.uuidString,
                         item.name, item.cardNameQuery, item.displayMode.rawValue, item.coverCardID ?? "", "", "",
                         "", formatter.string(from: item.createdAt), formatter.string(from: item.updatedAt)])
        }
        for item in document.cardMetadata {
            rows.append(["card_metadata", item.cardID, "", "", "", "", "", "", "", "", "", "", "", "",
                         String(item.isWishlisted), item.notes, "", "", formatter.string(from: item.updatedAt)])
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
