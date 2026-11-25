//
// PlanStatus.swift
// Tempo
//
// What the Subscription page says about the user's plan, worked out in one
// place. The server decides whether an account is Pro, because the server is
// what gates every Pro feature (a subscription row, or the operator
// allowlist). The App Store, on the device, knows the details only Apple
// knows: a trial, a renewal that was turned off, a payment problem. This
// merges the two, and says so when they disagree.
//

import Foundation

// MARK: - ServerPlan

/// What `GET /v1/user/me` says about the plan: the same answer the gates use.
struct ServerPlan: Equatable, Sendable {
    let isPro: Bool
    /// The App Store product behind it. nil when Pro is granted without a purchase.
    let productId: String?
    /// When the subscription period ends. nil when Pro is granted without a purchase.
    let expiresAt: Date?

    init(isPro: Bool, productId: String? = nil, expiresAt: Date? = nil) {
        self.isPro = isPro
        self.productId = productId
        self.expiresAt = expiresAt
    }

    init(_ me: UserMeResponseDTO) {
        self.init(isPro: me.isPro, productId: me.productId, expiresAt: me.subscriptionExpiresAt)
    }

    static func fetch(apiClient: APIClient) async throws -> ServerPlan {
        let me: UserMeResponseDTO = try await apiClient.request(APIEndpoint<UserMeResponseDTO>.currentUser())
        return ServerPlan(me)
    }
}

// MARK: - PlanAction

/// The one main button under the plan.
enum PlanAction: Equatable, Sendable {
    /// Open the paywall.
    case showPaywall
    /// Open Apple's subscription page (change plan, renewal, payment method).
    case manageInAppStore
}

// MARK: - PlanStatus

