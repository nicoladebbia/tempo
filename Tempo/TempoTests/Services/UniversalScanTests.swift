//
// UniversalScanTests.swift
// Tempo
//
// Round 3 (Lane B): the one Scan screen — camera permission mapping, which
// modes each opener offers, where each mode's result goes, and the
// cached-product-first barcode lookup (known products open with no network).
//

import AVFoundation
import SwiftData
@testable import Tempo
import XCTest

// MARK: - CameraPermissionTests

final class CameraPermissionTests: XCTestCase {
    func testAuthorizedWithCameraIsAuthorized() {
        XCTAssertEqual(CameraPermission.resolve(status: .authorized, cameraSupported: true), .authorized)
    }

    func testNotDeterminedAsksOnFirstScan() {
        XCTAssertEqual(CameraPermission.resolve(status: .notDetermined, cameraSupported: true), .notDetermined)
    }

    func testDeniedAndRestrictedAreSeparateFromUnsupported() {
        XCTAssertEqual(CameraPermission.resolve(status: .denied, cameraSupported: true), .denied)
        XCTAssertEqual(CameraPermission.resolve(status: .restricted, cameraSupported: true), .restricted)
        // A "no" wins even where there is no scanner: Settings is the message.
        XCTAssertEqual(CameraPermission.resolve(status: .denied, cameraSupported: false), .denied)
    }

    func testNoScannerIsUnsupported() {
        XCTAssertEqual(CameraPermission.resolve(status: .authorized, cameraSupported: false), .unsupported)
        XCTAssertEqual(CameraPermission.resolve(status: .notDetermined, cameraSupported: false), .unsupported)
    }

    func testOnlyDeniedAndRestrictedAreBlockedByUser() {
        XCTAssertTrue(CameraPermission.denied.isBlockedByUser)
        XCTAssertTrue(CameraPermission.restricted.isBlockedByUser)
        XCTAssertFalse(CameraPermission.unsupported.isBlockedByUser)
        XCTAssertFalse(CameraPermission.notDetermined.isBlockedByUser)
    }

    @MainActor
    func testMessagesDifferForDeniedAndUnsupported() {
        XCTAssertNotEqual(ScanBarcodeSurface.title(for: .denied), ScanBarcodeSurface.title(for: .unsupported))
        XCTAssertTrue(ScanBarcodeSurface.message(for: .denied).contains("Settings"))
        XCTAssertFalse(ScanBarcodeSurface.message(for: .unsupported).contains("Settings"))
    }
}

// MARK: - ScanRoutingTests

final class ScanRoutingTests: XCTestCase {
    func testTodayOffersEveryModeAndRoutesEach() {
        let kind = ScanContextKind.today
        XCTAssertEqual(kind.allowedModes, ScanMode.allCases)
        XCTAssertEqual(kind.route(for: .barcode), .foodProductPage)
        XCTAssertEqual(kind.route(for: .receipt), .receiptReview)
        XCTAssertEqual(kind.route(for: .label), .addProduct)
        XCTAssertEqual(kind.route(for: .mealPhoto), .mealPhotoReview)
    }

    func testLogAndSearchHandFoodsBackToTheCaller() {
        XCTAssertEqual(ScanContextKind.logMeal.route(for: .barcode), .foodItemCallback)
        XCTAssertEqual(ScanContextKind.foodSearch.route(for: .barcode), .foodItemCallback)
        XCTAssertEqual(ScanContextKind.logMeal.route(for: .mealPhoto), .mealPhotoReview)
    }

    func testPantryAndSupplementsRouteBarcodeToTheirOwnConfirmStep() {
        XCTAssertEqual(ScanContextKind.pantryBarcode.route(for: .barcode), .pantryStaging)
        XCTAssertEqual(ScanContextKind.supplements.route(for: .barcode), .supplementShelf)
        XCTAssertEqual(ScanContextKind.pantryReceipt.route(for: .receipt), .receiptReview)
    }

    func testAllowedModesPerCaller() {
        XCTAssertEqual(ScanContextKind.logMeal.allowedModes, [.barcode, .mealPhoto])
        XCTAssertEqual(ScanContextKind.foodSearch.allowedModes, [.barcode])
        XCTAssertEqual(ScanContextKind.foodCheck.allowedModes, [.barcode, .label])
        XCTAssertEqual(ScanContextKind.pantryBarcode.allowedModes, [.barcode])
        XCTAssertEqual(ScanContextKind.pantryReceipt.allowedModes, [.receipt])
        XCTAssertEqual(ScanContextKind.supplements.allowedModes, [.barcode])
    }

    func testDisallowedModeHasNoRoute() {
        XCTAssertNil(ScanContextKind.pantryBarcode.route(for: .receipt))
        XCTAssertNil(ScanContextKind.supplements.route(for: .mealPhoto))
        XCTAssertNil(ScanContextKind.pantryReceipt.route(for: .barcode))
    }

