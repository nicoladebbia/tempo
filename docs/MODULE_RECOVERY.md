# RecoverIQ — Recovery Module UX Specification

**Module Codename:** RecoverIQ
**App:** Tempo (iOS, SwiftUI)
**Version:** 1.0
**Last Updated:** 2026-03-24
**Author:** Tempo Design Team

---

## Table of Contents

1. [Design Philosophy & Principles](#1-design-philosophy--principles)
2. [Information Architecture & Navigation](#2-information-architecture--navigation)
3. [Design Tokens & Shared Components](#3-design-tokens--shared-components)
4. [Screen 1: Recovery Today View (Main Screen)](#4-screen-1-recovery-today-view)
5. [Screen 2: Sleep Detail View](#5-screen-2-sleep-detail-view)
6. [Screen 3: Strain Detail View](#6-screen-3-strain-detail-view)
7. [Screen 4: Recovery Trends View](#7-screen-4-recovery-trends-view)
8. [Screen 5: Prescription Engine — Full Algorithm Specification](#8-screen-5-prescription-engine)
9. [Screen 6: Whoop Connection Status](#9-screen-6-whoop-connection-status)
10. [Screen 7: Recovery Notifications](#10-screen-7-recovery-notifications)
11. [Screen 8: Historical Comparison](#11-screen-8-historical-comparison)
12. [Accessibility & Edge Cases](#12-accessibility--edge-cases)
13. [Data Formatting Rules](#13-data-formatting-rules)
14. [Animation Specifications](#14-animation-specifications)

---

## 1. Design Philosophy & Principles

### Core Thesis

Recovery data is useless if it stays as numbers. RecoverIQ exists to close the gap between "I know my recovery is 45%" and "I know exactly what to do about it." Every screen must answer one question: **"So what do I do?"**

### Design Principles

1. **Prescription over information.** Every data point must connect to an action. If a metric cannot drive a recommendation, it is secondary.
2. **Glanceable, then deep.** The first 2 seconds on any screen deliver the headline. Depth is progressive — tap to reveal, never forced.
3. **Color is communication.** Green/yellow/red is the universal language of this module. Users should know their state from the color alone, before reading a single number.
4. **Honest, not anxious.** A red recovery day is not an emergency. The tone is a calm coach: direct, specific, encouraging. Never guilt-inducing.
5. **Context makes data useful.** A number without comparison is noise. Every metric shows: current value, trend vs yesterday, trend vs personal average.

### Target User Profile

Active male, mid-20s. Trains 4-5x/week (gym + football). Wears a Whoop 4.0 24/7. Checks recovery every morning but often ignores the data because Whoop tells him *what* but not *what to do*. Wants a coach in his pocket that synthesizes recovery, sleep, strain, and nutrition into a single daily game plan.

### Medical Disclaimer & Scope of Recommendations

> **IMPORTANT — This module touches health and must be medically responsible.**
>
> Tempo is a **wellness and fitness tool**, not a medical device. All recovery prescriptions are informational and educational. They do not constitute medical advice, diagnosis, or treatment. Users should consult a qualified healthcare provider before making changes to their exercise, nutrition, or sleep habits — particularly if they have pre-existing conditions, take medication, or experience unusual symptoms.
>
> **Supplement disclaimer:** Any mention of dietary supplements (magnesium, tart cherry juice, etc.) in prescriptions is for informational purposes only. These statements have not been evaluated by the Food and Drug Administration (FDA). Supplements are not intended to diagnose, treat, cure, or prevent any disease. Users should consult a healthcare provider before starting any supplement regimen.
>
> **Wearable data disclaimer:** Recovery scores, HRV readings, and sleep metrics from Whoop are estimates derived from optical sensor data — they are not clinical-grade measurements. They should be interpreted alongside subjective self-assessment and should never replace professional medical testing or evaluation.

This disclaimer text must appear in the Recovery module footer (always visible at bottom of Recovery Today View) and must be accessible from every PrescriptionCard's "Why this recommendation?" sheet.

### Calibration Period — First 14 Days

The prescription engine requires a **14-day calibration period** after initial Whoop connection before issuing personalized prescriptions. During this period:

1. **Days 1-7:** No prescriptions generated. The app displays: "We're learning your body's patterns. Generic wellness tips will appear here until we have 7 days of data. Wear your Whoop consistently to speed this up."
2. **Days 8-13:** Conservative prescriptions using population-average baselines. Confidence indicator: `.low`. A banner displays: "Your prescriptions are improving. [N] more days until fully personalized."
3. **Day 14+:** Full personalized prescriptions using the user's own 14-day baseline for HRV, RHR, sleep need, and recovery distribution. Confidence: `.medium` (upgrades to `.high` at 30+ days).

**Why 14 days:** Whoop's own onboarding documentation recommends 14 days of consistent wear to establish reliable baselines. HRV has high day-to-day variability (Plews et al., 2012); a minimum of 14 data points is needed to compute a meaningful rolling average and standard deviation for individual baseline detection. Prescriptions issued before this period would be based on population norms, which are clinically unreliable for individual decision-making (see "HRV Is Individual" below).

### HRV Is Individual — No Population Norms

**Critical clinical principle:** HRV is highly individual. A resting HRV of 40ms may be entirely normal and healthy for one person, while 80ms is normal for another. Absolute HRV values are meaningless without individual context. Tempo must NEVER compare a user's HRV to population averages or classify an absolute HRV value as "good" or "bad."

All HRV interpretation in this module uses:
- **Personal 30-day rolling baseline** (mean and standard deviation of lnRMSSD)
- **Deviation from personal baseline** (measured in standard deviations)
- **7-day trend direction** (improving, stable, declining)
- **7-day coefficient of variation** (per Flatt & Esco, 2016 — CV > 10% flags autonomic disturbance)

This is consistent with the approach in EXERCISE_SCIENCE.md Section 3.1 and Section 6.2.

### Data Limitations — What Whoop Data Cannot Tell You

The following limitations must be acknowledged in the prescription engine's "Why?" reasoning panels whenever relevant:

1. **HRV confounders:** HRV is affected by alcohol consumption, caffeine intake, acute illness, psychological stress, menstrual cycle, certain medications (beta-blockers, stimulants), and measurement conditions — not just training load. A single low-HRV day does not necessarily indicate physical fatigue. The app should note in reasoning: "HRV can be influenced by factors beyond training — including alcohol, stress, illness, and caffeine."

2. **Single-day noise:** One bad recovery score does not warrant major behavioral changes. Recovery scores on any single day are noisy. **Trends over 7+ days are far more clinically meaningful than any individual reading.** The prescription engine already uses modifiers that require multi-day patterns (e.g., "consecutive low recovery days >= 2"), which is correct. The app should never use alarming language based on a single day's data.

3. **Whoop is not a medical device:** Whoop's optical heart rate sensor provides estimates of HRV, RHR, SpO2, and sleep staging. These are not equivalent to ECG-derived HRV, polysomnography-staged sleep, or pulse oximetry from medical devices. Accuracy varies with skin tone, fit, movement, and ambient conditions.

4. **Recovery score is a composite estimate:** Whoop's recovery score is a proprietary composite of HRV, RHR, sleep performance, and respiratory rate. The exact weighting is not published. Tempo adds value by contextualizing this score with additional modifiers (strain history, football schedule, sleep debt), but the underlying score inherits Whoop's measurement limitations.

### Emotional Design Goals

| Recovery Zone | Emotional Tone | Visual Tone | Language Tone |
|---|---|---|---|
| Green (67-100%) | Confident, energized | Bright, expansive | "You're primed. Let's go." |
| Yellow (34-66%) | Calm, strategic | Neutral, measured | "Solid base. Train smart today." |
| Red (0-33%) | Reassuring, protective | Muted, warm | "Your body is rebuilding. Honor it." |

**Note on zone thresholds (67% / 34%):** These boundaries align with Whoop's system for user consistency. They are pragmatic conventions, not clinically derived cutoffs — no peer-reviewed study establishes 67% or 34% as physiologically meaningful thresholds. They approximately divide the recovery distribution into thirds (see EXERCISE_SCIENCE.md Section 6.1). The real clinical value comes from the *modifier system* (Section 8.2), which layers evidence-based rules on top of these zones. The zones themselves are a communication framework, not a diagnostic tool. See EXERCISE_SCIENCE.md Section 9.3 for a confidence assessment of this approach.

---

## 2. Information Architecture & Navigation

### Module Entry Point

RecoverIQ lives as a primary tab in Tempo's tab bar. Tab icon: a heartbeat pulse line. Tab label: "Recover."

### Screen Hierarchy

```
Recovery Tab
├── Recovery Today View (main screen, default on tab tap)
│   ├── → Sleep Detail View (tap sleep card or sleep metrics)
│   ├── → Strain Detail View (tap strain card or strain metrics)
│   ├── → Recovery Trends View (tap "See Trends" or any trend sparkline)
│   ├── → Prescription Detail (tap any prescription card → sheet)
│   └── → Historical Comparison (tap "Compare" button in trends)
├── Whoop Connection Status (accessible from gear icon in nav bar)
└── Recovery Notifications (system-level, configured in Settings)
```

### Navigation Pattern

- **Primary navigation:** Vertical scroll on main screen. All secondary screens push onto a NavigationStack.
- **Back navigation:** Standard iOS back chevron, top-left. Swipe-right gesture enabled on all pushed views.
- **Sheet presentations:** Prescription reasoning, metric deep-dives, and feedback dialogs present as `.sheet` (half-height detent first, drag to full).
- **Tab bar:** Always visible except during full-screen chart interactions.

### Pull-to-Refresh

Available on all scrollable screens. Triggers a Whoop API sync. Shows a custom animation: the recovery ring briefly spins. If data is less than 5 minutes old, shows a toast: "Data is up to date" and does not re-fetch.

---

## 3. Design Tokens & Shared Components

### Color Palette

> **Design System alignment:** Recovery zone colors are aligned with `tempo.color.recovery.*` tokens from DESIGN_SYSTEM.md. Sleep stage colors are registered as `tempo.color.sleep.*`. HR zone colors and metric health colors extend the Design System as `tempo.color.recovery.zone.*` and `tempo.color.recovery.metric.*` tokens. Surface colors below are Recovery-specific dark mode values (approved module-specific theme).

```
// Recovery Zone Colors
recovery.green.primary    = #22C55E   (recovery >= 67) — token: tempo.color.recovery.green
recovery.green.bg         = #22C55E @ 12% opacity
recovery.yellow.primary   = #EAB308   (recovery 34-66) — token: tempo.color.recovery.yellow
recovery.yellow.bg        = #EAB308 @ 12% opacity
recovery.red.primary      = #DC2626   (recovery < 34) — token: tempo.color.recovery.red
recovery.red.bg           = #DC2626 @ 12% opacity

// Metric Health Colors (for individual metrics like HRV, RHR)
metric.good               = #22C55E   — uses tempo.color.recovery.green
metric.normal             = #A0AEC0   (gray, neutral)
metric.concerning         = #DC2626   — uses tempo.color.recovery.red

// Sleep Stage Colors
sleep.awake               = #FF6B6B
sleep.light               = #74B9FF
sleep.deep                = #0652DD
sleep.rem                 = #A29BFE

// HR Zone Colors (Whoop's 6 zones)
zone.1                    = #B8E6F0   (50-60% max HR)
zone.2                    = #74B9FF   (60-70%)
zone.3                    = #22C55E   (70-80%) — uses tempo.color.recovery.green
zone.4                    = #EAB308   (80-90%) — uses tempo.color.recovery.yellow
zone.5                    = #FF8C42   (90-95%)
zone.6                    = #DC2626   (95-100%) — uses tempo.color.recovery.red

// Surface & Text (Recovery module dark theme — approved exception, see Design System note above)
surface.primary           = #0D0D0D   — aligned with tempo.color.bg.primary (dark)
surface.card              = #1C1C1E   — aligned with tempo.color.surface.card (dark)
surface.cardElevated      = #2C2C2E   — aligned with tempo.color.surface.sheet (dark)
text.primary              = #F5F2ED   — aligned with tempo.color.text.primary (dark)
text.secondary            = #A1A1AA   — aligned with tempo.color.text.secondary (dark)
text.tertiary             = #8E8E93   — aligned with tempo.color.text.tertiary (dark)
divider                   = #38383A   — uses tempo.color.divider.default (dark)
```

### Typography Scale

```
.heroScore        = SF Pro Rounded, Bold, 72pt, tracking: -2
.heroLabel        = SF Pro Text, Medium, 15pt, tracking: 0.5, uppercase
.sectionTitle     = SF Pro Display, Bold, 28pt  // aligned with other modules
.cardTitle        = SF Pro Text, Semibold, 17pt
.cardBody         = SF Pro Text, Regular, 15pt
.metricValue      = SF Pro Rounded, Semibold, 28pt
.metricLabel      = SF Pro Text, Regular, 13pt, tracking: 0.3
.metricUnit       = SF Pro Text, Regular, 11pt
.prescriptionText = SF Pro Text, Medium, 16pt
.reasoningText    = SF Pro Text, Regular, 14pt, color: text.secondary
.trendDelta       = SF Pro Rounded, Medium, 13pt
.sparklineLabel   = SF Pro Text, Regular, 11pt
.tabLabel         = SF Pro Text, Medium, 10pt
.toast            = SF Pro Text, Medium, 14pt
.timestamp        = SF Pro Text, Regular, 12pt, color: text.tertiary
```

### Spacing & Layout Constants

```
screen.horizontalPadding  = 20pt   — uses tempo.space.screen.edge
card.padding              = 16pt   — uses tempo.space.card.padding
card.cornerRadius         = 16pt   — uses tempo.radius.3xl
card.spacing              = 12pt  (vertical gap between cards) — uses tempo.space.card.gap
section.topPadding        = 24pt
metric.iconSize           = 20pt
metric.sparklineHeight    = 32pt
metric.sparklineWidth     = 80pt
ring.outerDiameter        = 200pt
ring.strokeWidth          = 14pt
ring.innerDiameter        = 172pt
chart.height              = 200pt
chart.barCornerRadius     = 4pt
statusBar.safeAreaTop     = dynamic (respect safe area)
tabBar.height             = 49pt (standard iOS; +34pt safe area on Face ID devices = 83pt total)
```

### Shared Components

#### 3.1 MetricTile

A reusable component for displaying a single health metric with trend.

```
┌─────────────────────┐
│  [icon]  HRV        │  ← metricLabel, text.secondary
│  68 ms              │  ← metricValue + metricUnit
│  ↑ 12% ──────────   │  ← trendDelta + sparkline (7 days)
└─────────────────────┘
```

**Props:**
- `icon`: SFSymbol name (e.g., `waveform.path.ecg`)
- `label`: String (e.g., "HRV")
- `value`: Double, formatted per data rules
- `unit`: String (e.g., "ms")
- `trend`: Enum — `.up(percentage)`, `.down(percentage)`, `.stable`
- `trendColor`: green if trend is favorable direction, red if unfavorable, gray if stable
- `sparklineData`: [Double] — last 7 values
- `sparklineColor`: matches trend color
- `healthStatus`: Enum — `.good`, `.normal`, `.concerning`

**Layout:**
- Width: flexible, fills available space in HStack/LazyVGrid
- Height: 88pt
- Background: `surface.card`
- Corner radius: 12pt
- Internal padding: 12pt

**States:**
- **Default:** As described above.
- **Tapped:** Background brightens to `surface.cardElevated`. Haptic: `.light`. Expands to show 7-day sparkline chart inline (animated, 0.3s spring).
- **Loading:** Value shows as `--` with a shimmer animation. Sparkline shows a flat gray line.
- **Unavailable:** Value shows as `--`. Label shows "No data." No sparkline. Gray tint over entire tile.
- **Expanded:** Below the main content, a 7-day mini chart (height: 80pt) slides in. X-axis: day abbreviations (M, T, W, T, F, S, S). Y-axis: auto-scaled. Current day highlighted with a dot. Tap again or tap another tile to collapse.

**Trend Arrow Logic:**
- Up arrow (SF Symbol: `arrow.up.right`): current value > yesterday's value by > 2%
- Down arrow (`arrow.down.right`): current value < yesterday's value by > 2%
- Stable dash (`minus`): within +/- 2%
- Percentage shown: `abs((today - yesterday) / yesterday * 100)`, rounded to nearest integer, displayed as "↑ 12%" or "↓ 5%" or "— stable"

**Trend Color Logic (metric-specific):**
| Metric | Up = | Down = |
|---|---|---|
| HRV | Green (higher is better) | Red |
| RHR | Red (lower is better) | Green |
| SpO2 | Green (higher is better) | Red |
| Skin Temp | Context-dependent* | Context-dependent* |

*Skin Temp: deviation > 0.5C from 7-day average in either direction = yellow. Within 0.5C = gray (stable). > 1.0C deviation = red.

#### 3.2 PrescriptionCard

A card displaying one actionable recommendation.

```
┌──────────────────────────────────────────────┐
│  🏋️  Training                                │
│  ─────────────────────────────────────────── │
│  Full send — compound lifts and PRs are OK   │
│  today. Your recovery supports high volume.  │
│                                              │
│  [Why this recommendation?]     chevron.right│
└──────────────────────────────────────────────┘
```

**Props:**
- `icon`: String (emoji or SFSymbol)
- `category`: String (e.g., "Training", "Nutrition", "Sleep", "Hydration", "Caffeine")
- `headline`: String — bold, one-line summary (e.g., "Full send — heavy training OK")
- `body`: String — 1-2 sentence elaboration
- `reasoning`: String — hidden, shown on tap of "Why this recommendation?"
- `priority`: Enum — `.primary`, `.secondary`, `.tertiary` (affects sort order and visual weight)

**Layout:**
- Width: `screen width - (2 * screen.horizontalPadding)` = full bleed within padding
- Min height: 100pt. Grows with content.
- Background: `surface.card`
- Corner radius: `card.cornerRadius` (16pt)
- Internal padding: `card.padding` (16pt)
- Icon: 24pt, leading, vertically centered with category label
- Category label: `cardTitle`, same line as icon, 8pt gap from icon
- Divider: 1pt line, `divider` color, 8pt vertical margin
- Headline: `prescriptionText`, `text.primary`
- Body: `reasoningText`, `text.secondary`, 4pt below headline
- "Why this recommendation?" link: bottom of card, `reasoningText`, tinted `recovery.[zone].primary`
- Chevron: trailing, vertically centered with "Why" link, `text.tertiary`

**States:**
- **Default:** As described.
- **Tapped (on "Why" link):** Opens a `.sheet` with medium detent (50% screen height). Sheet contains: the recommendation repeated at top, then a detailed explanation of every factor that went into the recommendation. Factors listed as bullet points with the data values that triggered them. Example: "Your recovery is 78% (green zone). Your HRV is 68ms, which is 12% above your 30-day average. Yesterday's strain was 12.4, which is moderate. No football scheduled today. Result: full training volume is appropriate."
- **Loading:** Headline shows "Generating your prescription..." with a pulsing dot animation. Body is hidden. Background has a subtle shimmer.
- **Error:** Headline shows "Couldn't generate this prescription." Body: "Check your Whoop connection." Tapping the card opens Whoop Connection Status.
- **Feedback submitted:** After user rates, a small checkmark appears next to the category label. Subtle green flash on appear.

#### 3.3 TrendChart

A shared charting component for line/bar charts.

**Props:**
- `data`: [(Date, Double)] — array of data points
- `chartType`: `.line`, `.bar`, `.area`
- `color`: Color
- `showXAxis`: Bool
- `showYAxis`: Bool
- `xAxisFormatter`: (Date) -> String
- `yAxisFormatter`: (Double) -> String
- `highlightToday`: Bool
- `overlayLines`: [(label: String, data: [(Date, Double)], color: Color)] — for multi-line charts
- `timeRange`: `.week`, `.twoWeeks`, `.month`, `.quarter`
- `interactionMode`: `.scrub` (drag to see values), `.tap` (tap a point to see value), `.none`

**Layout:**
- Width: fills container
- Height: `chart.height` (200pt)
- X-axis labels: `sparklineLabel`, `text.tertiary`
- Y-axis labels: `sparklineLabel`, `text.tertiary`
- Grid lines: `divider` color, 0.5pt, dashed

**Interaction — Scrub Mode:**
- Long press on chart activates scrub mode. Haptic: `.medium` on activation.
- Drag finger horizontally. A vertical rule line (1pt, white @ 50% opacity) follows the finger.
- Above the rule line, a floating tooltip shows: date (formatted as "Mon, Mar 18") and value (formatted per data rules).
- Tooltip background: `surface.cardElevated`, corner radius: 8pt, padding: 8pt.
- On release: rule line and tooltip fade out (0.2s).
- While scrubbing, the header value (if linked) updates in real-time to match the scrubbed point.

**Empty State:**
- If data array is empty or has < 2 points: show a dashed horizontal line at the midpoint of the Y-axis range, with a label centered: "Not enough data yet. Check back after a few days."
- Text: `reasoningText`, `text.tertiary`.

#### 3.4 RecoveryRing

The circular gauge used to display recovery score.

**Structure:**
- Outer track: full 360-degree circle, `surface.card` color (the "empty" track), stroke width: `ring.strokeWidth` (14pt).
- Fill track: partial arc from 12 o'clock position, clockwise, filling `recovery_score / 100` of the circle. Color: `recovery.[zone].primary`. Stroke cap: `.round`.
- Inner content (centered inside ring):
  - Score number: `heroScore` (72pt), color: `recovery.[zone].primary`
  - Label below number: "RECOVERY" in `heroLabel`, `text.secondary`
- Ring diameter: `ring.outerDiameter` (200pt)

**Animation on Load:**
- Ring fill animates from 0% to actual value over 1.2 seconds.
- Easing: `.spring(response: 0.8, dampingFraction: 0.7)` — slight overshoot and settle.
- Score number counts up from 0 to actual value in sync with ring fill. Number uses a `Text` with `.contentTransition(.numericText())` modifier.
- Color transitions smoothly if the fill crosses a zone boundary during animation (e.g., passes through red, yellow, then settles in green).

**Glow Effect:**
- A soft radial glow behind the ring, color-matched to the zone, radius: 120pt, opacity: 15%.
- In dark mode (always dark in Tempo), this creates a subtle halo effect.

#### 3.5 FeedbackMechanism

"Was this prescription helpful?" interaction.

```
┌──────────────────────────────────────────────┐
│  Was today's prescription helpful?            │
│                                              │
│  [👍 Helpful]    [👎 Not helpful]             │
│                                              │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  Optional: What would you change?            │
│  ┌────────────────────────────────────────┐  │
│  │ Free text input...                     │  │
│  └────────────────────────────────────────┘  │
│                        [Submit]              │
└──────────────────────────────────────────────┘
```

**Trigger:** Appears at the bottom of the Recovery Today View after 6:00 PM local time, only if the user has viewed the prescription at least once today. Does not appear if already submitted today.

**Props:**
- `date`: Date — the day being rated
- `prescriptionId`: UUID — links feedback to the specific prescription set
- `rating`: Enum — `.helpful`, `.notHelpful`, `nil`
- `freeText`: String? — optional

**Layout:**
- Full-width card, `surface.card`, corner radius: 16pt
- Title: `cardTitle`, "Was today's prescription helpful?"
- Buttons: Two buttons side by side, each 50% width minus 4pt gap.
  - Unselected: border 1pt `divider`, transparent fill, `text.secondary` text
  - Selected helpful: fill `recovery.green.bg`, border `recovery.green.primary`, text `recovery.green.primary`
  - Selected not helpful: fill `recovery.red.bg`, border `recovery.red.primary`, text `recovery.red.primary`
  - Button height: 44pt. Corner radius: 10pt.
- Divider: dashed, 1pt, `divider`, 12pt vertical margin. Only shown after a button is selected.
- Free text field: shown only after a button is selected. TextEditor, 3 lines visible, `surface.cardElevated` background, corner radius: 8pt, placeholder text: "What would you change?", `text.tertiary`.
- Submit button: trailing-aligned below text field. Capsule shape, `recovery.[zone].primary` fill, white text, height: 36pt, horizontal padding: 24pt. Disabled (opacity 0.4) until a rating is selected.

**States:**
- **Pre-6PM / Not yet viewed prescription:** Hidden entirely. Zero height.
- **Shown, no interaction:** Both buttons unselected. Free text hidden.
- **Rating selected:** Selected button styled. Free text area slides in (0.3s). Submit button appears.
- **Submitted:** Entire card collapses to a single line: "Thanks for your feedback!" with a checkmark. 0.3s animation. Remains visible until user scrolls past.
- **Already submitted today:** Card shows collapsed "Thanks" state on load.

---

## 4. Screen 1: Recovery Today View

This is the main screen of the RecoverIQ module. It is the first thing the user sees when they tap the Recover tab. It must deliver three things within 3 seconds: (1) how recovered am I, (2) what should I do, (3) what are the details.

### Full Screen Layout (Top to Bottom)

```
┌──────────────────────────────────────────────────┐
│ status bar                                        │
├──────────────────────────────────────────────────┤
│ ◀ (hidden, root)    Recovery    ⚙️ (connection)   │  ← Navigation bar
├──────────────────────────────────────────────────┤
│                                                    │
│              ┌──────────────┐                      │
│              │              │                      │
│              │    ╭────╮    │                      │
│              │   │  78  │   │                      │  ← RecoveryRing
│              │   │RECOV.│   │                      │
│              │    ╰────╯    │                      │
│              │              │                      │
│              └──────────────┘                      │
│                                                    │
│         ↑ 12% above your average                   │  ← Comparison label
│         Monday, March 24                           │  ← Date label
│                                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ │
│  │ ♡ HRV    │ │ ♡ RHR    │ │ O₂ SpO2  │ │🌡Temp│ │  ← MetricTile row
│  │ 68 ms    │ │ 52 bpm   │ │ 97%      │ │36.8°C│ │
│  │ ↑ 12%    │ │ ↓ 3%     │ │ — stable │ │— stbl│ │
│  └──────────┘ └──────────┘ └──────────┘ └──────┘ │
│                                                    │
│  ── Today's Prescription ──────────────────────── │  ← Section header
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 🏋️  Training                               │   │
│  │ ────────────────────────────────────────── │   │
│  │ Full send — compound lifts and PRs OK.     │   │  ← PrescriptionCard
│  │ Your body is primed for high output.       │   │
│  │ [Why?]                            ›        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 🍽  Meal Timing                             │   │
│  │ ────────────────────────────────────────── │   │
│  │ Eat protein within 1h post-training.       │   │  ← PrescriptionCard
│  │ Extra 30g carbs — high strain expected.    │   │
│  │ [Why?]                            ›        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 🛏  Bedtime                                 │   │
│  │ ────────────────────────────────────────── │   │
│  │ Target: 10:30 PM                           │   │  ← PrescriptionCard
│  │ Sleep debt: 2.1h. Get 8.5h tonight.        │   │
│  │ [Why?]                            ›        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ ☕  Caffeine Cutoff                         │   │
│  │ ────────────────────────────────────────── │   │
│  │ No caffeine after 2:00 PM.                 │   │  ← PrescriptionCard
│  │ 8h buffer before your target bedtime.      │   │
│  │ [Why?]                            ›        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 💧  Hydration                               │   │
│  │ ────────────────────────────────────────── │   │
│  │ Target: 3.2L today.                        │   │
│  │ +500ml for planned training session.       │   │
│  │ [Why?]                            ›        │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Quick Insights ────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 📊 Recovery Trends        [See Trends ›]  │   │
│  │ 7-day avg: 71%  ↑ 4%                      │   │  ← Trends teaser
│  │ ▁▃▅▇▅▆▇                                   │   │     with mini sparkline
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 😴 Last Night's Sleep      [Details ›]    │   │
│  │ 7h 23m  •  Sleep Score: 82%               │   │  ← Sleep teaser
│  │ ██████████░░░ SWS: 1h42m  REM: 1h58m     │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 🔥 Yesterday's Strain     [Details ›]     │   │
│  │ 14.2  •  Calories: 2,847                  │   │  ← Strain teaser
│  │ ████████████████░░░░░                      │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Was today's prescription helpful?           │   │
│  │                                            │   │  ← FeedbackMechanism
│  │ [👍 Helpful]    [👎 Not helpful]           │   │     (after 6PM only)
│  └────────────────────────────────────────────┘   │
│                                                    │
│  Last synced: 2 min ago                           │  ← Sync timestamp
│                                                    │
│  (bottom padding: 32pt + tabBar.height)           │
└──────────────────────────────────────────────────┘
```

### 4.1 Navigation Bar

- **Style:** `.inline` display mode. Background: `surface.primary` (black), no blur. Transparent until user scrolls past the recovery ring, then solid black with a 0.5pt bottom border (`divider`).
- **Title:** "Recovery" — `sectionTitle`, centered.
- **Leading item:** None (this is the root view of the tab).
- **Trailing item:** Gear icon (SF Symbol: `gearshape`), 22pt, `text.secondary`. Tapping opens Whoop Connection Status (pushed onto NavigationStack).
- **Scroll behavior:** As user scrolls down and the recovery ring moves off-screen, the navigation bar title transitions to show the score inline: "Recovery · 78%" with a small colored dot matching the zone. This uses a custom `.toolbar` with an opacity transition tied to scroll offset.

**Compact Nav Title (appears when ring scrolls off-screen):**
```
◀    ● 78% Recovery    ⚙️
     ^
     green dot, 8pt diameter
```

### 4.2 Hero Section — Recovery Ring

**Position:** Centered horizontally. Top edge: 16pt below navigation bar.

**Component:** `RecoveryRing` (see 3.4).

**Recovery Score Display:**
- Score: integer, no decimals. Formatted as plain number (e.g., "78", not "78%").
- Font: `heroScore` (72pt).
- Color: matches zone (`recovery.[zone].primary`).
- Below score, inside ring: "RECOVERY" in `heroLabel` (15pt, uppercase, `text.secondary`).

**Comparison Label:**
- Positioned 8pt below the ring.
- Centered horizontally.
- Format: "[arrow] [X]% [above/below] your average"
- Arrow: `↑` if above, `↓` if below. Color: green if above, red if below.
- "your average" = 30-day rolling average of recovery scores.
- Font: `trendDelta` (13pt), `text.secondary` for the text, colored for the arrow and percentage.
- Example: "↑ 12% above your average" or "↓ 8% below your average"
- If today's score equals average (+/- 1%): "Right at your average"

**Date Label:**
- 4pt below comparison label.
- Format: "EEEE, MMMM d" (e.g., "Monday, March 24").
- Font: `timestamp` (12pt), `text.tertiary`.
- If viewing a past day (via historical navigation): shows that date, plus "(X days ago)" suffix.

**Edge Cases:**
- **No recovery data yet today (Whoop hasn't processed):** Ring shows at 0% fill, gray color. Score shows "--". Comparison label: "Waiting for Whoop to process your recovery..." Label pulses with a slow fade animation (1.5s cycle).
- **Recovery score is 0:** Ring shows at 0% fill (just the track), red color. Score shows "0". This is valid — extremely poor recovery.
- **First day of use (no average):** Comparison label: "Your first recovery day! We'll track trends from here."

### 4.3 Key Metrics Row

**Position:** 20pt below the date label.

**Layout:** Horizontal `ScrollView` with `.horizontal` axis, `.showsIndicators(false)`. Contains 4 `MetricTile` components in an `HStack` with 8pt spacing. Leading padding: `screen.horizontalPadding`. Trailing padding: `screen.horizontalPadding`.

Each tile width: `(screen.width - 40 - 24) / 4` on larger phones (iPhone Pro Max). On smaller phones (iPhone SE, iPhone mini): tiles are slightly wider, and the row scrolls horizontally with the 4th tile partially visible to hint at scrollability.

**Breakpoint:** If `screen.width < 390pt`, use scrollable HStack. If `>= 390pt`, use fixed-width LazyVGrid with 4 columns.

**Metric Tiles (left to right):**

**Tile 1: HRV**
- Icon: SF Symbol `waveform.path.ecg`
- Label: "HRV"
- Value: `hrv_rmssd_milli` from Whoop, rounded to nearest integer
- Unit: "ms"
- **Assessment is ALWAYS relative to the user's personal baseline, never population norms:**
  - Good: above user's 30-day rolling average (personal baseline)
  - Concerning: > 1 standard deviation below user's 30-day baseline (per Plews et al., 2012)
  - Normal: within 1 SD of personal baseline
- During calibration period (first 14 days): show value with no color coding. Label: "Building your baseline..."
- The "Why?" tooltip for this tile should state: "HRV is highly individual. Your baseline of [X]ms is unique to you. We compare today's reading to YOUR average, not population norms."

**Tile 2: Resting Heart Rate**
- Icon: SF Symbol `heart.fill`
- Label: "RHR"
- Value: `resting_heart_rate` from Whoop, rounded to nearest integer
- Unit: "bpm"
- Good: below user's 30-day average (lower RHR = better recovery)
- Concerning: above 30-day average by > 10%
- Normal: within 10% of average
- Note: trend arrow direction is inverted — down arrow is green (good), up arrow is red (bad)

**Tile 3: Blood Oxygen**
- Icon: SF Symbol `lungs.fill`
- Label: "SpO2"
- Value: `spo2_percentage` from Whoop, 0 decimal places
- Unit: "%"
- Good: >= 96%
- Normal: 94-95%
- Concerning: < 94%
- Note: SpO2 changes are usually very small. Trend percentage should use 1 decimal place for this metric (e.g., "↓ 0.5%").

**Tile 4: Skin Temperature**
- Icon: SF Symbol `thermometer.medium`
- Label: "Temp"
- Value: `skin_temp_celsius` from Whoop, 1 decimal place
- Unit: "°C"
- Assessment: deviation from 7-day rolling average
  - Within 0.5°C: normal (gray)
  - 0.5-1.0°C deviation: yellow (flag)
  - > 1.0°C deviation: red (concerning — possible illness)
- Trend: shows deviation from average, not yesterday comparison. Format: "+0.3°C vs avg" or "-0.2°C vs avg"

**Tap Interaction:**
- Tapping any MetricTile expands it in-place (see MetricTile 3.1, Expanded state).
- Only one tile can be expanded at a time. Expanding a tile collapses any previously expanded tile.
- The expansion pushes content below it downward with a spring animation.

### 4.4 Today's Prescription Section

**Section Header:**
- 24pt top margin from metrics row.
- "Today's Prescription" — `sectionTitle` (20pt, semibold).
- Leading-aligned within `screen.horizontalPadding`.
- A small colored dot (8pt, `recovery.[zone].primary`) precedes the text, 6pt gap.

**Prescription Cards Stack:**
- Vertical stack of `PrescriptionCard` components, 12pt spacing between cards.
- Cards appear in priority order (see Prescription Engine, Section 8).
- Standard priority order: Training > Meal Timing > Bedtime > Caffeine > Hydration.
- Each card uses the `PrescriptionCard` component (see 3.2).

**Card-Specific Details:**

**Card: Training Prescription**
- Icon: "🏋️" (emoji, not SF Symbol — more visually distinct)
- Category: "Training"
- Headline variations by zone:
  - Green (67-100%): "Full send — compound lifts and PRs are OK"
  - Green + high HRV: "Peak state — push your limits today"
  - Yellow (50-66%): "Moderate day — reduce volume 20%"
  - Yellow (34-49%): "Easy-moderate — maintain intensity, cut volume 30%"
  - Red (20-33%): "Easy day — mobility, stretching, or light cardio"
  - Red (0-19%): "Rest day — your body needs full recovery"
  - Red + declining HRV 3+ days: "Mandatory rest — HRV trending down, avoid all training"
- Body: 1-2 sentences expanding on the headline with specific guidance.
- Modifier overlays (appended to body text):
  - If football match within 24h: "Football match tomorrow — save your legs."
  - If football match within 48h: "Football in 2 days — keep today moderate."
  - If consecutive high strain (>14) for 2+ days: "You've pushed hard for [N] days straight. Prioritize recovery."

**Card: Meal Timing Prescription**
- Icon: "🍽"
- Category: "Meal Timing"
- Headline: dynamic based on context (examples below)
- Logic inputs: recovery zone, expected strain, workout timing, NutriTrack data
- Example headlines:
  - Pre-workout (training planned within 3h): "Eat 30-50g carbs 1-2h before training"
  - Post-workout: "Hit 30-40g protein within 1h after your session"
  - High strain expected: "Add 30g carbs to your pre-training meal"
  - Low recovery: "Prioritize protein today — aim for 2g/kg body weight"
  - Poor sleep last night: "Include magnesium-rich foods: dark leafy greens, nuts, seeds"
  - Football day: "High-carb meal 3-4h before kickoff. 1-1.5g/kg carbs."
- If NutriTrack data is available: reference actual macro numbers. "You've had 45g protein so far. Aim for 80g more today."
- If NutriTrack data is NOT available: give general guidance. "Aim for a palm-sized protein source at each meal."

**Card: Bedtime Prescription**
- Icon: "🛏"
- Category: "Bedtime"
- Headline: "Target: [HH:MM AM/PM]"
- Body: "Sleep debt: [X.X]h. Aim for [Y]h [Z]m tonight."
- Bedtime calculation: see Prescription Engine (Section 8, Sleep Prescription Logic).
- If sleep debt > 3h: body appends "You're carrying significant sleep debt. Prioritize an early night."
- If sleep debt < 0.5h: body changes to "Sleep debt is minimal. Maintain your current routine."
- Time format: 12-hour with AM/PM. No leading zero for hour. Examples: "10:30 PM", "11:15 PM", "9:45 PM".

**Card: Caffeine Cutoff**
- Icon: "☕"
- Category: "Caffeine Cutoff"
- Headline: "No caffeine after [H:MM PM]"
- Body: "8-hour buffer before your target bedtime."
- Calculation: `target_bedtime - 8 hours`. Example: bedtime 10:30 PM → cutoff 2:30 PM.
- If cutoff has already passed: headline changes to "Caffeine window has closed for today." Body: "Your target bedtime is [time]. Stick to water and herbal tea."
- If cutoff is within 1 hour: headline appends "(closing soon!)"
- Note: This card is relevant since the user does not drink coffee, but caffeine includes pre-workout supplements, energy drinks, tea, etc. Body should clarify: "This includes pre-workout, energy drinks, and tea."
- **Individual variation note:** The 8-hour default is based on Drake et al. (2013), which showed 400mg caffeine 6 hours before bed significantly disrupted sleep. We use 8 hours as a conservative buffer. However, caffeine metabolism varies significantly between individuals due to CYP1A2 gene polymorphisms — fast metabolizers (CYP1A2 *1A/*1A) clear caffeine in 4-5 hours, while slow metabolizers may need 10+ hours (Sachse et al., 1999). **The cutoff buffer must be user-adjustable in Settings > Recovery > Caffeine Sensitivity**, with options of 6h / 8h (default) / 10h / 12h. The "Why?" reasoning should state: "Default is 8 hours. If you find caffeine doesn't affect your sleep, you can shorten this. If you're sensitive to caffeine, extend it. Adjust in Settings."

**Card: Hydration Prescription**
- Icon: "💧"
- Category: "Hydration"
- Headline: "Target: [X.X]L today"
- Body: dynamic explanation of how the target was calculated.
- Example body: "Base: 2.5L + 500ml for training + 250ml for low recovery = 3.2L"
- If no training planned: "Base: 2.5L. No training adjustment needed today."
- Volume formatting: 1 decimal place, in liters. Example: "3.2L", "2.5L", "3.7L".
- **Miami climate note:** The base formula (35ml/kg, per Sawka et al., 2007) is a general guideline for temperate climates. In Miami's subtropical environment (avg. humidity 70-80%), sweat evaporation is impaired, meaning the body sweats MORE to achieve the same cooling effect. The heat adjustment in Section 8.5 (+500ml at >85F, +1L at >95F) partially addresses this, but the app should also factor humidity. **When humidity > 70% AND temperature > 80F, add an additional 250ml to the base target** even without planned training — this accounts for higher insensible fluid losses during daily activities in humid subtropical conditions. The "Why?" reasoning should explain: "Miami's high humidity reduces sweat evaporation, so your body works harder to cool itself. You lose more fluid even during routine activities."

### 4.5 Quick Insights Section

**Section Header:**
- 24pt top margin from last prescription card.
- "Quick Insights" — `sectionTitle`.
- Leading-aligned within `screen.horizontalPadding`.

**Three teaser cards in a vertical stack, 12pt spacing.**

**Card: Recovery Trends Teaser**
- Icon: "📊" (leading)
- Title: "Recovery Trends" — `cardTitle`
- Action: "See Trends ›" — trailing, `recovery.[zone].primary` color
- Line 1: "7-day avg: [XX]% [↑/↓ X%]" — average of last 7 recovery scores, compared to previous 7 days
- Line 2: Mini sparkline, 7 data points, height: 24pt, color: `recovery.[zone].primary`
- Tap: pushes Recovery Trends View onto NavigationStack.
- Background: `surface.card`, corner radius: 16pt, padding: 16pt.

**Card: Last Night's Sleep Teaser**
- Icon: "😴"
- Title: "Last Night's Sleep"
- Action: "Details ›"
- Line 1: "[Xh YYm] · Sleep Score: [ZZ]%"
- Line 2: Horizontal mini bar showing sleep stage proportions (awake/light/deep/REM). Height: 8pt, corner radius: 4pt. Full width of card minus padding.
- Below bar: "SWS: [Xh YYm]  REM: [Xh YYm]" in `sparklineLabel`, `text.secondary`.
- Duration formatting: hours and minutes, e.g., "7h 23m". If < 1 hour for a stage: just minutes, e.g., "42m".
- Tap: pushes Sleep Detail View.
- Color coding of sleep score: same green/yellow/red thresholds as recovery.

**Card: Yesterday's Strain Teaser**
- Icon: "🔥"
- Title: "Yesterday's Strain"
- Action: "Details ›"
- Line 1: "[XX.X] · Calories: [X,XXX]"
- Line 2: Horizontal bar showing strain as proportion of max (21). Height: 8pt, corner radius: 4pt. Fill color: gradient from zone.1 to zone.6 based on strain level.
- Strain formatting: 1 decimal place (e.g., "14.2"). Calories: integer with thousands separator (e.g., "2,847").
- Tap: pushes Strain Detail View.

### 4.6 Feedback Section

- Conditionally shown (see FeedbackMechanism 3.5 for rules).
- 12pt top margin from last quick insight card.
- Full `FeedbackMechanism` component.

### 4.7 Sync Timestamp

- 16pt below feedback card (or below quick insights if feedback is hidden).
- Centered text: "Last synced: [relative time]"
- Font: `timestamp` (12pt), `text.tertiary`.
- Relative time formatting: "Just now" (< 1 min), "2 min ago", "15 min ago", "1h ago", "3h ago". Never shows more than "24h ago" — if > 24h, shows "Over 24h ago — tap to sync" and text is tappable to trigger refresh.
- Bottom padding: 32pt below timestamp (ensures content clears tab bar).

### 4.7a Recovery Module Footer Disclaimer

Below the sync timestamp, always display a tappable disclaimer footer:

- Text: "Recovery data is an estimate, not a clinical measurement. [Learn More]"
- Font: `sparklineLabel` (11pt), `text.tertiary`.
- "Learn More" tappable text opens a sheet with the full medical disclaimer (see Section 1, "Medical Disclaimer & Scope").
- 8pt top margin from sync timestamp.
- This footer is ALWAYS visible — it does not conditionally hide.

### 4.8 Loading State (Full Screen)

When the screen loads for the first time or after a manual refresh:

```
┌──────────────────────────────────────────────────┐
│                                                    │
│              ┌──────────────┐                      │
│              │   ╭────╮     │                      │
│              │  │  --  │    │  ← Ring track visible │
│              │  │RECOV.│    │    but empty, pulsing │
│              │   ╰────╯     │                      │
│              └──────────────┘                      │
│                                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ │
│  │ ██████   │ │ ██████   │ │ ██████   │ │██████│ │  ← Shimmer placeholders
│  │ ██████   │ │ ██████   │ │ ██████   │ │██████│ │
│  └──────────┘ └──────────┘ └──────────┘ └──────┘ │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ ████████████████████████████████████████   │   │  ← Shimmer cards
│  │ ████████████████████                       │   │
│  └────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────┐   │
│  │ ████████████████████████████████████████   │   │
│  │ ████████████████████                       │   │
│  └────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

- Recovery ring: empty track visible, score shows "--", RECOVERY label visible. Ring has a slow clockwise rotation animation (subtle, 4s per rotation, opacity pulses 50%-100%).
- Metric tiles: shimmer rectangles matching tile dimensions. Standard iOS shimmer: a diagonal light band sweeping left-to-right, 1.5s cycle.
- Prescription cards: shimmer rectangles, 2-3 rows of varying width to suggest text.
- Duration: loading state shows for minimum 0.5s (to prevent flash) even if data returns instantly. Maximum: 10s before showing error state.

### 4.9 Error State (No Whoop Data)

If Whoop data fetch fails entirely:

```
┌──────────────────────────────────────────────────┐
│                                                    │
│              ┌──────────────┐                      │
│              │   ╭────╮     │                      │
│              │  │  ⚠️  │    │                      │
│              │  │      │    │                      │
│              │   ╰────╯     │                      │
│              └──────────────┘                      │
│                                                    │
│         Couldn't load your recovery data           │
│                                                    │
│    Check your Whoop connection and try again.      │
│                                                    │
│           [ Reconnect Whoop ]                      │
│           [   Try Again     ]                      │
│                                                    │
└──────────────────────────────────────────────────┘
```

- Ring: empty track, warning icon centered instead of score.
- Title: "Couldn't load your recovery data" — `cardTitle`, `text.primary`, centered.
- Subtitle: "Check your Whoop connection and try again." — `cardBody`, `text.secondary`, centered.
- Buttons: two vertically stacked.
  - "Reconnect Whoop": primary button, `recovery.green.primary` fill, white text, full width (minus 40pt padding), height: 50pt, corner radius: 12pt. Pushes Whoop Connection Status.
  - "Try Again": secondary button, transparent fill, `text.secondary` text with 1pt `divider` border, same dimensions. Triggers data refresh.
- Buttons: 12pt vertical spacing between them.

### 4.10 Partial Data State

If some Whoop data is available but not all (e.g., recovery processed but sleep not yet):

- Show available data normally.
- Missing data tiles/cards show their individual loading or unavailable states.
- Prescription engine runs with available data, noting reduced confidence: prescription headline prefixed with "Based on partial data: " in `text.tertiary`.

---

## 5. Screen 2: Sleep Detail View

Accessed by tapping the Sleep teaser card on Recovery Today View.

### Navigation

- Pushed onto NavigationStack.
- Back button: "< Recovery" (standard iOS back).
- Title: "Sleep" — `sectionTitle`, `.inline` display mode.
- No trailing nav items.

### Full Screen Layout

```
┌──────────────────────────────────────────────────┐
│ < Recovery          Sleep                ⚙️       │
├──────────────────────────────────────────────────┤
│                                                    │
│              ┌──────────────┐                      │
│              │   ╭────╮     │                      │
│              │  │  82  │    │                      │  ← Sleep Score Ring
│              │  │SLEEP │    │                      │
│              │   ╰────╯     │                      │
│              └──────────────┘                      │
│                                                    │
│     7h 23m asleep  ·  8h 05m in bed               │
│     Sleep Efficiency: 91.3%                        │
│                                                    │
│  ── Sleep Stages ──────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ ████ ████████████ ██████████ ████████      │   │  ← Stacked bar
│  │ Awake  Light        Deep       REM         │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ │
│  │ Awake    │ │ Light    │ │ Deep     │ │ REM  │ │
│  │ 32m     │ │ 3h 11m  │ │ 1h 42m  │ │1h58m │ │  ← Stage tiles
│  │ 7%      │ │ 43%     │ │ 23%     │ │ 27%  │ │
│  │ ● OK    │ │ ● High  │ │ ● Good  │ │● Good│ │
│  └──────────┘ └──────────┘ └──────────┘ └──────┘ │
│                                                    │
│  ── Sleep Needed Breakdown ────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Baseline need           7h 15m             │   │
│  │ + Sleep debt            +45m               │   │
│  │ + Yesterday's strain    +20m               │   │
│  │ - Naps                  -0m                │   │
│  │ ──────────────────────────────             │   │
│  │ Total needed            8h 20m             │   │
│  │ Actual sleep            7h 23m             │   │
│  │ ──────────────────────────────             │   │
│  │ Deficit                 -57m    ● Yellow   │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Sleep Metrics ─────────────────────────────── │
│                                                    │
│  ┌──────────────────┐ ┌──────────────────┐        │
│  │ Consistency      │ │ Respiratory Rate │        │
│  │ 78%              │ │ 15.2 br/min      │        │
│  │ ↑ 3%             │ │ — stable         │        │
│  └──────────────────┘ └──────────────────┘        │
│  ┌──────────────────┐ ┌──────────────────┐        │
│  │ Efficiency       │ │ Disturbances     │        │
│  │ 91.3%            │ │ 4                │        │
│  └──────────────────┘ └──────────────────┘        │
│                                                    │
│  ── Sleep Trends ──────────────────────────────── │
│                                                    │
│  [7D]  [14D]  [30D]                               │  ← Time range pills
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │         ╱╲    ╱╲                           │   │
│  │  ╱╲   ╱  ╲  ╱  ╲    ╱╲                   │   │  ← Sleep duration
│  │ ╱  ╲ ╱    ╲╱    ╲  ╱  ╲                  │   │     line chart
│  │╱    ╲            ╲╱    ╲                  │   │
│  │ M   T   W   T   F   S   S                │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Bedtime Consistency ───────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │  Target: 10:30 PM                          │   │
│  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │   │
│  │  •      •                 •                │   │  ← Scatter plot
│  │       •      •                  •          │   │     dots = actual
│  │                    •                       │   │     bedtimes
│  │  M   T   W   T   F   S   S                │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Nap Tracking ──────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ No naps detected today                     │   │
│  │                                            │   │
│  │ This week: 1 nap (Tuesday, 25m)           │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
└──────────────────────────────────────────────────┘
```

### 5.1 Sleep Score Ring

**Component:** Reuses `RecoveryRing` component with modified labels.

- Score: `sleep_performance_percentage` from Whoop, rounded to integer.
- Inner label: "SLEEP" instead of "RECOVERY".
- Color zones (sleep-specific):
  - Green: >= 85% sleep performance
  - Yellow: 70-84%
  - Red: < 70%
- Animation: same count-up as recovery ring.
- Size: same as recovery ring (200pt diameter).

**Below the ring:**
- Line 1: "[Xh YYm] asleep · [Xh YYm] in bed" — `cardBody`, `text.primary`.
  - "asleep" = total_sleep_time (excluding awake time)
  - "in bed" = time_in_bed (total from sleep start to sleep end)
- Line 2: "Sleep Efficiency: [XX.X]%" — `metricLabel`, `text.secondary`.
  - 1 decimal place. Color-coded: green >= 90%, yellow 80-89%, red < 80%.

### 5.2 Sleep Stages Section

**Stacked Horizontal Bar:**
- Width: card width (full bleed minus padding).
- Height: 24pt.
- Corner radius: 12pt (fully rounded ends).
- Segments from left to right: Awake, Light, Deep (SWS), REM.
- Each segment width proportional to its percentage of total time in bed.
- Colors: `sleep.awake`, `sleep.light`, `sleep.deep`, `sleep.rem`.
- Minimum visible segment width: 4pt (even if percentage is tiny, ensure visibility).
- No gaps between segments.
- Animation: segments grow from left to right on appear, staggered by 0.1s each, total animation: 0.5s.

**Stage Tiles (below the bar):**

Four tiles in a horizontal row (same layout as MetricTiles on Recovery Today). Each tile:

- Stage name: `metricLabel`, colored to match the stage bar.
- Duration: `metricValue`, `text.primary`. Format: "Xh YYm" (e.g., "1h 42m"). If < 1h: just "YYm" (e.g., "32m").
- Percentage: `metricUnit`, `text.secondary`. Format: "XX%" (integer, no decimals).
- Optimal indicator: colored dot + label.
  - Awake: < 10% = "Good" (green), 10-15% = "OK" (yellow), > 15% = "High" (red)
  - Light: 40-60% = "Normal" (gray), < 40% = "Low" (yellow), > 60% = "High" (yellow)
  - Deep (SWS): >= 15% = "Good" (green), 10-14% = "OK" (yellow), < 10% = "Low" (red)
  - REM: >= 20% = "Good" (green), 15-19% = "OK" (yellow), < 15% = "Low" (red)

**Tap interaction:** Tapping a stage tile shows a tooltip with the optimal range: "Optimal deep sleep: 1h 30m - 2h (15-20% of total sleep)."

**Sleep Architecture Clinical Notes (inform tooltip "Learn More" content and "Why?" panels):**

- **Sleep cycles are NOT a fixed 90 minutes.** The commonly cited "90-minute cycle" is an approximation. Actual cycle length ranges from 80-120 minutes and varies throughout the night, between individuals, and even between nights for the same person (Carskadon & Dement, 2017). The first cycle is typically the shortest (70-100 min), and cycles lengthen as the night progresses. **The app must never state "one sleep cycle = 90 minutes" as a fact.** Instead, use "approximately 80-120 minutes" or simply refer to "a full sleep cycle."
- **Sleep stage distribution shifts across the night.** The first half of the night is dominated by slow-wave sleep (deep/SWS), while the second half is predominantly REM sleep (Stickgold & Walker, 2005). This means: (a) going to bed late and sleeping fewer hours disproportionately cuts REM sleep, and (b) waking up early disproportionately cuts REM sleep. **The "Why?" reasoning for bedtime prescriptions should note:** "Going to bed on time protects your REM sleep, which occurs mostly in the second half of the night. REM is critical for memory, emotional regulation, and learning."
- **Whoop's sleep staging is an estimate.** Whoop uses accelerometer and heart rate data to infer sleep stages. Polysomnography (the gold standard) uses EEG, EOG, and EMG. Whoop's staging accuracy is reasonable for consumer use but should not be treated as clinical-grade. The app should note in the sleep detail "Learn More": "Sleep stages are estimated from your Whoop sensor data. For clinical sleep assessment, consult a sleep specialist."

### 5.3 Sleep Needed Breakdown

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**Layout:** Vertical list of rows. Each row is an HStack with leading label and trailing value.

| Row | Label | Value | Notes |
|---|---|---|---|
| 1 | "Baseline need" | "7h 15m" | `sleep_needed.baseline_milli` converted to h/m |
| 2 | "+ Sleep debt" | "+45m" | `sleep_needed.need_from_sleep_debt_milli` |
| 3 | "+ Yesterday's strain" | "+20m" | `sleep_needed.need_from_strain_milli` |
| 4 | "- Naps" | "-0m" | Nap duration subtracted. If no naps: "-0m" |
| Divider | 1pt line, `divider` | | |
| 5 | "Total needed" | "8h 20m" | Sum. Font: `cardTitle` (bold) |
| 6 | "Actual sleep" | "7h 23m" | `total_sleep_time`. Font: `cardTitle` |
| Divider | 1pt line, `divider` | | |
| 7 | "Deficit" or "Surplus" | "-57m" or "+12m" | Actual - Needed. Color: red if deficit, green if surplus. Trailing colored dot + zone label. |

- Label font: `cardBody`, `text.secondary`.
- Value font: `cardBody`, `text.primary` (except rows 5-7 as noted).
- Row height: 36pt.
- "+" and "-" signs are explicit on rows 2-4 and row 7.
- If deficit is 0: show "On target" in green, no +/- sign.

### 5.4 Sleep Metrics Grid

**Layout:** 2-column LazyVGrid, 8pt spacing. Each cell is a compact MetricTile variant (smaller than the main MetricTile).

**Metrics:**

| Metric | Icon | Value | Unit | Trend | Good/Concerning |
|---|---|---|---|---|---|
| Sleep Consistency | `clock.arrow.2.circlepath` | `sleep_consistency_percentage` | "%" | vs 7-day avg | >= 80% good, < 60% concerning |
| Respiratory Rate | `lungs` | `respiratory_rate` | "br/min" | vs yesterday | Stable = good, > 2 br/min change = concerning |
| Sleep Efficiency | `bed.double.fill` | `sleep_efficiency_percentage` | "%" | vs 7-day avg | >= 90% good, < 80% concerning |
| Disturbances | `exclamationmark.triangle` | integer count | "" | vs 7-day avg | < 5 good, > 10 concerning |

- Tile height: 76pt (slightly smaller than main MetricTiles).
- Respiratory rate: 1 decimal place.
- All percentages: 1 decimal place.
- Disturbance count: integer, no decimals.

### 5.5 Sleep Trend Chart

**Time Range Selector:**
- Three pill buttons: "7D", "14D", "30D".
- Horizontal arrangement, centered.
- Selected pill: `recovery.[zone].primary` fill, white text.
- Unselected pills: `surface.card` fill, `text.secondary` text.
- Pill dimensions: auto-width with 16pt horizontal padding, height: 32pt, corner radius: 16pt.
- Tap: switches chart data. Haptic: `.light`. Smooth crossfade on chart data (0.3s).
- Default selection: "7D".

**Chart:**
- Component: `TrendChart` (see 3.3).
- Type: `.area` (filled line chart).
- Data: sleep duration (hours) for each night in the selected range.
- Y-axis: hours, auto-scaled with 0.5h increments (e.g., 6.0, 6.5, 7.0, 7.5, 8.0).
- X-axis: day labels. For 7D: day abbreviations (M, T, W, ...). For 14D: every other day. For 30D: weekly labels (Mar 1, Mar 8, ...).
- Color: `sleep.deep` for the fill (gradient from `sleep.deep` at top to transparent at bottom).
- Line: 2pt stroke, `sleep.deep`.
- Horizontal reference line: dashed, `text.tertiary` @ 50%, at "sleep needed" baseline. Label: "Needed: 7h 15m" at the right end of the line.
- Interaction: scrub mode (see TrendChart 3.3).
- Today's point: emphasized with a larger dot (6pt radius vs 3pt).

### 5.6 Bedtime Consistency Chart

**Chart Type:** Scatter plot.

- Y-axis: time of day (inverted — earlier time at top, later at bottom). Range: 9:00 PM to 1:00 AM (auto-scales if user goes outside this range).
- X-axis: days in selected range (matches sleep trend chart's range selector).
- Each dot: actual bedtime for that night. Dot size: 8pt. Color: green if within 30min of target, yellow if 30-60min off, red if > 60min off.
- Reference line: horizontal dashed line at target bedtime. Label: "Target: 10:30 PM".
- Interaction: tap a dot to see exact bedtime and deviation from target in a tooltip.

### 5.7 Nap Tracking Section

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**States:**

- **No nap today, no naps this week:**
  - Text: "No naps detected" — `cardBody`, `text.secondary`.

- **No nap today, naps this week:**
  - Line 1: "No naps detected today" — `cardBody`, `text.secondary`.
  - Line 2: "This week: [N] nap(s) ([day], [duration])" — `reasoningText`, `text.tertiary`.
  - If multiple naps: "This week: 3 naps (Tue 25m, Thu 18m, Sat 30m)".

- **Nap detected today:**
  - Line 1: "Nap detected: [start time] - [end time] ([duration])" — `cardBody`, `text.primary`.
  - Line 2: "This reduces your sleep debt by ~[X]m." — `reasoningText`, `text.secondary`.
  - Nap icon: SF Symbol `moon.zzz`, leading.

- **Multiple naps today:**
  - List each nap as a row with time range and duration.
  - Summary: "Total nap time: [Xm]. Sleep need reduced by [Ym]."

**Nap Duration Guidance (shown in "Learn More" tooltip):**

The common "20 or 90 minute" nap advice is an oversimplification. Evidence-based nap guidance:

- **10-20 minutes (power nap):** The optimal short nap duration. Keeps the sleeper in light sleep (stages N1-N2), avoiding slow-wave sleep (SWS) entry. Produces measurable improvements in alertness, reaction time, and mood without sleep inertia (Waterhouse et al., 2007; Brooks & Lack, 2006). **This is the recommended nap for most situations.** The app should recommend "10-20 minutes" rather than exactly "20 minutes."
- **30-60 minutes: AVOID.** This duration risks waking from SWS, causing significant sleep inertia — grogginess, impaired cognitive function, and reduced performance for 15-30 minutes post-nap. Worse performance than no nap at all during the inertia period.
- **Full sleep cycle (~80-120 min):** Includes all sleep stages and avoids sleep inertia by waking from light sleep. Produces the strongest cognitive and physical benefits. However, this duration is impractical for most situations and may interfere with nighttime sleep onset if taken after 2 PM. **The app should recommend this only on red recovery days when a full-cycle nap before 2 PM is feasible.** Do NOT state "90 minutes" as a fixed number — say "a full cycle (approximately 80-120 minutes)."
- **Timing matters:** Naps taken after 3 PM can delay nighttime sleep onset and fragment nighttime sleep architecture (Milner & Cote, 2009). The app should warn: "Late naps may make it harder to fall asleep tonight."

---

## 6. Screen 3: Strain Detail View

Accessed by tapping the Strain teaser card on Recovery Today View.

### Navigation

- Pushed onto NavigationStack.
- Back button: "< Recovery".
- Title: "Strain".

### Full Screen Layout

```
┌──────────────────────────────────────────────────┐
│ < Recovery          Strain                        │
├──────────────────────────────────────────────────┤
│                                                    │
│              ┌──────────────┐                      │
│              │   ╭────╮     │                      │
│              │  │ 14.2 │    │                      │  ← Strain Gauge
│              │  │STRAIN│    │                      │
│              │   ╰────╯     │                      │
│              └──────────────┘                      │
│                                                    │
│     Moderate-High  ·  Calories: 2,847              │
│                                                    │
│  ── Heart Rate Zones ──────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Zone 6 ██ 4m                    2%         │   │
│  │ Zone 5 █████ 12m                7%         │   │
│  │ Zone 4 ████████████ 38m         22%        │   │  ← Horizontal
│  │ Zone 3 ██████████████████ 52m   30%        │   │     bar chart
│  │ Zone 2 ███████████████ 45m      26%        │   │
│  │ Zone 1 ██████ 22m              13%         │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Strain Breakdown ──────────────────────────── │
│                                                    │
│  ┌──────────────────┐ ┌──────────────────┐        │
│  │ Workout Strain   │ │ Day Strain       │        │
│  │ 11.8             │ │ 2.4              │        │
│  │ ████████████░░░░ │ │ ██░░░░░░░░░░░░░░ │        │
│  └──────────────────┘ └──────────────────┘        │
│                                                    │
│  ── Calories ──────────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Total         2,847 kcal                   │   │
│  │ Active        1,342 kcal    (47%)          │   │
│  │ Basal         1,505 kcal    (53%)          │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Heart Rate ────────────────────────────────── │
│                                                    │
│  ┌──────────────────┐ ┌──────────────────┐        │
│  │ Average HR      │ │ Max HR           │        │
│  │ 78 bpm          │ │ 186 bpm          │        │
│  │ vs rest: 52 bpm │ │                  │        │
│  └──────────────────┘ └──────────────────┘        │
│                                                    │
│  ── 24h Heart Rate Timeline ───────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 186 ─                          ╱╲          │   │
│  │      │                        ╱  ╲         │   │
│  │ 120 ─│          ╱╲           ╱    ╲        │   │  ← HR timeline
│  │      │         ╱  ╲    ╱╲  ╱      ╲       │   │
│  │  78 ─│────────╱    ╲──╱  ╲╱        ╲──── │   │
│  │      │───────                       ────  │   │
│  │  52 ─│                                     │   │
│  │    12AM  3AM  6AM  9AM  12PM  3PM  6PM 9PM│   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Strain Trends ─────────────────────────────── │
│                                                    │
│  [7D]  [14D]  [30D]                               │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │   ╱╲     ╱╲                                │   │
│  │  ╱  ╲   ╱  ╲                  ╱╲          │   │  ← Strain trend
│  │ ╱    ╲ ╱    ╲     ╱╲        ╱  ╲         │   │
│  │╱      ╲      ╲   ╱  ╲      ╱    ╲        │   │
│  │               ╲ ╱    ╲    ╱      ╲       │   │
│  │                ╲      ╲  ╱        ╲      │   │
│  │ M   T   W   T   F   S   S                │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Strain vs Recovery ────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ When your strain exceeds 14, your next-day │   │
│  │ recovery drops by an average of 23%.       │   │
│  │                                            │   │
│  │ Avg recovery after low strain (<10): 74%   │   │
│  │ Avg recovery after high strain (>14): 57%  │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
└──────────────────────────────────────────────────┘
```

### 6.1 Strain Gauge

**Component:** Reuses `RecoveryRing` but adapted for strain's 0-21 scale.

- Value: `strain` from Whoop cycle, 1 decimal place.
- Fill: `strain / 21` of the circle.
- Inner label: "STRAIN" in `heroLabel`.
- Score font: `heroScore` (72pt). Because strain has 1 decimal, the font may need to be slightly smaller (64pt) to fit "XX.X" inside the ring. Use dynamic sizing: if value >= 10.0, use 64pt; if < 10.0, use 72pt.
- Color: gradient based on strain level:
  - 0-7: `zone.2` (light effort)
  - 7-14: `zone.3` / `zone.4` (moderate)
  - 14-18: `zone.5` (high)
  - 18-21: `zone.6` (extreme)

**Strain Label (below gauge):**
- Qualitative label: "Low" (0-7), "Moderate" (7-10), "Moderate-High" (10-14), "High" (14-18), "Peak" (18-21)
- Format: "[Qualifier] · Calories: [X,XXX]"
- Font: `cardBody`, `text.secondary`.

### 6.2 Heart Rate Zones

**Chart Type:** Horizontal bar chart.

**Layout:**
- Card: `surface.card`, corner radius: 16pt, padding: 16pt.
- 6 rows, one per zone. Top row = Zone 6 (highest), bottom = Zone 1 (lowest).
- Each row:
  - Leading label: "Zone [N]" — `metricLabel`, `text.secondary`, fixed width: 56pt.
  - Bar: height 20pt, corner radius: 4pt, color: `zone.[N]`. Width proportional to time in that zone relative to longest zone.
  - Duration label: right of bar, 8pt gap, "[Xm]" or "[Xh Ym]" — `sparklineLabel`, `text.primary`.
  - Percentage: trailing-aligned, "[XX]%" — `sparklineLabel`, `text.secondary`.
- Row spacing: 8pt.
- Bar animation: bars grow from left on appear, staggered 0.05s each from bottom to top, 0.4s total.

**Zone definitions:**
| Zone | HR Range | Description |
|---|---|---|
| 1 | 50-60% max HR | Warm-up / recovery |
| 2 | 60-70% max HR | Fat burn / easy |
| 3 | 70-80% max HR | Aerobic / moderate |
| 4 | 80-90% max HR | Threshold / hard |
| 5 | 90-95% max HR | VO2max / very hard |
| 6 | 95-100% max HR | Anaerobic / max effort |

**Tap interaction:** Tapping a zone row highlights it and shows a tooltip: "Zone [N]: [X]m at [low]-[high] bpm. [description]."

### 6.3 Strain Breakdown

Two cards side by side in an HStack, each 50% width.

**Workout Strain Card:**
- Title: "Workout Strain" — `metricLabel`
- Value: sum of all workout strains, 1 decimal — `metricValue`
- Mini bar: workout strain / 21 fill proportion, `zone.4` color, height: 6pt, corner radius: 3pt.

**Day Strain Card:**
- Title: "Day Strain" — `metricLabel`
- Value: total strain - workout strain, 1 decimal — `metricValue`
- Mini bar: day strain / 21 fill proportion, `zone.2` color, height: 6pt, corner radius: 3pt.

If no workouts logged: Workout Strain shows "0.0" and Day Strain equals Total Strain.

### 6.4 Calories Breakdown

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

Three rows:

| Row | Label | Value | Supplemental |
|---|---|---|---|
| Total | "Total" | "[X,XXX] kcal" | (bold) |
| Active | "Active" | "[X,XXX] kcal" | "([XX]%)" |
| Basal | "Basal" | "[X,XXX] kcal" | "([XX]%)" |

- Calorie formatting: integer with thousands separator (e.g., "2,847"). Unit: "kcal".
- Active = `kilojoule` converted to kcal (divide by 4.184). Note: Whoop API reports `kilojoule` as the active calories in kilojoules.
- Basal = estimated from user profile (if available) or Whoop-reported total minus active.
- Percentage: active as % of total, basal as % of total. Integer, no decimals.

### 6.5 Heart Rate Metrics

Two cards side by side:

**Average HR:** value in bpm (integer). Below: "vs rest: [RHR] bpm" in `sparklineLabel`, `text.tertiary`.

**Max HR:** value in bpm (integer). If max HR is within 5 bpm of known max HR (220 - age): label below: "Near your max" in `recovery.red.primary`.

### 6.6 24-Hour Heart Rate Timeline

**Chart:** `TrendChart` component, type: `.area`.
- Data: heart rate samples throughout the day (Whoop provides these in cycle data).
- X-axis: 24 hours, labeled every 3 hours (12AM, 3AM, 6AM, ..., 9PM).
- Y-axis: bpm, auto-scaled with ~20 bpm increments.
- Line color: gradient from `zone.1` (low HR) to `zone.6` (high HR) based on the Y value at each point.
- Fill: gradient from line color at 30% opacity to transparent.
- Reference line: horizontal dashed line at RHR. Label: "RHR: [XX] bpm" at the right end.
- Workout periods: highlighted with a subtle background band (vertical stripe, `zone.4` at 10% opacity) behind the chart. Small label above: workout type icon.
- Interaction: scrub mode. Tooltip shows time and HR.

### 6.7 Strain Trends

- Identical layout to Sleep Trend Chart (5.5): time range selector + TrendChart.
- Data: daily strain values.
- Y-axis: 0-21 scale.
- Color: `zone.4`.
- Reference line: user's average strain (dashed, `text.tertiary`).

### 6.8 Strain vs Recovery Correlation Insight

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**Content:** 2-3 sentences of algorithmic insight. Generated by analyzing the user's historical data:

- Calculate average next-day recovery for days following low strain (<10), moderate strain (10-14), and high strain (>14).
- Present the most significant finding.
- Format as natural language, not bullets.
- Font: `cardBody`, `text.primary`.
- If insufficient data (< 14 days): "We need a couple more weeks of data to identify your strain-recovery patterns. Check back soon."

**Examples:**
- "When your strain exceeds 14, your next-day recovery drops by an average of 23%. Your body recovers best after moderate days (strain 10-14)."
- "Back-to-back high strain days (>14 for 2+ days) reduce your recovery by 31% on average. Consider alternating hard and easy days."
- "Your recovery is remarkably consistent regardless of strain. Sleep quality appears to be a bigger factor for you."

---

## 7. Screen 4: Recovery Trends View

Accessed by tapping "See Trends" on the Recovery Today View.

### Navigation

- Pushed onto NavigationStack.
- Back button: "< Recovery".
- Title: "Trends".
- Trailing nav item: "Compare" button (text, `recovery.[zone].primary`). Pushes Historical Comparison view.

### Full Screen Layout

```
┌──────────────────────────────────────────────────┐
│ < Recovery         Trends              Compare    │
├──────────────────────────────────────────────────┤
│                                                    │
│  [7D]  [14D]  [30D]  [90D]                        │  ← Time range pills
│                                                    │
│  ── Recovery · HRV · RHR ──────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 100%─                                      │   │
│  │      │  ●    ●                             │   │
│  │  75%─│●  ╲  ╱ ╲  ●                        │   │  ← Multi-line
│  │      │ ╲  ╲╱   ╲╱ ╲  ●                   │   │     chart
│  │  50%─│  ╲           ╲╱                    │   │
│  │      │                                     │   │
│  │  25%─│                                     │   │
│  │      │                                     │   │
│  │   0%─│─────────────────────────────────── │   │
│  │    M    T    W    T    F    S    S         │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  Legend: [● Recovery] [● HRV] [● RHR]             │  ← Toggle legend
│                                                    │
│  ── Pattern Insights ──────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 💡 Your recovery averages 72% when you     │   │
│  │    sleep 7.5h or more.                     │   │
│  └────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────┐   │
│  │ 💡 After high strain days (>14), your      │   │
│  │    recovery drops 23% the next day.        │   │
│  └────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────┐   │
│  │ 💡 Your HRV has trended up 8% over the    │   │
│  │    last 30 days — a sign of improving      │   │
│  │    fitness.                                │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Calendar Heatmap ──────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │       March 2026                           │   │
│  │ M  ■  ■  □  ■  ■                          │   │
│  │ T  ■  □  ■  ■  ■                          │   │
│  │ W  □  ■  ■  ■                              │   │  ← Heatmap grid
│  │ T  ■  ■  ■  □                              │   │
│  │ F  □  ■  ■  ■                              │   │
│  │ S  ■  ■  □  ■                              │   │
│  │ S  ■  □  ■  ■                              │   │
│  │                                            │   │
│  │  □ Red   ■ Yellow   ■ Green                │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Best & Worst Days ─────────────────────────── │
│                                                    │
│  ┌──────────────────┐ ┌──────────────────┐        │
│  │ Best Recovery    │ │ Worst Recovery   │        │
│  │ 94% — Mar 15    │ │ 28% — Mar 3     │        │
│  │ After: 6.2h     │ │ After: 4.8h     │        │
│  │ sleep, rest day  │ │ sleep, 18.4     │        │
│  │                  │ │ strain prev day │        │
│  └──────────────────┘ └──────────────────┘        │
│                                                    │
│  ── Day-of-Week Patterns ──────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │  Mon  ████████████████████░░░  68%         │   │
│  │  Tue  ██████████████████████░░  72%        │   │
│  │  Wed  ████████████████████████░  78%       │   │
│  │  Thu  ██████████████████████░░  73%        │   │  ← Avg recovery
│  │  Fri  █████████████████░░░░░░  62%         │   │     by day of week
│  │  Sat  ██████████████████████████  82%      │   │
│  │  Sun  █████████████████████████░  80%      │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
└──────────────────────────────────────────────────┘
```

### 7.1 Time Range Selector

- Four pill buttons: "7D", "14D", "30D", "90D".
- Same styling as Sleep Trends pills (see 5.5).
- Default: "30D" (trends are most meaningful at 30+ days).
- Changing range updates ALL charts and insights on this screen.

### 7.2 Multi-Line Chart

**Component:** `TrendChart` with `overlayLines`.

**Primary line (always visible):** Recovery % — `recovery.green.primary`, 2pt stroke.
**Overlay line 1 (toggleable):** HRV — `#A29BFE` (purple), 1.5pt stroke, dashed.
**Overlay line 2 (toggleable):** RHR — `#FF6B6B` (salmon), 1.5pt stroke, dashed.

**Legend (below chart):**
- Three toggle buttons in an HStack, 12pt spacing.
- Each: colored circle (8pt) + label. Tap to toggle that line on/off.
- Active: full opacity, label `text.primary`.
- Inactive: 30% opacity, label `text.tertiary`, line hidden from chart with fade animation.
- Default: Recovery on, HRV on, RHR off (to avoid visual clutter; user enables if interested).

**Y-Axis:**
- When only Recovery is shown: 0-100% scale.
- When HRV is enabled: dual Y-axis. Recovery on left (0-100%), HRV on right (auto-scaled to user's range, e.g., 30-120ms).
- When RHR is enabled: shares the right axis with HRV (if both on), or gets its own right axis (auto-scaled, e.g., 40-80 bpm).
- Maximum 2 Y-axes (left + right). If all three metrics are on, Recovery uses left axis, HRV and RHR share right axis (normalized).

**Interaction:** Scrub mode. Tooltip shows all active metrics for that date.

### 7.3 Pattern Insights Cards

**Generation:** Algorithmic, based on correlation analysis of user's data within the selected time range.

**Layout:** Vertical stack of cards, 8pt spacing. Each card: `surface.card`, corner radius: 12pt, padding: 12pt.

**Card content:** Leading bulb icon ("💡"), then insight text. Font: `cardBody`, `text.primary`.

**Insights generated (in priority order — show top 3-5):**

1. **Sleep-recovery correlation:** "Your recovery averages [X]% when you sleep [Y]h or more, but only [Z]% when you sleep less."
   - Only show if difference between above/below threshold recovery is > 10%.
   - Threshold Y: user's sleep baseline.

2. **Strain-recovery correlation:** "After high strain days (>[threshold]), your recovery drops [X]% the next day."
   - Threshold: 14 for moderately active users, 16 for very active.
   - Only show if average next-day drop > 15%.

3. **HRV trend:** "Your HRV has [trended up/trended down/remained stable] [X]% over the last [time range]."
   - Calculate linear regression slope over the selected period.
   - "Trended up" if slope > 2% over period. Add: "a sign of improving fitness."
   - "Trended down" if slope < -2%. Add: "consider reducing training load."
   - "Remained stable" otherwise. Add: "your training load is well-matched to your recovery capacity."

4. **Consistency insight:** "You recover best on [day(s) of week] (avg [X]%) and worst on [day(s)] (avg [Y]%)."
   - Only show if max - min day-of-week average > 10%.

5. **Consecutive day pattern:** "After [N]+ consecutive days with strain > [X], your recovery takes [Y] days to return to your average."
   - Requires at least 30 days of data.

6. **Sleep consistency impact:** "When you go to bed within 30 minutes of the same time, your recovery is [X]% higher."
   - Compare recovery on consistent vs inconsistent sleep schedule nights.
   - Only show if difference > 8%.

**Empty state:** If < 7 days of data: show a single card: "We're collecting data to identify your recovery patterns. Check back after a week of wearing your Whoop consistently."

**Tap interaction:** Tapping an insight card expands it to show supporting data (the actual numbers behind the insight) in a slide-down section. Includes a mini chart relevant to the insight (e.g., scatter plot of sleep duration vs next-day recovery).

### 7.4 Calendar Heatmap

**Layout:** Grid of colored squares, one per day, arranged in a GitHub-style contribution graph.

- Rows: 7 (Monday at top, Sunday at bottom).
- Columns: number of weeks in the selected range. For 30D: ~4-5 columns. For 90D: ~13 columns.
- Cell size: calculated to fit screen width. For 30D: ~40pt. For 90D: ~20pt.
- Cell corner radius: 4pt (30D) or 2pt (90D).
- Cell spacing: 3pt.
- Colors:
  - Green: recovery >= 67% (intensity varies: 67-79% = lighter green, 80-100% = darker green)
  - Yellow: recovery 34-66% (same intensity variance)
  - Red: recovery 0-33% (same intensity variance)
  - Gray: no data for that day
- Month label: above the grid, left-aligned. `sectionTitle`. If range spans 2+ months, both labels shown at the correct column position.
- Day labels: leading column. "M", "T", "W", "T", "F", "S", "S" — `sparklineLabel`, `text.tertiary`.

**Legend:** Below the grid, horizontal: three colored squares with labels. "Red (0-33%)", "Yellow (34-66%)", "Green (67-100%)".

**Tap interaction:** Tapping a cell shows a tooltip: "Mar 15: 94% (Green). HRV: 72ms. Sleep: 8h 12m." Includes the top 3 metrics for that day.

### 7.5 Best & Worst Days

**Layout:** Two cards side by side, each 50% width.

**Best Recovery Card:**
- Title: "Best Recovery" — `cardTitle`, `recovery.green.primary`
- Score: "[XX]% — [MMM d]" — `metricValue`
- Context: 2-3 lines explaining what led to it. "After: [sleep duration] sleep, [qualifier] day" — `reasoningText`, `text.secondary`.
- Example: "94% — Mar 15. After: 8.2h sleep, rest day."

**Worst Recovery Card:**
- Title: "Worst Recovery" — `cardTitle`, `recovery.red.primary`
- Score and context: same format.
- Example: "28% — Mar 3. After: 4.8h sleep, 18.4 strain previous day."

**Data range:** Uses the selected time range. If multiple days tie, show the most recent.

### 7.6 Day-of-Week Pattern Analysis

**Chart Type:** Horizontal bar chart.

- 7 rows, one per day (Monday through Sunday).
- Bar: fill proportional to average recovery (0-100%), color: zone-appropriate (green/yellow/red based on the average).
- Trailing label: average recovery percentage, integer.
- Font: `metricLabel` for day names, `metricValue` for percentages (smaller variant, 17pt).
- Highlight: the best day has a subtle glow/border. The worst day has a subtle indicator (e.g., `text.tertiary` border).
- Card: `surface.card`, corner radius: 16pt, padding: 16pt.

**Insight below chart (if pattern exists):**
- If consistent pattern: "Your recovery dips on [worst day] — this is often after [activity]. Consider scheduling rest on [worst day - 1]."
- Font: `reasoningText`, `text.secondary`.

---

## 8. Screen 5: Prescription Engine — Full Algorithm Specification

This section documents the complete logic that generates the Daily Prescription. The prescription engine runs once daily when fresh Whoop recovery data is available (typically between 5-7 AM after the user wakes). It can be re-run manually via pull-to-refresh.

**Calibration gate:** Before generating any prescription, check `daysOfWhoopData`. If < 7, do not generate prescriptions (show onboarding message per Section 1, "Calibration Period"). If 7-13, generate conservative prescriptions using population baselines with `.low` confidence. If >= 14, use personal baselines. All HRV, RHR, and sleep baseline comparisons require >= 14 days of data to be clinically meaningful.

**Safety invariant:** The prescription engine must NEVER recommend training through a red recovery day. Even if the user feels fine subjectively, the app should not encourage overriding a red zone. The manual override ("I Feel Great") exists as a user-initiated escape hatch in MODULE_TRAINING.md, but the prescription engine itself must always err on the side of caution. Red zone = rest or mobility, period. The reasoning panel should explain: "Even if you feel good, your biometrics suggest your body needs recovery. Training through low recovery increases injury risk and delays adaptation."

### 8.1 Input Data Model

```
struct PrescriptionInputs {
    // Whoop Recovery (today)
    let recoveryScore: Int              // 0-100
    let hrvRmssd: Double                // milliseconds
    let restingHeartRate: Int           // bpm
    let spo2: Double                    // percentage
    let skinTemp: Double                // celsius

    // Whoop Sleep (last night)
    let totalSleepHours: Double         // decimal hours
    let sleepDebt: Double               // hours (cumulative)
    let sleepEfficiency: Double         // percentage
    let sleepPerformance: Double        // percentage
    let sleepConsistency: Double        // percentage
    let deepSleepHours: Double          // SWS duration
    let remSleepHours: Double           // REM duration

    // Whoop Strain (yesterday)
    let yesterdayStrain: Double          // 0-21
    let yesterdayCalories: Int           // kcal

    // Historical (30-day)
    let avgRecovery30d: Double
    let avgHrv30d: Double
    let avgRhr30d: Double
    let hrvTrend7d: TrendDirection      // .up, .down, .stable
    let consecutiveHighStrainDays: Int  // days with strain > 14
    let consecutiveLowRecoveryDays: Int // days with recovery < 50

    // User Context
    let bodyWeightKg: Double
    let plannedActivities: [PlannedActivity]  // from user's calendar/input
    let footballSchedule: [FootballMatch]       // day, time
    let wakeTime: Date                          // today's wake time
    let currentTime: Date
    let ambientTempFahrenheit: Double?          // from weather API
    let ambientHumidityPercent: Double?         // from weather API (relative humidity %)

    // NutriTrack Data (optional)
    let nutriTrackConnected: Bool
    let todayProteinG: Double?
    let todayCarbsG: Double?
    let todayFatG: Double?
    let todayCaloriesConsumed: Int?
    let proteinTargetG: Double?
    let carbsTargetG: Double?
}

enum TrendDirection {
    case up(percentage: Double)
    case down(percentage: Double)
    case stable
}

struct PlannedActivity {
    let type: ActivityType      // .gym, .run, .football, .mobility, .rest
    let scheduledTime: Date?
    let expectedDurationMin: Int?
}

struct FootballMatch {
    let date: Date
    let time: Date?
    let type: MatchType     // .competitive, .training, .pickup
}
```

### 8.2 Training Prescription Algorithm

```
func generateTrainingPrescription(inputs: PrescriptionInputs) -> TrainingPrescription {

    // Step 1: Determine base zone
    var zone: TrainingZone
    switch inputs.recoveryScore {
        case 85...100: zone = .peakGreen       // "Peak state"
        case 67...84:  zone = .green           // "Full send"
        case 50...66:  zone = .upperYellow     // "Moderate day"
        case 34...49:  zone = .lowerYellow     // "Easy-moderate"
        case 20...33:  zone = .upperRed        // "Easy day"
        case 0...19:   zone = .red             // "Rest day"
    }

    // Step 2: Apply modifiers (each can downgrade zone by 1 level)

    // Modifier A: HRV trend declining 3+ days
    if inputs.hrvTrend7d == .down && inputs.consecutiveLowRecoveryDays >= 2 {
        zone = zone.downgradeByOne()
        modifiers.append(.decliningHRV)
    }

    // Modifier B: Consecutive high strain
    if inputs.consecutiveHighStrainDays >= 2 {
        zone = zone.downgradeByOne()
        modifiers.append(.consecutiveHighStrain(days: inputs.consecutiveHighStrainDays))
    }

    // Modifier C: Football proximity
    let hoursToFootball = inputs.footballSchedule
        .filter { $0.date >= inputs.currentTime }
        .map { $0.date.timeIntervalSince(inputs.currentTime) / 3600 }
        .min()

    if let hours = hoursToFootball {
        if hours <= 24 {
            zone = min(zone, .upperYellow)  // cap at moderate
            modifiers.append(.footballTomorrow)
        } else if hours <= 48 {
            if zone == .peakGreen { zone = .green }  // slight downgrade only
            modifiers.append(.footballIn2Days)
        }
    }

    // Modifier D: Poor sleep (< 6h or efficiency < 75%)
    if inputs.totalSleepHours < 6.0 || inputs.sleepEfficiency < 75.0 {
        zone = zone.downgradeByOne()
        modifiers.append(.poorSleep)
    }

    // Modifier E: Sleep debt > 4h
    if inputs.sleepDebt > 4.0 {
        zone = zone.downgradeByOne()
        modifiers.append(.significantSleepDebt)
    }

    // Modifier F: Extreme heat / WBGT safety (Miami-specific)
    // Wet Bulb Globe Temperature (WBGT) > 28°C (82.4°F) = high exertional heat illness risk
    // per ACSM (Armstrong et al., 2007). If outdoor training is planned and WBGT exceeds
    // this threshold, the app should warn the user and suggest indoor alternatives.
    // This does not downgrade the zone (you can still train hard indoors), but it
    // adds a safety overlay to the training prescription body text.
    if let wbgt = calculateWBGT(temp: inputs.ambientTempFahrenheit, humidity: inputs.ambientHumidityPercent) {
        if wbgt > 82.4 {  // °F equivalent of 28°C
            modifiers.append(.extremeHeatWarning(wbgt: wbgt))
            // Note: if WBGT > 90°F (32.2°C), outdoor training should be STRONGLY discouraged
        }
    }

    // Step 3: Zone can never be upgraded by modifiers, only downgraded.
    // Minimum zone is .red (rest day). Cannot go below.

    // Step 4: Generate headline and body
    return TrainingPrescription(
        zone: zone,
        headline: zone.headline,
        body: zone.bodyText(modifiers: modifiers),
        modifiers: modifiers
    )
}
```

**Training Zone Outputs:**

| Zone | Headline | Body | Volume | Intensity |
|---|---|---|---|---|
| `.peakGreen` | "Peak state — push your limits today" | "HRV is elevated and recovery is excellent. This is the day for PRs, heavy compound lifts, or your hardest interval session. Train with intent — but always with proper form and warm-up." | 100% | 100% |
| `.green` | "Full send — compound lifts and PRs OK" | "Recovery supports high-volume training. Hit your planned workout at full intensity." | 100% | 90-100% |
| `.upperYellow` | "Moderate day — reduce volume 20%" | "Solid recovery but not peak. Train at normal intensity but cut total sets/reps by about 20%. Focus on quality reps." | 80% | 90-100% |
| `.lowerYellow` | "Easy-moderate — maintain intensity, cut volume 30%" | "Recovery is below average. Keep weights the same but reduce total volume by 30%. Skip accessory work if needed." | 70% | 80-90% |
| `.upperRed` | "Easy day — mobility, stretching, or light cardio" | "Your body needs recovery. Stick to mobility work, yoga, a light walk, or easy swimming. Avoid resistance training." | 30% | 50% |
| `.red` | "Rest day — full recovery" | "Recovery is very low. Take a complete rest day. Light walking is fine but avoid structured training. Focus on sleep, nutrition, and hydration." | 0% | 0% |

> **APP STORE COMPLIANCE -- Medical Disclaimer Requirement:**
> Every PrescriptionCard rendered from the above zone outputs MUST include a tappable
> "Why this recommendation?" link that opens a sheet. That sheet MUST contain, at the
> bottom, the following disclaimer text (see also Section 1, "Medical Disclaimer & Scope"):
>
> *"This is not medical advice. Tempo provides fitness and wellness recommendations based on
> wearable sensor data, which are estimates -- not clinical-grade measurements. Consult a
> qualified healthcare professional before making changes to your exercise, nutrition, or
> sleep habits, particularly if you have pre-existing conditions or experience unusual symptoms."*
>
> Additionally, for `.upperRed` and `.red` zones, the prescription body text MUST append:
> *"If you experience persistent low recovery for 7 or more days, consider consulting a
> healthcare professional to rule out underlying health issues."*
>
> See `docs/APP_STORE_COMPLIANCE.md` Section 6 for the full content and safety requirements.

**Heat Safety Overlay (appended to body text when `.extremeHeatWarning` modifier is present):**
- WBGT 82-86°F: "Heat advisory: outdoor training carries elevated risk today. Consider training indoors or during early morning/evening hours. Apply sunscreen (SPF 30+) for any outdoor activity."
- WBGT 86-90°F: "High heat risk: reduce outdoor training intensity by 50% and limit duration to 30 minutes. Hydrate aggressively. Apply sunscreen. Consider moving your session indoors."
- WBGT > 90°F: "Extreme heat danger: avoid outdoor training. Exertional heat stroke risk is significantly elevated (Armstrong et al., 2007). Train indoors only. If you must be outdoors, limit exposure and monitor for symptoms: dizziness, nausea, confusion, cessation of sweating."

**Sunscreen reminder:** When any outdoor activity (football, running) is planned and the UV index > 3 (obtained from weather API), append to the training prescription body: "Don't forget sunscreen (SPF 30+ minimum, reapply every 2 hours during outdoor activity)."

### 8.3 Nutrition Prescription Algorithm

```
func generateNutritionPrescription(inputs: PrescriptionInputs) -> NutritionPrescription {

    var recommendations: [NutritionRecommendation] = []

    // Rule 1: Expected strain adjustment
    let expectedStrain = estimateExpectedStrain(from: inputs.plannedActivities)
    if expectedStrain > 14 {
        recommendations.append(
            .carbAdjustment(
                headline: "Extra 30-50g carbs today",
                body: "High strain expected from your planned activities. Fuel up with additional carbohydrates.",
                reason: "Planned activities suggest strain > 14 today"
            )
        )
    }

    // Rule 2: Low recovery — protein emphasis
    // Evidence: Jäger et al. (2017) ISSN position stand supports 1.6-2.2g/kg/day for
    // athletes. The 2.0g/kg target is within this evidence-based range.
    // Note: There is no specific evidence that low *recovery scores* require additional
    // protein above normal athletic intake. The rationale is that muscle protein synthesis
    // supports repair, and adequate (not excessive) protein intake is always important.
    // We are NOT recommending protein above the standard athletic range — we are
    // emphasizing hitting the target on days when recovery is compromised.
    if inputs.recoveryScore < 50 {
        let proteinTarget = inputs.bodyWeightKg * 2.0  // 2g/kg — within ISSN range
        recommendations.append(
            .proteinEmphasis(
                headline: "Prioritize protein — aim for \(Int(proteinTarget))g today",
                body: "Low recovery means your muscles need repair. Target 2g protein per kg body weight (Jäger et al., 2017).",
                reason: "Recovery is \(inputs.recoveryScore)% — adequate protein (1.6-2.2g/kg, ISSN position stand) supports tissue repair and immune function"
            )
        )
    }

    // Rule 3: Poor sleep — magnesium-rich foods
    // Evidence: Abbasi et al. (2012) — magnesium supplementation improved sleep quality,
    // but this study was in ELDERLY subjects, not young athletes. The evidence for
    // magnesium-rich FOODS (not supplements) improving sleep in young adults is limited.
    // We recommend foods (not supplements) as a low-risk, food-first approach.
    if inputs.sleepPerformance < 70 || inputs.totalSleepHours < 6.0 {
        recommendations.append(
            .micronutrientFocus(
                headline: "Include magnesium-rich foods today",
                body: "Dark leafy greens, almonds, pumpkin seeds, and dark chocolate may support sleep quality and recovery.",
                reason: "Sleep performance was \(Int(inputs.sleepPerformance))% — magnesium-rich foods may aid sleep and muscle relaxation (Abbasi et al., 2012, in elderly populations; extrapolation to young athletes is limited). This is a food-based recommendation, not a supplement recommendation. If considering magnesium supplements, consult a healthcare provider. Dietary supplements are not FDA-evaluated."
            )
        )
    }

    // Rule 4: Pre-workout meal timing
    if let nextWorkout = inputs.plannedActivities.first(where: { $0.scheduledTime != nil }) {
        let hoursUntilWorkout = nextWorkout.scheduledTime!.timeIntervalSince(inputs.currentTime) / 3600
        if hoursUntilWorkout > 1 && hoursUntilWorkout <= 4 {
            recommendations.append(
                .mealTiming(
                    headline: "Eat carbs 1-2h before training",
                    body: "Aim for 30-50g carbs and 15-20g protein. Your session is in ~\(Int(hoursUntilWorkout))h.",
                    reason: "Pre-workout nutrition improves performance and reduces muscle breakdown"
                )
            )
        }
    }

    // Rule 5: Post-workout protein window
    // (This appears as a time-sensitive notification, see Notifications section)

    // Rule 6: Football day nutrition
    if let match = inputs.footballSchedule.first, Calendar.current.isDateInToday(match.date) {
        let hoursToMatch = match.time?.timeIntervalSince(inputs.currentTime) ?? 0 / 3600
        recommendations.append(
            .footballPrep(
                headline: "High-carb meal 3-4h before kickoff",
                body: "Aim for 1-1.5g carbs per kg body weight (\(Int(inputs.bodyWeightKg * 1.2))g). Include rice, pasta, or bread with a lean protein source. Light snack (banana, energy bar) 30-60 min before.",
                reason: "Football requires sustained high-intensity effort — glycogen loading is critical"
            )
        )
    }

    // Rule 7: NutriTrack integration (if connected)
    if inputs.nutriTrackConnected, let consumed = inputs.todayProteinG, let target = inputs.proteinTargetG {
        let remaining = target - consumed
        if remaining > 20 {
            recommendations.append(
                .trackingUpdate(
                    headline: "You need \(Int(remaining))g more protein today",
                    body: "You've logged \(Int(consumed))g of your \(Int(target))g target. A chicken breast (~40g) or protein shake (~25g) would help.",
                    reason: "Based on your NutriTrack log for today"
                )
            )
        }
    }

    // Priority sort: football prep > protein target > carb adjustment > meal timing > micro focus > tracking
    recommendations.sort(by: \.priority)

    // Take top 2-3 recommendations for the card
    return NutritionPrescription(
        headline: recommendations.first?.headline ?? "Eat balanced meals today",
        body: recommendations.prefix(2).map(\.body).joined(separator: " "),
        allRecommendations: recommendations
    )
}

func estimateExpectedStrain(from activities: [PlannedActivity]) -> Double {
    var total: Double = 3.0  // base daily strain
    for activity in activities {
        switch activity.type {
            case .gym:      total += 8.0 + Double(activity.expectedDurationMin ?? 60) * 0.05
            case .run:      total += 7.0 + Double(activity.expectedDurationMin ?? 30) * 0.08
            case .football: total += 10.0 + Double(activity.expectedDurationMin ?? 90) * 0.04
            case .mobility: total += 2.0
            case .rest:     total += 0.0
        }
    }
    return min(total, 21.0)
}
```

> **Nutrition Prescription Disclaimer:** All nutrition recommendations generated by the
> prescription engine are general wellness guidance, not individualized dietary advice.
> Users with food allergies, intolerances, medical dietary restrictions, or eating
> disorders should consult a registered dietitian or healthcare professional. The app
> does not account for medical conditions that affect nutritional needs (e.g., diabetes,
> kidney disease, celiac disease). This disclaimer must be accessible from every
> NutritionPrescriptionCard's "Why this recommendation?" sheet.

### 8.4 Sleep Prescription Algorithm

```
func generateSleepPrescription(inputs: PrescriptionInputs) -> SleepPrescription {

    // Step 1: Calculate target sleep duration
    let baselineNeed: Double = 7.5  // hours; could be personalized from Whoop's sleep_needed.baseline
    // Evidence: Watson et al. (2015) AASM consensus — 7-9h for adults, 8-10h for athletes.
    // 7.5h is conservative; personalizes from Whoop's sleep_needed.baseline after calibration.

    // Sleep debt repayment: max 1h per night
    // Evidence: Banks & Dinges (2007) showed sleep debt accumulates linearly and requires
    // multiple recovery nights. Belenky et al. (2003) found subjects restricted to 5h/night
    // did not fully recover even after 3 nights of 8h sleep. The 1h/night cap is a PRACTICAL
    // limit — not derived from a specific study. It prevents the algorithm from prescribing
    // unrealistic 10-11h sleep targets. The true physiology of sleep debt repayment is poorly
    // characterized; some evidence suggests ~1/3 of debt is recovered per extra hour of sleep
    // (Kitamura et al., 2016). The 1h cap is a reasonable heuristic.
    let debtRepayment = min(inputs.sleepDebt, 1.0)

    // Strain adjustment: high strain yesterday adds 15-30 min
    let strainAdjustment: Double
    switch inputs.yesterdayStrain {
        case 0..<10:   strainAdjustment = 0
        case 10..<14:  strainAdjustment = 0.25   // 15 min
        case 14..<18:  strainAdjustment = 0.5    // 30 min
        default:       strainAdjustment = 0.5    // cap at 30 min
    }

    let targetSleepDuration = baselineNeed + debtRepayment + strainAdjustment

    // Step 2: Calculate target bedtime
    // Assume wake time is consistent (use today's wake time or user-set alarm)
    let wakeTime = inputs.wakeTime  // or user's set alarm for tomorrow
    let fallAsleepBuffer: Double = 0.25  // 15 minutes to fall asleep

    let targetBedtime = wakeTime
        .addingTimeInterval(-(targetSleepDuration + fallAsleepBuffer) * 3600)

    // Step 3: Caffeine cutoff
    // Default 8h buffer per Drake et al. (2013). User-adjustable (6/8/10/12h) in
    // Settings > Recovery > Caffeine Sensitivity to account for individual CYP1A2
    // polymorphisms affecting caffeine metabolism rate.
    let caffeineBufferHours = userSettings.caffeineBufferHours ?? 8.0  // default 8h
    let caffeineCutoff = targetBedtime.addingTimeInterval(-caffeineBufferHours * 3600)

    // Step 4: Screen time suggestion
    let screenCutoff = targetBedtime.addingTimeInterval(-1 * 3600)

    // Step 5: Generate sleep debt context
    let debtContext: String
    switch inputs.sleepDebt {
        case 0..<0.5:    debtContext = "Sleep debt is minimal. Maintain your routine."
        case 0.5..<2.0:  debtContext = "Mild sleep debt (\(String(format: "%.1f", inputs.sleepDebt))h). An extra 30-60 min tonight will help."
        case 2.0..<4.0:  debtContext = "Moderate sleep debt (\(String(format: "%.1f", inputs.sleepDebt))h). Prioritize an early bedtime tonight."
        default:         debtContext = "Significant sleep debt (\(String(format: "%.1f", inputs.sleepDebt))h). Your body needs multiple nights of good sleep to recover."
    }

    return SleepPrescription(
        targetBedtime: targetBedtime,
        targetSleepDuration: targetSleepDuration,
        sleepDebt: inputs.sleepDebt,
        debtContext: debtContext,
        caffeineCutoff: caffeineCutoff,
        screenCutoff: screenCutoff,
        headline: "Target: \(targetBedtime.formatted(.dateTime.hour().minute()))",
        body: "Sleep debt: \(String(format: "%.1f", inputs.sleepDebt))h. Aim for \(formatDuration(targetSleepDuration)) tonight."
    )
}
```

### 8.5 Hydration Prescription Algorithm

```
func generateHydrationPrescription(inputs: PrescriptionInputs) -> HydrationPrescription {

    // Step 1: Base hydration
    // Evidence: Sawka et al. (2007) ACSM position stand. 35ml/kg is the general
    // guideline for temperate climates. This is a starting point, not a precision target.
    let baseLiters = inputs.bodyWeightKg * 0.035  // 35ml per kg

    // Step 2: Activity adjustment
    var activityAdjustment: Double = 0
    for activity in inputs.plannedActivities {
        let hours = Double(activity.expectedDurationMin ?? 0) / 60.0
        activityAdjustment += hours * 0.5  // 500ml per hour of training
    }

    // Step 3: Heat AND humidity adjustment (Miami-specific)
    // In humid environments, sweat does not evaporate efficiently, meaning the body
    // must produce MORE sweat for the same cooling effect. This increases fluid loss
    // beyond what temperature alone would predict.
    var heatAdjustment: Double = 0
    if let temp = inputs.ambientTempFahrenheit, temp > 85 {
        heatAdjustment = 0.5  // +500ml
        if temp > 95 { heatAdjustment = 1.0 }  // +1L in extreme heat
    }
    // Humidity adjustment: when humidity > 70% and temp > 80F, add 250ml
    // even without planned training (insensible losses in subtropical climate)
    if let temp = inputs.ambientTempFahrenheit, let humidity = inputs.ambientHumidityPercent {
        if humidity > 70 && temp > 80 {
            heatAdjustment += 0.25  // +250ml for humid conditions
        }
    }

    // Step 4: Recovery adjustment
    var recoveryAdjustment: Double = 0
    if inputs.recoveryScore < 50 {
        recoveryAdjustment = 0.25  // +250ml
    }
    if inputs.recoveryScore < 30 {
        recoveryAdjustment = 0.5  // +500ml
    }

    let totalLiters = baseLiters + activityAdjustment + heatAdjustment + recoveryAdjustment

    // Step 5: Generate breakdown explanation
    var breakdownParts: [String] = ["Base: \(String(format: "%.1f", baseLiters))L"]
    if activityAdjustment > 0 {
        breakdownParts.append("+\(String(format: "%.1f", activityAdjustment))L for training")
    }
    if heatAdjustment > 0 {
        breakdownParts.append("+\(String(format: "%.1f", heatAdjustment))L for heat")
    }
    if recoveryAdjustment > 0 {
        breakdownParts.append("+\(String(format: "%.1f", recoveryAdjustment))L for low recovery")
    }

    return HydrationPrescription(
        targetLiters: totalLiters,
        headline: "Target: \(String(format: "%.1f", totalLiters))L today",
        body: breakdownParts.joined(separator: " + "),
        breakdown: breakdownParts
    )
}
```

### 8.6 Prescription Confidence Level

Each prescription carries a confidence indicator based on data completeness:

```
enum PrescriptionConfidence {
    case high       // All inputs available, 14+ days of history
    case medium     // Most inputs available, 7-14 days of history
    case low        // Missing key inputs or < 7 days of history
}
```

**Display:**
- High: no indicator (default assumption).
- Medium: small info icon next to section header. Tap: "Some data is estimated. Prescriptions improve with more Whoop history."
- Low: yellow info banner above prescription cards: "Limited data available. These prescriptions will become more personalized as we learn your patterns."

**Clinical note on confidence:** Even at "high" confidence, prescriptions are based on wearable-grade biometric data and algorithmic heuristics, not clinical assessments. The confidence level reflects data completeness, not medical certainty. All prescriptions carry the general disclaimer (see Section 1, "Medical Disclaimer & Scope").

### 8.7 Prescription Persistence & Timing

- Prescriptions are generated once per day when fresh recovery data arrives.
- Stored locally (Core Data or SwiftData) with the date as key.
- If the user opens the app before recovery data is available (e.g., 4 AM): show yesterday's prescription with a label: "Today's prescription will be ready once your Whoop processes recovery (usually by 7 AM)."
- Prescriptions do NOT change mid-day (consistency is important for trust). Exception: if user manually triggers a refresh AND new Whoop data is available.
- Historical prescriptions are preserved for the feedback loop and trend analysis.

---

## 9. Screen 6: Whoop Connection Status

Accessed from the gear icon on the Recovery Today View nav bar.

### Full Screen Layout

```
┌──────────────────────────────────────────────────┐
│ < Recovery       Whoop Connection                 │
├──────────────────────────────────────────────────┤
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │                                            │   │
│  │   [Whoop Logo]                             │   │
│  │                                            │   │
│  │   Status: ● Connected                      │   │
│  │                                            │   │
│  │   Last Sync: 2 minutes ago                 │   │
│  │   Data through: March 24, 2026 6:42 AM     │   │
│  │                                            │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Data Freshness ────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Recovery    ● Fresh     Today 6:42 AM      │   │
│  │ Sleep       ● Fresh     Today 6:42 AM      │   │
│  │ Strain      ● Fresh     Today 6:42 AM      │   │
│  │ Workouts    ● Fresh     Today 6:42 AM      │   │
│  │ Heart Rate  ● Stale     Yesterday 11:30 PM │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  [ Sync Now ]                                     │
│                                                    │
│  ── Account ───────────────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Whoop Account    user@email.com       ›    │   │
│  │ Disconnect Whoop                      ›    │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
└──────────────────────────────────────────────────┘
```

### 9.1 Connection States

**State: Connected**
- Status dot: green (8pt circle, `recovery.green.primary`).
- Status text: "Connected" — `cardBody`, `recovery.green.primary`.
- Last sync: relative time format (same as main screen sync timestamp).
- Data through: absolute date/time, format: "MMMM d, yyyy h:mm a".
- Whoop logo: centered, 48pt height, grayscale with green tint overlay.

**State: Disconnected**
- Status dot: red.
- Status text: "Disconnected" — `recovery.red.primary`.
- Below: "Tempo cannot access your Whoop data. Reconnect to resume tracking." — `cardBody`, `text.secondary`.
- Action button: "Reconnect Whoop" — primary button style (green fill, full width, 50pt height).
- Reconnect flow: opens Whoop OAuth flow in an in-app browser (ASWebAuthenticationSession). On success: returns to this screen with "Connected" state, triggers immediate sync.
- Below reconnect button: "Troubleshooting" link → expands to show:
  1. "Make sure you're logged into Whoop on your phone."
  2. "Check that Whoop app is updated to the latest version."
  3. "Try logging out and back into Whoop, then reconnect here."
  4. "Contact support if the issue persists."

**State: Syncing**
- Status dot: pulsing blue (8pt circle, `#74B9FF`, opacity pulsing 50%-100%).
- Status text: "Syncing..." — `cardBody`, `#74B9FF`.
- Progress: indeterminate. Spinning activity indicator below the status text.
- "Sync Now" button: disabled, shows "Syncing..."
- Duration: typical sync takes 2-5 seconds. Timeout: 30 seconds.

**State: Error**
- Status dot: yellow.
- Status text: "Connection Error" — `recovery.yellow.primary`.
- Error details: "Last attempt failed: [error description]" — `reasoningText`, `text.secondary`.
- Action buttons: "Try Again" (primary) + "Reconnect" (secondary).
- Error descriptions (mapped from API errors):
  - 401: "Authentication expired. Please reconnect."
  - 429: "Whoop API rate limit reached. Please wait a few minutes."
  - 500+: "Whoop's servers are temporarily unavailable."
  - Network error: "No internet connection. Check your network."

### 9.2 Data Freshness Table

Each data category shows:
- Name: "Recovery", "Sleep", "Strain", "Workouts", "Heart Rate"
- Status dot: green ("Fresh" — data from today), yellow ("Stale" — data from yesterday or older), red ("Missing" — no data).
- Timestamp: when this data was last updated. Format: "Today [time]" or "[Day] [time]".
- "Fresh" threshold: data timestamp is from today.
- "Stale" threshold: data timestamp is from yesterday.
- "Missing": no data found for this category.

### 9.3 Sync Now Button

- Full width, secondary style (1pt `divider` border, transparent fill, `text.primary` text).
- Height: 44pt. Corner radius: 10pt.
- Tap: triggers Whoop API sync. Button transitions to loading state (spinner replaces text).
- On success: button text briefly shows "Synced!" with a checkmark, then returns to "Sync Now" after 2 seconds.
- On failure: button text shows "Sync Failed" in red, then returns to "Sync Now" after 3 seconds. Error details appear in a toast at the top of the screen.
- Cooldown: cannot trigger sync more than once per 60 seconds. If tapped within cooldown: button shows "Try again in [X]s" and does not trigger.

### 9.4 Account Section

- "Whoop Account": shows the email associated with the connected Whoop account. Tapping opens the Whoop app (if installed) or Whoop website.
- "Disconnect Whoop": tapping shows a confirmation alert.
  - Alert title: "Disconnect Whoop?"
  - Alert message: "Tempo will no longer receive your recovery, sleep, and strain data. You can reconnect at any time."
  - Actions: "Disconnect" (destructive, red text) | "Cancel"
  - On disconnect: clears OAuth tokens, transitions to Disconnected state. Does NOT delete historical data.

---

## 10. Screen 7: Recovery Notifications

These are push notifications and in-app banners generated by the prescription engine. Configured in Tempo's Settings screen (not part of RecoverIQ module directly, but specified here for completeness).

### 10.1 Notification Types

#### Morning Recovery Report
- **Trigger:** Fires when fresh recovery data is available (typically 5-7 AM). If user has set a wake alarm in Tempo, fires at wake time.
- **Title:** "Good morning"
- **Body:** "Recovery: [XX]% ([Zone]). [One-sentence training recommendation]."
- **Examples:**
  - "Recovery: 78% (Green). Full send today — your body is ready for a big session."
  - "Recovery: 45% (Yellow). Keep it moderate today. Reduce volume, maintain intensity."
  - "Recovery: 22% (Red). Rest day. Focus on sleep and nutrition."
- **Category:** `morning_recovery` — allows custom notification actions.
- **Actions:**
  - "View Prescription" → opens Recovery Today View.
  - "Dismiss" → dismisses notification.
- **Sound:** Custom gentle chime (0.5s). Not the default iOS sound.
- **Badge:** Updates app badge to show recovery score (e.g., "78"). Clears when app is opened.

#### Low Recovery Alert
- **Trigger:** Fires with morning report only if recovery < 34% (red zone).
- **Title:** "Recovery Alert"
- **Body:** "Recovery: [XX]%. [Specific recommendation]. Your body needs rest."
- **Examples:**
  - "Recovery: 28%. Swap your gym session for mobility or a walk. Your body needs rest."
  - "Recovery: 15%. Rest day recommended. Skip structured training. Prioritize sleep tonight."
- **Priority:** `.timeSensitive` (bypasses Focus mode if enabled).
- **Sound:** Slightly more urgent chime. Still gentle, not alarming.
- **Safety rule:** This notification must NEVER suggest the user can "push through" or "train anyway if you feel fine." The app must not encourage training through red recovery. The user can choose to override in MODULE_TRAINING.md's manual override system, but the prescription engine's job is to recommend rest. Language must be prescriptive ("rest day recommended") not permissive ("you could still train light").

#### Bedtime Reminder
- **Trigger:** Fires 30 minutes before target bedtime.
- **Title:** "Bedtime in 30 minutes"
- **Body:** "Start winding down. Put screens away by [screen cutoff time]. Target: [bedtime]."
- **Category:** `bedtime_reminder`
- **Actions:**
  - "Set Alarm" → opens Clock app with alarm pre-set for wake time (if iOS allows deep link).
  - "Snooze 30m" → reschedules notification for 30 minutes later. Only available once.
  - "Dismiss"

#### Sleep Debt Warning
- **Trigger:** Fires with morning report if cumulative sleep debt exceeds 4.0 hours.
- **Frequency:** Maximum once every 3 days (avoid nagging).
- **Title:** "Sleep Debt Warning"
- **Body:** "You've accumulated [X.X]h of sleep debt this week. Aim for [Y]h sleep tonight to start recovering."
- **Priority:** Standard.

#### Post-Workout Protein Reminder
- **Trigger:** Fires when a Whoop workout ends (detected via Whoop activity data becoming available). If Whoop doesn't provide real-time workout end: fires 1 hour after a workout start is detected.
- **Title:** "Post-workout nutrition"
- **Body:** "Hit 30-40g protein within the next hour for optimal recovery."
- **Category:** `post_workout`
- **Actions:**
  - "Log Meal" → opens NutriTrack (if integrated) or Tempo's nutrition input.
  - "Dismiss"

#### Caffeine Cutoff Reminder
- **Trigger:** Fires 15 minutes before the calculated caffeine cutoff time.
- **Title:** "Caffeine cutoff in 15 minutes"
- **Body:** "Switch to water or herbal tea after [cutoff time] to protect tonight's sleep."
- **Frequency:** Daily (if user hasn't disabled).

### 10.2 Notification Settings

Accessible from Tempo Settings > Notifications > Recovery.

| Setting | Default | Options |
|---|---|---|
| Morning Recovery Report | ON | ON / OFF |
| Low Recovery Alert | ON | ON / OFF |
| Bedtime Reminder | ON | ON / OFF / Custom time offset (15/30/45/60 min before) |
| Sleep Debt Warning | ON | ON / OFF |
| Post-Workout Protein | ON | ON / OFF |
| Caffeine Cutoff | OFF | ON / OFF |

**UI:** Standard iOS Settings-style list with toggles. Each setting has a subtitle explaining what it does.

### 10.3 In-App Banners

When the user is actively in the app, notifications appear as in-app banners instead of push notifications.

**Banner style:**
- Appears at the top of the screen, below the status bar.
- Height: 64pt.
- Background: `surface.cardElevated` with slight blur.
- Corner radius: 12pt (bottom corners only).
- Icon: relevant emoji (same as notification).
- Title + body: truncated to 2 lines.
- Swipe up to dismiss. Auto-dismisses after 5 seconds.
- Tap: navigates to relevant screen.

---

## 11. Screen 8: Historical Comparison

Accessed from "Compare" button on the Recovery Trends View nav bar.

### Full Screen Layout

```
┌──────────────────────────────────────────────────┐
│ < Trends        Comparison                        │
├──────────────────────────────────────────────────┤
│                                                    │
│  ── This Week vs Last Week ────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │              This Week    Last Week   Δ    │   │
│  │ Recovery     71%          68%        +3%   │   │
│  │ HRV          65 ms        61 ms      +7%   │   │
│  │ RHR          53 bpm       55 bpm     -4%   │   │
│  │ Sleep        7h 18m       6h 52m    +26m   │   │
│  │ Strain       12.4         13.8       -10%  │   │
│  │ Consistency  82%          74%        +8%   │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  Overall: ↑ Improving                              │
│  Your recovery metrics are trending positively.    │
│  Sleep consistency improvement is the biggest      │
│  factor.                                           │
│                                                    │
│  ── Monthly Averages ──────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 80%─                                       │   │
│  │     │       ╱╲                             │   │
│  │ 70%─│      ╱  ╲      ╱╲                  │   │  ← Monthly avg
│  │     │     ╱    ╲    ╱  ╲    ●            │   │     recovery trend
│  │ 60%─│    ╱      ╲  ╱    ╲  ╱             │   │
│  │     │   ╱        ╲╱      ╲╱              │   │
│  │ 50%─│──╱                                  │   │
│  │     Oct  Nov  Dec  Jan  Feb  Mar          │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Personal Records ──────────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ 🏆  Personal Records (Last 90 Days)        │   │
│  │                                            │   │
│  │ Highest Recovery    94%     Mar 15         │   │
│  │ Best HRV            82 ms   Mar 12         │   │
│  │ Lowest RHR          49 bpm  Feb 28         │   │
│  │ Best Sleep Score    96%     Mar 8          │   │
│  │ Longest Green Streak  5 days  Mar 10-14   │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ── Your Recovery Profile ─────────────────────── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Based on 87 days of data:                  │   │
│  │                                            │   │
│  │ You're a consistent recoverer. Your        │   │
│  │ recovery stays in the green zone 62% of    │   │
│  │ days. Sleep is your primary recovery        │   │
│  │ driver — when you get 7.5h+, your recovery │   │
│  │ averages 76%. Your HRV responds quickly    │   │
│  │ to rest days (typically +15% the day after  │   │
│  │ rest). You handle high strain well but need │   │
│  │ at least one easy day per 3 hard days.     │   │
│  │                                            │   │
│  │ Strengths:                                 │   │
│  │ • High strain tolerance                    │   │
│  │ • Quick HRV rebound after rest             │   │
│  │                                            │   │
│  │ Areas to improve:                          │   │
│  │ • Bedtime consistency (varies by 1.5h)     │   │
│  │ • Weekend recovery (drops 12% vs weekdays) │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
└──────────────────────────────────────────────────┘
```

### 11.1 This Week vs Last Week

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**Table Layout:**
- 4 columns: Metric | This Week | Last Week | Delta
- Header row: `metricLabel`, `text.tertiary`, bold.
- Data rows: 6 metrics (Recovery, HRV, RHR, Sleep, Strain, Consistency).
- Each cell: `cardBody`, `text.primary` for values, delta column colored (green = improvement, red = decline, gray = neutral).
- Row height: 36pt. Alternating row backgrounds: transparent and `surface.primary` @ 30% (subtle banding).

**Metric calculations:**
- "This Week" = average of available days in the current week (Mon-today).
- "Last Week" = average of all 7 days last week.
- Delta: percentage change for %, bpm, ms metrics. Absolute change for sleep duration ("+26m"). Direction matters: for RHR, a decrease is positive (green). For strain, lower can be either neutral or intentional (gray).

**Improvement direction:**
| Metric | Improvement = |
|---|---|
| Recovery | Higher |
| HRV | Higher |
| RHR | Lower |
| Sleep | More (up to a point; > 9h is yellow) |
| Strain | Context-dependent (gray) |
| Consistency | Higher |

**Summary text (below table):**
- "Overall: ↑ Improving" / "Overall: → Steady" / "Overall: ↓ Declining"
- Determined by: count of improving metrics vs declining. If more improving: "Improving". If more declining: "Declining". Equal or mixed: "Steady".
- 1-2 sentences identifying the primary driver of change.
- Font: `cardBody`, `text.primary` for the summary, `reasoningText`, `text.secondary` for the detail sentences.

### 11.2 Monthly Average Trend

**Chart:** `TrendChart`, type: `.line`.
- Data: one point per month, representing the average recovery for that month.
- X-axis: month abbreviations (Oct, Nov, Dec, ...).
- Y-axis: 0-100% recovery.
- Data range: up to 12 months of history (or however much is available).
- Current month's point: emphasized with a larger dot and "current" label.
- Color: `recovery.green.primary`.
- If < 2 months of data: show a message instead of chart: "Monthly trends will appear after your second month of data."

### 11.3 Personal Records

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**Header:** "🏆 Personal Records (Last 90 Days)" — `cardTitle`.

**Records table:** 5 rows.

| Record | Value | Date |
|---|---|---|
| Highest Recovery | "[XX]%" | "[MMM d]" |
| Best HRV | "[XX] ms" | "[MMM d]" |
| Lowest RHR | "[XX] bpm" | "[MMM d]" |
| Best Sleep Score | "[XX]%" | "[MMM d]" |
| Longest Green Streak | "[N] days" | "[MMM d]-[MMM d]" |

- Leading label: `cardBody`, `text.secondary`.
- Value: `metricValue` (smaller, 20pt), `text.primary`.
- Date: `sparklineLabel`, `text.tertiary`, trailing-aligned.
- Row height: 36pt.

**Green Streak:** consecutive days with recovery >= 67%. "Longest" = the maximum consecutive run in the last 90 days.

**New record highlight:** If any record was set in the last 7 days, that row gets a subtle golden glow/border (`#FFD700` @ 20% opacity) and a "NEW" badge (small capsule, golden, trailing).

### 11.4 Your Recovery Profile

**Card:** `surface.card`, corner radius: 16pt, padding: 16pt.

**Content:** A natural-language summary of the user's recovery patterns, generated algorithmically. This is the most personalized feature in the module.

**Header:** "Based on [N] days of data:" — `metricLabel`, `text.tertiary`.

**Body:** 3-5 sentences covering:
1. **Recovery consistency** — what percentage of days are green/yellow/red.
2. **Primary recovery driver** — the factor most correlated with good recovery (usually sleep duration or sleep consistency).
3. **Strain response** — how quickly HRV/recovery bounces back after hard days.
4. **Optimal pattern** — the training-to-rest ratio that produces best recovery.

**Strengths and Areas to Improve:**
- Bullet lists, 2 items each.
- Strengths: green dot prefix, `text.primary`.
- Areas: yellow dot prefix, `text.primary`.
- Determined by ranking the user's metrics against their own history and identifying top/bottom performers.

**Minimum data requirement:** 30 days. Below that: show "We're building your recovery profile. It will be ready after 30 days of consistent Whoop use. You're on day [N]." with a progress bar showing N/30.

**Clinical note:** The recovery profile is based on correlations in the user's own data. Correlations are not causation — e.g., "recovery is higher after rest days" does not necessarily mean rest causes higher recovery; both may be influenced by a third factor (e.g., weekend vs. weekday stress patterns). The profile should use language like "Your recovery tends to be higher when..." rather than "Rest causes better recovery." This keeps the app honest about what the data can and cannot prove.

**Font:** `cardBody` for the main paragraph, `reasoningText` for bullets.

---

## 12. Accessibility & Edge Cases

### 12.1 Accessibility

**VoiceOver:**
- All MetricTiles: accessibilityLabel includes metric name, value, unit, and trend. Example: "HRV, 68 milliseconds, up 12 percent from yesterday."
- RecoveryRing: "Recovery score: 78 percent. Green zone. 12 percent above your 30-day average."
- PrescriptionCards: read full headline and body. "Why this recommendation" button is labeled: "View reasoning for [category] prescription."
- Charts: accessibilityLabel summarizes the data. "Recovery trend over 7 days. Lowest: 58 percent on Tuesday. Highest: 82 percent on Saturday. Average: 71 percent." Audio graph trait enabled where available (iOS 15+).
- Color-coded elements: always have a text equivalent (e.g., zone label "Green", "Yellow", "Red" in addition to color).

**Dynamic Type:**
- All text scales with Dynamic Type up to AX5.
- MetricTiles: if text overflows, tiles increase height (not width). Sparklines may be hidden at largest text sizes.
- RecoveryRing: score font scales down to 48pt minimum. Ring size remains fixed.
- PrescriptionCards: height grows with content. No truncation.
- Charts: fixed height (200pt). Labels scale but chart area is preserved.

**Reduce Motion:**
- If "Reduce Motion" is enabled: ring fill appears instantly (no animation), score appears at final value (no count-up), chart transitions are crossfades instead of animations, shimmer loading states replaced with static gray placeholders.

**Color Blind Support:**
- In addition to color, zones are indicated by text labels ("Green", "Yellow", "Red").
- Trend arrows use direction (up/down/flat) as the primary indicator, with color as secondary.
- Charts include a pattern option (in Settings): dashed lines, dotted lines, and solid lines instead of relying solely on color to differentiate metrics.

### 12.2 Edge Cases

**No Whoop connected (first launch):**
- Recovery Today View shows an onboarding card instead of the ring:
  ```
  ┌────────────────────────────────────────┐
  │  Connect your Whoop to get started     │
  │                                        │
  │  RecoverIQ turns your Whoop data into  │
  │  daily prescriptions — what to train,  │
  │  eat, and when to sleep.               │
  │                                        │
  │  [ Connect Whoop ]                     │
  └────────────────────────────────────────┘
  ```
- No other content shown below this card.

**Whoop worn but recovery not yet processed:**
- Ring shows "--" with pulsing animation.
- Previous night's sleep data may be available: show sleep teaser.
- Prescription section: "Your prescription will be ready once Whoop processes your recovery. This usually happens within 30 minutes of waking."
- If it's past 10 AM and still no data: show a "Having trouble?" link to Whoop Connection Status.

**User slept with Whoop off (no sleep data):**
- Sleep teaser: "No sleep data detected. Was your Whoop charged and worn?"
- Prescription engine: generates conservative prescriptions (treats as yellow zone if recovery is unavailable, skips sleep-based prescriptions).
- Sleep Detail View: "No sleep recorded for last night. Whoop requires consistent wear to track sleep."

**Whoop battery died mid-sleep:**
- Partial sleep data may be available. Sleep stages bar shows available data with a gray "Unknown" segment.
- Prescription engine: flags "partial sleep data" in reasoning. Makes best-effort prescription with available data.

**No planned activities entered:**
- Training prescription still generates based on recovery zone alone.
- Nutrition prescription uses conservative estimates (no strain-specific carb adjustments).
- Hydration prescription uses base only (no activity adjustment).
- A subtle prompt appears below prescriptions: "Add your planned activities for more personalized prescriptions."

**NutriTrack not connected:**
- Meal timing prescriptions give general guidance (not specific macro numbers).
- No "remaining protein" or tracking-based recommendations.
- A prompt in the nutrition card: "Connect NutriTrack for macro-specific recommendations."

**Timezone change (travel):**
- Bedtime prescription uses the device's current timezone.
- Sleep data from Whoop is in UTC; convert to local time for display.
- If timezone changed in the last 24h: add a note to sleep prescription: "You recently changed timezones. It may take 1-2 days for your body to adjust. Prioritize sleep consistency."

**Very first day with Whoop (no historical data):**
- No trends, comparisons, or pattern insights.
- MetricTiles show values but no trend arrows (no yesterday to compare to). HRV tile shows no color coding during calibration (see Section 1, "Calibration Period").
- Sparklines show a single dot.
- Prescription engine: within first 7 days, no prescriptions are generated (see Section 1, "Calibration Period"). Days 8-13 use population averages. Day 14+ uses personal baselines. Confidence: `.low` until day 14, `.medium` until day 30, `.high` thereafter.
- Recovery Profile: "Day 1! We'll start building your profile as data comes in. Wear your Whoop consistently — we need 14 days to personalize your prescriptions."

**Recovery score of exactly 34 or 67 (zone boundary):**
- 34 maps to yellow zone (inclusive lower bound: 34-66 = yellow).
- 67 maps to green zone (inclusive lower bound: 67-100 = green).
- Consistent throughout all components.

**When to recommend professional consultation (per EXERCISE_SCIENCE.md Section 9.8):**
The app must display a persistent advisory banner and recommend consulting a healthcare professional when:
1. Recovery is red (<34%) for 7+ consecutive days.
2. Resting heart rate is >10 bpm above 30-day baseline for 3+ consecutive days.
3. Sleep duration is <5 hours for 5+ consecutive nights.
4. The user cannot complete any prescribed workout for 2+ consecutive weeks.

**Banner text:** "Your recovery has been consistently low for [X] days. While this can happen during stressful periods, prolonged patterns like this may warrant a check-in with a doctor or sports medicine professional. This is not an emergency — just a smart precaution." This banner persists until the condition resolves or the user dismisses with acknowledgment.

> **APP STORE COMPLIANCE -- "Consult a Healthcare Professional" Requirement:**
> This banner is critical for App Store compliance. Health apps that provide recovery and
> training recommendations MUST direct users to professional medical advice when data
> suggests a persistent issue. The banner MUST:
> 1. Appear automatically when any of the 4 trigger conditions above are met.
> 2. Be visually distinct (not easily confused with a standard prescription card).
> 3. Include the word "doctor" or "healthcare professional" explicitly.
> 4. NOT be dismissible without the user tapping "I understand" (acknowledgment gate).
> 5. Re-appear if the condition persists after dismissal (once per 7-day cycle).
>
> The banner is NOT a diagnosis. It is a responsible wellness app behavior that Apple
> reviewers specifically look for in health apps. See `docs/APP_STORE_COMPLIANCE.md`
> Section 6.2 for the full specification.

---

## 13. Data Formatting Rules

### 13.1 Numbers

| Data | Format | Examples | Rounding |
|---|---|---|---|
| Recovery score | Integer, no % symbol in ring, % in text | "78" (ring), "78%" (text) | Round to nearest integer |
| HRV | Integer + "ms" | "68 ms" | Round to nearest integer |
| RHR | Integer + "bpm" | "52 bpm" | Round to nearest integer |
| SpO2 | Integer + "%" | "97%" | Round to nearest integer |
| Skin temp | 1 decimal + "°C" | "36.8°C" | Round to 1 decimal |
| Strain | 1 decimal (no unit) | "14.2" | Round to 1 decimal |
| Calories | Integer with thousands separator + "kcal" | "2,847 kcal" | Round to nearest integer |
| Sleep duration | Hours + minutes | "7h 23m" | Round minutes to nearest integer |
| Sleep percentage | 1 decimal + "%" | "91.3%" | Round to 1 decimal |
| Hydration | 1 decimal + "L" | "3.2L" | Round to 1 decimal |
| Protein/carbs/fat | Integer + "g" | "45g" | Round to nearest integer |
| Respiratory rate | 1 decimal + "br/min" | "15.2 br/min" | Round to 1 decimal |
| Heart rate (avg/max) | Integer + "bpm" | "186 bpm" | Round to nearest integer |
| Time of day | 12-hour, no leading zero | "10:30 PM", "2:00 PM" | To nearest minute |
| Trend percentage | Integer + "%" | "↑ 12%", "↓ 5%" | Round to nearest integer |
| Sleep debt | 1 decimal + "h" | "2.1h" | Round to 1 decimal |
| Body weight | 1 decimal + "kg" | "72.5 kg" | Round to 1 decimal |
| Temperature (ambient) | Integer + "°F" | "85°F" | Round to nearest integer |

### 13.2 Dates & Times

| Context | Format | Example |
|---|---|---|
| Full date (labels) | "EEEE, MMMM d" | "Monday, March 24" |
| Date in tables/records | "MMM d" | "Mar 15" |
| Date range | "MMM d-MMM d" or "MMM d-d" (same month) | "Mar 10-14" or "Feb 28-Mar 3" |
| Time of day | "h:mm a" (12-hour, no leading zero) | "10:30 PM", "2:00 PM" |
| Relative time (sync) | Custom relative | "Just now", "2 min ago", "1h ago" |
| Month in chart | "MMM" | "Mar" |
| Day abbreviation | First letter or three letters | "M" or "Mon" |

### 13.3 Text Formatting

- Prescription headlines: sentence case, no period at end.
- Prescription body: sentence case, period at end.
- Metric labels: title case (e.g., "Resting Heart Rate", "Sleep Consistency").
- Section headers: title case.
- Zone labels: capitalized ("Green", "Yellow", "Red").
- Trend text: no period ("↑ 12% above your average").

### 13.4 Locale Handling

- Number formatting: respect device locale for decimal separators and thousands separators. US default: "2,847" and "3.2". European: "2.847" and "3,2".
- Date formatting: respect device locale. US: "March 24, 2026". UK: "24 March 2026".
- Temperature: display in °C by default. Add a setting for °F preference (convert: °F = °C * 9/5 + 32).
- Time: respect 12h/24h device setting. If 24h: "22:30" instead of "10:30 PM".
- Hydration: liters by default. Add a setting for oz preference (1L = 33.814 oz, display as "108 oz").

---

## 14. Animation Specifications

### 14.1 Screen Transitions

| Transition | Type | Duration | Easing |
|---|---|---|---|
| Tab switch to Recovery | Standard iOS tab crossfade | 0.2s | `.easeInOut` |
| Push to detail view | Standard iOS push (slide left) | 0.35s | `.spring(response: 0.35, dampingFraction: 0.9)` |
| Sheet presentation | iOS sheet (slide up from bottom) | 0.3s | `.spring(response: 0.3, dampingFraction: 0.85)` |
| Sheet dismissal | Slide down + fade | 0.25s | `.easeOut` |

### 14.2 Component Animations

| Component | Animation | Duration | Easing | Trigger |
|---|---|---|---|---|
| RecoveryRing fill | Arc grows from 0 to value | 1.2s | `.spring(response: 0.8, dampingFraction: 0.7)` | On appear |
| RecoveryRing score | Numeric count up | 1.2s | Synced with ring | On appear |
| RecoveryRing glow | Fade in | 0.5s | `.easeIn` | After ring completes |
| MetricTile expand | Height grows, sparkline slides in | 0.3s | `.spring(response: 0.3, dampingFraction: 0.85)` | On tap |
| MetricTile collapse | Height shrinks, sparkline slides out | 0.25s | `.easeOut` | On tap elsewhere |
| PrescriptionCard appear | Slide up + fade in, staggered | 0.4s each, 0.1s stagger | `.spring(response: 0.4, dampingFraction: 0.8)` | On appear (after ring completes) |
| Sleep stages bar | Segments grow left to right | 0.5s total, 0.1s stagger per segment | `.easeOut` | On appear |
| HR zone bars | Bars grow from left | 0.4s total, 0.05s stagger bottom to top | `.spring(response: 0.3, dampingFraction: 0.8)` | On appear |
| Heatmap cells | Fade in, staggered by column | 0.3s per column, 0.05s stagger | `.easeIn` | On appear |
| Chart data transition | Crossfade/morph between datasets | 0.3s | `.easeInOut` | On time range change |
| Shimmer loading | Diagonal light sweep | 1.5s loop | Linear | While loading |
| Feedback card collapse | Height shrinks to single line | 0.3s | `.easeOut` | On submit |
| Toast appear | Slide down from top | 0.3s | `.spring(response: 0.3, dampingFraction: 0.8)` | On trigger |
| Toast disappear | Slide up + fade | 0.2s | `.easeIn` | After 5s or swipe up |
| Pull-to-refresh ring | Rotate 360 degrees | 0.8s | `.linear` (continuous) | While refreshing |
| Nav bar compact transition | Opacity crossfade | 0.2s | `.easeInOut` | On scroll threshold |

### 14.3 Haptic Feedback

| Action | Haptic Type |
|---|---|
| MetricTile tap | `.impact(.light)` |
| PrescriptionCard tap | `.impact(.light)` |
| Chart scrub activation (long press) | `.impact(.medium)` |
| Chart scrub data point crossing | `.impact(.soft)` (on each point) |
| Feedback button tap | `.impact(.light)` |
| Feedback submit | `.notification(.success)` |
| Pull-to-refresh trigger | `.impact(.medium)` |
| Sync complete (success) | `.notification(.success)` |
| Sync failed | `.notification(.error)` |
| Time range pill change | `.selection` |
| Recovery ring animation complete | `.notification(.success)` |
| Heatmap cell tap | `.impact(.light)` |
| Record new personal best (first view) | `.notification(.success)` |

### 14.4 Scroll Behavior

- Main Recovery Today View: standard `ScrollView` with bouncy overscroll.
- Scroll indicator: hidden (`.scrollIndicators(.hidden)`).
- Content insets: top: 0 (content starts at nav bar), bottom: `tabBar.height` + 32pt.
- Lazy loading: charts and trend sections use `LazyVStack` to defer rendering until visible. Prescription cards are in a regular `VStack` (always rendered, as they're above the fold).
- Scroll-to-top: tapping the tab bar icon when already on Recovery tab scrolls to top with animation.

---

## Appendix A: Whoop API Data Mapping

| Tempo Field | Whoop API Endpoint | Whoop Field |
|---|---|---|
| Recovery score | `GET /v1/recovery` | `score.recovery_score` |
| HRV | `GET /v1/recovery` | `score.hrv_rmssd_milli` |
| RHR | `GET /v1/recovery` | `score.resting_heart_rate` |
| SpO2 | `GET /v1/recovery` | `score.spo2_percentage` |
| Skin temp | `GET /v1/recovery` | `score.skin_temp_celsius` |
| Sleep performance | `GET /v1/sleep` | `score.sleep_performance_percentage` |
| Sleep efficiency | `GET /v1/sleep` | `score.sleep_efficiency_percentage` |
| Sleep consistency | `GET /v1/sleep` | `score.sleep_consistency_percentage` |
| Total sleep time | `GET /v1/sleep` | `score.stage_summary.total_in_bed_time_milli - score.stage_summary.total_awake_time_milli` |
| SWS (deep) | `GET /v1/sleep` | `score.stage_summary.total_slow_wave_sleep_time_milli` |
| REM | `GET /v1/sleep` | `score.stage_summary.total_rem_sleep_time_milli` |
| Light sleep | `GET /v1/sleep` | `score.stage_summary.total_light_sleep_time_milli` |
| Awake time | `GET /v1/sleep` | `score.stage_summary.total_awake_time_milli` |
| Sleep needed | `GET /v1/sleep` | `score.sleep_needed` (baseline + debt + strain) |
| Respiratory rate | `GET /v1/sleep` | `score.respiratory_rate` |
| Strain | `GET /v1/cycle` | `score.strain` |
| Calories (active) | `GET /v1/cycle` | `score.kilojoule` (convert to kcal) |
| Average HR | `GET /v1/cycle` | `score.average_heart_rate` |
| Max HR | `GET /v1/cycle` | `score.max_heart_rate` |
| Workout strain | `GET /v1/workout` | `score.strain` |
| Zone durations | `GET /v1/workout` | `score.zone_duration` (zones 0-5 → zones 1-6) |
| Workout HR data | `GET /v1/workout` | `score.average_heart_rate`, `score.max_heart_rate` |
| Workout distance | `GET /v1/workout` | `score.distance_meter` |

## Appendix B: Color Quick Reference

```
Recovery Zones (tempo.color.recovery.*):
  Green  (#22C55E / dark: #4ADE80): recovery >= 67%
  Yellow (#EAB308 / dark: #FACC15): recovery 34-66%
  Red    (#DC2626 / dark: #F87171): recovery < 34%

Sleep Score Zones (tempo.color.recovery.*):
  Green  (#22C55E / dark: #4ADE80): performance >= 85%
  Yellow (#EAB308 / dark: #FACC15): performance 70-84%
  Red    (#DC2626 / dark: #F87171): performance < 70%

Sleep Stages:
  Awake  (#FF6B6B)
  Light  (#74B9FF)
  Deep   (#0652DD)
  REM    (#A29BFE)

HR Zones:
  Zone 1 (#B8E6F0)
  Zone 2 (#74B9FF)
  Zone 3 (#22C55E)
  Zone 4 (#EAB308)
  Zone 5 (#FF8C42)
  Zone 6 (#DC2626)

Surfaces (dark mode — aligned with Design System):
  Primary    (#0D0D0D) — tempo.color.bg.primary
  Card       (#1C1C1E) — tempo.color.surface.card
  Elevated   (#2C2C2E) — tempo.color.surface.sheet

Text (dark mode — aligned with Design System):
  Primary    (#F5F2ED) — tempo.color.text.primary
  Secondary  (#A1A1AA) — tempo.color.text.secondary
  Tertiary   (#8E8E93) — tempo.color.text.tertiary

Dividers:    (#38383A) — tempo.color.divider.default
```

---

*End of RecoverIQ Module UX Specification. This document is the single source of truth for all recovery module design and behavior.*
