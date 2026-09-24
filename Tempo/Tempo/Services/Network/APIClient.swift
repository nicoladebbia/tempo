//
// APIClient.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os
import UIKit

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let authInterceptor: AuthInterceptor?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var etagCache: [String: String] = [:]

    private let logger = Logger(subsystem: "app.tempo", category: "APIClient")

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0

    init(
        baseURL: URL = AppConstants.apiBaseURL,
        session: URLSession? = nil,
        authInterceptor: AuthInterceptor? = nil
    ) {
        self.baseURL = baseURL
        // Default session has a 60s per-request timeout. AI proxy calls
        // (Haiku via Railway backend) can legitimately exceed that when
        // Railway is cold-starting from sleep — we saw two consecutive
        // /v1/nutrition/ai/proxy/text requests time out (-1001) right
        // after a token refresh that put the backend on its first call
        // for the session. 120s gives the cold-start headroom without
        // hiding actual hangs from the user.
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: config)
        }
        self.authInterceptor = authInterceptor

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public API

    func request<T: Decodable & Sendable>(
        _ endpoint: APIEndpoint<T>,
        body: (some Encodable & Sendable)? = nil as String?,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let urlRequest = try await buildRequest(endpoint, body: body, queryItems: queryItems)
        return try await executeWithRetry(urlRequest, endpoint: endpoint)
    }

    func request<T: Decodable & Sendable>(
        _ endpoint: APIEndpoint<T>,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let urlRequest = try await buildRequest(endpoint, body: nil as String?, queryItems: queryItems)
        return try await executeWithRetry(urlRequest, endpoint: endpoint)
    }

    // MARK: - Request Building

    private func buildRequest(
        _ endpoint: APIEndpoint<some Any>,
        body: (some Encodable)?,
        queryItems: [URLQueryItem]?
    ) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Custom headers per DEPENDENCIES.md Section 2.1
        request.setValue(appVersion, forHTTPHeaderField: "X-Client-Version")
        await request.setValue(deviceID(), forHTTPHeaderField: "X-Device-Id")

        if endpoint.method != .get {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        // ETag
        let cacheKey = endpoint.path
        if let etag = etagCache[cacheKey] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        // Auth
        if endpoint.requiresAuth, let interceptor = authInterceptor {
            // No access token → one refresh attempt, else fail locally as
            // .unauthorized (not retryable). Sending the request bare only
            // earned a guaranteed 401 plus retries while signed out.
            var token = try await interceptor.validToken()
            if token == nil {
                token = try? await interceptor.refreshAndGetToken()
            }
            guard let token else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Body
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        #if DEBUG
            logRequest(request)
        #endif

        return request
    }

    // MARK: - Execution with Retry

    private func executeWithRetry<T: Decodable & Sendable>(
        _ request: URLRequest,
        endpoint: APIEndpoint<T>,
        attempt: Int = 0,
        didRefreshToken: Bool = false
    ) async throws -> T {
        do {
            #if DEBUG
                let started = Date()
            #endif
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noResponse
            }

            #if DEBUG
                logResponse(httpResponse, data: data, elapsed: Date().timeIntervalSince(started))
            #endif

            // Cache ETag
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                etagCache[endpoint.path] = etag
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                }
                do {
                    if endpoint.expectsEnvelope {
                        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
                        return envelope.data
                    } else {
                        return try decoder.decode(T.self, from: data)
                    }
                } catch {
                    throw APIError.decodingFailed(error.localizedDescription)
                }

            case 304:
                // Not Modified — caller should use cached data
                throw APIError.notModified

            case 401:
                #if DEBUG
                    let serverReason = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                    let hadAuthHeader = request.value(forHTTPHeaderField: "Authorization") != nil
                    logger.error("← 401 \(endpoint.path) authHeaderPresent=\(hadAuthHeader) didRefresh=\(didRefreshToken) body=\(serverReason)")
                #endif
                // Token expired — refresh and retry once (does not consume a retry attempt)
                if endpoint.requiresAuth, let interceptor = authInterceptor, !didRefreshToken {
                    // A failed refresh means signed out — surface .unauthorized
                    // (non-retryable), not a retryable networkError.
                    guard let newToken = try? await interceptor.refreshAndGetToken() else {
                        throw APIError.unauthorized
                    }
                    var retryRequest = request
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    return try await executeWithRetry(retryRequest, endpoint: endpoint, attempt: 0, didRefreshToken: true)
                }
                throw APIError.unauthorized

            case 402:
                // Payment Required — backend `TempoErrorMiddleware` emits a
                // body like `{ "error": true, "reason": "...", "code": "..." }`.
                // Map `code` to the typed APIError so calling views can branch
                // on subscription vs consent without parsing free text.
                // Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
                let errBody = try? self.decoder.decode(APIError.TempoErrorBody.self, from: data)
                if errBody?.code == "ai_consent_required" {
                    throw APIError.aiConsentRequired
                }
                throw APIError.subscriptionRequired

            case 403:
                throw APIError.forbidden

            case 404:
                throw APIError.notFound

            case 409:
                throw APIError.conflict

            case 413:
                throw APIError.payloadTooLarge

            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw APIError.rateLimited(retryAfter: retryAfter)

            case 500 ... 599:
                throw APIError.serverError(statusCode: httpResponse.statusCode)

            default:
                throw APIError.unknown(statusCode: httpResponse.statusCode)
            }
        } catch let error as APIError {
            // Retry logic per ERROR_RECOVERY_FLOWS.md Section 8
            if error.isRetryable, attempt < maxRetries {
                let delay = retryDelay(for: error, attempt: attempt)
                try await Task.sleep(for: .seconds(delay))
                return try await executeWithRetry(request, endpoint: endpoint, attempt: attempt + 1)
            }
            throw error
        } catch is CancellationError {
            throw APIError.timeout
        } catch {
            // Connection refused (code -1004) — server not running, do not retry
            if let urlError = error as? URLError, urlError.code.rawValue == -1004 {
                throw APIError.connectionRefused
            }

            let apiError = APIError.networkError(error.localizedDescription)
            if apiError.isRetryable, attempt < maxRetries {
                let delay = baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
                return try await executeWithRetry(request, endpoint: endpoint, attempt: attempt + 1)
            }
            throw apiError
        }
    }

    // MARK: - Retry Delay

    private func retryDelay(for error: APIError, attempt: Int) -> TimeInterval {
        switch error {
        case let .rateLimited(retryAfter):
            retryAfter ?? 60.0
        default:
            // Exponential backoff: 1s, 2s, 4s
            baseDelay * pow(2.0, Double(attempt))
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func deviceID() async -> String {
        // Stable device identifier — in production, store in Keychain
        let vendorID = await MainActor.run { UIDevice.current.identifierForVendor }
        return vendorID?.uuidString ?? UUID().uuidString
    }

    // MARK: - Debug Logging

    #if DEBUG
        private func logRequest(_ request: URLRequest) {
            logger.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        }

        private func logResponse(_ response: HTTPURLResponse, data: Data, elapsed: TimeInterval) {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory)
            let ms = String(format: "%.0f", elapsed * 1000)
            logger.debug("← \(response.statusCode) [\(size)] \(ms)ms \(response.url?.absoluteString ?? "")")
        }
    #endif
}
