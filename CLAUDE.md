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
2. **Server-dependent features** (weekly plan, AI, pushes, Pro gates, groceries, receipts): `scripts/testenv.sh up` (add `--rebuild` after backend edits), then `scripts/sim.sh qa --local`. Each worktree gets its own test server (own port, database and clock), so `reset`, `time`, `fault` and `--rebuild` never touch another session's. `testenv.sh status` shows yours, `testenv.sh servers` lists them all. This simulator gets its own Pro test account; `--as NAME` gives another account, `--free` one without Pro.
3. **Start from a scenario, not by hand:** `scripts/sim.sh qa --local --scenario NAME` wipes the app and seeds a known state (`sim.sh scenarios` lists them). A new feature that needs a starting state gets a new `case "name": // description` in `Tempo/Tempo/App/ScenarioSeed.swift`, with a test in `ScenarioSeedTests`.
4. **Bad AI and slow networks:** check that AI features survive `testenv.sh ai broken`, `empty`, `slow` and `error` without a crash or blank screen. Set it back with `testenv.sh ai fake`. Real Claude only with `testenv.sh up --real-ai`, which costs money, so only when asked. `up --real-ai --record` saves real replies; `testenv.sh ai replay` serves them back for free.
5. **Notifications:** server pushes really reach the simulator (`testenv.sh pushes` shows them). `scripts/sim.sh notify <kind>` sends any notification with its real buttons (`notify help`).
6. **Outside services are fake** (`tempo-backend/Sources/App/TestMode/`). A `[test-mode] blocked outbound` line in `testenv.sh logs` means a new service needs a fixture. A changed AI prompt or response shape needs its fixture updated too; `TestModeTests` checks each fixture against the decoder its feature really uses.
7. **Time, failures, people:** check time-dependent features by moving the server clock (`testenv.sh time set sunday 19:55`, `time +3d`, `time reset`) and running the job now (`testenv.sh job run morning-briefing --as NAME`). The server's scheduled jobs never run on their own. Check error paths with `testenv.sh fault add <path> error|slow|logout|garbage|empty|timeout` (`fault clear` afterwards), sign-in with `auth ttl 10` and `sign-out NAME`, and Pro states with `testenv.sh sub NAME trial|cancelled|grace|billing-retry|expired|refunded`. Persona scenarios (`--scenario athlete|picky-vegan|exam-week|injured|lapsed-pro`) give weeks of history. A second user goes on `scripts/sim.sh --sim b qa --local --as NAME`. The browser control page (the `control` URL in `testenv.sh status`) does all of this with buttons. The clock moves app logic only: new XP rows and the leaderboard still use real dates. Always put the clock, faults and AI mode back when you're done.
8. **Report what you saw:** screenshots (`sim.sh shot`) or what you saw in `testenv.sh pushes`/`logs`. A simulator check is necessary but not sufficient: only Nicola's on-device check counts as verified.

- **Fast check** (GitHub, this Mac's runner `mac-mini-tempo`): runs on every push, about 15 s–2 min, never blocks merges. If it's red on your branch, fix it before calling the work done.
- **Nightly** at 03:00 (`scripts/nightly.sh`): all tests and scenarios for main + open PRs. Report at `~/.tempo-nightly/latest.html`.
- Known flaky test: `LiveActivityCoordinatorTests.testEndingActiveResumesHighestPrioritySuspendedAliveParticipant`. Rerun it before treating it as a regression.
- Test mode only runs locally (loopback DB, no Railway env, never `--env production`). Never set `TEMPO_TEST_MODE` on a deployed server.
- **API shape changes** (a route's JSON, a DTO, a CodingKey, a push payload): regenerate `contracts/golden/` (`TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden`) and make both sides pass: backend `ContractGoldenTests` and iOS `APIContractTests`. See `contracts/README.md`.

## Big changes: "Try it yourself" device-test page (REQUIRED)

Whenever a session builds a big change (a `/round`, a multi-lane feature, a redesign, or anything touching 5+ user-visible behaviours), it ends with a device-test page that Nicola works through on his iPhone. Example: https://claude.ai/artifact/9ZkPYxm5QMVnEno6TbyQtQ (Nutrition Rounds 2–3 Test).

- **Build it from `.claude/templates/device-test.html`.** Copy it to the scratchpad, fill in the header, setup box and `GROUPS`, and publish with `Artifact` using `capabilities: {"db": {}}` (load `artifact-capabilities` first). Keep the look and behaviour: Works / Partly / Broken / Didn't see on every step, a note box per step, a sticky tally, and an "Anything else" box for free ideas and problems.
- **Cover every change.** Write one step per user-visible change, grouped by screen or feature, each tagged with its round/PR. A step says what to tap (**Do**) and what should happen (**Expect**) in plain words. Include the cross-surface checks: when a number also shows on another screen (Dashboard tile, Health app), the step says it must match.
- **"Before you start" box (always):**
  1. The exact Xcode project to open: absolute path `~/dev/<worktree>/Tempo/Tempo.xcodeproj`, plus the branch name and the PR(s) it contains. Point at the worktree/branch that holds _all_ the changes being tested (the merged/stacked branch, or `~/dev/tempo` on `main` if it's already merged). Run `xcodegen generate` in that worktree before publishing, so the project is ready to open.
  2. The test rules: pick the iPhone as the run destination, do a fresh ⌘R (Product ▸ Clean Build Folder first if anything looks stale), the phone stays on the production backend, and one visible sign that tells an old build from the new one (e.g. "no Kitchen tab = old build").
  3. Any setup a step needs (Pro on/off, Whoop connected, permissions to reset afterwards).
- **Give Nicola the link** in the final summary under "👉 What you need to do", together with the Xcode path and branch.
- **Read the answers back** with `ArtifactData` (`list` on collection `results`; doc id = step id, `status` works|partly|broken|skip, `note`; `_general` = free notes). Every Broken/Partly step and every note becomes a fix or a follow-up, logged in the round memory (and the progress page's `items` for audit rounds). Republish the same URL for retests and keep step ids stable so earlier answers stay attached.

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
