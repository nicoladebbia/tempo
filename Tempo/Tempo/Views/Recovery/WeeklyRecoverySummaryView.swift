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
                // The week's recovery, and how it moved against last week
                heroSection(stats)

                // Average HRV, RHR and sleep with their change vs last week
                averagesSection(stats)

                // Best & Worst Days
                bestWorstSection(stats)

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

    /// The hero: the week's average recovery on the dial, with its zone and
    /// how it moved against last week.
    private func heroSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        let zone = RecoveryZone(score: stats.avgRecovery)
        return RecoveryHero {
            TideDial(score: Int(stats.avgRecovery), caption: "7-day avg", diameter: Tide.dialHero)
        } side: {
            Text("Recovery").tideLabel(Tide.text3)
            Text("\(zone.displayName) zone")
                .font(Tide.title2)
                .foregroundStyle(zone.tideColor)
            changeLine(
                current: stats.avgRecovery, previous: stats.prevWeekAvgRecovery,
                unit: "%", higherIsBetter: true, suffix: " vs last week"
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Average recovery \(Int(stats.avgRecovery)) percent, \(zone.displayName) zone")
    }

    /// HRV, resting heart rate and sleep in one card, each with its change vs
    /// last week. They stack at accessibility text sizes.
    private func averagesSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "7-day averages", trailing: "Change vs last week")

            layout {
                averageColumn(
                    label: "HRV", value: "\(Int(stats.avgHRV))", unit: "ms",
                    current: stats.avgHRV, previous: stats.prevWeekAvgHRV, higherIsBetter: true
                )
                if !stacked {
                    columnDivider
                }
                averageColumn(
                    label: "RHR", value: "\(Int(stats.avgRHR))", unit: "bpm",
                    current: stats.avgRHR, previous: stats.prevWeekAvgRHR, higherIsBetter: false
                )
                if !stacked {
                    columnDivider
                }
                averageColumn(
                    label: "Sleep", value: String(format: "%.1f", stats.avgSleep), unit: "h",
                    current: stats.avgSleep, previous: stats.prevWeekAvgSleep, higherIsBetter: true
                )
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(width: Tide.rule)
            .accessibilityHidden(true)
    }

    private func averageColumn(
        label: String, value: String, unit: String,
        current: Double, previous: Double?, higherIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            TideNumber(value, unit: unit, size: Tide.numeralM, relativeTo: .title2)
            changeLine(current: current, previous: previous, unit: unit, higherIsBetter: higherIsBetter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(changeLabel(label: label, current: current, previous: previous, unit: unit, higherIsBetter: higherIsBetter))
    }

    /// An arrow and the signed change against last week. Green is the good side.
    private func changeLine(
        current: Double, previous: Double?, unit: String, higherIsBetter: Bool, suffix: String = ""
    ) -> some View {
        let delta = previous.map { current - $0 }
        let isPositive = delta.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }
        let tint = isPositive.map { $0 ? TideTone.mint : Tide.danger } ?? Tide.text3
        let formatted = delta.map { unit == "h" ? String(format: "%+.1f", $0) : String(format: "%+.0f", $0) }
        return HStack(spacing: Tide.s1) {
            Image(systemName: isPositive.map { $0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
                .font(Tide.label)
                .accessibilityHidden(true)
            Text(formatted.map { "\($0)\(unit)\(suffix)" } ?? "No last week")
                .font(Tide.numeral(Tide.axisSize + 1, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .foregroundStyle(tint)
    }

    private func changeLabel(label: String, current: Double, previous: Double?, unit: String, higherIsBetter: Bool) -> String {
        let delta = previous.map { current - $0 }
        let isPositive = delta.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }
        let formatted = delta.map { unit == "h" ? String(format: "%+.1f", $0) : String(format: "%+.0f", $0) }
        let value = unit == "h" ? String(format: "%.1f", current) : "\(Int(current))"
        return formatted.map {
            "\(label) \(value) \(unit), \($0) \(unit), \(isPositive == true ? "better" : "worse") than last week"
        } ?? "\(label) \(value) \(unit), no data for last week"
    }

    // MARK: - Best & Worst Days

    private func bestWorstSection(_ stats: RecoveryViewModel.WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Highlights")

            // One card, two rows: the best day and the toughest day.
            VStack(spacing: Tide.s4) {
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

                if stats.bestDay != nil, stats.worstDay != nil {
                    TideDivider()
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
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
                // The score drops under the name when the text is large.
                let head = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                head {
                    Text(label)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }

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
                    let legend = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                        : AnyLayout(HStackLayout(spacing: Tide.s4))
                    legend {
                        legendDot(label: "Recovery", color: TideTone.mint)
                        legendDot(label: "Strain", color: TideTone.amber)
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: Tide.s2)
                        }
                        Text("Total: \(String(format: "%.0f", stats.totalStrain))")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        .frame(width: fraction > 0 ? max(Tide.s2, geo.size.width * fraction) : 0)
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
