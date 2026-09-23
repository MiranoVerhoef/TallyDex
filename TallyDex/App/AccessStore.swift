import Foundation
import Observation
import Security
import StoreKit
import SwiftUI

enum AccessConfiguration {
    // Leave the public beta unlocked until the real App Store product, pricing,
    // grandfathering policy, and sandbox purchase flow have been approved.
    static let lifetimeProductID = "com.miranoverhoef.TallyDex.lifetime"
    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60
    static let productIDs = [lifetimeProductID] + CoffeeTipTier.allCases.map(\.productID)

    static var isEnforced: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AccessGateTesting")
#else
        false
#endif
    }
}

enum CoffeeTipTier: String, CaseIterable, Identifiable {
    case espresso
    case coffee = "regular"
    case largeCoffee = "large"
    case coffeeRound = "round"

    var id: String { rawValue }
    var productID: String { "com.miranoverhoef.TallyDex.coffee.\(rawValue)" }

    var title: String {
        switch self {
        case .espresso: "Espresso"
        case .coffee: "Coffee"
        case .largeCoffee: "Large coffee"
        case .coffeeRound: "Coffee round"
        }
    }

    static func matching(productID: String) -> Self? {
        allCases.first { $0.productID == productID }
    }
}

struct TrialAnchor: Codable, Equatable {
    let startedAt: Date
    var lastSeenAt: Date
}

enum AccessStatus: Equatable {
    case earlyAccess
    case checking
    case notStarted
    case trial(daysRemaining: Int)
    case expired
    case lifetime

    var canEdit: Bool {
        switch self {
        case .earlyAccess, .trial, .lifetime: true
        case .checking, .notStarted, .expired: false
        }
    }
}

enum AccessPolicy {
    static func status(
        enforced: Bool,
        hasVerifiedLifetime: Bool,
        anchor: TrialAnchor?,
        now: Date
    ) -> AccessStatus {
        guard enforced else { return .earlyAccess }
        if hasVerifiedLifetime { return .lifetime }
        guard let anchor else { return .notStarted }
        let effectiveNow = max(now, anchor.lastSeenAt)
        let remaining = anchor.startedAt.addingTimeInterval(AccessConfiguration.trialDuration)
            .timeIntervalSince(effectiveNow)
        guard remaining > 0 else { return .expired }
        return .trial(daysRemaining: max(1, Int(ceil(remaining / 86_400))))
    }

    static func advancing(_ anchor: TrialAnchor, to now: Date) -> TrialAnchor {
        TrialAnchor(startedAt: anchor.startedAt, lastSeenAt: max(anchor.lastSeenAt, now))
    }
}

enum AccessError: Error {
    case editingRequiresAccess
    case trialStorageUnavailable
}

private enum TrialStorageError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case invalidData

    var description: String {
        switch self {
        case .keychain(let status): "Keychain status \(status)"
        case .invalidData: "Trial data is invalid"
        }
    }
}

@MainActor
protocol TrialAnchorStoring {
    func load() throws -> TrialAnchor?
    func save(_ anchor: TrialAnchor) throws
}

@MainActor
struct KeychainTrialAnchorStore: TrialAnchorStoring {
    private let service: String
    private let account = "trial-anchor-v1"

    init(namespace: String = "") {
        service = "com.miranoverhoef.TallyDex.access" + (namespace.isEmpty ? "" : ".\(namespace)")
    }

    func load() throws -> TrialAnchor? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TrialStorageError.keychain(status) }
        guard let data = result as? Data,
              let anchor = try? JSONDecoder().decode(TrialAnchor.self, from: data) else {
            throw TrialStorageError.invalidData
        }
        return anchor
    }

    func save(_ anchor: TrialAnchor) throws {
        let data = try JSONEncoder().encode(anchor)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw TrialStorageError.keychain(status) }
        var insert = query
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw TrialStorageError.keychain(insertStatus) }
    }
}

@MainActor
@Observable
final class AccessStore {
    private let enforced: Bool
    private let anchorStore: any TrialAnchorStoring
    private let now: @Sendable () -> Date
    private var anchor: TrialAnchor?
    private var trialStorageReady = true
    private var hasVerifiedLifetime = false
    private var hasStarted = false
    @ObservationIgnored private var transactionTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    private(set) var status: AccessStatus
    private(set) var lifetimeProduct: Product?
    private(set) var tipProducts: [CoffeeTipTier: Product] = [:]
    private(set) var isWorking = false
    var message: String?
    var tipMessage: String?
    var isMembershipPresented = false

