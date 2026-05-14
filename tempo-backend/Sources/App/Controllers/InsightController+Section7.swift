import Fluent
import Vapor

// MARK: - InsightController §7 routes
//
// Per INTELLIGENCE_REMEDIATION_PLAN.md §7. The original InsightController only
// shipped weekly-report / patterns / drill-sergeant. This extension adds the
// remaining 7 AI features:
//
//   POST /v1/insights/recovery-prescription   §3.6 Haiku  cache 12h Redis
//   GET  /v1/insights/morning-briefing        §3.1 Template + Haiku fallback
//   POST /v1/insights/training-adjustment     §3.11 Haiku no-cache
//   GET  /v1/insights/dashboard               §3.10 Haiku cache by data hash
//   POST /v1/insights/training-program        §3.5 Sonnet cache 7d Postgres
//   POST /v1/insights/study-schedule          §3.7 Sonnet cache until exam edit
//   POST /v1/insights/achievement-copy        §3.9 Haiku cache forever
//
// All inputs are JSON in the request body (or query params for GET). Inputs
// are pre-aggregated by iOS — the backend doesn't redo the cross-domain joins
// per spec §4.1, it trusts the caller to assemble the prompt-ready payload.

extension InsightController {

    // MARK: §3.6 Recovery Prescription

    @Sendable
    func recoveryPrescription(req: Request) async throws -> Envelope<RecoveryPrescriptionResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        var input = try req.content.decode(RecoveryPrescriptionInput.self)
        // Stamp the userId server-side; clients should not be trusted to set it.
        input.userId = userId

        let bypass = req.query[Bool.self, at: "force_regenerate"] ?? false
        let result = try await RecoveryPrescriptionService.shared.generate(
            input: input, on: req, bypassCache: bypass
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.1 Morning Briefing

    @Sendable
    func morningBriefing(req: Request) async throws -> Envelope<MorningBriefingResponse> {
        let userId = try req.auth.requireUserID()
        // Template-first. Decoded from query params for the simple case;
        // for richer contexts the iOS client can POST to a future route.
        let date = req.query[String.self, at: "date"] ?? ISO8601DateFormatter().string(from: Date()).prefix(10).description
        let input = try MorningBriefingService.shared.extractContext(from: req, userId: userId, date: date)
        let result = try await MorningBriefingService.shared.generate(input: input, on: req)
        // Morning briefing does not count against the 12-call/day AI limit
        // because it's template-first (free). Only the Haiku fallback bills.
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.11 Training Adjustment

    @Sendable
    func trainingAdjustment(req: Request) async throws -> Envelope<TrainingAdjustmentResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        let body = try req.content.decode(TrainingAdjustmentInput.self)
        let result = try await TrainingAdjustmentService.shared.generate(
            input: body.withUserID(userId), on: req
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.10 Dashboard Insights

    @Sendable
    func dashboardInsights(req: Request) async throws -> Envelope<DashboardInsightsResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        let input = try DashboardInsightsService.shared.extractContext(from: req, userId: userId)
        let bypass = req.query[Bool.self, at: "force_regenerate"] ?? false
        let result = try await DashboardInsightsService.shared.generate(
            input: input, on: req, bypassCache: bypass
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.5 Training Program

    @Sendable
    func trainingProgram(req: Request) async throws -> Envelope<TrainingProgramResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        let body = try req.content.decode(TrainingProgramInput.self)
        let bypass = req.query[Bool.self, at: "force_regenerate"] ?? false
        let result = try await TrainingProgramService.shared.generate(
            input: body.withUserID(userId), on: req, bypassCache: bypass
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.7 Study Schedule

    @Sendable
    func studySchedule(req: Request) async throws -> Envelope<StudyScheduleResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        let body = try req.content.decode(StudyScheduleInput.self)
        let bypass = req.query[Bool.self, at: "force_regenerate"] ?? false
        let result = try await StudyScheduleService.shared.generate(
            input: body.withUserID(userId), on: req, bypassCache: bypass
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: §3.9 Achievement Copy

    @Sendable
    func achievementCopy(req: Request) async throws -> Envelope<AchievementCopyResponse> {
        let userId = try req.auth.requireUserID()
        try await checkDailyAILimit(userID: userId, on: req)

        let body = try req.content.decode(AchievementCopyInput.self)
        let result = try await AchievementCopyService.shared.generate(
            input: body.withUserID(userId), on: req
        )
        await incrementDailyAICount(userID: userId, on: req)
        return Envelope(data: result, requestID: req.requestID)
    }
}
