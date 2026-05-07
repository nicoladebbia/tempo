//
// DrillSergeantBubble.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - DrillSergeantBubble

// Per DESIGN_SYSTEM.md Section 8.2 — Prescription Card variant:
// Ink Black bg, Signal Red accent, bold drill-sergeant copy.

struct DrillSergeantBubble: View {
    let message: String
    var intensity: DrillSergeantIntensity = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: intensity.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(intensity.accentColor)

                Text(intensity.label)
                    .font(.tempoOrdersLabel)
                    .tracking(TempoTracking.ordersLabel)
                    .foregroundStyle(Color.tempoAmber)
            }

            Text(message)
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoBone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoInk)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .shadow(
            color: intensity.accentColor.opacity(0.15),
            radius: 8, x: 0, y: 0
        )
    }
}

// MARK: - DrillSergeantIntensity

enum DrillSergeantIntensity {
    case encouraging
    case standard
    case urgent
    case critical

    var icon: String {
        switch self {
        case .encouraging: "hand.thumbsup.fill"
        case .standard: "megaphone.fill"
        case .urgent: "exclamationmark.triangle.fill"
        case .critical: "flame.fill"
        }
    }

    var label: String {
        switch self {
        case .encouraging: "ORDERS"
        case .standard: "ORDERS"
        case .urgent: "WARNING"
        case .critical: "FINAL WARNING"
        }
    }

    var accentColor: Color {
        switch self {
        case .encouraging: .tempoSuccess
        case .standard: .tempoSignal
        case .urgent: .tempoAmber
        case .critical: .tempoSignal
        }
    }
}

// MARK: - DrillSergeantContext

// Context-aware message generation based on progress, time, streaks, and patterns.

struct DrillSergeantContext {
    let completedCount: Int
    let totalCount: Int
    let streakCount: Int
    let timeToPS5: TimeInterval
    let totalStudyMinutes: Int
    let studyTargetMinutes: Int
    let recoveryScore: Double?
    let dailyState: DailyAccountabilityState
    let isWeekend: Bool
    let hourOfDay: Int

    var completionPercentage: Double {
        guard totalCount > 0 else {
            return 0
        }
        return Double(completedCount) / Double(totalCount)
    }

    var remainingCount: Int {
        totalCount - completedCount
    }

    var hoursToPS5: Double {
        timeToPS5 / 3600.0
    }

    var studyRemaining: Int {
        max(0, studyTargetMinutes - totalStudyMinutes)
    }
}

// MARK: - DrillSergeantMessageGenerator

enum DrillSergeantMessageGenerator {
    /// Generate a context-aware drill sergeant message with appropriate intensity.
    static func generate(context: DrillSergeantContext) -> (message: String, intensity: DrillSergeantIntensity)? {
        switch context.dailyState {
        case .morningSetup:
            (morningMessage(context: context), .standard)
        case .tracking:
            trackingMessage(context: context)
        case .approachingDeadline:
            (approachingMessage(context: context), .urgent)
        case .finalWarning:
            (finalWarningMessage(context: context), .critical)
        case .dayFailed:
            (failedMessage(context: context), .critical)
        case .unlocked:
            nil // No drill sergeant when unlocked
        case .overrideActive:
            ("Rest day active. Recovery is part of the process. Don't make it a habit.", .encouraging)
        case .review:
            nil
        }
    }

    // MARK: - Morning Messages

    private static func morningMessage(context: DrillSergeantContext) -> String {
        if context.streakCount > 7 {
            return "Day \(context.streakCount + 1) starts now. You didn't build a \(context.streakCount)-day streak to quit today. Set your non-negotiables."
        }
        if context.isWeekend {
            return "Weekend doesn't mean day off. Set your non-negotiables and earn your free time."
        }
        let messages = [
            "New day, new chance to not be mediocre. Set your non-negotiables.",
            "Yesterday is gone. Today is what matters. Set up and get moving.",
            "The alarm went off for a reason. Set your tasks and handle your business.",
        ]
        return messages[abs(Calendar.current.component(.day, from: Date())) % messages.count]
    }

    // MARK: - Tracking Messages (context-aware)

