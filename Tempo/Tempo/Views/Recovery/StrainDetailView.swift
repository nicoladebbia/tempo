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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
        return RecoveryHero {
            RecoveryStrainGauge(strain: strain, color: strainColor, diameter: Tide.dialHero)
        } side: {
            Text("Strain").tideLabel()
            Text(strainClassification)
                .font(Tide.title2)
                .foregroundStyle(strainColor)
                .fixedSize(horizontal: false, vertical: true)
            Text("Calories: \(viewModel.formattedCalories)")
                .font(Tide.body)
                .foregroundStyle(Tide.text)
        }
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

            // Side by side, or one over the other when the text is large.
            let tiles = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            tiles {
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
                    .fixedSize(horizontal: false, vertical: true)
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
                        TideLevelBar(progress: Double(activePct) / 100, color: strainColor, height: Tide.bar)
                            .padding(.bottom, Tide.s2)
                            .accessibilityHidden(true)
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
                    HStack(spacing: Tide.s3) {
                        Image(systemName: "flame")
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                        Text("No calorie data available")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func caloriesRow(label: String, value: String, detail: String? = nil, bold: Bool = false) -> some View {
        // At large text the name, share and amount stack instead of fighting for one line.
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        return layout {
            Text(label)
                .font(bold ? Tide.headline : Tide.body)
                .foregroundStyle(bold ? Tide.text : Tide.text2)
            if !stacks {
                Spacer(minLength: Tide.s2)
            }
            if let detail {
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            // Scales with the text around it, so the amount never reads smaller than its label.
            TideNumber(
                value,
                size: bold ? Tide.numeralS : Tide.numeralS - Tide.s1,
                relativeTo: .body,
                weight: .semibold
            )
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .padding(.vertical, stacks ? Tide.s2 : 0)
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
                    RecoveryChartPlaceholder(
                        message: "Need \(3 - viewModel.strainChartData.count) more day\(3 - viewModel.strainChartData.count == 1 ? "" : "s") of data to show trends."
                    )
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
