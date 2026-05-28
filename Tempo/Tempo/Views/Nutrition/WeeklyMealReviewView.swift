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
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                header
                if meals.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedByDay, id: \.dayStart) { group in
                        daySection(group)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Week in Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $selection, onDismiss: load) { meal in
            MealFeedbackSheet(meal: meal, existing: feedbackByMealID[meal.id])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("LAST 7 DAYS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Text("\(feedbackCount) of \(meals.count) reviewed")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Notes here flow into next week's plan. The model honours specific changes (\"add lemon\", \"100g not 300g\") and patterns across multiple meals.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No meals in the past 7 days yet.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
        .tempoCard()
    }

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(dayLabelFormatter.string(from: group.dayStart).uppercased())
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .tracking(0.5)
                .foregroundStyle(Color.tempoTextSecondary)

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
        return HStack(spacing: TempoSpacing.md) {
            Image(systemName: statusIcon(meal.status))
                .font(.system(size: 16))
                .foregroundStyle(statusColor(meal.status))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(meal.scheduledTime)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .monospacedDigit()
            }

            Spacer()

            if let feedback {
                feedbackBadge(feedback)
            } else if meal.status == .eaten {
                Text("Review")
                    .font(.tempoCaption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.tempoAmber.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    private func feedbackBadge(_ feedback: MealFeedback) -> some View {
        HStack(spacing: 4) {
            if let rating = feedback.rating, rating > 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.tempoAmber)
                Text("\(rating)")
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .monospacedDigit()
            } else {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.tempoSuccess)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.tempoSuccess.opacity(0.12))
        .clipShape(Capsule())
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
                    if lhsMin != rhsMin { return lhsMin < rhsMin }
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
        let allMeals = (try? modelContext.fetch(descriptor)) ?? []
        meals = allMeals.filter { meal in
            meal.status == .eaten || meal.status == .skipped
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
        case .eaten: .tempoSuccess
        case .skipped: .tempoError
        default: .tempoTextTertiary
        }
    }
}
