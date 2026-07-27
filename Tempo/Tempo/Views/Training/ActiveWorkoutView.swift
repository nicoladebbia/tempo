//
// ActiveWorkoutView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Active Workout View

// Per MODULE_TRAINING.md Section 3 — Exercise-by-exercise set logging.
// Per STATE_MACHINES.md Section 1 — Workout session states.

struct ActiveWorkoutView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var inputWeight: Double = 0
    @State
    private var inputReps: Double = 8
    /// Signed added load (display unit) for bodyweight-loaded lifts: positive =
    /// weight belt/vest, negative = assistance (band/machine). Only used when the
    /// current exercise is bodyweight-loaded; effective load = bodyweight ± this.
    @State
    private var inputAddedLoad: Double = 0
    @State
    private var showFinishConfirmation = false
    @Query
    private var allSettings: [UserSettings]
    @Query
    private var profiles: [UserProfile]

    /// User weight-unit preference. The stepper edits a *display* value in
    /// this unit; storage stays kg (converted at the log boundary) so
    /// volume/PR/history math is never corrupted.
    private var weightUnit: WeightUnit {
        allSettings.first?.weightUnit ?? .kg
    }

    /// Stepper increment in the display unit: 2.5 kg vs a realistic 5 lb
    /// plate jump.
    private var weightStep: Double {
        weightUnit == .kg ? 2.5 : 5
    }

    /// Upper bound in the display unit (≈ 500 kg).
    private var weightRangeMax: Double {
        weightUnit == .kg ? 500 : 1100
    }

    /// Per-side plate hint for bar-loaded lifts, e.g. "20 kg/side + 20 kg bar".
    /// `inputWeight` is in the display unit; bar math is done in kg then shown
    /// in the user's unit. Nil for dumbbells/cables/machines/bodyweight.
    private var perSideHint: String? {
        guard let equipment = viewModel.currentExercise?.exercise?.equipment,
              equipment.isBarLoaded
        else {
            return nil
        }
        let totalKg = weightUnit.convert(inputWeight, to: .kg)
        let bar = equipment.barWeightKg
        guard totalKg >= bar else {
            return nil
        }
        let perSideKg = (totalKg - bar) / 2
        let perSide = WeightUnit.kg.convert(perSideKg, to: weightUnit)
        let unit = weightUnit.abbreviation
        let perSideStr = String(format: weightUnit == .kg ? "%.1f" : "%.0f", perSide)

        // §5 plate calculator — the previously-orphaned showPlateCalculator
        // setting gates the actual PLATE breakdown ("20 + 2.5 per side");
        // the plain per-side weight stays either way.
        if allSettings.first?.showPlateCalculator ?? true, perSideKg > 0 {
            let plates = PlateMath.breakdown(perSideKg: perSideKg)
            if !plates.isEmpty {
                let approx = PlateMath.isExact(plates: plates, perSideKg: perSideKg) ? "" : "≈"
                let plateStr = approx + PlateMath.label(plates: plates, in: weightUnit)
                if bar > 0 {
                    let barStr = String(format: "%.0f", WeightUnit.kg.convert(bar, to: weightUnit))
                    return "\(plateStr) per side + \(barStr) \(unit) bar"
                }
                return "\(plateStr) per side"
            }
        }

        if bar > 0 {
            let barStr = String(format: weightUnit == .kg ? "%.0f" : "%.0f",
                                WeightUnit.kg.convert(bar, to: weightUnit))
            return "\(perSideStr) \(unit)/side + \(barStr) \(unit) bar"
        }
        return "\(perSideStr) \(unit)/side"
    }

    /// Whether the current lift is bodyweight-loaded (pull-up/dip) — logged as a
    /// signed added load on top of bodyweight rather than a raw total weight.
    private var isBodyweightLift: Bool {
        guard let eq = viewModel.currentExercise?.exercise?.equipment else {
            return false
        }
        return StrengthStandards.isBodyweightLoaded(eq)
    }

    /// User bodyweight (kg) for effective-load math. 0 when unknown → the
    /// effective load degrades to just the added load.
    private var bodyweightKg: Double {
        profiles.first?.weightKg ?? 0
    }

    /// Effective logged load (kg) for a bodyweight lift = bodyweight ± added,
    /// never negative. `inputAddedLoad` is in the display unit.
    private var bodyweightEffectiveKg: Double {
        max(0, bodyweightKg + weightUnit.convert(inputAddedLoad, to: .kg))
    }

    /// Human hint under the added-load stepper: "= 77.7 kg effective · assisted".
    private var bodyweightEffectiveHint: String {
        let unit = weightUnit.abbreviation
        let effDisplay = WeightUnit.kg.convert(bodyweightEffectiveKg, to: weightUnit)
        let effStr = String(format: weightUnit == .kg ? "%.1f" : "%.0f", effDisplay)
        let tag: String = if inputAddedLoad > 0 {
            "weighted"
        } else if inputAddedLoad < 0 {
            "assisted"
        } else {
            "bodyweight"
        }
        return "= \(effStr) \(unit) effective · \(tag)"
    }

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Timer bar
                timerBar

                // Content based on state
                switch viewModel.sessionState {
                case .warmup:
                    warmupContent

                case .exercise(.setActive):
                    setActiveContent

                case .exercise(.resting):
                    RestTimerView(viewModel: viewModel)

                case let .exercise(.betweenExercises(_, toIndex)):
                    exerciseTransition(toIndex: toIndex)

                case .paused:
                    pausedOverlay

                case .crashedRecovery:
                    crashRecoveryContent

                default:
                    // Transient states (cooldown/summary/saved/discarded/idle):
                    // the cover is being dismissed — show the app background, not
                    // a blank "broken"-looking view, during the teardown frame.
                    Color.tempoBgPrimary
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFinishConfirmation = true
                } label: {
                    Text("Finish")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        // Centered alert (not a popover/action sheet) for the finish choice.
        .alert("Finish Workout?", isPresented: $showFinishConfirmation) {
            Button("Save what I did") {
                viewModel.finishWorkout()
            }
            Button("Discard workout", role: .destructive) {
                // Discard rolls back + resets; TrainingTabView observes
                // .discarded and dismisses the cover (don't dismiss here too,
                // which raced the reset and left a blank screen).
                viewModel.discardActiveWorkout(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save keeps the sets you've logged. Discard throws this session away — the day stays open to redo.")
        }
        .onAppear { loadCurrentSetInputs() }
        // NOTE: cover teardown on .discarded is owned SOLELY by TrainingTabView
        // (it owns showActiveWorkout). No child dismiss() here — two owners
        // racing was the earlier blank-flash bug. The router's neutral-background
        // default covers the single teardown frame.
        .onChange(of: viewModel.currentExerciseIndex) { _, _ in loadCurrentSetInputs() }
        .onChange(of: viewModel.currentSetIndex) { _, _ in loadCurrentSetInputs() }
        // Re-sync the wall-clock rest timer when returning from the background,
        // so a timer that elapsed (or ran down) while the app was backgrounded
        // reflects real time instead of freezing.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.syncRestTimer()
                viewModel.syncWarmupTimer()
            }
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        HStack {
            // Elapsed time
            Text(viewModel.formattedElapsedTime)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .monospacedDigit()

            Spacer()

            // Progress
            Text("\(viewModel.completedSets)/\(viewModel.totalSets) sets")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()

            // Volume
            Text(viewModel.formattedVolume)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
    }

    // MARK: - Set Active Content

    // Per MODULE_TRAINING.md Section 3 — Weight/reps inputs, DONE button

    private var setActiveContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Ramp-up banner — makes it unmistakable that this is a warm-up
                // set (not a working set), on EVERY exercise that has them
                // (e.g. Lat Pulldown), not just the first.
                if currentSetIsWarmup {
                    VStack(spacing: TempoSpacing.xxs) {
                        Text("RAMP-UP SET")
                            .font(.tempoCaption1)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoSignal)
                        Text("Warm up to your working weight — these don't count toward your sets.")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(TempoSpacing.sm)
                    .background(Color.tempoSignal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }

                // Tier 2.3 — pain caution: a recent note flagged this exercise.
                if let exID = viewModel.currentExercise?.exercise?.id,
                   viewModel.painFlaggedExercises.contains(exID) {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.tempoWarning)
                        Text("You noted pain here recently — weight held, go easy and stop if it hurts.")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TempoSpacing.sm)
                    .background(Color.tempoWarning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }

                // §6 superset banner — the pair alternates with no rest inside
                // it; the one rest comes after the second lift.
                if let partner = viewModel.currentSupersetPartnerName {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.tempoSignal)
                        Text("Superset with \(partner) — no rest between the pair.")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TempoSpacing.sm)
                    .background(Color.tempoSignal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }

                // Exercise info
                exerciseHeader

                // Set counter
                Text(viewModel.setCountText)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                if isBodyweightLift {
                    // Bodyweight-loaded lift (pull-up/dip): log a SIGNED added
                    // load — negative = assistance (band/machine), positive =
                    // weight belt/vest. Effective load = bodyweight ± this.
                    VStack(spacing: TempoSpacing.sm) {
                        Text("ADDED LOAD — − assisted / + weighted")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        NumberStepperView(
                            value: $inputAddedLoad,
                            range: -weightRangeMax ... weightRangeMax,
                            step: weightStep,
                            format: weightUnit == .kg ? "%+.1f" : "%+.0f",
                            unit: weightUnit.abbreviation
                        )
                        Text(bodyweightEffectiveHint)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                } else {
                    // Weight input — the logged number is TOTAL load including the
                    // bar. For bar-loaded lifts we show a per-side plate hint so
                    // there's no ambiguity about what to actually put on.
                    VStack(spacing: TempoSpacing.sm) {
                        Text("WEIGHT — total incl. bar")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        NumberStepperView(
                            value: $inputWeight,
                            range: 0 ... weightRangeMax,
                            step: weightStep,
                            format: weightUnit == .kg ? "%.1f" : "%.0f",
                            unit: weightUnit.abbreviation
                        )
                        if let hint = perSideHint {
                            Text(hint)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }

                // Reps input
                VStack(spacing: TempoSpacing.sm) {
                    Text("REPS")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    NumberStepperView(
                        value: $inputReps,
                        range: 1 ... 100,
                        step: 1,
                        format: "%.0f",
                        unit: "reps"
                    )
                }

                // RPE is collected end-of-set in the inline feedback panel
                // (under the rest timer), not here — one prompt, not two.

                // Set progress
                setProgress

                // Done button
                Button {
                    // Inputs are in the user's display unit; persist kg. For a
                    // bodyweight lift the logged weight is the EFFECTIVE load
                    // (bodyweight ± added) and we also record the signed added load.
                    if isBodyweightLift {
                        viewModel.logSet(
                            weight: bodyweightEffectiveKg,
                            reps: Int(inputReps),
                            addedLoadKg: weightUnit.convert(inputAddedLoad, to: .kg),
                            modelContext: modelContext
                        )
                    } else {
                        let weightKg = weightUnit.convert(inputWeight, to: .kg)
                        viewModel.logSet(
                            weight: weightKg,
                            reps: Int(inputReps),
                            modelContext: modelContext
                        )
                    }
                    HapticManager.notification(.success)
                } label: {
                    Text(currentSetIsWarmup ? "Finish Warm-Up Set" : "Finish Set")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
    }

    /// Whether the set currently being entered is a warm-up (ramp) set.
    private var currentSetIsWarmup: Bool {
        viewModel.currentSet?.isWarmup ?? false
    }

    // MARK: - Warmup Content

    // A guided, workout-SPECIFIC 10–15 min warm-up + mobility block shown before
    // the first working set. Content comes from WarmupRoutine (single source,
    // shared with the WeekPlanView mobility card). Includes elbow/biceps-tendon
    // prep on every day. After the routine, the first exercise's ramp-set
    // targets are previewed, then "Start Working Sets" enters the lift.
    // This block logs nothing — it is deliberately not part of WorkoutSessionState.

    private var warmupContent: some View {
        Group {
            if let move = viewModel.currentWarmupMove {
                warmupMovePlayer(move)
            } else {
                warmupRampPreview
            }
        }
    }

    /// Guided step-through: one move at a time, big and readable. Timed moves
    /// show a countdown that auto-advances; rep-based moves show a Next button.
    private func warmupMovePlayer(_ move: WarmupMove) -> some View {
        let routine = viewModel.warmupRoutine
        let total = routine?.moves.count ?? 0
        let isTimed = (move.durationSeconds ?? 0) > 0

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("WARM-UP · MOVE \(viewModel.warmupMoveIndex + 1) OF \(total)")
                        .font(.tempoCaption2)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text(move.name)
                        .font(.tempoTitle1)
                        .foregroundStyle(move.isTendonPrep ? Color.tempoSignal : Color.tempoTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(move.dose)
                        .font(.tempoHeadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                if isTimed {
                    Text(warmupCountdownLabel)
                        .font(.tempoDataLarge)
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Text(move.howTo)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let cue = move.cue {
                    HStack(alignment: .top, spacing: TempoSpacing.xs) {
                        Image(systemName: "lightbulb.fill")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoSignal)
                        Text(cue)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    viewModel.skipWarmupMove()
                    HapticManager.notification(.success)
                } label: {
                    Text(isTimed ? "Skip →" : "Done — Next →")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Button {
                    viewModel.advancePastWarmup()
                    HapticManager.selection()
                } label: {
                    Text("Skip whole warm-up")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.xl)
        }
    }

    private var warmupCountdownLabel: String {
        let s = Int(viewModel.warmupMoveRemaining.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// After the routine: preview the first exercise's ramp sets and start.
    private var warmupRampPreview: some View {
        let firstExercise = viewModel.todayPlan?.orderedExercises.first
        let warmupSets = (firstExercise?.orderedSets ?? []).filter(\.isWarmup)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("WARM-UP DONE")
                        .font(.tempoCaption1)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Ramp up: \(firstExercise?.exercise?.name ?? "")")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                .padding(.top, TempoSpacing.lg)
                .padding(.horizontal, TempoSpacing.screenEdge)

                if !warmupSets.isEmpty {
                    VStack(spacing: TempoSpacing.sm) {
                        ForEach(Array(warmupSets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Ramp set \(index + 1)")
                                    .font(.tempoHeadline)
                                    .foregroundStyle(Color.tempoTextSecondary)
                                Spacer()
                                Text(warmupTargetLabel(set))
                                    .font(.tempoHeadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.tempoTextPrimary)
                            }
                            .padding(TempoSpacing.cardPadding)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                        }
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                } else {
                    Text("No ramp sets for this exercise — go straight to your working sets.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.horizontal, TempoSpacing.screenEdge)
                }

                Button {
                    viewModel.advancePastWarmup()
                    HapticManager.notification(.success)
                } label: {
                    Text("Start Working Sets")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
            .padding(.vertical, TempoSpacing.lg)
        }
    }

    private func warmupTargetLabel(_ set: PlannedSet) -> String {
        if let w = set.targetWeight, w > 0 {
            let display = WeightUnit.kg.convert(w, to: weightUnit)
            return "\(Int(display)) \(weightUnit.abbreviation) × \(set.targetReps)"
        }
        return "Bodyweight × \(set.targetReps)"
    }

    // MARK: - Exercise Header

    private var exerciseHeader: some View {
        VStack(spacing: TempoSpacing.sm) {
            if let exercise = viewModel.currentExercise?.exercise {
                ExerciseDemoImage(demoAsset: exercise.demoAsset, muscleGroup: exercise.muscleGroup, symbolSize: 40)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                Text(exercise.name.uppercased())
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)

                Text(exercise.muscleGroup.displayName)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Set Progress

    private var setProgress: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                if let exercise = viewModel.currentExercise {
                    // Iterate the elements by stable id — never index into
                    // orderedSets by position. The +/- buttons mutate this
                    // array; a ForEach over `.indices` keeps a stale range
                    // and crashes (Index out of range) on the next render.
                    ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { idx, set in
                        if set.isWarmup {
                            // Warmup sets shown as smaller, outlined dots
                            Circle()
                                .stroke(setDotColor(set: set, index: idx), lineWidth: 1.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Circle()
                                .fill(setDotColor(set: set, index: idx))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            // +/- set buttons
            HStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.removeLastUncompletedSet(
                        from: viewModel.currentExerciseIndex,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .disabled((viewModel.currentExercise?.orderedSets.count ?? 0) <= 1)

                Text("\(viewModel.workingSetCount) sets")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)

                Button {
                    viewModel.addSet(
                        to: viewModel.currentExerciseIndex,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
    }

    private func setDotColor(set: PlannedSet, index: Int) -> Color {
        if set.completed {
            Color.tempoRecoveryGreen
        } else if index == viewModel.currentSetIndex {
            Color.tempoSignal
        } else {
            Color.tempoTextTertiary.opacity(0.3)
        }
    }

    // MARK: - Exercise Transition

    private func exerciseTransition(toIndex: Int) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()

            Text("NEXT EXERCISE")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            if let plan = viewModel.todayPlan {
                let exercises = plan.orderedExercises
                if toIndex < exercises.count, let name = exercises[toIndex].exercise?.name {
                    Text(name.uppercased())
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }

            ProgressView()

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "pause.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("PAUSED")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(viewModel.formattedElapsedTime)
                .font(.tempoDataLarge)
                .foregroundStyle(Color.tempoTextSecondary)
                .monospacedDigit()

            VStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.resume()
                } label: {
                    Text("RESUME")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Button {
                    showFinishConfirmation = true
                } label: {
                    Text("End Workout")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
    }

    // MARK: - Crash Recovery Content

    private var crashRecoveryContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoRecoveryYellow)

            Text("Resume Your Workout?")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("It looks like a workout was in progress.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.resumeFromCrash()
                } label: {
                    Text("RESUME WORKOUT")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Button {
                    viewModel.discardCrashedWorkout(modelContext: modelContext)
                    dismiss()
                } label: {
                    Text("Discard")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func loadCurrentSetInputs() {
        // Bodyweight-loaded lift: seed the SIGNED added-load stepper from the
        // set's planned suggestion (bodyweight ± this = effective target) rather
        // than a total weight.
        if isBodyweightLift {
            let addedKg = viewModel.currentSet?.addedLoadKg ?? 0
            let display = WeightUnit.kg.convert(addedKg, to: weightUnit)
            inputAddedLoad = (display / weightStep).rounded() * weightStep
            if let targetReps = viewModel.currentSet?.targetReps {
                inputReps = Double(targetReps)
            }
            return
        }

        // Warm-up (ramp) sets pre-fill their OWN target (the 50%/75% ramp
        // weight) — NOT the sticky/previous weight, which would carry the
        // working weight onto the ramps and make them identical. Working sets
        // use sticky (carry the weight you actually lifted forward).
        // stickyWeight/target is kg-stored; convert to the display unit and snap
        // to the stepper grid so the first +/- tap lands on a clean increment.
        let sourceKg: Double? = if viewModel.currentSet?.isWarmup == true {
            viewModel.currentSet?.targetWeight
        } else {
            viewModel.stickyWeight
        }
        if let kg = sourceKg {
            let display = WeightUnit.kg.convert(kg, to: weightUnit)
            inputWeight = (display / weightStep).rounded() * weightStep
        }
        if let targetReps = viewModel.currentSet?.targetReps {
            inputReps = Double(targetReps)
        }
    }
}

// MARK: - PlateMath (§5 — pure, unit-tested)

/// Greedy per-side plate breakdown over a standard kg plate set. Pure and
/// Date-free so it unit-tests cleanly. Greedy is exact for this plate set
/// (each denomination ≥ the sum of all smaller ones), so "largest first" is
/// also "fewest plates".
enum PlateMath {
    /// Standard plates available per side, kg, descending.
    static let standardPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Plates (kg, descending) whose sum best approximates `perSideKg` from
    /// below. An unreachable remainder < the smallest plate is dropped —
    /// the label marks approximation with "≈".
    static func breakdown(
        perSideKg: Double,
        plates: [Double] = PlateMath.standardPlatesKg
    ) -> [Double] {
        var remaining = perSideKg
        var result: [Double] = []
        for plate in plates.sorted(by: >) {
            while remaining >= plate - 0.001 {
                result.append(plate)
                remaining -= plate
            }
        }
        return result
    }

    /// Human label: "20 + 2.5" (kg) or the lb-converted equivalents, with a
    /// leading "≈" when the plates don't sum to the exact target.
    static func label(plates: [Double], in unit: WeightUnit) -> String {
        guard !plates.isEmpty else { return "" }
        let parts = plates.map { plateKg -> String in
            let v = WeightUnit.kg.convert(plateKg, to: unit)
            return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2g", v)
        }
        return parts.joined(separator: " + ")
    }

    /// Whether `plates` exactly builds `perSideKg` (within 10 g).
    static func isExact(plates: [Double], perSideKg: Double) -> Bool {
        abs(plates.reduce(0, +) - perSideKg) < 0.01
    }
}
