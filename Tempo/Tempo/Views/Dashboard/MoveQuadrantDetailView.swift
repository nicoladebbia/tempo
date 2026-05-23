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
// Sections: workout hero, movement load gauge, HR zone intensity profile,
// muscle group breakdown, workout history, weekly volume chart.

struct MoveQuadrantDetailView: View {
    let data: MoveQuadrantData
    @Environment(ServiceContainer.self)
    private var services
    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false

    @Query(
        filter: #Predicate<WorkoutPlan> { $0.statusRaw == "completed" },
        sort: \WorkoutPlan.date,
        order: .reverse
    )
    private var completedWorkouts: [WorkoutPlan]

    @Query
    private var userSettings: [UserSettings]

    @Query
    private var userProfiles: [UserProfile]

    // HR zones for last session — nil = not loaded, .some([]) = loaded/no data.
    @State private var lastSessionHRZones: [HRZoneMinutes]?
    // Workout window used to bound HR sample fetch (start/end of last session).
    @State private var lastSessionWindow: (start: Date, end: Date)?

    @Environment(\.modelContext)
    private var modelContext

    @State private var trainingVM: TrainingViewModel?
    @State private var showActiveWorkout = false
    @State private var showSummary = false

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    /// Tanaka formula: 208 − 0.7 × age. Neutral default 200 when age unknown
    /// so zone thresholds are still displayed (just less personalized).
    private var maxHeartRate: Double {
        if let age = userProfiles.first?.age {
            return 208 - 0.7 * Double(age)
        }
        return 200
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if data.isConnected || healthKitAuthorized {
                    workoutHeroSection
                    movementLoadGauge
                    intensityProfileSection
                    muscleGroupSection
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
            await loadLastSessionHRZones()
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
            if case .summary = newState {
                showActiveWorkout = false
                showSummary = true
            }
        }
    }

    // MARK: - Data Loaders

    private func loadLastSessionHRZones() async {
        guard let last = completedWorkouts.first else {
            lastSessionHRZones = []
            return
        }
        let sessionDate = last.finishedAt ?? last.date

        // Fetch both workout window and HR samples in parallel (isolated try? per
        // healthkit_batch_fetch_trap — individual failures must not zero others).
        async let workoutsAsync = try? await services.healthKit.fetchWorkouts(for: sessionDate)
        async let hrAsync = try? await services.healthKit.fetchHeartRate(for: sessionDate)

        let workouts = await workoutsAsync ?? []
        let hrSamples = await hrAsync ?? []

        // Match the HK workout whose window overlaps the session's finish time.
        let sessionFinish = last.finishedAt ?? last.date
        let matchedWorkout = workouts.first { w in
            w.startDate <= sessionFinish && w.endDate >= last.date
        } ?? workouts.first

        // Window: if we matched a real HK workout, filter HR samples to its
        // bounds. Otherwise use the full day (no-watch fallback).
        let window: (start: Date, end: Date)?
        if let w = matchedWorkout {
            window = (w.startDate, w.endDate)
        } else {
            window = nil
        }
        lastSessionWindow = window

        let filteredSamples: [HeartRateSample]
        if let w = window {
            filteredSamples = hrSamples.filter { $0.timestamp >= w.start && $0.timestamp <= w.end }
        } else {
            filteredSamples = hrSamples
        }

        lastSessionHRZones = computeHRZones(from: filteredSamples, maxHR: maxHeartRate)
    }

    /// Bins each HR sample into a zone by comparing bpm to max HR percentage
    /// thresholds. Each sample is counted as 1 "minute" of zone time (HealthKit
    /// HR samples are ~1/min during workouts; gap-weighting not worth it here).
    private func computeHRZones(from samples: [HeartRateSample], maxHR: Double) -> [HRZoneMinutes] {
        var counts: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for sample in samples {
            let pct = sample.bpm / maxHR
            switch pct {
            case ..<0.60: counts[1, default: 0] += 1
            case 0.60..<0.70: counts[2, default: 0] += 1
            case 0.70..<0.80: counts[3, default: 0] += 1
            case 0.80..<0.90: counts[4, default: 0] += 1
            default: counts[5, default: 0] += 1
            }
        }
        return [
            HRZoneMinutes(zone: 1, label: "Z1", color: .tempoTextTertiary, minutes: counts[1] ?? 0),
            HRZoneMinutes(zone: 2, label: "Z2", color: .tempoSleepLight, minutes: counts[2] ?? 0),
            HRZoneMinutes(zone: 3, label: "Z3", color: .tempoAmber, minutes: counts[3] ?? 0),
            HRZoneMinutes(zone: 4, label: "Z4", color: Color.orange, minutes: counts[4] ?? 0),
            HRZoneMinutes(zone: 5, label: "Z5", color: .tempoError, minutes: counts[5] ?? 0),
        ]
    }

