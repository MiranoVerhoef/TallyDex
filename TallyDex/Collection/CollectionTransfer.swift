import Foundation

struct PortableCollectionDocument: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.miranoverhoef.tallydex.collection"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let ownership: [OwnershipRecord]
    let setPreferences: [SetPreferenceRecord]
    let folders: [FolderRecord]
    let cardMetadata: [CardMetadataRecord]

    struct OwnershipRecord: Codable, Equatable, Sendable {
        let cardID: String
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
        let createdAt: Date
        let updatedAt: Date
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

    var importedCount: Int { additions + changes }
    var hasChanges: Bool { importedCount + removals > 0 }
}

struct PreparedCollectionImport: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let document: PortableCollectionDocument
    let mergePreview: CollectionImportPreview
    let replacePreview: CollectionImportPreview
}

enum CollectionTransferCodec {
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
            "card_name_query", "display_mode", "wishlisted", "notes", "created_at", "updated_at",
        ]]
        let formatter = ISO8601DateFormatter()

        for item in document.ownership {
            rows.append(["ownership", item.cardID, item.variant.rawValue, String(item.quantity)]
                + Array(repeating: "", count: 12)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.setPreferences {
            rows.append(["set_preference", "", "", "", item.setID, item.status.rawValue,
                         item.goal.rawValue, item.includedVariants.map(\.rawValue).sorted().joined(separator: "|"),
                         String(item.includesSecretCards)]
                + Array(repeating: "", count: 7)
                + [formatter.string(from: item.updatedAt)])
        }
        for item in document.folders {
            rows.append(["folder", "", "", "", "", "", "", "", "", item.id.uuidString,
                         item.name, item.cardNameQuery, item.displayMode.rawValue, "", "",
                         formatter.string(from: item.createdAt), formatter.string(from: item.updatedAt)])
        }
        for item in document.cardMetadata {
            rows.append(["card_metadata", item.cardID, "", "", "", "", "", "", "", "", "", "", "",
                         String(item.isWishlisted), item.notes, "", formatter.string(from: item.updatedAt)])
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
