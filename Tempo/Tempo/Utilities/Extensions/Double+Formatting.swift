import Foundation

extension Double {

    /// Formats weight: "80.5 kg" or "177 lbs"
    func formattedWeight(unit: WeightUnit = .kg) -> String {
        switch unit {
        case .kg:
            return truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(self)) kg"
                : String(format: "%.1f kg", self)
        case .lbs:
            return "\(Int(self)) lbs"
        }
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
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    /// Formats calories: "2,340 cal"
    var formattedCalories: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: self)) ?? "\(Int(self))"
        return "\(formatted) cal"
    }

    /// Formats with k/M suffix for large numbers: "12.4k XP"
    var formattedCompact: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", self / 1_000_000)
        }
        if self >= 1_000 {
            return String(format: "%.1fk", self / 1_000)
        }
        return "\(Int(self))"
    }
}

// WeightUnit is defined in Models/SharedTypes/WeightUnit.swift
