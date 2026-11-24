//
// BodyQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftUI

// MARK: - BodyQuadrantDetailView

// Per MODULE_DASHBOARD.md Section 4.2 — Body Expanded View.
// Recovery hero, metric cards, 7-day trend chart, sleep breakdown,
// strain gauge, historical comparison.

struct BodyQuadrantDetailView: View {
    // MARK: Internal

    let data: BodyQuadrantData

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                if data.isConnected {
                    // Recovery Hero
                    recoveryHeroSection

                    // Metric Cards
                    metricCardsSection

                    // Recovery Trend Chart
                    recoveryTrendSection

                    // Sleep Breakdown
                    sleepBreakdownSection

                    // Strain Breakdown
                    strainBreakdownSection

                    // Historical Comparison
                    historicalComparisonSection
                } else {
                    TrainEmptyCard(
                        systemImage: "sensor.tag.radiowaves.forward.fill",
                        title: "No Whoop Connected",
                        message: "Connect your Whoop to see recovery, HRV, sleep, and strain data."
                    )
                    Button {
                        showWhoopConnect = true
                    } label: {
                        Text("Connect Whoop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidePrimary)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, TideTrain.pageBottom)
        }
        .tidePage()
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWhoopConnect) {
            NavigationStack {
                WhoopConnectionView()
            }
        }
    }

    // MARK: Private

    private struct ComparisonMetric: Hashable {
        let label: String
        let delta: String
        let color: Color
    }

