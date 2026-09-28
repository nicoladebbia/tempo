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
            WatchScreenshotSeed.seedIfRequested()
            if ProcessInfo.processInfo.arguments.contains("--uitesting-guided-run-sample") {
                _selectedTab = State(initialValue: 1)
            }
            // Watch audit, 2026-09 — same screenshot/manual-QA aid as above:
            // the vertically-paging TabView has no other scriptable way to
            // land on a specific page (no swipe injection in the
            // simulator), so `--uitesting-watch-tab=<0-4>` jumps straight to
            // one of Glance/Workout/Focus Timer/Quick Log/Recovery.
            if let tabArg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--uitesting-watch-tab=") }),
               let tab = Int(tabArg.dropFirst("--uitesting-watch-tab=".count))
            {
                _selectedTab = State(initialValue: tab)
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

    /// Watch audit, 2026-09 — screenshot/manual-QA aid only, same idea as
    /// `GuidedRunWatchSeed` but for the daily snapshot, today's workout and a
    /// focus session, so Glance/Workout/Quick Log/Recovery/Focus Timer can
    /// all be screenshotted showing real-shaped data on a simulator with no
    /// paired phone at all.
    enum WatchScreenshotSeed {
        static func seedIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("--uitesting-watch-sample-data") else {
                return
            }
            WatchConnectivityService.shared.latestSnapshot = WatchSnapshot(
                dailyScore: 78,
                recoveryZone: "green",
                recoveryScore: 82,
                sleepHours: 7.4,
                hrv: 62,
                rhr: 54,
                nextTaskName: "Study Session",
                nextTaskTimeRemaining: "1h 20m",
                nonNegotiables: [
                    WatchNonNegotiableItem(id: "1", title: "Morning workout", isCompleted: true),
                    WatchNonNegotiableItem(id: "2", title: "Read 20 pages", isCompleted: false),
                ],
                nnCompleted: 1,
                nnTotal: 2,
                leisureUnlocked: false,
                currentStreak: 12,
                xp: 4200,
                leaderboardPosition: 3,
                nextMeal: WatchNextMeal(id: "m1", name: "Lunch"),
                hasRealData: true,
                updatedAt: Date()
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            WatchConnectivityService.shared.latestWorkout = WatchWorkoutPayload(
                workoutType: "PUSH",
                dayKey: formatter.string(from: Date()),
                unit: "kg",
                exercises: [
                    WatchWorkoutPayload.Exercise(
                        name: "Bench Press", totalSets: 4, completedSets: 2,
                        targetReps: 8, targetWeightKg: 80, perSide: false
                    ),
                    WatchWorkoutPayload.Exercise(
                        name: "Overhead Press", totalSets: 3, completedSets: 0,
                        targetReps: 10, targetWeightKg: 45, perSide: false
                    ),
                ],
                updatedAt: Date()
            )
            WatchConnectivityService.shared.latestFocusTimer = WatchFocusTimerPayload(
                isPaused: false,
                remainingSeconds: 18 * 60 + 12,
                phaseLabel: "FOCUS TIME",
                sessionIndex: 2,
                totalSessions: 4,
                updatedAt: Date()
            )
        }
    }
#endif
