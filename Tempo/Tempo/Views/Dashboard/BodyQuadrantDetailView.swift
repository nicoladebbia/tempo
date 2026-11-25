//
// BodyQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - BodyQuadrantDetailView

// Per MODULE_DASHBOARD.md Section 4.2 — Body Expanded View.
// Today's recovery and vitals, the last 7 days, last night's sleep stages, strain,
// and how today compares. Every number comes from Whoop or Health: today's from
// the live read, the history from the days stored on the phone. Where there is
// none yet, the page says so instead of showing a stand-in. Body progress
// (weight, body fat, lean mass, photos) opens from here.

struct BodyQuadrantDetailView: View {
    // MARK: Internal

    let data: BodyQuadrantData

    var body: some View {
        TideScrollPage {
            if showsRecovery {
                heroSection
                if typeSize.isAccessibilitySize, !data.isConnected {
                    connectButton
                }
                vitalsSection
            } else {
                noDataSection
            }

            BodyProgressLinkCard()

            if showsRecovery {
                trendSection
                sleepSection
                strainSection
                comparisonSection
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The one action while nothing is connected, under the thumb.
            if !data.isConnected, !typeSize.isAccessibilitySize {
                connectButton
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s3)
                    .padding(.bottom, Tide.s2)
                    .pinnedBarScrim()
            }
        }
        // The page the Sleep card opens: there is no separate sleep screen.
        .firstTip(
            "recovery.sleep",
            "Tap a number to see how it is worked out. Weight and photos are under Body progress.",
            systemImage: "moon.zzz"
        )
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .tideCovered(showWhoopConnect)
        .sheet(isPresented: $showWhoopConnect) {
            NavigationStack {
                WhoopConnectionView()
            }
        }
        .accessibilityIdentifier("body-page")
    }

    // MARK: Private

    /// One line of the comparison card: a period and what changed in it.
    private struct ComparisonLine: Identifiable {
        struct Cell: Identifiable {
            let label: String
            let value: String
            let color: Color
            var id: String {
                label
            }
        }

        let title: String
        let cells: [Cell]
        var id: String {
            title
        }
    }

    @Query(bodyRecentDescriptor())
    private var recent: [DailyRecovery]
    @State
    private var showWhoopConnect = false
    @Environment(\.dynamicTypeSize)
    private var typeSize

    // MARK: Data

    /// The stored days as plain readings, newest first.
    private var readings: [RecoveryDayReading] {
        recent.map(RecoveryViewModel.reading(from:))
    }

    /// The last 7 calendar days that have readings, oldest first.
    private var week: [RecoveryDayReading] {
        RecoveryWindow.select(readings, days: 7, endingOn: Date())
    }

    private var baseline: BodyHistory.Baseline {
        BodyHistory.baseline(readings, today: Date())
    }

    private var todayReading: RecoveryDayReading? {
        BodyHistory.reading(on: Date(), in: readings)
    }

    /// Last night's stage minutes, from today's stored day.
    private var stages: SleepStageMinutes? {
        guard let row = recent.first(where: { Calendar.current.isDateInToday($0.date) }) else {
            return nil
        }
        return SleepStageMinutes(
            deep: row.deepSleepMin, rem: row.remSleepMin, light: row.lightSleepMin, awake: row.awakeMin
        )
    }

    /// Something to show: a live read, or days already stored on the phone.
    private var showsRecovery: Bool {
        data.isConnected || !week.isEmpty
    }

    private var zoneColor: Color {
        data.recoveryZone?.tideColor ?? Tide.text3
    }

    private var recoveryQuip: String {
        guard let score = data.recoveryScore else {
            return ""
        }
        switch score {
        case 90 ... 100: return "Go break something. In a good way."
        case 67 ..< 90: return "You're good to push it."
        case 50 ..< 67: return "Yellow zone. Choose your battles."
        case 34 ..< 50: return "Your body is waving a yellow flag."
        default: return "Sit down. Seriously."
        }
    }

