//
// ExerciseDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ExerciseDetailView

// Per MODULE_TRAINING.md Section 10 — Exercise detail with stats and progress.
// Per WIREFRAMES.md Screen 20 — Name, info pills, stats card, progress chart, instructions.

struct ExerciseDetailView: View {
    @Bindable
    var exercise: Exercise

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query
    private var allSettings: [UserSettings]
    @State
    private var chartRange: ChartRange = .thirtyDays
    /// The chart's scrub position (nil = nothing held).
    @State
    private var scrubDate: Date?
    /// §10.6 — delete confirmation for custom exercises.
    @State
    private var showDeleteConfirm = false
    /// §10.6/§1 — blocks the delete when the exercise is in today's
    /// unfinished plan (deleting it mid-plan would nullify a slot the active
    /// session is about to read).
    @State
    private var showActivePlanBlock = false

    private var settings: UserSettings? {
        allSettings.first
    }

    private var weightUnit: WeightUnit {
        settings?.weightUnit ?? .kg
    }

    enum ChartRange: String, CaseIterable {
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "ALL"

        var days: Int? {
            switch self {
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .all: nil
            }
        }
    }

    var body: some View {
        TrainPlanPage {
            // Demo area placeholder
            // Per WIREFRAMES.md Screen 20 — 200pt demo area
            demoArea

            // Exercise name
            Text(exercise.name)
                .accessibilityLabel(exercise.name.uppercased())
                .font(Tide.title)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Info pills
            // Per WIREFRAMES.md Screen 20 — muscle group, equipment, compound/isolation
            infoPills

            // Secondary muscles
            if !exercise.secondaryMuscles.isEmpty {
                Text("Secondary: \(exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }

            // Stats card
            // Per WIREFRAMES.md Screen 20 — YOUR STATS section
            statsCard

            // Progress chart
            // Per WIREFRAMES.md Screen 20 — e1RM line chart with time range picker
            progressChart

            // Instructions
            if let instructions = exercise.instructions, !instructions.isEmpty {
                instructionsSection(instructions)
            }

            // Coaching cues
            if !exercise.cues.isEmpty {
                cuesSection
            }

            // Rest timer customization
            restTimerSection
        }
        .tidePage()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        // §10.6 — custom exercises can be deleted; seeded library ones can't.
        .toolbar {
            if exercise.isCustom {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        if isInTodaysActivePlan {
                            showActivePlanBlock = true
                        } else {
                            showDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this custom exercise?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteCustomExercise()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "It disappears from the library and pickers. Past sessions that used it keep their logged sets, but lose the exercise name."
            )
        }
        .alert("Can't Delete Yet", isPresented: $showActivePlanBlock) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This exercise is in today's workout. Finish or swap it out of today's plan first, then delete it.")
        }
    }

    /// §1 — an Exercise deletion nullifies (not cascades onto) today's
    /// PlannedExercise slots, so deleting an exercise mid-plan would leave the
    /// live session pointing at a nil exercise. Refuse until today's plan is
    /// no longer active.
    private var isInTodaysActivePlan: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (exercise.plannedExercises ?? []).contains { planned in
            guard let plan = planned.workoutPlan else {
                return false
            }
            return cal.isDate(plan.date, inSameDayAs: today) && !plan.status.isTerminal
        }
    }

    private func deleteCustomExercise() {
        guard exercise.isCustom, !isInTodaysActivePlan else {
            return
        }
        modelContext.delete(exercise)
        modelContext.saveOrAlert("exercise")
        HapticManager.notification(.success)
        dismiss()
    }

    // MARK: - Demo Area

    // Per WIREFRAMES.md Screen 20 — 200pt height, surface bg

    private var demoArea: some View {
        ZStack {
            ExerciseImageView(exercise: exercise, style: .hero)
        }
        .frame(maxWidth: .infinity)
        .frame(height: TideTrain.demo)
        .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
    }

    // MARK: - Info Pills

    // Per WIREFRAMES.md Screen 20 — 24pt height pill chips

    private var infoPills: some View {
        VStack(spacing: Tide.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    pillRow
                }
                VStack(spacing: Tide.s2) {
                    pillRow
                }
            }
            beginnerExplainer
        }
    }

    @ViewBuilder
    private var pillRow: some View {
        TrainTag(text: exercise.muscleGroup.displayName, color: Color.accentColor)
        TrainTag(text: equipmentLabel)
        TrainTag(text: exercise.isCompound ? "Compound" : "Isolation")
    }

    /// Plain-language one-liner for whichever pills are most likely to confuse
    /// a beginner. UserSettings.experienceLevel isn't persisted today, so this
    /// is shown unconditionally — the explainer is small and dismissible by
    /// just ignoring it, and the cost to an experienced user is one secondary
    /// line vs. a beginner being stuck.
    @ViewBuilder
    private var beginnerExplainer: some View {
        let equipmentTip = equipmentExplainer
        let movementTip = exercise.isCompound
            ? "Compound — works multiple muscle groups at once. Heaviest, most efficient lifts."
            : "Isolation — targets one muscle. Lighter, used for shaping or weak points."
        VStack(alignment: .leading, spacing: Tide.hair) {
            if let equipmentTip {
                Text(equipmentTip)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Text(movementTip)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var equipmentExplainer: String? {
        switch exercise.equipment {
        case .barbell: "Barbell — long metal bar you load with plates on each end. Used for the heaviest lifts."
        case .dumbbell: "Dumbbell — short handheld weights, one per hand. Better for balance and one-arm work."
        case .cable: "Cable — adjustable pulley with a handle. Constant tension through the whole movement."
        case .machine: "Machine — fixed path with selectable weight stack. Easier to learn; safer for going heavy alone."
        case .bodyweight: "Bodyweight — no equipment, you ARE the load. Scales by adjusting leverage or reps."
        case .kettlebell: "Kettlebell — ball-shaped weight with a handle. Great for swings and ballistic moves."
        case .resistanceBand: "Band — elastic; tension increases as you stretch it. Light option for assistance or warm-ups."
        case .smithMachine: "Smith Machine — barbell locked on vertical rails. Stable, but limits natural movement path."
        case .ezBar: "EZ Bar — short curved barbell. Easier on the wrists for curls and skullcrushers."
        case .trapBar: "Trap Bar — hexagonal bar you stand inside. Easier-on-the-back deadlift variant."
        case .pullUpBar: "Pull-Up Bar — overhead bar. Hang and pull yourself up; the canonical upper-body bodyweight test."
        case .bench: "Bench — flat or adjustable padded bench. Lets you press, row, or step up from a stable base."
        case .none: nil
        }
    }

    // MARK: - Stats Card

    // Per WIREFRAMES.md Screen 20 — Current 1RM, Best Set, Volume (30d), Sessions (30d)

    private var statsCard: some View {
        let history = sortedHistory
        let thirtyDayHistory = history.filter {
            $0.date > Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        }
        let current1RM = exercise.currentEstimated1RM
        let bestSet = ExerciseBestSet.pick(from: history, bodyweight: StrengthStandards.isBodyweightLoaded(exercise.equipment))
        let volume30d = thirtyDayHistory.reduce(0.0) { $0 + $1.totalVolume }
        let sessions30d = thirtyDayHistory.count

        return TrainPlanCard(label: "Your stats") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: TideTrain.statColumn * 1.4), spacing: Tide.s3, alignment: .topLeading)],
                alignment: .leading,
                spacing: Tide.s4
            ) {
                TrainStat(
                    value: current1RM.map { WeightFormat.text(kg: $0, unit: weightUnit) } ?? "—",
                    label: "Current 1RM",
                    size: Tide.numeralS
                )
                TrainStat(
                    value: bestSetText(bestSet),
                    label: "Best Set",
                    size: Tide.numeralS
                )
                TrainStat(
                    value: volume30d > 0 ? formatVolume(volume30d) : "—",
                    label: "Volume (30d)",
                    size: Tide.numeralS
                )
                TrainStat(
                    value: sessions30d > 0 ? "\(sessions30d)" : "—",
                    label: "Sessions (30d)",
                    size: Tide.numeralS
                )
            }

            // PR display
            if let allTimePR = exercise.allTimePR {
                HStack(spacing: Tide.s2) {
                    Image(systemName: "trophy.fill")
                        .font(Tide.caption)
                        .foregroundStyle(TideTrain.record) // prGold
                        .accessibilityHidden(true)

                    Text(
                        "All-Time 1RM PR: \(WeightFormat.text(kg: allTimePR, unit: weightUnit))"
                    )
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Progress Chart

    // Per WIREFRAMES.md Screen 20 — e1RM line chart, 200pt, with 30D/90D/ALL picker

    private var progressChart: some View {
        // One point per day; bodyweight sessions carry no e1RM — never plot a 0.
        let chartDays = ProgressLabMath.dailyBestE1RM(
            filteredHistory(for: chartRange).map { ($0.date, $0.estimated1RM) }
        )
        let points = chartDays.map {
            TrainPlanPoint(date: $0.date, value: WeightUnit.kg.convert($0.e1RM, to: weightUnit))
        }
        let shown = scrubDate.flatMap { target in
            points.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        } ?? points.last

        return TrainPlanCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Tide.s3) {
                    Text("Progress · e1RM").tideLabel()
                    Spacer(minLength: Tide.s2)
                    rangeTabs
                        .frame(maxWidth: TideTrain.tabsCompact)
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Progress · e1RM").tideLabel()
                    rangeTabs
                }
            }

            if let shown {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber(
                        "\(Int(shown.value.rounded()))",
                        unit: weightUnit.abbreviation,
                        size: Tide.numeralS,
                        relativeTo: .title2,
                        color: Color.accentColor
                    )
                    Spacer(minLength: Tide.s2)
                    Text(shown.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                TrainPlanTrendChart(points: points, scrub: $scrubDate)
            } else {
                TrainEmptyCard(systemImage: "chart.line.uptrend.xyaxis", title: "No history yet")
            }
        }
    }

    private var rangeTabs: some View {
        TrainPlanTabs(
            items: ChartRange.allCases.map { (tag: $0, label: $0.rawValue) },
            selection: $chartRange
        )
        .onChange(of: chartRange) {
            scrubDate = nil
        }
    }

    // MARK: - Instructions

    // Per WIREFRAMES.md Screen 20 — Numbered step-by-step instructions

    private func instructionsSection(_ instructions: String) -> some View {
        TrainPlanCard(label: "Instructions") {
            Text(instructions)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Coaching Cues

    private var cuesSection: some View {
        TrainPlanCard(label: "Coaching cues") {
            ForEach(Array(exercise.cues.enumerated()), id: \.offset) { index, cue in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                    Text("\(index + 1)")
                        .font(TideTrain.figure(.caption, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: Tide.s4, alignment: .trailing)
                        .accessibilityHidden(true)

                    Text(cue)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Rest Timer Customization

    private var restTimerSection: some View {
        TrainPlanCard(label: "Rest timer") {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text("Preferred rest between sets")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)

                Spacer(minLength: Tide.s2)

                if let rest = exercise.preferredRestSeconds {
                    Text(formatRestDuration(rest))
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .monospacedDigit()
                }
            }

            Stepper(
                value: Binding(
                    get: { exercise.preferredRestSeconds ?? 90 },
                    set: { newValue in
                        exercise.preferredRestSeconds = newValue
                        modelContext.saveOrAlert("exercise")
                    }
                ),
                in: 30 ... 300,
                step: 15
            ) {
                Text(formatRestDuration(exercise.preferredRestSeconds ?? 90))
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .monospacedDigit()
            }

            // Reset to default
            if exercise.preferredRestSeconds != nil {
                Button {
                    exercise.preferredRestSeconds = nil
                    modelContext.saveOrAlert("exercise")
                } label: {
                    Text("Reset to Default")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
            }
        }
    }

    private func formatRestDuration(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        if min > 0, sec > 0 {
            return "\(min)m \(sec)s"
        } else if min > 0 {
            return "\(min)m"
        }
        return "\(sec)s"
    }

    // MARK: - Helpers

    private var sortedHistory: [ExerciseHistory] {
        (exercise.history ?? []).sorted { $0.date > $1.date }
    }

    private func filteredHistory(for range: ChartRange) -> [ExerciseHistory] {
        let history = (exercise.history ?? []).sorted { $0.date < $1.date }
        guard let days = range.days else {
            return history
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return history.filter { $0.date > cutoff }
    }

    private func bestSetText(_ best: ExerciseBestSet?) -> String {
        guard let best else {
            return "—"
        }
        return "\(WeightFormat.setLoad(kg: best.weightKg, addedKg: best.addedLoadKg, bodyweight: best.isBodyweight, unit: weightUnit)) × \(best.reps)"
    }

    private func formatVolume(_ volume: Double) -> String {
        WeightFormat.volumeText(kg: volume, unit: weightUnit)
    }

    private var equipmentLabel: String {
        switch exercise.equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Band"
        case .smithMachine: "Smith"
        case .ezBar: "EZ Bar"
        case .trapBar: "Trap Bar"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .none: "None"
        }
    }
}

// MARK: - ExerciseDemoImage

/// Reference photo for an exercise, loaded remotely from the bundled free-exercise-db
/// map. `demoAsset` is a relative path (e.g. "Barbell_Bench_Press_-_Medium_Grip/0.jpg")
/// served via jsDelivr and cached by URLCache. Falls back to a muscle-group SF Symbol
/// when the exercise has no mapped image or the fetch fails. Shared by ExerciseDetailView
/// (demo area) and ActiveWorkoutView (session header).
struct ExerciseDemoImage: View {
    let demoAsset: String?
    let muscleGroup: MuscleGroup
    var symbolSize: CGFloat = 48

    /// jsDelivr CDN — rate-limit-friendly for repeated in-app fetches vs raw.githubusercontent.
    private static let cdnBase = "https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/"

    private var url: URL? {
        guard let demoAsset, !demoAsset.isEmpty else {
            return nil
        }
        return URL(string: Self.cdnBase + demoAsset)
    }

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty:
                    ProgressView()
                        .tint(Tide.text3)
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: fallbackSymbol)
            .trainGlyph(symbolSize, relativeTo: .title)
            .foregroundStyle(Tide.text3)
    }

    private var fallbackSymbol: String {
        switch muscleGroup {
        case .core: "figure.core.training"
        case .fullBody: "figure.strengthtraining.functional"
        case .cardio: "figure.run"
        default: "figure.strengthtraining.traditional"
        }
    }
}
