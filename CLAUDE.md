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

## Key Conventions
- Swift 6, strict concurrency
- SwiftData for local persistence, `@Observable` for services
- HealthKit as unified biometric bus
- Only 3 third-party iOS dependencies: PostHog, Crashlytics, Lottie (see `docs/DEPENDENCIES.md`)
- All colors/tokens from `docs/DESIGN_SYSTEM.md` — use canonical values
- All strings from `docs/UX_COPY_BIBLE.md`
- All state machines from `docs/STATE_MACHINES.md`
- **One asset catalog per target.** Tempo target = `Tempo/Tempo/Assets.xcassets` only. New colors go in `Tempo/Tempo/Assets.xcassets/Colors/`. Multiple `.xcassets` in the same target generates duplicate symbols in `GeneratedAssetSymbols.swift`. Every catalog folder needs a `Contents.json` at its root.

## Critical References (Read Before Coding)
- `docs/CROSS_DOC_AUDIT.md` — 47 known inconsistencies across docs. Always check canonical values here.
- `docs/TECHNICAL_FEASIBILITY_AUDIT.md` — Things that WON'T work as originally specified. Use recommended alternatives.
- `docs/ARCHITECTURE_DECISIONS.md` — 30 ADRs explaining WHY every decision was made.

## Documentation Suite (39 files, ~100K lines)
See `docs/INDEX.md` for the complete directory with reading orders, cross-references, and glossary.

## Related Projects
- `~/Projects/nutrition-app/` — NutriTrack (Flask, 140+ API endpoints, Whoop integration built-in)
- `~/Projects/saife/` — Swift/SwiftUI iOS project (reference for patterns)
