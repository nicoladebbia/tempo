import SwiftUI
import Charts

// MARK: - Body Quadrant Detail View
// Per MODULE_DASHBOARD.md Section 4.2 — Body Expanded View.
// Recovery hero, metric cards, 7-day trend chart, sleep breakdown,
// strain gauge, historical comparison.

struct BodyQuadrantDetailView: View {

    let data: BodyQuadrantData

    // Stub 7-day trend data
    private let trendData: [RecoveryTrendPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).map { offset in
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
                        action: {}
                    )
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, 50)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Recovery Hero
    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Hero Section

    private var recoveryHeroSection: some View {
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
                Text(data.formattedRecovery)
                    .font(.tempoScoreDisplay)
                    .foregroundStyle(zoneColor)
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
            }

            Spacer()
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
                value: data.formattedHRV,
                label: "HRV",
                comparison: comparisonIndicator(current: data.hrv, average: avgHRV, higherIsBetter: true)
            )

            metricCard(
                value: data.formattedRHR,
                label: "RHR",
                comparison: comparisonIndicator(current: data.rhr, average: avgRHR, higherIsBetter: false)
            )

            metricCard(
                value: data.formattedSleep,
                label: "Sleep",
                comparison: comparisonIndicator(current: data.sleepHours, average: avgSleep, higherIsBetter: true)
            )

            metricCard(
                value: data.formattedSpo2,
                label: "SpO2",
                comparison: spo2Comparison
            )
        }
    }

    private func metricCard(value: String, label: String, comparison: (String, Color)) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Text(comparison.0)
                .font(.tempoCaption2)
                .foregroundStyle(comparison.1)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
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
            }
            .chartYScale(domain: 0...100)
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
        .padding(14)
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
                    sleepSegment(width: geo.size.width * Double(deepSleepMin) / total,
                                 color: Color(red: 88/255, green: 86/255, blue: 214/255)) // #5856D6
                    sleepSegment(width: geo.size.width * Double(remSleepMin) / total,
                                 color: Color(red: 90/255, green: 200/255, blue: 250/255)) // #5AC8FA
                    sleepSegment(width: geo.size.width * Double(lightSleepMin) / total,
                                 color: Color(red: 209/255, green: 209/255, blue: 214/255)) // #D1D1D6
                    sleepSegment(width: geo.size.width * Double(awakeSleepMin) / total,
                                 color: Color(red: 255/255, green: 149/255, blue: 0/255)) // #FF9500
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(height: 24)

            // Legend 2x2 grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                sleepLegendItem(color: Color(red: 88/255, green: 86/255, blue: 214/255),
                                label: "Deep", duration: formatMinutes(deepSleepMin))
                sleepLegendItem(color: Color(red: 90/255, green: 200/255, blue: 250/255),
                                label: "REM", duration: formatMinutes(remSleepMin))
                sleepLegendItem(color: Color(red: 209/255, green: 209/255, blue: 214/255),
                                label: "Light", duration: formatMinutes(lightSleepMin))
                sleepLegendItem(color: Color(red: 255/255, green: 149/255, blue: 0/255),
                                label: "Awake", duration: formatMinutes(awakeSleepMin))
            }

            // Performance + bed time
            Text("Performance: \(data.formattedSleepPerformance)")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("In bed: 11:15 PM → 6:45 AM")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(14)
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
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Historical Comparison
    // Per MODULE_DASHBOARD.md Section 4.2 — Historical Comparison

    private var historicalComparisonSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("HISTORICAL COMPARISON")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            // vs Yesterday (stub data)
            comparisonRow(period: "Yesterday", changes: [
                ("Recovery", "+5%", Color.tempoSuccess),
                ("HRV", "-2 ms", Color.tempoError),
            ])

            comparisonRow(period: "Last Week", changes: [
                ("Recovery", "+8%", Color.tempoSuccess),
                ("Sleep", "+0.5h", Color.tempoSuccess),
            ])

            HStack {
                Text("7-day avg Recovery:")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                Text("\(Int(avgRecovery))%")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        data.recoveryZone?.color ?? Color.tempoTextTertiary
    }

    private var recoveryQuip: String {
        guard let score = data.recoveryScore else { return "" }
        switch score {
        case 90...100: return "Go break something. In a good way."
        case 67..<90: return "You're good to push it."
        case 50..<67: return "Yellow zone. Choose your battles."
        case 34..<50: return "Your body is waving a yellow flag."
        default: return "Sit down. Seriously."
        }
    }

    private var strainZoneLabel: String {
        guard let strain = data.strain else { return "--" }
        switch strain {
        case 0..<10: return "Low"
        case 10..<14: return "Moderate"
        case 14..<18: return "High"
        default: return "Overreaching"
        }
    }

    private var strainRecommendation: String {
        guard let recovery = data.recoveryScore else { return "--" }
        if recovery >= 80 { return "Push it" }
        if recovery >= 50 { return "Moderate" }
        return "Take it easy"
    }

    private func comparisonIndicator(current: Double?, average: Double, higherIsBetter: Bool) -> (String, Color) {
        guard let current else { return ("--", .tempoTextTertiary) }
        let ratio = current / average
        if ratio > 1.05 {
            return ("↑ vs avg", higherIsBetter ? Color.tempoSuccess : Color.tempoError)
        } else if ratio < 0.95 {
            return ("↓ vs avg", higherIsBetter ? Color.tempoError : Color.tempoSuccess)
        }
        return ("= avg", Color.tempoTextTertiary)
    }

    private var spo2Comparison: (String, Color) {
        guard let spo2 = data.spo2 else { return ("--", .tempoTextTertiary) }
        return spo2 >= 95 ? ("Normal", .tempoSuccess) : ("Low", .tempoError)
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

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func comparisonRow(period: String, changes: [(String, String, Color)]) -> some View {
        HStack {
            Text("vs \(period):")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                Text("\(change.0) \(change.1)")
                    .font(.tempoBody)
                    .foregroundStyle(change.2)
            }
            Spacer()
        }
    }
}

// MARK: - Recovery Trend Point

struct RecoveryTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
}

// MARK: - Semi-Circle Arc Shape

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
                isConnected: true, lastSync: Date()
            )
        )
    }
}
