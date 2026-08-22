import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolve(_ storedValue: String) -> AppAppearance {
        AppAppearance(rawValue: storedValue) ?? .system
    }
}

enum SetsScope: String, CaseIterable, Identifiable {
    case all
    case mySets
    case hidden

    static let storageKey = "sets.defaultScope"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Sets"
        case .mySets: "My Sets"
        case .hidden: "Hidden"
        }
    }

    var pickerTitle: String {
        switch self {
        case .all: "All"
        case .mySets: "My Sets"
        case .hidden: "Hidden"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .mySets: "star"
        case .hidden: "eye.slash"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: "Every English card set will appear here when the catalog is ready."
        case .mySets: "Sets you choose to collect will appear here."
        case .hidden: "Sets you hide will stay here without losing collection data."
        }
    }

    static func resolve(_ storedValue: String) -> SetsScope {
        SetsScope(rawValue: storedValue) ?? .all
    }
}

enum SetsBrowsingStyle: String, CaseIterable, Identifiable {
    case seriesFirst
    case grouped

    static let storageKey = "sets.browsingStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped: "Grouped List"
        case .seriesFirst: "Series First"
        }
    }

    var description: String {
        switch self {
        case .grouped: "Show every set in one list, grouped under its series."
        case .seriesFirst: "Choose a series first, then choose one of its sets."
        }
    }

    static func resolve(_ storedValue: String) -> SetsBrowsingStyle {
        SetsBrowsingStyle(rawValue: storedValue) ?? .seriesFirst
    }
}

