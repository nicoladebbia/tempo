//
// WhoopService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AuthenticationServices
import Foundation
import os

// MARK: - WhoopService

// Connects directly to Whoop's Developer API v2 via OAuth2.
// User must register at developer.whoop.com and enter client_id/secret.

@Observable
final class WhoopService: NSObject, WhoopServiceProtocol, @unchecked Sendable {
    private(set) var connectionState: WhoopConnectionState = .disconnected
    private(set) var isDemoMode: Bool = false
    private(set) var lastSyncDate: Date?
    private(set) var profileFirstName: String?
    private(set) var profileLastName: String?

    private let logger = Logger(subsystem: "app.tempo", category: "WhoopService")
    private let mockService = MockWhoopService()
    private let session = URLSession.shared
    private var authSession: ASWebAuthenticationSession?

    // MARK: - OAuth Constants

    private enum OAuth {
        static let authURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
        static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!
        static let apiBase = URL(string: "https://api.prod.whoop.com/developer/v2")!
        static let callbackScheme = "tempo"
        static let redirectURI = "tempo://whoop/callback"
        /// `offline` is REQUIRED to receive a refresh token. Without it, Whoop
        /// returns only a 1-hour access token and the connection breaks daily.
        static let scopes = "offline read:recovery read:cycles read:sleep read:workout read:profile read:body_measurement"
        // Registered at developer.whoop.com
        static let defaultClientID = "9f8c50af-76a4-4fad-8e18-6fbf96f92c16"
        static let defaultClientSecret = "44f8cdc9f57990ad94e0c23f95b4b426ef9b4b19f440c3251ad87af83d0f6fcd"
    }

    // MARK: - Keychain Keys

    private enum Keys {
        static let clientID = "whoop.client_id"
        static let clientSecret = "whoop.client_secret"
        /// Atomic JSON bundle holding {access, refresh, expiry}. Phase 3.
        static let tokenBundle = "whoop.token_bundle"
        // Legacy 3-key storage (read-only, for migration to bundle).
        static let accessToken = "whoop.access_token"
        static let refreshToken = "whoop.refresh_token"
        static let tokenExpiry = "whoop.token_expiry"
    }

    // MARK: - Token Bundle

