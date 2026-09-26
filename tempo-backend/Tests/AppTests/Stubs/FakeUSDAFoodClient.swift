@testable import App
import Vapor

// MARK: - FakeUSDAFoodClient

//
// Injected in place of USDAAPIClient wherever a test needs
// FoodNutritionResolver to succeed (or fail) without ever touching the real
// USDA API. Canned responses are keyed by the exact `query` string passed to
// `search`, mirroring how FakeExerciseImageGenerator stands in for
// OpenAIImageGenerator.

final class FakeUSDAFoodClient: USDAFoodClient, @unchecked Sendable {
    enum Response {
        case success(USDASearchRawResponse)
        case failure(Error)
    }

    private var responses: [String: Response]
    private let callCounter = NIOLockedCounter()

    init(responses: [String: Response] = [:]) {
        self.responses = responses
    }

    var callCount: Int {
        callCounter.value
    }

    func setResponse(_ response: Response, for query: String) {
        responses[query] = response
    }

    func search(query: String, dataTypes _: [String], pageSize _: Int, on _: Request) async throws -> USDASearchRawResponse {
        callCounter.increment()
        switch responses[query] {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        case nil:
            return USDASearchRawResponse(foods: [])
        }
    }
}
