import Foundation
import GRDB
import UIKit
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

    func testTCGdexCapsRetryAfterDelay() async throws {
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(), statusCode: 429, retryAfter: "3600"),
            HTTPResponse(
                data: Data(#"[{"id":"base","name":"Base"}]"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let delays = DurationRecorder()
        let client = TCGdexClient(
            httpClient: stub,
            retryPolicy: .init(maximumAttempts: 2, baseDelay: .zero),
            sleep: { duration in await delays.append(duration) }
        )

        _ = try await client.fetchSeriesIndex()

        let recordedDelays = await delays.values
        XCTAssertEqual(recordedDelays, [.seconds(30)])
    }

    func testTCGdexDoesNotRetryCancelledRequest() async {
        let stub = CancelledHTTPClientStub()
        let client = TCGdexClient(
            httpClient: stub,
            retryPolicy: .init(maximumAttempts: 3, baseDelay: .zero),
            sleep: { _ in }
        )

        do {
            _ = try await client.fetchSeriesIndex()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }

        let requestCount = await stub.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testTCGdexUsesETagForUnchangedCompleteCardIndex() async throws {
        let stub = HTTPClientStub(responses: [
            HTTPResponse(
                data: Data(#"[{"id":"base-1","localId":"1","name":"Card"}]"#.utf8),
                statusCode: 200,
                retryAfter: nil,
                etag: "index-v1"
            ),
            HTTPResponse(data: Data(), statusCode: 304, retryAfter: nil),
        ])
        let client = TCGdexClient(
            httpClient: stub,
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero),
            etagStore: TCGdexETagStore()
        )

        _ = try await client.fetchCardIndex()
        do {
            _ = try await client.fetchCardIndex()
            XCTFail("Expected an unchanged response")
        } catch {
            XCTAssertEqual(error as? TCGdexError, .notModified)
        }

        let firstHeader = await stub.header("If-None-Match", requestIndex: 0)
        let secondHeader = await stub.header("If-None-Match", requestIndex: 1)
        XCTAssertNil(firstHeader)
        XCTAssertEqual(secondHeader, "index-v1")
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

    func testTCGdexDecodesRichCardMetadataWithoutFlatteningIt() async throws {
        let response = #"""
        {
          "id": "base1-4",
          "localId": "4",
          "name": "Charizard",
          "category": "Pokemon",
          "dexId": [6],
          "hp": 120,
          "types": ["Fire"],
          "evolveFrom": "Charmeleon",
          "stage": "Stage2",
          "attacks": [{
            "cost": ["Fire", "Fire", "Colorless"],
            "name": "Fire Spin",
            "damage": 100,
            "effect": "Discard 2 Energy."
          }],
          "abilities": [{
            "type": "Pokemon Power",
            "name": "Energy Burn",
            "effect": "Attached Energy becomes Fire Energy."
          }],
          "weaknesses": [{"type": "Water", "value": "×2"}],
          "resistances": [{"type": "Fighting", "value": "-30"}],
          "retreat": 3,
          "regulationMark": "G",
          "legal": {"standard": false, "expanded": true},
          "description": "Spits fire hot enough to melt boulders.",
          "updated": "2026-08-20T08:25:49+01:00",
          "set": {"id": "base1"},
          "variants": {"holo": true}
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "base1-4")
        let metadata = try XCTUnwrap(snapshot.card.metadata)

        XCTAssertEqual(metadata.dexIDs, [6])
        XCTAssertEqual(metadata.hp, 120)
        XCTAssertEqual(metadata.types, ["Fire"])
        XCTAssertEqual(metadata.evolvesFrom, "Charmeleon")
        XCTAssertEqual(metadata.stage, "Stage2")
        XCTAssertEqual(metadata.attacks.first?.damage, "100")
        XCTAssertEqual(metadata.attacks.first?.cost, ["Fire", "Fire", "Colorless"])
        XCTAssertEqual(metadata.abilities.first?.name, "Energy Burn")
        XCTAssertEqual(metadata.weaknesses.first, CatalogTypeModifier(type: "Water", value: "×2"))
        XCTAssertEqual(metadata.resistances.first, CatalogTypeModifier(type: "Fighting", value: "-30"))
        XCTAssertEqual(metadata.retreatCost, 3)
        XCTAssertEqual(metadata.regulationMark, "G")
        XCTAssertEqual(metadata.legality, CatalogCardLegality(standard: false, expanded: true))
        XCTAssertEqual(metadata.flavorText, "Spits fire hot enough to melt boulders.")
        XCTAssertNotNil(metadata.updatedAt)
    }

    func testRepositoryPersistsRichCardMetadata() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "base", name: "Original", logoURL: nil)
        let catalogSet = set(id: "base1", seriesID: "base", name: "Base Set")
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        let metadata = CatalogCardMetadata(
            dexIDs: [6], hp: 120, types: ["Fire"], evolvesFrom: "Charmeleon",
            stage: "Stage2", suffix: nil,
            attacks: [CatalogCardAttack(name: "Fire Spin", cost: ["Fire"], damage: "100", effect: nil)],
            abilities: [], weaknesses: [], resistances: [], retreatCost: 3,
            regulationMark: nil, legality: nil, rulesText: nil, trainerType: nil,
            energyType: nil, flavorText: nil, updatedAt: nil
        )
        let card = CatalogCard(
            id: "base1-4", setID: "base1", localID: "4", name: "Charizard",
            imageURL: nil, category: "Pokemon", illustrator: nil, rarity: "Rare Holo",
            metadata: metadata
        )

        try await repository.replaceCard(CatalogCardSnapshot(card: card, variants: [.holo]))

        let storedCard = try await repository.fetchCard(id: card.id)
        XCTAssertEqual(storedCard?.metadata, metadata)
    }

    func testTCGdexPreservesExactDetailedPrintingMetadata() async throws {
        let response = #"""
        {
          "id": "base1-4",
          "localId": "4",
          "name": "Charizard",
          "set": { "id": "base1" },
          "variants": { "holo": true, "firstEdition": true },
          "variants_detailed": [
            {
              "type": "holo",
              "subtype": "shadowless",
              "size": "standard",
              "stamp": ["1st-edition"],
              "foil": "cosmos",
              "languages": ["en", "fr"],
              "variantId": "exact-printing-id",
              "thirdParty": {
                "cardmarket": 660224,
                "tcgplayer": 106999,
                "cardtrader": 12345
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

        let snapshot = try await client.fetchCard(id: "base1-4")
        let printing = try XCTUnwrap(snapshot.printings.first)

        XCTAssertEqual(printing.id, "base1-4|exact-printing-id")
        XCTAssertEqual(printing.kind, .firstEdition)
        XCTAssertEqual(printing.rawType, "holo")
        XCTAssertEqual(printing.subtype, "shadowless")
        XCTAssertEqual(printing.size, "standard")
        XCTAssertEqual(printing.stamps, ["1st-edition"])
        XCTAssertEqual(printing.foil, "cosmos")
        XCTAssertEqual(printing.languages, ["en", "fr"])
        XCTAssertEqual(printing.cardmarketProductID, 660224)
        XCTAssertEqual(printing.tcgplayerProductID, 106999)
        XCTAssertEqual(printing.cardtraderProductID, 12345)
        XCTAssertEqual(printing.displayName, "First edition · Shadowless · Cosmos foil")
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
              "avg1": 0.06,
              "avg7": 0.08,
              "avg30": 0.11,
              "avg-holo": 0.28,
              "trend-holo": 0.26,
              "avg1-holo": 0.24,
              "avg7-holo": 0.25,
              "avg30-holo": 0.29
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
        let normalCardmarket = snapshot.prices.first {
            $0.source == .cardmarket && $0.variant == .normal
        }
        XCTAssertEqual(normalCardmarket?.average1Day, 0.06)
        XCTAssertEqual(normalCardmarket?.average7Days, 0.08)
        XCTAssertEqual(normalCardmarket?.average30Days, 0.11)
        let reverseCardmarket = snapshot.prices.first {
            $0.source == .cardmarket && $0.variant == .reverseHolo
        }
        XCTAssertEqual(reverseCardmarket?.average1Day, 0.24)
        XCTAssertEqual(reverseCardmarket?.average7Days, 0.25)
        XCTAssertEqual(reverseCardmarket?.average30Days, 0.29)
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
                  "trend-holo": 0,
                  "avg1": 60.00,
                  "avg7": 56.61,
                  "avg30": 54.25
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
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket }?.average1Day,
            60.00
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket }?.average7Days,
            56.61
        )
        XCTAssertEqual(
            snapshot.prices.first { $0.source == .cardmarket }?.average30Days,
            54.25
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
            [.normal, .prerelease, .prereleaseStaff]
        )
        XCTAssertEqual(
            CatalogVariantOverrides.apply(to: [.normal], cardID: "swshp-SWSH186"),
            [.normal, .prerelease, .prereleaseStaff]
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

    func testRepositoryPersistsAndRefreshesExactPrintingsWithoutErasingOnLegacyResponse() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.upsertSeries([
            CatalogSeries(id: "base", name: "Base", logoURL: nil),
        ])
        try await repository.replaceSets(
            [set(id: "base1", seriesID: "base", name: "Base Set")],
            forSeriesID: "base"
        )
        let card = CatalogCard(
            id: "base1-4",
            setID: "base1",
            localID: "4",
            name: "Charizard",
            imageURL: nil,
            category: "Pokemon",
            illustrator: nil,
            rarity: "Rare Holo"
        )
        let unlimited = CatalogPrinting(
            cardID: card.id,
            providerID: "unlimited-id",
            rawType: "holo",
            kind: .holo,
            subtype: "unlimited",
            size: "standard",
            stamps: [],
            foil: nil,
            languages: ["en"],
            cardmarketProductID: 273699,
            tcgplayerProductID: 42382,
            cardtraderProductID: nil
        )
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.holo],
            printings: [unlimited]
        ))
        let firstStoredPrintings = try await repository.fetchPrintings(cardID: card.id)
        XCTAssertEqual(firstStoredPrintings, [unlimited])

        // A legacy response without detailed records must not destroy cached
        // exact metadata or affect broad ownership keys.
        try await repository.replaceCard(CatalogCardSnapshot(card: card, variants: [.holo]))
        let preservedPrintings = try await repository.fetchPrintings(cardID: card.id)
        XCTAssertEqual(preservedPrintings, [unlimited])

        let shadowless = CatalogPrinting(
            cardID: card.id,
            providerID: "shadowless-id",
            rawType: "holo",
            kind: .firstEdition,
            subtype: "shadowless",
            size: "standard",
            stamps: ["1st-edition"],
            foil: nil,
            languages: [],
            cardmarketProductID: 660224,
            tcgplayerProductID: 106999,
            cardtraderProductID: nil
        )
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card,
            variants: [.holo, .firstEdition],
            printings: [shadowless]
        ))
        let refreshedPrintings = try await repository.fetchPrintings(cardID: card.id)
        XCTAssertEqual(refreshedPrintings, [shadowless])
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
                    productID: 886400,
                    average1Day: 0.07,
                    average7Days: 0.08,
                    average30Days: 0.09
                ),
            ]
        ))

        let variants = try await repository.fetchVariants(cardID: card.id)
        let prices = try await repository.fetchPrices(cardIDs: [card.id])

        XCTAssertEqual(variants, [.normal, .reverseHolo])
        XCTAssertEqual(prices[card.id]?.first?.productID, 886400)
        XCTAssertEqual(prices[card.id]?.first?.average1Day, 0.07)
        XCTAssertEqual(prices[card.id]?.first?.average7Days, 0.08)
        XCTAssertEqual(prices[card.id]?.first?.average30Days, 0.09)
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

    func testArtworkCacheUsesWebPForLogosAndPNGForSymbols() {
        let extensionless = URL(string: "https://assets.tcgdex.net/en/sv/sv01/logo")!
        let png = URL(string: "https://example.com/logo.png")!
        let symbol = URL(string: "https://assets.tcgdex.net/en/sv/sv01/symbol")!

        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(extensionless).absoluteString,
            "https://assets.tcgdex.net/en/sv/sv01/logo.webp"
        )
        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(
                symbol,
                category: .expansionSymbols
            ).absoluteString,
            "https://assets.tcgdex.net/en/sv/sv01/symbol.png"
        )
        XCTAssertEqual(CatalogArtworkCache.resolvedAssetURL(png), png)
    }

    func testCatalogMetadataFallbackPreservesArtwork() {
        let seriesLogo = URL(string: "https://assets.example/series")!
        let setLogo = URL(string: "https://assets.example/set")!
        let symbol = URL(string: "https://assets.example/symbol")!
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let fallbackSeries = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: seriesLogo)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let fallbackSet = CatalogSet(
            id: catalogSet.id,
            seriesID: catalogSet.seriesID,
            name: catalogSet.name,
            abbreviation: "SVI",
            logoURL: setLogo,
            symbolURL: symbol,
            officialCardCount: 198,
            totalCardCount: 258,
            releaseDate: "2023-03-31",
            rarityCounts: nil
        )

        XCTAssertEqual(series.fillingMissingMetadata(from: fallbackSeries).logoURL, seriesLogo)
        XCTAssertEqual(catalogSet.fillingMissingMetadata(from: fallbackSet).logoURL, setLogo)
        XCTAssertEqual(catalogSet.fillingMissingMetadata(from: fallbackSet).symbolURL, symbol)
    }

    func testUpcomingAvailabilityUsesExactIDsAndNormalizedExactNamesOnly() throws {
        let referenceDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 9, day: 9)
            )
        )
        let announced = CatalogSet(
            id: "upcoming-30c", seriesID: "me", name: "30th Celebration",
            abbreviation: nil, logoURL: nil, symbolURL: nil,
            officialCardCount: 0, totalCardCount: 0,
            releaseDate: "2026-09-16", rarityCounts: nil
        )
        let recentlyReleased = CatalogSet(
            id: "me05", seriesID: "me", name: "Pitch Black",
            abbreviation: nil, logoURL: nil, symbolURL: nil,
            officialCardCount: 86, totalCardCount: 122,
            releaseDate: "2026-08-22", rarityCounts: nil
        )
        let old = set(id: "me01", seriesID: "me", name: "Mega Evolution")
        let candidates = CatalogUpcomingAvailability.candidates(
            in: [CatalogSeriesGroup(
                series: CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil),
                sets: [announced, recentlyReleased, old]
            )],
            relativeTo: referenceDate
        )
        XCTAssertEqual(Set(candidates.map(\.id)), Set([announced.id, recentlyReleased.id]))

        let exactRemote = CatalogSet(
            id: "me06", seriesID: "me", name: "30th Celebration",
            abbreviation: "30C", logoURL: URL(string: "https://assets.example/logo"),
            symbolURL: nil, officialCardCount: 100, totalCardCount: 130,
            releaseDate: "2026-09-16", rarityCounts: nil
        )
        let nearRemote = CatalogSet(
            id: "me07", seriesID: "me", name: "30th Celebration Special",
            abbreviation: nil, logoURL: nil, symbolURL: nil,
            officialCardCount: 0, totalCardCount: 0,
            releaseDate: nil, rarityCounts: nil
        )
        let snapshot = CatalogSeriesSnapshot(
            series: CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil),
            sets: [nearRemote, exactRemote]
        )
        XCTAssertEqual(
            CatalogUpcomingAvailability.providerSet(for: announced, in: snapshot)?.id,
            exactRemote.id
        )
        let unmatched = CatalogSet(
            id: "upcoming-other", seriesID: "me", name: "Unknown Set",
            abbreviation: nil, logoURL: nil, symbolURL: nil,
            officialCardCount: 0, totalCardCount: 0,
            releaseDate: nil, rarityCounts: nil
        )
        XCTAssertNil(CatalogUpcomingAvailability.providerSet(for: unmatched, in: snapshot))
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

    func testArtworkCacheRepairsTCGdexUniversalSymbolPath() {
        let symbol = URL(string: "https://assets.tcgdex.net/univ/swsh/swsh9/symbol")!
        XCTAssertEqual(
            CatalogArtworkCache.resolvedAssetURL(
                symbol,
                category: .expansionSymbols
            ).absoluteString,
            "https://assets.tcgdex.net/en/swsh/swsh9/symbol.png"
        )
    }

    func testArtworkFallbackUsesVerifiedParentSetPathsOnly() {
        let galleryCard = CatalogCard(
            id: "swsh12.5gg-GG36",
            setID: "swsh12.5gg",
            localID: "GG36",
            name: "Entei V",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        XCTAssertEqual(
            galleryCard.thumbnailArtworkReference.map {
                CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
            },
            "https://assets.tcgdex.net/en/swsh/swsh12.5/GG36/low.webp"
        )

        let providerGap = CatalogCard(
            id: "swsh12.5gg-GG48",
            setID: "swsh12.5gg",
            localID: "GG48",
            name: "Zacian V",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        XCTAssertEqual(
            providerGap.thumbnailArtworkReference.map {
                CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
            },
            "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/SWSH12PT5GG/SWSH12PT5GG_EN_GG48.png"
        )

        let lowOnly = CatalogCard(
            id: "swsh12.5gg-GG06",
            setID: "swsh12.5gg",
            localID: "GG06",
            name: "Goodra",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        XCTAssertNotNil(lowOnly.thumbnailArtworkReference)
        XCTAssertEqual(lowOnly.fullArtworkReference?.category, .cardArtwork)

        let unrelated = CatalogCard(
            id: "tk-example-1",
            setID: "tk-example",
            localID: "1",
            name: "Example",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        XCTAssertEqual(
            unrelated.thumbnailArtworkReference.map {
                CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
            },
            "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/TK-EXAMPLE/TK-EXAMPLE_EN_1.png"
        )
    }

    func testArtworkFallbackRepairsRioluGalarianGalleryImage() {
        let riolu = CatalogCard(
            id: "swsh12.5gg-GG26",
            setID: "swsh12.5gg",
            localID: "GG26",
            name: "Riolu",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )

        XCTAssertEqual(
            riolu.thumbnailArtworkReference.map {
                CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
            },
            "https://assets.tcgdex.net/en/swsh/swsh12.5/GG26/low.webp"
        )
        XCTAssertEqual(
            riolu.fullArtworkReference.map {
                CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
            },
            "https://assets.tcgdex.net/en/swsh/swsh12.5/GG26/high.webp"
        )
    }

    func testArtworkFallbackUsesExactOfficialMEPAssets() {
        for (localID, name) in [("010", "Riolu"), ("012", "Mega Lucario ex"), ("033", "Mega Lucario ex")] {
            let card = CatalogCard(
                id: "mep-\(localID)",
                setID: "mep",
                localID: localID,
                name: name,
                imageURL: nil,
                category: nil,
                illustrator: nil,
                rarity: nil
            )
            let expected = "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/MEP/MEP_EN_\(Int(localID)!).png"

            XCTAssertEqual(
                card.thumbnailArtworkReference.map {
                    CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
                },
                expected
            )
            XCTAssertEqual(
                card.fullArtworkReference.map {
                    CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
                },
                expected
            )
            XCTAssertEqual(card.fullArtworkReference?.category, .cardArtwork)
        }
    }

    func testArtworkFallbackUsesOfficialSetAndCollectorIdentityUniversally() {
        let examples = [
            ("smp-SM192", "smp", "SM192", "Lucario & Melmetal GX", "SMP", "SM192"),
            ("sm6-122", "sm6", "122", "Lucario GX", "SM6", "122"),
            ("sm3.5-001", "sm3.5", "001", "Example", "SM35", "1"),
        ]

        for (id, setID, localID, name, assetCode, number) in examples {
            let card = CatalogCard(
                id: id,
                setID: setID,
                localID: localID,
                name: name,
                imageURL: nil,
                category: nil,
                illustrator: nil,
                rarity: nil
            )
            XCTAssertEqual(
                card.thumbnailArtworkReference.map {
                    CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString
                },
                "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/\(assetCode)/\(assetCode)_EN_\(number).png"
            )
        }
    }

    func testArtworkCacheFallsBackToOfficialAssetWhenTCGdexImageFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(), statusCode: 404, retryAfter: nil),
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub)
        let card = CatalogCard(
            id: "me05-001",
            setID: "me05",
            localID: "001",
            name: "Example",
            imageURL: URL(string: "https://assets.tcgdex.net/en/me/me05/001"),
            category: nil,
            illustrator: nil,
            rarity: nil
        )

        let references = card.thumbnailArtworkReferences
        XCTAssertEqual(
            references.map(\.url.absoluteString),
            [
                "https://assets.tcgdex.net/en/me/me05/001",
                "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/ME05/ME05_EN_1.png",
            ]
        )
        let resolved = try await cache.bestAvailableData(for: references)

        XCTAssertEqual(resolved, imageData)
        let requestCount = await stub.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testArtworkCacheCompressesLargeCardImagesOnDevice() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try makeNoisyPNG(width: 720, height: 1_008)
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: original, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub)
        let reference = CatalogArtworkReference(
            url: URL(string: "https://assets.example/card.png")!,
            category: .cardThumbnails
        )

        let optimized = try await cache.data(for: reference)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(optimized as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)

        XCTAssertLessThan(optimized.count, original.count)
        XCTAssertLessThanOrEqual(max(width, height), 480)
    }

    @MainActor
    func testFirstSetVisitWarmsEveryThumbnailOnlyOnce() async throws {
        let suiteName = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let store = ArtworkCacheStore(
            cache: CatalogArtworkCache(rootDirectory: root, httpClient: stub),
            userDefaults: defaults
        )
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let cards = ["001", "002"].map { localID in
            CatalogCard(
                id: "sv01-\(localID)",
                setID: "sv01",
                localID: localID,
                name: "Card \(localID)",
                imageURL: URL(string: "https://assets.example/\(localID).png"),
                category: nil,
                illustrator: nil,
                rarity: nil
            )
        }

        await store.warmImagesIfNeeded(set: catalogSet, cards: cards)
        await store.warmImagesIfNeeded(set: catalogSet, cards: cards)

        let requestCount = await stub.requestCount
        let signatures = defaults.dictionary(
            forKey: ArtworkCacheStore.warmedSetSignaturesKey
        ) as? [String: String]
        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(signatures?[catalogSet.id])
        XCTAssertNil(store.cacheWarmProgress[catalogSet.id])
    }

    @MainActor
    func testFirstCollectionVisitWarmsEveryThumbnailOnlyOnce() async throws {
        let suiteName = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let store = ArtworkCacheStore(
            cache: CatalogArtworkCache(rootDirectory: root, httpClient: stub),
            userDefaults: defaults
        )
        let card = CatalogCard(
            id: "smp-SM95", setID: "smp", localID: "SM95", name: "Lucario",
            imageURL: URL(string: "https://assets.example/lucario.png"),
            category: nil, illustrator: nil, rarity: nil
        )
        let key = "collection-test"

        await store.warmImagesIfNeeded(cacheKey: key, cards: [card])
        await store.warmImagesIfNeeded(cacheKey: key, cards: [card])

        let requestCount = await stub.requestCount
        XCTAssertEqual(requestCount, 1)
        let signatures = defaults.dictionary(
            forKey: ArtworkCacheStore.warmedSetSignaturesKey
        ) as? [String: String]
        XCTAssertNotNil(signatures?[key])
        XCTAssertNil(store.cacheWarmProgress[key])
    }

    @MainActor
    func testWarmCheckDoesNotRedownloadAnExistingCachedImage() async throws {
        let suiteName = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub)
        let reference = CatalogArtworkReference(
            url: URL(string: "https://assets.example/existing.png")!,
            category: .cardThumbnails
        )
        _ = try await cache.data(for: reference)
        let store = ArtworkCacheStore(cache: cache, userDefaults: defaults)
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Cached Card",
            imageURL: reference.url, category: nil, illustrator: nil, rarity: nil
        )

        await store.warmImagesIfNeeded(cacheKey: "existing-grid", cards: [card])

        let requestCount = await stub.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(store.cacheWarmProgress["existing-grid"])
        let signatures = defaults.dictionary(
            forKey: ArtworkCacheStore.warmedSetSignaturesKey
        ) as? [String: String]
        XCTAssertNotNil(signatures?["existing-grid"])
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

    func testRepositorySearchesCollectorNumberWithOfficialSetCount() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil)
        let ascendedHeroes = CatalogSet(
            id: "me02.5",
            seriesID: "me",
            name: "Ascended Heroes",
            abbreviation: "ASC",
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 217,
            totalCardCount: 295,
            releaseDate: nil,
            rarityCounts: nil
        )
        let card = CatalogCard(
            id: "me02.5-076",
            setID: "me02.5",
            localID: "076",
            name: "Lillie's Clefairy ex",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [ascendedHeroes]),
        ])
        try await repository.replaceSearchIndex([card])

        let results = try await repository.searchCards(query: "076/217")

        XCTAssertEqual(results.map(\.card.id), [card.id])
    }

    func testRepositorySearchesBySetCodeAndCollectorNumber() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let energySet = CatalogSet(
            id: "sve",
            seriesID: "sv",
            name: "Scarlet & Violet Energies",
            abbreviation: "SVE",
            logoURL: nil,
            symbolURL: nil,
            officialCardCount: 16,
            totalCardCount: 16,
            releaseDate: nil,
            rarityCounts: nil
        )
        let card = CatalogCard(
            id: "sve-012",
            setID: "sve",
            localID: "012",
            name: "Lightning Energy",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [energySet]),
        ])
        try await repository.replaceSearchIndex([card])

        let results = try await repository.searchCards(query: "SVE 012")

        XCTAssertEqual(results.map(\.card.id), [card.id])
    }

    func testScannerExtractsSetCodeAndCollectorNumber() {
        let candidates = CardTextRecognizer.setAndCollectorCandidates(
            in: ["Basic Lightning Energy", "SVEEN", "/ 012", "2024 Pokémon"]
        )

        XCTAssertTrue(candidates.contains("SVE 012"))
    }

    func testScannerRepairsPartiallyReadLanguageMarkAfterSetCode() {
        let candidates = CardTextRecognizer.setAndCollectorCandidates(
            in: ["Illus. fakuyoa", "J CRIE 022/086", "2026 Pokémon"]
        )

        XCTAssertEqual(Array(candidates.prefix(2)), ["CRIE 022", "CRI 022"])
    }

    func testRepositoryRecognizesVanGoghSearchAlias() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let promos = set(id: "svp", seriesID: "sv", name: "SVP Black Star Promos")
        let card = CatalogCard(
            id: "svp-085",
            setID: "svp",
            localID: "085",
            name: "Pikachu with Grey Felt Hat",
            imageURL: nil,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [promos]),
        ])
        try await repository.replaceSearchIndex([card])

        let results = try await repository.searchCards(query: "Van Gogh")

        XCTAssertEqual(results.map(\.card.id), [card.id])
    }

    func testRepositoryCanReturnMoreThanOneHundredVariantSearchCandidates() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let cards = (1...125).map { number in
            CatalogCard(
                id: "sv01-\(number)", setID: "sv01", localID: String(number),
                name: "Pikachu", imageURL: nil, category: nil, illustrator: nil, rarity: nil
            )
        }
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceSearchIndex(cards)

        let ordinaryResults = try await repository.searchCards(query: "Pikachu")
        let completeCandidates = try await repository.searchCards(query: "Pikachu", limit: nil)

        XCTAssertEqual(ordinaryResults.count, 100)
        XCTAssertEqual(completeCandidates.count, 125)
    }

    @MainActor
    func testStampedVariantSearchChecksMoreThanOneHundredCandidates() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let cards = (1...101).map { number in
            CatalogCard(
                id: "sv01-\(number)", setID: "sv01", localID: String(number),
                name: "Pikachu", imageURL: nil, category: nil, illustrator: nil, rarity: nil
            )
        }
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceSearchIndex(cards)
        for card in cards {
            try await repository.replaceCard(CatalogCardSnapshot(
                card: card,
                variants: [.prereleaseStaff]
            ))
        }
        let provider = CatalogProviderSpy(cardSnapshot: CatalogCardSnapshot(
            card: cards[0],
            variants: [.prereleaseStaff]
        ))
        let store = CatalogStore(provider: provider, repository: repository)

        let results = try await store.searchCards(query: "Pikachu staff")

        XCTAssertEqual(results.count, 101)
        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 0)
    }

    @MainActor
    func testStampedVariantSearchRejectsMoreThanFiveHundredCandidates() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let cards = (1...501).map { number in
            CatalogCard(
                id: "sv01-\(number)", setID: "sv01", localID: String(number),
                name: "Broad Match", imageURL: nil, category: nil, illustrator: nil, rarity: nil
            )
        }
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceSearchIndex(cards)
        let provider = CatalogProviderSpy(cardSnapshot: CatalogCardSnapshot(
            card: cards[0],
            variants: [.prereleaseStaff]
        ))
        let store = CatalogStore(provider: provider, repository: repository)

        do {
            _ = try await store.searchCards(query: "Broad Match staff")
            XCTFail("Expected an overly broad stamped search to be rejected")
        } catch let error as CatalogSearchError {
            XCTAssertEqual(error, .variantQueryTooBroad(candidateCount: 501))
        }

        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 0)
    }

    func testVariantSearchQueryRecognizesPrereleaseAndStaffTerms() {
        XCTAssertEqual(
            CatalogVariantSearchQuery("Lucario prerelease"),
            .init(textQuery: "Lucario", requirement: .prerelease)
        )
        XCTAssertEqual(
            CatalogVariantSearchQuery("pre-release SM95"),
            .init(textQuery: "SM95", requirement: .prerelease)
        )
        XCTAssertEqual(
            CatalogVariantSearchQuery("Lucario pre release staff"),
            .init(textQuery: "Lucario", requirement: .staff)
        )
        XCTAssertTrue(
            CatalogVariantSearchQuery.Requirement.prerelease.matches([.prereleaseStaff])
        )
    }

    @MainActor
    func testCatalogSearchHydratesAndFiltersStampedVariants() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sm", name: "Sun & Moon", logoURL: nil)
        let promoSet = set(id: "smp", seriesID: "sm", name: "SM Black Star Promos")
        let lucario = CatalogCard(
            id: "smp-test", setID: "smp", localID: "TEST", name: "Lucario",
            imageURL: nil, category: nil, illustrator: nil, rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [promoSet]),
        ])
        try await repository.replaceSearchIndex([lucario])
        let provider = CatalogProviderSpy(cardSnapshot: CatalogCardSnapshot(
            card: lucario,
            variants: [.prerelease, .prereleaseStaff]
        ))
        let store = CatalogStore(provider: provider, repository: repository)

        let staffResults = try await store.searchCards(query: "Lucario staff")
        let prereleaseResults = try await store.searchCards(query: "prerelease Lucario")

        XCTAssertEqual(staffResults.map(\.card.id), [lucario.id])
        XCTAssertEqual(prereleaseResults.map(\.card.id), [lucario.id])
        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 1, "The second query should reuse the hydrated variants")
    }

    @MainActor
    func testBarePrereleaseSearchReturnsKnownAndCachedStampedCards() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sm", name: "Sun & Moon", logoURL: nil)
        let promos = set(id: "smp", seriesID: series.id, name: "SM Black Star Promos")
        let lucario = CatalogCard(
            id: "smp-SM95", setID: promos.id, localID: "SM95", name: "Lucario",
            imageURL: nil, category: nil, illustrator: nil, rarity: nil
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [promos]),
        ])
        try await repository.replaceSearchIndex([lucario])
        let provider = CatalogProviderSpy(cardSnapshot: CatalogCardSnapshot(
            card: lucario,
            variants: [.normal]
        ))
        let store = CatalogStore(provider: provider, repository: repository)

        let results = try await store.searchCards(query: "prerelease")

        XCTAssertEqual(results.map(\.card.id), [lucario.id])
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

    func testForeverHistorySizeLimitsMapToApproximatePointCeilings() {
        XCTAssertEqual(
            CatalogPriceHistorySizeLimit.allCases.map(\.title),
            ["50 MB", "100 MB", "250 MB", "500 MB", "1 GB"]
        )
        XCTAssertEqual(CatalogPriceHistorySizeLimit.mb50.maximumPointCount, 312_500)
        XCTAssertEqual(CatalogPriceHistorySizeLimit.mb100.maximumPointCount, 625_000)
        XCTAssertEqual(CatalogPriceHistorySizeLimit.mb250.maximumPointCount, 1_562_500)
        XCTAssertEqual(CatalogPriceHistorySizeLimit.mb500.maximumPointCount, 3_125_000)
        XCTAssertEqual(CatalogPriceHistorySizeLimit.gb1.maximumPointCount, 6_250_000)
    }

    func testPriceStorageCanPruneAndPurgeWithoutTouchingCardData() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Sprigatito",
            imageURL: nil, category: "Pokemon", illustrator: nil, rarity: "Common"
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        let dates = [
            "2026-01-01T08:00:00Z",
            "2026-04-01T08:00:00Z",
            "2026-08-01T08:00:00Z",
        ].compactMap(ISO8601DateFormatter().date)
        for (index, date) in dates.enumerated() {
            try await repository.replaceCard(CatalogCardSnapshot(
                card: card,
                variants: [.normal],
                prices: [.init(
                    cardID: card.id,
                    variant: .normal,
                    source: .cardmarket,
                    currencyCode: "EUR",
                    amount: Double(index + 1),
                    updatedAt: date
                )]
            ))
        }
        try await repository.setMetadataDate(
            dates.last!,
            forKey: "catalog.price.\(card.id).lastRefresh"
        )

        var statistics = try await repository.priceStorageStatistics()
        XCTAssertEqual(statistics.currentPriceCount, 1)
        XCTAssertEqual(statistics.historyPointCount, 3)
        XCTAssertGreaterThan(statistics.databaseByteCount, 0)

        let cutoff = ISO8601DateFormatter().date(from: "2026-03-01T00:00:00Z")!
        let removed = try await repository.prunePriceHistory(
            olderThan: cutoff,
            maximumPoints: 1
        )
        XCTAssertEqual(removed, 2)
        statistics = try await repository.priceStorageStatistics()
        XCTAssertEqual(statistics.historyPointCount, 1)

        try await repository.clearPriceHistory()
        statistics = try await repository.priceStorageStatistics()
        XCTAssertEqual(statistics.historyPointCount, 0)
        XCTAssertEqual(statistics.currentPriceCount, 1)
        let cachedCardAfterHistoryClear = try await repository.fetchCard(id: card.id)
        XCTAssertEqual(cachedCardAfterHistoryClear?.name, card.name)

        try await repository.clearAllPrices()
        statistics = try await repository.priceStorageStatistics()
        XCTAssertEqual(statistics.currentPriceCount, 0)
        let refreshMetadata = try await repository.metadataDate(
            forKey: "catalog.price.\(card.id).lastRefresh"
        )
        let cachedCardAfterAllPricesClear = try await repository.fetchCard(id: card.id)
        XCTAssertNil(refreshMetadata)
        XCTAssertEqual(cachedCardAfterAllPricesClear?.rarity, "Common")
    }

    @MainActor
    func testCardDetailsUseFreshLocalPriceCache() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Sprigatito",
            imageURL: nil, category: "Pokemon", illustrator: nil, rarity: "Common"
        )
        let refreshDate = Date(timeIntervalSince1970: 10_000)
        let snapshot = CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(
                cardID: card.id,
                variant: .normal,
                source: .cardmarket,
                currencyCode: "EUR",
                amount: 1.25,
                updatedAt: refreshDate
            )]
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceCard(snapshot)
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.price.\(card.id).lastRefresh"
        )
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.price.\(card.id).rollingAveragesChecked"
        )
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.card.\(card.id).detailedPrintingsChecked"
        )
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.card.\(card.id).richMetadataChecked.v1"
        )
        let provider = CatalogProviderSpy(cardSnapshot: snapshot)
        let store = CatalogStore(
            provider: provider,
            repository: repository,
            now: { refreshDate.addingTimeInterval(60 * 60) }
        )

        let loaded = try await store.details(for: card)

        XCTAssertEqual(loaded.prices.first?.amount, 1.25)
        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 0)
    }

    @MainActor
    func testForcedCardDetailsBypassFreshLocalPriceCache() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Sprigatito",
            imageURL: nil, category: "Pokemon", illustrator: nil, rarity: "Common"
        )
        let refreshDate = Date(timeIntervalSince1970: 10_000)
        let cachedSnapshot = CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(
                cardID: card.id,
                variant: .normal,
                source: .cardmarket,
                currencyCode: "EUR",
                amount: 1.25,
                updatedAt: refreshDate,
                average1Day: 1.20
            )]
        )
        let refreshedSnapshot = CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(
                cardID: card.id,
                variant: .normal,
                source: .cardmarket,
                currencyCode: "EUR",
                amount: 1.50,
                updatedAt: refreshDate.addingTimeInterval(60),
                average1Day: 1.45
            )]
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceCard(cachedSnapshot)
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.price.\(card.id).lastRefresh"
        )
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.price.\(card.id).rollingAveragesChecked"
        )
        let provider = CatalogProviderSpy(cardSnapshot: refreshedSnapshot)
        let store = CatalogStore(
            provider: provider,
            repository: repository,
            now: { refreshDate.addingTimeInterval(60 * 60) }
        )

        let loaded = try await store.details(for: card, forceRefresh: true)

        XCTAssertEqual(loaded.prices.first?.amount, 1.50)
        XCTAssertEqual(loaded.prices.first?.average1Day, 1.45)
        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 1)
    }

    @MainActor
    func testCardDetailsRefreshLegacyCacheOnceForRollingAverages() async throws {
        let database = try CatalogDatabase.inMemory()
        let repository = GRDBCatalogRepository(database: database)
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        let catalogSet = set(id: "sv01", seriesID: "sv", name: "Scarlet & Violet")
        let card = CatalogCard(
            id: "sv01-001", setID: "sv01", localID: "001", name: "Sprigatito",
            imageURL: nil, category: "Pokemon", illustrator: nil, rarity: "Common"
        )
        let refreshDate = Date(timeIntervalSince1970: 10_000)
        let legacySnapshot = CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(
                cardID: card.id,
                variant: .normal,
                source: .cardmarket,
                currencyCode: "EUR",
                amount: 1.25,
                updatedAt: refreshDate
            )]
        )
        let refreshedSnapshot = CatalogCardSnapshot(
            card: card,
            variants: [.normal],
            prices: [.init(
                cardID: card.id,
                variant: .normal,
                source: .cardmarket,
                currencyCode: "EUR",
                amount: 1.25,
                updatedAt: refreshDate,
                average1Day: 1.20,
                average7Days: 1.15,
                average30Days: 1.10
            )]
        )
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [catalogSet]),
        ])
        try await repository.replaceCard(legacySnapshot)
        try await repository.setMetadataDate(
            refreshDate,
            forKey: "catalog.price.\(card.id).lastRefresh"
        )
        let provider = CatalogProviderSpy(cardSnapshot: refreshedSnapshot)
        let store = CatalogStore(
            provider: provider,
            repository: repository,
            now: { refreshDate.addingTimeInterval(60 * 60) }
        )

        let firstLoad = try await store.details(for: card)
        let secondLoad = try await store.details(for: card)

        XCTAssertEqual(firstLoad.prices.first?.average30Days, 1.10)
        XCTAssertEqual(secondLoad.prices.first?.average30Days, 1.10)
        let cardRequestCount = await provider.cardRequestCount
        XCTAssertEqual(cardRequestCount, 1)
        let rollingAverageRefresh = try await repository.metadataDate(
            forKey: "catalog.price.\(card.id).rollingAveragesChecked"
        )
        XCTAssertNotNil(rollingAverageRefresh)
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

    func testArtworkCacheLimitRemovesCardImagesBeforeCoreArtwork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cardDirectory = root.appendingPathComponent("card-artwork", isDirectory: true)
        let setDirectory = root.appendingPathComponent("set-logos", isDirectory: true)
        try FileManager.default.createDirectory(at: cardDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: setDirectory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: cardDirectory.appendingPathComponent("card.webp"))
        try Data(repeating: 2, count: 10).write(to: setDirectory.appendingPathComponent("set.png"))
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = CatalogArtworkCache(rootDirectory: root, maximumByteCount: 15)
        try await cache.enforceLimit()
        let snapshot = await cache.snapshot()

        XCTAssertEqual(snapshot.statistics(for: .cardArtwork), .empty)
        XCTAssertEqual(snapshot.statistics(for: .setLogos).fileCount, 1)
        XCTAssertEqual(snapshot.totalByteCount, 10)
    }

    func testOfflineSetArtworkSurvivesAutomaticCacheRemoval() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheRoot = base.appendingPathComponent("cache", isDirectory: true)
        let offlineRoot = base.appendingPathComponent("offline", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let cache = CatalogArtworkCache(
            rootDirectory: cacheRoot,
            offlineRootDirectory: offlineRoot,
            maximumByteCount: 1
        )
        let reference = CatalogArtworkReference(
            url: URL(string: "https://assets.example/cards/1")!,
            category: .cardArtwork,
            offlineSetID: "set-one"
        )
        let expected = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))

        try await cache.storeOffline(expected, for: reference, setID: "set-one")
        try await cache.removeAll()
        try await cache.enforceLimit()

        let restored = try await cache.data(for: reference)
        let statistics = await cache.offlineStatistics(setID: "set-one")
        XCTAssertEqual(restored, expected)
        XCTAssertEqual(statistics.fileCount, 1)
        XCTAssertEqual(statistics.byteCount, Int64(expected.count))

        try await cache.removeOfflineSet(setID: "set-one")
        let removedStatistics = await cache.offlineStatistics(setID: "set-one")
        XCTAssertEqual(removedStatistics, .empty)
    }

    func testArtworkCacheRejectsMalformedImageData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = CatalogArtworkCache(rootDirectory: root)
        let reference = CatalogArtworkReference(
            url: URL(string: "https://assets.example/set")!,
            category: .setLogos
        )

        do {
            try await cache.storeOffline(Data("not an image".utf8), for: reference, setID: "set-one")
            XCTFail("Expected malformed image data to be rejected")
        } catch CatalogArtworkCacheError.invalidImageData {
            // Expected.
        } catch {
            XCTFail("Expected invalidImageData, received \(error)")
        }
    }

    func testArtworkCacheRepairsCorruptCachedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub)
        let reference = CatalogArtworkReference(
            url: URL(string: "https://assets.example/set")!,
            category: .setLogos
        )

        let initiallyCached = try await cache.data(for: reference)
        XCTAssertEqual(initiallyCached, imageData)
        let cacheDirectory = root.appendingPathComponent("set-logos", isDirectory: true)
        let cachedFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("broken".utf8).write(to: cachedFile, options: .atomic)

        let repaired = try await cache.data(for: reference)
        let requestCount = await stub.requestCount
        XCTAssertEqual(repaired, imageData)
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testOfflineSetPinsReloadAndSizeEstimateIsStable() {
        let suiteName = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["set-one", "set-two"], forKey: ArtworkCacheStore.offlineSetIDsKey)

        let store = ArtworkCacheStore(
            cache: CatalogArtworkCache(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            userDefaults: defaults
        )

        XCTAssertEqual(store.pinnedSetIDs, ["set-one", "set-two"])
        XCTAssertEqual(CatalogOfflineSetEstimator.estimatedByteCount(cardCount: 100), 35_250_000)
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

    private func makeNoisyPNG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 0x12345678
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            state = 1_664_525 &* state &+ 1_013_904_223
            pixels[offset] = UInt8(truncatingIfNeeded: state)
            pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 8)
            pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 16)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ))
        return try XCTUnwrap(UIImage(cgImage: image).pngData())
    }
}

