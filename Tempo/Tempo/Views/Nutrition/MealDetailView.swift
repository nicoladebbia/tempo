//
// MealDetailView.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import SwiftData
import SwiftUI

/// Full-screen detail for a single `PlannedMeal`. Three blocks, top to bottom:
///   1. Schedule — prep-start countdown, meal time, eat-finish.
///   2. Prep checklist — auto-generated from frozen ingredients requiring defrost.
///   3. Recipe — ingredients grouped by storage location, numbered steps, macros.
///
/// Step + ingredient checkboxes are in-memory only; they reset when the view
/// disappears. Persisting them is left to a future iteration.
struct MealDetailView: View {
    let meal: PlannedMeal
    /// A "Log meal" notification button opens straight into Mark eaten.
    var opensMarkEaten = false

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// Prep-checklist state is in-memory only (defrost items are derived from
    /// ingredients, not first-class persisted entities). Ingredient/step state
    /// lives on the SwiftData models themselves so it survives backgrounding.
    @State
    private var checkedPrepItems: Set<UUID> = []

    /// True while the MarkEatenSheet is presented. Tapping the overdue
    /// "Mark Eaten" button flips this on; the sheet routes the chosen
    /// time + feel back through `commitMarkEaten`.
    @State
    private var presentMarkEatenSheet: Bool = false

    /// User's planned wake time in minutes-from-midnight, read from
    /// `UserSettings`. Defaults to 07:00 when no settings row exists.
    /// Combined with `actualWakeTime` to compute the schedule shift the
    /// detail view applies (display-only — `scheduledTime` is never
    /// mutated by this screen).
    @State
    private var plannedWakeMinutes: Int = 420
    /// HealthKit/Whoop wake time for today, used as the "actual" anchor
    /// against `plannedWakeMinutes`. Nil until the async fetch lands.
    @State
    private var actualWakeTime: Date?

    /// Drives the eat-time editor sheet. Flipped on by the "Edit time"
    /// button in the .eaten branch of statusLine. The sheet binds to
    /// `eatTimeEdit` and commits via `commitEatTimeEdit()` on dismiss.
    @State
    private var presentEatTimeEditor: Bool = false

    /// Drives the "Undo — not eaten" confirmation sheet in the `.eaten`
    /// status branch.
    @State
    private var presentUndoConfirm: Bool = false
    @State
    private var undoConfirmed: Bool = false
    @State
    private var eatTimeEdit: Date = .now
    /// When true, the Mark-Eaten sheet opens straight into the "Ate something
    /// else" lane (set by the dedicated swap button below).
    @State
    private var openSheetToSubstitute: Bool = false

    /// Parses "what did you eat" text into real foods + DB macros for the
    /// substitute lane. Built lazily from the shared apiClient.
    @State
    private var nlService: NaturalLanguageLoggingService?

    /// True while a substitute note is being parsed through the NL pipeline.
    /// The sheet has already dismissed by the time the parse runs, so the
    /// spinner lives here on the detail screen. Drives a blocking overlay so
    /// the user can't fire a second mark-eaten mid-parse.
    @State
    private var isResolvingSubstitute: Bool = false
    /// Set when the NL parse fails or returns nothing. Surfaced as an alert.
    /// On failure the meal is left fully intact (recipe + macros + planned
    /// status) so the user loses nothing and can retry.
    @State
    private var substituteError: String?
    /// Pro / AI-off while reading "what you ate": asks for the fix.
    @State
    private var substituteBlocker: AIBlocker?
    /// What really happened after a skip ("Coach: ..."), shown under "Skipped".
    /// nil until a redistribution was actually applied.
    @State
    private var skipRedistributionNote: String?
    /// Error from a shared eat/skip/undo/delete action.
    @State
    private var actionError: String?
    /// "Save as preset" naming alert.
    @State
    private var presentPresetAlert = false
    @State
    private var presetNameDraft = ""

    /// Shared side-effect environment (pantry, shift, rebalance, reminders).
    private var outcomeEnv: MealOutcomeService.Env {
        MealOutcomeService.Env.live(
            modelContext: modelContext,
            notifications: services.notifications,
            whoop: services.whoop
        )
    }

    /// A weekly-plan row for a later day: nothing to log yet.
    private var isFutureDay: Bool {
        Calendar.current.startOfDay(for: meal.dayDate) > Calendar.current.startOfDay(for: Date())
    }

    /// The sheet picks "now minus a few minutes"; on another day only its
    /// hour and minute count, placed on that day (like `commitEatTimeEdit`).
    private func eatTimeOnMealDay(_ picked: Date) -> Date {
        let cal = Calendar.current
        guard !cal.isDateInToday(meal.dayDate) else {
            return picked
        }
        var components = cal.dateComponents([.year, .month, .day], from: cal.startOfDay(for: meal.dayDate))
        components.hour = cal.component(.hour, from: picked)
        components.minute = cal.component(.minute, from: picked)
        return cal.date(from: components) ?? picked
    }

    /// A log the user added on top of the plan — undoing it deletes it.
    private var isUnplannedLog: Bool {
        meal.isUnplannedLog
    }

