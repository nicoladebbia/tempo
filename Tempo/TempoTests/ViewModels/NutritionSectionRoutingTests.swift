//
// NutritionSectionRoutingTests.swift
// TempoTests
//
// Tab sections (Today / Plan / Log / Kitchen / Coach) and Kitchen deep links.
//

@testable import Tempo
import XCTest

@MainActor
final class NutritionSectionRoutingTests: XCTestCase {
    func testSectionOrderAndNames() {
        XCTAssertEqual(NutritionSection.allCases.map(\.rawValue), ["Today", "Plan", "Log", "Kitchen", "Coach"])
    }

    func testKitchenHasFourPartsPantryFirst() {
        XCTAssertEqual(KitchenSection.allCases.map(\.rawValue), ["Pantry", "Groceries", "Receipts", "Supplements"])
        XCTAssertEqual(NutritionTabViewModel().selectedKitchen, .pantry, "Pantry is the default Kitchen part")
    }

    func testOpenKitchenGroceriesRoutesBoth() {
        let vm = NutritionTabViewModel()
        XCTAssertEqual(vm.selectedTab, .today)
        vm.openKitchen(.groceries)
        XCTAssertEqual(vm.selectedTab, .kitchen)
        XCTAssertEqual(vm.selectedKitchen, .groceries)
    }

    func testOpenKitchenSupplements() {
        let vm = NutritionTabViewModel()
        vm.openKitchen(.supplements)
        XCTAssertEqual(vm.selectedTab, .kitchen)
        XCTAssertEqual(vm.selectedKitchen, .supplements)
    }

    func testOpenQuickLogGoesToLogAndRequestsFocus() {
        let vm = NutritionTabViewModel()
        vm.openQuickLog()
        XCTAssertEqual(vm.selectedTab, .log)
        XCTAssertTrue(vm.focusQuickLogRequested)
    }
}
