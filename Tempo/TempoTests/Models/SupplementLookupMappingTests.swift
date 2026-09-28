//
// SupplementLookupMappingTests.swift
// Tempo
//
// The barcode-scan → shelf bridge (Supplement+Lookup.swift): a DTO from the
// backend must map onto a Supplement with the right kind/servings/brand/upc,
// an unrecognized kind string must fall back to `.other` rather than crash,
// duplicate detection must match by UPC first then name, and a restock must
// top up (not reset) servingsRemaining and stamp lastRestockedAt.
//

@testable import Tempo
import XCTest

@MainActor
final class SupplementLookupMappingTests: XCTestCase {
    private func makeDTO(
        upc: String = "0123456789012",
        brand: String? = "Thorne",
        name: String = "Creatine Monohydrate",
        kind: String = "creatine",
        dosePerServing: String? = "5 g",
        servingsPerContainer: Double? = 90,
        proteinGramsPerServing: Double? = nil,
        certifications: [String] = ["NSF Certified for Sport"]
    ) -> SupplementLookupDTO {
        SupplementLookupDTO(
            upc: upc,
            brand: brand,
            name: name,
            kind: kind,
            dosePerServing: dosePerServing,
            servingsPerContainer: servingsPerContainer,
            proteinGramsPerServing: proteinGramsPerServing,
            certifications: certifications,
            source: "dsld"
        )
    }

    // MARK: - DTO → Supplement mapping

    func testMapsFieldsFromDTO() {
        let dto = makeDTO()
        let supp = Supplement(lookup: dto)
        XCTAssertEqual(supp.name, "Creatine Monohydrate")
        XCTAssertEqual(supp.kind, .creatine)
        XCTAssertEqual(supp.dosePerServing, "5 g")
        XCTAssertEqual(supp.brand, "Thorne")
        XCTAssertEqual(supp.upc, "0123456789012")
        XCTAssertEqual(supp.servingsPerContainer, 90)
        // New product from a scan starts with a full container, not empty.
        XCTAssertEqual(supp.servingsRemaining, 90)
    }

    func testUnknownKindStringFallsBackToOther() {
        let dto = makeDTO(kind: "some-future-kind-the-app-doesnt-know")
        let supp = Supplement(lookup: dto)
        XCTAssertEqual(supp.kind, .other)
    }

    func testMissingOptionalFieldsDefaultSafely() {
        let dto = makeDTO(dosePerServing: nil, servingsPerContainer: nil, proteinGramsPerServing: nil)
        let supp = Supplement(lookup: dto)
        XCTAssertEqual(supp.dosePerServing, "")
        XCTAssertEqual(supp.proteinGramsPerServing, 0)
        XCTAssertEqual(supp.servingsRemaining, 0)
        XCTAssertNil(supp.servingsPerContainer)
    }

    func testProteinGramsCarryThroughForProteinPowders() {
        let dto = makeDTO(name: "Whey Isolate", kind: "protein", proteinGramsPerServing: 25)
        let supp = Supplement(lookup: dto)
        XCTAssertEqual(supp.proteinGramsPerServing, 25)
    }

    // MARK: - Duplicate detection

    func testDuplicateMatchesByUPC() {
        let existing = Supplement(name: "My Creatine", kind: .creatine)
        existing.upc = "0123456789012"
        let found = Supplement.duplicate(forUPC: "0123456789012", name: "Totally Different Label", in: [existing])
        XCTAssertTrue(found === existing)
    }

    func testDuplicateMatchesByNameCaseInsensitively() {
        let existing = Supplement(name: "Creatine Monohydrate", kind: .creatine)
        let found = Supplement.duplicate(forUPC: "999", name: "creatine monohydrate", in: [existing])
        XCTAssertTrue(found === existing)
    }

    func testDuplicateIgnoresArchivedItems() {
        let archived = Supplement(name: "Creatine Monohydrate", kind: .creatine, isArchived: true)
        let found = Supplement.duplicate(forUPC: "999", name: "Creatine Monohydrate", in: [archived])
        XCTAssertNil(found)
    }

    func testNoDuplicateWhenNothingMatches() {
        let existing = Supplement(name: "Whey Isolate", kind: .protein)
        let found = Supplement.duplicate(forUPC: "999", name: "Creatine Monohydrate", in: [existing])
        XCTAssertNil(found)
    }

    // MARK: - Restock

    func testRestockAddsToExistingServings() {
        let existing = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 5)
        existing.restock(fromContainerSize: 90)
        XCTAssertEqual(existing.servingsRemaining, 95, "Restock tops up, it doesn't reset")
    }

    func testRestockStampsLastRestockedAt() {
        let existing = Supplement(name: "Creatine", kind: .creatine)
        XCTAssertNil(existing.lastRestockedAt)
        existing.restock(fromContainerSize: 90)
        XCTAssertNotNil(existing.lastRestockedAt)
    }

    func testRestockIgnoresNegativeContainerSize() {
        let existing = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 10)
        existing.restock(fromContainerSize: -5)
        XCTAssertEqual(existing.servingsRemaining, 10)
    }
}
