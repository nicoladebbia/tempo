import Vapor
import JWT
import Crypto

// MARK: - Apple Auth Service
// Per BACKEND_API.md Section 2.1 — Verifies Apple identity tokens.
// Uses Vapor JWT's built-in Apple JWKS verification (auto-fetches and caches keys).

struct AppleAuthService {

    /// Verifies an Apple identity token and returns the decoded payload.
    /// Per BACKEND_API.md Section 2.1:
    /// 1. Fetch Apple's public keys (JWKS — handled by Vapor JWT)
    /// 2. Verify RS256 signature
    /// 3. Validate claims: iss, aud, exp
    /// 4. Validate nonce
    static func verifyIdentityToken(
        _ identityToken: String,
        expectedNonce: String,
        on req: Request
    ) async throws -> AppleIdentityToken {
        let bundleID = Environment.get("APPLE_BUNDLE_ID") ?? "com.nicoladebbia.Tempo"

        // Verify token using Vapor JWT's built-in Apple verification
        // This fetches Apple's JWKS, verifies RS256 signature, checks iss + exp
        let payload: AppleIdentityToken
        do {
            payload = try await req.jwt.apple.verify(identityToken, applicationIdentifier: bundleID)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired Apple identity token.")
        }

        // Validate nonce — Apple sends SHA-256 hash of the client nonce
        if let tokenNonce = payload.nonce {
            let expectedHash = SHA256.hash(data: Data(expectedNonce.utf8))
                .compactMap { String(format: "%02x", $0) }
                .joined()
            guard tokenNonce == expectedHash || tokenNonce == expectedNonce else {
                throw Abort(.badRequest, reason: "Nonce mismatch.")
            }
        } else if payload.nonceSupported?.value == true {
            // Nonce is supported but not present — fail
            throw Abort(.badRequest, reason: "Nonce expected but not found in token.")
        }

        return payload
    }
}
