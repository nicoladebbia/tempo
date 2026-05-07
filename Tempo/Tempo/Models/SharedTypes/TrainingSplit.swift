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
}
