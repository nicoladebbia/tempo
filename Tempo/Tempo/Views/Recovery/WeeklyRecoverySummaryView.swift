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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        TideScrollPage {
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
                TideEmptyPanel(
                    systemImage: "chart.bar.xaxis",
                    title: "Need at least 3 days of data",
                    message: "Keep wearing your Whoop and check back soon for your weekly summary."
                )
                .tideCard()
            }
        }
        .navigationTitle("Weekly Summary")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Averages Section

    private func averagesSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "7-day averages")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: 2),
                spacing: Tide.s3
            ) {
                TideMetricTile(
                    label: "Recovery",
                    value: "\(Int(stats.avgRecovery))",
                    unit: "%",
                    tint: RecoveryZone(score: stats.avgRecovery).tideColor,
                    systemImage: "heart.text.square.fill"
                )
                TideMetricTile(
                    label: "HRV",
                    value: "\(Int(stats.avgHRV))",
                    unit: "ms",
                    tint: TideSleepStage.rem,
                    systemImage: "waveform.path.ecg"
                )
                TideMetricTile(
                    label: "RHR",
                    value: "\(Int(stats.avgRHR))",
                    unit: "bpm",
                    tint: Tide.danger,
                    systemImage: "heart.fill"
                )
                TideMetricTile(
                    label: "Sleep",
                    value: String(format: "%.1f", stats.avgSleep),
                    unit: "h",
                    tint: TideSleepStage.light,
                    systemImage: "moon.zzz.fill"
                )
            }
        }
    }

    // MARK: - Best & Worst Days

    private func bestWorstSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Highlights")

            if let best = stats.bestDay {
                dayHighlightCard(
                    icon: "arrow.up.circle.fill",
                    label: "Best day",
                    date: best.0,
                    score: best.1,
                    explanation: bestDayExplanation(best.0),
                    color: TideTone.mint
                )
            }

            if let worst = stats.worstDay {
                dayHighlightCard(
                    icon: "arrow.down.circle.fill",
                    label: "Toughest day",
                    date: worst.0,
                    score: worst.1,
                    explanation: worstDayExplanation(worst.0),
                    color: Tide.danger
                )
            }
        }
    }

    private func dayHighlightCard(icon: String, label: String, date: Date, score: Double, explanation: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.title2)
                .foregroundStyle(color)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)

                    Spacer(minLength: Tide.s2)

                    TideNumber("\(Int(score))", unit: "%", size: Tide.numeralM, relativeTo: .title2, color: color)
                }

                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)

                if !explanation.isEmpty {
                    Text(explanation)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .lineSpacing(Tide.hair)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
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
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Vs last week")

            layout {
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
        let delta = previous.map { current - $0 }
        let isPositive = delta.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }
        let tint = isPositive.map { $0 ? TideTone.mint : Tide.danger } ?? Tide.text3
        let formatted = delta.map { unit == "h" ? String(format: "%+.1f", $0) : String(format: "%+.0f", $0) }
        return VStack(spacing: Tide.s2) {
            Text(label)
                .tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)

            Image(systemName: isPositive.map { $0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
                .font(Tide.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(formatted.map { "\($0)\(unit)" } ?? "--")
                .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            formatted.map { "\(label) \($0) \(unit), \(isPositive == true ? "better" : "worse") than last week" }
                ?? "\(label), no data for last week"
        )
    }

    // MARK: - Strain vs Recovery Balance

    private func strainRecoveryBalanceSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        let last7 = Array(viewModel.recentRecoveries.suffix(7))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Strain vs recovery balance")

            if last7.count >= 3 {
                VStack(spacing: Tide.s3) {
                    // One row per day: recovery bar over strain bar
                    ForEach(last7, id: \.id) { day in
                        balanceRow(day)
                    }

                    // Legend
                    HStack(spacing: Tide.s4) {
                        legendDot(label: "Recovery", color: TideTone.mint)
                        legendDot(label: "Strain", color: TideTone.amber)
                        Spacer(minLength: Tide.s2)
                        Text("Total: \(String(format: "%.0f", stats.totalStrain))")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    .padding(.top, Tide.s1)

                    // Balance assessment
                    let balanceText = strainRecoveryAssessment(stats)
                    if !balanceText.isEmpty {
                        Text(balanceText)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .lineSpacing(Tide.hair)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .tideCard()
            } else {
                Text("Need at least 3 days to compare strain and recovery.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
        }
    }

    private func balanceRow(_ day: DailyRecovery) -> some View {
        let zone = RecoveryZone(score: day.recoveryScore)
        return HStack(spacing: Tide.s3) {
            // Day label
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.s8, alignment: .leading)

            VStack(spacing: Tide.s1) {
                barTrack(fraction: min(day.recoveryScore / 100.0, 1.0), color: zone.tideColor)
                barTrack(fraction: min((day.strain ?? 0) / 21.0, 1.0), color: TideTone.amber.opacity(0.8))
            }

            // Score labels
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(day.recoveryScore))%")
                    .font(Tide.numeral(Tide.axisSize + 1, .semibold))
                    .foregroundStyle(zone.tideColor)
                Text(day.strain.map { String(format: "%.0f", $0) } ?? "--")
                    .font(Tide.numeral(Tide.axisSize + 1, .medium))
                    .foregroundStyle(TideTone.amber)
            }
            .frame(minWidth: Tide.s10, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(
            "Recovery \(Int(day.recoveryScore)) percent, strain \(day.strain.map { String(format: "%.0f", $0) } ?? "none")"
        )
    }

    private func barTrack(fraction: Double, color: Color) -> some View {
        Capsule()
            .fill(Tide.fill)
            .frame(height: Tide.s2)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(Tide.s2, geo.size.width * fraction))
                }
            }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: Tide.s2) {
            Circle()
                .fill(color)
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
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
        let last7 = Array(viewModel.recentRecoveries.suffix(7))
        let greenDays = last7.count(where: { $0.recoveryScore >= 67 })
        let yellowDays = last7.count(where: { $0.recoveryScore >= 34 && $0.recoveryScore < 67 })
        let redDays = last7.count(where: { $0.recoveryScore < 34 })
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Recovery distribution")

            layout {
                distributionTile(label: "Green", count: greenDays, total: last7.count, color: TideTone.mint)
                distributionTile(label: "Yellow", count: yellowDays, total: last7.count, color: TideTone.amber)
                distributionTile(label: "Red", count: redDays, total: last7.count, color: Tide.danger)
            }
        }
    }

    private func distributionTile(label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(spacing: Tide.s2) {
            TideNumber("\(count)", size: Tide.numeralL, relativeTo: .largeTitle, color: color)

            Text(count == 1 ? "day" : "days")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)

            Text(label).tideLabel(color)

            barTrack(fraction: total > 0 ? Double(count) / Double(total) : 0, color: color)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) zone, \(count) \(count == 1 ? "day" : "days") of \(total)")
    }
}
