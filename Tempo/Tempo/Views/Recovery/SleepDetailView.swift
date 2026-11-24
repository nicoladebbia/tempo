//
// SleepDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - SleepDetailView

// Per MODULE_RECOVERY.md Section 5 — Sleep Detail Screen.
// Per WIREFRAMES.md Section 5 — Recovery screens.

struct SleepDetailView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        TideScrollPage(energy: 1) {
            // Sleep Score Dial
            sleepScoreSection

            // Sleep Stages
            sleepStagesSection

            // Sleep Debt Section
            sleepDebtSection

            // Sleep Metrics Grid
            sleepMetricsGrid

            // Sleep Trend Chart
            sleepTrendSection
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Sleep Score Section

    // Per MODULE_RECOVERY.md Section 5.1

    private var sleepScoreSection: some View {
        RecoveryHero {
            TideDial(
                score: viewModel.todayRecovery?.sleepScore.map { Int($0.rounded()) },
                caption: "Sleep",
                diameter: Tide.dialHero
            )
        } side: {
            // Duration line
            TideNumber(viewModel.formattedSleepHours, unit: "asleep", size: Tide.numeralM, relativeTo: .title2)

            // Efficiency
            if let efficiency = viewModel.todayRecovery?.sleepEfficiency {
                TideStatusPill(
                    text: "Efficiency \(String(format: "%.1f", efficiency))%",
                    tint: sleepEfficiencyColor(efficiency)
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sleep Stages Section

    // Per MODULE_RECOVERY.md Section 5.2

    private var sleepStagesSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Sleep stages")

            VStack(alignment: .leading, spacing: Tide.s4) {
                if viewModel.totalSleepStageMinutes > 0 {
                    // Stacked horizontal bar
                    sleepStagesBar

                    // Stage tiles
                    LazyVGrid(columns: stageColumns, spacing: Tide.s3) {
                        stageTile(name: "Awake", minutes: viewModel.awakeMinutes, color: TideSleepStage.awake)
                        stageTile(name: "Light", minutes: viewModel.lightSleepMinutes, color: TideSleepStage.light)
                        stageTile(name: "Deep", minutes: viewModel.deepSleepMinutes, color: TideSleepStage.deep)
                        stageTile(name: "REM", minutes: viewModel.remSleepMinutes, color: TideSleepStage.rem)
                    }
                } else {
                    VStack(spacing: Tide.s2) {
                        Image(systemName: "moon.zzz")
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                        Text("No sleep stage data available")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tide.s4)
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var stageColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tide.s2), count: typeSize.isAccessibilitySize ? 2 : 4)
    }

    private var stageMinutes: [(minutes: Int, color: Color)] {
        [
            (viewModel.awakeMinutes, TideSleepStage.awake),
            (viewModel.lightSleepMinutes, TideSleepStage.light),
            (viewModel.deepSleepMinutes, TideSleepStage.deep),
            (viewModel.remSleepMinutes, TideSleepStage.rem),
        ]
    }

    /// Per MODULE_RECOVERY.md Section 5.2 — Stacked horizontal bar
    private var sleepStagesBar: some View {
        let total = Double(stageMinutes.reduce(0) { $0 + $1.minutes })
        return GeometryReader { geo in
            let gaps = Tide.hair * 3
            HStack(spacing: Tide.hair) {
                ForEach(Array(stageMinutes.enumerated()), id: \.offset) { _, stage in
                    RoundedRectangle(cornerRadius: Tide.s1 + Tide.hair, style: .continuous)
                        .fill(stage.color)
                        .frame(width: max(Tide.s2, (geo.size.width - gaps) * (total > 0 ? Double(stage.minutes) / total : 0)))
                }
            }
        }
        .frame(height: Tide.s8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(
            "Awake \(formatMinutes(viewModel.awakeMinutes)), light \(formatMinutes(viewModel.lightSleepMinutes)), "
                + "deep \(formatMinutes(viewModel.deepSleepMinutes)), REM \(formatMinutes(viewModel.remSleepMinutes))"
        )
    }

    private func stageTile(name: String, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(spacing: Tide.s1 + Tide.hair) {
                Circle()
                    .fill(color)
                    .frame(width: Tide.s2, height: Tide.s2)
                    .accessibilityHidden(true)
                Text(name).tideLabel(color)
            }
            Text(formatMinutes(minutes))
                .font(Tide.numeral(Tide.numeralS, .bold))
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            Text("\(stagePercent(minutes))%")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
            TideLevelBar(progress: Double(stagePercent(minutes)) / 100, color: color, height: Tide.barSlim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sleep Debt Section

    private var sleepDebtSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Sleep debt")

            VStack(alignment: .leading, spacing: Tide.s4) {
                // Debt amount with severity colour
                HStack(spacing: Tide.s3) {
                    Image(systemName: debtSeverityIcon)
                        .font(Tide.title2)
                        .foregroundStyle(debtSeverityColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Tide.hair) {
                        TideNumber(
                            String(format: "%.1f", viewModel.calculatedSleepDebt), unit: "hours",
                            size: Tide.numeralL, relativeTo: .largeTitle
                        )
                        Text("accumulated over 7 days")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }

                    Spacer(minLength: Tide.s2)

                    // Severity badge
                    TideStatusPill(text: viewModel.sleepDebtSeverity.rawValue, tint: debtSeverityColor)
                }

                // Severity bar and its scale
                VStack(spacing: Tide.s1) {
                    TideLevelBar(
                        progress: min(viewModel.calculatedSleepDebt / 10.0, 1.0),
                        color: debtSeverityColor,
                        height: Tide.bar
                    )
                    HStack {
                        scaleLabel("0h")
                        Spacer()
                        scaleLabel("5h")
                        Spacer()
                        scaleLabel("10h+")
                    }
                    .accessibilityHidden(true)
                }

                // Payback plan
                if let paybackPlan = viewModel.sleepDebtPaybackPlan {
                    TideDivider()

                    HStack(alignment: .top, spacing: Tide.s3) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(Tide.headline)
                            .foregroundStyle(TideSleepStage.deep)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text("Payback plan")
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                            Text(paybackPlan)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .lineSpacing(Tide.hair)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard()
        }
    }

    private func scaleLabel(_ text: String) -> some View {
        Text(text)
            .font(Tide.numeral(Tide.axisSize, .medium))
            .foregroundStyle(Tide.text3)
    }

    private var debtSeverityColor: Color {
        switch viewModel.sleepDebtSeverity {
        case .minimal: TideTone.mint
        case .moderate: TideTone.amber
        case .significant: Tide.streak
        case .critical: Tide.danger
        }
    }

    private var debtSeverityIcon: String {
        switch viewModel.sleepDebtSeverity {
        case .minimal: "checkmark.circle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .significant: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    // MARK: - Sleep Metrics Grid

    // Per MODULE_RECOVERY.md Section 5.4

    private var sleepMetricsGrid: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Sleep metrics")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: typeSize.isAccessibilitySize ? 1 : 2),
                spacing: Tide.s3
            ) {
                TideMetricTile(
                    label: "Consistency",
                    value: viewModel.todayRecovery?.sleepConsistency.map { "\(Int($0))" } ?? "--",
                    unit: viewModel.todayRecovery?.sleepConsistency == nil ? nil : "%",
                    systemImage: "clock.arrow.2.circlepath"
                )
                TideMetricTile(
                    label: "Respiratory rate",
                    value: viewModel.todayRecovery?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "br/min",
                    systemImage: "lungs"
                )
                TideMetricTile(
                    label: "Efficiency",
                    value: viewModel.todayRecovery?.sleepEfficiency.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "%",
                    systemImage: "bed.double.fill"
                )
                TideMetricTile(
                    label: "Sleep debt",
                    value: viewModel.todayRecovery?.sleepDebt.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "h",
                    systemImage: "moon.zzz.fill"
                )
            }
        }
    }

    // MARK: - Sleep Trend Section

    // Per MODULE_RECOVERY.md Section 5.5

    private var sleepTrendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Sleep trends")

            Group {
                if viewModel.sleepChartData.count >= 3 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: "sleep",
                                label: "Sleep",
                                color: TideSleepStage.deep,
                                points: viewModel.sleepChartData.map {
                                    TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                                }
                            ),
                        ],
                        height: Tide.chartHeight
                    )
                } else {
                    RecoveryChartPlaceholder(
                        message: "Need \(3 - viewModel.sleepChartData.count) more day\(3 - viewModel.sleepChartData.count == 1 ? "" : "s") of data to show trends."
                    )
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }

    private func stagePercent(_ minutes: Int) -> Int {
        let total = viewModel.awakeMinutes + viewModel.lightSleepMinutes + viewModel.deepSleepMinutes + viewModel.remSleepMinutes
        guard total > 0 else {
            return 0
        }
        return Int(Double(minutes) / Double(total) * 100)
    }

    private func sleepEfficiencyColor(_ value: Double) -> Color {
        switch value {
        case 90...: TideTone.mint
        case 80 ..< 90: TideTone.amber
        default: Tide.danger
        }
    }
}

// MARK: - Sleep Stage Colors

// Per MODULE_RECOVERY.md Section 3 — Sleep Stage Colors, on the Tide palette
// (TideSleepStage in Tide+Recovery.swift).

extension Color {
    static let sleepAwake = TideSleepStage.awake
    static let sleepLight = TideSleepStage.light
    static let sleepDeep = TideSleepStage.deep
    static let sleepREM = TideSleepStage.rem
}
