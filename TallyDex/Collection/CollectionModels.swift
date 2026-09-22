import Foundation

enum CollectionOwnershipFilter: String, CaseIterable, Identifiable, Sendable {
    case all, owned, missing
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CollectionCardSort: String, CaseIterable, Identifiable, Sendable {
    case releaseNewest, releaseOldest, setName, collectorNumber, cardName
    var id: String { rawValue }
    var title: String {
        switch self {
        case .releaseNewest: "Release date (newest)"
        case .releaseOldest: "Release date (oldest)"
        case .setName: "Set name"
        case .collectorNumber: "Collector number"
        case .cardName: "Card name"
        }
    }

    func precedes(_ left: CatalogCardSearchResult, _ right: CatalogCardSearchResult) -> Bool {
        switch self {
        case .releaseNewest:
            let l = left.setReleaseDate ?? "", r = right.setReleaseDate ?? ""
            if l != r { return l > r }
        case .releaseOldest:
            let l = left.setReleaseDate.flatMap { $0.isEmpty ? nil : $0 } ?? "9999"
            let r = right.setReleaseDate.flatMap { $0.isEmpty ? nil : $0 } ?? "9999"
            if l != r { return l < r }
        case .setName:
            let order = left.setName.localizedCaseInsensitiveCompare(right.setName)
            if order != .orderedSame { return order == .orderedAscending }
        case .collectorNumber:
            let l = Int(left.card.localID) ?? .max, r = Int(right.card.localID) ?? .max
            if l != r { return l < r }
        case .cardName:
            let order = left.card.name.localizedCaseInsensitiveCompare(right.card.name)
            if order != .orderedSame { return order == .orderedAscending }
        }
        if left.setName != right.setName { return left.setName < right.setName }
        let order = left.card.localID.localizedStandardCompare(right.card.localID)
        return order == .orderedSame ? left.card.id < right.card.id : order == .orderedAscending
    }
}

/// Temporary browsing choices only: never mutate a folder's species rules,
/// ownership, goals, or backups. Empty values mean no restriction.
struct CollectionCardFilters: Equatable, Sendable {
    var ownership: CollectionOwnershipFilter = .all
    var type = ""
    var seriesID = ""
    var setID = ""
    var rarity = ""
    var releaseYear = 0
    var sort: CollectionCardSort = .releaseNewest

    func activeCount(defaultOwnership: CollectionOwnershipFilter) -> Int {
        [ownership != defaultOwnership, !type.isEmpty, !seriesID.isEmpty,
         !setID.isEmpty, !rarity.isEmpty, releaseYear != 0].filter { $0 }.count
    }

    func matches(_ result: CatalogCardSearchResult, seriesID resolvedSeriesID: String?,
                 isOwned: Bool, progress: CollectionProgress) -> Bool {
        let ownershipMatches: Bool = switch ownership {
        case .all: true
        case .owned: isOwned
        case .missing: progress.completedSlots < progress.requiredSlots
        }
        return ownershipMatches
            && (type.isEmpty || result.card.metadata?.types.contains { Self.normalized($0) == Self.normalized(type) } == true)
            && (rarity.isEmpty || result.card.rarity.map { Self.normalized($0) == Self.normalized(rarity) } == true)
            && (seriesID.isEmpty || resolvedSeriesID == seriesID)
            && (setID.isEmpty || result.card.setID == setID)
            && (releaseYear == 0 || result.setReleaseDate?.hasPrefix(String(releaseYear)) == true)
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct CollectionCardFilterOptions: Sendable {
    struct Choice: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
    }
    let types: [String]
    let rarities: [String]
    let eras: [Choice]
    let sets: [Choice]
    let releaseYears: [Int]
    let seriesBySetID: [String: String]
    let missingTypeCount: Int
    let missingRarityCount: Int

    init(matches: [CatalogCardSearchResult], groups: [CatalogSeriesGroup]) {
        func values(_ strings: [String]) -> [String] {
            let cleaned = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
            var unique: [String: String] = [:]
            for value in cleaned where unique[CollectionCardFilters.normalized(value)] == nil {
                unique[CollectionCardFilters.normalized(value)] = value
            }
            return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        types = values(matches.flatMap { $0.card.metadata?.types ?? [] })
        rarities = values(matches.compactMap { $0.card.rarity })
        missingTypeCount = matches.filter { result in
            !(result.card.metadata?.types.contains { !CollectionCardFilters.normalized($0).isEmpty } ?? false)
        }.count
        missingRarityCount = matches.filter { CollectionCardFilters.normalized($0.card.rarity ?? "").isEmpty }.count
        var mapping: [String: String] = [:]
        for group in groups { for set in group.sets { mapping[set.id] = group.series.id } }
        seriesBySetID = mapping
        let matchingSetIDs = Set(matches.map { $0.card.setID })
        var seenEras: Set<String> = []
        eras = groups.compactMap { group in
            guard group.sets.contains(where: { matchingSetIDs.contains($0.id) }), seenEras.insert(group.series.id).inserted else { return nil }
            return Choice(id: group.series.id, name: group.series.name)
        }
        var matchingSets: [String: Choice] = [:]
        for result in matches { matchingSets[result.card.setID] = Choice(id: result.card.setID, name: result.setName) }
        sets = matchingSets.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        releaseYears = Set(matches.compactMap { $0.setReleaseDate.flatMap { Int($0.prefix(4)) } }).sorted(by: >)
    }

    func sets(in seriesID: String) -> [Choice] {
        seriesID.isEmpty ? sets : sets.filter { seriesBySetID[$0.id] == seriesID }
    }
}

struct CollectionVariantEntry: Equatable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let quantity: Int
    let updatedAt: Date

    var id: String { "\(cardID)|\(variant.rawValue)" }
}

/// Ownership of one exact printing reported by TCGdex. Printing identifiers
/// are scoped to a card, so both values are always part of the identity.
struct CollectionPrintingEntry: Equatable, Identifiable, Sendable {
    let cardID: String
    let printingID: String
    let variant: CatalogVariantKind
    let quantity: Int
    let updatedAt: Date

