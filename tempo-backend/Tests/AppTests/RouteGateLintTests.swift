import Testing
import Foundation

// MARK: - Route Gate Lint
//
// Asserts that every controller registered in routes.swift is hung off
// `protected` (which composes JWTAuthMiddleware + ToSGateMiddleware) UNLESS
// it's explicitly named in the carve-out list below.
//
// Why this test exists: when a future commit adds a new controller, the
// natural pattern is to `v1.grouped("xyz").register(...)`. If the author
// forgets to use `protected.grouped(...)` instead, the controller
// silently bypasses both the JWT auth AND the ToS gate — exactly the
// kind of regression LAUNCH_PUNCH_LIST.md §3.5 was set up to prevent.
//
// To add a new public/webhook controller intentionally, update
// `permittedV1Controllers` below. The test failure will tell you to.

struct RouteGateLintTests {

    /// Controllers that are intentionally registered outside `protected`.
    /// Every entry needs a one-line justification right next to it.
    static let permittedV1Controllers: Set<String> = [
        "AuthController",         // pre-auth: sign-in / refresh / logout
        "SubscriptionController", // Apple's V2 webhook — verified by JWS not JWT
        "WhoopWebhookController"  // Whoop's webhook — verified by HMAC not JWT
    ]

    @Test func everyControllerIsBehindProtectedOrPermitted() throws {
        let routesURL = try Self.routesSwiftURL()
        let source = try String(contentsOf: routesURL, encoding: .utf8)

        // Match a `register(collection: SomeController())` line and look at
        // the chain leading up to it. We pair each register call with the
        // group root (`protected` or `v1` or `auth`) that started its chain.

        let registerPattern = #/register\(collection:\s+(\w+)\(\)\)/#
        let registrations = source.matches(of: registerPattern)

        var seen: [(controller: String, rootGroup: String)] = []
        for match in registrations {
            let controller = String(match.1)
            let rootGroup = Self.findRootGroup(for: match.range, in: source) ?? "?"
            seen.append((controller, rootGroup))
        }

        #expect(!seen.isEmpty, "Found zero controllers in routes.swift — pattern probably broke")

        for (controller, root) in seen {
            if root == "protected" { continue }
            #expect(
                Self.permittedV1Controllers.contains(controller),
                """
                \(controller) is registered under `\(root)` (NOT `protected`).
                Either move it behind `protected.grouped(...)` so it gets JWT
                auth + ToS gate, or add it to permittedV1Controllers in this
                test with a one-line justification.
                """
            )
        }
    }

    /// Look backwards from a `.register(...)` call to find which top-level
    /// group identifier started the chain. Walks up through `.grouped(...)`
    /// calls. The first identifier that doesn't look like a method call is
    /// the root.
    private static func findRootGroup(for range: Range<String.Index>, in source: String) -> String? {
        // Take the 600 chars preceding the register call and search for the
        // most recent `try <root>.grouped(...)` or `try <root>.register(...)`
        // at the start of a chain.
        let lookback = source[..<range.lowerBound]
        let tail = lookback.suffix(600)
        let chainPattern = #/try\s+(\w+)\s*(?:\n\s*)?\.grouped/#
        if let lastMatch = tail.matches(of: chainPattern).last {
            return String(lastMatch.1)
        }
        // Also handle direct `try <root>.register(...)` with no .grouped() chain.
        let directPattern = #/try\s+(\w+)\s*(?:\n\s*)?\.register\(/#
        if let lastMatch = tail.matches(of: directPattern).last {
            return String(lastMatch.1)
        }
        return nil
    }

    private static func routesSwiftURL() throws -> URL {
        // Test binary lives in .build/.../debug; routes.swift is two-or-three
        // directories above under Sources/App. Walk up from the file we
        // know — the test source itself.
        let here = URL(fileURLWithPath: #filePath)
        // .../tempo-backend/Tests/AppTests/RouteGateLintTests.swift
        //    ^ go up 3 levels to tempo-backend/
        let backendRoot = here
            .deletingLastPathComponent()  // AppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // tempo-backend/
        return backendRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("App")
            .appendingPathComponent("routes.swift")
    }
}
