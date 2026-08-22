import CryptoKit
import Foundation
import Observation

enum CatalogArtworkCategory: String, CaseIterable, Identifiable, Sendable {
    case seriesLogos = "series-logos"
    case setLogos = "set-logos"
    case expansionSymbols = "expansion-symbols"
    case cardThumbnails = "card-thumbnails"
    case cardArtwork = "card-artwork"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seriesLogos: "Series logos"
        case .setLogos: "Set logos"
        case .expansionSymbols: "Expansion symbols"
        case .cardThumbnails: "Card thumbnails"
        case .cardArtwork: "Full card artwork"
        }
    }

    var systemImage: String {
        switch self {
        case .seriesLogos: "rectangle.stack"
        case .setLogos: "photo.on.rectangle"
        case .expansionSymbols: "seal"
        case .cardThumbnails: "rectangle.grid.3x2"
        case .cardArtwork: "rectangle.portrait"
        }
    }
}

struct CatalogArtworkReference: Hashable, Sendable {
    let url: URL
    let category: CatalogArtworkCategory
}

struct CatalogArtworkCacheStatistics: Equatable, Sendable {
    let fileCount: Int
    let byteCount: Int64

    static let empty = CatalogArtworkCacheStatistics(fileCount: 0, byteCount: 0)
}

struct CatalogArtworkCacheSnapshot: Equatable, Sendable {
    let statistics: [CatalogArtworkCategory: CatalogArtworkCacheStatistics]

    static let empty = CatalogArtworkCacheSnapshot(statistics: [:])

    func statistics(for category: CatalogArtworkCategory) -> CatalogArtworkCacheStatistics {
        statistics[category] ?? .empty
    }

    var totalFileCount: Int {
        statistics.values.reduce(0) { $0 + $1.fileCount }
    }

    var totalByteCount: Int64 {
        statistics.values.reduce(0) { $0 + $1.byteCount }
    }
}

enum CatalogArtworkCacheError: Error {
    case invalidResponse
    case emptyData
}

actor CatalogArtworkCache {
    static let shared = CatalogArtworkCache()

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TallyDexArtwork", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
    }

    static func resolvedAssetURL(_ url: URL, category: CatalogArtworkCategory) -> URL {
        if category == .cardThumbnails {
            return url.appending(path: "low.webp")
        }
        if category == .cardArtwork {
            return url.appending(path: "high.webp")
        }
        guard url.pathExtension.isEmpty else { return url }
        return url.appendingPathExtension("png")
    }

    static func resolvedAssetURL(_ url: URL) -> URL {
        resolvedAssetURL(url, category: .setLogos)
    }

    func data(for reference: CatalogArtworkReference) async throws -> Data {
        let fileURL = cachedFileURL(for: reference)
        if let cached = try? Data(contentsOf: fileURL), !cached.isEmpty {
            return cached
        }

        let sourceURL = Self.resolvedAssetURL(reference.url, category: reference.category)
        let (data, response) = try await URLSession.shared.data(from: sourceURL)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw CatalogArtworkCacheError.invalidResponse
        }
        guard !data.isEmpty else { throw CatalogArtworkCacheError.emptyData }

        let directory = directory(for: reference.category)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return data
    }

    func prefetch(_ references: [CatalogArtworkReference]) async {
        let uniqueReferences = Array(Set(references))
        let batchSize = 8

        for batchStart in stride(from: 0, to: uniqueReferences.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, uniqueReferences.count)
            let batch = uniqueReferences[batchStart..<batchEnd]
            await withTaskGroup(of: Void.self) { group in
                for reference in batch {
                    group.addTask {
                        _ = try? await self.data(for: reference)
                    }
                }
            }
        }
    }

    func snapshot() -> CatalogArtworkCacheSnapshot {
        var result: [CatalogArtworkCategory: CatalogArtworkCacheStatistics] = [:]

        for category in CatalogArtworkCategory.allCases {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory(for: category),
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let byteCount = urls.reduce(into: Int64(0)) { total, url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
            result[category] = CatalogArtworkCacheStatistics(
                fileCount: urls.count,
                byteCount: byteCount
            )
        }

        return CatalogArtworkCacheSnapshot(statistics: result)
    }

    func remove(_ category: CatalogArtworkCategory) throws {
        let target = directory(for: category)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.removeItem(at: rootDirectory)
    }

    private func directory(for category: CatalogArtworkCategory) -> URL {
        rootDirectory.appendingPathComponent(category.rawValue, isDirectory: true)
    }

    private func cachedFileURL(for reference: CatalogArtworkReference) -> URL {
        let sourceURL = Self.resolvedAssetURL(reference.url, category: reference.category)
        let digest = SHA256.hash(data: Data(sourceURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileExtension = sourceURL.pathExtension.isEmpty ? "data" : sourceURL.pathExtension
        return directory(for: reference.category)
            .appendingPathComponent(digest)
            .appendingPathExtension(fileExtension)
    }
}

@MainActor
@Observable
final class ArtworkCacheStore {
    private(set) var snapshot = CatalogArtworkCacheSnapshot.empty
    private(set) var isPrefetching = false
    private(set) var statusMessage: String?

    @ObservationIgnored private let cache: CatalogArtworkCache

    init(cache: CatalogArtworkCache = .shared) {
        self.cache = cache
    }

    func refreshSnapshot() async {
        snapshot = await cache.snapshot()
    }

    func prefetch(groups: [CatalogSeriesGroup]) async {
        guard !isPrefetching else { return }
        isPrefetching = true
        statusMessage = nil
        defer { isPrefetching = false }

        let references = groups.flatMap(\.artworkReferences)
        await cache.prefetch(references)
        snapshot = await cache.snapshot()
        statusMessage = "Artwork is available offline."
    }

    func remove(_ category: CatalogArtworkCategory) async {
        do {
            try await cache.remove(category)
            snapshot = await cache.snapshot()
            statusMessage = "Cleared \(category.title.lowercased())."
        } catch {
            statusMessage = "That cache could not be cleared."
        }
    }

    func removeAll() async {
        do {
            try await cache.removeAll()
            snapshot = await cache.snapshot()
            statusMessage = "Cleared all artwork caches."
        } catch {
            statusMessage = "The artwork cache could not be cleared."
        }
    }
}

extension CatalogSeriesGroup {
    var artworkReferences: [CatalogArtworkReference] {
        var references: [CatalogArtworkReference] = []
        if let logoURL = series.logoURL {
            references.append(.init(url: logoURL, category: .seriesLogos))
        }
        for set in sets {
            if let logoURL = set.logoURL {
                references.append(.init(url: logoURL, category: .setLogos))
            }
            if let symbolURL = set.symbolURL {
                references.append(.init(url: symbolURL, category: .expansionSymbols))
            }
        }
        return references
    }

    var preferredArtworkReference: CatalogArtworkReference? {
        series.logoURL.map { .init(url: $0, category: .seriesLogos) }
    }
}

extension CatalogSet {
    var preferredArtworkReference: CatalogArtworkReference? {
        logoURL.map { .init(url: $0, category: .setLogos) }
    }
}

extension CatalogCard {
    var thumbnailArtworkReference: CatalogArtworkReference? {
        imageURL.map { .init(url: $0, category: .cardThumbnails) }
    }

    var fullArtworkReference: CatalogArtworkReference? {
        imageURL.map { .init(url: $0, category: .cardArtwork) }
    }
}
