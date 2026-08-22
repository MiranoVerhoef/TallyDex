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

        migrator.registerMigration("catalog-v2-set-abbreviation") { database in
            try database.alter(table: "catalogSet") { table in
                table.add(column: "abbreviation", .text)
            }
        }

        migrator.registerMigration("catalog-v3-set-rarity-counts") { database in
            try database.alter(table: "catalogSet") { table in
                table.add(column: "rarityCountsJSON", .text)
            }
        }

        migrator.registerMigration("catalog-v4-card-search-index") { database in
            try database.create(table: "catalogSearchCard") { table in
                table.column("id", .text).primaryKey()
                table.column("setID", .text)
                    .notNull()
                    .indexed()
                    .references("catalogSet", onDelete: .cascade)
                table.column("localID", .text).notNull()
                table.column("name", .text).notNull().indexed()
                table.column("imageURL", .text)
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

    func fetchDownloadedSetIDs() async throws -> [String] {
        try await database.queue.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT DISTINCT setID FROM catalogCard ORDER BY setID"
            )
        }
    }

    func searchCards(query: String) async throws -> [CatalogCardSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await database.queue.read { database in
            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            let tokenClause = "(search.name LIKE ? COLLATE NOCASE OR search.localID LIKE ? COLLATE NOCASE OR catalogSet.name LIKE ? COLLATE NOCASE)"
            let whereClause = Array(repeating: tokenClause, count: tokens.count).joined(separator: " AND ")
            let arguments = tokens.flatMap { token in
                let pattern = "%\(token)%"
                return [pattern, pattern, pattern]
            }
            return try Row.fetchAll(
                database,
                sql: """
                SELECT search.*, catalogSet.name AS setName
                FROM catalogSearchCard AS search
                JOIN catalogSet ON catalogSet.id = search.setID
                WHERE \(whereClause)
                ORDER BY search.name COLLATE NOCASE, catalogSet.name COLLATE NOCASE, search.localID
                LIMIT 100
                """,
                arguments: StatementArguments(arguments)
            ).map { row in
                CatalogCardSearchResult(
                    card: CatalogCard(
                        id: row["id"],
                        setID: row["setID"],
                        localID: row["localID"],
                        name: row["name"],
                        imageURL: Self.url(row["imageURL"]),
                        category: nil,
                        illustrator: nil,
                        rarity: nil
                    ),
                    setName: row["setName"]
                )
            }
        }
    }

    func fetchSearchResults(cardIDs: [String]) async throws -> [CatalogCardSearchResult] {
        guard !cardIDs.isEmpty else { return [] }
        return try await database.queue.read { database in
            let placeholders = Array(repeating: "?", count: cardIDs.count).joined(separator: ",")
            return try Row.fetchAll(
                database,
                sql: """
                SELECT search.*, catalogSet.name AS setName
                FROM catalogSearchCard AS search
                JOIN catalogSet ON catalogSet.id = search.setID
                WHERE search.id IN (\(placeholders))
                ORDER BY search.name COLLATE NOCASE, catalogSet.name COLLATE NOCASE, search.localID
                """,
                arguments: StatementArguments(cardIDs)
            ).map { row in
                CatalogCardSearchResult(
                    card: CatalogCard(
                        id: row["id"],
                        setID: row["setID"],
                        localID: row["localID"],
                        name: row["name"],
                        imageURL: Self.url(row["imageURL"]),
                        category: nil,
                        illustrator: nil,
                        rarity: nil
                    ),
                    setName: row["setName"]
                )
            }
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
            if seriesIDs.isEmpty {
                try database.execute(sql: "DELETE FROM catalogSeries")
                return
            }

            let seriesPlaceholders = Array(repeating: "?", count: seriesIDs.count).joined(separator: ",")
            try database.execute(
                sql: "DELETE FROM catalogSeries WHERE id NOT IN (\(seriesPlaceholders))",
                arguments: StatementArguments(seriesIDs)
            )

            if setIDs.isEmpty {
                try database.execute(sql: "DELETE FROM catalogSet")
            } else {
                let setPlaceholders = Array(repeating: "?", count: setIDs.count).joined(separator: ",")
                try database.execute(
                    sql: "DELETE FROM catalogSet WHERE id NOT IN (\(setPlaceholders))",
                    arguments: StatementArguments(setIDs)
                )
            }

            for (seriesIndex, snapshot) in snapshots.enumerated() {
                let series = snapshot.series
                try database.execute(
                    sql: """
                    INSERT INTO catalogSeries (id, name, logoURL, sortIndex)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        logoURL = excluded.logoURL,
                        sortIndex = excluded.sortIndex
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
            let existingSortIndex = try Int.fetchOne(
                database,
                sql: "SELECT sortIndex FROM catalogSet WHERE id = ?",
                arguments: [snapshot.set.id]
            ) ?? 0
            try Self.insert(snapshot.set, sortIndex: existingSortIndex, database: database)
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

    func replaceSearchIndex(_ cards: [CatalogCard]) async throws {
        let cardIDs = cards.map(\.id)
        guard Set(cardIDs).count == cardIDs.count else {
            throw CatalogRepositoryError.invalidSnapshot
        }

        try await database.queue.write { database in
            try database.execute(sql: "DELETE FROM catalogSearchCard")
            for card in cards {
                try database.execute(
                    sql: """
                    INSERT INTO catalogSearchCard (id, setID, localID, name, imageURL)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        card.id,
                        card.setID,
                        card.localID,
                        card.name,
                        card.imageURL?.absoluteString,
                    ]
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
                (id, seriesID, name, abbreviation, logoURL, symbolURL, officialCardCount, totalCardCount, releaseDate, rarityCountsJSON, sortIndex)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                seriesID = excluded.seriesID,
                name = excluded.name,
                abbreviation = COALESCE(excluded.abbreviation, catalogSet.abbreviation),
                logoURL = excluded.logoURL,
                symbolURL = excluded.symbolURL,
                officialCardCount = excluded.officialCardCount,
                totalCardCount = excluded.totalCardCount,
                releaseDate = COALESCE(excluded.releaseDate, catalogSet.releaseDate),
                rarityCountsJSON = COALESCE(excluded.rarityCountsJSON, catalogSet.rarityCountsJSON),
                sortIndex = excluded.sortIndex
            """,
            arguments: [
                set.id,
                set.seriesID,
                set.name,
                set.abbreviation,
                set.logoURL?.absoluteString,
                set.symbolURL?.absoluteString,
                set.officialCardCount,
                set.totalCardCount,
                set.releaseDate,
                encodeRarityCounts(set.rarityCounts),
                sortIndex,
            ]
        )
    }

    private static func catalogSet(row: Row) -> CatalogSet {
        CatalogSet(
            id: row["id"],
            seriesID: row["seriesID"],
            name: row["name"],
            abbreviation: row["abbreviation"],
            logoURL: url(row["logoURL"]),
            symbolURL: url(row["symbolURL"]),
            officialCardCount: row["officialCardCount"],
            totalCardCount: row["totalCardCount"],
            releaseDate: row["releaseDate"],
            rarityCounts: decodeRarityCounts(row["rarityCountsJSON"])
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

    private static func encodeRarityCounts(_ counts: [CatalogRarityCount]?) -> String? {
        guard let counts,
              let data = try? JSONEncoder().encode(counts) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeRarityCounts(_ string: String?) -> [CatalogRarityCount]? {
        guard let string,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([CatalogRarityCount].self, from: data)
    }
}

enum CatalogRepositoryError: Error, Equatable {
    case seriesMismatch
    case invalidSnapshot
}
