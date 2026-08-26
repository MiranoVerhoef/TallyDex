import Foundation
import XCTest
@testable import TallyDex

final class CollectionFoundationTests: XCTestCase {
    func testRepositoryTracksVariantQuantitiesIndependently() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let firstUpdate = Date(timeIntervalSince1970: 100)
        let secondUpdate = Date(timeIntervalSince1970: 200)

        try await repository.setQuantity(
            2,
            cardID: "sm115-2",
            variant: .normal,
            updatedAt: firstUpdate
        )
        try await repository.setQuantity(
            1,
            cardID: "sm115-2",
            variant: .reverseHolo,
            updatedAt: secondUpdate
        )

        let entries = try await repository.fetchEntries(cardID: "sm115-2")
        let ownedEntries = try await repository.fetchOwnedEntries()
        XCTAssertEqual(Set(entries.map(\.variant)), [.normal, .reverseHolo])
        XCTAssertEqual(entries.first(where: { $0.variant == .normal })?.quantity, 2)
        XCTAssertEqual(entries.first(where: { $0.variant == .reverseHolo })?.quantity, 1)
        XCTAssertEqual(entries.first(where: { $0.variant == .reverseHolo })?.updatedAt, secondUpdate)
        XCTAssertEqual(Set(ownedEntries.map(\.variant)), [.normal, .reverseHolo])
    }

    func testZeroQuantityRemovesOnlyRequestedVariant() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        try await repository.setQuantity(2, cardID: "base1-4", variant: .normal, updatedAt: update)
        try await repository.setQuantity(1, cardID: "base1-4", variant: .holo, updatedAt: update)

        try await repository.setQuantity(0, cardID: "base1-4", variant: .normal, updatedAt: update)

        let entries = try await repository.fetchEntries(cardID: "base1-4")
        XCTAssertEqual(entries.map(\.variant), [.holo])
        XCTAssertEqual(entries.first?.quantity, 1)
    }

    func testNegativeQuantityIsRejectedWithoutChangingSavedValue() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        try await repository.setQuantity(2, cardID: "xy12-4", variant: .normal, updatedAt: update)

        do {
            try await repository.setQuantity(-1, cardID: "xy12-4", variant: .normal, updatedAt: update)
            XCTFail("Expected an invalid quantity error")
        } catch {
            XCTAssertEqual(error as? CollectionRepositoryError, .invalidQuantity)
        }

        let entries = try await repository.fetchEntries(cardID: "xy12-4")
        XCTAssertEqual(entries.first?.quantity, 2)
    }

    @MainActor
    func testCollectionStoreReloadsPersistedQuantities() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let firstStore = CollectionStore(repository: repository)
        try await firstStore.setQuantity(3, cardID: "sv03.5-011", variant: .reverseHolo)

        let relaunchedStore = CollectionStore(repository: repository)
        let quantities = try await relaunchedStore.quantities(for: "sv03.5-011")

        XCTAssertEqual(quantities[.reverseHolo], 3)
    }

    @MainActor
    func testSimpleCheckmarkCanRemoveEveryOwnedPrinting() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let store = CollectionStore(repository: repository)
        try await store.setQuantity(2, cardID: "pl1-53", variant: .normal)
        try await store.setQuantity(1, cardID: "pl1-53", variant: .prereleaseStaff)

        try await store.removeAllOwnership(cardID: "pl1-53")

        let entries = try await repository.fetchEntries(cardID: "pl1-53")
        XCTAssertFalse(store.owns(cardID: "pl1-53"))
        XCTAssertEqual(entries, [])
    }

    @MainActor
    func testCollectionStoreKeepsOwnershipIndexesInSync() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        try await repository.setQuantity(
            2,
            cardID: "sv-test-001",
            variant: .normal,
            updatedAt: .now
        )
        let store = CollectionStore(repository: repository)
        await store.start()

        XCTAssertTrue(store.owns(cardID: "sv-test-001"))
        XCTAssertEqual(store.ownedCardIDs, Set(["sv-test-001"]))
        XCTAssertEqual(store.entries(for: "sv-test-001").first?.quantity, 2)

        try await store.setQuantity(1, cardID: "sv-test-001", variant: .reverseHolo)
        XCTAssertEqual(Set(store.entries(for: "sv-test-001").map(\.variant)), [.normal, .reverseHolo])

        try await store.removeAllOwnership(cardID: "sv-test-001")
        XCTAssertFalse(store.owns(cardID: "sv-test-001"))
        XCTAssertTrue(store.ownedCardIDs.isEmpty)
        XCTAssertTrue(store.entries(for: "sv-test-001").isEmpty)
    }

    func testSetGoalPersistsWithoutChangingOwnership() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        try await repository.setQuantity(1, cardID: "me01-001", variant: .normal, updatedAt: update)

        try await repository.setGoal(.master, setID: "me01", updatedAt: update)

        let goals = try await repository.fetchSetGoals()
        let entries = try await repository.fetchEntries(cardID: "me01-001")
        XCTAssertEqual(goals["me01"], .master)
        XCTAssertEqual(entries.first?.quantity, 1)
    }

    func testAutomaticBackupRestoresEntireCollectionAndCreatesSafetyBackup() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let folderID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let before = Date(timeIntervalSince1970: 100)
        let after = Date(timeIntervalSince1970: 200)

        try await repository.setQuantity(1, cardID: "me01-001", variant: .normal, updatedAt: before)
        try await repository.saveSetPreference(
            SetCollectionPreference(
                setID: "me01",
                status: .collecting,
                goal: .custom,
                includedVariants: [.reverseHolo],
                includesSecretCards: false,
                updatedAt: before
            )
        )
        try await repository.saveCustomFolder(
            CustomCollectionFolder(
                id: folderID,
                name: "Before",
                cardNameQuery: "Lucario",
                displayMode: .allMatching,
                createdAt: before,
                updatedAt: before
            )
        )
        try await repository.saveCardMetadata(
            CardCollectionMetadata(
                cardID: "me01-001",
                isWishlisted: false,
                notes: "Before",
                updatedAt: before
            )
        )
        let backup = try await repository.createBackup(
            reason: "Test Set: Custom → Master",
            createdAt: before
        )

        try await repository.setQuantity(0, cardID: "me01-001", variant: .normal, updatedAt: after)
        try await repository.setQuantity(3, cardID: "me01-001", variant: .holo, updatedAt: after)
        try await repository.saveSetPreference(
            SetCollectionPreference(
                setID: "me01",
                status: .hidden,
                goal: .master,
                includedVariants: Set(CatalogVariantKind.allCases),
                includesSecretCards: true,
                updatedAt: after
            )
        )
        try await repository.saveCustomFolder(
            CustomCollectionFolder(
                id: folderID,
                name: "After",
                cardNameQuery: "Riolu",
                displayMode: .ownedOnly,
                createdAt: before,
                updatedAt: after
            )
        )
        try await repository.saveCardMetadata(
            CardCollectionMetadata(
                cardID: "me01-001",
                isWishlisted: true,
                notes: "After",
                updatedAt: after
            )
        )

        try await repository.restoreBackup(
            id: backup.id,
            safetyBackupReason: "Before restore",
            restoredAt: after
        )

        let restoredEntries = try await repository.fetchEntries(cardID: "me01-001")
        let restoredPreferences = try await repository.fetchSetPreferences()
        let restoredFolders = try await repository.fetchCustomFolders()
        let restoredMetadata = try await repository.fetchCardMetadata(cardID: "me01-001")
        XCTAssertEqual(restoredEntries.map(\.variant), [.normal])
        XCTAssertEqual(restoredPreferences["me01"]?.goal, .custom)
        XCTAssertEqual(restoredPreferences["me01"]?.includedVariants, [.reverseHolo])
        XCTAssertEqual(restoredFolders.first?.name, "Before")
        XCTAssertEqual(restoredMetadata.notes, "Before")
        let backups = try await repository.fetchBackups()
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(backups.first?.reason, "Before restore")
    }

    func testCustomFolderPersistsAndCanBeEdited() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let folder = CustomCollectionFolder(
            id: id,
            name: "All Lucario",
            cardNameQuery: "Lucario",
            displayMode: .allMatching,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try await repository.saveCustomFolder(folder)

        let edited = CustomCollectionFolder(
            id: id,
            name: "Owned Lucario",
            cardNameQuery: "Lucario",
            displayMode: .ownedOnly,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try await repository.saveCustomFolder(edited)

        let savedFolders = try await repository.fetchCustomFolders()
        XCTAssertEqual(savedFolders, [edited])
    }

    func testDeletingCustomFolderDoesNotDeleteOwnedCards() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        let folder = CustomCollectionFolder(
            id: UUID(),
            name: "Lucario",
            cardNameQuery: "Lucario",
            displayMode: .allMatching,
            createdAt: update,
            updatedAt: update
        )
        try await repository.setQuantity(1, cardID: "sv06-113", variant: .normal, updatedAt: update)
        try await repository.saveCustomFolder(folder)

        try await repository.deleteCustomFolder(id: folder.id)

        let savedFolders = try await repository.fetchCustomFolders()
        let ownedEntries = try await repository.fetchEntries(cardID: "sv06-113")
        XCTAssertTrue(savedFolders.isEmpty)
        XCTAssertEqual(ownedEntries.first?.quantity, 1)
    }

    func testCustomFolderRequiresNameAndCardRule() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        let folder = CustomCollectionFolder(
            id: UUID(),
            name: "  ",
            cardNameQuery: "Lucario",
            displayMode: .allMatching,
            createdAt: update,
            updatedAt: update
        )

        do {
            try await repository.saveCustomFolder(folder)
            XCTFail("Expected an invalid custom folder error")
        } catch {
            XCTAssertEqual(error as? CollectionRepositoryError, .invalidCustomFolder)
        }
    }

    @MainActor
    func testCollectionStoreDefaultsToNormalGoal() async throws {
        let defaults = UserDefaults.standard
        let previousGoal = defaults.object(forKey: CollectionSettings.defaultGoalKey)
        defaults.set(CollectionGoal.normal.rawValue, forKey: CollectionSettings.defaultGoalKey)
        defer {
            if let previousGoal {
                defaults.set(previousGoal, forKey: CollectionSettings.defaultGoalKey)
            } else {
                defaults.removeObject(forKey: CollectionSettings.defaultGoalKey)
            }
        }
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let store = CollectionStore(repository: repository)

        XCTAssertEqual(store.goal(for: "sv01"), .normal)
        try await store.setGoal(.master, for: "sv01")
        XCTAssertEqual(store.goal(for: "sv01"), .master)
    }

    @MainActor
    func testCollectionStoreReloadsCustomFolders() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        let folder = CustomCollectionFolder(
            id: UUID(),
            name: "Lucario",
            cardNameQuery: "Lucario",
            displayMode: .allMatching,
            createdAt: update,
            updatedAt: update
        )
        try await repository.saveCustomFolder(folder)

        let store = CollectionStore(repository: repository)
        await store.start()

        XCTAssertEqual(store.customFolders, [folder])
    }

    func testSetPreferencePersistsTrackingGoalAndCustomRules() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let preference = SetCollectionPreference(
            setID: "sv03.5",
            status: .hidden,
            goal: .custom,
            includedVariants: [.normal, .reverseHolo],
            includesSecretCards: true,
            updatedAt: Date(timeIntervalSince1970: 500)
        )

        try await repository.saveSetPreference(preference)

        let preferences = try await repository.fetchSetPreferences()
        XCTAssertEqual(preferences["sv03.5"], preference)
    }

    func testRemovingSetPreferencePreservesOwnership() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 500)
        try await repository.setQuantity(1, cardID: "sv03.5-001", variant: .normal, updatedAt: update)
        try await repository.saveSetPreference(
            SetCollectionPreference(
                setID: "sv03.5",
                status: .collecting,
                goal: .normal,
                includedVariants: [.normal],
                includesSecretCards: true,
                updatedAt: update
            )
        )

        try await repository.deleteSetPreference(setID: "sv03.5")

        let preferences = try await repository.fetchSetPreferences()
        let entries = try await repository.fetchEntries(cardID: "sv03.5-001")
        XCTAssertNil(preferences["sv03.5"])
        XCTAssertEqual(entries.first?.quantity, 1)
    }

    @MainActor
    func testCollectionStoreExposesMySetsAndHiddenStatus() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let store = CollectionStore(repository: repository)
        let update = Date(timeIntervalSince1970: 500)

        try await store.saveSetPreference(
            SetCollectionPreference(
                setID: "sv01",
                status: .collecting,
                goal: .normal,
                includedVariants: [.normal],
                includesSecretCards: false,
                updatedAt: update
            )
        )
        try await store.saveSetPreference(
            SetCollectionPreference(
                setID: "sv02",
                status: .hidden,
                goal: .master,
                includedVariants: [.normal],
                includesSecretCards: true,
                updatedAt: update
            )
        )

        XCTAssertEqual(store.trackingStatus(for: "sv01"), .collecting)
        XCTAssertEqual(store.trackingStatus(for: "sv02"), .hidden)
        XCTAssertEqual(store.trackingStatus(for: "sv03"), .notCollecting)
    }

    func testWishlistAndNotesPersistTogether() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let metadata = CardCollectionMetadata(
            cardID: "sv03.5-001",
            isWishlisted: true,
            notes: "Need a clean binder copy.",
            updatedAt: Date(timeIntervalSince1970: 600)
        )

        try await repository.saveCardMetadata(metadata)

        let saved = try await repository.fetchCardMetadata(cardID: metadata.cardID)
        let missing = try await repository.fetchCardMetadata(cardID: "missing")
        XCTAssertEqual(saved, metadata)
        XCTAssertEqual(missing, .empty(cardID: "missing"))
    }

    func testGoalAwareProgressSeparatesNormalAndMaster() {
        let set = CatalogSet(
            id: "sv-test",
            seriesID: "sv",
            name: "Test Set",
            abbreviation: "TST",
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 2,
            totalCardCount: 3,
            releaseDate: "2026-01-01",
            rarityCounts: nil
        )
        let cards = [
            card(id: "sv-test-001", number: "001"),
            card(id: "sv-test-002", number: "002"),
            card(id: "sv-test-003", number: "003"),
        ]
        let owned = [
            CollectionVariantEntry(
                cardID: cards[0].id,
                variant: .normal,
                quantity: 1,
                updatedAt: .now
            ),
            CollectionVariantEntry(
                cardID: cards[0].id,
                variant: .reverseHolo,
                quantity: 1,
                updatedAt: .now
            ),
        ]
        let variants: [String: Swift.Set<CatalogVariantKind>] = Dictionary(
            uniqueKeysWithValues: cards.map {
                ($0.id, Swift.Set([CatalogVariantKind.normal, CatalogVariantKind.reverseHolo]))
            }
        )

        let normal = CollectionProgressCalculator.progress(
            cards: cards,
            set: set,
            preference: preference(setID: set.id, goal: .normal),
            availableVariants: variants,
            ownedEntries: owned
        )
        let master = CollectionProgressCalculator.progress(
            cards: cards,
            set: set,
            preference: preference(setID: set.id, goal: .master),
            availableVariants: variants,
            ownedEntries: owned
        )

        XCTAssertEqual(normal, CollectionProgress(completedSlots: 1, requiredSlots: 3))
        XCTAssertEqual(master, CollectionProgress(completedSlots: 2, requiredSlots: 6))

        let perCard = CollectionProgressCalculator.progressByCardID(
            cards: cards,
            set: set,
            preference: preference(setID: set.id, goal: .master),
            availableVariants: variants,
            ownedEntries: owned
        )
        XCTAssertEqual(
            perCard[cards[0].id],
            CollectionProgress(completedSlots: 2, requiredSlots: 2)
        )
        XCTAssertEqual(
            perCard[cards[1].id],
            CollectionProgress(completedSlots: 0, requiredSlots: 2)
        )
        XCTAssertEqual(CollectionProgressCalculator.combined(perCard), master)
    }

    func testGoalAwareProgressAppliesCustomRules() {
        let set = CatalogSet(
            id: "sv-test",
            seriesID: "sv",
            name: "Test Set",
            abbreviation: "TST",
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 2,
            totalCardCount: 3,
            releaseDate: "2026-01-01",
            rarityCounts: nil
        )
        let cards = [
            card(id: "sv-test-001", number: "001"),
            card(id: "sv-test-002", number: "002"),
            card(id: "sv-test-003", number: "003"),
        ]
        let variants: [String: Swift.Set<CatalogVariantKind>] = [
            cards[0].id: [.normal, .holo, .reverseHolo],
            cards[1].id: [.normal, .holo],
            cards[2].id: [.normal, .reverseHolo],
        ]
        let owned = [
            CollectionVariantEntry(cardID: cards[0].id, variant: .holo, quantity: 1, updatedAt: .now),
            CollectionVariantEntry(cardID: cards[0].id, variant: .reverseHolo, quantity: 1, updatedAt: .now),
            CollectionVariantEntry(cardID: cards[1].id, variant: .holo, quantity: 1, updatedAt: .now),
            CollectionVariantEntry(cardID: cards[2].id, variant: .normal, quantity: 1, updatedAt: .now),
        ]
        let custom = CollectionProgressCalculator.progress(
            cards: cards,
            set: set,
            preference: SetCollectionPreference(
                setID: set.id,
                status: .collecting,
                goal: .custom,
                includedVariants: [.reverseHolo],
                includesSecretCards: false,
                updatedAt: .now
            ),
            availableVariants: variants,
            ownedEntries: owned
        )

        XCTAssertEqual(custom, CollectionProgress(completedSlots: 1, requiredSlots: 1))
    }

    func testGoalChoicesAndLegacyMigration() {
        XCTAssertEqual(CollectionGoal.allCases, [.normal, .master, .custom])
        XCTAssertEqual(CollectionGoal.migrated(persistedValue: "main"), .normal)
        XCTAssertEqual(CollectionGoal.migrated(persistedValue: "complete"), .normal)
        XCTAssertEqual(CollectionGoal.migrated(persistedValue: "holoChase"), .custom)
        XCTAssertEqual(CollectionGoal.migrated(persistedValue: "master"), .master)
        XCTAssertNil(CollectionGoal.migrated(persistedValue: "unknown"))
    }

    func testGoalRulesDoNotRetainCustomConfigurationWhenSwitching() {
        let customRules = SetCollectionPreference(
            setID: "me01",
            status: .collecting,
            goal: .master,
            includedVariants: [.reverseHolo],
            includesSecretCards: false,
            updatedAt: .now
        )

        let master = customRules.applyingCanonicalGoalRules()
        XCTAssertEqual(master.includedVariants, Set(CatalogVariantKind.allCases))
        XCTAssertTrue(master.includesSecretCards)

        let normal = SetCollectionPreference(
            setID: "me01",
            status: .collecting,
            goal: .normal,
            includedVariants: [.holo, .reverseHolo],
            includesSecretCards: false,
            updatedAt: .now
        ).applyingCanonicalGoalRules()
        XCTAssertEqual(normal.includedVariants, [.normal])
        XCTAssertTrue(normal.includesSecretCards)
    }

    func testMultipleCopyTrackingDefaultsOff() {
        XCTAssertFalse(CollectionSettings.allowsMultipleCopiesDefault)
    }

    func testDefaultMasterPreferenceStartsWithEveryPrintingType() {
        let preference = SetCollectionPreference.defaultPreference(
            setID: "me04",
            goal: .master
        )

        XCTAssertEqual(preference.goal, .master)
        XCTAssertEqual(preference.includedVariants, Set(CatalogVariantKind.allCases))
        XCTAssertTrue(preference.includesSecretCards)
    }

    func testDefaultCustomPreferenceUsesConfiguredRules() {
        let preference = SetCollectionPreference.defaultPreference(
            setID: "me04",
            goal: .custom,
            customVariants: [.holo, .reverseHolo],
            customIncludesSecretCards: false
        )

        XCTAssertEqual(preference.includedVariants, [.holo, .reverseHolo])
        XCTAssertFalse(preference.includesSecretCards)
    }

    func testNormalHidesExtraPrintingTypesWithoutDiscardingThem() {
        let knownVariants: Set<CatalogVariantKind> = [.normal, .reverseHolo, .holo]
        let normal = SetCollectionPreference.defaultPreference(setID: "me04", goal: .normal)
        let master = SetCollectionPreference.defaultPreference(setID: "me04", goal: .master)

        XCTAssertEqual(normal.visibleVariants(in: knownVariants), [.normal])
        XCTAssertEqual(master.visibleVariants(in: knownVariants), knownVariants)
    }

    func testPortableBackupRoundTripPreservesEveryCollectionRecord() async throws {
        let source = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let destination = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let update = Date(timeIntervalSince1970: 100)
        let folderID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        try await source.setQuantity(2, cardID: "me01-001", variant: .reverseHolo, updatedAt: update)
        try await source.saveSetPreference(.init(
            setID: "me01", status: .hidden, goal: .custom,
            includedVariants: [.holo, .reverseHolo], includesSecretCards: false, updatedAt: update
        ))
        try await source.saveCustomFolder(.init(
            id: folderID, name: "Lucario", cardNameQuery: "Lucario", displayMode: .ownedOnly,
            createdAt: update, updatedAt: update
        ))
        try await source.saveCardMetadata(.init(
            cardID: "me01-001", isWishlisted: true, notes: "Binder page 3", updatedAt: update
        ))

        let exported = try await source.exportCollection(exportedAt: update, appVersion: "0.4.0 (15)")
        let data = try CollectionTransferCodec.encode(exported)
        let decoded = try CollectionTransferCodec.decode(data)
        XCTAssertEqual(decoded, exported)

        try await destination.importCollection(decoded, mode: .replace, importedAt: update.addingTimeInterval(1))
        let entries = try await destination.fetchEntries(cardID: "me01-001")
        let preferences = try await destination.fetchSetPreferences()
        let folders = try await destination.fetchCustomFolders()
        let metadata = try await destination.fetchCardMetadata(cardID: "me01-001")
        XCTAssertEqual(entries.first?.quantity, 2)
        XCTAssertEqual(preferences["me01"]?.includedVariants, [.holo, .reverseHolo])
        XCTAssertEqual(folders.first?.id, folderID)
        XCTAssertEqual(metadata.notes, "Binder page 3")
    }

    func testMergeIsIdempotentAndKeepsNewerLocalConflict() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        try await repository.setQuantity(3, cardID: "me01-002", variant: .holo, updatedAt: newer)
        let document = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: PortableCollectionDocument.currentSchemaVersion,
            exportedAt: older,
            appVersion: "0.4.0 (15)",
            ownership: [
                .init(cardID: "me01-001", variant: .normal, quantity: 1, updatedAt: older),
                .init(cardID: "me01-002", variant: .holo, quantity: 1, updatedAt: older),
            ],
            setPreferences: [], folders: [], cardMetadata: []
        )

        let preview = try await repository.previewImport(document, mode: .merge)
        XCTAssertEqual(preview.additions, 1)
        XCTAssertEqual(preview.conflicts, 1)
        try await repository.importCollection(document, mode: .merge, importedAt: newer.addingTimeInterval(1))
        try await repository.importCollection(document, mode: .merge, importedAt: newer.addingTimeInterval(2))

        let addedEntries = try await repository.fetchEntries(cardID: "me01-001")
        let conflictedEntries = try await repository.fetchEntries(cardID: "me01-002")
        let backups = try await repository.fetchBackups()
        XCTAssertEqual(addedEntries.first?.quantity, 1)
        XCTAssertEqual(conflictedEntries.first?.quantity, 3)
        XCTAssertEqual(backups.count, 1)
    }

    func testReplacePreviewReportsRemovalsAndCreatesRollbackBackup() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let before = Date(timeIntervalSince1970: 100)
        let importedAt = Date(timeIntervalSince1970: 200)
        try await repository.setQuantity(1, cardID: "old-card", variant: .normal, updatedAt: before)
        let empty = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: PortableCollectionDocument.currentSchemaVersion,
            exportedAt: importedAt,
            appVersion: "0.4.0 (15)",
            ownership: [], setPreferences: [], folders: [], cardMetadata: []
        )

        let preview = try await repository.previewImport(empty, mode: .replace)
        XCTAssertEqual(preview.removals, 1)
        try await repository.importCollection(empty, mode: .replace, importedAt: importedAt)
        let emptyEntries = try await repository.fetchOwnedEntries()
        XCTAssertTrue(emptyEntries.isEmpty)

        let backups = try await repository.fetchBackups()
        let rollback = try XCTUnwrap(backups.first)
        try await repository.restoreBackup(
            id: rollback.id,
            safetyBackupReason: "Before rollback",
            restoredAt: importedAt.addingTimeInterval(1)
        )
        let restoredEntries = try await repository.fetchEntries(cardID: "old-card")
        XCTAssertEqual(restoredEntries.first?.quantity, 1)
    }

    func testCSVQuotesNotesAndIncludesEveryRecordType() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let document = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: 1,
            exportedAt: date,
            appVersion: "0.4.0 (15)",
            ownership: [.init(cardID: "card-1", variant: .normal, quantity: 1, updatedAt: date)],
            setPreferences: [.init(
                setID: "set-1", status: .collecting, goal: .normal,
                includedVariants: [.normal], includesSecretCards: true, updatedAt: date
            )],
            folders: [.init(
                id: UUID(), name: "Favorites", cardNameQuery: "Lucario", displayMode: .allMatching,
                createdAt: date, updatedAt: date
            )],
            cardMetadata: [.init(cardID: "card-1", isWishlisted: true, notes: "Mint, signed", updatedAt: date)]
        )
        let csv = String(decoding: CollectionTransferCodec.csv(document), as: UTF8.self)
        XCTAssertTrue(csv.contains("ownership"))
        XCTAssertTrue(csv.contains("set_preference"))
        XCTAssertTrue(csv.contains("folder"))
        XCTAssertTrue(csv.contains("card_metadata"))
        XCTAssertTrue(csv.contains("\"Mint, signed\""))
    }

    func testLocalHTTPRequestParsesEncodedValuesCookiesAndBodyLength() throws {
        let body = "code=123456&note=Binder+page+%233"
        let raw = """
        POST /api/cards/SM%2095/metadata?q=Lucario%20Staff HTTP/1.1\r
        Host: tallydex.local\r
        Cookie: tallydex_session=abc123; theme=light\r
        Content-Type: application/x-www-form-urlencoded\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        let request = try XCTUnwrap(LocalHTTPRequest.parse(Data(raw.utf8)))

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/api/cards/SM 95/metadata")
        XCTAssertEqual(request.query["q"], "Lucario Staff")
        XCTAssertEqual(request.cookies["tallydex_session"], "abc123")
        XCTAssertEqual(request.cookies["theme"], "light")
        XCTAssertEqual(request.formValues["code"], "123456")
        XCTAssertEqual(request.formValues["note"], "Binder page #3")
        XCTAssertEqual(LocalHTTPRequest.expectedByteCount(in: Data(raw.utf8)), raw.utf8.count)
    }

    func testLocalHTTPResponseAddsSecurityAndNoStoreHeaders() throws {
        let response = LocalHTTPResponse.html("<h1>TallyDex</h1>")
        let encoded = try XCTUnwrap(String(data: response.encoded, encoding: .utf8))

        XCTAssertTrue(encoded.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(encoded.contains("Cache-Control: no-store\r\n"))
        XCTAssertTrue(encoded.contains("Connection: close\r\n"))
        XCTAssertTrue(encoded.contains("Content-Length: 17\r\n"))
        XCTAssertTrue(encoded.contains("X-Content-Type-Options: nosniff\r\n"))
        XCTAssertTrue(encoded.contains("X-Frame-Options: DENY\r\n"))
        XCTAssertTrue(encoded.contains("Referrer-Policy: no-referrer\r\n"))
        XCTAssertTrue(encoded.hasSuffix("\r\n\r\n<h1>TallyDex</h1>"))
    }

    private func card(id: String, number: String) -> CatalogCard {
        CatalogCard(
            id: id,
            setID: "sv-test",
            localID: number,
            name: "Test Card",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
    }

    private func preference(setID: String, goal: CollectionGoal) -> SetCollectionPreference {
        SetCollectionPreference(
            setID: setID,
            status: .collecting,
            goal: goal,
            includedVariants: [.normal, .holo, .reverseHolo],
            includesSecretCards: true,
            updatedAt: .now
        )
    }
}
