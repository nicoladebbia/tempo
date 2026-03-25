import Foundation

/// Converts between kg and lbs with rounding rules appropriate per equipment type.
enum WeightConverter {

    /// Convert kg to lbs.
    static func toLbs(_ kg: Double) -> Double {
        kg * 2.20462
    }

    /// Convert lbs to kg.
    static func toKg(_ lbs: Double) -> Double {
        lbs / 2.20462
    }

    /// Round to nearest plate increment.
    /// Barbell: 2.5 kg / 5 lbs. Dumbbell: 1 kg / 2 lbs. Machine: 5 kg / 10 lbs.
    static func roundToPlate(_ weight: Double, equipment: PlateIncrement, unit: WeightUnit = .kg) -> Double {
        let increment: Double
        switch (equipment, unit) {
        case (.barbell, .kg): increment = 2.5
        case (.barbell, .lbs): increment = 5
        case (.dumbbell, .kg): increment = 1
        case (.dumbbell, .lbs): increment = 2
        case (.machine, .kg): increment = 5
        case (.machine, .lbs): increment = 10
        case (.bodyweight, _): return weight
        }
        return (weight / increment).rounded() * increment
    }

    enum PlateIncrement: Sendable {
        case barbell
        case dumbbell
        case machine
        case bodyweight
    }
}
