# MODULE_RECOVERY — "RecoverIQ" Recovery Module

> **Module**: Recovery (RecoverIQ)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Views/Recovery/RecoveryTodayView.swift`
- `Tempo/Tempo/Views/Recovery/RecoveryTabView.swift`, `SleepDetailView.swift`, `StrainDetailView.swift`, `RecoveryTrendsView.swift`, `WeeklyRecoverySummaryView.swift`, `WhoopConnectionView.swift`, `RecoveryAIInsightView.swift`
- `Tempo/Tempo/ViewModels/RecoveryViewModel.swift`
- `Tempo/Tempo/Services/Engines/RecoveryEngine.swift`
- `Tempo/Tempo/Services/Recovery/RecoveryAIInsightService.swift`

---

## Table of Contents

1. [Design Philosophy & Principles](#1-design-philosophy--principles)
2. [Information Architecture & Navigation](#2-information-architecture--navigation)
3. [Design Tokens & Shared Components](#3-design-tokens--shared-components)
4. [Screen 1: Recovery Today View](#4-screen-1-recovery-today-view)
5. [Screen 2: Sleep Detail View](#5-screen-2-sleep-detail-view)
6. [Screen 3: Strain Detail View](#6-screen-3-strain-detail-view)
7. [Screen 4: Recovery Trends View](#7-screen-4-recovery-trends-view)
8. [Screen 5: Prescription Engine — Algorithm](#8-screen-5-prescription-engine)
9. [Screen 6: Whoop Connection Status](#9-screen-6-whoop-connection-status)
10. [Screen 7: Recovery Notifications](#10-screen-7-recovery-notifications)
11. [Screen 8: Historical Comparison](#11-screen-8-historical-comparison)
12. [Accessibility & Edge Cases](#12-accessibility--edge-cases)
13. [Data Formatting Rules](#13-data-formatting-rules)
14. [Animation Specifications](#14-animation-specifications)

---

## 1. Design Philosophy & Principles

> **Aspirational — no code surface.** The original §1 (core thesis, design principles, target user, calibration-period narrative, "HRV is individual", data-limitations essay, emotional goals) is design philosophy with no enforced representation in code. Two of its load-bearing promises are **not built**: the **14-day calibration gate** (no-prescription days 1-7, conservative 8-13, personalized 14+) is absent from `RecoveryEngine` (see §8, §12), and the **medical-disclaimer / scope-of-recommendations** copy is not rendered on any recovery surface (see §4.4, §4.7a, §8.2). Treat the original §1 prose as product intent, not a code contract.

---

## 2. Information Architecture & Navigation

### Module Entry Point

`RecoveryTabView` — root is a `NavigationStack` with the generic app `.tempoSettingsToolbar()` and a `RecoveryViewModel` constructed on first appear from `services.whoop / recoveryEngine / calendar`.

### Screen Hierarchy & Navigation Pattern

`RecoveryTabView.recoveryContent` uses a **segmented `Picker`** (`RecoveryTab.allCases`: Today / Sleep / Strain / Trends) that switches the body between `RecoveryTodayView`, `SleepDetailView`, `StrainDetailView`, `RecoveryTrendsView`.

> **Divergence from original spec:** The spec defined Today as the root screen with Sleep / Strain / Trends **pushed onto the NavigationStack** via tappable teaser cards. Actual code uses a **top segmented control** to switch screens in-place. `RecoveryTodayView.quickInsightsSection` *also* carries `NavigationLink`s to the same `SleepDetailView` / `StrainDetailView` / `RecoveryTrendsView`, so the same screens are reachable two ways (segment + push) — navigation is doubled and inconsistent with the spec's single push model.

### Gear → Whoop Connection

> **Divergence from original spec:** The toolbar is the **generic app settings toolbar** (`.tempoSettingsToolbar()`), not a recovery-specific gear that pushes `WhoopConnectionView`. `WhoopConnectionView` exists but is not reachable from a recovery-screen gear.

### Pull-to-Refresh — IMPLEMENTED

`RecoveryTodayView` uses SwiftUI's stock `.refreshable { await viewModel.refresh(modelContext:) }`.

---

## 3. Design Tokens & Shared Components

> **Divergence from original spec:** The original §3 re-specified the full color palette, typography scale, spacing constants, and a shared-component catalog. These are **not recovery-specific** — recovery views consume the same app-wide tokens documented as ground truth in `MODULE_DASHBOARD.md §1` (asset-catalog colorsets via `Color+Tempo.swift`, system-relative `Font+Tempo.swift`, `TempoSpacing/TempoRadius/TempoAnimation` enums in `DesignTokens.swift`). Recovery uses `Color.tempoRecoveryGreen/Yellow/Red` (+ `…Bg`), `ScoreRingView`, `TempoSectionHeader`, `TempoLineChart`, `.tempoShadow(.card)`. Read the asset catalog / `DesignTokens.swift` for ground-truth values; not duplicated here.

> **Status: NOT IMPLEMENTED — shared `FeedbackMechanism` component (original §3.5).** No thumbs-up/down feedback component is wired into any recovery screen (see §4.6).

---

## 4. Screen 1: Recovery Today View

`RecoveryTodayView` — a vertical `ScrollView` (indicators hidden). Section order top → bottom (per `body`):

```
+-------------------------------------+
|  Hero recovery ring + comparison + date
|  Recovery Analysis card (recoveryExplanation)
|  "What Drove Your Score" (HRV/RHR/Sleep vs 30d)
|  Key Metrics row (HRV/RHR/SpO2/Temp)
|  Health Alerts (activeAnomalies, if any)
|  Legacy Warnings (prescription.warnings, if any)
|  RecoveryAIInsightView (Last Week + Today's Read)
|  Quick Insights (Trends/Sleep/Strain teasers)
+-------------------------------------+
```

> **Divergence from original spec:** The spec's stack (hero → Key Metrics → **5-card Today's Prescription** → Quick Insights → Feedback → Sync timestamp → Footer disclaimer) is **not** what's built. The prescription cards, feedback, sync timestamp, and footer disclaimer are absent; "Recovery Analysis", "What Drove Your Score", "Health Alerts", and `RecoveryAIInsightView` are additions not in the original spec.

### 4.1 Navigation Bar

Covered by §2. Generic settings toolbar; no recovery gear.

### 4.2 Hero Section — Recovery Ring — IMPLEMENTED (data) / DIVERGED (animation)

`RecoveryTodayView.heroSection`: a 200pt `ScoreRingView` (strokeWidth 14) with a blurred zone-color glow, zone-tinted via `viewModel.recoveryZone`, plus `viewModel.comparisonText` and a `TimelineView(.everyMinute)` date label (`weekday(.wide).month(.wide).day()`). Score counts up from 0 on appear / on `todayRecovery.recoveryScore` change.

> **Divergence from original spec:** Count-up uses `.easeOut(duration: 1.0)`, **not** the spec's `.spring(response: 0.8, dampingFraction: 0.7)` over 1.2s. `comparisonText` (`RecoveryViewModel`) covers the core "vs 30-day average" cases incl. "Your first recovery day!" / "Right at your average", but the spec's "Waiting for Whoop to process…" pulsing state and "(X days ago)" historical suffix are not built.

### 4.3 Key Metrics Row — PARTIAL

`RecoveryTodayView.metricsRow`: four tiles (HRV / RHR / SpO2 / Temp) via `metricTile`, each with an optional `vs avg` arrow from `baselineIndicator(for:)`. Tap presents `MetricTrendSheet` (`.medium` detent) — a 7-day `TempoLineChart` + Min/Avg/Max over `viewModel.recentRecoveries.suffix(7)`.

> **Divergence from original spec:** Tap opens a **medium sheet with a 7-day chart**, not the spec's in-place tile expand. Baseline coding is a single binary vs-avg arrow — no good/concerning/normal 3-state, no "Building your baseline…" calibration gate, no SpO2 1-decimal trend, no skin-temp "+0.3 °C vs avg" phrasing.

### 4.4 Today's Prescription Section

> **Status: NOT IMPLEMENTED — the 5-card prescription UI.** `RecoveryEngine.generatePrescription` produces a real `DailyPrescription` (`trainingRec`, `trainingDetail`, `nutritionRecs`, `bedtimeTarget`, `caffeineCutoff`, `hydrationTargetMl`, `warnings`) — see §8 — but `RecoveryTodayView` **renders only `prescription.warnings`** (`warningsSection`). The Training / Meal / Bedtime / Caffeine / Hydration cards, the "Why this recommendation?" reasoning sheet, and the per-card medical disclaimer do **not** exist on this screen. The prescription is functionally replaced by `RecoveryAIInsightView` (a single AI paragraph, see §4.5a). The engine's structured output is computed, persisted, and then discarded by the UI.

> **App Store compliance gap:** The spec required a medical/scope disclaimer on this prescriptive surface (original §4.4 / §8.2 callout). No disclaimer is rendered anywhere a recommendation appears. This is an unmet App Store medical-disclaimer requirement, flagged again in §4.7a and §8.2.

### 4.5 Quick Insights Section — PARTIAL

`RecoveryTodayView.quickInsightsSection`: up to three `NavigationLink` teaser cards — Recovery Trends (`avgRecovery7d`), Last Night's Sleep (`formattedSleepHours` + score), Today's Strain (`formattedStrain` + calories). Each is a plain text+chevron card.

> **Divergence from original spec:** Text lines only — no Trends mini-sparkline, no sleep-stage mini-bar, no strain proportion bar, no 7-day-avg delta arrow.

### 4.5a Recovery Analysis, Score Breakdown, Health Alerts, AI Read — IMPLEMENTED (additions)

Not in the original spec but present and functional:
- **Recovery Analysis** (`recoveryExplanationSection`): zone-tinted card rendering `viewModel.recoveryExplanation`.
- **What Drove Your Score** (`scoreBreakdownSection`): HRV / RHR / Sleep rows vs 30-day baselines (`hrvDelta/hrvBaseline30d`, `rhrDelta/rhrBaseline30d`, `sleepDelta/sleepNeededHours`) with directional arrows.
- **Health Alerts** (`anomalyWarningsSection`): renders `viewModel.activeAnomalies` (critical vs non-critical color), shown only when non-empty.
- **`RecoveryAIInsightView`**: a Haiku-generated daily paragraph ("Today's Read") plus a Monday-only "Last Week" recap, cached per calendar day by `RecoveryAIInsightService` (`cachedParagraph` → no API call on re-appear). A `#if DEBUG`-only regenerate button (each tap = a paid Haiku call; release builds rely on the per-day cache as cost control). Empty state: "Connect WHOOP to get today's personalised read."

### 4.6 Feedback Section

> **Status: NOT IMPLEMENTED.** No thumbs-up/down "Was today's prescription helpful?" mechanism (no `FeedbackMechanism`) on the Today screen.

### 4.7 Sync Timestamp

> **Status: NOT IMPLEMENTED.** No "Last synced: N min ago" on the Today screen. A `lastSyncText` exists only in `WhoopConnectionView`.

### 4.7a Recovery Module Footer Disclaimer

> **Status: NOT IMPLEMENTED.** No always-visible medical-disclaimer footer ("…not medical advice… Learn More") on the Today screen. **App Store compliance gap** — the only disclaimer-adjacent string anywhere is the score<34 "consider consulting a healthcare professional" sentence inside an engine warning (§8, §12).

### 4.8 Loading State

> **Status: NOT IMPLEMENTED — spec'd shimmer/ring-track.** `RecoveryTabView` shows only a bare `ProgressView()` until the view model exists. `RecoveryTodayView` has no `loadState` branch. The only skeleton is `RecoveryAIInsightView.loadingSkeleton`, scoped to the AI card alone.

### 4.9 Error State (No Whoop Data)

> **Status: NOT IMPLEMENTED.** `RecoveryLoadState.error` exists in `RecoveryViewModel` but `RecoveryTodayView` never renders an error branch — no "Couldn't load your recovery data", no reconnect/try-again buttons.

### 4.10 Partial Data State

> **Status: NOT IMPLEMENTED.** No "Based on partial data:" prefix or partial-data handling in any recovery view.

---

## 5. Screen 2: Sleep Detail View

`SleepDetailView`.

### 5.1 Sleep Score Ring — IMPLEMENTED
`sleepScoreSection` — SLEEP-labelled ring with sleep-specific zones.

### 5.2 Sleep Stages Section — IMPLEMENTED
`sleepStagesBar` / `barSegment` / `stageTile` — stacked stage bar + Awake/Light/Deep/REM tiles.

### 5.3 Sleep Needed Breakdown — PARTIAL
`sleepDebtSection` exists but is the sleep-debt-payback view, **not** the spec'd line-item table (baseline / +debt / +strain / −naps / total / actual / deficit). No nap subtraction line.

### 5.4 Sleep Metrics Grid — PARTIAL
`sleepMetricsGrid` / `sleepMetricCell` present (Consistency / Respiratory Rate / Efficiency / Disturbances). Full wiring of all four (esp. disturbances, subject to model field availability) not confirmed.

### 5.5 Sleep Trend Chart — PARTIAL
`sleepTrendSection` chart present; the spec'd 7/14/30D range pills are not confirmed in this section.

### 5.6 Bedtime Consistency Chart

> **Status: NOT IMPLEMENTED.** No bedtime-consistency scatter chart in `SleepDetailView`.

### 5.7 Nap Tracking Section

> **Status: NOT IMPLEMENTED.** No nap-tracking section in `SleepDetailView`.

---

## 6. Screen 3: Strain Detail View

`StrainDetailView`.

### 6.1 Strain Gauge — IMPLEMENTED
`strainGaugeSection`.

### 6.2 Heart Rate Zones

> **Status: NOT IMPLEMENTED — 6-zone duration bars.** `heartRateSection` / `hrMetricCard` render avg/max HR cards only; no per-zone (Zone 1–6) duration bar chart.

### 6.3 Strain Breakdown — PARTIAL
`strainClassification` / `strainColor` — classification text only, not the spec'd breakdown.

### 6.4 Calories Breakdown — PARTIAL
`caloriesSection` / `caloriesRow` present; spec'd active/basal split not confirmed (single value likely).

### 6.5 Heart Rate Metrics — IMPLEMENTED
`heartRateSection` (avg/max HR).

### 6.6 24-Hour Heart Rate Timeline

> **Status: NOT IMPLEMENTED.** No 24-hour HR timeline.

### 6.7 Strain Trends — IMPLEMENTED
`strainTrendSection`.

### 6.8 Strain vs Recovery Correlation Insight — PARTIAL
The correlation logic exists in `RecoveryEngine.detectHighStrainPattern` and surfaces in the **Trends** insights list, **not** as a dedicated correlation card on the Strain screen.

---

## 7. Screen 4: Recovery Trends View

`RecoveryTrendsView`.

### 7.1 Time Range Selector — PARTIAL
`timeRangePicker` present; exact options vs spec's 7/14/30/90D (the `TrendRange` enum) not fully confirmed.

### 7.2 Multi-Line Chart — IMPLEMENTED
`chartSection` / `chartData` / `legendRow` — Recovery / HRV / RHR series with toggles.

### 7.3 Pattern Insights Cards — IMPLEMENTED (real algorithms)
`insightsSection` backed by `RecoveryEngine.detectTrends` → `detectHRVDecline` (3+ consecutive HRV-decline days), `detectRecoveryTrend` (>10% half-vs-half shift, ≥7 days), `detectSleepInconsistency` (std-dev > 1h, ≥5 days), `detectHighStrainPattern` (≥3 high-strain/low-recovery days). These are genuine computed insights over `[DailyRecovery]`, each with a `confidence` value.

> **Divergence from original spec:** Implements ~4 of the spec's 6 pattern templates. Not built: explicit sleep-recovery-correlation and day-of-week consistency phrasings as spec'd; no "X days to return to average" recovery-latency insight.

### 7.4 Calendar Heatmap

> **Status: NOT IMPLEMENTED.** No calendar heatmap.

### 7.5 Best & Worst Days — PARTIAL
Exists as `WeeklyRecoverySummaryView.bestWorstSection`, **not** on the Trends view as spec'd.

### 7.6 Day-of-Week Pattern Analysis

> **Status: NOT IMPLEMENTED.** No day-of-week pattern analysis.

---

## 8. Screen 5: Prescription Engine — Algorithm

`RecoveryEngine` (`RecoveryEngineProtocol`). **This is a real algorithm, not hardcoded output.** `generatePrescription(recovery:schedule:)` consumes live Whoop-derived `DailyRecovery` (`recoveryScore`, `sleepDebt`, `sleepHours`, `sleepEfficiency`, `strain`, `sleepScore`, `hrvRmssd`) plus `[CalendarEvent]` and returns a `DailyPrescription`.

> **Status: NOT IMPLEMENTED — calibration gate.** The spec's "<7 days → no prescription, 7–13 → conservative, 14+ → personalized" gate is absent. `generatePrescription` always generates regardless of data history (`daysOfWhoopData` does not exist here). See §1, §12.

### 8.1 Input Data Model — PARTIAL
Inputs are real Whoop-derived values. **Missing inputs** vs the spec'd `PrescriptionInputs`: spo2/skinTemp, sleepConsistency, deep/REM hours, yesterdayCalories, 30-day averages, hrvTrend7d, consecutive-day counts, ambient temp/humidity, NutriTrack remaining macros. **Hardcoded placeholders:** `bodyWeightKg: 80` and `wakeTimeMinutes: 420` (7:00 AM) are passed as literals with `// will use UserProfile/UserSettings when available` comments — not user data.

### 8.2 Training Prescription Algorithm — PARTIAL
`generateTrainingPrescription`: real 6-tier zone map (85–100→5 peakGreen, 67–84→4 green, 50–66→3 upperYellow, 34–49→2 lowerYellow, 20–33→1 upperRed, else→0 red), then downgrade modifiers — **D** poor sleep (<6h or efficiency <75%), **E** sleep debt >4h, **C** football tomorrow caps at zone 3 — with a hard floor at zone 0. Each zone yields a specific headline + body with sleep/debt/strain context strings.

> **Safety invariant — IMPLEMENTED:** zones 0–1 prescribe only full rest / active recovery; minimum zone is 0. Never recommends structured training through red.

> **Divergence from original spec:** Missing Modifier A (HRV-trend-declining + consecutive low recovery), Modifier B (≥2 consecutive high-strain days), the football-48h tier (only "tomorrow" cap exists), and Modifier F (WBGT/heat overlay + sunscreen). **No "Why this recommendation?" sheet and no medical disclaimer wired** — App Store compliance gap (see §4.4, §4.7a).

### 8.3 Nutrition Prescription Algorithm — PARTIAL
Inline rules in `generatePrescription`: low recovery (<50) → protein; poor sleep (`sleepScore`<70 or `sleepHours`<6) → magnesium foods; planned training → pre-workout carbs; football today → high-carb pre-kickoff (inserted first); empty → balanced-meals fallback.

> **Divergence from original spec:** No expectedStrain estimator, no bodyweight-scaled protein/carb grams, no pre-workout timing window, no NutriTrack remaining-protein rule, no priority sort, no nutrition disclaimer. Strings are simpler than the spec's rules 1–7.

### 8.4 Sleep Prescription Algorithm — PARTIAL
`generateSleepPrescription`: real — baseline 7.5h + `min(sleepDebt, 1h)` repayment + strain adjustment (15/30 min by yesterday strain band) + 30-min debt acceleration when debt >2h; bedtime = wake − need − 15-min onset buffer; caffeine cutoff = bedtime − 8h.

> **Divergence from original spec:** Wake time hardcoded 7:00 AM (§8.1). Caffeine buffer fixed at 8h (no Settings 6/8/10/12h option), no screen cutoff, no debt-context tiers.

### 8.5 Hydration Prescription Algorithm — PARTIAL
`generateHydrationTarget`: real — 35 ml/kg base + 500 ml if planned training + 250 ml if recovery <50 + another 250 ml if <30.

> **Divergence from original spec:** Body weight hardcoded 80 kg (§8.1). No heat/humidity (Miami) adjustment, no per-hour activity scaling, no breakdown string — returns a single `Int` ml.

### 8.6 Prescription Confidence Level

> **Status: NOT IMPLEMENTED.** No `PrescriptionConfidence` enum and no confidence field on `DailyPrescription`. (The `confidence` values in `RecoveryEngine` belong to `RecoveryInsight` trend detection, unrelated to prescription confidence.)

### 8.7 Prescription Persistence & Timing — PARTIAL
`RecoveryViewModel.refresh` generates a `DailyPrescription` and inserts it into SwiftData.

> **Divergence from original spec:** Regenerates on **every pull-to-refresh** — no "once per day / don't change mid-day" guard and no "show yesterday's prescription until today's data is available" fallback.

---

## 9. Screen 6: Whoop Connection Status

`WhoopConnectionView`.

### 9.1 Connection States — PARTIAL
`statusText` handles Connected / "Not Connected" (+ a DEMO badge). No distinct Syncing or Error visual state, no error-code mapping (401/429/500/network), no troubleshooting expander.

### 9.2 Data Freshness Table

> **Status: NOT IMPLEMENTED — stub.** `dataPreviewSection` hardcodes **every** row (Recovery / Sleep / Strain / HRV / SpO2 / Skin Temp) to the literal string `"Available"` with a static checkmark. There is no per-category Fresh/Stale/Missing logic and no real timestamps.

### 9.3 Sync Now Button — PARTIAL
`syncButton` exists; transient "Synced!" / "Sync Failed" states and a 60s cooldown are not confirmed.

### 9.4 Account Section — PARTIAL
Disconnect button + confirmation dialog present. No Whoop account-email row / open-Whoop-app link (a credential-setup flow exists instead).

---

## 10. Screen 7: Recovery Notifications

> **Status: NOT IMPLEMENTED.** None of §10.1's recovery notifications exist: Morning Recovery Report, Low Recovery Alert (timeSensitive, <34%), Sleep Debt Warning, Post-Workout Protein Reminder, Caffeine Cutoff Reminder. The only adjacent APIs are generic accountability notifications — `scheduleMorningBriefing` (the Lockdown briefing, not a recovery-score report) and `scheduleBedtimeReminder(time:)` (a generic reminder **not** driven by the prescription's computed bedtime, no "Bedtime in 30 minutes" recovery copy, no Set Alarm/Snooze actions). §10.2's 6 recovery-specific toggles with defaults are not confirmed in the generic `NotificationSettingsView`. §10.3's recovery in-app banner component does not exist.

