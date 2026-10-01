//
// PlanUpdateBanner.swift
// Tempo
//
// Two small cards for the weekly plan: "Your setup changed — update the rest
// of the week?" (nothing rebuilds behind the user's back; they choose), and
// the fix card for a build that can never succeed as-is (needs Pro / AI off).
//

import SwiftUI

// MARK: - PlanUpdateBanner

struct PlanUpdateBanner: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tempoAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your setup changed — update the rest of the week?")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Meals you've eaten and past days stay. Planned meals from today on are replaced.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            HStack(spacing: TempoSpacing.lg) {
                Spacer()
                Button {
                    HapticManager.selection()
                    viewModel.dismissPlanUpdateBanner()
                } label: {
                    Text("Not now")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.tempoTextSecondary)
                .accessibilityIdentifier("planUpdateNotNow")

                Button {
                    HapticManager.lightImpact()
                    viewModel.generatePlan(
                        modelContext: modelContext,
                        whoop: services.whoop,
                        apiClient: services.apiClient,
                        notifications: services.notifications,
                        trainingEngine: services.trainingEngine,
                        healthKit: services.healthKit
                    )
                } label: {
                    Text(viewModel.isGeneratingPlan ? "Updating…" : "Update")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.tempoSignal)
                .disabled(viewModel.isGeneratingPlan)
                .accessibilityIdentifier("planUpdateConfirm")
            }
            .buttonStyle(.plain)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoAmber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .accessibilityIdentifier("planUpdateBanner")
    }
}

// MARK: - PlanBlockerCard

/// Shown when the plan can't be built because the user needs Pro or hasn't
/// allowed AI features: the reason, and a button to fix it.
struct PlanBlockerCard: View {
    let blocker: PlanGenerationBlocker
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var isWorking = false
    @State
    private var consentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tempoAmber)
                Text(blocker.message)
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            if let consentError {
                Text(consentError)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoError)
            }
            Button {
                act()
            } label: {
                Text(isWorking ? "Working…" : blocker.actionTitle)
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoSignal)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("planBlockerAction")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoAmber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func act() {
        switch blocker {
        case .proRequired:
            showPaywall = true
        case .aiConsentRequired:
            isWorking = true
            consentError = nil
            Task {
                do {
                    let _: AIConsentResponseDTO = try await services.apiClient.request(
                        APIEndpoint<AIConsentResponseDTO>.setAIConsent(),
                        body: AIConsentRequestDTO(consented: true)
                    )
                    viewModel.planGenerationBlocker = nil
                    viewModel.planGenerationError = nil
                    viewModel.generatePlan(
                        modelContext: modelContext,
                        whoop: services.whoop,
                        apiClient: services.apiClient,
                        notifications: services.notifications,
                        trainingEngine: services.trainingEngine,
                        healthKit: services.healthKit
                    )
                } catch {
                    consentError = "Couldn't turn on AI features. Try again."
                }
                isWorking = false
            }
        }
    }
}
