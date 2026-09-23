# Tempo

**A daily-readiness training engine spanning a native iOS app, a watchOS companion, a widget, and a Swift backend — where an LLM plans the workout and a deterministic, fully unit-tested safety floor holds the veto.**

This is a single-developer project. The interesting part isn't the feature count; it's the architecture: biometric signals from four sources are fused on-device into a baseline-relative readiness picture, an LLM proposes a session against that picture, and a pure-function gate downgrades the proposal whenever the body data says the day is cooked — so a confident-wrong model answer can never push a hard session onto a sick or under-recovered user.

---

## The problem

"Train hard, recover hard" apps fail in two predictable ways:

1. **They trust a single fused number.** Whoop hands you one recovery score; most apps prescribe straight off it. But the score lags the body — you can have a normal recovery score the morning your HRV has already crashed and your respiratory rate is climbing, which is what an incubating illness looks like a day before symptoms.
2. **The moment you let an LLM plan the workout, you inherit its failure mode:** it will occasionally output a confident, well-worded prescription that is exactly wrong for the day (hard legs the day before a match; conditioning on a red-recovery morning). A chatbot that's wrong 3% of the time is fine. A *training* coach that's wrong 3% of the time injures you.

Tempo's answer is a hybrid: **the LLM owns modality, intensity, and voice; a deterministic floor owns "not on a clearly-cooked day."** The model's creativity is bounded by gates that are pure functions of biometric data, ordered by severity, and unit-tested without a device. The model can be interesting; it cannot be dangerous.

---

## Architecture

Three client surfaces and a backend, with a deliberate split of responsibility:

```
┌─────────────────────────── iOS app (SwiftUI + SwiftData) ───────────────────────────┐
│                                                                                       │
│  HealthKit ─┐                                                                          │
│  WeatherKit ─┼─▶ ReadinessAssembler ──▶ ReadinessPicture ──┐                          │
│  EventKit   ─┤   (pure: 30d/7d windows,                    │                          │
│  Whoop  ─────┘    HRV z-score, deviations)                 ▼                          │
│                                              ┌──── LLM proposes DailySessionDTO ◀── backend proxy
│                                              │                  │                      │
│                                              │                  ▼                      │
│                                              │     TrainingSafetyFloor.classify()      │
│                                              │     (pure, ordered gates, ≤4 tiers)     │
│                                              │                  │                      │
│            SwiftData (≈60 @Model entities, App Group container) ◀─┴── downgraded session
│                       │                                                                │
│         PendingSync queue (offline-first, last-writer-wins by updatedAt)              │
│                       │   WCSession ──▶ watchOS app (WatchSnapshot + complications)    │
│                       │   App-Group UserDefaults ──▶ Widget   ·   ActivityKit ──▶ Live Activity
└───────────────────────┼───────────────────────────────────────────────────────────────┘
                        │  HTTPS (JWT)
                        ▼
┌─────────────────── tempo-backend (Vapor 4, Swift 6) ──────────────────────────────────┐
│  Auth (Sign in with Apple → JWT + rotating refresh tokens)                             │
│  AIBudgetTracker (actor) — pre-flight spend gate, microdollar cost model, 5-tier        │
│    throttle ladder, persisted to Postgres so caps survive restarts & span replicas     │
│  Claude proxy services (Coach / Nutrition) — thin auth+budget+audit relay; tool loop    │
│    stays on the client                                                                  │
│  Whoop OAuth proxy + HMAC-verified webhooks (Redis idempotency → Vapor Queue job)       │
│  APNs push · App Store Server Notification verification · friends/XP/leaderboard        │
│  PostgreSQL (Fluent, ≈26 migrations) · Redis (cache + queue) · scheduled jobs           │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

The client is the source of truth for personal data (offline-first); the backend is the source of truth for anything multi-user (social, leaderboards), anything that must not be spoofed (subscription entitlement), and anything that costs money per call (AI).

---

## Key engineering decisions & tradeoffs

### 1. LLM plans, a pure-function floor vetoes — and the two are tested separately

`Services/Engines/TrainingSafetyFloor.swift` is the spine of the project. Tier (`severe` / `moderate` / `normal`) is a **pure function of ordered gates over a `ReadinessPicture`** — no SwiftData query, no network, no clock — so the whole decision is unit-testable with hand-built inputs and no device. `severe` is a logical OR over several routes:

- composite recovery below the red band (trust Whoop's fused score when it's already screaming);
- **HRV crash AND RHR spike** — an AND-gate, because either alone is noise;
- an **illness triad** added after a real incident: *any two of* {respiratory-rate elevation, skin-temp deviation ≥1°C, SpO₂ below 94} on a non-green day. One signal is hydration or sensor drift; two is the pre-symptomatic signature the resp-rate-only route was missing.

Two design choices make this trustworthy. First, **cold-start gating**: the raw multi-signal routes (HRV z-score, RHR deviation) require ≥14 valid baseline samples (`hasBaselineForFloor`); below that the floor degrades to the composite score plus absolute sleep debt, so it never fires off a z-score computed against three days of data. Second, every threshold is annotated `[L]` (literature-locked) or `[D]` (defensible default) inline, so the line between "this is from the science" and "this is my tuned guess" is explicit in the source.

The harness (`DailyReadinessHarness.swift`, `#if DEBUG` only) is the part most apps skip: it runs ~20 synthetic readiness pictures through the *real* model proxy at production settings and reports **two independent rates — prompt quality (how often the raw model output is already sensible *before* the floor touches it) and safety (how often the floor had to rescue it)**. A prompt that passes 100% only because the floor keeps catching it is a *failing* prompt. It also checks named anti-patterns the floor structurally cannot catch — a pre-match tempo run, a hard-legs day before a match — where the prompt is the only line of defense. That's the real go/no-go gate.

