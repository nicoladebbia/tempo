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
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .body)
    private var dayDisc: CGFloat = 32
    @State
    private var weekData: WeeklyAccountabilityData?
    @State
    private var isLoading = true

    var body: some View {
        TideScrollPage(spacing: Tide.s6, spacer: Tide.s2) {
            if isLoading {
                loadingState
            } else if let data = weekData {
                reportContent(data)
            } else {
                emptyState
            }
        }
        .navigationTitle("Weekly Report Card")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadWeekData() }
    }

    // MARK: - Report Content

    @ViewBuilder
    private func reportContent(_ data: WeeklyAccountabilityData) -> some View {
        // Overall grade and completion
        overallGradeSection(data)

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
    }

    // MARK: - Overall Grade

    private func overallGradeSection(_ data: WeeklyAccountabilityData) -> some View {
        let percent = Int((data.overallCompletionRate * 100).rounded())

        return RecoveryHero {
            TideDial(score: percent, caption: "Done", diameter: Tide.dialHero)
                .accessibilityLabel("Completion")
                .accessibilityValue("\(percent) percent")
        } side: {
            Text(data.periodText).tideLabel()

            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(data.overallGrade.letter)
                    .font(Tide.numeral(Tide.numeralL, .heavy))
                    .foregroundStyle(gradeColor(data.overallGrade))
                    .lineLimit(1)
                Text("Overall grade").tideLabel()
            }
            .accessibilityElement(children: .combine)

            Text(data.overallGrade.description)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(data.totalCompleted)/\(data.totalTasks) non-negotiables completed this week")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Category Grades

    private func categoryGradesSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Category grades")

            VStack(spacing: 0) {
                ForEach(Array(data.categoryGrades.enumerated()), id: \.element.name) { index, category in
                    categoryRow(category)

                    if index < data.categoryGrades.count - 1 {
                        TideDivider().padding(.leading, Tide.s4)
                    }
                }
            }
            .tideCard(padding: 0)
        }
    }

    private func categoryRow(_ category: CategoryGrade) -> some View {
        HStack(spacing: Tide.s3) {
            TideAreaIconTile(systemName: category.icon, tint: gradeColor(category.grade))

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(category.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)

                Text("\(category.daysCompleted)/7 days completed")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)

                TideLevelBar(
                    progress: Double(category.daysCompleted) / 7.0,
                    color: gradeColor(category.grade),
                    height: Tide.barSlim
                )
                .padding(.top, Tide.s1)
            }

            Spacer(minLength: Tide.s2)

            Text(category.grade.letter)
                .font(Tide.numeral(Tide.numeralM, .bold))
                .foregroundStyle(gradeColor(category.grade))
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Daily Breakdown

    private func dailyBreakdownSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Daily breakdown")

            HStack(spacing: Tide.s1) {
                ForEach(data.dailyResults, id: \.dayName) { day in
                    VStack(spacing: Tide.s2) {
                        Text(day.dayName)
                            .tideLabel(Tide.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)

                        dayMark(day)

                        Text("\(day.studyMinutes)m")
                            .font(Tide.axisFont)
                            .foregroundStyle(Tide.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dayDescription(day))
                }
            }
            .tideCard(padding: Tide.s3)
        }
    }

    @ViewBuilder
    private func dayMark(_ day: DailyResult) -> some View {
        if day.allComplete {
            Circle()
                .fill(TideTone.mint)
                .overlay(Image(systemName: "checkmark").font(Tide.label).foregroundStyle(Tide.ink))
                .frame(width: dayDisc, height: dayDisc)
        } else if day.completionRate > 0 {
            Circle()
                .fill(TideTone.amber.opacity(0.18))
                .overlay(Circle().strokeBorder(TideTone.amber, lineWidth: Tide.rule))
                .overlay(
                    Text("\(Int(day.completionRate * 100))")
                        .font(Tide.numeral(Tide.axisSize, .bold))
                        .foregroundStyle(TideTone.amber)
                )
                .frame(width: dayDisc, height: dayDisc)
        } else {
            Circle()
                .strokeBorder(Tide.hairline, lineWidth: Tide.rule)
                .overlay(Text("--").font(Tide.numeral(Tide.axisSize, .bold)).foregroundStyle(Tide.text3))
                .frame(width: dayDisc, height: dayDisc)
        }
    }

    private func dayDescription(_ day: DailyResult) -> String {
        let state = if day.allComplete {
            "all done"
        } else if day.completionRate > 0 {
            "\(Int(day.completionRate * 100)) percent done"
        } else {
            "nothing logged"
        }
        return "\(day.dayFullName), \(state), \(day.studyMinutes) minutes studied"
    }

    // MARK: - Study Time

    private func studyTimeSection(_ data: WeeklyAccountabilityData) -> some View {
        let bars = data.dailyResults.map {
            TempoBarChartSeries<String>.Bar(label: $0.dayName, value: Double($0.studyMinutes))
        }
        let series = TempoBarChartSeries(id: "study", label: "Study", color: mood.accent, bars: bars)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s4))

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Study time")

            VStack(alignment: .leading, spacing: Tide.s4) {
                layout {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("Total").tideLabel()
                        TideNumber(
                            formatStudyTime(data.totalStudyMinutes), size: Tide.numeralM, relativeTo: .title
                        )
                    }
                    .accessibilityElement(children: .combine)

                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }

                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Tide.s1) {
                        Text("Daily average").tideLabel()
                        TideNumber(
                            formatStudyTime(data.averageStudyMinutes),
                            size: Tide.numeralM, relativeTo: .title, color: mood.accent
                        )
                    }
                    .accessibilityElement(children: .combine)
                }

                TideBarChart(
                    series: [series],
                    height: Tide.chartHeightCompact,
                    emphasis: todayDayName
                )
                .accessibilityLabel("Study minutes per day")
                .accessibilityValue(data.dailyResults.map { "\($0.dayName) \($0.studyMinutes)" }.joined(separator: ", "))
            }
            .tideCard()
        }
    }

    /// The short name of today's weekday, matching `DailyResult.dayName` (Monday first, English).
    private var todayDayName: String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let weekday = Calendar.current.component(.weekday, from: Date())
        return names[(weekday + 5) % 7]
    }

    // MARK: - Streak Section

    private func streakSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Streak")

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))

            layout {
                streakStat(
                    label: "Current", value: data.currentStreak, color: Tide.streak, systemImage: "flame.fill"
                )
                streakStat(label: "Longest", value: data.longestStreak, color: Tide.text, systemImage: nil)
                streakStat(label: "Perfect days", value: data.perfectDays, color: TideTone.mint, systemImage: nil)
            }
            .tideCard()
        }
    }

    private func streakStat(label: String, value: Int, color: Color, systemImage: String?) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(spacing: Tide.s1 + Tide.hair) {
                if let systemImage {
                    Image(systemName: systemImage).font(Tide.label).foregroundStyle(color)
                        .accessibilityHidden(true)
                }
                Text(label).tideLabel().lineLimit(1).minimumScaleFactor(Tide.labelShrink)
            }
            TideNumber("\(value)", size: Tide.numeralM, relativeTo: .title, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Highlights

    private func highlightsSection(_ data: WeeklyAccountabilityData) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Highlights")

            if let best = data.bestDay {
                highlightRow(
                    systemImage: "star.fill",
                    text: "Best day: \(best.dayFullName)",
                    rate: best.completionRate,
                    tint: TideTone.mint
                )
            }

            if let worst = data.worstDay {
                highlightRow(
                    systemImage: "exclamationmark.triangle.fill",
                    text: "Weakest day: \(worst.dayFullName)",
                    rate: worst.completionRate,
                    tint: Tide.danger
                )
            }
        }
    }

    private func highlightRow(systemImage: String, text: String, rate: Double, tint: Color) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.headline)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)

            Spacer(minLength: Tide.s2)

            TideNumber(
                "\(Int(rate * 100))", unit: "%", size: Tide.numeralS, relativeTo: .headline, color: tint
            )
        }
        .tideTintedCard(tint, padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading & Empty States

    private var loadingState: some View {
        VStack(spacing: Tide.s4) {
            ProgressView()
                .tint(Tide.text2)
            Text("Crunching your week...")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tide.s10)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        TideEmptyPanel(
            systemImage: "chart.bar.doc.horizontal",
            title: "No data yet",
            message: "Complete at least one full day of non-negotiables to see your weekly report card."
        )
        .tideCard()
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
             .aMinus: TideTone.mint
        case .bPlus,
             .b,
             .bMinus: TideTone.sky
        case .cPlus,
             .c: TideTone.amber
        case .d,
             .f: Tide.danger
        }
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
