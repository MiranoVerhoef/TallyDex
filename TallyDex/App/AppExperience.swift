import SwiftUI

enum AppExperienceSettings {
    static let introductionCompletedKey = "app.experience.introductionCompleted"
    static let lastSeenReleaseVersionKey = "app.experience.lastSeenReleaseVersion"

    static func nextDestination(
        introductionCompleted: Bool,
        lastSeenReleaseVersion: String,
        currentVersion: String
    ) -> AppExperienceDestination? {
        guard introductionCompleted else { return .introduction }
        guard lastSeenReleaseVersion != currentVersion else { return nil }
        return .whatsNew
    }
}

enum AppExperienceDestination: String, Identifiable {
    case introduction
    case whatsNew

    var id: String { rawValue }
}

struct AppReleaseNote: Identifiable, Equatable {
    let systemImage: String
    let title: String
    let detail: String

    var id: String { title }
}

struct AppRelease: Equatable {
    let version: String
    let headline: String
    let notes: [AppReleaseNote]
}

enum AppReleaseNotes {
    static let current = AppRelease(
        version: "0.9.14",
        headline: "A friendlier start, and clearer updates",
        notes: [
            AppReleaseNote(
                systemImage: "sparkles",
                title: "Set up TallyDex your way",
                detail: "A new introduction explains the main tools and lets you choose your browsing, appearance, and collection defaults before you begin."
            ),
            AppReleaseNote(
                systemImage: "slider.horizontal.3",
                title: "Preferences from the start",
                detail: "Choose how sets are organized, your collection goal, exact copy counts, and whether prices use Cardmarket in EUR or TCGplayer in USD."
            ),
            AppReleaseNote(
                systemImage: "list.bullet.rectangle.portrait.fill",
                title: "Richer, cleaner card details",
                detail: "Card pages now store and organize Pokédex numbers, HP, type, evolution, attacks, abilities, weaknesses, resistance, retreat cost, regulation marks, legality, and card text when TCGdex supplies them."
            ),
            AppReleaseNote(
                systemImage: "megaphone.fill",
                title: "Never miss an update",
                detail: "TallyDex now presents What’s New once after each app update. The latest notes and the introduction can also be opened again from Settings."
            ),
        ]
    )
}

struct IntroductionView: View {
    let onComplete: () -> Void

    @AppStorage(SetsScope.storageKey) private var defaultSetsScope = SetsScope.all.rawValue
    @AppStorage(SetsBrowsingStyle.storageKey) private var browsingStyle = SetsBrowsingStyle.seriesFirst.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(CollectionSettings.defaultGoalKey)
    private var defaultCollectionGoal = CollectionSettings.defaultGoal.rawValue
    @AppStorage(CollectionSettings.allowsMultipleCopiesKey)
    private var allowsMultipleCopies = CollectionSettings.allowsMultipleCopiesDefault
    @AppStorage(PricingSettings.sourceKey)
    private var preferredPriceSource = PricingSettings.defaultSource.rawValue
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    browsingPage.tag(1)
                    collectionPage.tag(2)
                    pricingPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: index == page ? 26 : 8, height: 8)
                            .animation(.snappy, value: page)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(pageCount)")
                .padding(.vertical, 14)

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Back") {
                            withAnimation { page -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(page == pageCount - 1 ? "Start Collecting" : "Continue") {
                        if page == pageCount - 1 {
                            onComplete()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { onComplete() }
                }
            }
        }
    }

    private var welcomePage: some View {
        onboardingPage {
            Image("TallyDexLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 210, maxHeight: 76)
                .accessibilityLabel("TallyDex")

            Text("Your collection, clearly counted")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Browse every English Pokémon TCG set, record exact printings, scan cards, and understand what you own—all with collection data stored on this iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                introductionFeature("square.grid.2x2", "Browse", "Explore sets and search the complete catalogue.")
                introductionFeature("camera.viewfinder", "Scan", "Use a card photo to find likely matches on device.")
                introductionFeature("rectangle.stack", "Collect", "Track goals, quantities, wishlists, and notes.")
            }
        }
    }

    private var browsingPage: some View {
        onboardingPage {
            onboardingHeading(
                systemImage: "square.grid.2x2.fill",
                title: "Choose how you browse",
                detail: "These become your defaults. Nothing here hides or changes collection data."
            )

            preferenceCard("Starting set view") {
                Picker("Starting set view", selection: $defaultSetsScope) {
                    ForEach(SetsScope.allCases) { scope in
                        Label(scope.title, systemImage: scope.systemImage)
                            .tag(scope.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.navigationLink)
            }

            preferenceCard("Set organization") {
                Picker("Set organization", selection: $browsingStyle) {
                    ForEach(SetsBrowsingStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(SetsBrowsingStyle.resolve(browsingStyle).description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            preferenceCard("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var collectionPage: some View {
        onboardingPage {
            onboardingHeading(
                systemImage: "rectangle.stack.fill",
                title: "Choose how you collect",
                detail: "These defaults apply only to sets you have not configured yet."
            )

            preferenceCard("Default collection goal") {
                Picker("Default collection goal", selection: $defaultCollectionGoal) {
                    ForEach(CollectionGoal.allCases, id: \.self) { goal in
                        Text(goal.displayName).tag(goal.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(CollectionGoal(rawValue: defaultCollectionGoal)?.explanation ?? CollectionGoal.normal.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            preferenceCard("Copies") {
                Toggle("Track exact copy counts", isOn: $allowsMultipleCopies)
                Text(allowsMultipleCopies
                     ? "Use − and + controls to record exact quantities."
                     : "Use simple checkmarks to record whether you own a printing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Label("Your collection stays local. TallyDex uses no analytics and creates safety backups before imports or restores.", systemImage: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))

            Text("You can change every preference later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var pricingPage: some View {
        onboardingPage {
            onboardingHeading(
                systemImage: "eurosign.arrow.circlepath",
                title: "Choose your price market",
                detail: "TallyDex keeps marketplace prices in their native currency, with no hidden conversion."
            )

            preferenceCard("Preferred prices") {
                Picker("Preferred prices", selection: $preferredPriceSource) {
                    ForEach(CatalogPriceSource.allCases) { source in
                        Text(source.currencyCode).tag(source.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                let source = CatalogPriceSource(rawValue: preferredPriceSource)
                    ?? PricingSettings.defaultSource
                HStack(spacing: 12) {
                    Image(systemName: source == .cardmarket ? "eurosign.circle.fill" : "dollarsign.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(source.displayName) · \(source.currencyCode)")
                            .font(.headline)
                        Text(source == .cardmarket
                             ? "European market prices supplied by TCGdex."
                             : "US market prices supplied by TCGdex.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }

            Label("Your choice controls collection values and the default price shown for each printing. Historical data remains separated by marketplace and currency.", systemImage: "chart.line.uptrend.xyaxis")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))

            Text("Everything is ready. You can revisit these choices in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func onboardingPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                content()
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
    }

    private func onboardingHeading(
        systemImage: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 20))
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func introductionFeature(
        _ systemImage: String,
        _ title: String,
        _ detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func preferenceCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WhatsNewView: View {
    let release: AppRelease
    var onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22))
                        Text("What’s New in TallyDex")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Version \(release.version)")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text(release.headline)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        ForEach(release.notes) { note in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: note.systemImage)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 44, height: 44)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title).font(.headline)
                                    Text(note.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                .frame(maxWidth: 620)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("What’s New")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let onDone {
                    Button("Continue", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.bar)
                }
            }
        }
    }
}
