import Foundation
import Observation

struct BundledCatalogSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let language: String
    let series: [CatalogSeriesSnapshot]
}

enum BundledCatalogError: Error, Equatable {
    case missingResource
    case unsupportedSnapshot
}

struct BundledCatalogLoader: Sendable {
    let bundle: Bundle

    func load() throws -> BundledCatalogSnapshot {
        guard let url = bundle.url(forResource: "catalog-en", withExtension: "json") else {
            throw BundledCatalogError.missingResource
        }

        let snapshot = try JSONDecoder().decode(
            BundledCatalogSnapshot.self,
            from: Data(contentsOf: url)
        )
        guard snapshot.schemaVersion == 1, snapshot.language == "en" else {
            throw BundledCatalogError.unsupportedSnapshot
        }
        return snapshot
    }
}

@MainActor
@Observable
final class CatalogStore {
    private(set) var groups: [CatalogSeriesGroup] = []
    private(set) var isInitialLoading = true
    private(set) var isRefreshing = false
    private(set) var refreshMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isPreparingSearchIndex = false
    private(set) var searchIndexMessage: String?
    private(set) var searchIndexUpdated: Date?

    @ObservationIgnored private let provider: any CatalogProvider
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var repository: (any CatalogRepository)?
    @ObservationIgnored private var bundledSetsByID: [String: CatalogSet] = [:]
    @ObservationIgnored private var hasStarted = false

    private static let lastCatalogRefreshKey = "catalog.lastRefresh"
    private static let lastSearchIndexRefreshKey = "catalog.searchIndex.lastRefresh"
    private static let staleInterval: TimeInterval = 6 * 60 * 60

    init(
        provider: any CatalogProvider = TCGdexClient(),
        repository: (any CatalogRepository)? = nil,
        bundle: Bundle = .main,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.repository = repository
        self.bundle = bundle
        self.now = now
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            let repository = try resolveRepository()
            let bundledSnapshot = try? BundledCatalogLoader(bundle: bundle).load()
            if let bundledSnapshot {
                bundledSetsByID = Dictionary(
                    uniqueKeysWithValues: bundledSnapshot.series
                        .flatMap(\.sets)
                        .map { ($0.id, $0) }
                )
            }

            if try await repository.fetchSeries().isEmpty {
                guard let snapshot = bundledSnapshot else {
                    throw BundledCatalogError.missingResource
                }
                try await repository.replaceCatalog(snapshot.series)
            }

            try await loadCachedCatalog(from: repository)
            isInitialLoading = false

            lastUpdated = try await repository.metadataDate(forKey: Self.lastCatalogRefreshKey)
            searchIndexUpdated = try await repository.metadataDate(
                forKey: Self.lastSearchIndexRefreshKey
            )
            if needsRefresh(lastUpdated) {
                await refresh()
            } else if needsRefresh(searchIndexUpdated) {
                await refreshSearchIndex(in: repository)
            }
        } catch {
            isInitialLoading = false
            refreshMessage = "The catalog could not be loaded. Pull down to try again."
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }

