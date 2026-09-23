import Foundation
import GRDB
import UIKit
import XCTest
@testable import TallyDex

final class CatalogFoundationTests: XCTestCase {
    func testSharedOwnershipReferencesDoNotDoubleValueOrPriceUnquotedStamps() {
        let normal = CollectionVariantEntry(cardID: "swsh8-16", variant: .normal, quantity: 3,
            updatedAt: Date(timeIntervalSince1970: 100))
        let stamp = CollectionVariantEntry(cardID: normal.cardID, variant: .trickOrTrade, quantity: 4,
            updatedAt: normal.updatedAt)
        let quote = CatalogPriceQuote(cardID: normal.cardID, variant: .normal, source: .cardmarket,
            currencyCode: "EUR", amount: 2, updatedAt: normal.updatedAt)
        let summary = CatalogValueCalculator.summary(entries: [normal, stamp, normal, stamp],
            prices: [normal.cardID: [quote]], source: .cardmarket)
        XCTAssertEqual(summary.amount, 6)
        XCTAssertEqual(summary.pricedVariants, 1)
        XCTAssertEqual(summary.missingVariants, 1)
        XCTAssertEqual(
            CatalogValueCalculator.cardTotals(
                entries: [normal, stamp, normal, stamp],
                prices: [normal.cardID: [quote]], source: .cardmarket
            ),
            [normal.cardID: 6]
        )
        let removed = CollectionVariantEntry(cardID: normal.cardID, variant: .normal, quantity: 0,
            updatedAt: Date(timeIntervalSince1970: 200))
        for entries in [[normal, removed], [removed, normal]] {
            XCTAssertEqual(CatalogValueCalculator.summary(entries: entries, prices: [normal.cardID: [quote]],
                source: .cardmarket).amount, 0)
        }
    }

    func testTrickOrTradeChecklistsHaveThirtyCanonicalIDsAndCorrectEras() throws {
        XCTAssertEqual(TrickOrTradeRelease.all.map(\.year), [2022, 2023, 2024])
        XCTAssertEqual(TrickOrTradeRelease.all.map(\.seriesID), ["swsh", "sv", "sv"])
        let allIDs = TrickOrTradeRelease.all.flatMap(\.cardIDs)
        XCTAssertEqual(Set(allIDs).count, 90)
        for release in TrickOrTradeRelease.all {
            XCTAssertEqual(release.cardIDs.count, 30)
            XCTAssertEqual(release.set.totalCardCount, 30)
            XCTAssertNil(release.printing(cardID: "not-a-member"))
            for id in release.cardIDs {
                let printing = try XCTUnwrap(release.printing(cardID: id))
                XCTAssertEqual(printing.cardID, id)
                XCTAssertEqual(printing.kind, .trickOrTrade)
                XCTAssertEqual(printing.stamps, ["trick-or-trade"])
                XCTAssertEqual(printing.subtype, String(release.year))
                XCTAssertNil(printing.cardmarketProductID)
            }
        }
        let groups = [CatalogSeriesGroup(series: .init(id: "sv", name: "SV", logoURL: nil), sets: [])]
        let added = TrickOrTradeRelease.adding(to: groups)
        XCTAssertEqual(added[0].sets.map(\.id), ["tallydex-tot-2024", "tallydex-tot-2023"])
        XCTAssertEqual(TrickOrTradeRelease.adding(to: added), added)
    }

