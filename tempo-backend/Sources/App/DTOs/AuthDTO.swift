import Vapor

// MARK: - Auth DTOs
// Per BACKEND_API.md Section 2 — Authentication response/request DTOs.

struct AuthTokenResponse: Content {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    init(accessToken: String, refreshToken: String, expiresIn: Int = 900) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = "Bearer"
        self.expiresIn = expiresIn
    }
}

struct AppleSignInRequest: Content, Validatable {
    let identityToken: String
    let authorizationCode: String
    let firstName: String?
    let lastName: String?
    let nonce: String

    static func validations(_ validations: inout Validations) {
        validations.add("identityToken", as: String.self, is: !.empty)
        validations.add("authorizationCode", as: String.self, is: !.empty)
        validations.add("nonce", as: String.self, is: !.empty)
    }
}

struct RefreshTokenRequest: Content, Validatable {
    let refreshToken: String

    static func validations(_ validations: inout Validations) {
        validations.add("refreshToken", as: String.self, is: !.empty)
    }
}

struct LogoutRequest: Content {
    let refreshToken: String?
    let allDevices: Bool?
}
