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
            upc: "0123456789012",
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

        let outcome = await SupplementLookupRunner.run(upc: "0123456789012", isOffline: false, using: mock)

        XCTAssertEqual(outcome, .found(dto))
        XCTAssertEqual(mock.requestedUPCs, ["0123456789012"])
    }

    func testNotFoundMapsAPIErrorNotFound() async {
        let mock = MockSupplementLookupService()
        mock.result = .failure(APIError.notFound)

        let outcome = await SupplementLookupRunner.run(upc: "000", isOffline: false, using: mock)

        XCTAssertEqual(outcome, .notFound)
    }

    func testOfflineShortCircuitsWithoutCallingTheService() async {
        let mock = MockSupplementLookupService()
        mock.result = .success(makeDTO())

        let outcome = await SupplementLookupRunner.run(upc: "000", isOffline: true, using: mock)

        XCTAssertEqual(outcome, .offline)
        XCTAssertTrue(mock.requestedUPCs.isEmpty, "Offline must not attempt the network call")
    }

    func testOtherAPIErrorsMapToFailed() async {
        let mock = MockSupplementLookupService()
        mock.result = .failure(APIError.serverError(statusCode: 500))

        let outcome = await SupplementLookupRunner.run(upc: "000", isOffline: false, using: mock)

        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }

    func testNonAPIErrorsAlsoMapToFailedRatherThanCrashing() async {
        struct SomeOtherError: Error {}
        let mock = MockSupplementLookupService()
        mock.result = .failure(SomeOtherError())

        let outcome = await SupplementLookupRunner.run(upc: "000", isOffline: false, using: mock)

        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }
}
