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
        // The app ships under three bundle IDs (Debug / Staging / Release),
        // each of which Apple stamps as the token's `aud`. The backend must
        // accept any of them. `APPLE_BUNDLE_ID` may override as a
        // comma-separated allowlist; the default covers all three shipped
        // variants. (The old fallback `com.nicoladebbia.Tempo` matched none
        // of them, which 401'd every sign-in.)
        let bundleIDs: [String] = (Environment.get("APPLE_BUNDLE_ID")
            ?? "app.tempo.Tempo,app.tempo.Tempo.dev,app.tempo.Tempo.staging")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Verify token using Vapor JWT's built-in Apple verification
        // (fetches Apple's JWKS, verifies RS256 signature, checks iss + exp).
        // Vapor's verify() takes a single applicationIdentifier, so try each
        // allowed bundle ID and accept the first that validates.
        var payload: AppleIdentityToken?
        var lastError: Error?
        for bundleID in bundleIDs {
            do {
                payload = try await req.jwt.apple.verify(
                    identityToken,
                    applicationIdentifier: bundleID
                )
                break
            } catch {
                lastError = error
                req.logger.warning(
                    "[apple-auth] verify failed for aud=\(bundleID): \(String(reflecting: error))"
                )
            }
        }
        guard let payload else {
            req.logger.error(
                "[apple-auth] all bundle IDs failed (\(bundleIDs.joined(separator: ","))). Last error: \(String(reflecting: lastError))"
            )
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