    private struct TokenBundle: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
    }

    // MARK: - JSON Decoder

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Init

    override init() {
        super.init()
        // Restore connection state from Keychain.
        // Phase 3: distinguish (fresh access) / (expired access + refresh exists) / (no tokens).
        guard let bundle = loadTokenBundle() else {
            connectionState = .disconnected
            return
        }
        let now = Date().timeIntervalSince1970
        if bundle.expiresAt > now + 60 {
            connectionState = .connected
        } else {
            // Access expired but we have a refresh token — kick off a silent refresh.
            connectionState = .connecting
            Task { [weak self] in
                try? await self?.refreshIfNeeded()
            }
        }
    }

    // MARK: - Credentials

    var hasCredentials: Bool {
        clientID != nil && clientSecret != nil
    }

    private var clientID: String? {
        KeychainService.load(key: Keys.clientID).flatMap { String(data: $0, encoding: .utf8) }
            ?? OAuth.defaultClientID
    }

    private var clientSecret: String? {
        KeychainService.load(key: Keys.clientSecret).flatMap { String(data: $0, encoding: .utf8) }
            ?? OAuth.defaultClientSecret
    }

    func saveCredentials(clientID: String, clientSecret: String) throws {
        try KeychainService.save(key: Keys.clientID, data: Data(clientID.utf8))
        try KeychainService.save(key: Keys.clientSecret, data: Data(clientSecret.utf8))
    }

    func clearCredentials() throws {
        try KeychainService.delete(key: Keys.clientID)
        try KeychainService.delete(key: Keys.clientSecret)
        try clearTokens()
        connectionState = .disconnected
        isDemoMode = false
    }

    // MARK: - Token Storage (atomic JSON bundle)

    private func loadTokenBundle() -> TokenBundle? {
        // Try the atomic bundle first.
        if let data = KeychainService.load(key: Keys.tokenBundle),
           let bundle = try? JSONDecoder().decode(TokenBundle.self, from: data)
        {
            return bundle
        }
        // Migrate from legacy 3-key storage (one-shot).
        guard let access = KeychainService.load(key: Keys.accessToken).flatMap({ String(data: $0, encoding: .utf8) }),
              let refresh = KeychainService.load(key: Keys.refreshToken).flatMap({ String(data: $0, encoding: .utf8) }),
              let expiryData = KeychainService.load(key: Keys.tokenExpiry),
              let expiryStr = String(data: expiryData, encoding: .utf8),
              let expiry = Double(expiryStr)
        else {
            return nil
        }
        let bundle = TokenBundle(accessToken: access, refreshToken: refresh, expiresAt: expiry)
        // Write the new key, then drop the legacy ones.
        if let encoded = try? JSONEncoder().encode(bundle) {
            try? KeychainService.save(key: Keys.tokenBundle, data: encoded)
        }
        try? KeychainService.delete(key: Keys.accessToken)
        try? KeychainService.delete(key: Keys.refreshToken)
        try? KeychainService.delete(key: Keys.tokenExpiry)
        logger.info("Whoop tokens migrated from legacy 3-key storage to atomic bundle")
        return bundle
    }

    private var storedAccessToken: String? {
        loadTokenBundle()?.accessToken
    }

    private var storedRefreshToken: String? {
        loadTokenBundle()?.refreshToken
    }

    private var tokenExpiry: Date? {
        loadTokenBundle().map { Date(timeIntervalSince1970: $0.expiresAt) }
    }

    /// Atomic write of all 3 token values. Critical for refresh-token
    /// rotation: if the new refresh token is ever lost, the user is bricked.
    private func saveTokens(access: String, refresh: String, expiresIn: Int) throws {
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60)).timeIntervalSince1970
        let bundle = TokenBundle(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
        let data = try JSONEncoder().encode(bundle)
        try KeychainService.save(key: Keys.tokenBundle, data: data)
    }

    private func clearTokens() throws {
        try KeychainService.delete(key: Keys.tokenBundle)
        // Best-effort cleanup of any straggler legacy keys.
        try? KeychainService.delete(key: Keys.accessToken)
        try? KeychainService.delete(key: Keys.refreshToken)
        try? KeychainService.delete(key: Keys.tokenExpiry)
    }

    // MARK: - Valid Access Token (auto-refresh)

    private func validAccessToken() async throws -> String {
        // Check if current token is still valid
        if let token = storedAccessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }

        // Token expired or missing — force refresh
        return try await forceTokenRefresh()
    }

    /// Refresh the access token using the stored refresh token.
    /// Used by validAccessToken() and as a retry mechanism on 401.
    /// Phase 3: Whoop rotates refresh tokens (single-use), so the new refresh
    /// token MUST be persisted atomically. Transient network errors retry once;
    /// terminal HTTP errors (400/401) clear tokens and surface .error state.
    private func forceTokenRefresh() async throws -> String {
        guard let refreshToken = storedRefreshToken,
              let cID = clientID,
              let cSecret = clientSecret
        else {
            throw WhoopError.notConnected
        }

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": cID,
            "client_secret": cSecret,
            "redirect_uri": OAuth.redirectURI,
            "scope": OAuth.scopes,
        ]

        let tokenResponse: WhoopTokenResponse
        do {
            tokenResponse = try await postTokenRequest(body: body)
        } catch let urlError as URLError where Self.isTransient(urlError) {
            // One retry on transient network errors. Don't clear tokens — the
            // Whoop server may not have consumed the refresh token yet.
            logger.info("Whoop refresh transient \(urlError.code.rawValue) — retrying once")
            do {
                tokenResponse = try await postTokenRequest(body: body)
            } catch {
                logger.error("Whoop refresh retry failed: \(error.localizedDescription)")
                connectionState = .error("Network error — tap to reconnect")
                throw WhoopError.notConnected
            }
        } catch let httpError as WhoopError {
            // Terminal HTTP error (e.g. 401): refresh token is dead. Clear and surface.
            logger.error("Whoop refresh terminal error — clearing tokens: \(httpError.localizedDescription)")
            try? clearTokens()
            connectionState = .error("Whoop session expired — tap to reconnect")
            throw WhoopError.notConnected
        } catch {
            // Unknown error — be safe: surface but DON'T clear tokens.
            logger.error("Whoop refresh unknown error: \(error.localizedDescription)")
            connectionState = .error("Refresh failed — tap to reconnect")
            throw WhoopError.notConnected
        }

        try saveTokens(
            access: tokenResponse.accessToken,
            refresh: tokenResponse.refreshToken ?? refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
        connectionState = .connected
        logger.info("Whoop token refreshed successfully")
        return tokenResponse.accessToken
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .dnsLookupFailed,
             .cannotFindHost,
             .cannotConnectToHost:
            true
        default:
            false
        }
    }

    // MARK: - Public Refresh Hook

    /// Phase 3: refresh tokens proactively on scenePhase==.active and cold launch.
    /// No-op if access token is fresh for >60s. Throws on terminal failures.
    func refreshIfNeeded() async throws {
        guard let bundle = loadTokenBundle() else {
            return // not connected, nothing to do
        }
        if bundle.expiresAt > Date().timeIntervalSince1970 + 60 {
            return // still fresh
        }
        _ = try await forceTokenRefresh()
    }

    // MARK: - Connect (Direct OAuth)

    func connect() async throws {
        guard connectionState != .connecting else {
            return
        }

        guard let cID = clientID else {
            throw WhoopError.noCredentials
        }

        connectionState = .connecting

        do {
            // Build Whoop OAuth authorization URL
            var components = URLComponents(url: OAuth.authURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: cID),
                URLQueryItem(name: "redirect_uri", value: OAuth.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: OAuth.scopes),
                URLQueryItem(name: "state", value: UUID().uuidString),
            ]

            guard let authURL = components.url else {
                throw WhoopError.invalidAuthorizationURL
            }

            // Open Whoop login page in browser
            let callbackURL = try await openAuthSession(url: authURL)

            // Extract authorization code from callback
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)

            // Check for error
            if let error = callbackComponents?.queryItems?.first(where: { $0.name == "error" })?.value {
                if error == "access_denied" {
                    throw WhoopError.userDeniedAccess
                }
                throw WhoopError.oauthError(error)
            }

            guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw WhoopError.noCallbackURL
            }

            // Exchange authorization code for tokens
            try await exchangeCodeForTokens(code: code)

            connectionState = .connected
            isDemoMode = false
            lastSyncDate = Date()

            // Fetch profile name after successful connection
            if let profile: WhoopAPIProfileResponse = try? await whoopGet(path: "/user/profile/basic") {
                profileFirstName = profile.firstName
                profileLastName = profile.lastName
            }

            logger.info("Whoop connected via direct OAuth")

        } catch {
            switch error {
            case WhoopError.userCancelled:
                connectionState = .disconnected
            default:
                connectionState = .error(error.localizedDescription)
                throw error
            }
        }
    }

    // MARK: - Demo Mode

    func connectDemo() async {
        isDemoMode = true
        connectionState = .connected
        lastSyncDate = Date()
        logger.info("Whoop connected in demo mode")
    }

    // MARK: - Disconnect

    func disconnect() async throws {
        try? clearTokens()
        connectionState = .disconnected
        isDemoMode = false
        logger.info("Whoop disconnected")
    }

    // MARK: - Fetch Recovery

    func fetchRecovery(for date: Date) async throws -> WhoopRecoveryData {
        if isDemoMode {
            return try await mockService.fetchRecovery(for: date)
        }

        let (start, end) = dateRange(for: date)
        print("[Whoop] fetchRecovery: range \(start) → \(end)")
        let response: WhoopAPIResponse<WhoopAPIRecoveryRecord> = try await whoopGet(
            path: "/recovery",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        // Log what we got
        print("[Whoop] Recovery: \(response.records.count) records")
        for (i, r) in response.records.enumerated() {
            print("[Whoop]   [\(i)] state=\(r.scoreState ?? "nil") hasScore=\(r.score != nil) recovery=\(r.score?.recoveryScore ?? -1)")
        }

        // Prefer SCORED, fall back to any record with a score
        let record = response.records.first(where: { $0.scoreState == "SCORED" && $0.score != nil })
            ?? response.records.first(where: { $0.score != nil })

        guard let record, let score = record.score else {
            print("[Whoop] Recovery: NO usable record found")
            throw WhoopError.noDataAvailable
        }

        let result = WhoopRecoveryData(
            score: score.recoveryScore ?? 0,
            hrvRmssd: score.hrvRmssdMilli ?? 0,
            restingHeartRate: score.restingHeartRate ?? 0,
            spo2: score.spo2Percentage,
            skinTemp: score.skinTempCelsius,
            date: date
        )
        print("[Whoop] Recovery result: score=\(result.score)%, hrv=\(result.hrvRmssd)ms, rhr=\(result.restingHeartRate)bpm")
        return result
    }

    // MARK: - Fetch Recovery Batch (all scored records in range)

    func fetchRecoveryBatch(for date: Date) async throws -> [WhoopRecoveryData] {
        if isDemoMode {
            return try await [mockService.fetchRecovery(for: date)]
        }

        let (start, end) = dateRange(for: date)
        let response: WhoopAPIResponse<WhoopAPIRecoveryRecord> = try await whoopGet(
            path: "/recovery",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return response.records.compactMap { record in
            guard record.scoreState == "SCORED", let score = record.score else {
                return nil
            }
            let recordDate = record.createdAt.flatMap { isoFormatter.date(from: $0) } ?? date
            return WhoopRecoveryData(
                score: score.recoveryScore ?? 0,
                hrvRmssd: score.hrvRmssdMilli ?? 0,
                restingHeartRate: score.restingHeartRate ?? 0,
                spo2: score.spo2Percentage,
                skinTemp: score.skinTempCelsius,
                date: recordDate
            )
        }
    }

    // MARK: - Fetch Sleep Batch (all scored records in range)

    func fetchSleepBatch(for date: Date) async throws -> [WhoopSleepData] {
        if isDemoMode {
            return try await [mockService.fetchSleep(for: date)]
        }

        let (start, end) = dateRange(for: date)
        let response: WhoopAPIResponse<WhoopAPISleepRecord> = try await whoopGet(
            path: "/activity/sleep",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return response.records.compactMap { record in
            guard record.nap != true, record.scoreState == "SCORED", let score = record.score else {
                return nil
            }
            let stages = score.stageSummary
            let lightMilli: Int64 = stages?.totalLightSleepTimeMilli ?? 0
            let deepMilli: Int64 = stages?.totalSlowWaveSleepTimeMilli ?? 0
            let remMilli: Int64 = stages?.totalRemSleepTimeMilli ?? 0
            let awakeMilli: Int64 = stages?.totalAwakeTimeMilli ?? 0
            let totalSleepMilli = lightMilli + deepMilli + remMilli
            let recordDate = record.createdAt.flatMap { isoFormatter.date(from: $0) } ?? date

            return WhoopSleepData(
                totalHours: Double(totalSleepMilli) / 3_600_000.0,
                sleepScore: score.sleepPerformancePercentage ?? 0,
                sleepEfficiency: score.sleepEfficiencyPercentage ?? 0,
                sleepConsistency: score.sleepConsistencyPercentage ?? 0,
                deepSleepMinutes: Int(deepMilli / 60000),
                remSleepMinutes: Int(remMilli / 60000),
                lightSleepMinutes: Int(lightMilli / 60000),
                awakeMinutes: Int(awakeMilli / 60000),
                respiratoryRate: score.respiratoryRate ?? 0,
                date: recordDate
            )
        }
    }

    // MARK: - Fetch Sleep

    func fetchSleep(for date: Date) async throws -> WhoopSleepData {
        if isDemoMode {
            return try await mockService.fetchSleep(for: date)
        }

        let (start, end) = dateRange(for: date)
        print("[Whoop] fetchSleep: range \(start) → \(end)")
        let response: WhoopAPIResponse<WhoopAPISleepRecord> = try await whoopGet(
            path: "/activity/sleep",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        print("[Whoop] Sleep: \(response.records.count) records")
        for (i, r) in response.records.enumerated() {
            print("[Whoop]   [\(i)] nap=\(r.nap ?? false) state=\(r.scoreState ?? "nil") hasScore=\(r.score != nil)")
        }

        // Get main sleep (not nap), prefer scored
        let record = response.records.first(where: { $0.nap != true && $0.scoreState == "SCORED" })
            ?? response.records.first(where: { $0.nap != true && $0.score != nil })

        guard let record, let score = record.score else {
            print("[Whoop] Sleep: NO usable record found")
            throw WhoopError.noDataAvailable
        }

        let stages = score.stageSummary
        let lightMilli: Int64 = stages?.totalLightSleepTimeMilli ?? 0
        let deepMilli: Int64 = stages?.totalSlowWaveSleepTimeMilli ?? 0
        let remMilli: Int64 = stages?.totalRemSleepTimeMilli ?? 0
        let awakeMilli: Int64 = stages?.totalAwakeTimeMilli ?? 0
        let totalSleepMilli = lightMilli + deepMilli + remMilli

        return WhoopSleepData(
            totalHours: Double(totalSleepMilli) / 3_600_000.0,
            sleepScore: score.sleepPerformancePercentage ?? 0,
            sleepEfficiency: score.sleepEfficiencyPercentage ?? 0,
            sleepConsistency: score.sleepConsistencyPercentage ?? 0,
            deepSleepMinutes: Int(deepMilli / 60000),
            remSleepMinutes: Int(remMilli / 60000),
            lightSleepMinutes: Int(lightMilli / 60000),
            awakeMinutes: Int(awakeMilli / 60000),
            respiratoryRate: score.respiratoryRate ?? 0,
            date: date
        )
    }

    // MARK: - Fetch Workouts

    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData] {
        if isDemoMode {
            return try await mockService.fetchWorkouts(for: date)
        }

        let (start, end) = dateRange(for: date)
        let response: WhoopAPIResponse<WhoopAPIWorkoutRecord> = try await whoopGet(
            path: "/activity/workout",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        let isoFormatter = ISO8601DateFormatter()
        return response.records.compactMap { record in
            let startTime = record.start.flatMap { isoFormatter.date(from: $0) } ?? date
            let endTime = record.end.flatMap { isoFormatter.date(from: $0) }
            let durationMin = endTime.map { $0.timeIntervalSince(startTime) / 60.0 } ?? 0

            return WhoopWorkoutData(
                strain: record.score?.strain ?? 0,
                averageHeartRate: Double(record.score?.averageHeartRate ?? 0),
                maxHeartRate: Double(record.score?.maxHeartRate ?? 0),
                caloriesBurned: (record.score?.kilojoule ?? 0) / 4.184,
                durationMinutes: durationMin,
                sportID: record.sportId ?? 0,
                startTime: startTime
            )
        }
    }

    // MARK: - Fetch Cycle (Strain)

    func fetchCycle(for date: Date) async throws -> WhoopCycleData {
        if isDemoMode {
            return try await mockService.fetchCycle(for: date)
        }

        let (start, end) = dateRange(for: date)
        let response: WhoopAPIResponse<WhoopAPICycleRecord> = try await whoopGet(
            path: "/cycle",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
            ]
        )

        // Prefer SCORED, fall back to any record with a score
        let record = response.records.first(where: { $0.scoreState == "SCORED" && $0.score != nil })
            ?? response.records.first(where: { $0.score != nil })

        guard let record, let score = record.score else {
            logger.info("Whoop cycle: \(response.records.count) records, none with score")
            throw WhoopError.noDataAvailable
        }

        return WhoopCycleData(
            strain: score.strain ?? 0,
            averageHeartRate: Double(score.averageHeartRate ?? 0),
            maxHeartRate: Double(score.maxHeartRate ?? 0),
            caloriesBurned: (score.kilojoule ?? 0) / 4.184,
            dayStrain: score.strain ?? 0,
            date: date
        )
    }

    // MARK: - Sync All

    func syncAll() async throws {
        let today = Date()
        _ = try? await fetchRecovery(for: today)
        _ = try? await fetchSleep(for: today)
        _ = try? await fetchWorkouts(for: today)
        _ = try? await fetchCycle(for: today)
        lastSyncDate = Date()
        logger.info("Whoop sync all completed")

        // Day-plan engine signal — fresh recovery score may shift the
        // bedtime fence and training-program rationale. DayPlanScheduler
        // debounces; safe to post even when no plan exists yet.
        await MainActor.run {
            NotificationCenter.default.post(
                name: .tempoDayPlanReplanRequested,
                object: nil,
                userInfo: ["reason": DayPlanReason.whoopSynced.rawValue]
            )
        }
    }

    // MARK: - Check Connection on Launch

    func checkConnectionOnLaunch() async {
        // If we have tokens, verify they work by fetching profile
        guard storedAccessToken != nil else {
            logger.debug("Whoop launch check: no stored token — disconnected")
            connectionState = .disconnected
            return
        }

        logger.info("Whoop launch check: found stored token, verifying...")

        do {
            let profile: WhoopAPIProfileResponse = try await whoopGet(path: "/user/profile/basic")
            profileFirstName = profile.firstName
            profileLastName = profile.lastName
            connectionState = .connected
            logger.info("Whoop launch check: connected (profile OK) — \(profile.firstName ?? "?") \(profile.lastName ?? "?")")
        } catch {
            // Token might be expired but refreshable — try refresh
            if storedRefreshToken != nil {
                do {
                    _ = try await validAccessToken()
                    connectionState = .connected
                    logger.info("Whoop launch check: connected (after token refresh)")
                } catch {
                    connectionState = .disconnected
                    logger.warning("Whoop launch check: token refresh failed — \(error.localizedDescription)")
                }
            } else {
                connectionState = .disconnected
                logger.info("Whoop launch check: no refresh token — disconnected")
            }
        }
    }

    // MARK: - Private: OAuth Helpers

    @MainActor
    private func openAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuth.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil

                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: WhoopError.userCancelled)
                    } else {
                        continuation.resume(throwing: WhoopError.authSessionFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: WhoopError.noCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.authSession = session
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String) async throws {
        guard let cID = clientID, let cSecret = clientSecret else {
            throw WhoopError.noCredentials
        }

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": cID,
            "client_secret": cSecret,
            "redirect_uri": OAuth.redirectURI,
        ]

        let tokenResponse = try await postTokenRequest(body: body)
        try saveTokens(
            access: tokenResponse.accessToken,
            refresh: tokenResponse.refreshToken ?? "",
            expiresIn: tokenResponse.expiresIn
        )
    }

    /// Character set for application/x-www-form-urlencoded values.
    /// Only unreserved characters (RFC 3986) — everything else gets percent-encoded.
    /// Critical: urlQueryAllowed does NOT encode + / = & which corrupts OAuth tokens.
    private static let formAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    private func postTokenRequest(body: [String: String]) async throws -> WhoopTokenResponse {
        var request = URLRequest(url: OAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = body.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhoopError.authSessionFailed("No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("Token exchange failed (\(httpResponse.statusCode)): \(body)")
            throw WhoopError.oauthError("Token exchange failed: \(httpResponse.statusCode)")
        }

        return try Self.decoder.decode(WhoopTokenResponse.self, from: data)
    }

    // MARK: - Private: API Calls

    private func whoopGet<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let token = try await validAccessToken()

        var components = URLComponents(url: OAuth.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw WhoopError.invalidAuthorizationURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhoopError.authSessionFailed("No HTTP response")
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            // Raw JSON dump for diagnostics — first 800 chars
            if let raw = String(data: data, encoding: .utf8) {
                print("[WhoopAPI] \(path) (\(data.count) bytes): \(String(raw.prefix(800)))")
            }
            do {
                return try Self.decoder.decode(T.self, from: data)
            } catch {
                print("[WhoopAPI] DECODE FAILED for \(path): \(error)")
                throw WhoopError.backendError(code: "decode", message: error.localizedDescription)
            }
        case 401:
            // Token rejected — force refresh and retry once before giving up
            logger.info("Whoop \(path): 401 — forcing token refresh and retry")
            do {
                let newToken = try await forceTokenRefresh()
                var retryRequest = request
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: retryRequest)
                guard let retryHttp = retryResponse as? HTTPURLResponse,
                      (200 ... 299).contains(retryHttp.statusCode)
                else {
                    logger.error("Whoop \(path): retry also failed")
                    try? clearTokens()
                    connectionState = .disconnected
                    throw WhoopError.notConnected
                }
                logger.info("Whoop \(path): retry succeeded after refresh")
                return try Self.decoder.decode(T.self, from: retryData)
            } catch {
                logger.error("Whoop \(path): 401 recovery failed — \(error.localizedDescription)")
                try? clearTokens()
                connectionState = .disconnected
                throw WhoopError.notConnected
            }
        case 404:
            throw WhoopError.noDataAvailable
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("Whoop API error (\(httpResponse.statusCode)): \(body)")
            throw WhoopError.backendError(code: "\(httpResponse.statusCode)", message: body)
        }
    }

    // MARK: - Private: Date Helpers

    private func dateRange(for date: Date) -> (start: String, end: String) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        // 7 days back to capture all recent data; 2 days forward for safety
        let start = startOfDay.addingTimeInterval(-7 * 86400)
        let end = startOfDay.addingTimeInterval(2 * 86400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (formatter.string(from: start), formatter.string(from: end))
    }
}

