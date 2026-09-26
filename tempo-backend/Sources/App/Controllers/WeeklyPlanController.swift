import Fluent
import Foundation
import Queues
import Vapor

// MARK: - WeeklyPlanController

//
// Routes (mounted at /v1/nutrition/weekly-plans by routes.swift, behind
// protected + RateLimitMiddleware + SubscriptionMiddleware, same as
// NutritionAIController):
//   POST /v1/nutrition/weekly-plans         — kick off "build next week"
//   GET  /v1/nutrition/weekly-plans/latest  — the caller's newest job
//   GET  /v1/nutrition/weekly-plans/:id     — one job, caller's own only
//
// The actual Claude call + macro solve happen in WeeklyPlanJob (Queues),
// with the app closed — this controller only creates/reads the row.
//
// NOTE ON JSON CASING: every response here is built with a bare
// `JSONEncoder()` (see WeeklyPlanEnvelope below), NOT the app's global
// snake_case ContentConfiguration. The envelope/job fields (id, week_start,
// status, ...) are still explicit snake_case via CodingKeys — same casing
// iOS sees from every other endpoint — but the embedded `plan` object must
// come back byte-for-byte what WeeklyPlanPipeline produced (camelCase,
// because that's the shape iOS's own prompt asked Claude for). Foundation's
// JSONEncoder.keyEncodingStrategy has no way to exempt a subtree, so the
// only way to protect `plan` is to not use a strategy at all and spell out
// the outer keys by hand.

