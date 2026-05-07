//
// Streak.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - Streak

@Model
final class Streak {
    @Attribute(.unique)
    var id: UUID

    var typeRaw: String

    var currentCount: Int

    var longestCount: Int

    var lastCompletedDate: Date?

    var freezesUsed: Int

    var freezesAvailable: Int

    // MARK: - Computed

    @Transient
    var type: StreakType {
        get { StreakType(rawValue: typeRaw) ?? .overall }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var isActive: Bool {
        guard let lastDate = lastCompletedDate else {
            return false
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastDay = calendar.startOfDay(for: lastDate)
        return lastDay >= yesterday
    }

    @Transient
    var canFreeze: Bool {
        freezesAvailable > freezesUsed
    }

    // MARK: - Methods

    func recordCompletion(for date: Date = Date()) {
        let today = Calendar.current.startOfDay(for: date)

        guard lastCompletedDate != today else {
            return
        }

        if isActive {
            currentCount += 1
        } else {
            currentCount = 1
        }

        if currentCount > longestCount {
            longestCount = currentCount
        }

        lastCompletedDate = today
    }

    func breakStreak() {
        currentCount = 0
    }

    func useFreeze() -> Bool {
        guard canFreeze else {
            return false
        }
        freezesUsed += 1
        lastCompletedDate = Calendar.current.startOfDay(for: Date())
        return true
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        type: StreakType,
        currentCount: Int = 0,
        longestCount: Int = 0,
        lastCompletedDate: Date? = nil,
        freezesUsed: Int = 0,
        freezesAvailable: Int = 2
    ) {
        self.id = id
        typeRaw = type.rawValue
        self.currentCount = currentCount
        self.longestCount = longestCount
        self.lastCompletedDate = lastCompletedDate
        self.freezesUsed = freezesUsed
        self.freezesAvailable = freezesAvailable
    }
}

// MARK: - DTO

extension Streak {
    struct DTO: Codable {
        let id: UUID
        let type: String
        let current_count: Int
        let longest_count: Int
        let last_completed_date: Date?
        let freezes_used: Int
        let freezes_available: Int
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            type: typeRaw,
            current_count: currentCount,
            longest_count: longestCount,
            last_completed_date: lastCompletedDate,
            freezes_used: freezesUsed,
            freezes_available: freezesAvailable
        )
    }
}
