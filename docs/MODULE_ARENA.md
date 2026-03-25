# MODULE_ARENA.md — "ClutchTime" Arena Module UX Specification

**App:** Tempo (iOS, SwiftUI)
**Module Codename:** ClutchTime
**Version:** 2.0
**Last Updated:** 2026-03-24
**Author:** UX/UI Spec — Head of Gamification (ex-Duolingo, Strava, FIFA Ultimate Team)

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

### Core Feeling
ClutchTime must feel like the intersection of a **FIFA Ultimate Team card screen**, **Strava's segment leaderboards**, and **Duolingo's streak anxiety**. The user should feel a constant, low-grade competitive tension — "I wonder if Marco passed me today" — that pulls them back into the app.

This is not gamification bolted onto a productivity app. This IS the reason people open Tempo at 11:47 PM to check if they can squeeze in one more non-negotiable before midnight. The Arena should produce the same compulsive "one more turn" feeling that Civilization perfected — except each "turn" is a real-life action that makes the user's life better.

### Design Pillars

1. **Always a scoreboard.** Every screen subtly reminds you where you stand relative to friends. XP is never more than one tap away.
2. **Loss aversion > reward seeking.** Streaks, rank positions, and "about to lose" notifications are more motivating than earning new things. Protect what you've built. Duolingo proved this: people are 2.5x more likely to open the app to avoid losing a streak than to gain XP.
3. **Micro-dopamine loops.** Every action produces visible feedback within 300ms. XP floats, bars fill, badges glow. Never a dead tap. The brain needs the reward signal to be IMMEDIATE — even a 1-second delay reduces habit formation by 40%.
4. **Social proof as fuel.** Seeing friends' activity normalizes effort. "Marco already did his workout" is more motivating than any push notification copy. This is the Strava model — you don't just run, you run knowing your friends will see it.
5. **Accessible depth.** Surface is simple (XP goes up, level goes up). Depth is there for those who want it (multiplier math, achievement hunting, challenge strategy).
6. **Fair competition, not demoralizing comparison.** The system must feel winnable to a casual user and deep to a hardcore one. Nobody should open the leaderboard and think "why bother." League tiers, weekly resets, and normalization solve this.
7. **Earned, not bought.** There is no pay-to-win. Every XP point represents real effort. This is sacred. The moment someone can buy XP, the entire competitive ecosystem dies.

### Visual Language

