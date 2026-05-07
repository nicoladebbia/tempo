//
// WeightUnit.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

enum WeightUnit: String, Codable, CaseIterable {
    case kg
    case lbs

    var abbreviation: String {
        switch self {
        case .kg: "kg"
        case .lbs: "lbs"
        }
    }

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        guard self != target else {
            return value
        }
        switch (self, target) {
        case (.kg, .lbs): return value * 2.20462
        case (.lbs, .kg): return value / 2.20462
        default: return value
        }
    }
}
