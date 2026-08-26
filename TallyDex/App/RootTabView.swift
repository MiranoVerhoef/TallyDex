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
            Tab(value: .sets) {
                SetsView()
            } label: {
                Label("Sets", systemImage: "square.grid.2x2")
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }

            Tab(value: .search) {
                SearchView()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }

            Tab(value: .collection) {
                CollectionView()
            } label: {
                Label("Collection", systemImage: "rectangle.stack")
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }

            Tab(value: .settings) {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .dynamicTypeSize(...DynamicTypeSize.large)
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
        .environment(LocalCollectionSharingController())
}
