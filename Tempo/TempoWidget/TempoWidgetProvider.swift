//
// TempoWidgetProvider.swift
// TempoWidget
//
// One timeline for all four widgets: it reads the `WidgetSnapshot` the app
// last wrote into the app group. Nothing is invented: before the app has
// written anything the entry carries no snapshot, and each widget draws its
// designed empty state. A snapshot from an earlier day is carried to today
// (targets kept, progress cleared), and a second entry at midnight does the
// same if nobody opens the app overnight.
//

import SwiftUI
import WidgetKit

// MARK: - TempoWidgetEntry

struct TempoWidgetEntry: TimelineEntry {
    let date: Date
    /// nil until the app has written one.
    let snapshot: WidgetSnapshot?

    var mood: TideMood {
        TideMood(score: snapshot?.score)
    }
}

// MARK: - TempoWidgetProvider

struct TempoWidgetProvider: TimelineProvider {
    /// How often the widget re-reads the app group when nothing reloads it.
    static let refresh: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> TempoWidgetEntry {
        TempoWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TempoWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoWidgetEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(entry(at: midnight))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refresh))))
    }

    private func entry(at date: Date) -> TempoWidgetEntry {
        TempoWidgetEntry(date: date, snapshot: WidgetSnapshot.read()?.carried(to: date))
    }
}

// MARK: - Formatting

extension WidgetSnapshot {
    /// "1,840" style, or "--" for a value the app does not have yet.
    static func text(_ value: Int?) -> String {
        value.map { $0.formatted() } ?? "--"
    }
}
