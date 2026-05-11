//
// WeeklyRecoverySummaryView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - WeeklyRecoverySummaryView

// 7-day summary with averages, best/worst days, trend arrows, strain vs recovery balance

struct WeeklyRecoverySummaryView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if let stats = viewModel.weeklyStats {
                    // Average Cards
                    averagesSection(stats)

                    // Best & Worst Days
                    bestWorstSection(stats)

                    // Trend Arrows vs Previous Week
                    trendArrowsSection(stats)

                    // Strain vs Recovery Balance
                    strainRecoveryBalanceSection(stats)

                    // Recovery Distribution
                    recoveryDistributionSection
                } else {
                    // Not enough data
                    VStack(spacing: TempoSpacing.md) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.tempoTextTertiary)

                        Text("Need at least 3 days of data")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)

                        Text("Keep wearing your Whoop and check back soon for your weekly summary.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, TempoSpacing.xxxl)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Weekly Summary")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(modelContext: modelContext)
        }
    }

    // MARK: - Averages Section

    private func averagesSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("7-Day Averages")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm),
            ], spacing: TempoSpacing.sm) {
                averageCard(
                    icon: "heart.text.square.fill",
                    label: "Recovery",
                    value: "\(Int(stats.avgRecovery))%",
                    color: RecoveryZone(score: stats.avgRecovery).zoneColor
                )
                averageCard(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(stats.avgHRV)) ms",
                    color: Color.tempoSleepREM
                )
                averageCard(
                    icon: "heart.fill",
                    label: "RHR",
                    value: "\(Int(stats.avgRHR)) bpm",
                    color: Color.tempoRecoveryRed
                )
                averageCard(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: String(format: "%.1fh", stats.avgSleep),
                    color: Color.sleepDeep
                )
            }
        }
    }

    private func averageCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Image(systemName: icon)
                .font(.tempoTitle3)
                .foregroundStyle(color)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(value)
                .font(.tempoTitle3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Best & Worst Days

    private func bestWorstSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Highlights")

            if let best = stats.bestDay {
                dayHighlightCard(
                    icon: "arrow.up.circle.fill",
                    label: "Best Day",
                    date: best.0,
                    score: best.1,
                    explanation: bestDayExplanation(best.0),
                    color: Color.tempoRecoveryGreen
                )
            }

            if let worst = stats.worstDay {
                dayHighlightCard(
                    icon: "arrow.down.circle.fill",
                    label: "Toughest Day",
                    date: worst.0,
                    score: worst.1,
                    explanation: worstDayExplanation(worst.0),
                    color: Color.tempoRecoveryRed
                )
            }
        }
    }

    private func dayHighlightCard(icon: String, label: String, date: Date, score: Double, explanation: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.tempoTitle2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                HStack {
                    Text(label)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Spacer()

                    Text("\(Int(score))%")
                        .font(.tempoTitle3)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }

                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                Text(explanation)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineSpacing(2)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func bestDayExplanation(_ date: Date) -> String {
        guard let recovery = viewModel.recentRecoveries.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        })
        else {
            return ""
        }

        var reasons: [String] = []
        if let sleep = recovery.sleepHours, sleep >= 7.5 {
            reasons.append("\(String(format: "%.1f", sleep))h of quality sleep")
        }
        if let hrv = recovery.hrvRmssd, let baseline = viewModel.hrvBaseline30d, hrv > baseline {
            reasons.append("HRV \(Int(hrv - baseline))ms above baseline")
        }
        if let rhr = recovery.restingHR, let baseline = viewModel.rhrBaseline30d, rhr < baseline {
            reasons.append("RHR \(Int(baseline - rhr))bpm below average")
        }
        return reasons.isEmpty ? "Strong recovery across all metrics." : reasons.joined(separator: ", ") + "."
    }

    private func worstDayExplanation(_ date: Date) -> String {
        guard let recovery = viewModel.recentRecoveries.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        })
        else {
            return ""
        }

        var reasons: [String] = []
        if let sleep = recovery.sleepHours, sleep < 6.5 {
            reasons.append("only \(String(format: "%.1f", sleep))h of sleep")
        }
        if let hrv = recovery.hrvRmssd, let baseline = viewModel.hrvBaseline30d, hrv < baseline - 10 {
            reasons.append("HRV \(Int(baseline - hrv))ms below baseline")
        }
        if let strain = recovery.strain, strain > 14 {
            reasons.append("high strain (\(String(format: "%.1f", strain)))")
        }
        return reasons.isEmpty ? "Multiple metrics below baseline." : reasons.joined(separator: ", ") + "."
    }

    // MARK: - Trend Arrows vs Previous Week

    private func trendArrowsSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("vs Last Week")

            HStack(spacing: TempoSpacing.sm) {
                trendArrowTile(
                    label: "Recovery",
                    current: stats.avgRecovery,
                    previous: stats.prevWeekAvgRecovery,
                    unit: "%",
                    higherIsBetter: true
                )
                trendArrowTile(
                    label: "HRV",
                    current: stats.avgHRV,
                    previous: stats.prevWeekAvgHRV,
                    unit: "ms",
                    higherIsBetter: true
                )
                trendArrowTile(
                    label: "RHR",
                    current: stats.avgRHR,
                    previous: stats.prevWeekAvgRHR,
                    unit: "bpm",
                    higherIsBetter: false
                )
                trendArrowTile(
                    label: "Sleep",
                    current: stats.avgSleep,
                    previous: stats.prevWeekAvgSleep,
                    unit: "h",
                    higherIsBetter: true
                )
            }
        }
    }

    private func trendArrowTile(label: String, current: Double, previous: Double?, unit: String, higherIsBetter: Bool) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)

            if let prev = previous {
                let delta = current - prev
                let isPositive = higherIsBetter ? delta >= 0 : delta <= 0
                let arrow = isPositive ? "arrow.up.right" : "arrow.down.right"

                Image(systemName: arrow)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isPositive ? Color.tempoRecoveryGreen : Color.tempoRecoveryRed)

                let formatted = unit == "h" ? String(format: "%+.1f", delta) : String(format: "%+.0f", delta)
                Text("\(formatted)\(unit)")
                    .font(.tempoCaption1)
                    .fontWeight(.medium)
                    .foregroundStyle(isPositive ? Color.tempoRecoveryGreen : Color.tempoRecoveryRed)
            } else {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.tempoTextTertiary)

                Text("--")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Strain vs Recovery Balance

    private func strainRecoveryBalanceSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Strain vs Recovery Balance")

            VStack(spacing: TempoSpacing.sm) {
                // 7-day chart showing strain and recovery side by side
                let last7 = Array(viewModel.recentRecoveries.suffix(7))

                if last7.count >= 3 {
                    // Bar representation
                    ForEach(last7, id: \.id) { day in
                        HStack(spacing: TempoSpacing.sm) {
                            // Day label
                            Text(day.date, format: .dateTime.weekday(.abbreviated))
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .frame(width: 32, alignment: .leading)

                            // Recovery bar
                            GeometryReader { geo in
                                let recoveryFraction = min(day.recoveryScore / 100.0, 1.0)
                                let strainFraction = min((day.strain ?? 0) / 21.0, 1.0)

                                VStack(spacing: 2) {
                                    // Recovery
                                    HStack(spacing: 0) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(RecoveryZone(score: day.recoveryScore).zoneColor)
                                            .frame(width: geo.size.width * recoveryFraction, height: 10)
                                        Spacer(minLength: 0)
                                    }
                                    // Strain
                                    HStack(spacing: 0) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Color.tempoRecoveryYellow.opacity(0.7))
                                            .frame(width: geo.size.width * strainFraction, height: 10)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .frame(height: 22)

                            // Score labels
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(Int(day.recoveryScore))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(RecoveryZone(score: day.recoveryScore).zoneColor)
                                Text(day.strain.map { String(format: "%.0f", $0) } ?? "--")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.tempoRecoveryYellow)
                            }
                            .frame(width: 30, alignment: .trailing)
                        }
                    }

                    // Legend
                    HStack(spacing: TempoSpacing.lg) {
                        HStack(spacing: TempoSpacing.xxs) {
                            Circle()
                                .fill(Color.tempoRecoveryGreen)
                                .frame(width: 8, height: 8)
                            Text("Recovery")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        HStack(spacing: TempoSpacing.xxs) {
                            Circle()
                                .fill(Color.tempoRecoveryYellow)
                                .frame(width: 8, height: 8)
                            Text("Strain")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Spacer()
                        Text("Total: \(String(format: "%.0f", stats.totalStrain))")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .padding(.top, TempoSpacing.xs)

                    // Balance assessment
                    let balanceText = strainRecoveryAssessment(stats)
                    if !balanceText.isEmpty {
                        Text(balanceText)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .lineSpacing(2)
                            .padding(.top, TempoSpacing.xs)
                    }
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    private func strainRecoveryAssessment(_ stats: RecoveryViewModel.WeeklyStats) -> String {
        let avgStrain = stats.totalStrain / 7.0
        let avgRecovery = stats.avgRecovery

        if avgRecovery >= 67, avgStrain >= 12 {
            return "Great balance. You're training hard and recovering well. Keep this rhythm."
        } else if avgRecovery < 50, avgStrain >= 14 {
            return "Your strain is outpacing your recovery. Consider reducing training volume this week or adding an extra rest day."
        } else if avgRecovery >= 67, avgStrain < 10 {
            return "You have room to push harder. Your recovery supports more training stimulus."
        } else if avgRecovery < 50, avgStrain < 10 {
            return "Both strain and recovery are low. Focus on sleep quality and nutrition to build your recovery back up."
        }
        return "Moderate balance. Monitor how you feel and adjust training intensity day-by-day."
    }

    // MARK: - Recovery Distribution

    private var recoveryDistributionSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Recovery Distribution")

            let last7 = Array(viewModel.recentRecoveries.suffix(7))
            let greenDays = last7.count(where: { $0.recoveryScore >= 67 })
            let yellowDays = last7.count(where: { $0.recoveryScore >= 34 && $0.recoveryScore < 67 })
            let redDays = last7.count(where: { $0.recoveryScore < 34 })

            HStack(spacing: TempoSpacing.sm) {
                distributionTile(
                    label: "Green",
                    count: greenDays,
                    total: last7.count,
                    color: Color.tempoRecoveryGreen
                )
                distributionTile(
                    label: "Yellow",
                    count: yellowDays,
                    total: last7.count,
                    color: Color.tempoRecoveryYellow
                )
                distributionTile(
                    label: "Red",
                    count: redDays,
                    total: last7.count,
                    color: Color.tempoRecoveryRed
                )
            }
        }
    }

    private func distributionTile(label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text("\(count)")
                .font(.tempoLargeTitle)
                .foregroundStyle(color)

            Text(count == 1 ? "day" : "days")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(label)
                .font(.tempoCaption1)
                .fontWeight(.medium)
                .foregroundStyle(color)

            // Mini bar
            GeometryReader { geo in
                let fraction = total > 0 ? Double(count) / Double(total) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }
}

// MARK: - RecoveryZone Color Helper

private extension RecoveryZone {
    var zoneColor: Color {
        switch self {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
    }
}
