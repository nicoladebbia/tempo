//
// ComplicationViews.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI
import WidgetKit

// MARK: - CircularComplicationView

// Per APPLE_WATCH_APP.md Section 2.3 — Circular, Rectangular, Inline, Corner, ExtraLarge views.

// Per Section 2.3 — Score ring, 4pt stroke, centered score number

struct CircularComplicationView: View {
    let data: TempoComplicationData

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            ProgressView(value: Double(data.dailyScore) / 100.0) {
                Text("\(data.dailyScore)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .progressViewStyle(.circular)
        }
    }
}

// MARK: - RectangularComplicationView

// Per Section 2.3 — Recovery zone + score top, next task bottom

struct RectangularComplicationView: View {
    let data: TempoComplicationData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(zoneColor(data.recoveryZone))
                    .frame(width: 8, height: 8)
                Text("Recovery \(data.recoveryScore)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Score \(data.dailyScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            if data.leisureUnlocked {
                Text("All clear. Earned.")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else if data.nextTaskName.isEmpty {
                Text("Open Tempo on iPhone")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if data.nextTaskTimeRemaining.isEmpty {
                Text(data.nextTaskName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(data.nextTaskName) — \(data.nextTaskTimeRemaining)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        case "unknown": .gray
        default: .green
        }
    }
}

// MARK: - InlineComplicationView

// Per Section 2.3 — "Score: 78 | Study: 1h23m left"

struct InlineComplicationView: View {
    let data: TempoComplicationData

    var body: some View {
        ViewThatFits {
            Text("\(Image(systemName: "circle.fill")) Score: \(data.dailyScore) | \(data.nextTaskName): \(data.nextTaskTimeRemaining)")
            Text("\(Image(systemName: "circle.fill")) \(data.dailyScore) | \(data.nextTaskName)")
            Text("\(Image(systemName: "circle.fill")) Score: \(data.dailyScore)")
        }
    }
}
