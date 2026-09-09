import CryptoKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

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
    let offlineSetID: String?

    init(
        url: URL,
        category: CatalogArtworkCategory,
        offlineSetID: String? = nil
    ) {
        self.url = url
        self.category = category
        self.offlineSetID = offlineSetID
    }
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

/// TCGdex currently omits the image field for several English gallery and vault
/// subsets even though the same assets are available on its CDN under the parent
/// set path. When TCGdex has no image, the same exact set ID and collector number
/// are also checked against Pokémon's official static card assets. A short alias
/// table handles legacy IDs whose official asset directory uses a different but
/// verified code. A card name or nearby collector number is never guessed.
enum TCGdexArtworkFallbacks {
    private static let parentSetBySetID: [String: String] = [
        "swsh4.5sv": "swsh4.5",
        "swsh9tg": "swsh9",
        "swsh10tg": "swsh10",
        "swsh11tg": "swsh11",
        "swsh12tg": "swsh12",
        "swsh12.5gg": "swsh12.5",
    ]

    private static let knownUnavailableCardIDs: Set<String> = [
        "swsh4.5sv-SV028",
        "swsh4.5sv-SV046",
        "swsh4.5sv-SV078",
        "swsh12.5gg-GG48",
        "swsh12.5gg-GG63",
    ]

    private static let knownUnavailableHighResolutionCardIDs: Set<String> = [
        "swsh4.5sv-SV011",
        "swsh4.5sv-SV067",
        "swsh9tg-TG23",
        "swsh10tg-TG19",
        "swsh10tg-TG28",
        "swsh12tg-TG04",
        "swsh12tg-TG24",
        "swsh12tg-TG29",
        "swsh12.5gg-GG06",
        "swsh12.5gg-GG34",
        "swsh12.5gg-GG62",
        "swsh12.5gg-GG64",
        "swsh12.5gg-GG67",
        "swsh12.5gg-GG69",
    ]

    private static let officialAssetCodeBySetID: [String: String] = [
        "2011bw": "MCD11",
        "2012bw": "MCD12",
        "2014xy": "MCD14",
        "2015xy": "MCD15",
        "2016xy": "MCD16",
        "2017sm": "MCD17",
        "2018sm": "MCD18",
        "2019sm": "MCD19",
        "2021swsh": "MCD21",
        "2022swsh": "MCD22",
        "bog": "BP",
        "hgssp": "HSP",
        "sm3.5": "SM35",
        "sm7.5": "SM75",
        "swsh4.5sv": "SWSH45SV",
        "swsh12.5gg": "SWSH12PT5GG",
        "tk-ex-latia": "TK1A",
        "tk-ex-latio": "TK1B",
        "tk-ex-m": "TK2B",
        "tk-ex-p": "TK2A",
    ]

    static func cardImageURLs(
        for card: CatalogCard,
        category: CatalogArtworkCategory
    ) -> [URL] {
        var urls: [URL] = []
        if let imageURL = card.imageURL { urls.append(imageURL) }

        if !knownUnavailableCardIDs.contains(card.id),
           !(category == .cardArtwork
             && knownUnavailableHighResolutionCardIDs.contains(card.id)),
           let parentSetID = parentSetBySetID[card.setID] {
            if let correctedURL = URL(
                string: "https://assets.tcgdex.net/en/swsh/\(parentSetID)/\(card.localID)"
            ) {
                urls.append(correctedURL)
            }
        }

        let assetCode = officialAssetCodeBySetID[card.setID.lowercased()]
            ?? card.setID.uppercased()
        let collectorNumber = Int(card.localID).map(String.init) ?? card.localID
        if !assetCode.isEmpty,
           !collectorNumber.isEmpty,
           let officialURL = URL(
               string: "https://assets.pokemon.com/static-assets/content-assets/cms2/img/cards/web/\(assetCode)/\(assetCode)_EN_\(collectorNumber).png"
           ) {
            urls.append(officialURL)
        }
        return urls.reduce(into: []) { result, url in
            if !result.contains(url) { result.append(url) }
        }
    }
}