        do {
            let repository = try resolveRepository()
            let downloadedSetIDs = try await repository.fetchDownloadedSetIDs()
            let snapshots = try await fetchRemoteCatalog()
            try await repository.replaceCatalog(snapshots)
            await refreshDownloadedSets(downloadedSetIDs, in: repository)
            await refreshSearchIndex(in: repository)
            let refreshDate = now()
            try await repository.setMetadataDate(refreshDate, forKey: Self.lastCatalogRefreshKey)
            try await loadCachedCatalog(from: repository)
            lastUpdated = refreshDate
        } catch {
            refreshMessage = groups.isEmpty
                ? "The catalog could not be downloaded. Pull down to try again."
                : "You’re viewing the saved catalog because refresh is unavailable."
        }
    }

    /// Re-checks the six-hour catalog window without forcing a network request.
    /// Called whenever the app becomes active so newly announced sets and artwork
    /// appear even when TallyDex has remained installed and suspended for days.
    func refreshIfNeeded() async {
        guard hasStarted else { return }
        if needsRefresh(lastUpdated) {
            await refresh()
        } else if needsRefresh(searchIndexUpdated), let repository = try? resolveRepository() {
            await refreshSearchIndex(in: repository)
        }
    }

    func cards(for set: CatalogSet, forceRefresh: Bool = false) async throws -> [CatalogCard] {
        let repository = try resolveRepository()
        let cachedCards = try await repository.fetchCards(setID: set.id)
        let refreshKey = setRefreshKey(set.id)
        let setLastUpdated = try await repository.metadataDate(forKey: refreshKey)

        guard forceRefresh || cachedCards.isEmpty || needsRefresh(setLastUpdated) else {
            return cachedCards
        }

        do {
            let snapshot = try await provider.fetchSet(id: set.id)
            try await repository.replaceSet(snapshot)
            try await repository.setMetadataDate(now(), forKey: refreshKey)
            try await loadCachedCatalog(from: repository)
            return try await repository.fetchCards(setID: set.id)
        } catch {
            guard !cachedCards.isEmpty else { throw error }
            return cachedCards
        }
    }

    func searchCards(query: String) async throws -> [CatalogCardSearchResult] {
        try await resolveRepository().searchCards(query: query)
    }

    func searchResults(cardIDs: [String]) async throws -> [CatalogCardSearchResult] {
        try await resolveRepository().fetchSearchResults(cardIDs: cardIDs)
    }

    func details(for card: CatalogCard) async throws -> CatalogCardSnapshot {
        let repository = try resolveRepository()
        do {
            let snapshot = try await provider.fetchCard(id: card.id)
            try await repository.replaceCard(snapshot)
            return snapshot
        } catch {
            let variants = try await repository.fetchVariants(cardID: card.id)
            if card.category != nil || card.illustrator != nil || card.rarity != nil || !variants.isEmpty {
                return CatalogCardSnapshot(card: card, variants: variants)
            }
            throw error
        }
    }

    private func resolveRepository() throws -> any CatalogRepository {
        if let repository {
            return repository
        }
        let repository = GRDBCatalogRepository(database: try CatalogDatabase.applicationDatabase())
        self.repository = repository
        return repository
    }

    private func loadCachedCatalog(from repository: any CatalogRepository) async throws {
        let series = try await repository.fetchSeries()
        let cachedSets = try await repository.fetchSets(seriesID: nil).map { set in
            set.fillingMissingMetadata(from: bundledSetsByID[set.id])
        }
        let cachedIDs = Set(cachedSets.map(\.id))
        let cachedNames = Set(cachedSets.map { $0.name.lowercased() })
        let announcedSets = bundledSetsByID.values
            .filter { set in
                set.isUpcoming(relativeTo: now())
                    && !cachedIDs.contains(set.id)
                    && !cachedNames.contains(set.name.lowercased())
            }
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        let sets = announcedSets + cachedSets
        let setsBySeries = Dictionary(grouping: sets, by: \.seriesID)
        groups = series.map { item in
            CatalogSeriesGroup(series: item, sets: setsBySeries[item.id] ?? [])
        }
    }

    private func fetchRemoteCatalog() async throws -> [CatalogSeriesSnapshot] {
        let provider = self.provider
        let index = try await provider.fetchSeriesIndex()
        let physicalSeries = index.filter { $0.id != "tcgp" }.reversed()
        let order = Dictionary(
            uniqueKeysWithValues: physicalSeries.enumerated().map { ($0.element.id, $0.offset) }
        )

        return try await withThrowingTaskGroup(of: CatalogSeriesSnapshot.self) { group in
            for series in physicalSeries {
                group.addTask {
                    try await provider.fetchSeries(id: series.id)
                }
            }

            var snapshots: [CatalogSeriesSnapshot] = []
            for try await snapshot in group {
                let newestSetsFirst = CatalogSeriesSnapshot(
                    series: snapshot.series,
                    sets: Array(snapshot.sets.reversed())
                )
                snapshots.append(newestSetsFirst)
            }
            let sortedSnapshots = snapshots.sorted {
                order[$0.series.id, default: .max] < order[$1.series.id, default: .max]
            }
            return await enrichSetMetadata(in: sortedSnapshots)
        }
    }

    private func refreshDownloadedSets(
        _ setIDs: [String],
        in repository: any CatalogRepository
    ) async {
        guard !setIDs.isEmpty else { return }
        let provider = self.provider
        let snapshots = await withTaskGroup(of: CatalogSetSnapshot?.self) { group in
            for id in setIDs {
                group.addTask { try? await provider.fetchSet(id: id) }
            }

            var result: [CatalogSetSnapshot] = []
            for await snapshot in group {
                if let snapshot { result.append(snapshot) }
            }
            return result
        }

        for snapshot in snapshots {
            try? await repository.replaceSet(snapshot)
            try? await repository.setMetadataDate(now(), forKey: setRefreshKey(snapshot.set.id))
        }
    }

    private func refreshSearchIndex(in repository: any CatalogRepository) async {
        guard !isPreparingSearchIndex else { return }
        isPreparingSearchIndex = true
        searchIndexMessage = nil
        defer { isPreparingSearchIndex = false }

        do {
            let remoteCards = try await provider.fetchCardIndex()
            let validSetIDs = Set(try await repository.fetchSets(seriesID: nil).map(\.id))
            let searchableCards = remoteCards.filter { validSetIDs.contains($0.setID) }
            try await repository.replaceSearchIndex(searchableCards)
            let refreshDate = now()
            try await repository.setMetadataDate(
                refreshDate,
                forKey: Self.lastSearchIndexRefreshKey
            )
            searchIndexUpdated = refreshDate
        } catch {
            searchIndexMessage = "The complete search catalog couldn’t be updated. It will retry automatically."
        }
    }

    private func enrichSetMetadata(
        in snapshots: [CatalogSeriesSnapshot]
    ) async -> [CatalogSeriesSnapshot] {
        let cachedSetsByID = Dictionary(
            uniqueKeysWithValues: groups.flatMap(\.sets).map { ($0.id, $0) }
        )
        let fallbackSetsByID = bundledSetsByID.merging(cachedSetsByID) { _, cached in cached }
        let initiallyEnriched = snapshots.map { snapshot in
            CatalogSeriesSnapshot(
                series: snapshot.series,
                sets: snapshot.sets.map { set in
                    set.fillingMissingMetadata(from: fallbackSetsByID[set.id])
                }
            )
        }
        let missingIDs = initiallyEnriched
            .flatMap(\.sets)
            .filter { $0.abbreviation == nil }
            .map(\.id)

        guard !missingIDs.isEmpty else { return initiallyEnriched }

        let provider = self.provider
        let detailedSets = await withTaskGroup(of: CatalogSet?.self) { group in
            for id in missingIDs {
                group.addTask {
                    try? await provider.fetchSet(id: id).set
                }
            }

            var sets: [CatalogSet] = []
            for await set in group {
                if let set { sets.append(set) }
            }
            return Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        }

        return initiallyEnriched.map { snapshot in
            CatalogSeriesSnapshot(
                series: snapshot.series,
                sets: snapshot.sets.map { set in
                    set.fillingMissingMetadata(from: detailedSets[set.id])
                }
            )
        }
    }

    private func needsRefresh(_ lastUpdated: Date?) -> Bool {
        guard let lastUpdated else { return true }
        return now().timeIntervalSince(lastUpdated) >= Self.staleInterval
    }

    private func setRefreshKey(_ setID: String) -> String {
        "catalog.set.\(setID).lastRefresh"
    }
}
