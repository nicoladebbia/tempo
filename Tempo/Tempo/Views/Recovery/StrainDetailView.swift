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

    /// The top of the strain scale.
    private let strainMax = 21.0

    var body: some View {
        TideScrollPage(energy: 1) {
            // Strain gauge
            strainGaugeSection

            // Heart Rate Summary
            heartRateSection

            // Calories Breakdown
            caloriesSection

            // Strain Trend Chart
            strainTrendSection
        }
        .navigationTitle("Strain")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.forceRefresh(modelContext: modelContext)
        }
    }

    // MARK: - Strain Gauge Section

    // Per MODULE_RECOVERY.md Section 6 — Strain value on a 0-21 scale. The dial
    // shows a 0-100 score, so the 0-21 figure gets a large numeral and a level bar.

    private var strainGaugeSection: some View {
        let strain = viewModel.todayRecovery?.strain
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Strain").tideLabel()
                Spacer(minLength: Tide.s2)
                TideStatusPill(text: strainClassification, tint: strainColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(
                    strain.map { String(format: "%.1f", $0) } ?? "--",
                    size: Tide.numeralHero, relativeTo: .largeTitle, color: strainColor
                )
                Text("of 21")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
            }

            TideLevelBar(
                progress: min(max((strain ?? 0) / strainMax, 0), 1),
                color: strainColor,
                height: Tide.bar
            )

            Text("Calories: \(viewModel.formattedCalories)")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Strain \(strain.map { String(format: "%.1f", $0) } ?? "none") out of 21, \(strainClassification)"
        )
    }

    // MARK: - Heart Rate Section

    // Per MODULE_RECOVERY.md Section 6 — HR metrics

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Heart rate")

            HStack(spacing: Tide.s3) {
                TideMetricTile(
                    label: "Average HR",
                    value: viewModel.todayRecovery?.avgHR.map { "\(Int($0))" } ?? "--",
                    unit: "bpm",
                    tint: Tide.text,
                    systemImage: "heart.fill"
                )
                TideMetricTile(
                    label: "Max HR",
                    value: viewModel.todayRecovery?.maxHR.map { "\(Int($0))" } ?? "--",
                    unit: "bpm",
                    tint: Tide.text,
                    systemImage: "heart.circle.fill"
                )
            }

            // RHR comparison
            if let avgHR = viewModel.todayRecovery?.avgHR,
               let rhr = viewModel.todayRecovery?.restingHR
            {
                Text("Resting: \(Int(rhr)) bpm · Elevated by \(Int(avgHR - rhr)) bpm during activity")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
    }

    // MARK: - Calories Section

    // Per MODULE_RECOVERY.md Section 6 — Calories breakdown

    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Calories")

            VStack(spacing: 0) {
                if let totalCal = viewModel.todayRecovery?.caloriesBurned, totalCal > 0 {
                    caloriesRow(label: "Total", value: viewModel.formattedCalories, bold: true)

                    // Active vs basal split derived from strain data
                    if let active = viewModel.activeCalories,
                       let basal = viewModel.basalCalories,
                       let activePct = viewModel.activeCaloriePercent,
                       let basalPct = viewModel.basalCaloriePercent
                    {
                        TideDivider()
                        caloriesRow(label: "Active", value: "\(Int(active).formatted()) kcal", detail: "\(activePct)%")
                        TideDivider()
                        caloriesRow(label: "Basal", value: "\(Int(basal).formatted()) kcal", detail: "\(basalPct)%")
                    } else {
                        let activeCal = Int(totalCal * 0.47)
                        let basalCal = Int(totalCal * 0.53)
                        TideDivider()
                        caloriesRow(label: "Active", value: "\(activeCal.formatted()) kcal", detail: "~47%")
                        TideDivider()
                        caloriesRow(label: "Basal", value: "\(basalCal.formatted()) kcal", detail: "~53%")
                    }
                } else {
                    Text("No calorie data available")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func caloriesRow(label: String, value: String, detail: String? = nil, bold: Bool = false) -> some View {
        HStack(spacing: Tide.s3) {
            Text(label)
                .font(bold ? Tide.headline : Tide.body)
                .foregroundStyle(bold ? Tide.text : Tide.text2)
            Spacer(minLength: Tide.s2)
            if let detail {
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            Text(value)
                .font(Tide.numeral(bold ? Tide.numeralS : Tide.numeralS - Tide.s1, .semibold))
                .foregroundStyle(Tide.text)
        }
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Strain Trend Section

    // Per MODULE_RECOVERY.md Section 6 — 7-day strain trend chart

    private var strainTrendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Strain trends")

            Group {
                if viewModel.strainChartData.count >= 3 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: "strain",
                                label: "Strain",
                                color: TideTone.amber,
                                points: viewModel.strainChartData.map {
                                    TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                                }
                            ),
                        ],
                        height: Tide.chartHeight
                    )
                } else {
                    Text(
                        "Need \(3 - viewModel.strainChartData.count) more day\(3 - viewModel.strainChartData.count == 1 ? "" : "s") of data to show trends."
                    )
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tide.s8)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    // MARK: - Helpers

    private var strainClassification: String {
        guard let strain = viewModel.todayRecovery?.strain else {
            return "No data"
        }
        switch strain {
        case 0 ..< 5: return "Light"
        case 5 ..< 10: return "Low"
        case 10 ..< 14: return "Moderate"
        case 14 ..< 18: return "Moderate-High"
        case 18...: return "Overreaching"
        default: return "No data"
        }
    }

    private var strainColor: Color {
        guard let strain = viewModel.todayRecovery?.strain else {
            return Tide.text3
        }
        switch strain {
        case 0 ..< 10: return TideTone.mint
        case 10 ..< 14: return TideTone.amber
        case 14 ..< 18: return Tide.streak
        default: return Tide.danger
        }
    }
}