private actor HTTPClientStub: HTTPClient {
    private var responses: [HTTPResponse]
    private var requests: [URLRequest] = []
    private(set) var requestCount = 0

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        requests.append(request)
        guard !responses.isEmpty else {
            throw TCGdexError.invalidResponse
        }
        return responses.removeFirst()
    }

    func header(_ field: String, requestIndex: Int) -> String? {
        guard requests.indices.contains(requestIndex) else { return nil }
        return requests[requestIndex].value(forHTTPHeaderField: field)
    }
}

private actor CancelledHTTPClientStub: HTTPClient {
    private(set) var requestCount = 0

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        throw CancellationError()
    }
}

private actor DurationRecorder {
    private(set) var values: [Duration] = []

    func append(_ value: Duration) {
        values.append(value)
    }
}

private actor CatalogProviderSpy: CatalogProvider {
    let cardSnapshot: CatalogCardSnapshot
    private(set) var cardRequestCount = 0

    init(cardSnapshot: CatalogCardSnapshot) {
        self.cardSnapshot = cardSnapshot
    }

    func fetchCardIndex() async throws -> [CatalogCard] {
        throw TCGdexError.invalidResponse
    }

    func fetchSeriesIndex() async throws -> [CatalogSeries] {
        throw TCGdexError.invalidResponse
    }

    func fetchSeries(id: String) async throws -> CatalogSeriesSnapshot {
        throw TCGdexError.invalidResponse
    }

    func fetchSet(id: String) async throws -> CatalogSetSnapshot {
        throw TCGdexError.invalidResponse
    }

    func fetchCard(id: String) async throws -> CatalogCardSnapshot {
        cardRequestCount += 1
        return cardSnapshot
    }
}
