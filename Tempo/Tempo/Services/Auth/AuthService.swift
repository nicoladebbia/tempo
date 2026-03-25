import Foundation

enum AuthState: Sendable, Equatable {
    case unauthenticated
    case authenticated(userID: UUID)
    case expired
}

@Observable
@MainActor
final class AuthService {

    private(set) var authState: AuthState = .unauthenticated

    private static let accessTokenKey = "tempo.jwt.access"
    private static let refreshTokenKey = "tempo.jwt.refresh"
    private static let userIDKey = "tempo.auth.userID"

    init() {
        restoreSession()
    }

    // MARK: - Public API

    func signInWithApple() async throws {
        // Placeholder — real implementation in Phase 6 (step 6.5)
        let mockAccessToken = "mock_access_token_\(UUID().uuidString)"
        let mockRefreshToken = "mock_refresh_token_\(UUID().uuidString)"
        let mockUserID = UUID()

        try storeTokens(accessToken: mockAccessToken, refreshToken: mockRefreshToken)
        try storeUserID(mockUserID)
        authState = .authenticated(userID: mockUserID)
    }

    func refreshToken() async throws -> String {
        // Placeholder — real implementation in Phase 6 (step 6.3)
        guard case .authenticated = authState else {
            authState = .unauthenticated
            throw AuthError.notAuthenticated
        }

        let newAccessToken = "refreshed_access_token_\(UUID().uuidString)"
        try KeychainService.save(
            key: Self.accessTokenKey,
            data: Data(newAccessToken.utf8)
        )
        return newAccessToken
    }

    func signOut() {
        try? KeychainService.deleteAll()
        authState = .unauthenticated
    }

    // MARK: - Token Access

    var accessToken: String? {
        guard let data = KeychainService.load(key: Self.accessTokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private

    private func restoreSession() {
        guard let userIDData = KeychainService.load(key: Self.userIDKey),
              let userIDString = String(data: userIDData, encoding: .utf8),
              let userID = UUID(uuidString: userIDString),
              KeychainService.load(key: Self.accessTokenKey) != nil else {
            authState = .unauthenticated
            return
        }
        authState = .authenticated(userID: userID)
    }

    private func storeTokens(accessToken: String, refreshToken: String) throws {
        try KeychainService.save(key: Self.accessTokenKey, data: Data(accessToken.utf8))
        try KeychainService.save(key: Self.refreshTokenKey, data: Data(refreshToken.utf8))
    }

    private func storeUserID(_ userID: UUID) throws {
        try KeychainService.save(key: Self.userIDKey, data: Data(userID.uuidString.utf8))
    }

    enum AuthError: Error {
        case notAuthenticated
    }
}

// MARK: - AuthTokenProvider Conformance

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
