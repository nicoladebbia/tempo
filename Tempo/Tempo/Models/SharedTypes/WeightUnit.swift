import Foundation

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg
    case lbs

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        guard self != target else { return value }
        switch (self, target) {
        case (.kg, .lbs): return value * 2.20462
        case (.lbs, .kg): return value / 2.20462
        default: return value
        }
    }
}
