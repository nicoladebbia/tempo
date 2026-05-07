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

    @Environment(\.colorScheme)
    private var colorScheme

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
            case .down: .tempoError
            case .flat: .tempoTextTertiary
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
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Text(value)
                    .font(.tempoDataLarge)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Spacer()

            if let trendValue, trendDirection != .none {
                HStack(spacing: TempoSpacing.xxs) {
                    Image(systemName: trendDirection.icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(trendValue)
                        .font(.tempoCaption1)
                }
                .foregroundStyle(trendDirection.color)
            }
        }
        .padding(TempoSpacing.cardPaddingCompact)
        .frame(height: 80)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .tempoShadow(.card)
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: TempoElevation.cardDarkBorderWidth)
                .opacity(colorScheme == .dark ? 1 : 0)
        )
    }
}
