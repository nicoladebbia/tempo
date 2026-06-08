# Training Intelligence — Road to a Real 10/10

**Status:** Audit + full implementation spec
**Author:** Claude (Opus 4.8), 2026-06-08
**Scope:** The Training module (RepForge) as a *training-intelligence system*. Not UI polish, not the workout-session state machine, not gamification.
**Current score:** **4/10** (verified by live code trace — see `§0`)
**Target:** **10/10**, hybrid architecture — deterministic floor + LLM-in-loop + on-device learning + outcome validation.

> This file is the executable plan. Each fix names the real file, the real signature, the diff, the caller change, and the test. Hand any phase to a `/build` session and it runs.

---

## §0 — Why it's a 4 today (ground truth, not vibes)

Traced live path: `TrainingViewModel.loadToday → loadWeekPlan → trainingEngine.generateWeekPlan` (`TrainingViewModel.swift:202`, `TrainingEngine.swift:265`). It is 100% local, deterministic Swift. `TrainingViewModel.init` (`TrainingViewModel.swift:180`) takes `trainingEngine`, `whoop`, `healthKit` — **no `APIClient`** — so the AI path is structurally unreachable from the Training tab.

What's real and good (keeps the floor at 4, not 2):
- Multi-signal deterministic engine: recovery zones × football T-0/T-1/T+1 × split rotation × deload cycle.
- Reads **real** Whoop recovery (not mocked).
- **The RPE feedback substrate already exists** — `SetFeedback` (`SetFeedback.swift`), and `ExerciseHistory` already carries `avgRPE`, `worstFormRaw`, `feedbackSampleCount` aggregates (`ExerciseHistory.swift:30-43`). The Tier-2 gate in `calculateProgressiveOverload` (`TrainingEngine.swift:173-180`) already *vetoes* progression on RPE≥9 or broken form.

What caps it at 4:
1. **No learning / no personalization.** Same input → same output forever. Increments, thresholds, rep targets all hardcoded (`TrainingEngine.swift:22-26`, `431-442`).
2. **Feedback loop is half-open.** RPE/form can only *block* a jump (binary veto). It never *sizes* the jump, never tunes the per-user target, never accelerates an easy lifter. `breathDifficulty` is captured and **never read by the engine at all**.
3. **The LLM training services are dead-on-arrival from the app.** `TrainingProgramService` (Sonnet) and `TrainingAdjustmentService` (Haiku) exist, are route-registered, have valid model IDs — but `TrainingAdjustmentService` has **no iOS endpoint** and `TrainingProgramService`'s only caller sits behind `DayPlanView`, which is never instantiated. Existence ≠ reachability.
4. **Calendar football detection built but unwired** — engine only sees static `UserSettings.footballDays`.
5. **No outcome validation.** Nothing checks whether last week's plan actually worked before generating next week's.

The rubric:

| Score | Definition |
|---|---|
| 1–2 | Static plan, ignores state. |
| 3–4 | Multi-signal **deterministic** rules. Adapts to inputs; same input → same output; no learning. ← **we are here** |
| 5–6 | Rich rule engine **or** LLM-in-loop adapting plans live. |
| 7–8 | ML/LLM personalizing from the user's own history; closed feedback loops. |
| 9–10 | Continual on-device learning **+ outcome-validated** adaptation; the system measurably improves its own prescriptions. |

---

## §1 — Architecture target (the 10/10 shape)

Five layers, each with a clear owner. The deterministic engine never leaves — it's the safety floor and the offline path.

```
┌─ OUTCOME ─ TrainingOutcomeEvaluator: did last week's plan produce progress
│            without overreaching? Feeds a "plan quality" score back in.        (Phase 4)
├─ LEARN ──  AdaptiveProfile (on-device): per-exercise learned increment,
│            per-user recovery threshold offset, fatigue trend model.           (Phase 3)
├─ LLM ────  TrainingProgramService (Sonnet, weekly) + TrainingAdjustmentService
│            (Haiku, live mid-session) wired into the REAL path, gated+budgeted. (Phase 2)
├─ LOOP ───  Closed RPE/form/breath → progression sizing, not just veto.        (Phase 1)
└─ FLOOR ──  TrainingEngine deterministic rules — offline + fallback always.    (exists)
```

