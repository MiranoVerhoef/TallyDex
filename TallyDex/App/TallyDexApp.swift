import SwiftUI

@main
struct TallyDexApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var catalogStore = CatalogStore()
    @State private var artworkCacheStore = ArtworkCacheStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .environment(artworkCacheStore)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start()
                    await artworkCacheStore.prefetch(groups: catalogStore.groups)
                }
        }
    }
}
