//
// PaywallView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import StoreKit
import SwiftUI

// MARK: - PaywallView

// Per BUILD_PLAN Step 20.1 — Paywall UI with feature comparison.
// Per MONETIZATION_STRATEGY.md — Annual pre-selected, "BEST VALUE" badge, trial callout.
// Per APP_STORE_COMPLIANCE.md Section 5 — Required disclosure text.
//
// Tide: the field behind, glass cards, the plans as two selectable glass rows
// and the trial button pinned at the bottom.

struct PaywallView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    @State
    private var selectedProduct: SubscriptionProduct = .annual
    @State
    private var isStudentMode = false
    @State
    private var isPurchasing = false
    @State
    private var errorMessage: String?
    @State
    private var products: [Product] = []
    /// Length in days of the free trial this Apple ID can still get, read
    /// from the store. nil until the store confirms one: a lapsed subscriber
    /// usually can't have it again, and the paywall must not promise it then.
    @State
    private var trialDays: Int?

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: Tide.s5) {
                // Header
                header

                // What it costs, first: the price of the plan picked below.
                priceHero

                // Feature list
                featureList

                // Plan selector
                planSelector

                // Student discount
                studentToggle

                // What it replaces
                savingsCallout

                // Legal disclosure
                // Per APP_STORE_COMPLIANCE.md Section 5.2
                legalText

                // Too big to pin: the actions follow the page instead.
                if dynamicTypeSize.isAccessibilitySize {
                    footer(pinned: false)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s8)
            .padding(.bottom, Tide.s6)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                footer(pinned: true)
            }
        }
        .tidePage(energy: 1)
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
        .task {
            await loadProducts()
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Tide.s3) {
            TideStateMark(systemName: "crown.fill", tint: Tide.carbs)

            Text("UNLOCK TEMPO PRO")
                .font(Tide.title)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Price hero

    /// The price and period of a plan: the store's own string when it loaded.
    private func price(for product: SubscriptionProduct) -> String {
        if let storeProduct = products.first(where: { $0.id == product.rawValue }) {
            return storeProduct.displayPrice
        }
        return switch product {
        case .monthly: "$4.99"
        case .annual: "$39.99"
        case .studentMonthly: "$2.99"
        case .studentAnnual: "$23.99"
        }
    }

    private func period(for product: SubscriptionProduct) -> String {
        product == .monthly || product == .studentMonthly ? "month" : "year"
    }

    /// The trial and the price that follows it, in one line: the line the
    /// button below is agreeing to.
    private var trialTerms: String {
        let plan = "\(price(for: effectiveProduct)) per \(period(for: effectiveProduct))"
        guard let trialDays else {
            return "Billed \(plan). Cancel anytime."
        }
        return "\(trialDays)-day free trial, then \(plan)"
    }

    private var priceHero: some View {
        VStack(spacing: Tide.s2) {
            Text(trialDays.map { "\($0) DAYS FREE, THEN" } ?? "PRO FOR")
                .tideLabel(mood.accent)
            TideNumber(
                price(for: effectiveProduct),
                unit: "/\(period(for: effectiveProduct))",
                size: Tide.numeralL,
                relativeTo: .largeTitle
            )
            Text("Your AI-powered life operating system.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .animation(Tide.snap, value: effectiveProduct)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trialTerms)
    }

    // MARK: - Features

    // Per MONETIZATION_STRATEGY.md — Hero Pro features, ordered by Tier 1 priority.

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            featureRow(icon: "sparkles", text: "Recovery insights from Whoop & wearables")
            featureRow(icon: "brain.head.profile", text: "AI-powered workout programming")
            featureRow(icon: "fork.knife", text: "AI nutrition coaching & meal plans")
            featureRow(icon: "chart.line.uptrend.xyaxis", text: "Progress charts & weekly reports")
        }
        .tideCard(padding: Tide.s4)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.icon, alignment: .center)
                .accessibilityHidden(true)

            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(minHeight: Tide.icon + Tide.s1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plan Selector

    // Per MONETIZATION_STRATEGY.md — Annual pre-selected with "BEST VALUE" badge.

    /// The effective product for the current mode (standard or student).
    private var effectiveProduct: SubscriptionProduct {
        isStudentMode ? selectedProduct.studentVariant : selectedProduct.standardVariant
    }

    private var planSelector: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            VStack(spacing: Tide.s3) {
                // Annual plan
                planCard(
                    product: isStudentMode ? .studentAnnual : .annual,
                    isSelected: selectedProduct.standardVariant == .annual,
                    badge: "BEST VALUE"
                )

                // Monthly plan
                planCard(
                    product: isStudentMode ? .studentMonthly : .monthly,
                    isSelected: selectedProduct.standardVariant == .monthly,
                    badge: nil
                )
            }
        }
    }

    private func planCard(
        product: SubscriptionProduct,
        isSelected: Bool,
        badge: String?
    ) -> some View {
        let isAnnual = product == .annual || product == .studentAnnual
        let isMonthly = product == .monthly || product == .studentMonthly
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))

        return Button {
            selectedProduct = product
        } label: {
            layout {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.headline)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    HStack(spacing: Tide.s2) {
                        Text(product.displayName)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)

                        if let badge {
                            planTag(badge, color: Tide.carbs)
                        }

                        if product.isStudent {
                            planTag("40% OFF", color: Color.tempoSuccess)
                        }
                    }

                    if isAnnual {
                        Text("Save 33%")
                            .font(Tide.caption)
                            .foregroundStyle(Color.tempoRecoveryGreen)
                    }
                }

                if !stacked {
                    Spacer(minLength: Tide.s2)
                }

                // Per APP_STORE_COMPLIANCE.md Section 5.6 — Use Product.displayPrice
                VStack(alignment: stacked ? .leading : .trailing, spacing: Tide.hair) {
                    Text(price(for: product))
                        .font(Tide.numeral(Tide.numeralS + Tide.s1))
                        .foregroundStyle(Tide.text)
                        .contentTransition(.numericText())

                    Text(isMonthly ? "/month" : "/year")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                }
            }
            .padding(Tide.s4)
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s6, alignment: .leading)
            .glassEffect(
                .regular.tint(isSelected ? mood.accent.opacity(0.22) : Tide.glassCard),
                in: .rect(cornerRadius: Tide.tileRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(isSelected ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(
            "\(product.displayName) plan\(badge != nil ? ", \(badge!)" : "")\(product.isStudent ? ", student pricing" : "")"
        )
    }

    private func planTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Tide.label)
            .foregroundStyle(color)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.hair)
            .background(color.opacity(0.16), in: .capsule)
    }

    // MARK: - Student Toggle

    private var studentToggle: some View {
        VStack(spacing: Tide.s2) {
            Button(action: { isStudentMode.toggle() }) {
                HStack(spacing: Tide.s3) {
                    Image(systemName: "graduationcap.fill")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.carbs)
                        .accessibilityHidden(true)
                    Text("I'm a student")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                    Spacer()
                    Image(systemName: isStudentMode ? "checkmark.circle.fill" : "circle")
                        .font(Tide.headline)
                        .foregroundStyle(isStudentMode ? Color.tempoSuccess : Tide.text3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Tide.s4)
                .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s2)
                .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(TideCardPressStyle())
            .sensoryFeedback(.selection, trigger: isStudentMode)
            .accessibilityAddTraits(isStudentMode ? [.isSelected, .isButton] : .isButton)

            if isStudentMode {
                Text("40% off with valid .edu email")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .transition(.opacity)
            }
        }
        .animation(Tide.snap, value: isStudentMode)
    }

    // MARK: - Savings Callout

    @ViewBuilder
    private var savingsCallout: some View {
        VStack(spacing: Tide.s2) {
            Text("STOP PAYING FOR 5 APPS")
                .tideLabel(Tide.carbs)
            Text("Sleep tracking + Workouts + Recovery + Nutrition + Accountability")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !isStudentMode {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Color.tempoSuccess)
                        .accessibilityHidden(true)
                    Text("Replaces Whoop ($30) + MyFitnessPal ($20) + Strong ($5) = saves $55/mo")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    // MARK: - Footer (pinned)

    private func footer(pinned: Bool) -> some View {
        VStack(spacing: Tide.s1) {
            Text(trialTerms)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Tide.s1)

            purchaseButton

            footerActions
        }
        .padding(.horizontal, pinned ? Tide.edge : 0)
        .padding(.top, pinned ? Tide.s6 : Tide.s2)
        .padding(.bottom, Tide.s1)
        .background {
            if pinned {
                pinnedFade
            }
        }
    }

    /// Solid under the actions, with a short fade above so the page scrolls
    /// away softly instead of running through the price line.
    private var pinnedFade: some View {
        Tide.ink.opacity(0.97)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Tide.ink.opacity(0), Tide.ink.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Tide.s6)
                .offset(y: -Tide.s6)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    private var purchaseButton: some View {
        Button {
            Task { await performPurchase() }
        } label: {
            ZStack {
                // Per MONETIZATION_STRATEGY.md — "Start Free Trial" CTA
                Text(trialDays == nil ? "Subscribe" : "Start Free Trial")
                    .opacity(isPurchasing ? 0 : 1)
                if isPurchasing {
                    ProgressView()
                        .tint(Tide.ink)
                }
            }
        }
        .buttonStyle(.tidePrimary)
        .disabled(isPurchasing)
        .accessibilityLabel(trialDays == nil ? "Subscribe" : "Start free trial")
    }

    private var footerActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            // Per APP_STORE_COMPLIANCE.md Section 5.4 — Restore Purchases button
            Button {
                Task { await restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Per MONETIZATION_STRATEGY.md — "Maybe Later" secondary option
            Button {
                dismiss()
            } label: {
                Text("Maybe Later")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Per APP_STORE_COMPLIANCE.md Section 5.2, 5.5 — Required subscription disclosure.
    private var legalText: some View {
        Text(
            "\(trialDays.map { "\($0)-day free trial, then auto-renews." } ?? "Auto-renews.") Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period."
        )
        .font(Tide.label.weight(.regular))
        .foregroundStyle(Tide.text3)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(Tide.s4)
        .accessibilityLabel("Close")
    }

    // MARK: - Actions

    private func loadProducts() async {
        // Retries the StoreKit catalogue if launch couldn't reach the store.
        await services.subscriptions.startObserving()
        products = services.subscriptions.availableProducts()
        trialDays = await eligibleTrialDays()
    }

    /// The free trial's length in days, only when the store offers one and this
    /// Apple ID is still eligible. One subscription group, so one answer.
    private func eligibleTrialDays() async -> Int? {
        guard let info = products.first?.subscription,
              let offer = info.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await info.isEligibleForIntroOffer
        else {
            return nil
        }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        default: return nil
        }
    }

    private func performPurchase() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await services.subscriptions.purchase(effectiveProduct)
            dismiss()
        } catch let error as SubscriptionError where error == .userCancelled {
            // User cancelled — no error to show
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        do {
            try await services.subscriptions.restorePurchases()
            if services.subscriptions.isPro {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SubscriptionError + Equatable

extension SubscriptionError: Equatable {
    static func == (lhs: SubscriptionError, rhs: SubscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.productNotFound, .productNotFound),
             (.userCancelled, .userCancelled),
             (.pending, .pending),
             (.unknown, .unknown):
            true
        case (.verificationFailed, .verificationFailed):
            true
        default:
            false
        }
    }
}