**Hard rule — the floor never goes away.** Every LLM/learning output is *advisory* and clamped by the deterministic engine. If Claude says "+10kg" the engine caps it at one increment. If the API is down, the floor runs unchanged. This is what makes a 10 *realistic* and *safe* rather than a black box that hurts the user.

**Phasing maps to score:**
- Phase 1 (close the loop): 4 → 6
- Phase 2 (wire the LLM live): 6 → 7.5
- Phase 3 (on-device learning): 7.5 → 9
- Phase 4 (outcome validation): 9 → 10

---

## PHASE 1 — Close the feedback loop (4 → 6)

No network, no ML. Pure engine work. Highest intelligence-per-line because the data is **already being collected and thrown away**. Do this first.

### Fix 1.1 — Progression *sizing* from RPE, not just veto

**File:** `Tempo/Tempo/Services/Engines/TrainingEngine.swift:149`
**Problem:** `calculateProgressiveOverload` uses RPE only as a binary gate (`:173-180`). A set that felt like RPE 5 (trivial) gets the same +2.5kg as one that felt like RPE 8 (hard-but-clean). An easy lifter is under-loaded for weeks.

**New signature** (protocol + impl):

```swift
// TrainingEngineProtocol.swift — replace the calculateProgressiveOverload decl
func calculateProgressiveOverload(
    for exercise: Exercise,
    history: [ExerciseHistory],
    profile: AdaptiveProfile?   // nil in Phase 1; wired in Phase 3
) -> ProgressionDecision

// New return type (add near top of TrainingEngineProtocol.swift)
struct ProgressionDecision: Equatable, Sendable {
    let weight: Double
    let reps: Int
    let deltaApplied: Double        // signed kg change, for the "why" UI
    let rationale: ProgressionReason
}

enum ProgressionReason: String, Equatable, Sendable, Codable {
    case acceleratedEasyLoad     // RPE low + clean → 2× increment (clamped)
    case standardProgression     // 2-of-3 hit, normal RPE
    case heldHighRPE             // RPE ≥ 9
    case heldBrokenForm          // sloppy/failed
    case heldInsufficientData
    case deloadedRepeatedFailure
}
```

**Replace the body** (`TrainingEngine.swift:149-209`) with sizing logic. Key change — read the existing `avgRPE` aggregate to *scale* the increment:

```swift
func calculateProgressiveOverload(
    for exercise: Exercise,
    history: [ExerciseHistory],
    profile: AdaptiveProfile? = nil
) -> ProgressionDecision {
    let defaultReps = exercise.isCompound ? 8 : 12
    // Phase 3 swaps the constant for profile?.learnedIncrement(for:) ?? base
    let baseIncrement = profile?.learnedIncrement(for: exercise.id)
        ?? weightIncrement(for: exercise.equipment)

    let recentSessions = history.sorted { $0.date > $1.date }.prefix(3)
    guard recentSessions.count >= 2 else {
        let lastWeight = history.first?.bestSetWeight ?? 0
        return ProgressionDecision(weight: lastWeight, reps: defaultReps,
            deltaApplied: 0, rationale: .heldInsufficientData)
    }
    let currentWeight = recentSessions.first?.bestSetWeight ?? 0

    // Tier-2 veto (UNCHANGED — the safety floor)
    if let lastFeedback = recentSessions.first(where: { $0.feedbackSampleCount > 0 }) {
        if (lastFeedback.avgRPE ?? 0) >= 9 {
            return ProgressionDecision(weight: currentWeight, reps: defaultReps,
                deltaApplied: 0, rationale: .heldHighRPE)
        }
        let formBroke = lastFeedback.worstFormRaw
            .flatMap(FormQuality.init(rawValue:))?.isNegativeSignal ?? false
        if formBroke {
            return ProgressionDecision(weight: currentWeight, reps: defaultReps,
                deltaApplied: 0, rationale: .heldBrokenForm)
        }
    }

    var successCount = 0
    for session in recentSessions where (session.bestSetReps ?? 0) >= defaultReps {
        successCount += 1
    }

    if successCount >= 2 {
        // NEW: size the jump by how easy it felt. Low RPE + clean + reps spare
        // → double increment (clamped to one extra step). This is the open loop.
        let lastRPE = recentSessions.first(where: { $0.feedbackSampleCount > 0 })?.avgRPE
        let multiplier: Double = (lastRPE != nil && lastRPE! <= 6.5) ? 2.0 : 1.0
        let delta = baseIncrement * multiplier
        return ProgressionDecision(
            weight: currentWeight + delta, reps: defaultReps,
            deltaApplied: delta,
            rationale: multiplier > 1 ? .acceleratedEasyLoad : .standardProgression)
    }

    if successCount == 0, recentSessions.count >= 3 {
        let avgReps = recentSessions.compactMap(\.bestSetReps).reduce(0, +)
            / max(1, recentSessions.count)
        if avgReps < Int(Double(defaultReps) * 0.75) {
            return ProgressionDecision(
                weight: max(0, currentWeight - baseIncrement), reps: defaultReps,
                deltaApplied: -baseIncrement, rationale: .deloadedRepeatedFailure)
        }
    }
    return ProgressionDecision(weight: currentWeight, reps: defaultReps,
        deltaApplied: 0, rationale: .standardProgression)
}
```

