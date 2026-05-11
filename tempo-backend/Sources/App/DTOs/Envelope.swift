import Vapor

// MARK: - Envelope DTO
// Per VAPOR_PROJECT_STRUCTURE.md — Standard response wrapper.
// All API responses wrapped in { ok, data, pagination?, meta }.

struct Envelope<T: Content>: Content {
    var ok: Bool
    var data: T
    var pagination: PaginationMeta?
    var meta: ResponseMeta

    init(data: T, pagination: PaginationMeta? = nil, requestID: String? = nil) {
        self.ok = true
        self.data = data
        self.pagination = pagination
        self.meta = ResponseMeta(
            requestID: requestID ?? "req_" + String.randomHex(length: 12),
            timestamp: Date()
        )
    }
}

// MARK: - Response Meta

struct ResponseMeta: Content {
    var requestID: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case timestamp
    }
}

// MARK: - Pagination Meta

struct PaginationMeta: Content {
    var cursor: String?
    var hasMore: Bool
    var count: Int

    enum CodingKeys: String, CodingKey {
        case cursor
        case hasMore = "has_more"
        case count
    }
}

// MARK: - Pagination Query

struct PaginationQuery: Content {
    var cursor: String?
    var limit: Int?
    var direction: String?
}

// MARK: - Empty Response

/// Standard empty payload for endpoints that confirm success without a body.
/// Used as `Envelope<EmptyResponse>` so the response shape remains consistent.
struct EmptyResponse: Content {}
