//
//  SubscriptionDetailView.swift
//  Tempo
//
//  Subscription: the real plan, what it unlocks and when it renews or ends.
//  The plan comes from `PlanStatus`, which merges what the server says (what
//  every Pro gate checks) with what the App Store says on this device.
//

import StoreKit
import SwiftUI

// MARK: - SubscriptionDetailView

struct SubscriptionDetailView: View {
    var plan: PlanModel

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var showManage = false
    @State
    private var isRestoring = false
    @State
    private var restoreError: String?

    private var status: PlanStatus {
        plan.status(device: services.subscriptions.state)
    }

    /// What Pro gives, in the words the paywall uses.
    private static let benefits: [(icon: String, text: String)] = [
        ("sparkles", String(localized: "Recovery insights from Whoop & wearables")),
        ("brain.head.profile", String(localized: "AI-powered workout programming")),
        ("fork.knife", String(localized: "AI nutrition coaching & meal plans")),
        ("chart.line.uptrend.xyaxis", String(localized: "Progress charts & weekly reports")),
    ]

    /// States where the next step is the one thing to do here, so it sits under the thumb.
    private func isPinned(_ status: PlanStatus) -> Bool {
        switch status.kind {
        case .free,
             .expired,
             .cancelled,
             .grace: status.action != nil
        case .trial,
             .active,
             .included: false
        }
    }

    private func actionButton(_ status: PlanStatus) -> some View {
        Button { perform(status.action) } label: {
            Text(status.actionTitle ?? "")
        }
        .buttonStyle(.tidePrimary)
        .accessibilityIdentifier("subscriptionAction")
    }

