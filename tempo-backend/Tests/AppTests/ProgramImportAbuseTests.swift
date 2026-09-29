@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - Program-import abuse hardening tests

//
// Covers: model/mediaType/base64 allowlists (pure), atomic quota under
// concurrency, per-session call caps, old-month session rejection, the
// AI-consent gate and the feedback daily quota (HTTP, real Postgres+Redis).
//
// ANTHROPIC_API_KEY is unset in tests, so a request that clears every gate
// fails inside the Claude proxy (5xx). "Reached Claude" therefore == the gate
// let it through, and a 4xx == a gate rejected it.

@Suite("ProgramImportPolicy")
struct ProgramImportPolicyTests {
    @Test func onlySonnetModelIsAllowed() throws {
        try ProgramImportPolicy.validateModel("sonnet")
        #expect(throws: ProgramImportPolicy.PolicyError.self) { try ProgramImportPolicy.validateModel("opus") }
        #expect(throws: ProgramImportPolicy.PolicyError.self) { try ProgramImportPolicy.validateModel("claude-opus-4") }
        #expect(throws: ProgramImportPolicy.PolicyError.self) { try ProgramImportPolicy.validateModel("") }
    }

    @Test func maxTokensAreClamped() {
        #expect(ProgramImportPolicy.clampedMaxTokens(4096, cap: 4096) == 4096)
        #expect(ProgramImportPolicy.clampedMaxTokens(1_000_000, cap: 4096) == 4096)
        #expect(ProgramImportPolicy.clampedMaxTokens(-5, cap: 4096) == 1)
        #expect(ProgramImportPolicy.clampedMaxTokens(1500, cap: 1500) == 1500)
    }

    @Test func mediaTypeAndBase64AreValidated() throws {
        try ProgramImportPolicy.validateImage(mediaType: "image/jpeg", base64: "AAAA")
        try ProgramImportPolicy.validateImage(mediaType: "image/png", base64: "AAAA")
        #expect(throws: ProgramImportPolicy.PolicyError.unsupportedMediaType("text/html")) {
            try ProgramImportPolicy.validateImage(mediaType: "text/html", base64: "AAAA")
        }
        #expect(throws: ProgramImportPolicy.PolicyError.invalidBase64) {
            try ProgramImportPolicy.validateImage(mediaType: "image/jpeg", base64: "not base64!!")
        }
        #expect(throws: ProgramImportPolicy.PolicyError.invalidBase64) {
            try ProgramImportPolicy.validateImage(mediaType: "image/jpeg", base64: "")
        }
    }

    @Test func userMessageLengthIsCapped() throws {
        try ProgramImportPolicy.validateUserMessage("x", max: 10)
        #expect(throws: ProgramImportPolicy.PolicyError.userMessageTooLong(max: 10)) {
            try ProgramImportPolicy.validateUserMessage(String(repeating: "x", count: 11), max: 10)
        }
    }

    @Test func serverOwnedPromptsAreNonEmpty() {
        #expect(ProgramImportPolicy.structureSystemPrompt.hasPrefix("You extract a personal trainer's training program"))
        #expect(ProgramImportPolicy.feedbackSystemPrompt.hasPrefix("You read a personal trainer's short message"))
        #expect(ProgramImportPolicy.transcribeSystemPrompt.hasPrefix("You transcribe pages"))
    }
}

