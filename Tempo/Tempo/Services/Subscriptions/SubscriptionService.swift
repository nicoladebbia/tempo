//
// SubscriptionService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os
import StoreKit

// MARK: - SubscriptionService

// Per BUILD_PLAN Step 20.1 — StoreKit 2 implementation.
// Per MONETIZATION_STRATEGY.md — $4.99/month, $39.99/year, 7-day trial.
// Per MONETIZATION_STRATEGY.md — Student pricing: $2.99/month, $23.99/year (40% off).
// Per DEPENDENCIES.md Section 2.15 — Raw StoreKit 2 (no RevenueCat).

@Observable
@MainActor
final class SubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
    // MARK: - State

    private(set) var state: SubscriptionState = .free

    var isPro: Bool {
        state.isPro
    }

    // MARK: - Private

    private var updateTask: Task<Void, Never>?
    /// True once `startObserving()` has begun. Guards against the app calling it
    /// again (scene re-creation re-runs `.task`), which would otherwise replace
    /// the live `Transaction.updates` listener and re-fetch products.
    private(set) var isObserving = false
    private var products: [Product] = []
    private let productIds = Set(SubscriptionProduct.allCases.map(\.rawValue))

    // MARK: - Public API

    /// Idempotent: the first call loads products, resolves the current entitlement
    /// (so a paying user is Pro right after launch) and starts the
    /// `Transaction.updates` listener (renewals, refunds, Ask-to-Buy approvals).
    func startObserving() async {
        guard !isObserving else {
            // A launch offline leaves the catalogue empty; try again so the
            // paywall isn't stuck with no plans until a relaunch.
            if products.isEmpty {
                await loadProducts()
            }
            return
        }
        isObserving = true
        await loadProducts()
        await refreshState()
        listenForTransactions()
    }

    func purchase(_ product: SubscriptionProduct) async throws {
        guard let storeProduct = products.first(where: { $0.id == product.rawValue }) else {
            Logger.subscription.error("Product not found: \(product.rawValue)")
            throw SubscriptionError.productNotFound
        }

        let result = try await storeProduct.purchase()

        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshState()
            Logger.subscription.info("Purchase successful: \(product.rawValue)")

        case .userCancelled:
            Logger.subscription.info("User cancelled purchase")
            throw SubscriptionError.userCancelled

        case .pending:
            Logger.subscription.info("Purchase pending approval")
            throw SubscriptionError.pending

        @unknown default:
            Logger.subscription.warning("Unknown purchase result")
            throw SubscriptionError.unknown
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshState()
        Logger.subscription.info("Purchases restored, state: \(String(describing: self.state))")
    }

    func refreshState() async {
        #if DEBUG
            // Simulator QA: `-debugPlan trial|active|cancelled|grace|expired|free`.
            if let name = UserDefaults.standard.string(forKey: "debugPlan"),
               let sample = SubscriptionState.debugSample(named: name)
            {
                state = sample
                return
            }
        #endif

        var latestTransaction: StoreKit.Transaction?
        var latestDate: Date = .distantPast

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else {
                continue
            }
            guard productIds.contains(transaction.productID) else {
                continue
            }

            if transaction.purchaseDate > latestDate {
                latestDate = transaction.purchaseDate
                latestTransaction = transaction
            }
        }

        // The renewal status also covers a subscription that is no longer an
        // entitlement (payment retrying, ended), which `currentEntitlements` omits.
        let status = await newestRenewalStatus()
        var renewal = StoreEntitlement.Renewal.unknown
        if let status, latestTransaction == nil || status.transaction.purchaseDate >= latestDate {
            latestTransaction = status.transaction
            renewal = status.renewal
        } else if let status, let latest = latestTransaction, status.transaction.id == latest.id {
            renewal = status.renewal
        }

        guard let transaction = latestTransaction else {
            state = .free
            return
        }

        state = SubscriptionState.resolve(
            StoreEntitlement(
                productId: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate,
                isIntroOffer: transaction.offer?.type == .introductory,
                renewal: renewal
            )
        )
    }

    // MARK: - Helpers

    /// Available StoreKit products for display.
    func availableProducts() -> [Product] {
        products.sorted { $0.price < $1.price }
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
            Logger.subscription.info("Loaded \(self.products.count) products")
        } catch {
            Logger.subscription.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    private func listenForTransactions() {
        updateTask?.cancel()
        updateTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else {
                    return
                }
                guard let transaction = try? checkVerified(result) else {
                    continue
                }
                await transaction.finish()
                await refreshState()
            }
        }
    }

    /// The newest of our subscriptions in the App Store's renewal list, with
    /// where it stands: renewing, renewal off, payment problem, ended.
    private func newestRenewalStatus() async -> (transaction: StoreKit.Transaction, renewal: StoreEntitlement.Renewal)? {
        guard let groupID = products.first?.subscription?.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: groupID)
        else {
            return nil
        }
        var newest: (transaction: StoreKit.Transaction, renewal: StoreEntitlement.Renewal)?
        for status in statuses {
            guard let transaction = try? checkVerified(status.transaction),
                  productIds.contains(transaction.productID)
            else {
                continue
            }
            if let current = newest, current.transaction.purchaseDate >= transaction.purchaseDate {
                continue
            }
            newest = (transaction, renewal(for: status))
        }
        return newest
    }

    private func renewal(for status: Product.SubscriptionInfo.Status) -> StoreEntitlement.Renewal {
        let info = try? checkVerified(status.renewalInfo)
        switch status.state {
        case .subscribed:
            guard let info else {
                return .unknown
            }
            return info.willAutoRenew ? .willRenew : .willNotRenew
        case .inGracePeriod:
            return .gracePeriod(until: info?.gracePeriodExpirationDate)
        case .inBillingRetryPeriod:
            return .billingRetry
        case .revoked:
            return .revoked
        case .expired:
            return .expired
        default:
            return .unknown
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(value):
            return value
        case let .unverified(_, error):
            throw SubscriptionError.verificationFailed(error)
        }
    }
}

// MARK: - SubscriptionError

enum SubscriptionError: LocalizedError {
    case productNotFound
    case userCancelled
    case pending
    case unknown
    case verificationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .productNotFound: String(localized: "Subscription product not found.")
        case .userCancelled: String(localized: "Purchase was cancelled.")
        case .pending: String(localized: "Purchase is pending approval.")
        case .unknown: String(localized: "An unknown error occurred.")
        case .verificationFailed: String(localized: "Transaction verification failed.")
        }
    }
}
