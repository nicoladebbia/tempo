import Foundation
import JWT
import Vapor

// MARK: - App Store Server Notifications V2 — JWS verification
//
// Per LAUNCH_PUNCH_LIST.md §3.2 + Apple's "Receiving App Store Server
// Notifications" guide.
//
// Apple delivers a single JSON body: `{ "signedPayload": "<JWS>" }`.
// The JWS:
//   - is signed by Apple
//   - carries an `x5c` header with the leaf cert + intermediate + Apple
//     Root CA - G3
//   - decodes to ResponseBodyV2DecodedPayload, which contains
//     `data.signedTransactionInfo` and `data.signedRenewalInfo` — two
//     further JWS strings that each chain up to the same Apple root.
//
// We validate the outer JWS, then verify each inner JWS *separately* so
// we never trust unverified inner data.

// MARK: Outer envelope

struct AppStoreSignedPayloadEnvelope: Content {
    let signedPayload: String
}

// MARK: V2 decoded payload (outer JWS body)
//
// We model only the fields we read. Apple sends more (summary blocks for
// renewal-extension responses, etc.); JSONDecoder ignores unknown keys.

struct ResponseBodyV2DecodedPayload: JWTPayload {
    let notificationType: String
    let subtype: String?
    let notificationUUID: String
    let version: String?
    let signedDate: Double?  // ms since epoch
    let data: NotificationData?

    func verify(using _: some JWTAlgorithm) async throws {
        // Apple's notifications carry no `exp`/`nbf`/`aud` claims —
        // the JWS signature itself + the x5c chain are the only proofs
        // of authenticity. Time-based replay protection happens via
        // the notificationUUID idempotency table on the controller side.
    }
}

struct NotificationData: Codable, Sendable {
    let appAppleId: Int?
    let bundleId: String?
    let bundleVersion: String?
    let environment: String  // "Sandbox" or "Production"
    let signedTransactionInfo: String?
    let signedRenewalInfo: String?
    let status: Int?
}

// MARK: Inner transaction info

struct AppStoreTransactionInfoPayload: JWTPayload {
    let originalTransactionId: String
    let transactionId: String?
    let productId: String
    let purchaseDate: Double?  // ms
    let originalPurchaseDate: Double?  // ms
    let expiresDate: Double?  // ms
    let type: String?
    let inAppOwnershipType: String?
    let environment: String
    let revocationDate: Double?  // ms
    let revocationReason: Int?

    func verify(using _: some JWTAlgorithm) async throws {}
}

// MARK: Inner renewal info

struct AppStoreRenewalInfoPayload: JWTPayload {
    let originalTransactionId: String
    let autoRenewProductId: String?
    let productId: String
    let autoRenewStatus: Int?
    let environment: String
    let renewalDate: Double?  // ms
    let recentSubscriptionStartDate: Double?  // ms

    func verify(using _: some JWTAlgorithm) async throws {}
}

// MARK: - Verifier

/// Holds the X5CVerifier so we only build the trust store once. Apple Root
/// CA - G3 is inlined as PEM below; it's a public document (fetched from
/// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer on
/// 2026-05-15, SHA-256 fingerprint
/// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79).
/// Bundling it sidesteps a runtime fetch + cache, and the root rotates
/// only on ~25-year boundaries — well outside our update cycle.
final class AppStoreNotificationVerifier: Sendable {
    static let shared = AppStoreNotificationVerifier()

    // Apple Root CA - G3 (public).
    // See https://www.apple.com/certificateauthority/
    private static let appleRootCAG3PEM = """
    -----BEGIN CERTIFICATE-----
    MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
    QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
    IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
    MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
    b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
    aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
    AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
    TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
    IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
    MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
    MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
    at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
    6BgD56KyKA==
    -----END CERTIFICATE-----
    """

    private let verifier: X5CVerifier

    private init() {
        do {
            self.verifier = try X5CVerifier(rootCertificates: [Self.appleRootCAG3PEM])
        } catch {
            // The cert is a compile-time constant we know parses. If it
            // doesn't, the build is broken and crashing on boot is the
            // right signal.
            fatalError("Failed to initialize Apple Root CA G3: \(error)")
        }
    }

    /// Verify the outer envelope. The returned payload's nested
    /// `signedTransactionInfo` / `signedRenewalInfo` are STILL untrusted
    /// strings — call `verifyTransaction(_:)` / `verifyRenewal(_:)` on
    /// each before reading them.
    func verifyEnvelope(_ jws: String) async throws -> ResponseBodyV2DecodedPayload {
        try await verifier.verifyJWS(jws, as: ResponseBodyV2DecodedPayload.self)
    }

    func verifyTransaction(_ jws: String) async throws -> AppStoreTransactionInfoPayload {
        try await verifier.verifyJWS(jws, as: AppStoreTransactionInfoPayload.self)
    }

    func verifyRenewal(_ jws: String) async throws -> AppStoreRenewalInfoPayload {
        try await verifier.verifyJWS(jws, as: AppStoreRenewalInfoPayload.self)
    }
}
