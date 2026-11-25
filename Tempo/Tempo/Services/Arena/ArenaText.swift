//
// ArenaText.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaText

// The few sentences the Arena builds from numbers, in one place so "1 days
// left" cannot come back and each rule has a test.

enum ArenaText {
    /// "1 day", "2 days": the noun agrees with the number.
    static func count(_ number: Int, _ singular: String, plural: String? = nil) -> String {
        let noun = number == 1 ? singular : (plural ?? singular + "s")
        return "\(number.formatted()) \(noun)"
    }

    /// How long a challenge has to run, from its last day.
    /// "Last day", "1 day left", "5 days left".
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<1: "Last day"
        default: "\(count(days, "day")) left"
        }
    }

    /// How long until a challenge starts: "Starts tomorrow", "Starts in 3 days".
    static func startsIn(_ days: Int) -> String {
        days <= 1 ? "Starts tomorrow" : "Starts in \(count(days, "day"))"
    }

    /// "#2 of 5" for a rank among `total` people.
    static func rank(_ rank: Int, of total: Int) -> String {
        "#\(rank) of \(total)"
    }

    /// "+3 more" for what the list leaves out.
    static func more(_ number: Int) -> String {
        "+\(number) more"
    }
}
