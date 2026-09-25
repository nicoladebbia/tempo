//
// TrainerProgramImportQuotaMappingTests.swift
// Tempo
//
// APIClient's 402 handling must map `code: "program_import_quota"` to
// `APIError.programImportQuotaExceeded(limit:used:resetsAt:)` with the
// structured fields intact (fix #1) — not just the generic
// `.subscriptionRequired` every other 402 gets. Uses a stub URLProtocol
// (same pattern as AIProgramPlannerFailureTests) so this runs with no real
// network.
//

import Foundation
@testable import Tempo
import XCTest

// MARK: - QuotaStubProtocol

private final class QuotaStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - TrainerProgramImportQuotaMappingTests

final class TrainerProgramImportQuotaMappingTests: XCTestCase {
    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuotaStubProtocol.self]
        return APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config))
    }

    func testProgramImportQuotaCodeMapsToStructuredError() async {
        QuotaStubProtocol.status = 402
        QuotaStubProtocol.body = Data("""
        {"error":true,"reason":"You've used your 2 free trainer-program imports this month.","code":"program_import_quota","limit":2,"used":2,"resets_at":"2026-10-01T00:00:00Z"}
        """.utf8)

        do {
            let _: ProgramImportQuotaResponseDTO = try await makeClient().request(
                APIEndpoint<ProgramImportQuotaResponseDTO>.trainerProgramImportQuota()
            )
            XCTFail("expected .programImportQuotaExceeded to be thrown")
        } catch let APIError.programImportQuotaExceeded(limit, used, resetsAt) {
            XCTAssertEqual(limit, 2)
            XCTAssertEqual(used, 2)
            XCTAssertGreaterThan(resetsAt.timeIntervalSince1970, 0)
        } catch {
            XCTFail("expected .programImportQuotaExceeded, got \(error)")
        }
    }

    func testOtherFourZeroTwoCodesStillMapToSubscriptionRequired() async {
        QuotaStubProtocol.status = 402
        QuotaStubProtocol.body = Data(#"{"error":true,"reason":"Pro required","code":"subscription_required"}"#.utf8)

        do {
            let _: ProgramImportQuotaResponseDTO = try await makeClient().request(
                APIEndpoint<ProgramImportQuotaResponseDTO>.trainerProgramImportQuota()
            )
            XCTFail("expected .subscriptionRequired to be thrown")
        } catch APIError.subscriptionRequired {
            // expected — unrelated 402 codes must not be reclassified as a quota error.
        } catch {
            XCTFail("expected .subscriptionRequired, got \(error)")
        }
    }

    func testProgramImportQuotaUserMessageNamesTheLimit() {
        let error = APIError.programImportQuotaExceeded(limit: 2, used: 2, resetsAt: Date())
        XCTAssertTrue(error.userMessage.contains("2"))
        XCTAssertFalse(error.isRetryable, "a blind retry can't fix an exhausted monthly quota")
    }
}
