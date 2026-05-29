//
// ContentView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

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
    // Hot reload (dev only, no-op in Release). Edit a SwiftUI view body and
    // save → InjectionIII pushes it into the running sim in ~1s, no rebuild.
    @ObserveInjection var inject

    var body: some View {
        Group {
            if services.appState.isOnboardingComplete {
                mainTabView
                    .task { ensureUserProfile() }
            } else {
                OnboardingContainerView()
            }
        }
        .preferredColorScheme(.dark)
        .enableInjection()
    }

    /// Creates a UserProfile from onboarding data if one doesn't exist yet.
    private func ensureUserProfile() {
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
            modelContext.insert(settings)
        }

        try? modelContext.save()
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

            NutritionTabView()
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
        .tint(Color.tempoSignal)
        .toolbarBackground(.hidden, for: .tabBar)
        .onChange(of: appState.activeTab) { _, _ in
            HapticManager.selection()
        }
    }
}
