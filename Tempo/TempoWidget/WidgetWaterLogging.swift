//
// WidgetWaterLogging.swift
// TempoWidget
//
// The widget extension's half of "Log water" (the app's is
// `Tempo/Intents/WaterLogging.swift`). The system may run the +250 ml button's
// intent in this process, which cannot open the app's database. So the glass is
// queued in the app group (`PendingWaterQueue`; the app adds it to its store and
// to Apple Health when it next runs) and the widgets' own total moves at once,
// so the tap shows.
//

import Foundation
import WidgetKit

enum WaterLogging {
    static func log(ml: Int) async throws -> WaterLogOutcome {
        let now = Date()
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
              PendingWaterQueue.append(ml: ml, at: now, defaults: defaults)
        else {
            throw WaterIntentError.couldNotSave
        }
        let base = WidgetSnapshot.read(from: defaults) ?? .empty(for: Calendar.current.startOfDay(for: now))
        let today = base.carried(to: now)
        let total = today.waterMl + ml
        today.updatingWater(ml: total, targetMl: today.waterTargetMl, now: now).write(to: defaults)
        WidgetCenter.shared.reloadAllTimelines()
        return WaterLogOutcome(addedMl: ml, totalMl: total, targetMl: today.waterTargetMl)
    }
}
