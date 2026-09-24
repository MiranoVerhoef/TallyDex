import Foundation
import XCTest
@testable import TallyDex

final class CollectionFoundationTests: XCTestCase {
    func testCollectionFiltersDoNotHideUnknownMetadataByDefault() {
        let unknown = filterResult(id: "unknown", setID: "unknown-set", types: nil, rarity: nil, date: nil)
        let all = CollectionCardFilters()
        XCTAssertTrue(all.matches(unknown, seriesID: nil, isOwned: false, progress: .init(completedSlots: 0, requiredSlots: 1)))
        XCTAssertEqual(all.activeCount(defaultOwnership: .all), 0)
        var type = all
        type.type = "Grass"
        XCTAssertFalse(type.matches(unknown, seriesID: nil, isOwned: true, progress: .init(completedSlots: 1, requiredSlots: 1)))
        var rarity = all
        rarity.rarity = "Rare"
        XCTAssertFalse(rarity.matches(unknown, seriesID: nil, isOwned: false, progress: .init(completedSlots: 0, requiredSlots: 1)))
    }

    func testCollectionFiltersIntersectWithoutDistinguishingPokemonSuffixes() {
        let matching = filterResult(id: "a", setID: "sv-test", types: [" Grass ", "Psychic"], rarity: "Rare", date: "2024-03-22")
        let filters = CollectionCardFilters(type: "grass", seriesID: "sv", setID: "sv-test", rarity: " rare ", releaseYear: 2024)
        XCTAssertTrue(filters.matches(matching, seriesID: "sv", isOwned: false, progress: .init(completedSlots: 0, requiredSlots: 1)))
        for mismatch in [
            CollectionCardFilters(type: "Fire"), CollectionCardFilters(seriesID: "swsh"),
            CollectionCardFilters(setID: "sv-other"), CollectionCardFilters(rarity: "Common"),
            CollectionCardFilters(releaseYear: 2023)
        ] {
            XCTAssertFalse(mismatch.matches(matching, seriesID: "sv", isOwned: false, progress: .init(completedSlots: 0, requiredSlots: 1)))
        }
        XCTAssertTrue(CollectionCardFilters(type: "Psychic").matches(matching, seriesID: "sv", isOwned: false,
            progress: .init(completedSlots: 0, requiredSlots: 1)))
    }

    func testCollectionFiltersUseSetAndEraIdentityInsteadOfSharedNames() {
        let a = filterResult(id: "a", setID: "swsh-promo", types: [], rarity: nil, date: nil)
        let b = filterResult(id: "b", setID: "sv-promo", types: [], rarity: nil, date: nil)
        XCTAssertEqual(a.setName, b.setName)
        let set = CollectionCardFilters(setID: "swsh-promo")
        XCTAssertTrue(set.matches(a, seriesID: "swsh", isOwned: true, progress: .init(completedSlots: 1, requiredSlots: 1)))
        XCTAssertFalse(set.matches(b, seriesID: "sv", isOwned: true, progress: .init(completedSlots: 1, requiredSlots: 1)))
        XCTAssertFalse(CollectionCardFilters(seriesID: "swsh").matches(b, seriesID: "sv", isOwned: true,
            progress: .init(completedSlots: 1, requiredSlots: 1)))
    }

    func testCollectionFilterOptionsAreScopedToMembersAndPreserveExactSetIDs() {
        func group(_ id: String, sets: [String]) -> CatalogSeriesGroup {
            .init(series: .init(id: id, name: id, logoURL: nil), sets: sets.map {
                .init(id: $0, seriesID: id, name: "Promos", abbreviation: nil, logoURL: nil, symbolURL: nil,
                      officialCardCount: 1, totalCardCount: 1, releaseDate: nil, rarityCounts: nil)
            })
        }
        let options = CollectionCardFilterOptions(matches: [
            filterResult(id: "a", setID: "swsh-promo", types: ["Grass", " grass ", "Psychic"], rarity: " Rare ", date: "2021-01-01"),
            filterResult(id: "b", setID: "sv-promo", types: nil, rarity: "rare", date: "2024-01-01"),
            filterResult(id: "c", setID: "unknown-set", types: [" "], rarity: nil, date: nil)
        ], groups: [group("swsh", sets: ["swsh-promo"]), group("sv", sets: ["sv-promo"]), group("unused", sets: ["unused-set"])])
        XCTAssertEqual(options.types.map(CollectionCardFilters.normalized), ["grass", "psychic"])
        XCTAssertEqual(options.rarities.map(CollectionCardFilters.normalized), ["rare"])
        XCTAssertEqual(options.eras.map(\.id), ["swsh", "sv"])
        XCTAssertEqual(options.sets.count, 3)
        XCTAssertEqual(options.sets(in: "swsh").map(\.id), ["swsh-promo"])
        XCTAssertEqual(options.sets(in: "").count, 3)
        XCTAssertEqual(options.releaseYears, [2024, 2021])
        XCTAssertEqual(options.missingTypeCount, 2)
        XCTAssertEqual(options.missingRarityCount, 1)
    }

    func testCollectionOwnershipFiltersRetainPartialMasterCompletionAndOwnedOnlyDefaults() {
        let card = filterResult(id: "a", setID: "s", types: nil, rarity: nil, date: nil)
        let partial = CollectionProgress(completedSlots: 1, requiredSlots: 2)
        XCTAssertTrue(CollectionCardFilters(ownership: .missing).matches(card, seriesID: nil, isOwned: true, progress: partial))
        XCTAssertTrue(CollectionCardFilters(ownership: .owned).matches(card, seriesID: nil, isOwned: true, progress: partial))
        XCTAssertFalse(CollectionCardFilters(ownership: .owned).matches(card, seriesID: nil, isOwned: false, progress: partial))
        XCTAssertFalse(CollectionCardFilters(ownership: .missing).matches(card, seriesID: nil, isOwned: true,
            progress: .init(completedSlots: 2, requiredSlots: 2)))
        XCTAssertEqual(CollectionCardFilters(ownership: .owned).activeCount(defaultOwnership: .owned), 0)
        XCTAssertEqual(CollectionCardFilters(ownership: .all, type: "Grass", seriesID: "sv", setID: "s", rarity: "Rare", releaseYear: 2024)
            .activeCount(defaultOwnership: .owned), 6)
    }

    func testCollectionCardSortKeepsUnknownDatesLastAndUsesCanonicalTieBreaker() {
        let old = filterResult(id: "a", setID: "s", types: nil, rarity: nil, date: "2021-01-01")
        let new = filterResult(id: "b", setID: "s", types: nil, rarity: nil, date: "2024-01-01")
        let unknown = filterResult(id: "c", setID: "s", types: nil, rarity: nil, date: nil)
        let emptyDate = filterResult(id: "d", setID: "s", types: nil, rarity: nil, date: "")
        XCTAssertEqual([unknown, old, new].sorted(by: CollectionCardSort.releaseNewest.precedes).map(\.id), ["b", "a", "c"])
        XCTAssertEqual([unknown, new, old].sorted(by: CollectionCardSort.releaseOldest.precedes).map(\.id), ["a", "b", "c"])
        XCTAssertEqual([emptyDate, unknown, new, old].sorted(by: CollectionCardSort.releaseNewest.precedes).map(\.id), ["b", "a", "c", "d"])
        XCTAssertEqual([emptyDate, unknown, new, old].sorted(by: CollectionCardSort.releaseOldest.precedes).map(\.id), ["a", "b", "c", "d"])
        for sort in CollectionCardSort.allCases {
            XCTAssertFalse(sort.precedes(old, old))
        }
        XCTAssertEqual([new, old].sorted(by: CollectionCardSort.cardName.precedes).map(\.id), ["a", "b"])
    }

