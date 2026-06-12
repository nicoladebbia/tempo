//
// DailyReadinessHarness.swift
// Tempo
//
// The D0 prompt-harness spike (docs/INTELLIGENT_TRAINING_SYSTEM.md §5.2-FIX, §19.1).
// This is the FIRST thing built — it retires the build's #1 risk (§11): "the
// daily prompt producing confident-wrong sessions." It runs ~20 synthetic
// ReadinessPictures through the REAL Haiku proxy at PRODUCTION settings
// (temp 0.6, ~700 tokens) and reports TWO independent rates:
//
//   • PROMPT QUALITY — how often Haiku's RAW output is already sensible, before
//     the floor touches it. This is the real go/no-go: a prompt that needs the
//     floor to rescue it constantly is FAILING even at "100% floor-passing".
//   • SAFETY — how often the floor had to downgrade. High = prompt unsafe.
//
// Plus NAMED anti-pattern checks the floor cannot catch (per advisor): a SEVERE
// picture must make Haiku ITSELF pick recovery/rest UNAIDED; a T-1 (pre-match)
// picture must not yield hard legs / hard conditioning.
//
// #if DEBUG only — never ships. Invoke from a debug menu or a test harness.
//

#if DEBUG
import Foundation
import OSLog

// MARK: - Harness result

struct HarnessResult: Sendable {
    let total: Int
    /// Raw Haiku output parsed cleanly (parser path).
    var parsed = 0
    /// Raw output was sensible BEFORE the floor (the real prompt-quality signal).
    var sensibleUnaided = 0
    /// Floor had to downgrade (safety rescue — high is bad for the prompt).
    var floorRescued = 0
    /// Named anti-pattern checks (severe→rest unaided, prematch→no hard legs).
    var antiPatternPassed = 0
    var antiPatternTotal = 0
    /// Anti-patterns the FLOOR cannot catch (pre-match tempo run, match-day) — the
    /// prompt is the ONLY defense here, so these are the true 100% gate. Failures
    /// of floor-CAUGHT anti-patterns (red/sleep/illness) are NOT architecture
    /// failures: the floor backstops them by design (§6). See HarnessGateTests.
    var promptOnlyAntiPatternPassed = 0
    var promptOnlyAntiPatternTotal = 0
    /// Longest shortWhy seen (the live D2 parse-fail was a >120-char title; this
    /// shows how close clean runs get to the 120 budget). Now coerced, not fatal.
    var maxShortWhyLen = 0
    /// Per-case failure notes for diagnosis.
    var failures: [String] = []

    var promptQualityRate: Double { total == 0 ? 0 : Double(sensibleUnaided) / Double(total) }
    var parseRate: Double { total == 0 ? 0 : Double(parsed) / Double(total) }

    /// Verdict per §19.1 + the corrected anti-pattern categorization (advisor):
    /// PASS = prompt-quality ≥ 19/20 AND every floor-CAN'T-catch anti-pattern
    /// passes (100%). A floor-CAUGHT anti-pattern miss is expected and safe —
    /// the floor forces recovery on those days — so it does NOT fail the gate;
    /// it only shows up as a prompt-quality point (already counted in the 19/20).
    var verdict: String {
        let q = sensibleUnaided // integer count — no float truncation (advisor)
        let promptOnlyClean = promptOnlyAntiPatternPassed == promptOnlyAntiPatternTotal
        if q >= 19, promptOnlyClean { return "PASS — prompt validated, coach may ship" }
        if !promptOnlyClean { return "FAIL — a floor-CAN'T-catch anti-pattern failed (the prompt is the only defense here). Architecture in question, STOP." }
        if q <= 15 { return "FAIL — prompt quality too low (\(q)/\(total)). STOP." }
        return "BORDERLINE (\(q)/\(total)) — re-run before verdict (Haiku is nondeterministic)"
    }
}

// MARK: - Harness

@MainActor
enum DailyReadinessHarness {

    private static let logger = Logger(subsystem: "com.tempo.app", category: "readiness_harness")

