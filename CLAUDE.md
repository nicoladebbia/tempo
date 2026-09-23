# Tempo — Life Operating System

Native iOS app (Swift/SwiftUI) that unifies fitness, nutrition, recovery, academics, and accountability. Drill-sergeant tone. Built for public App Store release.

## Quick Start
- **Architecture overview:** `ARCHITECTURE.md`
- **Full documentation index:** `docs/INDEX.md` (start here to find anything)
- **Build plan:** `docs/BUILD_PLAN.md` (dependency-ordered phases + steps)
- **Build progress:** `docs/BUILD_PROGRESS.md` (what's done, what's next)

## Slash Commands
- `/build` — Start or continue building. Reads the build plan, finds next step, executes it following the docs, marks complete, commits, continues.
- `/build-status` — Show progress: phases complete, next step, blockers.
- `/build-step 3.2` — Show details for a specific step, optionally execute it.

## Hot Reload (Inject) — what auto-applies vs what needs ⌘R (IMPORTANT)
Tempo has Inject hot-reload wired (dev-only; `@ObserveInjection`+`.enableInjection()` in `ContentView.swift`, `-interposable` Debug linker flag in `project.yml`). When the InjectionIII app is running and watching `Tempo/`, **saving a `.swift` file injects it into the running simulator in ~1s — including saves made by your Edit/Write tools.** But this only works for a narrow class of change, and you MUST tell Nicola which case applies after every UI edit:

- **Injects live (no rebuild):** changes confined to a SwiftUI view `body` — colors, padding, fonts, text, spacing, conditional layout, card↔list swaps. Tell Nicola: "saved — should hot-reload in the sim."
- **Needs ⌘R rebuild (Inject will NOT catch it):** new/changed stored properties or `@State`, new types, changed function signatures, new files, `@Model`/SwiftData schema changes, anything in services/view-models structure, or anything touching app launch / data loading / navigation state. Tell Nicola explicitly: "this needs a ⌘R — Inject won't pick it up."
- **Multi-file edits:** after editing 2+ files in one change (e.g. a view AND its view model), do NOT trust the partial injection — tell Nicola to ⌘R once. Inject may inject one file mid-edit and show a broken intermediate state.
- **Never call a hot-injected screen "verified."** Inject reloads view code but does not restart the app or re-run launch logic. A structural change that *looks* right after injection is not proven — per global rule L145, only a full ⌘R relaunch exercises the real path. State "necessary but not sufficient — needs a clean ⌘R to verify" for anything structural.

## Stale Build on Device — CHECK FIRST when "it's still broken" (CRITICAL)
Nicola runs Tempo on his **physical iPhone** ("iPhone di Nicola"), not the simulator. `xcodebuild -destination 'platform=iOS Simulator'` (or `generic/platform=iOS`) **compiles but installs NOTHING on the device** — the phone keeps running whatever Xcode last ⌘R'd. This means a "still broken / my change isn't showing / all the old problems persist" report is, by default, a **stale binary**, NOT a code bug. This trap cost ~half a session (2026-05-31): repeated code-spelunking on a device running pre-change code.

**Before diagnosing any "still broken" / "didn't work" / "nothing changed" report:**
1. **Confirm the build is fresh on the device.** The deterministic tell: a DEBUG `print` you added produces **zero log lines** at the moment it should fire (e.g. zero `[Workout]` lines after starting a workout) → the instrumented code is NOT on the device → stale build. Stop; tell Nicola to ⌘R (device destination), do not touch code.
2. **CLI builds prove compilation ONLY.** `xcodebuild ... build` succeeding ≠ the change is on the phone, ≠ runtime-verified. NEVER write "verified"/"fixed"/"working" off a CLI build — only off an on-device observation after a confirmed fresh ⌘R (per global rule L145).
3. `xcrun devicectl list devices` reveals a connected physical device; if one is present, assume device-not-sim is the run target unless Nicola says otherwise.

## Architecture
- **iOS:** SwiftUI + SwiftData + HealthKit + EventKit (iOS 17.4+ per feasibility audit)
- **Backend:** Vapor (Swift) + PostgreSQL + Redis
- **Integrations:** Whoop API (OAuth2 via backend proxy), NutriTrack (Flask proxy), Apple HealthKit, Apple Calendar
- **AI:** Claude API (Haiku for real-time, Sonnet for deep analysis)
- **Auth:** Sign in with Apple + JWT (ES256)
- **Push:** APNs (Time Sensitive, NOT Critical Alerts — per feasibility audit)

## 5 Modules
1. **Dashboard (LifeOS)** — 4-quadrant view: Body/Fuel/Mind/Move
2. **Training (RepForge)** — AI workout coach, Whoop recovery-adjusted, football-aware
3. **Accountability (Lockdown)** — Non-negotiables, focus timer, drill-sergeant notifications
4. **Recovery (RecoverIQ)** — Whoop-powered daily prescriptions
5. **Arena (ClutchTime)** — XP, levels, leaderboards, challenges, achievements

## Parallel Claude Sessions — One Terminal Per Worktree (IMPORTANT)
Nicola runs several `claude` sessions at once, each in its own terminal, working on Tempo simultaneously ("you do Recovery, you do Arena, you do Training"). **The hard rule that makes this safe: each terminal must be in a SEPARATE git worktree — never multiple sessions in the same directory.** Two `claude` sessions in the same `~/dev/tempo` are independent processes editing the same files on disk; the second write silently clobbers the first with no conflict. Git cannot fix that. Separate worktrees physically isolate the files.

**Layout (sibling worktrees, each its own branch off `main`):**
```
~/dev/tempo/            ← MAIN repo. Merge here. Do NOT run parallel sessions in this dir.
~/dev/tempo-recovery/   ← terminal 1, branch `recovery`
~/dev/tempo-arena/      ← terminal 2, branch `arena`
~/dev/tempo-training/   ← terminal 3, branch `training`
```

