import SwiftUI
import WidgetKit

// MARK: - Widget Entry View
// Per XCODE_PROJECT_STRUCTURE.md Section 10.5 — Entry view switching on widget family.

struct TempoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TempoWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.data)
        case .systemMedium:
            MediumWidgetView(data: entry.data)
        case .systemLarge:
            LargeWidgetView(data: entry.data)
        default:
            SmallWidgetView(data: entry.data)
        }
    }
}

// MARK: - Lock Screen Widget Views
// Per WIREFRAMES.md Screen 52

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TempoWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Per Screen 52 — 50pt diameter, 3pt stroke, zone color, score centered
            Gauge(value: Double(entry.data.dailyScore), in: 0...100) {
                Text("T")
            } currentValueLabel: {
                Text("\(entry.data.dailyScore)")
                    .font(.system(size: 18, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            // Per Screen 52 — "Tempo: 78 · 72% rec · 7.2h sleep"
            VStack(alignment: .leading, spacing: 2) {
                Text("Tempo: \(entry.data.dailyScore)")
                    .font(.system(size: 12, weight: .medium))
                Text("\(entry.data.recoveryScore)% rec · \(String(format: "%.1fh", entry.data.sleepHours)) sleep")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            // Per Screen 52 — "Tempo 78 | Rec 72%"
            if entry.data.dailyScore > 0 {
                Text("Tempo \(entry.data.dailyScore) | Rec \(entry.data.recoveryScore)%")
            } else {
                Text("Tempo --")
            }

        default:
            Text("\(entry.data.dailyScore)")
        }
    }
}
