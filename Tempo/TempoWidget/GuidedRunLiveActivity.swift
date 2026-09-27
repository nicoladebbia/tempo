//
// GuidedRunLiveActivity.swift
// TempoWidget
//
// Guided run mode — lock-screen + Dynamic Island for a live guided run.
// `context.state` is a `GuidedRunActivitySnapshot`: work steps count UP from
// `timerAnchor` (open-ended — no cap to hit zero against), rest counts DOWN
// to it. Both use `Text(timerInterval:)` so the system ticks the digits with
// no per-second push from the app. Mirrors WorkoutLiveActivity's structure.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - GuidedRunLiveActivity

struct GuidedRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedRunActivityAttributes.self) { context in
            GuidedRunLockScreenView(runTitle: context.attributes.runTitle, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.orange)
                        Text(context.state.isRest ? "REST" : "RUN")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GuidedRunTimerText(state: context.state)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .frame(width: 70)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stepTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GuidedRunDetailRow(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                GuidedRunTimerText(state: context.state)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - GuidedRunTimerText

/// Renders the shared timer rule: paused freezes on `frozenText`; otherwise a
/// date-based `Text(timerInterval:)` counts up (work) or down (rest/countdown).
private struct GuidedRunTimerText: View {
    let state: GuidedRunActivitySnapshot

    var body: some View {
        if state.isPaused {
            Text(state.frozenText ?? "--:--")
        } else if state.countsDown {
            // `Text(timerInterval:)` traps if lowerBound > upperBound.
            // `state.timerAnchor` is a snapshot from whenever the app last
            // pushed it — by the time the widget actually renders (any real
            // ActivityKit propagation delay), "now" can already be past a
            // very-short-lived anchor. Guard rather than trust the source
            // never produces this: a stale "0:00" for one frame beats a crash.
            if state.timerAnchor > Date.now {
                Text(timerInterval: Date.now ... state.timerAnchor, countsDown: true)
            } else {
                Text("0:00")
            }
        } else {
            Text(timerInterval: state.timerAnchor ... Date.distantFuture, countsDown: false)
        }
    }
}

// MARK: - GuidedRunDetailRow

private struct GuidedRunDetailRow: View {
    let state: GuidedRunActivitySnapshot

    var body: some View {
        HStack(spacing: 10) {
            if state.isPaused {
                Text("PAUSED")
                    .fontWeight(.bold)
            } else if let next = state.nextStepText {
                Text(next)
            } else if let detail = state.detailText {
                Text(detail)
            }
            if let distance = state.distanceText {
                Text(distance)
            }
            if let pace = state.paceText {
                Text(pace)
            }
            Spacer()
            if let hr = state.heartRateText {
                Label(hr, systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - GuidedRunLockScreenView

private struct GuidedRunLockScreenView: View {
    let runTitle: String
    let state: GuidedRunActivitySnapshot

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isRest ? "hourglass" : "figure.run")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(runTitle.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(state.stepTitle)
                    .font(.headline)
                    .lineLimit(1)
                GuidedRunDetailRow(state: state)
            }

            Spacer()

            GuidedRunTimerText(state: state)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.6))
        .activitySystemActionForegroundColor(.orange)
    }
}
