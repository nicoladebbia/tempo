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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Sleep Score Ring
                sleepScoreSection

                // Sleep Stages
                sleepStagesSection

                // Sleep Debt Section (Task 3)
                sleepDebtSection

                // Sleep Metrics Grid
                sleepMetricsGrid

                // Sleep Trend Chart
                sleepTrendSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(modelContext: modelContext)
        }
    }

    // MARK: - Sleep Score Section

    // Per MODULE_RECOVERY.md Section 5.1

    private var sleepScoreSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            ScoreRingView(
                score: viewModel.todayRecovery?.sleepScore ?? 0,
                maxScore: 100,
                label: "SLEEP",
                size: 200,
                strokeWidth: 14
            )

            // Duration line
            HStack(spacing: TempoSpacing.xs) {
                Text(viewModel.formattedSleepHours)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("asleep")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // Efficiency
            if let efficiency = viewModel.todayRecovery?.sleepEfficiency {
                Text("Sleep Efficiency: \(String(format: "%.1f", efficiency))%")
                    .font(.tempoCaption1)
                    .foregroundStyle(sleepEfficiencyColor(efficiency))
            }
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Sleep Stages Section

    // Per MODULE_RECOVERY.md Section 5.2

    private var sleepStagesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Sleep Stages")

            // Stacked horizontal bar
            if viewModel.totalSleepStageMinutes > 0 {
                sleepStagesBar

                // Stage tiles
                HStack(spacing: TempoSpacing.sm) {
                    stageTile(
                        name: "Awake",
                        minutes: viewModel.awakeMinutes,
                        color: Color.sleepAwake,
                        percentage: stagePercent(viewModel.awakeMinutes)
                    )
                    stageTile(
                        name: "Light",
                        minutes: viewModel.lightSleepMinutes,
                        color: Color.sleepLight,
                        percentage: stagePercent(viewModel.lightSleepMinutes)
                    )
                    stageTile(
                        name: "Deep",
                        minutes: viewModel.deepSleepMinutes,
                        color: Color.sleepDeep,
                        percentage: stagePercent(viewModel.deepSleepMinutes)
                    )
                    stageTile(
                        name: "REM",
                        minutes: viewModel.remSleepMinutes,
                        color: Color.sleepREM,
                        percentage: stagePercent(viewModel.remSleepMinutes)
                    )
                }
            } else {
                Text("No sleep stage data available")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.lg)
            }
        }
    }

    /// Per MODULE_RECOVERY.md Section 5.2 — Stacked horizontal bar with labels
    private var sleepStagesBar: some View {
        VStack(spacing: TempoSpacing.xs) {
            GeometryReader { geo in
                let total = Double(viewModel.awakeMinutes + viewModel.lightSleepMinutes + viewModel.deepSleepMinutes + viewModel
                    .remSleepMinutes)
                let width = geo.size.width

                HStack(spacing: 2) {
                    if total > 0 {
                        barSegment(
                            label: "Awake",
                            minutes: viewModel.awakeMinutes,
                            fraction: Double(viewModel.awakeMinutes) / total,
                            color: Color.sleepAwake,
                            totalWidth: width
                        )
                        barSegment(
                            label: "Light",
                            minutes: viewModel.lightSleepMinutes,
                            fraction: Double(viewModel.lightSleepMinutes) / total,
                            color: Color.sleepLight,
                            totalWidth: width
                        )
                        barSegment(
                            label: "Deep",
                            minutes: viewModel.deepSleepMinutes,
                            fraction: Double(viewModel.deepSleepMinutes) / total,
                            color: Color.sleepDeep,
                            totalWidth: width
                        )
                        barSegment(
                            label: "REM",
                            minutes: viewModel.remSleepMinutes,
                            fraction: Double(viewModel.remSleepMinutes) / total,
                            color: Color.sleepREM,
                            totalWidth: width
                        )
                    }
                }
            }
            .frame(height: 36)

            // Inline minute labels below bar
            HStack(spacing: 2) {
                let total = Double(viewModel.awakeMinutes + viewModel.lightSleepMinutes + viewModel.deepSleepMinutes + viewModel
                    .remSleepMinutes)
                if total > 0 {
                    stageLabel(formatMinutes(viewModel.awakeMinutes), fraction: Double(viewModel.awakeMinutes) / total)
                    stageLabel(formatMinutes(viewModel.lightSleepMinutes), fraction: Double(viewModel.lightSleepMinutes) / total)
                    stageLabel(formatMinutes(viewModel.deepSleepMinutes), fraction: Double(viewModel.deepSleepMinutes) / total)
                    stageLabel(formatMinutes(viewModel.remSleepMinutes), fraction: Double(viewModel.remSleepMinutes) / total)
                }
            }
        }
    }

    private func barSegment(label: String, minutes: Int, fraction: Double, color: Color, totalWidth: CGFloat) -> some View {
        let minWidth: CGFloat = 8
        let gapTotal: CGFloat = 6 // 3 gaps of 2pt
        let segmentWidth = max(minWidth, (totalWidth - gapTotal) * fraction)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: segmentWidth, height: 36)
    }

    private func stageLabel(_ text: String, fraction: Double) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.tempoTextTertiary)
            .frame(maxWidth: fraction > 0.08 ? .infinity : 0)
            .opacity(fraction > 0.08 ? 1 : 0)
    }

    private func stageTile(name: String, minutes: Int, color: Color, percentage: Int) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.tempoCaption2)
                .foregroundStyle(color)

            Text(formatMinutes(minutes))
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("\(percentage)%")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Sleep Debt Section (Task 3)

    private var sleepDebtSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Sleep Debt")

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                // Debt amount with severity color
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: debtSeverityIcon)
                        .font(.tempoTitle3)
                        .foregroundStyle(debtSeverityColor)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: TempoSpacing.xs) {
                            Text(String(format: "%.1f", viewModel.calculatedSleepDebt))
                                .font(.tempoLargeTitle)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text("hours")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Text("accumulated over 7 days")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Spacer()

                    // Severity badge
                    Text(viewModel.sleepDebtSeverity.rawValue)
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(debtSeverityColor)
                        .padding(.horizontal, TempoSpacing.sm)
                        .padding(.vertical, TempoSpacing.xxs)
                        .background(debtSeverityColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Severity progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.tempoSurfaceCard)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(debtSeverityColor)
                            .frame(
                                width: min(geo.size.width, geo.size.width * min(viewModel.calculatedSleepDebt / 10.0, 1.0)),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                // Scale labels
                HStack {
                    Text("0h")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Text("5h")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Text("10h+")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                // Payback plan
                if let paybackPlan = viewModel.sleepDebtPaybackPlan {
                    Divider()
                        .background(Color.tempoBorder)

                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.tempoBody)
                            .foregroundStyle(Color.sleepDeep)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Payback Plan")
                                .font(.tempoHeadline)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text(paybackPlan)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .lineSpacing(2)
                        }
                    }
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    private var debtSeverityColor: Color {
        switch viewModel.sleepDebtSeverity {
        case .minimal: Color.tempoRecoveryGreen
        case .moderate: Color.tempoRecoveryYellow
        case .significant: Color(red: 1.0, green: 0.6, blue: 0.2) // orange
        case .critical: Color.tempoRecoveryRed
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Sleep Metrics")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm),
            ], spacing: TempoSpacing.sm) {
                sleepMetricCell(
                    icon: "clock.arrow.2.circlepath",
                    label: "Consistency",
                    value: viewModel.todayRecovery?.sleepConsistency.map { "\(Int($0))%" } ?? "--",
                    unit: ""
                )
                sleepMetricCell(
                    icon: "lungs",
                    label: "Respiratory Rate",
                    value: viewModel.todayRecovery?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "br/min"
                )
                sleepMetricCell(
                    icon: "bed.double.fill",
                    label: "Efficiency",
                    value: viewModel.todayRecovery?.sleepEfficiency.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "%"
                )
                sleepMetricCell(
                    icon: "moon.zzz.fill",
                    label: "Sleep Debt",
                    value: viewModel.todayRecovery?.sleepDebt.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "h"
                )
            }
        }
    }

    private func sleepMetricCell(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: icon)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Text(label)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            HStack(spacing: 2) {
                Text(value)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Sleep Trend Section

    // Per MODULE_RECOVERY.md Section 5.5

    private var sleepTrendSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Sleep Trends")

            if viewModel.sleepChartData.count >= 3 {
                TempoLineChart(
                    data: [
                        TempoLineChartData(
                            id: "sleep",
                            label: "Sleep",
                            color: Color.sleepDeep,
                            points: viewModel.sleepChartData.map {
                                TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                            }
                        ),
                    ],
                    height: 200
                )
            } else {
                Text(
                    "Need \(3 - viewModel.sleepChartData.count) more day\(3 - viewModel.sleepChartData.count == 1 ? "" : "s") of data to show trends."
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, TempoSpacing.xxxl)
            }
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
        case 90...: Color.tempoRecoveryGreen
        case 80 ..< 90: Color.tempoRecoveryYellow
        default: Color.tempoRecoveryRed
        }
    }
}

// MARK: - Sleep Stage Colors

// Per MODULE_RECOVERY.md Section 3 — Sleep Stage Colors
// Now centralized in Color+Tempo.swift as .tempoSleepAwake, .tempoSleepLight, .tempoSleepDeep, .tempoSleepREM

extension Color {
    static let sleepAwake = Color.tempoSleepAwake
    static let sleepLight = Color.tempoSleepLight
    static let sleepDeep = Color.tempoSleepDeep
    static let sleepREM = Color.tempoSleepREM
}
