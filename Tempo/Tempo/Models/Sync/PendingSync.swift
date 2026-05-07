//
// PendingSync.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

@Model
final class PendingSync {
    @Attribute(.unique)
    var id: UUID

    var entityType: String

    var entityID: UUID

    var actionRaw: String

    var payload: Data?

    var createdAt: Date

    var retryCount: Int

    var lastError: String?

    var nextRetryAt: Date?

    // MARK: - Computed

    @Transient
    var action: SyncAction {
        get { SyncAction(rawValue: actionRaw) ?? .update }
        set { actionRaw = newValue.rawValue }
    }

    @Transient
    var isReadyForRetry: Bool {
        guard let nextRetry = nextRetryAt else {
            return true
        }
        return Date() >= nextRetry
    }

    @Transient
    var isExhausted: Bool {
        retryCount >= 5
    }

    // MARK: - Methods

    func recordFailure(error: String) {
        retryCount += 1
        lastError = error
        let delay = TimeInterval(30 * pow(4.0, Double(retryCount - 1)))
        nextRetryAt = Date().addingTimeInterval(min(delay, 7200))
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: UUID,
        action: SyncAction,
        payload: Data? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        actionRaw = action.rawValue
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
