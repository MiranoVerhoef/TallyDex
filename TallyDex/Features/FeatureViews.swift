import SwiftUI

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
            VStack(spacing: 0) {
                Picker("Sets view", selection: $selectedScope) {
                    ForEach(SetsScope.allCases) { scope in
                        Text(scope.pickerTitle)
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                setsContent
            }
            .navigationTitle("Sets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("TallyDexLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 132, height: 44)
                        .accessibilityLabel("TallyDex")
                }
            }
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
                        }
                    } header: {
                        CatalogSeriesHeader(group: group)
                    }
                }
            }
            .listStyle(.insetGrouped)
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
                }
            }
            .listStyle(.insetGrouped)
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

private struct CatalogSetRow: View {
    let set: CatalogSet

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: set.logoURL?.appendingPathExtension("png")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                default:
                    Image(systemName: "rectangle.stack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 116, height: 76)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(set.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let abbreviation = set.abbreviation {
                    Text(abbreviation)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
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
            AsyncImage(url: group.series.logoURL?.appendingPathExtension("png")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                default:
                    Image(systemName: "rectangle.stack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, height: 48)
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
        List(group.sets) { set in
            NavigationLink {
                CatalogSetDetailView(set: set)
            } label: {
                CatalogSetRow(set: set)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.series.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct CatalogSetDetailView: View {
    let set: CatalogSet

    private var secretCardCount: Int {
        max(0, set.totalCardCount - set.officialCardCount)
    }

    private var cardCountText: String {
        if secretCardCount > 0 {
            "\(set.officialCardCount) cards + \(secretCardCount) secret"
        } else {
            "\(set.officialCardCount) cards"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AsyncImage(url: set.logoURL?.appendingPathExtension("png")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    default:
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 300, minHeight: 120, maxHeight: 170)
                .padding(.top)

                VStack(spacing: 6) {
                    if let abbreviation = set.abbreviation {
                        Text(abbreviation)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(cardCountText)
                        .font(.title3.weight(.semibold))
                }
                .accessibilityElement(children: .combine)

                ContentUnavailableView(
                    "Card List Coming Next",
                    systemImage: "rectangle.grid.3x2",
                    description: Text("This set is connected to the local catalog. The card grid and collection controls are the next slice.")
                )
            }
            .padding()
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search the Catalog",
                systemImage: "magnifyingglass",
                description: Text("Find cards by name, set, or collector number.")
            )
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Card, set, or number")
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
            }
            .navigationTitle("Settings")
        }
    }
}
