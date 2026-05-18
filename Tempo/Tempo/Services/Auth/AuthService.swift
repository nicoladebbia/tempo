//
// AuthService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - AuthState

enum AuthState: Equatable {
    case unauthenticated
    case authenticated(userID: String)
    case expired
}

// MARK: - AuthService

// Per BUILD_PLAN step 6.5 — Sign in with Apple → Backend → Keychain.

@Observable
@MainActor
final class AuthService: NSObject {
    private(set) var authState: AuthState = .unauthenticated

    private static let accessTokenKey = "tempo.jwt.access"
    private static let refreshTokenKey = "tempo.jwt.refresh"
    private static let userIDKey = "tempo.auth.userID"

    private var apiClient: APIClient?
    private var signInContinuation: CheckedContinuation<ASAuthorization, Error>?
    private var currentNonce: String?

    override init() {
        super.init()
        restoreSession()
    }

    /// Wire up the API client after ServiceContainer is constructed.
    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async throws {
        let nonce = generateNonce()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)

        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            self.signInContinuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
        try await completeAppleSignIn(authorization: authorization, nonce: nonce)
    }

    /// Generate a fresh nonce and its SHA-256 hash for a SIWA request. The
    /// caller (a `SignInWithAppleButton.onRequest` closure) sets the hash on
    /// the request; the raw nonce must be passed back to
    /// `completeAppleSignIn` so the backend can verify it against the token.
    func makeNonce() -> (raw: String, hashed: String) {
        let nonce = generateNonce()
        currentNonce = nonce
        return (nonce, sha256(nonce))
    }

    /// Exchange an already-obtained Apple authorization for backend tokens.
    /// Used by the native `SignInWithAppleButton` flow, which presents its
    /// own controller — so there is NO second `ASAuthorizationController`
    /// here. `signInWithApple()` (manual-controller flow) funnels through
    /// this same method after its continuation resolves.
    func completeAppleSignIn(authorization: ASAuthorization, nonce: String) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authCodeData, encoding: .utf8)
        else {
            throw AuthError.invalidCredential
        }

        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName

        // Send to backend
        guard let apiClient else {
            throw AuthError.notConfigured
        }

        struct AppleSignInBody: Encodable, Sendable {
            let identityToken: String
            let authorizationCode: String
            let firstName: String?
            let lastName: String?
            let nonce: String
        }

        let body = AppleSignInBody(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            firstName: firstName,
            lastName: lastName,
            nonce: nonce
        )

        let response: AuthTokenResponse = try await apiClient.request(
            .signInWithApple(),
            body: body
        )

        // Store tokens in Keychain
        try storeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)

        // Decode user ID from JWT (sub claim)
        let userID = decodeUserIDFromJWT(response.accessToken) ?? "unknown"
        try storeUserID(userID)
        authState = .authenticated(userID: userID)
    }

    // MARK: - Token Refresh

    func refreshToken() async throws -> String {
        guard case .authenticated = authState else {
            authState = .unauthenticated
            throw AuthError.notAuthenticated
        }

        guard let storedRefresh = loadRefreshToken() else {
            authState = .unauthenticated
            throw AuthError.notAuthenticated
        }

        guard let apiClient else {
            throw AuthError.notConfigured
        }

        struct RefreshBody: Encodable, Sendable {
            let refreshToken: String
        }

        let response: AuthTokenResponse = try await apiClient.request(
            .refreshToken(),
            body: RefreshBody(refreshToken: storedRefresh)
        )

        try storeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response.accessToken
    }

    // MARK: - Sign Out

    func signOut() async {
        // Notify backend (best effort)
        if let apiClient, let refreshTokenValue = loadRefreshToken() {
            struct LogoutBody: Encodable, Sendable {
                let refreshToken: String?
                let allDevices: Bool?
            }
            _ = try? await apiClient.request(
                APIEndpoint<EmptyResponse>.logout(),
                body: LogoutBody(refreshToken: refreshTokenValue, allDevices: false)
            )
        }

        try? KeychainService.deleteAll()
        authState = .unauthenticated
    }

    // MARK: - Account Deletion
    //
    // Apple-required (App Store Review Guideline 5.1.1(v)): an in-app
    // deletion path. Server soft-deletes the account (30-day recovery
    // window via /v1/auth/recover) and wipes owned per-user data
    // synchronously. On success we drop local tokens just like signOut.
    //
    // If the backend call fails we surface the error and leave the local
    // session intact — better to retry than to land the user in a state
    // where their server account still exists but the device thinks it
    // was deleted.

    func deleteAccount() async throws {
        guard let apiClient else {
            throw AuthError.notAuthenticated
        }
        _ = try await apiClient.request(
            APIEndpoint<AccountDeletionResponseDTO>.deleteAccount()
        )

        try? KeychainService.deleteAll()
        authState = .unauthenticated
    }

    // MARK: - Token Access

    var accessToken: String? {
        guard let data = KeychainService.load(key: Self.accessTokenKey) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private Helpers

    private func restoreSession() {
        guard let userIDData = KeychainService.load(key: Self.userIDKey),
              let userID = String(data: userIDData, encoding: .utf8),
              KeychainService.load(key: Self.accessTokenKey) != nil
        else {
            authState = .unauthenticated
            return
        }
        authState = .authenticated(userID: userID)
    }

    private func storeTokens(accessToken: String, refreshToken: String) throws {
        try KeychainService.save(key: Self.accessTokenKey, data: Data(accessToken.utf8))
        try KeychainService.save(key: Self.refreshTokenKey, data: Data(refreshToken.utf8))
    }

    private func storeUserID(_ userID: String) throws {
        try KeychainService.save(key: Self.userIDKey, data: Data(userID.utf8))
    }

    private func loadRefreshToken() -> String? {
        guard let data = KeychainService.load(key: Self.refreshTokenKey) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Decode `sub` claim from JWT payload (base64url-encoded middle segment).
    private func decodeUserIDFromJWT(_ jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else {
            return nil
        }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else {
            return nil
        }
        return sub
    }

    /// Generate a random nonce string.
    private func generateNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms {
                if remainingLength == 0 {
                    break
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    /// SHA-256 hash of a string, returned as hex.
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    enum AuthError: Error, LocalizedError {
        case notAuthenticated
        case notConfigured
        case invalidCredential
        case signInCancelled

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: "Not authenticated."
            case .notConfigured: "Auth service not configured."
            case .invalidCredential: "Invalid Apple credential."
            case .signInCancelled: "Sign in cancelled."
            }
        }
    }
}

// MARK: ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            signInContinuation?.resume(returning: authorization)
            signInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as? ASAuthorizationError)?.code == .canceled {
                signInContinuation?.resume(throwing: AuthError.signInCancelled)
            } else {
                signInContinuation?.resume(throwing: error)
            }
            signInContinuation = nil
        }
    }
}

// MARK: - AuthServiceTokenProvider

final class AuthServiceTokenProvider: AuthTokenProvider, @unchecked Sendable {
    private let authService: AuthService

    @MainActor
    init(authService: AuthService) {
        self.authService = authService
    }

    func accessToken() async -> String? {
        await MainActor.run { authService.accessToken }
    }

    func refreshToken() async throws -> String {
        try await authService.refreshToken()
    }
}
