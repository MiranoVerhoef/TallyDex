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
    @State private var catalogStore = CatalogStore()
    @State private var collectionStore = CollectionStore()
    @State private var artworkCacheStore = ArtworkCacheStore()
    @State private var localCollectionSharing = LocalCollectionSharingController()
    @State private var appNavigation = AppNavigationStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(collectionStore)
                .environment(artworkCacheStore)
                .environment(localCollectionSharing)
                .environment(appNavigation)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start()
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
                    await collectionStore.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        if !allowBrowserSharingWhileBackgrounded, localCollectionSharing.isRunning {
                            localCollectionSharing.stop()
                        }
                        return
                    }
                    Task {
                        await catalogStore.refreshIfNeeded()
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
