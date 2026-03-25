import Vapor

// MARK: - Request Auth Accessor
// Per VAPOR_PROJECT_STRUCTURE.md Section 8 — convenience accessor for authenticated user.

extension Request {
    var auth: AuthAccessor { AuthAccessor(request: self) }

    struct AuthAccessor {
        let request: Request

        func requireUserID() throws -> String {
            guard let auth = request.storage[AuthenticatedUserKey.self] else {
                throw Abort(.unauthorized, reason: "Not authenticated.")
            }
            return auth.userID
        }

        func requireAdmin() throws {
            guard let auth = request.storage[AuthenticatedUserKey.self], auth.isAdmin else {
                throw Abort(.forbidden, reason: "Admin access required.")
            }
        }

        var user: AuthenticatedUser? {
            request.storage[AuthenticatedUserKey.self]
        }

        var deviceID: String? {
            request.storage[AuthenticatedUserKey.self]?.deviceID
        }
    }
}
