# AI Intelligence Engine — "CortexAI"

> **Subsystem**: AI Intelligence Engine (CortexAI)
> **App**: Tempo — Vapor backend (Swift) + iOS (SwiftUI)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: Backend + iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

This is the **strongest-built subsystem in Tempo**. 11 of 12 AI features ship complete (real prompt + endpoint + algorithmic fallback + cache); 1 is partial (Notification Batch — pre-gen built, runtime accuracy-swap missing). All core infrastructure (Claude client, all §3 prompts, persistent budget tracker, per-model circuit breaker, two-tier cache + SWR + cache warming, AI consent) is implemented. The unbuilt parts are the Responsible-AI safety nets (§7.2–7.6) and the §2.3 retry policy.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `tempo-backend/Sources/App/Services/InsightService.swift` (`AIConfig`, `CircuitBreaker`, `callClaude`, weekly-report + pattern + drill-sergeant)
- `tempo-backend/Sources/App/Services/{MorningBriefing,RecoveryPrescription,TrainingProgram,TrainingAdjustment,MealTiming,StudySchedule,AchievementCopy,DashboardInsights,DrillSergeantBatch}Service.swift`
- `tempo-backend/Sources/App/Services/{AIBudgetTracker,AICache,AIFeatureRunner}.swift`
- `tempo-backend/Sources/App/Controllers/{InsightController,InsightController+Section7,UserController}.swift`
- `tempo-backend/Sources/App/Jobs/{WeeklySummary,DrillSergeantBatch}Job.swift`, `App/configure.swift`, `App/routes.swift`
- iOS consumer: `Tempo/Tempo/Services/Recovery/RecoveryAIInsightService.swift`

---

## Table of Contents

