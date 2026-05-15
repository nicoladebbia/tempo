import Fluent
import Vapor

// MARK: - ToS Gate Middleware
//
// Per LAUNCH_PUNCH_LIST.md §3.5: every active user must have accepted the
// Terms of Service + Privacy Policy. This middleware refuses any
// authenticated request whose user has `tos_accepted_at IS NULL` by
// returning 451 Unavailable for Legal Reasons.
//
// Exempted routes (must always be reachable so the user can transition
// from "signed-in but not accepted" to "accepted"):
//   - GET  /v1/user/me           — iOS reads the gate state from here
//   - POST /v1/user/accept-tos   — the acceptance write itself
//   - DELETE /v1/user/me         — Apple-required deletion path
//   - POST /v1/auth/logout       — log out without accepting
//
// All other protected routes (sync, AI, nutrition, recovery, training,
// Whoop, social) fall behind the gate.
//
// JWTAuthMiddleware MUST run first; this middleware reads
// `req.auth.userID` to know whom to check.

struct ToSGateMiddleware: AsyncMiddleware {

    /// Path suffixes that bypass the gate. Matched against the *full* path
    /// after Vapor's routing has already pinned the request to a group
    /// (so paths look like "/v1/user/me", "/v1/user/accept-tos", etc.).
    static let exemptPaths: Set<String> = [
        "/v1/user/me",
        "/v1/user/accept-tos",
        "/v1/auth/logout"
    ]

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Always allow the exempt paths.
        let path = request.url.path
        if Self.exemptPaths.contains(path) {
            return try await next.respond(to: request)
        }

        // Honor HTTP method on DELETE /v1/user/me too.
        if path == "/v1/user/me", request.method == .DELETE {
            return try await next.respond(to: request)
        }

        let userID: String
        do {
            userID = try request.auth.requireUserID()
        } catch {
            // Not authenticated — let JWTAuthMiddleware's own 401 surface.
            return try await next.respond(to: request)
        }

        guard let user = try await User.find(userID, on: request.db) else {
            throw Abort(.unauthorized, reason: "User not found.")
        }

        if user.tosAcceptedAt == nil {
            throw Abort(
                .unavailableForLegalReasons,
                reason: "Terms of Service acceptance required. POST /v1/user/accept-tos to continue.",
                identifier: "tos_acceptance_required"
            )
        }

        return try await next.respond(to: request)
    }
}
