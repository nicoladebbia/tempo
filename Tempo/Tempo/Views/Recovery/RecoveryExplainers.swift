//
// RecoveryExplainers.swift
// Tempo
//
// What each number on the Recovery page means, how it is worked out and what to
// do about it. The score, the vitals, sleep and strain all come from WHOOP:
// Tempo does not score them, so the "how" says what WHOOP sends and what Tempo
// adds on top (the zone colours, the 30-day averages, the sleep debt). The
// thresholds named here are the ones in `RecoveryZone`, `StrainLevel` and
// `RecoveryViewModel`; change one and change its text.
//

import SwiftUI

extension Explainer {
    // MARK: Recovery score

    /// The Day dial. The action follows the zone the dial is showing.
    static func recoveryScore(zone: RecoveryZone?) -> Explainer {
        let action: LocalizedStringResource = switch zone {
        case .green: "You are in the green. Your body can take a normal training day, so train as planned."
        case .yellow: "You are in the yellow. Keep today's session moderate and stop a set or two short of your limit."
        case .red: "You are in the red. Swap the hard session for a walk or mobility and get to bed early tonight."
        case nil: "Wear your WHOOP tonight and pull down to refresh in the morning to get your first score."
        }
        return Explainer(
            id: "recovery-score",
            title: "Recovery",
            what: "How ready your body is to take on strain today, from 0 to 100.",
            how: """
            WHOOP works it out overnight, mainly from your heart rate variability, resting heart rate, \
            breathing rate and sleep, and Tempo shows the number it sends. Green is 67 or more, yellow is 34 to 66, \
            red is below 34. The line under the zone compares today with the average of your last 30 scored days.
            """,
            action: action,
            systemImage: "heart.fill"
        )
    }

    /// The Week and Month dial: an average, not a day.
    static let recoveryAverage = Explainer(
        id: "recovery-average",
        title: "Average recovery",
        what: "Your recovery score averaged over every day in this period that has a reading.",
        how: """
        Tempo adds up the daily WHOOP recovery scores in the period and divides by the number of days with a reading. \
        The line under it is the change against the period before: last week, last month or the 90 days before.
        """,
        action: "If the average is yellow or red and falling, take your easiest training day first this week and look at the sleep trend below.",
        systemImage: "heart.fill"
    )

    // MARK: Vitals

    static let hrv = Explainer(
        id: "hrv",
        title: "HRV",
        what: "Heart rate variability: how much the time between your heartbeats changes, in milliseconds. Higher usually means a well recovered body.",
        how: """
        WHOOP measures it while you sleep. Tempo compares it with the average of your last 30 days, today included, \
        and shows the difference. Above your average is the good side.
        """,
        action: "If it stays below your average for three days in a row, cut your hard sets by a third and protect your sleep.",
        systemImage: "waveform.path.ecg"
    )

    static let restingHeartRate = Explainer(
        id: "resting-hr",
        title: "Resting heart rate",
        what: "Your heart rate at rest, in beats per minute. A lower number than usual means your body is recovered.",
        how: """
        WHOOP takes it from your sleep. Tempo compares it with the average of your last 30 days, today included. \
        Below your average is the good side, so a down arrow is green here.
        """,
        action: "Several mornings in a row above your average can mean stress, poor sleep or illness: lighten training and sleep more.",
        systemImage: "heart.fill"
    )

    static let bloodOxygen = Explainer(
        id: "spo2",
        title: "Blood oxygen",
        what: "How much oxygen your blood carries overnight, as a percentage. Most healthy people sit around 95 to 100.",
        how: "WHOOP measures it while you sleep. Tempo compares it with the average of your last 30 days and shows if tonight was above or below it.",
        action: "One low night is noise. If it stays well below your usual for several nights, mention it to a doctor.",
        systemImage: "lungs.fill"
    )

    static let skinTemperature = Explainer(
        id: "skin-temp",
        title: "Skin temperature",
        what: "The temperature of your skin overnight, in degrees Celsius.",
        how: """
        WHOOP measures it while you sleep. Tempo compares it with the average of your last 30 days. \
        Within half a degree of your average shows green; further away in either direction shows red.
        """,
        action: "A jump of a degree or more over your average can be a sign you are getting ill: rest, drink water and watch how you feel.",
        systemImage: "thermometer.medium"
    )

    static func vital(_ metric: MetricType) -> Explainer {
        switch metric {
        case .hrv: hrv
        case .rhr: restingHeartRate
        case .spo2: bloodOxygen
        case .temp: skinTemperature
        }
    }

    // MARK: What drove the score

    static let sleepAgainstNeed = Explainer(
        id: "sleep-vs-need",
        title: "Sleep against what you need",
        what: "The hours you slept last night compared with the hours your body needs.",
        how: """
        The change is hours slept minus hours needed. Your need is your baseline need plus 30 minutes after a day with \
        strain from 10 to 14, or an hour after 14 or more. The baseline comes from a WHOOP export if you imported one. \
        Without it Tempo compares you with your 30-day average sleep instead, and with 8 hours if it has no history yet.
        """,
        action: "If you are below your need, move tonight's bedtime earlier by the difference.",
        systemImage: "bed.double.fill"
    )

    // MARK: Sleep

    static let sleepScore = Explainer(
        id: "sleep-score",
        title: "Sleep score",
        what: "How much of the sleep your body needed you actually got, as a percentage.",
        how: "It is WHOOP's sleep performance number: hours slept against the hours WHOOP says you needed. Tempo shows it as sent and does not recalculate it.",
        action: "Under 70 two nights in a row: bring your bedtime forward by 30 minutes tonight.",
        systemImage: "moon.zzz.fill"
    )