    var id: String { "\(cardID)|\(printingID)" }
}

enum CollectionGoal: String, Codable, CaseIterable, Sendable {
    case normal
    case master
    case custom

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .master: "Master"
        case .custom: "Custom"
        }
    }

    var explanation: String {
        switch self {
        case .normal: "Collect every card once. Any owned printing counts."
        case .master: "Collect every known printing of every card."
        case .custom: "Choose which numbered cards and printing types count."
        }
    }

    static func migrated(persistedValue: String) -> CollectionGoal? {
        switch persistedValue {
        case "main", "complete": .normal
        case "holoChase": .custom
        default: CollectionGoal(rawValue: persistedValue)
        }
    }
}

enum CollectionSettings {
    static let allowsMultipleCopiesKey = "collection.allowsMultipleCopies"
    static let allowsMultipleCopiesDefault = false
    static let defaultGoalKey = "collection.defaultGoal"
    static let defaultGoal = CollectionGoal.normal
    static let defaultCustomVariantsKey = "collection.defaultCustomVariants"
    static let defaultCustomIncludesSecretCardsKey = "collection.defaultCustomIncludesSecretCards"
    static let defaultCustomVariants: Set<CatalogVariantKind> = [.normal]
    static let defaultCustomIncludesSecretCards = true

    static var preferredDefaultGoal: CollectionGoal {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultGoalKey) else {
            return defaultGoal
        }
        return CollectionGoal(rawValue: rawValue) ?? defaultGoal
    }

    static var preferredDefaultCustomVariants: Set<CatalogVariantKind> {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: defaultCustomVariantsKey) else {
            return defaultCustomVariants
        }
        let variants = Set(rawValues.compactMap(CatalogVariantKind.init(rawValue:)))
        return variants.isEmpty ? defaultCustomVariants : variants
    }

    static var preferredDefaultCustomIncludesSecretCards: Bool {
        guard UserDefaults.standard.object(forKey: defaultCustomIncludesSecretCardsKey) != nil else {
            return defaultCustomIncludesSecretCards
        }
        return UserDefaults.standard.bool(forKey: defaultCustomIncludesSecretCardsKey)
    }
}

enum SetTrackingStatus: String, Codable, CaseIterable, Sendable {
    case notCollecting
    case collecting
    case hidden

    var displayName: String {
        switch self {
        case .notCollecting: "Not collecting"
        case .collecting: "My Sets"
        case .hidden: "Hidden"
        }
    }
}

struct SetCollectionPreference: Equatable, Sendable {
    let setID: String
    let status: SetTrackingStatus
    let goal: CollectionGoal
    let includedVariants: Set<CatalogVariantKind>
    let includesSecretCards: Bool
    let updatedAt: Date

    static func defaultPreference(
        setID: String,
        goal: CollectionGoal = .normal,
        customVariants: Set<CatalogVariantKind> = CollectionSettings.preferredDefaultCustomVariants,
        customIncludesSecretCards: Bool = CollectionSettings.preferredDefaultCustomIncludesSecretCards,
        updatedAt: Date = .distantPast
    ) -> SetCollectionPreference {
        let rules: (variants: Set<CatalogVariantKind>, includesSecretCards: Bool) = switch goal {
        case .normal: ([.normal], true)
        case .master: (Set(CatalogVariantKind.allCases), true)
        case .custom: (customVariants.isEmpty ? [.normal] : customVariants, customIncludesSecretCards)
        }
        return SetCollectionPreference(
            setID: setID,
            status: .notCollecting,
            goal: goal,
            includedVariants: rules.variants,
            includesSecretCards: rules.includesSecretCards,
            updatedAt: updatedAt
        )
    }

