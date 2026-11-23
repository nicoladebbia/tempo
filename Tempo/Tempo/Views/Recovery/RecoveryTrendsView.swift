//
// RecoveryTrendsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Recovery Trends View

// Per MODULE_RECOVERY.md Section 7 — Trends screen.
// Per BUILD_PLAN.md Step 8.5 — Time range picker, multi-line chart, pattern insights.

struct RecoveryTrendsView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var showRecovery = true
    @State
    private var showHRV = true
    @State
    private var showRHR = false

    var body: some View {
        TideScrollPage(energy: 1) {
            // Time range picker
            timeRangePicker

            // Average values
            averagesRow

            // Multi-line chart and its toggles
            chartCard

            // Weekly Summary Link
            weeklySummaryLink

            // Pattern Insights
            insightsSection
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Time Range Picker

    // Per MODULE_RECOVERY.md Section 7 — Time range pills

    private var timeRangePicker: some View {
        TidePillPicker(
            options: RecoveryViewModel.TrendRange.allCases,
            selection: $viewModel.selectedTrendRange,
            title: \.rawValue,
            label: "Time range"
        )
    }

    // MARK: - Averages Row

    private var averagesRow: some View {
        HStack(spacing: Tide.s3) {
            averageTile(
                label: "Recovery",
                value: viewModel.avgRecovery7d.map { "\(Int($0))" } ?? "--",
                unit: viewModel.avgRecovery7d == nil ? nil : "%"
            )
            averageTile(
                label: "HRV",
                value: viewModel.avgHRV7d.map { "\(Int($0))" } ?? "--",
                unit: viewModel.avgHRV7d == nil ? nil : "ms"
            )
            averageTile(
                label: "RHR",
                value: viewModel.avgRHR7d.map { "\(Int($0))" } ?? "--",
                unit: viewModel.avgRHR7d == nil ? nil : "bpm"
            )
        }
    }

    private func averageTile(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text("Avg \(label)")
                .tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            TideNumber(value, unit: unit, size: Tide.numeralS + Tide.s1, relativeTo: .title3)
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Multi-Line Chart

    // Per MODULE_RECOVERY.md Section 7 — Recovery, HRV, RHR overlaid

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            if chartData.isEmpty {
                Text("Need more days of data to show trends.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tide.s8)
            } else {
                TideLineChart(
                    data: chartData,
                    height: Tide.chartHeight + Tide.s5
                )
            }

            // Legend / toggles
            legendRow
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private var chartData: [TempoLineChartData<String>] {
        var series: [TempoLineChartData<String>] = []

        if showRecovery, viewModel.recoveryChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "recovery",
                    label: "Recovery",
                    color: TideTone.mint,
                    points: viewModel.recoveryChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }

        if showHRV, viewModel.hrvChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "hrv",
                    label: "HRV",
                    color: TideSleepStage.rem,
                    points: viewModel.hrvChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }

        if showRHR, viewModel.rhrChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "rhr",
                    label: "RHR",
                    color: Tide.danger,
                    points: viewModel.rhrChartData.map {
                        TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                    }
                )
            )
        }

        return series
    }

    // MARK: - Legend / Toggles

    // Per MODULE_RECOVERY.md Section 7 — Toggle legend

    private var legendRow: some View {
        HStack(spacing: Tide.s2) {
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
    }

    // MARK: - Weekly Summary Link

    private var weeklySummaryLink: some View {
        NavigationLink {
            WeeklyRecoverySummaryView(viewModel: viewModel)
        } label: {
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: "calendar.badge.clock", tint: zoneColor)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Weekly recovery report")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)

                    if let stats = viewModel.weeklyStats {
                        Text(
                            "Avg \(Int(stats.avgRecovery))% recovery · \(String(format: "%.1f", stats.avgSleep))h sleep · \(String(format: "%.0f", stats.totalStrain)) total strain"
                        )
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("View your 7-day summary")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                    }
                }

                Spacer(minLength: Tide.s2)

                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
    }

    // MARK: - Pattern Insights Section

    // Per MODULE_RECOVERY.md Section 7 — Pattern insight cards

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

    // MARK: - Helpers

    private var zoneColor: Color {
        viewModel.recoveryZone.tideColor
    }
}