struct SetsView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @AppStorage(SetsScope.storageKey) private var defaultScope = SetsScope.all.rawValue
    @AppStorage(SetsBrowsingStyle.storageKey) private var browsingStyle = SetsBrowsingStyle.seriesFirst.rawValue
    @State private var selectedScope = SetsScope.all
    @State private var didApplyDefault = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Image("TallyDexLogo")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 132, height: 44)
                            .accessibilityLabel("TallyDex")
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    HStack {
                        Text("Sets")
                            .font(.largeTitle.bold())
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                    Picker("Sets view", selection: $selectedScope) {
                        ForEach(SetsScope.allCases) { scope in
                            Text(scope.pickerTitle)
                                .tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    setsContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                guard !didApplyDefault else { return }
                selectedScope = SetsScope.resolve(defaultScope)
                didApplyDefault = true
            }
            .onChange(of: defaultScope) { _, newValue in
                selectedScope = SetsScope.resolve(newValue)
            }
        }
    }

    @ViewBuilder
    private var setsContent: some View {
        switch selectedScope {
        case .all:
            if catalogStore.isInitialLoading && catalogStore.groups.isEmpty {
                ProgressView("Loading saved catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if catalogStore.groups.isEmpty {
                ContentUnavailableView(
                    "Catalog Unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(catalogStore.refreshMessage ?? SetsScope.all.emptyDescription)
                )
            } else {
                catalogList
            }
        case .mySets, .hidden:
            ContentUnavailableView(
                selectedScope.title,
                systemImage: selectedScope.systemImage,
                description: Text(selectedScope.emptyDescription)
            )
        }
    }

    @ViewBuilder
    private var catalogList: some View {
        switch SetsBrowsingStyle.resolve(browsingStyle) {
        case .grouped:
            List {
                catalogRefreshMessage

                ForEach(catalogStore.groups) { group in
                    Section {
                        ForEach(group.sets) { set in
                            NavigationLink {
                                CatalogSetDetailView(set: set)
                            } label: {
                                CatalogSetRow(set: set)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        CatalogSeriesHeader(group: group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await catalogStore.refresh()
            }
        case .seriesFirst:
            List {
                catalogRefreshMessage

                ForEach(catalogStore.groups) { group in
                    NavigationLink {
                        CatalogSeriesSetsView(group: group)
                    } label: {
                        CatalogSeriesRow(group: group)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await catalogStore.refresh()
            }
        }
    }

    @ViewBuilder
    private var catalogRefreshMessage: some View {
        if let message = catalogStore.refreshMessage {
            Label(message, systemImage: "icloud.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CatalogSeriesHeader: View {
    let group: CatalogSeriesGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.series.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            Text("\(group.sets.count) \(group.sets.count == 1 ? "set" : "sets")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CatalogArtwork: View {
    let reference: CatalogArtworkReference?

    var body: some View {
        if let reference {
            CachedCatalogImage(reference: reference)
        } else {
            CatalogPlaceholderMark()
        }
    }
}

private struct CatalogSymbol: View {
    let url: URL

    var body: some View {
        CachedCatalogImage(
            reference: CatalogArtworkReference(url: url, category: .expansionSymbols)
        )
    }
}

private struct CachedCatalogImage: View {
    let reference: CatalogArtworkReference
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                CatalogPlaceholderMark()
            }
        }
        .task(id: reference) {
            imageData = try? await CatalogArtworkCache.shared.data(for: reference)
        }
    }
}

private struct CatalogPlaceholderMark: View {
    var body: some View {
        Image("TallyDexLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(8)
            .accessibilityLabel("TallyDex placeholder")
    }
}

private struct CatalogSetRow: View {
    let set: CatalogSet

    var body: some View {
        HStack(spacing: 12) {
            CatalogArtwork(reference: set.preferredArtworkReference)
            .frame(width: 116, height: 76)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(set.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if set.isUpcoming(), let releaseDate = set.releaseDateValue {
                    Label {
                        Text("Upcoming · \(releaseDate.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                }

                if set.usesPrintedExpansionCode, let abbreviation = set.abbreviation {
                    Text(abbreviation)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if let symbolURL = set.symbolURL {
                    CatalogSymbol(url: symbolURL)
                        .frame(width: 30, height: 20)
                        .accessibilityLabel("Expansion symbol")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CatalogSeriesRow: View {
    let group: CatalogSeriesGroup

    var body: some View {
        HStack(spacing: 14) {
            CatalogArtwork(reference: group.preferredArtworkReference)
            .frame(width: 124, height: 72)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.series.name)
                    .font(.body.weight(.semibold))
                Text("\(group.sets.count) \(group.sets.count == 1 ? "set" : "sets")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CatalogSeriesSetsView: View {
    let group: CatalogSeriesGroup

    var body: some View {
        List {
            ForEach(group.sets) { set in
                NavigationLink {
                    CatalogSetDetailView(set: set)
                } label: {
                    CatalogSetRow(set: set)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.series.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct CatalogSetDetailView: View {
    let set: CatalogSet
    @Environment(CatalogStore.self) private var catalogStore
    @State private var isShowingInformation = false
    @State private var cards: [CatalogCard] = []
    @State private var isLoadingCards = true
    @State private var cardMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                CatalogArtwork(reference: set.preferredArtworkReference)
                .frame(maxWidth: 260, minHeight: 96, maxHeight: 140)
                .padding(.top)

                VStack(spacing: 6) {
                    if set.usesPrintedExpansionCode, let abbreviation = set.abbreviation {
                        Text(abbreviation)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else if set.logoURL != nil, let symbolURL = set.symbolURL {
                        CatalogSymbol(url: symbolURL)
                            .frame(width: 42, height: 28)
                            .accessibilityLabel("Expansion symbol")
                    }
                }
                .accessibilityElement(children: .combine)

                if isLoadingCards && cards.isEmpty {
                    ProgressView("Updating card list…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if cards.isEmpty {
                    ContentUnavailableView(
                        set.isUpcoming() ? "Cards Not Announced Yet" : "Card List Unavailable",
                        systemImage: "rectangle.grid.3x2",
                        description: Text(cardMessage ?? "Pull down to check for this set’s cards again.")
                    )
                } else {
                    HStack {
                        Text("\(cards.count) cards")
                            .font(.headline)
                        Spacer()
                        if isLoadingCards {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(cards) { card in
                            NavigationLink {
                                CatalogCardDetailView(card: card)
                            } label: {
                                CatalogCardTile(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await loadCards(forceRefresh: true)
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Set information", systemImage: "info.circle") {
                    isShowingInformation = true
                }
            }
        }
        .sheet(isPresented: $isShowingInformation) {
            CatalogSetInformationView(set: set)
        }
        .task(id: set.id) {
            await loadCards()
        }
    }

    private func loadCards(forceRefresh: Bool = false) async {
        isLoadingCards = true
        cardMessage = nil
        defer { isLoadingCards = false }
        do {
            cards = try await catalogStore.cards(for: set, forceRefresh: forceRefresh)
        } catch {
            cardMessage = set.isUpcoming()
                ? "The card list will appear automatically after it is published."
                : "TallyDex couldn’t update this card list. Check your connection and pull down to retry."
        }
    }
}

private struct CatalogCardTile: View {
    let card: CatalogCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedCardImage(reference: card.thumbnailArtworkReference)
                .aspectRatio(245 / 337, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(card.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("#\(card.localID)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CachedCardImage: View {
    let reference: CatalogArtworkReference?
    @State private var imageData: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Image(systemName: "rectangle.portrait")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: reference) {
            guard let reference else { return }
            imageData = try? await CatalogArtworkCache.shared.data(for: reference)
        }
    }
}

private struct CatalogCardDetailView: View {
    let card: CatalogCard
    @Environment(CatalogStore.self) private var catalogStore
    @State private var snapshot: CatalogCardSnapshot?
    @State private var message: String?

    private var displayedCard: CatalogCard { snapshot?.card ?? card }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CachedCardImage(reference: displayedCard.fullArtworkReference)
                    .aspectRatio(245 / 337, contentMode: .fit)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Collector number", value: displayedCard.localID)
                    if let category = displayedCard.category {
                        LabeledContent("Category", value: category)
                    }
                    if let rarity = displayedCard.rarity {
                        LabeledContent("Rarity", value: rarity)
                    }
                    if let illustrator = displayedCard.illustrator {
                        LabeledContent("Illustrator", value: illustrator)
                    }
                }

                if let variants = snapshot?.variants, !variants.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Available variants")
                            .font(.headline)
                        Text(variants.map(variantTitle).sorted().joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }

                if let message {
                    Label(message, systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: card.id) {
            do {
                snapshot = try await catalogStore.details(for: card)
            } catch {
                message = "Detailed card data will be retried the next time you open this card."
            }
        }
    }

    private func variantTitle(_ variant: CatalogVariantKind) -> String {
        switch variant {
        case .normal: "Normal"
        case .reverseHolo: "Reverse holo"
        case .holo: "Holo"
        case .firstEdition: "First edition"
        case .watermarkedPromo: "Watermarked promo"
        }
    }
}

private struct CatalogSetInformationView: View {
    let set: CatalogSet
    @Environment(\.dismiss) private var dismiss

    private var additionalCardCount: Int {
        max(0, set.totalCardCount - set.officialCardCount)
    }

    private var releaseDateText: String {
        guard let releaseDate = set.releaseDate else { return "Unknown" }
        let parts = releaseDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar(identifier: .gregorian).date(
                  from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              ) else {
            return releaseDate
        }
        return date.formatted(date: .long, time: .omitted)
    }

    private var sortedRarityCounts: [CatalogRarityCount] {
        let priority = [
            "illustration rare": 0,
            "ultra rare": 1,
            "special illustration rare": 2,
            "hyper rare": 3,
            "mega hyper rare": 4,
        ]
        return (set.rarityCounts ?? []).sorted {
            let left = priority[$0.rarity.lowercased(), default: .max]
            let right = priority[$1.rarity.lowercased(), default: .max]
            if left == right { return $0.rarity < $1.rarity }
            return left < right
        }
    }

    private var additionalRarityCounts: [CatalogRarityCount] {
        let candidates = sortedRarityCounts.filter { rarityCount in
            let rarity = rarityCount.rarity.lowercased()
            return rarity.contains("illustration")
                || rarity.contains("ultra")
                || rarity.contains("hyper")
                || rarity.contains("secret")
                || rarity.contains("rainbow")
                || rarity.contains("shiny")
                || rarity.contains("gold")
                || rarity.contains("trainer gallery")
                || rarity.contains("classic collection")
        }
        guard candidates.reduce(0, { $0 + $1.count }) == additionalCardCount else {
            return []
        }
        return candidates
    }

    private func displayName(for rarity: String) -> String {
        switch rarity.lowercased() {
        case "illustration rare": "Illustration Rare (IR)"
        case "special illustration rare": "Special Illustration Rare (SIR)"
        case "ultra rare": "Ultra Rare (UR)"
        case "mega hyper rare": "Mega Hyper Rare (MHR)"
        default: rarity.capitalized
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Release") {
                    LabeledContent("Date", value: releaseDateText)
                    if set.usesPrintedExpansionCode, let abbreviation = set.abbreviation {
                        LabeledContent("Expansion code", value: abbreviation)
                    } else if let symbolURL = set.symbolURL {
                        LabeledContent("Expansion symbol") {
                            CatalogSymbol(url: symbolURL)
                                .frame(width: 34, height: 24)
                                .accessibilityLabel("Expansion symbol")
                        }
                    } else if let abbreviation = set.abbreviation {
                        LabeledContent("Catalog ID", value: abbreviation)
                    }
                }

                Section("Cards") {
                    if set.officialCardCount > 0 {
                        LabeledContent("Main numbered cards", value: "\(set.officialCardCount)")
                        LabeledContent("Total cataloged cards", value: "\(set.totalCardCount)")
                    } else {
                        LabeledContent("Card counts", value: "To be announced")
                    }
                }

                if !additionalRarityCounts.isEmpty {
                    Section {
                        ForEach(additionalRarityCounts) { rarityCount in
                            LabeledContent(
                                displayName(for: rarityCount.rarity),
                                value: "\(rarityCount.count)"
                            )
                        }
                    } header: {
                        Text("Additional cards")
                    } footer: {
                        Text("\(additionalCardCount) cards beyond the main numbered set.")
                    }
                } else if additionalCardCount > 0 {
                    Section("Additional cards") {
                        LabeledContent("Additional cards", value: "\(additionalCardCount)")
                    }
                }

                if additionalRarityCounts.isEmpty && !sortedRarityCounts.isEmpty {
                    Section("Rarity breakdown") {
                        ForEach(sortedRarityCounts) { rarityCount in
                            LabeledContent(
                                displayName(for: rarityCount.rarity),
                                value: "\(rarityCount.count)"
                            )
                        }
                    }
                }

                Section {
                    Text("Additional cards are entries beyond the main numbered set. A master collection may also include parallel variants such as reverse holos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(set.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SearchView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @State private var query = ""
    @State private var results: [CatalogCardSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if catalogStore.isPreparingSearchIndex {
                        ProgressView("Preparing complete card search…")
                    } else {
                        ContentUnavailableView(
                            "Search the Catalog",
                            systemImage: "magnifyingglass",
                            description: Text(
                                catalogStore.searchIndexMessage
                                    ?? "Find every cataloged card by card name, set, or collector number."
                            )
                        )
                    }
                } else if isSearching && results.isEmpty {
                    ProgressView("Searching…")
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { result in
                        NavigationLink {
                            CatalogCardDetailView(card: result.card)
                        } label: {
                            HStack(spacing: 12) {
                                CachedCardImage(reference: result.card.thumbnailArtworkReference)
                                    .frame(width: 52, height: 72)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.card.name)
                                        .font(.body.weight(.semibold))
                                    Text("\(result.setName) · #\(result.card.localID)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Card, set, or number")
            .task(id: "\(query)|\(catalogStore.isPreparingSearchIndex)") {
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    results = []
                    return
                }
                isSearching = true
                defer { isSearching = false }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                results = (try? await catalogStore.searchCards(query: query)) ?? []
            }
        }
    }
}

struct CollectionView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your Collection Is Empty",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Cards you collect will appear here.")
            )
            .navigationTitle("Collection")
        }
    }
}

struct SettingsView: View {
    @AppStorage(SetsScope.storageKey) private var defaultSetsScope = SetsScope.all.rawValue
    @AppStorage(SetsBrowsingStyle.storageKey) private var browsingStyle = SetsBrowsingStyle.seriesFirst.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Default View", selection: $defaultSetsScope) {
                        ForEach(SetsScope.allCases) { scope in
                            Label(scope.title, systemImage: scope.systemImage)
                                .tag(scope.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Layout", selection: $browsingStyle) {
                        ForEach(SetsBrowsingStyle.allCases) { style in
                            Text(style.title)
                                .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Sets")
                } footer: {
                    Text(SetsBrowsingStyle.resolve(browsingStyle).description)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Storage") {
                    NavigationLink {
                        ArtworkCacheSettingsView()
                    } label: {
                        Label("Artwork Cache", systemImage: "externaldrive")
                    }
                }

                Section("Privacy") {
                    LabeledContent("Storage", value: "On this iPhone")
                    LabeledContent("Analytics", value: "None")
                }

                Section("Data") {
                    Button("Export Backup") {}
                        .disabled(true)
                    Button("Import Backup") {}
                        .disabled(true)
                }

                Section("iCloud") {
                    LabeledContent("Sync", value: "Off")
                }

                Section {
                    NavigationLink {
                        AboutTallyDexView()
                    } label: {
                        Label("About TallyDex", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct ArtworkCacheSettingsView: View {
    @Environment(ArtworkCacheStore.self) private var artworkCacheStore
    @Environment(CatalogStore.self) private var catalogStore
    @State private var isConfirmingClearAll = false

    private func sizeDescription(_ statistics: CatalogArtworkCacheStatistics) -> String {
        guard statistics.fileCount > 0 else { return "Empty" }
        let size = ByteCountFormatter.string(
            fromByteCount: statistics.byteCount,
            countStyle: .file
        )
        return "\(statistics.fileCount) · \(size)"
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task {
                        await artworkCacheStore.prefetch(groups: catalogStore.groups)
                    }
                } label: {
                    if artworkCacheStore.isPrefetching {
                        Label("Caching Artwork…", systemImage: "arrow.down.circle")
                    } else {
                        Label("Cache Missing Artwork", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(artworkCacheStore.isPrefetching || catalogStore.groups.isEmpty)

                LabeledContent(
                    "Total",
                    value: sizeDescription(
                        CatalogArtworkCacheStatistics(
                            fileCount: artworkCacheStore.snapshot.totalFileCount,
                            byteCount: artworkCacheStore.snapshot.totalByteCount
                        )
                    )
                )
            } footer: {
                Text("TallyDex stores TCGdex series logos, set logos, expansion symbols, and viewed card images on this iPhone so they appear immediately after a cold launch.")
            }

            Section("Choose What to Remove") {
                ForEach(CatalogArtworkCategory.allCases) { category in
                    let statistics = artworkCacheStore.snapshot.statistics(for: category)
                    HStack(spacing: 12) {
                        Label(category.title, systemImage: category.systemImage)
                        Spacer()
                        Text(sizeDescription(statistics))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Clear", role: .destructive) {
                            Task { await artworkCacheStore.remove(category) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(statistics.fileCount == 0)
                    }
                }
            }

            Section {
                Button("Clear All Artwork", role: .destructive) {
                    isConfirmingClearAll = true
                }
                .disabled(artworkCacheStore.snapshot.totalFileCount == 0)
            }

            if let statusMessage = artworkCacheStore.statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Artwork Cache")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await artworkCacheStore.refreshSnapshot()
        }
        .confirmationDialog(
            "Clear every cached logo and symbol?",
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All Artwork", role: .destructive) {
                Task { await artworkCacheStore.removeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Artwork will download again when needed.")
        }
    }
}

private struct AboutTallyDexView: View {
    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("TallyDexLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 90)
                    Text(versionDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("The Name") {
                Text("TallyDex combines “tally”—keeping a count—with “dex,” a catalog or index. It is a catalog for tallying your card collection.")
            }

            Section("Data & Artwork") {
                Text("Catalog metadata, set logos, and expansion symbols are supplied by TCGdex and cached locally by TallyDex.")
                Link("Visit TCGdex", destination: URL(string: "https://www.tcgdex.net")!)
            }

            Section("Copyright & Ownership") {
                Text("TallyDex original code, interface, name, and artwork © 2026 Mirano Verhoef. All rights reserved.")
                Text("Pokémon and all related card, set, expansion, character, logo, and artwork rights belong to their respective owners.")
                Text("© Pokémon. © Nintendo/Creatures Inc./GAME FREAK inc. TM, ® Nintendo.")
                Text("TallyDex is an unofficial fan-made app. It is not affiliated with, endorsed by, or sponsored by The Pokémon Company, Nintendo, Creatures Inc., or GAME FREAK inc.")
            }
        }
        .navigationTitle("About TallyDex")
        .navigationBarTitleDisplayMode(.inline)
    }
}
