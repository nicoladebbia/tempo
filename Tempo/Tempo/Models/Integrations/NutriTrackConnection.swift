import Foundation
import SwiftData

@Model
final class NutriTrackConnection {

    @Attribute(.unique)
    var id: UUID

    var isConnected: Bool

    var serverURL: String?

    var lastSyncAt: Date?

    var statusMessage: String?

    // MARK: - Computed

    @Transient
    var lastSyncFormatted: String? {
        guard let lastSync = lastSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        isConnected: Bool = false,
        serverURL: String? = nil,
        lastSyncAt: Date? = nil,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.isConnected = isConnected
        self.serverURL = serverURL
        self.lastSyncAt = lastSyncAt
        self.statusMessage = statusMessage
    }
}
