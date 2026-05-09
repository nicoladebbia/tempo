//
// WorkoutView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Workout View

// Per APPLE_WATCH_APP.md Section 3.3 — Active workout set logging.
// Primary Watch use case: log sets/reps from wrist during gym sessions.

struct WorkoutView: View {
    let connectivity: WatchConnectivityService
    @State private var workoutState = WatchWorkoutState()
    @State private var isResting = false
    @State private var restSeconds = 120

    var body: some View {
        if workoutState.isActive {
            if isResting {
                restTimerContent
            } else {
                activeWorkoutContent
            }
        } else {
            workoutReadyContent
        }
    }

    // MARK: - Ready State (No Active Workout)

    // Per APPLE_WATCH_APP.md Section 3.3.1

    private var workoutReadyContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("TODAY'S WORKOUT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(connectivity.latestSnapshot.nextTaskName)
                    .font(.system(size: 17, weight: .bold))

                // Recovery-based intensity
                HStack(spacing: 4) {
                    Circle()
                        .fill(zoneColor(connectivity.latestSnapshot.recoveryZone))
                        .frame(width: 8, height: 8)
                    Text(
                        "Recovery: \(connectivity.latestSnapshot.recoveryZone == "green" ? "GO" : connectivity.latestSnapshot.recoveryZone == "yellow" ? "MODERATE" : "EASY")"
                    )
                    .font(.system(size: 14, weight: .medium))
                }

                // Start button — Full width, 50pt, green
                Button {
                    WatchHapticService.playWorkoutStart()
                    workoutState.isActive = true
                    workoutState.currentSet = 1
                    workoutState.totalSets = 4
                    workoutState.exerciseName = "Bench Press"
                    workoutState.lastWeight = 80
                    workoutState.lastReps = 8
                    connectivity.sendAction(.startWorkout)
                } label: {
                    Text("START WORKOUT")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Active Workout

    // Per APPLE_WATCH_APP.md Section 3.3.2

    private var activeWorkoutContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Exercise name + set
                Text(workoutState.exerciseName)
                    .font(.system(size: 17, weight: .bold))
                Text("Set \(workoutState.currentSet) of \(workoutState.totalSets)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                // Target display — monospaced in card
                Text("\(workoutState.lastReps) reps × \(Int(workoutState.lastWeight)) kg")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // SET DONE — 56pt height, large tap target
                Button {
                    WatchHapticService.playSetComplete()
                    connectivity.sendAction(.logSet, payload: [
                        "set": "\(workoutState.currentSet)",
                        "reps": "\(workoutState.lastReps)",
                        "weight": "\(workoutState.lastWeight)",
                    ])

                    if workoutState.currentSet >= workoutState.totalSets {
                        // Exercise done
                        workoutState.isActive = false
                        WatchHapticService.playWorkoutEnd()
                        connectivity.sendAction(.endWorkout)
                    } else {
                        // Start rest timer
                        isResting = true
                        restSeconds = 120
                    }
                } label: {
                    Text("✓  SET DONE")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                // Secondary actions
                HStack(spacing: 8) {
                    Button {
                        // Skip set
                        workoutState.currentSet += 1
                    } label: {
                        Text("SKIP")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Adjust - placeholder
                    } label: {
                        Text("ADJUST")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Rest Timer

    // Per APPLE_WATCH_APP.md Section 3.3.3

    private var restTimerContent: some View {
        VStack(spacing: 10) {
            Text("REST")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            // Large countdown
            Text(formatTime(restSeconds))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(restSeconds <= 10 ? .red : .white)

            // Next set info
            VStack(spacing: 4) {
                Text("NEXT SET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(workoutState.exerciseName) \(workoutState.currentSet + 1)/\(workoutState.totalSets)")
                    .font(.system(size: 14, weight: .medium))
                Text("\(workoutState.lastReps) reps × \(Int(workoutState.lastWeight)) kg")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Controls
            HStack(spacing: 8) {
                Button {
                    restSeconds += 30
                } label: {
                    Text("+30s")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    // Skip rest, go to next set
                    isResting = false
                    workoutState.currentSet += 1
                } label: {
                    Text("DONE")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .onAppear { startRestTimer() }
    }

    private func startRestTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if restSeconds > 0 {
                restSeconds -= 1
            } else {
                timer.invalidate()
                WatchHapticService.playRestTimerEnd()
                isResting = false
                workoutState.currentSet += 1
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        default: .green
        }
    }
}
