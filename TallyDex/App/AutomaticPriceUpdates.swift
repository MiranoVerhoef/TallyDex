import BackgroundTasks
import Foundation
import Observation
import SwiftUI
import UIKit

enum AutomaticPriceUpdateSettings {
    static let enabledKey = "pricing.automaticUpdates"
    static let backgroundKey = "pricing.backgroundUpdates"
    static let lastCheckKey = "pricing.automaticLastCheck"
    static let retryAfterKey = "pricing.automaticRetryAfter"
    static let taskIdentifier = "com.miranoverhoef.TallyDex.prices.refresh"
    static let explanation = "Prices update for owned cards first, then My Sets. Background updates let iOS check while TallyDex is closed, using internet data and battery.\n\nOnly card IDs are requested from TCGdex. Your collection file, notes and photos are not uploaded.\n\niOS chooses when updates run and may pause them in Low Power Mode or after you force-quit."
}

struct AutomaticPriceTarget: Equatable, Sendable {
    let cardID: String
    let isOwned: Bool
    let lastAttempt: Date?
    let lastSuccess: Date?
}

enum AutomaticPriceUpdatePolicy {
    static func attemptKey(_ id: String) -> String { "catalog.price.auto.\(id).attempt" }
    static func successKey(_ id: String) -> String { "catalog.price.auto.\(id).success" }

    static func dueTargets(_ targets: [AutomaticPriceTarget], now: Date, limit: Int) -> [AutomaticPriceTarget] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        return Array(targets.filter { target in
            if let success = target.lastSuccess, success >= today { return false }
            // Failed/offline requests and cards without prices must not spin.
            if let attempt = target.lastAttempt, now.timeIntervalSince(attempt) < 6 * 60 * 60,
               target.lastSuccess.map({ attempt > $0 }) ?? true { return false }
            return true
        }.sorted {
            if $0.isOwned != $1.isOwned { return $0.isOwned }
            let left = $0.lastAttempt ?? .distantPast
            let right = $1.lastAttempt ?? .distantPast
            return left == right ? $0.cardID < $1.cardID : left < right
        }.prefix(max(0, limit)))
    }
}

struct AutomaticPriceUpdateContext: Equatable {
    let active: Bool
    let enabled: Bool
    let ready: Bool
    let ownedIDs: Set<String>
    let collectingSetIDs: Set<String>
}

/// One bounded queue shared by foreground catch-up and the OS refresh handler.
/// It deliberately never writes to CollectionStore or hydrates card printings.
@MainActor
@Observable
final class AutomaticPriceUpdater {
    private(set) var isRunning = false
    private(set) var checkedCount = 0
    private(set) var status = ""

