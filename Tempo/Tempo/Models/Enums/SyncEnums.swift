import Foundation

// MARK: - SyncAction

enum SyncAction: String, Codable, CaseIterable, Sendable {
    case create
    case update
    case delete
}
