//
// TrainingSplit.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

enum TrainingSplit: String, Codable, CaseIterable {
    case pushPullLegs = "ppl"
    case upperLower = "upper_lower"
    case fullBody = "full_body"
    case bro = "bro_split"
    case custom

    var displayName: String {
        switch self {
        case .pushPullLegs: "Push/Pull/Legs"
        case .upperLower: "Upper/Lower"
        case .fullBody: "Full Body"
        case .bro: "Bro Split"
        case .custom: "Custom"
        }
    }

    /// Maps an onboarding split CHIP label (TrainingSetupView.splits) to the
    /// canonical split. Returns nil for "I Don't Know" / unknown so the caller can
    /// fall back to a days-per-week inference instead of forcing a guess. Requirement
    /// (a) — the user's explicit split choice was captured then discarded at
    /// onboarding completion; this rescues it (mirrors the experienceLevel rescue).
    static func fromOnboardingLabel(_ label: String) -> TrainingSplit? {
        switch label {
        case "PPL": .pushPullLegs
        case "Upper/Lower": .upperLower
        case "Full Body": .fullBody
        case "Bro Split": .bro
        default: nil // "I Don't Know" or anything unmapped
        }
    }

    /// Infers a sensible split from the user's chosen training days/week — used
    /// only when no explicit split was picked ("I Don't Know"). Standard
    /// hypertrophy cadence: ≤3 → full body, 4 → upper/lower, 5 → bro, 6+ → PPL.
    static func forDaysPerWeek(_ days: Int) -> TrainingSplit {
        switch days {
        case ...3: .fullBody
        case 4: .upperLower
        case 5: .bro
        default: .pushPullLegs
        }
    }
}
