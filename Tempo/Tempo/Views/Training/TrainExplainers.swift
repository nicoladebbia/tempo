//
// TrainExplainers.swift
// Tempo
//
// What every Train number means, in three short answers each: what it is,
// how it is worked out, what to do about it. The "how" of each one states
// what the code really does (the engine, view or model it comes from is named
// in the comment above it) and must be changed together with that code.
//
// Each explainer is defined once here and reused wherever its number shows.
//

import Foundation

enum TrainExplainers {
    // MARK: - Effort

    /// `PlannedSet.targetRIR` (the caption on the set) and `PlannedSet.effectiveRIR`.
    static let rir = Explainer(
        id: "train.rir",
        title: "Reps in reserve (RIR)",
        what: "How many more reps you could still do at the end of a set before form would break.",
        how: "Each set has a target. When you log how hard a set felt (RPE), Tempo counts the reps in reserve as 10 minus that number.",
        action: "End the set with about that many reps left, and log your effort so the next weight fits.",
        systemImage: "speedometer"
    )

    /// `plan.sessionRPE` (the card after a workout) and the per-set RPE chips.
    static let rpe = Explainer(
        id: "train.rpe",
        title: "RPE",
        what: "A 1 to 10 rating of how hard a set or a whole session felt, where 10 is all out.",
        how: "You enter it. For a set, Tempo reads it as reps in reserve (10 minus RPE); a session rating is read by your coach the next day.",
        action: "Rate it right after you finish and be honest, because Tempo uses it to set your next weights.",
        systemImage: "gauge.with.needle"
    )

    // MARK: - Strength numbers

    /// `StrengthStandards.e1RM`, `PlannedSet.estimated1RM`, all-time best in the logger strip.
    static let bestE1RM = Explainer(
        id: "train.e1rm.best",
        title: "Best estimated 1RM",
        what: "The heaviest weight you could lift once, estimated from your sets instead of tested.",
        how: "Weight × (1 + (reps + reps in reserve) ÷ 30), counting reps up to 12 and reserve up to 4. This is the highest estimate from every session of this lift.",
        action: "Use it to judge progress over weeks, not to test yourself. If it climbs, the plan is working.",
        systemImage: "scalemass"
    )

    /// `Exercise.currentEstimated1RM`: the strongest estimate of the last 42 days.
    static let currentE1RM = Explainer(
        id: "train.e1rm.current",
        title: "Current 1RM",
        what: "The heaviest weight you could lift once, estimated from your sets instead of tested.",
        how: "Weight × (1 + (reps + reps in reserve) ÷ 30), counting reps up to 12 and reserve up to 4. This is the highest estimate from the last 6 weeks, so one light day does not read as getting weaker.",
        action: "Watch it over weeks. If it is flat, ask whether you are eating, sleeping and progressing the weights enough.",
        systemImage: "scalemass"
    )

    /// The weight Tempo suggests for a set (`PrescriptionMath`, `calculateProgressiveOverload`).
    static let target = Explainer(
        id: "train.target",
        title: "Target weight",
        what: "The weight Tempo suggests for this set today.",
        how: "It works back from your recent best estimated 1RM to the weight that leaves the planned reps in reserve. Low recovery, a deload week or a very hard last session makes it lighter or holds it.",
        action: "Start at the target. If it feels clearly too heavy or too light, change the weight and log what you really lifted.",
        systemImage: "target"
    )

    /// `TrainingEngine.personalRecordKind`.
    static let personalRecord = Explainer(
        id: "train.pr",
        title: "Personal record",
        what: "A new best on a lift, beyond anything you have logged before.",
        how: "The first log of a lift only sets the starting mark. After that, a set is a record when it beats your best estimated 1RM and your best plain weight-and-reps (up to 12 reps), or is your heaviest weight yet. Bodyweight moves count most reps. Warm-ups and drop sets never count.",
        action: "Share it if you like, and log your effort honestly so the next target builds on the new best.",
        systemImage: "trophy"
    )

    // MARK: - Session numbers

    /// `PlannedSet.volume` summed by `TrainingViewModel.formattedVolume`.
    static let volume = Explainer(
        id: "train.volume",
        title: "Volume",
        what: "The total weight you lifted in the workout.",
        how: "Weight × reps for every working set, added up. Ramp-up sets are left out, drop sets are in, and a one-sided move counts both sides.",
        action: "Compare it with the same workout last week, not with a different day.",
        systemImage: "chart.bar"
    )

