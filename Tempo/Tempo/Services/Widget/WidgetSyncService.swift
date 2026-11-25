//
// WidgetSyncService.swift
// Tempo
//
// Writes the widgets' data into the shared app group and asks WidgetKit to
// reload. The widget extension (`TempoWidget/`) only READS `WidgetSnapshot`.
//
// Two writers, one value:
//  - Today's live snapshot (`publish(today:)`), every time Today redraws with
//    different numbers. The same snapshot Today shows, so a widget cannot
//    disagree with it.
//  - Water logged while the app has no screen (Siri, Shortcuts, the widget's
//    own +250 button): `recordWater`. It patches only the water total.
//

import Foundation
import OSLog
import WidgetKit

@MainActor
enum WidgetSyncService {
    static let appGroupID = WidgetSnapshot.appGroupID

    /// Last snapshot written this process: skips the write and the timeline
    /// reload when a refresh produced identical data (Today redraws often).
    private static var lastPublished: WidgetSnapshot?

    /// Writes Today's numbers for the widgets.
    static func publish(
        today: TodaySnapshot,
        now: Date = Date(),
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        publish(WidgetSnapshot(today: today, now: now), defaults: defaults, reload: reload)
    }

    /// Write `snapshot` and reload widget timelines when it changed.
    /// `defaults` / `reload` are injectable for tests.
    static func publish(
        _ snapshot: WidgetSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        guard let defaults else {
            Logger.sync.error("Widget app group \(appGroupID, privacy: .public) unavailable: widget not updated")
            return
        }
        if let lastPublished, lastPublished.sameContent(as: snapshot) {
            return
        }
        guard snapshot.write(to: defaults) else {
            Logger.sync.error("Widget snapshot could not be written")
            return
        }
        lastPublished = snapshot
        reload()
    }

    /// Water was logged with no screen up to refresh the widgets: put the day's
    /// new total in them now.
    /// Patches the water of the snapshot already there, or starts today's
    /// with only water filled in when the app has not written one yet.
    static func recordWater(
        totalMl: Int,
        targetMl: Int?,
        now: Date = Date(),
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        let base = WidgetSnapshot.read(from: defaults) ?? .empty(for: Calendar.current.startOfDay(for: now))
        publish(base.updatingWater(ml: totalMl, targetMl: targetMl, now: now), defaults: defaults, reload: reload)
    }

    /// Test hook: forget the dedupe cache.
    static func resetDedupe() {
        lastPublished = nil
    }
}
