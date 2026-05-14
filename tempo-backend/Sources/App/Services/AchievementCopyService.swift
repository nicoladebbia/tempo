import Foundation
import Vapor

// MARK: - AchievementCopyService
//
// Per AI_INTELLIGENCE_ENGINE.md §3.9 + INTELLIGENCE_REMEDIATION_PLAN.md §7.9.
//
// Generates celebration copy for an achievement unlock. Haiku, high temperature
// for variety. Cached forever per (user, achievement) — once you unlock the
// 7-day-streak badge, the copy doesn't regenerate.

struct AchievementCopyService {
    static let shared = AchievementCopyService()
    private init() {}

    func generate(
        input: AchievementCopyInput,
        on req: Request
    ) async throws -> AchievementCopyResponse {
        let spec = AIFeatureSpec<AchievementCopyResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 200,
            temperature: 0.9,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 600,
            cacheKey: .achievementCopy(userId: input.userId ?? "", achievementId: input.achievementId)
        )
        let (value, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            buildPrompts: { (AchievementCopyPrompts.system, AchievementCopyPrompts.buildUserPrompt(from: input)) },
            parse: { raw in AchievementCopyResponse(copy: raw.trimmingCharacters(in: .whitespacesAndNewlines)) },
            fallback: { AchievementCopyResponse(copy: "\(input.achievementName) unlocked. Earned, not given. \(input.requirementSummary).") }
        )
        return value
    }
}

struct AchievementCopyInput: Content {
    var userId: String? = nil
    let achievementId: String
    let achievementName: String
    let requirementSummary: String       // e.g. "Maintained 7-day streak"
    let userContext: String              // brief context, e.g. "Day 7 streak after a 14-day miss last month"

    // Vapor's convertFromSnakeCase turns "achievement_id" into "achievementId",
    // not "achievementId". Spell out the keys explicitly so the wire format
    // stays snake_case while Swift uses our ID-suffix convention.

    func withUserID(_ id: String) -> AchievementCopyInput {
        var copy = self
        copy.userId = id
        return copy
    }
}

struct AchievementCopyResponse: Content {
    let copy: String
}

enum AchievementCopyPrompts {
    static let system = """
    You generate ONE celebration sentence (max 2) for an achievement unlock in a fitness app. Drill-sergeant tone — earned, not soft. Reference what the user did to earn it. No emojis. No greetings. Output the copy directly, no quotes, no labels.
    """

    static func buildUserPrompt(from x: AchievementCopyInput) -> String {
        """
        Achievement: \(x.achievementName)
        Earned by: \(x.requirementSummary)
        User context: \(x.userContext)

        Write the celebration copy (1-2 sentences, drill-sergeant tone, reference the user's specific journey):
        """
    }
}
