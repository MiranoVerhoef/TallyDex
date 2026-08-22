import Foundation
import GRDB

final class CollectionDatabase: @unchecked Sendable {
    let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try migrate()
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try migrate()
    }

    static func inMemory() throws -> CollectionDatabase {
        try CollectionDatabase(queue: DatabaseQueue())
    }

    static func applicationDatabase(fileManager: FileManager = .default) throws -> CollectionDatabase {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(path: "TallyDex", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "collection.sqlite")
        return try CollectionDatabase(path: databaseURL.path(percentEncoded: false))
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("collection-v1-variant-quantities") { database in
            try database.create(table: "collectionVariant") { table in
                table.column("cardID", .text).notNull().indexed()
                table.column("variant", .text).notNull()
                table.column("quantity", .integer).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["cardID", "variant"])
            }
        }

        migrator.registerMigration("collection-v2-set-goals") { database in
            try database.create(table: "collectionSetPreference") { table in
                table.column("setID", .text).primaryKey()
                table.column("goal", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("collection-v3-custom-folders") { database in
            try database.create(table: "customCollectionFolder") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("cardNameQuery", .text).notNull()
                table.column("displayMode", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("collection-v4-set-management") { database in
            try database.alter(table: "collectionSetPreference") { table in
                // Existing goal rows already represent sets the collector chose,
                // so they migrate into My Sets automatically.
                table.add(column: "status", .text).notNull().defaults(to: SetTrackingStatus.collecting.rawValue)
                table.add(column: "includedVariantsJSON", .text)
                table.add(column: "includesSecretCards", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("collection-v5-card-metadata") { database in
            try database.create(table: "collectionCardMetadata") { table in
                table.column("cardID", .text).primaryKey()
                table.column("isWishlisted", .boolean).notNull().defaults(to: false)
                table.column("notes", .text).notNull().defaults(to: "")
                table.column("updatedAt", .datetime).notNull()
            }
        }

        try migrator.migrate(queue)
    }
}

final class GRDBCollectionRepository: CollectionRepository, @unchecked Sendable {
    private let database: CollectionDatabase

    init(database: CollectionDatabase) {
        self.database = database
    }

    func fetchEntries(cardID: String) async throws -> [CollectionVariantEntry] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT cardID, variant, quantity, updatedAt
                FROM collectionVariant
                WHERE cardID = ?
                ORDER BY variant
                """,
                arguments: [cardID]
            ).compactMap(Self.entry)
        }
    }

    func fetchOwnedEntries() async throws -> [CollectionVariantEntry] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT cardID, variant, quantity, updatedAt
                FROM collectionVariant
                WHERE quantity > 0
                ORDER BY updatedAt DESC, cardID, variant
                """
            ).compactMap(Self.entry)
        }
    }

    func fetchSetGoals() async throws -> [String: CollectionGoal] {
        try await database.queue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT setID, goal FROM collectionSetPreference"
            )
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                let setID: String = row["setID"]
                let rawGoal: String = row["goal"]
                guard let goal = CollectionGoal(rawValue: rawGoal) else { return nil }
                return (setID, goal)
            })
        }
    }

    func fetchSetPreferences() async throws -> [String: SetCollectionPreference] {
        try await database.queue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT setID, goal, status, includedVariantsJSON, includesSecretCards, updatedAt
                FROM collectionSetPreference
                """
            )
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let preference = Self.setPreference(row) else { return nil }
                return (preference.setID, preference)
            })
        }
    }

    func fetchCustomFolders() async throws -> [CustomCollectionFolder] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, name, cardNameQuery, displayMode, createdAt, updatedAt
                FROM customCollectionFolder
                ORDER BY name COLLATE NOCASE, createdAt, id
                """
            ).compactMap(Self.customFolder)
        }
    }

    func fetchCardMetadata(cardID: String) async throws -> CardCollectionMetadata {
        try await database.queue.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT cardID, isWishlisted, notes, updatedAt
                FROM collectionCardMetadata
                WHERE cardID = ?
                """,
                arguments: [cardID]
            ) else {
                return .empty(cardID: cardID)
            }
            return CardCollectionMetadata(
                cardID: row["cardID"],
                isWishlisted: row["isWishlisted"],
                notes: row["notes"],
                updatedAt: row["updatedAt"]
            )
        }
    }

    func setGoal(_ goal: CollectionGoal, setID: String, updatedAt: Date) async throws {
        try await database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO collectionSetPreference (setID, goal, updatedAt)
                VALUES (?, ?, ?)
                ON CONFLICT(setID) DO UPDATE SET
                    goal = excluded.goal,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [setID, goal.rawValue, updatedAt]
            )
        }
    }

    func saveSetPreference(_ preference: SetCollectionPreference) async throws {
        let variants = preference.includedVariants.map(\.rawValue).sorted()
        let variantsJSON = String(
            data: try JSONEncoder().encode(variants),
            encoding: .utf8
        )
        try await database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO collectionSetPreference
                    (setID, goal, status, includedVariantsJSON, includesSecretCards, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(setID) DO UPDATE SET
                    goal = excluded.goal,
                    status = excluded.status,
                    includedVariantsJSON = excluded.includedVariantsJSON,
                    includesSecretCards = excluded.includesSecretCards,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    preference.setID,
                    preference.goal.rawValue,
                    preference.status.rawValue,
                    variantsJSON,
                    preference.includesSecretCards,
                    preference.updatedAt,
                ]
            )
        }
    }

    func deleteSetPreference(setID: String) async throws {
        try await database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM collectionSetPreference WHERE setID = ?",
                arguments: [setID]
            )
        }
    }

    func saveCustomFolder(_ folder: CustomCollectionFolder) async throws {
        let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = folder.cardNameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !query.isEmpty else {
            throw CollectionRepositoryError.invalidCustomFolder
        }

        try await database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO customCollectionFolder
                    (id, name, cardNameQuery, displayMode, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    cardNameQuery = excluded.cardNameQuery,
                    displayMode = excluded.displayMode,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    folder.id.uuidString,
                    name,
                    query,
                    folder.displayMode.rawValue,
                    folder.createdAt,
                    folder.updatedAt,
                ]
            )
        }
    }

    func deleteCustomFolder(id: UUID) async throws {
        try await database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM customCollectionFolder WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func saveCardMetadata(_ metadata: CardCollectionMetadata) async throws {
        try await database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO collectionCardMetadata (cardID, isWishlisted, notes, updatedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(cardID) DO UPDATE SET
                    isWishlisted = excluded.isWishlisted,
                    notes = excluded.notes,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    metadata.cardID,
                    metadata.isWishlisted,
                    metadata.notes,
                    metadata.updatedAt,
                ]
            )
        }
    }

    func setQuantity(
        _ quantity: Int,
        cardID: String,
        variant: CatalogVariantKind,
        updatedAt: Date
    ) async throws {
        guard quantity >= 0 else {
            throw CollectionRepositoryError.invalidQuantity
        }

        try await database.queue.write { database in
            if quantity == 0 {
                try database.execute(
                    sql: "DELETE FROM collectionVariant WHERE cardID = ? AND variant = ?",
                    arguments: [cardID, variant.rawValue]
                )
            } else {
                try database.execute(
                    sql: """
                    INSERT INTO collectionVariant (cardID, variant, quantity, updatedAt)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(cardID, variant) DO UPDATE SET
                        quantity = excluded.quantity,
                        updatedAt = excluded.updatedAt
                    """,
                    arguments: [cardID, variant.rawValue, quantity, updatedAt]
                )
            }
        }
    }

    private static func entry(_ row: Row) -> CollectionVariantEntry? {
        let rawVariant: String = row["variant"]
        guard let variant = CatalogVariantKind(rawValue: rawVariant) else { return nil }
        return CollectionVariantEntry(
            cardID: row["cardID"],
            variant: variant,
            quantity: row["quantity"],
            updatedAt: row["updatedAt"]
        )
    }

    private static func customFolder(_ row: Row) -> CustomCollectionFolder? {
        let rawID: String = row["id"]
        let rawMode: String = row["displayMode"]
        guard let id = UUID(uuidString: rawID),
              let displayMode = CustomCollectionFolderDisplayMode(rawValue: rawMode) else {
            return nil
        }
        return CustomCollectionFolder(
            id: id,
            name: row["name"],
            cardNameQuery: row["cardNameQuery"],
            displayMode: displayMode,
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"]
        )
    }

    private static func setPreference(_ row: Row) -> SetCollectionPreference? {
        let rawGoal: String = row["goal"]
        let rawStatus: String = row["status"]
        guard let goal = CollectionGoal(rawValue: rawGoal),
              let status = SetTrackingStatus(rawValue: rawStatus) else {
            return nil
        }
        let variantsJSON: String? = row["includedVariantsJSON"]
        let rawVariants: [String]
        if let variantsJSON,
           let data = variantsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            rawVariants = decoded
        } else {
            rawVariants = goal == .holoChase
                ? [CatalogVariantKind.holo.rawValue, CatalogVariantKind.reverseHolo.rawValue]
                : [CatalogVariantKind.normal.rawValue]
        }
        return SetCollectionPreference(
            setID: row["setID"],
            status: status,
            goal: goal,
            includedVariants: Set(rawVariants.compactMap(CatalogVariantKind.init(rawValue:))),
            includesSecretCards: row["includesSecretCards"],
            updatedAt: row["updatedAt"]
        )
    }
}
