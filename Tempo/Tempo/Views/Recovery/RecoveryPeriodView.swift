//
// RecoveryPeriodView.swift
// Tempo
//
// The Week and Month views of the Recovery page: how the period averaged and
// moved against the one before, the trend chart, best and toughest day, strain
// against recovery, the zone split and pattern insights. It replaces the old
// Trends tab and the weekly recovery report, which were two pages for one
// question. Per MODULE_RECOVERY.md Section 7.
//

import SwiftData
import SwiftUI

// MARK: - RecoveryPeriodView

struct RecoveryPeriodView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var showRecovery = true
    @State
    private var showHRV = true
    @State
    private var showRHR = false

    private var days: Int {
        viewModel.trendRangeDays(viewModel.selectedTrendRange)
    }

    /// "7-day", "30-day" or "90-day".
    private var periodName: String {
        "\(days)-day"
    }

    /// What the period is set against.
    private var comparisonName: String {
        switch viewModel.selectedTrendRange {
        case .week: "last week"
        case .month: "last month"
        case .quarter: "the 90 days before"
        }
    }

    var body: some View {
        TideScrollPage(energy: 1) {
            if let stats = viewModel.periodStats {
                // A refresh that failed with numbers on screen keeps them.
                if case let .error(message) = viewModel.loadState {
                    RecoveryErrorBanner(message: message)
                }

                // The period's recovery, and how it moved
                heroSection(stats)

                // Average HRV, RHR and sleep with their change
                averagesSection(stats)

                // Recovery, HRV and RHR over the period
                trendSection

                // Sleep hours and strain over the period
                singleTrendSection(
                    title: "Sleep trend", id: "sleep", label: "Sleep", color: TideSleepStage.deep,
                    data: viewModel.sleepChartData, fitsRange: true
                )
                singleTrendSection(
                    title: "Strain trend", id: "strain", label: "Strain", color: TideTone.amber,
                    data: viewModel.strainChartData
                )

                // Best and toughest day
                highlightsSection(stats)

                // Strain against recovery
                balanceSection(stats)

                // Green, yellow and red days
                distributionSection(stats)

                // Patterns found in the data
                insightsSection
            } else if case let .error(message) = viewModel.loadState {
                RecoveryErrorPanel(message: message) {
                    Task { await viewModel.forceRefresh(modelContext: modelContext) }
                }
            } else if viewModel.loadState == .loading {
                RecoverySkeleton(label: "Loading recovery")
                    .padding(.horizontal, -Tide.edge)
            } else {
                TideEmptyPanel(
                    systemImage: "chart.bar.xaxis",
                    title: "Need at least 3 days of data",
                    message: "Keep wearing your WHOOP and check back soon for your trends."
                )
                .tideCard()
                .accessibilityIdentifier("recovery-period-empty")
            }
        }
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
        .accessibilityIdentifier("recovery-period-view")
    }

    // MARK: - Hero

    /// The period's average recovery on the dial, with its zone and how it moved.
    private func heroSection(_ stats: RecoveryPeriodStats) -> some View {
        let zone = RecoveryZone(score: stats.avgRecovery)
        return RecoveryHero {
            TideDial(score: Int(stats.avgRecovery), caption: "\(periodName) avg", diameter: Tide.dialHero)
                .explains(Explainer.recoveryAverage.showing("\(Int(stats.avgRecovery)) percent"))
        } side: {
            Text("Recovery").tideLabel(Tide.text3)
            Text("\(zone.displayName) zone")
                .font(Tide.title2)
                .foregroundStyle(zone.tideColor)
            changeLine(
                current: stats.avgRecovery, previous: stats.previous?.recovery,
                unit: "%", higherIsBetter: true, withComparison: true
            )
            Text(stats.dayCount == 1 ? "1 day with a reading" : "\(stats.dayCount) days with readings")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        // `.contain`, not `.combine`: the dial is a button that opens its explainer.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            stats.dayCount == 1
                ? "Average recovery \(Int(stats.avgRecovery)) percent over 1 day, \(zone.displayName) zone"
                : "Average recovery \(Int(stats.avgRecovery)) percent over \(stats.dayCount) days, \(zone.displayName) zone"
        )
        .accessibilityIdentifier("recovery-period-hero")
    }

    // MARK: - Averages

    /// HRV, resting heart rate and sleep in one card, each with its change. They
    /// stack at accessibility text sizes. A vital with no readings shows "--".
    private func averagesSection(_ stats: RecoveryPeriodStats) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "\(periodName) averages", trailing: "Change vs \(comparisonName)")

            layout {
                averageColumn(
                    label: "HRV", value: stats.avgHRV.map { "\(Int($0))" }, unit: "ms",
                    current: stats.avgHRV, previous: stats.previous?.hrv, higherIsBetter: true
                )
                if !stacked {
                    columnDivider
                }
                averageColumn(
                    label: "RHR", value: stats.avgRHR.map { "\(Int($0))" }, unit: "bpm",
                    current: stats.avgRHR, previous: stats.previous?.rhr, higherIsBetter: false
                )
                if !stacked {
                    columnDivider
                }
                averageColumn(
                    label: "Sleep", value: stats.avgSleep.map { String(format: "%.1f", $0) }, unit: "h",
                    current: stats.avgSleep, previous: stats.previous?.sleep, higherIsBetter: true
                )
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .explains(.periodAverages)
        }
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(width: Tide.rule)
            .accessibilityHidden(true)
    }

    private func averageColumn(
        label: String, value: String?, unit: String,
        current: Double?, previous: Double?, higherIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            TideNumber(value ?? "--", unit: value == nil ? nil : unit, size: Tide.numeralM, relativeTo: .title2)
            if let current {
                changeLine(current: current, previous: previous, unit: unit, higherIsBetter: higherIsBetter)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// An arrow and the signed change against the period before. Green is the
    /// good side. A change that rounds to nothing reads "Same".
    private func changeLine(
        current: Double, previous: Double?, unit: String, higherIsBetter: Bool, withComparison: Bool = false
    ) -> some View {
        let delta = previous.map { current - $0 }
        let isFlat = delta.map { unit == "h" ? ($0 * 10).rounded() == 0 : $0.rounded() == 0 } ?? false
        let isPositive = delta.map { higherIsBetter ? $0 >= 0 : $0 <= 0 }
        let tint = isFlat ? Tide.text2 : (isPositive.map { $0 ? TideTone.mint : Tide.danger } ?? Tide.text3)
        let formatted = delta.map { unit == "h" ? String(format: "%+.1f", $0) : String(format: "%+.0f", $0) }
        // The arrow points the way the number moved; the colour says if that is good.
        let icon = isFlat ? "equal" : (delta.map { $0 > 0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
        return HStack(spacing: Tide.s1) {
            Image(systemName: icon)
                .font(Tide.label)
                .accessibilityHidden(true)
            changeText(formatted: formatted, unit: unit, isFlat: isFlat, withComparison: withComparison)
                .font(Tide.caption.weight(.semibold).monospacedDigit())
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .foregroundStyle(tint)
    }

    private func changeText(formatted: String?, unit: String, isFlat: Bool, withComparison: Bool) -> Text {
        guard let formatted else {
            return Text("No earlier data")
        }
        if isFlat {
            // The tile header already says "Change vs last week"; only the hero line spells it out.
            return withComparison ? Text("Same as \(comparisonName)") : Text("Same")
        }
        return withComparison ? Text("\(formatted)\(unit) vs \(comparisonName)") : Text("\(formatted)\(unit)")
    }

    // MARK: - Trend chart

    // Per MODULE_RECOVERY.md Section 7: recovery, HRV and RHR overlaid

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Trend")

            VStack(alignment: .leading, spacing: Tide.s4) {
                if chartData.isEmpty {
                    RecoveryChartPlaceholder(
                        message: "Need more days of data to show trends.",
                        height: Tide.chartHeight + Tide.s5
                    )
                } else {
                    TideLineChart(
                        data: chartData,
                        height: Tide.chartHeight + Tide.s5
                    )
                }

                legendRow
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var chartData: [TempoLineChartData<String>] {
        var series: [TempoLineChartData<String>] = []

        if showRecovery, viewModel.recoveryChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "recovery", label: "Recovery", color: TideTone.mint,
                    points: viewModel.recoveryChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }
        if showHRV, viewModel.hrvChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "hrv", label: "HRV", color: TideSleepStage.rem,
                    points: viewModel.hrvChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }
        if showRHR, viewModel.rhrChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "rhr", label: "RHR", color: Tide.danger,
                    points: viewModel.rhrChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }
        return series
    }

    /// One vital over the period, in a card of its own.
    /// `fitsRange` draws the chart over the range the values actually span (sleep
    /// hours 7 to 8) instead of from zero, so the change shows.
    private func singleTrendSection(
        title: String, id: String, label: String, color: Color, data: [(Date, Double)], fitsRange: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: title)

            Group {
                if data.count >= 3 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: id, label: label, color: color,
                                points: data.map { TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1) }
                            ),
                        ],
                        height: Tide.chartHeight,
                        yDomain: fitsRange ? ChartScale.fitted(data.map(\.1)) : nil
                    )
                } else {
                    RecoveryChartPlaceholder(message: "Need more days of data to show trends.")
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
        .accessibilityIdentifier("recovery-\(id)-trend")
    }

    // Per MODULE_RECOVERY.md Section 7: toggle legend

    private var legendRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            legendToggle(label: "Recovery", color: TideTone.mint, isOn: $showRecovery)
            legendToggle(label: "HRV", color: TideSleepStage.rem, isOn: $showHRV)
            legendToggle(label: "RHR", color: Tide.danger, isOn: $showRHR)
        }
    }

    private func legendToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(Tide.snap) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Tide.s2) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Tide.text3)
                    .frame(width: Tide.s3, height: Tide.s3)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(isOn.wrappedValue ? Tide.text : Tide.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .padding(.horizontal, Tide.s3)
            .frame(minHeight: Tide.hit)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("recovery-trend-toggle-\(label.lowercased())")
    }

    // MARK: - Best and toughest day

    private func highlightsSection(_ stats: RecoveryPeriodStats) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Highlights")

            // One card, two rows: the best day and the toughest day.
            VStack(spacing: Tide.s4) {
                if let best = stats.best {
                    dayHighlight(
                        icon: "arrow.up.circle.fill", label: "Best day",
                        date: best.date, score: best.score,
                        explanation: bestDayExplanation(best.date), color: TideTone.mint
                    )
                }

                if stats.best != nil, stats.worst != nil {
                    TideDivider()
                }

                if let worst = stats.worst {
                    dayHighlight(
                        icon: "arrow.down.circle.fill", label: "Toughest day",
                        date: worst.date, score: worst.score,
                        explanation: worstDayExplanation(worst.date), color: Tide.danger
                    )
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func dayHighlight(
        icon: String, label: String, date: Date, score: Double, explanation: String, color: Color
    ) -> some View {
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

    private func recovery(on date: Date) -> DailyRecovery? {
        viewModel.recentRecoveries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func bestDayExplanation(_ date: Date) -> String {
        guard let recovery = recovery(on: date) else {
            return ""
        }
        var reasons: [String] = []
        if let sleep = recovery.sleepHours, sleep >= 7.5 {
            reasons.append("\(String(format: "%.1f", sleep))h of quality sleep")
        }
        if let hrv = recovery.hrvRmssd, let baseline = viewModel.hrvBaseline30d, Int(hrv - baseline) >= 1 {
            reasons.append("HRV \(Int(hrv - baseline))ms above baseline")
        }
        if let rhr = recovery.restingHR, let baseline = viewModel.rhrBaseline30d, Int(baseline - rhr) >= 1 {
            reasons.append("RHR \(Int(baseline - rhr))bpm below average")
        }
        return reasons.isEmpty ? "Strong recovery across all metrics." : reasons.joined(separator: ", ") + "."
    }

    private func worstDayExplanation(_ date: Date) -> String {
        guard let recovery = recovery(on: date) else {
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

    // MARK: - Strain against recovery

    private func balanceSection(_ stats: RecoveryPeriodStats) -> some View {
        // One row per day only fits a week. A month gets the summary.
        let rows = days <= 7 ? viewModel.periodReadings : []
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Strain vs recovery balance")

            VStack(spacing: Tide.s3) {
                ForEach(rows, id: \.date) { day in
                    balanceRow(day)
                }

                if !rows.isEmpty {
                    balanceLegend(stats)
                }

                if rows.isEmpty, let avgStrain = stats.avgStrain {
                    TideNumber(
                        String(format: "%.1f", avgStrain), unit: "avg strain",
                        size: Tide.numeralM, relativeTo: .title2, color: TideTone.amber
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let avgStrain = stats.avgStrain {
                    Text(RecoveryBalance.assessment(avgRecovery: stats.avgRecovery, avgStrain: avgStrain))
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .lineSpacing(Tide.hair)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No strain recorded in this period.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tideCard()
            .explains(.strainBalance)
        }
    }

    private func balanceLegend(_ stats: RecoveryPeriodStats) -> some View {
        let legend = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return legend {
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
    }

    private func balanceRow(_ day: RecoveryDayReading) -> some View {
        let zone = RecoveryZone(score: day.recovery)
        return HStack(spacing: Tide.s3) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.s8, alignment: .leading)

            VStack(spacing: Tide.s1) {
                barTrack(fraction: min(day.recovery / 100.0, 1.0), color: zone.tideColor)
                barTrack(fraction: min((day.strain ?? 0) / 21.0, 1.0), color: TideTone.amber.opacity(0.8))
            }

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(day.recovery))%")
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
            "Recovery \(Int(day.recovery)) percent, strain \(day.strain.map { String(format: "%.0f", $0) } ?? "none")"
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

    // MARK: - Zone split

    private func distributionSection(_ stats: RecoveryPeriodStats) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Recovery distribution")

            layout {
                distributionTile(label: "Green", count: stats.greenDays, total: stats.dayCount, color: TideTone.mint)
                distributionTile(label: "Yellow", count: stats.yellowDays, total: stats.dayCount, color: TideTone.amber)
                distributionTile(label: "Red", count: stats.redDays, total: stats.dayCount, color: Tide.danger)
            }
            .explains(.recoveryDistribution)
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

    // MARK: - Pattern insights

    // Per MODULE_RECOVERY.md Section 7: pattern insight cards

    @ViewBuilder
    private var insightsSection: some View {
        if !viewModel.insights.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Pattern insights")

                ForEach(viewModel.insights, id: \.id) { insight in
                    insightCard(insight)
                }
            }
        }
    }

    private func insightCard(_ insight: RecoveryInsight) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: "lightbulb.fill")
                .font(Tide.headline)
                .foregroundStyle(TideTone.amber)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(insight.title)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)

                Text(insight.body)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}
