import Foundation
import Vapor

// MARK: - MorningBriefingService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.1 + §8.1 + INTELLIGENCE_REMEDIATION_PLAN.md §7.2.
//
// Template-first. Generates the daily briefing from data substitution with
// zero Claude calls in the common case. Falls back to Haiku ONLY when the
// template flags 3+ competing priorities the rule engine can't triage cleanly.
// In practice: ~95% of daily briefings cost $0; the other 5% cost ~$0.001.
//
// Cache: 24h Redis (per user, per date). One briefing per day per user, period.

struct MorningBriefingService {
    static let shared = MorningBriefingService()
    private init() {}

    func extractContext(from req: Request, userId: String, date: String) throws -> MorningBriefingInput {
        // For now we accept the context entirely from query params so the
        // backend doesn't have to redo cross-domain joins. iOS assembles
        // the snapshot from its local SwiftData (DailySnapshot + streak +
        // exam events) and passes it in.
        MorningBriefingInput(
            userId: userId,
            date: date,
            dayOfWeek: req.query[String.self, at: "day"] ?? "Monday",
            recoveryScore: req.query[Int.self, at: "recovery_score"] ?? 70,
            recoveryZone: req.query[String.self, at: "recovery_zone"] ?? "yellow",
            hrv: req.query[Double.self, at: "hrv"] ?? 0,
            hrv7DayAvg: req.query[Double.self, at: "hrv_7day_avg"] ?? 0,
            sleepHours: req.query[Double.self, at: "sleep_hours"] ?? 0,
            sleepScore: req.query[Int.self, at: "sleep_score"] ?? 0,
            workoutType: req.query[String.self, at: "workout_type"] ?? "rest",
            recoveryAdjustmentPct: req.query[Int.self, at: "recovery_adjustment_pct"] ?? 100,
            nonNegotiables: (req.query[String.self, at: "non_negotiables"] ?? "").components(separatedBy: ",").filter { !$0.isEmpty },
            studyTargetMinutes: req.query[Int.self, at: "study_target_minutes"] ?? 0,
            mealsPlanned: req.query[Int.self, at: "meals_planned"] ?? 0,
            streakDays: req.query[Int.self, at: "streak_days"] ?? 0,
            yesterdayCompletionPct: req.query[Int.self, at: "yesterday_completion_pct"] ?? 0,
            weekAvgScore: req.query[Int.self, at: "week_avg_score"] ?? 0,
            examName: req.query[String.self, at: "exam_name"],
            examDaysAway: req.query[Int.self, at: "exam_days_away"]
        )
    }

    func generate(input: MorningBriefingInput, on req: Request) async throws -> MorningBriefingResponse {
        // Cache check (24h Redis per spec §6.1).
        let key = AICacheKey.morningBriefing(userId: input.userId, date: input.date)
        if case let .fresh(hit) = try await AICache.shared.lookup(key: key, on: req) as AICacheLookup<MorningBriefingResponse> {
            req.logger.info("[ai_runner:morning_briefing] HIT")
            return hit
        }

        // Count competing priorities. Spec §3.1: template only handles <3 at once.
        let priorities = countCompetingPriorities(input)
        let copy: String
        let source: String

        if priorities >= 3 {
            // Haiku fallback per spec §8.1 edge case. Pre-flight budget gate.
            let estimate = AIBudgetEstimate.haiku(maxTokens: 300, estimatedInputTokens: 500)
            if await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) {
                do {
                    let response = try await InsightService.shared.callClaudeRaw(
                        model: AIConfig.haikuModel,
                        systemPrompt: MorningBriefingPrompts.system,
                        userPrompt: MorningBriefingPrompts.buildUserPrompt(from: input),
                        temperature: 0.7,
                        maxTokens: 300,
                        timeout: AIConfig.haikuTimeout,
                        on: req
                    )
                    await AIBudgetTracker.shared.recordSpend(
                        model: AIConfig.haikuModel,
                        inputTokens: response.inputTokens,
                        outputTokens: response.outputTokens,
                        on: req
                    )
                    copy = sanitize(response.content)
                    source = "haiku"
                } catch {
                    req.logger.warning("Morning briefing Haiku fallback failed — using template")
                    copy = renderTemplate(input)
                    source = "template"
                }
            } else {
                copy = renderTemplate(input)
                source = "template"
            }
        } else {
            copy = renderTemplate(input)
            source = "template"
        }