    func visibleVariants(in knownVariants: Set<CatalogVariantKind>) -> Set<CatalogVariantKind> {
        switch goal {
        case .master:
            return knownVariants
        case .custom:
            return knownVariants.intersection(includedVariants)
        case .normal:
            let preference: [CatalogVariantKind] = [
                .normal,
                .holo,
                .reverseHolo,
                .firstEdition,
                .watermarkedPromo,
                .prerelease,
                .prereleaseStaff,
            ]
            guard let primary = preference.first(where: knownVariants.contains) else { return [] }
            return [primary]
        }
    }

    func applyingCanonicalGoalRules() -> SetCollectionPreference {
        let rules: (variants: Set<CatalogVariantKind>, includesSecretCards: Bool) = switch goal {
        case .normal:
            ([.normal], true)
        case .master:
            (Set(CatalogVariantKind.allCases), true)
        case .custom:
            (includedVariants.isEmpty ? [.normal] : includedVariants, includesSecretCards)
        }
        return SetCollectionPreference(
            setID: setID,
            status: status,
            goal: goal,
            includedVariants: rules.variants,
            includesSecretCards: rules.includesSecretCards,
            updatedAt: updatedAt
        )
    }
}

struct CardCollectionMetadata: Equatable, Sendable {
    let cardID: String
    let isWishlisted: Bool
    let notes: String
    let updatedAt: Date

    static func empty(cardID: String) -> CardCollectionMetadata {
        CardCollectionMetadata(cardID: cardID, isWishlisted: false, notes: "", updatedAt: .distantPast)
    }
}

struct CollectionProgress: Equatable, Sendable {
    let completedSlots: Int
    let requiredSlots: Int

    var percentage: Int {
        guard requiredSlots > 0 else { return 0 }
        return Int((Double(completedSlots) / Double(requiredSlots) * 100).rounded())
    }
}

enum CollectionProgressCalculator {
    static func printingProgress(
        cardID: String,
        availableVariants: Set<CatalogVariantKind>,
        ownedEntries: [CollectionVariantEntry]
    ) -> CollectionProgress {
        let required = availableVariants.isEmpty ? Set([CatalogVariantKind.normal]) : availableVariants
        let owned = Set(
            ownedEntries.lazy
                .filter { $0.cardID == cardID && $0.quantity > 0 }
                .map(\.variant)
        )
        return CollectionProgress(
            completedSlots: required.intersection(owned).count,
            requiredSlots: required.count
        )
    }

    static func progress(
        cards: [CatalogCard],
        set: CatalogSet,
        preference: SetCollectionPreference,
        availableVariants: [String: Set<CatalogVariantKind>],
        ownedEntries: [CollectionVariantEntry],
        availablePrintings: [String: [CatalogPrinting]] = [:],
        exactOwnedEntries: [CollectionPrintingEntry] = []
    ) -> CollectionProgress {
        combined(
            progressByCardID(
                cards: cards,
                set: set,
                preference: preference,
                availableVariants: availableVariants,
                ownedEntries: ownedEntries,
                availablePrintings: availablePrintings,
                exactOwnedEntries: exactOwnedEntries
            )
        )
    }

    static func progressByCardID(
        cards: [CatalogCard],
        set: CatalogSet,
        preference: SetCollectionPreference,
        availableVariants: [String: Set<CatalogVariantKind>],
        ownedEntries: [CollectionVariantEntry],
        availablePrintings: [String: [CatalogPrinting]] = [:],
        exactOwnedEntries: [CollectionPrintingEntry] = []
    ) -> [String: CollectionProgress] {
        let owned = Dictionary(grouping: ownedEntries.filter { $0.quantity > 0 }, by: \.cardID)
        let exactOwned = Dictionary(grouping: exactOwnedEntries.filter { $0.quantity > 0 }, by: \.cardID)
        var result: [String: CollectionProgress] = [:]
        result.reserveCapacity(cards.count)

        for card in cards where includes(card: card, set: set, preference: preference) {
            let knownVariants = availableVariants[card.id] ?? []
            let broadOwnedForCard = owned[card.id] ?? []
            let exactOwnedForCard = exactOwned[card.id] ?? []
            let ownedVariants = Set(broadOwnedForCard.map(\.variant)).union(exactOwnedForCard.map(\.variant))

            if preference.goal == .normal {
                result[card.id] = CollectionProgress(
                    completedSlots: ownedVariants.isEmpty ? 0 : 1,
                    requiredSlots: 1
                )
                continue
            }

            let requiredVariants = variants(
                for: preference,
                knownVariants: knownVariants
            )
            let currentPrintingIDs = Set((availablePrintings[card.id] ?? []).map(\.providerID))
            let unresolvedExactCount = exactOwnedForCard.filter {
                !currentPrintingIDs.contains($0.printingID)
            }.count
            var completedSlots = 0
            var requiredSlots = 0
            for variant in requiredVariants {
                let exactOptions = (availablePrintings[card.id] ?? []).filter { $0.kind == variant }
                guard !exactOptions.isEmpty else {
                    requiredSlots += 1
                    if ownedVariants.contains(variant) { completedSlots += 1 }
                    continue
                }

                requiredSlots += exactOptions.count
                let requiredIDs = Set(exactOptions.map(\.providerID))
                let exactCompleted = Set(
                    exactOwnedForCard
                        .filter { requiredIDs.contains($0.printingID) }
                        .map(\.printingID)
                ).count
                // An old broad check represents one real but unspecified copy.
                // It may satisfy one slot, never every possible exact printing.
                let fallbackCompleted = broadOwnedForCard.contains { $0.variant == variant } ? 1 : 0
                completedSlots += min(exactOptions.count, exactCompleted + fallbackCompleted)
            }
            // A stale provider ID still represents a real owned card. Normal
            // reconciliation resolves it; this fallback protects progress when
            // a future provider correction is genuinely ambiguous.
            completedSlots += min(unresolvedExactCount, max(0, requiredSlots - completedSlots))
            result[card.id] = CollectionProgress(completedSlots: completedSlots, requiredSlots: requiredSlots)
        }
        return result
    }

