//
// NotificationRecorder.swift
// Tempo
//
// Records the notifications posted to a center while a test runs. Observer
// closures are `@Sendable`, so a test can't count posts by mutating a captured
// local `var`; read `count` / `notifications` from the recorder instead. It
// stops observing when it goes away.
//

import Foundation

final class NotificationRecorder: @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    private var received: [Notification] = []
    private var token: NSObjectProtocol?

    init(_ name: Notification.Name, center: NotificationCenter = .default) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
            self?.record(note)
        }
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }

    var notifications: [Notification] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    var count: Int {
        notifications.count
    }

    var didPost: Bool {
        count > 0
    }

    private func record(_ note: Notification) {
        lock.lock()
        defer { lock.unlock() }
        received.append(note)
    }
}
