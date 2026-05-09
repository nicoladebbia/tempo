//
// FocusTimerLiveActivity.swift
// Tempo
//
// Created by Tempo on 09/05/2026.
//
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - FocusTimerLiveActivity

struct FocusTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTimerActivityAttributes.self) { context in
            // Lock-screen + banner presentation
            FocusTimerLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.blue)
                        Text("Study")
                            .font(.caption2.bold())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date() ... context.state.phaseEndsAt, countsDown: true)
                        .monospacedDigit()
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let subject = context.state.subject {
                        Text(subject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.phaseLabel)
                            .font(.caption2)
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Session \(context.state.sessionIndex)/\(context.state.totalSessions)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(timerInterval: Date() ... context.state.phaseEndsAt, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - FocusTimerLockScreenView

private struct FocusTimerLockScreenView: View {
    let state: FocusTimerActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.subject ?? "Focus")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(state.phaseLabel)
                    .font(.caption2)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text(timerInterval: Date() ... state.phaseEndsAt, countsDown: true)
                .monospacedDigit()
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
