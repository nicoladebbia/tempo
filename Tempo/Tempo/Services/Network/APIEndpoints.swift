//
// APIEndpoints.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIEndpoint

struct APIEndpoint<Response: Decodable & Sendable> {
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

// MARK: - AuthTokenResponse

struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

// MARK: - SyncStatusResponse

struct SyncStatusResponse: Codable {
    let last_synced: [String: String]
}

// MARK: - SyncBatchResponse

struct SyncBatchResponse: Codable {
    let succeeded: Int
    let failed: Int
}

// MARK: - EmptyResponse

struct EmptyResponse: Codable {}
