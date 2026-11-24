//
// StatCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Stat Card

// Per DESIGN_SYSTEM.md Section 8.2 — Stat Card:
// 80pt height, 12pt radius, 12pt padding, lighter shadow (0.04 opacity).

struct StatCardView: View {
    let label: String
    let value: String
    let trendValue: String?
    let trendDirection: TrendDirection

    @ScaledMetric(relativeTo: .footnote)
    private var trendSize: CGFloat = 13

    enum TrendDirection {
        case up
        case down
        case flat
        case none

        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .flat: "arrow.right"
            case .none: ""
            }
        }

        var color: Color {
            switch self {
            case .up: .tempoSuccess
            case .down: Tide.danger
            case .flat: Tide.text3
            case .none: .clear
            }
        }
    }

    init(label: String, value: String, trendValue: String? = nil, trendDirection: TrendDirection = .none) {
        self.label = label
        self.value = value
        self.trendValue = trendValue
        self.trendDirection = trendDirection
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                TideNumber(value, size: Tide.numeralS + Tide.s2, relativeTo: .title2)
            }

            Spacer()

            if let trendValue, trendDirection != .none {
                HStack(spacing: Tide.hair) {
                    Image(systemName: trendDirection.icon)
                        .font(Tide.caption)
                    Text(trendValue)
                        .font(Tide.numeral(trendSize, .semibold))
                }
                .foregroundStyle(trendDirection.color)
            }
        }
        .padding(Tide.s3)
        .frame(minHeight: 80)
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.tileRadius))
        .accessibilityElement(children: .combine)
    }
}
