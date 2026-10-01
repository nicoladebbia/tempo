import Foundation
import NIOConcurrencyHelpers
import Vapor

// MARK: - Test mode

//
// Local test server for simulator QA (`scripts/testenv.sh`). Turned on ONLY
// when TEMPO_TEST_MODE=1 AND the environment is not production. When on:
//   - /v1/test/* routes exist (test login without Sign in with Apple, AI
//     mode switch, captured pushes) — see TestModeController.
//   - Every outbound HTTP call goes through TestModeClient, which answers
//     Claude, USDA, Open Food Facts, DSLD, Instacart, OpenAI and Whoop with
//     fixtures and refuses any other host, so nothing leaves the Mac.
//   - APNs sends are captured (and delivered to the user's simulator with
//     `xcrun simctl push` when its UDID is known) instead of hitting Apple.
// Production never registers any of this: `isEnabled` is false there even
// if the flag is set by mistake.

enum TestMode {
    static func isEnabled(_ app: Application) -> Bool {
        guard app.environment != .production, runsLocally() else { return false }
        if let forced = app.storage[ForcedKey.self] {
            return forced
        }
        return Environment.get("TEMPO_TEST_MODE") == "1"
    }

    /// Per-app switch for unit tests: the env var is process-wide, so tests
    /// setting it would turn test mode on in suites running alongside.
    static func force(_ enabled: Bool, on app: Application) {
        app.storage[ForcedKey.self] = enabled
    }

    /// Vapor only knows it's in production from `--env`/`VAPOR_ENV`, which
    /// a deploy can forget. So also require a local database and no hosting
    /// platform: a stray TEMPO_TEST_MODE=1 on Railway must stay inert.
    static func runsLocally(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if env.keys.contains(where: { $0.hasPrefix("RAILWAY_") }) {
            return false
        }
        let loopback: Set = ["127.0.0.1", "localhost", "::1"]
        if let url = env["DATABASE_URL"] {
            guard let host = URL(string: url)?.host, loopback.contains(host) else { return false }
        }
        return loopback.contains(env["DB_HOST"] ?? "localhost")
    }

    private struct ForcedKey: StorageKey {
        typealias Value = Bool
    }

    /// Wires the fake HTTP client, the default AI mode and the test routes.
    /// Call after the rest of configure() (the real client must exist first:
    /// `--real-ai` passes Claude calls through to it).
    static func configure(_ app: Application) throws {
        guard isEnabled(app) else { return }
        let state = TestModeState()
        if let raw = Environment.get("TEMPO_TEST_AI"), let mode = AIMode(rawValue: raw) {
            state.aiMode = mode
        }
        app.testMode = state

        let real = app.client
        app.clients.use { app in
            TestModeClient(eventLoop: app.eventLoopGroup.next(), state: state, real: real, logger: app.logger)
        }

        app.middleware.use(TestModeFaultMiddleware(faults: state.faults))
        try app.grouped("v1", "test").register(collection: TestModeController())
        app.logger.warning("TEST MODE ON — fake outside services, /v1/test routes, pushes captured (AI: \(state.aiMode.rawValue))")
    }
}

// MARK: - AI modes

enum AIMode: String, Codable, Sendable, CaseIterable {
    /// Realistic fixture per feature.
    case fake
    /// HTTP 200 whose text is malformed/truncated JSON — exercises parse-failure paths.
    case broken
    /// HTTP 200 with an empty text block.
    case empty
    /// Realistic fixture after a long delay — exercises spinners and timeouts.
    case slow
    /// HTTP 529 "overloaded" from Anthropic.
    case error
    /// Pass through to the real Claude API (needs a real ANTHROPIC_API_KEY).
    case real
}

// MARK: - State

struct CapturedPush: Content, Sendable {
    let id: UUID
    let userID: String
    let createdAt: Date
    /// Full APNs JSON payload (aps + custom keys), ready for `simctl push`.
    let payload: String
    /// "delivered" (simctl push ran), "captured" (no simulator known) or "failed: …".
    var delivery: String
}

struct AICallRecord: Content, Sendable {
    let at: Date
    let feature: String
    let mode: String
    let status: Int
}

final class TestModeState: @unchecked Sendable {
    private let lock = NIOLock()
    let faults = FaultStore()
    private var _accessTokenTTL: TimeInterval?
    private var _aiMode: AIMode = .fake
    private var _slowSeconds: Double = 8
    private var _pushes: [CapturedPush] = []
    private var _aiCalls: [AICallRecord] = []
    private var _simulatorByUser: [String: String] = [:]

    var aiMode: AIMode {
        get { lock.withLock { _aiMode } }
        set { lock.withLock { _aiMode = newValue } }
    }

    /// Shorter access tokens, to exercise silent re-login (nil = the real 15 min).
    var accessTokenTTL: TimeInterval? {
        get { lock.withLock { _accessTokenTTL } }
        set { lock.withLock { _accessTokenTTL = newValue } }
    }

    var slowSeconds: Double {
        get { lock.withLock { _slowSeconds } }
        set { lock.withLock { _slowSeconds = newValue } }
    }

    func simulator(for userID: String) -> String? {
        lock.withLock { _simulatorByUser[userID] }
    }

    func setSimulator(_ udid: String?, for userID: String) {
        lock.withLock { _simulatorByUser[userID] = udid }
    }

    func record(_ push: CapturedPush) {
        lock.withLock {
            _pushes.append(push)
            if _pushes.count > 500 {
                _pushes.removeFirst(_pushes.count - 500)
            }
        }
    }

    func pushes(for userID: String?) -> [CapturedPush] {
        lock.withLock { userID.map { id in _pushes.filter { $0.userID == id } } ?? _pushes }
    }

    func clearPushes(for userID: String?) {
        lock.withLock {
            if let userID {
                _pushes.removeAll { $0.userID == userID }
            } else {
                _pushes.removeAll()
            }
        }
    }

    func record(_ call: AICallRecord) {
        lock.withLock {
            _aiCalls.append(call)
            if _aiCalls.count > 500 {
                _aiCalls.removeFirst(_aiCalls.count - 500)
            }
        }
    }

    var aiCalls: [AICallRecord] {
        lock.withLock { _aiCalls }
    }
}

extension Application {
    private struct TestModeKey: StorageKey {
        typealias Value = TestModeState
    }

    /// Non-nil only when test mode is on.
    var testMode: TestModeState? {
        get { storage[TestModeKey.self] }
        set { storage[TestModeKey.self] = newValue }
    }
}
