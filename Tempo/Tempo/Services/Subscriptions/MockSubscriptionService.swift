//
// MockSubscriptionService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import StoreKit

// MARK: - Mock Subscription Service

// For previews, tests, and ServiceContainer.mock().

@Observable
@MainActor
final class MockSubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
    private(set) var state: SubscriptionState = .free

    var isPro: Bool {
        state.isPro
    }

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

    /// Mock has no real StoreKit products; PaywallView falls back to static
    /// price copy when this is empty.
    func availableProducts() -> [Product] { [] }

    // MARK: - Test Helpers

    func simulateState(_ newState: SubscriptionState) {
        state = newState
    }
}