    var isEnforced: Bool { enforced }
    var canEdit: Bool {
        AccessPolicy.status(
            enforced: enforced,
            hasVerifiedLifetime: hasVerifiedLifetime,
            anchor: anchor,
            now: now()
        ).canEdit && status != .checking
    }

    init(
        enforced: Bool = AccessConfiguration.isEnforced,
        anchorStore: any TrialAnchorStoring = KeychainTrialAnchorStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.enforced = enforced
        self.anchorStore = anchorStore
        self.now = now
        if enforced {
            var loadFailed = false
            do {
                anchor = try anchorStore.load()
            } catch {
                trialStorageReady = false
                loadFailed = true
            }
            status = .checking
            if loadFailed {
                message = "Trial data could not be read on this device. No new trial was started."
            }
        } else {
            status = .earlyAccess
        }
    }

    deinit {
        transactionTask?.cancel()
        clockTask?.cancel()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        transactionTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    if CoffeeTipTier.matching(productID: transaction.productID) != nil {
                        self.tipMessage = "Thank you for supporting TallyDex!"
                        await transaction.finish()
                    } else if transaction.productID == AccessConfiguration.lifetimeProductID {
                        await transaction.finish()
                    }
                }
                if self.enforced { await self.refreshEntitlement() }
            }
        }
        if enforced {
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled { return }
                    self?.tick()
                }
            }
            await refreshEntitlement()
        }
        await finishUnfinishedTransactions()
        await loadProducts()
        tick()
    }

    func tick() {
        guard enforced else { return }
        if let anchor {
            let advanced = AccessPolicy.advancing(anchor, to: now())
            if advanced != anchor {
                do {
                    try anchorStore.save(advanced)
                    self.anchor = advanced
                } catch {
                    message = "Trial status could not be saved on this device."
                }
            }
        }
        status = AccessPolicy.status(
            enforced: enforced,
            hasVerifiedLifetime: hasVerifiedLifetime,
            anchor: anchor,
            now: now()
        )
    }

    func startTrial() throws {
        guard enforced else { return }
        guard trialStorageReady else { throw AccessError.trialStorageUnavailable }
        guard anchor == nil else { return }
        let start = now()
        let newAnchor = TrialAnchor(startedAt: start, lastSeenAt: start)
        try anchorStore.save(newAnchor)
        anchor = newAnchor
        message = nil
        tick()
    }

    func requireEditing() throws {
        guard canEdit else {
            isMembershipPresented = true
            throw AccessError.editingRequiresAccess
        }
    }

    func purchaseLifetime() async {
        guard enforced, !isWorking else { return }
        guard let lifetimeProduct else {
            message = "The purchase is not available right now. Try again later."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await lifetimeProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
                message = status == .lifetime ? nil : "Purchase verification is still pending."
            case .success(.unverified):
                message = "This purchase could not be verified. No access was granted."
            case .pending:
                message = "Purchase pending approval. Your collection remains safe."
            case .userCancelled:
                message = nil
            @unknown default:
                message = "The purchase could not be completed."
            }
        } catch {
            message = "The purchase could not be completed. Try again later."
        }
    }

    func restorePurchases() async {
        guard enforced, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = status == .lifetime ? "Lifetime access restored." : "No lifetime purchase was found."
        } catch {
            message = "Restore could not connect to the App Store. Try again later."
        }
    }

    func purchaseTip(_ tier: CoffeeTipTier) async {
        guard !isWorking else { return }
        guard let product = tipProducts[tier] else {
            tipMessage = "This coffee tip is not available right now."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard transaction.productID == tier.productID else {
                    tipMessage = "This purchase could not be matched to a coffee tip."
                    return
                }
                tipMessage = "Thank you for supporting TallyDex!"
                await transaction.finish()
            case .success(.unverified):
                tipMessage = "This tip could not be verified. Please check your purchase history."
            case .pending:
                tipMessage = "Your tip is pending approval. No further action is needed."
            case .userCancelled:
                tipMessage = nil
            @unknown default:
                tipMessage = "The tip could not be completed."
            }
        } catch {
            tipMessage = "The tip could not be completed. Please try again later."
        }
    }

    private func refreshEntitlement() async {
        var foundVerifiedPurchase = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == AccessConfiguration.lifetimeProductID,
                  transaction.revocationDate == nil else { continue }
            foundVerifiedPurchase = true
        }
        hasVerifiedLifetime = foundVerifiedPurchase
        tick()
    }

    private func finishUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if CoffeeTipTier.matching(productID: transaction.productID) != nil {
                tipMessage = "Thank you for supporting TallyDex!"
                await transaction.finish()
            } else if transaction.productID == AccessConfiguration.lifetimeProductID {
                if enforced { await refreshEntitlement() }
                await transaction.finish()
            }
        }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: AccessConfiguration.productIDs)
            lifetimeProduct = products.first {
                $0.id == AccessConfiguration.lifetimeProductID && $0.type == .nonConsumable
            }
            tipProducts = Dictionary(uniqueKeysWithValues: products.compactMap { product in
                guard product.type == .consumable,
                      let tier = CoffeeTipTier.matching(productID: product.id) else { return nil }
                return (tier, product)
            })
            if enforced && lifetimeProduct == nil {
                message = "Lifetime purchase is not available yet. Your collection remains readable and exportable."
            }
        } catch {
            if enforced {
                message = "The store is unavailable. Your collection remains readable and exportable."
            }
        }
    }
}

