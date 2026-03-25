import SwiftUI
import WidgetKit

// MARK: - Complication Views
// Per APPLE_WATCH_APP.md Section 2.3 — Circular, Rectangular, Inline, Corner, ExtraLarge views.

// MARK: - Circular Complication
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

// MARK: - Rectangular Complication
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
            } else {
                Text("\(data.nextTaskName) — \(data.nextTaskTimeRemaining)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        default: return .green
        }
    }
}

// MARK: - Inline Complication
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