// MARK: ASWebAuthenticationPresentationContextProviding

extension WhoopService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - WhoopError

enum WhoopError: Error, Equatable {
    case userCancelled
    case userDeniedAccess
    case invalidAuthorizationURL
    case noCallbackURL
    case authSessionFailed(String)
    case oauthError(String)
    case backendError(code: String, message: String)
    case noDataAvailable
    case notConnected
    case noCredentials
}

// MARK: - WhoopTokenResponse

private struct WhoopTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
}

// MARK: - WhoopAPIResponse

// All DTOs use generous optionals — Whoop API fields vary by device model and score state.

private struct WhoopAPIResponse<T: Codable & Sendable>: Codable {
    let records: [T]
    let nextToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try full array decode first (fast path)
        do {
            records = try container.decode([T].self, forKey: .records)
        } catch {
            // Full array decode failed — try lossy: decode one-by-one, skip bad elements
            print("[WhoopAPI] Full array decode failed: \(error)")
            var lossy: [T] = []
            if var array = try? container.nestedUnkeyedContainer(forKey: .records) {
                while !array.isAtEnd {
                    if let element = try? array.decode(T.self) {
                        lossy.append(element)
                    } else {
                        // Skip bad element by decoding as opaque object
                        _ = try? array.decode(SkipElement.self)
                    }
                }
            }
            records = lossy
            print("[WhoopAPI] Lossy decode recovered \(lossy.count) records")
        }

