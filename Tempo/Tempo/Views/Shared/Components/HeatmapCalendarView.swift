//
// HeatmapCalendarView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Heatmap Calendar View

// Per DESIGN_SYSTEM.md Section 8.7 — Heatmap Calendar:
// Dynamic cell sizing (fits screen width), 5 intensity levels, Canvas-based for performance.
// Cell size computed from available width via GeometryReader — no horizontal scroll needed.

struct HeatmapCalendarView: View {
    let data: [Date: Double]
    let startDate: Date
    let endDate: Date

    @Environment(\.tideMood)
    private var mood
    @State
    private var selectedDate: Date?
    @ScaledMetric(relativeTo: .headline)
    private var tipSize: CGFloat = 17

    /// Day label column width
    private let dayLabelWidth: CGFloat = 20
    private let dayLabelTrailing: CGFloat = 4
    private let cellRadius: CGFloat = 2.5

    init(data: [Date: Double], startDate: Date? = nil, endDate: Date? = nil) {
        self.data = data
        let calendar = Calendar.current
        self.endDate = endDate ?? Date()
        self.startDate = startDate ?? calendar.date(byAdding: .day, value: -364, to: self.endDate)!
    }

    /// Number of weeks in the grid
    private var weekCount: Int {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 52
        return weeks + 1
    }