**Tradeoff:** this is far more machinery than calling the model and showing the answer. The payoff is that the dangerous failure mode is engineered out rather than hoped away, and the safety logic ships with real test coverage instead of vibes.

### 2. Bounded online learning, not a trained model

`AdaptiveProfileUpdater.swift` personalizes load over time, but deliberately as **clamped online statistics, not a learned net.** Each saved session nudges the per-user weight increment multiplicatively (1.1× after an easy session, 0.9× after a hard one) with an absolute per-session cap (≤1 kg) and hard floor/ceiling, and tracks fatigue as an EWMA. Every update is small, bounded, and reversible, so the profile converges over weeks and can never make a wild jump off one weird session — and, like the floor, it's a pure function and fully unit-tested. For a single-user app where a bad adaptation means a hurt user, predictable-and-boring beats clever-and-opaque.

### 3. SwiftData + offline-first sync, last-writer-wins

Local persistence is **SwiftData** (~60 `@Model` entities — `DailyRecovery`, `DayPlan`, `MorningCheckIn`, `AdaptiveProfile`, `ExerciseHistory`, …) in a single **`VersionedSchema` V1** living in the shared **App Group container** (`group.app.tempo.Tempo`), CloudKit deliberately off (`cloudKitDatabase: .none`) — sync is owned, not delegated to iCloud. The app is fully usable offline; mutations land locally and enqueue into a `PendingSync` queue. `SyncCoordinatorProtocol` defines `uploadPending()` / `downloadUpdates(since:)` (timestamp-delta pull) and resolves `SyncConflict`s by **`updatedAt` last-writer-wins**.

**Honest tradeoff:** last-writer-wins is the right call here (single human, a phone + a watch, rarely truly concurrent edits) and wrong for genuine multi-device collaboration — it silently drops the losing edit. It's a deliberate scope decision, not an oversight; the conflict type carries both timestamps so the policy can be upgraded later without reworking the queue. SwiftData over Core Data buys first-class Swift 6 concurrency and far less boilerplate, at the cost of a less mature migration story. Two honest consequences: there's **no `SchemaMigrationPlan` to V2 yet** (pre-ship, V1 evolves in place — a real versioned migration is gated on the first post-launch breaking change), and complex nested relationships are hand-rolled as JSON columns where SwiftData's relationship modeling got awkward. All derivation logic lives in pure engines *outside* persistence, so the schema stays thin.

### 4. The AI budget lives in the backend, as an actor, in microdollars

