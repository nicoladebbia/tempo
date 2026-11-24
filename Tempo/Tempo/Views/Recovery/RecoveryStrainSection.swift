//
// RecoveryStrainSection.swift
// Tempo
//
// Today's strain, as a section of the Recovery Day view: the gauge, heart rate
// and calories. Per MODULE_RECOVERY.md Section 6. The strain trend lives in
// Week and Month. Calories are WHOOP's total only: the old active and basal
// split was an estimate from a formula, not a reading, so it is gone.
//

import SwiftUI

struct RecoveryStrainSection: View {
    var viewModel: RecoveryViewModel
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var strain: Double? {
        viewModel.todayRecovery?.strain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Strain")

            if strain != nil || hasHeartRate || hasCalories {
                gaugeCard
                heartRateCard
            } else {
                TideEmptyPanel(
                    systemImage: "flame",
                    title: "No strain yet today",
                    message: "Strain and calories show up as WHOOP records your day."
                )
                .tideCard()
            }
        }
        .accessibilityIdentifier("recovery-strain-section")
    }

    private var hasHeartRate: Bool {
        viewModel.todayRecovery?.avgHR != nil || viewModel.todayRecovery?.maxHR != nil
    }

    private var hasCalories: Bool {
        (viewModel.todayRecovery?.caloriesBurned ?? 0) > 0
    }

    // MARK: - Gauge

    // Per MODULE_RECOVERY.md Section 6 — Strain value on a 0-21 scale. The dial
    // shows a 0-100 score, so the 0-21 figure gets a gauge of its own.

    private var gaugeCard: some View {
        RecoveryHero {
            RecoveryStrainGauge(strain: strain, color: strainColor, diameter: Tide.dialSheet)
        } side: {
            Text(strainClassification)
                .font(Tide.title2)
                .foregroundStyle(strainColor)
                .fixedSize(horizontal: false, vertical: true)
            if hasCalories {
                Text("Calories: \(viewModel.formattedCalories)")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Strain \(strain.map { String(format: "%.1f", $0) } ?? "none") out of 21, \(strainClassification)"
        )
    }

    // MARK: - Heart rate

    // Per MODULE_RECOVERY.md Section 6 — HR metrics

    @ViewBuilder
    private var heartRateCard: some View {
        if hasHeartRate {
            VStack(alignment: .leading, spacing: Tide.s3) {
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
    }

    // MARK: - Helpers

    private var strainClassification: String {
        StrainLevel(strain: strain)?.name ?? "No strain yet"
    }

    private var strainColor: Color {
        StrainLevel(strain: strain)?.tideColor ?? Tide.text3
    }
}
