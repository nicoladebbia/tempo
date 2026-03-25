import Foundation

// MARK: - Subscription Service Protocol
// Per STATE_MACHINES.md Section 15 — Subscription state machine.
// Per MONETIZATION_STRATEGY.md — Free/Pro tier split with StoreKit 2.

@MainActor
protocol SubscriptionServiceProtocol: AnyObject, Sendable {

    /// Current subscription state.
    var state: SubscriptionState { get }

    /// Whether the user currently has Pro access.
    var isPro: Bool { get }

    /// Start observing StoreKit transaction updates.
    func startObserving() async

    /// Purchase a subscription product.
    func purchase(_ product: SubscriptionProduct) async throws

    /// Restore previous purchases.
    func restorePurchases() async throws

    /// Refresh entitlement state from StoreKit.
    func refreshState() async
}

// MARK: - Subscription State
// Per STATE_MACHINES.md Section 15

enum SubscriptionState: Codable, Equatable, Sendable {
    case free
    case trial(startDate: Date, endDate: Date)
    case active(productId: String, expirationDate: Date, isAutoRenewing: Bool)
    case gracePeriod(productId: String, graceEndDate: Date)
    case expired(lastProductId: String, expiredAt: Date)
    case churned(lastProductId: String, expiredAt: Date)

    var isPro: Bool {
        switch self {
        case .free, .expired, .churned: return false
        case .trial, .active, .gracePeriod: return true
        }
    }
}

// MARK: - Subscription Product
// Per MONETIZATION_STRATEGY.md — Two products in tempo_pro group.

enum SubscriptionProduct: String, CaseIterable, Sendable {
    case monthly = "com.tempo.pro.monthly"
    case annual = "com.tempo.pro.annual"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }
}
