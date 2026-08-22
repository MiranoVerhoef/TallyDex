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
    case master

    var displayName: String {
        switch self {
        case .main: "Main"
        case .master: "Master"
        }
    }

    var explanation: String {
        switch self {
        case .main: "Tap a checkmark to add the card’s standard printing."
        case .master: "Tap a checkmark to choose Normal, Holo, Reverse Holo, and other printings."
        }
    }
}

protocol CollectionRepository: Sendable {
    func fetchEntries(cardID: String) async throws -> [CollectionVariantEntry]
    func fetchOwnedEntries() async throws -> [CollectionVariantEntry]
    func fetchSetGoals() async throws -> [String: CollectionGoal]
    func setGoal(_ goal: CollectionGoal, setID: String, updatedAt: Date) async throws
    func setQuantity(
        _ quantity: Int,
        cardID: String,
        variant: CatalogVariantKind,
        updatedAt: Date
    ) async throws
}

enum CollectionRepositoryError: Error, Equatable {
    case invalidQuantity
}
