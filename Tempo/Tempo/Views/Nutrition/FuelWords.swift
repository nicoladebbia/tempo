//
// FuelWords.swift
// Tempo
//
// Counts written the way a person says them: "1 meal", "2 meals", never "1 meals".
//

import Foundation

enum FuelWords {
    /// "1 meal", "3 meals". `plural` is only for nouns that do not just take an "s".
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : (plural ?? singular + "s"))
    }
}
