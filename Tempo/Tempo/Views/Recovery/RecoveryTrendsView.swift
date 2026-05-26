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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Time range picker
                timeRangePicker

                // Average values
                averagesRow

                // Multi-line chart
                chartSection

                // Legend / toggles
                legendRow

                // Weekly Summary Link (Task 5)
                weeklySummaryLink

                // Pattern Insights
                insightsSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Time Range Picker

    // Per MODULE_RECOVERY.md Section 7 — Time range pills

    private var timeRangePicker: some View {
        HStack(spacing: TempoSpacing.sm) {
            ForEach(RecoveryViewModel.TrendRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.selectedTrendRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.tempoCaption1)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            viewModel.selectedTrendRange == range
                                ? Color.white
                                : Color.tempoTextSecondary
                        )
                        .padding(.horizontal, TempoSpacing.md)
                        .padding(.vertical, TempoSpacing.sm)
                        .background(
                            viewModel.selectedTrendRange == range
                                ? zoneColor
                                : Color.tempoSurfaceCard
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.top, TempoSpacing.md)
        .sensoryFeedback(.selection, trigger: viewModel.selectedTrendRange)
    }

    // MARK: - Averages Row

    private var averagesRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            averageCard(
                label: "Avg Recovery",
                value: viewModel.avgRecovery7d.map { "\(Int($0))%" } ?? "--"
            )
            averageCard(
                label: "Avg HRV",
                value: viewModel.avgHRV7d.map { "\(Int($0)) ms" } ?? "--"
            )
            averageCard(
                label: "Avg RHR",
                value: viewModel.avgRHR7d.map { "\(Int($0)) bpm" } ?? "--"
            )
        }
    }

    private func averageCard(label: String, value: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
            Text(value)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Multi-Line Chart

    // Per MODULE_RECOVERY.md Section 7 — Recovery, HRV, RHR overlaid

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            if chartData.isEmpty {
                Text("Need more days of data to show trends.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.xxxl)
            } else {
                TempoLineChart(
                    data: chartData,
                    height: 220
                )
            }
        }
    }

    private var chartData: [TempoLineChartData<String>] {
        var series: [TempoLineChartData<String>] = []

        if showRecovery, viewModel.recoveryChartData.count >= 3 {
            series.append(
                TempoLineChartData(
                    id: "recovery",
                    label: "Recovery",
                    color: Color.tempoRecoveryGreen,
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
                    color: Color.tempoSleepREM, // #A29BFE
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
                    color: Color.tempoRecoveryRed,
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
        HStack(spacing: TempoSpacing.lg) {
            legendToggle(
                label: "Recovery",
                color: Color.tempoRecoveryGreen,
                isOn: $showRecovery
            )
            legendToggle(
                label: "HRV",
                color: Color.tempoSleepREM,
                isOn: $showHRV
            )
            legendToggle(
                label: "RHR",
                color: Color.tempoRecoveryRed,
                isOn: $showRHR
            )
        }
    }

    private func legendToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: TempoSpacing.xs) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Color.tempoTextTertiary)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(
                        isOn.wrappedValue
                            ? Color.tempoTextPrimary
                            : Color.tempoTextTertiary
                    )
            }
        }
    }

    // MARK: - Weekly Summary Link (Task 5)

    private var weeklySummaryLink: some View {
        NavigationLink {
            WeeklyRecoverySummaryView(viewModel: viewModel)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.tempoBody)
                            .foregroundStyle(zoneColor)

                        Text("Weekly Recovery Report")
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }

                    if let stats = viewModel.weeklyStats {
                        Text(
                            "Avg \(Int(stats.avgRecovery))% recovery  |  \(String(format: "%.1f", stats.avgSleep))h sleep  |  \(String(format: "%.0f", stats.totalStrain)) total strain"
                        )
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    } else {
                        Text("View your 7-day summary")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(zoneColor)
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pattern Insights Section

    // Per MODULE_RECOVERY.md Section 7 — Pattern insight cards

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            if !viewModel.insights.isEmpty {
                TempoSectionHeader("Pattern Insights")

                ForEach(viewModel.insights, id: \.id) { insight in
                    insightCard(insight)
                }
            }
        }
    }

    private func insightCard(_ insight: RecoveryInsight) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoRecoveryYellow)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(insight.title)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(insight.body)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        switch viewModel.recoveryZone {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
    }
}
