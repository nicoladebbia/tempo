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
        // All math in the DISPLAY unit with the regional bar (a US bar is
        // 45 lbs, not the 44.1 a 20 kg bar converts to) and regional plate
        // denominations — "22.5 lbs/side" a lifter can actually build.
        let bar = WeightConverter.barWeight(for: equipment, unit: weightUnit)
        guard inputWeight >= bar else {
            return nil
        }
        let perSide = (inputWeight - bar) / 2
        let unit = weightUnit.abbreviation
        let perSideStr = String(format: weightUnit == .kg ? "%.1f" : "%.1f", perSide)
        let barStr = String(format: "%.0f", bar)

        // §5 plate calculator — the previously-orphaned showPlateCalculator
        // setting gates the actual PLATE breakdown ("20 + 2.5 per side");
        // the plain per-side weight stays either way.
        if allSettings.first?.showPlateCalculator ?? true, perSide > 0 {
            let plates = PlateMath.breakdown(perSide: perSide, plates: PlateMath.plates(for: weightUnit))
            if !plates.isEmpty {
                let approx = PlateMath.isExact(plates: plates, perSide: perSide) ? "" : "≈"
                let plateStr = approx + PlateMath.label(values: plates)
                if bar > 0 {
                    return "\(plateStr) per side + \(barStr) \(unit) bar"
                }
                return "\(plateStr) per side"
            }
        }

        if bar > 0 {
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

                case .interruptedCall:
                    interruptedCallOverlay

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

    // §11.7 rework — a single-screen cockpit: compact header, one-line alert
    // chips, LAST/TARGET/BEST context from real history, steppers, dots, and
    // a Skip+Finish action row. No ScrollView: everything fits one page.
    private var setActiveContent: some View {
        VStack(spacing: TempoSpacing.md) {
            exerciseHeader

            alertChips

            contextStrip

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
                    // §11.12 — the effort target that makes the weight make
                    // sense: the load is computed FOR this rep count at this
                    // proximity to failure.
                    if !currentSetIsWarmup, let rir = viewModel.currentSet?.targetRIR {
                        Text(rir == 0
                            ? "All out — nothing left in the tank"
                            : "Effort: leave \(rir) rep\(rir == 1 ? "" : "s") in the tank")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoAmber)
                    }
                }

            // RPE is collected end-of-set in the inline feedback panel
            // (under the rest timer), not here — one prompt, not two.

            Spacer(minLength: 0)

            setProgress

            actionRow
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.md)
    }

    /// One-line condition chips (ramp / pain / superset) — the old full-width
    /// banners each ate a screen row; these say the same thing in 28pt.
    @ViewBuilder
    private var alertChips: some View {
        let exerciseID: UUID? = viewModel.currentExercise?.exercise?.id
        let painFlagged = exerciseID.map { viewModel.painFlaggedExercises.contains($0) } ?? false
        if currentSetIsWarmup || painFlagged || viewModel.currentSupersetPartnerName != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TempoSpacing.xs) {
                    if currentSetIsWarmup {
                        chip("flame", "RAMP-UP — doesn't count", Color.tempoSignal)
                    }
                    if painFlagged {
                        chip("exclamationmark.triangle.fill", "Pain flagged — weight held, go easy", Color.tempoWarning)
                    }
                    if let partner = viewModel.currentSupersetPartnerName {
                        chip("arrow.triangle.2.circlepath", "Superset: \(partner)", Color.tempoSignal)
                    }
                }
            }
        }
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: TempoSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.tempoCaption2)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Context Strip (§11.7 — the "more data")

    /// Display-unit conversion for stored-kg history values.
    private func displayWeight(_ kg: Double) -> String {
        String(format: "%.0f", WeightUnit.kg.convert(kg, to: weightUnit))
    }

    /// Best working set of the most recent PRIOR session of this lift.
    private var lastSessionStat: String? {
        guard let rows = viewModel.currentExercise?.exercise?.history else {
            return nil
        }
        let cal = Calendar.current
        let prior = rows
            .filter { !cal.isDateInToday($0.date) }
            .max { $0.date < $1.date }
        guard let prior, let w = prior.bestSetWeight, let r = prior.bestSetReps else {
            return nil
        }
        return "\(displayWeight(w)) × \(r)"
    }

    /// Today's prescription for the CURRENT set.
    private var targetStat: String? {
        guard let set = viewModel.currentSet, let w = set.targetWeight else {
            return nil
        }
        return "\(displayWeight(w)) × \(set.targetReps)"
    }

    /// All-time best estimated 1RM for this lift.
    private var bestE1RMStat: String? {
        let best = (viewModel.currentExercise?.exercise?.history ?? [])
            .compactMap(\.estimated1RM)
            .max()
        guard let best, best > 0 else {
            return nil
        }
        return displayWeight(best)
    }

    /// LAST / TARGET / BEST — the numbers a lifter actually wants mid-set:
    /// what you did last time, what today asks, what your ceiling is.
    private var contextStrip: some View {
        HStack(spacing: TempoSpacing.sm) {
            statCell("LAST", lastSessionStat ?? "—")
            statCell("TARGET", targetStat ?? "—", highlight: true)
            statCell("BEST e1RM", bestE1RMStat ?? "—")
        }
    }

    private func statCell(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(value)
                .font(.tempoSubheadline)
                .fontWeight(.semibold)
                .foregroundStyle(highlight ? Color.tempoAccent : Color.tempoTextPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    // MARK: - Action Row

    /// Skip + Finish side by side — skip always visible, never the hero.
    private var actionRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            // §2.16 — skip without logging. On a warmup set one tap drops the
            // whole remaining ramp; on a working set it skips just this set.
            Button {
                if currentSetIsWarmup {
                    viewModel.skipRemainingWarmups(modelContext: modelContext)
                } else {
                    viewModel.skipCurrentSet(modelContext: modelContext)
                }
            } label: {
                Text(currentSetIsWarmup ? "Skip Ramp" : "Skip")
                    .font(.tempoSubheadline)
                    .frame(width: 104)
                    .frame(height: 56)
                    .background(Color.tempoBgSecondary)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }

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
                Text(currentSetIsWarmup ? "Finish Warm-Up" : "Finish Set")
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.tempoSignal)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
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

    // §11.7 — compact header row: 64pt demo thumb, name + muscle/set line,
    // session ring. The old 150pt card + centered titles ate a third of the
    // screen; this says the same in one row.
    private var exerciseHeader: some View {
        HStack(spacing: TempoSpacing.md) {
            if let exercise = viewModel.currentExercise?.exercise {
                ExerciseDemoImage(demoAsset: exercise.demoAsset, muscleGroup: exercise.muscleGroup, symbolSize: 24)
                    .frame(width: 64, height: 64)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name.uppercased())
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("\(exercise.muscleGroup.displayName) · \(viewModel.setCountText)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: TempoSpacing.sm)

                sessionRing
            }
        }
        // Slide-in on exercise change — .id remounts the header so the
        // asymmetric transition fires exactly once per movement.
        .id(viewModel.currentExerciseIndex)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(duration: 0.45), value: viewModel.currentExerciseIndex)
    }

    /// Compact session ring: today's completed working sets over planned.
    private var sessionRing: some View {
        let total = max(1, viewModel.totalSets)
        let fraction = Double(viewModel.completedSets) / Double(total)
        return ZStack {
            Circle()
                .stroke(Color.tempoTextTertiary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.tempoAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: fraction)
            Text("\(viewModel.completedSets)/\(viewModel.totalSets)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tempoTextPrimary)
                .contentTransition(.numericText())
        }
        .frame(width: 46, height: 46)
        .padding(6)
        .background(Color.tempoBgPrimary.opacity(0.85))
        .clipShape(Circle())
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
                        Group {
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
                        // §11.6 — the live dot breathes; completion springs.
                        .scaleEffect(idx == viewModel.currentSetIndex ? 1.35 : 1)
                        .animation(.spring(duration: 0.35), value: viewModel.currentSetIndex)
                        .animation(.spring(duration: 0.35), value: set.completed)
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

    // MARK: - Call Interruption Overlay

    /// STATE_MACHINES §1 — a live phone call parks the session here; it
    /// restores itself when the call ends (no buttons needed, but an escape
    /// hatch resumes manually if CallKit never reports the end).
    private var interruptedCallOverlay: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "phone.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoSignal)

            Text("ON A CALL")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Workout paused — it resumes by itself when you hang up.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.screenEdge)

            Button {
                viewModel.handleCallChange(callEnded: true)
            } label: {
                Text("Resume now")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

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

    /// Standard US plates per side, lbs, descending.
    static let standardPlatesLbs: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// Regional plate denominations for the display unit — the breakdown is
    /// computed directly in that unit, never converted.
    static func plates(for unit: WeightUnit) -> [Double] {
        unit == .kg ? standardPlatesKg : standardPlatesLbs
    }

    /// Plates (same unit as `perSide`, descending) whose sum best
    /// approximates `perSide` from below. An unreachable remainder < the
    /// smallest plate is dropped — the label marks approximation with "≈".
    static func breakdown(
        perSide: Double,
        plates: [Double] = PlateMath.standardPlatesKg
    ) -> [Double] {
        var remaining = perSide
        var result: [Double] = []
        for plate in plates.sorted(by: >) {
            while remaining >= plate - 0.001 {
                result.append(plate)
                remaining -= plate
            }
        }
        return result
    }

    /// Human label: "45 + 2.5" — values are already in the display unit.
    static func label(values: [Double]) -> String {
        values.map { v in
            v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2g", v)
        }
        .joined(separator: " + ")
    }

    /// Whether `plates` exactly builds `perSide` (within 10 g / 0.01 lb).
    static func isExact(plates: [Double], perSide: Double) -> Bool {
        abs(plates.reduce(0, +) - perSide) < 0.01
    }
}
