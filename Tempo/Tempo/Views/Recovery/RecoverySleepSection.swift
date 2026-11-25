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
            TideSectionLabel(title: String(localized: "Sleep"))

            if hasSleep {
                scoreCard
                stagesCard
                debtCard
                metricsGrid
            } else {
                TideEmptyPanel(
                    systemImage: "moon.zzz",
                    title: String(localized: "No sleep recorded"),
                    message: String(localized: "Last night's sleep shows up here once WHOOP has processed it.")
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
                caption: String(localized: "Sleep"),
                diameter: Tide.dialSheet
            )
            .explains(
                Explainer.sleepScore.showing(
                    viewModel.todayRecovery?.sleepScore.map { String(localized: "\(Int($0.rounded())) percent") }
                )
            )
        } side: {
            TideNumber(viewModel.formattedSleepHours, unit: String(localized: "asleep"), size: Tide.numeralM, relativeTo: .title2)
            if let efficiency = viewModel.todayRecovery?.sleepEfficiency {
                TideStatusPill(
                    text: String(localized: "Efficiency \(efficiency.tempoDecimal(1))%"),
                    tint: efficiencyColor(efficiency)
                )
                .explains(Explainer.sleepEfficiency.showing(String(localized: "\(efficiency.tempoDecimal(1)) percent")))
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
                    stageTile(name: String(localized: "Awake"), minutes: viewModel.awakeMinutes, color: TideSleepStage.awake)
                    stageTile(name: String(localized: "Light"), minutes: viewModel.lightSleepMinutes, color: TideSleepStage.light)
                    stageTile(name: String(localized: "Deep"), minutes: viewModel.deepSleepMinutes, color: TideSleepStage.deep)
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
        .explains(.sleepStages)
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
            String(
                localized: "Awake \(formatMinutes(viewModel.awakeMinutes)), light \(formatMinutes(viewModel.lightSleepMinutes)), deep \(formatMinutes(viewModel.deepSleepMinutes)), REM \(formatMinutes(viewModel.remSleepMinutes))"
            )
        )
    }

    private func stageTile(name: String, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(spacing: Tide.s1 + Tide.hair) {
                Circle()
                    .fill(color)
                    .frame(width: Tide.s2, height: Tide.s2)
                    .accessibilityHidden(true)
                Text(name)
                    .tideLabel(color)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
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

            // Debt amount with severity colour. At large text the amount, its
            // caption and the severity no longer share one row.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            layout {
                Image(systemName: debtSeverityIcon)
                    .font(Tide.title2)
                    .foregroundStyle(debtSeverityColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    TideNumber(
                        viewModel.calculatedSleepDebt.tempoDecimal(1), unit: String(localized: "hours"),
                        size: Tide.numeralL, relativeTo: .largeTitle
                    )
                    Text("accumulated over 7 days")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }

                TideStatusPill(text: viewModel.sleepDebtSeverity.title, tint: debtSeverityColor)
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
        .explains(Explainer.sleepDebt.showing(String(localized: "\(viewModel.calculatedSleepDebt.tempoDecimal(1)) hours")))
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
                label: String(localized: "Consistency"),
                value: viewModel.todayRecovery?.sleepConsistency.map { "\(Int($0))" } ?? "--",
                unit: viewModel.todayRecovery?.sleepConsistency == nil ? nil : "%",
                systemImage: "clock.arrow.2.circlepath"
            )
            .explains(.sleepConsistency)
            TideMetricTile(
                label: String(localized: "recovery.respiratory-rate.tile", defaultValue: "Respiratory rate", comment: "Short tile label (narrow column); the explainer keeps the full name"),
                value: viewModel.todayRecovery?.respiratoryRate.map { $0.tempoDecimal(1) } ?? "--",
                unit: String(localized: "br/min"),
                systemImage: "lungs"
            )
            .explains(.respiratoryRate)
        }
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? String(localized: "\(h)h \(m)m") : String(localized: "\(h)h")
        }
        return String(localized: "\(minutes)m")
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
