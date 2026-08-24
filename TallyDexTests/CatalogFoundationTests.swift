import Foundation
import GRDB
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

    func testTCGdexDecodesExactMarketplacePricesPerPrinting() async throws {
        let response = #"""
        {
          "id": "swsh3-136",
          "localId": "136",
          "name": "Furret",
          "set": { "id": "swsh3" },
          "variants": { "normal": true, "reverse": true },
          "pricing": {
            "cardmarket": {
              "updated": "2026-08-22T08:03:05.134Z",
              "unit": "EUR",
              "avg": 0.10,
              "trend": 0.07,
              "avg-holo": 0.28,
              "trend-holo": 0.26
            },
            "tcgplayer": {
              "updated": "2026-08-22T08:03:19.776Z",
              "unit": "USD",
              "normal": { "marketPrice": 0.21 },
              "reverse-holofoil": { "marketPrice": 0.43 }
            }
          }
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "swsh3-136")

        XCTAssertEqual(snapshot.prices.count, 4)
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket && $0.variant == .normal }?.amount,
            0.07
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket && $0.variant == .reverseHolo }?.amount,
            0.26
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .tcgplayer && $0.variant == .normal }?.amount,
            0.21
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .tcgplayer && $0.variant == .reverseHolo }?.amount,
            0.43
        )
    }

    func testCardmarketDoesNotGuessWhichFoilPriceBelongsToMultipleFoilVariants() async throws {
        let response = #"""
        {
          "id": "example-1",
          "localId": "1",
          "name": "Example",
          "set": { "id": "example" },
          "variants": { "normal": true, "reverse": true, "holo": true },
          "pricing": {
            "cardmarket": {
              "updated": "2026-08-22T08:03:05.134Z",
              "unit": "EUR",
              "trend": 1.00,
              "trend-holo": 4.00
            }
          }
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "example-1")

        XCTAssertEqual(snapshot.prices.map(\.variant), [.normal])
    }

    func testDetailedVariantPricingUsesExactMarketplacePrinting() async throws {
        let response = #"""
        {
          "id": "me01-184",
          "localId": "184",
          "name": "Lillie's Determination",
          "set": { "id": "me01" },
          "variants": { "normal": false, "reverse": false, "holo": true },
          "variants_detailed": [
            {
              "type": "holo",
              "pricing": {
                "cardmarket": {
                  "updated": "2026-08-24T08:03:04.743Z",
                  "unit": "EUR",
                  "idProduct": 885188,
                  "trend": 61.31,
                  "trend-holo": 0
                },
                "tcgplayer": {
                  "updated": "2026-08-24T08:03:26.603Z",
                  "unit": "USD",
                  "holofoil": { "productId": 693184, "marketPrice": 64.16 }
                }
              }
            }
          ],
          "pricing": {
            "cardmarket": {
              "updated": "2026-08-24T08:03:04.743Z",
              "unit": "EUR",
              "trend": 61.31,
              "trend-holo": 0
            }
          }
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "me01-184")

        XCTAssertEqual(snapshot.prices.count, 2)
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket && $0.variant == .holo }?.amount,
            61.31
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .tcgplayer && $0.variant == .holo }?.amount,
            64.16
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket }?.marketplaceURL?.absoluteString,
            "https://www.cardmarket.com/en/Pokemon/Products?idProduct=885188"
        )
    }

    func testDetailedMarketplaceDataRepairsIncorrectLegacyVariantFlags() async throws {
        let response = #"""
        {
          "id": "me04-002",
          "localId": "002",
          "name": "Kakuna",
          "set": { "id": "me04" },
          "variants": { "normal": true, "reverse": false, "holo": false },
          "variants_detailed": [
            {
              "type": "normal",
              "pricing": {
                "cardmarket": {
                  "updated": "2026-08-24T08:03:04.576Z",
                  "unit": "EUR",
                  "idProduct": 886394,
                  "trend": 0.04,
                  "trend-holo": 0.10
                },
                "tcgplayer": {
                  "updated": "2026-08-24T08:03:27.460Z",
                  "unit": "USD",
                  "normal": { "productId": 693502, "marketPrice": 0.13 },
                  "reverse-holofoil": { "productId": 693502, "marketPrice": 0.24 }
                }
              }
            }
          ]
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "me04-002")

        XCTAssertEqual(snapshot.variants, [.normal, .reverseHolo])
        XCTAssertEqual(snapshot.prices.count, 4)
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket && $0.variant == .reverseHolo }?.amount,
            0.10
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket }?.productID,
            886394
        )
    }

    func testTCGdexCombinesLegacyAndDetailedVariantData() async throws {
        let response = #"""
        {
          "id": "me04-001",
          "localId": "001",
          "name": "Weedle",
          "set": { "id": "me04" },
          "variants": { "normal": true, "reverse": false },
          "variants_detailed": [
            { "type": "normal" },
            { "type": "reverse" }
          ]
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "me04-001")

        XCTAssertEqual(snapshot.variants, [.normal, .reverseHolo])
    }

    func testVariantOverridesFillKnownTCGdexGaps() {
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal], cardID: "me04-001"),
            [.normal]
        )
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

    func testRepositoryRefreshPreservesPreviouslyCachedVariants() async throws {
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
        XCTAssertEqual(storedVariants, [.normal, .reverseHolo, .holo])
    }

    func testRepositoryUsesPricedPrintingToRepairCachedVariantAndPersistsProductLink() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.upsertSeries([
            CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil),
        ])
        try await repository.replaceSets(
            [set(id: "me04", seriesID: "me", name: "Chaos Rising")],
            forSeriesID: "me"
        )
        let card = CatalogCard(
            id: "me04-008",
            setID: "me04",
            localID: "008",
            name: "Vulpix",
            imageURL: nil,
            category: "Pokemon",
            illustrator: nil,
            rarity: "Common"
        )
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [
                CatalogPriceQuote(
                    cardID: card.id,
                    variant: .reverseHolo,
                    source: .cardmarket,
                    currencyCode: "EUR",
                    amount: 0.08,
                    updatedAt: .now,
                    productID: 886400
                ),
            ]
        ))

        let variants = try await repository.fetchVariants(cardID: card.id)
        let prices = try await repository.fetchPrices(cardIDs: [card.id])

        XCTAssertEqual(variants, [.normal, .reverseHolo])
        XCTAssertEqual(prices[card.id]?.first?.productID, 886400)
        XCTAssertEqual(
            prices[card.id]?.first?.marketplaceURL?.absoluteString,
            "https://www.cardmarket.com/en/Pokemon/Products?idProduct=886400"
        )
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

    func testRepositoryCachesCurrentPricesAndDailyHistory() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Sprigatito",
            imageURL: nil, category: nil, illustrator: nil, rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        let firstDate = ISO8601DateFormatter().date(from: "2026-08-21T08:00:00Z")!
        let secondDate = ISO8601DateFormatter().date(from: "2026-08-22T08:00:00Z")!
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(cardID: card.id, variant: .normal, source: .cardmarket,
                           currencyCode: "EUR", amount: 1.25, updatedAt: firstDate)]
        ))
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(cardID: card.id, variant: .normal, source: .cardmarket,
                           currencyCode: "EUR", amount: 1.50, updatedAt: secondDate)]
        ))
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(cardID: card.id, variant: .normal, source: .cardmarket,
                           currencyCode: "EUR", amount: 1.75, updatedAt: secondDate)]
        ))

        let current = try await repository.fetchPrices(cardIDs: [card.id])[card.id]
        let history = try await repository.fetchPriceHistory(
            cardID: card.id,
            source: .cardmarket
        )
        let historyCount = try await database.queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM catalogPriceHistory")
        }

        XCTAssertEqual(current?.first?.amount, 1.75)
        XCTAssertEqual(historyCount, 2)
        XCTAssertEqual(history.map(\.amount), [1.25, 1.75])
        XCTAssertEqual(history.map(\.variant), [.normal, .normal])
        XCTAssertEqual(history.map(\.source), [.cardmarket, .cardmarket])
        XCTAssertEqual(history.map(\.currencyCode), ["EUR", "EUR"])
    }

    func testPriceHistoryRangesAndSummaryUseExactOrderedPoints() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24)
        ))
        let day: (Int) -> Date = { offset in
            calendar.date(byAdding: .day, value: offset, to: referenceDate)!
        }
        let points = [
            CatalogPriceHistoryPoint(
                cardID: "card", variant: .normal, source: .cardmarket,
                day: day(-31), currencyCode: "EUR", amount: 4,
                sourceUpdatedAt: day(-31)
            ),
            CatalogPriceHistoryPoint(
                cardID: "card", variant: .normal, source: .cardmarket,
                day: day(-6), currencyCode: "EUR", amount: 5,
                sourceUpdatedAt: day(-6)
            ),
            CatalogPriceHistoryPoint(
                cardID: "card", variant: .normal, source: .cardmarket,
                day: referenceDate, currencyCode: "EUR", amount: 6,
                sourceUpdatedAt: referenceDate
            ),
        ].reversed()

        let sevenDays = CatalogPriceHistoryRange.sevenDays.filter(
            Array(points),
            relativeTo: referenceDate,
            calendar: calendar
        )
        let thirtyDays = CatalogPriceHistoryRange.thirtyDays.filter(
            Array(points),
            relativeTo: referenceDate,
            calendar: calendar
        )
        let all = CatalogPriceHistoryRange.all.filter(
            Array(points),
            relativeTo: referenceDate,
            calendar: calendar
        )
        let summary = try XCTUnwrap(CatalogPriceHistorySummary(points: sevenDays))

        XCTAssertEqual(sevenDays.map(\.amount), [5, 6])
        XCTAssertEqual(thirtyDays.map(\.amount), [5, 6])
        XCTAssertEqual(all.map(\.amount), [4, 5, 6])
        XCTAssertEqual(summary.current, 6)
        XCTAssertEqual(summary.absoluteChange, 1)
        XCTAssertEqual(summary.percentageChange, 20)
        XCTAssertEqual(summary.low, 5)
        XCTAssertEqual(summary.high, 6)
    }

    func testCollectionValueUsesExactVariantsQuantitiesAndReportsMissingPrices() {
        let date = Date(timeIntervalSince1970: 1)
        let entries = [
            CollectionVariantEntry(cardID: "one", variant: .normal, quantity: 2, updatedAt: date),
            CollectionVariantEntry(cardID: "one", variant: .reverseHolo, quantity: 1, updatedAt: date),
        ]
        let prices = [
            "one": [
                CatalogPriceQuote(cardID: "one", variant: .normal, source: .cardmarket,
                                  currencyCode: "EUR", amount: 1.25, updatedAt: date),
            ],
        ]

        let summary = CatalogValueCalculator.summary(
            entries: entries,
            prices: prices,
            source: .cardmarket
        )

        XCTAssertEqual(summary.amount, 2.50)
        XCTAssertEqual(summary.pricedVariants, 1)
        XCTAssertEqual(summary.missingVariants, 1)
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
