# MODULE_DASHBOARD — "LifeOS" Home Screen

> **Module**: Dashboard (LifeOS)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 2.0 Spec — Production-Grade
> **Last Updated**: 2026-03-24
> **Audience**: iOS developers — this document is the single source of truth. Build from it without asking questions.

---

## Table of Contents

1. [Design System Constants](#1-design-system-constants)
2. [Data Layer Contract](#2-data-layer-contract)
3. [Main Dashboard View](#3-main-dashboard-view)
4. [Expanded Quadrant Views](#4-expanded-quadrant-views)
5. [Weekly Report View](#5-weekly-report-view)
6. [Pattern / Correlation View](#6-pattern--correlation-view)
7. [Daily Timeline View](#7-daily-timeline-view)
8. [Quick Actions](#8-quick-actions)
9. [Widget Specifications](#9-widget-specifications)
10. [AI Insights Engine](#10-ai-insights-engine)
11. [Drill Sergeant Voice System](#11-drill-sergeant-voice-system)
12. [First-Time User Experience](#12-first-time-user-experience)
13. [Offline Mode & Stale Data](#13-offline-mode--stale-data)
14. [Notification Deep-Links](#14-notification-deep-links)
15. [Accessibility](#15-accessibility)
16. [Performance Budget](#16-performance-budget)
17. [Error Handling Matrix](#17-error-handling-matrix)

---

## 1. Design System Constants

### 1.1 Color Palette

| Token | Hex (Light) | Hex (Dark) | Usage |
|-------|-------------|------------|-------|
| `tempo.color.bg.primary` | `#F5F2ED` | `#0D0D0D` | Main background |
| `tempo.color.surface.card` | `#FFFFFF` | `#1C1C1E` | Card surfaces |
| `tempo.color.surface.card.pressed` | `#F0F0F0` | `#252525` | Card tap highlight |
| `tempo.color.text.primary` | `#0D0D0D` | `#F5F2ED` | Headlines, large numbers |
| `tempo.color.text.secondary` | `#4B5563` | `#A1A1AA` | Labels, captions |
| `tempo.color.text.tertiary` | `#6B7280` | `#8E8E93` | Placeholder, disabled |
| `tempo.color.primary.signal` | `#E63946` | `#FF4D5A` | Primary accent (drill-sergeant red) |
| `tempo.color.recovery.green` | `#22C55E` | `#4ADE80` | Recovery green, on-track |
| `tempo.color.recovery.yellow` | `#EAB308` | `#FACC15` | Caution, moderate recovery |
| `tempo.color.recovery.red` | `#DC2626` | `#F87171` | Alert, low recovery, behind target |
| `tempo.color.accent.electric` | `#3B82F6` | `#60A5FA` | Mind quadrant accent |
| `tempo.color.accent.amber` | `#F59E0B` | `#FBBF24` | Move quadrant accent |
| `tempo.color.accent.violet` | `#8B5CF6` | `#A78BFA` | Fuel quadrant accent |
| `tempo.color.recovery.green` | `#22C55E` | `#4ADE80` | Body quadrant — recovery >= 67% |
| `tempo.color.recovery.yellow` | `#EAB308` | `#FACC15` | Body quadrant — recovery 34-66% |
| `tempo.color.recovery.red` | `#DC2626` | `#F87171` | Body quadrant — recovery < 34% |
| `tempo.color.ring.track` | `#E5E5EA` | `#2C2C2E` | Progress ring background track |
| `tempo.color.divider.default` | `#E5E7EB` | `#2C2C2E` | Hairline dividers |
| `tempo.color.state.locked` | `#8E8E93` | `#636366` | Non-negotiable locked state |
| `tempo.color.semantic.warning` | `#EAB308` | `#FACC15` | Stale data indicator (timestamp, dot) |
| `tempo.color.banner.offline.bg` | `#FFF3CD` | `#332B00` | Offline banner background |
| `tempo.color.banner.offline.text` | `#856404` | `#EAB308` | Offline banner text |

### 1.2 Typography

All fonts use **SF Pro** (system default). Weights reference the SF Pro weight scale.

| Token | Size | Weight | Tracking | Line Height | Usage |
|-------|------|--------|----------|-------------|-------|
| `tempo.display` | 34pt | Black (900) | -0.4pt | 40pt | Daily score number |
| `tempo.headline` | 28pt | Bold (700) | -0.3pt | 34pt | Screen titles |
| `tempo.title1` | 22pt | Bold (700) | -0.2pt | 28pt | Quadrant primary value |
| `tempo.title2` | 20pt | Semibold (600) | 0pt | 26pt | Section headers |
| `tempo.title3` | 17pt | Semibold (600) | 0pt | 22pt | Expanded view headers |
| `tempo.body` | 15pt | Regular (400) | 0pt | 20pt | Body text, descriptions |
| `tempo.callout` | 14pt | Medium (500) | 0pt | 19pt | Card labels |
| `tempo.caption1` | 12pt | Medium (500) | 0pt | 16pt | Quadrant secondary values |
| `tempo.caption2` | 11pt | Regular (400) | 0.2pt | 14pt | Timestamps, units |
| `tempo.overline` | 10pt | Bold (700) | 1.5pt | 12pt | Quadrant category labels (uppercased) |

### 1.3 Spacing & Layout

| Token | Value | Usage |
|-------|-------|-------|
| `tempo.space.xs` | 4pt | Inline element gaps |
| `tempo.space.sm` | 8pt | Tight padding inside cards |
| `tempo.space.md` | 12pt | Standard internal padding |
| `tempo.space.card.gap` | 12pt | Card-to-card vertical gaps |
| `tempo.space.lg` | 16pt | Card internal padding, section spacing |
| `tempo.space.screen.edge` | 20pt | Screen edge insets |
| `tempo.space.2xl` | 24pt | Major section dividers |
| `tempo.space.3xl` | 32pt | Top-of-screen safe area padding |
| `tempo.radius.card` | 16pt | Card corner radius |
| `tempo.radius.inner` | 10pt | Nested element radius |
| `tempo.radius.pill` | 999pt | Pill-shaped badges |
| `tempo.radius.ring` | Full circle | Score rings |
| `tempo.shadow.card` | `0 2 8 rgba(0,0,0,0.06)` | Light mode card shadow |
| `tempo.shadow.card.dark` | `0 2 8 rgba(0,0,0,0.3)` | Dark mode card shadow |
| `tempo.shadow.elevated` | `0 8 24 rgba(0,0,0,0.12)` | Expanded views, modals |

### 1.4 Pixel-Perfect Sizing Reference

| Device | Screen Width | Screen Height | Safe Area Top | Safe Area Bottom | Quadrant Width | Quadrant Min Height | Usable Viewport Height |
|--------|-------------|---------------|---------------|------------------|----------------|---------------------|----------------------|
| iPhone SE (3rd) | 375pt | 667pt | 47pt | 34pt | 159.5pt | 160pt | 586pt |
| iPhone 15 | 393pt | 852pt | 59pt | 34pt | 168.5pt | 160pt | 759pt |
| iPhone 15 Pro | 393pt | 852pt | 59pt | 34pt | 168.5pt | 160pt | 759pt |
| iPhone 15 Plus | 430pt | 932pt | 59pt | 34pt | 187pt | 160pt | 839pt |
| iPhone 15 Pro Max | 430pt | 932pt | 59pt | 34pt | 187pt | 160pt | 839pt |
| iPhone 16 Pro | 402pt | 874pt | 62pt | 34pt | 173pt | 160pt | 778pt |
| iPhone 16 Pro Max | 440pt | 956pt | 62pt | 34pt | 192pt | 160pt | 860pt |

**Quadrant width formula**: `(screenWidth - (2 * tempo.space.xl) - tempo.space.lg) / 2`
- iPhone SE: `(375 - 40 - 16) / 2 = 159.5pt` (round to 159.5pt, LazyVGrid handles sub-pixel)
- iPhone 15: `(393 - 40 - 16) / 2 = 168.5pt`
- iPhone 15 Pro Max: `(430 - 40 - 16) / 2 = 187pt`
- iPhone 16 Pro Max: `(440 - 40 - 16) / 2 = 192pt`

**Quadrant content area** (internal): `quadrantWidth - (2 * 14pt internal padding) = quadrantWidth - 28pt`
- iPhone SE: 131.5pt usable content width
- iPhone 15: 140.5pt
- iPhone 15 Pro Max: 159pt
- iPhone 16 Pro Max: 164pt

> **Note:** Quadrant width formula uses `tempo.space.screen.edge` (20pt) for margins and `tempo.space.lg` (16pt) for inter-quadrant gap.

**Quadrant height behavior**:
- Minimum height: 160pt (enforced via `.frame(minHeight: 160)`)
- Maximum height: unbounded — content-driven
- Row alignment: each row of the 2x2 grid aligns to the taller card in that row. The `LazyVGrid` handles this naturally. If the BODY card requires 200pt (due to strain bar + full data) and FUEL requires 220pt (due to macro bars), both cards in row 1 become 220pt. The MIND/MOVE row calculates independently.
- **Typical heights by state**:
  - Full data, all fields populated: 195-225pt per card
  - Disconnected state (connect prompt): 180pt
  - Loading shimmer state: 180pt (fixed during shimmer to avoid layout jumps)
  - Partial data (some fields nil): same as full data — nil fields show `"--"` but occupy the same space

**Total dashboard content height estimate** (all data connected, typical):
- Header: ~56pt
- Score section: ~140pt (ring 100pt + labels + padding)
- Quadrant grid: ~460pt (two rows of ~210pt + 16pt gap)
- Non-negotiables: ~110pt
- Insights banner: ~80pt (when present)
- Bottom breathing room: 50pt
- **Total**: ~896pt

This means:
- iPhone SE (586pt viewport): scrolls ~310pt. Significant scroll.
- iPhone 15 (759pt viewport): scrolls ~137pt. Light scroll.
- iPhone 15 Pro Max (839pt viewport): scrolls ~57pt. Barely scrolls with 5 non-negotiables + insight.

### 1.5 Animation Constants

| Token | Duration | Curve | Usage |
|-------|----------|-------|-------|
| `tempo.motion.small` | 200ms | easeOut | Button taps, highlights |
| `tempo.motion.medium` | 300ms | spring(response: 0.3, dampingFraction: 0.8) | Card transitions |
| `tempo.motion.data` | 800ms | spring(response: 0.8, dampingFraction: 0.7) | Score ring fill on load |
| `tempo.motion.large` | 500ms | spring(response: 0.4, dampingFraction: 0.82) | Quadrant expansion |
| `tempo.motion.stagger.card` | 60ms | — | Delay between staggered card appearances |
| `tempo.motion.large` | 500ms | easeInOut | Pull-to-refresh completion |
| `tempo.motion.data` | 800ms | easeOut | Numeric counter roll-up on value change |
| `tempo.motion.small` | 200ms | easeInOut | Stale data indicator appearance |
| `tempo.motion.shimmer` | 1500ms | linear | Skeleton shimmer sweep, repeating |
| `tempo.motion.celebration` | 1000ms | easeOut | Non-negotiable completion burst |
| `tempo.motion.medium` | 300ms | easeIn | Insight banner swipe dismiss |
| `tempo.motion.medium` | 300ms | spring(response: 0.3, dampingFraction: 0.8) | Value text change transition |

---

## 2. Data Layer Contract

### 2.1 Data Sources & Refresh Strategy

| Source | Refresh Trigger | Cache TTL | Background Refresh | Staleness Threshold | Critical Staleness |
|--------|----------------|-----------|-------------------|--------------------|--------------------|
| Whoop API | Pull-to-refresh, app foreground, every 15 min background | 5 min | Yes (BGAppRefreshTask) | > 30 min = stale indicator | > 2 hr = yellow timestamp |
| HealthKit | Pull-to-refresh, app foreground, HKObserverQuery | Real-time via observer | Yes (HKObserverQuery) | > 10 min for HR, never for steps | > 30 min for HR |
| NutriTrack API | Pull-to-refresh, app foreground, every 10 min background | 3 min | Yes | > 20 min = stale indicator | > 1 hr = yellow timestamp |
| Local DB | Immediate (SwiftData) | N/A | N/A | Never stale | N/A |

**Staleness visual treatment**: When a data source exceeds its staleness threshold, the "Last sync" timestamp for that quadrant changes color from `tempo.text.tertiary` to `tempo.stale` (yellow). A small 4pt yellow dot appears next to the quadrant's category label, right of the icon. At critical staleness, the entire timestamp pulses (opacity 0.5 to 1.0, 2s cycle).

### 2.2 Data Models

```
DashboardState {
    date: Date                          // Today's date
    dailyScore: Int?                    // 0-100, nil if not yet calculable
    lastRefresh: Date

    body: BodyQuadrantData
    fuel: FuelQuadrantData
    mind: MindQuadrantData
    move: MoveQuadrantData

    nonNegotiables: [NonNegotiable]
    connectionStatus: ConnectionStatus
    isOffline: Bool                     // NWPathMonitor status
    dataAge: DataAgeStatus              // per-source staleness tracking
}

BodyQuadrantData {
    recovery_score: Double?             // 0-100 (maps from DailySnapshot.recoveryScore)
    hrv_rmssd: Double?                  // milliseconds, 1 decimal (maps from DailySnapshot.hrv)
    resting_heart_rate: Double?         // bpm (maps from DailySnapshot.rhr — Double, not Int)
    sleep_hours: Double?                // hours, 1 decimal (maps from DailySnapshot.sleepHours)
    sleep_performance_percentage: Double? // 0-100 (maps from DailySnapshot.sleepScore)
    strain: Double?                     // 0.0-21.0, 1 decimal (maps from DailySnapshot.strain)
    spo2_percentage: Double?            // percentage (maps from DailySnapshot.spo2)
    source: .whoop | .disconnected      // computed from WhoopService state
    lastSync: Date?                     // computed from WhoopService.lastSyncDate
    isStale: Bool                       // computed: lastSync > staleness threshold
}
// See DATA_MODELS_IOS.md Section 4.2 for the canonical view model definition.

FuelQuadrantData {
    calories_consumed: Int?             // kcal
    calories_target: Int?               // kcal
    protein_g: Int?                     // grams
    protein_target_g: Int?              // grams
    carbs_g: Int?                       // grams
    carbs_target_g: Int?                // grams
    fat_g: Int?                         // grams
    fat_target_g: Int?                  // grams
    meals_logged: Int?                  // count
    meals_planned: Int?                 // count
    meal_statuses: [MealStatus]         // array of { name, status: .logged | .planned | .skipped }
    source: .nutritrack | .disconnected
    lastSync: Date?
    isStale: Bool
}

MindQuadrantData {
    study_minutes_today: Int            // minutes
    study_target_minutes: Int           // minutes
    exams: [Exam]                       // sorted by date ascending
    current_streak_days: Int            // consecutive days meeting target
    source: .local
}

Exam {
    name: String                        // e.g. "Calculus II"
    date: Date
    daysUntil: Int                      // computed
}

MoveQuadrantData {
    workout_status: .completed | .planned | .restDay | .none
    workout_name: String?               // e.g. "Upper Body Push"
    workout_duration_minutes: Int?
    steps: Int?                         // from HealthKit
    steps_target: Int                   // default 10000
    active_calories: Int?               // from HealthKit
    heart_rate_current: Int?            // latest sample
    source: .healthkit | .disconnected
    lastSync: Date?
    isStale: Bool
}

NonNegotiable {
    id: UUID
    title: String                       // e.g. "Morning workout"
    isCompleted: Bool
    category: .body | .fuel | .mind | .move
}

ConnectionStatus {
    whoop: .connected | .disconnected | .syncing | .error(String)
    healthkit: .authorized | .denied | .notDetermined
    nutritrack: .connected | .disconnected | .syncing | .error(String)
}

DataAgeStatus {
    whoopAge: TimeInterval?             // seconds since last successful sync
    nutritrackAge: TimeInterval?
    healthkitAge: TimeInterval?

    func isStale(_ source: DataSource) -> Bool
    func isCriticallyStale(_ source: DataSource) -> Bool
}
```

### 2.3 Daily Score Calculation

The daily score (0-100) is a weighted composite. This is the EXACT algorithm — no shortcuts.

**Step 1: Compute raw sub-scores (each 0-100)**

| Component | Weight | Source | Formula | Edge Cases |
|-----------|--------|--------|---------|------------|
| Recovery | 25% | Whoop `recovery_score` | Direct pass-through (already 0-100) | If nil: weight redistributes. If 0: score is 0, not nil. |
| Nutrition | 25% | NutriTrack | `base = min(100, (calories_consumed / calories_target) * 100)`. Then: `penalty = missed_meals * 10` where missed = meals with status `.skipped`. Final: `max(0, base - penalty)` | If no target set: 0. If calories_consumed is nil: weight redistributes. If target is 0: guard against division by zero, treat as 0. Overeating does NOT reduce score — it caps at 100 for the calorie component. |
| Study | 25% | Local DB | `min(100, (study_minutes_today / study_target_minutes) * 100)` | If `study_target_minutes` is 0: guard, treat as 100 (no target = automatically met). If no sessions logged but target > 0: score is 0. |
| Movement | 25% | HealthKit | `steps_component = min(50, (steps / steps_target) * 50)` + `workout_component = (workout_status == .completed) ? 50 : 0`. Final: `min(100, steps_component + workout_component)` | If steps is nil and no workout: weight redistributes only if HealthKit is `.denied` or `.notDetermined`. If authorized but 0 steps (morning): score is 0 for this component, do NOT redistribute. |

**Step 2: Handle missing sources (weight redistribution)**

```
let connected_sources = sources.filter { $0.isAvailable }
if connected_sources.count < 2 {
    dailyScore = nil  // Show "--" — not enough data
    return
}

// Redistribute weights equally among available sources
let base_weight = 0.25
let missing_count = 4 - connected_sources.count
let extra_per_source = (base_weight * Double(missing_count)) / Double(connected_sources.count)

var score = 0.0
for source in connected_sources {
    score += source.rawScore * (base_weight + extra_per_source)
}
dailyScore = Int(round(score))
```

**"Available" means**: the source is connected AND has returned at least one non-nil primary value for today. A connected source with all nil values (e.g., Whoop connected but no recovery data yet) is treated as unavailable for score purposes.

**Step 3: Guard rails**
- Clamp final score to 0-100: `max(0, min(100, score))`
- If calculation results in NaN or Inf (e.g., division by zero slipped through): set `dailyScore = nil`, log error
- Score is always an integer — `Int(round(...))`

### 2.4 Data Formatting Rules

Every data value on the dashboard has an exact format, animation behavior, and stale indicator.

| Data Point | Format | Examples | Font Token | Color Token | Alignment | Animation on Change | Stale Treatment |
|-----------|--------|---------|------------|-------------|-----------|--------------------|-----------------|
| Recovery score | Integer + `%` suffix, no space | `72%`, `45%`, `91%` | `tempo.title1` | Recovery zone color (green/yellow/red) | Left | Counter roll: old value counts to new over `tempo.anim.counter` (0.8s). Each intermediate frame shows an integer. Direction: counts up or down naturally. | Yellow tint on % symbol if Whoop data > 30min old |
| HRV | 1 decimal + ` ms` suffix | `68.3 ms`, `112.0 ms` | `tempo.callout` | `tempo.text.primary` | Left in metric block | Fade transition: old value fades out (0.15s), new fades in (0.15s). No counter — decimals look jittery when counting. | Show `"--"` if nil. Yellow dot next to label if stale. |
| Resting heart rate | Integer + ` bpm` suffix | `52 bpm`, `61 bpm` | `tempo.callout` | `tempo.text.primary` | Left in metric block | Fade transition (same as HRV) | Show `"--"` if nil |
| Sleep hours | 1 decimal + `h` suffix, no space | `7.2h`, `5.8h` | `tempo.callout` | `tempo.text.primary` | Left in metric block | Fade transition | Show `"--"` if nil |
| Sleep performance | Integer + `%` suffix | `85%` | `tempo.callout` | `tempo.text.primary` | Left | Fade transition | Show `"--"` if nil |
| Strain | 1 decimal, no suffix | `14.2`, `8.7` | `tempo.caption2` | `tempo.text.tertiary` | Right-aligned below bar | Fade transition | Show `"--"` if nil |
| SpO2 | Integer + `%` suffix | `97%` | `tempo.callout` | `tempo.text.primary` | Left in metric block | Fade transition | Show `"--"` if nil |
| Calories consumed | Integer, locale thousands separator (`,` for en_US) | `1,842`, `2,150` | `tempo.callout` (in ring) or `tempo.display` (expanded hero) | `tempo.text.primary` | Centered in ring | Counter roll (0.8s). Counts through integers. Uses `NumberFormatter` with `.decimal` style for locale-appropriate separators during counting. | Yellow timestamp if NutriTrack > 20min old |
| Calorie target | Integer, locale thousands separator | `2,400` | `tempo.callout` | `tempo.text.tertiary` | After `/` | No animation (target rarely changes) | N/A (target is local) |
| Protein/Carbs/Fat | Integer + `g` suffix, no space | `142g`, `65g` | `tempo.caption2` | `tempo.text.primary` | Left of bar | Counter roll (0.4s, shorter since values are smaller) | Follow NutriTrack staleness |
| Macro target | Integer + `g` suffix | `180g`, `280g`, `80g` | `tempo.caption2` | `tempo.text.tertiary` | Right of bar | No animation | N/A |
| Steps | Integer, locale thousands separator | `8,432`, `12,100` | `tempo.callout` | Color-coded (see Move quadrant) | Left in metric block | Counter roll (0.8s). Counts through integers with separator formatting maintained at each frame. | Show `"--"` if nil |
| Active calories | Integer + ` cal` suffix | `342 cal`, `580 cal` | `tempo.callout` | `tempo.text.primary` | Left in metric block | Counter roll (0.6s) | Show `"--"` if nil |
| Study minutes | If >= 60: `Xh Ym`. If < 60: `Xm`. No leading zeros. | `2h 15m`, `45m`, `0m` | `tempo.title1` | `tempo.text.primary` | Left | Counter roll on the minute value. If crossing an hour boundary (e.g., 58m to 1h 02m), fade the entire string instead of counting. | N/A (local data) |
| Exam countdown | `in X days`. If today: `TODAY`. If tomorrow: `TOMORROW` | `in 6 days`, `TODAY`, `TOMORROW` | `tempo.caption1` | Varies (see Mind quadrant) | Left | No animation — value changes at midnight only | N/A |
| Daily score | Integer, no suffix. Displayed inside ring. | `78`, `0`, `100` | `tempo.display` | `tempo.text.primary` | Centered in ring | Counter roll on first appear: 0 to target over `tempo.anim.ring` (1.0s), synced with ring fill animation. On subsequent updates: counter roll from old to new over 0.5s. Each frame shows integer only. | Ring track pulses if all sources stale |
| Streak | Integer + `d` suffix, no space | `12d`, `3d` | `tempo.caption2` (< 7d) or `tempo.caption1` (>= 7d) | `tempo.text.secondary` (< 7d) or `tempo.orange` (>= 7d) | Left | Pop animation on increment: text scales 1.0 to 1.15 to 1.0 over 0.3s spring. Fire icon does the same. | N/A |
| Timestamps | Relative. `"Just now"` (< 60s). `"Xm ago"` (1-59 min). `"Xh ago"` (1-23h). `"Yesterday HH:mm"` (24-48h). `"MMM d"` (> 48h). | `Just now`, `2m ago`, `1h ago`, `Yesterday 14:30`, `Mar 22` | `tempo.caption2` | `tempo.text.tertiary` (normal), `tempo.stale` (stale), pulsing `tempo.stale` (critical) | Right-aligned or centered per context | No animation — updates every 60s via timer. Text changes with crossfade (0.15s). | Color shift to yellow at staleness threshold, pulsing at critical. |
| Meals logged count | `"X/Y meals"` or `"All Y meals logged"` | `2/4 meals`, `All 4 meals logged` | `tempo.caption1` | `tempo.text.secondary` or `tempo.green` (all logged) | Left | Fade transition when meal count changes. Checkmark appears with scale-in spring (0.3s) when all meals logged. | Follow NutriTrack staleness |

---

## 3. Main Dashboard View

### 3.1 Screen Architecture

The dashboard is a single `ScrollView` (vertical, `.bounces(true)`) with the following stacked sections from top to bottom:

```
+-------------------------------------+
|          Safe Area Top              |
+-------------------------------------+
|  [A] Header Bar                     |
+-------------------------------------+
|  [B] Daily Score Section            |
+-------------------------------------+
|  [C] Quadrant Grid (2x2)           |
|  +------------+  +------------+    |
|  |   BODY     |  |   FUEL     |    |
|  |            |  |            |    |
|  +------------+  +------------+    |
|  +------------+  +------------+    |
|  |   MIND     |  |   MOVE     |    |
|  |            |  |            |    |
|  +------------+  +------------+    |
+-------------------------------------+
|  [D] Non-Negotiables Bar           |
+-------------------------------------+
|  [E] Quick Insights Banner         |
+-------------------------------------+
|          Safe Area Bottom           |
+-------------------------------------+
```

The entire view is embedded in a `NavigationStack`. No `TabView` — the dashboard is the root of a single navigation stack. Tab bar (if present elsewhere in the app) sits below and is not part of this spec.

### 3.2 Section [A]: Header Bar

**Position**: Pinned to top of scroll view (not sticky — scrolls with content). Sits immediately below the safe area inset.

**Layout**:
```
+------------------------------------------+
| Mon, Mar 24                   [gear] [bell] |
| Rise and grind, Nicola.                 |
+------------------------------------------+
```

- **Left side, line 1**: Date — format: `EEE, MMM d` (e.g., `Mon, Mar 24`). Font: `tempo.callout`, color: `tempo.text.secondary`.
- **Left side, line 2**: Greeting text. Font: `tempo.title2`, color: `tempo.text.primary`.
- **Right side**: Two icon buttons, horizontally stacked, 8pt gap between them.
  - Settings gear: SF Symbol `gearshape.fill`, 22pt, `tempo.text.secondary`. Tap navigates to Settings screen (out of scope for this spec — push onto NavigationStack).
  - Notification bell: SF Symbol `bell.fill`, 22pt, `tempo.text.secondary`. If unread notifications exist, a 6pt red circle (`tempo.red`) is positioned at top-right of the bell icon, offset by (-2pt, 2pt). Tap navigates to Notifications screen.

**Padding**: 20pt horizontal (left and right), 8pt top (below safe area), 4pt bottom.

**Greeting Logic** (time-of-day based, using device local time):

| Time Range | Greeting Text |
|-----------|---------------|
| 04:00-07:59 | `"Early bird gets the gains, {firstName}."` |
| 08:00-11:59 | `"Rise and grind, {firstName}."` |
| 12:00-13:59 | `"No half reps this afternoon, {firstName}."` |
| 14:00-16:59 | `"Keep the pressure on, {firstName}."` |
| 17:00-20:59 | `"Finish what you started, {firstName}."` |
| 21:00-23:59 | `"Earn your sleep, {firstName}."` |
| 00:00-03:59 | `"You should be asleep, {firstName}."` |

Replace `{firstName}` with user's first name from their profile. If no name is set, omit the name entirely (e.g., `"Rise and grind."`).

### 3.3 Section [B]: Daily Score Section

**Position**: Below header, centered horizontally.

**Layout**:
```
        +----------+
        |          |
        |    78    |
        |          |
        +----------+
        Daily Score
      Last sync: 2m ago
```

**Score Ring — Geometry**:
- **Outer diameter**: 100pt
- **Ring stroke width**: 8pt (this means the visible ring band is 8pt thick)
- **Inner clear area diameter**: 84pt (100 - 8 - 8)
- **Track color** (background ring): `tempo.ring.track`
- **Gap at top**: 4pt gap (3.6 degrees) at the 12 o'clock position — the ring is NOT a complete circle. This gap gives the ring a modern, Oura-like feel. The track ring shows the gap. The fill ring starts at 12 o'clock + 1.8 degrees (half the gap) and fills clockwise.
- **Fill color**: Angular gradient along the ring path:
  - Score 0-39: Gradient from `tempo.red` (start) to a slightly darker red `#CC2F26` (end of fill)
  - Score 40-69: Gradient from `tempo.yellow` to a slightly deeper amber `#E6C109`
  - Score 70-100: Gradient from `tempo.green` to a slightly deeper green `#28B84C`
- **Ring cap style**: `.round` — the ends of the fill arc are rounded, not flat
- **Fill amount**: `score / 100` of the available arc (360 degrees minus the 3.6 degree gap = 356.4 degrees available)
- **Score number**: Centered inside the ring vertically and horizontally. Font: `tempo.display` (34pt Black). Color: `tempo.text.primary`. Baseline sits at ring vertical center + 12pt (visually centered accounting for ascender/descender).

**Score Ring Animation**:
- **On first appear** (app cold launch, tab switch with `!hasAnimated`):
  1. Ring track appears immediately (opacity 1.0)
  2. Fill arc animates from 0 degrees to target fill over `tempo.anim.ring` (1.0s spring, response: 0.8, dampingFraction: 0.7). The spring curve means it slightly overshoots the target and settles.
  3. Score number counts up from 0 to target value simultaneously, driven by a `TimelineView(.animation)` that ticks every frame. At each frame: `displayedValue = Int(round(animationProgress * targetScore))`. The counter naturally syncs with the ring because both use the same animation progress value.
  4. Number displays as integer only at every frame — no decimals, no formatting artifacts during count.
- **On data update** (pull-to-refresh returns new score):
  1. Ring animates from current fill angle to new fill angle over 0.5s spring.
  2. Number counts from current displayed value to new value over the same 0.5s.
  3. If the score crosses a color zone boundary (e.g., 65 to 72 = yellow to green), the fill color crossfades to the new zone color over the same 0.5s. The gradient endpoint changes, and the transition is handled by `AnimatableModifier` on the gradient colors.
- **On app foreground** (data already cached, no change): No animation. Ring and number appear at current values instantly.

**"Daily Score" label**: Centered below ring, 4pt gap. Font: `tempo.caption1`, color: `tempo.text.secondary`.

**"Last sync" label**: Centered below "Daily Score", 2pt gap. Font: `tempo.caption2`, color: `tempo.text.tertiary`. Format: `Last sync: {relative_time}` using the most recent `lastSync` timestamp from any connected data source. Color shifts to `tempo.stale` if the most recent sync is > 30 min ago.

**Score Ring States**:

| State | Ring | Number | Label | Animation |
|-------|------|--------|-------|-----------|
| Full data (>= 2 sources) | Filled to score with gradient | `78` | "Daily Score" | Ring fill + counter (see above) |
| Loading (first load, never had data) | Track ring pulses: opacity 0.3 to 1.0 to 0.3, 1.5s sinusoidal loop | `--` (em dashes, `tempo.display`, `tempo.text.tertiary`) | "Calculating..." in `tempo.text.tertiary` | Pulse continues until data arrives |
| Data refreshing (had data, now refreshing) | Ring stays at previous fill value. A subtle shimmer sweeps across the ring stroke (same shimmer as skeleton loading). | Previous score number remains | "Syncing..." in `tempo.text.tertiary`, animated dots: `"Syncing."` -> `"Syncing.."` -> `"Syncing..."` every 0.5s | Shimmer on ring, dot animation on label |
| Insufficient data (< 2 sources connected) | Empty track ring (no fill), full opacity | `--` | "Connect more sources" | None — static |
| Error (all sources errored) | Track ring tinted red: `tempo.red` at 20% opacity overlaid on track | `!` in `tempo.red`, `tempo.display` | "Sync failed — pull to retry" in `tempo.red` | Exclamation mark pulses opacity 0.6 to 1.0, 1s cycle |
| Offline with cached score | Ring filled to cached score, but ring stroke becomes dashed (5pt dash, 3pt gap) | Cached score number | "Offline" in `tempo.stale` | Dash pattern animates: rotates slowly clockwise, 1 revolution per 10s |

**Padding**: 16pt top, 20pt bottom.

### 3.4 Section [C]: Quadrant Grid

**Layout**: A 2-column `LazyVGrid` with two rows, creating a 2x2 grid.

```swift
// Exact layout definition
LazyVGrid(columns: [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16)
], spacing: 16)
```

- **Horizontal inset**: 20pt left and right (matching screen edge insets).
- **Inter-card gap**: 16pt horizontal, 16pt vertical.
- **Card height behavior**: Not fixed. Cards are flexible height. Minimum height: 160pt. Maximum height: unbounded (content-driven). Each row aligns to the taller card in that row.

**Grid order** (reading order, left-to-right, top-to-bottom):
1. Top-left: **BODY**
2. Top-right: **FUEL**
3. Bottom-left: **MIND**
4. Bottom-right: **MOVE**

This order is fixed and not user-configurable in v1.

**Card Base Style** (shared by all four quadrants):

- Background: `tempo.bg.card`
- Corner radius: `tempo.radius.card` (16pt)
- Shadow: `tempo.shadow.card`
- Internal padding: 14pt all sides
- Border: None in default state. When tapped (pressed state), background changes to `tempo.bg.card.pressed` with `tempo.anim.fast`.
- Tap gesture: The entire card is tappable. On tap, navigates to the expanded quadrant view (Section 4). Use `ButtonStyle` that scales the card to 0.97 on press with `tempo.anim.fast` and returns to 1.0 on release.
- **Per-quadrant stale overlay**: If the quadrant's data source is stale (see Section 13), a 1pt border in `tempo.stale` at 40% opacity appears around the card, inside the existing corner radius. This is in addition to the yellow timestamp treatment.

**Card Internal Structure** (shared skeleton):
```
+----------------------------+
| CATEGORY LABEL    [icon]   |  <- overline + accent icon
|                            |
| Primary Value              |  <- large number
| Primary Subtitle           |  <- label for value
|                            |
| metric1    metric2         |  <- secondary metrics row
| label1     label2          |
|                            |
| [Status / Progress]        |  <- contextual bottom row
+----------------------------+
```

**Quadrant-specific per-device adjustments**:

| Element | iPhone SE (159.5pt card) | iPhone 15 (168.5pt card) | iPhone 15 Pro Max+ (187pt+ card) |
|---------|------------------------|-------------------------|----------------------------------|
| BODY secondary metrics | Show 2 metrics only (HRV + Sleep). Hide RHR — still in expanded view. | Show all 3 (HRV, RHR, Sleep) | Show all 3, comfortable spacing |
| FUEL macro bar labels | Single letter: `P`, `C`, `F` | Single letter: `P`, `C`, `F` | Full word: `Protein`, `Carbs`, `Fat` if card width >= 187pt |
| MIND exam name | Truncate with `...` after 12 chars | Truncate after 15 chars | Truncate after 20 chars |
| MOVE active cal label | `"Act Cal"` | `"Active Cal"` | `"Active Cal"` |
| General text | `.minimumScaleFactor(0.8)` on all value labels to prevent clipping | Scale factor 0.85 | No scaling needed |

---

#### 3.4.1 BODY Quadrant

**Category label**: `"BODY"` — font: `tempo.overline`, color: `tempo.text.secondary`, uppercased, tracking: 1.5pt.

**Accent icon**: SF Symbol `heart.fill`, 14pt, color: matches recovery zone color (green/yellow/red). Positioned top-right of card, vertically aligned with category label.

**Primary value**: Recovery score. Font: `tempo.title1` (22pt Bold). Color: recovery zone color.
- Green (`tempo.body.green`): recovery >= 67
- Yellow (`tempo.body.yellow`): recovery 34-66
- Red (`tempo.body.red`): recovery < 34
- Displayed as: `72%`
- **Value change animation**: Counter roll from old to new over `tempo.anim.counter` (0.8s). If the zone color changes, the color crossfades simultaneously using `.contentTransition(.numericText())` in iOS 17+.

**Primary subtitle**: `"Recovery"` — font: `tempo.caption1`, color: `tempo.text.secondary`. Positioned 2pt below primary value.

**Secondary metrics row**: A horizontal row of 2-3 small metric blocks (see per-device table above), evenly spaced across the card width, 12pt below the primary subtitle.

Each metric block:
```
  68.3        52         7.2h
  HRV (ms)   RHR (bpm)  Sleep
```
- Value: font `tempo.callout` (14pt Medium), color `tempo.text.primary`
- Label: font `tempo.caption2` (11pt Regular), color `tempo.text.tertiary`, 1pt below value
- Value change: fade transition (0.15s out, 0.15s in) — never counter roll on decimals

Metrics shown (left to right):
1. **HRV**: value = `hrv_rmssd` formatted to 1 decimal. Label = `"HRV"`. If nil, show `"--"`.
2. **RHR**: value = `resting_heart_rate` as integer. Label = `"RHR"`. If nil, show `"--"`. Hidden on iPhone SE.
3. **Sleep**: value = `sleep_hours` formatted to 1 decimal + `"h"`. Label = `"Sleep"`. If nil, show `"--"`.

**Bottom row**: Strain indicator. A thin horizontal bar (height: 4pt, corner radius: 2pt) spanning the card width (minus internal padding). Track color: `tempo.ring.track`. Fill color: gradient from `tempo.green` (low strain) to `tempo.red` (high strain) — a three-stop gradient: `tempo.green` at 0%, `tempo.yellow` at 50%, `tempo.red` at 100%. The fill extends to `strain / 21.0` of the bar. Below the bar, right-aligned: `"Strain 14.2"` — font: `tempo.caption2`, color: `tempo.text.tertiary`. 8pt gap above the bar from the secondary metrics row. Fill animates to new position with `tempo.anim.standard` when strain value updates.

**Full Data Example**:
```
+----------------------------+
| BODY                    V  |
|                            |
| 72%                        |
| Recovery                   |
|                            |
| 68.3    52      7.2h       |
| HRV     RHR     Sleep      |
|                            |
| ============-----------    |
|                Strain 14.2 |
+----------------------------+
```

**Whoop Disconnected State**:
```
+----------------------------+
| BODY                    V  |
|                            |
| [Whoop icon]               |
| Connect Whoop              |
| to track recovery          |
|                            |
|      [ Connect ]           |
|                            |
+----------------------------+
```
- Icon: SF Symbol `sensor.tag.radiowaves.forward.fill`, 28pt, color: `tempo.text.tertiary`.
- "Connect Whoop" — font: `tempo.callout`, color: `tempo.text.primary`.
- "to track recovery" — font: `tempo.caption2`, color: `tempo.text.tertiary`.
- `[ Connect ]` button: pill-shaped, background `tempo.accent`, text color white, font `tempo.callout`, horizontal padding 20pt, vertical padding 8pt, corner radius `tempo.radius.pill`. Tap opens Whoop OAuth flow.
- All content is centered vertically and horizontally within the card.

**Loading State (Skeleton Shimmer)**:
```
+----------------------------+
| BODY                    V  |
|                            |
| ----                       |  <- shimmer placeholder (40pt wide, 22pt tall, 4pt radius)
| ---------                  |  <- shimmer placeholder (70pt wide, 12pt tall)
|                            |
| ---  ---  ----             |  <- shimmer placeholders (each 30pt wide, 14pt tall)
| ---  ---  -----            |  <- shimmer placeholders (each 30pt wide, 11pt tall)
|                            |
| -------------------------  |  <- shimmer bar (full width, 4pt tall)
+----------------------------+
```
- Shimmer animation: A diagonal gradient highlight (white at 30% opacity, 40pt wide band, angled 20 degrees) sweeps left-to-right across all placeholder rectangles simultaneously over `tempo.anim.shimmer` (1.5s), linear timing, repeating infinitely. Placeholder base color: `tempo.ring.track`, corner radius 4pt on all rectangles.
- **Independent per-quadrant skeleton**: Each quadrant can be in skeleton state independently. If Whoop loads first, BODY shows real data while FUEL still shows skeleton (if NutriTrack is slower). The skeleton-to-data transition per quadrant: all shimmer placeholders crossfade to real content over 0.25s. No layout jump — the placeholder rectangles are positioned to match real content positions exactly.

**Error State** (Whoop connected but API returned error):
```
+----------------------------+
| BODY                    V  |
|                            |
| [!]                        |
| Sync failed                |
| Pull to refresh            |
|                            |
|           2m ago           |
+----------------------------+
```
- Warning icon: SF Symbol `exclamationmark.triangle.fill`, 24pt, `tempo.yellow`.
- "Sync failed" — font: `tempo.callout`, color: `tempo.text.primary`.
- "Pull to refresh" — font: `tempo.caption2`, color: `tempo.text.tertiary`.
- Timestamp: last successful sync. Font: `tempo.caption2`, color: `tempo.text.tertiary`, right-aligned at bottom.

**Partial Data State** (some fields nil, e.g., recovery available but HRV not yet):
- Show available fields normally. For nil fields, show `"--"` in the value position with the label still visible. Do not hide the metric block. This prevents layout shifts when data arrives.

---

#### 3.4.2 FUEL Quadrant

**Category label**: `"FUEL"` — font: `tempo.overline`, color: `tempo.text.secondary`.

**Accent icon**: SF Symbol `flame.fill`, 14pt, color: `tempo.purple`.

**Primary value**: Calorie progress ring.
- Ring outer diameter: 52pt
- Ring stroke width: 5pt
- Inner clear area: 42pt diameter
- Track: `tempo.ring.track`
- Fill: `tempo.purple`, solid (no gradient)
- Fill amount: `min(1.0, calories_consumed / calories_target)`
- No gap at top (unlike the daily score ring — this is a simpler progress ring)
- Ring cap: `.round`
- **Inside the ring**: consumed calories as integer (font: `tempo.callout`, color: `tempo.text.primary`). Use `.minimumScaleFactor(0.6)` to fit 4-digit numbers. If the number is 5+ digits (unlikely but guarded), show in abbreviated form: `"10.2k"`.
- **Right of the ring** (8pt gap, vertically centered):
  - Line 1: `"1,842 / 2,400"` — `calories_consumed` in `tempo.callout` + `tempo.text.primary`, then `" / "` in `tempo.text.tertiary`, then `calories_target` in `tempo.callout` + `tempo.text.tertiary`.
  - Line 2: `"kcal"` — font: `tempo.caption2`, color: `tempo.text.tertiary`.
- **Ring fill animation**: On value change, ring fill animates from old to new over 0.4s spring. Calorie number inside ring does counter roll simultaneously.

**Macro bars**: Three horizontal progress bars, stacked vertically with 6pt spacing between them, 12pt below the calorie section. Each bar:
- Height: 6pt, corner radius: 3pt
- Track: `tempo.ring.track`
- Full width: card width minus (2 * 14pt internal padding)
- Label left of bar: macro initial + amount. Font: `tempo.caption2`, color: `tempo.text.primary`.
- Target right of bar: target amount. Font: `tempo.caption2`, color: `tempo.text.tertiary`.

Layout for each bar row:
```
P 142g  ============-------  180g
C 205g  ==============-----  280g
F  52g  ======-------------   80g
```

Bar fill colors:
- Protein: `#5AC8FA` (system teal)
- Carbs: `#FFD60A` (system yellow)
- Fat: `#FF9F0A` (system orange)

Bar fill animation: On value change, bar width animates from old to new over `tempo.anim.standard` (0.35s spring). The label counters roll simultaneously.

**Bottom row**: Meals logged status. Format: `"{logged}/{planned} meals"`. Font: `tempo.caption1`, color: `tempo.text.secondary`. If all meals logged, color changes to `tempo.green` and text becomes `"All {planned} meals logged "` + SF Symbol `checkmark` inline (12pt, `tempo.green`, not emoji). Checkmark appears with scale-in: 0 to 1.0 over 0.3s spring.

**NutriTrack Disconnected State**:
Same pattern as Body disconnected. Icon: SF Symbol `fork.knife`, 28pt. Text: `"Connect NutriTrack"` / `"to track nutrition"`. Button: `[ Connect ]` same style as Body. Tap opens NutriTrack auth flow.

**Loading State**: Same shimmer pattern as Body. Ring placeholder is a circle shimmer (52pt), bar placeholders are rectangles.

**Edge case — calories over target**: If `calories_consumed > calories_target`, the ring fills to 100% and the fill color changes to `tempo.red`. The calorie text shows the actual consumed value. An additional label appears: `"+{overage} kcal over"` in `tempo.red`, font `tempo.caption2`. This label fades in with `tempo.anim.fade` (0.25s).

**Edge case — no meals planned**: If `meals_planned` is 0 or nil, bottom row shows `"No meals planned"` in `tempo.text.tertiary`.

---

#### 3.4.3 MIND Quadrant

**Category label**: `"MIND"` — font: `tempo.overline`, color: `tempo.text.secondary`.

**Accent icon**: SF Symbol `book.fill`, 14pt, color: `tempo.blue`.

**Primary value**: Study minutes today. Font: `tempo.title1`, color: `tempo.text.primary`. Formatted per Section 2.4 rules (e.g., `"2h 15m"` or `"45m"`).

**Primary subtitle**: Progress fraction `"{minutes} / {target} min"`. Font: `tempo.caption1`, color: `tempo.text.secondary`.
- If study_minutes >= study_target: text becomes `"Target hit."`, color `tempo.green`, with a brief pulse animation (scale 1.0 to 1.05 to 1.0 over 0.3s) on the moment it transitions.

**Progress bar**: Full-width horizontal bar, 4pt height, corner radius 2pt. Track: `tempo.ring.track`. Fill: `tempo.blue`. Fill amount: `min(1.0, study_minutes / study_target)`. 10pt below subtitle. Fill animates with `tempo.anim.standard` on value change.

**Exam countdown**: The most urgent exam (earliest `date` that is >= today). Displayed 10pt below the progress bar.
```
[calendar] Calculus II in 6 days
```
- Calendar icon: SF Symbol `calendar`, 12pt, color: `tempo.text.secondary`.
- Exam name: font `tempo.caption1`, color: `tempo.text.primary`. Truncation: see per-device table.
- Countdown: font `tempo.caption1`, color varies:
  - <= 3 days: `tempo.red`
  - 4-7 days: `tempo.yellow`
  - > 7 days: `tempo.text.secondary`
- Format: `"{name} in {N} days"`, or `"{name} TOMORROW"`, or `"{name} TODAY"` (in `tempo.red`, bold).

If there are 2+ exams within 14 days, show the second exam on a new line directly below, same format but font `tempo.caption2` and color `tempo.text.tertiary`.

**Bottom row**: Streak badge. Only shown if `current_streak_days >= 2`.
```
[flame] 12d streak
```
- Fire icon: SF Symbol `flame.fill`, 11pt, color: `tempo.orange`.
- Text: `"{N}d streak"` — font: `tempo.caption2`, color: `tempo.text.secondary`.
- If streak >= 7, add emphasis: font becomes `tempo.caption1` (Medium weight), color `tempo.orange`.

**No Exams Set State**: Exam countdown section is hidden. In its place: `"No upcoming exams"` — font: `tempo.caption2`, color: `tempo.text.tertiary`. Below it: `"+ Add exam"` as a tappable text link, font: `tempo.caption2`, color: `tempo.blue`. Tap presents Add Exam sheet (modal `.sheet`).

**No Study Data (first day or no sessions today)**: Primary value shows `"0m"`. Subtitle shows `"0 / {target} min"`. Progress bar is empty. A motivational nudge appears: `"Open a book. NOW."` — font: `tempo.caption2`, color: `tempo.accent`, italic. Positioned where the exam countdown would be, only shown if study_minutes == 0.

---

#### 3.4.4 MOVE Quadrant

**Category label**: `"MOVE"` — font: `tempo.overline`, color: `tempo.text.secondary`.

**Accent icon**: SF Symbol `figure.run`, 14pt, color: `tempo.orange`.

**Primary value display** depends on `workout_status`:

**Case: `.completed`**:
- Primary value: SF Symbol `checkmark.circle.fill` at 20pt inline + `" Done"`. Font: `tempo.title1`, color: `tempo.green`.
- Below (2pt gap): workout name, e.g., `"Upper Body Push -- 52m"`. Font: `tempo.caption1`, color: `tempo.text.secondary`.

**Case: `.planned`**:
- Primary value: workout name. Font: `tempo.title1`, color: `tempo.text.primary`.
- Below (2pt gap): `"Planned for today"`. Font: `tempo.caption1`, color: `tempo.orange`.

**Case: `.restDay`**:
- Primary value: `"Rest Day"`. Font: `tempo.title1`, color: `tempo.text.secondary`.
- Below (2pt gap): `"Recovery is training."`. Font: `tempo.caption1`, color: `tempo.text.tertiary`, italic.

**Case: `.none`** (no workout planned or completed, not a designated rest day):
- Primary value: `"No workout"`. Font: `tempo.title1`, color: `tempo.text.tertiary`.
- Below (2pt gap): `"Add one or skip -- your call."`. Font: `tempo.caption1`, color: `tempo.text.tertiary`.

**Secondary metrics row** (10pt below workout section): Two metric blocks, evenly split across card width.

```
  8,432        342 cal
  Steps        Active Cal
```

- Steps value: formatted with thousands separator. Label: `"Steps"`.
  - Color coding: if `steps >= steps_target`: `tempo.green`. If `steps >= steps_target * 0.7`: `tempo.text.primary`. Else: `tempo.text.secondary`.
- Active calories value: integer + ` cal`. Label: `"Active Cal"` (or `"Act Cal"` on SE).
- Both values animate with counter roll on change (0.8s for steps, 0.6s for calories).

**Bottom row**: Steps progress bar. Same style as Mind's progress bar. Track: `tempo.ring.track`. Fill: `tempo.orange`. Fill: `min(1.0, steps / steps_target)`. Right-aligned below bar: `"{steps_target formatted} goal"` — font: `tempo.caption2`, color: `tempo.text.tertiary`.

**HealthKit Not Authorized State**: Same disconnected pattern. Icon: SF Symbol `heart.text.square`, 28pt. Text: `"Allow Health Access"` / `"to track activity"`. Button: `[ Authorize ]`. Tap triggers `HKHealthStore.requestAuthorization()`.

**No Step Data Yet (morning, HealthKit authorized but 0 steps)**: Show `"0"` for steps, `"0 cal"` for active calories. Progress bar empty. This is not an error — it is the expected morning state.

---

### 3.5 Section [D]: Non-Negotiables Bar

**Position**: Below quadrant grid, 20pt gap.

**Concept**: The user defines up to 7 daily "non-negotiable" tasks. Completing all of them "unlocks" a reward (e.g., PS5 time). This bar shows progress.

**Layout**:
```
+-----------------------------------------+
| 3/5 done -- PS5 locked [lock]           |
| ==================-----------           |
| [v] Morning workout  [v] 8h sleep      |
| [ ] 2L water  [ ] Meal prep  [v] Study |
+-----------------------------------------+
```

**Container**: Full width (minus 20pt left/right insets), background `tempo.bg.card`, corner radius `tempo.radius.card`, shadow `tempo.shadow.card`, padding 14pt.

**Header line**: Left-aligned. Format: `"{completed}/{total} done -- {reward_name} {lock_status}"`.
- Font: `tempo.callout`, color: `tempo.text.primary`.
- Lock status:
  - If all completed: `"unlocked"` + SF Symbol `lock.open.fill`, color `tempo.green`.
  - If not all completed: `"locked"` + SF Symbol `lock.fill`, color `tempo.locked`.

**Progress bar**: Below header, 8pt gap. Full width, height 6pt, corner radius 3pt. Track: `tempo.ring.track`. Fill: `tempo.accent`. Fill amount: `completed / total`. When all complete, fill color transitions to `tempo.green` with `tempo.anim.standard`. Fill animates on each completion.

**Non-negotiable items**: Below progress bar, 10pt gap. Flow layout (horizontal wrap). Each item is a pill:
- Completed: SF Symbol `checkmark.circle.fill` at 10pt, `tempo.green`. Text: `tempo.caption2`, color: `tempo.text.secondary`, strikethrough.
- Incomplete: SF Symbol `circle` at 10pt, `tempo.text.tertiary`. Text: `tempo.caption2`, color: `tempo.text.primary`.
- Items wrap to next line if they overflow. Horizontal gap between pills: 12pt. Vertical gap between rows: 6pt.

**Tap interaction on individual item**: Tapping an incomplete item marks it as complete. Tapping a completed item marks it as incomplete (toggle). On complete:
1. Haptic feedback (`UIImpactFeedbackGenerator`, `.light`)
2. Checkmark icon scales from 0 to 1.0 with spring (0.3s, response: 0.3, dampingFraction: 0.6)
3. Text transitions to strikethrough with 0.2s crossfade
4. Progress bar fill animates to new width over `tempo.anim.standard`

**Long press on item**: Opens a context menu with:
- "Edit" — presents edit sheet
- "Remove" — removes with confirmation alert

**All-complete celebration**: When the last item is checked off:
1. The progress bar fill transitions to green (0.35s).
2. The lock icon transitions to unlocked with a 0.5s spring scale animation (scale 1.0 to 1.3 to 1.0).
3. A confetti-like particle burst (subtle — 10-15 small colored circles, `tempo.anim.confetti` 0.8s duration) emits from the lock icon position. Particles: 3-5pt circles in `tempo.green`, `tempo.yellow`, `tempo.accent`, `tempo.blue`, `tempo.orange`. Particles fly outward in a 120-degree upward cone with randomized velocities (40-80pt/s) and gravity pulling them down. Fade to 0% opacity over the last 0.3s. Use a custom `Canvas` or `TimelineView` for this.
4. Haptic: `UINotificationFeedbackGenerator`, `.success`.

**Empty State (no non-negotiables set)**: Bar still shows but with: `"Set your daily non-negotiables"` — font: `tempo.callout`, color: `tempo.text.secondary`. Below: `"+ Add non-negotiable"` link, font: `tempo.caption1`, color: `tempo.accent`. Tap presents the Add Non-Negotiable sheet.

### 3.6 Section [E]: Quick Insights Banner

**Position**: Below non-negotiables, 16pt gap. Only shown if there is an insight to display.

**Layout**:
```
+-----------------------------------------+
| [bulb] When you sleep < 6.5h, you skip |
|        breakfast 67% of the time.       |
|                                    [>]  |
+-----------------------------------------+
```

**Container**: Full width (minus 20pt insets), background `tempo.bg.card`, corner radius `tempo.radius.card`, shadow `tempo.shadow.card`, padding 14pt.

**Icon**: SF Symbol `lightbulb.fill`, 14pt, color `tempo.yellow`. Top-left, aligned with first line of text.

**Text**: Font: `tempo.body`, color: `tempo.text.primary`. Max 2 lines. The text is generated by the AI Insights Engine (see Section 10) and cached. One insight per day — rotate daily.

**Arrow**: SF Symbol `chevron.right`, 12pt, color: `tempo.text.tertiary`. Right side, vertically centered. Indicates tappability.

**Tap**: Navigates to Pattern/Correlation view (Section 6), scrolled to the relevant insight.

**Dismiss**: Swipe left to dismiss the banner for the day. A 60pt swipe threshold triggers the dismiss. The banner slides out to the left with `tempo.anim.dismiss` (0.3s easeIn). Dismissal is stored locally (per-day flag). The space collapses after dismissal with `tempo.anim.standard` (0.35s spring) so the FAB doesn't jump.

**No insight available**: Banner is not rendered. The space collapses (no blank gap).

### 3.7 Pull-to-Refresh

**Trigger**: Custom pull-to-refresh on the scroll view. Overscroll threshold: 60pt.

**Custom Pull Indicator Design** (NOT the default iOS spinner):

The indicator is a custom view that appears above the header when the user pulls down.

**Pull-down states (as user drags)**:
1. **0-30pt overscroll**: A small ring (24pt diameter, 2pt stroke, `tempo.accent`) begins drawing clockwise from 12 o'clock. At 30pt, the ring is 50% drawn.
2. **30-60pt overscroll**: Ring continues drawing. At 60pt, the ring is 100% drawn. The ring scales from 0.8 to 1.0 during this phase.
3. **60pt threshold crossed**: Haptic (`UIImpactFeedbackGenerator`, `.medium`). The ring becomes a spinning indicator — it rotates continuously at 1 revolution per 0.8s. A status text appears below the ring.

**Status text during refresh** (sequential, centered below spinning ring):
- Font: `tempo.caption1`, color: `tempo.text.secondary`
- Text transitions with crossfade (0.15s):

| Phase | Text | Duration |
|-------|------|----------|
| 1. Whoop sync starts | `"Pulling recovery data..."` | Shows until Whoop responds or 3s, whichever is first |
| 2. NutriTrack sync starts (parallel) | `"Syncing meals..."` | Shows for 1.5s or until NutriTrack responds |
| 3. HealthKit query runs (parallel) | `"Reading activity..."` | Shows for 1s or until HealthKit responds |
| 4. All sources responded | `"Locked in."` | Shows for 0.6s minimum display time |

**The status text cycles through sources in the order above regardless of which finishes first.** If all sources respond before the text cycle completes, fast-forward to "Locked in." after a 0.3s minimum on the current text.

**Minimum display time**: The pull-to-refresh indicator stays visible for at least 1.0s total (even if all sources respond instantly). This prevents a jarring flash.

**Refresh behavior**:
1. On trigger, all data sources refresh in parallel:
   - Whoop API: fetch today's recovery, sleep, strain
   - NutriTrack API: fetch today's meals, calories, macros
   - HealthKit: re-query today's steps, calories, workouts, heart rate
   - Local DB: re-read study data, non-negotiables
2. Each quadrant independently transitions from current data to new data. If a quadrant's data changes, its values animate (counter roll, bar fill, etc.). If data hasn't changed, no animation — values stay static. **No shimmer during pull-to-refresh** — unlike first load, pull-to-refresh keeps the old data visible while fetching.
3. The spinner dismisses after ALL sources have responded (or timed out). Timeout per source: 10 seconds. If a source times out, show its last cached data with a stale indicator (timestamp turns `tempo.stale`).
4. The daily score re-calculates after all sources respond. Score ring animates to new value.
5. "Last sync" timestamp updates to "Just now".

**Error during refresh**: If a source errors during refresh:
- That quadrant's data remains unchanged (shows cached data)
- A brief toast appears at the bottom of the screen: `"[source] sync failed"` — font: `tempo.caption1`, background: `tempo.bg.card`, `tempo.shadow.elevated`, corner radius 8pt, padding 8pt 12pt. Auto-dismisses after 2s with slide-down + fade.
- Other quadrants continue refreshing independently.

**If ALL sources fail**: Toast shows `"Sync failed. Check your connection."`. The spinning ring transitions to `tempo.red` briefly (0.3s) before the indicator dismisses.

### 3.8 Scroll Behavior

- The entire dashboard scrolls vertically. There is no horizontal scrolling.
- On iPhone SE (375pt width, ~667pt height), all content fits within approximately 896pt, requiring a ~310pt scroll.
- On iPhone 15 Pro Max (430pt width, ~932pt height), all content may fit without scrolling if non-negotiables have <= 5 items and the insight banner is present.
- Content inset at bottom: 34pt (safe area) + 16pt extra breathing room = 50pt.
- Scroll indicators: hidden (`.scrollIndicators(.hidden)`).
- Scroll bounces at top (enables pull-to-refresh) and bottom.

### 3.9 Load Choreography — First Appear Stagger Animation

When the dashboard loads for the first time (app launch or tab switch), elements animate in with a precisely timed staggered sequence. Each quadrant can be in skeleton, real data, or disconnected state independently.

**Phase 1: Layout appears (t=0.0s)**:
1. **t=0.0s**: Header fades in (opacity 0 to 1, duration 0.2s, easeOut). Immediate — no delay.
2. **t=0.1s**: Score ring track appears (opacity 0 to 1, 0.15s). Score ring begins fill animation (1.0s spring). Number begins counting.

**Phase 2: Quadrants stagger in (t=0.2s - 0.44s)**:
3. **t=0.2s**: Body quadrant slides up from 20pt below its final position + fades in (opacity 0 to 1). Duration: `tempo.anim.standard` (0.35s spring). The card appears in whatever state it's in:
   - If data cached from previous session: renders with cached data immediately (no skeleton).
   - If no cache and source connected: renders in skeleton shimmer state. When data arrives (could be 0.5s to 3s later), skeleton crossfades to real data (0.25s).
   - If source disconnected: renders in disconnected state immediately.
4. **t=0.28s**: Fuel quadrant slides up + fades in (same animation). Same state logic.
5. **t=0.36s**: Mind quadrant slides up + fades in. Mind always has local data, so it never shows skeleton.
6. **t=0.44s**: Move quadrant slides up + fades in. HealthKit data is typically instant, so skeleton is rare here.

**Phase 3: Bottom sections (t=0.5s+)**:
7. **t=0.5s**: Non-negotiables bar slides up + fades in (0.35s spring). Always has local data.
8. **t=0.6s**: Insight banner slides up + fades in (0.35s spring). Only if an insight exists.

**Skeleton-to-data transition per quadrant**:
When a quadrant is in skeleton state and its data arrives:
1. Shimmer animation stops
2. All placeholder rectangles crossfade to the real content (0.25s easeInOut)
3. The card height may change (if real content is taller/shorter than the 180pt skeleton height). The height change is animated with `tempo.anim.standard` (0.35s spring). This means the grid row height changes, which pushes the second row down. That movement is animated too.
4. After real values are visible, value-specific animations fire (e.g., recovery ring fill, calorie ring fill). These start 0.1s after the crossfade completes.

**On subsequent appearances** (returning from a detail view): No stagger animation plays — content appears immediately at current state.

Use an `@State private var hasAnimated = false` flag per session, set to `true` after first animation. On `onAppear`, if `!hasAnimated`, run the sequence.

---

## 4. Expanded Quadrant Views

### 4.1 Expansion Mechanic

When a user taps a quadrant card, the app navigates to a **full-screen detail view** via `NavigationStack` push. This is NOT a bottom sheet and NOT an in-place expansion — it is a standard iOS navigation push with a custom matched geometry transition.

**Transition choreography**:
1. The tapped card's `ButtonStyle` fires: scale 1.0 to 0.97 (press), back to 1.0 (release). Duration: `tempo.anim.fast` (0.2s).
2. Simultaneously, `matchedGeometryEffect` begins: the card's frame (position + size + corner radius) animates to fill the screen.
   - Shared namespace: `"quadrant"`, id = quadrant type enum (`.body`, `.fuel`, `.mind`, `.move`)
   - The card background color stays `tempo.bg.card` during transition and becomes the detail view background.
   - Corner radius animates: 16pt (card) to 0pt (full screen). Use `matchedGeometryEffect` on the background `RoundedRectangle`.
3. Duration: `tempo.anim.expand` (0.4s spring, response: 0.4, dampingFraction: 0.82).
4. During the transition, card content fades out (0.15s) and detail view content fades in (0.15s, starting at t=0.2s of the transition). This prevents content from stretching oddly during the geometry change.
5. The navigation bar appears with a back button (SF Symbol `chevron.left`, `tempo.text.primary`). Title = quadrant name ("Body", "Fuel", "Mind", "Move"). Nav bar animates in from the top with 0.2s fade, starting at t=0.2s.

**Back navigation**: Standard iOS back swipe gesture (edge pan from left, 20pt trigger zone) or back button tap. Same matched geometry transition in reverse: detail content fades out (0.15s), card content fades in, geometry contracts from full screen back to the card's position in the grid.

**Scroll position preservation**: When returning to the dashboard from an expanded view, the scroll position is exactly where the user left it. The expanded card is visible on screen.

---

### 4.2 Body Expanded View

**Screen title**: `"Body"` (in nav bar)

**Layout** (top to bottom, scrollable):

```
+-----------------------------------------+
| < Body                                 |
+-----------------------------------------+
|                                         |
|        +-------------+                  |
|        |             |                  |
|        |     72%     |   Recovery       |
|        |             |   "You're good   |
|        +-------------+    to push it."  |
|                                         |
|  HRV        RHR       Sleep    SpO2     |
|  68.3 ms    52 bpm    7.2h     97%      |
|  ^ vs avg   v vs avg  = avg   Normal   |
|                                         |
+-----------------------------------------+
|  RECOVERY TREND (7 DAYS)               |
|  [line chart with area fill]           |
|                                         |
+-----------------------------------------+
|  SLEEP BREAKDOWN                        |
|  [horizontal stacked bar]              |
|  Performance: 85%                       |
|  In bed: 11:14 PM -> 6:38 AM          |
|                                         |
+-----------------------------------------+
|  STRAIN BREAKDOWN                       |
|  [semicircle gauge with needle]        |
|  Strain zone: High                     |
|  Recommended: Moderate (recovery 72%)  |
|                                         |
+-----------------------------------------+
|  HISTORICAL COMPARISON                  |
|  vs Yesterday: Recovery ^5%, HRV v2ms  |
|  vs Last Week: Recovery ^8%, Sleep +0.5h|
|  7-day avg Recovery: 65%               |
|                                         |
+-----------------------------------------+
```

**Recovery Hero Section**:
- Recovery ring: 120pt diameter, 10pt stroke, same color/gradient logic and gap as dashboard ring but larger. Positioned: centered horizontally on screens <= 390pt width (stacked layout), or left-aligned at 20pt inset on screens > 390pt (side-by-side with text).
- Score inside ring: font `tempo.display`, recovery zone color.
- Right of ring (side-by-side) or below ring (stacked):
  - "Recovery" label: font `tempo.title3`, color `tempo.text.primary`.
  - Drill-sergeant quip: font `tempo.body`, color `tempo.text.secondary`, italic. See Section 11 for the full quip system.

Recovery quips (expanded view context):

| Recovery Range | Quip Pool (randomly select one) |
|---------------|--------------------------------|
| 90-100 | `"Go break something. In a good way."` / `"Peak condition. No excuses today."` / `"Your body said yes. Don't waste it."` |
| 67-89 | `"You're good to push it."` / `"Green means go. Get after it."` / `"Solid recovery. Make it count."` |
| 50-66 | `"Ease up or pay for it tomorrow."` / `"Yellow zone. Choose your battles."` / `"Moderate effort. Save the fireworks."` |
| 34-49 | `"Your body is waving a yellow flag."` / `"Sub-50. Train smart, not hard."` / `"Recovery debt is building. Pay attention."` |
| 0-33 | `"Sit down. Seriously."` / `"Red zone. Walk, stretch, nothing more."` / `"Your body needs a ceasefire."` |

**Metric Cards Row**: Four equally-spaced cards in a horizontal scroll on SE, or a 4-column grid if screen width >= 393pt. Each card:
- Background: `tempo.bg.card`, corner radius: `tempo.radius.inner`, padding: 10pt.
- Size: 80pt wide (fixed), height: flexible (typically ~70pt).
- Value: font `tempo.title3`, color `tempo.text.primary`.
- Label: font `tempo.caption2`, color `tempo.text.tertiary`.
- Comparison indicator: arrow symbol + `"vs avg"`. The average is the 7-day rolling average.
  - `^` (value > avg * 1.05): color `tempo.green` for HRV/Sleep, `tempo.red` for RHR
  - `v` (value < avg * 0.95): color `tempo.red` for HRV/Sleep, `tempo.green` for RHR
  - `=` (within 5%): color `tempo.text.tertiary`
  - For SpO2: show `"Normal"` if >= 95%, `"Low"` in `tempo.red` if < 95%

**Recovery Trend Chart (7 Days)**:
- Chart type: Line chart with filled area underneath (gradient from line color at 30% opacity to transparent at bottom).
- Chart height: 160pt. Full card width minus 28pt internal padding.
- X-axis: Days of the week abbreviated (`M`, `T`, `W`, `Th`, `F`, `Sa`, `Su`). Font: `tempo.caption2`, color `tempo.text.tertiary`.
- Y-axis: Hidden. But the chart area has horizontal dashed grid lines at 33% and 67% marks (mapping to recovery zone boundaries). Grid line color: `tempo.divider`, dash pattern [4, 4].
- Data points: Circles (6pt diameter) on the line, filled with the recovery zone color for that day.
- Line color: `tempo.text.primary`, 2pt stroke.
- Interaction: Tap and hold on the chart for 0.3s (long press) to activate scrubber. A vertical scrubber line (`tempo.accent`, 1pt) appears. As the user drags horizontally, a tooltip floats 8pt above the scrubber showing `"{day}: {score}%"`. Font: `tempo.caption1`, background: `tempo.bg.card`, shadow `tempo.shadow.elevated`, corner radius 6pt, padding 6pt. Release dismisses the scrubber with fade (0.15s).
- If fewer than 7 days of data: show available days only, left-aligned. Empty days are not plotted. A dashed line connects across gaps.
- Time range selector: Segmented control above the chart — `7D | 30D | 90D`. Default: `7D`. Font: `tempo.caption1`. Selected segment: `tempo.accent` background, white text, corner radius 6pt. Unselected: clear background, `tempo.text.secondary`. Changing selection: chart crossfades (0.2s) while new data loads. If data for the new range isn't cached, show a 20pt inline spinner for up to 2s.

**Sleep Breakdown**:
- Horizontal stacked bar chart showing sleep stages.
- Total bar width: full card width. Height: 24pt. Corner radius: 12pt.
- Segments (left to right): Deep (darkest), REM, Light, Awake.
  - Deep: `#5856D6` (system indigo)
  - REM: `#5AC8FA` (system teal)
  - Light: `#D1D1D6` (system gray 4)
  - Awake: `#FF9500` (system orange)
- Below the bar: Legend — each stage with a color dot (8pt circle), stage name, and duration (e.g., `"Deep  1.5h"`). Arranged as 2x2 grid. Font: `tempo.caption1`.
- `"Performance: 85%"`: font `tempo.callout`, color `tempo.text.primary`.
- `"In bed: 11:14 PM -> 6:38 AM"`: font `tempo.caption2`, color `tempo.text.secondary`. Time format: `h:mm a`.

**Strain Breakdown**:
- Strain gauge: A 180-degree arc (semicircle) with a needle indicator. Arc goes from green (left, 0) through yellow (middle, ~10) to red (right, 21).
- Arc diameter: 160pt, stroke 10pt.
- Needle: A 2pt-wide line from the center of the arc to the position corresponding to the current strain. Needle color: `tempo.text.primary`. A small circle (8pt) at the needle tip.
- Below arc: `"Strain zone: {zone}"` where zone = "Low" (0-9), "Moderate" (10-13), "High" (14-17), "Overreaching" (18-21).
- Recommendation: `"Recommended: {recommendation} (recovery {recovery}%)"`. Recommendation maps:
  - Recovery >= 80: `"Push it"`
  - Recovery 50-79: `"Moderate"`
  - Recovery < 50: `"Take it easy"`

**Historical Comparison**:
- Container: `tempo.bg.card`, corner radius `tempo.radius.card`, padding 14pt.
- Each row: `"vs {period}: {metric} {arrow}{delta}"`.
  - Arrow: `^` or `v`.
  - Delta: absolute change with unit (e.g., `"^5%"`, `"v2 ms"`, `"+0.5h"`).
  - Positive changes (recovery/sleep/HRV up, RHR down): `tempo.green`.
  - Negative changes: `tempo.red`.
  - Neutral: `tempo.text.secondary`.
- Font: `tempo.body`. Spacing between rows: 8pt.

---

### 4.3 Fuel Expanded View

**Screen title**: `"Fuel"`

**Layout** (scrollable):

**Calorie Hero Section**:
- Ring: 120pt diameter, 10pt stroke, `tempo.purple` fill, `.round` cap.
- Inside ring: `calories_consumed` formatted. Font: `tempo.display`.
- Right of ring: `"of {target} kcal"` — font `tempo.body`, color `tempo.text.secondary`.
- Quip below (drill-sergeant tone):

| Calorie Status | Quip Pool |
|---------------|-----------|
| < 50% of target | `"You running on fumes?"` / `"That's not enough to fuel a hamster."` / `"Eat. This isn't negotiable."` |
| 50-79% of target | `"Still got room for {remaining} kcal."` / `"Halfway there. Keep fueling."` |
| 80-100% of target | `"On track. Don't blow it at dinner."` / `"Dialed in. Keep it clean."` |
| 100-120% of target | `"Over by {overage}. Noted."` / `"Slight surplus. Not the end of the world."` |
| > 120% of target | `"That's a surplus, not a strategy."` / `"{overage} over. Tomorrow, tighten up."` |

**Macro Section**:
- Each macro gets a full-width row in a card container.
- Macro name: font `tempo.callout`, color `tempo.text.primary`.
- Progress bar: height 8pt, corner radius 4pt. Same colors as dashboard (Protein teal, Carbs yellow, Fat orange).
- Right of bar: `"{consumed}/{target}g"` — font `tempo.callout`.
- Below bar: `"{percent}% of calories"` — font `tempo.caption2`, color `tempo.text.tertiary`. Calculate as: `(macro_g * calories_per_gram / total_calories * 100)`. Protein: 4 cal/g, Carbs: 4 cal/g, Fat: 9 cal/g.
- Spacing between macros: 16pt.

**Meals Section**:
- Each meal is a row in a list-style card.
- Left: status icon. Logged: SF Symbol `checkmark.circle.fill`, `tempo.green`. Planned: SF Symbol `circle`, `tempo.text.tertiary`. Skipped: SF Symbol `xmark.circle.fill`, `tempo.red`.
- Meal name: font `tempo.body`, color `tempo.text.primary`.
- Time: font `tempo.caption1`, color `tempo.text.secondary`. Logged meals show actual time. Planned meals show `"(planned)"`.
- Calories: font `tempo.callout`, color `tempo.text.primary`. Planned meals show `"--"`.
- Row height: 48pt. Separator: 1pt hairline `tempo.divider`.
- Tapping a logged meal navigates to the meal detail (push onto nav stack).
- Tapping a planned meal opens the Log Meal flow.

**`[ + Log Meal ]` button**: Full width (minus insets), height 44pt, background `tempo.accent`, corner radius `tempo.radius.inner`, text `"+ Log Meal"` in white, font `tempo.callout`, centered. Tap opens the NutriTrack meal logging flow (presented as `.fullScreenCover`).

**Calorie Trend Chart (7 Days)**:
- Chart type: Vertical bar chart.
- Each bar: width 28pt, corner radius 4pt (top only), color `tempo.purple`.
- A horizontal dashed line at the target calorie level. Line color: `tempo.text.tertiary`, 1pt, dash pattern [4, 4].
- Bars that exceed the target: the portion above the line is `tempo.red`.
- X-axis: same day format as recovery chart.
- Interaction: tap a bar to show a tooltip with `"{day}: {calories} kcal"`.
- Time range selector: same segmented control as Body chart.

**Weekly Average Section**:
- Simple text block in a card.
- `"Calories: {avg}/day (target {target})"` — font `tempo.body`.
- `"Protein: {avg}g/day"` — font `tempo.body`.
- `"Compliance: {percent}%"` — calculated as days within 90-110% of calorie target, out of days with data. Font `tempo.body`, color: >= 80% `tempo.green`, 50-79% `tempo.yellow`, < 50% `tempo.red`.

---

### 4.4 Mind Expanded View

**Screen title**: `"Mind"`

**Progress Hero**:
- Study time: font `tempo.display`, color `tempo.text.primary`. Format: `"2h 15m"`.
- Target: `"/ 3h target"` — font `tempo.title3`, color `tempo.text.tertiary`. Same line, 4pt gap.
- Full-width progress bar: 8pt height, corner radius 4pt. Fill: `tempo.blue`. Track: `tempo.ring.track`.
- Percentage: right-aligned, same line as bar. Font: `tempo.callout`, color `tempo.text.secondary`.
- Quip:

| Progress | Quip Pool |
|---------|-----------|
| 0% | `"Zero minutes. The books miss you."` / `"Nothing logged. The clock is ticking."` |
| 1-49% | `"Not done yet. Back to the desk."` / `"Under half. Pick up the pace."` |
| 50-99% | `"Halfway doesn't pass exams."` / `"More than half. Keep going."` |
| 100% | `"Target hit. Respect."` / `"Full send. Well done."` |
| > 120% | `"Going extra. That's elite."` / `"Overtime. You're building something."` |

**Today's Sessions**:
- Each session row: icon (SF Symbol `book.fill`, `tempo.blue`), subject name (font `tempo.body`, color `tempo.text.primary`), duration right-aligned (font `tempo.callout`, color `tempo.text.secondary`).
- Second line: time range. Font `tempo.caption2`, color `tempo.text.tertiary`. Format: `h:mm a -- h:mm a`.
- Row height: 52pt. Separator: `tempo.divider`.
- If no sessions today: `"No study sessions yet"` centered, font `tempo.body`, color `tempo.text.tertiary`.

**`[ Start Study Session ]` button**: Full width, height 48pt, background `tempo.blue`, corner radius `tempo.radius.inner`. Icon: SF Symbol `play.fill`, 14pt, white. Text: `"Start Study Session"`, white, font `tempo.callout`. Tap starts the study timer (presented as `.fullScreenCover`).

**Upcoming Exams**:
- Each exam is a row. Left: colored circle (12pt).
  - <= 7 days: red circle, pulsing opacity animation (0.5 to 1.0, 1s sinusoidal loop).
  - 8-14 days: yellow circle, static.
  - > 14 days: gray circle, static.
- Exam name: font `tempo.body`, color `tempo.text.primary`.
- Date + countdown: font `tempo.caption1`, color `tempo.text.secondary`. Format: `"MMM d ({N} days)"`.
- Row height: 44pt.
- Tap on exam row: navigates to Exam Detail (push onto nav).

**`[ + Add Exam ]`**: Text button, font `tempo.callout`, color `tempo.blue`. Tap presents Add Exam sheet.

**Study Trend Chart**: Same pattern as Fuel's calorie trend — vertical bar chart, `tempo.blue` bars, dashed target line.
- Below chart: `"Weekly total: {Xh Ym}"` — font `tempo.callout`, color `tempo.text.primary`.
- Streak: `"{N}-day streak"` with flame icon — same formatting as dashboard streak badge, but font `tempo.callout`.

**Focus Breakdown**:
- Horizontal bar chart grouped by subject (from local study session data, aggregated over current week).
- Each row: subject name (font `tempo.body`), horizontal bar (height 8pt, color `tempo.blue` at varying opacities — darkest for highest time, lightest for lowest, range 40%-100% opacity), total time, percentage.
- Bars are proportional to each other (longest bar = full width).

---

### 4.5 Move Expanded View

**Screen title**: `"Move"`

**Workout Hero**:
- If completed: SF Symbol `checkmark.circle.fill` (20pt, `tempo.green`) + workout name. Font: `tempo.title2`, color `tempo.text.primary`.
  - Second line: duration + calories + avg HR. Font: `tempo.body`, color `tempo.text.secondary`. Separated by ` * ` (middle dot with spaces).
  - Quip: italic, `tempo.body`, `tempo.text.secondary`. Pool: `"Solid session. Now recover."` / `"Done and dusted."` / `"Checked off. Next one's waiting."` / `"Work in the bank."` — rotate randomly per day.
- If planned: workout name, font `tempo.title2`. Below: `"Planned. Tap to start."`, font `tempo.body`, `tempo.orange`.
- If rest day: `"Rest Day"`, font `tempo.title2`, color `tempo.text.secondary`. Quip: `"Growth happens in the recovery."`, italic.
- If none: `"No workout today"`, font `tempo.title2`, color `tempo.text.tertiary`. Below: `"[ + Plan Workout ]"` text button, `tempo.orange`.

**Today's Activity**:
- Two stat cards side-by-side, each: 50% width minus gaps. Background `tempo.bg.card`, corner radius `tempo.radius.inner`, padding 12pt, centered content.
  - Steps card: value font `tempo.title1`, `tempo.text.primary`. Label font `tempo.caption1`, `tempo.text.secondary`. Below label: `"/{target formatted}"` font `tempo.caption2`, `tempo.text.tertiary`.
  - Active Cal card: same layout.
- Below cards: full-width steps progress bar. Same as dashboard. 8pt height. Right-aligned percentage.
- Step pace projection: `"Step pace: On track for {projected}"`. Projected = `(current_steps / hours_elapsed_today) * 16` (assuming 16 waking hours, 6AM start). If before 8AM or hours_elapsed < 1: show `"Too early to project"` instead. Font: `tempo.caption1`, color `tempo.text.secondary`. If projected >= target: `tempo.green`. If projected < target * 0.8: `tempo.yellow`.

**Heart Rate Section**:

> **FEASIBILITY NOTE (Technical Feasibility Audit Section 1.5):** Live heart rate data requires Apple Watch. Without Apple Watch, iPhones have no wrist HR sensor. Whoop HR data arrives post-workout only (not in real-time). The display below adapts based on the user's hardware.

- **With Apple Watch:** `"Current: {hr} bpm"` — font `tempo.title3`, color `tempo.text.primary`. If no recent HR sample (> 10 min old), show `"Last: {hr} bpm ({time ago})"` in `tempo.text.secondary`.
- **Whoop only (no Apple Watch):** Show `"Last: {hr} bpm ({time ago})"` from the most recent Whoop sync. During workouts, show `"HR will update after Whoop syncs"` in `tempo.text.tertiary`. Post-workout, populate retroactively from Whoop API data.
- **No wearable:** Show `"No heart rate data. Connect Apple Watch or Whoop."` in `tempo.text.tertiary`.
- Chart: Line chart of today's HR data from HealthKit (Apple Watch) or Whoop API (post-sync).
  - X-axis: hours (12 AM to current time). Font: `tempo.caption2`.
  - Y-axis: bpm range. Auto-scaled with 10bpm padding.
  - Line: 1.5pt, `tempo.red`.
  - Area fill: gradient from `tempo.red` at 15% opacity to transparent.
  - Workout periods: highlighted with a translucent `tempo.orange` rectangle behind the line during workout time ranges.
  - Interaction: same scrubber as recovery chart.
  - If Whoop-only: HR data may have gaps between syncs. Show dashed line segments for interpolated periods.
- `"Today's range: {min} -- {max} bpm"` — font `tempo.caption2`, color `tempo.text.secondary`.

**Workout History**:
- List of workouts from the past 7 days (from HealthKit `HKWorkout` queries), sorted most recent first.
- Each row: day abbreviation (font `tempo.caption1`, `tempo.text.tertiary`, 36pt fixed width), workout name (font `tempo.body`, `tempo.text.primary`), duration + calories right-aligned (font `tempo.caption1`, `tempo.text.secondary`).
- Row height: 44pt. Separator: `tempo.divider`.
- If no workouts in 7 days: `"No workouts recorded this week."`, centered, `tempo.text.tertiary`.

**Weekly Volume Chart**:
- Vertical bar chart of daily active calories, `tempo.orange` bars. Same style as other bar charts.
- Below: `"Total: {cal} cal * {N} workouts"` — font `tempo.callout`.
- `"vs last week: {+/-percent}%"` — font `tempo.caption1`. Positive: `tempo.green`. Negative: `tempo.red`.

**`[ Start Workout ]` button**: Same style as Log Meal button but `tempo.orange` background. Icon: `play.fill`. Tap opens Workout view (`.fullScreenCover`).

---

## 5. Weekly Report View

### 5.1 Access

- **Primary access**: A push notification sent every Sunday at 8:00 PM local time: `"Your weekly report is ready. How'd you do?"`. Tapping the notification deep-links to the Weekly Report view (see Section 14 for deep-link behavior).
- **Secondary access**: A `"View Weekly Report"` button in the Settings or Profile screen. Also accessible by tapping the date in the Header Bar (Section 3.2) — this opens a date picker. Selecting a past week navigates to that week's report. Tapping `"This Week"` opens the current report.
- **Navigation**: Pushed onto the `NavigationStack` from the dashboard. Back button returns to dashboard.

### 5.2 Layout

```
+-----------------------------------------+
| < Weekly Report                        |
| Mar 18 -- Mar 24, 2026                |
+-----------------------------------------+
|                                         |
|  OVERALL SCORE                          |
|        +----------+                     |
|        |    74    |                     |
|        +----------+                     |
|   "Solid week. Room to grow."          |
|                                         |
|  +-------------------+                  |
|  | Body: 72  Fuel: 78 |                 |
|  | Mind: 68  Move: 78  |                |
|  +-------------------+                  |
|                                         |
+-----------------------------------------+
|  BODY                                   |
|  Avg Recovery: 68%  (^4% vs last week) |
|  Avg Sleep: 7.1h    Avg HRV: 65ms     |
|  [7-day recovery line chart]           |
|  Best day: Wednesday (92%)             |
|  Worst day: Friday (41%)              |
|                                         |
+-----------------------------------------+
|  FUEL                                   |
|  Avg Calories: 2,180/day              |
|  Compliance: 85% (6/7 days on target) |
|  Protein avg: 158g  Target: 180g      |
|  [7-day calorie bar chart]            |
|  ! Protein was under target 5/7 days  |
|                                         |
+-----------------------------------------+
|  MIND                                   |
|  Total study: 14h 30m                  |
|  Daily avg: 2h 4m  Target: 3h         |
|  Streak: 12 days                       |
|  [7-day study bar chart]              |
|  Top subject: Calculus II (42%)        |
|                                         |
+-----------------------------------------+
|  MOVE                                   |
|  Workouts: 4/5 planned                 |
|  Total active cal: 1,257              |
|  Avg steps: 9,200/day                 |
|  [7-day active cal bar chart]         |
|  vs last week: +12% volume            |
|                                         |
+-----------------------------------------+
|  AI INSIGHTS                            |
|  [insight cards - see Section 10]      |
|                                         |
+-----------------------------------------+
|  PATTERNS DETECTED                      |
|  [pattern cards]                        |
|                                         |
+-----------------------------------------+
|  [ Share Report ]                       |
|                                         |
|  <- Previous Week    Next Week ->      |
|                                         |
+-----------------------------------------+
```

### 5.3 Overall Score Section

- Score ring: 100pt, same style as daily score ring. The value is the average of all 7 daily scores for the week. If fewer than 7 days have scores, average the available days and show `"({N}/7 days)"` below.
- Below: weekly quip.

| Avg Score | Quip |
|-----------|-------|
| 90-100 | `"Dominant week. Keep the standard."` |
| 75-89 | `"Solid week. Room to grow."` |
| 60-74 | `"Average. You know you're better than this."` |
| 40-59 | `"Below the line. Time to lock in."` |
| 0-39 | `"Rough week. Reset starts now."` |

- Quadrant breakdown: Four labeled scores in a 2x2 mini-grid. Each: quadrant name (font `tempo.caption1`, color `tempo.text.secondary`) + score (font `tempo.title3`, recovery-zone-color logic applied). Card background: `tempo.bg.card`, corner radius `tempo.radius.inner`, padding 10pt. Grid gap: 10pt.

### 5.4 Per-Quadrant Sections

Each section follows this structure:
1. **Section header**: quadrant name, font `tempo.title2`, color `tempo.text.primary`.
2. **Key metrics**: 2-3 lines of summary stats with comparison to last week. Font `tempo.body`. Delta arrows colored green/red.
3. **Chart**: 7-day trend chart (same chart style as the expanded views). Height: 120pt.
4. **Highlight**: A single-line callout — best day, worst stat, notable achievement. Font `tempo.callout`, color `tempo.text.secondary`.
5. **Warning (if applicable)**: A `!` prefixed line if a metric is consistently below target. Font `tempo.callout`, color `tempo.yellow`.

Section container: no card background — content flows directly in the scroll view with `tempo.divider` hairlines between sections.

### 5.5 AI Insights Section

- Section header: `"AI INSIGHTS"`, font `tempo.title2`.
- Container: `tempo.bg.card`, corner radius `tempo.radius.card`, padding 0 (individual insight cards handle padding).
- Each insight: 14pt padding, separated by 1pt `tempo.divider` hairlines.
  - Lightbulb icon: SF Symbol `lightbulb.fill`, 14pt, `tempo.yellow`. Top-left.
  - Text: font `tempo.body`, color `tempo.text.primary`. Maximum 3 lines.
  - Insights are generated by the AI Insights Engine (Section 10). 2-4 insights per weekly report.
- **Expandable insights**: Each insight card has a `chevron.down` icon (12pt, `tempo.text.tertiary`) at the right. Tapping the card expands it to show a 1-2 sentence explanation below the insight. The expansion is animated with `tempo.anim.standard`. The chevron rotates 180 degrees to point up.
- **Dismissible**: Swipe left on an insight to dismiss it (for this report only). A red `trash` icon appears on swipe. Dismissed insights are stored so they don't reappear.

### 5.6 Patterns Detected Section

- Section header: `"PATTERNS DETECTED"`, font `tempo.title2`.
- Each pattern is a card:
  - Pattern statement: `"{trigger} -> {outcome}"`. Font `tempo.callout`, color `tempo.text.primary`. Bold the trigger and outcome.
  - Stats: `"{correlation}% correlation * {N} occurrences"`. Font `tempo.caption2`, color `tempo.text.secondary`.
  - Card: `tempo.bg.card`, corner radius `tempo.radius.inner`, padding 12pt.
  - Tap: navigates to Pattern detail in Section 6.

### 5.7 Share Functionality

**`[ Share Report ]` button**: Full width, height 44pt, background `tempo.accent`, corner radius `tempo.radius.inner`. Text: `"Share Report"`, white, font `tempo.callout`.

On tap:
1. Generate a summary image: a 1080x1920pt (9:16 aspect) image rendered using SwiftUI's `ImageRenderer`.
   - Background: `tempo.bg.primary` (dark mode forced for share images — always dark).
   - Content: Overall score ring + 4 quadrant scores + top 2 key stats per quadrant + top AI insight.
   - Tempo logo/watermark at bottom: `"Tempo"` in `tempo.overline`, `tempo.text.tertiary`.
2. Present `UIActivityViewController` with the generated image and a text summary: `"My Tempo week: {score}/100 -- Body {body_score}, Fuel {fuel_score}, Mind {mind_score}, Move {move_score}"`.

### 5.8 Week Navigation

- `"<- Previous Week"` and `"Next Week ->"`: text buttons at the bottom.
- Font: `tempo.callout`, color: `tempo.accent`.
- `"Next Week ->"` is disabled (grayed out, `tempo.text.tertiary`) if the current report is for the current week.
- Tapping week navigation triggers a horizontal slide transition: previous slides right-to-left, next slides left-to-right. Duration: `tempo.anim.standard`.

---

## 6. Pattern / Correlation View

### 6.1 Access

- Tapping the Quick Insights Banner (Section 3.6) from the dashboard.
- Tapping a pattern card in the Weekly Report.
- From the dashboard header: long-press the daily score ring for 0.5s -> context menu -> `"View Patterns"`.

### 6.2 Screen Layout

**Navigation**: Pushed onto nav stack. Title: `"Patterns"`.

```
+-----------------------------------------+
| < Patterns                             |
+-----------------------------------------+
|                                         |
| [  7D  |  30D  |  90D  |  ALL  ]       |
|                                         |
+-----------------------------------------+
|  STRONG CORRELATIONS                    |
|  [scatter plot cards]                  |
|                                         |
+-----------------------------------------+
|  BEHAVIORAL PATTERNS                    |
|  [pattern cards with bullet outcomes]  |
|                                         |
+-----------------------------------------+
|  RECOMMENDATIONS                        |
|  [numbered actionable items]           |
|                                         |
+-----------------------------------------+
```

### 6.3 Time Range Selector

- Segmented control at top: `7D | 30D | 90D | ALL`.
- Same style as chart time range selectors. Default: `30D`.
- Changing the time range re-calculates all correlations and patterns. Show a brief loading spinner (inline, 20pt, `tempo.text.tertiary`) while computing. Timeout: 5s. If computation takes > 5s, show cached results for the closest available range.

### 6.4 Strong Correlations Section

**Section header**: `"STRONG CORRELATIONS"` — font `tempo.title2`.

Only show correlations with `|r| >= 0.5` (moderate to strong). Sort by `|r|` descending. Maximum 5 displayed.

**Correlation Pairs to Compute**:

| Variable A | Variable B | Expected Direction |
|-----------|-----------|-------------------|
| sleep_hours | next-day recovery_score | Positive |
| sleep_hours | study_minutes (same day) | Positive |
| recovery_score | study_minutes (same day) | Positive |
| recovery_score | workout_completed (bool to 0/1) | Positive |
| strain | next-day recovery_score | Negative |
| study_minutes | non_negotiables_completion_pct | Positive |
| calories_consumed_pct_of_target | next-day recovery_score | Positive |
| workout_completed | study_minutes (same day) | Positive |
| sleep_hours | calories_consumed | Positive |
| recovery_score | steps | Positive |

**Each Correlation Card**:
- Card: `tempo.bg.card`, corner radius `tempo.radius.card`, padding 14pt.
- Title: `"{Variable A} vs {Variable B}"`. Font: `tempo.callout`, color `tempo.text.primary`.
- Chart: Scatter plot, 160pt height, full card width.
  - Each data point: 6pt circle, color `tempo.accent` at 60% opacity.
  - Best-fit line: 1.5pt dashed line, color `tempo.text.secondary`.
  - X-axis: Variable A. Y-axis: Variable B. Axis labels: font `tempo.caption2`, color `tempo.text.tertiary`.
  - Interaction: Tap a data point for 0.3s (long press) -> tooltip shows the date and both values.
- `"r = {value} * {strength} {direction}"`:
  - Value: Pearson correlation coefficient, 2 decimal places.
  - Strength: `"Strong"` if |r| >= 0.7, `"Moderate"` if |r| >= 0.5.
  - Direction: `"positive"` or `"negative"`.
  - Font: `tempo.caption1`, color: |r| >= 0.7 ? `tempo.green` : `tempo.text.secondary`.
- Human-readable insight: 1 line, font `tempo.body`, italic, `tempo.text.secondary`.

### 6.5 Behavioral Patterns Section

**Section header**: `"BEHAVIORAL PATTERNS"` — font `tempo.title2`.

**Pattern Detection Algorithm** (rule-based, computed locally):

For each trigger condition, scan all days in the selected time range where the condition is true. Then compute the average of outcome metrics for those days vs. all other days. If the difference is >= 20% (relative), it is a pattern.

**Trigger Conditions to Check**:
- `sleep_hours < 6.5`
- `sleep_hours >= 8.0`
- `recovery_score > 80`
- `recovery_score < 40`
- `workout_completed == true`
- `study_minutes > study_target`
- `calories_consumed > calories_target * 1.1`
- `calories_consumed < calories_target * 0.7`

**Outcome Metrics to Check**:
- `breakfast_skipped` (first meal logged after 11 AM or no meal before noon)
- `study_minutes` (same day)
- `next_day_recovery_score`
- `non_negotiables_completion_pct` (same day)
- `calories_consumed_pct_of_target` (same day)
- `steps` (same day)

**Each Pattern Card**:
- Card: `tempo.bg.card`, corner radius `tempo.radius.card`, padding 14pt.
- Trigger: `"When {condition}:"` — font `tempo.callout`, color `tempo.text.primary`, bold.
- Outcomes: Bulleted list. Each bullet: `"* {outcome description}"`. Font: `tempo.body`, color `tempo.text.primary`.
  - Percentage differences colored: positive outcomes `tempo.green`, negative outcomes `tempo.red`.
- Occurrence count: `"Occurrences: {N} in {range} days"`. Font: `tempo.caption2`, color `tempo.text.tertiary`.
- Minimum 3 occurrences required to show a pattern. Otherwise, suppress it.

### 6.6 Recommendations Section

**Section header**: `"RECOMMENDATIONS"` — font `tempo.title2`.

**Content**: Numbered list of 2-4 actionable recommendations derived from the top patterns and correlations. Each recommendation:
- Number: font `tempo.title3`, `tempo.accent`.
- Title: 1 line, font `tempo.callout`, color `tempo.text.primary`, bold.
- Impact line: `"Impact: {description}"`. Font `tempo.body`, color `tempo.text.secondary`.
- Spacing between items: 16pt.

Recommendations are generated by ranking patterns by impact magnitude (largest percentage difference first) and converting triggers into actionable advice. The wording is direct and imperative: `"Prioritize 7+ hours sleep"` not `"Consider sleeping more"`.

---

## 7. Daily Timeline View

### 7.1 Access

- Long-press the date in the Header Bar for 0.5s -> context menu -> `"View Timeline"`.
- Also accessible from the expanded view of any quadrant: a `"See in Timeline"` link at the bottom of each section.

### 7.2 Screen Layout

**Navigation**: Pushed onto nav stack. Title: `"Today"` (or the selected date if viewing a past day).

```
+-----------------------------------------+
| < Today                     Mar 24     |
+-----------------------------------------+
|                                         |
|  6:38 AM  [sun] Woke up               |
|           Recovery: 72% * Sleep: 7.2h  |
|           |                             |
|  7:15 AM  [dumbbell] Morning Workout   |
|           Upper Body Push * 52 min     |
|           342 cal * Avg HR 145         |
|           |                             |
|  8:15 AM  [fork] Breakfast             |
|           Oats, banana, protein shake  |
|           480 kcal * P:35g C:62g F:12g |
|           |                             |
|  9:00 AM  [book] Study: Calculus II    |
|           1h 30m                       |
|           |                             |
| 10:30 AM  [check] Non-neg: Workout    |
|           |                             |
| - - - - NOW (10:45 AM) - - - - - -    |
|           |                             |
| 12:30 PM  [fork] Lunch (planned)      |
|           |                             |
|  2:00 PM  [book] Study: Physics       |
|           |                             |
|  6:30 PM  [fork] Dinner (planned)     |
|           |                             |
| 10:00 PM  [moon] Target bedtime       |
|                                         |
+-----------------------------------------+
```

### 7.3 Timeline Structure

- The view is a `ScrollView` containing a vertical list of time-stamped events.
- Left column: time (font `tempo.caption1`, color `tempo.text.tertiary`, 60pt fixed width, right-aligned).
- Vertical line: 2pt wide, color `tempo.divider`, runs from top event to bottom event, positioned 8pt right of the time column.
- Event dot: 10pt circle on the vertical line. Past events: filled with category color. Future events: `tempo.ring.track` fill with category color stroke (1.5pt).
- Right column: event details (padding 12pt left of the vertical line).

**Event Types and Icons**:

| Event Type | Icon (SF Symbol) | Color | Source |
|-----------|-----------------|-------|--------|
| Wake up | `sunrise.fill` | `tempo.body.green` | Whoop sleep end time |
| Workout | `dumbbell.fill` | `tempo.orange` | HealthKit workout |
| Meal (logged) | `fork.knife` | `tempo.purple` | NutriTrack |
| Meal (planned) | `fork.knife` (outlined variant) | `tempo.text.tertiary` | NutriTrack |
| Study session | `book.fill` | `tempo.blue` | Local |
| Non-negotiable | `checkmark.circle.fill` | `tempo.green` | Local |
| Target bedtime | `moon.fill` | `tempo.body.green` | Computed from sleep target |

**Event Detail Layout**:
- Line 1: Icon (14pt) + event name. Font: `tempo.body`, color `tempo.text.primary` for past events, `tempo.text.tertiary` for future events.
- Line 2+: Additional details. Font: `tempo.caption1`, color `tempo.text.secondary` for past, `tempo.text.tertiary` for future.
- Past events: normal opacity (1.0). Future events: 0.6 opacity on all elements.

**"NOW" Divider**:
- A horizontal dashed line spanning the full width. Dash pattern: [6, 4]. Color: `tempo.accent`.
- Label: `"NOW ({time})"` centered on the line. Font: `tempo.caption1`, color `tempo.accent`, bold. Background: `tempo.bg.primary` (to create a break in the dashed line behind the text). Padding: 4pt horizontal around the text.
- The scroll view auto-scrolls to center the NOW divider on appear with `tempo.anim.standard`.
- If it is currently before the first event or after the last event, the NOW marker appears at the corresponding edge.
- The NOW time updates every 60s.

**Spacing**: 24pt between events. The vertical connecting line fills the gap.

**Tap interactions**:
- Tap a meal event: navigate to meal detail.
- Tap a workout event: navigate to workout detail.
- Tap a study session event: navigate to study session detail.
- Tap a planned meal: open Log Meal flow.
- Tap a non-negotiable: toggle its completion (same animation as dashboard).

**Empty state** (first day, no events): `"Your day is a blank canvas. Start building."` — centered, font `tempo.body`, `tempo.text.tertiary`.

---

## 8. Quick Actions

### 8.1 Access Methods

Quick actions are available from two places:

**Method 1: Floating Action Button (FAB)**
- Position: Bottom-right corner, 20pt from right edge, 20pt from bottom safe area.
- Size: 56pt circle.
- Background: `tempo.accent`.
- Icon: SF Symbol `plus`, 24pt, white.
- Shadow: `tempo.shadow.elevated`.
- The FAB is visible at all times on the dashboard (overlays scroll content). It fades to 40% opacity when the user is actively scrolling (triggered by `ScrollView` `onScrollPhaseChange` or gesture detection) and returns to 100% opacity 0.5s after scrolling stops, using `tempo.anim.fade`.

**Method 2: Haptic long-press on a quadrant card**
- Long-pressing (0.5s threshold) a quadrant card presents a context menu with actions relevant to that quadrant. A haptic (`UIImpactFeedbackGenerator`, `.medium`) fires when the menu appears.

### 8.2 FAB Expansion

Tapping the FAB triggers an expansion animation:

1. The `+` icon rotates 45 degrees to become an `x` (close) icon. Duration: 0.2s, easeOut.
2. Four action buttons fan out above the FAB in a vertical stack (each 60pt above the previous). Each button animates from the FAB's center position to its final position with a stagger of 0.06s. Duration per button: `tempo.anim.standard`.
3. A semi-transparent overlay (`#000000` at 40% opacity) covers the rest of the screen behind the action buttons. Fades in over 0.2s. Tap the overlay or the `x` to close.

**Action Buttons** (from bottom to top):

| Order | Label | Icon (SF Symbol) | Color | Action |
|-------|-------|-----------------|-------|--------|
| 1 (closest to FAB) | Log Meal | `fork.knife` | `tempo.purple` | Present NutriTrack Log Meal as `.sheet` |
| 2 | Start Workout | `figure.run` | `tempo.orange` | Present Start Workout as `.fullScreenCover` |
| 3 | Study Timer | `book.fill` | `tempo.blue` | Present Study Timer as `.fullScreenCover` |
| 4 (farthest from FAB) | Check Non-Neg | `checkmark.circle` | `tempo.green` | Present Non-Negotiable checklist as `.sheet(detents: [.medium])` |

**Each action button**:
- Size: 44pt circle.
- Background: the specified color.
- Icon: white, 18pt.
- Label: appears to the left of the circle, 8pt gap. Font: `tempo.caption1`, color: white. Background: `#000000` at 60%, corner radius 4pt, padding 4pt horizontal 8pt vertical. The label fades in 0.1s after the button reaches its position.

### 8.3 Quadrant Long-Press Context Menus

**Body quadrant long-press menu**:
- `"View Details"` — navigates to Body expanded view
- `"Sync Whoop"` — forces a Whoop API refresh
- `"Open Whoop App"` — deep-links to Whoop app (`whoop://`)

**Fuel quadrant long-press menu**:
- `"View Details"` — navigates to Fuel expanded view
- `"Log Meal"` — presents Log Meal flow
- `"Quick Add Calories"` — presents a simple number input sheet for quick calorie logging

**Mind quadrant long-press menu**:
- `"View Details"` — navigates to Mind expanded view
- `"Start Study Timer"` — starts study timer
- `"Add Exam"` — presents Add Exam sheet

**Move quadrant long-press menu**:
- `"View Details"` — navigates to Move expanded view
- `"Start Workout"` — starts workout
- `"Log Steps Manually"` — presents manual step entry

Context menu style: Use SwiftUI `.contextMenu` modifier. Native iOS context menu with haptic, blur background, and preview.

---

## 9. Widget Specifications

### 9.1 Small Widget (Pixel-Perfect Layout)

**Dimensions by device**:

| Device | Widget Size | Content Inset | Usable Area |
|--------|-----------|--------------|-------------|
| iPhone SE | 148x148pt | 11pt all sides | 126x126pt |
| iPhone 15 | 158x158pt | 11pt all sides | 136x136pt |
| iPhone 15 Pro Max | 170x170pt | 11pt all sides | 148x148pt |
| iPhone 16 Pro Max | 170x170pt | 11pt all sides | 148x148pt |

**Content**: Daily score ring + two most important metrics.

```
+---------------------+
| TEMPO               |
|                     |
|    +----+           |
|    | 78 |           |
|    +----+           |
|                     |
| [G] 72% rec  7.2h  |
+---------------------+
```

**Exact layout specification**:
- **Top-left**: `"TEMPO"` — font: system 10pt bold, `tempo.text.secondary`. Uppercase, tracking 1.5pt. Position: 0pt from top-left of usable area.
- **Center**: Score ring:
  - Diameter: 52pt
  - Stroke: 4pt
  - Ring style: same gradient as dashboard ring but simplified (solid color, no gradient, to save widget rendering budget)
  - Score number: system 20pt bold, centered in ring
  - Position: centered horizontally in usable area, vertical center offset -6pt (slightly above true center to leave room for bottom metrics)
- **Bottom row**: 8pt from bottom of usable area. Two metrics, evenly split:
  - Left metric: Recovery zone color dot (6pt circle, 2pt from left edge) + 4pt gap + recovery percentage (system 11pt medium). E.g., `"72% rec"`.
  - Right metric: Sleep hours (system 11pt medium) + 4pt gap + moon icon (SF Symbol `moon.fill`, 8pt, `tempo.text.secondary`). E.g., `"7.2h"`. Right-aligned.

**Data priority** (when not all data is available):
1. Always show daily score if available
2. Recovery score is the first metric (left)
3. Sleep hours is the second metric (right)
4. If recovery unavailable: show steps instead (`"8.4k steps"`)
5. If sleep unavailable: show study time (`"2h 15m study"`)

**States**:
- Loading: `"..."` in place of score. Metrics show `"--"`.
- No data: `"Open Tempo"` centered, system 13pt medium, `tempo.text.tertiary`.
- Offline with cached data: show cached data as normal. No stale indicator in small widget (too cluttered).

**Tap**: Deep-links to dashboard (`tempo://dashboard`).

**Background**: `tempo.bg.card` (adapts to light/dark mode). No shadow (widgets don't support custom shadows).

**Update frequency**: Every 15 minutes via `TimelineProvider`. In the `getTimeline` method, return entries at 15-minute intervals for the next hour (4 entries). Each entry reads from the shared app group's cached data — NO network calls in the widget process.

**Placeholder content** (shown before any data loads):
- Ring track only (no fill), `"--"` inside
- Metrics: `"--"` for both
- Background: `tempo.bg.card`

### 9.2 Medium Widget (Pixel-Perfect Layout)

**Dimensions by device**:

| Device | Widget Size | Content Inset | Usable Area |
|--------|-----------|--------------|-------------|
| iPhone SE | 321x148pt | 11pt all sides | 299x126pt |
| iPhone 15 | 338x158pt | 11pt all sides | 316x136pt |
| iPhone 15 Pro Max | 364x170pt | 11pt all sides | 342x148pt |

**Content**: Daily score + all 4 quadrant summaries.

```
+--------------------------------------------+
| TEMPO                           Mon Mar 24 |
|                                            |
|  +----+  BODY 72%   |  FUEL 1842/2400     |
|  | 78 |  Sleep 7.2h |  P:142 C:205 F:52   |
|  +----+  -----------|-------------------   |
|          MIND 2h15m |  MOVE [v] Done       |
|          12d streak |  8,432 steps         |
+--------------------------------------------+
```

**Exact layout**:
- **Top row** (8pt from top): `"TEMPO"` left-aligned (system 10pt bold, `tempo.text.secondary`), date right-aligned (system 10pt, `tempo.text.tertiary`), format: `"EEE MMM d"`.
- **Left column** (width: 30% of usable area, vertically centered): Score ring, 48pt diameter, 4pt stroke. Number: system 18pt bold.
- **Right column** (width: 70%, split into 2x2 grid):
  - Dividers: 1pt hairlines `tempo.divider`, horizontal center + vertical center of the right column.
  - Each quadrant cell: padded 6pt from dividers and edges.
  - Quadrant name: system 9pt bold, quadrant accent color (e.g., BODY in recovery zone color, FUEL in `tempo.purple`, MIND in `tempo.blue`, MOVE in `tempo.orange`).
  - Metric line 1: system 11pt medium, `tempo.text.primary`. Show the most important metric.
  - Metric line 2 (if space): system 10pt, `tempo.text.secondary`. Show secondary info.

**Content per quadrant cell**:
- BODY: `"72%"` (recovery), `"Sleep 7.2h"` (second line)
- FUEL: `"1842/2400"` (calories), `"P:142 C:205 F:52"` (macros abbreviated)
- MIND: `"2h15m"` (study time), `"12d streak"` (if streak >= 2, else exam countdown)
- MOVE: workout status icon + text, step count

**Tap regions**: Divide the right two-thirds into four quadrant tap areas. Each links to the corresponding expanded view:
- Top-left cell: `tempo://dashboard/body`
- Top-right cell: `tempo://dashboard/fuel`
- Bottom-left cell: `tempo://dashboard/mind`
- Bottom-right cell: `tempo://dashboard/move`
- Score ring tap: `tempo://dashboard` (main dashboard)

**States**: Same as small widget. If a source is disconnected, its quadrant shows `"--"` for values but still shows the label.

### 9.3 Large Widget (Pixel-Perfect Layout)

**Dimensions by device**:

| Device | Widget Size | Content Inset | Usable Area |
|--------|-----------|--------------|-------------|
| iPhone SE | 321x324pt | 11pt all sides | 299x302pt |
| iPhone 15 | 338x354pt | 11pt all sides | 316x332pt |
| iPhone 15 Pro Max | 364x382pt | 11pt all sides | 342x360pt |

**Content**: Full dashboard summary — score, all quadrants with more detail, non-negotiable progress.

```
+--------------------------------------------+
| TEMPO                           Mon Mar 24 |
|                                            |
|           +------+                         |
|           |  78  |  Daily Score             |
|           +------+                         |
|                                            |
|  +------------------+ +----------------+   |
|  | BODY             | | FUEL           |   |
|  | [G] 72% Recovery | | 1,842/2,400   |   |
|  | HRV 68.3  RHR 52 | | P:142 C:205   |   |
|  | Sleep 7.2h       | | F:52  2/4 meal|   |
|  +------------------+ +----------------+   |
|  +------------------+ +----------------+   |
|  | MIND             | | MOVE           |   |
|  | 2h 15m / 3h     | | [v] Done       |   |
|  | Calc II: 6 days  | | 8,432 steps   |   |
|  | [flame] 12d      | | 342 active cal|   |
|  +------------------+ +----------------+   |
|                                            |
|  3/5 non-negotiables =========---------    |
|                                            |
+--------------------------------------------+
```

**Exact layout**:
- Header: same as medium. 8pt from top.
- Score ring: 56pt diameter, 5pt stroke, centered. `"Daily Score"` label below in system 10pt. Combined height ~76pt.
- Quadrant cards: 2x2 grid, 8pt gap between cards. Each card:
  - Width: `(usable_width - 8pt gap) / 2`
  - Height: flexible, typically ~72pt
  - Background: `Color(.systemFill)` (quaternary system fill — slightly elevated from widget background)
  - Corner radius: 8pt
  - Internal padding: 6pt
  - Quadrant name: system 9pt bold, quadrant accent color
  - 3 metric lines: system 10pt, truncated with `.lineLimit(1)`
- Non-negotiable bar at bottom: 8pt from bottom of usable area.
  - `"3/5 non-negotiables"` — system 10pt medium, `tempo.text.primary`
  - Progress bar: full width, 4pt height, 2pt radius. Track: `tempo.ring.track`. Fill: `tempo.accent`. If all complete: fill = `tempo.green`.

**Tap**: Same deep-linking as medium widget. Score area links to dashboard. Each quadrant card links to its expanded view. Non-negotiable bar links to `tempo://dashboard` (scrolled to non-negotiables — handled by the app).

### 9.4 Lock Screen Widgets

**Circular (Lock Screen)**:
- Size: 50pt diameter
- Content: Score number `"78"` centered, system 18pt bold, white
- Ring: rendered around the circular widget boundary, 3pt stroke, using the widget's `AccessoryWidgetBackground` for the track
- Fill: clockwise from top, colored per score zone

**Rectangular (Lock Screen)**:
- Size: 157x36pt (iPhone 15)
- Content: `"Tempo: 78 * 72% rec * 7.2h sleep"` — single line, system 12pt medium
- Truncation: if text overflows, drop sleep data first, then recovery detail

**Inline (Lock Screen)**:
- Content: `"Tempo 78 | Rec 72%"` — text only, system 12pt
- If no score: `"Tempo --"`

All lock screen widgets update every 15 minutes. Lock screen widgets use `AccessoryWidgetBackground` for automatic system styling.

### 9.5 Widget Deep Link URL Scheme

| URL | Destination | App Behavior on Open |
|-----|-------------|---------------------|
| `tempo://dashboard` | Main dashboard | Scroll to top, refresh data |
| `tempo://dashboard/body` | Body expanded view | Push Body view onto nav stack |
| `tempo://dashboard/fuel` | Fuel expanded view | Push Fuel view onto nav stack |
| `tempo://dashboard/mind` | Mind expanded view | Push Mind view onto nav stack |
| `tempo://dashboard/move` | Move expanded view | Push Move view onto nav stack |
| `tempo://dashboard/report` | Weekly report | Push current week report |
| `tempo://dashboard/timeline` | Daily timeline | Push today's timeline |
| `tempo://action/log-meal` | Log Meal flow | Present as `.sheet` over dashboard |
| `tempo://action/start-workout` | Start Workout flow | Present as `.fullScreenCover` |
| `tempo://action/study-timer` | Study Timer | Present as `.fullScreenCover` |

### 9.6 Widget Timeline Provider Logic

```swift
struct DashboardTimelineProvider: TimelineProvider {
    // Placeholder: shown in widget gallery and before first data
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(
            date: Date(),
            score: nil,
            recovery: nil,
            sleep: nil,
            calories: nil,
            calorieTarget: nil,
            studyMinutes: nil,
            studyTarget: nil,
            steps: nil,
            workoutStatus: nil,
            nonNegCompleted: 0,
            nonNegTotal: 0,
            isPlaceholder: true
        )
    }

    // Snapshot: shown in widget gallery preview
    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        // Return realistic sample data
        completion(DashboardEntry(
            date: Date(),
            score: 78,
            recovery: 72,
            sleep: 7.2,
            calories: 1842,
            calorieTarget: 2400,
            studyMinutes: 135,
            studyTarget: 180,
            steps: 8432,
            workoutStatus: .completed,
            nonNegCompleted: 3,
            nonNegTotal: 5,
            isPlaceholder: false
        ))
    }

    // Timeline: return entries for the next hour at 15-min intervals
    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let currentDate = Date()
        let data = SharedDataStore.readFromAppGroup() // Read cached data from shared container

        var entries: [DashboardEntry] = []
        for minuteOffset in stride(from: 0, through: 45, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            entries.append(DashboardEntry(date: entryDate, /* ... from cached data ... */))
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }
}
```

The widget NEVER makes network calls. All data comes from the shared app group container that the main app writes to after each sync.

---

## 10. AI Insights Engine

### 10.1 Overview

The AI Insights Engine uses Claude API to generate personalized insights from the user's cross-domain data. Insights appear in the Weekly Report (Section 5.5), the Quick Insights Banner (Section 3.6), and the Patterns view (Section 6).

### 10.2 Data Sent to Claude

The following data is compiled into a structured payload and sent to the backend, which forwards it to Claude API. **No raw timestamps or personally identifiable information beyond first name is sent.**

```json
{
  "user_context": {
    "first_name": "Nicola",
    "goals": ["muscle_gain", "exam_prep"],
    "active_days": 47
  },
  "week_summary": {
    "dates": "2026-03-18 to 2026-03-24",
    "daily_scores": [72, 68, 85, 74, 61, 78, 80],
    "body": {
      "recovery_scores": [65, 58, 92, 72, 41, 68, 82],
      "sleep_hours": [7.2, 6.1, 8.3, 7.0, 5.8, 7.5, 7.8],
      "hrv_values": [62, 55, 78, 65, 48, 60, 72],
      "rhr_values": [54, 58, 50, 53, 61, 55, 51],
      "strain_values": [14.2, 12.8, 8.5, 15.1, 11.3, 13.7, 9.2]
    },
    "fuel": {
      "daily_calories": [2180, 1950, 2400, 2250, 1800, 2350, 2100],
      "calorie_target": 2400,
      "daily_protein": [165, 142, 180, 158, 120, 175, 155],
      "protein_target": 180,
      "meals_logged_per_day": [4, 3, 4, 4, 2, 4, 3],
      "meals_planned_per_day": [4, 4, 4, 4, 4, 4, 4]
    },
    "mind": {
      "daily_study_minutes": [135, 90, 210, 180, 45, 120, 150],
      "study_target_minutes": 180,
      "subjects_studied": {"Calculus II": 525, "Physics": 320, "Comp Sci": 250, "Other": 165},
      "streak_days": 12,
      "upcoming_exams": [
        {"name": "Calculus II", "days_until": 6},
        {"name": "Physics", "days_until": 15}
      ]
    },
    "move": {
      "workouts": [
        {"day": "Mon", "name": "Upper Push", "duration_min": 52, "calories": 342},
        {"day": "Tue", "name": "Upper Pull", "duration_min": 55, "calories": 325},
        {"day": "Thu", "name": "HIIT", "duration_min": 30, "calories": 280},
        {"day": "Sat", "name": "Lower Pull", "duration_min": 48, "calories": 310}
      ],
      "daily_steps": [8432, 7200, 10500, 9100, 5600, 11200, 8800],
      "step_target": 10000
    },
    "non_negotiables": {
      "daily_completion_pct": [80, 60, 100, 80, 40, 100, 80]
    },
    "detected_patterns": [
      {"trigger": "sleep < 6.5h", "outcomes": ["skip_breakfast_67pct", "study_drops_40pct", "next_day_recovery_avg_38pct"], "occurrences": 8},
      {"trigger": "recovery > 80%", "outcomes": ["complete_all_nonneg_82pct", "study_35pct_more", "hit_calorie_target_90pct"], "occurrences": 12}
    ]
  }
}
```

### 10.3 Prompt Template

The backend sends this EXACT system prompt to Claude (model: `claude-sonnet-4-20250514`):

```
You are the AI brain of Tempo, a life operating system for a driven university student.
Your tone is a drill sergeant who actually cares: blunt, direct, zero fluff, occasional
dark humor. Never use exclamation marks. Never use emojis. Use imperatives.

Analyze the user's weekly data and generate EXACTLY 3 insights and 1 weekly summary quip.

Rules:
- Each insight must be data-backed. Reference specific numbers.
- Each insight must be actionable — tell the user what to DO, not just what happened.
- Insights should cross domains (e.g., sleep affecting study, recovery affecting nutrition).
- Maximum 2 sentences per insight.
- The summary quip is 1 sentence, max 10 words.
- Do NOT repeat patterns the user already knows (provided in detected_patterns).
- Focus on non-obvious connections.

Respond in this exact JSON format:
{
  "summary_quip": "string",
  "insights": [
    {
      "text": "string (max 2 sentences, the insight itself)",
      "explanation": "string (max 2 sentences, the data backing it up)",
      "category": "body|fuel|mind|move|cross_domain",
      "priority": 1|2|3
    }
  ]
}
```

### 10.4 Insight Generation Schedule

- **Weekly report insights**: Generated every Sunday at 7:00 PM local time (1 hour before the notification). The backend compiles the week's data, calls Claude, caches the response. If Claude is unavailable (timeout, error), fall back to rule-based insights (Section 6.5 patterns, reformatted as prose).
- **Daily banner insight**: Rotated from the most recent weekly insights. Monday shows insight #1, Tuesday shows insight #2, Wednesday shows insight #3, Thursday-Sunday shows the highest-priority insight from the previous or current week that the user hasn't dismissed.

### 10.5 Insight Display Design

**In Weekly Report** (Section 5.5):
- Card container: `tempo.bg.card`, corner radius `tempo.radius.card`
- Each insight: 14pt padding, separated by 1pt `tempo.divider`
- Lightbulb icon: SF Symbol `lightbulb.fill`, 14pt, `tempo.yellow`, top-left
- Insight text: font `tempo.body`, `tempo.text.primary`, max 3 lines
- Tap to expand: reveals the `explanation` field below, font `tempo.caption1`, `tempo.text.secondary`, italic. Expand animation: `tempo.anim.standard`
- Chevron: `chevron.down` (12pt, `tempo.text.tertiary`) rotates to `chevron.up` on expand

**In Dashboard Banner** (Section 3.6):
- Single insight, max 2 lines. If the insight text is > 2 lines, truncate with `...` and the chevron right indicates "tap for more".
- Tapping navigates to Patterns view, pre-scrolled to the relevant section.

### 10.6 Fallback When AI is Unavailable

If the Claude API call fails (network error, timeout > 10s, rate limit, malformed response):
1. Log the error for monitoring.
2. Generate rule-based insights using the pattern detection algorithm from Section 6.5.
3. Format the top 3 patterns as prose insights. Example: Pattern `"sleep < 6.5h -> skip breakfast 67%"` becomes insight: `"When you sleep under 6.5 hours, you skip breakfast 67% of the time. Set a hard 10:30 PM cutoff."`
4. Summary quip falls back to the score-based quips from Section 5.3.
5. A small `"[offline insight]"` badge (font `tempo.caption2`, `tempo.text.tertiary`, italic) appears below each fallback insight to indicate it was not AI-generated.

### 10.7 Example Insights (Real-Feeling Data)

These are examples of the quality and specificity expected from the AI engine:

1. `"Your recovery drops 15% the day after you study past 11 PM. Three of your five sub-60% recovery days this month followed late study sessions. Set a 10 PM cutoff."` — category: cross_domain, priority: 1

2. `"You hit your protein target on workout days (avg 172g) but miss it on rest days (avg 138g). Prep a protein-heavy snack for non-training days."` — category: fuel, priority: 2

3. `"Wednesday was your peak day this week: 92% recovery, 3.5h study, workout completed. You slept 8.3h the night before and ate 2,400 kcal. Replicate that formula."` — category: cross_domain, priority: 1

4. `"You studied Calculus II for 42% of your total time but Physics gets the same exam weight and only got 25%. Rebalance before April 8."` — category: mind, priority: 2

5. `"On days you complete your morning workout non-negotiable, you average 2.4h study time vs 1.2h on skip days. The morning workout is your keystone habit."` — category: cross_domain, priority: 1

---

## 11. Drill Sergeant Voice System

### 11.1 Context-Aware Message Pool

The drill sergeant voice is the soul of Tempo. Every message is context-aware, data-driven, and never generic. Below is the COMPLETE message pool organized by scenario. The app selects the appropriate pool based on current data state and randomly picks one message, seeded by `Date()` so the same message shows all day.

### 11.2 Dashboard Greeting Quips (Section 3.2)

Already defined in Section 3.2. These are time-of-day based only.

### 11.3 Daily Score Context Quips

Shown below the score ring when the user long-presses it (in a tooltip).

| Score Range | Context | Quip |
|-------------|---------|------|
| 90-100 | Any | `"Peak performance. Don't let up."` |
| 90-100 | Streak >= 7 | `"Day {N}. You're building a machine."` |
| 75-89 | Any | `"Good. Not great. Close the gap."` |
| 75-89 | Yesterday was < 60 | `"Bounce-back day. Keep it going."` |
| 60-74 | Any | `"Middle of the pack. That bother you?"` |
| 60-74 | Exam <= 3 days | `"Exam in {N} days and this is your effort?"` |
| 40-59 | Any | `"Below the line. Fix it before midnight."` |
| 40-59 | Missed workout | `"Skipped the workout. The score noticed."` |
| 40-59 | Low sleep | `"5.8 hours of sleep shows. Everywhere."` |
| 0-39 | Any | `"Rock bottom is a foundation. Build from here."` |
| 0-39 | Second bad day | `"Two days in a row. This is becoming a pattern."` |

### 11.4 Recovery Quips (Body Expanded View)

See Section 4.2 for the full pool (3 options per zone).

### 11.5 Nutrition Quips (Fuel Expanded View)

See Section 4.3 for the full pool.

### 11.6 Study Quips (Mind Expanded View)

See Section 4.4 for the full pool.

### 11.7 Workout Quips (Move Expanded View)

See Section 4.5 for the full pool.

### 11.8 Non-Negotiable Quips

| Scenario | Quip Pool |
|---------|-----------|
| 0 of N completed, before noon | `"Clean slate. Get to work."` / `"Five zeros. Unacceptable by tonight."` |
| 0 of N completed, after 6 PM | `"Zero done. The day is almost over."` / `"Evening and nothing checked off. Move."` |
| 1 of N completed | `"One down. {remaining} to go. Keep moving."` |
| Half completed | `"Halfway. Don't coast."` / `"50%. The second half is where discipline lives."` |
| N-1 of N completed | `"One left. Finish it."` / `"So close. Don't leave it hanging."` |
| All completed, before 2 PM | `"All done before 2 PM. Elite."` / `"Locked in early. PS5 earned."` |
| All completed, after 2 PM | `"Done. PS5 unlocked."` / `"All checked. You earned it."` |
| All completed + high daily score (>= 80) | `"Perfect day. This is the standard now."` |

### 11.9 Special Scenario Quips

| Scenario | Detection Logic | Quip Pool |
|---------|----------------|-----------|
| First day ever | `UserDefaults.standard.bool(forKey: "hasOpenedDashboard") == false` | `"Day one. No history. No excuses. Let's build."` / `"Welcome to Tempo. We don't do easy."` |
| Streak milestone (7d) | `streak_days == 7` | `"Seven days straight. That's a habit forming."` |
| Streak milestone (14d) | `streak_days == 14` | `"Two weeks. You're not the same person who started."` |
| Streak milestone (30d) | `streak_days == 30` | `"Thirty days. Most people quit at seven. Noted."` |
| Streak milestone (100d) | `streak_days == 100` | `"Triple digits. You're in rare territory."` |
| Streak broken | `yesterday_streak > 0 && today_streak == 0` | `"Streak broken at {N} days. Restart. Now."` / `"The streak died. Mourn it for 5 seconds, then start a new one."` |
| Sunday evening (review time) | Day == Sunday && hour >= 18 | `"Sunday check-in. How honest are you willing to be?"` / `"Week's almost done. Own the scorecard."` |
| Monday morning | Day == Monday && hour < 12 | `"New week. Clean slate. Set the tone."` / `"Monday. The most important day of the week."` |
| Exam tomorrow | `nearest_exam.daysUntil == 1` | `"Exam tomorrow. You either put in the work or you didn't."` / `"{exam_name} is tomorrow. No cramming saves a lazy week."` |
| Exam today | `nearest_exam.daysUntil == 0` | `"Exam day. Trust the prep. Execute."` / `"{exam_name} today. Deep breath. Go."` |
| Great recovery + no training yet | `recovery >= 80 && workout_status != .completed && hour >= 10` | `"Recovery at {N}%. Your body is ready. Are you?"` / `"Green zone and no workout yet. Wasting it."` |
| Bad sleep + exam this week | `sleep_hours < 6 && nearest_exam.daysUntil <= 7` | `"Under 6 hours with an exam in {N} days. Fix tonight."` |
| All meals logged + on target | `meals_logged == meals_planned && calories within 10% of target` | `"Nutrition: dialed. Keep it boring."` |
| Missed meals (2+ skipped) | `skipped_meals >= 2` | `"Two meals skipped. Your body doesn't care about your schedule."` |
| Late night (after midnight, app open) | `hour >= 0 && hour < 4` | `"It's past midnight. Whatever you're doing isn't worth the recovery cost."` |

### 11.10 Quip Selection Algorithm

```swift
func selectQuip(for scenario: QuipScenario, data: DashboardState) -> String {
    let pool = quipPool(for: scenario, data: data)

    // Seed random with today's date so the same quip shows all day
    let calendar = Calendar.current
    let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 0
    var rng = SeededRandomNumberGenerator(seed: UInt64(dayOfYear))

    return pool.randomElement(using: &rng) ?? "Get after it."
}
```

The quip updates once per day at midnight local time. This prevents the jarring UX of seeing different quips on every refresh.

---

## 12. First-Time User Experience

### 12.1 Day 0 — Zero Data, No Integrations

When the user opens the dashboard for the first time (no data, no integrations connected):

**Dashboard state**:
- Header greeting: `"Let's get started."` (overrides time-of-day greeting for the first session only. Uses `UserDefaults.standard.bool(forKey: "hasSeenFirstGreeting")`)
- Settings icon visible, notification bell hidden (no notifications yet)
- Score ring: empty track, `"--"` inside, `"Connect more sources"` below
- No stagger animation on first launch — all elements appear simultaneously with a single 0.3s fade-in. The stagger animation starts on the SECOND session.

**Quadrant states**:
```
+-----------------+  +-----------------+
| BODY         V  |  | FUEL         F  |
|                 |  |                 |
| [Whoop icon]    |  | [Fork icon]     |
| Connect Whoop   |  | Connect         |
| to track        |  | NutriTrack      |
| recovery        |  | to track        |
|                 |  | nutrition       |
| [ Connect ]     |  | [ Connect ]     |
+-----------------+  +-----------------+
+-----------------+  +-----------------+
| MIND         B  |  | MOVE         R  |
|                 |  |                 |
| 0m              |  | [Heart icon]    |
| Set your study  |  | Allow Health    |
| target          |  | Access          |
|                 |  | to track        |
|  [ Set Up ]     |  | activity        |
|                 |  | [ Authorize ]   |
+-----------------+  +-----------------+
```

- BODY: Whoop connect prompt (see Section 3.4.1 disconnected state)
- FUEL: NutriTrack connect prompt (see Section 3.4.2 disconnected state)
- MIND: Shows `"0m"` with subtitle `"Set your study target"` and a `[ Set Up ]` button that presents the study target configuration sheet. Font: `tempo.callout`, `tempo.blue`.
- MOVE: HealthKit authorization prompt (see Section 3.4.4 not authorized state)

**Non-negotiables**: Empty state with `"Set your daily non-negotiables"` and `"+ Add non-negotiable"` link.

**Insight banner**: Not shown (no data to derive insights from).

**FAB**: Visible but its actions are contextual:
- Log Meal: presents even without NutriTrack (allows manual entry)
- Start Workout: disabled if HealthKit not authorized, shows tooltip `"Authorize Health first"`
- Study Timer: always available
- Check Non-Neg: presents Add Non-Negotiable if none are set

### 12.2 Day 1 — Partial Data (Some Sources Connected)

Assume the user connected Whoop and HealthKit on Day 0 but hasn't connected NutriTrack. It's now 2 PM on Day 1.

**Dashboard state**:
- Greeting: time-of-day based (normal)
- Score ring: calculated from 3 sources (Whoop, HealthKit, Local). Weight redistribution: each gets 33.3%. FUEL weight (25%) split equally among the three. Score shows a number (e.g., `65`).
- "Last sync" shows relative timestamp.

**Quadrant states**:
- BODY: Full data from Whoop (recovery, HRV, RHR, sleep, strain). Fully functional.
- FUEL: Still shows `"Connect NutriTrack"` prompt. The daily score calculates without it.
- MIND: Shows `"0m"` or actual study time if user started a session. Study target was set on Day 0, so subtitle shows `"0 / 180 min"` or actual progress. No exams yet unless user added one.
- MOVE: Steps and calories from HealthKit. No workout yet or workout completed. Fully functional.

**Non-negotiables**: User may have set 1-2. Progress bar and pills render normally.

**Insight banner**: Not shown (need >= 7 days of data for pattern detection).

### 12.3 Day 7 — Full Data, All Sources Connected

By Day 7, all sources are connected and the user has a week of data.

**Dashboard state**:
- Score ring: all 4 sources active, 25% each. Full score.
- All quadrants show real data, fully populated.
- Non-negotiables populated and tracking.
- **First insight banner appears**: The pattern detection engine has 7 days of data. The first insight is generated and appears in the banner. This is a moment of delight — the app "waking up" and starting to understand the user.
- Stagger animation plays normally on each cold launch.
- Weekly report is generated for the first time and notification fires on Sunday at 8 PM.

### 12.4 Progressive Richness Indicators

| Feature | Unlocks At | Indicator |
|---------|-----------|-----------|
| Daily score | 2+ sources connected (could be Day 0) | Score ring fills instead of showing `"--"` |
| Insight banner | 7 days of data from >= 2 sources | Banner appears below non-negotiables |
| Patterns view | 14 days of data | `"View Patterns"` link appears in score ring context menu |
| Strong correlations | 30 days of data (need >= 30 data points for meaningful r) | Scatter plots appear in Patterns view |
| AI insights | 7 days of data + backend available | AI-generated insights replace rule-based ones |
| Weekly report | End of first full week | Notification fires, report accessible |
| Historical comparison | 2+ days of data | `"vs Yesterday"` row appears in expanded views |
| 7-day trend charts | 3+ days of data (chart renders with available points) | Charts show partial data, fill in over time |

---

## 13. Offline Mode & Stale Data

### 13.1 Offline Detection

Use `NWPathMonitor` to detect network status. The monitor runs on a background queue and publishes status changes via `@Observable` `NetworkMonitor` class.

```swift
@Observable
class NetworkMonitor {
    var isConnected: Bool = true
    var connectionType: NWInterface.InterfaceType? = nil

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
```

### 13.2 Offline Banner

When `isConnected == false`:

- A thin banner appears at the TOP of the dashboard, below the safe area but ABOVE the header bar.
- Banner height: 28pt.
- Background: `tempo.offline.bg` (`#FFF3CD` light / `#332B00` dark).
- Text: `"Offline -- showing cached data"`, centered. Font: `tempo.caption1`, color: `tempo.offline.text`.
- Left icon: SF Symbol `wifi.slash`, 12pt, `tempo.offline.text`.
- **Appearance animation**: Slides down from behind the safe area over 0.3s (`tempo.anim.dismiss` reversed). Pushes all dashboard content down by 28pt, animated.
- **Disappearance**: When connectivity restores, banner slides up and out over 0.3s. Content shifts back up. Then an automatic refresh triggers (same as pull-to-refresh but without the custom spinner — just background data fetch).

### 13.3 Per-Source Stale Data Indicators

Each data source has independent staleness tracking:

| Source | Fresh | Stale Threshold | Stale Treatment | Critical Threshold | Critical Treatment |
|--------|-------|----------------|-----------------|-------------------|--------------------|
| Whoop | < 30 min | 30 min - 2 hr | Yellow 4pt dot next to BODY label. Timestamp text turns `tempo.stale`. | > 2 hr | Timestamp pulses (opacity 0.5-1.0, 2s cycle). Card gets 1pt `tempo.stale` border at 40% opacity. |
| NutriTrack | < 20 min | 20 min - 1 hr | Yellow dot next to FUEL label. Timestamp turns `tempo.stale`. | > 1 hr | Same pulsing + border treatment. |
| HealthKit | < 10 min (HR only) | 10 min - 30 min | Yellow dot next to MOVE label (only if HR is the stale value; steps are always "live" via observer). | > 30 min | Same treatment. Steps are never considered stale while HealthKit is authorized. |
| Local | Never stale | N/A | N/A | N/A | N/A |

**Last-synced timestamp per quadrant**: Each quadrant card shows its own last-sync time in the bottom-right corner when stale. Format: `"Synced {relative_time}"` in `tempo.caption2`. This only appears when the source is stale — when fresh, no timestamp is shown on the card (it would be noise).

### 13.4 Feature Degradation by Connectivity State

| Feature | Online | Offline (with cache) | Offline (no cache) |
|---------|--------|---------------------|-------------------|
| Dashboard display | Full real-time data | Cached data with stale indicators | Disconnected states for API sources. Local data (Mind, non-negs) still works. |
| Pull-to-refresh | Refreshes all sources | Pull gesture works but immediately shows error toast: `"No connection. Showing cached data."` Minimum display time still applies. | Same behavior |
| Daily score | Calculated from live data | Calculated from cached data. Accuracy note: cached recovery may not reflect current state, but score is still useful as "last known". | Only from local + HealthKit (if authorized). May show `"--"` if < 2 sources. |
| AI insights | Generated from server | Cached insights from last generation. If no cache: rule-based fallback from local pattern engine. | Rule-based only from local data. |
| Weekly report | Generated on-demand | Cached report. If never generated: `"Weekly report available when online."` | Same |
| Expanded views | Full data + charts | Cached data + charts. Charts may have gaps. | Minimal data. Charts may be empty. |
| Widgets | Shared data from last sync | Same as main app (widgets always read from cache). | Placeholder or last available data. |
| Study timer | Fully functional (local) | Fully functional | Fully functional |
| Meal logging | Sends to NutriTrack API | Queued locally. Syncs when online. Show `"Saved locally. Will sync when online."` toast. | Same — local queue. |

### 13.5 Cache Storage

All data is cached in SwiftData with `lastSync` timestamps per record:

```swift
@Model
class CachedDashboardData {
    var date: Date
    var bodyData: Data?          // JSON-encoded BodyQuadrantData
    var fuelData: Data?          // JSON-encoded FuelQuadrantData
    var mindData: Data?          // JSON-encoded MindQuadrantData (redundant with local, but cached for widget)
    var moveData: Data?          // JSON-encoded MoveQuadrantData
    var dailyScore: Int?
    var whoopLastSync: Date?
    var nutritrackLastSync: Date?
    var healthkitLastSync: Date?
    var lastModified: Date
}
```

Cache is written after every successful data fetch. The cache is also written to the shared App Group container for widget access.

---

## 14. Notification Deep-Links

### 14.1 Notification Types & Deep-Link Targets

| Notification | Trigger | Content | Deep-Link URL | Landing State |
|-------------|---------|---------|---------------|---------------|
| Weekly report ready | Sunday 8:00 PM local | `"Your weekly report is ready. How'd you do?"` | `tempo://dashboard/report` | Weekly Report view pushed onto nav stack. Dashboard is the root. User sees the full report. Scroll position: top. |
| Low recovery warning | Recovery < 34%, detected at 7:00 AM | `"Recovery at {N}%. Take it easy today."` | `tempo://dashboard/body` | Body expanded view pushed. Recovery hero section visible at top. The red recovery ring is prominent. |
| Exam reminder | Exam <= 3 days away, 9:00 AM | `"{exam_name} in {N} days. Study or suffer."` | `tempo://dashboard/mind` | Mind expanded view pushed. Upcoming Exams section auto-scrolled to the relevant exam row. That exam row has a brief highlight animation: background flashes `tempo.yellow` at 15% opacity for 1s, then fades. |
| Meal reminder | Planned meal time +30 min if not logged, checked hourly | `"You missed logging {meal_name}. Log it now."` | `tempo://action/log-meal` | Log Meal sheet presents over dashboard. If the specific meal can be pre-selected, do so. |
| Non-neg reminder | 8:00 PM if < 100% complete | `"{remaining} non-negotiables left. PS5 is still locked."` | `tempo://dashboard` | Dashboard scrolls to Non-Negotiables bar. The bar has a brief highlight: 1pt `tempo.accent` border pulses once (0.5s on, 0.5s off, 0.5s on). |
| Streak at risk | 9:00 PM if study_minutes < study_target and streak >= 3 | `"Streak at {N} days. {remaining} min to keep it alive."` | `tempo://dashboard/mind` | Mind expanded view. Study progress section prominent. `[ Start Study Session ]` button pulses once (scale 1.0 to 1.03 to 1.0, 0.5s). |
| Study session complete | Study timer reaches target | `"Target hit. {total} today. Respect."` | `tempo://dashboard` | Dashboard loads normally. Mind quadrant's primary value shows the updated study time with the counter roll animation. |
| Morning briefing | 7:00 AM daily (configurable) | `"Recovery {N}%. {workout_or_rest} day. {meals_planned} meals planned."` | `tempo://dashboard` | Dashboard loads with stagger animation (since this is likely a cold launch). Score ring animates. |
| Workout reminder | If workout planned and not started by 4:00 PM | `"Planned workout still pending. Start or skip?"` | `tempo://dashboard/move` | Move expanded view. `[ Start Workout ]` button highlighted. |

### 14.2 Deep-Link Handling Architecture

```swift
// In the main App struct
@main
struct TempoApp: App {
    @State private var navigationPath = NavigationPath()
    @State private var pendingDeepLink: DeepLink? = nil

    var body: some Scene {
        WindowGroup {
            DashboardView(navigationPath: $navigationPath)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    // Check for notification deep-link from cold launch
                    if let pending = pendingDeepLink {
                        executePendingDeepLink(pending)
                    }
                }
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "tempo" else { return }

        switch url.host {
        case "dashboard":
            if let path = url.pathComponents.dropFirst().first {
                switch path {
                case "body": navigationPath.append(QuadrantRoute.body)
                case "fuel": navigationPath.append(QuadrantRoute.fuel)
                case "mind": navigationPath.append(QuadrantRoute.mind)
                case "move": navigationPath.append(QuadrantRoute.move)
                case "report": navigationPath.append(DashboardRoute.weeklyReport)
                case "timeline": navigationPath.append(DashboardRoute.timeline)
                default: break // Just show dashboard
                }
            }
            // If just "tempo://dashboard", pop to root and optionally scroll
        case "action":
            if let action = url.pathComponents.dropFirst().first {
                switch action {
                case "log-meal": presentLogMeal()
                case "start-workout": presentStartWorkout()
                case "study-timer": presentStudyTimer()
                default: break
                }
            }
        default: break
        }
    }
}
```

### 14.3 Cold Launch vs Warm Launch Deep-Link Behavior

**Cold launch** (app not in memory):
1. App initializes, dashboard renders with cached data, stagger animation fires.
2. After the stagger animation completes (t=0.7s), the deep-link navigation executes.
3. This means the user briefly sees the dashboard animating in, then the target view pushes on. This is intentional — it gives the user spatial context (they know they're in the dashboard, then going to a detail).
4. If the target is a sheet/fullScreenCover (e.g., Log Meal), it presents at t=0.5s (slightly earlier, since sheets don't need nav stack context).

**Warm launch** (app in background):
1. Dashboard is already rendered with existing data.
2. Deep-link navigation executes immediately (within 1 frame).
3. A background data refresh triggers simultaneously so the user sees fresh data.

### 14.4 Scroll Position & Highlighted Element

When a deep-link targets the main dashboard with a specific section to highlight (e.g., non-negotiables reminder):

1. If the dashboard is already visible, use `ScrollViewReader` with `.scrollTo(id:anchor:)` to scroll to the target section.
2. The scroll animation uses `tempo.anim.standard`.
3. The target element's ID is set via `.id("non-negotiables-bar")` or equivalent.
4. After scrolling completes (0.35s), the highlight animation fires (described per-notification in the table above).
5. If the user was on a different view (e.g., expanded quadrant), pop to dashboard root first, then scroll.

---

## 15. Accessibility

### 15.1 VoiceOver

Every interactive element must have:
- **Accessibility label**: Descriptive text. E.g., the Body quadrant card: `"Body quadrant. Recovery 72 percent. HRV 68.3 milliseconds. Resting heart rate 52 bpm. Sleep 7.2 hours. Strain 14.2 out of 21. Double tap to view details."`.
- **Accessibility value**: For progress-based elements. E.g., calorie ring: value = `"1842 of 2400 kilocalories, 77 percent"`.
- **Accessibility traits**: `.isButton` for tappable cards. `.isHeader` for section headers. `.updatesFrequently` for the score number during count-up animation.
- **Accessibility hint**: `"Double tap to view details"` on quadrant cards. `"Double tap to toggle"` on non-negotiable items.

**Stale data announcement**: When a quadrant becomes stale, post a `UIAccessibility.post(notification: .announcement, argument: "Body data is stale. Last synced 45 minutes ago.")` announcement. Only announce once per staleness transition, not repeatedly.

### 15.2 Dynamic Type

- All text must scale with Dynamic Type up to `xxxLarge`.
- When text size is `xxLarge` or larger:
  - The quadrant grid switches from 2x2 to a single-column vertical stack (each card full width).
  - Metric labels wrap to new lines instead of truncating.
  - The Daily Score ring scales to 120pt.
- Use `@ScaledMetric` for spacing tokens and icon sizes.

### 15.3 Reduce Motion

When `UIAccessibility.isReduceMotionEnabled`:
- Disable stagger animations on appear — all elements appear immediately.
- Score ring: no animated fill, appear at final value instantly.
- Value changes: no counter roll, values snap to new numbers instantly.
- Card taps: no scale animation on press.
- Quadrant expansion: cross-dissolve instead of matched geometry.
- Confetti animation for non-negotiables: replaced with a simple flash (background briefly changes to `tempo.green` at 10% opacity, 0.3s).
- Pull-to-refresh: use native spinner instead of custom ring animation.

### 15.4 Color Contrast

All text and icon colors meet WCAG 2.1 AA contrast requirements (minimum 4.5:1 for normal text, 3:1 for large text) against their background. The design system colors specified above satisfy this in both light and dark mode.

### 15.5 Bold Text

When the Bold Text accessibility setting is enabled, all `Regular` weight text becomes `Medium`, all `Medium` becomes `Semibold`, all `Semibold` becomes `Bold`. Use `UIAccessibility.isBoldTextEnabled` or rely on the system font weight adjustment.

---

## 16. Performance Budget

| Metric | Target | Measurement |
|--------|--------|-------------|
| Time to First Meaningful Paint | < 300ms | From `viewDidAppear` to all cached data rendered |
| Time to Interactive | < 500ms | All taps responsive, no pending layout |
| Pull-to-Refresh Complete | < 3s | From pull to all data refreshed (95th percentile) |
| Score Ring Animation | 60 fps | No frame drops during ring fill |
| Scroll Performance | 60 fps | No frame drops during scroll |
| Memory Usage | < 50MB | Dashboard view total memory footprint |
| Widget Refresh | < 5s budget | TimelineProvider `getTimeline` execution time |
| Cold Launch to Dashboard | < 1.5s | App process start to dashboard rendered |
| Skeleton to Real Data | < 2s | Per-quadrant, from first data request to render |
| Deep-Link Navigation | < 0.5s | From notification tap to target view visible |

### 16.1 Caching Strategy

- All data models are cached in SwiftData with `lastSync` timestamps.
- On app launch, render immediately from cache. Then fetch fresh data in the background and animate changes in.
- Charts cache their rendered paths. Only recompute on data change, not on scroll.
- Widget timeline entries are pre-computed and stored. The widget only reads static data — no network calls in the widget process.

### 16.2 Image / Asset Budget

- The dashboard uses zero raster images — all visuals are SF Symbols, SwiftUI shapes, and Canvas drawings.
- This ensures crisp rendering at all scales and zero image decode overhead.

---

## 17. Error Handling Matrix

| Scenario | User-Facing Behavior | Technical Behavior |
|---------|---------------------|-------------------|
| Whoop API returns 401 (token expired) | Body quadrant shows "Reconnect Whoop" with a Reconnect button | Clear Whoop token. On button tap, restart OAuth. |
| Whoop API returns 429 (rate limited) | Body quadrant shows last cached data with yellow "Last sync" timestamp | Retry with exponential backoff: 30s, 60s, 120s. Max 3 retries. |
| Whoop API returns 500 | Body quadrant shows error state (Section 3.4.1) | Retry once after 10s. If still failing, show error. Cache `lastError` for display. |
| Whoop API timeout (>10s) | Body quadrant shows last cached data + stale indicator | Log timeout. Use cached data. Retry on next refresh cycle. |
| HealthKit authorization denied | Move quadrant shows "Allow Health Access" state | Do not re-prompt. Show the authorization button which opens Settings via `UIApplication.openSettingsURLString`. |
| HealthKit returns no data | Move quadrant shows 0 values (not error state) | This is normal (morning state). Show zeros, not an error. |
| NutriTrack API unreachable | Fuel quadrant shows last cached data or "Connect NutriTrack" if never connected | Retry with exponential backoff. Show stale indicator on timestamps. |
| NutriTrack API returns malformed data | Fuel quadrant shows last cached data | Log the error. Do not crash. Use cached data. Report to analytics. |
| No internet connection | Offline banner appears. All API-dependent quadrants show cached data. | Detect via `NWPathMonitor`. See Section 13 for full offline behavior. |
| First launch (no data at all) | See Section 12 (First-Time User Experience) | Guide user through connecting sources. |
| App backgrounded for >24h | On foreground, show yesterday's data briefly, then refresh to today | Detect date change. If `lastRefresh.date != today`, clear day-specific caches and trigger full refresh. Show loading shimmer while refreshing. |
| Core Data / SwiftData migration failure | Show a generic "Something went wrong" screen with "Restart App" button | Log crash diagnostics. Attempt re-migration once. If fails, present recovery flow that clears local data (with user confirmation: "This will reset your local data. Connected services will re-sync."). |
| Daily score calculation returns NaN/Inf | Show "--" for daily score | Guard all divisions against zero. Log the computation inputs for debugging. |
| Widget fails to load data | Widget shows "Open Tempo" fallback | Widget timeline returns a fallback entry. On tap, deep-link to dashboard which triggers a fresh sync. |
| Claude API unavailable for insights | Show rule-based insights with `"[offline insight]"` badge | See Section 10.6 for full fallback behavior. |
| Deep-link to unavailable view | Navigate to dashboard root instead | If a deep-link targets an expanded view but the source is disconnected, show the dashboard and scroll to that quadrant's connect prompt. |
| Notification received while in-app | Do NOT navigate. Show an in-app banner: same text as notification, 44pt height, `tempo.bg.card`, slides down from top, auto-dismisses after 4s. Tap on banner executes the deep-link. | Use `UNUserNotificationCenter.delegate` with `userNotificationCenter(_:willPresent:)` returning `.banner`. Custom in-app banner for richer experience. |

---

## Appendix A: ASCII Mockup — Full Dashboard (iPhone 15, 393pt width)

```
+=========================================+
|  Mon, Mar 24                    [G] [B] |  <- [A] Header
|  Rise and grind, Nicola.                |
|                                         |
|              +----------+               |  <- [B] Score
|              |          |               |
|              |    78    |               |
|              |          |               |
|              +----------+               |
|              Daily Score                |
|            Last sync: 2m ago            |
|                                         |
|  +---------------+  +---------------+   |  <- [C] Quadrants
|  | BODY        V |  | FUEL        F |   |
|  |               |  |               |   |
|  | 72%           |  |  [--] 1842   |   |
|  | Recovery      |  |  [  ] /2400  |   |
|  |               |  |  kcal        |   |
|  | 68.3  52 7.2h |  |              |   |
|  | HRV  RHR Slp  |  | P142 C205 F52|  |
|  |               |  |               |   |
|  | ========----- |  | 2/4 meals     |   |
|  |    Strain 14.2|  |               |   |
|  +---------------+  +---------------+   |
|                                         |
|  +---------------+  +---------------+   |
|  | MIND       B  |  | MOVE       R  |   |
|  |               |  |               |   |
|  | 2h 15m       |  | [v] Done      |   |
|  | 135/180 min  |  | Upper Push 52m|   |
|  |               |  |               |   |
|  | =========--- |  | 8,432  342cal |   |
|  |               |  | Steps  Active |   |
|  | [C] Calc 6d  |  |               |   |
|  | [F] 12d strk |  | ========----- |   |
|  |               |  |    10,000 goal|   |
|  +---------------+  +---------------+   |
|                                         |
|  +----------------------------------+   |  <- [D] Non-Negs
|  | 3/5 done -- PS5 locked [L]      |   |
|  | ==============----------         |   |
|  | [v] Workout [v] 8h sleep        |   |
|  | [ ] 2L water [ ] Meal prep [v]S |   |
|  +----------------------------------+   |
|                                         |
|  +----------------------------------+   |  <- [E] Insight
|  | [*] When you sleep < 6.5h, you  |   |
|  |     skip breakfast 67% of the  > |   |
|  |     time.                        |   |
|  +----------------------------------+   |
|                                         |
|                                    [+]  |  <- FAB
|                                         |
+=========================================+
```

## Appendix B: iPhone SE Layout Adjustments

On iPhone SE (375pt width, 667pt height):

- Quadrant width reduces to ~159.5pt. Content inside cards must accommodate this:
  - Body: Secondary metrics row shows 2 metrics only (HRV + Sleep). RHR hidden (visible in expanded view).
  - Fuel: Macro bars use single letter labels (`P`, `C`, `F`).
  - Mind: Exam countdown truncates long exam names with `...` after 12 characters.
  - Move: `"Active Cal"` label truncates to `"Act Cal"`.
- Score ring remains 100pt (centered, plenty of room).
- Non-negotiable pills may require more rows of wrapping.
- The total content height will be approximately 950-1000pt, requiring meaningful scrolling on the 586pt viewport.
- FAB position: 16pt from right edge (instead of 20pt) to avoid feeling cramped.

## Appendix C: First Launch State

See Section 12 for the complete first-time user experience specification with Day 0, Day 1, and Day 7 states.

## Appendix D: Data Change Animation Reference

Quick reference for how every data type animates when its value changes:

| Data Type | Animation | Duration | Notes |
|-----------|-----------|----------|-------|
| Integer values (score, recovery, steps, calories, protein, etc.) | Counter roll (increment/decrement through integers) | `tempo.anim.counter` (0.8s) for large numbers, 0.4s for small (< 100) | Use `TimelineView(.animation)` for frame-perfect counting |
| Decimal values (HRV, sleep hours, strain) | Crossfade (old out, new in) | 0.15s out + 0.15s in = 0.3s total | Counter roll on decimals looks jittery — always crossfade |
| Progress bars (strain, macros, study, steps) | Width animation from old to new | `tempo.anim.standard` (0.35s spring) | Bar fill smoothly extends or retracts |
| Ring fills (score ring, calorie ring) | Arc angle animation | 0.5s spring for updates, 1.0s for first appear | Ring overshoots slightly due to spring curve |
| Status text changes (workout status, meal status) | Crossfade | 0.25s easeInOut | Text swaps cleanly without jarring pop |
| Color zone changes (recovery green/yellow/red) | Color crossfade | 0.4s easeInOut | Applied to text color, ring fill, and accent icon simultaneously |
| Badge appearances (streak, checkmarks) | Scale-in spring (0 to 1.0) | 0.3s, dampingFraction: 0.6 | Slight overshoot for bouncy feel |
| Badge disappearances (streak broken) | Scale-out + fade | 0.2s easeIn | Quick exit — the loss should feel abrupt |
