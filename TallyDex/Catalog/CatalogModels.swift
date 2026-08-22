import Foundation

struct CatalogSeries: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let logoURL: URL?
}

struct CatalogRarityCount: Codable, Equatable, Hashable, Identifiable, Sendable {
    let rarity: String
    let count: Int

    var id: String { rarity }
}

struct CatalogSet: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let seriesID: String
    let name: String
    let abbreviation: String?
    let logoURL: URL?
    let symbolURL: URL?
    let officialCardCount: Int
    let totalCardCount: Int
    let releaseDate: String?
    let rarityCounts: [CatalogRarityCount]?

    /// Scarlet & Violet introduced printed expansion codes in place of the
    /// expansion symbols used by earlier English releases. Mega Evolution
    /// continues that modern convention.
    var usesPrintedExpansionCode: Bool {
        seriesID == "sv" || seriesID == "me"
    }

    var preferredArtworkURL: URL? {
        logoURL ?? symbolURL
    }

    var releaseDateValue: Date? {
        guard let releaseDate else { return nil }
        let parts = releaseDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    func isUpcoming(relativeTo date: Date = .now) -> Bool {
        guard let releaseDateValue else { return false }
        return releaseDateValue > date
    }

    func fillingMissingMetadata(from fallback: CatalogSet?) -> CatalogSet {
        CatalogSet(
            id: id,
            seriesID: seriesID,
            name: name,
            abbreviation: abbreviation ?? fallback?.abbreviation,
            logoURL: logoURL,
            symbolURL: symbolURL,
            officialCardCount: officialCardCount,
            totalCardCount: totalCardCount,
            releaseDate: releaseDate ?? fallback?.releaseDate,
            rarityCounts: rarityCounts?.isEmpty == false
                ? rarityCounts
                : fallback?.rarityCounts
        )
    }
}

struct CatalogCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let setID: String
    let localID: String
    let name: String
    let imageURL: URL?
    let category: String?
    let illustrator: String?
    let rarity: String?
}

enum CatalogVariantKind: String, Codable, CaseIterable, Sendable {
    case normal
    case reverseHolo
    case holo
    case firstEdition
    case watermarkedPromo

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .reverseHolo: "Reverse holo"
        case .holo: "Holo"
        case .firstEdition: "First edition"
        case .watermarkedPromo: "Watermarked promo"
        }
    }
}

struct CatalogCardSnapshot: Codable, Equatable, Sendable {
    let card: CatalogCard
    let variants: Set<CatalogVariantKind>
}

struct CatalogCardSearchResult: Equatable, Identifiable, Sendable {
    let card: CatalogCard
    let setName: String
    let setReleaseDate: String?

    init(card: CatalogCard, setName: String, setReleaseDate: String? = nil) {
        self.card = card
        self.setName = setName
        self.setReleaseDate = setReleaseDate
    }

    var id: String { card.id }
}

struct CatalogSeriesSnapshot: Codable, Equatable, Sendable {
    let series: CatalogSeries
    let sets: [CatalogSet]
}

struct CatalogSetSnapshot: Codable, Equatable, Sendable {
    let set: CatalogSet
    let cards: [CatalogCard]
}

protocol CatalogProvider: Sendable {
    func fetchCardIndex() async throws -> [CatalogCard]
    func fetchSeriesIndex() async throws -> [CatalogSeries]
    func fetchSeries(id: String) async throws -> CatalogSeriesSnapshot
    func fetchSet(id: String) async throws -> CatalogSetSnapshot
    func fetchCard(id: String) async throws -> CatalogCardSnapshot
}

protocol CatalogRepository: Sendable {
    func fetchSeries() async throws -> [CatalogSeries]
    func fetchSets(seriesID: String?) async throws -> [CatalogSet]
    func fetchCards(setID: String) async throws -> [CatalogCard]
    func fetchDownloadedSetIDs() async throws -> [String]
    func searchCards(query: String) async throws -> [CatalogCardSearchResult]
    func fetchCards(matchingName query: String) async throws -> [CatalogCardSearchResult]
    func fetchSearchResults(cardIDs: [String]) async throws -> [CatalogCardSearchResult]
    func fetchVariants(cardID: String) async throws -> Set<CatalogVariantKind>
    func fetchVariants(cardIDs: [String]) async throws -> [String: Set<CatalogVariantKind>]
    func metadataDate(forKey key: String) async throws -> Date?
    func upsertSeries(_ series: [CatalogSeries]) async throws
    func replaceCatalog(_ snapshots: [CatalogSeriesSnapshot]) async throws
    func replaceSets(_ sets: [CatalogSet], forSeriesID seriesID: String) async throws
    func replaceSet(_ snapshot: CatalogSetSnapshot) async throws
    func replaceCard(_ snapshot: CatalogCardSnapshot) async throws
    func replaceSearchIndex(_ cards: [CatalogCard]) async throws
    func setMetadataDate(_ date: Date, forKey key: String) async throws
}

struct CatalogSeriesGroup: Equatable, Identifiable, Sendable {
    let series: CatalogSeries
    let sets: [CatalogSet]

    var id: String { series.id }

    var preferredArtworkURL: URL? {
        series.logoURL
    }
}
