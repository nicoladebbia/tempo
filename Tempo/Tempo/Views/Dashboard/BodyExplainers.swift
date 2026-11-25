//
// BodyExplainers.swift
// Tempo
//
// What each number on the Body page and on Body progress means, how it is worked
// out and what to do about it. The "how" follows the code: the trend is
// `BodyProgress.trend`, the readings behind it are `BodyProgress.measurements`
// and the comparisons are `BodyHistory`. Change one of those and change its text.
// The strain gauge on the Body page reuses `Explainer.recoveryStrain` (Recovery).
//

import SwiftUI

extension Explainer {
    // MARK: Body progress

    static let bodyWeight = Explainer(
        id: "body-weight",
        title: "Weight",
        what: "Your latest weight from Apple Health, in the unit you chose. The date under it is the day it was weighed.",
        how: """
        Tempo reads the newest weight in Health and keeps one snapshot of it a day. If the same weighing is copied into several days, \
        it counts once, on the day it was measured. A reading below 20 kg or above 400 kg is treated as a scale glitch and left out.
        """,
        action: "Weigh yourself at the same time every morning, after the toilet and before you eat.",
        systemImage: "scalemass.fill"
    )

    static let bodyFat = Explainer(
        id: "body-fat",
        title: "Body fat",
        what: "The share of your weight that is fat, as a percentage, from Apple Health.",
        how: """
        Tempo reads the newest body fat reading in Health, which your scale or another app wrote there. \
        A reading below 2 percent or above 70 percent is treated as a glitch and left out. Scales only estimate it, so compare it with itself.
        """,
        action: "Use the same scale in the same conditions each time: the direction over weeks counts, one reading does not.",
        systemImage: "percent"
    )

    static let leanMass = Explainer(
        id: "body-lean-mass",
        title: "Lean mass",
        what: "Everything in your weight that is not fat, in your weight unit, as Apple Health has it.",
        how: """
        Tempo reads the newest lean body mass in Health and does not calculate it. \
        A reading below 10 kg or above 300 kg is treated as a glitch and left out.
        """,
        action: "Keep your protein and your hard sets up while the weight comes down: that is how lean mass holds.",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let bodyTrend = Explainer(
        id: "body-trend",
        title: "Trend",
        what: "Where the line is heading, in your unit a week. Body fat is in points of percentage a week.",
        how: """
        Tempo draws the straight line that best fits every reading in the range you picked and reads its slope as a weekly change, \
        so one heavy or light day does not move it. It needs at least 3 readings covering 7 days or more. \
        A change under 0.05 a week reads as holding steady.
        """,
        action: "Switch to 90 days before you judge it: single weeks swing with water and salt.",
        systemImage: "chart.line.uptrend.xyaxis"
    )

    // MARK: Body page

    /// The Recovery dial on the Body page. The line under it here is a quip for the score, not a comparison.
    static func bodyRecovery(zone: RecoveryZone?) -> Explainer {
        let action: LocalizedStringResource = switch zone {
        case .green: "You are in the green. Your body can take a normal training day, so train as planned."
        case .yellow: "You are in the yellow. Keep today's session moderate and stop a set or two short of your limit."
        case .red: "You are in the red. Swap the hard session for a walk or mobility and get to bed early tonight."
        case nil: "Connect WHOOP and wear it tonight to get your first score."
        }
        return Explainer(
            id: "body-recovery",
            title: "Recovery",
            what: "How ready your body is to take on strain today, from 0 to 100.",
            how: """
            WHOOP works it out overnight and Tempo shows the number it sends. Apple Health has no recovery score. \
            Green is 67 or more, yellow is 34 to 66 and red is below 34.
            """,
            action: action,
            systemImage: "heart.fill"
        )
    }

    static let bodyHRV = Explainer(
        id: "body-hrv",
        title: "HRV",
        what: "Heart rate variability: how much the time between your heartbeats changes, in milliseconds. Higher usually means a well recovered body.",
        how: """
        Tempo compares today with the average of the 7 days before today, and needs at least 3 of those days to have a reading. \
        Within 5 percent either way reads as near average. Above is green and below is red.
        """,
        action: "If it is below average, keep today's hard sets to two thirds of your usual and go to bed early.",
        systemImage: "waveform.path.ecg"
    )

    static let bodyRestingHeartRate = Explainer(
        id: "body-resting-hr",
        title: "Resting heart rate",
        what: "Your heart rate at rest, in beats per minute. A lower number than usual means your body is recovered.",
        how: """
        Tempo compares today with the average of the 7 days before today, and needs at least 3 of those days to have a reading. \
        Within 5 percent either way reads as near average. Below is green here and above is red.
        """,
        action: "If it is above average, lighten today's training and drink more water.",
        systemImage: "heart.fill"
    )

    static let bodySleep = Explainer(
        id: "body-sleep",
        title: "Sleep",
        what: "The hours you slept last night.",
        how: """
        Tempo compares last night with the average of the 7 days before today, and needs at least 3 of those days to have a reading. \
        Within 5 percent either way reads as near average. Above is green and below is red.
        """,
        action: "If you are below average, go to bed 30 minutes earlier tonight.",
        systemImage: "bed.double.fill"
    )

    static let bodyOxygen = Explainer(
        id: "body-spo2",
        title: "Blood oxygen",
        what: "How much oxygen your blood carries overnight, as a percentage.",
        how: "Tempo shows the reading it receives from WHOOP or Apple Health. 95 percent or more reads as normal and green. Below 95 reads as low and red. It is not compared with your average.",
        action: "One low night is noise. If it stays low for several nights, mention it to a doctor.",
        systemImage: "lungs.fill"
    )

    static let bodySleepStages = Explainer(
        id: "body-sleep-stages",
        title: "Last night's sleep",
        what: "How last night split between deep, REM, light and awake time, and how well you slept against what you needed.",
        how: """
        WHOOP measures the minutes in each stage and Tempo shows them as sent. Performance is WHOOP's sleep performance: \
        hours slept against the hours it says you needed.
        """,
        action: "To protect deep sleep, finish dinner at least three hours before bed and keep alcohol out of the evening.",
        systemImage: "moon.stars.fill"
    )

    static let bodyComparison = Explainer(
        id: "body-comparison",
        title: "Compared with",
        what: "How today stands against yesterday, last week and your recent average.",
        how: """
        Yesterday is today minus yesterday for recovery and HRV. Last week is today minus the same day a week ago for recovery and sleep. \
        The 7-day average is the average of the 7 days before today, shown once 3 of them have a reading. \
        A line shows only when both days have readings. Up is green, down is red.
        """,
        action: "If last week's line is red on sleep, repeat last week's bedtime tonight.",
        systemImage: "arrow.left.arrow.right"
    )
}

extension BodyMetric {
    /// The explainer for this measurement, so the trend card can explain the one on the chart.
    var explainer: Explainer {
        switch self {
        case .weight: .bodyWeight
        case .bodyFat: .bodyFat
        case .leanMass: .leanMass
        }
    }
}
