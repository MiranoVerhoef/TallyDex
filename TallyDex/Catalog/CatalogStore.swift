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

    @ObservationIgnored private let provider: any CatalogProvider
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var repository: (any CatalogRepository)?
    @ObservationIgnored private var hasStarted = false

    private static let lastCatalogRefreshKey = "catalog.lastRefresh"
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
            if try await repository.fetchSeries().isEmpty {
                let snapshot = try BundledCatalogLoader(bundle: bundle).load()
                try await repository.replaceCatalog(snapshot.series)
            }

            try await loadCachedCatalog(from: repository)
            isInitialLoading = false

            lastUpdated = try await repository.metadataDate(forKey: Self.lastCatalogRefreshKey)
            if needsRefresh(lastUpdated) {
                await refresh()
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
            let snapshots = try await fetchRemoteCatalog()
            try await repository.replaceCatalog(snapshots)
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
        let sets = try await repository.fetchSets(seriesID: nil)
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
            return snapshots.sorted {
                order[$0.series.id, default: .max] < order[$1.series.id, default: .max]
            }
        }
    }

    private func needsRefresh(_ lastUpdated: Date?) -> Bool {
        guard let lastUpdated else { return true }
        return now().timeIntervalSince(lastUpdated) >= Self.staleInterval
    }
}
