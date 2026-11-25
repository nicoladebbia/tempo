//
// TempoShell.swift
// Tempo
//
// The app's frame: four tabs (Today, Train, Fuel, Arena) and the "+" capture
// control. See docs/UI_REWORK_PLAN.md.
//

import SwiftUI

struct TempoShell: View {
    let nutritionViewModel: NutritionTabViewModel

    @Environment(ServiceContainer.self)
    private var services

    /// What the tab bar can select. `capture` is the "+": it never becomes the
    /// active tab, it opens the capture sheet.
    private enum Slot: Hashable {
        case today, train, fuel, arena, capture

        init(_ tab: AppTab) {
            switch tab {
            case .today: self = .today
            case .train: self = .train
            case .fuel: self = .fuel
            case .arena: self = .arena
            }
        }

        var tab: AppTab? {
            switch self {
            case .today: .today
            case .train: .train
            case .fuel: .fuel
            case .arena: .arena
            case .capture: nil
            }
        }
    }

    /// The prominent "+" needs iOS 27. iOS 26 gets the same "+" as the tab
    /// bar's own separated trailing button, so it is part of the bar: it moves
    /// and scales with it and never sits on top of a screen's content.
    /// `-tideCaptureFallback` forces the iOS 26 form (QA).
    private var hasProminentTab: Bool {
        if ProcessInfo.processInfo.arguments.contains("-tideCaptureFallback") {
            return false
        }
        if #available(iOS 27.0, *) {
            return true
        }
        return false
    }

    private var selection: Binding<Slot> {
        Binding(
            get: { Slot(services.appState.activeTab) },
            set: { slot in
                if let tab = slot.tab {
                    services.appState.activeTab = tab
                } else {
                    services.appState.captureRequested = true
                }
            }
        )
    }

    var body: some View {
        @Bindable
        var appState = services.appState
        return tabs
            .captureHost(isPresented: $appState.captureRequested, nutritionViewModel: nutritionViewModel)
            // The one place the workout screens are presented from.
            .workoutSessionHost()
            // Fuel logs made from the "+" sheet or the Scan tile end with an Undo toast; it rests
            // above the tab bar. Inside the Fuel tab its own host takes over (a second one does nothing).
            .fuelLogToastHost(placement: .aboveTabBar)
            // The mood goes on last, outside the hosts: a cover or sheet the shell
            // presents inherits what its presenter has, so it needs the day's
            // colour there, not only on the tabs.
            // The tab bar takes the mood colour, not the old accent setting.
            .tint(TideMood(score: appState.dayScore).accent)
            .environment(\.tideMood, TideMood(score: appState.dayScore))
            .onChange(of: appState.activeTab, initial: true) { _, tab in
                TempoSignpost.mark("ShellBody")
                TempoSignpost.tabPicked(tab)
            }
            .task {
                TideShaders.prewarm()
            }
        #if DEBUG
            .fullScreenCover(isPresented: .constant(TideGallery.requested != nil)) {
                TideGallery(score: TideGallery.requested ?? nil)
            }
        #endif
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 27.0, *), hasProminentTab {
            TabView(selection: selection) {
                mainTabs
                SwiftUI.Tab("Log", systemImage: "plus", value: Slot.capture, role: .prominent) {
                    Color.clear
                }
            }
        } else {
            TabView(selection: selection) {
                mainTabs
                SwiftUI.Tab("Log", systemImage: "plus", value: Slot.capture, role: .search) {
                    Color.clear
                }
            }
        }
    }

    @TabContentBuilder<Slot>
    private var mainTabs: some TabContent<Slot> {
        SwiftUI.Tab(AppTab.today.title, systemImage: AppTab.today.icon, value: Slot.today) {
            TodayView()
        }
        SwiftUI.Tab(AppTab.train.title, systemImage: AppTab.train.icon, value: Slot.train) {
            TrainingTabView()
                .onAppear { TempoSignpost.tabContentShown(.train) }
        }
        SwiftUI.Tab(AppTab.fuel.title, systemImage: AppTab.fuel.icon, value: Slot.fuel) {
            NutritionTabView(viewModel: nutritionViewModel)
                .onAppear { TempoSignpost.tabContentShown(.fuel) }
        }
        SwiftUI.Tab(AppTab.arena.title, systemImage: AppTab.arena.icon, value: Slot.arena) {
            ArenaTabView()
                .onAppear { TempoSignpost.tabContentShown(.arena) }
        }
    }
}