struct WeeklyPlanController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post(use: create)
        routes.get("latest", use: latest)
        routes.get(":id", use: getByID)
    }

    // MARK: - POST /

    @Sendable
    func create(_ req: Request) async throws -> WeeklyPlanEnvelope<WeeklyPlanCreateResponse> {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(WeeklyPlanCreateRequest.self)
        try Self.validate(input)

        if let existing = try await Self.findInFlightJob(userID: userID, weekStart: input.weekStart, on: req.db) {
            let resolved = try await Self.markStaleIfNeeded(existing, on: req)
            if resolved.statusEnum == .queued || resolved.statusEnum == .running {
                return WeeklyPlanEnvelope(data: WeeklyPlanCreateResponse(job: resolved), requestID: req.requestID)
            }
            // Fell through: the in-flight job was stale and just got marked
            // failed — fall through to create a fresh one below.
        }

        let payload = WeeklyPlanRequestPayload(
            system: input.system, prompt: input.prompt, targets: input.targets, timezone: input.timezone
        )
        let requestJSON = try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"

        let job = WeeklyPlanJobRecord(userID: userID, weekStart: input.weekStart, requestJSON: requestJSON)
        do {
            try await job.save(on: req.db)
        } catch {
            // The SELECT above and this INSERT aren't atomic: a second
            // concurrent POST (double-tap, or a client retry after a
            // timed-out-but-actually-succeeded request) can race past the
            // check above before either commits. The partial unique index
            // on (user_id, week_start) WHERE status IN (queued, running)
            // (CreateWeeklyPlanJobs) is the real backstop — it turns the
            // loser's INSERT into a constraint violation instead of a
            // second Claude Sonnet call + a second push. Same pattern as
            // TrainerProgramImportQuotaService.isUniqueConstraintViolation.
            guard Self.isUniqueConstraintViolation(error),
                  let winner = try await Self.findInFlightJob(userID: userID, weekStart: input.weekStart, on: req.db)
            else {
                throw error
            }
            return WeeklyPlanEnvelope(data: WeeklyPlanCreateResponse(job: winner), requestID: req.requestID)
        }
        try await req.queues(.mealPlans).dispatch(WeeklyPlanJob.self, job.requireID())

        return WeeklyPlanEnvelope(data: WeeklyPlanCreateResponse(job: job), requestID: req.requestID)
    }

    private static func findInFlightJob(userID: String, weekStart: String, on db: any Database) async throws -> WeeklyPlanJobRecord? {
        try await WeeklyPlanJobRecord.query(on: db)
            .filter(\.$userID == userID)
            .filter(\.$weekStart == weekStart)
            .filter(\.$status ~~ [WeeklyPlanJobRecord.Status.queued.rawValue, WeeklyPlanJobRecord.Status.running.rawValue])
            .sort(\.$createdAt, .descending)
            .first()
    }

    private static func isUniqueConstraintViolation(_ error: Error) -> Bool {
        if let dbError = error as? any DatabaseError, dbError.isConstraintFailure {
            return true
        }
        // Fallback for drivers/wrappers that don't conform to DatabaseError:
        // Postgres unique_violation is SQLSTATE 23505.
        let description = String(describing: error)
        return description.contains("23505") || description.localizedCaseInsensitiveContains("duplicate key")
    }

    // MARK: - GET /latest

    @Sendable
    func latest(_ req: Request) async throws -> WeeklyPlanEnvelope<WeeklyPlanStatusResponse?> {
        let userID = try req.auth.requireUserID()
        guard let job = try await WeeklyPlanJobRecord.query(on: req.db)
            .filter(\.$userID == userID)
            .sort(\.$createdAt, .descending)
            .first()
        else {
            return WeeklyPlanEnvelope(data: nil, requestID: req.requestID)
        }
        let resolved = try await Self.markStaleIfNeeded(job, on: req)
        return WeeklyPlanEnvelope(data: WeeklyPlanStatusResponse(job: resolved), requestID: req.requestID)
    }

    // MARK: - GET /:id

    @Sendable
    func getByID(_ req: Request) async throws -> WeeklyPlanEnvelope<WeeklyPlanStatusResponse> {
        let userID = try req.auth.requireUserID()
        guard
            let idParam = req.parameters.get("id"),
            let id = UUID(uuidString: idParam)
        else {
            throw Abort(.badRequest, reason: "Invalid job id.")
        }
        guard
            let job = try await WeeklyPlanJobRecord.find(id, on: req.db),
            job.userID == userID
        else {
            throw Abort(.notFound)
        }
        let resolved = try await Self.markStaleIfNeeded(job, on: req)
        return WeeklyPlanEnvelope(data: WeeklyPlanStatusResponse(job: resolved), requestID: req.requestID)
    }

    // MARK: - Staleness

    /// A queued/running job older than `staleAfter` is presumed dead (worker
    /// crash, deploy mid-job — production runs no queue worker at all today
    /// outside the dedicated `.mealPlans` in-process worker). Persists +
    /// returns the failed state so the phone can retry instead of polling
    /// forever.
    static func markStaleIfNeeded(_ job: WeeklyPlanJobRecord, on req: Request) async throws -> WeeklyPlanJobRecord {
        guard job.statusEnum == .queued || job.statusEnum == .running else { return job }
        guard let createdAt = job.createdAt,
              Date().timeIntervalSince(createdAt) > WeeklyPlanJobRecord.staleAfter
        else { return job }

        job.statusEnum = .failed
        job.error = "timed out"
        job.completedAt = Date()
        try await job.save(on: req.db)
        return job
    }

    // MARK: - Validation

    /// 200 KB, matching the spec's cap on system + prompt combined.
    private static let maxPromptBytes = 200 * 1024

    /// A stateless `yyyy-MM-dd` check (calendar-valid, not just shaped right)
    /// — deliberately not a shared `DateFormatter`: `DateFormatter` is not
    /// safe to invoke concurrently from multiple request handlers on
    /// Vapor's event loops, and this codebase's own convention (see
    /// `TrainerProgramImportQuotaService.currentYearMonth`) is a fresh
    /// formatter/calendar per call, never a shared static one.
    private static func isValidWeekStart(_ string: String) -> Bool {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .init(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // `Calendar.date(from:)` normalizes out-of-range fields instead of
        // failing (e.g. Feb 30 quietly becomes Mar 2), so round-trip the
        // result and compare — a strict validity check, not just "parses".
        guard let date = calendar.date(from: components) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }

    private static func validate(_ input: WeeklyPlanCreateRequest) throws {
        guard
            input.weekStart.count == 10,
            isValidWeekStart(input.weekStart)
        else {
            throw WeeklyPlanValidationError.invalidWeekStart
        }
        guard !input.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WeeklyPlanValidationError.emptyPrompt
        }
        guard input.system.utf8.count + input.prompt.utf8.count <= maxPromptBytes else {
            throw WeeklyPlanValidationError.payloadTooLarge
        }
        guard !input.targets.isEmpty else {
            throw WeeklyPlanValidationError.invalidTargets
        }
        for target in input.targets.values {
            guard target.kcal > 0, target.proteinG > 0, target.carbsG > 0, target.fatG > 0 else {
                throw WeeklyPlanValidationError.invalidTargets
            }
        }
        guard !input.timezone.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WeeklyPlanValidationError.invalidTimezone
        }
    }
}

