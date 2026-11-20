import Crypto
import Foundation
import Vapor

// MARK: - Whoop Webhook Middleware
//
// Signature check exactly as WHOOP documents it (developer.whoop.com, "Webhooks Security", read 2026-11-20):
//   headers   X-WHOOP-Signature            the signature, base64
//             X-WHOOP-Signature-Timestamp  milliseconds since epoch
//   expected  base64( HMAC-SHA256( timestamp_header + raw_body, client_secret ) )   (no separator between the two)
// The secret is the app's client secret from the WHOOP Developer Dashboard.

struct WhoopWebhookMiddleware: AsyncMiddleware {
    /// Reject deliveries whose timestamp is more than this far from now (replay protection).
    static let maxAge: TimeInterval = 5 * 60

    /// `WHOOP_WEBHOOK_SECRET` if set, otherwise the app's `WHOOP_CLIENT_SECRET` (which is what WHOOP signs with).
    static func secret() -> String? {
        for name in ["WHOOP_WEBHOOK_SECRET", "WHOOP_CLIENT_SECRET"] {
            if let value = Environment.get(name), !value.isEmpty { return value }
        }
        return nil
    }

    static func expectedSignature(timestamp: String, body: String, secret: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data((timestamp + body).utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return Data(mac).base64EncodedString()
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let rawBody = request.body.data else { throw Abort(.badRequest, reason: "Empty body") }
        let bodyString = String(buffer: rawBody)

        guard let signature = request.headers.first(name: "X-WHOOP-Signature") else {
            throw Abort(.badRequest, reason: "Missing X-WHOOP-Signature header")
        }
        guard let timestampString = request.headers.first(name: "X-WHOOP-Signature-Timestamp"), let timestampMs = Double(timestampString) else {
            throw Abort(.badRequest, reason: "Missing or invalid X-WHOOP-Signature-Timestamp header")
        }

        // Replay protection: the timestamp is in MILLISECONDS.
        let sentAt = Date(timeIntervalSince1970: timestampMs / 1000)
        guard abs(Date().timeIntervalSince(sentAt)) <= Self.maxAge else {
            request.logger.warning("Whoop webhook outside the allowed time window: \(timestampString)")
            throw Abort(.unauthorized, reason: "Timestamp too old")
        }

        guard let secret = Self.secret() else {
            request.logger.error("Neither WHOOP_WEBHOOK_SECRET nor WHOOP_CLIENT_SECRET is configured")
            throw Abort(.internalServerError, reason: "Webhook secret not configured")
        }

        let expected = Self.expectedSignature(timestamp: timestampString, body: bodyString, secret: secret)
        guard timingSafeEqual(signature, expected) else {
            request.logger.warning("Whoop webhook signature mismatch")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        return try await next.respond(to: request)
    }

    /// Timing-safe string comparison to prevent timing attacks on HMAC verification.
    private func timingSafeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for i in 0 ..< aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}
