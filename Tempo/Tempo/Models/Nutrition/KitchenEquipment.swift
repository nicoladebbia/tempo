//
// KitchenEquipment.swift
// Tempo
//
// The cooking appliances the user owns at home. The meal-plan AI reads this so
// it only programs recipes the user can actually make (no "roast in the oven"
// if they have only a stovetop + microwave). Per NUTRITION_PERSONALIZATION
// §9 — home-equipment only; per-location (school microwave) is deferred.
//
// One row per appliance with an `isAvailable` toggle. A standard set is seeded
// on first open of the Kitchen settings page; the user flips what they have.
//

import Foundation
import SwiftData

// MARK: - KitchenApplianceKind

/// The standard appliance set Tempo seeds. `rawValue` is the stable storage +
/// the user-facing label source.
enum KitchenApplianceKind: String, Codable, CaseIterable, Sendable {
    case stovetop
    case oven
    case microwave
    case riceCooker = "rice_cooker"
    case airFryer = "air_fryer"
    case blender
    case foodProcessor = "food_processor"
    case slowCooker = "slow_cooker"
    case toaster
    case kettle
    case grill

    var displayName: String {
        switch self {
        case .stovetop: "Stovetop"
        case .oven: "Oven"
        case .microwave: "Microwave"
        case .riceCooker: "Rice cooker"
        case .airFryer: "Air fryer"
        case .blender: "Blender"
        case .foodProcessor: "Food processor"
        case .slowCooker: "Slow cooker"
        case .toaster: "Toaster"
        case .kettle: "Kettle"
        case .grill: "Grill"
        }
    }

    var icon: String {
        switch self {
        case .stovetop: "flame"
        case .oven: "oven"
        case .microwave: "microwave"
        case .riceCooker: "takeoutbag.and.cup.and.straw"
        case .airFryer: "wind"
        case .blender: "tornado"
        case .foodProcessor: "gearshape.2"
        case .slowCooker: "timer"
        case .toaster: "square.split.1x2"
        case .kettle: "cup.and.saucer"
        case .grill: "grill"
        }
    }

    /// Appliances most people own — seeded as available so a user who never
    /// visits the Kitchen page still gets sensible recipes (a stovetop +
    /// microwave kitchen, not an empty one that blocks all cooking).
    var seededAvailable: Bool {
        switch self {
        case .stovetop, .oven, .microwave: true
        default: false
        }
    }
}

// MARK: - KitchenEquipment

@Model
final class KitchenEquipment {
    @Attribute(.unique)
    var id: UUID

    /// `KitchenApplianceKind.rawValue`.
    var kindRaw: String

    /// Whether the user has this appliance. The AI only uses available ones.
    var isAvailable: Bool

    var updatedAt: Date

    @Transient
    var kind: KitchenApplianceKind? {
        KitchenApplianceKind(rawValue: kindRaw)
    }

    init(
        id: UUID = UUID(),
        kind: KitchenApplianceKind,
        isAvailable: Bool,
        updatedAt: Date = Date()
    ) {
        self.id = id
        kindRaw = kind.rawValue
        self.isAvailable = isAvailable
        self.updatedAt = updatedAt
    }

    /// The standard appliance set with seeded availability — inserted on first
    /// open of the Kitchen settings page when no rows exist yet.
    static func seededSet() -> [KitchenEquipment] {
        KitchenApplianceKind.allCases.map {
            KitchenEquipment(kind: $0, isAvailable: $0.seededAvailable)
        }
    }
}
