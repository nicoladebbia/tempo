//
// TempoWatchApp.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoWatchApp

// Per APPLE_WATCH_APP.md Section 3.1 — NavigationStack with vertically-paging TabView.
// 5 pages: Glance, Workout, Focus Timer, Quick Log, Recovery.

@main
struct TempoWatchApp: App {
    @State
    private var connectivityService = WatchConnectivityService.shared
    /// Screenshot/manual-QA aid only — jumps straight to the Workout tab when
    /// `GuidedRunWatchSeed` seeded a sample run, so a screenshot doesn't need
    /// a Digital Crown/page swipe the simulator has no scriptable way to send.
    @State
    private var selectedTab = 0

    init() {
        #if DEBUG
            GuidedRunWatchSeed.seedIfRequested()
            if ProcessInfo.processInfo.arguments.contains("--uitesting-guided-run-sample") {
                _selectedTab = State(initialValue: 1)
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                GlanceHomeView(connectivity: connectivityService).tag(0)
                WorkoutView(connectivity: connectivityService).tag(1)
                FocusTimerView(connectivity: connectivityService).tag(2)
                QuickLogView(connectivity: connectivityService).tag(3)
                RecoveryView(connectivity: connectivityService).tag(4)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

#if DEBUG
    /// Guided run mode — screenshot/manual-QA aid only. The Watch mirror is
    /// normally populated by a live WCSession push from the phone; this lets
    /// the Workout tab's guided-run screen be exercised on a simulator with
    /// no paired session at all (the phone side has its own equivalent,
    /// GuidedRunUITestSeed).
    enum GuidedRunWatchSeed {
        static func seedIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("--uitesting-guided-run-sample") else {
                return
            }
            WatchConnectivityService.shared.latestGuidedRun = GuidedRunActivitySnapshot(
                stepTitle: "Shuttle 1 · Rep 2/4",
                detailText: "Cap 1:05",
                nextStepText: nil,
                distanceText: nil,
                paceText: nil,
                heartRateText: "142 bpm",
                heartRateZone: 3,
                isRest: false,
                isCountdown: false,
                isPaused: false,
                countsDown: false,
                timerAnchor: Date().addingTimeInterval(-24),
                frozenText: nil,
                updatedAt: Date()
            )
        }
    }
#endif
