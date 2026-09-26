//
// NextWeekPlanCard.swift
// Tempo
//
// The Plan tab's window onto the Sunday loop: "building…", "next week is
// ready — preview", a failure with a retry, or (on weekends) a nudge to plan
// next week now. Hidden on weekdays when nothing is going on.
//

import SwiftUI

// MARK: - NextWeekPlanCard

struct NextWeekPlanCard: View {
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var preview: WeeklyPlanPayload?

    private var service: WeeklyPlanService {
        WeeklyPlanService.shared
    }

    private var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    var body: some View {
        Group {
            switch service.phase {
            case let .building(weekStart):
                row(
                    icon: "hourglass",
                    tint: .tempoInfo,
                    title: "Building the week of \(Self.day(weekStart))",
                    detail: "Checking every food and solving each day's macros. You'll get a notification."
                ) { ProgressView() }
            case let .upcoming(plan, weekStart):
                row(
                    icon: "checkmark.seal.fill",
                    tint: .tempoSuccess,
                    title: "Next week is planned",
                    detail: "Starts Monday \(Self.day(weekStart)). It replaces this plan then."
                ) {
                    Button("Preview") { preview = plan }
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoSignal)
                        .accessibilityIdentifier("nextWeekPreview")
                }
            case let .failed(message):
                row(icon: "exclamationmark.triangle.fill", tint: .tempoError, title: "Next week's plan didn't build", detail: message) {
                    Button("Try again") { services.appState.weeklyCheckInRequested = true }
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoSignal)
                }
            case .idle:
                if isWeekend {
                    row(
                        icon: "calendar.badge.plus",
                        tint: .tempoSignal,
                        title: "Plan next week",
                        detail: "30 seconds on what's different — the rest comes from your routine."
                    ) {
                        Button("Start") { services.appState.weeklyCheckInRequested = true }
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoSignal)
                            .accessibilityIdentifier("nextWeekStart")
                    }
                }
            }
        }
        .sheet(item: $preview) { plan in
            WeeklyPlanPreviewView(plan: plan)
        }
    }

    private func row(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.tempoHeadline)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text(title)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(detail)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .tempoCard()
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - WeeklyPlanPayload + Identifiable

extension WeeklyPlanPayload: Identifiable {
    var id: String {
        days.map { "\($0.dayIndex)\($0.meals.count)" }.joined()
    }
}

// MARK: - WeeklyPlanPreviewView

/// Read-only look at a plan that hasn't started yet.
struct WeeklyPlanPreviewView: View {
    let plan: WeeklyPlanPayload

    @Environment(\.dismiss)
    private var dismiss

    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(plan.days.sorted { $0.dayIndex < $1.dayIndex }, id: \.dayIndex) { day in
                    Section {
                        ForEach(day.meals.sorted { $0.scheduledTime < $1.scheduledTime }, id: \.mealNumber) { meal in
                            mealRow(meal)
                        }
                    } header: {
                        HStack {
                            Text(Self.dayNames[min(max(day.dayIndex, 0), 6)])
                            Spacer()
                            Text("\(Int(day.meals.reduce(0) { $0 + $1.calories })) kcal · \(day.dayType)")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Next week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func mealRow(_ meal: WeeklyPlanPayload.Meal) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text(meal.scheduledTime)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(meal.mealName)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(Int(meal.calories)) kcal")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            ForEach(Array(meal.foods.enumerated()), id: \.offset) { _, food in
                HStack(spacing: TempoSpacing.xs) {
                    Text("\(Int(food.quantityGrams)) g \(food.name)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    if food.source == "restaurant" {
                        Text("approx")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoWarning)
                    }
                }
            }
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }
}
