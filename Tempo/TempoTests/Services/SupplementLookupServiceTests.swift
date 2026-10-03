//
// SupplementLookupServiceTests.swift
// Tempo
//
// The scan screen must never dead-end: a 404 → notFound, no network →
// offline (checked before ever hitting the mock), any other failure →
// failed(message) — each mapped by `SupplementLookupRunner` from a mocked
// `SupplementLookupServicing`, no real network or SwiftUI involved.
//

@testable import Tempo
import XCTest

// MARK: - MockSupplementLookupService

@MainActor
private final class MockSupplementLookupService: SupplementLookupServicing {
    var result: Result<SupplementLookupDTO, Error> = .failure(APIError.notFound)
    private(set) var requestedUPCs: [String] = []

    func lookUp(upc: String) async throws -> SupplementLookupDTO {
        requestedUPCs.append(upc)
        return try result.get()
    }
}

// MARK: - SupplementLookupServiceTests

@MainActor
final class SupplementLookupServiceTests: XCTestCase {
    private func makeDTO() -> SupplementLookupDTO {
        SupplementLookupDTO(
            upc: "748927028669",
            brand: "Thorne",
            name: "Creatine Monohydrate",
            kind: "creatine",
            dosePerServing: "5 g",
            servingsPerContainer: 90,
            proteinGramsPerServing: nil,
            certifications: [],
            source: "dsld"
        )
    }

    func testFoundOutcomeCarriesTheDTO() async {
        let mock = MockSupplementLookupService()
        let dto = makeDTO()
        mock.result = .success(dto)

        let outcome = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock)

        XCTAssertEqual(outcome, .found(dto))
        XCTAssertEqual(mock.requestedUPCs, ["748927028669"])
    }

    func testNotFoundMapsAPIErrorNotFound() async {
        let mock = MockSupplementLookupService()
        mock.result = .failure(APIError.notFound)

        let outcome = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock)

        XCTAssertEqual(outcome, .notFound)
    }

    func testOfflineShortCircuitsWithoutCallingTheService() async {
        let mock = MockSupplementLookupService()
        mock.result = .success(makeDTO())

        let outcome = await SupplementLookupRunner.run(upc: "748927028669", isOffline: true, using: mock)

        XCTAssertEqual(outcome, .offline)
        XCTAssertTrue(mock.requestedUPCs.isEmpty, "Offline must not attempt the network call")
    }

    func testOtherAPIErrorsMapToFailed() async {
        let mock = MockSupplementLookupService()
        mock.result = .failure(APIError.serverError(statusCode: 500))

        let outcome = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock)

        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }

    func testPhoneEAN13SpellingIsSentAsTheUPCA() async {
        let mock = MockSupplementLookupService()
        mock.result = .success(makeDTO())

        _ = await SupplementLookupRunner.run(upc: "0748927028669", isOffline: false, using: mock)

        XCTAssertEqual(mock.requestedUPCs, ["748927028669"])
    }

    func testBadCheckDigitIsInvalidWithoutTouchingTheNetwork() async {
        let mock = MockSupplementLookupService()

        let outcome = await SupplementLookupRunner.run(upc: "748927028660", isOffline: false, using: mock)

        guard case .invalid = outcome else { return XCTFail("Expected .invalid, got \(outcome)") }
        XCTAssertTrue(mock.requestedUPCs.isEmpty)
    }

    func testShelfAnswersOfflineAndInEitherSpelling() async {
        let mock = MockSupplementLookupService()
        let owned = Supplement(name: "Gold Standard Whey", kind: .protein, dosePerServing: "1 scoop", proteinGramsPerServing: 24, servingsRemaining: 10)
        owned.upc = "748927028669"
        owned.brand = "Optimum Nutrition"

        let outcome = await SupplementLookupRunner.run(upc: "0748927028669", isOffline: true, using: mock, shelf: [owned])

        guard case let .found(dto) = outcome else { return XCTFail("Expected .found, got \(outcome)") }
        XCTAssertEqual(dto.name, "Gold Standard Whey")
        XCTAssertEqual(dto.source, "shelf")
        XCTAssertTrue(mock.requestedUPCs.isEmpty)
    }

    func testArchivedShelfItemIsNotAMatch() async {
        let mock = MockSupplementLookupService()
        mock.result = .success(makeDTO())
        let old = Supplement(name: "Old", kind: .protein, isArchived: true)
        old.upc = "748927028669"

        _ = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock, shelf: [old])

        XCTAssertEqual(mock.requestedUPCs.count, 1)
    }

    func testCacheServesAnOfflineRescanAndIsFilledByAHit() async {
        let defaults = UserDefaults(suiteName: "SupplementLookupServiceTests.\(UUID().uuidString)")!
        let cache = SupplementLookupCache(defaults: defaults)
        let mock = MockSupplementLookupService()
        mock.result = .success(makeDTO())

        _ = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock, cache: cache)
        let again = await SupplementLookupRunner.run(upc: "0748927028669", isOffline: true, using: mock, cache: cache)

        XCTAssertEqual(again, .found(makeDTO()))
        XCTAssertEqual(mock.requestedUPCs.count, 1)
    }

    func testMissesAreNeverCached() async {
        let defaults = UserDefaults(suiteName: "SupplementLookupServiceTests.\(UUID().uuidString)")!
        let cache = SupplementLookupCache(defaults: defaults)
        let mock = MockSupplementLookupService()
        mock.result = .failure(APIError.notFound)

        _ = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock, cache: cache)
        mock.result = .success(makeDTO())
        let second = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock, cache: cache)

        XCTAssertEqual(second, .found(makeDTO()))
    }

    func testNonAPIErrorsAlsoMapToFailedRatherThanCrashing() async {
        struct SomeOtherError: Error {}
        let mock = MockSupplementLookupService()
        mock.result = .failure(SomeOtherError())

        let outcome = await SupplementLookupRunner.run(upc: "748927028669", isOffline: false, using: mock)

        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }
}
