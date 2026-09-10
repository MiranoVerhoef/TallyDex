import Foundation

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
                        .filter { $0.variant == variant && requiredIDs.contains($0.printingID) }
                        .map(\.printingID)
                ).count
                // An old broad check represents one real but unspecified copy.
                // It may satisfy one slot, never every possible exact printing.
                let fallbackCompleted = broadOwnedForCard.contains { $0.variant == variant } ? 1 : 0
                completedSlots += min(exactOptions.count, exactCompleted + fallbackCompleted)
            }
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

struct PokemonRuleChoice: Equatable, Identifiable, Sendable {
    let name: String
    let matchingCardCount: Int
    let exampleCard: CatalogCard
    let exampleSetName: String

    var id: String { name.lowercased() }
}

enum PokemonRuleSearch {
    static func choices(
        from results: [CatalogCardSearchResult],
        query: String
    ) -> [PokemonRuleChoice] {
        let normalizedQuery = normalized(query)
        var grouped: [String: (name: String, matches: [CatalogCardSearchResult])] = [:]
        for result in results {
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
            guard let example = group.matches.first else { return nil }
            return PokemonRuleChoice(
                name: group.name,
                matchingCardCount: group.matches.count,
                exampleCard: example.card,
                exampleSetName: example.setName
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
        self.displayMode = displayMode
        self.iconName = CollectionFolderIcon.validated(iconName).rawValue
        self.coverCardID = coverCardID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    case invalidBackup
    case invalidImport
    case importTooLarge(maximumByteCount: Int)
    case unsupportedImportVersion(Int)
}