    /// `ExerciseHistory.totalVolume` over the last 30 days.
    static let volume30 = Explainer(
        id: "train.volume30",
        title: "Volume (30 days)",
        what: "The total weight you lifted on this exercise over the last 30 days.",
        how: "The volume of each session in the last 30 days, added up. A session's volume is weight × reps for its working sets.",
        action: "If it rises over several weeks along with your estimated 1RM, the plan is working.",
        systemImage: "chart.bar"
    )

    /// `WorkoutPlan.completedSets` over `WorkoutPlan.totalSets`.
    static let setsDone = Explainer(
        id: "train.sets",
        title: "Sets done",
        what: "How many of today's working sets you have finished.",
        how: "Finished working sets over planned working sets. Ramp-up sets are not counted.",
        action: "Keep going until it is full. A set you skip is removed from the plan, so it stops counting.",
        systemImage: "checkmark.circle"
    )

    /// `TodayWorkoutView.estimatedDuration(plan:)`; used when the plan has no stored duration.
    static let estimatedTime = Explainer(
        id: "train.time",
        title: "Estimated time",
        what: "About how long today's session should take from start to finish.",
        how: "5 minutes of warm-up, 2.5 minutes for each working set of a big multi-joint lift, 1.5 for each smaller one, 1 for each ramp-up set, 1 between exercises and 3 of cooldown, never under 20. It does not know your own rest times.",
        action: "If it does not fit your window, drop an exercise or two instead of rushing your rests.",
        systemImage: "clock"
    )

    /// `plan.recoveryAdjustment`, `TrainingEngine.recoverySetsDropped` and `recoveryLoadScale`.
    static let recoveryColour = Explainer(
        id: "train.recovery",
        title: "Recovery colour",
        what: "How recovered you are today, and how Tempo shaped the session because of it.",
        how: "Tempo works it out from your recovery score. Green keeps the full plan. Yellow and red take a set off each big lift, two when recovery is very low, and can lower the weights a little.",
        action: "Follow the shorter session today. If you feel better than the colour says, add a set with + during the workout.",
        systemImage: "heart.text.square"
    )

    /// `TrainingLoadCard`, `ReadinessTrendMath.acuteChronicRatio`.
    static let trainingLoad = Explainer(
        id: "train.load",
        title: "Training load (ACWR)",
        what: "How hard you have trained recently compared with the last four weeks.",
        how: "Tempo averages your daily Whoop strain over about a week and over about four weeks, giving recent days more weight, then divides one by the other. It needs at least 14 days of strain.",
        action: "Stay between 0.8 and 1.3. Above 1.3 take an easier day, because the coach blocks two-a-days there. Below 0.8 you have room to do more.",
        systemImage: "chart.line.uptrend.xyaxis"
    )

    /// Whoop strain as stored on `ActivitySession.strain`.
    static let strain = Explainer(
        id: "train.strain",
        title: "Whoop strain",
        what: "Whoop's score for how much a session or day asked of your body, from 0 to 21.",
        how: "Whoop works it out from your heart rate, and Tempo shows the number as Whoop reports it. A total adds up every session.",
        action: "After a very high number, make the next day easier and aim for an early night.",
        systemImage: "bolt.heart"
    )

    // MARK: - Heatmap

    /// `MuscleHeatEngine.volumes`: secondary muscles earn `secondaryFactor` (half).
    static let heatVolume = Explainer(
        id: "train.heat.volume",
        title: "7-day volume",
        what: "How much weight you lifted for this muscle in the last 7 days.",
        how: "Weight × reps for every set, counted in full for the muscle an exercise mainly trains and at half for the muscles that help.",
        action: "Compare it with last week. If a muscle is far behind the others, add a set or two for it next session.",
        systemImage: "chart.bar"
    )

    /// `MuscleHeatEngine.setCounts`: primary muscle only.
    static let heatSets = Explainer(
        id: "train.heat.sets",
        title: "Working sets",
        what: "How many sets you did for this muscle in the last 7 days.",
        how: "It counts the sets of exercises that mainly train this muscle. Helper muscles do not get the set.",
        action: "If it is low for a muscle you want to grow, add a set or two for it in your next sessions.",
        systemImage: "number"
    )

    /// `MuscleHeatEngine.heat`: every muscle over the hottest one.
    static let heatScale = Explainer(
        id: "train.heat.scale",
        title: "Heatmap colours",
        what: "How much each muscle did compared with your hardest-worked muscle this week.",
        how: "Each muscle's 7-day volume divided by the highest muscle's volume, so the hottest muscle is always at the top of the scale.",
        action: "Look for the cold spots. The colours show training volume, not how recovered a muscle is.",
        systemImage: "figure.arms.open"
    )