        nextToken = try? container.decode(String.self, forKey: .nextToken)
    }

    private enum CodingKeys: String, CodingKey {
        case records
        case nextToken
    }

    /// Empty struct that decodes from any JSON object — used to skip bad array elements.
    private struct SkipElement: Decodable {}
}

// MARK: - WhoopAPIProfileResponse

/// Profile response — parse first_name, last_name, email from Whoop API.
private struct WhoopAPIProfileResponse: Codable {
    let firstName: String?
    let lastName: String?
    let email: String?
}

// MARK: - WhoopAPIRecoveryRecord

// Minimal structs — only fields we actually read. Extra JSON keys are ignored by decoder.
// Avoids type-mismatch failures (e.g. Whoop returns some IDs as strings, some as ints).

private struct WhoopAPIRecoveryRecord: Codable {
    let createdAt: String?
    let scoreState: String?
    let score: WhoopAPIRecoveryScore?
}

// MARK: - WhoopAPIRecoveryScore

private struct WhoopAPIRecoveryScore: Codable {
    let userCalibrating: Bool?
    let recoveryScore: Double?
    let restingHeartRate: Double?
    let hrvRmssdMilli: Double?
    let spo2Percentage: Double?
    let skinTempCelsius: Double?
}

// MARK: - WhoopAPISleepRecord

