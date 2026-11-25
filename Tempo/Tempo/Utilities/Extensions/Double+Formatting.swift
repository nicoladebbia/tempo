//
// Double+Formatting.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

extension Double {
    /// A number for display text in the user's own format: "1.5" in English, "1,5" in Italian.
    /// Same digits as `String(format: "%.<digits>f")` (no thousands separator), so English text
    /// does not change. Use it for text the user reads; keep `String(format:)` for text that is
    /// parsed back, exported or sent to a server.
    func tempoDecimal(_ digits: Int = 1) -> String {
        formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// Formats a weight already in `unit`: "80.5 kg" or "177 lbs".
    func formattedWeight(unit: WeightUnit = .kg) -> String {
        "\(WeightFormat.number(self)) \(unit.abbreviation)"
    }

    /// Formats as percentage: "78%"
    var formattedPercentage: String {
        "\(Int(self))%"
    }

    /// Formats as score: "78" (no unit)
    var formattedScore: String {
        "\(Int(self))"
    }

    /// Formats duration in seconds to "Xh Ym" or "Xm Ys"
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? String(localized: "\(hours)h \(minutes)m") : String(localized: "\(hours)h")
        }
        if minutes > 0 {
            return seconds > 0 ? String(localized: "\(minutes)m \(seconds)s") : String(localized: "\(minutes)m")
        }
        return String(localized: "\(seconds)s")
    }

    /// Formats calories: "2,340 cal"
    var formattedCalories: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: self)) ?? "\(Int(self))"
        return String(localized: "\(formatted) cal")
    }

    /// Formats with k/M suffix for large numbers: "12.4k XP"
    var formattedCompact: String {
        if self >= 1_000_000 {
            return (self / 1_000_000).tempoDecimal(1) + "M"
        }
        if self >= 1000 {
            return (self / 1000).tempoDecimal(1) + "k"
        }
        return "\(Int(self))"
    }
}

// WeightUnit is defined in Models/SharedTypes/WeightUnit.swift
