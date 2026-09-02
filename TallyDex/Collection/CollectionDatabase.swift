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

        migrator.registerMigration("collection-v6-simple-goals-and-prerelease-variants") { database in
            try database.execute(
                sql: """
                UPDATE collectionSetPreference
                SET goal = 'normal', includesSecretCards = 1
                WHERE goal IN ('main', 'complete')
                """
            )
            try database.execute(
                sql: """
                UPDATE collectionSetPreference
                SET goal = 'custom', includesSecretCards = 1
                WHERE goal = 'holoChase'
                """
            )

            // These promo IDs are Prerelease printings. Move any previously
            // checked "Normal" quantity to the corrected printing without loss.
            try database.execute(
                sql: """
                INSERT INTO collectionVariant (cardID, variant, quantity, updatedAt)
                SELECT cardID, 'prerelease', quantity, updatedAt
                FROM collectionVariant
                WHERE cardID IN ('smp-SM95', 'swshp-SWSH186') AND variant = 'normal'
                ON CONFLICT(cardID, variant) DO UPDATE SET
                    quantity = MAX(quantity, excluded.quantity),
                    updatedAt = MAX(updatedAt, excluded.updatedAt)
                """
            )
            try database.execute(
                sql: """
                DELETE FROM collectionVariant
                WHERE cardID IN ('smp-SM95', 'swshp-SWSH186') AND variant = 'normal'
                """
            )
        }

        migrator.registerMigration("collection-v7-automatic-backups") { database in
            try database.create(table: "collectionBackup") { table in
                table.column("id", .text).primaryKey()
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("reason", .text).notNull()
                table.column("payloadJSON", .text).notNull()
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
                guard let goal = CollectionGoal.migrated(persistedValue: rawGoal) else { return nil }
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

    func fetchBackups() async throws -> [CollectionBackup] {
        try await database.queue.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, createdAt, reason
                FROM collectionBackup
                ORDER BY createdAt DESC, id DESC
                """
            ).compactMap(Self.backup)
        }
    }

    func exportCollection(
        exportedAt: Date,
        appVersion: String
    ) async throws -> PortableCollectionDocument {
        try await database.queue.read { database in
            Self.portableDocument(
                from: try Self.captureSnapshot(in: database),
                exportedAt: exportedAt,
                appVersion: appVersion
            )
        }
    }

    func previewImport(
        _ document: PortableCollectionDocument,
        mode: CollectionImportMode
    ) async throws -> CollectionImportPreview {
        try Self.validate(document)
        return try await database.queue.read { database in
            Self.preview(
                document,
                current: Self.portableDocument(
                    from: try Self.captureSnapshot(in: database),
                    exportedAt: document.exportedAt,
                    appVersion: document.appVersion
                ),
                mode: mode
            )
        }
    }

    func importCollection(
        _ document: PortableCollectionDocument,
        mode: CollectionImportMode,
        importedAt: Date
    ) async throws {
        try Self.validate(document)
        try await database.queue.write { database in
            let currentPayload = try Self.captureSnapshot(in: database)
            let current = Self.portableDocument(
                from: currentPayload,
                exportedAt: document.exportedAt,
                appVersion: document.appVersion
            )
            let preview = Self.preview(document, current: current, mode: mode)
            guard preview.hasChanges else { return }

            let safetyBackup = CollectionBackup(
                id: UUID(),
                createdAt: importedAt,
                reason: "Before \(mode.displayName.lowercased()) import"
            )
            try Self.insertBackup(safetyBackup, payload: currentPayload, in: database)

            switch mode {
            case .replace:
                try Self.applySnapshot(Self.backupPayload(from: document), in: database)
            case .merge:
                try Self.merge(document, into: current, in: database)
            }
            try Self.pruneBackups(in: database)
        }
    }

    func createBackup(reason: String, createdAt: Date) async throws -> CollectionBackup {
        let backup = CollectionBackup(id: UUID(), createdAt: createdAt, reason: reason)
        try await database.queue.write { database in
            try Self.insertBackup(backup, payload: Self.captureSnapshot(in: database), in: database)
            try Self.pruneBackups(in: database)
        }
        return backup
    }

    func restoreBackup(
        id: UUID,
        safetyBackupReason: String,
        restoredAt: Date
    ) async throws {
        try await database.queue.write { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT payloadJSON FROM collectionBackup WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                throw CollectionRepositoryError.invalidBackup
            }
            let payloadJSON: String = row["payloadJSON"]
            guard let payloadData = payloadJSON.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(CollectionBackupPayload.self, from: payloadData) else {
                throw CollectionRepositoryError.invalidBackup
            }

            let safetyBackup = CollectionBackup(
                id: UUID(),
                createdAt: restoredAt,
                reason: safetyBackupReason
            )
            try Self.insertBackup(
                safetyBackup,
                payload: Self.captureSnapshot(in: database),
                in: database
            )
            try Self.applySnapshot(payload, in: database)
            try Self.pruneBackups(in: database)
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

    private static func backup(_ row: Row) -> CollectionBackup? {
        let rawID: String = row["id"]
        guard let id = UUID(uuidString: rawID) else { return nil }
        return CollectionBackup(
            id: id,
            createdAt: row["createdAt"],
            reason: row["reason"]
        )
    }

    private static func captureSnapshot(in database: Database) throws -> CollectionBackupPayload {
        let variants = try Row.fetchAll(
            database,
            sql: "SELECT cardID, variant, quantity, updatedAt FROM collectionVariant"
        ).map {
            CollectionBackupPayload.Variant(
                cardID: $0["cardID"],
                variant: $0["variant"],
                quantity: $0["quantity"],
                updatedAt: $0["updatedAt"]
            )
        }
        let preferences = try Row.fetchAll(
            database,
            sql: """
            SELECT setID, goal, status, includedVariantsJSON, includesSecretCards, updatedAt
            FROM collectionSetPreference
            """
        ).map {
            CollectionBackupPayload.Preference(
                setID: $0["setID"],
                goal: $0["goal"],
                status: $0["status"],
                includedVariantsJSON: $0["includedVariantsJSON"],
                includesSecretCards: $0["includesSecretCards"],
                updatedAt: $0["updatedAt"]
            )
        }
        let folders = try Row.fetchAll(
            database,
            sql: """
            SELECT id, name, cardNameQuery, displayMode, createdAt, updatedAt
            FROM customCollectionFolder
            """
        ).map {
            CollectionBackupPayload.Folder(
                id: $0["id"],
                name: $0["name"],
                cardNameQuery: $0["cardNameQuery"],
                displayMode: $0["displayMode"],
                createdAt: $0["createdAt"],
                updatedAt: $0["updatedAt"]
            )
        }
        let metadata = try Row.fetchAll(
            database,
            sql: "SELECT cardID, isWishlisted, notes, updatedAt FROM collectionCardMetadata"
        ).map {
            CollectionBackupPayload.Metadata(
                cardID: $0["cardID"],
                isWishlisted: $0["isWishlisted"],
                notes: $0["notes"],
                updatedAt: $0["updatedAt"]
            )
        }
        return CollectionBackupPayload(
            variants: variants,
            preferences: preferences,
            folders: folders,
            metadata: metadata
        )
    }

    private static func portableDocument(
        from payload: CollectionBackupPayload,
        exportedAt: Date,
        appVersion: String
    ) -> PortableCollectionDocument {
        PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: PortableCollectionDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            appVersion: appVersion,
            ownership: payload.variants.compactMap { item in
                guard let variant = CatalogVariantKind(rawValue: item.variant) else { return nil }
                return .init(
                    cardID: item.cardID,
                    variant: variant,
                    quantity: item.quantity,
                    updatedAt: item.updatedAt
                )
            }.sorted { ($0.cardID, $0.variant.rawValue) < ($1.cardID, $1.variant.rawValue) },
            setPreferences: payload.preferences.compactMap { item in
                guard let goal = CollectionGoal.migrated(persistedValue: item.goal),
                      let status = SetTrackingStatus(rawValue: item.status) else { return nil }
                let variants = item.includedVariantsJSON
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [CatalogVariantKind.normal.rawValue]
                return .init(
                    setID: item.setID,
                    status: status,
                    goal: goal,
                    includedVariants: variants.compactMap(CatalogVariantKind.init(rawValue:)).sorted { $0.rawValue < $1.rawValue },
                    includesSecretCards: item.includesSecretCards,
                    updatedAt: item.updatedAt
                )
            }.sorted { $0.setID < $1.setID },
            folders: payload.folders.compactMap { item in
                guard let id = UUID(uuidString: item.id),
                      let mode = CustomCollectionFolderDisplayMode(rawValue: item.displayMode) else { return nil }
                return .init(
                    id: id,
                    name: item.name,
                    cardNameQuery: item.cardNameQuery,
                    displayMode: mode,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            cardMetadata: payload.metadata.map {
                .init(cardID: $0.cardID, isWishlisted: $0.isWishlisted, notes: $0.notes, updatedAt: $0.updatedAt)
            }.sorted { $0.cardID < $1.cardID }
        )
    }

    private static func backupPayload(from document: PortableCollectionDocument) throws -> CollectionBackupPayload {
        let encoder = JSONEncoder()
        return CollectionBackupPayload(
            variants: document.ownership.map {
                .init(cardID: $0.cardID, variant: $0.variant.rawValue, quantity: $0.quantity, updatedAt: $0.updatedAt)
            },
            preferences: try document.setPreferences.map {
                let variantsJSON = String(
                    data: try encoder.encode($0.includedVariants.map(\.rawValue).sorted()),
                    encoding: .utf8
                )
                return .init(
                    setID: $0.setID,
                    goal: $0.goal.rawValue,
                    status: $0.status.rawValue,
                    includedVariantsJSON: variantsJSON,
                    includesSecretCards: $0.includesSecretCards,
                    updatedAt: $0.updatedAt
                )
            },
            folders: document.folders.map {
                .init(
                    id: $0.id.uuidString,
                    name: $0.name,
                    cardNameQuery: $0.cardNameQuery,
                    displayMode: $0.displayMode.rawValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            metadata: document.cardMetadata.map {
                .init(cardID: $0.cardID, isWishlisted: $0.isWishlisted, notes: $0.notes, updatedAt: $0.updatedAt)
            }
        )
    }

    private static func validate(_ document: PortableCollectionDocument) throws {
        guard document.format == PortableCollectionDocument.formatIdentifier else {
            throw CollectionRepositoryError.invalidImport
        }
        guard document.schemaVersion == PortableCollectionDocument.currentSchemaVersion else {
            throw CollectionRepositoryError.unsupportedImportVersion(document.schemaVersion)
        }
        guard document.ownership.allSatisfy({ !$0.cardID.isEmpty && $0.quantity > 0 }),
              Set(document.ownership.map { "\($0.cardID)|\($0.variant.rawValue)" }).count == document.ownership.count,
              document.setPreferences.allSatisfy({ !$0.setID.isEmpty && !$0.includedVariants.isEmpty }),
              Set(document.setPreferences.map(\.setID)).count == document.setPreferences.count,
              document.folders.allSatisfy({
                  !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !$0.cardNameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              Set(document.folders.map(\.id)).count == document.folders.count,
              document.cardMetadata.allSatisfy({ !$0.cardID.isEmpty }),
              Set(document.cardMetadata.map(\.cardID)).count == document.cardMetadata.count else {
            throw CollectionRepositoryError.invalidImport
        }
    }

    private static func preview(
        _ incoming: PortableCollectionDocument,
        current: PortableCollectionDocument,
        mode: CollectionImportMode
    ) -> CollectionImportPreview {
        var additions = 0
        var changes = 0
        var conflicts = 0
        var skipped = 0
        var removals = 0

        func compare<Key: Hashable, Value: Equatable>(
            incoming: [Key: Value],
            current: [Key: Value],
            date: (Value) -> Date
        ) {
            for (key, item) in incoming {
                guard let saved = current[key] else { additions += 1; continue }
                if saved == item { skipped += 1; continue }
                if mode == .replace || date(item) > date(saved) {
                    changes += 1
                } else {
                    conflicts += 1
                }
            }
            if mode == .replace {
                removals += current.keys.filter { incoming[$0] == nil }.count
            }
        }

        compare(
            incoming: Dictionary(uniqueKeysWithValues: incoming.ownership.map { ("\($0.cardID)|\($0.variant.rawValue)", $0) }),
            current: Dictionary(uniqueKeysWithValues: current.ownership.map { ("\($0.cardID)|\($0.variant.rawValue)", $0) }),
            date: \.updatedAt
        )
        compare(
            incoming: Dictionary(uniqueKeysWithValues: incoming.setPreferences.map { ($0.setID, $0) }),
            current: Dictionary(uniqueKeysWithValues: current.setPreferences.map { ($0.setID, $0) }),
            date: \.updatedAt
        )
        compare(
            incoming: Dictionary(uniqueKeysWithValues: incoming.folders.map { ($0.id, $0) }),
            current: Dictionary(uniqueKeysWithValues: current.folders.map { ($0.id, $0) }),
            date: \.updatedAt
        )
        compare(
            incoming: Dictionary(uniqueKeysWithValues: incoming.cardMetadata.map { ($0.cardID, $0) }),
            current: Dictionary(uniqueKeysWithValues: current.cardMetadata.map { ($0.cardID, $0) }),
            date: \.updatedAt
        )
        return .init(additions: additions, changes: changes, conflicts: conflicts, skipped: skipped, removals: removals)
    }

    private static func merge(
        _ incoming: PortableCollectionDocument,
        into current: PortableCollectionDocument,
        in database: Database
    ) throws {
        let currentOwnership = Dictionary(uniqueKeysWithValues: current.ownership.map { ("\($0.cardID)|\($0.variant.rawValue)", $0) })
        for item in incoming.ownership {
            if let saved = currentOwnership["\(item.cardID)|\(item.variant.rawValue)"],
               item.updatedAt <= saved.updatedAt {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO collectionVariant (cardID, variant, quantity, updatedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(cardID, variant) DO UPDATE SET quantity = excluded.quantity, updatedAt = excluded.updatedAt
                """,
                arguments: [item.cardID, item.variant.rawValue, item.quantity, item.updatedAt]
            )
        }

        let currentPreferences = Dictionary(uniqueKeysWithValues: current.setPreferences.map { ($0.setID, $0) })
        let encoder = JSONEncoder()
        for item in incoming.setPreferences {
            if let saved = currentPreferences[item.setID], item.updatedAt <= saved.updatedAt {
                continue
            }
            let variantsJSON = String(data: try encoder.encode(item.includedVariants.map(\.rawValue).sorted()), encoding: .utf8)
            try database.execute(
                sql: """
                INSERT INTO collectionSetPreference (setID, goal, status, includedVariantsJSON, includesSecretCards, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(setID) DO UPDATE SET goal = excluded.goal, status = excluded.status,
                    includedVariantsJSON = excluded.includedVariantsJSON,
                    includesSecretCards = excluded.includesSecretCards, updatedAt = excluded.updatedAt
                """,
                arguments: [item.setID, item.goal.rawValue, item.status.rawValue, variantsJSON, item.includesSecretCards, item.updatedAt]
            )
        }

        let currentFolders = Dictionary(uniqueKeysWithValues: current.folders.map { ($0.id, $0) })
        for item in incoming.folders {
            if let saved = currentFolders[item.id], item.updatedAt <= saved.updatedAt {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO customCollectionFolder (id, name, cardNameQuery, displayMode, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, cardNameQuery = excluded.cardNameQuery,
                    displayMode = excluded.displayMode, updatedAt = excluded.updatedAt
                """,
                arguments: [item.id.uuidString, item.name, item.cardNameQuery, item.displayMode.rawValue, item.createdAt, item.updatedAt]
            )
        }

        let currentMetadata = Dictionary(uniqueKeysWithValues: current.cardMetadata.map { ($0.cardID, $0) })
        for item in incoming.cardMetadata {
            if let saved = currentMetadata[item.cardID], item.updatedAt <= saved.updatedAt {
                continue
            }
            try database.execute(
                sql: """
                INSERT INTO collectionCardMetadata (cardID, isWishlisted, notes, updatedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(cardID) DO UPDATE SET isWishlisted = excluded.isWishlisted,
                    notes = excluded.notes, updatedAt = excluded.updatedAt
                """,
                arguments: [item.cardID, item.isWishlisted, item.notes, item.updatedAt]
            )
        }
    }

    private static func insertBackup(
        _ backup: CollectionBackup,
        payload: CollectionBackupPayload,
        in database: Database
    ) throws {
        guard let payloadJSON = String(
            data: try JSONEncoder().encode(payload),
            encoding: .utf8
        ) else {
            throw CollectionRepositoryError.invalidBackup
        }
        try database.execute(
            sql: """
            INSERT INTO collectionBackup (id, createdAt, reason, payloadJSON)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [backup.id.uuidString, backup.createdAt, backup.reason, payloadJSON]
        )
    }

    private static func applySnapshot(
        _ payload: CollectionBackupPayload,
        in database: Database
    ) throws {
        try database.execute(sql: "DELETE FROM collectionVariant")
        try database.execute(sql: "DELETE FROM collectionSetPreference")
        try database.execute(sql: "DELETE FROM customCollectionFolder")
        try database.execute(sql: "DELETE FROM collectionCardMetadata")

        for item in payload.variants {
            try database.execute(
                sql: """
                INSERT INTO collectionVariant (cardID, variant, quantity, updatedAt)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [item.cardID, item.variant, item.quantity, item.updatedAt]
            )
        }
        for item in payload.preferences {
            try database.execute(
                sql: """
                INSERT INTO collectionSetPreference
                    (setID, goal, status, includedVariantsJSON, includesSecretCards, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.setID,
                    item.goal,
                    item.status,
                    item.includedVariantsJSON,
                    item.includesSecretCards,
                    item.updatedAt,
                ]
            )
        }
        for item in payload.folders {
            try database.execute(
                sql: """
                INSERT INTO customCollectionFolder
                    (id, name, cardNameQuery, displayMode, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id,
                    item.name,
                    item.cardNameQuery,
                    item.displayMode,
                    item.createdAt,
                    item.updatedAt,
                ]
            )
        }
        for item in payload.metadata {
            try database.execute(
                sql: """
                INSERT INTO collectionCardMetadata (cardID, isWishlisted, notes, updatedAt)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [item.cardID, item.isWishlisted, item.notes, item.updatedAt]
            )
        }
    }

    private static func pruneBackups(in database: Database) throws {
        try database.execute(
            sql: """
            DELETE FROM collectionBackup
            WHERE id NOT IN (
                SELECT id FROM collectionBackup
                ORDER BY createdAt DESC, id DESC
                LIMIT 10
            )
            """
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
        guard let goal = CollectionGoal.migrated(persistedValue: rawGoal),
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
            rawVariants = [CatalogVariantKind.normal.rawValue]
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

private struct CollectionBackupPayload: Codable {
    struct Variant: Codable, Equatable {
        let cardID: String
        let variant: String
        let quantity: Int
        let updatedAt: Date
    }

    struct Preference: Codable, Equatable {
        let setID: String
        let goal: String
        let status: String
        let includedVariantsJSON: String?
        let includesSecretCards: Bool
        let updatedAt: Date
    }

    struct Folder: Codable, Equatable {
        let id: String
        let name: String
        let cardNameQuery: String
        let displayMode: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct Metadata: Codable, Equatable {
        let cardID: String
        let isWishlisted: Bool
        let notes: String
        let updatedAt: Date
    }

    let variants: [Variant]
    let preferences: [Preference]
    let folders: [Folder]
    let metadata: [Metadata]
}