User-triggered LLM calls are a standing way to wake up to a surprise bill. `AIBudgetTracker` is a Swift `actor` that enforces a **hard monthly ceiling, pre-flight**: callers ask `canMakeCall(estimatedCostCents:)` with a worst-case estimate *before* the HTTP request, and if it would breach the cap the call is rejected and the caller falls back to rule-based output. Spend is modeled in **microdollars** for precision and persisted to Postgres via an **atomic `INSERT … ON CONFLICT DO UPDATE SET spend = spend + EXCLUDED`** — not a read-modify-write — so concurrent calls across replicas can't race the counter and caps survive process restarts (no double-spend on redeploy). A 5-tier throttle ladder degrades gracefully — at 80% it downgrades Opus→Sonnet and disables on-demand patterns; at 95% it keeps only the recovery prescription; at 100% it 503s — and per-caller sub-caps (e.g. a dedicated "coach" budget) are enforced *alongside* the global cap. Three more layers sit around it: a **per-model circuit breaker** (3 failures in 10 min → open, half-open recovery, fall back to rule-based), a **per-user daily call cap** (Redis-keyed), and a **two-tier response cache** — Redis for short-TTL ephemeral insights, Postgres for long-TTL artifacts (weekly reports, training programs) that must survive a Redis flush. The proxy itself is a thin auth + budget + audit relay; the tool-use loop stays on the client, so the backend never holds conversation state.

### 5. Three surfaces, three sharing mechanisms — chosen per constraint, not uniformly

The phone is the single source of truth; the watch and widget are projections. Critically, the projection mechanism differs by surface because the constraints differ:

- **Watch** gets a lightweight `WatchSnapshot` (Codable struct) over **WCSession** — dual-path: `sendMessage` when the phone is reachable, `updateApplicationContext` (durable, re-delivered on next activation) when it isn't. No SwiftData and no HealthKit on the watch; pushing the whole database to a battery-constrained device would be wrong. Quick actions (start workout, log set) reverse-flow back over the same session.
- **Widget** reads a flat set of keys from **App-Group `UserDefaults`**, not the shared SwiftData store — WidgetKit's tight memory sandbox makes a heavy store the wrong tool. The phone writes the keys and calls `reloadAllTimelines()`; the widget falls back to a 15-minute timeline otherwise.
- **Focus-timer Live Activity** uses **ActivityKit** with a wall-clock `phaseEndsAt`, so the Dynamic Island counts down on the system timer with zero polling from the extension.

The tradeoff is explicit: watch/widget data can be slightly stale in exchange for far lower power draw and no background-task machinery. One App Group identifier ties all three surfaces together.

---

## Notable implementation details

- **A hand-rolled `@Observable @MainActor` DI container** (`ServiceContainer`, ~35 protocol-backed services) is wired at app root via SwiftUI `@Environment`, with the auth↔API-client circular dependency broken by injecting a token provider into the API client's interceptor before configuring auth. Protocol fronts give every service a mock for tests.
- **Single-flight deduplication** guards the expensive paths (the daily readiness call, AI insights): a second request for the same day joins the in-flight `Task` rather than firing a duplicate model call — a deliberate defense against the SwiftUI view-remount retry storm.
- **The AI coach has a real memory model**, not just a chat log: `LearnedPreference` rows are confidence-scored (explicit 0.9–1.0, observed 0.5, inferred 0.4), tagged with a subject taxonomy and a scope (weekday / match-day / travel / …), and **decay per-subject per-day** (red-line preferences never decay; meal-timing decays fast), auto-deactivating below 0.2. The retriever injects only the active, in-scope preferences into the system prompt.
- **Whoop webhooks** are verified at a route-level middleware — **HMAC-SHA256 with a constant-time (timing-safe) compare and a 5-minute timestamp window to defeat replays** — then deduplicated by `traceId` via a Redis key (Whoop retries), then handed to a **Vapor Queue** job so the HTTP handler returns immediately. The job invalidates the matching Redis cache patterns. Whoop OAuth tokens are AES-encrypted at rest, and token refresh is **deduplicated by an actor** so simultaneous requests for one user share a single refresh task. Scheduled jobs cover morning briefings, weekly summaries, leaderboard refresh, and twice-weekly notification batching.
- **Cross-surface verification is a documented hazard, not an afterthought.** The 5 modules read overlapping SwiftData; a change can compile, merge with zero git conflicts, and still desync two screens that read the same `@Observable` service. The repo encodes an "enumerate every reader before declaring done" rule and a backing review agent.
- **Pure engines, thin views.** The readiness math (`ReadinessAssembler`, `ReadinessTrendMath`), the floor, the adaptive updater, and the session DTO parser are all pure functions taking already-fetched arrays — the view model does the I/O. That's why **87 app-side test files** exist with a dedicated unit test per engine.
- **Sign in with Apple → short-lived access JWT + opaque rotating refresh tokens.** Apple identity tokens are verified server-side against Apple's JWKS (RS256, nonce + audience checked); refresh tokens are stored only as SHA-256 hashes with explicit revocation (`revoked_at`); and **instant logout works via a Redis `jti` blocklist** checked on every request rather than waiting for the access token to expire. A `ToSGateMiddleware` 451s any request from a user who hasn't accepted terms, with carve-outs for the accept/logout/delete routes.
- **Honest auth caveat:** the access-token signing key is currently HMAC-SHA256, not the ES256/P-256 the docs target (`configure.swift` carries the comment). Subscription state is written only by the App Store Server Notifications webhook, which is JWS-verified against Apple Root CA G3 (the old client-trusting `POST /subscription/verify` was removed). Gap: the webhook can't yet create a subscription row for a new purchase — that needs iOS to set `appAccountToken` on purchase — so new purchases are currently logged as orphans. Called out here rather than overstated.
- **XcodeGen-generated project** (`Tempo/project.yml` is source of truth — the `.xcodeproj` is not hand-edited), SwiftLint + SwiftFormat as pre-build phases, three configs (Dev/Staging/Release), Fastlane for release.

