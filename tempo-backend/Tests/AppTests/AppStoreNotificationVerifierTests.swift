@testable import App
import Testing
import Foundation

// MARK: - AppStoreNotificationVerifier tests
//
// We deliberately don't ship a "happy path" test that verifies a real
// Apple-signed payload. That requires an offline fixture Apple ships
// only via their developer portal (not redistributable), and live calls
// to App Store Connect's "Request Test Notification" button. Those
// belong in a manual integration check, not unit tests.
//
// What we CAN test cheaply and meaningfully: the verifier MUST refuse
// forged tokens. If these fail, the signature check is silently
// accepting garbage.

struct AppStoreNotificationVerifierTests {

    /// A JWS we made up: header "alg=none", random payload, no signature.
    /// X5CVerifier should reject it because the x5c chain is missing.
    @Test func rejectsTokenWithoutX5CChain() async throws {
        let header = #"{"alg":"ES256","typ":"JWT"}"#
        let payload = #"{"notificationType":"TEST","notificationUUID":"abc-123"}"#
        let encodedHeader = Data(header.utf8).base64URLEncodedString()
        let encodedPayload = Data(payload.utf8).base64URLEncodedString()
        let forgedJWS = "\(encodedHeader).\(encodedPayload).fakesignature"

        await #expect(throws: (any Error).self) {
            _ = try await AppStoreNotificationVerifier.shared.verifyEnvelope(forgedJWS)
        }
    }

    /// Garbage that isn't even a JWS at all.
    @Test func rejectsMalformedString() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await AppStoreNotificationVerifier.shared.verifyEnvelope("not-a-jws")
        }
    }

    /// Empty input.
    @Test func rejectsEmptyString() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await AppStoreNotificationVerifier.shared.verifyEnvelope("")
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
