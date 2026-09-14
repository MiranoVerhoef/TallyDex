#if DEBUG
import Foundation

/// Explicit opt-in UI fixtures: separate database and preferences per test UUID.
/// Nothing here is compiled into a Release app or uses the user's collection.
@MainActor
struct ReliabilityUITestFixture {
    let id: UUID
    let scenario: String

    static var current: Self? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("-ReliabilityUITesting"),
              let text = process.environment["TALLYDEX_UI_TEST_ID"], let id = UUID(uuidString: text),
              let scenario = process.environment["TALLYDEX_UI_TEST_SCENARIO"],
              ["fresh", "update", "restore", "merge", "replace"].contains(scenario) else { return nil }
        return .init(id: id, scenario: scenario)
    }

    var defaults: UserDefaults {
        let defaults = UserDefaults(suiteName: "com.miranoverhoef.TallyDex.Reliability.\(id.uuidString)")!
        if !defaults.bool(forKey: "fixture.preferences.initialized") {
            defaults.set(scenario != "fresh", forKey: AppExperienceSettings.introductionCompletedKey)
            defaults.set(scenario == "update" ? "0.9.23" : (scenario == "fresh" ? "" : AppReleaseNotes.current.version),
                         forKey: AppExperienceSettings.lastSeenReleaseVersionKey)
            defaults.set(false, forKey: CardDisplaySettings.detailsExpandedByDefaultKey)
            defaults.set(false, forKey: CollectionSettings.allowsMultipleCopiesKey)
            defaults.set(PricingSettings.defaultSource.rawValue, forKey: PricingSettings.sourceKey)
            defaults.set(true, forKey: "fixture.preferences.initialized")
        }
        return defaults
    }

    private var directory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TallyDexReliabilityUITests", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func repository() -> GRDBCollectionRepository {
        try! GRDBCollectionRepository(database: CollectionDatabase(path: directory.appendingPathComponent("collection.sqlite").path))
    }

    func makeCollectionStore() -> CollectionStore {
        CollectionStore(repository: repository(), now: { Date(timeIntervalSince1970: 300) })
    }

    func makeCatalogStore() -> CatalogStore {
        CatalogStore(provider: ReliabilityCatalogProvider(),
                     repository: try! GRDBCatalogRepository(database: CatalogDatabase.inMemory()))
    }

    func prepare(_ store: CollectionStore) async {
        if defaults.bool(forKey: "fixture.collection.initialized") {
            await store.start()
            return
        }
        do {
            let repository = repository()
            let cardID = ReliabilityCatalogProvider.card.id
            let stamp = TrickOrTradeRelease.all[0].printing(cardID: cardID)!
            try await repository.setPrintingQuantity(3, cardID: cardID, printingID: "ui-normal", variant: .normal,
                                                      updatedAt: Date(timeIntervalSince1970: 100))
            try await repository.setPrintingQuantity(4, cardID: cardID, printingID: stamp.providerID, variant: .trickOrTrade,
                                                      updatedAt: Date(timeIntervalSince1970: 100))
            await store.start()
            _ = try await store.createBackup(reason: "Reliability baseline")
            let baseline = try await store.exportDocument()
            try await store.setPrintingQuantity(7, cardID: cardID, printing: ReliabilityCatalogProvider.normal)
            try await store.setPrintingQuantity(2, cardID: cardID, printing: stamp)
            defaults.set(true, forKey: "fixture.collection.initialized")
            if scenario == "merge" || scenario == "replace" {
                let incoming = PortableCollectionDocument(
                    format: baseline.format, schemaVersion: baseline.schemaVersion, exportedAt: baseline.exportedAt,
                    appVersion: baseline.appVersion, ownership: baseline.ownership,
                    setPreferences: baseline.setPreferences, folders: baseline.folders, cardMetadata: baseline.cardMetadata,
                    exactOwnership: baseline.exactOwnership + [.init(cardID: "ui-other-1", printingID: "ui-incoming",
                        variant: .normal, quantity: 2, updatedAt: Date(timeIntervalSince1970: 100))]
                )
                let url = directory.appendingPathComponent("Reliability.pokecollection")
                try CollectionTransferCodec.encode(incoming).write(to: url, options: .atomic)
                await store.openExternalBackup(at: url)
            }
        } catch {
            defaults.set(String(describing: error), forKey: "fixture.error")
        }
    }

    func state(_ store: CollectionStore) -> String {
        let stamp = TrickOrTradeRelease.all[0].printing(cardID: ReliabilityCatalogProvider.card.id)!
        return "normal=\(store.printingQuantity(cardID: stamp.cardID, printingID: "ui-normal"));stamp=\(store.printingQuantity(cardID: stamp.cardID, printingID: stamp.providerID));incoming=\(store.printingQuantity(cardID: "ui-other-1", printingID: "ui-incoming"));owned=\(store.ownedCardIDs.count);backups=\(store.backups.count);intro=\(defaults.bool(forKey: AppExperienceSettings.introductionCompletedKey));seen=\(defaults.string(forKey: AppExperienceSettings.lastSeenReleaseVersionKey) ?? "");error=\(defaults.string(forKey: "fixture.error") ?? "none")"
    }
}

private struct ReliabilityCatalogProvider: CatalogProvider {
    static let card = CatalogCard(id: "swsh8-16", setID: "swsh8", localID: "16", name: "Phantump", imageURL: nil,
        category: "Pokémon", illustrator: nil, rarity: nil)
    static let normal = CatalogPrinting(cardID: card.id, providerID: "ui-normal", rawType: "normal", kind: .normal,
        subtype: nil, size: "standard", stamps: [], foil: nil, languages: ["en"],
        cardmarketProductID: nil, tcgplayerProductID: nil, cardtraderProductID: nil)
    private static let series = CatalogSeries(id: "swsh", name: "Sword & Shield", logoURL: nil)
    private static let set = CatalogSet(id: "swsh8", seriesID: "swsh", name: "Fusion Strike", abbreviation: nil,
        logoURL: nil, symbolURL: nil, officialCardCount: 1, totalCardCount: 1, releaseDate: "2021-11-12", rarityCounts: nil)
    func fetchCardIndex() async throws -> [CatalogCard] { [Self.card] }
    func fetchSeriesIndex() async throws -> [CatalogSeries] { [Self.series] }
    func fetchSeries(id: String) async throws -> CatalogSeriesSnapshot { .init(series: Self.series, sets: [Self.set]) }
    func fetchSet(id: String) async throws -> CatalogSetSnapshot { .init(set: Self.set, cards: [Self.card]) }
    func fetchCard(id: String) async throws -> CatalogCardSnapshot {
        guard id == Self.card.id else { throw TCGdexError.invalidResponse }
        return .init(card: Self.card, variants: [.normal], printings: [Self.normal])
    }
}
#endif
