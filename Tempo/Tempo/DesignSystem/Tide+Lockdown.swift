//
// Tide+Lockdown.swift
// Tempo
//
// Lockdown's own Tide pieces: the week of streak days and the 365-day
// history grid. They take the same data as the older shared views but draw it
// in Tide colours, with room for a finger.
//

import SwiftUI

// MARK: - TideStreakDots

/// One column per day of the week, Monday first: a letter above a disc that is
/// lit when the day was completed, ringed when it was missed, and carries the
/// mood colour for today.
struct TideStreakDots: View {
    let days: [StreakDotsView.DayStatus]

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .body)
    private var disc: CGFloat = 32

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                VStack(spacing: Tide.s2) {
                    Text(Self.shortName(index)).tideLabel(Tide.text3)
                    dot(status)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Self.fullName(index)), \(spoken(status))")
            }
        }
        .animation(Tide.snap, value: days.map(\.isCompleted))
    }

    @ViewBuilder
    private func dot(_ status: StreakDotsView.DayStatus) -> some View {
        switch status {
        case .completed:
            lit
        case .missed:
            Circle()
                .fill(Tide.danger.opacity(0.16))
                .overlay(Circle().strokeBorder(Tide.danger.opacity(0.55), lineWidth: Tide.rule))
                .overlay(Image(systemName: "xmark").font(Tide.label).foregroundStyle(Tide.danger))
                .frame(width: disc, height: disc)
        case let .today(completed):
            if completed {
                lit
            } else {
                Circle()
                    .fill(mood.accent.opacity(0.14))
                    .overlay(Circle().strokeBorder(mood.accent, lineWidth: Tide.hair))
                    .overlay(Circle().fill(mood.accent).frame(width: Tide.s2, height: Tide.s2))
                    .frame(width: disc, height: disc)
            }
        case .future:
            Circle()
                .strokeBorder(Tide.hairline, lineWidth: Tide.rule)
                .frame(width: disc, height: disc)
        }
    }

    private var lit: some View {
        Circle()
            .fill(TideTone.mint)
            .overlay(Image(systemName: "checkmark").font(Tide.label).foregroundStyle(Tide.ink))
            .frame(width: disc, height: disc)
    }

    private func spoken(_ status: StreakDotsView.DayStatus) -> String {
        switch status {
        case .completed: "completed"
        case .missed: "missed"
        case let .today(completed): completed ? "today, completed" : "today, in progress"
        case .future: "upcoming"
        }
    }

    /// Monday-first single letters ("M", "T", ...), in the user's language.
    private static func shortName(_ index: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(index + 1) % 7]
    }

    private static func fullName(_ index: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(index + 1) % 7]
    }
}

// MARK: - TideHeatmap

