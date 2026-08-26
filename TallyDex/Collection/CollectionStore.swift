import Foundation
import Observation

@MainActor
@Observable
final class CollectionStore {
    private(set) var quantitiesByCardID: [String: [CatalogVariantKind: Int]] = [:]
    private(set) var ownedEntries: [CollectionVariantEntry] = []
    private(set) var ownedCardIDs: Set<String> = []
    private(set) var goalsBySetID: [String: CollectionGoal] = [:]
    private(set) var setPreferencesByID: [String: SetCollectionPreference] = [:]
    private(set) var customFolders: [CustomCollectionFolder] = []
    private(set) var cardMetadataByID: [String: CardCollectionMetadata] = [:]
    private(set) var backups: [CollectionBackup] = []
    private(set) var isInitialLoading = true
    private(set) var loadMessage: String?
    private(set) var pendingExternalImport: PreparedCollectionImport?
    private(set) var externalImportError: String?

    @ObservationIgnored private var repository: (any CollectionRepository)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var ownedEntriesByCardID: [String: [CollectionVariantEntry]] = [:]

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
            try await reloadCollectionState()
        } catch {
            loadMessage = "Your saved collection couldn’t be loaded."
        }
        isInitialLoading = false
    }

    func goal(for setID: String) -> CollectionGoal {
        goalsBySetID[setID] ?? CollectionSettings.preferredDefaultGoal
    }

    func preference(for setID: String) -> SetCollectionPreference {
        setPreferencesByID[setID] ?? .defaultPreference(
            setID: setID,
            goal: CollectionSettings.preferredDefaultGoal
        )
    }

    func trackingStatus(for setID: String) -> SetTrackingStatus {
        preference(for: setID).status
    }

    func setGoal(_ goal: CollectionGoal, for setID: String) async throws {
        var preference = preference(for: setID)
        preference = SetCollectionPreference(
            setID: setID,
            status: .collecting,
            goal: goal,
            includedVariants: preference.includedVariants,
            includesSecretCards: preference.includesSecretCards,
            updatedAt: now()
        )
        try await saveSetPreference(preference)
    }

    func saveSetPreference(_ preference: SetCollectionPreference) async throws {
        let preference = preference.applyingCanonicalGoalRules()
        if preference.status == .notCollecting {
            try await resolveRepository().deleteSetPreference(setID: preference.setID)
            setPreferencesByID.removeValue(forKey: preference.setID)
            goalsBySetID.removeValue(forKey: preference.setID)
        } else {
            try await resolveRepository().saveSetPreference(preference)
            setPreferencesByID[preference.setID] = preference
            goalsBySetID[preference.setID] = preference.goal
        }
    }

    @discardableResult
    func createBackup(reason: String) async throws -> CollectionBackup {
        let backup = try await resolveRepository().createBackup(
            reason: reason,
            createdAt: now()
        )
        backups = try await resolveRepository().fetchBackups()
        return backup
    }

    func restoreBackup(_ backup: CollectionBackup) async throws {
        try await resolveRepository().restoreBackup(
            id: backup.id,
            safetyBackupReason: "Before restoring: \(backup.reason)",
            restoredAt: now()
        )
        try await reloadCollectionState()
    }

    func exportDocument() async throws -> PortableCollectionDocument {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return try await resolveRepository().exportCollection(
            exportedAt: now(),
            appVersion: "\(version) (\(build))"
        )
    }

    func prepareImport(data: Data, filename: String) async throws -> PreparedCollectionImport {
        let document: PortableCollectionDocument
        do {
            document = try CollectionTransferCodec.decode(data)
        } catch {
            throw CollectionRepositoryError.invalidImport
        }
        let repository = try resolveRepository()
        async let mergePreview = repository.previewImport(document, mode: .merge)
        async let replacePreview = repository.previewImport(document, mode: .replace)
        return try await PreparedCollectionImport(
            filename: filename,
            document: document,
            mergePreview: mergePreview,
            replacePreview: replacePreview
        )
    }

    func importCollection(_ prepared: PreparedCollectionImport, mode: CollectionImportMode) async throws {
        try await resolveRepository().importCollection(prepared.document, mode: mode, importedAt: now())
        try await reloadCollectionState()
    }

    func openExternalBackup(at url: URL) async {
        externalImportError = nil
        pendingExternalImport = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingExternalImport = try await prepareImport(
                data: data,
                filename: url.lastPathComponent
            )
        } catch CollectionRepositoryError.unsupportedImportVersion(let version) {
            externalImportError = "This backup uses schema version \(version), which this version of TallyDex can’t import."
        } catch {
            externalImportError = "That file is not a valid TallyDex .pokecollection backup. No data was changed."
        }
    }

    func clearExternalImport() {
        pendingExternalImport = nil
        externalImportError = nil
    }

    func cardMetadata(for cardID: String, forceReload: Bool = false) async throws -> CardCollectionMetadata {
        if !forceReload, let metadata = cardMetadataByID[cardID] { return metadata }
        let metadata = try await resolveRepository().fetchCardMetadata(cardID: cardID)
        cardMetadataByID[cardID] = metadata
        return metadata
    }

    func saveCardMetadata(cardID: String, isWishlisted: Bool, notes: String) async throws {
        let metadata = CardCollectionMetadata(
            cardID: cardID,
            isWishlisted: isWishlisted,
            notes: notes,
            updatedAt: now()
        )
        try await resolveRepository().saveCardMetadata(metadata)
        cardMetadataByID[cardID] = metadata
    }

    func saveCustomFolder(_ folder: CustomCollectionFolder) async throws {
        try await resolveRepository().saveCustomFolder(folder)
        customFolders.removeAll { $0.id == folder.id }
        customFolders.append(folder)
        sortCustomFolders()
    }

    func deleteCustomFolder(id: UUID) async throws {
        try await resolveRepository().deleteCustomFolder(id: id)
        customFolders.removeAll { $0.id == id }
    }

    func quantity(cardID: String, variant: CatalogVariantKind) -> Int {
        if let loadedQuantity = quantitiesByCardID[cardID]?[variant] {
            return loadedQuantity
        }
        return ownedEntriesByCardID[cardID]?.first {
            $0.variant == variant
        }?.quantity ?? 0
    }

    func owns(cardID: String) -> Bool {
        ownedCardIDs.contains(cardID)
    }

    func entries(for cardID: String) -> [CollectionVariantEntry] {
        ownedEntriesByCardID[cardID] ?? []
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

        var quantities = quantitiesByCardID[cardID] ?? Dictionary(
            uniqueKeysWithValues: entries(for: cardID).map { ($0.variant, $0.quantity) }
        )
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
        refreshOwnershipIndex(for: cardID)
    }

    func removeAllOwnership(cardID: String) async throws {
        let savedQuantities = try await quantities(for: cardID)
        for variant in savedQuantities.keys where savedQuantities[variant, default: 0] > 0 {
            try await setQuantity(0, cardID: cardID, variant: variant)
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

    private func reloadCollectionState() async throws {
        let repository = try resolveRepository()
        async let entries = repository.fetchOwnedEntries()
        async let preferences = repository.fetchSetPreferences()
        async let folders = repository.fetchCustomFolders()
        async let savedBackups = repository.fetchBackups()
        ownedEntries = try await entries
        rebuildOwnershipIndexes()
        setPreferencesByID = try await preferences
        goalsBySetID = setPreferencesByID.mapValues(\.goal)
        customFolders = try await folders
        backups = try await savedBackups
        quantitiesByCardID.removeAll()
        cardMetadataByID.removeAll()
    }

    private func rebuildOwnershipIndexes() {
        ownedEntriesByCardID = Dictionary(
            grouping: ownedEntries.filter { $0.quantity > 0 },
            by: \.cardID
        )
        ownedCardIDs = Set(ownedEntriesByCardID.keys)
    }

    private func refreshOwnershipIndex(for cardID: String) {
        let entries = ownedEntries.filter { $0.cardID == cardID && $0.quantity > 0 }
        if entries.isEmpty {
            ownedEntriesByCardID.removeValue(forKey: cardID)
            ownedCardIDs.remove(cardID)
        } else {
            ownedEntriesByCardID[cardID] = entries
            ownedCardIDs.insert(cardID)
        }
    }

    private func sortCustomFolders() {
        customFolders.sort {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison == .orderedSame {
                if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.createdAt < $1.createdAt
            }
            return comparison == .orderedAscending
        }
    }
}
