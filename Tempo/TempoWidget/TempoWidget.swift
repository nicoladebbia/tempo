//
// TempoWidget.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI
import WidgetKit

// MARK: - WidgetData

// Per XCODE_PROJECT_STRUCTURE.md Section 10 — Main widget with TimelineProvider.
// Per Section 10.4 — Reads from shared UserDefaults (group.app.tempo).
// Per Section 10.6 — Refreshes every 15 minutes as fallback; main app triggers on score change.

struct WidgetData {
    let dailyScore: Int
    let recoveryZone: String
    let recoveryScore: Int
    let sleepHours: Double
    let hrv: Double
    let rhr: Int
    let caloriesConsumed: Int
    let caloriesTarget: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let mealsLogged: Int
    let mealsTarget: Int
    let studyMinutes: Int
    let studyTargetMinutes: Int
    let streakCount: Int
    let nextExam: String
    let workoutDone: Bool
    let stepCount: Int
    let activeCalories: Int
    let nnCompleted: Int
    let nnTotal: Int

    static let placeholder = WidgetData(
        dailyScore: 78,
        recoveryZone: "green",
        recoveryScore: 72,
        sleepHours: 7.2,
        hrv: 68.3,
        rhr: 52,
        caloriesConsumed: 1842,
        caloriesTarget: 2400,
        protein: 142,
        carbs: 205,
        fat: 52,
        mealsLogged: 2,
        mealsTarget: 4,
        studyMinutes: 135,
        studyTargetMinutes: 180,
        streakCount: 12,
        nextExam: "Calc II: 6 days",
        workoutDone: true,
        stepCount: 8432,
        activeCalories: 342,
        nnCompleted: 3,
        nnTotal: 5
    )

    static func fromDefaults() -> WidgetData {
        let d = UserDefaults(suiteName: "group.app.tempo")
        return WidgetData(
            dailyScore: d?.integer(forKey: "widget.dailyScore") ?? 0,
            recoveryZone: d?.string(forKey: "widget.recoveryZone") ?? "green",
            recoveryScore: d?.integer(forKey: "widget.recoveryScore") ?? 0,
            sleepHours: d?.double(forKey: "widget.sleepHours") ?? 0,
            hrv: d?.double(forKey: "widget.hrv") ?? 0,
            rhr: d?.integer(forKey: "widget.rhr") ?? 0,
            caloriesConsumed: d?.integer(forKey: "widget.caloriesConsumed") ?? 0,
            caloriesTarget: d?.integer(forKey: "widget.caloriesTarget") ?? 0,
            protein: d?.integer(forKey: "widget.protein") ?? 0,
            carbs: d?.integer(forKey: "widget.carbs") ?? 0,
            fat: d?.integer(forKey: "widget.fat") ?? 0,
            mealsLogged: d?.integer(forKey: "widget.mealsLogged") ?? 0,
            mealsTarget: d?.integer(forKey: "widget.mealsTarget") ?? 0,
            studyMinutes: d?.integer(forKey: "widget.studyMinutes") ?? 0,
            studyTargetMinutes: d?.integer(forKey: "widget.studyTargetMinutes") ?? 0,
            streakCount: d?.integer(forKey: "widget.streakCount") ?? 0,
            nextExam: d?.string(forKey: "widget.nextExam") ?? "",
            workoutDone: d?.bool(forKey: "widget.workoutDone") ?? false,
            stepCount: d?.integer(forKey: "widget.stepCount") ?? 0,
            activeCalories: d?.integer(forKey: "widget.activeCalories") ?? 0,
            nnCompleted: d?.integer(forKey: "widget.nnCompleted") ?? 0,
            nnTotal: d?.integer(forKey: "widget.nnTotal") ?? 0
        )
    }

    var zoneColor: Color {
        switch recoveryZone {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        default: .green
        }
    }

    var scoreColor: Color {
        if dailyScore >= 80 {
            return .green
        }
        if dailyScore >= 50 {
            return .orange
        }
        return .red
    }

    var studyTimeFormatted: String {
        let h = studyMinutes / 60
        let m = studyMinutes % 60
        return h > 0 ? "\(h)h\(m > 0 ? "\(m)m" : "")" : "\(m)m"
    }

    var studyTargetFormatted: String {
        let h = studyTargetMinutes / 60
        return "\(h)h"
    }
}

// MARK: - TempoWidgetEntry

struct TempoWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - TempoTimelineProvider

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

// MARK: - TempoWidget

struct TempoWidget: Widget {
    let kind = "TempoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoTimelineProvider()) { entry in
            TempoWidgetEntryView(entry: entry)
                .background(Color.black)
        }
        .configurationDisplayName("Tempo Score")
        .description("Your daily life operating score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - TempoLockScreenWidget

struct TempoLockScreenWidget: Widget {
    let kind = "TempoLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .background(Color.black)
        }
        .configurationDisplayName("Tempo Score")
        .description("Daily score on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
