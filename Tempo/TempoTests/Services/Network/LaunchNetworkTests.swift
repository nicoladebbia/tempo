//
// LaunchNetworkTests.swift
// Tempo
//
// Launch used to send a burst of requests with an expired Tempo token (each one 401) and to ask
// for the same data several times at once. These pin the fixes: refresh before sending, share
// identical in-flight GETs, and share the WHOOP access token once per new token.
//

@testable import Tempo
import XCTest

private func jwt(exp: TimeInterval?) -> String {
    func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    var claims: [String: Any] = ["sub": "user-1"]
    if let exp {
        claims["exp"] = exp
    }
    let payload = try! JSONSerialization.data(withJSONObject: claims)
    return "\(b64url(Data(#"{"alg":"ES256"}"#.utf8))).\(b64url(payload)).sig"
}

// MARK: - FakeTokenProvider

private final class FakeTokenProvider: AuthTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private let fresh: String
    private var _refreshes = 0
    var refreshes: Int {
        lock.withLock { _refreshes }
    }

    init(token: String?, fresh: String) {
        self.token = token
        self.fresh = fresh
    }

    func accessToken() async -> String? {
        lock.withLock { token }
    }

    func refreshToken() async throws -> String {
        lock.withLock {
            _refreshes += 1
            token = fresh
            return fresh
        }
    }
}

// MARK: - Ping

private struct Ping: Decodable, Sendable, Equatable { let ok: Bool }

// MARK: - JWTExpiryTests

final class JWTExpiryTests: XCTestCase {
    func testReadsExpFromABase64URLPayload() {
        let exp: TimeInterval = 1_800_000_123
        XCTAssertEqual(JWTExpiry.expiry(of: jwt(exp: exp))?.timeIntervalSince1970, exp)
    }

    func testTokenWithoutReadableExpCountsAsValid() {
        XCTAssertNil(JWTExpiry.expiry(of: jwt(exp: nil)))
        XCTAssertNil(JWTExpiry.expiry(of: "not-a-jwt"))
        XCTAssertNil(JWTExpiry.expiry(of: "a.%%%.c"))
    }

    func testExpiredOrAboutToExpireTokenIsNotHandedOut() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = AuthInterceptor(tokenProvider: FakeTokenProvider(token: jwt(exp: now.timeIntervalSince1970 - 10), fresh: "x"))
        let nearlyExpired = AuthInterceptor(tokenProvider: FakeTokenProvider(token: jwt(exp: now.timeIntervalSince1970 + 30), fresh: "x"))
        let fresh = jwt(exp: now.timeIntervalSince1970 + 900)
        let valid = AuthInterceptor(tokenProvider: FakeTokenProvider(token: fresh, fresh: "x"))
        let opaque = AuthInterceptor(tokenProvider: FakeTokenProvider(token: "opaque", fresh: "x"))

        let a = try await expired.validToken(now: now)
        let b = try await nearlyExpired.validToken(now: now)
        let c = try await valid.validToken(now: now)
        let d = try await opaque.validToken(now: now)
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertEqual(c, fresh)
        XCTAssertEqual(d, "opaque")
    }
}

// MARK: - APIClientLaunchTests

