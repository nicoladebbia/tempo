//
// FocusTimerLiveActivity.swift
// TempoWidget
//
// Lock-screen + Dynamic Island presentation for a running focus timer, in the
// Tide look. The countdown is system timer text, so it ticks every second
// without the app pushing an update; the ring shows how far into the phase
// the last update was.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Presentation

private extension FocusTimerActivityAttributes.ContentState {
    var title: String {
        subject ?? String(localized: "Focus")
    }

    var phaseText: String {
        isPaused ? String(localized: "Paused") : phaseLabel
    }

    var sessionText: String {
        String(localized: "Session \(sessionIndex) of \(totalSessions)")
    }
}

// MARK: - FocusTimerLiveActivity

struct FocusTimerLiveActivity: Widget {
    private let tone = ActivityTone.focus

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTimerActivityAttributes.self) { context in
            FocusTimerLockScreenView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: Tide.s1) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(tone)
                        WidgetLabel(String(localized: "Focus"), color: tone)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusReadout(state: state)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        WidgetLabel(state.phaseText)
                        Spacer(minLength: Tide.s2)
                        Text(state.sessionText)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                    }
                    // The island's bottom corners are round: keep the line off them.
                    .padding(.horizontal, Tide.s2)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(tone)
            } compactTrailing: {
                if state.isPaused {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Tide.text2)
                } else {
                    Text.countdown(to: state.phaseEndsAt)
                        .font(Tide.numeral(Tide.numeralS * 0.8))
                        .monospacedDigit()
                        .foregroundStyle(tone)
                        .frame(maxWidth: WidgetMetrics.compactClock, alignment: .trailing)
                }
            } minimal: {
                if state.isPaused {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Tide.text2)
                } else {
                    Text.countdown(to: state.phaseEndsAt)
                        .font(Tide.label)
                        .monospacedDigit()
                        .foregroundStyle(tone)
                        .minimumScaleFactor(0.5)
                }
            }
            .keylineTint(tone)
        }
    }
}

// MARK: - FocusReadout

private struct FocusReadout: View {
    let state: FocusTimerActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            ActivityReadout(label: String(localized: "Timer")) { Text("Paused").font(Tide.headline) }
        } else {
            ActivityReadout(label: String(localized: "Left"), tone: ActivityTone.focus) {
                Text.countdown(to: state.phaseEndsAt)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: WidgetMetrics.readoutClock, alignment: .trailing)
            }
        }
    }
}

// MARK: - FocusTimerLockScreenView

private struct FocusTimerLockScreenView: View {
    let state: FocusTimerActivityAttributes.ContentState
    private let tone = ActivityTone.focus

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // A fixed-height banner: stack the row and drop the ring at the
                // largest text sizes so nothing is cut off.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    heading
                    FocusReadout(state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: Tide.s3) {
                    ring
                    heading
                    Spacer(minLength: Tide.s2)
                    FocusReadout(state: state)
                }
            }
        }
        .padding(Tide.s4)
        .tideActivityField(tone)
    }

    private var ring: some View {
        ZStack {
            WidgetRing(progress: state.progress, color: tone, lineWidth: WidgetMetrics.activityRingLine)
            Image(systemName: state.isPaused ? "pause.fill" : "book.fill")
                .font(.tideGlyph(WidgetMetrics.activityRingGlyph))
                .foregroundStyle(tone)
        }
        .frame(width: Tide.s10 + Tide.s2, height: Tide.s10 + Tide.s2)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            WidgetLabel(state.phaseText, color: tone)
            Text(state.title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state.sessionText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
        }
    }
}
