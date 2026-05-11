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
            VStack(spacing: TempoSpacing.xl) {
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
                    EmptyStateView(
                        icon: "sensor.tag.radiowaves.forward.fill",
                        title: "No Whoop Connected",
                        message: "Connect your Whoop to see recovery, HRV, sleep, and strain data.",
                        actionTitle: "Connect Whoop",
                        action: { showWhoopConnect = true }
                    )
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
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
        data.recoveryZone?.color ?? Color.tempoTextTertiary
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
            return ("--", .tempoTextTertiary)
        }
        return spo2 >= 95 ? ("Normal", .tempoSuccess) : ("Low", .tempoError)
    }

    // MARK: - Recovery Hero

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Hero Section

    private var recoveryHeroSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            // Data source badge
            if data.dataSource != .none {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: data.dataSource == .whoop
                        ? "sensor.tag.radiowaves.forward.fill"
                        : "applewatch")
                        .font(.tempoCaption2)
                    Text(data.dataSource.rawValue)
                        .font(.tempoCaption2)
                }
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, 4)
                .background(Color.tempoSurfaceCard)
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: TempoSpacing.xl) {
                // Recovery ring — 120pt
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    if let score = data.recoveryScore {
                        Circle()
                            .trim(from: 0, to: score / 100)
                            .stroke(
                                zoneColor,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text(scoreDigits)
                            .font(.tempoScoreDisplay)
                            .foregroundStyle(zoneColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("RECOVERY")
                            .font(.tempoCaption2)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(width: 96)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Recovery")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(recoveryQuip)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .italic()

                    // CTA when using HealthKit fallback (no Whoop recovery score)
                    if data.dataSource == .healthKit, data.recoveryScore == nil {
                        Text("Connect Whoop for full recovery data")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoSignal)
                    }
                }

                Spacer()
            }
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Metric Cards

    // Per MODULE_DASHBOARD.md Section 4.2 — Metric Cards Row

    private var metricCardsSection: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: TempoSpacing.sm), count: 4),
            spacing: TempoSpacing.sm
        ) {
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
    }

    // MARK: - Recovery Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Trend Chart (7 Days)

    private var recoveryTrendSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("RECOVERY TREND")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Chart(trendData) { point in
                // Area fill
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.tempoTextPrimary.opacity(0.15), Color.clear],
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
                .foregroundStyle(Color.tempoTextPrimary)
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
                        .foregroundStyle(Color.tempoTextSecondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(
                            position: .top,
                            spacing: 6,
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
                        .foregroundStyle(Color.tempoDivider)
                }
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
            .frame(height: 160)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Sleep Breakdown

    // Per MODULE_DASHBOARD.md Section 4.2 — Sleep Breakdown

    private var sleepBreakdownSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("SLEEP BREAKDOWN")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(height: 24)

            // Legend 2x2 grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
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
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("In bed: 11:15 PM → 6:45 AM")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Strain Breakdown

    // Per MODULE_DASHBOARD.md Section 4.2 — Strain Breakdown

    private var strainBreakdownSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("STRAIN BREAKDOWN")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Semicircle gauge
            ZStack {
                // Arc background
                SemiCircleArc(progress: 1.0)
                    .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 160, height: 80)

                // Arc fill with gradient
                SemiCircleArc(progress: min((data.strain ?? 0) / 21.0, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [Color.tempoSuccess, Color.tempoWarning, Color.tempoError],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 160, height: 80)
            }
            .frame(height: 90)

            Text("Strain zone: \(strainZoneLabel)")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Recommended: \(strainRecommendation) (recovery \(data.formattedRecovery))")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Historical Comparison

    // Per MODULE_DASHBOARD.md Section 4.2 — Historical Comparison

    private var historicalComparisonSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("HISTORICAL COMPARISON")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(spacing: 0) {
                comparisonRow(
                    period: "Yesterday",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "+5%", color: .tempoSuccess),
                        ComparisonMetric(label: "HRV", delta: "-2 ms", color: .tempoError),
                    ]
                )
                Divider().background(Color.tempoDivider)
                comparisonRow(
                    period: "Last Week",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "+8%", color: .tempoSuccess),
                        ComparisonMetric(label: "Sleep", delta: "+0.5h", color: .tempoSuccess),
                    ]
                )
                Divider().background(Color.tempoDivider)
                comparisonRow(
                    period: "7-day avg",
                    metrics: [
                        ComparisonMetric(label: "Recovery", delta: "\(Int(avgRecovery))%", color: .tempoTextPrimary),
                        ComparisonMetric(label: "HRV", delta: "\(Int(avgHRV)) ms", color: .tempoTextPrimary),
                    ]
                )
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func metricCard(value: String, label: String, comparison: (String, Color)) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .lineLimit(1)

            Text(comparison.0)
                .font(.tempoCaption2)
                .foregroundStyle(comparison.1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(10)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    private func tooltipCard(for point: RecoveryTrendPoint) -> some View {
        let zone = RecoveryZone(score: point.score)
        let delta = point.score - avgRecovery
        let deltaText = delta > 0
            ? "+\(Int(delta)) vs 7-day avg"
            : delta < 0 ? "\(Int(delta)) vs 7-day avg" : "= 7-day avg"
        return VStack(alignment: .leading, spacing: 2) {
            Text(TempoDateFormatters.shortDayOfWeek.string(from: point.date).uppercased())
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(point.score))")
                    .font(.tempoTitle3)
                    .foregroundStyle(zone.color)
                Text("%")
                    .font(.tempoCaption1)
                    .foregroundStyle(zone.color)
            }
            Text(deltaText)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, TempoSpacing.xs)
        .background(Color.tempoSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    private func sleepSegment(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0), height: 24)
    }

    private func sleepLegendItem(color: Color, label: String, duration: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label)  \(duration)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
        }
    }

    private func comparisonRow(period: String, metrics: [ComparisonMetric]) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Text(period.uppercased())
                .font(.tempoCaption2)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 88, alignment: .leading)

            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                HStack(spacing: 4) {
                    Text(metric.label)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text(metric.delta)
                        .font(.tempoCallout)
                        .monospacedDigit()
                        .foregroundStyle(metric.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, TempoSpacing.xs)
    }

    private func comparisonIndicator(current: Double?, average: Double, higherIsBetter: Bool) -> (String, Color) {
        guard let current else {
            return ("--", .tempoTextTertiary)
        }
        let ratio = current / average
        if ratio > 1.05 {
            return ("↑ vs avg", higherIsBetter ? Color.tempoSuccess : Color.tempoError)
        } else if ratio < 0.95 {
            return ("↓ vs avg", higherIsBetter ? Color.tempoError : Color.tempoSuccess)
        }
        return ("= avg", Color.tempoTextTertiary)
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
