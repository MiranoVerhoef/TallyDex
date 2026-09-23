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
    @State private var artworkCacheStore = ArtworkCacheStore()
    @State private var localCollectionSharing = LocalCollectionSharingController()
    @State private var appNavigation = AppNavigationStore()

    init() {
#if DEBUG
        if let fixture = ReliabilityUITestFixture.current {
            let accessStore = AccessStore(anchorStore: KeychainTrialAnchorStore(namespace: fixture.id.uuidString))
            _accessStore = State(initialValue: accessStore)
            _catalogStore = State(initialValue: fixture.makeCatalogStore())
            _collectionStore = State(initialValue: fixture.makeCollectionStore())
            return
        }
#endif
        let accessStore = AccessStore()
        _accessStore = State(initialValue: accessStore)
        _catalogStore = State(initialValue: CatalogStore())
        _collectionStore = State(initialValue: CollectionStore(accessStore: accessStore))
    }

    private var preferencesDefaults: UserDefaults {
#if DEBUG
        ReliabilityUITestFixture.current?.defaults ?? .standard
#else
        .standard
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .defaultAppStorage(preferencesDefaults)
                .environment(catalogStore)
                .environment(collectionStore)
                .environment(accessStore)
                .environment(artworkCacheStore)
                .environment(localCollectionSharing)
                .environment(appNavigation)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start()
#if DEBUG
                    if let fixture = ReliabilityUITestFixture.current {
                        await fixture.prepare(collectionStore)
                        collectionStore.installAccessStoreAfterFixtureSetup(accessStore)
                        return
                    }
#endif
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
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        if !allowBrowserSharingWhileBackgrounded, localCollectionSharing.isRunning {
                            localCollectionSharing.stop()
                        }
                        return
                    }
                    accessStore.tick()
                    Task {
                        await catalogStore.refreshIfNeeded()
#if DEBUG
                        if ReliabilityUITestFixture.current != nil { return }
#endif
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
    }
}
