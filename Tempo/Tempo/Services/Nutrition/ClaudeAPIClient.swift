//
// ClaudeAPIClient.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import os

// MARK: - ClaudeAPIClient

// Lightweight client for direct Claude API calls from the iOS app.
// Separate from the Tempo backend APIClient -- this goes straight to Anthropic
// for real-time coaching features where backend round-trips add unacceptable latency.
//
// Per AI_INTELLIGENCE_ENGINE.md Section 2.5, the backend handles most AI calls.
// This client handles only nutrition coaching features that need sub-second feedback.

actor ClaudeAPIClient {
    // MARK: - Configuration

    private let session: URLSession
    private let logger = Logger.nutrition
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// API key loaded from Info.plist (ANTHROPIC_API_KEY).
    private let apiKey: String

    // MARK: - Circuit Breaker State

    // Per AI_INTELLIGENCE_ENGINE.md Section 2.4

    private var circuitState: CircuitState = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    private var circuitOpenedAt: Date?

    private let failureThreshold = 3
    private let failureWindow: TimeInterval = 600 // 10 min
    private let recoveryTimeout: TimeInterval = 1800 // 30 min

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()

        if let key = Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String,
           !key.isEmpty, !key.hasPrefix("$(")
        {
            apiKey = key
        } else {
            apiKey = ""
            Logger.nutrition.warning("ANTHROPIC_API_KEY not found. Add it to Tempo/Configuration/Secrets.xcconfig")
        }
    }

    // MARK: - Public API

    /// Send a text message to Claude and receive the text response.
    func sendMessage(
        model: ClaudeModel,
        system: String,
        userMessage: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        try checkCircuit()

        let body = ClaudeRequestBody(
            model: model.rawValue,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: [
                ClaudeRequestMessage(role: "user", content: [
                    .text(userMessage),
                ]),
            ]
        )

        return try await execute(body: body, timeout: model.timeout)
    }

    /// Send a message with an image (base64-encoded) to Claude.
    /// Used for photo-based meal analysis coaching.
    func sendMessageWithImage(
        model: ClaudeModel,
        system: String,
        imageData: Data,
        userMessage: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        try checkCircuit()

        let base64Image = imageData.base64EncodedString()

        let body = ClaudeRequestBody(
            model: model.rawValue,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: [
                ClaudeRequestMessage(role: "user", content: [
                    .image(mediaType: "image/jpeg", data: base64Image),
                    .text(userMessage),
                ]),
            ]
        )

        return try await execute(body: body, timeout: model.timeout)
    }

    // MARK: - Execution

    private func execute(body: ClaudeRequestBody, timeout: TimeInterval) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.authError("API key not configured")
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = timeout

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw ClaudeAPIError.encodingFailed(error.localizedDescription)
        }

        #if DEBUG
            logger.debug("Claude API -> \(body.model) | max_tokens=\(body.maxTokens) | temp=\(body.temperature)")
        #endif

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                throw ClaudeAPIError.noResponse
            }

            #if DEBUG
                let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory)
                logger.debug("Claude API <- \(httpResponse.statusCode) [\(size)]")
            #endif

            switch httpResponse.statusCode {
            case 200 ... 299:
                recordSuccess()
                return try parseResponse(data)

            case 401:
                throw ClaudeAPIError.authError("Invalid API key")

            case 429:
                recordFailure()
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap { TimeInterval($0) }
                throw ClaudeAPIError.rateLimited(retryAfter: retryAfter)

            case 400:
                // Bad request -- prompt issue. Do NOT retry per AI_INTELLIGENCE_ENGINE.md Section 2.3.
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                logger.error("Claude API 400: \(errorBody)")
                throw ClaudeAPIError.badRequest(errorBody)

            case 500 ... 599:
                recordFailure()
                throw ClaudeAPIError.serverError(statusCode: httpResponse.statusCode)

            default:
                recordFailure()
                throw ClaudeAPIError.unknown(statusCode: httpResponse.statusCode)
            }
        } catch let error as ClaudeAPIError {
            throw error
        } catch is CancellationError {
            throw ClaudeAPIError.timeout
        } catch {
            recordFailure()
            throw ClaudeAPIError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> String {
        let response: ClaudeAPIResponse
        do {
            response = try decoder.decode(ClaudeAPIResponse.self, from: data)
        } catch {
            logger.error("Failed to decode Claude response: \(error.localizedDescription)")
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }

        guard let textBlock = response.content.first(where: { $0.type == "text" }),
              let text = textBlock.text, !text.isEmpty
        else {
            throw ClaudeAPIError.emptyResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Circuit Breaker

    // Per AI_INTELLIGENCE_ENGINE.md Section 2.4

    private func checkCircuit() throws {
        switch circuitState {
        case .closed:
            break

        case .open:
            guard let openedAt = circuitOpenedAt else {
                circuitState = .closed
                return
            }
            if Date().timeIntervalSince(openedAt) >= recoveryTimeout {
                circuitState = .halfOpen
                logger.info("Circuit breaker: OPEN -> HALF_OPEN (testing)")
            } else {
                throw ClaudeAPIError.circuitOpen
            }

        case .halfOpen:
            // Allow the test request through
            break
        }
    }

    private func recordSuccess() {
        switch circuitState {
        case .halfOpen:
            circuitState = .closed
            failureCount = 0
            lastFailureTime = nil
            circuitOpenedAt = nil
            logger.info("Circuit breaker: HALF_OPEN -> CLOSED (recovered)")
        case .closed:
            // Reset failure count on success
            failureCount = 0
        case .open:
            break
        }
    }

    private func recordFailure() {
        let now = Date()

        // Reset count if outside failure window
        if let lastFailure = lastFailureTime,
           now.timeIntervalSince(lastFailure) > failureWindow
        {
            failureCount = 0
        }

        failureCount += 1
        lastFailureTime = now

        if circuitState == .halfOpen {
            circuitState = .open
            circuitOpenedAt = now
            logger.warning("Circuit breaker: HALF_OPEN -> OPEN (test failed)")
        } else if failureCount >= failureThreshold {
            circuitState = .open
            circuitOpenedAt = now
            logger.warning("Circuit breaker: CLOSED -> OPEN (\(self.failureCount) failures in window)")
        }
    }
}

// MARK: - ClaudeModel

enum ClaudeModel: String {
    /// Haiku 4.5 -- sub-second latency for real-time features.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 2.1
    case haiku = "claude-haiku-4-5-20251001"

    /// Sonnet 4.6 -- deep analysis, weekly reviews.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 2.1
    case sonnet = "claude-sonnet-4-6"

    var timeout: TimeInterval {
        switch self {
        case .haiku: 10
        case .sonnet: 30
        }
    }
}

// MARK: - CircuitState

private enum CircuitState {
    case closed
    case open
    case halfOpen
}

// MARK: - ClaudeRequestBody

private struct ClaudeRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [ClaudeRequestMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

// MARK: - ClaudeRequestMessage

private struct ClaudeRequestMessage: Encodable {
    let role: String
    let content: [ClaudeRequestContent]
}

// MARK: - ClaudeRequestContent

private enum ClaudeRequestContent: Encodable {
    case text(String)
    case image(mediaType: String, data: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            try container.encode(ImageSource(type: "base64", mediaType: mediaType, data: data), forKey: .source)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    private struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }
}

// MARK: - ClaudeAPIResponse

private struct ClaudeAPIResponse: Decodable {
    let id: String
    let content: [ClaudeAPIContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case stopReason = "stop_reason"
    }
}

// MARK: - ClaudeAPIContentBlock

private struct ClaudeAPIContentBlock: Decodable {
    let type: String
    let text: String?
}

// MARK: - ClaudeAPIError

enum ClaudeAPIError: Error {
    case authError(String)
    case badRequest(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkError(String)
    case timeout
    case noResponse
    case emptyResponse
    case decodingFailed(String)
    case encodingFailed(String)
    case circuitOpen
    case unknown(statusCode: Int)

    /// Per AI_INTELLIGENCE_ENGINE.md Section 2.3: only retry server errors and rate limits.
    var isRetryable: Bool {
        switch self {
        case .rateLimited,
             .serverError:
            true
        default:
            false
        }
    }
}