    private var connectButton: some View {
        Button {
            showWhoopConnect = true
        } label: {
            Text("Connect WHOOP")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tidePrimary)
        .accessibilityIdentifier("body-connect-whoop")
    }

    // MARK: - Nothing yet

    // Neither a live read nor a stored day: the one thing to do is connect.

    private var noDataSection: some View {
        TideEmptyPanel(
            systemImage: "sensor.tag.radiowaves.forward.fill",
            title: "No Whoop connected",
            message: "Connect your Whoop to see recovery, HRV, sleep, and strain data."
        )
        .tideCard()
    }

    // MARK: - Hero

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Hero Section

    private var heroSection: some View {
        RecoveryHero {
            TideDial(
                score: data.recoveryScore.map { Int($0.rounded()) },
                caption: "Recovery",
                diameter: Tide.dialHero
            )
            .explains(
                Explainer.bodyRecovery(zone: data.recoveryZone)
                    .showing(data.recoveryScore.map { "\(Int($0.rounded())) percent" })
            )
        } side: {
            if data.dataSource != .none {
                TideStatusPill(
                    text: data.dataSource.rawValue,
                    tint: Tide.text2,
                    systemImage: data.dataSource == .whoop ? "sensor.tag.radiowaves.forward.fill" : "applewatch"
                )
            }

            if let zone = data.recoveryZone {
                Text("\(zone.displayName) zone")
                    .font(Tide.title2)
                    .foregroundStyle(zoneColor)
                Text(recoveryQuip)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No recovery yet")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                Text(
                    data.dataSource == .healthKit
                        ? "Health has no recovery score. Connect WHOOP for the full picture."
                        : "Today's score lands once last night is processed."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Vitals

    // Per MODULE_DASHBOARD.md Section 4.2 — Metric Cards. Each is today's value
    // against the average of the days before it, once there are enough days.

    private var vitalsSection: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Tide.s3),
                count: typeSize.isAccessibilitySize ? 1 : 2
            ),
            spacing: Tide.s3
        ) {
            vitalTile(
                label: "HRV", value: data.hrv.map { String(format: "%.0f", $0) }, unit: "ms",
                explainer: .bodyHRV,
                note: comparisonNote(current: data.hrv, baseline: baseline.hrv, higherIsBetter: true)
            )
            vitalTile(
                label: "Resting HR", value: data.rhr.map { "\(Int($0))" }, unit: "bpm",
                explainer: .bodyRestingHeartRate,
                note: comparisonNote(current: data.rhr, baseline: baseline.rhr, higherIsBetter: false)
            )
            vitalTile(
                label: "Sleep", value: data.sleepHours.map { String(format: "%.1f", $0) }, unit: "h",
                explainer: .bodySleep,
                note: comparisonNote(current: data.sleepHours, baseline: baseline.sleepHours, higherIsBetter: true)
            )
            vitalTile(
                label: "SpO2", value: data.spo2.map { "\(Int($0))" }, unit: "%",
                explainer: .bodyOxygen,
                note: oxygenNote
            )
        }
    }

    private func vitalTile(
        label: String, value: String?, unit: String, explainer: Explainer, note: (String, Color)
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(label)
                .tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            TideNumber(
                value ?? "--", unit: value == nil ? nil : unit,
                size: Tide.numeralS + Tide.s1, relativeTo: .title3,
                color: value == nil ? Tide.text3 : Tide.text
            )
            Text(note.0)
                .font(Tide.caption)
                .foregroundStyle(note.1)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
        .explains(explainer.showing(value.map { "\($0) \(unit)" }))
    }

    /// How today sits against the average of the days before. Silent without a
    /// reading, and without enough days to average.
    private func comparisonNote(current: Double?, baseline: Double?, higherIsBetter: Bool) -> (String, Color) {
        guard let current else {
            return ("No reading", Tide.text3)
        }
        guard let baseline else {
            return ("No baseline yet", Tide.text3)
        }
        let verdict = BodyHistory.verdict(current: current, baseline: baseline, higherIsBetter: higherIsBetter)
        switch verdict {
        case .same:
            return ("Near average", Tide.text2)
        case .better:
            return (higherIsBetter ? "Above average" : "Below average", TideTone.mint)
        case .worse:
            return (higherIsBetter ? "Below average" : "Above average", Tide.danger)
        }
    }

    private var oxygenNote: (String, Color) {
        guard let spo2 = data.spo2 else {
            return ("No reading", Tide.text3)
        }
        return spo2 >= 95 ? ("Normal", TideTone.mint) : ("Low", Tide.danger)
    }

    // MARK: - Recovery Trend

    // Per MODULE_DASHBOARD.md Section 4.2 — Recovery Trend Chart (7 Days)

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Recovery trend", trailing: "7 days")

            Group {
                if week.count >= 2 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: "recovery", label: "Recovery", color: TideTone.mint,
                                points: week.map { TempoLineChartData<String>.DataPoint(date: $0.date, value: $0.recovery) }
                            ),
                        ],
                        height: Tide.chartHeight,
                        valueFormat: .number.precision(.fractionLength(0))
                    )
                } else {
                    RecoveryChartPlaceholder(message: "Need two days of recovery to draw a trend.")
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
        .accessibilityIdentifier("body-trend")
    }

    // MARK: - Sleep

    // Per MODULE_DASHBOARD.md Section 4.2 — Sleep Breakdown

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Last night's sleep")

            if let stages {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    RecoveryStagesBar(
                        segments: stageSegments(stages),
                        accessibilityValue: "Deep \(SleepStageMinutes.formatted(stages.deep)), REM \(SleepStageMinutes.formatted(stages.rem)), "
                            + "light \(SleepStageMinutes.formatted(stages.light)), awake \(SleepStageMinutes.formatted(stages.awake))"
                    )

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Tide.s3, alignment: .leading),
                            count: typeSize.isAccessibilitySize ? 1 : 2
                        ),
                        spacing: Tide.s3
                    ) {
                        stageLegend(name: "Deep", minutes: stages.deep, color: TideSleepStage.deep)
                        stageLegend(name: "REM", minutes: stages.rem, color: TideSleepStage.rem)
                        stageLegend(name: "Light", minutes: stages.light, color: TideSleepStage.light)
                        stageLegend(name: "Awake", minutes: stages.awake, color: TideSleepStage.awake)
                    }

                    if data.sleepPerformance != nil {
                        TideDivider()
                        HStack {
                            Text("Performance")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                            Spacer(minLength: Tide.s2)
                            Text(data.formattedSleepPerformance)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .explains(.bodySleepStages)
            } else {
                TideEmptyPanel(
                    systemImage: "moon.zzz",
                    title: "No sleep stages yet",
                    message: "Last night's stages show up once WHOOP has processed it."
                )
                .tideCard()
            }
        }
        .accessibilityIdentifier("body-sleep")
    }

    private func stageSegments(_ stages: SleepStageMinutes) -> [(minutes: Int, color: Color)] {
        [
            (stages.deep, TideSleepStage.deep),
            (stages.rem, TideSleepStage.rem),
            (stages.light, TideSleepStage.light),
            (stages.awake, TideSleepStage.awake),
        ]
    }

    private func stageLegend(name: String, minutes: Int, color: Color) -> some View {
        HStack(spacing: Tide.s2) {
            Circle()
                .fill(color)
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)
            Text(name)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
            Text(SleepStageMinutes.formatted(minutes))
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Strain

    // Per MODULE_DASHBOARD.md Section 4.2 — Strain Breakdown

    private var strainSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Strain")

            if let level = StrainLevel(strain: data.strain) {
                RecoveryHero {
                    RecoveryStrainGauge(strain: data.strain, color: level.tideColor, diameter: Tide.dialSheet)
                } side: {
                    Text(level.name)
                        .font(Tide.title2)
                        .foregroundStyle(level.tideColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let advice = StrainLevel.advice(recovery: data.recoveryScore) {
                        Text("Recommended: \(advice)")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Based on recovery \(data.formattedRecovery)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Strain \(String(format: "%.1f", data.strain ?? 0)) out of 21, \(level.name)"
                )
                .explains(Explainer.recoveryStrain.showing("\(String(format: "%.1f", data.strain ?? 0)) of 21"))
            } else {
                TideEmptyPanel(
                    systemImage: "flame",
                    title: "No strain yet today",
                    message: "Strain shows up as WHOOP records your day."
                )
                .tideCard()
            }
        }
        .accessibilityIdentifier("body-strain")
    }

    // MARK: - Comparison

    // Per MODULE_DASHBOARD.md Section 4.2 — Historical Comparison. A line only
    // appears when both days it compares have readings.

    private var comparisonLines: [ComparisonLine] {
        var lines = [ComparisonLine]()

        let yesterday = BodyHistory.day(1, before: Date()).flatMap { BodyHistory.reading(on: $0, in: readings) }
        let yesterdayCells = BodyHistory.changes(today: todayReading, other: yesterday, kinds: [.recovery, .hrv])
        if !yesterdayCells.isEmpty {
            lines.append(ComparisonLine(title: "Yesterday", cells: yesterdayCells.map(changeCell)))
        }

        let lastWeek = BodyHistory.day(7, before: Date()).flatMap { BodyHistory.reading(on: $0, in: readings) }
        let weekCells = BodyHistory.changes(today: todayReading, other: lastWeek, kinds: [.recovery, .sleep])
        if !weekCells.isEmpty {
            lines.append(ComparisonLine(title: "Last week", cells: weekCells.map(changeCell)))
        }

        var averages = [ComparisonLine.Cell]()
        if let recovery = baseline.recovery {
            averages.append(.init(label: "Recovery", value: "\(Int(recovery.rounded()))%", color: Tide.text))
        }
        if let hrv = baseline.hrv {
            averages.append(.init(label: "HRV", value: "\(Int(hrv.rounded())) ms", color: Tide.text))
        }
        if !averages.isEmpty {
            lines.append(ComparisonLine(title: "7-day average", cells: averages))
        }
        return lines
    }

    private func changeCell(_ change: BodyHistory.Change) -> ComparisonLine.Cell {
        let label = switch change.kind {
        case .recovery: "Recovery"
        case .hrv: "HRV"
        case .sleep: "Sleep"
        }
        let color: Color = switch change.verdict {
        case .better: TideTone.mint
        case .worse: Tide.danger
        case .same: Tide.text
        }
        return .init(label: label, value: change.text, color: color)
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Compared with")

            let lines = comparisonLines
            if lines.isEmpty {
                TideEmptyPanel(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "Not enough days yet",
                    message: "Comparisons appear after a few days of readings."
                )
                .tideCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 {
                            TideDivider()
                        }
                        comparisonRow(line)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .explains(.bodyComparison)
            }
        }
        .accessibilityIdentifier("body-comparison")
    }

    private func comparisonRow(_ line: ComparisonLine) -> some View {
        let title = Text(line.title)
            .tideLabel(Tide.text3)
        let cells = ForEach(line.cells) { cell in
            HStack(spacing: Tide.s1) {
                Text(cell.label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Text(cell.value)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(cell.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                title
                    .lineLimit(1)
                    .frame(width: Tide.hit * 2.4, alignment: .leading)
                cells
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                title
                cells
            }
        }
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent days

/// The last three weeks of stored days: enough for a 7-day baseline, last
/// week's day and today.
private func bodyRecentDescriptor() -> FetchDescriptor<DailyRecovery> {
    var descriptor = FetchDescriptor<DailyRecovery>(sortBy: [SortDescriptor(\.date, order: .reverse)])
    descriptor.fetchLimit = 21
    return descriptor
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BodyQuadrantDetailView(
            data: BodyQuadrantData(
                recoveryScore: 72, hrv: 48, rhr: 62, sleepHours: 7.2,
                sleepPerformance: 78, strain: 12.4, spo2: 97.5,
                isConnected: true, lastSync: Date(),
                dataSource: .whoop
            )
        )
    }
    .modelContainer(
        for: [DailyRecovery.self, DailyPrescription.self, BodyComposition.self, UserSettings.self],
        inMemory: true
    )
}
