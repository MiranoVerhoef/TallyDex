import Foundation

struct CatalogSeries: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let logoURL: URL?

    func fillingMissingMetadata(from fallback: CatalogSeries?) -> CatalogSeries {
        CatalogSeries(
            id: id,
            name: name,
            logoURL: logoURL ?? fallback?.logoURL
        )
    }
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
            logoURL: logoURL ?? fallback?.logoURL,
            symbolURL: symbolURL ?? fallback?.symbolURL,
            officialCardCount: officialCardCount,
            totalCardCount: totalCardCount,
            releaseDate: releaseDate ?? fallback?.releaseDate,
            rarityCounts: rarityCounts?.isEmpty == false
                ? rarityCounts
                : fallback?.rarityCounts
        )
    }
}

struct CatalogCardAttack: Codable, Equatable, Hashable, Sendable {
    let name: String
    let cost: [String]
    let damage: String?
    let effect: String?
}

struct CatalogCardAbility: Codable, Equatable, Hashable, Sendable {
    let type: String?
    let name: String
    let effect: String
}

struct CatalogTypeModifier: Codable, Equatable, Hashable, Sendable {
    let type: String
    let value: String?
}

struct CatalogCardLegality: Codable, Equatable, Hashable, Sendable {
    let standard: Bool
    let expanded: Bool
}

struct CatalogCardMetadata: Codable, Equatable, Hashable, Sendable {
    let dexIDs: [Int]
    let hp: Int?
    let types: [String]
    let evolvesFrom: String?
    let stage: String?
    let suffix: String?
    let attacks: [CatalogCardAttack]
    let abilities: [CatalogCardAbility]
    let weaknesses: [CatalogTypeModifier]
    let resistances: [CatalogTypeModifier]
    let retreatCost: Int?
    let regulationMark: String?
    let legality: CatalogCardLegality?
    let rulesText: String?
    let trainerType: String?
    let energyType: String?
    let flavorText: String?
    let updatedAt: Date?
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
    let metadata: CatalogCardMetadata?

    init(
        id: String,
        setID: String,
        localID: String,
        name: String,
        imageURL: URL?,
        category: String?,
        illustrator: String?,
        rarity: String?,
        metadata: CatalogCardMetadata? = nil
    ) {
        self.id = id
        self.setID = setID
        self.localID = localID
        self.name = name
        self.imageURL = imageURL
        self.category = category
        self.illustrator = illustrator
        self.rarity = rarity
        self.metadata = metadata
    }
}

enum CatalogVariantKind: String, Codable, CaseIterable, Sendable {
    case normal
    case reverseHolo
    case holo
    case firstEdition
    case watermarkedPromo
    case prerelease
    case prereleaseStaff
    case trickOrTrade
    case jumbo

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .reverseHolo: "Reverse holo"
        case .holo: "Holo"
        case .firstEdition: "First edition"
        case .watermarkedPromo: "Watermarked promo"
        case .prerelease: "Prerelease"
        case .prereleaseStaff: "Prerelease Staff"
        case .trickOrTrade: "Trick or Trade"
        case .jumbo: "Jumbo"
        }
    }
}

/// One exact printing object supplied by TCGdex's `variants_detailed` field.
/// `providerID` is only unique within a card, so `id` deliberately includes
/// the card ID. Broad `CatalogVariantKind` values remain the ownership key in
/// this release to preserve existing collections losslessly.
struct CatalogPrinting: Codable, Equatable, Hashable, Identifiable, Sendable {
    let cardID: String
    let providerID: String
    let rawType: String
    let kind: CatalogVariantKind?
    let subtype: String?
    let size: String?
    let stamps: [String]
    let foil: String?
    let languages: [String]
    let cardmarketProductID: Int?
    let tcgplayerProductID: Int?
    let cardtraderProductID: Int?

    var id: String { "\(cardID)|\(providerID)" }

    var displayName: String {
        var components = [kind?.displayName ?? Self.title(rawType)]
        if let subtype, !subtype.isEmpty { components.append(Self.title(subtype)) }
        for stamp in stamps where !Self.isRepresentedByKind(stamp, kind: kind) {
            components.append(Self.title(stamp))
        }
        if let foil, !foil.isEmpty { components.append("\(Self.title(foil)) foil") }
        if size == "jumbo", kind != .jumbo { components.append("Jumbo") }
        return components.joined(separator: " · ")
    }

