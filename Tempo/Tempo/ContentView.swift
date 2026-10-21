//
// ContentView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Combine
import Inject
import os
import SwiftData
import SwiftUI

// MARK: - Content View

// Per BUILD_PLAN step 3.10 — 5-tab TabView wired to AppState.activeTab.
// Conditionally shows onboarding if !isOnboardingComplete.

struct ContentView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    /// Hot reload (dev only, no-op in Release). Edit a SwiftUI view body and
    /// save → InjectionIII pushes it into the running sim in ~1s, no rebuild.
    @ObserveInjection var inject

    /// Drives the app-wide accent tint. Observing the AppStorage key here (not
    /// reading Color.tempoAccent statically) is what makes the Appearance
    /// accent picker actually re-tint the app live when the choice changes.
    @AppStorage("accentColorChoice")
    private var accentColorChoice: String = "signal_red"

    /// The Nutrition tab's view model, owned here so plan-input changes are
    /// handled even when the Nutrition tab was never opened (see
    /// `handlePlanInputsChanged`).
    @State
    private var nutritionViewModel = NutritionTabViewModel()
    @Environment(\.scenePhase)
    private var scenePhase

    private var accentColor: Color {
        switch accentColorChoice {
        case "electric_blue": .tempoElectric
        case "success_green": .tempoSuccess
        default: .tempoSignal
        }
    }

    var body: some View {
        Group {
            if services.appState.isOnboardingComplete {
                mainTabView
                    .task {
                        ensureUserProfile()
                        // One-time clear-skin opt-in migration, at launch so it
                        // sees an existing install's plan before any regen.
                        _ = ClearSkinFocusSetting.resolve(modelContext: modelContext)
                        handlePlanInputsChanged()
                        rescheduleTrainerSessionReminders()
                        rescheduleSupplementReminders()
                        rescheduleMealReminders()
                        await WeeklyPlanReminder.sync(settings: NutritionTabViewModel.loadUserSettings(modelContext: modelContext))
                        await syncWeeklyPlan()
                        #if DEBUG && targetEnvironment(simulator)
                            // `sim.sh qa --local`: a wiped app was never asked
                            // for notifications, and simctl can't grant them —
                            // ask now (sim.sh taps Allow) so test pushes land.
                            if TestServer.baseURLOverride != nil {
                                _ = try? await services.notifications.requestAuthorization()
                            }
                        #endif
                        #if DEBUG
                            await ScenarioSeed.afterLaunch(modelContext: modelContext, deps: PlanDeps(services))
                        #endif
                    }
            } else {
                OnboardingContainerView()
            }
        }
        .preferredColorScheme(.dark)
        .enableInjection()
    }

    /// Creates a UserProfile from onboarding data if one doesn't exist yet.
    private func ensureUserProfile() {
        // Runs every launch (cheap when there's nothing to heal).
        dedupeUserSettings()
        let descriptor = FetchDescriptor<UserProfile>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else {
            return
        }

        // Read onboarding data from UserDefaults (persisted during onboarding)
        let data = UserDefaults.standard.dictionary(forKey: "tempo.onboarding.data")
        let name = data?["displayName"] as? String ?? "Athlete"
        let user = data?["username"] as? String ?? "athlete"
        let identity = data?["identityLabel"] as? String ?? "Athlete"

        let profile = UserProfile(
            appleID: "local",
            username: user,
            displayName: name,
            identityLabel: identity
        )
        modelContext.insert(profile)

        // Also ensure UserSettings exists
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        if (try? modelContext.fetchCount(settingsDescriptor)) == 0 {
            let settings = UserSettings()
            settings.userProfile = profile
            // Seed durable experience level from onboarding BEFORE the blob is
            // deleted at completion — otherwise the cold-start estimator reads
            // nil forever and treats every user as a beginner.
            if let raw = data?["experienceLevel"] as? String, !raw.isEmpty {
                settings.experienceLevelRaw = raw
            }
            // Requirement (a): rescue the user's chosen split too — it was captured
            // at onboarding then discarded, so every new user silently got PPL. An
            // explicit pick wins; "I Don't Know" falls back to a days/week inference.
            if let label = data?["preferredSplit"] as? String,
               let split = TrainingSplit.fromOnboardingLabel(label)
            {
                settings.trainingSplit = split
            } else if let days = data?["daysPerWeek"] as? Int {
                settings.trainingSplit = TrainingSplit.forDaysPerWeek(days)
            }
            modelContext.insert(settings)
        }

        try? modelContext.save()
    }

    /// Self-healing: collapse duplicate UserSettings rows into one canonical
    /// row. Three creation sites exist (onboarding, AI-meals settings, coach
    /// interview) and every reader does an UNSORTED `.first` — with two rows,
    /// two screens can each pick a different one (the Settings page showed
    /// football days while the schedule editor showed none). Union the
    /// football bitmask, prefer configured values over defaults, delete extras.
    private func dedupeUserSettings() {
        let all = (try? modelContext.fetch(FetchDescriptor<UserSettings>())) ?? []
        guard all.count > 1 else {
            return
        }
        let survivor = all.first { $0.userProfile != nil }
            ?? all.max { $0.footballDaysRaw.nonzeroBitCount < $1.footballDaysRaw.nonzeroBitCount }
            ?? all[0]
        for dupe in all where dupe !== survivor {
            survivor.footballDaysRaw |= dupe.footballDaysRaw
            if survivor.trainingSplitRaw == TrainingSplit.pushPullLegs.rawValue,
               dupe.trainingSplitRaw != TrainingSplit.pushPullLegs.rawValue
            {
                survivor.trainingSplitRaw = dupe.trainingSplitRaw
            }
            if survivor.experienceLevelRaw == nil {
                survivor.experienceLevelRaw = dupe.experienceLevelRaw
            }
            if survivor.userProfile == nil {
                survivor.userProfile = dupe.userProfile
            }
            modelContext.delete(dupe)
        }
        try? modelContext.save()
        Logger.sync.info("[Settings] deduped UserSettings: \(all.count) rows → 1")
    }

    private var mainTabView: some View {
        @Bindable
        var appState = services.appState
        return TabView(selection: $appState.activeTab) {
            DashboardView()
                .tabItem {
                    Label(Tab.dashboard.title, systemImage: Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)

            RecoveryTabView()
                .tabItem {
                    Label(Tab.recovery.title, systemImage: Tab.recovery.icon)
                }
                .tag(Tab.recovery)

            TrainingTabView()
                .tabItem {
                    Label(Tab.training.title, systemImage: Tab.training.icon)
                }
                .tag(Tab.training)

            NutritionTabView(viewModel: nutritionViewModel)
                .tabItem {
                    Label(Tab.nutrition.title, systemImage: Tab.nutrition.icon)
                }
                .tag(Tab.nutrition)

            LockdownTabView()
                .tabItem {
                    Label(Tab.lockdown.title, systemImage: Tab.lockdown.icon)
                }
                .tag(Tab.lockdown)
        }
        .tint(accentColor)
        .toolbarBackground(.hidden, for: .tabBar)
        .onChange(of: appState.activeTab) { _, _ in
            HapticManager.selection()
        }
        // Sunday loop: pick up a server-built plan whenever the app comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await syncWeeklyPlan() }
                // Foreground is one of the required reschedule triggers per
                // the supplement timing engine — doses drift with the clock
                // (a "pre-training" dose from yesterday shouldn't still be
                // pending), so the rolling today+tomorrow window rebuilds
                // every time the app comes back.
                rescheduleSupplementReminders()
                rescheduleMealReminders()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWeeklyPlanApplied)) { _ in
            nutritionViewModel.adoptActivePlan(modelContext: modelContext, notifications: services.notifications)
        }
        .sheet(isPresented: $appState.weeklyCheckInRequested) {
            WeeklyCheckInView()
        }
        // A meal notification opens that meal; pre-meal reminders follow the plan.
        .mealNotificationHooks(request: $appState.requestedMeal) {
            rescheduleMealReminders()
        }
        // Training settings (split / football days / trainer program) and
        // diet-profile edits can happen from Training, Dashboard Settings or
        // Nutrition. Handle them here, app-wide, so the meal plan follows even
        // if the Nutrition tab was never opened. Debounced because each chip
        // toggle posts and a user can flip several in a row — one regen at
        // the end of the burst, not N.
        .onReceive(
            NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)
                .merge(with: NotificationCenter.default.publisher(for: .tempoDietaryProfileChanged))
                .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
        ) { _ in
            handlePlanInputsChanged()
        }
        // Fix #12 — trainer-session reminders follow the same real week the
        // Training tab shows: a program edit, a settings toggle, or a logged
        // workout can all change which of the next 7 days actually run a
        // session (recovery/match pauses included). Debounced for the same
        // reason as the nutrition regen above — `.tempoWorkoutChanged` in
        // particular can fire several times in a row (each set logged).
        .onReceive(
            NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)
                .merge(with: NotificationCenter.default.publisher(for: .tempoWorkoutChanged))
                .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
        ) { _ in
            rescheduleTrainerSessionReminders()
        }
        // Supplement reminders follow the shelf, per-supplement overrides, the
        // active plan's take/skip + timing decisions, and the training
        // schedule they anchor to — any of those changing can move today's
        // doses. `.tempoSupplementsChanged` is posted by the shelf-editing
        // views and by a "taken" toggle; the other two cover a fresh plan and
        // a routine/training edit.
        .onReceive(
            NotificationCenter.default.publisher(for: .tempoSupplementsChanged)
                .merge(with: NotificationCenter.default.publisher(for: .tempoWeeklyPlanApplied))
                .merge(with: NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged))
                .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
        ) { _ in
            rescheduleSupplementReminders()
        }
    }

    /// Rebuilds today+tomorrow's supplement reminders. See
    /// `SupplementReminderScheduler`.
    private func rescheduleSupplementReminders() {
        SupplementReminderScheduler.reschedule(notifications: services.notifications, modelContext: modelContext)
    }

    /// Rebuilds the pre-meal reminders. See `MealReminderPlanner`.
    private func rescheduleMealReminders() {
        MealReminderPlanner.reschedule(modelContext: modelContext, notifications: services.notifications)
    }

    private func syncWeeklyPlan() async {
        await WeeklyPlanService.shared.sync(modelContext: modelContext, deps: PlanDeps(services))
    }

    /// Rebuilds the rolling 7-day window of trainer-session reminders. See
    /// `TrainerSessionReminderScheduler`.
    private func rescheduleTrainerSessionReminders() {
        TrainerSessionReminderScheduler.reschedule(
            notifications: services.notifications,
            trainingEngine: services.trainingEngine,
            whoop: services.whoop,
            healthKit: services.healthKit,
            modelContext: modelContext
        )
        // Weekly-upload feature — same hooks/debounce as the trainer-session
        // reminders above.
        WeeklyUploadReminderScheduler.reschedule(
            notifications: services.notifications,
            trainingEngine: services.trainingEngine,
            whoop: services.whoop,
            healthKit: services.healthKit,
            modelContext: modelContext
        )
    }

    /// Flags the active meal plan as out of date when its inputs fingerprint
    /// no longer matches. Never rebuilds it: Today shows an "update the rest
    /// of the week?" banner and the user decides.
    private func handlePlanInputsChanged() {
        nutritionViewModel.checkPlanFreshness(modelContext: modelContext)
    }
}
