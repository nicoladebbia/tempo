import Vapor

// MARK: - Request ID Middleware
// Per VAPOR_PROJECT_STRUCTURE.md — Generates or propagates X-Request-Id on every request/response.

struct RequestIdMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let requestID = request.headers.first(name: "X-Request-Id")
            ?? "req_" + String.randomHex(length: 12)

        request.storage[RequestIDKey.self] = requestID
        request.logger[metadataKey: "request_id"] = .string(requestID)

        var response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Request-Id", value: requestID)
        return response
    }
}

struct RequestIDKey: StorageKey {
    typealias Value = String
}
