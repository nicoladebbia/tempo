//
// RecoverySleepSection.swift
// Tempo
//
// Last night's sleep, as a section of the Recovery Day view: the score and
// hours, the stages, the debt and how to pay it back, and the sleep metrics.
// Per MODULE_RECOVERY.md Section 5. The sleep trend lives in Week and Month.
//

import SwiftUI

// MARK: - RecoverySleepSection

struct RecoverySleepSection: View {
    var viewModel: RecoveryViewModel
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var hasSleep: Bool {
        viewModel.todayRecovery?.sleepHours != nil || viewModel.totalSleepStageMinutes > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Sleep")

            if hasSleep {
                scoreCard
                stagesCard
                debtCard
                metricsGrid
            } else {
                TideEmptyPanel(
                    systemImage: "moon.zzz",
                    title: "No sleep recorded",
                    message: "Last night's sleep shows up here once WHOOP has processed it."
                )
                .tideCard()
            }
        }
        .accessibilityIdentifier("recovery-sleep-section")
    }

    // MARK: - Score

    // Per MODULE_RECOVERY.md Section 5.1

    private var scoreCard: some View {
        RecoveryHero {
            TideDial(
                score: viewModel.todayRecovery?.sleepScore.map { Int($0.rounded()) },
                caption: "Sleep",
                diameter: Tide.dialSheet
            )
        } side: {
            TideNumber(viewModel.formattedSleepHours, unit: "asleep", size: Tide.numeralM, relativeTo: .title2)
            if let efficiency = viewModel.todayRecovery?.sleepEfficiency {
                TideStatusPill(
                    text: "Efficiency \(String(format: "%.1f", efficiency))%",
                    tint: efficiencyColor(efficiency)
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stages

    // Per MODULE_RECOVERY.md Section 5.2

    private var stagesCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("Stages").tideLabel()

            if viewModel.totalSleepStageMinutes > 0 {
                stagesBar

                LazyVGrid(columns: stageColumns, spacing: Tide.s3) {
                    stageTile(name: "Awake", minutes: viewModel.awakeMinutes, color: TideSleepStage.awake)
                    stageTile(name: "Light", minutes: viewModel.lightSleepMinutes, color: TideSleepStage.light)
                    stageTile(name: "Deep", minutes: viewModel.deepSleepMinutes, color: TideSleepStage.deep)
                    stageTile(name: "REM", minutes: viewModel.remSleepMinutes, color: TideSleepStage.rem)
                }
            } else {
                Text("No sleep stage data for last night.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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

    private var stagesBar: some View {
        RecoveryStagesBar(
            segments: stageMinutes,
            accessibilityValue:
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
            TideNumber(formatMinutes(minutes), size: Tide.numeralS, relativeTo: .title3)
            Text("\(stagePercent(minutes))%")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
            TideLevelBar(progress: Double(stagePercent(minutes)) / 100, color: color, height: Tide.barSlim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Debt

    private var debtCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("Sleep debt").tideLabel()

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

    // MARK: - Metrics

    // Per MODULE_RECOVERY.md Section 5.4. Sleep debt has its own card above, so
    // the page never shows it twice with two different numbers.

    private var metricsGrid: some View {
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

    private func efficiencyColor(_ value: Double) -> Color {
        switch value {
        case 90...: TideTone.mint
        case 80 ..< 90: TideTone.amber
        default: Tide.danger
        }
    }
}
