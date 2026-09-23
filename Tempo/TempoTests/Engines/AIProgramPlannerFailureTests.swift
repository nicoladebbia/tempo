//
// AIProgramPlannerFailureTests.swift
// Tempo
//
// The AI week call must tell "AI is off for this user" (402 not Pro / no
// consent — silent, week marked done) apart from "AI is broken right now"
// (surfaced on Week Plan and retried).
//

@testable import Tempo
import XCTest

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class AIProgramPlannerFailureTests: XCTestCase {
    private func planner() -> AIProgramPlanner {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config))
        return AIProgramPlanner(api: api)
    }

    private func run() async -> (rationale: String?, failed: Bool) {
        let result = await planner().planWeek(
            deterministicPlans: [],
            weekStart: Date(),
            recovery7Day: [],
            recentSessions: [],
            footballDays: [],
            goal: "hypertrophy"
        )
        return (result.rationale, result.failed)
    }

    func testNotProIsNotAFailure() async {
        StubProtocol.status = 402
        StubProtocol.body = Data(#"{"error":true,"reason":"pro","code":"subscription_required"}"#.utf8)
        let result = await run()
        XCTAssertNil(result.rationale)
        XCTAssertFalse(result.failed)
    }

    func testClientErrorIsAFailure() async {
        StubProtocol.status = 404
        StubProtocol.body = Data(#"{"error":true,"reason":"missing"}"#.utf8)
        let result = await run()
        XCTAssertNil(result.rationale)
        XCTAssertTrue(result.failed)
    }

    func testPersistenceAlertMessageNamesTheOperation() {
        PersistenceAlert.shared.report("session notes")
        XCTAssertEqual(PersistenceAlert.shared.message?.contains("session notes"), true)
        PersistenceAlert.shared.message = nil
    }
}
