import SwiftUI

@main
struct TallyDexApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var catalogStore = CatalogStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(catalogStore)
                .preferredColorScheme(AppAppearance.resolve(appearance).colorScheme)
                .task {
                    await catalogStore.start()
                }
        }
    }
}
