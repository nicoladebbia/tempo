//
// AuthServiceExpiredSessionTests.swift
// Tempo
//
// A refresh token the server rejects ends the session: the app must stop
// claiming `.authenticated` (Settings then shows Sign in with Apple again)
// and drop only its own JWTs — Whoop and other keychain items stay.
//

@testable import Tempo
import XCTest

@MainActor
final class AuthServiceExpiredSessionTests: XCTestCase {
    private let otherKey = "tempo.test.unrelated"

    override func tearDown() {
        try? KeychainService.delete(key: otherKey)
        try? KeychainService.delete(key: "tempo.jwt.access")
        try? KeychainService.delete(key: "tempo.jwt.refresh")
        try? KeychainService.delete(key: "tempo.auth.userID")
        super.tearDown()
    }

    func testExpiredSessionFlipsStateAndClearsOnlyTempoTokens() throws {
        try KeychainService.save(key: "tempo.jwt.access", data: Data("old-access".utf8))
        try KeychainService.save(key: "tempo.jwt.refresh", data: Data("old-refresh".utf8))
        try KeychainService.save(key: "tempo.auth.userID", data: Data("usr_test".utf8))
        try KeychainService.save(key: otherKey, data: Data("whoop-like".utf8))

        let auth = AuthService()
        XCTAssertEqual(auth.authState, .authenticated(userID: "usr_test"), "restored from the keychain")

        auth.endExpiredSession()

        XCTAssertEqual(auth.authState, .expired)
        XCTAssertNil(KeychainService.load(key: "tempo.jwt.access"))
        XCTAssertNil(KeychainService.load(key: "tempo.jwt.refresh"))
        XCTAssertNil(KeychainService.load(key: "tempo.auth.userID"))
        XCTAssertNotNil(KeychainService.load(key: otherKey), "unrelated keychain items survive")
        XCTAssertNil(AuthService().accessToken, "a relaunch starts signed out")
    }
}