    @State
    private var showWhoopConnect = false
    @State
    private var selectedTrendDate: Date?
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Stub 7-day trend data
    private let trendData: [RecoveryTrendPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6 ... 0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let scores: [Double] = [58, 65, 72, 55, 78, 68, 72]
            return RecoveryTrendPoint(date: date, score: scores[offset + 6])
        }
    }()

    // Stub sleep data
    private let deepSleepMin = 75
    private let remSleepMin = 88
    private let lightSleepMin = 195
    private let awakeSleepMin = 22

    // Stub 7-day averages
    private let avgRecovery: Double = 65
    private let avgHRV: Double = 52
    private let avgRHR: Double = 60
    private let avgSleep: Double = 7.0

    /// Bare digit strings keep all four cards visually identical — units
    /// live in the label below so the value glyph width is consistent.
    private var hrvDigits: String {
        data.hrv.map { String(format: "%.0f", $0) } ?? "--"
    }

    private var rhrDigits: String {
        data.rhr.map { "\(Int($0))" } ?? "--"
    }

    private var sleepDigits: String {
        data.sleepHours.map { String(format: "%.1f", $0) } ?? "--"
    }

    private var spo2Digits: String {
        data.spo2.map { "\(Int($0))" } ?? "--"
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        data.recoveryZone?.color ?? Tide.text3
    }

    /// Score digits without the "%" suffix, so the 64pt display font
    /// fits the 120pt ring on a single line. The "%" is implied by the
    /// "RECOVERY" caption beneath.
    private var scoreDigits: String {
        guard let score = data.recoveryScore else {
            return "--"
        }
        return "\(Int(score))"
    }

    /// Resolves the trend chart's current X-selection to the nearest data point.
    /// `chartXSelection` snaps to whatever value the user dragged to (typically
    /// not exactly on a sample), so we map back to the closest sample by day.
    private var selectedTrendPoint: RecoveryTrendPoint? {
        guard let selectedTrendDate else {
            return nil
        }
        return trendData.min(by: { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedTrendDate))
                < abs(rhs.date.timeIntervalSince(selectedTrendDate))
        })
    }

    private var recoveryQuip: String {
        guard let score = data.recoveryScore else {
            return ""
        }
        switch score {
        case 90 ... 100: return "Go break something. In a good way."
        case 67 ..< 90: return "You're good to push it."
        case 50 ..< 67: return "Yellow zone. Choose your battles."
        case 34 ..< 50: return "Your body is waving a yellow flag."
        default: return "Sit down. Seriously."
        }
    }

    private var strainZoneLabel: String {
        guard let strain = data.strain else {
            return "--"
        }
        switch strain {
        case 0 ..< 10: return "Low"
        case 10 ..< 14: return "Moderate"
        case 14 ..< 18: return "High"
        default: return "Overreaching"
        }
    }

    private var strainRecommendation: String {
        guard let recovery = data.recoveryScore else {
            return "--"
        }
        if recovery >= 80 {
            return "Push it"
        }
        if recovery >= 50 {
            return "Moderate"
        }
        return "Take it easy"
    }

    private var spo2Comparison: (String, Color) {
        guard let spo2 = data.spo2 else {
            return ("--", Tide.text3)
        }
        return spo2 >= 95 ? ("Normal", TideTrain.positive) : ("Low", Tide.danger)
    }

    // MARK: - Recovery Hero

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Hero Section

    private var recoveryHeroSection: some View {
        VStack(spacing: Tide.s3) {
            // Data source badge
            if data.dataSource != .none {
                HStack(spacing: Tide.s1) {
                    Image(systemName: data.dataSource == .whoop
                        ? "sensor.tag.radiowaves.forward.fill"
                        : "applewatch")
                        .font(Tide.caption)
                    Text(data.dataSource.rawValue)
                        .font(Tide.caption)
                }
                .foregroundStyle(Tide.text3)
                .padding(.horizontal, Tide.s2)
                .padding(.vertical, Tide.s1)
                .background(Tide.fill)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
                : AnyLayout(HStackLayout(spacing: Tide.s5))
            layout {
                // Recovery ring
                ZStack {
                    Circle()
                        .stroke(Tide.hairline, style: StrokeStyle(lineWidth: TideTrain.ringStroke, lineCap: .round))
                    if let score = data.recoveryScore {
                        Circle()
                            .trim(from: 0, to: score / 100)
                            .stroke(
                                zoneColor,
                                style: StrokeStyle(lineWidth: TideTrain.ringStroke, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text(scoreDigits)
                            .font(TideTrain.figure(.largeTitle))
                            .foregroundStyle(zoneColor)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                        Text("Recovery").tideLabel(Tide.text3)
                    }
                    .frame(width: TideTrain.ringInner)
                }
                .frame(width: TideTrain.ring, height: TideTrain.ring)

                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Recovery")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)

                    Text(recoveryQuip)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)

                    // CTA when using HealthKit fallback (no Whoop recovery score)
                    if data.dataSource == .healthKit, data.recoveryScore == nil {
                        Text("Connect Whoop for full recovery data")
                            .font(Tide.caption)
                            .foregroundStyle(Color.accentColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Metric Cards

    // Per MODULE_DASHBOARD.md Section 4.2 — Metric Cards Row

    private var metricCardsSection: some View {
        let cards = Group {
            metricCard(
                value: hrvDigits,
                label: "HRV · ms",
                comparison: comparisonIndicator(current: data.hrv, average: avgHRV, higherIsBetter: true)
            )

            metricCard(
                value: rhrDigits,
                label: "RHR · bpm",
                comparison: comparisonIndicator(current: data.rhr, average: avgRHR, higherIsBetter: false)
            )

            metricCard(
                value: sleepDigits,
                label: "Sleep · h",
                comparison: comparisonIndicator(current: data.sleepHours, average: avgSleep, higherIsBetter: true)
            )

            metricCard(
                value: spo2Digits,
                label: "SpO2 · %",
                comparison: spo2Comparison
            )
        }
        // Four across while they fit; two by two at large text sizes.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                cards
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s2), count: 2),
                spacing: Tide.s2
            ) {
                cards
            }
        }
    }

    // MARK: - Recovery Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Trend Chart (7 Days)

    private var recoveryTrendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Recovery trend")

            Chart(trendData) { point in
                // Area fill
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Tide.hairline, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                // Line
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Tide.text)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                // Points colored by zone
                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(RecoveryZone(score: point.score).color)
                .symbolSize(36)

                // Selection rule + annotation
                if let selection = selectedTrendPoint,
                   Calendar.current.isDate(selection.date, inSameDayAs: point.date)
                {
                    RuleMark(x: .value("Selected", selection.date, unit: .day))
                        .foregroundStyle(Tide.text3)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(
                            position: .top,
                            spacing: Tide.s2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            tooltipCard(for: selection)
                        }

                    PointMark(
                        x: .value("Day", selection.date, unit: .day),
                        y: .value("Score", selection.score)
                    )
                    .foregroundStyle(RecoveryZone(score: selection.score).color)
                    .symbolSize(120)
                }
            }
            .chartXSelection(value: $selectedTrendDate)
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [33, 67]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Tide.hairline)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: typeSize.isAccessibilitySize ? 2 : 1)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                    }
                }
            }
            .frame(height: TideTrain.chartHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Sleep Breakdown

    // Per MODULE_DASHBOARD.md Section 4.2 — Sleep Breakdown

    private var sleepBreakdownSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Sleep breakdown")

            // Stacked bar
            let total = Double(deepSleepMin + remSleepMin + lightSleepMin + awakeSleepMin)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    sleepSegment(
                        width: geo.size.width * Double(deepSleepMin) / total,
                        color: Color.tempoSleepDeep
                    ) // #5856D6
                    sleepSegment(
                        width: geo.size.width * Double(remSleepMin) / total,
                        color: Color.tempoSleepREM
                    ) // #5AC8FA
                    sleepSegment(
                        width: geo.size.width * Double(lightSleepMin) / total,
                        color: Color.tempoSleepLight
                    ) // #D1D1D6
                    sleepSegment(
                        width: geo.size.width * Double(awakeSleepMin) / total,
                        color: Color.tempoSleepAwake
                    ) // #FF9500
                }
                .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
            }
            .frame(height: TideTrain.stackBar)

            // Legend: two columns, one at large text sizes
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2),
                spacing: Tide.s2
            ) {
                sleepLegendItem(
                    color: Color.tempoSleepDeep,
                    label: "Deep",
                    duration: formatMinutes(deepSleepMin)
                )
                sleepLegendItem(
                    color: Color.tempoSleepREM,
                    label: "REM",
                    duration: formatMinutes(remSleepMin)
                )
                sleepLegendItem(
                    color: Color.tempoSleepLight,
                    label: "Light",
                    duration: formatMinutes(lightSleepMin)
                )
                sleepLegendItem(
                    color: Color.tempoSleepAwake,
                    label: "Awake",
                    duration: formatMinutes(awakeSleepMin)
                )
            }

            // Performance + bed time
            Text("Performance: \(data.formattedSleepPerformance)")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("In bed: 11:15 PM → 6:45 AM")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Strain Breakdown

    // Per MODULE_DASHBOARD.md Section 4.2 — Strain Breakdown

    private var strainBreakdownSection: some View {
        VStack(spacing: Tide.s3) {
            TideSectionLabel(title: "Strain breakdown")

            // Semicircle gauge
            ZStack {
                // Arc background
                SemiCircleArc(progress: 1.0)
                    .stroke(Tide.hairline, style: StrokeStyle(lineWidth: TideTrain.ringStroke, lineCap: .round))
                    .frame(width: TideTrain.gaugeWidth, height: TideTrain.gaugeHeight)

                // Arc fill with gradient
                SemiCircleArc(progress: min((data.strain ?? 0) / 21.0, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [TideTrain.positive, TideTrain.caution, Tide.danger],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: TideTrain.ringStroke, lineCap: .round)
                    )
                    .frame(width: TideTrain.gaugeWidth, height: TideTrain.gaugeHeight)
            }
            .frame(height: TideTrain.gaugeHeight + TideTrain.ringStroke)
            .accessibilityHidden(true)

            Text("Strain zone: \(strainZoneLabel)")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Recommended: \(strainRecommendation) (recovery \(data.formattedRecovery))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Historical Comparison

    // Per MODULE_DASHBOARD.md Section 4.2 — Historical Comparison

    private var historicalComparisonSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Historical comparison")

            VStack(spacing: 0) {
                comparisonRow(
                    period: "Yesterday",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "+5%", color: TideTrain.positive),
                        ComparisonMetric(label: "HRV", delta: "-2 ms", color: Tide.danger),
                    ]
                )
                TrainPlanDivider()
                comparisonRow(
                    period: "Last Week",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "+8%", color: TideTrain.positive),
                        ComparisonMetric(label: "Sleep", delta: "+0.5h", color: TideTrain.positive),
                    ]
                )
                TrainPlanDivider()
                comparisonRow(
                    period: "7-day avg",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "\(Int(avgRecovery))%", color: Tide.text),
                        ComparisonMetric(label: "HRV", delta: "\(Int(avgHRV)) ms", color: Tide.text),
                    ]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    private func metricCard(value: String, label: String, comparison: (String, Color)) -> some View {
        VStack(spacing: Tide.s1) {
            Text(value)
                .font(TideTrain.figure(.title3))
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)

            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)

            Text(comparison.0)
                .font(Tide.caption)
                .foregroundStyle(comparison.1)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity, minHeight: TideTrain.statColumn)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    private func tooltipCard(for point: RecoveryTrendPoint) -> some View {
        let zone = RecoveryZone(score: point.score)
        let delta = point.score - avgRecovery
        let deltaText = delta > 0
            ? "+\(Int(delta)) vs 7-day avg"
            : delta < 0 ? "\(Int(delta)) vs 7-day avg" : "= 7-day avg"
        return VStack(alignment: .leading, spacing: Tide.hair) {
            Text(TempoDateFormatters.shortDayOfWeek.string(from: point.date).uppercased())
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                Text("\(Int(point.score))")
                    .font(Tide.headline)
                    .foregroundStyle(zone.color)
                Text("%")
                    .font(Tide.caption)
                    .foregroundStyle(zone.color)
            }
            Text(deltaText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                .stroke(Tide.hairline, lineWidth: 1)
        )
    }

    private func sleepSegment(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0), height: TideTrain.stackBar)
    }

    private func sleepLegendItem(color: Color, label: String, duration: String) -> some View {
        HStack(spacing: Tide.s2) {
            Circle()
                .fill(color)
                .frame(width: TideTrain.dot, height: TideTrain.dot)
            Text("\(label)  \(duration)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func comparisonRow(period: String, metrics: [ComparisonMetric]) -> some View {
        let title = Text(period.uppercased())
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
        let cells = ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
            HStack(spacing: Tide.s1) {
                Text(metric.label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Text(metric.delta)
                    .font(TideTrain.figure(.callout, weight: .semibold))
                    .foregroundStyle(metric.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                title
                    .frame(width: TideTrain.statColumn, alignment: .leading)
                cells
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                title
                cells
            }
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func comparisonIndicator(current: Double?, average: Double, higherIsBetter: Bool) -> (String, Color) {
        guard let current else {
            return ("--", Tide.text3)
        }
        let ratio = current / average
        if ratio > 1.05 {
            return ("↑ vs avg", higherIsBetter ? TideTrain.positive : Tide.danger)
        } else if ratio < 0.95 {
            return ("↓ vs avg", higherIsBetter ? Tide.danger : TideTrain.positive)
        }
        return ("= avg", Tide.text3)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0, m > 0 {
            return "\(h)h \(m)m"
        }
        if h > 0 {
            return "\(h)h"
        }
        return "\(m)m"
    }
}

// MARK: - RecoveryTrendPoint

struct RecoveryTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
}

// MARK: - SemiCircleArc

struct SemiCircleArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2, rect.height)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * progress),
            clockwise: false
        )
        return path
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BodyQuadrantDetailView(
            data: BodyQuadrantData(
                recoveryScore: 72, hrv: 48, rhr: 62, sleepHours: 7.2,
                sleepPerformance: 78, strain: 12.4, spo2: 97.5,
                isConnected: true, lastSync: Date(),
                dataSource: .whoop
            )
        )
    }
}
