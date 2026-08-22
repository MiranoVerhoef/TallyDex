import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case sets
    case search
    case collection
    case settings
}

struct RootTabView: View {
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
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .environment(CollectionStore())
}
