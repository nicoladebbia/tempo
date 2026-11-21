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
    private(set) var lastLabelID: String?
    private(set) var lastOpenFactsBarcode: String?

    /// Search / label doubles for the merged-search tests (default: nothing, like the protocol default).
    var dsldSearch: Result<[SupplementSearchHit], Error> = .success([])
    var offSearch: Result<[SupplementSearchHit], Error> = .success([])
    var dsldLabel: SupplementLookupDTO?
    var offLabel: SupplementLookupDTO?

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

extension FakeSupplementLookupClient {
    func search(query _: String, on _: Request) async throws -> [SupplementSearchHit] {
        try dsldSearch.get()
    }

    func searchOpenFacts(query _: String, on _: Request) async throws -> [SupplementSearchHit] {
        try offSearch.get()
    }

    func label(id: String, on _: Request) async throws -> SupplementLookupDTO? {
        lastLabelID = id
        return dsldLabel
    }

    func openFactsLabel(barcode: String, on _: Request) async throws -> SupplementLookupDTO? {
        lastOpenFactsBarcode = barcode
        return offLabel
    }
}

// MARK: - FakeSupplementLabelReader

/// Answers `read-label` with canned model text (or a canned error), no network.
struct FakeSupplementLabelReader: SupplementLabelReading {
    let result: Result<String, Error>

    func readLabel(imageBase64 _: String, mediaType _: String, on _: Request) async throws -> String {
        try result.get()
    }
}
