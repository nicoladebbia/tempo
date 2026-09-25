//
// MoveQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - MoveQuadrantDetailView

// Per MODULE_DASHBOARD.md Section 4.5 — Move Expanded View.
// Workout hero, activity stats, steps progress, heart rate section,
// workout history, weekly volume chart.

struct MoveQuadrantDetailView: View {
    let data: MoveQuadrantData
    @Environment(ServiceContainer.self)
    private var services
    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false

    /// Real completed workouts, newest first. Empty until the user finishes
    /// a session — no seed data (Phase 1, done_when #1).
    @Query(
        filter: #Predicate<WorkoutPlan> { $0.statusRaw == "completed" },
        sort: \WorkoutPlan.date,
        order: .reverse
    )
    private var completedWorkouts: [WorkoutPlan]

    /// User weight-unit preference for volume display.
    @Query
    private var userSettings: [UserSettings]

    /// Post-workout average HR for the most recent completed session,
    /// sourced from HealthKit `HKWorkout` samples. `nil` = not yet loaded;
    /// `.some(nil)` = loaded but no HR recorded (Phase 1, done_when #3).
    @State private var lastSessionAvgHR: Double??

    @Environment(\.modelContext)
    private var modelContext

    // Live workout session presented directly from the Move detail (chosen
    // behavior). Mirrors TrainingTabView's VM + fullScreenCover wiring so the
    // session behaves identically wherever it's started.
    @State private var trainingVM: TrainingViewModel?
    @State private var showActiveWorkout = false
    @State private var showSummary = false

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if data.isConnected || healthKitAuthorized {
                    workoutHeroSection
                    todayActivitySection
                    heartRateSection
                    workoutHistorySection
                    weeklyVolumeSection
                    startWorkoutButton
                } else {
                    EmptyStateView(
                        icon: "heart.text.square",
                        title: "Health Access Required",
                        message: "Allow HealthKit access to track steps, calories, and workout data.",
                        actionTitle: "Authorize",
                        action: {
                            Task {
                                try? await services.healthKit.requestAuthorization()
                                healthKitAuthorized = true
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Move")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: completedWorkouts.first?.id) {
            await loadLastSessionHR()
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            if let trainingVM {
                NavigationStack {
                    ActiveWorkoutView(viewModel: trainingVM)
                }
            }
        }
        .fullScreenCover(isPresented: $showSummary, onDismiss: {
            showSummary = false
        }) {
            if let trainingVM {
                NavigationStack {
                    WorkoutSummaryView(viewModel: trainingVM)
                }
            }
        }
        .onChange(of: trainingVM?.sessionState) { _, newState in
            if newState?.needsWorkoutScreen == true, !showActiveWorkout {
                // A session that went live without the Start button (watch-
                // started and adopted on load, or crash recovery) still needs
                // its screen — otherwise timers run behind the Today view.
                showActiveWorkout = true
            } else if case .summary = newState {
                showActiveWorkout = false
                showSummary = true
            } else if case .discarded = newState {
                // Mirror TrainingTabView: without this branch a discard from a
                // session started HERE left sessionState stuck at .discarded —
                // covers stayed torn down but the VM never reset, so the next
                // start from this screen ran on stale state.
                showActiveWorkout = false
                showSummary = false
                if let trainingVM {
                    Task { @MainActor in
                        await trainingVM.loadToday(modelContext: modelContext)
                        trainingVM.sessionState = .idle
                    }
                }
            }
        }
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { trainingVM?.saveErrorMessage != nil },
                set: {
                    if !$0 {
                        trainingVM?.saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trainingVM?.saveErrorMessage ?? "")
        }
    }

    // MARK: - Real Data Loaders

    /// Reads the most recent completed session's `HKWorkout` HR summary.
    ///
    /// Per the `healthkit_batch_fetch_trap` memory: `fetchWorkouts` is
    /// HKSampleQuery-based and throws code 11 ("No data available") on an
    /// iPhone with no Apple Watch. It MUST be isolated in its own `try?`
    /// with an empty default — never a shared do/catch.
    private func loadLastSessionHR() async {
        guard let last = completedWorkouts.first else {
            lastSessionAvgHR = .some(nil)
            return
        }
        let sessionDate = last.finishedAt ?? last.date
        let samples = await (try? services.healthKit.fetchWorkouts(for: sessionDate)) ?? []
        // Match the HK workout that overlaps this session's finish time;
        // fall back to the highest-HR sample for the day.
        let avg = samples
            .compactMap(\.averageHeartRate)
            .max()
        lastSessionAvgHR = .some(avg)
    }

    /// 7-day training-volume series from completed sessions only:
    /// Σ(actualWeight × actualReps) over completed sets, in the user's unit.
    /// Per done_when #2 — NOT planned exercises, NOT active calories.
    private var weeklyVolumeTrend: [TrainingVolumePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let window = (-6 ... 0).map { offset in
            calendar.date(byAdding: .day, value: offset, to: today)!
        }
        let byDay = Dictionary(grouping: completedWorkouts) { plan in
            calendar.startOfDay(for: plan.finishedAt ?? plan.date)
        }
        return window.map { day in
            let plansThatDay = byDay[day] ?? []
            // Fix #9 — same source as every other volume reader:
            // `WorkoutPlan.totalVolume` (working sets only, per-side aware).
            let volumeKg = plansThatDay.reduce(0.0) { $0 + $1.totalVolume }
            let displayVolume = WeightUnit.kg.convert(volumeKg, to: weightUnit)
            return TrainingVolumePoint(date: day, volume: displayVolume)
        }
    }

    // MARK: - Workout Hero

    // Per MODULE_DASHBOARD.md Section 4.5 — Workout Hero

    private var workoutHeroSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            switch data.workoutStatus {
            case .completed:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.tempoSuccess)
                    Text(data.workoutName ?? "Workout")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                }

                HStack(spacing: 0) {
                    Text("\(data.formattedWorkoutDuration)")
                    Text(" · ")
                    Text(data.formattedActiveCalories)
                }
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

                Text(workoutQuip)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .italic()

            case .planned:
                Text(data.workoutName ?? "Workout")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("Planned. Tap to start.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoAmber)

            case .restDay:
                Text("Rest Day")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextSecondary)
                Text("Growth happens in the recovery.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .italic()

            case .none:
                Text("No workout today")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextTertiary)

                Button {
                    // Was an EMPTY closure — a dead-end that looked tappable.
                    // Generate today's plan through the same pipeline the
                    // Training tab uses; the .tempoWorkoutChanged fan-out then
                    // flips the Dashboard's workoutStatus to .planned.
                    Task { @MainActor in
                        let vm = trainingVM ?? TrainingViewModel(
                            trainingEngine: services.trainingEngine,
                            whoop: services.whoop,
                            healthKit: services.healthKit,
                            apiClient: services.apiClient,
                            calendarService: services.calendar
                        )
                        trainingVM = vm
                        await vm.loadToday(modelContext: modelContext)
                        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
                        HapticManager.notification(.success)
                    }
                } label: {
                    Text("+ Plan Workout")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoAmber)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Today's Activity

    // Per MODULE_DASHBOARD.md Section 4.5 — Today's Activity

    private var todayActivitySection: some View {
        VStack(spacing: TempoSpacing.md) {
            // Two stat cards
            HStack(spacing: TempoSpacing.md) {
                activityCard(
                    value: data.formattedSteps,
                    label: "Steps",
                    subtitle: "/\(NumberFormatter.localizedString(from: NSNumber(value: data.stepsTarget), number: .decimal))"
                )

                activityCard(
                    value: data.formattedActiveCalories,
                    label: "Active Cal",
                    subtitle: nil
                )

                activityCard(
                    value: data.formattedStrain,
                    label: "Strain",
                    subtitle: nil
                )
            }

            // Steps progress bar
            HStack(spacing: TempoSpacing.sm) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tempoBorder).frame(height: 8)
                        Capsule().fill(Color.tempoAmber)
                            .frame(width: geo.size.width * min(data.stepsProgress, 1.0), height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(Int(min(data.stepsProgress, 1.0) * 100))%")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Step pace projection
            Text(stepPaceProjection)
                .font(.tempoCaption1)
                .foregroundStyle(stepPaceColor)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func activityCard(value: String, label: String, subtitle: String?) -> some View {
        // All three cards are identical: same fixed height, same value font
        // (no minimumScaleFactor so "1332" and "5.0" render at the same
        // size), and the subtitle line's space is always reserved so a card
        // with no subtitle is exactly as tall as one that has it.
        VStack(spacing: TempoSpacing.xxs) {
            Text(value)
                .font(.tempoTitle3)
                .fontWeight(.bold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)
            Text(subtitle ?? " ")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Heart Rate Section

    // Per MODULE_DASHBOARD.md Section 4.5 — post-workout HR summary only.
    // No live HR streaming (no Apple Watch — see build constraints).

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("HEART RATE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            switch lastSessionAvgHR {
            case .none:
                // Not yet loaded — quiet placeholder, no spinner churn.
                Text("—")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextTertiary)
            case let .some(.some(avg)):
                Text("Last session avg: \(Int(avg.rounded())) bpm")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                if let last = completedWorkouts.first {
                    Text(last.type.displayName + " · " + (last.finishedAt ?? last.date)
                        .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            case .some(.none):
                // Loaded, but no HKWorkout HR for this session.
                Text("No HR data recorded")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Workout History

    // Per MODULE_DASHBOARD.md Section 4.5 — real completed sessions only.

    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WORKOUT HISTORY")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.bottom, TempoSpacing.md)

            let recent = Array(completedWorkouts.prefix(5))
            if recent.isEmpty {
                Text("No workouts recorded yet.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, workout in
                    HStack(spacing: TempoSpacing.md) {
                        Text((workout.finishedAt ?? workout.date)
                            .formatted(.dateTime.weekday(.abbreviated)))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .frame(width: 36, alignment: .leading)

                        Text(workout.type.displayName)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Spacer()

                        let dur = workout.durationMinutes ?? workout.actualDurationMinutes
                        let vol = WeightUnit.kg.convert(workout.totalVolume, to: weightUnit)
                        Text(volumeHistoryLabel(durationMinutes: dur, volume: vol))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .frame(minHeight: 44)

                    if index < recent.count - 1 {
                        Divider().background(Color.tempoDivider)
                    }
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func volumeHistoryLabel(durationMinutes: Int?, volume: Double) -> String {
        let unit = weightUnit.abbreviation
        let volStr = volume >= 1000
            ? String(format: "%.1fk %@", volume / 1000, unit)
            : "\(Int(volume)) \(unit)"
        if let dur = durationMinutes {
            return "\(dur)m · \(volStr)"
        }
        return volStr
    }

    // MARK: - Weekly Volume Chart

    // Per MODULE_DASHBOARD.md Section 4.5 — training volume from completed
    // sets (actual weight × actual reps), NOT active calories.

    private var weeklyVolumeSection: some View {
        let trend = weeklyVolumeTrend
        let unit = weightUnit.abbreviation
        let totalVol = trend.reduce(0.0) { $0 + $1.volume }
        let workoutDays = trend.count(where: { $0.volume > 0 })

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WEEKLY VOLUME")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            if totalVol == 0 {
                Text("No completed sets this week.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                Chart(trend) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(Color.tempoAmber)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                        }
                    }
                }
                .frame(height: 140)

                Text(
                    "Total: \(NumberFormatter.localizedString(from: NSNumber(value: Int(totalVol)), number: .decimal)) \(unit) · \(workoutDays) \(workoutDays == 1 ? "session" : "sessions")"
                )
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Start Workout Button

    // Per MODULE_DASHBOARD.md Section 4.5

    private var startWorkoutButton: some View {
        Button {
            Task { @MainActor in
                // Build the VM lazily, same construction as TrainingTabView.
                let vm = trainingVM ?? TrainingViewModel(
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit,
                    apiClient: services.apiClient,
                    calendarService: services.calendar
                )
                trainingVM = vm
                await vm.loadToday(modelContext: modelContext)
                vm.startWorkout()
                showActiveWorkout = true
                HapticManager.notification(.success)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Start Workout")
                    .font(.tempoCallout)
            }
            .foregroundStyle(Color.tempoTextInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.tempoAmber)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
    }

    // MARK: - Helpers

    private var workoutQuip: String {
        [
            "Solid session. Now recover.",
            "Done and dusted.",
            "Checked off. Next one's waiting.",
            "Work in the bank.",
        ].randomElement() ?? ""
    }

    private var stepPaceProjection: String {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let hoursElapsed = now.timeIntervalSince(startOfDay) / 3600
        let hour = calendar.component(.hour, from: now)

        guard hour >= 8, hoursElapsed >= 1, let steps = data.steps else {
            return "Too early to project"
        }

        let projected = Int(Double(steps) / hoursElapsed * 16)
        return "Step pace: On track for \(NumberFormatter.localizedString(from: NSNumber(value: projected), number: .decimal))"
    }

    private var stepPaceColor: Color {
        guard let steps = data.steps else {
            return .tempoTextSecondary
        }
        let calendar = Calendar.current
        let hoursElapsed = Date().timeIntervalSince(calendar.startOfDay(for: Date())) / 3600
        guard hoursElapsed >= 1 else {
            return .tempoTextSecondary
        }
        let projected = Int(Double(steps) / hoursElapsed * 16)
        if projected >= data.stepsTarget {
            return .tempoSuccess
        }
        if projected < Int(Double(data.stepsTarget) * 0.8) {
            return .tempoWarning
        }
        return .tempoTextSecondary
    }
}

// MARK: - TrainingVolumePoint

/// One day's training volume (Σ actual weight × actual reps over completed
/// sets) in the user's weight unit. Backs the Weekly Volume chart.
struct TrainingVolumePoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MoveQuadrantDetailView(
            data: MoveQuadrantData(
                workoutStatus: .completed,
                workoutName: "Upper Body Push",
                workoutDurationMinutes: 55,
                steps: 8432,
                stepsTarget: 10000,
                activeCalories: 342,
                heartRateCurrent: 72,
                isConnected: true,
                lastSync: Date()
            )
        )
    }
    .environment(ServiceContainer.mock())
}