    static func combined(_ progressByCardID: [String: CollectionProgress]) -> CollectionProgress {
        progressByCardID.values.reduce(
            into: CollectionProgress(completedSlots: 0, requiredSlots: 0)
        ) { result, progress in
            result = CollectionProgress(
                completedSlots: result.completedSlots + progress.completedSlots,
                requiredSlots: result.requiredSlots + progress.requiredSlots
            )
        }
    }

    static func includes(
        card: CatalogCard,
        set: CatalogSet,
        preference: SetCollectionPreference
    ) -> Bool {
        switch preference.goal {
        case .normal, .master:
            return true
        case .custom:
            return preference.includesSecretCards || isMainNumbered(card, in: set)
        }
    }

    private static func variants(
        for preference: SetCollectionPreference,
        knownVariants: Set<CatalogVariantKind>
    ) -> Set<CatalogVariantKind> {
        switch preference.goal {
        case .normal:
            return []
        case .master:
            return knownVariants.isEmpty ? [.normal] : knownVariants
        case .custom:
            if knownVariants.isEmpty {
                return preference.includedVariants.contains(.normal) ? [.normal] : []
            }
            return knownVariants.intersection(preference.includedVariants)
        }
    }

    private static func isMainNumbered(_ card: CatalogCard, in set: CatalogSet) -> Bool {
        guard set.officialCardCount > 0 else { return true }
        let trimmed = card.localID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isNumber),
              let number = Int(trimmed) else {
            return set.totalCardCount == set.officialCardCount
        }
        return number <= set.officialCardCount
    }
}

enum CustomCollectionFolderDisplayMode: String, Codable, CaseIterable, Sendable {
    case allMatching
    case ownedOnly

    var displayName: String {
        switch self {
        case .allMatching: "All"
        case .ownedOnly: "Owned"
        }
    }

    var explanation: String {
        switch self {
        case .allMatching: "Show every matching card so you can see what is still missing."
        case .ownedOnly: "Only show matching cards already in your collection."
        }
    }
}

struct PokemonCollectionRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let dexID: Int?

    init(name: String, dexID: Int? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dexID = dexID
    }

    var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    static func isValid(_ rules: [Self]) -> Bool {
        (1...2).contains(rules.count)
            && rules.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.dexID.map { $0 > 0 } ?? true) }
            && Set(rules.map(\.id)).count == rules.count
            && Set(rules.compactMap(\.dexID)).count == rules.compactMap(\.dexID).count
    }

    static func decode(_ json: String?) -> [Self]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Self].self, from: data)
    }

    static func encode(_ rules: [Self]?) throws -> String? {
        guard let rules else { return nil }
        return String(data: try JSONEncoder().encode(rules), encoding: .utf8)
    }
}

struct PokemonRuleChoice: Equatable, Identifiable, Sendable {
    let name: String
    let matchingCardCount: Int
    let exampleCard: CatalogCard
    let exampleSetName: String
    let dexID: Int?

    var id: String { name.lowercased() }
    var rule: PokemonCollectionRule { .init(name: name, dexID: dexID) }
}

