import Vapor
import Crypto

// MARK: - Whoop Webhook Middleware
// Per INTEGRATION_SPECS.md Section 1.4 — HMAC-SHA256 verification for Whoop webhooks.

struct WhoopWebhookMiddleware: AsyncMiddleware {

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Read raw body for signature verification
        guard let rawBody = request.body.data else {
            throw Abort(.badRequest, reason: "Empty body")
        }
        let bodyString = String(buffer: rawBody)

        // 2. Extract signature and timestamp headers
        guard let signature = request.headers.first(name: "X-Whoop-Signature") else {
            throw Abort(.badRequest, reason: "Missing X-Whoop-Signature header")
        }
        guard let timestampString = request.headers.first(name: "X-Whoop-Timestamp"),
              let timestamp = Double(timestampString) else {
            throw Abort(.badRequest, reason: "Missing or invalid X-Whoop-Timestamp header")
        }

        // 3. Replay attack prevention: reject if timestamp is >5 minutes old
        let webhookTime = Date(timeIntervalSince1970: timestamp)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        guard webhookTime > fiveMinutesAgo else {
            request.logger.warning("Whoop webhook replay attempt: timestamp \(timestampString)")
            throw Abort(.unauthorized, reason: "Timestamp too old")
        }

        // 4. HMAC-SHA256 verification
        guard let webhookSecret = Environment.get("WHOOP_WEBHOOK_SECRET") else {
            request.logger.error("WHOOP_WEBHOOK_SECRET not configured")
            throw Abort(.internalServerError, reason: "Webhook secret not configured")
        }

        let signatureInput = "\(timestampString).\(bodyString)"
        let expectedSignature = HMAC<SHA256>.authenticationCode(
            for: Data(signatureInput.utf8),
            using: SymmetricKey(data: Data(webhookSecret.utf8))
        )
        let expectedHex = expectedSignature.map { String(format: "%02x", $0) }.joined()

        // Timing-safe comparison to prevent timing attacks
        guard timingSafeEqual(signature, expectedHex) else {
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
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}