    /// Calculate cell size and gap to fit within a given width
    private func cellMetrics(for availableWidth: CGFloat) -> (cellSize: CGFloat, cellGap: CGFloat) {
        let gridWidth = availableWidth - dayLabelWidth - dayLabelTrailing
        // cellSize + cellGap per column, minus one gap
        // totalWidth = weekCount * cellSize + (weekCount - 1) * cellGap
        // Use a ratio: gap = cellSize * 0.15 (roughly)
        // totalWidth = weekCount * cellSize + (weekCount - 1) * cellSize * 0.15
        // totalWidth = cellSize * (weekCount + (weekCount - 1) * 0.15)
        let ratio: CGFloat = 0.15
        let denominator = CGFloat(weekCount) + CGFloat(weekCount - 1) * ratio
        let size = gridWidth / denominator
        let gap = size * ratio
        return (cellSize: floor(size * 2) / 2, cellGap: floor(gap * 2) / 2)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = cellMetrics(for: geometry.size.width)
            VStack(alignment: .leading, spacing: Tide.s2) {
                // Month labels
                monthLabelsView(cellSize: metrics.cellSize, cellGap: metrics.cellGap)

                HStack(alignment: .top, spacing: 0) {
                    // Day labels
                    dayLabelsView(cellSize: metrics.cellSize, cellGap: metrics.cellGap)

                    // Heatmap grid — fits within available width, no scroll needed
                    heatmapGridView(cellSize: metrics.cellSize, cellGap: metrics.cellGap)
                }

                // Legend
                legendView(cellSize: metrics.cellSize)

                // Tooltip
                if let selected = selectedDate {
                    tooltipView(for: selected)
                }
            }
        }
        .frame(height: dynamicHeight)
    }

    /// Estimate total height so GeometryReader doesn't collapse
    private var dynamicHeight: CGFloat {
        // Month labels (~14) + spacing + grid (7 rows) + spacing + legend (~14) + spacing + tooltip (~20)
        // Use a conservative estimate with small cell size
        let estimatedCellSize: CGFloat = 10
        let estimatedGap: CGFloat = 1.5
        let gridHeight = 7 * (estimatedCellSize + estimatedGap) - estimatedGap
        return 14 + Tide.s2 + gridHeight + Tide.s2 + 14 + Tide.s2 + 20
    }

    // MARK: - Subviews

    private func monthLabelsView(cellSize: CGFloat, cellGap: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Offset for day labels
            Spacer().frame(width: dayLabelWidth + dayLabelTrailing)

            let months = monthPositions()
            ForEach(months, id: \.offset) { month in
                Text(month.label)
                    .font(Tide.label)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .frame(width: CGFloat(month.weeks) * (cellSize + cellGap), alignment: .leading)
            }
        }
    }

    private func dayLabelsView(cellSize: CGFloat, cellGap: CGFloat) -> some View {
        VStack(spacing: cellGap) {
            ForEach(0 ..< 7, id: \.self) { dayIndex in
                if dayIndex % 2 == 0 {
                    Text(dayLabel(for: dayIndex))
                        .font(Tide.label)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Tide.text3)
                        .frame(width: dayLabelWidth, height: cellSize, alignment: .trailing)
                } else {
                    Spacer().frame(width: dayLabelWidth, height: cellSize)
                }
            }
        }
        .padding(.trailing, dayLabelTrailing)
    }

    private func heatmapGridView(cellSize: CGFloat, cellGap: CGFloat) -> some View {
        Canvas { context, _ in
            let calendar = Calendar.current
            var current = startDate

            // Align to start of week
            let weekday = calendar.component(.weekday, from: current)
            let daysToSubtract = (weekday - calendar.firstWeekday + 7) % 7
            current = calendar.date(byAdding: .day, value: -daysToSubtract, to: current)!

            while current <= endDate {
                let dayOfWeek = (calendar.component(.weekday, from: current) - calendar.firstWeekday + 7) % 7
                let weekIndex = calendar.dateComponents([.weekOfYear], from: startDate, to: current).weekOfYear ?? 0

                let x = CGFloat(weekIndex) * (cellSize + cellGap)
                let y = CGFloat(dayOfWeek) * (cellSize + cellGap)
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                let path = Path(roundedRect: rect, cornerRadius: cellRadius)

                let intensity = data[calendar.startOfDay(for: current)] ?? 0
                let color = cellColor(for: intensity)
                context.fill(path, with: .color(color))

                // Today border
                if calendar.isDateInToday(current) {
                    context.stroke(path, with: .color(Tide.text), lineWidth: 1)
                }

                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
        }
        .frame(
            width: CGFloat(weekCount) * (cellSize + cellGap) - cellGap,
            height: 7 * (cellSize + cellGap) - cellGap
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    selectedDate = dateAt(point: value.location, cellSize: cellSize, cellGap: cellGap)
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        selectedDate = nil
                    }
                }
        )
    }

    private func legendView(cellSize: CGFloat) -> some View {
        HStack(spacing: Tide.s1) {
            Spacer()
            Text("Less")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)

            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: cellRadius)
                    .fill(cellColor(for: intensity))
                    .frame(width: cellSize, height: cellSize)
            }

            Text("More")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
        }
    }

    @ViewBuilder
    private func tooltipView(for date: Date) -> some View {
        let value = data[Calendar.current.startOfDay(for: date)] ?? 0
        HStack(spacing: Tide.s2) {
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
            Text(String(format: "%.0f%%", value * 100))
                .font(Tide.numeral(tipSize))
                .foregroundStyle(Tide.text)
        }
    }

    // MARK: - Helpers

    /// Empty days are a faint cell; the more of the day was done, the brighter
    /// the mood accent.
    private func cellColor(for intensity: Double) -> Color {
        guard intensity > 0 else {
            return Tide.fill
        }
        let level = min(max(ceil(intensity * 4) / 4, 0.25), 1)
        return mood.accent.opacity(0.22 + 0.78 * level)
    }

    private func dateAt(point: CGPoint, cellSize: CGFloat, cellGap: CGFloat) -> Date? {
        let calendar = Calendar.current
        let col = Int(point.x / (cellSize + cellGap))
        let row = Int(point.y / (cellSize + cellGap))
        guard row >= 0, row < 7 else {
            return nil
        }

        let weekday = calendar.component(.weekday, from: startDate)
        let startOffset = (weekday - calendar.firstWeekday + 7) % 7
        var baseDate = calendar.date(byAdding: .day, value: -startOffset, to: startDate)!
        baseDate = calendar.date(byAdding: .day, value: col * 7 + row, to: baseDate)!
        guard baseDate >= startDate, baseDate <= endDate else {
            return nil
        }
        return calendar.startOfDay(for: baseDate)
    }

    private func dayLabel(for index: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday - 1
        return symbols[(index + firstWeekday) % 7]
    }

    private func monthPositions() -> [(offset: Int, label: String, weeks: Int)] {
        let calendar = Calendar.current
        var result: [(offset: Int, label: String, weeks: Int)] = []
        var current = startDate
        var lastMonth = -1

        while current <= endDate {
            let month = calendar.component(.month, from: current)
            if month != lastMonth {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                result.append((offset: result.count, label: formatter.string(from: current), weeks: 0))
                lastMonth = month
            }
            if !result.isEmpty {
                result[result.count - 1].weeks += 1
            }
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }
        return result
    }
}