enum PokemonRuleSearch {
    static func choices(
        from results: [CatalogCardSearchResult],
        query: String
    ) -> [PokemonRuleChoice] {
        let normalizedQuery = normalized(query)
        var grouped: [String: (name: String, matches: [CatalogCardSearchResult])] = [:]
        for result in results {
            guard isPokemon(result.card) else { continue }
            for speciesName in speciesNames(in: result.card.name) {
                let key = normalized(speciesName)
                guard key.contains(normalizedQuery) else { continue }
                if var existing = grouped[key] {
                    if !existing.matches.contains(where: { $0.card.id == result.card.id }) {
                        existing.matches.append(result)
                    }
                    grouped[key] = existing
                } else {
                    grouped[key] = (speciesName, [result])
                }
            }
        }

        return grouped.compactMap { _, group in
            // Never infer which ID belongs to which name from a multi-Pokémon card.
            guard let example = group.matches.first(where: {
                speciesNames(in: $0.card.name).count == 1
            }) ?? group.matches.first else { return nil }
            return PokemonRuleChoice(
                name: group.name,
                matchingCardCount: group.matches.count,
                exampleCard: example.card,
                exampleSetName: example.setName,
                dexID: verifiedDexID(for: group.name, from: group.matches)
            )
        }.sorted { left, right in
            let leftName = normalized(left.name)
            let rightName = normalized(right.name)
            let leftExact = leftName == normalizedQuery
            let rightExact = rightName == normalizedQuery
            if leftExact != rightExact { return leftExact }
            let leftPrefix = leftName.hasPrefix(normalizedQuery)
            let rightPrefix = rightName.hasPrefix(normalizedQuery)
            if leftPrefix != rightPrefix { return leftPrefix }
            if left.name.count != right.name.count { return left.name.count < right.name.count }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    static func matches(cardName: String, pokemonName: String) -> Bool {
        let expected = normalized(pokemonName)
        guard !expected.isEmpty else { return false }
        return speciesNames(in: cardName).contains { normalized($0) == expected }
    }

    static func matches(card: CatalogCard, rules: [PokemonCollectionRule]) -> Bool {
        guard isPokemon(card) else { return false }
        return rules.contains { rule in
            if let dexID = rule.dexID, let ids = card.metadata?.dexIDs, !ids.isEmpty {
                return ids.contains(dexID)
            }
            return matches(cardName: card.name, pokemonName: rule.name)
        }
    }

    static func verifiedDexID(for name: String, from results: [CatalogCardSearchResult]) -> Int? {
        let ids = Set(results.compactMap { result -> Int? in
            let species = speciesNames(in: result.card.name)
            guard isPokemon(result.card), species.count == 1,
                  normalized(species[0]) == normalized(name),
                  let dexIDs = result.card.metadata?.dexIDs, dexIDs.count == 1,
                  let id = dexIDs.first, id > 0 else { return nil }
            return id
        })
        return ids.count == 1 ? ids.first : nil
    }

    private static func isPokemon(_ card: CatalogCard) -> Bool {
        guard let category = card.category else { return true }
        return normalized(category) == "pokemon"
    }

    private static func speciesNames(in cardName: String) -> [String] {
        cardName.components(separatedBy: " & ").compactMap { component in
            var name = component.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonPokemonSuffixes = [" Spirit Link", " Doll"]
            guard !nonPokemonSuffixes.contains(where: {
                name.range(of: $0, options: [.caseInsensitive, .anchored, .backwards]) != nil
            }) else { return nil }

            let suffixes = [
                " V-UNION", " VSTAR", " VMAX", " LEGEND", " BREAK", " LV.X",
                " Prime", " Star", "-GX", " GX", "-EX", " EX", " ex", " V",
                " GL", " FB", " E4", " C", " G", " δ", " ☆",
            ]
            var removedSuffix = true
            while removedSuffix {
                removedSuffix = false
                for suffix in suffixes where name.range(
                    of: suffix,
                    options: [.caseInsensitive, .anchored, .backwards]
                ) != nil {
                    name.removeLast(suffix.count)
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    removedSuffix = true
                    break
                }
            }

            if let ownerRange = name.range(of: "'s ", options: [.caseInsensitive, .backwards]) {
                name = String(name[ownerRange.upperBound...])
            }

            let prefixes = [
                "Mega ", "M ", "Hisuian ", "Galarian ", "Alolan ", "Paldean ",
                "Dark ", "Light ", "Rocket's ",
            ]
            var removedPrefix = true
            while removedPrefix {
                removedPrefix = false
                for prefix in prefixes where name.hasPrefix(prefix, options: .caseInsensitive) {
                    name.removeFirst(prefix.count)
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    removedPrefix = true
                    break
                }
            }
            return name.isEmpty ? nil : name
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private extension String {
    func hasPrefix(_ prefix: String, options: String.CompareOptions) -> Bool {
        range(of: prefix, options: options.union(.anchored)) != nil
    }
}

struct CustomCollectionFolder: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let cardNameQuery: String
    /// A canonical species selected from the catalogue. `nil` identifies a
    /// legacy free-text rule, which retains its original substring behavior.
    let pokemonName: String?
    /// Up to two verified species rules. Absent on older folders/backups.
    let pokemonRules: [PokemonCollectionRule]?
    let displayMode: CustomCollectionFolderDisplayMode
    let iconName: String
    let coverCardID: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        name: String,
        cardNameQuery: String,
        pokemonName: String? = nil,
        pokemonRules: [PokemonCollectionRule]? = nil,
        displayMode: CustomCollectionFolderDisplayMode,
        iconName: String = CollectionFolderIcon.defaultIcon.rawValue,
        coverCardID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.cardNameQuery = cardNameQuery
        self.pokemonName = pokemonName
        self.pokemonRules = pokemonRules
        self.displayMode = displayMode
        self.iconName = CollectionFolderIcon.validated(iconName).rawValue
        self.coverCardID = coverCardID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var effectivePokemonRules: [PokemonCollectionRule] {
        pokemonRules ?? pokemonName.map { [.init(name: $0)] } ?? []
    }

    var pokemonSummary: String? {
        let rules = effectivePokemonRules
        return rules.isEmpty ? nil : rules.map(\.name).joined(separator: " + ")
    }
}

enum CollectionFolderIcon: String, CaseIterable, Identifiable, Sendable {
    case stack = "rectangle.stack.fill"
    case folder = "folder.fill"
    case star = "star.fill"
    case heart = "heart.fill"
    case sparkles = "sparkles"
    case bolt = "bolt.fill"
    case flame = "flame.fill"
    case crown = "crown.fill"
    case trophy = "trophy.fill"
    case paw = "pawprint.fill"

    static let defaultIcon: CollectionFolderIcon = .stack
    var id: String { rawValue }

    static func validated(_ value: String?) -> CollectionFolderIcon {
        value.flatMap(CollectionFolderIcon.init(rawValue:)) ?? defaultIcon
    }
}

enum BinderPocketLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case four = "4-pocket"
    case nine = "9-pocket"
    case twelve = "12-pocket"
    case twelveXL = "12-pocket-xl"
    case sixteenXXL = "16-pocket-xxl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .four: "4-pocket · 160 cards"
        case .nine: "9-pocket · 360 cards"
        case .twelve: "12-pocket · 480 cards"
        case .twelveXL: "12-pocket XL · 624 cards"
        case .sixteenXXL: "16-pocket XXL · 1,088 cards"
        }
    }

    var shortName: String {
        switch self {
        case .four: "4-pocket"
        case .nine: "9-pocket"
        case .twelve: "12-pocket"
        case .twelveXL: "12-pocket XL"
        case .sixteenXXL: "16-pocket XXL"
        }
    }

    var rows: Int {
        switch self {
        case .four: 2
        case .nine, .twelve, .twelveXL: 3
        case .sixteenXXL: 4
        }
    }

    var columns: Int {
        switch self {
        case .four: 2
        case .nine: 3
        case .twelve, .twelveXL, .sixteenXXL: 4
        }
    }

    var pocketsPerSide: Int { rows * columns }

    var doubleSidedPageCount: Int {
        switch self {
        case .four, .nine, .twelve: 20
        case .twelveXL: 26
        case .sixteenXXL: 34
        }
    }

    var capacity: Int { pocketsPerSide * doubleSidedPageCount * 2 }

    var formatSummary: String {
        "\(columns) × \(rows) · \(doubleSidedPageCount) double-sided pages"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawValue = try? container.decode(String.self),
           let layout = Self(rawValue: rawValue) {
            self = layout
            return
        }

        // Versions through 0.9.28 stored the pocket count as a JSON number.
        switch try container.decode(Int.self) {
        case 9: self = .nine
        case 12: self = .twelve
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported binder pocket layout"
            )
        }
    }
}

