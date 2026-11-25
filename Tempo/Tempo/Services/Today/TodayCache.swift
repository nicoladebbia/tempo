//
// TodayCache.swift
// Tempo
//
// The last Today that was drawn, kept on disk so the next launch can draw it
// before anything has loaded. It holds health and nutrition numbers, so the
// file is written with complete file protection and removed on sign-out and
// account deletion (docs/SECURITY_AND_PRIVACY.md, data inventory).
//

import Foundation
import os

// MARK: - TodayCaching

protocol TodayCaching: Sendable {
    /// The saved snapshot as it should look at `now` (an earlier day's progress cleared).
    func load(now: Date, calendar: Calendar) -> TodaySnapshot?
    /// Saves in the background. Returns at once.
    func save(_ snapshot: TodaySnapshot)
    /// Removes the saved copy, and any save still waiting to be written.
    func clear()
}

extension TodayCaching {
    func load() -> TodaySnapshot? {
        load(now: Date(), calendar: .current)
    }
}

// MARK: - TodayCache

/// File-backed cache. All disk work runs on one private serial queue, so it
/// never blocks the main thread and a `clear()` can never be overtaken by an
/// earlier `save`.
final class TodayCache: TodayCaching {
    let url: URL
    private let queue = DispatchQueue(label: "com.tempo.today-cache", qos: .utility)

    static let shared = TodayCache(
        url: URL.cachesDirectory.appending(path: "today-snapshot.json")
    )

    init(url: URL) {
        self.url = url
    }

    /// Reads on the cache queue, after any save or clear already requested.
    /// Call it off the main thread (launch does: `TodayLaunchSnapshot`).
    func load(now: Date = Date(), calendar: Calendar = .current) -> TodaySnapshot? {
        queue.sync {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(TodaySnapshot.self, from: data)
            else {
                return nil
            }
            return snapshot.carried(to: calendar.startOfDay(for: now))
        }
    }

    func save(_ snapshot: TodaySnapshot) {
        queue.async { [url] in
            guard let data = try? JSONEncoder().encode(snapshot) else {
                return
            }
            // Unreadable while the phone is locked.
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    func clear() {
        queue.async { [url] in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Waits for every save and clear requested so far (tests).
    func flush() {
        queue.sync {}
    }
}

// MARK: - TodayLaunchSnapshot

/// Reads the saved snapshot off the main thread as the process starts, so it
/// is already in memory when Today draws its first frame. If the read is not
/// finished by then, Today picks it up as soon as it is (`value`).
final class TodayLaunchSnapshot: Sendable {
    static let shared = TodayLaunchSnapshot(cache: TodayCache.shared)

    /// Outer nil: still reading.
    private let result: OSAllocatedUnfairLock<TodaySnapshot??>
    private let task: Task<TodaySnapshot?, Never>

    init(cache: any TodayCaching) {
        let result = OSAllocatedUnfairLock<TodaySnapshot??>(initialState: nil)
        self.result = result
        task = Task.detached(priority: .userInitiated) {
            let snapshot = cache.load()
            result.withLock { $0 = .some(snapshot) }
            return snapshot
        }
    }

    /// Starts the read. Call once, as early in launch as possible.
    static func begin() {
        _ = shared
    }

    /// The snapshot if the read has finished; `ready` is false while it has not.
    func peek() -> (ready: Bool, snapshot: TodaySnapshot?) {
        result.withLock { value in
            switch value {
            case let .some(snapshot): (true, snapshot)
            case .none: (false, nil)
            }
        }
    }

    var value: TodaySnapshot? {
        get async {
            _ = await task.value
            return peek().snapshot
        }
    }

    /// Forgets the snapshot (sign-out), so nothing drawn later can bring it back.
    func discard() {
        result.withLock { $0 = .some(nil) }
    }
}
