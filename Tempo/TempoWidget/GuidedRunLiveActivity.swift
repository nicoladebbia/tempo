//
// GuidedRunLiveActivity.swift
// TempoWidget
//
// Lock-screen + Dynamic Island presentation for a guided run (shuttles,
// fartlek, intervals), in the Tide look. The clock is system timer text
// (counting down for a countdown or rest, up for an open step), so nothing is
// pushed once a second; a paused run freezes on the app's own text.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - GuidedRunLiveActivity

struct GuidedRunLiveActivity: Widget {
    private let tone = ActivityTone.run

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedRunActivityAttributes.self) { context in
            GuidedRunLockScreenView(runTitle: context.attributes.runTitle, state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: Tide.s1) {
                        Image(systemName: state.isRest ? "hourglass" : "figure.run")
                            .foregroundStyle(tone)
                        WidgetLabel(state.isRest ? "Rest" : "Run", color: tone)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GuidedRunReadout(state: state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.stepTitle)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // The island's bottom corners are round: keep the line off them.
                    GuidedRunDetailRow(state: state)
                        .padding(.horizontal, Tide.s2)
                }
            } compactLeading: {
                Image(systemName: state.isRest ? "hourglass" : "figure.run")
                    .foregroundStyle(tone)
            } compactTrailing: {
                GuidedRunTimerText(state: state)
                    .font(Tide.numeral(Tide.numeralS * 0.8))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .frame(maxWidth: WidgetMetrics.compactClock, alignment: .trailing)
            } minimal: {
                Image(systemName: state.isRest ? "hourglass" : "figure.run")
                    .foregroundStyle(tone)
            }
            .keylineTint(tone)
        }
    }
}

// MARK: - GuidedRunTimerText

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
            Text.countdown(to: state.timerAnchor)
        } else {
            Text(timerInterval: state.timerAnchor ... Date.distantFuture, countsDown: false)
        }
    }
}

// MARK: - GuidedRunReadout

private struct GuidedRunReadout: View {
    let state: GuidedRunActivitySnapshot

    var body: some View {
        ActivityReadout(label: label, tone: state.isPaused ? Tide.text2 : ActivityTone.run) {
            GuidedRunTimerText(state: state)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: WidgetMetrics.readoutClock, alignment: .trailing)
        }
    }

    private var label: String {
        if state.isPaused {
            return "Paused"
        }
        if state.isRest {
            return "Rest"
        }
        return state.countsDown ? "Left" : "Time"
    }
}

// MARK: - GuidedRunDetailRow

private struct GuidedRunDetailRow: View {
    let state: GuidedRunActivitySnapshot

    var body: some View {
        HStack(spacing: Tide.s3) {
            if state.isPaused {
                Text("Paused")
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
            Spacer(minLength: Tide.s2)
            if let hr = state.heartRateText {
                Label(hr, systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Tide.danger)
            }
        }
        .font(Tide.caption)
        .foregroundStyle(Tide.text2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - GuidedRunLockScreenView

private struct GuidedRunLockScreenView: View {
    let runTitle: String
    let state: GuidedRunActivitySnapshot
    private let tone = ActivityTone.run

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // A fixed-height banner: stack the row and drop the detail
                // line at the largest text sizes so nothing is cut off.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    heading
                    GuidedRunReadout(state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(spacing: Tide.s3) {
                        ActivityTile(symbol: state.isRest ? "hourglass" : "figure.run", tone: tone)
                        heading
                        Spacer(minLength: Tide.s2)
                        GuidedRunReadout(state: state)
                    }
                    GuidedRunDetailRow(state: state)
                }
            }
        }
        .padding(Tide.s4)
        .tideActivityField(tone)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            WidgetLabel(runTitle, color: tone)
            Text(state.stepTitle)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}
