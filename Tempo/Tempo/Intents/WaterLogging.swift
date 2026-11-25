//
// WaterLogging.swift
// Tempo
//
// The app's half of "Log water" (the widget extension has its own, see
// `TempoWidget/WidgetWaterLogging.swift`). Saves through `WaterStore`, the one
// store every screen uses, so Apple Health gets the sample, Today and Fuel
// re-read the total (`.tempoWaterLogged`), and the widgets get the new figure.
//

import Foundation
import SwiftData

@MainActor
enum WaterLogging {
    /// Logs `ml` in the running app's store.
    static func log(ml: Int) async throws -> WaterLogOutcome {
        guard let env = await TempoIntentEnvironment.resolve() else {
            throw WaterIntentError.appNotReady
        }
        let store = WaterStore(context: env.context, healthKit: env.healthKit)
        return try log(ml: ml, store: store, context: env.context, defaults: env.widgetDefaults)
    }

    /// The same, against any store: what the tests call.
    static func log(
        ml: Int,
        store: WaterStore,
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
    ) throws -> WaterLogOutcome {
        guard store.add(ml: ml, at: now) != nil else {
            throw WaterIntentError.couldNotSave
        }
        let (total, target) = totals(in: context, now: now)
        // The widgets show the new total now, even with no screen to refresh them.
        WidgetSyncService.recordWater(totalMl: total, targetMl: target, now: now, defaults: defaults)
        return WaterLogOutcome(addedMl: ml, totalMl: total, targetMl: target)
    }

    private static func totals(in context: ModelContext, now: Date) -> (total: Int, target: Int?) {
        (WaterStore.total(on: now, in: context), DailyNutritionTargets.todayWaterTargetMl(in: context, now: now))
    }

    /// Adds the glasses the widget's button queued while the app was not
    /// running (see `PendingWaterQueue`), so they reach the store, Apple Health
    /// and every screen. Returns how many were added.
    @discardableResult
    static func drainPending(
        store: WaterStore,
        context: ModelContext,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
        now: Date = Date()
    ) -> Int {
        var added = 0
        for entry in PendingWaterQueue.pending(defaults: defaults) {
            guard store.add(ml: entry.ml, at: entry.at) != nil else {
                break
            }
            PendingWaterQueue.remove(entry, defaults: defaults)
            added += 1
        }
        if added > 0 {
            let (total, target) = totals(in: context, now: now)
            WidgetSyncService.recordWater(totalMl: total, targetMl: target, now: now, defaults: defaults)
        }
        return added
    }
}
