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

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "moon.zzz.fill")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoViolet)
                    .frame(width: 40, height: 40)
                    .background(Color.tempoViolet.opacity(TempoOpacity.o15))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("It's past midnight. Get to bed.")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Sleep is part of the plan. The session waits for the morning.")
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text("TOMORROW MORNING")
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(sessionName)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                if blockCount > 0 {
                    Text(trainerDay?.isStrength == false ? "\(blockCount) blocks" : "\(blockCount) exercises")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TempoSpacing.md)
            .background(Color.tempoSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))

            Button(action: onSkipForTonight) {
                Text("Skip for tonight")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)
        }
        .padding(TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .padding(.horizontal, TempoSpacing.lg)
    }
}