    /// True once this screen deleted its own meal row: nothing may read the
    /// deleted model while the dismiss animation runs.
    @State
    private var isRemoved = false

    var body: some View {
        if isRemoved {
            Color.clear
        } else {
            detail
        }
    }

    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                heroCard
                scheduleSection
                if !prepChecklistItems.isEmpty {
                    prepChecklistSection
                }
                // When a meal was overridden by the user (NL log, voice
                // log, manual log, or "Ate something else" substitute) we
                // prefer the user's actual foods over the AI recipe.
                // Signal: linkedMealLogID is non-nil AND the meal.foods
                // array is populated. Otherwise the planned recipe is
                // still what the user is making, so render that.
                if shouldRenderActualFoods {
                    noRecipeFallback
                } else if let recipe = meal.recipe {
                    ingredientsSection(recipe: recipe)
                    stepsSection(recipe: recipe)
                } else {
                    noRecipeFallback
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s6)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The one thing left to do with a meal sits under the thumb.
        .fuelBottomBar(isShown: needsAnswer) { mealActions }
        .animation(Tide.snap, value: needsAnswer)
        .tidePage()
        .navigationTitle(meal.mealName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadWakeSignal() }
        .onAppear {
            if opensMarkEaten, meal.status == .planned || meal.status == .modified {
                resolveAsEaten()
            }
        }
        // This meal is about to be deleted elsewhere (plan rebuild, Log tab):
        // leave before the model goes away so nothing renders a dead row.
        .onReceive(NotificationCenter.default.publisher(for: .tempoMealWillBeRemoved)) { note in
            if let id = note.userInfo?["id"] as? UUID, id == meal.id {
                dismiss()
            }
        }
        .sheet(isPresented: $presentMarkEatenSheet) {
            MarkEatenSheet(meal: meal, startWithSubstitute: openSheetToSubstitute) { eatTime, feel, satiety, substitute in
                commitMarkEaten(at: eatTime, feel: feel, satiety: satiety, substitute: substitute)
            }
            // Open large when entering the substitute lane so the "what did you
            // eat" field is on-screen, not clipped below a .medium fold.
            .presentationDetents(openSheetToSubstitute ? [.large] : [.medium, .large])
        }
        .sheet(isPresented: $presentEatTimeEditor) {
            eatTimeEditorSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentUndoConfirm, onDismiss: {
            // Undo runs once the sheet is gone: it may pop this screen.
            if undoConfirmed {
                undoConfirmed = false
                undoEaten()
            }
        }) {
            UndoMealSheet(
                mealName: meal.mealName,
                kcal: Int(meal.totalCalories.rounded()),
                isLog: isUnplannedLog,
                onConfirm: {
                    undoConfirmed = true
                    presentUndoConfirm = false
                },
                onCancel: { presentUndoConfirm = false }
            )
            .presentationDetents([.height(Tide.fuelDetentConfirm), .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Save as favourite", isPresented: $presentPresetAlert) {
            TextField("Name", text: $presetNameDraft)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It sits at the top of Log a meal, one tap to log again.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { actionError != nil }, set: {
                if !$0 {
                    actionError = nil
                }
            })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .overlay {
            if isResolvingSubstitute {
                substituteResolvingOverlay
            }
        }
        .alert(
            "Couldn't log that",
            isPresented: Binding(
                get: { substituteError != nil },
                set: {
                    if !$0 {
                        substituteError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { substituteError = nil }
        } message: {
            Text(substituteError ?? "Try describing what you ate a bit differently.")
        }
        .aiBlockerAlert($substituteBlocker)
    }

    /// Blocking spinner shown while the substitute note is parsed. The sheet
    /// is already gone, so this is the only feedback the user gets that work
    /// is happening — keep it on top of the scroll content.
    private var substituteResolvingOverlay: some View {
        ZStack {
            Tide.ink.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: Tide.s3) {
                ProgressView()
                    .tint(mood.accent)
                Text("Logging what you ate…")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            .tideCard(padding: Tide.s4, radius: Tide.cardRadius)
        }
    }

    // MARK: - Eat-time editor

    /// Minimal time-only DatePicker sheet for fixing the recorded
    /// `actualEatenAt` after the fact. Saves to PlannedMeal AND, when a
    /// linked MealLog exists, updates that row's `loggedAt` too so the
    /// Fuel "last meal" line and Coach context stay coherent.
    private var eatTimeEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Tide.s4) {
                Text("Set the time you actually ate \(meal.mealName.lowercased()).")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                DatePicker(
                    "Eaten at",
                    selection: $eatTimeEdit,
                    in: ...Date(),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Button {
                    commitEatTimeEdit()
                    presentEatTimeEditor = false
                    HapticManager.notification(.success)
                } label: {
                    Text("Save")
                }
                .buttonStyle(.tidePrimary)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s4)
            .padding(.bottom, Tide.s4)
            .tidePage()
            .navigationTitle("Edit eat time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentEatTimeEditor = false }
                }
            }
        }
    }

    /// Persists the chosen `eatTimeEdit` to PlannedMeal.actualEatenAt and
    /// the linked MealLog (if any). Bound to today's date — the picker
    /// only exposes hour/minute, so we keep the calendar day stable.
    @MainActor
    private func commitEatTimeEdit() {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: meal.dayDate)
        let hour = cal.component(.hour, from: eatTimeEdit)
        let minute = cal.component(.minute, from: eatTimeEdit)
        var components = cal.dateComponents([.year, .month, .day], from: dayStart)
        components.hour = hour
        components.minute = minute
        guard let normalized = cal.date(from: components) else {
            return
        }
        meal.actualEatenAt = normalized

        // Keep the linked MealLog row in sync so the Fuel card and Coach
        // context don't disagree with the planned-meal display.
        if let logID = meal.linkedMealLogID {
            let descriptor = FetchDescriptor<MealLog>(
                predicate: #Predicate<MealLog> { $0.id == logID }
            )
            if let log = try? modelContext.fetch(descriptor).first {
                log.loggedAt = normalized
            }
        }
        try? modelContext.save()
        // Dashboard's "last meal" line reads this time.
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
    }

