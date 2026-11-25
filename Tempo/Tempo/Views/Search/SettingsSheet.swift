//
// SettingsSheet.swift
// Tempo
//
// Settings opened from anywhere, optionally straight on one page. Search and
// the Today checklist use it to land on "Schedule", "Connections", "Goal" and
// the rest. The page list is `SettingsDestination`.
//

import SwiftUI

// MARK: - SettingsSheet

struct SettingsSheet: View {
    let page: SettingsDestination?

    @State
    private var path: [SettingsDestination]

    init(page: SettingsDestination?) {
        self.page = page
        _path = State(initialValue: page.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            DashboardSettingsView()
                .navigationDestination(for: SettingsDestination.self) { page in
                    SettingsPageView(page: page)
                }
        }
        .persistenceAlert()
    }
}

// MARK: - SettingsPageView

/// The screen for one `SettingsDestination`.
struct SettingsPageView: View {
    let page: SettingsDestination

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        switch page {
        case .schedule: ScheduleSettingsDetailView()
        case .training: TrainingSettingsDetailView()
        case .focusTimer: FocusTimerSettingsDetailView()
        case .modes: ModesSettingsDetailView()
        case .dietProfile: FuelSetupView(embedded: true)
        case .weeklyHabits: WeeklyHabitsSettingsView()
        case .connections: ConnectionsView()
        case .todaysNotifications: NotificationInboxView(onOpen: { dismiss() })
        case .notifications: NotificationSettingsView()
        case .subscription: SettingsSubscriptionPage()
        case .account: AccountDetailView()
        case .exportData: DataExportView()
        case .profile: ProfileSettingsDetailView()
        case .goal: GoalEditorView()
        case .getSetUp: SetupChecklistPage()
        }
    }
}

// MARK: - SettingsSubscriptionPage

/// The Subscription page owns its own copy of the plan when it is opened directly.
private struct SettingsSubscriptionPage: View {
    @State
    private var plan = PlanModel()

    var body: some View {
        SubscriptionDetailView(plan: plan)
    }
}
