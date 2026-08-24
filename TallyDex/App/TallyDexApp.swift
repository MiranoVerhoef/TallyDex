import SwiftUI

@main
struct TallyDexApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var catalogStore = CatalogStore()
    @State private var collectionStore = CollectionStore()
    @State private var artworkCacheStore = ArtworkCacheStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(collectionStore)
                .environment(artworkCacheStore)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start()
                    await artworkCacheStore.prefetch(groups: catalogStore.groups)
                }
                .task {
                    await collectionStore.start()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await catalogStore.refreshIfNeeded()
                    await artworkCacheStore.prefetch(groups: catalogStore.groups)
                }
                .onOpenURL { url in
                    Task { await collectionStore.openExternalBackup(at: url) }
                }
        }
    }
}
