//
// SyncState.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

@Model
final class SyncState {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var entityType: String

    var lastSyncedAt: Date?

    var lastServerVersion: String?

    var pendingChangesCount: Int

    // MARK: - Computed

    @Transient
    var hasPendingChanges: Bool {
        pendingChangesCount > 0
    }

    @Transient
    var timeSinceLastSync: TimeInterval? {
        lastSyncedAt.map { Date().timeIntervalSince($0) }
    }

    @Transient
    var isStale: Bool {
        guard let interval = timeSinceLastSync else {
            return true
        }
        return interval > 900
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        entityType: String,
        lastSyncedAt: Date? = nil,
        lastServerVersion: String? = nil,
        pendingChangesCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.lastSyncedAt = lastSyncedAt
        self.lastServerVersion = lastServerVersion
        self.pendingChangesCount = pendingChangesCount
    }
}