    var marketplaceIdentifiersDescription: String? {
        var values: [String] = []
        if let cardmarketProductID { values.append("Cardmarket \(cardmarketProductID)") }
        if let tcgplayerProductID { values.append("TCGplayer \(tcgplayerProductID)") }
        if let cardtraderProductID { values.append("CardTrader \(cardtraderProductID)") }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private static func title(_ value: String) -> String {
        value
            .split(separator: "-")
            .map { word in
                switch word.lowercased() {
                case "1st": "1st"
                case "hp": "HP"
                default: word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }
            }
            .joined(separator: " ")
    }

    private static func isRepresentedByKind(
        _ stamp: String,
        kind: CatalogVariantKind?
    ) -> Bool {
        switch (stamp, kind) {
        case ("1st-edition", .firstEdition),
             ("w-promo", .watermarkedPromo),
             ("pre-release", .prerelease),
             ("staff", .prereleaseStaff),
             ("trick-or-trade", .trickOrTrade):
            true
        default:
            false
        }
    }
}

struct CatalogVariantSearchQuery: Equatable, Sendable {
    enum Requirement: Equatable, Sendable {
        case prerelease
        case staff

        func matches(_ variants: Set<CatalogVariantKind>) -> Bool {
            switch self {
            case .prerelease:
                variants.contains(.prerelease) || variants.contains(.prereleaseStaff)
            case .staff:
                variants.contains(.prereleaseStaff)
            }
        }

        var displayName: String {
            switch self {
            case .prerelease: "Prerelease"
            case .staff: "Prerelease Staff"
            }
        }
    }

    let textQuery: String
    let requirement: Requirement?

    init(textQuery: String, requirement: Requirement?) {
        self.textQuery = textQuery
        self.requirement = requirement
    }

    init(_ query: String) {
        let rawTokens = query.split(whereSeparator: \Character.isWhitespace).map(String.init)
        var textTokens: [String] = []
        var foundPrerelease = false
        var foundStaff = false
        var index = 0

        while index < rawTokens.count {
            let token = Self.normalized(rawTokens[index])
            if token == "staff" {
                foundStaff = true
            } else if token == "prerelease" || token == "pre-release" {
                foundPrerelease = true
            } else if token == "pre",
                      rawTokens.indices.contains(index + 1),
                      Self.normalized(rawTokens[index + 1]) == "release" {
                foundPrerelease = true
                index += 1
            } else {
                textTokens.append(rawTokens[index])
            }
            index += 1
        }

        textQuery = textTokens.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        requirement = if foundStaff {
            .staff
        } else if foundPrerelease {
            .prerelease
        } else {
            nil
        }
    }

    private static func normalized(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters)
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

enum CardDisplaySettings {
    static let detailsExpandedByDefaultKey = "cards.details.expandedByDefault"
    static let defaultDetailsExpanded = false

    static var detailsExpandedByDefault: Bool {
        UserDefaults.standard.object(forKey: detailsExpandedByDefaultKey) as? Bool
            ?? defaultDetailsExpanded
    }
}

enum PricingSettings {
    static let sourceKey = "pricing.preferredSource"
    static let cardmarketCountryKey = "pricing.cardmarket.country"
    static let cardmarketCurrencyKey = "pricing.cardmarket.currency"
    static let historyRetentionKey = "pricing.history.retention"
    static let foreverHistorySizeLimitKey = "pricing.history.foreverSizeLimit"
    static let defaultSource = CatalogPriceSource.cardmarket
    static let defaultCardmarketCurrency = CardmarketCurrencyPreference.eur
    static let defaultHistoryRetention = CatalogPriceHistoryRetention.oneYear
    static let defaultForeverHistorySizeLimit = CatalogPriceHistorySizeLimit.mb50
    static let timeBasedMaximumHistoryPointCount = 250_000

    static var preferredSource: CatalogPriceSource {
        guard let rawValue = UserDefaults.standard.string(forKey: sourceKey) else {
            return defaultSource
        }
        return CatalogPriceSource(rawValue: rawValue) ?? defaultSource
    }

    static var historyRetention: CatalogPriceHistoryRetention {
        guard let rawValue = UserDefaults.standard.string(forKey: historyRetentionKey) else {
            return defaultHistoryRetention
        }
        return CatalogPriceHistoryRetention(rawValue: rawValue) ?? defaultHistoryRetention
    }

    static var foreverHistorySizeLimit: CatalogPriceHistorySizeLimit {
        guard let rawValue = UserDefaults.standard.string(forKey: foreverHistorySizeLimitKey) else {
            return defaultForeverHistorySizeLimit
        }
        return CatalogPriceHistorySizeLimit(rawValue: rawValue) ?? defaultForeverHistorySizeLimit
    }

    static var maximumHistoryPointCount: Int {
        historyRetention == .forever
            ? foreverHistorySizeLimit.maximumPointCount
            : timeBasedMaximumHistoryPointCount
    }
}

enum CatalogPriceHistoryRetention: String, CaseIterable, Identifiable, Sendable {
    case ninetyDays
    case oneYear
    case forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ninetyDays: "90 days"
        case .oneYear: "1 year"
        case .forever: "Forever"
        }
    }

