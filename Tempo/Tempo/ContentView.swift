import SwiftUI

// MARK: - Content View
// Per BUILD_PLAN step 3.10 — 5-tab TabView wired to AppState.activeTab.
// Conditionally shows onboarding if !isOnboardingComplete.

struct ContentView: View {

    @Environment(ServiceContainer.self) private var services

    var body: some View {
        Group {
            if services.appState.isOnboardingComplete {
                mainTabView
            } else {
                OnboardingContainerView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabView: some View {
        @Bindable var appState = services.appState
        return TabView(selection: $appState.activeTab) {
            DashboardView()
                .tabItem {
                    Label(Tab.dashboard.title, systemImage: Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)

            TrainingTabView()
                .tabItem {
                    Label(Tab.training.title, systemImage: Tab.training.icon)
                }
                .tag(Tab.training)

            LockdownTabView()
                .tabItem {
                    Label(Tab.lockdown.title, systemImage: Tab.lockdown.icon)
                }
                .tag(Tab.lockdown)

            RecoveryTabView()
                .tabItem {
                    Label(Tab.recovery.title, systemImage: Tab.recovery.icon)
                }
                .tag(Tab.recovery)

            ArenaTabView()
                .tabItem {
                    Label(Tab.arena.title, systemImage: Tab.arena.icon)
                }
                .tag(Tab.arena)
        }
        .tint(Color.tempoSignal)
        .onChange(of: appState.activeTab) { _, _ in
            HapticManager.selection()
        }
    }
}

