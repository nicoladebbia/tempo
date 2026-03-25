import Vapor

// MARK: - Tempo Error Codes
// Per BACKEND_API.md — Centralized error definitions matching error codes.

enum TempoError {
    // Auth (1xxx)
    static let tokenExpired = Abort(.unauthorized, reason: "Access token has expired.", identifier: "1001")
    static let invalidIdentityToken = Abort(.badRequest, reason: "Invalid identity token.", identifier: "1002")
    static let nonceMismatch = Abort(.badRequest, reason: "Nonce mismatch.", identifier: "1003")
    static let authCodeInvalid = Abort(.badRequest, reason: "Authorization code invalid.", identifier: "1004")
    static let signatureVerificationFailed = Abort(.unauthorized, reason: "Signature verification failed.", identifier: "1005")
    static let identityTokenExpired = Abort(.unauthorized, reason: "Identity token expired.", identifier: "1006")
    static let accountInRecoveryWindow = Abort(.conflict, reason: "Account in recovery window. Use POST /v1/auth/recover.", identifier: "1007")
    static let refreshTokenMalformed = Abort(.badRequest, reason: "Missing or malformed refresh token.", identifier: "1008")
    static let refreshTokenExpired = Abort(.unauthorized, reason: "Refresh token expired.", identifier: "1009")
    static let refreshTokenRevoked = Abort(.unauthorized, reason: "Refresh token revoked or not found.", identifier: "1010")
    static let refreshTokenReplay = Abort(.unauthorized, reason: "Replay detected. All sessions invalidated.", identifier: "1011")
    static let deviceIDMismatch = Abort(.unauthorized, reason: "Device ID mismatch.", identifier: "1012")
    static let noDeletedAccount = Abort(.notFound, reason: "No deleted account found.", identifier: "1013")
    static let recoveryWindowExpired = Abort(.gone, reason: "Recovery window expired.", identifier: "1014")
    static let adminRequired = Abort(.forbidden, reason: "Admin scope required.", identifier: "1015")

    // Validation (2xxx)
    static let validationFailed = Abort(.badRequest, reason: "Validation failed.", identifier: "2001")
    static let usernameTaken = Abort(.conflict, reason: "Username already taken.", identifier: "2002")
    static let userNotFound = Abort(.notFound, reason: "User not found.", identifier: "2006")

    // Integration (3xxx)
    static let whoopAlreadyConnected = Abort(.conflict, reason: "Whoop already connected.", identifier: "3001")
    static let whoopNotConnected = Abort(.notFound, reason: "Whoop not connected.", identifier: "3005")
    static let syncInProgress = Abort(.conflict, reason: "Sync already in progress.", identifier: "3006")
    static let invalidWebhookSignature = Abort(.unauthorized, reason: "Invalid webhook signature.", identifier: "3010")

    // Arena (4xxx)
    static let challengeStartMustBeFuture = Abort(.badRequest, reason: "Start date must be in the future.", identifier: "4013")
    static let inviteTargetNotFriend = Abort(.badRequest, reason: "Invite target is not a friend.", identifier: "4014")
    static let tooManyActiveChallenges = Abort(.tooManyRequests, reason: "Too many active challenges.", identifier: "4015")
    static let challengeNotFound = Abort(.notFound, reason: "Challenge not found.", identifier: "4017")
    static let alreadyParticipating = Abort(.conflict, reason: "Already participating.", identifier: "4018")
    static let challengeFull = Abort(.conflict, reason: "Challenge is full.", identifier: "4019")
    static let challengeEnded = Abort(.conflict, reason: "Challenge has ended.", identifier: "4020")
    static let notAParticipant = Abort(.conflict, reason: "Not a participant.", identifier: "4021")

    // Server (5xxx)
    static let rateLimitExceeded = Abort(.tooManyRequests, reason: "Rate limit exceeded.", identifier: "5001")
}
