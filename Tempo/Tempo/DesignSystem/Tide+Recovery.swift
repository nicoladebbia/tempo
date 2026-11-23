//
// Tide+Recovery.swift
// Tempo
//
// Charts and colours for Recovery and Lockdown in the Tide look: a hairline
// grid, condensed axis numerals, a mood-coloured line with a soft area, and a
// scrub that reads the nearest point. They take the same data types as the
// old Tempo charts, so a call site only changes its name.
//

import Charts
import SwiftUI

// MARK: - Layout tokens

extension Tide {
    /// Axis numerals on a chart. Smaller than any text style, on purpose.
    static let axisSize: CGFloat = 11
    /// Standard chart heights.
    static let chartHeight: CGFloat = 180
    static let chartHeightCompact: CGFloat = 140
    /// The font every chart axis uses.
    static let axisFont = Tide.numeral(axisSize, .medium)
}

// MARK: - Zone and sleep colours

extension RecoveryZone {
    /// Green, yellow or red recovery, on the Tide palette.
    var tideColor: Color {
        switch self {
        case .green: TideTone.mint
        case .yellow: TideTone.amber
        case .red: Tide.danger
        }
    }
}

// MARK: - TideSleepStage

enum TideSleepStage {
    static let awake = Tide.streak
    static let light = TideTone.sky
    static let deep = TideTone.indigo
    static let rem = TideTone.violet
}

// MARK: - Tinted card

extension View {
    /// A glass card that carries a colour: an alert, a zone, a goal reached.
    func tideTintedCard(
        _ tint: Color, padding: CGFloat = Tide.s5, radius: CGFloat = Tide.cardRadius
    ) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: Tide.rule)
            )
    }
}

// MARK: - TideYAxisMarks

/// The value labels and hairline grid on the y axis, shared by both charts.
@AxisContentBuilder
private func tideYAxisMarks(showGrid: Bool) -> some AxisContent {
    AxisMarks(position: .trailing) { _ in
        if showGrid {
            AxisGridLine(stroke: StrokeStyle(lineWidth: Tide.rule))
                .foregroundStyle(Tide.hairline)
        }
        AxisValueLabel()
            .font(Tide.axisFont)
            .foregroundStyle(Tide.text3)
    }
}

// MARK: - TideLineChart

/// A line chart: one or more series, a soft area under each, a hairline grid.
/// Drag across it to read the nearest point.
struct TideLineChart<ID: Hashable>: View {
    let data: [TempoLineChartData<ID>]
    var height: CGFloat = Tide.chartHeight
    var showGrid = true
    /// About this many x-axis labels, one per distinct day. Nil: every day (7 or
    /// fewer points), weekly or fortnightly ticks beyond that.
    var axisDesiredCount: Int?
    /// Format for the scrub readout, e.g. one decimal.
    var valueFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0 ... 1))

    @State
    private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        Chart {
            ForEach(data) { series in
                seriesMarks(series)
            }
            selectionMarks
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            xAxisMarks
        }
        .chartYAxis {
            tideYAxisMarks(showGrid: showGrid)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selection?.date)
        .animation(reduceMotion ? nil : Tide.snap, value: selection?.date)
    }

    // MARK: Marks

    @ChartContentBuilder
    private func seriesMarks(_ series: TempoLineChartData<ID>) -> some ChartContent {
        let key = "\(series.id)"
        let fade = LinearGradient(
            colors: [series.color.opacity(0.28), series.color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        ForEach(series.points, id: \.date) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value),
                series: .value("Series", key),
                stacking: .unstacked
            )
            .foregroundStyle(fade)
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value),
                series: .value("Series", key)
            )
            .foregroundStyle(series.color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        // The latest reading is always marked.
        if let last = series.points.max(by: { $0.date < $1.date }) {
            PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                .foregroundStyle(series.color)
                .symbolSize(70)
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected = selection {
            RuleMark(x: .value("Selected", selected.date))
                .foregroundStyle(Tide.hairline)
                .lineStyle(StrokeStyle(lineWidth: Tide.rule))
                .annotation(
                    position: .top, spacing: Tide.s1,
                    overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled)
                ) {
                    readout(value: selected.value, date: selected.date)
                }
            PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                .foregroundStyle(Tide.text)
                .symbolSize(90)
        }
    }

    // MARK: Scrub

    private var selection: (date: Date, value: Double)? {
        guard let selectedDate, let first = data.first else {
            return nil
        }
        var best: TempoLineChartData<ID>.DataPoint?
        var bestGap = Double.greatestFiniteMagnitude
        for point in first.points {
            let gap = abs(point.date.timeIntervalSince(selectedDate))
            if gap < bestGap {
                best = point
                bestGap = gap
            }
        }
        guard let best else {
            return nil
        }
        return (best.date, best.value)
    }

    private func readout(value: Double, date: Date) -> some View {
        VStack(spacing: 0) {
            Text(value, format: valueFormat)
                .font(Tide.numeral(Tide.numeralS, .bold))
                .foregroundStyle(Tide.text)
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(Tide.label)
                .foregroundStyle(Tide.text2)
        }
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, Tide.s1 + Tide.hair)
        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.controlRadius))
    }

    // MARK: Axis

    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        AxisMarks(values: xAxisDates) { _ in
            AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false)
                .font(Tide.axisFont)
                .foregroundStyle(Tide.text3)
        }
    }

    /// With `axisDesiredCount`: at most that many tick dates, one per distinct
    /// day among the data, evenly sampled. Nil: every day for a short series,
    /// every 7th or 14th day for a long one.
    private var xAxisDates: [Date] {
        let calendar = Calendar.current
        var seen = Set<Date>()
        let days = (data.first?.points ?? []).map(\.date).sorted().filter {
            seen.insert(calendar.startOfDay(for: $0)).inserted
        }
        if let desired = axisDesiredCount, desired > 1, days.count > desired {
            let step = Double(days.count - 1) / Double(desired - 1)
            return (0 ..< desired).map { days[Int((Double($0) * step).rounded())] }
        }
        if axisDesiredCount != nil || days.count <= 7 {
            return days
        }
        let stride = days.count <= 30 ? 7 : 14
        return days.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }
}

