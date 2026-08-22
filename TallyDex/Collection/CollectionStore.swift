import Foundation
import Observation

@MainActor
@Observable
final class CollectionStore {
    private(set) var quantitiesByCardID: [String: [CatalogVariantKind: Int]] = [:]
    private(set) var ownedEntries: [CollectionVariantEntry] = []
    private(set) var goalsBySetID: [String: CollectionGoal] = [:]
    private(set) var isInitialLoading = true
    private(set) var loadMessage: String?

    @ObservationIgnored private var repository: (any CollectionRepository)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var hasStarted = false

    init(
        repository: (any CollectionRepository)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.now = now
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let repository = try resolveRepository()
            async let entries = repository.fetchOwnedEntries()
            async let goals = repository.fetchSetGoals()
            ownedEntries = try await entries
            goalsBySetID = try await goals
        } catch {
            loadMessage = "Your saved collection couldn’t be loaded."
        }
        isInitialLoading = false
    }

    func goal(for setID: String) -> CollectionGoal {
        goalsBySetID[setID] ?? .main
    }

    func setGoal(_ goal: CollectionGoal, for setID: String) async throws {
        try await resolveRepository().setGoal(goal, setID: setID, updatedAt: now())
        goalsBySetID[setID] = goal
    }

    func quantity(cardID: String, variant: CatalogVariantKind) -> Int {
        if let loadedQuantity = quantitiesByCardID[cardID]?[variant] {
            return loadedQuantity
        }
        return ownedEntries.first {
            $0.cardID == cardID && $0.variant == variant
        }?.quantity ?? 0
    }

    func owns(cardID: String) -> Bool {
        ownedEntries.contains { $0.cardID == cardID && $0.quantity > 0 }
    }

    func quantities(for cardID: String, forceReload: Bool = false) async throws -> [CatalogVariantKind: Int] {
        if !forceReload, let quantities = quantitiesByCardID[cardID] {
            return quantities
        }

        let entries = try await resolveRepository().fetchEntries(cardID: cardID)
        let quantities = Dictionary(uniqueKeysWithValues: entries.map { ($0.variant, $0.quantity) })
        quantitiesByCardID[cardID] = quantities
        return quantities
    }

    func setQuantity(
        _ quantity: Int,
        cardID: String,
        variant: CatalogVariantKind
    ) async throws {
        let updatedAt = now()
        try await resolveRepository().setQuantity(
            quantity,
            cardID: cardID,
            variant: variant,
            updatedAt: updatedAt
        )

        var quantities = quantitiesByCardID[cardID] ?? [:]
        if quantity == 0 {
            quantities.removeValue(forKey: variant)
        } else {
            quantities[variant] = quantity
        }
        quantitiesByCardID[cardID] = quantities

        ownedEntries.removeAll { $0.cardID == cardID && $0.variant == variant }
        if quantity > 0 {
            ownedEntries.append(
                CollectionVariantEntry(
                    cardID: cardID,
                    variant: variant,
                    quantity: quantity,
                    updatedAt: updatedAt
                )
            )
        }
        ownedEntries.sort {
            if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func resolveRepository() throws -> any CollectionRepository {
        if let repository {
            return repository
        }
        let repository = GRDBCollectionRepository(
            database: try CollectionDatabase.applicationDatabase()
        )
        self.repository = repository
        return repository
    }
}