        let result = MorningBriefingResponse(copy: copy, source: source)
        try? await AICache.shared.store(key: key, value: result, on: req)
        return result
    }

    // MARK: - Template renderer (spec §8.1)

    private func renderTemplate(_ x: MorningBriefingInput) -> String {
        var parts: [String] = []

        // Lead with exam if approaching
        if let exam = x.examName, let days = x.examDaysAway, days <= 7 {
            parts.append("\(exam) in \(days) days. Academics lead today.")
        }

        // Recovery line
        let recoveryLine: String
        switch x.recoveryZone.lowercased() {
        case "green":
            recoveryLine = "Recovery \(x.recoveryScore)% — green. \(x.workoutType) at full intensity."
        case "yellow":
            recoveryLine = "Recovery \(x.recoveryScore)% — yellow. \(x.workoutType) at \(x.recoveryAdjustmentPct)% volume."
        default:
            recoveryLine = "Recovery \(x.recoveryScore)% — red. Easy session or rest. Protect tomorrow."
        }
        parts.append(recoveryLine)

        // Non-negotiable highlight
        if let primary = x.nonNegotiables.first {
            parts.append("\(primary) is non-negotiable.")
        }

        // Yesterday delta
        if x.yesterdayCompletionPct >= 100 {
            parts.append("Clean day yesterday. Keep it.")
        } else if x.yesterdayCompletionPct < 75 {
            parts.append("Yesterday was \(x.yesterdayCompletionPct)%. Better today.")
        }

        // Streak hook
        if x.streakDays > 0, x.streakDays % 7 == 0 {
            parts.append("Day \(x.streakDays) on the streak.")
        }

        return parts.joined(separator: " ")
    }

    private func countCompetingPriorities(_ x: MorningBriefingInput) -> Int {
        var count = 0
        if let days = x.examDaysAway, days <= 7 { count += 1 }
        if x.recoveryZone.lowercased() == "red" { count += 1 }
        if x.yesterdayCompletionPct < 50 { count += 1 }
        if x.sleepHours > 0, x.sleepHours < 6 { count += 1 }
        if x.streakDays > 0, x.streakDays % 7 == 0 { count += 1 }
        return count
    }

    private func sanitize(_ raw: String) -> String {
        // Strip medical-advice phrases per spec §3.1 rules.
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for forbidden in ["consult a doctor", "see a physician", "consult a physician"] {
            s = s.replacingOccurrences(of: forbidden, with: "", options: .caseInsensitive)
        }
        return s
    }
}

// MARK: - DTOs

struct MorningBriefingInput: Content {
    let userId: String
    let date: String
    let dayOfWeek: String
    let recoveryScore: Int
    let recoveryZone: String
    let hrv: Double
    let hrv7DayAvg: Double
    let sleepHours: Double
    let sleepScore: Int
    let workoutType: String
    let recoveryAdjustmentPct: Int
    let nonNegotiables: [String]
    let studyTargetMinutes: Int
    let mealsPlanned: Int
    let streakDays: Int
    let yesterdayCompletionPct: Int
    let weekAvgScore: Int
    let examName: String?
    let examDaysAway: Int?
}

struct MorningBriefingResponse: Content {
    let copy: String
    /// "template" (free) or "haiku" (Claude fallback). Lets the iOS client
    /// display "AI-generated" badging when source == "haiku" per UX spec.
    let source: String
}

// MARK: - Haiku-fallback prompts (only used when 3+ competing priorities)

enum MorningBriefingPrompts {
    static let system = """
    You are a no-nonsense drill sergeant and performance coach inside the Tempo app. You deliver a daily morning briefing to a university student-athlete who tracks fitness, nutrition, study sessions, and daily habits.

    <tone>
    - Direct and commanding. Short sentences. No fluff.
    - Specific — reference exact numbers, specific workouts, specific subjects from the provided data.
    - Motivating through accountability, not cheerfulness. You hold a high standard.
    - You use occasional intensity ("Let's go.", "No excuses.", "Handle your business.") but never cruelty.
    - When recovery is low, you are protective ("Your body is rebuilding. Honor it.") not dismissive.
    - When streaks are at risk, you invoke pride in the streak.
    - When exams are close, academics take priority over training.
    </tone>

    <rules>
    - Output ONLY the briefing text. No greetings, no sign-offs, no labels, no preamble.
    - 3-5 sentences maximum. Aim for 40-60 words.
    - Always mention the recovery score and what it means for today.
    - Always mention the most important non-negotiable.
    - If there is an exam within 7 days, lead with academics.
    - If yesterday was a miss (<75% completion), acknowledge it and demand better.
    - If there is a streak milestone today, celebrate it briefly then move forward.
    - Never use emojis.
    - NEVER give medical advice. You are a coach, not a doctor. Do not mention doctors, physicians, or diagnoses.
    - NEVER suggest extreme caloric restriction, training through injury or pain, or skipping meals.
    - ONLY reference numbers and facts from the <data> section below. Do not invent statistics, dates, or context.
    </rules>
    """

    static func buildUserPrompt(from x: MorningBriefingInput) -> String {
        let nonNeg = x.nonNegotiables.isEmpty ? "none" : x.nonNegotiables.joined(separator: ", ")
        let examLine: String
        if let name = x.examName, let days = x.examDaysAway {
            examLine = "- EXAM: \(name) in \(days) days"
        } else {
            examLine = ""
        }
        return """
        <data>
        TODAY'S DATA:
        - Date: \(x.date) (\(x.dayOfWeek))
        - Recovery: \(x.recoveryScore)% (\(x.recoveryZone))
        - HRV: \(x.hrv)ms (7-day avg: \(x.hrv7DayAvg)ms)
        - Sleep: \(x.sleepHours)h (score: \(x.sleepScore)%)

        TODAY'S PLAN:
        - Workout: \(x.workoutType) (adjusted to \(x.recoveryAdjustmentPct)% volume)
        - Non-negotiables: \(nonNeg)
        - Study target: \(x.studyTargetMinutes) min
        - Meals planned: \(x.mealsPlanned)

        CONTEXT:
        - Current streak: \(x.streakDays) days
        - Yesterday's completion: \(x.yesterdayCompletionPct)%
        - Week so far: \(x.weekAvgScore)/100
        \(examLine)
        </data>

        Generate the morning briefing. Use ONLY the data above.
        """
    }
}
