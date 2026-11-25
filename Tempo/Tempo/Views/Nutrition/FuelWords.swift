//
// FuelWords.swift
// Tempo
//
// Counts written the way a person says them: "1 meal", "2 meals", never "1 meals".
//

import Foundation

enum FuelWords {
    /// "1 meal", "3 meals". `plural` is only for nouns that do not just take an "s".
    /// The nouns the app uses are whole phrases in the String Catalog (one/other forms per
    /// language); any other noun falls back to the English rule.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        switch singular {
        case "item": String(localized: "\(n) items")
        case "serving": String(localized: "\(n) servings")
        case "meal": String(localized: "\(n) meals")
        case "day": String(localized: "\(n) days")
        case "week": String(localized: "\(n) weeks")
        case "product": String(localized: "\(n) products")
        case "match": String(localized: "\(n) matches")
        default: "\(n) " + (n == 1 ? singular : (plural ?? singular + "s"))
        }
    }
}
