import Foundation
import Observation

@MainActor
@Observable
final class CollectionStore {
    private(set) var quantitiesByCardID: [String: [CatalogVariantKind: Int]] = [:]
    private(set) var ownedEntries: [CollectionVariantEntry] = []
    private(set) var broadOwnedEntries: [CollectionVariantEntry] = []
    private(set) var exactOwnedEntries: [CollectionPrintingEntry] = []
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
            let repository = try resolveRepository()
            try await repository.prepareExactOwnershipMigration(createdAt: now())
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
        guard data.count <= CollectionTransferCodec.maximumImportByteCount else {
            throw CollectionRepositoryError.importTooLarge(
                maximumByteCount: CollectionTransferCodec.maximumImportByteCount
            )
        }
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
            let data = try CollectionTransferCodec.readImportData(at: url)
            pendingExternalImport = try await prepareImport(
                data: data,
                filename: url.lastPathComponent
            )
        } catch CollectionRepositoryError.importTooLarge(let maximumByteCount) {
            let limit = ByteCountFormatter.string(
                fromByteCount: Int64(maximumByteCount),
                countStyle: .file
            )
            externalImportError = "That backup is larger than the \(limit) safety limit. No data was changed."
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

    func printingEntries(for cardID: String) -> [CollectionPrintingEntry] {
        exactOwnedEntries.filter { $0.cardID == cardID }
    }

    func printingQuantity(cardID: String, printingID: String) -> Int {
        exactOwnedEntries.first {
            $0.cardID == cardID && $0.printingID == printingID
        }?.quantity ?? 0
    }

    func quantities(for cardID: String, forceReload: Bool = false) async throws -> [CatalogVariantKind: Int] {
        if !forceReload, let quantities = quantitiesByCardID[cardID] {
            return quantities
        }

        let repository = try resolveRepository()
        async let broad = repository.fetchEntries(cardID: cardID)
        async let exact = repository.fetchPrintingEntries(cardID: cardID)
        let quantities = Self.aggregateQuantities(broad: try await broad, exact: try await exact)
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

        broadOwnedEntries.removeAll { $0.cardID == cardID && $0.variant == variant }
        if quantity > 0 {
            broadOwnedEntries.append(
                CollectionVariantEntry(
                    cardID: cardID,
                    variant: variant,
                    quantity: quantity,
                    updatedAt: updatedAt
                )
            )
        }
        rebuildAggregatedOwnership()
    }

    func setPrintingQuantity(
        _ quantity: Int,
        cardID: String,
        printing: CatalogPrinting
    ) async throws {
        guard let variant = printing.kind else { return }
        let updatedAt = now()
        let repository = try resolveRepository()
        try await repository.prepareExactOwnershipMigration(createdAt: updatedAt)
        try await repository.setPrintingQuantity(
            quantity,
            cardID: cardID,
            printingID: printing.providerID,
            variant: variant,
            updatedAt: updatedAt
        )
        try await reloadOwnership(for: cardID)
    }

    func setPreferredQuantity(
        _ quantity: Int,
        cardID: String,
        variant: CatalogVariantKind,
        printings: [CatalogPrinting]
    ) async throws {
        let matching = printings.filter { $0.kind == variant }
        if matching.count == 1, let printing = matching.first {
            try await reconcileExactOwnership(cardID: cardID, printings: printings)
            try await setPrintingQuantity(quantity, cardID: cardID, printing: printing)
        } else {
            try await setQuantity(quantity, cardID: cardID, variant: variant)
        }
    }

    /// Safely upgrades broad ownership only when TCGdex supplies one and only
    /// one exact record for that broad printing type. Ambiguous ownership stays
    /// broad until the collector chooses an exact printing.
    func reconcileExactOwnership(cardID: String, printings: [CatalogPrinting]) async throws {
        guard !printings.isEmpty else { return }
        let repository = try resolveRepository()
        try await repository.prepareExactOwnershipMigration(createdAt: now())
        let changed = try await repository.reconcileExactOwnership(
            cardID: cardID,
            printings: printings
        )
        if changed {
            try await reloadOwnership(for: cardID)
            backups = try await repository.fetchBackups()
        }
    }

    func removeAllOwnership(cardID: String) async throws {
        let repository = try resolveRepository()
        let broad = try await repository.fetchEntries(cardID: cardID)
        let exact = try await repository.fetchPrintingEntries(cardID: cardID)
        for entry in broad where entry.quantity > 0 {
            try await repository.setQuantity(0, cardID: cardID, variant: entry.variant, updatedAt: now())
        }
        for entry in exact where entry.quantity > 0 {
            try await repository.setPrintingQuantity(
                0,
                cardID: cardID,
                printingID: entry.printingID,
                variant: entry.variant,
                updatedAt: now()
            )
        }
        try await reloadOwnership(for: cardID)
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
        async let printingEntries = repository.fetchOwnedPrintingEntries()
        async let preferences = repository.fetchSetPreferences()
        async let folders = repository.fetchCustomFolders()
        async let metadata = repository.fetchAllCardMetadata()
        async let savedBackups = repository.fetchBackups()
        broadOwnedEntries = try await entries
        exactOwnedEntries = try await printingEntries
        rebuildAggregatedOwnership()
        setPreferencesByID = try await preferences
        goalsBySetID = setPreferencesByID.mapValues(\.goal)
        customFolders = try await folders
        cardMetadataByID = try await metadata
        backups = try await savedBackups
        quantitiesByCardID.removeAll()
    }

    private func rebuildAggregatedOwnership() {
        var grouped: [String: CollectionVariantEntry] = [:]
        for entry in broadOwnedEntries {
            grouped[entry.id] = entry
        }
        for entry in exactOwnedEntries {
            let key = "\(entry.cardID)|\(entry.variant.rawValue)"
            if let saved = grouped[key] {
                grouped[key] = CollectionVariantEntry(
                    cardID: entry.cardID,
                    variant: entry.variant,
                    quantity: saved.quantity + entry.quantity,
                    updatedAt: max(saved.updatedAt, entry.updatedAt)
                )
            } else {
                grouped[key] = CollectionVariantEntry(
                    cardID: entry.cardID,
                    variant: entry.variant,
                    quantity: entry.quantity,
                    updatedAt: entry.updatedAt
                )
            }
        }
        ownedEntries = grouped.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
            return $0.updatedAt > $1.updatedAt
        }
        ownedEntriesByCardID = Dictionary(
            grouping: ownedEntries.filter { $0.quantity > 0 },
            by: \.cardID
        )
        ownedCardIDs = Set(ownedEntriesByCardID.keys)
        quantitiesByCardID = Dictionary(uniqueKeysWithValues: ownedEntriesByCardID.map { cardID, entries in
            (cardID, Dictionary(uniqueKeysWithValues: entries.map { ($0.variant, $0.quantity) }))
        })
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

    private func reloadOwnership(for cardID: String) async throws {
        let repository = try resolveRepository()
        let broadForCard = try await repository.fetchEntries(cardID: cardID)
        let exactForCard = try await repository.fetchPrintingEntries(cardID: cardID)
        broadOwnedEntries.removeAll { $0.cardID == cardID }
        broadOwnedEntries.append(contentsOf: broadForCard.filter { $0.quantity > 0 })
        exactOwnedEntries.removeAll { $0.cardID == cardID }
        exactOwnedEntries.append(contentsOf: exactForCard.filter { $0.quantity > 0 })
        rebuildAggregatedOwnership()
    }

    private static func aggregateQuantities(
        broad: [CollectionVariantEntry],
        exact: [CollectionPrintingEntry]
    ) -> [CatalogVariantKind: Int] {
        var result: [CatalogVariantKind: Int] = [:]
        for entry in broad { result[entry.variant, default: 0] += entry.quantity }
        for entry in exact { result[entry.variant, default: 0] += entry.quantity }
        return result
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