private struct WhoopAPISleepRecord: Codable {
    let createdAt: String?
    let nap: Bool?
    let scoreState: String?
    let score: WhoopAPISleepScore?
}

// MARK: - WhoopAPISleepScore

private struct WhoopAPISleepScore: Codable {
    let stageSummary: WhoopAPIStageSummary?
    let respiratoryRate: Double?
    let sleepPerformancePercentage: Double?
    let sleepConsistencyPercentage: Double?
    let sleepEfficiencyPercentage: Double?
}

// MARK: - WhoopAPIStageSummary

private struct WhoopAPIStageSummary: Codable {
    let totalInBedTimeMilli: Int64?
    let totalAwakeTimeMilli: Int64?
    let totalLightSleepTimeMilli: Int64?
    let totalSlowWaveSleepTimeMilli: Int64?
    let totalRemSleepTimeMilli: Int64?
    let sleepCycleCount: Int?
    let disturbanceCount: Int?
}

// MARK: - WhoopAPIWorkoutRecord

private struct WhoopAPIWorkoutRecord: Codable {
    let start: String?
    let end: String?
    let sportId: Int?
    let scoreState: String?
    let score: WhoopAPIWorkoutScore?
}

// MARK: - WhoopAPIWorkoutScore

private struct WhoopAPIWorkoutScore: Codable {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let distanceMeter: Double?
}

// MARK: - WhoopAPICycleRecord

private struct WhoopAPICycleRecord: Codable {
    let scoreState: String?
    let score: WhoopAPICycleScore?
}

// MARK: - WhoopAPICycleScore

private struct WhoopAPICycleScore: Codable {
    let strain: Double?
    let kilojoule: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
}
