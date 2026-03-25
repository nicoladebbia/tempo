# Tempo -- Formal State Machine Specifications

> **Version:** 1.1
> **Last Updated:** 2026-03-24
> **Author:** Formal Methods Specification (v1.1: Formal Verification Pass)
> **Status:** Definitive Reference
> **Purpose:** Eliminate "impossible state" bugs by formally defining every stateful feature in Tempo.

Every state machine in this document follows a rigorous format:
- **States**: exhaustive enumeration with descriptions
- **Transitions**: trigger event, guard condition, action performed
- **Entry/Exit actions**: side effects on entering/leaving a state
- **Error states and recovery paths**: what happens when things go wrong
- **Timeout handling**: what happens when the clock runs out
- **Persistence strategy**: what survives app kill
- **UI mapping**: which screen/component corresponds to each state
- **Notification triggers**: which transitions fire notifications
- **Analytics events**: which transitions are tracked

---

## Table of Contents

1. [Workout Session](#1-workout-session)
2. [Focus Timer](#2-focus-timer)
3. [Daily Accountability](#3-daily-accountability)
4. [Whoop Sync](#4-whoop-sync)
5. [NutriTrack Sync](#5-nutritrack-sync)
6. [Non-Negotiable Item](#6-non-negotiable-item)
7. [Streak](#7-streak)
8. [Challenge](#8-challenge)
9. [Friend Request](#9-friend-request)
10. [Onboarding](#10-onboarding)
11. [Push Notification Escalation](#11-push-notification-escalation)
12. [Workout Plan Generation](#12-workout-plan-generation)
13. [Recovery Prescription](#13-recovery-prescription)
14. [App Sync Orchestrator](#14-app-sync-orchestrator)
15. [Subscription](#15-subscription)
16. [Exercise Set](#16-exercise-set)

---

## 1. Workout Session

The most safety-critical state machine in Tempo. An active workout involves real-time timer management, set persistence, crash recovery, phone call interruption, and Live Activity coordination. A bug here means lost workout data.

### State Diagram

```
                        +-----------+
                        |   idle    |
                        +-----+-----+
                              |
                     [user taps START WORKOUT]
                              |
                        +-----v-----+
                        |  warmup   |<--------------------------+
                        +-----+-----+                           |
                              |                                 |
                  [warmup sets complete                         |
                   OR no warmup configured]                     |
                              |                                 |
                        +-----v-----+                           |
                   +--->| exercise  |<------+                   |
                   |    +-----+-----+       |                   |
                   |          |             |                   |
                   |    (concurrent region) |                   |
                   |    +-------------------+---+               |
                   |    |                       |               |
                   |    v                       v               |
                   | +----------+    +------------------+       |
                   | |set_active|    | between_exercises|-------+
                   | +----+-----+    +------------------+
                   |      |
                   |      | [set logged]
                   |      v
                   | +----------+
                   | | resting  |
                   | +----+-----+
                   |      |
                   |      | [rest complete OR skipped]
                   |      |
                   +------+
                              |
                   [all exercises complete OR user taps FINISH]
                              |
                        +-----v-----+
                        | cooldown  |
                        +-----+-----+
                              |
                        +-----v-----+
                        |  summary  |
                        +-----+-----+
                              |
                     [user taps SAVE / auto-save]
                              |
                        +-----v-----+
                        |   saved   |
                        +-----------+

  === Interruption overlay (orthogonal region) ===

  Any state in {warmup, exercise.setActive, exercise.resting,
  exercise.betweenExercises, cooldown} can transition to:

        +----------+     [resume]      +----------------+
        |  paused  |<----------------->| previous state |
        +----+-----+                   +----------------+
             |
             +--- [End & Discard] ---> +-----------+
             |                         | discarded |
             +--- [End & Save]   ---> +-----------+
                                       | summary   |
                                       +-----------+

        +-------------------+     [call ends]     +----------------+
        | interrupted_call  |<------------------->| previous state |
        +-------------------+                     +----------------+
             |
             | [call > 10 min]
             v
        +----------+
        |  paused  |
        +----------+

        +-------------------+
        | crashed_recovery  |  (app relaunched with persisted state)
        +-------------------+
```

### States

| State | Description |
|-------|-------------|
| `idle` | No active workout. Default state on app launch (unless crash recovery needed). |
| `warmup` | User is performing warmup sets for the first exercise. |
| `exercise` | User is working through exercises. Contains sub-states. |
| `exercise.setActive` | A working set is in progress (weight/reps inputs visible, DONE button active). |
| `exercise.resting` | Rest timer counting down between sets or after a set. |
| `exercise.betweenExercises` | Transitioning from one exercise to the next (animation/auto-advance). |
| `cooldown` | All exercises complete. Final rest timer (skippable). Celebration animations. |
| `summary` | Post-workout summary screen. Stats, PRs, ring animation. |
| `saved` | Workout persisted to SwiftData and synced to backend. Terminal state. |
| `paused` | Workout timer halted. User initiated or auto-pause (10 min inactivity). |
| `interrupted_call` | Phone call active. Timer paused. Set state frozen. |
| `crashed_recovery` | App relaunched and found persisted in-progress workout in SwiftData. |
| `discarded` | User chose "End & Discard." No data saved. Terminal state. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `idle` | `warmup` | User taps START WORKOUT | Workout plan exists for today | Start workout timer; create `WorkoutSession` in SwiftData; start Live Activity; disable idle timer; log `workout.started` |
| `idle` | `exercise.setActive` | User taps START WORKOUT | Workout has no warmup configured | Same as above but skip warmup |
| `idle` | `crashed_recovery` | App launch | `WorkoutSession` with `isActive == true` found in SwiftData | Show recovery banner: "Resume your workout?" |
| `crashed_recovery` | `exercise.setActive` | User taps Resume | Always | Restore timer from persisted elapsed time; restore current exercise/set index; restart Live Activity |
| `crashed_recovery` | `discarded` | User taps Discard | Always | Delete incomplete `WorkoutSession`; clear Live Activity |
| `warmup` | `exercise.setActive` | All warmup sets logged | `currentExercise.warmupSetsRemaining == 0` | Transition to first working set; update Live Activity |
| `warmup` | `exercise.resting` | Warmup set logged (not last) | `currentExercise.warmupSetsRemaining > 0` (more warmup sets remain, rest between them) | Start 60s rest timer (or 90s if this is the last warmup set before working sets) |
| `exercise.setActive` | `exercise.resting` | User taps DONE (set complete) | `weight > 0 AND reps > 0` (Machine 16: set transitions to `completed`) OR `reps == 0` (Machine 16: set transitions to `failed`) | Persist set to SwiftData; update volume totals; check for PR (if completed, not failed); start rest timer; fire haptic `.success` or `.error`; update Live Activity |
| `exercise.resting` | `exercise.setActive` | Rest timer reaches 0 OR user taps Skip Rest | More sets remain for current exercise | Load next set inputs; fire haptic `.warning` (timer end) or `.light` (skip) |
| `exercise.resting` | `exercise.betweenExercises` | Rest timer reaches 0 OR skip | Current exercise has no more sets AND more exercises remain | Show "Next: {exercise name}" transition |
| `exercise.betweenExercises` | `exercise.setActive` | Transition animation complete (300ms) | Next exercise exists | Load next exercise; update header; reset set counter |
| `exercise.setActive` | `cooldown` | User taps DONE on last set of last exercise | `isLastSet && isLastExercise` | Start final rest timer (skippable); trigger celebration animation |
| `cooldown` | `summary` | Final rest complete OR user skips | Always | Calculate workout stats; detect PRs; generate summary data; stop workout timer |
| `summary` | `saved` | User taps Save & Close OR auto-save after 5 min | Always | Persist final `WorkoutSession`; sync to backend; write to HealthKit; end Live Activity; re-enable idle timer |
| Any active state (`warmup`, `exercise.setActive`, `exercise.resting`, `exercise.betweenExercises`, `cooldown`) | `paused` | User taps Pause | Workout is in active state | Pause workout timer; pause rest timer (if running); update Live Activity to paused; record `pausedFromState` |
| Any active state | `interrupted_call` | Phone call starts (CTCallCenter / CallKit) | Workout is in active state | Pause all timers; preserve exact set state; record `previousState` |
| Any active state | `paused` | No interaction for 10 min | `lastInteractionTime + 10min < now` | Auto-pause; show "PAUSED" overlay; fire notification: "Still working out?" |
| `paused` | Previous active state | User taps Resume | Always | Resume workout timer (excluding paused duration); resume rest timer; update Live Activity |
| `interrupted_call` | Previous active state | Phone call ends (CTCallCenter / CallKit) | Always | Resume all timers from persisted elapsed time; update Live Activity |
| `interrupted_call` | `paused` | Phone call ends AND auto-pause threshold passed | `callDuration > 10min` | Transition to paused instead of auto-resuming; show "PAUSED" overlay |
| `paused` | `discarded` | User taps End & Discard | Confirmation accepted | Delete `WorkoutSession`; end Live Activity |
| `paused` | `summary` | User taps End & Save | Confirmation accepted | Same as cooldown -> summary but skip final rest |
| `summary` | `saved` | _see above_ | _see above_ | **Cross-machine trigger:** On save, emit `WorkoutCompleted` event -> Machine 8 (Challenge) updates scores; Machine 7 (Streak) updates daily progress via non-negotiable completion; Machine 14 (App Sync) queues backend sync |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `warmup` | Load first warmup set (50% of working weight); show WARM-UP label | -- |
| `exercise.setActive` | Pre-fill weight (sticky from previous set or target); pre-fill reps; show plate hint; update exercise progress bar | Persist current set data to SwiftData |
| `exercise.resting` | Start rest timer; show countdown circle (200pt); if superset: skip rest, show banner "No rest"; update Live Activity with countdown | Stop rest timer if running |
| `cooldown` | Trigger confetti if PRs hit; triple haptic pulse; show final rest timer | -- |
| `summary` | Calculate all stats; ring fill animation (800ms); show PR badges | -- |
| `paused` | Freeze all timers; record pause start time; update Live Activity; re-enable idle timer | Record pause duration; subtract from total time |
| `interrupted_call` | Pause all timers; preserve exact set state; record `callStartTime` and `previousState` | Calculate call duration; subtract from workout time |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| Paused with no interaction | 2 hours | Auto-save workout as incomplete; end Live Activity; transition to `saved` with `isComplete: false` |
| Rest timer | Configured duration (default 90-180s) | Transition to next set; fire haptic + notification if backgrounded |
| Backgrounded during rest | N/A | Timer continues via Date diff on foreground return |
| Crash recovery prompt | 30 seconds after app relaunch | Auto-resume (do not auto-discard) |
| Summary screen with no interaction | 5 minutes | Auto-save workout; transition to `saved`; end Live Activity |
| Interrupted call with no end event | 30 minutes | Transition to `paused`; fire notification: "Still working out?" |

### Swift Enum

```swift
enum WorkoutSessionState: Codable, Equatable {
    case idle
    case warmup(exerciseIndex: Int, warmupSetIndex: Int)
    case exercise(ExerciseSubState)
    case cooldown
    case summary
    case saved
    case paused(previousState: PausedFromState, pauseStartTime: Date)
    case interruptedCall(previousState: PausedFromState)
    case crashedRecovery
    case discarded

    enum ExerciseSubState: Codable, Equatable {
        case setActive(exerciseIndex: Int, setIndex: Int)
        case resting(exerciseIndex: Int, setIndex: Int, remainingSeconds: TimeInterval)
        case betweenExercises(fromIndex: Int, toIndex: Int)
    }

    enum PausedFromState: Codable, Equatable {
        case warmup(exerciseIndex: Int, warmupSetIndex: Int)
        case exercise(ExerciseSubState)
        case cooldown
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `WorkoutSession.state: WorkoutSessionState` | YES |
| `startTime` | `WorkoutSession.startedAt: Date` | YES |
| `elapsedTime` | `WorkoutSession.elapsedSeconds: TimeInterval` | YES (updated every set completion) |
| `completedSets` | `WorkoutSession.sets: [CompletedSet]` | YES (appended on each DONE tap) |
| `currentExerciseIndex` | `WorkoutSession.currentExerciseIndex: Int` | YES |
| `currentSetIndex` | `WorkoutSession.currentSetIndex: Int` | YES |
| `pauseDuration` | `WorkoutSession.totalPauseDuration: TimeInterval` | YES |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `idle` | `TodaysWorkoutView` -- START WORKOUT button visible |
| `warmup` | `ActiveWorkoutView` -- WARM-UP label, reduced weight shown |
| `exercise.setActive` | `ActiveWorkoutView` -- weight/reps inputs, DONE button |
| `exercise.resting` | `ActiveWorkoutView` -- 200pt countdown circle overlay |
| `exercise.betweenExercises` | `ActiveWorkoutView` -- horizontal slide animation |
| `cooldown` | `ActiveWorkoutView` -- celebration + final rest |
| `summary` | `WorkoutSummaryView` -- stats, PRs, ring animation |
| `saved` | Return to `TodaysWorkoutView` or `DashboardView` |
| `paused` | `ActiveWorkoutView` -- "PAUSED" overlay, Resume button |
| `crashed_recovery` | `ActiveWorkoutView` -- "Resume your workout?" banner |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| Active -> paused (auto-pause) | "Still working out? Tap to continue." |
| `exercise.resting` timer ends (backgrounded) | "Rest over -- Set {n} ready" |
| `summary` (with PR) | "New PR! {exercise}: {weight}kg x {reps}" |
| `paused` timeout (2h) | "Workout auto-saved. You were away for a while." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `workout.started` | `workoutType`, `exerciseCount`, `recoveryScore` |
| `workout.set_completed` | `exerciseId`, `setIndex`, `weight`, `reps`, `isPR` |
| `workout.paused` | `reason: manual | auto_pause | phone_call` |
| `workout.resumed` | `pauseDuration` |
| `workout.completed` | `totalDuration`, `totalVolume`, `prCount`, `setCount` |
| `workout.discarded` | `completedSets`, `reason` |
| `workout.crash_recovered` | `setsBeforeCrash`, `elapsedBeforeCrash` |

---

## 2. Focus Timer

The Pomodoro/focus system is a multi-phase timer with session tracking, break management, and focus scoring. It must handle backgrounding gracefully since students lock their phones while studying.

### State Diagram

```
                    +--------------+
                    | idle         |
                    +------+-------+
                           |
                  [user taps Start / configures]
                           |
                    +------v-------+
                    | configuring  |
                    +------+-------+
                           |
                  [configuration confirmed / timer starts]
                           |
                    +------v-------+
               +--->| focusing     |<-----------+
               |    +------+-------+            |
               |           |                    |
               |    [timer reaches 0:00]        |
               |           |                    |
               |    +------v-------+            |
               |    | session_done |-----+      |
               |    +------+-------+     |      |
               |           |             |      |
               |   [normal break]  [long break  |
               |           |       interval]    |
               |    +------v-------+     |      |
               |    | on_break     |     |      |
               |    +------+-------+     |      |
               |           |             |      |
               |    [break timer 0:00]   |      |
               |           |             |      |
               |    +------v-------+     |      |
               |    | break_done   |     |      |
               |    +------+-------+     |      |
               |           |             |      |
               |           |       +-----v----+ |
               |           |       |long_break| |
               |           |       +-----+----+ |
               |           |             |      |
               |           +------+------+      |
               |                  |             |
               |           [more sessions       |
               |            remaining] ---------+
               |                  |
               |           [all sessions
               |            complete or
               |            last session]
               |                  |
               |           +------v-------+
               |           | completed    |
               |           +------+-------+
               |                  |
               |           +------v-------+
               |           | review       |
               |           +--------------+

  === Orthogonal pause region ===

  {focusing, on_break, long_break} can enter:

        +-----------+
        |  paused   |
        +-----------+

  === Orthogonal cancel region ===

  Any non-terminal state can enter:

        +-----------+
        | cancelled |
        +-----------+
```

### States

| State | Description |
|-------|-------------|
| `idle` | No timer active. Default state. |
| `configuring` | User is selecting session type, subject, duration. Timer not started. |
| `focusing` | Focus countdown running. Screen stays on. Auto-lock disabled. |
| `sessionDone` | Focus period ended. Awaiting break start (auto or manual). |
| `onBreak` | Short break countdown running. Motivational message shown. |
| `breakDone` | Break ended. Awaiting next focus session start. |
| `longBreak` | Long break after N sessions (default 4). Longer duration. |
| `completed` | All planned sessions finished. Celebration overlay. |
| `review` | Session summary with focus score, total time, distraction count. |
| `paused` | Timer frozen. Colon blinks. Pause duration tracked. |
| `cancelled` | User stopped and discarded. Partial time may be saved. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `idle` | `configuring` | User opens Focus Timer view | Always | Load last-used settings; show session type picker |
| `configuring` | `focusing` | User taps Start / Resume | Subject selected (or "No Subject") | Start countdown; disable idle timer; start Live Activity; log `focus.session_started` |
| `focusing` | `sessionDone` | Timer reaches 0:00 | Always | Fire completion haptic + sound; record session duration; calculate partial focus score |
| `focusing` | `paused` | User taps Pause | Timer is running | Freeze timer; record pause start; enable idle timer; blink colon |
| `paused` | `focusing` | User taps Resume | Previous state was focusing | Resume countdown; disable idle timer; record pause duration |
| `paused` | `onBreak` | User taps Resume | Previous state was onBreak | Resume break countdown |
| `paused` | `cancelled` | User taps Stop & Discard | Confirmation accepted | Discard session time (or save partial if > 5 min) |
| `sessionDone` | `onBreak` | Auto-start (3s countdown) OR user taps Start Break | (`autoStartBreaks == true` OR manual tap) AND `sessionIndex % longBreakInterval != 0` | Start short break countdown; show motivational message; change ring to green |
| `sessionDone` | `longBreak` | Auto-start OR user taps Start Break | `sessionIndex % longBreakInterval == 0` AND `sessionIndex < totalSessions` | Start long break with extended duration; show "Long Break" label |
| `sessionDone` | `focusing` | User taps Skip Break | `sessionIndex < totalSessions` | Increment session counter; start next focus countdown |
| `sessionDone` | `completed` | All sessions done | `sessionIndex >= totalSessions` | Fire celebration; calculate final focus score |
| `onBreak` | `breakDone` | Break timer reaches 0:00 | Always | Fire break-end haptic; show "Start Focus" button |
| `breakDone` | `focusing` | Auto-start OR user taps Start Focus | `sessionIndex < totalSessions` | Increment session counter; start focus countdown |
| `breakDone` | `completed` | All sessions done | `sessionIndex >= totalSessions` | Fire celebration; calculate final focus score |
| `longBreak` | `focusing` | Long break ends OR user skips | `sessionIndex < totalSessions` | Start next focus session |
| `longBreak` | `completed` | All sessions done | `sessionIndex >= totalSessions` | Same as breakDone -> completed |
| `longBreak` | `paused` | User taps Pause | Timer is running | Freeze timer; record pause start; enable idle timer |
| `paused` | `longBreak` | User taps Resume | Previous state was longBreak | Resume long break countdown |
| `completed` | `review` | Celebration overlay dismissed OR auto-dismiss after 5s | Always | Display focus score, total time, distraction count |
| `review` | `idle` | User taps DONE | Always | Save session to SwiftData; update daily study total; end Live Activity; **Cross-machine trigger:** emit `FocusSessionCompleted` -> Machine 6 (Non-Negotiable) updates study-hours progress; Machine 7 (Streak) re-evaluates daily completion; Machine 8 (Challenge) updates `studyHours` metric if active |
| `focusing` | `cancelled` | User taps Stop & Save | Confirmation accepted, elapsed > 5 min | Save partial time; update study total; end Live Activity |
| `focusing` | `cancelled` | User taps Stop & Discard | Confirmation accepted, elapsed <= 5 min | Discard; end Live Activity |
| Any active | `paused` | App backgrounded | Timer running | Timer continues via Date diff (not actual background timer); push notification scheduled for session end |
| `paused` | Previous state | App foregrounded | Timer should still be running | Calculate elapsed from Date diff; if timer should have ended, transition to sessionDone/breakDone |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `focusing` | Disable idle timer; start Live Activity; set background blue gradient; increment `focusingStartTime` | Record elapsed focus time |
| `onBreak` | Change ring to green; show motivational quote; enable idle timer | -- |
| `longBreak` | Show "Long Break" label; extended duration | -- |
| `paused` | Record `pauseStartTime`; blink colon; enable idle timer | Record pause duration; add to `totalPauseDuration` |
| `completed` | Triple haptic; celebration overlay; checkmark animation | -- |
| `review` | Calculate focus score from: distraction count, pause frequency, pause ratio, completion % | Persist `FocusSession` to SwiftData |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| Paused with no interaction | 30 minutes | Auto-save partial session; transition to `cancelled` with `savedPartialTime` if elapsed > 5 min, otherwise transition to `idle` |
| Configuring with no interaction | 10 minutes | Transition to `idle`; discard unsaved configuration |
| Timer expires while backgrounded | N/A | Handled via local notification + Date diff on foreground |
| Break expires while backgrounded | N/A | Same; on foreground, show "Break's over" overlay |
| `sessionDone` / `breakDone` with no interaction | 5 minutes | Auto-start next phase (break or focus); if `autoStartBreaks == false`, fire notification: "Ready for the next session?" |

### Swift Enum

```swift
enum FocusTimerState: Codable, Equatable {
    case idle
    case configuring(sessionType: SessionType, subject: String?)
    case focusing(session: Int, totalSessions: Int, remainingSeconds: TimeInterval)
    case sessionDone(session: Int)
    case onBreak(session: Int, remainingSeconds: TimeInterval)
    case breakDone(session: Int)
    case longBreak(session: Int, remainingSeconds: TimeInterval)
    // NOTE: `onBreak` is for short breaks only. `longBreak` is a separate state.
    // Do NOT use `isLongBreak` flag -- the type system enforces the distinction.
    case completed(totalSessions: Int, totalFocusTime: TimeInterval)
    case review(focusScore: Int, totalTime: TimeInterval, distractions: Int)
    case paused(previousPhase: FocusPhase, pauseStartTime: Date)
    case cancelled(savedPartialTime: TimeInterval?)

    enum FocusPhase: Codable, Equatable {
        case focusing(session: Int, remainingSeconds: TimeInterval)
        case onBreak(session: Int, remainingSeconds: TimeInterval)
        case longBreak(session: Int, remainingSeconds: TimeInterval)
    }

    enum SessionType: String, Codable {
        case pomodoro       // 25/5
        case longFocus      // 50/10
        case deepWork       // 90/20
        case custom
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `FocusSession.state: FocusTimerState` | YES |
| `startTime` | `FocusSession.startedAt: Date` | YES |
| `subject` | `FocusSession.subject: String?` | YES |
| `accumulatedFocusTime` | `FocusSession.accumulatedFocusSeconds: TimeInterval` | YES |
| `distractionCount` | `FocusSession.distractions: Int` | YES |
| `pauseCount` | `FocusSession.pauseCount: Int` | YES |
| `totalPauseDuration` | `FocusSession.totalPauseDuration: TimeInterval` | YES |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `idle` | Study card on Lockdown Main View with "Start Timer" button |
| `configuring` | Timer Settings Sheet (session type, subject, durations) |
| `focusing` | Full-screen `FocusTimerView` -- blue ring, countdown, PAUSE button |
| `onBreak` / `longBreak` | `FocusTimerView` -- green ring, motivational quote |
| `paused` | `FocusTimerView` -- blinking colon, RESUME button, amber phase label |
| `completed` | `FocusTimerView` -- celebration overlay |
| `review` | `FocusTimerView` -- focus score, stats summary, DONE button |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| `focusing` timer ends (backgrounded) | "Focus session complete! Time for a break." (sound: completion chime) |
| `onBreak` timer ends (backgrounded) | "Break's over. Ready for the next session?" |
| `longBreak` timer ends (backgrounded) | "Long break's over. {remaining} sessions left." |
| `completed` | "All study sessions complete! {totalTime} of focused study." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `focus.session_started` | `sessionType`, `subject`, `focusDuration`, `sessionNumber` |
| `focus.session_completed` | `actualDuration`, `focusScore`, `distractions`, `pauseCount` |
| `focus.session_cancelled` | `elapsed`, `reason: discard | save_partial` |
| `focus.break_skipped` | `breakType: short | long` |
| `focus.distraction_tapped` | `count`, `sessionElapsed` |

---

## 3. Daily Accountability

The Lockdown module's daily lifecycle. Governs the entire day from morning setup through unlock/fail, including mid-day mode switches (exam mode, sick day).

### State Diagram

```
    +-------------------+
    | morning_setup     |  (00:00 - configurable morning time)
    +--------+----------+
             |
    [morning briefing notification fired OR user opens app]
             |
    +--------v----------+
    | tracking          |<------+
    +--------+----------+       |
             |                  |
    [completion > 50% but      [mode override:
     time > halfway to PS5]     sick/rest/exam]
             |                  |
    +--------v----------+  +----v---------+
    | approaching       |  | override     |
    | _deadline         |  | _active      |
    +--------+----------+  +--------------+
             |
    [< 30 min to PS5 time, tasks incomplete]
             |
    +--------v----------+
    | final_warning     |
    +--------+----------+
             |
        +----+----+
        |         |
  [all done] [PS5 time passed,
        |     tasks incomplete]
        |         |
  +-----v----+ +--v----------+
  | unlocked  | | day_failed  |
  +-----+----+ +--+----------+
        |         |
        +----+----+
             |
    [23:59 or user opens review next day]
             |
    +--------v----------+
    | review            |
    +-------------------+
```

### States

| State | Description |
|-------|-------------|
| `morningSetup` | Day has not started yet. Non-negotiables loaded from configuration. Waiting for morning briefing trigger. |
| `tracking` | Active tracking period. Non-negotiable cards visible. Progress updating from integrations (Whoop, NutriTrack, timer). |
| `approachingDeadline` | Time is > 50% toward PS5 time AND completion < 100%. Notifications escalate from Tier 1 to Tier 2. |
| `finalWarning` | < 30 min to PS5 time. Tier 3-4 notifications. Red pulse on lock icon. |
| `unlocked` | All non-negotiables complete. Lock animates to open. Confetti. "You earned it." |
| `dayFailed` | PS5 time passed with incomplete tasks. Streak at risk. Red state. |
| `overrideActive` | Sick day, rest day, or exam mode activated. Normal tracking suspended or modified. |
| `review` | End-of-day or next-morning review. Stats, streak update, weekly context. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `morningSetup` | `tracking` | Morning briefing fires OR user opens Lockdown tab | Current time >= morning briefing time | Load today's non-negotiables; start integration syncs; set app badge to incomplete count |
| `tracking` | `approachingDeadline` | Timer tick (every 60s) | `completionPercent < 100 && timeToPS5 < (totalDayWindow * 0.5)` | Increase notification tier; update time remaining display |
| `tracking` | `unlocked` | Non-negotiable completion | `allNonNegotiables.allSatisfy { $0.isComplete }` | Lock -> unlock animation; confetti; triple haptic; sound chime; update streak; award XP |
| `approachingDeadline` | `unlocked` | Non-negotiable completion | All complete | Same as above |
| `approachingDeadline` | `finalWarning` | Timer tick | `timeToPS5 < 30.minutes` | Fire Tier 3/4 notifications; red pulse on lock icon |
| `finalWarning` | `unlocked` | Non-negotiable completion | All complete | "Better late than never" variant; reduced celebration |
| `finalWarning` | `dayFailed` | PS5 time reached | `currentTime >= ps5Time && !allComplete` | "PS5 time passed. Tasks still incomplete."; XP penalty queued; streak at risk |
| `dayFailed` | `unlocked` | Non-negotiable completion (after PS5 time) | All complete, current day | "Unlocked. Better late than never."; streak preserved; reduced XP penalty |
| Any non-terminal | `overrideActive` | User activates sick day / rest day / exam mode | Before 12:00 noon (sick/rest) OR any time (exam) | Suspend or modify non-negotiables; prevent XP penalties; preserve streak; log override reason; **Cross-machine trigger:** Machine 11 (Notification Escalation) -> `resolved` with reason `overrideActivated` |
| `overrideActive` | `tracking` | Override deactivated | User explicitly cancels AND `currentTime < ps5Time` | Restore normal non-negotiables (exam mode modifies targets instead) |
| `overrideActive` | `review` | Day ends (23:59) | Override still active at day boundary | Calculate daily stats with override rules; streak preserved; XP adjusted per override type |
| `approachingDeadline` | `tracking` | Task auto-uncompleted or target increased | `completionPercent >= 100` was true but target changed OR `timeToPS5 >= (totalDayWindow * 0.5)` due to PS5 time adjustment | Re-evaluate notification tier; update time display |
| `tracking` / `unlocked` / `dayFailed` | `review` | Day ends (23:59) OR user opens next day | Always at day boundary | Calculate daily stats; update streak; calculate XP; generate review data |
| `review` | `morningSetup` (next day) | New day begins | `currentDate > reviewDate` | Reset all non-negotiable progress; load new day configuration |
| `tracking` | `tracking` | Timezone change detected | `TimeZone.current != storedTimezone` | Recalculate PS5 time; adjust notification schedule; log `accountability.timezone_changed` |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `morningSetup` | Load non-negotiable config; schedule morning briefing notification | -- |
| `tracking` | Start periodic sync (Whoop/NutriTrack every 15 min); update progress bars; set badge count | -- |
| `approachingDeadline` | Start 60s timer for time-remaining updates; escalate notification tier | -- |
| `finalWarning` | Red pulse on lock icon; fire urgent notification; set badge count to remaining | -- |
| `unlocked` | Animate lock open; confetti (50 particles, 2s); triple haptic; chime; clear badge; persist unlock time | -- |
| `dayFailed` | Red state on all UI; queue XP penalty for 23:59; send final notification | -- |
| `overrideActive` | Record override type + reason; adjust streak rules; modify XP rules | Restore normal rules |
| `review` | Calculate: total completion %, per-task stats, streak update, XP earned/lost | Persist `DailyAccountabilityRecord` |

### Swift Enum

```swift
enum DailyAccountabilityState: Codable, Equatable {
    case morningSetup(date: Date, nonNegotiableCount: Int)
    case tracking(completedCount: Int, totalCount: Int)
    case approachingDeadline(completedCount: Int, totalCount: Int, minutesToPS5: Int)
    case finalWarning(completedCount: Int, totalCount: Int, minutesToPS5: Int)
    case unlocked(unlockTime: Date, completionTime: Date)
    case dayFailed(completedCount: Int, totalCount: Int)
    case overrideActive(type: OverrideType, previousState: TrackingSnapshot)
    case review(date: Date, stats: DailyStats)

    enum OverrideType: String, Codable {
        case sickDay
        case restDay
        case mentalHealthDay
        case examMode
    }

    struct TrackingSnapshot: Codable, Equatable {
        let completedCount: Int
        let totalCount: Int
    }

    struct DailyStats: Codable, Equatable {
        let completionPercent: Double
        let streakUpdated: Bool
        let xpEarned: Int
        let xpPenalty: Int
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `DailyAccountability.state` | YES |
| `date` | `DailyAccountability.date: Date` | YES |
| `nonNegotiableProgress` | `DailyAccountability.items: [NonNegotiableProgress]` | YES |
| `overrideType` | `DailyAccountability.overrideType: OverrideType?` | YES |
| `unlockTime` | `DailyAccountability.unlockedAt: Date?` | YES |
| `ps5Time` | `DailyAccountability.configuredPS5Time: Date` | YES |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `morningSetup` | Lockdown Main View -- loading/skeleton state |
| `tracking` | Lockdown Main View -- cards with progress bars, LOCKED banner |
| `approachingDeadline` | Lockdown Main View -- countdown amber tint, escalating text |
| `finalWarning` | Lockdown Main View -- red pulse, urgent countdown |
| `unlocked` | Lockdown Main View -- green state, confetti, lock open |
| `dayFailed` | Lockdown Main View -- red state, "Handle your business" |
| `overrideActive` | Lockdown Main View -- grey state, override banner |
| `review` | Streak & Consistency View -- daily review card |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| -> `morningSetup` -> `tracking` | Tier 0: Morning Briefing |
| -> `approachingDeadline` | Tier 1: Gentle Reminder |
| Still in `approachingDeadline` | Tier 2: Firm Warning |
| -> `finalWarning` | Tier 3: Urgent Alert |
| Still in `finalWarning` (< 10 min) | Tier 4: Critical |
| -> `unlocked` | Tier 5: Celebration |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `accountability.day_started` | `date`, `nonNegotiableCount`, `isWeekend`, `isExamMode` |
| `accountability.task_completed` | `taskId`, `taskType`, `completionMethod: auto | manual`, `timeOfDay` |
| `accountability.unlocked` | `unlockTime`, `minutesBeforePS5`, `completionOrder` |
| `accountability.day_failed` | `completedCount`, `totalCount`, `missedTasks` |
| `accountability.override_activated` | `type`, `timeOfDay` |
| `accountability.timezone_changed` | `from`, `to`, `adjustmentMinutes` |

---

## 4. Whoop Sync

The Whoop integration is a backend-mediated OAuth2 flow with token lifecycle management. This state machine covers the entire connection lifecycle from the iOS client's perspective.

### State Diagram

```
    +--------------+
    | disconnected |<-----------+
    +------+-------+            |
           |                    |
    [user taps Connect Whoop]   |
           |                    |
    +------v-------+            |
    | authorizing  |            |
    +------+-------+            |
           |                    |
    [OAuth success]             |
           |                    |
    +------v-------+            |
    | connected    |            |
    +------+-------+            |
           |                    |
     (concurrent sub-states)    |
     +---------+---------+      |
     |         |         |      |
     v         v         v      |
  +------+ +------+ +-------+  |
  |syncing| | idle | | error |  |
  +------+ +------+ +-------+  |
                                |
     [token expires]            |
           |                    |
    +------v-------+            |
    | token_expired|            |
    +------+-------+            |
           |                    |
    [backend refreshes]         |
           |                    |
    +------v-------+            |
    | refreshing   |----+       |
    +------+-------+    |       |
           |            |       |
    [refresh success]  [refresh failed /
           |            token revoked]
    +------v-------+    |       |
    | connected    |    +-------+
    +--------------+
```

### States

| State | Description |
|-------|-------------|
| `disconnected` | No Whoop connection. User has not authorized or has been disconnected. |
| `authorizing` | OAuth2 flow in progress. ASWebAuthenticationSession open. |
| `connected` | Whoop is linked. Tokens are valid. Parent state for sub-states. |
| `connected.syncing` | Actively fetching data from Whoop API via backend. |
| `connected.idle` | Connected and data is fresh. No active sync. |
| `connected.error` | Connected but last sync failed (network, API error). Retry scheduled. |
| `tokenExpired` | Access token expired. Refresh needed before next API call. |
| `refreshing` | Backend is refreshing the access token with Whoop. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `disconnected` | `authorizing` | User taps Connect Whoop | Network available | Set state to `.connecting`; request auth URL from backend; open ASWebAuthenticationSession |
| `authorizing` | `connected.syncing` | OAuth callback success | State parameter valid | Exchange code via backend; trigger initial 30-day sync; update UI to "Connected" |
| `authorizing` | `disconnected` | User cancels OAuth | Always | Set state to `.disconnected`; no error shown |
| `authorizing` | `disconnected` | OAuth error (denied, timeout, backend error) | Always | Show error message; log error |
| `connected.idle` | `connected.syncing` | Periodic sync trigger (every 30 min) OR pull-to-refresh OR app foreground | `lastSync + syncInterval < now` | Request sync from backend; show spinner |
| `connected.syncing` | `connected.idle` | Sync complete | Data received and persisted | Update `lastSyncAt`; refresh UI; update HealthKit |
| `connected.syncing` | `connected.error` | Sync failed | Network error OR API error (not token) | Show error badge; schedule retry (exponential backoff: 2m, 4m, 8m, max 30m) |
| `connected.error` | `connected.syncing` | Retry timer fires OR user taps Retry | Network available | Re-attempt sync |
| `connected.*` | `tokenExpired` | Any API call returns 401 | Backend detects expired token | Pause pending operations |
| `tokenExpired` | `refreshing` | Automatic | Always (backend handles this transparently) | Backend POSTs refresh_token to Whoop |
| `refreshing` | `connected.syncing` | Refresh success | New tokens stored | Retry the failed API call |
| `refreshing` | `disconnected` | Refresh failed (token revoked) | Whoop returns 400/401 on refresh | Mark as disconnected; send push "Whoop disconnected. Tap to reconnect."; clear stored tokens |
| `connected.*` | `disconnected` | User taps Disconnect | Confirmation accepted | Revoke tokens on backend; clear local data; update UI |
| `connected.*` | `connected.error` | Rate limited (429) | `Retry-After` header present | Wait for `Retry-After` duration; then retry |
| `authorizing` | `disconnected` | OAuth session timeout | `elapsedSinceAuthStart > 60s` | Cancel ASWebAuthenticationSession; show "Connection timed out. Try again." |
| `connected.syncing` | `connected.error` | Sync request timeout | `elapsedSinceSyncStart > 30s` | Cancel request; mark sync as failed; schedule retry |
| `refreshing` | `refreshing` | Token refresh timeout | `elapsedSinceRefreshStart > 10s` AND `retryCount < 3` | Retry refresh (up to 3 attempts) |
| `refreshing` | `disconnected` | Token refresh timeout (max retries exceeded) | `retryCount >= 3` | Mark as disconnected; send push "Whoop disconnected. Tap to reconnect."; clear stored tokens |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| OAuth session | 60 seconds | Cancel session; show "Connection timed out" |
| Backend auth URL request | 15 seconds | Cancel; show "Connection timed out" |
| Sync request | 30 seconds | Mark sync as failed; transition to error |
| Token refresh | 10 seconds | Retry up to 3 times, then mark disconnected |

### Swift Enum

```swift
enum WhoopSyncState: Codable, Equatable {
    case disconnected
    case authorizing
    case connected(WhoopConnectionSubState)
    case tokenExpired
    case refreshing

    enum WhoopConnectionSubState: Codable, Equatable {
        case syncing(startedAt: Date)
        case idle(lastSync: Date)
        case error(WhoopSyncError, retryAt: Date?)
    }

    enum WhoopSyncError: Codable, Equatable {
        case networkUnavailable
        case apiError(statusCode: Int)
        case rateLimited(retryAfter: TimeInterval)
        case membershipExpired
        case unknown(message: String)
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `connectionState` | `WhoopIntegration.connectionState` | YES (on backend + local cache) |
| `lastSyncAt` | `WhoopIntegration.lastSyncAt: Date?` | YES |
| `lastSyncStatus` | `WhoopIntegration.lastSyncStatus: String?` | YES |
| Tokens | Backend only (encrypted) | YES (server-side) |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `disconnected` | Whoop Connect View -- "Connect Whoop" button |
| `authorizing` | System OAuth browser sheet |
| `connected.idle` | Recovery badge: "[sync] Synced 6:42 AM" |
| `connected.syncing` | Recovery badge: spinner + "Syncing..." |
| `connected.error` | Recovery badge: yellow "[sync] Stale -- tap to sync" |
| `tokenExpired` / `refreshing` | Brief spinner (usually transparent to user) |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| `refreshing` -> `disconnected` (revoked) | "Whoop disconnected. Tap to reconnect." |
| `connected.syncing` -> `connected.idle` (first sync) | "Whoop connected! Your recovery data is ready." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `whoop.connect_started` | -- |
| `whoop.connect_success` | `daysOfHistoryRequested` |
| `whoop.connect_failed` | `error`, `step` |
| `whoop.sync_completed` | `dataPoints`, `duration` |
| `whoop.sync_failed` | `error`, `retryCount` |
| `whoop.disconnected` | `reason: user | token_revoked | membership_expired` |

---

## 5. NutriTrack Sync

NutriTrack connects via a backend proxy using a user-provided server URL and PIN. Simpler than Whoop OAuth but with its own failure modes.

### State Diagram

```
    +--------------+<-----------+<--[user taps Disconnect]--+
    | disconnected |            |                           |
    +------+-------+            |                           |
           |            [rejected/     [timeout/            |
    [user enters URL     unreachable]   unreachable]        |
     + PIN, taps                |                           |
     Connect]                   |                           |
           |                    |                           |
    +------v-------+            |                           |
    | connecting   |-----+------+                           |
    +------+-------+                                        |
           |                                                |
    [PIN verified successfully]                             |
           |                                                |
    +------v-------+                                        |
    | connected    |----------------------------------------+
    +------+-------+
           |
     (sub-states)
     +------+------+------+
     |      |      |      |
     v      v      v      |
  +------+ +----+ +-----+ |
  |syncing| |idle| |error| |
  +------+ +----+ +-----+ |
                           |
     [sync returns 401 / PIN expired]
           |               |
    +------v-------+       |
    | pin_expired  |       |
    +------+-------+       |
           |               |
    [user re-enters PIN]   |
           |               |
    +------v-------+       |
    | connecting   |-------+
    +--------------+
```

### States

| State | Description |
|-------|-------------|
| `disconnected` | No NutriTrack connection configured. |
| `connecting` | Backend is verifying the server URL and PIN with NutriTrack. |
| `connected.syncing` | Actively fetching meal/nutrition data from NutriTrack. |
| `connected.idle` | Connected and data is fresh. |
| `connected.error` | Last sync failed (server down, network loss, invalid response). |
| `pinExpired` | Stored PIN no longer accepted by NutriTrack. User must re-enter. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `disconnected` | `connecting` | User submits URL + PIN | URL non-empty, PIN >= 4 digits | Backend POSTs to NutriTrack `/api/pin/verify` |
| `connecting` | `connected.idle` | PIN verified | Backend receives 200 OK | Store encrypted URL + PIN on backend; update UI; trigger initial sync |
| `connecting` | `disconnected` | PIN rejected | Backend receives 401 | Show "Invalid PIN. Check your NutriTrack settings." |
| `connecting` | `disconnected` | Server unreachable | Network error or timeout | Show "Could not reach NutriTrack server. Check the URL." |
| `connected.idle` | `connected.syncing` | Periodic sync (every 15 min) OR pull-to-refresh | `lastSync + 15min < now` | Fetch today's meals from NutriTrack |
| `connected.syncing` | `connected.idle` | Sync success | Meals data received | Update meal counts; update non-negotiable progress; refresh UI |
| `connected.syncing` | `connected.error` | Sync failed (not PIN issue) | Server error OR network error | Show error state; schedule retry |
| `connected.syncing` | `pinExpired` | Sync returns 401 (PIN invalid) | Backend gets 401 from NutriTrack | Show "NutriTrack PIN expired. Please re-enter." |
| `connected.error` | `connected.syncing` | Retry timer fires | Network available | Re-attempt sync |
| `pinExpired` | `connecting` | User enters new PIN | PIN >= 4 digits | Verify new PIN with backend |
| `connected.*` | `disconnected` | User taps Disconnect | Confirmation accepted | Clear stored credentials on backend; clear local cache |
| `connecting` | `disconnected` | Connection timeout | `elapsedSinceConnectStart > 15s` | Cancel request; show "Could not reach NutriTrack server. Check the URL." |
| `connected.syncing` | `connected.error` | Sync timeout | `elapsedSinceSyncStart > 30s` | Cancel request; mark sync as failed; schedule retry (exponential backoff: 2m, 4m, 8m, max 30m) |
| `connected.error` | `connected.error` | Retry max exceeded | `retryCount >= 5` | Stop auto-retrying; show "Persistent sync failure. Tap to retry manually."; require user-initiated retry |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| PIN verification request | 15 seconds | Cancel; show "Could not reach NutriTrack server. Check the URL."; transition to `disconnected` |
| Sync request | 30 seconds | Mark sync as failed; transition to `connected.error`; schedule retry |
| Retry backoff max | 5 consecutive failures | Stop auto-retry; require user-initiated retry |
| `pinExpired` with no user action | N/A | Remains in `pinExpired` indefinitely; periodic push reminder every 24h: "NutriTrack PIN still expired." |

### Swift Enum

```swift
enum NutriTrackSyncState: Codable, Equatable {
    case disconnected
    case connecting
    case connected(NutriTrackConnectionSubState)
    case pinExpired

    enum NutriTrackConnectionSubState: Codable, Equatable {
        case syncing(startedAt: Date)
        case idle(lastSync: Date)
        case error(NutriTrackError, retryAt: Date?)
    }

    enum NutriTrackError: Codable, Equatable {
        case serverUnreachable
        case invalidResponse
        case networkUnavailable
        case unknown(message: String)
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `connectionState` | `NutriTrackIntegration.state` | YES |
| `lastSyncAt` | `NutriTrackIntegration.lastSyncAt: Date?` | YES |
| `serverURL` + `pin` | Backend only (encrypted) | YES (server-side) |
| `cachedMeals` | `NutriTrackIntegration.todayMeals: [MealEntry]` | YES |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `disconnected` | NutriTrack Connect View -- URL + PIN fields |
| `connecting` | NutriTrack Connect View -- loading spinner |
| `connected.idle` | Meals card: "NUTRITRACK" badge, meal counts |
| `connected.syncing` | Meals card: spinner overlay |
| `connected.error` | Meals card: amber "Sync failed" message |
| `pinExpired` | NutriTrack Connect View -- "PIN Expired" banner + re-entry field |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| -> `pinExpired` | "NutriTrack PIN expired. Re-enter to keep tracking meals." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `nutritrack.connect_success` | -- |
| `nutritrack.connect_failed` | `reason` |
| `nutritrack.sync_completed` | `mealCount`, `duration` |
| `nutritrack.pin_expired` | -- |

---

## 6. Non-Negotiable Item

Each individual non-negotiable task follows its own lifecycle within a day. This machine is instantiated per-item per-day.

### State Diagram

```
    +--------------+
    | not_started  |
    +------+-------+
           |
    [first progress reported:
     timer started / Whoop sync / manual check / NutriTrack meal]
           |
    +------v-------+
    | in_progress  |
    +------+-------+
           |
     +-----+-----+
     |     |      |
     v     |      v
+--------+ | +--------+
|completed| | |overdue |
+--------+ | +--------+
           |      |
           v      v
      +--------+
      |skipped |
      +--------+
```

### States

| State | Description |
|-------|-------------|
| `notStarted` | Zero progress. No interaction or auto-tracking data received today. |
| `inProgress` | Partial completion. Timer running, some meals logged, some steps counted. |
| `completed` | Target met or exceeded. 100% progress. Checkmark displayed. |
| `overdue` | Past deadline (PS5 time) and not completed. Pulsing red. |
| `skipped` | Explicitly skipped by user (with optional reason). Counts as done for streak. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `notStarted` | `inProgress` | Any progress > 0 | progress > 0 AND progress < target | Update progress bar; change card border to blue |
| `notStarted` | `completed` | Full progress in one event | progress >= target (e.g., binary task checked) | Completion animation; haptic; update daily total |
| `notStarted` | `skipped` | User swipe-left or context menu "Skip" | Always | Record skip reason; mark as done for streak; grey out card |
| `inProgress` | `completed` | Progress reaches target | `currentProgress >= target` | Completion animation; haptic `.success`; update daily total; check if all-complete |
| `inProgress` | `overdue` | PS5 time reached | `currentTime >= ps5Time && !isComplete` | Red pulse on card; change progress bar to red |
| `inProgress` | `skipped` | User skips | Always | Same as notStarted -> skipped |
| `overdue` | `completed` | Progress reaches target (after PS5 time) | `currentProgress >= target` | Muted completion (no confetti); update daily total; check if all-complete for late unlock |
| `overdue` | `skipped` | User swipe-left or context menu "Skip" | Always | Record skip reason; mark as done for streak; grey out card |
| `completed` | `inProgress` | Target changed mid-day (increased) | `newTarget > currentProgress` | Re-open card; update target display |
| `completed` | `completed` | Additional progress logged | `currentProgress > target` | Update "extra" display (e.g., "2h 15m / 2h") |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `notStarted` | Grey card border; tertiary icon tint | -- |
| `inProgress` | Blue card border; blue icon tint; show progress bar fill | -- |
| `completed` | Green border; green icon; checkmark stroke animation (0.3s); scale pulse 1.0->1.03->1.0; haptic; update parent accountability state | -- |
| `overdue` | Red pulsing border (opacity 0.5->1.0, 2s cycle); red icon; urgency message | -- |
| `skipped` | Grey border; strikethrough name; 60% opacity; show skip reason | -- |

### Swift Enum

```swift
enum NonNegotiableItemState: Codable, Equatable {
    case notStarted
    case inProgress(current: Double, target: Double)
    case completed(current: Double, target: Double, completedAt: Date)
    case overdue(current: Double, target: Double)
    case skipped(reason: String?, skippedAt: Date)
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `NonNegotiableProgress.state` | YES |
| `currentProgress` | `NonNegotiableProgress.currentValue: Double` | YES |
| `target` | `NonNegotiableProgress.targetValue: Double` | YES |
| `trackingSource` | `NonNegotiableProgress.source: TrackingSource` | YES |
| `completedAt` | `NonNegotiableProgress.completedAt: Date?` | YES |

### UI Mapping

| State | Component |
|-------|-----------|
| `notStarted` | Card with "NOT STARTED" label, grey |
| `inProgress` | Card with progress bar, "1h 23m / 2h" |
| `completed` | Card with "DONE" + green checkmark |
| `overdue` | Card with "OVERDUE" pulsing red |
| `skipped` | Card with "SKIPPED" + strikethrough |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| `notStarted` and time > noon | Tier 1: "You haven't started {task} yet." |
| -> `overdue` | Tier 3/4: "{task} is overdue." |
| -> `completed` | None (parent accountability handles unlock notification) |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `nonneg.started` | `taskId`, `taskType`, `trackingMethod` |
| `nonneg.progress_updated` | `taskId`, `currentValue`, `targetValue`, `source` |
| `nonneg.completed` | `taskId`, `completionTime`, `method: auto | manual` |
| `nonneg.skipped` | `taskId`, `reason` |
| `nonneg.overdue` | `taskId`, `currentProgress` |

---

## 7. Streak

The streak is a daily-resolution counter that must handle timezone changes, rest days, sick days, and streak freezes. A bug here damages user trust more than almost anything else.

### State Diagram

```
    +--------------+       +-----------+
    | inactive     |------>| active    |
    | (day_0)      |       | (day_N)   |
    +--------------+       +-----+-----+
                                 |
                          +------+------+
                          |             |
                   [< 2h to midnight,  [midnight arrives,
                    tasks incomplete]    tasks incomplete,
                          |             no freeze available]
                          v             v
                   +-----------+  +-----------+
                   | at_risk   |  | broken    |
                   +-----+-----+  +-----------+
                         |
                  +------+------+
                  |             |
           [tasks completed   [midnight, freeze available]
            before midnight]        |
                  |           +-----v-----------+
                  v           | preserved       |
           +-----------+      | (via_freeze)    |
           | active    |      +-----------------+
           | (day_N+1) |
           +-----------+
```

### States

| State | Description |
|-------|-------------|
| `inactive` | Streak is at 0. No active streak. User has never completed a full day or streak was broken. |
| `active(dayN)` | Streak is alive. `N` consecutive days completed. |
| `atRisk` | Less than 2 hours to midnight and today's tasks are not yet complete. Streak may break. |
| `broken` | Midnight passed without completion. Streak reset to 0. |
| `preserved(viaFreeze)` | Midnight passed without completion but a streak freeze was used. Streak survives. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `inactive` | `active(1)` | All non-negotiables completed | First complete day ever OR first day after break | Set streak to 1; fire streak-start haptic |
| `active(N)` | `active(N+1)` | Day boundary (00:00) | Previous day was fully completed | Increment streak; check for milestone; update UI |
| `active(N)` | `atRisk` | Periodic check (every 30 min after 10 PM) | `currentTime > (midnight - 2h) && !allComplete && streakN > 0` | Fire notification: "Your {N}-day streak is at risk!"; show amber warning in UI; **Cross-machine trigger:** Machine 11 (Notification Escalation) escalates to at least `urgent` tier if not already there |
| `atRisk` | `active(N+1)` | All non-negotiables completed | Before midnight | Streak preserved; fire relief notification: "Streak saved! {N+1} days." |
| `atRisk` | `broken` | Midnight | Tasks incomplete AND no freeze available | Reset streak to 0; fire XP penalty (-100 or -50 depending on length); notification: "Streak broken." |
| `atRisk` | `preserved(viaFreeze)` | Midnight | Tasks incomplete AND freeze available | Consume one streak freeze; streak count unchanged; notification: "Freeze used. Streak at {N}." |
| `broken` | `inactive` | Acknowledgement | Always | Log broken streak length; track in analytics |
| `inactive` | `active(1)` | Next completed day | All tasks done | Restart streak from 1 |
| `preserved` | `active(N)` | Next day begins | Always | Resume normal tracking; streak count unchanged |
| `active(N)` | `active(N)` | Rest day / sick day | Override active for today | Day does not count toward streak but does not break it; streak number unchanged |
| `active(N)` | `active(N)` | Timezone change | User crosses timezone boundary | Recalculate midnight boundary; if the change would create a double-count, skip; if it would create a gap, apply freeze if available |

### Swift Enum

```swift
enum StreakState: Codable, Equatable {
    case inactive
    case active(dayCount: Int, startDate: Date)
    case atRisk(dayCount: Int, minutesToMidnight: Int)
    case broken(previousLength: Int, brokenAt: Date)
    case preserved(dayCount: Int, freezeUsedAt: Date, freezesRemaining: Int)
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `UserStreak.state: StreakState` | YES |
| `currentCount` | `UserStreak.currentStreak: Int` | YES |
| `longestEver` | `UserStreak.longestStreak: Int` | YES |
| `startDate` | `UserStreak.streakStartDate: Date?` | YES |
| `freezesAvailable` | `UserStreak.streakFreezes: Int` | YES |
| `lastEvaluatedDate` | `UserStreak.lastEvaluatedDate: Date` | YES |

### UI Mapping

| State | Component |
|-------|-----------|
| `inactive` | Grey flame icon, "0" streak counter, static |
| `active(N)` | Gold flame (flickering animation), N counter |
| `atRisk` | Amber flame, pulsing, warning banner |
| `broken` | Grey flame, "Streak broken" message, restart CTA |
| `preserved` | Gold flame + snowflake icon, "Freeze used" label |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| -> `atRisk` | "Your {N}-day streak is at risk! Complete your tasks before midnight." |
| `atRisk` -> `active(N+1)` | "Streak saved! {N+1} days and counting." |
| -> `broken` | "Your {N}-day streak just broke. Day 1 starts tomorrow." |
| -> `preserved` | "Streak freeze used. Your {N}-day streak survives." |
| `active(N)` where N is milestone (7, 14, 30, 50, 100) | "Milestone! {N}-day streak. Keep building." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `streak.day_added` | `newCount`, `dayDate` |
| `streak.at_risk` | `count`, `minutesToMidnight` |
| `streak.broken` | `previousLength`, `missedTasks` |
| `streak.freeze_used` | `count`, `freezesRemaining` |
| `streak.milestone_reached` | `milestone` |

---

## 8. Challenge

Arena challenges between friends. Handles the full lifecycle from invite through completion, including edge cases like participant leaving or creator canceling.

### State Diagram

```
    +-----------+
    | invited   |
    +-----+-----+
          |
    +-----+-----+-----+-----+
    |           |     |     |
    v           v     v     v
+---------+ +-----+ +-----+ +----------+
| accepted| |decl.| |expr.| |cancelled |
+----+----+ +-----+ +-----+ +----------+
     |
     +----------+
     |          |
     |   [creator cancels before start]
     |          v
     |   +----------+
     |   |cancelled |
     |   +----------+
     |
     | [challenge start time reached]
     v
+---------+
| active  |
|(tracking)|
+----+----+
     |
     +------+
     |      |
     |  [participant forfeits]
     |      v
     | +-----------+
     | | abandoned |
     | +-----------+
     |
     | [end date reached]
     v
+---------+
| ending  |  (final calculation, 24h grace for late syncs)
+----+----+
     |
     +------+------+------+
     |      |      |      |
     v      v      v      v
  +-----+ +-----+ +-----+
  | won | | lost| | tied|
  +-----+ +-----+ +-----+
```

### States

| State | Description |
|-------|-------------|
| `invited` | Challenge created. Invite sent to opponent(s). Awaiting response. |
| `accepted` | Opponent accepted. Waiting for start time (challenges start at midnight of the next day). |
| `declined` | Opponent declined. Terminal state. |
| `expired` | Invite not responded to within 48 hours. Terminal state. |
| `active(tracking)` | Challenge is live. Metrics being tracked daily. |
| `ending` | End date reached. 24-hour grace period for late data syncs. |
| `completed(won)` | User won the challenge. XP awarded. |
| `completed(lost)` | User lost. Participation XP awarded. |
| `completed(tied)` | Tie. Both get winner XP. |
| `cancelled` | Creator cancelled before start. No XP impact. |
| `abandoned` | Participant forfeited mid-challenge. Counts as loss. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| -- | `invited` | User creates challenge | Valid metric, valid opponent(s), user level >= 7 (creation) or any level (join) | Create challenge record; send push to opponent(s); log `challenge.created` |
| `invited` | `accepted` | Opponent taps Accept | Within 48h of invite | Notify creator; schedule start for next midnight; award 25 XP (join bonus) to accepter |
| `invited` | `declined` | Opponent taps Decline | Within 48h | Notify creator; no XP impact |
| `invited` | `expired` | 48h timer | No response received | Notify creator: "{Name} didn't respond."; no XP impact |
| `invited` | `cancelled` | Creator cancels | Before acceptance | Delete invite; notify opponent if already seen |
| `accepted` | `active(tracking)` | Midnight of start date | Both participants exist | Start daily metric tracking; daily progress notifications; update leaderboard |
| `accepted` | `cancelled` | Creator cancels | Before start time | Refund join XP; notify opponent |
| `active(tracking)` | `ending` | End date midnight reached | Always | Lock in final scores; start 24h grace period for Whoop/NutriTrack late syncs |
| `active(tracking)` | `abandoned` | Participant taps Forfeit | Confirmation accepted | Count as loss for forfeiter; award participation XP (if > 50% days participated); opponent wins |
| `ending` | `completed(won)` | Grace period ends | User's score > opponent's | Award winner XP (200 1v1, 300 group); push notification; update achievements |
| `ending` | `completed(lost)` | Grace period ends | User's score < opponent's | Award participation XP (50, if > 50% participation); push notification |
| `ending` | `completed(tied)` | Grace period ends | Scores equal | Award winner XP to both |
| `active(tracking)` | `active(tracking)` | Friend removed | Opponent still exists in challenge | Opponent shown as "Former Opponent"; challenge continues normally |
| `active(tracking)` | `completed(won)` | Opponent deletes account | Always | Auto-win for remaining player |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| `invited` with no response | 48 hours | Transition to `expired`; notify creator |
| `ending` grace period | 24 hours | Transition to `completed(won/lost/tied)` based on final scores |
| `active` with no score updates from participant | 7 days | Send reminder notification to inactive participant; if 14 days, mark as `abandoned` |

### Swift Enum

```swift
enum ChallengeState: Codable, Equatable {
    case invited(createdAt: Date, expiresAt: Date)
    case accepted(startDate: Date)
    case declined
    case expired
    case active(
        startDate: Date,
        endDate: Date,
        metric: ChallengeMetric,
        scores: [UUID: Double]
    )
    case ending(endDate: Date, graceDeadline: Date)
    case completed(ChallengeResult)
    case cancelled(by: UUID)
    case abandoned(by: UUID)

    enum ChallengeMetric: String, Codable {
        case totalXP
        case workoutCount
        case studyHours
        case stepCount
        case caloriesBurned
        case streakLength
    }

    enum ChallengeResult: Codable, Equatable {
        case won(xpAwarded: Int)
        case lost(participationXP: Int)
        case tied(xpAwarded: Int)
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `Challenge.state` | YES (synced to backend) |
| `participants` | `Challenge.participants: [ChallengeParticipant]` | YES (backend) |
| `scores` | `Challenge.dailyScores: [DailyScore]` | YES (backend) |
| `metric` | `Challenge.metric: ChallengeMetric` | YES |
| `startDate` / `endDate` | `Challenge.startDate / endDate` | YES |

### UI Mapping

| State | Screen/Component |
|-------|-----------------|
| `invited` | Challenge card with Accept/Decline buttons; push notification |
| `accepted` | Challenge card with "Starts {date}" countdown |
| `active` | Challenge detail view -- live score comparison, daily breakdown |
| `ending` | Challenge card -- "Calculating final results..." |
| `completed(won)` | Victory screen -- confetti, "+200 XP", share button |
| `completed(lost)` | Loss screen -- "Rematch" CTA |
| `completed(tied)` | Tie screen -- both get winner treatment |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| -> `invited` (opponent) | "{Name} challenged you to {metric}!" |
| -> `accepted` (creator) | "{Name} accepted! Challenge starts tomorrow." |
| -> `declined` (creator) | "{Name} declined your challenge." |
| -> `expired` (creator) | "{Name} didn't respond. Challenge cancelled." |
| `active` -- opponent overtakes | "{Name} just passed you!" (max 3/day) |
| `active` -- halfway | "Halfway! You're {winning/losing} by {amount}." |
| -> `completed(won)` | "You won! +{XP} XP" |
| -> `completed(lost)` | "{Opponent} won. +{XP} XP for participating." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `challenge.created` | `metric`, `duration`, `participantCount` |
| `challenge.accepted` | `challengeId`, `responseTime` |
| `challenge.declined` | `challengeId` |
| `challenge.started` | `challengeId`, `participants` |
| `challenge.completed` | `challengeId`, `result`, `finalScores`, `duration` |
| `challenge.abandoned` | `challengeId`, `abandonedBy`, `dayNumber` |

---

## 9. Friend Request

Simple but important. Must handle blocking correctly to prevent harassment. Blocking after acceptance must also remove from leaderboards and active challenges.

### State Diagram

```
    +--------+
    | none   |
    +---+----+
        |
    [user sends request]
        |
    +---v----------+
    | pending_sent |<--------+
    +---+----------+         |
        |                    |
   +----+----+----+         |
   |    |    |    |         |
   v    v    v    v         |
+----+ +----+ +----+ +----+|
|accp| |decl| |blkd| |expr||
+--+-+ +----+ +----+ +----+|
   |                        |
   | [user blocks after     |
   |  accept]               |
   |    +------+            |
   +--->|blocked|            |
        +--+---+            |
           |                |
        [unblock]           |
           |                |
        +--v---+            |
        | none |------------+
        +------+  (can re-send)
```

### States

| State | Description |
|-------|-------------|
| `none` | No relationship between users. Default. |
| `pendingSent` | Current user sent a request. Awaiting response. |
| `pendingReceived` | Current user received a request. Awaiting their response. |
| `accepted` | Friends. Mutual. Visible on leaderboards. Can challenge. |
| `declined` | Request was declined. Can re-send after cooldown (7 days). |
| `blocked` | One user blocked the other. Invisible to each other. |
| `expired` | Request expired (14 days, no response). |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `none` | `pendingSent` | User taps Add Friend | Not blocked by recipient | Send request; push to recipient |
| `none` | `pendingReceived` | Other user sends request | Not blocked by current user | Show in notifications; badge on Arena tab |
| `pendingReceived` | `accepted` | User taps Accept | Always | Add to mutual friend lists; push to sender; unlock leaderboard visibility |
| `pendingReceived` | `declined` | User taps Decline | Always | Remove from pending; no notification to sender |
| `pendingReceived` | `blocked` | User taps Block | Always | Block bidirectionally; remove all shared data |
| `pendingSent` | `accepted` | Recipient accepts | Always | Add to mutual friends; push to current user |
| `pendingSent` | `declined` | Recipient declines | Always | Update UI; allow re-request after 7-day cooldown |
| `pendingSent` | `expired` | 14 days pass | No response | Notify sender; auto-cleanup |
| `pendingSent` | `none` | User cancels request | Before response | Remove pending request |
| `accepted` | `none` | User removes friend | Confirmation accepted | Remove from mutual lists; remove from each other's leaderboards; active challenges continue as "Former Opponent" |
| `accepted` | `blocked` | User blocks friend | Confirmation accepted | Block bidirectionally; remove friend; hide from search/leaderboard; active challenges: opponent shown as "Former Opponent" |
| `blocked` | `none` | User unblocks | Always | Remove block; do NOT re-add as friend; must send new request |
| `declined` | `none` | 7-day cooldown expires | Always | Allow new request |

### Swift Enum

```swift
enum FriendRequestState: Codable, Equatable {
    case none
    case pendingSent(sentAt: Date)
    case pendingReceived(sentAt: Date, senderId: UUID)
    case accepted(since: Date)
    case declined(at: Date, cooldownEnds: Date)
    case blocked(by: UUID, at: Date)
    case expired(originalSentAt: Date)
}
```

### Persistence Strategy

Backend-only. The iOS app caches the friend list locally but the source of truth is the server.

| Field | Backend Table | Synced to iOS |
|-------|--------------|---------------|
| `status` | `friendships.status` | YES |
| `sentAt` | `friendships.created_at` | YES |
| `acceptedAt` | `friendships.accepted_at` | YES |
| `blockedUsers` | `user_blocks` table | YES (block list cached locally) |

### UI Mapping

| State | Component |
|-------|-----------|
| `none` | "Add Friend" button on search results |
| `pendingSent` | "Pending" label (grey) with Cancel option |
| `pendingReceived` | Accept / Decline buttons on notification card |
| `accepted` | Friend card in friend list with Challenge shortcut |
| `blocked` | Not visible anywhere. Listed in Settings > Blocked Users |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| -> `pendingReceived` | "{Name} wants to be your friend on Tempo." (Accept / Decline buttons) |
| -> `accepted` (sender) | "{Name} accepted your friend request." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `friend.request_sent` | `recipientId`, `source: search | qr | username` |
| `friend.request_accepted` | `senderId`, `responseTime` |
| `friend.request_declined` | `senderId` |
| `friend.removed` | `friendId` |
| `friend.blocked` | `blockedId`, `wasAccepted` |
| `friend.unblocked` | `unblockedId` |

---

## 10. Onboarding

A 12-step linear flow with back navigation, skip support on optional steps, and resume-after-kill. The critical invariant: no step is ever lost if the app is killed.

### State Diagram

```
    +--------+   +------+   +---------+   +----------------+
    | splash |-->| auth |-->| profile |-->| training_setup |
    +--------+   +------+   +---------+   +-------+--------+
                                                   |
    +----------------+   +-----------+   +---------v--------+
    | nutritrack     |<--| whoop     |<--| academic_setup   |
    | _connect       |   | _connect  |   |                  |
    +-------+--------+   +-----------+   +------------------+
            |
    +-------v--------+   +-----------+   +---------+
    | healthkit      |-->| notific-  |-->| arena   |
    |                |   | ations    |   |         |
    +----------------+   +-----------+   +----+----+
                                              |
                                        +-----v----+
                                        | goals    |
                                        +-----+----+
                                              |
                                        +-----v----+
                                        | complete |
                                        +----------+
```

### States

| State | Description |
|-------|-------------|
| `splash` | Animated splash screen (1.8s). Auto-advances. |
| `auth` | Sign in with Apple. REQUIRED. No skip. |
| `profile` | Display name, username, photo. REQUIRED (name + username). Photo optional. |
| `trainingSetup` | Training profile: do you train? Frequency? Experience? OPTIONAL (can skip). |
| `academicSetup` | Academic profile: university, year, schedule. OPTIONAL. |
| `goals` | Daily goals: study hours, meal count, PS5 time. REQUIRED. |
| `whoopConnect` | Connect Whoop account. OPTIONAL. |
| `nutritrackConnect` | Connect NutriTrack. OPTIONAL. |
| `healthkit` | Request HealthKit permissions. OPTIONAL (but encouraged). |
| `notifications` | Request notification permissions. OPTIONAL (but strongly encouraged). |
| `arena` | Arena intro: explain XP, leaderboards, challenges. Informational. |
| `complete` | Onboarding finished. Show congratulations. Transition to Dashboard. Terminal. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `splash` | `auth` | Animation completes (1.8s) | First launch | Auto-advance |
| `splash` | (Dashboard) | App launch | Already onboarded (`onboardingComplete == true`) | Skip entirely |
| `auth` | `profile` | Apple sign-in success | `userIdentifier` received | Create user on backend; store credentials |
| `auth` | `auth` | Sign-in cancelled | Always | Stay on screen; no error shown |
| `profile` | `trainingSetup` | User taps Continue | Display name valid AND username valid + available | Create profile on backend |
| `trainingSetup` | `academicSetup` | User taps Continue OR Skip | Always | Save training preferences (or defaults if skipped) |
| `academicSetup` | `goals` | User taps Continue OR Skip | Always | Save academic info (or defaults) |
| `goals` | `whoopConnect` | User taps Continue | Study target + meal target + PS5 time set | Save goals; create non-negotiable templates |
| `whoopConnect` | `nutritrackConnect` | Connected successfully OR user taps Skip | Always | If connected: trigger initial sync; if skipped: mark as skipped |
| `nutritrackConnect` | `healthkit` | Connected OR Skip | Always | Same pattern |
| `healthkit` | `notifications` | Permissions granted OR denied OR Skip | Always | Request HealthKit authorization; handle response silently |
| `notifications` | `arena` | Permissions granted OR denied OR Skip | Always | Request notification authorization |
| `arena` | `complete` | User taps "Enter Tempo" | Always | Set `onboardingComplete = true`; transition to Dashboard |
| Any step | Previous step | User taps Back | Not on `splash` or `auth` | Navigate back; preserve entered data |
| Any step | Same step | App killed and relaunched | `onboardingComplete == false` | Resume at `lastCompletedStep + 1` |

### Swift Enum

```swift
enum OnboardingState: Codable, Equatable {
    case splash
    case auth
    case profile
    case trainingSetup
    case academicSetup
    case goals
    case whoopConnect
    case nutritrackConnect
    case healthkit
    case notifications
    case arena
    case complete

    var stepNumber: Int {
        switch self {
        case .splash: return 0
        case .auth: return 1
        case .profile: return 2
        case .trainingSetup: return 3
        case .academicSetup: return 4
        case .goals: return 5
        case .whoopConnect: return 6
        case .nutritrackConnect: return 7
        case .healthkit: return 8
        case .notifications: return 9
        case .arena: return 10
        case .complete: return 11
        }
    }

    var isRequired: Bool {
        switch self {
        case .auth, .profile, .goals: return true
        default: return false
        }
    }
}
```

### Persistence Strategy

| Field | Storage | Survives App Kill |
|-------|---------|-------------------|
| `currentStep` | `UserDefaults["onboarding_step"]` | YES |
| `isComplete` | `UserDefaults["onboarding_complete"]` | YES |
| `stepData` | `UserDefaults["onboarding_data"]` (JSON blob) | YES (each step saves incrementally) |
| `trainingAnswers` | Within stepData JSON | YES |
| `academicAnswers` | Within stepData JSON | YES |
| `goalAnswers` | Within stepData JSON | YES |

### UI Mapping

| State | Screen |
|-------|--------|
| `splash` | Full-screen splash animation (TEMPO wordmark) |
| `auth` | Sign in with Apple screen |
| `profile` | Photo + display name + username form |
| `trainingSetup` | Card-based training questionnaire |
| `academicSetup` | University + year + schedule form |
| `goals` | Study target + meals + PS5 time configuration |
| `whoopConnect` | Whoop branded connect button |
| `nutritrackConnect` | NutriTrack URL + PIN entry |
| `healthkit` | Permission request explanation screen |
| `notifications` | Permission request with drill-sergeant preview |
| `arena` | XP/leaderboard intro with animations |
| `complete` | "Welcome to Tempo" celebration; CTA to Dashboard |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `onboarding.step_completed` | `step`, `duration`, `skipped: Bool` |
| `onboarding.step_abandoned` | `step`, `duration` |
| `onboarding.completed` | `totalDuration`, `stepsSkipped`, `integrationsConnected` |
| `onboarding.resumed` | `resumedAtStep`, `previousSessionDuration` |

---

## 11. Push Notification Escalation

The drill-sergeant notification system for accountability. This machine runs per-day and governs escalation from gentle to critical.

### State Diagram

```
    +---------+
    | quiet   |  (morning, before Tier 0 fires)
    +----+----+
         |
    [morning briefing time]
         |
    +----v----+
    | gentle  |  (Tier 0-1: morning briefing + gentle reminder)
    +----+----+
         |
    [time > noon, tasks < 50%]
         |
    +----v----+
    | firm    |  (Tier 2: firm warnings)
    +----+----+
         |
    [approaching PS5 time, tasks incomplete]
         |
    +----v----+
    | urgent  |  (Tier 3: urgent alerts)
    +----+----+
         |
    [< 30 min to PS5, tasks incomplete]
         |
    +----v----+
    | critical|  (Tier 4: final warning, Time Sensitive notification)
    +----+----+
         |
    [all tasks complete OR day ends]
         |
    +----v----+
    | resolved|
    +---------+
```

### States

| State | Description |
|-------|-------------|
| `quiet` | Before morning briefing. No notifications sent today. |
| `gentle` | Tier 0 (morning briefing) sent. Tier 1 (gentle reminder) eligible at 12-3 PM if < 50% done. |
| `firm` | Tier 2 active. Firmer copy. Sent at 3-5 PM if tasks still lagging. |
| `urgent` | Tier 3 active. Approaching PS5 time. Sent every 30-60 min. |
| `critical` | Tier 4. Final warning. < 30 min to PS5 time. Most aggressive copy. `.timeSensitive` interruption level (Critical Alerts not available -- see Technical Feasibility Audit). |
| `resolved` | All tasks completed (at any stage) OR day ended. No more notifications. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `quiet` | `gentle` | Morning briefing time reached | Day is active (not rest/sick) | Fire Tier 0 notification (morning briefing); set badge to incomplete count |
| `gentle` | `firm` | Time > noon AND background refresh | `completionPercent < 50 && hasUnstartedTask` | Fire Tier 1 notification (gentle reminder, max 1); schedule Tier 2 check |
| `firm` | `urgent` | Time approaching PS5 AND background refresh | `timeToPS5 < 2h && completionPercent < 100` | Fire Tier 2 notification (firm warning); schedule Tier 3 check |
| `urgent` | `critical` | Time very close to PS5 | `timeToPS5 < 30min && !allComplete` | Fire Tier 3 notification (urgent alert); schedule Tier 4 at PS5 - 10 min |
| `critical` | `resolved` | PS5 time reached OR all complete | Always | If all complete: celebration notification (Tier 5); if failed: no more notifications today |
| Any non-resolved | `resolved` | All tasks completed | `allNonNegotiables.isComplete` | Cancel all pending UNNotification requests; fire Tier 5 celebration; clear badge |
| Any non-resolved | `resolved` | Override activated (sick/rest day) | Machine 3 (Daily Accountability) enters `overrideActive` | Cancel all pending notifications; clear badge; log resolution reason `overrideActivated` |
| `resolved` | `quiet` | New day begins (00:00) | `currentDate > resolvedDate` | Reset all notification state; schedule next morning briefing; clear `notificationsSentToday` |
| Any | `quiet` | DND active | System Focus/DND detected | Defer notifications until DND ends; do not skip tiers (queue them) |
| `gentle` | `gentle` | User taps Snooze (1h) | `snoozesUsedToday < 1` (max 1 snooze per tier per day) | Reschedule Tier 1 for +1h |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `quiet` | Schedule morning briefing at configured time | -- |
| `gentle` | Fire Tier 0 (morning briefing); schedule Tier 1 check at noon-3PM | -- |
| `firm` | Fire Tier 1 (gentle reminder); schedule Tier 2 at 3-5PM | -- |
| `urgent` | Fire Tier 2 (firm warning); schedule Tier 3 at PS5-60min | -- |
| `critical` | Fire Tier 3 (urgent alert); schedule Tier 4 at PS5-10min; set `timeSensitive` | -- |
| `resolved` | Cancel all pending UNNotification requests for today; clear badge | Persist resolution reason and final tier reached |

### Swift Enum

```swift
enum NotificationEscalationState: Codable, Equatable {
    case quiet
    case gentle(briefingSentAt: Date)
    case firm(lastNotificationAt: Date)
    case urgent(lastNotificationAt: Date, notificationCount: Int)
    case critical(lastNotificationAt: Date)
    case resolved(reason: ResolutionReason)

    enum ResolutionReason: String, Codable {
        case allTasksComplete
        case dayEnded
        case overrideActivated  // sick/rest day
    }
}
```

### Persistence Strategy

| Field | Storage | Survives App Kill |
|-------|---------|-------------------|
| `state` | `UserDefaults["notification_escalation_state"]` | YES |
| `date` | `UserDefaults["notification_escalation_date"]` | YES |
| `notificationsSentToday` | `UserDefaults["notifications_sent_today"]` (JSON array) | YES |
| `snoozeCount` | `UserDefaults["snooze_count_today"]` | YES |

### UI Mapping

No direct UI. This machine operates in the background and drives `UNUserNotificationCenter`. The escalation state is visible indirectly through the Lockdown Main View's tone and urgency.

### Analytics Events

| Event | Properties |
|-------|-----------|
| `notification.sent` | `tier`, `messageId`, `completionPercent`, `timeToPS5` |
| `notification.tapped` | `tier`, `action: start_timer | view_plan | snooze`, `responseTime` |
| `notification.escalated` | `fromTier`, `toTier`, `completionPercent` |
| `notification.resolved` | `reason`, `finalTier`, `totalNotificationsSent` |

---

## 12. Workout Plan Generation

The AI-powered workout programming engine. Plans become stale when recovery data changes, the calendar shifts, or the user manually modifies exercises.

### State Diagram

```
    +---------+
    | stale   |  (no plan exists, or plan is outdated)
    +----+----+
         |
    [user opens Training tab OR new recovery data]
         |
    +----v-------+
    | generating |
    +----+-------+
         |
    [algorithm completes]
         |
    +----v-------+
    | ready      |
    +----+-------+
         |
    [user swaps exercise / changes sets / manual edit]
         |
    +----v-------+
    | modified   |
    +----+-------+
         |
    [new recovery data OR new calendar event OR
     deload trigger OR user requests regeneration]
         |
    +----v----------+
    | regenerating  |
    +----+----------+
         |
    +----v-------+
    | ready      |
    +------------+
```

### States

| State | Description |
|-------|-------------|
| `stale` | No valid workout plan. Needs generation. Trigger: first launch, new week, or invalidation. |
| `generating` | Algorithm is computing the workout plan (recovery data, calendar, progressive overload, periodization). |
| `ready` | Plan exists and is current. Displayed to user. |
| `modified` | User has made manual changes (swapped exercise, changed sets/reps). Plan is partially user-controlled. |
| `regenerating` | New data arrived that requires plan update (recovery changed, calendar changed). Preserves user modifications where possible. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `stale` | `generating` | App launch OR user opens Training | No valid plan for current week | Run generation algorithm; show loading skeleton |
| `generating` | `ready` | Algorithm completes | Valid plan produced | Display workout cards; animate in; persist to SwiftData |
| `generating` | `stale` | Algorithm fails | Missing required data (no training profile) | Show error: "Set up your training profile"; link to settings |
| `ready` | `modified` | User swaps exercise / edits sets / changes reps | User-initiated change | Persist modification; mark plan as `hasUserEdits: true`; show "Modified" badge |
| `ready` | `regenerating` | New Whoop recovery data differs significantly (>15% change) | Recovery score changed enough to affect volume | Regenerate with new recovery; adjust volume/intensity |
| `ready` | `regenerating` | Calendar event changes (football practice added/removed) | Football or class conflicts detected | Regenerate avoiding conflicts |
| `ready` | `stale` | New week begins (Monday 00:00) | Always | Invalidate current plan; trigger fresh generation |
| `modified` | `regenerating` | User taps "Regenerate" OR significant data change | Always | Regenerate but respect user exercise swaps where possible |
| `regenerating` | `ready` | Regeneration completes | Valid plan produced | Update plan; show diff if exercises changed; persist |
| `regenerating` | `modified` | Regeneration fails | Previous user-modified plan exists | Revert to previous modified plan; show error toast: "Could not update plan. Using current plan." |
| `regenerating` | `stale` | Regeneration fails | No previous plan to revert to | Show error: "Plan generation failed"; link to settings |
| `ready` | `ready` | Deload week triggered | `consecutiveHeavyWeeks >= deloadThreshold` | Transform current plan to deload variant (-40% volume); show deload banner |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| `generating` algorithm running | 15 seconds | Cancel; transition to `stale` with reason `manualInvalidation`; show "Plan generation timed out. Tap to retry." |
| `regenerating` algorithm running | 15 seconds | Cancel; revert to previous plan (`ready` or `modified`); show error toast |

### Swift Enum

```swift
enum WorkoutPlanState: Codable, Equatable {
    case stale(reason: StaleReason)
    case generating(startedAt: Date)
    case ready(generatedAt: Date, hasUserEdits: Bool)
    case modified(originalPlan: Date, lastEditAt: Date)
    case regenerating(reason: RegenerationReason, startedAt: Date)

    enum StaleReason: String, Codable {
        case noProfile
        case newWeek
        case firstLaunch
        case manualInvalidation
    }

    enum RegenerationReason: String, Codable {
        case recoveryChanged
        case calendarChanged
        case userRequested
        case deloadTriggered
    }
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `WeeklyPlan.state` | YES |
| `exercises` | `WeeklyPlan.days: [DailyPlan]` | YES |
| `generatedAt` | `WeeklyPlan.generatedAt: Date` | YES |
| `userEdits` | `WeeklyPlan.userEdits: [PlanEdit]` | YES |
| `recoveryScoreAtGeneration` | `WeeklyPlan.recoveryScore: Double?` | YES |

### UI Mapping

| State | Screen |
|-------|--------|
| `stale` | Today's Workout View -- "Generating your workout..." skeleton |
| `generating` | Today's Workout View -- skeleton loading |
| `ready` | Today's Workout View -- full exercise cards with recovery badge |
| `modified` | Today's Workout View -- "Modified" badge on edited exercises |
| `regenerating` | Today's Workout View -- brief shimmer on cards being updated |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `plan.generated` | `exerciseCount`, `recoveryScore`, `planType`, `duration` |
| `plan.modified` | `editType: swap | sets | reps | remove | add`, `exerciseId` |
| `plan.regenerated` | `reason`, `changedExercises` |
| `plan.deload_triggered` | `consecutiveWeeks`, `recoveryTrend` |

---

## 13. Recovery Prescription

The RecoverIQ prescription engine. Generates actionable recommendations from Whoop data. Must handle partial data and late-arriving data gracefully.

### State Diagram

```
    +--------------+
    | pending_data |  (waiting for Whoop sync to deliver today's scores)
    +------+-------+
           |
    [sufficient data received: recovery + sleep + strain]
           |
    +------v-------+
    | generating   |  (prescription algorithm running)
    +------+-------+
           |
    +------v-------+
    | active       |  (prescription displayed, actionable)
    +------+-------+
           |
    [midnight OR 18+ hours since generation]
           |
    +------v-------+
    | expired      |
    +------+-------+
           |
    [new day's data arrives]
           |
    +------v-------+
    | regenerating |
    +------+-------+
           |
    +------v-------+
    | active       |
    +--------------+
```

### States

| State | Description |
|-------|-------------|
| `pendingData` | Waiting for today's Whoop data. May have partial data (e.g., sleep but no recovery score yet). |
| `generating` | Algorithm is computing prescriptions from recovery score, HRV, RHR, sleep stages, strain history, calendar. |
| `active` | Prescription set is ready and displayed. Training, nutrition, sleep, caffeine, hydration recommendations. |
| `expired` | Prescription is from yesterday or > 18 hours old. Still displayed but marked as stale. |
| `regenerating` | New data arrived that materially changes the prescription (e.g., recovery score updated from "PENDING" to "SCORED"). |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `pendingData` | `generating` | Whoop sync delivers recovery data | `score_state == "SCORED"` | Extract: recovery score, HRV, RHR, sleep performance, skin temp; feed to algorithm |
| `pendingData` | `pendingData` | Whoop sync delivers partial data | `score_state == "PENDING_SCORE"` | Show "Recovery score processing..." with shimmer; cache partial data |
| `pendingData` | `generating` | Manual override (user says "I feel great/terrible") | User provides subjective input | Generate prescription from subjective + any partial data available |
| `generating` | `active` | Algorithm completes | Valid prescriptions produced (>= 1 recommendation) | Display prescription cards; persist to SwiftData; show feedback card after 6 PM |
| `generating` | `pendingData` | Algorithm fails | Insufficient data | Show "Waiting for more data" |
| `active` | `expired` | Midnight OR 18 hours since generation | `generatedAt + 18h < now` | Mark as "Yesterday's prescription" in grey; keep visible but add stale badge |
| `active` | `regenerating` | Recovery score updated (>10% change) | `abs(newScore - oldScore) > 10` | Re-run algorithm with updated score |
| `active` | `regenerating` | User taps "Refresh Prescription" | Always | Re-run with latest data |
| `expired` | `pendingData` | New day starts | Always | Clear old prescription; await new data |
| `regenerating` | `active` | Regeneration completes | Valid prescriptions produced | Update cards with diff animation; show "Updated" badge |
| `regenerating` | `active` | Regeneration fails | Previous prescriptions exist | Keep previous prescriptions; show error toast: "Could not refresh. Showing current prescription." |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| `generating` algorithm running | 10 seconds | Cancel; transition to `pendingData`; show "Prescription generation timed out. Will retry on next sync." |
| `regenerating` algorithm running | 10 seconds | Cancel; keep previous `active` prescriptions; show error toast |
| `pendingData` waiting for Whoop | 4 hours after expected Whoop sync | Show "Whoop data delayed" message; offer manual override input ("How do you feel?") |

### Swift Enum

```swift
enum RecoveryPrescriptionState: Codable, Equatable {
    case pendingData(partialData: PartialRecoveryData?)
    case generating(inputData: RecoveryInputData)
    case active(
        prescriptions: [Prescription],
        generatedAt: Date,
        recoveryScore: Double
    )
    case expired(prescriptions: [Prescription], generatedAt: Date)
    case regenerating(
        previousPrescriptions: [Prescription],
        reason: RegenerationReason
    )

    struct PartialRecoveryData: Codable, Equatable {
        var sleepData: SleepData?
        var strainData: StrainData?
        var recoveryScore: Double?
    }

    enum RegenerationReason: String, Codable {
        case scoreUpdated
        case userRequested
        case newDataArrived
    }
}
// CODABLE REQUIREMENT: `Prescription`, `RecoveryInputData`, `SleepData`,
// and `StrainData` MUST all conform to `Codable & Equatable` for this
// enum to compile. These types are defined in the data layer.
// Similarly, `AppSyncState.IntegrationSource` uses `Set<IntegrationSource>`
// which requires `Hashable` (already satisfied via `Codable` + `String` raw value).
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `DailyPrescription.state` | YES |
| `prescriptions` | `DailyPrescription.prescriptions: [Prescription]` | YES |
| `generatedAt` | `DailyPrescription.generatedAt: Date?` | YES |
| `recoveryScore` | `DailyPrescription.recoveryScore: Double?` | YES |
| `feedbackRating` | `DailyPrescription.feedbackRating: Rating?` | YES |

### UI Mapping

| State | Screen |
|-------|--------|
| `pendingData` | Recovery Today View -- shimmer/skeleton on prescription cards |
| `generating` | Recovery Today View -- "Generating prescriptions..." with pulsing dots |
| `active` | Recovery Today View -- full prescription cards with "Why this?" link |
| `expired` | Recovery Today View -- prescription cards with grey "Yesterday" badge |
| `regenerating` | Recovery Today View -- brief shimmer on updating cards |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| `pendingData` -> `active` (first of day) | "Your daily prescription is ready. Tap to see what to do today." |
| `active` (bedtime recommendation) | "RecoverIQ says: be in bed by {time} tonight." (scheduled at bedtime - 30 min) |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `prescription.generated` | `recoveryScore`, `prescriptionCount`, `zone` |
| `prescription.viewed` | `prescriptionId`, `timeOfDay` |
| `prescription.reasoning_tapped` | `prescriptionId` |
| `prescription.feedback_submitted` | `rating`, `hasFreeText`, `prescriptionId` |
| `prescription.regenerated` | `reason`, `scoreDelta` |

---

## 14. App Sync Orchestrator

Coordinates concurrent syncs across all integrations. Prevents thundering herd, handles priority ordering, and manages the offline queue.

### State Diagram

```
    +--------+
    | idle   |
    +---+----+
        |
    [sync trigger: periodic / pull-to-refresh / app foreground]
        |
    +---v--------+
    | syncing    |  (concurrent sub-machines)
    +---+--------+
        |
    +---+---+---+---+
    |   |   |   |   |
    v   v   v   v   |
   W   H   N   C   |   W = Whoop
   h   e   u   a   |   H = HealthKit
   o   a   t   l   |   N = NutriTrack
   o   l   r   e   |   C = Calendar
   p   t   i   n   |
       h   T   d   |
       K   r   a   |
       i   a   r   |
       t   c       |
           k       |
    +---+---+---+--+
        |
    +---v-----------+        +--------------------+
    | complete      |        | partial_failure    |
    +---------------+        +--------------------+
                             | (some syncs failed) |
                             +--------+-----------+
                                      |
                             +--------v-----------+
                             | retry              |
                             +--------------------+

    +-------------------+
    | full_failure      |  (all syncs failed -- likely offline)
    +--------+----------+
             |
    +--------v----------+
    | offline_queue     |  (operations queued for when network returns)
    +-------------------+
```

### States

| State | Description |
|-------|-------------|
| `idle` | No sync in progress. All data is current (or last sync is cached). |
| `syncing` | One or more integrations actively syncing. Concurrent sub-states per integration. |
| `complete` | All syncs succeeded. Data is fresh. |
| `partialFailure` | Some syncs succeeded, some failed. Show mixed status. |
| `fullFailure` | All syncs failed. Likely offline. |
| `retry` | Retrying failed syncs with exponential backoff. |
| `offlineQueue` | Device is offline. Mutations (set logged, task completed) queued for upload. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `idle` | `syncing` | Periodic timer (30 min) OR pull-to-refresh OR app foreground | Network available | Start parallel syncs: Whoop (if connected), HealthKit, NutriTrack (if connected), Calendar; priority order: HealthKit > Whoop > NutriTrack > Calendar |
| `syncing` | `complete` | All child syncs succeed | All integration sub-machines in `.idle` | Update `lastSyncAt` for each; refresh all UI; log `sync.completed` |
| `syncing` | `partialFailure` | Some succeed, some fail | At least one success AND one failure | Show success for completed; show error badge for failed; schedule retry |
| `syncing` | `fullFailure` | All fail | Network likely unavailable | Show "Offline" badge; activate offline queue |
| `partialFailure` | `retry` | Retry timer fires | Network available AND `attemptNumber < 3` | Re-attempt only failed syncs |
| `retry` | `complete` | Retried syncs succeed | All now successful | Update UI; transition to `idle` |
| `retry` | `partialFailure` | Some retries still failing | `attemptNumber < 3` | Schedule next retry (exponential: 2m, 4m, 8m) |
| `retry` | `idle` | Max retries exceeded | `attemptNumber >= 3` | Stop retrying; keep partial data from successful syncs; show persistent error badge on failed integrations; log `sync.max_retries_exceeded`; schedule next periodic sync normally |
| `fullFailure` | `offlineQueue` | Operations attempted while offline | Network unavailable | Queue operations with timestamps; process FIFO when network returns |
| `offlineQueue` | `syncing` | Network restored | `NWPathMonitor` detects connectivity | Flush queue in order; resume normal sync |
| `complete` | `idle` | UI updated | Always | Reset to idle; schedule next periodic sync |
| `partialFailure` | `idle` | No retry scheduled (max retries exceeded or user dismissed) | Always | Keep error badges for failed integrations; schedule next periodic sync |

### Timeout Handling

| Condition | Timeout | Action |
|-----------|---------|--------|
| Any individual sync within `syncing` | 30 seconds per integration | Cancel timed-out sync; mark that integration as failed; continue waiting for others |
| All syncs in `syncing` collectively | 60 seconds | Cancel all remaining syncs; transition to `partialFailure` (if any succeeded) or `fullFailure` |
| `offlineQueue` operations | N/A | Queue persists indefinitely; flushed in FIFO order when network returns; stale operations (> 24h) are discarded with log |
| `retry` between attempts | Exponential: 2m, 4m, 8m | Fire next retry attempt; if network lost during wait, transition to `offlineQueue` |

### Parallel Sync Combination Logic

When `syncing` with multiple concurrent sub-syncs, the parent state is determined by the **union** of child outcomes:
- **All succeed** -> `complete`
- **All fail** -> `fullFailure`
- **Mixed** -> `partialFailure` with `succeeded` and `failed` sets populated
- Each child sync is independent; one child's failure does NOT cancel other children.
- A child returning data triggers its corresponding UI refresh immediately (do not wait for all children).

### Swift Enum

```swift
enum AppSyncState: Codable, Equatable {
    case idle(lastSync: Date?)
    case syncing(activeSyncs: Set<IntegrationSource>)
    case complete(syncedAt: Date)
    case partialFailure(
        succeeded: Set<IntegrationSource>,
        failed: Set<IntegrationSource>,
        retryAt: Date?
    )
    case fullFailure(error: SyncError)
    case retry(
        failing: Set<IntegrationSource>,
        attemptNumber: Int,
        nextRetryAt: Date
    )
    case offlineQueue(queuedOperations: Int)

    enum IntegrationSource: String, Codable, Hashable {
        case whoop
        case healthKit
        case nutriTrack
        case calendar
    }

    enum SyncError: Codable, Equatable {
        case networkUnavailable
        case allFailed(errors: [String])
    }
}
```

### Persistence Strategy

| Field | Storage | Survives App Kill |
|-------|---------|-------------------|
| `lastSyncAt` (per integration) | SwiftData / UserDefaults | YES |
| `offlineQueue` | SwiftData `OfflineOperation` table | YES (critical: queued sets, completions) |
| `retryState` | UserDefaults | YES |

### UI Mapping

| State | Component |
|-------|-----------|
| `idle` | No visible indicator (data is fresh) |
| `syncing` | Pull-to-refresh spinner; recovery ring briefly spins |
| `complete` | Toast: "Data is up to date" (if user-triggered) |
| `partialFailure` | Amber badge on failed integration's card |
| `fullFailure` | "Offline" banner at top of Dashboard |
| `offlineQueue` | "Offline -- changes will sync when connected" banner |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `sync.started` | `trigger: periodic | pull_refresh | foreground`, `integrations` |
| `sync.completed` | `duration`, `dataPointsReceived` |
| `sync.partial_failure` | `succeeded`, `failed`, `errors` |
| `sync.full_failure` | `error` |
| `sync.offline_queue_flushed` | `operationCount`, `queueDuration` |

---

## 15. Subscription

StoreKit 2 subscription lifecycle. Must handle trial, grace period, billing failure, restore, and family sharing. A bug here means revenue loss or users losing access unexpectedly.

### State Diagram

```
    +--------+
    | free   |
    +---+----+
        |
    [user starts trial via StoreKit 2]
        |
    +---v----+
    | trial  |  (7 days)
    +---+----+
        |
    [trial converts (auto-renew) OR user purchases directly]
        |
    +---v----+
    | active |
    +---+----+
        |
    [billing failure]
        |
    +---v-----------+
    | grace_period  |  (Apple's 6/16-day grace)
    +---+-----------+
        |
    +---+---+
    |       |
    v       v
+------+ +--------+
|active| |expired |
|(paid)| +---+----+
+------+     |
             | [30 days, no re-subscribe]
             v
         +--------+
         | churned|
         +--------+
```

### States

| State | Description |
|-------|-------------|
| `free` | No subscription. Free tier features only. |
| `trial` | 7-day free trial of Pro. Full Pro access. Converts to paid at end unless cancelled. |
| `active` | Paid Pro subscription (monthly or annual). Full access. |
| `gracePeriod` | Subscription failed to renew (billing issue). Apple provides 6 days (weekly) or 16 days (monthly/annual) to resolve. Full access continues during grace. |
| `expired` | Subscription lapsed. Downgraded to free tier. Can still restore or re-subscribe. |
| `churned` | 30+ days since expiration with no re-subscribe. Marketing segment for win-back. |

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `free` | `trial` | User taps "Start Free Trial" | `Transaction.currentEntitlements` has no prior trial | Start StoreKit 2 purchase flow; on success: unlock Pro; sync to backend; log `subscription.trial_started` |
| `free` | `active` | User purchases (skipping trial or trial already used) | Purchase succeeds | Unlock Pro; sync to backend; show welcome; log `subscription.purchased` |
| `trial` | `active` | Trial period ends, auto-renew succeeds | StoreKit transaction update received | Seamless transition; no UI interruption; log `subscription.trial_converted` |
| `trial` | `free` | User cancels during trial AND trial period ends | StoreKit reports expiration with `isUpgraded == false` AND user had opted out of auto-renew | Downgrade to free; show "Trial ended" screen with re-subscribe CTA. Note: while cancellation is detected, Pro remains active until `endDate`; the "Your trial ends {date}" banner shows during the remaining trial period. |
| `trial` | `expired` | Trial ends, payment method fails | StoreKit reports billing failure at trial-to-paid conversion | Downgrade to free; show "Trial ended -- billing issue" screen with re-subscribe CTA; do NOT grant grace period for trial conversions |
| `active` | `gracePeriod` | Renewal fails (billing issue) | Apple webhook `DID_FAIL_TO_RENEW` | Continue Pro access; after 3 days: in-app banner "Billing issue"; after 6 days: push notification; log `subscription.billing_issue` |
| `gracePeriod` | `active` | Billing resolved | Apple webhook `DID_RENEW` | Remove billing banner; log `subscription.billing_resolved` |
| `gracePeriod` | `expired` | Grace period ends without resolution | Apple webhook `EXPIRED` | Downgrade to free; show "Subscription expired" banner; lock Pro features; log `subscription.expired` |
| `active` | `expired` | User explicitly cancels and period ends | StoreKit reports expiration | Downgrade to free at period end; show "Your Pro ends {date}" until then |
| `expired` | `active` | User re-subscribes | Purchase succeeds | Unlock Pro; sync to backend; log `subscription.resubscribed` |
| `expired` | `active` | User taps Restore Purchases | `Transaction.currentEntitlements` finds active subscription (e.g., from another device) | Unlock Pro; show "Pro restored!" |
| `expired` | `churned` | 30 days after expiration | No re-subscribe | Marketing segment transition; eligible for win-back offers |
| `churned` | `active` | User re-subscribes (possibly with win-back offer) | Purchase succeeds | Unlock Pro; log `subscription.winback` |
| `free` | `active` | Family sharing grants access | StoreKit detects family subscription | Unlock Pro; show "Pro via Family Sharing" badge |
| Any | `active` | Promotional offer redeemed | StoreKit promotional offer | Unlock Pro for offer duration |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `free` | Lock Pro features; show soft paywalls; set `isPro = false` | -- |
| `trial` | Unlock all Pro features; schedule trial-end notification (day 5); set `isPro = true` | -- |
| `active` | Unlock all Pro features; set `isPro = true`; sync to backend | -- |
| `gracePeriod` | Keep Pro unlocked; show billing issue banner (after 3 days); schedule push (6 days) | -- |
| `expired` | Lock Pro features; show "Subscription expired" banner; show re-subscribe CTA; set `isPro = false` | -- |
| `churned` | Same as expired; flag for win-back marketing | -- |

### Swift Enum

```swift
enum SubscriptionState: Codable, Equatable {
    case free
    case trial(startDate: Date, endDate: Date)
    case active(
        productId: String,
        expirationDate: Date,
        isAutoRenewing: Bool
    )
    case gracePeriod(
        productId: String,
        graceEndDate: Date,
        failedAt: Date
    )
    case expired(
        lastProductId: String,
        expiredAt: Date
    )
    case churned(
        lastProductId: String,
        expiredAt: Date,
        churnedAt: Date
    )

    var isPro: Bool {
        switch self {
        case .free, .expired, .churned: return false
        case .trial, .active, .gracePeriod: return true
        }
    }
}
```

### Persistence Strategy

| Field | Storage | Survives App Kill |
|-------|---------|-------------------|
| `state` | Backend `user_subscriptions` table + local cache via StoreKit 2 `Transaction.currentEntitlements` | YES |
| `productId` | Backend + StoreKit | YES |
| `expirationDate` | Backend + StoreKit | YES |
| `isTrial` | Backend `is_trial` column | YES |
| `originalTransactionId` | Backend (unique key for subscription lifecycle) | YES |

### UI Mapping

| State | Screen |
|-------|--------|
| `free` | Paywall screen when tapping Pro features; "Free" label in Settings |
| `trial` | "Pro Trial -- {N} days remaining" banner; full Pro UI |
| `active` | "Tempo Pro" badge in Settings; no paywall interruptions |
| `gracePeriod` | "Billing issue" banner (after 3 days); Pro features still work |
| `expired` | "Subscription expired" banner; soft paywalls return; "Resubscribe" CTA |
| `churned` | Same as expired + potential win-back offer banner |

### Notification Triggers

| Transition | Notification |
|------------|-------------|
| `trial` day 5 | "Your Pro trial ends in 2 days. Here's what you'd lose: {features}." |
| `trial` -> `free` (cancelled) | "Your trial has ended. We hope you enjoyed Pro." |
| `gracePeriod` day 6 | "Billing issue with your Tempo Pro subscription. Update your payment method." |
| `expired` | "Your Pro subscription has expired. Resubscribe to keep AI training, full drill sergeant, and unlimited friends." |
| `churned` (win-back) | "We miss you. Come back to Pro -- your {streakLength}-day streak data is waiting." |

### Analytics Events

| Event | Properties |
|-------|-----------|
| `subscription.trial_started` | `productId` |
| `subscription.trial_converted` | `productId`, `trialDuration` |
| `subscription.purchased` | `productId`, `price`, `isAnnual` |
| `subscription.billing_issue` | `productId`, `graceEndDate` |
| `subscription.billing_resolved` | `productId`, `daysInGrace` |
| `subscription.expired` | `productId`, `lifetimeDuration`, `wasAutoRenewing` |
| `subscription.resubscribed` | `productId`, `daysLapsed` |
| `subscription.restored` | `productId`, `fromDevice` |
| `subscription.churned` | `productId`, `daysSinceExpiry` |

---

## 16. Exercise Set

Each individual set within a workout has its own lifecycle. Handles weight/rep changes mid-set, RPE entry, undo, and the special cases of failed sets and skipped sets.

### State Diagram

```
    +---------+
    | pending |
    +----+----+
         |
    [set becomes active (previous set done + rest complete)]
         |
    +----v--------+
    | in_progress |<----+
    +----+--------+     |
         |              |
    +----+----+----+    |
    |    |    |    |    |
    v    v    v    |    |
+-----+ +--+ +---+|   |
|compl| |fa| |ski| |   |
|eted | |il| |ppe| |   |
+--+--+ +-++ |d  | |   |
   |      |  +---+ |   |
   |      |        |   |
   +------+--------+   |
          |             |
      [undo within 10s] |
          +-------------+
```

### States

| State | Description |
|-------|-------------|
| `pending` | Set has not been reached yet in the workout sequence. Weight/reps show target values. |
| `inProgress` | This is the current active set. Weight/reps inputs are editable. DONE button is live. |
| `completed` | User tapped DONE. Weight and reps recorded. Set slides into completed area. |
| `failed` | User logged 0 reps (confirmed). Marked with red X. Counts as attempted but failed. |
| `skipped` | User explicitly skipped this set (from context menu or by advancing). No weight/reps recorded. |

> **Note:** `undone` is NOT a persisted state. It is a transient transition action: when the user taps Undo on a `completed` or `failed` set, the set reverts directly to `inProgress`. The `undone` label exists only for analytics tracking (`set.undone` event). The Swift enum does NOT include an `undone` case.

### Transitions

| From | To | Trigger | Guard | Action |
|------|----|---------|-------|--------|
| `pending` | `inProgress` | Previous set completed + rest done (or this is set 1) | Set is next in sequence | Pre-fill weight (sticky from previous set or target); pre-fill reps; show plate hint; activate DONE button |
| `inProgress` | `completed` | User taps DONE | `weight > 0 AND reps > 0` | Record weight, reps, timestamp; check for PR; fire haptic `.success`; checkmark animation; slide to completed area; start rest timer |
| `inProgress` | `failed` | User taps DONE with 0 reps | `reps == 0` confirmed via dialog | Record weight, 0 reps; mark with red X; no PR check; fire haptic `.error`; start rest timer |
| `inProgress` | `skipped` | User taps Skip Set (context menu) | Always | No data recorded; advance to next set or exercise; no rest timer |
| `completed` | `inProgress` (undo) | User taps Undo (within 10s) | `timeSinceCompletion < 10s` | Revert set; remove from completed area; cancel rest timer; restore inputs |
| `failed` | `inProgress` (undo) | User taps Undo | `timeSinceCompletion < 10s` | Same as above |
| `inProgress` | `inProgress` | Weight changed mid-set | User adjusts stepper/keypad/picker | Update weight display; update plate hint; mark as user-modified |
| `inProgress` | `inProgress` | Reps changed | User adjusts reps stepper | Update reps display; color-code if below target |
| `completed` | `completed` | RPE entered | User taps RPE button (1-10) | Record RPE value; show RPE badge on completed set row |
| `inProgress` | `skipped` | Parent workout enters `cooldown` or `summary` | This set was `inProgress` when workout ended early | Auto-skip remaining sets; mark as `skipped(at: now)` |

### Entry/Exit Actions

| State | Entry Action | Exit Action |
|-------|-------------|-------------|
| `pending` | Show target weight/reps in muted style; DONE button disabled | -- |
| `inProgress` | Activate weight/reps inputs; enable DONE button; show plate hint; scroll to center | Persist current input values |
| `completed` | Checkmark draw (0.3s); haptic `.success`; slide row into completed area; increment set counter | Update volume totals; check PR |
| `failed` | Red X animation; haptic `.error` | Log failed attempt |
| `skipped` | Grey out row; show "SKIPPED" label | -- |

### Swift Enum

```swift
enum ExerciseSetState: Codable, Equatable {
    case pending(targetWeight: Double, targetReps: Int)
    case inProgress(
        currentWeight: Double,
        currentReps: Int,
        isUserModified: Bool
    )
    case completed(
        weight: Double,
        reps: Int,
        rpe: Int?,
        completedAt: Date,
        isPR: Bool
    )
    case failed(
        weight: Double,
        attemptedAt: Date
    )
    case skipped(at: Date)
}
```

### Persistence Strategy

| Field | SwiftData Model | Survives App Kill |
|-------|----------------|-------------------|
| `state` | `WorkoutSet.state` | YES |
| `weight` | `WorkoutSet.weight: Double` | YES |
| `reps` | `WorkoutSet.reps: Int` | YES |
| `rpe` | `WorkoutSet.rpe: Int?` | YES |
| `completedAt` | `WorkoutSet.completedAt: Date?` | YES |
| `isPR` | `WorkoutSet.isPR: Bool` | YES |

### UI Mapping

| State | Component |
|-------|-----------|
| `pending` | Greyed-out row in "Upcoming Sets" area |
| `inProgress` | Active set logging row -- weight/reps inputs, DONE button |
| `completed` | Row in "Completed Sets" area with green checkmark, weight x reps |
| `failed` | Row in "Completed Sets" with red X, weight, "0 reps" |
| `skipped` | Row in "Completed Sets" with grey "SKIPPED" label |

### Notification Triggers

None. Exercise sets are entirely in-app interactions. The parent Workout Session machine handles workout-level notifications.

### Analytics Events

| Event | Properties |
|-------|-----------|
| `set.completed` | `exerciseId`, `weight`, `reps`, `rpe`, `isPR`, `isWarmup` |
| `set.failed` | `exerciseId`, `weight` |
| `set.skipped` | `exerciseId`, `setNumber` |
| `set.undone` | `exerciseId`, `secondsAfterCompletion` |
| `set.weight_changed` | `exerciseId`, `fromWeight`, `toWeight`, `inputMethod: stepper | picker | keypad` |

---

## Appendix A: Cross-Machine Interaction Map

These interactions are MANDATORY -- when a state machine transition fires, it MUST trigger the corresponding cross-machine events. Missing any of these creates inconsistent state.

| Source Machine | Trigger Transition | Target Machine(s) | Required Action |
|---------------|-------------------|-------------------|----------------|
| **1. Workout Session** | `summary` -> `saved` | 8. Challenge (update `workoutCount` / `caloriesBurned` scores); 7. Streak (re-evaluate daily completion via Non-Negotiable); 14. App Sync (queue backend sync) | Emit `WorkoutCompleted` event with `totalVolume`, `exerciseCount`, `prCount` |
| **2. Focus Timer** | `review` -> `idle` | 6. Non-Negotiable (update study-hours progress); 7. Streak (re-evaluate); 8. Challenge (update `studyHours` metric) | Emit `FocusSessionCompleted` event with `totalFocusTime`, `subject` |
| **3. Daily Accountability** | `tracking` -> `unlocked` | 7. Streak (`active(N)` -> `active(N+1)` at day boundary); 11. Notification Escalation (-> `resolved`) | Emit `DayUnlocked` event |
| **3. Daily Accountability** | Any -> `overrideActive` | 11. Notification Escalation (-> `resolved` with reason `overrideActivated`); 7. Streak (day does not count but does not break) | Emit `OverrideActivated` event |
| **4. Whoop Sync** | `connected.syncing` -> `connected.idle` | 12. Workout Plan (trigger regeneration if recovery > 15% change); 13. Recovery Prescription (trigger generation if `pendingData`) | Emit `WhoopDataReceived` event with `recoveryScore`, `hrv`, `strain` |
| **5. NutriTrack Sync** | `connected.syncing` -> `connected.idle` | 6. Non-Negotiable (update meal-count progress) | Emit `NutriTrackDataReceived` event with `mealCount`, `macros` |
| **6. Non-Negotiable** | Any -> `completed` | 3. Daily Accountability (re-evaluate if all complete -> `unlocked`); 8. Challenge (update relevant metric) | Emit `NonNegotiableCompleted` event |
| **7. Streak** | `active(N)` -> `atRisk` | 11. Notification Escalation (escalate to at least `urgent` tier) | Emit `StreakAtRisk` event with `dayCount`, `minutesToMidnight` |
| **15. Subscription** | Any -> `expired` / `churned` | All feature-gated machines: lock Pro features; 12. Workout Plan (disable AI-powered generation, use basic templates) | Emit `SubscriptionStateChanged` event |

---

## Appendix B: Concurrent State Region Rules

### Workout Session -- Exercise Sub-States

The `exercise` state contains three mutually exclusive sub-states: `setActive`, `resting`, `betweenExercises`. The pause overlay is ORTHOGONAL to these sub-states, meaning:

- `exercise.setActive` + user taps Pause -> `paused(previousState: .exercise(.setActive(...)))`
- `exercise.resting` + user taps Pause -> `paused(previousState: .exercise(.resting(...)))`
- `exercise.betweenExercises` + user taps Pause -> `paused(previousState: .exercise(.betweenExercises(...)))`
- `warmup` + user taps Pause -> `paused(previousState: .warmup(...))`
- `cooldown` + user taps Pause -> `paused(previousState: .cooldown)`

ALL five pause transitions MUST exist. The `PausedFromState` enum MUST cover all five cases (it currently covers `warmup`, `exercise`, and `cooldown` -- which is correct since `exercise` wraps `ExerciseSubState`).

### App Sync Orchestrator -- Parallel Sub-Syncs

The `syncing` state runs up to 4 child syncs concurrently. The combination logic:
- Each child sync is independent: Whoop, HealthKit, NutriTrack, Calendar.
- Each child has its own timeout (30s).
- The parent `syncing` state transitions based on the UNION of child outcomes (see Parallel Sync Combination Logic in Machine 14).
- If a child fails but another is still running, the parent remains in `syncing` until all children complete or timeout.

---

## Appendix C: State Machine Invariants

These invariants must hold across ALL state machines. Violations indicate bugs.

### Global Invariants

1. **No state machine may be in two states simultaneously** (except concurrent sub-state regions explicitly modeled, such as Workout Session's exercise sub-states).

2. **Every terminal state is reachable.** There are no dead-end states from which the user cannot escape.

3. **Every non-terminal state has at least one exit transition.** No state traps the user forever.

4. **App kill at ANY state must result in recoverable state on relaunch.** Every state machine's persistence strategy must guarantee this.

5. **Network loss must NEVER cause data loss.** All user-generated data (sets, timer sessions, task completions) must persist locally first, sync later.

6. **Time-dependent transitions must use `Date` comparisons, not background timers.** iOS kills background timers. Always calculate elapsed time from `Date()` diff on foreground return.

7. **State transitions must be atomic.** The state variable, associated data, and SwiftData writes must occur in a single transaction. No partial state updates.

8. **All `Codable` state enums must handle unknown cases gracefully.** When a new case is added in a future version, old persisted data decoded without it must fall back to a safe default (typically `idle` or the initial state).

9. **Cross-machine events must fire AFTER the source transition completes and persists.** Never fire a cross-machine event from a state that has not been committed to storage. This prevents cascading failures from leaving two machines in inconsistent states.

10. **Timeout transitions must always target a recoverable state.** A timeout must never transition to a permanent error state. It must either retry, fall back to a previous state, or transition to a terminal state with data preserved.

### Testing Requirements

Each state machine should have:
- **Exhaustive transition tests**: every transition in the table is tested.
- **Invalid transition tests**: attempting an illegal transition (e.g., `idle` -> `summary`) throws or is a no-op.
- **Persistence round-trip tests**: encode state to JSON/SwiftData, decode, verify equality.
- **Timeout tests**: mock clock advances to verify timeout transitions fire correctly.
- **Crash recovery tests**: simulate app kill at each state, verify correct recovery on relaunch.
- **Concurrent access tests**: verify actor isolation prevents race conditions on state updates.
- **Cross-machine event tests**: verify that when a source transition fires, all target machines receive and process the event correctly.
- **Timeout recovery tests**: for every state with a timeout, verify the timeout transitions to a recoverable state and does not lose data.
