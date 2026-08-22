import Foundation
import GRDB

final class CatalogDatabase: @unchecked Sendable {
    let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try migrate()
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try migrate()
    }

    static func inMemory() throws -> CatalogDatabase {
        try CatalogDatabase(queue: DatabaseQueue())
    }

    static func applicationDatabase(fileManager: FileManager = .default) throws -> CatalogDatabase {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(path: "TallyDex", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "catalog.sqlite")
        return try CatalogDatabase(path: databaseURL.path(percentEncoded: false))
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("catalog-v1") { database in
            try database.create(table: "catalogSeries") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("logoURL", .text)
                table.column("sortIndex", .integer).notNull()
            }

            try database.create(table: "catalogSet") { table in
                table.column("id", .text).primaryKey()
                table.column("seriesID", .text)
                    .notNull()
                    .indexed()
                    .references("catalogSeries", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("logoURL", .text)
                table.column("symbolURL", .text)
                table.column("officialCardCount", .integer).notNull()
                table.column("totalCardCount", .integer).notNull()
                table.column("releaseDate", .text)
                table.column("sortIndex", .integer).notNull()
            }

            try database.create(table: "catalogCard") { table in
                table.column("id", .text).primaryKey()
                table.column("setID", .text)
                    .notNull()
                    .indexed()
                    .references("catalogSet", onDelete: .cascade)
                table.column("localID", .text).notNull()
                table.column("name", .text).notNull()
                table.column("imageURL", .text)
                table.column("category", .text)
                table.column("illustrator", .text)
                table.column("rarity", .text)
                table.column("sortIndex", .integer).notNull()
            }

            try database.create(table: "catalogVariant") { table in
                table.column("cardID", .text)
                    .notNull()
                    .references("catalogCard", onDelete: .cascade)
                table.column("kind", .text).notNull()
                table.primaryKey(["cardID", "kind"])
            }

            try database.create(table: "catalogMetadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }

        try migrator.migrate(queue)
    }
}

final class GRDBCatalogRepository: CatalogRepository, @unchecked Sendable {
    private let database: CatalogDatabase

    init(database: CatalogDatabase) {
        self.database = database
    }

    func fetchSeries() async throws -> [CatalogSeries] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT id, name, logoURL FROM catalogSeries ORDER BY sortIndex"
            ).map { row in
                CatalogSeries(
                    id: row["id"],
                    name: row["name"],
                    logoURL: Self.url(row["logoURL"])
                )
            }
        }
    }

    func fetchSets(seriesID: String?) async throws -> [CatalogSet] {
        try await database.queue.read { database in
            let rows: [Row]
            if let seriesID {
                rows = try Row.fetchAll(
                    database,
                    sql: "SELECT * FROM catalogSet WHERE seriesID = ? ORDER BY sortIndex",
                    arguments: [seriesID]
                )
            } else {
                rows = try Row.fetchAll(
                    database,
                    sql: "SELECT * FROM catalogSet ORDER BY seriesID, sortIndex"
                )
            }
            return rows.map(Self.catalogSet)
        }
    }

    func fetchCards(setID: String) async throws -> [CatalogCard] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT * FROM catalogCard WHERE setID = ? ORDER BY sortIndex",
                arguments: [setID]
            ).map(Self.catalogCard)
        }
    }

    func fetchVariants(cardID: String) async throws -> Set<CatalogVariantKind> {
        try await database.queue.read { database in
            let rawValues = try String.fetchAll(
                database,
                sql: "SELECT kind FROM catalogVariant WHERE cardID = ? ORDER BY kind",
                arguments: [cardID]
            )
            return Set(rawValues.compactMap(CatalogVariantKind.init(rawValue:)))
        }
    }

    func metadataDate(forKey key: String) async throws -> Date? {
        try await database.queue.read { database in
            try Date.fetchOne(
                database,
                sql: "SELECT updatedAt FROM catalogMetadata WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func upsertSeries(_ series: [CatalogSeries]) async throws {
        try await database.queue.write { database in
            for (index, item) in series.enumerated() {
                try database.execute(
                    sql: """
                    INSERT INTO catalogSeries (id, name, logoURL, sortIndex)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        logoURL = excluded.logoURL,
                        sortIndex = excluded.sortIndex
                    """,
                    arguments: [item.id, item.name, item.logoURL?.absoluteString, index]
                )
            }
        }
    }

    func replaceCatalog(_ snapshots: [CatalogSeriesSnapshot]) async throws {
        let seriesIDs = snapshots.map(\.series.id)
        let setIDs = snapshots.flatMap { $0.sets.map(\.id) }
        guard Set(seriesIDs).count == seriesIDs.count,
              Set(setIDs).count == setIDs.count,
              snapshots.allSatisfy({ snapshot in
                  snapshot.sets.allSatisfy { $0.seriesID == snapshot.series.id }
              }) else {
            throw CatalogRepositoryError.invalidSnapshot
        }

        try await database.queue.write { database in
            try database.execute(sql: "DELETE FROM catalogSeries")

            for (seriesIndex, snapshot) in snapshots.enumerated() {
                let series = snapshot.series
                try database.execute(
                    sql: """
                    INSERT INTO catalogSeries (id, name, logoURL, sortIndex)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [series.id, series.name, series.logoURL?.absoluteString, seriesIndex]
                )

                for (setIndex, set) in snapshot.sets.enumerated() {
                    try Self.insert(set, sortIndex: setIndex, database: database)
                }
            }
        }
    }

    func replaceSets(_ sets: [CatalogSet], forSeriesID seriesID: String) async throws {
        guard sets.allSatisfy({ $0.seriesID == seriesID }) else {
            throw CatalogRepositoryError.seriesMismatch
        }

        try await database.queue.write { database in
            try database.execute(
                sql: "DELETE FROM catalogSet WHERE seriesID = ?",
                arguments: [seriesID]
            )
            for (index, set) in sets.enumerated() {
                try Self.insert(set, sortIndex: index, database: database)
            }
        }
    }

    func replaceSet(_ snapshot: CatalogSetSnapshot) async throws {
        try await database.queue.write { database in
            try Self.insert(snapshot.set, sortIndex: 0, database: database)
            try database.execute(
                sql: "DELETE FROM catalogCard WHERE setID = ?",
                arguments: [snapshot.set.id]
            )
            for (index, card) in snapshot.cards.enumerated() {
                try database.execute(
                    sql: """
                    INSERT INTO catalogCard
                        (id, setID, localID, name, imageURL, category, illustrator, rarity, sortIndex)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        card.id,
                        card.setID,
                        card.localID,
                        card.name,
                        card.imageURL?.absoluteString,
                        card.category,
                        card.illustrator,
                        card.rarity,
                        index,
                    ]
                )
            }
        }
    }

    func replaceCard(_ snapshot: CatalogCardSnapshot) async throws {
        try await database.queue.write { database in
            let card = snapshot.card
            try database.execute(
                sql: """
                INSERT INTO catalogCard
                    (id, setID, localID, name, imageURL, category, illustrator, rarity, sortIndex)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(id) DO UPDATE SET
                    setID = excluded.setID,
                    localID = excluded.localID,
                    name = excluded.name,
                    imageURL = excluded.imageURL,
                    category = excluded.category,
                    illustrator = excluded.illustrator,
                    rarity = excluded.rarity
                """,
                arguments: [
                    card.id,
                    card.setID,
                    card.localID,
                    card.name,
                    card.imageURL?.absoluteString,
                    card.category,
                    card.illustrator,
                    card.rarity,
                ]
            )
            try database.execute(
                sql: "DELETE FROM catalogVariant WHERE cardID = ?",
                arguments: [card.id]
            )
            for variant in snapshot.variants.sorted(by: { $0.rawValue < $1.rawValue }) {
                try database.execute(
                    sql: "INSERT INTO catalogVariant (cardID, kind) VALUES (?, ?)",
                    arguments: [card.id, variant.rawValue]
                )
            }
        }
    }

    func setMetadataDate(_ date: Date, forKey key: String) async throws {
        try await database.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO catalogMetadata (key, value, updatedAt)
                VALUES (?, 'date', ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [key, date]
            )
        }
    }

    private static func insert(_ set: CatalogSet, sortIndex: Int, database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO catalogSet
                (id, seriesID, name, logoURL, symbolURL, officialCardCount, totalCardCount, releaseDate, sortIndex)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                seriesID = excluded.seriesID,
                name = excluded.name,
                logoURL = excluded.logoURL,
                symbolURL = excluded.symbolURL,
                officialCardCount = excluded.officialCardCount,
                totalCardCount = excluded.totalCardCount,
                releaseDate = COALESCE(excluded.releaseDate, catalogSet.releaseDate),
                sortIndex = excluded.sortIndex
            """,
            arguments: [
                set.id,
                set.seriesID,
                set.name,
                set.logoURL?.absoluteString,
                set.symbolURL?.absoluteString,
                set.officialCardCount,
                set.totalCardCount,
                set.releaseDate,
                sortIndex,
            ]
        )
    }

    private static func catalogSet(row: Row) -> CatalogSet {
        CatalogSet(
            id: row["id"],
            seriesID: row["seriesID"],
            name: row["name"],
            logoURL: url(row["logoURL"]),
            symbolURL: url(row["symbolURL"]),
            officialCardCount: row["officialCardCount"],
            totalCardCount: row["totalCardCount"],
            releaseDate: row["releaseDate"]
        )
    }

    private static func catalogCard(row: Row) -> CatalogCard {
        CatalogCard(
            id: row["id"],
            setID: row["setID"],
            localID: row["localID"],
            name: row["name"],
            imageURL: url(row["imageURL"]),
            category: row["category"],
            illustrator: row["illustrator"],
            rarity: row["rarity"]
        )
    }

    private static func url(_ string: String?) -> URL? {
        string.flatMap(URL.init(string:))
    }
}

enum CatalogRepositoryError: Error, Equatable {
    case seriesMismatch
    case invalidSnapshot
}
