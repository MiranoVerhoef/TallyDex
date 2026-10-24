import SwiftUI

struct CollectionWishlistView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CollectionStore.self) private var collection
    @State private var cards: [CatalogCardSearchResult] = []
    @State private var query = ""
    @State private var loading = true
    @State private var message: String?
    @State private var retry = 0

    private var ids: [String] {
        collection.cardMetadataByID.values.filter(\.isWishlisted).map(\.cardID).sorted()
    }

    private var visibleCards: [CatalogCardSearchResult] {
        let identifiers = Set(ids)
        return cards.filter { identifiers.contains($0.id) && CatalogCardTextQuery.matches(query, card: $0.card, setName: $0.setName) }
    }

    var body: some View {
        List {
            if loading && cards.isEmpty {
                ProgressView("Loading wishlist…")
            } else if ids.isEmpty {
                ContentUnavailableView("Your Wishlist Is Empty", systemImage: "heart",
                    description: Text("Add cards using Wishlist in card details."))
            } else {
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try Again") { retry += 1 }
                }
                if visibleCards.isEmpty && message == nil {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(visibleCards) { result in
                    NavigationLink {
                        CatalogCardDetailView(card: result.card, cards: visibleCards.map(\.card))
                    } label: {
                        HStack(spacing: 12) {
                            // Reuse the same artwork pipeline as card details.
                            WishlistArtwork(card: result.card)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.card.name).font(.headline)
                                Text("\(result.setName) · #\(result.card.localID)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if collection.owns(cardID: result.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint).accessibilityLabel("Owned")
                            }
                        }
                    }
                    .accessibilityIdentifier("wishlist.card.\(result.id)")
                }
            }
        }
        .navigationTitle("Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Pokémon and number")
        .task(id: "\(ids.joined(separator: "|"))|\(catalog.isPreparingSearchIndex)|\(retry)") {
            loading = true
            message = nil
            defer { loading = false }
            do {
                let loaded = try await catalog.searchResults(cardIDs: ids)
                try Task.checkCancellation()
                cards = loaded.sorted { $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending }
                if loaded.count < ids.count {
                    message = "Some wishlist cards are not available in the saved catalog yet. Your wishlist is preserved."
                }
            } catch is CancellationError { return }
            catch { message = "Your wishlist couldn’t be loaded. Please try again." }
        }
    }
}

private struct WishlistArtwork: View {
    let card: CatalogCard
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 48, height: 66)
        .accessibilityHidden(true)
        .task(id: card.id) {
            if let data = try? await CatalogArtworkCache.shared.bestAvailableData(for: card.thumbnailArtworkReferences) {
                image = UIImage(data: data)
            }
        }
    }
}
