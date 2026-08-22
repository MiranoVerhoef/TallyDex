import Foundation

struct CollectionVariantEntry: Equatable, Identifiable, Sendable {
    let cardID: String
    let variant: CatalogVariantKind
    let quantity: Int
    let updatedAt: Date

    var id: String { "\(cardID)|\(variant.rawValue)" }
}

enum CollectionGoal: String, Codable, CaseIterable, Sendable {
    case main
    case complete
    case holoChase
    case master
    case custom

    var displayName: String {
        switch self {
        case .main: "Main"
        case .complete: "Complete"
        case .holoChase: "Holo Chase"
        case .master: "Master"
        case .custom: "Custom"
        }
    }

    var explanation: String {
        switch self {
        case .main: "Collect one standard printing of every card in the official numbering."
        case .complete: "Collect one printing of every main and secret-numbered card."
        case .holoChase: "Collect the selected Holo and Reverse Holo printings."
        case .master: "Collect every known printing of every card."
        case .custom: "Choose which numbered cards and printing types count."
        }
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

    static func defaultPreference(setID: String, updatedAt: Date = .distantPast) -> SetCollectionPreference {
        SetCollectionPreference(
            setID: setID,
            status: .notCollecting,
            goal: .main,
            includedVariants: [.normal],
            includesSecretCards: false,
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
        let owned = Dictionary(grouping: ownedEntries.filter { $0.quantity > 0 }, by: \.cardID)
        var requiredSlots = 0
        var completedSlots = 0

        for card in cards where includes(card: card, set: set, preference: preference) {
            let knownVariants = availableVariants[card.id] ?? []
            let requiredVariants = variants(
                for: preference,
                knownVariants: knownVariants
            )
            if requiredVariants.isEmpty { continue }

            requiredSlots += requiredVariants.count
            let ownedVariants = Set((owned[card.id] ?? []).map(\.variant))
            completedSlots += requiredVariants.intersection(ownedVariants).count
        }
        return CollectionProgress(completedSlots: completedSlots, requiredSlots: requiredSlots)
    }

    static func includes(
        card: CatalogCard,
        set: CatalogSet,
        preference: SetCollectionPreference
    ) -> Bool {
        switch preference.goal {
        case .main:
            return isMainNumbered(card, in: set)
        case .complete, .holoChase, .master:
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
        case .main, .complete:
            let preferenceOrder: [CatalogVariantKind] = [
                .normal, .holo, .reverseHolo, .firstEdition, .watermarkedPromo,
            ]
            return [preferenceOrder.first(where: knownVariants.contains) ?? .normal]
        case .holoChase:
            let holoVariants: Set<CatalogVariantKind> = [.holo, .reverseHolo]
            return knownVariants
                .intersection(preference.includedVariants)
                .intersection(holoVariants)
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

protocol CollectionRepository: Sendable {
    func fetchEntries(cardID: String) async throws -> [CollectionVariantEntry]
    func fetchOwnedEntries() async throws -> [CollectionVariantEntry]
    func fetchSetGoals() async throws -> [String: CollectionGoal]
    func fetchSetPreferences() async throws -> [String: SetCollectionPreference]
    func fetchCustomFolders() async throws -> [CustomCollectionFolder]
    func fetchCardMetadata(cardID: String) async throws -> CardCollectionMetadata
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
}
