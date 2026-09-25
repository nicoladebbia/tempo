import Vapor

// MARK: - TrainingProgramImportController

//
// Trainer Program import (photo/PDF/text -> a structured training program),
// fixes #1 + #2:
//   #1 — imports used to live behind the whole-group SubscriptionMiddleware
//        on /v1/nutrition/ai/*, so a non-Pro user's import failed outright.
//        This controller does its own entitlement check instead: free users
//        get a small monthly quota (see TrainerProgramImportQuotaService),
//        Pro/allowlisted users are unlimited. NOT registered behind
//        SubscriptionMiddleware.
//   #2 — a multi-page import used to fire one vision request PER PAGE
//        against the 20/min nutrition-ai limit and could exhaust it mid
//        import. Transcription is now ONE Claude call per batch of up to 5
//        page images (iOS batches), against this controller's own, higher
//        per-minute limit (10/min — see routes.swift), separate from the
//        nutrition-ai group entirely.
//
// Routes (all under `protected`, i.e. JWT + ToS gate; own rate limit; no
// SubscriptionMiddleware):
//   POST /v1/training/program-import/transcribe
//   POST /v1/training/program-import/structure
//   GET  /v1/training/program-import/quota

struct TrainingProgramImportController: RouteCollection {
    /// 1–5 images per transcribe request.
    static let maxImagesPerRequest = 5
    /// Total raw (decoded) image bytes per request — the vision proxy's own
    /// body limit is set well above this (see boot(routes:)) to leave room
    /// for base64 + JSON overhead.
    static let maxRawImageBytesPerRequest = Int(4.5 * 1024 * 1024)

    func boot(routes: RoutesBuilder) throws {
        routes.on(.POST, "transcribe", body: .collect(maxSize: "7mb"), use: transcribe)
        routes.on(.POST, "structure", body: .collect(maxSize: "256kb"), use: structure)
        routes.get("quota", use: quota)
    }

    // MARK: - Transcribe

    @Sendable
    func transcribe(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(ProgramImportTranscribeRequest.self)

        do {
            try ProgramImportTranscribeValidation.validate(
                sessionID: input.sessionID,
                imageCount: input.images.count,
                hintTextsCount: input.hintTexts.count,
                rawByteEstimate: input.images.reduce(0) { $0 + Self.rawByteCount(fromBase64: $1.base64) }
            )
        } catch let error as ProgramImportTranscribeValidation.ValidationError {
            throw Abort(.badRequest, reason: error.reason)
        }

        if let quotaResponse = try await gateOrQuotaResponse(userID: userID, sessionID: input.sessionID, on: req) {
            return quotaResponse
        }

        let hintTexts: [String?] = input.hintTexts.isEmpty
            ? Array(repeating: nil, count: input.images.count)
            : input.hintTexts

        let proxyResponse = try await NutritionClaudeProxyService.shared.sendMultiImage(
            input: NutritionProxyMultiImageRequest(
                model: "sonnet",
                system: input.system,
                userMessage: input.userMessage,
                images: input.images.map { NutritionProxyImageInput(mediaType: $0.mediaType, base64: $0.base64) },
                hintTexts: hintTexts,
                maxTokens: min(8000, max(2000, input.images.count * 1800)),
                temperature: 0,
                caller: "trainer_program_transcribe"
            ),
            on: req
        )

        let pages = ProgramImportPageSplitter.split(proxyResponse.text)
        let envelope = Envelope(data: ProgramImportTranscribeResponse(pages: pages), requestID: req.requestID)
        let response = Response(status: .ok)
        try response.content.encode(envelope)
        return response
    }

    // MARK: - Structure

    @Sendable
    func structure(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(ProgramImportStructureRequest.self)
        do {
            try ProgramImportTranscribeValidation.validateSessionID(input.sessionID)
        } catch let error as ProgramImportTranscribeValidation.ValidationError {
            throw Abort(.badRequest, reason: error.reason)
        }

        if let quotaResponse = try await gateOrQuotaResponse(userID: userID, sessionID: input.sessionID, on: req) {
            return quotaResponse
        }

        let proxyResponse = try await NutritionClaudeProxyService.shared.sendText(
            input: NutritionProxyTextRequest(
                model: input.model,
                system: input.system,
                userMessage: input.userMessage,
                maxTokens: input.maxTokens,
                temperature: input.temperature,
                caller: input.caller
            ),
            on: req
        )

        let envelope = Envelope(data: ProgramImportStructureResponse(text: proxyResponse.text), requestID: req.requestID)
        let response = Response(status: .ok)
        try response.content.encode(envelope)
        return response
    }

    // MARK: - Quota

    @Sendable
    func quota(req: Request) async throws -> Envelope<ProgramImportQuotaResponse> {
        let userID = try req.auth.requireUserID()
        let snapshot = try await TrainerProgramImportQuotaService.snapshot(userID: userID, on: req)
        return Envelope(
            data: ProgramImportQuotaResponse(
                isPro: snapshot.isPro,
                limit: snapshot.limit,
                used: snapshot.used,
                remaining: snapshot.remaining,
                resetsAt: snapshot.resetsAt
            ),
            requestID: req.requestID
        )
    }

    // MARK: - Shared gate

    /// Runs the quota gate. Returns nil when the caller should proceed;
    /// returns a fully-formed 402 Response (bypassing TempoErrorMiddleware
    /// entirely, so it can carry the structured {limit, used, resets_at}
    /// fields the iOS client needs) when the free monthly quota is exhausted.
    private func gateOrQuotaResponse(userID: String, sessionID: String, on req: Request) async throws -> Response? {
        let result = try await TrainerProgramImportQuotaService.gate(userID: userID, sessionID: sessionID, on: req)
        switch result {
        case .allowed:
            return nil
        case let .exceeded(limit, used, resetsAt):
            let body = ProgramImportQuotaErrorBody(
                error: true,
                reason: "You've used your \(limit) free trainer-program imports this month.",
                code: "program_import_quota",
                limit: limit,
                used: used,
                resetsAt: resetsAt
            )
            let response = Response(status: .paymentRequired)
            try response.content.encode(body)
            return response
        }
    }

