# Tempo -- Accessibility Specification v1.0

**App:** Tempo (iOS, SwiftUI, iOS 17+)
**Standard:** WCAG 2.2 AA + Apple Human Interface Guidelines (Accessibility)
**Author:** Accessibility Specialist
**Last Updated:** 2026-03-24
**Scope:** Every screen, every interaction, every edge case.

> Accessibility is not a feature toggle. It is a quality standard that applies to every line of UI code shipped in Tempo. If a screen cannot be operated by a blind user with VoiceOver, a motor-impaired user with Switch Control, or a low-vision user at AX5 Dynamic Type, that screen is not done.

---

## Table of Contents

1. [Accessibility Standards](#1-accessibility-standards)
2. [VoiceOver -- Complete Screen-by-Screen Audit](#2-voiceover--complete-screen-by-screen-audit)
3. [Dynamic Type](#3-dynamic-type)
4. [Color and Visual Accessibility](#4-color-and-visual-accessibility)
5. [Motor Accessibility](#5-motor-accessibility)
6. [Reduce Motion](#6-reduce-motion)
7. [Cognitive Accessibility](#7-cognitive-accessibility)
8. [Audio Accessibility](#8-audio-accessibility)
9. [Accessibility Testing Checklist](#9-accessibility-testing-checklist)
10. [Accessibility Settings in Tempo](#10-accessibility-settings-in-tempo)
11. [Localization Accessibility](#11-localization-accessibility)

---

## 1. Accessibility Standards

### 1.1 Compliance Targets

| Standard | Level | Requirement |
|----------|-------|-------------|
| **WCAG 2.2** | AA (minimum) | All 50 success criteria at Level A and AA must be met. Level AAA is targeted where achievable (e.g., contrast ratios, text spacing). |
| **Apple HIG -- Accessibility** | Full compliance | Every guideline in the Accessibility chapter of the Apple Human Interface Guidelines. |
| **Section 508** | Functional equivalence | Federal accessibility standard. Met by satisfying WCAG 2.2 AA. |
| **EN 301 549** | Clause 11 (Software) | European standard. Required for App Store distribution in the EU. Met by satisfying WCAG 2.2 AA plus mobile-specific requirements. |

### 1.2 Assistive Technology Support Matrix

| Technology | Support Level | Notes |
|------------|--------------|-------|
| **VoiceOver** | Full | Every screen fully navigable. Custom actions for complex interactions. Rotor support. Focus management on all state changes. |
| **Switch Control** | Full | All screens navigable via scanning. Custom scan groups defined for complex layouts (dashboard quadrants, workout cards). |
| **Voice Control** | Full | Every button, link, and interactive element has a visible or accessibility label that matches Voice Control commands. |
| **Full Keyboard Access** | Full | All interactive elements reachable via Tab key. Focus ring visible on all focused elements. Enter/Space activate. Arrow keys navigate within groups. |
| **AssistiveTouch** | Full | No interaction requires multi-finger gestures exclusively. Single-tap alternatives exist for every action. |
| **Dwell Control** | Supported | All interactive elements respond to dwell selection. No time-critical hover states. |
| **Braille Display** | Supported | VoiceOver Braille output verified for all labels and values. |
| **Made for iPhone Hearing Aids** | Supported | Audio routing tested with MFi hearing aids. |

### 1.3 Core Principles

1. **Perceivable.** All information is available through at least two sensory channels (visual + auditory, visual + haptic, auditory + haptic). No information conveyed by color alone.
2. **Operable.** Every function is reachable by every input method: touch, VoiceOver gesture, Switch Control scan, Voice Control command, external keyboard.
3. **Understandable.** Labels are concise and unambiguous. State changes are announced. Errors explain what went wrong and how to fix it. Language is plain (8th-grade reading level or below).
4. **Robust.** Standard UIKit/SwiftUI accessibility APIs are used (no custom hacks). Tested with future OS betas before shipping updates.

### 1.4 Accessibility Traits Reference

All custom views must set appropriate accessibility traits:

| Trait | When to Use |
|-------|------------|
| `.isButton` | Any tappable element that performs an action |
| `.isHeader` | Section headers, screen titles, quadrant titles |
| `.isLink` | Elements that navigate to another screen or open a URL |
| `.isImage` | Decorative or informational images |
| `.updatesFrequently` | Live data: timers, heart rate, step counter |
| `.isStaticText` | Labels that do not change |
| `.isSelected` | Currently selected tab, filter, or option |
| `.isNotEnabled` | Disabled buttons, locked features |
| `.isSummaryElement` | Score ring, daily score, streak counter -- announced on screen summary |
| `.startsMediaSession` | Start Workout button, Start Timer button |
| `.adjustable` | Weight steppers, rep counters, sliders |

---

## 2. VoiceOver -- Complete Screen-by-Screen Audit

### 2.0 Global VoiceOver Conventions

**Reading order:** Unless specified otherwise, VoiceOver reads top-to-bottom, left-to-right within each logical row. Grouped elements are read as a single unit with a combined label.

**Navigation bar:** On every screen, VoiceOver reads:
1. Back button (if present): "Back, button"
2. Screen title (if present): "[Title], heading"
3. Right bar buttons, left-to-right

**Tab bar:** Read as a group at the bottom: "[Tab name], tab, [N] of 5, [selected/not selected]"

**Focus management rules (global):**
- On screen push: focus moves to the first meaningful element (usually the screen title or primary content, NOT the back button).
- On sheet presentation: focus moves to the sheet title or first interactive element.
- On sheet dismissal: focus returns to the element that triggered the sheet.
- On alert presentation: focus moves to the alert title.
- On alert dismissal: focus returns to the element that triggered the alert.
- On action completion (e.g., completing a set, checking off a non-negotiable): focus stays on the completed element and an announcement is posted.
- On pull-to-refresh: announce "Refreshing" then "Data updated" when complete.
- On data load failure: announce "Failed to load [data type]. Double-tap to retry."

**Announcement posting:** Use `UIAccessibility.post(notification: .announcement, argument:)` for all state changes that are not focus changes. Use `UIAccessibility.post(notification: .screenChanged, argument:)` when the entire screen content changes. Use `UIAccessibility.post(notification: .layoutChanged, argument:)` when a portion of the screen updates.

---

### 2.1 Dashboard (LifeOS)

The dashboard is the home screen with a 4-quadrant layout (Body, Fuel, Mind, Move), a score ring, a non-negotiable status bar, and a greeting.

#### Reading Order

1. Greeting text ("Day 47. Don't break now." -- trait: `.isStaticText`)
2. Score Ring (composite element)
3. Body quadrant (grouped)
4. Fuel quadrant (grouped)
5. Mind quadrant (grouped)
6. Move quadrant (grouped)
7. Non-negotiable status bar (grouped)
8. Quick action buttons (if visible)

**Rationale:** The score ring is the most important piece of information on this screen. Quadrants are read left-to-right, top-to-bottom (Body top-left, Fuel top-right, Mind bottom-left, Move bottom-right). This matches the visual layout and gives a consistent spatial model to blind users.

#### Element Labels

**Score Ring:**
- Label: "Daily score"
- Value: "[score] out of 100"
- Hint: "Double-tap for score breakdown"
- Trait: `.isSummaryElement`
- Example announcement: "Daily score, 78 out of 100. 12 points higher than yesterday."
- Implementation: Combine the ring, the number, and the delta label into one `accessibilityElement` with a compound label.
- When score is nil (not yet calculable): "Daily score, not yet available. Complete more activities to generate a score."

**Body Quadrant (collapsed):**
- Accessibility container: YES, group child elements
- Label: "Body. Recovery [score] percent. [zone] zone."
- Value: "Heart rate variability [HRV] milliseconds. Resting heart rate [RHR] BPM. Sleep [hours] hours."
- Hint: "Double-tap to expand body details"
- Trait: `.isButton`, `.isHeader`
- Example: "Body. Recovery 78 percent. Green zone. Heart rate variability 68 milliseconds. Resting heart rate 52 BPM. Sleep 7.2 hours. Double-tap to expand body details."
- When Whoop disconnected: "Body. Whoop not connected. Double-tap to connect."
- When data stale: "Body. Recovery 78 percent. Green zone. Data from 4 hours ago."

**Fuel Quadrant (collapsed):**
- Label: "Fuel. [consumed] of [target] calories."
- Value: "Protein [g] grams. Carbs [g] grams. Fat [g] grams. [logged] of [planned] meals logged."
- Hint: "Double-tap to expand nutrition details"
- Trait: `.isButton`, `.isHeader`
- Example: "Fuel. 1,420 of 2,800 calories. Protein 95 grams. Carbs 160 grams. Fat 48 grams. 2 of 3 meals logged. Double-tap to expand nutrition details."
- When NutriTrack disconnected: "Fuel. NutriTrack not connected. Double-tap to connect."

**Mind Quadrant (collapsed):**
- Label: "Mind. [minutes] of [target] minutes studied."
- Value: "Current streak: [days] days. [Next exam info]."
- Hint: "Double-tap to expand study details"
- Trait: `.isButton`, `.isHeader`
- Example: "Mind. 90 of 120 minutes studied. Current streak: 12 days. Next exam: Calculus 2, in 6 days. Double-tap to expand study details."

**Move Quadrant (collapsed):**
- Label: "Move. Workout [status]."
- Value: "[steps] steps of [target]. Active calories [cal]."
- Hint: "Double-tap to expand training details"
- Trait: `.isButton`, `.isHeader`
- Example: "Move. Workout completed. Upper Body Push, 45 minutes. 8,420 steps of 10,000. Active calories 320. Double-tap to expand training details."
- When no workout planned: "Move. Rest day. 8,420 steps of 10,000. Active calories 320."

**Non-Negotiable Status Bar:**
- Label: "[completed] of [total] non-negotiables completed."
- Value: If locked: "PlayStation locked." If unlocked: "PlayStation unlocked. Earned at [time]."
- Hint: "Double-tap to view non-negotiable details"
- Trait: `.isButton`
- Example: "3 of 5 non-negotiables completed. PlayStation locked. Double-tap to view non-negotiable details."

#### Expanded Quadrant Views

When a quadrant is tapped and expands to show details, VoiceOver must:
1. Post a `.layoutChanged` notification with focus on the expanded content's first element.
2. Each metric within the expanded view is its own accessibility element.
3. Charts within expanded views follow the chart accessibility rules (Section 2.7).
4. A "Collapse" action is available as a custom accessibility action on the expanded quadrant header.

#### Custom Rotor Actions

Register the following custom rotor:
- **"Quadrants" rotor**: Allows flicking up/down to jump between the four quadrants directly.
- **"Quick Actions" rotor**: Jump to quick action buttons (Log Meal, Start Workout, Start Study).

#### Pull-to-Refresh

- On pull gesture: announce "Refreshing data"
- On completion: announce "Dashboard updated. [time]."
- On failure: announce "Refresh failed. Check your connection."

---

### 2.2 Training (RepForge)

#### 2.2.1 Today's Workout View

**Reading Order:**
1. Date label
2. Workout title (e.g., "Push Day")
3. Recovery badge bar (grouped)
4. Workout meta bar (grouped)
5. Exercise cards (sequential, top to bottom)
6. Add Exercise button
7. Start Workout button (pinned at bottom)

**Recovery Badge Bar (grouped as one element):**
- Label: "Recovery [score] percent. [zone] zone."
- Value: "[adjustment]. Last synced [time]."
- Hint: "Double-tap to view recovery details and override"
- Example: "Recovery 78 percent. Green zone. Full volume. Last synced 6:42 AM. Double-tap to view recovery details and override."
- Color-blind note: The zone is conveyed through both the icon shape (checkmark/warning/X) and the text label, never color alone.

**Workout Meta Bar (grouped):**
- Label: "Today's workout"
- Value: "Approximately [duration] minutes. [exercise count] exercises. [set count] sets."
- Trait: `.isStaticText`
- Example: "Today's workout. Approximately 52 minutes. 6 exercises. 24 sets."

**Exercise Card:**
- Each card is an accessibility container.
- Combined label for the card: "[number]. [exercise name]. [muscle group]. [sets] sets of [reps] at [weight] kilograms."
- Value: "Last session: [weight] kilograms, [reps] reps. [completed/not completed]."
- Hint: "Double-tap to view exercise options. Swipe up or down to adjust."
- Progressive overload indicator: If present, append to label: "Weight increased from last session."
- Example: "1. Bench Press. Chest. 4 sets of 8 at 85 kilograms. Last session: 82.5 kilograms, 8 reps, completed. Weight increased from last session. Double-tap to view exercise options."

**Superset Grouping:**
- The superset container is an accessibility element with label: "Superset [A/B], [count] exercises."
- Children are read in order within the group.
- Example: "Superset A, 2 exercises. 3A. Cable Fly. Chest. 3 sets of 12 at 15 kilograms..."

**Start Workout Button:**
- Label: "Start workout"
- Hint: "Double-tap to begin logging today's workout"
- Trait: `.isButton`, `.startsMediaSession`

**Rest Day View:**
- Score ring replaced with: "Rest day. Recovery [score] percent."
- Next workout info: "Next workout: [day], [type]."
- Mobility button: "Start a mobility flow, button."

#### 2.2.2 Active Workout View

This is the hardest screen for accessibility. The user is physically exercising, potentially sweating, with limited attention. VoiceOver must be efficient, non-verbose, and support rapid interaction.

**Design constraints for accessibility during exercise:**
- Labels are SHORT. No unnecessary words.
- Custom actions replace complex gestures.
- The rest timer announces periodically without requiring user interaction.
- One-handed operation is assumed.

**Reading Order (during a set):**
1. Current exercise name and number
2. Current set indicator (e.g., "Set 2 of 4")
3. Target weight and reps
4. Weight input stepper
5. Reps input stepper
6. RPE selector (optional)
7. Complete Set button
8. Rest timer (when active)
9. Exercise navigation (previous/next)

**Current Exercise Header:**
- Label: "[exercise name]. Set [current] of [total]."
- Value: "Target: [reps] reps at [weight] kilograms."
- Trait: `.isHeader`
- Example: "Bench Press. Set 2 of 4. Target: 8 reps at 85 kilograms."

**Weight Input Stepper:**
- Label: "Weight"
- Value: "[current] kilograms"
- Hint: "Swipe up to increase by 2.5 kilograms. Swipe down to decrease."
- Trait: `.adjustable`
- On increment: announce "[new value] kilograms"
- On decrement: announce "[new value] kilograms"
- Custom action: "Set custom weight" -- opens a numeric input field

**Reps Input Stepper:**
- Label: "Reps"
- Value: "[current]"
- Hint: "Swipe up to increase. Swipe down to decrease."
- Trait: `.adjustable`
- On increment: announce "[new value]"
- On decrement: announce "[new value]"

**RPE Selector (when visible):**
- Label: "Rate of perceived exertion"
- Value: "[current] out of 10"
- Hint: "Swipe up to increase. Swipe down to decrease. 1 is easy, 10 is maximum effort."
- Trait: `.adjustable`

**Complete Set Button:**
- Label: "Complete set"
- Hint: "Double-tap to log this set and start rest timer"
- Trait: `.isButton`
- On activation: announce "Set [N] completed. [weight] kilograms, [reps] reps. Rest timer started."

**Rest Timer (when active):**
- Label: "Rest timer"
- Value: "[minutes] minutes, [seconds] seconds remaining"
- Trait: `.updatesFrequently`
- Announcement schedule:
  - On start: "Rest timer started. [duration] seconds."
  - At 30-second intervals (for timers over 60s): "[seconds] seconds remaining"
  - At 10 seconds: "10 seconds remaining"
  - At 0: "Rest complete. Next set ready." (plus haptic `.warning`)
- Custom actions:
  - "Skip timer" -- immediately ends rest and announces "Timer skipped. Ready for set [N]."
  - "Add 30 seconds" -- extends timer and announces "30 seconds added. [new total] remaining."

**Exercise Navigation:**
- Custom accessibility actions on the exercise header:
  - "Next exercise" -- navigates forward, announces "[exercise name]. Set 1 of [total]."
  - "Previous exercise" -- navigates back, announces "[exercise name]. Set [current] of [total]."
- Swipe gestures: Three-finger swipe left/right (standard VoiceOver page navigation) moves between exercises.

**Custom Rotor Actions for Active Workout:**
- "Complete Set" -- available as a rotor action from anywhere on the screen.
- "Skip Timer" -- available when rest timer is running.
- "Next Exercise" -- jumps to the next exercise.
- "Previous Exercise" -- jumps to the previous exercise.
- "End Workout" -- confirms and ends the workout session.

**Workout Timer (elapsed time):**
- Available in the navigation bar area.
- Label: "Workout duration"
- Value: "[hours] hours, [minutes] minutes" (announced only when focused, not continuously)
- Trait: `.updatesFrequently`

**PR Achievement (during workout):**
- When a personal record is achieved on completing a set:
  - Announcement: "Personal record. [exercise name]. [weight] kilograms for [reps] reps."
  - Haptic: double success tap
  - If Reduce Motion is on: no confetti, just the announcement and haptic

**Superset Handling in Active Workout:**
- Announce: "Superset. [Exercise A name] and [Exercise B name]. Alternate between exercises with no rest."
- After completing a round of both exercises: "Superset round [N] complete. Rest timer started."

#### 2.2.3 Workout Summary (Post-Workout)

**Reading Order:**
1. "Workout Complete" heading
2. Summary ring (total duration, total volume)
3. Exercise summary list (each exercise with sets completed, best set)
4. PR badges (if any)
5. XP earned
6. Done button

**Summary Ring:**
- Label: "Workout complete"
- Value: "[duration] minutes. [total sets] sets. [total volume] kilograms total volume."
- Example: "Workout complete. 48 minutes. 22 sets. 8,450 kilograms total volume."

**PR Badge:**
- Label: "Personal record: [exercise name]"
- Value: "[weight] kilograms for [reps] reps"
- Trait: `.isImage` (badge icon)

**XP Earned:**
- Label: "XP earned"
- Value: "Plus [amount] XP"
- Example: "XP earned. Plus 185 XP."

#### 2.2.4 Week Plan View

**Reading Order:**
1. Screen title ("Week Plan")
2. Days, Monday through Sunday, each as a grouped element

**Day Element:**
- Label: "[Day name]. [Workout type]."
- Value: "[status]." (Planned / Completed / Skipped / Rest Day)
- Hint: "Double-tap to view details"
- Example: "Monday. Push Day. Completed."

#### 2.2.5 Exercise Library View

- Search field: "Search exercises, text field."
- Filter buttons: "[Filter name], toggle button, [selected/not selected]"
- Each exercise row: "[Exercise name]. [Muscle group]. [Equipment]. Double-tap to view details."

#### 2.2.6 Progress Charts View

See Section 2.7 (Charts) for detailed chart accessibility handling.

---

### 2.3 Accountability (Lockdown)

#### 2.3.1 Lockdown Main View

**Reading Order:**
1. Screen title ("Lockdown")
2. Date label
3. Status banner (progress ring + lock status)
4. Non-negotiable cards (top to bottom)
5. Leisure status bar
6. Start Study Timer button

**Status Banner (grouped):**
- Label: "Daily progress, [percentage] percent."
- Value: "[Locked/Unlocked]. [context message]."
- Example: "Daily progress, 47 percent. Locked. 4 hours 32 minutes until your usual PlayStation time."
- When unlocked: "Daily progress, 100 percent. Unlocked. Earned at 18:42. Enjoy your evening."

**Non-Negotiable Card:**
- Each card is a single accessibility element.
- Label: "[Task name]. [tracking source]."
- Value: "[progress] of [target]. [percentage] percent. [status]."
- Hint: If manual task: "Double-tap to toggle completion." If auto-tracked: "Tracked automatically via [source]." If has action: "Double-tap to [action]."
- Example (study): "Study. Manual tracking. 1 hour 23 minutes of 2 hours. 69 percent. In progress. Double-tap to start study timer."
- Example (training, auto): "Training. Tracked automatically via Whoop. Completed. 45 minutes recorded."
- Example (meals): "Meals. Tracked via NutriTrack. 2 of 3. 67 percent. Next: Dinner before 8 PM."
- Example (custom, not started): "Read 30 minutes. Manual tracking. Not started. 0 percent. Double-tap to mark as in progress."

**Leisure Status Bar (grouped):**
- Label: "Leisure status"
- Value: If locked: "Locked. Complete [N] more to unlock." If unlocked: "Unlocked."
- Trait: `.isSummaryElement`

**Start Study Timer Button:**
- Label: "Start study timer"
- Trait: `.isButton`, `.startsMediaSession`
- Hint: "Double-tap to open the focus timer"

#### 2.3.2 Focus Timer View

**Critical accessibility concern:** The user is studying. VoiceOver announcements must not be distracting or frequent. The timer should be quiet by default, with the user controlling announcement frequency.

**Reading Order:**
1. Timer mode indicator (Focus / Break)
2. Timer display (minutes and seconds)
3. Session counter ("Session 3 of 4")
4. Control buttons (Start / Pause / Stop / Skip)
5. Session history (today's completed sessions)

**Timer Display:**
- Label: "Time remaining"
- Value: "[minutes] minutes, [seconds] seconds"
- Trait: `.updatesFrequently`
- Announcement schedule (configurable in Tempo accessibility settings, see Section 10):
  - **Default (every 5 minutes):** "25 minutes remaining." "20 minutes remaining." etc.
  - **Frequent (every 1 minute):** Announced every minute.
  - **Minimal (key milestones only):** Announced at halfway, 5 minutes remaining, and 1 minute remaining.
  - **Silent:** No periodic announcements. User checks manually by focusing the timer.
- At timer completion: "Focus session complete. [total minutes] minutes logged. [Break/Next session] starting."
- Implementation: Use a background timer that posts `.announcement` notifications at the configured interval. Do NOT update the accessibility value every second -- only when the user focuses the element.

**Session Counter:**
- Label: "Focus session [current] of [total]"
- Trait: `.isStaticText`
- Example: "Focus session 3 of 4"

**Control Buttons:**
- Start: "Start timer, button"
- Pause: "Pause timer, button"
- Resume: "Resume timer, button" (replaces Pause when paused)
- Stop: "Stop timer, button. Double-tap to end current session."
- Skip: "Skip to [break/focus], button"

**Break Timer:**
- Same structure as focus timer.
- Label changes to "Break time remaining"
- At completion: "Break over. Focus session [N] ready."

**Audio Cues (alternative to visual timer):**
- A quiet tick sound can be enabled (configurable) to indicate the timer is running. One tick every 30 seconds. Disabled by default.
- At 1 minute remaining: a double-tick sound.
- At completion: a distinct completion chime (not a harsh alarm).
- These audio cues serve as a non-visual timer feedback mechanism.

#### 2.3.3 Streak Calendar View

- Calendar grid: Each day cell is an accessibility element.
- Label: "[Full date]. [status]."
- Value: "[score] points. [completed] of [total] non-negotiables."
- Example: "Monday, March 17. All non-negotiables completed. 92 points. 5 of 5 non-negotiables."
- Example (missed): "Tuesday, March 18. Incomplete. 54 points. 3 of 5 non-negotiables."
- Current streak: announced as a summary element at the top: "Current streak: [N] days."
- Heatmap colors: supplemented with text labels. Never rely on color alone. Each cell also shows a small icon: checkmark for complete, dash for partial, X for missed.

---

### 2.4 Recovery (RecoverIQ)

#### 2.4.1 Recovery Today View

**Reading Order:**
1. Screen title
2. Recovery score ring (primary element)
3. Recovery zone badge and label
4. Metric tiles (HRV, RHR, Sleep, Strain) -- 2x2 grid, left-to-right, top-to-bottom
5. Prescription cards (scrollable)
6. Trend section header and sparklines

**Recovery Score Ring:**
- Label: "Recovery score"
- Value: "[score] percent. [zone] zone."
- Hint: "Double-tap to view recovery trends"
- Trait: `.isSummaryElement`
- Delta announcement: "[up/down] [amount] from yesterday. [up/down] [amount] from your 7-day average."
- Example: "Recovery score. 78 percent. Green zone. Up 12 from yesterday. Up 5 from your 7-day average."
- When no data: "Recovery score. No data available. Connect Whoop to see your recovery."

**Metric Tiles (HRV, RHR, Sleep Hours, Sleep Performance, Strain, SpO2):**
Each tile is one accessibility element:
- Label: "[metric name]"
- Value: "[value] [unit]. [trend direction] [trend percentage] from 7-day average."
- Hint: "Double-tap to view [metric name] details"
- Example: "Heart rate variability. 68 milliseconds. Up 12 percent from 7-day average. Double-tap to view heart rate variability details."
- Sparkline within tile: NOT a separate element. Its trend is captured in the value text above.
- Color of trend indicator: supplemented with arrow direction text (up/down/stable).

**Prescription Cards:**
Each prescription is one accessibility element:
- Label: "[Prescription type]"
- Value: "[Recommendation text]"
- Hint: "Double-tap to see reasoning"
- Example: "Training recommendation. Full volume, push for personal records. Double-tap to see reasoning."
- Example: "Bedtime recommendation. Aim for 22:30. You have 2.5 hours of sleep debt. Double-tap to see reasoning."
- Example: "Caffeine cutoff. No caffeine after 14:00. Double-tap to see reasoning."

**Warning Cards (when present):**
- Label: "Recovery warning"
- Value: "[warning text]"
- Trait: `.isStaticText`
- Example: "Recovery warning. Heart rate variability has been dropping for 3 consecutive days."

#### 2.4.2 Sleep Detail View

**Reading Order:**
1. Back button and screen title
2. Sleep score summary
3. Sleep stage chart (with accessible summary)
4. Sleep metrics (Duration, Efficiency, Latency, Disturbances)
5. Sleep consistency data

**Sleep Stage Chart:**
- The stacked bar chart is NOT navigable point-by-point (too many segments).
- Instead, a single grouped element:
  - Label: "Sleep stages"
  - Value: "Awake [time]. Light sleep [time]. Deep sleep [time]. REM sleep [time]. Total [time]."
  - Hint: "Double-tap to hear detailed breakdown"
  - Custom action "Hear detailed breakdown": reads percentages and comparisons to ideal targets.
- A data table alternative is available via the rotor (see Section 2.7).

#### 2.4.3 Strain Detail View

- Same pattern as Recovery Today.
- Strain ring: "Strain. [value] out of 21. [descriptor: light/moderate/high/overreaching]."
- Heart rate zone chart: accessible summary with time in each zone.

#### 2.4.4 Recovery Trends View

- See Section 2.7 (Charts) for full chart accessibility.
- Period selector: "Time period. [7 days / 30 days / 90 days]. [Selected]."
- Summary above chart: "Recovery trend: [improving/declining/stable] over the last [period]. Average [value] percent."

---

### 2.5 Arena (ClutchTime)

#### 2.5.1 Arena Main View

**Reading Order:**
1. Screen title
2. XP summary (total XP, level, progress to next level)
3. Streak flame counter
4. Today's XP breakdown (collapsible)
5. Leaderboard preview (top 3)
6. Active challenges
7. Recent achievements

**XP Summary (grouped):**
- Label: "Your XP"
- Value: "[total] XP. Level [N], [title]. [amount] XP to level [N+1]."
- Trait: `.isSummaryElement`
- Example: "Your XP. 12,450 XP. Level 14, Warrior. 550 XP to level 15."

**Streak Counter:**
- Label: "Current streak"
- Value: "[N] days"
- Hint: "Double-tap to view streak details"
- Example: "Current streak. 23 days. Double-tap to view streak details."

**Today's XP Breakdown:**
- Label: "Today's XP"
- Value: "Plus [total] XP today"
- Hint: "Double-tap to expand"
- When expanded, each line item:
  - "[Source]. [amount] XP."
  - Example: "Complete workout. Plus 100 XP." / "Hit protein target. Plus 30 XP." / "Missed study target. Minus 30 XP."

#### 2.5.2 Leaderboard View

**Reading Order:**
1. Screen title
2. Time period selector
3. Your rank summary
4. Leaderboard list (ranked)

**Your Rank Summary:**
- Label: "Your rank"
- Value: "[ordinal] place with [amount] XP. [ahead/behind] [name] by [difference] XP."
- Trait: `.isSummaryElement`
- Example: "Your rank. 2nd place with 2,340 XP. Behind Marco by 170 XP."

**Leaderboard Row:**
- Each row is one accessibility element.
- Label: "[rank]. [display name]."
- Value: "[amount] XP. [level] [title]."
- Hint for your own row: "This is you."
- Example: "1st. Marco. 2,510 XP. Level 15, Elite." / "2nd. You. 2,340 XP. Level 14, Warrior. This is you."

**Time Period Selector:**
- "Time period. [This Week / This Month / All Time]. Button."
- Announce selection: "[Period] selected. Loading leaderboard."

#### 2.5.3 Challenges View

**Active Challenge Card:**
- Label: "[Challenge name]. [time remaining]."
- Value: "Your score: [score]. [Opponent/Leader]: [name] with [score]. [Metric]."
- Hint: "Double-tap to view challenge details"
- Example: "Study Hours Battle. 3 days remaining. Your score: 14 hours. Marco: 12 hours. Study minutes tracked. Double-tap to view challenge details."

**Available Challenge:**
- Label: "[Challenge name]. [description]."
- Hint: "Double-tap to join"

#### 2.5.4 Achievements View

**Achievement Badge:**
- Label: "[Badge name]"
- Value: "[Description]. Earned [date]."
- Trait: `.isImage`
- Example: "Iron Streak. Completed 30 consecutive days of non-negotiables. Earned March 15."

**Locked Achievement:**
- Label: "[Badge name]. Locked."
- Value: "[Requirement to unlock]."
- Example: "Century Club. Locked. Log 100 workouts to unlock."

#### 2.5.5 Social Feed

- Each feed item: "[Friend name] [action]. [time ago]."
- Example: "Marco completed a Push Day workout. 2 hours ago."
- Trait: `.isStaticText`

---

### 2.6 Onboarding

#### Reading Order per Step

Each onboarding step follows the same pattern:
1. Progress indicator: "Step [N] of 12"
2. Illustration/animation: described with label (e.g., "Four rings merging into one unified ring")
3. Headline text
4. Body text
5. Primary CTA button
6. Secondary action (Skip/Back) if present

**Step 1 (Welcome):**
- Animation label: "Four activity rings merging into one unified ring"
- Headline: Read as `.isHeader`
- CTA: "Get Started, button"

**Step 2 (Sign in with Apple):**
- Apple sign-in button is a system component with built-in accessibility.
- Privacy notice: read as `.isStaticText`

**Permission Request Steps (HealthKit, Notifications, Calendar):**
- Each permission shows what data will be used and why.
- The system permission dialog has its own built-in VoiceOver support.
- After permission granted/denied: announce the result and move focus to the Continue button.

**Whoop/NutriTrack Connection Steps:**
- "Connect [service], button"
- "Skip for now, button"
- After successful connection: announce "[Service] connected successfully."

**Goal Setup Steps:**
- Each goal input uses `.adjustable` trait for steppers.
- Example: "Daily study target. 2 hours. Swipe up to increase by 30 minutes. Swipe down to decrease."

---

### 2.7 Charts (Global Specification)

Charts are inherently visual. Tempo must provide full non-visual access to chart data through multiple complementary approaches.

#### Approach 1: Accessibility Summary

Every chart has a single summary element positioned before the chart:
- Label: "[Chart title]"
- Value: "[Summary sentence]."
- Example: "Recovery trend, last 7 days. Improving. Average 72 percent. Highest: 92 percent on Monday. Lowest: 54 percent on Thursday."
- Example: "Weight progression, Bench Press, last 12 weeks. Increasing. Started at 70 kilograms. Current: 85 kilograms. All-time best: 85 kilograms."

#### Approach 2: Data Table Alternative

Available via a custom VoiceOver rotor action "Show Data Table":
- Transforms the chart into an accessible table format.
- Columns: Date/Time, Value, Delta from previous.
- Rows correspond to data points.
- Each cell: "[date]. [value] [unit]. [up/down/no change] [amount] from previous."

#### Approach 3: Audio Graph (AccessibilityChartDescriptor)

Implement `AXChartDescriptor` for all Swift Charts:
- Provides sonification: pitch maps to value (higher pitch = higher value).
- Users can scrub through data points with VoiceOver gestures.
- Each data point announces: "[date]. [value] [unit]."
- Axis descriptions: "X axis: [description]. Y axis: [description]."

Implementation:
```
// Required for every Chart view
.accessibilityChartDescriptor(self)
```

Where the view conforms to `AXChartDescriptorRepresentable` and provides:
- `accessibilityChartDescriptor`: The chart descriptor with series, data points, X and Y axis descriptions.

#### Approach 4: Key Data Point Narration

For trend charts, announce:
- Highest value and date
- Lowest value and date
- Start value and end value
- Trend direction (improving/declining/stable)
- Average value

#### Chart Types and Specific Handling

| Chart Type | Summary Format | Audio Graph | Data Table |
|------------|---------------|-------------|------------|
| Line chart (Recovery Trends) | "Trend: [direction]. Average: [value]." | Yes, pitch = recovery % | Yes |
| Bar chart (Sleep Stages) | "[Stage]: [duration], [percentage]." | Yes, pitch = duration | Yes |
| Ring/Arc (Score Ring) | "[value] out of [max], [percentage]" | No (single value) | No |
| Progress bar | "[value] of [target], [percentage]" | No (single value) | No |
| Heatmap (Streak Calendar) | Per-cell labels (see 2.3.3) | No | Yes (calendar grid) |
| Sparkline (Metric Tiles) | Embedded in tile label | No (too small) | No |
| Stacked bar (HR Zones) | Zone-by-zone breakdown in text | Yes, pitch = HR zone | Yes |
| Scatter plot (Correlations) | "Correlation: [strong/moderate/weak] [positive/negative]" | No | Yes |

---

### 2.8 Settings and Profile

**Settings List:**
- Each setting row: "[Setting name]. [Current value]."
- Toggle settings: "[Setting name], switch button, [on/off]."
- Navigation settings: "[Setting name]. Double-tap to open."
- Destructive settings (e.g., disconnect Whoop, delete account): Include trait `.isButton` and a confirmation alert before execution.

**Profile View:**
- Profile picture: "[User's display name], profile image."
- Stats: each as a separate element.
- Edit button: "Edit profile, button."

---

### 2.9 Drill Sergeant Alerts

In-app overlay alerts (when a non-negotiable deadline is approaching):
- VoiceOver reads the alert as a modal: focus trapped inside until dismissed.
- Label: "Accountability alert"
- Value: "[Message text]."
- Dismiss button: "Dismiss, button"
- Action button (if present): "[Action], button" (e.g., "Start studying")
- Example: "Accountability alert. 2 tasks incomplete. Evening approaching. Dismiss, button. Start studying, button."

---

### 2.10 Widgets (Lock Screen and Home Screen)

All widgets must set:
- `accessibilityLabel` on the widget view
- Combined summary text (not individual sub-elements for small widgets)

**Small Widget (Score):**
- "Tempo. Daily score [value] out of 100. [N] of [total] non-negotiables done."

**Medium Widget (Dashboard Summary):**
- "Tempo. Score [value]. Recovery [value] percent. [calories] calories. [study minutes] minutes studied. [workout status]."

**Large Widget (Non-Negotiables):**
- "Tempo. [completed] of [total] non-negotiables. [list each with status]."

---

## 3. Dynamic Type

### 3.1 Compliance Requirement

Every text element in Tempo MUST scale with the system Dynamic Type setting. The app must be fully usable at every size from xSmall through AX5 (Accessibility Extra Extra Extra Large).

### 3.2 Font Size Scaling Table

All sizes in points. SF Pro system fonts scale automatically when using `UIFontMetrics` or SwiftUI's `.font(.system(...))` with `TextStyle`.

| Tempo Style | Text Style Mapping | Default (Large) | xSmall | AX1 | AX3 | AX5 | Capped? |
|---|---|---|---|---|---|---|---|
| Score Display | `.largeTitle` | 64pt | 51pt | 77pt | 82pt | 83pt | Yes, max 1.3x (83pt) |
| Score Display Small | `.largeTitle` | 48pt | 38pt | 58pt | 62pt | 62pt | Yes, max 1.3x (62pt) |
| XP Display | `.title1` | 36pt | 29pt | 43pt | 47pt | 47pt | Yes, max 1.3x (47pt) |
| Timer Display | `.largeTitle` | 56pt | 45pt | 67pt | 67pt | 67pt | Yes, max 1.2x (67pt) |
| Timer Display Small | `.title1` | 40pt | 32pt | 48pt | 52pt | 52pt | Yes, max 1.3x (52pt) |
| Large Title | `.largeTitle` | 34pt | 27pt | 44pt | 53pt | 58pt | No |
| Title 1 | `.title1` | 28pt | 22pt | 36pt | 43pt | 48pt | No |
| Title 2 | `.title2` | 22pt | 18pt | 29pt | 34pt | 38pt | No |
| Title 3 | `.title3` | 20pt | 16pt | 26pt | 31pt | 34pt | No |
| Headline | `.headline` | 17pt | 14pt | 23pt | 27pt | 31pt | No |
| Body | `.body` | 17pt | 14pt | 23pt | 27pt | 31pt | No |
| Body Bold | `.body` | 17pt | 14pt | 23pt | 27pt | 31pt | No |
| Callout | `.callout` | 16pt | 13pt | 22pt | 26pt | 29pt | No |
| Subheadline | `.subheadline` | 15pt | 12pt | 21pt | 24pt | 27pt | No |
| Footnote | `.footnote` | 13pt | 11pt | 19pt | 21pt | 24pt | No |
| Caption 1 | `.caption1` | 12pt | 10pt | 18pt | 20pt | 22pt | No |
| Caption 2 | `.caption2` | 11pt | 9pt | 17pt | 19pt | 21pt | No |
| Data Large | `.title2` | 24pt | 19pt | 31pt | 31pt | 31pt | Yes, max 1.3x (31pt) |
| Data Medium | `.body` | 17pt | 14pt | 23pt | 27pt | 31pt | No |
| Data Small | `.footnote` | 13pt | 11pt | 19pt | 21pt | 24pt | No |

**Cap justification:** Score Display, Timer Display, XP Display, and Data Large are capped because they appear in spatially constrained containers (rings, timer circles, inline metrics). Allowing them to scale fully would break the layout of rings and progress indicators. At maximum cap, the ring diameter itself also scales up (see layout adaptations below).

### 3.3 Layout Adaptations by Dynamic Type Category

#### At Large (Default)
- Standard 2x2 quadrant grid on Dashboard.
- Exercise cards at standard height.
- Timer centered in circle.
- Leaderboard rows at 56pt height.
- Score ring at default 200pt diameter.

#### At Extra Large / XXL
- Minor padding adjustments (card padding increases from 16pt to 20pt).
- Metric tile labels may wrap to two lines.
- Leaderboard rows expand to 64pt height.

#### At AX1 -- AX3 (Accessibility sizes)
- **Dashboard quadrants stack vertically** (1-column layout instead of 2x2 grid). Order: Body, Fuel, Mind, Move. Each quadrant takes full width.
- **Score ring scales to 240pt diameter** (from 200pt) to accommodate larger text inside.
- **Exercise cards** expand vertically. Prescription and last-performance info stack vertically instead of inline.
- **Leaderboard rows** expand to 80pt minimum height. Rank and name stack above XP and level.
- **Metric tiles** become full-width, stacking vertically instead of 2x2.
- **Timer display** scales, but the timer circle also enlarges to 240pt.
- **Non-negotiable cards** expand. Progress bar and text stack vertically.
- **Navigation and tab bar** use system-provided scaling.

#### At AX4 -- AX5 (Largest accessibility sizes)
- **Dashboard quadrants are individually scrollable cards.** The main dashboard becomes a single scrollable column of full-width cards.
- **Score ring scales to 280pt diameter.** Score number may use 2 lines if needed (unlikely at cap).
- **All text is scrollable.** No text is clipped or truncated -- content that overflows is scrollable.
- **Exercise cards** become significantly taller. Each piece of information (name, prescription, history, actions) is on its own line.
- **Button heights increase to 60pt** minimum for easier tapping at these sizes.
- **Tab bar labels** scale with system (iOS handles this).
- **Charts** reduce to show fewer data points (7 instead of 30) to avoid overcrowding at large label sizes.
- **Streak calendar** switches from a month grid to a scrollable list of days (the grid becomes unreadable at AX5).

### 3.4 Text Truncation Strategy

| Element | Strategy | Justification |
|---------|----------|---------------|
| Screen titles | Never truncate | Always fully visible; scrollable if needed |
| Exercise names | Truncate with ellipsis after 2 lines | Names like "Single-Arm Dumbbell Incline Bench Press" could be long |
| Metric values | Never truncate | Numbers must always be fully visible |
| Metric labels | Truncate after 1 line | Brief labels; full label in VoiceOver |
| Notification text | Expand vertically | Drill sergeant messages must be fully readable |
| Leaderboard names | Truncate after 1 line with ellipsis | Display names can vary in length |
| Challenge descriptions | Expand vertically up to 4 lines, then truncate | |
| Button labels | Never truncate; reduce padding if needed | Button text must be fully readable |

### 3.5 Implementation Rules

1. **Always use `UIFontMetrics`** (UIKit) or `.font(.system(size:weight:design:).leading(.tight))` with `@ScaledMetric` (SwiftUI) for custom-sized text.
2. **Never use a fixed font size** without wrapping it in `UIFontMetrics.default.scaledValue(for:)`.
3. **Use `@ScaledMetric` for non-text dimensions** that should scale with Dynamic Type (icon sizes, minimum heights, ring diameters).
4. **Test at every size.** Use Xcode's Environment Overrides or the Accessibility Inspector to test xSmall, Large, AX1, AX3, and AX5 at minimum.
5. **Use `.minimumScaleFactor()` sparingly and only as a last resort.** Prefer layout adaptation over text shrinking.
6. **ScrollView everywhere.** Every screen that could overflow at AX5 must be in a ScrollView.
7. **Line limits.** Never set `.lineLimit(1)` on text that conveys essential information. Use `.lineLimit(nil)` or a reasonable limit (2-3) with truncation.

---

## 4. Color and Visual Accessibility

### 4.1 Color Contrast Ratios (WCAG 2.2 AA)

All text/background combinations verified. Minimum: 4.5:1 for normal text (<18pt or <14pt bold), 3:1 for large text (>=18pt or >=14pt bold).

#### Light Mode

| Text Token | Background Token | Contrast Ratio | WCAG Level | Pass? |
|---|---|---|---|---|
| Ink Black (#0D0D0D) | Bone White (#F5F2ED) | 17.4:1 | AAA | Yes |
| Secondary Text (#4B5563) | Bone White (#F5F2ED) | 7.2:1 | AAA | Yes |
| Tertiary Text (#6B7280) | Bone White (#F5F2ED) | 4.8:1 | AA | Yes |
| Disabled Text (#9CA3AF) | Bone White (#F5F2ED) | 3.1:1 | -- | Exempt (disabled state) |
| Signal Red (#E63946) | Bone White (#F5F2ED) | 4.6:1 | AA (large text) | Yes (use only >=18pt) |
| Signal Red (#E63946) | White Card (#FFFFFF) | 4.5:1 | AA (large text) | Yes (use only >=18pt) |
| Electric Blue (#3B82F6) | Bone White (#F5F2ED) | 4.5:1 | AA | Yes |
| Mission Green (#22C55E) | Bone White (#F5F2ED) | 2.5:1 | -- | FAIL for text. Use with icon+text only, never as standalone text on light backgrounds. |
| Command Amber (#F59E0B) | Bone White (#F5F2ED) | 2.1:1 | -- | FAIL for text. Use on dark backgrounds only, or pair with icon/text in Ink Black. |
| Fail Red (#DC2626) | Bone White (#F5F2ED) | 5.3:1 | AA | Yes |
| Ink Black (#0D0D0D) | White Card (#FFFFFF) | 19.3:1 | AAA | Yes |

**Remediation for failing combinations:**
- Mission Green on light backgrounds: use Ink Black text alongside a green icon/badge. Never use green text on Bone White.
- Command Amber on light backgrounds: use Ink Black text alongside an amber icon/badge. Amber text is permitted only on Ink Black backgrounds (8.2:1).

#### Dark Mode

| Text Token | Background Token | Contrast Ratio | WCAG Level | Pass? |
|---|---|---|---|---|
| Bone White (#F5F2ED) | True Black (#0D0D0D) | 17.4:1 | AAA | Yes |
| Secondary Text Dark (#A1A1AA) | Card Dark (#1C1C1E) | 6.1:1 | AA | Yes |
| Tertiary Text Dark (#71717A) | Card Dark (#1C1C1E) | 3.9:1 | AA (large text) | Yes (use only >=18pt) |
| Signal Red Dark (#FF4D5A) | Card Dark (#1C1C1E) | 4.6:1 | AA | Yes |
| Electric Blue Dark (#60A5FA) | Card Dark (#1C1C1E) | 4.8:1 | AA | Yes |
| Mission Green Dark (#4ADE80) | Card Dark (#1C1C1E) | 7.1:1 | AA | Yes |
| Command Amber Dark (#FBBF24) | Card Dark (#1C1C1E) | 9.4:1 | AAA | Yes |
| Fail Red Dark (#F87171) | Card Dark (#1C1C1E) | 5.2:1 | AA | Yes |
| Protocol Violet Dark (#A78BFA) | Card Dark (#1C1C1E) | 4.6:1 | AA | Yes |

### 4.2 Color Blind Support

No information may be conveyed by color alone. Every use of color as a semantic indicator must be accompanied by at least one additional differentiator: icon shape, text label, or pattern.

#### Recovery Zone Indicators

| Zone | Color | Shape/Icon | Text Label | Pattern (charts) |
|------|-------|-----------|------------|-----------------|
| Green (67-100%) | Green (#22C55E / #4ADE80) | Checkmark circle (`checkmark.circle.fill`) | "Green zone" or "Full recovery" | Solid fill |
| Yellow (34-66%) | Yellow (#EAB308 / #FACC15) | Warning triangle (`exclamationmark.triangle.fill`) | "Yellow zone" or "Moderate recovery" | Diagonal stripes |
| Red (0-33%) | Red (#DC2626 / #F87171) | X circle (`xmark.circle.fill`) | "Red zone" or "Low recovery" | Cross-hatch |

#### Streak Calendar

| Status | Color | Icon | Text |
|--------|-------|------|------|
| Complete | Green fill | Checkmark | "Done" |
| Partial | Amber fill | Dash/tilde | "[N]/[total]" |
| Missed | Red fill | X mark | "Missed" |
| Future | Gray fill | Dot | "[date]" |
| Today | Outlined/active | Ring | "Today" |

#### Leaderboard Positions

| Position | Color | Additional Indicator |
|----------|-------|---------------------|
| 1st place | Gold (#FFD700) | Crown icon + "1st" text |
| 2nd place | Silver (#C0C0C0) | "2nd" text |
| 3rd place | Bronze (#CD7F32) | "3rd" text |
| Your position | Electric Blue highlight | "You" badge |
| Others | No special color | Rank number only |

#### Chart Lines

When multiple data series appear on the same chart:
- Use different line styles: solid, dashed, dotted.
- Use different point markers: circle, square, triangle, diamond.
- Color is supplementary, not primary differentiator.
- Legend includes both color swatch AND line/marker preview.

#### Color Blind Simulation Verification

Before each release, verify all screens under three simulations:

| Type | Prevalence | Test Tool | Key Risk Areas |
|------|-----------|-----------|----------------|
| **Protanopia** (no red) | ~1% males | Xcode Accessibility Inspector > Color Filters | Recovery red/green distinction, error states, streak calendar |
| **Deuteranopia** (no green) | ~6% males | Same | Recovery green vs yellow, success vs warning states |
| **Tritanopia** (no blue) | ~0.01% | Same | Electric Blue vs Protocol Violet, study module accents |

All three simulations must confirm that every piece of semantic information remains distinguishable. The icon+text+pattern approach above ensures this.

### 4.3 Increase Contrast Mode

When the user enables Settings > Accessibility > Display & Text Size > Increase Contrast:

| Element | Default | Increased Contrast |
|---------|---------|-------------------|
| Card backgrounds (light mode) | `#FFFFFF` | `#FFFFFF` with 1pt `#C0C0C0` border |
| Card backgrounds (dark mode) | `#1C1C1E` | `#000000` with 1pt `#3A3A3E` border |
| Dividers | `#E5E7EB` / `#38383A` | `#C0C0C0` / `#5A5A5A` (stronger) |
| Overlay scrim | 40% / 50% opacity | 60% / 70% opacity |
| Button backgrounds | Standard | Slightly darker/lighter for more contrast with text |
| Thin separators | 0.5pt hairline | 1pt solid line |
| Score ring track | 12% opacity tint | 20% opacity tint |
| Skeleton shimmer | Subtle gradient | Stronger gradient with higher contrast |

Implementation: Use `@Environment(\.colorSchemeContrast)` to detect `.increased` and swap to higher-contrast variants.

### 4.4 Reduce Transparency Mode

When the user enables Settings > Accessibility > Display & Text Size > Reduce Transparency:

| Element | Default | Reduced Transparency |
|---------|---------|---------------------|
| Navigation bar | `.ultraThinMaterial` blur | Solid `tempo/bg/primary` color |
| Tab bar | System blur material | Solid `tempo/bg/primary` color |
| Bottom sheet handle bar | Semi-transparent | Solid background |
| Floating bottom buttons | `.ultraThinMaterial` backdrop | Solid `tempo/bg/primary` |
| Overlay scrim | Semi-transparent black | Solid dark background (fully opaque) |
| Status banner backgrounds | Semi-transparent tint | Solid tint color at full opacity |
| Card glassmorphism effects (if any) | Blur + transparency | Solid color |

Implementation: Use `@Environment(\.accessibilityReduceTransparency)` to detect and swap materials for solid colors.

### 4.5 Differentiate Without Color

WCAG 1.4.1: Color is not used as the only visual means of conveying information.

Complete audit of color-only indicators and their non-color supplements:

| Indicator | Color Used | Non-Color Supplement |
|-----------|-----------|---------------------|
| Recovery zone (green/yellow/red) | Zone color | Icon shape + text label ("Green zone") |
| Non-negotiable completion | Green checkmark / Red incomplete | Checkmark/X icon + text ("Done"/"Not started") |
| Progress bar fill | Color changes with progress | Percentage text label always visible |
| Streak calendar day status | Color fill | Icon (check/dash/X) + accessible label |
| Leaderboard rank | Gold/Silver/Bronze | Rank number + text label |
| XP gain/loss | Blue (positive) / Red (negative) | Plus/minus prefix in text (+100 / -50) |
| Chart trend direction | Green (up) / Red (down) | Arrow icon (up/down) + text label |
| Error states | Red border | Error icon + error message text |
| PR indicator | Gold badge | Text "PR" + star icon |
| Training adjustment | Recovery color | Text label ("Full Volume" / "-20% Volume") |
| Timer states (running/paused) | Color change | Button label change (Start/Pause/Resume) + icon change |
| Superset grouping | Color-coded brackets | Labeled bracket ("Superset A") + numbered sub-items (3A, 3B) |
| Sleep stages | Distinct colors per stage | Text labels in legend + pattern fills in chart bars |
| Heart rate zones | Gradient colors | Zone numbers (1-6) + text labels |
| Connection status | Green/Red dot | Text label ("Connected"/"Disconnected") + icon |

---

## 5. Motor Accessibility

### 5.1 Touch Targets

**Minimum touch target: 44x44 points** (Apple HIG requirement).

During Active Workout: **56x56 points minimum** (sweat, fatigue, reduced dexterity).

#### Element Touch Target Audit

| Element | Default Size | Touch Target | Compliant? | Action Required |
|---------|-------------|-------------|------------|----------------|
| Tab bar icons | 25x25pt visual | 44x44pt (system) | Yes | None |
| Navigation back button | 17x17pt visual | 44x44pt (system) | Yes | None |
| Nav bar action buttons | 22x22pt visual | 44x44pt (padding) | Yes | Ensure hit area padding |
| Exercise card demo button | 17x17pt visual | 44x44pt | Yes | Use `.contentShape(Rectangle())` with 44pt frame |
| Exercise card more button | 17x17pt visual | 44x44pt | Yes | Same |
| Weight stepper buttons | 44x44pt | 56x56pt (workout) | Yes | Enlarge in active workout |
| Rep counter buttons | 44x44pt | 56x56pt (workout) | Yes | Enlarge in active workout |
| Complete Set button | 56pt height, full width | 56pt height | Yes | None |
| Start Workout button | 56pt height, full width | 56pt height | Yes | None |
| Start Timer button | 56pt height, full width | 56pt height | Yes | None |
| Timer Pause/Resume | 44x44pt | 44x44pt | Yes | None |
| Streak calendar day cell | Variable | Min 44x44pt | Verify | May need enlargement at small screen widths |
| Non-negotiable checkbox | 28x28pt visual | 44x44pt (hit area) | Yes | Padding extends hit area |
| Settings toggle | 51x31pt (system) | System default | Yes | None |
| Search field clear button | 14x14pt visual | 44x44pt (system) | Yes | None |
| Leaderboard row tap | Full width, variable height | Min 56pt height | Yes | None |
| Achievement badge tap | Variable | Min 44x44pt | Verify | Ensure badges are not too small |
| Filter chips | Variable width, 32pt height | Min 44pt height, min 44pt width | Adjust | Increase height to 44pt or add padding |
| Date picker cells | Variable | Min 44x44pt | Verify | System date picker handles this |
| Chart data points | 8-12pt visual | Min 44x44pt tap area | Adjust | Use invisible overlay touch areas |
| Onboarding CTA buttons | 56pt height | 56pt height | Yes | None |

### 5.2 Switch Control

Switch Control scans through interactive elements on screen. Tempo must define logical scan groups to prevent the scanning from taking dozens of steps to reach key actions.

**Scan Group Definitions:**

| Screen | Groups |
|--------|--------|
| Dashboard | [Score Ring] > [Body Quadrant] > [Fuel Quadrant] > [Mind Quadrant] > [Move Quadrant] > [Non-Negotiable Bar] > [Tab Bar] |
| Today's Workout | [Recovery Badge] > [Exercise 1] > [Exercise 2] > ... > [Start Workout] > [Tab Bar] |
| Active Workout | [Exercise Header] > [Weight Stepper] > [Reps Stepper] > [Complete Set] > [Timer Controls] |
| Focus Timer | [Timer Display] > [Control Buttons] > [Session Info] |
| Lockdown | [Status Banner] > [Task 1] > [Task 2] > ... > [Leisure Bar] > [Start Timer] > [Tab Bar] |
| Recovery Today | [Score Ring] > [Metrics Grid] > [Prescriptions] > [Tab Bar] |
| Arena Main | [XP Summary] > [Streak] > [Today XP] > [Leaderboard Preview] > [Tab Bar] |
| Leaderboard | [Period Selector] > [Your Rank] > [Leaderboard List] |

Implementation: Use `accessibilityNavigationStyle = .combined` on grouped containers and set proper `shouldGroupAccessibilityChildren = true`.

### 5.3 Voice Control

Every interactive element must have a visible label or accessibility label that matches what a Voice Control user would say.

**Voice Control naming rules:**
- Buttons: The button label IS the voice command. "Start Workout" is activated by saying "Tap Start Workout."
- If a button has only an icon (no visible text), set `accessibilityLabel` so Voice Control can show the name overlay. Examples:
  - Gear icon: `accessibilityLabel = "Settings"`
  - Calendar icon: `accessibilityLabel = "Week plan"`
  - Back chevron: `accessibilityLabel = "Back"`
  - Play icon on exercise: `accessibilityLabel = "Exercise demo"`
  - Ellipsis icon: `accessibilityLabel = "More options"`
- Tab bar items have visible labels; they already work.
- For identical labels on screen (e.g., multiple "More options" buttons), Voice Control will show numbers to disambiguate. This is acceptable but minimize it where possible by using more specific labels.

**Voice Control grid:** For complex screens (dashboard, charts), Voice Control's "Show Grid" command overlays a numbered grid. Ensure all tappable areas are reachable within the grid.

### 5.4 AssistiveTouch Compliance

No function in Tempo requires multi-finger gestures as the ONLY input method.

| Gesture | Used Where | Single-Touch Alternative |
|---------|-----------|------------------------|
| Two-finger pinch-to-zoom | Charts | Zoom buttons (+/-) overlaid on chart, or use AccessibilityZoom |
| Swipe to dismiss sheet | Bottom sheets, modals | Close/Done button always present |
| Three-finger swipe | VoiceOver page navigation | Standard VoiceOver controls |
| Long press | Context menus on exercise cards | "More options" button visible |
| Pull-to-refresh | All scrollable screens | Refresh button in navigation bar |
| Shake to undo | Not used in Tempo | N/A |

### 5.5 One-Handed Use

Critical for workout scenarios (one hand holding a barbell grip, one hand using phone).

**One-handed design rules:**
- All primary actions on the Active Workout screen are reachable in the bottom 60% of the screen.
- The Complete Set button is at the bottom, within thumb reach.
- Weight/rep steppers are in the center-to-bottom area.
- No critical actions in the top-left corner (hardest to reach one-handed on large phones).
- If a confirmation dialog appears during workout, the primary action ("Confirm") is always the bottom button.

**Reachability assessment (iPhone 15 Pro Max, right-handed):**

| Screen Area | Reachability | Tempo's Approach |
|-------------|-------------|-----------------|
| Bottom center | Easy reach | Primary CTA buttons, Complete Set, timer controls |
| Bottom corners | Comfortable | Tab bar items, secondary actions |
| Middle center | Comfortable | Weight/rep inputs, exercise info |
| Top center | Stretch | Screen titles, date (non-interactive, informational) |
| Top corners | Difficult | Navigation buttons (Back, Settings) -- non-critical during workout |

### 5.6 Dwell Control

Dwell Control (hover-to-tap) support:
- All interactive elements have a defined hit area (no ambiguous tap zones).
- No element requires a precise tap -- all use generous hit areas (44pt minimum).
- Hover states (if using iPad pointer) provide visual feedback.
- No drag-and-drop interactions are the ONLY way to perform an action. Drag-to-reorder exercises has a "Move" button alternative in the context menu.

### 5.7 External Keyboard Support

Full Keyboard Access (Settings > Accessibility > Keyboards > Full Keyboard Access):

| Key | Action |
|-----|--------|
| Tab | Move focus to next interactive element |
| Shift+Tab | Move focus to previous element |
| Enter/Space | Activate focused element (tap) |
| Arrow keys | Navigate within groups (stepper values, tab bar, segmented controls) |
| Escape | Dismiss sheet/modal, go back |
| Cmd+1 through Cmd+5 | Switch tabs (Dashboard, Training, Lockdown, Recovery, Arena) |

**Focus ring:** All focused elements show a visible focus ring (system default blue ring, 3pt offset). On Tempo's dark backgrounds, the focus ring is white/light for visibility.

---

## 6. Reduce Motion

When Settings > Accessibility > Motion > Reduce Motion is enabled, all animations are replaced with static alternatives or simple cross-fades.

### 6.1 Complete Animation Replacement Table

| Animation | Default Behavior | Reduce Motion Alternative |
|-----------|-----------------|--------------------------|
| **Score Ring draw** | Arc animates from 0 to value over 1.0s with spring | Ring draws instantly at final value, no animation |
| **Score Ring on value change** | Animated arc transition, 0.8s spring | Instant value update, no arc animation |
| **XP counter increment** | Numbers count up from old to new value over 0.5s | Final value displayed instantly |
| **XP float animation** | "+100 XP" floats up and fades, 1.5s | "+100 XP" appears in place, then fades (opacity only, 0.3s) |
| **Card transitions (push/pop)** | Slide left/right, 0.35s spring | Cross-fade, 0.2s ease-in-out |
| **Tab switching** | Slide animation between tab content | Cross-fade, 0.2s |
| **Pull-to-refresh spinner** | Custom rotation animation | Static activity indicator (system UIActivityIndicatorView) |
| **Level-up celebration** | Particles, glow, scale animation, 2s | Static badge display with glow border, fade in 0.3s |
| **Achievement unlock** | Badge flies in from right, bounces, 0.8s | Badge fades in, 0.3s |
| **PR badge pop** | Scale 0 to 1.15 to 1.0, gold shimmer, 0.4s | Badge appears at scale 1.0, no shimmer |
| **Timer ring pulse** | Continuous pulsing border, 1s loop | Static ring border, no pulse. Use color change only. |
| **Timer ring countdown** | Continuous smooth arc decrease | Static arc, updated every 5 seconds (stepped, not animated) |
| **Chart draw-in** | Lines/bars draw from left to right, 0.5s | Chart appears fully drawn instantly |
| **Chart tooltip** | Slides in from data point, 0.2s | Appears instantly at position |
| **Leaderboard rank change** | Rows slide up/down to new positions, 0.3s | Rows update in place, no movement |
| **Streak flame animation** | Flame flickers continuously | Static flame icon, no animation |
| **Exercise card expand/collapse** | Height animates with spring, 0.35s | Instant height change (or cross-fade) |
| **Set row slide-in** | Completed set slides into history, 0.25s | Row appears in place |
| **Confetti burst (PR)** | Particle system, 2s | No confetti. Static "PR" badge only. |
| **Workout complete ring fill** | Arc fills to 100%, 0.8s | Ring appears at 100% instantly |
| **Onboarding splash animation** | Multi-step fade/scale sequence, 1.8s | Simple fade-in of final state, 0.5s |
| **Onboarding ring convergence** | Four rings merge into one, looping | Static single ring |
| **Lock/unlock animation** | Shackle lifts, rotation, scale pulse | Lock icon swaps instantly (no movement) |
| **Progress bar fill** | Animated fill, 0.3s spring | Instant fill to value |
| **Skeleton loading shimmer** | Gradient sweeps left to right, looping | Static gray placeholder (no shimmer) |
| **Bottom sheet presentation** | Slide up from bottom, 0.4s | Appears instantly (or 0.2s fade) |
| **Notification banner slide** | Slides down from top, 0.3s | Appears instantly |
| **Haptic feedback** | Unchanged | Haptics are NOT affected by Reduce Motion. They remain active. |
| **Audio cues** | Unchanged | Audio cues are NOT affected by Reduce Motion. |

### 6.2 Implementation

```swift
// Check in SwiftUI
@Environment(\.accessibilityReduceMotion) var reduceMotion

// Apply conditional animation
.animation(reduceMotion ? nil : .spring(response: 0.35), value: someState)

// For cross-fade alternative
.transition(reduceMotion ? .opacity : .slide)
```

### 6.3 Auto-Play Content

If any screens include auto-playing video content (e.g., exercise demos): when Reduce Motion is enabled, videos should NOT auto-play. Show a static thumbnail with a play button overlay instead.

---

## 7. Cognitive Accessibility

### 7.1 Information Density Management

| Screen | Information Elements | Risk Level | Simplification Strategy |
|--------|---------------------|------------|------------------------|
| Dashboard | 4 quadrants, score ring, non-negotiable bar, greeting, 12+ data points | HIGH | Default: summary mode (key number per quadrant). Tap to expand details. Tempo offers a "Simplified Dashboard" option (Section 10). |
| Active Workout | Exercise name, set info, weight/rep inputs, timer, exercise list | MEDIUM | Only the current exercise and current set are prominent. Everything else is dimmed or below the fold. |
| Recovery Today | Score ring, 4+ metric tiles, 3+ prescription cards, trend sparklines | HIGH | Prescription cards have one clear action sentence each. Details are behind "See reasoning" tap. |
| Arena Main | XP, level, streak, leaderboard preview, challenges, achievements | HIGH | Progressive disclosure: main view shows XP + level + rank. Everything else is below the fold or in sub-tabs. |
| Focus Timer | Timer, session count, controls | LOW | Intentionally minimal. One number (time), two buttons (pause/stop). |
| Lockdown | Non-negotiable list, progress bars, lock status | MEDIUM | Clear visual hierarchy: lock status at top, tasks in order, primary CTA at bottom. |

### 7.2 Consistent Navigation

| Pattern | Rule |
|---------|------|
| Tab bar | Always visible on all main screens. Never hidden (except during full-screen modals like Active Workout). |
| Back button | Always in the top-left corner. Always uses the system back chevron. |
| Primary CTA | Always at the bottom of the screen. Always full-width. Always the highest visual prominence button. |
| Pull-to-refresh | Available on every scrollable screen. Always the same gesture. |
| Sheets | Always dismissible by pulling down or tapping a close/done button. |
| Destructive actions | Always require confirmation. Always use red text. |
| Settings access | Always via a gear icon in the navigation bar. |

### 7.3 Error Recovery

| Error Type | Message Format | Recovery Action |
|------------|---------------|----------------|
| Network failure | "Could not reach the server. Check your connection." | Retry button + automatic retry after 30s |
| Whoop sync failure | "Whoop data could not be synced. Using last known data." | Retry button + manual sync option |
| NutriTrack connection lost | "NutriTrack connection lost. Reconnect in Settings." | Button navigates to Settings |
| Invalid input (weight/reps) | "Enter a number between [min] and [max]." | Input field highlighted, cursor placed, previous valid value shown |
| Workout data loss | "Your workout data was not saved. [N] sets recovered." | Auto-recovery from local cache + manual save option |
| Sign-in failure | "Sign in failed. Try again." | Retry button |
| Permission denied | "[Permission] is required for [feature]. Open Settings to enable." | Deep link to Settings app |

**Error message rules:**
- First sentence: What happened.
- Second sentence: What to do about it.
- No technical jargon (no "HTTP 500", no "timeout", no "nil response").
- No blame language ("You did something wrong"). Use passive or objective voice.

### 7.4 Reading Level

All user-facing text in Tempo must be at or below an **8th-grade reading level** (Flesch-Kincaid Grade Level <= 8).

| Text Category | Example (Good) | Example (Bad) |
|---|---|---|
| Notification | "3 tasks left today. You've got this." | "Three outstanding non-negotiable items remain for today's accountability cycle." |
| Error | "Could not load data. Try again." | "The application encountered a transient network error while attempting to fetch remote data." |
| Onboarding | "Tempo tracks your training, food, and study." | "Tempo provides a comprehensive integrated platform for multi-dimensional life tracking." |
| Recovery advice | "Take it easy today. Your body needs rest." | "Based on your biometric analysis, moderate intensity training is contraindicated." |

**Drill sergeant copy is exempt from reading-level tests** -- its direct, colloquial style is intentionally informal and already at a low reading level. "You skipped legs. Your quads noticed." is grade 4.

### 7.5 Predictable Behavior

| Gesture/Action | Always Does | Never Does |
|---|---|---|
| Single tap on card | Expands card or navigates to detail | Does not trigger destructive action |
| Swipe right from left edge | Goes back (system gesture) | Does not delete or dismiss |
| Long press on card | Opens context menu | Does not move/rearrange without explicit mode |
| Swipe left on list row | Shows delete/action options | Does not auto-delete (requires confirmation) |
| Double-tap (VoiceOver) | Activates the focused element | Same as single tap for sighted users |
| Pull down | Refresh data | Does not navigate or trigger modal |

### 7.6 Focus Management After Actions

| Action | Focus Behavior |
|--------|---------------|
| Complete a non-negotiable | Focus stays on the completed item. Announcement: "[Task name] completed." |
| Complete a set (workout) | Focus moves to "Complete Set" button for next set. Announcement: "Set [N] completed." |
| Complete all sets for an exercise | Focus moves to next exercise header. Announcement: "[Exercise name] complete. Next: [next exercise]." |
| Complete entire workout | Focus moves to Workout Summary screen title. |
| Timer expires (focus timer) | Focus moves to the session complete message. Audio chime plays. |
| Timer expires (rest timer) | Focus moves to the exercise/set info. Announcement: "Rest complete." |
| Dismiss a sheet | Focus returns to the element that opened the sheet. |
| Delete an item | Focus moves to the item above (or below if first item). |
| Error occurs | Focus moves to the error message. |
| Data refresh completes | Focus stays on current element. Announcement: "Data updated." |

---

## 8. Audio Accessibility

### 8.1 Closed Captions

If exercise demo videos are added in a future version:
- All videos MUST include closed captions (burned-in or `.vtt` sidecar).
- Captions must describe both spoken content and relevant sounds (e.g., "[metal clanking] Lower the bar slowly").
- Captioning language must match the user's app language setting.
- Caption styling: white text on semi-transparent black background, minimum 18pt, SF Pro Text.

### 8.2 Visual Alternatives for Sounds

| Sound Event | Visual Alternative |
|---|---|
| Timer completion chime | Screen flash (brief white overlay, 0.2s). Prominent "Time's up" banner. Haptic `.warning`. |
| Rest timer expiry | Visual pulse of the timer circle + "REST COMPLETE" text overlay. Haptic `.warning`. |
| PR achievement sound | Gold border flash on the PR badge. Haptic double-tap. |
| Workout complete sound | Full-screen "WORKOUT COMPLETE" banner. Haptic triple-tap. |
| Notification sound (drill sergeant) | Standard iOS notification banner + badge count. Red dot indicator on tab bar. |
| Level up sound | Level badge glow animation. Haptic `.success`. |
| Error sound | Red flash on the error source element. Haptic `.error`. |

**Rule:** Every sound event has BOTH a visual and a haptic alternative. A deaf user should never miss a notification or state change.

### 8.3 Hearing Aid Compatibility

- Test with Made for iPhone (MFi) hearing aids.
- All audio (timer sounds, notification sounds, achievement sounds) must route correctly through MFi hearing aids.
- No frequency-critical audio: do not rely on distinguishing between similar tones. Use distinct sounds (chime vs. beep vs. buzz) that differ in pattern and rhythm, not just pitch.
- Audio graph sonification (charts) must also route through hearing aids.

### 8.4 Mono Audio

- No information is conveyed through stereo panning.
- All audio in Tempo is mono-compatible. When the system Mono Audio setting is enabled, no information is lost.
- Implementation: All custom audio files should be mono or stereo-symmetric. Do not pan sounds left or right.

### 8.5 Audio Descriptions Toggle

If exercise demo animations (non-video) are used:
- An audio description mode can be enabled that narrates the movement: "Starting position: Stand with feet shoulder-width apart, barbell at chest height. Movement: Press the barbell overhead, extending arms fully."
- This is controlled via Tempo's in-app accessibility settings (Section 10).

---

## 9. Accessibility Testing Checklist

### 9.1 Pre-Release Checklist

Run these tests before EVERY release. Each test must pass on a physical device (not just Simulator).

#### VoiceOver Navigation Tests (35 test cases)

| # | Test | Screen | Expected Result | Pass? |
|---|------|--------|----------------|-------|
| 1 | Navigate all tabs via VoiceOver | Tab bar | Each tab announces name and position ("Dashboard, tab, 1 of 5") | |
| 2 | Read dashboard score ring | Dashboard | Announces score, delta, trend | |
| 3 | Read all 4 quadrants | Dashboard | Each announces summary data without tapping | |
| 4 | Expand and collapse quadrant | Dashboard | Focus moves to expanded content, custom action to collapse | |
| 5 | Read non-negotiable status | Dashboard | Announces completed count and lock status | |
| 6 | Navigate exercise list | Today's Workout | Each exercise reads name, sets, reps, weight, muscle group | |
| 7 | Read superset grouping | Today's Workout | Announces "Superset A, 2 exercises" before children | |
| 8 | Start workout via VoiceOver | Today's Workout | "Start workout" button activatable, transitions to active workout | |
| 9 | Adjust weight stepper | Active Workout | Swipe up/down changes value, new value announced | |
| 10 | Adjust reps stepper | Active Workout | Swipe up/down changes value, new value announced | |
| 11 | Complete a set | Active Workout | Announces completion, weight, reps, starts rest timer | |
| 12 | Rest timer announcement | Active Workout | Periodic time announcements at configured intervals | |
| 13 | Skip rest timer | Active Workout | Custom action works, announces "Timer skipped" | |
| 14 | Navigate between exercises | Active Workout | Custom actions "Next exercise" / "Previous exercise" work | |
| 15 | Read workout summary | Post-Workout | Duration, sets, volume, XP earned all read | |
| 16 | Read non-negotiable cards | Lockdown | Each card reads task, source, progress, status | |
| 17 | Toggle manual non-negotiable | Lockdown | Double-tap toggles, announces "[Task] completed" or "[Task] uncompleted" | |
| 18 | Start focus timer | Focus Timer | Timer starts, announces initial duration | |
| 19 | Pause and resume timer | Focus Timer | Button label changes, timer state announced | |
| 20 | Timer completion | Focus Timer | Announces session complete with total time | |
| 21 | Read recovery score | Recovery Today | Score, zone, delta from yesterday, 7-day average | |
| 22 | Read metric tiles | Recovery Today | Each tile reads value, unit, trend | |
| 23 | Read prescription cards | Recovery Today | Each reads recommendation and has "See reasoning" hint | |
| 24 | Navigate chart with audio graph | Recovery Trends | AXChartDescriptor allows scrubbing through data points | |
| 25 | Read chart summary | Recovery Trends | Summary announces trend, average, high, low | |
| 26 | Read XP summary | Arena | Total XP, level, title, progress to next level | |
| 27 | Read leaderboard | Leaderboard | Each row reads rank, name, XP. Your row says "This is you." | |
| 28 | Read challenge card | Challenges | Challenge name, time remaining, your score, opponent score | |
| 29 | Read achievement badge | Achievements | Badge name, description, earned date (or lock status) | |
| 30 | Navigate onboarding | Onboarding | All 12 steps navigable, all CTAs activatable | |
| 31 | Pull-to-refresh announcement | Any scrollable | "Refreshing" then "Data updated" or error message | |
| 32 | Sheet dismiss and focus return | Any sheet | Focus returns to triggering element after sheet dismissed | |
| 33 | Alert dismiss and focus return | Any alert | Focus returns to triggering element after alert dismissed | |
| 34 | Error state announcement | Network error | Error message read, retry action available | |
| 35 | Widget accessibility | Lock/Home screen | Widget reads combined summary label | |

#### Dynamic Type Tests (15 test cases)

| # | Test | Size | Expected Result | Pass? |
|---|------|------|----------------|-------|
| 1 | Dashboard layout at Large | Default | 2x2 quadrant grid, all text readable | |
| 2 | Dashboard layout at AX3 | AX3 | Quadrants stack vertically, score ring enlarged | |
| 3 | Dashboard layout at AX5 | AX5 | Single column, all text readable, nothing clipped | |
| 4 | Active Workout at AX3 | AX3 | All inputs reachable, timer readable | |
| 5 | Exercise card at AX5 | AX5 | All info visible, may need vertical scrolling | |
| 6 | Focus Timer at AX5 | AX5 | Timer numbers readable, controls reachable | |
| 7 | Leaderboard at AX3 | AX3 | Rows expand, all text visible | |
| 8 | Streak calendar at AX5 | AX5 | Switches to list view | |
| 9 | Score ring text at cap | AX5 | Text scales to cap (83pt), fits within enlarged ring | |
| 10 | Buttons at AX5 | AX5 | Labels never truncated, height increases to 60pt | |
| 11 | Charts at AX5 | AX5 | Axis labels readable, fewer data points shown | |
| 12 | Navigation bar at AX3 | AX3 | Title readable, buttons reachable | |
| 13 | Settings list at AX5 | AX5 | All rows expand, toggles reachable | |
| 14 | Onboarding at AX5 | AX5 | All text readable, CTAs reachable | |
| 15 | xSmall verification | xSmall | All text still readable (not too small) | |

#### Color Accessibility Tests (8 test cases)

| # | Test | Expected Result | Pass? |
|---|------|----------------|-------|
| 1 | Protanopia simulation -- Recovery zones | Zones distinguishable via icons and text | |
| 2 | Deuteranopia simulation -- Recovery zones | Zones distinguishable via icons and text | |
| 3 | Tritanopia simulation -- Blue/violet elements | Study vs. recovery accents distinguishable | |
| 4 | Increase Contrast mode | Cards have visible borders, dividers stronger | |
| 5 | Reduce Transparency mode | No blurred materials, all solid backgrounds | |
| 6 | All text contrast ratios (light mode) | All meet WCAG AA (4.5:1 normal, 3:1 large) | |
| 7 | All text contrast ratios (dark mode) | All meet WCAG AA | |
| 8 | No color-only information | Every colored indicator has non-color supplement | |

#### Reduce Motion Tests (5 test cases)

| # | Test | Expected Result | Pass? |
|---|------|----------------|-------|
| 1 | Score ring on load | No animation, ring appears at final value | |
| 2 | Navigation transitions | Cross-fade instead of slide | |
| 3 | PR achievement | No confetti/particles, static badge | |
| 4 | XP counter | No counting animation, final value shown | |
| 5 | Skeleton loading | No shimmer, static gray placeholder | |

#### Keyboard Navigation Tests (5 test cases)

| # | Test | Expected Result | Pass? |
|---|------|----------------|-------|
| 1 | Tab through all main screen elements | Focus ring visible, all elements reachable | |
| 2 | Enter/Space activates buttons | All buttons respond to Enter and Space | |
| 3 | Escape dismisses sheets/modals | Sheets and modals dismiss on Escape | |
| 4 | Cmd+1 through Cmd+5 switch tabs | All tabs accessible via keyboard shortcut | |
| 5 | Arrow keys in steppers | Weight/rep steppers respond to up/down arrows | |

#### Switch Control Tests (3 test cases)

| # | Test | Expected Result | Pass? |
|---|------|----------------|-------|
| 1 | Scan dashboard | Scan groups are logical, score ring reachable in 3 scans | |
| 2 | Complete a set in active workout | Weight, reps, and Complete Set all reachable via scanning | |
| 3 | Navigate between tabs | Tab bar items are a scan group, all reachable | |

#### Automated Tests (2 test cases)

| # | Test | Tool | Expected Result | Pass? |
|---|------|------|----------------|-------|
| 1 | Accessibility Inspector audit | Xcode Accessibility Inspector | Zero warnings for missing labels, zero contrast failures | |
| 2 | XCTest accessibility audit | `performAccessibilityAudit()` (Xcode 15+) | Zero failures | |

#### Scenario Tests (4 test cases)

| # | Scenario | Description | Expected Result | Pass? |
|---|----------|------------|----------------|-------|
| 1 | Blind user completes a workout | VoiceOver only: navigate to Training, start workout, log 3 sets, complete workout, read summary | All steps achievable without sighted assistance |
| 2 | Motor-impaired user runs focus timer | Switch Control: navigate to Lockdown, start focus timer, wait for completion, see result | Timer controllable via switch scanning |
| 3 | Low-vision user reads dashboard at AX5 | Dynamic Type AX5: open Dashboard, read all quadrant data, check non-negotiable status | All data readable, no clipping, no overlap |
| 4 | Deaf user receives drill sergeant notification | Muted device: receive a Lockdown notification, see visual indicator on tab bar, read notification content | Notification content fully accessible without sound |

### 9.2 Regression Test Triggers

Re-run the full accessibility checklist when:
- Any new screen is added
- Any existing screen layout changes
- Any color token changes
- Any animation is added or modified
- Any new interactive component is added
- iOS version bump (test on new OS beta)

---

## 10. Accessibility Settings in Tempo

Tempo provides its own accessibility settings in addition to respecting all system-level accessibility settings. These are located at Settings > Accessibility within the app.

### 10.1 In-App Accessibility Settings

| Setting | Options | Default | Description |
|---------|---------|---------|-------------|
| **Simplified Dashboard** | On / Off | Off | Reduces the dashboard to a single-column layout with one key metric per module. Removes sparklines, secondary metrics, and decorative elements. Shows: Daily Score, Recovery %, Calories, Study Minutes, Workout Status. |
| **High Contrast Mode** | On / Off | Off | Supplements system Increase Contrast. Adds visible borders to all cards, increases divider weight, uses only high-contrast color combinations. Works independently of the system setting. |
| **Audio Descriptions for Charts** | On / Off | Off | When focused on a chart, VoiceOver reads an extended description of the data including all data points, trend, and statistics. More verbose than the default summary. |
| **Haptic-Only Mode** | On / Off | Off | Disables all custom sounds (timer chimes, achievement sounds, notification sounds). Replaces every audio event with a distinct haptic pattern. System notification sounds follow the system setting. |
| **Timer Announcement Frequency** | Every 5 min (default) / Every 1 min / Key milestones only / Silent | Every 5 min | Controls how often VoiceOver announces the remaining time during Focus Timer and Rest Timer. "Silent" means no periodic announcements -- user checks manually. |
| **Large Button Mode** | On / Off | Off | Increases all button heights to 64pt minimum. Increases touch targets to 56x56pt minimum across the entire app (not just Active Workout). Increases stepper button size. Useful for users with tremors or limited fine motor control. |
| **Workout VoiceOver Verbosity** | Full / Concise / Minimal | Concise | **Full**: Every element fully described (labels + values + hints). **Concise**: Key info only (exercise name, set, weight, reps). **Minimal**: Only current action ("Set 2. 85 kg. 8 reps. Complete set.") |
| **Auto-Read Prescriptions** | On / Off | Off | When opening Recovery Today, VoiceOver automatically reads all prescription cards in sequence without requiring manual navigation. Useful for a quick morning briefing. |

### 10.2 System Settings Tempo Respects

These iOS system settings are automatically respected without any user configuration:

| System Setting | Tempo's Response |
|---|---|
| Dynamic Type size | All text scales. Layout adapts at accessibility sizes. |
| Bold Text | All text renders in bold. SF Pro Text becomes SF Pro Text Bold, etc. |
| Reduce Motion | All animations replaced per Section 6. |
| Increase Contrast | Card borders added, dividers strengthened per Section 4.3. |
| Reduce Transparency | Materials replaced with solid colors per Section 4.4. |
| Differentiate Without Color | Extra icons/patterns added (already default behavior). |
| On/Off Labels | Toggle switches show I/O labels. |
| Button Shapes | Buttons show underlines/shapes to indicate tappability. |
| Prefer Cross-Fade Transitions | Navigation transitions use cross-fade. |
| Auto-Play Video Previews | Exercise demos do not auto-play. |
| Dim Flashing Lights | Any screen flash effects (timer completion) are suppressed. |
| Per-App Text Size | Tempo respects per-app Dynamic Type overrides (iOS 15+). |
| Spoken Content | Speak Screen and Speak Selection work on all text. |
| VoiceOver | Full support per Section 2. |
| Switch Control | Full support per Section 5.2. |
| Voice Control | Full support per Section 5.3. |
| Full Keyboard Access | Full support per Section 5.7. |
| Mono Audio | No stereo-only information per Section 8.4. |
| Sound Recognition | Tempo's custom sounds do not interfere. |

### 10.3 Accessibility Settings UI

The in-app accessibility settings screen uses a standard grouped list:

```
┌────────────────────────────────────┐
│ < Settings      ACCESSIBILITY      │
├────────────────────────────────────┤
│                                    │
│ DISPLAY                            │
│ ┌────────────────────────────────┐ │
│ │ Simplified Dashboard    [OFF]  │ │
│ │ High Contrast Mode      [OFF]  │ │
│ │ Large Button Mode       [OFF]  │ │
│ └────────────────────────────────┘ │
│                                    │
│ VOICEOVER                          │
│ ┌────────────────────────────────┐ │
│ │ Audio Descriptions       [OFF] │ │
│ │ Workout Verbosity    [Concise] │ │
│ │ Auto-Read Prescriptions  [OFF] │ │
│ │ Timer Announcements  [5 min]   │ │
│ └────────────────────────────────┘ │
│                                    │
│ INTERACTION                        │
│ ┌────────────────────────────────┐ │
│ │ Haptic-Only Mode         [OFF] │ │
│ └────────────────────────────────┘ │
│                                    │
│ Tempo also respects all iOS        │
│ accessibility settings.            │
│ Open iOS Settings > Accessibility  │
│ for additional options.            │
│                                    │
└────────────────────────────────────┘
```

VoiceOver labels for this screen:
- Section headers are `.isHeader` traits.
- Toggle rows: "[Setting name], switch button, [on/off]. [Description]."
- Picker rows: "[Setting name], [current value]. Double-tap to change."
- Footer text: read as `.isStaticText`.

---

## 11. Localization Accessibility

### 11.1 Right-to-Left (RTL) Language Support

Tempo must be prepared for RTL layout if localized to Arabic, Hebrew, or other RTL languages.

**Layout rules for RTL:**
- All leading/trailing constraints must use `.leading` and `.trailing` (not `.left`/`.right`). SwiftUI handles this automatically with `HStack` and padding modifiers.
- The tab bar order stays the same (not mirrored). Tab bar is language-direction neutral.
- Navigation: back button moves to the top-right corner. Standard iOS behavior.
- Progress bars fill from right to left.
- Score rings still fill clockwise (universal convention).
- Charts: X-axis origin moves to the right.
- Lists remain top-to-bottom.
- Text alignment: natural (`.leading`, not `.left`).

**Implementation checklist for RTL readiness:**
- [ ] No hardcoded `.left` / `.right` alignment anywhere in code
- [ ] No hardcoded leading/trailing padding values that assume LTR
- [ ] All icons that imply direction (arrows, chevrons) flip automatically via `flipsForRightToLeftLayoutDirection`
- [ ] Images that are directional (e.g., a running figure) have RTL variants or are symmetrical
- [ ] Test with Xcode scheme > Options > Application Language > Right to Left Pseudolanguage

### 11.2 Screen Reader Pronunciation Hints

Exercise names and technical terms may not be pronounced correctly by VoiceOver in all languages/locales.

**Pronunciation hint strategy:**
- Use `accessibilityLanguage` property to specify the language of exercise names. Most exercise names are English-origin regardless of app locale. Set `accessibilityLanguage = "en"` on exercise name labels to ensure correct English pronunciation even when the app is in another language.
- For metric abbreviations: spell them out in the accessibility label.
  - "kg" becomes "kilograms" in the accessibility label
  - "cal" becomes "calories"
  - "BPM" becomes "beats per minute"
  - "ms" becomes "milliseconds"
  - "HRV" becomes "heart rate variability" (first mention on a screen), then "H R V" (subsequent mentions)
  - "RHR" becomes "resting heart rate"
  - "RPE" becomes "rate of perceived exertion"
  - "XP" becomes "experience points" (first mention), then "X P" (subsequent)
  - "PR" becomes "personal record"
  - "PPL" becomes "push pull legs"

**Custom pronunciation table for exercise names that VoiceOver commonly mispronounces:**

| Exercise Name | Default VoiceOver | Correct Pronunciation Hint |
|---|---|---|
| "Deadlift" | Usually correct | No hint needed |
| "Superset" | "Super-set" or "Soop-erset" | `accessibilitySpeechIPANotation`: /ˈsuːpərˌsɛt/ |
| "Hypertrophy" | Commonly mispronounced | `accessibilitySpeechIPANotation`: /haɪˈpɜːrtrəfi/ |
| "AMRAP" | May spell out letters | `accessibilityLabel`: "As many reps as possible" |
| "EMOM" | May spell out letters | `accessibilityLabel`: "Every minute on the minute" |
| "RPE" | "Arpy" | `accessibilityLabel`: "Rate of perceived exertion" |

### 11.3 Number Formatting

- All numbers respect the user's locale for formatting:
  - Decimal separator: "." (US) vs "," (EU)
  - Thousands separator: "," (US) vs "." (EU)
  - Weight units: kg by default (configurable to lbs in settings)
- VoiceOver reads numbers using the locale's pronunciation:
  - "2,340 XP" in en-US: "Two thousand three hundred forty experience points"
  - "2.340 XP" in it-IT: "Duemilatrecentoquaranta punti esperienza"
- Date formatting uses locale-aware formatters (`DateFormatter` with `.locale = .autoupdatingCurrent`).
- Time formatting respects 12h/24h system setting. Tempo's UI uses 24h format (design decision), but VoiceOver reads times in the user's preferred format.

### 11.4 Content Translation Accessibility

When localizing Tempo:
- Drill sergeant messages must be culturally adapted, not just translated. Direct translation of English military colloquialisms will not work.
- VoiceOver label strings must be in the localized language. They are part of the `Localizable.strings` file, not hardcoded.
- Achievement badge descriptions must be translated.
- Exercise names should remain in English with pronunciation hints (they are universal gym terminology) unless a locale-specific standard exists.

---

## Appendix A: Accessibility API Quick Reference

### SwiftUI Modifiers Used Throughout

```swift
// Labels and hints
.accessibilityLabel("Daily score")
.accessibilityValue("78 out of 100")
.accessibilityHint("Double-tap for score breakdown")

// Traits
.accessibilityAddTraits(.isHeader)
.accessibilityAddTraits(.isButton)
.accessibilityAddTraits(.updatesFrequently)
.accessibilityAddTraits(.isSummaryElement)
.accessibilityAddTraits(.startsMediaSession)

// Grouping
.accessibilityElement(children: .combine)
.accessibilityElement(children: .contain)

// Custom actions
.accessibilityAction(named: "Complete set") { completeSet() }
.accessibilityAction(named: "Skip timer") { skipTimer() }
.accessibilityAction(named: "Next exercise") { nextExercise() }

// Adjustable (steppers, sliders)
.accessibilityAdjustableAction { direction in
    switch direction {
    case .increment: weight += 2.5
    case .decrement: weight -= 2.5
    }
}

// Charts
.accessibilityChartDescriptor(chartDescriptor)

// Rotor
.accessibilityRotor("Quadrants") {
    ForEach(quadrants) { quadrant in
        AccessibilityRotorEntry(quadrant.name, id: quadrant.id)
    }
}

// Environment checks
@Environment(\.accessibilityReduceMotion) var reduceMotion
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
@Environment(\.colorSchemeContrast) var contrast
@Environment(\.dynamicTypeSize) var dynamicTypeSize
@Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
@Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

// Announcements
UIAccessibility.post(notification: .announcement, argument: "Set 2 completed.")
UIAccessibility.post(notification: .screenChanged, argument: firstElement)
UIAccessibility.post(notification: .layoutChanged, argument: updatedElement)
```

### Testing Tools

| Tool | Purpose | When to Use |
|------|---------|------------|
| **Xcode Accessibility Inspector** | Inspect labels, traits, values. Run automated audits. Simulate color filters. | Every screen, during development. |
| **VoiceOver on device** | Real-world screen reader testing. | Every screen, before PR merge. |
| **`performAccessibilityAudit()`** | Automated XCTest accessibility check. | CI pipeline, every build. |
| **Xcode Environment Overrides** | Test Dynamic Type, Reduce Motion, Increase Contrast, Bold Text. | Every screen, during development. |
| **Color Contrast Analyzer** | Verify specific color combinations. | When changing color tokens. |
| **Sim Daltonism** (macOS app) | Real-time color blindness simulation. | Before each release. |
| **Switch Control on device** | Test scanning behavior. | Before each release. |
| **Voice Control on device** | Test voice command discoverability. | Before each release. |

---

## Appendix B: Acceptance Criteria

A screen is considered "accessibility complete" when ALL of the following are true:

1. Every interactive element has an `accessibilityLabel`.
2. Every dynamic value element has an `accessibilityValue`.
3. Every interactive element that is not self-evident has an `accessibilityHint`.
4. Every heading has `.isHeader` trait.
5. Reading order is logical (matches visual hierarchy).
6. No information is conveyed by color alone.
7. All text/background combinations meet WCAG AA contrast ratios.
8. All text scales with Dynamic Type.
9. Layout adapts at AX3 and AX5 without clipping or overlapping.
10. All animations have Reduce Motion alternatives.
11. All touch targets are at least 44x44pt.
12. Focus management is correct after every state change.
13. Automated accessibility audit (`performAccessibilityAudit()`) passes with zero issues.
14. A VoiceOver-only walkthrough of the screen's primary user flow succeeds.

No screen ships without meeting all 14 criteria.