struct CatalogOfflineSetStatistics: Equatable, Sendable {
    let fileCount: Int
    let byteCount: Int64

    static let empty = CatalogOfflineSetStatistics(fileCount: 0, byteCount: 0)
}

enum CatalogOfflineSetEstimator {
    static let estimatedBytesPerCard: Int64 = 350_000
    static let estimatedSetArtworkBytes: Int64 = 250_000

    static func estimatedByteCount(cardCount: Int) -> Int64 {
        estimatedSetArtworkBytes + Int64(max(0, cardCount)) * estimatedBytesPerCard
    }
}

enum CatalogArtworkCacheError: Error {
    case invalidResponse
    case emptyData
    case invalidImageData
}

actor CatalogArtworkCache {
    static let shared = CatalogArtworkCache()
    static let maximumByteCount: Int64 = 400 * 1_024 * 1_024

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let offlineRootDirectory: URL
    private let maximumByteCount: Int64
    private let httpClient: any HTTPClient

    init(
        rootDirectory: URL? = nil,
        offlineRootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        maximumByteCount: Int64 = CatalogArtworkCache.maximumByteCount,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.fileManager = fileManager
        self.maximumByteCount = maximumByteCount
        self.httpClient = httpClient
        let automaticCacheBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TallyDexArtwork", isDirectory: true)
        let resolvedRootDirectory = rootDirectory
            ?? automaticCacheBase.appendingPathComponent("v2", isDirectory: true)
        self.rootDirectory = resolvedRootDirectory
        self.offlineRootDirectory = offlineRootDirectory
            ?? (rootDirectory != nil
                ? resolvedRootDirectory.appendingPathComponent("offline-sets", isDirectory: true)
                : fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("TallyDexOfflineSets", isDirectory: true)
                    .appendingPathComponent("v1", isDirectory: true))
        if rootDirectory == nil {
            let legacyAutomaticCache = automaticCacheBase
                .appendingPathComponent("v1", isDirectory: true)
            if fileManager.fileExists(atPath: legacyAutomaticCache.path) {
                try? fileManager.removeItem(at: legacyAutomaticCache)
            }
        }
    }

    static func resolvedAssetURL(_ url: URL, category: CatalogArtworkCategory) -> URL {
        // Some verified fallbacks are already complete PNG URLs rather than the
        // extensionless TCGdex asset base used by the primary API.
        if !url.pathExtension.isEmpty { return url }
        if category == .cardThumbnails {
            return url.appending(path: "low.webp")
        }
        if category == .cardArtwork {
            return url.appending(path: "high.webp")
        }
        let localizedURL: URL
        if category == .expansionSymbols,
           url.host == "assets.tcgdex.net",
           url.path.hasPrefix("/univ/") {
            localizedURL = URL(
                string: url.absoluteString.replacingOccurrences(of: "/univ/", with: "/en/")
            ) ?? url
        } else {
            localizedURL = url
        }
        guard localizedURL.pathExtension.isEmpty else { return localizedURL }
        return localizedURL.appendingPathExtension("png")
    }

    static func resolvedAssetURL(_ url: URL) -> URL {
        resolvedAssetURL(url, category: .setLogos)
    }

    static func isValidImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    static func optimizedImageData(
        _ data: Data,
        category: CatalogArtworkCategory
    ) -> Data {
        let target: (maximumPixelSize: Int, quality: Double)? = switch category {
        case .cardThumbnails: (480, 0.78)
        case .cardArtwork: (1_600, 0.88)
        case .seriesLogos, .setLogos, .expansionSymbols: nil
        }
        guard let target,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: target.maximumPixelSize,
                  ] as CFDictionary
              ) else {
            return data
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: target.quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return data }
        let optimized = output as Data
        return optimized.count < data.count ? optimized : data
    }

    func data(for reference: CatalogArtworkReference) async throws -> Data {
        if let offlineSetID = reference.offlineSetID {
            let offlineURL = offlineFileURL(for: reference, setID: offlineSetID)
            if let offline = validCachedData(at: offlineURL, category: reference.category) {
                return offline
            }
        }

        let fileURL = cachedFileURL(for: reference)
        if let cached = validCachedData(at: fileURL, category: reference.category) {
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: fileURL.path
            )
            return cached
        }

        let sourceURL = Self.resolvedAssetURL(reference.url, category: reference.category)
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let response = try await httpClient.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CatalogArtworkCacheError.invalidResponse
        }
        guard !response.data.isEmpty else { throw CatalogArtworkCacheError.emptyData }
        guard Self.isValidImageData(response.data) else {
            throw CatalogArtworkCacheError.invalidImageData
        }

        let directory = directory(for: reference.category)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let storedData = Self.optimizedImageData(response.data, category: reference.category)
        try storedData.write(to: fileURL, options: .atomic)
        try trimIfNeeded()
        return storedData
    }

    func bestAvailableData(for references: [CatalogArtworkReference]) async throws -> Data {
        let references = references.reduce(into: [CatalogArtworkReference]()) { result, reference in
            if !result.contains(reference) { result.append(reference) }
        }
        var lastError: Error = CatalogArtworkCacheError.invalidResponse
        for reference in references {
            do {
                return try await data(for: reference)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func bestAvailableData(for card: CatalogCard) async throws -> Data {
        try await bestAvailableData(
            for: card.fullArtworkReferences + card.thumbnailArtworkReferences
        )
    }

    @discardableResult
    func storeOffline(
        _ data: Data,
        for reference: CatalogArtworkReference,
        setID: String
    ) throws -> Int64 {
        guard !data.isEmpty else { throw CatalogArtworkCacheError.emptyData }
        guard Self.isValidImageData(data) else {
            throw CatalogArtworkCacheError.invalidImageData
        }
        let storedData = Self.optimizedImageData(data, category: reference.category)
        return try writeOffline(storedData, for: reference, setID: setID)
    }

    @discardableResult
    private func writeOffline(
        _ data: Data,
        for reference: CatalogArtworkReference,
        setID: String
    ) throws -> Int64 {
        let directory = offlineDirectory(for: setID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        let fileURL = offlineFileURL(for: reference, setID: setID)
        try data.write(to: fileURL, options: .atomic)
        return Int64(data.count)
    }

    @discardableResult
    func downloadOffline(
        reference: CatalogArtworkReference,
        setID: String
    ) async throws -> Int64 {
        let offlineURL = offlineFileURL(for: reference, setID: setID)
        if let offline = validCachedData(at: offlineURL, category: reference.category) {
            return Int64(offline.count)
        }

        let cachedURL = cachedFileURL(for: reference)
        if let cached = validCachedData(at: cachedURL, category: reference.category) {
            return try writeOffline(cached, for: reference, setID: setID)
        }

        let sourceURL = Self.resolvedAssetURL(reference.url, category: reference.category)
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let response = try await httpClient.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CatalogArtworkCacheError.invalidResponse
        }
        return try storeOffline(response.data, for: reference, setID: setID)
    }

    func offlineStatistics(setID: String) -> CatalogOfflineSetStatistics {
        let urls = (try? fileManager.contentsOfDirectory(
            at: offlineDirectory(for: setID),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let byteCount = urls.reduce(into: Int64(0)) { total, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return CatalogOfflineSetStatistics(fileCount: urls.count, byteCount: byteCount)
    }

    func removeOfflineSet(setID: String) throws {
        let target = offlineDirectory(for: setID)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func removeAllOfflineSets() throws {
        guard fileManager.fileExists(atPath: offlineRootDirectory.path) else { return }
        try fileManager.removeItem(at: offlineRootDirectory)
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

    func enforceLimit() throws {
        try trimIfNeeded()
    }

    private func directory(for category: CatalogArtworkCategory) -> URL {
        rootDirectory.appendingPathComponent(category.rawValue, isDirectory: true)
    }

    private func offlineDirectory(for setID: String) -> URL {
        let digest = SHA256.hash(data: Data(setID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return offlineRootDirectory.appendingPathComponent(digest, isDirectory: true)
    }

    private func offlineFileURL(
        for reference: CatalogArtworkReference,
        setID: String
    ) -> URL {
        offlineDirectory(for: setID).appendingPathComponent(cacheFileName(for: reference))
    }

    private func cachedFileURL(for reference: CatalogArtworkReference) -> URL {
        directory(for: reference.category).appendingPathComponent(cacheFileName(for: reference))
    }

    private func validCachedData(
        at url: URL,
        category: CatalogArtworkCategory
    ) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard Self.isValidImageData(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return data
    }

    private func cacheFileName(for reference: CatalogArtworkReference) -> String {
        let sourceURL = Self.resolvedAssetURL(reference.url, category: reference.category)
        let digest = SHA256.hash(data: Data(sourceURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileExtension = sourceURL.pathExtension.isEmpty ? "data" : sourceURL.pathExtension
        return "\(reference.category.rawValue)-\(digest).\(fileExtension)"
    }

    private func trimIfNeeded() throws {
        struct CachedFile {
            let url: URL
            let byteCount: Int64
            let modifiedAt: Date
            let isCoreArtwork: Bool
        }

        var files: [CachedFile] = []
        for category in CatalogArtworkCategory.allCases {
            let isCoreArtwork = category == .seriesLogos
                || category == .setLogos
                || category == .expansionSymbols
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory(for: category),
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls {
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                    .contentModificationDateKey,
                ])
                guard values?.isRegularFile == true else { continue }
                files.append(CachedFile(
                    url: url,
                    byteCount: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    isCoreArtwork: isCoreArtwork
                ))
            }
        }

        var totalByteCount = files.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalByteCount > maximumByteCount else { return }
        files.sort {
            if $0.isCoreArtwork != $1.isCoreArtwork {
                return !$0.isCoreArtwork
            }
            return $0.modifiedAt < $1.modifiedAt
        }
        for file in files where totalByteCount > maximumByteCount {
            try fileManager.removeItem(at: file.url)
            totalByteCount -= file.byteCount
        }
    }
}

@MainActor
@Observable
final class ArtworkCacheStore {
    static let offlineSetIDsKey = "catalog.offlineSetIDs"
    static let warmedSetSignaturesKey = "catalog.warmedSetSignatures"
    private static let cacheWarmAlgorithmVersion = "2"

    private(set) var snapshot = CatalogArtworkCacheSnapshot.empty
    private(set) var isPrefetching = false
    private(set) var statusMessage: String?
    private(set) var pinnedSetIDs: Set<String>
    private(set) var offlineStatistics: [String: CatalogOfflineSetStatistics] = [:]
    private(set) var preparingSetIDs: Set<String> = []
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var cacheWarmProgress: [String: Double] = [:]

    @ObservationIgnored private let cache: CatalogArtworkCache
    @ObservationIgnored private let userDefaults: UserDefaults

    init(
        cache: CatalogArtworkCache = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.cache = cache
        self.userDefaults = userDefaults
        self.pinnedSetIDs = Set(
            userDefaults.stringArray(forKey: Self.offlineSetIDsKey) ?? []
        )
    }

    func refreshSnapshot() async {
        try? await cache.enforceLimit()
        snapshot = await cache.snapshot()
        await refreshOfflineStatistics()
    }

    func prefetch(groups: [CatalogSeriesGroup]) async {
        guard !isPrefetching else { return }
        isPrefetching = true
        statusMessage = nil
        defer { isPrefetching = false }

        try? await cache.enforceLimit()
        await cache.prefetch(groups.flatMap(\.artworkReferences))
        snapshot = await cache.snapshot()
        statusMessage = "Catalog logos and symbols are cached."
    }

    func remove(_ category: CatalogArtworkCategory) async {
        do {
            try await cache.remove(category)
            if category == .cardThumbnails {
                clearWarmedSetSignatures()
            }
            snapshot = await cache.snapshot()
            statusMessage = "Cleared \(category.title.lowercased())."
        } catch {
            statusMessage = "That cache could not be cleared."
        }
    }

    func removeAll() async {
        do {
            try await cache.removeAll()
            clearWarmedSetSignatures()
            snapshot = await cache.snapshot()
            statusMessage = "Cleared all artwork caches."
        } catch {
            statusMessage = "The artwork cache could not be cleared."
        }
    }

    func isPinned(setID: String) -> Bool {
        pinnedSetIDs.contains(setID)
    }

    func isPreparing(setID: String) -> Bool {
        preparingSetIDs.contains(setID)
    }

    func beginPreparing(setID: String) {
        preparingSetIDs.insert(setID)
        statusMessage = nil
    }

    func warmImagesIfNeeded(set: CatalogSet, cards: [CatalogCard]) async {
        guard !cards.isEmpty, cacheWarmProgress[set.id] == nil else { return }
        let signature = cacheWarmSignature(setID: set.id, cards: cards)
        let storedSignatures = userDefaults.dictionary(
            forKey: Self.warmedSetSignaturesKey
        ) as? [String: String] ?? [:]
        guard storedSignatures[set.id] != signature else { return }

        let requestGroups = cards.map(\.thumbnailArtworkReferences).filter { !$0.isEmpty }
        guard !requestGroups.isEmpty else {
            persistWarmedSetSignature(signature, setID: set.id)
            return
        }

        cacheWarmProgress[set.id] = 0
        defer { cacheWarmProgress.removeValue(forKey: set.id) }
        let cache = cache
        var completed = 0
        var succeeded = 0

        for batchStart in stride(from: 0, to: requestGroups.count, by: 6) {
            guard !Task.isCancelled else { return }
            let batchEnd = min(batchStart + 6, requestGroups.count)
            let batch = Array(requestGroups[batchStart..<batchEnd])
            let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for alternatives in batch {
                    group.addTask {
                        (try? await cache.bestAvailableData(for: alternatives)) != nil
                    }
                }
                var values: [Bool] = []
                for await value in group { values.append(value) }
                return values
            }
            completed += results.count
            succeeded += results.filter { $0 }.count
            cacheWarmProgress[set.id] = Double(completed) / Double(requestGroups.count)
        }

        // Do not remember a fully failed attempt, because it most likely happened
        // while the device was offline. Exact unavailable images are still handled
        // honestly by their normal on-demand placeholders.
        if succeeded > 0 {
            persistWarmedSetSignature(signature, setID: set.id)
        }
        snapshot = await cache.snapshot()
    }

    func preparationFailed(setID: String, setName: String) {
        preparingSetIDs.remove(setID)
        statusMessage = "\(setName) couldn’t be prepared for offline use."
    }

    func keepOffline(set: CatalogSet, cards: [CatalogCard]) async {
        let requestGroups = (
            set.offlineArtworkReferences.map { [$0] }
                + cards.flatMap(\.offlineArtworkReferenceGroups)
        ).reduce(into: [[CatalogArtworkReference]]()) { result, group in
            if !group.isEmpty, !result.contains(group) { result.append(group) }
        }
        guard !cards.isEmpty, !requestGroups.isEmpty else {
            preparationFailed(setID: set.id, setName: set.name)
            return
        }

        preparingSetIDs.remove(set.id)
        downloadProgress[set.id] = 0
        statusMessage = nil
        let cache = cache
        var succeeded = 0
        var failed = 0

        for batchStart in stride(from: 0, to: requestGroups.count, by: 6) {
            let batchEnd = min(batchStart + 6, requestGroups.count)
            let batch = Array(requestGroups[batchStart..<batchEnd])
            let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for alternatives in batch {
                    group.addTask {
                        for reference in alternatives {
                            do {
                                _ = try await cache.downloadOffline(
                                    reference: reference,
                                    setID: set.id
                                )
                                return true
                            } catch {
                                continue
                            }
                        }
                        return false
                    }
                }
                var values: [Bool] = []
                for await value in group { values.append(value) }
                return values
            }
            succeeded += results.filter { $0 }.count
            failed += results.filter { !$0 }.count
            downloadProgress[set.id] = Double(succeeded + failed) / Double(requestGroups.count)
        }

        downloadProgress.removeValue(forKey: set.id)
        if failed == 0 {
            pinnedSetIDs.insert(set.id)
            persistPinnedSetIDs()
            offlineStatistics[set.id] = await cache.offlineStatistics(setID: set.id)
            statusMessage = "\(set.name) is available offline."
        } else {
            try? await cache.removeOfflineSet(setID: set.id)
            offlineStatistics.removeValue(forKey: set.id)
            statusMessage = "\(set.name) wasn’t fully downloaded. Check your connection and retry."
        }
    }

    func removeOfflineSet(setID: String, setName: String) async {
        do {
            try await cache.removeOfflineSet(setID: setID)
            pinnedSetIDs.remove(setID)
            offlineStatistics.removeValue(forKey: setID)
            persistPinnedSetIDs()
            statusMessage = "Removed the offline copy of \(setName)."
        } catch {
            statusMessage = "The offline copy of \(setName) couldn’t be removed."
        }
    }

    func removeAllOfflineSets() async {
        do {
            try await cache.removeAllOfflineSets()
            pinnedSetIDs.removeAll()
            offlineStatistics.removeAll()
            persistPinnedSetIDs()
            statusMessage = "Removed every offline set."
        } catch {
            statusMessage = "Offline sets couldn’t be removed."
        }
    }

    private func refreshOfflineStatistics() async {
        var values: [String: CatalogOfflineSetStatistics] = [:]
        for setID in pinnedSetIDs {
            values[setID] = await cache.offlineStatistics(setID: setID)
        }
        offlineStatistics = values
    }

    private func persistPinnedSetIDs() {
        userDefaults.set(pinnedSetIDs.sorted(), forKey: Self.offlineSetIDsKey)
    }

    private func cacheWarmSignature(setID: String, cards: [CatalogCard]) -> String {
        let identity = cards
            .sorted { $0.id < $1.id }
            .map { card in
                let sources = card.thumbnailArtworkReferences
                    .map { CatalogArtworkCache.resolvedAssetURL($0.url, category: $0.category).absoluteString }
                    .joined(separator: ",")
                return "\(card.id)=\(sources)"
            }
            .joined(separator: "|")
        let payload = "\(Self.cacheWarmAlgorithmVersion)|\(setID)|\(identity)"
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func persistWarmedSetSignature(_ signature: String, setID: String) {
        var signatures = userDefaults.dictionary(
            forKey: Self.warmedSetSignaturesKey
        ) as? [String: String] ?? [:]
        signatures[setID] = signature
        userDefaults.set(signatures, forKey: Self.warmedSetSignaturesKey)
    }

    private func clearWarmedSetSignatures() {
        userDefaults.removeObject(forKey: Self.warmedSetSignaturesKey)
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
        logoURL.map { .init(url: $0, category: .setLogos, offlineSetID: id) }
    }

    var offlineArtworkReferences: [CatalogArtworkReference] {
        [
            logoURL.map { .init(url: $0, category: .setLogos, offlineSetID: id) },
            symbolURL.map { .init(url: $0, category: .expansionSymbols, offlineSetID: id) },
        ].compactMap { $0 }
    }
}

extension CatalogCard {
    var thumbnailArtworkReferences: [CatalogArtworkReference] {
        TCGdexArtworkFallbacks.cardImageURLs(for: self, category: .cardThumbnails).map {
            .init(url: $0, category: .cardThumbnails, offlineSetID: setID)
        }
    }

    var thumbnailArtworkReference: CatalogArtworkReference? {
        thumbnailArtworkReferences.first
    }

    var fullArtworkReferences: [CatalogArtworkReference] {
        let fullReferences = TCGdexArtworkFallbacks.cardImageURLs(
            for: self,
            category: .cardArtwork
        ).map { url in
            CatalogArtworkReference(url: url, category: .cardArtwork, offlineSetID: setID)
        }
        return fullReferences.isEmpty ? thumbnailArtworkReferences : fullReferences
    }

    var fullArtworkReference: CatalogArtworkReference? {
        fullArtworkReferences.first
    }

    var offlineArtworkReferences: [CatalogArtworkReference] {
        [thumbnailArtworkReference, fullArtworkReference].compactMap { $0 }
    }

    var offlineArtworkReferenceGroups: [[CatalogArtworkReference]] {
        [thumbnailArtworkReferences, fullArtworkReferences]
    }
}
