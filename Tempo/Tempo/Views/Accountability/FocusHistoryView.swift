//
// FocusHistoryView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Focus History View

// Shows study session history with daily bar chart and aggregate stats.

struct FocusHistoryView: View {
    @Query(sort: \StudySession.startTime, order: .reverse)
    private var sessions: [StudySession]

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .caption2)
    private var heatCell: CGFloat = 14

    var body: some View {
        Group {
            if sessions.isEmpty {
                // Nothing logged: a page that says so, not a chart of empty bars and four zeros.
                ArenaEmptyPage(
                    title: "No sessions yet",
                    message: "Start a focus timer and every session lands here, with what you studied and when.",
                    art: { ArenaEmptyArt(systemImage: "timer", tint: mood.accent) }
                )
            } else {
                history
            }
        }
        .navigationTitle("Focus History")
        .navigationBarTitleDisplayMode(.large)
    }

    private var history: some View {
        TideScrollPage(spacing: Tide.s6, spacer: Tide.s2) {
            // 7-day bar chart
            weeklyChartSection

            // Aggregate stats
            statsSection

            // Subject breakdown (current week)
            subjectBreakdownSection

            // Time-of-day heatmap (last 30 days)
            heatmapSection

            // Session list
            sessionListSection
        }
    }

    // MARK: - Weekly Chart

    private var weeklyChartSection: some View {
        let days = last7DaysData
        let total = days.reduce(0) { $0 + $1.minutes }
        let bars = days.map { TempoBarChartSeries<String>.Bar(label: $0.label, value: Double($0.minutes)) }
        let series = TempoBarChartSeries(id: "minutes", label: "Minutes", color: mood.accent, bars: bars)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Last 7 days", trailing: formatMinutes(total))

            VStack(alignment: .leading, spacing: Tide.s3) {
                TideBarChart(
                    series: [series],
                    height: Tide.chartHeight,
                    emphasis: days.last?.label
                )
                .accessibilityLabel("Minutes studied, last 7 days")
                .accessibilityValue(days.map { "\($0.label) \($0.minutes) minutes" }.joined(separator: ", "))

                Text("Minutes per day").font(Tide.label).foregroundStyle(Tide.text3)
            }
            .tideCard()
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        let best = bestDay
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Stats")

            LazyVGrid(
                // One tile per row at accessibility sizes, so the numbers keep their width.
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tide.s3),
                    count: typeSize.isAccessibilitySize ? 1 : 2
                ),
                spacing: Tide.s3
            ) {
                TideMetricTile(
                    label: "Sessions",
                    value: "\(sessions.count)",
                    tint: Tide.text,
                    systemImage: "clock.fill"
                )
                TideMetricTile(
                    label: "Total time",
                    value: formattedTotalMinutes,
                    tint: Tide.text,
                    systemImage: "timer"
                )
                TideMetricTile(
                    label: "Avg focus",
                    value: "\(averageFocusScore)",
                    unit: "%",
                    tint: focusScoreColor(averageFocusScore),
                    systemImage: "brain.head.profile"
                )
                TideMetricTile(
                    label: "Best day",
                    value: best?.name ?? "--",
                    detail: best?.duration,
                    tint: TideTone.gold,
                    systemImage: "trophy.fill"
                )
            }
        }
    }

    // MARK: - Subject Breakdown

    /// Aggregate study minutes by subject for the current calendar week.
    private var subjectBreakdownData: [(subject: String, minutes: Int)] {
        let cal = Calendar.current
        let now = Date()
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now
        var bucket = [String: Int]()
        for session in sessions where session.startTime >= weekStart {
            let key = (session.subject?.isEmpty ?? true) ? "Untagged" : session.subject!
            bucket[key, default: 0] += session.durationMinutes
        }
        return bucket
            .map { (subject: $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes }
    }

    private var subjectBreakdownSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "By subject", trailing: "This week")

            let data = subjectBreakdownData
            if data.isEmpty {
                TideEmptyPanel(
                    systemImage: "books.vertical",
                    title: "No subjects logged this week"
                )
                .tideCard()
            } else {
                VStack(spacing: Tide.s4) {
                    let total = max(1, data.reduce(0) { $0 + $1.minutes })
                    ForEach(data, id: \.subject) { row in
                        subjectRow(row, total: total)
                    }
                }
                .tideCard()
            }
        }
    }

    private func subjectRow(_ row: (subject: String, minutes: Int), total: Int) -> some View {
        let fraction = Double(row.minutes) / Double(total)
        let stacks = typeSize.isAccessibilitySize
        let head = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(alignment: .leading, spacing: Tide.s2) {
            head {
                Text(row.subject)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(stacks ? 3 : 1)
                if !stacks {
                    Spacer(minLength: Tide.s2)
                }
                Text(formatMinutes(row.minutes))
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                    .foregroundStyle(Tide.text2)
            }
            TideLevelBar(progress: fraction, color: mood.accent.opacity(0.5 + 0.5 * fraction), height: Tide.barSlim)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Time-of-Day Heatmap

    /// 7 columns (Mon-Sun) × 16 rows (06:00 - 21:00) cumulative minutes
    /// across the past 30 days.
    private var heatmapBuckets: [[Int]] {
        let cal = Calendar.current
        let now = Date()
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now
        var grid = Array(repeating: Array(repeating: 0, count: 16), count: 7)
        for session in sessions where session.startTime >= thirtyDaysAgo {
            let hour = cal.component(.hour, from: session.startTime)
            let weekday = cal.component(.weekday, from: session.startTime)
            // Convert weekday (1=Sun ... 7=Sat) to Mon-first column index.
            let col = (weekday + 5) % 7
            guard hour >= 6, hour <= 21 else {
                continue
            }
            let row = hour - 6
            grid[col][row] += session.durationMinutes
        }
        return grid
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Time of day", trailing: "Last 30 days")

            let grid = heatmapBuckets
            let maxValue = max(1, grid.flatMap(\.self).max() ?? 1)
            let hasData = grid.contains { $0.contains { $0 > 0 } }

            VStack(spacing: Tide.hair) {
                // Day-of-week header
                HStack(spacing: Tide.hair) {
                    Color.clear.frame(width: Tide.s6, height: Tide.rule)
                    ForEach(Array(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].enumerated()), id: \.offset) { _, d in
                        Text(d)
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)

                ForEach(0 ..< 16, id: \.self) { row in
                    HStack(spacing: Tide.hair) {
                        Text(hourLabel(row + 6))
                            .font(Tide.axisFont)
                            .foregroundStyle(Tide.text3)
                            .frame(width: Tide.s6, alignment: .trailing)
                            .padding(.trailing, Tide.s1)
                            .accessibilityHidden(true)
                        ForEach(0 ..< 7, id: \.self) { col in
                            heatmapCell(value: grid[col][row], max: maxValue)
                        }
                    }
                }
            }
            .tideCard(padding: Tide.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Study time by weekday and hour, last 30 days")
            .accessibilityValue(hasData ? "Busiest slot \(busiestSlot(grid))" : "No sessions")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        // Show every 3rd hour to keep the column tidy.
        hour % 3 == 0 ? "\(hour)" : ""
    }

    private func heatmapCell(value: Int, max: Int) -> some View {
        let intensity = Double(value) / Double(max)
        let color = value == 0
            ? Tide.fill
            : mood.accent.opacity(0.2 + 0.8 * intensity)
        return RoundedRectangle(cornerRadius: Tide.hair)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: heatCell)
    }

    private func busiestSlot(_ grid: [[Int]]) -> String {
        var best = (col: 0, row: 0, value: -1)
        for col in 0 ..< 7 {
            for row in 0 ..< 16 where grid[col][row] > best.value {
                best = (col, row, grid[col][row])
            }
        }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return "\(names[best.col]) at \(best.row + 6):00"
    }

    // MARK: - Session List

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Recent sessions")

            if sessions.isEmpty {
                TideEmptyPanel(
                    systemImage: "timer",
                    title: "No sessions yet",
                    message: "Start a focus timer to begin tracking."
                )
                .tideCard()
            } else {
                let recent = Array(sessions.prefix(20))
                VStack(spacing: 0) {
                    ForEach(recent) { session in
                        sessionRow(session)

                        if session.id != recent.last?.id {
                            TideDivider().padding(.leading, Tide.s4)
                        }
                    }
                }
                .tideCard(padding: 0)
            }
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        let stacks = typeSize.isAccessibilitySize
        let score = session.effectiveFocusScore > 0
            ? TideNumber(
                "\(session.effectiveFocusScore)",
                unit: "%",
                size: Tide.numeralS,
                relativeTo: .headline,
                weight: .semibold,
                color: focusScoreColor(session.effectiveFocusScore)
            )
            : nil

        return HStack(alignment: stacks ? .top : .center, spacing: Tide.s3) {
            TideAreaIconTile(systemName: "book.fill", tint: mood.accent)

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(session.subject ?? "Focus Session")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(stacks ? 4 : 2)

                Text(
                    "\(session.durationFormatted) \u{00B7} \(Text(session.startTime, format: .dateTime.month(.abbreviated).day().hour().minute()))"
                )
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)

                // At large text the focus score sits under the time, not beside the name.
                if stacks, let score {
                    score
                }
            }

            if !stacks {
                Spacer(minLength: Tide.s2)

                if let score {
                    score
                }
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    private func focusScoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return TideTone.mint
        }
        if score >= 50 {
            return TideTone.amber
        }
        return Tide.danger
    }

    // MARK: - Data

    private struct DayData {
        let date: Date
        let label: String
        let minutes: Int
        let isToday: Bool
    }

    private var last7DaysData: [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        return (0 ..< 7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let dayMinutes = sessions
                .filter { $0.startTime >= dayStart && $0.startTime < nextDay }
                .reduce(0) { $0 + $1.durationMinutes }

            return DayData(
                date: date,
                label: dayFormatter.string(from: date),
                minutes: dayMinutes,
                isToday: daysAgo == 0
            )
        }
    }

    private var formattedTotalMinutes: String {
        formatMinutes(sessions.reduce(0) { $0 + $1.durationMinutes })
    }

    private func formatMinutes(_ total: Int) -> String {
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private var averageFocusScore: Int {
        let scored = sessions.filter { $0.focusScore != nil || $0.distractions > 0 }
        guard !scored.isEmpty else {
            return 0
        }
        let total = scored.reduce(0) { $0 + $1.effectiveFocusScore }
        return total / scored.count
    }

    /// The study day with the most minutes: its weekday name and total.
    private var bestDay: (name: String, duration: String)? {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var bestDay: Date?
        var bestMinutes = 0

        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }

        for (date, daySessions) in grouped {
            let totalMinutes = daySessions.reduce(0) { $0 + $1.durationMinutes }
            if totalMinutes > bestMinutes {
                bestMinutes = totalMinutes
                bestDay = date
            }
        }

        guard let best = bestDay else {
            return nil
        }

        return (dayFormatter.string(from: best), formatMinutes(bestMinutes))
    }
}
