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

    /// Animated recovery score — starts at 0, fills to actual score on appear
    @State
    private var animatedScore: Double = 0
    @State
    private var hasAppeared = false

    /// Metric detail sheet
    @State
    private var selectedMetric: MetricType?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Hero: Recovery Ring
                heroSection

                // Recovery Score Explanation (Task 1)
                recoveryExplanationSection

                // Recovery Score Breakdown
                scoreBreakdownSection

                // Key Metrics Row
                metricsRow

                // Anomaly Warning Cards (Task 4)
                if !viewModel.activeAnomalies.isEmpty {
                    anomalyWarningsSection
                }

                // Legacy Warnings (if any)
                if let prescription = viewModel.todayPrescription, !prescription.warnings.isEmpty {
                    warningsSection(prescription.warnings)
                }

                // Today's AI-generated recovery read (replaces the old
                // static 2-day prescription text).
                RecoveryAIInsightView(recovery: viewModel.todayRecovery)

                // Quick Insights
                quickInsightsSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .refreshable {
            await viewModel.refresh(modelContext: modelContext)
        }
        .task {
            if viewModel.loadState != .loaded {
                await viewModel.refresh(modelContext: modelContext)
            }
        }
    }

    // MARK: - Hero Section

    // Per MODULE_RECOVERY.md Section 4.2 — Recovery Ring + comparison label

    private var heroSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            // Recovery Ring with zone color
            ZStack {
                // Glow effect
                Circle()
                    .fill(zoneColor.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .blur(radius: 30)

                ScoreRingView(
                    score: animatedScore,
                    maxScore: 100,
                    label: "RECOVERY",
                    size: 200,
                    strokeWidth: 14
                )
            }

            // Comparison label
            Text(viewModel.comparisonText)
                .font(.tempoCaption1)
                .foregroundStyle(
                    viewModel.comparisonIsPositive
                        ? Color.tempoRecoveryGreen
                        : Color.tempoRecoveryRed
                )

            // Date label — ticks via TimelineView so it survives midnight rollover.
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.top, TempoSpacing.lg)
        .onAppear {
            guard !hasAppeared else {
                return
            }
            hasAppeared = true
            animatedScore = 0
            withAnimation(.easeOut(duration: 1.0)) {
                animatedScore = viewModel.todayRecovery?.recoveryScore ?? 0
            }
        }
        .onChange(of: viewModel.todayRecovery?.recoveryScore) { _, newValue in
            withAnimation(.easeOut(duration: 1.0)) {
                animatedScore = newValue ?? 0
            }
        }
    }

    // MARK: - Recovery Explanation Section (Task 1)

    private var recoveryExplanationSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.tempoBody)
                    .foregroundStyle(zoneColor)

                Text("Recovery Analysis")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Text(viewModel.recoveryExplanation)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineSpacing(3)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .fill(Color.tempoSurfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                        .stroke(zoneColor.opacity(0.3), lineWidth: 1)
                )
        )
        .tempoShadow(.card)
    }

    // MARK: - Anomaly Warnings Section (Task 4)

    private var anomalyWarningsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            TempoSectionHeader("Health Alerts", accentColor: Color.tempoRecoveryRed)

            ForEach(viewModel.activeAnomalies) { anomaly in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Image(systemName: anomaly.icon)
                        .font(.tempoTitle3)
                        .foregroundStyle(
                            anomaly.severity == .critical
                                ? Color.tempoRecoveryRed
                                : Color.tempoRecoveryYellow
                        )
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Text(anomaly.title)
                            .font(.tempoHeadline)
                            .foregroundStyle(
                                anomaly.severity == .critical
                                    ? Color.tempoRecoveryRed
                                    : Color.tempoRecoveryYellow
                            )

                        Text(anomaly.detail)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .lineSpacing(2)
                    }
                }
                .padding(TempoSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                        .fill(
                            anomaly.severity == .critical
                                ? Color.tempoRecoveryRedBg
                                : Color.tempoRecoveryYellow.opacity(0.1)
                        )
                )
            }
        }
    }

    // MARK: - Key Metrics Row

    // Per MODULE_RECOVERY.md Section 4.3 — HRV, RHR, SpO2, Temp

    private var metricsRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            metricTile(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: viewModel.formattedHRV,
                unit: "ms",
                metric: .hrv
            )
            metricTile(
                icon: "heart.fill",
                label: "RHR",
                value: viewModel.formattedRHR,
                unit: "bpm",
                metric: .rhr
            )
            metricTile(
                icon: "lungs.fill",
                label: "SpO2",
                value: viewModel.formattedSpO2,
                unit: "%",
                metric: .spo2
            )
            metricTile(
                icon: "thermometer.medium",
                label: "Temp",
                value: viewModel.formattedSkinTemp,
                unit: "°C",
                metric: .temp
            )
        }
        .sheet(item: $selectedMetric) { metric in
            MetricTrendSheet(
                metric: metric,
                viewModel: viewModel
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func metricTile(icon: String, label: String, value: String, unit: String, metric: MetricType) -> some View {
        Button {
            selectedMetric = metric
        } label: {
            VStack(spacing: TempoSpacing.xxs) {
                Image(systemName: icon)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                Text(label)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)

                HStack(spacing: 2) {
                    Text(value)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(unit)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                // Baseline indicator
                if let indicator = baselineIndicator(for: metric) {
                    HStack(spacing: 2) {
                        Image(systemName: indicator.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("vs avg")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(indicator.isPositive ? Color.tempoRecoveryGreen : Color.tempoRecoveryRed)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TempoSpacing.md)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Warnings Section

    // Per MODULE_RECOVERY.md — Warnings highlighted in red

    private func warningsSection(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoRecoveryRed)

                    Text(warning)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
                .padding(TempoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoRecoveryRedBg)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
        }
    }

    // MARK: - Prescription Section

    // Per MODULE_RECOVERY.md Section 4.4

    

    // MARK: - Recovery Prescription Card

    // Per MODULE_RECOVERY.md Section 3.2

    

    // MARK: - Quick Insights Section

    // Per MODULE_RECOVERY.md Section 4.5

    private var quickInsightsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Quick Insights")

            // Recovery Trends Teaser
            if let avg = viewModel.avgRecovery7d {
                NavigationLink {
                    RecoveryTrendsView(viewModel: viewModel)
                } label: {
                    insightCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Recovery Trends",
                        detail: "7-day avg: \(Int(avg))%",
                        action: "See Trends"
                    )
                }
                .buttonStyle(.plain)
            }

            // Sleep Teaser
            if viewModel.todayRecovery?.sleepHours != nil {
                NavigationLink {
                    SleepDetailView(viewModel: viewModel)
                } label: {
                    insightCard(
                        icon: "moon.zzz.fill",
                        title: "Last Night's Sleep",
                        detail: "\(viewModel.formattedSleepHours) · Score: \(viewModel.formattedSleepScore)",
                        action: "Details"
                    )
                }
                .buttonStyle(.plain)
            }

            // Strain Teaser
            if viewModel.todayRecovery?.strain != nil {
                NavigationLink {
                    StrainDetailView(viewModel: viewModel)
                } label: {
                    insightCard(
                        icon: "flame.fill",
                        title: "Today's Strain",
                        detail: "\(viewModel.formattedStrain) · Calories: \(viewModel.formattedCalories)",
                        action: "Details"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func insightCard(icon: String, title: String, detail: String, action: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: icon)
                        .font(.tempoBody)
                        .foregroundStyle(zoneColor)

                    Text(title)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }

                Text(detail)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            HStack(spacing: TempoSpacing.xxs) {
                Text(action)
                    .font(.tempoCaption1)
                    .foregroundStyle(zoneColor)
                Image(systemName: "chevron.right")
                    .font(.tempoCaption2)
                    .foregroundStyle(zoneColor)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Score Breakdown Section (Task 2)

    // Shows what drove the recovery score: HRV, RHR, Sleep vs 30-day baselines

    private var scoreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("What Drove Your Score")

            VStack(spacing: TempoSpacing.sm) {
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
                    scoreDriverRow(
                        label: "Sleep",
                        todayValue: viewModel.formattedSleepHours,
                        unit: "",
                        delta: sleepDelta,
                        baselineValue: viewModel.sleepNeededHours.map { "\(String(format: "%.1f", $0))h" } ?? "--",
                        isHigherBetter: true
                    )
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
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
        let isPositive = isHigherBetter ? delta >= 0 : delta <= 0
        return HStack {
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 2) {
                Text(todayValue)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            Spacer()

            // Delta arrow
            HStack(spacing: 4) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%+.0f", delta))
                    .font(.tempoCaption1)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isPositive ? Color.tempoRecoveryGreen : Color.tempoRecoveryRed)

            Text("avg \(baselineValue)")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 65, alignment: .trailing)
        }
    }

    // MARK: - Baseline Indicator Helper (Task 3)

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

    // MARK: - Sleep Goal Detail (Task 1)

    

    // MARK: - Helpers

    private var zoneColor: Color {
        switch viewModel.recoveryZone {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
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
        VStack(spacing: TempoSpacing.lg) {
            // Header
            HStack {
                Image(systemName: metric.icon)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextSecondary)
                Text("\(metric.rawValue) — Last 7 Days")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            // Sparkline chart
            if trendData.count >= 2 {
                TempoLineChart(
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
                    height: 160
                )
            } else {
                Text("Need \(3 - trendData.count) more days of data to show trends.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.xxxl)
            }

            // Summary stats
            if !trendData.isEmpty {
                HStack(spacing: TempoSpacing.lg) {
                    summaryItem(label: "Min", value: trendData.map(\.1).min())
                    summaryItem(label: "Avg", value: trendData.map(\.1).reduce(0, +) / Double(trendData.count))
                    summaryItem(label: "Max", value: trendData.map(\.1).max())
                }
            }

            Spacer()
        }
        .padding(TempoSpacing.screenEdge)
        .background(Color.tempoBgPrimary)
    }

    private func summaryItem(label: String, value: Double?) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
            Text(value.map { metric == .temp ? String(format: "%.1f", $0) : "\(Int($0))" } ?? "--")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(metric.unit)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var sparklineColor: Color {
        switch metric {
        case .hrv: Color.tempoSleepREM // #A29BFE
        case .rhr: Color.tempoRecoveryRed
        case .spo2: Color.tempoRecoveryGreen
        case .temp: Color.tempoRecoveryYellow
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