struct PlanStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case free
        case trial
        case active
        /// Renewal is off: Pro until the period ends.
        case cancelled
        /// A payment failed; Apple is retrying and Pro stays on for now.
        case grace
        case expired
        /// Pro comes with the account (operator access), no purchase behind it.
        case included
    }

    let kind: Kind
    let isPro: Bool
    /// "Pro", "Pro · Trial", "Free".
    let title: String
    /// One plain line under the title.
    let subtitle: String
    /// The date that matters in this state, with what it is.
    let dateLabel: String?
    let date: Date?
    /// Where the trial started, so the bar can fill.
    let startDate: Date?
    let productName: String?
    let action: PlanAction?
    let actionTitle: String?
    /// Set when the server and the App Store disagree.
    let notice: String?

    // MARK: Resolving

    /// - Parameters:
    ///   - server: the server's answer, or nil when it hasn't answered yet.
    ///   - device: what the App Store says on this device.
    static func resolve(server: ServerPlan?, device: SubscriptionState) -> PlanStatus {
        if device.isPro {
            var status = fromDevice(device)
            if let server, !server.isPro {
                status = status.withNotice(
                    String(
                        localized: "We haven't confirmed this on our side yet, so some Pro features may stay locked. Restore purchases, or try again in a few minutes."
                    )
                )
            }
            return status
        }
        if let server, server.isPro {
            return fromServer(server)
        }
        return fromDevice(device)
    }

    private static func fromDevice(_ device: SubscriptionState) -> PlanStatus {
        switch device {
        case .free:
            return free
        case let .trial(startDate, endDate):
            return PlanStatus(
                kind: .trial, isPro: true, title: String(localized: "Pro · Trial"),
                subtitle: String(localized: "Full access while your trial runs."),
                dateLabel: String(localized: "Trial ends"), date: endDate, startDate: startDate, productName: nil,
                action: .manageInAppStore, actionTitle: String(localized: "Manage subscription"), notice: nil
            )
        case let .active(productId, expirationDate, isAutoRenewing):
            if isAutoRenewing {
                return PlanStatus(
                    kind: .active, isPro: true, title: String(localized: "Pro"),
                    subtitle: String(localized: "You have full access to Tempo Pro."),
                    dateLabel: String(localized: "Renews"), date: expirationDate, startDate: nil,
                    productName: productName(productId),
                    action: .manageInAppStore, actionTitle: String(localized: "Manage subscription"), notice: nil
                )
            }
            return PlanStatus(
                kind: .cancelled, isPro: true, title: String(localized: "Pro · Ends soon"),
                subtitle: String(localized: "Renewal is off. You keep Pro until this period ends."),
                dateLabel: String(localized: "Ends"), date: expirationDate, startDate: nil,
                productName: productName(productId),
                action: .manageInAppStore, actionTitle: String(localized: "Turn renewal back on"), notice: nil
            )
        case let .gracePeriod(productId, graceEndDate):
            return PlanStatus(
                kind: .grace, isPro: true, title: String(localized: "Pro · Payment problem"),
                subtitle: String(localized: "Apple couldn't take your payment. Pro stays on while it tries again."),
                dateLabel: String(localized: "Fix it by"), date: graceEndDate, startDate: nil,
                productName: productName(productId),
                action: .manageInAppStore, actionTitle: String(localized: "Update payment method"), notice: nil
            )
        case let .expired(lastProductId, expiredAt),
             let .churned(lastProductId, expiredAt):
            return PlanStatus(
                kind: .expired, isPro: false, title: String(localized: "Expired"),
                subtitle: String(localized: "Your Pro has ended. Subscribe again to get it back."),
                dateLabel: String(localized: "Ended"), date: expiredAt, startDate: nil,
                productName: productName(lastProductId),
                action: .showPaywall, actionTitle: String(localized: "Subscribe again"), notice: nil
            )
        }
    }

    /// Pro on the server with nothing on this device: operator access, or a
    /// subscription bought somewhere else.
    private static func fromServer(_ server: ServerPlan) -> PlanStatus {
        if let productId = server.productId, let expiresAt = server.expiresAt {
            return PlanStatus(
                kind: .active, isPro: true, title: String(localized: "Pro"),
                subtitle: String(localized: "You have full access to Tempo Pro."),
                dateLabel: activeUntilLabel, date: expiresAt, startDate: nil,
                productName: productName(productId),
                action: .manageInAppStore, actionTitle: String(localized: "Manage subscription"), notice: nil
            )
        }
        return PlanStatus(
            kind: .included, isPro: true, title: String(localized: "Pro · Included"),
            subtitle: String(localized: "Pro comes with your account. Nothing to pay."),
            dateLabel: nil, date: nil, startDate: nil, productName: nil,
            action: nil, actionTitle: nil, notice: nil
        )
    }

    private static let activeUntilLabel = String(localized: "Active until")

    private static let free = PlanStatus(
        kind: .free, isPro: false, title: String(localized: "plan.free", defaultValue: "Free", comment: "Name of the free plan (not the free time slot)"),
        subtitle: String(localized: "Upgrade to unlock everything Tempo offers."),
        dateLabel: nil, date: nil, startDate: nil, productName: nil,
        action: .showPaywall, actionTitle: String(localized: "Subscribe to Pro"), notice: nil
    )

    private static func productName(_ productId: String) -> String? {
        SubscriptionProduct(rawValue: productId)?.displayName
    }

    private func withNotice(_ text: String) -> PlanStatus {
        PlanStatus(
            kind: kind, isPro: isPro, title: title, subtitle: subtitle,
            dateLabel: dateLabel, date: date, startDate: startDate, productName: productName,
            action: action, actionTitle: actionTitle, notice: text
        )
    }

    // MARK: Countdown

    /// Whole days from `now` to the date that matters, rounded up, never negative.
    func daysLeft(now: Date = .now) -> Int? {
        guard let date else {
            return nil
        }
        return max(0, Int((date.timeIntervalSince(now) / 86400).rounded(.up)))
    }

    /// What the day count counts, for the states that count down.
    func countdownUnit(days: Int) -> String? {
        let one = days == 1
        switch kind {
        case .trial: return one ? String(localized: "day of trial left") : String(localized: "days of trial left")
        case .active:
            // The server alone can't say whether it renews, only when it ends.
            if dateLabel == Self.activeUntilLabel {
                return one ? String(localized: "day of Pro left") : String(localized: "days of Pro left")
            }
            return one ? String(localized: "day to renewal") : String(localized: "days to renewal")
        case .cancelled: return one ? String(localized: "day until it ends") : String(localized: "days until it ends")
        case .grace: return one ? String(localized: "day to fix it") : String(localized: "days to fix it")
        case .free,
             .expired,
             .included: return nil
        }
    }

    /// How far through the trial `now` is, 0...1. nil outside a trial.
    func trialProgress(now: Date = .now) -> Double? {
        guard kind == .trial, let startDate, let date else {
            return nil
        }
        let span = max(date.timeIntervalSince(startDate), 1)
        return min(max(now.timeIntervalSince(startDate), 0), span) / span
    }
}
