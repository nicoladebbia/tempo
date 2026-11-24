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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                if data.isConnected || healthKitAuthorized {
                    workoutHeroSection
                    todayActivitySection
                    heartRateSection
                    workoutHistorySection
                    weeklyVolumeSection
                    startWorkoutButton
                } else {
                    TrainEmptyCard(
                        systemImage: "heart.text.square",
                        title: "Health Access Required",
                        message: "Allow HealthKit access to track steps, calories, and workout data."
                    )
                    Button {
                        Task {
                            try? await services.healthKit.requestAuthorization()
                            healthKitAuthorized = true
                        }
                    } label: {
                        Text("Authorize")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidePrimary)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, TideTrain.pageBottom)
        }
        .tidePage()
        .navigationTitle("Move")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: completedWorkouts.first?.id) {
            await loadLastSessionHR()
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
        let end = last.finishedAt ?? last.date
        let start = last.startedAt ?? end.addingTimeInterval(-Double(last.durationMinutes ?? 60) * 60)
        var samples = await (try? services.healthKit.fetchWorkouts(for: end)) ?? []
        if !Calendar.current.isDate(start, inSameDayAs: end) {
            samples += await (try? services.healthKit.fetchWorkouts(for: start)) ?? []
        }
        // Only the HK workout that actually overlaps this session — never
        // another activity from the same day.
        let avg = WorkoutSample.bestOverlap(start: start, end: end, in: samples)?.averageHeartRate
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
        VStack(alignment: .leading, spacing: Tide.s1) {
            switch data.workoutStatus {
            case .completed:
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Tide.headline)
                        .foregroundStyle(TideTrain.positive)
                        .accessibilityHidden(true)
                    Text(data.workoutName ?? "Workout")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("\(data.formattedWorkoutDuration) · \(data.formattedActiveCalories)")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(workoutQuip)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)

            case .planned:
                Text(data.workoutName ?? "Workout")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Planned. Tap to start.")
                    .font(Tide.body)
                    .foregroundStyle(TideTrain.caution)

            case .restDay:
                Text("Rest Day")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                Text("Growth happens in the recovery.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)

            case .none:
                Text("No workout today")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)

                Button {
                    // Was an EMPTY closure — a dead-end that looked tappable.
                    // Generate today's plan through the same pipeline the
                    // Training tab uses; the .tempoWorkoutChanged fan-out then
                    // flips the Dashboard's workoutStatus to .planned.
                    Task { @MainActor in
                        await services.workoutSession.viewModel.loadToday(modelContext: modelContext)
                        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
                        HapticManager.notification(.success)
                    }
                } label: {
                    Text("+ Plan Workout")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(TideTrain.caution)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Today's Activity

    // Per MODULE_DASHBOARD.md Section 4.5 — Today's Activity

    private var todayActivitySection: some View {
        let stepsSubtitle = "/\(NumberFormatter.localizedString(from: NSNumber(value: data.stepsTarget), number: .decimal))"
        let stats = Group {
            activityCard(value: data.formattedSteps, label: "Steps", subtitle: stepsSubtitle)
            activityCard(value: data.formattedActiveCalories, label: "Active Cal", subtitle: nil)
            activityCard(value: data.formattedStrain, label: "Strain", subtitle: nil)
        }
        return VStack(spacing: Tide.s3) {
            // Three stat cards; one per row once the text gets large.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s3) {
                    stats
                }
                VStack(spacing: Tide.s2) {
                    stats
                }
            }

            // Steps progress bar
            HStack(spacing: Tide.s2) {
                TideLevelBar(progress: min(data.stepsProgress, 1.0), color: TideTrain.caution, height: Tide.bar)

                Text("\(Int(min(data.stepsProgress, 1.0) * 100))%")
                    .font(TideTrain.figure(.footnote, weight: .semibold))
                    .foregroundStyle(Tide.text2)
                    .fixedSize()
            }

            // Step pace projection
            Text(stepPaceProjection)
                .font(Tide.caption)
                .foregroundStyle(stepPaceColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tideCard(padding: Tide.s4)
    }

    private func activityCard(value: String, label: String, subtitle: String?) -> some View {
        // All three cards are identical: same minimum height, same value font
        // (no minimumScaleFactor so "1332" and "5.0" render at the same
        // size), and the subtitle line's space is always reserved so a card
        // with no subtitle is exactly as tall as one that has it.
        VStack(spacing: Tide.hair) {
            Text(value)
                .font(TideTrain.figure(.title2))
                .foregroundStyle(Tide.text)
                .lineLimit(1)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
            Text(subtitle ?? " ")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .lineLimit(1)
        }
        .padding(.vertical, Tide.s2)
        .frame(maxWidth: .infinity)
        .frame(minHeight: TideTrain.statColumn)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                .stroke(Tide.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Heart Rate Section

    // Per MODULE_DASHBOARD.md Section 4.5 — post-workout HR summary only.
    // No live HR streaming (no Apple Watch — see build constraints).

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Heart rate")

            switch lastSessionAvgHR {
            case .none:
                // Not yet loaded — quiet placeholder, no spinner churn.
                Text("—")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text3)
            case let .some(.some(avg)):
                Text("Last session avg: \(Int(avg.rounded())) bpm")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let last = completedWorkouts.first {
                    Text(last.type.displayName + " · " + (last.finishedAt ?? last.date)
                        .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            case .some(.none):
                // Loaded, but no HKWorkout HR for this session.
                Text("No HR data recorded")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Workout History

    // Per MODULE_DASHBOARD.md Section 4.5 — real completed sessions only.

    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Workout history")

            let recent = Array(completedWorkouts.prefix(5))
            if recent.isEmpty {
                Text("No workouts recorded yet.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tide.s4)
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 {
                        TrainPlanDivider()
                    }
                    historyRow(workout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    private func historyRow(_ workout: WorkoutPlan) -> some View {
        let day = Text((workout.finishedAt ?? workout.date).formatted(.dateTime.weekday(.abbreviated)))
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
        let name = Text(workout.type.displayName)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
        let dur = workout.durationMinutes ?? workout.actualDurationMinutes
        let detail = Text(Self.volumeHistoryLabel(durationMinutes: dur, volumeKg: workout.totalVolume, unit: weightUnit))
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                day
                    .frame(width: TideTrain.rowThumb, alignment: .leading)
                name
                Spacer(minLength: Tide.s2)
                detail
            }
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(spacing: Tide.s2) {
                    day
                    name
                }
                detail
            }
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "52m · 4.2k kg"; a session with no lifted volume (a run, mobility)
    /// shows just its duration, never "0 kg".
    static func volumeHistoryLabel(durationMinutes: Int?, volumeKg: Double, unit: WeightUnit) -> String {
        var parts: [String] = []
        if let dur = durationMinutes {
            parts.append("\(dur)m")
        }
        if volumeKg > 0 {
            parts.append(WeightFormat.volumeText(kg: volumeKg, unit: unit))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Weekly Volume Chart

    // Per MODULE_DASHBOARD.md Section 4.5 — training volume from completed
    // sets (actual weight × actual reps), NOT active calories.

    private var weeklyVolumeSection: some View {
        let trend = weeklyVolumeTrend
        let unit = weightUnit.abbreviation
        let totalVol = trend.reduce(0.0) { $0 + $1.volume }
        let workoutDays = trend.count(where: { $0.volume > 0 })

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Weekly volume")

            if totalVol == 0 {
                Text("No completed sets this week.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tide.s4)
            } else {
                Chart(trend) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(TideTrain.caution)
                    .cornerRadius(Tide.s1)
                }
                // Large text: every other day label and no value axis, so
                // the labels never run into each other.
                .chartYAxis(typeSize.isAccessibilitySize ? .hidden : .automatic)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: typeSize.isAccessibilitySize ? 2 : 1)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text3)
                            }
                        }
                    }
                }
                .frame(height: typeSize.isAccessibilitySize ? TideTrain.chartHeight : TideTrain.barsHeight)

                Text(
                    "Total: \(NumberFormatter.localizedString(from: NSNumber(value: Int(totalVol)), number: .decimal)) \(unit) · \(workoutDays) \(workoutDays == 1 ? "session" : "sessions")"
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Start Workout Button

    // Per MODULE_DASHBOARD.md Section 4.5

    private var startWorkoutButton: some View {
        Button {
            Task { @MainActor in
                // The shared session: a second tap while it is starting, or
                // while it is already on screen, never starts another.
                _ = await services.workoutSession.start(modelContext: modelContext)
            }
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tidePrimary)
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
            return Tide.text2
        }
        let calendar = Calendar.current
        let hoursElapsed = Date().timeIntervalSince(calendar.startOfDay(for: Date())) / 3600
        guard hoursElapsed >= 1 else {
            return Tide.text2
        }
        let projected = Int(Double(steps) / hoursElapsed * 16)
        if projected >= data.stepsTarget {
            return TideTrain.positive
        }
        if projected < Int(Double(data.stepsTarget) * 0.8) {
            return TideTrain.caution
        }
        return Tide.text2
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
