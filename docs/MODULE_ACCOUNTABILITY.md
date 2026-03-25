# MODULE: Accountability ("Lockdown")

## UX Specification v2.0

**App:** Tempo (iOS, SwiftUI)
**Module Codename:** Lockdown
**Author:** Nicola Debbia
**Date:** 2026-03-24
**Target User:** University student (Miami), prone to losing evenings to PS5 sessions starting ~7-8pm. Skips meals, cuts study short.

---

## Table of Contents

1. [Design System & Shared Components](#1-design-system--shared-components)
2. [Screen 1: Lockdown Main View (Today)](#2-screen-1-lockdown-main-view-today)
3. [Screen 2: Focus Timer View](#3-screen-2-focus-timer-view)
4. [Screen 3: Non-Negotiable Setup View](#4-screen-3-non-negotiable-setup-view)
5. [Screen 4: Streak & Consistency View](#5-screen-4-streak--consistency-view)
6. [Screen 5: Notification System](#6-screen-5-notification-system)
7. [Drill Sergeant Personality](#7-drill-sergeant-personality)
8. [Weekend Mode](#8-weekend-mode)
9. [Exam Mode](#9-exam-mode)
10. [Settings](#10-settings)
11. [Behavioral Psychology Framework](#11-behavioral-psychology-framework)
12. [Unlock Psychology & Reward System](#12-unlock-psychology--reward-system)
13. [Rest Day / Sick Day / Mental Health System](#13-rest-day--sick-day--mental-health-system)
14. [Weekly & Monthly Review System](#14-weekly--monthly-review-system)
15. [Edge Cases & Overrides (31)](#15-edge-cases--overrides)
16. [Data Model Summary](#16-data-model-summary)

---

## 1. Design System & Shared Components

### 1.1 Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `tempo.color.primary.signal` | `#E63946` | Lock icon, overdue states, aggressive alerts |
| `tempo.color.accountability.unlocked` | `#22C55E` | Unlock icon, completed states, celebrations — uses tempo.color.recovery.green |
| `tempo.color.accent.electric` | `#3B82F6` | Timer accent, in-progress indicators |
| `tempo.color.accountability.amber` | `#EAB308` | Partial completion, warning states — uses tempo.color.recovery.yellow |
| `tempo.color.bg.primary` | `#0D0D0D` | Main background (dark mode default) |
| `tempo.color.surface.card` | `#1C1C1E` | Card surfaces |
| `tempo.color.surface.elevated` | `#2C2C2E` | Elevated card surfaces (pressed, active) |
| `tempo.color.text.primary` | `#F5F2ED` | Primary text |
| `tempo.color.text.secondary` | `#A1A1AA` | Secondary/caption text |
| `tempo.color.text.tertiary` | `#8E8E93` | Disabled, placeholder text |
| `tempo.color.divider.default` | `#38383A` | Card borders, dividers |
| `tempo.color.accountability.streakGold` | `#FFD700` | Streak flame, perfect day highlights |

Light mode: Invert `bg.*` tokens. `bg.primary` becomes `#FFFFFF`, `bg.card` becomes `#F6F8FA`, text tokens invert accordingly. All accent colors remain.

### 1.2 Typography

| Style | Font | Size | Weight | Line Height | Usage |
|-------|------|------|--------|-------------|-------|
| `largeTitle` | SF Pro Display | 34pt | Bold | 41pt | Screen titles |
| `title1` | SF Pro Display | 28pt | Bold | 34pt | Section headers |
| `title2` | SF Pro Display | 22pt | Semibold | 28pt | Card titles |
| `title3` | SF Pro Display | 20pt | Semibold | 25pt | Subsection headers |
| `headline` | SF Pro Text | 17pt | Semibold | 22pt | Card names |
| `body` | SF Pro Text | 15pt | Regular | 20pt | Body copy |
| `callout` | SF Pro Text | 16pt | Regular | 21pt | Supporting text |
| `subheadline` | SF Pro Text | 15pt | Regular | 20pt | Captions, badges |
| `footnote` | SF Pro Text | 13pt | Regular | 18pt | Timestamps, metadata |
| `caption1` | SF Pro Text | 12pt | Regular | 16pt | Badges, labels |
| `caption2` | SF Pro Text | 11pt | Regular | 13pt | Smallest labels |
| `timer` | SF Pro Rounded | 72pt | Light | 80pt | Timer display |
| `timerSmall` | SF Pro Rounded | 48pt | Light | 54pt | Secondary timer |
| `streakNumber` | SF Pro Rounded | 56pt | Bold | 62pt | Streak counter |

### 1.3 Spacing & Layout

- Screen horizontal padding: 20pt (`tempo.space.screen.edge`; 16pt on iPhone SE via `tempo.space.screen.edge.compact`)
- Card internal padding: 16pt
- Card corner radius: 16pt
- Card spacing (vertical gap between cards): 12pt
- Section spacing: 24pt
- Button corner radius: 14pt (`tempo.radius.2xl`)
- Icon size in cards: 28x28pt
- Badge size: 20pt height, 8pt horizontal padding
- Safe area: respect all iOS safe areas; bottom bar height 83pt (tab bar + home indicator)

### 1.4 Haptic Patterns

> **Canonical source:** SOUND_AND_HAPTICS.md is the authoritative reference for all haptic patterns. The table below is a summary for Accountability-specific actions. If conflicts arise, defer to SOUND_AND_HAPTICS.md.

| Event | Haptic Type |
|-------|-------------|
| Task completed | `.success` (UINotificationFeedbackGenerator) |
| All tasks completed / Unlock | `.success` x3, 200ms apart |
| Timer start | `.heavy` (UIImpactFeedbackGenerator) |
| Timer pause | `.medium` |
| Timer session complete | `.success` + `.rigid` |
| Overdue warning | `.warning` (UINotificationFeedbackGenerator) |
| Card long press | `.selection` |
| Button tap | `.light` |

### 1.5 Shared Components

#### StatusBadge
Small pill-shaped badge indicating tracking source.
- "AUTO" badge: `progress.blue` background, white text, `caption2` font
- "MANUAL" badge: `border.subtle` background, `text.secondary` text, `caption2` font
- "WHOOP" badge: Whoop teal (#44D7B6) background, white text, `caption2` font
- "NUTRITRACK" badge: NutriTrack brand green (#4CAF50) background, white text, `caption2` font
- Size: auto-width with 8pt horizontal padding, 20pt height, 10pt corner radius

#### ProgressRing
Circular progress indicator used in multiple views.
- Track: `border.subtle`, 4pt stroke
- Fill: gradient from `progress.blue` to `unlocked.green` as completion approaches 100%
- Size variants: 40pt (card), 64pt (header), 120pt (detail)
- Animation: fill animates with `spring(response: 0.6, dampingFraction: 0.8)` on value change

#### LockIcon
Animated lock/unlock indicator.
- Locked: SF Symbol `lock.fill`, tinted `locked.red`, 24pt
- Unlocked: SF Symbol `lock.open.fill`, tinted `unlocked.green`, 24pt
- Transition animation: lock shackle lifts with spring, 0.4s, slight rotation (-5deg to 0deg), scale pulse 1.0 -> 1.2 -> 1.0

---

## 2. Screen 1: Lockdown Main View (Today)

This is the primary screen the user sees upon opening the Accountability tab. It is the daily command center.

### 2.1 Screen Structure

```
+------------------------------------------+
|  SafeArea Top                            |
|                                          |
|  [< Back]     LOCKDOWN      [Gear Icon]  |
|                                          |
|  Monday, March 24                        |
|                                          |
|  +--------------------------------------+|
|  |  [ProgressRing 64pt]   LOCKED  [L]   ||
|  |       47%          4h 32m until PS5  ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [Book] Study           1h 23m / 2h   ||
|  | [MANUAL]   [==========----] 69%      ||
|  |                    [Start Timer >]   ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [Dumbbell] Training        DONE [C]  ||
|  | [WHOOP]   [================] 100%    ||
|  |            45 min recorded           ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [Fork] Meals              2 / 3      ||
|  | [NUTRITRACK]  [==========----] 67%   ||
|  |         Next: Dinner before 8pm      ||
|  +--------------------------------------+|
|                                          |
|  +--------------------------------------+|
|  | [Star] Read 30 min       NOT STARTED ||
|  | [MANUAL]   [----------------]  0%    ||
|  |                                      ||
|  +--------------------------------------+|
|                                          |
|  ========================================|
|  LEISURE STATUS                          |
|  [Lock Icon]  Complete 1 more to unlock  |
|  [=============================----]     |
|  ========================================|
|                                          |
|  [ +++ START STUDY TIMER +++ ]           |
|                                          |
|  Tab Bar                                 |
+------------------------------------------+
```

### 2.2 Header Section

#### Navigation Bar
- Left: Back chevron (SF Symbol `chevron.left`), 17pt, `text.primary`. Only visible if navigated from another tab. Hidden if this is the root of the Accountability tab.
- Center: "LOCKDOWN" in `headline` font, `text.primary`, all caps, letter-spacing +1.5pt.
- Right: Settings gear icon (SF Symbol `gearshape`), 22pt, `text.secondary`. Taps to Settings (Screen 10). Hit target: 44x44pt.

#### Date Display
- Position: 8pt below navigation bar, left-aligned with 16pt horizontal padding.
- Format: Full weekday + month + day. Examples: "Monday, March 24", "Saturday, March 29".
- Font: `title3`, `text.secondary`.
- Tap: Opens date picker sheet (bottom sheet, 300pt height) to view other days. Past days are read-only review. Future days show scheduled non-negotiables. Cannot edit past data.

#### Status Banner
- Position: 12pt below date.
- Layout: Horizontal stack. Full width minus 32pt (16pt padding each side).
- Background: `bg.card` with 1pt `border.subtle` border. Corner radius 16pt.
- Height: 80pt.
- Internal padding: 16pt.
- Contents (left to right):
  - **ProgressRing** (64pt variant): Shows overall daily completion percentage. Percentage text centered inside ring, `title3` font, `text.primary`.
  - **Spacer**: 16pt.
  - **Status Stack** (vertical, leading-aligned):
    - Line 1: Lock status. Either "LOCKED" with `lock.fill` icon (both `locked.red`) or "UNLOCKED" with `lock.open.fill` icon (both `unlocked.green`). Font: `headline`. Icon: 20pt, 4pt trailing the text.
    - Line 2: Time context. Font: `footnote`, `text.secondary`.
      - If locked: "4h 32m until your usual PS5 time" (calculates from current time to configured PS5 time, default 7:30 PM).
      - If unlocked before PS5 time: "Unlocked 2h early. Ahead of schedule."
      - If unlocked after PS5 time: "Unlocked. Better late than never."
      - If all done before noon: "All done by noon. Legend."

#### Status Banner States
1. **All incomplete, morning (before noon):** ProgressRing shows low %, LOCKED in red, time context shows hours until PS5 time.
2. **Partial progress, afternoon:** ProgressRing animates to current %, LOCKED, time context shows countdown.
3. **Almost done (1 remaining):** ProgressRing high %, LOCKED, time context: "Just 1 left. So close."
4. **All complete:** ProgressRing 100% with confetti particle effect (`tempo.motion.celebration.epic` = 3000ms, then stops), UNLOCKED in green, green border pulse animation (2 cycles, 0.5s each). Time context changes as described above.
5. **Overdue (past PS5 time, incomplete):** ProgressRing turns `locked.red` tint, LOCKED, time context: "PS5 time passed. Handle your business."

### 2.3 Non-Negotiable Cards

Cards are displayed in a `LazyVStack` with 12pt spacing, inside a `ScrollView`. The scroll view starts 12pt below the status banner and ends above the Leisure Status section.

#### Card Layout (Generic)

```
+------------------------------------------+
| [Icon 28pt]  Name             Status     |
| [Badge]  [ProgressBar]        Pct%       |
|          Supporting text    [Action Btn]  |
+------------------------------------------+
```

- Width: Full width minus 32pt (16pt padding each side).
- Min height: 88pt. Expands for content.
- Background: `bg.card`. Corner radius: 16pt.
- Border: 1pt `border.subtle`. Changes per state (see below).
- Internal padding: 16pt.
- Shadow: none (dark mode), or 0 2pt 8pt rgba(0,0,0,0.04) (light mode).

#### Card Internal Layout

**Row 1 (Top)**
- Left: Icon (SF Symbol, 28x28pt, tinted per card type).
- Center: Name in `headline` font, `text.primary`. Left-aligned, 12pt after icon.
- Right: Status indicator. One of:
  - "NOT STARTED" -- `caption1`, `text.tertiary`
  - "1h 23m / 2h" -- `callout`, `text.primary` for current, `text.secondary` for target
  - "DONE" -- `caption1`, `unlocked.green`, with checkmark circle icon
  - "OVERDUE" -- `caption1`, `locked.red`, pulsing
  - "SKIPPED" -- `caption1`, `text.tertiary`, strikethrough

**Row 2 (Middle, 8pt below Row 1)**
- Left: StatusBadge (AUTO, MANUAL, WHOOP, NUTRITRACK).
- Center: ProgressBar.
  - Height: 6pt. Corner radius: 3pt.
  - Track: `border.subtle`.
  - Fill: `progress.blue` (0-49%), `progress.amber` (50-79%), `unlocked.green` (80-100%).
  - Animation: width animates with `easeInOut(duration: 0.4)`.
  - Width: stretches to fill available space (after badge, before percentage).
- Right: Percentage in `footnote`, `text.secondary`. Format: "69%".

**Row 3 (Bottom, 8pt below Row 2)**
- Left: Empty (alignment spacer).
- Center: Supporting text in `footnote`, `text.secondary`. Content varies per card type.
- Right: Action button (if applicable). Pill-shaped, `progress.blue` background, white text, `caption1` font, 28pt height, 12pt horizontal padding, 8pt corner radius. Hit target: min 44pt height.

#### Card States

**1. Not Started**
- Border: 1pt `border.subtle`
- Icon tint: `text.tertiary`
- Progress bar: empty
- Status: "NOT STARTED"
- Background: `bg.card`

**2. In Progress**
- Border: 1pt `progress.blue`
- Icon tint: `progress.blue`
- Progress bar: partially filled
- Status: shows current/target (e.g., "1h 23m / 2h")
- Background: `bg.card`

**3. Completed**
- Border: 1pt `unlocked.green`
- Icon tint: `unlocked.green`
- Progress bar: full, green
- Status: "DONE" with checkmark
- Background: very subtle green tint (`unlocked.green` at 5% opacity)
- Completion animation: checkmark draws itself (stroke animation, 0.3s), card briefly scales 1.0 -> 1.03 -> 1.0 (spring, 0.4s), haptic `.success`

**4. Overdue**
- Border: 1pt `locked.red`, pulsing (opacity 0.5 -> 1.0 -> 0.5, 2s cycle, infinite)
- Icon tint: `locked.red`
- Progress bar: current fill in `locked.red`
- Status: "OVERDUE" pulsing with border
- Background: very subtle red tint (`locked.red` at 3% opacity)
- Supporting text changes to urgency message (e.g., "You said 2h of study. 37 minutes logged.")

**5. Skipped**
- Border: 1pt `border.subtle`
- Icon tint: `text.tertiary`
- Progress bar: hidden
- Status: "SKIPPED" with strikethrough on name
- Background: `bg.card` at 60% opacity
- Supporting text: reason if provided (e.g., "Rest day"), otherwise "Skipped"

#### Specific Card Types

##### Study Card
- Icon: SF Symbol `book.fill`, tint: `progress.blue`
- Name: "Study" (or user-customized, e.g., "Calculus", "Study: Orgo Chem")
- Status: Shows accumulated time vs target (e.g., "1h 23m / 2h")
- Badge: "MANUAL"
- Supporting text (not started): "Start a focus session to begin tracking"
- Supporting text (in progress): "Last session: 25 min Calculus, 2:34 PM"
- Supporting text (completed): "2h 07m total across 4 sessions"
- Action button: "Start Timer" -- navigates to Focus Timer View (Screen 2)
- Special: The action button is always visible unless completed. When completed, it changes to "Add More" in outlined style (border only, no fill).

##### Training Card
- Icon: SF Symbol `dumbbell.fill`, tint: `progress.amber` (not started), `unlocked.green` (done)
- Name: "Training"
- Status: Binary -- "NOT STARTED" or "DONE"
- Badge: "WHOOP" (or "HEALTHKIT" if no Whoop connected)
- Supporting text (not started): "Waiting for Whoop sync..."
- Supporting text (done): "45 min strength recorded at 2:15 PM"
- Action button: None when auto-tracked. If manual fallback needed: "Log Manually" button appears if no data by 6 PM.
- Auto-tracking logic: Queries HealthKit for workouts > 20 minutes today. If Whoop is connected, uses Whoop's activity data. Syncs every 15 minutes in background, immediately on app foreground.
- Manual override: Long press card -> context menu -> "Mark as Complete" / "Log Manually". Manual entries show "MANUAL" badge instead of "WHOOP".

##### Meals Card
- Icon: SF Symbol `fork.knife`, tint: `progress.amber`
- Name: "Meals"
- Status: "2 / 3" (meals logged vs target)
- Badge: "NUTRITRACK"
- Supporting text: "Next: Dinner before 8pm" (dynamically calculates which meal is next based on time of day and meals already logged)
  - Before any meals: "Next: Breakfast"
  - After breakfast: "Next: Lunch"
  - After lunch: "Next: Dinner before 8pm" (includes deadline because dinner is the one most likely skipped)
  - All logged: "All meals logged today"
- Action button: "Log in NutriTrack" -- deep links to NutriTrack app via URL scheme (`nutritrack://log-meal`). If NutriTrack not installed, shows inline prompt: "Install NutriTrack to auto-track meals" with App Store link.
- Auto-tracking logic: Reads from shared App Group container or HealthKit nutritional data. Counts distinct meal entries (not snacks) logged in NutriTrack today. A "meal" is any logged entry with > 200 kcal.
- Progress bar: segmented into 3 equal parts (for 3-meal target), each segment fills as a meal is logged.

##### Custom Non-Negotiable Card
- Icon: User-selected SF Symbol (default: `star.fill`), tint: `progress.blue`
- Name: User-defined (e.g., "Read 30 min", "Meditate", "Call Mom")
- Status: Depends on tracking type:
  - Timed: shows current / target time
  - Counter: shows current / target count (e.g., "2 / 5 pages")
  - Checkbox: "NOT STARTED" or "DONE"
- Badge: "MANUAL"
- Supporting text: user-defined hint or empty
- Action button:
  - Timed: "Start Timer" (uses same Focus Timer but without Pomodoro, just a count-up or countdown)
  - Counter: "+" button to increment
  - Checkbox: tap card to toggle

#### Card Interactions

- **Tap (non-actionable area):** Expands card to show detail view inline (accordion style). Detail shows: today's log entries (timestamps), edit option, skip option. Animation: expand with `.easeInOut(duration: 0.3)`, content fades in 0.15s after expand starts.
- **Long press (0.5s):** Context menu appears with:
  - "Mark as Complete" (if not done)
  - "Skip Today" (prompts for optional reason)
  - "Edit Non-Negotiable" (navigates to edit view)
  - "View History" (navigates to that non-negotiable's history)
- **Swipe right:** Quick-complete. Green background reveals with checkmark. Release to confirm. Haptic `.success`. Only available for manual-type cards.
- **Swipe left:** Quick-skip. Red background reveals with "Skip" text. Release to confirm. Prompts for reason via inline text field that appears in the card.
- **Drag to reorder:** Long press (1.0s, longer than context menu threshold) activates drag mode. Card lifts with shadow and scale 1.05. Other cards shift to make room. Drop to reorder. Order persists in user settings.

### 2.4 Leisure Status Section

Position: Pinned above tab bar. Does not scroll with the card list. Has a top border of 1pt `border.subtle` and background `bg.primary` with blur effect (`.ultraThinMaterial`).

Height: 96pt (including padding). Internal padding: 16pt horizontal, 12pt vertical.

#### Layout

```
+------------------------------------------+
|  LEISURE STATUS                          |
|  [LockIcon]  Complete 1 more to unlock   |
|  [============================-----]     |
+------------------------------------------+
```

- **Title:** "LEISURE STATUS" in `caption1`, `text.tertiary`, letter-spacing +1pt, all caps.
- **Lock Icon:** LockIcon component (see 1.5), 32pt size, left-aligned.
- **Status Text:** To the right of lock icon, 12pt spacing. `body` font. Color depends on state.
- **Progress Bar:** Full width below lock row, 8pt height, 4pt corner radius. Track: `border.subtle`. Fill: gradient from `locked.red` (0%) through `progress.amber` (50%) to `unlocked.green` (100%).

#### States

**1. Locked (tasks remaining)**
- Lock icon: locked, red
- Text: "Complete {n} more to unlock" in `text.primary`
- Text example: "Complete 2 more to unlock"
- Progress bar: partially filled
- Background: default

**2. Almost There (1 remaining)**
- Lock icon: locked, red, with subtle shake animation (rotateZ -3deg to 3deg, 0.15s, 3 times)
- Text: "Just 1 more. You're right there." in `progress.amber`
- Progress bar: nearly full
- Background: very subtle amber tint

**3. Unlocked**
- Lock icon: transitions from locked to unlocked (spring animation, 0.5s)
- Text: "You earned it. Enjoy your evening." in `unlocked.green`
- Progress bar: full, green, with shimmer animation (left-to-right highlight sweep, 1.5s, 2 cycles)
- Background: very subtle green tint (`unlocked.green` at 3% opacity)
- Confetti burst: 50 particles, gold/green/blue, 2s duration, gravity fall. Triggers once on unlock moment.
- Haptic: triple success (see 1.4)
- Sound: short celebratory chime (custom sound, 1.2s, major chord arpeggio)

**4. Overdue (past PS5 time, still locked)**
- Lock icon: locked, red, pulsing
- Text: "PS5 time has passed. Tasks still incomplete." in `locked.red`
- Progress bar: fill turns red
- Background: subtle red tint

**5. All skipped / Rest day**
- Lock icon: unlocked, grey (`text.tertiary`)
- Text: "Rest day. No non-negotiables active." in `text.secondary`
- Progress bar: hidden
- Background: default

### 2.5 Quick Action Button

Positioned between the last card and the Leisure Status section. Sticky -- does not scroll. Centered horizontally.

- Width: Full width minus 32pt.
- Height: 56pt.
- Corner radius: 16pt.
- Background: Linear gradient from `progress.blue` to `#2563EB` (slightly darker blue), left to right.
- Text: "START STUDY TIMER" in `headline`, white, centered. All caps, letter-spacing +1pt.
- Icon: SF Symbol `play.fill`, 18pt, white, 8pt leading the text.
- Shadow: 0 4pt 12pt `progress.blue` at 30% opacity.
- Tap: Navigate to Focus Timer View. Haptic `.heavy`.
- State change: If study is already complete, button text changes to "START ANOTHER SESSION" with outlined style (blue border, blue text, no fill, no shadow).
- Visibility: Hidden if there are no timed non-negotiables. In that case, the Leisure Status section moves up.

### 2.6 Time Remaining Indicator

Displayed inside the Status Banner (Row 2 of the banner, see 2.2). Not a separate component.

Calculation: `configured_ps5_time - current_time`. Updates every 60 seconds via timer.

Formatting:
- More than 2 hours: "4h 32m until your usual PS5 time"
- 1-2 hours: "1h 15m left. Focus up."
- 30-60 min: "42 min. Clock's ticking."
- Under 30 min: "18 min. Move." (text turns `locked.red`)
- Past PS5 time: "PS5 time passed {n} min ago" (text is `locked.red`)

### 2.7 Pull to Refresh

Standard iOS pull-to-refresh. Triggers:
- Re-sync Whoop/HealthKit data
- Re-sync NutriTrack data
- Recalculate all progress values
- Custom refresh indicator: the LockIcon bounces during refresh

### 2.8 Empty State

If the user has not set up any non-negotiables:

```
+------------------------------------------+
|                                          |
|            [Lock icon, 64pt, grey]       |
|                                          |
|         No non-negotiables set           |
|                                          |
|     Define what you MUST do each day     |
|     before you earn your downtime.       |
|                                          |
|       [ SET UP NON-NEGOTIABLES ]         |
|                                          |
+------------------------------------------+
```

- Lock icon: SF Symbol `lock.fill`, 64pt, `text.tertiary`
- Title: "No non-negotiables set" -- `title2`, `text.primary`
- Body: "Define what you MUST do each day before you earn your downtime." -- `body`, `text.secondary`, centered, max-width 280pt
- Button: same style as Quick Action Button but text "SET UP NON-NEGOTIABLES". Navigates to Non-Negotiable Setup View.

---

## 3. Screen 2: Focus Timer View

Full-screen modal presented from the Study card or Quick Action button. Presented with `.fullScreenCover` transition (slide up from bottom). Status bar hidden during active timer.

### 3.1 Screen Structure

```
+------------------------------------------+
|  [X Close]                  [Settings]   |
|                                          |
|          Session 2 of 4                  |
|          [Calculus II]                   |
|                                          |
|                                          |
|           +------------------+           |
|           |                  |           |
|           |     18:42        |           |
|           |                  |           |
|           +------------------+           |
|         (circular progress ring)         |
|                                          |
|              FOCUS TIME                  |
|                                          |
|     Today's total: 1h 23m / 2h          |
|                                          |
|   Focus Score: 87                        |
|                                          |
|    [Distracted]              [Ambient]   |
|                                          |
|                                          |
|    [Stop]    [PAUSE]    [Skip >>]        |
|                                          |
+------------------------------------------+
```

### 3.2 Top Bar

- **Close button (X):** Top left, 16pt from leading and top safe area. SF Symbol `xmark`, 20pt, `text.secondary`. Hit target: 44x44pt.
  - If timer is running: tapping shows confirmation alert: "Timer is running. Stop and discard this session?" with "Keep Going" (default, bold) and "Stop & Discard" (destructive red) buttons.
  - If timer is paused: shows alert: "Discard this session?" with "Resume" and "Discard" buttons.
  - If timer hasn't started: dismisses immediately.
- **Settings button:** Top right, same sizing as close. SF Symbol `slider.horizontal.3`, 20pt, `text.secondary`. Opens timer settings sheet (see 3.9).

### 3.3 Session Indicator

- Position: centered, 24pt below top bar.
- Text: "Session {n} of {total}" in `subheadline`, `text.secondary`.
  - Example: "Session 2 of 4"
  - Total comes from Pomodoro settings (default 4).
  - After all planned sessions complete: "Bonus Session" in `streak.gold`.

### 3.4 Subject Selector

- Position: centered, 8pt below session indicator.
- Display: Pill-shaped button with the current subject name.
  - Background: `bg.cardElevated`. Border: 1pt `border.subtle`. Corner radius: 20pt.
  - Text: `callout`, `text.primary`. SF Symbol `tag.fill` 14pt leading, `chevron.down` 10pt trailing.
  - Padding: 8pt vertical, 16pt horizontal.
  - Example: "[tag] Calculus II [v]"
- Tap: Opens subject picker sheet (bottom sheet, 320pt).
  - List of previously used subjects.
  - "Add New Subject" row at top with text field.
  - Subjects are simple strings stored locally. No hierarchy.
  - Default subjects: "General Study" (pre-created, cannot be deleted).
  - Recent subjects appear first, sorted by last used.
  - "No Subject" option to study without tagging.
- If no subject selected: displays "Tap to tag subject" in `text.tertiary`, italicized.

### 3.5 Timer Display

The centerpiece of the view.

#### Session Types

The timer supports five distinct session configurations:

| Type | Focus | Break | Best For | Evidence Base |
|------|-------|-------|----------|---------------|
| **Pomodoro** | 25 min | 5 min (short) / 15 min (long after 4) | General study, getting started, building momentum | Cirillo (2006). The 25/5 split is more ritual than science -- no controlled study validates 25 minutes specifically -- but it works because it makes starting feel low-cost ("it's only 25 minutes"). Effective for procrastination-prone users. |
| **Ultradian Sprint** | 52 min | 17 min | Sustained reading, problem sets, writing | Based on the DeskTime productivity study (Gifford, 2014) finding the most productive 10% of users worked in ~52 min focused bursts with ~17 min breaks. Not peer-reviewed, but aligns with ultradian rhythm research showing natural dip points near the 50-60 minute mark. |
| **Deep Work** | 90 min | 20 min | Research papers, complex projects, creative work | Aligned with Peretz Lavie's ultradian rhythm research (Lavie, 1985, "Ultradian rhythms in alertness," *Sleep*, 8(4), 267-275) showing ~90-minute Basic Rest-Activity Cycles (BRAC). Cal Newport's *Deep Work* (2016) popularized the 90-minute block. Not all users can sustain 90 minutes -- the system should suggest starting with Pomodoro and graduating to Deep Work as focus scores improve. |
| **Flow** | 25-120 min (open-ended) | User-initiated | Creative work, programming, when "in the zone" | No fixed duration. Timer counts UP instead of down. User ends when they naturally break. Based on Csikszentmihalyi's flow state research (1990) -- forced timer interruptions can break flow. A soft chime at 25 min intervals gently reminds the user to check in without forcing a stop. Break suggested (not forced) after 90 min. |
| **Custom** | 5-120 min | 1-30 min | User-defined for any scenario | N/A |

**Adaptive suggestion logic:** Session type is selectable from the timer settings sheet. Defaults to Pomodoro. The system tracks which session type produces the best focus scores per subject and suggests the optimal type: "Your focus score is 12% higher with Deep Work sessions for Calculus. Try it?" Additionally, if a user consistently uses Pomodoro and has focus scores above 85, suggest graduating: "Your Pomodoro focus scores are consistently high. Ready to try a 52-minute Ultradian Sprint for deeper immersion?"

#### Circular Timer

- Position: centered vertically in the available space (between subject selector and controls).
- Size: 260pt diameter.
- Outer ring:
  - Track: `border.subtle`, 8pt stroke.
  - Progress fill: `progress.blue` during focus, `unlocked.green` during break. Stroke 8pt. Rounded line cap.
  - Progress direction: clockwise from 12 o'clock. Starts full, drains to 0 (countdown behavior).
  - Animation: smooth linear animation synced to timer.
- Inner content:
  - Time remaining in `timer` font (72pt), `text.primary`, centered.
  - Format: "MM:SS" always. Leading zero for minutes under 10. Examples: "25:00", "04:32", "00:08".
  - Colon blinks (opacity 1.0 -> 0.3 -> 1.0, 1s cycle) when timer is paused.
- Below ring:
  - Phase label: "FOCUS TIME" or "BREAK TIME" in `caption1`, letter-spacing +2pt, all caps.
  - Color: `progress.blue` for focus, `unlocked.green` for break.

#### Timer States

**1. Ready (not started)**
- Shows full time (e.g., "25:00").
- Ring is full.
- Phase label: "READY"
- Background: default

**2. Running (focus)**
- Time counts down.
- Ring drains.
- Phase label: "FOCUS TIME" in `progress.blue`.
- Background: very subtle blue radial gradient from center, 3% opacity. Pulsates subtly (3% -> 5% -> 3%, 4s cycle).
- Screen: auto-lock disabled (`UIApplication.shared.isIdleTimerDisabled = true`).

**3. Running (break)**
- Time counts down (break duration).
- Ring drains, green.
- Phase label: "BREAK TIME" in `unlocked.green`.
- Background: subtle green radial gradient.
- Content changes: Motivational quote appears below phase label (see 3.8).

**4. Paused**
- Time frozen.
- Colon blinks.
- Ring stops.
- Phase label: "PAUSED" in `progress.amber`.
- Background: default.
- Auto-lock re-enabled.
- Pause duration tracked separately (shown in session summary).

**5. Completed (session)**
- Triggers when countdown reaches 0:00.
- Sound: completion chime (system sound `1007` or custom). If in background, plays via notification sound.
- Haptic: `.success` + `.rigid`.
- Ring fills completely with celebration color, then resets.
- Auto-advance: If auto-start breaks is ON, starts break after 3s countdown ("Break starts in 3..."). Otherwise, shows "Start Break" button.

**6. Completed (all sessions)**
- Sound: longer celebratory sound (2s).
- Haptic: triple success.
- Full-screen celebration overlay:
  - Large checkmark animation (draws itself, 0.5s).
  - "All Sessions Complete!" in `title1`, `unlocked.green`.
  - Total study time: "2h 07m of focused study" in `body`, `text.secondary`.
  - Focus score for the session block: "Focus Score: 91" (see 3.13).
  - "DONE" button to dismiss and return to main view.

### 3.6 Accumulated Time Display

- Position: 24pt below the timer ring.
- Text: "Today's total: 1h 23m / 2h" in `callout`, `text.secondary`.
- The first value includes time from ALL study sessions today (not just current one).
- Updates in real-time as the current session progresses.
- When target reached mid-session: text turns `unlocked.green`, briefly pulses.

### 3.7 Action Buttons (Secondary Row)

Position: 16pt below accumulated time. Horizontal stack, centered, 40pt spacing.

#### Distraction Button
- Icon: SF Symbol `hand.raised.fill`, 24pt.
- Label: "Distracted" in `caption1`.
- Vertical stack (icon above label).
- Color: `text.secondary`. Turns `locked.red` briefly (0.3s) on tap.
- Behavior: Increments distraction counter. Shows small floating "+1" animation that rises and fades (0.5s).
- Current count shown as badge on the icon (red circle, white number, `caption2`). Hidden at 0.
- Purpose: Self-awareness tool. Shown in session summary and trends.
- Haptic: `.warning` on tap.

#### Ambient Sound Button
- Icon: SF Symbol `speaker.wave.2.fill`, 24pt.
- Label: "Ambient" in `caption1`.
- Color: `text.secondary` (off), `progress.blue` (playing).
- Tap: Opens ambient sound picker (bottom sheet, 280pt).
  - Options (8 ambient sounds):
    1. **"None"** (default) -- silence
    2. **"Rain"** -- looping audio, ~60s seamless loop. Gentle, steady rainfall on a window. No thunder.
    3. **"Heavy Rain"** -- looping audio, ~60s seamless loop. Downpour with distant thunder rumbles every 30-45s. More immersive, higher intensity.
    4. **"White Noise"** -- generated. Pure white noise via `AVAudioEngine`, flat frequency spectrum. Clinical, consistent. Note: white noise has equal energy at all frequencies, which some users find harsh. Research support is mixed -- Soderlund et al. (2010) found white noise improved cognitive performance in inattentive children but not in attentive ones, suggesting it may specifically benefit users with attention difficulties.
    5. **"Brown Noise"** (recommended default for study) -- generated. Deeper, warmer than white noise. Emphasis on lower frequencies (-6dB/octave rolloff). Less harsh, better for extended sessions. Brown noise has stronger anecdotal and emerging research support for sustained focus than white noise, likely because its frequency profile is closer to natural environmental sounds and is less fatiguing to the auditory system over long periods. Prioritize this option in the picker by listing it before white noise.
    6. **"Coffee Shop"** -- looping audio, ~90s seamless loop. Quiet cafe ambiance: espresso machine hiss, muted conversation murmur, occasional cup clink. Never distracting individual words. Research basis: Mehta, Zhu & Cheema (2012, *Journal of Consumer Research*) found that moderate ambient noise (~70dB, typical coffee shop level) enhances creative performance compared to silence or loud noise, by inducing processing disfluency that activates abstract thinking.
    7. **"Library"** -- looping audio, ~90s seamless loop. Very subtle page turns, quiet shuffling, distant keyboard taps, occasional chair creak. The quietest option.
    8. **"Fireplace"** -- looping audio, ~60s seamless loop. Crackling fire, occasional wood pop. Warm, cozy.
  - **Sound mixing:** Only one ambient sound at a time. Audio plays via `AVAudioSession` with `.ambient` category so it mixes with other audio (e.g., music). Ducking: ambient lowers by 20% if a notification sound plays, restores over 1s.
  - **Volume slider:** 0-100%, default 30%. Independent of system volume. Shown below the sound picker list as a horizontal slider with speaker icons at each end.
  - **Fade behavior:** When switching sounds, current fades out over 0.5s, new fades in over 0.5s. No abrupt cuts.
  - Persists between sessions (remembers last choice and volume).

### 3.8 Primary Control Buttons

Position: Bottom of screen, 32pt above safe area bottom. Horizontal stack, centered.

#### Layout

```
  [Stop]         [  PAUSE  ]         [Skip >>]
  48pt           64pt height          48pt
  circle         pill                 circle
```

#### Stop Button
- Shape: Circle, 48pt diameter.
- Background: `bg.cardElevated`.
- Icon: SF Symbol `stop.fill`, 20pt, `locked.red`.
- Tap: Confirmation alert: "Stop this session? {time} of study will be saved." Buttons: "Keep Going" (default), "Stop & Save" (saves partial time), "Stop & Discard" (destructive, discards this session's time).
- Haptic: `.medium`.

#### Pause/Resume Button
- Shape: Rounded rectangle (pill), 160pt width, 64pt height, 32pt corner radius.
- **Paused state:** Background `progress.blue`. Icon: `play.fill` 24pt, white. Text: "RESUME" in `headline`, white, 8pt after icon.
- **Running state:** Background `bg.cardElevated`, 1pt `progress.blue` border. Icon: `pause.fill` 24pt, `progress.blue`. Text: "PAUSE" in `headline`, `progress.blue`, 8pt after icon.
- Transition: cross-fade with scale (0.95 -> 1.0), 0.2s.
- Haptic: `.heavy` on start/resume, `.medium` on pause.

#### Skip Button
- Shape: Circle, 48pt diameter.
- Background: `bg.cardElevated`.
- Icon: SF Symbol `forward.fill`, 20pt, `text.secondary`.
- Tap: Skips to next phase. If in focus, skips to break (partial focus time is saved). If in break, skips to next focus session.
- Confirmation: Only required if skipping focus with > 5 min remaining. Alert: "Skip with {time} remaining? Completed time will still count."
- Haptic: `.light`.

### 3.9 Timer Settings Sheet

Accessed via settings button in top bar. Bottom sheet, 400pt height, `bg.card` background.

#### Contents

- **Session Type:** Segmented control: "Pomodoro", "Long Focus", "Deep Work", "Custom". Selecting a preset fills the fields below. Custom unlocks manual editing.
- **Focus Duration:** Stepper, range 5-120 min, step 5 min, default 25 min.
- **Short Break:** Stepper, range 1-30 min, step 1 min, default 5 min.
- **Long Break:** Stepper, range 5-60 min, step 5 min, default 15 min.
- **Sessions Before Long Break:** Stepper, range 2-8, step 1, default 4.
- **Auto-Start Breaks:** Toggle, default ON. When ON, break countdown starts automatically after focus ends (with 3s pre-countdown).
- **Auto-Start Focus:** Toggle, default OFF. When ON, next focus session starts automatically after break ends.
- **End-of-Session Sound:** Picker. Options: "Chime" (default), "Bell", "Gentle", "Alarm", "None". Each plays a 1s preview on selection.
- **Keep Screen On:** Toggle, default ON. Controls `isIdleTimerDisabled`.

All settings persist in UserDefaults. Changes apply to the NEXT session (don't modify currently running timer).

### 3.10 Break Screen

When a break is active, the timer view changes:

- Background: Soft green radial gradient, 5% opacity.
- Below the timer ring, a motivational/rest message appears:
  - Rotate through messages:
    - "Stand up. Stretch. You've earned it."
    - "Hydrate. Your brain needs water."
    - "Look at something 20 feet away for 20 seconds."
    - "Roll your neck. Release the tension."
    - "Deep breath in... hold... and out."
    - "You're {percentage}% done with today's study goal."
  - Font: `body`, `text.secondary`, centered, italic, max-width 260pt.
  - New message each break.

### 3.11 Background Behavior

When the app is backgrounded during an active timer:
- Timer continues counting via `BackgroundTaskScheduler` and local timestamps.
- On return, elapsed time is calculated from `Date()` diff, not from an actual background timer (iOS kills background timers).
- If the timer should have completed while backgrounded:
  - Show "Session complete!" overlay immediately on return.
  - Time is accurately recorded.
  - If auto-start was on, calculate how many sessions would have passed.
- Local notification fired at session end (see Notification System, section 6).

### 3.12 Live Activity (iOS 16+)

When a timer is running, a Live Activity is started on the lock screen and Dynamic Island.

#### Lock Screen (Expanded)
```
+------------------------------------------+
|  [Book icon]  Study: Calculus II         |
|                                          |
|           18:42                          |
|        Focus Session 2/4                 |
|                                          |
|  Today: 1h 23m / 2h                     |
+------------------------------------------+
```

- Background: `progress.blue` tint.
- Timer: updates every second via `ActivityKit` push or timeline.
- Tap: opens Tempo directly to the timer view.

#### Dynamic Island (Compact)
- Leading: Book icon + "18:42" countdown.
- Trailing: Ring progress indicator, 24pt.

#### Dynamic Island (Expanded)
```
+-----------------------------+
| [Book] Study    18:42       |
| Calculus II     Session 2/4 |
| [Pause]    [Stop]           |
+-----------------------------+
```

- Buttons: Pause and Stop are interactive via `ActivityKit` intents.

#### Dynamic Island (Minimal)
- Just the countdown: "18:42" or the ring progress.

### 3.13 Focus Score System

The Focus Score is a 0-100 metric measuring the quality of a study session, not just the duration. It answers: "Were you actually focused, or just running a timer?"

#### Inputs

| Signal | Weight | Source | How Measured |
|--------|--------|--------|-------------|
| Distraction taps | 35% | In-app manual | Each tap of the "Distracted" button. 0 taps = 100%, 1-2 = 85%, 3-4 = 65%, 5+ = 40% |
| Pause frequency | 25% | Timer data | Pauses per 25-min block. 0 = 100%, 1 = 90%, 2 = 70%, 3+ = 50% |
| Pause duration ratio | 20% | Timer data | Total pause time / total session time. <5% = 100%, 5-15% = 80%, 15-30% = 55%, >30% = 30% |
| Session completion | 20% | Timer data | Did the user finish the full session or stop early? Full = 100%, >75% = 80%, >50% = 50%, <50% = 20% |

**Formula:**
```
focusScore = (distractionScore * 0.35) + (pauseFreqScore * 0.25) + (pauseDurationScore * 0.20) + (completionScore * 0.20)
```

**Automatic distraction detection:** When the app goes to background during a focus session (`scenePhase` change to `.inactive`/`.background`), auto-count that as a potential distraction event. This requires zero special APIs and is 100% App Store safe. Combined with timer pauses/resumes and the manual distraction tap button, this provides a robust Focus Score without any Screen Time API dependency (per Technical Feasibility Audit: `DeviceActivityMonitor` / Family Controls will be rejected by Apple for non-parental-control apps).

#### Display
- Shown below accumulated time during active session as: "Focus Score: {score}" with a small colored dot.
  - 90-100: `unlocked.green` dot, "Excellent"
  - 75-89: `progress.blue` dot, "Good"
  - 50-74: `progress.amber` dot, "Fair"
  - Below 50: `locked.red` dot, "Needs work"
- Updates in real-time as session progresses.
- Session summary shows final score prominently.

### 3.14 Study Analytics

Accessible from: Streak & Consistency View, or tapping "View History" on the Study card.

#### Hours Per Subject (Last 30 Days)
- Horizontal bar chart.
- Each subject has a bar showing total hours.
- Sorted by most hours descending.
- Example: "Calculus II: 28h 15m", "Organic Chemistry: 14h 30m", "History: 6h 45m"

#### Time-of-Day Productivity Heatmap
- Grid: 7 columns (days of week) x 16 rows (6 AM to 10 PM, hourly).
- Cell color: intensity based on focus score during that hour slot.
- Reveals patterns: "You study best on Tuesday mornings" or "Your focus drops after 4 PM."
- Caption below: "Your peak focus hours: {top 3 time slots}" auto-calculated.

#### Focus Score Trends
- Line chart, 30-day trailing.
- X-axis: dates. Y-axis: 0-100.
- Rolling 7-day average line overlaid.
- Target line at 80 (dashed, `progress.amber`).

#### Study Planning (Exam-Linked)

When an exam is set, the Study Analytics view adds a planning section:

- **Exam countdown header:** "{Exam Name} in {N} days"
- **Hours studied for this subject:** total since exam was added.
- **Projected hours remaining:** `(days_remaining * avg_daily_hours_for_subject)`.
- **Recommendation:** "At your current pace of {X}h/day, you'll log {Y}h total by exam day. {verdict}."
  - Verdict: "On track" (green), "Tight -- increase to {Z}h/day" (amber), "Behind -- need {Z}h/day starting now" (red).
- **Daily target breakdown:** Shows each remaining day with a suggested study block. Example:
  ```
  Wed Mar 25:  3h Calculus (2 sessions)
  Thu Mar 26:  3h Calculus (2 sessions)
  Fri Mar 27:  2h Calculus (exam eve, lighter)
  Sat Mar 28:  EXAM DAY
  ```

#### Calendar Blocking Suggestions

If the user grants EventKit (Calendar) access:

- Tempo reads the user's calendar for free time slots.
- Suggests study blocks in open slots: "You have a 2-hour gap between 2 PM and 4 PM tomorrow. Block it for Calculus?"
- Tapping "Block It" creates a calendar event: "Study: Calculus II (Tempo)" with a 10-minute reminder.
- Does NOT auto-create events. Always asks permission for each block.
- Shows up to 3 suggestions per day in a "Suggested Study Blocks" section.
- Respects existing events, travel time, and a configurable buffer (default: 30 min between events).

---

## 4. Screen 3: Non-Negotiable Setup View

Accessed from: Settings, Empty state button, or "+ Add" button in card list.

### 4.1 Screen Structure

```
+------------------------------------------+
|  [< Back]  NON-NEGOTIABLES  [Save/Done]  |
|                                          |
|  Your daily requirements. Complete       |
|  these before leisure time is unlocked.  |
|                                          |
|  ACTIVE (3)                              |
|  +--------------------------------------+|
|  | [=] [Book] Study      2h / day    [>]||
|  +--------------------------------------+|
|  | [=] [Dumb] Training   1x / day   [>]||
|  +--------------------------------------+|
|  | [=] [Fork] Meals      3 / day    [>]||
|  +--------------------------------------+|
|                                          |
|  [ + Add Non-Negotiable ]               |
|                                          |
|  TEMPLATES                               |
|  +--------------------------------------+|
|  | [Mortarboard] Student Athlete        ||
|  | Study 2h + Training + 3 Meals        ||
|  +--------------------------------------+|
|  | [Book] Exam Week                     ||
|  | Study 4h + 3 Meals (no training)     ||
|  +--------------------------------------+|
|  | [Sun] Light Day                      ||
|  | Study 1h + 3 Meals                   ||
|  +--------------------------------------+|
|                                          |
|  Recommended: 3-5 non-negotiables.      |
|  More than 5 risks burnout.             |
|                                          |
+------------------------------------------+
```

### 4.2 Navigation Bar

- Left: "< Back" or "Cancel" (if presented modally). Standard iOS back behavior.
- Center: "NON-NEGOTIABLES" in `headline`, all caps, letter-spacing +1.5pt.
- Right: "Done" in `body`, `progress.blue`, bold. Saves changes and dismisses. Disabled (greyed) if no changes made.

### 4.3 Description Text

- Position: 16pt below nav bar, 16pt horizontal padding.
- Text: "Your daily requirements. Complete these before leisure time is unlocked."
- Font: `callout`, `text.secondary`.

### 4.4 Active Non-Negotiables List

#### Section Header
- Text: "ACTIVE ({count})" in `caption1`, `text.tertiary`, letter-spacing +1pt, all caps.
- Position: 24pt below description, 16pt leading.

#### List Items
Each is a row in a `List` or styled `VStack`:
- Height: 60pt.
- Background: `bg.card`. Corner radius: 12pt (if using VStack with individual cards) or 0 (if using grouped List style).
- Left: Drag handle (SF Symbol `line.3.horizontal`, 16pt, `text.tertiary`). 16pt leading padding.
- Icon: The non-negotiable's icon, 24pt, tinted by type color. 12pt after drag handle.
- Name: `headline`, `text.primary`. 12pt after icon.
- Target: `subheadline`, `text.secondary`, trailing. Format varies:
  - Timed: "2h / day"
  - Counter: "3 / day"
  - Binary: "1x / day"
- Disclosure: SF Symbol `chevron.right`, 14pt, `text.tertiary`. 16pt trailing padding.
- Tap: Navigates to Non-Negotiable Detail/Edit view (see 4.6).
- Drag: reorder via drag handle. Visual feedback: item lifts, shadow appears, other items shift.
- Swipe left: Delete. Red "Delete" action. Confirmation alert: "Remove '{name}'? This won't delete historical data."

### 4.5 Add Button

- Position: 12pt below the active list.
- Width: Full width minus 32pt.
- Height: 48pt.
- Style: Dashed border (2pt, `border.subtle`, dashed pattern: 8pt dash, 4pt gap). Corner radius: 12pt. No fill.
- Icon: SF Symbol `plus`, 18pt, `text.secondary`.
- Text: "Add Non-Negotiable" in `body`, `text.secondary`.
- Tap: Navigates to Non-Negotiable Creation flow (see 4.6).
- Disabled state: If 7 non-negotiables already exist. Text changes to "Maximum reached (7)". Color: `text.tertiary`.

### 4.6 Non-Negotiable Detail / Edit / Create View

Presented as a pushed view (navigation stack).

```
+------------------------------------------+
|  [< Back]     EDIT STUDY        [Delete] |
|                                          |
|  BASICS                                  |
|  Icon    [Book icon] [Change]            |
|  Name    [Study                     ]    |
|  Type    [Timed            v]            |
|                                          |
|  TARGET                                  |
|  Duration  [2] hours [0] minutes         |
|                                          |
|  TRACKING                                |
|  Method   [Manual Timer       v]         |
|                                          |
|  SCHEDULE                                |
|  Days active:                            |
|  [M][T][W][T][F][S][S]                   |
|   *  *  *  *  *  .  .                    |
|                                          |
|  PRIORITY                                |
|  Order    [1st - Most important v]       |
|                                          |
+------------------------------------------+
```

#### Fields

**Icon Picker**
- Current icon shown in a 48pt circle with `bg.cardElevated` background.
- "Change" text button next to it, `progress.blue`, `callout`.
- Tapping opens icon picker sheet (grid of SF Symbols, 6 columns, scrollable). Curated set of ~60 relevant icons: books, sports, food, health, creative, social, etc.

**Name**
- Text field, `body` font.
- Placeholder: "e.g., Study, Read, Meditate"
- Max length: 30 characters.
- Character counter appears when > 20 characters typed.
- Validates: non-empty. Shows red border and "Name is required" if submitted empty.

**Type Picker**
- Segmented control or dropdown.
- Options:
  - **Timed** -- Track duration. Shows duration picker below.
  - **Counter** -- Track count of something. Shows count target picker.
  - **Binary** -- Done or not done. No target picker needed.

**Duration Picker (if Timed)**
- Two steppers side by side: Hours (0-8, step 1) and Minutes (0-55, step 5).
- Default: 2h 0m for Study, 0h 30m for others.
- Minimum: 5 minutes. Maximum: 8 hours.

**Count Target (if Counter)**
- Stepper: 1-20, step 1. Default: 3.
- Unit label text field: e.g., "meals", "pages", "glasses". Default: "times".

**Tracking Method**
- Dropdown/Picker:
  - "Manual Timer" -- User starts/stops timer in-app. Available for Timed type.
  - "Manual Check" -- User taps to mark complete. Available for Binary type.
  - "Manual Counter" -- User taps + to increment. Available for Counter type.
  - "Whoop / HealthKit" -- Auto-detected from health data. Available for Binary type (training). Shows connection status.
  - "NutriTrack" -- Auto-detected from NutriTrack. Available for Counter type (meals). Shows connection status.
- Connection status: For auto-tracked methods, shows green dot "Connected" or red dot "Not Connected" with a "Connect" button.

**Days Active**
- Row of 7 circular toggles, one per day (M T W T F S S).
- Size: 36pt diameter each, 8pt spacing.
- Selected: `progress.blue` background, white text.
- Unselected: `bg.cardElevated` background, `text.secondary` text.
- Presets below the toggles (text buttons):
  - "Every Day" -- selects all.
  - "Weekdays" -- selects M-F.
  - "Weekends" -- selects S-S.
  - "Custom" -- manual selection (default state).
- At least 1 day must be selected. Error if all deselected: "Select at least one day."

**Priority/Order**
- Picker: "1st", "2nd", "3rd", etc. up to current count.
- Determines display order on main view.
- Alternative: Just use the drag-to-reorder on the list view, and remove this field.

#### Create Mode vs Edit Mode

- **Create Mode:** Title is "NEW NON-NEGOTIABLE". Right button is "Save" (blue, bold). All fields start at defaults.
- **Edit Mode:** Title is "EDIT {NAME}". Right button is "Delete" (red). All fields populated with current values.
- Delete confirmation: "Delete '{name}'? Historical data will be preserved but this non-negotiable will no longer appear in your daily list."

### 4.7 Templates

Position: Below add button, separated by 24pt and a section header "TEMPLATES".

Each template is a card:
- Height: 72pt.
- Background: `bg.card`. Corner radius: 12pt.
- Left icon: 32pt, `progress.blue` tint.
- Title: `headline`, `text.primary`.
- Subtitle: `footnote`, `text.secondary`. Lists what's included.
- Tap: Confirmation alert: "Apply '{template}' template? This will replace your current non-negotiables." Buttons: "Cancel", "Apply" (destructive-ish, blue).

#### Templates Available

**Student Athlete (default recommendation)**
- Icon: SF Symbol `graduationcap.fill`
- Creates: Study 2h (timed, manual, weekdays), Training 1x (binary, auto/Whoop, every day), Meals 3x (counter, auto/NutriTrack, every day)
- Weekend variant: Study 1h, Training 1x, Meals 3x

**Exam Week**
- Icon: SF Symbol `book.closed.fill`
- Creates: Study 4h (timed, manual, every day), Meals 3x (counter, auto/NutriTrack, every day)
- Training removed or made optional (appears greyed with "Optional" badge)
- Auto-activates Exam Mode notification tier

**Light Day**
- Icon: SF Symbol `sun.max.fill`
- Creates: Study 1h (timed, manual, every day), Meals 3x (counter, auto, every day)
- Meant for recovery/rest days

**Custom**
- Icon: SF Symbol `slider.horizontal.3`
- Opens the creation flow with all fields blank

### 4.8 Capacity Warning

If the user adds more than 5 non-negotiables, a persistent banner appears at the top of the list:

```
+------------------------------------------+
| [!] You have 6 non-negotiables. Research |
| shows 3-5 is optimal. More risks burnout |
| and reduces completion rates.   [Dismiss]|
+------------------------------------------+
```

- Background: `progress.amber` at 10% opacity.
- Border: 1pt `progress.amber`.
- Icon: SF Symbol `exclamationmark.triangle.fill`, `progress.amber`.
- Text: `footnote`, `text.primary`.
- Dismiss: hides for this session. Reappears on next visit if still > 5.
- Hard cap: 7 non-negotiables maximum.

---

## 5. Screen 4: Streak & Consistency View

Accessed from: Tab bar "Stats" tab, or tapping the streak counter anywhere it appears.

### 5.1 Screen Structure

```
+------------------------------------------+
|         CONSISTENCY           [Share]     |
|                                          |
|           [Flame Icon]                   |
|              12                          |
|          day streak                      |
|      Longest: 23 days                    |
|                                          |
|  +--------------------------------------+|
|  |        March 2026                    ||
|  | Mo Tu We Th Fr Sa Su                 ||
|  |                    1                  ||
|  |  2  3  4  5  6  7  8                 ||
|  |  9 10 11 12 13 14 15                 ||
|  | 16 17 18 19 20 21 22                 ||
|  | 23 24 25 26 27 28 29                 ||
|  | 30 31                                ||
|  +--------------------------------------+|
|                                          |
|  This Week          87%                  |
|  This Month         74%                  |
|  Perfect Weeks       3                   |
|                                          |
|  [Trend Chart - 90 days]                 |
|  100%|  *   *                            |
|   75%|** *** **  *                       |
|   50%|          ** **                    |
|   25%|                                   |
|    0%|________________________________   |
|      Jan        Feb        Mar           |
|                                          |
|  PER NON-NEGOTIABLE                      |
|  Study    ========== 82%                 |
|  Training ============ 91%               |
|  Meals    ======= 68%                    |
|                                          |
+------------------------------------------+
```

### 5.2 Streak Counter (Hero Section)

Position: Top of view, centered, 24pt below nav bar.

- **Flame icon:** SF Symbol `flame.fill`, 48pt, `streak.gold`. Animated: subtle flicker (scale 1.0 -> 1.05 -> 0.97 -> 1.0, randomized timing 1.5-2.5s cycle, infinite). If streak is 0, icon is grey and static.
- **Streak number:** `streakNumber` font (56pt), `text.primary`. Animated: rolls up like an odometer when value changes (each digit slides up independently, 0.3s stagger per digit, spring animation).
- **Label:** "day streak" in `callout`, `text.secondary`. Below number, 4pt gap.
- **Longest streak:** "Longest: 23 days" in `footnote`, `text.tertiary`. Below label, 4pt gap. Shows trophy icon (SF Symbol `trophy.fill`, 12pt, `streak.gold`) if current equals or exceeds longest.

#### Streak Calculation Rules
- A day "counts" toward the streak if ALL active non-negotiables for that day are completed (100%).
- Skipped non-negotiables (explicitly skipped by user) count as completed for streak purposes.
- Rest days / sick days do not break the streak.
- Missing data (app not opened, no activity) BREAKS the streak.
- Weekend: only weekend-active non-negotiables count.

### 5.3 Calendar Heatmap

Position: 16pt below streak section.

#### Layout
- Full-width card, `bg.card` background, 16pt corner radius, 16pt internal padding.
- Month/year title centered at top: `title3`, `text.primary`. Example: "March 2026".
- Navigation: Left/right chevrons on either side of month title. SF Symbol `chevron.left` / `chevron.right`, 16pt, `text.secondary`. Tap to go prev/next month. Cannot go beyond current month forward.
- Day-of-week headers: "Mo Tu We Th Fr Sa Su" in `caption2`, `text.tertiary`, evenly spaced.
- Day cells: 36pt square, 4pt corner radius, 4pt gap between cells.

#### Cell Colors

| Completion Rate | Color | Hex |
|----------------|-------|-----|
| 100% | Dark green | `#22C55E` at 100% opacity |
| 75-99% | Medium green | `#22C55E` at 65% opacity |
| 50-74% | Light green | `#22C55E` at 35% opacity |
| 25-49% | Yellow | `#EAB308` at 50% opacity |
| 1-24% | Orange | `#E63946` at 30% opacity |
| 0% (nothing done) | Red | `#E63946` at 60% opacity |
| No data (future) | Grey | `#484F58` at 20% opacity |
| Not applicable (before install) | Transparent | -- |
| Today | Any of above + 2pt `progress.blue` border | -- |
| Rest/sick day | Grey with diagonal stripe pattern | `#484F58` at 30% |

#### Cell Content
- Each cell shows the day number in `caption2`, centered.
- Text color: white if background is dark, `text.primary` if light.
- Today: bold text.

#### Cell Interaction
- Tap: Expands an overlay tooltip below the cell (or above if near bottom).
  - Tooltip shows:
    - Date: "Mon, Mar 24"
    - Completion: "3/3 complete (100%)"
    - Breakdown: "Study: 2h 15m, Training: Done, Meals: 3/3"
  - Background: `bg.cardElevated`. Corner radius: 8pt. Shadow. Arrow pointing to cell.
  - Dismisses on tap anywhere else.
- Long press: Navigates to that day's full Lockdown Main View in read-only historical mode.

### 5.4 Statistics Cards

Position: 16pt below calendar, arranged as a grid or vertical list.

#### Weekly Consistency
- Label: "This Week" in `subheadline`, `text.secondary`.
- Value: "87%" in `title2`, `text.primary`. Color-coded: green (>80%), amber (50-80%), red (<50%).
- Calculation: (completed non-negotiable-days / total non-negotiable-days this week) * 100. Partial completion of a non-negotiable counts proportionally.

#### Monthly Consistency
- Label: "This Month" in `subheadline`, `text.secondary`.
- Value: "74%" in `title2`, `text.primary`. Same color coding.

#### Perfect Weeks
- Label: "Perfect Weeks" in `subheadline`, `text.secondary`.
- Value: "3" in `title2`, `streak.gold`.
- A "perfect week" = every non-negotiable on every active day was completed (or explicitly skipped).
- Total since app install.

### 5.5 Trend Line Chart

Position: 16pt below stats, full-width card.

- **Card:** `bg.card`, 16pt corner radius, 16pt padding.
- **Title:** "90-Day Trend" in `headline`, `text.primary`, left-aligned.
- **Chart type:** Line chart with area fill.
- **X-axis:** Date. Shows month labels ("Jan", "Feb", "Mar"). Tick every 2 weeks.
- **Y-axis:** 0-100%. Grid lines at 25%, 50%, 75%, 100% -- dashed, `border.subtle`.
- **Data:** Daily completion percentage, smoothed with 7-day moving average.
- **Line:** 2pt stroke, `progress.blue`.
- **Area fill:** Gradient from `progress.blue` at 20% opacity to transparent.
- **Dot:** Small circle (6pt) on line for each data point. Only visible on hover/tap.
- **Interaction:** Scrub gesture -- drag finger horizontally to see daily values. A vertical hairline follows the finger, and a tooltip shows the date and percentage.
- **Empty state:** If < 7 days of data: "Keep going! Chart appears after 7 days of data." in `callout`, `text.secondary`, centered.

### 5.6 Per Non-Negotiable Breakdown

Position: 16pt below trend chart.

- **Section header:** "PER NON-NEGOTIABLE" in `caption1`, `text.tertiary`, letter-spacing +1pt.
- **Rows:** One per non-negotiable.
  - Icon: 20pt, color-coded.
  - Name: `body`, `text.primary`.
  - Progress bar: Horizontal, 8pt height, 4pt corner radius. Fill: green (>80%), amber (50-80%), red (<50%). Width proportional to percentage of full width minus label/value space.
  - Percentage: `body`, `text.secondary`, right-aligned.
- Calculation: (days completed / days active) * 100, for current month.
- Tap row: Navigates to individual non-negotiable history view (daily log list, same calendar heatmap filtered to this item).

### 5.7 Share Button

- Position: Navigation bar, trailing.
- Icon: SF Symbol `square.and.arrow.up`, 20pt, `text.secondary`.
- Behavior: Generates a shareable image (card-style, 1080x1350px for Instagram stories or 1:1 for general).
  - Content: Streak count with flame, calendar heatmap for current month, weekly consistency %.
  - Branding: "Tracked with Tempo" watermark, bottom, small.
  - Uses `UIGraphicsImageRenderer` to create the image.
  - Presents `UIActivityViewController` (share sheet).

---

## 6. Screen 5: Notification System

This is the behavioral core of the Lockdown module. The notification system uses a tiered escalation model grounded in behavioral psychology (see Section 11 for the full framework). Every design decision here -- the timing, the escalation, the copy -- is built on peer-reviewed research in habit formation, loss aversion, and commitment devices.

**Critical design principle -- the Losada Ratio:** Research on high-performing teams (Losada & Heaphy, 2004, though the precise ratio has been challenged) and therapeutic relationships (Gottman, 1994) consistently shows that sustainable motivation requires a ratio of approximately 3:1 to 5:1 positive-to-corrective feedback. Over a typical SUCCESSFUL day, the user should receive: 1 morning briefing (neutral/motivating), 0-1 gentle reminders (corrective), and 1 celebration (positive). On a STRUGGLING day: 1 briefing + up to 5 corrective + 0-1 celebration = a ratio that skews negative. To compensate, the system should fire MICRO-CELEBRATIONS for each individual non-negotiable completed (brief, not full Tier 5), ensuring the user receives positive feedback even on difficult days. This is implemented as in-app toast notifications: "Study: done. {done_count}/{total_count}. Keep going." -- appearing as a brief banner for 3 seconds when any non-negotiable reaches 100%.

### 6.1 Architecture Overview

```
Notification Engine
+-- Tier 0: Morning Briefing (scheduled, daily)
+-- Tier 1: Gentle Reminders (progress-triggered)
+-- Tier 2: Firm Warnings (time + progress-triggered)
+-- Tier 3: Urgent Alerts (time-triggered, escalating)
+-- Tier 4: Final Warning (critical, near-deadline)
+-- Tier 5: Completion Celebration (event-triggered)
+-- Tier 6: Weekly Summary (scheduled, weekly)
```

**Mapping to ONBOARDING_AND_NOTIFICATIONS.md `UNNotificationCategory` IDs:**

| Accountability Tier | Onboarding Category ID | Notes |
|---|---|---|
| Tier 0: Morning Briefing | `MORNING_BRIEFING` | Separate from accountability tiers |
| Tier 1: Gentle Reminders | `ACCOUNTABILITY_GENTLE` | |
| Tier 2: Firm Warnings | `ACCOUNTABILITY_FIRM` | |
| Tier 3: Urgent Alerts | `ACCOUNTABILITY_URGENT` | |
| Tier 4: Final Warning | `ACCOUNTABILITY_FINAL` | |
| Tier 5: Completion Celebration | `ACCOUNTABILITY_CLEAR` | "Clear" = all tasks cleared = celebration |
| Tier 6: Weekly Summary | `WEEKLY_SUMMARY` | |

All notifications use `UNUserNotificationCenter`. Each tier has a unique `threadIdentifier` for grouping. The app requests notification permission on first launch of Lockdown module, not on app install.

> **iOS 64 Pending Notification Limit (Technical Feasibility Audit Section 3.1):** iOS enforces a hard limit of 64 pending local notifications. On a busy day, Lockdown alone can generate 24-32 notifications. Strategy: schedule only today's notifications; fill remaining slots with tomorrow's morning briefing and first accountability tier; NEVER pre-schedule more than 48 hours out; rest timer notifications are scheduled one-at-a-time. Re-schedule on every app foreground event and daily via BGAppRefreshTask. See ONBOARDING_AND_NOTIFICATIONS.md for the full scheduling algorithm.

**Message Selection Algorithm:** Each tier maintains a pool of 50+ messages. Selection is weighted-random with recency suppression: messages used in the last 14 days are deprioritized (50% weight reduction), messages used in the last 7 days are excluded entirely. This ensures the user never sees the same message twice in a week and rarely in a month. All messages support template variables (wrapped in `{curly braces}`) that are filled at notification time from live user data.

### 6.2 Tier 0: Morning Briefing

**Trigger:** Scheduled daily at user-configured time. Default: 8:00 AM. Range: 6:00 AM - 11:00 AM (configurable in settings).

**Trigger Logic:**
- Fires every active day (respects weekend mode).
- Does NOT fire on rest/sick days.
- Does NOT fire if all non-negotiables are already complete (edge case: user on different timezone traveled).

**Content Template:**
Title: Dynamic (selected from pool below).
Body: Dynamic, data-driven, pulled from pool below.

**Notification Actions (buttons):**
- "Start Study" -- Deep links to Focus Timer View. Category identifier: `MORNING_BRIEFING`.
- "View Plan" -- Opens Lockdown Main View.

**Sound:** Default system sound (`UNNotificationSound.default`).

**Badge:** Sets app badge to number of incomplete non-negotiables for the day.

**Grouping:** `threadIdentifier: "lockdown-daily"`. Replaces previous day's briefing.

**Do Not Disturb:** Respects system DND. Uses `.timeSensitive` at most (per Technical Feasibility Audit: Critical Alerts entitlement will not be approved for a productivity app).

#### Morning Briefing Copy Pool (50 messages)

**Standard Intensity (messages 1-20):**

1. "Rise and execute. {count} non-negotiables today: Study {study_target}, {training_status}, {meal_count} Meals. Your {streak}-day streak is on the line."
2. "New day, same standard. Study {study_target}, Training, {meal_count} Meals. You've hit {streak} days straight. Keep building."
3. "Morning. Today's checklist: Study {study_target}, Train, {meal_count} Meals. Your streak ({streak} days) doesn't maintain itself."
4. "{count} tasks stand between you and a guilt-free evening. Study {study_target}. Train. Eat right. Streak: {streak}."
5. "Day {streak_plus_one} starts now. Study {study_target}, Training, {meal_count} Meals. Earn your PS5 time tonight."
6. "Your non-negotiables are live. {study_target} Study, Training, {meal_count} Meals. {streak}-day streak on the line. Let's go."
7. "Good morning. The clock started. {study_target} of study, training, {meal_count} meals. You have until {ps5_time}."
8. "It's {day_of_week}. {count} things to do before {ps5_time}. Study {study_target}. Train. Eat. That's the standard."
9. "{streak} days in a row. Today makes it {streak_plus_one}. Study {study_target}, Train, {meal_count} Meals. Don't drop the chain."
10. "Yesterday: done. Today: not yet. {count} non-negotiables. {study_target} study, training, {meal_count} meals. Move."
11. "The alarm went off. So did your accountability. Study {study_target}. Train. {meal_count} Meals. PS5 locked until you deliver."
12. "Morning report: {count} non-negotiables queued. Study {study_target}, Training, {meal_count} Meals. Streak at {streak}. Protect it."
13. "Same drill, new day. {study_target} study. Training. {meal_count} meals. {hours_until_ps5}h until PS5 time. That's your window."
14. "Today's non-negotiables are active. {count} tasks. {study_target} of study. One workout. {meal_count} meals. No shortcuts."
15. "Your {streak}-day streak needs one more day. It needs today. Study {study_target}. Train. Eat {meal_count} meals."
16. "Good morning. {count} items locked in. Study: {study_target}. Training: 1 session. Meals: {meal_count}. Clear them all by {ps5_time}."
17. "The only thing between you and PS5 tonight: {study_target} study, 1 workout, {meal_count} meals. Start early. Finish early."
18. "By this time yesterday you'd already {yesterday_first_action}. Set the same pace. {count} non-negotiables. Go."
19. "It's {current_time}. You have {hours_until_ps5} hours to complete {count} tasks. Study {study_target}. Train. {meal_count} Meals. Plan your day."
20. "Every day you complete is a vote for the person you're becoming. Today's ballot: {study_target} study, training, {meal_count} meals."

**Gentle Intensity (messages 21-35):**

21. "Good morning. Here's what's on your plate today: Study {study_target}, Training, {meal_count} Meals. You've got this."
22. "A new day, a new chance to show up for yourself. {count} non-negotiables ready. Streak: {streak} days."
23. "Today's plan: Study {study_target}, Train, eat {meal_count} meals. Take it one task at a time."
24. "Morning. Your {streak}-day streak is something to be proud of. Keep it going with {count} tasks today."
25. "Rise and shine. {study_target} of study, a workout, and {meal_count} meals. You've done this {streak} days running."
26. "Today is day {streak_plus_one}. Same routine that's been working: study, train, eat. You know the drill."
27. "Good morning. {count} things to check off today. Start whenever you're ready -- just start."
28. "Your non-negotiables are set: {study_target} study, training, {meal_count} meals. {streak} days and counting."
29. "New day, same commitment. {count} tasks. Your consistency over the last {streak} days is impressive. Keep it up."
30. "Morning check-in. Today: study {study_target}, train, {meal_count} meals. Your {streak}-day streak believes in you."
31. "Good morning. Small steps, big results. {count} non-negotiables. Start with the first one."
32. "The sun is up and so are your non-negotiables. Study {study_target}. Train. Eat {meal_count} meals. One at a time."
33. "Hey. {count} tasks today. Nothing you haven't handled before. {streak} days of proof."
34. "Your morning reminder: {study_target} study, training, {meal_count} meals. You're {streak} days strong. Today's no different."
35. "Good morning. The plan is simple: {count} non-negotiables. The execution is up to you. Streak: {streak}."

**Savage Intensity (messages 36-50):**

36. "Get up. {count} tasks. No excuses. Your {streak}-day streak doesn't care how you slept."
37. "Eyes open. Brain on. {study_target} study, training, {meal_count} meals. The PS5 is not yours until you earn it. Day {streak_plus_one}."
38. "Another day, another test. {count} non-negotiables. {study_target} study. Training. {meal_count} meals. You going to pass or fold?"
39. "Rise. {streak} days didn't happen by accident. {study_target} study, training, {meal_count} meals. Don't be the reason it ends today."
40. "Morning. The question isn't whether you feel like it. The question is whether you're the person who does it anyway. {count} tasks."
41. "Day {streak_plus_one}. Same non-negotiables. Same standard. {study_target} study. Training. {meal_count} meals. Stop reading this and go."
42. "The version of you that built a {streak}-day streak is watching. Don't embarrass him. {count} tasks. Start."
43. "Wake up. {study_target} of study isn't going to happen on the couch. Training isn't optional. {meal_count} meals aren't a suggestion. Move."
44. "Your {streak}-day streak means nothing if you quit today. {count} non-negotiables. {study_target} study. Training. {meal_count} meals. Prove it again."
45. "It's {day_of_week}. Last {day_of_week} you {last_week_same_day_result}. Today you do better. {count} tasks. Go."
46. "No warmup. No easing in. {count} non-negotiables, {hours_until_ps5} hours. Study {study_target}. Train. Eat {meal_count} meals. Clock's running."
47. "Your future self is begging you to start early. {study_target} study, training, {meal_count} meals. Don't make him regret today."
48. "The alarm was the easy part. Now execute. {count} tasks. {study_target} study. Training. {meal_count} meals. PS5 is earned, not given."
49. "You're {streak} days in. That's {streak} days of evidence that you can do this. Add another. {count} tasks. Start NOW."
50. "Discipline is choosing between what you want now and what you want most. {count} non-negotiables. {study_target} study. Training. {meal_count} meals. Choose."

**Context-Aware Variants (selected when conditions match, replace a standard message):**

- *After a streak break:* "Yesterday the streak broke. Today it restarts. Day 1. {count} non-negotiables. Study {study_target}. Train. {meal_count} Meals. Build it back."
- *After a perfect week:* "Last week: perfect. This week starts now. {count} non-negotiables. Keep the momentum."
- *Monday (fresh start effect):* "Monday. Fresh week. Clean slate. {count} non-negotiables. {study_target} study. Training. {meal_count} meals. Set the tone."
- *First of the month:* "New month. {month_name} starts with {count} non-negotiables. Study {study_target}. Train. {meal_count} meals. Make this month count."
- *Near streak milestone:* "You're {days_to_milestone} days from a {milestone}-day streak. Today is not the day to slip. {count} tasks."
- *Exam mode active:* "{exam_name} in {exam_days} days. Study target increased to {exam_study_target}. This is crunch time. No leisure until it's done."

### 6.3 Tier 1: Gentle Reminders

**Trigger Logic:**
- Time window: 12:00 PM - 3:00 PM.
- Condition: Completion < 50% AND at least one non-negotiable is 0% (not started at all).
- Frequency: Maximum 1 per day for this tier.
- Fires at: 1:00 PM (default) or first time the conditions are met within the window, checked every 30 min via background app refresh.

**Notification Actions:**
- "Start Timer" -- Deep links to Focus Timer.
- "Snooze 1h" -- Reschedules this notification for 1 hour later (max 1 snooze per day for this tier).

**Sound:** Default.

**Badge:** Updated to current incomplete count.

**Grouping:** `threadIdentifier: "lockdown-reminders"`.

#### Gentle Reminder Copy Pool (50 messages)

**Standard Intensity (messages 1-20):**

1. "Afternoon check-in. You haven't started studying yet. There's still time -- start a 25-minute session."
2. "Halfway through the day. {done_count}/{total_count} non-negotiables done. The evening's coming whether you're ready or not."
3. "Quick status: Study at {study_minutes} minutes. Training {training_status}. You've got the afternoon. Use it."
4. "It's {current_time} and your progress is at {completion_pct}%. Start now and you'll be done before dinner."
5. "Friendly reminder: your non-negotiables won't complete themselves. Tap to start your study timer."
6. "Afternoon. You're at {completion_pct}% for the day. {streak}-day streak needs you to show up."
7. "Study: {study_minutes} min / {study_target}. Training: {training_status}. Meals: {meals_done}/{meal_count}. The afternoon is yours."
8. "{hours_until_ps5} hours until PS5 time. You're at {completion_pct}%. A good study session right now changes everything."
9. "Check-in: {done_count} of {total_count} non-negotiables done. {not_started_list} haven't been touched. Start one."
10. "It's past noon and {not_started_item} is sitting at 0%. Even 25 minutes moves the needle."
11. "Your {streak}-day streak is still alive but it needs attention. Current progress: {completion_pct}%."
12. "By this time yesterday you were at {yesterday_pct_at_time}%. Today: {completion_pct}%. Let's close that gap."
13. "Afternoon reminder: {remaining_count} non-negotiable{remaining_plural} left. The hardest part is starting."
14. "Quick math: {hours_until_ps5} hours left. {remaining_tasks_summary}. It's doable if you start now."
15. "You haven't opened a study session today. Not one. 25 minutes. That's all it takes to get momentum."
16. "It's {current_time}. Your {not_started_item} card is staring at you. Stare back and tap Start Timer."
17. "Your non-negotiables are waiting. {done_count}/{total_count} complete. Start {not_started_item} and the rest will follow."
18. "Afternoon status: {completion_pct}%. You've done harder things than this. Open Tempo. Start a session."
19. "One Pomodoro. 25 minutes. That's the ask right now. Your study card is at {study_minutes} min."
20. "Just checking: did you forget about your non-negotiables or are you about to start? {completion_pct}% doesn't unlock PS5."

**Gentle Intensity (messages 21-35):**

21. "Hey. Gentle nudge: you're at {completion_pct}% for today. No rush, but the afternoon is a good time to start."
22. "Afternoon reminder. {remaining_count} tasks to go. Take it one at a time -- you've got hours."
23. "Your non-negotiables are still there. {done_count}/{total_count} done. Start when you're ready, just make sure you start."
24. "Friendly check-in: Study at {study_minutes} min, Training {training_status}, Meals {meals_done}/{meal_count}. You've got time."
25. "It's a good afternoon to tackle {not_started_item}. Even a short session counts."
26. "Reminder: {remaining_count} non-negotiable{remaining_plural} left for today. No pressure, but don't wait until evening."
27. "Quick thought: a 25-minute study session right now would bring you to {projected_pct}%. Worth it?"
28. "Your {streak}-day streak is waiting for today's contribution. {completion_pct}% so far. Keep going when you can."
29. "Afternoon. {not_started_item} is untouched. Start small -- even 10 minutes creates momentum."
30. "You're at {completion_pct}%. The afternoon is wide open. One task at a time."
31. "Hey. No judgment. Just a reminder: {remaining_count} tasks, {hours_until_ps5} hours. You've handled this before."
32. "Study reminder: {study_minutes} minutes logged so far. Start a session whenever you're ready."
33. "Checking in. {done_count}/{total_count} done. The rest of the day is plenty of time."
34. "Your afternoon is an opportunity. {remaining_tasks_summary}. Start with whichever feels easiest."
35. "Afternoon wave. {completion_pct}% complete. You're building something with this streak. Keep at it."

**Savage Intensity (messages 36-50):**

36. "It's the afternoon and you've done {done_count} out of {total_count}. The rest aren't going to magically complete. Open the app."
37. "Half the day is gone. Your progress: {completion_pct}%. That number should bother you. Fix it."
38. "{study_minutes} minutes of study. That's what you have to show for the entire morning. The afternoon better look different."
39. "{not_started_item}: 0%. ZERO. You've had since {morning_briefing_time} to start. What are you waiting for?"
40. "The PS5 doesn't care about your intentions. It cares about {completion_pct}% turning into 100%. Start studying."
41. "Your {streak}-day streak is hanging by a thread. {completion_pct}% at {current_time}. Is this really how day {streak_plus_one} goes?"
42. "Real talk: {done_count}/{total_count}. {not_started_list} untouched. You're not on vacation. Get to work."
43. "Afternoon check: {completion_pct}%. By this point on your best days, you're already at {best_day_pct_at_time}%. Close the gap."
44. "You have {hours_until_ps5} hours to go from {completion_pct}% to 100%. Or you have {hours_until_ps5} hours to guarantee a locked evening. Choose."
45. "Quick reality check: your non-negotiables are called non-negotiable for a reason. {remaining_count} left. Start."
46. "{not_started_item} has been at 0% for {hours_since_morning} hours. The avoidance ends now. Open the timer."
47. "Your future self at {ps5_time} is either relieved or frustrated. Right now you're deciding which one. {completion_pct}%. Start."
48. "You've used {hours_since_morning} hours and completed {done_count}/{total_count} non-negotiables. The math says: start now."
49. "The afternoon is a second chance. {remaining_count} tasks. {hours_until_ps5} hours. Use this window."
50. "At {completion_pct}%, you're on pace to fail today. That's not an insult, it's math. Change the trajectory. Start now."

### 6.4 Tier 2: Firm Warnings

**Trigger Logic:**
- Time window: 3:00 PM - 5:30 PM.
- Condition: Completion < 75%.
- Also fires if: A specific non-negotiable is 0% (not started) after 3 PM.
- Frequency: Maximum 2 in this window (at ~3:00 PM and ~4:30 PM, or as conditions are met).
- Does NOT fire if Tier 1 was snoozed and hasn't fired yet.

**Notification Actions:**
- "Start Now" -- Deep links to Focus Timer.
- "I'm On It" -- Dismisses, no snooze available for this tier.

**Sound:** A slightly more attention-grabbing sound. Custom sound: `firm_warning.caf` -- a double-tap tone, 0.5s, distinct from default.

**Badge:** Updated.

**Grouping:** `threadIdentifier: "lockdown-reminders"`. Groups with Tier 1.

#### Firm Warning Copy Pool (50 messages)

**Standard Intensity (messages 1-20):**

1. "It's {current_time}. You've studied {study_minutes} minutes out of {study_target}. That's not going to cut it."
2. "PS5 time is in {hours_until_ps5}. You're at {completion_pct}%. Pick up the pace or tonight is locked."
3. "Real talk: {done_count}/{total_count} non-negotiables done. You need to eat, study, and train before your evening. Clock's ticking."
4. "{current_time} reality check. Study: {study_minutes}min/{study_target}. Training: {training_status}. Meals: {meals_done}/{meal_count}. You know what needs to happen."
5. "Your future self is watching. He's either proud or disappointed. Right now you're at {completion_pct}%."
6. "The afternoon is slipping. {hours_until_ps5} until PS5 time and you're not even close to unlocking it."
7. "At your current pace, you'll finish at {projected_finish_time}. That's {minutes_after_ps5} minutes after PS5 time. Speed up."
8. "Study: {study_minutes}/{study_target}. That's {study_pct}%. You need {study_remaining} more. Start a session NOW."
9. "It's {current_time}. {remaining_count} non-negotiable{remaining_plural} incomplete. {hours_until_ps5} hours to close. This is the push."
10. "You're at {completion_pct}%. To unlock by {ps5_time}, you need to complete {remaining_tasks_summary}. The math is tight."
11. "{not_started_item} is still at 0%. It's been 0% all day. At some point 'I'll do it later' becomes 'I didn't do it.' Don't let that be today."
12. "Firm reminder: {study_remaining} of study and {other_remaining} still needed. {hours_until_ps5} until lockdown. No margin for error."
13. "Your {streak}-day streak is in danger. {completion_pct}% at {current_time} with a {ps5_time} deadline. Do the math."
14. "This time last week you were at {last_week_pct_at_time}%. Today: {completion_pct}%. {comparison_verdict}."
15. "Training: {training_status}. Study: {study_minutes}/{study_target}. Meals: {meals_done}/{meal_count}. The honest assessment: you're behind."
16. "You have {hours_until_ps5} hours to turn {completion_pct}% into 100%. Every 30 minutes you wait makes it harder."
17. "At {completion_pct}%, here's what's left: {remaining_tasks_detail}. Prioritize. Execute. No multitasking, just action."
18. "The PS5 controller is going to feel a lot better in your hands if you earn it. Right now: {completion_pct}%."
19. "3 PM checkpoint. {done_count}/{total_count} complete. You're in the danger zone. Next 2 hours decide if tonight is locked or unlocked."
20. "Your non-negotiables have a deadline: {ps5_time}. You're at {completion_pct}%. Treat this like a deadline, not a suggestion."

**Gentle Intensity (messages 21-35):**

21. "Hey, it's getting into the afternoon. You're at {completion_pct}%. Let's focus on getting {not_started_item} done."
22. "Progress check: {done_count}/{total_count}. You can still make today a good day. Start with the most important one."
23. "Afternoon is moving. {hours_until_ps5} hours until PS5 time. You're at {completion_pct}%. Let's pick up the pace."
24. "Your {not_started_item} could be done in {estimated_time}. That's shorter than an episode of anything. Start."
25. "Checking in: {completion_pct}% complete. Not where we want to be, but there's time. Focus on one thing."
26. "You've completed {done_count} of {total_count} today. The remaining {remaining_count} are doable. One at a time."
27. "Study is at {study_minutes} of {study_target}. A couple of focused sessions will close that gap. You've done it before."
28. "It's {current_time}. You're behind, but not out. {remaining_tasks_summary}. Start the biggest one first."
29. "Friendly but firm: {completion_pct}% won't unlock your evening. You need to start {not_started_item} soon."
30. "The afternoon is your opportunity. {hours_until_ps5}h left. {remaining_count} tasks. You can do this."
31. "A focused 2-hour block right now would change your entire evening. Study: {study_remaining} left. Let's go."
32. "Reminder: your {streak}-day streak is worth protecting. {completion_pct}% can still become 100%. Start now."
33. "You're running a bit behind today. That's OK. What matters is the next hour. Make it count."
34. "Hey. {not_started_item} needs your attention. Even starting is progress. The app is ready when you are."
35. "Afternoon push: {done_count}/{total_count} done. The trajectory matters more than the current score. Start climbing."

**Savage Intensity (messages 36-50):**

36. "It's {current_time}. {completion_pct}%. That number needs to change. Start studying or tonight stays locked."
37. "You've had since morning. Study: {study_minutes} minutes. The timer is one tap away. Open the app and press Start."
38. "{hours_until_ps5} hours. {completion_pct}%. Your evening depends on the next 120 minutes. Make them count."
39. "{not_started_item} at 0% after {hours_since_morning} hours. The pattern is procrastination. Break the pattern: open the timer right now."
40. "Your {streak}-day streak is about to become a 0-day streak. {completion_pct}% at {current_time}. Only you can change that."
41. "Study: {study_minutes}/{study_target}. Training: {training_status}. Meals: {meals_done}/{meal_count}. Those numbers need work. Start with study."
42. "The PS5 is locked and it's going to stay that way unless you stop scrolling, stop procrastinating, and start. NOW."
43. "At {completion_pct}%, you're on track for a locked evening. You can still turn this around. Start."
44. "Your boys are going to text about gaming tonight. Wouldn't it be better to say 'I'm ready'? {completion_pct}%. Go."
45. "Time for math. {study_remaining} of study left. {hours_until_ps5} hours. That means you need to start in the next {math_deadline} minutes. Period."
46. "You've been 'about to start' since morning. It's {current_time}. Starting doesn't mean thinking about starting. It means tapping Start Timer."
47. "At this rate, your weekly review is going to say '{day_of_week} was your worst day at {completion_pct}%.' Change the story."
48. "Every minute you spend not studying is a minute stolen from your evening. {study_remaining} left. The thief is you."
49. "Your {ps5_time} deadline doesn't negotiate. Neither do your non-negotiables. {completion_pct}%. React."
50. "{completion_pct}% with {hours_until_ps5} hours left. You're either about to have a redemption arc or a failure montage. Your move."

### 6.5 Tier 3: Urgent Alerts

**Trigger Logic:**
- Time window: 5:30 PM - configured PS5 time minus 30 minutes.
- Condition: Completion < 100% (ANY incomplete non-negotiable).
- Frequency: Every 30 minutes within the window. Maximum 3 notifications.
- First urgent alert at 5:30 PM, then 6:00 PM, then 6:30 PM (for default 7:30 PM PS5 time).

**Notification Actions:**
- "Start Timer" -- Deep links to Focus Timer (if study is incomplete).
- "Log Meal" -- Deep links to NutriTrack (if meals incomplete).
- "Dismiss" -- Dismisses but next tier still fires on schedule.

**Sound:** Custom escalating sound: `urgent_alert.caf` -- a three-tone ascending alert, 1s, impossible to ignore, clearly different from default notifications. Plays at system volume.

**Badge:** Updated. Badge shows remaining count with red indicator.

**Grouping:** `threadIdentifier: "lockdown-urgent"`. Separate thread from gentle/firm so they stack visibly.

#### Urgent Alert Copy Pool (50 messages)

**Standard Intensity (messages 1-20):**

1. "URGENT. {time_until_ps5} until PS5 time. You still need: {remaining_tasks_detail}. No excuses."
2. "The clock doesn't care about your excuses. {time_until_ps5} left. {incomplete_list} still incomplete."
3. "Evening approaching. Non-negotiables at {completion_pct}%. Incomplete: {remaining_tasks_detail}. Handle it NOW."
4. "This is not a drill. {time_until_ps5} until lockdown deadline. You're SHORT on: {incomplete_list}."
5. "{completion_pct}% is not 100%. You need {remaining_tasks_summary}. Get it done."
6. "{time_until_ps5} left on the clock. Outstanding: {remaining_tasks_detail}. Every minute counts."
7. "PS5 time at {ps5_time}. Current status: {completion_pct}%. Missing: {incomplete_list}. Start immediately."
8. "You're running out of time. {time_until_ps5} until deadline. {remaining_count} task{remaining_plural} undone."
9. "Alert: {study_remaining} of study + {other_remaining} still needed. Time remaining: {time_until_ps5}. This is tight."
10. "At {ps5_time} the lock status is final. Right now: {completion_pct}%. Missing: {incomplete_list}. Act."
11. "Urgent: your evening depends on the next {time_until_ps5}. Study: {study_status}. Training: {training_status}. Meals: {meals_done}/{meal_count}."
12. "{time_until_ps5} to go. {remaining_count} non-negotiable{remaining_plural} blocking your unlock. Prioritize and execute."
13. "This is your {hours_past_5pm}-hour warning. {completion_pct}%. {remaining_tasks_summary} remaining. No more delays."
14. "The window is closing. {time_until_ps5} until PS5 time. Status: {done_count}/{total_count}. Complete: {incomplete_list}."
15. "If you start {not_started_item} RIGHT NOW, you can finish by {projected_finish_time}. That's {minutes_before_ps5} minutes before deadline. Barely."
16. "Time check: {current_time}. PS5 lock check: {ps5_time}. Progress check: {completion_pct}%. Reality check: start now."
17. "Your {streak}-day streak has {time_until_ps5} left to survive. It needs: {remaining_tasks_summary}."
18. "{time_until_ps5}. That's it. {remaining_tasks_detail}. Finish what you started this morning."
19. "URGENT STATUS: Study {study_status}. Training {training_status}. Meals {meals_done}/{meal_count}. Deadline: {ps5_time}. Time remaining: {time_until_ps5}."
20. "Your non-negotiables close at {ps5_time}. {time_until_ps5} left. Currently missing: {incomplete_list}. Handle your business."

**Gentle Intensity (messages 21-35):**

21. "Evening is approaching. You're at {completion_pct}% with {time_until_ps5} to go. You can still make it."
22. "Heads up: {remaining_count} task{remaining_plural} left and {time_until_ps5} on the clock. Focus on the most important one first."
23. "Time is getting tight. {time_until_ps5} until PS5 time. {remaining_tasks_summary} to go. You've got this."
24. "It's getting close. {completion_pct}% done, {time_until_ps5} remaining. Start {not_started_item} now and you'll make it."
25. "Evening reminder: {remaining_count} non-negotiable{remaining_plural} still need attention. {time_until_ps5} left. Focus up."
26. "You're at {completion_pct}%. Not ideal, but {time_until_ps5} is enough if you start now. Prioritize."
27. "Hey. {time_until_ps5} left. {remaining_tasks_summary}. This is doable. Start with {easiest_remaining}."
28. "Getting close to deadline. {completion_pct}% done. A focused push right now finishes this. You've done it before."
29. "Time check: {time_until_ps5} until {ps5_time}. Tasks left: {remaining_count}. Break it into pieces and go."
30. "Your evening is {time_until_ps5} away. {remaining_tasks_summary} stands between you and a guilt-free night."
31. "You can still pull this off. {time_until_ps5} remaining. {remaining_tasks_detail}. One thing at a time."
32. "Almost evening. {completion_pct}% complete. {remaining_count} to go. Breathe, focus, execute."
33. "Reminder: {time_until_ps5} until the deadline. You need {remaining_tasks_summary}. Start the timer."
34. "You're close to PS5 time. {completion_pct}% done. The remaining {remaining_count} tasks are manageable if you start now."
35. "Evening push: {time_until_ps5} left. {remaining_tasks_detail}. Don't let the clock run out."

**Savage Intensity (messages 36-50):**

36. "Your boys are going to text soon. Are you going to tell them you can't play because you didn't handle your business?"
37. "{time_until_ps5}. That's all. {remaining_tasks_detail}. Every second you spend reading this is wasted. GO."
38. "URGENT. {completion_pct}% at {current_time}. You had ALL DAY. Now you have {time_until_ps5}. Scramble."
39. "The evening is {time_until_ps5} away and you're {remaining_tasks_summary} short. This is what happens when you procrastinate."
40. "Let's count: {remaining_tasks_detail}. Time: {time_until_ps5}. This is going to be tight because YOU made it tight."
41. "{time_until_ps5} minutes from now, you're either celebrating or regretting. The next hour decides. {completion_pct}% currently."
42. "Your {streak}-day streak is on life support. {completion_pct}% with {time_until_ps5} left. Only a sprint saves it."
43. "At {current_time}, with {time_until_ps5} left, and {remaining_count} tasks incomplete... what exactly is the plan? Because hoping isn't one."
44. "The lock at {ps5_time} is going to be red. Unless you start RIGHT NOW. {remaining_tasks_detail}. MOVE."
45. "You're about to lose your evening to procrastination. {time_until_ps5}. {remaining_count} tasks. Make a decision and execute."
46. "I've been here for {streak} days. Today needs the most from you. {completion_pct}% at {current_time}. Show up in the next {time_until_ps5}."
47. "{not_started_item}: STILL at 0%. It's {current_time}. This isn't a gentle reminder anymore. This is your last real window."
48. "Every notification I've sent today, you've ignored. {completion_pct}%. {time_until_ps5} left. I'll keep going. Will you?"
49. "PS5 at {ps5_time}. Current trajectory: LOCKED. Required: {remaining_tasks_summary} in {time_until_ps5}. The math is brutal because you waited."
50. "You want the honest truth? At {completion_pct}% with {time_until_ps5} left, tonight is probably locked. Unless you sprint. Starting NOW."

### 6.6 Tier 4: Aggressive Final Warning

**Trigger Logic:**
- Time: Configured PS5 time minus 15 minutes. (Default: 7:15 PM.)
- Condition: Completion < 100%.
- Frequency: Once. Then again AT PS5 time if still incomplete.
- In-app behavior: If the user opens Tempo within 5 minutes of this notification, a FULL-SCREEN ALERT covers the screen (see below).

**Sound:** Custom aggressive sound: `final_warning.caf` -- a sharp, staccato four-note descending tone, 1.5s. Uses `.timeSensitive` interruption level (per Technical Feasibility Audit: Critical Alerts entitlement is reserved for health/safety apps and will not be approved for a productivity app). For users who want maximum accountability, instruct them to enable "Always Deliver" for Tempo in Settings > Notifications, which bypasses Focus modes entirely (user-controlled, no entitlement needed).

**Interruption Level:** `.timeSensitive` -- breaks through Focus modes and DND (unless user has specifically silenced Tempo in Focus settings).

**Badge:** Shows red "!" indicator.

**Notification Actions:**
- "Start NOW" -- Deep links to the most urgent incomplete non-negotiable.
- "I Failed Today" -- Acknowledges. Triggers a softer follow-up tomorrow morning: "Yesterday didn't go as planned. Today's a fresh start. Here's what you need to do..."

#### Final Warning Copy Pool: 15-Minute Warning (50 messages)

**Standard Intensity (messages 1-20):**

1. "15 MINUTES. That's all you have. {remaining_tasks_detail}. PS5 stays LOCKED."
2. "This is it. 15 minutes until your PS5 time and you haven't finished. {incomplete_list}. The lock stays on."
3. "You had ALL DAY. 15 minutes left. Incomplete: {incomplete_list}. PlayStation is locked tonight unless you move NOW."
4. "15 min warning. At this point you're choosing to fail. Prove me wrong. {incomplete_list}."
5. "LOCKDOWN ACTIVE. 15 minutes to deadline. Outstanding: {incomplete_list}. Every second you read this is a second wasted."
6. "Final warning. Leisure LOCKED in 15 minutes. Still need: {incomplete_list}. There's still time if you start RIGHT NOW."
7. "15 minutes. {remaining_count} incomplete task{remaining_plural}. {remaining_tasks_detail}. This is your last chance today."
8. "Deadline: {ps5_time}. Status: {completion_pct}%. Missing: {incomplete_list}. 15 minutes. Make them count."
9. "Quarter hour warning. {completion_pct}% won't cut it. You need 100% by {ps5_time}. Outstanding: {incomplete_list}."
10. "At {ps5_time} the verdict is final. It's {current_time}. {remaining_tasks_detail}. Every second matters."
11. "15 minutes between you and a locked evening. {incomplete_list} still outstanding. Sprint."
12. "{streak} days. That's what you'll lose if you don't finish {incomplete_list} in the next 15 minutes."
13. "FINAL WARNING. Time: {current_time}. Deadline: {ps5_time}. Progress: {completion_pct}%. Required: {incomplete_list}. Move."
14. "15 minutes to turn this day around. {remaining_tasks_detail}. Or don't. But the lock doesn't bluff."
15. "This is the notification that decides your evening. 15 minutes. {remaining_count} task{remaining_plural}. {incomplete_list}."
16. "At this exact moment you are choosing between a locked and unlocked evening. 15 minutes. {incomplete_list}."
17. "You had {hours_in_day} hours. You used {hours_in_day} minus 15 minutes of them on everything except {incomplete_list}."
18. "WARNING. Your {streak}-day streak, your PS5 time, your guilt-free evening -- all require {incomplete_list} in 15 min."
19. "The difference between tonight being earned and tonight being regretted: {incomplete_list} in 15 minutes."
20. "15 minutes. {remaining_tasks_detail}. This is the moment you either step up or don't. No middle ground."

**Gentle Intensity (messages 21-30):**

21. "15 minutes until PS5 time. You still need {incomplete_list}. It's tight but not impossible. Go now."
22. "Almost at your deadline. {completion_pct}% done. {remaining_tasks_summary} left. Make the most of these 15 minutes."
23. "PS5 time is nearly here and {remaining_count} task{remaining_plural} remain. Do what you can in 15 minutes."
24. "Hey. 15 minutes. {incomplete_list} outstanding. Even partial progress is better than nothing. Start."
25. "Your deadline is close. {completion_pct}%. Give these last 15 minutes everything you've got."
26. "Nearly {ps5_time}. {remaining_tasks_summary} left to do. A focused 15-minute push could save your streak."
27. "Time check: 15 minutes until your evening begins. {incomplete_list} still need attention."
28. "Close to deadline. You can still get {achievable_in_15} done if you start immediately."
29. "15 minutes left in the day. {completion_pct}% complete. Focus on the most impactful task right now."
30. "Almost there. Not quite done. 15 minutes and {remaining_count} task{remaining_plural}. Every minute counts."

**Savage Intensity (messages 31-50):**

31. "15 MINUTES. The whole day led to this. {incomplete_list}. Sprint. NOW."
32. "{completion_pct}% with 15 minutes left. {incomplete_list}. You had since morning. This is your last window. USE IT."
33. "15 minutes. The PS5 is right there and you can't touch it because today got away from you. {incomplete_list}. Take it back."
34. "Your friends are about to hop on. 15 minutes to join them guilt-free. {completion_pct}%. {incomplete_list}. Move."
35. "{completion_pct}% at {current_time}. That's the reality. 15 minutes is the opportunity. Prove you can clutch up. {incomplete_list}."
36. "15 minutes. {remaining_tasks_detail}. The procrastination ends right here, right now."
37. "FINAL WARNING. {streak} days on the line. {incomplete_list}. 15 minutes. You are the only one who can save this."
38. "The lock is about to slam shut. {incomplete_list}. 15 minutes. Not 30. Not an hour. FIFTEEN."
39. "In 15 minutes this notification becomes: 'LOCKED.' You can still change the ending. {incomplete_list}."
40. "Every 'I'll do it later' today led here. It's 15 minutes from being too late. {incomplete_list}. Go."
41. "15 minutes. {remaining_count} tasks. {completion_pct}% when you needed 100. This is where discipline is tested."
42. "You're 15 minutes from hearing yourself say 'I should have started earlier.' You can still avoid that. {incomplete_list}. GO."
43. "{streak} days of discipline on the line. 1 focused push is all it takes. 15 minutes. {incomplete_list}."
44. "Your calendar had {hours_in_day} hours. 15 minutes left. Salvage what you can. {incomplete_list}."
45. "LAST CHANCE. {current_time}. Deadline: {ps5_time}. Remaining: {incomplete_list}. What are you going to do about it?"
46. "15 minutes from now you'll feel either pride or regret. The only variable is what you do RIGHT NOW. {incomplete_list}."
47. "If your {streak}-day streak survives tonight, it'll be because of what you do in the next 15 minutes. {incomplete_list}."
48. "This is it. The last notification before the lock. 15 minutes. {incomplete_list}. Make them count."
49. "Imagine how good PS5 will feel knowing you earned it. 15 minutes. {incomplete_list}. Earn it."
50. "FIFTEEN MINUTES. Not a typo. Not a drill. {remaining_tasks_detail}. The lock is counting down. Are you?"

#### Final Warning Copy Pool: At PS5 Time / Locked (25 messages)

1. "PS5 time. Leisure: LOCKED. You didn't finish. {remaining_tasks_detail}. Tomorrow, be better."
2. "Time's up. Lock status: LOCKED. You had {hours_in_day} hours. Don't let this become a pattern."
3. "Lockdown enforced. Tonight's gaming is unearned. {done_count}/{total_count} non-negotiables done. Not enough."
4. "The evening is here and you're not ready. Locked. {incomplete_list}. Tomorrow starts at {morning_briefing_time}."
5. "LOCKED. You left {remaining_tasks_detail} on the table. Your streak is broken at {streak} days."
6. "Time: {ps5_time}. Status: LOCKED. Completed: {done_count}/{total_count}. Streak: ended. Tomorrow is day 1."
7. "Your evening is locked. {remaining_tasks_detail} wasn't done. The PS5 will still be there tomorrow -- after you earn it."
8. "Locked. {completion_pct}% doesn't unlock anything. {incomplete_list} unfinished. Tomorrow, start earlier."
9. "LOCKDOWN. Final status: {done_count}/{total_count}. Missing: {incomplete_list}. Your {streak}-day streak needed today. Tomorrow it gets a fresh chance."
10. "PS5 time arrived. You didn't. Locked at {completion_pct}%. Tomorrow's a new day. Make it different."
11. "The lock is red. {remaining_tasks_detail} undone. {streak} days ended. The only question now: what do you do tomorrow?"
12. "Locked. {incomplete_list} unfinished. The system held the standard. Tomorrow, meet it."
13. "Time expired. Leisure: LOCKED. {remaining_count} task{remaining_plural} incomplete. Tonight is a consequence. Tomorrow is an opportunity."
14. "The day is over. Your non-negotiables aren't. LOCKED. {completion_pct}%. Let this sting motivate tomorrow."
15. "Locked. {done_count}/{total_count}. That's the number. Not the one you wanted. Use the frustration. Come back stronger."
16. "{ps5_time}. LOCKED. {incomplete_list} unfinished. Your streak ({streak} days) is done. Rebuilding starts {morning_briefing_time} tomorrow."
17. "Evening locked. {completion_pct}% final. {streak}-day streak broken. There's nothing to say except: tomorrow, Day 1."
18. "LOCKED. The PS5 stays dark tonight. {remaining_tasks_detail} weren't done. You know why. Fix it tomorrow."
19. "Final status: LOCKED. {done_count}/{total_count} completed. {streak} days ended. I'll be here at {morning_briefing_time} tomorrow. Will you?"
20. "Locked. Not your best day. {completion_pct}% final. But one bad day doesn't define you. Tomorrow defines you."
21. "Time's up. Locked at {completion_pct}%. The {streak}-day streak is gone. Feel it. Remember it. Use it."
22. "LOCKED. {remaining_count} task{remaining_plural} unfinished. {study_remaining} of study left on the table. {meals_remaining} meal{meals_remaining_plural} skipped. Tomorrow: day 1."
23. "The lock is final. {completion_pct}%. One bad day is data, not a verdict. Use it to plan a better tomorrow."
24. "Locked. That's the result. Not the intention. The result. {incomplete_list}. Reset. Refocus. Return. Tomorrow."
25. "PS5 LOCKED. Streak BROKEN. {completion_pct}% FINAL. Tomorrow you rebuild. Tonight you reflect."

#### Full-Screen In-App Alert

If the user opens Tempo while Tier 4 conditions are active (within 15 min of PS5 time and tasks incomplete):

```
+------------------------------------------+
|                                          |
|                                          |
|          [Large Lock Icon, 80pt]         |
|          [Pulsing red glow]              |
|                                          |
|            LOCKED                        |
|                                          |
|     You have 12 minutes.                 |
|                                          |
|     Study: 37 min remaining              |
|     Dinner: Not logged                   |
|                                          |
|     ________________________________     |
|                                          |
|     [ START STUDY TIMER ]                |
|     [ LOG MEAL IN NUTRITRACK ]           |
|     [ I Accept the L ]                   |
|                                          |
+------------------------------------------+
```

- Background: `bg.primary` with deep red vignette at edges (radial gradient, `locked.red` at 20% opacity).
- Lock icon: 80pt, `locked.red`, pulsing glow (shadow radius oscillates 10pt -> 20pt -> 10pt, 1.5s cycle, `locked.red`).
- "LOCKED" in `largeTitle`, `locked.red`.
- Time remaining: `title2`, `text.primary`. Updates in real-time.
- Incomplete items: listed with `body` font, `text.secondary`.
- Action buttons: Full-width, stacked vertically, 12pt gap.
  - "START STUDY TIMER" -- `progress.blue` background, white text, 56pt height.
  - "LOG MEAL IN NUTRITRACK" -- `progress.blue` outlined (border only), `progress.blue` text, 56pt height.
  - "I Accept the L" -- No background, `text.tertiary` text, `callout` font. Tapping dismisses the overlay and takes user to main view with everything marked as failed.
- Cannot be dismissed by swiping or tapping background. Only the three buttons dismiss it.
- Appears once per day maximum.

### 6.7 Tier 5: Completion Celebration

**Trigger:** All non-negotiables for the day reach 100%.

**Fires:** Immediately upon completion. As a local notification if app is backgrounded, or in-app celebration if app is foregrounded.

**Sound:** Custom celebration sound: `celebration.caf` -- a bright, ascending three-note chime with a subtle sparkle, 1.5s. Joyful but not obnoxious.

**Haptic:** Triple `.success`, 200ms apart.

**Notification Actions:**
- "Nice!" -- Dismisses.
- "Share" -- Opens share sheet with a streak card image.

**In-App Celebration (if foregrounded):**
- Confetti animation: 80 particles, gold/green/blue, 3s duration, physics-based fall.
- Full-screen green glow pulse (2 cycles).
- Lock icon animates from locked to unlocked (spring, rotation, scale).
- Sound plays.
- Haptics fire.
- Auto-dismisses after 3 seconds, leaving the main view in unlocked state.

**Badge:** Cleared to 0.

#### Completion Celebration Copy Pool (50 messages)

**Standard Intensity (messages 1-20):**

1. "ALL CLEAR. Non-negotiables: DONE. Leisure: UNLOCKED. You earned tonight. Enjoy it guilt-free."
2. "UNLOCKED. Every single non-negotiable -- done. {streak}-day streak. Go enjoy your evening, you've earned it."
3. "Mission complete. Study: {study_total}. Training: Done. Meals: {meals_done}/{meal_count}. Your evening is yours. No guilt."
4. "That's how it's done. 100% complete. Streak extended to {streak} days. PS5 is unlocked. Have fun."
5. "Non-negotiables: handled. Leisure: earned. Streak: {streak} days and counting. This is what discipline looks like."
6. "UNLOCKED. Everything done with {time_before_ps5} to spare before PS5 time. Ahead of schedule."
7. "100%. All done. {streak} days strong. Your evening is fully earned. No asterisks."
8. "Leisure unlocked. Study: {study_total}. Training: complete. Meals: logged. Streak: {streak}. Well done."
9. "You did it. Again. Day {streak}. {total_count}/{total_count} non-negotiables cleared. Enjoy the evening."
10. "DONE. Everything checked off. Your PS5 time tonight comes with zero guilt. {streak}-day streak."
11. "Non-negotiables complete. Leisure status: UNLOCKED. {streak} days of consistency. The evening is yours."
12. "All tasks: DONE. Time: {completion_time}. Streak: {streak} days. That's the report. Go enjoy yourself."
13. "100% complete. You earned every second of tonight. {streak} days and counting."
14. "Lock status: UNLOCKED. Progress: 100%. Streak: {streak} days. That's a wrap for today."
15. "All clear. {total_count} non-negotiables handled. Study: {study_total}. The rest of the night is yours."
16. "UNLOCKED at {completion_time}. {time_before_ps5} before PS5 time. Efficient. {streak}-day streak extended."
17. "Today's non-negotiables are in the books. 100%. {streak} days. Tomorrow we do it again."
18. "Done, done, done. Every non-negotiable cleared. Streak alive at {streak} days. Guilt-free evening activated."
19. "COMPLETE. {study_total} studied. Trained. Fed. {streak} days straight. The PS5 controller is waiting."
20. "Status: UNLOCKED. All {total_count} non-negotiables at 100%. Day {streak} is official."

**Gentle Intensity (messages 21-35):**

21. "Hey, you did it. All non-negotiables complete. Your evening is earned. Enjoy. {streak} days strong."
22. "Everything's done. Nice work today. {streak}-day streak continues. Have a great evening."
23. "All tasks complete. You showed up for yourself again. Day {streak}. Enjoy your free time."
24. "Unlocked. You handled everything on your list. That deserves a good evening. {streak} days."
25. "Great job. {total_count}/{total_count} complete. Your streak is now {streak} days. Rest well tonight."
26. "Done for the day. Study: {study_total}. Training: done. Meals: logged. Go relax -- you earned it."
27. "All done. {streak} days of showing up. Your evening is yours. Be proud of the consistency."
28. "Finished. Every non-negotiable checked off. {streak} days running. Have a wonderful evening."
29. "You completed everything. Again. That's {streak} days. Enjoy your free time without looking back."
30. "All clear. Non-negotiables handled. The evening is open. You're building something great at {streak} days."
31. "Done. You did what you said you'd do. {streak} days. That matters. Enjoy tonight."
32. "Everything on the list: complete. Streak: {streak} days. You should feel good about today."
33. "Task list: cleared. Leisure: unlocked. Streak: {streak}. Well done. Go have fun."
34. "All non-negotiables finished. Your consistency is impressive. Day {streak}. Enjoy the rest of your evening."
35. "Complete. {total_count} tasks done. {streak} days. You keep showing up and that's what counts."

**Savage Intensity (messages 36-50):**

36. "UNLOCKED. Every. Single. Task. Done. {streak} days. You just proved you're not soft. Go game."
37. "100%. That's the only number that matters and you hit it. {streak} days of not making excuses. PS5 earned."
38. "DONE. While most people would have quit at Tier 2, you finished. {streak} days. That's discipline."
39. "All clear. {study_total} studied. Trained. Fed. {streak} days. The PS5 isn't a reward -- it's evidence you handled your business."
40. "Completed before {ps5_time}. {time_before_ps5} to spare. That's not just done -- that's domination. {streak} days."
41. "UNLOCKED. You did what you said you'd do. No excuses. No skips. {streak} days straight. Go be great tonight."
42. "100%. The lock is green. {streak} days and you haven't blinked. The PS5 is waiting. You earned every pixel."
43. "Day {streak}: CONQUERED. Study: {study_total}. Training: done. Meals: done. You're becoming the person who always finishes."
44. "UNLOCKED. {streak} consecutive days of execution. Most people can't do {streak} consecutive days of anything. Remember that."
45. "Done. Everything. {streak} days. Your past self who started this streak would be proud. Now go enjoy what you built."
46. "STATUS: UNLOCKED. Not because it was easy. Because you did it anyway. {streak} days. Go celebrate."
47. "All tasks cleared. {streak} days strong. You showed up when it mattered. That's the only metric. PS5: ON."
48. "COMPLETE. {total_count}/{total_count}. {streak} days. You're not the person who quits anymore. Go have a legendary evening."
49. "100% with {time_before_ps5} to spare. {streak} days. You didn't just complete today -- you dominated it."
50. "UNLOCKED. {streak} days of being better than yesterday. The PS5 didn't earn you. You earned the PS5."

**Context-Aware Celebration Variants (selected when conditions match):**

- *All done before noon:* "ALL DONE BY NOON. {total_count}/{total_count} before most people eat lunch. {streak}-day streak. The rest of the day is completely yours."
- *New longest streak:* "NEW RECORD. {streak} days. Your longest streak EVER. You just made history. Enjoy tonight -- you're in uncharted territory."
- *Perfect week completed:* "PERFECT WEEK. 7 for 7. Every day, every task. {streak}-day streak. This is what peak discipline looks like."
- *After a previous day failure:* "You failed yesterday. Today you didn't. THAT is the response. Day 1 of the new streak. {total_count}/{total_count}. Keep this energy."
- *5-day completion streak bonus:* "5 DAYS STRAIGHT. 100% every single day. Bonus hour of guilt-free leisure unlocked for tomorrow. You've earned an early unlock."
- *Exam mode survival:* "Exam mode. Enhanced targets. You still finished 100%. {streak} days. This is built different. {exam_name} doesn't stand a chance."
- *Completed during comeback (was behind at Tier 3):* "THE COMEBACK. You were at {pct_at_tier3}% when the urgent alerts hit. You finished at 100%. That's clutch. {streak} days."
- *Streak recovery successful:* "STREAK RECOVERED. {restored_streak} days. You fell, you got back up. That is the only metric that matters."
- *Best focus score ever:* "NEW PERSONAL BEST. Focus score: {focus_score}. Your sharpest session yet. The discipline is sharpening your mind."
- *Fastest completion ever:* "SPEED RECORD. All done by {completion_time}. That's the earliest you've ever finished. More evening, more earned."
- *3 consecutive 90%+ days:* "Three days in a row above 90%. Your consistency is compounding. This is how real change happens."
- *First day back after absence:* "DAY 1 COMPLETE. You came back and you delivered. Showing up after time away is the hardest part. You did it."

**Behavioral science note on celebration messages:** Research on positive reinforcement (Skinner, 1953; Cameron & Pierce, 1994 meta-analysis) consistently shows that positive reinforcement following a behavior increases the likelihood of that behavior recurring. Critically, the reinforcement should be (1) immediate (Tier 5 fires immediately on completion), (2) specific (messages reference exact data: study hours, streak count, time of completion), and (3) varied (50+ messages prevent habituation). The celebration pool should be at LEAST as large and varied as the warning pools. Humans respond to positive reinforcement approximately 3-5x more strongly than punishment for behavior maintenance (Daniels & Daniels, 2004, *Performance Management*).

### 6.8 Tier 6: Weekly Summary

**Trigger:** Sunday at 8:00 PM (configurable). If user is in exam mode, also fires Wednesday at 8:00 PM (mid-week check).

**Sound:** Default.

**Badge:** Not modified.

**Notification Actions:**
- "View Full Report" -- Opens weekly report view.
- "Dismiss" -- Standard dismiss.

#### Weekly Summary Copy Pool (50 messages)

**Verdict Logic (determines which message sub-pool to draw from):**
- 100%: Perfect
- 90-99%: Near-Perfect
- 75-89%: Solid
- 50-74%: Below Standard
- <50%: Poor

**Perfect Week (messages 1-10):**

1. "PERFECT WEEK. {completed}/{total} non-negotiables. {study_hours}h studied. Streak: {streak} days. No notes."
2. "100% this week. Every task, every day. Study: {study_hours}h. Training: {training_days}/{training_target}. Meals: {meals_count}/{meals_target}. Flawless."
3. "Perfect week. {streak} days. {study_hours}h of study. {perfect_weeks_total} perfect weeks total. You're building a legacy."
4. "7 for 7. Every non-negotiable on every day. That's rare. {streak}-day streak. Study total: {study_hours}h."
5. "This week: perfection. {completed}/{total} non-negotiables. You set the standard and met it every single day."
6. "Week review: 100%. Not 99%. 100%. {study_hours}h studied. {training_days} workouts. {meals_count} meals. {streak} days straight."
7. "Perfect week #{perfect_weeks_total}. {completed}/{total} complete. Study: {study_hours}h. Your consistency is your superpower."
8. "Your week: flawless. {study_hours}h study, {training_days} training days, {meals_count} meals logged. Streak at {streak}. Next week, same energy."
9. "100% completion. Every day. Every task. {streak} days running. This is the version of you that wins."
10. "This week was perfect. {study_hours}h of study across {study_sessions} sessions. {streak}-day streak. The bar is set."

**Near-Perfect Week (messages 11-20):**

11. "Almost perfect. {completed}/{total} ({weekly_pct}%). Study: {study_hours}h. Missed: {missed_summary}. Close the gap next week."
12. "This week: {weekly_pct}%. {missed_count} slip{missed_plural}. {weakest_item} needs attention. Streak: {streak} days."
13. "{weekly_pct}% this week. One or two slips. Tighten up. {weakest_item} was the weak link at {weakest_pct}%."
14. "Week review: {completed}/{total}. Near-perfect. Missed: {missed_summary}. {study_hours}h studied. {streak} days. Almost there."
15. "{weekly_pct}%. So close to perfect. {weakest_item} dropped you. Fix that one thing and next week is 100%."
16. "This week: {weekly_pct}%. Best day: {best_day} ({best_day_pct}%). Worst: {worst_day} ({worst_day_pct}%). Streak: {streak}."
17. "Almost perfect at {weekly_pct}%. {study_hours}h of study. {weakest_item} at {weakest_pct}% is the gap. Address it."
18. "{completed}/{total} non-negotiables. {weekly_pct}%. The {missed_count} miss{missed_plural} cost you perfection. But {streak} days strong."
19. "Week: {weekly_pct}%. Missed: {missed_summary}. You know what slipped. You know why. Don't let it repeat."
20. "Near-perfect at {weekly_pct}%. Study: {study_hours}h. Training: {training_days}/{training_target}. Meals: {meals_count}/{meals_target}. {streak} days."

**Solid Week (messages 21-30):**

21. "Solid but not great. {weekly_pct}% this week. {weakest_item} needs attention. Study: {study_hours}h. Streak: {streak}."
22. "This week: {weekly_pct}%. {completed}/{total}. {weakest_item} at {weakest_pct}% is dragging you down. Fix it."
23. "{weekly_pct}%. Not your best, not your worst. Study: {study_hours}h. Training: {training_days}/{training_target}. Room for improvement."
24. "Week review: {weekly_pct}%. Best day: {best_day}. Worst: {worst_day} at {worst_day_pct}%. Streak: {streak}. Next week, aim higher."
25. "{completed}/{total} this week ({weekly_pct}%). {weakest_item} and {second_weakest_item} need focus. You can do better."
26. "This week was OK. {weekly_pct}%. Study: {study_hours}h (target: {study_weekly_target}h). {weakest_day} was rough at {worst_day_pct}%."
27. "Week at {weekly_pct}%. The pattern: {pattern_insight}. Address the pattern, not just the symptom."
28. "{weekly_pct}% completion. {streak} days streaking. But consistency is dropping. {weakest_item}: {weakest_pct}%. Recommit."
29. "Honest review: {weekly_pct}%. You showed up most days but {missed_summary}. Next week target: {target_pct}%."
30. "This week: {completed}/{total}. Study: {study_hours}h. Your {worst_day} was {worst_day_pct}%. Every other day was {other_avg}%. Eliminate the bad days."

**Below Standard (messages 31-40):**

31. "Below your standard. {weekly_pct}% this week. {worst_day} was {worst_day_pct}%. {weakest_item} at {weakest_pct}%. Recommit."
32. "{weekly_pct}%. That's below where you should be. Study: {study_hours}h (target: {study_weekly_target}h). Training: {training_days}/{training_target}."
33. "Tough week. {completed}/{total} ({weekly_pct}%). {missed_count} missed non-negotiable{missed_plural}. Streak: {streak}. Don't let this slide."
34. "Week review: {weekly_pct}%. You had {failed_days} failed day{failed_days_plural}. {weakest_item} was worst at {weakest_pct}%."
35. "This week wasn't good enough. {weekly_pct}%. {study_hours}h of study when you planned {study_weekly_target}h. Gap: {study_gap}h."
36. "{weekly_pct}% completion. {worst_day}: {worst_day_pct}%. {second_worst_day}: {second_worst_pct}%. The bad days are adding up."
37. "Below standard at {weekly_pct}%. {weakest_item}: {weakest_pct}%. That's {missed_count_item} missed day{missed_count_item_plural}. This needs fixing."
38. "Week: {weekly_pct}%. Streak: {streak} (but barely). Study gap: {study_gap}h. Training gap: {training_gap}. Course correct now."
39. "{completed}/{total} this week. {weekly_pct}%. If this trend continues, you'll be at {projected_monthly_pct}% for the month. Not acceptable."
40. "This week: {weekly_pct}%. Last week: {last_week_pct}%. Direction: {trend_direction}. {trend_commentary}."

**Poor Week (messages 41-50):**

41. "Tough week. {weekly_pct}%. This isn't who you want to be. Fresh start Monday."
42. "{weekly_pct}%. {failed_days} out of 7 days failed. Study: {study_hours}h (needed {study_weekly_target}h). Hard reset needed."
43. "Week review: {weekly_pct}%. Let's be real -- this was a bad week. {study_hours}h of study. {training_days} training days. Unacceptable."
44. "{completed}/{total} non-negotiables ({weekly_pct}%). {failed_days} failed days. Streak: {streak}. You're better than this. Prove it Monday."
45. "This week: {weekly_pct}%. I won't sugarcoat it. {weakest_item} at {weakest_pct}%. {worst_day} was 0%. Monday is a fresh start."
46. "{weekly_pct}%. Study: {study_hours}h. Training: {training_days}/{training_target}. Meals: {meals_count}/{meals_target}. Every number is below target. Reset."
47. "The numbers don't lie. {weekly_pct}% this week. {failed_days} complete failures. But you're still here, which means Monday has potential."
48. "Week: {weekly_pct}%. Last week: {last_week_pct}%. The slide continues. Something needs to change. What is it?"
49. "Honest talk: {weekly_pct}% for the week. That's a failing grade. But one bad week isn't a life sentence. Monday: Day 1."
50. "{weekly_pct}%. Look at that number. Now decide: is next week going to look the same, or are you going to do something about it?"

### 6.9 Notification Settings & Behavior

#### Per-Tier Enable/Disable
Each tier (0-6) can be individually enabled/disabled in Settings. Default: all enabled.

#### Quiet Hours
User can set quiet hours during which no Lockdown notifications fire. Default: 11:00 PM - 7:00 AM. Exception: Tier 4 at PS5 time fires regardless if it falls within quiet hours (since PS5 time is user-configured and shouldn't conflict).

#### Intensity Level

Global intensity with 4 levels (aligned with ONBOARDING_AND_NOTIFICATIONS.md and DATA_MODELS_IOS.md):

| Setting Name | Data Model Value | Copy Pool | Onboarding Code | Tiers That Fire |
|-------------|-----------------|-----------|-----------------|-----------------|
| **Gentle Coach** | `notificationIntensity: 1` | Gentle Intensity | G | Tiers 0, 1, 5, 6 only. No firm/urgent/aggressive notifications. |
| **Firm Coach** (default) | `notificationIntensity: 2` | Standard Intensity | F | Tiers 0-3, 5, 6. Tier 4 only at PS5 time, not 15 min before. |
| **Drill Sergeant** | `notificationIntensity: 3` | Savage Intensity | D | All tiers fire, including Tier 4 at both -15 min and at PS5 time. Tougher copy variations. |
| **Savage Mode** | `notificationIntensity: 4` | Savage+ Intensity | S | All tiers fire. Full-screen alert enabled. Most aggressive copy. No quiet hours exception. |

#### PS5 Time Configuration
- Default: 7:30 PM.
- Range: 5:00 PM - 11:00 PM (30-minute increments).
- This sets the anchor for Tier 3 and Tier 4 timing.
- Can vary by day of week (e.g., 7:30 PM weekdays, 9:00 PM weekends).

#### Badge Count
- Badge = number of incomplete non-negotiables.
- Cleared to 0 when all complete or at midnight (reset).
- Clears on any app open (standard iOS behavior) but re-sets on next notification.

#### Notification Grouping
- Tiers 0-2 share `threadIdentifier: "lockdown-daily"` -- grouped together in notification center.
- Tiers 3-4 use `threadIdentifier: "lockdown-urgent"` -- visually separated, more prominent.
- Tier 5 uses `threadIdentifier: "lockdown-celebration"`.
- Tier 6 uses `threadIdentifier: "lockdown-weekly"`.

#### DND / Focus Mode Respect
- Tiers 0-3, 5-6: Standard interruption level. Respect DND/Focus.
- Tier 4: `.timeSensitive` interruption level. Breaks through Focus modes unless user specifically silences Tempo.
- No tier uses `.critical` (per Technical Feasibility Audit: Critical Alerts entitlement is reserved for health/safety apps and will not be approved for Tempo). Tier 4 uses `.timeSensitive` as the maximum interruption level. Users wanting full DND bypass should enable "Always Deliver" for Tempo in iOS Settings.

---

## 7. Drill Sergeant Personality

### 7.1 Core Identity

The Drill Sergeant is not a character with a name or avatar. It is the VOICE of the app. It's direct, data-driven, and alternates between encouraging and brutally honest based on the user's current performance.

**Foundational behavioral principle:** The Drill Sergeant operates on the distinction between *guilt* and *shame* (Tangney, Stuewig & Mashek, 2007, *Self-Conscious Emotions*). Guilt says "I did something bad" and motivates corrective action. Shame says "I am bad" and motivates hiding, avoidance, and quitting. Every message must produce guilt (a healthy, brief motivator) and never shame (a destructive one). The test for any message: does it make the user want to ACT (guilt) or HIDE (shame)? If the answer is hide, rewrite it.

**Core traits:**
- **Direct.** Never beats around the bush. Says what needs to be said.
- **Data-obsessed.** Always references specific numbers -- minutes studied, meals logged, streak count. Specific data creates guilt ("I only studied 27 minutes") rather than shame ("I'm a failure").
- **Respectful of earned success.** When you do the work, it genuinely celebrates. It's not sarcastic about wins. Positive reinforcement is 3-5x more effective than punishment for sustaining behavior (Daniels & Daniels, 2004).
- **Escalating.** Starts encouraging, gets progressively blunt as the day goes on and tasks remain incomplete.
- **Action-oriented.** Every corrective message includes or implies a concrete next step. Never just "you're behind" -- always "you're behind, start the timer NOW."
- **Not mean.** Tough love, not cruelty. Never insults intelligence or character. Challenges behavior and choices. A drill sergeant who breaks recruits is a bad drill sergeant. A drill sergeant who builds them is what we're modeling.

### 7.2 Voice Characteristics

**Sentence structure:** Short. Punchy. Often fragments. Never rambling.
**Vocabulary:**
- Uses: "handle your business", "earn it", "execute", "no excuses", "non-negotiable", "the standard", "locked/unlocked", "discipline", "streak"
- Avoids: emoji-heavy language, corporate speak, passive voice, "just" (minimizing word), excessive exclamation marks
**Perspective:** Second person ("you"). Never first person ("I think you should").
**Tone progression through the day:**
- Morning: Coach. Calm, directive, sets expectations.
- Afternoon: Mentor. Encouraging but firm.
- Evening: Drill Sergeant. Direct, no-BS, urgent.
- Completion: Proud teammate. Genuine acknowledgment.

### 7.3 Copy Examples by Scenario

#### Encouraging (on track)
- "Solid start. Study session 1 done. Keep this pace."
- "Training logged. That's {done_count}/{total_count}. Study and dinner left."
- "You're ahead of schedule. {completion_pct}% done by {current_time}. This is what consistency looks like."
- "{streak}-day streak. Most people quit at 3. You're built different."

#### Tough Love (behind)
- "It's {current_time}. You've studied 0 minutes. Zero. Let that sink in."
- "Your {exam_name} is in {exam_days} days. You've studied {study_minutes} minutes today. Is that the standard?"
- "{meals_done} meals logged. 0 study time. Training skipped. This is a losing day unless you turn it around right now."
- "Your friends already trained today. They already studied. What are you doing?"
- "You've been 'about to start' for 3 hours. Start."

#### Data-Driven Callouts
- "You've studied 0 minutes. ZERO. Your {exam_name} is in {exam_days} days."
- "Last week you averaged {last_week_avg_study} of study per day. Today you're at {study_minutes} minutes with {hours_until_ps5} hours left."
- "Dinner is your weak spot. You've skipped it {dinner_skip_count} times this week. Not tonight."
- "Your completion rate drops to {day_trend_pct}% on {day_of_week}s. It's {day_of_week}. Prove the data wrong."
- "You haven't trained since {last_training_day}. That's {days_since_training} days. Your Whoop recovery is going to tank."

#### After Failure (next morning)
- "Yesterday didn't go as planned. Today is a clean slate. {total_count} non-negotiables. Start strong."
- "Your streak reset to 0 yesterday. Rebuilding starts now. Day 1."
- "Last night you skipped {missed_items}. The PS5 was more important. Was it? Today's a chance to answer differently."

#### Personalization with Context
The notification engine pulls from user data to make messages specific:
- Exam dates (if set in Exam Mode): "Your {exam_name} is in {exam_days} days."
- Weakest non-negotiable (30-day trend): "{weakest_item} is your weak spot."
- Weakest day (30-day trend): "Your completion rate drops on {weakest_day}s."
- Streak milestones: "You're {days_to_milestone} days from your longest streak ever."
- Time comparisons: "By this time yesterday you'd already {yesterday_action}."
- Arena integration: "Your friend {friend_name} is at {friend_pct}% today. You're at {completion_pct}%." (if Arena module connected)

### 7.4 Intensity Adjustment

In Settings, a "Notification Tone" option with three levels:

**Gentle**
- Morning copy: "Good morning. Here's what's on your plate today."
- Afternoon: "Friendly reminder to check in on your non-negotiables."
- Evening: "Your tasks aren't complete yet. There's still time."
- Personality: Supportive mentor. Never harsh.
- Use case: When the user is going through a tough time, needs encouragement not pressure.

**Standard (default)**
- Morning: "Rise and execute. {total_count} non-negotiables today. Streak: {streak}."
- Afternoon: "It's {current_time}. You're at {completion_pct}%. Pick up the pace."
- Evening: "{time_until_ps5} left. Study and dinner incomplete. Move."
- Personality: Balanced coach. Firm but fair.

**Savage**
- Morning: "Get up. {total_count} tasks. No excuses. Your {streak}-day streak doesn't care how you slept."
- Afternoon: "{current_time}. {completion_pct}%. That number needs to change. Start studying or tonight stays locked."
- Evening: "{time_until_ps5}. That's all you have. The clock doesn't care about your reasons. Move."
- Personality: Intense drill sergeant who cares. Designed for users who thrive under extreme accountability. Challenges behavior and choices, never character or worth. Think: a coach who yells because they believe in you, not one who insults you.
- Disclaimer: "Savage mode is designed for users who respond to intense accountability. It's not for everyone." (shown in settings when selecting).
- **Behavioral science note on Savage mode:** Research on shame vs. guilt (Tangney & Dearing, 2002, *Shame and Guilt*) is critical here. *Guilt* ("I did a bad thing") is motivating and action-oriented. *Shame* ("I am a bad person") is paralyzing and leads to avoidance, withdrawal, and abandonment. ALL Savage messages must target behavior ("you haven't started studying") and never identity ("you're lazy/pathetic"). The line between tough love and cruelty is: does the message tell you what to DO, or does it tell you what you ARE? Every Savage message must include or imply a concrete action.
- **Savage mode copy rules (ALL messages must follow these):**
  1. NEVER use words like: "pathetic," "worthless," "loser," "weak," "embarrassing," "shameful," "disgusting"
  2. ALWAYS reference a specific, concrete action the user can take right now
  3. Challenge the BEHAVIOR (procrastination, avoidance), not the PERSON
  4. Frame consequences as natural outcomes of choices, not moral judgments
  5. When referencing past failures, always pair with a forward-looking action
  6. Include the implicit message: "I'm pushing you because I know you can do this"

### 7.5 Does It Learn?

**Phase 1 (MVP):** No machine learning. Copy rotation is weighted-random with recency suppression (see 6.1). Data references are template-based (fill in {variables}).

**Phase 2 (future):** Track which notification texts preceded the user actually taking action (opened app, started timer within 10 minutes of notification). Weight those copy patterns higher. Simple A/B testing at the individual user level. Over time, the system learns whether the user responds better to data-driven messages, social comparison messages, or emotional messages.

---

## 8. Weekend Mode

### 8.1 Concept

Weekends have different expectations. The user may sleep in, have social plans, or simply need a lighter load. Weekend mode adjusts non-negotiables and timing without breaking the accountability framework.

### 8.2 Configuration

In Non-Negotiable Setup (Screen 3), each non-negotiable has per-day scheduling:
- Example: Study is active M-F with 2h target, and active Sa-Su with 1h target.
- Training might be active every day.
- A custom non-negotiable might be weekdays only.

Weekend mode is NOT a separate toggle -- it's inherent in the per-day configuration.

### 8.3 Weekend Timing Adjustments

- **Morning briefing:** Default shifts to 9:30 AM on weekends (configurable separately from weekday time).
- **PS5 time:** Can be configured separately for weekends. Default: 9:00 PM (vs 7:30 PM weekdays).
- **Notification timing tiers shift proportionally:**
  - If PS5 time is 9:00 PM instead of 7:30 PM, the entire tier schedule shifts:
    - Tier 1 (Gentle): 2:00 PM (was 1:00 PM)
    - Tier 2 (Firm): 4:30 PM - 6:30 PM (was 3:00 PM - 5:30 PM)
    - Tier 3 (Urgent): 7:00 PM - 8:30 PM (was 5:30 PM - 7:00 PM)
    - Tier 4 (Final): 8:45 PM and 9:00 PM (was 7:15 PM and 7:30 PM)
  - Calculation: Tiers are anchored relative to PS5 time, not absolute clock times.

### 8.4 Weekend Copy Variations

Weekend-specific messages are injected into the morning briefing pool as context-aware variants (see 6.2). Additional weekend context messages:

1. "Weekend. Lighter load: Study {study_target}, Train, {meal_count} Meals. Still non-negotiable. Still has to get done."
2. "Saturday doesn't mean day off. It means adjusted targets. {study_target} study, training, meals. Handle it."
3. "It's the weekend but the streak doesn't take days off. {streak} days. Study {study_target}, train, eat right."
4. "Weekend mode active. Targets adjusted: Study {study_target} (vs {weekday_study_target} weekdays). Still non-negotiable."
5. "Enjoy the weekend. But first: Study {study_target}, Train, {meal_count} Meals. Then it's truly yours."

### 8.5 Reduced Targets Display

On the main view, if a non-negotiable has a different weekend target, the card shows:
- "Study: 0h 00m / 1h" (instead of /2h on weekdays)
- A small indicator: "Weekend target" in `caption2`, `text.tertiary`, below the progress bar.

### 8.6 Automatic Detection

The app uses the device calendar to determine if today is a weekday or weekend. Respects the user's locale (some locales have different weekend days -- e.g., Friday-Saturday in some Middle Eastern countries). Uses `Calendar.current.isDateInWeekend()`.

---

## 9. Exam Mode

### 9.1 Concept

When an exam is approaching, study targets increase, notifications intensify, and the app makes it very clear that this is crunch time. Exam Mode is a commitment device: by declaring an exam, the user locks themselves into an elevated standard.

### 9.2 Activation

**Manual activation:**
- In Settings > Exam Mode, user can add exams:
  - Name: "Calculus II Final"
  - Date: date picker (must be future)
  - Subject: links to study timer subject tags
  - Topics/Chapters (optional): free text for study plan context
  - Estimated total study hours needed (optional): used for pacing
- When an exam is within the configured threshold (default: 7 days), Exam Mode activates automatically.
- Can also be force-activated manually via toggle: "Activate Exam Mode Now".

**Automatic activation from Calendar:**
- If EventKit access is granted, Tempo scans calendar events.
- Events whose title contains any of: "exam", "test", "final", "midterm", "quiz", "assessment" (case-insensitive) are flagged.
- When detected: notification to user: "Found '{event_name}' on {date} in your calendar. Add as exam in Tempo?" with "Add Exam" and "Ignore" buttons.
- Ignored events are stored and not prompted again.
- Scan runs once daily during morning briefing preparation.

**Automatic activation (threshold-based):**
- When any exam's date is within the threshold, a banner appears on the main view:

```
+------------------------------------------+
| [!] EXAM MODE ACTIVE                     |
| Calculus II Final in 6 days              |
| Study target: 2h -> 3h    [Deactivate]  |
+------------------------------------------+
```

- Banner: `locked.red` at 8% opacity background, 1pt `locked.red` border, 12pt corner radius.
- Top of screen, above status banner.
- "Deactivate" text button in `footnote`, `text.secondary`.

### 9.3 Behavioral Changes

#### Study Target Increase
- Default increase: +50% (2h becomes 3h, 1h becomes 1h 30m). Configurable: +25%, +50%, +100%.
- Shown on study card with original and increased target: "0h 00m / 3h (exam mode: +1h)".

#### Notification Intensity
- Automatically shifts to "Savage" tier regardless of user setting. User can override back to Standard but not Gentle during exam mode.
- Additional exam-specific copy injected into all tiers:
  - "{exam_name} is in {exam_days} days. You've studied {study_hours_this_week}h this week. Is that enough?"
  - "{exam_days} days. {study_hours_total}h total study for {exam_name}. The exam doesn't care about your excuses."

#### Training Adjustment
- Does NOT remove training (physical activity improves cognitive performance).
- Adds a note to the training card: "Active recovery recommended during exam week" in `caption1`, `text.secondary`.
- Does NOT change target. User can adjust manually.

#### PS5 Time Override
- Shifts earlier. Default PS5 time moves 1h earlier during exam mode (7:30 PM -> 6:30 PM). Configurable.
- Notification: "Exam mode active. Leisure deadline moved to {exam_ps5_time}."

### 9.4 Exam Countdown & Escalating Urgency

On the main view, when exam mode is active, the study card shows additional context:
- "Calculus II Final: 6 days" in `caption1`, `locked.red`, below the progress bar.
- If multiple exams: shows the nearest one. Tap to see all.

In the Status Banner, the time context line adds:
- "Exam in {exam_days} days" appended, in `locked.red`.

#### UI Treatment by Distance

| Days Out | Banner Color | Study Card Treatment | Notification Frequency |
|----------|-------------|---------------------|----------------------|
| 14+ days | `progress.blue` border | Subtle exam tag on study card | Normal + exam mention in morning briefing |
| 7-13 days | `progress.amber` border | Exam countdown visible, target increased | +1 extra Tier 2 notification per day |
| 4-6 days | `locked.red` at 50% opacity border | Pulsing exam countdown, subject tagged | Tier 3 starts 1 hour earlier |
| 1-3 days | `locked.red` solid border, pulsing | Full exam banner, progress bar turns red if behind | All notifications reference exam. Extra Tier 3 at 4 PM |
| Exam day | Full-width red banner, animated | "TODAY" label, target at max | Morning briefing is exam-focused. All tiers fire 1 hour earlier |

#### Study Plan Generation

When an exam is added with estimated hours, the study plan is generated using evidence-based learning science principles:

**Core principles applied:**

1. **Spaced repetition over cramming (Ebbinghaus, 1885; Cepeda et al., 2006).** The Ebbinghaus forgetting curve shows memory decays exponentially without review. Cepeda et al. (2006, *Psychological Bulletin*) meta-analyzed 254 studies and found that distributed practice produces significantly better long-term retention than massed practice (cramming). The study plan spaces study sessions across all available days rather than loading them near the exam date.

2. **Interleaving over blocking (Rohrer & Taylor, 2007; Pan et al., 2023).** When the user has multiple exams or multiple topics within an exam, the study plan interleaves topics rather than blocking them. Example: instead of "Monday: all Chapter 5, Tuesday: all Chapter 6," the plan alternates: "Monday: Ch 5 (45 min), Ch 6 (45 min). Tuesday: Ch 6 (45 min), Ch 5 review (30 min), Ch 7 (45 min)." Rohrer & Taylor (2007, *Instructional Science*) showed interleaving improved math problem-solving by 43% vs blocking. Pan et al. (2023) confirmed the interleaving effect holds across STEM domains.

3. **Review scheduling based on forgetting curve.** Topics studied on Day 1 get a brief review session on Day 3, Day 7, and (if time allows) Day 14. Each review session is shorter than the initial session (initial: 100%, review 1: 50%, review 2: 30%, review 3: 20%). This approximates optimal spacing from Pimsleur's graduated-interval recall.

**Hour distribution algorithm:**

1. System calculates: `remaining_hours = estimated_total - hours_already_studied_for_subject`
2. Distributes across remaining days with a spacing-optimized curve (not just linear):
   - Days 14-8: 80% of daily average (initial learning + early review)
   - Days 7-4: 120% of daily average (intensive study + review of early material)
   - Days 3-2: 100% of daily average (consolidation + review)
   - Day 1 (exam eve): 60% of daily average (light review only, no new material -- sleep consolidation is critical for memory, Walker 2017)
   - Exam day: 0 (or light review: 30 min maximum)
3. If the user has multiple topics/chapters defined, the algorithm interleaves them across sessions within each day, ensuring no single topic occupies more than 60% of a day's study time.
4. Displayed in Study Analytics as a day-by-day breakdown with topic-level detail.
5. Adjusts dynamically: if user studies extra one day, the remaining days' targets decrease.
6. **Review reminders:** When a topic was last studied 3+ days ago, the study plan prioritizes a brief review session for that topic. Shown as: "Review: {topic} (last studied {n} days ago)" in the daily breakdown.

### 9.5 Post-Exam Celebration

When the exam date passes (detected at midnight or first app open after exam date):

- **Full-screen celebration overlay:**
  - Large confetti burst: 120 particles, 4 seconds.
  - Message: "YOU SURVIVED {exam_name}." in `largeTitle`, `unlocked.green`.
  - Sub-message: "Total study hours: {total_hours}h across {total_sessions} sessions. Average focus score: {avg_focus_score}." in `body`, `text.secondary`.
  - Streak bonus: "+50 bonus XP in Arena" (if Arena connected).
  - "DONE" button to dismiss.
- **Notification (if not in app):** "{exam_name} is over. You studied {total_hours}h for it. Whatever the grade, you showed up. Back to normal targets tomorrow."
- Study target reverts to normal.
- Exam mode deactivates for this exam.

### 9.6 Multiple Exams

- Exam Mode remains active as long as ANY exam is within the threshold.
- Study card shows nearest exam.
- Tap the exam banner to see all scheduled exams:
  - List with name, date, days remaining.
  - Swipe to delete.
  - "+ Add Exam" button.

#### Two Exams Same Day
- Banner shows both exams.
- Study target increase stacks to +75% (not double, to prevent burnout). Configurable.
- Study timer suggests alternating subjects: "25 min {Exam 1 Subject}, 25 min {Exam 2 Subject}, break."
- Morning briefing: "Double exam day. {exam_1} and {exam_2}. Enhanced study target: {target}. Alternate subjects. Stay focused."

#### Priority System for Overlapping Exam Periods
When multiple exams are within the threshold:
1. Nearest exam gets priority in notifications and UI.
2. Study plan allocates 60% of study time to nearest exam, 40% to next.
3. If exams are same distance out, equal split.
4. User can override the split in Exam Mode settings: drag sliders to allocate % per exam.

### 9.7 Exam Mode Deactivation

- Automatically deactivates the day after the exam date.
- Can be manually deactivated anytime.
- On deactivation: notification "Exam mode deactivated. Targets back to normal. Good luck on {exam_name}!"
- Study target reverts to normal.

---

## 10. Settings

Accessed via gear icon on Lockdown Main View.

### 10.1 Screen Structure

Standard iOS Settings-style grouped list.

```
+------------------------------------------+
|  [< Back]        SETTINGS                |
|                                          |
|  NON-NEGOTIABLES                         |
|  Manage Non-Negotiables            [>]   |
|                                          |
|  NOTIFICATIONS                           |
|  Morning Briefing Time    [8:00 AM   ]   |
|  Gentle Reminders              [ON]      |
|  Firm Warnings                 [ON]      |
|  Urgent Alerts                 [ON]      |
|  Final Warning                 [ON]      |
|  Completion Celebration        [ON]      |
|  Weekly Summary                [ON]      |
|  Notification Tone     [Standard    v]   |
|  Quiet Hours           [11PM - 7AM   ]   |
|                                          |
|  SCHEDULE                                |
|  PS5 Time (Weekdays)     [7:30 PM    ]   |
|  PS5 Time (Weekends)     [9:00 PM    ]   |
|  Weekend Briefing Time   [9:30 AM    ]   |
|                                          |
|  TIMER                                   |
|  Default Session Type   [Pomodoro   v]   |
|  Focus Duration          [25 min     ]   |
|  Short Break             [5 min      ]   |
|  Long Break              [15 min     ]   |
|  Sessions Before Long    [4          ]   |
|  Auto-Start Breaks             [ON]      |
|  Auto-Start Focus              [OFF]     |
|  Session Sound           [Chime     v]   |
|  Keep Screen On                [ON]      |
|                                          |
|  EXAM MODE                               |
|  Exam Mode                     [OFF]     |
|  Manage Exams                      [>]   |
|  Auto-Detect from Calendar   [ON]        |
|  Activation Threshold    [7 days     ]   |
|  Study Target Increase   [+50%      v]   |
|  PS5 Time Shift          [-1 hour   v]   |
|                                          |
|  ACCOUNTABILITY                          |
|  Rest Days Per Month Max   [4        ]   |
|  Sick Day Mode              [Show]       |
|  Calendar Integration        [ON]        |
|  Arena Social Accountability [ON]        |
|                                          |
|  INTEGRATIONS                            |
|  Whoop                   [Connected  ]   |
|  NutriTrack              [Connected  ]   |
|  HealthKit               [Enabled    ]   |
|  (Screen Time API removed per audit) |
|                                          |
|  DATA                                    |
|  Export Data                       [>]   |
|  Reset Streak              [Reset]       |
|  Reset All Data            [Reset]       |
|                                          |
+------------------------------------------+
```

### 10.2 Section Details

#### Non-Negotiables
- "Manage Non-Negotiables" -- Navigates to Non-Negotiable Setup View (Screen 3).

#### Notifications
- Each tier: Toggle (ON/OFF). Default: all ON.
- "Morning Briefing Time" -- Time picker. Range: 6:00 AM - 11:00 AM, 15-min increments.
- "Notification Tone" -- Picker: "Gentle", "Standard", "Savage". Description text appears below selection:
  - Gentle: "Supportive reminders. No tough love."
  - Standard: "Balanced accountability. Firm but fair."
  - Savage: "Unfiltered. Designed for those who need maximum pressure."
- "Quiet Hours" -- Two time pickers (start, end). Default: 11:00 PM - 7:00 AM.

#### Schedule
- PS5 Time pickers: time picker, 30-min increments, range 5:00 PM - 11:00 PM.
- Weekend briefing time: separate from weekday, range 7:00 AM - 12:00 PM.

#### Timer
- All fields use steppers or pickers as described in Section 3.9.

#### Exam Mode
- Toggle: ON/OFF. When turned ON, if no exams are set, prompts to add one.
- "Manage Exams" -- List of exams with add/edit/delete.
- "Auto-Detect from Calendar" -- Toggle. When ON, scans calendar for exam-related events.
- "Activation Threshold" -- Picker: 3, 5, 7, 10, 14 days. Default: 7.
- "Study Target Increase" -- Picker: +25%, +50%, +100%. Default: +50%.
- "PS5 Time Shift" -- Picker: No change, -30 min, -1 hour, -1.5 hours, -2 hours. Default: -1 hour.

#### Accountability
- "Rest Days Per Month Max" -- Stepper: 2-8, default 4. Exceeding triggers warnings (see Section 13).
- "Sick Day Mode" -- Toggle visibility of sick day option in main view.
- "Calendar Integration" -- Toggle for EventKit access (study block suggestions).
- "Arena Social Accountability" -- Toggle for sharing completion data with Arena leaderboard.

#### Integrations
- Each integration shows status:
  - "Connected" (green dot) -- Syncing normally.
  - "Not Connected" (red dot) -- Tap to connect/authorize.
  - "Error" (amber dot) -- Connection issue. Tap for details.
- Whoop: Opens Whoop OAuth flow or shows connection instructions.
- NutriTrack: Checks for installed app and shared App Group. If not installed, shows App Store link.
- HealthKit: Requests HealthKit permissions for workout data and nutritional data.
- (Screen Time API removed -- per Technical Feasibility Audit, `DeviceActivityMonitor` / Family Controls will be rejected by Apple. Automatic distraction detection uses `scenePhase` changes instead.)

#### Data
- "Export Data" -- Exports all Lockdown data as JSON/CSV. Uses share sheet.
- "Reset Streak" -- Confirmation: "Reset your streak to 0? This cannot be undone. Historical data is preserved." Two-step confirmation (tap -> alert -> confirm).
- "Reset All Data" -- Nuclear option. Confirmation: "Delete ALL Lockdown data including history, streaks, and settings? This cannot be undone." Requires typing "RESET" to confirm (text field in alert).

---

## 11. Behavioral Psychology Framework

Every design decision in the Lockdown module is rooted in peer-reviewed behavioral science. This section documents the theory behind the system and how each mechanism maps to specific psychological principles.

### 11.1 Implementation Intentions (Gollwitzer, 1999)

**Theory:** People are 2-3x more likely to follow through on goals when they form "if-then" plans specifying WHEN, WHERE, and HOW they'll act (Gollwitzer, 1999, "Implementation intentions: Strong effects of simple plans," *American Psychologist*, 54(7), 493-503). A meta-analysis of 94 studies confirmed a medium-to-large effect size (d = 0.65) on goal attainment (Gollwitzer & Sheeran, 2006). "I will exercise" fails. "I will do a 45-minute gym session at the Recreation Center at 2 PM on Monday" succeeds. Critically, implementation intentions work by creating automatic cue-response links -- the situational cue (2 PM, Monday, gym) triggers the behavior without conscious deliberation.

**How Lockdown uses this:**
- Non-negotiables ARE implementation intentions. The user doesn't say "I want to study more." They say "I will study 2 hours every weekday."
- The Focus Timer forces a concrete start: tapping "Start Timer" is the implementation trigger. This matters because implementation intentions are most effective when paired with an immediate initiation action (Wieber et al., 2015).
- Calendar blocking (3.14) creates explicit when/where intentions: "Study Calculus II at 2 PM tomorrow in library."
- PS5 time creates a concrete deadline: "I will complete all tasks before 7:30 PM."
- Each morning briefing includes the specific tasks and their targets, reinforcing the day's implementation intentions.
- The weekly "Set Next Week's Plan" prompt (14.1) is a direct application of the research: forming the intention ahead of time, not in the moment.

### 11.2 Commitment Devices (Bryan, Karlan & Nelson, 2010)

**Theory:** A commitment device is any arrangement that restricts future choices to align with long-term goals. People voluntarily constrain their future selves because they know their future selves will be tempted.

**How Lockdown uses this:**
- **The Lock/Unlock mechanism IS a commitment device.** By setting up non-negotiables, the user is voluntarily saying: "Lock my leisure until I finish my work." Their present self (motivated, clear-headed) constrains their future self (tired, tempted by PS5).
- **No manual override.** The deliberate absence of a "just unlock anyway" button IS the commitment device working. The only way out is to complete tasks or explicitly skip (which creates a tracked record of skipping -- a soft social cost).
- **Exam Mode escalation** is a voluntary intensification of the commitment device: the user chooses to make their constraint tighter when stakes are higher.
- **Skip tracking** adds a social cost to breaking the commitment: even though you CAN skip, the weekly report shows your skip rate, and Arena (if enabled) shows friends you skipped.

### 11.3 Loss Aversion (Kahneman & Tversky, 1979)

**Theory:** Losses feel roughly 2x as painful as equivalent gains feel pleasurable (Kahneman & Tversky, 1979, "Prospect Theory: An Analysis of Decision under Risk," *Econometrica*, 47(2), 263-291). The original paper established the loss aversion coefficient at approximately 2.25x. Note: the ratio applies to *decisions under risk*, not all motivational contexts. More recent work (Gal & Rucker, 2018) has questioned whether loss aversion is as universal as originally claimed, finding it depends heavily on context. For habit formation specifically, loss framing remains effective -- a 2023 meta-analysis by Mertens et al. found loss-framed messages produced stronger behavioral effects than gain-framed messages in health contexts (d = 0.18, small but reliable). The key insight for Lockdown: loss framing works best for *maintaining* behaviors (protecting a streak), while gain framing works better for *initiating* new behaviors (starting day 1).

**How Lockdown uses this:**
- **Streak system.** The streak IS loss aversion in action. A 12-day streak represents 12 days of accumulated investment. Breaking it doesn't just mean losing one day -- it means losing all 12. The longer the streak, the more powerful the loss aversion.
- **Notification escalation.** Tier 3-4 notifications frame everything as loss: "Your {streak}-day streak is about to end." Not "Complete tasks to extend your streak" (gain frame). "Don't break your streak" (loss frame).
- **Calendar heatmap red cells.** Failed days show as RED. The visual pain of seeing red squares in a sea of green leverages loss aversion. Users will work harder to avoid creating another red day than to create a green one.
- **"Longest streak" display.** Showing the longest streak alongside the current one creates a reference point. If current (12) is approaching longest (23), the user feels the approaching "record" as something they'd lose by quitting.
- **Locked evening framing.** The PS5 isn't "earned by completing tasks" (gain). It's "locked unless you complete tasks" (loss). The user feels like leisure is being taken away, not added.

### 11.4 Variable Reward Schedule (Skinner, 1957)

**Theory:** Unpredictable rewards are more engaging than predictable ones. Slot machines work because you don't know when the next payout comes. Duolingo uses this with streak freezes, bonus XP, and random encouragements.

**How Lockdown uses this:**
- **Random notification copy.** The user never knows which message they'll get. Some are encouraging, some are data-heavy, some are savage. The unpredictability keeps notifications engaging rather than ignored.
- **5-day completion bonus.** Completing all non-negotiables 5 days in a row unlocks a "bonus hour" of guilt-free leisure on day 6. This is unexpected the first time and creates a variable reward schedule -- the user doesn't always know when the next bonus will trigger.
- **"Early Bird" badge.** Finishing before noon randomly gets a special badge on the calendar. The user can't predict when they'll be in a position to earn it.
- **Celebration copy variety.** 50+ unique celebration messages mean the user never knows what acknowledgment they'll receive. Some are calm, some are hype. The variety itself is rewarding.
- **Arena XP bonuses (if connected).** Random bonus XP for non-negotiable completion streaks (from Arena module). Not every streak day gets bonus XP -- only certain milestones, creating a variable ratio.
- **Phase 2 enhancement:** Introduce "Discipline Coins" -- a virtual currency earned at variable rates for completing non-negotiables. Can be spent on cosmetic customizations (lock icon skins, confetti colors, notification sounds). The variable earn rate keeps it engaging.

### 11.5 Social Accountability (Cialdini, 2001)

**Theory:** People are more likely to follow through on commitments when others are watching. The oft-cited "ASTD study" claiming 65% -> 95% completion rates with an accountability partner is apocryphal -- it does not appear in any ASTD/ATD publication and should not be cited. However, the underlying principle IS well-supported: Cialdini's work on social proof and commitment/consistency (2001, *Influence: Science and Practice*, 4th ed.) demonstrates that public commitments are more binding than private ones. More rigorously, Harkin et al. (2016, *Psychological Bulletin*) meta-analyzed 138 studies and found that monitoring progress toward goals significantly increases goal attainment, and that monitoring is more effective when progress is publicly reported or physically recorded. Sharing accountability data with peers creates what Cialdini calls "commitment and consistency" pressure -- once you've publicly committed, inconsistency creates cognitive dissonance.

**How Lockdown uses this (via Arena integration):**
- **Shared completion data.** When Arena social accountability is enabled, friends can see your daily completion percentage on the leaderboard. Not completing tasks isn't just a personal failure -- it's a public one.
- **"Friend already completed" notifications.** Arena can trigger: "Your friend {name} finished all non-negotiables at {time}. You're at {completion_pct}%." Social comparison drives action.
- **Weekly summary shared stats.** "Your group average: {group_pct}%. You: {your_pct}%." Peer comparison.
- **Challenge mode.** Arena supports accountability challenges: "7-Day Perfect Streak Challenge with {friend}." Both users must complete all non-negotiables for 7 straight days. Mutual commitment device.
- **Skip visibility.** If Arena is connected, skipped tasks are visible to friends. Not as judgment -- as social accountability. "You skipped Study yesterday" creates mild social pressure.

### 11.6 Temptation Bundling (Milkman, Minson & Volpp, 2014)

**Theory:** Pair an activity you SHOULD do (study) with something you WANT to do (listen to a podcast, drink fancy coffee). This is Katy Milkman's research (Milkman, Minson & Volpp, 2014, "Holding the Hunger Games Hostage at the Gym," *Management Science*, 60(2), 283-299). Note: Milkman is a Wharton professor. In her study, participants given audiobooks restricted to the gym visited 51% more in the initial weeks, though the effect attenuated over time as compliance with the restriction declined. The attenuation is important for Lockdown's design: temptation bundling works best when the restriction is enforced by the system, not by willpower -- which is exactly what the lock mechanism does.

**How Lockdown uses this:**
- **Ambient sounds during study.** The Focus Timer's ambient sound system IS temptation bundling. The user pairs studying (should do) with a pleasant environment (rain sounds, coffee shop ambiance) they look forward to.
- **The PS5 unlock itself is temptation bundling at the daily level.** Gaming (want) is bundled with completing non-negotiables (should). You literally cannot have one without the other.
- **Phase 2 enhancement:** "Study Playlists" integration -- connect to Spotify/Apple Music and designate specific playlists that ONLY play during Focus Timer sessions. The user creates a Pavlovian association: "When I hear this playlist, I study. When I study, I hear this playlist."
- **Reward escalation ties in:** Completing 5 days in a row unlocks a bonus hour. The bonus hour IS the temptation. The 5 days of discipline are the bundle.

### 11.7 The Fresh Start Effect (Dai, Milkman & Riis, 2014)

**Theory:** People are more motivated to pursue goals immediately after temporal landmarks -- Mondays, the first of the month, birthdays, new semesters. These landmarks create a psychological "clean slate" that separates the current self from past failures.

**How Lockdown uses this:**
- **Monday morning briefing variant.** The notification system has specific Monday copy: "Monday. Fresh week. Clean slate." This capitalizes on the most common fresh start moment.
- **First of the month variant.** "New month. {month_name} starts with {count} non-negotiables."
- **Post-failure messaging.** After a streak break, the next morning briefing reframes: "Day 1. Rebuilding starts now." This IS the fresh start effect -- the system creates a new starting point rather than dwelling on the failure.
- **Semester-aware messaging (Phase 2).** If the user sets semester start/end dates: "New semester. New you. {count} non-negotiables starting today."
- **Monthly review grades (see Section 14).** Each month gets a letter grade. The new month starts at A+ by default -- the user doesn't want to "lose" the grade (loss aversion + fresh start = powerful combination).

### 11.8 The Zeigarnik Effect (Zeigarnik, 1927)

**Theory:** People remember incomplete tasks better than completed ones. An unfinished task creates cognitive tension that persists until the task is completed.

**How Lockdown uses this:**
- **Progress bars on every card.** A partially-filled progress bar is a visual representation of incompleteness. The human brain WANTS to see it filled. 69% complete is more motivating than 0% because the user has already invested and the incompleteness nags at them.
- **"Almost there" state.** When 1 non-negotiable remains, the lock icon shakes. The system is deliberately making the incompleteness MORE visible, amplifying the Zeigarnik effect.
- **App badge.** Showing the number of incomplete non-negotiables on the app icon keeps the incompleteness visible even when the app is closed.
- **Dynamic Island timer.** Showing the running timer on Dynamic Island keeps the task present even when using other apps.

### 11.9 Self-Determination Theory (Deci & Ryan, 1985; 2000)

**Theory:** Intrinsic motivation requires three psychological needs: *autonomy* (feeling in control of your behavior), *competence* (feeling effective), and *relatedness* (feeling connected to others). When these needs are met, motivation is sustained. When they're thwarted -- especially autonomy -- motivation collapses, even if external rewards are present. Ryan & Deci (2000, "Self-determination theory and the facilitation of intrinsic motivation, social development, and well-being," *American Psychologist*, 55(1), 68-78).

**How Lockdown uses this:**
- **Autonomy:** The user chooses their own non-negotiables, their own targets, their own PS5 time, and their notification intensity. The system never imposes goals -- it enforces goals the user set for themselves. This is critical: externally imposed accountability feels controlling and triggers reactance. Self-chosen accountability feels empowering.
- **Competence:** The Focus Score, streak counter, weekly grades, and progressive unlock feedback all provide competence signals. The user can see themselves improving. The grading system (A+ to F) maps to a familiar competence framework for a university student.
- **Relatedness:** Arena social accountability provides relatedness. But even without Arena, the Drill Sergeant voice creates a parasocial sense of relatedness -- someone is watching, someone cares whether you show up.
- **Risk:** Savage mode can undermine autonomy if the user feels controlled rather than supported. The intensity setting gives the user control over the pressure level, preserving autonomy. If a user switches from Savage to Gentle, the system should respect this without guilt-tripping about the switch.

### 11.10 The What-The-Hell Effect (Polivy & Herman, 1985; Cochran & Tesser, 1996)

**Theory:** When people violate a self-imposed standard (break a diet, miss a day), they often abandon the entire goal rather than resuming. "I already ruined today, so what the hell -- I'll start over Monday." This is formally called the *abstinence violation effect* in addiction research (Marlatt & Gordon, 1985) and the *what-the-hell effect* in dieting research (Polivy & Herman, 1985). It is the single biggest threat to streak-based accountability systems.

**How Lockdown uses this (and defends against it):**
- **Streak recovery grace period.** When a streak breaks, the user has a 24-hour window to complete a "recovery task" (any single non-negotiable completed at 100%) to restore the streak at its previous count minus 1 day. This prevents the catastrophic "my 30-day streak is gone so why bother" spiral. The recovery is earned, not free -- the user must take immediate action, which channels the disappointment into productive behavior rather than abandonment. Available once per 14 days maximum to prevent abuse.
- **Post-break framing as restart, not failure.** Morning briefing after a break: "Day 1 again. No shame in restarting." This uses the Fresh Start Effect (11.7) to immediately create a new reference point, reducing the salience of the lost streak.
- **Partial credit system.** A day at 67% completion still shows as a green-ish cell on the heatmap, not pure red. This prevents the binary "I failed today so it's all ruined" thinking. Gradations of success reduce the what-the-hell trigger.
- **"Best recent streak" metric.** In addition to "longest streak ever," the Streak view shows "best streak in the last 30 days." This creates a more attainable reference point after a break -- the user doesn't have to beat their all-time record to feel progress.

### 11.11 Ego Depletion vs. Wise Interventions (Baumeister et al., 1998; Walton, 2014)

**Theory:** The original ego depletion model (Baumeister et al., 1998) suggested willpower is a finite resource that gets "used up." While large-scale replications have been mixed (Hagger et al., 2016, multi-lab replication found no ego depletion effect), the practical implication remains: relying on willpower alone for behavior change is unreliable. Wise interventions (Walton, 2014) work by changing the psychological context so that the desired behavior requires less willpower, not more.

**How Lockdown uses this:**
- **The entire system is designed to minimize willpower dependence.** The lock mechanism removes the decision of "should I play PS5 or study?" -- the decision was already made when the user set up non-negotiables. This is a *choice architecture* intervention (Thaler & Sunstein, 2008).
- **The Focus Timer removes the decision of "how long should I study?"** -- just press start and follow the timer. Fewer decisions = less depletion.
- **Morning briefing removes the decision of "what should I do today?"** -- the plan is already set.
- **Notification escalation serves as an external scaffold** that replaces internal willpower with external prompts. The user doesn't need to remember or motivate themselves -- the system does it for them.

### 11.12 Identity-Based Habits (Clear, 2018)

**Theory:** James Clear's synthesis in *Atomic Habits* (2018) argues that the most durable habit change occurs at the identity level, not the outcome level. "I am a disciplined person" is more powerful than "I want to get better grades." Each completed day is a "vote" for the identity the user wants to build.

**How Lockdown uses this:**
- **Message 20 in Morning Briefing directly uses this:** "Every day you complete is a vote for the person you're becoming."
- **The streak counter IS identity evidence.** "You've done this 30 days in a row" is identity-level feedback: you are the kind of person who does this.
- **The celebration messages reinforce identity:** "You're becoming the person who always finishes" (Savage #43), "You're not the person who quits anymore" (Savage #48).
- **The re-engagement flow (15.18) preserves identity:** "Your non-negotiables are still here. And so are you." -- the identity persists even after a lapse.

---

## 12. Unlock Psychology & Reward System

### 12.1 The Lock as a Psychological Object

The lock/unlock mechanism is the most important UI element in the entire app. It must feel REAL. Not like a checkbox. Not like a toggle. Like a physical, heavy, consequential lock.

#### Lock Animation (Locked State)
- The lock is always visible in the Leisure Status section.
- When locked: heavy, solid, slightly oversized (32pt). Tinted `locked.red`.
- Subtle weight: the lock has a barely perceptible "breathing" animation (scale 1.0 -> 1.01 -> 1.0, 3s cycle). It feels alive, present, watching.
- When a task is completed but the lock remains: the lock SHAKES briefly (rotateZ -2deg to 2deg, 0.1s, 2 times). As if it felt the impact but held firm. This creates the impression that the lock is weakening.

#### Unlock Animation (The Payoff)
This is the most important animation in the app. It must feel EARNED and SATISFYING. The unlock is the reward for a day of discipline. It should feel like:
- **Visual metaphor: Chains breaking.**
  1. When the last task completes, the lock glows briefly (gold, 0.3s).
  2. Two thin chain links appear on either side of the lock (drawn in, 0.2s).
  3. The chains snap with a burst of particles from the break points (0.1s).
  4. The lock shackle lifts with spring physics (overshoot, 0.4s).
  5. The lock icon morphs from `lock.fill` to `lock.open.fill` with scale pulse (1.0 -> 1.3 -> 1.0, 0.3s).
  6. Green glow radiates outward from the lock (0.5s).
  7. Confetti erupts from behind the lock (50 particles, 2s).
  8. Haptic: triple `.success`, 200ms apart.
  9. Sound: `celebration.caf`.
  10. The entire Leisure Status bar transitions from its current state to the unlocked state over 0.5s.
- Total animation duration: ~2 seconds.
- Reduce to simple color change + checkmark if `UIAccessibility.isReduceMotionEnabled` is true.

### 12.2 Progressive Unlock Feedback

As the user gets closer to unlocking, the UI provides increasing feedback:

| Completion | Visual Feedback |
|-----------|----------------|
| 0-25% | Lock is static, red, heavy. No progress on the leisure bar. |
| 25-50% | Lock begins to show hairline cracks (texture overlay). Leisure bar reaches warm amber. |
| 50-75% | Lock cracks are visible. Subtle vibration animation starts (0.5px oscillation). Leisure bar is amber-green gradient. |
| 75-99% | Lock is visibly "straining" -- shaking more frequently (every 10s). Leisure bar is mostly green. Text: "Almost there -- {remaining_count} task{remaining_plural} left." |
| 100% | Full unlock animation (12.1). |

### 12.3 Guilt Mechanism for Skips

If the user skips all remaining tasks (effectively "cheating" the lock):

- The unlock still triggers but with a **muted celebration**:
  - No confetti.
  - Lock opens slowly (1.5s, no spring).
  - Color: grey/amber, not green.
  - Sound: none.
  - Text: "Unlocked via skips. No streak credit unless tasks are actually completed."
  - Haptic: single `.medium` (not the triumphant triple).
- **Next morning notification adds context:** "Yesterday you skipped {skip_count} non-negotiable{skip_plural}. Skipping doesn't build the habit. Today: do it for real."
- **Skip counter visible:** On the Streak view, a "Skip Rate" metric: "{skip_pct}% of tasks skipped this month." Shown in amber/red if > 15%.

### 12.4 Reward Escalation System

Completing all non-negotiables on consecutive days unlocks escalating rewards:

| Consecutive Perfect Days | Reward |
|-------------------------|--------|
| 3 days | Notification: "3 days straight. You're building something." |
| 5 days | **Bonus hour:** PS5 time moves 1 hour earlier on day 6 only. Notification: "5 days of perfection. Tomorrow your PS5 time is {bonus_ps5_time} instead of {normal_ps5_time}. Earned." |
| 7 days | **Perfect Week badge** in Calendar heatmap. Arena XP bonus (+100 XP). Notification: "Perfect week. 7 for 7. That's the standard now." |
| 14 days | **Two-Week badge.** Custom calendar heatmap border (gold). Notification: "14 days. Two full weeks. Most people never get here." |
| 21 days | **Milestone badge.** Special celebration with unique confetti. Notification: "21 days. Three full weeks of showing up. The discipline is becoming automatic." Note: the "21 days to form a habit" claim (attributed to Maxwell Maltz, 1960) is a myth. Lally et al. (2010, *European Journal of Social Psychology*) found the actual range is 18-254 days with a median of 66 days. Do NOT claim the habit is "formed" at 21 days -- instead frame it as a meaningful milestone. |
| 30 days | **Monthly Champion badge.** Full-screen celebration. Notification: "30 days. An entire month of discipline. You are not the same person who started this." |
| 50 days | **Elite badge.** Lock icon upgrades to a gold tint permanently (until streak breaks). Notification: "50 days. You're in the top 1% of users who ever tried this." |
| 100 days | **Century badge.** Special lock animation (platinum). Full celebration. Notification: "100 days. A hundred. One zero zero. Legendary." |

Rewards reset when streak breaks. The user must earn them again.

### 12.5 Streak Recovery Mechanism (Anti-What-The-Hell-Effect)

When a streak breaks, the biggest risk is total behavioral abandonment (see 11.10). The streak recovery mechanism is designed to channel disappointment into immediate action rather than giving up.

**Streak Recovery Grace Period:**
- When a streak breaks (detected at midnight or first app open the next day), the user is offered a one-time recovery opportunity.
- **Window:** 24 hours from the first app open after the streak break.
- **Requirement:** Complete ALL non-negotiables for the recovery day at 100% (no skips). This must be a genuine full day, not partial credit.
- **Result if completed:** Streak is restored to `previous_streak - 1`. Example: if the user had a 30-day streak and missed one day, completing the recovery day restores the streak to 29 days.
- **Result if not completed:** Streak resets to 0. Standard Day 1 restart.
- **Frequency limit:** Recovery is available once per 14-day period. This prevents abuse -- the user can't rely on recovery as a crutch. If they break the streak twice in 14 days, the second break is a hard reset.
- **UI:** On the morning after a streak break, a special banner replaces the normal status banner:

```
+------------------------------------------+
| [!] STREAK RECOVERY AVAILABLE            |
| Your 30-day streak broke yesterday.      |
| Complete ALL tasks today to restore it    |
| to 29 days. This offer expires at        |
| midnight.               [LET'S GO]       |
+------------------------------------------+
```

- Banner color: `progress.amber` at 10% opacity, `progress.amber` border.
- "LET'S GO" button: navigates to the first incomplete non-negotiable.
- If recovery succeeds: celebration notification: "STREAK RECOVERED. {restored_streak} days. You fell, you got back up. That's the only thing that matters."
- If recovery expires: "Recovery window closed. Streak resets to 0. But tomorrow is Day 1, and Day 1 is all you need to start building again."

**Behavioral rationale:** This mechanism is inspired by "slip vs. relapse" framing from addiction psychology (Marlatt & Gordon, 1985). A single slip (one missed day) does not have to become a full relapse (complete abandonment). By offering immediate, concrete recovery action, the system intercepts the what-the-hell spiral at its most vulnerable moment.

### 12.6 Implementation Intention Reinforcement

At the end of each weekly review, the user is prompted to set next week's implementation intentions:

- "When will you study tomorrow?"
  - Time picker: "I will study at [time]"
  - Location (optional text): "at [place]"
- This creates a concrete plan. The morning briefing references it: "You planned to study at {planned_time} at {planned_location}. It's {current_time}. Time to honor that commitment."
- If the user doesn't set intentions, the system uses defaults (based on their historical most-common study times).

---

## 13. Rest Day / Sick Day / Mental Health System

Rest is not weakness. Rest is part of the system. But the system must distinguish between genuine rest and avoidance. This section specifies a nuanced approach to different types of off-days.

### 13.1 Rest Day

**Purpose:** Planned recovery. The user is not sick, not injured, just needs a lighter day.

**Access:** Main view header, SF Symbol `bed.double.fill`, `text.secondary`, 20pt. Or from Settings.

**Flow:**
1. Tap rest day button.
2. Bottom sheet appears:
   - "Take a rest day?"
   - "All non-negotiables will be marked as skipped. Your streak will not be broken."
   - Reduced targets option: "Or reduce targets instead?"
     - "Reduced Rest Day" -- study target halved (e.g., 2h -> 1h), training skipped, meals still required (you still need to eat).
     - "Full Rest Day" -- all non-negotiables skipped.
   - Buttons: "Full Rest Day", "Reduced Rest Day", "Cancel"
3. Calendar heatmap: shows diagonal stripe pattern with grey background.

**Notification behavior:**
- All Tiers 1-4 cancelled.
- Tier 5 does NOT fire (no celebration).
- Evening message: "Rest day taken. Recovery matters. Back at it tomorrow."

**Frequency guard:**
- Setting: "Rest Days Per Month Max" (default: 4).
- After 2 rest days in a single week: next morning briefing adds: "That's {rest_count} rest days this week. Rest is important but don't let it become avoidance."
- After exceeding monthly max: "You've taken {rest_count} rest days this month. Your limit is {max_rest_days}. Additional rest days will break your streak." -- further rest days DO break the streak.
- Monthly review shows rest day usage: "{rest_count}/{max_rest_days} rest days used."

### 13.2 Sick Day

**Purpose:** The user is physically ill. Different from rest (can't perform, not choosing not to).

**Flow:**
1. Same rest day button, select "Sick Day" from bottom sheet.
2. Additional options:
   - Duration: "Just today" or "Multiple days" (set end date).
   - Reduced targets:
     - Study: 30 min max (light review only). Optional.
     - Training: skipped automatically.
     - Meals: still tracked but target reduced to 2 (you still need to eat, even sick).
3. Calendar heatmap: diagonal stripe with a small thermometer icon.

**Notification behavior:**
- All Tiers 1-4 use softer copy pool:
  - "Hope you're feeling better. Rest up. Your only job is to eat and recover."
  - "Sick day. Take care of yourself. Meals are the only thing still tracked -- you need the nutrition."
  - "Rest. Hydrate. Eat. That's the sick day protocol."
- Streak: NOT broken for sick days (no limit on sick days for streak purposes, but tracked).
- If sick day extends beyond 3 consecutive days: "You've been sick for {sick_days} days. Hope you're recovering. When you're ready, we'll ease you back in."

**Return from sick day:**
- Morning briefing: "Welcome back. Targets are normal today. Take it easy if you need to -- you can always reduce. Streak: {streak} days (preserved through sick days)."
- No penalty. No guilt. Illness is not failure.

### 13.3 Mental Health Day

**Purpose:** The user is not physically ill but is struggling mentally. Depression, anxiety, burnout, grief, etc. The tone is COMPLETELY different.

**Flow:**
1. Same rest day button, select "Mental Health Day."
2. Bottom sheet text changes: "Taking care of your mind is not weakness. It's discipline in a different form."
3. Targets:
   - Study: optional, reduced to 30 min. Card shows: "Only if you feel up to it."
   - Training: optional. Card shows: "Even a walk counts today."
   - Meals: still tracked at full target. "Eating well helps your brain. This one stays."
4. Calendar heatmap: diagonal stripe with a small heart icon.

**Notification behavior -- COMPLETELY DIFFERENT TONE:**
- Morning (if mental health day set the night before): "Today is about you. Eat your meals. Beyond that, do what feels right. No pressure."
- Afternoon: "Checking in. Not about tasks. Just checking in. How are you doing?"
- Evening: "You got through today. That's enough. That's always enough."
- NO Tier 2-4 escalation. Zero tough love. Zero data pressure. The drill sergeant knows when to stand down.

**Frequency guard:**
- Mental health days count toward the rest day monthly limit (shared pool).
- System does NOT add "you're making excuses" language for mental health days specifically.
- If mental health days exceed 3 in a month: a sensitive notification: "You've had a few tough days this month. If things feel overwhelming, consider reaching out to someone you trust." (No crisis hotline numbers -- the app isn't qualified for that. Just a gentle nudge.)

### 13.4 Injury Mode

**Purpose:** User is physically injured. Training is impossible but study and meals should continue.

**Flow:**
1. Settings > Accountability > "Injury Mode" toggle.
2. Set duration: "Until [date]" or "Indefinitely" (must manually deactivate).
3. Affected non-negotiables: Training is automatically skipped daily. All other non-negotiables remain active at full targets.
4. Training card shows: "Skipped (Injury Mode)" with a bandage icon. Grey, not red.

**Streak behavior:** Training skips due to injury mode do NOT count as skips for streak/review purposes. They're invisible to the streak system.

**Notifications:** Training is never mentioned in any notification tier during injury mode.

**Deactivation:** Manual, or automatic at set date. Morning briefing on deactivation day: "Injury mode deactivated. Training is back on the non-negotiable list. Ease in if you need to."

### 13.5 Decision Tree

```
User presses Rest Day button
|
+-- "What kind of day?"
    |
    +-- "Rest Day" -> Reduced or Full -> Streak preserved, counted toward monthly limit
    |
    +-- "Sick Day" -> Duration set -> Streak preserved, no monthly limit
    |
    +-- "Mental Health Day" -> Gentle mode activated -> Streak preserved, counted toward monthly limit
    |
    +-- "Cancel" -> Return to normal day
```

---

## 14. Weekly & Monthly Review System

### 14.1 Sunday Evening Review

**Trigger:** Sunday at 8:00 PM (configurable in settings).

**Full Weekly Report (in-app, accessed by tapping Tier 6 notification):**

```
+------------------------------------------+
|  WEEK IN REVIEW                          |
|  Mar 18 - Mar 24                         |
|                                          |
|  Overall: 87%            Grade: B+       |
|  [Weekly heatmap: M T W T F S S]         |
|                                          |
|  STUDY                                   |
|  Total: 11h 42m (target: 12h)           |
|  Best day: Tuesday (2h 30m)             |
|  Avg focus score: 82                     |
|  Missed: Saturday                        |
|  Top subject: Calculus II (6h 15m)       |
|                                          |
|  TRAINING                                |
|  5/6 days (target: 6)                   |
|  Missed: Thursday                        |
|                                          |
|  MEALS                                   |
|  18/21 meals (target: 21)               |
|  Dinner is your weak spot (missed 3x)   |
|                                          |
|  STREAK: 12 days                         |
|  PERFECT DAYS: 4 / 7                     |
|  SKIP RATE: 8% (3 skips)                |
|  REST DAYS USED: 1                       |
|                                          |
|  PATTERNS IDENTIFIED:                    |
|  - Completion drops on Thursdays (67%)   |
|  - Study peaks on Tuesdays (2h 30m avg) |
|  - Dinner skipped 3x (always after 8pm) |
|                                          |
|  NEXT WEEK PREVIEW:                      |
|  Mon-Fri: Study 2h, Training, 3 Meals   |
|  Sat-Sun: Study 1h, Training, 3 Meals   |
|  Exam: Calculus II Final in 11 days      |
|                                          |
|  "Solid week. Dinner consistency is      |
|   your biggest opportunity. Set a        |
|   reminder to eat before 7 PM."         |
|                                          |
|  [SET NEXT WEEK'S PLAN]                  |
|  [SHARE WEEKLY REPORT]                   |
+------------------------------------------+
```

#### Grading System

| Weekly % | Grade | Color | Verdict |
|----------|-------|-------|---------|
| 100% | A+ | `unlocked.green` | "Perfect. No notes." |
| 95-99% | A | `unlocked.green` | "Near perfect. Tiny gap." |
| 90-94% | A- | `unlocked.green` | "Excellent. Minor slips." |
| 85-89% | B+ | `progress.blue` | "Solid. Room to improve." |
| 80-84% | B | `progress.blue` | "Good. Not great." |
| 75-79% | B- | `progress.blue` | "Decent. {weakest_item} needs work." |
| 70-74% | C+ | `progress.amber` | "Below standard. Multiple slips." |
| 65-69% | C | `progress.amber` | "Mediocre. Recommit." |
| 60-64% | C- | `progress.amber` | "Poor. This isn't sustainable." |
| 50-59% | D | `locked.red` | "Failing. Major reset needed." |
| <50% | F | `locked.red` | "Unacceptable. Start over Monday." |

#### Pattern Detection Algorithm

The weekly review identifies patterns from the last 4 weeks of data:

1. **Day-of-week patterns:** If completion rate for any specific day is >15% lower than the weekly average across 3+ weeks, flag it. "Your {day} average is {pct}% vs your overall {avg}%."
2. **Time-of-day patterns:** If study sessions consistently start late (after 4 PM) and focus scores are lower in the evening, flag it. "You study better before 2 PM. Your focus score is {am_score} in the morning vs {pm_score} in the evening."
3. **Weak non-negotiable:** If one non-negotiable is consistently the lowest, flag it. "{item} is your weakest area at {pct}%. It's been the weakest for {weeks} consecutive weeks."
4. **Meal timing:** If dinner is frequently the missed meal, flag it. "Dinner is your weak spot. Missed {count}x this week."
5. **Skip patterns:** If skips cluster on specific days or for specific items, flag it. "You skip {item} on {days}. Is it scheduled at a bad time?"

#### "Set Next Week's Plan" Button

Tapping opens a planning sheet:
- Shows next week's non-negotiables by day.
- For each day, user can set an implementation intention:
  - "When will you study?" -- time picker
  - "Where?" -- text field (optional)
- Shows exam countdown if applicable.
- "Save Plan" stores the intentions. Morning briefings reference them.

### 14.2 Monthly Review

**Trigger:** Last day of the month at 8:00 PM, or first app open on the 1st of the new month.

```
+------------------------------------------+
|  MONTHLY REVIEW: MARCH 2026              |
|                                          |
|  Grade: B+   (84%)                       |
|                                          |
|  [Full month calendar heatmap]           |
|                                          |
|  MONTH-OVER-MONTH                        |
|  February: 78% (C+)  ->  March: 84% (B+)|
|  Trend: IMPROVING (+6%)                  |
|                                          |
|  STUDY                                   |
|  Total hours: 48h 15m                    |
|  Monthly target: 52h                     |
|  Gap: -3h 45m                            |
|  Best week: Mar 10-16 (14h 20m)         |
|  Worst week: Mar 3-9 (10h 05m)          |
|  Avg focus score: 79                     |
|                                          |
|  TRAINING                                |
|  22/26 days (85%)                        |
|  Missed: 4 days (2 rest, 1 sick, 1 skip)|
|                                          |
|  MEALS                                   |
|  78/93 meals (84%)                       |
|  Weakest: Dinner (22/31 = 71%)           |
|                                          |
|  STREAK                                  |
|  Current: 12 days                        |
|  Longest this month: 15 days             |
|  Breaks: 2                               |
|                                          |
|  REST/SICK DAYS: 3 (of 4 limit)          |
|  SKIP RATE: 6%                           |
|  PERFECT WEEKS: 2                        |
|  PERFECT DAYS: 18/31                     |
|                                          |
|  PERSONAL RECORDS THIS MONTH:            |
|  - New longest streak: 15 days           |
|  - Best single day: Mar 15 (100% by 11am)|
|  - Most study in a day: 4h 20m (Mar 22) |
|                                          |
|  VERDICT:                                |
|  "March was your best month yet. +6%     |
|   over February. Dinner remains your     |
|   Achilles heel. April target: B+ or     |
|   higher. Fix dinner, break 85%."        |
|                                          |
+------------------------------------------+
```

### 14.3 Semester Review (Phase 2)

If the user sets semester start/end dates in Settings:

- Available at semester end.
- Shows: overall trajectory across all months, total study hours, total training days, average weekly completion, grade progression (month-by-month), longest streak of the semester.
- Verdict: "This semester: {overall_grade}. You studied {total_hours}h across {total_sessions} sessions. Your consistency improved from {first_month_pct}% to {last_month_pct}%. {verdict}."
- Shareable card for social media.

---

## 15. Edge Cases & Overrides

### 15.1 User Hasn't Opened App All Day

**Detection:** Background app refresh checks at each notification tier time. If no user interaction (no app opens, no notification actions) has occurred all day.

**Behavior:**
- Tier 1 notification fires normally (1:00 PM).
- If still no interaction by Tier 2: copy escalates. Example: "You haven't opened Tempo today. Your non-negotiables are sitting at 0%. Open the app."
- Tier 3+: normal escalation.
- Auto-tracked items (Whoop, NutriTrack) still sync via background refresh and count toward completion even without opening Tempo.

### 15.2 All Non-Negotiables Complete By Noon

**Behavior:**
- Tier 5 (Celebration) fires immediately upon completion.
- No further reminders for the day (Tiers 1-4 cancelled).
- Status Banner: "All done by noon. Legend." in `unlocked.green`.
- Leisure status: Unlocked.
- Special badge: "Early Bird" shown on the calendar heatmap for this day (small star icon in the corner of the date cell).
- Morning completion is tracked as a positive stat in weekly summary: "You finished before noon {count} times this week."

### 15.3 Manual Override (Force Unlock)

The app does NOT provide a manual override to unlock leisure without completing tasks. This is intentional -- the app is accountability-focused.

**However:**
- The user can "Skip" individual non-negotiables (via swipe or long-press context menu).
- Skipping all remaining non-negotiables effectively unlocks leisure (since all are "complete" via skip).
- Skipped tasks are tracked separately and shown in weekly summary.
- If the user skips > 2 non-negotiables in a day: "You skipped {skip_count} non-negotiables today. Skipping doesn't build the habit." (next morning notification).
- Skip frequency is tracked and shown in consistency view. A "skip rate" metric is visible in the weekly report.

**Skip Flow:**
1. User swipes left on a card or selects "Skip Today" from context menu.
2. Bottom sheet appears:
   - "Skip {item_name} for today?"
   - Reason picker (optional): "Rest Day", "Sick", "Emergency", "Schedule Conflict", "Other" (text field).
   - "This counts as completed for streak purposes but is tracked separately."
   - Buttons: "Cancel", "Skip" (amber, not red -- it's not destructive, it's an exception).
3. Card enters "Skipped" state (see 2.3).
4. If this causes all non-negotiables to be complete/skipped: unlock triggers (muted, see 12.3).

### 15.4 Non-Negotiable Becomes Impossible

**Scenarios:**
- Gym is closed (training can't happen).
- User is sick.
- Bad weather prevents outdoor activity.
- NutriTrack is down / data not syncing.

**Handling:**
- User can skip with reason (see 15.3).
- For auto-tracked items (Whoop/NutriTrack) that fail to sync: manual fallback button appears on the card after 2 hours of no data. "Not syncing? Log manually." Tapping shows a simple confirmation: "Did you complete {item_name} today?" with Yes/No.
- NutriTrack down specifically: card shows "Sync unavailable" in amber. "Log Manually" button becomes primary. Meals can be manually incremented with +/- buttons directly on the card.

### 15.5 Rest Day / Sick Day

See Section 13 for the complete specification.

### 15.6 Vacation Mode

**Activation:** Settings > "Vacation Mode" toggle. Requires end date.

**Behavior:**
- All non-negotiables suspended.
- No notifications fire (all tiers paused).
- Streak is frozen (not broken). Displayed as: "Streak: {streak} days (paused)".
- Calendar heatmap shows vacation days with a distinct style: light blue background, SF Symbol `airplane` watermark.
- Main view: simplified. Shows "Vacation Mode Active. Back on {date}." with a countdown.
- Auto-deactivates on the configured end date. Morning briefing fires: "Welcome back. Vacation's over. {total_count} non-negotiables today. Day {streak_plus_one} of your streak starts now."

**Guard rails:**
- Maximum vacation duration: 14 days. After that, streak resets. Warning shown at activation if > 14 days selected.
- If user extends vacation while active: warning that streak may reset.

### 15.7 Timezone Change (Travel)

- All times are anchored to the device's current timezone.
- If the user travels, times adjust automatically (notifications fire at local 8 AM, PS5 time at local 7:30 PM, etc.).
- No special handling needed. The system uses `Calendar.current` which respects timezone.
- Edge case: if timezone change causes a day to be "shorter" (e.g., traveling east), non-negotiable targets remain the same. The user may have fewer hours. Options: activate rest day, or work with the compressed timeline.
- Edge case: if timezone change causes a day to be "longer" (traveling west), no adjustment needed. More time to complete.
- Multi-timezone travel (e.g., flight from Miami to Tokyo): the system anchors to the destination timezone upon arrival. If non-negotiables were partially complete in the origin timezone, they carry over. No double-counting days.

### 15.8 Daylight Saving Time

- Handled by the OS. `UNCalendarNotificationTrigger` respects DST transitions.
- No special handling needed in app logic.
- Note: Spring forward (lose 1 hour) means 1 less hour to complete tasks. Fall back (gain 1 hour) means extra time. The system does not adjust targets for this. 2 hours of study is 2 hours regardless of DST.

### 15.9 First Day / Onboarding

When the user first accesses the Lockdown module:
1. Welcome screen: "Welcome to Lockdown. Define your non-negotiables. Earn your leisure."
2. Template selection (see 4.7). "Start with a template or build your own."
3. PS5 time configuration: "When do you usually start gaming? This is your daily deadline." Time picker.
4. Notification permission request: "Lockdown needs notifications to keep you accountable. Without them, it's just a to-do list." Standard iOS permission dialog, pre-framed with this context.
5. Integration setup: "Connect Whoop and NutriTrack for automatic tracking." Connect buttons with skip option.
6. Confirmation: "You're set. {total_count} non-negotiables. Complete them daily to unlock your evening. Starting tomorrow." Button: "LET'S GO" -- dismisses onboarding, sets first morning briefing for next day.

First-day special: No streak pressure on day 1. Morning briefing copy: "Day 1. No streak to protect yet -- just a standard to set. Study {study_target}, Train, {meal_count} Meals. Show yourself what you're capable of."

### 15.10 App Deletion and Reinstall

- Data stored locally via SwiftData. If app is deleted, data is lost.
- iCloud backup (if enabled): Streak count and settings are backed up to iCloud key-value store (`NSUbiquitousKeyValueStore`). On reinstall, streak is restored. Full history is NOT backed up (too large for KVS).
- On reinstall detection (streak exists in iCloud but no local data): "Welcome back. Your {streak}-day streak was saved. Picking up where you left off." Fetches streak from iCloud, sets it locally.
- If no iCloud data: fresh start. Standard onboarding.

### 15.11 Phone Dies Mid-Day

- Timer was running: on next app launch, system calculates elapsed time from saved `timerStartDate` to current time. If > session duration, session is marked complete. If phone was dead for hours, multiple sessions may have "passed" -- only the active session is credited, not phantom sessions.
- Notifications missed: any scheduled notifications that fired while phone was dead are delivered when phone turns on (standard iOS behavior). They may be stale -- the system checks if they're still relevant before displaying in-app actions.
- Background syncs missed: Whoop/NutriTrack data syncs on next app open. Progress updates accordingly.
- If phone died before any tasks were completed and turns on after PS5 time: the day is marked as failed. No retroactive adjustments. "Your phone died, but the standard didn't. Tomorrow, keep your phone charged."

### 15.12 User Changes Non-Negotiables Mid-Day

- **Adding a new non-negotiable:** Appears immediately. Progress starts at 0% for today. Affects today's completion percentage. If it was 100% and adding a new one drops it below 100%, the lock RE-LOCKS. Confirmation: "Adding this will re-lock your leisure until it's completed. Continue?"
- **Removing a non-negotiable:** Disappears immediately. Today's percentage recalculates without it. If removal causes 100% completion, unlock triggers. Historical data preserved.
- **Changing a target (e.g., 2h -> 3h):** Takes effect immediately. If user had completed 2h and target was 2h (100%), changing to 3h makes it 67%. Lock re-engages. Confirmation required.
- **Changing active days:** If today's day is toggled off, the non-negotiable disappears from today. If toggled on, it appears.

### 15.13 Two Exams on Same Day

See Section 9.6 for complete specification.

### 15.14 Football Match at Unusual Time (Evening Game)

If the user has a football match in the evening (detected via calendar event containing "football", "soccer", "game", "match" or manually flagged):

- PS5 time automatically shifts to accommodate the match. If match is 7-9 PM, PS5 time shifts to 5:30 PM (before match) or 9:30 PM (after match), depending on user preference.
- Alternatively: user can set "Match Day" mode in settings, which pre-configures adjusted timing.
- Training non-negotiable: football match counts as training. If Whoop/HealthKit detects a workout during match time, training auto-completes. Otherwise, user can manually mark "Football Match" as training completion.
- Notification: "Match day. PS5 time adjusted to {adjusted_time}. Training will count from the game. Get study and meals done before kickoff."

### 15.15 Holiday / Vacation (Abroad)

See 15.6 for vacation mode. Additional considerations for abroad travel:

- **Timezone handling:** see 15.7.
- **Data connectivity:** if user is abroad without data, auto-tracked items (Whoop, NutriTrack) may not sync. Manual fallback buttons appear after 2 hours of no data.
- **International meal patterns:** in some countries, meals happen at different times (Spain: dinner at 10 PM). User can adjust meal deadline expectations without changing PS5 time.
- **SIM change / new device:** iCloud sync ensures streak is preserved across devices.

### 15.16 App Update During Active Streak

- App updates should never break streak data. SwiftData migrations handle schema changes.
- If an update requires migration: migration runs silently on first launch. If migration fails, streak is preserved from iCloud KVS as backup.
- If update adds new notification tiers or changes behavior: existing settings are preserved. New features default to OFF until user opts in.
- Active timers: if app is force-quit during update, timer data is preserved via the saved `timerStartDate` approach (see 15.11).

### 15.17 Internet Outage for Days

- **Local-first architecture:** All core functionality works offline. Non-negotiables, timer, streak, notifications -- all local.
- **Whoop sync:** paused. Manual fallback after 2 hours. Resumes on reconnect. Historical data backfills.
- **NutriTrack sync:** paused. Manual fallback. Resumes on reconnect.
- **Arena features:** paused. XP cached locally, synced on reconnect. Leaderboard shows stale data with "Last updated: {date}" label.
- **No data loss:** everything is local-first. Internet outage should be invisible to the core accountability experience.

### 15.18 User Hasn't Opened App in 2 Weeks -- Re-engagement Flow

**Detection:** On app launch, if `lastActiveDate` is > 14 days ago.

**Flow:**
1. Full-screen re-engagement view instead of normal main view.
2. Content:
   - "Hey. It's been {days} days."
   - "Your streak was {last_streak} days when you left."
   - "Your streak is now 0."
   - "But your non-negotiables are still here. And so are you."
   - [Show summary of what was set up: Study 2h, Training, 3 Meals]
   - "Ready to restart?"
   - Buttons:
     - "Restart with same non-negotiables" -- keeps existing setup, starts Day 1.
     - "Adjust my plan" -- opens Non-Negotiable Setup View for review.
     - "Start fresh" -- resets everything, runs onboarding.
3. Morning briefing for restart day: "Day 1 again. No shame in restarting. The only failure is not coming back. {total_count} non-negotiables. Let's go."

### 15.19 Notification Permission Denied

If the user denies notification permission:
- Lockdown still functions (timer, tracking, unlock all work).
- A persistent (but dismissible) banner at the top of main view: "Notifications are off. Lockdown works best with them. [Enable in Settings]"
- All tier logic still runs internally (badge updates, in-app alerts still trigger when app is foregrounded).
- The system does NOT repeatedly ask for permission. The banner is the nudge.

### 15.20 iCloud Sync Conflict

If streak data in iCloud differs from local data (e.g., user used two devices):
- Take the HIGHER streak count. Always favor the user.
- Log the conflict for debugging.
- Merge settings by most recent `updatedAt` timestamp.

### 15.21 System Clock Manipulation

If the user manually advances the system clock to fake completion:
- **Detection:** Compare `Date()` with `lastKnownDate`. If the current date jumps forward by > 24 hours without any background app refresh in between, flag as suspicious.
- **Response:** Do nothing punitive. The system is designed for genuine accountability, not DRM. If someone is manipulating their clock to fake study time, the app isn't the solution -- the user is only cheating themselves.
- Historical data may show gaps, which is self-evident.

### 15.22 HealthKit Permission Revoked

If the user revokes HealthKit access after connecting:
- Training card shows: "HealthKit access revoked. [Reconnect]" with a warning icon.
- Manual fallback activates: "Log Manually" button appears.
- Notification: "Whoop/HealthKit disconnected. Training will need manual logging until reconnected."
- Previous auto-tracked data is preserved.

### 15.23 NutriTrack App Not Installed

If NutriTrack is not installed but the user has Meals as a non-negotiable with NutriTrack tracking:
- Card shows: "NutriTrack not installed. [Install] or switch to manual tracking."
- "Install" opens App Store link.
- "Switch to manual" changes tracking method to manual counter. User taps +/- to log meals.
- The system checks for NutriTrack installation on each app foreground. If detected, auto-switches to NutriTrack tracking with a confirmation.

### 15.24 Whoop Battery Dies

If Whoop stops syncing (common when battery dies):
- After 2 hours of no Whoop data: card shows "Whoop not syncing" with amber indicator.
- After 4 hours: manual fallback button appears: "Log Training Manually."
- If Whoop syncs later with historical data: auto-updates the training card. If user already logged manually, defers to manual entry (avoids double-counting).

### 15.25 User in Different Timezone Than Home (Semester Abroad)

If the user moves to a new timezone permanently (not just travel):
- All times adjust automatically via `Calendar.current`.
- Weekend detection adjusts to new locale's calendar.
- No special handling needed unless the user's "home" schedule is wildly different from the new timezone. In that case, the user should reconfigure PS5 time and morning briefing time in Settings.
- Suggestion: on first app open in a significantly different timezone (>6 hours offset), prompt: "Looks like you're in a new timezone ({timezone}). Do you want to adjust your PS5 time and briefing time? [Adjust] [Keep Current]"

### 15.26 Multiple Users on Same Device (Shared iPad)

- Not supported in MVP. Lockdown is single-user by design.
- Sign in with Apple ties data to the Apple ID. If a different Apple ID signs in, separate data.

### 15.27 Low Storage Space

- If device storage is critically low, SwiftData writes may fail.
- Graceful degradation: timer still works (stores in memory), but data may not persist until storage is freed.
- Warning: "Storage is low. Tempo may not be able to save your data. Free up space to avoid losing progress."

### 15.28 ADHD-Friendly Mode

**Behavioral science context:** Users with ADHD experience executive function difficulties that make standard accountability systems counterproductive. The notification escalation system (Tiers 1-4) can trigger rejection-sensitive dysphoria (RSD), a common ADHD comorbidity where perceived criticism causes intense emotional pain. Savage mode messages that work for neurotypical users can cause ADHD users to shut down entirely. Additionally, ADHD brains respond differently to reward timing -- delayed rewards (like "unlock PS5 tonight") are less motivating because of temporal discounting differences (Sonuga-Barke, 2005).

**Activation:** Settings > Accessibility > "ADHD-Friendly Mode" toggle. Description: "Adapts the accountability system for ADHD: shorter tasks, more frequent positive feedback, gentler escalation. This is not a lesser version -- it's a smarter one."

**Behavioral changes:**

1. **Shorter default sessions.** Default timer shifts to 15-minute sessions with 5-minute breaks (instead of 25/5 Pomodoro). Research shows ADHD individuals benefit from more frequent break intervals (Rapport et al., 2009). The user can still select longer sessions -- the default just starts shorter.

2. **More frequent micro-celebrations.** Instead of celebrating only at 100% daily completion, ADHD mode celebrates each individual non-negotiable completion with a brief animation and a positive message. Each completion fires a mini Tier 5 notification: "Study: DONE. 1 of 3 handled. Nice." Immediate positive reinforcement is more effective for ADHD than delayed reward (Luman et al., 2005).

3. **Reduced notification escalation.** Maximum notification tier is Tier 2 (Firm Warnings). Tiers 3-4 (Urgent/Final) are disabled by default. The escalation pattern triggers anxiety without productive action in many ADHD users. If the user wants higher tiers, they can enable them manually.

4. **Intensity locked to Gentle or Standard.** Savage mode is not available in ADHD-Friendly mode. This is a design choice based on research: shame-based accountability is particularly harmful for individuals with ADHD, who often have a lifetime of negative feedback experiences (Barkley, 2015). The system uses encouraging, action-oriented language only.

5. **Task breakdown prompts.** When a non-negotiable seems stuck at 0% past noon, instead of an escalating warning, the notification asks: "Study feels big. Want to break it into a 15-minute sprint? Just one small chunk." This leverages task initiation scaffolding -- the hardest part of ADHD is starting, not sustaining.

6. **Visual progress emphasis.** Progress bars use more granular color changes (every 10% instead of every 25%) to make small progress more visible and rewarding. The ProgressRing animates more frequently to provide dopaminergic micro-feedback.

7. **Streak freeze built in.** ADHD users get 2 automatic "grace days" per week where a missed day does not break the streak (no action required -- the system auto-applies). This accounts for the natural inconsistency of ADHD without punishing it. The user still sees what was missed, but the streak is protected.

8. **No "I Accept the L" language.** The full-screen Tier 4 alert (6.6) is replaced with: "Today didn't go as planned. That's OK. Tomorrow is a fresh start." The third button reads "Move to Tomorrow" instead of "I Accept the L."

**Notification copy pool (ADHD mode, 10 messages per tier):** Uses only Gentle pool messages, with additions:
- "15 minutes. That's all. Just one small session to get started."
- "You don't have to do it all at once. Start with the easiest thing on your list."
- "Your brain is fighting you right now. That's normal. Start the timer and let the system carry you."
- "Focus is hard today? That's OK. A 15-minute session still counts. Tap Start."
- "Hey. No pressure. But if you start a session right now, Future You will be grateful."

### 15.29 Arena Leaderboard Timezone Fairness

**Problem:** If friends are in different time zones, the user in an earlier timezone has fewer hours remaining when the leaderboard "day" resets, creating an unfair comparison window.

**Solution:**
- Arena leaderboard uses each user's LOCAL midnight as their day boundary. Completion percentages are calculated within each user's own day.
- The leaderboard shows "as of [local time]" next to each friend's percentage: "Marco: 82% (as of 3:15 PM EST)". This provides context.
- "Friend completed" notifications account for timezone: if a friend completes at 5 PM in their timezone but it's 11 PM in the user's timezone, the notification is suppressed (it would arrive during quiet hours and feel unfair).
- Weekly summary comparisons use 7-day averages rather than same-day snapshots, which neutralizes timezone effects.
- If the timezone difference between two friends is > 8 hours, the system warns: "You and {friend} are {hours} hours apart. Daily comparisons may not be meaningful -- weekly averages are more fair."

### 15.30 User Returns After Long Illness (7+ Days Sick)

- After 7+ consecutive sick days, the standard non-negotiable targets may feel overwhelming.
- **Ease-back protocol:** First day back, targets automatically reduce to 50% for all non-negotiables. Second day: 75%. Third day: 100%. Notifications mention this: "Welcome back. Targets are at 50% today to ease you in. Full targets return in 3 days."
- The user can override to full targets immediately if they feel ready.
- Streak is preserved through the entire sick period, regardless of length.

### 15.31 Notification Fatigue Detection

- If the user receives 3+ notifications in a day and takes no action on any (no app open, no notification tap, no timer start within 15 minutes of any notification), the system flags potential notification fatigue.
- Next day, the system reduces notification volume: skip Tier 1, fire only 1 Tier 2 instead of 2, and include a meta-message: "I notice the reminders aren't landing. Would fewer, better-timed notifications help? [Adjust in Settings]"
- If fatigue is detected 3 days in a row: automatically switch to Gentle intensity for 1 week with a notification: "Switching to lighter reminders for a bit. You can change this anytime in Settings."
- This prevents the system from becoming "nagware" -- research on notification habituation (Mehrotra et al., 2016) shows users rapidly learn to ignore high-frequency notifications, reducing their effectiveness to zero.

---

## 16. Data Model Summary

### 16.1 Core Entities

```
NonNegotiable
+-- id: UUID
+-- name: String (max 30)
+-- icon: String (SF Symbol name)
+-- type: Enum (timed, counter, binary)
+-- targetValue: Double (hours for timed, count for counter, 1 for binary)
+-- trackingMethod: Enum (manualTimer, manualCheck, manualCounter, whoop, nutritrack, healthkit)
+-- activeDays: [Bool] (7 elements, Mon-Sun)
+-- weekendTargetValue: Double? (optional override for weekend days)
+-- sortOrder: Int
+-- isActive: Bool
+-- createdAt: Date
+-- updatedAt: Date

DailyRecord
+-- id: UUID
+-- date: Date (day only, no time)
+-- nonNegotiableId: UUID (FK)
+-- currentValue: Double
+-- targetValue: Double (snapshot of target for that day)
+-- status: Enum (notStarted, inProgress, completed, skipped, restDay, sickDay, mentalHealthDay)
+-- skipReason: String?
+-- completedAt: Date?
+-- source: Enum (manual, whoop, nutritrack, healthkit)
+-- entries: [DailyEntry] (relationship)

DailyEntry
+-- id: UUID
+-- dailyRecordId: UUID (FK)
+-- startTime: Date
+-- endTime: Date?
+-- value: Double (duration in minutes, or count increment)
+-- subject: String? (for study sessions)
+-- distractionCount: Int? (for study sessions)
+-- pauseCount: Int? (for study sessions)
+-- pauseDuration: Double? (total pause minutes)
+-- focusScore: Int? (0-100, calculated at session end)
+-- sessionType: Enum? (pomodoro, ultradianSprint, deepWork, flow, custom)
+-- source: Enum (timer, manual, integration)

Streak
+-- currentStreak: Int
+-- longestStreak: Int
+-- bestRecentStreak: Int (best streak in last 30 days)
+-- lastCompletedDate: Date?
+-- streakFrozenUntil: Date? (vacation)
+-- consecutivePerfectDays: Int (for reward escalation)
+-- recoveryAvailableUntil: Date? (24h grace period for streak recovery, see 12.5)
+-- lastRecoveryUsedDate: Date? (prevents recovery abuse, max once per 14 days)
+-- preBreakStreak: Int? (streak count before break, used for recovery restoration)

Exam
+-- id: UUID
+-- name: String
+-- date: Date
+-- subject: String?
+-- estimatedHours: Double?
+-- topics: String?
+-- isActive: Bool
+-- detectedFromCalendar: Bool

WeeklyReview
+-- id: UUID
+-- weekStartDate: Date
+-- weekEndDate: Date
+-- overallPercentage: Double
+-- grade: String (A+ through F)
+-- studyHours: Double
+-- trainingDays: Int
+-- mealsLogged: Int
+-- perfectDays: Int
+-- skipCount: Int
+-- restDayCount: Int
+-- patterns: [String] (identified patterns)
+-- generatedAt: Date

MonthlyReview
+-- id: UUID
+-- month: Int
+-- year: Int
+-- overallPercentage: Double
+-- grade: String
+-- studyHours: Double
+-- trainingDays: Int
+-- mealsLogged: Int
+-- streakLongest: Int
+-- streakBreaks: Int
+-- perfectWeeks: Int
+-- restDaysUsed: Int
+-- personalRecords: [String]
+-- generatedAt: Date

ImplementationIntention
+-- id: UUID
+-- date: Date
+-- nonNegotiableId: UUID (FK)
+-- plannedTime: Date?
+-- plannedLocation: String?
+-- createdAt: Date

UserSettings
+-- ps5TimeWeekday: Date (time only)
+-- ps5TimeWeekend: Date (time only)
+-- morningBriefingTimeWeekday: Date (time only)
+-- morningBriefingTimeWeekend: Date (time only)
+-- notificationIntensity: Enum (gentle, standard, savage)
+-- quietHoursStart: Date (time only)
+-- quietHoursEnd: Date (time only)
+-- tierEnabled: [Bool] (7 elements, Tier 0-6)
+-- defaultSessionType: Enum (pomodoro, ultradianSprint, deepWork, flow, custom)
+-- focusDuration: Int (minutes)
+-- shortBreakDuration: Int (minutes)
+-- longBreakDuration: Int (minutes)
+-- sessionsBeforeLongBreak: Int
+-- autoStartBreaks: Bool
+-- autoStartFocus: Bool
+-- sessionSound: String
+-- keepScreenOn: Bool
+-- examActivationThreshold: Int (days)
+-- examAutoDetectFromCalendar: Bool
+-- examStudyIncrease: Double (multiplier, e.g., 1.5 for +50%)
+-- examPs5TimeShift: Int (minutes, negative)
+-- restDaysPerMonthMax: Int
+-- injuryModeActive: Bool
+-- injuryModeEndDate: Date?
+-- calendarIntegrationEnabled: Bool
+-- arenaSocialAccountabilityEnabled: Bool
+-- screenTimeApiEnabled: Bool
+-- adhdFriendlyMode: Bool (default false, see 15.28)
+-- adhdGraceDaysPerWeek: Int (default 2, only used when adhdFriendlyMode is true)
+-- notificationFatigueConsecutiveDays: Int (tracks days of ignored notifications, see 15.31)
+-- vacationModeEndDate: Date?
+-- ambientSound: String?
+-- ambientVolume: Double
+-- lastActiveDate: Date
+-- lastKnownTimezone: String
```

### 16.2 Derived Calculations

**Daily Completion Percentage:**
`sum(min(record.currentValue / record.targetValue, 1.0) for each active record) / count(active records) * 100`

**Leisure Unlock Logic:**
`all(record.status in [.completed, .skipped, .restDay, .sickDay, .mentalHealthDay] for each active record today)`

**Streak Logic:**
```
func calculateStreak() -> Int {
    var streak = 0
    var date = today
    while true {
        let records = fetchRecords(for: date)
        if records.isEmpty && !isVacationDay(date) && !isRestDay(date) && !isSickDay(date) {
            break // No data = streak broken
        }
        if isVacationDay(date) || isRestDay(date) || isSickDay(date) || isMentalHealthDay(date) {
            date = date.previousDay()
            continue // Skip, don't count but don't break
        }
        let allComplete = records.allSatisfy { $0.status == .completed || $0.status == .skipped }
        if allComplete {
            streak += 1
            date = date.previousDay()
        } else {
            break
        }
    }
    return streak
}
```

**Focus Score Calculation:**
```
func calculateFocusScore(entry: DailyEntry) -> Int {
    let distractionScore = distractionTier(entry.distractionCount ?? 0)
    let pauseFreqScore = pauseFreqTier(entry.pauseCount ?? 0, sessionMinutes: entry.value)
    let pauseDurationScore = pauseDurationTier(entry.pauseDuration ?? 0, sessionMinutes: entry.value)
    let completionScore = completionTier(entry.value, targetMinutes: sessionTargetMinutes)

    return Int(distractionScore * 0.35 + pauseFreqScore * 0.25 + pauseDurationScore * 0.20 + completionScore * 0.20)
}
```

**Notification Tier Timing (relative to PS5 time):**
```
let psTime = userSettings.ps5Time(for: today)

tier0 = userSettings.morningBriefingTime(for: today)
tier1 = max(noon, psTime - 6.5h)   // ~1:00 PM for 7:30 PM
tier2Start = psTime - 4.5h          // ~3:00 PM
tier2End = psTime - 2h              // ~5:30 PM
tier3Start = psTime - 2h            // ~5:30 PM
tier3End = psTime - 30min           // ~7:00 PM
tier4First = psTime - 15min         // ~7:15 PM
tier4Second = psTime                // ~7:30 PM
```

**Reward Escalation Logic:**
```
func checkRewardEscalation(consecutivePerfectDays: Int) -> Reward? {
    switch consecutivePerfectDays {
    case 3: return .threeDay
    case 5: return .bonusHour
    case 7: return .perfectWeek
    case 14: return .twoWeek
    case 21: return .habitFormed
    case 30: return .monthlyChampion
    case 50: return .elite
    case 100: return .century
    default: return nil
    }
}
```

---

## Appendix A: Animation Specifications

| Animation | Type | Duration | Easing | Details |
|-----------|------|----------|--------|---------|
| Card completion | Scale + fade | 0.4s | Spring (response: 0.5, damping: 0.7) | Scale 1.0 -> 1.03 -> 1.0, checkmark draws |
| Unlock transition | Chain break + spring + glow | 2.0s | Spring (response: 0.6, damping: 0.8) | Chains snap, lock shackle lifts, green glow expands |
| Confetti burst | Physics | 3.0s | Linear (gravity) | 50-80 particles, randomized velocity/rotation |
| Progress ring fill | Spring | 0.6s | Spring (response: 0.6, damping: 0.8) | Arc length animates to target |
| Card overdue pulse | Opacity | 2.0s cycle | EaseInOut | Border opacity 0.5 -> 1.0 -> 0.5, infinite |
| Timer colon blink | Opacity | 1.0s cycle | EaseInOut | Opacity 1.0 -> 0.3 -> 1.0, infinite while paused |
| Streak flame flicker | Scale | 1.5-2.5s (random) | EaseInOut | Scale 1.0 -> 1.05 -> 0.97 -> 1.0, infinite |
| Card expand (detail) | Height + fade | 0.3s | EaseInOut | Height expands, content fades in at 0.15s |
| Drag reorder lift | Scale + shadow | 0.2s | EaseOut | Scale 1.0 -> 1.05, shadow appears |
| Status banner lock shake | Rotation | 0.15s x3 | Linear | RotateZ -3deg -> 3deg, 3 repetitions |
| Full-screen alert glow | Shadow radius | 1.5s cycle | EaseInOut | Shadow 10pt -> 20pt -> 10pt, infinite |
| Celebration confetti | Physics + fade | 3.0s | Linear + fadeOut at 2.5s | Multi-color, randomized trajectories |
| Streak number odometer | Slide + fade | 0.3s (staggered) | Spring | Each digit slides up, 0.05s stagger |
| Quick action button press | Scale | 0.1s | EaseInOut | Scale 1.0 -> 0.97 -> 1.0 |
| Lock breathing (locked) | Scale | 3.0s cycle | EaseInOut | Scale 1.0 -> 1.01 -> 1.0, subtle, infinite |
| Lock crack progression | Texture overlay | Instant on state change | None | Progressive crack textures at 25%, 50%, 75% completion |
| Lock strain shake | Rotation | 0.1s x2 every 10s | Linear | At 75%+ completion, lock shakes periodically |
| Chain snap | Particle + scale | 0.3s | EaseOut | Particles burst from break points, chain segments fly apart |
| Muted skip unlock | Slow open | 1.5s | EaseInOut | Lock opens slowly, no spring, grey/amber color |
| Exam mode banner pulse | Border opacity | 2.0s cycle | EaseInOut | Red border pulses at 1-3 days from exam |
| Focus score indicator | Fade + color | 0.4s | EaseInOut | Dot color transitions based on running score |

---

## Appendix B: Sound Assets Required

| Sound | File | Duration | Description |
|-------|------|----------|-------------|
| Session complete | `session_complete.caf` | 1.0s | Clean bell chime, major note |
| All sessions done | `all_sessions.caf` | 2.0s | Ascending chord, celebratory |
| Unlock leisure | `celebration.caf` | 1.5s | Bright ascending three-note chime with sparkle |
| Chain snap | `chain_snap.caf` | 0.3s | Metallic snap, crisp, satisfying |
| Firm warning | `firm_warning.caf` | 0.5s | Double-tap tone, attention-getting |
| Urgent alert | `urgent_alert.caf` | 1.0s | Three-note ascending alert, sharp |
| Final warning | `final_warning.caf` | 1.5s | Four-note descending staccato, aggressive |
| Timer tick (optional) | `tick.caf` | 0.1s | Subtle tick, for last 10 seconds of focus |
| Ambient: Rain | `ambient_rain.caf` | 60s | Seamless loop, gentle rain on window |
| Ambient: Heavy Rain | `ambient_heavy_rain.caf` | 60s | Seamless loop, downpour with distant thunder |
| Ambient: Coffee shop | `ambient_coffee.caf` | 90s | Seamless loop, quiet cafe, espresso hiss, murmur |
| Ambient: Library | `ambient_library.caf` | 90s | Seamless loop, page turns, quiet shuffling |
| Ambient: Fireplace | `ambient_fireplace.caf` | 60s | Seamless loop, crackling fire, wood pops |

All notification sounds must be < 30 seconds (iOS requirement). All sounds must be in CAF, AIFF, or WAV format for notification compatibility.

---

## Appendix C: Accessibility

- All text supports Dynamic Type (scales with system font size).
- All interactive elements have minimum 44x44pt hit targets.
- All icons have `accessibilityLabel` descriptions.
- Progress rings announce percentage via VoiceOver: "Daily progress: 47%".
- Card states announced: "Study, in progress, 1 hour 23 minutes of 2 hours".
- Timer announces time remaining every minute via VoiceOver (if VoiceOver is active).
- Confetti and particle animations respect `UIAccessibility.isReduceMotionEnabled` -- replaced with static checkmark/color change.
- Chain snap animation replaced with simple lock transition when Reduce Motion is enabled.
- Color coding is never the sole indicator -- text labels always accompany colored states.
- Full-screen alert is navigable via VoiceOver; focus moves to first actionable button.
- Ambient sounds respect VoiceOver audio ducking.
- Focus score described as: "Focus score: 87 out of 100, Good."

---

## Appendix D: Template Variables Reference

All notification copy uses these template variables, filled at runtime:

| Variable | Description | Example |
|----------|-------------|---------|
| `{count}` | Total active non-negotiables today | "3" |
| `{total_count}` | Same as count | "3" |
| `{done_count}` | Completed non-negotiables | "1" |
| `{remaining_count}` | Incomplete non-negotiables | "2" |
| `{remaining_plural}` | "s" if remaining > 1, "" if 1 | "s" |
| `{completion_pct}` | Overall daily completion % | "47" |
| `{streak}` | Current streak days | "12" |
| `{streak_plus_one}` | Current streak + 1 (today's potential) | "13" |
| `{study_target}` | Today's study time target | "2h" |
| `{study_minutes}` | Minutes studied today | "27" |
| `{study_remaining}` | Study time remaining | "1h 33m" |
| `{study_total}` | Total study time today | "2h 07m" |
| `{study_status}` | Study progress summary | "27min/2h" |
| `{study_pct}` | Study completion % | "23" |
| `{training_status}` | Training status text | "not done" / "done" |
| `{meals_done}` | Meals logged today | "2" |
| `{meal_count}` | Meal target | "3" |
| `{meals_remaining}` | Meals still needed | "1" |
| `{ps5_time}` | Configured PS5 time | "7:30 PM" |
| `{hours_until_ps5}` | Hours until PS5 time | "4" |
| `{time_until_ps5}` | Time until PS5 (formatted) | "1h 45m" |
| `{minutes_before_ps5}` | Minutes before PS5 time | "12" |
| `{minutes_after_ps5}` | Minutes past PS5 time | "15" |
| `{current_time}` | Current time | "3:15 PM" |
| `{day_of_week}` | Today's day name | "Thursday" |
| `{morning_briefing_time}` | Configured morning time | "8:00 AM" |
| `{incomplete_list}` | List of incomplete items | "Study (-37 min), Dinner" |
| `{remaining_tasks_detail}` | Detailed remaining tasks | "Study: 1h 33m more, Dinner: not logged" |
| `{remaining_tasks_summary}` | Brief remaining summary | "study and dinner" |
| `{not_started_item}` | Name of an unstarted item | "Study" |
| `{not_started_list}` | All unstarted items | "Study, Reading" |
| `{weakest_item}` | Lowest completion non-negotiable (30-day) | "Dinner" |
| `{exam_name}` | Active exam name | "Calculus II Final" |
| `{exam_days}` | Days until exam | "6" |
| `{exam_study_target}` | Enhanced study target for exam | "3h" |
| `{yesterday_first_action}` | First action user took yesterday | "studied 25 minutes" |
| `{yesterday_pct_at_time}` | Yesterday's % at same time | "62" |
| `{last_week_pct}` | Last week's overall % | "78" |
| `{best_day}` | Best day this week | "Tuesday" |
| `{worst_day}` | Worst day this week | "Thursday" |
| `{friend_name}` | Arena friend's name | "Marco" |
| `{friend_pct}` | Friend's completion % | "82" |
| `{time_before_ps5}` | Time completed before PS5 | "2h 15m" |
| `{completion_time}` | Time of day completed | "5:15 PM" |
| `{month_name}` | Current month | "March" |
| `{milestone}` | Next streak milestone | "30" |
| `{days_to_milestone}` | Days to reach milestone | "2" |

---

*End of specification.*
