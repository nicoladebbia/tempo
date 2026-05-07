//
// WhoopConnection.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

@Model
final class WhoopConnection {
    @Attribute(.unique)
    var id: UUID

    var isConnected: Bool

    var lastSyncAt: Date?

    var tokenExpiresAt: Date?

    var whoopUserID: String?

    var statusMessage: String?

    // MARK: - Computed

    @Transient
    var isTokenExpired: Bool {
        guard let expires = tokenExpiresAt else {
            return true
        }
        return Date().addingTimeInterval(300) >= expires
    }

    @Transient
    var lastSyncFormatted: String? {
        guard let lastSync = lastSyncAt else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        isConnected: Bool = false,
        lastSyncAt: Date? = nil,
        tokenExpiresAt: Date? = nil,
        whoopUserID: String? = nil,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.isConnected = isConnected
        self.lastSyncAt = lastSyncAt
        self.tokenExpiresAt = tokenExpiresAt
        self.whoopUserID = whoopUserID
        self.statusMessage = statusMessage
    }
}
