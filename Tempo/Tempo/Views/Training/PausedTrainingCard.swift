//
// PausedTrainingCard.swift
// Tempo
//
// Pause/travel-pain feature — Today's calm "Paused — recover" card, shown
// INSTEAD of the normal workout content while today is covered by a
// `TrainingPause` and today's plan is still untouched (`.planned` — a
// started/completed session is sacred and is never interrupted by a pause
// that started later, same invariant `TrainingPauseSchedule.apply` itself
// enforces). Self-contained, same drop-in pattern as
// `MissedTrainerSessionCard.swift`/`WeeklyUploadPromptCard.swift` — see
// `TodayWorkoutView.swift`'s body for the one-line insertion point.
//

import SwiftData
import SwiftUI

// MARK: - PausedTrainingCard

struct PausedTrainingCard: View {
    @Bindable
    var viewModel: TrainingViewModel
    let pause: TrainingPause
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var showResumeOptions = false

    var body: some View {
        // A pause is a stretch of days, so the hero is that count, with a ring
        // that fills toward the planned return when there is one.
        TrainDayHero(
            label: String(localized: "Paused"),
            figure: "\(daysPaused)",
            unit: daysPaused == 1 ? String(localized: "day", comment: "Unit under a number, singular") : String(localized: "days", comment: "Unit under a number, plural"),
            caption: title,
            chips: [pause.reason.displayName]
        ) {
            returnRing
        } footer: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text(subtitle)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showResumeOptions = true
                } label: {
                    Text("Resume now")
                }
                .buttonStyle(.trainBanner(tint: TideTrain.positive))
            }
        }
        .confirmationDialog("Resume training?", isPresented: $showResumeOptions, titleVisibility: .visible) {
            if needsFixedModeDecision {
                Button("Continue this week where I left off (shift program)") {
                    resume(decision: .shiftForward)
                }
                Button("Just continue from today") {
                    resume(decision: .continueFromToday)
                }
            } else {
                Button("Resume now") {
                    resume(decision: .continueFromToday)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if needsFixedModeDecision {
                Text(
                    "Your trainer's program uses fixed weekdays. Pick up the same week you paused in, or just continue from today's weekday."
                )
            }
        }
    }

    private var needsFixedModeDecision: Bool {
        pause.scheduleModeAtPauseTyped == .fixed
    }

    // MARK: - Hero

    /// Whole days since the pause began, counting today.
    private var daysPaused: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: pause.startDate)
        let today = cal.startOfDay(for: Date())
        return max(1, (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }

    /// Whole days from the start to the planned return, inclusive; nil when open-ended.
    private var plannedDays: Int? {
        guard let end = pause.plannedEndDate else {
            return nil
        }
        let cal = Calendar.current
        let days = (cal.dateComponents([.day], from: cal.startOfDay(for: pause.startDate), to: cal.startOfDay(for: end)).day ?? 0) + 1
        return max(days, 1)
    }

    @ViewBuilder
    private var returnRing: some View {
        if let plannedDays {
            TrainRing(
                progress: Double(min(daysPaused, plannedDays)) / Double(plannedDays),
                tint: TideTrain.positive,
                diameter: TideTrain.heroRing
            ) {
                Image(systemName: "leaf.fill")
                    .font(Tide.title2)
                    .foregroundStyle(TideTrain.positive)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pause progress")
            .accessibilityValue("Day \(min(daysPaused, plannedDays)) of \(plannedDays)")
        } else {
            TideIconTile(systemName: "leaf.fill", tint: TideTrain.positive, size: TideTrainSession.stateTile)
        }
    }

    private var title: String {
        switch pause.reason {
        case .sick: String(localized: "Recover — training is on hold")
        case .injured: String(localized: "Recover — training is on hold")
        case .travel: String(localized: "Away — training is on hold")
        case .other: String(localized: "Training is on hold")
        }
    }

    private var subtitle: String {
        if let end = pause.plannedEndDate {
            return String(localized: "Back on \(end.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).")
        }
        return String(localized: "Resume whenever you're ready.")
    }

    private func resume(decision: PauseResumeDecision) {
        viewModel.resumePause(pause, decision: decision, modelContext: modelContext)
        HapticManager.selection()
    }
}
