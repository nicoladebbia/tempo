# MODULE_DASHBOARD — "LifeOS" Home Screen

> **Module**: Dashboard (LifeOS)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Views/Dashboard/DashboardView.swift`
- `Tempo/Tempo/ViewModels/DashboardViewModel.swift`
- `Tempo/Tempo/Views/Dashboard/*QuadrantDetailView.swift`, `WeeklyReportView.swift`, `WelcomeBannerView.swift`, `DashboardLoadingView.swift`
- `Tempo/Tempo/Utilities/Constants/DesignTokens.swift`, `Utilities/Extensions/Color+Tempo.swift`, `Font+Tempo.swift`
- `Tempo/TempoWidget/TempoWidget.swift`, `TempoWidgetViews.swift`

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

The original spec used a `tempo.color.bg.primary` dotted-token namespace. **That namespace does not exist in code.** The real system is:
- Colors: named **asset catalog colorsets** (`Tempo/Tempo/Assets.xcassets/Colors/*.colorset`), accessed via static `Color` accessors in `Color+Tempo.swift`.
- Spacing / radius / opacity / animation / elevation: Swift **enums** in `Utilities/Constants/DesignTokens.swift`.
- Typography: static `Font` accessors in `Font+Tempo.swift`.

> **Divergence from original spec:** Token *names and access pattern* changed entirely (asset names + Swift accessors, not dotted string tokens). Concrete hex values live in the `.colorset` JSON and are not duplicated here — read the asset catalog for ground-truth hex.

### 1.1 Color Palette

| Asset Name (colorset) | Swift Accessor | Usage |
|-----------------------|----------------|-------|
| `tempo-bg-primary` | `Color.tempoBgPrimary` | Main background |
| `tempo-bg-secondary` | `Color.tempoBgSecondary` | Secondary surface (Arena card, etc.) |
| `tempo-bg-tertiary` | `Color.tempoBgTertiary` | Tertiary background |
| `tempo-surface-card` | `Color.tempoSurfaceCard` | Card surfaces |
| `tempo-surface-sheet` | `Color.tempoSurfaceSheet` | Bottom-sheet surface |
| `tempo-surface-elevated` | `Color.tempoSurfaceElevated` | Elevated surface |
| `tempo-ink` | `Color.tempoInk` | Ink (shadow/scrim base) |
| `tempo-bone` | `Color.tempoBone` | Bone (light neutral) |
| `tempo-signal` | `Color.tempoSignal` | Primary accent (drill-sergeant red) |
| `tempo-signal-pressed` | `Color.tempoSignalPressed` | Primary accent pressed |
| `tempo-text-primary` | `Color.tempoTextPrimary` | Headlines, large numbers |
| `tempo-text-secondary` | `Color.tempoTextSecondary` | Labels, captions |
| `tempo-text-tertiary` | `Color.tempoTextTertiary` | Placeholder, disabled |
| `tempo-text-disabled` | `Color.tempoTextDisabled` | Disabled text |
| `tempo-text-inverse` | `Color.tempoTextInverse` | Inverse text |
| `tempo-recovery-green` / `-bg` | `Color.tempoRecoveryGreen` / `…GreenBg` | Recovery high zone |
| `tempo-recovery-yellow` / `-bg` | `Color.tempoRecoveryYellow` / `…YellowBg` | Recovery moderate zone |
| `tempo-recovery-red` / `-bg` | `Color.tempoRecoveryRed` / `…RedBg` | Recovery low zone |
| `tempo-electric` | `Color.tempoElectric` | Mind/info accent |
| `tempo-amber` | `Color.tempoAmber` | Move accent |
| `tempo-violet` | `Color.tempoViolet` | Fuel accent |
| `tempo-success` | `Color.tempoSuccess` | On-track / complete |
| `tempo-warning` | `Color.tempoWarning` | Caution |
| `tempo-error` | `Color.tempoError` | Error |
| `tempo-info` | `Color.tempoInfo` | Info |
| `tempo-border` / `-focused` / `-error` | `Color.tempoBorder` / `…Focused` / `…Error` | Borders |
| `tempo-divider` / `-heavy` | `Color.tempoDivider` / `…Heavy` | Dividers |
| _(literal RGB, no asset)_ | `Color.tempoPRGold` | PR gold |
| _(literal RGB, no asset)_ | `Color.tempoMacroProtein` / `…Carbs` / `…Fat` | Macro bar colors |

### 1.2 Typography

Fonts are SF Pro (system). Accessors are static `Font` values in `Font+Tempo.swift`. Tokens map to system text styles (Dynamic Type aware), NOT fixed point sizes.

| Swift Accessor | Maps To | Typical Usage |
|----------------|---------|---------------|
| `Font.tempoXPDisplay` | computed large display | Quadrant primary value (e.g. recovery %) |
| `Font.tempoLargeTitle` | `.largeTitle.bold()` | Large titles |
| `Font.tempoTitle1` | `.title.bold()` | Hero values |
| `Font.tempoTitle2` | `.title2.bold()` | Greeting line, screen titles |
| `Font.tempoTitle3` | `.title3.weight(.semibold)` | Section headers |
| `Font.tempoHeadline` | `.headline` | Headlines |
| `Font.tempoSubheadline` | `.subheadline` | Non-negotiables header |
| `Font.tempoBody` / `tempoBodyBold` | `.body` / `.body.semibold` | Body text |
| `Font.tempoCallout` | `.callout` | Callouts |
| `Font.tempoCaption1` / `tempoCaption2` | `.caption` / `.caption2` | Captions, units, timestamps |
| `Font.tempoFootnote` | `.footnote` | Footnotes |
| `Font.tempoDataMedium` / `tempoDataLarge` | computed monospaced data | Score pill number, score sheet hero |

> **Divergence from original spec:** Spec specified fixed point sizes/weights/tracking per token. Code uses **relative system text styles** (Dynamic Type scales automatically); there is no fixed 34pt/28pt/etc. scale enforced in code.

### 1.3 Spacing & Layout

From `enum TempoSpacing` / `enum TempoRadius` / `enum TempoOpacity` (`DesignTokens.swift`). Selected tokens:

| Token | Value |
|-------|-------|
| `TempoSpacing.xxs` | 2pt |
| `TempoSpacing.xs` | 4pt |
| `TempoSpacing.sm` | 8pt |
| `TempoSpacing.md` | 12pt |
| `TempoSpacing.lg` | 16pt |
| `TempoSpacing.xl` / `.screenEdge` | 20pt |
| `TempoSpacing.xxl` | 24pt |
| `TempoSpacing.xxxl` / `.sectionGap` | 32pt |
| `TempoSpacing.cardPadding` | 16pt |
| `TempoSpacing.cardPaddingCompact` / `.cardGap` | 12pt |
| `TempoRadius.lg` | 10pt |
| `TempoRadius.xl` | 12pt |
| `TempoRadius.xxl` | 14pt |
| `TempoRadius.xxxl` | 16pt (standard cards) |
| `TempoRadius.xxxxl` | 20pt (sheets) |
| `TempoRadius.pill` | 9999pt |

> **Status: NOT IMPLEMENTED — pixel-perfect per-device sizing tables.** The original §1.4 device matrix (per-iPhone quadrant widths, viewport heights, scroll estimates) and the `(screenWidth - 2*edge - gap)/2` quadrant formula are **not in code**. The grid uses a plain 2-column `LazyVGrid` with `GridItem(.flexible())` and `TempoSpacing.cardGap` — SwiftUI handles all sizing. There is no size-class branching. Treat the old §1.4 numbers as design notes only.

### 1.5 Animation Constants

From `enum TempoAnimation` (`DesignTokens.swift`): `microDuration` 0.1s, `smallDuration` 0.2s, `mediumDuration` 0.3s, `largeDuration` 0.5s, `dataDuration` 0.7s, `celebrationDuration` 1.0s; stagger constants (`staggerCard` 0.06s, `staggerBar` 0.05s, `staggerRing` 0.15s); springs `springMedium`, `springLarge`, `springData`, `springCelebration`; easing `micro`, `small`.

> **Divergence from original spec:** Tokens exist but most of the dashboard does **not** consume the stagger/celebration/ring-fill tokens (see §3.9, §3.5, §3.3). They are defined but largely unused on this screen.

Shadows/elevation: `struct TempoShadow` + `enum TempoElevation` (`cardLight`, `sheetLight/Dark`, `fabLight/Dark`, `popoverLight/Dark`, `scrimLight/Dark`), applied via a `.tempoShadow(.card)` modifier.

---

## 2. Data Layer Contract

### 2.1 Data Sources & Refresh Strategy

> **Status: NOT IMPLEMENTED — per-source TTL / staleness-threshold engine.** There is no `DataAgeStatus`, no `isCriticallyStale`, no per-source cache-TTL or staleness-threshold table in code. Data is loaded by `DashboardViewModel` on appear / pull-to-refresh from the live services (`WhoopService`, `HealthKit`, nutrition, SwiftData). A future build would add a staleness model to drive §13.3 stale UI.

### 2.2 Data Models

Implemented in `DashboardViewModel.swift` as plain structs surfaced as properties on the `@Observable` view model: `BodyQuadrantData`, `FuelQuadrantData`, `MindQuadrantData`, `MoveQuadrantData`, `NonNegotiableItem`. Field names match the spec's intent (recovery/hrv/rhr/sleep/strain; calories/macros/meals; study minutes/exams/streak; workout status/steps/active cal). Each quadrant struct also carries an `isConnected` flag and `formatted*` computed helpers used directly by the views.

> **Divergence from original spec:** No `DashboardState` umbrella struct, no `ConnectionStatus`/`DataAgeStatus`/`isStale`/`isOffline` fields. The view model exposes the quadrant structs and a `dailyScore: Int?` directly.

### 2.3 Daily Score Calculation

Implemented in `DashboardViewModel.computeDailyScore()`. Real behavior:

| Component | Weight | "Available" condition (in code) | Raw formula |
|-----------|--------|----------------------------------|-------------|
| Recovery | 25% | `body.isConnected && body.recoveryScore != nil` | `recoveryScore` pass-through (0 if nil) |
| Nutrition | 25% | `fuel.isConnected && fuel.caloriesConsumed != nil` | `min(100, consumed/target*100)`, guarded for `target>0`; `max(0, base)` |
| Study | 25% | **always `true`** ("local data always available") | `target>0 ? min(100, minutes/target*100) : 100` |
| Movement | 25% | `move.isConnected` | `min(50, steps/target*50) + (workout==.completed ? 50 : 0)`, capped 100 |

Weight redistribution, `<2 available → nil`, NaN/Inf guard → `nil`, and `Int(round(clamped 0…100))` all match the spec.

> **Divergence from original spec:**
> - **No missed-meal penalty.** Spec's `penalty = missed_meals * 10` is **not implemented** — nutrition raw is just `max(0, base)`.
> - **Study is always "available".** `studyAvailable = true` unconditionally, so study never triggers redistribution and a zero-study day still counts as a real source.
> - **"Available" for movement = `move.isConnected`**, not the spec's "returned ≥1 non-nil primary value for today". A connected source with all-nil values is still counted.

### 2.4 Data Formatting Rules

Suffix/format helpers exist as `formatted*` computed properties on the quadrant structs (`formattedRecovery`, `formattedCalories`, etc.) and `DashboardViewModel.formattedDailyScore`. Numeric value changes use SwiftUI's `.contentTransition(.numericText())`.

> **Divergence from original spec:** No bespoke counter-roll `TimelineView` animation, no per-value stale yellow tint, and no verified full relative-timestamp ladder ("Just now / Xm ago / Yesterday HH:mm / MMM d") across every value. The header date/time/last-sync line refreshes via `TimelineView(.everyMinute)` (`DashboardView.headerRow()`); per-value counter rolls from the spec are not built.

---

## 3. Main Dashboard View

### 3.1 Screen Architecture

`DashboardView` is a vertical `ScrollView` inside a `NavigationStack`. Section order top → bottom (per `DashboardView` body / `dashboardContent`):

```
+-------------------------------------+
|  Header row (greeting + meta + score pill)
|  Welcome banner  (only if setup incomplete)
|  Quadrant grid  (2x2)               |
|  Quick actions row (≤2 buttons)     |
|  Weather recommendation (if any)    |
|  Non-negotiables section            |
|  Insight row                        |
|  Arena quick-access card            |
+-------------------------------------+
```

> **Divergence from original spec:** There is **no separate centered Daily Score section** between header and grid (see §3.3), and the quick-actions / weather / arena-card rows are not in the original spec stack.

### 3.2 Header Bar

`DashboardView.headerRow()`. Layout: a leading `VStack` with the **greeting** (`Font.tempoTitle2`, `vm.greeting`) on line 1, and a `TimelineView(.everyMinute)` meta line on line 2 containing date · time · (optional weather) · (optional last-sync), all `tempoCaption1/2` tertiary. Trailing: the **score pill** (see §3.3).

Settings gear and notification bell are **navigation-bar toolbar items** (`.toolbar` in `DashboardView`), each with `.accessibilityLabel`.

> **Divergence from original spec:**
> - Gear/bell are nav-bar toolbar items, **not** in-card 22pt buttons with an 8pt gap.
> - The bell has **no unread red-dot badge**.
> - The header carries extra **time / weather / last-sync chips** not in the spec.
> - The greeting is **priority-based copy from UX_COPY_BIBLE**, NOT the spec's 7 fixed time-range strings — see §11.

### 3.3 Daily Score Section

The daily score is rendered as a **compact tappable pill in the header row** (`DashboardView.headerRow()`): a 28pt `ScoreRingView` (strokeWidth 3) + the integer score in `Font.tempoDataMedium`. Tapping it presents `ScoreBreakdownSheet`.

`ScoreBreakdownSheet` (private struct in `DashboardView.swift`) shows an **80pt** `ScoreRingView` (strokeWidth 8), `"<score>/100"`, a "Daily Score" label, and per-component breakdown rows (Recovery / Nutrition / Study / Movement, each /25, with availability) driven by `vm.scoreBreakdown`.

> **Divergence from original spec:** Major. There is **no centered 100pt score ring section** with "Daily Score"/"Last sync" labels, top gap, angular gradient zones, or count-up `TimelineView` below the header. The big ring exists only at **80pt inside the tap-through breakdown sheet**, not 100pt on the main screen.

> **Status: NOT IMPLEMENTED — score ring state machine.** No "Calculating…", "Syncing…", "Connect more sources", "Sync failed — pull to retry", or dashed offline-ring states. When `vm.dailyScore == nil` the pill simply does not render.

### 3.4 Quadrant Grid

`DashboardView.quadrantGrid()` — a 2-column `LazyVGrid` (`GridItem(.flexible())`, `TempoSpacing.cardGap`). Each tile is a `NavigationLink(.plain)` to its detail view. Tiles are built by `bodyCard()`, `moveCard()`, `fuelCard()`, `mindCard()` wrapped in a shared `cardShell(label:)`. The fuel tile is wrapped in a `TimelineView(.everyMinute)` whose `NavigationLink` destination is computed by `fuelDestination(vm:now:)` (prep-window aware).

**Grid order in code: BODY, MOVE, FUEL, MIND.**

> **Divergence from original spec:** Spec required **BODY, FUEL, MIND, MOVE**. Actual order is **BODY, MOVE, FUEL, MIND**. Tiles use `.buttonStyle(.plain)` — no press-scale `ButtonStyle`, no per-quadrant stale-border overlay.

#### 3.4.1 BODY quadrant — IMPLEMENTED

`DashboardView.bodyCard()`. When connected (`data.isConnected` or `services.whoop.connectionState == .connected`): recovery value in `Font.tempoXPDisplay` tinted by `data.recoveryZone?.color`, mini-metrics for HRV / RHR / Sleep, and a strain indicator. When disconnected: `connectPrompt(...)` to connect Whoop.

#### 3.4.2 FUEL quadrant — DIVERGED

`DashboardView.fuelCard()`. When a `data.nextMeal` exists: renders `NextMealCardView(meal:style:.compact)` + a divider + a slim calorie progress strip (`formattedCalories` / `formattedCalorieTarget` kcal). Fallback (no plan): macro-summary path via `fuelCardMacroRing(...)`. Disconnected: `connectPrompt(...)`.

> **Divergence from original spec:** This is a meal-plan-aware design driven by the app's separate nutrition module — **not** the spec's 52pt calorie ring + 3 stacked macro bars + "X/Y meals" bottom row.

#### 3.4.3 MIND quadrant — IMPLEMENTED

`DashboardView.mindCard()`. Study minutes, progress, exam countdown, streak — backed by real local SwiftData.

#### 3.4.4 MOVE quadrant — IMPLEMENTED

`DashboardView.moveCard()` with `workoutStatus` cases (completed/planned/restDay/none), steps + active calories, steps progress; `connectPrompt(...)` when HealthKit not connected.

> **Status: NOT IMPLEMENTED — per-device metric adjustments** (SE RHR-hide, P/C/F vs full words, exam-truncation lengths). No size-class branching anywhere in the grid.

> **Status: NOT IMPLEMENTED — per-quadrant loading shimmer.** Only a full-screen `DashboardLoadingView` exists; there are no independent per-quadrant skeleton placeholders.

> **Divergence from original spec — quadrant error states:** Only disconnected (`connectPrompt`) states exist per quadrant. Sync-failed / pull-to-retry / per-quadrant last-sync timestamp is **not** built; error handling is dashboard-wide via `ErrorStateView`.

### 3.5 Non-Negotiables Bar

`DashboardView.nonNegotiablesSection()` + `nonNegotiablePill()`. When `vm.nonNegotiablesTotal > 0`: a header (`"<done>/<total> done"` + open/closed lock icon tinted success when all done), a 4pt progress bar (`vm.nonNegotiableProgress`, success vs signal color), and a horizontal row of pills (`ForEach(vm.nonNegotiables)`), each a checkmark/circle + title with strikethrough when completed. Empty state: lock icon + "Set your non-negotiables" + "Daily commitments you won't break" + an "Add" button opening `showNonNegotiableSetup`.

> **Divergence from original spec:** Pills are **read-only display** — no tap-to-toggle, no haptics, no long-press Edit/Remove menu. No reward name in the header ("PS5 locked"), no "locked/unlocked" text label, no all-complete confetti/particle burst + success haptic, and a plain `HStack` (no `FlowLayout` wrap). Empty-state copy differs from the spec's.

### 3.6 Quick Insights Banner

`DashboardView.insightRow()` renders a rule-based insight (bulb icon, text, chevron). Tapping it presents `InsightDetailSheet`. Insights are produced by `DashboardViewModel.generateAllInsights()` (low-recovery, sleep-nutrition, recovery-training, sleep-study, streak rules) and rotated by an index, with a dot indicator that advances rotation on tap.

> **Divergence from original spec:** Tap opens an `InsightDetailSheet`, **not** the Patterns view (which does not exist — see §6). No swipe-left per-day dismiss flag; rotation is index-based, not the §10.4 day-of-week schedule.

### 3.7 Pull-to-Refresh

`DashboardView` uses SwiftUI's stock `.refreshable { … }` (native system spinner).

> **Divergence from original spec:** The custom 60pt-threshold pull indicator / custom ring is **not** implemented.

### 3.9 Load Choreography

> **Status: NOT IMPLEMENTED.** There is no staggered per-section appear animation in `dashboardContent`. Sections appear together. `TempoAnimation.staggerCard` is defined but unused here.

---

## 4. Expanded Quadrant Views

### 4.1 Expansion Transition

Each quadrant pushes its detail screen via a plain `NavigationLink` push.

> **Status: NOT IMPLEMENTED — matchedGeometry morph.** No `@Namespace`/`matchedGeometryEffect`, no corner-radius/geometry morph, no content cross-fade. Standard navigation push only.

### 4.2 Body Expanded View — PARTIAL / STUBBED DATA

`Views/Dashboard/BodyQuadrantDetailView.swift`. Real structure: recovery trend chart (Swift Charts), `recoveryQuip`, recovery-trend section, sleep breakdown, strain breakdown, historical comparison (incl. SpO2).

> **Stub / placeholder data — documented as such:** The 7-day recovery trend is a **hardcoded array** (`trendData` literal `scores: [58, 65, 72, 55, 78, 68, 72]` — see the `// Stub 7-day trend data` comment in `BodyQuadrantDetailView`). Sleep data is also a hardcoded stub (`// Stub sleep data`), including a literal `"In bed: 11:15 PM → 6:45 AM"`. These render real-looking charts but are **not** real Whoop history.

> **Divergence from original spec:** No 7D/30D/90D segmented selector.

### 4.3 Fuel Expanded View — DIVERGED

`Views/Dashboard/FuelQuadrantDetailView.swift` (+ `FuelQuadrantDetailContainer.swift`). A fuel detail view exists but is built around the app's separate nutrition/meal-plan module.

> **Divergence from original spec:** Not the spec's calorie-ring-hero + macro-%-of-calories + 7-day bar chart + compliance% layout. Different design entirely, owned by the nutrition module.

### 4.4 Mind Expanded View — IMPLEMENTED (real data)

`Views/Dashboard/MindQuadrantDetailView.swift`. Uses real `@Query StudySession` data, real `studyQuip`, today's-sessions and upcoming-exams sections, study trend chart (Swift Charts).

> **Divergence from original spec:** No 7D/30D/90D selector.

### 4.5 Move Expanded View — IMPLEMENTED (real data)

`Views/Dashboard/MoveQuadrantDetailView.swift`. **Rebuilt to use real data:** completed workouts come from `@Query<WorkoutPlan>` filtered to `statusRaw == "completed"` (newest first, **no seed/stub array**). The Heart Rate section loads the most recent completed session's HR via `services.healthKit.fetchWorkouts(for:)` into `lastSessionAvgHR: Double??` with three states: not-loaded (`—`), loaded-with-value ("Last session avg: N bpm"), loaded-no-data ("No HR data recorded"). Includes activity stats, step-pace projection, and weekly volume (weight-unit aware via `@Query UserSettings`).

> **Audit correction (audit was stale here):** The doc-audit flagged a hardcoded `workoutHistory` literal array and a stub `heartRateData` generator. **Neither exists in current code** — this view now reads real `@Query WorkoutPlan` data and real HealthKit `HKWorkout` HR. This section is genuinely IMPLEMENTED on real data.

> **Divergence from original spec:** No 7D/30D/90D selector; no live HR streaming (post-session summary only — by design, no Apple Watch dependency).

---

## 5. Weekly Report View

`Views/Dashboard/WeeklyReportView.swift` is a complete UI scaffold: `overallScoreRing`, `miniScoreGrid`, per-quadrant `sectionCard`, `aiInsightsSection`, `weekOverWeekSection`, and a `WeeklyReportData` model.

> **Status: NOT IMPLEMENTED — the report never populates.** `loadReport()` is a stub: `// TODO: Fetch from API via services.apiClient` — it sleeps 500ms and sets `isLoading = false`. It never constructs `WeeklyReportData`, so the view **always shows the empty state**. No data ever renders.

> **Status: NOT IMPLEMENTED — report access, share, week navigation.** No Sunday-8PM notification scheduling, no header-date-tap → report navigation, no `ImageRenderer`/`ShareLink`/`UIActivityViewController` (no 1080×1920 share image), and no previous/next-week controls or week-offset state.

---

## 6. Pattern / Correlation View

> **Status: NOT IMPLEMENTED.** There is no Patterns/Correlation screen and no Pearson-correlation engine anywhere in the app target. The §3.6 insight row's chevron does **not** lead here (it opens `InsightDetailSheet`). A future build would need: a correlation engine over historical quadrant data, a time-range selector, and the strong-correlations / behavioral-patterns / recommendations screen.

---

## 7. Daily Timeline View

> **Status: NOT IMPLEMENTED.** No daily-timeline screen exists. (`TimelineView` references in code are SwiftUI's built-in `TimelineView(.everyMinute)` used for header/fuel-tile ticking — not the spec's time-stamped event timeline with a NOW divider.) A future build would need an event model aggregating cross-domain events plus the scrollable timeline UI.

---

## 8. Quick Actions

The dashboard's quick actions are a **static vertical button list** (`DashboardView.quickActionsRow()`): up to ~2 buttons from `vm.quickActions`, each routing to a target tab (with a special-case meal-logging sheet), followed by an optional weather-recommendation banner. A separate `arenaQuickAccessCard()` links to the Arena tab.

> **Status: NOT IMPLEMENTED — FAB fan-out & long-press menus.** A `TempoFAB` component exists at `Views/Shared/Components/TempoFAB.swift` but is **not used on the dashboard**. There is no floating action button, no fan-out expansion, no dimming overlay, and no `.contextMenu`/long-press on quadrant cards.

---

## 9. Widget Specifications

`TempoWidget/`: `TempoWidget.swift` (`struct WidgetData`, `TempoTimelineProvider`, `TempoLockScreenWidget` declared with `.supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])`) and `TempoWidgetViews.swift` (`SmallWidgetView`, `MediumWidgetView`, `LargeWidgetView`).

> **Status: NOT IMPLEMENTED — the widget data pipeline.** `WidgetData.fromDefaults()` reads `UserDefaults(suiteName: "group.app.tempo.Tempo")`, **but the app target never writes to that App Group and never calls `WidgetCenter.reloadAllTimelines()`** (verified: no `WidgetCenter`/`reloadTimelines`/App-Group-write references anywhere in `Tempo/Tempo`). Widgets therefore render only `WidgetData.placeholder` (previews) or zeroed defaults. The widget UI is built; the data feed is not.

> **Divergence from original spec:** Single `.widgetURL("tempo://dashboard")` on all sizes — no per-quadrant `tempo://dashboard/body|fuel|mind|move` tap regions, and no app-side handler for these URLs anyway (see §14). No per-device sizing tables. Lock-screen widget is declared but lacks the spec's distinct accessoryCircular/Rectangular/Inline layouts.

---

## 10. AI Insights Engine

> **Status: NOT IMPLEMENTED — the cross-domain Claude AI engine.** Dashboard insights are **100% local rule-based** (`DashboardViewModel.generateAllInsights()`). There is no Claude API call, no backend payload, and no §10.4 schedule for dashboard insights. (`RecoveryAIInsightService` exists but is recovery-module specific, not this cross-domain engine.)

What exists instead — rule-based generation (the only path): `generateAllInsights()` produces low-recovery, sleep↔nutrition, recovery↔training, sleep↔study, and streak insights from current quadrant values, rotated in the §3.6 insight row. No "[offline insight]" badge; not derived from a pattern engine (§6 doesn't exist).

---

## 11. Drill Sergeant Voice System

Quip pools exist in specific places: greeting (`DashboardViewModel.greetingForCurrentTime(firstName:)`), `recoveryQuip` (`BodyQuadrantDetailView`), `studyQuip` (`MindQuadrantDetailView`), `workoutQuip` (`MoveQuadrantDetailView`).

The greeting is **priority-based** (not 7 fixed time strings): Priority 1 low-recovery (<40) → "Recovery is low…"; P2 streak ≥14 → "<N>-day streak…"; P3 deload week → "Deload week…"; P4 training context (planned/completed/restDay copy from `move.workoutName`); P5 poor sleep (<6.5h); P6 high recovery (≥80); time-of-day is only a fallback.

> **Divergence from original spec:** Greeting copy and selection diverge from the spec's 7 fixed strings — it follows UX_COPY_BIBLE priority logic. Not implemented: date-seeded `SeededRandomNumberGenerator` selection (§11.10), score-context long-press tooltip quips (§11.3), non-negotiable quips (§11.8), special-scenario quips (§11.9).

---

## 12. First-Time User Experience

`DashboardView` shows `WelcomeBannerView` gated on `!hasCompletedSetup`. `WelcomeBannerView` is a "Welcome to Tempo" onboarding banner: connect-source step cards (e.g. "Connect Whoop" with completion checkmarks), a remaining-steps count ("One more step to go."), and a "Skip for now" button. The whole banner hides once all steps are done.

> **Status: NOT IMPLEMENTED — Day 0/1/7 progressive matrix.** The specific Day0/Day1/Day7 quadrant state matrix, the "Let's get started" first-greeting override, the no-stagger-on-first-launch rule, and progressive-richness unlock indicators (§12.4) are not built (and depend on the missing patterns/insights features).

---

## 13. Offline Mode & Stale Data

A `NetworkMonitor` exists at `Utilities/Helpers/NetworkMonitor.swift` and is referenced in `App/ServiceContainer.swift`.

> **Status: NOT IMPLEMENTED — dashboard offline/stale UX.** The dashboard does **not** consume `NetworkMonitor` (no offline references in `DashboardView`). There is no offline banner (no `wifi.slash`), no per-source stale indicators (yellow dot / stale timestamp / pulsing critical / card border), and no `CachedDashboardData` SwiftData model or App-Group cache write. The only persisted dashboard state is `DailyScoreEntry` (score-history sparkline only — see §16).

---

## 14. Notification Deep-Links

> **Status: NOT IMPLEMENTED.** There is no `onOpenURL` / `tempo://` deep-link handler in the app or dashboard (the only URL handling is `WhoopService` OAuth). No `QuadrantRoute`/`DeepLink` types, no scroll-to-section + highlight on deep-link, no cold/warm-launch routing. Widget `tempo://dashboard` URLs have no receiver.

---

## 15. Accessibility

Implemented: the two toolbar buttons have `.accessibilityLabel` ("Notifications", "Settings") in `DashboardView`.

> **Status: NOT IMPLEMENTED — the rest of §15.** No composed quadrant-card accessibility labels/values/hints, no `.updatesFrequently`, no stale announcements. No Dynamic-Type single-column grid switch at xxLarge. No `accessibilityReduceMotion` handling. Color-contrast (WCAG AA) and Bold-Text support are design-token assertions, not independently verifiable from code.

---

## 16. Performance Budget

Implemented: only the daily-score sparkline is cached/persisted via `DailyScoreEntry` (`loadScoreHistory`/`persistDailyScore` in `DashboardView`). Zero raster images — the dashboard uses only SF Symbols (`Image(systemName:)`) and SwiftUI shapes (IMPLEMENTED per §16.2).

> **Status: NOT IMPLEMENTED — full caching strategy.** No cache-first full-dashboard render (no `CachedDashboardData`), no widget timeline pre-compute pipeline, no chart-path caching.

---

## 17. Error Handling Matrix

Implemented: dashboard-wide `ErrorStateView` (sync failed + retry) and the daily-score NaN/Inf guard → `nil` ("--") in `DashboardViewModel.computeDailyScore()`.

> **Status: NOT IMPLEMENTED — the per-row error matrix.** Per-row 401-reconnect, 429-backoff-yellow-timestamp, HK-denied-opens-Settings, offline-cached fallback, and the in-app notification banner behaviors are not built. Error handling is dashboard-wide only.

---

*End of as-built description. Reconciled to code on 2026-05-19. Where this doc and the source disagree, the source is authoritative — fix the doc, not the code, unless the divergence is itself the bug.*