final class APIClientLaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testExpiredTokenIsRefreshedOnceBeforeSendingSoNothingComesBack401() async throws {
        let fresh = jwt(exp: Date().timeIntervalSince1970 + 3600)
        let provider = FakeTokenProvider(token: jwt(exp: Date().timeIntervalSince1970 - 60), fresh: fresh)
        MockURLProtocol.setHandler { req in
            let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
            return auth == "Bearer \(fresh)"
                ? .init(statusCode: 200, data: Data(#"{"ok":true,"data":{"ok":true}}"#.utf8))
                : .init(statusCode: 401, data: Data(#"{"error":true}"#.utf8))
        }
        let client = try APIClient(
            baseURL: XCTUnwrap(URL(string: "https://example.test")),
            session: MockURLProtocol.makeSession(),
            authInterceptor: AuthInterceptor(tokenProvider: provider)
        )

        async let a: Ping = client.request(APIEndpoint<Ping>(path: "/v1/a", method: .post))
        async let b: Ping = client.request(APIEndpoint<Ping>(path: "/v1/b", method: .post))
        let results = try await [a, b]

        XCTAssertEqual(results, [Ping(ok: true), Ping(ok: true)])
        XCTAssertEqual(provider.refreshes, 1, "one refresh shared by both requests")
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2, "no request went out with the expired token")
    }

    func testOverlappingIdenticalGetsShareOneNetworkCall() async throws {
        MockURLProtocol.setHandler { _ in
            Thread.sleep(forTimeInterval: 0.3) // keep the first call on the wire while the others arrive
            return .init(statusCode: 200, data: Data(#"{"ok":true,"data":{"ok":true}}"#.utf8))
        }
        let client = try APIClient(baseURL: XCTUnwrap(URL(string: "https://example.test")), session: MockURLProtocol.makeSession())
        let endpoint = APIEndpoint<Ping>(path: "/v1/same", method: .get, requiresAuth: false)

        async let a: Ping = client.request(endpoint)
        async let b: Ping = client.request(endpoint)
        async let c: Ping = client.request(endpoint)
        let results = try await [a, b, c]

        XCTAssertEqual(results, Array(repeating: Ping(ok: true), count: 3))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)

        // Once finished, the next GET goes out again (no stale caching).
        _ = try await client.request(endpoint)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
    }

    func testAGetStartedAfterAWriteNeverJoinsAnOlderGet() async throws {
        MockURLProtocol.setHandler { req in
            if req.httpMethod == "GET" { Thread.sleep(forTimeInterval: 0.5) }
            return .init(statusCode: 200, data: Data(#"{"ok":true,"data":{"ok":true}}"#.utf8))
        }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: MockURLProtocol.makeSession())
        let read = APIEndpoint<Ping>(path: "/v1/meals", method: .get, requiresAuth: false)
        let write = APIEndpoint<Ping>(path: "/v1/meals", method: .post, requiresAuth: false)

        let before = Task { try await client.request(read) }
        try await Task.sleep(for: .milliseconds(150)) // the first GET is on the wire
        _ = try await client.request(write)
        _ = try await client.request(read) // must see the write: its own request
        _ = try await before.value

        let gets = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "GET" }
        XCTAssertEqual(gets.count, 2)
    }

    func testABookkeepingWriteDoesNotSplitOverlappingGets() async throws {
        MockURLProtocol.setHandler { req in
            if req.httpMethod == "GET" { Thread.sleep(forTimeInterval: 0.5) }
            return .init(statusCode: 200, data: Data(#"{"ok":true,"data":{"ok":true}}"#.utf8))
        }
        let client = try APIClient(baseURL: XCTUnwrap(URL(string: "https://example.test")), session: MockURLProtocol.makeSession())
        let read = APIEndpoint<Ping>(path: "/v1/plans/latest", method: .get, requiresAuth: false)
        let register = APIEndpoint<Ping>(path: "/v1/devices/register", method: .post, requiresAuth: false, changesReads: false)

        let before = Task { try await client.request(read) }
        try await Task.sleep(for: .milliseconds(150)) // the first GET is on the wire
        // The mock serves one request at a time, so the POST stays pending while the GET sleeps:
        // start it, let it pass the client, then read while both are still open.
        let write = Task { try await client.request(register) }
        try await Task.sleep(for: .milliseconds(50))
        _ = try await client.request(read) // nothing it reads changed: joins the first GET
        _ = try await before.value
        _ = try await write.value

        let gets = MockURLProtocol.recordedRequests.filter { $0.httpMethod == "GET" }
        XCTAssertEqual(gets.count, 1)
    }

    func testPushTokenRegisterIsABookkeepingWrite() {
        XCTAssertFalse(APIEndpoint<DeviceTokenRegisterResponseDTO>.registerDeviceToken().changesReads)
        XCTAssertTrue(APIEndpoint<WhoopTokenShareResponse>.whoopShareToken().changesReads,
                      "a WHOOP share turns the coach's 404 into data")
    }

    func testPostsAreNeverShared() async throws {
        MockURLProtocol.setHandler { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return .init(statusCode: 200, data: Data(#"{"ok":true,"data":{"ok":true}}"#.utf8))
        }
        let client = try APIClient(baseURL: XCTUnwrap(URL(string: "https://example.test")), session: MockURLProtocol.makeSession())
        let endpoint = APIEndpoint<Ping>(path: "/v1/write", method: .post, requiresAuth: false)
        async let a: Ping = client.request(endpoint)
        async let b: Ping = client.request(endpoint)
        _ = try await [a, b]
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
    }
}

// MARK: - WhoopTokenSharerTests

final class WhoopTokenSharerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _sent: [WhoopTokenShareRequest] = []
        private var _unlinks = 0
        var fail = false
        var sent: [WhoopTokenShareRequest] {
            lock.withLock { _sent }
        }

        var unlinks: Int {
            lock.withLock { _unlinks }
        }

        func record(_ r: WhoopTokenShareRequest) throws -> WhoopTokenShareResponse {
            try lock.withLock {
                _sent.append(r)
                if fail {
                    throw APIError.timeout
                }
                return WhoopTokenShareResponse(linked: true, managedBy: "phone", expiresAt: r.expiresAt)
            }
        }

        func unlink() {
            lock.withLock { _unlinks += 1 }
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(_ rec: Recorder) -> WhoopTokenSharer {
        let n = now
        return WhoopTokenSharer(send: { try rec.record($0) }, unlink: { rec.unlink() }, now: { n })
    }

    func testSendsEachNewTokenOnceAndOnlyTheAccessToken() async {
        let rec = Recorder()
        let sharer = make(rec)
        let ok1 = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        let again = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        let ok2 = await sharer.share(accessToken: "t2", expiresAt: now.addingTimeInterval(3600))
        XCTAssertTrue(ok1)
        XCTAssertFalse(again, "same token is not re-sent")
        XCTAssertTrue(ok2)
        XCTAssertEqual(rec.sent.map(\.accessToken), ["t1", "t2"])
    }

    func testExpiredOrEmptyTokensAreNotSent() async {
        let rec = Recorder()
        let sharer = make(rec)
        let expired = await sharer.share(accessToken: "old", expiresAt: now.addingTimeInterval(-1))
        let empty = await sharer.share(accessToken: "", expiresAt: now.addingTimeInterval(3600))
        XCTAssertFalse(expired)
        XCTAssertFalse(empty)
        XCTAssertTrue(rec.sent.isEmpty)
    }

    func testAFailedShareIsRetriedOnTheNextCall() async {
        let rec = Recorder()
        rec.fail = true
        let sharer = make(rec)
        let first = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        rec.fail = false
        let second = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertEqual(rec.sent.count, 2)
    }

    func testEachSuccessfulShareAnnouncesWhoopAccess() async {
        let rec = Recorder()
        let sharer = make(rec)
        let counter = NotificationCounter(.tempoWhoopAccessShared)
        rec.fail = true
        _ = await sharer.share(accessToken: "t0", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(counter.count, 0, "a failed share announces nothing")
        rec.fail = false
        _ = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        _ = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        _ = await sharer.share(accessToken: "t2", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(counter.count, 2, "one per token the server accepted; a skipped repeat announces nothing")
    }

    func testUnlinkForgetsTheLastTokenSoAReconnectSharesAgain() async {
        let rec = Recorder()
        let sharer = make(rec)
        _ = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        await sharer.unlink()
        let again = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        XCTAssertEqual(rec.unlinks, 1)
        XCTAssertTrue(again)
    }

    func testAShareThatRacesAnUnlinkDoesNotCountAsCurrent() async {
        let rec = Recorder()
        let n = now
        let sharer = WhoopTokenSharer(
            send: { req in
                try await Task.sleep(for: .milliseconds(200))
                return try rec.record(req)
            },
            unlink: { rec.unlink() },
            now: { n }
        )
        let expiry = n.addingTimeInterval(3600)
        async let shared = sharer.share(accessToken: "t1", expiresAt: expiry)
        try? await Task.sleep(for: .milliseconds(50))
        await sharer.unlink() // waits for the in-flight PUT, then DELETEs
        let result = await shared
        XCTAssertFalse(result, "a share overtaken by an unlink is not current")
        XCTAssertEqual(rec.unlinks, 1)
        // After the unlink the same token can be shared again on reconnect.
        let again = await sharer.share(accessToken: "t1", expiresAt: now.addingTimeInterval(3600))
        XCTAssertTrue(again)
    }

    func testRequestEncodesSnakeCaseKeysTheServerReads() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(WhoopTokenShareRequest(accessToken: "a", expiresAt: now))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["access_token", "expires_at"])
    }
}

// MARK: - NotificationCounter

/// Counts posts of one notification (posted synchronously, so no waiting needed).
private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var token: NSObjectProtocol?
    var count: Int { lock.withLock { _count } }

    init(_ name: Notification.Name) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            lock.withLock { _count += 1 }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

// MARK: - ColdLaunchActivationTests

final class ColdLaunchActivationTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyTheLaunchActivationIsSkipped() {
        var cold = ColdLaunchActivation(launchedAt: launch)
        XCTAssertTrue(cold.isColdLaunch(now: launch.addingTimeInterval(0.5)))
        XCTAssertFalse(cold.isColdLaunch(now: launch.addingTimeInterval(1)), "a second activation is a real return")
    }

    func testAFirstActivationLongAfterLaunchIsARealReturn() {
        var cold = ColdLaunchActivation(launchedAt: launch)
        XCTAssertFalse(cold.isColdLaunch(now: launch.addingTimeInterval(120)))
    }
}
