//
// PendingWaterQueue.swift
// Shared by Tempo and TempoWidget
//
// Water the widget's button logged from inside the widget extension, which has
// no access to the app's database. Each glass is one small entry in the app
// group; the app adds them to its store (and so to Apple Health) the next time
// it runs, then removes them. One key per entry, so the extension appending
// while the app drains can never lose or double an entry.
//

import Foundation

// MARK: - PendingWaterLog

struct PendingWaterLog: Codable, Equatable, Sendable {
    let id: UUID
    let ml: Int
    let at: Date
}

// MARK: - PendingWaterQueue

enum PendingWaterQueue {
    private static let prefix = "widget.pendingWater.v1."

    /// Adds a glass to the queue. Returns false when the app group is unavailable.
    @discardableResult
    static func append(
        ml: Int,
        at date: Date = Date(),
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
    ) -> Bool {
        guard let defaults else {
            return false
        }
        let entry = PendingWaterLog(id: UUID(), ml: ml, at: date)
        guard let data = try? JSONEncoder().encode(entry) else {
            return false
        }
        defaults.set(data, forKey: prefix + entry.id.uuidString)
        return true
    }

    /// Everything waiting, oldest first, without removing it.
    static func pending(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
    ) -> [PendingWaterLog] {
        guard let defaults else {
            return []
        }
        let entries: [PendingWaterLog] = defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix(prefix), let data = value as? Data else {
                return nil
            }
            return try? JSONDecoder().decode(PendingWaterLog.self, from: data)
        }
        return entries.sorted { $0.at < $1.at }
    }

    /// Removes an entry once the app has saved it.
    static func remove(
        _ entry: PendingWaterLog,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
    ) {
        defaults?.removeObject(forKey: prefix + entry.id.uuidString)
    }
}
