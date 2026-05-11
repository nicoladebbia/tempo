//
// WeeklyAccountabilityView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - WeeklyAccountabilityView

// Shows a 7-day accountability report card with completion rates,
// study time breakdown, streak history, and letter grades per category.

struct WeeklyAccountabilityView: View {
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var weekData: WeeklyAccountabilityData?
    @State
    private var isLoading = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if isLoading {
                loadingState
            } else if let data = weekData {
                reportContent(data)
            } else {
                emptyState
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("WEEKLY REPORT CARD")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadWeekData() }
    }

    // MARK: - Report Content

    private func reportContent(_ data: WeeklyAccountabilityData) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            // Period header
            Text(data.periodText)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.top, TempoSpacing.sm)

            // Overall grade
            overallGradeSection(data)

            // Completion rate ring
            completionRateSection(data)

            // Per-category grades
            categoryGradesSection(data)

            // Daily breakdown
            dailyBreakdownSection(data)

            // Study time chart
            studyTimeSection(data)

            // Streak history
            streakSection(data)

            // Best/worst days
            highlightsSection(data)

            Spacer().frame(height: TempoSpacing.xxxl)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Overall Grade

    private func overallGradeSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            Text(data.overallGrade.letter)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundStyle(gradeColor(data.overallGrade))

            Text("Overall Accountability Grade")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(data.overallGrade.description)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)
        }
        .padding(.vertical, TempoSpacing.lg)
    }

    // MARK: - Completion Rate

    private func completionRateSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            CircularRingView(
                progress: data.overallCompletionRate,
                color: completionColor(data.overallCompletionRate),
                ringSize: .large,
                label: "Completion",
                valueText: "\(Int(data.overallCompletionRate * 100))%"
            )

            Text("\(data.totalCompleted)/\(data.totalTasks) non-negotiables completed this week")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    // MARK: - Category Grades

    private func categoryGradesSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("CATEGORY GRADES")
                .font(.tempoCaption2)
                .tracking(1)
                .foregroundStyle(Color.tempoTextTertiary)

            ForEach(data.categoryGrades, id: \.name) { category in
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: category.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(gradeColor(category.grade))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Text("\(category.daysCompleted)/7 days completed")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }

                    Spacer()

                    Text(category.grade.letter)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(gradeColor(category.grade))

                    // Mini progress bar
                    LinearProgressBar(
                        progress: Double(category.daysCompleted) / 7.0,
                        color: gradeColor(category.grade),
                        height: 4,
                        showPercentage: false
                    )
                    .frame(width: 40)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                        .stroke(Color.tempoBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Daily Breakdown

    private func dailyBreakdownSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("DAILY BREAKDOWN")
                .font(.tempoCaption2)
                .tracking(1)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.xs) {
                ForEach(data.dailyResults, id: \.dayName) { day in
                    VStack(spacing: TempoSpacing.xs) {
                        Text(day.dayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.tempoTextSecondary)

                        ZStack {
                            Circle()
                                .fill(day.allComplete ? Color
                                    .tempoSuccess : (day.completionRate > 0 ? Color.tempoAmber : Color.tempoBorder))
                                .frame(width: 36, height: 36)

                            if day.allComplete {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if day.completionRate > 0 {
                                Text("\(Int(day.completionRate * 100))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("--")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                        }

                        Text("\(day.studyMinutes)m")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(TempoSpacing.md)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Study Time

    private func studyTimeSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STUDY TIME")
                .font(.tempoCaption2)
                .tracking(1)
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: TempoSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text(formatStudyTime(data.totalStudyMinutes))
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Daily Average")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text(formatStudyTime(data.averageStudyMinutes))
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoElectric)
                    }
                }

                // Mini bar chart for daily study
                HStack(alignment: .bottom, spacing: TempoSpacing.xs) {
                    ForEach(data.dailyResults, id: \.dayName) { day in
                        VStack(spacing: 2) {
                            let maxMinutes = max(1, data.dailyResults.map(\.studyMinutes).max() ?? 1)
                            let height = max(4, CGFloat(day.studyMinutes) / CGFloat(maxMinutes) * 60)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.studyMinutes > 0 ? Color.tempoElectric : Color.tempoBorder)
                                .frame(height: height)

                            Text(day.dayName)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Streak Section

    private func streakSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STREAK")
                .font(.tempoCaption2)
                .tracking(1)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.lg) {
                VStack(spacing: TempoSpacing.xs) {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.tempoAmber)
                        Text("\(data.currentStreak)")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    Text("Current")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Divider().frame(height: 50)

                VStack(spacing: TempoSpacing.xs) {
                    Text("\(data.longestStreak)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("Longest")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Divider().frame(height: 50)

                VStack(spacing: TempoSpacing.xs) {
                    Text("\(data.perfectDays)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Perfect Days")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Highlights

    private func highlightsSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("HIGHLIGHTS")
                .font(.tempoCaption2)
                .tracking(1)
                .foregroundStyle(Color.tempoTextTertiary)

            if let best = data.bestDay {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.tempoSuccess)

                    Text("Best Day: \(best.dayFullName)")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Spacer()

                    Text("\(Int(best.completionRate * 100))%")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoSuccess)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSuccess.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }

            if let worst = data.worstDay {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.tempoSignal)

                    Text("Weakest Day: \(worst.dayFullName)")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Spacer()

                    Text("\(Int(worst.completionRate * 100))%")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoSignal)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSignal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
        }
    }

    // MARK: - Loading & Empty States

    private var loadingState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            ProgressView()
            Text("Crunching your week...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No data yet")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Complete at least one full day of non-negotiables to see your weekly report card.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer()
        }
    }

    // MARK: - Data Loading

    private func loadWeekData() {
        isLoading = true

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Get start of current week (Monday)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Monday = 0
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            isLoading = false
            return
        }

        // Fetch all DailyAccountability records for this week
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let descriptor = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { da in
                da.date >= weekStart && da.date < weekEnd
            },
            sortBy: [SortDescriptor(\.date)]
        )

        guard let accountabilities = try? modelContext.fetch(descriptor) else {
            isLoading = false
            return
        }

        // Fetch streaks
        let overallRaw = "overall"
        let streakDescriptor = FetchDescriptor<Streak>(
            predicate: #Predicate { s in s.typeRaw == overallRaw }
        )
        let overallStreak = try? modelContext.fetch(streakDescriptor).first

        // Build daily results
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayFullNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var dailyResults: [DailyResult] = []

        for i in 0 ..< 7 {
            guard let dayDate = calendar.date(byAdding: .day, value: i, to: weekStart) else {
                continue
            }
            let dayData = accountabilities.first { calendar.isDate($0.date, inSameDayAs: dayDate) }

            let completed = dayData?.completedCount ?? 0
            let total = dayData?.totalCount ?? 0
            let rate = total > 0 ? Double(completed) / Double(total) : 0

            dailyResults.append(DailyResult(
                dayName: dayNames[i],
                dayFullName: dayFullNames[i],
                completionRate: rate,
                allComplete: dayData?.allComplete ?? false,
                studyMinutes: dayData?.totalStudyMinutes ?? 0
            ))
        }

        // Category grades
        var categoryData: [String: (completed: Int, total: Int, icon: String)] = [:]
        let categoryDefs: [(NonNegotiableType, String, String)] = [
            (.study, "Study", "book.fill"),
            (.train, "Training", "dumbbell.fill"),
            (.meals, "Meals", "fork.knife"),
        ]

        for (type, name, icon) in categoryDefs {
            var completed = 0
            var total = 0

            for accountability in accountabilities {
                let progress = (accountability.nonNegotiableProgress ?? [])
                    .filter { $0.nonNegotiable?.type == type }
                total += progress.count
                completed += progress.filter(\.isCompleted).count
            }

            categoryData[name] = (completed, total, icon)
        }

        let categoryGrades: [CategoryGrade] = categoryDefs.map { _, name, icon in
            let data = categoryData[name] ?? (0, 0, icon)
            let daysCompleted = data.total > 0
                ? Int(round(Double(data.completed) / max(1, Double(data.total)) * 7))
                : 0
            return CategoryGrade(
                name: name,
                icon: icon,
                daysCompleted: min(7, daysCompleted),
                grade: letterGrade(from: data.total > 0 ? Double(data.completed) / Double(data.total) : 0)
            )
        }

        // Totals
        let totalCompleted = accountabilities.reduce(0) { $0 + $1.completedCount }
        let totalTasks = accountabilities.reduce(0) { $0 + $1.totalCount }
        let overallRate = totalTasks > 0 ? Double(totalCompleted) / Double(totalTasks) : 0
        let totalStudy = accountabilities.reduce(0) { $0 + $1.totalStudyMinutes }
        let activeDays = max(1, accountabilities.count)
        let perfectDays = dailyResults.filter(\.allComplete).count

        // Best/worst (only among days with data)
        let daysWithData = dailyResults.filter { $0.completionRate > 0 || $0.allComplete }
        let bestDay = daysWithData.max(by: { $0.completionRate < $1.completionRate })
        let worstDay = daysWithData.min(by: { $0.completionRate < $1.completionRate })

        // Period text
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: weekStart)
        formatter.dateFormat = "MMM d, yyyy"
        let endDate = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let endStr = formatter.string(from: endDate)

        weekData = WeeklyAccountabilityData(
            periodText: "\(startStr) - \(endStr)",
            overallGrade: letterGrade(from: overallRate),
            overallCompletionRate: overallRate,
            totalCompleted: totalCompleted,
            totalTasks: totalTasks,
            categoryGrades: categoryGrades,
            dailyResults: dailyResults,
            totalStudyMinutes: totalStudy,
            averageStudyMinutes: totalStudy / activeDays,
            currentStreak: overallStreak?.currentCount ?? 0,
            longestStreak: overallStreak?.longestCount ?? 0,
            perfectDays: perfectDays,
            bestDay: bestDay,
            worstDay: worstDay != bestDay ? worstDay : nil
        )

        isLoading = false
    }

    // MARK: - Helpers

    private func letterGrade(from rate: Double) -> LetterGrade {
        switch rate {
        case 0.95 ... 1.0: .aPlus
        case 0.90 ..< 0.95: .a
        case 0.85 ..< 0.90: .aMinus
        case 0.80 ..< 0.85: .bPlus
        case 0.75 ..< 0.80: .b
        case 0.70 ..< 0.75: .bMinus
        case 0.65 ..< 0.70: .cPlus
        case 0.60 ..< 0.65: .c
        case 0.50 ..< 0.60: .d
        default: rate >= 0.95 ? .aPlus : .f
        }
    }

    private func gradeColor(_ grade: LetterGrade) -> Color {
        switch grade {
        case .aPlus,
             .a,
             .aMinus: .tempoSuccess
        case .bPlus,
             .b,
             .bMinus: .tempoElectric
        case .cPlus,
             .c: .tempoAmber
        case .d: .tempoSignal
        case .f: .tempoSignal
        }
    }

    private func completionColor(_ rate: Double) -> Color {
        if rate >= 0.9 {
            return .tempoSuccess
        }
        if rate >= 0.7 {
            return .tempoElectric
        }
        if rate >= 0.5 {
            return .tempoAmber
        }
        return .tempoSignal
    }

    private func formatStudyTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