    // MARK: - Weekly Volume (for chart + muscle breakdown)

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
            let volumeKg = plansThatDay.reduce(0.0) { acc, plan in
                acc + plan.orderedExercises.reduce(0.0) { exAcc, ex in
                    exAcc + (ex.sets ?? []).reduce(0.0) { setAcc, set in
                        guard set.completed,
                              let w = set.actualWeight,
                              let r = set.actualReps else { return setAcc }
                        return setAcc + (w * Double(r))
                    }
                }
            }
            let displayVolume = WeightUnit.kg.convert(volumeKg, to: weightUnit)
            return TrainingVolumePoint(date: day, volume: displayVolume)
        }
    }

    // MARK: - Workout Hero

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

                Button {} label: {
                    Text("+ Plan Workout")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoAmber)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Movement Load Gauge (Proposal 1)

    // Composite 0–100 score: steps-vs-target 40%, active-cal (cap 500) 30%,
    // Whoop strain (cap 14 = "High" zone) 30%. Documented so the weights
    // can be revisited when the personalization engine ships calibration data.
    private var movementLoadScore: Double {
        let stepsScore = min(Double(data.steps ?? 0) / Double(data.stepsTarget), 1.0) * 40
        let calScore = min(Double(data.activeCalories ?? 0) / 500.0, 1.0) * 30
        let strainScore = min((data.strain ?? 0) / 14.0, 1.0) * 30
        return stepsScore + calScore + strainScore
    }

    private var loadGaugeColor: Color {
        switch movementLoadScore {
        case 70...: Color.tempoSuccess
        case 40..<70: Color.tempoAmber
        default: Color.tempoTextTertiary
        }
    }

    private var loadZoneLabel: String {
        switch movementLoadScore {
        case 70...: "Active"
        case 40..<70: "Moderate"
        default: "Low"
        }
    }

    private var movementLoadGauge: some View {
        VStack(spacing: TempoSpacing.md) {
            // Arc gauge — semicircle opens downward, so the score VStack is
            // bottom-aligned inside a 160×96 ZStack so the digits sit within
            // the arc opening rather than floating above the curve.
            ZStack(alignment: .bottom) {
                SemiCircleArc(progress: 1.0)
                    .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 180, height: 90)

                SemiCircleArc(progress: movementLoadScore / 100.0)
                    .stroke(loadGaugeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 180, height: 90)
                    .animation(.easeOut(duration: 0.6), value: movementLoadScore)

                VStack(spacing: 0) {
                    Text("\(Int(movementLoadScore))")
                        .font(.tempoScoreDisplaySmall)
                        .foregroundStyle(loadGaugeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("MOVE LOAD")
                        .font(.tempoCaption2)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .frame(width: 120)
                .padding(.bottom, 4)
            }
            .frame(width: 180, height: 96)

            // Zone label
            Text(loadZoneLabel)
                .font(.tempoCallout)
                .foregroundStyle(loadGaugeColor)

            // Component chips below the arc so the underlying signals aren't hidden.
            HStack(spacing: TempoSpacing.sm) {
                loadChip(value: data.formattedSteps, label: "Steps")
                loadChip(value: data.formattedActiveCalories, label: "Active Cal")
                loadChip(value: data.formattedStrain, label: "Strain")
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func loadChip(value: String, label: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(value)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xs)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    // MARK: - Intensity Profile (Proposal 3)

    private var intensityProfileSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("INTENSITY PROFILE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            if userProfiles.first?.age == nil {
                Text("Set your age in Settings to see HR zones.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else if lastSessionHRZones == nil {
                // Not yet loaded
                Text("—")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else if let zones = lastSessionHRZones, zones.allSatisfy({ $0.minutes == 0 }) {
                Text("No HR data recorded for last session.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else if let zones = lastSessionHRZones {
                let totalMinutes = zones.reduce(0) { $0 + $1.minutes }
                let maxMinutes = zones.map(\.minutes).max() ?? 1

                VStack(spacing: TempoSpacing.sm) {
                    // Horizontal bar per zone
                    ForEach(zones) { zone in
                        HStack(spacing: TempoSpacing.sm) {
                            Text(zone.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(zone.color)
                                .frame(width: 20, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tempoBorder).frame(height: 10)
                                    Capsule().fill(zone.color)
                                        .frame(
                                            width: maxMinutes > 0
                                                ? geo.size.width * CGFloat(zone.minutes) / CGFloat(maxMinutes)
                                                : 0,
                                            height: 10
                                        )
                                        .animation(.easeOut(duration: 0.5), value: zone.minutes)
                                }
                            }
                            .frame(height: 10)

                            Text("\(zone.minutes)m")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.tempoTextSecondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }

                    // Coaching read — static lookup, not AI
                    if let coaching = hrZoneCoachingRead(zones: zones, total: totalMinutes) {
                        Text(coaching)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .padding(.top, TempoSpacing.xs)
                    }
                }
            }

            // Session label
            if let last = completedWorkouts.first {
                Text(last.type.displayName + " · " + (last.finishedAt ?? last.date)
                    .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func hrZoneCoachingRead(zones: [HRZoneMinutes], total: Int) -> String? {
        guard total > 0 else { return nil }
        let z4 = zones.first { $0.zone == 4 }?.minutes ?? 0
        let z5 = zones.first { $0.zone == 5 }?.minutes ?? 0
        let z2 = zones.first { $0.zone == 2 }?.minutes ?? 0
        let hardMinutes = z4 + z5
        let hardFraction = Double(hardMinutes) / Double(total)

        if hardFraction > 0.4 {
            return "Pushed hard — \(hardMinutes) min in Zones 4–5. Prioritize recovery."
        } else if z2 > 15 {
            return "Good aerobic base work. Sustainable effort across the session."
        } else if hardMinutes < 5 {
            return "Low intensity session. Consider adding a few harder intervals next time."
        }
        return "Mixed effort — good tempo work this session."
    }

    // MARK: - Muscle Group Breakdown (Proposal 6)

    // Aggregates last-7-days completed sets by primary muscle group.
    // Groups by muscleGroupRaw (String) to avoid decoding @Transient in a tight
    // loop, then maps to MuscleGroup once per group key for display labels/icons.

    private var muscleGroupVolumes: [(group: MuscleGroup, volumeKg: Double)] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        var totals: [String: Double] = [:]
        for plan in completedWorkouts {
            let planDate = plan.finishedAt ?? plan.date
            guard planDate >= cutoff else { continue }
            for ex in plan.orderedExercises {
                guard let rawGroup = ex.exercise?.muscleGroupRaw else { continue }
                let vol = (ex.sets ?? []).reduce(0.0) { acc, set in
                    guard set.completed, let w = set.actualWeight, let r = set.actualReps else { return acc }
                    return acc + w * Double(r)
                }
                totals[rawGroup, default: 0] += vol
            }
        }

        return totals
            .compactMap { raw, vol -> (MuscleGroup, Double)? in
                guard let group = MuscleGroup(rawValue: raw), vol > 0 else { return nil }
                return (group, vol)
            }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    private var muscleGroupSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("MUSCLE GROUPS · 7 DAYS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            let groups = muscleGroupVolumes
            if groups.isEmpty {
                Text("No completed sets this week.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                let maxVol = groups.first?.volumeKg ?? 1

                VStack(spacing: TempoSpacing.sm) {
                    ForEach(Array(groups.prefix(6).enumerated()), id: \.element.group.rawValue) { _, pair in
                        HStack(spacing: TempoSpacing.sm) {
                            Text(pair.group.displayName)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .frame(width: 84, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.tempoBorder).frame(height: 8)
                                    Capsule().fill(Color.tempoAmber)
                                        .frame(
                                            width: geo.size.width * CGFloat(pair.volumeKg / maxVol),
                                            height: 8
                                        )
                                }
                            }
                            .frame(height: 8)

                            let dispVol = WeightUnit.kg.convert(pair.volumeKg, to: weightUnit)
                            Text(formatVolume(dispVol))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.tempoTextSecondary)
                                .frame(width: 52, alignment: .trailing)
                                .lineLimit(1)
                        }
                    }

                    if let read = muscleBalanceRead(groups: groups) {
                        Text(read)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .padding(.top, TempoSpacing.xs)
                    }
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func muscleBalanceRead(groups: [(group: MuscleGroup, volumeKg: Double)]) -> String? {
        guard groups.count >= 2 else { return nil }
        let trained = Set(groups.map(\.group))
        let legGroups: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
        let upperGroups: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps]
        let hasLegs = !trained.isDisjoint(with: legGroups)
        let hasUpper = !trained.isDisjoint(with: upperGroups)

        if hasUpper && !hasLegs {
            return "Upper-body heavy this week — no leg volume logged. Intentional?"
        } else if hasLegs && !hasUpper {
            return "Leg-dominant week — upper body hasn't moved. Intentional?"
        } else if hasLegs && hasUpper {
            return "Balanced week across major groups."
        }
        return nil
    }

    // MARK: - Workout History

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

    private var startWorkoutButton: some View {
        Button {
            Task { @MainActor in
                let vm = trainingVM ?? TrainingViewModel(
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit
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

    private func formatVolume(_ v: Double) -> String {
        let unit = weightUnit.abbreviation
        if v >= 1000 {
            return String(format: "%.1fk %@", v / 1000, unit)
        }
        return "\(Int(v)) \(unit)"
    }
}

// MARK: - HRZoneMinutes

struct HRZoneMinutes: Identifiable {
    let id = UUID()
    let zone: Int
    let label: String
    let color: Color
    let minutes: Int
}

// MARK: - TrainingVolumePoint

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