struct MembershipView: View {
    @Environment(AccessStore.self) private var access
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Access", value: statusText)
                    if access.isEnforced {
                        Text("Try every feature for 14 days. There is no subscription and no automatic charge.")
                        Text("After the trial, your collection stays readable and exportable. Editing requires one lifetime purchase.")
                        if let product = access.lifetimeProduct {
                            Text("Lifetime access: \(product.displayPrice).")
                        }
                    } else {
                        Text("Early access is unlocked. Purchases are not active in this build.")
                    }
                }

                if access.isEnforced {
                    Section {
                        if access.status == .notStarted {
                            Button("Start 14-Day Trial") {
                                do {
                                    try access.startTrial()
                                    access.isMembershipPresented = false
                                    dismiss()
                                } catch {
#if DEBUG
                                    access.message = "The trial could not start: \(error)."
#else
                                    access.message = "The trial could not start. Please try again."
#endif
                                }
                            }
                            .disabled(access.isWorking)
                        }
                        Button {
                            Task { await access.purchaseLifetime() }
                        } label: {
                            Label(
                                "Unlock Forever\(access.lifetimeProduct.map { " · \($0.displayPrice)" } ?? "")",
                                systemImage: "checkmark.seal"
                            )
                        }
                        .disabled(access.lifetimeProduct == nil || access.isWorking)

                        Button("Restore Purchase") {
                            Task { await access.restorePurchases() }
                        }
                        .disabled(access.isWorking)
                    } footer: {
                        Text("The displayed price comes from the App Store. Your trial never purchases anything automatically.")
                    }
                }

                if let message = access.message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Access & Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusText: String {
        switch access.status {
        case .earlyAccess: "Early access"
        case .checking: "Checking purchases…"
        case .notStarted: "Trial not started"
        case .trial(let days): "Trial · \(days) day\(days == 1 ? "" : "s") left"
        case .expired: "Trial ended"
        case .lifetime: "Lifetime access"
        }
    }
}

struct TipJarView: View {
    @Environment(AccessStore.self) private var access

    var body: some View {
        Form {
            Section {
                Text("Enjoying TallyDex? You can buy me a coffee. Tips are optional, can be repeated, and do not unlock app features.")
            }

            Section("Choose a coffee") {
                ForEach(CoffeeTipTier.allCases) { tier in
                    if let product = access.tipProducts[tier] {
                        Button {
                            Task { await access.purchaseTip(tier) }
                        } label: {
                            HStack {
                                Label(tier.title, systemImage: "cup.and.saucer.fill")
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(access.isWorking)
                        .accessibilityIdentifier("tip.\(tier.rawValue)")
                    }
                }
                if access.tipProducts.isEmpty {
                    Text("Coffee tips are unavailable right now.")
                        .foregroundStyle(.secondary)
                }
            }

            if let tipMessage = access.tipMessage {
                Section { Text(tipMessage).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Buy Me a Coffee")
        .navigationBarTitleDisplayMode(.inline)
    }
}
