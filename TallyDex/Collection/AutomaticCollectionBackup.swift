import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AutomaticCollectionBackup {
    struct Destination: Codable, Sendable {
        let id: UUID
        let bookmark: Data
        let name: String

        init(folder: URL) throws {
            guard folder.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            defer { folder.stopAccessingSecurityScopedResource() }
            id = UUID()
            bookmark = try folder.bookmarkData(options: .minimalBookmark)
            name = folder.lastPathComponent
        }
    }

    struct SavedBackup: Codable, Sendable {
        let fingerprint: String
        let filename: String
        let date: Date
    }

    static let versionLimits = 1...50
    private static let settingsKey = "collection.automaticBackup."

    private(set) var destination: Destination?
    private(set) var isEnabled: Bool
    private(set) var keepVersions: Int
    private(set) var isSaving = false
    private(set) var message: String?
    var lastSavedAt: Date? { lastSave?.date }
    var observationID: UUID? { isEnabled ? destination?.id : nil }

    private var lastSave: SavedBackup?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let filePrefix: String
    @ObservationIgnored private var scheduledSave: Task<Void, Never>?
    @ObservationIgnored private var firstPendingChange: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let key = Self.settingsKey
        let storedDestination = defaults.data(forKey: key + "destination")
            .flatMap { try? JSONDecoder().decode(Destination.self, from: $0) }
        destination = storedDestination
        isEnabled = storedDestination != nil && defaults.bool(forKey: key + "enabled")
        let savedLimit = defaults.integer(forKey: key + "keepVersions")
        keepVersions = Self.versionLimits.contains(savedLimit) ? savedLimit : 10
        lastSave = defaults.data(forKey: key + "lastSave")
            .flatMap { try? JSONDecoder().decode(SavedBackup.self, from: $0) }
        let fileID = defaults.string(forKey: key + "fileID").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(fileID.uuidString, forKey: key + "fileID")
        let fileTag = fileID.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        filePrefix = "TallyDex-Auto-\(fileTag)-"
    }

    func chooseFolder(_ selection: Destination, collection: CollectionStore) async throws {
        guard !isSaving, !collection.isInitialLoading, collection.loadMessage == nil else {
            throw CocoaError(.fileWriteUnknown)
        }
        scheduledSave?.cancel()
        scheduledSave = nil
        isSaving = true
        message = nil
        defer {
            isSaving = false
            if firstPendingChange != nil { requestSave(collection) }
        }

        let encodedSelection = try JSONEncoder().encode(selection)
        // Verify the saved folder permission with a real backup before enabling it.
        let (saved, rotationFailed) = try await writeBackup(collection, to: selection, previous: nil)
        defaults.set(encodedSelection, forKey: Self.settingsKey + "destination")
        destination = selection
        setEnabled(true)
        recordSave(saved, rotationFailed: rotationFailed)
    }

    func setEnabled(_ enabled: Bool) {
        guard !enabled || destination != nil else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.settingsKey + "enabled")
        message = nil
        if !enabled {
            scheduledSave?.cancel()
            scheduledSave = nil
            firstPendingChange = nil
        }
    }

    func setKeepVersions(_ count: Int, collection: CollectionStore) {
        guard Self.versionLimits.contains(count), count != keepVersions else { return }
        keepVersions = count
        defaults.set(count, forKey: Self.settingsKey + "keepVersions")
        requestSave(collection)
    }

    func watch(_ collection: CollectionStore) async {
        guard let id = observationID else { return }
        do {
            for try await _ in try collection.backupChanges() {
                guard !Task.isCancelled, observationID == id else { return }
                requestSave(collection)
            }
        } catch {
            guard !Task.isCancelled, observationID == id else { return }
            message = "TallyDex couldn’t monitor collection changes for backup."
        }
    }

    func requestSave(_ collection: CollectionStore, immediate: Bool = false) {
        guard isEnabled, !collection.isInitialLoading, collection.loadMessage == nil else { return }
        let now = clock.now
        if firstPendingChange == nil { firstPendingChange = now }
        guard !isSaving, let firstPendingChange else { return }
        scheduledSave?.cancel()
        // Wait for edits to settle, with a cap for continuous editing.
        let deadline = immediate ? now : min(now + .seconds(15), firstPendingChange + .seconds(120))
        scheduledSave = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.save(collection)
        }
    }

    func flushPending(_ collection: CollectionStore) {
        if firstPendingChange != nil { requestSave(collection, immediate: true) }
    }

    private func save(_ collection: CollectionStore) async {
        guard let id = observationID, let destination else { return }
        scheduledSave = nil
        firstPendingChange = nil
        isSaving = true
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Collection backup") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            isSaving = false
            if firstPendingChange != nil { requestSave(collection) }
        }

        do {
            let (saved, rotationFailed) = try await writeBackup(collection, to: destination, previous: lastSave)
            guard observationID == id else { return }
            recordSave(saved, rotationFailed: rotationFailed)
        } catch {
            guard observationID == id else { return }
            message = "Backup couldn’t be saved. Check the folder in Files or choose another folder."
        }
    }

    private func writeBackup(
        _ collection: CollectionStore, to destination: Destination, previous: SavedBackup?
    ) async throws -> (SavedBackup, Bool) {
        let document = try await collection.exportDocument()
        let limit = keepVersions
        let prefix = filePrefix
        return try await Task.detached(priority: .utility) {
            try Self.write(document, to: destination, previous: previous, limit: limit, prefix: prefix)
        }.value
    }

    private func recordSave(_ backup: SavedBackup, rotationFailed: Bool) {
        setLastSave(backup)
        message = rotationFailed ? "Backup saved. Some older versions couldn’t be removed." : nil
    }

    private func setLastSave(_ backup: SavedBackup?) {
        lastSave = backup
        defaults.set(backup.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.settingsKey + "lastSave")
    }

    private nonisolated static func write(
        _ document: PortableCollectionDocument, to destination: Destination,
        previous: SavedBackup?, limit: Int, prefix: String
    ) throws -> (SavedBackup, Bool) {
        var stale = false
        let folder = try URL(resolvingBookmarkData: destination.bookmark, options: .withoutUI,
                             relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        return try writeVersions(document, in: folder, previous: previous, limit: limit, prefix: prefix)
    }

    nonisolated static func writeVersions(
        _ document: PortableCollectionDocument, in folder: URL,
        previous: SavedBackup?, limit: Int, prefix: String
    ) throws -> (SavedBackup, Bool) {
        let stableData = try CollectionTransferCodec.encode(document.withExportDate(Date(timeIntervalSince1970: 0)))
        let fingerprint = SHA256.hash(data: stableData).description
        let manager = FileManager.default
        var coordinationError: NSError?
        var result: Result<(SavedBackup, Bool), Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinated in
            result = Result {
                let saved: SavedBackup
                if let previous, previous.fingerprint == fingerprint,
                   manager.fileExists(atPath: coordinated.appendingPathComponent(previous.filename).path) {
                    saved = previous
                } else {
                    let data = try CollectionTransferCodec.encode(document)
                    guard data.count <= CollectionTransferCodec.maximumImportByteCount else {
                        throw CollectionRepositoryError.importTooLarge(
                            maximumByteCount: CollectionTransferCodec.maximumImportByteCount
                        )
                    }
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let stamp = formatter.string(from: document.exportedAt).replacingOccurrences(of: ":", with: "")
                    let filename = "\(prefix)\(stamp)-\(UUID().uuidString.prefix(8)).pokecollection"
                    try data.write(to: coordinated.appendingPathComponent(filename), options: .atomic)
                    saved = SavedBackup(fingerprint: fingerprint, filename: filename, date: document.exportedAt)
                }
                do {
                    try rotate(in: coordinated, prefix: prefix, keeping: limit, newest: saved.filename)
                    return (saved, false)
                } catch {
                    return (saved, true)
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private nonisolated static func rotate(in folder: URL, prefix: String, keeping limit: Int, newest: String) throws {
        let manager = FileManager.default
        let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        let versions = files.compactMap { url -> URL? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.lastPathComponent != newest, url.pathExtension == "pokecollection",
                  name.hasPrefix(prefix),
                  name.dropFirst(prefix.count).range(of: #"^\d{4}-\d{2}-\d{2}T\d{6}\.\d{3}Z-[0-9A-F]{8}$"#,
                                                    options: .regularExpression) != nil,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            return url
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for version in versions.dropFirst(limit - 1) {
            try manager.removeItem(at: version)
        }
    }
}
