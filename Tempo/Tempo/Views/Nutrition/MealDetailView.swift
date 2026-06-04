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

    @Environment(\.dismiss)
    private var dismiss
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

    /// Drives the "Undo — not eaten" confirmation dialog in the `.eaten`
    /// status branch.
    @State
    private var presentUndoConfirm: Bool = false
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                header
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
                    macrosSummarySection(recipe: recipe)
                    ingredientsSection(recipe: recipe)
                    stepsSection(recipe: recipe)
                } else {
                    noRecipeFallback
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(meal.mealName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadWakeSignal() }
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
                .presentationDetents([.height(280)])
        }
        .confirmationDialog(
            "Undo this meal?",
            isPresented: $presentUndoConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark as not eaten", role: .destructive) {
                undoEaten()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This puts \(meal.mealName) back to planned and removes it from today's totals. Any pantry stock it used is added back.")
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
                set: { if !$0 { substituteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { substituteError = nil }
        } message: {
            Text(substituteError ?? "Try describing what you ate a bit differently.")
        }
    }

    /// Blocking spinner shown while the substitute note is parsed. The sheet
    /// is already gone, so this is the only feedback the user gets that work
    /// is happening — keep it on top of the scroll content.
    private var substituteResolvingOverlay: some View {
        ZStack {
            Color.tempoBgPrimary.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: TempoSpacing.md) {
                ProgressView()
                    .tint(Color.tempoSignal)
                Text("Logging what you ate…")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    // MARK: - Eat-time editor

    /// Minimal time-only DatePicker sheet for fixing the recorded
    /// `actualEatenAt` after the fact. Saves to PlannedMeal AND, when a
    /// linked MealLog exists, updates that row's `loggedAt` too so the
    /// Fuel "last meal" line and Coach context stay coherent.
    private var eatTimeEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Text("Set the time you actually ate \(meal.mealName.lowercased()).")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
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
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Color.tempoTextInverse)
                        .background(Color.tempoSignal)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.md)
            .background(Color.tempoBgPrimary)
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
        guard let normalized = cal.date(from: components) else { return }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(meal.mealName)
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
            if let recipe = meal.recipe, let description = recipe.recipeDescription {
                Text(description)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Schedule

    // Single timeline block. Drives every displayed time off the
    // Whoop/HealthKit-aware annotator, so wake-time shifts surface here just
    // like they do in the Fuel day list. AI-redistribution and
    // eating-time shifts are already persisted to `scheduledTime`, so
    // they ride along for free.

    private var scheduleSection: some View {
        let display = scheduleDisplay
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("SCHEDULE")
                Spacer()
                if display.hasShift {
                    shiftChip(minutes: display.shiftMinutes)
                }
            }

            TimelineView(.everyMinute) { context in
                let now = context.date
                let phase = SchedulePhase(meal: meal, now: now, display: display)
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    statusLine(phase: phase, now: now, display: display)
                    // The Prep / Eat / Finish ladder describes future
                    // steps — for an already-eaten or skipped meal those
                    // chips are stale noise. Status line above already
                    // shows "Eaten at HH:mm" or "Skipped".
                    if !phase.isResolved {
                        timelineTrack(now: now, display: display, phase: phase)
                    }
                    // Action row (Mark Eaten / Skip / Ate something else) for
                    // ANY not-yet-resolved meal — not just overdue. Lets you
                    // record what you ate (or a swap) even before the meal's
                    // scheduled time, e.g. you ate breakfast early.
                    if !phase.isResolved {
                        mealActions
                    }
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
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
                .font(.tempoBody)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        case .prepping:
            Text("Prep now — eat at \(Self.clockFormatter.string(from: display.mealTime)).")
                .font(.tempoBody)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoSignal)
        case .eating:
            let minutes = max(0, Int(display.eatFinish.timeIntervalSince(now) / 60))
            Text("Eat now — \(formatDuration(minutes: minutes)) left.")
                .font(.tempoBody)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoSuccess)
        case .overdue:
            let minutes = max(1, Int(now.timeIntervalSince(display.eatFinish) / 60))
            Text("Past \(Self.clockFormatter.string(from: display.eatFinish)) — did you eat it? (\(formatDuration(minutes: minutes)) overdue)")
                .font(.tempoBody)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoAmber)
        case let .eaten(at):
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(spacing: TempoSpacing.sm) {
                    if let at {
                        Text("Eaten at \(Self.clockFormatter.string(from: at)).")
                            .font(.tempoBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoSuccess)
                    } else {
                        Text("Eaten.")
                            .font(.tempoBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoSuccess)
                    }
                    Spacer(minLength: 0)
                    Button {
                        eatTimeEdit = at ?? Date()
                        presentEatTimeEditor = true
                        HapticManager.lightImpact()
                    } label: {
                        Label("Edit time", systemImage: "clock.arrow.circlepath")
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoSignal)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit eat time")
                }
                // Correct what was eaten after the fact — re-opens the swap
                // sheet so "actually I ate something else" works even once the
                // meal is already marked eaten. commitMarkEaten re-records it.
                Button {
                    resolveAsSubstitute()
                } label: {
                    Label("Change what I ate", systemImage: "arrow.triangle.swap")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change what I ate")

                // Undo — take the meal back to planned so a wrong log (e.g.
                // logged to the wrong slot) can be fixed. Confirmed because it
                // clears the eaten state, deletes feedback, and re-credits any
                // pantry stock this meal pulled.
                Button(role: .destructive) {
                    presentUndoConfirm = true
                    HapticManager.lightImpact()
                } label: {
                    Label("Undo — not eaten", systemImage: "arrow.uturn.backward")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoError)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo, mark as not eaten")
            }
        case .skipped:
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("Skipped — macros redistributed.")
                    .font(.tempoBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextSecondary)
                // Un-skip: put the meal back to planned so it counts again.
                // A skipped meal never decremented the pantry or stored
                // feedback, so undoMealEaten reverses it cleanly (status →
                // planned). No confirmation needed — nothing to lose.
                Button {
                    NutritionTabViewModel().undoMealEaten(meal, modelContext: modelContext)
                    HapticManager.lightImpact()
                } label: {
                    Label("Undo skip — back to planned", systemImage: "arrow.uturn.backward")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoSignal)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo skip, back to planned")
            }
        }
    }

    /// Inline Eat / Skip buttons shown only in the `.overdue` phase. Both
    /// write directly to SwiftData here — the richer redistribution +
    /// shift flow happens upstream when actions originate from the day
    /// list. From this screen we do the minimum honest thing: record the
    /// status, cancel pending notifications, save.
    private var mealActions: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Button {
                    resolveAsEaten()
                } label: {
                    Label("Mark Eaten", systemImage: "checkmark.circle.fill")
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.tempoSuccess.opacity(0.18))
                        .foregroundStyle(Color.tempoSuccess)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    resolveAsSkipped()
                } label: {
                    Label("Skip", systemImage: "xmark.circle.fill")
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.tempoError.opacity(0.15))
                        .foregroundStyle(Color.tempoError)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            // "Ate something else" — surfaces the substitute lane directly
            // instead of burying it inside the Mark-Eaten sheet. Opens the
            // same sheet pre-expanded to the swap section.
            Button {
                resolveAsSubstitute()
            } label: {
                Label("Ate something else", systemImage: "arrow.triangle.swap")
                    .font(.tempoCallout)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.tempoSurfaceCard)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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

    /// Revert this meal to planned (the user logged it wrong — e.g. an açai
    /// bowl marked under Breakfast instead of Snack). Routes through the
    /// single `NutritionTabViewModel.undoMealEaten` implementation (status
    /// reset, feedback deletion, guarded pantry re-credit, sync notification)
    /// so the logic lives in ONE place. Operates on the shared SwiftData
    /// context, so the meal object flips to .planned everywhere it's
    /// observed; we then dismiss back to the list.
    private func undoEaten() {
        NutritionTabViewModel().undoMealEaten(meal, modelContext: modelContext)
        dismiss()
    }

    /// Sheet's onCommit handler. Writes the chosen eat time, feel, and
    /// substitute (if any), cancels pending notifications, saves.
    /// When a substitute is present the planned macros are zeroed so the
    /// day's totals stop counting a meal the user didn't eat.
    private func commitMarkEaten(
        at eatTime: Date,
        feel: MealFeel?,
        satiety: MealSatiety?,
        substitute: MarkEatenSheet.Substitute?
    ) {
        guard let substitute else {
            // Plain "ate the planned meal" — synchronous. Decrement once.
            recordEaten(at: eatTime, feel: feel, satiety: satiety)
            if !meal.didDecrementPantry {
                PantryDecrementService.decrement(for: meal, modelContext: modelContext)
                meal.didDecrementPantry = true
                try? modelContext.save()
            }
            HapticManager.notification(.success)
            return
        }
        // Substitute lane: parse "what did you eat" into real foods + DB macros
        // via the NL pipeline, then REPLACE the meal's foods/macros so the
        // detail screen shows what was actually eaten (not the old recipe, not
        // zeros). One Haiku call. Eat time defaults to now (no scrubber here).
        Task { await resolveSubstitute(note: substitute.note, usedPantry: substitute.usedPantry, feel: feel, satiety: satiety) }
    }

    /// Shared eaten-status write (status + time + notifications + feedback).
    @MainActor
    private func recordEaten(at eatTime: Date, feel: MealFeel?, satiety: MealSatiety? = nil, substituteNote: String? = nil) {
        meal.status = .eaten
        meal.actualEatenAt = eatTime
        try? modelContext.save()
        services.notifications.cancelDefrostReminders(forMealID: meal.id)
        services.notifications.cancelPrepStartReminder(forMealID: meal.id)
        services.notifications.cancelOverdueMealReminder(forMealID: meal.id)
        if feel != nil || satiety != nil || substituteNote != nil {
            let feedback = MealFeedback(
                plannedMeal: meal,
                mealFeel: feel,
                satiety: satiety,
                substituteNote: substituteNote,
                substituteCalories: nil
            )
            modelContext.insert(feedback)
            try? modelContext.save()
        }
    }

    @MainActor
    private func resolveSubstitute(note: String, usedPantry: Bool, feel: MealFeel?, satiety: MealSatiety?) async {
        if nlService == nil {
            nlService = NaturalLanguageLoggingService(apiClient: services.apiClient)
        }
        guard let nlService else { return }
        isResolvingSubstitute = true
        defer { isResolvingSubstitute = false }
        do {
            let items = try await nlService.parseNaturalLanguage(note)
            guard !items.isEmpty else {
                substituteError = "Couldn't recognize any food in \"\(note)\". Edit and try again."
                return
            }
            // Replace the meal's foods + macros with what was actually eaten.
            // Day/Fuel totals sum PlannedMeal.totalCalories (NOT MealLog), so we
            // set them directly and create NO MealLog (would double-count).
            meal.foods = items.map {
                PlannedFood(
                    name: $0.name,
                    quantityGrams: $0.quantityGrams,
                    calories: $0.calories,
                    proteinG: $0.proteinG,
                    carbsG: $0.carbsG,
                    fatG: $0.fatG
                )
            }
            meal.totalCalories = items.reduce(0) { $0 + $1.calories }
            meal.totalProtein = items.reduce(0) { $0 + $1.proteinG }
            meal.totalCarbs = items.reduce(0) { $0 + $1.carbsG }
            meal.totalFat = items.reduce(0) { $0 + $1.fatG }
            // Clear the planned recipe so the detail view renders the actual
            // foods (noRecipeFallback) instead of the original dish.
            meal.recipe = nil
            recordEaten(at: .now, feel: feel, satiety: satiety, substituteNote: note)
            // Decrement the pantry ONLY if the user said they used their own
            // stock, and only once per meal (guard against re-edit
            // double-subtract). "Ate out" / unknown leaves the pantry alone.
            if usedPantry, !meal.didDecrementPantry {
                let foods = meal.foods
                _ = PantryDecrementService.decrement(
                    foods: foods, label: meal.mealName, modelContext: modelContext
                )
                meal.didDecrementPantry = true
                try? modelContext.save()
            }
            HapticManager.notification(.success)
        } catch {
            substituteError = "Couldn't read that: \(error.localizedDescription). Your note is kept — try again."
        }
    }

    private func resolveAsSkipped() {
        meal.status = .skipped
        try? modelContext.save()
        services.notifications.cancelDefrostReminders(forMealID: meal.id)
        services.notifications.cancelPrepStartReminder(forMealID: meal.id)
        services.notifications.cancelOverdueMealReminder(forMealID: meal.id)
        HapticManager.lightImpact()
    }

    /// Horizontal track laid out via HStack so end-node labels can't clip
    /// off-screen. Prep / Eat / Finish anchor to leading / centre /
    /// trailing of the container. The progress fill grows from leading
    /// using `GeometryReader` for the width only — never for absolute
    /// node positioning. Track colour adapts to phase: amber when
    /// overdue, dimmed when resolved.
    private func timelineTrack(now: Date, display: MealScheduleDisplay, phase: SchedulePhase) -> some View {
        let progress = markerProgress(now: now, display: display, phase: phase)
        let trackColor = trackColorFor(phase: phase)
        return VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.tempoBorder)
                    .frame(height: 4)
                GeometryReader { geo in
                    Capsule()
                        .fill(trackColor)
                        .frame(width: geo.size.width * progress, height: 4)
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(Color.tempoTextPrimary)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.tempoSurfaceCard, lineWidth: 3))
                                .offset(x: 6)
                                .opacity(progress > 0 && progress < 1 ? 1 : 0)
                        }
                }
                .frame(height: 12)

                HStack(spacing: 0) {
                    ForEach(timelinePoints(display: display)) { point in
                        timelineNode(point: point, phase: phase)
                            .frame(maxWidth: .infinity, alignment: alignmentFor(point: point))
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 0) {
                ForEach(timelinePoints(display: display)) { point in
                    timelineNodeLabel(point: point, phase: phase)
                        .frame(maxWidth: .infinity, alignment: alignmentFor(point: point))
                }
            }
        }
        .padding(.top, TempoSpacing.xs)
    }

    private func timelineNode(point: TimelinePoint, phase: SchedulePhase) -> some View {
        let isNext = point.id == phase.nextPointID
        let size: CGFloat = isNext ? 14 : 10
        let dotColor: Color = {
            if case .overdue = phase, point.id == .finish { return Color.tempoAmber }
            return isNext ? Color.tempoSignal : Color.tempoTextTertiary
        }()
        return Circle()
            .fill(dotColor)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.tempoSurfaceCard, lineWidth: 2))
    }

    private func timelineNodeLabel(point: TimelinePoint, phase: SchedulePhase) -> some View {
        let isNext = point.id == phase.nextPointID
        return VStack(spacing: 1) {
            Text(point.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(isNext ? Color.tempoTextPrimary : Color.tempoTextTertiary)
            Text(Self.clockFormatter.string(from: point.date))
                .font(isNext ? .tempoCallout : .tempoCaption2)
                .fontWeight(isNext ? .semibold : .medium)
                .foregroundStyle(isNext ? Color.tempoTextPrimary : Color.tempoTextSecondary)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func alignmentFor(point: TimelinePoint) -> Alignment {
        switch point.id {
        case .prep: .leading
        case .eat: .center
        case .finish: .trailing
        }
    }

    private func trackColorFor(phase: SchedulePhase) -> Color {
        switch phase {
        case .overdue: Color.tempoAmber
        case .skipped: Color.tempoTextTertiary
        case .eaten: Color.tempoSuccess
        default: Color.tempoSignal
        }
    }

    private func shiftChip(minutes: Int) -> some View {
        let sign = minutes > 0 ? "+" : "−"
        return HStack(spacing: 4) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("\(sign)\(formatDuration(minutes: abs(minutes))) wake shift")
                .font(.tempoCaption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.tempoElectric)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 4)
        .background(Color.tempoElectric.opacity(0.12))
        .clipShape(Capsule())
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
        case .eaten, .skipped, .overdue:
            return 1.0
        case .beforePrep:
            return 0
        case .prepping, .eating:
            let total = display.eatFinish.timeIntervalSince(display.prepStart)
            guard total > 0 else { return 0 }
            let elapsed = now.timeIntervalSince(display.prepStart)
            let clamped = max(0, min(elapsed, total))
            return CGFloat(clamped / total)
        }
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("PREP CHECKLIST")
            ForEach(prepChecklistItems) { item in
                checklistRow(
                    id: item.id,
                    title: item.title,
                    subtitle: item.detail,
                    iconName: "snowflake",
                    isChecked: checkedPrepItems.contains(item.id),
                    toggle: { togglePrep(item.id) }
                )
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Macros

    private func macrosSummarySection(recipe: Recipe) -> some View {
        let totalMinutes = recipe.totalMinutes
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("MACROS PER SERVING")
            HStack(spacing: TempoSpacing.md) {
                macroPill(label: "CAL", value: "\(Int(recipe.totalCalories))")
                macroPill(label: "P", value: "\(Int(recipe.totalProteinGrams))g")
                macroPill(label: "C", value: "\(Int(recipe.totalCarbsGrams))g")
                macroPill(label: "F", value: "\(Int(recipe.totalFatGrams))g")
            }
            HStack(spacing: TempoSpacing.md) {
                inlineMetric(icon: "clock", text: "\(totalMinutes) min")
                inlineMetric(icon: "person.2", text: "\(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")")
                inlineMetric(icon: "flame", text: recipe.difficulty.rawValue.capitalized)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(value)
                .font(.tempoCallout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineMetric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.tempoTextTertiary)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Ingredients

    private func ingredientsSection(recipe: Recipe) -> some View {
        let groups = groupIngredients(recipe.orderedIngredients)
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("INGREDIENTS")
            if groups.isEmpty {
                Text("No ingredients listed.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(groups, id: \.title) { group in
                    ingredientGroup(group)
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func ingredientGroup(_ group: IngredientGroup) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: group.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.top, 4)

            ForEach(group.items) { ingredient in
                checklistRow(
                    id: ingredient.id,
                    title: ingredient.displayName,
                    subtitle: ingredientSubtitle(ingredient),
                    iconName: nil,
                    isChecked: ingredient.isCollected,
                    toggle: { toggleIngredient(ingredient) }
                )
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("STEPS")
            if recipe.orderedSteps.isEmpty {
                Text("No steps were generated for this meal.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(recipe.orderedSteps) { step in
                    stepRow(step)
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func stepRow(_ step: RecipeStep) -> some View {
        let checked = step.isComplete
        return Button {
            toggleStep(step)
            HapticManager.lightImpact()
        } label: {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.tempoSuccess)
                    } else {
                        Text("\(step.orderIndex + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.instruction)
                        .font(.tempoBody)
                        .foregroundStyle(checked ? Color.tempoTextTertiary : Color.tempoTextPrimary)
                        .strikethrough(checked, color: Color.tempoTextTertiary)
                        .multilineTextAlignment(.leading)
                    if let duration = step.durationMinutes, duration > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                            Text("\(duration) min")
                                .font(.tempoCaption2)
                        }
                        .foregroundStyle(Color.tempoTextTertiary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
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
            // "regenerate" message.
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                foodsTotalsCard(foods: foods)
                foodsListCard(foods: foods)
            }
        } else {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                sectionLabel("RECIPE")
                Text("AI couldn't generate a recipe for this meal. Regenerate the weekly plan to retry.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(TempoSpacing.buttonPaddingV)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    /// Summary card: total calories + P/C/F across the foods array.
    /// Mirrors recipe `macrosSummarySection` shape so a user can't tell
    /// they're on the no-recipe path unless they look.
    private func foodsTotalsCard(foods: [PlannedFood]) -> some View {
        let totalKcal = foods.reduce(0.0) { $0 + $1.calories }
        let totalP = foods.reduce(0.0) { $0 + $1.proteinG }
        let totalC = foods.reduce(0.0) { $0 + $1.carbsG }
        let totalF = foods.reduce(0.0) { $0 + $1.fatG }
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("TOTALS")
            HStack(spacing: TempoSpacing.md) {
                Text("\(Int(totalKcal)) kcal")
                    .font(.tempoTitle3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoViolet)
                Spacer()
                macroBadge("P", value: Int(totalP), color: Color.tempoMacroProtein)
                macroBadge("C", value: Int(totalC), color: Color.tempoMacroCarbs)
                macroBadge("F", value: Int(totalF), color: Color.tempoMacroFat)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func foodsListCard(foods: [PlannedFood]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("WHAT YOU ATE")
            ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                HStack(spacing: TempoSpacing.sm) {
                    Circle()
                        .fill(Color.tempoViolet.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(food.name)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text("\(Int(food.quantityGrams))g")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("\(Int(food.calories)) kcal")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroBadge(_ label: String, value: Int, color: Color) -> some View {
        Text("\(label): \(value)g")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Shared row + label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoModuleTag)
            .tracking(TempoTracking.drillLabel)
            .foregroundStyle(Color.tempoTextSecondary)
    }

    private func checklistRow(
        id _: UUID,
        title: String,
        subtitle: String?,
        iconName: String?,
        isChecked: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: {
            toggle()
            HapticManager.lightImpact()
        }) {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isChecked ? Color.tempoSuccess : Color.tempoTextTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let iconName {
                            Image(systemName: iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.tempoElectric)
                        }
                        Text(title)
                            .font(.tempoBody)
                            .foregroundStyle(isChecked ? Color.tempoTextTertiary : Color.tempoTextPrimary)
                            .strikethrough(isChecked, color: Color.tempoTextTertiary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
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
            case .eating, .overdue, .eaten, .skipped: .finish
            }
        }

        var isResolved: Bool {
            switch self {
            case .eaten, .skipped: true
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
            if now < display.prepStart { self = .beforePrep }
            else if now < display.mealTime { self = .prepping }
            else if now < display.eatFinish { self = .eating }
            else { self = .overdue }
        }
    }

    private enum TimelinePointID: Hashable {
        case prep, eat, finish
    }

    private struct TimelinePoint: Identifiable {
        let id: TimelinePointID
        let label: String
        let date: Date
    }
}