    func cutoff(relativeTo date: Date, calendar: Calendar = .current) -> Date? {
        let days: Int? = switch self {
        case .ninetyDays: 90
        case .oneYear: 365
        case .forever: nil
        }
        guard let days else { return nil }
        return calendar.date(
            byAdding: .day,
            value: -(days - 1),
            to: calendar.startOfDay(for: date)
        )
    }
}

enum CatalogPriceHistorySizeLimit: String, CaseIterable, Identifiable, Sendable {
    case mb50
    case mb100
    case mb250
    case mb500
    case gb1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mb50: "50 MB"
        case .mb100: "100 MB"
        case .mb250: "250 MB"
        case .mb500: "500 MB"
        case .gb1: "1 GB"
        }
    }

    var byteCount: Int64 {
        switch self {
        case .mb50: 50_000_000
        case .mb100: 100_000_000
        case .mb250: 250_000_000
        case .mb500: 500_000_000
        case .gb1: 1_000_000_000
        }
    }

    var maximumPointCount: Int {
        Int(byteCount / CatalogPriceStorageStatistics.estimatedBytesPerHistoryPoint)
    }
}

enum CardmarketCountryPreference: String, CaseIterable, Identifiable, Sendable {
    case all
    case austria = "AT"
    case belgium = "BE"
    case bulgaria = "BG"
    case croatia = "HR"
    case cyprus = "CY"
    case czechia = "CZ"
    case denmark = "DK"
    case estonia = "EE"
    case finland = "FI"
    case france = "FR"
    case germany = "DE"
    case greece = "GR"
    case hungary = "HU"
    case iceland = "IS"
    case ireland = "IE"
    case italy = "IT"
    case latvia = "LV"
    case liechtenstein = "LI"
    case lithuania = "LT"
    case luxembourg = "LU"
    case malta = "MT"
    case netherlands = "NL"
    case norway = "NO"
    case poland = "PL"
    case portugal = "PT"
    case romania = "RO"
    case slovakia = "SK"
    case slovenia = "SI"
    case spain = "ES"
    case sweden = "SE"
    case switzerland = "CH"
    case unitedKingdom = "GB"

    var id: String { rawValue }

    var displayName: String {
        guard self != .all else { return "All countries" }
        return Locale.current.localizedString(forRegionCode: rawValue) ?? rawValue
    }

    /// Reserved for Cardmarket's seller-country filter when new third-party API
    /// applications are accepted again. Current TCGdex aggregates ignore it.
    var cardmarketSellerCountryID: Int? {
        switch self {
        case .all: nil
        case .austria: 1
        case .belgium: 2
        case .bulgaria: 3
        case .switzerland: 4
        case .cyprus: 5
        case .czechia: 6
        case .germany: 7
        case .denmark: 8
        case .estonia: 9
        case .spain: 10
        case .finland: 11
        case .france: 12
        case .unitedKingdom: 13
        case .greece: 14
        case .hungary: 15
        case .ireland: 16
        case .italy: 17
        case .liechtenstein: 18
        case .lithuania: 19
        case .luxembourg: 20
        case .latvia: 21
        case .malta: 22
        case .netherlands: 23
        case .norway: 24
        case .poland: 25
        case .portugal: 26
        case .romania: 27
        case .sweden: 28
        case .slovenia: 30
        case .slovakia: 31
        case .croatia: 35
        case .iceland: 37
        }
    }
}

enum CardmarketCurrencyPreference: String, CaseIterable, Identifiable, Sendable {
    case eur = "EUR"
    case usd = "USD"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eur: "Euro (EUR)"
        case .usd: "US Dollar (USD)"
        }
    }
}

struct CardmarketListingPreferences: Equatable, Sendable {
    let country: CardmarketCountryPreference
    let currency: CardmarketCurrencyPreference
}

struct CardmarketListingRequest: Equatable, Sendable {
    let productID: Int
    let preferences: CardmarketListingPreferences
}

struct CardmarketListing: Equatable, Identifiable, Sendable {
    let id: Int
    let productID: Int
    let sellerCountryCode: String
    let currencyCode: String
    let amount: Double
    let condition: String?
    let language: String?
    let isFoil: Bool
    let isReverseHolo: Bool
}

enum CardmarketListingAvailability: Equatable, Sendable {
    case waitingForOfficialAPI
    case available
}

protocol CardmarketListingProvider: Sendable {
    var availability: CardmarketListingAvailability { get }
    func listings(for request: CardmarketListingRequest) async throws -> [CardmarketListing]
}

