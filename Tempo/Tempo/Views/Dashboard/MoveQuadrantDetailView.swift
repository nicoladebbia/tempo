import SwiftUI
import Charts

// MARK: - Move Quadrant Detail View
// Per MODULE_DASHBOARD.md Section 4.5 — Move Expanded View.
// Workout hero, activity stats, steps progress, heart rate section,
// workout history, weekly volume chart.

struct MoveQuadrantDetailView: View {

    let data: MoveQuadrantData

    // Stub workout history
    private let workoutHistory: [WorkoutHistoryItem] = [
        WorkoutHistoryItem(day: "Today", name: "Upper Body Push", duration: 55, calories: 342),
        WorkoutHistoryItem(day: "Mon", name: "Lower Body", duration: 62, calories: 410),
        WorkoutHistoryItem(day: "Sat", name: "Full Body", duration: 48, calories: 320),
        WorkoutHistoryItem(day: "Thu", name: "Upper Body Pull", duration: 52, calories: 335),
    ]

    // Stub 7-day active calorie trend
    private let volumeTrend: [ActiveCalTrendPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let values = [420, 0, 380, 0, 335, 0, 342]
        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return ActiveCalTrendPoint(date: date, calories: values[offset + 6])
        }
    }()

    // Stub HR data
    private let heartRateData: [HRDataPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (6...Int(Date().timeIntervalSince(calendar.startOfDay(for: Date())) / 3600)).compactMap { hour in
            guard hour <= 24 else { return nil }
            let date = calendar.date(byAdding: .hour, value: hour, to: today)!
            let bpm: Double
            if hour >= 9 && hour <= 10 { bpm = Double.random(in: 120...165) } // Workout window
            else { bpm = Double.random(in: 55...85) }
            return HRDataPoint(time: date, bpm: bpm)
        }
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if data.isConnected {
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
                        action: {}
                    )
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, 50)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Move")
        .navigationBarTitleDisplayMode(.inline)
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
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func activityCard(value: String, label: String, subtitle: String?) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(value)
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Heart Rate Section
    // Per MODULE_DASHBOARD.md Section 4.5 — Heart Rate Section

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("HEART RATE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            if let lastHR = data.heartRateCurrent {
                Text("Current: \(lastHR) bpm")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
            } else {
                Text("No heart rate data")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // HR chart
            if !heartRateData.isEmpty {
                Chart(heartRateData) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.tempoError.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(Color.tempoError)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(TempoDateFormatters.timeOnly.string(from: date))
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                        }
                    }
                }
                .frame(height: 120)

                let bpms = heartRateData.map(\.bpm)
                if let minBPM = bpms.min(), let maxBPM = bpms.max() {
                    Text("Today's range: \(Int(minBPM)) — \(Int(maxBPM)) bpm")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Workout History
    // Per MODULE_DASHBOARD.md Section 4.5 — Workout History

    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WORKOUT HISTORY")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.bottom, TempoSpacing.md)

            if workoutHistory.isEmpty {
                Text("No workouts recorded this week.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                ForEach(Array(workoutHistory.enumerated()), id: \.element.id) { index, workout in
                    HStack(spacing: TempoSpacing.md) {
                        Text(workout.day)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .frame(width: 36, alignment: .leading)

                        Text(workout.name)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Spacer()

                        Text("\(workout.duration)m · \(workout.calories) cal")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .frame(minHeight: 44)

                    if index < workoutHistory.count - 1 {
                        Divider().background(Color.tempoDivider)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Weekly Volume Chart
    // Per MODULE_DASHBOARD.md Section 4.5 — Weekly Volume Chart

    private var weeklyVolumeSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WEEKLY VOLUME")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Chart(volumeTrend) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Calories", point.calories)
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

            // Weekly totals
            let totalCal = volumeTrend.reduce(0) { $0 + $1.calories }
            let workoutCount = volumeTrend.filter { $0.calories > 0 }.count
            Text("Total: \(NumberFormatter.localizedString(from: NSNumber(value: totalCal), number: .decimal)) cal · \(workoutCount) workouts")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("vs last week: +12%")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSuccess)
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Start Workout Button
    // Per MODULE_DASHBOARD.md Section 4.5

    private var startWorkoutButton: some View {
        Button {} label: {
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
        ["Solid session. Now recover.",
         "Done and dusted.",
         "Checked off. Next one's waiting.",
         "Work in the bank."].randomElement() ?? ""
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
        guard let steps = data.steps else { return .tempoTextSecondary }
        let calendar = Calendar.current
        let hoursElapsed = Date().timeIntervalSince(calendar.startOfDay(for: Date())) / 3600
        guard hoursElapsed >= 1 else { return .tempoTextSecondary }
        let projected = Int(Double(steps) / hoursElapsed * 16)
        if projected >= data.stepsTarget { return .tempoSuccess }
        if projected < Int(Double(data.stepsTarget) * 0.8) { return .tempoWarning }
        return .tempoTextSecondary
    }
}

// MARK: - Supporting Types

struct WorkoutHistoryItem: Identifiable {
    let id = UUID()
    let day: String
    let name: String
    let duration: Int
    let calories: Int
}

struct ActiveCalTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
}

struct HRDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let bpm: Double
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
                stepsTarget: 10_000,
                activeCalories: 342,
                heartRateCurrent: 72,
                isConnected: true,
                lastSync: Date()
            )
        )
    }
}
