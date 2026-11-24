//
// RecoveryTodayView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - RecoveryTodayView

// Per MODULE_RECOVERY.md Section 4 — Main screen of RecoverIQ module.
// Per WIREFRAMES.md Section 5 — Recovery layout.

struct RecoveryTodayView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Metric detail sheet
    @State
    private var selectedMetric: MetricType?

    @State
    private var showWhoopConnect = false

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    /// True once a night of readings is in. Before that the day holds a record
    /// with a score of 0 and nothing else, which must not read as a red day.
    private var hasData: Bool {
        guard let recovery = viewModel.todayRecovery else {
            return false
        }
        return recovery.hrvRmssd != nil || recovery.restingHR != nil
            || recovery.sleepHours != nil || recovery.strain != nil
            || recovery.recoveryScore > 0
    }

    var body: some View {
        TideScrollPage(energy: 1) {
            if hasData {
                // Hero: the recovery dial
                heroSection

                // Anomaly Warning Cards
                if !viewModel.activeAnomalies.isEmpty {
                    anomalyWarningsSection
                }

                // Legacy Warnings (if any)
                if let prescription = viewModel.todayPrescription, !prescription.warnings.isEmpty {
                    warningsSection(prescription.warnings)
                }

                // Today's AI-generated recovery read: the why, right under the
                // score (replaces the old static 2-day prescription text).
                RecoveryAIInsightView(recovery: viewModel.todayRecovery)

                // Key Metrics
                metricsGrid

                // Recovery Score Breakdown
                scoreBreakdownSection

                // Recovery Score Explanation
                recoveryExplanationSection

                // Subjective morning check-in (INTELLIGENT_TRAINING_SYSTEM §4.2)
                MorningCheckInCard()

                // Quick Insights
                quickInsightsSection
            } else if viewModel.loadState == .loading {
                // The page's own shape while the first read is on its way.
                RecoverySkeleton(label: "Loading recovery")
                    .padding(.horizontal, -Tide.edge)
            } else {
                noDataSection

                // How you feel does not need a wearable.
                MorningCheckInCard()
            }
        }
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
        .task {
            if viewModel.loadState != .loaded {
                await viewModel.refresh(modelContext: modelContext)
            }
        }
        .tideCovered(selectedMetric != nil || showWhoopConnect)
        .sheet(item: $selectedMetric) { metric in
            MetricTrendSheet(
                metric: metric,
                viewModel: viewModel
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWhoopConnect, onDismiss: {
            Task { await viewModel.forceRefresh(modelContext: modelContext) }
        }) {
            NavigationStack {
                WhoopConnectionView()
            }
        }
    }

    // MARK: - No Data

    // Before the first night of readings: the dial at rest, one line on what to
    // do, and the button to do it.

    private var noDataSection: some View {
        VStack(spacing: Tide.s4) {
            RecoveryHero {
                TideDial(score: nil, caption: "Recovery", diameter: Tide.dialHero)
            } side: {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .tideLabel(Tide.text3)
                }

                Text("No recovery yet")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)

                Text("Connect WHOOP, then pull down to refresh. Your first score lands after one night of data.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)

            Button("Connect WHOOP") {
                showWhoopConnect = true
            }
            .buttonStyle(.tidePrimary)
        }
    }

    // MARK: - Hero Section

    // Per MODULE_RECOVERY.md Section 4.2 — Recovery dial + comparison label

    private var heroSection: some View {
        RecoveryHero {
            TideDial(
                score: viewModel.todayRecovery.map { Int($0.recoveryScore.rounded()) },
                caption: "Recovery",
                diameter: Tide.dialHero
            )
        } side: {
            // Date label — ticks via TimelineView so it survives midnight rollover.
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .tideLabel(Tide.text3)
            }

            if viewModel.todayRecovery?.recoveryScore != nil {
                Text("\(viewModel.recoveryZone.displayName) zone")
                    .font(Tide.title2)
                    .foregroundStyle(zoneColor)
            }

            // Comparison label
            Text(viewModel.comparisonText)
                .font(Tide.body)
                .foregroundStyle(viewModel.comparisonIsPositive ? TideTone.mint : Tide.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Recovery Explanation Section

    private var recoveryExplanationSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                Image(systemName: "brain.head.profile")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(zoneColor)
                    .accessibilityHidden(true)
                Text("Recovery analysis").tideLabel()
            }

            Text(viewModel.recoveryExplanation)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .lineSpacing(Tide.s1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Anomaly Warnings Section

    private var anomalyWarningsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Health alerts")

            ForEach(viewModel.activeAnomalies) { anomaly in
                let tint = anomaly.severity == .critical ? Tide.danger : TideTone.amber
                HStack(alignment: .top, spacing: Tide.s3) {
                    Image(systemName: anomaly.icon)
                        .font(Tide.headline)
                        .foregroundStyle(tint)
                        .frame(width: Tide.icon)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(anomaly.title)
                            .font(Tide.headline)
                            .foregroundStyle(tint)
                        Text(anomaly.detail)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .lineSpacing(Tide.hair)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tideTintedCard(tint, padding: Tide.s4, radius: Tide.tileRadius)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Key Metrics

    // Per MODULE_RECOVERY.md Section 4.3 — HRV, RHR, SpO2, Temp

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Vitals")
            LazyVGrid(columns: metricColumns, spacing: Tide.s3) {
                metricTile(label: "HRV", value: viewModel.formattedHRV, metric: .hrv)
                metricTile(label: "Resting HR", value: viewModel.formattedRHR, metric: .rhr)
                metricTile(label: "SpO2", value: viewModel.formattedSpO2, metric: .spo2)
                metricTile(label: "Skin temp", value: viewModel.formattedSkinTemp, metric: .temp)
            }
        }
    }

    private func metricTile(label: String, value: String, metric: MetricType) -> some View {
        let indicator = baselineIndicator(for: metric)
        return Button {
            selectedMetric = metric
        } label: {
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(spacing: Tide.s1 + Tide.hair) {
                    Image(systemName: metric.icon)
                        .font(Tide.label)
                        .foregroundStyle(Tide.text2)
                        .accessibilityHidden(true)
                    Text(label)
                        .tideLabel()
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(Tide.labelShrink)
                }

                TideNumber(value, unit: metric.unit, size: Tide.numeralM, relativeTo: .title2)

                // Baseline indicator: green is the good side of your own average.
                if let indicator {
                    HStack(spacing: Tide.s1) {
                        Image(systemName: indicator.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(Tide.label)
                        Text("vs avg").font(Tide.caption)
                    }
                    .foregroundStyle(indicator.isPositive ? TideTone.mint : Tide.danger)
                } else {
                    Text("No baseline yet")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label) \(value) \(metric.unit)"
                + (indicator.map { $0.isPositive ? ", better than your average" : ", worse than your average" } ?? "")
        )
        .accessibilityHint("Shows the last 7 days")
    }

    // MARK: - Warnings Section

    // Per MODULE_RECOVERY.md — Warnings highlighted in red

    private func warningsSection(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: Tide.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.danger)
                        .accessibilityHidden(true)

                    Text(warning)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tideTintedCard(Tide.danger, padding: Tide.s4, radius: Tide.tileRadius)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Quick Insights Section

    // Per MODULE_RECOVERY.md Section 4.5

    private var quickInsightsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Quick insights")

            // Three ways into the other tabs read as one list, not three cards.
            VStack(spacing: 0) {
                // Recovery Trends Teaser
                if let avg = viewModel.avgRecovery7d {
                    NavigationLink {
                        RecoveryTrendsView(viewModel: viewModel)
                    } label: {
                        insightRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Recovery trends",
                            detail: "7-day avg: \(Int(avg))%"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Sleep Teaser
                if viewModel.todayRecovery?.sleepHours != nil {
                    if viewModel.avgRecovery7d != nil {
                        TideDivider()
                    }
                    NavigationLink {
                        SleepDetailView(viewModel: viewModel)
                    } label: {
                        insightRow(
                            icon: "moon.zzz.fill",
                            title: "Last night's sleep",
                            detail: "\(viewModel.formattedSleepHours) · Score: \(viewModel.formattedSleepScore)"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Strain Teaser
                if viewModel.todayRecovery?.strain != nil {
                    if viewModel.avgRecovery7d != nil || viewModel.todayRecovery?.sleepHours != nil {
                        TideDivider()
                    }
                    NavigationLink {
                        StrainDetailView(viewModel: viewModel)
                    } label: {
                        insightRow(
                            icon: "flame.fill",
                            title: "Today's strain",
                            detail: "\(viewModel.formattedStrain) · Calories: \(viewModel.formattedCalories)"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func insightRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Tide.s3) {
            // At the largest text sizes the words need the whole row, not the icon tile.
            if !typeSize.isAccessibilitySize {
                TideAreaIconTile(systemName: icon, tint: zoneColor)
            }

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text(detail)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }

            Spacer(minLength: Tide.s2)

            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Score Breakdown Section

    // Shows what drove the recovery score: HRV, RHR, Sleep vs 30-day baselines

    private var scoreBreakdownSection: some View {
        let hasRows = viewModel.hrvDelta != nil || viewModel.rhrDelta != nil || viewModel.sleepDelta != nil
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "What drove your score")

            VStack(spacing: 0) {
                if let hrvDelta = viewModel.hrvDelta, let baseline = viewModel.hrvBaseline30d {
                    scoreDriverRow(
                        label: "HRV",
                        todayValue: viewModel.formattedHRV,
                        unit: "ms",
                        delta: hrvDelta,
                        baselineValue: "\(Int(baseline))",
                        isHigherBetter: true
                    )
                }
                if let rhrDelta = viewModel.rhrDelta, let baseline = viewModel.rhrBaseline30d {
                    TideDivider()
                    scoreDriverRow(
                        label: "RHR",
                        todayValue: viewModel.formattedRHR,
                        unit: "bpm",
                        delta: rhrDelta,
                        baselineValue: "\(Int(baseline))",
                        isHigherBetter: false
                    )
                }
                if let sleepDelta = viewModel.sleepDelta {
                    TideDivider()
                    scoreDriverRow(
                        label: "Sleep",
                        todayValue: viewModel.formattedSleepHours,
                        unit: "",
                        delta: sleepDelta,
                        baselineValue: viewModel.sleepNeededHours.map { "\(String(format: "%.1f", $0))h" } ?? "--",
                        isHigherBetter: true
                    )
                }
                if !hasRows {
                    Text("Your drivers show up after a few days of data.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func scoreDriverRow(
        label: String,
        todayValue: String,
        unit: String,
        delta: Double,
        baselineValue: String,
        isHigherBetter: Bool
    ) -> some View {
        // A change that rounds to nothing is "on average", not an arrow with "-0".
        let rounded = delta.rounded()
        let isFlat = rounded == 0
        let isPositive = isHigherBetter ? delta >= 0 : delta <= 0
        return HStack(spacing: Tide.s3) {
            Text(label)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.s10, alignment: .leading)

            TideNumber(todayValue, unit: unit.isEmpty ? nil : unit, size: Tide.numeralS, relativeTo: .headline)

            Spacer(minLength: Tide.s2)

            // Delta arrow
            HStack(spacing: Tide.s1) {
                Image(systemName: isFlat ? "equal" : (isPositive ? "arrow.up.right" : "arrow.down.right"))
                    .font(Tide.label)
                Text(isFlat ? "0" : String(format: "%+.0f", rounded))
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
            }
            .foregroundStyle(isFlat ? Tide.text2 : (isPositive ? TideTone.mint : Tide.danger))

            Text("avg \(baselineValue)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .frame(minWidth: Tide.s10 + Tide.s6, alignment: .trailing)
        }
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label) \(todayValue) \(unit), \(isFlat ? "right at" : (isPositive ? "better than" : "worse than")) your average of \(baselineValue)"
        )
    }

    // MARK: - Baseline Indicator Helper

    private struct BaselineIndicator {
        let isPositive: Bool
    }

    private func baselineIndicator(for metric: MetricType) -> BaselineIndicator? {
        switch metric {
        case .hrv:
            guard let delta = viewModel.hrvDelta else {
                return nil
            }
            return BaselineIndicator(isPositive: delta >= 0) // Higher HRV = better
        case .rhr:
            guard let delta = viewModel.rhrDelta else {
                return nil
            }
            return BaselineIndicator(isPositive: delta <= 0) // Lower RHR = better
        case .spo2:
            guard let delta = viewModel.spo2Delta else {
                return nil
            }
            return BaselineIndicator(isPositive: delta >= 0) // Higher SpO2 = better
        case .temp:
            guard let delta = viewModel.skinTempDelta else {
                return nil
            }
            // Skin temp: closer to baseline is better, deviation either way is concerning
            return BaselineIndicator(isPositive: abs(delta) < 0.5)
        }
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        viewModel.recoveryZone.tideColor
    }
}

// MARK: - MetricType

enum MetricType: String, Identifiable, CaseIterable {
    case hrv = "HRV"
    case rhr = "RHR"
    case spo2 = "SpO2"
    case temp = "Temp"

    var id: String {
        rawValue
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .rhr: "bpm"
        case .spo2: "%"
        case .temp: "°C"
        }
    }

    var icon: String {
        switch self {
        case .hrv: "waveform.path.ecg"
        case .rhr: "heart.fill"
        case .spo2: "lungs.fill"
        case .temp: "thermometer.medium"
        }
    }
}

// MARK: - MetricTrendSheet

struct MetricTrendSheet: View {
    let metric: MetricType
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        TideScrollPage(spacing: Tide.s5, spacer: Tide.s6) {
            // Header
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: metric.icon, tint: sparklineColor)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(metric.rawValue)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text("Last 7 days")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                TideCloseButton { dismiss() }
            }
            .accessibilityElement(children: .contain)

            // Sparkline chart
            Group {
                if trendData.count >= 2 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: metric.rawValue,
                                label: metric.rawValue,
                                color: sparklineColor,
                                points: trendData.map {
                                    TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                                }
                            ),
                        ],
                        height: Tide.chartHeight
                    )
                } else {
                    RecoveryChartPlaceholder(
                        message: "Need \(3 - trendData.count) more days of data to show trends."
                    )
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

            // Summary stats
            if !trendData.isEmpty {
                HStack(spacing: Tide.s3) {
                    summaryItem(label: "Min", value: trendData.map(\.1).min())
                    summaryItem(label: "Avg", value: trendData.map(\.1).reduce(0, +) / Double(trendData.count))
                    summaryItem(label: "Max", value: trendData.map(\.1).max())
                }
            }
        }
    }

    private func summaryItem(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            TideNumber(
                value.map { metric == .temp ? String(format: "%.1f", $0) : "\(Int($0))" } ?? "--",
                unit: metric.unit,
                size: Tide.numeralS + Tide.s1,
                relativeTo: .title3
            )
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    private var sparklineColor: Color {
        switch metric {
        case .hrv: TideSleepStage.rem
        case .rhr: Tide.danger
        case .spo2: TideTone.mint
        case .temp: TideTone.amber
        }
    }

    private var trendData: [(Date, Double)] {
        let recent = Array(viewModel.recentRecoveries.suffix(7))
        switch metric {
        case .hrv:
            return recent.compactMap { r in
                guard let v = r.hrvRmssd else {
                    return nil
                }
                return (r.date, v)
            }
        case .rhr:
            return recent.compactMap { r in
                guard let v = r.restingHR else {
                    return nil
                }
                return (r.date, v)
            }
        case .spo2:
            return recent.compactMap { r in
                guard let v = r.spo2 else {
                    return nil
                }
                return (r.date, v)
            }
        case .temp:
            return recent.compactMap { r in
                guard let v = r.skinTemp else {
                    return nil
                }
                return (r.date, v)
            }
        }
    }
}

// MARK: - RecoveryLoadState + Equatable

extension RecoveryLoadState: Equatable {
    static func == (lhs: RecoveryLoadState, rhs: RecoveryLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): true
        case (.loaded, .loaded): true
        case let (.error(a), .error(b)): a == b
        default: false
        }
    }
}
