# Tempo — Complete Screen Wireframes

> **Device Reference**: iPhone 15 Pro — 393 x 852 pt
> **All measurements**: Proportional to device dimensions
> **Box-drawing legend**: Solid lines = component boundaries, dashed = interactive zones
> **Version**: 1.1 — 2026-03-24 (HIG audit, missing states, settings, error flows added)

---

## Table of Contents

1. [Tab Bar & Navigation](#1-tab-bar--navigation)
2. [Dashboard](#2-dashboard)
3. [Training](#3-training)
4. [Accountability](#4-accountability)
5. [Recovery](#5-recovery)
6. [Arena](#6-arena)
7. [Onboarding](#7-onboarding)
8. [Widgets](#8-widgets)
9. [Modals & Sheets](#9-modals--sheets)
10. [Settings](#10-settings)
11. [Notifications](#11-notifications)
12. [Error & Offline States](#12-error--offline-states)
13. [Missing Module States](#13-missing-module-states)

---

## 1. Tab Bar & Navigation

### Screen 1: Tab Bar — All 5 Tabs

```
Component: TempoTabBar
Height: 83pt (49pt bar + 34pt safe area)
Background: surface.primary with .ultraThinMaterial blur

┌─────────────────────────────────────────────────────────────┐
│                          393pt                              │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────┐       │
│  │  20pt   │  20pt   │  20pt   │  20pt   │  20pt   │ ← icon│
│  │         │         │         │         │   ●     │   size │
│  │ house   │ dumbbell│  lock   │  heart  │ trophy  │       │
│  │ .fill   │  .fill  │  .fill  │  pulse  │  .fill  │       │
│  │         │         │         │         │         │       │
│  │ Home    │ Train   │  Lock   │ Recover │ Arena   │ ← 10pt│
│  │         │         │  down   │         │         │  label │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┤       │
│  │  78pt   │  78pt   │  78pt   │  78pt   │  78pt   │ ← each│
│  │         │         │         │         │         │  cell  │
│  └─────────┴─────────┴─────────┴─────────┴─────────┘       │
│  │←──────────────── 393pt ──────────────────→│              │
│                                                             │
│  Active state:  tempo.color.primary.signal (#E63946)        │
│  Inactive state: tempo.color.secondary.ash (#9CA3AF)        │
│  Touch target: 78pt x 49pt per tab (exceeds 44pt minimum)  │
│  Badge (red dot): 6pt circle, top-right of icon, offset    │
│     (-2pt, 2pt) from icon bounds                            │
│                                                             │
│  ── 34pt safe area (home indicator) ─────────────────────── │
└─────────────────────────────────────────────────────────────┘

ON TAP: Each tab switches the root NavigationStack.
        Spring animation 200ms on icon scale (1.0 -> 1.15 -> 1.0).
```

### Screen 2: Navigation Bar Variants

```
VARIANT A — Standard Inline Title
┌─────────────────────────────────────────────────────────────┐
│ 59pt safe area top                                          │
├─────────────────────────────────────────────────────────────┤
│ 44pt                                                        │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ ◀ Back              Recovery              ⚙ 22pt     │   │
│ │ 17pt                .cardTitle             gear       │   │
│ │ chevron.left        centered              trailing   │   │
│ │                                           44x44 hit  │   │
│ └───────────────────────────────────────────────────────┘   │
│ 20pt ←────── padding ──────→ 20pt                           │
├─────────────────────────────────────────────────────────────┤
│ 0.5pt divider — tempo.color.border.default                  │
└─────────────────────────────────────────────────────────────┘

VARIANT B — Large Title (Dashboard)
┌─────────────────────────────────────────────────────────────┐
│ 59pt safe area top                                          │
├─────────────────────────────────────────────────────────────┤
│ ┌───────────────────────────────────────────────────────┐   │
│ │ Mon, Mar 24                          ⚙  🔔           │   │
│ │ tempo.callout                      22pt  22pt        │   │
│ │ text.secondary                     icons, 8pt gap    │   │
│ │                                                       │   │
│ │ Rise and grind, Nicola.                               │   │
│ │ tempo.title2, text.primary                            │   │
│ └───────────────────────────────────────────────────────┘   │
│ ←20pt                                            20pt→      │
│ Height: ~56pt content                                       │
├─────────────────────────────────────────────────────────────┤

VARIANT C — With Search Bar
┌─────────────────────────────────────────────────────────────┐
│ 59pt safe area top                                          │
├─────────────────────────────────────────────────────────────┤
│ │ ◀ Back          Exercise Library                     │   │
│ ├───────────────────────────────────────────────────────┤   │
│ │ ┌─────────────────────────────────────────────────┐   │   │
│ │ │ 🔍  Search exercises...                         │   │   │
│ │ │     36pt height, radius.lg (10pt)               │   │   │
│ │ │     bg.tertiary, text.tertiary placeholder      │   │   │
│ │ └─────────────────────────────────────────────────┘   │   │
│ │ ←16pt                                        16pt→    │   │
│ └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Dashboard

### Screen 3: Main Dashboard — Full Data

```
State: Populated (normal use)
Component: DashboardView
Navigation: Tab 1 root
Tab bar: Visible (83pt)
┌───────────────────────────────────────┐
│           iPhone 15 Pro               │
│           393 x 852 pt                │
│                                       │
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Mon, Mar 24              ⚙   🔔  │ │ ← [A] Header Bar
│ │ Rise and grind, Nicola.           │ │    56pt total
│ └───────────────────────────────────┘ │
│ ←20pt                        20pt→    │
│           ↕ 16pt gap                  │
│                                       │
│         ┌────────────┐                │ ← [B] Daily Score
│         │            │                │    Ring: 100pt dia
│         │     78     │                │    Stroke: 8pt
│         │ tempo.disp │                │    Gap at 12 o'clock
│         │   34pt Blk │                │    Fill: green gradient
│         └────────────┘                │
│          Daily Score                  │ ← tempo.caption1
│  (no sync line: auto-syncs every 5m) │
│                                       │
│           ↕ 20pt gap                  │
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │ ← [C] Quadrant Grid
│ │ BODY         ♥  │ │ FUEL      🔥 │ │    LazyVGrid 2-col
│ │                 │ │              │ │    spacing: 16pt
│ │ 72%             │ │ ┌──┐  1,842 │ │    card min-h: 160pt
│ │ Recovery        │ │ │  │ /2,400 │ │
│ │                 │ │ │52│  kcal  │ │ ← 52pt calorie ring
│ │ 68.3  52  7.2h  │ │ └──┘        │ │
│ │ HRV  RHR Sleep  │ │             │ │
│ │                 │ │ P 142g ████ │ │ ← macro bars
│ │ ═══════════──── │ │ C 205g ████ │ │    6pt height
│ │      Strain 14.2│ │ F  52g ███  │ │
│ │                 │ │             │ │
│ │ 16pt pad all    │ │ 2/4 meals   │ │
│ ├─────────────────┤ ├──────────────┤ │
│ │ card: 168.5pt w │ │ card: 168.5pt│ │
│ │ bg: surface.card│ │ radius: 16pt │ │
│ │ shadow: card    │ │              │ │
│ └─────────────────┘ └──────────────┘ │
│           ↕ 16pt                      │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ MIND         📖 │ │ MOVE      🏃 │ │
│ │                 │ │              │ │
│ │ 2h 15m          │ │ ✓ Done       │ │
│ │ 135/180 min     │ │ Push - 52m   │ │
│ │                 │ │              │ │
│ │ ████████████──  │ │ 8,432  342cal│ │
│ │                 │ │ Steps  ActCal│ │
│ │ 📅 Calc II      │ │              │ │
│ │    in 6 days    │ │ ████████──── │ │
│ │                 │ │   10K goal   │ │
│ │ 🔥 12d streak   │ │              │ │
│ └─────────────────┘ └──────────────┘ │
│           ↕ 20pt                      │
│ ┌───────────────────────────────────┐ │ ← [D] Non-Negotiables
│ │ 3/5 done - PS5 locked 🔒         │ │    Bar
│ │ ═══════════════════════─────────  │ │    6pt progress bar
│ │ ✓ Morning workout  ✓ 8h sleep    │ │    pills: flow layout
│ │ ○ 2L water  ○ Meal prep  ✓ Study │ │
│ └───────────────────────────────────┘ │
│           ↕ 16pt                      │
│ ┌───────────────────────────────────┐ │ ← [E] Insight Banner
│ │ 💡 When you sleep < 6.5h, you    │ │    dismissible
│ │    skip breakfast 67% of the  ›   │ │    swipe-left
│ └───────────────────────────────────┘ │
│                                       │
│           ↕ 50pt bottom breathing     │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ │ Home  Train  Lock  Recov Arena    │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

LAYOUT MATH:
  Screen edge padding: 20pt each side
  Quadrant width: (393 - 40 - 16) / 2 = 168.5pt
  Internal card padding: 16pt all sides (tempo.space.card.padding)
  Content width per card: 168.5 - 32 = 136.5pt
  Total content height: ~896pt (scrollable on all devices)

ON TAP (quadrant): NavigationStack push to expanded view
ON TAP (non-neg item): Toggle complete/incomplete
ON TAP (insight): Push to Pattern/Correlation view
ON PULL DOWN (60pt): Pull-to-refresh with custom ring indicator
```

### Screen 4: Main Dashboard — Loading State (Skeletons)

```
┌───────────────────────────────────────┐
│                                       │
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Mon, Mar 24              ⚙   🔔  │ │ ← Header: real data
│ │ Rise and grind, Nicola.           │ │   (always local)
│ └───────────────────────────────────┘ │
│                                       │
│         ┌────────────┐                │ ← Score Ring:
│         │    ╌╌╌╌    │                │    track pulses
│         │     --     │                │    opacity 0.3-1.0
│         │            │                │    1.5s sinusoidal
│         └────────────┘                │
│         Calculating...                │ ← text.tertiary
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ BODY         ♥  │ │ FUEL      🔥 │ │
│ │                 │ │              │ │
│ │ ░░░░            │ │   ░░░░      │ │ ← shimmer rect
│ │ ░░░░░░░░        │ │   ░░░░░    │ │    40pt x 22pt
│ │                 │ │              │ │    70pt x 12pt
│ │ ░░░  ░░░  ░░░░ │ │ ░░░░░░░░░  │ │    30pt x 14pt
│ │ ░░░  ░░░  ░░░░ │ │ ░░░░░░░░░  │ │    each
│ │                 │ │ ░░░░░░░░░  │ │
│ │ ░░░░░░░░░░░░░░ │ │              │ │ ← full-width bar
│ └─────────────────┘ └──────────────┘ │
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ MIND         📖 │ │ MOVE      🏃 │ │ ← MIND has local
│ │                 │ │              │ │   data, no skeleton
│ │ 0m              │ │ ░░░░░░░░    │ │   MOVE may show
│ │ 0/180 min       │ │ ░░░░░       │ │   skeleton briefly
│ │ ────────────    │ │              │ │
│ │ 📅 Calc II      │ │ ░░░  ░░░   │ │
│ │    in 6 days    │ │ ░░░  ░░░   │ │
│ └─────────────────┘ └──────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Non-neg: local
│ │ 0/5 done - PS5 locked 🔒         │ │   data, real content
│ │ ──────────────────────────────    │ │
│ │ ○ Morning workout  ○ 8h sleep    │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

SHIMMER ANIMATION:
  Diagonal gradient highlight (white @ 30% opacity)
  40pt wide band, 20deg angle
  Sweeps left-to-right over 1.5s, linear, repeating
  Base color: tempo.ring.track
  Placeholder corner radius: 4pt

NOTE: Each quadrant loads independently.
      BODY may show skeleton while MIND shows real data.
      Transition: shimmer crossfades to real content (0.25s).
```

### Screen 5: Main Dashboard — First Day (Empty/Partial)

```
┌───────────────────────────────────────┐
│                                       │
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Mon, Mar 24              ⚙   🔔  │ │
│ │ Welcome to Tempo, Nicola.         │ │ ← first-day greeting
│ └───────────────────────────────────┘ │
│                                       │
│         ┌────────────┐                │ ← Empty ring: track
│         │            │                │   only, no fill
│         │     --     │                │   score not yet
│         │            │                │   calculable
│         └────────────┘                │
│       Connect more sources            │ ← text.secondary
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ BODY         ♥  │ │ FUEL      🔥 │ │
│ │                 │ │              │ │
│ │ 📡              │ │ 🍴           │ │ ← disconnected
│ │ Connect Whoop   │ │ Connect      │ │   state icons
│ │ to track        │ │ NutriTrack   │ │   28pt, centered
│ │ recovery        │ │ to track     │ │
│ │                 │ │ nutrition    │ │
│ │  [ Connect ]    │ │  [ Connect ] │ │ ← pill button
│ │                 │ │              │ │   accent bg
│ └─────────────────┘ └──────────────┘ │   white text
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ MIND         📖 │ │ MOVE      🏃 │ │
│ │                 │ │              │ │
│ │ 0m              │ │ No workout   │ │
│ │ 0/120 min       │ │ Add one or   │ │
│ │ ────────────    │ │ skip.        │ │
│ │                 │ │              │ │
│ │ No upcoming     │ │ 0      0 cal│ │
│ │ exams           │ │ Steps ActCal│ │
│ │ + Add exam      │ │              │ │
│ │                 │ │ ──────────── │ │
│ └─────────────────┘ └──────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Set your daily non-negotiables    │ │ ← empty state
│ │ + Add non-negotiable              │ │   accent link text
│ └───────────────────────────────────┘ │
│                                       │
│ (No insight banner — hidden when      │
│  no data available)                   │
└───────────────────────────────────────┘

ON TAP [Connect] in BODY: Opens Whoop OAuth flow
ON TAP [Connect] in FUEL: Opens NutriTrack auth flow
ON TAP [+ Add exam]: Presents Add Exam sheet
ON TAP [+ Add non-negotiable]: Presents setup sheet
```

### Screen 5B: Main Dashboard — Error State (Data Load Failed)

```
Component: DashboardErrorState
┌───────────────────────────────────────┐
│           iPhone 15 Pro               │
│           393 x 852 pt                │
│                                       │
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Mon, Mar 24              ⚙   🔔  │ │ ← [A] Header Bar
│ │ Rise and grind, Nicola.           │ │    56pt total (local)
│ └───────────────────────────────────┘ │
│ ←20pt                        20pt→    │
│           ↕ 16pt gap                  │
│                                       │
│         ┌────────────┐                │ ← Score Ring: track
│         │    ╌╌╌╌    │                │    only, no fill
│         │     --     │                │    pulsing opacity
│         │            │                │    0.3-1.0, 1.5s
│         └────────────┘                │
│          Score unavailable            │ ← tempo.caption2
│                                       │    text.tertiary
│           ↕ 20pt gap                  │
│                                       │
│ ┌─────────────────┐ ┌──────────────┐ │ ← Quadrant Grid
│ │ BODY         ♥  │ │ FUEL      🔥 │ │    same 2-col grid
│ │                 │ │              │ │
│ │  ⚠️             │ │  ⚠️          │ │ ← error icon 28pt
│ │  Connection     │ │  Connection  │ │    centered
│ │  failed         │ │  failed      │ │    text.secondary
│ │                 │ │              │ │
│ │  [ Retry ]      │ │  [ Retry ]   │ │ ← pill button 32pt
│ │                 │ │              │ │    semantic.error bg
│ │ 14pt pad all    │ │              │ │    white text
│ ├─────────────────┤ ├──────────────┤ │
│ │ card: 168.5pt w │ │ card: 168.5pt│ │
│ │ bg: surface.card│ │ radius: 16pt │ │
│ └─────────────────┘ └──────────────┘ │
│           ↕ 16pt                      │
│ ┌─────────────────┐ ┌──────────────┐ │
│ │ MIND         📖 │ │ MOVE      🏃 │ │ ← MIND has local
│ │                 │ │              │ │    data, shows real
│ │ 0m              │ │  ⚠️          │ │    MOVE may also
│ │ 0/180 min       │ │  HealthKit   │ │    fail
│ │ ────────────    │ │  unavailable │ │
│ │ 📅 Calc II      │ │  [ Retry ]   │ │
│ │    in 6 days    │ │              │ │
│ └─────────────────┘ └──────────────┘ │
│           ↕ 20pt                      │
│ ┌───────────────────────────────────┐ │ ← Non-neg: local data
│ │ 0/5 done - PS5 locked 🔒         │ │    always available
│ │ ──────────────────────────────    │ │
│ │ ○ Morning workout  ○ 8h sleep    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Error Banner
│ │ ⚠️ Some data couldn't load.      │ │    bg: semantic.error
│ │    Pull down to retry.        ✕  │ │    at 10% opacity
│ └───────────────────────────────────┘ │    dismissible
│                                       │
│           ↕ 50pt bottom breathing     │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ │ Home  Train  Lock  Recov Arena    │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ERROR BEHAVIOR:
  Each quadrant loads independently and can fail independently.
  If ALL quadrants fail: show full-screen error view with single
    "Retry All" button (primary, 56pt) centered below the score ring.
  If SOME quadrants fail: show per-quadrant error as above.
  Pull-to-refresh retries all failed quadrants.
  Error banner auto-dismisses after 8s or on tap of ✕.
  Retry button: haptic .light, 200ms debounce.

COPY (from UX_COPY_BIBLE):
  Full failure: "Connection failed. Retry or check your signal."
  Partial failure: "Some data couldn't load. Pull down to retry."
  Whoop timeout: "Whoop is taking a while. We'll keep trying."
  NutriTrack down: "NutriTrack is unreachable. Check back soon."
```

### Screen 6: Body Quadrant Expanded

```
State: Populated | Also needed: Loading (skeleton), Error (retry)
Component: BodyExpandedView
Navigation: Push from dashboard BODY quadrant
Tab bar: Hidden (NavigationStack push, back via ◀ or swipe-from-left)
┌───────────────────────────────────────┐
│                                       │
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ◀ Body                                │ ← Nav bar, 44pt, inline
│                                       │    .cardTitle centered
│                                       │    ◀ chevron.left 17pt
│                                       │    back button 44x44 hit
├───────────────────────────────────────┤
│                                       │
│      ┌──────────────┐                 │
│      │              │  Recovery       │ ← Ring: 120pt dia
│      │    ╭────╮    │                 │   10pt stroke
│      │   │  72  │   │  "You're good  │   recovery zone
│      │   │      │   │   to push it." │   color
│      │    ╰────╯    │                 │
│      └──────────────┘                 │
│                                       │
│  ┌────────┐┌────────┐┌────────┐┌────┐│ ← Metric cards
│  │ HRV    ││ RHR    ││ Sleep  ││SpO2││   80pt wide
│  │ 68.3ms ││ 52 bpm ││ 7.2h  ││ 97%││   ~70pt tall
│  │ ^ vs   ││ v vs   ││ = avg ││Norm││   bg.card
│  │  avg   ││  avg   ││       ││    ││   radius: 10pt
│  └────────┘└────────┘└────────┘└────┘│
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ RECOVERY TREND (7 DAYS)           │ │ ← Section
│ │ [ 7D | 30D | 90D ]               │ │   segmented ctrl
│ │                                   │ │
│ │     ●                    ●        │ │ ← Line chart
│ │   ●   ●              ●           │ │   160pt height
│ │         ●    ●    ●              │ │   area fill under
│ │ ─ ─ ─ ─ ─ ─ ─ ─ 67% ─ ─ ─ ─ ─ │ │   dashed grid
│ │ ─ ─ ─ ─ ─ ─ ─ ─ 33% ─ ─ ─ ─ ─ │ │   at zone bounds
│ │                                   │ │
│ │  M    T    W   Th    F   Sa   Su  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SLEEP BREAKDOWN                   │ │
│ │ ████████████████░░░░░░░░░         │ │ ← stacked bar
│ │ Deep REM  Light  Awake            │ │   24pt height
│ │                                   │ │   12pt radius
│ │ ● Deep  1.5h    ● REM  2.0h      │ │ ← 2x2 legend
│ │ ● Light 3.2h    ● Awake 0.5h     │ │   8pt color dots
│ │                                   │ │
│ │ Performance: 85%                  │ │
│ │ In bed: 11:14 PM -> 6:38 AM      │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STRAIN BREAKDOWN                  │ │
│ │         ╭─────────────╮           │ │ ← 180deg arc
│ │     ╭───╯    14.2     ╰───╮      │ │   160pt dia
│ │   green    yellow     red         │ │   needle at
│ │ Strain zone: High                 │ │   strain/21
│ │ Recommended: Moderate (72%)       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ HISTORICAL COMPARISON             │ │
│ │ vs Yesterday: Recovery ^5%        │ │ ← green
│ │ vs Last Week: Recovery ^8%        │ │ ← green
│ │ 7-day avg Recovery: 65%           │ │
│ └───────────────────────────────────┘ │
│                                       │
└───────────────────────────────────────┘

NAVIGATION: matchedGeometryEffect from dashboard card
  Card (168.5pt, 16pt radius) -> full screen (0pt radius)
  0.4s spring, response: 0.4, damping: 0.82
  Content crossfade during transition
  Back: swipe from left edge or ◀ button

LAYOUT:
  Screen edge padding: 20pt (tempo.space.screen.edge)
  Section spacing: 20pt (tempo.space.xl)
  Card padding: 16pt (tempo.space.card.padding)
  Card radius: 16pt (tempo.radius.3xl)
  Card bg: tempo.color.surface.card
  Card shadow: tempo.shadow.card
  Metric card width: (393 - 40 - 24) / 4 = 82.25pt
  Metric card height: ~70pt
  Metric card radius: 10pt (tempo.radius.lg)
  Chart height (7d trend): 160pt
  Chart height (sleep/strain): 120pt
  Segmented control: 36pt height

LOADING STATE (skeleton):
  Ring: pulsing track, no fill, "--" text, opacity 0.3-1.0
  Metric tiles: shimmer rects (82x14pt, 60x10pt per tile)
  Charts: shimmer rects full-width, 160pt / 120pt height
  Section headers: real text (local), body = shimmer

ERROR STATE:
  Ring: shows last-known value or "--" with ⚠️ badge
  Below ring: "Whoop data unavailable. Pull down to retry."
  All sections: replaced with single centered error card
    56pt height, surface.card bg, 16pt radius
    ⚠️ icon 20pt + "Couldn't load recovery data" text.secondary
    [Retry] pill button, 32pt, semantic.error bg
```

### Screen 7: Fuel Quadrant Expanded

```
State: Populated | Also needed: Loading (skeleton), Error (retry)
Component: FuelExpandedView
Navigation: Push from dashboard FUEL quadrant
Tab bar: Hidden (NavigationStack push)
┌───────────────────────────────────────┐
│ ◀ Fuel                                │ ← Nav bar 44pt, inline
├───────────────────────────────────────┤
│                                       │
│   ┌──────────┐                        │
│   │          │  1,842 of 2,400 kcal   │ ← Ring: 120pt
│   │  1,842   │  "On track. Don't      │   10pt stroke
│   │          │   blow it at dinner."   │   purple fill
│   └──────────┘                        │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ MACROS                            │ │
│ │                                   │ │
│ │ Protein                 142/180g  │ │ ← bar height: 8pt
│ │ ████████████████████░░░░░░░       │ │   teal fill
│ │ 24% of calories                   │ │
│ │                                   │ │
│ │ Carbs                   205/280g  │ │
│ │ ██████████████████████░░░░░       │ │   yellow fill
│ │ 35% of calories                   │ │
│ │                                   │ │
│ │ Fat                      52/80g   │ │
│ │ █████████████░░░░░░░░░░░░░        │ │   orange fill
│ │ 20% of calories                   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ MEALS                             │ │
│ │                                   │ │
│ │ ✓  Breakfast            8:15 AM   │ │ ← green checkmark
│ │                          520 cal  │ │   48pt row height
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   1pt divider
│ │ ✓  Lunch               12:45 PM  │ │
│ │                          780 cal  │ │
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ ○  Dinner              (planned)  │ │ ← gray circle
│ │                            --     │ │
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ ○  Snack               (planned)  │ │
│ │                            --     │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │           + Log Meal              │ │ ← accent bg, 44pt
│ └───────────────────────────────────┘ │   white text
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ CALORIE TREND (7 DAYS)           │ │ ← bar chart
│ │ ─ ─ ─ ─ ─ 2,400 target ─ ─ ─ ─  │ │   purple bars
│ │  █   █   █   █   █   █   █       │ │   dashed target
│ │  █   █   █   █   █   █   █       │ │   line
│ │  █   █   █   █   █   █           │ │
│ │  M   T   W  Th   F  Sa  Su       │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP (logged meal): Push to meal detail
ON TAP (planned meal): Open log meal flow
ON TAP [+ Log Meal]: Present NutriTrack meal logging

LAYOUT:
  Screen edge padding: 20pt (tempo.space.screen.edge)
  Section spacing: 20pt (tempo.space.xl)
  Card padding: 16pt (tempo.space.card.padding)
  Card radius: 16pt (tempo.radius.3xl)
  Ring: 120pt diameter, 10pt stroke, purple fill
  Macro bar height: 8pt, radius: 4pt
  Meal row height: 48pt minimum (44pt content + 4pt divider padding)
  Meal row touch target: full-width x 48pt (exceeds 44pt min)
  Calorie chart: 160pt height
  CTA button [+ Log Meal]: full-width - 40pt, 44pt height
    bg: tempo.color.accent.violet, text: white, radius: tempo.radius.2xl

LOADING STATE: Ring shimmer, macro bars as shimmer rects, meal list skeleton (4 rows, 48pt each)
ERROR STATE: "NutriTrack data unavailable" card with [Retry] + [Open NutriTrack] buttons
```

### Screen 8: Mind Quadrant Expanded

```
State: Populated | Also needed: Loading (skeleton), Error (retry), Empty (no sessions today)
Component: MindExpandedView
Navigation: Push from dashboard MIND quadrant
Tab bar: Hidden (NavigationStack push)
┌───────────────────────────────────────┐
│ ◀ Mind                                │ ← Nav bar 44pt, inline
├───────────────────────────────────────┤
│                                       │
│  2h 15m  / 3h target                  │ ← display + title3
│  ████████████████████░░░░░░░░  75%    │   8pt bar, blue
│                                       │
│  "More than half. Keep going."        │ ← italic, secondary
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ TODAY'S SESSIONS                  │ │
│ │                                   │ │
│ │ 📖  Calculus II            45m    │ │ ← 52pt row
│ │     9:00 AM - 9:45 AM            │ │   caption2
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ 📖  Organic Chemistry      30m    │ │
│ │     11:15 AM - 11:45 AM          │ │
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ 📖  Calculus II            60m    │ │
│ │     2:00 PM - 3:00 PM            │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │    ▶  Start Study Session         │ │ ← blue bg, 48pt
│ └───────────────────────────────────┘ │   play.fill icon
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ UPCOMING EXAMS                    │ │
│ │                                   │ │
│ │ 🔴  Calculus II                   │ │ ← red = <= 7 days
│ │     Jun 12 (6 days)              │ │   pulsing opacity
│ │                                   │ │
│ │ 🟡  Organic Chemistry             │ │ ← yellow = 8-14d
│ │     Jun 18 (12 days)             │ │
│ │                                   │ │
│ │ + Add Exam                        │ │ ← blue text link
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STUDY TREND (7 DAYS)             │ │
│ │ ─ ─ ─ ─ ─ 3h target ─ ─ ─ ─ ─  │ │
│ │  █   █   █   █   █   █   █       │ │ ← blue bars
│ │  M   T   W  Th   F  Sa  Su       │ │
│ │ Weekly total: 14h 30m             │ │
│ │ 🔥 12-day streak                  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ FOCUS BREAKDOWN (This Week)       │ │
│ │                                   │ │
│ │ Calculus II     ██████████  42%   │ │ ← horizontal bars
│ │ Orgo Chem       ██████      28%   │ │   proportional
│ │ Anatomy         █████       22%   │ │   opacity varies
│ │ General         ██           8%   │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 9: Move Quadrant Expanded

```
State: Populated (workout done) | Also needed: Loading, Error, Empty (no workout today)
Component: MoveExpandedView
Navigation: Push from dashboard MOVE quadrant
Tab bar: Hidden (NavigationStack push)
┌───────────────────────────────────────┐
│ ◀ Move                                │ ← Nav bar 44pt, inline
├───────────────────────────────────────┤
│                                       │
│  ✓ Upper Body Push - 52m              │ ← title2 + green
│  52m · 342 cal · Avg HR 142 bpm      │   body, secondary
│  "Done and dusted."                   │   italic
│                                       │
│ ┌────────────────┐ ┌────────────────┐ │ ← Two stat cards
│ │     8,432      │ │      342       │ │   50% width each
│ │     Steps      │ │   Active Cal   │ │   bg.card
│ │    /10,000     │ │                │ │   radius: 10pt
│ └────────────────┘ └────────────────┘ │
│ ████████████████████░░░░░░░░░  84%    │ ← steps bar
│ Step pace: On track for 11,200        │ ← green text
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ HEART RATE                        │ │
│ │ Current: 72 bpm                   │ │
│ │                                   │ │
│ │  ╱╲   ╱╲╱╲    ╱╲     ╱╲  ╱╲     │ │ ← HR line chart
│ │ ╱  ╲╱╱    ╲╱╲╱  ╲╱╲╱╱  ╲╱  ╲    │ │   1.5pt stroke
│ │ ████████████                       │ │   workout = orange
│ │ 6AM  9AM  12PM  3PM  6PM  9PM    │ │   area overlay
│ │                                   │ │
│ │ Today's range: 58 - 172 bpm       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ WORKOUT HISTORY (7 days)          │ │
│ │                                   │ │
│ │ Mon  Upper Body Push    52m 342cal│ │ ← 44pt rows
│ │ Sat  Leg Day            68m 510cal│ │
│ │ Thu  Pull Day           55m 380cal│ │
│ │ Tue  Push Day           50m 330cal│ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │    ▶  Start Workout               │ │ ← orange bg, 48pt
│ └───────────────────────────────────┘ │   radius: tempo.radius.2xl
│                                       │   text: white, bodyBold
│ ── 34pt safe area ──────────────────  │   full-width - 40pt
└───────────────────────────────────────┘

LAYOUT:
  Screen edge padding: 20pt (tempo.space.screen.edge)
  Section spacing: 20pt (tempo.space.xl)
  Card padding: 16pt (tempo.space.card.padding)
  Card radius: 16pt (tempo.radius.3xl)
  Stat card width: (393 - 40 - 16) / 2 = 168.5pt
  Stat card height: ~70pt
  Steps bar height: 8pt, radius: 4pt
  HR chart height: 160pt
  Workout history row height: 44pt minimum (HIG compliant)
  CTA [Start Workout]: full-width - 40pt, 48pt height
    bg: tempo.color.accent.amber (#FF9500), text: white

EMPTY STATE (no workout today):
  Replace workout summary with centered content:
    60pt SF Symbol icon: figure.walk (tertiary)
    "No workout today." — body, text.secondary
    "Rest day or add a session." — caption, text.tertiary
    [+ Add Workout] pill button, accent bg, 44pt

LOADING STATE: Stat cards shimmer, HR chart shimmer rect, history rows shimmer
ERROR STATE: "HealthKit data unavailable" + [Open Health Settings] button
```

### Screen 10: Weekly Report View

```
┌───────────────────────────────────────┐
│ ◀ Weekly Report                       │
│ Mar 18 - Mar 24, 2026                 │
├───────────────────────────────────────┤
│                                       │
│  OVERALL SCORE                        │ ← title2
│                                       │
│         ┌──────────┐                  │ ← 100pt ring
│         │    74    │                  │   same style as
│         └──────────┘                  │   daily score
│   "Solid week. Room to grow."         │ ← italic, secondary
│                                       │
│  ┌─────────────────┐┌──────────────┐  │ ← 2x2 mini-grid
│  │ Body:  72       ││ Fuel:  78    │  │   10pt gap
│  ├─────────────────┤├──────────────┤  │   cards with
│  │ Mind:  68       ││ Move:  78    │  │   accent colors
│  └─────────────────┘└──────────────┘  │
│                                       │
│ ── BODY ─────────────────────────── ─ │ ← section divider
│ Avg Recovery: 68%  (^4% vs last wk)  │   green delta
│ Avg Sleep: 7.1h    Avg HRV: 65ms     │
│ ┌───────────────────────────────────┐ │
│ │  ●     ●                ●        │ │ ← 120pt chart
│ │    ●      ●    ●    ●            │ │
│ │  M  T  W  Th  F  Sa  Su          │ │
│ └───────────────────────────────────┘ │
│ Best day: Wednesday (92%)             │
│ Worst day: Friday (41%)              │
│                                       │
│ ── FUEL ─────────────────────────── ─ │
│ Avg Calories: 2,180/day              │
│ Compliance: 85% (6/7 on target)      │
│ Protein avg: 158g  Target: 180g      │
│ ┌───────────────────────────────────┐ │
│ │  █  █  █  █  █  █  █             │ │ ← bar chart
│ │  M  T  W  Th  F  Sa  Su          │ │
│ └───────────────────────────────────┘ │
│ ! Protein under target 5/7 days      │ ← yellow warning
│                                       │
│ ── MIND ─────────────────────────── ─ │
│ Total study: 14h 30m                  │
│ Daily avg: 2h 4m  Target: 3h         │
│ Streak: 12 days                       │
│ ┌───────────────────────────────────┐ │
│ │  █  █  █  █  █  █  █             │ │
│ └───────────────────────────────────┘ │
│ Top subject: Calculus II (42%)        │
│                                       │
│ ── MOVE ─────────────────────────── ─ │
│ Workouts: 4/5 planned                 │
│ Total active cal: 1,257              │
│ Avg steps: 9,200/day                 │
│ ┌───────────────────────────────────┐ │
│ │  █  █  █  █  █  █  █             │ │
│ └───────────────────────────────────┘ │
│ vs last week: +12% volume             │ ← green
│                                       │
│ ── AI INSIGHTS ──────────────────── ─ │
│ ┌───────────────────────────────────┐ │
│ │ 💡 Your recovery improves 15%    ▼│ │ ← expandable
│ │    when you sleep before 11 PM.   │ │
│ │ 💡 Study sessions after workouts ▼│ │
│ │    produce 20% more focused time. │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │         Share Report              │ │ ← accent, 44pt
│ └───────────────────────────────────┘ │
│                                       │
│ ← Previous Week        Next Week →    │ ← navigation
└───────────────────────────────────────┘
```

---

## 3. Training

### Screen 11: Today's Workout — Exercise List with Recovery Badge

```
State: Populated (workout planned for today)
Component: TodayWorkoutView
Navigation: Tab 2 root
Tab bar: Visible (83pt) — but obscured by pinned START WORKOUT bar
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ < Training                   ⚙  📅   │ ← nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│  Monday, March 24                     │ ← caption, secondary
│  PUSH DAY                             │ ← heroTitle 34pt
│                                       │
│ ┌───────────────────────────────────┐ │ ← Recovery Badge
│ │ 🟢 78% Recovery · Full Volume    │ │   Bar 52pt
│ │ 🔄 Synced 6:42 AM                │ │   surface bg
│ └───────────────────────────────────┘ │   radius: 12pt
│                                       │
│  ⏱ ~52 min · 6 exercises · 24 sets   │ ← caption, secondary
│                                       │
│ ┌───────────────────────────────────┐ │ ← Exercise Card
│ │ 1  BENCH PRESS              CHEST │ │   surface bg
│ │    4 x 8 @ 85kg           ↗      │ │   radius: 16pt
│ │    Last: 82.5kg x 8 ✓            │ │   min-h: 88pt
│ │    Plates: 20+10+2.5 per side    │ │
│ │                           ▶  ··· │ │
│ └───────────────────────────────────┘ │
│                 ↕ 8pt                 │
│ ┌───────────────────────────────────┐ │
│ │ 2  INCLINE DB PRESS        CHEST │ │
│ │    3 x 10 @ 32kg                 │ │
│ │    Last: 30kg x 10 ✓             │ │
│ │                           ▶  ··· │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌ ─ ─ SUPERSET A ─ ─ ─ ─ ─ ─ ─ ─ ┐ │ ← dashed border
│ │ ┌─────────────────────────────┐  │ │   supersetA color
│ │ │ 3A CABLE FLY          CHEST│  │ │   (#5E5CE6)
│ │ │    3 x 12 @ 15kg           │  │ │
│ │ │    Last: 12.5kg x 12 ✓     │  │ │
│ │ └─────────────────────────────┘  │ │
│ │           ↓ (no rest)             │ │ ← arrow.down icon
│ │ ┌─────────────────────────────┐  │ │
│ │ │ 3B LATERAL RAISE   SHOULDER│  │ │
│ │ │    3 x 15 @ 10kg           │  │ │
│ │ │    Last: 10kg x 14          │  │ │
│ │ └─────────────────────────────┘  │ │
│ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 4  OVERHEAD PRESS       SHOULDER │ │
│ │    4 x 8 @ 50kg                  │ │
│ │    Last: 47.5kg x 8 ✓            │ │
│ │    Plates: 15 per side            │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 5  TRICEP PUSHDOWN       TRICEPS │ │
│ │    3 x 12 @ 25kg                 │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │ ← dashed button
│ │        + Add Exercise             │ │   44pt height
│ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │
│                                       │
│        (120pt bottom spacer)          │
│                                       │
├───────────────────────────────────────┤ ← Pinned bottom
│ ┌───────────────────────────────────┐ │   .ultraThinMaterial
│ │      ▶  START WORKOUT             │ │   56pt button
│ │      primary bg, white text       │ │   16pt radius
│ │      bodyBold centered            │ │   16pt margins
│ └───────────────────────────────────┘ │
│ ── 34pt safe area ──────────────────  │
└───────────────────────────────────────┘

CARD ROW BREAKDOWN:
  Row 1: [number 20pt] [NAME caps, cardTitle] [MUSCLE TAG pill 24pt]
  Row 2: [prescription, body, secondary] [↗ if progressive overload]
  Row 3: [Last: history, caption, tertiary] [✓ if hit target]
  Row 4: [Plates hint, caption, tertiary] (barbell only)
  Right actions: [play.circle ▶ 17pt] [ellipsis ··· 17pt]
  All touch targets: 44pt minimum
```

### Screen 12: Today's Workout — Rest Day

```
┌───────────────────────────────────────┐
│ < Training                   ⚙  📅   │
├───────────────────────────────────────┤
│                                       │
│  Monday, March 24                     │
│  REST DAY                             │ ← heroTitle
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🟢 78% Recovery · Resting        │ │
│ └───────────────────────────────────┘ │
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ 🧘   │                 │ ← 80pt illustration
│              └──────┘                 │
│                                       │
│      Your body builds muscle          │ ← body, secondary
│      while you rest.                  │   centered
│                                       │
│      Next workout: Tomorrow           │
│      PULL DAY                         │ ← bodyBold, primary
│                                       │
│ ┌───────────────────────────────────┐ │
│ │   🧘  Start a Mobility Flow      │ │ ← secondary button
│ │       surface bg, 44pt            │ │   12pt radius
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │   💪  I want to train anyway      │ │ ← text-only button
│ │       secondary text, 44pt        │ │
│ └───────────────────────────────────┘ │
│                                       │
└───────────────────────────────────────┘

ON TAP [Mobility]: Navigate to pre-built 15-20m session
ON TAP [Train anyway]: Bottom sheet with quick workout options
  + Warning: "Overtraining can hurt your progress." in yellow
```

### Screen 13: Today's Workout — Football Day

```
┌───────────────────────────────────────┐
│ < Training                   ⚙  📅   │
├───────────────────────────────────────┤
│                                       │
│  Wednesday, March 26                  │
│  FOOTBALL DAY                         │ ← heroTitle
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🟢 72% Recovery · Match Day      │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⚽  Football @ 8:00 PM            │ │ ← event card
│ │    Location: Campo Sportivo       │ │   surface bg
│ │    Duration: ~90 min              │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ PRE-MATCH PREP (Optional)        │ │ ← section header
│ │                                   │ │
│ │ 1  Foam Roll - Lower Body        │ │
│ │    10 min                         │ │
│ │                                   │ │
│ │ 2  Dynamic Stretching             │ │
│ │    8 min                          │ │
│ │                                   │ │
│ │ 3  Activation - Glutes/Core      │ │
│ │    7 min                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │      ▶  START PRE-MATCH PREP     │ │ ← primary CTA
│ └───────────────────────────────────┘ │
│                                       │
│  Tomorrow: REST or UPPER BODY         │ ← caption, tertiary
│  (depends on recovery after match)    │
└───────────────────────────────────────┘
```

### Screen 14: Active Workout — During a Set

```
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Workout Header
│ │ X End    PUSH DAY    ⏱ 34:12     │ │   52pt height
│ │ red      captionBold  metricSmall │ │   bottom 0.5pt
│ │ 44pt hit  secondary   monospaced  │ │   divider
│ └───────────────────────────────────┘ │
│                                       │
│  BENCH PRESS                          │ ← sectionHeader
│  4 x 8 @ 85kg · Last: 82.5kgx8      │ ← body, secondary
│  ↗ 2.5kg from last session           │ ← caption, primary
│                                       │
│ ┌───────────────────────────────────┐ │ ← Set Logging Row
│ │                                   │ │   surface bg
│ │  SET 1                 TARGET: 8  │ │   16pt radius
│ │                                   │ │   16pt padding
│ │  ┌────┐┌──┐┌──────────┐┌──┐┌────┐│ │
│ │  │-2.5││ -││    85    ││ +││+2.5││ │ ← Weight input
│ │  │56x ││44││  130x48  ││44││56x ││ │   SF Mono 32pt
│ │  │36pt││x ││ surfElev ││x ││36pt││ │   stepper 44x44
│ │  └────┘│44││  12pt rad││44│└────┘│ │   quick-add 56x36
│ │        └──┘└──────────┘└──┘  kg  │ │
│ │                                   │ │
│ │       ┌──┐┌──────────┐┌──┐       │ │ ← Reps input
│ │       │ -││     8    ││ +│ reps  │ │   same style
│ │       └──┘└──────────┘└──┘       │ │   no quick-add
│ │                                   │ │
│ │  Plates: 20 + 10 + 2.5 each side │ │ ← caption, tertiary
│ │                                   │ │
│ │       ┌─────────────────┐         │ │ ← DONE button
│ │       │   ✓  CHECK DONE │         │ │   160pt x 48pt
│ │       │   primary bg    │         │ │   14pt radius
│ │       │   bodyBold white│         │ │   center
│ │       └─────────────────┘         │ │
│ │                                   │ │
│ │  RPE (optional):                  │ │ ← 5 circles
│ │   ○    ○    ○    ○    ○           │ │   32pt dia
│ │   6    7    8    9   10           │ │   8pt spacing
│ └───────────────────────────────────┘ │
│                                       │
│ ── Completed Sets ─────────────────── │ ← divider + caption
│                                       │
│ (empty - no sets completed yet)       │ ← tertiary, italic
│                                       │
├───────────────────────────────────────┤ ← Bottom Nav
│ Exercise 1 of 6                       │   pinned
│ ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    │   3pt progress bar
│                                       │
│  ◀ PREV         REST         NEXT ▶  │   56pt height
└───────────────────────────────────────┘

WEIGHT INPUT METHODS:
  1. Smart Stepper: tap +/- buttons (default)
  2. Scroll Wheel: long-press (500ms) the weight number
  3. Direct Keypad: tap the weight number
  Haptic: .rigid on stepper, .medium on quick-add
```

### Screen 15: Active Workout — Rest Timer Countdown

```
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ X End    PUSH DAY    ⏱ 38:42     │ │
│ └───────────────────────────────────┘ │
│                                       │
│  BENCH PRESS                          │
│  Set 2 of 4 complete                  │
│                                       │
│                                       │
│                                       │
│           ┌──────────────┐            │ ← Rest Timer Circle
│           │              │            │   200pt diameter
│           │              │            │   border pulses
│           │    2:34      │            │   1s easeInOut
│           │   timerDisp  │            │
│           │    72pt      │            │   At <= 10s:
│           │              │            │   faster pulse
│           │              │            │   0.5s cycle
│           └──────────────┘            │   haptic: .light x2
│                                       │
│         ┌────┐          ┌────┐        │ ← adjust buttons
│         │-30s│          │+30s│        │   44pt touch
│         └────┘          └────┘        │   secondary text
│                                       │
│      ┌──────────────────────┐         │
│      │     SKIP REST        │         │ ← ghost button
│      │  secondary text, 44pt│         │   text only
│      └──────────────────────┘         │
│                                       │
│  Next: INCLINE DB PRESS               │ ← caption
│  3 x 10 @ 32kg                        │   tertiary
│                                       │
├───────────────────────────────────────┤
│ Exercise 1 of 6                       │
│ ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    │
│  ◀ PREV         REST         NEXT ▶  │
└───────────────────────────────────────┘

AT 0:00:
  Haptic: .warning + chime
  If backgrounded: push notification
  Auto-advance to next set
```

### Screen 16: Active Workout — Between Exercises

```
┌───────────────────────────────────────┐
│ ┌───────────────────────────────────┐ │
│ │ X End    PUSH DAY    ⏱ 42:15     │ │
│ └───────────────────────────────────┘ │
│                                       │
│  INCLINE DB PRESS                     │ ← New exercise
│  3 x 10 @ 32kg · Last: 30kgx10       │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │  SET 1                 TARGET: 10 │ │
│ │                                   │ │
│ │       ┌──┐┌──────────┐┌──┐       │ │
│ │       │ -││    32    ││ +│  kg   │ │ ← DB: no quick-add
│ │       └──┘└──────────┘└──┘       │ │   outer buttons
│ │                                   │ │   (increment: 2kg)
│ │       ┌──┐┌──────────┐┌──┐       │ │
│ │       │ -││    10    ││ +│ reps  │ │
│ │       └──┘└──────────┘└──┘       │ │
│ │                                   │ │
│ │       ┌─────────────────┐         │ │
│ │       │   ✓  CHECK DONE │         │ │
│ │       └─────────────────┘         │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── Completed Sets ─────────────────── │
│                                       │
│ (previous exercise completed)         │
│                                       │
├───────────────────────────────────────┤
│ Exercise 2 of 6                       │
│ ████████░░░░░░░░░░░░░░░░░░░░░░░░░    │
│  ◀ PREV         REST         NEXT ▶  │
└───────────────────────────────────────┘

EXERCISE TRANSITION:
  Horizontal slide animation (300ms)
  Previous slides left, new slides in from right
  Swipe left/right also navigates
```

### Screen 17: Workout Summary (Post-Workout)

```
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│           WORKOUT COMPLETE            │ ← sectionHeader
│                                       │
│         ┌──────────────┐              │ ← Completion ring
│         │              │              │   animates 0->100%
│         │    ✓ 100%    │              │   800ms easeInOut
│         │              │              │
│         └──────────────┘              │
│                                       │
│  PUSH DAY                             │ ← heroTitle
│  Monday, March 24                     │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SUMMARY                           │ │
│ │                                   │ │
│ │  Duration          52:34          │ │ ← stat rows
│ │  Total Volume      12,450 kg      │ │
│ │  Sets Completed    24/24          │ │
│ │  Avg RPE           7.8            │ │
│ │  Est. Calories     342            │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ PERSONAL RECORDS 🏆               │ │ ← gold section
│ │                                   │ │   only if PRs hit
│ │ 🥇 Bench Press  87.5kg x 8       │ │   prGold shimmer
│ │    New estimated 1RM: 110.5kg     │ │   confetti burst
│ │                                   │ │
│ │ 🥈 Overhead Press  52.5kg x 8    │ │
│ │    Previous best: 50kg x 8       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ EXERCISE BREAKDOWN                │ │
│ │                                   │ │
│ │ ✓ Bench Press     4x8 @ 85-87.5  │ │
│ │ ✓ Incline DB      3x10 @ 32      │ │
│ │ ✓ Cable Fly       3x12 @ 15      │ │ ← green checks
│ │ ✓ Lateral Raise   3x15 @ 10      │ │
│ │ ✓ OH Press        4x8 @ 50-52.5  │ │
│ │ ✓ Tri Pushdown    3x12 @ 25      │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │          SAVE & CLOSE             │ │ ← primary, 56pt
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │          Share Workout            │ │ ← secondary, 44pt
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 18: Week Plan View (7-Day Grid)

```
┌───────────────────────────────────────┐
│ ◀ Training         Week Plan    ⚙     │
├───────────────────────────────────────┤
│                                       │
│  ← Mar 18 - Mar 24 →                 │ ← week navigation
│                                       │
│ ┌──────┬──────┬──────┬──────┐        │ ← 7-day grid
│ │ MON  │ TUE  │ WED  │ THU  │        │   horizontal scroll
│ │      │      │      │      │        │   each: 100pt wide
│ │ PUSH │ PULL │ REST │ LEG  │        │
│ │  ✓   │  ✓   │  —   │ 🟢   │        │   ✓=done, 🟢=today
│ │ 52m  │ 55m  │      │      │        │   —=rest
│ │      │      │      │      │        │
│ │ 6ex  │ 6ex  │      │ 5ex  │        │
│ │ 24s  │ 24s  │      │ 20s  │        │
│ ├──────┼──────┼──────┼──────┤        │
│ │ FRI  │ SAT  │ SUN  │              │
│ │      │      │      │              │
│ │ PUSH │ ⚽   │ REST │              │
│ │      │FTBALL│      │              │
│ │      │      │      │              │
│ │ 6ex  │ 90m  │      │              │
│ │ 24s  │      │      │              │
│ └──────┴──────┴──────┘              │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ WEEK STATS                        │ │
│ │ Planned sessions: 4 gym + 1 ftbl │ │
│ │ Completed: 2/5                    │ │
│ │ Est. total time: 3h 50m          │ │
│ │ Volume target: ~45,000 kg        │ │
│ └───────────────────────────────────┘ │
│                                       │
│ Recovery-based adjustments active     │ ← info text
│ Workouts adapt to daily Whoop data    │   caption, tertiary
└───────────────────────────────────────┘

ON TAP (day cell): Navigate to that day's workout view
ON TAP (empty day): Option to add workout or set as rest
```

### Screen 19: Exercise Library (Search + Filters)

```
┌───────────────────────────────────────┐
│ ◀ Back          Exercise Library      │
├───────────────────────────────────────┤
│ ┌───────────────────────────────────┐ │
│ │ 🔍  Search exercises...           │ │ ← search bar
│ └───────────────────────────────────┘ │   36pt, radius 10pt
│                                       │
│ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐│ ← filter chips
│ │All ││Ches││Back││Legs││Shldr││Arms││   horizontal scroll
│ │    ││ t  ││    ││    ││     ││    ││   24pt height
│ └────┘└────┘└────┘└────┘└────┘└────┘│   pill radius
│                                       │   selected = primary
│ ┌────┐┌──────┐┌────────┐┌──────────┐│ ← equipment filter
│ │All ││Barbell││Dumbbell││Cable/Mach││   second row
│ └────┘└──────┘└────────┘└──────────┘│
│                                       │
│ POPULAR                               │ ← section header
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ BENCH PRESS           Chest      │ │ ← exercise row
│ │ Barbell · Compound                │ │   min-h: 64pt
│ │ ───────────────────────────────── │ │
│ │ SQUAT                  Quads     │ │
│ │ Barbell · Compound                │ │
│ │ ───────────────────────────────── │ │
│ │ DEADLIFT               Back      │ │
│ │ Barbell · Compound                │ │
│ │ ───────────────────────────────── │ │
│ │ OVERHEAD PRESS         Shoulders │ │
│ │ Barbell · Compound                │ │
│ │ ───────────────────────────────── │ │
│ │ LAT PULLDOWN           Back      │ │
│ │ Cable · Compound                  │ │
│ │ ───────────────────────────────── │ │
│ │ DUMBBELL CURL          Biceps    │ │
│ │ Dumbbell · Isolation              │ │
│ └───────────────────────────────────┘ │
│                                       │
│ 150+ exercises                        │ ← footer count
└───────────────────────────────────────┘

ON TAP (exercise): Navigate to Exercise Detail view
ON TAP (from add flow): Select exercise, dismiss to workout
```

### Screen 20: Exercise Detail View

```
┌───────────────────────────────────────┐
│ ◀ Library          Bench Press        │
├───────────────────────────────────────┤
│                                       │
│ ┌───────────────────────────────────┐ │
│ │                                   │ │ ← Demo area
│ │        (Exercise animation        │ │   looping GIF
│ │         or illustration)          │ │   200pt height
│ │                                   │ │   surface bg
│ └───────────────────────────────────┘ │
│                                       │
│  BENCH PRESS                          │ ← heroTitle
│                                       │
│ ┌────┐ ┌──────────┐ ┌────────┐       │ ← info pills
│ │Chest│ │ Barbell  │ │Compound│       │   24pt height
│ └────┘ └──────────┘ └────────┘       │   pill radius
│                                       │
│  Secondary: Triceps, Anterior Delts   │ ← caption
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ YOUR STATS                        │ │
│ │                                   │ │
│ │ Current 1RM:  110.5 kg           │ │
│ │ Best Set:     87.5kg x 8         │ │
│ │ Total Volume: 24,500 kg (30d)    │ │
│ │ Sessions:     12 (30d)           │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ PROGRESS (e1RM)                   │ │ ← line chart
│ │ [ 30D | 90D | ALL ]              │ │   200pt height
│ │                                   │ │
│ │     ●  ●  ●                       │ │
│ │   ●         ●  ●  ●              │ │
│ │  ●                    ●           │ │
│ │                                   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ INSTRUCTIONS                      │ │
│ │ 1. Lie flat on bench, feet flat   │ │
│ │ 2. Grip bar shoulder-width...     │ │
│ │ 3. ...                            │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 21: Progress Chart (Per Exercise)

```
┌───────────────────────────────────────┐
│ ◀ Bench Press      Progress           │
├───────────────────────────────────────┤
│                                       │
│  ESTIMATED 1RM                        │ ← section
│                                       │
│  110.5 kg                             │ ← display font
│  ^2.5kg from last month              │ ← green delta
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ [ 30D | 90D | 1Y | ALL ]         │ │ ← time selector
│ │                                   │ │
│ │ 115─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │ ← line chart
│ │     ╱╲                            │ │   200pt height
│ │ 110─╱──╲────╱╲──────────●        │ │   scrub mode
│ │   ╱╱    ╲╱╱    ╲╱╲  ╱╱           │ │   on long-press
│ │ 105─ ─ ─ ─ ─ ─ ─ ─╲╱─ ─ ─ ─ ─  │ │
│ │                                   │ │
│ │ 100─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │                                   │ │
│ │ Feb 24  Mar 3  Mar 10  Mar 17 24  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ VOLUME TREND                      │ │
│ │                                   │ │
│ │  █   █   █   █                    │ │ ← bar chart
│ │  █   █   █   █                    │ │   weekly totals
│ │ W1  W2  W3  W4                    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SESSION HISTORY                   │ │
│ │                                   │ │
│ │ Mar 24  4x8 @ 85-87.5kg  🏆 PR   │ │
│ │ Mar 21  4x8 @ 82.5-85kg          │ │
│ │ Mar 17  4x8 @ 82.5kg             │ │
│ │ Mar 14  4x8 @ 80-82.5kg          │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

---

## 4. Accountability

### Screen 22: Lockdown Main — Tasks In Progress, PS5 Locked

```
State: Populated (tasks in progress)
Component: LockdownView
Navigation: Tab 3 root
Tab bar: Visible (83pt) — obscured by pinned bottom bar
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│            LOCKDOWN            ⚙      │ ← headline, caps
│                                       │
│  Monday, March 24                     │ ← title3, secondary
│                                       │
│ ┌───────────────────────────────────┐ │ ← Status Banner
│ │ ┌──────┐                          │ │   80pt height
│ │ │      │  LOCKED  🔒              │ │   bg.card, 16pt rad
│ │ │ 47%  │  4h 32m until PS5 time  │ │   ProgressRing 64pt
│ │ │      │                          │ │   locked.red icon
│ │ └──────┘                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Study Card
│ │ 📖  Study              1h 23m/2h │ │   IN PROGRESS
│ │ MANUAL  ██████████░░░░░     69%  │ │   blue border
│ │          Last: 25m Calc 2:34 PM  │ │   blue icon
│ │                    Start Timer ▶ │ │   action button
│ └───────────────────────────────────┘ │   28pt pill
│            ↕ 12pt spacing             │
│ ┌───────────────────────────────────┐ │ ← Training Card
│ │ 🏋️  Training              DONE ✓ │ │   COMPLETED
│ │ WHOOP  ████████████████████ 100% │ │   green border
│ │          45 min recorded          │ │   green icon
│ └───────────────────────────────────┘ │   subtle green tint
│                                       │
│ ┌───────────────────────────────────┐ │ ← Meals Card
│ │ 🍴  Meals                   2/3  │ │   IN PROGRESS
│ │ NUTRITRACK ██████████░░░░   67%  │ │   blue border
│ │         Next: Dinner before 8pm  │ │
│ │                  Log in NutriTrk ▶│ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Custom Card
│ │ ⭐  Read 30 min      NOT STARTED │ │   NOT STARTED
│ │ MANUAL  ░░░░░░░░░░░░░░░░░   0%  │ │   default border
│ │                                   │ │   tertiary icon
│ └───────────────────────────────────┘ │
│                                       │
├───────────────────────────────────────┤ ← Leisure Status
│ LEISURE STATUS                        │   pinned, 96pt
│ 🔒 Complete 1 more to unlock         │   blur material
│ ████████████████████████░░░░░░░░░░    │   gradient bar
├───────────────────────────────────────┤   red->amber->green
│ ┌───────────────────────────────────┐ │
│ │   ▶  START STUDY TIMER            │ │ ← Quick Action
│ │   gradient blue bg, 56pt          │ │   16pt radius
│ │   headline white, caps            │ │
│ └───────────────────────────────────┘ │
│ ── Tab Bar ─────────────────────────  │
└───────────────────────────────────────┘

CARD STATES (border color / icon tint):
  Not Started: border.subtle / text.tertiary
  In Progress: progress.blue / progress.blue
  Completed: unlocked.green / unlocked.green + green tint bg
  Overdue: locked.red (pulsing) / locked.red
  Skipped: border.subtle / text.tertiary, strikethrough

INTERACTIONS:
  Tap card: Expand inline (accordion) showing detail
  Long press (0.5s): Context menu
  Swipe right: Quick-complete (manual cards only)
  Swipe left: Quick-skip
  Long press (1.0s): Drag to reorder
```

### Screen 23: Lockdown Main — All Done, PS5 Unlocked

```
┌───────────────────────────────────────┐
│            LOCKDOWN            ⚙      │
│                                       │
│  Monday, March 24                     │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ┌──────┐                          │ │ ← Status Banner
│ │ │      │  UNLOCKED  🔓            │ │   unlocked.green
│ │ │ 100% │  Unlocked 2h early.     │ │   green text
│ │ │      │  Ahead of schedule.      │ │   confetti on
│ │ └──────┘                          │ │   unlock moment
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 📖  Study           2h 07m/2h ✓  │ │ ← all cards
│ │ MANUAL  ████████████████████ 100%│ │   COMPLETED
│ │          2h 07m across 4 sessions │ │   green border
│ └───────────────────────────────────┘ │   green tint
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🏋️  Training              DONE ✓ │ │
│ │ WHOOP  ████████████████████ 100% │ │
│ │          45 min strength 2:15 PM  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🍴  Meals                  3/3 ✓ │ │
│ │ NUTRITRACK ████████████████ 100% │ │
│ │          All meals logged today   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⭐  Read 30 min        30m/30m ✓ │ │
│ │ MANUAL  ████████████████████ 100%│ │
│ └───────────────────────────────────┘ │
│                                       │
├───────────────────────────────────────┤
│ LEISURE STATUS                        │ ← UNLOCKED
│ 🔓 You earned it. Enjoy your evening.│    green text
│ ████████████████████████████████████  │    full green bar
│                                       │    shimmer 2 cycles
├───────────────────────────────────────┤
│ ┌───────────────────────────────────┐ │
│ │   START ANOTHER SESSION           │ │ ← outlined style
│ │   blue border, blue text, no fill │ │   (study complete)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

UNLOCK CELEBRATION:
  Lock icon spring animation: locked -> unlocked (0.5s)
  Confetti: 50 particles, gold/green/blue, 2s duration
  Haptic: triple .success, 200ms apart
  Sound: short celebratory chime (1.2s major chord)
  Green border pulse animation (2 cycles, 0.5s each)
```

### Screen 24: Focus Timer — Idle/Ready State

```
┌───────────────────────────────────────┐
│ X Close                     Settings  │ ← fullScreenCover
│                                       │
│          Session 1 of 4               │ ← subheadline
│      ┌───────────────────┐            │    secondary
│      │ Calculus II    ▼  │            │ ← subject pill
│      └───────────────────┘            │   cardElevated bg
│                                       │   tap: picker sheet
│                                       │
│                                       │
│          ┌────────────────┐           │ ← Circular Timer
│          │                │           │   260pt diameter
│          │                │           │   8pt stroke
│          │    25:00       │           │   progress.blue
│          │    timer 72pt  │           │   full ring
│          │                │           │
│          │                │           │
│          └────────────────┘           │
│              READY                    │ ← caption1, caps
│                                       │   letter-spacing +2
│                                       │
│     Today's total: 1h 23m / 2h       │ ← callout
│                                       │   secondary
│                                       │
│                                       │
│     🤚                         🔊    │ ← secondary buttons
│  Distracted                  Ambient  │   icon above label
│                                       │   24pt icons
│                                       │
│                                       │
│  ┌───┐  ┌────────────────┐  ┌───┐    │ ← control buttons
│  │ ■ │  │     START      │  │ ▶▶│    │   Stop: 48pt circle
│  │48p│  │   160 x 64pt   │  │48p│    │   Start: 160x64 pill
│  └───┘  │   blue bg      │  └───┘    │   Skip: 48pt circle
│  Stop   └────────────────┘  Skip     │
│                                       │
└───────────────────────────────────────┘

SESSION TYPES (selectable in settings):
  Pomodoro:   25m focus / 5m break (15m long break after 4)
  Long Focus: 50m focus / 10m break
  Deep Work:  90m focus / 20m break
  Custom:     5-120m / 1-30m
```

### Screen 25: Focus Timer — Active Countdown

```
┌───────────────────────────────────────┐
│ X Close                     Settings  │
│                                       │
│          Session 2 of 4               │
│      ┌───────────────────┐            │
│      │ Calculus II    ▼  │            │
│      └───────────────────┘            │
│                                       │
│                                       │
│          ┌────────────────┐           │ ← Timer draining
│          │                │           │   clockwise from
│          │   ████         │           │   12 o'clock
│          │  █    █        │           │   progress.blue
│          │  █18:42█       │           │   fill
│          │  █    █        │           │
│          │   ████         │           │   Background:
│          │                │           │   subtle blue
│          └────────────────┘           │   radial gradient
│           FOCUS TIME                  │   3% opacity
│                                       │   pulsating
│     Today's total: 1h 23m / 2h       │
│                                       │
│     Focus Score: 87                   │ ← real-time score
│                                       │
│     🤚                         🔊    │
│  Distracted                  Ambient  │
│     ● 2                     playing   │ ← red badge count
│                                       │   blue when active
│                                       │
│  ┌───┐  ┌────────────────┐  ┌───┐    │
│  │ ■ │  │     PAUSE      │  │ ▶▶│    │
│  └───┘  │   blue bg      │  └───┘    │
│  Stop   └────────────────┘  Skip     │
│                                       │
└───────────────────────────────────────┘

DURING ACTIVE:
  Screen auto-lock disabled
  Colon blinks when PAUSED (opacity 1.0 -> 0.3, 1s cycle)
  Distraction counter: tap shows floating "+1" animation
  Ambient sound plays via AVAudioSession .ambient category
```

### Screen 26: Focus Timer — Break

```
┌───────────────────────────────────────┐
│ X Close                     Settings  │
│                                       │
│          Break — Session 2 of 4       │
│                                       │
│                                       │
│                                       │
│          ┌────────────────┐           │ ← Green ring
│          │                │           │   draining
│          │   ████         │           │   unlocked.green
│          │  █    █        │           │
│          │  █ 3:42 █      │           │   Background:
│          │  █    █        │           │   subtle green
│          │   ████         │           │   radial gradient
│          │                │           │
│          └────────────────┘           │
│           BREAK TIME                  │ ← green text
│                                       │
│     "The mind is not a vessel         │ ← motivational
│      to be filled, but a fire         │   quote during
│      to be kindled." — Plutarch       │   breaks
│                                       │
│     Today's total: 1h 48m / 2h       │
│                                       │
│                                       │
│                                       │
│  ┌───┐  ┌────────────────┐  ┌───┐    │
│  │ ■ │  │   SKIP BREAK   │  │ ▶▶│    │
│  └───┘  │  green outline  │  └───┘    │
│  Stop   └────────────────┘  Next     │
│                                       │
└───────────────────────────────────────┘
```

### Screen 27: Non-Negotiable Setup (Add/Edit)

```
┌───────────────────────────────────────┐
│ ◀ Back       Non-Negotiables    Done  │
├───────────────────────────────────────┤
│                                       │
│  YOUR DAILY NON-NEGOTIABLES           │ ← title1
│  These must be done before leisure.   │ ← body, secondary
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 📖  Study 2h               [edit]│ │ ← existing items
│ │     Timed · Auto-tracked          │ │   with edit button
│ │     MANUAL                        │ │   drag handles
│ └───────────────────────────────────┘ │   on right edge
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🏋️  Training               [edit]│ │
│ │     Binary · Auto-tracked         │ │
│ │     WHOOP                         │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🍴  Eat 3 meals            [edit]│ │
│ │     Counter · Auto-tracked        │ │
│ │     NUTRITRACK                    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⭐  Read 30 min            [edit]│ │
│ │     Timed · Manual                │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │
│ │    + Add Non-Negotiable           │ │ ← dashed button
│ │    (max 8)                        │ │
│ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │
│                                       │
│ ── ADD FORM (when + tapped) ──────── │
│                                       │
│  Name                                 │
│  ┌───────────────────────────────┐    │
│  │ e.g. "Meditate 10 min"       │    │ ← text field, 48pt
│  └───────────────────────────────┘    │
│                                       │
│  Icon                                 │
│  ○⭐ ○📖 ○💧 ○🧘 ○🏃 ○✏️ ○☎️ ○🎯   │ ← icon selector
│                                       │
│  Tracking Type                        │
│  ┌──────┐ ┌──────┐ ┌──────┐          │
│  │ Timed│ │Count │ │Yes/No│          │ ← 3 options
│  └──────┘ └──────┘ └──────┘          │
│                                       │
│  Target (if Timed):  [30] minutes     │ ← stepper
│                                       │
│ ┌───────────────────────────────────┐ │
│ │           ADD                     │ │ ← primary, 56pt
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 28: Streak Calendar Heatmap

```
┌───────────────────────────────────────┐
│ ◀ Lockdown      Consistency           │
├───────────────────────────────────────┤
│                                       │
│  🔥 CURRENT STREAK                    │
│                                       │
│      47                               │ ← streakNumber
│      DAYS                             │   56pt bold
│                                       │   streak.gold
│  Best ever: 52 days                   │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Heatmap Calendar
│ │                                   │ │   12 months visible
│ │  Jan ░░░░░░░                      │ │   each cell: 12pt
│ │  Feb ░░░░███░░░░░                 │ │   4pt gap
│ │  Mar ░░░░████████░░               │ │
│ │  Apr ░░░█████████████░            │ │   Colors:
│ │  May ░░███████████████░           │ │   ░ = missed
│ │  Jun ░████████████████░░          │ │   █ = completed
│ │  Jul ░░░░░░░███████████░          │ │   ❄ = freeze used
│ │  Aug ░░░████████████████          │ │
│ │  Sep ████████████████████         │ │   Scroll up/down
│ │  Oct █████████████████████        │ │   for more months
│ │  Nov ████████████████████░        │ │
│ │  Dec █████████████████████        │ │
│ │                                   │ │
│ │  ■ Perfect   ■ Partial   ░ Missed │ │ ← legend
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STATS                             │ │
│ │                                   │ │
│ │ Perfect days this month:  18/24   │ │
│ │ Completion rate (90d):    87%     │ │
│ │ Streak freezes remaining: 2/3    │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP (calendar cell): Show that day's detail inline
  - What was completed, what was missed
  - Total completion percentage
```

### Screen 29: Exam Mode Active View

```
┌───────────────────────────────────────┐
│            LOCKDOWN            ⚙      │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Exam Mode Banner
│ │ 🎓  EXAM MODE ACTIVE             │ │   amber bg
│ │     Calculus II — Jun 12          │ │   black text
│ │     6 days remaining              │ │   prominent
│ │     Study target: 4h/day          │ │
│ └───────────────────────────────────┘ │
│                                       │
│  Monday, March 24                     │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Status Banner
│ │ ┌──────┐                          │ │   (same as normal
│ │ │ 32%  │  LOCKED  🔒              │ │    but exam mode
│ │ └──────┘  2h 15m until PS5       │ │    adds urgency)
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Study card
│ │ 📖  Calculus II        1h 18m/4h │ │   ELEVATED priority
│ │ MANUAL  ████████░░░░░░░     33%  │ │   amber highlight
│ │          Start a deep focus       │ │
│ │                    Start Timer ▶ │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🏋️  Training          AUTO ✓     │ │ ← Normal cards
│ │ ... (same as normal)              │ │   below study
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Exam mode stats
│ │ EXAM WEEK STATS                   │ │
│ │ Day 3 of exam mode               │ │
│ │ Total study: 9h 30m              │ │
│ │ Daily avg: 3h 10m (target: 4h)   │ │
│ │ ████████████████░░░░░░░░  79%    │ │
│ └───────────────────────────────────┘ │
│                                       │
├───────────────────────────────────────┤
│ LEISURE STATUS                        │
│ 🔒 Exam mode. Extra discipline.      │
│ ██████████░░░░░░░░░░░░░░░░░░░░░░░    │
├───────────────────────────────────────┤
│ ┌───────────────────────────────────┐ │
│ │   ▶  START DEEP FOCUS (90 MIN)   │ │ ← exam mode CTA
│ └───────────────────────────────────┘ │   deep work default
└───────────────────────────────────────┘
```

---

## 5. Recovery

### Screen 30: Recovery Today — Green Zone

```
State: Populated (green zone, recovery 67-100%)
Component: RecoveryTodayView
Navigation: Tab 4 root
Tab bar: Visible (83pt)
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│          Recovery               ⚙     │ ← nav bar 44pt, inline
├───────────────────────────────────────┤
│                                       │
│         ┌──────────────────┐          │ ← RecoveryRing
│         │                  │          │   200pt diameter
│         │    ╭────────╮    │          │   14pt stroke
│         │   │          │   │          │   green fill
│         │   │    78    │   │          │   72pt heroScore
│         │   │ RECOVERY │   │          │   15pt heroLabel
│         │   │          │   │          │
│         │    ╰────────╯    │          │   Glow: 120pt
│         │                  │          │   radius, 15%
│         └──────────────────┘          │   opacity
│                                       │
│       ↑ 12% above your average        │ ← trendDelta 13pt
│       Monday, March 24                │ ← timestamp 12pt
│                                       │
│ ┌─────────┐┌─────────┐┌────────┐┌───┐│ ← MetricTile row
│ │♡ HRV    ││♡ RHR    ││O₂ SpO2 ││🌡 ││   4 tiles
│ │ 68 ms   ││ 52 bpm  ││ 97%    ││36.8│   88pt height
│ │ ↑ 12%   ││ ↓ 3%    ││— stable││—  ││   12pt radius
│ │ ▁▃▅▇▅▆▇ ││ ▇▅▃▁▃▅▃ ││ ▅▅▅▅▅▅││▅▅▅││   sparklines
│ └─────────┘└─────────┘└────────┘└───┘│
│                                       │
│ ── Today's Prescription ──────────── │ ← sectionTitle 20pt
│   ● green dot, 8pt                    │
│                                       │
│ ┌───────────────────────────────────┐ │ ← PrescriptionCard
│ │ 🏋️  Training                      │ │   surface.card
│ │ ─────────────────────────────────── │   16pt radius
│ │ Full send — compound lifts and    │ │   16pt padding
│ │ PRs are OK today.                 │ │
│ │ [Why this recommendation?]     ›  │ │ ← green text
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ 🍽  Meal Timing                    │ │
│ │ ─────────────────────────────────── │
│ │ Eat protein within 1h post-       │ │
│ │ training. Extra 30g carbs.        │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🛏  Bedtime                        │ │
│ │ ─────────────────────────────────── │
│ │ Target: 10:30 PM                  │ │
│ │ Sleep debt: 2.1h. Get 8.5h.      │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ☕  Caffeine Cutoff                │ │
│ │ ─────────────────────────────────── │
│ │ No caffeine after 2:00 PM.       │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 💧  Hydration                      │ │
│ │ ─────────────────────────────────── │
│ │ Target: 3.2L today.              │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── Quick Insights ───────────────── ─ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 📊 Recovery Trends   See Trends › │ │ ← teaser cards
│ │ 7-day avg: 71%  ↑ 4%             │ │
│ │ ▁▃▅▇▅▆▇                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 😴 Last Night's Sleep  Details › │ │
│ │ 7h 23m · Sleep Score: 82%        │ │
│ │ ████████████░░░                   │ │ ← sleep stage bar
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🔥 Yesterday's Strain  Details › │ │
│ │ 14.2 · Calories: 2,847           │ │
│ │ ████████████████░░░░░             │ │ ← strain bar
│ └───────────────────────────────────┘ │
│                                       │
│  Last synced: 2 min ago               │ ← timestamp
│                                       │
│  (32pt + tabBar padding)              │
└───────────────────────────────────────┘

ON TAP [Why?]: Sheet with medium detent, detailed reasoning
ON TAP (MetricTile): Expand inline with 7-day mini chart
ON TAP [See Trends]: Push Recovery Trends View
ON TAP [Details]: Push Sleep/Strain Detail View
SCROLL: Nav bar shows "● 78% Recovery" when ring off-screen
```

### Screen 31: Recovery Today — Red Zone

```
┌───────────────────────────────────────┐
│          Recovery               ⚙     │
├───────────────────────────────────────┤
│                                       │
│         ┌──────────────────┐          │
│         │    ╭────────╮    │          │ ← RED ring fill
│         │   │    28    │   │          │   recovery.red
│         │   │ RECOVERY │   │          │   red glow
│         │    ╰────────╯    │          │
│         └──────────────────┘          │
│                                       │
│       ↓ 22% below your average        │ ← red arrow
│       Monday, March 24                │
│                                       │
│ ┌─────────┐┌─────────┐┌────────┐┌───┐│ ← MetricTiles
│ │♡ HRV    ││♡ RHR    ││O₂ SpO2 ││🌡 ││   concerning vals
│ │ 42 ms   ││ 68 bpm  ││ 96%    ││37.2│   shown in red
│ │ ↓ 25%   ││ ↑ 18%   ││— stable││+0.4│   where applicable
│ └─────────┘└─────────┘└────────┘└───┘│
│                                       │
│ ── Today's Prescription ──────────── │
│   ● red dot, 8pt                      │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🏋️  Training                      │ │ ← DIFFERENT
│ │ ─────────────────────────────────── │   prescriptions
│ │ Rest day — your body needs full   │ │   for red zone
│ │ recovery. Walk or stretch only.   │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🍽  Nutrition                      │ │
│ │ ─────────────────────────────────── │
│ │ Prioritize protein — aim for      │ │ ← recovery-focused
│ │ 2g/kg body weight. Anti-          │ │   nutrition advice
│ │ inflammatory foods.               │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🛏  Bedtime                        │ │
│ │ ─────────────────────────────────── │
│ │ Target: 9:30 PM (earlier!)        │ │ ← earlier bedtime
│ │ Sleep debt: 4.5h. Critical.       │ │   urgent language
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ (same caffeine + hydration cards)     │
│ ...                                   │
└───────────────────────────────────────┘

NOTE: Entire visual tone shifts to muted/warm
  Emotional tone: "Reassuring, protective"
  Language: "Your body is rebuilding. Honor it."
```

### Screen 32: Sleep Detail with Stage Bars

```
┌───────────────────────────────────────┐
│ ◀ Recovery       Sleep Detail         │
├───────────────────────────────────────┤
│                                       │
│  LAST NIGHT                           │ ← sectionTitle
│                                       │
│  7h 23m                               │ ← metricValue 28pt
│  Sleep Score: 82%                     │ ← green text
│                                       │
│  In bed: 11:14 PM                     │ ← body, secondary
│  Woke: 6:38 AM                        │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SLEEP STAGES                      │ │
│ │                                   │ │
│ │ ████████████████████░░░░░░░░░░░░  │ │ ← 24pt stacked bar
│ │ ▓▓▓▓ Deep  ████ REM  ░░░░ Light  │ │   12pt radius
│ │ ░ Awake                           │ │
│ │                                   │ │
│ │ Deep Sleep     1h 42m      23%    │ │ ← stage details
│ │ ████████████████████               │ │   indigo
│ │                                   │ │
│ │ REM Sleep      1h 58m      27%    │ │
│ │ ██████████████████████             │ │   teal
│ │                                   │ │
│ │ Light Sleep    3h 12m      44%    │ │
│ │ ████████████████████████████████   │ │   gray
│ │                                   │ │
│ │ Awake          31m          6%    │ │
│ │ ████                               │ │   orange
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SLEEP TIMELINE                    │ │ ← horizontal chart
│ │                                   │ │   time on X axis
│ │ ─ Awake ─                         │ │   stages on Y
│ │ ─ REM ──────                      │ │   colored blocks
│ │ ─ Light ──────────                │ │
│ │ ─ Deep ──────                     │ │
│ │                                   │ │
│ │ 11PM  12AM  1AM  2AM  3AM  ...    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SLEEP TREND (7 DAYS)              │ │
│ │ [ 7D | 30D ]                      │ │
│ │                                   │ │
│ │  █   █   █   █   █   █   █       │ │ ← bar chart
│ │ ─ ─ ─ ─ 8h target ─ ─ ─ ─ ─ ─   │ │   stacked by stage
│ │  M   T   W  Th   F  Sa  Su       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ Sleep consistency score: 78%          │
│ Avg bedtime this week: 11:22 PM      │
└───────────────────────────────────────┘
```

### Screen 33: Strain Detail with HR Zones

```
┌───────────────────────────────────────┐
│ ◀ Recovery      Strain Detail         │
├───────────────────────────────────────┤
│                                       │
│  YESTERDAY'S STRAIN                   │
│                                       │
│  14.2                                 │ ← metricValue 28pt
│  High strain day                      │ ← yellow text
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STRAIN GAUGE                      │ │
│ │                                   │ │
│ │        ╭───────────────╮          │ │ ← 180deg arc
│ │    ╭───╯       ▲       ╰───╮     │ │   needle at 14.2
│ │  green    yellow    red           │ │   160pt diameter
│ │  0       10.5       21           │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ HR ZONE DISTRIBUTION              │ │
│ │                                   │ │
│ │ Zone 1 (50-60%)     12m    █     │ │ ← horizontal bars
│ │ Zone 2 (60-70%)     28m    ███   │ │   colored per zone
│ │ Zone 3 (70-80%)     45m   ██████ │ │   zone.1 through
│ │ Zone 4 (80-90%)     22m    ████  │ │   zone.6
│ │ Zone 5 (90-95%)      8m    ██    │ │
│ │ Zone 6 (95-100%)     2m    █     │ │
│ │                                   │ │
│ │ Total active: 1h 57m             │ │
│ │ Calories burned: 2,847           │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STRAIN TREND (7 DAYS)            │ │
│ │ [ 7D | 30D ]                      │ │
│ │                                   │ │
│ │  █   █   █   █   █   █   █       │ │
│ │  M   T   W  Th   F  Sa  Su       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ STRAIN vs RECOVERY CORRELATION    │ │
│ │                                   │ │
│ │ High strain yesterday (14.2)      │ │
│ │ contributed to today's moderate   │ │
│ │ recovery (72%).                   │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 34: Recovery Trends (30-Day Chart)

```
┌───────────────────────────────────────┐
│ ◀ Recovery     Recovery Trends        │
├───────────────────────────────────────┤
│                                       │
│  [ 7D | 30D | 90D ]                  │ ← time range selector
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ RECOVERY SCORE                    │ │
│ │                                   │ │
│ │ 30-day avg: 68%                   │ │
│ │ Trend: ↑ improving               │ │ ← green
│ │                                   │ │
│ │  ●                                │ │ ← line chart
│ │    ●  ●     ●                     │ │   200pt height
│ │ ─ ─ ─●─ ─ ─ ─67%─ ─●─ ─ ─ ─ ─  │ │   dashed zone
│ │            ●         ●  ●         │ │   boundaries
│ │ ─ ─ ─ ─ ─ ─ ─33%─ ─ ─ ─ ─ ─ ─  │ │   color per zone
│ │                          ●        │ │   per data point
│ │                                   │ │
│ │  1   5   10   15   20   25  30    │ │   scrub on hold
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ HRV TREND                         │ │
│ │ 30-day avg: 62ms                  │ │
│ │                                   │ │
│ │ (similar line chart, 160pt)       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ SLEEP DURATION TREND              │ │
│ │ 30-day avg: 7.0h                  │ │
│ │                                   │ │
│ │ (bar chart, 160pt)                │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ RHR TREND                         │ │
│ │ 30-day avg: 54 bpm                │ │
│ │                                   │ │
│ │ (line chart, 160pt)               │ │
│ └───────────────────────────────────┘ │
│                                       │
│  [ Compare ]                          │ ← button to
│                                       │   Historical
│                                       │   Comparison view
└───────────────────────────────────────┘
```

### Screen 35: Whoop Connection Setup

```
┌───────────────────────────────────────┐
│ ◀ Recovery     Whoop Connection       │
├───────────────────────────────────────┤
│                                       │
│  WHOOP INTEGRATION                    │ ← sectionTitle
│                                       │
│ ┌───────────────────────────────────┐ │
│ │                                   │ │
│ │  Status:  ● Connected             │ │ ← green dot
│ │                                   │ │
│ │  Last sync:   2 minutes ago       │ │
│ │  Member since: Jan 15, 2025      │ │
│ │  Device:  Whoop 4.0               │ │
│ │                                   │ │
│ │  Data points synced today:        │ │
│ │    Recovery:  ✓  78%              │ │
│ │    Sleep:     ✓  7h 23m           │ │
│ │    Strain:    ✓  14.2             │ │
│ │    HRV:       ✓  68ms            │ │
│ │    RHR:       ✓  52 bpm          │ │
│ │    SpO2:      ✓  97%             │ │
│ │    Skin Temp: ✓  36.8°C          │ │
│ │                                   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │        Sync Now                   │ │ ← primary, 48pt
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │        Disconnect Whoop           │ │ ← destructive
│ │        red text, outlined         │ │   confirmation
│ └───────────────────────────────────┘ │   required
│                                       │
│  Whoop data refreshes every 15 min   │ ← footnote
│  in the background via BGAppRefresh.  │   text.tertiary
└───────────────────────────────────────┘
```

---

## 6. Arena

### Screen 36: Arena Main — XP, Level, Leaderboard Preview

```
State: Populated (has XP, friends, challenges)
Component: ArenaView
Navigation: Tab 5 root
Tab bar: Visible (83pt)
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│  ARENA                      ⚙  👤    │ ← 34pt bold, white
│                                       │   left-aligned
│ ┌───────────────────────────────────┐ │ ← Hero Card
│ │ ┌──────┐                          │ │   88pt, #12203A
│ │ │ LVL  │  WARRIOR          🔥14   │ │   1pt border
│ │ │  14  │  ████████████░░░  72%    │ │   16pt radius
│ │ │ 48pt │  4,551 / 5,070 XP       │ │
│ │ └──────┘                          │ │   Level badge:
│ └───────────────────────────────────┘ │   48x48, silver
│                                       │
│ ┌───────────────────────────────────┐ │ ← Today's XP Card
│ │ TODAY'S XP                        │ │   min-h: 180pt
│ │                                   │ │   #12203A
│ │ ┌──────────┐   Earned: +385 XP   │ │
│ │ │   385    │   Potential: +430    │ │ ← SF Mono 48pt
│ │ │   XP     │   ────────────────   │ │   electric blue
│ │ └──────────┘   Multiplier: 1.5x  │ │   slot-machine
│ │                                   │ │   animation
│ │ 🏋️  Workout            +150 XP   │ │
│ │ 📖  Study               +80 XP   │ │ ← XP breakdown
│ │ 🍴  Meals               +45 XP   │ │   rows 32pt each
│ │ 🦶  Steps (8K)          +35 XP   │ │   emoji + label
│ │ ✓   Tasks               +50 XP   │ │   + value trailing
│ │ 🌙  Sleep               +25 XP   │ │
│ │                     See Details › │ │ ← blue text
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Leaderboard
│ │ 🏆 WEEKLY LEADERBOARD             │ │   Preview
│ │                                   │ │   ~140pt
│ │ 👑 1. Marco         2,450 XP L18 │ │   #FFD700 crown
│ │ ● 2. You           2,320 XP L14  │ │   blue highlight
│ │   3. Luca          2,180 XP L16  │ │
│ │                                   │ │
│ │ 130 XP behind #1     See All ›   │ │ ← orange gap text
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Active Challenges
│ │ ⚔️ ACTIVE CHALLENGES              │ │
│ │                                   │ │
│ │ vs Marco: Most Study Hours        │ │ ← challenge item
│ │ You: 12.5h  |  Marco: 14.2h      │ │   score in blue
│ │ ████████░░░░░░░  3 days left      │ │   if winning, red
│ │                                   │ │   if losing
│ │ Group: Weekly XP Race (5 players) │ │
│ │ You're #2          2 days left    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Recent Badges
│ │ 🏅 RECENT ACHIEVEMENTS            │ │
│ │                                   │ │
│ │ ┌────────┐  ┌────────┐           │ │   64x64 badge
│ │ │🏆 Iron │  │🏃 Road │           │ │   horizontal
│ │ │  Will  │  │Warrior │           │ │   scroll if >2
│ │ │ 30-day │  │10K x 7 │           │ │
│ │ └────────┘  └────────┘           │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Challenge CTA
│ │  ⚡ Challenge a Friend            │ │   gradient button
│ │     blue->purple, 52pt            │ │   14pt radius
│ │     bold 17pt white               │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── Tab Bar ─────────────────────────  │
└───────────────────────────────────────┘

SCROLL: Hero card shrinks (88pt->56pt) and sticks
  Level badge: 48->32pt, streak moves inline
  Spring animation 300ms

COLORS (Arena palette):
  Background: #0A1628 (deep navy)
  XP/Progress: #2D7FF9 (electric blue)
  Streak/Fire: #FF6B2C (molten orange)
  Achievements: #22C55E (emerald)
  Losses: #FF3B5C (crimson)
  Cards: #12203A, border: #1E3A5F
```

### Screen 37: Full Leaderboard with Rankings

```
┌───────────────────────────────────────┐
│ ◀ Arena        LEADERBOARD            │
├───────────────────────────────────────┤
│                                       │
│ ┌──────────┬──────────┬──────────┐    │ ← Period tabs
│ │  WEEKLY  │ MONTHLY  │ ALL-TIME │    │   36pt segmented
│ │ (active) │          │          │    │   #2D7FF9 selected
│ └──────────┴──────────┴──────────┘    │
│                                       │
│ [FRIENDS ▼]  Filter: [Total XP ▼]    │ ← scope + filter
│                                       │
│ ┌───────────────────────────────────┐ │ ← Podium (top 3)
│ │                                   │ │   180pt height
│ │        ┌────┐                     │ │
│ │        │ 👑 │                     │ │   #1: 120pt pillar
│ │  ┌───┐ │Marc│ ┌───┐              │ │   #2: 100pt pillar
│ │  │Nic│ │2450│ │Luc│              │ │   #3: 85pt pillar
│ │  │2320│ │L18 │ │2180│             │ │
│ │  │L14 │ │    │ │L16 │             │ │   Avatars: 48pt
│ │  └───┘ └────┘ └───┘              │ │   tier-colored
│ │   #2     #1     #3               │ │   borders
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Ranked List
│ │ 4. ↑2 🟢 Sara       1,980  L12  │ │   56pt rows
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ 5. ↓1 🟢 Gianluca   1,820  L11  │ │   Components:
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   rank (mono 16pt)
│ │ 6. —  🟢 Andrea     1,650  L10  │ │   movement arrow
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   online dot 8pt
│ │ 7. ↓1 🔴 Davide     1,420  L 9  │ │   avatar 36pt
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   name (15pt)
│ │ 8. —  🟢 Matteo     1,380  L 9  │ │   XP (mono 14pt)
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   level mini badge
│ │ 9. ↑3 🟢 Elena      1,200  L 8  │ │
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   Current user:
│ │10. ↓1 🔴 Filippo    1,050  L 7  │ │   blue bg 10%
│ └───────────────────────────────────┘ │   3pt left border
│                                       │
│ ┌───────────────────────────────────┐ │
│ │  👤+ Invite Friends to Leaderboard│ │ ← dashed border
│ └───────────────────────────────────┘ │   blue text
└───────────────────────────────────────┘

RANK CHANGE ANIMATION:
  Rows slide to new positions (500ms ease)
  Up: green flash, Down: red flash
  Rank number: 3D flip animation (400ms)
```

### Screen 38: Challenge Creation (Step 1: Select Metric)

```
┌───────────────────────────────────────┐
│           ─── drag ───                │ ← bottom sheet
│                                       │   full height
│  START A CHALLENGE                X   │ ← sectionHeader
│                                       │
│  Step 1: What are you competing on?   │ ← body, secondary
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 📖  Most Study Hours              │ │ ← metric options
│ │     Who can study more this week  │ │   cards, 72pt each
│ └───────────────────────────────────┘ │   tap to select
│                                       │   selected = blue
│ ┌───────────────────────────────────┐ │   border + bg
│ │ 🏋️  Most Workouts                 │ │
│ │     Complete the most sessions    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🦶  Most Steps                    │ │
│ │     Total steps over the period   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⭐  Highest XP                    │ │
│ │     Total XP earned               │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🔥  Longest Streak               │ │
│ │     Who can keep the streak alive │ │
│ └───────────────────────────────────┘ │
│                                       │
│  Duration: [ 3 days ] [ 7 days ]      │ ← segmented
│            [ 14 days] [ 30 days]      │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │     NEXT: Choose Opponent         │ │ ← primary, 56pt
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 39: Challenge Active View with Standings

```
┌───────────────────────────────────────┐
│ ◀ Arena         Challenge             │
├───────────────────────────────────────┤
│                                       │
│  ⚔️ MOST STUDY HOURS                  │ ← title
│  vs Marco · 3 days left              │ ← subtitle
│                                       │
│ ┌───────────────────────────────────┐ │
│ │                                   │ │ ← Head-to-head
│ │  ┌──────┐         ┌──────┐       │ │   avatars + scores
│ │  │ You  │   VS    │Marco │       │ │   72pt avatars
│ │  │      │         │      │       │ │
│ │  └──────┘         └──────┘       │ │
│ │                                   │ │
│ │  12.5h              14.2h         │ │ ← SF Mono, 28pt
│ │  (losing)           (winning)     │ │   red vs blue
│ │                                   │ │
│ │  Gap: 1.7h behind                │ │ ← crimson text
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ PROGRESS                          │ │
│ │                                   │ │
│ │ Day 4 of 7                        │ │ ← time progress
│ │ ████████████████░░░░░░░░░  57%    │ │   bar
│ │                                   │ │
│ │ ┌─────────────────────────────┐   │ │ ← daily breakdown
│ │ │ Day   You    Marco          │   │ │   chart
│ │ │  1    2.0h   1.5h          │   │ │
│ │ │  2    3.0h   3.5h          │   │ │
│ │ │  3    4.0h   4.2h          │   │ │
│ │ │  4    3.5h   5.0h          │   │ │
│ │ └─────────────────────────────┘   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ REWARDS                           │ │
│ │ Winner: 200 XP                    │ │
│ │ Participation: 50 XP             │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 40: Achievement Grid (Earned + Locked)

```
┌───────────────────────────────────────┐
│ ◀ Arena        Achievements           │
├───────────────────────────────────────┤
│                                       │
│  12 / 108 UNLOCKED                    │ ← title, secondary
│                                       │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐          │ ← category filter
│ │All ││Gym  ││Study││Social│          │   pill chips
│ └────┘ └────┘ └────┘ └────┘          │   horizontal scroll
│                                       │
│ ┌───────────────────────────────────┐ │
│ │                                   │ │ ← Achievement Grid
│ │ ┌──────┐ ┌──────┐ ┌──────┐       │ │   3 columns
│ │ │  🏆  │ │  🏃  │ │  📖  │       │ │   80x100 each
│ │ │ IRON │ │ ROAD │ │SCHOL.│       │ │   12pt gap
│ │ │ WILL │ │WARRIOR│ │      │       │ │
│ │ │ ✓    │ │ ✓    │ │ ✓    │       │ │   Earned: full
│ │ └──────┘ └──────┘ └──────┘       │ │   color + check
│ │                                   │ │
│ │ ┌──────┐ ┌──────┐ ┌──────┐       │ │
│ │ │  💪  │ │  🔒  │ │  🔒  │       │ │   Locked: gray
│ │ │BEAST │ │ ???  │ │ ???  │       │ │   tint + lock
│ │ │ MODE │ │      │ │      │       │ │   or ??? text
│ │ │ ✓    │ │ 62%  │ │ 0%   │       │ │
│ │ └──────┘ └──────┘ └──────┘       │ │   Progress %
│ │                                   │ │   shown for
│ │ ┌──────┐ ┌──────┐ ┌──────┐       │ │   partially
│ │ │  🔒  │ │  🔒  │ │  🔒  │       │ │   completed
│ │ │ ???  │ │ ???  │ │ ???  │       │ │
│ │ │ 25%  │ │  0%  │ │  0%  │       │ │
│ │ └──────┘ └──────┘ └──────┘       │ │
│ │                                   │ │
│ │ (continues scrolling...)          │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP (earned): Full-screen detail with badge art,
  description, date earned, stats at unlock time
ON TAP (locked with progress): Shows requirements
  and current progress toward each
ON TAP (locked ???): Shows "Keep grinding to discover
  this achievement."
```

### Screen 41: Friend List with Online Status

```
┌───────────────────────────────────────┐
│ ◀ Arena         Friends        +      │ ← + opens add sheet
├───────────────────────────────────────┤
│                                       │
│ ┌───────────────────────────────────┐ │ ← search bar
│ │ 🔍  Search friends...             │ │
│ └───────────────────────────────────┘ │
│                                       │
│  ONLINE (3)                           │ ← section header
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🟢 👤 Marco        LV18  2,450XP │ │ ← 56pt rows
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   online dot
│ │ 🟢 👤 Sara         LV12  1,980XP │ │   green = active
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   today
│ │ 🟢 👤 Luca         LV16  2,180XP │ │
│ └───────────────────────────────────┘ │
│                                       │
│  OFFLINE (4)                          │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⚫ 👤 Andrea       LV10  1,650XP │ │ ← gray dot
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │   not active
│ │ ⚫ 👤 Davide       LV 9  1,420XP │ │   today
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ ⚫ 👤 Matteo       LV 9  1,380XP │ │
│ │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ │
│ │ ⚫ 👤 Filippo      LV 7  1,050XP │ │
│ └───────────────────────────────────┘ │
│                                       │
│  PENDING (1)                          │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🟡 👤 @elena_fit   Sent 2d ago   │ │ ← pending invite
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │  👤+ Invite More Friends          │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP (friend row): Push to Friend Profile view
ON SWIPE LEFT: Remove friend (confirmation required)
```

### Screen 42: Friend Profile View

```
┌───────────────────────────────────────┐
│ ◀ Friends         Profile       ···   │ ← overflow: remove/
│                                       │   block/report
│          ┌──────────┐                 │
│          │  80x80   │                 │ ← avatar circle
│          │  AVATAR  │                 │   tier-colored
│          └──────────┘                 │   border
│          @marco_p                     │
│       ⚔️ GLADIATOR - Level 18        │
│                                       │
│ ┌────────┬────────┬────────┬────────┐ │ ← stats grid
│ │TOTAL   │WORK-   │STUDY   │MEALS   │ │   72pt cells
│ │ XP     │OUTS    │HOURS   │        │ │   mono values
│ │ 23.4K  │  186   │ 420h   │ 1,240  │ │
│ └────────┴────────┴────────┴────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ ⚡ Challenge @marco_p             │ │ ← blue gradient
│ └───────────────────────────────────┘ │   challenge CTA
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🔥 STREAK: 28 days               │ │
│ │ Longest: 45 days                  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 🏅 ACHIEVEMENT SHOWCASE           │ │
│ │                                   │ │
│ │ ┌──────┐ ┌──────┐ ┌──────┐       │ │ ← their pinned
│ │ │  🏆  │ │  💪  │ │  🎓  │       │ │   badges
│ │ │ IRON │ │BEAST │ │HONOR │       │ │
│ │ │ WILL │ │ MODE │ │ ROLL │       │ │
│ │ └──────┘ └──────┘ └──────┘       │ │
│ │                                   │ │
│ │ 24/108 Achievements               │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 📊 PERSONAL RECORDS              │ │
│ │ Bench Press 1RM:    105 kg       │ │ ← only if shared
│ │ Squat 1RM:         140 kg       │ │
│ │ Deadlift 1RM:      170 kg       │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 43: Social Feed

```
┌───────────────────────────────────────┐
│ ◀ Arena           Feed                │
├───────────────────────────────────────┤
│                                       │
│ ┌───────────────────────────────────┐ │ ← Feed item
│ │ 👤 Marco         · 2h ago        │ │   card style
│ │                                   │ │   #12203A
│ │ 🏋️ Completed Push Day             │ │   16pt radius
│ │    52 min · 12,450 kg volume     │ │
│ │    +150 XP                        │ │
│ │                                   │ │
│ │ 👍 3   💬 1              React ▶  │ │ ← reactions
│ └───────────────────────────────────┘ │
│            ↕ 8pt                      │
│ ┌───────────────────────────────────┐ │
│ │ 👤 Sara          · 4h ago        │ │
│ │                                   │ │
│ │ 🏆 Achievement Unlocked          │ │
│ │    "Road Warrior" — 10K steps    │ │   ← gold highlight
│ │    for 7 consecutive days        │ │
│ │    +75 XP                         │ │
│ │                                   │ │
│ │ 👍 5   💬 2              React ▶  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 👤 You           · 6h ago        │ │
│ │                                   │ │
│ │ 📖 Study Session Complete         │ │
│ │    2h 07m Calculus II             │ │
│ │    +80 XP                         │ │
│ │                                   │ │
│ │ 👍 2                     React ▶  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ 👤 Luca          · Yesterday     │ │
│ │                                   │ │
│ │ ⚔️ Challenge Won                  │ │
│ │    Beat Marco in "Weekly Steps"   │ │
│ │    +200 XP                        │ │
│ │                                   │ │
│ │ 👍 8   💬 4              React ▶  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ (infinite scroll, loads more)         │
└───────────────────────────────────────┘

FEED EVENTS: workout, study, achievement, PR, challenge
  win/loss, level up, streak milestone
REACTIONS: thumbs up, fire, clap, muscle (custom set at L18)
```

---

## 7. Onboarding

### Screen 44: Welcome / Value Prop (Step 1)

```
┌───────────────────────────────────────┐
│ ┌───────────────────────────────────┐ │ ← Progress bar
│ │ █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │ │   1/12 segments
│ │ 3pt height, full width - 32pt     │ │   white fill
│ └───────────────────────────────────┘ │   20% white unfill
│                                       │
│                                       │
│                                       │
│           ╭ ─ ─ ─ ─ ╮                │ ← Animation zone
│          ╱            ╲               │   4 rings converge
│         │   ○  ○  ○  ○ │             │   into 1 unified
│         │    ╲ ╱╲ ╱    │             │   ring
│         │     ●══●     │             │   amber pulse
│          ╲            ╱               │   SwiftUI Canvas
│           ╰ ─ ─ ─ ─ ╯                │
│                                       │
│                                       │
│   STOP MANAGING YOUR LIFE             │ ← SF Pro Display
│   IN 5 DIFFERENT APPS.               │   Black, 28pt
│                                       │   white, centered
│                                       │
│   Training. Nutrition.                │ ← SF Pro Text
│   Recovery. Academics.                │   Regular, 17pt
│   One system. One score.              │   70% white
│   Zero excuses.                       │   line-height 1.4x
│                                       │
│                                       │
│                                       │
│                                       │
│ ┌───────────────────────────────────┐ │ ← CTA Button
│ │         GET STARTED               │ │   full width - 32pt
│ │                                   │ │   56pt height
│ │   amber (#F59E0B) bg             │ │   14pt radius
│ │   black text, Semibold 17pt       │ │   haptic: light
│ └───────────────────────────────────┘ │
│                                       │
│ BG: true black (#000000)              │
│ Dark mode only during onboarding      │
└───────────────────────────────────────┘
```

### Screen 45: Training Setup (Step 4)

```
┌───────────────────────────────────────┐
│ ◀  ████░░░░░░░░░░░░░░░░░░░░░░░░░░   │ ← 4/12 progress
│                                       │
│     LET'S BUILD YOUR                  │ ← SF Pro Display
│     TRAINING PROFILE.                 │   Bold, 24pt, white
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Do you train?                     │ │ ← Question card
│ │ ┌───────────┐ ┌───────────┐       │ │   10% white bg
│ │ │    YES    │ │    NO     │       │ │   1pt 15% border
│ │ │  (amber)  │ │           │       │ │   pill toggles
│ │ └───────────┘ └───────────┘       │ │   50% width each
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← animates in
│ │ What do you do?                   │ │   staggered 0.1s
│ │ ┌───┐ ┌───────┐ ┌──────────┐     │ │
│ │ │Gym│ │Running│ │Team Sport│     │ │   multi-select
│ │ └───┘ └───────┘ └──────────┘     │ │   chip buttons
│ │ ┌─────┐                           │ │
│ │ │Other│                           │ │
│ │ └─────┘                           │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ How many days/week?               │ │
│ │ ○ ○ ○ ④ ○ ○ ○                    │ │ ← circular buttons
│ │ 1 2 3 4 5 6 7                    │ │   single select
│ └───────────────────────────────────┘ │   amber selected
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Preferred split?                  │ │
│ │ ┌───┐┌───────────┐┌──────────┐   │ │
│ │ │PPL││Upper/Lower││Full Body │   │ │   pills
│ │ └───┘└───────────┘└──────────┘   │ │
│ │ ┌─────────┐┌──────────────┐       │ │
│ │ │Bro Split││I Don't Know │       │ │
│ │ └─────────┘└──────────────┘       │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Experience level                  │ │
│ │ ┌─────────────────────────────┐   │ │ ← large cards
│ │ │█ Beginner                   │   │ │   amber left border
│ │ │  Less than 1yr consistent   │   │ │   when selected
│ │ └─────────────────────────────┘   │ │
│ │ ┌─────────────────────────────┐   │ │
│ │ │  Intermediate               │   │ │
│ │ │  1-3yr, compound lifts OK   │   │ │
│ │ └─────────────────────────────┘   │ │
│ │ ┌─────────────────────────────┐   │ │
│ │ │  Advanced                   │   │ │
│ │ │  3+yr, tracking overload    │   │ │
│ │ └─────────────────────────────┘   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │          CONTINUE                 │ │ ← amber, 56pt
│ └───────────────────────────────────┘ │   disabled until
│                                       │   required answered
└───────────────────────────────────────┘
```

### Screen 46: Goal / Non-Negotiable Setup (Step 6)

```
┌───────────────────────────────────────┐
│ ◀  ██████░░░░░░░░░░░░░░░░░░░░░░░░   │ ← 6/12 progress
│                                       │
│     WHAT ARE YOU                      │
│     FIGHTING FOR?                     │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ Primary goal                      │ │
│ │ ┌─────────────────────────────┐   │ │ ← goal options
│ │ │█ Build Muscle               │   │ │   52pt height each
│ │ │  Gain size and strength     │   │ │   amber left border
│ │ └─────────────────────────────┘   │ │   when selected
│ │ ┌─────────────────────────────┐   │ │
│ │ │  Lose Fat                   │   │ │
│ │ └─────────────────────────────┘   │ │
│ │ ┌─────────────────────────────┐   │ │
│ │ │  Improve Performance        │   │ │
│ │ └─────────────────────────────┘   │ │
│ │ ┌─────────────────────────────┐   │ │
│ │ │  Stay Healthy               │   │ │
│ │ └─────────────────────────────┘   │ │
│ │ ┌─────────────────────────────┐   │ │
│ │ │  All-Around                 │   │ │
│ │ └─────────────────────────────┘   │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ YOUR NON-NEGOTIABLES              │ │
│ │ These are daily. No exceptions.   │ │
│ │                                   │ │
│ │ ☑ Train                    [edit] │ │ ← pre-filled
│ │ ☑ Study 2h                [edit] │ │   from previous
│ │ ☑ Eat 3 meals             [edit] │ │   steps
│ │ ☐ ........................ [add]  │ │ ← add custom
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ What's your biggest time-waster?  │ │
│ │ ┌──────────┐ ┌──────────────┐     │ │
│ │ │PS5/Gaming│ │Social Media │     │ │ ← multi-select
│ │ │ (amber)  │ │             │     │ │
│ │ └──────────┘ └──────────────┘     │ │
│ │ ┌────────────────┐ ┌────────┐     │ │
│ │ │Netflix/Streaming│ │YouTube│     │ │
│ │ └────────────────┘ └────────┘     │ │
│ │ ┌────────────────────────────┐    │ │
│ │ │ Other: __________________ │    │ │
│ │ └────────────────────────────┘    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ When does your evening start?     │ │
│ │                                   │ │
│ │      ┌───── 7:30 PM ─────┐       │ │ ← time picker
│ │      │   (compact wheel)  │       │ │   15min increments
│ │      └────────────────────┘       │ │   5PM - 11PM range
│ │                                   │ │
│ │ This is when the drill sergeant   │ │
│ │ gets serious.                     │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │          CONTINUE                 │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 47: Whoop Connection (Step 7)

```
┌───────────────────────────────────────┐
│ ◀  ███████░░░░░░░░░░░░░░░░░░░░░░░   │ ← 7/12 progress
│                                       │
│     YOUR BODY TALKS.                  │
│     LET'S LISTEN.                     │
│                                       │
│      ┌──────────────────────┐         │
│      │                      │         │ ← Whoop band
│      │   (Whoop band image  │         │   illustration
│      │    or illustration)  │         │   centered
│      │                      │         │
│      └──────────────────────┘         │
│                                       │
│  Whoop gives Tempo your:              │ ← body, 70% white
│                                       │
│  ♡  Recovery %                        │ ← amber icons
│     Know how hard to push today       │   16pt semibold
│                                       │   14pt regular
│  😴 Sleep Score                       │
│     Track sleep debt and quality      │
│                                       │
│  🔥 Daily Strain                      │
│     See your training load            │
│                                       │
│  📊 HRV Trends                       │
│     Detect overtraining early         │
│                                       │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │        CONNECT WHOOP              │ │ ← amber, 56pt
│ │                                   │ │   triggers OAuth
│ └───────────────────────────────────┘ │
│                                       │
│          Skip for now                 │ ← 14pt, 60% white
│                                       │   shows confirmation
│                                       │   sheet listing
│                                       │   limited features
└───────────────────────────────────────┘

SUCCESS STATE:
  Button transforms to green card: "Connected!"
  Shows current recovery: "Recovery: 72%"
  Auto-advance to Step 8 after 1.5s

ERROR STATES:
  OAuth cancelled: stay on screen, no error
  Network error: "Couldn't connect. Try again?"
  Expired code: "Connection expired. Let's try again."
```

### Screen 48: Summary / First Mission (Step 12)

```
┌───────────────────────────────────────┐
│    ████████████████████████████████   │ ← 12/12 COMPLETE
│                                       │
│                                       │
│     YOU'RE LOCKED IN.                 │ ← SF Pro Display
│                                       │   Bold, 28pt, white
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ YOUR SETUP                        │ │ ← summary card
│ │                                   │ │   10% white bg
│ │ 🏋️ Training: PPL, 4 days/week    │ │
│ │ 📖 Study: 2h/day, 3 courses      │ │
│ │ 🍴 Meals: 3/day via NutriTrack   │ │
│ │ ♡  Recovery: Whoop connected      │ │
│ │ 🎮 Leisure: PS5, unlocks at 7:30 │ │
│ │                                   │ │
│ │ 4 non-negotiables set             │ │
│ │                                   │ │
│ │ Everything can be changed later   │ │ ← caption, 40% wht
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ YOUR FIRST MISSION                │ │ ← "mission" card
│ │                                   │ │   amber left border
│ │ Complete all 4 non-negotiables    │ │   4pt
│ │ today. That's it. Show Tempo      │ │
│ │ what you're made of.              │ │   amber text
│ │                                   │ │
│ │ Reward: 200 XP + "First Day"     │ │ ← reward preview
│ │ achievement                       │ │
│ └───────────────────────────────────┘ │
│                                       │
│                                       │
│ ┌───────────────────────────────────┐ │
│ │         LET'S GO                  │ │ ← amber, 56pt
│ │                                   │ │   navigates to
│ │                                   │ │   Dashboard
│ └───────────────────────────────────┘ │
│                                       │
│  "Discipline is choosing between      │ ← quote
│   what you want now and what you      │   14pt, 40% white
│   want most." — Abraham Lincoln       │   centered
└───────────────────────────────────────┘
```

---

## 8. Widgets

### Screen 49: Small Widget (158x158pt)

```
┌──────────────────────────────────────────┐
│  Small Widget — iPhone 15 Pro            │
│  158 x 158pt, 11pt content inset        │
│  Usable area: 136 x 136pt               │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ TEMPO                              │  │ ← 10pt bold
│  │ (tracking 1.5pt, secondary)        │  │   top-left
│  │                                    │  │
│  │         ┌────────┐                 │  │ ← Score ring
│  │         │        │                 │  │   52pt diameter
│  │         │   78   │                 │  │   4pt stroke
│  │         │  20pt  │                 │  │   solid zone color
│  │         └────────┘                 │  │   centered
│  │                                    │  │
│  │                                    │  │
│  │ 🟢 72% rec            7.2h 🌙     │  │ ← bottom row
│  │ ← 6pt dot              right →    │  │   8pt from bottom
│  │   11pt medium                      │  │   two metrics
│  └────────────────────────────────────┘  │
│                                          │
│  ON TAP: Deep-link tempo://dashboard     │
│  Update: every 15min TimelineProvider    │
│  BG: surface.card (light/dark adaptive)  │
└──────────────────────────────────────────┘
```

### Screen 50: Medium Widget (338x158pt)

```
┌──────────────────────────────────────────────────────────────┐
│  Medium Widget — iPhone 15 Pro                               │
│  338 x 158pt, 11pt content inset                             │
│  Usable area: 316 x 136pt                                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ TEMPO                                    Mon Mar 24  │    │
│  │                                                      │    │
│  │  ┌──────┐  ┌─────────────────┬─────────────────────┐│    │
│  │  │      │  │ BODY 72%        │ FUEL 1842/2400     ││    │
│  │  │  78  │  │ Sleep 7.2h      │ P:142 C:205 F:52   ││    │
│  │  │ 18pt │  ├─────────────────┼─────────────────────┤│    │
│  │  │      │  │ MIND 2h15m      │ MOVE ✓ Done         ││    │
│  │  └──────┘  │ 12d streak      │ 8,432 steps        ││    │
│  │  48pt ring │                 │                     ││    │
│  │  4pt stroke└─────────────────┴─────────────────────┘│    │
│  │                                                      │    │
│  │  ←── 30% ──→←────────── 70% ──────────────────────→ │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  TAP REGIONS: Score=dashboard, each quadrant=expanded view   │
│  Dividers: 1pt hairline, center vert + center horiz         │
│  Quadrant name: 9pt bold, accent color per quadrant          │
│  Metrics: 11pt medium primary, 10pt secondary                │
└──────────────────────────────────────────────────────────────┘
```

### Screen 51: Large Widget (338x354pt)

```
┌──────────────────────────────────────────────────────────────┐
│  Large Widget — iPhone 15 Pro                                │
│  338 x 354pt, 11pt content inset                             │
│  Usable area: 316 x 332pt                                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ TEMPO                                    Mon Mar 24  │    │
│  │                                                      │    │
│  │            ┌────────┐                                │    │
│  │            │   78   │  Daily Score                   │    │
│  │            │  18pt  │  10pt label                    │    │
│  │            └────────┘                                │    │
│  │            56pt ring, 5pt stroke                     │    │
│  │                                                      │    │
│  │  ┌───────────────────┐ ┌──────────────────────┐      │    │
│  │  │ BODY              │ │ FUEL                 │      │    │
│  │  │ 🟢 72% Recovery   │ │ 1,842/2,400 kcal    │      │    │
│  │  │ HRV 68.3  RHR 52  │ │ P:142 C:205         │      │    │
│  │  │ Sleep 7.2h        │ │ F:52  2/4 meals     │      │    │
│  │  └───────────────────┘ └──────────────────────┘      │    │
│  │   8pt gap                                            │    │
│  │  ┌───────────────────┐ ┌──────────────────────┐      │    │
│  │  │ MIND              │ │ MOVE                 │      │    │
│  │  │ 2h 15m / 3h      │ │ ✓ Done               │      │    │
│  │  │ Calc II: 6 days   │ │ 8,432 steps          │      │    │
│  │  │ 🔥 12d            │ │ 342 active cal       │      │    │
│  │  └───────────────────┘ └──────────────────────┘      │    │
│  │                                                      │    │
│  │  3/5 non-negotiables  ████████████████░░░░░░░░░      │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  Quadrant cards: systemFill bg, 8pt radius, 6pt padding     │
│  Each card: 3 lines of 10pt text, 9pt bold quadrant name    │
│  Non-neg bar: 4pt height, 2pt radius                        │
│  Deep-links: same as medium widget scheme                    │
└──────────────────────────────────────────────────────────────┘
```

### Screen 52: Lock Screen Widgets

```
CIRCULAR (Lock Screen)
┌────────────────────┐
│  50pt diameter     │
│                    │
│  ┌──────────┐      │
│  │ ╭──────╮ │      │ ← Ring rendered at widget boundary
│  │ │  78  │ │      │   3pt stroke, zone color fill
│  │ │ 18pt │ │      │   score centered
│  │ ╰──────╯ │      │   AccessoryWidgetBackground track
│  └──────────┘      │
│                    │
└────────────────────┘

RECTANGULAR (Lock Screen)
┌───────────────────────────────────────┐
│  157 x 36pt (iPhone 15)              │
│                                       │
│  ┌───────────────────────────────┐    │
│  │ Tempo: 78 · 72% rec · 7.2h   │    │ ← single line
│  │ sleep                         │    │   12pt medium
│  └───────────────────────────────┘    │   truncates from
│                                       │   right if overflow
└───────────────────────────────────────┘

INLINE (Lock Screen)
┌───────────────────────────────────────┐
│  Text only, inline with other widgets │
│                                       │
│  Tempo 78 | Rec 72%                   │ ← 12pt system
│                                       │
│  If no score: "Tempo --"              │
└───────────────────────────────────────┘

All lock screen widgets:
  Update: every 15 minutes
  Style: AccessoryWidgetBackground for automatic system styling
  Rendering: monochrome (iOS lock screen requirement)
```

---

## 9. Modals & Sheets

### Screen 53: Drill Sergeant Alert (Urgent In-App Notification)

```
┌───────────────────────────────────────┐
│                                       │
│ ┌───────────────────────────────────┐ │ ← slides down from
│ │                                   │ │   top, stays 5s
│ │  ┌──────────────────────────────┐ │ │   or until dismissed
│ │  │                              │ │ │
│ │  │  ⚠️  DRILL SERGEANT          │ │ │ ← warning icon
│ │  │                              │ │ │   bold title
│ │  │  PS5 time in 30 min.        │ │ │
│ │  │  Study still 45 min short.  │ │ │ ← 2 lines max
│ │  │  Handle it.                 │ │ │   body, white
│ │  │                              │ │ │
│ │  │  [Start Timer]   [Dismiss]  │ │ │ ← two actions
│ │  │   amber btn      text btn   │ │ │   28pt height
│ │  │                              │ │ │
│ │  └──────────────────────────────┘ │ │
│ │                                   │ │   bg: locked.red
│ │  Corner radius: 20pt              │ │   at 95% opacity
│ │  Padding: 20pt horizontal         │ │   + blur
│ │  Shadow: elevated                 │ │
│ └───────────────────────────────────┘ │   Haptic: .warning
│                                       │
│ (rest of current screen visible       │   Auto-dismiss: 5s
│  underneath, dimmed slightly)         │   Swipe up: dismiss
│                                       │
└───────────────────────────────────────┘

TRIGGER: Fires 30 min before configured evening time
  if non-negotiables are incomplete.
  Escalation levels (see ONBOARDING_AND_NOTIFICATIONS.md):
    Level 1 (gentle): 2h before
    Level 2 (firm): 1h before
    Level 3 (aggressive): 30 min before
    Level 4 (nuclear): past deadline
```

### Screen 54: Level Up Celebration

```
┌───────────────────────────────────────┐
│                                       │
│            (overlay on                │
│             current screen)           │
│                                       │
│                                       │
│                                       │
│      ┌──────────────────────┐         │
│      │                      │         │ ← modal card
│      │    ✦  ✦  ✦  ✦  ✦    │         │   centered
│      │                      │         │   #12203A bg
│      │     LEVEL UP         │         │   20pt radius
│      │                      │         │   entrance: scale
│      │   ┌──────────┐       │         │   0 -> 1.1 -> 1.0
│      │   │  LVL     │       │         │   spring 0.5s
│      │   │   15     │       │         │
│      │   │ WARRIOR  │       │         │ ← level badge
│      │   └──────────┘       │         │   scales up
│      │                      │         │   with shimmer
│      │   You are now a      │         │
│      │   WARRIOR            │         │ ← tier color text
│      │                      │         │
│      │   Unlocked:          │         │
│      │   Profile badge      │         │ ← unlock reward
│      │   showcase (pin 3)   │         │   listed
│      │                      │         │
│      │  ┌────────────────┐  │         │
│      │  │    CONTINUE    │  │         │ ← blue button
│      │  └────────────────┘  │         │   48pt
│      │                      │         │
│      └──────────────────────┘         │
│                                       │
│  Background: #0A1628 at 80% opacity   │ ← scrim overlay
│  Particles: gold/tier-color confetti  │
│  Haptic: triple .success              │
│  Sound: level-up chime (custom)       │
└───────────────────────────────────────┘
```

### Screen 55: PR Achievement Celebration

```
┌───────────────────────────────────────┐
│                                       │
│           (during active workout,     │
│            overlays on set logging)   │
│                                       │
│                                       │
│      ┌──────────────────────┐         │
│      │   ✦   ✦   ✦   ✦     │         │ ← gold particles
│      │  ✦                ✦  │         │   burst upward
│      │                      │         │
│      │   🏆 NEW PR          │         │ ← prGold (#FFD700)
│      │                      │         │   headline
│      │   BENCH PRESS        │         │ ← exercise name
│      │   87.5kg x 8         │         │   white, bold
│      │                      │         │
│      │   Est. 1RM: 110.5kg  │         │ ← secondary text
│      │   Previous: 107.5kg  │         │
│      │                      │         │
│      │   +75 XP             │         │ ← electric blue
│      │                      │         │   XP award
│      └──────────────────────┘         │
│                                       │
│  ── Auto-dismisses after 3s ──────── │
│  OR tap anywhere to dismiss           │
│                                       │
│  ANIMATION:                           │
│    Badge pops: scale 0->1.15->1.0     │
│    400ms spring, damping 0.5          │
│    Gold shimmer on exercise name      │
│    Confetti: gold particles (2s)      │
│    For ALL-TIME 1RM: full-screen      │
│    fireworks (3s, custom keyframe)    │
│                                       │
│  HAPTIC:                              │
│    Session PR: .success + .success    │
│    (double tap, 200ms delay)          │
│    All-time 1RM: .success x3 rapid   │
│    + 500ms + .success x2             │
└───────────────────────────────────────┘
```

### Screen 56: Confirmation Dialog (Destructive Action)

```
┌───────────────────────────────────────┐
│                                       │
│  (scrim overlay: #0D0D0D at 40%)      │
│                                       │
│                                       │
│                                       │
│      ┌──────────────────────┐         │ ← modal alert
│      │                      │         │   radius: 20pt
│      │   End Workout?       │         │   bg: surface.sheet
│      │                      │         │   shadow: elevated
│      │   You've completed   │         │   centered on screen
│      │   18 of 24 sets.     │         │
│      │   Unsaved progress   │         │
│      │   will be lost.      │         │ ← body text
│      │                      │         │   text.secondary
│      │   ─ ─ ─ ─ ─ ─ ─ ─   │         │
│      │                      │         │
│      │   [ Keep Training ]  │         │ ← primary action
│      │    bold, full width  │         │   48pt, primary bg
│      │    14pt radius       │         │
│      │                      │         │
│      │   [ End & Save ]     │         │ ← secondary
│      │    text only         │         │   text.secondary
│      │                      │         │
│      │   [ Discard ]        │         │ ← destructive
│      │    red text          │         │   locked.red
│      │                      │         │
│      └──────────────────────┘         │
│                                       │
│                                       │
│  ENTRANCE: Scale 0.8 -> 1.0 + fade   │
│  0.25s ease-out                       │
│  EXIT: Scale 1.0 -> 0.9 + fade out   │
│  Haptic: none (user-initiated)        │
│  Scrim tap: same as "Keep Training"   │
└───────────────────────────────────────┘

USAGE CONTEXTS:
  - End workout early (shown above)
  - Remove exercise from plan
  - Delete non-negotiable
  - Disconnect Whoop/NutriTrack
  - Remove friend
  - Leave challenge

BUTTON ORDER (top to bottom):
  1. Safe action (continue/keep) — bold, primary
  2. Moderate action (save & exit) — normal
  3. Destructive action (discard/delete) — red text, last
```

---

## Appendix: Design Token Quick Reference

```
COLORS (Light Mode):
  Primary:    #0D0D0D (Ink), #F5F2ED (Bone), #E63946 (Signal Red)
  Recovery:   #22C55E (green), #EAB308 (yellow), #DC2626 (red)
  Quadrant:   Body=zone color, Fuel=#AF52DE, Mind=#007AFF, Move=#FF9500
  Arena:      #0A1628 (bg), #2D7FF9 (XP), #FF6B2C (streak), #22C55E (win)
  Lockdown:   #E63946 (locked), #22C55E (unlocked), #3A86FF (progress)

SPACING:
  xs=4, sm=8, md=12, lg=16, xl=20, 2xl=24, 3xl=32, 4xl=40, 5xl=48
  Screen edge: 20pt (16pt on SE)
  Card padding: 16pt (12pt compact)
  Card gap: 16pt (12pt in accountability)

TYPOGRAPHY (SF Pro):
  Display: 34pt Black | Headline: 28pt Bold | Title1: 22pt Bold
  Title2: 20pt Semi | Title3: 17pt Semi | Body: 15pt Regular
  Callout: 14pt Medium | Caption1: 12pt Medium | Caption2: 11pt Regular
  Overline: 10pt Bold uppercase | Timer: 72pt SF Mono Bold

RADIUS:
  xs=3, sm=6, md=8, lg=10, xl=12, 2xl=14, 3xl=16, 4xl=20
  pill=9999 | circle=50%

COMPONENT HEIGHTS:
  Nav bar: 44pt | Tab bar: 83pt (49+34 safe)
  Primary button: 56pt | Secondary button: 44pt
  Exercise card: min 88pt | Set row: 64pt
  Recovery badge: 36pt pill | Input stepper: 44x44pt
  Rest timer circle: 200pt dia

SAFE AREAS:
  Top: 59pt (iPhone 15 Pro Dynamic Island)
  Bottom: 34pt (home indicator)
  Tab bar total: 83pt (49pt bar + 34pt safe)
  Scrollable content bottom inset: 83pt (tab bar) + 16pt breathing

TOUCH TARGET COMPLIANCE (HIG minimum 44x44pt):
  Tab bar cells: 78 x 49pt ✓
  Nav bar back button: 44 x 44pt ✓
  Nav bar trailing icons: 44 x 44pt ✓
  Primary buttons: full-width x 56pt ✓
  Secondary buttons: full-width x 44pt ✓
  Exercise card actions: 44 x 44pt ✓
  Input steppers: 44 x 44pt ✓
  Quick-add steppers: 56 x 36pt — height below 44pt ⚠️
    MITIGATION: Vertical hit area extended to 44pt via contentShape
  Filter chips: variable width x 24pt — height below 44pt ⚠️
    MITIGATION: Row spacing 12pt, vertical hit area extended to 44pt via contentShape
  RPE circles: 32pt diameter — below 44pt ⚠️
    MITIGATION: Hit area extended to 44x44pt via contentShape, 8pt gap is sufficient
```

---

## 10. Settings

### Screen 57: Settings Main

```
Component: SettingsView
Navigation: Push from ⚙ icon (present on Dashboard, Training, Accountability, Recovery, Arena)
Tab bar: Hidden (modal presentation or NavigationStack push)

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ◀ Back              Settings          │ ← Nav bar 44pt, inline
├───────────────────────────────────────┤
│                                       │
│  ┌───────────────────────────────────┐│
│  │ 👤  Nicola                        ││ ← Profile row
│  │     @nicola · Level 14 Warrior    ││    72pt height
│  │     Edit Profile               ›  ││    44x44 avatar
│  └───────────────────────────────────┘│    bg: surface.card
│                                       │    radius: 16pt
│  ←20pt                        20pt→   │    padding: 16pt
│           ↕ 24pt                      │
│                                       │
│  INTEGRATIONS                         │ ← sectionHeader 12pt
│  ←20pt                                │    text.tertiary, caps
│           ↕ 8pt                       │    letter-spacing +1
│                                       │
│  ┌───────────────────────────────────┐│
│  │ ♡  Whoop           ● Connected › ││ ← 52pt row, 16pt pad
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││    green dot 8pt
│  │ 🍴 NutriTrack      ● Connected › ││    chevron.right 12pt
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││    tertiary
│  │ ❤️ Apple Health     ● Connected › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📅 Apple Calendar   ● Connected › ││
│  └───────────────────────────────────┘│    bg: surface.card
│                                       │    radius: 16pt
│           ↕ 24pt                      │
│                                       │
│  TRAINING                             │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 🏋️ Training Split          PPL › ││ ← 52pt rows
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📅 Days per Week              4 › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ ⚽ Football Days       Wed, Sat › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ ⏱ Default Rest Timer      120s › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📊 Weight Unit              kg › ││
│  └───────────────────────────────────┘│
│                                       │
│           ↕ 24pt                      │
│                                       │
│  ACCOUNTABILITY                       │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ ✏️ Non-Negotiables         Edit › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🎮 Leisure Activity         PS5 › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🕐 Evening Start Time    7:30PM › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🔔 Drill Sergeant        Enabled  ││ ← toggle, no chevron
│  └───────────────────────────────────┘│
│                                       │
│           ↕ 24pt                      │
│                                       │
│  STUDY                                │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 📖 Daily Study Target        3h › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ ⏱ Focus Timer Mode    Pomodoro › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🔊 Ambient Sounds       Enabled  ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📅 Manage Exams                 › ││
│  └───────────────────────────────────┘│
│                                       │
│           ↕ 24pt                      │
│                                       │
│  NUTRITION                            │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 🎯 Calorie Target         2,400 › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🥩 Protein Target          180g › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🍞 Carb Target             280g › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🧈 Fat Target               80g › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🍽 Meals per Day              4 › ││
│  └───────────────────────────────────┘│
│                                       │
│           ↕ 24pt                      │
│                                       │
│  APP                                  │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 🌙 Appearance         System   › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📳 Haptics              Enabled  ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🔔 Notifications               › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📊 Export Data                  › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ ❓ Help & Support               › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📋 Privacy Policy               › ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📋 Terms of Service             › ││
│  └───────────────────────────────────┘│
│                                       │
│           ↕ 24pt                      │
│                                       │
│  ┌───────────────────────────────────┐│
│  │       Sign Out                    ││ ← text-only button
│  │       semantic.error text         ││    44pt height
│  │       centered                    ││
│  └───────────────────────────────────┘│
│                                       │
│  Tempo v1.0 (42)                      │ ← caption2, text.tertiary
│  Made with discipline.                │    centered
│                                       │
│           ↕ 34pt safe area            │
└───────────────────────────────────────┘

LAYOUT:
  Screen edge padding: 20pt (tempo.space.screen.edge)
  Section header top: 24pt, bottom: 8pt
  Row height: 52pt (exceeds 44pt minimum)
  Row padding: 16pt horizontal
  Card bg: tempo.color.surface.card
  Card radius: 16pt (tempo.radius.3xl)
  Divider: 0.5pt, tempo.color.divider.default, 16pt leading inset
  Toggle: standard SwiftUI Toggle, tint: tempo.color.primary.signal
  Chevron: 12pt, text.tertiary
  Value text: text.secondary, trailing

ON TAP (row with ›): Push to detail/edit screen
ON TAP (row with toggle): Toggle in-place
ON TAP [Sign Out]: Confirmation dialog (Screen 56 pattern)
```

### Screen 58: Notification Settings

```
Component: NotificationSettingsView
Navigation: Push from Settings > Notifications

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ◀ Settings       Notifications        │ ← Nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│  DRILL SERGEANT                       │ ← sectionHeader
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 🔔 Drill Sergeant        Enabled ││ ← master toggle
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ ⚡ Escalation Level    Aggressive ›││ ← 4 options
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🕐 First Reminder        2h before││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🔊 Sound                 Enabled ││
│  └───────────────────────────────────┘│
│                                       │
│  DAILY REMINDERS                      │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ 🌅 Morning Briefing      Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │    Time                   6:00 AM ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🍽 Meal Reminders         Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🌙 Bedtime Reminder      Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 📊 Weekly Report         Enabled ││
│  └───────────────────────────────────┘│
│                                       │
│  SOCIAL                               │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ ⚔️ Challenge Updates     Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 👤 Friend Activity       Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🏆 Leaderboard Changes   Enabled ││
│  └───────────────────────────────────┘│
│                                       │
│  WORKOUT                              │
│           ↕ 8pt                       │
│  ┌───────────────────────────────────┐│
│  │ ⏱ Rest Timer Alerts      Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │ 🏋️ Workout Reminder      Enabled ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │    Time                 Auto (AM) ││
│  └───────────────────────────────────┘│
│                                       │
│ ── 34pt safe area ──────────────────  │
└───────────────────────────────────────┘

Row height: 52pt, same card/section styling as Settings Main.
Toggles: standard SwiftUI Toggle, tint: tempo.color.primary.signal
When master "Drill Sergeant" is disabled, sub-rows dim (opacity 0.4).
```

---

## 11. Notifications

### Screen 59: Notification Center (Bell Icon)

```
Component: NotificationCenterSheet
Navigation: Sheet (medium detent) from 🔔 icon on Dashboard nav bar
Tab bar: Visible behind sheet

┌───────────────────────────────────────┐
│           ─── drag ───                │ ← sheet handle
│                                       │    4pt x 36pt, centered
│                                       │    bg.tertiary
│  NOTIFICATIONS                   ✕    │ ← sectionHeader
│                                       │    ✕ = 44x44 hit area
│  TODAY                                │ ← caption, text.tertiary
│                                       │
│  ┌───────────────────────────────────┐│
│  │ 🔴 DRILL SERGEANT    30m ago     ││ ← notification row
│  │    PS5 time in 30 min. Study     ││    min-h: 64pt
│  │    still 45 min short.           ││    16pt padding
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││    unread: blue dot 8pt
│  │ 🟢 RECOVERY          6:42 AM    ││    leading edge
│  │    Recovery at 78%. Full send    ││
│  │    today.                        ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │    WHOOP SYNC           6:42 AM  ││ ← read = no dot
│  │    All metrics synced.           ││    text.tertiary time
│  └───────────────────────────────────┘│
│                                       │
│  YESTERDAY                            │
│                                       │
│  ┌───────────────────────────────────┐│
│  │    WEEKLY REPORT        9:00 PM  ││
│  │    Your weekly report is ready.  ││
│  │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ││
│  │    CHALLENGE             3:15 PM  ││
│  │    Marco pulled ahead by 1.2h.  ││
│  └───────────────────────────────────┘│
│                                       │
│         Mark All as Read              │ ← text button, blue
│                                       │    44pt touch target
│ ── 34pt safe area ──────────────────  │
└───────────────────────────────────────┘

EMPTY STATE:
  Centered vertically in sheet:
    bell.slash icon, 48pt, text.tertiary
    "Nothing here yet." — body, text.secondary
    "Notifications will appear as you use Tempo." — caption, text.tertiary

ON TAP (notification row): Navigate to relevant screen
  Drill sergeant → Lockdown tab
  Recovery → Recovery tab
  Weekly report → Weekly Report view
  Challenge → Challenge detail
ON SWIPE LEFT: Delete notification
```

---

## 12. Error & Offline States

### Screen 60: Full Offline State

```
Component: OfflineView
Trigger: No network connectivity detected (NWPathMonitor)
Presentation: Banner at top of any screen, or full-screen if critical

VARIANT A — Banner (non-blocking)
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │ 📡 You're offline. Some data     │ │ ← 44pt height
│ │    may be outdated.               │ │    bg: semantic.warning
│ └───────────────────────────────────┘ │    at 15% opacity
│                                       │    text: text.primary
│ (normal screen content continues)    │    icon: 16pt
│                                       │    padding: 12pt horiz
│ ...                                   │    auto-dismiss when
│                                       │    connectivity returns
└───────────────────────────────────────┘

VARIANT B — Full Screen (when action requires network)
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ ◀ Back               [Screen Title]   │ ← Nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│                                       │
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ 📡   │                 │ ← 60pt SF Symbol
│              └──────┘                 │    wifi.slash
│                                       │    text.tertiary
│        No Connection                  │ ← title3, text.primary
│                                       │    centered
│   Check your Wi-Fi or cellular        │ ← body, text.secondary
│   connection and try again.           │    centered, max 280pt
│                                       │
│   ┌───────────────────────────────┐   │
│   │          Retry                │   │ ← primary button, 56pt
│   └───────────────────────────────┘   │    full-width - 40pt
│                                       │    radius: tempo.radius.2xl
│                                       │
│                                       │
│                                       │
│ ── Tab Bar ─────────────────────────  │
└───────────────────────────────────────┘

LAYOUT:
  Icon: centered horizontally, vertically offset -80pt from center
  Title: 12pt below icon
  Subtitle: 8pt below title, max-width 280pt
  Button: 24pt below subtitle
  All text centered
```

### Screen 61: Whoop Disconnected State (Recovery Tab)

```
Component: WhoopDisconnectedView
Trigger: Whoop OAuth token expired or revoked
Presentation: Replaces Recovery tab main content

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│          Recovery               ⚙     │ ← Nav bar, inline
├───────────────────────────────────────┤
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ ♡    │                 │ ← 60pt SF Symbol
│              └──────┘                 │    heart.slash
│                                       │    text.tertiary
│       Whoop Disconnected              │ ← title3, text.primary
│                                       │
│   Tempo needs Whoop to track your     │ ← body, text.secondary
│   recovery, sleep, and strain.        │    centered, max 280pt
│                                       │
│   ┌───────────────────────────────┐   │
│   │     Reconnect Whoop           │   │ ← primary button, 56pt
│   └───────────────────────────────┘   │
│                                       │
│   ┌───────────────────────────────┐   │
│   │     Use HealthKit Instead     │   │ ← secondary button, 44pt
│   └───────────────────────────────┘   │    text-only, text.secondary
│                                       │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ │ Home  Train  Lock  Recov Arena    │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP [Reconnect Whoop]: Triggers OAuth flow
ON TAP [Use HealthKit Instead]: Navigate to HealthKit permissions
```

---

## 13. Missing Module States

### Screen 62: Training — Loading State

```
Component: TrainingLoadingView
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ < Training                   ⚙  📅   │ ← Nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│  ░░░░░░░░░░░░░                        │ ← shimmer: day label
│  ░░░░░░░░░░░░░░░░░░                   │    80pt x 14pt
│                                       │    140pt x 34pt
│ ┌───────────────────────────────────┐ │ ← Recovery Badge
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░     │ │    shimmer bar
│ │ ░░░░░░░░░░░░░░░                  │ │    52pt height
│ └───────────────────────────────────┘ │
│                                       │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░          │ ← shimmer: summary
│                                       │
│ ┌───────────────────────────────────┐ │ ← Exercise Card skeletons
│ │ ░░░  ░░░░░░░░░░░░░░░  ░░░░░░    │ │    4 cards
│ │      ░░░░░░░░░░░░░░░░░          │ │    88pt each
│ │      ░░░░░░░░░░░░░░░            │ │    8pt gap
│ └───────────────────────────────────┘ │
│                 ↕ 8pt                 │
│ ┌───────────────────────────────────┐ │
│ │ ░░░  ░░░░░░░░░░░░░░░  ░░░░░░    │ │
│ │      ░░░░░░░░░░░░░░░░░          │ │
│ │      ░░░░░░░░░░░░░░░            │ │
│ └───────────────────────────────────┘ │
│                 ↕ 8pt                 │
│ ┌───────────────────────────────────┐ │
│ │ ░░░  ░░░░░░░░░░░░░░░  ░░░░░░    │ │
│ │      ░░░░░░░░░░░░░░░░░          │ │
│ └───────────────────────────────────┘ │
│                 ↕ 8pt                 │
│ ┌───────────────────────────────────┐ │
│ │ ░░░  ░░░░░░░░░░░░░░░  ░░░░░░    │ │
│ │      ░░░░░░░░░░░░░░░░░          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

SHIMMER: Same diagonal gradient as Dashboard loading (Screen 4).
```

### Screen 63: Training — Empty State (No Workout Plan)

```
Component: TrainingEmptyView
Trigger: User has no training plan configured

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ < Training                   ⚙  📅   │ ← Nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│  Monday, March 24                     │
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ 🏋️   │                 │ ← 60pt SF Symbol
│              └──────┘                 │    dumbbell
│                                       │    text.tertiary
│     Nothing here yet. That's on you.  │ ← body, text.secondary
│                                       │    centered
│  ┌───────────────────────────────┐    │
│  │    Generate My First Plan     │    │ ← primary button, 56pt
│  └───────────────────────────────┘    │    full-width - 40pt
│                                       │
│  ┌───────────────────────────────┐    │
│  │    Start a Quick Workout      │    │ ← secondary, 44pt
│  └───────────────────────────────┘    │    text-only
│                                       │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP [Generate My First Plan]: Triggers AI plan generation flow
ON TAP [Start a Quick Workout]: Opens exercise library with quick-start mode
```

### Screen 64: Training — Error State

```
Component: TrainingErrorView
Trigger: Failed to load workout plan from server

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│ < Training                   ⚙  📅   │ ← Nav bar 44pt
├───────────────────────────────────────┤
│                                       │
│  Monday, March 24                     │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Recovery Badge
│ │ 🟢 78% Recovery · Full Volume    │ │    (local data, shows
│ └───────────────────────────────────┘ │    even on error)
│                                       │
│              ┌──────┐                 │
│              │  ⚠️  │                 │ ← 48pt SF Symbol
│              └──────┘                 │    exclamationmark.triangle
│                                       │    semantic.error
│     Couldn't load your workout.       │ ← body, text.secondary
│     Check your connection.            │    centered
│                                       │
│  ┌───────────────────────────────┐    │
│  │          Retry                │    │ ← primary button, 56pt
│  └───────────────────────────────┘    │
│                                       │
│  ┌───────────────────────────────┐    │
│  │   Start Without a Plan       │    │ ← secondary, 44pt
│  └───────────────────────────────┘    │    text-only
│                                       │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 65: Accountability — Loading State

```
Component: LockdownLoadingView
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│            LOCKDOWN            ⚙      │
│                                       │
│  ░░░░░░░░░░░░░                        │ ← shimmer: date
│                                       │
│ ┌───────────────────────────────────┐ │ ← Status Banner skeleton
│ │ ┌──────┐                          │ │    shimmer ring 64pt
│ │ │ ░░░░ │  ░░░░░░░░░░░░░░░       │ │    shimmer text bars
│ │ │ ░░░░ │  ░░░░░░░░░░░░░░░░░░░   │ │
│ │ └──────┘                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Task card skeletons
│ │ ░░  ░░░░░░░░░░░░       ░░░░░░   │ │    4 cards, 72pt each
│ │     ░░░░░░░░░░░░░░░░░░░░░░░░    │ │    12pt gap
│ │     ░░░░░░░░░░░░░░░░░           │ │
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ ░░  ░░░░░░░░░░░░       ░░░░░░   │ │
│ │     ░░░░░░░░░░░░░░░░░░░░░░░░    │ │
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ ░░  ░░░░░░░░░░░░       ░░░░░░   │ │
│ │     ░░░░░░░░░░░░░░░░░░░░░░░░    │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

### Screen 66: Accountability — Empty State (No Non-Negotiables)

```
Component: LockdownEmptyView
Trigger: User has not configured any non-negotiables

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│            LOCKDOWN            ⚙      │
│                                       │
│  Monday, March 24                     │
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ 🔒   │                 │ ← 60pt SF Symbol
│              └──────┘                 │    lock.open
│                                       │    text.tertiary
│    Set your daily non-negotiables     │ ← body, text.secondary
│    and start earning your evenings.   │    centered, max 280pt
│                                       │
│  ┌───────────────────────────────┐    │
│  │   Set Up Non-Negotiables      │    │ ← primary button, 56pt
│  └───────────────────────────────┘    │    full-width - 40pt
│                                       │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP: Navigates to Non-Negotiable Setup (Screen 27)
```

### Screen 67: Recovery — Loading State

```
Component: RecoveryLoadingView
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│          Recovery               ⚙     │
├───────────────────────────────────────┤
│                                       │
│         ┌──────────────────┐          │ ← RecoveryRing skeleton
│         │                  │          │    200pt diameter
│         │    ╭────────╮    │          │    14pt stroke
│         │   │  ╌╌╌╌╌  │   │          │    pulsing track
│         │   │   --     │   │          │    opacity 0.3-1.0
│         │   │          │   │          │    1.5s sinusoidal
│         │    ╰────────╯    │          │
│         │                  │          │
│         └──────────────────┘          │
│       Pulling your numbers...         │ ← text.tertiary, caption
│                                       │
│ ┌─────────┐┌─────────┐┌────────┐┌───┐│ ← MetricTile shimmer
│ │ ░░░░░░  ││ ░░░░░░  ││ ░░░░░ ││░░░││    88pt height each
│ │ ░░░░    ││ ░░░░    ││ ░░░░  ││░░ ││
│ │ ░░░░░░░ ││ ░░░░░░░ ││ ░░░░░ ││░░░││
│ └─────────┘└─────────┘└────────┘└───┘│
│                                       │
│ ── Today's Prescription ──────────── │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Prescription skeletons
│ │ ░░  ░░░░░░░░░░░░░░░░░           │ │    3 cards
│ │     ░░░░░░░░░░░░░░░░░░░░░░░     │ │    each ~80pt
│ │     ░░░░░░░░░░░░░░░░░░░         │ │    12pt gap
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ ░░  ░░░░░░░░░░░░░░░░░           │ │
│ │     ░░░░░░░░░░░░░░░░░░░░░░░     │ │
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ ░░  ░░░░░░░░░░░░░░░░░           │ │
│ │     ░░░░░░░░░░░░░░░░░░░░░░░     │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

SHIMMER: Same as Dashboard loading (Screen 4).
Loading text: "Pulling your numbers..." — per UX_COPY_BIBLE militaristic style.
```

### Screen 68: Recovery — Yellow Zone

```
Component: RecoveryTodayView (yellow variant)
Trigger: Whoop recovery score 34-66%

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│          Recovery               ⚙     │
├───────────────────────────────────────┤
│                                       │
│         ┌──────────────────┐          │ ← RecoveryRing
│         │                  │          │    200pt diameter
│         │    ╭────────╮    │          │    14pt stroke
│         │   │          │   │          │    YELLOW fill
│         │   │    52    │   │          │    recovery.yellow
│         │   │ RECOVERY │   │          │    (#EAB308)
│         │   │          │   │          │
│         │    ╰────────╯    │          │    Glow: 120pt radius
│         │                  │          │    recovery.yellow.bg
│         └──────────────────┘          │    15% opacity
│                                       │
│       ↓ 5% below your average         │ ← yellow arrow
│       Monday, March 24                │
│                                       │
│ ┌─────────┐┌─────────┐┌────────┐┌───┐│ ← MetricTiles
│ │♡ HRV    ││♡ RHR    ││O₂ SpO2 ││🌡 ││    same layout as
│ │ 55 ms   ││ 58 bpm  ││ 97%    ││36.9││    green zone
│ │ ↓ 5%    ││ ↑ 8%    ││— stable││—  ││    (Screen 30)
│ │ ▁▃▅▇▅▃▁ ││ ▃▅▇▅▃▅▇ ││ ▅▅▅▅▅▅││▅▅▅││
│ └─────────┘└─────────┘└────────┘└───┘│
│                                       │
│ ── Today's Prescription ──────────── │
│   ● yellow dot, 8pt                  │
│                                       │
│ ┌───────────────────────────────────┐ │ ← PrescriptionCard
│ │ 🏋️  Training                      │ │    MODERATE tone
│ │ ─────────────────────────────────── │
│ │ Dial it back. Moderate weights,   │ │
│ │ skip the PRs. Accessory work OK.  │ │
│ │ [Why this recommendation?]     ›  │ │ ← yellow text
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ 🍽  Nutrition                      │ │
│ │ ─────────────────────────────────── │
│ │ Stick to your macros. Prioritize  │ │
│ │ whole foods. Extra water today.   │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│            ↕ 12pt                     │
│ ┌───────────────────────────────────┐ │
│ │ 🛏  Bedtime                        │ │
│ │ ─────────────────────────────────── │
│ │ Target: 10:00 PM                  │ │
│ │ Sleep debt: 3.2h. Aim for 8h+.   │ │
│ │ [Why?]                         ›  │ │
│ └───────────────────────────────────┘ │
│                                       │
│ (same caffeine + hydration cards     │
│  as green zone, Screens 30)         │
│                                       │
│ ── Quick Insights ───────────────── ─ │
│ (same teaser cards as Screen 30)     │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

VISUAL TONE: Slightly muted. Yellow glow around ring.
Ring stroke color: recovery.yellow (#EAB308)
Prescription [Why?] links: recovery.yellow text
Section dot: yellow, 8pt
```

### Screen 69: Arena — Loading State

```
Component: ArenaLoadingView
┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│  ARENA                      ⚙  👤    │ ← real header (local)
│                                       │
│ ┌───────────────────────────────────┐ │ ← Hero Card skeleton
│ │ ┌──────┐                          │ │    88pt, #12203A
│ │ │ ░░░  │  ░░░░░░░░░░░░░░        │ │    shimmer
│ │ │ ░░░  │  ░░░░░░░░░░░░░░░░░░    │ │
│ │ └──────┘                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Today's XP skeleton
│ │ ░░░░░░░░░░░░░                     │ │    180pt, #12203A
│ │ ┌──────────┐   ░░░░░░░░░░░      │ │
│ │ │  ░░░░░   │   ░░░░░░░░░        │ │
│ │ └──────────┘   ░░░░░░░░░░░░     │ │
│ │                                   │ │
│ │ ░░  ░░░░░░░░░░░░       ░░░░     │ │
│ │ ░░  ░░░░░░░░░░░░       ░░░░     │ │
│ │ ░░  ░░░░░░░░░░░░       ░░░░     │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Leaderboard skeleton
│ │ ░░░░░░░░░░░░░░░░░░░░░           │ │    140pt, #12203A
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░     │ │
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░     │ │
│ │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░     │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

SHIMMER: Same diagonal gradient, adapted to Arena dark bg (#0A1628).
  Shimmer highlight: #1E3A5F at 40% opacity.
```

### Screen 70: Arena — Empty State (No Friends)

```
Component: ArenaEmptyView
Trigger: User has no friends added, no XP history

┌───────────────────────────────────────┐
│ ── 59pt safe area ──────────────────  │
│                                       │
│  ARENA                      ⚙  👤    │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Hero Card (real)
│ │ ┌──────┐                          │ │    shows Level 1
│ │ │ LVL  │  RECRUIT          🔥 0   │ │    0 XP
│ │ │   1  │  ░░░░░░░░░░░░░░░  0%    │ │
│ │ │      │  0 / 100 XP              │ │
│ │ └──────┘                          │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Today's XP (real)
│ │ TODAY'S XP                        │ │    shows 0 with
│ │ ┌──────────┐   Earned: 0 XP      │ │    potential preview
│ │ │    0     │   Complete tasks to  │ │
│ │ │   XP     │   earn your first XP │ │
│ │ └──────────┘                      │ │
│ └───────────────────────────────────┘ │
│                                       │
│ ┌───────────────────────────────────┐ │ ← Empty Leaderboard
│ │ 🏆 WEEKLY LEADERBOARD             │ │
│ │                                   │ │
│ │       ┌──────┐                    │ │
│ │       │ 👤+  │                    │ │ ← 48pt icon
│ │       └──────┘                    │ │
│ │    Add friends to compete         │ │ ← body, white 70%
│ │    on the leaderboard.            │ │    centered
│ │                                   │ │
│ │  ┌────────────────────────────┐   │ │
│ │  │  👤+ Add Friends           │   │ │ ← outlined button
│ │  └────────────────────────────┘   │ │    #2D7FF9 border
│ └───────────────────────────────────┘ │    44pt
│                                       │
│ ── 34pt safe area ──────────────────  │
│ ┌───────────────────────────────────┐ │
│ │  🏠    💪    🔒    ❤️    🏆       │ │ ← Tab Bar (83pt)
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘

ON TAP [Add Friends]: Opens share sheet / friend invite flow
```

### Screen 71: Exercise Library — Search Results

```
Component: ExerciseLibrarySearchResults
Trigger: User types in search bar on Screen 19

STATE A — Results Found
┌───────────────────────────────────────┐
│ ◀ Back          Exercise Library      │
├───────────────────────────────────────┤
│ ┌───────────────────────────────────┐ │
│ │ 🔍  "bench"               ✕      │ │ ← search bar active
│ └───────────────────────────────────┘ │    ✕ = clear, 44x44 hit
│                                       │
│  3 results for "bench"               │ ← caption, text.tertiary
│                                       │
│ ┌───────────────────────────────────┐ │
│ │ BENCH PRESS              Chest    │ │ ← 64pt rows
│ │ Barbell · Compound                │ │    "bench" highlighted
│ │ ───────────────────────────────── │ │    in bold/amber
│ │ INCLINE BENCH PRESS      Chest    │ │
│ │ Barbell · Compound                │ │
│ │ ───────────────────────────────── │ │
│ │ CLOSE-GRIP BENCH PRESS  Triceps  │ │
│ │ Barbell · Compound                │ │
│ └───────────────────────────────────┘ │
│                                       │
└───────────────────────────────────────┘

STATE B — No Results
┌───────────────────────────────────────┐
│ ◀ Back          Exercise Library      │
├───────────────────────────────────────┤
│ ┌───────────────────────────────────┐ │
│ │ 🔍  "xyzabc"              ✕      │ │
│ └───────────────────────────────────┘ │
│                                       │
│                                       │
│              ┌──────┐                 │
│              │ 🔍   │                 │ ← 48pt SF Symbol
│              └──────┘                 │    magnifyingglass
│                                       │    text.tertiary
│     No exercises found.               │ ← body, text.secondary
│     Try a different search term.      │    centered
│                                       │
│                                       │
└───────────────────────────────────────┘

Search is debounced at 300ms. Results filter in real-time.
Match highlighting: matched substring in accent.amber.
```

---

## Appendix B: Consistency Checklist

```
TAB BAR PRESENCE:
  Dashboard (Screen 3, 4, 5, 5B): ✓ shown
  Training (Screen 11): ✓ shown (via tab bar bottom)
  Accountability (Screen 22, 23, 29): ✓ shown
  Recovery (Screen 30, 31): ✓ shown (via bottom padding note)
  Arena (Screen 36): ✓ shown
  Expanded views (6-9, 10): ✗ hidden (push navigation, correct)
  Active workout (14-17): ✗ hidden (fullScreenCover, correct)
  Focus timer (24-26): ✗ hidden (fullScreenCover, correct)
  Onboarding (44-48): ✗ hidden (pre-auth, correct)
  Settings (57-58): ✗ hidden (push navigation, correct)

NAVIGATION PATTERN CONSISTENCY:
  Tab switch: Root NavigationStack swap, spring 200ms
  Push: Standard iOS push (right-to-left), swipe-back enabled
  Sheet: .sheet modifier, medium/large detent as noted
  FullScreenCover: Active workout, Focus timer, Level up
  matchedGeometryEffect: Dashboard quadrant -> expanded view

CARD STYLE CONSISTENCY:
  Standard card: surface.card bg, radius 16pt (tempo.radius.3xl),
    padding 16pt (tempo.space.card.padding), shadow: tempo.shadow.card
  Arena card: #12203A bg, 1pt border #1E3A5F, radius 16pt, padding 16pt
  Onboarding card: 10% white bg, 1pt 15% white border, radius 16pt
  All cards: consistent across modules ✓

SCORE RING CONSISTENCY:
  Dashboard (Screen 3): 100pt dia, 8pt stroke, gap at 12 o'clock
  Weekly Report (Screen 10): 100pt dia, same style
  Recovery main (Screen 30): 200pt dia, 14pt stroke, zone-colored glow
  Body expanded (Screen 6): 120pt dia, 10pt stroke
  Fuel expanded (Screen 7): 120pt dia, 10pt stroke
  Widget small (Screen 49): 52pt dia, 4pt stroke
  Widget medium (Screen 50): 48pt dia, 4pt stroke
  Widget large (Screen 51): 56pt dia, 5pt stroke
  All rings: gap at 12 o'clock, clockwise fill ✓

BUTTON SIZE COMPLIANCE (44pt minimum touch target):
  Primary CTA: 56pt height ✓
  Secondary CTA: 44pt height ✓
  Text-only buttons: 44pt height ✓
  Navigation back: 44x44pt ✓
  Tab bar cells: 78x49pt ✓
  Filter chips: 24pt height ⚠️ (contentShape extends to 44pt)
  RPE circles: 32pt ⚠️ (contentShape extends to 44pt)
```
