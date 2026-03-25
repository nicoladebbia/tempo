import SwiftUI
import StoreKit

// MARK: - Paywall View
// Per BUILD_PLAN Step 20.1 — Paywall UI with feature comparison.
// Per MONETIZATION_STRATEGY.md — Annual pre-selected, "BEST VALUE" badge, trial callout.
// Per APP_STORE_COMPLIANCE.md Section 5 — Required disclosure text.

struct PaywallView: View {

    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: SubscriptionProduct = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var products: [Product] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Header
                header

                // Feature list
                featureList

                // Plan selector
                planSelector

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
            set: { if !$0 { errorMessage = nil } }
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

    // MARK: - Features
    // Per MONETIZATION_STRATEGY.md — 3-4 hero Pro features.

    private var featureList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            featureRow(icon: "brain.head.profile", text: "AI-powered workout programming")
            featureRow(icon: "chart.line.uptrend.xyaxis", text: "Progress charts & weekly AI reports")
            featureRow(icon: "person.2.fill", text: "Unlimited friends & social feed")
            featureRow(icon: "sparkles", text: "Pattern detection & recovery insights")
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

    private var planSelector: some View {
        VStack(spacing: TempoSpacing.sm) {
            // Annual plan
            planCard(
                product: .annual,
                isSelected: selectedProduct == .annual,
                badge: "BEST VALUE"
            )

            // Monthly plan
            planCard(
                product: .monthly,
                isSelected: selectedProduct == .monthly,
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
                    }

                    if product == .annual {
                        Text("Save 33%")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoRecoveryGreen)
                    }
                }

                Spacer()

                // Per APP_STORE_COMPLIANCE.md Section 5.6 — Use Product.displayPrice
                VStack(alignment: .trailing, spacing: 2) {
                    Text(storeProduct?.displayPrice ?? (product == .monthly ? "$4.99" : "$39.99"))
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(product == .monthly ? "/month" : "/year")
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
        .accessibilityLabel("\(product.displayName) plan\(badge != nil ? ", \(badge!)" : "")")
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

    // Per APP_STORE_COMPLIANCE.md Section 5.2, 5.5 — Required subscription disclosure.
    private var legalText: some View {
        Text("7-day free trial, then auto-renews. Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period.")
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
        if let service = services.subscriptions as? SubscriptionService {
            products = service.availableProducts()
        }
    }

    private func performPurchase() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await services.subscriptions.purchase(selectedProduct)
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

// MARK: - SubscriptionError Equatable

extension SubscriptionError: Equatable {
    static func == (lhs: SubscriptionError, rhs: SubscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.productNotFound, .productNotFound),
             (.userCancelled, .userCancelled),
             (.pending, .pending),
             (.unknown, .unknown):
            return true
        case (.verificationFailed, .verificationFailed):
            return true
        default:
            return false
        }
    }
}
