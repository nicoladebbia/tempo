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
                    .font(.tempoSubheadline.weight(.semibold))
                    .foregroundStyle(Color.tempoAmber)
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
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
                    viewModel.rebuildRestOfWeek(modelContext: modelContext, services: services)
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
                    .font(.tempoCaption1)
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
                if await viewModel.grantAIConsentAndRebuild(modelContext: modelContext, services: services) == false {
                    consentError = "Couldn't turn on AI features. Try again."
                }
                isWorking = false
            }
        }
    }
}
