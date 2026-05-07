//
// ActiveDays.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

struct ActiveDays: Codable, Equatable {
    var rawValue: Int

    static let monday = ActiveDays(rawValue: 1 << 0)
    static let tuesday = ActiveDays(rawValue: 1 << 1)
    static let wednesday = ActiveDays(rawValue: 1 << 2)
    static let thursday = ActiveDays(rawValue: 1 << 3)
    static let friday = ActiveDays(rawValue: 1 << 4)
    static let saturday = ActiveDays(rawValue: 1 << 5)
    static let sunday = ActiveDays(rawValue: 1 << 6)
    static let weekdays = ActiveDays(rawValue: 0b0011111)
    static let everyday = ActiveDays(rawValue: 0b1111111)

    func isActive(on weekday: Int) -> Bool {
        // weekday: 1 = Sunday (Calendar), remap to our Monday = 0
        let index = (weekday + 5) % 7
        return (rawValue & (1 << index)) != 0
    }

    mutating func toggle(_ day: ActiveDays) {
        rawValue ^= day.rawValue
    }
}