enum BinderPlanSourceKind: String, Codable, CaseIterable, Sendable {
    case collection
    case set

    var displayName: String {
        switch self {
        case .collection: "Collection"
        case .set: "Set"
        }
    }
}

enum BinderCardOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case setRelease
    case newestRelease
    case pokemonName
    case pokedexNumber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .setRelease: "Set release order"
        case .newestRelease: "Release year · newest first"
        case .pokemonName: "Pokémon name · A–Z"
        case .pokedexNumber: "Pokédex number"
        }
    }
}

struct BinderPlan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let sourceKind: BinderPlanSourceKind
    let sourceID: String
    let sourceName: String
    let pocketLayout: BinderPocketLayout
    let includesMissingCards: Bool
    let cardOrder: BinderCardOrder?
    let createdAt: Date
    let updatedAt: Date

    var effectiveCardOrder: BinderCardOrder { cardOrder ?? .setRelease }

    init(
        id: UUID,
        name: String,
        sourceKind: BinderPlanSourceKind,
        sourceID: String,
        sourceName: String,
        pocketLayout: BinderPocketLayout,
        includesMissingCards: Bool,
        cardOrder: BinderCardOrder = .setRelease,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.pocketLayout = pocketLayout
        self.includesMissingCards = includesMissingCards
        self.cardOrder = cardOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (sourceKind != .collection || UUID(uuidString: sourceID) != nil)
    }
}

