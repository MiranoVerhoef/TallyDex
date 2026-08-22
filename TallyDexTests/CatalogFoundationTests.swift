import Foundation
import XCTest
@testable import TallyDex

final class CatalogFoundationTests: XCTestCase {
    func testTCGdexDecodesSeriesIndex() async throws {
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(
                    data: Data(#"[{"id":"sv","name":"Scarlet & Violet"}]"#.utf8),
                    statusCode: 200,
                    retryAfter: nil
                ),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let series = try await client.fetchSeriesIndex()

        XCTAssertEqual(series, [CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)])
    }

    func testTCGdexDecodesCompleteCardSearchIndex() async throws {
        let response = #"""
        [
          {
            "id": "sm115-2",
            "localId": "2",
            "name": "Metapod",
            "image": "https://assets.tcgdex.net/en/sm/sm115/2"
          }
        ]
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let cards = try await client.fetchCardIndex()

        XCTAssertEqual(cards.first?.id, "sm115-2")
        XCTAssertEqual(cards.first?.setID, "sm115")
        XCTAssertEqual(cards.first?.name, "Metapod")
    }

    func testTCGdexRetriesRateLimitResponse() async throws {
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(), statusCode: 429, retryAfter: "0"),
            HTTPResponse(
                data: Data(#"[{"id":"base","name":"Base"}]"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let client = TCGdexClient(
            httpClient: stub,
            retryPolicy: .init(maximumAttempts: 2, baseDelay: .zero),
            sleep: { _ in }
        )

        let series = try await client.fetchSeriesIndex()
        let requestCount = await stub.requestCount

        XCTAssertEqual(series.first?.id, "base")
        XCTAssertEqual(requestCount, 2)
    }

    func testTCGdexDecodesDetailedCardVariants() async throws {
        let response = #"""
        {
          "id": "sv03.5-001",
          "localId": "001",
          "name": "Bulbasaur",
          "image": "https://assets.tcgdex.net/en/sv/sv03.5/001",
          "category": "Pokemon",
          "illustrator": "Yuu Nishida",
          "rarity": "Common",
          "set": { "id": "sv03.5" },
          "variants": {
            "firstEdition": false,
            "holo": false,
            "normal": true,
            "reverse": true,
            "wPromo": false
          }
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "sv03.5-001")

        XCTAssertEqual(snapshot.card.setID, "sv03.5")
        XCTAssertEqual(snapshot.variants, [.normal, .reverseHolo])
    }

