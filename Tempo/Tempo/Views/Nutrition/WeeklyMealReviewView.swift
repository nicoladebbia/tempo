//
// WeeklyMealReviewView.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import SwiftData
import SwiftUI

/// End-of-week review screen. Lists the last 7 days of `PlannedMeal`s,
/// grouped by day, with feedback state per row. Tap any row to open
/// `MealFeedbackSheet` — new or existing. The plan generator reads these
/// rows on next plan generation to anchor recipes/portions to the user's
/// actual taste signal.
struct WeeklyMealReviewView: View {
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var meals: [PlannedMeal] = []
    @State
    private var feedbackByMealID: [UUID: MealFeedback] = [:]
    @State
    private var selection: PlannedMeal?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s5) {
                header
                if meals.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedByDay, id: \.dayStart) { group in
                        daySection(group)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s4)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tidePage()
        .navigationTitle("Week in Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $selection, onDismiss: load) { meal in
            MealFeedbackSheet(meal: meal, existing: feedbackByMealID[meal.id])
                .presentationDetents([.medium, .large])
                .environment(\.tideInsidePage, false)
        }
    }

    // MARK: - Sections

    /// How much of the week has a review: a lit ring with the count, and what the notes do.
    private var header: some View {
        FuelProgressHero(
            done: feedbackCount,
            total: meals.count,
            title: "Last 7 days",
            caption: "Notes here flow into next week's plan. The model honours specific changes (\"add lemon\", \"100g not 300g\") and patterns across multiple meals."
        )
        .tideCard()
        .accessibilityValue("\(feedbackCount) of \(meals.count) reviewed")
    }

    private var emptyState: some View {
        FuelEmptyState(
            icon: "calendar.badge.exclamationmark",
            title: "No meals in the past 7 days yet.",
            message: "Mark meals eaten or skipped and they show up here to review."
        )
    }

    private func daySection(_ group: DayGroup) -> some View {
        FuelRowGroup(title: dayLabelFormatter.string(from: group.dayStart)) {
            ForEach(group.meals, id: \.id) { meal in
                Button {
                    HapticManager.lightImpact()
                    selection = meal
                } label: {
                    mealRow(meal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mealRow(_ meal: PlannedMeal) -> some View {
        let feedback = feedbackByMealID[meal.id]
        return HStack(spacing: Tide.s3) {
            Image(systemName: statusIcon(meal.status))
                .font(Tide.headline)
                .foregroundStyle(statusColor(meal.status))
                .frame(width: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(meal.mealName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meal.scheduledTime)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .monospacedDigit()
            }

            Spacer(minLength: Tide.s2)

            if let feedback {
                feedbackBadge(feedback)
            } else if meal.status == .eaten {
                FuelPill(text: "Review", color: Tide.warn)
            } else {
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }

    private func feedbackBadge(_ feedback: MealFeedback) -> some View {
        let rating = feedback.rating.flatMap { $0 > 0 ? $0 : nil }
        return HStack(spacing: Tide.s1) {
            if let rating {
                Image(systemName: "star.fill")
                    .font(Tide.label)
                    .foregroundStyle(Tide.warn)
                Text("\(rating)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
                    .monospacedDigit()
            } else {
                Image(systemName: "text.bubble.fill")
                    .font(Tide.label)
                    .foregroundStyle(Tide.good)
            }
        }
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(Tide.good.opacity(0.16), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating.map { "Rated \($0)" } ?? "Has a note")
    }

    // MARK: - Data

    private struct DayGroup {
        let dayStart: Date
        let meals: [PlannedMeal]
    }

    private var feedbackCount: Int {
        meals.filter { feedbackByMealID[$0.id] != nil }.count
    }

    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.dayDate) }
        return buckets
            .map { group in
                // Sort within day by scheduledTime ("HH:mm" → minutes-of-day)
                // so a 16:00 snack appears before a 17:30 dinner regardless
                // of the AI's mealNumber assignment. Matches the Today view
                // sort introduced in the previous commit.
                let sortedMeals = group.value.sorted { lhs, rhs in
                    let lhsMin = NutritionTabViewModel.minutesOfDay(from: lhs.scheduledTime) ?? Int.max
                    let rhsMin = NutritionTabViewModel.minutesOfDay(from: rhs.scheduledTime) ?? Int.max
                    if lhsMin != rhsMin {
                        return lhsMin < rhsMin
                    }
                    return lhs.mealNumber < rhs.mealNumber
                }
                return DayGroup(dayStart: group.key, meals: sortedMeals)
            }
            .sorted { $0.dayStart > $1.dayStart }
    }

    private func load() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: todayStart),
              let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else {
            return
        }
        // Predicate keeps the date window (last 7 days INCLUDING today).
        // We further filter in Swift to keep only meals that are actually
        // reviewable: .eaten or .skipped. `.planned` meals — today's
        // upcoming slots and any past-but-untouched ones — get hidden
        // because there's nothing to review yet. Older-than-7-days meals
        // stay in the DB but don't appear here; a future History view
        // will surface them read-only.
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= weekAgo && meal.dayDate < tomorrowStart
            },
            sortBy: [SortDescriptor(\.dayDate, order: .reverse), SortDescriptor(\.mealNumber)]
        )
        let allMeals = CanonicalMeals.historical((try? modelContext.fetch(descriptor)) ?? [])
        meals = allMeals.filter { meal in
            (meal.status == .eaten || meal.status == .skipped) && !EatenMealRecorder.isSupplementDose(meal)
        }

        // CRITICAL: do NOT iterate every MealFeedback row and read
        // row.plannedMeal?.id. After a daily reset / plan regen,
        // MealFeedback rows can point at cascade-deleted PlannedMeals;
        // even with deleteRule: .nullify the in-memory ref stays
        // dangling until re-fault, and reading .id crashes with
        // "SwiftData/BackingData.swift:1039 Fatal" (same class as the
        // refreshFeedbackPresence crash). Fetch per-mealID with a
        // predicate so SwiftData resolves the relationship server-side
        // and dangling rows simply don't match.
        let mealIDs = meals.map(\.id)
        var map: [UUID: MealFeedback] = [:]
        for mealID in mealIDs {
            let fbDescriptor = FetchDescriptor<MealFeedback>(
                predicate: #Predicate<MealFeedback> { row in
                    row.plannedMeal?.id == mealID
                }
            )
            if let row = (try? modelContext.fetch(fbDescriptor))?.first {
                map[mealID] = row
            }
        }
        feedbackByMealID = map
    }

    // MARK: - Helpers

    private let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private func statusIcon(_ status: MealStatus) -> String {
        switch status {
        case .eaten: "checkmark.circle.fill"
        case .skipped: "xmark.circle.fill"
        default: "circle"
        }
    }

    private func statusColor(_ status: MealStatus) -> Color {
        switch status {
        case .eaten: Tide.good
        case .skipped: Tide.danger
        default: Tide.text3
        }
    }
}
