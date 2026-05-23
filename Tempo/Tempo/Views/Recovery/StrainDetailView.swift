//
// StrainDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Strain Detail View

// Per MODULE_RECOVERY.md Section 6 — Strain Detail Screen.

struct StrainDetailView: View {
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.modelContext)
    private var modelContext

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Strain Gauge
                strainGaugeSection

                // Heart Rate Summary
                heartRateSection

                // Calories Breakdown
                caloriesSection

                // Strain Trend Chart
                strainTrendSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Strain")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Strain Gauge Section

    // Per MODULE_RECOVERY.md Section 6 — Strain value displayed as ring/gauge (0-21 scale)

    private var strainGaugeSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            // Use ScoreRingView with maxScore=21
            ScoreRingView(
                score: viewModel.todayRecovery?.strain ?? 0,
                maxScore: 21,
                label: "STRAIN",
                size: 200,
                strokeWidth: 14
            )

            // Classification + Calories
            HStack(spacing: TempoSpacing.sm) {
                Text(strainClassification)
                    .font(.tempoBody)
                    .foregroundStyle(strainColor)

                Text("·")
                    .foregroundStyle(Color.tempoTextTertiary)

                Text("Calories: \(viewModel.formattedCalories)")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Heart Rate Section

    // Per MODULE_RECOVERY.md Section 6 — HR metrics

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Heart Rate")

            HStack(spacing: TempoSpacing.sm) {
                hrMetricCard(
                    label: "Average HR",
                    value: viewModel.todayRecovery?.avgHR.map { "\(Int($0))" } ?? "--",
                    unit: "bpm",
                    icon: "heart.fill"
                )
                hrMetricCard(
                    label: "Max HR",
                    value: viewModel.todayRecovery?.maxHR.map { "\(Int($0))" } ?? "--",
                    unit: "bpm",
                    icon: "heart.circle.fill"
                )
            }

            // RHR comparison
            if let avgHR = viewModel.todayRecovery?.avgHR,
               let rhr = viewModel.todayRecovery?.restingHR
            {
                Text("Resting: \(Int(rhr)) bpm · Elevated by \(Int(avgHR - rhr)) bpm during activity")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func hrMetricCard(label: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: icon)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoRecoveryRed)
                Text(label)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            HStack(spacing: 2) {
                Text(value)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(unit)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Calories Section

    // Per MODULE_RECOVERY.md Section 6 — Calories breakdown

    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Calories")

            VStack(spacing: TempoSpacing.sm) {
                if let totalCal = viewModel.todayRecovery?.caloriesBurned, totalCal > 0 {
                    caloriesRow(label: "Total", value: viewModel.formattedCalories, bold: true)

                    // Active vs basal split derived from strain data
                    if let active = viewModel.activeCalories,
                       let basal = viewModel.basalCalories,
                       let activePct = viewModel.activeCaloriePercent,
                       let basalPct = viewModel.basalCaloriePercent
                    {
                        caloriesRow(label: "Active", value: "\(Int(active).formatted()) kcal", detail: "\(activePct)%")
                        caloriesRow(label: "Basal", value: "\(Int(basal).formatted()) kcal", detail: "\(basalPct)%")
                    } else {
                        let activeCal = Int(totalCal * 0.47)
                        let basalCal = Int(totalCal * 0.53)
                        caloriesRow(label: "Active", value: "\(activeCal.formatted()) kcal", detail: "~47%")
                        caloriesRow(label: "Basal", value: "\(basalCal.formatted()) kcal", detail: "~53%")
                    }
                } else {
                    Text("No calorie data available")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    private func caloriesRow(label: String, value: String, detail: String? = nil, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .tempoHeadline : .tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            Text(value)
                .font(bold ? .tempoHeadline : .tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Strain Trend Section

    // Per MODULE_RECOVERY.md Section 6 — 7-day strain trend chart

    private var strainTrendSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            TempoSectionHeader("Strain Trends")

            if viewModel.strainChartData.count >= 3 {
                TempoLineChart(
                    data: [
                        TempoLineChartData(
                            id: "strain",
                            label: "Strain",
                            color: Color.tempoRecoveryYellow,
                            points: viewModel.strainChartData.map {
                                TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                            }
                        ),
                    ],
                    height: 200
                )
            } else {
                Text(
                    "Need \(3 - viewModel.strainChartData.count) more day\(3 - viewModel.strainChartData.count == 1 ? "" : "s") of data to show trends."
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, TempoSpacing.xxxl)
            }
        }
    }

    // MARK: - Helpers

    private var strainClassification: String {
        guard let strain = viewModel.todayRecovery?.strain else {
            return "--"
        }
        switch strain {
        case 0 ..< 5: return "Light"
        case 5 ..< 10: return "Low"
        case 10 ..< 14: return "Moderate"
        case 14 ..< 18: return "Moderate-High"
        case 18...: return "Overreaching"
        default: return "--"
        }
    }

    private var strainColor: Color {
        guard let strain = viewModel.todayRecovery?.strain else {
            return Color.tempoTextTertiary
        }
        switch strain {
        case 0 ..< 10: return Color.tempoRecoveryGreen
        case 10 ..< 14: return Color.tempoRecoveryYellow
        case 14 ..< 18: return Color(red: 1, green: 140 / 255, blue: 66 / 255) // #FF8C42 zone.5
        default: return Color.tempoRecoveryRed
        }
    }
}
