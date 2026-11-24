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
    @Environment(\.tideMood)
    private var mood

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
                    tint: Tide.water,
                    title: "Building the week of \(Self.day(weekStart))",
                    detail: "Checking every food and solving each day's macros. You'll get a notification.",
                    isWorking: true
                ) { EmptyView() }
            case let .upcoming(plan, weekStart):
                row(
                    icon: "checkmark.seal.fill",
                    tint: Tide.good,
                    title: "Next week is planned",
                    detail: "Starts Monday \(Self.day(weekStart)). It replaces this plan then."
                ) {
                    Button("Preview") {
                        HapticManager.lightImpact()
                        preview = plan
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("nextWeekPreview")
                }
            case let .failed(message):
                row(icon: "exclamationmark.triangle.fill", tint: Tide.danger, title: "Next week's plan didn't build", detail: message) {
                    Button("Try again") {
                        HapticManager.lightImpact()
                        services.appState.weeklyCheckInRequested = true
                    }
                    .buttonStyle(.tideGlass)
                }
            case .idle:
                if isWeekend {
                    row(
                        icon: "calendar.badge.plus",
                        tint: mood.accent,
                        title: "Plan next week",
                        detail: "30 seconds on what's different — the rest comes from your routine."
                    ) {
                        Button("Start") {
                            HapticManager.lightImpact()
                            services.appState.weeklyCheckInRequested = true
                        }
                        .buttonStyle(.tideGlass)
                        .accessibilityIdentifier("nextWeekStart")
                    }
                }
            }
        }
        .sheet(item: $preview) { plan in
            WeeklyPlanPreviewView(plan: plan)
        }
    }

    /// An icon, a title and a sentence; the action sits under the text so a
    /// large text size can never squeeze it.
    private func row(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        isWorking: Bool = false,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s3) {
                TideIconTile(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isWorking {
                    ProgressView()
                        .tint(Tide.text2)
                }
            }
            action()
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .animation(Tide.snap, value: title)
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
            ScrollView {
                // One card per day: the day and its total on top, the meals under it.
                VStack(alignment: .leading, spacing: Tide.s5) {
                    ForEach(plan.days.sorted { $0.dayIndex < $1.dayIndex }, id: \.dayIndex) { day in
                        FuelRowGroup(
                            title: Self.dayNames[min(max(day.dayIndex, 0), 6)],
                            trailing: "\(Int(day.meals.reduce(0) { $0 + $1.calories })) kcal · \(day.dayType)"
                        ) {
                            ForEach(day.meals.sorted { $0.scheduledTime < $1.scheduledTime }, id: \.mealNumber) { meal in
                                mealRow(meal)
                            }
                        }
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .tidePage()
            .navigationTitle("Next week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
    }

    private func mealRow(_ meal: WeeklyPlanPayload.Meal) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(meal.scheduledTime)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                Text(meal.mealName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Tide.s2)
                Text("\(Int(meal.calories)) kcal")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            ForEach(Array(meal.foods.enumerated()), id: \.offset) { _, food in
                HStack(spacing: Tide.s2) {
                    Text("\(Int(food.quantityGrams)) g \(food.name)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if food.source == "restaurant" {
                        FuelPill(text: "approx", color: Tide.warn)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
