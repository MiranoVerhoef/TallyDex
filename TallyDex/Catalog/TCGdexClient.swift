import Foundation

struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let retryAfter: String?
}

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TCGdexError.invalidResponse
        }

        return HTTPResponse(
            data: data,
            statusCode: response.statusCode,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After")
        )
    }
}

struct TCGdexRetryPolicy: Sendable {
    let maximumAttempts: Int
    let baseDelay: Duration

    static let standard = TCGdexRetryPolicy(
        maximumAttempts: 3,
        baseDelay: .milliseconds(500)
    )
}

enum TCGdexError: Error, Equatable, Sendable {
    case invalidResponse
    case rateLimited(retryAfter: String?)
    case serverError(statusCode: Int)
    case httpError(statusCode: Int)
    case transport(String)
    case malformedResponse(String)
}

struct TCGdexClient: CatalogProvider, Sendable {
    private let baseURL: URL
    private let httpClient: any HTTPClient
    private let retryPolicy: TCGdexRetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.tcgdex.net/v2/en/")!
    ) {
        self.init(
            httpClient: URLSessionHTTPClient(session: session),
            baseURL: baseURL,
            retryPolicy: .standard
        )
    }

    init(
        httpClient: any HTTPClient,
        baseURL: URL = URL(string: "https://api.tcgdex.net/v2/en/")!,
        retryPolicy: TCGdexRetryPolicy = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func fetchSeriesIndex() async throws -> [CatalogSeries] {
        let response: [SeriesBriefDTO] = try await request(path: "series")
        return response.map(\.catalogSeries)
    }

    func fetchCardIndex() async throws -> [CatalogCard] {
        let response: [CardBriefDTO] = try await request(path: "cards")
        return response.compactMap(\.searchIndexCard)
    }

    func fetchSeries(id: String) async throws -> CatalogSeriesSnapshot {
        let response: SeriesDTO = try await request(path: "series/\(id)")
        let series = response.catalogSeries
        return CatalogSeriesSnapshot(
            series: series,
            sets: response.sets.map { $0.catalogSet(seriesID: series.id) }
        )
    }

    func fetchSet(id: String) async throws -> CatalogSetSnapshot {
        let response: SetDTO = try await request(path: "sets/\(id)")
        let set = response.catalogSet
        return CatalogSetSnapshot(
            set: set,
            cards: response.cards.map { $0.catalogCard(setID: set.id) }
        )
    }

    func fetchCard(id: String) async throws -> CatalogCardSnapshot {
        let response: CardDTO = try await request(path: "cards/\(id)")
        return CatalogCardSnapshot(
            card: response.catalogCard,
            variants: CatalogVariantOverrides.apply(
                to: response.variants?.availableKinds ?? [],
                cardID: response.id
            )
        )
    }

    private func request<Response: Decodable & Sendable>(path: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var attempt = 1

        while true {
            let response: HTTPResponse
            do {
                response = try await httpClient.send(request)
            } catch {
                guard attempt < retryPolicy.maximumAttempts else {
                    throw TCGdexError.transport(String(describing: error))
                }
                try await sleep(retryPolicy.baseDelay)
                attempt += 1
                continue
            }

            switch response.statusCode {
            case 200..<300:
                do {
                    return try JSONDecoder().decode(Response.self, from: response.data)
                } catch {
                    throw TCGdexError.malformedResponse(String(describing: error))
                }
            case 429:
                guard attempt < retryPolicy.maximumAttempts else {
                    throw TCGdexError.rateLimited(retryAfter: response.retryAfter)
                }
                try await sleep(retryDuration(from: response.retryAfter))
                attempt += 1
            case 500..<600:
                guard attempt < retryPolicy.maximumAttempts else {
                    throw TCGdexError.serverError(statusCode: response.statusCode)
                }
                try await sleep(retryPolicy.baseDelay)
                attempt += 1
            default:
                throw TCGdexError.httpError(statusCode: response.statusCode)
            }
        }
    }

    private func retryDuration(from header: String?) -> Duration {
        guard let header, let seconds = Double(header), seconds >= 0 else {
            return retryPolicy.baseDelay
        }
        return .milliseconds(Int64(seconds * 1_000))
    }
}