    func run(
        catalog: CatalogStore, ownedIDs: Set<String>, collectingSetIDs: Set<String>,
        background: Bool, defaults: UserDefaults = .standard
    ) async {
        guard !isRunning, defaults.object(forKey: AutomaticPriceUpdateSettings.enabledKey) as? Bool ?? true,
              !background || defaults.bool(forKey: AutomaticPriceUpdateSettings.backgroundKey),
              Date().timeIntervalSince1970 >= defaults.double(forKey: AutomaticPriceUpdateSettings.retryAfterKey),
              !Task.isCancelled else { return }
        isRunning = true
        checkedCount = 0
        defer {
            isRunning = false
            if checkedCount > 0 { catalog.automaticPricesDidUpdate() }
        }
        do {
            let targets = try await catalog.automaticPriceTargets(
                ownedIDs: ownedIDs, collectingSetIDs: collectingSetIDs
            )
            // Serial requests bound provider load. Repeated foreground batches
            // resume with the least recently attempted eligible card.
            let due = AutomaticPriceUpdatePolicy.dueTargets(
                targets, now: Date(), limit: background ? 60 : 120
            )
            let deadline = ContinuousClock.now.advanced(by: .seconds(background ? 22 : 90))
            var failures = 0
            for target in due {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline,
                      defaults.object(forKey: AutomaticPriceUpdateSettings.enabledKey) as? Bool ?? true,
                      !background || defaults.bool(forKey: AutomaticPriceUpdateSettings.backgroundKey) else { break }
                do {
                    try await catalog.refreshAutomaticPrice(cardID: target.cardID)
                    checkedCount += 1
                    defaults.set(Date().timeIntervalSince1970, forKey: AutomaticPriceUpdateSettings.lastCheckKey)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures += 1
                    // An offline connection or upstream outage should not walk
                    // the whole collection. Attempts persist across launches.
                    if failures >= 3 {
                        defaults.set(Date().addingTimeInterval(15 * 60).timeIntervalSince1970,
                                     forKey: AutomaticPriceUpdateSettings.retryAfterKey)
                        break
                    }
                }
                try await Task.sleep(for: .milliseconds(150))
            }
            status = failures > 0 ? "Some prices couldn’t be checked. TallyDex will retry later." : ""
            if checkedCount > 0 { _ = try await catalog.applyPriceHistoryRetention() }
        } catch is CancellationError {
            // iOS expiration or leaving the foreground cancels networking too.
        } catch {
            status = "Prices couldn’t be checked. TallyDex will retry later."
        }
    }

    static func schedule(defaults: UserDefaults = .standard) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AutomaticPriceUpdateSettings.taskIdentifier)
        guard defaults.object(forKey: AutomaticPriceUpdateSettings.enabledKey) as? Bool ?? true,
              defaults.bool(forKey: AutomaticPriceUpdateSettings.backgroundKey) else { return }
        let request = BGAppRefreshTaskRequest(identifier: AutomaticPriceUpdateSettings.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
        // Scheduling is best-effort (unavailable on some simulators or when
        // system refresh is disabled). Foreground updates remain available.
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct AutomaticPriceUpdatesSettingsView: View {
    @Environment(AutomaticPriceUpdater.self) private var updater
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AutomaticPriceUpdateSettings.enabledKey) private var enabled = true
    @AppStorage(AutomaticPriceUpdateSettings.backgroundKey) private var background = false
    @AppStorage(AutomaticPriceUpdateSettings.lastCheckKey) private var lastCheck = 0.0
    @State private var showsExplanation = false
    @State private var systemStatus = UIApplication.shared.backgroundRefreshStatus

    var body: some View {
        Form {
            Section {
                Toggle("Automatic price updates", isOn: $enabled)
                    .accessibilityIdentifier("prices.automatic")
                Toggle("Allow background updates", isOn: $background)
                    .disabled(!enabled)
                    .accessibilityIdentifier("prices.background")
            } header: {
                HStack {
                    Text("Price History")
                    Spacer()
                    Button { showsExplanation = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About automatic price updates")
                }
            } footer: {
                Text("Owned cards first, then My Sets. One observation per day when a check succeeds; missed days are not filled in.")
            }

            Section("Status") {
                LabeledContent("Last successful check") {
                    if lastCheck > 0 {
                        Text(Date(timeIntervalSince1970: lastCheck), style: .relative)
                    } else {
                        Text("Not yet checked")
                    }
                }
                if updater.isRunning {
                    Label("Updating prices…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                if !updater.status.isEmpty { Text(updater.status).foregroundStyle(.secondary) }
                if background && enabled {
                    LabeledContent("iOS Background App Refresh", value: systemStatus == .available ? "Available" : "Managed by iOS")
                    if systemStatus == .denied {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Text("iOS chooses when to refresh. Updates also catch up while you use TallyDex.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Automatic Updates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsExplanation) {
            HelpInformationView(title: "Automatic price updates", message: AutomaticPriceUpdateSettings.explanation)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { systemStatus = UIApplication.shared.backgroundRefreshStatus }
        }
    }
}
