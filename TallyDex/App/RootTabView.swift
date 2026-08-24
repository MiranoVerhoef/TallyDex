import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case sets
    case search
    case collection
    case settings
}

struct RootTabView: View {
    @Environment(CollectionStore.self) private var collectionStore
    @State private var selection: AppTab = .sets

    var body: some View {
        TabView(selection: $selection) {
            Tab("Sets", systemImage: "square.grid.2x2", value: .sets) {
                SetsView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }

            Tab("Collection", systemImage: "rectangle.stack", value: .collection) {
                CollectionView()
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .onChange(of: collectionStore.pendingExternalImport?.id) { _, id in
            if id != nil { selection = .settings }
        }
        .sheet(
            item: Binding(
                get: { collectionStore.pendingExternalImport },
                set: { if $0 == nil { collectionStore.clearExternalImport() } }
            )
        ) { prepared in
            CollectionImportPreviewView(prepared: prepared) { _ in
                collectionStore.clearExternalImport()
            }
        }
        .alert(
            "Couldn’t Open Backup",
            isPresented: Binding(
                get: { collectionStore.externalImportError != nil },
                set: { if !$0 { collectionStore.clearExternalImport() } }
            )
        ) {
            Button("OK") { collectionStore.clearExternalImport() }
        } message: {
            Text(collectionStore.externalImportError ?? "The backup couldn’t be opened.")
        }
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .environment(CollectionStore())
        .environment(ArtworkCacheStore())
}
