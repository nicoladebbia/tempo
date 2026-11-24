//
// RecoveryDayView.swift
// Tempo
//
// The Day view of the Recovery page: how recovered you are and why, the vitals,
// last night's sleep and today's strain, then the morning check-in.
//

import SwiftData
import SwiftUI

// MARK: - RecoveryDayView

// Per MODULE_RECOVERY.md Section 4 (score, vitals), Section 5 (sleep) and
// Section 6 (strain): the three used to be tabs, they are sections of one page.

struct RecoveryDayView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(ServiceContainer.self)
    private var services

    /// Connected but nothing scored yet is a wait, not a setup step.
    private var whoopConnected: Bool {
        services.whoop.connectionState == .connected
    }

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
        viewModel.todayRecovery.map { RecoveryViewModel.reading(from: $0).hasReadings } ?? false
    }

    var body: some View {
        TideScrollPage(energy: 1) {
            if hasData {
                // A refresh that failed after the data was already on screen
                // keeps the numbers and says what went wrong.
                if case let .error(message) = viewModel.loadState {
                    RecoveryErrorBanner(message: message)
                }

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

                // What drove the score, then the vitals behind it
                scoreBreakdownSection
                metricsGrid

                // Recovery Score Explanation
                recoveryExplanationSection

                // Last night and today's load
                RecoverySleepSection(viewModel: viewModel)
                RecoveryStrainSection(viewModel: viewModel)

                // Subjective morning check-in (INTELLIGENT_TRAINING_SYSTEM §4.2)
                MorningCheckInCard()
            } else if case let .error(message) = viewModel.loadState {
                RecoveryErrorPanel(message: message) {
                    Task { await viewModel.forceRefresh(modelContext: modelContext) }
                }

                // How you feel does not need a wearable.
                MorningCheckInCard()
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

                Text(
                    whoopConnected
                        ? "WHOOP is connected. Today's score lands once last night is processed. Pull down to refresh."
                        : "Connect WHOOP, then pull down to refresh. Your first score lands after one night of data."
                )
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)

            if !whoopConnected {
                Button("Connect WHOOP") {
                    showWhoopConnect = true
                }
                .buttonStyle(.tidePrimary)
            }
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