    var body: some View {
        let status = status
        TideSettingsPage {
            planCard(status)

            if let notice = status.notice {
                noticeCard(notice)
            }

            checkLine

            benefitsCard(status)

            if isPinned(status), typeSize.isAccessibilitySize {
                // Too big to pin: the button follows the page.
                actionButton(status)
            }

            detailsCard(status)

            SettingsFormCard(footnote: restoreError, footnoteColor: Tide.danger) {
                Button { Task { await restore() } } label: {
                    SettingsActionRow(icon: "arrow.clockwise", title: String(localized: "Restore Purchases"), tint: Tide.text)
                }
                .buttonStyle(.tideSettingsRow)
                .disabled(isRestoring)
            }
        }
        .safeAreaBar(edge: .bottom) {
            // The way forward is under the thumb when there is one to take.
            if isPinned(status), !typeSize.isAccessibilitySize {
                actionButton(status)
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s2)
            }
        }
        .tideCovered(showPaywall)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task { await plan.refresh(apiClient: services.apiClient) }
    }

    // MARK: Cards

    private func tint(for status: PlanStatus) -> Color {
        switch status.kind {
        case .trial,
             .active,
             .included: Tide.streak
        case .cancelled,
             .grace: Tide.settingsAttention
        case .free,
             .expired: Tide.text3
        }
    }

    /// The plan as a mark and a name; the days that matter under it.
    private func planCard(_ status: PlanStatus) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return TideSettingsHero {
            layout {
                TideIconTile(
                    systemName: status.isPro ? "crown.fill" : "crown",
                    tint: tint(for: status),
                    size: Tide.settingsBigTile
                )
                VStack(alignment: .leading, spacing: Tide.hair) {
                    TideLabel(String(localized: "Your plan"))
                    Text(status.title)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("subscriptionPlanTitle")
                    Text(status.subtitle)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if let days = status.daysLeft(), let unit = status.countdownUnit(days: days) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideNumber(
                        "\(days)", unit: unit,
                        size: Tide.numeralL, relativeTo: .largeTitle, color: tint(for: status)
                    )
                    .contentTransition(.numericText())
                    if let progress = status.trialProgress() {
                        TideLevelBar(progress: progress, color: tint(for: status), height: Tide.bar)
                            .background(Tide.fill, in: .capsule)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, Tide.s2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Where the server and the App Store disagree.
    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Tide.headline)
                .foregroundStyle(Tide.settingsAttention)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideTintedCard(Tide.settingsAttention, padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subscriptionNotice")
    }

    /// Whether Tempo has checked the plan with the server: a quiet line while it
    /// asks, and a way to ask again when it could not.
    @ViewBuilder
    private var checkLine: some View {
        switch plan.load {
        case .loading where plan.server == nil:
            HStack(spacing: Tide.s2) {
                ProgressView()
                Text("Checking your plan…")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tide.s2)
            .accessibilityElement(children: .combine)
        case .failed:
            VStack(alignment: .leading, spacing: Tide.s2) {
                Label("Couldn't check your plan with Tempo. What you see comes from this device.", systemImage: "wifi.exclamationmark")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await plan.refresh(apiClient: services.apiClient) }
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("subscriptionRetry")
            }
            .padding(.horizontal, Tide.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    /// What Pro unlocks: locked on the free plan, ticked on Pro.
    private func benefitsCard(_ status: PlanStatus) -> some View {
        TideSettingsSection(title: status.isPro ? String(localized: "Your Pro includes") : String(localized: "What Pro unlocks")) {
            ForEach(Array(Self.benefits.enumerated()), id: \.offset) { index, benefit in
                if index > 0 {
                    SettingsRowDivider()
                }
                benefitRow(benefit, isPro: status.isPro)
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s3)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(status.isPro ? String(localized: "Included") : String(localized: "Locked"))
            }
        }
    }

    /// One benefit. At accessibility sizes the tick sits under the words instead
    /// of squeezing beside them.
    @ViewBuilder
    private func benefitRow(_ benefit: (icon: String, text: String), isPro: Bool) -> some View {
        let stateIcon = Image(systemName: isPro ? "checkmark.circle.fill" : "lock.fill")
            .font(Tide.headline)
            .foregroundStyle(isPro ? mood.accent : Tide.text3)
            .accessibilityHidden(true)
        let text = Text(benefit.text)
            .font(Tide.bodyStrong)
            .foregroundStyle(isPro ? Tide.text : Tide.text2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if typeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: Tide.s3) {
                SettingsIconTile(systemName: benefit.icon, tint: isPro ? mood.accent : Tide.text3)
                VStack(alignment: .leading, spacing: Tide.s2) {
                    text
                    HStack(spacing: Tide.s2) {
                        stateIcon
                        Text(isPro ? String(localized: "Included") : String(localized: "Locked"))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            TideSettingsRowLine {
                HStack(spacing: Tide.s3) {
                    SettingsIconTile(systemName: benefit.icon, tint: isPro ? mood.accent : Tide.text3)
                    text
                }
            } trailing: {
                stateIcon
            }
        }
    }

    private func detailsCard(_ status: PlanStatus) -> some View {
        SettingsFormCard(title: String(localized: "Details")) {
            SettingsInfoRow(
                label: String(localized: "Status"),
                value: status.title,
                icon: "checkmark.seal.fill",
                iconTint: status.isPro ? mood.accent : Tide.text3,
                valueColor: status.isPro ? mood.accent : Tide.text3
            )
            if let label = status.dateLabel, let date = status.date {
                SettingsRowDivider()
                SettingsInfoRow(label: label, value: Self.dateString(date), icon: "calendar")
            }
            if let product = status.productName {
                SettingsRowDivider()
                SettingsInfoRow(label: String(localized: "Plan"), value: product, icon: "tag.fill")
            }
            if status.action == .manageInAppStore, !isPinned(status) {
                SettingsRowDivider()
                Button { showManage = true } label: {
                    SettingsActionRow(icon: "gearshape.fill", title: status.actionTitle ?? String(localized: "Manage subscription"), tint: Tide.text)
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("subscriptionManage")
            }
        }
    }

    // MARK: Actions

    private func perform(_ action: PlanAction?) {
        switch action {
        case .showPaywall: showPaywall = true
        case .manageInAppStore: showManage = true
        case nil: break
        }
    }

    private static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
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