/// A year of days as a grid of weeks, lit mint by how much of the day was done.
/// Cells are big enough to read and tap: the grid scrolls sideways and opens on
/// the most recent weeks. Tap a day for its figure.
struct TideHeatmap: View {
    let data: [Date: Double]
    let startDate: Date
    let endDate: Date

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .caption2)
    private var labelHeight: CGFloat = 14
    @State
    private var selectedDate: Date?

    private let cell: CGFloat = Tide.s3
    private let gap: CGFloat = Tide.s1 - Tide.rule
    private let dayLabelWidth: CGFloat = Tide.s5

    init(data: [Date: Double], startDate: Date? = nil, endDate: Date? = nil) {
        self.data = data
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endDate ?? Date())
        self.endDate = end
        self.startDate = startDate ?? calendar.date(byAdding: .day, value: -364, to: end) ?? end
    }

    // MARK: Geometry

    private var step: CGFloat {
        cell + gap
    }

    /// The first day of the week that holds `startDate`, so rows are weekdays.
    private var gridStart: Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: startDate)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: startDate) ?? startDate
    }

    private var dayCount: Int {
        max(0, (Calendar.current.dateComponents([.day], from: gridStart, to: endDate).day ?? 0) + 1)
    }

    private var weekCount: Int {
        (dayCount + 6) / 7
    }

    private var gridWidth: CGFloat {
        CGFloat(weekCount) * step - gap
    }

    private var gridHeight: CGFloat {
        7 * step - gap
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s1) {
                dayLabels

                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        monthLabels
                        grid
                    }
                    .padding(.trailing, Tide.hair)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }

            footer
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("History, last \(dayCount) days")
        .accessibilityValue(spokenSummary)
    }

    private var dayLabels: some View {
        VStack(spacing: gap) {
            Color.clear.frame(width: dayLabelWidth, height: labelHeight + Tide.s1)
            ForEach(0 ..< 7, id: \.self) { row in
                Text(row.isMultiple(of: 2) ? dayLabel(row) : "")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: dayLabelWidth, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks, id: \.week) { mark in
                Text(mark.label)
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .fixedSize()
                    .offset(x: CGFloat(mark.week) * step)
            }
        }
        .frame(width: gridWidth, height: labelHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        Canvas { context, _ in
            let calendar = Calendar.current
            for offset in 0 ..< dayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                    continue
                }
                if day < startDate {
                    continue
                }
                let column = offset / 7
                let row = offset % 7
                let rect = CGRect(
                    x: CGFloat(column) * step,
                    y: CGFloat(row) * step,
                    width: cell,
                    height: cell
                )
                let path = Path(roundedRect: rect, cornerRadius: Tide.hair)
                let value = data[calendar.startOfDay(for: day)] ?? 0
                context.fill(path, with: .color(color(for: value)))

                if calendar.isDateInToday(day) {
                    context.stroke(path, with: .color(Tide.text), lineWidth: Tide.rule)
                }
                if let selectedDate, calendar.isDate(day, inSameDayAs: selectedDate) {
                    context.stroke(path, with: .color(mood.accent), lineWidth: Tide.hair)
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight)
        .contentShape(.rect)
        .gesture(
            SpatialTapGesture()
                .onEnded { tap in
                    let picked = date(at: tap.location)
                    withAnimation(Tide.snap) {
                        selectedDate = picked == selectedDate ? nil : picked
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    @ViewBuilder
    private var footer: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))

        layout {
            tooltip
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            legend
        }
    }

    @ViewBuilder
    private var tooltip: some View {
        if let selectedDate {
            let value = data[Calendar.current.startOfDay(for: selectedDate)] ?? 0
            HStack(spacing: Tide.s2) {
                Text(selectedDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Text("\(Int((value * 100).rounded()))%")
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .bold))
                    .foregroundStyle(Tide.text)
            }
        } else {
            Text("Tap a day").font(Tide.caption).foregroundStyle(Tide.text3)
        }
    }

    private var legend: some View {
        HStack(spacing: Tide.s1) {
            Text("Less").font(Tide.label).foregroundStyle(Tide.text3)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: Tide.hair)
                    .fill(color(for: level))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(Tide.label).foregroundStyle(Tide.text3)
        }
    }

    // MARK: Helpers

    private func color(for value: Double) -> Color {
        guard value > 0 else {
            return Tide.fill
        }
        switch value {
        case ...0.25: return TideTone.mint.opacity(0.30)
        case ...0.50: return TideTone.mint.opacity(0.52)
        case ...0.75: return TideTone.mint.opacity(0.76)
        default: return TideTone.mint
        }
    }

    private func date(at point: CGPoint) -> Date? {
        let column = Int(point.x / step)
        let row = Int(point.y / step)
        guard row >= 0, row < 7, column >= 0 else {
            return nil
        }
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: column * 7 + row, to: gridStart),
              day >= startDate, day <= endDate
        else {
            return nil
        }
        return calendar.startOfDay(for: day)
    }

    private func dayLabel(_ row: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(row + Calendar.current.firstWeekday - 1) % 7]
    }

    /// The column where each month's first week starts.
    private var monthMarks: [(week: Int, label: String)] {
        let calendar = Calendar.current
        var marks: [(week: Int, label: String)] = []
        var lastMonth = -1
        for week in 0 ..< weekCount {
            guard let day = calendar.date(byAdding: .day, value: week * 7, to: gridStart) else {
                continue
            }
            let month = calendar.component(.month, from: day)
            if month != lastMonth {
                marks.append((week, day.formatted(.dateTime.month(.abbreviated))))
                lastMonth = month
            }
        }
        // A month label squeezed against the next one is unreadable: drop it.
        return marks.enumerated().compactMap { index, mark in
            let next = index + 1 < marks.count ? marks[index + 1].week : weekCount
            return next - mark.week >= 3 ? mark : nil
        }
    }

    private var spokenSummary: String {
        let full = data.values.filter { $0 >= 0.99 }.count
        return "\(full) full days"
    }
}
