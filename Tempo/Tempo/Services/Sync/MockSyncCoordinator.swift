import Foundation
import os

final class MockSyncCoordinator: SyncCoordinatorProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "app.tempo", category: "MockSync")

    func syncAll() async throws {
        logger.debug("Mock: syncAll()")
    }

    func uploadPending() async throws {
        logger.debug("Mock: uploadPending()")
    }

    func downloadUpdates(since: Date) async throws {
        logger.debug("Mock: downloadUpdates(since: \(since))")
    }

    func resolveConflicts(_ conflicts: [SyncConflict]) -> [SyncResolution] {
        logger.debug("Mock: resolveConflicts(\(conflicts.count) conflicts)")
        return conflicts.map { conflict in
            conflict.remoteUpdatedAt > conflict.localUpdatedAt ? .keepRemote : .keepLocal
        }
    }
}
