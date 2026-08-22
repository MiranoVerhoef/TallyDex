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
    case prerelease
    case prereleaseStaff

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .reverseHolo: "Reverse holo"
        case .holo: "Holo"
        case .firstEdition: "First edition"
        case .watermarkedPromo: "Watermarked promo"
        case .prerelease: "Prerelease"
        case .prereleaseStaff: "Prerelease Staff"
        }
    }
}

enum CatalogPriceSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case cardmarket
    case tcgplayer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cardmarket: "Cardmarket"
        case .tcgplayer: "TCGplayer"
        }
    }

    var currencyCode: String {
        switch self {
        case .cardmarket: "EUR"
        case .tcgplayer: "USD"
        }
    }
}

enum PricingSettings {
    static let sourceKey = "pricing.preferredSource"
    static let defaultSource = CatalogPriceSource.cardmarket

    static var preferredSource: CatalogPriceSource {
        guard let rawValue = UserDefaults.standard.string(forKey: sourceKey) else {
            return defaultSource
        }
        return CatalogPriceSource(rawValue: rawValue) ?? defaultSource
    }
}

struct CatalogPriceQuote: Codable, Equatable, Hashable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let source: CatalogPriceSource
    let currencyCode: String
    let amount: Double
    let updatedAt: Date

    var id: String { "\(cardID)|\(variant.rawValue)|\(source.rawValue)" }
}

struct CatalogValueSummary: Equatable, Sendable {
    let amount: Double
    let pricedVariants: Int
    let missingVariants: Int
    let source: CatalogPriceSource

    var currencyCode: String { source.currencyCode }
}

enum CatalogValueCalculator {
    static func summary(
        entries: [CollectionVariantEntry],
        prices: [String: [CatalogPriceQuote]],
        source: CatalogPriceSource
    ) -> CatalogValueSummary {
        var amount = 0.0
        var pricedVariants = 0
        var missingVariants = 0
        for entry in entries where entry.quantity > 0 {
            if let quote = prices[entry.cardID]?.first(where: {
                $0.variant == entry.variant && $0.source == source
            }) {
                amount += quote.amount * Double(entry.quantity)
                pricedVariants += 1
            } else {
                missingVariants += 1
            }
        }
        return CatalogValueSummary(
            amount: amount,
            pricedVariants: pricedVariants,
            missingVariants: missingVariants,
            source: source
        )
    }
}

/// TCGdex does not currently distinguish stamped Prerelease and Staff prints.
/// Keep the provider data primary, then apply small, sourced corrections for
/// English printings that would otherwise be invisible to collectors.
enum CatalogVariantOverrides {
    private struct Override {
        let additions: Set<CatalogVariantKind>
        let removals: Set<CatalogVariantKind>
    }

    private static let byCardID: [String: Override] = [
        // TCGdex's source record lists both printings. Keep Reverse visible
        // while the compiled API response temporarily reports Normal only.
        "me04-001": Override(additions: [.normal, .reverseHolo], removals: []),
        // Platinum 53/127 also had Prerelease and gold Staff-stamped prints.
        "pl1-53": Override(
            additions: [.normal, .reverseHolo, .prerelease, .prereleaseStaff],
            removals: []
        ),
        // SM95 and SWSH186 are themselves Prerelease promos; their other
        // English printing is the Staff-stamped version, not an unstamped Normal.
        "smp-SM95": Override(additions: [.prerelease, .prereleaseStaff], removals: [.normal]),
        "swshp-SWSH186": Override(additions: [.prerelease, .prereleaseStaff], removals: [.normal]),
    ]

    static func apply(to variants: Set<CatalogVariantKind>, cardID: String) -> Set<CatalogVariantKind> {
        guard let override = byCardID[cardID] else { return variants }
        return variants.subtracting(override.removals).union(override.additions)
    }
}

struct CatalogCardSnapshot: Codable, Equatable, Sendable {
    let card: CatalogCard
    let variants: Set<CatalogVariantKind>
    let prices: [CatalogPriceQuote]

    init(
        card: CatalogCard,
        variants: Set<CatalogVariantKind>,
        prices: [CatalogPriceQuote] = []
    ) {
        self.card = card
        self.variants = variants
        self.prices = prices
    }
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
    func fetchPrices(cardIDs: [String]) async throws -> [String: [CatalogPriceQuote]]
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