// MARK: - TideBarChart

/// A bar chart: rounded tops, a hairline grid, the picked bar lit while the
/// others dim. Drag across it to read a bar.
struct TideBarChart<ID: Hashable>: View {
    let series: [TempoBarChartSeries<ID>]
    var height: CGFloat = Tide.chartHeight
    var showGrid = true
    /// The label of the bar that stays fully lit while nothing is selected.
    var emphasis: String?
    /// A dashed goal line across the chart.
    var target: Double?

    @State
    private var selectedLabel: String?

    var body: some View {
        Chart {
            ForEach(series) { item in
                barMarks(item)
            }
            targetMark
            selectionMarks
        }
        .chartXSelection(value: $selectedLabel)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(Tide.axisFont)
                    .foregroundStyle(Tide.text3)
            }
        }
        .chartYAxis {
            tideYAxisMarks(showGrid: showGrid)
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selectedLabel)
    }

    @ChartContentBuilder
    private func barMarks(_ item: TempoBarChartSeries<ID>) -> some ChartContent {
        let key = "\(item.id)"
        let corner = UnevenRoundedRectangle(topLeadingRadius: Tide.s1, topTrailingRadius: Tide.s1)
        ForEach(item.bars, id: \.label) { bar in
            BarMark(
                x: .value("Category", bar.label),
                y: .value("Value", bar.value)
            )
            .foregroundStyle(item.color.opacity(opacity(for: bar.label)))
            .clipShape(corner)
            .position(by: .value("Series", key))
        }
    }

    @ChartContentBuilder
    private var targetMark: some ChartContent {
        if let target {
            RuleMark(y: .value("Target", target))
                .foregroundStyle(Tide.text3)
                .lineStyle(StrokeStyle(lineWidth: Tide.rule, dash: [Tide.s1, Tide.s1]))
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selectedLabel, let bar = series.first?.bars.first(where: { $0.label == selectedLabel }) {
            RuleMark(x: .value("Selected", selectedLabel))
                .foregroundStyle(.clear)
                .annotation(
                    position: .top, spacing: Tide.s1,
                    overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text(bar.value, format: .number.precision(.fractionLength(0 ... 1)))
                        .font(Tide.numeral(Tide.numeralS, .bold))
                        .foregroundStyle(Tide.text)
                        .padding(.horizontal, Tide.s3)
                        .padding(.vertical, Tide.s1)
                        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
                }
        }
    }

    private func opacity(for label: String) -> Double {
        guard let selectedLabel else {
            // At rest, the emphasised bar (today) is lit and the rest are softer.
            guard let emphasis else {
                return 1
            }
            return label == emphasis ? 1 : 0.55
        }
        return label == selectedLabel ? 1 : 0.4
    }
}
