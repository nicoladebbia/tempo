import Foundation

// MARK: - Sync Types

struct SyncConflict: Sendable {
    let entityType: String
    let entityID: UUID
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
}

enum SyncResolution: Sendable {
    case keepLocal
    case keepRemote
    case merge
}

// MARK: - Protocol

protocol SyncCoordinatorProtocol: Sendable {
    func syncAll() async throws
    func uploadPending() async throws
    func downloadUpdates(since: Date) async throws
    func resolveConflicts(_ conflicts: [SyncConflict]) -> [SyncResolution]
}
