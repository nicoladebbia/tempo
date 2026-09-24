//
// ContentView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Combine
import Inject
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
        #if DEBUG
            print("[Settings] deduped UserSettings: \(all.count) rows → 1")
        #endif
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
    }

    /// Regenerates the active meal plan when its inputs fingerprint no longer
    /// matches (no-op when nothing the plan depends on changed, when there's
    /// no plan, or when a generation is already running).
    private func handlePlanInputsChanged() {
        nutritionViewModel.regenerateIfOutOfDate(
            modelContext: modelContext,
            whoop: services.whoop,
            apiClient: services.apiClient,
            notifications: services.notifications,
            trainingEngine: services.trainingEngine,
            healthKit: services.healthKit
        )
    }
}
