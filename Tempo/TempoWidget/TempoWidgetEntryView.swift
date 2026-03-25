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

// MARK: - Lock Screen Widget View

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TempoWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.data.dailyScore), in: 0...100) {
                Text("T")
            } currentValueLabel: {
                Text("\(entry.data.dailyScore)")
                    .font(.system(size: 16, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Text("Tempo: \(entry.data.dailyScore)/100 · \(entry.data.streakCount)🔥")
        default:
            Text("\(entry.data.dailyScore)")
        }
    }
}
