import Foundation

// MARK: - Mock Subscription Service
// For previews, tests, and ServiceContainer.mock().

@Observable
@MainActor
final class MockSubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {

    private(set) var state: SubscriptionState = .free

    var isPro: Bool { state.isPro }

    func startObserving() async {}

    func purchase(_ product: SubscriptionProduct) async throws {
        // Simulate successful purchase
        state = .active(
            productId: product.rawValue,
            expirationDate: Calendar.current.date(byAdding: .month, value: 1, to: .now)!,
            isAutoRenewing: true
        )
    }

    func restorePurchases() async throws {}

    func refreshState() async {}

    // MARK: - Test Helpers

    func simulateState(_ newState: SubscriptionState) {
        state = newState
    }
}
