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

struct RequestedMealView: View {
    let request: MealRequest

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let meal = Self.meal(id: request.id, in: modelContext) {
                    MealDetailView(meal: meal, opensMarkEaten: request.action == .markEaten)
                } else {
                    VStack(spacing: TempoSpacing.md) {
                        Image(systemName: "fork.knife")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text("That meal isn't on your plan any more.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .multilineTextAlignment(.center)
                        Text("The plan was rebuilt since this reminder was set.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .padding(TempoSpacing.screenEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.tempoBgPrimary)
                    .accessibilityIdentifier("requestedMealMissing")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.tempoSignal)
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

// MARK: - ContentView hooks

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