    /// Pull the user's planned wake from `UserSettings` and today's actual
    /// wake from HealthKit so the schedule block reflects the same
    /// Whoop-adaptive shift the Fuel day list uses. Both fetches are
    /// non-fatal — failure leaves the block showing stored times.
    private func loadWakeSignal() async {
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(settingsDescriptor).first {
            plannedWakeMinutes = settings.wakeTimeMinutes
        }
        do {
            let sleep = try await services.healthKit.fetchSleepAnalysis(for: Date())
            actualWakeTime = sleep.wakeTime
        } catch {
            actualWakeTime = nil
        }
    }

    private var scheduleDisplay: MealScheduleDisplay {
        FuelMealScheduleAnnotator.display(
            for: meal,
            plannedWakeMinutes: plannedWakeMinutes,
            actualWakeTime: actualWakeTime
        )
    }

    /// True when the user replaced the AI-generated dish with their own
    /// log (NL, voice, manual, or substitute via MarkEatenSheet). In
    /// that state the recipe-card content is misleading — the user
    /// didn't make those ingredients or follow those steps — so we
    /// render the actual logged foods instead. Falls back to recipe
    /// rendering when nothing was overridden.
    private var shouldRenderActualFoods: Bool {
        meal.linkedMealLogID != nil && !meal.foods.isEmpty
    }

    // MARK: - Hero

    /// Calories and macros of what this page shows: the foods the user
    /// actually logged, else the recipe, else the plan's own totals.
    private var heroTotals: (kcal: Int, protein: Int, carbs: Int, fat: Int) {
        let foods = meal.foods
        if shouldRenderActualFoods || (meal.recipe == nil && !foods.isEmpty) {
            return (
                Int(foods.reduce(0.0) { $0 + $1.calories }),
                Int(foods.reduce(0.0) { $0 + $1.proteinG }),
                Int(foods.reduce(0.0) { $0 + $1.carbsG }),
                Int(foods.reduce(0.0) { $0 + $1.fatG })
            )
        }
        if let recipe = meal.recipe {
            return (
                Int(recipe.totalCalories), Int(recipe.totalProteinGrams),
                Int(recipe.totalCarbsGrams), Int(recipe.totalFatGrams)
            )
        }
        return (Int(meal.totalCalories), Int(meal.totalProtein), Int(meal.totalCarbs), Int(meal.totalFat))
    }

    /// A meal that is not eaten or skipped yet, on a day that has begun: the
    /// answer (Mark Eaten, swap, skip) sits in the bar under the thumb. Also
    /// open before the meal's time, for someone who ate early.
    private var needsAnswer: Bool {
        meal.status != .eaten && meal.status != .skipped && !isFutureDay
    }

