import Foundation
import NIOConcurrencyHelpers
import Vapor

// MARK: - Fault injection

//
// "Break the server on purpose": a rule makes requests whose path starts with
// `pathPrefix` (and optionally match a method / test user) fail the way real
// networks and servers fail, so the app's error, retry, spinner and sign-in
// paths can be exercised on the simulator. Rules apply to the app's API only,
// never to /v1/test itself.
//
//   scripts/testenv.sh fault add /v1/nutrition error 500
//   scripts/testenv.sh fault add /v1/insights slow 10 --count 1
//   scripts/testenv.sh fault list | clear

enum FaultKind: String, Codable, Sendable, CaseIterable {
    /// HTTP `status` (default 500) with the server's normal error body.
    case error
    /// Waits `delaySeconds` (default 8), then answers normally.
    case slow
    /// 401 "Invalid or expired access token." — what an expired session gets.
    case logout
    /// 200 with a truncated JSON body.
    case garbage
    /// 200 with an empty body.
    case empty
    /// Hangs for 75 s (past the app's request timeout), then 504.
    case timeout
}

struct FaultRule: Content, Sendable {
    var id: UUID?
    let pathPrefix: String
    var method: String?
    let kind: FaultKind
    var status: Int?
    var delaySeconds: Double?
    /// Fail only the next N matching requests; nil = until cleared.
    var remaining: Int?
    /// Only this user's requests (from their bearer token); nil = everyone.
    var userId: String?
    /// How many requests this rule has broken so far.
    var hits: Int?
}

final class FaultStore: @unchecked Sendable {
    private let lock = NIOLock()
    private var rules: [FaultRule] = []

    var all: [FaultRule] {
        lock.withLock { rules }
    }

    func add(_ rule: FaultRule) -> FaultRule {
        var rule = rule
        rule.id = UUID()
        rule.hits = 0
        lock.withLock { rules.append(rule) }
        return rule
    }

    func clear() {
        lock.withLock { rules.removeAll() }
    }

    func remove(id: UUID) {
        lock.withLock { rules.removeAll { $0.id == id } }
    }

    /// First matching rule, counted as used (a rule whose count runs out is removed).
    func take(path: String, method: String, userID: String?) -> FaultRule? {
        lock.withLock {
            guard let index = rules.firstIndex(where: { rule in
                path.hasPrefix(rule.pathPrefix)
                    && (rule.method.map { $0.uppercased() == method } ?? true)
                    && (rule.userId.map { $0 == userID } ?? true)
            }) else {
                return nil
            }
            rules[index].hits = (rules[index].hits ?? 0) + 1
            let rule = rules[index]
            if let remaining = rule.remaining {
                if remaining <= 1 {
                    rules.remove(at: index)
                } else {
                    rules[index].remaining = remaining - 1
                }
            }
            return rule
        }
    }
}

struct TestModeFaultMiddleware: AsyncMiddleware {
    let faults: FaultStore

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let path = request.url.path
        guard !path.hasPrefix("/v1/test"), !faults.all.isEmpty else {
            return try await next.respond(to: request)
        }
        // Unverified on purpose: only used to scope a rule to one test user.
        let userID = request.headers.bearerAuthorization.flatMap { Self.subject(ofJWT: $0.token) }
        guard let rule = faults.take(path: path, method: request.method.rawValue, userID: userID) else {
            return try await next.respond(to: request)
        }
        request.logger.info("[test-mode] fault \(rule.kind.rawValue) on \(request.method.rawValue) \(path)")
        switch rule.kind {
        case .slow:
            try await Task.sleep(nanoseconds: UInt64((rule.delaySeconds ?? 8) * 1_000_000_000))
            return try await next.respond(to: request)
        case .error:
            let status = HTTPResponseStatus(statusCode: rule.status ?? 500)
            return Self.json(#"{"error":true,"reason":"Injected fault (test mode): \#(status.code)"}"#, status: status)
        case .logout:
            return Self.json(#"{"error":true,"reason":"Invalid or expired access token."}"#, status: .unauthorized)
        case .garbage:
            return Self.json(#"{"ok":true,"data":{"unexpect"#, status: .ok)
        case .empty:
            return Self.json("", status: .ok)
        case .timeout:
            try await Task.sleep(nanoseconds: 75 * 1_000_000_000)
            return Self.json(#"{"error":true,"reason":"Gateway timeout (test mode)"}"#, status: .gatewayTimeout)
        }
    }

    static func json(_ body: String, status: HTTPResponseStatus) -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .json
        return Response(status: status, headers: headers, body: .init(string: body))
    }

    /// `sub` claim of a JWT without verifying it.
    static func subject(ofJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        return json["sub"] as? String
    }
}
