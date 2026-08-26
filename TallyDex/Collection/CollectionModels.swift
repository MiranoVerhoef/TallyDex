import Foundation

struct CollectionVariantEntry: Equatable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let quantity: Int
    let updatedAt: Date

    var id: String { "\(cardID)|\(variant.rawValue)" }
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
    static func progress(
        cards: [CatalogCard],
        set: CatalogSet,
        preference: SetCollectionPreference,
        availableVariants: [String: Set<CatalogVariantKind>],
        ownedEntries: [CollectionVariantEntry]
    ) -> CollectionProgress {
        combined(
            progressByCardID(
                cards: cards,
                set: set,
                preference: preference,
                availableVariants: availableVariants,
                ownedEntries: ownedEntries
            )
        )
    }

    static func progressByCardID(
        cards: [CatalogCard],
        set: CatalogSet,
        preference: SetCollectionPreference,
        availableVariants: [String: Set<CatalogVariantKind>],
        ownedEntries: [CollectionVariantEntry]
    ) -> [String: CollectionProgress] {
        let owned = Dictionary(grouping: ownedEntries.filter { $0.quantity > 0 }, by: \.cardID)
        var result: [String: CollectionProgress] = [:]
        result.reserveCapacity(cards.count)

        for card in cards where includes(card: card, set: set, preference: preference) {
            let knownVariants = availableVariants[card.id] ?? []
            let ownedVariants = Set((owned[card.id] ?? []).map(\.variant))

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
            result[card.id] = CollectionProgress(
                completedSlots: requiredVariants.intersection(ownedVariants).count,
                requiredSlots: requiredVariants.count
            )
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

struct CustomCollectionFolder: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let cardNameQuery: String
    let displayMode: CustomCollectionFolderDisplayMode
    let createdAt: Date
    let updatedAt: Date
}

struct CollectionBackup: Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let reason: String
}

protocol CollectionRepository: Sendable {
    func fetchEntries(cardID: String) async throws -> [CollectionVariantEntry]
    func fetchOwnedEntries() async throws -> [CollectionVariantEntry]
    func fetchSetGoals() async throws -> [String: CollectionGoal]
    func fetchSetPreferences() async throws -> [String: SetCollectionPreference]
    func fetchCustomFolders() async throws -> [CustomCollectionFolder]
    func fetchCardMetadata(cardID: String) async throws -> CardCollectionMetadata
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
}

enum CollectionRepositoryError: Error, Equatable {
    case invalidQuantity
    case invalidCustomFolder
    case invalidBackup
    case invalidImport
    case unsupportedImportVersion(Int)
}