    /// Runs all synthetic fixtures through the real Haiku endpoint and returns the
    /// two-rate result. `apiClient` is the same client RecoveryAIInsightService uses.
    static func run(apiClient: APIClient) async -> HarnessResult {
        let fixtures = SyntheticPictures.all
        var result = HarnessResult(total: fixtures.count)

        for (idx, fixture) in fixtures.enumerated() {
            do {
                let raw = try await callHaiku(fixture.picture, plannedModality: fixture.plannedModality, apiClient: apiClient)

                // FIRST-CALL GATE (advisor / §10): if the very first call fails to
                // return parseable 200, STOP — that's environment (auth/consent/
                // unknown caller tag), NOT the prompt. Don't read the fixture rates.
                let session: DailySessionDTO
                do {
                    session = try DailySessionParser.parse(raw)
                } catch {
                    if idx == 0 {
                        result.failures.append("⛔️ FIRST CALL did not parse — this is ENVIRONMENT (auth/consent/402), not the prompt. STOP and fix the call path before trusting any rate. Raw: \(raw.prefix(400))")
                        return result
                    }
                    throw error
                }
                result.parsed += 1

                // Track shortWhy length distribution — the live D2 bug was a >120
                // char title. Surface the max so we see how close clean runs get.
                result.maxShortWhyLen = max(result.maxShortWhyLen, session.shortWhy.count)

                // PROMPT QUALITY — judge the RAW session, before the floor.
                let rawSensible = fixture.rawIsSensible(session)
                if rawSensible { result.sensibleUnaided += 1 }
                else {
                    // Dump the FULL raw session so a too-strict judge can be told
                    // apart from a genuine prompt failure on triage (advisor).
                    result.failures.append("[\(idx)] \(fixture.name): raw not sensible — \(fixture.diagnose(session))\n      RAW: \(Self.dump(session))")
                }

                // SAFETY — did the floor have to step in?
                let decision = TrainingSafetyFloor.apply(session, picture: fixture.picture)
                if decision.wasDowngraded { result.floorRescued += 1 }

                // Does the floor INDEPENDENTLY protect this day? (severe tier, or a
                // worst-case "go hard" session would be downgraded). If so, an
                // anti-pattern miss is the floor's job, not an architecture failure.
                let floorProtects = TrainingSafetyFloor.classifyFloorTier(fixture.picture) == .severe
                    || TrainingSafetyFloor.apply(Self.worstCaseSession, picture: fixture.picture).wasDowngraded

                // NAMED anti-patterns. Split into the real gate (floor-CAN'T-catch)
                // vs floor-backstopped (counts only toward prompt-quality).
                if let check = fixture.antiPattern {
                    result.antiPatternTotal += 1
                    let passed = check(session)
                    if passed { result.antiPatternPassed += 1 }

                    if floorProtects {
                        if !passed {
                            result.failures.append("[\(idx)] \(fixture.name): anti-pattern missed but FLOOR-CAUGHT (safe by design — not a gate failure)")
                        }
                    } else {
                        result.promptOnlyAntiPatternTotal += 1
                        if passed { result.promptOnlyAntiPatternPassed += 1 }
                        else { result.failures.append("[\(idx)] \(fixture.name): ⛔️ PROMPT-ONLY anti-pattern FAILED — the floor cannot catch this; the prompt is the only defense. RAW: \(Self.dump(session))") }
                    }
                }
            } catch {
                result.failures.append("[\(idx)] \(fixture.name): parse/call failed — \(error)")
            }
        }

        logger.info("Harness: prompt-quality \(result.sensibleUnaided)/\(result.total), parsed \(result.parsed)/\(result.total), floor-rescued \(result.floorRescued), anti-pattern \(result.antiPatternPassed)/\(result.antiPatternTotal) (prompt-only gate \(result.promptOnlyAntiPatternPassed)/\(result.promptOnlyAntiPatternTotal)) → \(result.verdict)")
        return result
    }

    // MARK: - The Haiku call (mirrors RecoveryAIInsightService.sendWithRetry, production settings)

    private static func callHaiku(_ p: ReadinessPicture, plannedModality: String?, apiClient: APIClient) async throws -> String {
        let body = NutritionProxyTextRequest(
            model: "haiku",
            system: DailyCoachPrompt.system,
            userMessage: DailyCoachPrompt.userMessage(for: p, plannedModality: plannedModality),
            maxTokens: 700,        // §5.1 — a multi-block JSON object; 400 truncates.
            temperature: 0.6,      // §5.2-FIX — the production temp is the point of the test.
            caller: "daily_training_harness"
        )
        let response: NutritionProxyTextResponse = try await apiClient.request(
            APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
            body: body
        )
        return response.text
    }

    /// The worst thing Haiku could emit — used to probe whether the floor would
    /// independently protect a given day regardless of session content.
    private static let worstCaseSession = DailySessionDTO(
        modality: "legs", intensity: .max, durationMin: 90,
        blocks: [SessionBlockDTO(
            kind: .gym, label: "Max legs", notes: nil, cue: nil, scheduledMin: nil, split: "legs",
            reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
            durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil
        )],
        shortWhy: "max", fullWhy: nil, expectedStrain: 18, expectedSessionRPE: 10
    )

    /// Compact one-line dump of a session for failure triage.
    private static func dump(_ s: DailySessionDTO) -> String {
        let blocks = s.blocks.map { b in
            "\(b.kind.rawValue)(\(b.split ?? b.runType ?? b.label))"
        }.joined(separator: ", ")
        return "modality=\(s.modality) intensity=\(s.intensity.rawValue) dur=\(s.durationMin) blocks=[\(blocks)] why=\"\(s.shortWhy)\""
    }
}
#endif
