import Foundation
import Vapor

// MARK: - TrainingAdjustmentService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.11 + INTELLIGENCE_REMEDIATION_PLAN.md §7.3.
//
// Real-time training session adjustment based on today's recovery vs. the
// plan's assumed recovery. Haiku, no cache (recovery delta drives every call).

struct TrainingAdjustmentService {
    static let shared = TrainingAdjustmentService()
    private init() {}

    func generate(
        input: TrainingAdjustmentInput,
        on req: Request
    ) async throws -> TrainingAdjustmentResponse {
        let spec = AIFeatureSpec<TrainingAdjustmentResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 500,
            temperature: 0.3,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 800,
            cacheKey: nil  // No cache: every call is recovery-delta-driven.
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            buildPrompts: {
                (TrainingAdjustmentPrompts.system, TrainingAdjustmentPrompts.buildUserPrompt(from: input))
            },
            parse: { raw in try Self.parseJSON(raw) },
            fallback: { Self.fallback(input: input) }
        )
        return value
    }

    private static func parseJSON(_ raw: String) throws -> TrainingAdjustmentResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s = raw.firstIndex(of: "{").flatMap { start in
            raw.lastIndex(of: "}").map { String(raw[start ... $0]) }
        } ?? raw
        guard let data = s.data(using: .utf8) else { throw InsightError.malformedResponse }
        return try decoder.decode(TrainingAdjustmentResponse.self, from: data)
    }

    static func fallback(input: TrainingAdjustmentInput) -> TrainingAdjustmentResponse {
        let delta = input.todayRecovery - input.plannedRecoveryAssumption
        let adjustment: Double = delta < -15 ? 0.7 : delta < -5 ? 0.85 : 1.0
        return TrainingAdjustmentResponse(
            volumeAdjustment: adjustment,
            keepExercises: input.plannedExercises,
            dropExercises: [],
            note: "Auto-adjusted to \(Int(adjustment * 100))% volume based on \(Int(delta))-point recovery delta. AI commentary unavailable."
        )
    }
}

struct TrainingAdjustmentInput: Content {
    var userId: String? = nil
    let todayRecovery: Int
    let plannedRecoveryAssumption: Int
    let plannedWorkoutType: String
    let plannedExercises: [String]
    let footballTomorrow: Bool


    func withUserID(_ id: String) -> TrainingAdjustmentInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct TrainingAdjustmentResponse: Content {
    let volumeAdjustment: Double      // 0.0 - 1.2
    let keepExercises: [String]
    let dropExercises: [String]
    let note: String
}

enum TrainingAdjustmentPrompts {
    static let system = """
    You are a strength coach inside the Tempo app. The user has a planned workout but today's recovery differs from what was assumed. Decide which exercises to keep, which to drop, and the overall volume adjustment.

    <rules>
    - Use the recovery delta to decide intensity. Each 10-point drop = ~15% volume reduction.
    - Keep compound lifts unless recovery is red. Drop isolation work first.
    - If football is tomorrow, protect legs. Never recommend heavy legs the day before football.
    - Output ONLY valid JSON. No markdown.
    - NEVER suggest training through pain. NEVER recommend supplements.
    </rules>
    """

    static func buildUserPrompt(from x: TrainingAdjustmentInput) -> String {
        let exercises = x.plannedExercises.joined(separator: ", ")
        return """
        Planned workout type: \(x.plannedWorkoutType)
        Planned exercises: \(exercises)
        Planned assumed recovery: \(x.plannedRecoveryAssumption)%
        Today's actual recovery: \(x.todayRecovery)%
        Football tomorrow: \(x.footballTomorrow ? "yes" : "no")

        Return JSON:
        {
          "volume_adjustment": number (0.0-1.2),
          "keep_exercises": [string],
          "drop_exercises": [string],
          "note": string (1-2 sentences, drill-sergeant tone)
        }
        """
    }
}
