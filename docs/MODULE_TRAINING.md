# RepForge — Training Module UX Specification

**App**: Tempo (iOS, SwiftUI)
**Module Codename**: RepForge
**Version**: 2.0
**Last Updated**: 2026-03-24
**Author**: UX Specification — Exhaustive (CSCS-informed)

---

## Table of Contents

1. [Design System & Foundations](#1-design-system--foundations)
2. [Today's Workout View](#2-todays-workout-view)
3. [Active Workout View](#3-active-workout-view)
4. [Weight Input System (Deep Dive)](#4-weight-input-system-deep-dive)
5. [Plate Calculator](#5-plate-calculator)
6. [Superset, Circuit & Drop Set Support](#6-superset-circuit--drop-set-support)
7. [Rest Timer System](#7-rest-timer-system)
8. [Workout Summary (Post-Workout)](#8-workout-summary-post-workout)
9. [Week Plan View](#9-week-plan-view)
10. [Exercise Library (150+ Exercises)](#10-exercise-library-150-exercises)
11. [Progress Charts](#11-progress-charts)
12. [Personal Records System](#12-personal-records-system)
13. [Running & Cardio Module (Deep Dive)](#13-running--cardio-module-deep-dive)
14. [Training Settings](#14-training-settings)
15. [Workout Generation Algorithm](#15-workout-generation-algorithm)
16. [Progressive Overload Logic](#16-progressive-overload-logic)
17. [Recovery-Based Adjustment Algorithm](#17-recovery-based-adjustment-algorithm)
18. [Football Integration (Deep Dive)](#18-football-integration-deep-dive)
19. [Deload Week Specification](#19-deload-week-specification)
20. [Import / Export System](#20-import--export-system)
21. [Apple Watch Companion](#21-apple-watch-companion)
22. [Appendices](#appendices)

---

## 1. Design System & Foundations

### 1.1 Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `tempo.color.primary.signal` | `#E63946` | CTAs, active states, PR highlights |
| `tempo.color.primary.signal.pressed` | `#C62E3A` | Pressed state of primary buttons |
| `tempo.color.surface.card` | `#1A1A1E` | Card backgrounds |
| `tempo.color.bg.primary` | `#0F0F12` | Screen backgrounds |
| `tempo.color.surface.elevated` | `#242429` | Elevated cards, modals |
| `tempo.color.text.primary` | `#FFFFFF` | Headings, primary labels |
| `tempo.color.text.secondary` | `#8E8E93` | Subtext, timestamps |
| `tempo.color.text.tertiary` | `#5A5A5E` | Disabled text, placeholders |
| `tempo.color.recovery.green` | `#22C55E` | Whoop green zone (>=67%) |
| `tempo.color.recovery.yellow` | `#EAB308` | Whoop yellow zone (34-66%) |
| `tempo.color.recovery.red` | `#DC2626` | Whoop red zone (<34%) |
| `tempo.color.training.setComplete` | `#22C55E` | Completed set indicator |
| `tempo.color.training.setActive` | `#E63946` | Current set indicator |
| `tempo.color.training.setUpcoming` | `#3A3A3E` | Upcoming set indicator |
| `tempo.color.training.supersetA` | `#5E5CE6` | Superset connector color A |
| `tempo.color.training.supersetB` | `#BF5AF2` | Superset connector color B |
| `tempo.color.training.circuit` | `#FF9F0A` | Circuit connector color |
| `tempo.color.training.dropSet` | `#FF375F` | Drop set indicator |
| `tempo.color.divider.default` | `#38383A` | Separator lines |
| `tempo.color.training.prGold` | `#FFD700` | Personal record badge |
| `tempo.color.training.prSilver` | `#C0C0C0` | Runner-up / secondary PR |
| `tempo.color.training.deloadBlue` | `#64D2FF` | Deload week indicator |
| `tempo.color.training.plateRed` | `#E74C3C` | 25kg plate visual |
| `plateBlue` | `#3498DB` | 20kg plate visual |
| `plateYellow` | `#F1C40F` | 15kg plate visual |
| `plateGreen` | `#2ECC71` | 10kg plate visual |
| `plateWhite` | `#ECF0F1` | 5kg plate visual |
| `plateSmall` | `#95A5A6` | 2.5kg and 1.25kg plate visual |

### 1.2 Typography

| Style | Font | Size | Weight | Tracking |
|-------|------|------|--------|----------|
| `heroTitle` | SF Pro Display | 34pt | Bold | -0.4 |
| `screenTitle` | SF Pro Display | 28pt | Bold | -0.4 |
| `sectionHeader` | SF Pro Text | 20pt | Semibold | -0.2 |
| `cardTitle` | SF Pro Text | 17pt | Semibold | -0.2 |
| `body` | SF Pro Text | 15pt | Regular | 0 |
| `bodyBold` | SF Pro Text | 15pt | Semibold | 0 |
| `caption` | SF Pro Text | 13pt | Regular | 0.1 |
| `captionBold` | SF Pro Text | 13pt | Semibold | 0.1 |
| `metric` | SF Mono | 48pt | Bold | -1.0 |
| `metricSmall` | SF Mono | 28pt | Semibold | -0.5 |
| `timerDisplay` | SF Mono | 72pt | Bold | -2.0 |
| `weightInput` | SF Mono | 32pt | Bold | -0.5 |
| `miniTag` | SF Pro Text | 11pt | Medium | 0.5 |
| `plateLabel` | SF Mono | 14pt | Bold | 0 |

### 1.3 Spacing System

Base unit: 4pt.

| Token | Value | Design System Token |
|-------|-------|---------------------|
| `xs` | 4pt | `tempo.space.xs` |
| `sm` | 8pt | `tempo.space.sm` |
| `md` | 12pt | `tempo.space.md` |
| `lg` | 16pt | `tempo.space.lg` |
| `xl` | 20pt | `tempo.space.xl` |
| `2xl` | 24pt | `tempo.space.2xl` |
| `3xl` | 32pt | `tempo.space.3xl` |

### 1.4 Component Dimensions

| Component | Height | Corner Radius |
|-----------|--------|---------------|
| Primary button | 56pt | 14pt (`tempo.radius.2xl`) |
| Secondary button | 44pt | 14pt (`tempo.radius.2xl`) |
| Exercise card | Dynamic (min 88pt) | 16pt |
| Set logging row | 64pt | 12pt |
| Navigation bar | 44pt (standard) | 0 |
| Tab bar | 49pt (+34pt safe area on Face ID devices = 83pt total) | 0 |
| Bottom sheet handle | 4pt x 36pt | 2pt |
| Recovery badge | 36pt | 18pt (pill) |
| Muscle tag | 24pt | 12pt (pill) |
| Rest timer circle | 200pt diameter | 100pt (circle) |
| Input stepper | 44pt x 44pt | 12pt |
| Plate disc (visual) | varies by weight | 50% (circle) |
| Quick-add weight button | 56pt x 36pt | 10pt |
| Scroll wheel picker | 200pt x 160pt | 16pt |
| Circuit bracket | Dynamic | 16pt |
| Watch complication | 44pt (circular) | 22pt (circle) |

### 1.5 Touch Targets

All interactive elements have a minimum touch target of **44pt x 44pt** per Apple HIG. During Active Workout, touch targets expand to **56pt x 56pt** minimum — the user may be sweating, gripping, or wearing gloves. Weight input stepper buttons during active workout are **64pt x 48pt** for maximum usability with wet or gloved hands.

### 1.6 Haptic Feedback Map

> **Canonical source:** SOUND_AND_HAPTICS.md is the authoritative reference for all haptic patterns. The table below is a summary for Training-specific actions. If conflicts arise, defer to SOUND_AND_HAPTICS.md.

| Action | Haptic |
|--------|--------|
| Set completed | `.success` (UINotificationFeedbackGenerator) |
| PR achieved | `.success` + 200ms delay + `.success` (double tap) |
| All-time 1RM PR | `.success` x3 rapid pulses + 500ms delay + `.success` x2 |
| Rest timer finished | `.warning` (UINotificationFeedbackGenerator) |
| Rest timer 10s warning | `.light` x2 rapid |
| Exercise swipe | `.light` (UIImpactFeedbackGenerator) |
| Button tap | `.light` (UIImpactFeedbackGenerator) |
| Weight stepper tick | `.rigid` (UIImpactFeedbackGenerator) |
| Weight stepper quick-add (+2.5/+5) | `.medium` (UIImpactFeedbackGenerator) |
| Plate calculator update | `.soft` (UIImpactFeedbackGenerator) |
| Scroll wheel snap | `.selection` (UISelectionFeedbackGenerator) |
| Workout finished | `.success` + custom pattern (3 pulses) |
| Deload week trigger | `.warning` + 300ms + `.light` |
| Superset transition (no rest) | `.rigid` + `.rigid` rapid (urgency cue) |
| Circuit round complete | `.medium` x2 |
| Drop set weight change | `.rigid` |
| Error (invalid input) | `.error` (UINotificationFeedbackGenerator) |
| Long-press menu open | `.medium` (UIImpactFeedbackGenerator) |
| Import complete | `.success` |
| Watch rest timer end | WKInterfaceDevice `.notification` |

### 1.7 Animation Specifications

| Animation | Duration | Curve | Description |
|-----------|----------|-------|-------------|
| Card expand/collapse | 350ms | `.spring(response: 0.35, dampingFraction: 0.8)` | Exercise card opens to show sets |
| Set row slide-in | 250ms | `.easeOut` | Completed set row slides into history |
| PR badge pop | 400ms | `.spring(response: 0.4, dampingFraction: 0.5)` | Scale 0 to 1.15 to 1.0 with gold shimmer |
| PR confetti burst | 2000ms | Custom keyframe | Gold particles for e1RM PR |
| PR fireworks | 3000ms | Custom keyframe | Full screen for all-time 1RM |
| Rest timer pulse | 1000ms | `.easeInOut` repeat | Circle border pulses while resting |
| Rest timer urgency | 500ms | `.easeInOut` repeat | Faster pulse in last 10 seconds |
| Recovery badge fade | 200ms | `.easeIn` | Recovery color transitions |
| Screen transition | 350ms | `.spring(response: 0.35, dampingFraction: 0.85)` | Standard push/pop navigation |
| Bottom sheet present | 400ms | `.spring(response: 0.4, dampingFraction: 0.8)` | Sheet slides up from bottom |
| Checkmark draw | 300ms | `.easeOut` | SVG path animation on set complete |
| Workout complete ring | 800ms | `.easeInOut` | Ring fills to 100% on summary |
| Plate calculator update | 200ms | `.spring(response: 0.3, dampingFraction: 0.7)` | Plates slide in/out on weight change |
| Superset bracket pulse | 800ms | `.easeInOut` repeat | Bracket glows during active superset |
| Circuit round counter | 300ms | `.spring(response: 0.3, dampingFraction: 0.6)` | Number increment animation |
| Drop set weight slide | 250ms | `.easeOut` | Old weight slides left, new slides in from right |
| Deload banner appear | 500ms | `.spring(response: 0.5, dampingFraction: 0.7)` | Blue banner slides down from top |
| Scroll wheel momentum | 400ms | `.spring(response: 0.4, dampingFraction: 0.85)` | Deceleration after flick |
| Weight quick-add pop | 150ms | `.spring(response: 0.15, dampingFraction: 0.5)` | Button scales 1.0 to 1.1 to 1.0 |

### 1.8 Accessibility

- All text respects Dynamic Type (minimum Large, scales to AX5).
- VoiceOver labels on every interactive element. Weight input announces: "Weight: 85 kilograms. Double tap to edit. Swipe up to increase by 2.5, swipe down to decrease."
- Reduce Motion: all spring animations become 200ms `.easeInOut`, confetti disabled, plate calculator uses fade instead of slide.
- High Contrast: card backgrounds shift from `#1A1A1E` to `#000000`, borders added at 1pt `#3A3A3E`.
- Color-blind safe: recovery states use icons in addition to color (checkmark for green, warning triangle for yellow, X for red). Plate calculator uses patterns in addition to color (stripes for 25kg, solid for 20kg, dots for 15kg, etc.).
- Switch Control: all workout logging reachable via sequential navigation. "Done" button is always first in tab order.
- Voice Control: "Log set", "Skip rest", "Next exercise" voice commands mapped.

---

## 2. Today's Workout View

### 2.1 Overview

The first screen the user sees when opening the Training tab. Shows today's programmed workout, adapted in real-time based on the latest Whoop recovery score. This is the "launch pad" for every training session.

### 2.2 Screen Structure

```
+-----------------------------------------+
| < Training                    [gear] [cal]| <- Nav bar (44pt)
|-----------------------------------------|
|                                          |
|  Monday, March 24                        | <- Date: caption, textSecondary
|  PUSH DAY                                | <- heroTitle, textPrimary
|                                          |
|  +--------------------------------------+|
|  | [green] 78% Recovery  *  Full Volume ||  <- Recovery Badge Bar (52pt)
|  | [sync] Synced 6:42 AM               ||
|  +--------------------------------------+|
|                                          |
|  [clock] ~52 min  *  6 exercises  *  24 || <- Workout meta: caption
|     sets                                ||
|                                          |
|  +--------------------------------------+|
|  | 1  BENCH PRESS               Chest   || <- Exercise Card
|  |     4 x 8 @ 85kg                    ||
|  |     Last: 82.5kg x 8 [check]        ||
|  |     Plates: 20+10+2.5 per side      || <- NEW: plate hint
|  |                              [>][...]||
|  +--------------------------------------+|
|                                 8pt gap   |
|  +--------------------------------------+|
|  | 2  INCLINE DB PRESS          Chest   ||
|  |     3 x 10 @ 32kg                   ||
|  |     Last: 30kg x 10 [check]         ||
|  |                              [>][...]||
|  +--------------------------------------+|
|                                          |
|  + - - SUPERSET A - - - - - - - - - - + |  <- Superset bracket
|  |+------------------------------------+| |
|  || 3A CABLE FLY                Chest  || |
|  ||    3 x 12 @ 15kg                  || |
|  ||    Last: 12.5kg x 12 [check]      || |
|  |+------------------------------------+| |
|  |+------------------------------------+| |
|  || 3B LATERAL RAISE        Shoulders  || |
|  ||    3 x 15 @ 10kg                  || |
|  ||    Last: 10kg x 14                || |
|  |+------------------------------------+| |
|  + - - - - - - - - - - - - - - - - - -+ |
|                                          |
|  +--------------------------------------+|
|  | 4  OVERHEAD PRESS        Shoulders   ||
|  |     4 x 8 @ 50kg                    ||
|  |     Last: 47.5kg x 8 [check]        ||
|  |     Plates: 15 per side              ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | 5  TRICEP PUSHDOWN          Triceps  ||
|  |     3 x 12 @ 25kg                   ||
|  |     Last: 22.5kg x 12 [check]       ||
|  +--------------------------------------+|
|                                          |
|  + - - - - - - - - - - - - - - - - - -+ |
|  |  + Add Exercise                      | <- Dashed border button (44pt)
|  + - - - - - - - - - - - - - - - - - -+ |
|                                          |
|         (bottom spacer: 120pt)           |
|                                          |
|-----------------------------------------|
|                                          |
|  +--------------------------------------+|
|  |       [>]  START WORKOUT             || <- Primary CTA (56pt), pinned
|  +--------------------------------------+| <- 16pt horizontal padding
|                                          | <- Safe area bottom
+-----------------------------------------+
```

### 2.3 Navigation Bar

- **Height**: 44pt (standard iOS).
- **Left**: Back chevron (SF Symbol: `chevron.left`, 17pt, `textPrimary`). Navigates to the main Tempo dashboard. Hidden if Training is a root tab.
- **Title**: "Training" in `cardTitle` style, centered. Hidden — we use the large title below instead.
- **Right icons** (24pt, `textSecondary`, 44pt touch targets, 16pt spacing between):
  - Gear icon (SF Symbol: `gearshape`): navigates to Training Settings.
  - Calendar icon (SF Symbol: `calendar`): navigates to Week Plan View.

### 2.4 Date and Workout Title

- **Date label**: `caption` style, `textSecondary`. Format: "EEEE, MMMM d" (e.g., "Monday, March 24"). Top padding: 16pt from nav bar.
- **Workout title**: `heroTitle` style, `textPrimary`. All caps. Top padding: 4pt from date. Examples:
  - "PUSH DAY"
  - "PULL DAY"
  - "LEG DAY"
  - "UPPER BODY"
  - "FULL BODY"
  - "EASY RUN"
  - "INTERVAL RUN"
  - "TEMPO RUN"
  - "LONG RUN"
  - "FARTLEK"
  - "MOBILITY FLOW"
  - "FOOTBALL PREP"
  - "DELOAD — PUSH" (deload week variant)
  - "REST DAY"

### 2.5 Recovery Badge Bar

A full-width card sitting below the title, height 52pt, background `surface`, corner radius 12pt, horizontal padding 16pt.

**Layout (horizontal stack)**:

```
+----------------------------------------------------+
| [dot] 78% Recovery  *  Full Volume    [sync] 6:42 AM|
+----------------------------------------------------+
```

- **Recovery dot**: 10pt circle, filled with recovery color (`recoveryGreen` / `recoveryYellow` / `recoveryRed`). Additionally, for color-blind accessibility:
  - Green: checkmark icon overlaid (SF Symbol: `checkmark.circle.fill`)
  - Yellow: warning icon (SF Symbol: `exclamationmark.triangle.fill`)
  - Red: X icon (SF Symbol: `xmark.circle.fill`)
- **Percentage**: `bodyBold`, `textPrimary`. "78% Recovery"
- **Separator dot**: `textTertiary`, 4pt.
- **Adjustment label**: `body`, recovery color. Values:
  - Green (>=67%): "Full Volume"
  - Green (80-89%): "Full Volume + Bonus Set"
  - Green (90-100%): "Peak — PR Attempt?"
  - Yellow (50-66%): "-20% Volume"
  - Yellow (34-49%): "-20% Volume, Lighter Load"
  - Red (<34%): "Swapped to Mobility" or "Active Recovery Only"
- **Sync indicator**: right-aligned, `caption`, `textTertiary`. "[sync] 6:42 AM" — last Whoop sync time. SF Symbol: `arrow.triangle.2.circlepath`, 11pt.

**Tap behavior**: Opens a bottom sheet (Recovery Detail Sheet) explaining:
- Current Whoop recovery score and what it means
- What adjustments were made to today's workout
- HRV, resting heart rate, sleep performance (pulled from Whoop via HealthKit)
- Option: "Override — I feel great" / "Override — I feel worse" (manual override buttons)

**States**:
- **Whoop connected, data fresh (<4 hours)**: Normal display as above.
- **Whoop connected, data stale (>4 hours)**: Sync icon turns `recoveryYellow`, label reads "[sync] Stale — tap to sync".
- **Whoop not connected**: Badge background becomes `surfaceElevated`, shows "Connect Whoop for smart recovery" with a link icon. Tap opens Settings > Integrations.
- **No Whoop data yet today**: Shows "Waiting for recovery data..." with a subtle shimmer animation (skeleton loading style).

### 2.6 Workout Meta Bar

Horizontal stack below recovery badge. Top padding: 16pt.

```
[clock] ~52 min  *  6 exercises  *  24 sets
```

- **Timer icon**: SF Symbol `timer`, 13pt, `textSecondary`.
- **Duration estimate**: `caption`, `textSecondary`. Calculated as: (total sets x avg time per set) + (total sets x avg rest per set) + (transition time x num exercises). Prefix with "~" to indicate estimate.
- **Separator**: " * " in `textTertiary`.
- **Exercise count**: `caption`, `textSecondary`. "{n} exercises".
- **Set count**: `caption`, `textSecondary`. "{n} sets".

### 2.7 Exercise Cards

Each exercise is a card with background `tempo.color.surface.card`, corner radius 16pt (`tempo.radius.3xl`), horizontal padding 16pt, vertical padding 12pt. Full width with 20pt horizontal margins from screen edges (`tempo.space.screen.edge`). Cards separated by 8pt vertical spacing.

**Card layout**:

```
+----------------------------------------------------+
|  1   BENCH PRESS                            Chest   |
|      4 x 8 @ 85kg                     [up-arrow]   |
|      Last: 82.5kg x 8 [check]                      |
|      Plates: 20+10+2.5 per side         [>] [...]  |
+----------------------------------------------------+
```

**Row 1 (top)**:
- **Exercise number**: `captionBold`, `textTertiary`, 20pt wide. Left-aligned.
- **Exercise name**: `cardTitle`, `textPrimary`. All caps. Truncates with ellipsis if longer than available width.
- **Muscle group tag**: Right-aligned pill. Height 24pt, horizontal padding 8pt. Background: `surfaceElevated`. Text: `miniTag`, `textSecondary`. All caps. Examples: "CHEST", "BACK", "SHOULDERS", "QUADS", "HAMSTRINGS", "TRICEPS", "BICEPS", "CORE", "FULL BODY", "GLUTES", "CALVES".

**Row 2**:
- **Prescription**: `body`, `textSecondary`. Format: "{sets} x {reps} @ {weight}{unit}". For bodyweight exercises: "{sets} x {reps} (BW)". For timed exercises: "{sets} x {duration}". For drop sets: "{sets} x {reps} @ {w1}/{w2}/{w3}". Top padding: 4pt from row 1.

**Row 3**:
- **Previous performance**: `caption`, `textTertiary`. Format: "Last: {weight} x {reps} [check]" if completed all target reps, or "Last: {weight} x {reps}" (no checkmark) if fell short. If no previous data: "First time — no history". Top padding: 2pt from row 2.

**Row 4 (barbell exercises only)**:
- **Plate hint**: `caption`, `textTertiary`. Format: "Plates: {plate breakdown} per side". E.g., "Plates: 20+10+2.5 per side". Only shown for barbell exercises. Calculated from the working weight minus the bar (20kg). This is a quick-glance reference so the user can start loading plates before the exercise.

**Right side actions** (vertically centered in the card):
  - **Demo button**: SF Symbol `play.circle` (17pt, `textTertiary`). Tap opens exercise demo (half-sheet with looping GIF/animation). 44pt touch target.
  - **More button**: SF Symbol `ellipsis` (17pt, `textTertiary`). Tap opens context menu. 44pt touch target. 8pt spacing from demo button.

**More button context menu options**:
1. "Swap Exercise" — opens exercise swap flow (section 2.13)
2. "Remove Exercise" — destructive, red text, confirmation alert
3. "Edit Sets & Reps" — inline edit mode
4. "Convert to Superset" — pair with adjacent exercise
5. "Convert to Drop Set" — change set scheme to drop set format
6. "Add Note" — opens note input for this exercise
7. "View History" — navigates to exercise detail / history in Progress Charts

**Progressive overload indicator**: When the AI has increased weight or reps from last session, show a small upward arrow icon (SF Symbol: `arrow.up.right`, 11pt) in `primary` color next to the prescription text. Tooltip on long-press: "Weight increased from 82.5kg based on your last performance."

### 2.8 Superset / Circuit / Drop Set Grouping

See Section 6 for comprehensive specification of all grouping types. In the Today's Workout View, they appear as visually grouped cards with colored brackets.

### 2.9 "Start Workout" Button

- **Position**: Pinned to bottom of screen, above safe area. Does NOT scroll with content.
- **Background**: Floating bar with `background` color + 20pt top blur (vibrancy material, `.ultraThinMaterial`).
- **Button**: Full width minus 40pt (20pt horizontal margin each side, `tempo.space.screen.edge`). Height 56pt. Corner radius 14pt (`tempo.radius.2xl`). Background `tempo.color.primary.signal`. Text: "START WORKOUT" in `bodyBold`, white, centered.
- **Icon**: SF Symbol `play.fill`, 15pt, white, 8pt left of text.
- **Pressed state**: Background darkens to `primaryDark`. Scale: 0.97 with 100ms spring.
- **Disabled state**: If no workout is programmed (should not happen normally), background becomes `surfaceElevated`, text becomes `textTertiary`.
- **Deload variant**: During deload weeks, button text reads "START DELOAD SESSION" and background is `deloadBlue` instead of `primary`.

**Tap behavior**: Transitions to Active Workout View with a full-screen push animation. The exercise list slides up and the Start button transforms into the workout timer bar (morphing animation, 500ms spring).

### 2.10 Rest Day View

When no workout is scheduled:

```
+-----------------------------------------+
|                                          |
|  Monday, March 24                        |
|  REST DAY                                |
|                                          |
|  +--------------------------------------+|
|  | [green] 78% Recovery  *  Resting    ||
|  +--------------------------------------+|
|                                          |
|                                          |
|           +----------+                   |
|           |  [yoga]  |                   | <- 80pt illustration
|           +----------+                   |
|                                          |
|     Your body builds muscle              |
|     while you rest.                      | <- body, textSecondary, center
|                                          |
|     Next workout: Tomorrow               |
|     PULL DAY                             | <- bodyBold, textPrimary
|                                          |
|  +--------------------------------------+|
|  |   [yoga] Start a Mobility Flow      || <- Secondary button (44pt)
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  |   [flex] I want to train anyway      || <- Tertiary button (text only)
|  +--------------------------------------+|
|                                          |
+-----------------------------------------+
```

- **"Start a Mobility Flow" button**: Secondary style — `surface` background, `textPrimary` text, 44pt height, 12pt radius. Navigates to a pre-built 15-20 minute mobility session.
- **"I want to train anyway" button**: Text-only, `textSecondary`, 44pt height. Tap opens bottom sheet:
  - "Quick Push" / "Quick Pull" / "Quick Legs" / "Quick Full Body" — shortened sessions (~30 min)
  - "Custom — Pick from Library"
  - Warning text: "You're scheduled to rest today. Overtraining can hurt your progress." in `caption`, `recoveryYellow`.

### 2.11 Football Day View

See Section 18 (Football Integration Deep Dive) for complete T-2 through T+2 specification.

When football is scheduled:

```
+-----------------------------------------+
|                                          |
|  Wednesday, March 26                     |
|  FOOTBALL DAY                            |
|                                          |
|  +--------------------------------------+|
|  | [green] 72% Recovery  *  Match Day  ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [ball] Football @ 8:00 PM           ||  <- Event card, surface bg
|  |    Location: Campo Sportivo          ||
|  |    Duration: ~90 min                 ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  |   PRE-MATCH PREP (Optional)         ||  <- Section header
|  |                                      ||
|  |   1  Foam Roll — Lower Body         ||
|  |      10 min                          ||
|  |                                      ||
|  |   2  Dynamic Stretching             ||
|  |      8 min                           ||
|  |                                      ||
|  |   3  Activation — Glutes/Core       ||
|  |      7 min                           ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  |     [>]  START PRE-MATCH PREP       ||
|  +--------------------------------------+|
|                                          |
|  Tomorrow: REST or UPPER BODY            |
|  (depends on recovery after match)       | <- caption, textTertiary
|                                          |
+-----------------------------------------+
```

### 2.12 Day-Before-Football View (T-1)

When tomorrow is a football day, today's workout NEVER includes heavy leg exercises. The view looks like a normal workout day but with a notice:

```
+--------------------------------------+
| [ball] Football tomorrow — legs      |  <- Info banner, 44pt
|    protected. Upper body focus.      |     Background: surfaceElevated
+--------------------------------------+     Text: caption, recoveryYellow
```

This banner sits between the recovery badge and the workout meta bar. It has a left border accent (3pt, `recoveryYellow`) and an SF Symbol `info.circle` (13pt) preceding the text.

### 2.13 Swap Exercise Flow

Triggered from the exercise card's more menu > "Swap Exercise".

**Step 1**: Bottom sheet presents (400ms spring animation). Height: 75% of screen. Handle bar at top (36pt x 4pt, `textTertiary`, centered).

```
+-----------------------------------------+
|              -----                       | <- Handle
|                                          |
|  Swap: BENCH PRESS                       | <- sectionHeader
|                                          |
|  Suggested alternatives:                 | <- caption, textSecondary
|                                          |
|  +--------------------------------------+|
|  | [star] DUMBBELL BENCH PRESS          || <- "[star]" = AI recommended
|  |   Chest  *  Dumbbells                ||
|  |   Same muscle group, similar         ||
|  |   movement pattern                   ||
|  +--------------------------------------+|
|  +--------------------------------------+|
|  |   INCLINE BARBELL PRESS              ||
|  |   Chest  *  Barbell                  ||
|  |   Upper chest emphasis               ||
|  +--------------------------------------+|
|  +--------------------------------------+|
|  |   MACHINE CHEST PRESS               ||
|  |   Chest  *  Machine                  ||
|  |   Lower injury risk                  ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [search]  Browse Exercise Library    || <- Opens full library
|  +--------------------------------------+|
+-----------------------------------------+
```

**AI-suggested alternatives**: Up to 3 exercises that:
1. Target the same primary muscle group
2. Use available equipment (per user settings)
3. Have a similar movement pattern (push/pull/hinge/squat/carry)
4. Are ranked by relevance ([star] icon on top recommendation)

**Selection**: Tap an alternative to select it. The sheet dismisses, the exercise card updates with a subtle crossfade animation (300ms). The prescription (sets x reps x weight) is recalculated based on the user's history with the new exercise, or estimated from the original if no history exists.

### 2.14 Add Exercise Flow

Triggered by the "+ Add Exercise" dashed-border button at the bottom of the exercise list.

Opens the Exercise Library in a modal presentation (full-screen cover). When the user selects an exercise:

1. Exercise is added at the bottom of the list.
2. A default prescription is generated: 3 x 10 (if no history) or based on last performance.
3. User can drag-to-reorder after adding.
4. Modal dismisses, scrolls to the newly added exercise with a highlight flash (300ms, `primary` at 10% opacity).

### 2.15 Drag-to-Reorder

Long-press (500ms) on any exercise card activates reorder mode:
- Card lifts with a scale (1.03) and shadow animation.
- Haptic: `.medium` impact.
- Other cards compress to make room (200ms, `.easeInOut`).
- Drop: card settles into new position with spring animation.
- Superset grouping is maintained — dragging within a superset reorders within it; dragging outside breaks the superset.

### 2.16 Pull-to-Refresh

Pull-to-refresh at the top of the scroll view triggers:
1. Re-fetch Whoop recovery data.
2. Recalculate adjustments.
3. Update the workout prescription if recovery changed significantly.
4. Standard iOS pull-to-refresh spinner.

### 2.17 Edge Cases

| Scenario | Behavior |
|----------|----------|
| No workout programmed and not a rest day | Show "No workout planned" + "Generate Today's Workout" button |
| Whoop battery dead / no data for 24h+ | Default to "yellow" (moderate) programming with a note: "No recovery data — using moderate defaults" |
| User already completed today's workout | Show the completed workout summary with a green checkmark overlay. "Start Workout" becomes "Start Another Workout" |
| Two workouts in one day (e.g., morning weights + evening football) | Show both as stacked cards. Primary: the next upcoming. Secondary: completed (collapsed) |
| Workout generated at midnight but recovery updates at 6 AM | Workout recalculates silently. If exercises changed, a banner appears: "Workout updated based on new recovery data" |
| Time zone change (travel) | Use device local time for "today" determination |
| No internet | All workout data is cached locally. Whoop sync shows "Offline" badge |
| Deload week active | All exercise cards show `deloadBlue` left accent bar. Banner at top: "DELOAD WEEK — Strategic recovery. Lighter weights, fewer sets." |

---

## 3. Active Workout View

### 3.1 Overview

This is the most critical screen in the entire app. The user is in the gym, possibly sweating, possibly wearing gloves, possibly fatigued. Every interaction must be achievable in 1-2 taps with large touch targets. The phone may be propped on a bench or held in one hand.

**Second-by-second interaction flow:**

1. **User arrives at gym** (0:00) — Opens Tempo, lands on Today's Workout View. Sees today's workout with recovery-adjusted prescription.
2. **Scans workout** (0:00-0:30) — Scrolls through exercises. Checks plate hints for first exercise. Optionally swaps an exercise or adjusts sets.
3. **Taps START WORKOUT** (0:30) — Full-screen push transition (500ms spring). Workout timer begins. First exercise appears. If warm-up sets are enabled, Warm-Up 1 is shown first.
4. **Warm-up set 1** (0:30-1:30) — Weight pre-filled at 50% of working weight. User taps DONE. Haptic `.success`. No rest timer — immediate transition to Warm-Up 2.
5. **Warm-up set 2** (1:30-2:30) — Weight pre-filled at 75% of working weight. User taps DONE. Rest timer starts (90 seconds for warm-up-to-working transition).
6. **Rest timer counts down** (2:30-4:00) — Large 200pt circle with countdown. Phone can be locked — Live Activity shows timer on lock screen. At 10 seconds remaining: haptic `.light` x2. At 0: haptic `.warning` + chime + "Rest over — Set 1 ready" notification if app backgrounded.
7. **Working Set 1** (4:00) — Weight pre-filled with target (e.g., 85kg). Reps pre-filled with target (e.g., 8). User performs the set in real life. Returns to phone.
8. **Logs Set 1** (4:00+) — **Scenario A (hit target):** Weight and reps match pre-fill. User taps DONE. One tap. **Scenario B (adjusted):** User taps the weight number, types 82.5 on the keypad, confirms. Taps reps stepper down to 7. Taps DONE. **Scenario C (quick-add):** User taps the "+2.5" quick button next to weight, making it 87.5. Taps DONE.
9. **Set complete animation** (200ms) — Green flash fills the DONE button. Checkmark draws in. Set row slides down to "Completed Sets" area. Haptic `.success`.
10. **Optional RPE** — User taps RPE 8 circle (or skips — it is optional).
11. **Rest timer auto-starts** (3:00 for compound) — Same as step 6. User can adjust +/-30s or skip.
12. **Sets 2, 3, 4** — Repeat steps 7-11. Weight is sticky (if user changed it on set 1, set 2 pre-fills with the changed value).
13. **Last set of exercise complete** — Rest timer starts. "Next: Incline DB Press" appears below timer. After rest (or skip), auto-transitions to next exercise with horizontal slide animation (300ms).
14. **Exercise complete animation** — Brief celebration: exercise card in the bottom drawer gets a green checkmark. Progress bar advances. If a PR was hit on this exercise, gold shimmer on the exercise name.
15. **Repeat for all exercises** — Navigate via bottom PREV/NEXT buttons or swipe left/right.
16. **Superset encountered** — After completing Exercise A set, NO rest timer. Immediate slide to Exercise B. "SUPERSET — No rest, go to Cable Fly" banner. After Exercise B set, rest timer starts. Round counter increments.
17. **Last set of last exercise** — NEXT button reads "FINISH" in `primary`. After DONE: final rest timer (skippable). Confetti if PRs hit. Triple haptic pulse.
18. **Workout Summary appears** — Ring animation fills. Stats display. PRs celebrated. Save and Close.

Total taps for a 24-set workout where user hits all targets: **24 taps** (one DONE per set) + optional RPE taps. That is the design goal: one tap per set when things go right.

### 3.2 Screen Structure — Main Exercise View

```
+-----------------------------------------+
|  X End    PUSH DAY    [timer] 34:12     | <- Workout header bar (52pt)
|-----------------------------------------|
|                                          |
|  BENCH PRESS                             | <- sectionHeader, textPrimary
|  4 x 8 @ 85kg  *  Last: 82.5kgx8       | <- body, textSecondary
|                                          |
|  +--------------------------------------+|
|  | SET 1                    TARGET: 8   || <- Set logging row
|  |                                      ||
|  |  [-2.5] [-] [  85  ] [+] [+2.5] kg  || <- Smart stepper w/ quick-add
|  |                                      ||
|  |  [-] [     8    ] [+]          reps  || <- Reps stepper
|  |                                      ||
|  |  Plates: 20 + 10 + 2.5 each side    || <- Plate hint
|  |                                      ||
|  |         [  CHECK DONE  ]             || <- Complete button (48pt)
|  +--------------------------------------+|
|                                          |
|  -- Completed Sets -------------------- | <- divider + caption
|                                          |
|  (empty -- no sets completed yet)        | <- textTertiary, italic
|                                          |
|-----------------------------------------|
|  Exercise 1 of 6                         | <- Exercise progress bar
|  [###..............................]     |
|                                          |
|  < PREV          REST         NEXT >    | <- Bottom navigation (56pt)
+-----------------------------------------+
```

### 3.3 Workout Header Bar

- **Height**: 52pt. Background: `background` with bottom border 0.5pt `divider`.
- **Left**: "X End" in `body`, `recoveryRed`. 44pt touch target. Tap triggers end-workout confirmation (see Section 3.14).
- **Center**: Workout name in `captionBold`, `textSecondary`. All caps. During deload weeks, prefixed with "DELOAD --" in `deloadBlue`.
- **Right**: Running timer in `metricSmall` (but at 17pt, monospaced), `textPrimary`. Format: "MM:SS" or "H:MM:SS" after 1 hour. Updates every second. SF Symbol `timer` (13pt) as prefix.

### 3.4 Exercise Header

Below the workout bar, 16pt top padding.

- **Exercise name**: `sectionHeader`, `textPrimary`. All caps.
- **Prescription + history**: `body`, `textSecondary`. Format: "{sets} x {reps} @ {weight}{unit} * Last: {weight}x{reps}". If PR was set last time, append trophy icon after the last performance.
- **Below prescription**: If the AI increased the weight, show a badge: "[up] 2.5kg from last session" in `caption`, `primary` color. 4pt top padding.
- **Difficulty tag**: `miniTag`, colored pill. Based on exercise difficulty from the database:
  - Beginner: `recoveryGreen` background
  - Intermediate: `recoveryYellow` background
  - Advanced: `recoveryRed` background

### 3.5 Set Logging Row — THE CORE INTERACTION

This is the single most important component in the entire app. It must be optimized for speed and sweaty fingers.

**Dimensions**: Full width minus 32pt margins. Height: dynamic (typically ~180pt including all controls). Background: `surface`. Corner radius: 16pt. Padding: 16pt all sides.

The weight input system is the most critical interaction in the app. See **Section 4** for the complete deep dive on all three input methods, when each is used, and the smart stepper design.

#### 3.5.1 Weight Input (Summary — see Section 4 for full spec)

- **Display**: `weightInput` style (SF Mono, 32pt, Bold), `textPrimary`, centered in a rounded rect (width: 130pt, height: 48pt, background: `surfaceElevated`, radius: 12pt).
- **Auto-fill**: Pre-populated with the target weight for this set. If the user changed the weight on the previous set, use that weight instead (sticky modification).
- **Three input methods**: Smart stepper (default), scroll wheel picker (long-press on number), direct keypad (tap on number). See Section 4.
- **Plate hint**: For barbell exercises, a single line below the weight showing the plate breakdown per side. Updates in real-time as weight changes.

#### 3.5.2 Reps Input

- **Display**: Same style as weight input. `weightInput` (32pt Mono), centered in 100pt wide rounded rect.
- **Auto-fill**: Pre-populated with target reps for this set.
- **Stepper buttons**: Same as weight, but increment/decrement by 1 rep. No quick-add buttons for reps.
- **Tap on number**: Opens numeric keypad for direct entry.
- **Color coding**: If entered reps < target, the number turns `recoveryYellow`. If entered reps = 0, turns `recoveryRed`.

#### 3.5.3 Numeric Keypad Overlay

When the user taps the weight or reps number directly:

```
+-----------------------------------------+
|                                          |
|         [  87.5  ] kg                    | <- Large display (metricSmall)
|                                          |
|  +-------+  +-------+  +-------+        |
|  |   1   |  |   2   |  |   3   |        | <- 72pt x 56pt buttons
|  +-------+  +-------+  +-------+        |
|  +-------+  +-------+  +-------+        |
|  |   4   |  |   5   |  |   6   |        |
|  +-------+  +-------+  +-------+        |
|  +-------+  +-------+  +-------+        |
|  |   7   |  |   8   |  |   9   |        |
|  +-------+  +-------+  +-------+        |
|  +-------+  +-------+  +-------+        |
|  |   .   |  |   0   |  |  <x   |        |
|  +-------+  +-------+  +-------+        |
|                                          |
|  +--------------------------------------+|
|  |           CONFIRM                    || <- Primary button (56pt)
|  +--------------------------------------+|
+-----------------------------------------+
```

- Presented as a bottom sheet, 60% screen height.
- Custom keypad (NOT the system keyboard) -- optimized for gym use.
- Button size: 72pt wide x 56pt tall. Large enough for sweaty taps.
- Corner radius: 12pt. Background: `surfaceElevated`.
- Text: `sectionHeader` (20pt Semibold).
- Haptic: `.light` on each key tap.
- Decimal point: only for weight input (not reps).
- Backspace: Deletes last digit. Long-press clears all.
- CONFIRM: Closes keypad, updates value, updates plate calculator.
- **Tap outside keypad**: Also confirms and closes.

#### 3.5.4 DONE Button (Set Complete)

- **Dimensions**: Width: 160pt, height: 48pt, centered. Corner radius: 14pt.
- **Default state**: Background: `primary`. Text: "CHECK DONE" in `bodyBold`, white. SF Symbol `checkmark` (15pt, bold) 6pt left of text.
- **Pressed state**: Scale 0.95, background `primaryDark`, 100ms.
- **Tap behavior**:
  1. Haptic: `.success`.
  2. Button animates: green flash (`setComplete`) fills from center outward (200ms).
  3. Checkmark draws in (SVG path animation, 300ms).
  4. Set row slides down to "Completed Sets" area (250ms, `.easeOut`).
  5. PR check runs immediately (see Section 12). If PR detected: gold badge pops in, double haptic.
  6. Next set auto-populates in the input area.
  7. Rest timer begins automatically (see Section 7).
  8. If this was the last set of the exercise, auto-advance to next exercise after rest timer (or immediately if rest is skipped).
- **Deload variant**: During deload weeks, button is `deloadBlue` instead of `primary`.

#### 3.5.5 RPE Input (Optional)

Below the DONE button, low visual priority:

- **Label**: "RPE (optional):" in `caption`, `textTertiary`.
- **Circles**: 5 circles in a horizontal row, labeled 6, 7, 8, 9, 10. Each circle: 32pt diameter, 8pt spacing. Default: `surfaceElevated` fill, `textTertiary` number.
- **Tap to select**: Selected circle fills with `primary`, number turns white. Only one can be selected.
- **RPE meaning** (long-press any circle for tooltip):
  - 6: Could do 4+ more reps (warm-up effort)
  - 7: Could do 3 more reps (moderate)
  - 8: Could do 2 more reps (challenging)
  - 9: Could do 1 more rep (near max)
  - 10: Maximum effort (absolute failure)
- **Default**: No RPE selected. It is not required to complete a set.
- RPE data is stored and used by the progressive overload algorithm (Section 16).
- **Deload guidance**: During deload weeks, a note appears: "Target RPE: 5-6 this week" in `deloadBlue`.

#### 3.5.6 One-Tap Complete Mode

For experienced users who do not need to modify weight/reps:

If the pre-filled values match the target (which they do by default), the user can hit DONE immediately without touching weight or reps. This means completing a set is literally ONE TAP.

**Auto-fill logic priority**:
1. If user modified weight/reps on previous set of the same exercise in this session, use those values.
2. Otherwise, use the programmed target (from the AI prescription).
3. For subsequent sets where the user consistently hits targets, keep auto-filling the target.
4. For drop sets: auto-fill with the next drop weight (see Section 6).

### 3.6 Completed Sets History

Below the active set input, a scrollable area shows completed sets:

```
-- Completed Sets ---------------------------

  Set 1    85kg x 8     RPE 7    [check]
  Set 2    85kg x 8     RPE 8    [check]
  Set 3    85kg x 7     RPE 9    [warn]   <- Missed target
```

- **Header**: "Completed Sets" in `captionBold`, `textTertiary`, with a horizontal divider line on each side.
- **Each row**: Height 36pt. Horizontal layout.
  - "Set {n}": `caption`, `textTertiary`, 60pt wide.
  - "{weight} x {reps}": `bodyBold`, `textPrimary`.
  - "RPE {n}": `caption`, `textSecondary` (omitted if RPE not entered).
  - Status icon: [check] (`setComplete`, 15pt) if reps >= target; [warn] (`recoveryYellow`, 15pt) if reps < target.
  - **PR badge**: If this set triggered a PR, a small gold star appears after the status icon.
- **Tap on a completed set row**: Expands to allow editing (in case user logged wrong value). Edit mode shows same weight/reps inputs inline. "Save" button replaces "DONE".
- **Swipe left on a completed set**: Reveals "Delete" button (red, 72pt wide). Removes the set from the record.

### 3.7 Rest Timer

See **Section 7** for the full rest timer specification. Summary: auto-starts after completing a set, takes over center of screen, 200pt countdown circle, +/-30s adjust, skip button, haptic at completion.

### 3.8 Exercise Navigation

#### 3.8.1 Bottom Navigation Bar

Pinned to the bottom of the screen, above the safe area.

- **Progress text**: "Exercise {n} of {total}" in `caption`, `textSecondary`.
- **Progress bar**: Full width minus 32pt margins. Height 3pt. Background: `surfaceElevated`. Fill: `primary`. Animated width transition (300ms, `.easeInOut`).
- **PREV button**: SF Symbol `chevron.left` (15pt) + "PREV" in `captionBold`, `textSecondary`. 44pt touch target. Disabled on first exercise.
- **REST label**: Center. Only visible during rest timer. Shows "REST" in `captionBold`, `primary`.
- **NEXT button**: "NEXT" + SF Symbol `chevron.right` (15pt) in `captionBold`, `textSecondary`. 44pt touch target. On last exercise, text changes to "FINISH" in `primary` color.

#### 3.8.2 Swipe Navigation

- **Swipe left**: Navigate to next exercise.
- **Swipe right**: Navigate to previous exercise.
- **Swipe gesture**: Requires 50pt horizontal travel to trigger. 30% of the next/prev exercise peeks in from the edge.

#### 3.8.3 Exercise List Drawer

Tap on "Exercise {n} of {total}" text to open a bottom sheet showing all exercises with completion status. Each row: 52pt height. Tap to jump directly to that exercise. Superset pairs are indented and bracketed. "+ Add Exercise" at bottom.

### 3.9 Live Activity / Lock Screen

During an active workout, a Live Activity appears on the lock screen and Dynamic Island (iPhone 14 Pro+):

**Dynamic Island (Compact)**: Dumbbell icon + workout timer + current exercise name.

**Dynamic Island (Expanded)**: Workout name, exercise, set number, target weight/reps. DONE button or rest countdown.

**Lock Screen**: Full exercise info + LOG SET button + SKIP button. When rest timer active, shows countdown.

**Always-On Display (iPhone 15 Pro+)**: Dimmed Live Activity. Timer updates every minute. No interactive buttons per Apple guidelines.

### 3.10 Workout Duration Timer

- Starts when "Start Workout" is tapped.
- Runs continuously, including during rest.
- Pauses if the user backgrounds the app for more than 10 minutes (auto-pause). Banner: "Still training?" on return.
- Force-quit recovery: full state persisted to SwiftData every set completion. Recovery on next launch.
- Timer format: "MM:SS" under 1 hour, "H:MM:SS" at 1 hour and beyond.

### 3.11 Auto-Pause Detection

If no interaction for 10 minutes:
1. Push notification: "Still working out? Tap to continue."
2. Timer pauses on-screen with "PAUSED" overlay.
3. On resume, paused duration excluded from total workout time.

### 3.12 Warm-Up Sets

For compound exercises, the first 1-3 sets can be designated as warm-up sets:

- **Label**: "WARM-UP" in `captionBold`, `textTertiary`.
- **Note**: "Warm-up -- doesn't count toward volume" in `caption`, `textTertiary`.
- **Auto-calculated weights**:
  - Working weight <= 60kg: 2 warm-ups at 50% and 75%.
  - Working weight 60-100kg: 2 warm-ups at 50% and 75%.
  - Working weight > 100kg: 3 warm-ups at 40%, 60%, and 80%.
- All warm-up weights rounded to nearest plate-loadable increment.
- Warm-up sets logged but excluded from volume and progressive overload.
- Rest between warm-ups: 60 seconds. Last warm-up to first working set: 90 seconds.
- Default: ON for compounds, OFF for isolation. Configurable in Training Settings.

### 3.13 End Workout Flow

Triggered by "X End" button or "FINISH" (after last exercise).

**Mid-workout**: Alert with Cancel / End & Save / Discard options. Shows completion stats.

**All exercises complete**: FINISH button on last exercise. After last set: final rest timer (skippable), celebration animation (confetti for PRs, ring fill otherwise), triple haptic pulse, auto-navigate to Workout Summary.

### 3.14 Edge Cases — Active Workout

| Scenario | Behavior |
|----------|----------|
| Phone call during workout | Timer pauses. Resumes when call ends. Set state preserved. |
| Low battery (<10%) | Banner: "Low battery -- workout saves continuously." |
| App crash / force quit | Full state persisted to SwiftData every set completion. Recovery on next launch. |
| User logs 0 reps | Prompt confirmation. Failed set marked with X (red). |
| User logs >30% more weight than target | Soft warning to catch typos. |
| Screen rotation | Locked to portrait during active workout. |
| Siri integration | "Hey Siri, log my set" logs with pre-filled values. |
| Apple Watch connected | Set can be logged from Watch. See Section 21. |
| Deload week | All weights show deload values. Banner: "Deload session -- keep it light." |

---

## 4. Weight Input System (Deep Dive)

The weight input is the single most-repeated interaction in the app. A user doing 24 working sets per session will interact with this component 24 times minimum. It must be fast for the common case (one tap: DONE with pre-filled weight) and flexible for adjustments. Three input methods exist, each optimized for a different scenario.

### 4.1 Method A: Smart Stepper (Default)

The default input method. Visible on every set logging row.

```
+----+ +----+               +----+ +----+
|-2.5| | -  |  [    85    ] | +  | |+2.5|  kg
+----+ +----+               +----+ +----+
```

**Components**:

- **Central display**: `weightInput` (SF Mono, 32pt Bold), `textPrimary`, centered in rounded rect (130pt x 48pt, `surfaceElevated`, 12pt radius). Shows current weight value. Tappable (opens Method C: keypad).
- **Inner stepper buttons** (- and +): 44pt x 44pt each, `surfaceElevated` background, 12pt radius. SF Symbol `minus` / `plus` (17pt bold), `textPrimary`.
  - Increment/decrement by the exercise's **standard increment**:
    - Barbell compounds (bench, squat, deadlift, OHP, row): **2.5kg** (5 lbs)
    - Dumbbell exercises: **2kg** per dumbbell (4 lbs)
    - Cable/machine exercises: **2.5kg** (5 lbs or 1 stack notch)
    - Bodyweight (weighted): **2.5kg** (5 lbs)
    - Kettlebell: **4kg** (standard KB jump)
  - Haptic: `.rigid` on each tap.
  - **Long-press**: Holding for 500ms+ enters rapid mode, incrementing every 150ms. Haptic `.rigid` on each tick. Acceleration: after 2 seconds of holding, increment doubles (e.g., 5kg per tick for barbell).
- **Outer quick-add buttons** (-2.5 and +2.5): 56pt x 36pt, `surfaceElevated` background, 10pt radius. Text in `captionBold`, `textSecondary`.
  - These are **context-aware**:
    - For barbell exercises: "-2.5" and "+2.5" (representing 1.25kg per side)
    - For dumbbell exercises: "-2" and "+2"
    - For cable/machine: "-5" and "+5" (common stack jump)
  - Haptic: `.medium` on tap. Button pops (scale 1.0 to 1.1 to 1.0, 150ms).
  - These buttons are the primary adjustment mechanism. Most weight changes between sets are small (2.5-5kg). The quick-add buttons handle this in one tap.

**When to use**: Default for all sets. Covers ~90% of weight adjustments (small increments up or down from the pre-filled value).

### 4.2 Method B: Scroll Wheel Picker

Activated by **long-pressing** the central weight display (500ms hold). A scroll wheel picker appears inline, replacing the stepper.

```
+--------------------------------------+
|                                       |
|              82.5                     |  <- dimmed
|              85.0   <---             |  <- selected (primary)
|              87.5                     |  <- dimmed
|                                       |
|  [Cancel]              [Confirm]     |
+--------------------------------------+
```

**Specifications**:
- **Container**: 200pt wide x 160pt tall, `surfaceElevated` background, 16pt radius. Centered where the stepper was.
- **Wheel**: UIPickerView-style vertical scroll. Each row: 40pt height.
- **Values**: Increments of the exercise's standard increment. Range: 0 to (current weight x 2) or 300kg, whichever is larger.
- **Selected row**: `primary` color text, `weightInput` style. Slight scale (1.05x).
- **Adjacent rows**: `textTertiary`, `body` style.
- **Momentum scrolling**: Standard iOS picker physics. Snaps to nearest valid weight.
- **Haptic**: `.selection` feedback on each value snap.
- **Cancel**: `captionBold`, `textSecondary`. Returns to previous value.
- **Confirm**: `captionBold`, `primary`. Accepts the selected value. Updates plate calculator.

**When to use**: Medium-range adjustments (jumping 10-20kg). Faster than repeated stepper taps, more discoverable than the keypad. Common scenario: user wants to do a lighter set and needs to drop from 85kg to 60kg — scroll wheel gets there in one flick.

### 4.3 Method C: Direct Keyboard Entry

Activated by **tapping** the central weight display. Opens the custom numeric keypad (see Section 3.5.3 for keypad layout).

**When to use**: Large jumps, unusual weights, or when the user knows the exact number. Common scenario: user is loading a different exercise mid-workout and knows they want exactly 67.5kg.

### 4.4 Input Method Selection Summary

| Method | Activation | Best for | Taps to adjust |
|--------|-----------|----------|----------------|
| Smart Stepper | Default (always visible) | Small adjustments (2.5-5kg) | 1-2 taps |
| Scroll Wheel | Long-press weight number | Medium adjustments (10-30kg) | Long-press + flick + confirm |
| Direct Keypad | Tap weight number | Large jumps or exact values | Tap + type + confirm |

### 4.5 Unit Toggle

- A small "kg" or "lbs" label sits to the right of the weight display.
- **Tap on the unit label**: Toggles between kg and lbs for this session only (does not change the global setting).
- Conversion is automatic and rounded to the nearest valid increment.
- Example: 85kg -> 187.5 lbs (nearest 5 lbs). 60kg -> 132.5 lbs.

### 4.6 Bodyweight Exercise Handling

For exercises flagged as bodyweight (pull-ups, dips, push-ups):

- **Unweighted**: Weight input is hidden. Only reps are shown. The display reads "BW" (bodyweight) in `textSecondary`.
- **Weighted**: If the user has previously logged weight for this bodyweight exercise, show a smaller weight input labeled "+{weight}kg" meaning additional weight (belt, vest, etc.). Stepper increments: 2.5kg.
- **Assisted**: If the user logs negative weight (e.g., -15kg for assisted pull-ups via machine), the display shows "-15kg" with an "Assisted" label.

### 4.7 Pre-Fill Intelligence

The weight pre-fill is not a simple "use last session's weight." The logic:

1. **Same exercise, same session, previous set modified**: Use the modified weight (sticky within session).
2. **Progressive overload says increase**: Use the new target weight (e.g., 87.5kg instead of 85kg).
3. **Same exercise, last session, completed successfully**: Use last session's working weight.
4. **Same exercise, last session, failed**: Use last session's working weight (algorithm decides if decrease is needed — see Section 16).
5. **Recovery adjustment active (yellow day)**: Use adjusted weight (-5% of target, rounded to nearest increment).
6. **Deload week**: Use deload weight (60% of current working weight).
7. **New exercise (no history)**: Estimate based on similar exercises the user has done. If no similar exercises, leave blank (user must enter).
8. **Returning after break (7-28+ days)**: Use break-adjusted weight (see Section 16.7).

---

## 5. Plate Calculator

### 5.1 Overview

The plate calculator answers the most common question in every gym: "What plates do I put on each side?" It appears in two places: (a) as a one-line hint on exercise cards and during set logging, and (b) as a full visual diagram accessible by tapping the hint.

### 5.2 Supported Plate Set

Standard Olympic plate set (configurable in Training Settings):

| Plate Weight | Color | Quantity Available (default) |
|-------------|-------|----------------------------|
| 25 kg | `plateRed` (#E74C3C) | 2 pairs (4 total) |
| 20 kg | `plateBlue` (#3498DB) | 2 pairs (4 total) |
| 15 kg | `plateYellow` (#F1C40F) | 2 pairs (4 total) |
| 10 kg | `plateGreen` (#2ECC71) | 2 pairs (4 total) |
| 5 kg | `plateWhite` (#ECF0F1) | 2 pairs (4 total) |
| 2.5 kg | `plateSmall` (#95A5A6) | 2 pairs (4 total) |
| 1.25 kg | `plateSmall` (#95A5A6) | 2 pairs (4 total) |

**Barbell weight**: 20 kg (standard Olympic). Configurable: 15 kg (women's), 10 kg (EZ curl), 7 kg (short bar).

The user can customize their available plates in Training Settings (e.g., home gym might not have 25kg plates, or might have bumper plates only).

### 5.3 Calculation Algorithm

```
FUNCTION calculate_plates(total_weight, bar_weight=20, available_plates):
  weight_per_side = (total_weight - bar_weight) / 2

  IF weight_per_side < 0:
    RETURN "Weight is less than the bar ({bar_weight}kg)"
  IF weight_per_side == 0:
    RETURN "Empty bar"

  plates_per_side = []
  remaining = weight_per_side

  # Greedy algorithm: largest plates first
  FOR plate_weight IN [25, 20, 15, 10, 5, 2.5, 1.25] DESCENDING:
    IF plate_weight NOT IN available_plates: CONTINUE
    max_available = available_plates[plate_weight] / 2  # per side
    count = 0
    WHILE remaining >= plate_weight AND count < max_available:
      plates_per_side.APPEND(plate_weight)
      remaining -= plate_weight
      count += 1

  IF remaining > 0.01:  # floating point tolerance
    RETURN "Cannot make {total_weight}kg with available plates"

  RETURN plates_per_side
```

### 5.4 One-Line Plate Hint

Shown on exercise cards and during set logging for barbell exercises only.

**Format**: "Plates: {plate1} + {plate2} + ... each side"

**Examples**:
- 60kg total (20kg bar): "Plates: 20 each side"
- 85kg total: "Plates: 20 + 10 + 2.5 each side"
- 100kg total: "Plates: 20 + 20 each side"
- 20kg total (empty bar): "Empty bar"
- 132.5kg total: "Plates: 25 + 20 + 10 + 1.25 each side"

**Styling**: `caption`, `textTertiary`. Plate weights in the text are colored with their corresponding plate color for quick visual matching.

### 5.5 Full Plate Diagram (Visual)

Tapping "View plate diagram" or tapping the plate hint line opens a bottom sheet (40% screen height) showing a visual representation of the barbell:

```
+-----------------------------------------+
|              -----                       | <- Handle
|                                          |
|  PLATE SETUP — 85kg                      | <- sectionHeader
|  Bar: 20kg + 32.5kg each side           |
|                                          |
|  Side view:                              |
|                                          |
|   [2.5] [10] [===20===]  |BAR|  [===20===] [10] [2.5]
|                                          |
|  Per side:                               |
|   +------+                               |
|   | 20kg |  (blue disc, large)          |
|   +------+                               |
|   +----+                                 |
|   |10kg|  (green disc, medium)          |
|   +----+                                 |
|   +--+                                   |
|   |2.5| (grey disc, small)              |
|   +--+                                   |
|                                          |
+-----------------------------------------+
```

**Visual representation**:
- **Bar**: Grey horizontal line, 200pt wide, 4pt thick, centered.
- **Plates**: Colored rectangles/rounded rects flanking the bar, symmetrical on both sides. Plate height varies by weight to give visual weight cues:
  - 25kg: 60pt tall, 14pt wide
  - 20kg: 56pt tall, 12pt wide
  - 15kg: 48pt tall, 11pt wide
  - 10kg: 40pt tall, 10pt wide
  - 5kg: 32pt tall, 8pt wide
  - 2.5kg: 24pt tall, 6pt wide
  - 1.25kg: 18pt tall, 5pt wide
- **Plate labels**: `plateLabel` (SF Mono, 14pt Bold), white text centered on the plate (or below if too small).
- **Plate colors**: Match the color palette defined in Section 1.1.
- **Order**: Heaviest plates closest to the center (closest to the bar collar), lightest on the outside. This matches real-world loading order.

**Animation**: When the user changes weight via the stepper, the plate diagram animates: new plates slide in from the outside (200ms spring), removed plates slide out. This gives immediate visual feedback.

**Per-side breakdown**: Below the diagram, a vertical list of plates needed per side with their colors and weights. Useful when the diagram is too small to read labels.

### 5.6 Edge Cases

| Scenario | Behavior |
|----------|----------|
| Weight not achievable with available plates | Show warning: "Cannot load exactly {weight}kg. Nearest: {nearest_lower}kg or {nearest_higher}kg." Offer to adjust weight. |
| Weight less than bar | Show "Weight is less than the bar (20kg)." |
| Non-barbell exercise | Plate calculator hidden. No plate hints shown. |
| EZ curl bar selected | Bar weight changes to 10kg. Plate calculation adjusts. |
| Dumbbell exercise | No plate calculator. Dumbbells are fixed-weight in most gyms. |
| User has custom plate set (e.g., only bumper plates) | Calculator uses only available plates from settings. |
| Imperial units (lbs) | Plates: 45, 35, 25, 10, 5, 2.5 lbs. Bar: 45 lbs. |

### 5.7 Smart Plate Suggestions

When the user is about to increase weight (progressive overload), the plate hint proactively shows what changes:

```
Current: 82.5kg -> Plates: 20 + 10 + 1.25 each side
Next:    85.0kg -> Plates: 20 + 10 + 2.5 each side
Change:  Swap 1.25 for 2.5 on each side
```

This "Change" line appears only when weight increases from the previous session, helping the user know exactly what to swap without mental math.

---

## 6. Superset, Circuit & Drop Set Support

### 6.1 Overview

Three advanced set structures beyond standard straight sets. Each has distinct visual treatment, logging flow, and rest behavior. The goal: zero confusion about what to do next, even when the user is mid-set and gassed.

### 6.2 Supersets (2-Exercise Pairs)

A superset pairs two exercises performed back-to-back with no rest between them. Rest only after completing one round (one set of each exercise).

#### 6.2.1 Visual Grouping — Today's Workout View

```
+ - - SUPERSET A - - - - - - - - - - +
| +----------------------------------+ |
| | 3A  CABLE FLY              Chest | |
| |     3 x 12 @ 15kg               | |
| |     Last: 12.5kg x 12           | |
| +----------------------------------+ |
|          [no rest arrow]             |
| +----------------------------------+ |
| | 3B  LATERAL RAISE     Shoulders  | |
| |     3 x 15 @ 10kg               | |
| |     Last: 10kg x 14             | |
| +----------------------------------+ |
+ - - - - - - - - - - - - - - - - - -+
```

- **Container**: Dashed border, 1pt, `supersetA` color. Corner radius 16pt. Internal padding 8pt.
- **Label**: "SUPERSET A" in `miniTag` style, `supersetA` color, positioned top-center, overlapping the dashed border with a `background`-colored backing pad (8pt horizontal padding).
- **Numbering**: "3A", "3B" instead of sequential. Letter suffix inherits superset color.
- **Between cards**: 4pt spacing (tighter than normal 8pt). A small "no rest" arrow icon (SF Symbol: `arrow.down`, 11pt, `supersetA`) centered between the two cards.
- **Multiple supersets**: Alternate between `supersetA` (#5E5CE6) and `supersetB` (#BF5AF2) colors.

#### 6.2.2 Active Workout Flow — Supersets

Step-by-step flow for a 3-round superset (Cable Fly + Lateral Raise):

1. **Exercise A, Set 1**: Normal set logging. Cable Fly appears. User logs 15kg x 12, taps DONE.
2. **No rest timer**. Instead: immediate horizontal slide transition (300ms) to Exercise B. A top banner appears: "SUPERSET -- No rest, go to Lateral Raise" in `caption`, `supersetA`. Banner background: `supersetA` at 10% opacity, full width, 36pt height.
3. **Exercise B, Set 1**: Lateral Raise appears. User logs 10kg x 15, taps DONE.
4. **Rest timer starts** (default 2:00 for supersets). Label: "Superset round 1 of 3 complete."
5. **Rest ends**: Returns to Exercise A, Set 2. Banner: "SUPERSET -- Round 2 of 3."
6. Repeat until all 3 rounds complete.
7. **All rounds done**: Both exercises marked complete. Normal transition to next exercise.

**The Exercise Navigation during supersets**:
- Both exercises show as "current" in the exercise list drawer:
  ```
  [>]  3A Cable Fly           1/3
  [>]  3B Lateral Raise       0/3     <- Both highlighted
  ```
- PREV/NEXT buttons navigate between the superset pair (A<->B) during a round, and to exercises outside the superset between rounds.

#### 6.2.3 Round Counter

During active superset, a round counter is visible in the exercise header:

```
SUPERSET A -- Round 2 of 3
  Cable Fly (3A) <-> Lateral Raise (3B)
```

- `captionBold`, `supersetA`. The round number animates (scale pop 1.0 to 1.2 to 1.0, 300ms) when a round completes.

### 6.3 Circuits (3+ Exercise Groups)

A circuit chains 3 or more exercises with no rest between them. Rest only after completing one full round.

#### 6.3.1 Visual Grouping — Today's Workout View

```
+ = = CIRCUIT A (3 exercises) = = = = +
| +----------------------------------+ |
| | 5A  PLANK                 Core   | |
| |     3 x 45s                      | |
| +----------------------------------+ |
|          [no rest arrow]             |
| +----------------------------------+ |
| | 5B  RUSSIAN TWIST        Core   | |
| |     3 x 20 @ 8kg                | |
| +----------------------------------+ |
|          [no rest arrow]             |
| +----------------------------------+ |
| | 5C  DEAD BUG              Core   | |
| |     3 x 12                       | |
| +----------------------------------+ |
+ = = = = = = = = = = = = = = = = = =+
```

- **Container**: Double dashed border, 1.5pt, `circuitC` color (#FF9F0A). Corner radius 16pt.
- **Label**: "CIRCUIT A (3 exercises)" in `miniTag`, `circuitC`.
- **Numbering**: "5A", "5B", "5C". Letter suffixes in `circuitC`.
- **"No rest" arrows** between each exercise card.
- Circuits are visually distinct from supersets by using a different color and double-dashed border.

#### 6.3.2 Active Workout Flow — Circuits

Same as supersets but with 3+ exercises per round. The flow:
1. Exercise A set -> immediate transition -> Exercise B set -> immediate transition -> Exercise C set -> **REST TIMER** (default 2:00).
2. After rest: back to Exercise A for the next round.
3. Round counter: "Circuit round 2 of 3."

**Key UX detail**: During a circuit, the bottom navigation shows a mini-progress indicator:

```
  Round 2 of 3:  [A: done] [B: current] [C: upcoming]
```

Each exercise in the circuit is represented by a small dot (8pt): green (done), primary (current), grey (upcoming).

### 6.4 Drop Sets

A drop set is a single exercise performed for multiple sets in rapid succession with decreasing weight and no rest between sets.

#### 6.4.1 Visual Grouping — Today's Workout View

```
+--------------------------------------+
| 6  LATERAL RAISE [drop]    Shoulders |   <- [drop] badge
|    Drop Set: 3 drops                 |
|    14kg x 10 -> 10kg x 12 -> 6kg x15|
|    Last: 12/10/8kg (10,12,15)        |
+--------------------------------------+
```

- **Drop badge**: Small pill badge "DROP" in `dropSet` color (#FF375F), `miniTag` style, positioned after the exercise name.
- **Prescription format**: Shows all drops on one line with arrows: "{w1} x {r1} -> {w2} x {r2} -> {w3} x {r3}".
- The weights decrease while the rep targets stay the same or increase (common drop set protocol).

#### 6.4.2 Active Workout Flow — Drop Sets

```
+----------------------------------------------------+
|  DROP SET -- Lateral Raise                           |
|  Drop 1 of 3                                        |
|                                                      |
|  [  14  ] kg    [  10  ] reps                       |
|                                                      |
|  NEXT DROP: 10kg x 12                               |
|                                                      |
|         [ CHECK DONE -- DROP ]                      |
+----------------------------------------------------+
```

1. **Drop 1**: User performs at starting weight. Taps "DONE -- DROP".
2. **Immediate transition** (no rest). Weight auto-decreases to the next drop value. Animation: old weight slides left and fades out (250ms), new weight slides in from right. Haptic: `.rigid`.
3. **Drop 2**: User performs. Taps "DONE -- DROP".
4. **Drop 3 (final)**: Button reads "DONE -- FINISH DROP SET" instead. After this, normal rest timer starts.
5. **All drops logged as one compound entry** in the completed sets history:
   ```
   Set 1 (Drop)  14kg x 10, 10kg x 12, 6kg x 15  [check]
   ```

**Key UX rule**: Between drops, there is NO rest timer and NO rest timer button. The urgency is intentional — drop sets are about continuous tension. The "no rest" banner from supersets is not needed here because the weight auto-changes within the same exercise view.

#### 6.4.3 Drop Set Configuration

When converting an exercise to a drop set (via More menu > "Convert to Drop Set"):

```
+-----------------------------------------+
|  DROP SET SETUP                          |
|                                          |
|  Starting weight: [14] kg               |
|  Number of drops: [3]  (2-5)            |
|                                          |
|  Drop percentage: [30%]                  |
|  (Each drop reduces weight by ~30%)     |
|                                          |
|  Calculated drops:                       |
|  Drop 1: 14kg x 10 reps                 |
|  Drop 2: 10kg x 12 reps                 |
|  Drop 3:  6kg x 15 reps                 |
|                                          |
|  [Cancel]              [Apply]           |
+-----------------------------------------+
```

- **Number of drops**: 2-5. Default: 3. Stepper control.
- **Drop percentage**: 25-40%. Default: 30%. Slider or stepper.
- **Rep adjustment**: Reps increase by 2 per drop by default (since weight is lighter, more reps are achievable). Editable.
- Drop weights are rounded to the nearest available increment.

### 6.5 Creating Groups

#### 6.5.1 Creating a Superset

1. From exercise card More menu: "Convert to Superset."
2. Bottom sheet: "Pair with which exercise?" Shows adjacent exercises.
3. Tap to select. Both exercises become a superset.
4. Alternative: long-press an exercise card, drag it onto another card. When overlapping, a "Create Superset?" tooltip appears. Drop to confirm.

#### 6.5.2 Creating a Circuit

1. From superset bracket's More menu: "Add to Circuit" (converts superset to circuit).
2. Or: from any exercise card: "Add to Circuit" -> select 2+ other exercises.
3. Maximum 5 exercises per circuit (more is unrealistic for gym use).

#### 6.5.3 Breaking Groups

- Drag an exercise out of a group bracket to remove it.
- From the group label's More menu: "Break Superset" / "Break Circuit" — reverts all exercises to straight sets.

---

## 7. Rest Timer System

### 7.1 Overview

Auto-starts after completing a set. Takes over the center of the active workout screen.

### 7.2 Screen Structure

```
+-----------------------------------------+
|  X End    PUSH DAY    [timer] 34:12     |
|-----------------------------------------|
|                                          |
|  BENCH PRESS -- Resting                  |
|  Set 2 of 4 completed                   |
|                                          |
|           +----------+                   |
|          /            \                  |
|         |              |                 |
|         |    2:34      |                 | <- timerDisplay (72pt)
|         |              |                 |
|          \            /                  |
|           +----------+                   |
|                                          | <- 200pt diameter circle
|     [  -30s  ]    [  +30s  ]            | <- Timer adjust buttons
|                                          |
|  +--------------------------------------+|
|  |        SKIP REST                     || <- Secondary button (44pt)
|  +--------------------------------------+|
|                                          |
|  Next: Set 3 -- 85kg x 8               | <- caption, textSecondary
|                                          |
|  -- Completed Sets -------------------- |
|  Set 1    85kg x 8     RPE 7    [check] |
|  Set 2    85kg x 8     RPE 8    [check] |
|                                          |
|-----------------------------------------|
|  Exercise 1 of 6                         |
|  [#######..........................]     |
|  < PREV         REST          NEXT >    |
+-----------------------------------------+
```

### 7.3 Timer Circle

- **Diameter**: 200pt.
- **Background circle**: 4pt stroke, `surfaceElevated`.
- **Progress arc**: 4pt stroke, `primary`. Draws clockwise from 12 o'clock, representing remaining time as a fraction of total rest.
- **Time display**: `timerDisplay` (SF Mono, 72pt, Bold), `textPrimary`, centered in circle. Format: "M:SS".
- **Pulse animation**: Progress arc border pulses with opacity (1.0 to 0.6 to 1.0) on a 1-second cycle. `.easeInOut` repeat.
- **Last 10 seconds**: Pulse accelerates to 500ms cycle. Arc color shifts from `primary` to `recoveryYellow`. Time display flashes. Haptic: `.light` x2 at the 10-second mark.
- **Timer at zero**: Arc disappears. Time shows "0:00" briefly, then flashes `primary` twice. Haptic `.warning`. Audio chime (if not silenced). Transitions back to set input.

### 7.4 Default Rest Times

| Exercise Type | Default Rest | Rationale |
|--------------|-------------|-----------|
| Barbell compound (Bench, Squat, Deadlift, OHP, Row) | 3:00 | ATP-PC replenishment for heavy loads, CNS recovery |
| Dumbbell compound (DB Bench, DB Row, DB OHP) | 2:30 | Slightly less CNS demand than barbell |
| Isolation single-joint (Curls, Extensions, Lateral Raises, Flyes) | 1:30 | Lower systemic fatigue, muscle-specific recovery |
| Machine exercises | 1:30 | Stabilizers not taxed, faster recovery |
| Cable exercises | 1:30 | Similar to machines |
| Bodyweight (Pull-ups, Dips, Push-ups) | 2:00 | Moderate systemic demand |
| Core exercises | 1:00 | Small muscle groups, quick recovery |
| Superset (rest after completing all exercises in one round) | 2:00 | Accounts for active rest during partner exercise |
| Circuit (rest after completing full round) | 2:00 | Same rationale as supersets |
| Drop set (rest after all drops) | 2:30 | Extended time under tension requires more recovery |
| Warm-up to warm-up | 0:60 | Minimal rest for progressive loading |
| Last warm-up to first working set | 1:30 | Prepare for working load |

Users can customize default rest times per exercise category in Training Settings. Per-exercise overrides are also possible in the Exercise Library.

**Recovery-adjusted rest times**: On yellow recovery days, all rest times get +30 seconds automatically. This is transparent to the user (shown in the Recovery Detail Sheet explanation).

### 7.5 Timer Controls

- **-30s button**: Left of timer. Pill shape, 72pt x 36pt, `surfaceElevated`. Text: "-30s" in `captionBold`, `textSecondary`. Reduces rest timer by 30 seconds. Minimum: 0.
- **+30s button**: Right of timer. Same style. Adds 30 seconds.
- **SKIP REST button**: Full width, secondary style (surface bg, textPrimary text, 44pt height). Immediately ends rest.
- **Tap on timer circle itself**: Also skips rest (convenience shortcut for experienced users).
- **Timer reaching zero**:
  1. Haptic: `.warning` notification feedback.
  2. Audio: Short chime (if device not silenced). Respects system volume.
  3. Timer text flashes `primary` color twice.
  4. Automatically transitions back to set input for next set.
  5. If phone is locked, a local notification fires: "Rest over -- Set {n} ready" with the exercise name.
  6. If Apple Watch is connected, Watch haptic fires simultaneously.

### 7.6 Rest Timer in Superset / Circuit Mode

- **Within a superset/circuit**: NO rest timer between exercises. Immediate transition with urgency haptic (`.rigid` + `.rigid` rapid).
- **After completing a round**: Rest timer appears with superset/circuit rest duration.
- **Label changes**: "Superset round {n} of {total} complete" or "Circuit round {n} of {total} complete."

### 7.7 Rest Timer in Drop Set Mode

- **Between drops**: NO rest timer. Weight changes immediately.
- **After all drops**: Normal rest timer with drop set rest duration (2:30 default).
- **Label**: "Drop set complete."

### 7.8 Background Timer

If the user switches to another app during rest:
- Timer continues counting in the background.
- A local notification fires when rest is complete.
- Live Activity on lock screen shows the countdown.
- On return to app, timer shows current remaining time (or "REST OVER -- tap to continue" if timer already finished).

---

## 8. Workout Summary (Post-Workout)

### 8.1 Screen Structure

```
+-----------------------------------------+
|  X Close                                 |
|-----------------------------------------|
|                                          |
|         WORKOUT COMPLETE                 | <- screenTitle, textPrimary
|         Push Day                         | <- body, textSecondary
|                                          |
|     +---------------------------+        |
|     |    +---------------+      |        | <- Completion ring (120pt)
|     |    |               |      |        |
|     |    |   100%        |      |        |
|     |    |               |      |        |
|     |    +---------------+      |        |
|     +---------------------------+        |
|                                          |
|  +----------+-----------+----------+     |
|  | [t] 48:32| [w] 12,480| [f] ~340 |    | <- Stat cards (80pt)
|  | Duration |  Volume   | Calories |    |
|  |          |   kg      |  kcal    |    |
|  +----------+-----------+----------+     |
|                                          |
|  [trophy] PERSONAL RECORDS              | <- sectionHeader, prGold
|  +--------------------------------------+|
|  | [star] Bench Press -- New Est. 1RM   || <- PR Card (gold border)
|  |   102.5kg (prev: 100kg)             ||
|  +--------------------------------------+|
|  +--------------------------------------+|
|  | [star] OHP -- Rep PR                ||
|  |   50kg x 9 (prev best: x 8)        ||
|  +--------------------------------------+|
|                                          |
|  EXERCISE BREAKDOWN                      | <- sectionHeader
|  +--------------------------------------+|
|  | Bench Press              4/4 [check] ||
|  | 85x8, 85x8, 85x7, 85x8             ||
|  | Vol: 2,380kg  Est 1RM: 102.5        ||
|  |--------------------------------------|
|  | Incline DB Press         3/3 [check] ||
|  | 32x10, 32x10, 32x9                  ||
|  | Vol: 928kg                           ||
|  |--------------------------------------|
|  | Cable Fly (SS)           3/3 [check] ||
|  | 15x12, 15x12, 15x12                 ||
|  | Vol: 540kg                           ||
|  |--------------------------------------|
|  | Lateral Raise (SS)      3/3 [check]  ||
|  | 10x15, 10x15, 10x14                 ||
|  | Vol: 440kg                           ||
|  |--------------------------------------|
|  | Overhead Press           4/4 [check] ||
|  | 50x8, 50x9, 50x8, 50x8             ||
|  | Vol: 1,650kg  Est 1RM: 63.5         ||
|  |--------------------------------------|
|  | Tricep Pushdown          3/3 [check] ||
|  | 25x12, 25x12, 25x11                 ||
|  | Vol: 875kg                           ||
|  +--------------------------------------+|
|                                          |
|  TOMORROW'S OUTLOOK                      |
|  +--------------------------------------+|
|  | Based on your effort today and       ||
|  | current recovery trend:              ||
|  |                                      ||
|  | [clipboard] Pull Day (estimated)     ||
|  | Will confirm after tonight's         ||
|  | Whoop recovery update.               ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  |         [note] ADD NOTES             || <- Secondary button
|  +--------------------------------------+|
|  +--------------------------------------+|
|  |         [share] SHARE                || <- Secondary button
|  +--------------------------------------+|
|  +--------------------------------------+|
|  |       [check]  SAVE & CLOSE         || <- Primary button (56pt)
|  +--------------------------------------+|
|                                          |
+-----------------------------------------+
```

### 8.2 Completion Ring

- **Diameter**: 120pt, centered.
- **Ring stroke**: 6pt. Background: `surfaceElevated`. Fill: `primary` (or `deloadBlue` during deload).
- **Fill animation**: Draws from 0% to actual completion percentage over 800ms with `.easeInOut` curve.
- **Center text**: Completion percentage in `metricSmall`, `textPrimary`.
- **Below ring**: "Complete" or "75% Complete" in `caption`, `textSecondary`.

### 8.3 Stat Cards

Three equal-width cards. Height 80pt, background `surface`, radius 12pt.

| Card | Icon | Primary Value | Label | Sublabel |
|------|------|---------------|-------|----------|
| Duration | `timer` | "48:32" | "Duration" | Active time only |
| Volume | `scalemass` | "12,480" | "Volume" | "kg" |
| Calories | `flame` | "~340" | "Calories" | "kcal" |

- **Volume calculation**: Sum of (weight x reps) for all working sets. Warm-up sets excluded.
- **Calorie calculation**: MET-based estimate from workout type, duration, body weight. Prefixed with "~". If HealthKit provides active calories, use that instead.

### 8.4 Personal Records Section

Only appears if PRs were achieved. See **Section 12** for the complete PR system specification.

PR cards: background `surface`, border 1.5pt `prGold`, corner radius 12pt, left accent 3pt gold bar. Slide in one at a time (200ms stagger) with scale pop and gold shimmer.

### 8.5 Exercise Breakdown

Single card with all exercises separated by 0.5pt `divider` lines. Each exercise shows: name, set completion, set-by-set results, volume, and estimated 1RM (for compounds).

### 8.6 Tomorrow's Outlook

Forward-looking recommendation card. Shows expected workout type contingent on recovery. Disclaimer about Whoop update.

### 8.7 Add Notes

Tapping "ADD NOTES" opens inline multi-line text input. Notes are searchable in workout history.

### 8.8 Share Card

Generates a styled share image (1080x1350 for Instagram story, 1080x1080 for square). Background gradient, Tempo branding, workout stats, PRs. Shared via UIActivityViewController. User can toggle what to include.

### 8.9 Save & Close

Primary button. Saves to SwiftData (already incrementally saved). Dismisses to Today's Workout View.

---

## 9. Week Plan View

### 9.1 Screen Structure

```
+-----------------------------------------+
|  < Back         THIS WEEK     [regen]   |
|-----------------------------------------|
|                                          |
|  March 24 -- 30, 2026                   | <- sectionHeader
|                                          |
|  +---+---+---+---+---+---+---+         |
|  |MON|TUE|WED|THU|FRI|SAT|SUN|         | <- Day headers
|  +---+---+---+---+---+---+---+         |
|  | G | G | F | Y | G | F |   |         | <- Recovery dots
|  |PSH|PUL|FTB|MOB|LEG|FTB|RST|         | <- Workout types
|  |chk|   |   |   |   |   |   |         | <- Status
|  +---+---+---+---+---+---+---+         |
|                                          |
|  -- TODAY: Monday -------------------- |
|  +--------------------------------------+|
|  | [check]  PUSH DAY -- Completed      ||
|  |    48:32  *  12,480kg               ||
|  +--------------------------------------+|
|                                          |
|  -- Tomorrow: Tuesday ---------------- |
|  +--------------------------------------+|
|  |    PULL DAY                          ||
|  |    ~50 min  *  6 exercises           ||
|  |    [G] Recovery: projected green     ||
|  +--------------------------------------+|
|                                          |
|  -- Wednesday ----------------------- |
|  +--------------------------------------+|
|  | [ball] FOOTBALL                      ||
|  |    Match @ 8:00 PM                  ||
|  |    Pre-match prep available          ||
|  +--------------------------------------+|
|                                          |
|  -- Thursday ----------------------- |
|  +--------------------------------------+|
|  | [yoga] MOBILITY FLOW                ||
|  |    ~25 min  *  Post-match           ||
|  |    [Y] Recovery: projected yellow    ||
|  +--------------------------------------+|
|                                          |
|  -- Friday -------------------------  |
|  +--------------------------------------+|
|  |    LEG DAY                           ||
|  |    ~55 min  *  6 exercises           ||
|  |    [G] Recovery: projected green     ||
|  +--------------------------------------+|
|                                          |
|  -- Saturday ----------------------- |
|  +--------------------------------------+|
|  | [ball] FOOTBALL                      ||
|  |    Match @ 3:00 PM                  ||
|  +--------------------------------------+|
|                                          |
|  -- Sunday -------------------------  |
|  +--------------------------------------+|
|  | [rest] REST DAY                      ||
|  |    Recovery day after match          ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  |     [regen]  REGENERATE PLAN        || <- Secondary button
|  +--------------------------------------+|
|                                          |
+-----------------------------------------+
```

### 9.2 Seven-Day Grid

- **Day headers**: `miniTag`, `textTertiary`, centered. 3-letter abbreviation.
- **Cell size**: Equal width (screen width / 7 - margins). Height: 80pt.
- **Recovery dots**: 8pt circles, recovery color. Future days are predictions.
- **Workout type abbreviations**: PSH, PUL, LEG, UPR, FUL, RUN, MOB, FTB, RST, DLD (deload).
- **Status indicators**: [check] (green) completed, [dot] (primary) today, (empty) future, [X] (red) missed.
- **Today's cell**: Background `surfaceElevated`, border 1.5pt `primary`.
- **Deload week**: All cells have `deloadBlue` bottom accent bar. Grid header reads "DELOAD WEEK" in `deloadBlue`.

### 9.3 Daily Detail Cards

Below the grid, vertical scrollable list. Completed, today, future, football, and rest day cards each styled per Section 2 patterns.

### 9.4 AI Plan Generation Logic

See **Section 15** for the complete workout generation algorithm with pseudocode.

Summary of generation rules (priority order):
1. Football days are fixed and immutable.
2. No heavy legs on football day or T-1.
3. Rest day after football if recovery is projected yellow/red.
4. Fill remaining days with training split, respecting 48h minimum between same muscle group.
5. Running on green-recovery non-weight-training days.
6. At least 1 rest day per week.
7. Mobility on yellow-recovery days or after football.
8. Deload week every 4-6 weeks or when triggered.

### 9.5 Regenerate Plan

"REGENERATE PLAN" button with confirmation dialog. Completed days are never modified. Changed cells get sparkle animation.

### 9.6 Manual Override

Tap future day card > "Change Workout Type" > bottom sheet with options. Selecting a new type regenerates that day's exercises while respecting constraints.

### 9.7 Week Navigation

Swipe left/right for next/previous weeks. Past weeks show completed history. Future weeks show projections (dashed borders, lower confidence).

### 9.8 Edge Cases

| Scenario | Behavior |
|----------|----------|
| User misses a day | Missed day shows X (red). Plan shifts: missed workout gets priority next available day. |
| Unplanned workout | Logged as "Unplanned." Plan adjusts to avoid overtraining same muscle group. |
| Football cancelled | Convert to regular training day via manual override. |
| Recovery consistently red 3+ days | Plan shifts to deload week. |
| Vacation (no gym) | Mark week as "Travel." Bodyweight-only or mobility-only sessions. |
| Deload week active | All future days show deload variants. Visual: `deloadBlue` accents everywhere. |

---

## 10. Exercise Library (150+ Exercises)

### 10.1 Screen Structure

```
+-----------------------------------------+
|  < Back       EXERCISE LIBRARY           |
|-----------------------------------------|
|  +--------------------------------------+|
|  | [search] Search exercises...         || <- Search bar (44pt)
|  +--------------------------------------+|
|                                          |
|  [All][Chest][Back][Shoulders][Arms]    | <- Filter chips (scrollable)
|  [Legs][Core][Cardio][Mobility]         |
|  [Football]                              |
|                                          |
|  Equipment: [All][BB][DB][Cable]        | <- Sub-filters
|  [Machine][BW][KB][Band]               |
|  Pattern: [All][Push][Pull][Hinge]      |
|  [Squat][Carry][Isolation]              |
|  Difficulty: [All][Beg][Int][Adv]       |
|                                          |
|  -- CHEST (16 exercises) -------------- |
|  +--------------------------------------+|
|  | [icon] Barbell Bench Press           ||
|  |    Barbell * Compound * Push         ||
|  |    Intermediate                      ||
|  +--------------------------------------+|
|  ...                                     |
|                                          |
|  +--------------------------------------+|
|  |     + CREATE CUSTOM EXERCISE        || <- Secondary button
|  +--------------------------------------+|
+-----------------------------------------+
```

### 10.2 Search and Filters

- **Search**: Real-time filtering as user types. Searches name, muscle group, equipment, and movement pattern. Debounced at 200ms.
- **Muscle group chips**: Single-select. Scrolls list to that category.
- **Sub-filters**: Equipment, Pattern, Difficulty. AND-combined with muscle group.
- **Difficulty filter**: Beginner / Intermediate / Advanced. Based on technical complexity and injury risk.

### 10.3 Exercise Data Schema

Every exercise in the database has the following fields:

```
Exercise {
  id: UUID
  name: String
  primaryMuscles: [MuscleGroup]           // e.g., [.pectoralisMajor]
  secondaryMuscles: [MuscleGroup]         // e.g., [.anteriorDeltoid, .triceps]
  equipment: Equipment                     // .barbell, .dumbbell, .cable, etc.
  difficulty: Difficulty                   // .beginner, .intermediate, .advanced
  movementPattern: MovementPattern         // .push, .pull, .hinge, .squat, .carry, .isolation, .core
  defaultSets: Int                         // e.g., 4
  defaultReps: Int                         // e.g., 8
  defaultRestSeconds: Int                  // e.g., 180
  weightIncrementKg: Double                // e.g., 2.5
  typicalProgressionIncrementKg: Double    // e.g., 2.5 per progression cycle
  commonMistakes: [String]                 // coaching cues
  substitutes: [ExerciseID]               // 3 alternative exercises
  trackingType: TrackingType              // .weightReps, .bodyweightReps, .duration, .distance
  includeWarmUpDefault: Bool              // true for compounds
  isCompound: Bool                        // affects rest time, warm-up, etc.
  barType: BarType?                       // .olympic20, .ezCurl10, .womens15, nil
  instructions: [String]                   // step-by-step how-to
  tips: [String]                          // coaching cues
  footballSafe: FootballSafety            // .always, .notOnT1, .notOnT0orT1, .never
}
```

### 10.4 Complete Exercise Database

Legend for each exercise entry:
- **Primary**: Primary muscles worked
- **Secondary**: Secondary muscles worked
- **Equipment**: Required equipment
- **Difficulty**: Beginner (B) / Intermediate (I) / Advanced (A)
- **Pattern**: Movement pattern
- **Default**: Sets x Reps, rest time
- **Increment**: Typical weight progression per cycle
- **Cues**: Key coaching cues / common mistakes
- **Substitutes**: 3 alternatives
- **Football**: Safety rating relative to match days

---

### CHEST (16 exercises)

#### 1. Barbell Bench Press
- **Primary**: Pectoralis major (sternal head), Pectoralis major (clavicular head)
- **Secondary**: Anterior deltoid, Triceps brachii, Serratus anterior
- **Equipment**: Barbell + Flat bench + Rack
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 4x8, 150s rest
- **Increment**: 2.5kg per progression cycle
- **Cues**: Retract and depress scapulae before unracking. Plant feet firmly. Lower to mid-chest with elbows at 45-75 degrees (NOT 90 -- this impinges the shoulder). Drive through the floor on the press. Bar path is a slight J-curve, not straight vertical. Do not bounce off chest.
- **Substitutes**: Dumbbell Bench Press, Machine Chest Press, Floor Press
- **Football**: Always safe (upper body pressing does not impair sprint or lower body match performance)

#### 2. Incline Barbell Bench Press
- **Primary**: Pectoralis major (clavicular head), Anterior deltoid
- **Secondary**: Triceps brachii, Serratus anterior
- **Equipment**: Barbell + Incline bench (30-45 degrees) + Rack
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 4x8, 150s rest
- **Increment**: 2.5kg
- **Cues**: Bench angle 30-45 degrees (higher = more shoulder, less chest). Grip slightly wider than flat bench. Lower to upper chest / clavicle line. Avoid excessive back arch.
- **Substitutes**: Incline Dumbbell Press, Low-to-High Cable Fly, Landmine Press
- **Football**: Always safe (upper body pressing does not impair match performance)

#### 3. Decline Barbell Bench Press
- **Primary**: Pectoralis major (sternal head, lower fibers)
- **Secondary**: Triceps brachii, Anterior deltoid
- **Equipment**: Barbell + Decline bench + Rack
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x10, 150s rest
- **Increment**: 2.5kg
- **Cues**: Secure legs under pads before unracking. Lower to lower chest / sternum. Shorter range of motion than flat bench. Do not go excessively heavy -- decline position makes bailout harder.
- **Substitutes**: High-to-Low Cable Fly, Dip (chest-focused), Decline Dumbbell Press
- **Football**: Always safe (upper body)

#### 4. Dumbbell Bench Press
- **Primary**: Pectoralis major, Anterior deltoid
- **Secondary**: Triceps brachii, Serratus anterior, Rotator cuff (stabilizers)
- **Equipment**: Dumbbells + Flat bench
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x10, 150s rest
- **Increment**: 2kg (1kg per dumbbell)
- **Cues**: Kick dumbbells up from knees to pressing position. Press in a slight arc (dumbbells come together at top but do not clank). Lower until upper arms are parallel to floor or slightly below. Greater range of motion than barbell -- use this for hypertrophy.
- **Substitutes**: Barbell Bench Press, Machine Chest Press, Push-Up
- **Football**: Always safe (moderate load)

#### 5. Incline Dumbbell Press
- **Primary**: Pectoralis major (clavicular head), Anterior deltoid
- **Secondary**: Triceps brachii, Serratus anterior
- **Equipment**: Dumbbells + Incline bench (30-45 degrees)
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x10, 150s rest
- **Increment**: 2kg
- **Cues**: Bench at 30 degrees for more chest, 45 degrees for more shoulder. Press to lockout but do not hyperextend elbows. Keep wrists neutral (do not let dumbbells roll back).
- **Substitutes**: Incline Barbell Press, Low-to-High Cable Fly, Landmine Press
- **Football**: Always safe

#### 6. Dumbbell Fly
- **Primary**: Pectoralis major (full)
- **Secondary**: Anterior deltoid, Biceps brachii (stabilizer)
- **Equipment**: Dumbbells + Flat bench
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2kg
- **Cues**: Maintain a slight bend in elbows throughout (15-20 degrees). Lower until you feel a deep stretch in the chest -- do not go past 180 degrees of shoulder abduction. Squeeze chest at the top. Think "hugging a barrel." Use lighter weight than pressing movements.
- **Substitutes**: Cable Fly (Low-to-High), Pec Deck, Cable Crossover
- **Football**: Always safe

#### 7. Cable Fly (Low-to-High)
- **Primary**: Pectoralis major (clavicular head)
- **Secondary**: Anterior deltoid
- **Equipment**: Cable machine (dual pulleys, low position)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Set pulleys at lowest position. Step forward for constant tension. Bring hands together at upper chest height with slight elbow bend. Squeeze at the top for 1 second. Control the eccentric -- do not let cables yank arms back.
- **Substitutes**: Incline Dumbbell Fly, Dumbbell Fly, Pec Deck
- **Football**: Always safe

#### 8. Cable Fly (High-to-Low)
- **Primary**: Pectoralis major (sternal head, lower fibers)
- **Secondary**: Anterior deltoid
- **Equipment**: Cable machine (dual pulleys, high position)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Set pulleys at highest position. Lean slightly forward. Bring hands together at hip level. Squeeze at the bottom. Think "scooping motion."
- **Substitutes**: Decline Dumbbell Fly, Dip (chest-focused), High-to-Low Cable Crossover
- **Football**: Always safe

#### 9. Cable Crossover (Mid)
- **Primary**: Pectoralis major (full)
- **Secondary**: Anterior deltoid
- **Equipment**: Cable machine (dual pulleys, mid position)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Pulleys at shoulder height. Step forward. Bring hands together in front of chest with arms slightly bent. Cross hands slightly at the bottom for extra squeeze.
- **Substitutes**: Dumbbell Fly, Pec Deck, Cable Fly (Low-to-High)
- **Football**: Always safe

#### 10. Machine Chest Press
- **Primary**: Pectoralis major, Anterior deltoid
- **Secondary**: Triceps brachii
- **Equipment**: Chest press machine
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg (1 stack notch)
- **Cues**: Adjust seat so handles are at mid-chest. Keep shoulder blades retracted. Press to full extension. Do not lock elbows aggressively. Good for beginners and for yellow-recovery day swaps.
- **Substitutes**: Barbell Bench Press, Dumbbell Bench Press, Push-Up
- **Football**: Always safe (low CNS demand)

#### 11. Pec Deck / Machine Fly
- **Primary**: Pectoralis major (full)
- **Secondary**: Anterior deltoid
- **Equipment**: Pec deck machine
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Adjust seat so handles align with mid-chest. Maintain slight elbow bend. Squeeze at the center for 1-2 seconds. Do not use momentum.
- **Substitutes**: Dumbbell Fly, Cable Fly (any angle), Cable Crossover
- **Football**: Always safe

#### 12. Push-Up
- **Primary**: Pectoralis major, Anterior deltoid
- **Secondary**: Triceps brachii, Core (stabilizer)
- **Equipment**: Bodyweight (no equipment)
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x15, 90s rest
- **Increment**: +2 reps per progression, or add weight vest
- **Cues**: Hands shoulder-width or slightly wider. Body in a straight line from head to heels. Lower until chest nearly touches floor. Full lockout at top. Avoid sagging hips or piking. Elbows at 45 degrees, not flared.
- **Substitutes**: Dumbbell Bench Press, Machine Chest Press, Banded Push-Up
- **Football**: Always safe

#### 13. Chest Dip
- **Primary**: Pectoralis major (lower fibers), Triceps brachii
- **Secondary**: Anterior deltoid, Core
- **Equipment**: Dip bars / Parallel bars
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x10, 120s rest
- **Increment**: +2.5kg (belt) or +1 rep
- **Cues**: Lean torso forward 15-30 degrees for chest emphasis (upright = more triceps). Lower until upper arms are parallel to floor or slight stretch in chest. Do not go too deep -- impinges shoulder. Weighted: use dip belt or hold dumbbell between feet.
- **Substitutes**: Decline Bench Press, High-to-Low Cable Fly, Decline Push-Up
- **Football**: Always safe (upper body; shoulder soreness from dips does not impair lower body match performance)

#### 14. Landmine Press
- **Primary**: Pectoralis major (clavicular head), Anterior deltoid
- **Secondary**: Triceps brachii, Serratus anterior, Core
- **Equipment**: Barbell + Landmine attachment (or corner)
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Grip end of barbell with both hands or single-arm. Press upward and forward following the arc. Core braced throughout. Great shoulder-friendly pressing alternative.
- **Substitutes**: Incline Dumbbell Press, Machine Chest Press, Cable Fly (Low-to-High)
- **Football**: Always safe (shoulder friendly)

#### 15. Floor Press
- **Primary**: Pectoralis major (mid-range), Triceps brachii
- **Secondary**: Anterior deltoid
- **Equipment**: Barbell or Dumbbells
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 4x6, 180s rest
- **Increment**: 2.5kg
- **Cues**: Lie on floor (no bench). Range of motion ends when triceps touch floor -- this removes the bottom stretch position. Good for lockout strength and shoulder-impaired lifters. Pause briefly on floor to eliminate bounce.
- **Substitutes**: Barbell Bench Press, Close-Grip Bench Press, Board Press
- **Football**: Always safe (upper body)

#### 16. Svend Press
- **Primary**: Pectoralis major (sternal head, peak contraction emphasis)
- **Secondary**: Anterior deltoid
- **Equipment**: Weight plate (single)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x15, 60s rest
- **Increment**: N/A (use heavier plate)
- **Cues**: Hold a plate between palms at chest height. Squeeze palms together hard. Press plate forward to arm's length while maintaining the squeeze. Return to chest. Light weight, high reps, maximum squeeze. Great finisher.
- **Substitutes**: Cable Crossover, Pec Deck, Plate Squeeze Press
- **Football**: Always safe

---

### BACK (16 exercises)

#### 17. Barbell Bent-Over Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii, Erector spinae
- **Equipment**: Barbell
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 4x8, 150s rest
- **Increment**: 2.5kg
- **Cues**: Hinge at hips to ~45 degree torso angle. Brace core hard. Pull bar to lower ribcage. Elbows drive back past torso. Squeeze shoulder blades at top for 1 second. Do not use excessive body English (momentum). Lower under control.
- **Substitutes**: Dumbbell Row, Seated Cable Row, Machine Row
- **Football**: Not on T-1 (lower back fatigue)

#### 18. Pendlay Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle/Lower trapezius
- **Secondary**: Posterior deltoid, Biceps brachii, Erector spinae
- **Equipment**: Barbell + Plates (bar rests on floor)
- **Difficulty**: Advanced
- **Pattern**: Pull
- **Default**: 4x5, 180s rest
- **Increment**: 2.5kg
- **Cues**: Torso parallel to floor (stricter than bent-over row). Bar starts on floor each rep -- dead stop. Explosive pull to lower chest. Release tension at bottom. Each rep is independent. Demands strong hip hinge position.
- **Substitutes**: Barbell Bent-Over Row, T-Bar Row, Seal Row
- **Football**: Not on T-0 or T-1

#### 19. Dumbbell Row (Single Arm)
- **Primary**: Latissimus dorsi, Rhomboids
- **Secondary**: Posterior deltoid, Biceps brachii, Core (anti-rotation)
- **Equipment**: Dumbbell + Flat bench
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x10, 120s rest (per side)
- **Increment**: 2kg
- **Cues**: One hand and knee on bench for support. Pull dumbbell to hip (not shoulder). Elbow drives past torso. Full stretch at bottom -- let scapula protract. Squeeze at top -- retract scapula. Do not rotate torso excessively.
- **Substitutes**: Seated Cable Row, Machine Row, Barbell Bent-Over Row
- **Football**: Always safe

#### 20. Seated Cable Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii
- **Equipment**: Cable machine + Seated row station + V-bar handle
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Sit upright, slight lean back (10-15 degrees). Pull handle to navel. Squeeze shoulder blades hard at peak contraction. Control the eccentric -- full stretch forward without rounding lower back. Do not use momentum.
- **Substitutes**: Dumbbell Row, Machine Row, Barbell Bent-Over Row
- **Football**: Always safe

#### 21. Lat Pulldown (Wide Grip)
- **Primary**: Latissimus dorsi (emphasis on width)
- **Secondary**: Biceps brachii, Lower trapezius, Rhomboids
- **Equipment**: Cable machine + Lat pulldown station + Wide bar
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Grip just outside shoulder width. Pull bar to upper chest (not behind neck -- behind-neck pulldowns are a shoulder injury waiting to happen). Lean back slightly (15-20 degrees). Initiate with scapulae depression. Full stretch at top.
- **Substitutes**: Pull-Up, Lat Pulldown (Close Grip), Machine Pulldown
- **Football**: Always safe

#### 22. Lat Pulldown (Close/Neutral Grip)
- **Primary**: Latissimus dorsi (emphasis on thickness)
- **Secondary**: Biceps brachii, Brachialis, Rhomboids
- **Equipment**: Cable machine + Lat pulldown station + V-bar or neutral grip handle
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Neutral grip (palms facing each other). Pull handle to upper chest. Elbows drive down and back. Close grip emphasizes lat stretch and contraction over width.
- **Substitutes**: Chin-Up, Lat Pulldown (Wide), Straight-Arm Pulldown
- **Football**: Always safe

#### 23. Pull-Up
- **Primary**: Latissimus dorsi, Lower trapezius, Rhomboids
- **Secondary**: Biceps brachii, Brachialis, Posterior deltoid, Core
- **Equipment**: Pull-up bar
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 3x8, 150s rest
- **Increment**: +1 rep or +2.5kg (belt/vest)
- **Cues**: Pronated grip (overhand), slightly wider than shoulder width. Initiate by depressing scapulae (pull shoulder blades down and back). Pull until chin clears bar. Full dead hang at bottom -- no half reps. If unable to complete reps, use band assistance or negatives.
- **Substitutes**: Lat Pulldown (Wide), Assisted Pull-Up Machine, Band-Assisted Pull-Up
- **Football**: Always safe

#### 24. Chin-Up
- **Primary**: Latissimus dorsi, Biceps brachii
- **Secondary**: Brachialis, Rhomboids, Lower trapezius, Core
- **Equipment**: Pull-up bar
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 3x8, 150s rest
- **Increment**: +1 rep or +2.5kg
- **Cues**: Supinated grip (underhand), shoulder-width. Stronger bicep involvement makes these easier than pull-ups for most people. Pull chin over bar. Full hang at bottom.
- **Substitutes**: Lat Pulldown (Close/Neutral), Assisted Chin-Up, Barbell Curl (bicep component only)
- **Football**: Always safe

#### 25. T-Bar Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii, Erector spinae
- **Equipment**: T-bar row station or Barbell + Landmine
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 3x10, 150s rest
- **Increment**: 2.5kg
- **Cues**: Straddle the bar. Close neutral grip. Row to chest. Keep torso at ~45 degrees. Do not jerk. Plates may limit range of motion -- use smaller plates for fuller ROM.
- **Substitutes**: Barbell Bent-Over Row, Dumbbell Row, Seal Row
- **Football**: Not on T-1

#### 26. Cable Face Pull
- **Primary**: Posterior deltoid, Rhomboids, Middle/Lower trapezius, External rotators
- **Secondary**: Biceps brachii
- **Equipment**: Cable machine + Rope attachment (high position)
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x15, 90s rest
- **Increment**: 2.5kg
- **Cues**: Pull rope to face level, separating hands at the end (external rotation component). Elbows high and wide. Squeeze shoulder blades. This is a corrective/prehab exercise as much as a builder -- do not ego lift. Keep it light, high reps.
- **Substitutes**: Band Face Pull, Reverse Fly (Dumbbell), Reverse Fly (Cable)
- **Football**: Always safe (shoulder health essential for football)

#### 27. Straight-Arm Pulldown
- **Primary**: Latissimus dorsi
- **Secondary**: Triceps brachii (long head), Teres major
- **Equipment**: Cable machine + Straight bar or rope (high position)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Stand facing cable, arms extended overhead. Pull bar down to thighs in an arc, keeping arms straight (slight elbow bend). Squeeze lats at bottom. Do not lean excessively or use body momentum. Great lat isolation.
- **Substitutes**: Dumbbell Pullover, Lat Pulldown (Wide), Pull-Up
- **Football**: Always safe

#### 28. Machine Row (Chest-Supported)
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii
- **Equipment**: Chest-supported row machine
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Chest supported eliminates lower back as a limiting factor. Focus purely on scapular retraction and lat engagement. Full stretch at bottom, hard squeeze at top.
- **Substitutes**: Dumbbell Row, Seated Cable Row, Seal Row
- **Football**: Always safe (zero lower back demand)

#### 29. Inverted Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii, Core
- **Equipment**: Barbell in rack or Smith machine (low height)
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x12, 90s rest
- **Increment**: +2 reps, or elevate feet for difficulty
- **Cues**: Lie under a bar set at hip height. Grip bar, body straight. Pull chest to bar. Scale difficulty by adjusting body angle (more horizontal = harder). Great regression from pull-ups.
- **Substitutes**: Pull-Up (progression), Lat Pulldown, Dumbbell Row
- **Football**: Always safe

#### 30. Barbell Deadlift (Conventional)
- **Primary**: Gluteus maximus, Hamstrings, Erector spinae
- **Secondary**: Latissimus dorsi, Trapezius, Quadriceps, Core, Forearms (grip)
- **Equipment**: Barbell + Plates
- **Difficulty**: Intermediate
- **Pattern**: Hinge
- **Default**: 3x5, 180s rest
- **Increment**: 2.5kg
- **Cues**: Bar over mid-foot. Hinge at hips, grip just outside knees. Chest up, lats engaged (bend the bar around your shins). Drive through the floor. Bar drags up shins and thighs. Lockout with glutes, not by hyperextending lower back. Do not round lower back at any point. If grip fails, use mixed grip or straps.
- **Substitutes**: Romanian Deadlift, Trap Bar Deadlift, Rack Pull
- **Football**: Not on T-0 or T-1 (massive CNS demand, hamstring/lower back fatigue)

#### 31. Seal Row
- **Primary**: Latissimus dorsi, Rhomboids, Middle trapezius
- **Secondary**: Posterior deltoid, Biceps brachii
- **Equipment**: Barbell or Dumbbells + Elevated bench (chest-supported prone)
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Lie face-down on an elevated bench (bench must be high enough for arms to fully extend). Row weight to bench from a dead stop. Eliminates all momentum and lower back involvement. Pure back isolation.
- **Substitutes**: Machine Row, Dumbbell Row, Chest-Supported T-Bar Row
- **Football**: Always safe

#### 32. Meadows Row
- **Primary**: Latissimus dorsi (lower), Teres major
- **Secondary**: Posterior deltoid, Biceps brachii, Obliques
- **Equipment**: Barbell + Landmine
- **Difficulty**: Advanced
- **Pattern**: Pull
- **Default**: 3x10, 120s rest (per side)
- **Increment**: 2.5kg
- **Cues**: Stand perpendicular to the barbell end. Staggered stance. Overhand grip on the fat end. Row in an arc toward hip. Unique angle hits lower lats that other rows miss. Named after John Meadows (RIP).
- **Substitutes**: Dumbbell Row, T-Bar Row, Single-Arm Cable Row
- **Football**: Always safe

---

### SHOULDERS (14 exercises)

#### 33. Barbell Overhead Press (Standing)
- **Primary**: Anterior deltoid, Medial deltoid
- **Secondary**: Triceps brachii, Upper trapezius, Serratus anterior, Core
- **Equipment**: Barbell + Rack
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 4x6, 150s rest
- **Increment**: 2.5kg (slowest progression of any barbell lift)
- **Cues**: Bar starts at front rack position (resting on front delts). Grip just outside shoulder width. Brace core. Press bar straight up -- move head BACK slightly as bar passes face, then forward under bar at lockout. Elbows slightly forward of bar at bottom. Full lockout overhead with bar over mid-foot.
- **Substitutes**: Dumbbell Overhead Press, Machine Shoulder Press, Landmine Press
- **Football**: Always safe (upper body pressing does not impair lower body match performance; core bracing demand is minimal at typical OHP loads)

#### 34. Dumbbell Overhead Press (Seated)
- **Primary**: Anterior deltoid, Medial deltoid
- **Secondary**: Triceps brachii, Upper trapezius
- **Equipment**: Dumbbells + Incline bench (set to ~85 degrees)
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x10, 150s rest
- **Increment**: 2kg
- **Cues**: Seated with back support. Start with dumbbells at shoulder height, palms forward. Press to lockout. Do not clank dumbbells at top. Lower under control to shoulder level. Seated reduces core demand and allows more focus on shoulders.
- **Substitutes**: Barbell Overhead Press, Arnold Press, Machine Shoulder Press
- **Football**: Always safe

#### 35. Arnold Press
- **Primary**: Anterior deltoid, Medial deltoid
- **Secondary**: Triceps brachii, Posterior deltoid (through rotation)
- **Equipment**: Dumbbells + Bench (seated)
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x10, 150s rest
- **Increment**: 2kg
- **Cues**: Start with dumbbells in front of chest, palms facing you (like top of a curl). As you press up, rotate palms outward. At the top, palms face forward. Reverse on the way down. The rotation through the press hits all three deltoid heads. Created by Arnold Schwarzenegger.
- **Substitutes**: Dumbbell Overhead Press, Barbell Overhead Press, Lu Raise
- **Football**: Always safe

#### 36. Lateral Raise (Dumbbell)
- **Primary**: Medial deltoid
- **Secondary**: Anterior deltoid, Upper trapezius
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x15, 90s rest
- **Increment**: 1kg per dumbbell (micro-loading critical -- lateral raises plateau fast)
- **Cues**: Slight forward lean (10-15 degrees). Lead with elbows, not hands. Raise to shoulder height -- not higher (upper trap takes over above 90 degrees). Slight bend in elbows. Pinky-up cue is a myth -- just focus on lifting with the elbow. Control the negative. Ego-lifting with lateral raises is the number one gym sin.
- **Substitutes**: Cable Lateral Raise, Machine Lateral Raise, Lu Raise
- **Football**: Always safe

#### 37. Lateral Raise (Cable)
- **Primary**: Medial deltoid
- **Secondary**: Anterior deltoid
- **Equipment**: Cable machine (low pulley)
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Stand side-on to the cable, handle in far hand. Cable runs behind body. Raise arm to shoulder height. Cable provides constant tension throughout the ROM (unlike dumbbells which lose tension at the bottom). Better strength curve for hypertrophy.
- **Substitutes**: Dumbbell Lateral Raise, Machine Lateral Raise, Band Lateral Raise
- **Football**: Always safe

#### 38. Front Raise (Dumbbell)
- **Primary**: Anterior deltoid
- **Secondary**: Upper pectoralis, Serratus anterior
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2kg
- **Cues**: Alternating or bilateral. Raise dumbbell(s) to shoulder height, arms nearly straight. Do not swing. Often unnecessary if doing enough pressing (bench press and OHP already hit anterior delts hard). Include only if anterior delt is a weak point.
- **Substitutes**: Cable Front Raise, Plate Front Raise, Barbell Front Raise
- **Football**: Always safe

#### 39. Reverse Fly (Dumbbell)
- **Primary**: Posterior deltoid, Rhomboids
- **Secondary**: Middle trapezius, Infraspinatus
- **Equipment**: Dumbbells + Incline bench (face down) or standing bent-over
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x15, 90s rest
- **Increment**: 1kg per dumbbell
- **Cues**: Bent over at hips or face-down on incline bench. Arms hang straight down. Raise dumbbells out to sides, squeezing rear delts and upper back. Keep slight elbow bend. Control the weight -- this is a finesse movement.
- **Substitutes**: Reverse Fly (Cable), Cable Face Pull, Band Pull-Apart
- **Football**: Always safe (posterior chain strengthening helps injury prevention)

#### 40. Reverse Fly (Cable)
- **Primary**: Posterior deltoid, Rhomboids
- **Secondary**: Middle trapezius
- **Equipment**: Cable machine (dual pulleys, mid-height)
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x15, 90s rest
- **Increment**: 2.5kg
- **Cues**: Cross cables (left hand holds right cable, right holds left). Pull apart to the sides. Constant tension advantage over dumbbells.
- **Substitutes**: Reverse Fly (Dumbbell), Face Pull, Band Pull-Apart
- **Football**: Always safe

#### 41. Machine Shoulder Press
- **Primary**: Anterior deltoid, Medial deltoid
- **Secondary**: Triceps brachii
- **Equipment**: Shoulder press machine
- **Difficulty**: Beginner
- **Pattern**: Push
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Adjust seat so handles are at shoulder height. Press to lockout. Good yellow-recovery-day swap for barbell OHP.
- **Substitutes**: Dumbbell Overhead Press, Barbell Overhead Press, Arnold Press
- **Football**: Always safe

#### 42. Upright Row (Dumbbell)
- **Primary**: Medial deltoid, Upper trapezius
- **Secondary**: Anterior deltoid, Biceps brachii
- **Equipment**: Dumbbells (preferred over barbell for shoulder safety)
- **Difficulty**: Intermediate
- **Pattern**: Pull
- **Default**: 3x10, 90s rest
- **Increment**: 2kg
- **Cues**: Use dumbbells, NOT barbell (barbell forces internal rotation under load -- impingement risk). Pull dumbbells up along torso, elbows leading. Stop when elbows reach shoulder height. Do not go higher. Keep weight light-moderate.
- **Substitutes**: Cable Lateral Raise, Dumbbell Lateral Raise, Lu Raise
- **Football**: Always safe

#### 43. Lu Raise
- **Primary**: Medial deltoid, Anterior deltoid
- **Secondary**: Upper trapezius
- **Equipment**: Dumbbells
- **Difficulty**: Advanced
- **Pattern**: Isolation
- **Default**: 3x10, 90s rest
- **Increment**: 1kg
- **Cues**: Named after Olympic weightlifter Lu Xiaojun. Start with dumbbells at sides. Raise to a Y-position overhead (arms at ~120 degrees from body). Full range of motion from hang to above head. Use light weight. Hits medial delt through its full range.
- **Substitutes**: Lateral Raise, Cable Lateral Raise, Arnold Press
- **Football**: Always safe

#### 44. Machine Lateral Raise
- **Primary**: Medial deltoid
- **Secondary**: Upper trapezius
- **Equipment**: Lateral raise machine
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Adjust pad to upper arm. Raise to shoulder height. Machine provides consistent resistance curve. Good for burnout sets.
- **Substitutes**: Dumbbell Lateral Raise, Cable Lateral Raise, Band Lateral Raise
- **Football**: Always safe

#### 45. Band Pull-Apart
- **Primary**: Posterior deltoid, Rhomboids, Middle trapezius
- **Secondary**: Infraspinatus, External rotators
- **Equipment**: Resistance band
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x20, 60s rest
- **Increment**: Use heavier band
- **Cues**: Hold band at shoulder width, arms extended forward at chest height. Pull band apart by squeezing shoulder blades together. Arms go straight out to sides. Excellent warm-up and corrective exercise. Should be in every push-day warm-up.
- **Substitutes**: Face Pull, Reverse Fly, Cable External Rotation
- **Football**: Always safe (essential prehab)

#### 46. Barbell Shrug
- **Primary**: Upper trapezius
- **Secondary**: Levator scapulae, Rhomboids
- **Equipment**: Barbell
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x12, 120s rest
- **Increment**: 5kg (traps respond to heavy loads)
- **Cues**: Grip just outside hip width. Stand tall. Shrug straight up -- do not roll shoulders (rolling is a myth and unnecessary). Hold at top for 1-2 seconds. Heavy weight is fine but control the negative.
- **Substitutes**: Dumbbell Shrug, Trap Bar Shrug, Cable Shrug
- **Football**: Always safe

---

### ARMS -- BICEPS (8 exercises)

#### 47. Barbell Curl
- **Primary**: Biceps brachii (both heads)
- **Secondary**: Brachialis, Brachioradialis, Forearm flexors
- **Equipment**: Barbell (straight or EZ curl)
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x10, 90s rest
- **Increment**: 2.5kg
- **Cues**: Shoulder-width grip. Elbows pinned at sides. Curl to full contraction (bar to front delts). Control the negative (2-3 second eccentric). No swinging -- if you have to swing, the weight is too heavy. EZ curl bar reduces wrist strain.
- **Substitutes**: Dumbbell Curl, Cable Curl, EZ Bar Curl
- **Football**: Always safe

#### 48. Dumbbell Curl (Standing)
- **Primary**: Biceps brachii
- **Secondary**: Brachialis, Brachioradialis
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x10, 90s rest
- **Increment**: 2kg
- **Cues**: Alternating or bilateral. Supinate wrist at the top (rotate pinky outward) for peak bicep contraction. Full extension at bottom -- none of this half-rep nonsense. Keep elbows slightly forward of torso.
- **Substitutes**: Barbell Curl, Cable Curl, Incline Dumbbell Curl
- **Football**: Always safe

#### 49. Hammer Curl
- **Primary**: Brachialis, Brachioradialis
- **Secondary**: Biceps brachii
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x10, 90s rest
- **Increment**: 2kg
- **Cues**: Neutral grip (palms facing each other throughout). Curl to shoulder. Emphasizes brachialis (underneath biceps) -- gives arm width and thickness. Also builds forearm size.
- **Substitutes**: Cross-Body Hammer Curl, Rope Cable Curl, Reverse Curl
- **Football**: Always safe

#### 50. Preacher Curl
- **Primary**: Biceps brachii (short head emphasis)
- **Secondary**: Brachialis
- **Equipment**: EZ curl bar or Dumbbells + Preacher bench
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x10, 90s rest
- **Increment**: 2.5kg (EZ bar) or 2kg (dumbbell)
- **Cues**: Upper arms flat on preacher pad. Curl to full contraction. DO NOT fully extend at the bottom under heavy load -- keep slight bend to protect elbow joint. The pad eliminates all cheating. Great for building the bicep peak.
- **Substitutes**: Concentration Curl, Spider Curl, Machine Preacher Curl
- **Football**: Always safe

#### 51. Cable Curl
- **Primary**: Biceps brachii
- **Secondary**: Brachialis
- **Equipment**: Cable machine + Straight bar or EZ bar (low position)
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Constant tension throughout ROM (unlike dumbbells). Stand with cable between legs or face cable. Curl to full contraction. Squeeze at top. Control eccentric.
- **Substitutes**: Barbell Curl, Dumbbell Curl, Band Curl
- **Football**: Always safe

#### 52. Concentration Curl
- **Primary**: Biceps brachii (peak emphasis)
- **Secondary**: Brachialis
- **Equipment**: Dumbbell + Bench (seated)
- **Difficulty**: Beginner
- **Pattern**: Pull (Isolation)
- **Default**: 3x12, 90s rest (per arm)
- **Increment**: 1kg
- **Cues**: Seated, elbow braced against inner thigh. Curl dumbbell to shoulder. Slow, controlled. The bracing eliminates all momentum -- pure isolation. The mind-muscle connection exercise for biceps.
- **Substitutes**: Preacher Curl, Spider Curl, Cable Curl (single arm)
- **Football**: Always safe

#### 53. Incline Dumbbell Curl
- **Primary**: Biceps brachii (long head -- stretched position)
- **Secondary**: Brachialis
- **Equipment**: Dumbbells + Incline bench (45-60 degrees)
- **Difficulty**: Intermediate
- **Pattern**: Pull (Isolation)
- **Default**: 3x10, 90s rest
- **Increment**: 1kg per dumbbell
- **Cues**: Sit on incline bench, arms hanging straight down behind torso. This puts the bicep long head in a stretched position -- the key stimulus for growth. Curl without bringing elbows forward. Use lighter weight than standing curls.
- **Substitutes**: Bayesian Cable Curl, Dumbbell Curl, Preacher Curl
- **Football**: Always safe

#### 54. Spider Curl
- **Primary**: Biceps brachii (short head)
- **Secondary**: Brachialis
- **Equipment**: EZ bar or Dumbbells + Incline bench (face down)
- **Difficulty**: Intermediate
- **Pattern**: Pull (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 2kg
- **Cues**: Lie face-down on incline bench, arms hanging straight down. Curl weight up. The bench eliminates all swinging. Maximum tension at the contracted (top) position -- opposite of incline curls. Pairs well with incline curls for complete bicep training.
- **Substitutes**: Preacher Curl, Concentration Curl, Machine Curl
- **Football**: Always safe

---

### ARMS -- TRICEPS (8 exercises)

#### 55. Tricep Pushdown (Cable -- Rope)
- **Primary**: Triceps brachii (lateral and medial heads)
- **Secondary**: Anconeus
- **Equipment**: Cable machine + Rope attachment (high position)
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Elbows pinned at sides. Push rope down and APART at the bottom (spreading the rope) for peak contraction. Do not lean over the weight. Upright torso. Control the eccentric -- do not let the weight yank your arms up.
- **Substitutes**: Tricep Pushdown (Straight Bar), Overhead Tricep Extension, Dip
- **Football**: Always safe

#### 56. Tricep Pushdown (Cable -- Straight Bar)
- **Primary**: Triceps brachii (all heads)
- **Secondary**: Anconeus
- **Equipment**: Cable machine + Straight bar (high position)
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Overhand grip, shoulder width. Press bar down to full lockout. Elbows stay pinned. Straight bar allows slightly heavier loads than rope.
- **Substitutes**: Rope Pushdown, Overhead Extension, Skull Crusher
- **Football**: Always safe

#### 57. Overhead Tricep Extension (Cable)
- **Primary**: Triceps brachii (long head -- stretched position)
- **Secondary**: Anconeus
- **Equipment**: Cable machine + Rope attachment (low position)
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Face away from cable. Rope behind head. Extend overhead. The overhead position stretches the long head (which crosses the shoulder joint) -- most important head for tricep size. Lean forward slightly at hips for stability.
- **Substitutes**: Dumbbell Overhead Extension, Skull Crusher, French Press
- **Football**: Always safe

#### 58. Skull Crusher (EZ Bar)
- **Primary**: Triceps brachii (all heads, emphasis on long head)
- **Secondary**: Anconeus
- **Equipment**: EZ curl bar + Flat bench
- **Difficulty**: Intermediate
- **Pattern**: Push (Isolation)
- **Default**: 3x10, 120s rest
- **Increment**: 2.5kg
- **Cues**: Lie on bench, arms extended, EZ bar above forehead. Lower bar by bending ONLY at elbows, bringing bar to forehead or just behind head. Press back up. Do not flare elbows. The name is a warning: control the weight. Use a spotter for heavy sets.
- **Substitutes**: Overhead Tricep Extension, Tricep Pushdown, Close-Grip Bench Press
- **Football**: Always safe

#### 59. Close-Grip Bench Press
- **Primary**: Triceps brachii, Pectoralis major (minor)
- **Secondary**: Anterior deltoid
- **Equipment**: Barbell + Flat bench + Rack
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x8, 150s rest
- **Increment**: 2.5kg
- **Cues**: Grip shoulder-width or slightly narrower (NOT hands-touching -- that strains wrists). Lower bar to lower chest. Press with emphasis on tricep lockout. Elbows stay closer to body than regular bench.
- **Substitutes**: Skull Crusher, Dip (tricep-focused), Diamond Push-Up
- **Football**: Always safe (upper body)

#### 60. Dumbbell Tricep Kickback
- **Primary**: Triceps brachii (lateral head)
- **Secondary**: Posterior deltoid (stabilizer)
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 3x12, 90s rest
- **Increment**: 1kg per dumbbell
- **Cues**: Hinge at hips, upper arm parallel to floor. Extend forearm back until arm is straight. Squeeze at peak contraction. Do not swing. Light weight, high reps. Often mocked but effective when done properly with strict form.
- **Substitutes**: Rope Pushdown, Single-Arm Cable Pushdown, Overhead Extension
- **Football**: Always safe

#### 61. Dip (Tricep-Focused)
- **Primary**: Triceps brachii, Pectoralis major (lower)
- **Secondary**: Anterior deltoid
- **Equipment**: Dip bars / Parallel bars
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x10, 120s rest
- **Increment**: +2.5kg (belt) or +1 rep
- **Cues**: Torso UPRIGHT (leaning forward shifts emphasis to chest). Lower until upper arms parallel to floor. Press to full lockout. Elbows point backward, not out. Weighted: dip belt or hold dumbbell between feet.
- **Substitutes**: Close-Grip Bench Press, Skull Crusher, Diamond Push-Up
- **Football**: Always safe (upper body)

#### 62. Diamond Push-Up
- **Primary**: Triceps brachii, Pectoralis major (inner)
- **Secondary**: Anterior deltoid, Core
- **Equipment**: Bodyweight (no equipment)
- **Difficulty**: Intermediate
- **Pattern**: Push
- **Default**: 3x12, 90s rest
- **Increment**: +2 reps
- **Cues**: Hands together under chest, index fingers and thumbs forming a diamond shape. Lower chest to hands. Press up. Harder than regular push-ups due to narrow base and tricep emphasis.
- **Substitutes**: Close-Grip Bench Press, Dip, Tricep Pushdown
- **Football**: Always safe

---

### LEGS -- QUADRICEPS (10 exercises)

#### 63. Barbell Back Squat
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Erector spinae, Core, Adductors
- **Equipment**: Barbell + Squat rack
- **Difficulty**: Intermediate
- **Pattern**: Squat
- **Default**: 4x6, 210s rest
- **Increment**: 2.5kg
- **Cues**: Bar on upper traps (high bar) or rear delts (low bar). Feet shoulder-width or slightly wider. Toes slightly out (15-30 degrees). Brace core (big breath, push abs out). Break at hips and knees simultaneously. Descend until hip crease is below knee (parallel minimum). Knees track over toes. Drive through full foot (not just heels). Do not let knees cave inward (cue: push knees out).
- **Substitutes**: Leg Press, Hack Squat, Goblet Squat
- **Football**: Not on T-0 or T-1 (massive leg fatigue, CNS demand). Schedule 48h+ before match.

#### 64. Barbell Front Squat
- **Primary**: Quadriceps (emphasis), Gluteus maximus
- **Secondary**: Core (heavy demand), Erector spinae, Upper back
- **Equipment**: Barbell + Squat rack
- **Difficulty**: Advanced
- **Pattern**: Squat
- **Default**: 3x8, 180s rest
- **Increment**: 2.5kg
- **Cues**: Bar rests on front delts in clean grip (preferred) or cross-arm grip. Elbows HIGH -- if elbows drop, you lose the bar forward. More upright torso than back squat. Greater quad emphasis, less lower back stress. Depth: at least parallel. Wrist flexibility often the limiting factor -- work on it.
- **Substitutes**: Barbell Back Squat, Goblet Squat, Leg Press (feet low)
- **Football**: Not on T-0 or T-1

#### 65. Leg Press
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Adductors
- **Equipment**: Leg press machine (45-degree or horizontal)
- **Difficulty**: Beginner
- **Pattern**: Squat
- **Default**: 3x10, 150s rest
- **Increment**: 5kg (per side on 45-degree) or 2.5kg (stack machine)
- **Cues**: Foot placement determines emphasis: high and wide = more glutes/hamstrings, low and narrow = more quads. Press through full foot. Lower until knees approach 90 degrees. Do NOT let lower back round off the pad at the bottom. Do not lock knees aggressively at the top.
- **Substitutes**: Barbell Back Squat, Hack Squat, Bulgarian Split Squat
- **Football**: Always safe at moderate weight. Reduce load on T-1.

#### 66. Hack Squat
- **Primary**: Quadriceps
- **Secondary**: Gluteus maximus, Adductors
- **Equipment**: Hack squat machine
- **Difficulty**: Intermediate
- **Pattern**: Squat
- **Default**: 3x10, 150s rest
- **Increment**: 5kg per side
- **Cues**: Back against pad, feet shoulder-width on platform. Lower until thighs at least parallel. The machine guides the path -- focus on depth and quad drive. Lower foot placement = more quad isolation.
- **Substitutes**: Leg Press, Barbell Back Squat, Pendulum Squat
- **Football**: Not on T-1 at heavy loads

#### 67. Leg Extension
- **Primary**: Quadriceps (rectus femoris emphasis)
- **Secondary**: None (pure isolation)
- **Equipment**: Leg extension machine
- **Difficulty**: Beginner
- **Pattern**: Isolation
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Adjust pad to sit on lower shin (above ankles). Extend legs fully. Squeeze at top for 1-2 seconds. Control the eccentric. Does NOT damage knees when done with controlled form and appropriate weight (the old myth is dead -- per Schoenfeld 2020). Great for quad isolation and rehabilitation.
- **Substitutes**: Sissy Squat, Wall Sit, Single-Leg Extension
- **Football**: Always safe (light to moderate weight acceptable even on T-1)

#### 68. Bulgarian Split Squat
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Adductors, Core (balance)
- **Equipment**: Dumbbells + Bench (rear foot elevated)
- **Difficulty**: Intermediate
- **Pattern**: Squat
- **Default**: 3x10, 120s rest (per leg)
- **Increment**: 2kg per dumbbell
- **Cues**: Rear foot on bench, laces down. Front foot 2-3 feet in front of bench. Lower until rear knee nearly touches floor. Front knee tracks over toes. Torso slightly forward. Unilateral -- exposes and corrects strength imbalances.
- **Substitutes**: Walking Lunge, Leg Press (single leg), Step-Up
- **Football**: Not on T-1 (heavy single-leg work = DOMS risk)

#### 69. Walking Lunge
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Adductors, Core
- **Equipment**: Dumbbells or Barbell
- **Difficulty**: Intermediate
- **Pattern**: Squat
- **Default**: 3x12 steps, 120s rest
- **Increment**: 2kg per dumbbell
- **Cues**: Long stride. Lower until both knees are at ~90 degrees. Push off front foot to step forward. Maintain upright torso. Walking adds a dynamic stability component. Excellent for football players -- mimics deceleration patterns.
- **Substitutes**: Bulgarian Split Squat, Reverse Lunge, Step-Up
- **Football**: Not on T-1 (DOMS risk in quads and glutes)

#### 70. Goblet Squat
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Core, Upper back (isometric hold)
- **Equipment**: Dumbbell or Kettlebell
- **Difficulty**: Beginner
- **Pattern**: Squat
- **Default**: 3x12, 90s rest
- **Increment**: 2kg (dumbbell) or 4kg (kettlebell)
- **Cues**: Hold weight at chest level, elbows inside knees at bottom. Natural squat pattern -- elbows push knees out. Great for beginners learning squat mechanics. Also a great yellow-recovery-day substitute for barbell squat.
- **Substitutes**: Barbell Back Squat, Leg Press, Air Squat
- **Football**: Always safe

#### 71. Sissy Squat
- **Primary**: Quadriceps (rectus femoris -- extreme stretch)
- **Secondary**: Hip flexors
- **Equipment**: Sissy squat stand or bodyweight (holding a post)
- **Difficulty**: Advanced
- **Pattern**: Squat
- **Default**: 3x12, 90s rest
- **Increment**: +2 reps or add light dumbbell
- **Cues**: Lean torso back while bending knees forward. Heels rise. Maximum quad stretch at the bottom. Looks bizarre, feels brutal. Do not go heavy -- bodyweight or light load only. Not for anyone with knee issues.
- **Substitutes**: Leg Extension, Spanish Squat (banded), Wall Sit
- **Football**: Always safe (bodyweight)

#### 72. Step-Up (Dumbbell)
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Core (balance)
- **Equipment**: Dumbbells + Elevated platform / Bench
- **Difficulty**: Beginner
- **Pattern**: Squat
- **Default**: 3x10, 120s rest (per leg)
- **Increment**: 2kg per dumbbell
- **Cues**: Platform at knee height or slightly below. Step up with one foot, drive through the heel. Fully extend at top. Step down controlled. Do NOT push off the back foot -- the working leg does all the work.
- **Substitutes**: Bulgarian Split Squat, Walking Lunge, Leg Press (single leg)
- **Football**: Always safe at moderate weight

---

### LEGS -- HAMSTRINGS & GLUTES (10 exercises)

#### 73. Romanian Deadlift (Barbell)
- **Primary**: Hamstrings, Gluteus maximus
- **Secondary**: Erector spinae, Adductors
- **Equipment**: Barbell
- **Difficulty**: Intermediate
- **Pattern**: Hinge
- **Default**: 3x10, 150s rest
- **Increment**: 2.5kg
- **Cues**: Bar starts from standing (NOT from the floor -- that is a conventional deadlift). Soft knee bend (15-20 degree bend, fixed throughout). Hinge at hips, pushing butt BACK. Bar stays close to legs (drags down thighs). Lower until hamstring stretch maxes out (usually mid-shin). Drive hips forward to stand. Do NOT round lower back. The hamstring stretch is the primary cue.
- **Substitutes**: Romanian Deadlift (Dumbbell), Good Morning, Stiff-Leg Deadlift
- **Football**: Not on T-1 (hamstring loading -- the most common football injury)

#### 74. Romanian Deadlift (Dumbbell)
- **Primary**: Hamstrings, Gluteus maximus
- **Secondary**: Erector spinae, Adductors
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Hinge
- **Default**: 3x10, 150s rest
- **Increment**: 2kg per dumbbell
- **Cues**: Same mechanics as barbell RDL but with dumbbells at sides. Slightly more natural arm path. Better for beginners learning the hip hinge pattern. Can also be done single-leg (see below).
- **Substitutes**: Barbell RDL, Single-Leg RDL, Lying Leg Curl
- **Football**: Not on T-1

#### 75. Single-Leg Romanian Deadlift
- **Primary**: Hamstrings, Gluteus maximus, Gluteus medius
- **Secondary**: Core (anti-rotation), Erector spinae
- **Equipment**: Dumbbell or Kettlebell (single)
- **Difficulty**: Intermediate
- **Pattern**: Hinge
- **Default**: 3x8, 120s rest (per leg)
- **Increment**: 2kg
- **Cues**: Stand on one leg, weight in opposite hand. Hinge forward as rear leg rises behind you. Body forms a T at the bottom. Do not rotate hips -- square to the floor. Free leg, torso, and arm form a straight line. Excellent for balance, glute medius activation, and hamstring health. Essential for football injury prevention.
- **Substitutes**: Romanian Deadlift (Dumbbell), Nordic Curl, Lying Leg Curl
- **Football**: Always safe (rehab-level loading)

#### 76. Lying Leg Curl
- **Primary**: Hamstrings (biceps femoris, semitendinosus, semimembranosus)
- **Secondary**: Gastrocnemius
- **Equipment**: Lying leg curl machine
- **Difficulty**: Beginner
- **Pattern**: Isolation (Hinge)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Pad above Achilles tendon (not on calf muscle). Curl heels toward glutes. Squeeze at the top. Control the eccentric -- no slamming the weight stack. Do not lift hips off the pad. Plantarflex (point toes) to reduce calf involvement and isolate hamstrings.
- **Substitutes**: Seated Leg Curl, Nordic Curl, Swiss Ball Leg Curl
- **Football**: Always safe (even on T-1 at light to moderate weight -- good for hamstring maintenance)

#### 77. Seated Leg Curl
- **Primary**: Hamstrings
- **Secondary**: Gastrocnemius
- **Equipment**: Seated leg curl machine
- **Difficulty**: Beginner
- **Pattern**: Isolation (Hinge)
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Adjust back pad and shin pad. Curl heels under the seat. Seated position stretches hamstrings at the hip, providing a different stimulus than lying curl. Both should be used. Squeeze at full contraction.
- **Substitutes**: Lying Leg Curl, Nordic Curl, Swiss Ball Leg Curl
- **Football**: Always safe

#### 78. Hip Thrust (Barbell)
- **Primary**: Gluteus maximus (peak contraction emphasis)
- **Secondary**: Hamstrings, Adductors, Core
- **Equipment**: Barbell + Bench + Hip thrust pad
- **Difficulty**: Intermediate
- **Pattern**: Hinge
- **Default**: 3x10, 120s rest
- **Increment**: 5kg (glutes respond to heavier loads)
- **Cues**: Upper back on bench, feet flat on floor. Bar across hip crease with pad. Drive through heels. Full hip extension at top -- squeeze glutes HARD for 1-2 seconds. Chin tucked (do not hyperextend neck). Ribs stay down. Posterior pelvic tilt at top. The best glute isolation exercise, period.
- **Substitutes**: Glute Bridge, Cable Pull-Through, Machine Hip Thrust
- **Football**: Not on T-1 at heavy loads

#### 79. Glute Bridge
- **Primary**: Gluteus maximus
- **Secondary**: Hamstrings, Core
- **Equipment**: Bodyweight (or dumbbell/plate on hips)
- **Difficulty**: Beginner
- **Pattern**: Hinge
- **Default**: 3x15, 60s rest
- **Increment**: +5 reps or add weight
- **Cues**: Lie on floor, knees bent, feet flat. Drive hips up. Squeeze glutes at top. Lighter regression of hip thrust. Good for warm-ups and activation. Single-leg variant is significantly harder.
- **Substitutes**: Hip Thrust, Cable Pull-Through, Frog Pump
- **Football**: Always safe (great activation before matches)

#### 80. Good Morning
- **Primary**: Hamstrings, Erector spinae
- **Secondary**: Gluteus maximus
- **Equipment**: Barbell (on upper back like a squat)
- **Difficulty**: Advanced
- **Pattern**: Hinge
- **Default**: 3x8, 150s rest
- **Increment**: 2.5kg (go conservative)
- **Cues**: Bar on upper back. Soft knees. Hinge at hips, pushing butt back. Torso descends toward parallel. Feel the hamstring stretch. Stand back up by driving hips forward. This is NOT a squat. Keep weight moderate -- this movement loaded improperly can be dangerous. Great for posterior chain development.
- **Substitutes**: Romanian Deadlift, Seated Good Morning, Reverse Hyper
- **Football**: Not on T-0 or T-1

#### 81. Nordic Curl
- **Primary**: Hamstrings (eccentric emphasis -- injury prevention)
- **Secondary**: Gastrocnemius
- **Equipment**: Bodyweight + Nordic curl station or partner holding feet
- **Difficulty**: Advanced
- **Pattern**: Hinge
- **Default**: 3x5, 120s rest
- **Increment**: +1 rep (this exercise is brutally hard)
- **Cues**: Kneel on pad, feet anchored. Lower torso forward under control (eccentric phase). Resist gravity for as long as possible. When you cannot hold anymore, catch yourself with hands in push-up position. Push back up and repeat. This is THE exercise for hamstring injury prevention -- research by Mjolsnes (2004) showed 65% reduction in hamstring injuries in football players doing Nordics. Non-negotiable for any footballer.
- **Substitutes**: Slider Leg Curl, Swiss Ball Leg Curl, Eccentric RDL
- **Football**: Always safe (essential prehab -- should be done year-round)

#### 82. Cable Pull-Through
- **Primary**: Gluteus maximus, Hamstrings
- **Secondary**: Erector spinae
- **Equipment**: Cable machine (low position) + Rope attachment
- **Difficulty**: Beginner
- **Pattern**: Hinge
- **Default**: 3x12, 90s rest
- **Increment**: 2.5kg
- **Cues**: Face away from cable, rope between legs. Hinge at hips. Drive hips forward to stand tall, squeezing glutes. Great teaching tool for the hip hinge pattern. No spinal loading.
- **Substitutes**: Hip Thrust, Glute Bridge, Romanian Deadlift
- **Football**: Always safe

---

### LEGS -- CALVES (3 exercises)

#### 83. Standing Calf Raise (Machine)
- **Primary**: Gastrocnemius
- **Secondary**: Soleus
- **Equipment**: Standing calf raise machine
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 4x15, 60s rest
- **Increment**: 5kg (calves need high volume and frequency)
- **Cues**: Balls of feet on platform, heels hanging off. Rise to full plantar flexion. Pause 1 second at top. Lower past the platform level for a full stretch (2-3 second eccentric). Calves respond to high reps, slow eccentrics, and full ROM. Straight legs emphasize gastrocnemius.
- **Substitutes**: Dumbbell Calf Raise, Smith Machine Calf Raise, Single-Leg Calf Raise
- **Football**: Always safe

#### 84. Seated Calf Raise
- **Primary**: Soleus
- **Secondary**: Gastrocnemius (minimal -- knee is bent)
- **Equipment**: Seated calf raise machine
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 4x15, 60s rest
- **Increment**: 5kg
- **Cues**: Bent knees take gastrocnemius out of the equation (it crosses the knee joint). Soleus is pure slow-twitch and responds to high reps (15-25). Full ROM: deep stretch at bottom, full contraction at top.
- **Substitutes**: Seated Dumbbell Calf Raise, Leg Press Calf Raise, Soleus Raise
- **Football**: Always safe

#### 85. Single-Leg Calf Raise (Bodyweight)
- **Primary**: Gastrocnemius, Soleus
- **Secondary**: Ankle stabilizers, Tibialis anterior (eccentric)
- **Equipment**: Bodyweight + Step/Platform
- **Difficulty**: Beginner
- **Pattern**: Push (Isolation)
- **Default**: 3x15, 60s rest (per leg)
- **Increment**: +2 reps or hold dumbbell
- **Cues**: Stand on one foot on a step edge. Full range of motion. 2-second hold at top. 3-second eccentric to full stretch. Unilateral work exposes calf imbalances. Great for runners and footballers.
- **Substitutes**: Standing Calf Raise, Seated Calf Raise, Jump Rope
- **Football**: Always safe (ankle stability is critical)

---

### CORE (12 exercises)

#### 86. Plank
- **Primary**: Transverse abdominis, Rectus abdominis (isometric)
- **Secondary**: Obliques, Erector spinae, Deltoids (isometric), Quadriceps (isometric)
- **Equipment**: Bodyweight
- **Difficulty**: Beginner
- **Pattern**: Core (Isometric)
- **Default**: 3x45s, 60s rest
- **Increment**: +15 seconds per progression
- **Cues**: Forearms on floor, elbows under shoulders. Body in a straight line. Squeeze glutes, brace core (push belly button toward spine). Do not sag hips or pike up. If you can hold for 2+ minutes, switch to harder progressions (weighted, RKC plank, long-lever plank).
- **Substitutes**: Dead Bug, Ab Wheel Rollout, Stir-the-Pot
- **Football**: Always safe

#### 87. Ab Wheel Rollout
- **Primary**: Rectus abdominis, Transverse abdominis
- **Secondary**: Latissimus dorsi, Serratus anterior, Hip flexors
- **Equipment**: Ab wheel (or barbell with round plates)
- **Difficulty**: Intermediate
- **Pattern**: Core
- **Default**: 3x10, 90s rest
- **Increment**: +2 reps or increase ROM (knees to standing)
- **Cues**: From knees: Roll out as far as possible while maintaining neutral spine. Do NOT let lower back arch (hyperextend). Pull back by contracting abs, not by piking at hips. Standing rollouts are an advanced progression. One of the most effective core exercises per EMG studies (Escamilla 2006).
- **Substitutes**: Plank, Fallout (cable/TRX), Body Saw
- **Football**: Always safe

#### 88. Hanging Leg Raise
- **Primary**: Rectus abdominis (lower emphasis), Hip flexors
- **Secondary**: Obliques, Forearms (grip)
- **Equipment**: Pull-up bar or Captain's Chair
- **Difficulty**: Intermediate
- **Pattern**: Core
- **Default**: 3x12, 90s rest
- **Increment**: +2 reps, or add ankle weight, or progress to toes-to-bar
- **Cues**: Hang from bar. Raise legs to at least 90 degrees. For maximum ab activation, continue curling pelvis upward (posterior pelvic tilt) after legs reach 90 degrees -- this is where rectus abdominis actually works. Legs straight = harder. Bent knees = easier. Avoid swinging.
- **Substitutes**: Lying Leg Raise, Reverse Crunch, Captain's Chair Leg Raise
- **Football**: Always safe

#### 89. Cable Woodchop
- **Primary**: Obliques (internal and external)
- **Secondary**: Transverse abdominis, Rectus abdominis, Shoulders (stabilizer)
- **Equipment**: Cable machine + Single handle (high or low position)
- **Difficulty**: Beginner
- **Pattern**: Core (Rotation)
- **Default**: 3x12, 90s rest (per side)
- **Increment**: 2.5kg
- **Cues**: Stand side-on to cable. Rotate torso from high-to-low (chop) or low-to-high (lift). Arms are a lever -- the rotation comes from the CORE, not the arms. Anti-rotation and rotation are both critical for football (kicking, tackling, turning).
- **Substitutes**: Pallof Press, Russian Twist, Medicine Ball Rotational Throw
- **Football**: Always safe (rotational power is game-critical)

#### 90. Russian Twist
- **Primary**: Obliques
- **Secondary**: Rectus abdominis, Hip flexors
- **Equipment**: Bodyweight, Dumbbell, or Medicine Ball
- **Difficulty**: Beginner
- **Pattern**: Core (Rotation)
- **Default**: 3x20 (10 per side), 60s rest
- **Increment**: +4 reps or add/increase weight
- **Cues**: Seated, lean back 45 degrees, feet off floor (or on floor for easier version). Rotate side to side, touching weight to floor on each side. Keep chest tall -- do not just move arms. Twist from the ribcage.
- **Substitutes**: Cable Woodchop, Bicycle Crunch, Medicine Ball Rotational Throw
- **Football**: Always safe

#### 91. Dead Bug
- **Primary**: Transverse abdominis, Rectus abdominis
- **Secondary**: Hip flexors, Obliques (anti-rotation)
- **Equipment**: Bodyweight
- **Difficulty**: Beginner
- **Pattern**: Core
- **Default**: 3x10 (per side), 60s rest
- **Increment**: +2 reps per side, or add ankle/wrist weights
- **Cues**: Lie on back, arms up, knees at 90 degrees. Extend opposite arm and leg simultaneously while PRESSING lower back into the floor. The goal is ZERO lower back arching. If your back arches, you have lost tension and the rep does not count. The most underrated core exercise. Physical therapists love it for a reason.
- **Substitutes**: Plank, Bird Dog, Pallof Press
- **Football**: Always safe (fundamental stability pattern)

#### 92. Pallof Press
- **Primary**: Transverse abdominis, Obliques (anti-rotation)
- **Secondary**: Rectus abdominis, Glutes (stabilizer)
- **Equipment**: Cable machine + Single handle (chest height) or Resistance band
- **Difficulty**: Beginner
- **Pattern**: Core (Anti-rotation)
- **Default**: 3x10, 60s rest (per side)
- **Increment**: 2.5kg or heavier band
- **Cues**: Stand side-on to cable. Hold handle at chest. Press arms straight out. The cable tries to rotate you -- RESIST. Hold extended position for 2 seconds. Return to chest. Pure anti-rotation. Essential for spine health and athletic performance.
- **Substitutes**: Dead Bug, Cable Woodchop, Single-Arm Farmer Walk
- **Football**: Always safe

#### 93. Bicycle Crunch
- **Primary**: Rectus abdominis, Obliques
- **Secondary**: Hip flexors
- **Equipment**: Bodyweight
- **Difficulty**: Beginner
- **Pattern**: Core
- **Default**: 3x20 (10 per side), 60s rest
- **Increment**: +4 reps
- **Cues**: Lie on back. Alternate bringing elbow to opposite knee. Extend opposite leg. Slow and controlled -- not a speed contest. If you are going fast, you are doing it wrong.
- **Substitutes**: Russian Twist, Cable Woodchop, V-Up
- **Football**: Always safe

#### 94. Farmer Walk / Carry
- **Primary**: Core (anti-lateral flexion), Trapezius, Forearms (grip)
- **Secondary**: Quadriceps, Glutes, Calves (locomotion)
- **Equipment**: Heavy dumbbells, Kettlebells, or Farmer walk handles
- **Difficulty**: Beginner
- **Pattern**: Carry
- **Default**: 3x40m, 90s rest
- **Increment**: +2kg per hand or +10m distance
- **Cues**: Pick up heavy weights. Walk tall. Shoulders back and down. Core braced. Do not lean to one side. Walk with purpose. The simplest exercise that trains everything. Grip, core, posture, conditioning. Every program should include carries.
- **Substitutes**: Suitcase Carry (single-arm), Trap Bar Carry, Waiter Walk
- **Football**: Always safe

#### 95. Suitcase Carry
- **Primary**: Obliques (anti-lateral flexion), Core
- **Secondary**: Trapezius, Forearms, Glutes (hip hike stability)
- **Equipment**: Single heavy dumbbell or kettlebell
- **Difficulty**: Intermediate
- **Pattern**: Carry
- **Default**: 3x40m per side, 90s rest
- **Increment**: +2kg or +10m
- **Cues**: Carry a heavy weight on one side. Walk without leaning. Your obliques and hip stabilizers fight the lateral pull. Switch sides each set. More sport-specific than bilateral farmer walks -- football is a single-leg sport.
- **Substitutes**: Farmer Walk, Cable Woodchop, Pallof Press
- **Football**: Always safe

#### 96. Hanging Knee Raise
- **Primary**: Rectus abdominis, Hip flexors
- **Secondary**: Obliques, Forearms (grip)
- **Equipment**: Pull-up bar
- **Difficulty**: Beginner
- **Pattern**: Core
- **Default**: 3x15, 90s rest
- **Increment**: +2 reps, or progress to straight-leg raise
- **Cues**: Hang from bar. Raise bent knees to chest. Curl pelvis upward at top for ab activation. Regression from hanging leg raise. Avoid swinging.
- **Substitutes**: Hanging Leg Raise, Lying Knee Raise, Captain's Chair Knee Raise
- **Football**: Always safe

#### 97. V-Up
- **Primary**: Rectus abdominis (full range)
- **Secondary**: Hip flexors, Obliques
- **Equipment**: Bodyweight
- **Difficulty**: Intermediate
- **Pattern**: Core
- **Default**: 3x12, 60s rest
- **Increment**: +2 reps or hold weight in hands
- **Cues**: Lie flat. Simultaneously raise legs and torso, reaching hands toward toes. Body forms a V at the top. Lower with control. Hard on hip flexors -- if they dominate, do Dead Bugs instead.
- **Substitutes**: Bicycle Crunch, Hanging Leg Raise, Tuck-Up
- **Football**: Always safe

---

### CARDIO (10 exercises)

#### 98. Outdoor Run (Easy/Zone 2)
- **Primary**: Cardiovascular system, Slow-twitch muscle fibers
- **Secondary**: Quadriceps, Hamstrings, Calves, Core
- **Equipment**: None (running shoes)
- **Difficulty**: Beginner
- **Pattern**: Cardio (Aerobic)
- **Default**: 30-45 min at conversational pace (Zone 2 HR)
- **Increment**: +5 min per week or +0.5 km
- **Cues**: Should be able to hold a conversation. Nasal breathing preferred. Do not chase pace -- chase heart rate zone. This is the foundation of all cardiovascular fitness. 80% of running volume should be easy.
- **Substitutes**: Treadmill Run, Cycling, Rowing
- **Football**: Not on T-1 (fresh legs needed). OK on T+2 if Green recovery.

#### 99. Outdoor Run (Tempo)
- **Primary**: Lactate threshold improvement, Cardiovascular system
- **Secondary**: Type IIa muscle fibers, Running economy
- **Equipment**: None (running shoes)
- **Difficulty**: Intermediate
- **Pattern**: Cardio (Threshold)
- **Default**: 20-30 min at threshold pace (Zone 3-4 HR)
- **Increment**: +2 min per week
- **Cues**: "Comfortably uncomfortable." Can speak in short phrases but not sentences. Sustained effort below lactate threshold. This is the pace that makes you faster. Warm up 10 min easy first.
- **Substitutes**: Treadmill Tempo Run, Cycling Tempo, Rowing Tempo
- **Football**: Not on T-1 or T-0. Schedule 48h+ from match.

#### 100. Interval Run (Track/Outdoor)
- **Primary**: VO2max improvement, Speed, Anaerobic capacity
- **Secondary**: Fast-twitch muscle fibers, Running economy
- **Equipment**: None (track or measured route preferred)
- **Difficulty**: Advanced
- **Pattern**: Cardio (High-Intensity Interval)
- **Default**: 6x400m at target pace with 90s jog recovery
- **Increment**: +1 interval or -5s per interval
- **Cues**: All-out (or near all-out) for the work interval. Active recovery (walk/jog) between. Warm up thoroughly (10 min easy + dynamic stretches + strides). Cool down 10 min easy. See Section 13 for full interval programming.
- **Substitutes**: Fartlek, Hill Sprints, Cycling Intervals
- **Football**: Not on T-1 or T-0. Not on T+1 either (legs need recovery).

#### 101. Fartlek Run
- **Primary**: Mixed aerobic/anaerobic, Speed variability
- **Secondary**: Running economy, Mental toughness
- **Equipment**: None
- **Difficulty**: Intermediate
- **Pattern**: Cardio (Mixed)
- **Default**: 25-35 min with unstructured speed surges
- **Increment**: +5 min or more/harder surges
- **Cues**: "Speed play" in Swedish. Run at easy pace, then surge to hard effort for 30s-2min using landmarks (to that lamppost, that tree, that corner). Recover at easy pace. Repeat organically. No strict structure -- listen to your body. Great for football fitness.
- **Substitutes**: Interval Run, Tempo Run, Hill Sprints
- **Football**: Not on T-1 or T-0.

#### 102. Hill Sprints
- **Primary**: Power, Glute/hamstring strength-endurance, Anaerobic capacity
- **Secondary**: Calf strength, VO2max
- **Equipment**: None (hill with 6-10% grade, 50-200m length)
- **Difficulty**: Advanced
- **Pattern**: Cardio (High-Intensity)
- **Default**: 8x50m hill sprints with walk-back recovery
- **Increment**: +2 sprints or steeper hill
- **Cues**: Sprint up the hill at 90-95% effort. Walk back down (full recovery). The incline reduces impact forces (less injury risk than flat sprints) while increasing power output. Walk-back is the recovery -- no rushing.
- **Substitutes**: Interval Run, Sled Push, Stair Sprints
- **Football**: Not on T-1 or T-0.

#### 103. Treadmill Run
- **Primary**: Same as outdoor equivalent (depends on settings)
- **Secondary**: Same
- **Equipment**: Treadmill
- **Difficulty**: Varies
- **Pattern**: Cardio
- **Default**: Matches outdoor equivalent but set 1% incline (to simulate wind resistance -- per Jones & Doust 1996)
- **Increment**: Same as outdoor
- **Cues**: 1% incline minimum for equivalence to outdoor running. Good for controlled pace work. Boring -- use it for interval work or when weather is bad. Treadmill does some of the work for you (the belt moves).
- **Substitutes**: Outdoor Run, Cycling, Rowing
- **Football**: Same restrictions as outdoor equivalent

#### 104. Cycling (Stationary)
- **Primary**: Quadriceps, Cardiovascular system
- **Secondary**: Hamstrings, Glutes, Calves
- **Equipment**: Stationary bike (spin bike, air bike, or recumbent)
- **Difficulty**: Beginner
- **Pattern**: Cardio
- **Default**: 20-30 min at moderate intensity (Zone 2-3)
- **Increment**: +5 min or increase resistance
- **Cues**: Non-impact cardio -- easy on joints. Good option for T+1 post-football active recovery. Adjust seat height so knee has slight bend at bottom of pedal stroke.
- **Substitutes**: Outdoor Run, Rowing, Elliptical
- **Football**: Always safe (great active recovery on T+1)

#### 105. Rowing Machine (Erg)
- **Primary**: Latissimus dorsi, Quadriceps, Cardiovascular system
- **Secondary**: Hamstrings, Glutes, Biceps, Core
- **Equipment**: Rowing machine (Concept2 or similar)
- **Difficulty**: Intermediate (technique matters)
- **Pattern**: Cardio (Full Body)
- **Default**: 20 min at moderate intensity, or 500m intervals
- **Increment**: +5 min or -5s per 500m
- **Cues**: Drive order: LEGS first, then BACK, then ARMS (most common mistake is pulling with arms first). Recovery order: ARMS, BACK, LEGS. Damper setting 3-5 for most people (10 is NOT harder, it just changes the feel). Monitor stroke rate: 20-24 spm for steady state.
- **Substitutes**: Cycling, Swimming, Ski Erg
- **Football**: Always safe

#### 106. Jump Rope
- **Primary**: Calves, Cardiovascular system
- **Secondary**: Shoulders, Forearms, Core, Coordination
- **Equipment**: Speed rope
- **Difficulty**: Beginner (basic) / Advanced (tricks)
- **Pattern**: Cardio
- **Default**: 3x3 min with 60s rest, or 10 min continuous
- **Increment**: +1 min or add complexity (double-unders)
- **Cues**: Stay on balls of feet. Small jumps (clear the rope by 1 inch max). Wrists rotate the rope, not shoulders. Double-unders: jump higher, spin faster. Excellent for football footwork and coordination.
- **Substitutes**: Boxing, Running, Cycling
- **Football**: Always safe

#### 107. Stair Climber / StairMaster
- **Primary**: Quadriceps, Gluteus maximus, Cardiovascular system
- **Secondary**: Calves, Hamstrings
- **Equipment**: Stair climber machine
- **Difficulty**: Beginner
- **Pattern**: Cardio
- **Default**: 15-20 min at moderate intensity
- **Increment**: +5 min or increase speed
- **Cues**: Stand upright -- do not lean on handrails (this cheats the exercise). Full steps. Higher intensity than walking but lower impact than running.
- **Substitutes**: Cycling, Incline Treadmill Walk, Rowing
- **Football**: Always safe

---

### MOBILITY (15 exercises)

#### 108. Foam Roll -- Full Body
- **Primary**: Myofascial release, All major muscle groups
- **Secondary**: Improved blood flow, Reduced muscle soreness
- **Equipment**: Foam roller
- **Difficulty**: Beginner
- **Pattern**: Mobility (Recovery)
- **Default**: 10 min (1-2 min per body area)
- **Increment**: N/A
- **Cues**: Roll each area slowly (1 inch per second). Pause on tender spots for 20-30 seconds. Areas: quads, IT band, hamstrings, calves, glutes, upper back, lats. Do NOT roll directly on the lower back or bony prominences. Pre-workout: brief, light passes. Post-workout or recovery day: longer, deeper work.
- **Substitutes**: Lacrosse Ball Myofascial Release, Massage Gun, Static Stretching
- **Football**: Always safe (essential pre-match and recovery)

#### 109. Dynamic Stretching Routine
- **Primary**: Joint mobility, Muscle activation, Movement prep
- **Secondary**: Core temperature increase, Neural activation
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Mobility (Warm-up)
- **Default**: 8 min (8-10 movements, 10 reps each)
- **Increment**: N/A
- **Cues**: Leg swings (front-back, side-to-side), hip circles, walking knee hugs, walking quad stretch, inchworms, world's greatest stretch, arm circles, torso rotations. Never static stretch before training (reduces power output per Behm 2004). Dynamic stretching primes the nervous system.
- **Substitutes**: Foam Roll + Activation, Light Cardio Warm-Up, Sport-Specific Warm-Up
- **Football**: Always safe (essential pre-match)

#### 110. Hip Flexor Stretch Series
- **Primary**: Iliopsoas, Rectus femoris
- **Secondary**: Quadriceps, Adductors
- **Equipment**: None (or yoga mat)
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 5 min (3 positions, 45s each side)
- **Increment**: N/A
- **Cues**: Half-kneeling hip flexor stretch (basic) -> couch stretch (elevated rear foot) -> pigeon pose variation. Squeeze glute of rear leg to deepen the stretch (reciprocal inhibition). Tight hip flexors are epidemic from sitting -- and they inhibit glute activation, reducing sprint power.
- **Substitutes**: World's Greatest Stretch, Pigeon Pose, Thomas Stretch
- **Football**: Always safe (essential for kicking mechanics)

#### 111. Shoulder Mobility Complex
- **Primary**: Glenohumeral joint, Scapulothoracic joint
- **Secondary**: Thoracic spine, Rotator cuff
- **Equipment**: Resistance band or PVC pipe
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 6 min (5-6 movements, 10 reps each)
- **Increment**: N/A
- **Cues**: Band pull-aparts, dislocates (PVC pipe overhead pass-throughs), wall slides, prone T/Y/I raises, internal/external rotation with band. Maintain before every push session. Healthy shoulders = long training career.
- **Substitutes**: Foam Roll Upper Back, Face Pulls, Yoga Shoulder Stretches
- **Football**: Always safe

#### 112. Yoga Flow (Sun Salutation)
- **Primary**: Full body mobility, Spine flexion/extension
- **Secondary**: Balance, Breathing, Core
- **Equipment**: Yoga mat
- **Difficulty**: Beginner
- **Pattern**: Mobility (Flow)
- **Default**: 15 min (5-6 sun salutations)
- **Increment**: +2 rounds or add complexity (warrior sequences)
- **Cues**: Mountain pose -> forward fold -> halfway lift -> plank -> chaturanga -> upward dog -> downward dog -> walk forward -> stand. Breath-linked movement. Each cycle takes ~1 minute. Excellent active recovery.
- **Substitutes**: Dynamic Stretching, Mobility Flow, Tai Chi
- **Football**: Always safe

#### 113. World's Greatest Stretch
- **Primary**: Hip flexors, Thoracic spine, Hamstrings, Adductors
- **Secondary**: Shoulders, Glutes, Calves
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Mobility (Warm-up)
- **Default**: 3x5 per side, no rest
- **Increment**: N/A (always the same)
- **Cues**: Lunge forward -> place same-side elbow to inside of front foot -> rotate torso and reach opposite arm to sky -> straighten front leg for hamstring stretch. Hits every major mobility restriction in one movement. The name is earned.
- **Substitutes**: Hip Flexor Stretch + Thoracic Rotation, Spider-Man Lunge
- **Football**: Always safe (perfect pre-match)

#### 114. 90/90 Hip Switch
- **Primary**: Hip internal and external rotation
- **Secondary**: Glutes, Adductors, Piriformis
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 3x8 switches, 60s rest
- **Increment**: N/A
- **Cues**: Sit on floor with both knees at 90 degrees (front leg externally rotated, back leg internally rotated). Switch sides by rotating hips. The holy grail of hip mobility. If you can do this smoothly, your hips are healthy.
- **Substitutes**: Pigeon Pose, Hip Flexor Stretch, Cossack Squat
- **Football**: Always safe

#### 115. Thoracic Spine Foam Roll
- **Primary**: Thoracic spine extension
- **Secondary**: Posterior chain, Breathing mechanics
- **Equipment**: Foam roller
- **Difficulty**: Beginner
- **Pattern**: Mobility (Recovery)
- **Default**: 3 min
- **Increment**: N/A
- **Cues**: Roller across upper back. Hug yourself or arms behind head. Extend over the roller (arching back) at each vertebral level. Roll from mid-back to upper back. Do NOT extend into the lower back. Improves overhead pressing and posture.
- **Substitutes**: Yoga Flow, Cat-Cow, Thread the Needle
- **Football**: Always safe

#### 116. Cat-Cow
- **Primary**: Spinal flexion and extension, Core
- **Secondary**: Scapular mobility, Diaphragm
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Mobility (Flow)
- **Default**: 2x10, no rest
- **Increment**: N/A
- **Cues**: Hands and knees. Cow: arch back, head up, belly drops. Cat: round back, tuck chin, pull belly button to spine. Slow, controlled movement linked with breath. Inhale on cow, exhale on cat.
- **Substitutes**: Yoga Flow, Thoracic Spine Roll, Segmental Cat-Cow
- **Football**: Always safe

#### 117. Pigeon Pose
- **Primary**: Piriformis, Gluteus maximus, Hip external rotators
- **Secondary**: Hip flexors (back leg)
- **Equipment**: Yoga mat
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 45-60s per side, 2 rounds
- **Increment**: N/A
- **Cues**: Front shin across the body (angle depends on flexibility). Back leg straight behind. Fold forward over front shin for deeper stretch. If this is too intense, do figure-4 stretch on back instead. Essential for anyone who sits a lot or plays football.
- **Substitutes**: 90/90 Hip Switch, Figure-4 Stretch, Seated Pigeon
- **Football**: Always safe

#### 118. Cossack Squat
- **Primary**: Hip adductors, Hip mobility, Quadriceps
- **Secondary**: Glutes, Hamstrings (stretched leg), Ankle mobility
- **Equipment**: Bodyweight (optional: light kettlebell as counterbalance)
- **Difficulty**: Intermediate
- **Pattern**: Mobility / Squat
- **Default**: 3x8 per side, 60s rest
- **Increment**: +2 reps or add weight
- **Cues**: Wide stance. Shift weight to one side, squatting deep on that leg while the other leg stays straight with toes up. Return to center and switch. Demands and builds hip mobility simultaneously. Also a great warm-up for squat days.
- **Substitutes**: Lateral Lunge, 90/90 Switch, Goblet Squat
- **Football**: Always safe

#### 119. Ankle Mobility Drill (Banded)
- **Primary**: Talocrural joint dorsiflexion
- **Secondary**: Soleus, Achilles tendon
- **Equipment**: Resistance band, Wall or rack
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 3x10 per ankle, no rest
- **Increment**: N/A
- **Cues**: Band around front of ankle, attached to rack behind. Lunge forward driving knee past toes. The band distracts the talus posteriorly, improving dorsiflexion. If your ankles are the limiting factor in your squat depth (heels rise), do this before every squat session.
- **Substitutes**: Wall Ankle Stretch, Calf Raise (eccentric), Elevated Heel Squat
- **Football**: Always safe (ankle mobility prevents sprains)

#### 120. Lacrosse Ball Myofascial Release
- **Primary**: Deep trigger point release
- **Secondary**: Improved tissue quality
- **Equipment**: Lacrosse ball
- **Difficulty**: Beginner
- **Pattern**: Mobility (Recovery)
- **Default**: 5-8 min targeting 2-3 areas
- **Increment**: N/A
- **Cues**: Place ball on target area (glutes, pec minor, feet arch, rear delt, subscapularis). Apply body weight. Find tender spot. Hold for 30-60 seconds until tenderness subsides. More targeted than foam roller. Hurts more. Works better on specific knots.
- **Substitutes**: Foam Roll, Massage Gun, Trigger Point Therapy
- **Football**: Always safe

#### 121. Banded Shoulder Dislocate
- **Primary**: Shoulder joint (full circumduction)
- **Secondary**: Pec minor, Rotator cuff, Latissimus dorsi
- **Equipment**: PVC pipe or Resistance band
- **Difficulty**: Beginner
- **Pattern**: Mobility (Warm-up)
- **Default**: 2x15, no rest
- **Increment**: Narrow grip width for difficulty
- **Cues**: Hold PVC pipe or band with wide overhand grip. Lift overhead and rotate all the way behind body and back. Arms stay straight. Start wide, narrow grip as mobility improves. If you feel clicking or pain, stop -- widen grip or see a physio.
- **Substitutes**: Shoulder Mobility Complex, Wall Slides, Band Pull-Apart
- **Football**: Always safe

#### 122. Jefferson Curl
- **Primary**: Entire posterior chain (vertebra-by-vertebra flexion)
- **Secondary**: Hamstrings, Erector spinae
- **Equipment**: Light dumbbell or barbell, Elevated platform
- **Difficulty**: Advanced
- **Pattern**: Mobility (Controlled Flexion)
- **Default**: 2x5, slow and controlled
- **Increment**: +1kg (very gradually)
- **Cues**: Stand on elevated surface. Hold light weight. Roll down ONE VERTEBRA AT A TIME from cervical spine to lumbar. Let weight pull you past feet. Reverse the process coming up. Do NOT go heavy. This is a mobility exercise, not a strength exercise. Contraindicated for anyone with disc issues.
- **Substitutes**: Standing Forward Fold, Segmental Cat-Cow, Good Morning (light)
- **Football**: Always safe at bodyweight/light load

---

### FOOTBALL-SPECIFIC (10 exercises)

These exercises are specifically programmed around match days for football performance.

#### 123. Glute Activation Bridge (Banded)
- **Primary**: Gluteus maximus, Gluteus medius
- **Secondary**: Core, Hip external rotators
- **Equipment**: Mini resistance band (around knees)
- **Difficulty**: Beginner
- **Pattern**: Hinge (Activation)
- **Default**: 2x15, no rest (pre-match warm-up)
- **Increment**: N/A (consistent warm-up drill)
- **Cues**: Band around knees. Glute bridge while pressing knees out against band. Fires glutes before match. Prevents the all-too-common "quad dominant, glute lazy" pattern that leads to hamstring injuries.
- **Substitutes**: Banded Clamshell, Single-Leg Glute Bridge, Fire Hydrant
- **Football**: Essential pre-match

#### 124. A-Skip Drill
- **Primary**: Hip flexors, Running mechanics
- **Secondary**: Calves, Coordination
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Football-Specific (Speed)
- **Default**: 2x20m, walk-back recovery
- **Increment**: N/A (warm-up drill)
- **Cues**: Exaggerated skipping motion. Drive knee to hip height. Punch foot down under hip. Arm swing opposite to leg. This is a neural primer for sprinting mechanics. Do before every match and sprint session.
- **Substitutes**: B-Skip, High Knees, Butt Kicks
- **Football**: Essential pre-match

#### 125. Banded Lateral Walk
- **Primary**: Gluteus medius, Tensor fasciae latae
- **Secondary**: Hip stabilizers
- **Equipment**: Mini resistance band (around ankles)
- **Difficulty**: Beginner
- **Pattern**: Football-Specific (Stability)
- **Default**: 2x15 steps each direction, no rest
- **Increment**: Use heavier band
- **Cues**: Quarter squat position. Steps sideways maintaining tension on band. Do not let feet come together. Activates hip abductors -- critical for cutting, changing direction, and knee stability during tackles.
- **Substitutes**: Banded Clamshell, Side Plank Hip Abduction, Lateral Lunge
- **Football**: Essential pre-match and pre-training

#### 126. Agility Ladder Drills
- **Primary**: Footwork speed, Coordination, Agility
- **Secondary**: Calves, Cardiovascular system
- **Equipment**: Agility ladder
- **Difficulty**: Beginner
- **Pattern**: Football-Specific (Agility)
- **Default**: 5 min (4-5 patterns, 2 reps each)
- **Increment**: Increase speed or add complexity
- **Cues**: Quick feet. Stay on balls of feet. Minimize ground contact time. Common patterns: two feet in each square, lateral in-out, Icky shuffle, crossover step. Great neural activation for match days.
- **Substitutes**: Cone Drills, Jump Rope, Shuttle Runs
- **Football**: Always safe (warm-up)

#### 127. Box Jump
- **Primary**: Quadriceps, Gluteus maximus (power/plyometric)
- **Secondary**: Hamstrings, Calves, Core
- **Equipment**: Plyometric box (20-30 inch)
- **Difficulty**: Intermediate
- **Pattern**: Squat (Plyometric)
- **Default**: 3x5, 120s rest
- **Increment**: +2 inches box height or +1 rep
- **Cues**: Stand in front of box, feet hip-width. Quarter squat, swing arms, JUMP. Land softly on the box with full foot. Stand up fully on box. Step down (do NOT jump down -- that is unnecessary eccentric stress). Focus on explosive concentric, soft landing.
- **Substitutes**: Broad Jump, Tuck Jump, Squat Jump
- **Football**: Not on T-1 or T-0

#### 128. Sprint Drills (10-30m)
- **Primary**: Fast-twitch muscle fibers, Acceleration, Neural power
- **Secondary**: Hamstrings, Glutes, Calves
- **Equipment**: None (flat surface, 30m+)
- **Difficulty**: Advanced
- **Pattern**: Football-Specific (Speed)
- **Default**: 6x20m with full recovery (walk back + 60s)
- **Increment**: +2 sprints or increase distance
- **Cues**: 95% effort (not 100% -- save that for match day). 45-degree forward lean at start. Pump arms hard. First 10m is acceleration. Decelerate gradually -- do not plant-and-stop. Full recovery between sprints. If hamstrings feel tight, stop immediately.
- **Substitutes**: Hill Sprints, Sled Push, Resisted Sprints (band)
- **Football**: Not on T-1 or T-0. Only when fully fresh.

#### 129. Copenhagen Adductor Exercise
- **Primary**: Adductors (hip adduction under load)
- **Secondary**: Obliques, Core
- **Equipment**: Bench or elevated surface
- **Difficulty**: Advanced
- **Pattern**: Football-Specific (Injury Prevention)
- **Default**: 3x6 per side, 90s rest
- **Increment**: +1 rep (progress slowly)
- **Cues**: Side plank position, top foot on bench, bottom foot hanging. Lift bottom leg to bench by adducting. Hold 2 seconds. Lower. The Copenhagen adductor exercise has been shown to reduce groin injuries in football players by 41% (Harmon 2019). Non-negotiable for footballers.
- **Substitutes**: Adductor Machine, Banded Adduction, Slider Adduction
- **Football**: Always safe (prehab -- train year-round)

#### 130. Eccentric Hamstring Slide
- **Primary**: Hamstrings (eccentric)
- **Secondary**: Glutes, Core
- **Equipment**: Sliders or towel on smooth floor
- **Difficulty**: Intermediate
- **Pattern**: Football-Specific (Injury Prevention)
- **Default**: 3x8, 90s rest
- **Increment**: +2 reps
- **Cues**: Lie on back, heels on sliders. Bridge up. Slowly extend legs (eccentric hamstring loading). Return by curling heels back. Control the extension -- do not just slide out and lose tension. Regression of Nordic curls for those who cannot yet do them.
- **Substitutes**: Nordic Curl, Swiss Ball Leg Curl, Single-Leg Slider Curl
- **Football**: Always safe (prehab)

#### 131. Single-Leg Balance (Eyes Closed)
- **Primary**: Proprioception, Ankle stabilizers
- **Secondary**: Gluteus medius, Core
- **Equipment**: None
- **Difficulty**: Beginner
- **Pattern**: Football-Specific (Balance)
- **Default**: 3x30s per leg, 30s rest
- **Increment**: +15s or add unstable surface (BOSU)
- **Cues**: Stand on one leg. Close eyes. Maintain balance. Sounds easy -- it is not. Proprioception degrades with fatigue (exactly when you need it most in a match). Training it builds resilience against late-game ankle injuries and missteps.
- **Substitutes**: BOSU Balance, Single-Leg RDL, Yoga Tree Pose
- **Football**: Always safe (do daily)

#### 132. Medicine Ball Rotational Throw
- **Primary**: Obliques (power), Core rotation
- **Secondary**: Hips, Shoulders, Chest
- **Equipment**: Medicine ball (3-6kg) + Wall
- **Difficulty**: Beginner
- **Pattern**: Football-Specific (Rotational Power)
- **Default**: 3x8 per side, 60s rest
- **Increment**: +1kg ball or +2 reps
- **Cues**: Stand perpendicular to wall. Rotate core and throw ball at wall as hard as possible. Catch rebound. Repeat. Power comes from the HIP rotation, not the arms. This mimics the rotational force in kicking, tackling, and changing direction.
- **Substitutes**: Cable Woodchop, Russian Twist, Landmine Rotation
- **Football**: Always safe (builds sport-specific power)

---

### ADDITIONAL EXERCISES (added for completeness)

These exercises are referenced as substitutes in the database but were missing dedicated entries.

#### 133. Trap Bar Deadlift (Hex Bar Deadlift)
- **Primary**: Quadriceps, Gluteus maximus, Hamstrings
- **Secondary**: Erector spinae, Trapezius, Core, Forearms (grip)
- **Equipment**: Trap bar (hex bar)
- **Difficulty**: Beginner
- **Pattern**: Hinge / Squat hybrid
- **Default**: 3x6, 150s rest
- **Increment**: 2.5-5kg
- **Cues**: Step inside the hex bar. Grip the handles at your sides. Sit hips back and down (between a squat and a deadlift). Chest up, lats engaged. Drive through the floor. Lockout with hips. The neutral grip and centered load reduce spinal shear stress compared to conventional deadlift (Swinton et al., 2011). Greater peak power and peak velocity than conventional deadlift at equivalent loads. The best general-purpose strength exercise for athletes who are not competitive powerlifters.
- **Substitutes**: Barbell Deadlift, Barbell Back Squat, Leg Press
- **Football**: Not on T-0 or T-1 (significant lower body demand, but safer than conventional deadlift for footballers due to reduced spinal loading)

#### 134. Reverse Lunge (Dumbbell)
- **Primary**: Quadriceps, Gluteus maximus
- **Secondary**: Hamstrings, Adductors, Core (balance)
- **Equipment**: Dumbbells
- **Difficulty**: Beginner
- **Pattern**: Squat
- **Default**: 3x10, 120s rest (per leg)
- **Increment**: 2kg per dumbbell
- **Cues**: Step backward into a lunge. Lower until both knees are at ~90 degrees. Front shin stays vertical. Push through front foot to return to standing. Reverse lunges are knee-friendlier than forward lunges because the deceleration is controlled by the front leg eccentrically rather than catching momentum. Excellent for footballers -- unilateral, functional, and lower injury risk than walking lunges.
- **Substitutes**: Walking Lunge, Bulgarian Split Squat, Step-Up
- **Football**: Not on T-1 (single-leg lower body)

#### 135. Trap Bar Shrug
- **Primary**: Upper trapezius
- **Secondary**: Levator scapulae, Rhomboids, Forearms (grip)
- **Equipment**: Trap bar
- **Difficulty**: Beginner
- **Pattern**: Pull
- **Default**: 3x12, 90s rest
- **Increment**: 5kg
- **Cues**: Same as barbell shrug but the trap bar allows heavier loads with a more natural arm position. Shrug straight up, hold 1-2 seconds at peak contraction. No rolling.
- **Substitutes**: Barbell Shrug, Dumbbell Shrug, Cable Shrug
- **Football**: Always safe

#### 136. Hip Flexor Stretch (Standing Banded)
- **Primary**: Iliopsoas, Rectus femoris
- **Secondary**: Tensor fasciae latae
- **Equipment**: Resistance band, Rack
- **Difficulty**: Beginner
- **Pattern**: Mobility (Stretch)
- **Default**: 3x30s per side, no rest
- **Increment**: N/A
- **Cues**: Attach band to rack at hip height. Step one foot into band, face away from rack. Band pulls hip into extension. Step forward into a half-kneeling position, allowing the band to distract the hip joint anteriorly. This improves hip extension range beyond what a static stretch alone can achieve. Essential for footballers who spend significant time sitting (university students) and need maximal hip extension for sprinting and kicking.
- **Substitutes**: Hip Flexor Stretch Series (#110), Couch Stretch, Thomas Stretch
- **Football**: Always safe (essential prehab)

---

**Total: 136 seeded exercises + custom exercise creation = 150+ available.**

### 10.5 Exercise Detail View

```
+-----------------------------------------+
|  < Back     BARBELL BENCH PRESS         |
|-----------------------------------------|
|                                          |
|  +--------------------------------------+|
|  |                                      ||
|  |     (Exercise demo animation)        || <- 200pt, looping
|  |     or illustration                  ||    2-frame crossfade
|  |                                      ||
|  +--------------------------------------+|
|                                          |
|  Chest  *  Barbell  *  Compound  *  Int | <- Tags row
|                                          |
|  MUSCLES WORKED                          |
|  +--------------------------------------+|
|  |  Primary: Pectoralis Major           ||
|  |  Secondary: Anterior Deltoid,        ||
|  |  Triceps Brachii, Serratus Anterior  ||
|  |                                      ||
|  |  (Muscle diagram -- front view       || <- 160pt
|  |   with highlighted muscles)          ||
|  +--------------------------------------+|
|                                          |
|  HOW TO PERFORM                          |
|  +--------------------------------------+|
|  | 1. Lie on a flat bench with          ||
|  |    feet firmly on the floor.         ||
|  | 2. Grip the bar slightly wider       ||
|  |    than shoulder width.              ||
|  | 3. Unrack and lower the bar to       ||
|  |    mid-chest, elbows at ~45-75 deg.  ||
|  | 4. Press up explosively to           ||
|  |    lockout. Repeat.                  ||
|  +--------------------------------------+|
|                                          |
|  COMMON MISTAKES                         |
|  * Flaring elbows to 90 degrees         |
|  * Bouncing bar off chest               |
|  * Not retracting scapulae              |
|  * Feet not planted firmly              |
|                                          |
|  ALTERNATIVES                            |
|  [Dumbbell Bench] [Machine Press] [Floor]|
|                                          |
|  YOUR HISTORY                            |
|  +--------------------------------------+|
|  |  Est. 1RM: 102.5kg                  ||
|  |  Best: 90kg x 6                     ||
|  |  Last session: 85kg x 8 (x4)        ||
|  |                                      ||
|  |  [View Full History ->]              ||
|  +--------------------------------------+|
|                                          |
|  SETTINGS                                |
|  Default rest time: [3:00] >            |
|  Weight increment:  [2.5kg] >           |
|  Include warm-up:   [On] >             |
|  Bar type:          [20kg Olympic] >    |
|                                          |
+-----------------------------------------+
```

### 10.6 Custom Exercise Creation

Multi-step form in full-screen modal. Fields: name (required), primary muscle group, secondary muscles, equipment, movement pattern, difficulty, tracking type (weight x reps / bodyweight x reps / duration / distance), default sets/reps, rest time, weight increment, notes/instructions. Custom exercises tagged with "Custom" badge in library.

---

## 11. Progress Charts

### 11.1 Screen Structure

Three tabs: Per Exercise, Muscle Groups, Overview. Segmented control at top.

### 11.2 Per-Exercise Chart View

When user selects an exercise:

- **Estimated 1RM Chart**: Line chart with data points. Height 200pt. Line: 2pt stroke, `primary`. Data points: 6pt circles. X-axis: time range. Y-axis: weight. Tap-and-hold for tooltips. Drag scrubbing with vertical line and haptic `.light` on each data point. Pinch to zoom for time range. **1RM Formula**: Epley: `1RM = weight x (1 + reps / 30)`. Uses the best set of each session. Also available: Brzycki formula as an option in settings.
- **Volume Chart**: Bar chart, 160pt height. Bars: `primary` fill, 8pt width. Shows total volume per session.
- **PR History**: Chronological list of all personal records for this exercise.
- **Session Log**: Full history of every session. Expandable rows showing set-by-set data.
- **Time range selector**: 1M, 3M, 6M, 1Y, All.

### 11.3 Muscle Group Tab

- **Weekly volume by muscle group**: Horizontal bar chart.
- **Balance analysis**: Flags muscle group imbalances using common ratios:
  - Push/Pull (chest+shoulders+triceps vs back+biceps): ideal 1:1 to 1:1.2
  - Quad/Hamstring: ideal 1:1 to 1.5:1
  - Warning icon (yellow) if outside range. Check icon (green) if within range.
- **Volume trend**: Stacked area chart showing weekly volume distribution over time.

### 11.4 Overview Tab

- **Total weekly volume**: Line chart.
- **Workout frequency**: Bar chart + 4-week average.
- **Consistency heatmap**: GitHub-style contribution graph. 52 columns x 7 rows. Color intensity based on volume relative to user average.
- **Body part split**: Donut chart showing % of volume per muscle group.
- **All-time stats**: Total workouts, total volume, total sets.

---

## 12. Personal Records System

### 12.1 What Qualifies as a PR

Five types of personal records are tracked:

| PR Type | Definition | When Checked | Notification |
|---------|-----------|-------------|--------------|
| **Estimated 1RM** | Highest calculated 1RM for an exercise (Epley formula) | After every working set | Gold confetti + double haptic |
| **Absolute 1RM** | Heaviest single rep (actual, not estimated) | When user logs 1 rep at a new max weight | Full-screen fireworks + triple haptic |
| **Rep PR at Weight** | Most reps at a given weight (or higher) | After every working set | Gold badge + single haptic |
| **Volume PR** | Highest total volume for one exercise in a single session | After last set of an exercise | Gold badge |
| **Endurance PR** | Longest distance or time for a cardio exercise | After cardio session completes | Gold badge |

### 12.2 1RM Calculation Formulas

**Primary (default): Epley Formula**
```
e1RM = weight x (1 + reps / 30)
```

**Secondary (available in settings): Brzycki Formula**
```
e1RM = weight x (36 / (37 - reps))
```

**When reps > 12**: Both formulas become increasingly inaccurate. For sets of 12+ reps, only Volume PR and Rep PR are tracked -- e1RM is suppressed.

**When reps = 1**: e1RM = actual weight (no estimation needed). This counts as both Estimated 1RM and Absolute 1RM.

### 12.3 PR Detection Algorithm

```
FUNCTION check_for_pr(completed_set, exercise, all_history):

  # Skip warm-up sets
  IF completed_set.isWarmUp: RETURN null

  # Skip if reps > 12 for 1RM calculation
  IF completed_set.reps <= 12:
    current_e1rm = epley(completed_set.weight, completed_set.reps)
    best_e1rm = MAX(all_history.e1rm_values) for this exercise

    IF current_e1rm > best_e1rm:
      IF completed_set.reps == 1:
        RETURN PR(type: .absolute1RM, value: completed_set.weight, previous: best_e1rm)
      ELSE:
        RETURN PR(type: .estimated1RM, value: current_e1rm, previous: best_e1rm)

  # Rep PR: most reps at this weight or higher
  best_reps_at_weight = MAX(reps) WHERE weight >= completed_set.weight in all_history
  IF completed_set.reps > best_reps_at_weight:
    RETURN PR(type: .repPR, value: completed_set.reps, weight: completed_set.weight, previous: best_reps_at_weight)

  RETURN null  # No PR

FUNCTION check_volume_pr(exercise_id, session_sets, all_history):
  session_volume = SUM(set.weight * set.reps for set in session_sets WHERE NOT set.isWarmUp)
  best_volume = MAX(session_volume) for this exercise in all_history

  IF session_volume > best_volume:
    RETURN PR(type: .volumePR, value: session_volume, previous: best_volume)

  RETURN null
```

### 12.4 PR Notification and Celebration

**During workout (real-time):**
1. PR detected after tapping DONE on a set.
2. **e1RM PR**: Gold badge pops in (400ms spring, scale 0 to 1.15 to 1.0) next to the completed set in the history. Badge reads "NEW e1RM: {value}kg" in `prGold`. Haptic: double `.success`. Small confetti burst (gold particles, 1 second, contained to the set row area).
3. **Absolute 1RM PR**: Full-screen confetti (3 seconds). Larger gold badge. Triple haptic. Screen briefly flashes gold at the edges.
4. **Rep PR**: Smaller gold badge "REP PR" next to the set. Single haptic.
5. **Volume PR**: Shown only at exercise completion (not per-set). Badge in exercise completion animation.

**In workout summary:**
- All PRs listed in a dedicated section with gold-bordered cards.
- PR cards slide in with staggered animation (200ms between each) and gold shimmer effect.

**Post-workout notification:**
- If PRs were hit, push notification: "New PR! Bench Press e1RM: 102.5kg" with trophy emoji.

### 12.5 PR History and Progression

In the Exercise Detail View and Progress Charts:
- **PR timeline**: All-time list of PRs, most recent first. Each entry: date, type, value, improvement from previous.
- **PR projection**: Based on the progression rate over the last 3 months, a dotted line on the e1RM chart projects where the user could be in 1, 3, 6 months. "Current trajectory: 110kg e1RM by May" in `caption`, `textSecondary`.

### 12.6 PR Achievements

Milestone PRs trigger special celebrations:
- **First PR ever**: "Welcome to the PR club!" special animation.
- **100kg bench / 140kg squat / 180kg deadlift**: "Century Club" / "Plate Milestone" badges.
- **2x bodyweight squat, 1.5x bodyweight bench, 2.5x bodyweight deadlift**: "Strength Standards" badges (if user has entered bodyweight).
- These are stored in the Arena module (ClutchTime) for XP and achievements.

---

## 13. Running & Cardio Module (Deep Dive)

### 13.1 Overview

Running and cardio workouts have a fundamentally different UX from weight training. No sets/reps -- the user tracks distance, time, pace, and heart rate. The view adapts based on workout type.

### 13.2 Run Types and Programming

| Run Type | Purpose | Duration | Intensity | HR Zone | Pace Zone | Frequency |
|---------|---------|----------|-----------|---------|-----------|-----------|
| Easy Run | Aerobic base, recovery | 30-60 min | Low | Zone 1-2 | 5:30-6:30/km | 2-3x/week |
| Tempo Run | Lactate threshold | 20-40 min | Moderate-High | Zone 3-4 | 4:30-5:00/km | 1x/week |
| Interval Run | VO2max, speed | 30-45 min total | High (during intervals) | Zone 4-5 | 3:30-4:15/km | 1x/week |
| Long Run | Endurance | 60-90 min | Low | Zone 1-2 | 5:30-6:30/km | 1x/week |
| Fartlek | Mixed, sport-specific | 25-40 min | Variable | Zone 2-5 | Variable | 1x/week |
| Recovery Run | Active recovery | 20-30 min | Very Low | Zone 1 | 6:00-7:00/km | As needed |

### 13.3 Pace Zones

Pace zones are calculated from the user's **lactate threshold pace** (LT pace), which can be:
1. **Estimated from a recent race or time trial**: e.g., if user ran 5km in 22:00, LT pace is approximately 4:24/km.
2. **Estimated from a tempo run**: Pace that can be sustained for 40-60 minutes at RPE 7-8.
3. **Manually entered** in Training Settings.
4. **Updated automatically** as the app accumulates run data and detects improvement.

| Zone | Name | % of LT Pace | Example (LT = 4:30/km) | Purpose |
|------|------|-------------|------------------------|---------|
| Z1 | Recovery | 75-80% | 5:40-6:00/km | Active recovery |
| Z2 | Easy/Aerobic | 80-88% | 5:05-5:40/km | Base building |
| Z3 | Tempo | 88-95% | 4:45-5:05/km | Threshold training |
| Z4 | Interval | 95-105% | 4:15-4:45/km | VO2max development |
| Z5 | Sprint | 105%+ | <4:15/km | Neuromuscular power |

### 13.4 Interval Programming Builder

The app generates interval sessions based on the user's fitness level and goals. Algorithm:

```
FUNCTION generate_interval_session(lt_pace, fitness_level, target_distance, available_time):

  # Determine interval structure
  IF fitness_level == .beginner:
    interval_distance = 200m
    num_intervals = 6
    work_pace = lt_pace * 0.95  # 95% of LT
    recovery_duration = 90s (jog)

  ELSE IF fitness_level == .intermediate:
    interval_distance = 400m
    num_intervals = 6-8
    work_pace = lt_pace * 1.00  # At LT
    recovery_duration = 90s (jog)

  ELSE IF fitness_level == .advanced:
    interval_distance = 800m OR 1000m
    num_intervals = 4-6
    work_pace = lt_pace * 1.05  # 105% of LT
    recovery_duration = 120s (jog)

  # Warm-up: 10 min easy + 4 strides (100m at Z4 pace)
  # Cool-down: 10 min easy
  # Total time: warm_up + (num_intervals * interval_time) + (num_intervals * recovery_duration) + cool_down

  RETURN IntervalSession(
    warmup: 10 min easy,
    strides: 4 x 100m,
    intervals: num_intervals x interval_distance at work_pace,
    recovery: recovery_duration jog between,
    cooldown: 10 min easy
  )
```

**Preset interval types**:
- **400m Repeats**: 6-10 x 400m at Z4-Z5 pace, 90s jog recovery. Classic track workout.
- **800m Repeats**: 4-6 x 800m at Z4 pace, 2:00 jog recovery. VO2max builder.
- **Tempo Intervals**: 3-4 x 1600m at Z3 pace, 60s jog recovery. Threshold work.
- **Fartlek (structured)**: 1 min hard / 1 min easy x 10-15. Or 2 min / 1 min x 8.
- **Hill Repeats**: 8-12 x 50-100m uphill at Z5 effort, walk-down recovery.
- **Pyramid**: 200-400-600-800-600-400-200 at Z4 pace, equal jog recovery.

### 13.5 Active Run View

See Section 8.3 of the original spec (preserved in full). Key additions:

**GPS Accuracy Handling**:
- GPS typically accurate to 5-15m outdoors.
- Under tree cover or between buildings: accuracy drops to 20-50m.
- App uses Kalman filtering on CLLocation data to smooth GPS noise.
- If GPS accuracy drops below 30m for 10+ seconds, show warning: "[warning] GPS accuracy low -- pace may be inaccurate."
- Pace is a rolling 30-second average to smooth GPS fluctuations. Raw instantaneous pace is too noisy.
- For track runs, offer "Track Mode" that calculates distance from lap count (400m per lap) instead of GPS.

**Route Comparison**:
- If the user runs the same route multiple times (detected by GPS route matching within 100m corridor), the app offers comparison:
- "You ran this route 3 times. Best: 24:32, Today: 25:01 (+0:29)."
- On the map, the previous best route is shown as a ghost line (faded `primary` at 30% opacity) alongside the current route.
- Per-km split comparison table: each km shows current pace vs best pace with delta.

### 13.6 VO2max Estimation

Estimated from running data using validated field-test equations:

```
VO2max (ml/kg/min) = estimated from best recent effort

METHOD 1: Cooper Test (Cooper, 1968)
  IF user ran a 12-minute all-out effort:
    VO2max = (distance_meters - 504.9) / 44.73
  Accuracy: r = 0.897 with measured VO2max (Cooper 1968). Standard error ~3 ml/kg/min.
  Note: requires a true maximal 12-minute effort. Submaximal runs will underestimate.

METHOD 2: Daniels' VDOT (Daniels, 2014 — Running Formula, 4th ed.)
  VDOT is a running-specific fitness index derived from race performance.
  IMPORTANT: VDOT is NOT identical to measured VO2max. VDOT represents the VO2max
  that a runner with "average" running economy would need to achieve that time.
  Runners with superior economy will have a VDOT that exceeds their measured VO2max.
  Display as "VDOT" in the app, not as "VO2max", to avoid misleading the user.

  Example VDOT values from race times (Daniels' Running Formula, 4th ed.):
  - 5K in 20:00 = VDOT 44.8
  - 5K in 22:00 = VDOT 40.5
  - 5K in 25:00 = VDOT 35.8
  - 10K in 45:00 = VDOT 42.4
  - 10K in 50:00 = VDOT 38.2

  Use the full VDOT lookup table for precise values, interpolating between entries.
  VDOT also drives training pace prescription (see Section 13.3).

METHOD 3: Sub-maximal estimation (Uth et al., 2004)
  VO2max = 15.3 * (HRmax / HRrest)
  Requires: measured or estimated HRmax (220 - age as fallback, or actual max from
  a hard effort), and resting HR. Accuracy: standard error ~5 ml/kg/min.
  Less accurate than Methods 1-2 but requires no maximal effort.

METHOD 4: Firstbeat-style regression (optional, requires HR + pace data)
  From steady-state run HR and pace data, estimate using the linear relationship
  between submaximal HR and running speed. Requires: HR data from a steady-state
  run of 15+ minutes, pace data, user age, user weight.
  This method improves over time as more data points accumulate.
```

VO2max (or VDOT, depending on the method used) is displayed in the Progress Charts > Overview tab and updates after each qualifying effort. The app should clearly label which method was used and its confidence level. Prefer Method 2 (VDOT from race times) when available, as it is the most practical and well-validated for training pace prescription.

### 13.7 Split Tracking and Analysis

- Per-km (or per-mile) splits recorded automatically.
- Each split: distance marker, pace, average HR, HR zone, elevation change.
- **Pace consistency metric**: Standard deviation of splits. Lower = more consistent pacing. "Pace consistency: 92% (excellent)" shown in run summary.
- **Negative split detection**: If second half was faster than first half, badge: "Negative Split -- strong finish!"
- **Positive split warning**: If pace degraded more than 10% from first to last km: "Pace faded in the back half. Consider starting slower."

### 13.8 Run Summary

Extends the standard workout summary with:
- Route map (full view, pace-colored gradient)
- Split table with pace, HR, zone per km
- HR zone distribution bar
- Average pace, best km pace, worst km pace
- Elevation gain/loss
- VO2max update (if applicable)
- Comparison to previous run on same route (if applicable)
- Estimated calories (from pace, weight, duration, grade)

---

## 14. Training Settings

### 14.1 Full Settings Screen

All settings from the original spec preserved. Additions:

**New settings sections**:

#### Plate Calculator Settings
- Bar type: Olympic 20kg (default), Women's 15kg, EZ Curl 10kg, Short Bar 7kg
- Available plates: Checkboxes for each plate weight (25, 20, 15, 10, 5, 2.5, 1.25 kg)
- Plate quantities: How many of each plate the user has access to
- Unit system: kg plates vs lbs plates (45, 35, 25, 10, 5, 2.5 lbs + 45 lbs bar)

#### Deload Settings
- Auto-deload trigger: On/Off (default: On)
- Deload frequency: Every 4 / 5 / 6 weeks (default: 5)
- Deload type preference: Volume deload (default), Intensity deload, Active recovery week
- Manual deload trigger button: "Start Deload Week Now"

#### PR Settings
- 1RM formula: Epley (default) / Brzycki
- PR celebrations: On/Off (default: On)
- PR sound: On/Off
- Track volume PRs: On/Off (default: On)

#### Apple Watch
- Watch companion: On/Off (default: On if Watch paired)
- Watch rest timer haptic: On/Off (default: On)
- Watch complication: Today's workout / Next workout / Weekly streak

#### Import/Export
- See Section 20 for complete specification.

---

## 15. Workout Generation Algorithm

### 15.1 Overview

The AI workout generator produces a complete, ordered exercise list with sets, reps, weight, and rest times for each day. It runs weekly (Sunday night) and can be re-run on demand. The algorithm is deterministic given the same inputs -- no randomness.

### 15.2 Inputs

```
WorkoutGenerationInput {
  // User profile
  training_split: TrainingSplit          // PPL, Upper/Lower, Full Body, Custom
  football_schedule: [DayOfWeek]        // e.g., [.wednesday, .saturday]
  equipment_available: [Equipment]      // e.g., [.barbell, .dumbbell, .cable, .machine]
  preferred_duration_minutes: Range     // e.g., 45...60
  bodyweight_kg: Double?                // for bodyweight exercises and calorie estimation
  experience_level: ExperienceLevel     // .beginner, .intermediate, .advanced

  // Recovery
  current_recovery_score: Int?          // 0-100 from Whoop (today)
  recovery_7day_avg: Int?               // rolling average
  recovery_trend: Trend                 // .improving, .stable, .declining

  // History
  exercise_history: [ExerciseLog]       // last 30 days of logged workouts
  progression_state: [ProgressionState] // per-exercise state (current weight, stall count, etc.)
  last_deload_date: Date?               // when was the last deload
  deload_preference: DeloadType         // .volume (default), .intensity, .activeRecovery

  // Calendar
  today: Date
  week_start: Date                      // Monday of the target week

  // Preferences
  user_preferences: UserPreferences {
    favorite_exercises: [ExerciseID]
    disliked_exercises: [ExerciseID]
    injury_flags: [MuscleGroup]         // avoid exercises targeting these
    include_warmups: Bool
    include_supersets: Bool
    superset_preference: SupersetPref   // .none, .time_saver, .aggressive
  }
}
```

### 15.3 Output

```
WeeklyPlan {
  days: [DayPlan] (7 days, Monday through Sunday)
}

DayPlan {
  date: Date
  type: WorkoutType
  exercises: [PlannedExercise]  // ordered list
  estimated_duration: Int       // minutes
  recovery_zone: RecoveryZone   // green/yellow/red (actual or projected)
  adjustments: [Adjustment]     // what was modified and why
}

PlannedExercise {
  exercise: Exercise
  order: Int
  target_sets: Int
  target_reps: Int
  target_weight: Double?
  rest_seconds: Int
  is_warmup: Bool
  superset_group: String?       // "A", "B", etc.
  notes: String?                // e.g., "Increased from 82.5kg"
}
```

### 15.4 Complete Algorithm (Pseudocode)

```
FUNCTION generate_weekly_plan(input: WorkoutGenerationInput) -> WeeklyPlan:

  plan = WeeklyPlan()

  // ============================================================
  // PHASE 1: ASSIGN WORKOUT TYPES TO DAYS
  // ============================================================

  // Step 1: Lock football days
  FOR day IN input.football_schedule:
    plan.days[day].type = .football
    plan.days[day].exercises = generate_prematch_prep()

  // Step 2: Lock T-1 days (day before football) -- protect legs
  FOR football_day IN input.football_schedule:
    t_minus_1 = football_day - 1
    IF plan.days[t_minus_1].type == nil:
      plan.days[t_minus_1].flag = .legProtected  // not a type assignment yet

  // Step 3: Handle T+1 days (day after football)
  FOR football_day IN input.football_schedule:
    t_plus_1 = football_day + 1
    projected_recovery = estimate_recovery_for_day(t_plus_1, input)
    IF projected_recovery < 34:
      plan.days[t_plus_1].type = .rest
    ELSE IF projected_recovery < 67:
      plan.days[t_plus_1].type = .mobility
    // ELSE: leave open for normal training

  // Step 4: Assign training split to remaining days
  open_days = days WHERE type == nil
  training_days_needed = split_days_per_week(input.training_split)

  // Remove days needed for rest (at least 1 per week)
  IF open_days.count > training_days_needed:
    // Mark excess days as rest, preferring Sunday
    rest_days_needed = open_days.count - training_days_needed
    FOR i in 0..<rest_days_needed:
      // Prefer Sunday, then day after hardest training day
      best_rest_day = find_optimal_rest_day(open_days, plan)
      plan.days[best_rest_day].type = .rest
      open_days.remove(best_rest_day)

  // Assign split types to remaining open days
  split_sequence = get_split_sequence(input.training_split)
  // PPL: [.push, .pull, .legs, .push, .pull, .legs]
  // Upper/Lower: [.upper, .lower, .upper, .lower]
  // Full Body: [.fullBody, .fullBody, .fullBody]

  // Respect constraints:
  // - No legs on T-1 days (swap with another day)
  // - Same muscle group needs 48h gap
  // - Running goes on non-weight-training days with green recovery

  assigned_index = 0
  FOR day IN open_days SORTED BY priority:
    IF assigned_index >= split_sequence.count: BREAK

    workout_type = split_sequence[assigned_index]

    // Check T-1 constraint
    IF day.flag == .legProtected AND workout_type == .legs:
      // Swap: find another day for legs, use a different split for today
      swap_result = find_leg_swap(open_days, plan, assigned_index, split_sequence)
      IF swap_result.success:
        workout_type = swap_result.replacement_for_today
      ELSE:
        // Cannot fit legs this week -- accept it
        workout_type = .push  // or .pull, whichever is more needed
        log_adjustment("Legs skipped this week -- football schedule conflict")

    plan.days[day].type = workout_type
    assigned_index += 1

  // Step 5: Schedule running on remaining open days (if any)
  FOR day IN open_days WHERE plan.days[day].type == nil:
    projected_recovery = estimate_recovery_for_day(day, input)
    IF projected_recovery >= 67 AND NOT is_t_minus_1(day):
      plan.days[day].type = .run
    ELSE IF projected_recovery >= 34:
      plan.days[day].type = .mobility
    ELSE:
      plan.days[day].type = .rest

  // ============================================================
  // PHASE 2: GENERATE EXERCISES FOR EACH DAY
  // ============================================================

  FOR day_plan IN plan.days WHERE day_plan.type IN [.push, .pull, .legs, .upper, .lower, .fullBody]:

    exercises = []
    target_duration = input.preferred_duration_minutes
    recovery_zone = day_plan.recovery_zone

    // Step 6: Select exercises
    exercise_pool = get_exercises_for_type(day_plan.type, input.equipment_available)
    exercise_pool = filter_out_disliked(exercise_pool, input.user_preferences)
    exercise_pool = filter_out_injured(exercise_pool, input.user_preferences.injury_flags)

    // Prioritize compound movements first, isolation last
    compounds = exercise_pool.filter { $0.isCompound }.sorted_by_priority()
    isolations = exercise_pool.filter { !$0.isCompound }.sorted_by_priority()

    // Select 2-3 compounds + 2-4 isolations based on duration
    num_compounds = (target_duration >= 50) ? 3 : 2
    num_isolations = (target_duration >= 50) ? 3 : 2

    // Exercise selection scoring
    FOR exercise IN compounds:
      score = 0
      score += recency_bonus(exercise, input.exercise_history)  // prefer exercises not done in last 7 days
      score += progression_bonus(exercise, input.progression_state)  // prefer exercises due for progression
      score += preference_bonus(exercise, input.user_preferences)  // prefer favorites
      score += variety_bonus(exercise, this_week_exercises)  // avoid same exercise 2x in 1 week
      score += muscle_coverage_bonus(exercise, selected_exercises)  // ensure all target muscles are hit
      exercise.selection_score = score

    selected_compounds = compounds.sorted_by_score().take(num_compounds)
    selected_isolations = isolations.sorted_by_score().take(num_isolations)

    all_selected = selected_compounds + selected_isolations

    // Step 7: Determine sets, reps, and weight for each exercise
    FOR exercise IN all_selected:
      prog_state = input.progression_state[exercise.id]

      // Base prescription from exercise defaults
      base_sets = exercise.defaultSets
      base_reps = exercise.defaultReps
      base_weight = prog_state?.currentWorkingWeight ?? estimate_starting_weight(exercise, input)

      // Apply recovery adjustments
      IF recovery_zone == .yellow_moderate:  // 50-66%
        base_sets = max(2, base_sets - 1)  // -20% volume (1 fewer set)
      ELSE IF recovery_zone == .yellow_low:  // 34-49%
        base_sets = max(2, base_sets - 1)
        base_weight = round_to_increment(base_weight * 0.95, exercise.weightIncrementKg)  // -5%
      // Red recovery: entire workout would have been swapped already

      // Apply deload adjustments (must respect the user's chosen deload type from Section 19.3)
      IF is_deload_week(input):
        deload_type = input.deload_preference  // .volume, .intensity, or .activeRecovery
        IF deload_type == .volume:
          // Volume Deload: same weight, ~40% fewer sets (per Pritchard 2015 tapering literature)
          // NOTE: -40% volume, NOT -50%. Maintaining intensity while reducing volume by ~40%
          // is the most evidence-supported deload strategy (Bosquet et al., 2007 meta-analysis).
          base_sets = max(2, round(base_sets * 0.60))  // -40% volume
          // Weight stays at 100% -- this preserves neuromuscular coordination
        ELSE IF deload_type == .intensity:
          // Intensity Deload: same sets, 60% of working weight
          base_weight = round_to_increment(base_weight * 0.60, exercise.weightIncrementKg)
          // Sets unchanged -- maintains movement volume
        ELSE IF deload_type == .activeRecovery:
          // No resistance training at all -- this branch should not reach here
          // (active recovery weeks replace the entire workout with mobility)

      // Apply progressive overload (green days only)
      IF recovery_zone == .green AND NOT is_deload_week(input):
        IF should_increase_weight(prog_state):
          base_weight += exercise.weightIncrementKg
          log_adjustment("Increased {exercise.name} from {old} to {base_weight}kg")

      exercises.append(PlannedExercise(
        exercise: exercise,
        target_sets: base_sets,
        target_reps: base_reps,
        target_weight: base_weight,
        rest_seconds: adjusted_rest(exercise, recovery_zone)
      ))

    // Step 8: Order exercises
    // Rule: compounds first, isolation last
    // Rule: most demanding (CNS) exercises first when user is freshest
    // Rule: supersets pair a compound with an isolation, or two non-competing isolations
    exercises.sort_by { fatigue_order_score($0) }

    // Step 9: Generate supersets (if enabled)
    IF input.user_preferences.include_supersets:
      exercises = create_supersets(exercises, input.user_preferences.superset_preference)
      // Time-saver: pair non-competing muscles (e.g., chest + rear delt)
      // Aggressive: pair antagonist muscles (e.g., bicep + tricep)

    // Step 10: Add warm-up sets (if enabled)
    IF input.user_preferences.include_warmups:
      FOR exercise IN exercises WHERE exercise.exercise.isCompound:
        warmups = generate_warmup_sets(exercise.target_weight, exercise.exercise)
        exercises.insert(warmups, before: exercise)

    // Step 11: Generate cooldown recommendation
    day_plan.cooldown = generate_cooldown(day_plan.type)
    // Push/Pull: upper body stretching (5 min)
    // Legs: lower body stretching + foam roll (10 min)
    // Full Body: full body stretching (8 min)

    day_plan.exercises = exercises
    day_plan.estimated_duration = calculate_duration(exercises)

  RETURN plan


// ============================================================
// HELPER: Fatigue Management Within a Session
// ============================================================

FUNCTION fatigue_order_score(exercise) -> Int:
  // Lower score = earlier in the workout
  score = 0

  // Compounds before isolations
  IF exercise.isCompound: score -= 100

  // Free weight before machine (more stabilizer demand when fresh)
  IF exercise.equipment IN [.barbell, .dumbbell]: score -= 50

  // Higher CNS demand first
  IF exercise.exercise IN [backSquat, deadlift, benchPress, overheadPress]: score -= 200

  // Bodyweight compound (pull-ups, dips) mid-session
  IF exercise.equipment == .bodyweight AND exercise.isCompound: score -= 25

  // Isolation and machine exercises last
  IF !exercise.isCompound: score += 50
  IF exercise.equipment == .machine: score += 25

  RETURN score


// ============================================================
// HELPER: Warm-Up Set Generation
// ============================================================

FUNCTION generate_warmup_sets(working_weight, exercise) -> [PlannedExercise]:
  warmups = []
  bar_weight = exercise.barType?.weight ?? 0

  IF working_weight <= 60:
    // 2 warm-up sets
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.50), reps: 8))
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.75), reps: 6))
  ELSE IF working_weight <= 100:
    // 2 warm-up sets
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.50), reps: 8))
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.75), reps: 5))
  ELSE:
    // 3 warm-up sets for heavy lifts (>100kg working weight)
    // Ramp progressively to minimize fatigue while priming the nervous system.
    // Per NSCA guidelines, warm-up sets should decrease in reps as weight increases.
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.40), reps: 8))
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.65), reps: 4))
    warmups.append(warmup_set(weight: round_to_plates(working_weight * 0.80), reps: 2))

  // First warm-up is always at least bar weight
  warmups[0].weight = max(bar_weight, warmups[0].weight)

  RETURN warmups


// ============================================================
// HELPER: Cooldown Recommendation
// ============================================================

FUNCTION generate_cooldown(workout_type) -> Cooldown:
  SWITCH workout_type:
    CASE .push, .pull:
      RETURN Cooldown(
        name: "Upper Body Cooldown",
        duration: 5,
        exercises: ["Chest doorway stretch (30s each side)",
                    "Lat hang from pull-up bar (30s)",
                    "Cross-body shoulder stretch (30s each)",
                    "Tricep overhead stretch (30s each)"]
      )
    CASE .legs:
      RETURN Cooldown(
        name: "Lower Body Cooldown",
        duration: 10,
        exercises: ["Quad stretch standing (45s each)",
                    "Hamstring stretch seated (45s each)",
                    "Hip flexor stretch half-kneeling (45s each)",
                    "Calf stretch wall (30s each)",
                    "Foam roll quads + hamstrings (3 min)"]
      )
    CASE .upper, .fullBody:
      RETURN Cooldown(
        name: "Full Body Cooldown",
        duration: 8,
        exercises: ["World's greatest stretch (5 each side)",
                    "Chest stretch (30s each)",
                    "Lat stretch (30s each)",
                    "Quad stretch (30s each)",
                    "Hamstring stretch (30s each)"]
      )
```

### 15.5 Volume Distribution Guidelines

Target weekly volume per muscle group (sets per week, per Schoenfeld 2017):

| Muscle Group | Beginner | Intermediate | Advanced |
|-------------|----------|-------------|----------|
| Chest | 6-8 sets | 10-14 sets | 16-20 sets |
| Back | 8-10 sets | 12-16 sets | 18-22 sets |
| Shoulders (side/rear) | 4-6 sets | 8-12 sets | 14-18 sets |
| Biceps | 4-6 sets | 8-10 sets | 12-16 sets |
| Triceps | 4-6 sets | 6-10 sets | 10-14 sets |
| Quadriceps | 6-8 sets | 10-14 sets | 16-20 sets |
| Hamstrings | 4-6 sets | 8-12 sets | 12-16 sets |
| Glutes | 4-6 sets | 8-12 sets | 12-16 sets |
| Calves | 4-6 sets | 8-10 sets | 12-16 sets |
| Core | 2-4 sets | 4-6 sets | 6-8 sets |

The algorithm distributes these across the week's training days, ensuring no single session exceeds ~25 working sets total (point of diminishing returns per Wernbom 2007).

### 15.6 Rest Time Guidelines (Evidence-Based)

Rest periods between sets are prescribed based on the training goal and exercise type. Schoenfeld et al. (2016) demonstrated that longer rest periods (3 minutes) between sets produced greater strength gains and hypertrophy than shorter rest periods (1 minute) in trained men performing compound movements. However, for isolation movements targeting hypertrophy, shorter rest periods are sufficient because the systemic fatigue is lower.

| Exercise Category | Goal | Rest Period | Evidence |
|---|---|---|---|
| Heavy compound (Squat, Deadlift, Bench, OHP) at RPE 8+ | Strength | 150-180s (2.5-3 min) | Schoenfeld et al. (2016): 3 min rest > 1 min for both strength and hypertrophy in compounds |
| Moderate compound (Rows, Lunges, RDL) at RPE 7-8 | Strength-Hypertrophy | 120-150s (2-2.5 min) | De Salles et al. (2009): 2-3 min for multi-joint exercises |
| Isolation exercises (Curls, Extensions, Flies) | Hypertrophy | 60-90s (1-1.5 min) | Willardson (2006): 1-2 min sufficient for single-joint exercises; shorter rest increases metabolic stress |
| Core exercises | Endurance/Stability | 30-60s | Low CNS demand; shorter rest maintains training density |
| Supersets (non-competing) | Time efficiency | 60-90s between pairs | Paz et al. (2017): non-competing supersets maintain performance with reduced session duration |

**Recovery zone adjustment**: When recovery is Yellow (34-66%), add 30 seconds to all rest periods. This accounts for reduced work capacity and ensures adequate phosphocreatine replenishment between sets (Harris et al., 1976: PCr resynthesis follows an exponential curve, reaching ~85% at 2 min and ~95% at 3 min).

---

## 16. Progressive Overload Logic

### 16.1 Core Algorithm -- When to Increase Weight

**The 2-of-3 Rule**: The algorithm evaluates the last 3 sessions of each exercise and requires 2 successful sessions before progressing the weight. This is a practical heuristic adapted from the ACSM's position stand on progression (Kraemer & Ratamess, 2004), which recommends load increases of 2-10% "when a target number of repetitions can be completed for a given number of sets." The ACSM guideline does not specify an exact session count; the 2-of-3 threshold was chosen to tolerate day-to-day performance variability (bad sleep, accumulated fatigue from football, menstrual cycle effects in female users) while still enforcing a meaningful consistency standard.

**Evidence level**: Moderate. No RCT directly validates the 2-of-3 rule against alternative thresholds (e.g., 2-of-2, 3-of-3, or 3-of-4). The EXERCISE_SCIENCE.md Algorithm Validation (Section 9.2) rates this as "Moderate -- the 2-of-3 threshold is a practical heuristic; no direct RCT validates this specific rule." It remains the best balance of progression speed vs. premature load increases, and is consistent with the general autoregulation literature (Helms et al., 2018). If a user finds it too conservative or too aggressive, the algorithm's behavior can be indirectly modulated via the RPE adjustments in Section 16.3.

```
FOR each exercise in the workout plan:
  recent_sessions = last 3 sessions of this exercise

  IF recent_sessions.count < 2:
    KEEP current prescription (not enough data)
    RETURN

  target_sets = prescribed number of working sets
  target_reps = prescribed rep target

  # Count "successful" sessions
  # A session is successful if ALL prescribed working sets hit the target rep count.
  successful_count = 0
  FOR each session in recent_sessions:
    completed_sets = sets where reps >= target_reps
    IF completed_sets >= target_sets:
      successful_count += 1

  # Decision
  IF successful_count >= 2 (out of last 3 sessions):
    INCREASE weight by standard_increment

  ELSE IF successful_count == 0:
    # User has failed target reps 3 sessions in a row
    IF avg_reps_across_sets < target_reps * 0.75:
      DECREASE weight by standard_increment
    ELSE:
      KEEP current weight (still adapting -- may be consolidating)
```

### 16.2 Standard Increments

| Exercise Category | Standard Increment | Minimum Increment |
|---|---|---|
| Barbell compounds (Bench, Squat, Deadlift, OHP, Row) | 2.5 kg (5 lbs) | 1.25 kg (2.5 lbs) |
| Dumbbell exercises | 2 kg (4 lbs) per hand | 1 kg (2 lbs) per hand |
| Cable/machine exercises | 2.5 kg (5 lbs) | 1 stack notch |
| Bodyweight exercises (weighted) | 2.5 kg (5 lbs) | 1.25 kg |
| Bodyweight (unweighted) | +1 rep to target | N/A |

When stuck at the same weight for 4+ consecutive sessions, the algorithm switches to **micro-loading** (minimum increment).

### 16.3 RPE-Informed Adjustments

- **Average RPE < 7**: Increase weight regardless of rep completion.
- **Average RPE 7-8**: Standard algorithm.
- **Average RPE 9-10**: Do NOT increase even if reps are hit. Flag for potential deload.

### 16.4 Recovery-Adjusted Progression

- **Green days**: Standard algorithm. Weight increases proceed.
- **Yellow days**: No new weight increases. Defer to next green session.
- **Red days**: Mobility/recovery, no weight training.

### 16.5 Missed Week Handling

| Days Since Last Session | Action |
|------------------------|--------|
| 7-14 days | Resume at -10%. One re-introduction session. |
| 14-28 days | Resume at -20%. Two re-introduction sessions. |
| 28+ days | Resume at -30%. Reset progression. |

### 16.6 Per-Exercise Progression Display

```
+-----------------------------------------+
|  PROGRESSION STATUS                      |
|                                          |
|  Current working weight: 85kg           |
|  Target: 4 x 8                          |
|  Sessions at this weight: 2             |
|  Successful sessions: 2 of 2            |
|                                          |
|  [up] Scheduled to increase to          |
|    87.5kg next session                   |
|                                          |
|  OR                                      |
|                                          |
|  [pause] Increase deferred -- waiting   |
|    for green recovery day                |
+-----------------------------------------+
```

---

## 17. Recovery-Based Adjustment Algorithm

### 17.1 Data Sources

| Source | Data | Update Frequency |
|--------|------|-----------------|
| Whoop (via HealthKit / Whoop API) | Recovery %, HRV, Resting HR, Sleep Performance, Strain | Daily (morning sync) |
| Apple Health (HealthKit) | Heart rate, active calories, sleep analysis | Continuous |
| Training History (local) | Yesterday's workout, volume, RPE | After each session |
| Calendar (EventKit) | Football schedule, other commitments | Real-time |

### 17.2 Recovery Score Interpretation

#### GREEN (>=67%) -- Full Volume
- Volume: 100%. Intensity: 100%. No swaps.
- Progressive overload: Active.
- **Sub-levels**: 80-89% may suggest bonus set. 90-100% may suggest PR attempt.

#### YELLOW (34-66%) -- Reduced
- Volume: -20% (1 fewer set per exercise, min 2 sets).
- Intensity: -5% on working weight (50-66% sub-range: volume only; 34-49%: volume + intensity + compound swaps).
- Compound swaps: Squat -> Leg Press, Deadlift -> RDL/Machine, OHP -> Machine Press.
- Progressive overload: Paused.
- Rest times: +30 seconds.

#### RED (<34%) -- Mobility/Rest
- Swap entire workout to 25-min mobility session.
- Weight workout deferred to next available day.
- If user overrides: -40% volume, -15% intensity, all compounds swapped to machines, warning displayed, session flagged.

### 17.3 Transparency

Every adjustment explained in the Recovery Detail Sheet. Shows: recovery score, HRV, resting HR, sleep data, what changed, and why.

Override options: "I Feel Great" (promotes to Green) and "I Feel Worse" (demotes to Red).

### 17.4 Historical Learning

Over time, the algorithm tracks:
1. Override frequency -- if >50% overrides, suggest lowering sensitivity.
2. Post-override performance -- validate recommendations.
3. Football recovery patterns -- adjust post-match restrictions.
4. Sleep correlation -- surface insights.

Weekly "Training Insights" section in settings.

---

## 18. Football Integration (Deep Dive)

### 18.1 Overview

Football (soccer) is the highest-priority calendar event. Every training decision respects the football schedule. This section specifies exactly how each day relative to a match is handled.

### 18.2 Day-by-Day Specification

#### T-2 (Two Days Before Match)

**Example**: Match on Wednesday, T-2 = Monday.

**Allowed**:
- Full upper body weight training (push or pull day)
- Light to moderate leg training (IF the user's legs are the focus AND there is no alternative scheduling)
- Easy running (Zone 1-2, max 30 min)
- Full core training
- All mobility work

**Restricted**:
- No heavy squats or deadlifts (reserve for 48h+ before match)
- No high-volume leg sessions (12+ leg sets)
- No interval/tempo runs (save legs)
- No plyometrics (box jumps, sprints)

**Algorithm behavior**:
- If training split calls for Leg Day: allow it but reduce volume by 25% and swap heavy barbell compounds for machines/dumbbells.
- If training split calls for Push or Pull: proceed normally.
- Recovery must be Green. If Yellow: reduce volume. If Red: mobility.

#### T-1 (Day Before Match)

**Example**: Match on Wednesday, T-1 = Tuesday.

**Allowed**:
- Upper body weight training only (push or pull)
- Light mobility / foam rolling
- Light activation work (banded glute bridges, core activation)
- Walking

**BANNED** (absolute, no override):
- Barbell Back Squat (any weight)
- Barbell Front Squat (any weight)
- Leg Press (heavy -- >60% of max)
- Barbell Deadlift (any variation)
- Romanian Deadlift (heavy)
- Bulgarian Split Squat
- Walking Lunge
- Hip Thrust (heavy)
- Box Jump / Plyometrics
- Interval Run / Tempo Run / Hill Sprints
- Sprint Drills

**Allowed leg exercises** (light/maintenance):
- Leg Extension (light to moderate, RPE < 6)
- Leg Curl (light to moderate, RPE < 6)
- Calf Raises (any weight)
- Bodyweight squats (warm-up only)
- Glute Bridge (bodyweight activation)
- Single-Leg Balance drills
- Banded lateral walks

**Algorithm behavior**:
- If split calls for Leg Day: swap entirely. PPL -> swap to Push or Pull (whichever is due). Upper/Lower -> swap to Upper. Full Body -> remove all heavy leg exercises, replace with upper body.
- Display info banner: "Football tomorrow -- legs protected. Upper body focus."
- Running: easy/recovery pace ONLY, max 20 minutes, Zone 1.

#### T-0 (Match Day)

**Allowed**:
- Pre-match preparation session (25 min, user-initiated):
  1. Foam Roll - Lower Body (10 min)
  2. Dynamic Stretching (8 min)
  3. Activation - Glutes/Core (7 min)
- Football match itself (logged as "Football" workout)

**BANNED** (absolute):
- Any weight training
- Any running workout
- Any mobility session longer than 30 minutes (save energy)

**Algorithm behavior**:
- Day type is locked to .football. No weight workout generated.
- Optional pre-match prep is presented but not required.
- Post-match: Whoop strain data is captured for recovery estimation.

#### T+1 (Day After Match)

**Example**: Match on Wednesday, T+1 = Thursday.

**Behavior is recovery-dependent**:

| Recovery | Workout | Notes |
|----------|---------|-------|
| Green (>=67%) | Upper body workout only (prefer Pull day) | Even with Green HRV, neuromuscular function is impaired for 48-72h post-match (Nedelec et al., 2012). No lower body resistance training on T+1 regardless of recovery score. |
| Yellow (50-66%) | Reduced workout (-20% volume) | Light upper body or mobility |
| Yellow (34-49%) | Mobility session only | 25-min foam roll + stretching |
| Red (<34%) | Rest day (forced) | "Your body needs recovery after yesterday's match." |

**Running**: Only if Green recovery. Easy pace ONLY, max 20 minutes. The goal is active recovery, not training stimulus.

**Lower body on T+1**: Absolutely no lower body resistance training on T+1, even with Green recovery. Neuromuscular markers (peak torque, rate of force development, countermovement jump height) remain significantly depressed at 24h post-match and do not fully recover until 48-72h (Nedelec et al., 2012; Ispirlidis et al., 2008). HRV may recover faster than neuromuscular function, making the recovery score misleading for lower body readiness on T+1.

**Algorithm logic**: Football acts as a leg stimulus. The algorithm counts a football match as equivalent to 5 sets of quad work, 4 sets of hamstring work, 4 sets of calf work, and 3 sets of glute work for the purpose of weekly volume tracking (see Section 18.3). This means: if the user plays football 2x/week, they may only need 1 dedicated leg session to maintain intermediate-level weekly volume targets.

#### T+2 (Two Days After Match)

**Example**: Match on Wednesday, T+2 = Friday.

**Behavior**: Essentially normal, with one consideration:
- If T+1 was a rest/mobility day (recovery was Red/Yellow), T+2 becomes the first training day back. Start with the highest-priority workout from the split.
- Leg training is allowed if recovery is Green.
- Full running is allowed if recovery is Green.

### 18.3 Two Matches Per Week Scheduling

When football is on both Wednesday and Saturday (common amateur schedule):

```
MON: Leg Day (only window: 2 days after Sat match, 2 days before Wed match)
     CRITICAL: Must be Green recovery. If Yellow: reduced legs. If Red: skip legs.
TUE: Push Day (T-1 for Wednesday -- upper body only)
WED: FOOTBALL (match day)
THU: Recovery/Mobility (T+1 -- almost always Yellow or Red)
FRI: Pull Day (T-1 for Saturday -- upper body only)
SAT: FOOTBALL (match day)
SUN: REST (T+1 -- recovery day)
```

**Key insight**: With 2 matches/week, the user gets exactly ONE potential leg day (Monday). If Monday's recovery is poor, legs get skipped entirely for the week. This is acceptable because football provides significant lower body stimulus. The algorithm does NOT force leg training when it would compromise match performance.

**Volume tracking adjustment**: The algorithm counts each 90-min football match as:
- 5 sets equivalent of quad work
- 4 sets equivalent of hamstring work
- 4 sets equivalent of calf work
- 3 sets equivalent of glute work

NOTE: These are conservative estimates. A football match involves high-volume locomotion (10-13 km per match per Bangsbo et al., 2006) with repeated sprints, decelerations, and direction changes, but the mechanical tension per contraction is far lower than resistance training. The stimulus is primarily metabolic and eccentric-deceleration, not concentric overload. Overestimating match volume credit risks under-prescribing gym-based leg work, which provides the progressive overload stimulus that football alone cannot. For a footballer playing 2x/week, these credits total 10 quad sets and 8 hamstring sets -- combined with one dedicated gym leg session at 6-8 sets, this places total weekly volume in the intermediate range (16-18 quad sets, 14-16 hamstring sets) which is appropriate.

This is added to the weekly volume tracker so the user does not see "low leg volume" warnings when they are playing football twice a week.

### 18.4 Calendar Integration

- Football days are set in Training Settings (recurring) or pulled from iOS Calendar (EventKit) if the user has a "Football" calendar.
- If the user adds/removes a football day mid-week, the plan regenerates immediately.
- If a match is cancelled, the user can convert the day to a regular training day via manual override.

---

## 19. Deload Week Specification

### 19.1 Overview

A deload is a planned period of reduced training stress that allows physiological and psychological recovery. It is NOT a break from training -- it is strategic lighter training that maintains movement patterns while allowing adaptation. Research supports deloading every 3-6 weeks for intermediate and advanced lifters (Zourdos 2016).

### 19.2 When Triggered

**Automatic triggers** (any one of these):
1. **Time-based**: 4-6 consecutive weeks of training without a deload (configurable, default 5 weeks).
2. **Stall-based**: 3+ exercises have stalled (no weight increase) for 6+ consecutive sessions.
3. **Recovery-based**: Whoop recovery has been yellow/red for 5+ of the last 7 days.
4. **RPE-based**: Average RPE across all exercises has been 9+ for 3 consecutive sessions (chronic overreaching).

**Manual triggers**:
- User selects "Start Deload Week" in Training Settings.
- AI proactively suggests it via a notification: "Your body is showing signs of accumulated fatigue. Consider a deload this week."

### 19.3 Three Deload Options

The user's preferred deload type is set in Training Settings. The algorithm uses this preference, but the user can change it when a deload is triggered.

#### Option A: Volume Deload (Default)

- **Concept**: Same weights, fewer sets. Maintain intensity, reduce volume.
- **Weight**: 100% of current working weight (no change). This is critical -- maintaining intensity preserves neuromuscular coordination and the strength adaptations built during the accumulation block.
- **Sets**: ~40% reduction (e.g., 4x8 becomes 2-3x8). Minimum 2 working sets per exercise. The 40% reduction is supported by Bosquet et al. (2007) meta-analysis on tapering, which found that volume reductions of 40-60% maximized performance supercompensation, and Pritchard et al. (2015), which showed that maintaining intensity while reducing volume improved 1RM by 2-4%. The previous -50% figure was overly aggressive; 40% provides sufficient fatigue dissipation while keeping the training stimulus meaningful.
- **Reps**: Same as normal.
- **RPE target**: 6-7 (should feel moderate but not challenging).
- **Rest**: Same as normal.
- **Exercise selection**: Same exercises as normal week. No swaps.
- **Duration**: Same time slots, but sessions are ~40% shorter.
- **Rationale**: Maintains neuromuscular coordination and technique at full intensity, while reducing total training stress enough to dissipate accumulated fatigue. Preferred by powerlifters and evidence-supported as the most effective deload strategy for strength maintenance.

#### Option B: Intensity Deload

- **Concept**: Same volume, lighter weights.
- **Weight**: 60% of current working weight.
- **Sets**: Same as normal (no reduction).
- **Reps**: Same as normal (may even increase slightly: if normally 4x8, could do 4x10 at lighter weight).
- **RPE target**: 5-6 (should feel easy).
- **Rest**: Reduced by 30 seconds (lighter weight = faster recovery).
- **Exercise selection**: Same exercises.
- **Duration**: Slightly shorter (less rest).
- **Rationale**: Maintains movement volume and technique practice with significantly less mechanical stress. Preferred by bodybuilders and hypertrophy-focused lifters.

#### Option C: Active Recovery Week

- **Concept**: Different activities entirely. No weight training.
- **Sessions**: 3-4 per week, each 25-35 minutes.
- **Activities**: Mobility flows, yoga, easy runs (Zone 1), swimming, cycling (easy), foam rolling.
- **No weight training at all** (complete CNS break).
- **RPE target**: 3-4 (effort should be minimal).
- **Rationale**: Complete break from resistance training. Psychological recovery is as important as physical. For users showing signs of burnout or chronic fatigue.

### 19.4 How Deload Week is Presented

**Trigger notification** (push notification + in-app banner):
- "Time for a strategic recovery week. You've trained hard for 5 weeks -- your muscles grow during rest, not during training. This is not weakness, this is how you get stronger."

**Today's Workout View during deload**:
- All cards have `deloadBlue` left accent bar.
- Banner at top: "DELOAD WEEK -- Strategic recovery. Lighter weights, fewer sets. Trust the process."
- Workout title prefix: "DELOAD --" (e.g., "DELOAD -- PUSH DAY").
- START WORKOUT button is `deloadBlue` instead of `primary`.
- Recovery badge reads "DELOAD WEEK" instead of the recovery score.

**Week Plan View during deload**:
- All day cells have `deloadBlue` bottom accent.
- Grid header: "DELOAD WEEK" in `deloadBlue`.

**During active workout**:
- Header bar shows "DELOAD -- PUSH DAY" in `deloadBlue`.
- RPE guidance below RPE circles: "Target RPE: 5-6 this week" in `deloadBlue`.
- Weight displays show deload weight with a small note: "(60% of working weight)" in `caption`, `deloadBlue`.
- If user tries to increase weight past the deload target (via stepper), soft warning: "Deload week -- keep it light. The goal is recovery."

**Psychological framing**:
- NEVER use words like "easy week" or "light week" (implies laziness).
- ALWAYS frame as "strategic recovery," "planned adaptation," "growth phase."
- Show progress context: "Your bench press has increased 10kg in 5 weeks. This deload lets your body consolidate those gains."
- After deload: "Deload complete. You should feel fresh and ready. Expect your next session to feel strong."

### 19.5 Post-Deload

- Resume at the weight BEFORE the deload (not the deload weight).
- Progressive overload algorithm resets its evaluation window (does not count deload sessions).
- First post-deload session is monitored closely: if RPE is high, the deload may not have been sufficient.
- User sees: "Back to full training. First session back -- your body should feel recovered and ready."

---

## 20. Import / Export System

### 20.1 Export Format

Tempo exports workout history as CSV. The file is UTF-8 encoded with headers on the first row.

**Tempo CSV Format**:
```
Date,Workout Name,Exercise Name,Set Number,Set Type,Weight (kg),Reps,Duration (s),Distance (m),RPE,Rest (s),Notes
2026-03-24,Push Day,Barbell Bench Press,1,Warm-up,40,8,,,,
2026-03-24,Push Day,Barbell Bench Press,2,Warm-up,60,6,,,,
2026-03-24,Push Day,Barbell Bench Press,3,Working,85,8,,,7,,
2026-03-24,Push Day,Barbell Bench Press,4,Working,85,8,,,8,,
2026-03-24,Push Day,Barbell Bench Press,5,Working,85,7,,,9,,
2026-03-24,Push Day,Barbell Bench Press,6,Working,85,8,,,8,,
2026-03-24,Push Day,Incline DB Press,1,Working,32,10,,,7,,
2026-03-24,Push Day,Incline DB Press,2,Working,32,10,,,8,,
2026-03-24,Push Day,Incline DB Press,3,Working,32,9,,,9,,
2026-03-24,Easy Run,,,,,,1722,5020,,,
```

**Column definitions**:
- **Date**: ISO 8601 date (YYYY-MM-DD)
- **Workout Name**: User-facing name of the workout session
- **Exercise Name**: Full exercise name as it appears in the library
- **Set Number**: Sequential set number within that exercise (1-based)
- **Set Type**: "Warm-up", "Working", "Drop", "Superset"
- **Weight (kg)**: Weight in kilograms. Empty for bodyweight or cardio.
- **Reps**: Rep count. Empty for timed or distance exercises.
- **Duration (s)**: Duration in seconds. Used for timed holds (plank) and cardio.
- **Distance (m)**: Distance in meters. Used for running and rowing.
- **RPE**: Rate of perceived exertion (6-10). Empty if not recorded.
- **Rest (s)**: Rest time after this set in seconds. Empty if not recorded.
- **Notes**: Free text. Quoted if contains commas.

**Export trigger**: Training Settings > Export Workout History. Generates file, presents iOS share sheet.

### 20.2 Strong App Import

Strong exports CSV with this format:
```
Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
```

**Mapping**:
| Strong Column | Tempo Column | Notes |
|--------------|-------------|-------|
| Date | Date | Parse MM/DD/YYYY or YYYY-MM-DD |
| Workout Name | Workout Name | Direct map |
| Exercise Name | Exercise Name | Fuzzy match to library (see below) |
| Set Order | Set Number | Direct map |
| Weight | Weight (kg) | Detect units from data (if values > 200, likely lbs -- convert) |
| Reps | Reps | Direct map |
| Distance | Distance (m) | Convert if in miles |
| Seconds | Duration (s) | Direct map |
| Notes | Notes | Direct map |
| RPE | RPE | Direct map |

**Exercise name fuzzy matching**:
1. Exact match (case-insensitive): "Barbell Bench Press" -> Barbell Bench Press
2. Partial match: "Bench Press (Barbell)" -> Barbell Bench Press
3. Common aliases: "Flat Bench Press" -> Barbell Bench Press, "Lat Pull Down" -> Lat Pulldown
4. Unmatched: Create as custom exercise with a note "Imported from Strong"

### 20.3 Hevy App Import

Hevy exports CSV with this format:
```
title,start_time,end_time,description,exercise_title,superset_id,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
```

**Mapping**:
| Hevy Column | Tempo Column | Notes |
|------------|-------------|-------|
| title | Workout Name | Direct map |
| start_time | Date | Parse ISO 8601 datetime |
| exercise_title | Exercise Name | Same fuzzy matching as Strong |
| superset_id | Superset group | Map to superset grouping |
| set_index | Set Number | Direct map |
| set_type | Set Type | Map: "normal"->"Working", "warmup"->"Warm-up", "dropset"->"Drop" |
| weight_kg | Weight (kg) | Direct map |
| reps | Reps | Direct map |
| distance_km | Distance (m) | Convert km to m |
| duration_seconds | Duration (s) | Direct map |
| rpe | RPE | Direct map |

### 20.4 Generic CSV Import

For CSV files that do not match Strong or Hevy format:

1. App detects the CSV is not a known format.
2. Column mapping interface appears:
   ```
   +--------------------------------------+
   | MAP YOUR CSV COLUMNS                  |
   |                                       |
   | Your column: "date"                   |
   | Maps to: [Date]              [v]     |
   |                                       |
   | Your column: "exercise"               |
   | Maps to: [Exercise Name]     [v]     |
   |                                       |
   | Your column: "weight_lbs"             |
   | Maps to: [Weight (kg)]       [v]     |
   | Unit: [lbs -> auto convert]          |
   |                                       |
   | ...                                   |
   |                                       |
   | [Preview Import]  [Import]            |
   +--------------------------------------+
   ```
3. Each CSV column gets a dropdown mapping to Tempo fields.
4. Unit detection: if column name contains "lbs" or "lb", auto-suggest conversion.
5. "Preview Import" shows first 10 rows with mapped values for verification.

### 20.5 Conflict Resolution

When importing, conflicts can arise:

| Conflict | Resolution |
|----------|-----------|
| Exercise already exists in library | Use existing exercise. Do not create duplicate. |
| Workout date already has a logged workout | Option: "Replace existing" or "Add alongside" (allows 2 workouts per day). |
| Weight in lbs but user setting is kg | Auto-convert. Show confirmation: "Detected lbs -- converting to kg." |
| Unknown exercise name | Create as custom exercise. Tag "Imported." |
| Corrupt/missing data in a row | Skip row. Show warning: "Skipped 3 rows with missing data." |
| Duplicate rows | Deduplicate by (date + exercise + set number). Keep first occurrence. |

### 20.6 Data Validation

Before import is finalized:
- **Weight range check**: Flag any set with weight > 500kg or < 0.
- **Rep range check**: Flag reps > 100 or < 0.
- **Date range check**: Flag dates in the future or before 2000.
- **Summary**: "Importing 234 workouts, 4,680 sets, spanning Jan 2024 - Mar 2026. 3 exercises will be created as custom."
- **Import is reversible**: "Undo Import" available for 24 hours after import (soft-delete flag on imported records).

---

## 21. Apple Watch Companion

### 21.1 Overview

The Apple Watch companion enables workout logging directly from the wrist. It is NOT a full replacement for the phone app -- it is a simplified interface for the most common actions: logging sets, tracking rest timers, and viewing the current exercise.

### 21.2 Watch App Architecture

- **Framework**: WatchKit + SwiftUI (watchOS 10+)
- **Communication**: WatchConnectivity framework for real-time sync with iPhone app.
- **Standalone capability**: Watch app CAN operate independently if iPhone is not nearby (cached workout plan on watch). Syncs when reconnected.
- **HealthKit**: Watch writes workout data directly to HealthKit (heart rate during workout).

### 21.3 Complication

The Tempo complication appears on the watch face:

**Circular complication (small)**:
```
+--------+
|  PUSH  |
|  [bar] |
+--------+
```
- Shows today's workout type abbreviation (PSH, PUL, LEG, etc.).
- Small progress bar showing workout completion (0% if not started, fills during workout).
- Tap: Opens Tempo watch app.

**Modular large complication**:
```
+---------------------------+
|  PUSH DAY  *  6 exercises |
|  [check] 78% Recovery     |
+---------------------------+
```
- Workout name and exercise count.
- Recovery score with color dot.
- Tap: Opens Tempo watch app.

**Corner complication**:
- Just the workout type icon (dumbbell for weights, shoe for run, yoga for mobility).

### 21.4 Watch Workout View (Not Started)

```
+-------------------+
|     PUSH DAY      |
|                   |
|  6 exercises      |
|  ~52 min          |
|                   |
|  [G] 78%          |
|                   |
|  [START]          |
+-------------------+
```

- Scrollable list of exercises with names and set counts.
- START button: taps to begin (syncs with iPhone app if connected).
- Crown scrolls through exercises.

### 21.5 Watch Active Workout View

```
+-------------------+
|  BENCH PRESS      |
|  Set 2/4          |
|                   |
|  85kg x 8         |
|                   |
|  [  DONE  ]       |
|                   |
|  34:12            |
+-------------------+
```

**Components**:
- **Exercise name**: Top, `headline` style. Truncated if long.
- **Set counter**: "Set {n}/{total}" below name.
- **Target**: "{weight} x {reps}" in large text.
- **DONE button**: Large green button, minimum 44pt height (per Apple Watch HIG). Full width.
- **Timer**: Bottom, small, running workout timer.

**Interaction flow**:
1. User sees current exercise and target.
2. If the pre-filled weight/reps are correct (common case), user taps DONE. **One tap.**
3. Haptic: `.success` via `WKInterfaceDevice.default().play(.success)`.
4. Set logged. If not last set: rest timer starts on watch.
5. If user needs to adjust weight: Crown rotation adjusts weight (stepper behavior). Digital Crown turns = +/- standard increment. Haptic `.click` on each increment.
6. Force touch (or long press on watchOS 10+): Opens options menu: Skip Exercise, End Workout, Adjust Reps.

### 21.6 Watch Rest Timer

```
+-------------------+
|  RESTING          |
|                   |
|     2:34          |  <- Large countdown
|                   |
|  [ring progress]  |  <- Circular progress
|                   |
|  [SKIP]           |
+-------------------+
```

- Circular progress ring fills as time passes (using WKInterfaceInlineMovie or SwiftUI animation).
- **Haptic at timer end**: `WKInterfaceDevice.default().play(.notification)` -- the Watch taps the wrist. This is the primary notification method (more reliable than looking at the phone).
- **10 seconds remaining**: Rapid haptic taps.
- **SKIP button**: Ends rest early.
- **Crown**: Adjusts rest time (+/- 15 seconds per click -- smaller increments on Watch due to Crown precision).

### 21.7 Watch Superset Flow

During supersets:
1. Exercise A set logged.
2. Watch immediately shows Exercise B (no rest timer). Banner: "SUPERSET" at top.
3. Exercise B set logged.
4. Rest timer starts.

### 21.8 Watch Workout Summary

After finishing:
```
+-------------------+
|  COMPLETE         |
|                   |
|  48:32            |
|  12,480 kg        |
|  24 sets          |
|                   |
|  [star] 2 PRs     |
|                   |
|  [DONE]           |
+-------------------+
```

- Minimal summary. Full details on iPhone.
- PR count shown with gold star.
- DONE dismisses and returns to watch face.

### 21.9 Watch-Phone Sync

- **Real-time**: When both devices are connected (Bluetooth/WiFi), every set logged on Watch immediately appears on iPhone (and vice versa). User can switch between devices mid-workout.
- **Offline**: If Watch is disconnected (gym without iPhone), workout is stored locally on Watch. When reconnected, data syncs automatically. Conflict resolution: Watch data wins if there is a time overlap (Watch was the active logging device).
- **Rest timer sync**: If rest timer is running on iPhone, Watch shows the same countdown. If started on Watch, iPhone reflects it.

### 21.10 Watch Battery Considerations

- Active workout session uses ~5-8% battery per hour (GPS off, heart rate on).
- If Watch battery < 10% during workout, a warning appears: "Low battery -- save your workout." Auto-save is aggressive (every set).
- Always-On Display shows workout timer even in AOD mode.

---

## Appendices

### Appendix A: Data Model (Key Entities)

```
WorkoutPlan
  - id: UUID
  - date: Date
  - type: WorkoutType (push, pull, legs, upper, lower, fullBody, run, mobility, football, rest, deload)
  - recoveryScore: Int? (0-100)
  - recoveryZone: RecoveryZone (green, yellow, red)
  - adjustments: [Adjustment]
  - status: PlanStatus (planned, active, completed, skipped, deferred)
  - exercises: [PlannedExercise]
  - isDeloadWeek: Bool

PlannedExercise
  - id: UUID
  - exercise: Exercise (reference)
  - orderIndex: Int
  - targetSets: Int
  - targetReps: Int (or targetDuration for timed)
  - targetWeight: Double?
  - isWarmUp: Bool
  - supersetGroup: String? ("A", "B", etc.)
  - circuitGroup: String?
  - isDropSet: Bool
  - dropWeights: [Double]?
  - notes: String?

Exercise
  - id: UUID
  - name: String
  - primaryMuscles: [MuscleGroup]
  - secondaryMuscles: [MuscleGroup]
  - equipment: Equipment
  - difficulty: Difficulty
  - movementPattern: MovementPattern
  - trackingType: TrackingType (weightReps, bodyweightReps, duration, distance)
  - defaultSets: Int
  - defaultReps: Int
  - defaultRestSeconds: Int
  - weightIncrement: Double
  - includeWarmUp: Bool
  - isCompound: Bool
  - barType: BarType?
  - isCustom: Bool
  - instructions: [String]
  - tips: [String]
  - commonMistakes: [String]
  - substitutes: [ExerciseID]
  - footballSafety: FootballSafety

CompletedWorkout
  - id: UUID
  - plan: WorkoutPlan (reference)
  - startTime: Date
  - endTime: Date
  - activeDuration: TimeInterval (excluding pauses)
  - totalVolume: Double (kg)
  - estimatedCalories: Int
  - notes: String?
  - personalRecords: [PersonalRecord]
  - sets: [CompletedSet]
  - isDeload: Bool
  - source: Source (.iPhone, .appleWatch)

CompletedSet
  - id: UUID
  - exercise: Exercise (reference)
  - setNumber: Int
  - weight: Double?
  - reps: Int?
  - rpe: Int? (6-10)
  - duration: TimeInterval?
  - distance: Double?
  - isWarmUp: Bool
  - setType: SetType (.working, .warmup, .drop, .superset, .circuit)
  - completedAt: Date

PersonalRecord
  - id: UUID
  - exercise: Exercise (reference)
  - type: PRType (estimated1RM, absolute1RM, repPR, volumePR, endurancePR)
  - value: Double
  - previousValue: Double
  - achievedAt: Date
  - formula: PRFormula? (.epley, .brzycki)

RunSession
  - id: UUID
  - completedWorkout: CompletedWorkout (reference)
  - distance: Double (meters)
  - avgPace: Double (seconds per km)
  - avgHeartRate: Int?
  - elevationGain: Double?
  - route: [CLLocationCoordinate2D]?
  - splits: [RunSplit]
  - hrZoneDistribution: [HRZone: TimeInterval]
  - estimatedVO2max: Double?

RunSplit
  - kilometer: Int
  - pace: Double (seconds per km)
  - avgHeartRate: Int?
  - hrZone: HRZone
  - elevationDelta: Double?

ProgressionState (per exercise)
  - exercise: Exercise (reference)
  - currentWorkingWeight: Double
  - sessionsAtWeight: Int
  - successfulSessions: Int
  - lastIncreasedDate: Date?
  - isStalled: Bool
  - consecutiveStallSessions: Int
  - isInDeload: Bool
  - lastDeloadDate: Date?

DeloadState
  - isActive: Bool
  - startDate: Date?
  - endDate: Date?
  - type: DeloadType (.volume, .intensity, .activeRecovery)
  - weeksSinceLastDeload: Int
  - trigger: DeloadTrigger (.timeBased, .stallBased, .recoveryBased, .rpeBased, .manual)

PlateConfiguration
  - barWeight: Double
  - availablePlates: [Double: Int]  // weight: quantity
  - unitSystem: UnitSystem
```

### Appendix B: Navigation Map

```
Tab Bar
+-- Training (tab)
    +-- Today's Workout View (root)
    |   +-- Start Workout -> Active Workout View
    |   |   +-- Exercise Demo (half-sheet)
    |   |   +-- Exercise List Drawer (bottom sheet)
    |   |   +-- Plate Calculator (bottom sheet)
    |   |   +-- Weight Scroll Wheel (inline)
    |   |   +-- Numeric Keypad (bottom sheet)
    |   |   +-- End Workout -> Workout Summary
    |   |   |   +-- Add Notes (inline)
    |   |   |   +-- Share Card (share sheet)
    |   |   |   +-- Save & Close -> Today's Workout View
    |   |   +-- Add Exercise -> Exercise Library (modal)
    |   +-- Swap Exercise (bottom sheet)
    |   |   +-- Browse Library -> Exercise Library (modal)
    |   +-- Add Exercise -> Exercise Library (modal)
    |   +-- Recovery Detail Sheet (bottom sheet)
    |   +-- Rest Day -> Mobility Flow / Custom Workout
    |   +-- Football Day -> Pre-Match Prep
    |   +-- Deload Banner -> Deload Detail Sheet
    +-- Week Plan View (from calendar icon)
    |   +-- Day Detail -> Today's Workout View (for that day)
    |   +-- Regenerate Plan
    +-- Progress Charts (from exercise history links)
    |   +-- Per Exercise -> Exercise Chart View
    |   +-- Muscle Groups -> Volume Analysis
    |   +-- Overview -> All-Time Stats
    +-- Exercise Library (from various entry points)
    |   +-- Exercise Detail View
    |   |   +-- View Full History -> Progress Charts
    |   |   +-- Plate Calculator (for barbell exercises)
    |   +-- Create Custom Exercise
    +-- Training Settings (from gear icon)
        +-- Training Split Selection
        +-- Football Schedule
        +-- Recovery Integration
        +-- Workout Preferences
        +-- Equipment Available
        +-- Plate Calculator Settings
        +-- Units & Display
        +-- Rest Timer Defaults
        +-- Deload Settings
        +-- PR Settings
        +-- Running Settings
        +-- Apple Watch Settings
        +-- Data Import/Export
            +-- Import from Strong
            +-- Import from Hevy
            +-- Import Generic CSV
            +-- Export History
```

### Appendix C: Gesture Summary

| Screen | Gesture | Action |
|--------|---------|--------|
| Today's Workout | Pull-to-refresh | Re-sync Whoop + recalculate |
| Today's Workout | Long-press exercise card | Drag-to-reorder |
| Today's Workout | Swipe left on exercise | Quick-delete (with undo) |
| Active Workout | Swipe left/right | Navigate exercises |
| Active Workout | Tap timer circle | Skip rest |
| Active Workout | Swipe left on completed set | Delete set |
| Active Workout | Long-press weight stepper | Rapid increment |
| Active Workout | Tap weight/reps value | Open keypad |
| Active Workout | Long-press weight value | Open scroll wheel picker |
| Active Workout | Tap plate hint | Open plate diagram |
| Week Plan | Swipe left/right | Navigate weeks |
| Week Plan | Tap grid cell | Scroll to day detail |
| Progress Charts | Tap-and-hold chart | Show data point tooltip |
| Progress Charts | Drag on chart | Scrub through data |
| Progress Charts | Pinch chart | Zoom time range |
| Running | Tap primary metric | Cycle metric display |
| Running | Swipe down on map | Collapse map |
| Apple Watch | Crown rotation | Adjust weight |
| Apple Watch | Tap DONE | Log set |
| Apple Watch | Force press | Options menu |

### Appendix D: Notification Schedule

| Notification | Trigger | Content |
|---|---|---|
| Morning workout reminder | 30 min before usual gym time | "Push Day ready -- [G] Full Volume. Let's go." |
| Rest timer complete | Timer reaches 0 (app backgrounded) | "Rest over -- Set 3 ready. Bench Press 85kg x 8" |
| Workout auto-paused | 10 min of inactivity | "Still working out? Tap to continue." |
| Weekly plan generated | Sunday 9:00 PM | "Your training week is planned. Tap to review." |
| Deload week suggestion | Algorithm trigger | "Strategic recovery week -- your body needs this to grow stronger." |
| Deload week start | Monday of deload week | "Deload week begins. Lighter weights, same focus. Trust the process." |
| PR celebration | Post-workout save (if PR hit) | "New PR! Bench Press e1RM: 102.5kg [trophy]" |
| Missed workout | 2 hours after usual gym time | "Missed your Pull Day? You can still fit it in later." |
| Recovery alert (red) | Morning Whoop sync <34% | "Recovery is low (28%). Today's workout adjusted to mobility." |
| Streak milestone | Every 4-week streak | "8-week training streak! Consistency is the ultimate performance enhancer." |
| Football T-1 reminder | Evening before match | "Football tomorrow -- today's workout protects your legs." |
| Import complete | After CSV import finishes | "Imported 234 workouts from Strong. Welcome to Tempo." |

---

*End of RepForge UX Specification v2.0*