---

## Tech stack

**iOS app** — Swift 6 (strict/complete concurrency), SwiftUI, SwiftData, iOS 17.4+. HealthKit · WeatherKit · EventKit · Speech · WidgetKit + Live Activities (ActivityKit) · App Intents. Companion **watchOS 10** app (WCSession + complications) and a home/Lock-Screen **widget** (App-Group `UserDefaults`). 3rd-party SPM: PostHog, Firebase Crashlytics, Lottie, Inject (debug hot-reload), swift-snapshot-testing. ~111k LOC / ~410 Swift files; XcodeGen-managed, six targets.

**Backend** (`tempo-backend/`) — Vapor 4 on Swift 6, Fluent + PostgreSQL, Redis, Vapor Queues. JWT auth, APNs, App Store Server Notification verification, Whoop OAuth + webhooks, actor-based AI spend metering & response cache. ~15k LOC / ~107 Swift files, ~26 migrations.

**AI** — Anthropic Claude (Haiku for real-time prescriptions, Sonnet for deep/monthly analysis), proxied and budget-metered through the backend.

---

## Build & run

### iOS app

```bash
brew install xcodegen swiftlint swiftformat
cd Tempo
xcodegen generate          # generates Tempo.xcodeproj from project.yml — don't edit the project by hand
open Tempo.xcodeproj
```

Build the **Tempo** scheme (Debug → `app.tempo.Tempo.dev`). Set `ANTHROPIC_API_KEY`, `TEMPO_API_BASE_URL`, `TEMPO_ENVIRONMENT` via `Tempo/Configuration/*.xcconfig`. HealthKit, Live Activities, and push require a real device + an Apple Developer team for provisioning. Requires Xcode 26.5+.

### Backend

```bash
cd tempo-backend
# needs PostgreSQL + Redis running; config via env (see Sources/App/configure.swift)
export DATABASE_URL=... REDIS_URL=... JWT_SECRET=... ANTHROPIC_API_KEY=...
swift run App migrate     # apply Fluent migrations
swift run App             # serve
```

---

## Status — honest

**Pre-release.** Active development on the **`training-intelligence`** branch (the daily-brain hybrid above is what's being hardened there); `main` is the stable line. Not on the App Store. The readiness engine, safety floor, adaptive learning, sync queue, and AI budget gate are implemented and unit-tested; the synthetic prompt-quality harness is the live tool for keeping the model honest before launch. Real-device verification (HealthKit/Whoop end-to-end, push, Live Activities) is the gating work between here and ship — and is treated as the only verification that counts, since a green CLI build proves compilation, not runtime behavior.

This repo is a private, in-progress personal project, shared as an engineering work sample.
