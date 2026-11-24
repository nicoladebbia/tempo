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

// MARK: - RecoveryHero

/// The opening of a Recovery detail page: an instrument on the left, what it
/// means on the right. The same shape as the hero on Today. It stacks at
/// accessibility text sizes so nothing truncates.
struct RecoveryHero<Gauge: View, Side: View>: View {
    @ViewBuilder var gauge: Gauge
    @ViewBuilder var side: Side

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s5))
        layout {
            gauge
                // What sits inside a dial stops growing before it touches the ring.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            VStack(alignment: .leading, spacing: Tide.s2) {
                side
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Tide.s2)
    }
}

// MARK: - RecoveryStrainGauge

/// The strain instrument: a 270 degree arc split into the four strain zones,
/// a lit arc up to today's value, and a tick every three points. Strain runs
/// 0 to 21, so it cannot share the 0 to 100 dial.
struct RecoveryStrainGauge: View {
    let strain: Double?
    var color: Color
    var diameter: CGFloat = Tide.dialHero

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown: Double = 0

    private static let maxValue = 21.0
    /// How much of the circle the gauge sweeps.
    private static let sweep = 0.75
    /// A zone starts where the last one ends: green below 10, amber to 14,
    /// orange to 18, red above.
    private static let zones: [(from: Double, to: Double, color: Color)] = [
        (0, 10, TideTone.mint),
        (10, 14, TideTone.amber),
        (14, 18, Tide.streak),
        (18, 21, Tide.danger),
    ]
    private static let tickStep = 3.0

    private var target: Double {
        min(max((strain ?? 0) / Self.maxValue, 0), 1)
    }

    private var lineWidth: CGFloat {
        Tide.s2
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, zone in
                RecoveryGaugeArc(from: zone.from / Self.maxValue * Self.sweep, to: zone.to / Self.maxValue * Self.sweep)
                    .stroke(zone.color.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            RecoveryGaugeArc(from: 0, to: shown * Self.sweep)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: color.opacity(0.5), radius: lineWidth)
            ticks
            VStack(spacing: Tide.hair) {
                TideNumber(
                    strain.map { String(format: "%.1f", $0) } ?? "--",
                    size: Tide.numeralM, relativeTo: .title, color: strain == nil ? Tide.text3 : Tide.text
                )
                Text("of 21")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(reduceMotion ? nil : Tide.settle) { shown = target }
        }
        .onChange(of: target) { _, new in
            withAnimation(reduceMotion ? nil : Tide.snap) { shown = new }
        }
        .accessibilityHidden(true)
    }

    private var ticks: some View {
        let count = Int(Self.maxValue / Self.tickStep)
        let radius = diameter / 2 - lineWidth - Tide.s2
        return ZStack {
            ForEach(0 ... count, id: \.self) { index in
                Capsule()
                    .fill(Tide.text3)
                    .frame(width: Tide.hair, height: Tide.s1)
                    .offset(y: -radius)
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-135 + 270 * Double(index) / Double(count)))
            }
        }
    }
}

// MARK: - RecoveryGaugeArc

/// An arc on the strain gauge. `from` and `to` are fractions of a full circle,
/// counted from the lower left where the gauge starts.
private struct RecoveryGaugeArc: Shape {
    var from: Double
    var to: Double

    nonisolated var animatableData: Double {
        get { to }
        set { to = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: diameter / 2 - Tide.s1,
            startAngle: .degrees(135 + 360 * from),
            endAngle: .degrees(135 + 360 * max(to, from)),
            clockwise: false
        )
        return path
    }
}

// MARK: - RecoverySkeleton

extension Tide {
    /// The slow breathing of a skeleton. Not used when Reduce Motion is on.
    static let recoveryPulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
}

// MARK: - RecoverySkeleton

/// The shape of a Recovery page before its data is there: the dial and two
/// lines of text, then three cards. It breathes slowly and holds still when
/// Reduce Motion is on.
struct RecoverySkeleton: View {
    /// What VoiceOver says while the page loads.
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var dim = false

    var body: some View {
        VStack(spacing: Tide.s4) {
            HStack(spacing: Tide.s5) {
                Circle()
                    .strokeBorder(Tide.track, lineWidth: Tide.bar)
                    .frame(width: Tide.dialHero, height: Tide.dialHero)
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Capsule().fill(Tide.track).frame(width: Tide.s10 * 2, height: Tide.s5)
                    Capsule().fill(Tide.track).frame(height: Tide.s3)
                    Capsule().fill(Tide.track).frame(width: Tide.s10 * 2.5, height: Tide.s3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Tide.s2)

            ForEach(0 ..< 3, id: \.self) { _ in
                Color.clear
                    .frame(height: Tide.s10 * 2)
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s4)
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            if !reduceMotion {
                withAnimation(Tide.recoveryPulse) { dim = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - RecoveryChartPlaceholder

/// What a trend chart shows before it has enough days: the empty grid and one
/// line saying what is missing. The card keeps its height, so the page does
/// not jump when the data arrives.
struct RecoveryChartPlaceholder: View {
    let message: String
    var height: CGFloat = Tide.chartHeight

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0 ..< 4, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: 0)
                    }
                    Rectangle()
                        .fill(Tide.hairline)
                        .frame(height: Tide.rule)
                }
            }
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s2)
                .background(Tide.ink.opacity(0.6), in: .rect(cornerRadius: Tide.controlRadius))
        }
        .frame(minHeight: height)
        .accessibilityElement(children: .combine)
    }
}
