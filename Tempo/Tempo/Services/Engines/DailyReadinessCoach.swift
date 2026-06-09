//
// DailyReadinessCoach.swift
// Tempo
//
// The daily training brain (docs/INTELLIGENT_TRAINING_SYSTEM.md §5.1). Mirrors
// RecoveryAIInsightService.sendWithRetry. Produces ONE floor-applied session per
// day for today's ReadinessPicture, reusing the D0-VERIFIED prompt + parser + floor.
//
// CONTRACT (advisor): produce-then-floor on EVERY path. The floor runs on the
// brain pick AND every fallback AND cold-start — it is NEVER bypassed (cold-start
// skips the BRAIN, not the FLOOR; §14.2 has floor-safety from day ~14, brain from
// day 31). Structure: candidate (brain | deterministic) → floor.apply() always →
// return decision + provenance. Persistence + WorkoutPlan resolution is the
// caller's job (TrainingViewModel) so this stays unit-testable.
//
// Cost (§10): ≤1 Haiku/day, gated by AdaptiveProfile.lastDailySessionDayKey in
// the caller. Single-flight here guards the in-flight window.
//

import Foundation
import OSLog

@Observable
final class DailyReadinessCoach: @unchecked Sendable {
    private let apiClient: APIClient
    private let logger = Logger.training
    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    /// Per-day single-flight: a second trigger for the same day joins the
    /// in-flight task instead of starting a second paid Haiku call.
    @MainActor private var inFlight: (day: Date, task: Task<CoachResult, Never>)?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Result

    struct CoachResult: Sendable {
        let decision: FloorDecision
        let source: DailySessionSource
    }

    // MARK: - Public

    /// Produce today's floor-applied session. `deterministicCandidate` is the
    /// engine's own pick for the day (the fallback + cold-start session, and what
    /// a parse-fail / offline / 402 falls back to). `plannedModality` is today's
    /// WorkoutPlan type (§8 — weekly owns the default). `brainEligible` is false
    /// in cold-start (<30 days) or on stale/absent Whoop data (§15.1) → skip the
    /// brain, but STILL run the floor.
    @MainActor
    func session(
        for picture: ReadinessPicture,
        plannedModality: String?,
        deterministicCandidate: DailySessionDTO,
        brainEligible: Bool
    ) async -> CoachResult {
        let day = Calendar.current.startOfDay(for: Date())
        if let inFlight, inFlight.day == day {
            return await inFlight.task.value
        }
        let task = Task<CoachResult, Never> { [self] in
            await produce(picture: picture, plannedModality: plannedModality,
                          deterministicCandidate: deterministicCandidate, brainEligible: brainEligible)
        }
        inFlight = (day, task)
        let result = await task.value
        inFlight = nil
        return result
    }

    // MARK: - Produce-then-floor (the contract)

    private func produce(
        picture: ReadinessPicture,
        plannedModality: String?,
        deterministicCandidate: DailySessionDTO,
        brainEligible: Bool
    ) async -> CoachResult {
        // 1. Candidate: brain when eligible, else deterministic. The floor runs
        //    on whatever this returns — never bypassed.
        var source: DailySessionSource
        var candidate: DailySessionDTO

        if brainEligible {
            if let brain = await callBrain(picture: picture, plannedModality: plannedModality) {
                candidate = brain
                source = .brain
            } else {
                // Offline / 402 / parse-fail → deterministic floor pick (§15.1).
                candidate = deterministicCandidate
                source = .floorFallback
            }
        } else {
            // Cold-start / stale-Whoop: deterministic engine, but floor STILL applies.
            candidate = deterministicCandidate
            source = .simple
        }

        // 2. Floor — ALWAYS, on every path.
        let decision = TrainingSafetyFloor.apply(candidate, picture: picture)
        logger.info("\(DebugTrace.prefix)[daily_coach] source=\(source.rawValue) tier=\(decision.tier.rawValue) downgraded=\(decision.wasDowngraded) modality=\(decision.session.modality)")
        return CoachResult(decision: decision, source: source)
    }

    // MARK: - The brain call (mirror RecoveryAIInsightService.sendWithRetry)

    /// Returns a parsed+contract-valid DTO, or nil on ANY failure (network, 402,
    /// parse-fail, truncation) → caller falls back to deterministic. Never throws.
    private func callBrain(picture: ReadinessPicture, plannedModality: String?) async -> DailySessionDTO? {
        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "haiku",
                    system: DailyCoachPrompt.system,
                    userMessage: DailyCoachPrompt.userMessage(for: picture, plannedModality: plannedModality),
                    maxTokens: 700,
                    temperature: 0.6,
                    caller: "daily_training"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                // Parse + contract-validate (D0). A throw here is a parse-fail →
                // fall back, never render half-parsed (§5.2-FIX / §13.1).
                return try DailySessionParser.parse(response.text)
            } catch is CancellationError {
                return nil
            } catch let error as APIError {
                // 402 = not Pro / no consent → silent deterministic fallback. Not retryable.
                if case .subscriptionRequired = error {
                    logger.info("\(DebugTrace.prefix)[daily_coach] 402 gate — deterministic fallback")
                    return nil
                }
                guard error.isRetryable, attempt < maxRetries else {
                    logger.warning("\(DebugTrace.prefix)[daily_coach] brain failed attempt=\(attempt): \(String(describing: error))")
                    return nil
                }
                try? await Task.sleep(for: .seconds(baseRetryDelay * pow(2.0, Double(attempt))))
            } catch let parseError as DailySessionParseError {
                // Parse/contract failure → deterministic fallback (do NOT retry; a
                // re-roll at temp 0.6 is a fresh paid call for the same likely shape).
                logger.warning("\(DebugTrace.prefix)[daily_coach] parse-fail → deterministic fallback: \(String(describing: parseError))")
                return nil
            } catch {
                logger.error("\(DebugTrace.prefix)[daily_coach] unexpected: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
}
