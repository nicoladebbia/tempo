//
// WhoopTokenSharer.swift
// Tempo
//
// The phone connects to WHOOP directly and owns the WHOOP login. The server's
// recovery coach (recent sessions, the post-workout weigh-in push) also reads
// WHOOP, so the phone shares each new WHOOP ACCESS token with the server:
//
//   PUT    /v1/integrations/whoop/token → WhoopTokenShareResponse (no envelope)
//   DELETE /v1/integrations/whoop       → WhoopUnlinkResponse      (no envelope)
//
// Only the access token (about an hour of life) is ever sent. The refresh token
// stays on the phone: WHOOP refresh tokens are single-use, so if the server
// refreshed too, phone and server would log each other out. The server never
// refreshes a phone-shared token; it just waits for the next one.
// Pinned by contracts/golden/integrations-whoop-token-put.json.
//

import Foundation
import os

// MARK: - WhoopTokenShareRequest

struct WhoopTokenShareRequest: Encodable, Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
    }
}

// MARK: - WhoopTokenShareResponse

struct WhoopTokenShareResponse: Decodable, Sendable, Equatable {
    let linked: Bool
    /// "phone": the server only holds the phone's access token. "server": it has its own WHOOP link.
    let managedBy: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case linked
        case managedBy = "managed_by"
        case expiresAt = "expires_at"
    }
}

// MARK: - WhoopUnlinkResponse

struct WhoopUnlinkResponse: Decodable, Sendable, Equatable {
    let disconnected: Bool
}

extension APIEndpoint where Response == WhoopTokenShareResponse {
    static func whoopShareToken() -> Self {
        APIEndpoint(path: "/v1/integrations/whoop/token", method: .put, expectsEnvelope: false)
    }
}

extension APIEndpoint where Response == WhoopUnlinkResponse {
    static func whoopUnlink() -> Self {
        APIEndpoint(path: "/v1/integrations/whoop", method: .delete, expectsEnvelope: false)
    }
}

// MARK: - WhoopTokenSharer

actor WhoopTokenSharer {
    typealias Send = @Sendable (WhoopTokenShareRequest) async throws -> WhoopTokenShareResponse
    typealias Unlink = @Sendable () async throws -> Void

    private let send: Send
    private let unlinkCall: Unlink
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "app.tempo", category: "WhoopTokenSharer")
    /// The last token the server accepted; the same token is never sent twice.
    private var lastShared: String?
    private var inFlight: (token: String, task: Task<Bool, Never>)?
    /// Bumped by `unlink()`: a share that started before an unlink must not count as current.
    private var generation = 0

    init(send: @escaping Send, unlink: @escaping Unlink, now: @escaping @Sendable () -> Date = { Date() }) {
        self.send = send
        unlinkCall = unlink
        self.now = now
    }

    init(apiClient: APIClient) {
        self.init(
            send: { try await apiClient.request(.whoopShareToken(), body: $0) },
            unlink: { _ = try await apiClient.request(.whoopUnlink()) }
        )
    }

    /// Share `accessToken` unless it already was (or is being) shared or has run out.
    /// Never throws: a failed share only means the server coach waits for the next token.
    @discardableResult
    func share(accessToken: String, expiresAt: Date) async -> Bool {
        guard !accessToken.isEmpty, expiresAt > now(), accessToken != lastShared else {
            return false
        }
        if let inFlight, inFlight.token == accessToken {
            return await inFlight.task.value
        }
        let request = WhoopTokenShareRequest(accessToken: accessToken, expiresAt: expiresAt)
        let send = send
        let logger = logger
        let task = Task<Bool, Never> {
            do {
                let response = try await send(request)
                logger.info("WHOOP access shared with the server (\(response.managedBy, privacy: .public))")
                return true
            } catch {
                logger.error("WHOOP access share failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        inFlight = (accessToken, task)
        let startedIn = generation
        let ok = await task.value
        if inFlight?.token == accessToken {
            inFlight = nil
        }
        guard startedIn == generation else {
            return false
        }
        if ok {
            lastShared = accessToken
        }
        return ok
    }

    /// WHOOP was disconnected on the phone: drop the server's copy too (best effort).
    func unlink() async {
        generation += 1
        lastShared = nil
        // Let a share already on the wire land first, so the DELETE below is the last word.
        if let pending = inFlight?.task {
            _ = await pending.value
        }
        do {
            try await unlinkCall()
        } catch APIError.notFound {
            // Nothing was linked.
        } catch {
            logger.error("WHOOP unlink failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