    private static func trackingMessage(context: DrillSergeantContext) -> (String, DrillSergeantIntensity) {
        // Zero progress
        if context.completedCount == 0 {
            if context.hoursToPS5 < 4 {
                return ("Zero done. \(formatTime(context.timeToPS5)) until lockdown. You haven't started. Move.", .urgent)
            }
            if context.hourOfDay > 12 {
                return ("It's past noon and you haven't done a single thing. The day won't wait for you.", .urgent)
            }
            return ("Zero progress. The day isn't going to handle itself.", .standard)
        }

        // Study-specific pressure
        if context.studyRemaining > 0, context.totalStudyMinutes == 0, context.hourOfDay > 14 {
            return ("You usually skip study on days like this. Not today. \(context.studyTargetMinutes)min target. Start now.", .urgent)
        }

        // Almost done
        if context.remainingCount == 1 {
            if context.streakCount > 0 {
                return ("One left. \(context.streakCount)-day streak on the line. Finish it.", .standard)
            }
            return ("Just 1 more. You're right there. Don't quit this close to the finish.", .encouraging)
        }

        // Low recovery context
        if let recovery = context.recoveryScore, recovery < 40 {
            return (
                "Recovery is \(Int(recovery))%. Your body's asking for rest, but your mind needs work. \(context.completedCount)/\(context.totalCount) done. Keep pushing smart.",
                .standard
            )
        }

        // Streak pressure
        if context.streakCount >= 10 {
            return (
                "\(context.completedCount)/\(context.totalCount) done. \(context.streakCount)-day streak. Don't be the reason it ends.",
                .standard
            )
        }

        // Study progress
        if context.studyRemaining > 30, context.hoursToPS5 < 3 {
            return (
                "\(context.studyRemaining)min of study left and only \(formatTime(context.timeToPS5)) remaining. Open the timer. Now.",
                .urgent
            )
        }

        // General progress with time context
        if context.hoursToPS5 < 2 {
            return (
                "\(context.completedCount)/\(context.totalCount) done. \(formatTime(context.timeToPS5)) left. No more procrastinating.",
                .urgent
            )
        }

        // Standard progress messages
        let remaining = context.remainingCount
        if context.completionPercentage >= 0.5 {
            return (
                "Over halfway. \(context.completedCount)/\(context.totalCount) done. Momentum is on your side. Don't stop.",
                .encouraging
            )
        }

        return ("\(context.completedCount)/\(context.totalCount) done. \(remaining) to go. Keep moving.", .standard)
    }

    // MARK: - Approaching Deadline Messages

    private static func approachingMessage(context: DrillSergeantContext) -> String {
        if context.studyRemaining > 60 {
            return "\(formatTime(context.timeToPS5)) left and \(context.studyRemaining)min of study remaining. You're behind. Every minute counts."
        }
        if context.remainingCount > 2 {
            return "\(context.remainingCount) tasks still open with \(formatTime(context.timeToPS5)) left. Clock's ticking. You know what to do."
        }
        if context.streakCount > 5 {
            return "Your \(context.streakCount)-day streak doesn't care about your excuses. \(formatTime(context.timeToPS5)) remaining. GO."
        }
        return "Clock's ticking. \(formatTime(context.timeToPS5)) to PS5 time. \(context.remainingCount) tasks left. You're running out of daylight."
    }

    // MARK: - Final Warning Messages

    private static func finalWarningMessage(context: DrillSergeantContext) -> String {
        if context.streakCount > 0 {
            return "\(formatTime(context.timeToPS5)) left. \(context.streakCount)-day streak DIES if you don't finish. This is it."
        }
        if context.remainingCount == 1 {
            return "Last chance. \(formatTime(context.timeToPS5)). ONE task between you and freedom. Do it NOW."
        }
        return "Last chance. PS5 time is almost here and you're not done. \(context.remainingCount) tasks. \(formatTime(context.timeToPS5)). No excuses."
    }

    // MARK: - Day Failed Messages

    private static func failedMessage(context: DrillSergeantContext) -> String {
        if context.streakCount > 0 {
            return "PS5 time came and went. Your \(context.streakCount)-day streak just died. Remember this feeling tomorrow."
        }
        if context.completedCount == 0 {
            return "Not a single task done. PS5 time passed. Today was a waste. Tomorrow, be different."
        }
        return "PS5 time came and went. \(context.completedCount)/\(context.totalCount) done. Close but not good enough. No excuses tomorrow."
    }

    // MARK: - Helpers

    private static func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