    func testEveryKindStartsInAnAllowedMode() {
        for kind in ScanContextKind.allCases {
            XCTAssertTrue(kind.allowedModes.contains(kind.initialMode), "\(kind)")
            XCTAssertNotNil(kind.route(for: kind.initialMode), "\(kind)")
        }
    }

    @MainActor
    func testViewNarrowsModesAndFallsBackWhenInitialIsNotAllowed() {
        let narrowed = UniversalScanView(context: .today(), initialMode: .receipt, allowedModes: [.receipt, .label])
        XCTAssertEqual(narrowed.allowedModes, [.receipt, .label])
        let fallback = UniversalScanView(context: .foodCheck, initialMode: .receipt)
        XCTAssertEqual(fallback.allowedModes, [.barcode, .label])
        let emptied = UniversalScanView(context: .foodCheck, allowedModes: [.receipt])
        XCTAssertEqual(emptied.allowedModes, [.barcode, .label])
    }

    func testContextKindMapping() {
        XCTAssertEqual(ScanContext.today().kind, .today)
        XCTAssertEqual(ScanContext.foodCheck.kind, .foodCheck)
        XCTAssertEqual(ScanContext.foodSearch(onFood: nil).kind, .foodSearch)
        XCTAssertNil(ScanContext.foodSearch(onFood: nil).foodCallback)
        XCTAssertNotNil(ScanContext.foodSearch(onFood: { _ in }).foodCallback)
        XCTAssertNil(ScanContext.today().foodCallback)
    }
}

// MARK: - CachedFirstLookupTests

@MainActor
final class CachedFirstLookupTests: XCTestCase {
    private final class FakeProducts: FoodProductProviding, @unchecked Sendable {
        var byBarcode: [String: FoodProduct] = [:]
        var error: Error?
        var lookups = 0

        func product(barcode: String) async throws -> FoodProduct? {
            lookups += 1
            if let error {
                throw error
            }
            return byBarcode[barcode]
        }

        func search(_: String, limit _: Int) async throws -> [FoodProduct] {
            []
        }

        func alternatives(for _: FoodProduct, limit _: Int) async throws -> [FoodProduct] {
            []
        }
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: ScannedFood.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func product(_ name: String, kcal: Double = 400) -> FoodProduct {
        FoodProduct(
            id: "8000500310427", barcode: "8000500310427", name: name, brand: "Acme", source: .openFoodFacts,
            quantityLabel: "250 g",
            per100g: FoodProduct.Nutrients(kcal: kcal, protein: 10, carbs: 50, sugars: 5, fat: 15, saturatedFat: 3, fiber: 3, salt: 0.2),
            nutriScoreGrade: "b", nutriScorePoints: 2, categories: ["snacks"]
        )
    }

    func testUnknownBarcodeHasNoCachedProduct() throws {
        let catalog = FoodCatalog(products: FakeProducts(), generic: nil)
        XCTAssertNil(try catalog.cachedProduct(barcode: "8000500310427", in: makeContext()))
        XCTAssertNil(try catalog.cachedProduct(barcode: "", in: makeContext()))
    }

    func testKnownBarcodeIsReturnedWithoutTouchingTheNetwork() throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.error = FoodLookupError.offline
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.recordView(product("Crunchy Bar"), in: context)

        XCTAssertEqual(catalog.cachedProduct(barcode: " 8000-500310427 ", in: context)?.name, "Crunchy Bar")
        XCTAssertEqual(fake.lookups, 0)
    }

    func testBackgroundRefreshUpdatesTheSavedCopy() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.byBarcode["8000500310427"] = product("Crunchy Bar 2.0", kcal: 380)
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.recordView(product("Crunchy Bar"), in: context)

        await catalog.refreshCached(barcode: "8000500310427", in: context)
        XCTAssertEqual(fake.lookups, 1)
        XCTAssertEqual(catalog.cachedProduct(barcode: "8000500310427", in: context)?.name, "Crunchy Bar 2.0")
    }

    func testBackgroundRefreshOfflineKeepsTheOldCopy() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.error = FoodLookupError.offline
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.recordView(product("Crunchy Bar"), in: context)

        await catalog.refreshCached(barcode: "8000500310427", in: context)
        XCTAssertEqual(catalog.cachedProduct(barcode: "8000500310427", in: context)?.name, "Crunchy Bar")
    }

    func testRefreshNeverOverwritesYourOwnProduct() async throws {
        let context = try makeContext()
        let fake = FakeProducts()
        fake.byBarcode["8000500310427"] = product("From the web")
        let catalog = FoodCatalog(products: fake, generic: nil)
        catalog.saveUserAdded(product("Mine"), photo: nil, in: context)

        await catalog.refreshCached(barcode: "8000500310427", in: context)
        XCTAssertEqual(fake.lookups, 0)
        XCTAssertEqual(catalog.cachedProduct(barcode: "8000500310427", in: context)?.name, "Mine")
    }
}