struct CatalogPriceQuote: Codable, Equatable, Hashable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let source: CatalogPriceSource
    let currencyCode: String
    let amount: Double
    let updatedAt: Date
    let productID: Int?
    let average1Day: Double?
    let average7Days: Double?
    let average30Days: Double?

    init(
        cardID: String,
        variant: CatalogVariantKind,
        source: CatalogPriceSource,
        currencyCode: String,
        amount: Double,
        updatedAt: Date,
        productID: Int? = nil,
        average1Day: Double? = nil,
        average7Days: Double? = nil,
        average30Days: Double? = nil
    ) {
        self.cardID = cardID
        self.variant = variant
        self.source = source
        self.currencyCode = currencyCode
        self.amount = amount
        self.updatedAt = updatedAt
        self.productID = productID
        self.average1Day = average1Day
        self.average7Days = average7Days
        self.average30Days = average30Days
    }

    var id: String { "\(cardID)|\(variant.rawValue)|\(source.rawValue)" }

    var marketplaceURL: URL? {
        guard let productID, productID > 0 else { return nil }
        switch source {
        case .cardmarket:
            return URL(string: "https://www.cardmarket.com/en/Pokemon/Products?idProduct=\(productID)")
        case .tcgplayer:
            return URL(string: "https://www.tcgplayer.com/product/\(productID)")
        }
    }

    var hasRollingAverages: Bool {
        average1Day != nil || average7Days != nil || average30Days != nil
    }
}

struct CatalogPriceHistoryPoint: Codable, Equatable, Hashable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let source: CatalogPriceSource
    let day: Date
    let currencyCode: String
    let amount: Double
    let sourceUpdatedAt: Date

    var id: String {
        "\(cardID)|\(variant.rawValue)|\(source.rawValue)|\(day.timeIntervalSinceReferenceDate)"
    }
}

enum CatalogPriceHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .sevenDays: "7D"
        case .thirtyDays: "30D"
        case .ninetyDays: "90D"
        case .all: "All"
        }
    }

    private var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .all: nil
        }
    }

    func filter(
        _ points: [CatalogPriceHistoryPoint],
        relativeTo date: Date = .now,
        calendar: Calendar = .current
    ) -> [CatalogPriceHistoryPoint] {
        let sorted = points.sorted { $0.day < $1.day }
        guard let dayCount,
              let cutoff = calendar.date(
                byAdding: .day,
                value: -(dayCount - 1),
                to: calendar.startOfDay(for: date)
              ) else {
            return sorted
        }
        return sorted.filter { $0.day >= cutoff }
    }
}

struct CatalogPriceHistorySummary: Equatable, Sendable {
    let current: Double
    let absoluteChange: Double?
    let percentageChange: Double?
    let low: Double
    let high: Double

    init?(points: [CatalogPriceHistoryPoint]) {
        let sorted = points.sorted { $0.day < $1.day }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        current = last.amount
        low = sorted.map(\.amount).min() ?? last.amount
        high = sorted.map(\.amount).max() ?? last.amount
        if sorted.count > 1 {
            absoluteChange = last.amount - first.amount
            percentageChange = first.amount == 0
                ? nil
                : ((last.amount - first.amount) / first.amount) * 100
        } else {
            absoluteChange = nil
            percentageChange = nil
        }
    }
}

struct CatalogPriceStorageStatistics: Equatable, Sendable {
    static let estimatedBytesPerHistoryPoint: Int64 = 160

    let currentPriceCount: Int
    let historyPointCount: Int
    let databaseByteCount: Int64

