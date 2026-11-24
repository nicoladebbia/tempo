//
// ActiveWorkoutView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ActiveWorkoutView

// Per MODULE_TRAINING.md Section 3 — Exercise-by-exercise set logging.
// Per STATE_MACHINES.md Section 1 — Workout session states.

struct ActiveWorkoutView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var inputWeight: Double = 0
    /// Fix #9 — not `private` below: read from ActiveWorkoutView+PerSide.swift
    /// (split out to stay under the file_length cap). `logRepsSeparately`/
    /// `inputRepsRight` back an optional L/R split log; never sticky (reset
    /// in `loadCurrentSetInputs`).
    @State
    var inputReps: Double = 8
    @State
    var logRepsSeparately = false
    @State
    var inputRepsRight: Double = 8
    /// Signed added load (display unit) for bodyweight-loaded lifts: positive =
    /// weight belt/vest, negative = assistance (band/machine). Only used when the
    /// current exercise is bodyweight-loaded; effective load = bodyweight ± this.
    @State
    private var inputAddedLoad: Double = 0
    @State
    private var showFinishConfirmation = false
    /// Pending "are you sure?" for an implausible set (0 kg / way past best).
    @State
    private var setPlausibilityWarning: String?
    /// §11.13 — "How to" sheet: full exercise detail from the set screen.
    @State
    private var showHowTo = false
    /// "This hurts" flow — see PainReportSheet.swift.
    @State
    private var showPainReport = false
    /// §4.2-4.4 — which numeric field the tap-to-type/wheel sheet is
    /// currently editing. nil = no sheet presented.
    @State
    private var activeEntryField: EntryField?
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

    /// Lower bound in the display unit: the empty bar for bar-loaded lifts
    /// (you can't lift less than the bar), else 0. A calibration set starts
    /// blank by design, so it keeps 0.
    private var weightRangeMin: Double {
        guard !currentSetIsCalibration, currentEquipment.isBarLoaded else {
            return 0
        }
        return WeightConverter.barWeight(for: currentEquipment, unit: weightUnit)
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
        let perSideStr = WeightFormat.number(perSide)
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
            // Empty bar: "Empty 45 lbs bar", never "0 lbs/side".
            return perSide > 0
                ? "\(perSideStr) \(unit)/side + \(barStr) \(unit) bar"
                : "Empty \(barStr) \(unit) bar"
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

    /// User bodyweight (kg) for effective-load math. 0 when unknown — §15:
    /// that used to fall straight through to `bodyweightEffectiveKg` and log
    /// a bodyweight lift at 0 kg. `bodyweightPromptDisplayValue` below is the
    /// inline session prompt that now covers this gap.
    private var bodyweightKg: Double {
        profiles.first?.weightKg ?? 0
    }

    /// §15 fix — inline prompt value (display unit) for a session where the
    /// profile has no bodyweight on file. Seeded to a sane default in
    /// `loadCurrentSetInputs`; only shown/used while `bodyweightKg <= 0`.
    @State
    private var bodyweightPromptDisplayValue: Double = 70

    /// Effective logged load (kg) for a bodyweight lift = bodyweight ± added,
    /// never negative. `inputAddedLoad` is in the display unit. Falls back to
    /// the inline prompt (never to 0) when the profile has no weight on file.
    private var bodyweightEffectiveKg: Double {
        BodyweightLiftMath.effectiveLoadKg(
            profileBodyweightKg: bodyweightKg,
            promptBodyweightKg: weightUnit.convert(bodyweightPromptDisplayValue, to: .kg),
            addedLoadKg: weightUnit.convert(inputAddedLoad, to: .kg)
        )
    }

    /// Human hint under the added-load stepper: "= 77.7 kg effective · assisted".
    private var bodyweightEffectiveHint: String {
        let unit = weightUnit.abbreviation
        let effStr = WeightFormat.number(kg: bodyweightEffectiveKg, unit: weightUnit)
        let tag = if inputAddedLoad > 0 {
            "weighted"
        } else if inputAddedLoad < 0 {
            "assisted"
        } else {
            "bodyweight"
        }
        return "= \(effStr) \(unit) effective · \(tag)"
    }

    @State
    private var prToast: PersonalRecord?
    @State
    private var showNotes = false

    /// §3 — see the toolbar Finish button's own comment: only a live or
    /// paused session offers the generic Finish action.
    private var showFinishButtonInToolbar: Bool {
        switch viewModel.sessionState {
        case .warmup,
             .exercise,
             .paused:
            true
        default:
            false
        }
    }

    private func prToastView(_ pr: PersonalRecord) -> some View {
        HStack(spacing: Tide.s2) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(TideTrain.record)
            VStack(alignment: .leading, spacing: 0) {
                Text("New PR")
                    .font(Tide.headline)
                    .foregroundStyle(TideTrain.record)
                // §15 fix — the weight shown here comes from `pr.value`
                // converted to the user's unit (PRDisplay), never from the
                // engine's kg-only, unit-unaware `context` string.
                Text("\(pr.exercise?.name ?? "Exercise") · \(PRDisplay.valueLabel(pr, unit: weightUnit))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s2)
        .background(Tide.fill)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                TideTrain.record.opacity(TideTrainSession.outlineOpacity),
                lineWidth: TideTrainSession.rule
            )
        )
        .accessibilityElement(children: .combine)
    }

    var body: some View {
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
                // the cover is being dismissed — keep the page, not a blank
                // "broken"-looking view, during the teardown frame.
                Color.clear
            }
        }
        // Set → rest → next set cross-fades instead of cutting.
        .animation(reduceMotion ? nil : Tide.snap, value: phaseKey)
        // The cover is opened from inside a page: draw its own field.
        .trainSheetRoot(energy: 0.8)
        // §12 — the PR moment lands on the set that earned it, not later on
        // the summary. logSet appends to detectedPRs when one fires.
        .overlay(alignment: .top) {
            if let pr = prToast {
                prToastView(pr)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, Tide.s6)
            }
        }
        .onChange(of: viewModel.detectedPRs.count) { old, new in
            guard new > old, let pr = viewModel.detectedPRs.last else {
                return
            }
            HapticManager.success()
            withAnimation(Tide.lively) { prToast = pr }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if prToast?.id == pr.id {
                    withAnimation(Tide.snap) { prToast = nil }
                }
            }
        }
        .sheet(isPresented: $showNotes) {
            if let plan = viewModel.todayPlan {
                NavigationStack {
                    SessionNotesField(plan: plan)
                        .padding(Tide.edge)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .trainSheetRoot()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    modelContext.saveOrAlert("session notes")
                                    showNotes = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
        // Save failures while the full-screen cover is up (the Training tab's
        // alerts can't present over it).
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { viewModel.saveErrorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveErrorMessage ?? "")
        }
        .persistenceAlert()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                .accessibilityLabel("Pause workout")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showNotes = true
                } label: {
                    Image(systemName: viewModel.todayPlan?.userNotes == nil ? "note.text.badge.plus" : "note.text")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                .accessibilityLabel("Session notes")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // §3 fix — Finish only makes sense while a session is
                // actually live or paused. `.crashedRecovery` has its own
                // Resume/Discard pair (finishing there skipped the timing
                // restore entirely) and `.interruptedCall` auto-resumes with
                // its own "Resume now" escape hatch — offering a second,
                // generic Finish in either duplicated (or for crashedRecovery,
                // silently bypassed) their real flows.
                if showFinishButtonInToolbar {
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Text("Finish")
                            .font(Tide.headline)
                            // The toolbar sits outside the sheet root's mood,
                            // so it reads the day's accent itself.
                            .foregroundStyle(TideMood(score: services.appState.dayScore).accent)
                    }
                }
            }
        }
        .alert(
            "Log this set?",
            isPresented: Binding(
                get: { setPlausibilityWarning != nil },
                set: {
                    if !$0 {
                        setPlausibilityWarning = nil
                    }
                }
            )
        ) {
            Button("Log it") {
                setPlausibilityWarning = nil
                commitCurrentSet()
            }
            Button("Fix it", role: .cancel) {}
        } message: {
            Text(setPlausibilityWarning ?? "")
        }
        // Centered alert (not a popover/action sheet) for the finish choice.
        .alert("Finish Workout?", isPresented: $showFinishConfirmation) {
            Button("Save what I did") {
                viewModel.finishWorkout(modelContext: modelContext)
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
        .sheet(isPresented: $showHowTo) {
            if let exercise = viewModel.currentExercise?.exercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                }
            }
        }
        .sheet(isPresented: $showPainReport, onDismiss: {
            // Mild pain reduces the CURRENT set's target weight in place
            // (TrainingViewModel+Pain.swift.reduceLoad) — refresh the cached
            // input fields so the athlete can't log the pre-reduction number.
            loadCurrentSetInputs()
        }) {
            // "End the session" is routed by sessionState (summary / discard
            // close this cover from TrainingTabView) — no dismiss() here.
            PainReportSheet(viewModel: viewModel, plannedExercise: viewModel.currentExercise)
        }
        // §4.2-4.4 — tap-to-type / scroll-wheel entry for weight, added load,
        // and reps. One sheet type, driven by which field was tapped.
        .sheet(item: $activeEntryField) { field in
            entrySheet(for: field)
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
        TrainSessionBar(
            elapsed: viewModel.formattedElapsedTime,
            done: viewModel.completedSets,
            total: viewModel.totalSets,
            volume: viewModel.formattedVolume
        )
    }

    /// Which screen the session is on: a change cross-fades the page.
    private var phaseKey: Int {
        switch viewModel.sessionState {
        case .warmup: 0
        case .exercise(.setActive): 1
        case .exercise(.resting): 2
        case .exercise(.betweenExercises): 3
        case .paused: 4
        case .interruptedCall: 5
        case .crashedRecovery: 6
        default: 7
        }
    }

    // MARK: - Set Active Content

    // Per MODULE_TRAINING.md Section 3 — Weight/reps inputs, DONE button

    /// The logger: what you are lifting, then the current set as one hero card
    /// (weight and reps side by side, the numbers you compare them with in its
    /// footer), then what is next. Finish Set sits at the bottom, under the thumb.
    private var setActiveContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                exerciseHeader

                alertChips

                // §15 fix — no bodyweight on file yet: prompt for it inline,
                // once, right here (not a separate screen), so the FIRST
                // bodyweight-lift log of the session never has to fall back
                // to 0 kg. Persisted to UserProfile.weightKg on Finish Set —
                // see `persistBodyweightIfNeeded()`.
                if isBodyweightLift, bodyweightKg <= 0 {
                    TrainStepper(
                        value: $bodyweightPromptDisplayValue,
                        label: "Your bodyweight",
                        range: WeightUnit.kg.convert(30, to: weightUnit) ... WeightUnit.kg.convert(300, to: weightUnit),
                        step: weightStep,
                        format: weightUnit == .kg ? "%.1f" : "%.0f",
                        unit: weightUnit.abbreviation,
                        caption: "Needed to log this lift. Saved to your profile for pull-ups, dips and similar lifts.",
                        onTapValue: { activeEntryField = .bodyweight }
                    )
                    .tideCard(padding: Tide.s4)
                }

                setCard

                // Fix #9 — optional L/R split (e.g. L 8 / R 7).
                if isPerSideExercise, !currentSetIsWarmup {
                    PerSideRepsControl(left: $inputReps, right: $inputRepsRight, splitEnabled: $logRepsSeparately)
                }

                // RPE is collected end-of-set in the inline feedback panel
                // (under the rest timer), not here — one prompt, not two.

                upNextLine
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            actionRow
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s3)
        }
    }

    /// The current set: weight and reps as one card.
    private var setCard: some View {
        let hasHints = loadHint != nil || effortCaption != nil
        return TrainSessionSetCard(showsHints: hasHints) {
            if isBodyweightLift {
                // Bodyweight-loaded lift (pull-up/dip): log a SIGNED added
                // load — negative = assistance (band/machine), positive =
                // weight belt/vest. Effective load = bodyweight ± this.
                TrainSessionField(
                    value: $inputAddedLoad,
                    label: "Added load",
                    range: -weightRangeMax ... weightRangeMax,
                    step: weightStep,
                    format: weightUnit == .kg ? "%+.1f" : "%+.0f",
                    unit: weightUnit.abbreviation,
                    reserveLabel: true,
                    onTapValue: { activeEntryField = .addedLoad }
                )
            } else {
                // Weight input — the logged number is TOTAL load including the
                // bar. For bar-loaded lifts we show a per-side plate hint so
                // there's no ambiguity about what to actually put on.
                TrainSessionField(
                    value: $inputWeight,
                    label: currentEquipment.isBarLoaded ? "Weight, total with bar" : "Weight",
                    range: weightRangeMin ... weightRangeMax,
                    step: weightStep,
                    format: weightUnit == .kg ? "%.1f" : "%.0f",
                    unit: weightUnit.abbreviation,
                    reserveLabel: true,
                    onTapValue: { activeEntryField = .weight }
                )
            }
        } secondary: {
            TrainSessionField(
                value: $inputReps,
                label: isPerSideExercise ? "REPS — LEFT" : "Reps",
                range: 1 ... 100,
                step: 1,
                format: "%.0f",
                unit: isPerSideExercise ? "reps / side" : "reps",
                reserveLabel: true,
                onTapValue: { activeEntryField = .reps }
            )
        } hints: {
            if let loadHint {
                Text(loadHint.text)
                    .font(Tide.caption)
                    .foregroundStyle(loadHint.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // §11.12 — the effort target that makes the weight make
            // sense: the load is computed FOR this rep count at this
            // proximity to failure.
            if let effortCaption {
                Text(effortCaption)
                    .font(Tide.caption)
                    .foregroundStyle(TideTrain.caution)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            contextStrip
        }
    }

    /// The line under the weight: the plates to load, the calibration prompt,
    /// or what a bodyweight set adds up to.
    private var loadHint: (text: String, color: Color)? {
        if isBodyweightLift {
            return ("Minus is assisted, plus is weighted. \(bodyweightEffectiveHint)", Tide.text2)
        }
        if currentSetIsCalibration {
            return (calibrationPromptText, TideTrain.caution)
        }
        return perSideHint.map { ($0, Tide.text2) }
    }

    /// "Leave 2 reps in the tank" — nil on ramp sets and when there is no target.
    private var effortCaption: String? {
        guard !currentSetIsWarmup, let rir = viewModel.currentSet?.targetRIR else {
            return nil
        }
        return rir == 0
            ? "All out — nothing left in the tank"
            : "Effort: leave \(rir) rep\(rir == 1 ? "" : "s") in the tank"
    }

    /// One-line condition chips (ramp / pain / superset / drop) — the old
    /// full-width banners each ate a screen row; these say the same thing in
    /// 28pt.
    @ViewBuilder
    private var alertChips: some View {
        let exerciseID: UUID? = viewModel.currentExercise?.exercise?.id
        let painFlagged = exerciseID.map { viewModel.painFlaggedExercises.contains($0) } ?? false
        let dropIndex = viewModel.currentSet?.dropStepIndex
        if currentSetIsWarmup || currentSetIsCalibration || painFlagged
            || viewModel.currentSupersetPartnerName != nil || dropIndex != nil
        {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tide.s1) {
                    if currentSetIsWarmup {
                        // §13 — a trainer day's ramp is one Tempo added.
                        let isTrainerDay = viewModel.currentExercise?.workoutPlan?.programSessionKey != nil
                        chip(
                            "flame",
                            isTrainerDay ? "TEMPO WARM-UP — doesn't count" : "RAMP-UP — doesn't count",
                            Color.accentColor
                        )
                    }
                    if currentSetIsCalibration {
                        chip("ruler", "CALIBRATION SET", TideTrain.caution)
                    }
                    if painFlagged {
                        chip("exclamationmark.triangle.fill", "Pain flagged — weight held, go easy", TideTrain.caution)
                    }
                    if let partner = viewModel.currentSupersetPartnerName {
                        let label = viewModel.currentGroupIsCircuit ? "Circuit" : "Superset"
                        chip("arrow.triangle.2.circlepath", "\(label): \(partner)", Color.accentColor)
                    }
                    // §6.4/§7.7 — a drop step: no rest, reduced weight, to failure.
                    if let dropIndex {
                        chip("arrow.down.circle.fill", "DROP \(dropIndex) — no rest, to failure", TideTrain.caution)
                    }
                }
            }
        }
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        TrainTag(text: text, systemImage: icon, color: color)
    }

    // MARK: - Context Strip (§11.7 — the "more data")

    /// Display-unit conversion for stored-kg history values.
    private func displayWeight(_ kg: Double) -> String {
        WeightFormat.number(kg: kg, unit: weightUnit)
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
        guard let prior, let r = prior.bestSetReps, r > 0 else {
            return nil
        }
        // A bodyweight set reads "BW × 10", never "0 × 10".
        if isBodyweightLift {
            return "\(WeightFormat.bodyweightLoad(addedKg: prior.bestSetAddedLoadKg, unit: weightUnit)) × \(r)"
        }
        guard let w = prior.bestSetWeight, w > 0 else {
            return "BW × \(r)"
        }
        return "\(displayWeight(w)) × \(r)"
    }

    /// Today's prescription for the CURRENT set.
    private var targetStat: String? {
        guard let set = viewModel.currentSet, let w = set.targetWeight else {
            return nil
        }
        let reps = SideRepsFormat.reps(set.targetReps, perSide: viewModel.currentExercise?.perSide == true)
        // No external load: 0 is "just bodyweight" on a bodyweight lift, and
        // "no weight prescribed yet" on a loaded one — never "0 × 10".
        if w <= 0 {
            return isBodyweightLift ? "BW × \(reps)" : "\(reps) reps"
        }
        return "\(displayWeight(w)) × \(reps)"
    }

    /// Plausibility check for the set about to be logged (display → kg).
    private var pendingSetWarning: String? {
        guard !isBodyweightLift else {
            return nil
        }
        let best = (viewModel.currentExercise?.exercise?.history ?? []).compactMap(\.estimated1RM).max()
        return SetPlausibility.warning(
            weightKg: weightUnit.convert(inputWeight, to: .kg),
            reps: Int(inputReps),
            bestE1RMKg: best,
            equipment: viewModel.currentExercise?.exercise?.equipment,
            isWarmup: currentSetIsWarmup
        )
    }

    private func commitCurrentSet() {
        // Inputs are in the user's display unit; persist kg. For a
        // bodyweight lift the logged weight is the EFFECTIVE load
        // (bodyweight ± added) and we also record the signed added load.
        if isBodyweightLift {
            // §15 — commit the inline prompt to the profile BEFORE
            // logging, so this and every later bodyweight lift this
            // session (and beyond) reads a real weight, not 0.
            persistBodyweightIfNeeded()
            viewModel.logSet(
                weight: bodyweightEffectiveKg,
                reps: Int(inputReps),
                addedLoadKg: weightUnit.convert(inputAddedLoad, to: .kg),
                leftReps: splitLeftReps,
                rightReps: splitRightReps,
                modelContext: modelContext
            )
        } else {
            let weightKg = weightUnit.convert(inputWeight, to: .kg)
            viewModel.logSet(
                weight: weightKg,
                reps: Int(inputReps),
                leftReps: splitLeftReps,
                rightReps: splitRightReps,
                modelContext: modelContext
            )
        }
        HapticManager.notification(.success)
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
        TrainSessionContext(cells: [
            .init(label: "Last", value: lastSessionStat ?? "—"),
            .init(label: "Target", value: targetStat ?? "—", highlight: true),
            .init(label: "Best e1RM", value: bestE1RMStat ?? "—"),
        ])
    }

    // MARK: - Drop Set Control (§6.4 / §6.5)

    /// "+ Drop Set" queues a reduced-weight, no-rest continuation right after
    /// this set (chainable — tap again for a second drop); once queued it
    /// becomes "Remove Drop" so an accidental tap is a one-tap undo. Hidden
    /// on warmups (a ramp set is never dropped).
    @ViewBuilder
    private var dropSetControl: some View {
        if !currentSetIsWarmup {
            Button {
                if viewModel.currentSetHasPendingDrop {
                    viewModel.removeTrailingDropSet(modelContext: modelContext)
                } else {
                    // Base the drop on what's dialed in NOW (kg), not the
                    // set's stale prescribed target. Bodyweight lifts drop
                    // off their prescribed load — no meaningful entered kg.
                    viewModel.addDropSet(
                        enteredWeightKg: isBodyweightLift ? nil : weightUnit.convert(inputWeight, to: .kg),
                        modelContext: modelContext
                    )
                }
                HapticManager.selection()
            } label: {
                Label(
                    viewModel.currentSetHasPendingDrop ? "Remove Drop" : "+ Drop Set",
                    systemImage: viewModel.currentSetHasPendingDrop ? "minus.circle" : "arrow.down.circle"
                )
                .font(Tide.bodyStrong)
                .foregroundStyle(viewModel.currentSetHasPendingDrop ? Tide.text2 : TideTrain.caution)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action Row

    /// Skip + Finish side by side — skip always visible, never the hero.
    private var actionRow: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            // Large text: the two buttons stack, Finish Set last (lowest, under the thumb).
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s2))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            layout {
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
                        .frame(minHeight: TideTrain.bigButton - Tide.s2)
                }
                .buttonStyle(.tideGlass)

                Button {
                    if let warning = pendingSetWarning {
                        setPlausibilityWarning = warning
                        return
                    }
                    commitCurrentSet()
                } label: {
                    Text(finishButtonLabel)
                        .frame(minHeight: TideTrain.bigButton - Tide.s2)
                }
                .buttonStyle(.tidePrimary)
                .sensoryFeedback(.success, trigger: viewModel.completedSets)
            }
        }
    }

    /// Whether the set currently being entered is a warm-up (ramp) set.
    var currentSetIsWarmup: Bool { // Fix #9 — not `private`: read from +PerSide.swift
        viewModel.currentSet?.isWarmup ?? false
    }

    /// §5 — whether the current set is a calibration set: a trainer % with no
    /// reliable e1RM to read it against. No weight is pre-filled; logging it
    /// derives the working weights for the rest of the exercise.
    private var currentSetIsCalibration: Bool {
        viewModel.currentSet?.isCalibration ?? false
    }

    /// §5 — "Calibration — pick a weight you could do ~N more reps with".
    private var calibrationPromptText: String {
        guard let rir = viewModel.currentSet?.targetRIR, rir > 0 else {
            return "Calibration — pick a weight for this exercise"
        }
        return "Calibration — pick a weight you could do ~\(rir) more rep\(rir == 1 ? "" : "s") with"
    }

    /// §6.4 — names the drop step explicitly ("Finish Drop 2") so the
    /// no-rest continuation reads as deliberate, not a UI glitch.
    private var finishButtonLabel: String {
        if currentSetIsWarmup {
            return "Finish Warm-Up"
        }
        if let dropIndex = viewModel.currentSet?.dropStepIndex {
            return "Finish Drop \(dropIndex)"
        }
        return "Finish Set"
    }

    // MARK: - Warmup Content

    // A guided, workout-SPECIFIC 10–15 min warm-up + mobility block shown before
    // the first working set. Content comes from WarmupRoutine (single source,
    // shared with the WeekPlanView mobility card). Includes elbow/biceps-tendon
    // prep on every day. After the routine, the first exercise's ramp-set
    // targets are previewed, then "Start Working Sets" enters the lift.
    // This block logs nothing — it is deliberately not part of WorkoutSessionState.

    @ViewBuilder
    private var warmupContent: some View {
        if let move = viewModel.currentWarmupMove {
            warmupMovePlayer(move)
        } else {
            warmupRampPreview
        }
    }

    /// Guided step-through: one move at a time, big and readable. Timed moves
    /// show a countdown that auto-advances; rep-based moves show a Next button.
    private func warmupMovePlayer(_ move: WarmupMove) -> some View {
        let routine = viewModel.warmupRoutine
        let total = routine?.moves.count ?? 0
        let isTimed = (move.durationSeconds ?? 0) > 0
        let left = viewModel.warmupMoveRemaining
        let fraction = isTimed ? min(max(left / Double(move.durationSeconds ?? 1), 0), 1) : 0

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Warm-up · move \(viewModel.warmupMoveIndex + 1) of \(total)").tideLabel()
                    TrainSessionDots(count: total, current: viewModel.warmupMoveIndex)
                    Text(move.name)
                        .font(Tide.title)
                        .foregroundStyle(move.isTendonPrep ? Color.accentColor : Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(move.dose)
                        .font(TideTrain.figure(.headline))
                        .foregroundStyle(Tide.text2)
                }

                if isTimed {
                    TrainRing(progress: fraction, diameter: TideTrainSession.restRingCompact) {
                        Text(warmupCountdownLabel)
                            .trainNumeral(TideTrainSession.ringClock)
                            .foregroundStyle(Tide.text)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.linear(duration: 1), value: fraction)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Time left")
                    .accessibilityValue(warmupCountdownLabel)
                }

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text(move.howTo)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cue = move.cue {
                        TrainSessionRule()
                        HStack(alignment: .top, spacing: Tide.s2) {
                            Image(systemName: "lightbulb.fill")
                                .font(Tide.caption)
                                .foregroundStyle(TideTrain.caution)
                                .accessibilityHidden(true)
                            Text(cue)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: Tide.s2) {
                Button {
                    viewModel.skipWarmupMove()
                    HapticManager.notification(.success)
                } label: {
                    Text(isTimed ? "Skip →" : "Done — Next →")
                }
                .buttonStyle(.tidePrimary)

                Button {
                    viewModel.advancePastWarmup()
                    HapticManager.selection()
                } label: {
                    Text("Skip whole warm-up")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
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
            VStack(alignment: .leading, spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Warm-up done").tideLabel()
                    Text("Ramp up: \(firstExercise?.exercise?.name ?? "")")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !warmupSets.isEmpty {
                    VStack(spacing: Tide.s3) {
                        ForEach(Array(warmupSets.enumerated()), id: \.element.id) { index, set in
                            if index > 0 {
                                TrainSessionRule()
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text("Ramp set \(index + 1)")
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(Tide.text2)
                                Spacer(minLength: Tide.s2)
                                Text(warmupTargetLabel(set))
                                    .font(TideTrain.figure(.title3))
                                    .foregroundStyle(Tide.text)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                } else {
                    Text("No ramp sets for this exercise — go straight to your working sets.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            Button {
                viewModel.advancePastWarmup()
                HapticManager.notification(.success)
            } label: {
                Text("Start Working Sets")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        }
    }

    private func warmupTargetLabel(_ set: PlannedSet) -> String {
        let reps = SideRepsFormat.reps(set.targetReps, perSide: set.plannedExercise?.perSide == true)
        if let w = set.targetWeight, w > 0 {
            return "\(WeightFormat.text(kg: w, unit: weightUnit)) × \(reps)"
        }
        return "Bodyweight × \(reps)"
    }

    // MARK: - Exercise Header

    /// What you are lifting: the demo picture, the name, where you are in it, and
    /// the "How to" and "This hurts" buttons. The set strip sits right under it:
    /// it is the progress of this exercise.
    private var exerciseHeader: some View {
        Group {
            if let exercise = viewModel.currentExercise?.exercise {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    if typeSize.isAccessibilitySize {
                        // Large text: picture and buttons on one row, the name
                        // gets the full width under them.
                        HStack(spacing: Tide.s3) {
                            headerPicture(exercise)
                            Spacer(minLength: 0)
                            headerButtons
                        }
                        headerTitle(exercise)
                    } else {
                        HStack(alignment: .center, spacing: Tide.s3) {
                            headerPicture(exercise)
                            headerTitle(exercise)
                            Spacer(minLength: 0)
                            headerButtons
                        }
                    }
                    setProgress
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Slide-in on exercise change — .id remounts the header so the
        // asymmetric transition fires exactly once per movement.
        .id(viewModel.currentExerciseIndex)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(Tide.lively, value: viewModel.currentExerciseIndex)
    }

    private func headerPicture(_ exercise: Exercise) -> some View {
        ExerciseImageView(exercise: exercise, style: .hero)
            .frame(width: TideTrain.thumb, height: TideTrain.thumb)
            .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private func headerTitle(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            // trainer-feedback-tests — this session's a
            // trainer-flagged 1RM/3RM/5RM/time-trial test.
            if viewModel.currentExercise?.isTestExercise == true {
                Text("TEST — WORK UP TO A MAX")
                    .font(Tide.label)
                    .foregroundStyle(Color.accentColor)
            }
            Text(exercise.name)
                .accessibilityLabel(exercise.name.uppercased())
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(Tide.labelShrink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(exercise.muscleGroup.displayName) · \(viewModel.setCountText)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var headerButtons: some View {
        GlassEffectContainer(spacing: Tide.s2) {
            HStack(spacing: Tide.s2) {
                TrainIconButton(systemImage: "info.circle", label: "How to") {
                    showHowTo = true
                }
                // "This hurts" flow — see PainReportSheet.swift.
                TrainIconButton(systemImage: "bandage", label: "This hurts", tint: Tide.danger) {
                    showPainReport = true
                }
            }
        }
    }

    /// §11.13 — what's coming after this exercise, visible WHILE lifting
    /// (the rest screen already previews it; the set screen didn't).
    private var upNextLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                Text("Up next").tideLabel()
                Text(upNextName ?? "Last exercise — finish strong")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                Spacer(minLength: Tide.s2)
                dropSetControl
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("Up next").tideLabel()
                Text(upNextName ?? "Last exercise — finish strong")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                dropSetControl
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var upNextName: String? {
        guard let plan = viewModel.todayPlan else {
            return nil
        }
        let exercises = plan.orderedExercises
        return exercises.indices
            .first { $0 > viewModel.currentExerciseIndex && !exercises[$0].orderedSets.isEmpty }
            .flatMap { exercises[$0].exercise?.name }
    }

    // MARK: - Set Progress

    /// One capsule per set, with the remove and add buttons at its ends.
    private var setProgress: some View {
        HStack(spacing: Tide.s2) {
            Button {
                viewModel.removeLastUncompletedSet(
                    from: viewModel.currentExerciseIndex,
                    modelContext: modelContext
                )
            } label: {
                Image(systemName: "minus")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled((viewModel.currentExercise?.orderedSets.count ?? 0) <= 1)
            .accessibilityLabel("Remove a set")

            if let exercise = viewModel.currentExercise {
                // Iterate the elements by stable id — never index into
                // orderedSets by position. The +/- buttons mutate this
                // array; a ForEach over `.indices` keeps a stale range
                // and crashes (Index out of range) on the next render.
                TrainSetStrip(items: exercise.orderedSets.enumerated().map { idx, set in
                    TrainSetStrip.Item(
                        id: set.id,
                        done: set.completed,
                        current: idx == viewModel.currentSetIndex,
                        warmup: set.isWarmup
                    )
                })
            }

            Button {
                viewModel.addSet(
                    to: viewModel.currentExerciseIndex,
                    modelContext: modelContext
                )
            } label: {
                Image(systemName: "plus")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a set")
        }
    }

    // MARK: - Exercise Transition

    /// The brief moment between two exercises: who is next, with their picture.
    private func exerciseTransition(toIndex: Int) -> some View {
        let exercises = viewModel.todayPlan?.orderedExercises ?? []
        let next = toIndex < exercises.count ? exercises[toIndex] : nil
        return VStack(spacing: Tide.s4) {
            Spacer()
            if let exercise = next?.exercise {
                ExerciseImageView(exercise: exercise, style: .hero)
                    .frame(width: TideTrain.hero, height: TideTrain.hero)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: Tide.s2) {
                    Text("Next exercise").tideLabel(Tide.text3)
                    Text(exercise.name)
                        .accessibilityLabel(exercise.name.uppercased())
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.muscleGroup.displayName)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            } else {
                Text("Next exercise").tideLabel(Tide.text3)
            }
            Spacer()
        }
        .padding(.horizontal, Tide.edge)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        TrainSessionStateView(
            systemImage: "pause.fill",
            title: "PAUSED",
            figure: viewModel.formattedElapsedTime
        ) {
            Button {
                viewModel.resume()
            } label: {
                Text("Resume")
            }
            .buttonStyle(.tidePrimary)

            Button {
                showFinishConfirmation = true
            } label: {
                Text("End Workout")
                    .foregroundStyle(Tide.danger)
            }
            .buttonStyle(.tideGlass)
        }
    }

    // MARK: - Call Interruption Overlay

    /// STATE_MACHINES §1 — a live phone call parks the session here; it
    /// restores itself when the call ends (no buttons needed, but an escape
    /// hatch resumes manually if CallKit never reports the end).
    private var interruptedCallOverlay: some View {
        TrainSessionStateView(
            systemImage: "phone.fill",
            title: "On a call",
            message: "Workout paused — it resumes by itself when you hang up."
        ) {
            Button {
                viewModel.handleCallChange(callEnded: true)
            } label: {
                Text("Resume now")
            }
            .buttonStyle(.tideGlass)
        }
    }

    // MARK: - Crash Recovery Content

    private var crashRecoveryContent: some View {
        TrainSessionStateView(
            systemImage: "arrow.counterclockwise",
            tint: TideTrain.caution,
            title: "Resume Your Workout?",
            message: "It looks like a workout was in progress."
        ) {
            Button {
                viewModel.resumeFromCrash()
            } label: {
                Text("Resume workout")
            }
            .buttonStyle(.tidePrimary)

            Button {
                // .discarded closes this cover from TrainingTabView.
                viewModel.discardCrashedWorkout(modelContext: modelContext)
            } label: {
                Text("Discard")
                    .foregroundStyle(Tide.danger)
            }
            .buttonStyle(.tideGlass)
        }
    }

    // MARK: - Numeric Entry (§4.2-4.4)

    /// Which numeric field the tap-to-type/wheel sheet is editing.
    private enum EntryField: String, Identifiable {
        case weight
        case addedLoad
        case reps
        case bodyweight
        var id: String {
            rawValue
        }
    }

    /// Equipment-aware weight increment for both the wheel and the keypad
    /// snap — same rule the +/- stepper already uses.
    private var currentEquipment: Equipment {
        viewModel.currentExercise?.exercise?.equipment ?? .none
    }

    @ViewBuilder
    private func entrySheet(for field: EntryField) -> some View {
        switch field {
        case .weight:
            NumericEntrySheet(
                title: "Weight",
                unit: weightUnit.abbreviation,
                initialValue: inputWeight,
                range: weightRangeMin ... weightRangeMax,
                wheelValues: NumericEntrySheet.weightWheelValues(step: weightStep, upperBound: weightRangeMax),
                displayFormat: weightUnit == .kg ? "%.1f" : "%.0f",
                snap: { displayValue in
                    let kg = WeightConverter.loadableKg(
                        weightUnit.convert(displayValue, to: .kg), equipment: currentEquipment, unit: weightUnit
                    )
                    return WeightUnit.kg.convert(kg, to: weightUnit)
                },
                onSave: { inputWeight = $0 }
            )
        case .addedLoad:
            NumericEntrySheet(
                title: "Added Load",
                unit: weightUnit.abbreviation,
                initialValue: inputAddedLoad,
                range: -weightRangeMax ... weightRangeMax,
                wheelValues: NumericEntrySheet.weightWheelValues(
                    step: weightStep, lowerBound: -weightRangeMax, upperBound: weightRangeMax
                ),
                displayFormat: weightUnit == .kg ? "%+.1f" : "%+.0f",
                snap: { (($0 / weightStep).rounded()) * weightStep },
                onSave: { inputAddedLoad = $0 }
            )
        case .reps:
            NumericEntrySheet(
                title: "Reps",
                unit: "reps",
                initialValue: inputReps,
                range: 1 ... 100,
                wheelValues: NumericEntrySheet.intWheelValues(1 ... 100),
                displayFormat: "%.0f",
                snap: { $0.rounded() },
                onSave: { inputReps = $0 }
            )
        case .bodyweight:
            let lower = WeightUnit.kg.convert(30, to: weightUnit)
            let upper = WeightUnit.kg.convert(300, to: weightUnit)
            NumericEntrySheet(
                title: "Bodyweight",
                unit: weightUnit.abbreviation,
                initialValue: bodyweightPromptDisplayValue,
                range: lower ... upper,
                wheelValues: NumericEntrySheet.weightWheelValues(
                    step: weightStep, lowerBound: lower, upperBound: upper
                ),
                displayFormat: weightUnit == .kg ? "%.1f" : "%.0f",
                snap: { (($0 / weightStep).rounded()) * weightStep },
                onSave: { bodyweightPromptDisplayValue = $0 }
            )
        }
    }

    // MARK: - Helpers

    /// §15 fix — commit the inline bodyweight prompt to the SAME place the
    /// rest of the app reads bodyweight (`UserProfile.weightKg`) the first
    /// time a bodyweight lift is about to be logged without one on file.
    /// No-op once a real profile weight exists, or if there's no profile row
    /// to write to.
    private func persistBodyweightIfNeeded() {
        guard isBodyweightLift, bodyweightKg <= 0, bodyweightPromptDisplayValue > 0,
              let profile = profiles.first
        else {
            return
        }
        profile.weightKg = weightUnit.convert(bodyweightPromptDisplayValue, to: .kg)
        modelContext.saveOrAlert("bodyweight")
    }

    private func loadCurrentSetInputs() {
        logRepsSeparately = false // Fix #9 — never sticky across sets
        // §15 — seed the inline bodyweight prompt with a sane default the
        // first time it's needed this session (only matters while
        // bodyweightKg <= 0; otherwise the prompt never renders).
        if isBodyweightLift, bodyweightKg <= 0 {
            bodyweightPromptDisplayValue = WeightUnit.kg.convert(70, to: weightUnit)
        }
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

        // §5 — a calibration set has no target to pre-fill by design (the
        // athlete picks live); reset to 0 so a heavier weight left over from
        // the PREVIOUS exercise/set can't carry in and look pre-filled.
        if currentSetIsCalibration {
            inputWeight = 0
            if let targetReps = viewModel.currentSet?.targetReps {
                inputReps = Double(targetReps)
            }
            return
        }

        // Warm-up (ramp) sets AND drop steps (§6.4) pre-fill their OWN target
        // — a ramp's 50%/75% weight, or a drop's already-reduced/snapped
        // weight — NOT the sticky/previous weight, which would carry the
        // parent set's heavier weight onto the drop. Plain working sets use
        // sticky (carry the weight you actually lifted forward).
        // stickyWeight/target is kg-stored; convert to the display unit and snap
        // to the stepper grid so the first +/- tap lands on a clean increment.
        let sourceKg: Double? = if viewModel.currentSet?.isWarmup == true || viewModel.currentSet?.isDropStep == true {
            viewModel.currentSet?.targetWeight
        } else {
            viewModel.stickyWeight
        }
        if let kg = sourceKg {
            let display = WeightUnit.kg.convert(kg, to: weightUnit)
            inputWeight = (display / weightStep).rounded() * weightStep
        }
        inputWeight = max(inputWeight, weightRangeMin)
        if let targetReps = viewModel.currentSet?.targetReps {
            inputReps = Double(targetReps)
        }
    }
}

// MARK: - PlateMath

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
            // Up to 2 decimals, no trailing zeros: 1.25, 2.5, 5 (never "%.2g" → "1.2").
            let r = (v * 100).rounded() / 100
            return r == r.rounded() ? String(format: "%.0f", r) : String(r)
        }
        .joined(separator: " + ")
    }

    /// Whether `plates` exactly builds `perSide` (within 10 g / 0.01 lb).
    static func isExact(plates: [Double], perSide: Double) -> Bool {
        abs(plates.reduce(0, +) - perSide) < 0.01
    }
}
