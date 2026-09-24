//
// MissingRecoveryDataTests.swift
// Tempo
//
// "No recovery synced" (a 0 score) must never read as red anywhere, and a
// signed-out API call must fail locally instead of hammering the backend.
//

import SwiftData
@testable import Tempo
import XCTest

private final class CountingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct SignedOut: AuthTokenProvider {
    func accessToken() async -> String? { nil }
    func refreshToken() async throws -> String { throw URLError(.userAuthenticationRequired) }
}

@MainActor
final class MissingRecoveryDataTests: XCTestCase {
    func testSignedOutAuthCallFailsLocallyWithoutRetry() async {
        CountingProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingProtocol.self]
        let api = APIClient(
            baseURL: URL(string: "https://stub.test")!,
            session: URLSession(configuration: config),
            authInterceptor: AuthInterceptor(tokenProvider: SignedOut())
        )
        do {
            let _: AIConsentResponseDTO = try await api.request(
                APIEndpoint<AIConsentResponseDTO>.setAIConsent(),
                body: AIConsentRequestDTO(consented: true)
            )
            XCTFail("expected unauthorized")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("expected .unauthorized, got \(error)")
            }
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(CountingProtocol.requests, 0, "no request leaves the device while signed out")
    }

    func testZeroScorePrescriptionIsNotRed() {
        let engine = RecoveryEngine()
        func rx(_ score: Double) -> DailyPrescription {
            engine.generatePrescription(
                recovery: DailyRecovery(date: Date(), recoveryScore: score, sleepHours: 8, sleepEfficiency: 90),
                schedule: []
            )
        }
        XCTAssertEqual(rx(0).trainingRec, rx(RecoveryEngine.unknownRecoveryScore).trainingRec)
        XCTAssertNotEqual(rx(0).trainingRec, rx(10).trainingRec, "a real red day still reads red")
    }

    func testTrainingTreatsZeroRecoveryRowAsUnknown() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(DailyRecovery(date: Date(), recoveryScore: 0))
        try context.save()
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        XCTAssertNil(vm.loadRecoveryScore(modelContext: context))
    }
}