    var estimatedHistoryByteCount: Int64 {
        Int64(historyPointCount) * Self.estimatedBytesPerHistoryPoint
    }
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
        // Shared views may reference the same canonical ownership record more
        // than once. Keep its latest value, rather than counting another copy.
        let uniqueEntries = entries.reduce(into: [String: CollectionVariantEntry]()) { result, entry in
            if let existing = result[entry.id],
               existing.updatedAt > entry.updatedAt
                || (existing.updatedAt == entry.updatedAt && existing.quantity >= entry.quantity) { return }
            result[entry.id] = entry
        }
        for entry in uniqueEntries.values.sorted(by: { $0.id < $1.id }) where entry.quantity > 0 {
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

/// Keep TCGdex's detailed printing data primary, then apply small, sourced
/// corrections for English Prerelease and Staff printings that the provider
/// does not yet identify.
enum CatalogVariantOverrides {
    private struct Override {
        let additions: Set<CatalogVariantKind>
        let removals: Set<CatalogVariantKind>
    }

    private static let byCardID: [String: Override] = [
        // Platinum 53/127 also had Prerelease and gold Staff-stamped prints.
        "pl1-53": Override(
            additions: [.normal, .reverseHolo, .prerelease, .prereleaseStaff],
            removals: []
        ),
        // Keep TCGdex's regular printing visible and add the two stamped versions.
        // A collector can therefore record regular, Prerelease, and Staff copies
        // independently without one printing hiding another.
        "smp-SM95": Override(additions: [.normal, .prerelease, .prereleaseStaff], removals: []),
        "swshp-SWSH186": Override(additions: [.normal, .prerelease, .prereleaseStaff], removals: []),
    ]

    static func apply(to variants: Set<CatalogVariantKind>, cardID: String) -> Set<CatalogVariantKind> {
        guard let override = byCardID[cardID] else { return variants }
        return variants.subtracting(override.removals).union(override.additions)
    }

    static func cardIDs(matching requirement: CatalogVariantSearchQuery.Requirement) -> [String] {
        byCardID.compactMap { cardID, override in
            requirement.matches(override.additions.subtracting(override.removals)) ? cardID : nil
        }
        .sorted()
    }
}

struct CatalogCardSnapshot: Codable, Equatable, Sendable {
    let card: CatalogCard
    let variants: Set<CatalogVariantKind>
    let prices: [CatalogPriceQuote]
    let printings: [CatalogPrinting]

    init(
        card: CatalogCard,
        variants: Set<CatalogVariantKind>,
        prices: [CatalogPriceQuote] = [],
        printings: [CatalogPrinting] = []
    ) {
        self.card = card
        self.variants = variants
        self.prices = prices
        self.printings = printings
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

enum CatalogSearchError: Error, Equatable, Sendable {
    case variantQueryTooBroad(candidateCount: Int)
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
    func searchCards(query: String, limit: Int?) async throws -> [CatalogCardSearchResult]
    func searchCards(requiredVariants: Set<CatalogVariantKind>) async throws -> [CatalogCardSearchResult]
    func fetchCards(matchingName query: String) async throws -> [CatalogCardSearchResult]
    func fetchCards(matchingPokemonRules rules: [PokemonCollectionRule]) async throws -> [CatalogCardSearchResult]
    func fetchSearchResults(cardIDs: [String]) async throws -> [CatalogCardSearchResult]
    func fetchVariants(cardID: String) async throws -> Set<CatalogVariantKind>
    func fetchVariants(cardIDs: [String]) async throws -> [String: Set<CatalogVariantKind>]
    func fetchPrintings(cardID: String) async throws -> [CatalogPrinting]
    func fetchPrices(cardIDs: [String]) async throws -> [String: [CatalogPriceQuote]]
    func fetchPriceHistory(
        cardID: String,
        source: CatalogPriceSource
    ) async throws -> [CatalogPriceHistoryPoint]
    func fetchCard(id: String) async throws -> CatalogCard?
    func priceStorageStatistics() async throws -> CatalogPriceStorageStatistics
    @discardableResult
    func prunePriceHistory(olderThan cutoff: Date?, maximumPoints: Int) async throws -> Int
    func clearPriceHistory() async throws
    func clearAllPrices() async throws
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

    var catalogueSetCount: Int {
        sets.count
    }

    var preferredArtworkURL: URL? {
        series.logoURL
    }
}

/// Presentation-only grouping. Provider series IDs and set/card identities stay intact.
enum CatalogSeriesGrouping {
    private static let mcdonaldsParentSeries: [String: String] = [
        "2011bw": "bw", "2012bw": "bw", "2013bw": "bw",
        "2014xy": "xy", "2015xy": "xy", "2016xy": "xy",
        "2017sm": "sm", "2018sm": "sm", "2019sm": "sm",
        "2021swsh": "swsh", "2022swsh": "swsh",
        "2023sv": "sv", "2024sv": "sv",
    ]

    static func groups(series: [CatalogSeries], sets: [CatalogSet]) -> [CatalogSeriesGroup] {
        let availableSeries = Set(series.map(\.id))
        let setsBySeries = Dictionary(grouping: sets) { set in
            if set.seriesID == "mc", let parent = mcdonaldsParentSeries[set.id],
               availableSeries.contains(parent) { return parent }
            // Unknown releases or absent parents remain visible in their provider series.
            return set.seriesID
        }
        return series.compactMap { item in
            let assigned = setsBySeries[item.id] ?? []
            if item.id == "mc", assigned.isEmpty { return nil }
            var ordered = assigned.filter { $0.seriesID == item.id }
            let supplemental = assigned.enumerated()
                .filter { $0.element.seriesID != item.id }
                .sorted {
                    let left = $0.element.releaseDate ?? ""
                    let right = $1.element.releaseDate ?? ""
                    return left == right ? $0.offset < $1.offset : left > right
                }
            for entry in supplemental {
                let set = entry.element
                let index = set.releaseDate.flatMap { date in
                    ordered.firstIndex { existing in
                        existing.releaseDate.map { $0 < date } ?? false
                    }
                } ?? ordered.endIndex
                ordered.insert(set, at: index)
            }
            return CatalogSeriesGroup(series: item, sets: ordered)
        }
    }
}

/// A checklist of exact stamped printings, not a second set of card records.
/// Membership was cross-checked against Pokellector/Bulbapedia and the English
/// TCGdex index. No artwork or market prices are inferred from the parent card.
struct TrickOrTradeRelease: Equatable, Identifiable, Sendable {
    let year: Int
    let seriesID: String
    let releaseDate: String
    let cardIDs: [String]

    var id: String { "tallydex-tot-\(year)" }
    var set: CatalogSet {
        CatalogSet(id: id, seriesID: seriesID, name: "Trick or Trade \(year)",
                   abbreviation: nil, logoURL: nil, symbolURL: nil,
                   officialCardCount: cardIDs.count, totalCardCount: cardIDs.count,
                   releaseDate: releaseDate, rarityCounts: nil)
    }

    static let all: [TrickOrTradeRelease] = [
        .init(year: 2022, seriesID: "swsh", releaseDate: "2022-09-01", cardIDs: [
            "swsh8-16", "swsh2-15", "swsh2-31", "swsh2-32", "swsh2-33",
            "swsh7-49", "swsh5-69", "swsh6-55", "swsh6-56", "swsh6-57",
            "swsh9-056", "swsh10-058", "swsh10-059", "swsh9-060", "swsh9-061",
            "swsh9-062", "swsh7-76", "swsh7-77", "swsh3-81", "swsh3-82",
            "swsh3-83", "swsh3.5-18", "swsh6-72", "swsh6-73", "swsh5-89",
            "swsh3-102", "swsh3-103", "swsh5-93", "swsh3-105", "swsh10-103",
        ]),
        .init(year: 2023, seriesID: "sv", releaseDate: "2023-09-01", cardIDs: [
            "swsh11-016", "swsh11-017", "swsh4-19", "sv01-034", "swsh11-024",
            "swsh11-025", "swsh11-026", "sv02-062", "swsh4-95", "swsh2-102",
            "swsh11-064", "swsh11-065", "swsh11-066", "swsh4-69", "swsh4-70",
            "swsh4-71", "sv01-087", "swsh11-073", "sv02-088", "sv01-089",
            "sv01-090", "sv02-097", "swsh7-80", "swsh11-081", "swsh1-89",
            "swsh1-90", "sv01-104", "sv01-106", "swsh12-103", "sv02-131",
        ]),
        .init(year: 2024, seriesID: "sv", releaseDate: "2024-08-30", cardIDs: [
            "sv06-012", "sv06-013", "sv02-012", "sv06-021", "sv06-022",
            "sv06-024", "sv06-036", "sv06-037", "sv06-038", "sv04-023",
            "sv02-050", "sv04.5-018", "sv06-111", "sv04-077", "sv04-078",
            "sv04.5-037", "sv04.5-042", "sv04.5-043", "sv05-077", "sv05-078",
            "sv06-095", "sv06-096", "sv05-102", "sv05-103", "sv04.5-057",
            "sv03-130", "sv03-131", "sv03-133", "sv03-136", "sv05-139",
        ]),
    ]

    static func release(setID: String) -> TrickOrTradeRelease? {
        all.first { $0.id == setID }
    }

    /// Keep known provider printing IDs intact. Curated IDs for absent printings
    /// are stable even if an API later supplies a different ID for the same stamp.
    func printing(cardID: String, providerPrintings: [CatalogPrinting] = []) -> CatalogPrinting? {
        guard cardIDs.contains(cardID) else { return nil }
        let knownID: String?
        if year == 2024 {
            knownID = switch cardID {
            case "sv03-130", "sv03-131", "sv03-133": "1jz5lzkp5ftnwh2lzmaeixidf6y9ps"
            case "sv03-136": "23hmnvtwds1n7f4b2o51f5iqrd8z"
            default: nil
            }
        } else { knownID = nil }
        let provider = providerPrintings.first {
            $0.stamps.contains("trick-or-trade") && (knownID == nil || $0.providerID == knownID)
        }
        return CatalogPrinting(
            cardID: cardID, providerID: knownID ?? "tallydex-tot-\(year)",
            rawType: provider?.rawType ?? "stamped", kind: .trickOrTrade,
            subtype: String(year), size: "standard", stamps: ["trick-or-trade"],
            foil: provider?.foil, languages: ["en"],
            cardmarketProductID: provider?.cardmarketProductID,
            tcgplayerProductID: provider?.tcgplayerProductID,
            cardtraderProductID: provider?.cardtraderProductID
        )
    }

    static func printings(cardID: String, providerPrintings: [CatalogPrinting]) -> [CatalogPrinting] {
        let releases = all.filter { $0.cardIDs.contains(cardID) }
        guard !releases.isEmpty else { return providerPrintings }
        // A provider stamp and its verified checklist entry describe the same
        // printing; never count both. Other provider printings stay unchanged.
        let representedIDs = Set(releases.compactMap { release in
            providerPrintings.first {
                $0.stamps.contains("trick-or-trade") && (
                    release.printing(cardID: cardID)?.providerID.hasPrefix("tallydex-") == true
                        || $0.providerID == release.printing(cardID: cardID)?.providerID
                )
            }?.providerID
        })
        return providerPrintings.filter { !representedIDs.contains($0.providerID) }
            + releases.compactMap { $0.printing(cardID: cardID, providerPrintings: providerPrintings) }
    }

    static func adding(to groups: [CatalogSeriesGroup]) -> [CatalogSeriesGroup] {
        groups.map { group in
            var sets = group.sets
            for release in all.filter({ $0.seriesID == group.id }) where !sets.contains(where: { $0.id == release.id }) {
                let index = sets.firstIndex { ($0.releaseDate ?? "9999") < release.releaseDate } ?? sets.endIndex
                sets.insert(release.set, at: index)
            }
            return CatalogSeriesGroup(series: group.series, sets: sets)
        }
    }
}

/// Era-level views of the exact oversized printings published by TCGdex.
/// Cards keep their canonical parent-set identity, so checking a jumbo here is
/// immediately reflected in the same card's printing picker and vice versa.
struct JumboPromoRelease: Equatable, Identifiable, Sendable {
    let seriesID: String
    let releaseDate: String
    let jumboPrintingCount: Int
    let cardIDs: [String]

    var id: String { "tallydex-jumbo-\(seriesID)" }
    /// Existing promo artwork reused by the virtual checklist. EX-era jumbo
    /// products use the Nintendo promos mark; the older Wizards eras share the
    /// Wizards Black Star Promos mark.
    var artworkSetID: String {
        switch seriesID {
        case "me": "mep"
        case "sv": "svp"
        case "swsh": "swshp"
        case "sm": "smp"
        case "dp": "dpp"
        case "ex": "np"
        default: "basep"
        }
    }

    var set: CatalogSet {
        catalogSet(copyingArtworkFrom: nil)
    }

    func catalogSet(copyingArtworkFrom artworkSet: CatalogSet?) -> CatalogSet {
        CatalogSet(
            id: id,
            seriesID: seriesID,
            name: "Jumbo Promos",
            abbreviation: nil,
            logoURL: artworkSet?.logoURL,
            symbolURL: nil,
            officialCardCount: jumboPrintingCount,
            totalCardCount: jumboPrintingCount,
            releaseDate: releaseDate,
            rarityCounts: nil
        )
    }

    /// Snapshot of English cards carrying `size: "jumbo"` in TCGdex's cards
    /// database. Some cards have multiple distinct jumbo printings, hence 152 exact
    /// printings across 145 canonical card records.
    static let all: [JumboPromoRelease] = [
        .init(seriesID: "me", releaseDate: "2025-09-26", jumboPrintingCount: 1, cardIDs: [
            "mep-012",
        ]),
        .init(seriesID: "sv", releaseDate: "2023-03-31", jumboPrintingCount: 44, cardIDs: [
            "sv03-125", "sv05-034", "sv05-081", "sv05-123", "sv06-040",
            "sv06-130", "sv07-001", "sv07-041", "sv07-105", "sv07-128",
            "sv08-048", "sv08-076", "sv08-130", "sv08.5-051", "sv08.5-076",
            "sv08.5-082", "sv09-030", "sv09-069", "sv09-075", "sv09-114",
            "sv10.5b-028", "svp-004", "svp-018", "svp-049", "svp-067",
            "svp-068", "svp-072", "svp-078", "svp-081", "svp-084",
            "svp-086", "svp-100", "svp-126", "svp-162", "svp-177",
            "svp-193", "svp-196", "svp-205", "svp-208", "svp-500",
        ]),
        .init(seriesID: "swsh", releaseDate: "2020-02-07", jumboPrintingCount: 73, cardIDs: [
            "swshp-SWSH001", "swshp-SWSH002", "swshp-SWSH003", "swshp-SWSH005",
            "swshp-SWSH014", "swshp-SWSH015", "swshp-SWSH016", "swshp-SWSH017",
            "swshp-SWSH021", "swshp-SWSH030", "swshp-SWSH043", "swshp-SWSH045",
            "swshp-SWSH049", "swshp-SWSH055", "swshp-SWSH057", "swshp-SWSH061",
            "swshp-SWSH078", "swshp-SWSH083", "swshp-SWSH084", "swshp-SWSH085",
            "swshp-SWSH086", "swshp-SWSH097", "swshp-SWSH099", "swshp-SWSH102",
            "swshp-SWSH103", "swshp-SWSH106", "swshp-SWSH107", "swshp-SWSH111",
            "swshp-SWSH130", "swshp-SWSH131", "swshp-SWSH132", "swshp-SWSH133",
            "swshp-SWSH134", "swshp-SWSH136", "swshp-SWSH137", "swshp-SWSH138",
            "swshp-SWSH139", "swshp-SWSH154", "swshp-SWSH155", "swshp-SWSH159",
            "swshp-SWSH163", "swshp-SWSH176", "swshp-SWSH180", "swshp-SWSH182",
            "swshp-SWSH184", "swshp-SWSH195", "swshp-SWSH197", "swshp-SWSH198",
            "swshp-SWSH214", "swshp-SWSH215", "swshp-SWSH219", "swshp-SWSH225",
            "swshp-SWSH226", "swshp-SWSH227", "swshp-SWSH228", "swshp-SWSH230",
            "swshp-SWSH249", "swshp-SWSH252", "swshp-SWSH254", "swshp-SWSH256",
            "swshp-SWSH265", "swshp-SWSH268", "swshp-SWSH280", "swshp-SWSH281",
            "swshp-SWSH286", "swshp-SWSH287", "swshp-SWSH292", "swshp-SWSH293",
            "swshp-SWSH294", "swshp-SWSH295", "swshp-SWSH298", "swshp-SWSH299",
            "swshp-SWSH301",
        ]),
        .init(seriesID: "sm", releaseDate: "2017-02-03", jumboPrintingCount: 1, cardIDs: [
            "sm3-88",
        ]),
        .init(seriesID: "dp", releaseDate: "2007-05-23", jumboPrintingCount: 10, cardIDs: [
            "dp1-103", "dp1-76", "dp1-93", "dpp-DP24", "dpp-DP26",
            "dpp-DP27", "dpp-DP40", "dpp-DP50",
        ]),
        .init(seriesID: "ex", releaseDate: "2003-06-18", jumboPrintingCount: 6, cardIDs: [
            "ex1-59", "ex1-74", "ex1-76", "ex1-94", "ex2-93",
        ]),
        .init(seriesID: "ecard", releaseDate: "2002-01-01", jumboPrintingCount: 8, cardIDs: [
            "bog-1", "bog-2", "bog-4", "bog-5", "bog-6", "bog-7", "bog-8", "bog-9",
        ]),
        .init(seriesID: "neo", releaseDate: "2000-12-16", jumboPrintingCount: 3, cardIDs: [
            "neo1-54", "neo1-57", "neo1-81",
        ]),
        .init(seriesID: "gym", releaseDate: "2000-08-14", jumboPrintingCount: 2, cardIDs: [
            "gym1-11", "gym2-14",
        ]),
        .init(seriesID: "base", releaseDate: "1999-01-09", jumboPrintingCount: 4, cardIDs: [
            "base1-44", "base1-46", "base1-58", "base1-63",
        ]),
    ]

    static func release(setID: String) -> JumboPromoRelease? {
        all.first { $0.id == setID }
    }

    static func contains(cardID: String) -> Bool {
        all.contains { $0.cardIDs.contains(cardID) }
    }

    static func printings(cardID: String, providerPrintings: [CatalogPrinting]) -> [CatalogPrinting] {
        guard contains(cardID: cardID) else { return providerPrintings }
        return providerPrintings.map { printing in
            guard printing.size == "jumbo", printing.kind != .jumbo else { return printing }
            return CatalogPrinting(
                cardID: printing.cardID,
                providerID: printing.providerID,
                rawType: printing.rawType,
                kind: .jumbo,
                subtype: printing.subtype,
                size: printing.size,
                stamps: printing.stamps,
                foil: printing.foil,
                languages: printing.languages,
                cardmarketProductID: printing.cardmarketProductID,
                tcgplayerProductID: printing.tcgplayerProductID,
                cardtraderProductID: printing.cardtraderProductID
            )
        }
    }

    static func adding(to groups: [CatalogSeriesGroup]) -> [CatalogSeriesGroup] {
        let artworkSetsByID = Dictionary(
            groups.flatMap(\.sets).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return groups.map { group in
            // The provider's old Miscellaneous/Jumbo cards shell has no card
            // records. Replace it with one useful checklist in each source era.
            var sets = group.sets.filter {
                $0.id != "jumbo" && release(setID: $0.id) == nil
            }
            guard let release = all.first(where: { $0.seriesID == group.id }) else {
                return CatalogSeriesGroup(series: group.series, sets: sets)
            }
            let promoIndex = sets.firstIndex {
                $0.name.localizedCaseInsensitiveContains("Black Star Promo")
                    || $0.name.localizedCaseInsensitiveContains("Wizards Black Star")
            }
            let jumboSet = release.catalogSet(copyingArtworkFrom: artworkSetsByID[release.artworkSetID])
            sets.insert(jumboSet, at: promoIndex.map { $0 + 1 } ?? 0)
            return CatalogSeriesGroup(series: group.series, sets: sets)
        }
    }
}