---

## 11. Screen 8: Historical Comparison

> **Status: NOT IMPLEMENTED as spec'd.** There is no dedicated Historical Comparison screen and no "Compare" nav-bar button. `RecoveryTrendsView.weeklySummaryLink` pushes `WeeklyRecoverySummaryView`, which **partially overlaps** but is a different screen: it has §11.1-adjacent week-over-week deltas (`RecoveryViewModel.WeeklyStats` avg recovery/HRV/RHR/sleep + `prevWeek*`, shown as arrow tiles in `trendArrowsSection`) and a Best/Worst section (§7.5) — but **not** the spec'd 4-column This-Week-vs-Last-Week table with Strain & Consistency rows + "Overall: Improving" sentence. §11.2 Monthly Average 12-month chart, §11.3 Personal Records (90-day, NEW badge), and §11.4 Your Recovery Profile (NL strengths/areas with 30-day gate) are entirely absent. (`RecoveryAIInsightService` produces a daily paragraph + a Monday weekly recap — not the spec'd structured profile.)

---

## 12. Accessibility & Edge Cases

> **Status: NOT IMPLEMENTED — most of §12.** No custom `.accessibilityLabel`s on the ring/tiles/charts/cards in `RecoveryTodayView` (default SwiftUI a11y only), no audio-graph traits. No explicit Reduce Motion handling (the count-up always runs). No color-blind pattern setting. No no-Whoop onboarding card — `RecoveryTodayView` always renders `heroSection`; when disconnected `RecoveryViewModel.refresh` skips the Whoop fetch but the UI shows an empty ring rather than a "Connect your Whoop to get started" card. None of the spec'd edge-case strings ("Was your Whoop charged", "recently changed timezones", "Day 1!", calibration-day messaging) exist.

> **Partial — professional-consultation advisory:** `RecoveryEngine` adds a single text warning when `score < 34` mentioning "consider consulting a healthcare professional", rendered via `RecoveryTodayView.warningsSection`. The spec's 4-condition trigger logic (7-day red streak, RHR streak, sleep<5h streak, workout failure), the visually-distinct non-dismissible banner with an acknowledgment gate, and the 7-day re-appear cycle are **not** built. App Store compliance gap.

> **IMPLEMENTED — zone boundary correctness:** `RecoveryEngine` zone tiers (67–84 green, 50–66 upperYellow, 34–49 lowerYellow) and `RecoveryZone(score:)` match the spec's boundaries (34→yellow, 67→green). Tempo font tokens scale with Dynamic Type; `RecoveryZone` carries a text label.

---

## 13. Data Formatting Rules

### 13.1 / 13.2 Number & Date Formatting — PARTIAL
`RecoveryViewModel` provides `formattedHRV/RHR/SpO2/SkinTemp/SleepHours/SleepScore/Strain/Calories/Bedtime/CaffeineCutoff/Hydration`; date label uses `.dateTime.weekday(.wide).month(.wide).day()`. Most formatters exist; spec'd exact per-field suffixes and relative sync-time / "MMM d–d" range are not all verified, and the relative sync time is not shown on the Today screen.

### 13.3 / 13.4 Locale & Unit Preferences

> **Status: NOT IMPLEMENTED.** No recovery locale/unit preference settings — no °C/°F, 12/24h, or L/oz toggles; no locale-aware thousands/decimal-separator handling specific to recovery.

---

## 14. Animation Specifications

> **Status: NOT IMPLEMENTED — most of §14.** Screen transitions are default SwiftUI `NavigationStack`/sheet animations, not the spec'd custom springs. The hero ring animates with `.easeOut(duration: 1.0)`, **not** the spec's `.spring(response: 0.8, dampingFraction: 0.7)` 1.2s (§4.2). No staggered card appearance, no spec'd shimmer sweep (only `RecoveryAIInsightView.loadingSkeleton`), no stages-bar grow animation. **No haptic feedback** anywhere in the recovery views (no `UIImpactFeedbackGenerator` / `.sensoryFeedback`). Scroll: indicators hidden (`showsIndicators: false`); no `LazyVStack` for charts, no tab-icon scroll-to-top.

---

*End of as-built description. Reconciled to code on 2026-05-19. Where this doc and the source disagree, the source is authoritative — fix the doc, not the code, unless the divergence is itself the bug.*
