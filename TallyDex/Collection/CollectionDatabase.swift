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
}