enum BinderPlanOrdering {
    static func sorted(
        _ results: [CatalogCardSearchResult],
        by order: BinderCardOrder
    ) -> [CatalogCardSearchResult] {
        results.sorted { left, right in
            switch order {
            case .setRelease:
                return releaseOrder(left, right, newestFirst: false)
            case .newestRelease:
                return releaseOrder(left, right, newestFirst: true)
            case .pokemonName:
                let name = left.card.name.localizedCaseInsensitiveCompare(right.card.name)
                if name != .orderedSame { return name == .orderedAscending }
                return releaseOrder(left, right, newestFirst: false)
            case .pokedexNumber:
                let leftDex = left.card.metadata?.dexIDs.first(where: { $0 > 0 }) ?? .max
                let rightDex = right.card.metadata?.dexIDs.first(where: { $0 > 0 }) ?? .max
                if leftDex != rightDex { return leftDex < rightDex }
                let name = left.card.name.localizedCaseInsensitiveCompare(right.card.name)
                if name != .orderedSame { return name == .orderedAscending }
                return releaseOrder(left, right, newestFirst: false)
            }
        }
    }

    private static func releaseOrder(
        _ left: CatalogCardSearchResult,
        _ right: CatalogCardSearchResult,
        newestFirst: Bool
    ) -> Bool {
        if left.setReleaseDate != right.setReleaseDate {
            switch (left.setReleaseDate, right.setReleaseDate) {
            case let (leftDate?, rightDate?): return newestFirst ? leftDate > rightDate : leftDate < rightDate
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): break
            }
        }
        let setName = left.setName.localizedCaseInsensitiveCompare(right.setName)
        if setName != .orderedSame { return setName == .orderedAscending }
        let localID = left.card.localID.localizedStandardCompare(right.card.localID)
        if localID != .orderedSame { return localID == .orderedAscending }
        return left.card.id < right.card.id
    }
}

enum BinderPlanStorage {
    static let key = "binderPlanner.plans.v1"

    static func load(from defaults: UserDefaults = .standard) -> [BinderPlan] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BinderPlan].self, from: data) else {
            return []
        }
        var seen = Set<UUID>()
        return decoded
            .filter { $0.isValid && seen.insert($0.id).inserted }
            .sorted { left, right in
                if left.updatedAt == right.updatedAt { return left.name < right.name }
                return left.updatedAt > right.updatedAt
            }
    }

    static func save(_ plans: [BinderPlan], to defaults: UserDefaults = .standard) throws {
        guard plans.allSatisfy(\.isValid), Set(plans.map(\.id)).count == plans.count else {
            throw CollectionRepositoryError.invalidBinderPlan
        }
        defaults.set(try JSONEncoder().encode(plans), forKey: key)
    }

    static func remove(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

struct BinderPlanSlotDefinition: Equatable, Identifiable, Sendable {
    let cardID: String
    let printingID: String?
    let variant: CatalogVariantKind?
    let label: String?
    let isOwned: Bool

    var id: String {
        if let printingID { return "\(cardID)|printing|\(printingID)" }
        if let variant { return "\(cardID)|variant|\(variant.rawValue)" }
        return "\(cardID)|normal-goal"
    }
}

enum BinderPlanLayoutBuilder {
    static func slots(
        cards: [CatalogCard],
        set: CatalogSet,
        preference: SetCollectionPreference,
        availableVariants: [String: Set<CatalogVariantKind>],
        availablePrintings: [String: [CatalogPrinting]],
        broadOwnedEntries: [CollectionVariantEntry],
        exactOwnedEntries: [CollectionPrintingEntry]
    ) -> [BinderPlanSlotDefinition] {
        let broadByCardID = Dictionary(
            grouping: broadOwnedEntries.filter { $0.quantity > 0 },
            by: \.cardID
        )
        let exactByCardID = Dictionary(
            grouping: exactOwnedEntries.filter { $0.quantity > 0 },
            by: \.cardID
        )
        var slots: [BinderPlanSlotDefinition] = []

        for card in cards where CollectionProgressCalculator.includes(
            card: card, set: set, preference: preference
        ) {
            let broad = broadByCardID[card.id] ?? []
            let exact = exactByCardID[card.id] ?? []
            let knownVariants = availableVariants[card.id] ?? []
            let supplementalVariant: CatalogVariantKind? = if JumboPromoRelease.release(setID: set.id) != nil {
                .jumbo
            } else if TrickOrTradeRelease.release(setID: set.id) != nil {
                .trickOrTrade
            } else {
                nil
            }

            if preference.goal == .normal, supplementalVariant == nil {
                slots.append(BinderPlanSlotDefinition(
                    cardID: card.id,
                    printingID: nil,
                    variant: nil,
                    label: nil,
                    isOwned: broad.contains { $0.quantity > 0 } || exact.contains { $0.quantity > 0 }
                ))
                continue
            }

            let requiredVariants: Set<CatalogVariantKind>
            if let supplementalVariant {
                requiredVariants = [supplementalVariant]
            } else if knownVariants.isEmpty {
                requiredVariants = switch preference.goal {
                case .normal, .master: [.normal]
                case .custom: preference.includedVariants.contains(.normal) ? [.normal] : []
                }
            } else {
                requiredVariants = preference.visibleVariants(in: knownVariants)
            }

            for variant in CatalogVariantKind.allCases where requiredVariants.contains(variant) {
                let exactOptions = (availablePrintings[card.id] ?? [])
                    .filter { $0.kind == variant }
                    .sorted { $0.providerID < $1.providerID }
                guard !exactOptions.isEmpty else {
                    slots.append(BinderPlanSlotDefinition(
                        cardID: card.id,
                        printingID: nil,
                        variant: variant,
                        label: variant.displayName,
                        isOwned: broad.contains { $0.variant == variant }
                            || exact.contains { $0.variant == variant }
                    ))
                    continue
                }

                var broadFallbacks = broad.contains { $0.variant == variant } ? 1 : 0
                for printing in exactOptions {
                    let hasExactCopy = exact.contains { $0.printingID == printing.providerID }
                    let usesFallback = !hasExactCopy && broadFallbacks > 0
                    if usesFallback { broadFallbacks -= 1 }
                    slots.append(BinderPlanSlotDefinition(
                        cardID: card.id,
                        printingID: printing.providerID,
                        variant: variant,
                        label: printing.displayName,
                        isOwned: hasExactCopy || usesFallback
                    ))
                }
            }
        }
        return slots
    }
}

struct CollectionBackup: Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let reason: String
}

