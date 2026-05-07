//
// SyncEnums.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - SyncAction

enum SyncAction: String, Codable, CaseIterable {
    case create
    case update
    case delete
}