// MARK: - Validation errors

enum WeeklyPlanValidationError: AbortError {
    case invalidWeekStart
    case emptyPrompt
    case payloadTooLarge
    case invalidTargets
    case invalidTimezone

    var status: HTTPResponseStatus {
        .badRequest
    }

    var reason: String {
        switch self {
        case .invalidWeekStart: "weekStart must be a valid yyyy-MM-dd date."
        case .emptyPrompt: "prompt must not be empty."
        case .payloadTooLarge: "system + prompt must not exceed 200 KB combined."
        case .invalidTargets: "targets must be non-empty, with positive kcal/proteinG/carbsG/fatG for every entry."
        case .invalidTimezone: "timezone must not be empty."
        }
    }
}

// MARK: - Request DTO

struct WeeklyPlanCreateRequest: Content {
    let weekStart: String
    let system: String
    let prompt: String
    let targets: [String: MacroTargetsDTO]
    let timezone: String
}

// MARK: - Response DTOs

//
// Plain (non-Content) Encodable types — they're only ever wrapped in
// WeeklyPlanEnvelope, which does its own encoding. See the file header for
// why this bypasses ContentConfiguration.global.

struct WeeklyPlanCreateResponse: Encodable {
    let id: String
    let status: String
    let weekStart: String

    private enum CodingKeys: String, CodingKey {
        case id, status
        case weekStart = "week_start"
    }

    init(job: WeeklyPlanJobRecord) {
        id = (job.id ?? UUID()).uuidString
        status = job.status
        weekStart = job.weekStart
    }
}

struct WeeklyPlanStatusResponse: Encodable {
    let id: String
    let weekStart: String
    let status: String
    let error: String?
    /// Untouched — see file header. `nil` until status == "ready".
    let plan: JSONValue?
    let createdAt: Date
    let completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case status, error, plan
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    init(job: WeeklyPlanJobRecord) {
        id = (job.id ?? UUID()).uuidString
        weekStart = job.weekStart
        status = job.status
        error = job.error
        if let planJSON = job.planJSON, let data = planJSON.data(using: .utf8) {
            plan = try? JSONDecoder().decode(JSONValue.self, from: data)
        } else {
            plan = nil
        }
        createdAt = job.createdAt ?? Date()
        completedAt = job.completedAt
    }
}

// MARK: - Envelope

//
// A from-scratch `{ok, data, meta}` wrapper — deliberately not the app's
// shared `Envelope<T: Content>` (Content pulls in ContentConfiguration.global,
// which would snake_case the embedded `plan` object's dictionary keys; see
// the file header). `T` only needs to be Encodable, which also lets `data`
// be an Optional (GET latest with no job yet returns `"data": null`).

struct WeeklyPlanEnvelope<T: Encodable>: AsyncResponseEncodable {
    let data: T
    let requestID: String?

    init(data: T, requestID: String? = nil) {
        self.data = data
        self.requestID = requestID
    }

    func encodeResponse(for _: Request) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let wire = Wire(
            ok: true,
            data: data,
            meta: Meta(requestId: requestID ?? "req_" + String.randomHex(length: 12), timestamp: Date())
        )
        let bytes = try encoder.encode(wire)
        let response = Response(status: .ok, body: .init(data: bytes))
        response.headers.contentType = .json
        return response
    }

    private struct Wire: Encodable {
        let ok: Bool
        let data: T
        let meta: Meta
    }

    private struct Meta: Encodable {
        let requestId: String
        let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case timestamp
        }
    }
}