    // MARK: - Progress and plan

    /// `ProgressChartsView.balanceAnalysis`.
    static let pushPull = Explainer(
        id: "train.pushpull",
        title: "Push/pull ratio",
        what: "Whether you train pushing and pulling about equally.",
        how: "Your 30-day volume for chest, shoulders and triceps divided by your volume for back and biceps. From 0.8 to 1.3 counts as balanced.",
        action: "If pushing is far ahead, add rows or pull-downs, and the other way round.",
        systemImage: "arrow.left.arrow.right"
    )

    /// `TrainingOutcomeEvaluator.qualityScore`.
    static let weekScore = Explainer(
        id: "train.weekscore",
        title: "Last week's score",
        what: "A score for last week of training: did your lifts progress, and did you show up.",
        how: "60% is progress (lifts whose estimated 1RM went up) and 40% is sessions done out of planned, lowered when you had days of all-out effort or sloppy form.",
        action: "Read the line under it to see what held the score back, such as missed sessions or lifts that did not go up.",
        systemImage: "checkmark.seal"
    )

    /// `TrainerProgramHistoryStats.stats`.
    static let sessionsDone = Explainer(
        id: "train.program.done",
        title: "Sessions done",
        what: "How many of your trainer's sessions you have done so far.",
        how: "Sessions done over sessions scheduled since the program started. A session counts when it is finished or at least one working set was ticked. Days Tempo changed, such as a pause or a match day, are left out.",
        action: "Do the next session, or send your trainer a report so they know what was missed.",
        systemImage: "checklist"
    )

    /// The deload banner (`deloadStyle`).
    static let deload = Explainer(
        id: "train.deload",
        title: "Deload week",
        what: "A planned easy week that lets your body catch up so you come back stronger.",
        how: "Tempo plans one every 5 weeks by default, or earlier when your fatigue score runs very high. The banner says whether this one means lighter weights, fewer sets or rest.",
        action: "Follow the lighter plan even if you feel good. The gains show up after the easy week.",
        systemImage: "arrow.down.circle"
    )

    // MARK: - On the set

    /// The "RAMP-UP" tag on a warm-up set.
    static let rampUp = Explainer(
        id: "train.ramp",
        title: "Ramp-up set",
        what: "A lighter warm-up set before your working sets.",
        how: "Tempo sets it below your working weight and leaves it out of sets done, volume and records.",
        action: "Do it at an easy pace to warm up, or tap Skip Ramp if you are already warm.",
        systemImage: "flame"
    )

    /// `TrainingViewModel.propagateCalibration`.
    static let calibration = Explainer(
        id: "train.calibration",
        title: "Calibration set",
        what: "A set where you pick the weight, so Tempo can find the right loads for the rest of the exercise.",
        how: "Tempo turns your reps into an estimated 1RM, weight × (1 + reps ÷ 30), and works out the weight of each remaining set from it.",
        action: "Pick a weight you could do the number of extra reps shown with, and log it honestly.",
        systemImage: "ruler"
    )

    /// A drop step (`PlannedSet.dropStepIndex`).
    static let dropSet = Explainer(
        id: "train.drop",
        title: "Drop set",
        what: "An extra set right after your last one, at a lower weight, with no rest, taken to failure.",
        how: "Drop sets count in your volume but never in estimated 1RM or records.",
        action: "Lower the weight enough to keep going, and tap Remove Drop if you added one by mistake.",
        systemImage: "arrow.down.circle"
    )

    // MARK: - Running

    /// `HeartRateZoneCalculator.zone` and `maxHeartRate`.
    static let heartRateZone = Explainer(
        id: "train.hrzone",
        title: "Heart rate zone",
        what: "Which of five effort bands your heart rate is in, from Z1 (very easy) to Z5 (all out).",
        how: "Each zone is a share of your maximum heart rate: under 60%, 60 to 70, 70 to 80, 80 to 90 and 90 or more. Your maximum is the one you entered, or 220 minus your age, or 190 if Tempo does not know your age.",
        action: "Keep easy runs in Z1 to Z2 and save Z4 and Z5 for the hard intervals.",
        systemImage: "heart"
    )

    /// Every explainer, for the tests.
    static let all: [Explainer] = [
        rir, rpe, bestE1RM, currentE1RM, target, personalRecord, volume, volume30, setsDone, estimatedTime,
        recoveryColour, trainingLoad, strain, heatVolume, heatSets, heatScale, pushPull, weekScore, sessionsDone,
        deload, rampUp, calibration, dropSet, heartRateZone,
    ]
}