**Caller change:** `TrainingViewModel+ExercisePopulation.swift` (the populate path calls this). Update call sites to consume `.weight`/`.reps` off the struct and surface `.rationale` in the exercise card "why" text. Grep: `grep -rn "calculateProgressiveOverload" Tempo/Tempo`.

**Why this matters for the score:** the loop is now *closed* — felt difficulty changes the next prescription's *magnitude*, not just its go/no-go. That alone is the 4→5 step.

### Fix 1.2 — Feed `breathDifficulty` into the conditioning signal

**File:** `TrainingEngine.swift` + `ExerciseHistory.swift:30`
`breathDifficulty` (`SetFeedback.swift:17`) is captured and never read. Add a session aggregate and use it to bias **rest prescription** and **conditioning-day volume**.

1. Add to `ExerciseHistory` (additive, lightweight migration — same pattern as the Tier-2 fields at `:30-43`):
   ```swift
   /// Fraction of entered feedback rows on this session marked `.gassed`
   /// (0...1). nil = no entered feedback. Biases rest + conditioning volume.
   var gassedFraction: Double?
   ```
2. Aggregate it where `avgRPE`/`worstFormRaw` are computed (find the session-save aggregation — `grep -rn "feedbackSampleCount =" Tempo/Tempo`).
3. New engine method:
   ```swift
   /// Per MODULE_TRAINING.md §17 — conditioning-debt signal. When recent
   /// sessions repeatedly gassed the user, lengthen rest and trim accessory
   /// volume even at green recovery (recovery score ≠ work capacity).
   func restMultiplier(history: [ExerciseHistory]) -> Double {
       let recent = history.sorted { $0.date > $1.date }.prefix(3)
       let gassy = recent.compactMap(\.gassedFraction).filter { $0 >= 0.5 }
       return gassy.count >= 2 ? 1.25 : 1.0   // +25% rest when conditioning-debt
   }
   ```

### Fix 1.3 — Tests (Phase 1 gate)

**File:** `Tempo/TempoTests/Engines/TrainingEngineProgressionTests.swift` (new — tests dir is an allowed new-file location).
Required cases:
- `acceleratedEasyLoad`: 2/3 success + avgRPE 5 + clean → `deltaApplied == 2 × base`.
- `standardProgression`: 2/3 success + avgRPE 8 → `deltaApplied == base`.
- `heldHighRPE`: avgRPE 9 → `deltaApplied == 0`, weight unchanged.
- `heldBrokenForm`: worstForm `.failed` → held even with reps hit.
- `restMultiplier`: two gassy sessions → `1.25`.
- **Determinism guard:** identical input twice → identical `ProgressionDecision` (protects the floor).

