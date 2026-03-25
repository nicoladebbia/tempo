import SwiftUI

// MARK: - Sleep Detail View
// Per MODULE_RECOVERY.md Section 5 — Sleep Detail Screen.
// Per WIREFRAMES.md Section 5 — Recovery screens.

struct SleepDetailView: View {

    @Bindable var viewModel: RecoveryViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {

                // Sleep Score Ring
                sleepScoreSection

                // Sleep Stages
                sleepStagesSection

                // Sleep Metrics Grid
                sleepMetricsGrid

                // Sleep Trend Chart
                sleepTrendSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, 100)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
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
            sectionHeader("Sleep Stages")

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

    // Per MODULE_RECOVERY.md Section 5.2 — Stacked horizontal bar
    private var sleepStagesBar: some View {
        GeometryReader { geo in
            let total = Double(viewModel.awakeMinutes + viewModel.lightSleepMinutes + viewModel.deepSleepMinutes + viewModel.remSleepMinutes)
            let width = geo.size.width

            HStack(spacing: 0) {
                if total > 0 {
                    barSegment(
                        fraction: Double(viewModel.awakeMinutes) / total,
                        color: Color.sleepAwake,
                        totalWidth: width
                    )
                    barSegment(
                        fraction: Double(viewModel.lightSleepMinutes) / total,
                        color: Color.sleepLight,
                        totalWidth: width
                    )
                    barSegment(
                        fraction: Double(viewModel.deepSleepMinutes) / total,
                        color: Color.sleepDeep,
                        totalWidth: width
                    )
                    barSegment(
                        fraction: Double(viewModel.remSleepMinutes) / total,
                        color: Color.sleepREM,
                        totalWidth: width
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: 24)
    }

    private func barSegment(fraction: Double, color: Color, totalWidth: CGFloat) -> some View {
        let minWidth: CGFloat = 4
        let segmentWidth = max(minWidth, totalWidth * fraction)
        return color
            .frame(width: segmentWidth)
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

    // MARK: - Sleep Metrics Grid
    // Per MODULE_RECOVERY.md Section 5.4

    private var sleepMetricsGrid: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionHeader("Sleep Metrics")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm)
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
            sectionHeader("Sleep Trends")

            if viewModel.sleepChartData.count >= 2 {
                TempoLineChart(
                    data: [
                        TempoLineChartData(
                            id: "sleep",
                            label: "Sleep",
                            color: Color.sleepDeep,
                            points: viewModel.sleepChartData.map {
                                TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                            }
                        )
                    ],
                    height: 200
                )
            } else {
                Text("Not enough data yet. Check back after a few days.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.xxxl)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.tempoTitle3)
            .foregroundStyle(Color.tempoTextPrimary)
    }

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
        guard total > 0 else { return 0 }
        return Int(Double(minutes) / Double(total) * 100)
    }

    private func sleepEfficiencyColor(_ value: Double) -> Color {
        switch value {
        case 90...: Color.tempoRecoveryGreen
        case 80..<90: Color.tempoRecoveryYellow
        default: Color.tempoRecoveryRed
        }
    }
}

// MARK: - Sleep Stage Colors
// Per MODULE_RECOVERY.md Section 3 — Sleep Stage Colors

extension Color {
    static let sleepAwake = Color(red: 1.0, green: 107 / 255, blue: 107 / 255) // #FF6B6B
    static let sleepLight = Color(red: 116 / 255, green: 185 / 255, blue: 1.0) // #74B9FF
    static let sleepDeep = Color(red: 6 / 255, green: 82 / 255, blue: 221 / 255)  // #0652DD
    static let sleepREM = Color(red: 162 / 255, green: 155 / 255, blue: 254 / 255) // #A29BFE
}
