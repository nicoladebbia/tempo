import SwiftUI

// MARK: - Heatmap Calendar View
// Per DESIGN_SYSTEM.md Section 8.7 — Heatmap Calendar:
// 14pt cells, 2pt gap, 3pt radius, 5 intensity levels, Canvas-based for performance.

struct HeatmapCalendarView: View {

    let data: [Date: Double]
    let startDate: Date
    let endDate: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    private let cellSize: CGFloat = 14
    private let cellGap: CGFloat = 2
    private let cellRadius: CGFloat = 3

    init(data: [Date: Double], startDate: Date? = nil, endDate: Date? = nil) {
        self.data = data
        let calendar = Calendar.current
        self.endDate = endDate ?? Date()
        self.startDate = startDate ?? calendar.date(byAdding: .day, value: -364, to: self.endDate)!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Month labels
            monthLabelsView

            HStack(alignment: .top, spacing: 0) {
                // Day labels
                dayLabelsView

                // Heatmap grid
                ScrollView(.horizontal, showsIndicators: false) {
                    heatmapGridView
                }
            }

            // Legend
            legendView

            // Tooltip
            if let selected = selectedDate {
                tooltipView(for: selected)
            }
        }
    }

    // MARK: - Subviews

    private var monthLabelsView: some View {
        HStack(spacing: 0) {
            // Offset for day labels
            Spacer().frame(width: 24)

            let months = monthPositions()
            ForEach(months, id: \.offset) { month in
                Text(month.label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: CGFloat(month.weeks) * (cellSize + cellGap), alignment: .leading)
            }
        }
    }

    private var dayLabelsView: some View {
        VStack(spacing: cellGap) {
            ForEach(0..<7, id: \.self) { dayIndex in
                if dayIndex % 2 == 0 {
                    Text(dayLabel(for: dayIndex))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(width: 20, height: cellSize, alignment: .trailing)
                } else {
                    Spacer().frame(width: 20, height: cellSize)
                }
            }
        }
        .padding(.trailing, TempoSpacing.xs)
    }

    private var heatmapGridView: some View {
        Canvas { context, size in
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
                    let borderColor = colorScheme == .dark ? Color.tempoBone : Color.tempoInk
                    context.stroke(path, with: .color(borderColor), lineWidth: 1.5)
                }

                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
        }
        .frame(width: gridWidth, height: 7 * (cellSize + cellGap) - cellGap)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    selectedDate = dateAt(point: value.location)
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        selectedDate = nil
                    }
                }
        )
    }

    private var legendView: some View {
        HStack(spacing: TempoSpacing.sm) {
            Spacer()
            Text("Less")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: cellRadius)
                    .fill(cellColor(for: intensity))
                    .frame(width: cellSize, height: cellSize)
            }

            Text("More")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    @ViewBuilder
    private func tooltipView(for date: Date) -> some View {
        let value = data[Calendar.current.startOfDay(for: date)] ?? 0
        HStack(spacing: TempoSpacing.xs) {
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(String(format: "%.0f%%", value * 100))
                .font(.tempoDataSmall)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Helpers

    private func cellColor(for intensity: Double) -> Color {
        let emptyColor = colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
            : Color.tempoBorder

        guard intensity > 0 else { return emptyColor }

        let levels: [(threshold: Double, light: Color, dark: Color)] = [
            (0.25, Color(red: 252 / 255, green: 165 / 255, blue: 165 / 255),
             Color(red: 127 / 255, green: 29 / 255, blue: 29 / 255)),
            (0.50, Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255),
             Color(red: 153 / 255, green: 27 / 255, blue: 27 / 255)),
            (0.75, Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255),
             Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)),
            (1.00, Color.tempoError,
             Color.tempoError),
        ]

        for level in levels {
            if intensity <= level.threshold {
                return colorScheme == .dark ? level.dark : level.light
            }
        }
        return colorScheme == .dark ? levels.last!.dark : levels.last!.light
    }

    private var gridWidth: CGFloat {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 52
        return CGFloat(weeks + 1) * (cellSize + cellGap)
    }

    private func dateAt(point: CGPoint) -> Date? {
        let calendar = Calendar.current
        let col = Int(point.x / (cellSize + cellGap))
        let row = Int(point.y / (cellSize + cellGap))
        guard row >= 0, row < 7 else { return nil }

        let weekday = calendar.component(.weekday, from: startDate)
        let startOffset = (weekday - calendar.firstWeekday + 7) % 7
        var baseDate = calendar.date(byAdding: .day, value: -startOffset, to: startDate)!
        baseDate = calendar.date(byAdding: .day, value: col * 7 + row, to: baseDate)!
        guard baseDate >= startDate, baseDate <= endDate else { return nil }
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