    /// One hero: the meal, its state, the calories as the figure, the macros
    /// as three lit rings.
    private var heroCard: some View {
        let totals = heroTotals
        let tone = FuelMealStyle.tone(for: meal.status, accent: mood.accent)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .top, spacing: Tide.s3) {
                TideIconTile(systemName: FuelMealStyle.icon(forName: meal.mealName), tint: tone)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(meal.mealName)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = meal.recipe?.recipeDescription {
                        Text(description)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: Tide.s2)
                FuelPill(text: meal.status.displayName, color: tone)
            }
            TideNumber("\(totals.kcal)", unit: "kcal", size: Tide.numeralL, relativeTo: .largeTitle)
            FuelMacroRings(protein: totals.protein, carbs: totals.carbs, fat: totals.fat)
            if let recipe = meal.recipe, !shouldRenderActualFoods {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tide.s4) { recipeMetrics(recipe) }
                    VStack(alignment: .leading, spacing: Tide.s2) { recipeMetrics(recipe) }
                }
            }
        }
        .tideCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func recipeMetrics(_ recipe: Recipe) -> some View {
        inlineMetric(icon: "clock", text: "\(recipe.totalMinutes) min")
        inlineMetric(icon: "person.2", text: "\(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")")
        inlineMetric(icon: "flame", text: recipe.difficulty.rawValue.capitalized)
    }

    // MARK: - Schedule

    // Single timeline block. Drives every displayed time off the
    // Whoop/HealthKit-aware annotator, so wake-time shifts surface here just
    // like they do in the Fuel day list. AI-redistribution and
    // eating-time shifts are already persisted to `scheduledTime`, so
    // they ride along for free.

    private var scheduleSection: some View {
        let display = scheduleDisplay
        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Schedule")
                Spacer()
                if display.hasShift {
                    shiftChip(minutes: display.shiftMinutes)
                }
            }

            TimelineView(.everyMinute) { context in
                let now = context.date
                let phase = SchedulePhase(meal: meal, now: now, display: display)
                VStack(alignment: .leading, spacing: Tide.s3) {
                    statusLine(phase: phase, now: now, display: display)
                    // The Prep / Eat / Finish ladder describes future
                    // steps — for an already-eaten or skipped meal those
                    // chips are stale noise. Status line above already
                    // shows "Eaten at HH:mm" or "Skipped".
                    if !phase.isResolved {
                        timelineTrack(now: now, display: display, phase: phase)
                    }
                    // Mark Eaten / swap / Skip for ANY not-yet-resolved meal
                    // (not just overdue, so breakfast eaten early can be
                    // recorded) live in the bar under the thumb: `needsAnswer`.
                }
            }
        }
        .tideCard()
    }

    // MARK: - Schedule sub-components

    /// Single-line status: the *one* thing the user needs to know right
    /// now. Replaces the redundant "Start prepping…" header that paired
    /// with a "PREP START 7:15" chip saying the same thing.
    @ViewBuilder
    private func statusLine(phase: SchedulePhase, now: Date, display: MealScheduleDisplay) -> some View {
        switch phase {
        case .beforePrep:
            let minutes = max(0, Int(display.prepStart.timeIntervalSince(now) / 60))
            Text("Start prepping in \(formatDuration(minutes: minutes)).")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
        case .prepping:
            Text("Prep now — eat at \(Self.clockFormatter.string(from: display.mealTime)).")
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
        case .eating:
            let minutes = max(0, Int(display.eatFinish.timeIntervalSince(now) / 60))
            Text("Eat now — \(formatDuration(minutes: minutes)) left.")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.good)
        case .overdue:
            let minutes = max(1, Int(now.timeIntervalSince(display.eatFinish) / 60))
            Text(
                "Past \(Self.clockFormatter.string(from: display.eatFinish)) — did you eat it? (\(formatDuration(minutes: minutes)) overdue)"
            )
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.warn)
        case let .eaten(at):
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(at.map { "Eaten at \(Self.clockFormatter.string(from: $0))." } ?? "Eaten.")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.good)
                Divider().overlay(Tide.hairline)
                FuelActionRow(icon: "clock.arrow.circlepath", title: "Edit time") {
                    eatTimeEdit = at ?? Date()
                    presentEatTimeEditor = true
                    HapticManager.lightImpact()
                }
                .accessibilityLabel("Edit eat time")
                // Correct what was eaten after the fact — re-opens the swap
                // sheet so "actually I ate something else" works even once the
                // meal is already marked eaten. commitMarkEaten re-records it.
                FuelActionRow(icon: "arrow.triangle.swap", title: "Change what I ate") {
                    resolveAsSubstitute()
                }
                .accessibilityLabel("Change what I ate")
                if !meal.foods.isEmpty {
                    FuelActionRow(icon: "star", title: "Save as favourite") {
                        presetNameDraft = meal.foods.count == 1 ? meal.foods[0].name : meal.mealName
                        presentPresetAlert = true
                        HapticManager.lightImpact()
                    }
                    .accessibilityLabel("Save this meal as a favourite")
                }
                // Undo — take the meal back to planned so a wrong log (e.g.
                // logged to the wrong slot) can be fixed. Confirmed because it
                // clears the eaten state, deletes feedback, and re-credits any
                // pantry stock this meal pulled.
                FuelActionRow(
                    icon: isUnplannedLog ? "trash" : "arrow.uturn.backward",
                    title: isUnplannedLog ? "Delete log" : "Undo — not eaten",
                    isDestructive: true
                ) {
                    presentUndoConfirm = true
                    HapticManager.lightImpact()
                }
                .accessibilityLabel(isUnplannedLog ? "Delete this log" : "Undo, mark as not eaten")
            }
        case .skipped:
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(skipRedistributionNote.map { "Skipped. \($0)" } ?? "Skipped.")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                Divider().overlay(Tide.hairline)
                // Un-skip: put the meal back to planned so it counts again.
                // The shared undo also re-balances the other meals, so macros
                // that were moved onto them when this was skipped move back.
                FuelActionRow(icon: "arrow.uturn.backward", title: "Undo skip — back to planned") {
                    skipRedistributionNote = nil
                    runAction { try MealOutcomeService.undo(meal, env: outcomeEnv) }
                    HapticManager.lightImpact()
                }
                .accessibilityLabel("Undo skip, back to planned")
            }
        }
    }

    /// Inline Eat / Skip buttons shown only in the `.overdue` phase. Both go
    /// through `MealOutcomeService`, the same path as the Today list.
    private var mealActions: some View {
        VStack(spacing: Tide.s2) {
            Button {
                resolveAsEaten()
            } label: {
                Label("Mark Eaten", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.tidePrimary)
            GlassEffectContainer(spacing: Tide.s2) {
                // Side by side while both labels fit on one line, stacked at
                // large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tide.s2) {
                        substituteButton
                        skipButton(fill: false)
                    }
                    VStack(spacing: Tide.s2) {
                        substituteButton
                        skipButton(fill: true)
                    }
                }
            }
        }
    }

    /// "Ate something else" — surfaces the substitute lane directly
    /// instead of burying it inside the Mark-Eaten sheet. Opens the
    /// same sheet pre-expanded to the swap section.
    private var substituteButton: some View {
        Button {
            resolveAsSubstitute()
        } label: {
            Label("Ate something else", systemImage: "arrow.triangle.swap")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
    }

    private func skipButton(fill: Bool) -> some View {
        Button {
            resolveAsSkipped()
        } label: {
            Label("Skip", systemImage: "xmark.circle.fill")
                .lineLimit(1)
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .buttonStyle(.tideGlass)
    }

    /// Triggers the MarkEatenSheet rather than committing immediately.
    /// Sheet's onCommit calls `commitMarkEaten` below with the chosen
    /// time + optional meal-feel chip.
    private func resolveAsEaten() {
        openSheetToSubstitute = false
        presentMarkEatenSheet = true
    }

    /// Opens the Mark-Eaten sheet straight into the "Ate something else" lane.
    private func resolveAsSubstitute() {
        openSheetToSubstitute = true
        presentMarkEatenSheet = true
    }

    /// Runs a shared eat/skip/undo action and reports a failure.
    @MainActor
    @discardableResult
    private func runAction(_ work: () throws -> some Any) -> Bool {
        do {
            _ = try work()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// Undo this meal. A plan slot reverts to planned (original dish back); a
    /// log added on top of the plan is DELETED (the screen blanks itself first,
    /// so nothing renders the deleted model).
    private func undoEaten() {
        let env = outcomeEnv
        let target = meal
        if target.isUnplannedLog, target.status == .eaten {
            // Delete first so a failure shows here. The screen blanks in the
            // same synchronous turn, before SwiftUI re-reads the deleted row.
            if runAction({ try MealOutcomeService.undo(target, env: env) }) {
                isRemoved = true
                HapticManager.notification(.success)
                dismiss()
            }
        } else {
            if runAction({ try MealOutcomeService.undo(target, env: env) }) {
                HapticManager.notification(.success)
            }
            dismiss()
        }
    }

    private func savePreset() {
        let name = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        // runAction already shows the error alert on failure; haptic only on success.
        let saved = runAction {
            try MealOutcomeService.savePreset(
                name: name,
                foods: meal.foods,
                mealType: MealType.inferred(fromName: meal.mealName) ?? .snack,
                isPinned: true,
                modelContext: modelContext
            )
        }
        if saved {
            HapticManager.notification(.success)
        }
    }

    /// Sheet's onCommit handler. Writes the chosen eat time, feel, and
    /// substitute (if any) through the shared service (pantry, shift,
    /// rebalance, reminders, Dashboard ping).
    private func commitMarkEaten(
        at eatTime: Date,
        feel: MealFeel?,
        satiety: MealSatiety?,
        substitute: MarkEatenSheet.Substitute?
    ) {
        guard !isFutureDay else {
            actionError = "That meal is on a later day. You can log it once the day comes."
            return
        }
        let eatTime = eatTimeOnMealDay(eatTime)
        guard let substitute else {
            // Plain "ate the planned meal" — synchronous. Decrements once.
            let done = runAction {
                try MealOutcomeService.markEaten(meal, at: eatTime, feel: feel, satiety: satiety, env: outcomeEnv)
            }
            if done {
                HapticManager.notification(.success)
            }
            return
        }
        // Substitute lane: parse "what did you eat" into real foods + DB macros
        // via the NL pipeline, then REPLACE the meal's foods/macros so the
        // detail screen shows what was actually eaten. The planned dish is
        // remembered so Undo brings it back. One Haiku call.
        Task { await resolveSubstitute(at: eatTime, note: substitute.note, usedPantry: substitute.usedPantry, feel: feel, satiety: satiety)
        }
    }

    @MainActor
    private func resolveSubstitute(at eatTime: Date, note: String, usedPantry: Bool, feel: MealFeel?, satiety: MealSatiety?) async {
        if nlService == nil {
            nlService = NaturalLanguageLoggingService(apiClient: services.apiClient)
        }
        guard let nlService else {
            return
        }
        isResolvingSubstitute = true
        defer { isResolvingSubstitute = false }
        do {
            let items = try await nlService.parseNaturalLanguage(note)
            guard !items.isEmpty else {
                substituteError = "Couldn't recognize any food in \"\(note)\". Edit and try again."
                return
            }
            let foods = items.map {
                PlannedFood(
                    name: $0.name,
                    quantityGrams: $0.quantityGrams,
                    calories: $0.calories,
                    proteinG: $0.proteinG,
                    carbsG: $0.carbsG,
                    fatG: $0.fatG
                )
            }
            // Pantry only when the user said they used their own stock.
            try MealOutcomeService.markEaten(
                meal,
                at: eatTime,
                feel: feel,
                satiety: satiety,
                replacingWith: foods,
                substituteNote: note,
                pantry: usedPantry ? .foods : .none,
                env: outcomeEnv
            )
            HapticManager.notification(.success)
        } catch {
            if let blocker = AIBlocker(error) {
                substituteBlocker = blocker
                return
            }
            substituteError = "Couldn't read that: \(AIBlocker.message(for: error)). Your note is kept — try again."
        }
    }

    /// Skip through the shared service, then redistribute the skipped macros
    /// over the rest of the day and say so only if that really happened.
    private func resolveAsSkipped() {
        let env = outcomeEnv
        let target = meal
        runAction { try MealOutcomeService.skip(target, env: env) }
        guard target.status == .skipped else {
            return
        }
        HapticManager.lightImpact()
        Task { @MainActor in
            // Same inputs as the Today card: today's Whoop recovery + sleep.
            let whoop = services.whoop
            let recovery = try? await whoop.fetchRecovery(for: Date()).score
            let sleep = try? await services.healthKit.fetchSleepAnalysis(for: Date()).totalHours
            let result = await MealOutcomeService.redistributeAfterSkip(
                target,
                service: MealRedistributionService(apiClient: services.apiClient),
                env: env,
                recoveryScore: recovery,
                sleepHours: sleep,
                strain: nil,
                dayType: "unknown"
            )
            if let result {
                skipRedistributionNote = "Your other meals were adjusted. \(result.reasoning)"
            }
        }
    }

    /// Prep / Eat / Finish on one lit track. The bar fills as the window
    /// passes; its colour follows the phase (amber when overdue).
    private func timelineTrack(now: Date, display: MealScheduleDisplay, phase: SchedulePhase) -> some View {
        FuelTimelineTrack(
            stops: timelinePoints(display: display).map { point in
                FuelTimelineTrack.Stop(
                    id: point.label,
                    label: point.label,
                    time: Self.clockFormatter.string(from: point.date),
                    isNext: point.id == phase.nextPointID
                )
            },
            progress: Double(markerProgress(now: now, display: display, phase: phase)),
            tone: trackColorFor(phase: phase)
        )
    }

    private func trackColorFor(phase: SchedulePhase) -> Color {
        switch phase {
        case .overdue: Tide.warn
        case .skipped: Tide.text3
        case .eaten: Tide.good
        default: mood.accent
        }
    }

    private func shiftChip(minutes: Int) -> some View {
        let sign = minutes > 0 ? "+" : "−"
        return Label("\(sign)\(formatDuration(minutes: abs(minutes))) wake shift", systemImage: "moon.zzz.fill")
            .font(Tide.caption)
            .foregroundStyle(Tide.water)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(Tide.water.opacity(0.12), in: Capsule())
            .accessibilityLabel("Schedule shifted by \(abs(minutes)) minutes due to wake time")
    }

    // MARK: - Schedule helpers

    private func timelinePoints(display: MealScheduleDisplay) -> [TimelinePoint] {
        [
            TimelinePoint(id: .prep, label: "Prep", date: display.prepStart),
            TimelinePoint(id: .eat, label: "Eat", date: display.mealTime),
            TimelinePoint(id: .finish, label: "Finish", date: display.eatFinish),
        ]
    }

    /// Returns 0…1 progress for the fill bar and "you are here" marker.
    /// Resolved phases (eaten/skipped/overdue) fill the bar fully so the
    /// track reads as complete and the now-marker is hidden by the
    /// overlay opacity check. In-window phases linearly interpolate.
    private func markerProgress(now: Date, display: MealScheduleDisplay, phase: SchedulePhase) -> CGFloat {
        switch phase {
        case .eaten,
             .skipped,
             .overdue:
            return 1.0
        case .beforePrep:
            return 0
        case .prepping,
             .eating:
            let total = display.eatFinish.timeIntervalSince(display.prepStart)
            guard total > 0 else {
                return 0
            }
            let elapsed = now.timeIntervalSince(display.prepStart)
            let clamped = max(0, min(elapsed, total))
            return CGFloat(clamped / total)
        }
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    // MARK: - Prep Checklist

    private var prepChecklistItems: [PrepChecklistItem] {
        guard let recipe = meal.recipe else {
            return []
        }
        return recipe.orderedIngredients
            .filter(\.requiresDefrostReminder)
            .map { ingredient in
                PrepChecklistItem(
                    id: ingredient.id,
                    title: ingredient.displayName,
                    detail: "Move from freezer \(ingredient.defrostLeadTimeHours) h before mealtime"
                )
            }
    }

    private var prepChecklistSection: some View {
        FuelSection(title: "Prep checklist") {
            ForEach(prepChecklistItems) { item in
                FuelCheckRow(
                    title: item.title,
                    detail: item.detail,
                    icon: "snowflake",
                    isOn: checkedPrepItems.contains(item.id)
                ) {
                    togglePrep(item.id)
                    HapticManager.lightImpact()
                }
            }
        }
    }

    private func inlineMetric(icon: String, text: String) -> some View {
        HStack(spacing: Tide.s1) {
            Image(systemName: icon)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
    }

    // MARK: - Ingredients

    private func ingredientsSection(recipe: Recipe) -> some View {
        let ingredients = recipe.orderedIngredients
        let groups = groupIngredients(ingredients)
        let collected = ingredients.filter(\.isCollected).count
        return FuelSection(title: "Ingredients", trailing: ingredients.isEmpty ? nil : "\(collected)/\(ingredients.count)") {
            if groups.isEmpty {
                Text("No ingredients listed.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                ForEach(groups, id: \.title) { group in
                    ingredientGroup(group)
                }
            }
        }
    }

    private func ingredientGroup(_ group: IngredientGroup) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Label(group.title, systemImage: group.icon)
                .tideLabel()
                .padding(.top, Tide.s1)

            ForEach(group.items) { ingredient in
                FuelCheckRow(
                    title: ingredient.displayName,
                    detail: ingredientSubtitle(ingredient),
                    isOn: ingredient.isCollected
                ) {
                    toggleIngredient(ingredient)
                    HapticManager.lightImpact()
                }
            }
        }
    }

    private func ingredientSubtitle(_ ingredient: RecipeIngredient) -> String? {
        var parts: [String] = []
        // 1. AI-provided household label wins when present.
        // 2. Otherwise fall back to a deterministic best-guess via
        //    FoodMacroDatabase.formatPortion — handles legacy recipes
        //    where displayQuantity was never populated. Falls all the
        //    way back to "Xg <food>" when the canonical name isn't in
        //    the portions table.
        // Countable foods (eggs, bananas) read as whole units ("5 eggs"),
        // overriding any gram-y AI label; non-countable foods keep the AI's
        // household label and fall back to grams. See bestPortionLabel.
        let portionLabel = FoodMacroDatabase.bestPortionLabel(
            food: ingredient.canonicalFoodName,
            grams: ingredient.quantityGrams,
            aiLabel: ingredient.displayQuantity
        )
        if !portionLabel.isEmpty {
            parts.append(portionLabel)
        }
        if let cal = ingredient.calories, cal > 0 {
            parts.append("\(Int(cal)) kcal")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Steps

    private func stepsSection(recipe: Recipe) -> some View {
        let steps = recipe.orderedSteps
        let done = steps.filter(\.isComplete).count
        return FuelSection(title: "Steps", trailing: steps.isEmpty ? nil : "\(done)/\(steps.count)") {
            if steps.isEmpty {
                Text("No steps were generated for this meal.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }
        }
    }

    private func stepRow(_ step: RecipeStep) -> some View {
        let checked = step.isComplete
        return Button {
            toggleStep(step)
            HapticManager.lightImpact()
        } label: {
            HStack(alignment: .top, spacing: Tide.s3) {
                FuelCheckMark(isOn: checked, number: step.orderIndex + 1)
                    .padding(.top, Tide.hair)

                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(step.instruction)
                        .font(Tide.body)
                        .foregroundStyle(checked ? Tide.text3 : Tide.text)
                        .strikethrough(checked, color: Tide.text3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let duration = step.durationMinutes, duration > 0 {
                        Label("\(duration) min", systemImage: "timer")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: Tide.hit, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    // MARK: - Fallback

    @ViewBuilder
    private var noRecipeFallback: some View {
        let foods = meal.foods
        if !foods.isEmpty {
            // Quick-log / NL-logged / preset-logged meals don't have a
            // generated Recipe but DO have a PlannedFood array. Render
            // them per-food with macros so the detail view actually
            // tells the user what they ate, not just a static
            // "regenerate" message. The hero above carries the totals.
            foodsListCard(foods: foods)
        } else {
            FuelSection(title: "Recipe") {
                Text("AI couldn't generate a recipe for this meal. Regenerate the weekly plan to retry.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
        }
    }

    /// Foods can be removed one by one from a log the user entered (an
    /// unplanned log or a replaced slot) once it is eaten.
    private var canRemoveFoods: Bool {
        meal.status == .eaten && (meal.isUnplannedLog || meal.replacedPlan != nil)
    }

    /// Removes one food from the log; removing the last one deletes the log.
    private func removeFood(at index: Int) {
        let env = outcomeEnv
        let target = meal
        if target.foods.count == 1, target.isUnplannedLog {
            undoEaten()
            return
        }
        runAction { try MealOutcomeService.removeFood(at: index, from: target, env: env) }
        HapticManager.lightImpact()
    }

    /// What was eaten, food by food, each with its share of the meal's
    /// calories as a quiet bar.
    private func foodsListCard(foods: [PlannedFood]) -> some View {
        let totalKcal = foods.reduce(0.0) { $0 + $1.calories }
        return FuelSection(title: "What you ate", trailing: "\(foods.count)") {
            ForEach(Array(foods.enumerated()), id: \.offset) { index, food in
                HStack(spacing: Tide.s2) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        let name = Text(food.name)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        let figures = HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                            if food.quantityGrams >= 1 {
                                Text("\(Int(food.quantityGrams))g")
                                    .font(Tide.caption).monospacedDigit()
                                    .foregroundStyle(Tide.text3)
                            }
                            Text("\(Int(food.calories)) kcal")
                                .font(Tide.bodyStrong).monospacedDigit()
                                .foregroundStyle(Tide.text)
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        // One line while it fits; at large text sizes the figures
                        // drop under the name so nothing is cut or hyphenated.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                                name
                                Spacer(minLength: Tide.s2)
                                figures
                            }
                            VStack(alignment: .leading, spacing: Tide.s1) {
                                name
                                figures
                            }
                        }
                        FuelShareBar(progress: totalKcal > 0 ? food.calories / totalKcal : 0)
                    }
                    if canRemoveFoods {
                        Button {
                            removeFood(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(Tide.headline)
                                .foregroundStyle(Tide.danger)
                                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(food.name) from this log")
                    }
                }
            }
        }
    }

    // MARK: - Shared row + label

    private func sectionLabel(_ text: String) -> some View {
        Text(text).tideLabel()
    }

    // MARK: - Mutation helpers

    private func toggleIngredient(_ ingredient: RecipeIngredient) {
        ingredient.isCollected.toggle()
        try? modelContext.save()
    }

    private func toggleStep(_ step: RecipeStep) {
        step.isComplete.toggle()
        try? modelContext.save()
    }

    private func togglePrep(_ id: UUID) {
        if checkedPrepItems.contains(id) {
            checkedPrepItems.remove(id)
        } else {
            checkedPrepItems.insert(id)
        }
    }

    // MARK: - Grouping helpers

    private func groupIngredients(_ ingredients: [RecipeIngredient]) -> [IngredientGroup] {
        var bucket: [PantryStorageLocation: [RecipeIngredient]] = [:]
        var ungrouped: [RecipeIngredient] = []
        for ingredient in ingredients {
            if let loc = ingredient.storageLocation {
                bucket[loc, default: []].append(ingredient)
            } else {
                ungrouped.append(ingredient)
            }
        }
        // Display order — fridge first, then freezer, cupboard, pantry, unknown last.
        let order: [PantryStorageLocation] = [.fridge, .freezer, .cupboard, .pantry]
        var groups: [IngredientGroup] = order.compactMap { loc in
            guard let items = bucket[loc], !items.isEmpty else {
                return nil
            }
            return IngredientGroup(title: loc.displayName, icon: loc.icon, items: items)
        }
        if !ungrouped.isEmpty {
            groups.append(IngredientGroup(title: "Other", icon: "questionmark.circle", items: ungrouped))
        }
        return groups
    }

    // MARK: - Helper types

    private struct PrepChecklistItem: Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    private struct IngredientGroup {
        let title: String
        let icon: String
        let items: [RecipeIngredient]
    }

    // MARK: - Formatters

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    // MARK: - Schedule nested types

    /// Phases the schedule block surfaces. Honors `meal.status` — the
    /// previous version only looked at the clock and so labelled a
    /// still-planned meal "Done" once the eat-finish time passed. Now:
    ///   - `.eaten` / `.skipped` short-circuit any clock-based phase,
    ///     because the user resolved the meal explicitly.
    ///   - `.overdue` is the unresolved case: clock past eatFinish AND
    ///     status still `.planned`. Drives the amber track + inline
    ///     Eat/Skip buttons.
    private enum SchedulePhase: Equatable {
        case beforePrep
        case prepping
        case eating
        case overdue
        case eaten(at: Date?)
        case skipped

        /// Which timeline node should be visually emphasised as "next up."
        /// Eaten/skipped/overdue all collapse onto Finish — the rest of the
        /// track is past.
        var nextPointID: TimelinePointID {
            switch self {
            case .beforePrep: .prep
            case .prepping: .eat
            case .eating,
                 .overdue,
                 .eaten,
                 .skipped: .finish
            }
        }

        var isResolved: Bool {
            switch self {
            case .eaten,
                 .skipped: true
            default: false
            }
        }

        init(meal: PlannedMeal, now: Date, display: MealScheduleDisplay) {
            switch meal.status {
            case .eaten:
                self = .eaten(at: meal.actualEatenAt)
                return
            case .skipped:
                self = .skipped
                return
            default:
                break
            }
            if now < display.prepStart {
                self = .beforePrep
            } else if now < display.mealTime {
                self = .prepping
            } else if now < display.eatFinish {
                self = .eating
            } else {
                self = .overdue
            }
        }
    }

    private enum TimelinePointID: Hashable {
        case prep
        case eat
        case finish
    }

    private struct TimelinePoint: Identifiable {
        let id: TimelinePointID
        let label: String
        let date: Date
    }
}
