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
/// allowed AI features: the shared AI blocker card, with plan wording and a
/// rebuild once AI is switched on.
struct PlanBlockerCard: View {
    let blocker: PlanGenerationBlocker
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    var body: some View {
        AIBlockerCard(blocker: blocker.aiBlocker, message: blocker.message) {
            viewModel.planGenerationBlocker = nil
            viewModel.planGenerationError = nil
            viewModel.rebuildRestOfWeek(modelContext: modelContext, services: services)
        }
        .accessibilityIdentifier("planBlockerCard")
    }
}
