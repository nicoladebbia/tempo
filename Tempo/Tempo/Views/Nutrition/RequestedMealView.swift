//
// RequestedMealView.swift
// Tempo
//
// What a meal notification opens: that meal's detail (optionally straight into
// Mark eaten). A meal that was eaten elsewhere or replaced by a plan rebuild
// says so instead of showing a dead screen.
//

import Combine
import SwiftData
import SwiftUI

// MARK: - RequestedMealView

struct RequestedMealView: View {
    let request: MealRequest

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            Group {
                if let meal = Self.meal(id: request.id, in: modelContext) {
                    MealDetailView(meal: meal, opensMarkEaten: request.action == .markEaten)
                } else {
                    missing
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(mood.accent)
                }
            }
        }
        // A sheet is its own page, even when a notification opens it from inside one.
        .environment(\.tideInsidePage, false)
    }

    /// The meal is gone: say so, say why, and give one way out.
    private var missing: some View {
        VStack(spacing: Tide.s4) {
            TideStateMark(systemName: "fork.knife", tint: Tide.warn)
            VStack(spacing: Tide.s2) {
                Text("That meal isn't on your plan any more.")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("The plan was rebuilt since this reminder was set.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: Tide.stateWidth)
        }
        .padding(.horizontal, Tide.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The one way out sits under the thumb.
        .fuelBottomBar {
            Button("Back to Fuel") { dismiss() }
                .buttonStyle(.tidePrimary)
        }
        .tidePage()
        .accessibilityIdentifier("requestedMealMissing")
    }

    static func meal(id: UUID, in modelContext: ModelContext) -> PlannedMeal? {
        var descriptor = FetchDescriptor<PlannedMeal>(predicate: #Predicate<PlannedMeal> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - MealNotificationHooks

private struct MealNotificationHooks: ViewModifier {
    @Binding
    var request: MealRequest?
    let reschedule: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { request in
                RequestedMealView(request: request)
            }
            // Pre-meal reminders follow the plan: a rebuild, a logged /
            // skipped / undone meal, a shifted day.
            .onReceive(
                NotificationCenter.default.publisher(for: .tempoNutritionLogged)
                    .merge(with: NotificationCenter.default.publisher(for: .tempoWeeklyPlanApplied))
                    .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
            ) { _ in
                reschedule()
            }
    }
}

extension View {
    /// Presents the meal a notification asked for and keeps the pre-meal
    /// reminders in step with plan changes.
    func mealNotificationHooks(request: Binding<MealRequest?>, reschedule: @escaping () -> Void) -> some View {
        modifier(MealNotificationHooks(request: request, reschedule: reschedule))
    }
}
