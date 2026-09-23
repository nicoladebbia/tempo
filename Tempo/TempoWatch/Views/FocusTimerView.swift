//
// FocusTimerView.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import SwiftUI

// MARK: - Focus Timer View

// Per APPLE_WATCH_APP.md Section 3.4 — Pomodoro timer on wrist.
// Start/pause/stop from wrist. Duration: 15/25/45/60 min presets.

struct FocusTimerView: View {
    let connectivity: WatchConnectivityService
    @State private var timerState = WatchTimerState()
    @State private var selectedDuration = 1500 // 25 min default

    private let durationPresets = [900, 1500, 2700, 3600] // 15, 25, 45, 60 min

    var body: some View {
        if timerState.isRunning {
            runningContent
        } else {
            readyContent
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

            Spacer()

            // Large countdown
            Text(formatTime(timerState.remainingSeconds))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.purple)

            Spacer()

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
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard timerState.isRunning, !timerState.isPaused else {
                if !timerState.isRunning {
                    timer.invalidate()
                }
                return
            }
            if timerState.remainingSeconds > 0 {
                timerState.remainingSeconds -= 1
            } else {
                timer.invalidate()
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