@Suite("ProgramImportAbuse", .serialized)
struct ProgramImportAbuseTests {
    // MARK: - Harness

    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func makeUser(app: Application, consent: Bool = true) async throws -> (user: User, token: String) {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "Test User")
        user.tosAcceptedAt = Date()
        if consent {
            user.aiConsentAt = Date()
        }
        try await user.save(on: app.db)
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let token = try await JWTService.issueAccessToken(userID: user.requireID(), deviceID: "test-device", on: req)
        return (user, token)
    }

    private func post(
        _ app: Application, _ path: String, token: String, json: String,
        _ check: @escaping (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "v1/training/program-import/\(path)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: token)
            req.headers.contentType = .json
            req.body = ByteBuffer(string: json)
        }, afterResponse: { res async throws in try await check(res) })
    }

    /// Exactly the shape TrainerProgramImportService sends.
    private func appStructureBody(session: String = UUID().uuidString) -> String {
        """
        {"session_id":"\(session)","model":"sonnet","system":"You extract...","user_message":"Parse the training program inside <program_text> ...",
         "max_tokens":4096,"temperature":0,"caller":"trainer_program_import"}
        """
    }

    /// Exactly the shape TrainerFeedbackService sends.
    private func appFeedbackBody() -> String {
        """
        {"model":"sonnet","system":"You read...","user_message":"Extract every change ...","max_tokens":1500,"temperature":0,"caller":"trainer_feedback_edit"}
        """
    }

    /// Exactly the shape TrainerProgramPageTranscriber sends (one jpeg page, hints empty).
    private func appTranscribeBody(session: String = UUID().uuidString, mediaType: String = "image/jpeg", base64: String = "/9j/4AAQSkZJRg==") -> String {
        """
        {"session_id":"\(session)","images":[{"media_type":"\(mediaType)","base64":"\(base64)"}],
         "hint_texts":[],"system":"You transcribe...","user_message":"Immediately before the transcription ..."}
        """
    }

    private func reachedClaude(_ res: XCTHTTPResponse) -> Bool {
        res.status.code >= 500
    }

    // MARK: - App's real payloads still pass every gate

    @Test func appPayloadsPassAllGates() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            try await post(app, "structure", token: token, json: appStructureBody()) { res in
                #expect(reachedClaude(res), "structure: got \(res.status)")
            }
            try await post(app, "feedback", token: token, json: appFeedbackBody()) { res in
                #expect(reachedClaude(res), "feedback: got \(res.status)")
            }
            try await post(app, "transcribe", token: token, json: appTranscribeBody()) { res in
                #expect(reachedClaude(res), "transcribe: got \(res.status)")
            }
        }
    }

    // MARK: - Model allowlist / token clamp

    @Test func disallowedModelIsRejected() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let body = appStructureBody().replacingOccurrences(of: "\"model\":\"sonnet\"", with: "\"model\":\"opus\"")
            try await post(app, "structure", token: token, json: body) { res in
                #expect(res.status == .badRequest)
            }
            let fb = appFeedbackBody().replacingOccurrences(of: "\"model\":\"sonnet\"", with: "\"model\":\"opus\"")
            try await post(app, "feedback", token: token, json: fb) { res in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func hugeMaxTokensDoesNotBreakAndOversizedMessageIsRejected() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let big = appStructureBody().replacingOccurrences(of: "\"max_tokens\":4096", with: "\"max_tokens\":900000")
            try await post(app, "structure", token: token, json: big) { res in
                #expect(reachedClaude(res), "clamped, not rejected: \(res.status)")
            }
            let long = String(repeating: "a", count: ProgramImportPolicy.structureMaxUserMessageChars + 1)
            let tooLong = appStructureBody().replacingOccurrences(of: "Parse the training program inside <program_text> ...", with: long)
            try await post(app, "structure", token: token, json: tooLong) { res in
                #expect(res.status == .badRequest)
            }
        }
    }

    // MARK: - transcribe media type / base64

    @Test func transcribeRejectsBadMediaTypeAndBase64() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            try await post(app, "transcribe", token: token, json: appTranscribeBody(mediaType: "text/html")) { res in
                #expect(res.status == .badRequest)
            }
            try await post(app, "transcribe", token: token, json: appTranscribeBody(base64: "%%%not-base64%%%")) { res in
                #expect(res.status == .badRequest)
            }
        }
    }

    // MARK: - AI consent

    @Test func routesRequireAIConsent() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app, consent: false)
            for (path, body) in [
                ("structure", appStructureBody()),
                ("feedback", appFeedbackBody()),
                ("transcribe", appTranscribeBody()),
            ] {
                try await post(app, path, token: token, json: body) { res in
                    #expect(res.status == .paymentRequired, "\(path): \(res.status)")
                    #expect(res.body.string.contains("ai_consent_required"), "\(path): \(res.body.string)")
                }
            }
        }
    }

    // MARK: - Feedback daily quota

    @Test func feedbackIsDailyCappedForFreeUsers() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            for i in 0 ..< TrainerProgramImportQuotaService.freeDailyFeedbackLimit {
                try await post(app, "feedback", token: token, json: appFeedbackBody()) { res in
                    #expect(reachedClaude(res), "call \(i): \(res.status)")
                }
            }
            try await post(app, "feedback", token: token, json: appFeedbackBody()) { res in
                #expect(res.status == .tooManyRequests)
            }
        }
    }

    // MARK: - Per-session structure cap (same session id re-used)

    @Test func sameSessionStructureCallsAreCapped() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let session = UUID().uuidString
            for i in 0 ..< TrainerProgramImportQuotaService.maxStructureCallsPerSession {
                try await post(app, "structure", token: token, json: appStructureBody(session: session)) { res in
                    #expect(reachedClaude(res), "call \(i): \(res.status)")
                }
            }
            try await post(app, "structure", token: token, json: appStructureBody(session: session)) { res in
                #expect(res.status == .tooManyRequests, "got \(res.status) \(res.body.string)")
                #expect(res.body.string.contains("program_import_session_limit"))
            }
        }
    }

    // MARK: - Quota service: race, cap, old months

    @Test func concurrentFreshSessionsCannotExceedFreeLimit() async throws {
        try await withApp { app in
            let (user, _) = try await makeUser(app: app)
            let userID = try user.requireID()
            let req = Request(application: app, on: app.eventLoopGroup.next())

            let results = try await withThrowingTaskGroup(of: TrainerProgramImportQuotaService.GateResult.self) { group in
                for _ in 0 ..< 5 {
                    group.addTask {
                        try await TrainerProgramImportQuotaService.gate(
                            userID: userID, sessionID: UUID().uuidString, kind: .structure, on: req
                        )
                    }
                }
                var all: [TrainerProgramImportQuotaService.GateResult] = []
                for try await result in group {
                    all.append(result)
                }
                return all
            }

            let allowed = results.filter { $0 == .allowed }.count
            #expect(allowed == TrainerProgramImportQuotaService.freeMonthlyLimit, "allowed=\(allowed) of 5 parallel fresh sessions")
            let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: userID, on: req)
            #expect(snapshot.used == TrainerProgramImportQuotaService.freeMonthlyLimit)
        }
    }

    @Test func oldMonthSessionCannotBeReused() async throws {
        try await withApp { app in
            let (user, _) = try await makeUser(app: app)
            let userID = try user.requireID()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            let session = UUID().uuidString
            try await TrainerProgramImport(userID: userID, sessionID: session, yearMonth: "2020-01").create(on: app.db)

            let result = try await TrainerProgramImportQuotaService.gate(userID: userID, sessionID: session, kind: .structure, on: req)
            #expect(result == .sessionExpired)
        }
    }

    @Test func transcribeCallsPerSessionAreCapped() async throws {
        try await withApp { app in
            let (user, _) = try await makeUser(app: app)
            let userID = try user.requireID()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            let session = UUID().uuidString
            for _ in 0 ..< TrainerProgramImportQuotaService.maxTranscribeCallsPerSession {
                let r = try await TrainerProgramImportQuotaService.gate(userID: userID, sessionID: session, kind: .transcribe, on: req)
                #expect(r == .allowed)
            }
            let over = try await TrainerProgramImportQuotaService.gate(userID: userID, sessionID: session, kind: .transcribe, on: req)
            #expect(over == .sessionCallLimit(limit: TrainerProgramImportQuotaService.maxTranscribeCallsPerSession))
            // Structure counter is independent.
            let structure = try await TrainerProgramImportQuotaService.gate(userID: userID, sessionID: session, kind: .structure, on: req)
            #expect(structure == .allowed)
        }
    }
}
