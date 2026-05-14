import Vapor
@preconcurrency import Redis

// MARK: - Insight Service
// Per AI_INTELLIGENCE_ENGINE.md Section 2 — Claude API client for all AI features.
// Per ADR-018 — Claude API over on-device ML.
// Per APP_STORE_COMPLIANCE.md Section 1 — AI data sent only with user consent.

actor InsightService {

    static let shared = InsightService()

    // MARK: - Circuit Breaker State
    // Per AI_INTELLIGENCE_ENGINE.md Section 2.4 — Per-model circuit breakers.

    private var haikuCircuitBreaker = CircuitBreaker()
    private var sonnetCircuitBreaker = CircuitBreaker()
    private var opusCircuitBreaker = CircuitBreaker()

    // Budget tracking now lives in `AIBudgetTracker.shared` — a Postgres-backed
    // actor that survives restarts and is shared across replicas. Per
    // INTELLIGENCE_REMEDIATION_PLAN.md §5.

    // MARK: - Public API

    /// Generate a weekly report analysis.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 3.2 — Sonnet 4.6, temp 0.4, structured JSON.
    func generateWeeklyReport(
        weekData: WeeklyReportInput,
        on req: Request
    ) async throws -> WeeklyReportResponse {
        let breaker = circuitBreaker(for: AIConfig.sonnetModel)
        guard breaker.state != .open else {
            req.logger.warning("Sonnet circuit breaker OPEN — using fallback for weekly report")
            return generateFallbackWeeklyReport(weekData)
        }

        // Pre-flight budget gate. Per AI_INTELLIGENCE_ENGINE.md §5.4.
        let estimate = AIBudgetEstimate.sonnet(maxTokens: 2_000, estimatedInputTokens: 4_000)
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) else {
            req.logger.warning("AI budget exhausted — using fallback for weekly report")
            return generateFallbackWeeklyReport(weekData)
        }

        let systemPrompt = WeeklyReportPrompts.system
        let userPrompt = WeeklyReportPrompts.buildUserPrompt(from: weekData)

        do {
            let response = try await callClaude(
                model: AIConfig.sonnetModel,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: 0.4,
                maxTokens: 2000,
                timeout: AIConfig.sonnetTimeout,
                on: req
            )

            // Parse JSON response
            guard let data = response.content.data(using: .utf8) else {
                throw InsightError.malformedResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let report = try decoder.decode(WeeklyReportResponse.self, from: data)

            recordSuccess(for: AIConfig.sonnetModel)
            return report
        } catch {
            recordFailure(for: AIConfig.sonnetModel)

            // Retry once with simplified prompt per Section 2.3
            if let insightError = error as? InsightError, insightError == .malformedResponse {
                req.logger.warning("Malformed JSON from weekly report — retrying with simplified prompt")
                do {
                    let retryResponse = try await callClaude(
                        model: AIConfig.sonnetModel,
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt + "\n\nCRITICAL: Return ONLY valid JSON. No markdown, no code blocks, no explanatory text. Start your response with { and end with }.",
                        temperature: 0.4,
                        maxTokens: 2000,
                        timeout: AIConfig.sonnetTimeout,
                        on: req
                    )

                    if let retryData = retryResponse.content.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        let report = try decoder.decode(WeeklyReportResponse.self, from: retryData)
                        recordSuccess(for: AIConfig.sonnetModel)
                        return report
                    }
                } catch {
                    req.logger.error("Weekly report retry also failed: \(error)")
                }
            }

            req.logger.error("Weekly report generation failed: \(error) — using fallback")
            return generateFallbackWeeklyReport(weekData)
        }
    }

    /// Detect behavioral patterns from multi-week data.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 3.3 — Opus 4.6, temp 0.3.
    func detectPatterns(
        input: PatternDetectionInput,
        on req: Request
    ) async throws -> PatternDetectionResponse {
        let breaker = circuitBreaker(for: AIConfig.opusModel)
        guard breaker.state != .open else {
            req.logger.warning("Opus circuit breaker OPEN — using fallback for patterns")
            return PatternDetectionResponse.fallback(totalDays: input.totalDays)
        }

        // Pattern detection is the most expensive feature (Opus). Use a
        // tighter estimate so this is the FIRST thing the budget gate
        // disables when funds run low.
        let estimate = AIBudgetEstimate.opus(maxTokens: 1_500, estimatedInputTokens: 6_000)
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) else {
            req.logger.warning("AI budget exhausted — using fallback for pattern detection")
            return PatternDetectionResponse.fallback(totalDays: input.totalDays)
        }

        // Threshold ladder: at caution (80%+), downgrade Opus to Sonnet.
        // Per AI_INTELLIGENCE_ENGINE.md §5.4 + §5.5 #8.
        let throttle = await AIBudgetTracker.shared.currentThrottleLevel(on: req)

        guard input.totalDays >= 14 else {
            return PatternDetectionResponse(
                patterns: [],
                dataQuality: DataQuality(
                    totalDays: input.totalDays,
                    daysWithRecovery: input.daysWithRecovery,
                    daysWithNutrition: input.daysWithNutrition,
                    daysWithStudy: input.daysWithStudy,
                    sufficientForAnalysis: false
                ),
                topInsight: "Need at least 14 days of data for pattern detection."
            )
        }

        let systemPrompt = PatternDetectionPrompts.system
        let userPrompt = PatternDetectionPrompts.buildUserPrompt(from: input)

        // Threshold ladder: at caution+ (80%+), downgrade Opus to Sonnet to
        // cut cost by ~5x while preserving the feature. Per spec §5.5 #8.
        let useDowngraded = throttle.rawValue >= AIBudgetTracker.ThrottleLevel.caution.rawValue
        let chosenModel = useDowngraded ? AIConfig.sonnetModel : AIConfig.opusModel
        let chosenTimeout = useDowngraded ? AIConfig.sonnetTimeout : AIConfig.opusTimeout
        if useDowngraded {
            req.logger.warning("Pattern detection: budget caution — downgrading Opus to Sonnet")
        }

        do {
            let response = try await callClaude(
                model: chosenModel,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: 0.3,
                maxTokens: 1500,
                timeout: chosenTimeout,
                on: req
            )

            guard let data = response.content.data(using: .utf8) else {
                throw InsightError.malformedResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(PatternDetectionResponse.self, from: data)
            recordSuccess(for: chosenModel)
            return result
        } catch {
            recordFailure(for: chosenModel)
            req.logger.error("Pattern detection failed: \(error) — using fallback")
            return PatternDetectionResponse.fallback(totalDays: input.totalDays)
        }
    }

    /// Generate contextual drill-sergeant copy.
    /// Per AI_INTELLIGENCE_ENGINE.md Section 3.1 — Haiku 4.5 fallback for morning briefing.
    func generateDrillSergeantCopy(
        context: DrillSergeantContext,
        on req: Request
    ) async throws -> String {
        let breaker = circuitBreaker(for: AIConfig.haikuModel)
        guard breaker.state != .open else {
            return generateFallbackDrillSergeant(context)
        }

        // Pre-flight budget gate.
        let estimate = AIBudgetEstimate.haiku(maxTokens: 200, estimatedInputTokens: 1_500)
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) else {
            req.logger.warning("AI budget exhausted — using fallback for drill sergeant")
            return generateFallbackDrillSergeant(context)
        }

        let systemPrompt = """
        You are a no-nonsense drill sergeant and performance coach inside the Tempo app. \
        You deliver motivational push based on the user's current data. \
        Direct and commanding. Short sentences. No fluff. \
        Specific — reference exact numbers from the provided data. \
        NEVER use emojis. NEVER give medical advice. \
        Output ONLY the copy text. No greetings, no labels. 3-5 sentences, 40-60 words.
        """

        let userPrompt = """
        Recovery: \(context.recoveryScore)% (\(context.recoveryZone))
        Streak: \(context.streakDays) days
        Today's workout: \(context.workoutType)
        Non-negotiables remaining: \(context.remainingTasks)/\(context.totalTasks)
        Yesterday completion: \(context.yesterdayCompletion)%
        Time of day: \(context.timeOfDay)
        \(context.examContext ?? "")

        Generate a drill-sergeant motivational message for this moment.
        """

        do {
            let response = try await callClaude(
                model: AIConfig.haikuModel,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: 0.7,
                maxTokens: 300,
                timeout: AIConfig.haikuTimeout,
                on: req
            )

            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(separator: " ").count
            guard wordCount >= 20 && wordCount <= 80 else {
                return generateFallbackDrillSergeant(context)
            }

            recordSuccess(for: AIConfig.haikuModel)
            return trimmed
        } catch {
            recordFailure(for: AIConfig.haikuModel)
            return generateFallbackDrillSergeant(context)
        }
    }

    // MARK: - Core Claude API Call
    // Per AI_INTELLIGENCE_ENGINE.md Section 2.5 — HTTP call to Anthropic Messages API.

    private func callClaude(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval,
        on req: Request
    ) async throws -> ClaudeAPIResponse {
        guard let apiKey = Environment.get("ANTHROPIC_API_KEY") else {
            throw InsightError.missingAPIKey
        }

        let requestBody = ClaudeAPIRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: userPrompt)
            ]
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(requestBody)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(name: "anthropic-version", value: "2023-06-01")

        let response = try await req.client.post(
            URI(string: "https://api.anthropic.com/v1/messages"),
            headers: headers
        ) { clientReq in
            clientReq.body = .init(data: bodyData)
        }

        guard response.status == .ok else {
            let statusCode = response.status.code
            // Per Section 2.3 — retry on 429, 500, 502, 503, 529; don't retry on 400, 401, 404
            if statusCode == 429 || statusCode >= 500 {
                throw InsightError.serverError(Int(statusCode))
            }
            throw InsightError.apiError(Int(statusCode), response.body.map { String(buffer: $0) } ?? "Unknown error")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiResponse = try response.content.decode(ClaudeAPIRawResponse.self, using: decoder)

        // Track token usage against the persistent monthly budget.
        // Per AI_INTELLIGENCE_ENGINE.md §5.4 + INTELLIGENCE_REMEDIATION_PLAN.md §5.
        await AIBudgetTracker.shared.recordSpend(
            model: model,
            inputTokens: apiResponse.usage.inputTokens,
            outputTokens: apiResponse.usage.outputTokens,
            on: req
        )

        // Extract text content
        guard let textBlock = apiResponse.content.first(where: { $0.type == "text" }) else {
            throw InsightError.malformedResponse
        }

        // Try to extract JSON from markdown code blocks if present
        let content = extractJSON(from: textBlock.text)

        return ClaudeAPIResponse(
            content: content,
            inputTokens: apiResponse.usage.inputTokens,
            outputTokens: apiResponse.usage.outputTokens,
            model: model
        )
    }

    // MARK: - JSON Extraction
    // Per AI_INTELLIGENCE_ENGINE.md Section 2.3 — Extract JSON from markdown wrapping.

    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Already valid JSON start
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }

        // Try to find JSON between code block markers
        if let jsonStart = trimmed.range(of: "{"),
           let jsonEnd = trimmed.range(of: "}", options: .backwards) {
            return String(trimmed[jsonStart.lowerBound...jsonEnd.upperBound])
        }

        return trimmed
    }

    // Budget tracking moved to AIBudgetTracker.shared — see file header.
    // Per INTELLIGENCE_REMEDIATION_PLAN.md §5.

    // MARK: - Circuit Breaker
    // Per AI_INTELLIGENCE_ENGINE.md Section 2.4 — Independent per-model breakers.

    private func circuitBreaker(for model: String) -> CircuitBreaker {
        switch model {
        case AIConfig.haikuModel: return haikuCircuitBreaker
        case AIConfig.sonnetModel: return sonnetCircuitBreaker
        case AIConfig.opusModel: return opusCircuitBreaker
        default: return haikuCircuitBreaker
        }
    }

    private func recordSuccess(for model: String) {
        switch model {
        case AIConfig.haikuModel: haikuCircuitBreaker.recordSuccess()
        case AIConfig.sonnetModel: sonnetCircuitBreaker.recordSuccess()
        case AIConfig.opusModel: opusCircuitBreaker.recordSuccess()
        default: break
        }
    }

    private func recordFailure(for model: String) {
        switch model {
        case AIConfig.haikuModel: haikuCircuitBreaker.recordFailure()
        case AIConfig.sonnetModel: sonnetCircuitBreaker.recordFailure()
        case AIConfig.opusModel: opusCircuitBreaker.recordFailure()
        default: break
        }
    }

    // MARK: - Fallbacks
    // Per AI_INTELLIGENCE_ENGINE.md Section 8 — Algorithmic fallbacks.

    private func generateFallbackWeeklyReport(_ input: WeeklyReportInput) -> WeeklyReportResponse {
        let title: String
        if input.avgScore >= 90 { title = "Dominant week across the board" }
        else if input.avgScore >= 75 { title = "Solid week with room to grow" }
        else if input.avgScore >= 60 { title = "Average week -- time to lock in" }
        else { title = "Below the line -- reset starts now" }

        let recoveryDelta = input.avgRecovery - input.prevAvgRecovery
        let recoverySentiment: String = recoveryDelta >= 0 ? "positive" : "warning"

        return WeeklyReportResponse(
            title: title,
            summary: "This week you scored an average of \(input.avgScore)/100 across \(input.daysWithData) days. " +
                     "Recovery averaged \(input.avgRecovery)% and you completed \(input.avgCompletionPct)% of non-negotiables.",
            sections: [
                ReportSection(
                    title: "Recovery & Sleep",
                    icon: "bed.double.fill",
                    body: "Average recovery: \(input.avgRecovery)% (\(recoveryDelta >= 0 ? "+" : "")\(recoveryDelta)% vs last week). " +
                          "Sleep averaged \(String(format: "%.1f", input.avgSleepHours))h.",
                    sentiment: recoverySentiment
                ),
                ReportSection(
                    title: "Fitness",
                    icon: "flame.fill",
                    body: "\(input.workoutCount) workouts completed this week.",
                    sentiment: input.workoutCount >= 4 ? "positive" : "warning"
                ),
                ReportSection(
                    title: "Nutrition",
                    icon: "fork.knife",
                    body: "Protein target hit \(input.proteinAdherencePct)% of days.",
                    sentiment: input.proteinAdherencePct >= 70 ? "positive" : "warning"
                ),
                ReportSection(
                    title: "Academics",
                    icon: "book.fill",
                    body: "Average daily study: \(input.avgStudyMinutes) minutes.",
                    sentiment: input.avgStudyMinutes >= input.studyTarget ? "positive" : "warning"
                ),
            ],
            actionItems: generateFallbackActionItems(input),
            comparedToLastWeek: WeekOverWeekDeltas(
                recoveryAvgChange: recoveryDelta,
                sleepAvgChangeMin: Int((input.avgSleepHours - input.prevAvgSleepHours) * 60),
                workoutCountChange: input.workoutCount - input.prevWorkoutCount,
                xpChange: input.weeklyXP - input.prevWeeklyXP,
                proteinAdherenceChange: input.proteinAdherencePct - input.prevProteinAdherencePct,
                studyAvgChangeMin: input.avgStudyMinutes - input.prevAvgStudyMinutes,
                completionPctChange: input.avgCompletionPct - input.prevAvgCompletionPct
            )
        )
    }

    private func generateFallbackActionItems(_ input: WeeklyReportInput) -> [String] {
        var items: [String] = []
        if input.avgSleepHours < 7.0 {
            items.append("Set a bedtime alarm for 23:30. Your sleep averaged \(String(format: "%.1f", input.avgSleepHours))h — below the 7h minimum.")
        }
        if input.proteinAdherencePct < 70 {
            items.append("Pre-prepare a protein source for your 4th meal. You missed your protein target on \(100 - input.proteinAdherencePct)% of days.")
        }
        if input.avgCompletionPct < 85 {
            items.append("Focus on completing all non-negotiables before evening. You averaged \(input.avgCompletionPct)% completion.")
        }
        // Pad to 3 items if needed
        if items.isEmpty { items.append("Maintain current momentum. Consistency is the goal.") }
        if items.count < 2 { items.append("Review your weakest day this week and identify what went wrong.") }
        if items.count < 3 { items.append("Set one specific improvement target for next week.") }
        return Array(items.prefix(3))
    }

    private func generateFallbackDrillSergeant(_ context: DrillSergeantContext) -> String {
        var parts: [String] = []

        switch context.recoveryZone {
        case "green":
            parts.append("Recovery at \(context.recoveryScore)%. Green light. Full send on \(context.workoutType) today.")
        case "yellow":
            parts.append("Recovery at \(context.recoveryScore)%. Yellow zone. \(context.workoutType) at reduced volume today.")
        case "red":
            parts.append("Recovery at \(context.recoveryScore)%. Red. Swapping to mobility. Your body needs it.")
        default:
            parts.append("Recovery at \(context.recoveryScore)%. Handle business.")
        }

        if context.remainingTasks > 0 {
            parts.append("\(context.remainingTasks) tasks remaining. No excuses.")
        }

        if context.streakDays > 0 {
            parts.append("Day \(context.streakDays + 1) of your streak. Don't break it.")
        }

        if let exam = context.examContext {
            parts.append(exam)
        }

        if context.yesterdayCompletion < 75 {
            parts.append("Yesterday was \(context.yesterdayCompletion)%. Better today.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Exposed helpers for AIFeatureRunner
    //
    // Per INTELLIGENCE_REMEDIATION_PLAN.md §7. These let AIFeatureRunner
    // share InsightService's circuit breaker and HTTP pipeline without
    // duplicating them. They wrap private methods declared above.

    func circuitBreakerState(for model: String) -> CircuitBreaker.State {
        circuitBreaker(for: model).state
    }

    func callClaudeRaw(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval,
        on req: Request
    ) async throws -> ClaudeAPIResponse {
        do {
            let response = try await callClaude(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maxTokens: maxTokens,
                timeout: timeout,
                on: req
            )
            recordSuccess(for: model)
            return response
        } catch {
            recordFailure(for: model)
            throw error
        }
    }
}

// MARK: - AI Configuration
// Per AI_INTELLIGENCE_ENGINE.md Section 2.5

struct AIConfig {
    static let haikuModel = "claude-haiku-4-5-20250901"
    static let sonnetModel = "claude-sonnet-4-6-20250514"
    static let opusModel = "claude-opus-4-6-20250901"

    /// Monthly Claude spend cap in cents. Default $50. Override at runtime via
    /// CLAUDE_MONTHLY_BUDGET_CENTS env var (used by AIBudgetTracker pre-flight
    /// gate). Per AI_INTELLIGENCE_ENGINE.md §5.4 + INTELLIGENCE_REMEDIATION_PLAN.md §5.
    static var monthlyBudgetCents: Int {
        Environment.get("CLAUDE_MONTHLY_BUDGET_CENTS").flatMap(Int.init) ?? 5000
    }
    static let dailyPerUserLimit = 12
    static let weeklyReportLimit = 3
    static let patternAnalysisLimit = 2

    static let maxRetries = 2
    static let baseRetryDelay: TimeInterval = 1.0
    static let backoffMultiplier: Double = 2.0

    static let haikuTimeout: TimeInterval = 5.0
    static let sonnetTimeout: TimeInterval = 30.0
    static let opusTimeout: TimeInterval = 60.0

    static let circuitBreakerFailureThreshold = 3
    static let circuitBreakerFailureWindow: TimeInterval = 600
    static let circuitBreakerRecoveryTimeout: TimeInterval = 1800
}

// MARK: - Circuit Breaker
// Per AI_INTELLIGENCE_ENGINE.md Section 2.4

struct CircuitBreaker {
    enum State {
        case closed, open, halfOpen
    }

    var state: State = .closed
    private var failureCount: Int = 0
    private var lastFailure: Date?
    private var halfOpenSuccessCount: Int = 0

    mutating func recordFailure() {
        failureCount += 1
        lastFailure = Date()
        if failureCount >= AIConfig.circuitBreakerFailureThreshold {
            state = .open
        }
    }

    mutating func recordSuccess() {
        switch state {
        case .closed:
            failureCount = 0
        case .halfOpen:
            halfOpenSuccessCount += 1
            if halfOpenSuccessCount >= 2 {
                state = .closed
                failureCount = 0
                halfOpenSuccessCount = 0
            }
        case .open:
            break
        }
    }

    mutating func checkRecovery() {
        guard state == .open, let lastFailure else { return }
        if Date().timeIntervalSince(lastFailure) >= AIConfig.circuitBreakerRecoveryTimeout {
            state = .halfOpen
            halfOpenSuccessCount = 0
        }
    }
}

// MARK: - Claude API Types

struct ClaudeAPIRequest: Content {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [ClaudeMessage]
}

struct ClaudeMessage: Content {
    let role: String
    let content: String
}

struct ClaudeAPIRawResponse: Content {
    let id: String
    let type: String
    let role: String
    let content: [ClaudeContentBlock]
    let model: String
    let usage: ClaudeUsage
}

struct ClaudeContentBlock: Content {
    let type: String
    let text: String
}

struct ClaudeUsage: Content {
    let inputTokens: Int
    let outputTokens: Int
}

struct ClaudeAPIResponse {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
    let model: String
}

// MARK: - Insight Errors

enum InsightError: Error, Equatable {
    case missingAPIKey
    case malformedResponse
    case serverError(Int)
    case apiError(Int, String)
    case budgetExhausted
    case insufficientData
}

// MARK: - Weekly Report DTOs
// Per AI_INTELLIGENCE_ENGINE.md Section 3.2

struct WeeklyReportInput {
    let userID: String
    let weekStart: String
    let weekEnd: String
    let streakDays: Int
    let level: Int
    let xpTotal: Int
    let avgScore: Int
    let daysWithData: Int
    let avgRecovery: Int
    let avgSleepHours: Double
    let avgCompletionPct: Int
    let workoutCount: Int
    let proteinAdherencePct: Int
    let avgStudyMinutes: Int
    let studyTarget: Int
    let weeklyXP: Int
    // Previous week for comparison
    let prevAvgRecovery: Int
    let prevAvgSleepHours: Double
    let prevWorkoutCount: Int
    let prevWeeklyXP: Int
    let prevProteinAdherencePct: Int
    let prevAvgStudyMinutes: Int
    let prevAvgCompletionPct: Int
}

struct WeeklyReportResponse: Content {
    let title: String
    let summary: String
    let sections: [ReportSection]
    let actionItems: [String]
    let comparedToLastWeek: WeekOverWeekDeltas
}

struct ReportSection: Content {
    let title: String
    let icon: String
    let body: String
    let sentiment: String
}

struct WeekOverWeekDeltas: Content {
    let recoveryAvgChange: Int
    let sleepAvgChangeMin: Int
    let workoutCountChange: Int
    let xpChange: Int
    let proteinAdherenceChange: Int
    let studyAvgChangeMin: Int
    let completionPctChange: Int
}

// MARK: - Pattern Detection DTOs
// Per AI_INTELLIGENCE_ENGINE.md Section 3.3

struct PatternDetectionInput {
    let userID: String
    let totalDays: Int
    let daysWithRecovery: Int
    let daysWithNutrition: Int
    let daysWithStudy: Int
    let dailyData: String  // Pre-formatted pipe-delimited string
    let precomputedStats: String
    let precomputedCorrelations: String
}

struct PatternDetectionResponse: Content {
    let patterns: [DetectedPattern]
    let dataQuality: DataQuality
    let topInsight: String

    static func fallback(totalDays: Int) -> PatternDetectionResponse {
        PatternDetectionResponse(
            patterns: [],
            dataQuality: DataQuality(
                totalDays: totalDays,
                daysWithRecovery: 0,
                daysWithNutrition: 0,
                daysWithStudy: 0,
                sufficientForAnalysis: false
            ),
            topInsight: "AI pattern detection temporarily unavailable. Showing standard analysis."
        )
    }
}

struct DetectedPattern: Content {
    let id: String
    let type: String  // "correlation", "behavioral", "temporal"
    let trigger: String
    let outcome: String
    let confidence: Double
    let occurrences: Int
    let recommendation: String
    let correlationR: Double?
}

struct DataQuality: Content {
    let totalDays: Int
    let daysWithRecovery: Int
    let daysWithNutrition: Int
    let daysWithStudy: Int
    let sufficientForAnalysis: Bool
}

// MARK: - Drill Sergeant DTOs

struct DrillSergeantContext {
    let recoveryScore: Int
    let recoveryZone: String
    let streakDays: Int
    let workoutType: String
    let remainingTasks: Int
    let totalTasks: Int
    let yesterdayCompletion: Int
    let timeOfDay: String
    let examContext: String?
}

// MARK: - Prompt Templates
// Per AI_INTELLIGENCE_ENGINE.md Section 3.2

enum WeeklyReportPrompts {
    static let system = """
    You are an elite performance analyst inside the Tempo app. You analyze one week of biometric, \
    nutrition, academic, and fitness data for a university student-athlete. Your analysis powers a \
    weekly report that the user reads every Sunday evening.

    Responsibilities:
    1. Provide a one-line title (max 60 chars) summarizing the week's dominant theme.
    2. Write a 2-3 sentence executive summary.
    3. Write analysis sections for each domain: Recovery & Sleep, Fitness, Nutrition, Academics. \
    Each section should be 2-4 sentences with specific numbers, dates, and comparisons.
    4. Identify 3 actionable recommendations that are specific, measurable, and tied to patterns in the data.
    5. Compute week-over-week comparison deltas for key metrics.

    Tone: Analytical and precise. Encouraging but honest. Use drill-sergeant tone only for action items.
    Do not use emojis. Do not give medical advice.

    For SF Symbol icon names, use ONLY: "bed.double.fill" (recovery/sleep), "flame.fill" (fitness), \
    "fork.knife" (nutrition), "book.fill" (academics).

    Output ONLY valid JSON matching the schema. No markdown code blocks, no explanatory text. \
    Start with { and end with }.
    """

    static func buildUserPrompt(from input: WeeklyReportInput) -> String {
        """
        Analyze this week's data and generate the weekly report. Reference ONLY the data provided.

        USER CONTEXT:
        - Streak: \(input.streakDays) days
        - Level: \(input.level) (\(input.xpTotal) XP)
        - Period: \(input.weekStart) to \(input.weekEnd)

        THIS WEEK SUMMARY:
        - Days with data: \(input.daysWithData)
        - Average daily score: \(input.avgScore)/100
        - Average recovery: \(input.avgRecovery)%
        - Average sleep: \(String(format: "%.1f", input.avgSleepHours))h
        - Workouts: \(input.workoutCount)
        - Protein adherence: \(input.proteinAdherencePct)% of days hitting target
        - Average study: \(input.avgStudyMinutes) min/day (target: \(input.studyTarget))
        - Non-negotiable completion: \(input.avgCompletionPct)%
        - Weekly XP: \(input.weeklyXP)

        LAST WEEK (for comparison):
        - Recovery: \(input.prevAvgRecovery)%
        - Sleep: \(String(format: "%.1f", input.prevAvgSleepHours))h
        - Workouts: \(input.prevWorkoutCount)
        - Protein adherence: \(input.prevProteinAdherencePct)%
        - Study: \(input.prevAvgStudyMinutes) min/day
        - Completion: \(input.prevAvgCompletionPct)%
        - XP: \(input.prevWeeklyXP)

        Respond with a JSON object:
        {
          "title": "string (max 60 chars)",
          "summary": "string (2-3 sentences)",
          "sections": [
            {"title": "Recovery & Sleep"|"Fitness"|"Nutrition"|"Academics", "icon": "bed.double.fill"|"flame.fill"|"fork.knife"|"book.fill", "body": "string", "sentiment": "positive"|"warning"|"negative"}
          ],
          "action_items": ["string (exactly 3 items)"],
          "compared_to_last_week": {
            "recovery_avg_change": number,
            "sleep_avg_change_min": number,
            "workout_count_change": number,
            "xp_change": number,
            "protein_adherence_change": number,
            "study_avg_change_min": number,
            "completion_pct_change": number
          }
        }
        """
    }
}

// Per AI_INTELLIGENCE_ENGINE.md Section 3.3

enum PatternDetectionPrompts {
    static let system = """
    You are a data scientist specializing in behavioral pattern detection for a health and \
    performance app. You receive compressed multi-week data and pre-computed statistics from a \
    university student-athlete. Your job is to find statistically meaningful patterns and \
    cross-domain correlations that the user would not notice on their own.

    Rules:
    - Only report patterns with at least 5 occurrences.
    - Only report correlations where |r| >= 0.5.
    - Maximum 6 patterns, ranked by confidence.
    - Say "correlates with" or "is followed by", NEVER "causes".
    - Output ONLY valid JSON. No markdown wrapping. Start with { and end with }.
    - NEVER invent data points.
    - NEVER give medical advice.
    """

    static func buildUserPrompt(from input: PatternDetectionInput) -> String {
        """
        Analyze this data for behavioral patterns and correlations.

        Data period: \(input.totalDays) days

        \(input.dailyData)

        Pre-computed stats:
        \(input.precomputedStats)

        Pre-computed correlations:
        \(input.precomputedCorrelations)

        Return patterns as JSON:
        {
          "patterns": [
            {"id": "string", "type": "correlation"|"behavioral"|"temporal", "trigger": "string", \
        "outcome": "string", "confidence": number, "occurrences": number, \
        "recommendation": "string", "correlation_r": number|null}
          ],
          "data_quality": {"total_days": number, "days_with_recovery": number, \
        "days_with_nutrition": number, "days_with_study": number, "sufficient_for_analysis": boolean},
          "top_insight": "string"
        }
        """
    }
}
