//
// NextMealCardView.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import SwiftUI

/// Compact card showing the next upcoming `PlannedMeal` — name, prep-start
/// countdown, prep + eat windows. Rendered inside the Dashboard's Fuel
/// quadrant tile and (eventually) inside `FuelQuadrantDetailView`. Tapping
/// the card is the caller's responsibility (wrap in NavigationLink or Button).
///
/// The countdown updates by ticking off a `TimelineView`, so the user sees a
/// live "Start prepping in N min" string without explicit `onAppear` timers.
struct NextMealCardView: View {
    let meal: PlannedMeal

    /// `.compact` is the tile-embedded variant (small, single row).
    /// `.full` is the row variant for detail screens (multi-line with eat-time too).
    var style: Style = .compact

    enum Style {
        case compact
        case full
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let prepStart = MealScheduleHelpers.prepStartDate(for: meal)
        let mealTime = MealScheduleHelpers.scheduledDate(for: meal)
        let eatFinish = MealScheduleHelpers.eatFinishDate(for: meal)
        let prepCountdown = NextMealCardView.countdownLabel(target: prepStart, now: now)

        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.tempoViolet)
                Text("NEXT MEAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.tempoTextTertiary)
                Spacer()
            }

            Text(meal.mealName)
                .font(style == .compact ? .tempoCallout : .tempoTitle3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)

            Text(prepCountdown)
                .font(.tempoCaption1)
                .fontWeight(.medium)
                .foregroundStyle(prepStart <= now ? Color.tempoSignal : Color.tempoTextSecondary)
                .lineLimit(1)

            if style == .full {
                HStack(spacing: TempoSpacing.md) {
                    timeChip(label: "Prep", time: prepStart)
                    timeChip(label: "Eat", time: mealTime)
                    timeChip(label: "Finish", time: eatFinish)
                }
                .padding(.top, 2)
            }
        }
    }

    private func timeChip(label: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(Self.clockFormatter.string(from: time))
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Formatters

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// "Start prepping in N min" / "Start prepping in N h" / "Start prepping now"
    /// once the prep-start has elapsed.
    static func countdownLabel(target: Date, now: Date) -> String {
        let interval = target.timeIntervalSince(now)
        if interval <= 60 {
            return "Start prepping now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "Start prepping in \(minutes) min"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 {
            return "Start prepping in \(hours) h"
        }
        return "Start prepping in \(hours) h \(remMin) min"
    }
}
