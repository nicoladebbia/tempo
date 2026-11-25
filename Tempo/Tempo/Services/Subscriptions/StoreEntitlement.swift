//
// StoreEntitlement.swift
// Tempo
//
// What StoreKit tells us about the user's newest subscription, as plain values,
// and how that becomes a `SubscriptionState`. Kept apart from StoreKit itself
// so every state (trial, renewal off, payment problem, ended) can be tested
// without a purchase.
//

import Foundation

// MARK: - StoreEntitlement

struct StoreEntitlement: Equatable, Sendable {
    /// Where the subscription is in its renewal cycle (StoreKit's renewal state
    /// plus whether it will renew).
    enum Renewal: Equatable, Sendable {
        /// StoreKit gave no renewal info (offline, or the lookup failed).
        case unknown
        case willRenew
        /// The user turned renewal off: Pro until the period ends.
        case willNotRenew
        /// A payment failed and Apple is retrying while access continues.
        case gracePeriod(until: Date?)
        /// A payment failed, the grace period is over and Apple keeps retrying: no access.
        case billingRetry
        /// Refunded or revoked: no access.
        case revoked
        case expired
    }

    let productId: String
    let purchaseDate: Date
    let expirationDate: Date?
    /// The current period began with an introductory offer (the free trial).
    let isIntroOffer: Bool
    let renewal: Renewal
}

// MARK: - Mapping

extension SubscriptionState {
    /// More than this many days after it ended, a lapsed subscription counts as churned.
    static let churnAfterDays = 30

    static func resolve(_ entitlement: StoreEntitlement, now: Date = .now) -> SubscriptionState {
        let productId = entitlement.productId
        let expiry = entitlement.expirationDate

        switch entitlement.renewal {
        case .revoked:
            return lapsed(productId: productId, endedAt: min(expiry ?? now, now), now: now)
        case .billingRetry:
            return lapsed(productId: productId, endedAt: expiry ?? now, now: now)
        case let .gracePeriod(until):
            // Access continues: the period has ended but the grace period has not.
            return .gracePeriod(productId: productId, graceEndDate: until ?? expiry ?? now)
        case .expired:
            return lapsed(productId: productId, endedAt: expiry ?? now, now: now)
        case .unknown,
             .willRenew,
             .willNotRenew:
            break
        }

        guard let expiry, expiry > now else {
            return lapsed(productId: productId, endedAt: expiry ?? now, now: now)
        }
        if entitlement.isIntroOffer {
            return .trial(startDate: entitlement.purchaseDate, endDate: expiry)
        }
        return .active(
            productId: productId, expirationDate: expiry,
            isAutoRenewing: entitlement.renewal != .willNotRenew
        )
    }

    private static func lapsed(productId: String, endedAt: Date, now: Date) -> SubscriptionState {
        let days = Calendar.current.dateComponents([.day], from: endedAt, to: now).day ?? 0
        return days > churnAfterDays
            ? .churned(lastProductId: productId, expiredAt: endedAt)
            : .expired(lastProductId: productId, expiredAt: endedAt)
    }
}

// MARK: - Debug samples

#if DEBUG
    extension SubscriptionState {
        /// A state to show on the simulator without a purchase: launch with
        /// `-debugPlan trial|active|cancelled|grace|expired|free`. Dates are
        /// relative to now. Debug builds only.
        static func debugSample(named name: String, now: Date = .now) -> SubscriptionState? {
            let day: TimeInterval = 86400
            let product = SubscriptionProduct.monthly.rawValue
            switch name {
            case "free": return .free
            case "trial": return .trial(startDate: now - 2 * day, endDate: now + 5 * day)
            case "active": return .active(productId: product, expirationDate: now + 12 * day, isAutoRenewing: true)
            case "cancelled": return .active(productId: product, expirationDate: now + 4 * day, isAutoRenewing: false)
            case "grace": return .gracePeriod(productId: product, graceEndDate: now + 6 * day)
            case "expired": return .expired(lastProductId: product, expiredAt: now - 3 * day)
            default: return nil
            }
        }
    }
#endif
