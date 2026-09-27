@testable import App
import Vapor

// MARK: - FakeInstacartClient

// Test double for InstacartClient — same shape as FakeUSDAFoodClient.

final class FakeInstacartClient: InstacartClient, @unchecked Sendable {
    enum Response {
        case success(String)
        case failure(Error)
    }

    private let response: Response
    private(set) var lastTitle: String?
    private(set) var lastItems: [InstacartCartItemDTO]?
    private(set) var lastAPIKey: String?

    init(response: Response) {
        self.response = response
    }

    func createShoppingListLink(
        title: String,
        items: [InstacartCartItemDTO],
        apiKey: String,
        on _: Request
    ) async throws -> String {
        lastTitle = title
        lastItems = items
        lastAPIKey = apiKey
        switch response {
        case let .success(url): return url
        case let .failure(error): throw error
        }
    }
}
