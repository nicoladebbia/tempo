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
- Backend: `cd tempo-backend && swift build && swift test`. Databases: `scripts/testenv.sh db && eval "$(scripts/testenv.sh test-env)"` first.
- Local test backend: `scripts/testenv.sh up` runs Postgres + Redis + the server in test mode on 127.0.0.1:58080. AI and outside services are fake by default; switch with `testenv.sh ai fake|broken|empty|slow|error`. `sim.sh qa --local` signs the simulator into its own test account on it, and `--scenario NAME` seeds a starting state (`sim.sh scenarios`). Real server pushes reach the simulator; send any notification with `sim.sh notify <kind>`. The phone always uses production. Details → `run-tempo` skill.
- CI: the "Fast check" workflow runs on this Mac (self-hosted runner `mac-mini-tempo`, about 1–2 min, never blocks merges). The nightly at 03:00 (`scripts/nightly.sh`) runs the full tests and scenarios for main + open PRs; the report is at `~/.tempo-nightly/latest.html`.
- A CLI build proves compilation only. Nicola runs the app on his physical iPhone; only an on-device check after a fresh ⌘R counts as verified. "Still broken" reports → suspect a stale device build first (`.claude/rules/swift.md`).

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
