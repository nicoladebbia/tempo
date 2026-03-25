# Tempo Apple Watch Companion App Specification v1.0

> The drill sergeant on your wrist. 3-second interactions. Zero excuses.

---

## Table of Contents

1. [Watch App Strategy](#1-watch-app-strategy)
2. [Watch Complications](#2-watch-complications)
3. [Watch App Screens](#3-watch-app-screens)
4. [Haptics](#4-haptics)
5. [Watch-iPhone Communication](#5-watch-iphone-communication)
6. [Performance Targets](#6-performance-targets)
7. [Watch Notifications](#7-watch-notifications)
8. [Live Activities on Watch](#8-live-activities-on-watch)
9. [Screen Specifications](#9-screen-specifications)

---

## 1. Watch App Strategy

### 1.1 Why Apple Watch

Tempo currently integrates with Whoop for biometrics, but the Apple Watch represents a 100M+ active installed base versus Whoop's niche market. Supporting Apple Watch does three things:

1. **Removes the Whoop dependency for public launch.** Users without Whoop can still get recovery data via Apple Watch + HealthKit (HRV, RHR, sleep stages, strain approximation from Active Energy).
2. **Gym convenience is a killer feature.** Logging sets from the wrist during a workout eliminates the need to pull out the phone between sets. This alone justifies the Watch app.
3. **Complications keep Tempo visible.** A complication on the watch face means the user sees their daily score, recovery zone, and next task hundreds of times per day. That is accountability that no notification can match.

### 1.2 Feature Triage: Wrist vs. Phone

| Feature | Watch | Phone | Rationale |
|---------|-------|-------|-----------|
| Daily score glance | Yes | Yes | Glanceable, perfect for wrist |
| Recovery zone + prescription | Summary | Full | Watch shows zone + 1-line prescription. Phone has full detail. |
| Workout logging (sets/reps) | Yes (primary gym UX) | Yes | The #1 Watch use case. Large buttons, haptic feedback. |
| Rest timer | Yes (primary) | Yes | Wrist is the natural place for a countdown timer |
| Focus timer (Pomodoro) | Yes | Yes | Start/pause/stop from wrist. Phone shows session history. |
| Non-negotiable checklist | Quick check-off only | Full management | Watch can mark items done. Phone manages the list. |
| Meal logging | "Mark as eaten" only | Full NutriTrack integration | Watch confirms scheduled meals. Phone handles entry/editing. |
| Weekly report / AI insights | No | Yes | Too much text for the wrist |
| Arena leaderboard | Position only | Full leaderboard | Watch shows "You: #3 of 8". Phone shows full board. |
| Challenges | Status badge only | Full management | Watch shows active challenge progress. |
| Onboarding / Settings | No | Yes | Never do setup on a Watch |
| Progress charts | No | Yes | Charts require study; not a 3-second interaction |
| Streak calendar | No | Yes | Heatmaps need screen real estate |

### 1.3 Architecture Decision: Companion App

**Choice: Companion Watch App (not independent)**

Rationale:
- Tempo's data originates from multiple server-side sources (Whoop API via backend proxy, NutriTrack via backend proxy, Arena leaderboards from PostgreSQL). The Watch cannot independently authenticate and sync with all these services.
- SwiftData models live on the iPhone. The Watch receives a lightweight snapshot.
- HealthKit data IS available independently on Watch, but the scoring engine, training engine, and recovery engine all run on iPhone. The Watch is a display + input terminal, not a compute node.
- WatchKit apps paired with an iPhone have access to Watch Connectivity for fast, reliable data transfer. An independent app would need its own network stack and auth, adding complexity with no benefit.

**Architecture diagram:**

```
┌─────────────────────────┐     WCSession      ┌──────────────────────┐
│     TEMPO WATCH APP     │◄──────────────────►│    TEMPO iOS APP     │
│                         │  transferUserInfo   │                      │
│  WatchSnapshot (read)   │  sendMessage        │  SwiftData (source)  │
│  WorkoutState (r/w)     │  transferFile       │  All Services        │
│  TimerState (r/w)       │  applicationContext  │  All Engines         │
│  QuickActions (write)   │                     │  Backend Sync        │
│                         │                     │                      │
│  Local: WKExtendedRT    │                     │  Watch Connectivity  │
│  HealthKit (direct)     │                     │  Session Delegate    │
│  Haptic Engine          │                     │                      │
└─────────────────────────┘                     └──────────────────────┘
```

### 1.4 Target Platform

| Requirement | Value |
|-------------|-------|
| Minimum watchOS | 10.0 |
| Recommended watchOS | 11.0+ (for Live Activities) |
| Supported hardware | Apple Watch Series 6+, SE (2nd gen)+, Ultra 1+ |
| Display sizes | 41mm, 45mm, 49mm (Ultra) |
| SDK | WatchKit, SwiftUI, WidgetKit (complications), Watch Connectivity |

### 1.5 Xcode Project Structure

```
TempoWatch/
├── TempoWatchApp.swift              # Watch app entry point
├── Models/
│   ├── WatchSnapshot.swift          # Lightweight daily data from iPhone
│   ├── WatchWorkoutState.swift      # Current workout + set tracking
│   ├── WatchTimerState.swift        # Focus timer state
│   └── WatchQuickAction.swift       # Actions to send back to iPhone
├── Services/
│   ├── WatchConnectivityService.swift  # WCSession management
│   ├── WatchHapticService.swift     # Haptic pattern definitions
│   └── WatchHealthKitService.swift  # Direct HealthKit reads (HR, steps)
├── Views/
│   ├── GlanceHomeView.swift         # Main watch face
│   ├── WorkoutView.swift            # Active workout logging
│   ├── FocusTimerView.swift         # Pomodoro timer
│   ├── QuickLogView.swift           # Quick actions
│   ├── RecoveryView.swift           # Recovery summary
│   └── ArenaGlanceView.swift        # XP + position
├── Complications/
│   ├── TempoComplicationProvider.swift  # TimelineProvider
│   └── ComplicationViews.swift      # All complication families
├── Notifications/
│   └── NotificationController.swift # Actionable watch notifications
└── Resources/
    └── Assets.xcassets              # Watch-specific assets
```

---

## 2. Watch Complications

Complications are the most important surface of the Watch app. They are visible on the watch face without launching anything. Every complication must answer the question: "How am I doing right now, and what should I do next?"

### 2.1 Data Model for Complications

```swift
struct TempoComplicationData: Codable {
    let dailyScore: Int                // 0-100
    let scoreProgress: Double          // 0.0-1.0 for ring fill
    let recoveryZone: RecoveryZone     // .green, .yellow, .red
    let recoveryScore: Int             // 0-100
    let nextTaskName: String           // "Study", "Train Legs", "Log Dinner"
    let nextTaskTimeRemaining: String  // "1h23m", "Now", "2:30 left"
    let nonNegotiablesProgress: String // "3/5"
    let leisureUnlocked: Bool
    let currentStreak: Int
    let xp: Int
    let leaderboardPosition: Int?
}
```

### 2.2 TimelineProvider

```swift
struct TempoComplicationProvider: TimelineProvider {
    typealias Entry = TempoComplicationEntry

    func placeholder(in context: Context) -> TempoComplicationEntry {
        // Static placeholder shown in complication picker
        TempoComplicationEntry(
            date: .now,
            data: .placeholder  // Score: 78, Recovery: Green, Next: "Study"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TempoComplicationEntry) -> Void) {
        // Quick snapshot for transitional states
        let data = WatchConnectivityService.shared.latestSnapshot
        completion(TempoComplicationEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoComplicationEntry>) -> Void) {
        let data = WatchConnectivityService.shared.latestSnapshot
        let now = Date()

        // Create entries: now, then refresh every 15 minutes
        var entries: [TempoComplicationEntry] = []
        for minuteOffset in stride(from: 0, through: 60, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now)!
            entries.append(TempoComplicationEntry(date: entryDate, data: data))
        }

        let timeline = Timeline(entries: entries, policy: .after(
            Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        ))
        completion(timeline)
    }
}

struct TempoComplicationEntry: TimelineEntry {
    let date: Date
    let data: TempoComplicationData
}
```

**Update triggers:**
- `WCSession` `applicationContext` update from iPhone (immediate complication refresh via `CLKComplicationServer.sharedInstance().reloadTimelines`)
- Timeline policy: refresh every 15 minutes as fallback
- iPhone pushes updated context whenever: score changes, non-negotiable completed, recovery data arrives, workout starts/ends

### 2.3 Complication Families

#### Circular (`accessoryCircular`)

**Design:** A single progress ring showing the daily score (0-100).

```
    ╭───────╮
   │  ╭───╮  │
   │ │ 78  │ │    ← Score number centered
   │  ╰───╯  │    ← Ring stroke = Signal Red gradient
    ╰───────╯       Ring fill = scoreProgress (0.0-1.0)
```

- Ring color: `tempo/gradient/score-ring` (Signal Red to Fail Red, clockwise)
- Ring background track: `tempo/secondary/ash` at 30% opacity
- Ring stroke width: 4pt
- Center text: Daily score in SF Pro Rounded Bold, 16pt
- Center text color: `tempo/text/primary-dark` (Bone White -- complications always render on dark)
- If score is 0 or no data: show "--" in center, empty ring

**Tap target:** Opens `GlanceHomeView`

```swift
ZStack {
    AccessoryWidgetBackground()
    ProgressView(value: Double(data.dailyScore) / 100.0) {
        Text("\(data.dailyScore)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
    }
    .progressViewStyle(.circular)
    .tint(Color.tempoSignal)
}
```

#### Rectangular (`accessoryRectangular`)

**Design:** Two-line layout -- recovery zone + score on top, next task on bottom.

```
┌──────────────────────────┐
│ 🟢 Recovery 82  Score 78 │  ← Line 1: zone dot + recovery + score
│ Study — 1h23m left       │  ← Line 2: next task + time remaining
└──────────────────────────┘
```

- Line 1: Recovery zone dot (colored circle, 8pt) + "Recovery XX" in SF Pro Text Semibold 13pt + "Score XX" in SF Pro Rounded Bold 13pt, right-aligned
- Line 2: Next task name + time remaining in SF Pro Text Regular 12pt, `tempo/text/secondary-dark`
- Zone dot color: `tempo/recovery/green-dark`, `tempo/recovery/yellow-dark`, or `tempo/recovery/red-dark`
- If leisure is unlocked: Line 2 shows "All clear. Earned." in `tempo/semantic/success-dark`

**Tap target:** Opens `RecoveryView` if tapped on top line, `GlanceHomeView` otherwise

```swift
VStack(alignment: .leading, spacing: 2) {
    HStack {
        Circle()
            .fill(data.recoveryZone.color)
            .frame(width: 8, height: 8)
        Text("Recovery \(data.recoveryScore)")
            .font(.system(size: 13, weight: .semibold))
        Spacer()
        Text("Score \(data.dailyScore)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
    }
    if data.leisureUnlocked {
        Text("All clear. Earned.")
            .font(.system(size: 12))
            .foregroundStyle(Color.tempoSuccess)
    } else {
        Text("\(data.nextTaskName) — \(data.nextTaskTimeRemaining)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}
```

#### Inline (`accessoryInline`)

**Design:** Single line of text with optional SF Symbol.

```
◉ Score: 78 | Study: 1h23m left
```

- Format: `"Score: {score} | {nextTask}: {timeRemaining}"`
- If leisure unlocked: `"Score: {score} | All clear"`
- Leading SF Symbol: `circle.fill` tinted to recovery zone color (note: inline complications have limited color support -- system renders in tint color, so the symbol serves as a visual anchor)
- Font: System default (inline complications use the watch face's font)
- Maximum character count: ~32 characters. Truncate task name if needed.

**Tap target:** Opens `GlanceHomeView`

```swift
ViewThatFits {
    Text("\(Image(systemName: "circle.fill")) Score: \(data.dailyScore) | \(data.nextTaskName): \(data.nextTaskTimeRemaining)")
    Text("\(Image(systemName: "circle.fill")) \(data.dailyScore) | \(data.nextTaskName)")
    Text("\(Image(systemName: "circle.fill")) Score: \(data.dailyScore)")
}
```

#### Corner (`accessoryCorner`)

**Design:** Score number with a curved gauge around the corner.

```
         78          ← Score number, large
    ╭──────────╮
    │ curved   │    ← Gauge arc follows corner curvature
    │ gauge    │       Fill = scoreProgress
    ╰──────────╯
```

- Inner content: Score number in SF Pro Rounded Bold, system-sized for corner
- Gauge: `Gauge(value:)` with angular style, tinted `tempo/primary/signal-dark`
- Gauge background track: `tempo/secondary/ash` at 30% opacity
- If recovery is red: gauge tint switches to `tempo/recovery/red-dark` as a warning

**Tap target:** Opens `GlanceHomeView`

```swift
Text("\(data.dailyScore)")
    .font(.system(size: 24, weight: .bold, design: .rounded))
    .widgetLabel {
        Gauge(value: Double(data.dailyScore), in: 0...100) {
            Text("Score")
        }
        .gaugeStyle(.accessoryLinear)
        .tint(data.dailyScore >= 50 ? Color.tempoSignal : Color.tempoError)
    }
```

#### Extra Large (`accessoryExtraLarge`) -- watchOS 10+ Infograph Extra Large

**Design:** Mini-dashboard with score ring, recovery badge, and next task.

```
┌──────────────────────┐
│       ╭───╮          │
│      │ 78  │         │  ← Large score ring, centered
│       ╰───╯          │
│   🟢 Recovery: 82    │  ← Recovery zone + score
│   Study — 1h23m      │  ← Next task
│   NN: 3/5            │  ← Non-negotiable progress
└──────────────────────┘
```

- Score ring: Same as circular but larger (ring stroke 6pt, score text 28pt SF Pro Rounded Bold)
- Recovery line: Zone dot (10pt) + "Recovery: XX" in SF Pro Text Semibold 14pt
- Task line: Task name + time in SF Pro Text Regular 13pt
- NN line: "NN: X/Y" in SF Pro Text Regular 12pt, `tempo/text/tertiary-dark`
- Vertical spacing: 4pt between elements

**Tap target:** Opens `GlanceHomeView`

### 2.4 Complication Refresh Strategy

| Trigger | Method | Latency |
|---------|--------|---------|
| Non-negotiable completed on iPhone | `WCSession.updateApplicationContext` triggers `CLKComplicationServer.reloadTimelines` | <5 seconds |
| Workout started/completed | Same as above | <5 seconds |
| Score recalculated | Same as above | <5 seconds |
| Recovery data arrives from Whoop | Same as above | <5 seconds |
| Timer started/stopped from Watch | Local state change triggers timeline reload | Immediate |
| Periodic fallback | `TimelineProvider` policy `.after(1 hour)` | 15-60 min |

---

## 3. Watch App Screens

### 3.1 Navigation Architecture

**Pattern: `NavigationStack` with `TabView` (vertical paging)**

The Watch app uses a vertically-paging `TabView` as the root, with 5 pages:

```
Page 1: Glance/Home View (default)
Page 2: Workout View
Page 3: Focus Timer View
Page 4: Quick Log View
Page 5: Recovery View
```

Swipe up/down to move between pages. The Digital Crown also scrolls. Arena Glance is accessible via a button on Page 1 (not a separate page -- it is low-frequency information).

This keeps the most-used features (Workout, Timer) one swipe from home.

### 3.2 Glance/Home View

The landing screen. Must communicate "how am I doing" in under 2 seconds.

```
┌──────────────────────────────┐
│          0734                │  ← Current time, 24h, top-right
│                              │
│        ╭──────╮              │
│       │       │             │
│       │  78   │             │  ← Daily score ring, large
│       │       │             │
│        ╰──────╯              │
│                              │
│   🟢 GREEN  Recovery 82     │  ← Recovery zone badge
│                              │
│   ┌────────────────────┐    │
│   │ ▸ Train Push       │    │  ← Next non-negotiable
│   │   Not started      │    │
│   └────────────────────┘    │
│                              │
│   🎮 PS5: Complete 2 more   │  ← Leisure unlock status
│                              │
│   NN: ███░░ 3/5             │  ← Non-negotiable progress bar
│                              │
│   ┌──────┐  ┌──────┐       │
│   │Arena │  │ More │       │  ← Bottom quick links
│   └──────┘  └──────┘       │
└──────────────────────────────┘
```

**Elements:**

| Element | Type | Font | Color |
|---------|------|------|-------|
| Time | Text | SF Pro Text Semibold 13pt | `tempo/text/tertiary-dark` |
| Score ring | `ProgressView(.circular)` | -- | `tempo/gradient/score-ring` |
| Score number | Text (center of ring) | SF Pro Rounded Bold 40pt | `tempo/text/primary-dark` |
| Recovery zone badge | HStack (dot + text) | SF Pro Text Semibold 15pt | Zone color + `tempo/text/primary-dark` |
| Recovery score | Text | SF Pro Rounded Bold 15pt | Zone color |
| Next task card | Rounded rect | SF Pro Text Semibold 15pt (name), Regular 12pt (status) | Card: `tempo/surface/card-dark`, Text: `tempo/text/primary-dark` |
| PS5 status | Text | SF Pro Text Regular 13pt | `tempo/text/secondary-dark`. Green if unlocked. |
| NN progress | ProgressView(.linear) + label | SF Pro Mono Medium 12pt | `tempo/primary/signal-dark` fill, `tempo/secondary/ash` track |
| Arena / More buttons | Rounded rect buttons | SF Pro Text Semibold 13pt | `tempo/surface/card-dark` bg |

**Behavior:**
- Scrollable via Digital Crown if content exceeds screen
- Tapping next task card: navigates to relevant view (Workout, Timer, or Quick Log)
- Tapping Arena button: pushes `ArenaGlanceView`
- Data refreshes on `willActivate` and when `WCSession` delivers new context
- If no data received from iPhone yet: show "--" for all values, "Open Tempo on iPhone" message

### 3.3 Workout View (PRIMARY USE CASE)

This is the reason the Watch app exists. During gym sessions, the phone stays in a bag or pocket. Every interaction here must work with sweaty hands and limited attention.

#### 3.3.1 Workout Summary (No Active Workout)

```
┌──────────────────────────────┐
│   TODAY'S WORKOUT            │
│                              │
│   Push Day                   │  ← Workout type
│   6 exercises, ~55 min       │  ← Summary
│                              │
│   🟢 Recovery: GO            │  ← Recovery-based intensity
│   Volume: Standard           │
│                              │
│   ┌────────────────────────┐ │
│   │                        │ │
│   │    START WORKOUT       │ │  ← Large green button
│   │                        │ │
│   └────────────────────────┘ │
│                              │
│   Exercises:                 │
│   1. Bench Press  4×8       │
│   2. Incline DB   3×10     │
│   3. Cable Fly    3×12     │
│   ...scroll for more        │
└──────────────────────────────┘
```

**Start Workout button:**
- Size: Full width minus 16pt padding, 50pt height
- Color: `tempo/semantic/success-dark` background, `tempo/primary/ink` text
- Corner radius: 14pt
- Tapping sends `startWorkout` action to iPhone via `sendMessage`
- If iPhone is unreachable: show "Open Tempo on iPhone first" alert

#### 3.3.2 Active Workout View (CRITICAL)

When a workout is in progress (started from Watch or iPhone), the Watch shows the current exercise and set.

```
┌──────────────────────────────┐
│  PUSH DAY          2 of 6   │  ← Workout type + exercise progress
│                              │
│  Bench Press                 │  ← Current exercise name
│  Set 2 of 4                 │  ← Current set
│                              │
│  ┌──────────────────────┐   │
│  │   8 reps × 80 kg     │   │  ← Target for this set
│  └──────────────────────┘   │
│                              │
│  ┌────────────────────────┐ │
│  │                        │ │
│  │    ✓  SET DONE         │ │  ← LARGE tap target, primary action
│  │                        │ │
│  └────────────────────────┘ │
│                              │
│  ┌──────────┐ ┌──────────┐ │
│  │  SKIP    │ │  ADJUST  │ │  ← Secondary actions
│  └──────────┘ └──────────┘ │
└──────────────────────────────┘
```

**"SET DONE" button:**
- Size: Full width minus 16pt padding, **56pt height** (extra tall for sweaty taps)
- Color: `tempo/primary/signal-dark` (#FF4D5A) background, white text
- Font: SF Pro Text Bold 18pt
- Corner radius: 14pt
- On tap: triggers `.success` haptic, advances to rest timer
- This button MUST have generous hit area -- extend tap target 8pt beyond visual bounds

**"SKIP" button:**
- Skips current set, marks as skipped
- Color: `tempo/surface/card-dark` background, `tempo/text/secondary-dark` text
- Size: Half width minus 12pt, 40pt height

**"ADJUST" button:**
- Opens a quick picker to change weight or reps for this set
- Uses Digital Crown for weight adjustment (increment: 2.5kg)
- Color: `tempo/surface/card-dark` background, `tempo/accent/electric-dark` text

**Exercise info:**
- Exercise name: SF Pro Text Bold 17pt, `tempo/text/primary-dark`
- Set progress: SF Pro Text Regular 14pt, `tempo/text/secondary-dark`
- Target display: SF Mono Bold 20pt in a card (`tempo/surface/card-dark` bg, 12pt corner radius, 12pt vertical padding)

#### 3.3.3 Rest Timer View

After completing a set, the rest timer starts automatically.

```
┌──────────────────────────────┐
│  REST                        │
│                              │
│                              │
│         1:32                 │  ← Large countdown, center
│                              │
│                              │
│  ┌────────────────────────┐ │
│  │    NEXT SET             │ │  ← Skip rest, go to next set
│  │    Bench Press 3/4      │ │
│  │    8 reps × 80 kg       │ │
│  └────────────────────────┘ │
│                              │
│  ┌──────────┐ ┌──────────┐ │
│  │  +30s    │ │  DONE    │ │  ← Extend or skip rest
│  └──────────┘ └──────────┘ │
└──────────────────────────────┘
```

**Timer display:**
- Font: SF Mono Bold 48pt
- Color: Starts `tempo/text/primary-dark`, transitions to `tempo/primary/signal-dark` at 10 seconds remaining
- Animation: Pulses at 3, 2, 1 seconds remaining

**Rest duration:**
- Default rest periods sent from iPhone as part of workout plan:
  - Compound exercises: 120s
  - Isolation exercises: 60s
  - Supersets: 30s between exercises, 90s between rounds
- "+30s" button extends the timer
- "DONE" button ends rest early, advances to next set

**Haptics on rest complete:**
- At 0 seconds: `.notification` type haptic
- Followed by 3 short taps at 0.5s intervals
- Watch screen turns on (via `WKInterfaceDevice.current().play(.notification)`)

#### 3.3.4 Exercise Transition

When all sets of an exercise are complete:

```
┌──────────────────────────────┐
│  ✓ Bench Press               │
│  4/4 sets complete           │
│                              │
│  Next up:                    │
│                              │
│  Incline Dumbbell Press      │
│  3 sets × 10 reps            │
│  22 kg each                  │
│                              │
│  ┌────────────────────────┐ │
│  │                        │ │
│  │    START EXERCISE       │ │
│  │                        │ │
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │    FINISH WORKOUT      │ │  ← Only on last exercise
│  └────────────────────────┘ │
└──────────────────────────────┘
```

**"FINISH WORKOUT" button:**
- Only appears when all exercises are complete (or user can force-finish anytime via long-press on the workout title)
- Color: `tempo/semantic/success-dark` background
- On tap: sends workout completion to iPhone, triggers celebration haptic, shows summary

#### 3.3.5 Workout Complete Summary

```
┌──────────────────────────────┐
│        DONE                  │
│                              │
│   Push Day Complete          │
│                              │
│   Duration:    47 min        │
│   Sets:        18/20         │
│   Volume:      4,280 kg      │
│   Avg Rest:    98 sec        │
│                              │
│   +50 XP                     │  ← XP earned, amber
│                              │
│   ┌────────────────────────┐ │
│   │       DISMISS           │ │
│   └────────────────────────┘ │
└──────────────────────────────┘
```

### 3.4 Focus Timer View

Pomodoro timer controlled from the wrist. Useful during study sessions when the phone should be out of reach (distraction-free).

#### 3.4.1 Timer Ready State

```
┌──────────────────────────────┐
│  FOCUS                       │
│                              │
│       25:00                  │  ← Default session length
│                              │
│  Sessions today: 3           │
│  Total: 1h15m               │
│                              │
│  ┌────────────────────────┐ │
│  │                        │ │
│  │       START             │ │
│  │                        │ │
│  └────────────────────────┘ │
│                              │
│  Duration: 25 min  ↻        │  ← Tap to cycle: 15/25/45/60
└──────────────────────────────┘
```

**Duration selector:**
- Tap cycles through preset durations: 15, 25, 45, 60 minutes
- Digital Crown can also adjust in 5-minute increments
- Default: 25 minutes (Pomodoro standard)

#### 3.4.2 Timer Running State

```
┌──────────────────────────────┐
│  FOCUS             Session 4 │
│                              │
│                              │
│        18:42                 │  ← Large countdown
│                              │
│                              │
│  ┌──────────┐ ┌──────────┐ │
│  │  PAUSE   │ │  STOP    │ │
│  └──────────┘ └──────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │     + 5 MINUTES         │ │  ← Extend session
│  └────────────────────────┘ │
└──────────────────────────────┘
```

**Timer display:**
- Font: SF Mono Bold 48pt
- Color: `tempo/accent/electric-dark` (study module color)
- Uses `TimelineView(.periodic(from: .now, by: 1.0))` for smooth countdown
- Screen stays on during active timer via `WKExtendedRuntimeSession`

**Controls:**
- PAUSE: `tempo/accent/electric-dark` bg. Pausing shows "RESUME" button in its place.
- STOP: `tempo/surface/card-dark` bg, `tempo/semantic/error-dark` text. Stops and records partial session.
- +5 MINUTES: `tempo/surface/card-dark` bg. Extends current session.

**On completion:**
- Extended haptic pattern: 3 long taps, pause, 2 short taps
- Screen turns on
- Shows "Session complete. +25 min logged." for 5 seconds
- Auto-sends session data to iPhone

### 3.5 Quick Log View

Rapid actions from the wrist. No keyboards, no text input. Just taps.

```
┌──────────────────────────────┐
│  QUICK LOG                   │
│                              │
│  ┌────────────────────────┐ │
│  │ ☐ Study 2h             │ │  ← Non-negotiable: tap to check
│  │   0h37m / 2h00m        │ │     (auto-tracked via timer)
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │ ☐ Train                │ │  ← Non-negotiable: tap to start
│  │   Not started          │ │     workout
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │ ☑ Eat 3 meals          │ │  ← Auto-tracked via NutriTrack
│  │   3/3 complete         │ │     Green checkmark
│  └────────────────────────┘ │
│                              │
│  ┌────────────────────────┐ │
│  │ ☐ Read 30 min          │ │  ← Manual: tap to mark done
│  │   Custom               │ │
│  └────────────────────────┘ │
│                              │
│  MEALS                       │
│  ┌──────────┐ ┌──────────┐ │
│  │✓ Lunch   │ │ Dinner   │ │  ← Tap to confirm meal eaten
│  │ 12:30    │ │ 19:30    │ │
│  └──────────┘ └──────────┘ │
└──────────────────────────────┘
```

**Non-negotiable items:**
- Auto-tracked items show real-time progress from iPhone data (study minutes, meals logged, workout status)
- Manual items: single tap toggles completion. Confirmation haptic (`.success`).
- Completed items: green checkmark, strikethrough text, `tempo/semantic/success-dark`
- Pending items: empty checkbox, `tempo/text/primary-dark`

**Meal buttons:**
- Shows today's scheduled meals from NutriTrack
- Already-eaten meals: green border, checkmark, dimmed
- Upcoming meals: white border, tappable
- Tapping "Dinner" sends `confirmMealEaten(mealId)` to iPhone, which logs it in NutriTrack
- Only shows meal name + scheduled time. No macro details (phone only).

**Behavior on tap:**
- Any state change is immediately sent to iPhone via `sendMessage` (real-time)
- If iPhone is unreachable: queue the action and send on next `sessionReachabilityDidChange`
- Show brief inline confirmation: "Logged." fades in and out over 1.5 seconds

### 3.6 Recovery View

Read-only summary of today's recovery data.

```
┌──────────────────────────────┐
│  RECOVERY                    │
│                              │
│        ╭──────╮              │
│       │       │             │
│       │  82   │             │  ← Recovery score ring
│       │       │             │
│        ╰──────╯              │
│       GREEN ZONE             │
│                              │
│  HRV       62 ms            │
│  RHR       54 bpm           │
│  Sleep     7h42m            │
│  Strain    12.4             │
│                              │
│  ┌────────────────────────┐ │
│  │ Rx: Full volume. Push  │ │  ← Short prescription
│  │ for PRs today.         │ │
│  └────────────────────────┘ │
│                              │
│  More detail on iPhone ▸    │
└──────────────────────────────┘
```

**Recovery ring:**
- Size: 80pt diameter
- Stroke: 6pt
- Color: Zone-appropriate gradient (`tempo/gradient/recovery-high`, `recovery-mid`, `recovery-low`)
- Score text: SF Pro Rounded Bold 32pt, zone color

**Metrics grid:**
- Labels: SF Pro Text Regular 13pt, `tempo/text/tertiary-dark`, left-aligned
- Values: SF Mono Semibold 15pt, `tempo/text/primary-dark`, right-aligned
- Vertical spacing: 8pt between rows

**Prescription card:**
- Background: Zone-tinted card (`tempo/recovery/green-bg-dark`, `yellow-bg-dark`, `red-bg-dark`)
- Text: SF Pro Text Regular 13pt, `tempo/text/primary-dark`
- Maximum 2 lines. Full prescription is on the iPhone.
- Corner radius: 10pt, padding: 10pt

**Data source:** Entirely from `WatchSnapshot` received via `WCSession`. No direct Whoop API calls from Watch.

### 3.7 Arena Glance View

Accessed via button on Glance/Home View. Not a primary page -- Arena is low-frequency.

```
┌──────────────────────────────┐
│  ARENA                       │
│                              │
│  Level 12                    │
│  ███████████░░░ 2,340 XP    │  ← Progress to next level
│                              │
│  This week: #3 of 8         │  ← Leaderboard position
│                              │
│  ┌────────────────────────┐ │
│  │ 🏆 Active Challenge     │ │
│  │ "Study Hours" week      │ │
│  │ You: 8h  Leader: 12h   │ │
│  └────────────────────────┘ │
│                              │
│  Streak: 23 days 🔥          │
│                              │
│  ◀ Back                      │
└──────────────────────────────┘
```

**Elements:**
- Level: SF Pro Rounded Bold 20pt, `tempo/accent/amber-dark`
- XP bar: Linear progress, `tempo/gradient/xp-bar`, 6pt height, 8pt corner radius
- XP label: SF Mono Medium 13pt, right of bar
- Leaderboard position: SF Pro Text Semibold 15pt. Position number in `tempo/accent/amber-dark`.
- Challenge card: `tempo/surface/card-dark` bg, 10pt corner radius
- Streak: SF Pro Text Semibold 15pt, flame emoji only exception to no-emoji rule (gamification context)

---

## 4. Haptics

All haptics use `WKInterfaceDevice.current().play(_:)` or the `WKHapticType` API. Custom patterns use `CHHapticEngine` where available (Series 6+).

### 4.1 Haptic Definitions

| Event | Haptic Type | Pattern | Notes |
|-------|-------------|---------|-------|
| **Set completed** | `.success` | Single strong tap | Immediate confirmation. The user should feel "done" without looking. |
| **Rest timer expired** | `.notification` + custom | 1 notification buzz, then 3 short taps at 500ms intervals | Must be unmissable in a noisy gym. Also wakes the screen. |
| **Non-negotiable checked off** | `.success` | Single strong tap | Same as set complete -- consistency matters. |
| **All non-negotiables done** | `.success` + `.success` | Two success taps, 300ms apart | Double-tap signals "something special" vs single-tap. |
| **Focus timer completed** | Custom sequence | 3 long taps (300ms each, 200ms gaps), 500ms pause, 2 short taps (150ms each) | Distinct pattern. User learns to recognize "that's my timer" without looking. |
| **Focus timer +5 min extend** | `.click` | Single light tap | Acknowledges the action without celebrating it. |
| **Workout started** | `.start` | System start haptic | Signals the beginning of something. |
| **Workout completed** | Custom celebration | 5 ascending-intensity taps over 1.5 seconds | Victory pattern. Crescendo effect. |
| **Exercise transition** | `.click` | Single light tap | Subtle. "Next thing." |
| **Streak milestone (7/30/100 days)** | Custom celebration + notification | Notification buzz, then rapid 8-tap burst (100ms each) | The most intense haptic in the app. Reserved for real milestones. |
| **PS5 unlocked (leisure earned)** | `.success` + `.success` + `.success` | Triple success, 200ms gaps | Three taps = "you're free." |
| **Error / action failed** | `.failure` | System failure haptic | Something went wrong. |
| **Adjust weight (Digital Crown)** | `.click` | Light click per detent | Crown rotation feedback for weight adjustment. |

### 4.2 Implementation

```swift
final class WatchHapticService {
    static let shared = WatchHapticService()
    private let device = WKInterfaceDevice.current()

    func setComplete() {
        device.play(.success)
    }

    func restTimerDone() {
        device.play(.notification)
        Task {
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(500))
                device.play(.click)
            }
        }
    }

    func focusTimerDone() {
        Task {
            // 3 long taps
            for _ in 0..<3 {
                device.play(.success)
                try? await Task.sleep(for: .milliseconds(500))
            }
            try? await Task.sleep(for: .milliseconds(500))
            // 2 short taps
            for _ in 0..<2 {
                device.play(.click)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func workoutComplete() {
        Task {
            // Ascending celebration
            for i in 0..<5 {
                device.play(i < 3 ? .click : .success)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func streakMilestone() {
        device.play(.notification)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            for _ in 0..<8 {
                device.play(.click)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func leisureUnlocked() {
        Task {
            for _ in 0..<3 {
                device.play(.success)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}
```

---

## 5. Watch-iPhone Communication

### 5.1 Communication Protocol

Watch Connectivity (`WCSession`) is the only transport. No direct networking from the Watch app.

| Method | Direction | Use Case | Delivery | Latency |
|--------|-----------|----------|----------|---------|
| `updateApplicationContext(_:)` | iPhone -> Watch | Daily snapshot, complication data | Guaranteed (latest only) | <5s when reachable, on next wake otherwise |
| `sendMessage(_:replyHandler:)` | Both | Real-time actions: set complete, timer start/stop, meal confirm | Immediate, requires reachability | <1s |
| `transferUserInfo(_:)` | iPhone -> Watch | Full workout plan, exercise details | Queued, FIFO, guaranteed | <30s typically |
| `transferFile(_:metadata:)` | iPhone -> Watch | (Reserved for future: exercise demo images) | Queued, background | Variable |

### 5.2 Data Payloads

#### iPhone -> Watch: Application Context (complication + glance data)

```swift
struct WatchApplicationContext: Codable {
    // Timestamp
    let updatedAt: Date

    // Daily Score
    let dailyScore: Int
    let scoreProgress: Double

    // Recovery
    let recoveryScore: Int?
    let recoveryZone: String        // "green", "yellow", "red"
    let hrvRmssd: Double?
    let restingHR: Double?
    let sleepHours: Double?
    let strain: Double?
    let prescriptionShort: String?  // 1-line prescription

    // Accountability
    let nonNegotiables: [WatchNonNegotiable]
    let leisureUnlocked: Bool
    let currentStreak: Int

    // Training
    let todayWorkoutType: String?   // "Push", "Pull", "Legs", etc.
    let todayWorkoutStatus: String  // "planned", "inProgress", "completed"
    let exerciseCount: Int
    let estimatedDuration: Int      // minutes

    // Nutrition
    let scheduledMeals: [WatchMeal]

    // Arena
    let xp: Int
    let level: Int
    let leaderboardPosition: Int?
    let leaderboardSize: Int?
    let activeChallengeTitle: String?
    let activeChallengeProgress: String?

    // Focus Timer
    let totalStudyMinutesToday: Int
    let studyTarget: Int
}

struct WatchNonNegotiable: Codable {
    let id: String
    let name: String
    let type: String            // "study", "train", "meals", "custom"
    let isCompleted: Bool
    let progress: String?       // "1h15m / 2h00m", "2/3", nil for custom
    let isAutoTracked: Bool
}

struct WatchMeal: Codable {
    let id: String
    let name: String            // "Lunch", "Dinner", "Snack"
    let scheduledTime: String   // "12:30", "19:30"
    let isEaten: Bool
}
```

Size estimate: ~1-2 KB. Well within `applicationContext` limits.

#### iPhone -> Watch: User Info Transfer (workout plan detail)

```swift
struct WatchWorkoutPlan: Codable {
    let workoutId: String
    let type: String
    let recoveryAdjustment: Double
    let exercises: [WatchExercise]
}

struct WatchExercise: Codable {
    let id: String
    let name: String
    let muscleGroup: String
    let order: Int
    let supersetGroup: Int?
    let sets: [WatchSet]
    let restSeconds: Int        // rest between sets
}

struct WatchSet: Codable {
    let setNumber: Int
    let targetReps: Int
    let targetWeight: Double?   // kg
    let isWarmup: Bool
}
```

Sent once when workout plan is generated or updated. ~2-5 KB depending on exercise count.

#### Watch -> iPhone: Actions (via sendMessage)

```swift
enum WatchAction: Codable {
    case startWorkout(workoutId: String)
    case completeSet(exerciseId: String, setNumber: Int, actualReps: Int?, actualWeight: Double?)
    case skipSet(exerciseId: String, setNumber: Int)
    case adjustSet(exerciseId: String, setNumber: Int, newReps: Int?, newWeight: Double?)
    case finishWorkout(workoutId: String)

    case startFocusTimer(durationMinutes: Int)
    case pauseFocusTimer
    case resumeFocusTimer
    case stopFocusTimer
    case extendFocusTimer(additionalMinutes: Int)

    case completeNonNegotiable(id: String)
    case confirmMealEaten(mealId: String)
}
```

Serialized as JSON dictionary with a `type` key and associated values. Typically <200 bytes per action.

### 5.3 Sync Protocol

```
STARTUP FLOW:
1. Watch app launches
2. WatchConnectivityService activates WCSession
3. Check WCSession.activationState == .activated
4. Read latest applicationContext (cached from last update)
5. Display immediately with cached data
6. If session.isReachable: send "heartbeat" message to iPhone
7. iPhone responds with fresh applicationContext

RUNTIME FLOW (iPhone -> Watch):
- Score changes -> updateApplicationContext
- Workout plan changes -> transferUserInfo
- Real-time workout state (if workout started from iPhone) -> sendMessage

RUNTIME FLOW (Watch -> iPhone):
- User action -> sendMessage with WatchAction
- If !session.isReachable: queue action locally, retry on reachabilityDidChange
- iPhone processes action, updates SwiftData, sends updated applicationContext back

CONFLICT RESOLUTION:
- iPhone is ALWAYS the source of truth
- If Watch sends "completeSet" but iPhone already advanced past that set: iPhone ignores, sends current state back
- If Watch has stale data (e.g., old workout plan): iPhone's applicationContext update overwrites
- Watch never persists data long-term. It holds only the latest snapshot.
```

### 5.4 Offline / Unreachable Handling

| Scenario | Watch Behavior |
|----------|---------------|
| iPhone not reachable, Watch has cached context | Show cached data with "Last updated: X min ago" in `tempo/text/tertiary-dark` |
| iPhone not reachable, user tries action | Queue action. Show "Queued. Will sync when connected." toast. |
| iPhone not reachable, no cached context | Show placeholder UI: "Open Tempo on iPhone to sync." |
| Workout in progress, iPhone disconnects | Watch continues tracking locally (set completions, rest timers). Queues all actions. Syncs when reconnected. |
| Focus timer running, iPhone disconnects | Timer continues on Watch (uses `WKExtendedRuntimeSession`). Session data sent to iPhone when reconnected. |

### 5.5 Bandwidth Optimization

- `applicationContext` only delivers the latest value (no queue buildup)
- `transferUserInfo` used only for full workout plans (infrequent, <5KB)
- Actions are tiny (<200 bytes each)
- No images transferred (exercise demos are phone-only)
- No audio or video
- Estimated daily data transfer: <50KB total in a typical day

---

## 6. Performance Targets

### 6.1 Launch Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cold launch to first meaningful content | <2.0 seconds | Time from tap to score ring visible with data |
| Warm launch (from suspended) | <0.5 seconds | Time from wrist raise to updated content |
| Complication tap to app view | <1.0 seconds | Time from complication tap to relevant view |

**Strategy:**
- Cache `applicationContext` in `UserDefaults` on Watch for instant display
- Load cached data synchronously on launch
- Refresh asynchronously when `WCSession` becomes active
- Pre-render complication views at compile time where possible

### 6.2 View Performance

| Metric | Target |
|--------|--------|
| View transition (page swipe) | <16ms per frame (60fps) |
| Set complete action -> visual update | <200ms |
| Rest timer countdown | Smooth 1-second ticks, no dropped frames |
| Digital Crown scroll | 60fps, no jank |

**Strategy:**
- All views use SwiftUI with minimal view hierarchy depth
- No heavy computation on the main thread
- Workout state updates via `@Published` properties on an `@Observable` service
- Timer uses `TimelineView` (not manual Timer-based updates)

### 6.3 Memory

| Metric | Target |
|--------|--------|
| Peak memory usage | <30MB |
| Typical memory usage | <20MB |
| Workout plan in memory | <500KB (even for 10+ exercises) |

**Strategy:**
- No images loaded (text + SF Symbols only)
- No SwiftData on Watch (all data from iPhone via lightweight Codable structs)
- No networking stack (no URLSession, no JSON decoders for API responses)

### 6.4 Battery Impact

| Usage Pattern | Target Battery Impact |
|---------------|----------------------|
| Complications only (no app launch) | <2% per day |
| 1 workout session (45 min active use) | <5% additional |
| 3 focus timer sessions (75 min screen on) | <8% additional |
| Typical full day (complications + 1 workout + 2 timer sessions) | <12% total |

**Strategy:**
- Complications use `TimelineProvider` (system-managed updates, no background tasks)
- `WKExtendedRuntimeSession` only during active workout and focus timer
- No background refresh tasks (all updates come from iPhone via Watch Connectivity)
- Screen timeout follows system settings (Watch auto-sleeps)
- No continuous sensor polling from the Watch app (HealthKit data comes from iPhone snapshot)

---

## 7. Watch Notifications

### 7.1 Notification Strategy

**Decision: Mirror select iPhone notifications + Watch-specific actionable notifications**

Not all iPhone notifications belong on the Watch. The Watch should only buzz for things that require immediate awareness or quick action.

### 7.2 Notification Routing

| Notification Type | Mirror to Watch? | Watch-Specific? | Rationale |
|-------------------|-----------------|----------------|-----------|
| Accountability escalation (2 PM gentle) | Yes | No | User should see this wherever they look first |
| Accountability escalation (5 PM+ firm) | Yes | No | Same |
| Accountability escalation (7 PM+ aggressive) | Yes, with haptic emphasis | No | These are urgent. Watch ensures they are felt. |
| "All clear. Earned." | Yes | No | Positive reinforcement at any surface |
| Rest timer done | No (iPhone) | Yes (Watch-native) | Only Watch needs this -- user is at gym |
| Focus timer done | No (iPhone) | Yes (Watch-native) | Only Watch needs this -- phone should be away |
| Workout reminder | Yes | No | "You haven't trained yet. Recovery is green." |
| Meal time reminder | Yes | No | "Lunch in 15 min. Log it." |
| Streak milestone | Yes | No | Celebration notification |
| Arena: friend passed you | Yes | No | Social motivation |
| Arena: challenge ending soon | Yes | No | Urgency |
| Weekly AI report ready | No | No | Long-form content, phone only |
| Sleep recommendation | Yes | No | "Bedtime in 30 min. Recovery depends on it." |

### 7.3 Actionable Watch Notifications

These notifications include buttons the user can tap directly from the notification, without opening the app.

#### Set Complete Notification (during active workout)

If the user's wrist is down when the rest timer ends:

```
┌──────────────────────────────┐
│  TEMPO                       │
│  Rest over. Bench Press 3/4  │
│  8 reps × 80 kg              │
│                              │
│  ┌────────────────────────┐ │
│  │     COMPLETE SET        │ │  ← Completes set, starts next rest
│  └────────────────────────┘ │
│  ┌────────────────────────┐ │
│  │     +30 SECONDS         │ │  ← Extends rest
│  └────────────────────────┘ │
│                              │
│                  Dismiss     │
└──────────────────────────────┘
```

**Implementation:**

```swift
// UNNotificationCategory registration
let completeSetAction = UNNotificationAction(
    identifier: "COMPLETE_SET",
    title: "Complete Set",
    options: .foreground
)
let extendRestAction = UNNotificationAction(
    identifier: "EXTEND_REST",
    title: "+30 Seconds",
    options: []
)
let workoutCategory = UNNotificationCategory(
    identifier: "WORKOUT_SET",
    actions: [completeSetAction, extendRestAction],
    intentIdentifiers: [],
    options: []
)
```

#### Non-Negotiable Reminder

```
┌──────────────────────────────┐
│  TEMPO                       │
│  2 tasks left. 1830.         │
│  Study: 45 min short.        │
│                              │
│  ┌────────────────────────┐ │
│  │    START FOCUS TIMER    │ │  ← Opens Focus Timer view
│  └────────────────────────┘ │
│                              │
│                  Dismiss     │
└──────────────────────────────┘
```

#### Meal Confirmation

```
┌──────────────────────────────┐
│  TEMPO                       │
│  Dinner scheduled at 1930.   │
│                              │
│  ┌────────────────────────┐ │
│  │      ATE IT             │ │  ← Confirms meal eaten
│  └────────────────────────┘ │
│  ┌────────────────────────┐ │
│  │      SKIPPED            │ │  ← Marks as skipped
│  └────────────────────────┘ │
└──────────────────────────────┘
```

### 7.4 Notification Timing Considerations

- **Do Not Disturb / Sleep Focus:** Tempo respects system Focus modes. No Watch buzzing during sleep.
- **Workout mode:** During an active workout (`WKExtendedRuntimeSession`), only rest-timer and workout-related notifications fire. All other categories are suppressed until workout ends.
- **Rate limiting:** Maximum 1 Watch notification per 10 minutes for non-urgent categories. Accountability escalations can fire more frequently (they are intentionally persistent).

---

## 8. Live Activities on Watch (watchOS 11+)

Live Activities, introduced for Apple Watch in watchOS 11, allow Tempo to display persistent, real-time state on the Smart Stack and Lock Screen without the user opening the app.

### 8.1 Workout Live Activity

When a workout is in progress, a Live Activity appears in the Smart Stack showing the current exercise and set.

**Compact view (Smart Stack):**

```
┌──────────────────────────────┐
│ 🏋️ Bench Press  Set 2/4     │
│    8 reps × 80 kg  REST 1:14│
└──────────────────────────────┘
```

**Expanded view (tap to expand):**

```
┌──────────────────────────────┐
│  PUSH DAY         2 of 6    │
│                              │
│  Bench Press                 │
│  Set 2 of 4                 │
│  8 reps × 80 kg              │
│                              │
│  REST: 1:14                  │
│                              │
│  ┌────────────────────────┐ │
│  │     COMPLETE SET        │ │
│  └────────────────────────┘ │
└──────────────────────────────┘
```

**Implementation:**

```swift
struct WorkoutLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let exerciseName: String
        let exerciseOrder: Int
        let totalExercises: Int
        let setNumber: Int
        let totalSets: Int
        let targetReps: Int
        let targetWeight: Double?
        let restEndDate: Date?         // nil if not resting
        let isResting: Bool
        let workoutType: String
    }

    let workoutId: String
}
```

**Update cadence:**
- Set completed -> immediate update (exercise name, set number)
- Rest timer started -> update with `restEndDate` for system countdown
- Rest timer ended -> update to clear rest state
- Exercise transition -> update with new exercise info
- Workout finished -> end the Live Activity with final summary

### 8.2 Focus Timer Live Activity

During an active focus session, a Live Activity shows the remaining time.

**Compact view (Smart Stack):**

```
┌──────────────────────────────┐
│ 📖 Focus  18:42  Session 4  │
└──────────────────────────────┘
```

**Expanded view:**

```
┌──────────────────────────────┐
│  FOCUS SESSION 4             │
│                              │
│        18:42                 │
│                              │
│  Total today: 1h40m         │
│                              │
│  ┌──────────┐ ┌──────────┐ │
│  │  PAUSE   │ │  + 5 MIN │ │
│  └──────────┘ └──────────┘ │
└──────────────────────────────┘
```

**Implementation:**

```swift
struct FocusTimerLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date              // for system countdown
        let sessionNumber: Int
        let totalMinutesToday: Int
        let isPaused: Bool
        let pausedTimeRemaining: Int?  // seconds, when paused
    }

    let targetMinutes: Int
}
```

**Update cadence:**
- Timer started -> create Live Activity with `endDate`
- Timer paused -> update with `isPaused: true` and remaining seconds
- Timer resumed -> update with new `endDate`
- Timer extended -> update with new `endDate`
- Timer completed -> end with summary ("25 min logged. +25 XP.")

### 8.3 Live Activity Considerations

- Live Activities require iOS 16.1+ on iPhone and watchOS 11+ on Watch
- The iPhone creates and manages the Activity (via `ActivityKit`). The Watch mirrors it automatically.
- Live Activities are limited to 4 hours maximum (system limit). Workouts exceeding 4 hours will transition to a notification.
- The countdown timer in the rest period uses `Text(timerInterval:)` for system-managed, battery-efficient countdown rendering.

---

## 9. Screen Specifications

### 9.1 Display Sizes

| Watch Size | Screen Width | Screen Height | Pixels | Corner Radius |
|------------|-------------|---------------|--------|---------------|
| 41mm (Series 7-10, SE) | 176pt (352px @2x) | 215pt (430px @2x) | 352 x 430 | 36pt |
| 45mm (Series 7-10) | 198pt (396px @2x) | 242pt (484px @2x) | 396 x 484 | 40pt |
| 49mm (Ultra 1-2) | 205pt (410px @2x) | 251pt (502px @2x) | 410 x 502 | 42pt |

### 9.2 Safe Areas and Margins

| Element | 41mm | 45mm | 49mm |
|---------|------|------|------|
| Leading/trailing margin | 8pt | 10pt | 12pt |
| Top safe area (below status bar) | 28pt | 28pt | 28pt |
| Bottom safe area | 14pt | 14pt | 14pt |
| Minimum tappable area | 38pt x 38pt | 38pt x 38pt | 38pt x 38pt |
| Recommended button height | 44pt | 50pt | 50pt |
| Primary action button height | 50pt | 56pt | 56pt |

### 9.3 Typography Per Screen (Size-Adapted)

#### Glance/Home View

| Element | 41mm | 45mm | 49mm | Font |
|---------|------|------|------|------|
| Score number (ring center) | 36pt | 40pt | 42pt | SF Pro Rounded Bold |
| Recovery zone label | 13pt | 15pt | 15pt | SF Pro Text Semibold |
| Next task name | 13pt | 15pt | 15pt | SF Pro Text Semibold |
| Next task status | 11pt | 12pt | 12pt | SF Pro Text Regular |
| PS5 status | 11pt | 13pt | 13pt | SF Pro Text Regular |
| NN progress label | 11pt | 12pt | 12pt | SF Mono Medium |
| Button text | 12pt | 13pt | 13pt | SF Pro Text Semibold |

#### Active Workout View

| Element | 41mm | 45mm | 49mm | Font |
|---------|------|------|------|------|
| Workout type header | 12pt | 13pt | 13pt | SF Pro Text Semibold |
| Exercise name | 15pt | 17pt | 17pt | SF Pro Text Bold |
| Set progress | 12pt | 14pt | 14pt | SF Pro Text Regular |
| Target (reps x weight) | 18pt | 20pt | 22pt | SF Mono Bold |
| "SET DONE" button text | 16pt | 18pt | 18pt | SF Pro Text Bold |
| Secondary button text | 13pt | 14pt | 14pt | SF Pro Text Semibold |

#### Rest Timer View

| Element | 41mm | 45mm | 49mm | Font |
|---------|------|------|------|------|
| "REST" header | 13pt | 14pt | 14pt | SF Pro Text Semibold |
| Timer countdown | 42pt | 48pt | 50pt | SF Mono Bold |
| Next set info | 12pt | 13pt | 13pt | SF Pro Text Regular |
| Button text | 13pt | 14pt | 14pt | SF Pro Text Semibold |

#### Focus Timer View

| Element | 41mm | 45mm | 49mm | Font |
|---------|------|------|------|------|
| "FOCUS" header | 13pt | 14pt | 14pt | SF Pro Text Semibold |
| Timer countdown | 42pt | 48pt | 50pt | SF Mono Bold |
| Session count | 12pt | 13pt | 13pt | SF Pro Text Regular |
| Button text | 13pt | 14pt | 14pt | SF Pro Text Semibold |

#### Recovery View

| Element | 41mm | 45mm | 49mm | Font |
|---------|------|------|------|------|
| Recovery score (ring center) | 28pt | 32pt | 34pt | SF Pro Rounded Bold |
| Zone label | 13pt | 14pt | 15pt | SF Pro Text Bold |
| Metric labels | 12pt | 13pt | 13pt | SF Pro Text Regular |
| Metric values | 13pt | 15pt | 15pt | SF Mono Semibold |
| Prescription text | 12pt | 13pt | 13pt | SF Pro Text Regular |

### 9.4 Button Specifications

All buttons on Watch must be easy to hit with wet or gloved fingers. Apple's HIG recommends minimum 44pt tap targets.

| Button Type | Width | Height (41mm) | Height (45mm/49mm) | Corner Radius | Padding |
|-------------|-------|---------------|-------------------|---------------|---------|
| Primary action ("SET DONE", "START") | Full width - 2x margin | 50pt | 56pt | 14pt | 16pt horizontal, 14pt vertical |
| Secondary action ("SKIP", "ADJUST") | (Full width - 2x margin - 8pt gap) / 2 | 38pt | 40pt | 10pt | 12pt horizontal, 10pt vertical |
| Tertiary / link ("+ 5 MIN", "+30s") | Full width - 2x margin | 36pt | 40pt | 10pt | 12pt horizontal, 8pt vertical |
| Quick log item (non-negotiable row) | Full width - 2x margin | 48pt | 52pt | 10pt | 12pt all sides |
| Meal confirm button | (Full width - 2x margin - 8pt gap) / 2 | 52pt | 56pt | 10pt | 8pt all sides |

**Button colors:**

| Button Type | Background | Text | Pressed State |
|-------------|------------|------|---------------|
| Primary destructive / action | `tempo/primary/signal-dark` (#FF4D5A) | White | 80% opacity |
| Primary positive | `tempo/semantic/success-dark` (#4ADE80) | `tempo/primary/ink` (#0D0D0D) | 80% opacity |
| Secondary | `tempo/surface/card-dark` (#1C1C1E) | `tempo/text/primary-dark` (#F5F2ED) | `tempo/surface/elevated-dark` (#3A3A3C) |
| Tertiary | `tempo/surface/card-dark` (#1C1C1E) | `tempo/accent/electric-dark` (#60A5FA) | `tempo/surface/elevated-dark` (#3A3A3C) |
| Disabled | `tempo/surface/card-dark` at 50% opacity | `tempo/text/disabled-dark` (#52525B) | No interaction |

### 9.5 Color Usage on Watch (OLED Optimization)

The Apple Watch uses an OLED display. Black pixels are truly off, consuming zero power. Tempo's dark mode palette is therefore the ONLY mode on Watch (there is no light mode for Watch).

**Rules:**
- Primary background: True black `#000000` (not Ink Black `#0D0D0D`). On OLED, `#000000` = pixels off = battery savings. Use `#0D0D0D` only for elements that need to be visually distinguishable from the bezel.
- Card surfaces: `tempo/surface/card-dark` (#1C1C1E) -- the slight elevation from true black makes cards visible.
- All accent colors use the `-dark` variants from the design system (brighter for contrast on dark backgrounds).
- Score ring, recovery ring: Use gradients. Gradients look exceptional on OLED because each pixel can be a different brightness.
- Avoid large areas of bright color -- they drain battery on OLED. Text and rings are fine. Full-color backgrounds are not.
- Signal Red buttons (primary action) are intentionally bright -- battery cost is acceptable for the most important tap target on screen.

**Watch-specific color tokens:**

| Token | Hex | Usage |
|-------|-----|-------|
| `tempo/watch/bg` | `#000000` | True black background (OLED off) |
| `tempo/watch/card` | `#1C1C1E` | Card / elevated surface |
| `tempo/watch/card-pressed` | `#3A3A3C` | Button press state |
| `tempo/watch/text-primary` | `#F5F2ED` | Primary text (Bone White) |
| `tempo/watch/text-secondary` | `#A1A1AA` | Secondary text |
| `tempo/watch/text-tertiary` | `#71717A` | Metadata, timestamps |
| All accent/semantic colors | Use `-dark` variants | Brighter for OLED contrast |

### 9.6 Navigation Pattern

**Root:** `TabView` with `.tabViewStyle(.verticalPage)` (watchOS 10+)

```swift
struct TempoWatchRootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GlanceHomeView()
                .tag(0)

            WorkoutView()
                .tag(1)

            FocusTimerView()
                .tag(2)

            QuickLogView()
                .tag(3)

            RecoveryView()
                .tag(4)
        }
        .tabViewStyle(.verticalPage)
        .onOpenURL { url in
            // Handle complication deep links
            if url.host == "workout" { selectedTab = 1 }
            if url.host == "timer" { selectedTab = 2 }
            if url.host == "recovery" { selectedTab = 4 }
        }
    }
}
```

**Within each page:**
- `NavigationStack` for drill-down views (e.g., Glance -> Arena Glance)
- No nested `TabView`s. Keep navigation flat.
- Digital Crown scrolls content within a page.
- Swipe left from leading edge: standard watchOS back gesture.
- Long-press on workout title during active workout: shows "Finish Workout" option.

### 9.7 Layout Principles

1. **One primary action per screen.** The active workout screen has ONE big red button. Everything else is secondary.
2. **Maximum 3 taps to any action.** Raise wrist -> swipe to page -> tap button. Done.
3. **Vertical scrolling only.** No horizontal carousels, no grids. Single column, top to bottom.
4. **Score rings are the visual anchor.** The daily score ring and recovery ring are the largest elements on their respective screens. They communicate state at a glance, before the user reads any text.
5. **No text paragraphs.** Maximum 2 lines of body text anywhere on Watch. If it needs more, it belongs on the phone.
6. **Generous vertical spacing.** 12pt between card elements, 16pt between sections. Cramped layouts feel hostile on a small screen.
7. **SF Symbols over text labels where possible.** A checkmark icon is faster to parse than "Completed" text. Use `symbolVariant(.fill)` for active states, `.none` for inactive.

---

## Appendix A: Watch App Icon

The Watch app icon follows the same design as the iOS app icon but rendered for Watch sizes:

| Size | Pixels | Usage |
|------|--------|-------|
| 1024x1024 | @1x | App Store (Watch) |
| 108x108 | @2x 54pt | Watch home screen (38mm) |
| 120x120 | @2x 60pt | Watch home screen (42mm) |
| 129x129 | @2x 64.5pt | Watch home screen (45mm) |
| 132x132 | @2x 66pt | Watch home screen (49mm Ultra) |

Design: Same Commander Black background, Signal Red 75% ring, Bone White "T" -- unchanged from iOS. The bold, high-contrast design reads well at Watch icon sizes.

---

## Appendix B: Development Phases

| Phase | Scope | Depends On (iOS) |
|-------|-------|-------------------|
| **Watch Phase 1** | Complications + Glance Home View + Watch Connectivity plumbing | iOS Phase 1 (Foundation) |
| **Watch Phase 2** | Workout View (full active workout flow) | iOS Phase 3 (Training) |
| **Watch Phase 3** | Focus Timer View + Quick Log View | iOS Phase 4 (Accountability) |
| **Watch Phase 4** | Recovery View + Notification actions | iOS Phase 2 (Whoop + Recovery) |
| **Watch Phase 5** | Arena Glance + Live Activities (watchOS 11) | iOS Phase 6 (Arena) |
| **Watch Phase 6** | Polish -- haptic tuning, performance optimization, edge cases | iOS Phase 7 (AI + Polish) |

Each Watch phase should be developed and tested alongside its corresponding iOS phase. The Watch app should never ship features that the iPhone app does not yet support.

---

## Appendix C: Testing Considerations

- **Physical device testing is mandatory.** The Simulator does not accurately reproduce haptics, Digital Crown feel, wrist-raise behavior, or real Watch Connectivity latency.
- **Test with wet hands.** The workout flow must work when the user's fingers are sweaty. Buttons must be large enough to hit reliably.
- **Test at the gym.** Fluorescent lighting, arm movements, between-set distraction -- this is the real environment.
- **Test all 3 Watch sizes.** Layout must not break on 41mm (smallest). Content must not feel empty on 49mm Ultra (largest).
- **Test iPhone disconnection.** Put iPhone in airplane mode during a workout. Verify queued actions sync correctly when reconnected.
- **Test complication freshness.** Verify complications update within 5 seconds of a score change on iPhone.
- **Battery profiling.** Run Instruments with the Energy Log template during a full workout session. Verify <5% drain target.