    private func filterResult(
        id: String,
        setID: String,
        types: [String]?,
        rarity: String?,
        date: String?,
        name: String = "Lucario GX",
        dexID: Int = 448,
        localID: String = "1"
    ) -> CatalogCardSearchResult {
        let metadata = types.map {
            CatalogCardMetadata(dexIDs: [dexID], hp: nil, types: $0, evolvesFrom: nil, stage: nil, suffix: nil,
                attacks: [], abilities: [], weaknesses: [], resistances: [], retreatCost: nil, regulationMark: nil,
                legality: nil, rulesText: nil, trainerType: nil, energyType: nil, flavorText: nil, updatedAt: nil)
        }
        return .init(card: CatalogCard(id: id, setID: setID, localID: localID, name: name, imageURL: nil,
            category: "Pokémon", illustrator: nil, rarity: rarity, metadata: metadata), setName: "Promos", setReleaseDate: date)
    }

    func testBinderPlansPersistMultipleValidatedLayouts() throws {
        let suite = "BinderPlanStorageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 100)
        let plans = [
            BinderPlan(
                id: UUID(), name: "Lucario Binder", sourceKind: .collection,
                sourceID: UUID().uuidString, sourceName: "Lucario", pocketLayout: .nine,
                includesMissingCards: true, cardOrder: .pokemonName, createdAt: now, updatedAt: now
            ),
            BinderPlan(
                id: UUID(), name: "Mega Evolution", sourceKind: .set,
                sourceID: "me01", sourceName: "Mega Evolution", pocketLayout: .twelve,
                includesMissingCards: false, cardOrder: .newestRelease,
                createdAt: now, updatedAt: now.addingTimeInterval(1)
            ),
        ]

        try BinderPlanStorage.save(plans, to: defaults)

        XCTAssertEqual(BinderPlanStorage.load(from: defaults), Array(plans.reversed()))

        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode([plans[0]])) as? [[String: Any]]
        )
        legacyJSON[0].removeValue(forKey: "cardOrder")
        defaults.set(try JSONSerialization.data(withJSONObject: legacyJSON), forKey: BinderPlanStorage.key)
        XCTAssertEqual(BinderPlanStorage.load(from: defaults).first?.effectiveCardOrder, .setRelease)

        XCTAssertThrowsError(try BinderPlanStorage.save([
            BinderPlan(
                id: UUID(), name: "", sourceKind: .set, sourceID: "", sourceName: "",
                pocketLayout: .nine, includesMissingCards: true,
                createdAt: now, updatedAt: now
            ),
        ], to: defaults)) { error in
            XCTAssertEqual(error as? CollectionRepositoryError, .invalidBinderPlan)
        }
    }

    func testBinderPocketLayoutsMatchPhysicalBinderFormats() {
        let expected: [(BinderPocketLayout, Int, Int, Int, Int, Int)] = [
            (.four, 2, 2, 20, 4, 160),
            (.nine, 3, 3, 20, 9, 360),
            (.twelve, 3, 4, 20, 12, 480),
            (.twelveXL, 3, 4, 26, 12, 624),
            (.sixteenXXL, 4, 4, 34, 16, 1_088),
        ]

        for (layout, rows, columns, pages, pocketsPerSide, capacity) in expected {
            XCTAssertEqual(layout.rows, rows)
            XCTAssertEqual(layout.columns, columns)
            XCTAssertEqual(layout.doubleSidedPageCount, pages)
            XCTAssertEqual(layout.pocketsPerSide, pocketsPerSide)
            XCTAssertEqual(layout.capacity, capacity)
        }
    }

    func testBinderPocketLayoutDecodesLegacyNumericValues() throws {
        XCTAssertEqual(try JSONDecoder().decode(BinderPocketLayout.self, from: Data("9".utf8)), .nine)
        XCTAssertEqual(try JSONDecoder().decode(BinderPocketLayout.self, from: Data("12".utf8)), .twelve)
    }

    func testBinderPlansTravelThroughExportImportAndBackupRestore() async throws {
        let timestamp = Date(timeIntervalSince1970: 500)
        let original = BinderPlan(
            id: UUID(),
            name: "Vault layout",
            sourceKind: .set,
            sourceID: "me01",
            sourceName: "Mega Evolution",
            pocketLayout: .twelveXL,
            includesMissingCards: true,
            cardOrder: .setRelease,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let repository = GRDBCollectionRepository(database: try .inMemory())
        try await repository.saveBinderPlan(original)
        let backup = try await repository.createBackup(reason: "Binder baseline", createdAt: timestamp)

        let exported = try await repository.exportCollection(exportedAt: timestamp, appVersion: "test")
        XCTAssertEqual(exported.binderPlans, [original])

        let destination = GRDBCollectionRepository(database: try .inMemory())
        try await destination.importCollection(exported, mode: .replace, importedAt: timestamp.addingTimeInterval(1))
        let importedPlans = try await destination.fetchBinderPlans()
        XCTAssertEqual(importedPlans, [original])

        let changed = BinderPlan(
            id: original.id,
            name: "Changed",
            sourceKind: original.sourceKind,
            sourceID: original.sourceID,
            sourceName: original.sourceName,
            pocketLayout: .sixteenXXL,
            includesMissingCards: false,
            cardOrder: .newestRelease,
            createdAt: original.createdAt,
            updatedAt: timestamp.addingTimeInterval(2)
        )
        try await repository.saveBinderPlan(changed)
        try await repository.restoreBackup(
            id: backup.id,
            safetyBackupReason: "Before binder restore",
            restoredAt: timestamp.addingTimeInterval(3)
        )
        let restoredPlans = try await repository.fetchBinderPlans()
        XCTAssertEqual(restoredPlans, [original])
    }

    func testBinderCardOrderSupportsReleaseNameAndPokedexLayouts() {
        let oldest = filterResult(
            id: "oldest", setID: "base", types: ["Grass"], rarity: nil, date: "1999-01-09",
            name: "Bulbasaur", dexID: 1, localID: "44"
        )
        let middle = filterResult(
            id: "middle", setID: "hgss", types: ["Lightning"], rarity: nil, date: "2010-02-10",
            name: "Pikachu", dexID: 25, localID: "70"
        )
        let newest = filterResult(
            id: "newest", setID: "mega", types: ["Fighting"], rarity: nil, date: "2026-08-28",
            name: "Lucario", dexID: 448, localID: "12"
        )
        let mixed = [middle, newest, oldest]

        XCTAssertEqual(BinderPlanOrdering.sorted(mixed, by: .setRelease).map(\.id), ["oldest", "middle", "newest"])
        XCTAssertEqual(BinderPlanOrdering.sorted(mixed, by: .newestRelease).map(\.id), ["newest", "middle", "oldest"])
        XCTAssertEqual(BinderPlanOrdering.sorted(mixed, by: .pokemonName).map(\.id), ["oldest", "newest", "middle"])
        XCTAssertEqual(BinderPlanOrdering.sorted(mixed, by: .pokedexNumber).map(\.id), ["oldest", "middle", "newest"])
    }

    func testBinderLayoutCreatesExactGoalSlotsAndUsesOneBroadFallback() {
        let cardID = "test-001"
        let card = CatalogCard(
            id: cardID, setID: "test", localID: "001", name: "Lucario",
            imageURL: nil, category: "Pokémon", illustrator: nil, rarity: nil
        )
        let set = CatalogSet(
            id: "test", seriesID: "test", name: "Test", abbreviation: nil,
            logoURL: nil, symbolURL: nil, officialCardCount: 1, totalCardCount: 1,
            releaseDate: nil, rarityCounts: nil
        )
        let normalOne = printing(cardID: cardID, id: "normal-one", kind: .normal)
        let normalTwo = printing(cardID: cardID, id: "normal-two", kind: .normal)
        let reverse = printing(cardID: cardID, id: "reverse", kind: .reverseHolo)
        let slots = BinderPlanLayoutBuilder.slots(
            cards: [card],
            set: set,
            preference: preference(setID: set.id, goal: .master),
            availableVariants: [cardID: [.normal, .reverseHolo]],
            availablePrintings: [cardID: [normalOne, normalTwo, reverse]],
            broadOwnedEntries: [
                .init(cardID: cardID, variant: .normal, quantity: 1, updatedAt: .now),
            ],
            exactOwnedEntries: [
                .init(cardID: cardID, printingID: reverse.providerID, variant: .reverseHolo, quantity: 1, updatedAt: .now),
            ]
        )

        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots.filter(\.isOwned).count, 2)
        XCTAssertEqual(slots.filter { $0.variant == .normal && $0.isOwned }.count, 1)
        XCTAssertEqual(slots.first { $0.printingID == reverse.providerID }?.isOwned, true)
    }

    @MainActor
    func testSharedCanonicalPrintingsSurviveDiskRestartMergeReplaceAndRollback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("reliability.sqlite").path
        let cardID = TrickOrTradeRelease.all[0].cardIDs[0]
        let normal = printing(cardID: cardID, id: "normal-exact", kind: .normal)
        let stamp = try XCTUnwrap(TrickOrTradeRelease.all[0].printing(cardID: cardID))
        let first = CollectionStore(repository: GRDBCollectionRepository(database: try CollectionDatabase(path: path)),
                                    now: { Date(timeIntervalSince1970: 100) })
        await first.start()
        try await first.setPrintingQuantity(3, cardID: cardID, printing: normal)
        try await first.setPrintingQuantity(4, cardID: cardID, printing: stamp)
        try await first.saveSetPreference(.init(setID: "swsh8", status: .collecting, goal: .master,
            includedVariants: [.normal, .trickOrTrade], includesSecretCards: true, updatedAt: Date(timeIntervalSince1970: 100)))
        try await first.saveCardMetadata(cardID: cardID, isWishlisted: true, notes: "Original notes")
        for rules in [[PokemonCollectionRule(name: "Phantump")], [.init(name: "Phantump"), .init(name: "Trevenant")]] {
            try await first.saveCustomFolder(.init(id: UUID(), name: rules.map(\.name).joined(separator: " + "),
                cardNameQuery: "Phantump", pokemonRules: rules, displayMode: .allMatching,
                coverCardID: cardID, createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100)))
        }
        let baseline = try await first.exportDocument()
        _ = try await first.createBackup(reason: "Original reliability baseline")
        let incoming = PortableCollectionDocument(format: baseline.format, schemaVersion: baseline.schemaVersion,
            exportedAt: baseline.exportedAt, appVersion: baseline.appVersion, ownership: baseline.ownership,
            setPreferences: baseline.setPreferences, folders: baseline.folders, cardMetadata: baseline.cardMetadata,
            exactOwnership: baseline.exactOwnership + [.init(cardID: "other-1", printingID: "normal-exact",
                variant: .normal, quantity: 2, updatedAt: Date(timeIntervalSince1970: 100))])
        let second = CollectionStore(repository: GRDBCollectionRepository(database: try CollectionDatabase(path: path)),
                                     now: { Date(timeIntervalSince1970: 300) })
        await second.start()
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: normal.providerID), 3)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: stamp.providerID), 4)
        XCTAssertEqual(second.ownedCardIDs, [cardID])
        XCTAssertEqual(second.customFolders.count, 2)
        XCTAssertEqual(second.preference(for: "swsh8").goal, .master)
        let card = CatalogCard(id: cardID, setID: "swsh8", localID: "16", name: "Phantump", imageURL: nil,
            category: "Pokémon", illustrator: nil, rarity: nil)
        let parentSet = CatalogSet(id: "swsh8", seriesID: "swsh", name: "Fusion Strike", abbreviation: nil,
            logoURL: nil, symbolURL: nil, officialCardCount: 1, totalCardCount: 1, releaseDate: nil, rarityCounts: nil)
        for folder in second.customFolders {
            let matching = [card].filter { PokemonRuleSearch.matches(card: $0, rules: folder.effectivePokemonRules) }
            XCTAssertEqual(matching.count, 1)
            let progress = CollectionProgressCalculator.progress(cards: matching, set: parentSet,
                preference: second.preference(for: parentSet.id), availableVariants: [cardID: [.normal]],
                ownedEntries: second.ownedEntries, availablePrintings: [cardID: [normal]],
                exactOwnedEntries: second.exactOwnedEntries)
            XCTAssertEqual(progress, CollectionProgress(completedSlots: 1, requiredSlots: 1))
        }
        let stampProgress = CollectionProgressCalculator.progress(cards: [card], set: TrickOrTradeRelease.all[0].set,
            preference: .defaultPreference(setID: TrickOrTradeRelease.all[0].id, goal: .master),
            availableVariants: [cardID: [.trickOrTrade]], ownedEntries: second.ownedEntries,
            availablePrintings: [cardID: [stamp]], exactOwnedEntries: second.exactOwnedEntries)
        XCTAssertEqual(stampProgress, CollectionProgress(completedSlots: 1, requiredSlots: 1))
        try await second.setPrintingQuantity(7, cardID: cardID, printing: normal)
        try await second.setPrintingQuantity(2, cardID: cardID, printing: stamp)
        try await second.saveCardMetadata(cardID: cardID, isWishlisted: false, notes: "Newer local notes")
        let prepared = try await second.prepareImport(data: CollectionTransferCodec.encode(incoming), filename: "Reliability.pokecollection")
        XCTAssertGreaterThan(prepared.mergePreview.conflicts, 0)
        XCTAssertTrue(prepared.mergePreview.hasChanges)
        try await second.importCollection(prepared, mode: .merge)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: normal.providerID), 7)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: stamp.providerID), 2)
        XCTAssertEqual(second.ownedCardIDs, [cardID, "other-1"])
        let mergedMetadata = try await second.cardMetadata(for: cardID)
        XCTAssertEqual(mergedMetadata.notes, "Newer local notes")
        let freshPreview = try await second.prepareImport(data: CollectionTransferCodec.encode(incoming), filename: "Reliability.pokecollection")
        XCTAssertFalse(freshPreview.mergePreview.hasChanges)
        let backupCount = second.backups.count
        try await second.importCollection(freshPreview, mode: .merge)
        XCTAssertEqual(second.backups.count, backupCount)
        try await second.importCollection(freshPreview, mode: .replace)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: normal.providerID), 3)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: stamp.providerID), 4)
        let replacedMetadata = try await second.cardMetadata(for: cardID)
        XCTAssertEqual(replacedMetadata.notes, "Original notes")
        let rollback = try XCTUnwrap(second.backups.first { $0.reason == "Before replace import" })
        let rollbackPreview = try await second.previewBackupRestore(rollback)
        XCTAssertTrue(rollbackPreview.hasChanges)
        try await second.restoreBackup(rollback)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: normal.providerID), 7)
        XCTAssertEqual(second.printingQuantity(cardID: cardID, printingID: stamp.providerID), 2)
        let beforeMerge = try XCTUnwrap(second.backups.first { $0.reason == "Before merge import" })
        try await second.restoreBackup(beforeMerge)
        XCTAssertEqual(second.ownedCardIDs, [cardID])
        let exported = try await second.exportDocument()
        XCTAssertEqual(exported.exactOwnership.count, 2)
        XCTAssertEqual(Set(exported.exactOwnership.map { "\($0.cardID)|\($0.printingID)" }).count, 2)
        let third = CollectionStore(repository: GRDBCollectionRepository(database: try CollectionDatabase(path: path)))
        await third.start()
        XCTAssertEqual(third.printingQuantity(cardID: cardID, printingID: normal.providerID), 7)
        XCTAssertEqual(third.printingQuantity(cardID: cardID, printingID: stamp.providerID), 2)
        XCTAssertEqual(third.ownedCardIDs, [cardID])
        XCTAssertEqual(third.customFolders.count, 2)
        XCTAssertEqual(third.preference(for: "swsh8").goal, .master)
    }

    @MainActor
    func testTrickOrTradeSharesCanonicalOwnershipWithoutTouchingNormalCopiesAndSurvivesBackup() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let store = CollectionStore(repository: repository)
        await store.start()
        let release = TrickOrTradeRelease.all[0]
        let cardID = release.cardIDs[0]
        let stamped = try XCTUnwrap(release.printing(cardID: cardID))
        try await store.setQuantity(1, cardID: cardID, variant: .normal)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: stamped.providerID), 0)
        try await store.setPrintingQuantity(1, cardID: cardID, printing: stamped)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: stamped.providerID), 1)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .normal), 1)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .trickOrTrade), 1)
        let backup = try await store.createBackup(reason: "Stamped card test")
        let exported = try await store.exportDocument()
        let decoded = try CollectionTransferCodec.decode(CollectionTransferCodec.encode(exported))
        XCTAssertEqual(decoded.exactOwnership.first?.cardID, cardID)
        XCTAssertEqual(decoded.exactOwnership.first?.printingID, stamped.providerID)
        XCTAssertEqual(decoded.exactOwnership.first?.variant, .trickOrTrade)
        try await store.setPrintingQuantity(0, cardID: cardID, printing: stamped)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .normal), 1)
        try await store.restoreBackup(backup)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: stamped.providerID), 1)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .normal), 1)
        XCTAssertEqual(store.ownedCardIDs, [cardID])
    }

    @MainActor
    func testJumboChecklistAndParentCardShareExactOwnership() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let store = CollectionStore(repository: repository)
        await store.start()
        let cardID = "mep-012"
        let jumbo = CatalogPrinting(
            cardID: cardID, providerID: "provider-jumbo", rawType: "holo",
            kind: .jumbo, subtype: nil, size: "jumbo", stamps: [], foil: nil,
            languages: ["en"], cardmarketProductID: 858147,
            tcgplayerProductID: 663178, cardtraderProductID: nil
        )
        let regular = CatalogPrinting(
            cardID: cardID, providerID: "provider-standard", rawType: "holo",
            kind: .holo, subtype: nil, size: "standard", stamps: [], foil: nil,
            languages: ["en"], cardmarketProductID: 858146,
            tcgplayerProductID: 663177, cardtraderProductID: nil
        )

        try await store.setPrintingQuantity(1, cardID: cardID, printing: jumbo)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: jumbo.providerID), 1)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: regular.providerID), 0)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .jumbo), 1)
        XCTAssertEqual(store.quantity(cardID: cardID, variant: .holo), 0)

        try await store.setPrintingQuantity(0, cardID: cardID, printing: jumbo)
        XCTAssertEqual(store.printingQuantity(cardID: cardID, printingID: jumbo.providerID), 0)
    }

    func testExactPrintingProgressRecognizesStableIdentityWhenKindMetadataChanges() throws {
        let release = TrickOrTradeRelease.all[2]
        let id = "sv03-130"
        let stamp = try XCTUnwrap(release.printing(cardID: id))
        let card = CatalogCard(id: id, setID: "sv03", localID: "130", name: "Umbreon", imageURL: nil,
                               category: nil, illustrator: nil, rarity: nil)
        let progress = CollectionProgressCalculator.progress(cards: [card], set: release.set,
            preference: .defaultPreference(setID: release.id, goal: .master),
            availableVariants: [id: [.trickOrTrade]], ownedEntries: [],
            availablePrintings: [id: [stamp]], exactOwnedEntries: [
                .init(cardID: id, printingID: stamp.providerID, variant: .normal, quantity: 1, updatedAt: Date())
            ])
        XCTAssertEqual(progress.completedSlots, 1)
        XCTAssertEqual(progress.requiredSlots, 1)
    }

    func testExactPrintingMigrationMovesOnlyUnambiguousOwnershipAndCanRollback() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let before = Date(timeIntervalSince1970: 100)
        let migration = Date(timeIntervalSince1970: 200)
        try await repository.setQuantity(2, cardID: "base1-4", variant: .holo, updatedAt: before)
        try await repository.prepareExactOwnershipMigration(createdAt: migration)
        try await repository.prepareExactOwnershipMigration(createdAt: migration.addingTimeInterval(1))

        let changed = try await repository.reconcileExactOwnership(
            cardID: "base1-4",
            printings: [printing(cardID: "base1-4", id: "unlimited-holo", kind: .holo)]
        )

        XCTAssertTrue(changed)
        let migratedBroad = try await repository.fetchEntries(cardID: "base1-4")
        let migratedExact = try await repository.fetchPrintingEntries(cardID: "base1-4")
        XCTAssertTrue(migratedBroad.isEmpty)
        XCTAssertEqual(migratedExact.first?.quantity, 2)
        let backups = try await repository.fetchBackups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.reason, "Before printing identity reconciliation")

        try await repository.restoreBackup(
            id: try XCTUnwrap(backups.first?.id),
            safetyBackupReason: "Before exact migration rollback",
            restoredAt: migration.addingTimeInterval(2)
        )
        let restoredBroad = try await repository.fetchEntries(cardID: "base1-4")
        let restoredExact = try await repository.fetchPrintingEntries(cardID: "base1-4")
        XCTAssertEqual(restoredBroad.first?.quantity, 2)
        XCTAssertTrue(restoredExact.isEmpty)
    }

    func testExactPrintingMigrationKeepsAmbiguousBroadOwnership() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        try await repository.setQuantity(1, cardID: "base1-4", variant: .holo, updatedAt: .now)

        let changed = try await repository.reconcileExactOwnership(
            cardID: "base1-4",
            printings: [
                printing(cardID: "base1-4", id: "unlimited", kind: .holo),
                printing(cardID: "base1-4", id: "shadowless", kind: .holo),
            ]
        )

        XCTAssertFalse(changed)
        let broad = try await repository.fetchEntries(cardID: "base1-4")
        let exact = try await repository.fetchPrintingEntries(cardID: "base1-4")
        XCTAssertEqual(broad.first?.quantity, 1)
        XCTAssertTrue(exact.isEmpty)
    }

    func testPrintingIdentityReconciliationMovesGeneratedOwnershipToCorrectedHolo() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let selectedAt = Date(timeIntervalSince1970: 100)
        try await repository.setPrintingQuantity(
            1,
            cardID: "30th-034",
            printingID: "generated",
            variant: .normal,
            updatedAt: selectedAt
        )

        let changed = try await repository.reconcileExactOwnership(
            cardID: "30th-034",
            printings: [printing(cardID: "30th-034", id: "jr7oetx1mqug9", kind: .holo)]
        )

        XCTAssertTrue(changed)
        let broad = try await repository.fetchEntries(cardID: "30th-034")
        XCTAssertTrue(broad.isEmpty)
        let exact = try await repository.fetchPrintingEntries(cardID: "30th-034")
        XCTAssertEqual(exact, [CollectionPrintingEntry(
            cardID: "30th-034",
            printingID: "jr7oetx1mqug9",
            variant: .holo,
            quantity: 1,
            updatedAt: selectedAt
        )])
    }

    func testPrintingIdentityReconciliationKeepsAmbiguousReplacementAsOneUnspecifiedCopy() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        try await repository.setPrintingQuantity(
            1,
            cardID: "future-001",
            printingID: "generated",
            variant: .normal,
            updatedAt: .now
        )

        let changed = try await repository.reconcileExactOwnership(
            cardID: "future-001",
            printings: [
                printing(cardID: "future-001", id: "standard-a", kind: .holo),
                printing(cardID: "future-001", id: "standard-b", kind: .holo),
            ]
        )

        XCTAssertTrue(changed)
        let exact = try await repository.fetchPrintingEntries(cardID: "future-001")
        XCTAssertTrue(exact.isEmpty)
        let broad = try await repository.fetchEntries(cardID: "future-001")
        XCTAssertEqual(broad.map(\.variant), [.holo])
        XCTAssertEqual(broad.map(\.quantity), [1])
    }

    func testProgressStillCountsUnresolvedProviderIdentityAsOwned() {
        let card = card(id: "future-001", number: "001")
        let progress = CollectionProgressCalculator.progressByCardID(
            cards: [card],
            set: CatalogSet(
                id: card.setID, seriesID: "future", name: "Future Set", abbreviation: nil,
                logoURL: nil, symbolURL: nil, officialCardCount: 1, totalCardCount: 1,
                releaseDate: nil, rarityCounts: nil
            ),
            preference: preference(setID: card.setID, goal: .master),
            availableVariants: [card.id: [.normal, .holo]],
            ownedEntries: [],
            availablePrintings: [card.id: [
                printing(cardID: card.id, id: "new-normal", kind: .normal),
                printing(cardID: card.id, id: "new-holo", kind: .holo),
            ]],
            exactOwnedEntries: [CollectionPrintingEntry(
                cardID: card.id,
                printingID: "retired-provider-id",
                variant: .normal,
                quantity: 1,
                updatedAt: .now
            )]
        )[card.id]

        XCTAssertEqual(progress, CollectionProgress(completedSlots: 1, requiredSlots: 2))
    }

    func testMasterProgressCountsExactPrintingsWithoutTurningFallbackIntoFalseCompletion() {
        let card = card(id: "base1-4", number: "4")
        let printings = [
            printing(cardID: card.id, id: "unlimited", kind: .holo),
            printing(cardID: card.id, id: "shadowless", kind: .holo),
        ]
        let progress = CollectionProgressCalculator.progressByCardID(
            cards: [card],
            set: CatalogSet(
                id: card.setID, seriesID: "base", name: "Base", abbreviation: nil,
                logoURL: nil, symbolURL: nil, officialCardCount: 1, totalCardCount: 1,
                releaseDate: nil, rarityCounts: nil
            ),
            preference: SetCollectionPreference.defaultPreference(setID: card.setID, goal: .master),
            availableVariants: [card.id: [.holo]],
            ownedEntries: [
                CollectionVariantEntry(cardID: card.id, variant: .holo, quantity: 1, updatedAt: .now),
            ],
            availablePrintings: [card.id: printings],
            exactOwnedEntries: []
        )[card.id]

        XCTAssertEqual(progress, CollectionProgress(completedSlots: 1, requiredSlots: 2))
    }

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
                pokemonName: "Lucario",
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

        let restorePreview = try await repository.previewBackupRestore(id: backup.id)
        XCTAssertEqual(restorePreview.additions, 1)
        XCTAssertEqual(restorePreview.changes, 3)
        XCTAssertEqual(restorePreview.conflicts, 0)
        XCTAssertEqual(restorePreview.removals, 1)
        XCTAssertEqual(restorePreview.items.count, 5)
        XCTAssertTrue(restorePreview.items.contains {
            $0.action == .removal && $0.title == "me01-001 · Holo"
        })
        let entriesAfterPreview = try await repository.fetchEntries(cardID: "me01-001")
        XCTAssertEqual(entriesAfterPreview.map(\.variant), [.holo])
        XCTAssertEqual(entriesAfterPreview.first?.quantity, 3)

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
        XCTAssertEqual(restoredFolders.first?.pokemonName, "Lucario")
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
            pokemonName: "Lucario",
            displayMode: .allMatching,
            iconName: CollectionFolderIcon.heart.rawValue,
            coverCardID: "smp-SM95",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try await repository.saveCustomFolder(folder)

        let edited = CustomCollectionFolder(
            id: id,
            name: "Owned Lucario",
            cardNameQuery: "Lucario",
            pokemonName: "Lucario",
            displayMode: .ownedOnly,
            iconName: CollectionFolderIcon.crown.rawValue,
            coverCardID: "swshp-SWSH186",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try await repository.saveCustomFolder(edited)

        let savedFolders = try await repository.fetchCustomFolders()
        XCTAssertEqual(savedFolders, [edited])
        XCTAssertEqual(savedFolders.first?.iconName, CollectionFolderIcon.crown.rawValue)
        XCTAssertEqual(savedFolders.first?.coverCardID, "swshp-SWSH186")
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
        let allMetadata = try await repository.fetchAllCardMetadata()
        let missing = try await repository.fetchCardMetadata(cardID: "missing")
        XCTAssertEqual(saved, metadata)
        XCTAssertEqual(allMetadata[metadata.cardID], metadata)
        XCTAssertEqual(missing, .empty(cardID: "missing"))
    }

    func testManualValuePersistsInCollectionExportAndBackupRestore() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let date = Date(timeIntervalSince1970: 600)
        let value = ManualCardValue(cardID: "sma-SV64", variant: .normal, currencyCode: "EUR",
                                    amount: 42.5, preferredOverMarket: true, updatedAt: date)
        try await repository.saveManualValue(value)
        let savedValues = try await repository.fetchManualValues()
        XCTAssertEqual(savedValues, [value])

        let document = try await repository.exportCollection(exportedAt: date, appVersion: "test")
        XCTAssertEqual(document.manualValues, [value])
        let imported = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        try await imported.importCollection(document, mode: .replace, importedAt: date)
        let importedValues = try await imported.fetchManualValues()
        XCTAssertEqual(importedValues, [value])
        let backup = try await repository.createBackup(reason: "Manual value test", createdAt: date)
        try await repository.deleteManualValue(cardID: value.cardID, variant: value.variant,
                                               currencyCode: value.currencyCode)
        let removedValues = try await repository.fetchManualValues()
        XCTAssertTrue(removedValues.isEmpty)
        try await repository.restoreBackup(id: backup.id, safetyBackupReason: "Before test restore",
                                           restoredAt: date.addingTimeInterval(1))
        let restoredValues = try await repository.fetchManualValues()
        XCTAssertEqual(restoredValues, [value])
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

        XCTAssertEqual(
            CollectionProgressCalculator.printingProgress(
                cardID: cards[0].id,
                availableVariants: [.normal, .reverseHolo, .holo],
                ownedEntries: [owned[0]]
            ),
            CollectionProgress(completedSlots: 1, requiredSlots: 3)
        )
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
        try await source.setPrintingQuantity(
            1,
            cardID: "me01-001",
            printingID: "provider-holo-1",
            variant: .holo,
            updatedAt: update
        )
        try await source.saveSetPreference(.init(
            setID: "me01", status: .hidden, goal: .custom,
            includedVariants: [.holo, .reverseHolo], includesSecretCards: false, updatedAt: update
        ))
        try await source.saveCustomFolder(.init(
            id: folderID, name: "Lucario", cardNameQuery: "Lucario", pokemonName: "Lucario",
            displayMode: .ownedOnly,
            iconName: CollectionFolderIcon.star.rawValue,
            coverCardID: "smp-SM95",
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
        let exactEntries = try await destination.fetchPrintingEntries(cardID: "me01-001")
        let preferences = try await destination.fetchSetPreferences()
        let folders = try await destination.fetchCustomFolders()
        let metadata = try await destination.fetchCardMetadata(cardID: "me01-001")
        XCTAssertEqual(entries.first?.quantity, 2)
        XCTAssertEqual(exactEntries.first?.printingID, "provider-holo-1")
        XCTAssertEqual(exactEntries.first?.quantity, 1)
        XCTAssertEqual(preferences["me01"]?.includedVariants, [.holo, .reverseHolo])
        XCTAssertEqual(folders.first?.id, folderID)
        XCTAssertEqual(folders.first?.pokemonName, "Lucario")
        XCTAssertEqual(folders.first?.iconName, CollectionFolderIcon.star.rawValue)
        XCTAssertEqual(folders.first?.coverCardID, "smp-SM95")
        XCTAssertEqual(metadata.notes, "Binder page 3")
    }

    func testSchemaOneBackupDecodesAndPreviewsWithEmptyExactOwnership() async throws {
        let json = #"""
        {
          "format": "com.miranoverhoef.tallydex.collection",
          "schemaVersion": 1,
          "exportedAt": "1970-01-01T00:01:40Z",
          "appVersion": "0.9.6 (42)",
          "ownership": [],
          "setPreferences": [],
          "folders": [],
          "cardMetadata": []
        }
        """#

        let decoded = try CollectionTransferCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.exactOwnership.isEmpty)
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let preview = try await repository.previewImport(decoded, mode: .merge)
        XCTAssertFalse(preview.hasChanges)
    }

    @MainActor
    func testOversizedBackupIsRejectedBeforeDecoding() async throws {
        let store = CollectionStore(
            repository: GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        )
        let oversized = Data(count: CollectionTransferCodec.maximumImportByteCount + 1)

        do {
            _ = try await store.prepareImport(data: oversized, filename: "too-large.pokecollection")
            XCTFail("Expected the oversized backup to be rejected")
        } catch CollectionRepositoryError.importTooLarge(let maximumByteCount) {
            XCTAssertEqual(maximumByteCount, CollectionTransferCodec.maximumImportByteCount)
        } catch {
            XCTFail("Expected importTooLarge, received \(error)")
        }
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
        XCTAssertEqual(preview.items.filter { $0.action == .addition }.count, 1)
        XCTAssertEqual(preview.items.filter { $0.action == .conflict }.count, 1)
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
        XCTAssertEqual(preview.items.first?.title, "old-card · Normal")
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
                coverCardID: "smp-SM95",
                createdAt: date, updatedAt: date
            )],
            cardMetadata: [.init(cardID: "card-1", isWishlisted: true, notes: "Mint, signed", updatedAt: date)]
        )
        let csv = String(decoding: CollectionTransferCodec.csv(document), as: UTF8.self)
        XCTAssertTrue(csv.contains("ownership"))
        XCTAssertTrue(csv.contains("set_preference"))
        XCTAssertTrue(csv.contains("folder"))
        XCTAssertTrue(csv.contains("card_metadata"))
        XCTAssertTrue(csv.contains("smp-SM95"))
        XCTAssertTrue(csv.contains("\"Mint, signed\""))
    }

    func testPriceChartingCSVDecodesExportedRowsAndQuotedFields() throws {
        let csv = """
        id,product-name,console-name,price-in-pennies,include-string,condition-string,condition-id,sku,notes,cost-basis-in-pennies,quantity,date-entered,date-purchased,grading-company,grading-cert-id,folder
        13644989,Annihilape [Reverse Holo] #41,Pokemon Pitch Black,139,Ungraded,Normal wear,1,,,0,2,2026-07-18,,,,
        13644053,Slowbro #30,Pokemon Pitch Black,17,Ungraded,Normal wear,1,,"Mint, centered",0,1,2026-07-18,,,,
        """

        let rows = try PriceChartingTransferCodec.decode(Data(csv.utf8))

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].productID, "13644989")
        XCTAssertEqual(rows[0].productName, "Annihilape [Reverse Holo] #41")
        XCTAssertEqual(rows[0].quantity, 2)
        let product = try XCTUnwrap(
            PriceChartingTransferCodec.productComponents(rows[0].productName)
        )
        XCTAssertEqual(product.name, "Annihilape")
        XCTAssertEqual(product.number, "41")
        XCTAssertEqual(product.variant, "Reverse Holo")
        XCTAssertEqual(PriceChartingTransferCodec.variant(named: product.variant ?? ""), .reverseHolo)
    }

    func testPriceChartingTextExportRepeatsQuantityAndLabelsPrinting() {
        let card = CatalogCard(
            id: "me05-041", setID: "me05", localID: "041", name: "Annihilape",
            imageURL: nil, category: nil, illustrator: nil, rarity: nil
        )
        let data = PriceChartingTransferCodec.textImport(
            ownership: [
                .init(cardID: card.id, variant: .reverseHolo, quantity: 2, updatedAt: .distantPast),
            ],
            cards: [.init(card: card, setName: "Pitch Black")]
        )

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "Annihilape [Reverse Holo] #041 Pokemon Pitch Black\n" +
            "Annihilape [Reverse Holo] #041 Pokemon Pitch Black\n"
        )
    }

    func testPriceChartingProductIDSurvivesBackupAndProducesImportableCSV() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let source = """
        id,product-name,console-name,price-in-pennies,include-string,condition-string,condition-id,sku,notes,cost-basis-in-pennies,quantity,date-entered,date-purchased,grading-company,grading-cert-id,folder
        13644989,Annihilape [Reverse Holo] #41,Pokemon Pitch Black,139,Ungraded,Normal wear,1,,"Mint, centered",0,1,2026-07-18,,,,
        """
        let sourceRow = try XCTUnwrap(PriceChartingTransferCodec.decode(Data(source.utf8)).first)
        let mapping = PriceChartingProductMapping(
            cardID: "me05-041", variant: .reverseHolo,
            fields: sourceRow.fields, updatedAt: timestamp
        )
        let document = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: PortableCollectionDocument.currentSchemaVersion,
            exportedAt: timestamp,
            appVersion: "Test",
            ownership: [.init(cardID: "me05-041", variant: .reverseHolo, quantity: 2, updatedAt: timestamp)],
            setPreferences: [], folders: [], cardMetadata: [], priceChartingMappings: [mapping]
        )

        try await repository.importCollection(document, mode: .replace, importedAt: timestamp)
        let exported = try await repository.exportCollection(exportedAt: timestamp, appVersion: "Test")
        XCTAssertEqual(exported.priceChartingMappings, [mapping])
        let csv = PriceChartingTransferCodec.csvExport(
            ownership: [
                .init(cardID: "me05-041", variant: .reverseHolo, quantity: 2, updatedAt: timestamp)
            ],
            mappings: exported.priceChartingMappings
        )
        XCTAssertEqual(csv.mapped, 1)
        XCTAssertEqual(csv.unmapped, 0)
        let roundTrip = try XCTUnwrap(PriceChartingTransferCodec.decode(csv.data).first)
        XCTAssertEqual(roundTrip.productID, "13644989")
        XCTAssertEqual(roundTrip.quantity, 2)
        XCTAssertEqual(roundTrip.fields[8], "Mint, centered")

        let backup = try await repository.createBackup(reason: "Before editing", createdAt: timestamp)
        try await repository.setQuantity(3, cardID: "me05-041", variant: .reverseHolo, updatedAt: timestamp.addingTimeInterval(1))
        try await repository.restoreBackup(id: backup.id, safetyBackupReason: "Before rollback", restoredAt: timestamp.addingTimeInterval(2))
        let restored = try await repository.exportCollection(exportedAt: timestamp, appVersion: "Test")
        XCTAssertEqual(restored.priceChartingMappings, [mapping])
        XCTAssertEqual(restored.ownership.first?.quantity, 2)
    }

    func testPokemonRuleChoicesUseRealNamesWithoutDuplicates() {
        let results = [
            searchResult(id: "a", name: "Lucario V", setName: "One"),
            searchResult(id: "b", name: "Lucario", setName: "Two"),
            searchResult(id: "c", name: "Lucario-GX", setName: "Three"),
            searchResult(id: "d", name: "Mega Lucario ex", setName: "Four"),
            searchResult(id: "e", name: "Lucario & Melmetal-GX", setName: "Five"),
            searchResult(id: "f", name: "Lucario C LV.X", setName: "Six"),
            searchResult(id: "g", name: "Lucario GL", setName: "Seven"),
            searchResult(id: "h", name: "Lucario Spirit Link", setName: "Eight"),
        ]

        let choices = PokemonRuleSearch.choices(from: results, query: "Lucario")

        XCTAssertEqual(choices.map(\.name), ["Lucario"])
        XCTAssertEqual(choices.first?.matchingCardCount, 7)
        XCTAssertTrue(PokemonRuleSearch.matches(cardName: "Lucario-GX", pokemonName: "Lucario"))
        XCTAssertTrue(PokemonRuleSearch.matches(cardName: "Lucario & Melmetal-GX", pokemonName: "Lucario"))
        XCTAssertTrue(PokemonRuleSearch.matches(cardName: "Lucario C LV.X", pokemonName: "Lucario"))
        XCTAssertFalse(PokemonRuleSearch.matches(cardName: "Lucario Spirit Link", pokemonName: "Lucario"))
        XCTAssertFalse(PokemonRuleSearch.matches(cardName: "Riolu", pokemonName: "Lucario"))
    }

    func testPokemonRuleSearchKeepsMewAndMewtwoDistinct() {
        let results = [
            searchResult(id: "a", name: "Mew ex", setName: "One"),
            searchResult(id: "b", name: "Mewtwo VSTAR", setName: "Two"),
        ]

        let choices = PokemonRuleSearch.choices(from: results, query: "Mew")

        XCTAssertEqual(choices.map(\.name), ["Mew", "Mewtwo"])
    }

    func testPokemonRulesUseVerifiedIDsAndFallbackOnlyWhenIDsAreMissing() {
        let rules = [PokemonCollectionRule(name: "Lucario", dexID: 448)]
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "An unusual form", ids: [448]), rules: rules))
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario & Melmetal-GX", ids: [809, 448]), rules: rules))
        XCTAssertFalse(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario", ids: [447]), rules: rules))
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "Mega Lucario ex", ids: []), rules: rules))
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario-GX", ids: nil), rules: rules))
        XCTAssertFalse(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario", ids: [448], category: "Trainer"), rules: rules))
        XCTAssertFalse(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario Spirit Link", ids: nil, category: nil), rules: rules))
    }

    func testTwoPokemonRulesIncludeEitherAndKeepMewDistinctFromMewtwo() {
        let rules = [PokemonCollectionRule(name: "Lucario", dexID: 448), .init(name: "Riolu", dexID: 447)]
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "Riolu", ids: [447]), rules: rules))
        XCTAssertTrue(PokemonRuleSearch.matches(card: pokemonCard(name: "Lucario V", ids: [448]), rules: rules))
        XCTAssertFalse(PokemonRuleSearch.matches(card: pokemonCard(name: "Pikachu", ids: [25]), rules: rules))
        XCTAssertFalse(PokemonRuleSearch.matches(card: pokemonCard(name: "Mewtwo", ids: nil), rules: [.init(name: "Mew")]))
    }

    func testPokemonChoicesNeverGuessMultiPokemonIDOrderOrConflictingIDs() {
        let lucario = pokemonCard(name: "Lucario V", ids: [448])
        let tagTeam = pokemonCard(name: "Lucario & Melmetal-GX", ids: [809, 448])
        let results = [lucario, tagTeam].map {
            CatalogCardSearchResult(card: $0, setName: "Test", setReleaseDate: nil)
        }
        XCTAssertEqual(PokemonRuleSearch.choices(from: results, query: "Lucario").first?.dexID, 448)
        XCTAssertNil(PokemonRuleSearch.choices(from: [results[1]], query: "Melmetal").first?.dexID)
        let contradictory = CatalogCardSearchResult(
            card: pokemonCard(name: "Lucario", ids: [447]), setName: "Test", setReleaseDate: nil
        )
        XCTAssertNil(PokemonRuleSearch.choices(from: results + [contradictory], query: "Lucario").first?.dexID)
    }

    func testPokemonRulesRejectDuplicatesAndMoreThanTwoSelections() {
        XCTAssertTrue(PokemonCollectionRule.isValid([.init(name: "Lucario", dexID: 448), .init(name: "Riolu", dexID: 447)]))
        XCTAssertFalse(PokemonCollectionRule.isValid([]))
        XCTAssertFalse(PokemonCollectionRule.isValid([.init(name: "Lucario"), .init(name: "lucario")]))
        XCTAssertFalse(PokemonCollectionRule.isValid([.init(name: "Lucario", dexID: 448), .init(name: "Mega Lucario", dexID: 448)]))
        XCTAssertFalse(PokemonCollectionRule.isValid([.init(name: "Lucario"), .init(name: "Riolu"), .init(name: "Pikachu")]))
        XCTAssertFalse(PokemonCollectionRule.isValid([.init(name: "   ")]))
        XCTAssertFalse(PokemonCollectionRule.isValid([.init(name: "Lucario", dexID: -1)]))
    }

    func testTwoPokemonFolderSurvivesEditBackupRestoreAndPortableMerge() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let destination = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let timestamp = Date(timeIntervalSince1970: 100)
        let rules = [PokemonCollectionRule(name: "Lucario", dexID: 448), .init(name: "Riolu", dexID: 447)]
        let folder = CustomCollectionFolder(
            id: UUID(), name: "Lucario + Riolu", cardNameQuery: "Lucario + Riolu", pokemonName: "Lucario",
            pokemonRules: rules, displayMode: .allMatching, coverCardID: "smp-SM95",
            createdAt: timestamp, updatedAt: timestamp
        )
        try await repository.setQuantity(3, cardID: "smp-SM95", variant: .holo, updatedAt: timestamp)
        try await repository.saveCustomFolder(folder)
        let fetched = try await repository.fetchCustomFolders()
        XCTAssertEqual(fetched, [folder])
        XCTAssertEqual(fetched.first?.pokemonSummary, "Lucario + Riolu")
        let backup = try await repository.createBackup(reason: "Two Pokémon", createdAt: timestamp)
        let exported = try await repository.exportCollection(exportedAt: timestamp, appVersion: "0.9.18")
        let decoded = try CollectionTransferCodec.decode(CollectionTransferCodec.encode(exported))
        XCTAssertEqual(decoded.folders.first?.pokemonRules, rules)
        let csv = String(decoding: CollectionTransferCodec.csv(decoded), as: UTF8.self)
        XCTAssertTrue(csv.contains("pokemon_rules"))
        XCTAssertTrue(csv.contains("Riolu"))
        XCTAssertTrue(csv.contains("448"))
        try await destination.importCollection(decoded, mode: .merge, importedAt: timestamp)
        let merged = try await destination.fetchCustomFolders()
        XCTAssertEqual(merged, [folder])
        try await repository.saveCustomFolder(.init(
            id: folder.id, name: "Riolu", cardNameQuery: "Riolu", pokemonName: "Riolu",
            pokemonRules: [rules[1]], displayMode: .ownedOnly,
            createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(1)
        ))
        try await repository.restoreBackup(id: backup.id, safetyBackupReason: "Before restore", restoredAt: timestamp.addingTimeInterval(2))
        let restored = try await repository.fetchCustomFolders()
        XCTAssertEqual(restored, [folder])
        let owned = try await repository.fetchEntries(cardID: "smp-SM95")
        XCTAssertEqual(owned.first?.quantity, 3)
        try await destination.importCollection(decoded, mode: .replace, importedAt: timestamp.addingTimeInterval(3))
        let replaced = try await destination.fetchCustomFolders()
        XCTAssertEqual(replaced, [folder])
    }

    func testLegacyAndSinglePokemonFoldersRetainTheirRules() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let legacy = CustomCollectionFolder(
            id: UUID(), name: "Luc", cardNameQuery: "Luc", displayMode: .allMatching,
            createdAt: timestamp, updatedAt: timestamp
        )
        let single = CustomCollectionFolder(
            id: UUID(), name: "Lucario", cardNameQuery: "Lucario", pokemonName: "Lucario",
            displayMode: .allMatching, createdAt: timestamp, updatedAt: timestamp
        )
        XCTAssertTrue(legacy.effectivePokemonRules.isEmpty)
        XCTAssertNil(legacy.pokemonSummary)
        XCTAssertEqual(single.effectivePokemonRules, [.init(name: "Lucario")])
    }

    func testInvalidTwoPokemonRulesCannotBeSavedOrImported() async throws {
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let timestamp = Date(timeIntervalSince1970: 100)
        let badRules = [PokemonCollectionRule(name: "Lucario"), .init(name: "lucario")]
        let folder = CustomCollectionFolder(
            id: UUID(), name: "Duplicates", cardNameQuery: "Lucario", pokemonRules: badRules,
            displayMode: .allMatching, createdAt: timestamp, updatedAt: timestamp
        )
        do {
            try await repository.saveCustomFolder(folder)
            XCTFail("Duplicate species must be rejected")
        } catch {
            XCTAssertEqual(error as? CollectionRepositoryError, .invalidCustomFolder)
        }
        let document = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier, schemaVersion: 4,
            exportedAt: timestamp, appVersion: "0.9.18", ownership: [], setPreferences: [],
            folders: [.init(id: folder.id, name: folder.name, cardNameQuery: folder.cardNameQuery,
                            pokemonRules: badRules, displayMode: .allMatching, createdAt: timestamp, updatedAt: timestamp)],
            cardMetadata: []
        )
        do {
            try await repository.importCollection(document, mode: .replace, importedAt: timestamp)
            XCTFail("Duplicate species in portable documents must be rejected")
        } catch {
            XCTAssertEqual(error as? CollectionRepositoryError, .invalidImport)
        }
        let folders = try await repository.fetchCustomFolders()
        XCTAssertTrue(folders.isEmpty)
    }

    private func pokemonCard(name: String, ids: [Int]?, category: String? = "Pokémon") -> CatalogCard {
        CatalogCard(
            id: name, setID: "test", localID: "1", name: name, imageURL: nil,
            category: category, illustrator: nil, rarity: nil,
            metadata: ids.map {
                CatalogCardMetadata(
                    dexIDs: $0, hp: nil, types: [], evolvesFrom: nil, stage: nil, suffix: nil,
                    attacks: [], abilities: [], weaknesses: [], resistances: [], retreatCost: nil,
                    regulationMark: nil, legality: nil, rulesText: nil, trainerType: nil, energyType: nil,
                    flavorText: nil, updatedAt: nil
                )
            }
        )
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

    func testCollectionManagerDownloadHasSafeAttachmentHeaders() throws {
        let response = LocalHTTPResponse.download(
            Data("backup".utf8),
            filename: "TallyDex-Collection-2026-09-23.pokecollection",
            contentType: "application/octet-stream"
        )
        let encoded = try XCTUnwrap(String(data: response.encoded, encoding: .utf8))
        XCTAssertTrue(encoded.contains("Content-Disposition: attachment; filename=\"TallyDex-Collection-2026-09-23.pokecollection\"\r\n"))
        XCTAssertTrue(encoded.contains("Cache-Control: no-store\r\n"))
        XCTAssertTrue(encoded.contains("Content-Length: 6\r\n"))
        XCTAssertTrue(encoded.hasSuffix("\r\n\r\nbackup"))
    }

    func testCollectionManagerBootstrapIncludesSavedVisibilityChoices() throws {
        let bootstrap = LocalSharingBootstrapDTO(
            sets: [], allowsMultipleCopies: false,
            browserGridColumns: "4", browserGridSpacing: "compact",
            showDetails: false, showMarket: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bootstrap)) as? [String: Any]
        )
        XCTAssertEqual(object["showDetails"] as? Bool, false)
        XCTAssertEqual(object["showMarket"] as? Bool, true)
    }

    @MainActor
    func testCollectionManagerShowsBroadAndExactOwnershipWithoutDuplicatingEdits() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let cardID = "sv-test-001"
        let exactOnlyID = "sv-test-002"
        let document = PortableCollectionDocument(
            format: PortableCollectionDocument.formatIdentifier,
            schemaVersion: PortableCollectionDocument.currentSchemaVersion,
            exportedAt: timestamp,
            appVersion: "Test",
            ownership: [
                .init(cardID: cardID, variant: .normal, quantity: 2, updatedAt: timestamp)
            ],
            setPreferences: [],
            folders: [],
            cardMetadata: [],
            exactOwnership: [
                .init(cardID: cardID, printingID: "normal-printing", variant: .normal, quantity: 1, updatedAt: timestamp),
                .init(cardID: cardID, printingID: "holo-printing", variant: .holo, quantity: 1, updatedAt: timestamp),
                .init(cardID: exactOnlyID, printingID: "exact-only", variant: .normal, quantity: 1, updatedAt: timestamp)
            ]
        )
        let response = LocalCollectionSharingController.cardsDTO(
            results: [
                .init(card: card(id: cardID, number: "001"), setName: "Test Set"),
                .init(card: card(id: exactOnlyID, number: "002"), setName: "Test Set")
            ],
            variantsByCardID: [cardID: [.normal]],
            document: document,
            mayBeTruncated: false
        )

        let result = try XCTUnwrap(response.cards.first)
        XCTAssertTrue(result.owned)
        let normal = try XCTUnwrap(result.variants.first { $0.id == CatalogVariantKind.normal.rawValue })
        let holo = try XCTUnwrap(result.variants.first { $0.id == CatalogVariantKind.holo.rawValue })
        XCTAssertEqual(normal.quantity, 3)
        XCTAssertEqual(normal.exactQuantity, 1)
        XCTAssertEqual(holo.quantity, 1)
        XCTAssertEqual(holo.exactQuantity, 1)
        let exactOnly = try XCTUnwrap(response.cards.first { $0.id == exactOnlyID })
        XCTAssertTrue(exactOnly.owned)
        XCTAssertEqual(exactOnly.variants.first?.quantity, 1)
        XCTAssertEqual(exactOnly.variants.first?.exactQuantity, 1)
        XCTAssertEqual(LocalCollectionSharingController.broadQuantity(forTotal: 3, exactQuantity: 1), 2)
        XCTAssertNil(LocalCollectionSharingController.broadQuantity(forTotal: 0, exactQuantity: 1))
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

    private func searchResult(
        id: String,
        name: String,
        setName: String
    ) -> CatalogCardSearchResult {
        CatalogCardSearchResult(
            card: CatalogCard(
                id: id,
                setID: "set-\(id)",
                localID: "1",
                name: name,
                imageURL: nil,
                category: nil,
                illustrator: nil,
                rarity: nil
            ),
            setName: setName,
            setReleaseDate: nil
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

    private func printing(
        cardID: String,
        id: String,
        kind: CatalogVariantKind
    ) -> CatalogPrinting {
        CatalogPrinting(
            cardID: cardID,
            providerID: id,
            rawType: kind.rawValue,
            kind: kind,
            subtype: nil,
            size: nil,
            stamps: [],
            foil: nil,
            languages: ["en"],
            cardmarketProductID: nil,
            tcgplayerProductID: nil,
            cardtraderProductID: nil
        )
    }
}
