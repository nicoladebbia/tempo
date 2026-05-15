import Vapor
import Fluent

// MARK: - Whoop OAuth Service
// Per INTEGRATION_SPECS.md Section 1.1 — Whoop OAuth2 token exchange and refresh.

struct WhoopOAuthService {

    // MARK: - Constants

    static let authorizeURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    static let revokeURL = "https://api.prod.whoop.com/oauth/oauth2/revoke"
    static let profileURL = "https://api.prod.whoop.com/developer/v1/user/profile/basic"

    static let scopes = "read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline"

    private static var clientID: String {
        Environment.get("WHOOP_CLIENT_ID") ?? ""
    }

    private static var clientSecret: String {
        Environment.get("WHOOP_CLIENT_SECRET") ?? ""
    }

    private static var redirectURI: String {
        // Default to the Railway public URL because api.tempo.app doesn't
        // exist yet (LAUNCH_PUNCH_LIST.md §3.11 — custom domain is deferred).
        // Overridable via env so swapping hosts doesn't require a code change.
        Environment.get("WHOOP_REDIRECT_URI")
            ?? "https://tempo-backend-production-39dc.up.railway.app/v1/integrations/whoop/callback"
    }

    // MARK: - Build Authorization URL

    /// Constructs the Whoop OAuth authorization URL with CSRF state.
    static func buildAuthorizationURL(state: String) -> String {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!.absoluteString
    }

    // MARK: - Exchange Code for Tokens

    /// Exchange authorization code for access + refresh tokens.
    /// Per INTEGRATION_SPECS.md Section 1.1 — POST to token endpoint.
    static func exchangeCode(
        _ code: String,
        on req: Request
    ) async throws -> TokenResponse {
        let response = try await req.client.post(URI(string: tokenURL)) { clientReq in
            try clientReq.content.encode(
                TokenRequest(
                    grantType: "authorization_code",
                    code: code,
                    clientId: clientID,
                    clientSecret: clientSecret,
                    redirectUri: redirectURI
                ),
                as: .urlEncodedForm
            )
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Whoop token exchange failed: \(response.status)")
        }

        return try response.content.decode(TokenResponse.self)
    }

    // MARK: - Refresh Token

    /// Refresh an expired access token.
    static func refreshAccessToken(
        refreshToken: String,
        on req: Request
    ) async throws -> TokenResponse {
        let response = try await req.client.post(URI(string: tokenURL)) { clientReq in
            try clientReq.content.encode(
                RefreshRequest(
                    grantType: "refresh_token",
                    refreshToken: refreshToken,
                    clientId: clientID,
                    clientSecret: clientSecret
                ),
                as: .urlEncodedForm
            )
        }

        guard response.status == .ok else {
            throw Abort(.unauthorized, reason: "Whoop token refresh failed.")
        }

        return try response.content.decode(TokenResponse.self)
    }

    // MARK: - Revoke Token

    /// Revoke a Whoop token (best effort).
    static func revokeToken(
        _ token: String,
        on req: Request
    ) async throws {
        _ = try? await req.client.post(URI(string: revokeURL)) { clientReq in
            try clientReq.content.encode(
                RevokeRequest(
                    token: token,
                    clientId: clientID,
                    clientSecret: clientSecret
                ),
                as: .urlEncodedForm
            )
        }
    }

    // MARK: - Fetch Whoop User Profile

    /// Get the Whoop user ID from the profile endpoint.
    static func fetchUserProfile(
        accessToken: String,
        on req: Request
    ) async throws -> String? {
        let response = try await req.client.get(URI(string: profileURL)) { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
        }

        guard response.status == .ok else { return nil }

        struct WhoopProfile: Content {
            let userId: Int

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }

        let profile = try? response.content.decode(WhoopProfile.self)
        return profile.map { String($0.userId) }
    }

    // MARK: - DTOs

    struct TokenRequest: Content {
        let grantType: String
        let code: String?
        let clientId: String
        let clientSecret: String
        let redirectUri: String?

        enum CodingKeys: String, CodingKey {
            case grantType = "grant_type"
            case code
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case redirectUri = "redirect_uri"
        }

        init(grantType: String, code: String, clientId: String, clientSecret: String, redirectUri: String) {
            self.grantType = grantType
            self.code = code
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.redirectUri = redirectUri
        }
    }

    struct RefreshRequest: Content {
        let grantType: String
        let refreshToken: String
        let clientId: String
        let clientSecret: String

        enum CodingKeys: String, CodingKey {
            case grantType = "grant_type"
            case refreshToken = "refresh_token"
            case clientId = "client_id"
            case clientSecret = "client_secret"
        }
    }

    struct RevokeRequest: Content {
        let token: String
        let clientId: String
        let clientSecret: String

        enum CodingKeys: String, CodingKey {
            case token
            case clientId = "client_id"
            case clientSecret = "client_secret"
        }
    }

    struct TokenResponse: Content {
        let accessToken: String
        let refreshToken: String
        let tokenType: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }
}
