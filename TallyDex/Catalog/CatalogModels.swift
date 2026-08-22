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
}

struct CatalogCardSnapshot: Codable, Equatable, Sendable {
    let card: CatalogCard
    let variants: Set<CatalogVariantKind>
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
    func fetchSeriesIndex() async throws -> [CatalogSeries]
    func fetchSeries(id: String) async throws -> CatalogSeriesSnapshot
    func fetchSet(id: String) async throws -> CatalogSetSnapshot
    func fetchCard(id: String) async throws -> CatalogCardSnapshot
}

protocol CatalogRepository: Sendable {
    func fetchSeries() async throws -> [CatalogSeries]
    func fetchSets(seriesID: String?) async throws -> [CatalogSet]
    func fetchCards(setID: String) async throws -> [CatalogCard]
    func fetchVariants(cardID: String) async throws -> Set<CatalogVariantKind>
    func metadataDate(forKey key: String) async throws -> Date?
    func upsertSeries(_ series: [CatalogSeries]) async throws
    func replaceCatalog(_ snapshots: [CatalogSeriesSnapshot]) async throws
    func replaceSets(_ sets: [CatalogSet], forSeriesID seriesID: String) async throws
    func replaceSet(_ snapshot: CatalogSetSnapshot) async throws
    func replaceCard(_ snapshot: CatalogCardSnapshot) async throws
    func setMetadataDate(_ date: Date, forKey key: String) async throws
}

struct CatalogSeriesGroup: Equatable, Identifiable, Sendable {
    let series: CatalogSeries
    let sets: [CatalogSet]

    var id: String { series.id }
}
