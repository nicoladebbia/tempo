# MODULE_ARENA — "ClutchTime" Arena Module

> **Module**: Arena (ClutchTime)
> **App**: Tempo — iOS (SwiftUI, iOS 17+) + Vapor backend
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS + backend developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

**The single most important fact about Arena:** the backend Arena subsystem is real and substantial (XP, Leaderboard, Friend, Challenge, Achievement controllers, all migrations, a 108-row achievement seed, registered routes), **but the iOS client never calls any of it.** `APIClient` exposes only generic `request` / `buildRequest` / `executeWithRetry` — there are zero Arena endpoint methods. Every Arena screen on iOS reads local SwiftData or hardcoded mock data. The two sides are independent and unsynced. This split is documented per-feature below.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):

iOS:
- `Tempo/Tempo/Views/Arena/ArenaTabView.swift`, `ArenaMainView.swift`
- `Tempo/Tempo/Views/Arena/LeaderboardView.swift`, `FriendSystemView.swift`, `ChallengesView.swift`, `AchievementsView.swift`, `ActivityFeedView.swift`
- `Tempo/Tempo/ViewModels/ArenaViewModel.swift`
- `Tempo/Tempo/Services/Engines/XPEngineProtocol.swift` (contains `LevelSystem`), `XPEngine.swift`, `MockXPEngine.swift`, `AchievementLibrary.swift`
- `Tempo/Tempo/Models/Arena/XPEvent.swift`, `Achievement.swift`, `ChallengeLocal.swift`, `ActivityEvent.swift`
- `Tempo/Tempo/Models/Accountability/Streak.swift`, `Models/User/UserSettings.swift`
- `Tempo/Tempo/App/ServiceContainer.swift`
- `Tempo/Tempo/Services/Network/APIClient.swift` (cited to underscore the *absence* of Arena methods)
- `Tempo/Tempo/Views/Onboarding/ArenaIntroView.swift`

Backend (Vapor, `tempo-backend/Sources/App/`):
- `Controllers/XPController.swift`, `LeaderboardController.swift`, `FriendController.swift`, `ChallengeController.swift`, `AchievementController.swift`
- `Models/XPEvent.swift`, `Achievement.swift`, `Challenge.swift`, `Friendship.swift`
- `Migrations/CreateXPEvents.swift`, `CreateAchievements.swift`, `CreateChallenges.swift`, `CreateFriendships.swift`, `CreateWeeklyLeaderboard.swift`, `SeedAchievements.swift`
- `routes.swift` (controllers registered there)

---

## Table of Contents

