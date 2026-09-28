@testable import App
import Vapor

// MARK: - FakeSupplementLookupClient

// Test double for SupplementLookupClient — same shape as FakeInstacartClient.

final class FakeSupplementLookupClient: SupplementLookupClient, @unchecked Sendable {
    enum Response {
        case found(SupplementLookupDTO)
        case notFound
        case failure(Error)
    }

    private let response: Response
    private(set) var lastUPC: String?

    init(response: Response) {
        self.response = response
    }

    func lookup(upc: String, on _: Request) async throws -> SupplementLookupDTO? {
        lastUPC = upc
        switch response {
        case let .found(dto): return dto
        case .notFound: return nil
        case let .failure(error): throw error
        }
    }
}
