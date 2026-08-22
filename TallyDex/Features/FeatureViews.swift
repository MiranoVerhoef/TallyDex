import SwiftUI

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

struct SetsView: View {
    @AppStorage(SetsScope.storageKey) private var defaultScope = SetsScope.all.rawValue
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

                ContentUnavailableView(
                    selectedScope.title,
                    systemImage: selectedScope.systemImage,
                    description: Text(selectedScope.emptyDescription)
                )
            }
            .navigationTitle("Sets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("TallyDexLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 124, height: 40)
                        .clipShape(.rect(cornerRadius: 8))
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
                } header: {
                    Text("Sets")
                } footer: {
                    Text("The Sets tab opens with this view.")
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
