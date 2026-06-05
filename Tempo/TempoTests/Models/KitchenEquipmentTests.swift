//
// KitchenEquipmentTests.swift
// Tempo
//
// The KitchenEquipment model + its seeded set. The contract that matters: the
// standard appliance list seeds with a sane basic kitchen available (stovetop,
// oven, microwave) and everything else off, so a user who never opens the
// Kitchen page still gets makeable recipes. Per NUTRITION_PERSONALIZATION §9.
//

@testable import Tempo
import XCTest

@MainActor
final class KitchenEquipmentTests: XCTestCase {

    // MARK: - Seeded set

    func testSeededSetCoversEveryAppliance() {
        let seeded = KitchenEquipment.seededSet()
        XCTAssertEqual(
            seeded.count,
            KitchenApplianceKind.allCases.count,
            "Seeds one row per known appliance"
        )
        let kinds = Set(seeded.compactMap(\.kind))
        XCTAssertEqual(kinds.count, KitchenApplianceKind.allCases.count, "No duplicate kinds")
    }

    func testSeededDefaultsAreBasicKitchen() {
        let byKind = Dictionary(
            uniqueKeysWithValues: KitchenEquipment.seededSet().compactMap { eq in
                eq.kind.map { ($0, eq.isAvailable) }
            }
        )
        // A user who never opens the page still gets a stovetop+oven+microwave.
        XCTAssertEqual(byKind[.stovetop], true)
        XCTAssertEqual(byKind[.oven], true)
        XCTAssertEqual(byKind[.microwave], true)
        // Specialty appliances default off — they must opt in.
        XCTAssertEqual(byKind[.airFryer], false)
        XCTAssertEqual(byKind[.slowCooker], false)
        XCTAssertEqual(byKind[.riceCooker], false)
    }

    // MARK: - Kind round-trip

    func testKindRoundTripsThroughRawValue() {
        let eq = KitchenEquipment(kind: .foodProcessor, isAvailable: true)
        XCTAssertEqual(eq.kindRaw, "food_processor")
        XCTAssertEqual(eq.kind, .foodProcessor)
    }

    func testEveryKindHasDisplayNameAndIcon() {
        for kind in KitchenApplianceKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind) needs a display name")
            XCTAssertFalse(kind.icon.isEmpty, "\(kind) needs an icon")
        }
    }
}
