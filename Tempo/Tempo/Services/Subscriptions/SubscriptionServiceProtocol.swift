//
// SubscriptionServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import StoreKit

// MARK: - SubscriptionServiceProtocol

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

    /// StoreKit products available for purchase, sorted for display.
    /// Mock implementations may return an empty array (previews fall back
    /// to static price copy).
    func availableProducts() -> [Product]
}

// MARK: - SubscriptionState

// Per STATE_MACHINES.md Section 15

enum SubscriptionState: Codable, Equatable {
    case free
    case trial(startDate: Date, endDate: Date)
    case active(productId: String, expirationDate: Date, isAutoRenewing: Bool)
    case gracePeriod(productId: String, graceEndDate: Date)
    case expired(lastProductId: String, expiredAt: Date)
    case churned(lastProductId: String, expiredAt: Date)

    var isPro: Bool {
        switch self {
        case .free,
             .expired,
             .churned: false
        case .trial,
             .active,
             .gracePeriod: true
        }
    }
}

// MARK: - SubscriptionProduct

// Per MONETIZATION_STRATEGY.md — Two products in tempo_pro group.

enum SubscriptionProduct: String, CaseIterable {
    case monthly = "com.tempo.pro.monthly"
    case annual = "com.tempo.pro.annual"
    case studentMonthly = "com.tempo.pro.student.monthly"
    case studentAnnual = "com.tempo.pro.student.annual"

    var displayName: String {
        switch self {
        case .monthly,
             .studentMonthly: "Monthly"
        case .annual,
             .studentAnnual: "Annual"
        }
    }

    /// Whether this is a student-discounted product.
    var isStudent: Bool {
        switch self {
        case .studentMonthly,
             .studentAnnual: true
        case .monthly,
             .annual: false
        }
    }

    /// The student equivalent of a standard product, or self if already student.
    var studentVariant: SubscriptionProduct {
        switch self {
        case .monthly: .studentMonthly
        case .annual: .studentAnnual
        case .studentMonthly,
             .studentAnnual: self
        }
    }

    /// The standard equivalent of a student product, or self if already standard.
    var standardVariant: SubscriptionProduct {
        switch self {
        case .studentMonthly: .monthly
        case .studentAnnual: .annual
        case .monthly,
             .annual: self
        }
    }
}