1. [Design Philosophy & Principles](#1-design-philosophy--principles)
2. [XP Economy — Full Specification & Simulation](#2-xp-economy--full-specification--simulation)
3. [Level System](#3-level-system)
4. [Streak System](#4-streak-system)
5. [Screen 1: Arena Main View](#5-screen-1-arena-main-view)
6. [Screen 2: Profile / Stats View](#6-screen-2-profile--stats-view)
7. [Screen 3: Leaderboard View](#7-screen-3-leaderboard-view)
8. [Screen 4: Friend System](#8-screen-4-friend-system)
9. [Screen 5: Challenges](#9-screen-5-challenges)
10. [Screen 6: Achievements / Badges](#10-screen-6-achievements--badges)
11. [Screen 7: XP Animation System](#11-screen-7-xp-animation-system)
12. [Screen 8: Social Feed](#12-screen-8-social-feed)
13. [Screen 9: Notifications (Arena-Specific)](#13-screen-9-notifications-arena-specific)
14. [Screen 10: Onboarding for Arena](#14-screen-10-onboarding-for-arena)
15. [Screen 11: Arena Settings](#15-screen-11-arena-settings)
16. [Color System & Typography](#16-color-system--typography)
17. [Data Models & Edge Cases](#17-data-models--edge-cases)
18. [XP Economy Simulation & Balancing](#18-xp-economy-simulation--balancing)
19. [Leaderboard Psychology & League System](#19-leaderboard-psychology--league-system)
20. [Challenge Design — Templates & Seasonal Events](#20-challenge-design--templates--seasonal-events)
21. [Achievement System — Expanded (108 Achievements)](#21-achievement-system--expanded-108-achievements)
22. [Anti-Cheat & Integrity System](#22-anti-cheat--integrity-system)
23. [Social Features Deep Dive](#23-social-features-deep-dive)
24. [Competitive Onboarding — The First 30 Days](#24-competitive-onboarding--the-first-30-days)
25. [Retention Mechanics & Re-Engagement](#25-retention-mechanics--re-engagement)
26. [Sound Design for Arena](#26-sound-design-for-arena)
27. [XP Economy Sinks & Spending](#27-xp-economy-sinks--spending)
28. [Monthly Economy Health Report](#28-monthly-economy-health-report)

---

## 1. Design Philosophy & Principles

This section is **design intent only** — there is no code that enforces a "philosophy". It is preserved as context for why the screens look the way they do. The original §1 described a FIFA-Ultimate-Team / Strava / Duolingo competitive-tension feel built on seven pillars (always-a-scoreboard, loss aversion, micro-dopamine, social proof, accessible depth, fair competition, earned-not-bought).

> **Divergence from original spec:** The spec proposed a separate `tempo.color.arena.*` token namespace and a bespoke navy/electric-blue scoreboard palette. **That namespace does not exist.** Arena screens use the same global design tokens as the rest of the app (`Color.tempo*`, `TempoSpacing.*`, system fonts) — see §16. The "earned, not bought" pillar holds trivially in code only because **no XP sink or shop exists at all** (see §27), not because a no-pay-to-win rule was implemented.

---

## 2. XP Economy — Full Specification & Simulation

XP exists in **two independent, unsynced implementations**:

- **iOS**: `XPEngine.calculateXP(...)` (`XPEngine.swift`) computes XP locally from app events and writes `XPEvent` rows into SwiftData. `ArenaViewModel.load(...)` aggregates those local rows. The production `ServiceContainer.live()` wires the real `XPEngine()`; previews wire `MockXPEngine()`.
- **Backend**: `XPController` (`XPController.swift`) exposes `POST events`, `GET today`, `GET history`, `GET level` (registered in `routes.swift`). `XPController.calculateBaseXP(type:source:)` is the backend XP table.

These two engines have **different XP tables** and are never reconciled. **iOS never POSTs to the backend `events` endpoint** — no caller of any XP endpoint exists in the iOS codebase (`APIClient` has no XP method).

> **Divergence from original spec:** §2 specified one canonical XP economy with exact per-action base values, daily caps, and anti-farm rules. Reality is two divergent tables. The backend `calculateBaseXP` values (e.g. `workout_logged: 50`, `nutrition_target_met: 50`, `challenge_won: 200`, `friend_added: 5`) do **not** match the spec's table (e.g. spec "Complete any workout = 100 XP"). iOS `XPEngine.calculateXP` uses its own constant set (`xpWorkoutBase`, `xpMealEach`, `xpPerPomodoro`, `xpPenalty*`, etc.). Neither implements the documented daily-cap / anti-farm matrix as a verified system.

### 2.1 XP Sources

**As built (iOS, `XPEngine.calculateXP`):** source-based XP with workout base, per-exercise bonus, first-workout-of-day, early-bird, meal-each, all-meals, per-pomodoro, study-target, all-non-negotiables, sleep bonus, steps bonus, perfect-day, weekly/monthly streak, and milestone XP. Penalty branches exist (skip-workout, miss-meal, miss-study) producing negative `amount`.

**As built (backend, `XPController.calculateBaseXP`):** flat per-`type` integers for `workout_logged`, `sleep_target_met`, `recovery_checked`, `meal_logged`, `nutrition_target_met`, `study_session`, `streak_maintained`, `streak_milestone`, `challenge_joined`, `challenge_won`, `friend_added`, `insight_viewed`, `achievement_unlocked`.

> **Divergence from original spec:** The spec's "complete table" with recovery-adjusted bonuses, PR bonuses, daily caps, and explicit anti-farm notes is not implemented as specified on either side.

### 2.2 XP Penalties

**As built:** iOS `XPEvent.amount` can be negative; `XPEngine.calculateXP` has explicit penalty branches (skip workout, missed meal × count, missed study). `ArenaViewModel.load` filters `xpBreakdown` to `$0.xp != 0`.

> **Divergence from original spec:** A penalty mechanism exists structurally, but the spec's exact penalty table is not enumerated/wired as documented. Backend has no penalty path.

### 2.3 XP Display Formatting

> **Status: NOT IMPLEMENTED — compact XP formatting.** There is no `1.2K` / `M` abbreviation formatter for XP in any Arena view. `ArenaViewModel` exposes raw `Int` XP and `xpBreakdown`; `ArenaMainView` renders raw values (`"\(entry.xp) XP"`, etc.).

---

## 3. Level System

There are **three divergent level systems** in play. The original audit only flagged two; this is the authoritative list:

| Source | # Levels | Titles |
|--------|----------|--------|
| Original spec (§3.1/3.2) | 50 + Prestige beyond 50 | Rookie/Contender/.../Legend + Prestige |
| iOS `LevelSystem.definitions` (`XPEngineProtocol.swift`) | **35** | Recruit, Soldier, Warrior, Captain, Commander, General, Legend, Mythic |
| Backend `XPController.levelThresholds` | **12** | Rookie, Beginner, Starter, Consistent, Dedicated, Driven, Focused, Optimizer, Elite, Master, Legend, Transcendent |

The iOS level system is the one users actually see (the backend `GET level` endpoint is never called). `LevelSystem` provides `level(forXP:)`, `xpForNextLevel(currentXP:)`, `xpRequired(for:)`, `definition(for:)`. The XP→level curve is a hand-tuned 35-step table from `xpRequired: 0` (level 1) to `120_000` (level 35, "Mythic").

> **Divergence from original spec:** §3.1 specified a 50-level formula with a Prestige system beyond 50. Neither exists. `grep "prestige"` returns no matches anywhere in `Tempo/` or `tempo-backend/`. iOS caps at level 35; backend caps at level 12 with an entirely different title scheme.

### 3.2 Level Titles

> **Divergence from original spec:** The spec's 10-tier naming (Rookie/Contender/Warrior/Gladiator/Centurion/Captain/Commander/Titan/Warlord/Legend) matches **neither** implementation. iOS titles repeat across level bands (Recruit×4, Soldier×5, …, Mythic×1). Title is resolved via `XPEngine.levelName(for:)` → `LevelSystem.definition(for:).name`.

### 3.3 Level-Up Rewards

> **Status: NOT IMPLEMENTED — level-gated unlock table.** None of the spec's 15 level unlocks (profile color L3, leaderboard L5, challenge creation L7, Arena Shop L12, etc.) exist. There is no level-gating logic anywhere; leaderboard, challenges, and achievements are all reachable from `ArenaTabView` regardless of level.

### 3.4 Level Display Component — IMPLEMENTED

`ArenaMainView` renders a level badge and an XP progress bar. `ArenaViewModel.load` populates `level` (`xpEngine.currentLevel(totalXP:)`), `levelTitle` (`xpEngine.levelName(for:)`), `xpForNextLevel` (`xpEngine.xpToNextLevel(totalXP:)`), and `xpProgress` (computed from `LevelSystem` thresholds: `(totalXP − currentLevelXP) / (nextLevelXP − currentLevelXP)`). At/above max level the next-level XP falls back to `currentLevelXP + 10000`.

---

## 4. Streak System

### 4.1 Streak Definition — IMPLEMENTED

Streaks are persisted in SwiftData via `Streak` (`Models/Accountability/Streak.swift`). `ArenaMainView` queries the `"overall"` streak; `ArenaViewModel.load` surfaces `streakDays` from the passed `userStreakDays`.

### 4.2 Streak Multipliers — IMPLEMENTED

`ArenaViewModel.load`: `streakMultiplier = 1.0 + min(0.50, Double(userStreakDays) * 0.02)` — +2%/day, capped at +50% (25 days). Backend `XPController.streakMultiplier(for:)` implements the identical formula. This is the one place iOS and backend agree.

### 4.3 Streak Freeze — DIVERGED

`Streak` carries `freezesAvailable` / `freezesUsed` (default 2 available). `ArenaViewModel.load` surfaces `freezesAvailable = max(0, streak.freezesAvailable − streak.freezesUsed)` and `freezesUsed`. `ArenaMainView` has a `showFreezeSaved` toast ("Freeze saved your streak!").

> **Divergence from original spec:** Freeze is a **local-only** model field. There is no UI flow to manually spend a freeze, no purchase mechanism, and no backend persistence/sync of freeze state. The "freeze saved your streak" toast exists but the spend wiring that would trigger it is not implemented.

### 4.4 Streak Display Component — IMPLEMENTED

`ArenaMainView` renders streak day count and freeze count, plus a multiplier chip (`String(format: "%.0fx"/"%.2fx", streakMultiplier)`) shown when `streakMultiplier > 1.0`.

---

## 5. Screen 1: Arena Main View — DIVERGED

`ArenaTabView` is a `NavigationStack` hosting `ArenaMainView` with `navigationDestination(for: ArenaDestination.self)` routing to `.leaderboard / .friends / .challenges / .achievements / .activityFeed`. `ArenaMainView` (~37 KB) builds all documented sections: XP/level header, `leaderboardPreviewCard`, `challengeCTAButton`, active challenges card, achievements card, streak section, recent activity feed, and a floating `showXPGain` toast.

> **Divergence from original spec:** The UI shell is complete, but the social data is never populated. `ArenaViewModel.load(...)` takes local SwiftData arrays only and **never assigns** `leaderboardPreview`, `myRank`, `gapToFirst`, `friendCount`, or `pendingRequestCount`. Because `leaderboardPreview` stays empty, `leaderboardPreviewCard` always renders its fallback: the literal text **"Add friends to compete!"** plus an "Invite Friends" `NavigationLink` to `.friends`. The ranked-friends preview path (`leaderboardRow`) is dead in practice.

### 5.5 States

> **Status: NOT IMPLEMENTED — full state machine.** `ArenaViewModel.loadState` is a simple `.loading` / `.loaded` enum (`ArenaLoadState`). There is no "syncing", "offline", "sync failed", or "no data" Arena-wide state UI as specified.

---

## 6. Screen 2: Profile / Stats View

> **Status: NOT IMPLEMENTED.** There is no `ProfileView` or `StatsView` in `Views/Arena/` (directory contains only Achievements, ActivityFeed, ArenaMain, ArenaTab, Challenges, FriendSystem, Leaderboard). The dedicated profile/stats screen and the §6.4 "Friend's Profile View" do not exist.

---

## 7. Screen 3: Leaderboard View — DIVERGED

`LeaderboardView` calls `loadMockData()` in `.onAppear`. The list is hardcoded: `LeaderboardEntry`s for **marcus / sofia / jake / emma** plus a self row, with a code comment "Mock Data (until backend sync is wired)".

The backend side is fully built but unused: `LeaderboardController.leaderboard(req:)` (period-based) and `LeaderboardController.friendsLeaderboard(req:)`, plus `Migrations/CreateWeeklyLeaderboard.swift`. No iOS code calls either endpoint.

> **Divergence from original spec:** The spec's weekly/monthly/all-time/friends tabs, podium, and ranked list render against **100% hardcoded placeholder data**. The real backend leaderboard exists but is dead code from the client's perspective.

---

## 8. Screen 4: Friend System — DIVERGED

`FriendSystemView` is **fake/local**. Friends and pending requests are local `@State` arrays. `acceptRequest(_:)` and `declineRequest(_:)` mutate those arrays in memory only. The "Add Friend" path sets `showComingSoonAlert = true`, producing an alert titled **"Coming Soon"** with body **"This feature is not yet available. Stay tuned!"**.

The backend `FriendController` fully implements `sendRequest`, `listRequests`, `acceptRequest`, `declineRequest`, `listFriends`, `removeFriend` (+ `Friendship` model + `CreateFriendships` migration). **No iOS code calls any of it** — `APIClient` has no friend methods.

> **Divergence from original spec:** §8's add-friend flow, request flow, friend list, privacy controls, and block/remove are not wired. iOS is a local stub with an explicit "Coming Soon" alert; the complete backend is unused.

---

## 9. Screen 5: Challenges — DIVERGED

`ChallengesView` uses `@Query` over local `ChallengeLocal` (SwiftData). Both the quick-start path (`startQuickChallenge(_:)`) and the custom-create path (`createChallenge()`) call `modelContext.insert(...)` — **local only, never the backend**.

`ChallengeTemplate.templates` defines **5 quick-start templates** (not zero, not the spec's 24): "7-Day Grind" (`non_negotiable_streak`, 7d), "Volume King" (`training_volume`, 7d), "Sleep Better" (`sleep_score`, 7d), "Study Marathon" (`study_minutes`, 7d), "Step Master" (`steps`, 7d).

Backend `ChallengeController` fully implements `create`, `list`, `detail`, `join`, `leave` (+ `Challenge` model + `CreateChallenges` migration), all unused by iOS.

> **Divergence from original spec:** §9 specified 24 templates, a fairness/handicap system, and a daily-challenge generator. Reality: 5 hardcoded templates, free-form local creation, no fairness/handicap/normalization logic anywhere (`grep "fairness"/"handicap"` → none), no daily-challenge generator. Backend challenge API exists but is never called by the client.
>
> *(Note: the original doc audit claimed "no templates implemented" — that audit was stale. The 5 `ChallengeTemplate` entries above are the ground truth.)*

### 9.8 Daily Challenge / 9.11 Fairness System

> **Status: NOT IMPLEMENTED.** No daily-challenge generator and no challenge fairness/handicap/normalization logic exist in either `ChallengesView` or `ChallengeController`.

---

## 10. Screen 6: Achievements / Badges — DIVERGED

iOS: `AchievementsView` uses `@Query` over local `Achievement` (SwiftData), filtered by `AchievementCategory`. The achievement catalog comes from the local `AchievementLibrary` engine, not the backend.

Backend: `AchievementController` implements `earned`, `available`, `check`, `pin`, `unpin` (+ `Achievement` model + `SeedAchievements` migration). **iOS calls none of it.**

> **Divergence from original spec:** Two parallel, unsynced achievement systems (local `AchievementLibrary` vs backend `AchievementController` + 108-row seed). The spec's near-completion nudges are not implemented (`grep "nudge"/"nearComplete"` → none).

---

## 11. Screen 7: XP Animation System — DIVERGED

Only the basic XP-earn float exists. `ArenaViewModel.load` sets `lastXPGainAmount` and `showXPGain = true` when `newTodayXP > previousTodayXP` and it is not the initial load. `ArenaMainView` renders a floating "+X XP" toast gated on `showXPGain`.

> **Status: NOT IMPLEMENTED — the rest of §11.** No level-up animation, no streak-milestone animation, no achievement-unlock animation, no leaderboard rank-change animation, no challenge-win animation, and no sound system. No confetti / Lottie usage in `ArenaMainView` (Lottie is a listed dependency but not used here).

---

## 12. Screen 8: Social Feed — DIVERGED

`ActivityFeedView` uses `@Query` over local `ActivityEvent` sorted by timestamp descending. `ArenaViewModel.load` surfaces `recentActivityEvents` (the user's own most recent 20 events) for the inline preview on `ArenaMainView`.

> **Divergence from original spec:** This is a **personal activity log**, not a social feed. It shows only the current user's own `ActivityEvent` rows. There is no friends' activity, no feed-ranking algorithm, no reactions, and no backend feed endpoint. §12.3–12.9 (feed item types, algorithm, inline preview privacy, no-comments policy) are not implemented as a social system.

---

## 13. Screen 9: Notifications (Arena-Specific)

> **Status: NOT IMPLEMENTED.** The documented Arena push notifications (rank overtake, streak warning, challenge invite, achievement unlock, friend request) with frequency limits, timing windows, badges, and deep links do not exist. `rank_overtake` / `streak_warn` / etc. appear only as generic enum cases in `UserSettings.swift` / `ActivityEvent.swift` / `NotificationService.swift`, with no Arena-specific trigger logic.

---

## 14. Screen 10: Onboarding for Arena — DIVERGED

`ArenaIntroView` exists — a **single** intro screen ("WELCOME TO\nTHE ARENA.", title + body).

> **Divergence from original spec:** §14.2 specified a **5-screen** onboarding flow. Only one `ArenaIntroView` screen exists; the multi-screen flow, its triggers, and §14.3 technical specs are not implemented.

---

## 15. Screen 11: Arena Settings

> **Status: NOT IMPLEMENTED.** There is no Arena Settings screen. `find/grep "ArenaSetting"/"ArenaPrivacy"/"profileVisibility"` returns no matches. `UserSettings.swift` has a couple of related fields (`dailyXPGoal`, `league`) but no Arena settings UI, privacy controls, or notification toggles per §15.2.

---

## 16. Color System & Typography

Arena screens use the **global** Tempo design tokens, not a separate Arena palette.

> **Divergence from original spec:** §16 specified an independent Arena color/typography/spacing/radius system (navy #0A1628, SF Mono numbers, `tempo.color.arena.*` tokens). That namespace does not exist. Arena views consume `Color.tempo*` accessors, `TempoSpacing.*` enums, and system fonts identically to the rest of the app. Concrete values live in the asset catalog / `DesignTokens.swift` — see `MODULE_DASHBOARD.md` §1 for the canonical token system. Some Arena views use inline `.font(.system(size:weight:design:.monospaced))` for the scoreboard feel rather than `Font.tempo*` accessors.

---

## 17. Data Models & Edge Cases

### 17.1 Core Data Models — IMPLEMENTED (independent, unsynced)

iOS (SwiftData, `Models/Arena/`): `XPEvent`, `Achievement`, `ChallengeLocal`, `ActivityEvent`. Plus `Streak` (`Models/Accountability/`) and `UserSettings` (`Models/User/`, carrying `dailyXPGoal` and a `league` enum).

Backend (Fluent, `Models/`): `XPEvent`, `Achievement`, `Challenge`, `Friendship`, plus the `CreateWeeklyLeaderboard` migration. Backend `XPEvent` carries `baseXP`, `multipliedXP`, `streakMultiplier`, `metadata`, and a `flagged: Bool` field.

> **Divergence from original spec:** Models exist on both sides but are **independent and never synced**. The iOS models are the live ones; the backend models are populated only if the (uncalled) endpoints were ever invoked.

### 17.2 Edge Cases & Error Handling

> **Status: NOT IMPLEMENTED as a documented matrix.** Not separately verifiable without exhaustive trace; no dedicated Arena edge-case handling layer beyond per-view defaults and `ArenaLoadState`.

---

## 18. XP Economy Simulation & Balancing — DIVERGED

A hand-tuned XP curve exists in iOS `LevelSystem.definitions` (35 levels, `0 → 120_000`). The +50% multiplier cap (§18.5 intent) is implemented in `ArenaViewModel.load` and `XPController.streakMultiplier`.

> **Divergence from original spec:** The curve is for 35 levels, not the spec's 50, and was not verified against §18.4's exact production table. §18.1–18.3 archetype simulations are design artifacts, not code.

> **Status: NOT IMPLEMENTED — §18.4 production curve & §18.6 "Fair Start".** There is no rebalanced 50-level production table and no fair-start / new-player normalization logic anywhere in the codebase.

---

## 19. Leaderboard Psychology & League System — DIVERGED

`UserSettings.league` is a computed `League` enum (default `.bronze`), surfaced as `currentLeague` in `ArenaViewModel`.

> **Divergence from original spec:** League is a **cosmetic stored field only**. There is no promotion/relegation logic, no league-based leaderboard grouping, and `LeaderboardController` has no league logic. §19.1–19.4 (Bronze→Diamond tiers, friend-leaderboard psychology, notification intelligence) are not implemented.

> **Status: NOT IMPLEMENTED — §19.5 "Normalized" leaderboard view.** No normalized/handicapped leaderboard view exists.

---

## 20. Challenge Design — Templates & Seasonal Events — DIVERGED

As built: **5** quick-start templates in `ChallengeTemplate.templates` (see §9), all 7-day, free-form local creation otherwise.

> **Divergence from original spec:** §20.1 specified 24 templates with difficulty tiers. Only 5 single-tier templates exist; no `difficulty` field.

> **Status: NOT IMPLEMENTED — §20.3 daily micro-challenges & §20.4 seasonal events.** No micro-challenge generator and no seasonal-event system (`grep "seasonal"/"micro.challenge"` → none).

---

## 21. Achievement System — Expanded (108 Achievements) — DIVERGED

`Migrations/SeedAchievements.swift` seeds **exactly 108** achievements (verified by counting `category:` entries). Category distribution as seeded:

| Category | Count |
|----------|-------|
| training | 40 |
| social | 15 |
| study | 12 |
| nutrition | 12 |
| recovery | 11 |
| steps | 10 |
| streaks | 8 |
| **Total** | **108** |

`AchievementController.check` handles a limited set of criteria types (workout_count, study_hours — where `study_hours` is a simplified `hours = events.count`, streak_days, level).

> **Divergence from original spec:** Count matches (108 seeded) but the category taxonomy differs from §21.2 (no `academic`/`elite`/`secret` category tags — the seed uses training/social/study/nutrition/recovery/steps/streaks). Criteria-type coverage is partial and one is explicitly "simplified". Critically, **iOS does not consume this seed** — it uses the local `AchievementLibrary` engine instead. End-to-end this is two unsynced systems; the 108-row seed only matters to the (uncalled) backend.

---

## 22. Anti-Cheat & Integrity System — DIVERGED

What exists: `XPController.recordEvents` guards `body.events.count <= 50` per request (a batch-size limit). Backend `XPEvent` has a `flagged: Bool` field (defaulted `false` in `CreateXPEvents`).

> **Divergence from original spec:** This is a near-empty stub of §22. The `flagged` boolean is **never set to `true`** anywhere — no code outside the model/migration references it. There are no daily XP caps, no XP-velocity checks, no study/workout fraud detection, no social report system, no consequence ladder, and no trust score (§22.2–22.8 all absent).

---

## 23. Social Features Deep Dive

> **Status: NOT IMPLEMENTED.** No reaction system (§23.2 "6 custom reactions"), no trash-talk text reactions (§23.3), and no named friend groups (§23.4/23.5). The activity feed is the personal log described in §12, not a social interaction surface.

---

## 24. Competitive Onboarding — The First 30 Days

> **Status: NOT IMPLEMENTED.** No day-by-day onboarding milestone engine and no "no friends" empty-state strategy beyond the static "Add friends to compete!" / "Invite Friends" fallback in `ArenaMainView.leaderboardPreviewCard` (§5).

---

## 25. Retention Mechanics & Re-Engagement

> **Status: NOT IMPLEMENTED.** No Arena-specific daily/weekly retention-hook system (§25.1/25.2). Generic notification plumbing exists app-wide but no Arena re-engagement triggers.

---

## 26. Sound Design for Arena

> **Status: NOT IMPLEMENTED.** No Arena sound system. No `AudioServices` / sound-effect playback in any Arena view (§11.7 / §26).

---

## 27. XP Economy Sinks & Spending

> **Status: NOT IMPLEMENTED.** XP is **earn-only**. There is no Arena Shop, no XP sink, and no XP-spend/cosmetic-purchase mechanism anywhere (`grep "shop|sink|spend|cosmetic"` in `Views/Arena` + backend Controllers → none). `SubscriptionController`/`Receipt*` are IAP, unrelated to XP.

---

## 28. Monthly Economy Health Report

> **Status: NOT IMPLEMENTED.** No monthly XP-economy report exists (`grep "MonthlyEconomy|economyReport"` → none). A backend `WeeklySummaryJob` exists but produces per-user summaries, not an economy-health report.
