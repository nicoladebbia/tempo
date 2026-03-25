import Vapor
import Fluent
@preconcurrency import Redis

// MARK: - Insight Controller
// Per BUILD_PLAN step 15.1 — Claude API backend endpoints.
// Per AI_INTELLIGENCE_ENGINE.md — Weekly report, patterns, drill-sergeant.
// Rate limited: 10 AI requests per user per day.

struct InsightController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("weekly-report", use: weeklyReport)
        routes.get("patterns", use: patterns)
        routes.get("drill-sergeant", use: drillSergeant)
    }

    // MARK: - GET /v1/insights/weekly-report
    // Per AI_INTELLIGENCE_ENGINE.md Section 3.2 — Generate weekly report.
    // Per BUILD_PLAN 15.1 — Sonnet 4.6, cached per week.

    func weeklyReport(req: Request) async throws -> Envelope<WeeklyReportResponse> {
        let userID = try req.auth.requireUserID()

        // Check daily AI rate limit
        try await checkDailyAILimit(userID: userID, on: req)

        // Check Redis cache first
        // Per AI_INTELLIGENCE_ENGINE.md Section 6.1 — cache key: insight:weekly:{user_id}:{week_start}
        let weekStart = currentWeekStart()
        let cacheKey = RedisKey("insight:weekly:\(userID):\(weekStart)")

        if let cached = try? await req.redis.get(cacheKey, as: String.self).get(),
           let jsonData = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let report = try? decoder.decode(WeeklyReportResponse.self, from: jsonData) {
                return Envelope(data: report, requestID: req.requestID)
            }
        }

        // Build input from user's data
        let input = try await buildWeeklyReportInput(userID: userID, weekStart: weekStart, on: req)

        // Generate report via InsightService
        let report = try await InsightService.shared.generateWeeklyReport(weekData: input, on: req)

        // Cache for 7 days
        // Per AI_INTELLIGENCE_ENGINE.md Section 6.1 — TTL 7 days
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(report),
           let jsonString = String(data: data, encoding: .utf8) {
            _ = try? await req.redis.set(cacheKey, to: jsonString).get()
            _ = try? await req.redis.expire(cacheKey, after: .seconds(7 * 24 * 3600)).get()
        }

        // Increment daily AI counter
        await incrementDailyAICount(userID: userID, on: req)

        return Envelope(data: report, requestID: req.requestID)
    }

    // MARK: - GET /v1/insights/patterns
    // Per AI_INTELLIGENCE_ENGINE.md Section 3.3 — Opus 4.6 pattern detection.

    func patterns(req: Request) async throws -> Envelope<PatternDetectionResponse> {
        let userID = try req.auth.requireUserID()

        try await checkDailyAILimit(userID: userID, on: req)

        // Check cache — 24h TTL per AI_INTELLIGENCE_ENGINE.md Section 6.1
        let cacheKey = RedisKey("insight:pattern:\(userID)")

        if let cached = try? await req.redis.get(cacheKey, as: String.self).get(),
           let jsonData = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let result = try? decoder.decode(PatternDetectionResponse.self, from: jsonData) {
                return Envelope(data: result, requestID: req.requestID)
            }
        }

        let input = try await buildPatternDetectionInput(userID: userID, on: req)

        let result = try await InsightService.shared.detectPatterns(input: input, on: req)

        // Cache for 24h
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(result),
           let jsonString = String(data: data, encoding: .utf8) {
            _ = try? await req.redis.set(cacheKey, to: jsonString).get()
            _ = try? await req.redis.expire(cacheKey, after: .seconds(24 * 3600)).get()
        }

        await incrementDailyAICount(userID: userID, on: req)

        return Envelope(data: result, requestID: req.requestID)
    }

    // MARK: - GET /v1/insights/drill-sergeant
    // Per AI_INTELLIGENCE_ENGINE.md Section 3.1 — Haiku 4.5 contextual drill-sergeant.

    func drillSergeant(req: Request) async throws -> Envelope<DrillSergeantResponse> {
        let userID = try req.auth.requireUserID()

        try await checkDailyAILimit(userID: userID, on: req)

        let context = try await buildDrillSergeantContext(userID: userID, on: req)

        let copy = try await InsightService.shared.generateDrillSergeantCopy(context: context, on: req)

        await incrementDailyAICount(userID: userID, on: req)

        return Envelope(
            data: DrillSergeantResponse(copy: copy, isDegraded: false),
            requestID: req.requestID
        )
    }

    // MARK: - Rate Limiting
    // Per AI_INTELLIGENCE_ENGINE.md Section 2.5 — 12 AI calls per user per day.

    private func checkDailyAILimit(userID: String, on req: Request) async throws {
        let key = RedisKey("ai_limit:\(userID):\(todayString())")
        let count = (try? await req.redis.get(key, as: Int.self).get()) ?? 0
        guard count < AIConfig.dailyPerUserLimit else {
            throw Abort(.tooManyRequests, reason: "Daily AI request limit reached (\(AIConfig.dailyPerUserLimit)). Try again tomorrow.")
        }
    }

    private func incrementDailyAICount(userID: String, on req: Request) async {
        let key = RedisKey("ai_limit:\(userID):\(todayString())")
        _ = try? await req.redis.increment(key).get()
        _ = try? await req.redis.expire(key, after: .seconds(24 * 3600)).get()
    }

    // MARK: - Data Builders

    private func buildWeeklyReportInput(
        userID: String,
        weekStart: String,
        on req: Request
    ) async throws -> WeeklyReportInput {
        // Fetch user for streak/level/XP
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        // Calculate week boundaries
        let calendar = Calendar.current
        let today = Date()
        let weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekEndDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? today

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let weekEnd = formatter.string(from: weekEndDate)

        // Fetch XP events for this week to compute weekly XP
        let weeklyEvents = try await XPEvent.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$createdAt >= weekStartDate)
            .all()
        let weeklyXP = weeklyEvents.reduce(into: 0) { $0 += $1.multipliedXP }

        // Simplified input — in production, this would query recovery, sleep, nutrition, study data
        return WeeklyReportInput(
            userID: userID,
            weekStart: weekStart,
            weekEnd: weekEnd,
            streakDays: user.streakDays,
            level: user.level,
            xpTotal: user.xpTotal,
            avgScore: 75,  // TODO: Compute from daily snapshots when available
            daysWithData: 7,
            avgRecovery: 72,  // TODO: Query from Whoop recovery data
            avgSleepHours: 7.0,
            avgCompletionPct: 80,
            workoutCount: 5,
            proteinAdherencePct: 70,
            avgStudyMinutes: 90,
            studyTarget: 120,
            weeklyXP: weeklyXP,
            prevAvgRecovery: 75,
            prevAvgSleepHours: 7.2,
            prevWorkoutCount: 5,
            prevWeeklyXP: max(0, weeklyXP - 50),
            prevProteinAdherencePct: 75,
            prevAvgStudyMinutes: 100,
            prevAvgCompletionPct: 85
        )
    }

    private func buildPatternDetectionInput(
        userID: String,
        on req: Request
    ) async throws -> PatternDetectionInput {
        // In production, this would query 30-90 days of cross-domain data
        // and pre-compute Pearson correlations server-side.
        // Per AI_INTELLIGENCE_ENGINE.md Section 3.3 — min 14 days.
        return PatternDetectionInput(
            userID: userID,
            totalDays: 0,  // Will return insufficient data until real data pipeline is wired
            daysWithRecovery: 0,
            daysWithNutrition: 0,
            daysWithStudy: 0,
            dailyData: "",
            precomputedStats: "",
            precomputedCorrelations: ""
        )
    }

    private func buildDrillSergeantContext(
        userID: String,
        on req: Request
    ) async throws -> DrillSergeantContext {
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour < 12 { timeOfDay = "morning" }
        else if hour < 17 { timeOfDay = "afternoon" }
        else { timeOfDay = "evening" }

        return DrillSergeantContext(
            recoveryScore: 72,  // TODO: Query latest Whoop recovery
            recoveryZone: "yellow",
            streakDays: user.streakDays,
            workoutType: "Training",  // TODO: Query today's planned workout
            remainingTasks: 3,  // TODO: Query from non-negotiables
            totalTasks: 4,
            yesterdayCompletion: 85,  // TODO: Query yesterday's completion
            timeOfDay: timeOfDay,
            examContext: nil  // TODO: Query upcoming exams
        )
    }

    // MARK: - Helpers

    private func currentWeekStart() -> String {
        let calendar = Calendar.current
        let weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: weekStartDate)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Response DTOs

struct DrillSergeantResponse: Content {
    let copy: String
    let isDegraded: Bool
}
