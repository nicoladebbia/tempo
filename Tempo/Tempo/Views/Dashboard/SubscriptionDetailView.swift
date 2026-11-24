//
//  SubscriptionDetailView.swift
//  Tempo
//
//  Subscription: the plan, what it unlocks and when it renews.
//

import SwiftUI

// MARK: - SubscriptionDetailView

/// Surfaces the real subscription state (plan, renewal/expiry, trial
/// countdown) that the root only showed as a single word.
struct SubscriptionDetailView: View {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var isRestoring = false
    @State
    private var restoreError: String?

    private var state: SubscriptionState {
        services.subscriptions.state
    }

    /// What Pro gives, in the words the paywall uses.
    private static let benefits: [(icon: String, text: String)] = [
        ("sparkles", "Recovery insights from Whoop & wearables"),
        ("brain.head.profile", "AI-powered workout programming"),
        ("fork.knife", "AI nutrition coaching & meal plans"),
        ("chart.line.uptrend.xyaxis", "Progress charts & weekly reports"),
    ]

    private var subscribeButton: some View {
        Button { showPaywall = true } label: {
            Label("Subscribe to Pro", systemImage: "sparkles")
        }
        .buttonStyle(.tidePrimary)
    }

    var body: some View {
        TideSettingsPage {
            planCard

            benefitsCard

            if !state.isPro, typeSize.isAccessibilitySize {
                // Too big to pin: the button follows the page.
                subscribeButton
            }

            SettingsFormCard(title: "Details") {
                SettingsInfoRow(
                    label: "Status",
                    value: planTitle,
                    icon: "checkmark.seal.fill",
                    iconTint: state.isPro ? mood.accent : Tide.text3,
                    valueColor: state.isPro ? mood.accent : Tide.text3
                )
                if let renewal = renewalLine {
                    SettingsRowDivider()
                    SettingsInfoRow(
                        label: renewal.label,
                        value: renewal.value,
                        icon: "calendar"
                    )
                }
                if let plan = productLine {
                    SettingsRowDivider()
                    SettingsInfoRow(label: "Plan", value: plan, icon: "tag.fill")
                }
            }

            SettingsFormCard(footnote: restoreError, footnoteColor: Tide.danger) {
                Button { Task { await restore() } } label: {
                    SettingsActionRow(icon: "arrow.clockwise", title: "Restore Purchases", tint: Tide.text)
                }
                .buttonStyle(.tideSettingsRow)
                .disabled(isRestoring)
            }
        }
        .safeAreaBar(edge: .bottom) {
            // The way in is under the thumb, on the free plan only.
            if !state.isPro, !typeSize.isAccessibilitySize {
                subscribeButton
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s2)
            }
        }
        .tideCovered(showPaywall)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The plan as a mark and a name; the days that matter under it.
    private var planCard: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return TideSettingsHero {
            layout {
                TideIconTile(
                    systemName: state.isPro ? "crown.fill" : "crown",
                    tint: state.isPro ? Tide.streak : Tide.text3,
                    size: Tide.settingsBigTile
                )
                VStack(alignment: .leading, spacing: Tide.hair) {
                    TideLabel("Your plan")
                    Text(planTitle)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(planSubtitle)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if let clock = countdown {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideNumber(
                        "\(clock.days)", unit: clock.unit,
                        size: Tide.numeralL, relativeTo: .largeTitle, color: clock.tint
                    )
                    .contentTransition(.numericText())
                    if let progress = clock.progress {
                        TideLevelBar(progress: progress, color: clock.tint, height: Tide.bar)
                            .background(Tide.fill, in: .capsule)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, Tide.s2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What Pro unlocks: locked on the free plan, ticked on Pro.
    private var benefitsCard: some View {
        TideSettingsSection(title: state.isPro ? "Your Pro includes" : "What Pro unlocks") {
            ForEach(Array(Self.benefits.enumerated()), id: \.offset) { index, benefit in
                if index > 0 {
                    SettingsRowDivider()
                }
                TideSettingsRowLine {
                    HStack(spacing: Tide.s3) {
                        SettingsIconTile(systemName: benefit.icon, tint: state.isPro ? mood.accent : Tide.text3)
                        Text(benefit.text)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(state.isPro ? Tide.text : Tide.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } trailing: {
                    Image(systemName: state.isPro ? "checkmark.circle.fill" : "lock.fill")
                        .font(Tide.headline)
                        .foregroundStyle(state.isPro ? mood.accent : Tide.text3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
                .accessibilityElement(children: .combine)
                .accessibilityValue(state.isPro ? "Included" : "Locked")
            }
        }
    }

    /// Whole days until the date that matters for this state, with what the
    /// number counts. The trial bar fills from the trial's start to its end.
    private var countdown: (days: Int, unit: String, tint: Color, progress: Double?)? {
        func days(until date: Date) -> Int {
            max(0, Int((date.timeIntervalSinceNow / 86400).rounded(.up)))
        }
        switch state {
        case let .trial(startDate, endDate):
            let left = days(until: endDate)
            let span = max(endDate.timeIntervalSince(startDate), 1)
            let elapsed = min(max(Date().timeIntervalSince(startDate), 0), span)
            return (left, left == 1 ? "day of trial left" : "days of trial left", mood.accent, elapsed / span)
        case let .active(_, expirationDate, isAutoRenewing):
            let left = days(until: expirationDate)
            let unit = isAutoRenewing
                ? (left == 1 ? "day to renewal" : "days to renewal")
                : (left == 1 ? "day until it ends" : "days until it ends")
            return (left, unit, mood.accent, nil)
        case let .gracePeriod(_, graceEndDate):
            let left = days(until: graceEndDate)
            return (left, left == 1 ? "day of grace left" : "days of grace left", Tide.danger, nil)
        case .free,
             .expired,
             .churned:
            return nil
        }
    }

    private var planTitle: String {
        switch state {
        case .free: "Free"
        case .trial: "Pro · Trial"
        case .active: "Pro"
        case .gracePeriod: "Pro · Billing issue"
        case .expired,
             .churned: "Expired"
        }
    }

    private var planSubtitle: String {
        if case .gracePeriod = state {
            return "There is a billing problem. Pro stays on until the grace period ends."
        }
        return state.isPro ? "You have full access to Tempo Pro." : "Upgrade to unlock everything Tempo offers."
    }

    private var renewalLine: (label: String, value: String)? {
        switch state {
        case let .trial(_, endDate): ("Trial ends", Self.dateString(endDate))
        case let .active(_, expirationDate, isAutoRenewing):
            (isAutoRenewing ? "Renews" : "Expires", Self.dateString(expirationDate))
        case let .gracePeriod(_, graceEndDate): ("Grace ends", Self.dateString(graceEndDate))
        case let .expired(_, expiredAt): ("Expired", Self.dateString(expiredAt))
        case let .churned(_, expiredAt): ("Expired", Self.dateString(expiredAt))
        case .free: nil
        }
    }

    private var productLine: String? {
        switch state {
        case let .active(productId, _, _): SubscriptionProduct(rawValue: productId)?.displayName
        case let .gracePeriod(productId, _): SubscriptionProduct(rawValue: productId)?.displayName
        default: nil
        }
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    @MainActor
    private func restore() async {
        guard !isRestoring else {
            return
        }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }
        do { try await services.subscriptions.restorePurchases() }
        catch { restoreError = error.localizedDescription }
    }
}
