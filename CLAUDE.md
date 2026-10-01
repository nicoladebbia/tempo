# Tempo — Life Operating System

Native iOS app (Swift/SwiftUI) + Vapor backend (`tempo-backend/`) unifying fitness, nutrition, recovery, academics and accountability. Drill-sergeant tone. Built for public App Store release.

## Docs
- `docs/INDEX.md` — index of all 39 docs (reading orders, glossary). Start here to find anything.
- `ARCHITECTURE.md` overview · `docs/BUILD_PLAN.md` phases/steps · `docs/BUILD_PROGRESS.md` status.
- Read before coding: `docs/CROSS_DOC_AUDIT.md` (47 known inconsistencies — canonical values), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` (what WON'T work + alternatives), `docs/ARCHITECTURE_DECISIONS.md` (30 ADRs). The two audits are read-only.

## Build & test
- iOS: `cd Tempo && xcodegen generate` (project is generated from `project.yml`; never hand-edit the .xcodeproj). Scheme `Tempo`.
- iOS tests: `xcodebuild test -project Tempo/Tempo.xcodeproj -scheme Tempo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TempoTests`
- Backend: `cd tempo-backend && swift build && swift test` (run needs Postgres + Redis; see README).
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

## Shared-model changes — cross-surface verification (CRITICAL)
Modules read overlapping data (Fuel quadrant ↔ Nutrition surfaces; Body ↔ Move share training/recovery state). A change that compiles can still leave two screens showing different numbers. Before calling done on ANY edit to a shared model, `@Observable` service or SwiftData entity:
1. Enumerate every reader (tight grep of the model/property name) and name them.
2. Re-verify EACH reader, not just the one you were asked about.
3. Edit spans 2+ modules → run the `architecture-guard` agent.
4. Summarize the blast radius: "Changed X. Readers: […]. Verified: […]. Unverified: […]." Never "done" while a reader is unverified.

## Audit sessions — Nutrition and Training run in parallel
Two sessions work at the same time, one per subject, each from its own audit report:
- **Nutrition**: report https://claude.ai/artifact/WmALRmh57ngV2LDwnzEddL · memory `nutrition-audit-*.md`, `nutrition-round*.md`
- **Training**: report https://claude.ai/artifact/NFFzLjVbQYXMKYhLBTLMeN · memory `training-audit-*.md`, `training-round*.md`
- **Progress page (shared, live)**: https://claude.ai/artifact/3F52azKNe1Sfcotc3rgSLc. Write to it with the `ArtifactData` tool (load via ToolSearch). Collections: `areas/{nutrition|training}` (branch, pr, now, updated_at) · `rounds/{area}-{n}` (title, status todo|in-progress|in-review|done, prs, note) · `items` (area, round, title, status fixed|already-fixed|skipped|needs-shared, pr, note) · `shared` (title, why, files, suggested, status open|claimed|done, owner, pr) · `claims` (file, area, branch, why, since). Pin writes to existing docs with `if_version`; use ISO timestamps.

Rules:
1. **Start**: work out which subject you are (ask if unclear), read your report (`Artifact` read), the latest round memory and the progress page, then fix round by round with `/round <area> <n>`.
2. **Reports are read-only.** Never edit or republish them. Progress goes on the progress page (update `areas`/`rounds` when a round starts, opens a PR or merges; add an `items` row per fixed/skipped item), plus the round memory and the PRs.
3. **Own subject, anywhere.** You may change anything about your subject in any module: Nutrition owns everything about food (Fuel quadrant, nutrition services, meal/supplement notifications, grocery, backend food routes); Training owns everything about training (Move/Body training state, programs, logger, workout notifications, backend training routes). Don't fix the other subject's bugs: add them to the page's `shared` list with `suggested` set to the other area. A food-related edit in a shared file still follows the cross-surface rule above, and an edit spanning 2+ modules runs `architecture-guard`.
4. **Claim shared files first.** Before editing a file both sessions might touch (`Dashboard*`, `ContentView`, `TempoApp`, `DailyResetCoordinator`, `AccountabilityEngine`, `project.yml`, any shared service/model), check `claims` on the page. Free → add a claim (doc id = file name) and go. Held by the other area → don't edit it: add a `shared` item and do it after their PR merges. Delete your claims when your PR merges.
5. **Shared to-do.** Items with `suggested: shared` (or left open) are taken by whichever session finishes its current round first: set `status: claimed`, `owner`, then `done` + `pr`.
6. **Re-check on latest main before fixing.** `git fetch` and check the item still happens on `origin/main` (code read or test server). If it's already gone, log it as `already-fixed` with the commit/PR that fixed it, and skip it.
7. **Before opening or updating a PR**: merge `origin/main` into your branch, rerun the tests, and resolve conflicts in shared files carefully (keep both subjects' changes).
8. **Own test server.** Each worktree gets its own test server (port, database, clock): `scripts/testenv.sh status` shows yours, `scripts/testenv.sh servers` lists them all. Never reset or time-travel another session's server. (Available once PRs #72/#74 are merged.)

## Related projects
- `~/dev/nutritrack-app/` — NutriTrack (Flask, 140+ API endpoints, built-in Whoop integration)
- `~/dev/saife/` — Swift/SwiftUI iOS project (pattern reference)
