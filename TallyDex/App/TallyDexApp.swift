import SwiftUI

enum BrowserSharingSettings {
    static let allowWhileBackgroundedKey = "browserSharing.allowWhileBackgrounded"
    static let allowWhileBackgroundedDefault = false
}

@main
struct TallyDexApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(BrowserSharingSettings.allowWhileBackgroundedKey)
    private var allowBrowserSharingWhileBackgrounded = BrowserSharingSettings.allowWhileBackgroundedDefault
    @State private var catalogStore: CatalogStore
    @State private var collectionStore: CollectionStore
    @State private var accessStore: AccessStore
    @State private var automaticBackup: AutomaticCollectionBackup
    @State private var artworkCacheStore = ArtworkCacheStore()
    @State private var localCollectionSharing = LocalCollectionSharingController()
    @State private var appNavigation = AppNavigationStore()
    @State private var priceUpdater = AutomaticPriceUpdater()
    @AppStorage(AutomaticPriceUpdateSettings.enabledKey) private var automaticPrices = true
    @AppStorage(AutomaticPriceUpdateSettings.backgroundKey) private var backgroundPrices = false
    @AppStorage(AppExperienceSettings.introductionCompletedKey) private var introductionCompleted = false

    init() {
#if DEBUG
        if let fixture = ReliabilityUITestFixture.current {
            let accessStore = AccessStore(anchorStore: KeychainTrialAnchorStore(namespace: fixture.id.uuidString))
            _accessStore = State(initialValue: accessStore)
            let catalogStore = fixture.makeCatalogStore()
            _catalogStore = State(initialValue: catalogStore)
            _collectionStore = State(initialValue: fixture.makeCollectionStore(catalogStore: catalogStore))
            _automaticBackup = State(initialValue: AutomaticCollectionBackup(defaults: fixture.defaults))
            return
        }
#endif
        let accessStore = AccessStore()
        _accessStore = State(initialValue: accessStore)
        let catalogStore = CatalogStore()
        _catalogStore = State(initialValue: catalogStore)
        _collectionStore = State(initialValue: CollectionStore(accessStore: accessStore, catalogStore: catalogStore))
        _automaticBackup = State(initialValue: AutomaticCollectionBackup())
    }

    private var preferencesDefaults: UserDefaults {
#if DEBUG
        ReliabilityUITestFixture.current?.defaults ?? .standard
#else
        .standard
#endif
    }

    private var isUITesting: Bool {
#if DEBUG
        ReliabilityUITestFixture.current != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#else
        false
#endif
    }

    private var priceUpdateContext: AutomaticPriceUpdateContext {
        AutomaticPriceUpdateContext(
            active: scenePhase == .active, enabled: automaticPrices,
            ready: !isUITesting && !catalogStore.isInitialLoading && !collectionStore.isInitialLoading
                && introductionCompleted,
            ownedIDs: collectionStore.ownedCardIDs,
            collectingSetIDs: Set(collectionStore.setPreferencesByID.values.filter { $0.status == .collecting }.map(\.setID))
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .defaultAppStorage(preferencesDefaults)
                .environment(catalogStore)
                .environment(collectionStore)
                .environment(automaticBackup)
                .environment(accessStore)
                .environment(artworkCacheStore)
                .environment(localCollectionSharing)
                .environment(appNavigation)
                .environment(priceUpdater)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start(allowRemoteRefresh: scenePhase == .active)
#if DEBUG
                    if let fixture = ReliabilityUITestFixture.current {
                        await fixture.prepare(collectionStore, catalogStore: catalogStore)
                        collectionStore.installAccessStoreAfterFixtureSetup(accessStore)
                        return
                    }
#endif
                    guard scenePhase == .active else { return }
                    await artworkCacheStore.prefetch(groups: catalogStore.groups)
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-BrowserEditorTesting") {
                        await collectionStore.start()
                        await localCollectionSharing.start(
                            catalogStore: catalogStore,
                            collectionStore: collectionStore
                        )
                    }
#endif
                }
                .task {
#if DEBUG
                    if ReliabilityUITestFixture.current != nil { return }
#endif
                    await collectionStore.start()
                }
                .task(id: collectionStore.isInitialLoading ? nil : automaticBackup.observationID) {
                    guard !collectionStore.isInitialLoading, collectionStore.loadMessage == nil else { return }
                    await automaticBackup.watch(collectionStore)
                }
                .task(id: priceUpdateContext) {
                    let context = priceUpdateContext
                    guard context.active, context.ready, context.enabled else { return }
                    while !Task.isCancelled {
                        await priceUpdater.run(catalog: catalogStore, ownedIDs: context.ownedIDs,
                            collectingSetIDs: context.collectingSetIDs, background: false,
                            defaults: preferencesDefaults)
                        do { try await Task.sleep(for: .seconds(120)) } catch { return }
                    }
                }
                .onChange(of: automaticPrices) { _, _ in schedulePriceUpdates() }
                .onChange(of: backgroundPrices) { _, _ in schedulePriceUpdates() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        if newPhase == .background {
                            schedulePriceUpdates()
                            automaticBackup.flushPending(collectionStore)
                        }
                        if !allowBrowserSharingWhileBackgrounded, localCollectionSharing.isRunning {
                            localCollectionSharing.stop()
                        }
                        return
                    }
                    accessStore.tick()
                    automaticBackup.requestSave(collectionStore)
                    Task {
                        await catalogStore.refreshIfNeeded()
#if DEBUG
                        if ReliabilityUITestFixture.current != nil { return }
#endif
                        guard scenePhase == .active else { return }
                        await artworkCacheStore.prefetch(groups: catalogStore.groups)
                    }
                }
                .onOpenURL { url in
                    if let cardID = CardDeepLink.cardID(from: url) {
                        appNavigation.open(cardID: cardID)
                    } else if let cardID = SharedCardDocument.cardID(from: url) {
                        appNavigation.open(cardID: cardID)
                    } else if url.isFileURL {
                        Task { await collectionStore.openExternalBackup(at: url) }
                    }
                }
        }
        .backgroundTask(.appRefresh(AutomaticPriceUpdateSettings.taskIdentifier)) {
            await refreshPricesInBackground()
        }
    }

    private func schedulePriceUpdates() {
        guard !isUITesting else { return }
        AutomaticPriceUpdater.schedule(defaults: preferencesDefaults)
    }

    @MainActor
    private func refreshPricesInBackground() async {
        guard !isUITesting,
              preferencesDefaults.bool(forKey: AppExperienceSettings.introductionCompletedKey),
              preferencesDefaults.bool(forKey: AutomaticPriceUpdateSettings.backgroundKey) else { return }
        defer { schedulePriceUpdates() }
        await collectionStore.start()
        // A simultaneous scene startup may already be loading the local store.
        while collectionStore.isInitialLoading && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        await priceUpdater.run(catalog: catalogStore, ownedIDs: collectionStore.ownedCardIDs,
            collectingSetIDs: Set(collectionStore.setPreferencesByID.values.filter { $0.status == .collecting }.map(\.setID)),
            background: true, defaults: preferencesDefaults)
    }
}
