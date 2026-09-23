//
// WorkoutView.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import SwiftUI

// MARK: - Workout View

// Per APPLE_WATCH_APP.md Section 3.3 — Active workout set logging.
// Primary Watch use case: log sets/reps from wrist during gym sessions.
// §21 — runs on the REAL plan pushed by the phone (WatchWorkoutPayload via
// application context), not hardcoded stubs. Each SET DONE round-trips to
// the phone as a .logSet quick action carrying the exercise name + actuals.

struct WorkoutView: View {
    let connectivity: WatchConnectivityService
    @State private var workoutState = WatchWorkoutState()
    @State private var exerciseIndex = 0
    @State private var isResting = false
    @State private var restSeconds = 120
    @State private var showAdjust = false

    /// The phone's payload, but only if it is actually TODAY's plan — a
    /// stale context from yesterday must not start yesterday's workout.
    private var todayWorkout: WatchWorkoutPayload? {
        guard let payload = connectivity.latestWorkout,
              payload.dayKey == Self.todayKey()
        else {
            return nil
        }
        return payload
    }

    private var remainingSets: Int {
        todayWorkout?.exercises.reduce(0) { $0 + max(0, $1.totalSets - $1.completedSets) } ?? 0
    }

    /// Weights travel as canonical kg; display follows the phone's unit.
    private var isLbs: Bool {
        connectivity.latestWorkout?.unit == "lbs"
    }

    private var unitLabel: String {
        isLbs ? "lbs" : "kg"
    }

    /// One plate-step in kg: ±5 lbs in lbs gyms, ±2.5 kg otherwise.
    private var adjustStepKg: Double {
        isLbs ? 5 / 2.20462 : 2.5
    }

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

                if let workout = todayWorkout, remainingSets > 0 {
                    Text(workout.workoutType)
                        .font(.system(size: 17, weight: .bold))

                    Text("\(workout.exercises.count) exercises · \(remainingSets) sets left")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

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
                        begin(workout)
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
                } else if todayWorkout != nil {
                    Text("ALL SETS DONE")
                        .font(.system(size: 17, weight: .bold))
                    Text("Today's lifting is in the books. Recover hard.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("NO WORKOUT SYNCED")
                        .font(.system(size: 15, weight: .bold))
                    Text("Open Tempo on your iPhone — today's plan lands here automatically.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
                Text("\(workoutState.lastReps) reps × \(weightLabel(workoutState.lastWeight)) \(unitLabel)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // SET DONE — 56pt height, large tap target
                Button {
                    connectivity.sendAction(.logSet, payload: [
                        "exercise": workoutState.exerciseName,
                        "set": "\(workoutState.currentSet)",
                        "reps": "\(workoutState.lastReps)",
                        "weight": "\(workoutState.lastWeight)",
                    ]) { ack in
                        switch ack {
                        case .confirmed: WatchHapticService.playSetComplete()
                        case .queued: WatchHapticService.playQueued()
                        case .failed: WatchHapticService.playError()
                        }
                    }
                    advance()
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
                        // Skip set — advance without logging it on the phone.
                        advance()
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
                        showAdjust.toggle()
                    } label: {
                        Text("ADJUST")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white.opacity(showAdjust ? 0.25 : 0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                if showAdjust {
                    // One plate-step per tap (±5 lbs / ±2.5 kg) on the working weight.
                    HStack(spacing: 8) {
                        Button {
                            workoutState.lastWeight = max(0, workoutState.lastWeight - adjustStepKg)
                        } label: {
                            Text("−\(isLbs ? "5 lbs" : "2.5 kg")")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            workoutState.lastWeight += adjustStepKg
                        } label: {
                            Text("+\(isLbs ? "5 lbs" : "2.5 kg")")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
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

            // Next set info — the queue already advanced when the set logged.
            VStack(spacing: 4) {
                Text("NEXT SET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(workoutState.exerciseName) \(workoutState.currentSet)/\(workoutState.totalSets)")
                    .font(.system(size: 14, weight: .medium))
                Text("\(workoutState.lastReps) reps × \(weightLabel(workoutState.lastWeight)) \(unitLabel)")
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
                    // Skip rest — the next set is already loaded.
                    isResting = false
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

    // MARK: - Queue

    /// Start at the first exercise that still has sets to do (the phone may
    /// have some already logged).
    private func begin(_ workout: WatchWorkoutPayload) {
        guard let index = workout.exercises.firstIndex(where: { $0.completedSets < $0.totalSets }) else {
            return
        }
        move(to: index, in: workout)
        workoutState.isActive = true
        connectivity.sendAction(.startWorkout) { ack in
            switch ack {
            case .confirmed: WatchHapticService.playWorkoutStart()
            case .queued: WatchHapticService.playQueued()
            case .failed: WatchHapticService.playError()
            }
        }
    }

    private func move(to index: Int, in workout: WatchWorkoutPayload) {
        let exercise = workout.exercises[index]
        exerciseIndex = index
        workoutState.exerciseName = exercise.name
        workoutState.totalSets = exercise.totalSets
        workoutState.currentSet = min(exercise.completedSets + 1, exercise.totalSets)
        workoutState.lastReps = exercise.targetReps
        workoutState.lastWeight = exercise.targetWeightKg
        showAdjust = false
    }

    /// Advance the local queue: next set → rest; exercise done → next
    /// exercise with room; nothing left → end workout.
    private func advance() {
        if workoutState.currentSet < workoutState.totalSets {
            workoutState.currentSet += 1
            startRest()
        } else if let workout = todayWorkout,
                  let next = workout.exercises.indices.first(where: { index in
                      index > exerciseIndex && workout.exercises[index].completedSets < workout.exercises[index].totalSets
                  })
        {
            move(to: next, in: workout)
            startRest()
        } else {
            workoutState.isActive = false
            isResting = false
            // §22 — no `.endWorkout` send: there's no honest phone-side
            // equivalent (see WatchQuickAction.swift). This haptic is purely
            // local — the LOCAL queue is empty — and "ALL SETS DONE" above
            // already reflects the real synced state from the last `.logSet`.
            WatchHapticService.playWorkoutEnd()
        }
    }

    private func startRest() {
        restSeconds = 120
        isResting = true
    }

    private func startRestTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if isResting, restSeconds > 0 {
                restSeconds -= 1
            } else {
                timer.invalidate()
                if isResting {
                    WatchHapticService.playRestTimerEnd()
                    isResting = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// kg → display unit, rounded to the nearest 0.5 so a snapped 40.82 kg
    /// shows as the 90 lbs it actually is, not 89.9997.
    private func weightLabel(_ weightKg: Double) -> String {
        let value = isLbs ? weightKg * 2.20462 : weightKg
        return String(format: "%g", (value * 2).rounded() / 2)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        case "unknown": .gray
        default: .green
        }
    }
}
