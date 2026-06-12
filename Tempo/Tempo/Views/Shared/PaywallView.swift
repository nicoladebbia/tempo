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

struct PaywallView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss

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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Header
                header

                // Consolidation pitch
                consolidationPitch

                // Feature list
                featureList

                // Plan selector
                planSelector

                // Student discount
                studentToggle

                // Savings callout
                savingsCallout

                // CTA
                purchaseButton

                // Restore + Dismiss
                footerActions

                // Legal disclosure
                // Per APP_STORE_COMPLIANCE.md Section 5.2
                legalText
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.xxl)
            .padding(.bottom, 40)
        }
        .background(Color.tempoBgPrimary)
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
        .task {
            await loadProducts()
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 {
                errorMessage = nil
            } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoAmber)

            Text("UNLOCK TEMPO PRO")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Your AI-powered life operating system.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Consolidation Pitch

    private var consolidationPitch: some View {
        VStack(spacing: 4) {
            Text("STOP PAYING FOR 5 APPS")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoAmber)
                .tracking(1.5)
            Text("Sleep tracking + Workouts + Recovery + Nutrition + Accountability")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, TempoSpacing.md)
    }

    // MARK: - Features

    // Per MONETIZATION_STRATEGY.md — Hero Pro features, ordered by Tier 1 priority.

    private var featureList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            featureRow(icon: "sparkles", text: "Recovery insights from Whoop & wearables")
            featureRow(icon: "brain.head.profile", text: "AI-powered workout programming")
            featureRow(icon: "fork.knife", text: "AI nutrition coaching & meal plans")
            featureRow(icon: "chart.line.uptrend.xyaxis", text: "Progress charts & weekly reports")
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.tempoSignal)
                .frame(width: 28, alignment: .center)

            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)

            Spacer()
        }
    }

    // MARK: - Plan Selector

    // Per MONETIZATION_STRATEGY.md — Annual pre-selected with "BEST VALUE" badge.

    /// The effective product for the current mode (standard or student).
    private var effectiveProduct: SubscriptionProduct {
        isStudentMode ? selectedProduct.studentVariant : selectedProduct.standardVariant
    }

    private var planSelector: some View {
        VStack(spacing: TempoSpacing.sm) {
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

    private func planCard(
        product: SubscriptionProduct,
        isSelected: Bool,
        badge: String?
    ) -> some View {
        let storeProduct = products.first { $0.id == product.rawValue }
        let isAnnual = product == .annual || product == .studentAnnual
        let isMonthly = product == .monthly || product == .studentMonthly
        let fallbackPrice = switch product {
        case .monthly: "$4.99"
        case .annual: "$39.99"
        case .studentMonthly: "$2.99"
        case .studentAnnual: "$23.99"
        }

        return Button {
            selectedProduct = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TempoSpacing.xs) {
                        Text(product.displayName)
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.tempoAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.tempoAmber.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        if product.isStudent {
                            Text("40% OFF")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.tempoSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.tempoSuccess.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    if isAnnual {
                        Text("Save 33%")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoRecoveryGreen)
                    }
                }

                Spacer()

                // Per APP_STORE_COMPLIANCE.md Section 5.6 — Use Product.displayPrice
                VStack(alignment: .trailing, spacing: 2) {
                    Text(storeProduct?.displayPrice ?? fallbackPrice)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(isMonthly ? "/month" : "/year")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(isSelected ? Color.tempoSignal : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(product.displayName) plan\(badge != nil ? ", \(badge!)" : "")\(product.isStudent ? ", student pricing" : "")"
        )
    }

    // MARK: - Student Toggle

    private var studentToggle: some View {
        VStack(spacing: TempoSpacing.sm) {
            Button(action: { isStudentMode.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(Color.tempoAmber)
                    Text("I'm a student")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Image(systemName: isStudentMode ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isStudentMode ? Color.tempoSuccess : Color.tempoTextTertiary)
                }
            }
            .buttonStyle(.plain)

            if isStudentMode {
                Text("40% off with valid .edu email")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    // MARK: - Savings Callout

    @ViewBuilder
    private var savingsCallout: some View {
        if !isStudentMode {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.tempoSuccess)
                Text("Replaces Whoop ($30) + MyFitnessPal ($20) + Strong ($5) = saves $55/mo")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await performPurchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(Color.tempoBone)
                } else {
                    // Per MONETIZATION_STRATEGY.md — "Start Free Trial" CTA
                    Text("Start Free Trial")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.tempoBone)
            .background(Color.tempoSignal)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
        .disabled(isPurchasing)
        .accessibilityLabel("Start free trial")
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: TempoSpacing.xl) {
            // Per APP_STORE_COMPLIANCE.md Section 5.4 — Restore Purchases button
            Button("Restore Purchases") {
                Task { await restorePurchases() }
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)

            // Per MONETIZATION_STRATEGY.md — "Maybe Later" secondary option
            Button("Maybe Later") {
                dismiss()
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    /// Per APP_STORE_COMPLIANCE.md Section 5.2, 5.5 — Required subscription disclosure.
    private var legalText: some View {
        Text(
            "7-day free trial, then auto-renews. Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period."
        )
        .font(.tempoCaption2)
        .foregroundStyle(Color.tempoTextTertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, TempoSpacing.md)
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(TempoSpacing.lg)
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Actions

    private func loadProducts() async {
        products = services.subscriptions.availableProducts()
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