**Phase 1 exit = these pass + a clean `xcodebuild`.** Score now 6: closed loop, multi-signal, still deterministic.

---

## PHASE 2 — Wire the LLM into the live path (6 → 7.5)

The services exist and call Claude. Make the app actually reach them, gated and clamped. Two endpoints: weekly program (Sonnet) and live mid-session adjustment (Haiku).

### Fix 2.1 — Add the missing iOS endpoints

**File:** `Tempo/Tempo/Services/Network/APIEndpoints.swift`
`training-program` may exist as `dayPlanTrainingProgram()`; `training-adjustment` has **no iOS endpoint**. Add both with training-owned names:

```swift
static func trainingProgram() -> APIEndpoint<DayPlanTrainingProgramResponse> {
    APIEndpoint(path: "/v1/insights/training-program", method: .post)
}
static func trainingAdjustment() -> APIEndpoint<TrainingAdjustmentResponseDTO> {
    APIEndpoint(path: "/v1/insights/training-adjustment", method: .post)
}
```

Add matching Codable request/response DTOs mirroring the backend (`TrainingAdjustmentService.swift:61-83`, `TrainingProgramService.swift:72-99`). Field names must match the JSON contract (`volume_adjustment`, `keep_exercises`, `drop_exercises`, `note`; program: `week_start`, `days[].workout_type`, `rationale`).

### Fix 2.2 — Give `TrainingViewModel` an `APIClient` (the structural unblock)

**File:** `Tempo/Tempo/ViewModels/TrainingViewModel.swift:180` + `Tempo/Tempo/App/ServiceContainer.swift:136`

```swift
// TrainingViewModel.swift — init
private let apiClient: APIClient?     // optional: nil → pure deterministic (tests, offline)

init(
    trainingEngine: any TrainingEngineProtocol,
    whoop: any WhoopServiceProtocol,
    healthKit: any HealthKitServiceProtocol,
    apiClient: APIClient? = nil       // additive, default nil — no caller breaks
) {
    self.trainingEngine = trainingEngine
    self.whoop = whoop
    self.healthKit = healthKit
    self.apiClient = apiClient
}
```

`ServiceContainer.swift:127-146` already builds `apiClient` and the live `TrainingEngine()` — thread it through (`:136` neighborhood). The mock container (`:105`) passes `nil`, preserving offline determinism in previews/tests.

### Fix 2.3 — `AIProgramPlanner`: LLM proposes, engine disposes

