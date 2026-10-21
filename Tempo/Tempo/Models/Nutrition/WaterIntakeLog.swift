//
// WaterIntakeLog.swift
// Tempo
//
// One row per water tap ("+250", "+500", custom). Water used to live only in
// the Dashboard view model's memory and vanished on relaunch; these rows are
// the saved source of truth that Nutrition Today, the Dashboard Fuel tile and
// Apple Health (dietaryWater) all read from. Undo deletes the row.
//

import Foundation
import SwiftData

@Model
final class WaterIntakeLog {
    @Attribute(.unique)
    var id: UUID

    /// Calendar day this counts toward, normalized to start-of-day.
    var day: Date

    /// Millilitres drunk.
    var ml: Int

    /// Wall-clock moment of the tap.
    var loggedAt: Date

    /// HKMetadataKeySyncIdentifier of the Apple Health sample written for this
    /// row ("tempo-water-<id>"). Undo deletes the Health sample by it.
    var healthSyncID: String

    init(id: UUID = UUID(), ml: Int, loggedAt: Date = Date()) {
        self.id = id
        self.ml = ml
        self.loggedAt = loggedAt
        day = Calendar.current.startOfDay(for: loggedAt)
        healthSyncID = WaterIntakeLog.syncID(for: id)
    }

    static func syncID(for id: UUID) -> String {
        "tempo-water-\(id.uuidString)"
    }
}
