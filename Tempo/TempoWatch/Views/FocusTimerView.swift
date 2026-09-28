//
// FocusTimerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Focus Timer View

// Per APPLE_WATCH_APP.md Section 3.4 — Pomodoro timer on wrist.
// Start/pause/stop from wrist. Duration: 15/25/45/60 min presets.

struct FocusTimerView: View {
    let connectivity: WatchConnectivityService
    @State
    private var timerState = WatchTimerState()
    /// The one live countdown loop — restarting (RESUME) cancels the old one,
    /// or two loops would tick at 2x and double-send the stop.
    @State
    private var countdownTask: Task<Void, Never>?
    @State
    private var selectedDuration = 1500 // 25 min default
    /// The `updatedAt` of the last phone snapshot this view has already
    /// adopted into `timerState` — lets `reconcileWithPhone` tell "the phone
    /// pushed something NEW" from "nothing changed since last time" without
    /// re-adopting (and re-jittering the countdown Task) on every re-render.
    @State
    private var adoptedPhoneUpdatedAt: Date?

    private let durationPresets = [900, 1500, 2700, 3600] // 15, 25, 45, 60 min

    var body: some View {
        Group {
            if timerState.isRunning {
                runningContent
            } else {
                readyContent
            }
        }
        .onAppear { reconcileWithPhone() }
        .onChange(of: connectivity.latestFocusTimer) { _, _ in reconcileWithPhone() }
    }

    // MARK: - Phone reconciliation

    // Watch audit, 2026-09 — before this, `timerState` was driven ENTIRELY
    // by wrist taps: a session started from the phone was invisible here
    // (this view kept showing "ready to start" while one was actually
    // running), and a session the phone cancelled kept ticking a phantom
    // countdown on the wrist forever. Mirrors `WorkoutView.todayWorkout` /
    // `GuidedRunWatchView`'s pattern of adopting the phone's pushed state
    // instead of only ever trusting local taps.

    /// Adopts a phone session this view hasn't already reflected, and stops
    /// a phone-adopted display once the phone says it ended. Never
    /// interferes with a purely wrist-started session already ticking
    /// locally between phone pushes — the `updatedAt` guard only reacts to
    /// an ACTUAL new snapshot.
    private func reconcileWithPhone() {
        guard let payload = connectivity.latestFocusTimer else {
            if adoptedPhoneUpdatedAt != nil {
                // The phone ended a session this view had adopted — stop
                // ticking, don't send `.stopFocusTimer` (nothing to tell the
                // phone; it's the one that just told US).
                countdownTask?.cancel()
                timerState.isRunning = false
                timerState.isPaused = false
                adoptedPhoneUpdatedAt = nil
            }
            return
        }
        guard payload.updatedAt != adoptedPhoneUpdatedAt else {
            return
        }
        adoptedPhoneUpdatedAt = payload.updatedAt
        timerState.isRunning = true
        timerState.isPaused = payload.isPaused
        timerState.remainingSeconds = max(0, Int(payload.remainingSeconds.rounded()))
        timerState.sessionCount = max(0, payload.sessionIndex - 1)
        if payload.isPaused {
            countdownTask?.cancel()
        } else {
            startCountdown()
        }
    }

    // MARK: - Ready State

    // Per APPLE_WATCH_APP.md Section 3.4.1

    private var readyContent: some View {
        VStack(spacing: 12) {
            Text("FOCUS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            // Duration display
            Text(formatTime(selectedDuration))
                .font(.system(size: 40, weight: .bold, design: .monospaced))

            // Session stats
            VStack(spacing: 2) {
                Text("Sessions today: \(timerState.sessionCount)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Start button
            Button {
                timerState.isRunning = true
                timerState.totalSeconds = selectedDuration
                timerState.remainingSeconds = selectedDuration
                connectivity.sendAction(.startFocusTimer, payload: [
                    "duration": "\(selectedDuration)",
                ]) { ack in
                    switch ack {
                    case .confirmed: WatchHapticService.playWorkoutStart()
                    case .queued: WatchHapticService.playQueued()
                    case .failed: WatchHapticService.playError()
                    }
                }
                startCountdown()
            } label: {
                Text("START")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Duration selector — tap to cycle
            Button {
                cycleDuration()
            } label: {
                Text("Duration: \(selectedDuration / 60) min  ↻")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Running State

    // Per APPLE_WATCH_APP.md Section 3.4.2

    private var runningContent: some View {
        // Watch audit, 2026-09 — this used to be a bare VStack whose two
        // flexible `Spacer()`s (removed below) made it greedily fill the
        // WHOLE page, pushing the top "FOCUS / Session N" row flush against
        // — on a 41mm watch, actually UNDER — the system time. Every other
        // tab wraps its content in a ScrollView, which correctly insets from
        // the top safe area; this one didn't, because the un-scrollable
        // Spacer-centered layout was never given room to size itself first.
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("FOCUS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Session \(timerState.sessionCount + 1)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Large countdown
                Text(formatTime(timerState.remainingSeconds))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
                    .padding(.vertical, 8)

                // Controls
                HStack(spacing: 8) {
                    if timerState.isPaused {
                        Button {
                            timerState.isPaused = false
                            connectivity.sendAction(.resumeFocusTimer)
                            startCountdown()
                        } label: {
                            Text("RESUME")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            timerState.isPaused = true
                            connectivity.sendAction(.pauseFocusTimer)
                        } label: {
                            Text("PAUSE")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        timerState.isRunning = false
                        timerState.isPaused = false
                        connectivity.sendAction(.stopFocusTimer)
                    } label: {
                        Text("STOP")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                // Extend
                Button {
                    timerState.remainingSeconds += 300 // +5 min
                } label: {
                    Text("+ 5 MINUTES")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func cycleDuration() {
        guard let idx = durationPresets.firstIndex(of: selectedDuration) else {
            selectedDuration = durationPresets[0]
            return
        }
        let nextIdx = (idx + 1) % durationPresets.count
        selectedDuration = durationPresets[nextIdx]
    }

    private func startCountdown() {
        // Task loop on the main actor (a Timer closure is @Sendable and can't
        // touch @State under Swift 6).
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while timerState.isRunning, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard timerState.isRunning, !Task.isCancelled else {
                    return
                }
                if timerState.isPaused {
                    continue
                }
                if timerState.remainingSeconds > 0 {
                    timerState.remainingSeconds -= 1
                    continue
                }
                timerState.isRunning = false
                timerState.sessionCount += 1
                connectivity.sendAction(.stopFocusTimer, payload: [
                    "completed": "true",
                    "duration": "\(timerState.totalSeconds)",
                ]) { ack in
                    switch ack {
                    case .confirmed: WatchHapticService.playFocusTimerEnd()
                    case .queued: WatchHapticService.playQueued()
                    case .failed: WatchHapticService.playError()
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
