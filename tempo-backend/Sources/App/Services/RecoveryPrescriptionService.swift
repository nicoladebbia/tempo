import Foundation
import Vapor

// MARK: - RecoveryPrescriptionService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.6 + INTELLIGENCE_REMEDIATION_PLAN.md §7.1.
//
// Generates a daily Haiku-driven recovery prescription from Whoop biometrics,
// nutrition data, and today's schedule. Triggered after each Whoop sync (or
// on-demand from the dashboard). Cached 12h per (user, date) in Redis.

struct RecoveryPrescriptionService {
    static let shared = RecoveryPrescriptionService()
    private init() {}

    func generate(
        input: RecoveryPrescriptionInput,
        on req: Request,
        bypassCache: Bool = false
    ) async throws -> RecoveryPrescriptionResponse {
        let spec = AIFeatureSpec<RecoveryPrescriptionResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 400,
            temperature: 0.2,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 1_200,
            cacheKey: .recoveryPrescription(userId: input.userId ?? "", date: input.date)
        )

        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (RecoveryPrescriptionPrompts.system, RecoveryPrescriptionPrompts.buildUserPrompt(from: input)) },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    // MARK: - JSON parsing

    private static func parseJSON(_ raw: String) throws -> RecoveryPrescriptionResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Permissive: handle Claude wrapping in markdown by extracting first {..}
        let extracted: String
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            extracted = String(raw[start ... end])
        } else {
            extracted = raw
        }
        guard let data = extracted.data(using: .utf8) else {
            throw InsightError.malformedResponse
        }
        let parsed = try decoder.decode(RecoveryPrescriptionResponse.self, from: data)

        // Validation per spec §3.6 rules — clamp safety-critical fields.
        return RecoveryPrescriptionResponse(
            trainingRecommendation: parsed.trainingRecommendation,
            trainingIntensity: parsed.trainingIntensity,
            volumeAdjustment: max(0.0, min(1.2, parsed.volumeAdjustment)),
            mealTiming: parsed.mealTiming,
            bedtimeTarget: parsed.bedtimeTarget,
            wakeTarget: parsed.wakeTarget,
            hydrationTargetMl: max(2_000, min(5_000, parsed.hydrationTargetMl)),
            caffeineCutoff: parsed.caffeineCutoff,
            warnings: parsed.warnings,
            topPriority: parsed.topPriority
        )
    }

    // MARK: - Rule-based fallback (per spec §8.6)

    static func fallback(input: RecoveryPrescriptionInput) -> RecoveryPrescriptionResponse {
        let intensity: String
        let volume: Double
        let recommendation: String
        switch input.recoveryZone.lowercased() {
        case "green":
            intensity = "full_send"
            volume = 1.0
            recommendation = "Full send. Recovery is green — push planned volume and intensity."
        case "yellow":
            intensity = "moderate"
            volume = 0.8
            recommendation = "Moderate session. Cut volume 20% — keep compound intensity, drop the last set of isolations."
        default:
            intensity = "easy"
            volume = 0.4
            recommendation = "Easy mobility or rest. Recovery is red — protect tomorrow's session."
        }
        return RecoveryPrescriptionResponse(
            trainingRecommendation: recommendation,
            trainingIntensity: intensity,
            volumeAdjustment: volume,
            mealTiming: "Hit protein target within 90 minutes of training. Front-load protein at breakfast and lunch.",
            bedtimeTarget: input.targetBedtime ?? "23:00",
            wakeTarget: input.targetWake ?? "07:00",
            hydrationTargetMl: 3_000,
            caffeineCutoff: "15:00",
            warnings: [],
            topPriority: "Protect tonight's sleep."
        )
    }
}

// MARK: - DTOs

struct RecoveryPrescriptionInput: Content {
    /// Stamped server-side from the JWT. Clients should omit; the controller
    /// rewrites this from the authenticated user.
    var userId: String? = nil
    let date: String              // "yyyy-MM-dd"

    // Explicit CodingKeys because convertFromSnakeCase turns "user_id" into
    // "userId" (lowercase 'd'), not the ID-suffix convention used here.
    let dayOfWeek: String
    let recoveryScore: Int
    let recoveryZone: String       // "green" | "yellow" | "red"
    let hrv: Double
    let hrvTrend: String           // "up" | "flat" | "down"
    let hrv7DayAvg: Double
    let rhr: Int
    let rhr7DayAvg: Int
    let sleepHours: Double
    let sleepPerformance: Int
    let sleepEfficiency: Int
    let sleepDebtHours: Double
    let yesterdayStrain: Double
    let respRate: Double
    let respBaseline: Double
    let yesterdayCalories: Int
    let calorieTarget: Int
    let yesterdayProtein: Int
    let proteinTarget: Int
    let yesterdayWaterMl: Int
    let plannedWorkout: String
    let footballToday: Bool
    let footballTime: String?
    let classesToday: String
    let targetWake: String?
    let targetBedtime: String?
    let targetSleepHours: Double
    let daysSinceRest: Int
    let recovery3Day: String       // e.g. "72/65/58"
    let strain3DayAvg: Double
}

