# Intelligent Training System — Buildable Spec

**Status:** Implementation spec, pre-build. Analysis-agent reviewed (verdict WEAK→corrected); ground-truth fixes applied in §2-CORRECTIONS, §5, §7, §8, §12. **Code re-verification pass (2026-06-09):** every file:line claim re-checked against live code. Corrected: the goal field (none exists — `"hypertrophy"` is hardcoded at `AIProgramPlanner.swift:383`, not a stored string); `WhoopWorkout` zones/distance (exist in backend + Whoop API, dropped at the iOS `WhoopWorkoutData` mapping — a DTO-widening task, not a data gap); `DailyRecovery` field name (`strain`, not `dayStrain`; `sleepScore`, not `sleepPerformance`); the existing T-1 rule (swaps ANY legs→upper, intensity-agnostic — NOT "heavy legs"; §12's heavy-legs-48h is the net-new extension); and the `WorkoutType` enum mapping in §13.1 (bare `push/sprint/…`, no `gym_`/`field_` prefixes). Awaiting Nicola approval.

> ## ⚠️ §2-CORRECTIONS — three ground-truth errors the review caught (verified against code). Read before building.
> 1. **There is NO goal field today — not even a string.** `generateWorkout` reads recoveryScore/footballDays/split only; rep targets are just `isCompound ? 8 : 12` (`TrainingEngine.swift:154`). No `trainingGoal` on `UserSettings`/`UserProfile`. The dual-goal model is **net-new end-to-end** (model + onboarding + every consumer), not a string→struct widening.
> 2. **Per-activity Whoop strain: PARTIALLY stored (this correction was itself revised on second audit).** `WhoopWorkoutData` is a live-fetched `struct` (`WhoopServiceProtocol.swift:108-116`) — strain/avgHR/maxHR/calories/duration/sportID/startTime, **no HR zones, no distance on the iOS struct** (they exist in the backend `WhoopWorkout` model and the Whoop API but are dropped at the iOS mapping boundary — see the §2 "Already wired" entry; widening is a build task, not a data gap). It DOES persist: `ActivitySession` is a live `@Model`; `TrainingViewModel.persistNonGymCompletion` (~`:1573`) writes strain/HR/calories/duration from a matched Whoop activity. **Caveat:** strain persists ONLY when Whoop tracked + matched the activity — **manual attestation writes strain = nil.** Consumed today only for completion detection, never fed to the next prescription. `RunSession` is defined with **ZERO write path** (dead code) → runs uncaptured. **No whole-session RPE anywhere** — only per-set gym RPE (`SetFeedback`). See §13 for the per-modality outcome table + the JSON schema.
> 3. **The existing AI returns PLAIN TEXT, not JSON.** `RecoveryInsight.body: String` (`RecoveryInsight.swift:25`); the proxy returns a paragraph. The structured `{modality, intensity, blocks, why}` JSON the floor needs is **net-new** — requires a schema-in-prompt, a parser, and (critically) a **parse-fail → deterministic-floor fallback** that this spec MUST define. "Mirrors RecoveryAIInsightService exactly" was false on the one dimension that matters. See §5.2-FIX.
>
> Also: day-strain ACWR IS computable cold from the 30-day `DailyRecovery.strain` backfill; per-MODALITY load decomposition is NOT (depends on correction #2's forward-accruing store).
**Author:** Claude (Opus 4.8), 2026-06-09
**Supersedes the framing of:** `docs/TRAINING_INTELLIGENCE_TO_10.md` (progression-math focus). That work is NOT discarded — see §8 (Existing-Work Disposition), pending analysis.

---

## §0 — What this is, in one paragraph

A Whoop-body-data-driven daily training system. Every day it reads the FULL picture of Nicola's body (all Whoop signals, not just the recovery score), what he actually did (Whoop-detected activity strain + logged feedback), his body-composition trend (Withings → Apple Health), his goal (dual: soccer performance + physique), and his real-world constraints (which venue/time, learned from habit), then produces ONE drill-sergeant prescription for the day via a daily Claude call — with a thin deterministic safety floor that can veto "train hard" when objective markers scream rest. Monthly, it runs a logged interview + a rich body-composition-backed summary.

This is **mostly a decision-layer + data-assembly build, not a data-pipeline build** — the audit proved the data the *first slice* needs (recovery/HRV/RHR/sleep/day-strain in `DailyRecovery`, body-comp via HealthKit) is already fetched, stored, and on-device; it's just ignored at decision time. **The one genuine exception is per-modality load:** Whoop per-activity HR zones never reach iOS and distance is dropped at the `WhoopWorkoutData` mapping (§2), so any zone/distance-aware *per-modality* intelligence DOES need real pipeline work (DTO widening / backend fetch). That's deferred enrichment, not first-slice work — the shippable slice stays pure assembly.

---

## §1 — Locked design decisions (from the 16-question interview)

| # | Decision | Value |
|---|---|---|
| 1 | Goal model | **Dual**: soccer performance + physique/hypertrophy, both meaningfully pursued |
| 2 | Autonomy | **Drill-sergeant**: ONE prescription/day, execute or don't (no menu) |
| 3 | Body-data vs motivation | **Body data wins** — hard safety floor; Whoop can hold him back |
| 4 | Explanation | **Short why + tap for detail** (terse default, full reasoning on demand) |
| 5 | Modalities | **Gym + field/sprint + pool + running + home/bodyweight** + mobility/rest |
| 6 | Environment input | **Learned-pattern-then-confirm**: "Gym day — you usually go ~4PM, can you make it?" Not a blank daily form, not static settings. |
| 7 | Match calendar | **Irregular** — Nicola enters matches as they come; system re-periodizes around each |
| 8 | Extra daily inputs | Whoop + per-set feedback + **subjective morning check-in** (mood/soreness/stress) + nutrition state + calendar load |
| 9 | Pattern learning | **Deep**: learns times, days, modalities, durations, skips → proposes the week pre-filled |
| 10 | Post-session feedback | Per-set RPE/form (exists) + **whole-session rating** + **adherence (did it/skipped/modified)** + **Whoop auto-confirm** |
| 11 | Long-term arc | **Monthly**: end-of-month logged interview/quiz + rich summary backed by **Withings body-comp** (weight, fat%, muscle%) |
| 12 | AI creativity | **Adaptive** — AI has real latitude to design each day within goal + readiness |
| 13 | Withings | Already → Apple Health → **consume via existing HealthKit** (`fetchBodyComposition()`), no direct OAuth |
| 14 | Build strategy | **Deferred to analysis agent** (§7 presents options + dependency/risk) |
| 15 | Existing-work relationship | **Deferred to analysis agent** (§8 presents keep-vs-supersede) |
| 16 | Doc type | **Buildable spec** — phases, files, steps, tests (this document) |

---

## §2 — Ground truth from the codebase (what exists vs. what's missing)

**Already wired (consume, don't build):**
- **Full Whoop fetch + store**: recovery, HRV (`hrvRmssd`), RHR (`restingHR`), respiratory rate, SpO2, skin temp, full sleep stages (`deepSleepMin`/`remSleepMin`/`lightSleepMin`/`awakeMin`), sleep score/efficiency/consistency (`sleepScore`/`sleepEfficiency`/`sleepConsistency` — NB: it's `sleepScore`, there is no `sleepPerformance` field), day strain (the field is `strain: Double?`, not `dayStrain`) — all in `DailyRecovery` (`Models/Recovery/DailyRecovery.swift`). 30-day backfill on connect.
- **Per-activity Whoop strain**: the **backend `WhoopWorkout` Fluent model** (`tempo-backend/Sources/App/Models/WhoopWorkout.swift`) persists the rich set — strain, avg/max HR, distance (`distance_meter`), altitude, and **6 HR zones** (`zone_zero_milli`…`zone_five_milli`). **But iOS does NOT receive most of it.** `fetchWorkouts(for:)` hits the Whoop `/activity/workout` API directly and maps into `WhoopWorkoutData` (`WhoopService.swift:761`), which carries only strain/avgHR/maxHR/calories/duration/sportID/startTime. The iOS decode DTO (`WhoopAPIWorkoutScore`) *does* decode `distanceMeter` — then **drops it** at the mapping step; HR zones are **never decoded** on the iOS path. So zones+distance are *available upstream*, **discarded at the iOS boundary** — surfacing them is a DTO-widening build task (decode + pass through, or fetch from the backend store), NOT a missing-data gap. *Today: strain etc. stored on `ActivitySession`, ignored at decision time.*
- **Body composition via HealthKit**: `HealthKitService.fetchBodyComposition()` → weight (kg), body-fat %, lean mass, timestamp. `.bodyMass`/`.bodyFatPercentage`/`.leanBodyMass` already in read auth (`HealthKitService.swift:496–518`, `HealthKitConstants.swift:35–47`). **Withings data already flows here.**
- **Daily AI call pattern**: `RecoveryAIInsightService` — `NutritionProxyTextRequest(model:system:userMessage:maxTokens:temperature:caller:)` → `nutritionProxyText()` endpoint, retry+backoff, single-flight dedup, SwiftData cache, backend 402 = Pro/consent gate. Haiku for daily; Sonnet exists for weekly `planWeek()`.
- **Daily AI hooks + card UI**: `TrainingViewModel.loadToday` (hooks at `:271`/`:277`/`:280`); `TodayWorkoutView.adjustmentCard` (`:296–361`) is the reusable card+why+buttons pattern.
- **Persisted run-once guards**: `AdaptiveProfile.lastAIHydratedWeekKey` / `lastAdjustmentCheckedDayKey` / `lastOutcomeReviewWeekKey` — the correct daily/weekly-cap pattern.

**Used at decision time today:** recovery score (→ zone), day strain, sleepHours/efficiency. **That's it.** HRV, RHR, respiratory, sleep stages, SpO2, skin temp, per-activity strain, body-comp = **dead code for decisions.**

**Net-new (must build):**
- Trend/baseline assembly from stored history (HRV-vs-baseline, RHR-vs-baseline, deep-sleep adequacy, acute-vs-chronic strain).
- Subjective morning check-in (model fields + UI) — no mood/soreness anywhere today.
- Per-activity strain surfaced into the daily picture (data exists, not assembled).
- The daily training-readiness Claude call (new caller, new prompt, new cache type).
- The safety floor (veto rules).
- Modality model (gym/field/pool/run/home/mobility/rest) — engine is gym-only today.
- Goal model expansion (soccer + physique). **There is NO persisted goal field today** (not on `UserSettings` or `UserProfile`) — the only "goal" is the string literal `"hypertrophy"` hardcoded at `AIProgramPlanner.swift:383` when calling `planWeek()`. So this is net-new model + onboarding + every consumer, not a string→struct widening (see §2-CORRECTIONS #1).
- Venue/time pattern learning + confirm flow.
- Match-calendar entry + re-periodization.
- Monthly interview + body-comp summary.

---

## §3 — Architecture (the daily decision pipeline)

```
                         ┌─────────────────────────── DAILY ───────────────────────────┐
INPUTS (mostly already stored)                    ASSEMBLY (new)            BRAIN            FLOOR (new)        OUTPUT
─────────────────────────────                    ───────────────          ───────          ──────────         ──────
Whoop: recovery, HRV, RHR, resp,  ─┐
  SpO2, skin temp, sleep stages    │
Whoop per-activity strain (yesterday)──► ReadinessAssembler ──► full picture ─► Claude ────► SafetyFloor ────► ONE session:
Withings body-comp (HealthKit)    ─┤    • HRV vs baseline       + 7-day        (Haiku,        can DOWNGRADE      modality, intensity,
Per-set feedback (exists)          │    • RHR vs baseline        trends         daily,         "train hard" →     duration, the work,
Whole-session rating (new)         │    • deep-sleep adequacy    + goal         adaptive)      rest/recovery       short "why" (tap=full)
Adherence (new)                    │    • acute:chronic strain   + venue        designs day    when markers
Morning check-in (new)             │    • body-comp trend        + match cal                   are severe
Venue/time pattern (learned, new) ─┘    • adherence pattern      + check-in
Match calendar (new)                                             + history
Nutrition state (exists) / calendar load (exists)
```

**Cadence:** fires once per day (persisted guard), re-fires on a new Whoop sync or a freshly logged session — never on a render loop (protects the 5h rate-limit window; body data doesn't change minute-to-minute).

**Why a floor under a full-Claude brain:** Nicola chose "feed everything to Claude." Correct for *reasoning*. But an LLM that says "go hard" on a day RHR is spiked + HRV crashed + sleep debt high can cause injury. The floor is a thin deterministic veto on the *dangerous* edge only — Claude owns modality/intensity/voice; the floor owns "not on a clearly-cooked day." (Decision #3: body data wins.)

---

## §4 — Data model & assembly layer (build first; everything depends on it)

### 4.1 `ReadinessAssembler` (new, pure, `Services/Engines/ReadinessAssembler.swift`)
Pure functions over arrays of `DailyRecovery` (history already stored). No network. Produces a `ReadinessPicture` value type:

```
struct ReadinessPicture {
  // today's raw
  recoveryScore, hrv, rhr, respRate, spo2, skinTemp
  sleepHours, deepSleepMin, remSleepMin, sleepEfficiency
  strain                       // NOTE: the field is `DailyRecovery.strain` (Double?), NOT `dayStrain`
  // computed trends (THE missing intelligence)
  hrvVsBaseline: Double        // today vs 30-day mean, % and z-score
  hrvTrend7d: .rising/.flat/.falling
  rhrVsBaseline: Double
  deepSleepAdequacy: Double     // deep min vs personal norm
  acuteChronicStrainRatio: Double  // 7-day strain load vs 28-day (overreach flag)
  // yesterday's actual work (from WhoopWorkout — surfaced, not ignored)
  yesterdaySessions: [{ type, strain, durationMin, avgHR }]
  // body composition trend (Withings via HealthKit)
  weightKg, bodyFatPct, leanMassKg, bodyCompTrend30d
  // subjective
  checkIn: { mood, soreness[bodyPart:level], stress } | nil
}
```
Baselines computed from the 30-day `DailyRecovery` history. **Tested**: trend math, baseline windows, empty/partial-history fallbacks.

### 4.2 Subjective check-in (new)
- `MorningCheckIn` fields on a model (extend `DailyRecovery` or new `@Model`): `mood: Int?`, `sorenessRaw: String?` (JSON bodyPart→1-10), `stress: Int?`, `capturedAt`.
- 5-second UI: a Today-screen tap-card, dismissible, written same-day.

### 4.3 Body-comp surfacing
- Call existing `HealthKitService.fetchBodyComposition()`; store daily snapshots (new `BodyComposition` `@Model` or reuse) so a 30-day trend exists for the monthly summary.

### 4.4 Modality + goal model (new)
- `TrainingModality` enum: `.gymHypertrophy, .gymStrength, .gymPower, .fieldSprint, .fieldAgility, .fieldSkill, .poolRecovery, .poolConditioning, .run(tempo/interval/long), .homeBodyweight, .mobility, .rest`.
- `TrainingGoal` expanded from the current string to a structured dual goal: `{ soccerWeight: Double, physiqueWeight: Double }` + phase.

---

## §5 — The daily brain (the Claude call)

### 5.1 `DailyReadinessCoach` (new, `Services/Engines/DailyReadinessCoach.swift`)
Mirrors `RecoveryAIInsightService` exactly:
- Builds `NutritionProxyTextRequest(model: "haiku", caller: "daily_training", maxTokens: ~700, temperature: 0.6, system: <coach prompt>, userMessage: <ReadinessPicture + goal + venue + matchCalendar serialized>)`.
- Single-flight dedup; SwiftData cache. **Storage is NOT free choice — §8's cadence contract requires a dedicated `DailySession` `@Model` linked 1:1 to today's `WorkoutPlan`** (the link is the desync guard for non-gym modalities). A `RecoveryInsight` string-type cache is insufficient — it can't hold structured blocks or carry the `WorkoutPlan` link.
- Persisted once-per-day guard: `AdaptiveProfile.lastDailySessionDayKey`.
- Retry+backoff; backend 402 = not-Pro/no-consent → silent fallback to the deterministic floor's own pick.
- **Model note:** daily = Haiku (cost/latency). Consider Sonnet for the monthly summary only.

### 5.2 The prompt shape (structured output)
System prompt establishes: drill-sergeant Tempo voice, dual goal (soccer+physique), the available modalities, the rule that body-data wins. User message carries the serialized `ReadinessPicture` + venue-for-today + upcoming matches + last session + adherence. **Claude returns JSON**: `{ modality, intensity, durationMin, blocks:[...], shortWhy, fullWhy }`. JSON so the floor can inspect/clamp it and the card can render it.

### 5.2-FIX — The prompt IS the product. Spec it like one (review G1 + C4).
The review's top finding: "feed serialized ReadinessPicture + goal" is a data dump, not a prompt — Haiku at temp 0.6 will return plausible garbage the floor can only catch on the *dangerous* edge, not the *useless* edge (e.g. a tempo run the day before a match). The brain's prompt MUST include, as first-class deliverables of D2:
- **A fixed JSON output schema embedded in the system prompt** (not just "return JSON").
- **2–3 worked exemplars** — a good dual-goal session, a recovery-day session, and a vetoed→downgraded example — so Haiku has a target shape.
- **An explicit dual-goal weighting instruction** (see §12 interference rule) — "today is soccer-emphasis, cap lifting volume / space conditioning ≥6h from heavy legs."
- **A parse-fail fallback path (REQUIRED):** JSON parse failure / truncation / prose-preamble → fall back to the deterministic engine's own pick for the day. Never show a half-parsed session. This path is net-new (the existing proxy returns text, so there is no parser today).
- **A `#if DEBUG` prompt harness:** run ~20 synthetic `ReadinessPicture`s through the REAL Haiku endpoint, assert every response parses AND passes the floor. If it can't reliably produce clean structured output, the architecture is in question — and you've learned it for one phase's cost, not the whole build. **This harness is the first thing built in D2.**

### 5.3 Output → `DailySession` value/model
Rendered in `TodayWorkoutView` via the `adjustmentCard` pattern: title (modality), short why, tap → full why, the block list. Drill-sergeant single prescription (Decision #2).

---

## §6 — The safety floor (new, the veto)

`TrainingSafetyFloor` (pure, `Services/Engines/TrainingSafetyFloor.swift`): takes the Claude `DailySession` + `ReadinessPicture`, returns a possibly-downgraded session.

Hard rules (tiered per Decision #3). All numeric thresholds below are concrete and implementable; each is tagged **[L]** (literature-locked — change only with new evidence) or **[D]** (defensible default — tunable knob).

#### 6.1 — Signal pipeline (how baselines & deviations are computed)

All inputs come from the trailing-30-day `DailyRecovery` history already stored. The method, not just the cutoff, matters:

- **HRV (rMSSD) is log-normal and noisy → work in `ln(rMSSD)`, never raw ms. [L]**
  - **Chronic baseline:** rolling **mean and SD of `ln(rMSSD)` over the trailing 30 valid days.** (EWMA is a defensible alternative that tracks fitness drift better, but the floor must be deterministic + unit-testable, so the fixed rolling window wins. **[L]** for the choice of rolling-mean-over-EWMA *given the test requirement*.)
  - **Acute signal:** rolling **mean of `ln(rMSSD)` over the trailing 7 valid days** — NOT a single day. A single day's rMSSD swings ±20% on noise alone (within-person CV); the 7-day mean is the actionable quantity. **[L]**
  - **Deviation = z-score:** `z_hrv = (acute7_lnHRV − baseline30_lnHRV) / baselineSD_lnHRV`. Z auto-adapts to the athlete's own variability; a fixed % cannot, which is exactly why % is the wrong primitive. The spec's old "X% below baseline" maps approximately as: for a typical ln-SD of 0.10–0.18, **z ≤ −1.5 ≈ 15–22% below baseline (7-day mean vs 30-day)** — report that human-readable figure in the UI, but **threshold on z internally.** **[L]** for method; the −1.5 cutoff is **[D]**.
- **RHR is ~normal → raw rolling mean + SD is fine.** `baseline30_rhr` = mean of trailing 30 valid days. Express deviation in **absolute bpm above baseline** (primary, intuitive) with a z-score backstop: `rhr_flag = (restingHR − baseline30_rhr) ≥ +5 bpm` OR `z_rhr ≥ +1.5`. **[D]** (the +5 bpm overtraining/illness elevation is commonly cited but not a bright line).
- **Respiratory rate:** `resp_flag = (respiratoryRate − baseline30_resp) ≥ +2 br/min`. Elevated resp rate is Whoop's documented illness/strain signal **[L]**; the +2 cutoff is **[D]**.
- **Recovery score & sleep:** use the values as-is — Whoop's recovery score already fuses HRV+RHR+resp+sleep, so we do NOT recompute it. We trust the composite for one route and recompute raw deviations only as an *independent second route* (below). Recovery bands are the canonical Whoop / in-code values: **red < 34, yellow 34–66, green ≥ 67** (`RecoveryZone(score:)`). **[L]** Sleep severity reuses the existing `sleepDebt` field and its `isSleepDebtCritical >= 4.0h` convention rather than inventing a parallel hours rule. **[L]** (reuse).

#### 6.2 — Tier thresholds

`classifyFloorTier(_ picture: ReadinessPicture) -> FloorTier` is a **pure function of ordered gates**: evaluate every SEVERE trigger; if none, evaluate MODERATE; else NORMAL.

| Signal | SEVERE | MODERATE | Tag |
|---|---|---|---|
| Recovery score | `< 34` (red) | `34–66` (yellow) | [L] band |
| HRV (`z_hrv`, ln, vs 30d) | `≤ −1.5` **paired with** RHR flag | `≤ −1.0` alone | method [L], cutoff [D] |
| RHR vs 30d baseline | `≥ +5 bpm` (or `z_rhr ≥ +1.5`) | `+3 to +4 bpm` | [D] |
| Resp rate vs 30d baseline | `≥ +2 br/min` AND recovery ≠ green (illness path) | `≥ +1 br/min` | signal [L], cutoff [D] |
| Sleep debt (`sleepDebt`) | `≥ 4h` (existing critical) | `2–4h` | [L] reuse |
| Sleep hours (raw, fallback) | `< 5h` for **2 consecutive** nights | single `< 5h` night | [D] |

**SEVERE** = ANY of (logical OR):
1. **Route A — composite:** `recoveryScore < 34` (red). Trust Whoop's fused score. **[L]**
2. **Route B — raw multi-signal AND-gate** (catches the cooked day Whoop smoothed over): `z_hrv ≤ −1.5` **AND** RHR flag (`≥ +5 bpm` or `z_rhr ≥ +1.5`). This is the spec's original "HRV crash AND RHR spike," made concrete. **[D]** cutoffs.
3. **Sleep route:** `sleepDebt ≥ 4h` **AND** recovery is yellow (not green). High sleep debt on an already-suppressed recovery is the dangerous combination; high sleep debt on a green day is downgraded to MODERATE. **[D]**.
4. **Illness route:** `resp_flag (≥ +2 br/min)` **AND** recovery ≠ green. Elevated respiratory rate is the early-illness tell; training hard while incubating illness is the inviolable veto. **[D]** cutoff.

→ force `.poolRecovery` / `.mobility` / `.rest`; Claude's "go hard" is vetoed; **no override** (Decision #3 = body data wins).

**MODERATE** = NOT severe, AND recovery is yellow (34–66) with at least ONE moderate flag (`z_hrv ≤ −1.0`, RHR `+3–4 bpm`, resp `≥ +1 br/min`, or `sleepDebt 2–4h`). → cap intensity/volume, **allow the modality** (Claude keeps modality choice; the floor clamps load).

**NORMAL** = recovery green (≥ 67) and no moderate flags. → no floor action; Claude's prescription passes through unchanged.

**Physiological rationale (one line each):** HRV suppression = parasympathetic withdrawal / unresolved autonomic load; RHR elevation = the classic overtraining/illness marker (sympathetic dominance, dehydration, infection); the AND-gate avoids vetoing on HRV noise alone; resp-rate rise = Whoop's documented pre-symptomatic illness signal; sleep debt = the single largest modifiable readiness deficit.

#### 6.3 — Missing data & cold-start (the gate protecting every raw route)

- **Minimum to compute an actionable HRV/RHR baseline: ≥ 14 valid (non-nil) samples in the trailing 30 days. [D]** Below that, `z_hrv` / `z_rhr` return `nil` and Routes B and the resp/RHR deviation are **disabled** — the floor degrades to **Route A (recovery zone) + absolute sleep only.** This IS the cold-start mode the spec already references (§G6, "until ~N days accrue"); wire to that concept, do not add a competing one.
- **Compute over valid samples, not calendar days** — gaps just shrink `n`. **Never impute a missing day as 0** — a zero would fake an HRV crash and fire a false SEVERE.
- **Single missing day:** ignore it, compute over what's present.
- **Acute (7-day) window needs ≥ 4 valid of the last 7** to produce a `z`; otherwise that route is nil for the day.

#### 6.4 — Properties

- **Match-protection**: the **existing** T-1 rule (`TrainingEngine.swift:87-90`, `:416-419`) swaps **ANY legs day** (not just "heavy" — it's intensity-agnostic) for an upper day when T-1 to a match. Keep it as a **separate** gate, NOT folded into the readiness tiers (it's schedule-driven, not body-data-driven). §12 *extends* this into a richer no-heavy-legs-within-48h rule across modalities — that extension is net-new; the shipped rule today is the cruder ANY-legs→upper swap.
- Floor is **deterministic + fully unit-tested** (adversarial: feed it a "go hard" Claude session + a cooked `ReadinessPicture`, prove it downgrades; feed each route in isolation; feed sub-14-sample history, prove it falls back to Route A without crashing).

---

## §7 — Build strategy (OPTIONS — analysis agent to recommend)

**Option A — thin end-to-end slice first.** P1: daily Haiku session on data we already have (recovery+strain+feedback) → render card → on device. Then enrich: P2 trend assembly, P3 modalities/venue/check-in, P4 Withings+monthly. Each phase ships usable.
**Option B — full data layer first.** P1: assemble ALL data correctly (per-activity strain, trends, body-comp, patterns), nothing visible. Then build the brain on a complete picture.
**RESOLVED (analysis agent): Constrained A — thinnest end-to-end slice that INCLUDES the minimum trend assembly the prompt needs to be non-garbage.** Pure-A (raw recovery+strain → Claude) reproduces the spec's own top risk: raw snapshots → confident-wrong. Pure-B defers the riskiest unknown (does the prompt work?) to the end after max sunk cost. The slice: HRV-vs-baseline + day-strain acute:chronic (both computable cold from the 30-day `DailyRecovery` backfill) → daily Haiku call → card, shipped on-device fast. The prompt is the risk, so the first slice must carry the minimum that makes the prompt real.

---

## §8 — Existing-work disposition (OPTIONS — analysis agent to recommend)

The prior work (TRAINING_INTELLIGENCE_TO_10 Phases 1–4 + measurement Steps 1–4: progression engine, AIProgramPlanner, AdaptiveProfile learning, PredictionLog spine, error-fit correction, hold-out) is on branch `training-intelligence` / PR #9.

- **Option Keep**: it becomes the **gym-lifting module**. The daily brain decides "today = gym," then delegates weight/rep/progression to the existing engine + prediction spine. Reused, not wasted.
- **Option Supersede**: the daily brain owns the decisions; old deterministic logic → fallback floor only.
- **RESOLVED (analysis agent): KEEP — high confidence, don't hedge.** The prior work is merged and LIVE in the decision path (`AIProgramPlanner.planWeek:44-84`, `AIProgramPlanner.reconcile` with `[0.5,1.1]` clamp `:102-130`, `PredictionLog`, `TrainingOutcomeEvaluator` all present). Superseding = deleting working, tested, safety-clamped, integrated code to rebuild the gym loop inside the LLM — strictly worse. The daily brain sits ABOVE: it decides "today = gym," then delegates set/rep/weight/progression to the existing engine + reconcile + prediction spine. The `PredictionLog` spine becomes the accuracy check the new floor needs.
- **CADENCE — RESOLVED (read/write contract, not "strategy vs tactics"). This is the load-bearing integration spec; build D2 to it.**

  Two AI loops at two cadences: `AIProgramPlanner.planWeek` (`AIProgramPlanner.swift:44-84`) runs once/ISO-week and **writes the persisted `[WorkoutPlan]` records** — one per training day, each carrying its `WorkoutType` (the day's modality/split), reconciled against the deterministic floor with the `[0.5,1.1]` volume clamp (`reconcile`, `:102-130`). The daily brain runs once/day. The desync risk is NOT "who decides intensity" — it's **which record each loop reads and writes.** A daily brain that authors a *competing* `DailySession` diverging from the day's persisted `WorkoutPlan` is the exact shared-model desync CLAUDE.md warns about: the engine fills one record, the card shows another, `PredictionLog` measures a third.

  **The contract (generalizes §13.1's "gym block is a POINTER"):**
  - **Weekly OWNS the modality-default.** `planWeek` decides which day = which `WorkoutType`. The persisted `WorkoutPlan` for today is the **source of truth the daily brain READS** — it does not author a parallel one.
  - **Daily OWNS intensity/volume** within that slot, and modality-OVERRIDE **only under a hard constraint**: floor-SEVERE (→ recovery/rest), venue unavailable (→ §15.4 home fallback), or match T-1 (→ leg swap). A normal-readiness day **keeps the weekly modality** and moves only intensity. Any override stays in-emphasis (physique-week legs→upper, never legs→pool unless readiness forces it).
  - **The daily brain edits today's existing `WorkoutPlan`; it does not author a competing modality decision.** Intensity/volume adjustment + (constrained) modality swap key off the one canonical row, so `populateExercises` and `PredictionLog` stay aligned. This is what makes "weekly = strategy" non-vacuous: if the daily brain could swap modality freely on any day, the `WorkoutPlan`/engine/`PredictionLog` record is orphaned and weekly is decorative — so free daily swapping is explicitly disallowed.
  - **⚠️ The persistence path SPLITS by modality (verified against `WorkoutPlan.swift:13-130`).** `WorkoutPlan` carries `type`, `durationMinutes`, `notes`, `recoveryAdjustment`, status, and a gym-shaped `exercises: [PlannedExercise]` (sets/reps/weights) — and **NOTHING else**: no pool distance/stroke, no run pace, no field reps, and none of the brain's `intensity`/`shortWhy`/`fullWhy`/`cue`. So:
    - **Gym day → "mutate in place, no sibling" is literally true.** `{kind:gym, split:…}` pointer → `populateExercises` fills `PlannedExercise` on the SAME `WorkoutPlan` → `PredictionLog`. One record. This is the path the trace below walks.
    - **Non-gym day (pool/run/field/bodyweight) → there is NO engine and `WorkoutPlan` cannot hold the content.** D2 introduces a **`DailySession` @Model linked 1:1 to today's `WorkoutPlan`** (carrying modality/intensity/blocks/why/cue + the per-modality `expected*` predictions of §13). **The 1:1 link IS the desync guard** (replacing "never a sibling" for these modalities): the `WorkoutPlan` remains the schedule/adherence/status record; the `DailySession` holds the prescription content; they are created and resolved together, never independently. Enumerate-the-readers (CLAUDE.md) applies to this pair specifically. **This 1:1 model + link is net-new D2 work, not yet built** — the gym trace is verified; the non-gym path is specified-but-unverified until D2.

  **Two-path trace — Tuesday, weekly wrote `WorkoutPlan(Tue = legs, physique-week)`:**
  - **(a) Normal readiness, GYM day:** daily brain READS `WorkoutPlan(Tue=legs)` → keeps modality=legs → sets today's intensity from `ReadinessPicture` → emits the gym POINTER `{kind:gym, split:legs}` → existing engine `populateExercises` fills sets/weights on the `WorkoutPlan` → `PredictionLog` written as today. **A `DailySession` IS still created** (1:1-linked) to carry the brain's intensity + shortWhy/fullWhy + floor tier + source — `WorkoutPlan` has no fields for those. So the card reads **why/intensity from `DailySession`, sets from the linked `WorkoutPlan`**. (Revised from an earlier "no new record" framing: a DailySession is created EVERY day so the 1:1 link is uniform, not gym-special-cased — gym just also fills WorkoutPlan.exercises via the engine.)
  - **(a′) Normal readiness, NON-GYM day** (weekly wrote `WorkoutPlan(Tue=pool)`): brain READS `WorkoutPlan(Tue=pool)` → keeps modality=pool → emits a pool block (`distanceM`/`stroke`/`intensityPct`) → **content persists on a `DailySession` @Model linked 1:1 to that `WorkoutPlan`** (since `WorkoutPlan` has no pool fields). The `WorkoutPlan` stays the schedule/status/adherence row; `DailySession` holds the prescription; outcome = sRPE (§13.2) since there's no gym `PredictionLog` here. Two records, one 1:1 link — the link is the guard.
  - **(b) Red readiness (recovery < 34):** daily brain READS the same `WorkoutPlan(Tue=legs)` → `TrainingSafetyFloor.apply` returns SEVERE → the existing legs `WorkoutPlan` is **marked `.skipped` (status set, NOT deleted — preserves the PredictionLog/adherence trail)** and the daily recovery session is shown in its place for the day. Next ISO week, `planWeek` re-plans fresh; the skipped record stays as history.
    - **Verified against code:** `WorkoutStatus` (`WorkoutEnums.swift:59-64`) already has `planned / inProgress / completed / skipped` — `.skipped` is terminal (`isTerminal`) and is the right state; **no new status case is needed.** BUT `.skipped` alone can't tell §15.2 apart a **floor-forced** skip ("plan didn't fit today's body" — NOT a user failure, must not count against adherence/streak) from a **user-flaked** skip (counts). That REASON is a separate concern from status — D2 adds an optional `skipReason` (e.g. `floorForced | userSkipped | venueUnavailable`) on `WorkoutPlan` (additive/optional, matches §10 migration rule), NOT a new `WorkoutStatus` case. The adherence logic (§15.2) reads `skipReason`, not just `status`.

- **MID-WEEK MATCH ENTRY (separate trigger, scope D3):** entering a new match mid-week is a **weekly-replan trigger** (`planWeek` re-runs to re-periodize the surrounding days + taper), distinct from the steady-state daily handoff above. §14 already says the match calendar re-periodizes; this names it as its own trigger so it isn't conflated with the daily loop. Until D3 wires the re-trigger, a mid-week match only drives the schedule-driven match-protection gate (T-1 leg swap) within the already-planned week.

---

## §9 — Phase breakdown (buildable; sequencing per §7 once agent rules)

Each phase: files, steps, tests, exit criteria. (Phase numbers are logical, not yet ordered.)

### Phase D1 — Readiness assembly + body-comp + check-in
- **Files (new):** `ReadinessAssembler.swift`, `ReadinessPicture` type, `MorningCheckIn` model + fields, `BodyComposition` snapshot model + daily store hook.
- **Files (edit):** `TempoSchemaV1.swift` (register new models), `RecoveryViewModel`/sync (snapshot body-comp daily), `DailyRecovery` (check-in fields).
- **Steps:** compute HRV/RHR baselines from 30-day history; acute:chronic strain; surface `WhoopWorkout` yesterday-sessions; wire `fetchBodyComposition()` daily snapshot; build check-in card.
- **Tests:** trend/baseline math, partial-history fallback, acute:chronic ratio, check-in persistence.
- **Exit:** `ReadinessPicture` assembles correctly from real stored data (unit) + renders check-in on device.

### Phase D2 — Daily brain + safety floor
- **Files (new):** `DailyReadinessCoach.swift`, `TrainingSafetyFloor.swift` *(first-cut built in D0)*, `DailySession` `@Model` **with a 1:1 `WorkoutPlan` relationship** (§8 desync guard), daily prompt *(built in D0 as `DailyCoachPrompt`)*. **Edit:** `WorkoutPlan` gains optional `skipReason` (§8); `WorkoutType` gains `pool`/`agility` cases (§13.1).
- **Files (edit):** `TrainingViewModel.loadToday` (add call after `:277`), `AdaptiveProfile` (`lastDailySessionDayKey`), `TodayWorkoutView` (session card).
- **Steps:** build/gate/cache the Haiku call (mirror RecoveryAIInsightService); JSON output parse; floor veto rules; card render; once-daily guard.
- **Tests:** floor downgrades dangerous sessions (adversarial), JSON parse robustness, once-daily guard idempotent across relaunch, offline → floor fallback.
- **Exit:** on device, a real daily session renders from a real Claude call for a Pro user; airplane mode → deterministic fallback; severe-readiness day → floor forces recovery.

### Phase D3 — Modalities, goal, venue-pattern, match calendar
- **Files (new):** `TrainingModality`, structured `TrainingGoal`, venue-pattern learner, match-calendar model + entry UI.
- **Steps:** expand goal in onboarding (soccer+physique sliders); modality-aware prescription; learn venue/time patterns → "usual 4PM?" confirm; match entry → re-periodize.
- **Tests:** pattern learner converges to real habit, match T-1 protection across modalities, goal-weighting changes prescription.
- **Exit:** on device, prescriptions span modalities, confirm-venue flow works, a logged match re-shapes the surrounding days.

### Phase D4 — Monthly arc
- **Files (new):** `MonthlyReview` model, monthly interview UI, monthly summary generator (Sonnet — richer), body-comp delta report.
- **Steps:** end-of-month logged interview; summary ("gym X times, +20lbs strength, always ~4PM, missed these days, +5kg @ 9.5% fat / 87% muscle from Withings"); marker tracking (sprint/HR-recovery/PRs/strain tolerance).
- **Tests:** summary aggregation correctness, body-comp delta math, marker trends.
- **Exit:** on device, a real month produces an accurate logged summary backed by Withings body-comp.

---

## §10 — Cross-cutting requirements

- **AI cost/gate (CLAUDE.md rule):** every Claude call Pro+consent gated (backend 402), once-daily (D2) / once-monthly (D4) persisted caps, `#if DEBUG` call logging. State ceiling in each PR: "≤1 Haiku/day + ≤1 Sonnet/month per user."
- **5h-window discipline:** fire on real change (new sync / logged session / new day), never on render.
- **Verification (L145):** no phase is "done" off a green build — each exits on an on-device ⌘R observation of the named path. Two new SwiftUI surfaces (session card, check-in, monthly) need device render confirmation.
- **Shared-model safety (CLAUDE.md):** `ReadinessPicture`/`DailyRecovery`/`AdaptiveProfile` are read by multiple surfaces — run enumerate-the-readers + `architecture-guard` before declaring any phase done.
- **Migrations:** all new model fields additive/optional (pre-launch single V1 schema, matches existing pattern).

## §12 — Dual-goal interference model (review G2/G3 — the training-science core that was MISSING)

The original spec modeled the dual goal as two weights and never said how the brain resolves their conflict. That's the difference between real dual-goal coaching and "do both, badly." Soccer conditioning and hypertrophy actively interfere (the **concurrent-training effect**): high running/sprint volume blunts hypertrophy; heavy leg strength work blunts sprint/change-of-direction. The system MUST encode this or it will prescribe self-sabotaging combinations.

**Rules the brain + floor must enforce (net-new):**
- **Spacing:** heavy lower-body strength and high-intensity conditioning/sprint work are NOT prescribed in the same ~24-48h on the same muscle groups; lift and conditioning ideally ≥6h apart or on alternating-emphasis days.
- **Emphasis weeks, not emphasis days:** the weekly planner (§8 cadence — it OWNS the modality-default per the read/write contract there) sets a soccer-emphasis or physique-emphasis bias for the week; the daily brain prescribes within it, adjusting intensity and (only under a hard constraint) overriding modality in-emphasis. You cannot maximize both in the same microcycle — the system picks a primary per block and protects the other at maintenance.
- **Match protection extends to lifting:** no heavy legs in the 48h before a logged match. This **extends** the existing T-1 rule — which today is a blunt "swap ANY legs day → upper at T-1" (`TrainingEngine.swift:87-90`, intensity-agnostic, 1-day window) — into an intensity-aware, 48h-window rule across modalities. The widening (intensity tiers + 48h + modality-aware) is net-new work, not a rename of what ships today.
- **Soccer is more than an enum (G3):** `.fieldSprint`/`.fieldAgility` need a real content+progression+recovery-cost model (volume, intensity, neural fatigue cost), not a bare label — otherwise "soccer intelligence" is theater, exactly like today's `.football` no-op note. This is a content generator the engine has never had; scope it as real work in D3, not a moderate add.

**ACWR honesty (G4):** the acute:chronic workload ratio is computed on WHOLE-DAY strain (the only thing in 30-day history). Use an EWMA-decoupled form, not a raw 7:28 (autocorrelation flaw); treat the 0.8-1.3 "sweet spot" as weakly-evidenced guidance, not gospel. Per-modality ACWR is impossible until the §2-CORRECTION #2 store accrues forward.

**Body-comp noise (G5):** Withings bioimpedance fat%/muscle% swings ±2-3% daily on hydration alone. The monthly summary MUST use a robust trend (rolling median or fitted slope down-weighting daily noise), NOT month-end point-to-point delta, or D4 reports noise as achievement.

**Cold-start (G6):** Week 1 has no baselines. Explicit cold-start mode: until ~N days of `DailyRecovery` history accrue, the brain falls back to the deterministic engine + recovery-score-only; trends are marked "building." Don't feed Claude empty/noisy baselines and let it sound confident about them.

## §11 — Honest scope note

This is a real multi-week redesign, not an increment. It is buildable entirely on the stack already in the repo — the data and the AI-call infra exist; the work is the assembly + brain + floor + modality/goal/monthly layers. The "intelligence" is real only when (a) trends are assembled (not raw snapshots fed to Claude), (b) the floor keeps it safe, and (c) it runs on real on-device data over weeks. The single biggest risk is the daily prompt producing confident-wrong sessions — mitigated by feeding assembled trends, the safety floor, and (reusing prior work) the prediction-accuracy spine measuring whether its prescriptions actually land.

## §13 — Daily-session JSON schema + per-modality outcome model (resolves the build-blockers)

### 13.1 The AI output schema (camelCase wire format; net-new, never touches the snake_case SwiftData DTOs)

Top-level session: `modality` (req), `intensity` (req: recovery|easy|moderate|hard|max), `durationMin` (req int), `blocks` (req, ≥1), `shortWhy` (req ≤120 chars), `fullWhy` (opt), `expectedStrain` (opt double — non-gym Whoop modalities; the prediction the outcome loop scores), `expectedSessionRPE` (opt int 1-10 — cross-modality fallback prediction).

`modality` enum maps to `WorkoutType`. **The actual `WorkoutType` cases (verified, `WorkoutEnums.swift:13-25`) are: `push, pull, legs, upper, lower, full_body, football, run, sprint, conditioning, mobility, rest`** — note: NO `gym_` prefix (gym days are the bare `push/pull/legs/upper/lower/full_body`), the sprint case is bare `sprint` (NOT `field_sprint`), and there is no agility or pool case. So the AI wire modality must either reuse these exact raw values or carry a documented mapping table. **⚠️ `pool_recovery`/`pool`, `field_agility`, and any `field_*`/`gym_*` prefixed value have NO `WorkoutType` case today** — D2 MUST extend the enum (add `pool`, `agility`) and/or define the wire→enum mapping, or those modalities drop silently on the floor. (The §13.2 table's "no `WorkoutType.pool`" note is consistent with this.)

**`block` = flat object with a `kind` discriminator + optional per-kind fields** (NOT a tagged enum — Haiku mangles nested `{gym:{...}}`; a flat struct with optionals parses with one Codable + retries reliably). Fields: `kind` (req: gym|field|pool|run|bodyweight|mobility|rest), `label` (req), `notes`; gym→`split`; field→`reps`|`distanceM`,`restSec`,`intensityPct`; pool→`distanceM`|`durationSec`,`stroke`,`intensityPct`; run→`runType`(req),`distanceM`|`durationSec`,`paceSecPerKm`,`intensityPct`; bodyweight→`reps`|`durationSec`,`sets`; mobility/rest→label suffices.

**Per-kind required contract** (parser enforces; any failure → whole session invalid → deterministic-floor fallback, never render half-parsed): gym needs `split`; field needs `reps`|`distanceM`; pool needs `distanceM`|`durationSec`; run needs `runType`+(`distanceM`|`durationSec`); bodyweight needs `reps`|`durationSec`; mobility/rest need nothing.

**CRITICAL — the gym block is a POINTER, not a prescription.** Per §8 KEEP: `{kind:gym, split:push}` only. The existing engine (`populateExercises`) fills exercises/sets/weights and writes `PredictionLog` as today. The AI must NOT emit gym weights — they'd fight `AIProgramPlanner.reconcile`'s `[0.5,1.1]` clamp and bypass the RPE accuracy loop. D2 must NOT build a competing gym prescriber inside the LLM.

### 13.2 Per-modality outcome model (makes measure-and-correct work beyond the gym)

| Modality | "Actual" outcome | Error definition | Available NOW? | Gap to close |
|---|---|---|---|---|
| Gym | mean entered set RPE → `PredictionLog.actualRPE` | `actualRPE − predictedRPE` (exists) | ✅ fully wired | none |
| Football/sprint/conditioning | `ActivitySession.strain` (Whoop-matched) | `actualStrain − expectedStrain` | ⚠️ strain yes IF Whoop tracked; nil on manual | emit `expectedStrain` + strain-prediction record (mirror PredictionLog), backfill at `persistNonGymCompletion` |
| Run | Whoop strain OR `RunSession` | `actualStrain−expected` or `actualRPE−expected` | ❌ RunSession dead code | route runs through ActivitySession OR wire RunSession; until then sessionRPE only |
| Pool | none today (unmodeled) | `actualSessionRPE − expectedSessionRPE` | ❌ no `WorkoutType.pool`, not in Whoop sport map | add enum case + sport-map entry; else sessionRPE only |
| Mobility/rest | completion (`WorkoutPlan.status`) | binary done/skipped | ✅ | none — don't force an effort metric |

**The single highest-leverage missing capture: whole-session RPE (sRPE).** Does not exist anywhere (only per-set gym RPE). One tap, 1–10, on session completion → gives EVERY non-gym modality a measurable outcome even with no Whoop activity, and is the `actual` for the `expectedSessionRPE` the AI emits. Build it on a new `SessionOutcome` model (or fields on `ActivitySession`).

**Minimal build for a real cross-modality loop:** (1) emit `expectedStrain`+`expectedSessionRPE` in JSON (free); (2) build sRPE capture (unlocks run/pool/manual-day); (3) add a strain-prediction record keyed by `workoutPlanID` mirroring `PredictionLog`, backfilled at the existing `persistNonGymCompletion` save point; (4) defer per-rep field actuals + RunSession wiring to a later enrichment.

## §14 — Resolved build-blockers (final question round, 2026-06-09)

**1. Emphasis driver = MANUAL, per block (Decision).** Nicola declares the block emphasis ("next 4 weeks = physique" / "now = soccer block"); the system periodizes within it (the non-emphasis goal held at maintenance per §12's interference rules). NOT auto-driven by the match calendar. Implication: needs a `TrainingBlock` concept (emphasis: soccer|physique + start/end or open-ended) + a simple "set current block" UI. The match calendar still drives match-protection (the existing T-1 rule = no legs at all the day before; §12 extends it to no-heavy-legs-within-48h) and taper INSIDE whatever block is active — it just doesn't flip the emphasis. Default before he sets one: physique (the current de-facto behavior).

**2. Cold-start N = 30 days (Decision).** Until 30 days of `DailyRecovery` history accrue, the brain runs SIMPLE mode: deterministic engine + recovery-score-only, trends shown as "building (day X/30)", no HRV/RHR-trend claims fed to Claude. Day 31+: full trend intelligence.
  - **⚠️ Interaction with §6 floor (must reconcile):** the floor's SEVERE Route B (HRV z-score + RHR) needs ≥14 valid samples for a baseline. With N=30 for the *brain*, but 14 for the *floor*, they diverge. **Resolution:** the FLOOR may use its routes as soon as it has ≥14 valid samples (safety should engage as early as it defensibly can — protecting the athlete is the priority); the BRAIN withholds trend-based *reasoning* until 30 days (intelligence claims need the more robust baseline). So: floor-safety from day ~14, full brain-intelligence from day 31. Document both thresholds explicitly in code; they are intentionally different and that's correct (safety earlier, sophistication later). Before day 14: floor uses Route A (recovery score) + absolute sleep only.

**3. Whole-session RPE (sRPE) = IN THE FIRST SLICE (Decision).** One-tap 1–10 after ANY session, on a new `SessionOutcome` model (or fields on `ActivitySession`). It is the `actual` for the AI's `expectedSessionRPE` and the ONLY outcome signal for non-gym days without a matched Whoop activity. Without it the cross-modality measure-and-correct loop is blind — so it's foundational, not an enrichment. Build in D2 alongside the brain.

**4. Technique coaching = FORM CUES per movement (Decision).** Every prescribed exercise/drill carries a short technique cue. Implementation: add an optional `cue: String` to the `block` schema (§13.1); the AI generates it (it already can). This directly answers Nicola's "training techniques for my body" — at low build cost (one schema field + render line on the session card). Progressive per-block technique GOALS (the richer option) are explicitly DEFERRED to a later phase; cues ship now.

### §14.1 — Net-new items these decisions ADD to the phase plan
- `TrainingBlock` model + "set current block (soccer/physique)" UI → folds into D3 (goal/periodization).
- Two distinct cold-start thresholds (floor ≥14 samples, brain ≥30 days) wired as named constants → D1 (assembly) + D2 (floor).
- `SessionOutcome` (sRPE) model + one-tap completion UI → D2 (first slice).
- `cue: String?` on the block schema + card render → D2 (schema) + D3 (field/drill cues for non-gym).

### §14.2 — Still explicitly DEFERRED (not in early slices; documented so they don't silently vanish)
- Pool + run modeled end-to-end (WorkoutType cases, Whoop sport-map, RunSession write path or ActivitySession routing) — §13.2.
- Per-rep field actuals (did you hit 10×30m at target times) — sRPE + strain cover the loop first.
- Progressive per-block technique goals (cues ship; tracked skill-progression later).
- Full unhappy-path design (Whoop disconnected for days / repeated non-adherence / no feedback for a week) — MUST be designed before D2 ships, currently golden-path only. **This is the largest remaining un-specced area.**

## §15 — Unhappy paths (was §14.2's "largest un-specced area" — MUST be settled before D2 ships)

The whole spec above is golden-path. For a system used daily, the failure states ARE the product. Each below: trigger → behavior → why.

### 15.1 — Whoop disconnected / stale data
- **No sync today, but <48h stale:** use the last good `DailyRecovery`; mark the card "based on yesterday's data." Brain still runs, floor still applies (on stale data — acceptable for 1 day).
- **>48h stale OR never connected:** the brain does NOT run on phantom data. Drop to **deterministic-engine mode** (recovery-score-only or, if none, the plain split engine), card states "connect Whoop for personalized readiness." No Claude call (nothing real to reason about → would be confident-wrong).
- **Floor with stale data:** the SEVERE routes still fire on the last known values for ≤48h; past that, only the schedule-driven match-protection gate remains. Never *upgrade* intensity on stale data — staleness biases conservative.

### 15.2 — Repeated non-adherence (prescription ignored)
- **Adherence is a tracked signal (Decision #10).** 3 skipped prescriptions in a rolling 7 days → the brain is TOLD this in the prompt ("user skipped the last 3 — likely the plan doesn't fit his real schedule/energy"). It should respond by proposing something smaller/different, not repeating the ignored plan louder.
- **7+ days zero adherence:** stop generating daily sessions (they're noise); surface a single "want to reset your plan?" prompt instead. Don't burn daily Claude calls into a void (5h-window discipline).
- **Never shame for missing — drill-sergeant ≠ abusive.** Re-engage, adapt, don't nag escalate. (Tempo is drill-sergeant in TONE, not a guilt machine.)

### 15.3 — No feedback logged (learning loop starves)
- **The loop degrades gracefully, never fabricates.** No entered RPE / sRPE → that day contributes NOTHING to learning (consistent with the existing `feedbackSampleCount > 0` gate and PredictionLog's `outcomeResolved` semantics — nil ≠ zero).
- **Whoop auto-confirm (Decision #10) is the safety net:** even with zero manual feedback, a Whoop-detected activity confirms a session happened + its strain, so adherence + strain-outcome still accrue. Manual feedback enriches; its absence doesn't blind the system, only narrows it.
- **Prolonged no-feedback (2+ weeks):** the monthly review (§16) explicitly notes "limited feedback this month — prescriptions are less personalized than they could be," and the prompt asks for it. Honest, not silent.

### 15.4 — No confirmable venue / time
- Venue confirm (Decision #6) is a PROPOSAL, not a gate. If the user declines the proposed venue/time and gives nothing, the brain prescribes the **home/bodyweight** modality (always available — Decision #5) at the readiness-appropriate intensity. The system is never stuck with "nothing to prescribe."
- **Travel-time awareness (Nicola's "15 min to the field"):** venue options carry an approximate travel cost; on a low-time day the brain prefers the nearer/zero-travel option (home/gym over field/pool). Lightweight: a per-venue `travelMin` on the venue profile, fed to the prompt, not a routing engine.

### 15.5 — Conflicting / impossible signals
- **Whoop says green but check-in says "exhausted, knee hurts":** subjective check-in can DOWNGRADE but never UPGRADE past the floor. A pain flag on a body part routes away from loading it (extends the existing Tier-2.3 pain-flag behavior). Body-data-wins (Decision #3) means the floor's SEVERE veto still dominates, but subjective complaints are a one-way downgrade within the allowed band.
- **AI proposes a modality the user has no venue for today:** floor/reconcile swaps to the nearest available modality of similar intent (e.g. proposed field-sprint but only gym available → power/plyo gym substitute), or home fallback.

## §16 — Venue & pattern learning (Decision #6/#9 — was net-new, ZERO spec; defined here)

The distinctive "you usually hit the gym ~4PM, can you make it?" feature. Net-new model + algorithm + storage.

### 16.1 — What's learned, and from what
Source of truth = completed sessions (adherence + Whoop auto-confirm + logged). Per (weekday × modality), learn:
- **Typical venue** (gym/field/pool/home) — mode of confirmed venues for that weekday.
- **Typical start time** — rolling median of confirmed session start times (from `ActivitySession.startTime` / workout logs) for that weekday+modality.
- **Typical duration** — rolling median of actual durations (Nicola noted sessions run ~50min not the prescribed 60).
- **Skip propensity** — fraction of prescribed sessions on that weekday actually completed (feeds §15.2).

### 16.2 — Storage & compute
- New `@Model VenuePattern` (or a JSON blob on `AdaptiveProfile`): keyed by weekday, holds `{venue, medianStartMinaftermidnight, medianDurationMin, completionRate, sampleCount}`.
- Pure recompute function over the last ~8 weeks of confirmed sessions, run on session save (cheap). **Cold-start:** until ≥3 confirmed samples for a weekday, no proposal — fall back to asking, or to the static `UserSettings` availability.
- **Propose-then-confirm flow:** morning of, the card shows "Gym day — your usual 4PM? [Yes] [Change]". "Change" → quick venue/time picker. The confirmed answer feeds today's prescription AND updates the pattern. NOT a blank daily form (Decision #6).

### 16.3 — Honesty
- The proposal is a low-confidence guess early (small `sampleCount`) → phrase it softer ("Gym today?") until the pattern is established; only assert the time ("usual 4PM?") once `sampleCount ≥ ~5`.

## §17 — Monthly arc (D4 — expanded from the one-paragraph stub)

### 17.1 — The logged interview (end of month)
A short structured quiz Nicola fills: what went well, what he skipped and why, injuries/niggles, subjective progress, goals for next month. Stored on `MonthlyReview`. This is the qualitative signal Whoop/Withings can't capture, and it feeds next month's emphasis (§14 manual block choice — the interview is where he'd naturally set it).

### 17.2 — The summary (generated, Sonnet — richer reasoning warranted once/month)
Aggregates the month into the kind of report Nicola described:
- **Training:** sessions completed by modality, adherence %, typical times ("always ~4PM"), missed days + streak impact.
- **Strength:** PR changes, total tonnage trend, error-trend from the PredictionLog spine ("prescriptions landed within 0.4 RPE — well-calibrated").
- **Body composition (Withings via HealthKit):** weight, body-fat%, muscle% deltas — using a **robust trend (rolling median / fitted slope), NOT month-end point-to-point** (§12 G5: bioimpedance daily noise is ±2-3%; naive deltas report noise as achievement).
- **Readiness:** HRV/RHR baseline shifts (is the athlete adapting — resting HR dropping, HRV rising = improving fitness).
- **Honest gaps:** "limited feedback this month" / "Whoop disconnected 6 days" stated, not hidden.

### 17.3 — Markers tracked over months (the "are you actually becoming a better athlete" answer)
Sprint times (if captured), HR-recovery, strength PRs, Whoop strain tolerance (same strain → better recovery = fitter), body-comp trend. These are the long-game proof the daily noise can't show.

## §18 — One day, end to end (the sequence narrative — was missing)

```
06:30  Withings weigh-in → Apple Health (Nicola's existing habit)
07:00  App open / Whoop morning sync fires
       → ReadinessAssembler reads 30-day DailyRecovery + today's sync
         + HealthKit body-comp + yesterday's ActivitySession strain
         → builds ReadinessPicture (trends computed, or "building day X/30")
07:00  Morning check-in card (5-sec: mood/soreness/stress) — optional, one-way downgrade
07:01  Venue proposal: "Gym day — usual 4PM?" [Yes]/[Change]   (§16)
       ── once-per-day guard (AdaptiveProfile.lastDailySessionDayKey) ──
       IF Pro + consent + Whoop fresh + ≥1 valid:
         → DailyReadinessCoach: ReadinessPicture + goal/block + venue + matches → Haiku → JSON session
       ELSE → deterministic-engine fallback (§15.1)
07:01  TrainingSafetyFloor.classify(picture) → SEVERE/MODERATE/NORMAL
       → clamps/downgrades the session (body-data-wins). Match-protection gate also applies.
       → parse-fail or floor-veto → deterministic pick (never half-parsed)
07:02  Session card renders: modality, short why, tap→full why, blocks w/ cues. Gym block = pointer → existing engine fills loads + writes PredictionLog.
~16:00 Nicola trains (or doesn't → adherence logged)
~17:00 Post-session: per-set RPE (gym, exists) + one-tap sRPE (all modalities, §13.2)
       → outcomes backfilled (PredictionLog.actualRPE, strain from ActivitySession, sRPE)
       → AdaptiveProfile error-fit correction (existing) + VenuePattern update (§16)
 night Whoop auto-confirm cross-checks what was actually done vs prescribed
end/mo MonthlyReview interview + Sonnet summary (§17)
```

## §19 — Success criteria & open questions (a buildable spec should state how we know it worked)

### 19.1 — How we'll know it's actually intelligent (not confident noise)
- **Prompt harness (§5.2-FIX) passes:** ≥18/20 synthetic ReadinessPictures yield valid, floor-passing, sensible sessions. If not → architecture in question, stop.
- **Floor never lets a SEVERE day train hard** (adversarial tests + on-device).
- **Hold-out (reusing prior PredictionLog work):** over weeks, the personalized prescription's RPE/strain error beats the deterministic baseline's — measurably, per the existing hold-out machinery extended to modalities.
- **Adherence ≥ baseline:** if the smart system's plans are skipped MORE than the old fixed plan, it's not fitting his life — a failure signal regardless of how clever the reasoning reads.

### 19.2 — Open questions still unresolved (decide before the relevant phase)
- **Exact morning check-in questions + soreness body-part list** (§4.2 says "mood/soreness/stress" — not the literal items/scale). [before D2]
- **ACWR decay constants** if EWMA-decoupled is chosen (§12 G4 names the method, not the λ). [before per-modality load, post-D2]
- **Sonnet-vs-Haiku for the monthly summary** — §17 assumes Sonnet; confirm the cost/quality call. [before D4]
- **`travelMin` per venue** — source? (manual once in settings, or inferred). [before §15.4 travel-awareness]
- ~~Does the weekly AIProgramPlanner get refactored to consume the new block-emphasis, or run parallel?~~ **RESOLVED in §8** (read/write contract + two-path trace): weekly owns the modality-default and writes the persisted `WorkoutPlan`; daily READS it, mutates intensity in place, overrides modality only under a hard constraint, and floor-SEVERE marks the day `.skipped` (with a new `skipReason`). `planWeek` does NOT need refactoring for the steady-state handoff — only D3's mid-week-match re-trigger calls it again. Remaining D3 sub-question: wiring `TrainingBlock` emphasis (§14.1) into `planWeek`'s `goal:` param (today hardcoded `"hypertrophy"`). [before D3]

## §21 — Two-a-day training (spec, 2026-06-09 — "can I do two different trainings in a day?")

### 21.1 — Use cases (Nicola's actual life; anything else is out of scope)
- **U1 — lift + soccer, same day:** gym ~16:00, play ~20:00. The common case and the reason the question exists.
- **U2 — match-day primer:** light upper-body AM, match PM (legal under §12 — it's *heavy legs* that's banned near matches, not all lifting).
- **U3 — morning run/pool + evening gym.**
- **NOT a goal:** two gym sessions/day. No use case, and §12 interference says no.

### 21.2 — Ground truth: what hard-codes one-session-per-day today (the honest blast radius)
- `WorkoutPlan.date` is normalized to start-of-day; `planResolution` (`TrainingViewModel.swift:857`) + the dedup pass (~:866-940) actively DELETE a second same-day plan — one-per-day is an enforced invariant, not an accident.
- `var todayPlan: WorkoutPlan?` (`TrainingViewModel.swift:74`) — singular; read by TodayWorkoutView, the start-workout flow, `deterministicCandidate`, the session card.
- `TrainingEngineProtocol.generateWeekPlan` emits exactly one plan per day; a football day is whole-day football.
- `DailySession` is 1:1 with the day's plan (§8 desync guard); the coach guard is once-daily.
- `TrainingOutcomeEvaluator.missedSessions` + §15.2 adherence count day-plans; Whoop auto-confirm and `loadNonGymActivity` match activities to THE day's plan by day.
- `VenuePattern` samples key on weekday only — two-a-day makes the start-time median bimodal. (§16.1 always said weekday × modality; two-a-day forces that fix.)
- WeekPlanView rows, Dashboard `refreshTrainingStatus`: one entry/day.

### 21.3 — Decision: staged. T1 composite day first; T2 true dual plans only if T1 proves insufficient.

**T1 — composite day (one plan, one session, time-tagged block groups). RECOMMENDED FIRST.**
The §13.1 schema already legally mixes block kinds in one session (gym + field). T1 makes that a real two-a-day surface:
- **Schema/model (additive):** optional `scheduledMin: Int?` per block (DTO + persisted block) — blocks carry times; the card groups by time: "PULL @ 16:00" / "FIELD @ 20:00".
- **Plan stays one `WorkoutPlan`** (anchor modality = the gym/primary part). Engine pointer fills gym loads exactly as today. The evening part completes via Whoop auto-detect (already an unlinked `ActivitySession`, already venue-learner evidence).
- **Brain:** prompt gains permission to emit a second time-tagged block group when context warrants (venue/time pattern says evening field, match calendar, user's confirmed venue), under §21.4 rules. The once-daily Haiku call covers the whole composite day — **zero new AI calls**.
- **Floor:** vetoes illegal combos (§21.4) by stripping the offending block group, not nuking the session.
- **Honest limitation (stated, accepted):** adherence stays day-granular — the day counts done when its anchor completes. Per-part adherence is T2's job.
- **Week row UI:** subtitle gains the second part ("PULL · +field 20:00").

**T2 — true dual plans (the real model; only after T1 demand is proven).**
- `WorkoutPlan` += optional `slot` (default 0) — additive migration. `planResolution`/dedup key on (day, slot); sacredness unchanged per plan.
- `generateWeekPlan` may emit 2 plans/day (emphasis-week rules from §12 decide when); `todayPlan` → `todayPlans` + selection; START WORKOUT per plan; `DailySession` 1:1 per plan (coach still once-daily: ONE Haiku call prescribes both slots).
- Adherence/evaluator/XP per plan (XP weighting = open decision 21.6); Whoop auto-confirm switches from day-matching to time-window overlap.
- Prereq (shippable inside T1): venue learner keyed weekday × modality.
- Mandatory: enumerate-the-readers over the full §21.2 list + architecture-guard. This phase touches the module's most load-bearing invariant.

### 21.4 — Interference rules for a two-part day (floor-enforced, both phases)
- ≥6h between parts (§12 spacing).
- Heavy lower-body + any field sprint/agility: NEVER same day. Floor strips the later-scheduled offender.
- Match T-0: part 1 may only be easy/moderate upper or mobility. T-1: existing no-heavy-legs rule applies to BOTH parts.
- ACWR > 1.3 → no second part (brain is told; floor downgrades a second part to mobility/rest).
- Floor-SEVERE day → one recovery session, period — the existing veto dominates everything above.
- Hard+hard is illegal regardless of modality pair: at most one part above `moderate`.

### 21.5 — Cost
Zero new AI calls in both phases (composite day rides the existing once-daily call; weekly Sonnet untouched). T1 is schema-additive only.

### 21.6 — Open decisions (settle before T2, not before T1)
- XP/streak semantics for a half-done two-part day.
- How a second slot enters the plan: planner-decided vs an explicit "add evening session" action (or both).
- Per-part sRPE (`SessionOutcome` per part) vs whole-day.

### 21.7 — Tests & exit criteria
- **T1:** parser round-trips `scheduledMin`; adversarial floor tests for every illegal combo in §21.4; card renders grouped parts; prompt harness re-run with ≥3 new two-a-day synthetic fixtures (all parse + pass floor); on-device render of a composite day (⌘R, L145).
- **T2:** planResolution slot-keying unit tests; per-plan adherence in the evaluator; Whoop time-window matcher; migration default (slot=0) on existing rows; full training-suite regression.
- **Exit (T1):** a real day shows "lift 16:00 + field 20:00" from one Claude call, floor demonstrably strips an illegal combo, Whoop evening detection lands as evidence.

## §20 — Section index (the doc grew; orient here)
§0 summary · §1 locked decisions · §2 ground truth (+CORRECTIONS) · §3 architecture · §4 assembly/models · §5 daily brain + prompt · §6 safety floor (concrete thresholds) · §7 build strategy (RESOLVED: constrained-A) · §8 existing-work (RESOLVED: keep) · §9 phases D1-D4 · §10 cross-cutting · §11 scope note · §12 dual-goal interference · §13 JSON schema + per-modality outcomes · §14 resolved blockers · §15 unhappy paths · §16 venue/pattern learning · §17 monthly arc · §18 day-in-the-life sequence · §19 success criteria + open questions · §20 index · §21 two-a-day (spec'd 2026-06-09, T1 composite day → T2 dual plans)