    func testTrickOrTradeEnrichmentKeepsProviderIdentityAndOtherStampTypes() throws {
        let release = TrickOrTradeRelease.all[2]
        let normal = CatalogPrinting(cardID: "sv03-136", providerID: "normal-stamp", rawType: "normal", kind: .normal,
            subtype: nil, size: "standard", stamps: ["trick-or-trade"], foil: nil, languages: [],
            cardmarketProductID: 785593, tcgplayerProductID: nil, cardtraderProductID: nil)
        let holo = CatalogPrinting(cardID: "sv03-136", providerID: "23hmnvtwds1n7f4b2o51f5iqrd8z", rawType: "holo", kind: .holo,
            subtype: nil, size: "standard", stamps: ["trick-or-trade"], foil: nil, languages: [],
            cardmarketProductID: 785594, tcgplayerProductID: nil, cardtraderProductID: nil)
        let result = TrickOrTradeRelease.printings(cardID: holo.cardID, providerPrintings: [normal, holo])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(normal))
        let stamped = try XCTUnwrap(result.first { $0.kind == .trickOrTrade })
        XCTAssertEqual(stamped.providerID, holo.providerID)
        XCTAssertEqual(stamped.cardmarketProductID, 785594)
        XCTAssertEqual(release.printing(cardID: holo.cardID)?.providerID, stamped.providerID)
        XCTAssertEqual(TrickOrTradeRelease.printings(cardID: holo.cardID, providerPrintings: result), result)
    }

    func testJumboPromosAreSplitByEraAndReplaceEmptyMiscellaneousShell() throws {
        XCTAssertEqual(JumboPromoRelease.all.map(\.seriesID), [
            "me", "sv", "swsh", "sm", "dp", "ex", "ecard", "neo", "gym", "base",
        ])
        XCTAssertEqual(JumboPromoRelease.all.flatMap(\.cardIDs).count, 145)
        XCTAssertEqual(Set(JumboPromoRelease.all.flatMap(\.cardIDs)).count, 145)
        XCTAssertEqual(JumboPromoRelease.all.map(\.jumboPrintingCount).reduce(0, +), 152)

        let oldShell = set(id: "jumbo", seriesID: "misc", name: "Jumbo cards")
        let promoLogo = try XCTUnwrap(URL(string: "https://example.com/mep-promos.png"))
        let groups = [
            CatalogSeriesGroup(
                series: .init(id: "me", name: "Mega Evolution", logoURL: nil),
                sets: [set(
                    id: "mep", seriesID: "me", name: "MEP Black Star Promos",
                    logoURL: promoLogo
                )]
            ),
            CatalogSeriesGroup(
                series: .init(id: "misc", name: "Miscellaneous", logoURL: nil),
                sets: [oldShell]
            ),
        ]
        let added = JumboPromoRelease.adding(to: groups)
        XCTAssertEqual(added[0].sets.map(\.id), ["mep", "tallydex-jumbo-me"])
        XCTAssertEqual(added[0].sets[1].logoURL, promoLogo)
        XCTAssertTrue(added.flatMap(\.sets).allSatisfy { $0.id != "jumbo" })
        XCTAssertEqual(JumboPromoRelease.adding(to: added), added)
    }

    @MainActor
    func testJumboPromosReuseTheirEraPromoArtworkIncludingBundledLogos() throws {
        let expectedArtworkIDs = [
            "me": "mep", "sv": "svp", "swsh": "swshp", "sm": "smp",
            "dp": "dpp", "ex": "np", "ecard": "basep", "neo": "basep",
            "gym": "basep", "base": "basep",
        ]
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: JumboPromoRelease.all.map { ($0.seriesID, $0.artworkSetID) }),
            expectedArtworkIDs
        )

        for release in JumboPromoRelease.all where release.artworkSetID != "np" {
            let source = set(
                id: release.artworkSetID,
                seriesID: release.seriesID,
                name: "Promo artwork"
            )
            let sourceImage = try XCTUnwrap(BundledSetLogo.image(for: source))
            let jumboImage = try XCTUnwrap(BundledSetLogo.image(for: release.set))
            XCTAssertTrue(sourceImage === jumboImage, "Expected shared artwork for \(release.id)")
        }
    }

    func testJumboPrintingKeepsProviderIdentityForSharedOwnership() throws {
        let original = CatalogPrinting(
            cardID: "mep-012", providerID: "provider-jumbo", rawType: "holo",
            kind: .holo, subtype: nil, size: "jumbo", stamps: [], foil: nil,
            languages: ["en"], cardmarketProductID: 858147,
            tcgplayerProductID: 663178, cardtraderProductID: nil
        )
        let normalized = try XCTUnwrap(
            JumboPromoRelease.printings(
                cardID: original.cardID,
                providerPrintings: [original]
            ).first
        )
        XCTAssertEqual(normalized.providerID, original.providerID)
        XCTAssertEqual(normalized.kind, .jumbo)
        XCTAssertEqual(normalized.displayName, "Jumbo")
        XCTAssertEqual(normalized.cardmarketProductID, original.cardmarketProductID)
    }

    @MainActor
    func testTrickOrTradeUsesCanonicalIndexWithoutCreatingDuplicateCardsOrSets() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let release = TrickOrTradeRelease.all[0]
        let parentIDs = Set(release.cardIDs.map { String($0.split(separator: "-")[0]) })
        try await repository.replaceCatalog([.init(series: .init(id: "swsh", name: "SWSH", logoURL: nil),
            sets: parentIDs.sorted().map { set(id: $0, seriesID: "swsh", name: $0) })])
        let cards = release.cardIDs.map { id in
            CatalogCard(id: id, setID: String(id.split(separator: "-")[0]), localID: String(id.split(separator: "-")[1]),
                        name: id, imageURL: nil, category: nil, illustrator: nil, rarity: nil)
        }
        try await repository.replaceSearchIndex(cards)
        let provider = CatalogProviderSpy(cardSnapshot: .init(card: cards[0], variants: [.normal]))
        let store = CatalogStore(provider: provider, repository: repository)
        let loaded = try await store.cards(for: release.set)
        XCTAssertEqual(loaded, cards)
        let requestCount = await provider.cardRequestCount
        XCTAssertEqual(requestCount, 0)
        let storedSets = try await repository.fetchSets(seriesID: nil)
        XCTAssertEqual(storedSets.count, parentIDs.count)
        let printingLookup = await store.cachedPrintings(for: cards)
        XCTAssertEqual(printingLookup.count, 30)
        XCTAssertEqual(printingLookup[cards[0].id]?.first?.kind, .trickOrTrade)
    }
    func testCatalogueKeepsRealEnergySetsWithoutSyntheticOverviewRows() {
        let sve = set(id: "sve", seriesID: "sv", name: "Scarlet & Violet Energy")
        let mee = set(id: "mee", seriesID: "me", name: "Mega Evolution Energy")
        let groups = TrickOrTradeRelease.adding(to: CatalogSeriesGrouping.groups(
            series: [.init(id: "sv", name: "SV", logoURL: nil), .init(id: "me", name: "ME", logoURL: nil)],
            sets: [sve, mee]
        ))
        XCTAssertEqual(groups.flatMap(\.sets).filter { $0.id == "sve" }, [sve])
        XCTAssertEqual(groups.flatMap(\.sets).filter { $0.id == "mee" }, [mee])
        XCTAssertFalse(groups.flatMap(\.sets).contains { $0.id.hasPrefix("tallydex-energy-") })
        XCTAssertTrue(groups.allSatisfy { $0.catalogueSetCount == $0.sets.count })
    }

    func testArtworkDiagnosticsPersistDeduplicateAndClearAfterFallbackSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = HTTPClientStub(responses: [.init(data: Data(#"{"id":"test-1","image":null}"#.utf8), statusCode: 200, retryAfter: nil)])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        let api = CatalogArtworkReference(url: URL(string: "https://example.com/v2/en/cards/test-1")!, category: .cardThumbnails,
                                          offlineSetID: "test", apiCardID: "test-1", cachedAssetURL: nil)
        _ = try? await cache.bestAvailableData(for: [api])
        _ = try? await cache.bestAvailableData(for: [api])
        let failed = await cache.artworkDiagnostics()
        XCTAssertEqual(failed.map(\.cardID), ["test-1"])
        let cold = CatalogArtworkCache(rootDirectory: root, httpClient: HTTPClientStub(responses: []))
        let persisted = await cold.artworkDiagnostics()
        XCTAssertEqual(persisted, failed)
        let imageURL = root.appendingPathComponent("fallback.png")
        try makeNoisyPNG(width: 1, height: 1).write(to: imageURL)
        _ = try await cache.bestAvailableData(for: [api, .init(url: imageURL, category: .cardThumbnails, offlineSetID: "test")])
        let cleared = await cache.artworkDiagnostics()
        XCTAssertTrue(cleared.isEmpty)
        let coldAfterSuccess = CatalogArtworkCache(rootDirectory: root, httpClient: HTTPClientStub(responses: []))
        let clearedPersisted = await coldAfterSuccess.artworkDiagnostics()
        XCTAssertTrue(clearedPersisted.isEmpty)
    }

    func testCancelledArtworkLoadIsNotReportedAsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: CancelledHTTPClientStub(), imageDirectory: TCGdexImageDirectory())
        _ = try? await cache.bestAvailableData(for: [.init(url: URL(string: "https://example.com/v2/en/cards/test-1")!,
            category: .cardThumbnails, offlineSetID: "test", apiCardID: "test-1", cachedAssetURL: nil)])
        let records = await cache.artworkDiagnostics()
        XCTAssertTrue(records.isEmpty)
    }

    func testExplicitArtworkRecheckBypassesRememberedMissingAPIImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let card = CatalogCard(id: "example-1", setID: "example", localID: "1", name: "Example", imageURL: nil,
                               category: nil, illustrator: nil, rarity: nil)
        let apiCount = card.fullArtworkReferences.filter { $0.apiCardID != nil }.count
        let empty = HTTPResponse(data: Data(#"{"id":"example-1","image":null}"#.utf8), statusCode: 200, retryAfter: nil)
        let png = try makeNoisyPNG(width: 1, height: 1)
        let stub = HTTPClientStub(responses: Array(repeating: empty, count: apiCount) + [
            .init(data: Data(), statusCode: 404, retryAfter: nil),
            .init(data: Data(#"{"id":"example-1","image":"https://art.example/verified/example-1"}"#.utf8), statusCode: 200, retryAfter: nil),
            .init(data: png, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        _ = try? await cache.bestAvailableData(for: card)
        let before = await cache.artworkDiagnostics()
        XCTAssertEqual(before.map(\.cardID), [card.id])
        let result = try await cache.recheckArtwork(for: card)
        XCTAssertEqual(result, png)
        let after = await cache.artworkDiagnostics()
        XCTAssertTrue(after.isEmpty)
        let requests = await stub.requestCount
        XCTAssertEqual(requests, apiCount + 3)
    }

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

    func testTCGdexDecodesJumboAsAnExactSharedPrinting() async throws {
        let response = #"""
        {
          "id": "mep-012",
          "localId": "012",
          "name": "Mega Lucario ex",
          "set": { "id": "mep" },
          "variants": { "holo": true },
          "variants_detailed": [
            { "type": "holo", "size": "standard", "variantId": "standard" },
            { "type": "holo", "size": "jumbo", "variantId": "provider-jumbo",
              "thirdParty": { "cardmarket": 858147, "tcgplayer": 663178 } }
          ]
        }
        """#
        let client = TCGdexClient(
            httpClient: HTTPClientStub(responses: [
                HTTPResponse(data: Data(response.utf8), statusCode: 200, retryAfter: nil),
            ]),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: .zero)
        )

        let snapshot = try await client.fetchCard(id: "mep-012")

        XCTAssertEqual(snapshot.variants, [.holo, .jumbo])
        let jumbo = try XCTUnwrap(snapshot.printings.first { $0.size == "jumbo" })
        XCTAssertEqual(jumbo.providerID, "provider-jumbo")
        XCTAssertEqual(jumbo.kind, .jumbo)
        XCTAssertEqual(jumbo.displayName, "Jumbo")
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

    func testRepositoryRefreshReplacesProvisionalVariantsWithAuthoritativeVariants() async throws {
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

    func testRepositoryDoesNotRegressCorrectedCardFromOlderFallbackResponse() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.upsertSeries([CatalogSeries(id: "me", name: "Mega Evolution", logoURL: nil)])
        try await repository.replaceSets(
            [set(id: "30th", seriesID: "me", name: "30th Celebration")],
            forSeriesID: "me"
        )

        func card(updatedAt: Date, rarity: String) -> CatalogCard {
            CatalogCard(
                id: "30th-034", setID: "30th", localID: "034", name: "Pikachu",
                imageURL: nil, category: "Pokemon", illustrator: nil, rarity: rarity,
                metadata: CatalogCardMetadata(
                    dexIDs: [25], hp: nil, types: [], evolvesFrom: nil, stage: nil,
                    suffix: nil, attacks: [], abilities: [], weaknesses: [], resistances: [],
                    retreatCost: nil, regulationMark: nil, legality: nil, rulesText: nil,
                    trainerType: nil, energyType: nil, flavorText: nil, updatedAt: updatedAt
                )
            )
        }

        let correctedAt = Date(timeIntervalSince1970: 200)
        let corrected = CatalogPrinting(
            cardID: "30th-034", providerID: "corrected-holo", rawType: "holo", kind: .holo,
            subtype: nil, size: "standard", stamps: [], foil: nil, languages: ["en"],
            cardmarketProductID: 907641, tcgplayerProductID: nil, cardtraderProductID: nil
        )
        try await repository.replaceCard(CatalogCardSnapshot(
            card: card(updatedAt: correctedAt, rarity: "Rare Holo"),
            variants: [.holo],
            prices: [CatalogPriceQuote(
                cardID: "30th-034", variant: .holo, source: .cardmarket,
                currencyCode: "EUR", amount: 1.77, updatedAt: correctedAt,
                productID: 907641
            )],
            printings: [corrected]
        ))

        try await repository.replaceCard(CatalogCardSnapshot(
            card: card(updatedAt: Date(timeIntervalSince1970: 100), rarity: "Unknown"),
            variants: [.normal],
            printings: [CatalogPrinting(
                cardID: "30th-034", providerID: "generated", rawType: "normal", kind: .normal,
                subtype: nil, size: "standard", stamps: [], foil: nil, languages: ["en"],
                cardmarketProductID: nil, tcgplayerProductID: nil, cardtraderProductID: nil
            )]
        ))

        let variants = try await repository.fetchVariants(cardID: "30th-034")
        let printings = try await repository.fetchPrintings(cardID: "30th-034")
        let savedCard = try await repository.fetchCard(id: "30th-034")
        let prices = try await repository.fetchPrices(cardIDs: ["30th-034"])
        XCTAssertEqual(variants, [.holo])
        XCTAssertEqual(printings, [corrected])
        XCTAssertEqual(savedCard?.rarity, "Rare Holo")
        XCTAssertEqual(prices["30th-034"]?.first?.productID, 907641)
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
            TCGdexArtworkFallbacks.cardImageURLs(for: galleryCard, category: .cardThumbnails).first.map {
                CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
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
            TCGdexArtworkFallbacks.cardImageURLs(for: providerGap, category: .cardThumbnails).first.map {
                CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
            },
            "https://assets.tcgdex.net/en/swsh/swsh12.5/GG48/low.webp"
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
            TCGdexArtworkFallbacks.cardImageURLs(for: unrelated, category: .cardThumbnails).first.map {
                CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
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
            TCGdexArtworkFallbacks.cardImageURLs(for: riolu, category: .cardThumbnails).first.map {
                CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
            },
            "https://assets.tcgdex.net/en/swsh/swsh12.5/GG26/low.webp"
        )
        XCTAssertEqual(
            TCGdexArtworkFallbacks.cardImageURLs(for: riolu, category: .cardArtwork).first.map {
                CatalogArtworkCache.resolvedAssetURL($0, category: .cardArtwork).absoluteString
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
                TCGdexArtworkFallbacks.cardImageURLs(for: card, category: .cardThumbnails).first.map {
                    CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
                },
                expected
            )
            XCTAssertEqual(
                TCGdexArtworkFallbacks.cardImageURLs(for: card, category: .cardArtwork).first.map {
                    CatalogArtworkCache.resolvedAssetURL($0, category: .cardArtwork).absoluteString
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
                TCGdexArtworkFallbacks.cardImageURLs(for: card, category: .cardThumbnails).first.map {
                    CatalogArtworkCache.resolvedAssetURL($0, category: .cardThumbnails).absoluteString
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
            HTTPResponse(data: Data(#"{"id":"me05-001","image":"https://assets.tcgdex.net/en/me/me05/001"}"#.utf8), statusCode: 200, retryAfter: nil),
            HTTPResponse(data: Data(), statusCode: 404, retryAfter: nil),
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
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
                CatalogAPISettings.customURL.appending(path: "cards/me05-001").absoluteString,
                "https://api.tcgdex.net/v2/en/cards/me05-001",
                "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/ME05/ME05_EN_1.png",
            ]
        )
        let resolved = try await cache.bestAvailableData(for: references)

        XCTAssertEqual(resolved, imageData)
        let requestCount = await stub.requestCount
        XCTAssertEqual(requestCount, 4)
    }

    func testAPIURLValidationAcceptsOnlyHTTPSOriginsAndEnglishRoots() {
        for input in ["https://tcgdex.tallydex.nl", "https://tcgdex.tallydex.nl/", "https://tcgdex.tallydex.nl/v2/en/"] {
            XCTAssertEqual(CatalogAPISettings.normalizedURL(input)?.absoluteString, "https://tcgdex.tallydex.nl/v2/en/")
        }
        for input in ["http://example.com", "https://user:secret@example.com", "https://example.com/v2/fr", "https://example.com?secret=x", "https://example.com/#fragment", ""] {
            XCTAssertNil(CatalogAPISettings.normalizedURL(input))
        }
    }

    func testConfiguredProviderUsesCustomThenOfficialAndBacksOffFailedHost() async throws {
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(), statusCode: 503, retryAfter: nil),
            HTTPResponse(data: Data(#"[{"id":"sv","name":"Scarlet & Violet"}]"#.utf8), statusCode: 200, retryAfter: nil),
            HTTPResponse(data: Data(#"[{"id":"sv","name":"Scarlet & Violet"}]"#.utf8), statusCode: 200, retryAfter: nil),
        ])
        let provider = ConfiguredCatalogProvider(
            httpClient: stub, customURL: URL(string: "https://mirror.example/v2/en/")!,
            useCustom: true, imageDirectory: TCGdexImageDirectory(), etagStore: nil
        )
        let first = try await provider.fetchSeriesIndex()
        let second = try await provider.fetchSeriesIndex()
        XCTAssertEqual(first, second)
        let urls = await stub.requestURLs
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://mirror.example/v2/en/series", "https://api.tcgdex.net/v2/en/series", "https://api.tcgdex.net/v2/en/series",
        ])
    }

    func testConfiguredProviderDoesNotFallbackOnCancellationOrNotModified() async throws {
        let cancelled = CancelledHTTPClientStub()
        let provider = ConfiguredCatalogProvider(httpClient: cancelled, useCustom: true, imageDirectory: TCGdexImageDirectory(), etagStore: nil)
        do { _ = try await provider.fetchSeriesIndex(); XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let cancellationCount = await cancelled.requestCount
        XCTAssertEqual(cancellationCount, 1)
        let stub = HTTPClientStub(responses: [HTTPResponse(data: Data(), statusCode: 304, retryAfter: nil)])
        let unchanged = ConfiguredCatalogProvider(httpClient: stub, useCustom: true, imageDirectory: TCGdexImageDirectory(), etagStore: nil)
        do { _ = try await unchanged.fetchCardIndex(); XCTFail("Expected not modified") }
        catch { XCTAssertEqual(error as? TCGdexError, .notModified) }
        let unchangedCount = await stub.requestCount
        XCTAssertEqual(unchangedCount, 1)
    }

    func testETagsDoNotCrossAPISourcesOrSurviveSwitchingBack() async throws {
        let stub = HTTPClientStub(responses: (0..<3).map { _ in
            HTTPResponse(data: Data(#"[{"id":"base-1","localId":"1","name":"Card"}]"#.utf8), statusCode: 200, retryAfter: nil, etag: "v1")
        })
        let etags = TCGdexETagStore()
        let primary = TCGdexClient(httpClient: stub, baseURL: URL(string: "https://mirror.example/v2/en/")!, etagStore: etags)
        let official = TCGdexClient(httpClient: stub, etagStore: etags)
        _ = try await primary.fetchCardIndex()
        _ = try await official.fetchCardIndex()
        _ = try await primary.fetchCardIndex()
        for index in 0..<3 {
            let header = await stub.header("If-None-Match", requestIndex: index)
            XCTAssertNil(header)
        }
    }

    func testBundledThumbnailsMatchExactIDsAndDecode() throws {
        XCTAssertEqual(BundledCardThumbnails.filesByCardID.count, 842)
        for id in ["ecard2-103a", "mfb-1", "mep-032", "30th-B", "30th-G", "30th-R"] {
            let url = try XCTUnwrap(BundledCardThumbnails.url(for: id))
            XCTAssertTrue(CatalogArtworkCache.isValidImageData(try Data(contentsOf: url)))
        }
        XCTAssertNil(BundledCardThumbnails.url(for: "not-a-real-card"))
        XCTAssertNil(BundledCardThumbnails.url(for: "mfb-1--blueborder"))
    }

    func testBundledThumbnailPrecedesPokemonHostAndUsesThumbnailCategory() throws {
        let card = CatalogCard(id: "ecard2-103a", setID: "ecard2", localID: "103a", name: "Porygon", imageURL: nil, category: nil, illustrator: nil, rarity: nil)
        let refs = card.fullArtworkReferences
        let bundledIndex = try XCTUnwrap(refs.firstIndex { $0.url.isFileURL })
        let pokemonIndex = try XCTUnwrap(refs.firstIndex { $0.url.host == "assets.pokemon.com" })
        XCTAssertLessThan(bundledIndex, pokemonIndex)
        XCTAssertEqual(refs[bundledIndex].category, .cardThumbnails)
        XCTAssertEqual(refs.filter { $0.apiCardID != nil }.last?.url.host, "api.tcgdex.net")
    }

    func testAPIReturnedImageIsUsedAndCachedForColdOfflineLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(#"{"id":"test-7","image":"https://cdn.example/changed/test/7"}"#.utf8), statusCode: 200, retryAfter: nil),
            HTTPResponse(data: png, statusCode: 200, retryAfter: nil),
        ])
        let reference = CatalogArtworkReference(url: URL(string: "https://mirror.example/v2/en/cards/test-7")!, category: .cardThumbnails, apiCardID: "test-7")
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        let data = try await cache.data(for: reference)
        XCTAssertEqual(data, png)
        let urls = await stub.requestURLs
        XCTAssertEqual(urls.last?.absoluteString, "https://cdn.example/changed/test/7/low.webp")
        let offlineHTTP = HTTPClientStub(responses: [])
        let cold = CatalogArtworkCache(rootDirectory: root, httpClient: offlineHTTP, imageDirectory: TCGdexImageDirectory())
        let cached = try await cold.data(for: reference)
        XCTAssertEqual(cached, png)
        let count = await offlineHTTP.requestCount
        XCTAssertEqual(count, 0)
    }

    func testAPIImageRejectsWrongCardAndDoesNotGuessArtwork() async throws {
        let directory = TCGdexImageDirectory()
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(#"{"id":"different-1","image":"https://cdn.example/wrong"}"#.utf8), statusCode: 200, retryAfter: nil),
        ])
        do {
            _ = try await directory.imageURL(endpoint: URL(string: "https://mirror.example/v2/en/cards/test-1")!, cardID: "test-1", httpClient: stub)
            XCTFail("Must reject the wrong card")
        } catch { XCTAssertEqual(error as? TCGdexError, .invalidResponse) }
    }

    func testKeptOfflineAPICardRemainsAvailableAfterChangingHost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let stub = HTTPClientStub(responses: [])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        let old = CatalogArtworkReference(url: URL(string: "https://old.example/v2/en/cards/test-1")!, category: .cardArtwork, offlineSetID: "test", apiCardID: "test-1")
        try await cache.storeOffline(png, for: old, setID: "test")
        let new = CatalogArtworkReference(url: URL(string: "https://new.example/v2/en/cards/test-1")!, category: .cardArtwork, offlineSetID: "test", apiCardID: "test-1")
        let data = try await cache.data(for: new)
        XCTAssertEqual(data, png)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0)
    }

    func testBundledFallbackNeedsNoImageDownloadAfterAPIsReportMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = HTTPClientStub(responses: [
            HTTPResponse(data: Data(), statusCode: 404, retryAfter: nil),
            HTTPResponse(data: Data(), statusCode: 404, retryAfter: nil),
        ])
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        let card = CatalogCard(id: "ecard2-103a", setID: "ecard2", localID: "103a", name: "Porygon", imageURL: nil, category: nil, illustrator: nil, rarity: nil)
        let data = try await cache.bestAvailableData(for: card)
        XCTAssertTrue(CatalogArtworkCache.isValidImageData(data))
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    func testArtworkChainStopsOnCancellationInsteadOfTryingNextSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = CancelledHTTPClientStub()
        let cache = CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory())
        let refs = ["https://example.com/first.png", "https://example.com/second.png"].map {
            CatalogArtworkReference(url: URL(string: $0)!, category: .cardThumbnails)
        }
        do { _ = try await cache.bestAvailableData(for: refs); XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testAllRecoveredParentPathsRemainEligibleForLowAndHighArtwork() {
        for id in ["swsh4.5sv-SV028", "swsh4.5sv-SV046", "swsh12.5gg-GG48", "swsh12.5gg-GG06", "swsh9tg-TG23"] {
            let pieces = id.split(separator: "-")
            let card = CatalogCard(id: id, setID: String(pieces[0]), localID: String(pieces[1]), name: "Test", imageURL: nil, category: nil, illustrator: nil, rarity: nil)
            for category in [CatalogArtworkCategory.cardThumbnails, .cardArtwork] {
                let refs = TCGdexArtworkFallbacks.references(for: card, category: category)
                let parentIndex = refs.firstIndex { $0.url.host == "assets.tcgdex.net" }
                XCTAssertEqual(parentIndex, 2)
                if let bundleIndex = refs.firstIndex(where: { $0.url.isFileURL }), let parentIndex {
                    XCTAssertLessThan(parentIndex, bundleIndex)
                }
            }
        }
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
        let imageDirectory = TCGdexImageDirectory()
        await imageDirectory.seed(
            Data(#"[{"id":"sv01-001","image":"https://assets.example/001.png"},{"id":"sv01-002","image":"https://assets.example/002.png"}]"#.utf8),
            baseURL: CatalogAPISettings.customURL, path: "cards"
        )
        let store = ArtworkCacheStore(
            cache: CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: imageDirectory),
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
            HTTPResponse(data: Data(#"{"id":"smp-SM95","image":"https://assets.example/lucario.png"}"#.utf8), statusCode: 200, retryAfter: nil),
            HTTPResponse(data: imageData, statusCode: 200, retryAfter: nil),
        ])
        let store = ArtworkCacheStore(
            cache: CatalogArtworkCache(rootDirectory: root, httpClient: stub, imageDirectory: TCGdexImageDirectory()),
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
        XCTAssertEqual(requestCount, 2)
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

    func testMcDonaldsGroupingMovesKnownSetsWithoutChangingTheirIdentities() {
        let mappings = [
            "2011bw": "bw", "2012bw": "bw", "2013bw": "bw",
            "2014xy": "xy", "2015xy": "xy", "2016xy": "xy",
            "2017sm": "sm", "2018sm": "sm", "2019sm": "sm",
            "2021swsh": "swsh", "2022swsh": "swsh", "2023sv": "sv", "2024sv": "sv",
        ]
        let series = ["sv", "swsh", "sm", "xy", "bw", "mc"].map {
            CatalogSeries(id: $0, name: $0, logoURL: nil)
        }
        let sets = mappings.keys.sorted().map { set(id: $0, seriesID: "mc", name: $0) }
        let groups = CatalogSeriesGrouping.groups(series: series, sets: sets)
        XCTAssertFalse(groups.contains { $0.id == "mc" })
        XCTAssertEqual(groups.flatMap(\.sets).count, sets.count)
        for group in groups {
            for relocated in group.sets {
                XCTAssertEqual(mappings[relocated.id], group.id)
                XCTAssertEqual(relocated, sets.first { $0.id == relocated.id })
                XCTAssertEqual(relocated.seriesID, "mc")
            }
        }
        XCTAssertEqual(CatalogSeriesGrouping.groups(series: series, sets: groups.flatMap(\.sets)), groups)
    }

    func testUnknownMcDonaldsReleasesAndAbsentParentsStayVisible() {
        let series = ["sv", "mc"].map { CatalogSeries(id: $0, name: $0, logoURL: nil) }
        let sets = [
            set(id: "2024sv", seriesID: "mc", name: "Known"),
            set(id: "2014xy", seriesID: "mc", name: "Missing parent"),
            set(id: "future-mcd", seriesID: "mc", name: "Unmapped release"),
        ]
        let groups = CatalogSeriesGrouping.groups(series: series, sets: sets)
        XCTAssertEqual(groups.first { $0.id == "sv" }?.sets.map(\.id), ["2024sv"])
        XCTAssertEqual(groups.first { $0.id == "mc" }?.sets.map(\.id), ["2014xy", "future-mcd"])
        XCTAssertEqual(Set(groups.flatMap(\.sets).map(\.id)), Set(sets.map(\.id)))
    }

    func testMcDonaldsGroupingInterleavesDatesWithoutReorderingExistingExpansions() {
        func datedSet(_ id: String, seriesID: String, date: String?) -> CatalogSet {
            CatalogSet(id: id, seriesID: seriesID, name: id, abbreviation: nil,
                       logoURL: nil, symbolURL: nil, officialCardCount: 15,
                       totalCardCount: 15, releaseDate: date, rarityCounts: nil)
        }
        let native = [datedSet("new", seriesID: "sv", date: "2024-11-08"),
                      datedSet("old", seriesID: "sv", date: "2023-03-31")]
        let added = [datedSet("2023sv", seriesID: "mc", date: "2023-08-01"),
                     datedSet("2024sv", seriesID: "mc", date: "2024-12-04")]
        let series = ["sv", "mc"].map { CatalogSeries(id: $0, name: $0, logoURL: nil) }
        let groups = CatalogSeriesGrouping.groups(series: series, sets: native + added)
        XCTAssertEqual(groups.first?.sets.map(\.id), ["2024sv", "new", "2023sv", "old"])
        XCTAssertEqual(groups.first?.sets.filter { $0.seriesID == "sv" }, native)
    }

    func testBundledMcDonaldsCoverageIsGroupedExactlyOnce() throws {
        let snapshot = try BundledCatalogLoader(bundle: .main).load()
        let sets = snapshot.series.flatMap(\.sets)
        let groups = CatalogSeriesGrouping.groups(series: snapshot.series.map(\.series), sets: sets)
        XCTAssertFalse(groups.contains { $0.id == "mc" })
        XCTAssertEqual(groups.flatMap(\.sets).count, sets.count)
        XCTAssertEqual(Set(groups.flatMap(\.sets).map(\.id)), Set(sets.map(\.id)))
        for set in sets where set.seriesID == "mc" {
            XCTAssertEqual(groups.flatMap(\.sets).filter { $0.id == set.id }, [set])
        }
    }

    @MainActor
    func testCatalogStoreGroupsCachedMcDonaldsWithoutRewritingProviderData() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let promo = set(id: "2024sv", seriesID: "mc", name: "McDonald's Collection 2024")
        let card = CatalogCard(id: "2024sv-1", setID: "2024sv", localID: "1", name: "Pikachu", imageURL: nil, category: nil, illustrator: nil, rarity: nil)
        try await repository.replaceCatalog([
            .init(series: .init(id: "sv", name: "Scarlet & Violet", logoURL: nil), sets: []),
            .init(series: .init(id: "mc", name: "McDonald's Collection", logoURL: nil), sets: [promo]),
        ])
        try await repository.replaceSet(.init(set: promo, cards: [card]))
        let timestamp = Date()
        for key in ["catalog.lastRefresh", "catalog.searchIndex.lastRefresh", "catalog.upcoming.lastAvailabilityCheck"] {
            try await repository.setMetadataDate(timestamp, forKey: key)
        }
        let provider = CatalogProviderSpy(cardSnapshot: .init(card: card, variants: [.normal]))
        let store = CatalogStore(provider: provider, repository: repository, now: { timestamp })
        await store.start()
        let visible = try XCTUnwrap(store.groups.first { $0.id == "sv" }?.sets.first { $0.id == "2024sv" })
        XCTAssertEqual(visible.seriesID, "mc")
        let storedSets = try await repository.fetchSets(seriesID: "mc")
        let storedCards = try await repository.fetchCards(setID: promo.id)
        XCTAssertEqual(storedSets, [promo])
        XCTAssertEqual(storedCards, [card])
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
        XCTAssertEqual(CatalogValueCalculator.cardTotals(
            entries: entries, prices: prices, source: .cardmarket
        ), ["one": 2.50])
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

    @MainActor
    func testPokemonCollectionMatchesCachedIDsAndDeduplicatesTwoSpecies() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        let series = CatalogSeries(id: "sv", name: "Scarlet & Violet", logoURL: nil)
        try await repository.replaceCatalog([
            CatalogSeriesSnapshot(series: series, sets: [set(id: "sv01", seriesID: "sv", name: "Test")]),
        ])
        let cards = [
            pokemonCollectionCard(id: "1", name: "Lucario V", ids: [448]),
            pokemonCollectionCard(id: "2", name: "Riolu", ids: [447]),
            pokemonCollectionCard(id: "3", name: "Riolu & Lucario-GX", ids: [447, 448]),
            pokemonCollectionCard(id: "4", name: "An unusual labelled form", ids: [448]),
            pokemonCollectionCard(id: "5", name: "Lucario", ids: [25]),
            pokemonCollectionCard(id: "6", name: "Lucario Spirit Link", ids: nil, category: "Trainer"),
            pokemonCollectionCard(id: "7", name: "Mega Lucario ex", ids: nil),
            pokemonCollectionCard(id: "8", name: "Pikachu", ids: [25]),
        ]
        try await repository.replaceSearchIndex(cards)
        for card in cards where card.metadata != nil || card.category == "Trainer" {
            try await repository.replaceCard(.init(card: card, variants: [.normal]))
        }
        let provider = CatalogProviderSpy(cardSnapshot: .init(card: cards[0], variants: [.normal]))
        let store = CatalogStore(provider: provider, repository: repository)
        let rules = [PokemonCollectionRule(name: "Lucario", dexID: 448), .init(name: "Riolu", dexID: 447)]
        let matches = try await store.cards(matchingPokemonRules: rules)
        XCTAssertEqual(Set(matches.map(\.card.id)), Set(["sv01-1", "sv01-2", "sv01-3", "sv01-4", "sv01-7"]))
        XCTAssertEqual(matches.count, 5)
        XCTAssertEqual(matches.first(where: { $0.card.id == "sv01-3" })?.card.metadata?.dexIDs, [447, 448])
        let requests = await provider.cardRequestCount
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testExistingSingleSpeciesCanResolveIDFromCachedMetadataWithoutNetwork() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.replaceCatalog([
            .init(series: .init(id: "sv", name: "Test", logoURL: nil), sets: [set(id: "sv01", seriesID: "sv", name: "Test")]),
        ])
        let lucario = pokemonCollectionCard(id: "1", name: "Lucario", ids: [448])
        let renamed = pokemonCollectionCard(id: "2", name: "A different title", ids: [448])
        try await repository.replaceSearchIndex([lucario, renamed])
        try await repository.replaceCard(.init(card: lucario, variants: [.normal]))
        try await repository.replaceCard(.init(card: renamed, variants: [.normal]))
        let provider = CatalogProviderSpy(cardSnapshot: .init(card: lucario, variants: [.normal]))
        let store = CatalogStore(provider: provider, repository: repository)
        let matches = try await store.cards(matchingPokemonRules: [.init(name: "Lucario")])
        XCTAssertEqual(matches.count, 2)
        let choices = PokemonRuleSearch.choices(from: try await repository.fetchCards(matchingName: "Lucario"), query: "Lucario")
        let resolved = await store.pokemonRule(for: try XCTUnwrap(choices.first))
        XCTAssertEqual(resolved.dexID, 448)
        let requests = await provider.cardRequestCount
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testPickerVerifiesOneRepresentativeAndDoesNotGuessTagTeamIDs() async throws {
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.inMemory())
        try await repository.replaceCatalog([
            .init(series: .init(id: "sv", name: "Test", logoURL: nil), sets: [set(id: "sv01", seriesID: "sv", name: "Test")]),
        ])
        let summary = pokemonCollectionCard(id: "1", name: "Lucario V", ids: nil)
        let detailed = pokemonCollectionCard(id: "1", name: "Lucario V", ids: [448])
        try await repository.replaceSearchIndex([summary])
        let provider = CatalogProviderSpy(cardSnapshot: .init(card: detailed, variants: [.normal]))
        let store = CatalogStore(provider: provider, repository: repository)
        let choices = PokemonRuleSearch.choices(from: [.init(card: summary, setName: "Test", setReleaseDate: nil)], query: "Lucario")
        let resolved = await store.pokemonRule(for: try XCTUnwrap(choices.first))
        XCTAssertEqual(resolved, .init(name: "Lucario", dexID: 448))
        let requests = await provider.cardRequestCount
        XCTAssertEqual(requests, 1)
    }

    private func pokemonCollectionCard(id: String, name: String, ids: [Int]?, category: String? = "Pokémon") -> CatalogCard {
        CatalogCard(
            id: "sv01-\(id)", setID: "sv01", localID: id, name: name, imageURL: nil,
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

    func testArtworkCachePreferenceDefaultsAndPersistsKnownLimits() {
        let suite = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ArtworkCacheSettings.preferredLimit(defaults: defaults), .mb400)
        for limit in ArtworkCacheSizeLimit.allCases {
            defaults.set(limit.rawValue, forKey: ArtworkCacheSettings.limitKey)
            XCTAssertEqual(ArtworkCacheSettings.preferredLimit(defaults: UserDefaults(suiteName: suite)!), limit)
            XCTAssertGreaterThan(limit.byteCount, 0)
        }
        defaults.set(-1, forKey: ArtworkCacheSettings.limitKey)
        XCTAssertEqual(ArtworkCacheSettings.preferredLimit(defaults: defaults), .mb400)
        XCTAssertEqual(ArtworkCacheSizeLimit.allCases.count, 6)
    }

    func testArtworkCacheReadsChangedLimitWithoutRestartAndPreservesOfflineData() async throws {
        let suite = "TallyDexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cardDirectory = root.appendingPathComponent("card-artwork", isDirectory: true)
        let logoDirectory = root.appendingPathComponent("set-logos", isDirectory: true)
        try FileManager.default.createDirectory(at: cardDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logoDirectory, withIntermediateDirectories: true)
        let cardFile = cardDirectory.appendingPathComponent("sparse-test.webp")
        XCTAssertTrue(FileManager.default.createFile(atPath: cardFile.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: cardFile)
        try handle.truncate(atOffset: UInt64(101 * 1_024 * 1_024))
        try handle.close()
        try Data([1]).write(to: logoDirectory.appendingPathComponent("test.png"))
        defaults.set(ArtworkCacheSizeLimit.mb250.rawValue, forKey: ArtworkCacheSettings.limitKey)
        let cache = CatalogArtworkCache(rootDirectory: root, preferencesSuiteName: suite)
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let offline = CatalogArtworkReference(url: URL(string: "https://example.com/test.png")!, category: .cardArtwork, offlineSetID: "test")
        try await cache.storeOffline(png, for: offline, setID: "test")
        try await cache.enforceLimit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: cardFile.path))
        defaults.set(ArtworkCacheSizeLimit.mb100.rawValue, forKey: ArtworkCacheSettings.limitKey)
        try await cache.enforceLimit()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cardFile.path))
        let remaining = await cache.snapshot()
        XCTAssertEqual(remaining.statistics(for: .setLogos).fileCount, 1)
        let preserved = try await cache.data(for: offline)
        XCTAssertEqual(preserved, png)
    }

    @MainActor
    func testScarletVioletSupplementalSetsHaveBundledLogos() throws {
        for (id, name) in [("svp", "SVP Black Star Promos"), ("sve", "Scarlet & Violet Energy")] {
            let image = try XCTUnwrap(BundledSetLogo.image(for: set(id: id, seriesID: "sv", name: name)))
            XCTAssertEqual(image.size.width, 420)
            XCTAssertEqual(image.size.height, 160)
        }
    }

    @MainActor
    func testReleased30thSetsReuseVerifiedCelebrationLogo() throws {
        let announced = try XCTUnwrap(BundledSetLogo.image(for: set(
            id: "upcoming-30c", seriesID: "me", name: "30th Celebration"
        )))
        for (id, name) in [("30th", "30th Celebration"), ("30th-c", "30th Classic Collection")] {
            let released = try XCTUnwrap(BundledSetLogo.image(for: set(
                id: id, seriesID: "me", name: name
            )))
            XCTAssertTrue(released === announced, "Expected \(id) to reuse the verified 30th logo")
        }
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
        logoURL: URL? = nil,
        rarityCounts: [CatalogRarityCount]? = nil
    ) -> CatalogSet {
        CatalogSet(
            id: id,
            seriesID: seriesID,
            name: name,
            abbreviation: abbreviation,
            logoURL: logoURL,
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
    var requestURLs: [URL] { requests.compactMap(\.url) }

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
