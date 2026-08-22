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
