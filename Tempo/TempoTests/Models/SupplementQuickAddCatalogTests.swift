//
// SupplementQuickAddCatalogTests.swift
// Tempo
//
// The quick-add grid's data: every entry must be well-formed (a real kind,
// a non-empty dose, a non-empty icon, protein grams only where they make
// sense) and the "skip what's already on the shelf" filter must match
// case-insensitively on name — the contract the quick-add sheet depends on
// to never offer a duplicate.
//

@testable import Tempo
import XCTest

final class SupplementQuickAddCatalogTests: XCTestCase {
    // MARK: - Catalog integrity

    func testCatalogHasAroundTwentyTwoItems() {
        XCTAssertGreaterThanOrEqual(SupplementQuickAddCatalog.items.count, 20)
        XCTAssertLessThanOrEqual(SupplementQuickAddCatalog.items.count, 25)
    }

    func testAllNamesAreUniqueCaseInsensitively() {
        let lowered = SupplementQuickAddCatalog.items.map { $0.name.lowercased() }
        XCTAssertEqual(Set(lowered).count, lowered.count, "Catalog must not contain duplicate names")
    }

    func testEveryItemHasNonEmptyDoseAndIcon() {
        for item in SupplementQuickAddCatalog.items {
            XCTAssertFalse(item.dose.isEmpty, "\(item.name) needs a labeled dose")
            XCTAssertFalse(item.icon.isEmpty, "\(item.name) needs an SF Symbol")
            XCTAssertFalse(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testOnlyProteinKindItemsCarryProteinGrams() {
        // Collagen (kind .other) is the one non-powder with protein (9 g/scoop).
        for item in SupplementQuickAddCatalog.items where item.kind != .protein && item.name != "Collagen" {
            XCTAssertEqual(item.proteinGrams, 0, "\(item.name) is not a protein powder; proteinGrams should be 0")
        }
    }

    func testProteinItemsHavePositiveProteinGrams() {
        let proteins = SupplementQuickAddCatalog.items.filter { $0.kind == .protein }
        XCTAssertFalse(proteins.isEmpty)
        for item in proteins {
            XCTAssertGreaterThan(item.proteinGrams, 0, "\(item.name) should carry its protein grams/serving")
        }
    }

    func testCreatineDefaultsToDailyInTheCatalog() {
        let creatine = SupplementQuickAddCatalog.items.first { $0.name.lowercased().contains("creatine monohydrate") }
        XCTAssertEqual(creatine?.takeDaily, true)
    }

    func testCommonNamesArePresent() {
        let names = Set(SupplementQuickAddCatalog.items.map { $0.name.lowercased() })
        for expected in [
            "creatine monohydrate",
            "whey protein",
            "vitamin d3",
            "omega-3 fish oil",
            "magnesium glycinate",
            "multivitamin",
            "pre-workout",
            "melatonin",
        ] {
            XCTAssertTrue(names.contains(expected), "Expected catalog to include \(expected)")
        }
    }

    // MARK: - Skip-what's-already-on-the-shelf filter

    func testAvailableExcludesExactNameMatch() {
        let available = SupplementQuickAddCatalog.available(excluding: ["Creatine Monohydrate"])
        XCTAssertFalse(available.contains { $0.name == "Creatine Monohydrate" })
    }

    func testAvailableExcludesCaseInsensitiveMatch() {
        let available = SupplementQuickAddCatalog.available(excluding: ["creatine monohydrate", "WHEY PROTEIN"])
        XCTAssertFalse(available.contains { $0.name == "Creatine Monohydrate" })
        XCTAssertFalse(available.contains { $0.name == "Whey Protein" })
    }

    func testAvailableKeepsEverythingWhenShelfIsEmpty() {
        let available = SupplementQuickAddCatalog.available(excluding: [])
        XCTAssertEqual(available.count, SupplementQuickAddCatalog.items.count)
    }

    func testAvailableIgnoresUnrelatedShelfNames() {
        let available = SupplementQuickAddCatalog.available(excluding: ["My Custom Stack"])
        XCTAssertEqual(available.count, SupplementQuickAddCatalog.items.count)
    }
}
