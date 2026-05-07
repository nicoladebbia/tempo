//
// SyncCoordinatorProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - SyncConflict

struct SyncConflict {
    let entityType: String
    let entityID: UUID
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
}

// MARK: - SyncResolution

enum SyncResolution {
    case keepLocal
    case keepRemote
    case merge
}

// MARK: - SyncCoordinatorProtocol

protocol SyncCoordinatorProtocol: Sendable {
    func syncAll() async throws
    func uploadPending() async throws
    func downloadUpdates(since: Date) async throws
    func resolveConflicts(_ conflicts: [SyncConflict]) -> [SyncResolution]
}
