import SwiftUI
import UIKit

private func formattedCatalogPrice(_ amount: Double, currencyCode: String) -> String {
    amount.formatted(
        .currency(code: currencyCode)
            .precision(.fractionLength(2))
    )
}

private struct CardCompletionIndicator: View {
    let progress: CollectionProgress
    var size: CGFloat = 34

    private var fraction: Double {
        guard progress.requiredSlots > 0 else { return 0 }
        return min(1, max(0, Double(progress.completedSlots) / Double(progress.requiredSlots)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.45), lineWidth: 3)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            if fraction >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(
            progress.requiredSlots == 1
                ? (progress.completedSlots == 1 ? "Owned" : "Missing")
                : "\(progress.completedSlots) of \(progress.requiredSlots) required printings owned"
        )
    }
}

private struct CollectionValueSummaryView: View {
    let summary: CatalogValueSummary
    var title = "Estimated value"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formattedCatalogPrice(summary.amount, currencyCode: summary.currencyCode))
                    .font(.headline.monospacedDigit())
            }
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let priced = "\(summary.pricedVariants) priced printing\(summary.pricedVariants == 1 ? "" : "s")"
        guard summary.missingVariants > 0 else {
            return "\(summary.source.displayName) · \(priced)"
        }
        return "\(summary.source.displayName) · \(priced) · \(summary.missingVariants) without an exact price"
    }
}

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
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(SetsScope.storageKey) private var defaultScope = SetsScope.all.rawValue
    @AppStorage(SetsBrowsingStyle.storageKey) private var browsingStyle = SetsBrowsingStyle.seriesFirst.rawValue
    @State private var selectedScope = SetsScope.all
    @State private var didApplyDefault = false
    @State private var editingSet: CatalogSet?

    private var scopedGroups: [CatalogSeriesGroup] {
        catalogStore.groups.compactMap { group in
            let sets = group.sets.filter { set in
                let status = collectionStore.trackingStatus(for: set.id)
                switch selectedScope {
                case .all: return status != .hidden
                case .mySets: return status == .collecting
                case .hidden: return status == .hidden
                }
            }
            guard !sets.isEmpty else { return nil }
            return CatalogSeriesGroup(series: group.series, sets: sets)
        }
    }

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
            .sheet(item: $editingSet) { set in
                CatalogSetCollectionSettingsView(set: set)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var setsContent: some View {
        if catalogStore.isInitialLoading && catalogStore.groups.isEmpty {
            ProgressView("Loading saved catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedScope == .all && catalogStore.groups.isEmpty {
            ContentUnavailableView(
                "Catalog Unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text(catalogStore.refreshMessage ?? SetsScope.all.emptyDescription)
            )
        } else if scopedGroups.isEmpty {
            ContentUnavailableView(
                selectedScope.title,
                systemImage: selectedScope.systemImage,
                description: Text(selectedScope.emptyDescription)
            )
        } else {
            catalogList
        }
    }

    @ViewBuilder
    private var catalogList: some View {
        switch SetsBrowsingStyle.resolve(browsingStyle) {
        case .grouped:
            List {
                catalogRefreshMessage

                ForEach(scopedGroups) { group in
                    Section {
                        ForEach(group.sets) { set in
                            CatalogSetLink(set: set) { editingSet = $0 }
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

                ForEach(scopedGroups) { group in
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

private struct CatalogSetLink: View {
    let set: CatalogSet
    let onEdit: (CatalogSet) -> Void

    var body: some View {
        NavigationLink {
            CatalogSetDetailView(set: set)
        } label: {
            CatalogSetRow(set: set)
        }
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3") {
                onEdit(set)
            }
        }
    }
}

private struct CatalogSetCollectionSettingsView: View {
    let set: CatalogSet
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus = SetTrackingStatus.notCollecting
    @State private var selectedGoal = CollectionGoal.normal
    @State private var includedVariants: Set<CatalogVariantKind> = [.normal]
    @State private var includesSecretCards = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var originalPreference: SetCollectionPreference?
    @State private var pendingPreference: SetCollectionPreference?
    @State private var isConfirmingGoalChange = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Set visibility") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(SetTrackingStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    Text("Hidden sets stay out of All Sets but keep every saved quantity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Collecting \(set.name)") {
                    Picker("Collection goal", selection: $selectedGoal) {
                        ForEach(CollectionGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    .disabled(selectedStatus != .collecting)

                    Text(selectedGoal.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if selectedStatus == .collecting && selectedGoal == .custom {
                    Section("Custom card rule") {
                        Toggle("Include secret-numbered cards", isOn: $includesSecretCards)
                    }
                    Section("Custom printings") {
                        ForEach(CatalogVariantKind.allCases, id: \.self) { variant in
                            variantToggle(variant)
                        }
                    }
                }

                Section {
                    Text("Changing goals creates a local backup first. Existing cards and quantities remain saved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                let preference = collectionStore.preference(for: set.id)
                originalPreference = preference
                selectedStatus = preference.status
                selectedGoal = preference.goal
                includedVariants = preference.includedVariants
                includesSecretCards = preference.includesSecretCards
            }
            .confirmationDialog(
                goalChangeTitle,
                isPresented: $isConfirmingGoalChange,
                titleVisibility: .visible
            ) {
                Button("Create Backup & Change Goal") {
                    guard let pendingPreference else { return }
                    persist(pendingPreference, creatingBackup: true)
                }
                Button("Cancel", role: .cancel) {
                    pendingPreference = nil
                }
            } message: {
                Text(goalChangeWarning)
            }
        }
    }

    private var goalChangeTitle: String {
        guard let originalPreference else { return "Change collection goal?" }
        return "Change \(originalPreference.goal.displayName) to \(selectedGoal.displayName)?"
    }

    private var goalChangeWarning: String {
        guard let originalPreference else {
            return "TallyDex will create a local collection backup before applying this change."
        }
        if originalPreference.goal == .master && selectedGoal == .normal {
            return "Your owned cards and printings will not be reset. Normal counts any owned printing as one card. If you later uncheck that card in Normal, all of its saved printings are removed. TallyDex will create a backup first."
        }
        if originalPreference.goal == .custom && selectedGoal == .master {
            return "Master will replace the Custom rules with every available printing and every numbered card. Your ownership stays saved, and TallyDex will back up the old Custom setup first."
        }
        return "The new goal will replace the previous goal rules without deleting ownership. TallyDex will create a local collection backup first."
    }

    private func variantToggle(_ variant: CatalogVariantKind) -> some View {
        Toggle(variant.displayName, isOn: Binding(
            get: { includedVariants.contains(variant) },
            set: { isIncluded in
                if isIncluded {
                    includedVariants.insert(variant)
                } else {
                    includedVariants.remove(variant)
                }
            }
        ))
    }

    private func save() {
        guard !isSaving else { return }
        message = nil
        let preference = preferenceToSave()
        if let originalPreference, originalPreference.goal != preference.goal {
            pendingPreference = preference
            isConfirmingGoalChange = true
            return
        }
        persist(preference, creatingBackup: false)
    }

    private func preferenceToSave() -> SetCollectionPreference {
        SetCollectionPreference(
            setID: set.id,
            status: selectedStatus,
            goal: selectedGoal,
            includedVariants: includedVariants,
            includesSecretCards: includesSecretCards,
            updatedAt: Date()
        )
        .applyingCanonicalGoalRules()
    }

    private func persist(
        _ preference: SetCollectionPreference,
        creatingBackup: Bool
    ) {
        guard !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            defer { isSaving = false }
            do {
                if creatingBackup, let originalPreference {
                    try await collectionStore.createBackup(
                        reason: "\(set.name): \(originalPreference.goal.displayName) → \(preference.goal.displayName)"
                    )
                }
                try await collectionStore.saveSetPreference(preference)
                dismiss()
            } catch {
                message = creatingBackup
                    ? "A backup couldn’t be created, so the goal was not changed."
                    : "That collection goal couldn’t be saved. Please try again."
            }
        }
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
    @State private var editingSet: CatalogSet?

    var body: some View {
        List {
            ForEach(group.sets) { set in
                CatalogSetLink(set: set) { editingSet = $0 }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.series.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingSet) { set in
            CatalogSetCollectionSettingsView(set: set)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private enum SetCardFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case missing

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct CatalogSetDetailView: View {
    let set: CatalogSet
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var isShowingInformation = false
    @State private var cards: [CatalogCard] = []
    @State private var isLoadingCards = true
    @State private var cardMessage: String?
    @State private var collectionMessage: String?
    @State private var selectedVariantCard: CatalogCard?
    @State private var updatingCardIDs: Set<String> = []
    @State private var selectedFilter = SetCardFilter.all
    @State private var searchText = ""
    @State private var availableVariantsByCardID: [String: Set<CatalogVariantKind>] = [:]
    @State private var pricesByCardID: [String: [CatalogPriceQuote]] = [:]
    @State private var isPreparingGoalMetadata = false

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14),
    ]

    private var collectionGoal: CollectionGoal {
        collectionStore.goal(for: set.id)
    }

    private var collectionPreference: SetCollectionPreference {
        collectionStore.preference(for: set.id)
    }

    private var progress: CollectionProgress {
        CollectionProgressCalculator.progress(
            cards: cards,
            set: set,
            preference: collectionPreference,
            availableVariants: availableVariantsByCardID,
            ownedEntries: collectionStore.ownedEntries
        )
    }

    private var valueSummary: CatalogValueSummary {
        let cardIDs = Set(cards.map(\.id))
        return CatalogValueCalculator.summary(
            entries: collectionStore.ownedEntries.filter { cardIDs.contains($0.cardID) },
            prices: pricesByCardID,
            source: CatalogPriceSource(rawValue: preferredPriceSource) ?? .cardmarket
        )
    }

    private var hasOwnedSetCards: Bool {
        let cardIDs = Set(cards.map(\.id))
        return collectionStore.ownedEntries.contains {
            $0.quantity > 0 && cardIDs.contains($0.cardID)
        }
    }

    private var visibleCards: [CatalogCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.filter { card in
            let filterMatches = switch selectedFilter {
            case .all: true
            case .owned: collectionStore.owns(cardID: card.id)
            case .missing: isMissingForGoal(card)
            }
            let searchMatches = query.isEmpty
                || card.name.localizedCaseInsensitiveContains(query)
                || card.localID.localizedCaseInsensitiveContains(query)
            return filterMatches && searchMatches
        }
    }

    private func isMissingForGoal(_ card: CatalogCard) -> Bool {
        let cardProgress = progress(for: card)
        return cardProgress.requiredSlots > 0 && cardProgress.completedSlots < cardProgress.requiredSlots
    }

    private func progress(for card: CatalogCard) -> CollectionProgress {
        CollectionProgressCalculator.progress(
            cards: [card],
            set: set,
            preference: collectionPreference,
            availableVariants: availableVariantsByCardID,
            ownedEntries: collectionStore.ownedEntries
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                CatalogArtwork(reference: set.preferredArtworkReference)
                .frame(maxWidth: 260, minHeight: 96, maxHeight: 140)
                .padding(.top)

                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        if set.usesPrintedExpansionCode, let abbreviation = set.abbreviation {
                            Text(abbreviation)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        } else if set.logoURL != nil, let symbolURL = set.symbolURL {
                            CatalogSymbol(url: symbolURL)
                                .frame(width: 42, height: 28)
                                .accessibilityLabel("Expansion symbol")
                        }

                        Text("\(progress.percentage)% \(collectionGoal.displayName)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)

                if hasOwnedSetCards {
                    CollectionValueSummaryView(summary: valueSummary, title: "Owned value")
                }

                if let collectionMessage {
                    Label(collectionMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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
                    Picker("Cards", selection: $selectedFilter) {
                        ForEach(SetCardFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("\(visibleCards.count) cards")
                            .font(.headline)
                        Spacer()
                        Text("\(progress.completedSlots) of \(progress.requiredSlots) goal slots")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if isPreparingGoalMetadata {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Loading printing rules")
                        }
                        if isLoadingCards {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visibleCards) { card in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    CatalogCardDetailView(card: card)
                                } label: {
                                    CatalogCardTile(card: card)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    handleCheckmarkTap(for: card)
                                } label: {
                                    if updatingCardIDs.contains(card.id) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(width: 34, height: 34)
                                    } else {
                                        CardCompletionIndicator(progress: progress(for: card))
                                    }
                                }
                                .background(.regularMaterial, in: Circle())
                                .contentShape(Circle())
                                .offset(x: 7, y: -7)
                                .disabled(updatingCardIDs.contains(card.id))
                                .accessibilityLabel("Edit owned printings for \(card.name)")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await loadCards(forceRefresh: true)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Card name or number"
        )
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
        .sheet(item: $selectedVariantCard) { card in
            CatalogVariantPickerView(card: card)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: set.id) {
            await loadCards()
        }
        .task(id: collectionGoal) {
            guard !cards.isEmpty else { return }
            await loadGoalVariants()
        }
        .onAppear {
            guard !cards.isEmpty else { return }
            Task {
                await loadGoalVariants()
            }
        }
    }

    private func handleCheckmarkTap(for card: CatalogCard) {
        collectionMessage = nil
        if collectionGoal == .master || collectionGoal == .custom {
            selectedVariantCard = card
            return
        }

        guard !updatingCardIDs.contains(card.id) else { return }
        updatingCardIDs.insert(card.id)
        Task {
            defer { updatingCardIDs.remove(card.id) }
            do {
                if collectionStore.owns(cardID: card.id) {
                    try await collectionStore.removeAllOwnership(cardID: card.id)
                    return
                }
                let snapshot = try await catalogStore.details(for: card)
                guard let standardVariant = preferredStandardVariant(in: snapshot.variants) else {
                    collectionMessage = "Printing information isn’t available for \(card.name) yet."
                    return
                }
                try await collectionStore.setQuantity(
                    1,
                    cardID: card.id,
                    variant: standardVariant
                )
            } catch {
                collectionMessage = "TallyDex couldn’t update \(card.name). Check your connection and try again."
            }
        }
    }

    private func preferredStandardVariant(
        in variants: Set<CatalogVariantKind>
    ) -> CatalogVariantKind? {
        let preference: [CatalogVariantKind] = [
            .normal,
            .holo,
            .reverseHolo,
            .firstEdition,
            .watermarkedPromo,
            .prerelease,
            .prereleaseStaff,
        ]
        return preference.first(where: variants.contains)
    }

    private func loadCards(forceRefresh: Bool = false) async {
        isLoadingCards = true
        cardMessage = nil
        defer { isLoadingCards = false }
        do {
            cards = try await catalogStore.cards(for: set, forceRefresh: forceRefresh)
            await loadGoalVariants(forcePriceRefresh: forceRefresh)
        } catch {
            cardMessage = set.isUpcoming()
                ? "The card list will appear automatically after it is published."
                : "TallyDex couldn’t update this card list. Check your connection and pull down to retry."
        }
    }

    private func loadGoalVariants(forcePriceRefresh: Bool = false) async {
        isPreparingGoalMetadata = true
        defer { isPreparingGoalMetadata = false }
        availableVariantsByCardID = await catalogStore.prepareVariants(
            for: cards,
            forcePriceRefresh: forcePriceRefresh
        )
        pricesByCardID = (try? await catalogStore.prices(cardIDs: cards.map(\.id))) ?? [:]
    }
}

private struct CatalogVariantPickerView: View {
    let card: CatalogCard
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CollectionSettings.allowsMultipleCopiesKey)
    private var allowsMultipleCopies = CollectionSettings.allowsMultipleCopiesDefault
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var snapshot: CatalogCardSnapshot?
    @State private var quantities: [CatalogVariantKind: Int] = [:]
    @State private var isLoading = true
    @State private var message: String?
    @State private var updatingVariants: Set<CatalogVariantKind> = []

    private var availableVariants: [CatalogVariantKind] {
        guard let variants = snapshot?.variants else { return [] }
        let visibleVariants = collectionStore.preference(for: card.setID).visibleVariants(in: variants)
        return CatalogVariantKind.allCases.filter(visibleVariants.contains)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CachedCardImage(reference: card.thumbnailArtworkReference)
                            .aspectRatio(245 / 337, contentMode: .fit)
                            .frame(width: 68)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name)
                                .font(.headline)
                            Text("#\(card.localID)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Owned printings") {
                    if isLoading {
                        ProgressView("Loading printings…")
                    } else if availableVariants.isEmpty {
                        Text("Printing information is not available for this card yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableVariants, id: \.self) { variant in
                            variantRow(variant)
                        }
                    }
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose printings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: card.id) {
                await load()
            }
        }
    }

    private func variantRow(_ variant: CatalogVariantKind) -> some View {
        let quantity = quantities[variant, default: 0]
        let isUpdating = updatingVariants.contains(variant)

        return HStack(spacing: 12) {
            Button {
                update(variant, to: quantity > 0 ? 0 : 1)
            } label: {
                Image(systemName: quantity > 0 ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
            .accessibilityLabel(quantity > 0 ? "Remove \(variant.displayName)" : "Add \(variant.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(variant.displayName)
                Text(priceText(for: variant))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if allowsMultipleCopies {
                Button {
                    update(variant, to: max(0, quantity - 1))
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(quantity == 0 || isUpdating)

                Text("\(quantity)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 24)

                Button {
                    update(variant, to: quantity + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
        }
    }

    private func priceText(for variant: CatalogVariantKind) -> String {
        let source = CatalogPriceSource(rawValue: preferredPriceSource) ?? .cardmarket
        guard let quote = snapshot?.prices.first(where: {
            $0.variant == variant && $0.source == source
        }) else {
            return "No TCGdex \(source.displayName) price for this printing"
        }
        return "\(source.displayName) · \(formattedCatalogPrice(quote.amount, currencyCode: quote.currencyCode))"
    }

    private func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            async let details = catalogStore.details(for: card)
            async let savedQuantities = collectionStore.quantities(for: card.id)
            snapshot = try await details
            quantities = try await savedQuantities
        } catch {
            message = "TallyDex couldn’t load this card’s printings. Please try again."
        }
    }

    private func update(_ variant: CatalogVariantKind, to quantity: Int) {
        guard !updatingVariants.contains(variant) else { return }
        updatingVariants.insert(variant)
        message = nil
        Task {
            defer { updatingVariants.remove(variant) }
            do {
                try await collectionStore.setQuantity(quantity, cardID: card.id, variant: variant)
                if quantity == 0 {
                    quantities.removeValue(forKey: variant)
                } else {
                    quantities[variant] = quantity
                }
            } catch {
                message = "That quantity couldn’t be saved. Please try again."
            }
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
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(CollectionSettings.allowsMultipleCopiesKey)
    private var allowsMultipleCopies = CollectionSettings.allowsMultipleCopiesDefault
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var snapshot: CatalogCardSnapshot?
    @State private var isLoadingDetails = true
    @State private var message: String?
    @State private var quantities: [CatalogVariantKind: Int] = [:]
    @State private var isLoadingCollection = true
    @State private var collectionMessage: String?
    @State private var updatingVariants: Set<CatalogVariantKind> = []
    @State private var isWishlisted = false
    @State private var notes = ""
    @State private var savedNotes = ""
    @State private var isSavingMetadata = false

    private var displayedCard: CatalogCard { snapshot?.card ?? card }
    private var availableVariants: [CatalogVariantKind] {
        guard let variants = snapshot?.variants else { return [] }
        let visibleVariants = collectionStore.preference(for: card.setID).visibleVariants(in: variants)
        return CatalogVariantKind.allCases.filter(visibleVariants.contains)
    }

    private var cardmarketURL: URL? {
        let visibleOrder = Dictionary(
            uniqueKeysWithValues: availableVariants.enumerated().map { ($0.element, $0.offset) }
        )
        return snapshot?.prices
            .filter { $0.source == .cardmarket && $0.marketplaceURL != nil }
            .sorted {
                visibleOrder[$0.variant, default: Int.max]
                    < visibleOrder[$1.variant, default: Int.max]
            }
            .compactMap(\.marketplaceURL)
            .first
    }

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
                        Text(variants.map(\.displayName).sorted().joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }

                personalSection
                collectionSection

                if let cardmarketURL {
                    Link(destination: cardmarketURL) {
                        Label("Open on Cardmarket", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let message {
                    Label(message, systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .safeAreaPadding(.bottom, 86)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: card.id) {
            isLoadingDetails = true
            defer { isLoadingDetails = false }
            do {
                snapshot = try await catalogStore.details(for: card)
            } catch {
                message = "Detailed card data will be retried the next time you open this card."
            }
        }
        .task(id: card.id) {
            isLoadingCollection = true
            defer { isLoadingCollection = false }
            do {
                async let savedQuantities = collectionStore.quantities(for: card.id)
                async let savedMetadata = collectionStore.cardMetadata(for: card.id)
                quantities = try await savedQuantities
                let metadata = try await savedMetadata
                isWishlisted = metadata.isWishlisted
                notes = metadata.notes
                savedNotes = metadata.notes
            } catch {
                collectionMessage = "Your saved collection details couldn’t be loaded."
            }
        }
    }

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Personal")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { isWishlisted },
                set: { newValue in
                    isWishlisted = newValue
                    saveMetadata()
                }
            )) {
                Label("Wishlist", systemImage: isWishlisted ? "heart.fill" : "heart")
            }
            .disabled(isSavingMetadata)

            Text("Notes")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $notes)
                .frame(minHeight: 90)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2))
                }

            HStack {
                Spacer()
                Button("Save Notes") { saveMetadata() }
                    .buttonStyle(.borderedProminent)
                    .disabled(notes == savedNotes || isSavingMetadata)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your collection")
                .font(.headline)

            if isLoadingDetails {
                ProgressView("Loading supported variants…")
            } else if availableVariants.isEmpty {
                Label("Variant information is unavailable for this card.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableVariants, id: \.self) { variant in
                    quantityRow(for: variant)
                }
            }

            if isLoadingCollection {
                ProgressView("Loading saved quantities…")
                    .controlSize(.small)
            }

            if let collectionMessage {
                Label(collectionMessage, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func quantityRow(for variant: CatalogVariantKind) -> some View {
        let quantity = quantities[variant, default: 0]
        let isUpdating = updatingVariants.contains(variant)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.displayName)
                    .font(.body.weight(.medium))
                Text(priceText(for: variant))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if allowsMultipleCopies {
                    Text(quantity == 1 ? "1 copy" : "\(quantity) copies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if allowsMultipleCopies {
                Button {
                    updateQuantity(for: variant, to: max(0, quantity - 1))
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(quantity == 0 || isUpdating)
                .accessibilityLabel("Remove one \(variant.displayName)")

                Text("\(quantity)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 28)
                    .accessibilityLabel("\(quantity) owned")

                Button {
                    updateQuantity(for: variant, to: quantity + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
                .accessibilityLabel("Add one \(variant.displayName)")
            } else {
                Button {
                    updateQuantity(for: variant, to: quantity > 0 ? 0 : 1)
                } label: {
                    Image(systemName: quantity > 0 ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel(
                    quantity > 0 ? "Remove \(variant.displayName)" : "Mark \(variant.displayName) as owned"
                )
            }
        }
    }

    private func priceText(for variant: CatalogVariantKind) -> String {
        let source = CatalogPriceSource(rawValue: preferredPriceSource) ?? .cardmarket
        guard let quote = snapshot?.prices.first(where: {
            $0.variant == variant && $0.source == source
        }) else {
            return "No TCGdex \(source.displayName) price for this printing"
        }
        return "\(source.displayName) · \(formattedCatalogPrice(quote.amount, currencyCode: quote.currencyCode))"
    }

    private func updateQuantity(for variant: CatalogVariantKind, to newQuantity: Int) {
        guard !updatingVariants.contains(variant) else { return }
        updatingVariants.insert(variant)
        collectionMessage = nil

        Task {
            defer { updatingVariants.remove(variant) }
            do {
                try await collectionStore.setQuantity(
                    newQuantity,
                    cardID: card.id,
                    variant: variant
                )
                if newQuantity == 0 {
                    quantities.removeValue(forKey: variant)
                } else {
                    quantities[variant] = newQuantity
                }
            } catch {
                collectionMessage = "That quantity couldn’t be saved. Please try again."
            }
        }
    }

    private func saveMetadata() {
        guard !isSavingMetadata else { return }
        isSavingMetadata = true
        collectionMessage = nil
        let wishlistValue = isWishlisted
        let notesValue = notes
        Task {
            defer { isSavingMetadata = false }
            do {
                try await collectionStore.saveCardMetadata(
                    cardID: card.id,
                    isWishlisted: wishlistValue,
                    notes: notesValue
                )
                savedNotes = notesValue
            } catch {
                collectionMessage = "Your wishlist or notes couldn’t be saved. Please try again."
            }
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

private enum SearchResultLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

struct SearchView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage("search.resultLayout") private var resultLayout = SearchResultLayout.list.rawValue
    @State private var query = ""
    @State private var results: [CatalogCardSearchResult] = []
    @State private var isSearching = false
    @State private var ownershipFilter = CollectionOwnershipFilter.all
    @State private var selectedSetName = ""
    @State private var selectedReleaseYear = 0
    @State private var sort = CollectionCardSort.releaseNewest

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14),
    ]

    private var availableSetNames: [String] {
        Array(Set(results.map(\.setName))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var availableReleaseYears: [Int] {
        Array(Set(results.compactMap { result in
            result.setReleaseDate.flatMap { Int($0.prefix(4)) }
        })).sorted(by: >)
    }

    private var visibleResults: [CatalogCardSearchResult] {
        results.filter { result in
            let isOwned = collectionStore.owns(cardID: result.card.id)
            let ownershipMatches: Bool = switch ownershipFilter {
            case .all: true
            case .owned: isOwned
            case .missing: !isOwned
            }
            return ownershipMatches
                && (selectedSetName.isEmpty || result.setName == selectedSetName)
                && (selectedReleaseYear == 0
                    || result.setReleaseDate?.hasPrefix(String(selectedReleaseYear)) == true)
        }.sorted(by: compareResults)
    }

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
                } else if visibleResults.isEmpty {
                    ContentUnavailableView(
                        "No Cards for These Filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another ownership, set, or release-year filter.")
                    )
                } else {
                    resultsContent
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Card, set, or number")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    searchFilterMenu
                }
            }
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

    @ViewBuilder
    private var resultsContent: some View {
        if SearchResultLayout(rawValue: resultLayout) == .grid {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(visibleResults) { result in
                        NavigationLink {
                            CatalogCardDetailView(card: result.card)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                CatalogCardTile(card: result.card)
                                Text(result.setName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .safeAreaPadding(.bottom, 86)
            }
        } else {
            List(visibleResults) { result in
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
                        Spacer()
                        if collectionStore.owns(cardID: result.card.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Owned")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var searchFilterMenu: some View {
        Menu("Filter, sort, and layout", systemImage: "line.3.horizontal.decrease.circle") {
            Menu("Ownership: \(ownershipFilter.title)") {
                ForEach(CollectionOwnershipFilter.allCases) { filter in
                    Button {
                        ownershipFilter = filter
                    } label: {
                        if ownershipFilter == filter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            }

            Menu(selectedSetName.isEmpty ? "Set: All" : "Set: \(selectedSetName)") {
                filterButton("All sets", isSelected: selectedSetName.isEmpty) {
                    selectedSetName = ""
                }
                ForEach(availableSetNames, id: \.self) { setName in
                    filterButton(setName, isSelected: selectedSetName == setName) {
                        selectedSetName = setName
                    }
                }
            }

            Menu(selectedReleaseYear == 0 ? "Release year: All" : "Release year: \(selectedReleaseYear)") {
                filterButton("All years", isSelected: selectedReleaseYear == 0) {
                    selectedReleaseYear = 0
                }
                ForEach(availableReleaseYears, id: \.self) { year in
                    filterButton(String(year), isSelected: selectedReleaseYear == year) {
                        selectedReleaseYear = year
                    }
                }
            }

            Menu("Sort: \(sort.title)") {
                ForEach(CollectionCardSort.allCases) { option in
                    filterButton(option.title, isSelected: sort == option) {
                        sort = option
                    }
                }
            }

            Menu("Layout: \((SearchResultLayout(rawValue: resultLayout) ?? .list).title)") {
                ForEach(SearchResultLayout.allCases) { layout in
                    Button {
                        resultLayout = layout.rawValue
                    } label: {
                        if resultLayout == layout.rawValue {
                            Label(layout.title, systemImage: "checkmark")
                        } else {
                            Label(layout.title, systemImage: layout.systemImage)
                        }
                    }
                }
            }

            Divider()
            Button("Reset filters", systemImage: "arrow.counterclockwise") {
                ownershipFilter = .all
                selectedSetName = ""
                selectedReleaseYear = 0
                sort = .releaseNewest
            }
        }
    }

    private func filterButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func compareResults(_ left: CatalogCardSearchResult, _ right: CatalogCardSearchResult) -> Bool {
        switch sort {
        case .releaseNewest:
            if left.setReleaseDate != right.setReleaseDate {
                return (left.setReleaseDate ?? "") > (right.setReleaseDate ?? "")
            }
        case .releaseOldest:
            if left.setReleaseDate != right.setReleaseDate {
                return (left.setReleaseDate ?? "9999") < (right.setReleaseDate ?? "9999")
            }
        case .setName:
            let comparison = left.setName.localizedCaseInsensitiveCompare(right.setName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        case .collectorNumber:
            let leftNumber = Int(left.card.localID) ?? .max
            let rightNumber = Int(right.card.localID) ?? .max
            if leftNumber != rightNumber { return leftNumber < rightNumber }
        case .cardName:
            let comparison = left.card.name.localizedCaseInsensitiveCompare(right.card.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }
        if left.setName != right.setName { return left.setName < right.setName }
        return left.card.localID.localizedStandardCompare(right.card.localID) == .orderedAscending
    }
}

struct CollectionView: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var cards: [CatalogCardSearchResult] = []
    @State private var pricesByCardID: [String: [CatalogPriceQuote]] = [:]
    @State private var isLoadingCards = false
    @State private var message: String?
    @State private var isCreatingFolder = false
    @State private var editingFolder: CustomCollectionFolder?

    private var ownedCardIDs: [String] {
        Array(Set(collectionStore.ownedEntries.map(\.cardID))).sorted()
    }

    private var ownedCardIDsKey: String {
        ownedCardIDs.joined(separator: "|")
    }

    private var valueSummary: CatalogValueSummary {
        CatalogValueCalculator.summary(
            entries: collectionStore.ownedEntries,
            prices: pricesByCardID,
            source: CatalogPriceSource(rawValue: preferredPriceSource) ?? .cardmarket
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !ownedCardIDs.isEmpty {
                    Section {
                        CollectionValueSummaryView(summary: valueSummary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if collectionStore.customFolders.isEmpty {
                        Button {
                            isCreatingFolder = true
                        } label: {
                            Label("Create your first folder", systemImage: "folder.badge.plus")
                        }
                    } else {
                        ForEach(collectionStore.customFolders) { folder in
                            NavigationLink {
                                CustomCollectionFolderDetailView(folder: folder)
                            } label: {
                                CustomCollectionFolderRow(folder: folder)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "slider.horizontal.3") {
                                    editingFolder = folder
                                }
                            }
                        }
                    }
                } header: {
                    Text("Custom folders")
                } footer: {
                    Text("Folders find cards by name. Ownership is shared with Sets and the rest of your collection.")
                }

                Section("Owned cards") {
                    if collectionStore.isInitialLoading || isLoadingCards && cards.isEmpty {
                        ProgressView("Loading your collection…")
                    } else if ownedCardIDs.isEmpty {
                        Text("No cards owned yet. Open a set or an All folder to start checking cards off.")
                            .foregroundStyle(.secondary)
                    } else if cards.isEmpty {
                        Label(
                            message
                                ?? collectionStore.loadMessage
                                ?? "Your quantities are safe and will appear after the catalog is available.",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(cards) { result in
                        NavigationLink {
                            CatalogCardDetailView(card: result.card)
                        } label: {
                            HStack(spacing: 12) {
                                CachedCardImage(reference: result.card.thumbnailArtworkReference)
                                    .frame(width: 52, height: 72)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.card.name)
                                        .font(.body.weight(.semibold))
                                    Text("\(result.setName) · #\(result.card.localID)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(collectionSummary(cardID: result.card.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New folder", systemImage: "folder.badge.plus") {
                        isCreatingFolder = true
                    }
                }
            }
            .sheet(isPresented: $isCreatingFolder) {
                CustomCollectionFolderEditorView(folder: nil)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingFolder) { folder in
                CustomCollectionFolderEditorView(folder: folder)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task(id: ownedCardIDsKey) {
                await loadCards()
            }
        }
    }

    private func collectionSummary(cardID: String) -> String {
        let entries = collectionStore.ownedEntries.filter { $0.cardID == cardID }
        let total = entries.reduce(0) { $0 + $1.quantity }
        let variants = entries
            .sorted { $0.variant.displayName < $1.variant.displayName }
            .map { "\($0.variant.displayName) ×\($0.quantity)" }
            .joined(separator: " · ")
        let copies = total == 1 ? "1 copy" : "\(total) copies"
        return variants.isEmpty ? copies : "\(copies) · \(variants)"
    }

    private func loadCards() async {
        guard !ownedCardIDs.isEmpty else {
            cards = []
            pricesByCardID = [:]
            return
        }
        isLoadingCards = true
        message = nil
        defer { isLoadingCards = false }
        do {
            let loadedCards = try await catalogStore.searchResults(cardIDs: ownedCardIDs)
            cards = loadedCards
            _ = await catalogStore.prepareVariants(for: loadedCards.map(\.card))
            pricesByCardID = (try? await catalogStore.prices(cardIDs: ownedCardIDs)) ?? [:]
        } catch {
            cards = []
            message = "Your quantities are safe, but their card details couldn’t be loaded."
        }
    }
}

private struct CustomCollectionFolderRow: View {
    let folder: CustomCollectionFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.body.weight(.semibold))
                Text("Matches “\(folder.cardNameQuery)” · \(folder.displayMode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CustomCollectionFolderEditorView: View {
    let folder: CustomCollectionFolder?
    @Environment(CollectionStore.self) private var collectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var cardNameQuery: String
    @State private var displayMode: CustomCollectionFolderDisplayMode
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var message: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedQuery: String {
        cardNameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(folder: CustomCollectionFolder?) {
        self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
        _cardNameQuery = State(initialValue: folder?.cardNameQuery ?? "")
        _displayMode = State(initialValue: folder?.displayMode ?? .allMatching)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder") {
                    TextField("Name, e.g. All Lucario", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Card name, e.g. Lucario", text: $cardNameQuery)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Show cards") {
                    Picker("Cards", selection: $displayMode) {
                        ForEach(CustomCollectionFolderDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(displayMode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("The folder updates automatically as the catalog and your ownership change.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if folder != nil {
                    Section {
                        Button("Delete Folder", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("Deleting a folder never removes cards or quantities from your collection.")
                    }
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(folder == nil ? "New folder" : "Edit folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty || trimmedQuery.isEmpty || isSaving)
                }
            }
            .alert("Delete \(folder?.name ?? "folder")?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) { deleteFolder() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your owned cards and quantities will stay unchanged.")
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty, !isSaving else { return }
        isSaving = true
        message = nil
        let timestamp = Date()
        let savedFolder = CustomCollectionFolder(
            id: folder?.id ?? UUID(),
            name: trimmedName,
            cardNameQuery: trimmedQuery,
            displayMode: displayMode,
            createdAt: folder?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        Task {
            do {
                try await collectionStore.saveCustomFolder(savedFolder)
                dismiss()
            } catch {
                message = "That folder couldn’t be saved. Please try again."
                isSaving = false
            }
        }
    }

    private func deleteFolder() {
        guard let folder, !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            do {
                try await collectionStore.deleteCustomFolder(id: folder.id)
                dismiss()
            } catch {
                message = "That folder couldn’t be deleted. Please try again."
                isSaving = false
            }
        }
    }
}

private enum CollectionCardSort: String, CaseIterable, Identifiable {
    case releaseNewest
    case releaseOldest
    case setName
    case collectorNumber
    case cardName

    var id: String { rawValue }
    var title: String {
        switch self {
        case .releaseNewest: "Release date (newest)"
        case .releaseOldest: "Release date (oldest)"
        case .setName: "Set name"
        case .collectorNumber: "Collector number"
        case .cardName: "Card name"
        }
    }
}

private enum CollectionOwnershipFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case missing

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct CustomCollectionFolderDetailView: View {
    let folder: CustomCollectionFolder
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var matches: [CatalogCardSearchResult] = []
    @State private var pricesByCardID: [String: [CatalogPriceQuote]] = [:]
    @State private var isLoading = true
    @State private var message: String?
    @State private var selectedVariantCard: CatalogCard?
    @State private var updatingCardIDs: Set<String> = []
    @State private var searchText = ""
    @State private var ownershipFilter: CollectionOwnershipFilter
    @State private var selectedSetName = ""
    @State private var selectedReleaseYear = 0
    @State private var sort = CollectionCardSort.releaseNewest

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14),
    ]

    init(folder: CustomCollectionFolder) {
        self.folder = folder
        _ownershipFilter = State(
            initialValue: folder.displayMode == .ownedOnly ? .owned : .all
        )
    }

    private var availableSetNames: [String] {
        Array(Set(matches.map(\.setName))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var availableReleaseYears: [Int] {
        Array(Set(matches.compactMap { result in
            result.setReleaseDate.flatMap { Int($0.prefix(4)) }
        })).sorted(by: >)
    }

    private var visibleMatches: [CatalogCardSearchResult] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return matches.filter { result in
            let isOwned = collectionStore.owns(cardID: result.card.id)
            let ownershipMatches: Bool = switch ownershipFilter {
            case .all: true
            case .owned: isOwned
            case .missing: !isOwned
            }
            let searchMatches = trimmedSearch.isEmpty
                || result.card.name.localizedCaseInsensitiveContains(trimmedSearch)
                || result.setName.localizedCaseInsensitiveContains(trimmedSearch)
                || result.card.localID.localizedCaseInsensitiveContains(trimmedSearch)
            let setMatches = selectedSetName.isEmpty || result.setName == selectedSetName
            let yearMatches = selectedReleaseYear == 0
                || result.setReleaseDate?.hasPrefix(String(selectedReleaseYear)) == true
            return ownershipMatches && searchMatches && setMatches && yearMatches
        }.sorted(by: compareResults)
    }

    private func compareResults(_ left: CatalogCardSearchResult, _ right: CatalogCardSearchResult) -> Bool {
        switch sort {
        case .releaseNewest:
            let leftDate = left.setReleaseDate ?? ""
            let rightDate = right.setReleaseDate ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
        case .releaseOldest:
            let leftDate = left.setReleaseDate ?? "9999"
            let rightDate = right.setReleaseDate ?? "9999"
            if leftDate != rightDate { return leftDate < rightDate }
        case .setName:
            let comparison = left.setName.localizedCaseInsensitiveCompare(right.setName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        case .collectorNumber:
            let leftNumber = Int(left.card.localID) ?? .max
            let rightNumber = Int(right.card.localID) ?? .max
            if leftNumber != rightNumber { return leftNumber < rightNumber }
        case .cardName:
            let comparison = left.card.name.localizedCaseInsensitiveCompare(right.card.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }
        if left.setName != right.setName { return left.setName < right.setName }
        return left.card.localID.localizedStandardCompare(right.card.localID) == .orderedAscending
    }

    private var ownedCount: Int {
        matches.reduce(into: 0) { count, result in
            if collectionStore.owns(cardID: result.card.id) { count += 1 }
        }
    }

    private var ownedPercentage: Int {
        guard !matches.isEmpty else { return 0 }
        return Int((Double(ownedCount) / Double(matches.count) * 100).rounded())
    }

    private var ownedMatchIDs: Set<String> {
        Set(matches.lazy.map(\.card.id).filter { collectionStore.owns(cardID: $0) })
    }

    private var ownedMatchIDsKey: String {
        ownedMatchIDs.sorted().joined(separator: "|")
    }

    private var valueSummary: CatalogValueSummary {
        CatalogValueCalculator.summary(
            entries: collectionStore.ownedEntries.filter { ownedMatchIDs.contains($0.cardID) },
            prices: pricesByCardID,
            source: CatalogPriceSource(rawValue: preferredPriceSource) ?? .cardmarket
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Matches card names containing “\(folder.cardNameQuery)”", systemImage: "text.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Text("\(ownedPercentage)% owned")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.12), in: Capsule())
                        Text("\(ownedCount) of \(matches.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if !ownedMatchIDs.isEmpty {
                        CollectionValueSummaryView(summary: valueSummary, title: "Folder value")
                            .padding(.top, 4)
                    }
                }

                if let message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isLoading && matches.isEmpty {
                    ProgressView("Finding matching cards…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if matches.isEmpty {
                    ContentUnavailableView(
                        "No Matching Cards",
                        systemImage: "rectangle.stack.badge.questionmark",
                        description: Text("Long-press this folder from Collection and edit its card-name rule.")
                    )
                } else if visibleMatches.isEmpty {
                    ContentUnavailableView(
                        "No Cards for These Filters",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another search, ownership filter, set, or release year.")
                    )
                } else {
                    HStack {
                        Text("\(visibleMatches.count) cards")
                            .font(.headline)
                        Spacer()
                        Text(ownershipFilter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visibleMatches) { result in
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink {
                                        CatalogCardDetailView(card: result.card)
                                    } label: {
                                        CatalogCardTile(card: result.card)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        handleCheckmarkTap(for: result.card)
                                    } label: {
                                        if updatingCardIDs.contains(result.card.id) {
                                            ProgressView()
                                                .controlSize(.small)
                                                .frame(width: 34, height: 34)
                                        } else {
                                            Image(
                                                systemName: collectionStore.owns(cardID: result.card.id)
                                                    ? "checkmark.circle.fill"
                                                    : "circle"
                                            )
                                            .font(.title2.weight(.semibold))
                                            .foregroundStyle(
                                                collectionStore.owns(cardID: result.card.id)
                                                    ? Color.accentColor
                                                    : Color.secondary
                                            )
                                            .frame(width: 34, height: 34)
                                        }
                                    }
                                    .background(.regularMaterial, in: Circle())
                                    .contentShape(Circle())
                                    .offset(x: 7, y: -7)
                                    .disabled(updatingCardIDs.contains(result.card.id))
                                    .contextMenu {
                                        Button("Choose printings", systemImage: "square.stack.3d.up") {
                                            selectedVariantCard = result.card
                                        }
                                    }
                                    .accessibilityLabel(
                                        collectionStore.owns(cardID: result.card.id)
                                            ? "Toggle standard printing for \(result.card.name)"
                                            : "Mark \(result.card.name) as owned"
                                    )
                                }

                                Text(result.setName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Card, set, or number")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Filter and sort", systemImage: "line.3.horizontal.decrease.circle") {
                    Menu("Ownership: \(ownershipFilter.title)") {
                        ForEach(CollectionOwnershipFilter.allCases) { filter in
                            Button {
                                ownershipFilter = filter
                            } label: {
                                if ownershipFilter == filter {
                                    Label(filter.title, systemImage: "checkmark")
                                } else {
                                    Text(filter.title)
                                }
                            }
                        }
                    }

                    Menu(selectedSetName.isEmpty ? "Set: All" : "Set: \(selectedSetName)") {
                        Button {
                            selectedSetName = ""
                        } label: {
                            if selectedSetName.isEmpty {
                                Label("All sets", systemImage: "checkmark")
                            } else {
                                Text("All sets")
                            }
                        }
                        ForEach(availableSetNames, id: \.self) { setName in
                            Button {
                                selectedSetName = setName
                            } label: {
                                if selectedSetName == setName {
                                    Label(setName, systemImage: "checkmark")
                                } else {
                                    Text(setName)
                                }
                            }
                        }
                    }

                    Menu(selectedReleaseYear == 0 ? "Release year: All" : "Release year: \(selectedReleaseYear)") {
                        Button {
                            selectedReleaseYear = 0
                        } label: {
                            if selectedReleaseYear == 0 {
                                Label("All years", systemImage: "checkmark")
                            } else {
                                Text("All years")
                            }
                        }
                        ForEach(availableReleaseYears, id: \.self) { year in
                            Button {
                                selectedReleaseYear = year
                            } label: {
                                if selectedReleaseYear == year {
                                    Label(String(year), systemImage: "checkmark")
                                } else {
                                    Text(String(year))
                                }
                            }
                        }
                    }

                    Menu("Sort: \(sort.title)") {
                        ForEach(CollectionCardSort.allCases) { option in
                            Button {
                                sort = option
                            } label: {
                                if sort == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Reset filters", systemImage: "arrow.counterclockwise") {
                        ownershipFilter = folder.displayMode == .ownedOnly ? .owned : .all
                        selectedSetName = ""
                        selectedReleaseYear = 0
                        sort = .releaseNewest
                    }
                }
            }
        }
        .sheet(item: $selectedVariantCard) { card in
            CatalogVariantPickerView(card: card)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: "\(folder.updatedAt.timeIntervalSince1970)|\(catalogStore.isPreparingSearchIndex)") {
            await loadMatches()
        }
        .task(id: ownedMatchIDsKey) {
            await loadPricesForOwnedMatches()
        }
    }

    private func handleCheckmarkTap(for card: CatalogCard) {
        guard !updatingCardIDs.contains(card.id) else { return }
        updatingCardIDs.insert(card.id)
        message = nil
        Task {
            defer { updatingCardIDs.remove(card.id) }
            do {
                if collectionStore.owns(cardID: card.id) {
                    try await collectionStore.removeAllOwnership(cardID: card.id)
                    return
                }
                let snapshot = try await catalogStore.details(for: card)
                let preference: [CatalogVariantKind] = [
                    .normal,
                    .holo,
                    .reverseHolo,
                    .firstEdition,
                    .watermarkedPromo,
                    .prerelease,
                    .prereleaseStaff,
                ]
                guard let standardVariant = preference.first(where: snapshot.variants.contains) else {
                    message = "Printing information isn’t available for \(card.name) yet."
                    return
                }
                try await collectionStore.setQuantity(
                    1,
                    cardID: card.id,
                    variant: standardVariant
                )
            } catch {
                message = "TallyDex couldn’t update \(card.name). Check your connection and try again."
            }
        }
    }

    private func loadMatches() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            matches = try await catalogStore.cards(matchingName: folder.cardNameQuery)
            await loadPricesForOwnedMatches()
            if matches.isEmpty, catalogStore.isPreparingSearchIndex {
                message = "TallyDex is preparing the complete card catalog. This folder will refresh automatically."
            }
        } catch {
            matches = []
            message = "Matching cards couldn’t be loaded. Please try again."
        }
    }

    private func loadPricesForOwnedMatches() async {
        let ownedCards = matches.lazy.map(\.card).filter {
            collectionStore.owns(cardID: $0.id)
        }
        let cards = Array(ownedCards)
        guard !cards.isEmpty else {
            pricesByCardID = [:]
            return
        }
        _ = await catalogStore.prepareVariants(for: cards)
        pricesByCardID = (try? await catalogStore.prices(cardIDs: cards.map(\.id))) ?? [:]
    }
}

struct SettingsView: View {
    @Environment(CollectionStore.self) private var collectionStore
    @AppStorage(SetsScope.storageKey) private var defaultSetsScope = SetsScope.all.rawValue
    @AppStorage(SetsBrowsingStyle.storageKey) private var browsingStyle = SetsBrowsingStyle.seriesFirst.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(CollectionSettings.allowsMultipleCopiesKey)
    private var allowsMultipleCopies = CollectionSettings.allowsMultipleCopiesDefault
    @AppStorage(CollectionSettings.defaultGoalKey)
    private var defaultCollectionGoal = CollectionSettings.defaultGoal.rawValue
    @AppStorage(CollectionSettings.defaultCustomIncludesSecretCardsKey)
    private var defaultCustomIncludesSecretCards = CollectionSettings.defaultCustomIncludesSecretCards
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @AppStorage(PricingSettings.cardmarketCountryKey)
    private var cardmarketCountry = CardmarketCountryPreference.all.rawValue
    @State private var defaultCustomVariants = CollectionSettings.preferredDefaultCustomVariants

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

                Section {
                    Picker("Default collection goal", selection: $defaultCollectionGoal) {
                        ForEach(CollectionGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Toggle("Track multiple copies", isOn: $allowsMultipleCopies)
                } header: {
                    Text("Collection")
                } footer: {
                    Text("The default goal applies to sets you have not configured yet. Existing set choices remain unchanged. " + (
                        allowsMultipleCopies
                            ? "Use − and + controls to save exact quantities for each printing."
                            : "A checkmark only records whether you own a printing. Existing quantities are preserved."
                    ))
                }

                if CollectionGoal(rawValue: defaultCollectionGoal) == .custom {
                    Section {
                        ForEach(CatalogVariantKind.allCases, id: \.self) { variant in
                            Toggle(
                                variant.displayName,
                                isOn: defaultCustomVariantBinding(for: variant)
                            )
                            .disabled(defaultCustomVariants == [variant])
                        }
                        Toggle("Include cards beyond the main set number", isOn: $defaultCustomIncludesSecretCards)
                    } header: {
                        Text("Default Custom Goal")
                    } footer: {
                        Text("New Custom sets will start with these printing types. At least one printing type must remain selected; each set can still be edited separately.")
                    }
                }

                Section {
                    Picker("Price source", selection: $preferredPriceSource) {
                        ForEach(CatalogPriceSource.allCases) { source in
                            Text("\(source.displayName) (\(source.currencyCode))")
                                .tag(source.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if CatalogPriceSource(rawValue: preferredPriceSource) == .cardmarket {
                        Picker("Listing country", selection: $cardmarketCountry) {
                            ForEach(CardmarketCountryPreference.allCases) { country in
                                Text(country.displayName).tag(country.rawValue)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Text("Prices")
                } footer: {
                    Text("Prices come through TCGdex and use each marketplace’s native currency. Exact per-printing marketplace IDs are used when TCGdex provides them. Cardmarket’s current TCGdex values are Europe-wide market aggregates; the listing-country preference is saved for seller-listing support and does not filter the aggregate yet.")
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
                    NavigationLink {
                        CollectionBackupsView()
                    } label: {
                        LabeledContent {
                            Text("\(collectionStore.backups.count)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Collection Backups", systemImage: "clock.arrow.circlepath")
                        }
                    }

                    NavigationLink {
                        CatalogIssueReportingView()
                    } label: {
                        Label("Missing or Incorrect Card", systemImage: "exclamationmark.bubble")
                    }
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

    private func defaultCustomVariantBinding(for variant: CatalogVariantKind) -> Binding<Bool> {
        Binding(
            get: { defaultCustomVariants.contains(variant) },
            set: { isIncluded in
                if isIncluded {
                    defaultCustomVariants.insert(variant)
                } else if defaultCustomVariants.count > 1 {
                    defaultCustomVariants.remove(variant)
                }
                UserDefaults.standard.set(
                    defaultCustomVariants.map(\.rawValue).sorted(),
                    forKey: CollectionSettings.defaultCustomVariantsKey
                )
            }
        )
    }
}

private struct CatalogIssueReportingView: View {
    private let newIssueURL = URL(
        string: "https://github.com/MiranoVerhoef/TallyDex/issues/new?template=missing-card.yml"
    )!
    private let issuesURL = URL(
        string: "https://github.com/MiranoVerhoef/TallyDex/issues?q=is%3Aissue%20label%3Acard-data"
    )!

    var body: some View {
        Form {
            Section("How Card Data Works") {
                Text("TallyDex uses TCGdex as its single source for card, set, and printing data. It does not create a missing card or printing unless that data is available through TCGdex.")
                Text("If something is missing or incorrect, report it on the TallyDex GitHub. The report can track the problem and link to any upstream TCGdex correction.")
            }

            Section {
                Link(destination: newIssueURL) {
                    Label("Report on GitHub", systemImage: "square.and.pencil")
                }
                Link(destination: issuesURL) {
                    Label("View Existing Reports", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("Card Data Reports")
            } footer: {
                Text("Include the set name and code, card name and collector number, what is missing or incorrect, and a reliable source or clear photo. A GitHub account is required to submit a report.")
            }
        }
        .navigationTitle("Card Data Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CollectionBackupsView: View {
    @Environment(CollectionStore.self) private var collectionStore
    @State private var selectedBackup: CollectionBackup?
    @State private var isRestoring = false
    @State private var message: String?

    var body: some View {
        Form {
            if collectionStore.backups.isEmpty {
                ContentUnavailableView(
                    "No Backups Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("TallyDex automatically creates one before a collection goal changes.")
                )
            } else {
                Section {
                    ForEach(collectionStore.backups) { backup in
                        Button {
                            selectedBackup = backup
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.reason)
                                    .foregroundStyle(.primary)
                                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isRestoring)
                    }
                } header: {
                    Text("Automatic Backups")
                } footer: {
                    Text("The newest 10 backups stay on this iPhone. Restoring also saves the current collection first, so the restore can be undone.")
                }
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Collection Backups")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Restore this collection backup?",
            isPresented: Binding(
                get: { selectedBackup != nil },
                set: { if !$0 { selectedBackup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive) {
                guard let backup = selectedBackup else { return }
                selectedBackup = nil
                restore(backup)
            }
            Button("Cancel", role: .cancel) {
                selectedBackup = nil
            }
        } message: {
            Text("This replaces current ownership, set goals, folders, wishlist, and notes with the saved snapshot. TallyDex will back up the current collection before restoring.")
        }
    }

    private func restore(_ backup: CollectionBackup) {
        guard !isRestoring else { return }
        isRestoring = true
        message = nil
        Task {
            defer { isRestoring = false }
            do {
                try await collectionStore.restoreBackup(backup)
                message = "Collection restored."
            } catch {
                message = "That backup couldn’t be restored. No collection data was changed."
            }
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
                Text("Missing or incorrect catalog data can be reported from Settings → Missing or Incorrect Card.")
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
