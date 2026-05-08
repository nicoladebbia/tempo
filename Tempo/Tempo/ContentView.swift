//
// ContentView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

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

        let profile = UserProfile(
            appleID: "local",
            username: user,
            displayName: name
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
                    Image(systemName: Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)

            RecoveryTabView()
                .tabItem {
                    Image(systemName: Tab.recovery.icon)
                }
                .tag(Tab.recovery)

            TrainingTabView()
                .tabItem {
                    Image(systemName: Tab.training.icon)
                }
                .tag(Tab.training)

            NutritionTabView()
                .tabItem {
                    Image(systemName: Tab.nutrition.icon)
                }
                .tag(Tab.nutrition)

            LockdownTabView()
                .tabItem {
                    Image(systemName: Tab.lockdown.icon)
                }
                .tag(Tab.lockdown)
        }
        .tint(Color.tempoSignal)
        .onChange(of: appState.activeTab) { _, _ in
            HapticManager.selection()
        }
    }
}
