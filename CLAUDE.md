# Tempo — Life Operating System

Native iOS app (Swift/SwiftUI) + Vapor backend (`tempo-backend/`) unifying fitness, nutrition, recovery, academics and accountability. Drill-sergeant tone. Built for public App Store release.

## Docs
- `docs/INDEX.md` — index of all 39 docs (reading orders, glossary). Start here to find anything.
- `ARCHITECTURE.md` overview · `docs/BUILD_PLAN.md` / `docs/BUILD_PROGRESS.md` = the original build plan (124/124 done; history only).
- Read before coding: `docs/CROSS_DOC_AUDIT.md` (47 known inconsistencies — canonical values), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` (what WON'T work + alternatives), `docs/ARCHITECTURE_DECISIONS.md` (30 ADRs). The two audits are read-only.

## Build & test
- iOS: `cd Tempo && xcodegen generate` (project is generated from `project.yml`; never hand-edit the .xcodeproj). Scheme `Tempo`.
- iOS build/test/run: **always through `scripts/sim.sh`** — it gives each worktree its own simulator ("Tempo · <worktree>") and its own `DerivedData/`, so parallel sessions never queue on or overwrite each other's simulator. `scripts/sim.sh test` (TempoTests; pass `-only-testing:...` to narrow), `scripts/sim.sh build`, `scripts/sim.sh qa` (install + launch past onboarding). Never use `-destination 'name=iPhone 17'` or the default DerivedData. Driving the app, screenshots, installing on the iPhone → `run-tempo` skill.
- Leftovers: `scripts/cleanup.py` lists unused worktrees, simulators and build caches (dry run); `--yes` removes them. Run it after a round is merged.
- Backend: `cd tempo-backend && swift build && swift test`, after `scripts/testenv.sh db && eval "$(scripts/testenv.sh test-env)"` (your own test DB; slot 2 = fast check, 3 = nightly).
- A CLI build proves compilation only. Nicola runs the app on his physical iPhone; only an on-device check after a fresh ⌘R counts as verified. "Still broken" reports → suspect a stale device build first (`.claude/rules/swift.md`).

## Testing workflow (every session)
Verify on the simulator against the **local test backend**, never production. The phone always stays on production.
1. **Start of session:** if `~/.tempo-nightly/latest.html` shows failures on the branch you're working on, mention them before you start.
2. **Server-dependent features** (weekly plan, AI, pushes, Pro gates, groceries, receipts): `scripts/testenv.sh up` (add `--rebuild` after backend edits), then `scripts/sim.sh qa --local`. This simulator gets its own Pro test account; `--as NAME` gives another account, `--free` one without Pro.
3. **Start from a scenario, not by hand:** `scripts/sim.sh qa --local --scenario NAME` wipes the app and seeds a known state (`sim.sh scenarios` lists them). A new feature that needs a starting state gets a new `case "name": // description` in `Tempo/Tempo/App/ScenarioSeed.swift`, with a test in `ScenarioSeedTests`.
4. **Bad AI and slow networks:** check that AI features survive `testenv.sh ai broken`, `empty`, `slow` and `error` without a crash or blank screen. Set it back with `testenv.sh ai fake`. Real Claude only with `testenv.sh up --real-ai`, which costs money, so only when asked.
5. **Notifications:** server pushes really reach the simulator (`testenv.sh pushes` shows them). `scripts/sim.sh notify <kind>` sends any notification with its real buttons (`notify help`).
6. **Outside services are fake** (`tempo-backend/Sources/App/TestMode/`). A `[test-mode] blocked outbound` line in `testenv.sh logs` means a new service needs a fixture. A changed AI prompt or response shape needs its fixture updated too; `TestModeTests` checks each fixture against the decoder its feature really uses.
7. **Report what you saw:** screenshots (`sim.sh shot`) or what you saw in `testenv.sh pushes`/`logs`. A simulator check is necessary but not sufficient: only Nicola's on-device check counts as verified.
- **Fast check** (GitHub, this Mac's runner `mac-mini-tempo`): runs on every push, about 15 s–2 min, never blocks merges. If it's red on your branch, fix it before calling the work done.
- **Nightly** at 03:00 (`scripts/nightly.sh`): all tests and scenarios for main + open PRs. Report at `~/.tempo-nightly/latest.html`.
- Known flaky test: `LiveActivityCoordinatorTests.testEndingActiveResumesHighestPrioritySuspendedAliveParticipant`. Rerun it before treating it as a regression.
- Test mode only runs locally (loopback DB, no Railway env, never `--env production`). Never set `TEMPO_TEST_MODE` on a deployed server.
- **API shape changes** (a route's JSON, a DTO, a CodingKey, a push payload): regenerate `contracts/golden/` (`TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden`) and make both sides pass: backend `ContractGoldenTests` and iOS `APIContractTests`. See `contracts/README.md`.

## Architecture
- iOS 17.4+: SwiftUI + SwiftData + HealthKit (unified biometric bus) + EventKit. Swift 6 strict concurrency; `@Observable` services.
- Backend: Vapor + PostgreSQL + Redis. Auth: Sign in with Apple + JWT (ES256). Push: APNs Time Sensitive (NOT Critical Alerts).
- Integrations: Whoop (OAuth2 via backend proxy), NutriTrack (Flask proxy), HealthKit, Apple Calendar. AI: Claude API (Haiku real-time, Sonnet deep analysis).
- 5 modules: Dashboard/LifeOS (Body/Fuel/Mind/Move quadrants) · Training/RepForge · Accountability/Lockdown · Recovery/RecoverIQ · Arena/ClutchTime.

## Conventions
- Only 3 third-party iOS deps: PostHog, Crashlytics, Lottie (`docs/DEPENDENCIES.md`).
- Colors/tokens from `docs/DESIGN_SYSTEM.md`, strings from `docs/UX_COPY_BIBLE.md`, state machines from `docs/STATE_MACHINES.md`.
- Parallel sessions: one git worktree per session, never two in the same dir — see `/parallel`.
- Workflow commands: `/audit <area>` (read-only audit → report + fix rounds) · `/round <area> <n>` (fix one round: decisions up front, lanes in worktrees, PRs) · `/review` + `/fix`.

## Shared-model changes — cross-surface verification (CRITICAL)
Modules read overlapping data (Fuel quadrant ↔ Nutrition surfaces; Body ↔ Move share training/recovery state). A change that compiles can still leave two screens showing different numbers. Before calling done on ANY edit to a shared model, `@Observable` service or SwiftData entity:
1. Enumerate every reader (tight grep of the model/property name) and name them.
2. Re-verify EACH reader, not just the one you were asked about.
3. Edit spans 2+ modules → run the `architecture-guard` agent.
4. Summarize the blast radius: "Changed X. Readers: […]. Verified: […]. Unverified: […]." Never "done" while a reader is unverified.

## Related projects
- `~/dev/nutritrack-app/` — NutriTrack (Flask, 140+ API endpoints, built-in Whoop integration)
- `~/dev/saife/` — Swift/SwiftUI iOS project (pattern reference)
