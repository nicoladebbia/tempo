//
// PlanUpdateBanner.swift
// Tempo
//
// Two small cards for the weekly plan: "Your setup changed — update the rest
// of the week?" (nothing rebuilds behind the user's back; they choose), and
// the fix card for a build that can never succeed as-is (needs Pro / AI off).
//

import SwiftData
import SwiftUI

// MARK: - PlanUpdateBanner

struct PlanUpdateBanner: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s3) {
                TideIconTile(systemName: "arrow.triangle.2.circlepath", tint: Tide.warn)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Your setup changed — update the rest of the week?")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Meals you've eaten and past days stay. Planned meals from today on are replaced.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GlassEffectContainer(spacing: Tide.s2) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Tide.s2))
                    : AnyLayout(HStackLayout(spacing: Tide.s2))
                layout {
                    Button {
                        HapticManager.selection()
                        viewModel.dismissPlanUpdateBanner()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("planUpdateNotNow")

                    Button {
                        HapticManager.lightImpact()
                        viewModel.rebuildRestOfWeek(modelContext: modelContext, services: services)
                    } label: {
                        HStack(spacing: Tide.s2) {
                            if viewModel.isGeneratingPlan {
                                ProgressView().tint(Tide.ink)
                            }
                            Text(viewModel.isGeneratingPlan ? "Updating…" : "Update")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(viewModel.isGeneratingPlan)
                    .accessibilityIdentifier("planUpdateConfirm")
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