protocol CollectionRepository: Sendable {
    func fetchEntries(cardID: String) async throws -> [CollectionVariantEntry]
    func fetchOwnedEntries() async throws -> [CollectionVariantEntry]
    func fetchPrintingEntries(cardID: String) async throws -> [CollectionPrintingEntry]
    func fetchOwnedPrintingEntries() async throws -> [CollectionPrintingEntry]
    func prepareExactOwnershipMigration(createdAt: Date) async throws
    @discardableResult
    func reconcileExactOwnership(
        cardID: String,
        printings: [CatalogPrinting]
    ) async throws -> Bool
    func fetchSetGoals() async throws -> [String: CollectionGoal]
    func fetchSetPreferences() async throws -> [String: SetCollectionPreference]
    func fetchCustomFolders() async throws -> [CustomCollectionFolder]
    func fetchBinderPlans() async throws -> [BinderPlan]
    func fetchCardMetadata(cardID: String) async throws -> CardCollectionMetadata
    func fetchAllCardMetadata() async throws -> [String: CardCollectionMetadata]
    func fetchBackups() async throws -> [CollectionBackup]
    func exportCollection(exportedAt: Date, appVersion: String) async throws -> PortableCollectionDocument
    func previewImport(
        _ document: PortableCollectionDocument,
        mode: CollectionImportMode
    ) async throws -> CollectionImportPreview
    func importCollection(
        _ document: PortableCollectionDocument,
        mode: CollectionImportMode,
        importedAt: Date
    ) async throws
    func createBackup(reason: String, createdAt: Date) async throws -> CollectionBackup
    func previewBackupRestore(id: UUID) async throws -> CollectionImportPreview
    func restoreBackup(
        id: UUID,
        safetyBackupReason: String,
        restoredAt: Date
    ) async throws
    func setGoal(_ goal: CollectionGoal, setID: String, updatedAt: Date) async throws
    func saveSetPreference(_ preference: SetCollectionPreference) async throws
    func deleteSetPreference(setID: String) async throws
    func saveCustomFolder(_ folder: CustomCollectionFolder) async throws
    func deleteCustomFolder(id: UUID) async throws
    func saveBinderPlan(_ plan: BinderPlan) async throws
    func deleteBinderPlan(id: UUID) async throws
    func saveCardMetadata(_ metadata: CardCollectionMetadata) async throws
    func setQuantity(
        _ quantity: Int,
        cardID: String,
        variant: CatalogVariantKind,
        updatedAt: Date
    ) async throws
    func setPrintingQuantity(
        _ quantity: Int,
        cardID: String,
        printingID: String,
        variant: CatalogVariantKind,
        updatedAt: Date
    ) async throws
}

enum CollectionRepositoryError: Error, Equatable {
    case invalidQuantity
    case invalidCustomFolder
    case invalidBinderPlan
    case invalidBackup
    case invalidImport
    case importTooLarge(maximumByteCount: Int)
    case unsupportedImportVersion(Int)
}
