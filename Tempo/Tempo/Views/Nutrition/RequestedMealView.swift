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
                    FuelEmptyState(
                        icon: "fork.knife",
                        title: "That meal isn't on your plan any more.",
                        message: "The plan was rebuilt since this reminder was set."
                    )
                    .padding(.horizontal, Tide.edge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tidePage()
                    .accessibilityIdentifier("requestedMealMissing")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(mood.accent)
                }
            }
        }
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