private struct SeriesBriefDTO: Decodable, Sendable {
    let id: String
    let name: String

    var catalogSeries: CatalogSeries {
        CatalogSeries(id: id, name: name, logoURL: nil)
    }
}

private struct SeriesDTO: Decodable, Sendable {
    let id: String
    let name: String
    let logo: URL?
    let sets: [SetBriefDTO]

    var catalogSeries: CatalogSeries {
        CatalogSeries(id: id, name: name, logoURL: logo)
    }
}

private struct SetBriefDTO: Decodable, Sendable {
    let id: String
    let name: String
    let abbreviation: SetAbbreviationDTO?
    let logo: URL?
    let symbol: URL?
    let cardCount: CardCountDTO

    func catalogSet(seriesID: String) -> CatalogSet {
        CatalogSet(
            id: id,
            seriesID: seriesID,
            name: name,
            abbreviation: abbreviation?.official,
            logoURL: logo,
            symbolURL: symbol,
            officialCardCount: cardCount.official,
            totalCardCount: cardCount.total ?? cardCount.official,
            releaseDate: nil,
            rarityCounts: nil
        )
    }
}

private struct SetDTO: Decodable, Sendable {
    let id: String
    let name: String
    let abbreviation: SetAbbreviationDTO?
    let logo: URL?
    let symbol: URL?
    let cardCount: CardCountDTO
    let releaseDate: String?
    let serie: SeriesBriefDTO
    let cards: [CardBriefDTO]

    var catalogSet: CatalogSet {
        CatalogSet(
            id: id,
            seriesID: serie.id,
            name: name,
            abbreviation: abbreviation?.official,
            logoURL: logo,
            symbolURL: symbol,
            officialCardCount: cardCount.official,
            totalCardCount: cardCount.total ?? cardCount.official,
            releaseDate: releaseDate,
            rarityCounts: nil
        )
    }
}

private struct SetAbbreviationDTO: Decodable, Sendable {
    let official: String?
}

private struct CardCountDTO: Decodable, Sendable {
    let official: Int
    let total: Int?
}

private struct CardBriefDTO: Decodable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: URL?

    var searchIndexCard: CatalogCard? {
        let setID = image?.deletingLastPathComponent().lastPathComponent
            ?? id.split(separator: "-").dropLast().joined(separator: "-")
        guard !setID.isEmpty else { return nil }
        return catalogCard(setID: setID)
    }

    func catalogCard(setID: String) -> CatalogCard {
        CatalogCard(
            id: id,
            setID: setID,
            localID: localId,
            name: name,
            imageURL: image,
            category: nil,
            illustrator: nil,
            rarity: nil
        )
    }
}

private struct CardDTO: Decodable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: URL?
    let category: String?
    let illustrator: String?
    let rarity: String?
    let set: SetReferenceDTO
    let variants: VariantsDTO?

    var catalogCard: CatalogCard {
        CatalogCard(
            id: id,
            setID: set.id,
            localID: localId,
            name: name,
            imageURL: image,
            category: category,
            illustrator: illustrator,
            rarity: rarity
        )
    }
}

private struct SetReferenceDTO: Decodable, Sendable {
    let id: String
}

private struct VariantsDTO: Decodable, Sendable {
    let firstEdition: Bool?
    let holo: Bool?
    let normal: Bool?
    let reverse: Bool?
    let wPromo: Bool?

    var availableKinds: Set<CatalogVariantKind> {
        var kinds = Set<CatalogVariantKind>()
        if normal == true { kinds.insert(.normal) }
        if reverse == true { kinds.insert(.reverseHolo) }
        if holo == true { kinds.insert(.holo) }
        if firstEdition == true { kinds.insert(.firstEdition) }
        if wPromo == true { kinds.insert(.watermarkedPromo) }
        return kinds
    }
}