    /// Base64's on-wire length is ~4/3 of the raw byte count (ignoring the
    /// small, bounded padding effect) — good enough for a pre-flight size
    /// guard without actually decoding every image.
    static func rawByteCount(fromBase64 base64: String) -> Int {
        (base64.count * 3) / 4
    }
}

// MARK: - ProgramImportTranscribeValidation

//
// Pure request-validation for the transcribe route — no Request/DB — so it's
// directly unit-testable. Mirrors the shape `TrainingProgramImportController.
// transcribe` needs to check before it does anything with the quota gate or
// the network: session id format, image count bounds, hint-text array
// length, and total raw byte budget.

enum ProgramImportTranscribeValidation {
    enum ValidationError: Error, Equatable {
        case invalidSessionID
        case imageCountOutOfRange(count: Int)
        case hintTextsLengthMismatch(hintTextsCount: Int, imageCount: Int)
        case batchTooLarge(rawByteEstimate: Int, maxBytes: Int)

        var reason: String {
            switch self {
            case .invalidSessionID:
                "session_id must be a UUID."
            case let .imageCountOutOfRange(count):
                "Send between 1 and \(TrainingProgramImportController.maxImagesPerRequest) images per request (got \(count))."
            case .hintTextsLengthMismatch:
                "hint_texts must be empty or match images in length."
            case let .batchTooLarge(rawByteEstimate, maxBytes):
                "That batch of images is too large (~\(rawByteEstimate / 1024)KB, max ~\(maxBytes / 1024)KB); send fewer or smaller pages per request."
            }
        }
    }

    static func validateSessionID(_ sessionID: String) throws {
        guard UUID(uuidString: sessionID) != nil else {
            throw ValidationError.invalidSessionID
        }
    }

    static func validate(
        sessionID: String,
        imageCount: Int,
        hintTextsCount: Int,
        rawByteEstimate: Int,
        maxImagesPerRequest: Int = TrainingProgramImportController.maxImagesPerRequest,
        maxRawImageBytesPerRequest: Int = TrainingProgramImportController.maxRawImageBytesPerRequest
    ) throws {
        try validateSessionID(sessionID)
        guard (1 ... maxImagesPerRequest).contains(imageCount) else {
            throw ValidationError.imageCountOutOfRange(count: imageCount)
        }
        guard hintTextsCount == 0 || hintTextsCount == imageCount else {
            throw ValidationError.hintTextsLengthMismatch(hintTextsCount: hintTextsCount, imageCount: imageCount)
        }
        guard rawByteEstimate <= maxRawImageBytesPerRequest else {
            throw ValidationError.batchTooLarge(rawByteEstimate: rawByteEstimate, maxBytes: maxRawImageBytesPerRequest)
        }
    }
}

// MARK: - DTOs

struct ProgramImportImageInput: Content {
    /// e.g. "image/jpeg", "image/png", "image/webp"
    let mediaType: String
    /// Base64-encoded image bytes (no data: prefix).
    let base64: String
}

struct ProgramImportTranscribeRequest: Content {
    /// Client-generated UUID, shared by every call (every transcribe batch +
    /// the structure call) that belongs to ONE import. Used for quota dedup.
    let sessionID: String
    let images: [ProgramImportImageInput]
    /// Per-image on-device text hint. Empty array = no hints; otherwise must
    /// match `images` in length (an entry may itself be null/absent for a
    /// page with no hint).
    let hintTexts: [String?]
    let system: String
    let userMessage: String

    // The global decoder's `.convertFromSnakeCase` turns `session_id` into
    // `sessionId`, which never matches a property spelled `sessionID` —
    // every request failed to decode (400). Map it explicitly.
    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case images, hintTexts, system, userMessage
    }
}

struct ProgramImportTranscribeResponse: Content {
    /// One entry per page, in the order the images were sent.
    let pages: [String]
}

struct ProgramImportStructureRequest: Content {
    let sessionID: String
    /// One of: "haiku", "sonnet" — the structure step always uses "sonnet"
    /// in practice (iOS sends it), enforced same as the nutrition proxy.
    let model: String
    let system: String
    let userMessage: String
    let maxTokens: Int
    let temperature: Double
    let caller: String

    /// See `ProgramImportTranscribeRequest.CodingKeys`.
    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case model, system, userMessage, maxTokens, temperature, caller
    }
}

struct ProgramImportStructureResponse: Content {
    let text: String
}

struct ProgramImportQuotaResponse: Content {
    let isPro: Bool
    /// nil = unlimited (Pro/allowlisted).
    let limit: Int?
    let used: Int
    /// nil = unlimited (Pro/allowlisted).
    let remaining: Int?
    let resetsAt: Date
}

/// 402 body for an exhausted free-tier quota. Deliberately shaped like
/// TempoErrorMiddleware's generic `{error, reason, code}` body (so existing
/// `code`-based error handling on iOS still works) PLUS the extra fields the
/// import screen needs to show "X of Y used, resets on Z" without a second
/// round-trip. Built and returned directly by the controller (not thrown)
/// so these extra fields survive — TempoErrorMiddleware's catch-all would
/// otherwise collapse any thrown error down to just {error, reason, code}.
struct ProgramImportQuotaErrorBody: Content {
    let error: Bool
    let reason: String
    let code: String
    let limit: Int
    let used: Int
    let resetsAt: Date
}
