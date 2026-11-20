//
// AuthInterceptor.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - AuthTokenProvider

protocol AuthTokenProvider: Sendable {
    func accessToken() async -> String?
    func refreshToken() async throws -> String
}

// MARK: - AuthInterceptor

actor AuthInterceptor {
    private let tokenProvider: AuthTokenProvider
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<String, Error>] = []

    init(tokenProvider: AuthTokenProvider) {
        self.tokenProvider = tokenProvider
    }

    /// The stored access token, or nil when there is none or it has (nearly) run out. nil makes the
    /// caller refresh BEFORE sending, so a cold launch with an expired token costs one refresh instead
    /// of a burst of requests that each come back 401.
    func validToken(now: Date = Date()) async throws -> String? {
        guard let token = await tokenProvider.accessToken() else {
            return nil
        }
        if let expiry = JWTExpiry.expiry(of: token), expiry <= now.addingTimeInterval(JWTExpiry.skew) {
            return nil
        }
        return token
    }

    func refreshAndGetToken() async throws -> String {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }

        isRefreshing = true
        do {
            let newToken = try await tokenProvider.refreshToken()
            let waiting = refreshContinuations
            refreshContinuations = []
            isRefreshing = false
            for continuation in waiting {
                continuation.resume(returning: newToken)
            }
            return newToken
        } catch {
            let waiting = refreshContinuations
            refreshContinuations = []
            isRefreshing = false
            for continuation in waiting {
                continuation.resume(throwing: error)
            }
            throw error
        }
    }
}

// MARK: - JWTExpiry

/// Reads the `exp` claim of a JWT without verifying it (the server does that).
/// A token without a readable `exp` counts as valid: the server's 401 still covers it.
enum JWTExpiry {
    /// Refresh this long before `exp` so a token can't run out in flight or on a skewed clock.
    static let skew: TimeInterval = 60

    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (object["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
