import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case sets
    case search
    case camera
    case collection
    case settings
}

@MainActor
@Observable
final class AppNavigationStore {
    var requestedCardID: String?

    func open(cardID: String) {
        requestedCardID = cardID
    }

    func clearCardRequest() {
        requestedCardID = nil
    }
}

enum CardDeepLink {
    static func url(cardID: String) -> URL {
        var components = URLComponents()
        components.scheme = "tallydex"
        components.host = "card"
        components.path = "/\(cardID)"
        return components.url!
    }

    static func cardID(from url: URL) -> String? {
        if url.scheme?.lowercased() == "tallydex", url.host?.lowercased() == "card" {
            let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return value.isEmpty ? nil : value.removingPercentEncoding ?? value
        }
        return nil
    }
}

struct RootTabView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(AppNavigationStore.self) private var appNavigation
    @State private var selection: AppTab = .sets
    @State private var deepLinkedCard: CatalogCard?
    @State private var deepLinkError: String?

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CameraTesting") {
            _selection = State(initialValue: .camera)
        }
#endif
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: .sets) {
                SetsView()
            } label: {
                Label("Sets", systemImage: "square.grid.2x2")
            }

            Tab(value: .search) {
                SearchView()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }

            Tab(value: .camera) {
                CardScannerView()
            } label: {
                Label("Camera", systemImage: "camera.viewfinder")
            }

            Tab(value: .collection) {
                CollectionView()
            } label: {
                Label("Collection", systemImage: "rectangle.stack")
            }

            Tab(value: .settings) {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .onChange(of: collectionStore.pendingExternalImport?.id) { _, id in
            if id != nil { selection = .settings }
        }
        .task(id: appNavigation.requestedCardID) {
            guard let cardID = appNavigation.requestedCardID else { return }
            selection = .search
            do {
                await catalogStore.start()
                var card: CatalogCard?
                for attempt in 0..<24 {
                    card = try await catalogStore.searchResults(cardIDs: [cardID]).first?.card
                    if card != nil { break }
                    if attempt < 23 {
                        try await Task.sleep(for: .milliseconds(250))
                    }
                }
                guard let card else {
                    deepLinkError = "That card is not in the local catalog yet. Let TallyDex finish updating and try the link again."
                    appNavigation.clearCardRequest()
                    return
                }
                deepLinkedCard = card
                appNavigation.clearCardRequest()
            } catch {
                deepLinkError = "TallyDex couldn’t open that shared card."
                appNavigation.clearCardRequest()
            }
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
        .sheet(item: $deepLinkedCard) { card in
            NavigationStack {
                CatalogCardDetailView(card: card)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { deepLinkedCard = nil }
                        }
                    }
            }
        }
        .alert(
            "Couldn’t Open Card",
            isPresented: Binding(
                get: { deepLinkError != nil },
                set: { if !$0 { deepLinkError = nil } }
            )
        ) {
            Button("OK") { deepLinkError = nil }
        } message: {
            Text(deepLinkError ?? "The shared card couldn’t be opened.")
        }
    }
}

#Preview {
    RootTabView()
        .environment(CatalogStore())
        .environment(CollectionStore())
        .environment(ArtworkCacheStore())
        .environment(LocalCollectionSharingController())
        .environment(AppNavigationStore())
}
