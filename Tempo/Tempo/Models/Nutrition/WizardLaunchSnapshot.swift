//
// WizardLaunchSnapshot.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - WizardLaunchSnapshot

struct WizardLaunchSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let pantry: PantrySnapshot
    let whoop: WhoopSnapshot?

    init(id: UUID = UUID(), pantry: PantrySnapshot, whoop: WhoopSnapshot?) {
        self.id = id
        self.pantry = pantry
        self.whoop = whoop
    }

    /// Pantry is considered "stale" when empty or last updated more than 7 days ago.
    /// Drives whether the PantryGap step fires.
    var pantryNeedsAttention: Bool {
        if pantry.itemCount == 0 {
            return true
        }
        guard let mostRecent = pantry.mostRecentUpdate else {
            return true
        }
        let secondsInWeek: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(mostRecent) > secondsInWeek
    }

    var hasWhoop: Bool {
        whoop != nil
    }
}

// MARK: - PantrySnapshot

struct PantrySnapshot: Sendable, Equatable {
    let itemCount: Int
    let mostRecentUpdate: Date?
}

// MARK: - WhoopSnapshot

struct WhoopSnapshot: Sendable, Equatable {
    let recoveryScore: Double
}
