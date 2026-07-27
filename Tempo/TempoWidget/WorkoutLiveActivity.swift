//
// WorkoutLiveActivity.swift
// TempoWidget
//
// §3.9 — lock-screen + Dynamic Island presentation for a live workout.
// Resting shows a live countdown to the next set; lifting shows the current
// exercise and set position; the bottom bar tracks whole-session working-set
// progress. Mirrors FocusTimerLiveActivity's structure.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(.orange)
                        Text(context.state.workoutType)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("PAUSED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    } else if context.state.isResting, let end = context.state.restEndsAt {
                        Text(timerInterval: Date.now ... end, countsDown: true)
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .frame(width: 60)
                    } else {
                        Text("\(context.state.completedSets)/\(context.state.totalSets)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isResting ? "Rest — next: \(context.state.exerciseName)" : context.state.exerciseName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.setText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(
                            value: Double(context.state.completedSets),
                            total: Double(max(1, context.state.totalSets))
                        )
                        .tint(.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                if context.state.isResting, let end = context.state.restEndsAt, !context.state.isPaused {
                    Text(timerInterval: Date.now ... end, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Lock Screen

private struct WorkoutLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isResting ? "hourglass" : "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.workoutType)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.isPaused ? "Paused" : state.setText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if state.isPaused {
                    Text("PAUSED")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if state.isResting, let end = state.restEndsAt {
                    Text("REST")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(timerInterval: Date.now ... end, countsDown: true)
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .frame(width: 70)
                } else {
                    Text("SETS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("\(state.completedSets)/\(state.totalSets)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.6))
        .activitySystemActionForegroundColor(.orange)
    }
}
