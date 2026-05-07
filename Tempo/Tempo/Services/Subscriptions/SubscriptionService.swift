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
    private var products: [Product] = []
    private let productIds = Set(SubscriptionProduct.allCases.map(\.rawValue))

    // MARK: - Public API

    func startObserving() async {
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

        guard let transaction = latestTransaction else {
            state = .free
            return
        }

        updateState(from: transaction)
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

    private func updateState(from transaction: StoreKit.Transaction) {
        let productId = transaction.productID
        let now = Date()

        // Check if in trial
        if let offer = transaction.offer, offer.type == .introductory,
           let expirationDate = transaction.expirationDate,
           expirationDate > now
        {
            state = .trial(startDate: transaction.purchaseDate, endDate: expirationDate)
            return
        }

        // Check if active
        if let expirationDate = transaction.expirationDate, expirationDate > now {
            // Check for grace period (revocation date present means billing issue)
            if transaction.revocationDate != nil {
                state = .gracePeriod(productId: productId, graceEndDate: expirationDate)
            } else {
                let isAutoRenewing = transaction.expirationDate != nil
                    && transaction.revocationDate == nil
                state = .active(
                    productId: productId,
                    expirationDate: expirationDate,
                    isAutoRenewing: isAutoRenewing
                )
            }
            return
        }

        // Expired
        let expiredAt = transaction.expirationDate ?? now
        let daysSinceExpiry = Calendar.current.dateComponents([.day], from: expiredAt, to: now).day ?? 0

        if daysSinceExpiry > 30 {
            state = .churned(lastProductId: productId, expiredAt: expiredAt)
        } else {
            state = .expired(lastProductId: productId, expiredAt: expiredAt)
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
        case .productNotFound: "Subscription product not found."
        case .userCancelled: "Purchase was cancelled."
        case .pending: "Purchase is pending approval."
        case .unknown: "An unknown error occurred."
        case .verificationFailed: "Transaction verification failed."
        }
    }
}
