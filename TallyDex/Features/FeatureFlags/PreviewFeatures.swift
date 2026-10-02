import SwiftUI

// Local preview controls, not security or paid-access entitlements. When the
// dashboard ships, set dashboardReleased to true and retire its code and keys.
enum PreviewFeatures {
    static let dashboardReleased = false
    static let dashboardUnlockedKey = "features.dashboard.previewUnlocked"
    static let dashboardEnabledKey = "features.dashboard.previewEnabled"

    static func acceptsDashboardCode(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines) == "Dashboard021026"
    }

    static func dashboardEnabled(unlocked: Bool, enabled: Bool,
                                 released: Bool = dashboardReleased) -> Bool {
        released || (unlocked && enabled)
    }
}

struct PreviewFeaturesSettingsView: View {
    @AppStorage(PreviewFeatures.dashboardUnlockedKey) private var unlocked = false
    @AppStorage(PreviewFeatures.dashboardEnabledKey) private var enabled = false
    @State private var code = ""
    @State private var message: String?
    @State private var invalidCode = false
    @FocusState private var isEnteringCode: Bool

    var body: some View {
        Form {
            if !PreviewFeatures.dashboardReleased {
                Section {
                    SecureField("Preview code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEnteringCode)
                        .accessibilityIdentifier("preview.code")
                        .onSubmit { unlock() }
                    Button("Enable Preview", action: unlock)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("preview.unlock")
                    if let message {
                        Text(message).font(.footnote)
                            .foregroundStyle(invalidCode ? Color.red : Color.secondary)
                            .accessibilityIdentifier("preview.message")
                    }
                } header: {
                    Text("Preview Access")
                } footer: {
                    Text("Preview features are unfinished and enabled only on this device. Codes do not unlock paid access or change your collection.")
                }
                if unlocked {
                    Section {
                        Toggle("Dashboard Preview", isOn: $enabled)
                            .accessibilityIdentifier("preview.dashboard")
                    } footer: {
                        Text("Show the experimental dashboard above Sets. You can turn it off at any time; your choice is kept across updates.")
                    }
                }
            } else {
                Section { Text("No preview features are currently available.") }
            }
        }
        .navigationTitle("Preview Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unlock() {
        guard PreviewFeatures.acceptsDashboardCode(code) else {
            invalidCode = true
            message = "Code not recognized."
            return
        }
        unlocked = true
        enabled = true
        code = ""
        isEnteringCode = false
        invalidCode = false
        message = "Dashboard preview enabled."
    }
}