    func testLucarioPrereleaseOverridesFillProviderGap() {
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal, .reverseHolo], cardID: "pl1-53"),
            [.normal, .reverseHolo, .prerelease, .prereleaseStaff]
        )
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal], cardID: "smp-SM95"),
            [.prerelease, .prereleaseStaff]
        )
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal], cardID: "swshp-SWSH186"),
            [.prerelease, .prereleaseStaff]
        )
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal], cardID: "sv01-001"),
            [.normal]
        )
    }

    func testTCGdexDecodesOfficialSetAbbreviation() async throws {
        let response = #"""
        {
          "id": "me04",
          "name": "Chaos Rising",
          "abbreviation": { "official": "CRI" },
          "cardCount": { "official": 86, "total": 122 },
          "serie": { "id": "me", "name": "Mega Evolution" },
          "cards": []
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchSet(id: "me04")

        XCTAssertEqual(snapshot.set.abbreviation, "CRI")
    }

    func testRepositoryReplacesOnlySetsForRequestedSeries() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let firstSeries = CatalogSeries(id: "base", name: "Base", logoURL: nil)
        let secondSeries = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        try await repository.upsertSeries([firstSeries, secondSeries])

        try await repository.replaceSets(
            [set(id: "base1", seriesID: "base", name: "Base Set")],
            forSeriesID: "base"
        )
        try await repository.replaceSets(
            [set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")],
            forSeriesID: "sv"
        )
        try await repository.replaceSets(
            [set(id: "base2", seriesID: "base", name: "Jungle")],
            forSeriesID: "base"
        )

        let allSets = try await repository.fetchSets(seriesID: nil)
        XCTAssertEqual(Set(allSets.map(\.id)), ["base2", "sv01"])
    }

    func testRepositoryRejectsSeriesMismatchBeforeReplacingData() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())

        do {
            try await repository.replaceSets(
                [set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")],
                forSeriesID: "base"
            )
            XCTFail("Expected a series mismatch error")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .seriesMismatch)
        }
    }

    func testRepositoryAtomicallyReplacesDetailedCardAndVariants() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.upsertSeries([
            CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil),
        ])
        let catalogSet = set(id: "sv03.5", seriesID: "sv", name: "151")
        try await repository.replaceSets([catalogSet], forSeriesID: "sv")

        let card = CatalogCard(
            id: "sv03.5-001",
            setID: "sv03.5",
            localID: "001",
            name: "Bulbasaur",
            imageURL: nil,
            category: "Pokemon",
            illustrator: "Yuu Nishida",
            rarity: "Common"
        )
        try await repository.replaceCard(
            CatalogCardSnapshot(card: card, variants: [.normal, .reverseHolo])
        )
        try await repository.replaceCard(
            CatalogCardSnapshot(card: card, variants: [.holo])
        )

        let storedCards = try await repository.fetchCards(setID: "sv03.5")
        let storedVariants = try await repository.fetchVariants(cardID: card.id)
        XCTAssertEqual(storedCards, [card])
        XCTAssertEqual(storedVariants, [.holo])
    }

    func testRepositoryReplacesWholeCatalogInDisplayOrder() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let mega = CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil)
        let scarletViolet = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)

        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(
                series: mega,
                sets: [
                    set(id: "me05", seriesID: "me", name: "Pitch Black"),
                    set(
                        id: "me04",
                        seriesID: "me",
                        name: "Chaos Rising",
                        abbreviation: "CRI",
                        rarityCounts: [
                            CatalogRarityCount(rarity: "Illustration rare", count: 11),
                            CatalogRarityCount(rarity: "Special illustration rare", count: 6),
                        ]
                    ),
                ]
            ),
            CatalogSeriesSnapshot(
                series: scarletViolet,
                sets: [set(id: "sv10", seriesID: "sv", name: "Destined Rivals")]
            ),
        ])

        let storedSeriesIDs = try await repository.fetchSeries().map(\.id)
        let storedMegaSetNames = try await repository.fetchSets(seriesID: "me").map(\.name)
        let storedChaosRising = try await repository.fetchSets(seriesID: "me")[1]
        XCTAssertEqual(storedSeriesIDs, ["me", "sv"])
        XCTAssertEqual(storedMegaSetNames, ["Pitch Black", "Chaos Rising"])
        XCTAssertEqual(storedChaosRising.abbreviation, "CRI")
        XCTAssertEqual(storedChaosRising.rarityCounts, [
            CatalogRarityCount(rarity: "Illustration rare", count: 11),
            CatalogRarityCount(rarity: "Special illustration rare", count: 6),
        ])
    }

    func testRepositoryRejectsInvalidWholeCatalogWithoutDeletingCache() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let base = CatalogSeries(id: "base", name: "Base", logoURL: nil)
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(
                series: base,
                sets: [set(id: "base1", seriesID: "base", name: "Base Set")]
            ),
        ])

        do {
            try await repository.replaceCatalog([
                CatalogSeriesSnapshot(
                    series: CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil),
                    sets: [set(id: "me05", seriesID: "wrong", name: "Pitch Black")]
                ),
            ])
            XCTFail("Expected invalid snapshot error")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .invalidSnapshot)
        }

        let storedSeries = try await repository.fetchSeries()
        let storedBaseSetIDs = try await repository.fetchSets(seriesID: "base").map(\.id)
        XCTAssertEqual(storedSeries, [base])
        XCTAssertEqual(storedBaseSetIDs, ["base1"])
    }

    func testPrintedExpansionCodesBeginWithScarletViolet() {
        XCTAssertFalse(set(id: "sm115", seriesID: "sm", name: "Hidden Fates").usesPrintedExpansionCode)
        XCTAssertTrue(set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet").usesPrintedExpansionCode)
        XCTAssertTrue(set(id: "me04", seriesID: "me", name: "Chaos Rising").usesPrintedExpansionCode)
    }

    func testSeriesWithoutLogoUsesTallyDexPlaceholderInsteadOfChildArtwork() {
        let symbolURL = URL(string: "https://assets.tcgdex.net/univ/mc/2021swsh/symbol")!
        let collection = CatalogSeriesGroup(
            series: CatalogSeries(id: "mc", name: "McDonald's Collection", logoURL: nil),
            sets: [
                CatalogSet(
                    id: "2021swsh",
                    seriesID: "mc",
                    name: "McDonald's Collection 2021",
                    abbreviation: nil,
                    logoURL: nil,
                    symbolURL: symbolURL,
                    officialCardCount: 25,
                    totalCardCount: 25,
                    releaseDate: nil,
                    rarityCounts: nil
                ),
            ]
        )

        XCTAssertNil(collection.preferredArtworkURL)
        XCTAssertNil(collection.preferredArtworkReference)
    }

    func testSetWithoutLogoUsesTallyDexPlaceholderWhileKeepingItsSymbol() {
        let symbolURL = URL(string: "https://assets.tcgdex.net/en/sm/sm115/symbol")!
        let hiddenFates = CatalogSet(
            id: "sm115",
            seriesID: "sm",
            name: "Hidden Fates",
            abbreviation: nil,
            logoURL: nil,
            symbolURL: symbolURL,
            officialCardCount: 68,
            totalCardCount: 69,
            releaseDate: nil,
            rarityCounts: nil
        )

        XCTAssertNil(hiddenFates.preferredArtworkReference)
        XCTAssertEqual(hiddenFates.symbolURL, symbolURL)
    }

    func testUpcomingSetUsesItsAnnouncedReleaseDate() {
        let upcoming = CatalogSet(
            id: "upcoming-30c",
            seriesID: "me",
            name: "30th Celebration",
            abbreviation: "30C",
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 0,
            totalCardCount: 0,
            releaseDate: "2026-09-16",
            rarityCounts: nil
        )
        let referenceDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 22)
        )!

        XCTAssertTrue(upcoming.isUpcoming(relativeTo: referenceDate))
        XCTAssertEqual(
            Calendar(identifier: .gregorian).dateComponents(
                [.year, .month, .day],
                from: upcoming.releaseDateValue!
            ),
            DateComponents(year: 2026, month: 9, day: 16)
        )
    }

    func testArtworkCacheAddsPNGExtensionOnlyWhenNeeded() {
        let extensionless = URL(string: "https://assets.tcgdex.net/en/sv/sv01/logo")!
        let png = URL(string: "https://example.com/logo.png")!

        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(extensionless).absoluteString,
            "https://assets.tcgdex.net/en/sv/sv01/logo.png"
        )
        XCTAssertEqual(CatalogArtworkCache.resolvedAssetURL(png), png)
    }

    func testArtworkCacheBuildsTCGdexCardImageURLs() {
        let card = URL(string: "https://assets.tcgdex.net/en/sv/sv03.5/001")!

        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(card, category: .cardThumbnails).absoluteString,
            "https://assets.tcgdex.net/en/sv/sv03.5/001/low.webp"
        )
        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(card, category: .cardArtwork).absoluteString,
            "https://assets.tcgdex.net/en/sv/sv03.5/001/high.webp"
        )
    }

    func testCatalogMetadataRefreshPreservesDownloadedCards() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let firstSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [firstSet]),
        ])
        let card = CatalogCard(
            id: "sv01-001",
            setID: "sv01",
            localID: "001",
            name: "Sprigatito",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceSet(CatalogSetSnapshot(set: firstSet, cards: [card]))

        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(
                series: CatalogSeries(id: "sv", name: "Scarlet & Violet Updated", logoURL: nil),
                sets: [set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet Updated")]
            ),
        ])

        let storedCards = try await repository.fetchCards(setID: "sv01")
        let storedSeries = try await repository.fetchSeries()
        XCTAssertEqual(storedCards, [card])
        XCTAssertEqual(storedSeries.first?.name, "Scarlet & Violet Updated")
    }

    func testRepositorySearchesPreloadedCardsByNameOrNumber() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001",
            setID: "sv01",
            localID: "001",
            name: "Sprigatito",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceSearchIndex([card])

        let byName = try await repository.searchCards(query: "sprig")
        let byNumber = try await repository.searchCards(query: "001")
        let bySetAndName = try await repository.searchCards(query: "Scarlet sprig")
        let byCardID = try await repository.fetchSearchResults(cardIDs: [card.id])
        let searchOnlyDownloadedSetIDs = try await repository.fetchDownloadedSetIDs()
        let expectedResult = CatalogCardSearchResult(card: card, setName: "Scarlet & Violet")
        XCTAssertEqual(byName, [expectedResult])
        XCTAssertEqual(byNumber, [expectedResult])
        XCTAssertEqual(bySetAndName, [expectedResult])
        XCTAssertEqual(byCardID, [expectedResult])
        XCTAssertTrue(searchOnlyDownloadedSetIDs.isEmpty)

        try await repository.replaceSet(CatalogSetSnapshot(set: catalogSet, cards: [card]))
        let downloadedSetIDs = try await repository.fetchDownloadedSetIDs()
        XCTAssertEqual(downloadedSetIDs, ["sv01"])
    }

    func testCustomFolderNameSearchReturnsEveryNameMatchOnly() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let lucarioSet = set(id: "sv01", seriesID: "sv", name: "Lucario Collection")
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [lucarioSet]),
        ])
        let matches = (0..<105).map { index in
            CatalogCard(
                id: "sv01-\(index)",
                setID: "sv01",
                localID: String(format: "%03d", index),
                name: index.isMultiple(of: 2) ? "Lucario" : "Lucario ex",
                imageURL: nil,
                category: nil,
                illustrator: nil,
                rarity: nil
            )
        }
        let unrelated = CatalogCard(
            id: "sv01-other",
            setID: "sv01",
            localID: "999",
            name: "Riolu",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceSearchIndex(matches + [unrelated])

        let results = try await repository.fetchCards(matchingName: "lucario")

        XCTAssertEqual(results.count, 105)
        XCTAssertFalse(results.contains { $0.card.id == unrelated.id })
        XCTAssertTrue(results.allSatisfy { $0.card.name.localizedCaseInsensitiveContains("lucario") })
    }

    func testArtworkCacheReportsAndSelectivelyClearsCategories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let seriesDirectory = root.appendingPathComponent("series-logos", isDirectory: true)
        let symbolDirectory = root.appendingPathComponent("expansion-symbols", isDirectory: true)
        try FileManager.default.createDirectory(at: seriesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symbolDirectory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12).write(to: seriesDirectory.appendingPathComponent("one.png"))
        try Data(repeating: 2, count: 7).write(to: symbolDirectory.appendingPathComponent("two.png"))
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = CatalogArtworkCache(rootDirectory: root)
        let initial = await cache.snapshot()
        XCTAssertEqual(initial.statistics(for: .seriesLogos).fileCount, 1)
        XCTAssertEqual(initial.statistics(for: .expansionSymbols).byteCount, 7)
        XCTAssertEqual(initial.totalFileCount, 2)

        try await cache.remove(.seriesLogos)
        let remaining = await cache.snapshot()
        XCTAssertEqual(remaining.statistics(for: .seriesLogos), .empty)
        XCTAssertEqual(remaining.statistics(for: .expansionSymbols).fileCount, 1)
    }

    private func set(
        id: String,
        seriesID: String,
        name: String,
        abbreviation: String? = nil,
        rarityCounts: [CatalogRarityCount]? = nil
    ) -> CatalogSet {
        CatalogSet(
            id: id,
            seriesID: seriesID,
            name: name,
            abbreviation: abbreviation,
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 1,
            totalCardCount: 1,
            releaseDate: nil,
            rarityCounts: rarityCounts
        )
    }
}

private actor HTTPClientStub: HTTPClient {
    private var responses: [HTTPResponse]
    private(set) var requestCount = 0

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        guard !responses.isEmpty else {
            throw TCGdexError.invalidResponse
        }
        return responses.removeFirst()
    }
}
