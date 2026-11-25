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
    /// "1 day", "2 days": the noun agrees with the number. English only: the
    /// screens use the whole-phrase helpers below, which Italian can translate.
    static func count(_ number: Int, _ singular: String, plural: String? = nil) -> String {
        let noun = number == 1 ? singular : (plural ?? singular + "s")
        return "\(number.formatted()) \(noun)"
    }

    /// "1 day", "3 days".
    static func days(_ number: Int) -> String {
        String(localized: "\(number) days")
    }

    /// "1 workout", "3 workouts".
    static func workouts(_ number: Int) -> String {
        String(localized: "\(number) workouts")
    }

    /// "1 streak freeze", "2 streak freezes".
    static func streakFreezes(_ number: Int) -> String {
        String(localized: "\(number) streak freezes")
    }

    /// "1 day streak", "5 days streak" (the old wording is kept as it was).
    static func streakDays(_ number: Int) -> String {
        String(localized: "\(number) days streak")
    }

    /// "Friends, 1 request", "Friends, 3 requests".
    static func friendsWithRequests(_ number: Int) -> String {
        String(localized: "Friends, \(number) requests")
    }

    /// How long a challenge has to run, from its last day.
    /// "Last day", "1 day left", "5 days left".
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case ..<1: String(localized: "Last day")
        default: String(localized: "\(days) days left")
        }
    }

    /// How long until a challenge starts: "Starts tomorrow", "Starts in 3 days".
    static func startsIn(_ days: Int) -> String {
        days <= 1 ? String(localized: "Starts tomorrow") : String(localized: "Starts in \(days) days")
    }

    /// "#2 of 5" for a rank among `total` people.
    static func rank(_ rank: Int, of total: Int) -> String {
        String(localized: "#\(rank) of \(total)")
    }

    /// "+3 more" for what the list leaves out.
    static func more(_ number: Int) -> String {
        String(localized: "+\(number) more")
    }
}
