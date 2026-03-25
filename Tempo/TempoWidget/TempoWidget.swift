import SwiftUI
import WidgetKit

// MARK: - Tempo Widget
// Per XCODE_PROJECT_STRUCTURE.md Section 10 — Main widget with TimelineProvider.
// Per Section 10.4 — Reads from shared UserDefaults (group.app.tempo).
// Per Section 10.6 — Refreshes every 15 minutes as fallback; main app triggers on score change.

// MARK: - Shared Data

struct WidgetData {
    let dailyScore: Int
    let recoveryZone: String
    let recoveryScore: Int
    let nextTaskName: String
    let nnProgress: String
    let streakCount: Int
    let caloriesBurned: Int
    let studyMinutes: Int
    let stepCount: Int

    static let placeholder = WidgetData(
        dailyScore: 72,
        recoveryZone: "green",
        recoveryScore: 85,
        nextTaskName: "Chest Day",
        nnProgress: "3/5",
        streakCount: 14,
        caloriesBurned: 420,
        studyMinutes: 90,
        stepCount: 8200
    )

    static func fromDefaults() -> WidgetData {
        let defaults = UserDefaults(suiteName: "group.app.tempo")
        return WidgetData(
            dailyScore: defaults?.integer(forKey: "widget.dailyScore") ?? 0,
            recoveryZone: defaults?.string(forKey: "widget.recoveryZone") ?? "green",
            recoveryScore: defaults?.integer(forKey: "widget.recoveryScore") ?? 0,
            nextTaskName: defaults?.string(forKey: "widget.nextTaskName") ?? "No task",
            nnProgress: defaults?.string(forKey: "widget.nnProgress") ?? "0/0",
            streakCount: defaults?.integer(forKey: "widget.streakCount") ?? 0,
            caloriesBurned: defaults?.integer(forKey: "widget.caloriesBurned") ?? 0,
            studyMinutes: defaults?.integer(forKey: "widget.studyMinutes") ?? 0,
            stepCount: defaults?.integer(forKey: "widget.stepCount") ?? 0
        )
    }
}

// MARK: - Timeline Entry

struct TempoWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Timeline Provider

struct TempoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TempoWidgetEntry {
        TempoWidgetEntry(date: .now, data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TempoWidgetEntry) -> Void) {
        let entry = TempoWidgetEntry(
            date: .now,
            data: context.isPreview ? .placeholder : .fromDefaults()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoWidgetEntry>) -> Void) {
        let entry = TempoWidgetEntry(date: .now, data: .fromDefaults())
        // Per XCODE_PROJECT_STRUCTURE.md Section 10.6 — refresh every 15 minutes as fallback
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Definition

struct TempoWidget: Widget {
    let kind = "TempoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoTimelineProvider()) { entry in
            TempoWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Tempo Score")
        .description("Your daily life operating score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Lock Screen Widget

struct TempoLockScreenWidget: Widget {
    let kind = "TempoLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Tempo Score")
        .description("Daily score on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}
