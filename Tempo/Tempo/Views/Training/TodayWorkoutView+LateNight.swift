//
// TodayWorkoutView+LateNight.swift
// Tempo
//
// Past midnight the calendar says it's the new day, but the athlete hasn't
// slept yet — offering "Start guided run" or "Missed X — do it today?" at
// 00:02 is wrong. Between midnight and 5am Today shows a bedtime card that
// previews what's on for the morning instead of the live session, with a
// quiet way to open the session anyway (a genuine early start).
//

import SwiftUI

// MARK: - LateNightWindow

enum LateNightWindow {
    /// Midnight up to (not including) this hour counts as "still last night".
    static let endHour = 5

    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) < endHour
    }

    /// "Skip for tonight" persists (`@AppStorage`) this timestamp — the
    /// bedtime card stays hidden across relaunches until it passes, then
    /// returns normally the next night. Always today's 05:00 local: tapped
    /// only from inside the 00:00–05:00 window itself, so this is always a
    /// few hours out, never a full day.
    static func skipUntil(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: now) ?? now
    }
}

extension TodayWorkoutView {
    /// A trained day (gym or non-gym) viewed in the late-night window.
    func showsBedtimeCard(showSessionAnyway: Bool, now: Date = Date()) -> Bool {
        guard !showSessionAnyway, LateNightWindow.contains(now) else {
            return false
        }
        // UI tests reach Today's session at any hour; opt in to see the card.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-skip-onboarding"), !args.contains("--uitesting-late-night") {
            return false
        }
        switch viewModel.todayDisplayState {
        case .gym,
             .nonGym:
            return viewModel.todayPlan?.status == .planned
        case .noPlan,
             .restDay:
            return false
        }
    }

    func bedtimeCard(onSkipForTonight: @escaping () -> Void) -> some View {
        let plan = viewModel.todayPlan
        let trainerDay = plan.flatMap { viewModel.trainerDay(forKey: $0.programSessionKey, modelContext: modelContext) }
        let sessionName = trainerDay?.title ?? plan?.type.displayName ?? "Training"
        let blockCount = trainerDay?.exercises.count ?? plan?.orderedExercises.count ?? 0

        let unit = trainerDay?.isStrength == false ? "blocks" : "exercises"
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TrainBedtimeHead()

            // What the morning holds, with its size as a figure like the day hero.
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("Tomorrow morning").tideLabel(Tide.text3)
                Text(sessionName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if blockCount > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                        TideNumber("\(blockCount)", size: Tide.numeralS, relativeTo: .title3)
                        Text(unit)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tide.s3)
            .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))

            Button(action: onSkipForTonight) {
                Text("Skip for tonight")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
        }
        .tideCard(padding: Tide.s4)
    }
}

// MARK: - TrainBedtimeHead

/// The bedtime card's opening: tile beside the words, stacked above them at big text sizes.
private struct TrainBedtimeHead: View {
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        layout {
            TideIconTile(systemName: "moon.zzz.fill", tint: TideTrain.violet, size: TideTrain.askTile)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("Late night").tideLabel(TideTrain.violet)
                Text("It's past midnight. Get to bed.")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sleep is part of the plan. The session waits for the morning.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
