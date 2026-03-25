import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIEndpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: HTTPMethod
    let requiresAuth: Bool

    init(path: String, method: HTTPMethod = .get, requiresAuth: Bool = true) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
    }
}

// MARK: - Auth Endpoints

extension APIEndpoint where Response == AuthTokenResponse {
    static func signInWithApple() -> Self {
        APIEndpoint(path: "/v1/auth/apple", method: .post, requiresAuth: false)
    }

    static func refreshToken() -> Self {
        APIEndpoint(path: "/v1/auth/refresh", method: .post, requiresAuth: false)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func logout() -> Self {
        APIEndpoint(path: "/v1/auth/logout", method: .post, requiresAuth: true)
    }
}

// MARK: - Sync Endpoints

extension APIEndpoint where Response == SyncStatusResponse {
    static func syncStatus() -> Self {
        APIEndpoint(path: "/v1/sync/status", method: .get)
    }
}

extension APIEndpoint where Response == SyncBatchResponse {
    static func syncBatch() -> Self {
        APIEndpoint(path: "/v1/sync/batch", method: .post)
    }
}

// MARK: - Response DTOs (stubs — full definitions in later phases)

struct AuthTokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

struct SyncStatusResponse: Codable, Sendable {
    let last_synced: [String: String]
}

struct SyncBatchResponse: Codable, Sendable {
    let succeeded: Int
    let failed: Int
}

struct EmptyResponse: Codable, Sendable {}