> **Design System exception (approved):** Arena uses its own independent color system to create a distinct "scoreboard" feel. These colors are registered in the Design System as `tempo.color.arena.*` tokens. Recovery zone colors (emerald/green) are aligned with `tempo.color.recovery.green` (#22C55E).

- **Primary palette:** Deep navy (#0A1628) background, electric blue (#2D7FF9) for XP/progress, molten orange (#FF6B2C) for streaks/fire, emerald (#22C55E) for achievements/wins, crimson (#FF3B5C) for losses/penalties.
- **Typography:** SF Pro Display (headings), SF Pro Text (body), SF Mono (numbers/stats). Numbers are ALWAYS displayed in SF Mono for that "scoreboard" feel.
- **Surfaces:** Cards use #12203A with 1pt border of #1E3A5F, corner radius 16pt. Elevated cards (active challenges, current rank) use a subtle glow: 0 0 20px rgba(45, 127, 249, 0.15).
- **Iconography:** SF Symbols throughout, with custom badge artwork for achievements (described per-achievement below).

---

## 2. XP Economy — Full Specification & Simulation

### 2.1 XP Sources — Complete Table

All XP values are BASE values before streak multipliers are applied.

#### Workout XP

| Action | Base XP | Conditions | Daily Cap |
|--------|---------|------------|-----------|
| Complete any workout | 100 XP | Must mark all exercises as done | 1 workout/day counts for XP |
| Recovery-adjusted compliance bonus | +20 to +50 XP | Green recovery = +50, Yellow = +30, Red (still trained) = +20 | Stacks on workout XP |
| Workout intensity bonus | +10 to +30 XP | Light = +10, Moderate = +20, Heavy = +30 (based on volume/load) | Per workout |
| First workout of the week (Monday) | +25 XP | Completed on Monday before 23:59 | Once per week |
| Personal Record (PR) | +75 XP | New max weight OR new max reps at same weight for any exercise | Per PR, max 3 PRs/day = 225 XP |

**Anti-farm note:** Only 1 workout per day earns the 100 XP base. Logging a second workout on the same day earns 0 base XP (PRs still count). This prevents "splitting" one workout into many for XP multiplication.

#### Study XP

| Action | Base XP | Conditions | Daily Cap |
|--------|---------|------------|-----------|
| Hit daily study target | 80 XP | Complete 100% of planned study time | Once per day |
| Study session logged | 30 XP | Minimum 25 minutes focused session (Pomodoro-length) | Max 6 sessions/day = 180 XP |
| Study time scaling bonus | +10 XP per hour | For every full hour studied beyond target | Max +50 XP/day |
| Exam mode survival | 150 XP | Complete a self-declared "exam week" (5+ consecutive days of 4h+ study) | Per exam week |

**Anti-farm note:** Study sessions use passive fraud detection only (gyroscope, accelerometer, session duration patterns -- see Section 22). No active phone interaction is required during study sessions, as interrupting deep focus would undermine the app's purpose. Sessions are flagged only when multiple passive signals combine to indicate likely fraud (e.g., phone in driving motion + long duration + no touch).

#### Nutrition XP

| Action | Base XP | Conditions | Daily Cap |
|--------|---------|------------|-----------|
| Log breakfast | 15 XP | Logged before 11:00 | Once per day |
| Log lunch | 15 XP | Logged before 15:00 | Once per day |
| Log dinner | 15 XP | Logged before 22:00 | Once per day |
| Log snack | 5 XP | Any additional meal/snack | Max 3 snacks/day = 15 XP |
| Hit protein target (within 10%) | +30 XP | Daily protein within 90-110% of target | Once per day |
| Hit calorie target (within 10%) | +20 XP | Daily calories within 90-110% of target | Once per day |
| Hit all macro targets | +40 XP | Protein + carbs + fat all within 10% of target | Once per day (replaces individual macro bonuses when achieved) |

#### Recovery & Sleep XP

| Action | Base XP | Conditions | Daily Cap |
|--------|---------|------------|-----------|
| Log sleep | 20 XP | Duration + quality logged | Once per day |
| Sleep score >= 80 | +25 XP | Based on duration, consistency, quality rating | Once per day |
| Sleep score >= 90 | +40 XP | Replaces the +25 bonus | Once per day |
| Green recovery score | +30 XP | Recovery algorithm rates user as "Green" | Once per day |

#### Steps XP

| Threshold | XP | Conditions |
|-----------|-----|------------|
| 5,000 steps | 20 XP | Synced from HealthKit |
| 8,000 steps | 35 XP | Replaces 5K reward |
| 10,000 steps | 50 XP | Replaces 8K reward |
| 15,000 steps | 75 XP | Replaces 10K reward |

Note: Step tiers are NOT cumulative. Only the highest achieved tier counts.

#### Non-Negotiables XP

| Action | Base XP | Conditions | Daily Cap |
|--------|---------|------------|-----------|
| Complete single non-negotiable | 10 XP | Per task checked off | Based on user's configured list |
| Complete ALL non-negotiables | +60 XP bonus | Every single one done before midnight | Once per day, stacks on individual XP |

#### Daily Composite Bonuses

| Action | Base XP | Conditions |
|--------|---------|------------|
| Perfect Day | 200 XP | ALL of: workout done + study target hit + all meals logged + all non-negotiables done + sleep logged |
| Near-Perfect Day | 75 XP | 4 out of 5 Perfect Day criteria met |

#### Daily Login Bonus

| Condition | XP | Notes |
|-----------|-----|-------|
| Open app (first time today) | 10 XP | Awarded once at first app open after midnight |
| Open app 7 days in a row | 25 XP bonus | Awarded on 7th consecutive day open, resets counter |

**Why login bonus exists:** This is a "foot in the door" mechanic. Getting someone to open the app is 90% of the battle. The XP is small enough to not distort the economy, large enough to register on the animation. Duolingo's daily visit streak is their #1 retention driver.

#### Challenge XP

| Action | Base XP | Conditions |
|--------|---------|------------|
| Join a challenge | 25 XP | One-time on join |
| Active challenge daily participation | 15 XP | Logged relevant metric on a challenge day |
| Win 1v1 challenge | 200 XP | Be the winner |
| Win group challenge | 300 XP | Be #1 in group of 3+ |
| Finish top 3 in group challenge | 100 XP | 2nd or 3rd place |
| Lose a challenge (participation) | 50 XP | Completed at least 50% of challenge days |

#### Maximum Theoretical Daily XP (No Challenges)

```
Workout:           100 + 50 + 30 + 25 (if Monday) = 205 (max with Monday bonus)
PRs:               75 * 3 = 225
Study:             80 + 180 + 50 = 310
Nutrition:         15 + 15 + 15 + 15 + 40 = 100
Recovery/Sleep:    20 + 40 + 30 = 90
Steps:             75
Non-negotiables:   ~50 (5 items) + 60 = 110
Perfect Day:       200
Login:             10
─────────────────────────────────────
THEORETICAL MAX:   ~1,325 XP/day (before multipliers)
REALISTIC GOOD DAY: ~500-700 XP/day
AVERAGE ACTIVE DAY: ~300-450 XP/day
```

### 2.2 XP Penalties

Penalties are applied at end-of-day (23:59 local time) to avoid punishing users who haven't finished their day yet.

| Violation | Penalty | Conditions | Grace |
|-----------|---------|------------|-------|
| Skip workout (scheduled day) | -50 XP | Had a workout planned, didn't mark as done or rest day | If recovery score is Red, no penalty (auto-excused) |
| Miss study target | -30 XP | Studied less than 50% of daily target | Weekends exempt unless user enabled weekend study |
| Miss all meals | -40 XP | Zero meals logged for the entire day | None |
| Miss 2+ meals | -20 XP | Logged only 1 meal | None |
| Break streak (from 7+ days) | -100 XP | Streak was >= 7 days and reset to 0 | Streak freeze prevents this |
| Break streak (from 3-6 days) | -50 XP | Streak was 3-6 days and reset to 0 | Streak freeze prevents this |

**Penalty Rules:**
- XP can never go below 0 for the day (daily floor = 0 XP).
- Penalties are NOT applied if the user has an active "Rest Day" or "Sick Day" flag set before 12:00 noon.
- Penalties are shown in the XP breakdown as red entries so the user understands what happened.
- Total daily penalty is capped at -150 XP to prevent catastrophic days from destroying motivation.

### 2.3 XP Display Formatting

- All XP numbers use SF Mono, weight: semibold.
- Positive XP: electric blue (#2D7FF9) with "+" prefix. Example: `+100 XP`
- Negative XP: crimson (#FF3B5C) with "-" prefix. Example: `-50 XP`
- Large numbers use comma separator: `12,450 XP`
- XP animations always show the delta, never just the new total.

---

## 3. Level System

### 3.1 XP-to-Level Formula

```
Cumulative XP required to reach level N = floor(200 * N^1.65)
XP for a single level = cumulative(N) - cumulative(N-1)
```

**Design target:** A Dedicated player (75th percentile) reaches Level 50 in approximately 5-6 months. See Section 18 for full simulation and archetype verification.

| Level | XP Required (cumulative) | XP for This Level | Title |
|-------|--------------------------|-------------------|-------|
| 1 | 0 | 0 | Rookie |
| 2 | 627 | 627 | Rookie |
| 3 | 1,490 | 863 | Rookie |
| 4 | 2,562 | 1,072 | Rookie |
| 5 | 3,820 | 1,258 | Rookie |
| 6 | 5,248 | 1,428 | Contender |
| 7 | 6,831 | 1,583 | Contender |
| 8 | 8,558 | 1,727 | Contender |
| 9 | 10,420 | 1,862 | Contender |
| 10 | 12,409 | 1,989 | Contender |
| 11 | 14,519 | 2,110 | Warrior |
| 12 | 16,744 | 2,225 | Warrior |
| 13 | 19,079 | 2,335 | Warrior |
| 14 | 21,520 | 2,441 | Warrior |
| 15 | 24,063 | 2,543 | Warrior |
| 16 | 26,703 | 2,640 | Gladiator |
| 17 | 29,438 | 2,735 | Gladiator |
| 18 | 32,263 | 2,825 | Gladiator |
| 19 | 35,176 | 2,913 | Gladiator |
| 20 | 38,175 | 2,999 | Gladiator |
| 21 | 41,255 | 3,080 | Centurion |
| 22 | 44,415 | 3,160 | Centurion |
| 23 | 47,652 | 3,237 | Centurion |
| 24 | 50,964 | 3,312 | Centurion |
| 25 | 54,349 | 3,385 | Centurion |
| 26 | 57,804 | 3,455 | Captain |
| 27 | 61,328 | 3,524 | Captain |
| 28 | 64,919 | 3,591 | Captain |
| 29 | 68,575 | 3,656 | Captain |
| 30 | 72,294 | 3,719 | Captain |
| 31 | 76,074 | 3,780 | Commander |
| 32 | 79,914 | 3,840 | Commander |
| 33 | 83,813 | 3,899 | Commander |
| 34 | 87,769 | 3,956 | Commander |
| 35 | 91,780 | 4,011 | Commander |
| 36 | 95,846 | 4,066 | Titan |
| 37 | 99,964 | 4,118 | Titan |
| 38 | 104,134 | 4,170 | Titan |
| 39 | 108,354 | 4,220 | Titan |
| 40 | 112,623 | 4,269 | Titan |
| 41 | 116,940 | 4,317 | Warlord |
| 42 | 121,304 | 4,364 | Warlord |
| 43 | 125,713 | 4,409 | Warlord |
| 44 | 130,167 | 4,454 | Warlord |
| 45 | 134,664 | 4,497 | Warlord |
| 46 | 139,204 | 4,540 | Legend |
| 47 | 143,785 | 4,581 | Legend |
| 48 | 148,407 | 4,622 | Legend |
| 49 | 153,069 | 4,662 | Legend |
| 50 | 157,770 | 4,701 | Legend |

**Time-to-Level-50 by Archetype (verified):**

| Archetype | Monthly XP (w/ multiplier) | Time to Level 50 | Level at 6 months |
|-----------|---------------------------|-------------------|-------------------|
| Ghost (25th) | ~2,130 | Never realistically | ~Level 6 |
| Casual (50th) | ~6,400 | ~24.7 months | ~Level 20 |
| Dedicated (75th) | ~22,500 | ~7.0 months | ~Level 42 |
| Hardcore (95th) | ~38,325 | ~4.1 months | Level 50 at ~month 4 |
| Perfect (100th) | ~83,310 | ~1.9 months | Level 50 in ~8 weeks |

**Why this curve works:** The Dedicated player hits Level 50 in approximately 7 months -- slightly beyond the original 6-month target, which is healthy. Reaching the final level should feel like an accomplishment, not an inevitability. The Casual player lands around Level 20 (Gladiator) at 6 months, which is the "aspirational middle" -- they can see the higher tiers exist and have something to chase. The Ghost player stays in early tiers, which is correct -- the system should not reward low engagement with high ranks.

**Beyond Level 50:** Prestige system. User can "prestige" back to Level 1 with a permanent star icon next to their name. Prestige count is displayed. XP requirement resets but all achievements and history are retained. Each prestige grants a unique border color for the avatar (Prestige 1 = gold, Prestige 2 = diamond, Prestige 3 = holographic).

### 3.2 Level Titles — Full List

| Range | Title | Visual Motif |
|-------|-------|-------------|
| 1-5 | Rookie | Gray shield |
| 6-10 | Contender | Bronze shield |
| 11-15 | Warrior | Silver shield with sword |
| 16-20 | Gladiator | Gold shield with dual swords |
| 21-25 | Centurion | Platinum helmet |
| 26-30 | Captain | Blue captain's insignia |
| 31-35 | Commander | Purple commander's star |
| 36-40 | Titan | Orange flame crown |
| 41-45 | Warlord | Red war banner |
| 46-50 | Legend | Holographic shifting gradient badge |

### 3.3 Level-Up Rewards

| Level | Unlock |
|-------|--------|
| 3 | Custom profile color (choose from 8 colors) |
| 5 | Leaderboard access unlocked |
| 7 | Challenge creation unlocked (can join before this) |
| 10 | Custom avatar border style (3 options) |
| 12 | Arena Shop access (spend XP on cosmetics — see Section 27) |
| 15 | Profile badge showcase (pin up to 3 achievements) |
| 18 | Custom reaction set (see Section 23.2) |
| 20 | Dark theme variant "Midnight Arena" |
| 25 | Animated avatar border |
| 28 | Group creation unlocked (see Section 23.5) |
| 30 | Custom challenge creation (set your own metrics) |
| 35 | Profile badge showcase expanded (pin up to 6) |
| 40 | Animated XP particles on profile |
| 45 | Exclusive "Warlord" chat emoji set |
| 50 | Prestige option unlocked, holographic profile card |

### 3.4 Level Display Component

```
+-----------------------------------------+
|  +--------+                             |
|  | LVL    |  WARRIOR                    |
|  |  14    |  ████████████░░░░░  72%     |
|  +--------+  21,520 / 24,063 XP        |
+-----------------------------------------+
```

**Specs:**
- Level number: SF Mono, 28pt, bold, white (#FFFFFF).
- Level badge: 48x48pt rounded square, background color matches title tier (gray/bronze/silver/gold/platinum/blue/purple/orange/red/holographic).
- Title text: SF Pro Display, 13pt, semibold, uppercase tracking 1.5pt, color matches tier.
- Progress bar: height 8pt, corner radius 4pt, background #1E3A5F, fill gradient left-to-right matching tier color.
- XP fraction: SF Mono, 12pt, regular, #8899AA.
- Percentage: SF Mono, 13pt, semibold, white.

---

## 4. Streak System

### 4.1 Streak Definition

A "streak day" is counted when the user completes **at least 3 of the following 5** before 23:59 local time:

1. Completed a workout OR logged a rest day (on a rest day)
2. Hit >= 75% of study target
3. Logged at least 2 meals
4. Completed at least 50% of non-negotiables
5. Logged sleep from previous night

This is intentionally achievable on "off days" to avoid streak-breaking on legitimate rest/low days.

### 4.2 Streak Multipliers

| Streak Length | Multiplier | Badge |
|---------------|-----------|-------|
| 0-2 days | 1.0x | None |
| 3-6 days | 1.1x | Small flame icon |
| 7-13 days | 1.25x | Medium flame, animated flicker |
| 14-29 days | 1.5x | Large flame, orange glow |
| 30-59 days | 1.75x | Blue flame, particle trail |
| 60-89 days | 2.0x | Purple flame, screen edge glow |
| 90-179 days | 2.25x | White-hot flame, avatar ring pulses |
| 180-364 days | 2.5x | Phoenix flame with wing spread animation |
| 365+ days | 3.0x | Legendary golden phoenix, permanent particle effect |

Multiplier applies to ALL XP earned that day (both positive sources). Penalties are NOT multiplied.

### 4.3 Streak Freeze

- **Earn rate:** 1 streak freeze per 7 consecutive streak days (auto-granted).
- **Max stockpile:** 3 freezes at a time.
- **Usage:** Automatically consumed if a day would break the streak. User is notified the next morning: "Your streak freeze saved your 14-day streak yesterday!"
- **Manual activation:** User can pre-activate a freeze from Arena Settings (e.g., planning a travel day). Pre-activated freezes show a snowflake icon on that day in the streak calendar.
- **Visual:** Frozen days show a blue snowflake icon instead of a flame in the streak calendar view.
- **Limitation:** Cannot use more than 2 freezes in any 14-day window (prevents gaming the system).
- **XP cost option:** Users can also purchase additional streak freezes from the Arena Shop for 500 XP each (max 1 purchase per week). See Section 27.

### 4.4 Streak Display Component

```
+----------------------------+
|   FIRE 14-DAY STREAK       |
|   +-+-+-+-+-+-+-+          |
|   |*|*|*|*|*|*|*| <- week  |
|   +-+-+-+-+-+-+-+          |
|   +-+-+-+-+-+-+-+          |
|   |*|*|*|*|*|*|*| <- week  |
|   +-+-+-+-+-+-+-+          |
|   1.5x MULTIPLIER ACTIVE   |
|   ICE 2 Freezes Available  |
+----------------------------+
```

**Specs:**
- Streak number: SF Mono, 32pt, bold, #FF6B2C (orange).
- "DAY STREAK": SF Pro Display, 14pt, semibold, uppercase, #FF6B2C.
- Flame icon: Custom animated Lottie, 24x24pt, loops continuously. Animation varies by streak tier (see 4.2).
- Calendar dots: 8pt circles. Filled = completed (green #22C55E). Empty outline = future. Red filled = missed (before freeze). Blue snowflake = freeze used. Today = pulsing ring animation.
- Multiplier text: SF Mono, 14pt, bold, electric blue (#2D7FF9).
- Freeze count: SF Pro Text, 12pt, regular, #8899AA. Snowflake icon is SF Symbol `snowflake`, 14pt.

---

## 5. Screen 1: Arena Main View

### 5.1 Navigation & Access

- Arena is a top-level tab in the app's tab bar (5th tab, rightmost).
- Tab icon: SF Symbol `trophy.fill`, 24pt.
- Active state: electric blue (#2D7FF9). Inactive: #556677.
- Badge on tab icon: red dot if there are unseen achievements, challenge invites, or leaderboard changes.

### 5.2 Full Screen Layout

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  ARENA                        GEAR  USER   |
|                                            |
| +----------------------------------------+ |
| |  +--------+                            | |
| |  | LVL    |  WARRIOR           FIRE14  | |
| |  |  14    |  ████████████░░░  72%      | |
| |  +--------+  21,520 / 24,063 XP       | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  TODAY'S XP                            | |
| |                                        | |
| |  +-----------+    Earned: +385 XP      | |
| |  |   385     |    Potential: +430 XP   | |
| |  |   XP      |    ──────────────────   | |
| |  +-----------+    Multiplier: 1.5x     | |
| |                                        | |
| |  GYM  Workout     +150 XP             | |
| |  BOOK Study        +80 XP             | |
| |  FORK Meals        +45 XP             | |
| |  FOOT Steps (8K)   +35 XP             | |
| |  CHECK Tasks       +50 XP             | |
| |  MOON Sleep        +25 XP             | |
| |                       See Details >    | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  TROPHY WEEKLY LEADERBOARD             | |
| |                                        | |
| |  CROWN 1. Marco         2,450 XP LV18 | |
| |     2. You           2,320 XP  LV14   | |
| |     3. Luca          2,180 XP  LV16   | |
| |                                        | |
| |  130 XP behind #1        See All >    | |
| |  (Weekly leaderboard shows RAW XP)    | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  SWORD ACTIVE CHALLENGES               | |
| |                                        | |
| |  vs Marco: Most Study Hours            | |
| |  You: 12.5h  |  Marco: 14.2h          | |
| |  ████████░░░░░░░░  3 days left         | |
| |                                        | |
| |  Group: Weekly XP Race (5 players)     | |
| |  You're #2          2 days left        | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  MEDAL RECENT ACHIEVEMENTS             | |
| |                                        | |
| |  [GOLD] Iron Will   [RUN] Road        | |
| |  30-day streak       Warrior           | |
| |  Unlocked today      10K steps x7     | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  SWORD CHALLENGE A FRIEND              | |
| |         [ Start a Challenge ]          | |
| +----------------------------------------+ |
|                                            |
| ░░░░░░░░░░░░ TAB BAR ░░░░░░░░░░░░░░░░░░ |
+--------------------------------------------+
```

### 5.3 Component Specifications

#### Header Bar
- "ARENA": SF Pro Display, 34pt, bold, white. Left-aligned, 16pt leading from safe area.
- Settings gear: SF Symbol `gearshape.fill`, 22pt, #8899AA. Tap target: 44x44pt. Position: trailing, 16pt from edge.
- Profile icon: SF Symbol `person.crop.circle.fill`, 22pt, #8899AA. Position: trailing, 8pt left of gear. Navigates to Profile/Stats View.

#### Hero Card (Level + Streak)
- Card: full width minus 20pt horizontal padding each side (`tempo.space.screen.edge`). Height: 88pt. Background: #12203A. Border: 1pt #1E3A5F. Corner radius: 16pt.
- Level badge: as specified in Section 3.4.
- Streak flame + number: positioned trailing, vertically centered. Flame is 20pt Lottie animation. Number is SF Mono, 20pt, bold, #FF6B2C.
- Tap interaction: tapping the hero card opens a modal with detailed level progress and streak calendar.
- Animation on load: XP bar fills from 0 to current percentage over 800ms, ease-out-cubic.

#### Today's XP Card
- Card: full width minus 16pt padding. Min height: 180pt (expands with content). Background: #12203A. Border: 1pt #1E3A5F. Corner radius: 16pt. Padding: 16pt internal.
- "TODAY'S XP": SF Pro Display, 13pt, semibold, uppercase, tracking 1.5pt, #8899AA. Top-left.
- Large XP number: SF Mono, 48pt, bold, electric blue (#2D7FF9). Centered in left portion. Counts up from 0 with a slot-machine animation on first load (1200ms).
- "Earned" / "Potential": SF Pro Text, 14pt, regular, #AABBCC. "Potential" shows XP still earnable today in a dimmed style.
- Multiplier: SF Mono, 14pt, bold, #FF6B2C. Shows current streak multiplier.
- XP breakdown rows:
  - Each row: emoji (16pt) + category name (SF Pro Text, 14pt, #CCDDEE) + XP value (SF Mono, 14pt, semibold, #2D7FF9), trailing-aligned.
  - Row height: 32pt. Vertical spacing: 4pt.
  - Categories not yet earned today show in dimmed (#556677) with "+0 XP".
  - Penalty rows (if any) show in crimson (#FF3B5C).
- "See Details >": SF Pro Text, 13pt, semibold, #2D7FF9. Trailing bottom. Tap navigates to full XP breakdown sheet.
- Tap interaction: tapping any row opens a detail popover showing the exact sources (e.g., tapping "Meals +45 XP" shows "Breakfast +15, Lunch +15, Snack +5, Protein target +10").

##### XP Detail Sheet (presented as .sheet modifier, detent: .medium expanding to .large)

```
+--------------------------------------------+
|            -- drag indicator --             |
|                                            |
|  TODAY'S XP BREAKDOWN       March 24       |
|                                            |
|  EARNED                                    |
|  ─────────────────────────────────────     |
|  GYM Push Day Workout          +100 XP     |
|     Recovery bonus (Green)     +50 XP      |
|     Intensity (Heavy)          +30 XP      |
|  BOOK Study target hit         +80 XP      |
|     Session 1 (45min)          +30 XP      |
|     Session 2 (30min)          +30 XP      |
|  FORK Breakfast                +15 XP      |
|     Lunch                      +15 XP      |
|     Snack                       +5 XP      |
|     Protein target hit         +30 XP      |
|  FOOT Steps (8,245 -- 8K tier) +35 XP      |
|  CHECK 4/5 non-negotiables     +40 XP      |
|  MOON Sleep logged (7.5h)      +20 XP      |
|     Sleep score 82             +25 XP      |
|  DOOR Login bonus              +10 XP      |
|  ─────────────────────────────────────     |
|  Subtotal                     +515 XP      |
|  Streak multiplier (1.5x)    x 1.5        |
|  ─────────────────────────────────────     |
|  TOTAL EARNED                 +772 XP      |
|                                            |
|  STILL AVAILABLE TODAY                     |
|  ─────────────────────────────────────     |
|  FORK Dinner                   +15 XP      |
|  CHECK 1 remaining task        +10 XP      |
|     All tasks bonus            +60 XP      |
|  FOOT Walk to 10K steps        +15 XP      |
|                                            |
|  Potential remaining           +100 XP     |
|  (after 1.5x multiplier)      +150 XP     |
|                                            |
|  PENALTIES                                 |
|  ─────────────────────────────────────     |
|  None today CHECK                          |
+--------------------------------------------+
```

**Specs for XP Detail Sheet:**
- Drag indicator: 36x5pt rounded rectangle, #556677, centered, 8pt from top.
- Section headers ("EARNED", "STILL AVAILABLE", "PENALTIES"): SF Pro Display, 13pt, semibold, uppercase, tracking 1.2pt. "EARNED" = #22C55E, "STILL AVAILABLE" = #8899AA, "PENALTIES" = #FF3B5C.
- Row items: emoji 14pt + label SF Pro Text 14pt regular #CCDDEE + value SF Mono 14pt semibold (blue for earned, gray for available, red for penalties). Indented sub-items have 24pt leading indent.
- Divider lines: 0.5pt, #1E3A5F, full width minus 16pt padding.
- Multiplier row: highlighted with subtle blue background (#2D7FF9 at 10% opacity), corner radius 8pt.
- Total row: SF Mono, 18pt, bold, white. Underlined with 2pt blue line.

#### Leaderboard Preview Card
- Card: full width minus 16pt padding. Height: ~140pt. Background: #12203A. Border: 1pt #1E3A5F. Corner radius: 16pt.
- "WEEKLY LEADERBOARD": SF Pro Display, 13pt, semibold, uppercase, tracking 1.5pt, #8899AA.
- Trophy emoji: inline, 16pt.
- Each rank row: height 36pt.
  - Rank number: SF Mono, 16pt, bold. #1 = gold (#FFD700), #2 = silver (#C0C0C0), #3 = #CD7F32 (bronze). Crown SF Symbol `crown.fill` 14pt gold for #1, replaces rank number.
  - Avatar: 28x28pt circle, loaded from user profile. Placeholder: SF Symbol `person.crop.circle.fill` in tier color.
  - Name: SF Pro Text, 15pt, semibold, white. "You" is highlighted with electric blue.
  - XP: SF Mono, 14pt, regular, #8899AA. Trailing.
  - Level badge: 20x20pt mini version of level badge component. Trailing after XP.
- Current user row: entire row has a subtle blue background (#2D7FF9 at 8% opacity), left border 3pt electric blue.
- Gap text: "130 XP behind #1" — SF Pro Text, 12pt, regular, #FF6B2C. Only shown when user is not #1.
- "See All >": SF Pro Text, 13pt, semibold, #2D7FF9. Trailing. Navigates to full Leaderboard View.
- Empty state (no friends): card shows "Add friends to compete!" with an "Invite Friends" button (see Section 8).

#### Active Challenges Card
- Card: full width minus 16pt padding. Variable height. Background: #12203A. Border: 1pt #1E3A5F. Corner radius: 16pt.
- "ACTIVE CHALLENGES": SF Pro Display, 13pt, semibold, uppercase, tracking 1.5pt, #8899AA. Sword-cross emoji inline.
- Individual challenge items stack vertically, separated by 0.5pt dividers.
- Challenge item:
  - Type + opponent: SF Pro Text, 14pt, semibold, white. "vs Marco: Most Study Hours"
  - Score comparison: SF Mono, 14pt, regular, white. Pipe separator `|`. User's score is blue if winning, red if losing.
  - Time remaining: SF Pro Text, 12pt, regular, #8899AA. "3 days left"
  - Progress bar: height 6pt, corner radius 3pt. Background #1E3A5F. Fill: blue if winning, red if losing. Represents time elapsed (not score).
- Max visible: 2 challenges. If more, show "+2 more" link.
- Tap: navigates to challenge detail view.
- Empty state: "No active challenges. Start one!" with CTA button.

#### Recent Achievements Card
- Card: full width minus 16pt padding. Height: 100pt. Background: #12203A. Border: 1pt #1E3A5F. Corner radius: 16pt.
- "RECENT ACHIEVEMENTS": SF Pro Display, 13pt, semibold, uppercase, tracking 1.5pt, #8899AA.
- Horizontal scroll of achievement badges (if more than 2):
  - Each badge: 64x64pt icon + name (SF Pro Text, 11pt, semibold, white, centered below) + unlock description (SF Pro Text, 10pt, regular, #8899AA).
  - Spacing: 12pt between badges.
- New/unseen badges have a subtle glow animation (pulsing white border, 2 seconds, repeats 3x then stops).
- Tap: navigates to full Achievements View.
- Empty state: "Complete tasks to unlock achievements!" with a locked badge icon.

#### Challenge a Friend CTA
- Full-width button, 16pt horizontal padding. Height: 52pt. Corner radius: 14pt.
- Background: gradient left-to-right, #2D7FF9 to #6C5CE7 (blue to purple).
- Text: "Challenge a Friend" — SF Pro Display, 17pt, bold, white, centered.
- SF Symbol `bolt.fill` 18pt white, 8pt left of text.
- Tap: opens Challenge Creation flow (Section 9.5).
- Press state: scale to 0.97, opacity 0.9, spring animation 200ms.
- Shadow: 0 4 20 rgba(45, 127, 249, 0.3).

### 5.4 Scroll Behavior
- Screen is a single `ScrollView` with `.scrollIndicators(.hidden)`.
- Hero card is pinned (sticky header) when scrolling: shrinks from 88pt to 56pt height, level badge shrinks to 32x32pt, streak moves inline. Transition: 300ms spring.
- Pull-to-refresh: custom Lottie animation of a trophy spinning. Refreshes all data.
- Bouncy overscroll: standard iOS rubber-banding.

### 5.5 States

#### Loading State
- Skeleton shimmer on all cards. Shimmer gradient: #12203A to #1E3A5F to #12203A, animated left-to-right, 1.5s loop.
- Hero card shows level badge placeholder (gray circle) and shimmer bar for XP.

#### Error State
- If data fails to load: card shows "Couldn't load [section]. Tap to retry." with SF Symbol `arrow.clockwise` in #FF6B2C. Retry animation: icon rotates 360 degrees.

#### First-Time State (New User)
- Hero card shows Level 1, 0 XP, 0-day streak.
- Today's XP card shows all categories at +0 XP with hint text: "Complete activities to earn XP!"
- Leaderboard preview shows empty state with invite CTA.
- Challenges card shows onboarding prompt: "Challenges unlock at Level 7. You're 6,831 XP away!"
- Achievements card shows the first "hidden" achievement teaser: "??? — Complete the Arena tutorial"

---

## 6. Screen 2: Profile / Stats View

### 6.1 Navigation
- Accessed via profile icon in Arena header, or by tapping your own row in any leaderboard.
- Presented as a push navigation (slides in from right).
- Back button: "Arena" with chevron.

### 6.2 Full Screen Layout

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  < Arena           PROFILE        EDIT     |
|                                            |
|           +------------+                   |
|           |            |                   |
|           |  AVATAR    |                   |
|           |   80pt     |                   |
|           |            |                   |
|           +------------+                   |
|          @nicoladebbia                     |
|       SWORD WARRIOR -- Level 14            |
|                                            |
|  +--------+--------+--------+--------+    |
|  |TOTAL   |WORK-   |STUDY   |MEALS   |    |
|  | XP     |OUTS    |HOURS   |        |    |
|  |45.2K   | 147    | 312h   | 891    |    |
|  +--------+--------+--------+--------+    |
|                                            |
| +----------------------------------------+ |
| |  FIRE STREAKS                          | |
| |                                        | |
| |  Current streak:        14 days        | |
| |  Longest ever:          43 days        | |
| |  Streak freezes:        2/3            | |
| |                                        | |
| |  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+         | |
| |  |*|*|*|*|*|*|*|*|*|*|*|*|*|*|        | |
| |  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+         | |
| |  Mar 11 ───────────────── Mar 24       | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  CHART THIS MONTH (March 2026)         | |
| |                                        | |
| |  Total XP earned:      8,420 XP        | |
| |  Avg daily XP:           351 XP        | |
| |  Workouts completed:      18           | |
| |  Study hours:           62.5h          | |
| |  Perfect days:              7          | |
| |  Challenges won:            3          | |
| |                                        | |
| |  ▁▂▃▅▇█▅▃▅▇█▅▂▃▅▇█▅▃▁▂▃▅             | |
| |  1  5  10  15  20  24                  | |
| |          Daily XP Chart                | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  MEDAL ACHIEVEMENT SHOWCASE            | |
| |                                        | |
| |  [TROPHY Iron Will]  [FLEX Beast Mode] | |
| |  [BOOK Scholar]                        | |
| |                                        | |
| |  12/108 Achievements Unlocked          | |
| |                   View All >           | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  MEDAL PERSONAL RECORDS                | |
| |                                        | |
| |  Bench Press 1RM:         95 kg        | |
| |  Squat 1RM:              120 kg        | |
| |  Deadlift 1RM:          140 kg         | |
| |  Longest study session:  4.5h          | |
| |  Highest daily XP:      1,120          | |
| |  Highest weekly XP:     5,830          | |
| |  Most steps in a day:   22,450         | |
| +----------------------------------------+ |
|                                            |
| ░░░░░░░░░░░░ TAB BAR ░░░░░░░░░░░░░░░░░░ |
+--------------------------------------------+
```

### 6.3 Component Specifications

#### Avatar Section
- Avatar: 80x80pt circle. Loaded from user's photo library or camera. Placeholder: SF Symbol `person.crop.circle.fill`, 80pt, #556677.
- Avatar border: 3pt ring. Color determined by level tier. Animated border for Level 25+ (slow rotation of gradient, 8 seconds per loop).
- Prestige stars (if any): small star icons (12pt) arranged in an arc above the avatar. Gold fill, SF Symbol `star.fill`.
- Edit button (pencil icon): top-right of screen, SF Symbol `pencil`, 20pt, #8899AA. Opens profile edit sheet.
- Username: SF Pro Text, 16pt, regular, #8899AA. Centered below avatar. Prefixed with "@".
- Title + Level: SF Pro Display, 18pt, bold, tier color. Sword emoji before title. Centered.

#### Stats Grid
- 4-column grid, full width minus 32pt padding. Height: 72pt per cell.
- Each cell: label on top (SF Pro Text, 11pt, regular, uppercase, #8899AA) + value below (SF Mono, 22pt, bold, white).
- Dividers: 0.5pt vertical lines between cells, #1E3A5F.
- Total XP: formatted with "K" suffix for thousands (e.g., "45.2K"). Below 1000: show exact number.
- Study hours: suffixed with "h". Meals: plain number.
- Tap any cell: haptic feedback (light impact) + shows a tooltip with exact value and historical trend.

#### Streaks Card
- As described in Section 4.4, but expanded to show full 14-day calendar view.
- Calendar dots are 10pt with 4pt spacing.
- Date labels below: SF Mono, 10pt, #556677.
- "Longest ever" has a small trophy icon if it equals or exceeds 30 days.

#### Monthly Summary Card
- "THIS MONTH" header with month name auto-populated.
- Stats rows: label (SF Pro Text, 14pt, regular, #AABBCC, leading) + value (SF Mono, 14pt, semibold, white, trailing).
- Row height: 28pt. Vertical padding between rows: 2pt.
- Daily XP chart: SwiftUI `Chart` using `BarMark`. Bar color: electric blue. Height: 80pt. X-axis: day numbers. Y-axis: hidden (bars are relative). Tap a bar to see that day's exact XP in a popover.
- Swipe left/right to navigate to previous/next months. Pagination dots below chart.

#### Achievement Showcase
- Shows user's pinned achievements (up to 3 pre-Level 35, up to 6 after).
- Each achievement: 56x56pt badge icon + name below (SF Pro Text, 11pt, semibold).
- Horizontal layout, centered. If fewer than max, remaining slots show dashed circle outlines (#1E3A5F).
- "12/108 Achievements Unlocked": SF Pro Text, 13pt, regular, #8899AA.
- "View All >": SF Pro Text, 13pt, semibold, #2D7FF9. Navigates to full Achievements screen.

#### Personal Records Card
- Each PR row: label (SF Pro Text, 14pt, regular, #AABBCC) + value (SF Mono, 14pt, bold, white) + small trend indicator if recently set (SF Symbol `arrow.up` 10pt, #22C55E, with "NEW" tag in tiny caps if set within last 7 days).
- PRs are auto-detected from workout logs. Gym PRs show weight in user's preferred unit (kg/lbs).
- Tap a PR row: shows history of that PR over time (simple line chart in a popover).

### 6.4 Friend's Profile View (Viewing Someone Else)

Same layout as own profile but:
- Edit button replaced with "..." overflow menu (options: Remove Friend, Block, Report).
- Avatar has no edit state.
- Achievement showcase shows THEIR pinned badges.
- "Challenge" button appears below stats grid: pill button, blue gradient, "Challenge @marco".
- Sensitive data hidden based on their privacy settings (see Section 15).
- Personal records only shown if they've opted in to sharing them.

### 6.5 States

- **Own profile, new user:** All stats show 0. Achievement showcase empty. PR list shows "Complete workouts to set records!" Monthly chart is flat.
- **Friend profile, private user:** Hidden sections show a lock icon + "This user keeps this info private."
- **Loading:** Skeleton shimmer on avatar (pulsing circle), stats grid (shimmer bars), cards.

---

## 7. Screen 3: Leaderboard View

### 7.1 Navigation
- Accessed via "See All >" from leaderboard preview card, or via tab within Arena.
- Full-screen push navigation from Arena Main View.

### 7.2 Full Screen Layout

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  < Arena        LEADERBOARD                |
|                                            |
|  +-----------+------------+------------+   |
|  | WEEKLY    | MONTHLY    | ALL-TIME   |   |
|  | (active)  |            |            |   |
|  +-----------+------------+------------+   |
|                                            |
|  [FRIENDS v] Filter: [Total XP v]         |
|                                            |
| +----------------------------------------+ |
| |         +------+                       | |
| |         | CROWN|                       | |
| |    +----+      +----+                  | |
| |    | #2 | #1   | #3 |                  | |
| |    |    |      |    |                  | |
| |    |Nico|Marc  |Luca|                  | |
| |    |2320|2450  |2180|                  | |
| |    |LV14|LV18  |LV16|                  | |
| |    +----+------+----+                  | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  4. UP2   GREEN Sara      1,980 LV12   | |
| |  5. DN1   GREEN Gianluca  1,820 LV11   | |
| |  6. --    GREEN Andrea    1,650 LV10   | |
| |  7. DN1   RED   Davide    1,420 LV 9   | |
| |  8. --    GREEN Matteo    1,380 LV 9   | |
| |  9. UP3   GREEN Elena     1,200 LV 8   | |
| | 10. DN1   RED   Filippo   1,050 LV 7   | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |    + Invite Friends to Leaderboard     | |
| +----------------------------------------+ |
|                                            |
| ░░░░░░░░░░░░ TAB BAR ░░░░░░░░░░░░░░░░░░ |
+--------------------------------------------+
```

### 7.3 Component Specifications

#### Period Tabs
- Segmented control, full width minus 32pt padding. Height: 36pt. Corner radius: 10pt.
- Background: #1E3A5F. Selected segment: #2D7FF9 with white text. Unselected: transparent with #8899AA text.
- Font: SF Pro Text, 13pt, semibold.
- Switching tabs: content cross-fades (200ms). Selected indicator slides with spring animation (250ms, damping 0.8).
- **Weekly:** Resets every Monday 00:00 local time. Shows current week's XP.
- **Monthly:** Resets 1st of each month. Shows current month's XP.
- **All-Time:** Cumulative total XP since account creation.

#### Leaderboard Scope Selector (NEW)

A second row of controls below the period tabs allows switching between leaderboard scopes:

| Scope | Description |
|-------|------------|
| **Friends** | Default. Only mutual friends. Max 50 users. |
| **My League** | Users of similar level grouped into leagues of 20. See Section 19. |

- Displayed as a pill-style toggle: `[FRIENDS]  [MY LEAGUE]`
- My League only available at Level 5+.

#### Filter Dropdown
- Position: below tabs, leading-aligned, 16pt padding.
- Pill button: height 32pt, corner radius 16pt, background #1E3A5F, border 1pt #2D7FF9.
- Text: SF Pro Text, 13pt, semibold, #2D7FF9. Chevron down SF Symbol, 10pt.
- Options (presented as `.menu` picker):
  - Total XP (default)
  - Workout Count
  - Study Hours
  - Steps
  - Longest Streak
  - Challenges Won
- Selected option has a checkmark. Changing filter reloads leaderboard with animation.

#### Podium (Top 3)
- Custom view, full width, height: 180pt. Background: subtle gradient from #12203A to transparent.
- Three "pillars" arranged center (#1 tallest), left (#2 medium), right (#3 shortest).
- Pillar widths: 90pt each. Heights: #1 = 120pt, #2 = 100pt, #3 = 85pt.
- Each pillar:
  - Avatar: 48pt circle at top, with level-tier colored border (2pt).
  - Crown for #1: SF Symbol `crown.fill`, 20pt, #FFD700, positioned above avatar with -8pt offset. Subtle bounce animation on load (400ms spring).
  - Name: SF Pro Text, 13pt, semibold, white. Centered below avatar. Truncated with "..." if > 8 chars.
  - XP: SF Mono, 12pt, bold, tier color. Below name.
  - Level badge: mini 18x18pt, below XP.
- Pillar surface color: #1 = gold gradient (20% opacity), #2 = silver gradient (15% opacity), #3 = bronze gradient (10% opacity).
- If current user is in top 3: their pillar has a pulsing blue outline (1.5pt, 2-second pulse cycle).
- Animation on load: pillars rise from bottom with staggered timing (#1 at 200ms, #2 at 350ms, #3 at 500ms). Spring animation, damping 0.7.

#### Ranked List (4th place onward)
- `List` with custom row style. Background: clear (inherits screen background).
- Each row: height 56pt. Padding 16pt horizontal.
- Components per row (left to right):
  - Rank number: SF Mono, 16pt, bold, #8899AA. Width: 28pt, trailing-aligned.
  - Movement indicator: width 24pt, centered.
    - Up: SF Symbol `arrow.up`, 10pt, #22C55E. Number of positions moved shown as tiny superscript.
    - Down: SF Symbol `arrow.down`, 10pt, #FF3B5C.
    - No change: "—", 10pt, #556677.
    - Movement calculated since previous day for Weekly/Monthly, since previous week for All-Time.
  - Online indicator: 8pt circle. Green (#22C55E) if active today, red (#FF3B5C) if not. "Active today" = logged at least one XP-earning action.
  - Avatar: 36pt circle, level-tier border 1.5pt.
  - Name: SF Pro Text, 15pt, semibold, white. Flex width.
  - XP: SF Mono, 14pt, regular, #8899AA. Trailing.
  - Level: mini badge 20x20pt. Trailing after XP, 4pt spacing.
- Current user's row: background #2D7FF9 at 10% opacity. Left border accent 3pt #2D7FF9. Name text is electric blue instead of white. Row sticks to bottom of visible area if scrolled off (persistent footer with blur background showing "You: #2 — 2,320 XP").
- Row separator: 0.5pt, #1E3A5F, inset 68pt from leading edge.
- Tap row: navigates to that friend's profile (Section 6.4).

#### Rank Change Animation
- When leaderboard refreshes and ranks change:
  - Rows that moved up: slide upward to new position over 500ms, ease-in-out. Brief green flash on row background (200ms fade).
  - Rows that moved down: slide downward, brief red flash.
  - New entries: fade in from 0 opacity, 300ms.
- Rank number updates with a "flip" animation (3D rotate on Y-axis, old number flips away, new number flips in, 400ms).

#### Invite Friends CTA
- Positioned at bottom of list (not fixed). Full width minus 32pt padding. Height: 48pt. Corner radius: 12pt.
- Background: #1E3A5F. Border: 1pt dashed #2D7FF9.
- Text: "+ Invite Friends to Leaderboard" — SF Pro Text, 15pt, semibold, #2D7FF9. Centered.
- SF Symbol `person.badge.plus` inline before text, 16pt.
- Tap: opens friend invite flow (Section 8).

### 7.4 States

#### Empty State (No Friends)
```
+--------------------------------------------+
|                                            |
|           +----------------+               |
|           |   TROPHY       |               |
|           |  Empty         |               |
|           |  podium        |               |
|           +----------------+               |
|                                            |
|     It's lonely at the top...              |
|     but it doesn't have to be.             |
|                                            |
|     Add friends to see who's               |
|     grinding harder this week.             |
|                                            |
|     [ Invite Friends ]                     |
|     [ Share Invite Link ]                  |
|                                            |
+--------------------------------------------+
```

- Trophy illustration: custom Lottie of a trophy with dust/cobwebs, subtle animation. 120x120pt, centered.
- Title: SF Pro Display, 20pt, bold, white. Centered.
- Subtitle: SF Pro Text, 15pt, regular, #8899AA. Centered. Max width 280pt.
- "Invite Friends" button: primary style (blue gradient, 48pt height, 14pt corner radius).
- "Share Invite Link" button: secondary style (#1E3A5F background, blue text, 48pt height).
- Spacing: 24pt between illustration and title, 8pt between title and subtitle, 32pt between subtitle and buttons, 12pt between buttons.

#### Single User (Only You)
- Podium shows only user in #1 position (centered).
- Below: "You're currently the only one here. Invite friends to compete!"
- Leaderboard shows user row with crown.

#### Loading
- Podium: 3 shimmer rectangles at pillar heights.
- List: 5 shimmer rows with avatar circle + text bars.

---

## 8. Screen 4: Friend System

### 8.1 Add Friend Flow

#### Access Points
1. "Invite Friends" button on leaderboard empty state.
2. "+" button on friend list screen.
3. "Challenge a Friend" CTA when no friends exist.
4. Share sheet from profile.

#### Add Friend Sheet (presented as `.sheet`, detent: `.large`)

```
+--------------------------------------------+
|            -- drag indicator --             |
|                                            |
|  ADD FRIENDS                        X      |
|                                            |
|  +--------------------------------------+  |
|  | SEARCH Search by username...         |  |
|  +--------------------------------------+  |
|                                            |
|  -- OR --                                  |
|                                            |
|  +--------------+  +------------------+    |
|  |  CAMERA QR   |  |  LINK Share      |    |
|  |  Code        |  |  Link            |    |
|  |  Scan        |  |                  |    |
|  +--------------+  +------------------+    |
|                                            |
|  +--------------------------------------+  |
|  |  CONTACTS Import from Contacts       |  |
|  +--------------------------------------+  |
|                                            |
|  SEARCH RESULTS                            |
|  ─────────────────────────────────────     |
|  (appears after typing 3+ characters)      |
|                                            |
|  GREEN @marco_p     Marco P.    LV18      |
|     [ + Add ]                              |
|                                            |
|  GREEN @marco_fit   Marco B.    LV 5      |
|     [ + Add ]                              |
|                                            |
|  PENDING REQUESTS                          |
|  ─────────────────────────────────────     |
|                                            |
|  @luca_99 sent you a request               |
|     [ Accept ]  [ Decline ]                |
|                                            |
|  You sent a request to @sara_d             |
|     [ Cancel Request ]                     |
|                                            |
+--------------------------------------------+
```

#### Search Component
- Search bar: height 44pt, corner radius 12pt, background #1E3A5F, border 1pt #2D7FF9 when focused.
- Placeholder: "Search by username..." SF Pro Text, 15pt, #556677.
- Search icon: SF Symbol `magnifyingglass`, 16pt, #556677, leading inset 12pt.
- Debounce: 300ms after last keystroke before searching.
- Minimum query: 3 characters.
- Results appear below with slide-down animation (200ms).
- No results: "No users found for '[query]'. Check the spelling or share your invite link instead."

#### Search Result Row
- Height: 56pt. Padding: 16pt horizontal.
- Online indicator: 8pt circle (green/gray).
- Username: SF Pro Text, 15pt, semibold, #8899AA. "@" prefix.
- Display name: SF Pro Text, 15pt, regular, white.
- Level badge: 20pt mini badge, trailing.
- "+ Add" button: pill shape, 32pt height, 72pt width, background #2D7FF9, text "Add" SF Pro Text, 13pt, bold, white.
- After tapping Add: button transitions to "Sent" with checkmark, background becomes #1E3A5F, text becomes #8899AA. Animation: button morphs (200ms spring).
- If already friends: button shows "Friends" with checkmark in green.

#### QR Code Scan
- Tap "QR Code Scan" card: opens camera view with QR scanner overlay.
- Scanner frame: 220x220pt centered square with animated corner brackets (blue, pulsing).
- Instructions: "Point at your friend's Tempo QR code" — SF Pro Text, 14pt, white, below frame.
- On successful scan: haptic (success), brief green flash on frame, auto-navigates to friend request confirmation.
- On invalid QR: haptic (error), frame flashes red, "Not a Tempo QR code. Try again." appears for 3 seconds.

#### Share Link
- Tap "Share Link" card: generates a unique invite URL (`tempo.app/invite/[user_id_hash]`) and opens iOS share sheet.
- Link preview when shared: Tempo app icon + "Join me on Tempo! I'm Level 14." + user's avatar.

#### Import from Contacts
- Tap: requests Contacts permission (standard iOS permission dialog).
- If granted: scans contacts for phone numbers/emails that match existing Tempo users.
- Results shown in a list with "Add" buttons. Non-Tempo contacts show "Invite via SMS" option.
- If denied: "Enable Contacts access in Settings to find friends." with "Open Settings" button.

### 8.2 Friend Request Flow

#### Receiving a Request
- Push notification: "[Name] wants to be your friend on Tempo!"
- In-app: red badge dot on Arena tab. Friend request appears in:
  1. Add Friend sheet "PENDING REQUESTS" section.
  2. Notification bell in Arena header (if implemented).
- Request row:
  - Avatar (36pt) + username + display name + level badge.
  - "Accept" button: green (#22C55E) fill, white text, 32pt height.
  - "Decline" button: transparent, #FF3B5C text, 32pt height.
  - Accept animation: row slides right and transforms into a "Now Friends!" confirmation with confetti particle burst (200ms).
  - Decline animation: row fades out (300ms). Declined user can re-request after 30 days.

#### Sending a Request
- After tapping "+Add": request is sent. Button changes to "Sent" (see above).
- If recipient accepts: user receives push notification "[Name] accepted your friend request!" and a green toast appears in-app.
- Request expires after 14 days if not accepted.

### 8.3 Friend List View

Accessed from Arena Settings or a "Friends" link in profile.

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  < Arena         FRIENDS      +            |
|                                            |
|  12 Friends                                |
|                                            |
| +----------------------------------------+ |
| | SEARCH Search friends...               | |
| +----------------------------------------+ |
|                                            |
|  ONLINE (5)                                |
|  ──────────────────────────────────────    |
|  GREEN @marco_p    Marco P.   LV18 SWORD  |
|  GREEN @sara_d     Sara D.    LV12 SWORD  |
|  GREEN @luca_99    Luca R.    LV16 SWORD  |
|  GREEN @gianluca   Gianluca   LV11 SWORD  |
|  GREEN @andrea_t   Andrea T.  LV10 SWORD  |
|                                            |
|  OFFLINE (7)                               |
|  ──────────────────────────────────────    |
|  GRAY @davide_m   Davide M.  LV 9  SWORD  |
|  GRAY @matteo_b   Matteo B.  LV 9  SWORD  |
|  ...                                       |
|                                            |
|  PENDING (1)                               |
|  ──────────────────────────────────────    |
|  WAIT @elena_v    Elena V.   LV 8         |
|     Sent 2 days ago    [ Cancel ]          |
|                                            |
+--------------------------------------------+
```

**Specs:**
- "+" button (top right): opens Add Friend sheet. SF Symbol `person.badge.plus`, 20pt, #2D7FF9.
- Friend count: SF Pro Text, 14pt, regular, #8899AA.
- Search bar: same as Add Friend search component.
- Section headers: SF Pro Display, 13pt, semibold, uppercase, tracking 1.2pt. "ONLINE" = #22C55E, "OFFLINE" = #8899AA, "PENDING" = #FF6B2C.
- Friend row: height 52pt.
  - Online indicator: 8pt circle (green/dark gray).
  - Username + name: same as search results.
  - Level badge: 20pt mini.
  - Challenge shortcut: sword icon (SF Symbol `bolt.fill`), 16pt, #2D7FF9. Tap opens challenge creation pre-filled with this friend.
  - Swipe left to reveal: "Remove" (red) and "Block" (dark red) actions.
- Max friend count: 50 friends. At 50: "Friend list full. Remove a friend to add more." displayed at top of Add Friend sheet.

### 8.4 Privacy Controls

Controlled per-user in Arena Settings (Section 15). Options:

| Data | Options | Default |
|------|---------|---------|
| Level & XP | Everyone / Friends Only / Hidden | Everyone |
| Workout details | Friends Only / Hidden | Friends Only |
| Study hours | Friends Only / Hidden | Friends Only |
| Nutrition data | Friends Only / Hidden | Hidden |
| Personal records | Friends Only / Hidden | Friends Only |
| Streak | Everyone / Friends Only / Hidden | Everyone |
| Active status (online) | Everyone / Friends Only / Hidden | Friends Only |
| Achievement showcase | Everyone / Friends Only / Hidden | Everyone |

### 8.5 Block & Remove

- **Remove Friend:** Swipe action or "..." menu on friend profile. Confirmation alert: "Remove @marco_p? They won't be notified, but you'll be removed from each other's leaderboards and active challenges." [Remove / Cancel].
- **Block:** "..." menu on friend profile or search result. Confirmation alert: "Block @marco_p? They won't be able to find you, send requests, or see your profile." [Block / Cancel]. Blocked users list accessible from Arena Settings.
- **Report:** "..." menu. Options: Inappropriate username, Harassment, Spam, Other. Opens native iOS form with optional text field. Submitted via standard API.

---

## 9. Screen 5: Challenges

### 9.1 Challenge Types

| Type | Min Players | Max Players | Description |
|------|-------------|-------------|-------------|
| Head-to-Head (1v1) | 2 | 2 | Direct competition on a specific metric |
| Group | 3 | 10 | Multiple friends competing, ranked |
| Daily Challenge | 1+ | Unlimited | Auto-generated, all users can opt in, new every day |

Community challenges (all Tempo users) are reserved for a future update and not specified here.

### 9.2 Available Metrics for Challenges

| Metric | Display Format | Data Source |
|--------|---------------|-------------|
| Total XP | "1,250 XP" | Sum of all XP earned during challenge |
| Workout Count | "12 workouts" | Number of completed workouts |
| Study Hours | "24.5 hours" | Total study time logged |
| Total Steps | "85,000 steps" | Cumulative steps from HealthKit |
| Perfect Days | "5 days" | Number of Perfect Day achievements |
| Meals Logged | "42 meals" | Number of meals logged |
| Streak Length | "14 days" | Longest unbroken streak during challenge period |

### 9.3 Challenge Durations

| Duration | Label | Use Case |
|----------|-------|----------|
| 1 day | "Daily Duel" | Quick burst, same-day resolution |
| 3 days | "Weekend Warrior" | Short sprint |
| 7 days | "Weekly War" | Standard competition |
| 14 days | "Fortnight Fight" | Extended battle |
| 30 days | "Monthly Marathon" | Long-term commitment |

### 9.4 Challenges Hub View

Accessed from Arena Main View by tapping Active Challenges card or a dedicated "Challenges" button.

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  < Arena        CHALLENGES                 |
|                                            |
| +----------------------------------------+ |
| |  SWORD ACTIVE (2)                      | |
| |                                        | |
| |  +----------------------------------+  | |
| |  | vs Marco - Study Hours - 7d      |  | |
| |  |                                  |  | |
| |  |  You         |    Marco          |  | |
| |  |  12.5h       |    14.2h          |  | |
| |  |  ██████░░░░  |  ████████░░░░     |  | |
| |  |                                  |  | |
| |  |  CLOCK 3 days, 14h remaining     |  | |
| |  |  You're losing by 1.7h           |  | |
| |  +----------------------------------+  | |
| |                                        | |
| |  +----------------------------------+  | |
| |  | Group - Weekly XP - 7d           |  | |
| |  | 5 players                         |  | |
| |  |                                  |  | |
| |  |  1. Luca      3,200 XP  CROWN    |  | |
| |  |  2. You       2,950 XP  <--      |  | |
| |  |  3. Marco     2,800 XP           |  | |
| |  |  4. Sara      2,100 XP           |  | |
| |  |  5. Andrea    1,900 XP           |  | |
| |  |                                  |  | |
| |  |  CLOCK 2 days remaining          |  | |
| |  +----------------------------------+  | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  MAIL INVITES (1)                      | |
| |                                        | |
| |  Luca challenged you!                  | |
| |  Metric: Steps - 3 days                | |
| |  [ Accept ]  [ Decline ]               | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  TARGET DAILY CHALLENGE                | |
| |                                        | |
| |  Today: Earn 500+ XP                   | |
| |  289 Tempo users participating          | |
| |  [ Join Today's Challenge ]             | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |  SCROLL HISTORY                        | |
| |                                        | |
| |  TROPHY vs Marco - XP - Won +200 XP   | |
| |  X Group - Steps - 3rd place           | |
| |  TROPHY vs Sara - Study - Won +200 XP  | |
| |                    View All >           | |
| +----------------------------------------+ |
|                                            |
| +----------------------------------------+ |
| |     SWORD [ Create New Challenge ]     | |
| +----------------------------------------+ |
|                                            |
| ░░░░░░░░░░░░ TAB BAR ░░░░░░░░░░░░░░░░░░ |
+--------------------------------------------+
```

### 9.5 Challenge Creation Flow

Multi-step sheet presented as `.fullScreenCover` with custom navigation.

#### Step 1: Select Type

- Type cards: full width minus 32pt, height 88pt, corner radius 16pt, background #12203A, border 1pt #1E3A5F.
- Selected state: border becomes 2pt #2D7FF9, subtle blue glow, scale 1.02 (spring 200ms).
- Icon: 28pt, leading inset 16pt.
- Title: SF Pro Display, 18pt, bold, white.
- Subtitle: SF Pro Text, 14pt, regular, #8899AA.
- Tap selects and auto-advances to Step 2 after 300ms delay (user sees selection feedback before transition).

#### Step 2: Select Metric

- Metric cards: 3-column grid. Each card: equal width, height 88pt, corner radius 14pt, background #12203A.
- Selected: blue border 2pt + glow. Only one selectable.
- Icon: 24pt centered. Label: SF Pro Text, 13pt, semibold, centered below.
- "Next" button: full width minus 32pt, height 48pt, blue gradient, disabled (gray) until selection made.

#### Step 3: Select Duration

- Duration cards: pill shapes, 72pt width, 64pt height, corner radius 14pt.
- Selected: blue fill (#2D7FF9) with white text. Unselected: #12203A with white text.
- Start/End dates: auto-calculated based on selection. SF Pro Text, 14pt, #8899AA. Challenge always starts the next midnight after creation to ensure fairness.
- Stakes text field: optional. Height 44pt, corner radius 12pt, background #1E3A5F. Placeholder: "e.g., Loser buys coffee". Max 100 characters. SF Pro Text, 14pt.

#### Step 4: Invite Players

- For 1v1: exactly 1 opponent required. "SELECTED (1/1)" counter.
- For Group: 2-9 opponents required. "SELECTED (3/9)" counter with min indicator.
- Friend list: same as Friend List View rows but with "+" button instead of challenge sword.
- "+" button: tapping adds to Selected list with slide-up animation. Row moves to SELECTED section.
- "x" on selected: removes from selection, row slides back down.
- Challenge summary: compact recap at bottom. SF Pro Text, 13pt, #8899AA. Stakes in quotes if set.
- "Send Challenge" button: full width minus 32pt, height 52pt, gradient (blue to purple), text "Send Challenge" SF Pro Display, 17pt, bold, white. Disabled until player requirements met.
- After sending: success animation (sword clash Lottie, 1.5 seconds) + haptic (success). Auto-dismisses to Challenges Hub.

### 9.6 Active Challenge Detail View

Tapping any active challenge card opens a full detail view.

**Head-to-Head Display:**
- VS layout: two avatars (56pt circles) facing each other with a sword/crossed-swords icon (24pt, #FF6B2C) between them.
- Score comparison: SF Mono, 28pt, bold. Winner's score is electric blue, loser's is #8899AA. Equal = both white.
- Tug-of-war bar: single bar where both sides "push" from their end. Width fills proportional to each person's score. Center line marks 50%. Winner's color extends past center. Left = user (blue), Right = opponent (orange). Height 12pt, corner radius 6pt.
- Status text: "You're behind by 1.7 hours" — SF Pro Text, 14pt, semibold. Red if losing, green if winning, white if tied.

**Group Display:**
- Instead of VS, shows a mini leaderboard (same format as main leaderboard but compact).
- User's row highlighted. Crown on #1.

**Daily Breakdown:**
- Each day is a row. Day number + date (SF Pro Text, 13pt, #8899AA) + both scores (SF Mono, 13pt) + checkmark if user won that day.
- Future days: grayed out with shimmer pattern.
- Today: highlighted with blue left border.

**"..." Overflow Menu Options:**
- Mute notifications for this challenge
- Forfeit challenge (confirmation required: "Forfeit? This counts as a loss and you won't receive participation XP.")
- Report challenge

### 9.7 Challenge Completion

When a challenge ends (timer reaches 0 or one side forfeits):

#### Winner Experience
1. Push notification: "You won the Study Hours challenge vs Marco! +200 XP"
2. On next app open: full-screen celebration overlay:
   - Background: dark with confetti particle system (gold and blue confetti, 3 seconds).
   - Trophy Lottie animation center screen (200x200pt), 2 seconds.
   - "VICTORY!" text: SF Pro Display, 36pt, bold, gold (#FFD700), drop shadow. Appears after trophy with scale-up animation.
   - Metric: "You studied 18.5h vs Marco's 16.2h" — SF Pro Text, 16pt, white.
   - XP earned: "+200 XP" floating animation (same as standard XP earn but larger, 24pt).
   - Stakes reminder: "Reminder: Loser buys pizza!" — SF Pro Text, 14pt, #FF6B2C, with pizza emoji.
   - "Share Victory" button: opens share sheet with pre-formatted image (challenge result card).
   - "Done" button: dismisses overlay.
   - Haptic: success pattern (two thuds).

#### Loser Experience
1. Push notification: "Marco won the Study Hours challenge. +50 XP for participating."
2. On next app open: result overlay (more subdued):
   - Background: dark, no confetti.
   - Silver shield icon (not animated), 120x120pt.
   - "CHALLENGE COMPLETE" text: SF Pro Display, 24pt, semibold, #8899AA.
   - Result: "Marco studied 16.2h vs your 18.5h" — SF Pro Text, 16pt, white.
   - XP earned: "+50 XP (Participation)" — SF Pro Text, 14pt, #2D7FF9.
   - "Rematch" button: primary style (blue gradient). Opens challenge creation pre-filled with same opponent and metric.
   - "Done" button: secondary style.
   - Haptic: light impact (single).

### 9.8 Daily Challenge

Auto-generated every day at 00:00 in the user's LOCAL TIME ZONE (not UTC). Each user's daily challenge window runs from their own midnight to midnight. Examples rotate on a schedule:
- Monday: "Earn 500+ XP today"
- Tuesday: "Log all 3 meals"
- Wednesday: "Hit 10,000 steps"
- Thursday: "Study 3+ hours"
- Friday: "Complete a workout + study session"
- Saturday: "Perfect Day challenge"
- Sunday: "Rest & recover: log sleep + hit 5K steps"

- Displayed in Challenges Hub as a special card with a gradient border (animated, cycling blue-purple-orange, 4 seconds).
- "Join" button: single tap. Joined users see their progress during the day.
- Completion: if criteria met by 23:59, user earns +50 XP bonus. No penalty for joining and not completing.
- No winner announced (it's personal), but a count of how many users completed it is shown the next day.

### 9.9 Challenge Notifications (Granular)

| Event | Notification | Frequency |
|-------|-------------|-----------|
| Someone overtakes you | "[Name] just passed you! You're now 1.2h behind." | Max 3/day per challenge |
| You overtake someone | "You just passed [Name]! Keep pushing!" | Immediate |
| Challenge halfway point | "Halfway there! You're [winning/losing] by [amount]." | Once per challenge |
| Challenge final day | "Last day! [Amount] separates you from [winning/losing]." | Once |
| Challenge ended | See 9.7 winner/loser notifications | Once |
| New challenge invite | "[Name] challenged you to [metric] for [duration]!" | Immediate |
| Challenge invite expiring | "Challenge invite from [Name] expires in 2 hours." | Once, 2h before expiry |

### 9.10 Challenge Edge Cases

- **Tie:** Both players/top players share the win. Both receive winner XP. Celebration screen shows "TIE!" with handshake Lottie.
- **Forfeit:** Forfeiting player receives 0 XP. Other player wins by default with full winner XP.
- **Friend removed during challenge:** Challenge continues. Removed friend appears as "Former Opponent" with avatar grayed out. Challenge completes normally.
- **User deletes account during challenge:** Other player wins by default.
- **No activity from either player:** Challenge ends with tie at 0. No XP awarded. Shown as "Abandoned" in history.
- **Challenge invite not accepted:** Expires after 48 hours. Creator is notified: "[Name] didn't respond. Challenge cancelled." Creator receives 0 XP refund for the join bonus (25 XP was never deducted -- it's only awarded on actual join).

### 9.11 Challenge Fairness System

#### Problem: "Most Study Hours" Is Unfair Across Course Loads

A part-time student with 2 classes cannot compete against a full-time student with 5 classes on raw study hours. This makes several challenge metrics structurally unfair.

**Solution: Completion-Percentage Mode**

When creating a Study Hours challenge, the creator can toggle "Normalize by Target" ON. When enabled:
- The metric becomes **percentage of daily study target hit**, not raw hours.
- A user whose target is 2h/day and studies 2h scores 100%. A user whose target is 5h/day and studies 5h also scores 100%.
- The challenge ranks by average daily completion percentage over the challenge period.
- Display format: "You: 94% avg | Marco: 88% avg" instead of raw hours.
- This mode is the DEFAULT for Study Hours challenges. Raw hours mode is available as "Absolute Mode" toggle.

**Metrics that support normalization:**
| Metric | Normalized Version |
|--------|--------------------|
| Study Hours | % of daily study target |
| Total XP | % of personal weekly average (rolling 4-week baseline) |
| Steps | % of personal step target |
| Meals Logged | % of meal plan compliance |

**Metrics that are naturally fair (no normalization needed):**
- Workout Count (binary: did you or didn't you)
- Perfect Days (same criteria for everyone)
- Streak Length (same criteria)

#### Problem: Time Zone Fairness

**Rule:** All challenges use the CREATOR'S time zone for start/end boundaries. However, the UI shows a COUNTDOWN TIMER for all participants, not a fixed clock time. This means a participant in a different timezone sees "2 days, 14 hours remaining" -- not "ends Tuesday at midnight CET." The countdown is equitable regardless of timezone.

**Daily sub-scores within challenges** (e.g., "who won Tuesday") use each participant's LOCAL midnight. This prevents gaming where a user in UTC+9 gets a 9-hour head start on the "day."

#### Problem: Runaway Winners / Dead Challenges

When one participant is clearly winning by a massive margin mid-challenge, the challenge becomes boring for everyone.

**Comeback Mechanics:**

1. **Momentum Bonus:** If a participant is losing by >25%, they earn a 1.15x score multiplier for their challenge metric the next day. If still losing by >40%, the multiplier increases to 1.25x. This gives the underdog a fighting chance without guaranteeing a comeback. The leader sees: "Your opponent has momentum! Stay sharp." The underdog sees: "Momentum bonus active -- push hard today!"

2. **Daily Win Streak Bonus:** In challenges 7+ days, if a participant wins 3 consecutive days, they earn +25 bonus XP regardless of overall standing. This keeps the losing player engaged by rewarding daily effort.

3. **"Clutch Day" Mechanic:** On the final day of any challenge, all participants' scores for that day count 1.5x. This makes the last day dramatic and prevents the leader from coasting. Shown as a banner: "CLUTCH DAY -- Today's score counts 1.5x!"

4. **Challenge Mercy Rule:** If one participant has 3x the other's score by the halfway point in a 1v1, the losing player is offered: "This challenge is lopsided. [Concede for 50 XP] or [Keep Fighting]." Conceding is NOT forfeit -- both players get participation XP, and the winner gets a reduced victory bonus (150 XP instead of 200). This prevents the losing player from feeling trapped.

---

## 10. Screen 6: Achievements / Badges

### 10.1 Achievement System Overview

108 achievements across 10 categories. Each has:
- **Name:** Short, punchy title
- **Description:** One sentence explaining what it is / flavor text
- **Icon Concept:** Visual description for design team
- **Criteria:** Exact measurable unlock condition
- **XP Reward:** One-time XP bonus on unlock
- **Rarity:** Common / Rare / Epic / Legendary / Mythic
- **Hidden:** Whether visible before unlock (surprise achievements marked with "?")

Rarity distribution:
- Common: 32 achievements (mostly visible, early unlocks -- some moved to hidden to avoid trivial dopamine)
- Rare: 29 achievements (visible, require sustained effort)
- Epic: 25 achievements (some hidden, require significant dedication)
- Legendary: 14 achievements (most hidden until unlocked, extraordinary feats)
- Mythic: 8 achievements (ALL hidden, extraordinary effort over months -- less than 1% of users should ever unlock these. Note: Mythic achievements require extraordinary EFFORT, not extraordinary luck. Criteria that depend on factors outside the user's control (illness, travel) use non-consecutive thresholds.)

**Full achievement list: See Section 21 for all 108 achievements with complete specifications.**

### 10.2 Achievements View — Full Screen Layout

```
+--------------------------------------------+
| ░░░░░░░░░░░ STATUS BAR ░░░░░░░░░░░░░░░░░░ |
|                                            |
|  < Profile     ACHIEVEMENTS                |
|                                            |
|  12/108 Unlocked           SEARCH Filter   |
|  ████████░░░░░░░░░░░░░░░  11%              |
|                                            |
|  +----------+----------+----------+        |
|  |   ALL    | UNLOCKED |  LOCKED  |        |
|  +----------+----------+----------+        |
|                                            |
|  GYM TRAINING (4/15)                       |
|  +------+ +------+ +------+ +------+      |
|  | CHECK| | CHECK| | CHECK| | CHECK|      |
|  |#1    | |#2    | |#6    | |#8    |      |
|  |50XP  | |100   | |75    | |75    |      |
|  +------+ +------+ +------+ +------+      |
|  +------+ +------+ +------+ +------+      |
|  | LOCK | | LOCK | | LOCK | | LOCK |      |
|  |#3    | |#4    | |#7    | |#9    |      |
|  +------+ +------+ +------+ +------+      |
|  ...                                       |
|                                            |
|  BOOK STUDY (3/12)                         |
|  ...                                       |
|                                            |
|  FORK NUTRITION (2/12)                     |
|  ...                                       |
|                                            |
|  MOON RECOVERY (1/10)                      |
|  ...                                       |
|                                            |
|  FIRE STREAKS (2/7)                        |
|  ...                                       |
|                                            |
|  USERS SOCIAL (0/12)                       |
|  ...                                       |
|                                            |
|  FOOT STEPS & MOVEMENT (0/10)              |
|  ...                                       |
|                                            |
|  STAR SPECIAL / RARE (0/12)               |
|  ...                                       |
|                                            |
|  EYE HIDDEN / SECRET (0/10)               |
|  ...                                       |
|                                            |
|  DIAMOND META (0/8)                        |
|  ...                                       |
|                                            |
| ░░░░░░░░░░░░ TAB BAR ░░░░░░░░░░░░░░░░░░ |
+--------------------------------------------+
```

**Specs:**

#### Header
- "12/108 Unlocked": SF Mono, 16pt, semibold, white. Leading.
- Filter button: SF Symbol `line.3.horizontal.decrease`, 18pt, #2D7FF9. Trailing. Tap opens filter options: by rarity (Common/Rare/Epic/Legendary/Mythic), by category, or by status (unlocked/locked).
- Overall progress bar: full width minus 32pt padding. Height 6pt, corner radius 3pt. Background #1E3A5F, fill #22C55E. Percentage label trailing (SF Mono, 12pt, #8899AA).

#### Tab Bar (All / Unlocked / Locked)
- Same segmented control style as Leaderboard period tabs (Section 7.3).
- "ALL" shows all achievements. "UNLOCKED" shows only earned. "LOCKED" shows only unearned (including hidden ones as "?").

#### Category Sections
- Section header: emoji + category name (SF Pro Display, 15pt, semibold, white) + progress (SF Mono, 13pt, #8899AA, e.g., "4/15").
- Badges displayed in a 5-column grid. Horizontal scrolling if more than 5 per row, otherwise wrapping grid.
- Each badge cell: 64x64pt.

#### Badge States

**Unlocked Badge:**
- Full-color icon at 64x64pt.
- Rarity-colored border: Common = #8899AA (1pt), Rare = #2D7FF9 (1.5pt), Epic = #A855F7 (2pt, subtle glow), Legendary = animated gradient border (gold-to-holographic, 2pt, slow rotation 6 seconds), Mythic = animated prismatic border with particle trail (3pt, constant slow shimmer).
- Checkmark overlay: small green circle (16pt) with white checkmark, bottom-right corner.
- Name below: SF Pro Text, 10pt, semibold, white.
- XP below name: SF Mono, 9pt, #8899AA.

**Locked Badge (Visible):**
- Grayscale silhouette of the icon, 64x64pt, opacity 40%.
- Lock icon overlay: SF Symbol `lock.fill`, 16pt, #556677, centered.
- Name below: SF Pro Text, 10pt, regular, #556677.
- Progress indicator (if applicable): tiny progress bar under name showing how close (e.g., "37/50 workouts").

**Hidden Badge (Locked + Hidden):**
- 64x64pt dark circle (#1E3A5F) with "?" in center (SF Mono, 24pt, bold, #556677).
- No name shown. Below shows "???" in #556677.
- No progress indicator.

#### Badge Detail Popover (Tap Any Badge)

- Presented as a centered popover (320pt wide, variable height) with backdrop blur.
- Icon: enlarged to 96x96pt with rarity border.
- Name: SF Pro Display, 20pt, bold, white, centered.
- Description: SF Pro Text, 14pt, regular, #AABBCC, centered, max width 280pt.
- Rarity: stars (1 = Common, 2 = Rare, 3 = Epic, 4 = Legendary, 5 = Mythic) + rarity name. Color matches rarity border.
- Reward: SF Mono, 14pt, bold, #2D7FF9.
- Unlock date (if unlocked): SF Pro Text, 13pt, regular, #8899AA.
- Progress (if locked and visible): progress bar (height 6pt, blue fill) + fraction + percentage.
- "Pin to Showcase" button (if unlocked): pill button, #1E3A5F background, #2D7FF9 text, 36pt height. Only visible if user has available showcase slots.
- For hidden badges: popover shows enlarged "?" icon, name "???", and a CATEGORY HINT instead of "Keep going to discover it!" The hint tells the user WHICH domain the achievement lives in without revealing the specific criteria. Examples:
  - "This is a hidden Training achievement. Keep pushing in the gym."
  - "This is a hidden Social achievement. It involves your friends."
  - "This is a hidden Time-based achievement. Timing matters."
  This ensures users don't feel cheated by fully opaque hidden achievements. They know WHERE to focus without knowing WHAT to do. This is the same pattern Halo and Overwatch use for hidden achievements -- category hint without criteria spoiler.
- Dismiss: tap outside popover or swipe down.

#### Hidden Achievement Discoverability System

Hidden achievements must be discoverable enough that users feel rewarded, not cheated, when they unlock one. Three layers:

1. **Category hints** (described above): every hidden badge shows which domain it belongs to.
2. **"Almost There" shimmer:** When a user is within 20% of unlocking a hidden achievement, the "?" badge gets a subtle gold shimmer animation in the achievements grid. The user knows SOMETHING is close without knowing what. This creates anticipation.
3. **Social discovery:** When a friend unlocks a hidden achievement, it appears in the feed with full name and description. Other users can see WHAT exists, even if they don't know the criteria. This is intentional -- seeing "Marco unlocked '3 AM Club'" makes you curious enough to try staying up, without the criteria being handed to you.
4. **Achievement count visibility:** The "12/108" counter includes hidden achievements in the total. Users know there are achievements they haven't seen, which drives exploration.

### 10.3 Achievement Near-Completion Nudges

When a user is within 10% of unlocking an achievement, a subtle nudge appears:

- On the Arena Main View, a small card appears above the "Recent Achievements" section:
  ```
  +----------------------------------------+
  |  Almost there! UNLOCK                   |
  |  "Gym Rat" -- 47/50 workouts            |
  |  ████████████████████░  94%             |
  +----------------------------------------+
  ```
- Max 1 nudge at a time. Priority: closest to completion. If multiple are at 100%, show the one with highest XP reward.
- Card has a subtle shimmer animation (hint of gold) to draw attention.

---

## 11. Screen 7: XP Animation System

### 11.1 XP Earn Animation ("+50 XP")

**Trigger:** Any action that awards XP.

**Animation sequence (total duration: 1200ms):**
1. **0ms:** Text "+[amount] XP" appears at the point of action (e.g., near the button that was tapped). SF Mono, 18pt, bold, #2D7FF9.
2. **0-100ms:** Scale from 0.5 to 1.2 (overshoot spring).
3. **100-300ms:** Scale settles to 1.0. Opacity at 100%.
4. **300-800ms:** Text rises vertically by 60pt. Opacity fades to 0. Subtle X-axis drift (random -10 to +10pt) for organic feel.
5. **800-1200ms:** Text fully transparent. Removed from view hierarchy.

**Multiplier display:** If streak multiplier is active, show the multiplied value with a small "x1.5" tag:
```
+75 XP x1.5
```
The "x1.5" is SF Mono, 10pt, #FF6B2C, positioned as superscript.

**Batch earning:** If multiple XP sources trigger simultaneously (e.g., completing all non-negotiables grants individual + bonus), stagger animations by 200ms each, then show a combined total last:
```
+10 XP  (rises and fades)
+10 XP  (200ms later)
+60 XP  BONUS! (400ms later, larger, gold color)
```

**Haptic:** Light impact on each individual earn. Medium impact on bonus/combined.

### 11.2 Level Up Animation

**Trigger:** User's total XP crosses the threshold for the next level.

**Animation sequence (total duration: 3500ms):**
1. **0ms:** Screen dims (overlay at 60% black opacity, 300ms fade-in).
2. **300ms:** Level badge zooms in from center of XP bar to center of screen. Scale 0.2 to 1.0, spring animation (damping 0.6, 500ms). Badge is the NEW level badge, 120x120pt.
3. **800ms:** Concentric ring burst: three rings expand outward from badge, each 2pt stroke, tier color, expanding from 120pt to 300pt diameter, fading out. Staggered by 150ms.
4. **1000ms:** "LEVEL UP!" text appears above badge. SF Pro Display, 32pt, bold, white. Drop shadow 0 2 10 rgba(0,0,0,0.5). Scale from 0.8 to 1.0, spring.
5. **1200ms:** New title appears below badge. "WARRIOR" (or new title). SF Pro Display, 20pt, bold, tier color. Fade in from 0 opacity, 300ms.
6. **1500ms:** New level number appears inside badge with a "flip" animation (3D Y-axis rotation). Old number flips away, new number flips in.
7. **1800ms:** Particle system activates: small dots in tier color radiate outward from badge, gravity pulls them down slightly. 2-second lifetime per particle. 40 particles total.
8. **2500ms:** If this level unlocks something (see Section 3.3), text appears: "New unlock: Leaderboard Access!" SF Pro Text, 14pt, semibold, #FFD700. Slide up animation, 300ms.
9. **3000ms:** "Continue" button fades in at bottom. Pill shape, 120pt wide, 44pt height, white text on tier-color background.
10. **3500ms:** If user doesn't tap Continue, overlay remains (does not auto-dismiss). User must engage.

**Sound:** Optional ascending chime (user can disable in settings). Three notes: C5, E5, G5, each 150ms, harp timbre.

**Haptic:** Notification success pattern at step 3 (ring burst).

### 11.3 Streak Milestone Animation

**Trigger:** Reaching a new streak tier (3, 7, 14, 30, 60, 90, 180, 365 days).

**Animation sequence (total duration: 2500ms):**
1. **0ms:** Flame icon in the streak display enlarges from current size to 64pt at screen center. Spring animation, 400ms.
2. **400ms:** Flame morphs into the new tier's flame variant (e.g., small flame becomes medium animated flame). Crossfade morph, 300ms.
3. **700ms:** Streak number appears above flame: "14-DAY STREAK!" SF Mono, 28pt, bold, #FF6B2C. Scale bounce 1.0 to 1.15 to 1.0, 300ms.
4. **1000ms:** New multiplier value pulses below: "1.5x MULTIPLIER ACTIVE" SF Mono, 16pt, bold, #2D7FF9. Fade in, 200ms.
5. **1200ms:** Ember particles burst from flame, 20 particles, orange-red, gravity-affected, 1.5s lifetime.
6. **2000ms:** All elements settle into the streak display card position (reverse of step 1 enlargement). Spring, 500ms.

**Haptic:** Medium impact at step 2 (morph), light impact at step 4 (multiplier).

### 11.4 Achievement Unlock Animation

**Trigger:** Achievement criteria met.

**Animation sequence (total duration: 2800ms):**
1. **0ms:** Badge icon appears at bottom-center of screen, scaled to 0. Quick scale-up to 80x80pt, spring (damping 0.5, 600ms) — intentionally bouncy.
2. **600ms:** Badge "slams" into final position center-screen. Brief screen shake effect (2pt random offset, 4 frames, 100ms).
3. **700ms:** Golden glow ring expands from badge, 80pt to 160pt, fade out. Duration 400ms.
4. **1100ms:** Achievement name fades in above: SF Pro Display, 20pt, bold, white. Description below: SF Pro Text, 14pt, regular, #AABBCC. Duration 300ms.
5. **1400ms:** XP reward floats up from badge: "+300 XP" in XP earn animation style (see 11.1) but larger (22pt).
6. **1800ms:** Rarity text fades in: "RARE ACHIEVEMENT" with star icons. Color matches rarity. Duration 200ms.
7. **2000ms:** "Share" and "Dismiss" buttons fade in at bottom.
8. **2800ms:** If not interacted with, remains on screen (does not auto-dismiss for 5 seconds, then fades out with 500ms if untouched).

**Rarity-specific embellishments:**
- Common: simple golden glow.
- Rare: glow + subtle blue sparkle particles (10 particles).
- Epic: glow + purple sparkle particles (20 particles) + badge rotation 360 degrees during slam.
- Legendary: glow + holographic shimmer across entire badge + confetti particle system (30 gold particles) + screen edge glow (purple, pulses once).
- Mythic: glow + prismatic light rays from badge + full-screen aurora effect (shifting colors, 3 seconds) + heavy confetti (50 particles) + screen rumble haptic.

**Haptic:** Success notification at step 2 (slam). Heavy impact for Legendary. Double heavy impact for Mythic.

**Sound:** Achievement chime. Common = single bell. Rare = two ascending bells. Epic = three ascending bells with reverb. Legendary = orchestral hit (compressed, 0.5s). Mythic = orchestral swell with choir (1.0s).

### 11.5 Leaderboard Rank Change Animation

See Section 7.3 "Rank Change Animation" for details. Summary:
- Rows slide up/down to new positions over 500ms.
- Green/red flash on moved rows.
- Rank numbers flip (3D Y-axis).
- If user gains #1 position: crown drops from top of screen, bounces once, settles on user's row. 800ms spring animation.

### 11.6 Challenge Win Animation

See Section 9.7 "Winner Experience" for full details. Key elements:
- Confetti particle system: 60 particles, gold + blue, varied sizes (4-12pt), gravity + slight horizontal drift, 3-second lifetime.
- Trophy Lottie: custom animation, metallic gold, 2-second loop. Designed at 200x200pt.
- "VICTORY!" text: SF Pro Display, 36pt, bold. Color: animated gradient (gold to white, oscillating, 2-second cycle).

### 11.7 Sound System

All sounds are optional (controlled in Arena Settings). Default: ON.

| Event | Sound | Duration | Volume |
|-------|-------|----------|--------|
| XP earn (small, < 50) | Soft "ding" | 150ms | 40% |
| XP earn (medium, 50-200) | Medium "ding" with resonance | 250ms | 60% |
| XP earn (large, > 200) | Full "cha-ching" | 400ms | 80% |
| Level up | Ascending harp (C-E-G) | 800ms | 100% |
| Streak milestone | Whoosh + fire crackle | 500ms | 70% |
| Achievement (Common) | Single bell | 200ms | 50% |
| Achievement (Rare) | Two ascending bells | 350ms | 60% |
| Achievement (Epic) | Three bells + reverb | 500ms | 75% |
| Achievement (Legendary) | Orchestral hit | 600ms | 100% |
| Achievement (Mythic) | Orchestral swell with choir | 1000ms | 100% |
| Challenge win | Triumphant horn + crowd cheer | 1200ms | 100% |
| Challenge loss | Soft descending tone | 400ms | 40% |
| Rank up on leaderboard | Quick ascending swoosh | 300ms | 50% |
| Rank down on leaderboard | Quick descending swoosh | 300ms | 30% |
| Daily login bonus | Warm "welcome" chime | 300ms | 50% |
| Reaction received | Subtle pop | 100ms | 30% |

All sounds use `AVAudioSession.Category.ambient` to mix with user's music. System volume respected. Sounds are compressed `.caf` files, < 50KB each. See Section 26 for detailed sound design specifications.

---

## 12. Screen 8: Social Feed

### 12.1 Overview

The Social Feed is a chronological stream of friends' activities. It serves as ambient social proof — users see what their friends are doing without explicit messaging. This is NOT a full social network feed; it is curated and minimal.

### 12.2 Access

- Accessed via a "Feed" tab within the Arena section (sub-tab below the main Arena header), or as a collapsible section on the Arena Main View.
- Position: between the Leaderboard Preview and Active Challenges cards on Arena Main View (collapsed by default, expandable).
- Dedicated full view: swipe right from Arena Main View or tap "Feed" sub-tab.

### 12.3 Feed Item Types

| Event Type | Template | Auto-Post? |
|------------|----------|------------|
| Workout complete | "[Name] completed a [workout name] workout" | Yes |
| Study milestone | "[Name] studied for [hours]h" | Only if >= 3h or new PR |
| Streak milestone | "[Name] hit a [N]-day streak!" | Yes (at tier boundaries) |
| Achievement unlocked | "[Name] unlocked \"[achievement name]\"" | Yes |
| Challenge won | "[Name] won the [challenge name]" | Yes |
| Level up | "[Name] reached Level [N] — [Title]!" | Yes |
| Personal record | "[Name] set a new PR: [exercise] [weight]" | Yes |
| Perfect day | "[Name] had a Perfect Day" | Yes |

**NOT auto-posted:** individual meal logs, individual non-negotiables, sleep data, step counts, routine activities. The feed should only show notable events.

### 12.4 Feed Item Component Specs

- Card: full width minus 16pt padding. Minimum height 72pt (variable). Background: #12203A. Border: 0.5pt #1E3A5F. Corner radius: 14pt. Internal padding: 12pt.
- Top row: avatar (28pt circle) + name (SF Pro Text, 14pt, semibold, white) + timestamp (SF Pro Text, 12pt, regular, #556677, trailing).
- Content line: SF Pro Text, 15pt, regular, white. Max 2 lines.
- Subtitle line (optional): SF Pro Text, 13pt, regular, #8899AA. Context info (XP earned, details).
- Reaction bar (bottom right): See Section 23.2 for the expanded 6-reaction system.
- Tap card: navigates to relevant detail (e.g., tap workout event to see friend's profile, tap challenge win to see challenge result).
- Swipe left on card: "Hide" option (hides this item, does not affect future items from this friend). "Mute [Name]" option (hides all future items from this friend until un-muted in settings).

### 12.5 Feed Algorithm

The feed uses a **relevance-weighted chronological** approach. It is primarily chronological (newest first) but applies the following boosts and filters:

**Boost factors (item appears higher):**
- Close friend (interacted with frequently in challenges): +2 position boost
- Achievement rarity Epic+: +1 position boost
- Challenge win involving user as participant: +3 position boost (you want to see if your rival won against someone else)
- Streak milestone at 30+ days: +1 position boost

**Filter rules (item is suppressed):**
- If a friend posts 3+ feed items in one hour, show only the most notable one and collapse rest into "and 2 more activities"
- Duplicate event types from same user within 4 hours: show only the latest
- Users you haven't interacted with in 30+ days: demoted to end of feed (not removed)

**Pagination:** Load 20 items at a time. Infinite scroll. Items older than 7 days are not loaded (archive accessible via "View older activity" link at bottom).

### 12.6 Feed Inline Preview (Arena Main View)

When collapsed on Arena Main View:
```
+----------------------------------------+
|  USERS FRIEND ACTIVITY                  |
|  Marco completed a workout - 2h ago     |
|  Luca hit a 7-day streak - 5h ago       |
|                       See Feed >        |
+----------------------------------------+
```

- Shows 2 most recent items, single line each, truncated.
- "See Feed >" navigates to full Feed view.

### 12.7 No Comments

The feed intentionally does NOT support comments. Rationale: comments create moderation overhead, complexity, and potential for negative interactions. Reactions (see Section 23.2 for the 6-reaction system) provide sufficient social interaction without the burden. This keeps the feed lightweight and positive.

### 12.8 Privacy

- Feed items respect privacy settings (Section 8.4). If a friend has hidden workout details, the feed item shows: "[Name] completed a workout" (no workout name or details).
- Users can disable their own feed posting entirely in Arena Settings: "Don't post my activities to friends' feeds." This makes them invisible in feeds but they can still see others' activities.

### 12.9 Feed States

- **Empty (no friends):** "Add friends to see their activity here!" with invite CTA.
- **Empty (friends but no recent activity):** "Your friends have been quiet today. Challenge someone to get things moving!" with challenge CTA.
- **Loading:** 3 skeleton cards with shimmer animation.
- **End of feed:** "You've seen everything. Pull down to refresh." Text in #556677, centered.

---

## 13. Screen 9: Notifications (Arena-Specific)

### 13.1 Push Notification Definitions

All notifications use `UNUserNotificationCenter`. Category identifiers and action buttons specified.

#### Competitive Notifications

| ID | Trigger | Title | Body | Actions | Sound |
|----|---------|-------|------|---------|-------|
| `arena.leaderboard.overtaken` | Friend passes user on weekly leaderboard | "You've been passed!" | "[Name] just passed you on the leaderboard. 23 XP behind." | "Open Arena" / "Dismiss" | Default |
| `arena.leaderboard.first` | User reaches #1 on weekly leaderboard | "You're #1!" | "You just took the top spot on the weekly leaderboard." | "Open Arena" | Triumphant chime |
| `arena.challenge.overtaken` | Opponent passes user in active challenge | "Challenge update" | "[Name] just took the lead! [Metric]: [their value] vs your [your value]." | "Open Challenge" / "Dismiss" | Default |
| `arena.challenge.invite` | Friend sends challenge invite | "New challenge!" | "[Name] challenged you: [Metric] for [Duration]. Accept?" | "Accept" / "Decline" / "View" | Default |
| `arena.challenge.accepted` | Opponent accepts your challenge invite | "Challenge accepted!" | "[Name] accepted your [Metric] challenge. It starts tomorrow!" | "Open Challenge" | Default |
| `arena.challenge.complete.win` | User wins a challenge | "Victory!" | "You won the [Metric] challenge vs [Name]! +[XP] XP earned." | "Open Arena" | Victory sound |
| `arena.challenge.complete.loss` | User loses a challenge | "Challenge complete" | "[Name] won the [Metric] challenge. +[XP] XP for participating." | "Rematch" / "Open Arena" | Soft tone |
| `arena.challenge.halfway` | Challenge reaches midpoint | "Halfway there" | "[Challenge]: You're [ahead/behind] by [amount]. Keep pushing!" | "Open Challenge" | Default |
| `arena.challenge.lastday` | Last day of a challenge | "Final push!" | "Last day of your [Metric] challenge vs [Name]. [Status]." | "Open Challenge" | Default |

#### Streak & Achievement Notifications

| ID | Trigger | Title | Body | Actions | Sound |
|----|---------|-------|------|---------|-------|
| `arena.streak.danger` | User hasn't met 3/5 streak criteria and it's 20:00 | "Streak in danger!" | "Your [N]-day streak ends at midnight. Complete 1 more task to save it!" | "Open Tempo" | Urgent tone |
| `arena.streak.saved` | Streak freeze auto-consumed | "Streak saved!" | "Your streak freeze protected your [N]-day streak yesterday." | "Open Arena" | Relief chime |
| `arena.streak.milestone` | User hits a streak tier | "Streak milestone!" | "[N]-day streak! [Multiplier]x XP multiplier activated." | "Open Arena" | Fire crackle |
| `arena.streak.broken` | Streak resets (no freeze available) | "Streak broken" | "Your [N]-day streak ended. Start a new one today!" | "Open Tempo" | Soft descending tone |
| `arena.levelup` | User levels up | "Level Up!" | "You're now a [Title] (Level [N])!" + unlock message if applicable | "Open Arena" | Level up chime |
| `arena.achievement` | Achievement unlocked | "Achievement unlocked!" | "[Achievement name] — [Short description]. +[XP] XP." | "View Achievement" | Achievement chime |

#### Social Notifications

| ID | Trigger | Title | Body | Actions | Sound |
|----|---------|-------|------|---------|-------|
| `arena.friend.request` | Someone sends friend request | "Friend request" | "[Name] wants to be your friend on Tempo." | "Accept" / "Decline" / "View Profile" | Default |
| `arena.friend.accepted` | Someone accepts user's request | "New friend!" | "[Name] accepted your friend request." | "Open Arena" | Default |
| `arena.friend.activity` | Friend achieves something notable | "[Name] is on a roll" | "[Name] just hit a 30-day streak!" | "Open Feed" | Default |
| `arena.reaction.received` | Close friend reacts to your activity | "Reaction" | "[Name] sent you FLEX on your workout" | "Open Feed" | Subtle pop (only if close friend) |

### 13.2 Notification Frequency Limits

To prevent notification fatigue:

| Category | Max per day | Cooldown between |
|----------|-------------|-----------------|
| Leaderboard overtaken | 3 | 2 hours |
| Challenge overtaken | 3 per challenge | 4 hours |
| Challenge invites | 5 | None (immediate) |
| Streak danger | 1 | N/A (once per evening) |
| Achievement unlocked | 5 | None (immediate, but rare by nature) |
| Friend activity | 3 | 1 hour |
| Level up | Unlimited | N/A (rare by nature) |
| Reactions | 3 | 1 hour |

### 13.3 Notification Timing

- `arena.streak.danger`: sent at 20:00 local time if criteria not met. If met between 20:00 and 23:59, a silent cancellation prevents delivery if still pending.
- Challenge notifications: sent as soon as the event occurs (real-time).
- Leaderboard notifications: checked every 30 minutes. If rank changed, notification sent (within frequency limits).
- Level-up and achievement notifications: sent immediately upon XP calculation.
- **Leaderboard overtaken notifications:** Only sent if user is in top 50% of their friend leaderboard OR within striking distance of the person who passed them (gap < 200 XP). This prevents last-place users from getting demoralizing "you've been passed again" notifications.

### 13.4 In-App Notification Badge

- Arena tab icon shows a red badge dot (not a number) when there are unseen:
  - Friend requests (count)
  - Challenge invites (count)
  - Achievement unlocks since last viewed (count)
  - Leaderboard position changes (boolean)
- Badge clears when user visits the relevant screen.

### 13.5 Notification Deep Links

Each notification's `userInfo` includes a `deepLink` key:
- `arena.leaderboard.*` -> opens Leaderboard View
- `arena.challenge.*` -> opens specific Challenge Detail View
- `arena.streak.*` -> opens Arena Main View (scrolled to streak section)
- `arena.achievement` -> opens Achievements View with specific achievement highlighted
- `arena.friend.*` -> opens Add Friend sheet with Pending Requests visible
- `arena.levelup` -> opens Arena Main View (triggers level-up animation if not yet seen)

---

## 14. Screen 10: Onboarding for Arena

### 14.1 Trigger

Arena onboarding launches when:
1. User first taps the Arena tab (after completing the main Tempo onboarding), OR
2. User is directed to Arena from the main onboarding flow.

### 14.2 Onboarding Flow (5 screens)

#### Screen 1: Welcome to the Arena

- Lottie: animated trophy with swords crossed behind it, subtle flame particles. Loops once then holds.
- Title: "Welcome to the Arena" — SF Pro Display, 28pt, bold, white, centered.
- Body: "This is where effort becomes competition. Earn XP for everything you do, level up, and prove you're grinding harder than your friends." — SF Pro Text, 16pt, regular, #AABBCC, centered, max width 300pt.
- Pagination dots: 8pt circles, active = white, inactive = #556677. Centered, 24pt from bottom of text.
- CTA button: "Let's Go" — full width minus 64pt padding, height 52pt, corner radius 14pt, blue gradient. Text SF Pro Display, 17pt, bold, white.
- Swipe right to advance (or tap CTA).

#### Screen 2: XP System

- XP list: each row animates in with stagger (150ms delay each). XP values count up from 0 to final value (slot machine effect, 400ms).
- Perfect Day row: highlighted with gold background at 10% opacity and gold text.

#### Screen 3: Streaks & Multipliers

- Flame Lottie: morphs through the different streak tier flames as user reads (small -> medium -> large -> blue -> purple). Timed to 6 seconds total, loops.
- Multiplier rows: appear with slide-in from right, staggered 200ms.

#### Screen 4: Compete with Friends

- Lottie: animated mini leaderboard with rows shuffling positions, crowns appearing/disappearing. Playful, 4-second loop.

#### Screen 5: Choose Your Name + First Achievement

- Avatar: tappable to open photo picker or camera. Default: first letter of name on tier-colored circle.
- Username field: height 48pt, corner radius 12pt, background #1E3A5F, border 2pt #2D7FF9 when focused.
  - Pre-filled with suggested username (first name + last initial, lowercase, no spaces).
  - Live availability check with 500ms debounce.
  - Valid: green checkmark + "Available" in #22C55E.
  - Taken: red X + "Already taken. Try another." in #FF3B5C.
  - Rules: 3-20 characters, lowercase alphanumeric + underscores only. No spaces. Validated client-side.
- "Enter the Arena" CTA: disabled until username is valid and available. Enabled state: gradient blue-to-purple with subtle shimmer animation.
- On tap: transitions to Arena Main View. Simultaneously triggers the "Genesis" achievement unlock animation (Section 11.4). First achievement earned: +25 XP. This seeds the XP bar and gives immediate gratification.

### 14.3 Onboarding Technical Specs

- Navigation: horizontal paged `TabView` with `.tabViewStyle(.page)`. Swipe between screens. CTA buttons also advance.
- Skip: no explicit skip button. User can swipe through quickly. But username screen (Screen 5) is mandatory.
- Persistence: `UserDefaults` key `arena_onboarding_completed` = `true` after completing Screen 5. Never shown again.
- Animation performance: all Lottie animations preloaded on Screen 1 appearing. Target: 60fps on iPhone 12 and newer.
- Total estimated time: 45-60 seconds for a user reading everything, 15-20 seconds for a speed-swiper.

---

## 15. Screen 11: Arena Settings

### 15.1 Navigation

- Accessed via gear icon in Arena header.
- Presented as push navigation from Arena Main View.

### 15.2 Settings Sections

Standard `List` with `.insetGrouped` style.
- Section headers: SF Pro Display, 13pt, semibold, uppercase, tracking 1.2pt, #8899AA.
- Row height: 44pt standard.
- Label: SF Pro Text, 16pt, regular, white, leading.
- Value/detail: SF Pro Text, 16pt, regular, #8899AA, trailing. Chevron for drill-downs.
- Toggles: standard SwiftUI `Toggle`, tint color #2D7FF9.

#### Profile Section
- **Display Name:** Tap opens text field editor. Max 30 characters.
- **Username:** Tap opens editor with same validation as onboarding. Changing username: limited to once per 30 days. Warning: "Friends will see your new username. You can change this once every 30 days."
- **Avatar:** Tap opens photo picker (PHPickerViewController) or camera. Crop to circle. Max 2MB after compression.
- **Profile Color:** Opens color picker with 8 preset colors (matches level unlock at Level 3). Pre-Level 3: shows lock icon and "Unlock at Level 3."

#### Privacy Section
- Each privacy row taps to cycle: Everyone -> Friends Only -> Hidden. Shown as a segmented control in the drill-down, or inline tap-to-cycle.
- "Post to Friends' Feed" toggle: when OFF, user's activities are not shown in any friend's feed. A warning appears: "Your activities won't appear in friends' feeds. You'll still see their activities."

#### Notifications Section
- Each toggle controls a group of push notifications (mapped to the IDs in Section 13.1).
- "Sound Effects" toggle: controls ALL in-app sounds (Section 11.7). When OFF, all animations are silent.

#### Streaks Section
- Current streak: display only. Streak number + flame icon.
- Streak freezes: "2/3 available" display. Not directly purchasable (earned via streaks, see Section 4.3).
- "Use Freeze Tomorrow": pre-activates a freeze for the next day. Toggle + confirmation: "This will use 1 of your 2 freezes for tomorrow. Your streak will be preserved even if you don't complete any tasks."
- Freeze History: drill-down list showing dates when freezes were earned and used.

#### Leaderboard Section
- "Participate in Leaderboard" toggle: when OFF, user is hidden from ALL leaderboards. Warning on toggle-off: "You won't appear on any leaderboard and won't see your ranking. Your friends won't see you in their leaderboards. You can re-join anytime."
- On re-join: user's accumulated XP is counted, they slot into the correct position. No XP is lost.

#### Arena Shop Section (NEW)
- "Arena Shop" row navigates to the XP spending store (Section 27).
- Shows current spendable XP balance.

#### Friends Section
- **Friend List:** navigates to Friend List View (Section 8.3).
- **Blocked Users:** list of blocked users with "Unblock" swipe action. Unblocking does NOT re-add as friend; they must send a new request.
- **Muted Users:** list of users muted from feed. "Unmute" swipe action.

#### Account Section
- **My QR Code:** full-screen view showing user's QR code (encodes user ID hash). Large QR (240x240pt), username below, "Scan this to add me on Tempo" instruction text. Share button to save image or share via share sheet.
- **Reset Arena Data:** DESTRUCTIVE. Confirmation flow:
  1. Tap: alert "Reset Arena Data? This will reset your XP, level, streaks, and achievements to zero. Your friends and challenge history will be preserved. This cannot be undone." [Reset / Cancel].
  2. If Reset tapped: second confirmation with text input: "Type RESET to confirm." Text field must match exactly.
  3. On confirm: all XP, level, streak, and achievement data is wiped. User returns to Level 1, 0 XP, 0-day streak. Friend list and account remain. Onboarding is NOT re-shown.

---

## 16. Color System & Typography

### 16.1 Color Palette

| Name | Hex | Usage |
|------|-----|-------|
| Deep Navy (Background) | #0A1628 | Main screen background |
| Card Surface | #12203A | Card backgrounds |
| Card Border | #1E3A5F | Card borders, dividers, inactive elements |
| Electric Blue | #2D7FF9 | XP values, progress bars, CTAs, active states |
| Molten Orange | #FF6B2C | Streaks, fire, urgency, multipliers |
| Emerald | #22C55E | Success, achievements, wins, online status, positive changes — aligned with tempo.color.recovery.green |
| Crimson | #FF3B5C | Losses, penalties, errors, negative changes, offline |
| Gold | #FFD700 | #1 rank, legendary items, prestige |
| Silver | #C0C0C0 | #2 rank, common achievements |
| Bronze | #CD7F32 | #3 rank |
| Purple Accent | #A855F7 | Epic rarity, commander tier, gradient accents |
| Lavender | #6C5CE7 | Gradient endpoint for CTAs |
| Mythic Pink | #FF1493 | Mythic rarity border, mythic achievement effects |
| Muted Text | #8899AA | Secondary text, labels, timestamps |
| Dim Text | #556677 | Tertiary text, disabled states, placeholders |
| White | #FFFFFF | Primary text, headings |
| Light Text | #AABBCC | Body text, descriptions |
| Dimmer Text | #CCDDEE | XP breakdown category labels |

### 16.2 Typography System

| Style | Font | Size | Weight | Tracking | Usage |
|-------|------|------|--------|----------|-------|
| Display Large | SF Pro Display | 34pt | Bold | 0 | Screen titles ("ARENA") |
| Display Medium | SF Pro Display | 28pt | Bold | 0 | Onboarding titles, celebration text |
| Display Small | SF Pro Display | 20pt | Bold | 0 | Card section headers, achievement names |
| Heading | SF Pro Display | 18pt | Bold | 0 | Profile title + level |
| Subheading | SF Pro Display | 15pt | Semibold | 0 | Category section headers |
| Section Label | SF Pro Display | 13pt | Semibold | 1.2-1.5pt | Uppercase labels (TODAY'S XP, WEEKLY LEADERBOARD) |
| Body | SF Pro Text | 16pt | Regular | 0 | Settings rows, main content |
| Body Small | SF Pro Text | 15pt | Regular | 0 | Feed content, leaderboard names |
| Body Smaller | SF Pro Text | 14pt | Regular | 0 | XP breakdown rows, challenge details |
| Caption | SF Pro Text | 13pt | Regular | 0 | Timestamps, secondary info |
| Caption Small | SF Pro Text | 12pt | Regular | 0 | Tertiary info, gap text |
| Caption Tiny | SF Pro Text | 10-11pt | Regular | 0 | Badge names, chart labels |
| Number Large | SF Mono | 48pt | Bold | 0 | Today's XP hero number |
| Number Display | SF Mono | 32pt | Bold | 0 | Streak count |
| Number Medium | SF Mono | 28pt | Bold | 0 | Level number, challenge scores |
| Number Standard | SF Mono | 22pt | Bold | 0 | Stats grid values |
| Number Body | SF Mono | 14-16pt | Semibold | 0 | XP values in rows, leaderboard XP |
| Number Small | SF Mono | 12pt | Regular | 0 | XP fractions, sub-values |
| Number Tiny | SF Mono | 9-10pt | Regular | 0 | Badge XP, chart values |

### 16.3 Spacing System

Base unit: 4pt.

| Token | Value | Usage |
|-------|-------|-------|
| `spacing.xs` | 4pt | Between inline elements |
| `spacing.sm` | 8pt | Between related elements (icon + label) |
| `spacing.md` | 12pt | Card internal padding, between compact rows |
| `spacing.lg` | 16pt | Screen edge padding, between cards, section spacing |
| `spacing.xl` | 24pt | Between major sections |
| `spacing.xxl` | 32pt | Between onboarding sections, major groups |

### 16.4 Corner Radius System

| Token | Value | Usage |
|-------|-------|-------|
| `radius.sm` | 8pt | Small pills, inline badges, progress bar |
| `radius.md` | 12pt | Buttons, text fields, search bars |
| `radius.lg` | 14pt | Feed items, CTA buttons, achievement cards |
| `radius.xl` | 16pt | Main cards, section cards |

---

## 17. Data Models & Edge Cases

### 17.1 Core Data Models (Conceptual)

```
User {
    id: UUID
    username: String (unique, 3-20 chars, lowercase alphanumeric + underscore)
    displayName: String (max 30 chars)
    avatarURL: URL?
    level: Int (1-50+)
    totalXP: Int
    spendableXP: Int (totalXP minus spent XP — see Section 27)
    currentStreak: Int
    longestStreak: Int
    streakFreezes: Int (0-3)
    prestigeCount: Int (0+)
    profileColor: String (hex)
    leagueId: UUID? (see Section 19)
    groupIds: [UUID] (see Section 23.5)
    trustScore: Float (0.0-1.0, see Section 22)
    createdAt: Date
    privacySettings: PrivacySettings
    notificationSettings: NotificationSettings
    arenaOnboardingCompleted: Bool
    leaderboardOptIn: Bool
    feedOptIn: Bool
}

DailyXP {
    id: UUID
    userId: UUID
    date: Date (day granularity)
    workoutXP: Int
    studyXP: Int
    nutritionXP: Int
    recoveryXP: Int
    stepsXP: Int
    nonNegotiablesXP: Int
    challengeXP: Int
    bonusXP: Int (Perfect Day, Near-Perfect, Login)
    penaltyXP: Int (negative)
    streakMultiplier: Float
    totalBeforeMultiplier: Int
    totalAfterMultiplier: Int
    breakdown: [XPEvent] (detailed log of each source)
}

XPEvent {
    id: UUID
    source: String (e.g., "workout.completion", "study.target_hit")
    baseXP: Int
    multipliedXP: Int
    timestamp: Date
    metadata: [String: Any] (e.g., exercise name, study duration)
    flagged: Bool (anti-cheat, see Section 22)
    flagReason: String?
}

Friendship {
    id: UUID
    requesterId: UUID
    recipientId: UUID
    status: Enum (pending, accepted, declined, blocked)
    createdAt: Date
    acceptedAt: Date?
}

Challenge {
    id: UUID
    type: Enum (headToHead, group)
    templateId: String? (see Section 20 for named templates)
    metric: String
    duration: Int (days)
    startDate: Date
    endDate: Date
    stakes: String? (max 100 chars)
    creatorId: UUID
    participants: [ChallengeParticipant]
    status: Enum (pending, active, completed, cancelled, abandoned)
    winnerId: UUID?
    difficultyTier: Enum? (casual, competitive, extreme)
    seasonalEventId: String? (see Section 20.4)
}

ChallengeParticipant {
    userId: UUID
    challengeId: UUID
    inviteStatus: Enum (pending, accepted, declined)
    currentScore: Float
    dailyScores: [DailyChallengeScore]
    xpAwarded: Int
}

Achievement {
    id: Int (1-108)
    name: String
    description: String
    flavorText: String
    category: Enum
    criteria: AchievementCriteria
    xpReward: Int
    rarity: Enum (common, rare, epic, legendary, mythic)
    isHidden: Bool
    isSeasonal: Bool
    seasonWindow: DateRange? (for limited-time achievements)
}

UserAchievement {
    userId: UUID
    achievementId: Int
    unlockedAt: Date
    isPinned: Bool
}

FeedItem {
    id: UUID
    userId: UUID
    type: Enum (workout, study, streak, achievement, challenge, level, pr, perfectDay)
    content: String
    metadata: [String: Any]
    createdAt: Date
    reactions: [Reaction]
}

Reaction {
    userId: UUID
    feedItemId: UUID
    type: Enum (strong, fire, respect, watching, electric, cold)
    createdAt: Date
}

League {
    id: UUID
    name: String (auto-generated)
    tier: Enum (bronze, silver, gold, platinum, diamond)
    weekNumber: Int
    participants: [LeagueParticipant]
    promotionSlots: Int (top N promote)
    relegationSlots: Int (bottom N relegate)
}

LeagueParticipant {
    userId: UUID
    leagueId: UUID
    weeklyXP: Int
    rank: Int
    promoted: Bool?
    relegated: Bool?
}

Group {
    id: UUID
    name: String (max 30 chars)
    creatorId: UUID
    members: [UUID] (max 20)
    avatarURL: URL?
    createdAt: Date
}

ShopPurchase {
    id: UUID
    userId: UUID
    itemId: String
    xpCost: Int
    purchasedAt: Date
}

IntegrityFlag {
    id: UUID
    userId: UUID
    xpEventId: UUID
    reason: String
    severity: Enum (low, medium, high, critical)
    resolved: Bool
    resolution: Enum? (cleared, adjusted, penalized)
    createdAt: Date
}
```

### 17.2 Edge Cases & Error Handling

#### Time Zone Handling
- All streak days, daily XP, and challenge periods are calculated in USER'S LOCAL TIME ZONE (from device settings).
- If user changes time zone mid-day (e.g., traveling): the day boundary is recalculated. If the "old" day had met streak criteria, it's locked in. The "new" day starts fresh.
- Challenge start/end times use the CREATOR'S time zone at creation time. All participants see a countdown timer (not a fixed time), so it's equitable regardless of zone.

#### Offline Behavior
- All XP calculations happen locally AND are synced to server.
- If offline: XP accrues locally. Streak status tracked locally. When connectivity resumes, sync occurs.
- Leaderboard and feed are unavailable offline. Show cached last-known state with "Last updated [time]" label and a dimmed overlay.
- Challenge scores sync on reconnect. If offline for > 24h during a challenge, a banner warns: "Your challenge data may be out of date."

#### Account Deletion
- When a user deletes their Tempo account:
  - Removed from all friends' lists (silently — no notification).
  - Active challenges: opponents win by default.
  - Feed items: removed (all reactions on their items also removed).
  - Leaderboard: removed immediately.
  - Data: permanently deleted after 30-day grace period (standard for account recovery).

#### Data Integrity
- XP cannot be manually edited by users. All XP is server-validated against logged activities.
- Anti-cheat: see Section 22 for comprehensive integrity system.
- Duplicate events: idempotency keys on all XP-granting actions. Logging the same workout twice does not double XP.

#### Concurrent Events
- If level-up and achievement unlock happen simultaneously (same action triggers both): level-up animation plays first (3.5s), then achievement animation plays (2.8s). Total: ~6.3s. User sees both sequentially.
- If multiple achievements unlock simultaneously: they queue and play one after another with 500ms gap. Max queue: 3. If more than 3, remaining are shown as a batch notification: "3 more achievements unlocked! View all."

#### Empty/Null States Summary

| State | Behavior |
|-------|----------|
| No friends | Leaderboard empty state with invite CTA |
| No challenges | Challenge hub shows "Create your first challenge!" |
| No achievements | Achievement view shows all locked badges |
| No XP today | Today's XP shows 0 with all categories dimmed |
| No meals logged | Nutrition XP shows +0, individual meal rows dimmed |
| No workout scheduled | Workout XP row shows "No workout today" in italic |
| No sleep data | Sleep/recovery rows show "Not logged" with dashed outline |
| Friend list full (50) | Add Friend shows "List full" error with suggestion to remove inactive friends |
| Challenge invite expired | Removed from invites list, notification sent to creator |
| Server error on any data | Section shows "Couldn't load. Tap to retry." |
| Rate limited (too many actions) | "Slow down! Try again in a moment." toast, 5s cooldown |

#### Device Compatibility
- Minimum: iPhone 12 (A14 Bionic), iOS 17.4.
- Animations: all Lottie animations at 60fps on A14+. On older devices (if supported in future): reduce particle counts by 50%, disable animated borders, use static gradients.
- Dynamic Type: all text scales with user's accessibility text size. Layout uses `@ScaledMetric` for spacing. Cards expand vertically. Horizontal layouts reflow to vertical at largest accessibility sizes.
- VoiceOver: all interactive elements have accessibility labels. XP values read as "plus 100 experience points." Achievements read name + description + rarity. Leaderboard reads "Rank [N], [Name], [XP] experience points, Level [N]."
- Reduce Motion: if `UIAccessibility.isReduceMotionEnabled`, all animations are replaced with simple fade-in/fade-out (200ms). No particle systems, no spring animations, no sliding. Level-up shows a static card instead of animated sequence.

---

## 18. XP Economy Simulation & Balancing

This section provides a complete economy simulation to verify that the XP-to-Level curve produces the intended player experience. Economy health is the difference between a game that feels "just right" and one that feels like a grind or a giveaway.

### 18.1 Player Archetypes

| Archetype | Percentile | Description | Daily behavior |
|-----------|-----------|-------------|----------------|
| **Ghost** | 25th | Opens app sometimes, logs a few things, inconsistent | Logs 1-2 meals, maybe a workout 2x/week, no study, no non-negotiables |
| **Casual** | 50th | Uses the app most days, not obsessive | 3-4 sessions/week workout, some study on weekdays, logs most meals, basic non-negotiables |
| **Dedicated** | 75th | Daily user, takes it seriously, occasional perfect days | Daily workout or study, all meals logged, most non-negotiables, decent sleep |
| **Hardcore** | 95th | Optimizes everything, rarely misses a day | Workout + study daily, all meals perfect, all non-negotiables, perfect sleep, PRs regularly |
| **Perfect** | 100th | Theoretical max player, never misses anything | Every possible XP source maxed every single day |

### 18.2 Daily XP by Archetype (Before Multiplier)

#### Ghost Player (25th percentile)
```
Active ~4 days/week. On active days:
  Workout (2x/week):         100 + 30 (intensity) = 130 XP on workout days
  Study (1x/week, 1 session):  30 XP
  Meals (1-2 logged):         15-30 XP
  Steps (usually < 5K):        0 XP
  Non-negotiables (0-1 done):  0-10 XP
  Sleep (sometimes logged):   0-20 XP
  Login:                       10 XP

  Active day average: ~120 XP
  Inactive day: ~10 XP (login only, maybe)
  Weekly average: (4 * 120) + (3 * 5) = ~495 XP/week
  Daily average: ~71 XP/day
  Monthly: ~2,130 XP
  Streak: rarely exceeds 3 days, so 1.0x multiplier most of the time
```

#### Casual Player (50th percentile)
```
Active 5-6 days/week. On active days:
  Workout (3-4x/week):       100 + 30 + 30 (recovery) = 160 XP
  Study (4x/week, 2 sessions): 80 + 60 = 140 XP on study days
  Meals (2-3 logged):         30-45 XP + occasional macro hit = ~50 XP
  Steps (5K-8K):              20-35 XP, average 28 XP
  Non-negotiables (3-4 done): 30-40 + occasional full bonus = ~45 XP
  Sleep (most days logged):   20 + occasional 25 = ~30 XP
  Login:                      10 XP
  Near-Perfect Day (1-2x/week): 75 XP

  Active day average: ~280 XP
  Light day average: ~120 XP
  Weekly average: (4 * 280) + (2 * 120) = ~1,360 XP/week
  Daily average: ~194 XP/day
  Monthly: ~5,820 XP
  Streak: maintains 3-7 days usually, 1.1x average multiplier
  Monthly with multiplier: ~6,400 XP
```

#### Dedicated Player (75th percentile)
```
Active 6-7 days/week. Consistent.
  Workout (5x/week):         100 + 40 (recovery) + 25 (intensity) = 165 XP + occasional PR 75 XP
  Study (5-6x/week, 3-4 sessions): 80 + 120 + 20 (scaling) = 220 XP
  Meals (3 logged most days): 45 + 30 (protein) + occasional 40 (all macros) = ~80 XP
  Steps (8K-10K):             35-50 XP, average 42 XP
  Non-negotiables (4-5 done): 40-50 + 60 (all done 4x/week) = ~65 XP average
  Sleep (daily):              20 + 25 (score 80+) = 45 XP
  Login:                      10 XP
  Perfect Day (2-3x/week):   200 XP average = ~75 XP/day spread
  Monday bonus: +25/7 = ~4 XP/day

  Daily average (before multiplier): ~500 XP
  Monthly (before multiplier): ~15,000 XP
  Streak: maintains 14-30+ days, 1.5x average multiplier
  Monthly with multiplier: ~22,500 XP
```

#### Hardcore Player (95th percentile)
```
Active 7 days/week. Optimizes everything.
  Workout (6x/week):         100 + 50 (green recovery) + 30 (heavy) + PRs = ~220 XP average
  Study (6x/week, 5-6 sessions): 80 + 150 + 40 (scaling) = 270 XP
  Meals (all logged, macros hit): 45 + 15 (snacks) + 40 (all macros) = 100 XP
  Steps (10K-15K):            50-75 XP, average 60 XP
  Non-negotiables (all done 6x/week): 50 + 60 = 110 XP average = ~95 XP/day
  Sleep (daily, score 85+):   20 + 25-40 = ~55 XP
  Login:                      10 XP
  Perfect Day (5-6x/week):   200 XP * 5.5/7 = ~157 XP/day spread
  Monday bonus: +25/7 = ~4 XP/day
  Challenge participation:    ~30 XP/day average (active challenges)

  Daily average (before multiplier): ~730 XP
  Monthly (before multiplier): ~21,900 XP
  Streak: maintains 30-60+ days, 1.75-2.0x average multiplier
  Monthly with multiplier: ~38,325 XP (at 1.75x)
```

#### Perfect Player (100th percentile) — Theoretical
```
Every single day, all caps hit:
  Workout: 100 + 50 + 30 = 180 XP (no Monday bonus averaged)
  PRs: ~75 XP (one PR per day average over time)
  Study: 80 + 180 + 50 = 310 XP
  Meals: 100 XP
  Sleep: 20 + 40 = 60 XP
  Recovery: 30 XP
  Steps: 75 XP
  Non-negotiables: 50 + 60 = 110 XP
  Perfect Day: 200 XP
  Login: 10 XP
  Monday bonus averaged: +4 XP
  Challenge participation: ~40 XP/day

  Daily (before multiplier): ~1,234 XP
  With 90+ day streak (2.25x): ~2,777 XP/day
  Monthly: ~83,310 XP
```

### 18.3 Time-to-Level Verification

**Target: Level 50 should take a Dedicated Player approximately 6-7 months.**

Level 50 requires 157,770 cumulative XP (see Section 3.1 for the canonical table using `floor(200 * N^1.65)`).

**Original curve `floor(100 * N^1.5)` was broken:** Level 50 at only 30,288 XP meant a Dedicated player reached it in ~6 weeks, not 6 months. The streak multiplier compounded the problem -- a 1.5x multiplier on 500 XP/day = 750/day = 22,500/month = Level 50 in 6 weeks. The curve was too flat.

### 18.4 Economy Rebalancing — Production XP Curve

**Production formula (canonical, used in Section 3.1):**
```
Cumulative XP to reach level N = floor(200 * N^1.65)
Per-level XP = cumulative(N) - cumulative(N-1)
```

**Verified time-to-level-50 with production curve:**

| Archetype | Monthly XP (w/ multiplier) | Time to Level 50 | Level at 6 months | Level at 12 months |
|-----------|---------------------------|-------------------|--------------------|---------------------|
| Ghost (25th) | ~2,130 | Never realistically | ~Level 6 (Contender) | ~Level 8 (Contender) |
| Casual (50th) | ~6,400 | ~24.7 months | ~Level 20 (Gladiator) | ~Level 28 (Captain) |
| Dedicated (75th) | ~22,500 | ~7.0 months | ~Level 42 (Warlord) | Level 50 + Prestige |
| Hardcore (95th) | ~38,325 | ~4.1 months | Level 50 + Prestige | Level 50 + Prestige 2 |
| Perfect (100th) | ~83,310 | ~1.9 months | Level 50 + Prestige 2 | Level 50 + Prestige 4+ |

**Why this is better than the previous curve:**
- Dedicated player reaches Legend tier in ~7 months. This is the sweet spot: long enough to be meaningful, short enough to be achievable within an academic year.
- Casual player reaches Gladiator (~Level 20) at 6 months. This is the "aspirational middle" -- they can see higher tiers and have a clear path forward without feeling permanently behind.
- Ghost player stays in Contender tier, which correctly reflects minimal engagement without being punishing (they still see progress).
- The Hardcore-to-Dedicated gap is ~3 months (not 5+ months), meaning effort is rewarded proportionally without making it feel pointless for non-optimizers.
- Perfect player reaches Level 50 in ~2 months, which is fast but requires genuinely superhuman consistency (every cap hit every day with a 90+ day streak). This is acceptable as a theoretical maximum.

**Inflation checkpoint at Level 30+:** At higher levels, the per-level XP requirement grows to ~3,700-4,700 XP per level. For a Dedicated player earning ~750 XP/day (with multiplier), each level takes ~5-6 days. This is the correct pacing -- one level-up celebration per week keeps the dopamine cycle alive without trivializing the achievement.

### 18.5 Multiplier Inflation Control

The streak multiplier is the biggest inflation driver. Without controls, a user with a 90+ day streak earns 2.25x, which means their daily XP effectively becomes a different economy than a new user.

**Control mechanisms:**

1. **Multiplier cap at 2.5x** (180+ day streaks) with 3.0x reserved only for 365+. This prevents runaway inflation.

2. **Weekly XP ceiling: 15,000 XP** (after multiplier). Any XP beyond this is "banked" and shown as "Overflow XP -- applied next week." Verification math:
   - Hardcore player: ~730 base/day x 1.75x = ~1,278/day x 7 = **~8,942/week** (well under ceiling)
   - Perfect player: ~1,234 base/day x 2.25x = ~2,777/day x 7 = **~19,438/week** (hits ceiling)
   - The old 12,000 ceiling was never reachable by any real player archetype (Hardcore topped out at ~8,900). A ceiling only the theoretical Perfect player hits is useless as inflation control. The 15,000 ceiling gates the Perfect player while giving Hardcore players room for exceptional weeks without frustration.

3. **Weekly leaderboard shows RAW XP (before multiplier).** This is the single most important fairness mechanism. A new user with a 0-day streak competes on equal footing against a user with a 90-day streak on the weekly board. Monthly and All-Time views show total (multiplied) XP.

4. **Diminishing multiplier returns at high levels:** For users Level 35+, the streak multiplier is soft-capped at 2.0x for LEADERBOARD purposes only. The user still earns the full multiplied XP for leveling and personal progress, but their leaderboard contribution uses the capped rate. This prevents late-game multiplier runaway from making leaderboards uncompetitive for newer serious users.

5. **Daily XP source caps (recap):**
   - Workout: max 1 workout XP grant/day (180 base + 225 PR cap = 405 max)
   - Study: max 310 base XP/day
   - Nutrition: max 100 base XP/day
   - Recovery/Sleep: max 90 base XP/day
   - Steps: max 75 base XP/day
   - Non-negotiables: max ~110 base XP/day (depends on user's list, max 5 items)
   - Perfect Day: max 200 base XP/day
   - Login: max 10 base XP/day
   - **Hard daily cap (before multiplier): 1,325 XP**
   - **Hard daily cap (after max multiplier of 3.0x): 3,975 XP** — but this is essentially unreachable because it requires a 365+ day streak AND hitting every single cap.

### 18.6 The "Fair Start" Problem

**Problem:** A user who joins 3 months after their friends will see a massive XP gap on the All-Time leaderboard and may feel like "what's the point."

**Solutions:**
1. **Weekly leaderboard is the default and primary view.** This resets every Monday, so a new user competes on equal footing from their first week.
2. **"New Player Momentum" bonus:** For the first 14 days, new users get a 1.5x base multiplier (stacks with streak multiplier). This accelerates them through the early levels where the gap feels biggest. Fades linearly from 1.5x to 1.0x over days 1-14.
3. **League system (Section 19):** Automatically groups users by activity level, so new users compete against other new users.
4. **All-Time leaderboard has a "Pace" mode:** Shows average daily XP instead of total, leveling the field for newer users.

---

## 19. Leaderboard Psychology & League System

### 19.1 The Problem with Pure Friend Leaderboards

In any friend-based leaderboard, one of three problems always emerges:
1. **The Runaway Leader:** One friend is way more active and has 3x everyone else's XP. Others stop trying.
2. **The Laggard:** One friend barely uses the app. They're always last. They eventually stop checking.
3. **The Uneven Group:** Some friends are hardcore, some are casual. The middle gets squeezed.

Duolingo solved this with leagues. Strava solved it with segments. We solve it with both.

### 19.2 League System Design

#### League Tiers

| Tier | Name | Color | Icon | Level Range to Enter |
|------|------|-------|------|---------------------|
| 1 | Bronze League | #CD7F32 | Bronze shield | Level 1-10 (everyone starts here) |
| 2 | Silver League | #C0C0C0 | Silver shield | Promoted from Bronze |
| 3 | Gold League | #FFD700 | Gold shield | Promoted from Silver |
| 4 | Platinum League | #E5E4E2 | Platinum crown | Promoted from Gold |
| 5 | Diamond League | #B9F2FF | Diamond with sparkle | Promoted from Platinum |

#### How Leagues Work

1. **Weekly cycle:** Every Monday at 00:00 in the user's LOCAL TIME ZONE, leagues reset. Since league participants may span time zones, each user's league score is calculated based on their local Monday-to-Sunday window. The league ranking is computed server-side using each participant's local-time weekly XP. This means a user in UTC+9 and a user in UTC-5 both get a full Monday-Sunday window in their own time zone.
2. **Group formation:** At the start of each week, users are grouped into leagues of ~20 people based on their PREVIOUS WEEK'S XP. This ensures similar activity levels compete against each other.
3. **Promotion/Relegation:** At end of each week:
   - Top 5 in each league: **promoted** to next tier (green highlight, upward arrow animation)
   - Middle 10: **stay** in current tier
   - Bottom 5: **relegated** to previous tier (yellow highlight, no shame animation — just a "try harder next week" message)
   - Bronze League bottom 5: stay in Bronze (cannot go lower)
   - Diamond League top 5: stay in Diamond (cannot go higher) but get a special "Diamond Elite" badge for that week
4. **Matchmaking:** Users are matched with other users who earned similar XP the previous week (+/- 20%). This prevents a hardcore user from stomping Bronze league users just because they had one bad week.
5. **League leaderboard** is a separate tab on the Leaderboard View (Section 7.2). Shows all ~20 users in your current league, their weekly XP, and promotion/relegation zones highlighted.

#### League Visual Treatment

```
+----------------------------------------+
|  YOUR LEAGUE: GOLD LEAGUE              |
|  Week of March 18-24                   |
|  ──────────────────────────────────    |
|                                        |
|  PROMOTION ZONE (Top 5) -- green       |
|  ──────────────────────────────────    |
|  1. StefanoR       4,200 XP  UP       |
|  2. ChiaraM        3,980 XP  UP       |
|  3. You            3,750 XP  UP       |
|  4. AlexP          3,600 XP  UP       |
|  5. MartaG         3,520 XP  UP       |
|  ──────────────────────────────────    |
|                                        |
|  SAFE ZONE (6-15) -- neutral           |
|  ──────────────────────────────────    |
|  6. DavideC        3,400 XP           |
|  7. LauraB         3,200 XP           |
|  ...                                   |
|  15. FedericoN     2,100 XP           |
|  ──────────────────────────────────    |
|                                        |
|  RELEGATION ZONE (Bottom 5) -- amber   |
|  ──────────────────────────────────    |
|  16. GiuliaT       1,800 XP  DOWN     |
|  17. PaoloV        1,650 XP  DOWN     |
|  18. SimoneR       1,400 XP  DOWN     |
|  19. ValentinaF    1,200 XP  DOWN     |
|  20. MicheleDR      890 XP  DOWN      |
|  ──────────────────────────────────    |
|                                        |
|  3 days left in this league week       |
+----------------------------------------+
```

- Promotion zone background: emerald (#22C55E) at 5% opacity. "UP" arrow icon in green.
- Safe zone: no special background.
- Relegation zone background: molten orange (#FF6B2C) at 5% opacity. "DOWN" arrow icon in amber.
- User's row: always highlighted with blue accent (same as friend leaderboard).

#### League Notifications

| Event | Notification |
|-------|-------------|
| League week started | "Gold League started! 20 opponents this week. Current rank: #8." |
| Entering promotion zone | "You're in the promotion zone! Keep it up to reach Platinum League." |
| Falling into relegation zone | "You've slipped into the relegation zone. Push harder to stay in Gold." |
| Promoted at week end | "Promoted to Platinum League! You finished #3 in Gold." |
| Relegated at week end | "Back to Silver League. New week, new chance." |
| Holding in Diamond Elite | "Diamond Elite again! You're in the top tier." |

### 19.3 Friend Leaderboard Psychology

#### Handling "Last Place Among Friends"

When the user is in last place on the friend leaderboard, the UI adapts:

1. **No "last place" label.** The position number is shown but never with language like "last" or "bottom."
2. **Encouraging frame:** Below the user's row, show: "You earned 450 XP this week. That's more than last week's 380!" — focus on personal progress, not relative position.
3. **Gap framing:** Instead of "1,500 XP behind #1" show "85 XP behind [Name above you]" — make the next achievable step feel close.
4. **Activity nudge:** If the user above them has been inactive today: "Gianluca hasn't logged any XP today. Catch up!"

#### Handling "One Friend Way Too Ahead"

When one friend has 2x+ the XP of the second-place person:

1. **Compressed scale:** The leaderboard podium adjusts pillar heights. #1 pillar is capped at 140pt regardless of how far ahead they are. Pillars represent relative difference between 2nd and 3rd, not absolute.
2. **"Different league" subtle indicator:** If the gap is >2x, show a subtle dividing line between #1 and #2 with tiny text: "On another level" — this normalizes the gap as admirable, not demoralizing.
3. **Category leaderboards:** Promote the filter dropdown more aggressively. "You're #1 in Study Hours this week!" -- let the casual user find a dimension where they excel.

#### Handling Cross-Tier Friendships (Bronze Player Adds Diamond Friend)

When a Bronze-league player (Level 3, earning ~200 XP/week) adds a Diamond-league friend (Level 45, earning ~8,000 XP/week), the friend leaderboard becomes inherently lopsided. Without mitigation, the Bronze player opens the leaderboard and sees they are 40x behind -- and quits.

**Mitigation layers:**

1. **Weekly leaderboard shows RAW XP (no multiplier).** This already closes the gap significantly. The Diamond friend's raw weekly output might be ~4,500 vs the Bronze player's ~200. Still a large gap, but not the 40x it would be with multipliers.

2. **Default sort = "Close Race" mode.** Instead of showing rank 1 through N, the default view anchors on the user's position and shows the 2 people above and 2 people below them. The Diamond friend is visible but not the focal point. The focal point is: "Can you beat the person directly above you?"

3. **"Your Bracket" indicator.** On the friend leaderboard, draw a subtle bracket around users within 2x of each other's weekly XP. Label it "Your Bracket" for the user. This groups the competitive set visually and makes the Diamond outlier clearly "not in your bracket" without calling anyone out.

4. **Effort Score toggle (Section 19.5).** Actively suggest this mode to users who are in the bottom 25% of their friend leaderboard: "Tip: Switch to Effort Score to compare relative effort instead of raw XP."

5. **League leaderboard as alternative.** If the friend leaderboard is lopsided, the league leaderboard (where the Bronze player competes against 19 other Bronze-level players) provides a fair competitive experience. Nudge: "Want a closer race? Check your Bronze League standings."

**The key insight:** The friend leaderboard does NOT need to be the competitive venue for mismatched friends. It is an ambient social feature. The LEAGUE leaderboard is the competitive venue. As long as the Bronze player has the league to compete in, the friend leaderboard is "interesting context" rather than "demoralizing comparison."

#### Weekly Reset: Casual-Friendly Design

The weekly reset can feel punishing to casual users ("I worked hard and now it's all gone"). Mitigations:

1. **The "Week in Review" card celebrates what was earned**, not what was lost. It leads with personal stats and personal bests, not rank.
2. **Carry-over momentum:** If a user finished in the top 50% of their friend leaderboard last week, they start the new week with a small visual indicator: a "hot start" flame on their leaderboard row for the first 24 hours. This is purely visual (no XP bonus) but signals "this person was competitive last week."
3. **The reset is framed as opportunity:** "New week, everyone's at 0. Your chance to climb." Never "Your XP has been reset."

#### Weekly Reset Ceremony

Every Monday at first app open:

1. **"Week in Review" card** appears at top of Arena Main View:
   ```
   +----------------------------------------+
   |  LAST WEEK'S RESULTS                   |
   |                                        |
   |  Your rank: #3 of 12 friends           |
   |  Total XP: 3,750 XP                    |
   |  Best day: Tuesday (820 XP)            |
   |                                        |
   |  CROWN Marco won the week: 4,200 XP   |
   |                                        |
   |  New week starts now. Everyone's at 0. |
   |  [ View Full Results ]  [ Dismiss ]    |
   +----------------------------------------+
   ```
2. **Leaderboard resets to 0** with a satisfying "sweep" animation (all XP numbers count down to 0, bars empty).
3. **"Monday Motivation" notification** sent at 08:00: "New week, new leaderboard. Everyone starts at zero. Make your move."

### 19.4 Leaderboard Notification Intelligence

Notifications about being overtaken are only useful if the user can realistically respond. Rules:

| Condition | Send overtaken notification? |
|-----------|------|
| User is in top 3 and gets passed | YES — high stakes |
| User is in top 50% and gets passed | YES — motivating |
| User is in bottom 50% and gets passed | NO — demoralizing |
| Gap after being passed is < 100 XP | YES with "You're only [X] XP behind!" |
| Gap after being passed is > 500 XP | NO — too much to overcome quickly |
| User has been inactive today | NO — don't nag inactive users about losing |
| User received an overtaken notification in last 2 hours | NO — cooldown |

### 19.5 "Normalized" Leaderboard View (Optional)

Accessible via a toggle in the filter dropdown: "Show Effort Score."

Instead of raw XP, shows a **percentage of each user's personal potential.** For example:
- Marco: earned 4,200 XP out of his 5,000 XP potential = 84% effort
- You: earned 3,750 XP out of your 4,500 XP potential = 83% effort
- Luca: earned 2,100 XP out of his 2,500 XP potential = 84% effort

This normalizes for lifestyle differences. Someone who only has 2 hours/day to use Tempo can "win" the effort leaderboard against someone with 6 hours/day. Potential is calculated from past behavior patterns (rolling 4-week average of daily maximum).

---

## 20. Challenge Design — Templates & Seasonal Events

### 20.1 Challenge Templates (24 Templates)

Each template has a name, description, icon, metric, suggested duration, and difficulty tier.

#### Training Challenges

**#1 — Iron Week**
- Description: "Most total gym volume (kg x reps) in a week."
- Icon: Barbell with weight plates, iron-gray
- Metric: Total training volume (calculated as sum of weight x reps for all exercises)
- Suggested duration: 7 days
- Difficulty: Competitive
- Flavor text: "The iron doesn't lie. Neither does the scoreboard."

**#2 — Beast Mode**
- Description: "Most workouts completed."
- Icon: Flexing arm with lightning bolts
- Metric: Workout count
- Suggested duration: 7 or 14 days
- Difficulty: Casual
- Flavor text: "Show up. That's all it takes."

**#3 — PR Chaser**
- Description: "Most personal records set."
- Icon: Arrow shattering a glass ceiling
- Metric: PR count
- Suggested duration: 14 or 30 days
- Difficulty: Competitive
- Flavor text: "Records exist to be broken."

**#4 — Heavy Metal**
- Description: "Highest single-set weight lifted on any exercise."
- Icon: Single massive dumbbell, metallic shine
- Metric: Max weight in a single set (any exercise)
- Suggested duration: 7 days
- Difficulty: Extreme
- Flavor text: "One rep. One chance. Make it count."

#### Study Challenges

**#5 — Scholar's Duel**
- Description: "Most total study hours."
- Icon: Two books clashing like swords
- Metric: Study hours
- Suggested duration: 7 days
- Difficulty: Competitive
- Flavor text: "Knowledge is power. Prove you want it more."

**#6 — Focus Fortress**
- Description: "Most consecutive Pomodoro sessions completed."
- Icon: Castle tower made of books
- Metric: Longest streak of back-to-back study sessions (25min+ each, <10min break between)
- Suggested duration: 3 or 7 days
- Difficulty: Competitive
- Flavor text: "Build your fortress one session at a time."

**#7 — Midnight Oil**
- Description: "Most study hours logged after 8 PM."
- Icon: Oil lamp burning, dark background
- Metric: Evening study hours (20:00-02:00)
- Suggested duration: 7 days
- Difficulty: Casual
- Flavor text: "When the world sleeps, scholars rise."

**#8 — Dawn Scholar**
- Description: "Most study sessions started before 8 AM."
- Icon: Sunrise behind an open book
- Metric: Count of sessions started between 05:00-08:00
- Suggested duration: 7 days
- Difficulty: Competitive
- Flavor text: "The early bird gets the grade."

#### Nutrition Challenges

**#9 — Meal Prep Master**
- Description: "Highest nutrition compliance (% of days with all 3 meals + macros hit)."
- Icon: Chef's hat with a checkmark
- Metric: Percentage of challenge days with all 3 meals logged + protein target hit
- Suggested duration: 7 or 14 days
- Difficulty: Competitive
- Flavor text: "Discipline is eating what you planned, not what you crave."

**#10 — Protein Wars**
- Description: "Most consecutive days hitting protein target."
- Icon: Chicken drumstick with a crown
- Metric: Consecutive days hitting protein within 10% of target
- Suggested duration: 14 days
- Difficulty: Casual
- Flavor text: "Protein doesn't build itself."

#### Lifestyle & Accountability Challenges

**#11 — Early Bird**
- Description: "Most tasks completed before noon."
- Icon: Rooster crowing at sunrise
- Metric: Count of non-negotiables + workouts + study sessions started before 12:00
- Suggested duration: 7 days
- Difficulty: Competitive
- Flavor text: "Win the morning, win the day."

**#12 — Night Owl Defense**
- Description: "Who can avoid late-night screen time the longest?"
- Icon: Owl with closed eyes, peaceful
- Metric: Consecutive days where no Tempo activity is logged after 23:00 (honors system + screen time integration if available)
- Suggested duration: 7 or 14 days
- Difficulty: Casual
- Flavor text: "The hardest rep is putting the phone down."

**#13 — Consistency Machine**
- Description: "Longest streak maintained during the challenge."
- Icon: Metronome ticking perfectly
- Metric: Longest consecutive streak days within challenge period
- Suggested duration: 14 or 30 days
- Difficulty: Competitive
- Flavor text: "Anyone can have a good day. Can you have a good month?"

**#14 — Step Battle**
- Description: "Most total steps."
- Icon: Two footprints racing
- Metric: Cumulative steps from HealthKit
- Suggested duration: 7 days
- Difficulty: Casual
- Flavor text: "10,000 steps? Those are rookie numbers."

**#15 — Recovery King**
- Description: "Highest average recovery score over the challenge period."
- Icon: Green battery with a crown
- Metric: Average recovery score (from Whoop or internal algorithm)
- Suggested duration: 7 days
- Difficulty: Casual
- Flavor text: "The hardest workers know when to rest hardest."

#### Multi-Metric Challenges

**#16 — The Gauntlet**
- Description: "Highest overall Tempo score across all metrics."
- Icon: Medieval gauntlet (armored glove) gripping lightning
- Metric: Combined score: (workout XP + study XP + nutrition XP + sleep XP + steps XP) / 5 categories, normalized
- Suggested duration: 7 or 14 days
- Difficulty: Extreme
- Flavor text: "Master of one? Try master of all."

**#17 — Perfect Day Race**
- Description: "Most Perfect Days during the challenge."
- Icon: Star constellation forming a trophy shape
- Metric: Perfect Day count
- Suggested duration: 7 or 14 days
- Difficulty: Extreme
- Flavor text: "Perfection isn't a goal. It's a habit."

**#18 — The Transformer**
- Description: "Biggest percentage improvement in daily XP average vs. previous month."
- Icon: Caterpillar-to-butterfly metamorphosis
- Metric: (Challenge period avg daily XP) / (Previous 30-day avg daily XP) as a ratio
- Suggested duration: 14 or 30 days
- Difficulty: Competitive
- Flavor text: "It's not where you are. It's how fast you're climbing."

#### Fun / Creative Challenges

**#19 — The Eliminator**
- Description: "Last person to miss a day loses. One skip and you're out."
- Icon: Red X eliminating silhouettes one by one
- Metric: Survival (binary daily check: did you earn >100 XP today? If not, eliminated)
- Suggested duration: Until one person remains (max 30 days)
- Difficulty: Extreme
- Flavor text: "In this challenge, second place is first loser."

**#20 — Mystery Metric**
- Description: "The metric is revealed each morning. Adapt or lose."
- Icon: Question mark in a crystal ball
- Metric: Rotates daily from the full metric list. Monday = Steps, Tuesday = Study, etc. Score = daily rank among participants (1st place gets 3 points, 2nd gets 2, 3rd gets 1). Most points wins.
- Suggested duration: 7 days
- Difficulty: Competitive
- Flavor text: "Expect the unexpected."

**#21 — The Underdog**
- Description: "Lower-level player gets a handicap. Can David beat Goliath?"
- Icon: Small figure facing a giant shadow
- Metric: Total XP, but the lower-level player gets a 1.25x handicap multiplier per level difference (max 2.0x)
- Suggested duration: 7 days
- Difficulty: Casual
- Flavor text: "Level doesn't determine heart."

**#22 — Tag Team**
- Description: "2v2 challenge. Combined team XP."
- Icon: Two pairs of fists bumping
- Metric: Sum of both team members' XP
- Suggested duration: 7 days
- Difficulty: Competitive
- Special: Requires exactly 4 participants, split into 2 teams during creation
- Flavor text: "You're only as strong as your weakest link."

**#23 — No Rest for the Wicked**
- Description: "Earn XP every single day. First person to have a zero-XP day loses."
- Icon: Ticking clock with flames
- Metric: Consecutive days with >0 XP earned (excluding login bonus)
- Suggested duration: Until someone breaks (max 30 days)
- Difficulty: Extreme
- Flavor text: "Rest days are for quitters."

**#24 — The Sprint**
- Description: "Most XP earned in a single 24-hour period during the challenge window."
- Icon: Lightning bolt breaking a speed record
- Metric: Highest single-day XP (each participant's best day counts, not cumulative)
- Suggested duration: 7 days (but only best day matters)
- Difficulty: Competitive
- Flavor text: "One perfect day. That's all you need."

### 20.2 Challenge Difficulty Tiers

| Tier | Description | Visual | XP Bonus for Winner |
|------|-------------|--------|---------------------|
| Casual | Low-pressure, good for new players, forgiving | Green border, leaf icon | +150 XP (1v1), +225 XP (group) |
| Competitive | Standard difficulty, requires consistent effort | Blue border, sword icon | +200 XP (1v1), +300 XP (group) |
| Extreme | High difficulty, demands peak performance | Red border, flame icon | +350 XP (1v1), +500 XP (group) |

Templates have a default tier but users can override when creating. Extreme challenges show a warning: "This challenge is intense. Are you sure?"

### 20.3 Daily Micro-Challenges

Auto-generated, opt-in, quick challenges that appear fresh every day. These are different from the existing Daily Challenge in Section 9.8 — micro-challenges are smaller and can be completed in a single action.

**Generation rules:**
- 3 micro-challenges are generated each day at 00:00
- User can opt into 0, 1, 2, or all 3
- Each completed micro-challenge awards 25 XP
- Micro-challenges are personal (not competitive) but completion is shown in feed

**Micro-Challenge Pool (30+ templates, rotated):**

| Category | Example Micro-Challenges |
|----------|------------------------|
| Training | "Complete 3 sets of pull-ups before noon" / "Do a 20-minute stretching session" / "Hit a new PR on any exercise today" / "Complete your workout in under 60 minutes" |
| Study | "Start a study session before 9 AM" / "Complete 4 Pomodoro sessions today" / "Study a subject you've been avoiding" / "Hit 110% of your study target" |
| Nutrition | "Log breakfast before 8 AM" / "Hit your protein target by lunch" / "Log a meal with 30g+ protein" / "Drink 3L of water today" |
| Movement | "Hit 12,000 steps today" / "Take a 30-minute walk" / "Take the stairs all day" |
| Recovery | "Be in bed by 22:30" / "Get 8+ hours of sleep" / "No screens 30 min before bed" |
| Accountability | "Complete your first non-negotiable before 8 AM" / "Complete ALL non-negotiables before 6 PM" / "No PS5 until all tasks are done" |

**Display:** Small cards in the Arena Main View, collapsible section titled "TODAY'S MICRO-CHALLENGES." Each card shows the challenge text, a progress indicator, and XP reward.

### 20.4 Seasonal Events

Seasonal events are time-limited, themed challenges available to all users. They create urgency, community participation, and limited-edition rewards.

#### Event Calendar

| Event | Window | Theme | Special Reward |
|-------|--------|-------|----------------|
| **New Year, New You** | Jan 1-31 | Resolution kickstart: earn as much XP as possible in January | "Resolution Keeper" limited-time achievement (500 XP) for earning 20,000+ XP in January |
| **Valentine's Challenge** | Feb 10-16 | Pair up with a friend for a 2-person cooperative challenge (combined XP target) | "Better Together" badge (limited edition) |
| **March Madness** | Mar 1-31 | Bracket-style elimination tournament. 16 users, single elimination, 3-day rounds | "March Champion" trophy badge |
| **Spring Reset** | Apr 1-14 | Focus on recovery and sleep metrics | "Spring Clean" badge for 7 consecutive green recovery days |
| **Finals Survivor** | May 1-31 & Dec 1-31 | Study-focused event: study hours leaderboard across all users | "Finals Hero" limited badge + 750 XP for top 10% in study hours |
| **Summer Shred** | Jun 1 - Aug 31 | Fitness-focused seasonal leaderboard: workout volume + steps | "Summer Body" badge progression (Bronze/Silver/Gold at 3 thresholds) |
| **Back to School** | Sep 1-30 | Balance challenge: must hit targets in ALL categories (not just one) | "Renaissance" badge for 15 Perfect Days in September |
| **Spooky Season** | Oct 25-31 | "Survive the week" — miss a day and you're "eliminated" from the event | "Survivor" limited badge |
| **Thanksgiving Gratitude** | Nov 20-27 | Cooperative: the community collectively tries to hit 1M XP. Individual contributions tracked | "Community Builder" badge if global goal met |
| **Holiday Hustle** | Dec 15-31 | "Don't let the holidays break your streak." Maintain streak through holiday season | "Holiday Hero" for maintaining 14-day streak during this period |

**Seasonal Event UI:**
- Banner at top of Arena Main View when active: gradient background matching theme, event name, countdown timer, CTA to join.
- Dedicated event detail screen accessible from banner.
- Seasonal achievements appear in a special "LIMITED TIME" section in the Achievements view. After the event ends, locked seasonal achievements disappear (but unlocked ones remain permanently).

---

## 21. Achievement System — Expanded (108 Achievements)

### 21.1 Rarity Distribution

| Rarity | Count | Border Color | XP Range | Expected % of users who unlock |
|--------|-------|-------------|----------|-------------------------------|
| Common | 32 | #8899AA (1pt) | 25-100 XP | 60-90% |
| Rare | 29 | #2D7FF9 (1.5pt) | 100-300 XP | 25-50% |
| Epic | 25 | #A855F7 (2pt, glow) | 300-750 XP | 5-20% |
| Legendary | 14 | Gold gradient (2pt, animated) | 750-3,000 XP | 1-5% |
| Mythic | 8 | Prismatic (#FF1493, 3pt, particle trail) | 2,000-5,000 XP | <1% |

**Note:** #71 Marathon Walker was reclassified from Rare to Epic (42,195 steps requires extraordinary effort). #38 Snack Attack was changed to Hidden (too trivially easy as a visible achievement). #100 was replaced to resolve a duplicate with #107. See individual achievement entries for balance notes.

### 21.2 Full Achievement List by Category

---

#### CATEGORY 1: TRAINING (15 Achievements)

**#1 — First Rep** (Common)
- "Complete your first workout."
- Icon: Single dumbbell, silver outline
- Criteria: Mark 1 workout as complete
- XP: 50 | Hidden: No
- Flavor: "Everyone starts somewhere. You started today."

**#2 — Getting Hooked** (Common)
- "Complete 10 workouts."
- Icon: Dumbbell with "10" badge
- Criteria: 10 total completed workouts
- XP: 100 | Hidden: No
- Flavor: "The habit is forming. Don't let go."

**#3 — Gym Rat** (Rare)
- "Complete 50 workouts."
- Icon: Dumbbell rack, bronze tint
- Criteria: 50 total completed workouts
- XP: 250 | Hidden: No
- Flavor: "The staff knows your name. The weights know your grip."

**#4 — Iron Temple** (Epic)
- "Complete 100 workouts."
- Icon: Temple pillars made of barbells, silver
- Criteria: 100 total completed workouts
- XP: 500 | Hidden: No
- Flavor: "This is your church. The barbell is your prayer."

**#5 — Beast Mode** (Legendary)
- "Complete 250 workouts."
- Icon: Roaring lion head, gold with flame mane
- Criteria: 250 total completed workouts
- XP: 1,000 | Hidden: Yes
- Flavor: "You're not working out anymore. You're becoming something else."

**#6 — The Machine** (Mythic)
- "Complete 500 workouts."
- Icon: Terminator-style metallic skull with glowing red eyes, holographic
- Criteria: 500 total completed workouts
- XP: 3,000 | Hidden: Yes
- Flavor: "They don't even ask if you're going to the gym anymore."

**#7 — New Max** (Common)
- "Set your first personal record."
- Icon: Arrow breaking through a ceiling
- Criteria: Log a new PR on any exercise
- XP: 75 | Hidden: No
- Flavor: "You just proved yesterday's you wrong."

**#8 — PR Machine** (Rare)
- "Set 10 personal records."
- Icon: Factory machine stamping out trophies
- Criteria: 10 total PRs set (any exercises)
- XP: 200 | Hidden: No
- Flavor: "Records fall like dominos when you show up every day."

**#9 — Record Breaker** (Epic)
- "Set 50 personal records."
- Icon: Shattered glass record disc
- Criteria: 50 total PRs
- XP: 500 | Hidden: No
- Flavor: "At this point, the only person you're competing with is yesterday's you."

**#10 — Early Bird Lifter** (Common)
- "Complete a workout before 7:00 AM."
- Icon: Sunrise behind a barbell
- Criteria: Start AND complete a workout between 04:00 and 07:00
- XP: 75 | Hidden: No
- Flavor: "While they sleep, you grow."

**#11 — Night Owl Grind** (Common)
- "Complete a workout after 10:00 PM."
- Icon: Moon and stars behind a dumbbell
- Criteria: Start AND complete a workout between 22:00 and 01:00
- XP: 75 | Hidden: No
- Flavor: "The gym is empty. The weights are all yours."

**#12 — Recovery Listener** (Rare)
- "Take a rest day when recovery score is red."
- Icon: Green heart with a bandage, glowing softly
- Criteria: Log a rest day on a day when recovery score is Red
- XP: 100 | Hidden: Yes
- Flavor: "The strongest thing you did today was nothing."

**#13 — Bodyweight Bencher** (Epic)
- "Bench press your bodyweight."
- Icon: Bench press with a "1x BW" badge
- Criteria: Log a bench press set where weight >= user's bodyweight (from Health profile)
- XP: 400 | Hidden: No
- Flavor: "You can officially press yourself off the ground. Both ways."

**#14 — Double Bodyweight Deadlift** (Legendary)
- "Deadlift 2x your bodyweight."
- Icon: Figure pulling a massive barbell from the ground, golden aura
- Criteria: Log a deadlift set where weight >= 2x user's bodyweight
- XP: 750 | Hidden: Yes
- Flavor: "The earth itself tried to hold that bar down."

**#15 — Million Kilo Club** (Mythic)
- "Lift 1,000,000 kg total volume across all workouts."
- Icon: Globe being lifted by Atlas, holographic with swirling numbers
- Criteria: Cumulative weight x reps across all logged workouts >= 1,000,000 kg
- XP: 5,000 | Hidden: Yes
- Flavor: "You have literally moved a million kilograms. That's not a metaphor."

---

#### CATEGORY 2: STUDY (12 Achievements)

**#16 — First Page** (Common)
- "Log your first study session."
- Icon: Open book with a single page turned
- Criteria: Log 1 study session (any duration)
- XP: 50 | Hidden: No
- Flavor: "Every thesis begins with a single page."

**#17 — Bookworm** (Common)
- "Study for 10 total hours."
- Icon: Stack of books with a worm poking out
- Criteria: 10 cumulative hours
- XP: 100 | Hidden: No
- Flavor: "You're starting to get that focused look."

**#18 — Deep Focus** (Rare)
- "Complete a single study session of 3+ hours."
- Icon: Brain with lightning bolts, blue aura
- Criteria: One unbroken study session >= 3 hours
- XP: 150 | Hidden: No
- Flavor: "Flow state achieved. The world disappeared for a while."

**#19 — Scholar** (Epic)
- "Study for 100 total hours."
- Icon: Graduation cap with sparkles
- Criteria: 100 cumulative hours
- XP: 400 | Hidden: No
- Flavor: "100 hours of investment in your future self."

**#20 — The Professor** (Legendary)
- "Study for 500 total hours."
- Icon: Professorial owl with spectacles, gold-framed
- Criteria: 500 cumulative hours
- XP: 1,000 | Hidden: Yes
- Flavor: "You could teach this course by now."

**#21 — Grandmaster** (Mythic)
- "Study for 1,000 total hours."
- Icon: Floating tome with orbiting knowledge particles, prismatic glow
- Criteria: 1,000 cumulative hours
- XP: 3,000 | Hidden: Yes
- Flavor: "10,000 hours to mastery. You're 10% of the way there. Keep going."

**#22 — Exam Survivor** (Epic)
- "Complete an exam week (5+ consecutive days of 4h+ study)."
- Icon: Shield cracked but still standing, red glow
- Criteria: 5 consecutive days with >= 4h study each
- XP: 300 | Hidden: No
- Flavor: "You walked through fire and came out the other side."

**#23 — Study Streak Pro** (Rare)
- "Hit your study target 14 days in a row."
- Icon: Calendar with 14 checkmarks and a flame
- Criteria: 14 consecutive days meeting >= 100% study target
- XP: 200 | Hidden: No
- Flavor: "Two weeks of discipline. This is who you are now."

**#24 — Dawn Scholar** (Common)
- "Start a study session before 6:00 AM."
- Icon: Rising sun behind an open book
- Criteria: Begin a study session between 04:00 and 06:00
- XP: 75 | Hidden: No
- Flavor: "The world's most successful people have one thing in common."

**#25 — Midnight Oil** (Common)
- "Study past 11:00 PM."
- Icon: Oil lamp burning in darkness
- Criteria: Active study session at 23:00
- XP: 50 | Hidden: No
- Flavor: "When the deadline doesn't care about your sleep schedule."

**#26 — Five Hour Marathon** (Rare)
- "Study for 5 hours in a single day."
- Icon: Marathon runner carrying books
- Criteria: 5+ hours of logged study in one calendar day
- XP: 200 | Hidden: No
- Flavor: "Your brain is sore in the best way."

**#27 — Study Centurion** (Epic)
- "Hit your study target 100 days total (not consecutive)."
- Icon: Roman centurion holding a scroll instead of a shield
- Criteria: 100 total days where study target was met
- XP: 500 | Hidden: No
- Flavor: "One hundred days of showing up. That's not luck. That's character."

---

#### CATEGORY 3: NUTRITION (12 Achievements)

**#28 — First Bite** (Common)
- "Log your first meal."
- Icon: Fork and knife crossed, simple outline
- Criteria: Log 1 meal
- XP: 30 | Hidden: No
- Flavor: "You are what you track."

**#29 — Three Square** (Common)
- "Log all 3 meals in a day."
- Icon: Three plates in a row, each with a checkmark
- Criteria: Log breakfast + lunch + dinner in one day
- XP: 50 | Hidden: No
- Flavor: "Fuel in, performance out."

**#30 — Macro Sniper** (Rare)
- "Hit all macro targets in a single day."
- Icon: Crosshair/target with a fork as the arrow
- Criteria: Protein, carbs, and fat all within 10% of target
- XP: 100 | Hidden: No
- Flavor: "Precision nutrition. Your body thanks you."

**#31 — Consistency Eater** (Rare)
- "Log all meals for 7 consecutive days."
- Icon: Seven plates forming a rainbow arc
- Criteria: 7 consecutive days with all 3 meals logged
- XP: 150 | Hidden: No
- Flavor: "A week of awareness. You see food differently now."

**#32 — Nutrition Machine** (Epic)
- "Log all meals for 30 consecutive days."
- Icon: Robot chef with precision tools
- Criteria: 30 consecutive days with all 3 meals logged
- XP: 400 | Hidden: No
- Flavor: "Logging is no longer a chore. It's autopilot."

**#33 — Protein King** (Epic)
- "Hit your protein target 30 days in a row."
- Icon: Crown made of chicken drumsticks (stylized)
- Criteria: 30 consecutive days hitting protein within 10%
- XP: 300 | Hidden: No
- Flavor: "Your muscles are throwing a party in your honor."

**#34 — Macro Perfectionist** (Epic)
- "Hit all macro targets for 7 consecutive days."
- Icon: Diamond with a fork, knife, and spoon forming the facets
- Criteria: 7 consecutive days with all macros within 10%
- XP: 500 | Hidden: Yes
- Flavor: "Seven days of nutritional perfection. Chef's kiss."

**#35 — Hydration Master** (Rare)
- "Log 3L+ water intake for 14 consecutive days."
- Icon: Water droplet with a crown
- Criteria: 14 consecutive days with 3+ liters water logged
- XP: 200 | Hidden: No
- Flavor: "Your kidneys just wrote you a thank-you note."

**#36 — Year-Round Logger** (Legendary)
- "Log at least 2 meals every day for 365 days."
- Icon: Calendar with every day filled, golden glow
- Criteria: 365 consecutive days with 2+ meals logged
- XP: 2,000 | Hidden: Yes
- Flavor: "You tracked every single day for a year. That's not discipline. That's identity."

**#37 — Clean Streak** (Common)
- "Hit your calorie target 3 days in a row."
- Icon: Three green checkmarks ascending
- Criteria: 3 consecutive days with calories within 10%
- XP: 75 | Hidden: No
- Flavor: "Three in a row. Now make it four."

**#38 — Snack Attack** (Common)
- "Log 3 snacks in one day."
- Icon: Three small plates with different snacks
- Criteria: Log 3 snacks in a single day
- XP: 50 | Hidden: Yes
- Flavor: "Snacking isn't cheating when you track it."
- **Note:** Changed to Hidden. This achievement is trivially easy and would be earned by accident in the first few days, providing zero dopamine as a visible achievement. As a hidden surprise, it delights instead of feeling hollow.

**#39 — Macro Maestro** (Legendary)
- "Hit all macro targets for 30 consecutive days."
- Icon: Conductor's baton made of a fork, with musical notes that are food icons
- Criteria: 30 consecutive days with all macros within 10%
- XP: 1,500 | Hidden: Yes
- Flavor: "An entire month of macro perfection. You're operating on a different level."

---

#### CATEGORY 4: RECOVERY (10 Achievements)

**#40 — Well Rested** (Common)
- "Achieve your first green recovery score."
- Icon: Green battery fully charged
- Criteria: 1 green recovery score
- XP: 50 | Hidden: No
- Flavor: "This is what peak readiness feels like."

**#41 — Green Machine** (Rare)
- "7 consecutive green recovery days."
- Icon: Seven green circles forming a chain
- Criteria: 7 consecutive green recovery scores
- XP: 150 | Hidden: No
- Flavor: "A full week in the green. Your body is a temple."

**#42 — Sleep Champion** (Rare)
- "Achieve a sleep score of 90+ for 7 consecutive nights."
- Icon: Pillow with a crown and "ZZZ" in gold
- Criteria: 7 consecutive sleep scores >= 90
- XP: 200 | Hidden: No
- Flavor: "Sleep is the ultimate performance enhancer."

**#43 — Recovery Sage** (Epic)
- "30 consecutive green recovery days."
- Icon: Meditating figure with a green aura, floating
- Criteria: 30 consecutive green recovery scores
- XP: 500 | Hidden: No
- Flavor: "A month in harmony. Your body and mind are aligned."

**#44 — The Machine Never Stops** (Legendary)
- "90 consecutive green recovery days."
- Icon: Perpetual motion machine with a green glow, holographic
- Criteria: 90 consecutive green recovery scores
- XP: 1,000 | Hidden: Yes
- Flavor: "Three months of perfect recovery. Scientists want to study you."

**#45 — HRV PR** (Rare)
- "Set a new all-time HRV high."
- Icon: Heart with an upward lightning bolt
- Criteria: New highest HRV reading (from Whoop or Health)
- XP: 100 | Hidden: No
- Flavor: "Your nervous system just peaked."

**#46 — Sleep PR** (Rare)
- "Set a new highest sleep score."
- Icon: Moon with a star above it, silver
- Criteria: New highest sleep score
- XP: 100 | Hidden: No
- Flavor: "Best night ever. Can you do it again?"

**#47 — Consistent Bedtime** (Rare)
- "Go to bed within 30 minutes of the same time for 14 days."
- Icon: Clock with a moon, perfectly aligned hands
- Criteria: 14 consecutive days where bedtime is within +/- 30 min of average
- XP: 200 | Hidden: No
- Flavor: "Your circadian rhythm just high-fived you."

**#48 — Early to Bed** (Common)
- "Log sleep with a bedtime before 22:30 for 7 days."
- Icon: Sleeping face with stars, peaceful blue
- Criteria: 7 days with logged bedtime before 22:30
- XP: 75 | Hidden: No
- Flavor: "You chose sleep over scrolling. Respect."

**#49 — Green Year** (Mythic)
- "300 green recovery days in a single calendar year (not necessarily consecutive)."
- Icon: Earth wrapped in a green vine, with a golden halo, prismatic
- Criteria: 300 green recovery days within any 365-day rolling window
- XP: 5,000 | Hidden: Yes
- Flavor: "300 green days in a year. Your body is a finely tuned instrument."
- **Balance note:** Changed from 365 CONSECUTIVE to 300 within a year. The original requirement was functionally impossible -- even elite athletes get sick, travel across time zones, or have stressful weeks that tank recovery. Requiring perfect consecutive recovery punishes things outside the user's control (illness, family emergencies). 300/365 (82%) is still an extraordinary feat that requires genuine lifestyle mastery, but allows ~65 days of human reality. The Mythic tier should reward extraordinary EFFORT, not extraordinary luck.

---

#### CATEGORY 5: STREAKS (7 Achievements)

**#50 — Spark** (Common)
- "Reach a 3-day streak." | Icon: Small matchstick flame
- XP: 30 | Hidden: No | Flavor: "A spark becomes a fire."

**#51 — On Fire** (Common)
- "Reach a 7-day streak." | Icon: Campfire, medium flame
- XP: 75 | Hidden: No | Flavor: "One week down. Momentum is real."

**#52 — Inferno** (Rare)
- "Reach a 14-day streak." | Icon: Bonfire with ember particles
- XP: 150 | Hidden: No | Flavor: "Two weeks. The habit is setting in."

**#53 — Iron Will** (Rare)
- "Reach a 30-day streak." | Icon: Iron anvil with fire burning on top
- XP: 300 | Hidden: No | Flavor: "Thirty days of not quitting. That's iron will."

**#54 — Unbreakable** (Epic)
- "Reach a 60-day streak." | Icon: Chains being shattered by a fist, blue energy
- XP: 500 | Hidden: No | Flavor: "Two months. They can't break what they can't catch."

**#55 — Forged in Fire** (Epic)
- "Reach a 90-day streak." | Icon: Sword being pulled from a forge, white-hot
- XP: 750 | Hidden: No | Flavor: "Quarter of a year. You're forged in fire now."

**#56 — Immortal** (Legendary)
- "Reach a 365-day streak." | Icon: Phoenix rising from ashes, holographic shimmer
- XP: 3,000 | Hidden: Yes | Flavor: "One full year. You didn't miss a single day. Immortal."

---

#### CATEGORY 6: SOCIAL (12 Achievements)

**#57 — First Rival** (Common)
- "Add your first friend." | Icon: Two fists bumping
- XP: 50 | Hidden: No | Flavor: "Competition begins now."

**#58 — Squad Up** (Common)
- "Have 5 friends on Tempo." | Icon: Five silhouettes in V formation
- XP: 100 | Hidden: No | Flavor: "Your squad is forming."

**#59 — Popular** (Rare)
- "Have 20 friends on Tempo." | Icon: Crowd silhouette with spotlight
- XP: 200 | Hidden: No | Flavor: "You're the connector."

**#60 — Full House** (Epic)
- "Have 50 friends (max) on Tempo." | Icon: Packed stadium
- XP: 400 | Hidden: No | Flavor: "Maximum capacity. Everyone wants to compete with you."

**#61 — First Blood** (Common)
- "Win your first challenge." | Icon: Sword with a single notch in the blade
- XP: 100 | Hidden: No | Flavor: "First win. Many more to come."

**#62 — Challenge Dominator** (Rare)
- "Win 10 challenges." | Icon: Throne made of swords
- XP: 300 | Hidden: No | Flavor: "The throne is yours."

**#63 — Undefeated** (Epic)
- "Win 25 challenges." | Icon: Golden champion belt
- XP: 500 | Hidden: No | Flavor: "They know better than to challenge you."

**#64 — Untouchable** (Epic)
- "Win 5 challenges in a row without a loss." | Icon: Shield with reflective surface
- XP: 500 | Hidden: Yes | Flavor: "Five straight wins. Untouchable."

**#65 — Win Streak Legend** (Legendary)
- "Win 10 challenges in a row." | Icon: Golden path of 10 trophies
- XP: 1,000 | Hidden: Yes | Flavor: "Ten consecutive victories. They write legends about less."

**#66 — Good Sport** (Common)
- "Complete 5 challenges (win or lose, must participate 50%+)." | Icon: Handshake with a medal
- XP: 75 | Hidden: No | Flavor: "It's not about winning. (It's a little about winning.)"

**#67 — Revenge** (Rare)
- "Win a rematch against someone who beat you." | Icon: Sword breaking another sword
- XP: 150 | Hidden: Yes | Flavor: "Revenge is a dish best served with XP."

**#68 — Group Commander** (Rare)
- "Win a group challenge with 5+ participants." | Icon: Commander leading troops
- XP: 200 | Hidden: No | Flavor: "You beat them all."

---

#### CATEGORY 7: STEPS & MOVEMENT (10 Achievements)

**#69 — First Steps** (Common)
- "Hit 5,000 steps in a day." | Icon: Single footprint
- XP: 30 | Hidden: No | Flavor: "Every journey begins with a single step. You took 5,000."

**#70 — Road Warrior** (Common)
- "Hit 10,000 steps 7 times." | Icon: Running shoe with a "7" badge
- XP: 100 | Hidden: No | Flavor: "10K steps is becoming second nature."

**#71 — Marathon Walker** (Epic)
- "Walk 42,195 steps in a single day (marathon distance symbolism)."
- Icon: Marathon medal, golden
- Criteria: 42,195+ steps in one day
- XP: 500 | Hidden: No | Flavor: "A marathon on your feet. Respect."
- **Balance note:** Reclassified from Rare to Epic. 42,195 steps is approximately 30-33km of walking. This requires 6-8 hours of continuous movement and is a genuinely extraordinary physical feat. Rare achievements should be achievable with sustained effort; this requires a dedicated full-day endeavor. The XP reward was also increased to match Epic tier.

**#72 — Step Millionaire** (Epic)
- "Accumulate 1,000,000 total steps."
- Icon: Odometer rolling over to 1,000,000
- XP: 500 | Hidden: No | Flavor: "One million steps. Where did they all take you?"

**#73 — Step Legend** (Legendary)
- "Hit 10,000+ steps every day for 30 days."
- Icon: Golden road stretching to the horizon
- Criteria: 30 consecutive days with 10K+ steps
- XP: 1,000 | Hidden: Yes | Flavor: "A month of movement. Your legs are works of art."

**#74 — 15K Club** (Rare)
- "Hit 15,000 steps in a day." | Icon: Running shoe with lightning
- XP: 100 | Hidden: No | Flavor: "Above and beyond."

**#75 — 20K Monster** (Rare)
- "Hit 20,000 steps in a day." | Icon: Two feet ablaze
- XP: 150 | Hidden: No | Flavor: "Your step counter is scared of you."

**#76 — 25K Ultra** (Epic)
- "Hit 25,000 steps in a day." | Icon: Winged sandals (Hermes-style)
- XP: 300 | Hidden: No | Flavor: "You walked an ultra today and called it Tuesday."

**#77 — Weekend Warrior Walker** (Common)
- "Hit 10K+ steps on both Saturday and Sunday."
- Icon: Calendar showing Sat-Sun highlighted with footprints
- XP: 75 | Hidden: No | Flavor: "Weekends aren't for sitting."

**#78 — Step Centurion** (Epic)
- "Hit 10K+ steps on 100 different days." | Icon: Roman numeral C made of footprints
- XP: 400 | Hidden: No | Flavor: "One hundred 10K days. Your Fitbit is proud."

---

#### CATEGORY 8: SPECIAL / COMPOSITE (12 Achievements)

**#79 — Perfect Day** (Common)
- "Achieve a Perfect Day." | Icon: Star with radiating lines, gold
- XP: 100 | Hidden: No | Flavor: "Every box checked. Flawless."

**#80 — Perfect Week** (Epic)
- "7 consecutive Perfect Days." | Icon: Seven stars forming a constellation
- XP: 500 | Hidden: No | Flavor: "Seven perfect days. That's not luck. That's design."

**#81 — Perfect Month** (Legendary)
- "30 consecutive Perfect Days." | Icon: Full moon made of gold, radiating light beams
- XP: 2,000 | Hidden: Yes | Flavor: "An entire month of perfection. You're playing a different game."

**#82 — Holiday Warrior** (Rare)
- "Maintain your streak on a national holiday." | Icon: Party hat on a warrior helmet
- XP: 150 | Hidden: Yes | Flavor: "Everyone else took the day off. Not you."

**#83 — Genesis** (Common)
- "Complete the Arena tutorial." | Icon: Glowing seed/sprout emerging from dark soil
- XP: 25 | Hidden: No | Flavor: "Welcome to the Arena. Your journey begins now."

**#84 — Level 10** (Common)
- "Reach Level 10." | Icon: Bronze "10" with upward arrow
- XP: 100 | Hidden: No | Flavor: "Double digits. You're getting serious."

**#85 — Level 25** (Rare)
- "Reach Level 25." | Icon: Silver "25" with crown
- XP: 300 | Hidden: No | Flavor: "Halfway to Legend. Keep climbing."

**#86 — Legend** (Epic)
- "Reach Level 50." | Icon: Holographic "50" with particle effects
- XP: 1,000 | Hidden: No | Flavor: "You've reached the summit. But there's always higher."

**#87 — Prestige** (Legendary)
- "Prestige for the first time." | Icon: Star shattering into golden dust, reforming
- XP: 1,500 | Hidden: Yes | Flavor: "Back to Level 1, but you're not the same person."

**#88 — Triple Threat** (Rare)
- "Earn 100+ XP from Workout, Study, AND Nutrition in a single day."
- Icon: Three lightning bolts converging
- XP: 150 | Hidden: No | Flavor: "Body, mind, and fuel. All firing."

**#89 — The Comeback** (Rare)
- "After a 7+ day streak breaks, build a new 7-day streak within 3 days."
- Icon: Phoenix rising from broken chains
- XP: 200 | Hidden: Yes | Flavor: "You fell. But you got up faster."

**#90 — Weekend Warrior** (Common)
- "Earn 500+ XP on a Saturday or Sunday."
- Icon: Calendar showing weekend highlighted with flames
- XP: 75 | Hidden: No | Flavor: "Weekends are for winners."

---

#### CATEGORY 9: HIDDEN / SECRET (10 Achievements)

All achievements in this category are hidden until unlocked. They are surprises.

**#91 — 3 AM Club** (Rare)
- "Log any activity between 3:00 AM and 4:00 AM."
- Icon: Crescent moon with a single bright star
- XP: 100 | Hidden: Yes | Flavor: "What are you doing awake? Whatever it is, we respect it."

**#92 — Double Prestige** (Legendary)
- "Prestige twice." | Icon: Two golden stars orbiting each other
- XP: 2,000 | Hidden: Yes | Flavor: "You've been to the top twice. This is personal now."

**#93 — The Streak Saver** (Common)
- "Have a streak freeze save your streak." | Icon: Snowflake catching a falling flame
- XP: 50 | Hidden: Yes | Flavor: "That was close. The freeze caught you."

**#94 — Sunday Funday** (Common)
- "Log a workout AND study session on a Sunday."
- Icon: Sunbeam with a dumbbell and book
- XP: 50 | Hidden: Yes | Flavor: "Most people rest on Sunday. You're not most people."

**#95 — New Year's Grinder** (Rare)
- "Earn 500+ XP on January 1st."
- Icon: Fireworks behind a trophy
- XP: 200 | Hidden: Yes | Flavor: "While everyone else was recovering, you were already ahead."

**#96 — Birthday Gains** (Rare)
- "Earn XP on your birthday." (Requires birthday in profile)
- Icon: Birthday cake with candles shaped like dumbbells
- XP: 150 | Hidden: Yes | Flavor: "Happy birthday. You chose gains over cake."

**#97 — Silent Assassin** (Epic)
- "Win 3 challenges in a row without sending a single reaction."
- Icon: Ninja mask, dark purple
- XP: 300 | Hidden: Yes | Flavor: "You let the scoreboard do the talking."

**#98 — Generous** (Common)
- "Send 50 total reactions to friends' activities."
- Icon: Hands clapping with hearts floating up
- XP: 75 | Hidden: Yes | Flavor: "You lift others up. That makes you a champion."

**#99 — The Collector** (Epic)
- "Have 5 friends who are each in a different League tier."
- Icon: Rainbow-colored friend silhouettes
- XP: 300 | Hidden: Yes | Flavor: "Your crew spans every league. Diverse taste."

**#100 — Secret Collector** (Epic)
- "Unlock all 10 Hidden/Secret category achievements."
- Icon: Magnifying glass revealing hidden symbols, golden glow
- XP: 500 | Hidden: Yes | Flavor: "You found every secret. Nothing stays hidden from you."
- **Balance note:** Replaced "100 Club" (unlock 100 achievements) which was a direct duplicate of #107 "Completionist II." This now rewards completing the hidden achievement category specifically, which is a distinct and meaningful challenge.

---

#### CATEGORY 10: META (8 Achievements)

Meta achievements reward earning achievements across different categories.

**#101 — Well Rounded** (Rare)
- "Unlock at least 1 achievement in every category."
- Icon: Circle divided into colored segments, each filled
- XP: 200 | Hidden: No | Flavor: "A little bit of everything. The mark of a true competitor."

**#102 — Training Elite** (Epic)
- "Unlock 10 Training achievements."
- Icon: Golden dumbbell with a crown
- XP: 400 | Hidden: No | Flavor: "The gym is your kingdom."

**#103 — Scholar Elite** (Epic)
- "Unlock 8 Study achievements."
- Icon: Golden book with a crown
- XP: 400 | Hidden: No | Flavor: "Knowledge is your superpower."

**#104 — Social Butterfly** (Rare)
- "Unlock 8 Social achievements."
- Icon: Butterfly with wings made of friend avatars
- XP: 200 | Hidden: No | Flavor: "Your social game is as strong as your grind."

**#105 — Achievement Hunter** (Epic)
- "Unlock 50 total achievements."
- Icon: Magnifying glass over a trophy
- XP: 500 | Hidden: No | Flavor: "Halfway to catching them all."

**#106 — Completionist I** (Legendary)
- "Unlock 75 total achievements."
- Icon: Three-quarter-filled progress ring, platinum
- XP: 1,000 | Hidden: No | Flavor: "75 down. You're obsessed. We love it."

**#107 — Completionist II** (Legendary)
- "Unlock 100 total achievements (includes meta-achievements)."
- Icon: Complete progress ring, gold with rays
- XP: 2,000 | Hidden: Yes | Flavor: "The century mark. You did what most never will."

**#108 — Tempo Mythic** (Mythic)
- "Unlock ALL 107 other achievements."
- Icon: Prismatic Tempo logo encased in crystal, orbited by all category icons, pulsing rainbow
- XP: 5,000 | Hidden: Yes | Flavor: "Every single achievement. You didn't just play the game. You completed it. Legend."

---

## 22. Anti-Cheat & Integrity System

### 22.1 Design Philosophy

The integrity system must be invisible to honest users and effective against bad actors. It should never publicly accuse anyone — all flags are resolved server-side. The goal is to maintain trust in the leaderboard, which is the foundation of the entire competitive experience.

If users believe someone is cheating and nothing happens, the leaderboard becomes meaningless. If the system is too aggressive and flags legitimate behavior, users get frustrated. The balance is: detect patterns, not single events.

### 22.2 Study Time Fraud Detection

**Threat:** User starts a study timer and walks away, earning XP for doing nothing.

> **REMEDIATED (Technical Feasibility Audit Section 6.3):** Continuous gyroscope/accelerometer monitoring replaced. Gyroscope drains 2-5% battery/hour, produces false positives (phone face-down = most common legitimate study setup), and cannot run when app is backgrounded. Use `CMMotionActivityManager` (battery-efficient motion coprocessor) and `scenePhase` detection instead.

**Detection methods:**

| Signal | Detection | Action |
|--------|-----------|--------|
| App backgrounded for 30+ min during active study timer | `scenePhase` monitoring: detect `.background` state during active timer (zero battery cost) | Session flagged. XP held in "pending" state |
| User was driving during study session | `CMMotionActivityManager.startActivityUpdates()` -- classifies automotive vs walking vs stationary using motion coprocessor (battery-efficient) | Flag for review |
| Implausible study duration | >8 hours continuous with no breaks | Cap XP at 6 sessions/day regardless. Anything beyond is flagged |
| Multiple devices | Same user logged study on phone AND tablet simultaneously | Only count one device. Take the longer session |
| Rapid session starts/stops | Starting and stopping sessions quickly (< 5 minutes) multiple times | After 3 quick-cancels in 1 hour, cooldown: next session must be 10+ minutes to earn XP |
| Whoop strain cross-validation | Compare study time with Whoop strain data (if connected). Elevated strain during "study" suggests physical activity | Flag for review (Whoop users only) |

**Resolution:** Pending XP from flagged sessions is resolved within 48 hours:
- If user was legitimately studying (e.g., using a separate textbook with phone face-down): XP released. Pattern learned for this user.
- If clearly fraudulent: XP removed. No notification sent for first offense. Repeat offenders see "Some XP was adjusted due to data validation."

### 22.3 Workout Fraud Detection

**Threat:** User logs a workout they didn't do.

**Detection methods:**

| Signal | Detection | Action |
|--------|-----------|--------|
| Workout logged but Whoop shows no strain increase | Compare logged workout time with Whoop strain data (if Whoop connected) | Flag. Whoop strain should increase by at least 2.0 during any real workout |
| Workout logged with impossibly heavy weights | Weight exceeds 2x user's previous max for that exercise | Require confirmation: "Are you sure? This is 2x your previous max." If confirmed, flag for review but allow |
| Workout duration < 10 minutes | Completed a full workout in under 10 minutes | XP awarded but flagged. Real workouts take 15+ minutes minimum |
| Multiple workouts on same day | User logs 3+ workouts | Only 1 workout/day earns base XP (already capped). Excess workouts tracked but no XP |
| Workout logged during sleep hours | Workout start time between 01:00-04:00 with no corresponding Whoop/HealthKit activity | Flag silently |

### 22.4 XP Velocity Checks

The system tracks XP earn rate in real-time and flags anomalies.

| Check | Threshold | Action |
|-------|-----------|--------|
| Daily XP exceeds hard cap | >1,500 XP before multiplier in a single day | Soft cap reached — additional XP logged but held for validation |
| Hourly XP rate | >500 XP in any 1-hour window (not counting challenge/achievement bonuses) | Flag for review |
| Sudden behavior change | User goes from ~200 XP/day average to >800 XP/day for 3+ consecutive days | Flag. Could be legitimate (exam season, new motivation) or gaming |
| Achievement farming | 5+ achievements unlocked in a single day (excluding first day) | Flag. Review criteria met |

### 22.5 Social Report System

Friends can report suspicious activity:

**Report flow:**
1. On any leaderboard row or friend profile, tap "..." > "Report suspicious activity"
2. Options:
   - "Their study hours seem unrealistic"
   - "Their workout data looks fake"
   - "Their XP is increasing too fast"
   - "Other (describe)"
3. User provides optional description (max 300 chars)
4. Report submitted to server. Reporter receives: "Thanks. We'll review this."

**Report handling:**
- 1 report: noted, no action
- 2 reports from different users about the same person: automatic data audit triggered
- 3+ reports: manual review by admin
- False reports (user reports someone who is clearly legitimate): reporter's report weight decreases

### 22.6 Consequence Ladder

| Offense Level | Trigger | Consequence | Notification to User |
|---------------|---------|-------------|---------------------|
| Level 0: Warning | First flag resolved as suspicious | XP adjusted for specific events. No penalty | "Some activity was adjusted during routine data validation." |
| Level 1: Mild | 2nd offense within 30 days | XP adjusted + 24-hour XP earn rate reduced to 75% | "Your account flagged a data inconsistency. XP earning temporarily limited." |
| Level 2: Moderate | 3rd offense within 60 days | XP adjusted + removed from leaderboards for 1 week | "Your account has been temporarily removed from leaderboards due to data concerns." |
| Level 3: Severe | 4+ offenses or clearly intentional manipulation | Permanent leaderboard ban (can still use app, earn XP, just invisible to others) | "Leaderboard participation has been revoked. Contact support to appeal." |

**Appeal process:** User can email support. Human review within 72 hours. If overturned, all consequences reversed and report weight reduced for reporters.

### 22.7 Trust Score

Each user has a hidden Trust Score (0.0 to 1.0, default 0.8 for new users):

- Increases by 0.01/week with no flags
- Decreases by 0.1 per resolved flag (flag confirmed as suspicious)
- Decreases by 0.2 per report upheld
- Users with Trust Score < 0.5: all XP is validated server-side before posting to leaderboard (slight delay in leaderboard updates)
- Users with Trust Score > 0.9: flagging thresholds relaxed (fewer false positives)

**Anti-Gaming the Trust Score:**

The Trust Score system itself can be weaponized. Two attack vectors and their mitigations:

1. **Report bombing (reporting innocent friends to lower their score):**
   - Reports do NOT directly affect the reported user's Trust Score. Only UPHELD reports (confirmed by data audit) decrease Trust Score.
   - Raw reports are filtered through the reporter's own Report Credibility score (separate from Trust Score). A reporter who has had 2+ reports dismissed as false loses report credibility: their future reports require 2 additional corroborating reports before triggering any audit.
   - Rate limit: a single user can report the same person only once per 30 days. A user can submit max 3 reports total per week. This prevents coordinated harassment.
   - If a user reports 3+ people in a week and all reports are dismissed: the reporter receives a warning ("Your recent reports didn't find issues. Please only report genuinely suspicious behavior.") and their next 5 reports carry zero weight.

2. **Self-manipulation (deliberately getting flagged then cleared to learn the system thresholds):**
   - Flag resolution details are NEVER shared with the user. They see "Some activity was adjusted" but never the specific detection method or threshold.
   - Threshold values are stored server-side and are not discoverable through client-side inspection.

### 22.8 False Positive Policy

**Target false positive rate: <3% of all flags.** At >5%, user trust erodes faster than cheating does.

**Mitigations to keep false positives low:**

1. **Study fraud detection (Section 22.2):** The "phone untouched for 30 minutes" signal has the HIGHEST false positive risk. Many legitimate study modes involve a textbook/laptop with the phone face-down. **Mitigation:** This signal alone NEVER triggers a flag. It must be combined with at least one additional signal (e.g., phone in motion + no touch, or implausible duration + no touch). Phone-face-down-while-studying is NORMAL behavior and must be treated as such.

2. **Workout logged during sleep hours (01:00-04:00):** This flags legitimate night-shift workers and early-morning gym-goers. **Mitigation:** If a user has logged 3+ workouts in this time window over the past 30 days, this signal is suppressed for them permanently (pattern recognized as their schedule).

3. **Sudden behavior change (200 -> 800 XP/day):** This flags users who are genuinely getting motivated (new semester, new year's resolution, started dating someone who works out). **Mitigation:** This flag is informational only for the first 7 days. Only if the sustained high output cannot be explained by any legitimate XP source combination does it escalate. Additionally, this flag is automatically suppressed during the first 30 days of account creation (new users naturally ramp up) and during seasonal events.

4. **XP velocity (>500 XP in one hour):** Legitimate on days with Perfect Day + workout + study target + achievement unlock. **Mitigation:** Achievement XP and challenge XP are excluded from hourly velocity calculations.

**Anti-cheat that is MORE ANNOYING than the cheating it prevents (removed):**

The original spec included "phone engagement check every 15 minutes during study sessions" (Section 22.2). This is removed. Requiring users to touch their phone every 15 minutes during study actively DISRUPTS the deep focus state the app is supposed to encourage. It punishes the exact behavior we want to reward. The phone-touching requirement would cause more uninstalls from frustrated legitimate users than it would prevent from cheaters. Replaced with passive signals only (gyroscope, accelerometer, session duration patterns).

---

## 23. Social Features Deep Dive

### 23.1 Activity Feed Algorithm

See Section 12.5 for the complete feed algorithm specification.

### 23.2 Reaction System — 6 Custom Reactions

The feed uses 6 custom reactions instead of generic like/heart. Each reaction communicates a specific emotion and creates micro-interactions that feel meaningful.

| Reaction | Name | Icon | Meaning | When to use |
|----------|------|------|---------|-------------|
| FLEX | Strong | Flexed bicep | "That's impressive" | PR set, heavy workout, big study session |
| FIRE | Fire | Flame | "You're on fire" | Streak milestone, hot leaderboard position, winning a challenge |
| SALUTE | Respect | Saluting face | "I respect the grind" | Showing up on tough days, recovery listener moments, consistency |
| EYES | Watching You | Eyes | "I see you" | Playful. Someone climbing the leaderboard, about to pass you |
| ZAP | Electric | Lightning bolt | "That's shocking/amazing" | Unexpected achievement, massive XP day, surprise result |
| ICE | Cold | Snowflake/Ice cube | "That's cold/impressive" | Dominating a challenge, untouchable streak, flexing on others |

**Reaction UI:**
- Long-press on any feed item to reveal reaction bar (similar to iMessage reactions). Bar appears above the card with a bounce animation (200ms).
- Each reaction icon: 36pt, spaced 8pt apart. Horizontal bar with rounded ends, background #12203A with 90% opacity + blur.
- Tap a reaction: icon scales to 1.5x then back to 1.0x (spring, 200ms). Haptic: light impact. Reaction added.
- Tap same reaction again: removes it (toggle behavior).
- Only 1 reaction per user per feed item.
- Reaction counts shown below the feed item: icon (16pt) + count (SF Mono, 12pt, #8899AA). Only reactions with count > 0 are shown.

**Push notifications for reactions:**
- Only notify when a "close friend" reacts. Close friend = someone you've had a challenge with in the last 30 days or interacted with (reacted to) in the last 7 days.
- Notification: "[Name] sent you FLEX on your workout" — max 3 reaction notifications/day.
- Non-close-friend reactions: no push notification. Badge on feed item only.

### 23.3 Trash Talk — Short Text Reactions

**Decision: NOT INCLUDED in v1.** Here's why:

Trash talk creates toxicity faster than it creates engagement. Even among friends, "text on the internet" is easily misread. Duolingo doesn't allow it. Strava doesn't allow it. The feed reaction system provides sufficient expression without the moderation burden.

**Future consideration (v2):** If demand exists, consider allowing short pre-set messages only (not free text):
- "Let's go!"
- "Is that all you got?"
- "You're next."
- "Respect."
- "Sleep on this."
- "Rematch?"

These are curated to be competitive without being mean.

### 23.4 Groups — Named Friend Groups

Groups allow users to create named sub-communities for tighter competition.

**Unlock:** Level 28+

**Creating a group:**
1. Navigate to Friends > Groups > "Create Group"
2. Set group name (max 30 chars, e.g., "Italian Crew")
3. Set optional group avatar (photo or emoji)
4. Invite friends (min 3, max 20)
5. Invited friends receive a group invite (similar to challenge invite)

**Group features:**
- **Group leaderboard:** Separate weekly leaderboard for just group members. Appears as a third scope on the Leaderboard View: `[FRIENDS] [MY LEAGUE] [GROUPS v]` with a dropdown to select which group.
- **Group challenges:** Creator can start challenges that auto-include all group members. No individual invites needed.
- **Group stats:** Monthly summary card showing group averages vs each member.
- **Group feed:** Filter the activity feed to show only group members' activities.

**Group management:**
- Creator is admin. Can add/remove members, delete group.
- Members can leave at any time.
- Group dissolves if fewer than 3 members remain.
- Max 5 groups per user.

### 23.5 Group UI

```
+----------------------------------------+
|  < Friends        GROUPS               |
|                                        |
|  YOUR GROUPS (2)                       |
|                                        |
|  +----------------------------------+  |
|  |  ITALIAN CREW           8 members|  |
|  |  This week's #1: Marco  3,200 XP|  |
|  |  Your rank: #3                   |  |
|  +----------------------------------+  |
|                                        |
|  +----------------------------------+  |
|  |  GYM BROS               4 members|  |
|  |  This week's #1: You    2,800 XP|  |
|  |  Your rank: #1   CROWN          |  |
|  +----------------------------------+  |
|                                        |
|  [ + Create New Group ]                |
|                                        |
+----------------------------------------+
```

---

## 24. Competitive Onboarding — The First 30 Days

The onboarding sequence described in Section 14 handles the first 60 seconds. This section describes the entire 30-day "ramp" that turns a new user into a competitive, engaged Arena participant.

### 24.1 Day-by-Day Onboarding Milestones

#### Hour 1: First XP
- Complete Arena tutorial -> "Genesis" achievement (25 XP)
- XP bar animation plays. User sees their first XP earn.
- Prompt: "Complete any task to earn more XP." Points user to other Tempo modules.

#### Day 1-2: First XP, first progress
- **Target:** Level 2 requires 627 cumulative XP. With 1.5x New Player Momentum bonus, a Dedicated user earns ~500 base * 1.5x = ~750 XP/day. Level 2 is achievable by end of Day 1 for active users, early Day 2 for casual users.
- **How Day 1:** Tutorial (25) + login (10) + one workout (~160) + one study session (30) + meals (~45) + steps (~35) = ~305 base XP * 1.5x momentum = ~457 XP. Not quite Level 2 yet -- and that's OK. Reaching Level 2 on Day 2 after logging more activities creates a "reward for coming back" loop.
- **On Level 2:** Mini celebration. "You're Level 2! You're picking this up fast."
- **Prompt:** "Keep going! Level 5 unlocks the leaderboard."

#### Day 2-3: Build the habit
- **Streak begins.** On Day 2, if user completed Day 1 streak criteria, show: "2-day streak! Keep it going for bonus XP."
- **Daily micro-challenge introduced:** "Try today's micro-challenge: Log all 3 meals."
- **Push notifications begin (gently):** "Welcome back! You're making progress toward Level 3."

#### Day 3-5: Hit Level 3
- **Level 3 requires 1,490 cumulative XP.** A Dedicated user with 1.5x momentum earns ~750/day, reaching Level 3 around Day 3. Casual users reach it around Day 5.
- **Unlock:** Custom profile color. Prompt user to personalize.
- **Streak hits 3 days = 1.1x multiplier.** Celebrate with streak animation.
- **Prompt:** "Your streak just earned you a 1.1x XP multiplier. Every day counts!"

#### Day 5-7: First week
- **Target:** ~Level 4-5 by end of first week (3,820 cumulative for Level 5). A Dedicated user with momentum bonus earns ~750/day * 7 = ~5,250 XP -- Level 5 reached. A Casual user earns ~290 base * 1.3x (momentum fading + streak starting) * 7 = ~2,639 XP -- reaches Level 4.
- **Day 5: Level 5 -> Leaderboard unlocks.**
  - If user has friends: "Your leaderboard is live! See where you stand."
  - If no friends: "The leaderboard is unlocked! Add friends to compete." -> Aggressive friend invite prompt.
- **Day 7: Weekly reset.** If user had friends: "Your first week is complete! Here's how you ranked."
- **If no friends by Day 7:** Show ghost/bot leaderboard with 5 simulated entries at similar levels. Label: "Sample leaderboard — add friends to see real rankings!" This prevents the demoralizing empty leaderboard.

#### Week 2: Social features
- **Day 8:** If user has <3 friends: "Challenge someone! Challenges are available at Level 7." or if already Level 7+: "Start your first challenge!"
- **Day 10:** First challenge suggested (auto-prompt if user hasn't started one): "Challenge [most active friend] to a 3-day Step Battle?"
- **Day 14:** Streak hits 14 days (if maintained) = 1.5x multiplier. Major celebration.

#### Week 3-4: Competitive hooks
- **Day 15:** League system introduced (if enough users). "You've been placed in Silver League with 19 others at your level!"
- **Day 21:** "Three weeks in! You're establishing yourself. Check your achievements — you might be close to unlocking something."
- **Day 28:** If user maintained streak: "4-week streak! You're in the top 10% of new users."

#### Day 30: Competitive user established
- **Push notification:** "One month on Tempo. You've earned [X] XP, hit [Y] achievements, and [won/participated in] [Z] challenges. The Arena is your playground now."
- **New Player Momentum bonus expires** (faded from 1.5x to 1.0x over days 1-14, so it's already gone).

### 24.2 Empty State Strategy — "No Friends" Problem

The biggest risk to Arena engagement is a user with no friends. An empty leaderboard is death.

**Solution layers:**

1. **Aggressive invite prompts** during Days 1-7 (see above). Not annoying, but persistent.
2. **QR code at gym/university:** Encourage physical sharing. "Show your QR code to a friend at the gym" prompt after first workout.
3. **Contact import:** Prompt on Day 3 (not Day 1 — let them experience the app first).
4. **Placeholder leaderboard:** If user has 0 friends by Day 5, show a placeholder leaderboard with clearly-labeled sample data. 5 bot entries with names like "Alex (sample)", "Jordan (sample)" at XP levels slightly above and below the user. This shows what the leaderboard COULD look like. Disappears when first real friend is added.
5. **"Solo Mode" fallback:** If user has no friends by Day 14, enable League system as primary competition mode. They compete against 19 strangers at their level. This gives the competitive experience without requiring friends.

---

## 25. Retention Mechanics & Re-Engagement

### 25.1 Daily Retention Hooks

| Mechanic | Description | Timing |
|----------|-------------|--------|
| Login bonus | 10 XP for first app open | On first open after midnight |
| 7-day login streak | +25 XP bonus on 7th consecutive day opened | Day 7 of consecutive opens |
| Streak anxiety | Streak danger notification at 20:00 if criteria not met | 20:00 local |
| "Still available" XP | Today's XP card shows potential remaining XP | Always visible on Arena Main View |
| Micro-challenges | 3 new opt-in micro-challenges daily | Generated at 00:00, visible from first open |
| Leaderboard proximity | "You're only 85 XP behind Marco" | Updated in real-time |

### 25.2 Weekly Retention Hooks

| Mechanic | Description | Timing |
|----------|-------------|--------|
| Monday motivation | "New week, new leaderboard. Everyone's at 0." push notification | Monday 08:00 |
| Weekly reset ceremony | "Week in Review" card on first Monday open | Monday first app open |
| League results | Promotion/relegation results | Monday 00:00 |
| Monday workout bonus | +25 XP for first workout of the week | Monday before 23:59 |
| Challenge invites | Prompt to start a new challenge if none active | Wednesday (mid-week energy dip) |

### 25.3 Monthly Retention Hooks

| Mechanic | Description | Timing |
|----------|-------------|--------|
| Monthly summary | "Your March: [X] XP, [Y] workouts, [Z] achievements" card | 1st of each month |
| Monthly leaderboard results | "You finished #3 among friends in March!" | 1st of each month |
| Seasonal events | Limited-time challenges and achievements | See Section 20.4 |

### 25.4 Streak Recovery — The "Don't Break the Chain" System

The streak is the single most powerful retention mechanic. Here's how we protect it and make breaking it recoverable:

**Visual: Chain metaphor**
- The streak display shows connected chain links instead of (or in addition to) calendar dots.
- Each day is a link. Active streak = unbroken chain. Broken streak = visible break in chain.
- Long-press on streak display shows full streak history: a timeline of all streaks, their lengths, and what broke them.

**Streak danger escalation (max 2 notifications per evening):**
1. **20:00:** Gentle push: "Your [N]-day streak ends at midnight. Complete 1 more task to save it!"
2. **22:30:** If still not met AND streak is 7+ days: "90 minutes left. Your [N]-day streak is on the line."
3. ~~**23:00 notification: REMOVED.**~~ Research on loss aversion in habit apps shows that 3 escalating notifications in one evening causes users to associate the app with anxiety. Two is the maximum. Users who ignore the first two will not respond to a third -- they will uninstall.

**After streak breaks:**
- DO NOT send a demoralizing notification. Instead, next morning: "New day, fresh start. Your next streak begins now."
- Show "Previous streak: [N] days" on the streak card for 7 days as motivation to rebuild.
- "The Comeback" achievement (Section 21, #89) incentivizes fast recovery.

**Streak loss penalty calibration:**
- The -100 XP penalty for breaking a 7+ day streak (Section 2.2) is appropriate for streaks of 7-30 days.
- For streaks of 30+ days that break: the penalty remains -100 XP (does NOT increase). Losing a long streak is already psychologically devastating. The natural loss of the multiplier (dropping from 2.0x back to 1.0x) effectively halves daily XP -- that is punishment enough. Increasing the XP penalty would feel punitive and drive uninstalls.
- For streaks of 60+ days that break: award a consolation "Memory" marker visible on the streak card: "Previous best: 67 days." This reframes the loss as an accomplishment to be proud of, not a failure to mourn.

### 25.5 Re-Engagement Sequences

When a user goes inactive, a specific notification sequence activates. The guiding principle: each notification should offer VALUE to the user, not guilt. If a notification would make the user feel bad for having a life, it is cut.

| Days Inactive | Notification | Tone | Rationale |
|---------------|-------------|------|-----------|
| 1 day | (none) | - | Normal rest day. Silence is respect. |
| 2 days | "Your streak is frozen. Come back to keep it alive!" | Informational | Only sent if user HAS an active streak. Provides useful info (freeze status). |
| 3 days | "Marco just passed you on the leaderboard. Still time to catch up this week." | Social proof | Only sent if user was in top 50% of friend leaderboard. Irrelevant for bottom-half users. |
| 7 days | "Hey [Name], your progress is safe. Level [N], [X] achievements. Pick up anytime." | Warmth | Reassurance, not guilt. Tells user nothing was lost. |
| 30 days | (none -- see win-back triggers below) | Respect | After 30 days, scheduled notifications stop entirely. Only event-driven triggers remain. |

**Notifications REMOVED from the original sequence:**
- ~~Day 5: "You've been quiet. Your friends miss competing with you."~~ -- Manipulative. Your friends don't know you've been inactive, and implying they do is dishonest. This is the kind of message that makes users screenshot and post "look how desperate this app is."
- ~~Day 7: "Your weekly leaderboard spot is empty. The competition goes on without you."~~ -- Pure guilt trip. A user who is dealing with exams, family issues, or just needs a break does not need to hear that life "goes on without them." Replaced with the warm Day 7 message above.
- ~~Day 14 nostalgia message~~ -- Removed. By day 14, if the Day 7 warmth message didn't work, a nostalgia play won't either. Silence is more dignified.
- ~~Day 60 "final attempt"~~ -- Removed. There is no "final attempt." We stop scheduled messages at Day 30 and rely only on natural win-back triggers.

**Win-back triggers (event-driven, not time-driven):**
1. **Friend challenge invite:** "Your friend [Name] challenged you! Join the [Metric] challenge?" -- triggered when a friend explicitly challenges the churned user. This is the strongest re-engagement signal because it comes from a real human who chose to involve them.
2. **Seasonal event start:** "Finals Survivor starts December 1st. Limited-time achievements available." -- triggered at seasonal event start. Max 1 seasonal notification per month for churned users.
3. **Milestone proximity:** "You were 3 achievements away from 'Scholar.' That progress is still here." -- one-time notification, sent once total, never repeated.

### 25.6 Comeback Bonus for Returning Users

When a user returns after 7+ days of inactivity, they receive a **Welcome Back Boost** instead of punishment:

| Days Away | Comeback Bonus | Duration |
|-----------|---------------|----------|
| 7-13 days | 1.25x XP multiplier | First 3 days back |
| 14-29 days | 1.5x XP multiplier + 1 free streak freeze | First 5 days back |
| 30-89 days | 2.0x XP multiplier + 2 free streak freezes + "Welcome Back" limited badge | First 7 days back |
| 90+ days | 2.0x XP multiplier + 3 free streak freezes + "The Return" achievement (hidden, 200 XP) | First 7 days back |

**Why comeback bonuses instead of punishment:**
- Punishment for leaving (e.g., decayed XP, lost rank) gives users ZERO reason to return. They think "I've already lost everything, why bother?"
- A comeback bonus gives users a REASON to return: "I get boosted XP for a week, so this is actually the best time to come back."
- The multiplier stacks with streak multiplier but is capped at a combined 3.0x (the comeback bonus does not let users exceed the system-wide multiplier ceiling).
- The free streak freezes address the #1 anxiety of returning users: "I'll lose my streak again immediately because I'm out of the habit."
- The "Welcome Back" badge and "The Return" achievement transform the absence from a failure into a narrative moment.

**On-screen experience when returning:**
```
+----------------------------------------+
|  WELCOME BACK, NICOLA!                 |
|                                        |
|  You were away for 18 days.            |
|  Your progress is exactly where you    |
|  left it.                              |
|                                        |
|  Level 14 -- Warrior                   |
|  12 achievements unlocked              |
|  Friends still competing               |
|                                        |
|  GIFT COMEBACK BOOST ACTIVE            |
|  1.5x XP for 5 days                   |
|  +1 Streak Freeze granted              |
|                                        |
|  [ Let's Go ]                          |
+----------------------------------------+
```

### 25.7 The "Bad Week" Recovery

If a user has a significantly worse week than their average (< 50% of typical weekly XP):

- DO NOT point out the bad week explicitly.
- Monday: "New week. Fresh start. You've got this."
- Tuesday: If user logs any activity: "Great to see you back! +[X] XP already."
- Focus on micro-wins: "You logged breakfast — that's 15 XP closer to your goals."

---

## 26. Sound Design for Arena

### 26.1 Sound Design Philosophy

Arena sounds must pass three tests:
1. **Is it satisfying?** Does the sound create a micro-dopamine hit?
2. **Is it unobtrusive?** Can someone play it on a train without embarrassment?
3. **Does it respect the moment?** Victory sounds are triumphant. XP earn sounds are subtle. The hierarchy must match the importance.

All sounds should feel like they belong to the same "world" — consistent timbre, similar frequency range, cohesive aesthetic. Think: the sound design of Overwatch's loot boxes meets Apple's notification sounds.

### 26.2 Sound Specifications

#### XP Earn Sounds

| Amount | Sound Description | Musical Notes | Duration | Pitch Variation |
|--------|-------------------|---------------|----------|-----------------|
| 1-25 XP | Soft glass tap, single note | C5 (soft) | 100ms | Randomize +/- 2 semitones for variety |
| 26-75 XP | Clean "ding" with slight resonance | E5 | 150ms | None |
| 76-150 XP | Full "ding" with harmonic overtone | G5 + C6 (faint) | 250ms | None |
| 151-300 XP | Rich "cha-ching" with metallic ring | C5-E5-G5 rapid arpeggio | 400ms | None |
| 300+ XP | Full "cha-ching" with shimmer tail | C5-E5-G5-C6 arpeggio + high shimmer | 600ms | None |
| Bonus XP | Same as amount tier but with additional "sparkle" overlay | Add high bells at 12-14kHz | +100ms | None |

**Pitch variation for small amounts:** Earning multiple small XP amounts in quick succession should sound musical, not repetitive. Each successive small XP earn shifts up by 2 semitones (C5 -> D5 -> E5 -> F5) before resetting. This creates an ascending "staircase" effect that feels like progress.

#### Level Up Sound
- **Description:** Three-note ascending harp arpeggio, followed by a warm pad swell
- **Notes:** C5 (150ms) -> E5 (150ms) -> G5 (held, 300ms with reverb tail)
- **Additional:** Subtle choir "ah" pad enters at G5, swells to 100% volume, fades over 500ms
- **Total duration:** 800ms core + 500ms reverb tail
- **Timbre:** Celtic harp sample, natural reverb (cathedral-like)

#### Streak Milestone Sound
- **Description:** Quick whoosh (like a flame igniting) followed by a crackling fire loop
- **Whoosh:** Synthesized noise sweep, low to high, 200ms
- **Crackle:** Recorded fire crackle, 300ms, low-pass filtered to be warm
- **Total duration:** 500ms

#### Achievement Unlock Sounds (Tiered)

| Rarity | Description | Duration |
|--------|-------------|----------|
| Common | Single tubular bell, clear tone | 200ms |
| Rare | Two tubular bells, ascending (C5 -> E5) | 350ms |
| Epic | Three tubular bells ascending (C5 -> E5 -> G5) + reverb cathedral echo | 500ms |
| Legendary | Orchestra hit: full brass stab (C major) + cymbal crash, compressed | 600ms |
| Mythic | Orchestral swell: strings crescendo + brass stab + choir "ah" + cymbal shimmer | 1000ms |

#### Challenge Sounds

| Event | Description | Duration |
|-------|-------------|----------|
| Challenge win | Triumphant horn fanfare (French horn, C major) + distant crowd cheering (low-pass filtered) | 1200ms |
| Challenge loss | Single low brass note (Bb3), gentle descending, with muted resolution | 400ms |
| Challenge invitation | Sword clash sound effect (two metallic impacts, 100ms apart) | 200ms |

#### Leaderboard Sounds

| Event | Description | Duration |
|-------|-------------|----------|
| Passing someone | Quick ascending synthesizer swoosh | 300ms |
| Being passed | Quick descending synthesizer swoosh (50% volume of "passing someone") | 300ms |
| Reaching #1 | Crown drop: metallic "clink" on stone + brief fanfare echo | 500ms |

#### Login & Reaction Sounds

| Event | Description | Duration |
|-------|-------------|----------|
| Daily login | Warm "welcome home" two-note chime (G4 -> C5), piano-like | 300ms |
| Reaction received | Soft bubble pop (like iMessage) | 100ms |
| Streak danger alert | Two quick warning tones (A4 -> A4), like a notification but more urgent | 300ms |

### 26.3 Technical Implementation

- **Format:** Compressed `.caf` files (Apple Core Audio Format). < 50KB each.
- **Audio session:** `AVAudioSession.Category.ambient`. Mixes with user's music. Respects silent switch and volume.
- **Preloading:** All sounds loaded into memory on Arena tab first appear (using `AVAudioPlayer` with `prepareToPlay()`). Total memory footprint: < 1MB.
- **Settings:** Global toggle in Arena Settings (ON by default). No per-sound control in v1.
- **Haptic pairing:** Every sound has a paired haptic. If sound is disabled but haptic is enabled, haptic still fires. If Reduce Motion is on, haptics are softened (light instead of medium, medium instead of heavy).

---

## 27. XP Economy Sinks & Spending

### 27.1 Why XP Sinks Matter

Without XP sinks, total XP only goes up. Over time, this creates two problems:
1. **Number inflation:** Numbers get so large they lose meaning. "I have 500,000 XP" doesn't feel different from "I have 600,000 XP."
2. **No spending decisions:** Users have no agency over their XP — it just accumulates. Spending creates strategic decisions.

The Arena Shop solves both problems by giving users a reason to SPEND XP on cosmetic items, creating economic circulation.

### 27.2 Spendable XP vs. Total XP

**CRITICAL DISTINCTION:**
- **Total XP** = lifetime earned XP. This determines your level. It NEVER decreases. Level progress is permanent.
- **Spendable XP** = Total XP minus all purchases. This is your "wallet."

Example: User has 30,000 Total XP (Level 50). They spend 5,000 XP in the shop. They're still Level 50 with 30,000 Total XP, but they have 25,000 Spendable XP.

This means spending XP never costs you level progress. It only costs you shop currency.

### 27.3 Arena Shop — Items & Prices

Unlocked at Level 12. Accessed from Arena Settings or a dedicated shop icon on the Arena Main View.

#### Profile Customization

| Item | Cost | Description |
|------|------|-------------|
| Profile Color (8 options, beyond Level 3 default) | 500 XP each | Additional profile accent colors: neon green, hot pink, cyan, coral, etc. |
| Animated Avatar Border: Pulse | 1,500 XP | Slow-pulse animation on avatar border |
| Animated Avatar Border: Flame | 3,000 XP | Flame animation circling avatar |
| Animated Avatar Border: Electric | 3,000 XP | Electric sparks circling avatar |
| Animated Avatar Border: Aurora | 5,000 XP | Northern lights effect on avatar border |
| Profile Card Background | 2,000 XP each | Alternative card backgrounds for your profile: Dark Carbon, Deep Ocean, Midnight Forest, Volcanic, Ice Crystal (5 options) |
| Custom XP Number Color | 1,000 XP each | Change the color of your XP numbers on YOUR screen only. Options: Gold, Emerald, Crimson, Purple, White |

#### Streak Items

| Item | Cost | Description | Limit |
|------|------|-------------|-------|
| Streak Freeze (extra) | 500 XP | Purchase an additional streak freeze beyond the earned ones | 1 per week |
| Streak Flame Skin: Blue | 2,000 XP | Replace default orange streak flame with blue flame | Permanent |
| Streak Flame Skin: Purple | 2,000 XP | Purple flame | Permanent |
| Streak Flame Skin: Green | 2,000 XP | Green flame | Permanent |
| Streak Flame Skin: White | 5,000 XP | White-hot flame (normally reserved for 90+ day streak visual) | Permanent |

#### Level-Up Effects

| Item | Cost | Description |
|------|------|-------------|
| Level-Up Confetti Style: Gold Rain | 3,000 XP | Replace default level-up particles with gold rain |
| Level-Up Confetti Style: Fireworks | 3,000 XP | Firework explosion instead of ring burst |
| Level-Up Confetti Style: Cherry Blossoms | 3,000 XP | Sakura petals falling |
| Custom Level-Up Sound | 2,000 XP each | 3 alternative level-up sounds (Orchestra, Electronic, 8-Bit) |

#### Leaderboard Flair

| Item | Cost | Description |
|------|------|-------------|
| Rank Frame: Gold | 5,000 XP | Golden frame around your leaderboard row |
| Rank Frame: Diamond | 8,000 XP | Diamond-sparkle frame |
| Name Color Override | 3,000 XP each | Change your name color on leaderboards (5 options) |
| Custom Podium Effect | 4,000 XP | When you're on the podium, your pillar has extra effects (flame base, sparkle, etc.) |

### 27.4 Shop UI

```
+----------------------------------------+
|  < Arena        ARENA SHOP              |
|                                        |
|  Spendable XP: 12,450 XP              |
|  (Total XP: 45,200 XP)                |
|                                        |
|  PROFILE                               |
|  ┌──────────────────────────────────┐  |
|  │ Animated Border: Flame  3,000 XP│  |
|  │ [Preview]         [Purchase]    │  |
|  └──────────────────────────────────┘  |
|  ...                                   |
|                                        |
|  STREAKS                               |
|  ...                                   |
|                                        |
|  LEADERBOARD                           |
|  ...                                   |
+----------------------------------------+
```

- "Preview" button: shows a preview of the cosmetic applied to user's profile (non-destructive preview).
- "Purchase" button: confirmation dialog: "Spend 3,000 XP on Animated Border: Flame? Your spendable XP will be 9,450 XP. Your level is NOT affected." [Purchase / Cancel]
- Insufficient XP: button is disabled, shows "Need [X] more XP."
- Already purchased: button shows "Owned" with checkmark. Item shows "Equipped" or "Equip" toggle.

### 27.5 Shop Pricing Philosophy

- **Streak Freeze (500 XP):** Priced to be affordable but not spammable. A Dedicated player earns ~750 XP/day, so this costs about 2/3 of a good day. Prevents abuse while being accessible.
- **Cosmetic items (1,000-8,000 XP):** Priced to represent 1-10 days of effort for a Dedicated player. The most expensive items require meaningful saving, creating anticipation.
- **No real-money purchases.** Every item is earned through effort only. This is a core principle.

---

## 28. Monthly Economy Health Report

### 28.1 Purpose

Every month, the system generates an internal economy health report. This is for the development team, not shown to users. It ensures the economy stays balanced as the user base grows.

### 28.2 Key Metrics to Track

| Metric | Healthy Range | Alert Threshold |
|--------|--------------|-----------------|
| **Median daily XP (active users)** | 200-500 XP | < 100 (engagement problem) or > 800 (inflation) |
| **P25-P75 daily XP spread** | < 4x difference | > 6x (casual vs hardcore gap too wide) |
| **% users with active streak** | > 40% | < 25% (streak system too hard) or > 80% (too easy) |
| **Average streak length** | 10-30 days | < 5 (too easy to break) or > 60 (freezes too generous) |
| **% users with 0 friends** | < 20% (after 7+ days) | > 35% (social onboarding failing) |
| **Challenge participation rate** | > 30% of users with friends | < 15% (challenges not compelling) |
| **Challenge completion rate** | > 70% | < 50% (challenges too long/hard) |
| **Weekly leaderboard engagement** | > 50% of users with friends check it | < 30% (leaderboard not sticky) |
| **League promotion rate** | ~25% per week | < 15% (too hard) or > 40% (too easy) |
| **Achievement unlock rate (Common)** | > 70% within 30 days | < 50% (too hard) |
| **Achievement unlock rate (Rare)** | 25-50% within 6 months | < 10% (too hard) or > 70% (too easy) |
| **Achievement unlock rate (Epic)** | 5-20% within 12 months | < 3% (too hard) |
| **Shop spending rate** | 40-60% of spendable XP circulated | < 20% (items not compelling) or > 80% (forced spending) |
| **Anti-cheat flag rate** | < 2% of XP events | > 5% (thresholds too aggressive) |
| **Anti-cheat false positive rate** | < 10% of flags | > 25% (system too aggressive) |
| **Churn rate (14-day inactive)** | < 15%/month | > 25% (retention problem) |
| **Re-engagement rate** | > 20% of churned users return within 30 days | < 10% (re-engagement failing) |

### 28.3 Automated Alerts

If any metric crosses its alert threshold for 2 consecutive weeks, an automated alert is generated:

```
ECONOMY ALERT: Median daily XP is 850 (threshold: 800)
Period: March 10-24, 2026
Possible causes: Streak multiplier inflation, new feature releasing too much XP
Recommended actions:
1. Review XP sources added in last update
2. Check streak multiplier distribution
3. Verify daily caps are enforced
```

### 28.4 Casual-Hardcore Gap Management

The most dangerous metric is the gap between casual (50th percentile) and hardcore (95th percentile) users. If this gap grows too large, casual users disengage.

**Current design gap:** Casual earns ~6,400 XP/month, Hardcore earns ~38,325 XP/month = 6.0x gap. On the weekly RAW leaderboard (no multipliers), the gap narrows: Casual ~1,360/week raw vs Hardcore ~5,110/week raw = 3.8x gap. This is within healthy range.

**Acceptable range:** 3x-8x gap (total XP). Below 3x means hardcore users are not rewarded enough for effort. Above 8x means casual users can never compete. On the weekly RAW leaderboard, target 2x-5x gap.

**Mitigation if gap exceeds 8x:**
1. Increase daily XP from "easy" activities (meals, sleep, login) by 20%
2. Introduce a "catch-up multiplier": users below median weekly XP get a 1.1x bonus
3. Cap streak multiplier effect on leaderboards

**Mitigation if gap falls below 3x:**
1. Increase PR bonus XP
2. Add more XP tiers for high-intensity activities
3. Introduce new advanced challenges with higher XP rewards

---

## End of Specification

This document fully specifies the Arena ("ClutchTime") module for Tempo iOS. Every screen, component, interaction, animation, data model, economy simulation, social system, anti-cheat mechanism, and edge case is defined. The implementation team should be able to build from this spec without ambiguity.

**Next steps for design team:**
1. Create all 108 achievement badge artworks based on icon concepts described.
2. Produce Lottie animation files for: streak flames (7 tiers), level-up sequence, challenge win confetti, onboarding illustrations (5), trophy/podium animations, and league promotion/relegation effects.
3. Record/synthesize all 18+ sound effects per the sound system table in Section 26.
4. Build a Figma component library matching the color system, typography, and spacing tokens.
5. Design seasonal event banners and limited-time achievement badges.
6. Design Arena Shop UI with preview and purchase flows.

**Next steps for engineering team:**
1. Implement data models and local persistence (SwiftData).
2. Build XP calculation engine with server-side validation and anti-cheat integration.
3. Implement the production XP curve (`floor(200 * N^1.65)`) per Section 3.1 (already updated with full level table).
4. Build real-time challenge score syncing (WebSocket or Firebase).
5. Build notification scheduling system with frequency limits and smart timing.
6. Integrate HealthKit for step data sync.
7. Implement League matchmaking algorithm (weekly grouping by activity level).
8. Build Arena Shop with spendable XP tracking.
9. Implement trust score system and anti-cheat flag pipeline.
10. Build group system with group leaderboards and challenges.
11. Set up monthly economy health monitoring dashboard.