struct RecoveryPrescriptionResponse: Content {
    let trainingRecommendation: String
    let trainingIntensity: String  // "full_send" | "moderate" | "easy" | "rest"
    let volumeAdjustment: Double
    let mealTiming: String
    let bedtimeTarget: String
    let wakeTarget: String
    let hydrationTargetMl: Int
    let caffeineCutoff: String
    let warnings: [String]
    let topPriority: String
}

// MARK: - Prompts

enum RecoveryPrescriptionPrompts {

    static let system = """
    You are a sports science advisor inside the Tempo app. You generate a daily recovery prescription based on biometric data, nutrition data, and the user's schedule. Your prescriptions are specific, time-bound, and actionable.

    <rules>
    - Every recommendation must be rooted in the provided <biometric_data> and <schedule>. Do NOT reference data that was not provided.
    - Be specific with times: "Bed by 23:15" not "go to bed earlier".
    - Be specific with quantities: "Drink 3L water today" not "stay hydrated".
    - Calculate caffeine cutoff as: target bedtime minus 8 hours.
    - Calculate target bedtime as: target wake time minus target sleep duration, adjusted for sleep debt.
    - If HRV has been declining for 3+ days, flag it as a warning.
    - If sleep debt exceeds 4 hours, flag it as a warning.
    - Training recommendation must align with recovery zone: green = "Full send", yellow = "Moderate: reduce volume 20%", red = "Easy/mobility only" or "Rest".
    - NEVER say "consult a doctor", "see a physician", or give medical diagnoses. You are a performance coach.
    - NEVER suggest supplements, medications, or specific drugs.
    - NEVER suggest caloric intake below 1,500 kcal for an active male.
    - NEVER suggest training through pain or injury. If strain is high and recovery is red, prescribe rest.
    - Hydration target must be between 2,000ml and 5,000ml. Anything outside this range should be capped.
    - Output ONLY valid JSON. No markdown wrapping. Start with { and end with }.
    </rules>
    """

    static func buildUserPrompt(from input: RecoveryPrescriptionInput) -> String {
        let football = input.footballToday ? "yes (\(input.footballTime ?? "unspecified"))" : "no"
        return """
        Generate today's recovery prescription. Use ONLY the data provided below.

        <biometric_data>
        TODAY: \(input.date) (\(input.dayOfWeek))

        WHOOP:
        - Recovery: \(input.recoveryScore)% (\(input.recoveryZone))
        - HRV: \(input.hrv)ms (3-day trend: \(input.hrvTrend), 7-day avg: \(input.hrv7DayAvg)ms)
        - Resting HR: \(input.rhr)bpm (7-day avg: \(input.rhr7DayAvg)bpm)
        - Last night sleep: \(input.sleepHours)h, Performance: \(input.sleepPerformance)%, Efficiency: \(input.sleepEfficiency)%
        - Sleep debt: \(input.sleepDebtHours)h
        - Yesterday's strain: \(input.yesterdayStrain)
        - Respiratory rate: \(input.respRate) breaths/min (baseline: \(input.respBaseline))
        </biometric_data>

        <nutrition_yesterday>
        - Calories: \(input.yesterdayCalories) / \(input.calorieTarget) target
        - Protein: \(input.yesterdayProtein)g / \(input.proteinTarget)g
        - Hydration: \(input.yesterdayWaterMl)ml
        </nutrition_yesterday>

        <schedule>
        - Planned workout: \(input.plannedWorkout)
        - Football: \(football)
        - Classes: \(input.classesToday)
        - Target wake time: \(input.targetWake ?? "07:00")
        - Target sleep duration: \(input.targetSleepHours)h
        </schedule>

        <recent_context>
        - Days since last rest day: \(input.daysSinceRest)
        - Recovery last 3 days: \(input.recovery3Day)
        - Average strain last 3 days: \(input.strain3DayAvg)
        </recent_context>

        Return ONLY valid JSON (no markdown, start with {):
        {
          "training_recommendation": "string",
          "training_intensity": "full_send" | "moderate" | "easy" | "rest",
          "volume_adjustment": number (0.0 to 1.2),
          "meal_timing": "string (specific recommendation)",
          "bedtime_target": "HH:MM",
          "wake_target": "HH:MM",
          "hydration_target_ml": number,
          "caffeine_cutoff": "HH:MM",
          "warnings": ["string"],
          "top_priority": "string (single most important thing to do today)"
        }
        """
    }
}
