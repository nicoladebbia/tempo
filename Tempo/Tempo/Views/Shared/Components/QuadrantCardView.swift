//
// QuadrantCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Dashboard Quadrant Card

// A square glass tile for one module: its symbol and name, one big figure and
// a line under it. Presses dip like every Tide card.

struct QuadrantCardView: View {
    let moduleIcon: String
    let moduleLabel: String
    let moduleColor: Color
    let metricValue: String
    let secondaryMetric: String
    let action: () -> Void

    @State
    private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(spacing: Tide.s2) {
                    Image(systemName: moduleIcon)
                        .font(Tide.headline)
                        .foregroundStyle(moduleColor)
                    Text(moduleLabel)
                        .tideLabel()
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }

                Spacer(minLength: Tide.s2)

                TideNumber(metricValue, size: Tide.numeralS + Tide.s2, relativeTo: .title2)

                Text(secondaryMetric)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}
