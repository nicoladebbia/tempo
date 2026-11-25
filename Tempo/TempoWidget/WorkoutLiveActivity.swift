//
// WorkoutLiveActivity.swift
// TempoWidget
//
// §3.9 — lock-screen + Dynamic Island presentation for a live workout, in the
// Tide look. Resting shows a live countdown to the next set (system timer
// text, so it ticks without the app pushing every second); lifting shows the
// current exercise and set position; the bar tracks whole-session
// working-set progress.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Presentation

private extension WorkoutActivityAttributes.ContentState {
    var symbol: String {
        isPaused ? "pause.fill" : (isResting ? "hourglass" : "dumbbell.fill")
    }

    /// The second line: where in the exercise, or what the pause is.
    var detail: String {
        if isPaused {
            return "Paused"
        }
        return isResting ? "Resting · \(setText)" : setText
    }

    var progress: Double? {
        totalSets > 0 ? min(max(Double(completedSets) / Double(totalSets), 0), 1) : nil
    }

    /// "12 of 20 sets"
    var progressText: String {
        "\(completedSets) of \(totalSets) sets"
    }
}

// MARK: - WorkoutLiveActivity

struct WorkoutLiveActivity: Widget {
    private let tone = ActivityTone.workout

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: Tide.s1) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(tone)
                        WidgetLabel(state.workoutType, color: tone)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutReadout(state: state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.isResting ? "Rest · next: \(state.exerciseName)" : state.exerciseName)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: Tide.s2) {
                        Text(state.detail)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                        WorkoutBar(state: state, tone: tone)
                    }
                }
            } compactLeading: {
                Image(systemName: state.isPaused ? "pause.fill" : "dumbbell.fill")
                    .foregroundStyle(tone)
            } compactTrailing: {
                if state.isResting, let end = state.restEndsAt, !state.isPaused {
                    Text.countdown(to: end)
                        .font(Tide.numeral(Tide.numeralS * 0.8))
                        .monospacedDigit()
                        .foregroundStyle(tone)
                        .frame(maxWidth: WidgetMetrics.compactClock, alignment: .trailing)
                } else {
                    Text("\(state.completedSets)/\(state.totalSets)")
                        .font(Tide.numeral(Tide.numeralS * 0.8))
                        .monospacedDigit()
                        .foregroundStyle(Tide.text)
                }
            } minimal: {
                if state.isResting, let end = state.restEndsAt, !state.isPaused {
                    Text.countdown(to: end)
                        .font(Tide.label)
                        .monospacedDigit()
                        .foregroundStyle(tone)
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: state.isPaused ? "pause.fill" : "dumbbell.fill")
                        .foregroundStyle(tone)
                }
            }
            .keylineTint(tone)
        }
    }
}

// MARK: - WorkoutBar

/// The bar under the exercise: whole-session progress while lifting, and while
/// resting a bar that drains from full to empty over the rest. The drain is a
/// system timer bar, so it runs by itself with no pushes from the app.
private struct WorkoutBar: View {
    let state: WorkoutActivityAttributes.ContentState
    let tone: Color

    var body: some View {
        if let range = state.restDrainRange {
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tone)
            .accessibilityHidden(true)
        } else {
            WidgetBar(progress: state.progress, color: tone)
        }
    }
}

// MARK: - WorkoutReadout

/// The right-hand figure: the rest countdown, the sets done, or the pause.
private struct WorkoutReadout: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            ActivityReadout(label: "Session") { Text("Paused").font(Tide.headline) }
        } else if state.isResting, let end = state.restEndsAt {
            ActivityReadout(label: "Rest", tone: ActivityTone.workout) {
                Text.countdown(to: end)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: WidgetMetrics.readoutClock, alignment: .trailing)
            }
        } else {
            ActivityReadout(label: "Sets") {
                Text("\(state.completedSets)/\(state.totalSets)")
            }
        }
    }
}

// MARK: - WorkoutLockScreenView

private struct WorkoutLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    private let tone = ActivityTone.workout

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // The lock screen is a fixed height: at the largest text sizes
                // the row stacks and the bar is left out, so nothing is cut off.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    heading
                    WorkoutReadout(state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    HStack(spacing: Tide.s3) {
                        ActivityTile(symbol: state.symbol, tone: tone)
                        heading
                        Spacer(minLength: Tide.s2)
                        WorkoutReadout(state: state)
                    }
                    if state.progress != nil {
                        HStack(spacing: Tide.s3) {
                            WorkoutBar(state: state, tone: tone)
                            Text(state.progressText)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(Tide.s4)
        .tideActivityField(tone)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            WidgetLabel(state.workoutType, color: tone)
            Text(state.exerciseName)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state.detail)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
        }
    }
}
