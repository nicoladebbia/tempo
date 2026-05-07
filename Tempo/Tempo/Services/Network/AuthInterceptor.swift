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

    func validToken() async throws -> String? {
        guard let token = await tokenProvider.accessToken() else {
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