**File (new):** `Tempo/Tempo/Services/Engines/AIProgramPlanner.swift` (net-new module — justified: it's the LLM↔engine reconciliation layer, no existing home).

Contract — **the LLM output is advisory; the engine clamps it:**

```swift
/// Calls TrainingProgramService (Sonnet) for a weekly skeleton, then
/// RECONCILES against the deterministic week plan. The deterministic plan
/// wins on safety: AI may reorder/retune within bounds but can never violate
/// T-0/T-1/T+1 football rules or push volumeAdjustment outside [0.5, 1.1].
@MainActor
final class AIProgramPlanner {
    private let api: APIClient
    private let engine: any TrainingEngineProtocol

    func planWeek(
        deterministicPlans: [WorkoutPlan],
        recovery7Day: [Int],
        recentSessions: [String],
        footballDays: ActiveDays,
        goal: String
    ) async -> [WorkoutPlan] {
        guard let ai = try? await api.request(.trainingProgram(),
            body: buildRequest(...)) else {
            return deterministicPlans       // API down → floor, unchanged
        }
        return reconcile(ai: ai, floor: deterministicPlans, football: footballDays)
    }

    /// Engine is the referee. AI can adjust volume within clamp + swap accessory
    /// emphasis; it CANNOT add legs on T-1, cannot exceed the deterministic
    /// recoveryAdjustment ceiling, cannot turn a red-recovery rest into training.
    private func reconcile(ai: DayPlanTrainingProgramResponse,
                           floor: [WorkoutPlan],
                           football: ActiveDays) -> [WorkoutPlan] { /* clamp logic */ }
}
```

**Wire into** `loadWeekPlan` (`TrainingViewModel.swift:202` path): after the deterministic `generateWeekPlan`, if `apiClient != nil` **and** Pro **and** AI-consent, call `AIProgramPlanner.planWeek` and use the reconciled result. Else use the deterministic plan. The floor is the default, the LLM is the upgrade.

### Fix 2.4 — Live mid-session adjustment (Haiku)

When today's actual recovery diverges ≥10 points from what the week plan assumed, offer a one-tap "re-tune today." Calls `.trainingAdjustment()`, applies `volumeAdjustment`/`dropExercises` **after** clamping through the engine. Trigger point: `loadToday` (`TrainingViewModel.swift:192`) after recovery resolves. Show as a dismissible card — never auto-mutate an in-progress workout.

### Fix 2.5 — Gating, budget, cost ceiling (REQUIRED — CLAUDE.md AI guardrail)

- Both calls behind the existing Pro + AI-consent middleware (already enforced server-side — `SubscriptionMiddleware`).
- Program call: **cached 7 days** server-side already; client calls it **once per week** max (guard on `weekStart`).
- Adjustment call: **once per day** max (guard on date), user-initiated only.
- `#if DEBUG` verbose logging of every call + a hard client-side daily counter. State the ceiling in the PR: "≤1 Sonnet + ≤1 Haiku call per user per day, both Pro-gated, both cached."

**Phase 2 exit:** on-device trace shows a real network call to `/v1/insights/training-program` on week load for a Pro user, reconciled against the floor; offline still produces the deterministic plan. Per CLAUDE.md L145, verify on a **real ⌘R device run**, not a CLI build — a green `xcodebuild` proves compile only. Score 7.5: LLM in the live loop, safety floor intact.

---

## PHASE 3 — On-device learning / personalization (7.5 → 9)

This is the jump from "adapts to inputs" to "learns *you*." No server round-trip — privacy-preserving, offline, free.

### Fix 3.1 — `AdaptiveProfile` model

**File (new):** `Tempo/Tempo/Models/Training/AdaptiveProfile.swift` (`@Model`, one row per user, SwiftData).

```swift
@Model
final class AdaptiveProfile {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date

    /// Per-exercise learned increment (kg), keyed by Exercise.id. Starts at the
    /// equipment default; nudged up when the user repeatedly accelerates (Fix
    /// 1.1 acceleratedEasyLoad), nudged down after repeated holds/failures.
    var learnedIncrements: [UUID: Double]

    /// Signed offset (points) on the user's recovery thresholds. A user who
    /// trains well at "yellow" earns a negative offset (green starts lower);
    /// one who craters at yellow earns positive. Clamped ±10 to stay safe.
    var recoveryThresholdOffset: Double

    /// EWMA of recent avgRPE — the fatigue trend. Rising trend at constant load
    /// = accumulating fatigue → bias toward deload earlier than the fixed cycle.
    var fatigueEWMA: Double?

    func learnedIncrement(for exerciseID: UUID) -> Double? { learnedIncrements[exerciseID] }
}
```

### Fix 3.2 — `AdaptiveProfileUpdater` (the learning rule)

**File (new):** `Tempo/Tempo/Services/Engines/AdaptiveProfileUpdater.swift`
Runs on workout save. Pure, deterministic, fully testable — "learning" here is bounded online stat updates, not a trained NN (right call for safety + auditability):

```swift
/// After each saved session, nudge the AdaptiveProfile. All updates bounded
/// and reversible — this never makes a wild jump, it converges over weeks.
func ingest(session: [ExerciseHistory], into profile: AdaptiveProfile) {
    for h in session {
        guard let exID = h.exercise?.id else { continue }
        let base = profile.learnedIncrements[exID] ?? defaultFor(h)
        switch h.avgRPE {
        case let r? where r <= 6.0:  // consistently easy → learn bigger steps
            profile.learnedIncrements[exID] = min(base * 1.1, base + 1.0)
        case let r? where r >= 8.5:  // consistently hard → learn smaller steps
            profile.learnedIncrements[exID] = max(base * 0.9, base - 1.0)
        default: break
        }
    }
    // fatigue EWMA + threshold offset updates...
}
```

### Fix 3.3 — Adaptive recovery thresholds

**File:** `TrainingEngine.swift:431` — `classifyRecoveryZone` becomes profile-aware:

```swift
private func classifyRecoveryZone(score: Double?, offset: Double = 0) -> RecoveryZone {
    guard let score else { return .green }
    if score >= 67 + offset { return .green }
    if score >= 34 + offset { return .yellow }
    return .red
}
```

Thread `profile.recoveryThresholdOffset` through `generateWorkout`/`generateWeekPlan`. **Clamp ±10** so a learned offset can never invert the safety meaning of red.

### Fix 3.4 — Fatigue-triggered deload (replaces pure calendar)

**File:** `TrainingEngine.swift:412` — `isDeloadWeek` gains a fatigue path. Currently purely periodic (`weeksSinceStart % frequency == 0`). Add: if `fatigueEWMA` rising across 3 sessions at flat/declining load **or** sleep-debt signal, trigger deload early. The docs (`MODULE_TRAINING.md §19`) already *spec* fatigue-based deload — it was never built. Build it.

### Fix 3.5 — Tests
`AdaptiveProfileUpdaterTests`: easy sessions raise the increment (bounded), hard sessions lower it (bounded), offset clamps at ±10, EWMA monotonic under constant RPE. **Convergence test:** 8 simulated easy sessions converge to a higher stable increment, not runaway.

**Phase 3 exit:** two users with identical Whoop scores but different RPE histories get **different** prescriptions. That's the definition of personalization — and the 9. Verify on device.

---

## PHASE 4 — Outcome validation (9 → 10)

The thing that separates "personalized" from "intelligent": the system grades its own prescriptions and corrects.

### Fix 4.1 — `TrainingOutcomeEvaluator`

**File (new):** `Tempo/Tempo/Services/Engines/TrainingOutcomeEvaluator.swift`
Weekly, on the first session of a new week, score the *previous* week:

```swift
struct WeekOutcome: Sendable {
    let plannedProgressionHits: Int      // exercises that hit their target
    let overreachEvents: Int             // sessions with RPE≥9 OR form break
    let missedSessions: Int
    let netVolumeChange: Double
    let qualityScore: Double             // 0...1 — progress WITHOUT overreach
}

/// Did last week's plan produce progress without overreaching? Feeds the
/// AdaptiveProfile AND the next Sonnet program prompt (closing the macro loop).
func evaluate(lastWeek: [ExerciseHistory], plan: [WorkoutPlan]) -> WeekOutcome
```

### Fix 4.2 — Feed outcome back into both loops
- **Into `AdaptiveProfile`:** low `qualityScore` from overreach → globally damp increments + nudge thresholds conservative. High score with no overreach → permit slightly more aggressive progression.
- **Into the Sonnet prompt:** add last week's `WeekOutcome` summary to `recentSessions` in `TrainingProgramInput` (`TrainingProgramService.swift:72`) so the LLM plans against *measured results*, not just raw recovery numbers. This is the macro feedback loop — the system's plan quality now compounds.

### Fix 4.3 — Surface it (trust + the "intelligent" feel)
A weekly "Coach Review" card: "Last week: 6/7 sessions, 4 PRs, 0 overreach. Bumping bench progression. Holding squat — your RPE trend is climbing." Reads the `WeekOutcome` — no new compute. **This is what makes a user *believe* it's a 10**, and it's honest because every number is real.

### Fix 4.4 — Tests
`TrainingOutcomeEvaluatorTests`: progress-without-overreach → high score; progress-with-overreach → penalized; missed sessions → penalized; feedback actually changes the next profile state.

**Phase 4 exit:** a full simulated month shows the system measurably tightening prescriptions after overreach and loosening after easy weeks — *self-correcting*. That's the 10.

---

## §2 — Full file manifest

**Edit (existing):**
| File | Change |
|---|---|
| `Services/Engines/TrainingEngine.swift` | Fix 1.1 sizing, 1.2 breath, 3.3 thresholds, 3.4 fatigue deload |
| `Services/Engines/TrainingEngineProtocol.swift` | `ProgressionDecision`, new signatures |
| `ViewModels/TrainingViewModel.swift` | Fix 2.2 APIClient, 2.3/2.4 wiring |
| `ViewModels/TrainingViewModel+ExercisePopulation.swift` | consume `ProgressionDecision` |
| `App/ServiceContainer.swift` | thread `apiClient` into TrainingViewModel |
| `Services/Network/APIEndpoints.swift` | Fix 2.1 two endpoints + DTOs |
| `Models/Training/ExerciseHistory.swift` | `gassedFraction` (1.2) |
| session-save aggregation site | aggregate `gassedFraction` |

**Create (new — all justified: tests dir, new `@Model`, or LLM/learning modules with no existing home):**
| File | Phase |
|---|---|
| `Models/Training/AdaptiveProfile.swift` | 3 |
| `Services/Engines/AIProgramPlanner.swift` | 2 |
| `Services/Engines/AdaptiveProfileUpdater.swift` | 3 |
| `Services/Engines/TrainingOutcomeEvaluator.swift` | 4 |
| `TempoTests/Engines/TrainingEngineProgressionTests.swift` | 1 |
| `TempoTests/Engines/AdaptiveProfileUpdaterTests.swift` | 3 |
| `TempoTests/Engines/TrainingOutcomeEvaluatorTests.swift` | 4 |

**Backend:** no new services needed — `TrainingProgramService` / `TrainingAdjustmentService` already exist and are correct. Phase 4.2 only *adds a field* to the existing `TrainingProgramInput` summary string. Do **not** modify committed migrations.

---

## §3 — Risk register

| Risk | Mitigation |
|---|---|
| LLM proposes unsafe plan (legs on T-1, train through red) | `reconcile()` clamps against deterministic floor; floor wins on every safety rule. Tested. |
| Learning runs away (increment spirals up) | All updates bounded (`±1kg`, `×1.1` cap) + convergence test. |
| Adaptive threshold inverts red-zone safety | Offset clamped ±10; red can never become trainable. |
| API cost creep | Pro-gated + server-cached + ≤1 Sonnet/≤1 Haiku per user/day + `#if DEBUG` counter. |
| SwiftData migration breaks | All new fields additive + optional/defaulted (matches existing Tier-2 pattern). |
| Shared-model desync | `AdaptiveProfile`/`ExerciseHistory` read by Move quadrant too — run enumerate-the-readers + `architecture-guard` per CLAUDE.md before declaring any phase done. |

## §4 — Verification discipline (per CLAUDE.md L145 + stale-build rule)

Each phase exits **only** on an on-device ⌘R observation of the specific path, never a CLI build:
- P1: device log shows `acceleratedEasyLoad` firing on a real easy session.
- P2: network trace shows the program call on week load for a Pro user; airplane mode → identical deterministic plan.
- P3: two RPE histories → two different prescriptions, observed on device.
- P4: simulated month self-corrects (unit-level) + Coach Review card renders real numbers on device.

A green `xcodebuild` proves compilation only. "Verified" requires the named path exercised on the phone after a confirmed fresh build.

---

## §5 — Honest ceiling

This reaches a **defensible 10 for a consumer training app**: closed feedback loop, LLM-in-loop with a safety floor, on-device personalization, and outcome-validated self-correction. It is **not** a sports-science research system — no force-plate data, no validated RPE-to-1RM individual regression, no periodization model peer-reviewed against outcomes. Those aren't realistic for an iPhone app and aren't what "10/10" means here. The 10 is: *the system measurably learns the individual user and corrects its own prescriptions, while never being able to prescribe something unsafe.* That's the right target, and every piece above is buildable with the stack already in the repo.
