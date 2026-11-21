//
// AIBlockerTests.swift
// Tempo
//
// Round 2 lane P: one mapping from "needs Pro" / "AI is off" errors, however
// deeply wrapped, to the shared card; and readable words for APIError.
//

@testable import Tempo
import XCTest

final class AIBlockerTests: XCTestCase {
    func testDirectAPIErrors() {
        XCTAssertEqual(AIBlocker(APIError.subscriptionRequired), .proRequired)
        XCTAssertEqual(AIBlocker(APIError.aiConsentRequired), .aiConsentRequired)
        XCTAssertNil(AIBlocker(APIError.serverError(statusCode: 500)))
        XCTAssertNil(AIBlocker(APIError.timeout))
        XCTAssertNil(AIBlocker(APIError.unauthorized))
    }

    func testNestedWrappers() {
        XCTAssertEqual(
            AIBlocker(MealPlanGeneratorError.generationFailed(APIError.subscriptionRequired)), .proRequired
        )
        XCTAssertEqual(
            AIBlocker(VoiceMealLogError.apiFailed(APIError.aiConsentRequired)), .aiConsentRequired
        )
        XCTAssertEqual(
            AIBlocker(VoicePantryError.apiFailed(APIError.subscriptionRequired)), .proRequired
        )
        XCTAssertEqual(
            AIBlocker(NutritionCoachError.apiFailed(APIError.subscriptionRequired)), .proRequired
        )
        XCTAssertEqual(
            AIBlocker(WeeklyPlanService.BuildError.server("ai_consent_required")), .aiConsentRequired
        )
        let wrapped = NSError(
            domain: "x", code: 1,
            userInfo: [NSUnderlyingErrorKey: APIError.subscriptionRequired]
        )
        XCTAssertEqual(AIBlocker(wrapped), .proRequired)
    }

    func testNonBlockersStayNil() {
        XCTAssertNil(AIBlocker(VoiceMealLogError.apiFailed(APIError.timeout)))
        XCTAssertNil(AIBlocker(VoiceMealLogError.emptyTranscript))
        XCTAssertNil(AIBlocker(NaturalLanguageLoggingError.parseFailed("x")))
        XCTAssertNil(AIBlocker(NutritionError.photoAnalysisFailed("x")))
        XCTAssertNil(AIBlocker(RecipeParseError.invalidResponse))
    }

    func testActionsAndCopy() {
        XCTAssertEqual(AIBlocker.proRequired.actionTitle, "See Pro")
        XCTAssertEqual(AIBlocker.aiConsentRequired.actionTitle, "Turn on AI")
        XCTAssertEqual(AIBlocker.message(for: APIError.subscriptionRequired), AIBlocker.proRequired.message)
        XCTAssertEqual(
            PlanGenerationBlocker(from: .aiConsentRequired).aiBlocker, .aiConsentRequired
        )
    }

    func testAPIErrorLocalizedDescriptionIsReadable() {
        let errors: [APIError] = [
            .invalidURL, .noResponse, .unauthorized, .forbidden, .notFound, .conflict, .payloadTooLarge,
            .rateLimited(retryAfter: nil), .serverError(statusCode: 500), .decodingFailed("x"),
            .networkError("x"), .connectionRefused, .notModified, .timeout, .unknown(statusCode: 3),
            .subscriptionRequired, .aiConsentRequired,
        ]
        for error in errors {
            let text = (error as Error).localizedDescription
            XCTAssertEqual(text, error.userMessage)
            XCTAssertFalse(text.contains("Tempo.APIError"), "\(error)")
        }
    }

    func testReadableDescriptionForWrappedFailures() {
        XCTAssertFalse(AIBlocker.readableDescription(NutritionError.noFoodDetected).contains("Tempo."))
        XCTAssertFalse(
            AIBlocker.readableDescription(NaturalLanguageLoggingError.parseFailed("Server error.")).contains("Tempo.")
        )
        XCTAssertEqual(
            AIBlocker.readableDescription(VoiceMealLogError.apiFailed(APIError.timeout)),
            "Couldn't reach the assistant: Request timed out. Please try again."
        )
    }

    func testConsentCacheRoundTrip() {
        let defaults = UserDefaults(suiteName: "AIBlockerTests-\(UUID().uuidString)")!
        XCTAssertNil(AIConsentStore.cachedValue(defaults: defaults))
        AIConsentStore.cache(true, defaults: defaults)
        XCTAssertEqual(AIConsentStore.cachedValue(defaults: defaults), true)
    }
}