// MARK: - WeeklyAccountabilityData

struct WeeklyAccountabilityData {
    let periodText: String
    let overallGrade: LetterGrade
    let overallCompletionRate: Double
    let totalCompleted: Int
    let totalTasks: Int
    let categoryGrades: [CategoryGrade]
    let dailyResults: [DailyResult]
    let totalStudyMinutes: Int
    let averageStudyMinutes: Int
    let currentStreak: Int
    let longestStreak: Int
    let perfectDays: Int
    let bestDay: DailyResult?
    let worstDay: DailyResult?
}

// MARK: - CategoryGrade

struct CategoryGrade {
    let name: String
    let icon: String
    let daysCompleted: Int
    let grade: LetterGrade
}

// MARK: - DailyResult

struct DailyResult: Equatable {
    let dayName: String
    let dayFullName: String
    let completionRate: Double
    let allComplete: Bool
    let studyMinutes: Int
}

// MARK: - LetterGrade

enum LetterGrade {
    case aPlus
    case a
    case aMinus
    case bPlus
    case b
    case bMinus
    case cPlus
    case c
    case d
    case f

    var letter: String {
        switch self {
        case .aPlus: "A+"
        case .a: "A"
        case .aMinus: "A-"
        case .bPlus: "B+"
        case .b: "B"
        case .bMinus: "B-"
        case .cPlus: "C+"
        case .c: "C"
        case .d: "D"
        case .f: "F"
        }
    }

    var description: String {
        switch self {
        case .aPlus: "Outstanding. You're a machine."
        case .a: "Excellent discipline. Keep this up."
        case .aMinus: "Great week. Room for one more push."
        case .bPlus: "Solid effort. Close to greatness."
        case .b: "Good work. Consistency is key."
        case .bMinus: "Decent. You can do better."
        case .cPlus: "Average. Your goals deserve more."
        case .c: "Mediocre. Time to step up."
        case .d: "Poor. This isn't who you want to be."
        case .f: "Failed. Reset. Tomorrow starts now."
        }
    }
}
