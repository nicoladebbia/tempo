//
// WidgetSyncService.swift
// Tempo
//
// Writes the Home/Lock Screen widget's data into the shared app-group
// UserDefaults and asks WidgetKit to reload. The widget extension
// (`TempoWidget/TempoWidget.swift` → `WidgetData.fromDefaults()`) only READS
// these keys; before this service nothing wrote them, so every widget showed
// zeros. Per XCODE_PROJECT_STRUCTURE.md §10.4 / §10.6.
//

import Foundation
import WidgetKit

// MARK: - WidgetSnapshot

/// Everything the widget renders. Field names mirror `WidgetData` in the
/// widget extension; keys are `widget.<field>`.
struct WidgetSnapshot: Equatable {
    var dailyScore: Int = 0
    var recoveryZone: String = RecoveryZone.green.rawValue
    var recoveryScore: Int = 0
    var sleepHours: Double = 0
    var hrv: Double = 0
    var rhr: Int = 0
    var caloriesConsumed: Int = 0
    var caloriesTarget: Int = 0
    var protein: Int = 0
    var carbs: Int = 0
    var fat: Int = 0
    var mealsLogged: Int = 0
    var mealsTarget: Int = 0
    var studyMinutes: Int = 0
    var studyTargetMinutes: Int = 0
    var streakCount: Int = 0
    var nextExam: String = ""
    var workoutDone: Bool = false
    var stepCount: Int = 0
    var activeCalories: Int = 0
    var nnCompleted: Int = 0
    var nnTotal: Int = 0
}

// MARK: - WidgetSyncService

@MainActor
enum WidgetSyncService {
    static let appGroupID = "group.app.tempo.Tempo"

    /// Last snapshot written this process — skips the write + timeline reload
    /// when a refresh produced identical data (Dashboard refreshes often).
    private static var lastPublished: WidgetSnapshot?

    /// Write `snapshot` and reload widget timelines when it changed.
    /// `defaults` / `reload` are injectable for tests.
    static func publish(
        _ snapshot: WidgetSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        guard let defaults else {
            #if DEBUG
                print("[Widget] app group \(appGroupID) unavailable — widget not updated")
            #endif
            return
        }
        guard snapshot != lastPublished else {
            return
        }
        write(snapshot, to: defaults)
        lastPublished = snapshot
        reload()
    }

    /// Test hook: forget the dedupe cache.
    static func resetDedupe() {
        lastPublished = nil
    }

    static func write(_ s: WidgetSnapshot, to d: UserDefaults) {
        d.set(s.dailyScore, forKey: "widget.dailyScore")
        d.set(s.recoveryZone, forKey: "widget.recoveryZone")
        d.set(s.recoveryScore, forKey: "widget.recoveryScore")
        d.set(s.sleepHours, forKey: "widget.sleepHours")
        d.set(s.hrv, forKey: "widget.hrv")
        d.set(s.rhr, forKey: "widget.rhr")
        d.set(s.caloriesConsumed, forKey: "widget.caloriesConsumed")
        d.set(s.caloriesTarget, forKey: "widget.caloriesTarget")
        d.set(s.protein, forKey: "widget.protein")
        d.set(s.carbs, forKey: "widget.carbs")
        d.set(s.fat, forKey: "widget.fat")
        d.set(s.mealsLogged, forKey: "widget.mealsLogged")
        d.set(s.mealsTarget, forKey: "widget.mealsTarget")
        d.set(s.studyMinutes, forKey: "widget.studyMinutes")
        d.set(s.studyTargetMinutes, forKey: "widget.studyTargetMinutes")
        d.set(s.streakCount, forKey: "widget.streakCount")
        d.set(s.nextExam, forKey: "widget.nextExam")
        d.set(s.workoutDone, forKey: "widget.workoutDone")
        d.set(s.stepCount, forKey: "widget.stepCount")
        d.set(s.activeCalories, forKey: "widget.activeCalories")
        d.set(s.nnCompleted, forKey: "widget.nnCompleted")
        d.set(s.nnTotal, forKey: "widget.nnTotal")
    }
}