**The helper script is `scripts/parallel.sh`** (run from the main repo):
- `./scripts/parallel.sh new recovery arena training` — creates one worktree+branch per name, opens a Terminal tab in each.
- `./scripts/parallel.sh list` — show active worktrees and their branch state.
- `./scripts/parallel.sh merge` — merge every worktree branch back onto `main` one at a time, then remove the worktrees+branches.

**Scope rule — assign by MODULE.** The 5 modules above are the natural boundaries: one session per module. Two sessions editing the same existing `.swift` file is the only real merge-conflict source; module scoping prevents it. Adding NEW files is conflict-free — `project.yml` is glob-sourced (`path: Tempo`), so XcodeGen auto-discovers new files and no session touches the project file.

**Build model: build-once-after-merge.** Parallel sessions EDIT and commit on their branch; they do not need to build. The single authoritative `/build` happens on `main` after all branches merge. Swift 6 strict-concurrency breakage surfaces there, not per-session — that's the accepted tradeoff.

**Two traps the merge step must handle:**
1. **Same-file conflict** = two sessions edited the same existing file. `parallel.sh merge` stops at it; resolve by hand (both intents matter), `git add`, `git commit`. A nasty conflict means the scope split was wrong — note it for next time.
2. **Shared-model desync (read the CRITICAL section below).** A clean merge with ZERO Git conflicts can still be wrong: if two sessions edited different files that both read the same `@Observable` service or SwiftData entity, it compiles, merges clean, and two screens show different numbers. After merge, run the enumerate-the-readers check on any shared model any session touched. **No Git conflict ≠ semantically safe.**

What worktrees do NOT fix: same-line edits still conflict at merge — but that's now an explicit, resolvable conflict instead of a silent overwrite. The fix for conflicts is better scope assignment, not Git config.

## Key Conventions
- Swift 6, strict concurrency
- SwiftData for local persistence, `@Observable` for services
- HealthKit as unified biometric bus
- Only 3 third-party iOS dependencies: PostHog, Crashlytics, Lottie (see `docs/DEPENDENCIES.md`)
- All colors/tokens from `docs/DESIGN_SYSTEM.md` — use canonical values
- All strings from `docs/UX_COPY_BIBLE.md`
- All state machines from `docs/STATE_MACHINES.md`
- **One asset catalog per target.** Tempo target = `Tempo/Tempo/Assets.xcassets` only. New colors go in `Tempo/Tempo/Assets.xcassets/Colors/`. Multiple `.xcassets` in the same target generates duplicate symbols in `GeneratedAssetSymbols.swift`. Every catalog folder needs a `Contents.json` at its root.
- **Never attach `.task`/`.onAppear` to a `Group` (or any conditional) whose first-realized branch is `EmptyView()`.** `Group` forwards modifiers to its *current* child; at first render that child is the `EmptyView()` branch, and `.task`/`.onAppear` on `EmptyView` is a **no-op** — so a self-loading view that gates on its own loaded state (`Group { if let x { card } else { EmptyView() } }.task { load() }`) **never loads** and is a permanent, silent, compiles-clean no-show. **Root any self-loading card's `body` in an always-present concrete container that hosts the lifecycle modifier** — `VStack(spacing: 0) { if let x { card } }.task { load() }`. Diagnosis: when a view that should self-populate renders nothing, **diff a working sibling in the same parent FIRST** (e.g. `MorningCheckInCard` was fixed by diffing `RecoveryAIInsightView` — same VStack, rendered fine — not by theorizing). Cost the paid lesson: D1 `MorningCheckInCard`, 2026-06-09.

## Shared-Model Changes — Cross-Surface Verification (CRITICAL)
Tempo's 5 modules read overlapping data. The Fuel quadrant and the Nutrition surfaces read the same nutrition model; Body and Move both read training/recovery state. The recurring bug: a change lands on ONE surface and silently desyncs the others, or fixing one screen breaks a sibling that reads the same source.

**The rule: before declaring done on ANY edit to a shared data model, `@Observable` service, or SwiftData entity, you MUST:**
1. **Enumerate every screen/view that reads it.** Grep the model/property name across the codebase to list all readers (scope the pattern tightly — a bare property name will false-positive). Name them explicitly in your response.
2. **Re-verify EACH reader** still renders correctly with the change — not just the one you were asked about. If Fuel changed, check the Nutrition surface too, and vice versa.
3. **Run the `architecture-guard` agent** (`.claude/agents/architecture-guard.md`) when the edit touches 2+ modules. That's what it's for.
4. **State the blast radius in your summary:** "Changed X. Readers: [list]. Verified: [list]. Unverified: [list]." Never write "done" while any reader is unverified — per global rule L145, one green surface verifies only that surface.

A change that compiles is NOT a change that's connected. The compile check passes while two screens show different numbers. Enumerate-the-readers is the only thing that catches it.

## Critical References (Read Before Coding)
- `docs/CROSS_DOC_AUDIT.md` — 47 known inconsistencies across docs. Always check canonical values here.
- `docs/TECHNICAL_FEASIBILITY_AUDIT.md` — Things that WON'T work as originally specified. Use recommended alternatives.
- `docs/ARCHITECTURE_DECISIONS.md` — 30 ADRs explaining WHY every decision was made.

## Documentation Suite (39 files, ~100K lines)
See `docs/INDEX.md` for the complete directory with reading orders, cross-references, and glossary.

## Related Projects
- `~/dev/nutrition-app/` — NutriTrack (Flask, 140+ API endpoints, Whoop integration built-in)
- `~/dev/saife/` — Swift/SwiftUI iOS project (reference for patterns)