    static let sleepEfficiency = Explainer(
        id: "sleep-efficiency",
        title: "Sleep efficiency",
        what: "The share of your time in bed that you were actually asleep.",
        how: "WHOOP measures it. Tempo shows it green at 90 percent or more, amber from 80 to 89 and red below 80.",
        action: "Below 85, keep the room cool and dark and put the phone down for the last hour before bed.",
        systemImage: "bed.double.fill"
    )

    static let sleepStages = Explainer(
        id: "sleep-stages",
        title: "Sleep stages",
        what: "How your night split between awake, light sleep, deep sleep and REM sleep.",
        how: """
        WHOOP measures the minutes in each stage. The percentage under each one is its share of the whole night in bed, \
        awake time included. Deep sleep is when the body repairs; REM is when the mind does.
        """,
        action: "To protect deep sleep, finish dinner at least three hours before bed and keep alcohol out of the evening.",
        systemImage: "moon.stars.fill"
    )

    static let sleepDebt = Explainer(
        id: "sleep-debt",
        title: "Sleep debt",
        what: "How many hours short of your sleep need you have been over the last 7 recorded days.",
        how: """
        For each of those days Tempo takes your need minus the hours you slept, never below zero, and adds the \
        shortfalls up. A long night does not cancel a short one, and a day with no sleep reading counts as zero. \
        Your need is the baseline from a WHOOP export, or 8 hours without one. Under 2 hours is minimal, 2 to 5 moderate, \
        5 to 8 significant and 8 or more critical.
        """,
        action: "Follow the payback plan under it: add the minutes it says to your bedtime for the next few nights.",
        systemImage: "moon.zzz.fill"
    )

    static let sleepConsistency = Explainer(
        id: "sleep-consistency",
        title: "Sleep consistency",
        what: "How regular your bed and wake times are from one day to the next, as a percentage.",
        how: "WHOOP calculates it from your recent sleep and wake times. Tempo shows it as sent.",
        action: "Go to bed and get up within 30 minutes of the same times every day, weekends included.",
        systemImage: "clock.arrow.2.circlepath"
    )

    static let respiratoryRate = Explainer(
        id: "respiratory-rate",
        title: "Respiratory rate",
        what: "How many breaths you take per minute while you sleep.",
        how: "WHOOP measures it overnight. Tempo shows it as sent. It is one of the signals WHOOP uses for your recovery.",
        action: "A rate well above your usual, together with a higher resting heart rate, can be an early sign of illness: take it easy that day.",
        systemImage: "lungs"
    )

    // MARK: Strain

    static let strain = Explainer(
        id: "strain",
        title: "Strain",
        what: "How hard your day has been on your body, on a scale from 0 to 21.",
        how: """
        WHOOP scores it from your heart rate across the day, so it keeps rising as you move. Tempo names it: \
        below 5 is light, 5 to 9 low, 10 to 13 moderate, 14 to 17 moderate-high and 18 or more overreaching.
        """,
        action: "Match strain to your recovery: Tempo suggests pushing when recovery is 80 or more, a moderate day from 50 to 79 and an easy day below 50.",
        systemImage: "flame.fill"
    )

    static let dayHeartRate = Explainer(
        id: "day-heart-rate",
        title: "Average and max heart rate",
        what: "Your average and your highest heart rate so far today, in beats per minute.",
        how: """
        WHOOP records them across the day. The line under them is your average minus your resting heart rate: \
        how much activity lifted your heart above rest.
        """,
        action: "If your max is far above your usual on a day you did not train hard, check your caffeine, stress and sleep.",
        systemImage: "heart.circle.fill"
    )

    // MARK: Week and Month

    static let periodAverages = Explainer(
        id: "period-averages",
        title: "Period averages",
        what: "Your HRV, resting heart rate and sleep averaged over this period, with the change against the period before.",
        how: """
        Tempo averages the days that have a reading for each one, so a day with no HRV does not pull the HRV average down. \
        Green is the good side: up for HRV and sleep, down for resting heart rate.
        """,
        action: "Pick the one that is red and work on it first: sleep earlier for sleep, lighter days for HRV and resting heart rate.",
        systemImage: "chart.line.uptrend.xyaxis"
    )

    static let strainBalance = Explainer(
        id: "strain-balance",
        title: "Strain against recovery",
        what: "Whether the load you put on your body matches how recovered it was.",
        how: """
        Tempo compares the period's average recovery with its average strain. Recovery of 67 or more with strain of 12 or more is a \
        great balance. Recovery under 50 with strain of 14 or more means strain is outpacing recovery. Recovery of 67 or more with \
        strain under 10 means you have room to push. Anything else reads as moderate.
        """,
        action: "Do what the sentence under the bars says: it is the one change to make this week.",
        systemImage: "scalemass.fill"
    )

    static let recoveryDistribution = Explainer(
        id: "recovery-distribution",
        title: "Green, yellow and red days",
        what: "How many days in this period landed in each recovery zone.",
        how: "Tempo counts each day with a WHOOP score: 67 or more is green, 34 to 66 is yellow and below 34 is red.",
        action: "If red days are more than a quarter of the period, plan a deload week.",
        systemImage: "chart.bar.fill"
    )

    // MARK: Morning check-in

    static let morningCheckIn = Explainer(
        id: "check-in",
        title: "Morning check-in",
        what: "How you feel, in your own words: energy from 1 to 5, stress from 1 to 10 and soreness from 1 to 10.",
        how: """
        Tempo uses your answers to soften today's training plan and never to make it harder than your recovery allows. \
        A body part rated 8 or more in soreness is treated as a pain flag, and the plan moves load away from it.
        """,
        action: "Answer it honestly before you look at your score: how you feel is the check on the number.",
        systemImage: "face.smiling"
    )
}
