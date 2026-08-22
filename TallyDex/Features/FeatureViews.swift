import SwiftUI

struct SetsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Label("All Sets", systemImage: "square.grid.2x2")
                    Label("My Sets", systemImage: "star")
                    Label("Hidden", systemImage: "eye.slash")
                }
            }
            .navigationTitle("Sets")
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
    var body: some View {
        NavigationStack {
            Form {
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