1. [AI Features Overview](#1-ai-features-overview)
2. [Claude API Configuration](#2-claude-api-configuration)
3. [Prompt Templates](#3-prompt-templates)
4. [Data Pipeline](#4-data-pipeline)
5. [Cost Management](#5-cost-management)
6. [Caching Strategy](#6-caching-strategy)
7. [Quality Assurance](#7-quality-assurance)
8. [Offline / Fallback System](#8-offline--fallback-system)
9. [Responsible AI & Safety](#9-responsible-ai--safety)
10. [Future AI Features (v2+)](#10-future-ai-features-v2)
11. [Privacy Considerations](#11-privacy-considerations)

---

## 1. AI Features Overview

All 12 features below exist in code. 11 are fully wired (service + prompt + fallback + cache + endpoint); Feature 12's runtime half is partial. The original numbering (1–12) is preserved so cross-doc references survive.

| # | Feature | Module | Trigger | Real Model | Status |
|---|---------|--------|---------|------------|--------|
| 1 | Morning Briefing Generation | Dashboard / Accountability | Daily at wake time | Template (free) + Haiku fallback | IMPLEMENTED |
| 2 | Weekly Report Analysis | Dashboard | Sunday 20:00 / on-demand | `claude-sonnet-4-6` | IMPLEMENTED |
| 3 | Pattern / Correlation Detection | Dashboard | Weekly / on-demand | `claude-opus-4-7` (→ Sonnet at budget caution) | IMPLEMENTED |
| 4 | Training Program Generation | RepForge | Weekly plan generation | `claude-sonnet-4-6` | IMPLEMENTED |
| 5 | Training Program Adjustment | RepForge | Recovery delta significant | `claude-haiku-4-5-20251001` | IMPLEMENTED |
| 6 | Recovery Prescription Generation | RecoverIQ | Daily after Whoop sync | `claude-haiku-4-5-20251001` | IMPLEMENTED |
| 7 | Drill Sergeant Notification Copy | Lockdown | 3-day batch (Sun/Wed) + on-demand | `claude-sonnet-4-6` (batch) / Haiku (on-demand) | IMPLEMENTED |
| 8 | Meal Timing Recommendations | RecoverIQ / Fuel | After recovery + nutrition refresh | `claude-haiku-4-5-20251001` | IMPLEMENTED |
| 9 | Study Schedule Optimization | Lockdown / Mind | Exam dates added / weekly planning | `claude-sonnet-4-6` | IMPLEMENTED |
| 10 | Achievement / Milestone Celebrations | Arena (ClutchTime) | On milestone trigger | `claude-haiku-4-5-20251001` | IMPLEMENTED |
| 11 | Natural Language Dashboard Insights | Dashboard | Dashboard load (if data changed) | `claude-haiku-4-5-20251001` | IMPLEMENTED |
| 12 | Notification Batch Pre-Generation | Lockdown | Sun + Wed 20:00 (3-day batch) | `claude-sonnet-4-6` | PARTIAL |

> **Divergence from original spec:** The spec's model names ("Haiku 4.5 / Sonnet 4.6 / Opus 4.6") were aspirational and several invented date suffixes returned **404** from Anthropic, silently forcing every call onto the rule-based fallback. `AIConfig` in `InsightService.swift` corrects them to the real, working IDs: `claude-haiku-4-5-20251001`, `claude-sonnet-4-6`, `claude-opus-4-7`. The corrected IDs (note: Opus is **4-7**, not the spec's 4.6) are ground truth — the doc IDs are the bug.

> **Status: NOT IMPLEMENTED — §3.4 runtime two-tier notification swap (Feature 12 partial).** Pre-generation is fully built (`DrillSergeantBatchService.generate`, `DrillSergeantBatchJob`, 3-day cache, Sun+Wed cron). The runtime accuracy-check — "if pre-gen copy references a task the user already completed, discard and fall back to Haiku/template before sending" — is **not built**. The scheduler reads the cached copy verbatim. Pre-gen half: real. Accuracy-swap half: missing.

### Feature Dependency Graph (as-built)

```
Whoop Sync ─┬─→ Recovery Prescription (Haiku)
            ├─→ Training Adjustment (Haiku, cacheKey nil — delta-driven)
            ├─→ Morning Briefing (template-first, Haiku edge-case fallback)
            └─→ Meal Timing (Haiku)

Nutrition Sync ─┬─→ Dashboard Insights (Haiku, input-hash gated)
                └─→ Meal Timing (Haiku)

Weekly Cron ─┬─→ Weekly Report (Sonnet)            [WeeklySummaryJob, Sun 20:00]
             ├─→ Pattern Detection (Opus→Sonnet)   [on-demand + warm path]
             ├─→ Training Program (Sonnet)
             ├─→ Notification Batch (Sonnet)        [DrillSergeantBatchJob, Sun+Wed 20:00]
             └─→ Study Schedule (Sonnet)

User Action ─┬─→ Pattern Query (Opus)
             └─→ Force-Regenerate Weekly (Sonnet, force_regenerate flag)
```

---

## 2. Claude API Configuration

### 2.1 Model Selection & 2.2 Per-Feature Configuration

`struct AIConfig` (`InsightService.swift`) holds the canonical model IDs, timeouts, budget, and limits. Per-feature `temperature`/`maxTokens` are applied at each service call site (e.g. Weekly Report Sonnet temp 0.4 / 2000 tok; Pattern Opus temp 0.3; Study Sonnet temp 0.3 / 1500 tok; Training Adjustment Haiku). Timeouts: `haikuTimeout` 5s, `sonnetTimeout` 30s, `opusTimeout` 60s.

> **Divergence from original spec:** Model IDs differ from doc §2.5 constants — see the §1 divergence callout. `AIConfig` carries an explicit code comment documenting why (doc IDs 404'd). Code is source of truth.

### 2.3 Retry Strategy

> **Divergence from original spec — single-shot, not the documented backoff policy.** Backend retry is **one** malformed-JSON retry with a stricter "return only valid JSON" prompt (`InsightService` weekly path; `AIFeatureRunner` shared path). There is **no** exponential-backoff loop, **no** `Retry-After` handling, **no** automatic retry on HTTP 429/5xx (`callClaude` throws on non-2xx, does not retry). `AIConfig.maxRetries` (2), `baseRetryDelay` (1.0s), `backoffMultiplier` (2.0) are declared but **unused server-side**. The only place a proper exponential-backoff retry exists is the iOS nutrition-proxy path `RecoveryAIInsightService.sendWithRetry` — it does not cover the core backend AI routes.

### 2.4 Circuit Breaker

IMPLEMENTED. Three independent per-model breakers (Haiku / Sonnet / Opus) in `InsightService`. `struct CircuitBreaker` has `closed / open / halfOpen` states, failure threshold 3, recovery timeout 1800s, half-open requires 2 consecutive successes to re-close. Checked before every Claude call.

> **Divergence from original spec:** `checkRecovery()` (open→halfOpen after recovery timeout) exists but is **not driven by a timer** — the transition only happens when the breaker is next consulted. Functional, but recovery is lazy rather than scheduled.

### 2.5 API Client (Vapor Backend)

IMPLEMENTED. `InsightService.callClaude` does a real `POST https://api.anthropic.com/v1/messages` with `x-api-key` from the `ANTHROPIC_API_KEY` env var and the `anthropic-version` header. Token usage from every response is recorded to the persistent budget tracker (§5.4).

---

## 3. Prompt Templates

IMPLEMENTED — all 12. Every feature has a real, non-stub system + user prompt. They are not duplicated here (they drift); read the builder symbol in the owning service:

| Feature | Prompt symbol |
|---------|---------------|
| 3.1 Morning Briefing | template engine in `MorningBriefingService.computeFresh`; Haiku fallback prompt `MorningBriefingService` |
| 3.2 Weekly Report | `WeeklyReportPrompts` (`InsightService`) |
| 3.3 Pattern Detection | `PatternDetectionPrompts` (`InsightService`) — pre-computed-stats design |
| 3.4 Drill Sergeant (batch) | `DrillSergeantBatchService` prompt builder; on-demand variant `InsightService.generateDrillSergeantCopy` |
| 3.5 Training Program | `TrainingProgramService` prompt builder |
| 3.6 Recovery Prescription | `RecoveryPrescriptionService` prompt builder |
| 3.7 Study Schedule | `StudySchedulePrompts.system` / `.buildUserPrompt` |
| 3.8 Meal Timing | `MealTimingService` prompt builder |
| 3.9 Achievement Copy | `AchievementCopyService` prompt builder |
| 3.10 Dashboard Insights | `DashboardInsightsService` prompt builder |
| 3.11 Training Adjustment | `TrainingAdjustmentService` prompt builder |

Endpoints (all via `InsightController` / `InsightController+Section7`, JWT-auth + daily-limit gated):
- `GET /v1/insights/weekly-report` (`force_regenerate` supported)
- `GET /v1/insights/patterns`
- `GET /v1/insights/drill-sergeant` (on-demand Haiku variant)
- `POST /v1/insights/training-program`
- `POST /v1/insights/training-adjustment`
- `POST /v1/insights/recovery-prescription`
- `POST /v1/insights/study-schedule`
- `POST /v1/insights/dashboard`
- `POST /v1/insights/achievement-copy`
- Morning Briefing endpoint (excluded from the 12/day per-user limit, per spec)

> **Divergence from original spec:** Meal Timing (§3.8) has a real service + prompt + fallback + cache but **no dedicated REST route** — it is invoked via the service/cache-warming layer, not independently reachable by the client like every other feature. Every other feature has its own controller endpoint.

---

## 4. Data Pipeline

> **Divergence from original spec — caller-assembled payloads, no dedicated anonymization layer.** Inputs are pre-aggregated **by iOS** and passed to the backend as prompt-ready DTOs (a controller comment confirms the backend trusts caller-assembled payloads). Pattern Detection accepts a pre-formatted pipe-delimited string + precomputed correlations (`PatternDetectionInput`), so the §4.3 compression format is honored — because the caller supplies it. `userId` is stamped server-side, never placed in prompts.

> **Status: NOT IMPLEMENTED — §4.4 enforced field-stripping.** There is no dedicated anonymization layer that strips email / apple_id / device_id / location / IP. PII absence relies on the prompt builders simply not including those fields. No assertion or test guarantees PII never enters a prompt.

---

## 5. Cost Management

### 5.4 Budget Enforcement & Threshold Ladder

IMPLEMENTED — and persistent. `actor AIBudgetTracker` is Postgres-backed (`AIMonthlySpend` model, `CreateAIMonthlySpend` migration), so spend survives process restarts. Pre-flight `canMakeCall` gate runs before every Claude call; `recordSpend` writes microdollar cost after. The `ThrottleLevel` ladder matches spec §5.4: 50% warn / 80% caution / 95% critical / 100% exhausted. At **caution**, Pattern Detection downgrades Opus→Sonnet. Per-user daily cap (`AIConfig.dailyPerUserLimit = 12`) is enforced via Redis (`InsightController.checkDailyAILimit`). Monthly cap defaults to $50, overridable via `CLAUDE_MONTHLY_BUDGET_CENTS`. Cost math in microdollars matches the spec.

> **Divergence from original spec:** §5.5 cost-optimization is partially realized. Conditional generation via input hash (§5.5) is implemented for Dashboard Insights. Per-correlation Pattern caching (§6.1 sub-note, claimed ~60% Opus reduction) is **not** — see §6.

---

## 6. Caching Strategy

IMPLEMENTED — two-tier, typed keys, per-feature TTLs, SWR, and cron warming. `AICache` is Redis-hot (≤24h) backed by Postgres long-lived (`CachedAIResponse` model, `CreateAIResponseCache` migration). Typed key factory with per-feature TTLs matching §6.1:

| Feature | TTL |
|---------|-----|
| Weekly Report | 7 days |
| Pattern Detection | 24 hours |
| Training Program | 7 days |
| Recovery Prescription | 12 hours |
| Morning Briefing | 1 day |
| Notification Batch | 3 days |
| Dashboard Insights | keyed by data-hash |
| Meal Timing | 2 hours |
| Study Schedule | until exam edit |
| Achievement Copy | forever (modeled as ~10 years) |

Stale-while-revalidate (`AICache.withSWR`) returns stale + regenerates in background. Cache warming: `WeeklySummaryJob` (Sun 20:00, scheduled in `configure.swift`), `DrillSergeantBatchJob` (Sun + Wed 20:00).

> **Divergence from original spec:** Pattern Detection caches the **whole pattern blob keyed by `totalDays`**, not per-correlation-pair. The spec's per-correlation cache (and its claimed ~60% Opus cost reduction) is not realized. Minor — full caching otherwise works as designed.

---

## 7. Quality Assurance

### 7.1 Response Validation Pipeline

> **Divergence from original spec — 3 of 6 stages built.** Parse check + schema decode + single malformed-JSON retry are real per service (`InsightService`, `AIFeatureRunner`). A length/word-count check exists for drill-sergeant and the weekly-report fallback. Stages 3 (hallucination cross-reference), 4 (safety regex), and 6 (tone check) are **not** built as a shared pipeline.

### 7.2 Hallucination Prevention

> **Status: NOT IMPLEMENTED — server-side numeric cross-reference.** Prompt-level grounding (XML tags, "only reference provided data", bad-output examples) **is** present in the prompts. The §7.2 server-side guard — extracting numbers from Claude output and rejecting any that deviate >5% from input, plus `correlation_r` replacement in pattern output — does **not** exist anywhere in the backend.

### 7.3 Medical / Health Disclaimer

> **Status: NOT IMPLEMENTED.** No `ai_disclaimer_accepted_at`, no full-screen AI disclaimer modal, no "AI analysis — not medical advice" per-report footer, no re-consent flow for the core AI insight views. The nutrition module's own unrelated disclaimer (`tempo.nutrition.disclaimerAccepted`) does not satisfy §7.3 for AI insights.

### 7.4 Harmful Content Prevention

> **Status: NOT IMPLEMENTED — global post-generation safety filter.** There is no `REJECT_PATTERNS` regex, no `ContentSafetyFilter`, no `HarmfulContent` / `stripUnsafeSentences` anywhere in `tempo-backend/Sources`. Layer-1 prompt prohibitions exist. The Layer-2 backstop applied to **every** response does not. The only post-generation sanitization is `MorningBriefingService.sanitize()`, which case-insensitively string-replaces exactly **3 phrases** ("consult a doctor", "see a physician", "consult a physician") on the Morning Briefing path only.

### 7.5 A/B Testing Framework & 7.6 User Feedback Loop

> **Status: NOT IMPLEMENTED.** No `PromptVariant`, no `InsightFeedback`, no thumbs-up/down on AI insights. Neither the A/B framework nor the feedback loop exists.

---

## 8. Offline / Fallback System

IMPLEMENTED — every feature has a real algorithmic fallback. Weekly-report and drill-sergeant fallbacks live in `InsightService`; per-service fallback functions exist for Recovery Prescription, Training Program, Meal Timing, Study Schedule, Dashboard Insights, Achievement Copy, and Pattern Detection (`PatternDetectionResponse.fallback`). Fallbacks fire on circuit-open, budget-exhausted, or parse failure — matching the §8.1/§8.2 design intent. The per-feature degradation matrix (§8.8) and the in-app graceful-degradation indicator (§8.9) are not separately built; degradation is the algorithmic fallback returning a valid response.

---

## 9. Responsible AI & Safety

> **Divergence from original spec — Layer 1 only; consent endpoint built, gating unverified.** AI consent is IMPLEMENTED: `POST /v1/user/ai-consent` (`UserController.setAIConsent`), backed by the `aiConsentAt` column (`AddAIConsentToUsers` migration, `User` model), idempotent and revocable (revoke sets `aiConsentAt = nil`). Layer-1 prompt-level medical-advice prohibitions are present in the prompts.
>
> Missing: Layer-2 content filter (§7.4), the numeric hallucination cross-reference (§7.2), and the disclaimer UI (§7.3). Also note: AI routes enforce auth + daily limit, but an explicit check that `aiConsentAt` is non-nil **before** calling Claude was not observed in the `InsightController` paths — consent is recorded but its enforcement at the call site is unverified.

---

## 10. Future AI Features (v2+)

> **Status: NOT IMPLEMENTED — explicitly out of scope.** Voice coaching, photo meal logging, conversational coach, AI workout variations, predictive recovery, and smart notification timing remain a v2+ roadmap. None exist in code.

---

## 11. Privacy Considerations

Implemented privacy surface: the AI consent endpoint + `aiConsentAt` column (see §9), revocable and idempotent. `userId` is stamped server-side and never sent in prompts.

> **Status: NOT IMPLEMENTED — the rest of §11.** No enforced data-minimization checklist (§4.4 / §11.5), no opt-out behavior wired to actually block AI calls, no AI-specific data-deletion path, and no independently verifiable App Store privacy-label mapping. These depend on the missing anonymization layer (§4.4) and the unverified consent gate (§9).

---

*End of as-built description. Reconciled to code on 2026-05-19. Where this doc and the source disagree, the source is authoritative — fix the doc, not the code, unless the divergence is itself the bug.*
