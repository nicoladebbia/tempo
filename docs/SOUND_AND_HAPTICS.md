# Tempo — Sound Design & Haptics Specification v1.0

> **Every tap should feel like racking a barbell. Every completion should hit like a deadlift PR.**

This document is the single source of truth for every sound effect, haptic pattern, ambient track, and audio-haptic synchronization in Tempo. Sound and haptics are not decoration — they are 50% of what makes Tempo feel like a premium, addictive, no-nonsense life operating system.

---

## Table of Contents

1. [Audio Identity](#1-audio-identity)
2. [Complete Sound Effect Catalog](#2-complete-sound-effect-catalog)
3. [Ambient Sound Library](#3-ambient-sound-library)
4. [Complete Haptic Catalog](#4-complete-haptic-catalog)
5. [Core Haptics Patterns (AHAP Files)](#5-core-haptics-patterns-ahap-files)
6. [Audio-Haptic Synchronization](#6-audio-haptic-synchronization)
7. [Sound Settings](#7-sound-settings)
8. [Audio File Specifications](#8-audio-file-specifications)

---

## 1. Audio Identity

### 1.1 Sonic Brand

Tempo's sound palette is **military-industrial precision meets modern electronic minimalism**. Think: the satisfying mechanical click of a weapon being armed, crossed with the clean digital tones of a spacecraft control panel. No organic warmth. No playful boops. Every sound communicates that this system is precise, purposeful, and in control.

**The sonic equation:** `Mechanical clicks + Digital tones + Metallic resonance = Tempo`

The overall palette is built from three sonic layers:

| Layer | Description | Examples |
|-------|-------------|---------|
| **Transient layer** | Ultra-short mechanical impacts — clicks, snaps, taps. Sub-50ms. These form the backbone of all interaction feedback. | Metal latch closing, bolt action, precision switch |
| **Tonal layer** | Clean sine/triangle/square wave tones at specific pitches. No reverb. Dry, immediate, definitive. 100-500ms. | Digital confirmation beep, military radio acknowledge |
| **Resonance layer** | Short metallic or glass resonance tails that give sounds a sense of physical weight. 200ms-1s decay. | Bell strike decay, industrial chime, steel plate ring |

### 1.2 Key Sonic Characteristics

- **Sharp.** Attack time under 5ms for all transient sounds. No soft fades in.
- **Clean.** No reverb on UI sounds. Ambient sounds live in their own spatial context.
- **Purposeful.** Every sound maps to exactly one meaning. Users should be able to identify what happened with eyes closed.
- **Hierarchical.** Sound intensity matches importance: navigation sounds are whisper-quiet; PR celebrations are commanding.
- **Non-fatiguing.** Workout sounds play dozens of times per session. They must be satisfying on rep 1 and rep 200.

### 1.3 Pitch Language

Tempo uses a deliberate pitch vocabulary to convey meaning instantly:

| Pitch Direction | Meaning | Used For |
|----------------|---------|----------|
| **Rising (low to high)** | Progress, completion, achievement | Set complete, exercise complete, XP earned |
| **Falling (high to low)** | Warning, attention needed, loss | Timer expiring, challenge lost, error |
| **Flat / single note** | Neutral action, acknowledgment | Tab switch, button press, weight adjust |
| **Ascending scale** | Major accomplishment, celebration | PR achieved, level up, workout complete |
| **Double pulse** | Urgency, interruption | Urgent notification, rest timer done |

### 1.4 Reference Apps for Sonic Direction

| App | What to take | What to avoid |
|-----|-------------|---------------|
| **Strong (workout app)** | Set completion sound is clean, satisfying, non-fatiguing. Good weight of feedback. | Sounds feel generic, not branded. |
| **Peloton** | Milestone sounds feel earned and celebratory. Leaderboard pass sound creates competitive tension. | Can be over-produced; music mixing is heavy. |
| **Apple Fitness+** | Achievement tones are warm but crisp. Haptic-audio pairing is flawless. | Too friendly for Tempo's drill-sergeant personality. |
| **Duolingo** | XP collection sound creates genuine dopamine. Streak sounds trigger loss aversion. Perfect gamification audio. | Too playful/cute. Tempo should feel industrial, not animated. |
| **Things 3** | Task completion sound is one of the most satisfying in any app — proves a simple sound can carry immense weight. | Single sound — no system/hierarchy. |
| **Strava** | Segment crown sounds feel competitive. Activity completion has gravitas. | Sparse audio system overall. |

### 1.5 Master Volume Strategy

| System State | Tempo Behavior |
|-------------|----------------|
| **Ring mode (normal)** | All sounds play at user-controlled volume (respects system volume slider) |
| **Silent mode (mute switch on)** | No sounds play. Haptics still fire. |
| **Do Not Disturb** | No notification sounds. In-app sounds play normally if app is foregrounded. |
| **Low Power Mode** | All sounds play normally. Haptics reduced to system-level feedback only (no custom Core Haptics). |
| **User's music playing** | Tempo sounds play as overlay (AVAudioSession category `.ambient`). Never pause or duck user music for UI sounds. Timer completion and notifications use `.playback` momentarily to play over music. |
| **Headphones connected** | All sounds route to headphones. Haptics still fire on device. |
| **Focus timer ambient active** | Ambient audio mixes with notification sounds. Notification sounds briefly duck ambient by 50% (300ms duck, 200ms release). |

**AVAudioSession Configuration:**
```
Category: .ambient (default for UI sounds)
Mode: .default
Options: [.mixWithOthers]

For timer completions and notifications:
Category: .playback (temporary, 2-second window)
Mode: .default
Options: [.duckOthers]
```

---

## 2. Complete Sound Effect Catalog

### 2.1 Sound Naming Convention

All sounds follow: `tempo_[module]_[action]`

Modules: `workout`, `timer`, `notif`, `arena`, `system`

### 2.2 Workout Sounds

#### `tempo_workout_set_complete`

| Property | Value |
|----------|-------|
| **Description** | Short, sharp metallic click-snap with a micro-tonal rise. The signature sound of Tempo. A mechanical latch engaging — like the barbell clip clicking into place. Subtle harmonic at 2kHz gives it "brightness" without harshness. |
| **Duration** | 0.3s (250ms sound + 50ms tail) |
| **Trigger** | User taps to complete any individual set |
| **Emotional purpose** | Instant dopamine. "That rep counted. You're making progress." This sound should be so satisfying that users look forward to tapping sets complete. |
| **Frequency of play** | 15-40 times per workout session. Must be non-fatiguing at high repetition. |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | MANDATORY |
| **Pitch** | Base: C5 (523Hz). Rises to D5 (587Hz) over 80ms. |
| **Volume relative to master** | 70% |

#### `tempo_workout_exercise_complete`

| Property | Value |
|----------|-------|
| **Description** | Two-part sound: the set_complete click followed immediately (50ms gap) by a slightly longer resonant tone — like a lock sliding into a heavier mechanism. Think: bolt closing + confirmation chime. More substantial than set_complete but not celebratory. |
| **Duration** | 0.5s |
| **Trigger** | All sets for an exercise are marked complete |
| **Emotional purpose** | Checkpoint passed. One exercise down. Acknowledgment of a larger unit of work. |
| **Frequency of play** | 4-8 times per workout |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | C5 click → E5 (659Hz) tone, 200ms sustain with 100ms decay |
| **Volume relative to master** | 80% |

#### `tempo_workout_start`

| Property | Value |
|----------|-------|
| **Description** | A short ascending three-note motif — C4, E4, G4 — played in rapid staccato (each note 80ms, 40ms gap). Clean square-wave synth with slight metallic edge. Ends with a single sharp snap. The "mission started" sound. |
| **Duration** | 0.8s |
| **Trigger** | User taps "Start Workout" button |
| **Emotional purpose** | Energizing. "Time to work. No more talking." Primes the user's nervous system for effort. |
| **Frequency of play** | Once per session |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 40KB |
| **Priority** | MANDATORY |
| **Pitch** | C4 (262Hz) → E4 (330Hz) → G4 (392Hz) |
| **Volume relative to master** | 90% |

#### `tempo_workout_complete`

| Property | Value |
|----------|-------|
| **Description** | The victory sound. A compressed, punchy ascending fanfare: low metallic impact (like a gong tap) followed by a quick ascending arpeggio (C4-E4-G4-C5) in clean synth, ending with a sustained C5 note that decays with slight metallic shimmer. Not overly dramatic — earned, not theatrical. |
| **Duration** | 1.5s |
| **Trigger** | User completes final exercise and workout is marked done |
| **Emotional purpose** | Triumph. "Mission complete. You did the work." This sound should make the user feel genuinely accomplished. |
| **Frequency of play** | Once per session |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 75KB |
| **Priority** | MANDATORY |
| **Pitch** | C4 → E4 → G4 → C5 arpeggio, C5 sustain with shimmer |
| **Volume relative to master** | 100% |

#### `tempo_workout_rest_tick`

| Property | Value |
|----------|-------|
| **Description** | Minimal, dry click — like a single metronome tick on wood. Almost subliminal. No tonal component, pure transient. |
| **Duration** | 0.1s (80ms transient + 20ms silence) |
| **Trigger** | Plays once per second during the final 5 seconds of rest timer |
| **Emotional purpose** | Building urgency. Countdown. "Get ready." |
| **Frequency of play** | 5 times per rest period (only last 5 seconds) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 5KB |
| **Priority** | MANDATORY |
| **Pitch** | Unpitched transient, centered around 1.5kHz |
| **Volume relative to master** | 50% (subtle) |

#### `tempo_workout_rest_done`

| Property | Value |
|----------|-------|
| **Description** | Sharp double-tap tone — two identical short tones (100ms each) with 80ms gap. Higher pitch than rest_tick. Like a digital whistle blow. Cuts through gym noise and headphone music. |
| **Duration** | 0.5s (100ms tone + 80ms gap + 100ms tone + 220ms tail) |
| **Trigger** | Rest timer reaches zero |
| **Emotional purpose** | "Time's up. Get under the bar." Demands attention without being alarming. |
| **Frequency of play** | 10-30 times per workout |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | A5 (880Hz) double pulse |
| **Volume relative to master** | 90% |

#### `tempo_workout_pr_achieved`

| Property | Value |
|----------|-------|
| **Description** | The PR sound must feel DIFFERENT from everything else. A sharp metallic strike (like hitting a steel plate) followed by a brief ascending shimmer (think: achievement unlocked in a AAA game, compressed to 1 second). Clean, punchy, unmistakable. Subtle stereo widening in the shimmer tail. |
| **Duration** | 1.0s |
| **Trigger** | System detects a new personal record (weight or reps) |
| **Emotional purpose** | "NEW RECORD." Pure celebration. The user should involuntarily smile. This sound is a dopamine injector. |
| **Frequency of play** | 0-3 times per workout (rare = special) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | Impact: unpitched metallic. Shimmer: G5 → B5 → D6 rapid arpeggio with 500ms decay |
| **Volume relative to master** | 100% |

#### `tempo_workout_weight_adjust`

| Property | Value |
|----------|-------|
| **Description** | Ultra-minimal tactile click. Like a physical detent on a rotary dial. Pure transient, no tone. Barely audible — the haptic does the heavy lifting here. |
| **Duration** | 0.05s |
| **Trigger** | Each step of the weight stepper (+/- buttons, or scroll) |
| **Emotional purpose** | Physical feedback for a digital control. Makes the stepper feel mechanical and precise. |
| **Frequency of play** | 10-50 times per workout (high frequency during weight entry) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 3KB |
| **Priority** | Optional (haptic alone is sufficient) |
| **Pitch** | Unpitched click, 3kHz center |
| **Volume relative to master** | 30% |

#### `tempo_workout_exercise_swipe`

| Property | Value |
|----------|-------|
| **Description** | Quick directional whoosh — a filtered noise sweep, low-to-high for forward swipe, high-to-low for backward swipe. Very subtle. Like turning a page in a steel-bound manual. |
| **Duration** | 0.2s |
| **Trigger** | Swiping between exercises in the active workout view |
| **Emotional purpose** | Spatial orientation. "Moving forward through the workout." |
| **Frequency of play** | 4-8 times per workout |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 10KB (two variants: forward/backward) |
| **Priority** | Optional |
| **Pitch** | Forward: 400Hz → 1.2kHz sweep. Backward: 1.2kHz → 400Hz sweep |
| **Volume relative to master** | 40% |

#### `tempo_workout_rep_count`

| Property | Value |
|----------|-------|
| **Description** | Minimal counting click — slightly softer and less "complete" than set_complete. Like a tally counter click. For bodyweight exercises or running where individual reps are tracked. |
| **Duration** | 0.1s |
| **Trigger** | Each rep logged (manual tap or auto-detection) |
| **Emotional purpose** | Rhythm. Counting. "Each one counts." |
| **Frequency of play** | 10-100+ per session (if enabled for bodyweight work) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 5KB |
| **Priority** | Optional (disabled by default, enable in settings) |
| **Pitch** | Unpitched click, 2kHz center, slightly softer attack than set_complete |
| **Volume relative to master** | 40% |

#### `tempo_workout_superset_transition`

| Property | Value |
|----------|-------|
| **Description** | Quick two-tone toggle — a low click followed immediately by a high click (like shifting gears). Signals transitioning from Exercise A to Exercise B within a superset. |
| **Duration** | 0.2s |
| **Trigger** | Transitioning between exercises in a superset pair |
| **Emotional purpose** | "Switch now. No rest. Keep moving." Quick transition energy. |
| **Frequency of play** | 2-8 times per workout (only during supersets) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 10KB |
| **Priority** | Optional |
| **Pitch** | E4 (330Hz) → A4 (440Hz), 50ms each, 40ms gap |
| **Volume relative to master** | 60% |

#### `tempo_workout_warmup_complete`

| Property | Value |
|----------|-------|
| **Description** | Soft ascending chime — lighter than exercise_complete. A gentle "ready to go" signal. Like tapping a small brass bell. |
| **Duration** | 0.4s |
| **Trigger** | User completes warm-up sets and transitions to working sets |
| **Emotional purpose** | "Warm-up done. Now the real work starts." |
| **Frequency of play** | 1-4 times per workout |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 20KB |
| **Priority** | Optional |
| **Pitch** | G4 → B4 quick rise, 300ms decay |
| **Volume relative to master** | 60% |

---

### 2.3 Timer Sounds

#### `tempo_timer_pomodoro_start`

| Property | Value |
|----------|-------|
| **Description** | Clean, focused "begin" tone. A single resolute note — like pressing a button on a mission timer. Sharp attack, quick 300ms decay. Signals the transition from idle to focused state. |
| **Duration** | 0.5s |
| **Trigger** | User starts a Pomodoro focus session |
| **Emotional purpose** | "Focus time. Starting now." Mental state shift. |
| **Frequency of play** | 4-12 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | E4 (330Hz), clean sine tone, sharp attack, 300ms exponential decay |
| **Volume relative to master** | 75% |

#### `tempo_timer_pomodoro_tick`

| Property | Value |
|----------|-------|
| **Description** | Ultra-subtle ambient tick. Barely perceptible — just enough to maintain awareness that the timer is running. Like a clock ticking in a quiet library. |
| **Duration** | 0.1s |
| **Trigger** | Once per minute during an active Pomodoro (optional, off by default) |
| **Emotional purpose** | Time awareness without distraction. Subtle accountability. |
| **Frequency of play** | 25-50 per session (if enabled) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 5KB |
| **Priority** | Optional (disabled by default) |
| **Pitch** | Unpitched soft transient, 800Hz center, very low amplitude |
| **Volume relative to master** | 20% |

#### `tempo_timer_pomodoro_warning`

| Property | Value |
|----------|-------|
| **Description** | Two soft rising tones — a gentle "heads up" that the session is ending soon. Less jarring than rest_done. Like a polite chime on a train before the doors close. |
| **Duration** | 0.4s |
| **Trigger** | 2 minutes remaining in Pomodoro session |
| **Emotional purpose** | "Almost there. Finish strong." Anticipation without breaking focus. |
| **Frequency of play** | Once per Pomodoro |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 20KB |
| **Priority** | MANDATORY |
| **Pitch** | C5 → E5, 120ms each, 80ms gap |
| **Volume relative to master** | 60% |

#### `tempo_timer_pomodoro_complete`

| Property | Value |
|----------|-------|
| **Description** | Satisfying session-complete bell. A clean metallic bell strike with gentle decay — like a meditation bowl, but shorter and more precise. The sound of a well-spent 25 minutes. |
| **Duration** | 0.8s |
| **Trigger** | Pomodoro timer reaches zero |
| **Emotional purpose** | "Session complete. You earned this break." Satisfaction and permission to rest. |
| **Frequency of play** | 4-12 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 40KB |
| **Priority** | MANDATORY |
| **Pitch** | G5 (784Hz) bell strike, 600ms natural decay |
| **Volume relative to master** | 85% |

#### `tempo_timer_break_start`

| Property | Value |
|----------|-------|
| **Description** | Gentle descending two-note transition. The inverse of pomodoro_start — signals downshift from focus to rest. Like releasing a tension spring. Slightly softer timbre than focus sounds. |
| **Duration** | 0.5s |
| **Trigger** | Break timer begins (after Pomodoro completion) |
| **Emotional purpose** | "Rest now. You need it." Permission to decompress. |
| **Frequency of play** | 4-12 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | E4 → C4 descending, softer timbre (more sine, less harmonic content) |
| **Volume relative to master** | 60% |

#### `tempo_timer_break_complete`

| Property | Value |
|----------|-------|
| **Description** | "Back to work" prompt. Sharper than break_start — a rising double-tap that pulls attention back. More assertive than pomodoro_warning. Like a supervisor tapping their watch. |
| **Duration** | 0.5s |
| **Trigger** | Short break timer (5 min) reaches zero |
| **Emotional purpose** | "Break's over. Back to it." Re-engages focus. |
| **Frequency of play** | 3-10 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | A4 → C5 rising double-tap, 100ms each, 80ms gap, sharper attack than break_start |
| **Volume relative to master** | 80% |

#### `tempo_timer_long_break_complete`

| Property | Value |
|----------|-------|
| **Description** | Similar to break_complete but with three notes instead of two, and a slightly lower starting pitch. Distinguishable by rhythm: three quick ascending notes vs two. Signals the end of a longer rest period. |
| **Duration** | 0.6s |
| **Trigger** | Long break timer (15-30 min) reaches zero |
| **Emotional purpose** | "Long break over. Next round." Resets mental energy for next Pomodoro cycle. |
| **Frequency of play** | 1-3 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 30KB |
| **Priority** | MANDATORY |
| **Pitch** | G4 → A4 → C5 triple-tap, 80ms each, 60ms gaps |
| **Volume relative to master** | 80% |

#### `tempo_timer_deep_work_complete`

| Property | Value |
|----------|-------|
| **Description** | More substantial completion sound for sessions over 50 minutes. A richer version of pomodoro_complete: bell strike followed by a brief harmonic shimmer (like the PR sound but warmer). Acknowledges that this was a bigger effort. |
| **Duration** | 1.0s |
| **Trigger** | Focus session of 50+ minutes completes |
| **Emotional purpose** | "That was a serious session. Respect." Deeper satisfaction than standard Pomodoro complete. |
| **Frequency of play** | 0-4 times per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | G5 bell strike → harmonic sustain with subtle E5 and B5 overtones, 800ms decay |
| **Volume relative to master** | 90% |

#### `tempo_timer_session_milestone`

| Property | Value |
|----------|-------|
| **Description** | Quick upward chime that plays at study milestones (1h, 2h, 3h marks). A brief "ping" with slight shimmer. Acknowledges sustained effort without breaking flow. |
| **Duration** | 0.3s |
| **Trigger** | Cumulative study time crosses an hour boundary |
| **Emotional purpose** | "Another hour logged. Keep going." Subtle positive reinforcement. |
| **Frequency of play** | 1-4 per study day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | Optional |
| **Pitch** | C6 (1047Hz) quick ping with 200ms shimmer decay |
| **Volume relative to master** | 50% |

---

### 2.4 Notification Sounds

These sounds are registered as custom notification sounds with iOS. They play through the system notification audio channel.

**Important:** iOS custom notification sounds must be under 30 seconds and in CAF, AIF, or WAV format. They are placed in the app bundle and referenced by filename in the push notification payload.

#### `tempo_notif_gentle`

| Property | Value |
|----------|-------|
| **Description** | Soft, non-intrusive single tone. Like a polite knock on a door. Warm but brief. Should not make the user jump or feel stressed. |
| **Duration** | 0.5s |
| **Trigger** | Gentle reminders (2 PM tier). "3 tasks left. You've got this." |
| **Emotional purpose** | Gentle nudge. Awareness without pressure. |
| **Notification escalation tier** | Tier 1 (Gentle) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | D4 (294Hz), soft sine tone, 100ms attack, 400ms decay |
| **Volume relative to master** | 50% |

#### `tempo_notif_firm`

| Property | Value |
|----------|-------|
| **Description** | Moderately attention-grabbing double tone. Two identical notes with a pause — like someone tapping their desk twice. Firmer than gentle, not yet alarming. The "I mean it" sound. |
| **Duration** | 0.8s |
| **Trigger** | Firm warnings (5 PM tier). "2 tasks incomplete. Evening approaching." |
| **Emotional purpose** | Increasing urgency. "You should pay attention to this." |
| **Notification escalation tier** | Tier 2 (Firm) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 40KB |
| **Priority** | MANDATORY |
| **Pitch** | E4 (330Hz) double pulse, 150ms each, 120ms gap, slightly harder attack |
| **Volume relative to master** | 70% |

#### `tempo_notif_urgent`

| Property | Value |
|----------|-------|
| **Description** | Sharp, attention-demanding triple pulse at higher pitch. Like a military radio alert. The "drop what you're doing" sound. Rising pitch on each pulse for escalating urgency. |
| **Duration** | 1.0s |
| **Trigger** | Urgent alerts (6:30 PM tier). "Study not done. DO IT NOW." |
| **Emotional purpose** | Urgency. Mild alarm. "This cannot wait." |
| **Notification escalation tier** | Tier 3 (Urgent) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | E5 → F#5 → G#5, 120ms each, 100ms gaps, hard square-wave attack |
| **Volume relative to master** | 90% |

#### `tempo_notif_critical`

| Property | Value |
|----------|-------|
| **Description** | Maximum severity. An alarm-like pattern: four rapid pulses with ascending pitch, followed by a brief silence and one final sharp tone. Industrial klaxon energy compressed into 1.5 seconds. This sound should make the user feel genuine discomfort about ignoring it. |
| **Duration** | 1.5s |
| **Trigger** | Critical/final warnings (7-8 PM tier). "Another day lost. Or do 45 min right now." |
| **Emotional purpose** | Maximum accountability. "This is your last chance today." The drill sergeant at full volume. |
| **Notification escalation tier** | Tier 4 (Critical) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 75KB |
| **Priority** | MANDATORY |
| **Pitch** | A4 → B4 → C#5 → D#5 rapid (80ms each, 50ms gaps) → 200ms silence → E5 (200ms, hard) |
| **Volume relative to master** | 100% |

#### `tempo_notif_positive`

| Property | Value |
|----------|-------|
| **Description** | Warm, confirming tone. A quick rising two-note chime with a brief shimmer. The "good news" notification sound. Distinctly different from the urgency spectrum — user should immediately know this is positive. |
| **Duration** | 0.5s |
| **Trigger** | Positive events: non-negotiable auto-completed, goal reached, leisure unlocked |
| **Emotional purpose** | Reward. "Something good happened." Warm and brief. |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | C5 → E5, 100ms each, gentle sine tone with harmonic warmth |
| **Volume relative to master** | 65% |

#### `tempo_notif_morning`

| Property | Value |
|----------|-------|
| **Description** | The morning briefing tone. Clean, bright, authoritative single tone that rises and sustains briefly before cutting cleanly. Like reveille compressed into one second — the "your day starts now" sound. Not gentle; not aggressive. Commanding. |
| **Duration** | 1.0s |
| **Trigger** | Morning briefing notification (configurable time, default 0700) |
| **Emotional purpose** | "Wake up. Here's your mission for today." Sets the tone for the day. |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | G4 sharp attack → sustain 400ms → quick rise to B4 → 200ms decay |
| **Volume relative to master** | 80% |

#### `tempo_notif_evening_summary`

| Property | Value |
|----------|-------|
| **Description** | End-of-day tone. A brief resolving two-note descending phrase — signals closure and finality. Like a bookend to the morning briefing. |
| **Duration** | 0.6s |
| **Trigger** | Evening summary notification (after all tasks complete or day ends) |
| **Emotional purpose** | "Day's over. Here's how you did." Closure and reflection. |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 30KB |
| **Priority** | Optional |
| **Pitch** | E4 → C4 descending, 150ms each, 100ms gap, warm decay |
| **Volume relative to master** | 60% |

---

### 2.5 Arena Sounds

#### `tempo_arena_xp_earn`

| Property | Value |
|----------|-------|
| **Description** | Coin/point collection sound. A quick, bright, crystalline "ding" — like collecting a gem in a mobile game but less cartoonish. The pitch varies with XP amount: small amounts are lower, large amounts are higher, creating a subtle "more = better" signal. |
| **Duration** | 0.3s |
| **Trigger** | XP is awarded for any action |
| **Emotional purpose** | Instant micro-dopamine. "Points earned." The sound that makes the XP system addictive. |
| **Pitch variants** | Small (1-20 XP): C5. Medium (21-50 XP): E5. Large (51-100 XP): G5. Bonus (100+ XP): C6. |
| **Frequency of play** | 5-20 times per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB per variant (4 variants) |
| **Priority** | MANDATORY |
| **Volume relative to master** | 60% |

#### `tempo_arena_level_up`

| Property | Value |
|----------|-------|
| **Description** | Triumphant, escalating fanfare. This is the BIG sound. Starts with a deep impact (sub-bass punch), then a rapid ascending arpeggio through a full octave (C4-C5), culminating in a sustained chord (C5-E5-G5) with metallic shimmer that decays over 1 second. The sound of genuine achievement. |
| **Duration** | 2.0s |
| **Trigger** | User reaches a new level |
| **Emotional purpose** | "LEVEL UP." Maximum celebration. This should feel like an event. Rare enough (every few days to weeks) that it never loses impact. |
| **Frequency of play** | Once every few days to weeks |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 100KB |
| **Priority** | MANDATORY |
| **Pitch** | Sub impact (60Hz) → C4-D4-E4-G4-A4-C5 arpeggio (50ms each) → C5+E5+G5 chord sustain 1s |
| **Volume relative to master** | 100% |

#### `tempo_arena_achievement_unlock`

| Property | Value |
|----------|-------|
| **Description** | Badge-clink with shimmer. A metallic impact (like a medal hitting a surface) followed by a brief crystalline shimmer. Distinct from level_up — shorter, sharper, more "badge" and less "fanfare." |
| **Duration** | 1.0s |
| **Trigger** | User earns a new achievement/badge |
| **Emotional purpose** | "New badge earned." Collection satisfaction. Makes badge hunting rewarding. |
| **Frequency of play** | 0-3 times per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | Metallic impact (unpitched, ~2kHz) → crystalline shimmer (B5 + F#6 harmonics, 700ms decay) |
| **Volume relative to master** | 85% |

#### `tempo_arena_challenge_start`

| Property | Value |
|----------|-------|
| **Description** | Competitive horn blast. A short, punchy brass-like synth tone — like the starting horn at a race, but synthesized and clean. One sharp blast with quick decay. |
| **Duration** | 0.8s |
| **Trigger** | User joins or starts a new challenge |
| **Emotional purpose** | "Game on." Competitive energy. Primes for rivalry. |
| **Frequency of play** | 0-2 times per week |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 40KB |
| **Priority** | MANDATORY |
| **Pitch** | G4 sawtooth-wave blast, sharp attack, 600ms decay with slight pitch bend down |
| **Volume relative to master** | 90% |

#### `tempo_arena_challenge_win`

| Property | Value |
|----------|-------|
| **Description** | Victory sound. An ascending three-note triumphant phrase (C5-E5-G5, each 200ms) followed by a crowd-like noise swell (filtered white noise with rising pitch envelope, 800ms). The "champion" sound. |
| **Duration** | 2.0s |
| **Trigger** | Challenge ends and user is the winner |
| **Emotional purpose** | "You won." Dominance. Competitive satisfaction. Makes the user want to challenge again. |
| **Frequency of play** | 0-2 times per week |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 100KB |
| **Priority** | MANDATORY |
| **Pitch** | C5 → E5 → G5 (200ms each) → crowd swell (filtered noise, 800Hz → 4kHz sweep, 800ms) |
| **Volume relative to master** | 100% |

#### `tempo_arena_challenge_lose`

| Property | Value |
|----------|-------|
| **Description** | Subdued, respectful "next time" tone. A single low note with a slight downward bend — not punishing, not mocking. Acknowledges the loss without rubbing it in. Like a brief minor chord that resolves quickly. |
| **Duration** | 0.5s |
| **Trigger** | Challenge ends and user did not win |
| **Emotional purpose** | "Not this time." Brief disappointment, motivation to try again. NOT demoralizing. |
| **Frequency of play** | 0-2 times per week |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 25KB |
| **Priority** | MANDATORY |
| **Pitch** | E4 → Eb4 slight bend down, 200ms tone, 300ms muted decay |
| **Volume relative to master** | 50% |

#### `tempo_arena_leaderboard_pass`

| Property | Value |
|----------|-------|
| **Description** | Quick competitive whoosh with an upward pitch. Like overtaking someone on a track — a swift, directional sound. Brief enough to not be distracting but distinct enough to trigger competitive awareness. |
| **Duration** | 0.3s |
| **Trigger** | User's leaderboard rank improves (passes a friend) |
| **Emotional purpose** | "You just passed someone." Competitive rush. |
| **Frequency of play** | 0-5 per day (in-app only, not as notification) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | Optional |
| **Pitch** | Filtered noise sweep 600Hz → 2kHz, 250ms, slight metallic ring |
| **Volume relative to master** | 55% |

#### `tempo_arena_streak_milestone`

| Property | Value |
|----------|-------|
| **Description** | Building crescendo that varies with streak length. A rapid ascending scale where the number of notes matches the milestone tier: 7-day = 3 notes, 14-day = 4 notes, 30-day = 5 notes, 60-day = 6 notes, 100-day = 7 notes + sustained chord. Each longer version builds more momentum. |
| **Duration** | 0.8s (7-day) to 1.5s (100-day) |
| **Trigger** | Streak reaches 7, 14, 30, 60, or 100 days |
| **Emotional purpose** | "Your streak is growing. Protect it." Building investment and loss aversion. |
| **Frequency of play** | Once per milestone (rare) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB per variant (5 variants) |
| **Priority** | MANDATORY |
| **Pitch** | 7-day: C5-E5-G5 (3 notes). 14-day: C5-E5-G5-C6. 30-day: C5-D5-E5-G5-C6. 60-day: C5-D5-E5-G5-A5-C6. 100-day: C5-D5-E5-F#5-G5-A5-C6 + sustained C6 chord. |
| **Volume relative to master** | 90% |

#### `tempo_arena_xp_penalty`

| Property | Value |
|----------|-------|
| **Description** | Brief negative indicator. A short, low buzzy tone — like a wrong-answer buzzer but much quieter and less aggressive. Communicates "something was deducted" without being punishing. |
| **Duration** | 0.3s |
| **Trigger** | XP deducted for missing a target |
| **Emotional purpose** | "You lost points." Brief sting. Motivates correction. |
| **Frequency of play** | 0-3 per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | Optional |
| **Pitch** | Eb3 (156Hz) buzzy square wave, 150ms, quick decay |
| **Volume relative to master** | 45% |

---

### 2.6 System Sounds

#### `tempo_system_unlock_leisure`

| Property | Value |
|----------|-------|
| **Description** | THE reward sound. This is the moment the user has been working toward all day. A satisfying mechanical "vault opening" sequence: heavy latch releasing (metallic clunk) followed by a chain sliding free (bright jingling sweep) followed by a clean resolution chord. Think: unlocking something physical and heavy. The sound of earned freedom. |
| **Duration** | 1.0s |
| **Trigger** | All non-negotiables completed, leisure is unlocked |
| **Emotional purpose** | "ALL CLEAR. You earned this." The single most emotionally significant sound in the app. Should trigger genuine relief and pride. |
| **Frequency of play** | Once per day (on a good day) |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 50KB |
| **Priority** | MANDATORY |
| **Pitch** | Latch: unpitched metallic clunk. Chain: 1kHz → 4kHz noise sweep 200ms. Resolution: C5 + E5 major third, 400ms sustain with warm decay |
| **Volume relative to master** | 100% |

#### `tempo_system_tab_switch`

| Property | Value |
|----------|-------|
| **Description** | Ultra-subtle tactile click. The lightest sound in the entire catalog. Almost imperceptible — exists only to reinforce the haptic feedback. Like a fingertip touching a glass surface. |
| **Duration** | 0.05s |
| **Trigger** | Switching between main tab bar tabs |
| **Emotional purpose** | Navigation confirmation. "You moved." Purely tactile reinforcement. |
| **Frequency of play** | 20-100+ per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 3KB |
| **Priority** | Optional (haptic alone is sufficient) |
| **Pitch** | Unpitched click, 4kHz center, extremely short |
| **Volume relative to master** | 20% |

#### `tempo_system_pull_refresh`

| Property | Value |
|----------|-------|
| **Description** | Subtle stretch-and-release sound. A quiet rising tone during pull, a soft pop on release/trigger. Like stretching a rubber band and letting it snap gently. |
| **Duration** | 0.2s (the release/trigger portion) |
| **Trigger** | Pull-to-refresh gesture completes (threshold crossed) |
| **Emotional purpose** | Physical feedback for a gesture. "Data refreshing." |
| **Frequency of play** | 5-20 per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 10KB |
| **Priority** | Optional |
| **Pitch** | Quick pop: 2kHz impulse, 50ms, with 150ms low-frequency "thud" (80Hz) undertone |
| **Volume relative to master** | 30% |

#### `tempo_system_error`

| Property | Value |
|----------|-------|
| **Description** | Soft negative indicator. A single low, muted tone that descends slightly. Not alarming — just "that didn't work." Like a polite denial. |
| **Duration** | 0.3s |
| **Trigger** | Any error state: network failure, invalid input, action failed |
| **Emotional purpose** | "Something went wrong." Brief, non-stressful acknowledgment. |
| **Frequency of play** | Infrequent |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | MANDATORY |
| **Pitch** | Bb3 (233Hz) → A3 (220Hz) slight descent, muted sine, 200ms tone + 100ms decay |
| **Volume relative to master** | 50% |

#### `tempo_system_success`

| Property | Value |
|----------|-------|
| **Description** | Soft positive indicator. A quick ascending two-note micro-chime. Brighter and quicker than notif_positive. For generic success states. |
| **Duration** | 0.3s |
| **Trigger** | Successful save, sync complete, connection established |
| **Emotional purpose** | "That worked." Quick, positive confirmation. |
| **Frequency of play** | 5-15 per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 15KB |
| **Priority** | MANDATORY |
| **Pitch** | C5 → E5, 80ms each, 60ms gap, clean sine tone |
| **Volume relative to master** | 45% |

#### `tempo_system_toggle`

| Property | Value |
|----------|-------|
| **Description** | Micro-switch sound. Two variants: toggle_on (rising pitch click) and toggle_off (falling pitch click). Like a physical toggle switch. |
| **Duration** | 0.08s |
| **Trigger** | Any toggle/switch interaction |
| **Emotional purpose** | Physical switch feedback. Binary state change confirmation. |
| **Frequency of play** | 2-10 per day |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 4KB per variant |
| **Priority** | Optional |
| **Pitch** | On: 2kHz → 3kHz micro-sweep. Off: 3kHz → 2kHz micro-sweep. |
| **Volume relative to master** | 30% |

#### `tempo_system_delete`

| Property | Value |
|----------|-------|
| **Description** | A quick, soft "thud" — like dropping something into a padded bin. Low, muted, definitive. Signals permanent removal. |
| **Duration** | 0.15s |
| **Trigger** | Deleting an item (swipe to delete, confirming deletion) |
| **Emotional purpose** | "Gone." Finality without drama. |
| **Frequency of play** | Infrequent |
| **Technical specs** | CAF, 48kHz, 16-bit, mono, < 8KB |
| **Priority** | Optional |
| **Pitch** | Low thud, 100Hz center, heavily damped, 100ms |
| **Volume relative to master** | 40% |

---

## 3. Ambient Sound Library

Ambient tracks play during focus timer sessions. They create an auditory environment that promotes sustained concentration.

### 3.1 General Ambient Specifications

| Property | Value |
|----------|-------|
| **Format** | M4A (AAC-LC compressed) |
| **Sample rate** | 44.1kHz |
| **Bit depth** | 16-bit |
| **Channels** | Stereo |
| **Max file size** | 2MB per track |
| **Loop strategy** | Seamless loop with 2s crossfade at loop point |
| **Raw track length** | 5 minutes each (loops seamlessly) |
| **Fade in on start** | 2s linear fade from silence |
| **Fade out on stop** | 2s linear fade to silence |
| **Volume relative to master** | 40% (default, user-adjustable via ambient volume slider: 0-100%) |
| **Mixing with notifications** | Ambient ducks to 50% volume when notification sounds play (300ms duck-in, 200ms release) |
| **Mixing with user music** | Ambient does NOT play if user has music playing. Detected via `AVAudioSession.sharedInstance().isOtherAudioPlaying`. Show "Music detected — ambient sounds disabled" in timer UI. |
| **Background behavior** | Continues playing when app is backgrounded (requires audio background mode) |

### 3.2 Track Catalog

#### 1. Rain (`tempo_ambient_rain`)

| Property | Value |
|----------|-------|
| **Description** | Gentle rain falling on a window. Consistent, moderate intensity. No thunder, no wind gusts, no dripping. Pure, steady rainfall. The most universally liked focus sound. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Broad-spectrum noise with emphasis on 2-8kHz (the "patter" frequencies). Gentle low-end rumble around 100-200Hz. |
| **Dynamics** | Nearly flat. Amplitude variation < 3dB throughout the track. No sudden peaks. |
| **Volume relative to ambient slider** | 100% (reference track) |

#### 2. White Noise (`tempo_ambient_whitenoise`)

| Property | Value |
|----------|-------|
| **Description** | Flat-spectrum white noise. Clinically even across all frequencies. Generated, not recorded. For users who want pure masking without any environmental character. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Flat from 20Hz to 20kHz. |
| **Dynamics** | Perfectly flat. No amplitude variation. |
| **Volume relative to ambient slider** | 90% (white noise is perceptually louder, reduce to compensate) |

#### 3. Brown Noise (`tempo_ambient_brownnoise`)

| Property | Value |
|----------|-------|
| **Description** | Deeper, warmer noise. Heavy low-frequency emphasis with a natural -6dB/octave rolloff. Like standing next to a waterfall. More soothing than white noise for most people. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | -6dB/octave from 20Hz. Dominant energy below 500Hz. Gentle rolloff above 2kHz. |
| **Dynamics** | Flat amplitude. Slight natural drift (< 1dB) acceptable. |
| **Volume relative to ambient slider** | 95% |

#### 4. Lo-fi Beats (`tempo_ambient_lofi`)

| Property | Value |
|----------|-------|
| **Description** | Instrumental lo-fi beat. Mellow keys or guitar over a slow, steady drum pattern. No vocals. No lyrics. Tempo approximately 70 BPM. Vinyl crackle undertone. Jazzy chord progressions that don't demand attention. |
| **Loop point** | 4:48.000 (aligned to 8-bar loop at 70 BPM) → crossfade to 0:00.000 |
| **Frequency spectrum** | Low-pass filtered around 8kHz (that "lo-fi" warmth). Emphasis on 200Hz-2kHz. |
| **Dynamics** | Gentle variation with the beat (< 6dB). Drums are soft, not driving. |
| **Volume relative to ambient slider** | 80% (music is more attention-grabbing, reduce volume) |
| **Licensing note** | Must be original composition or CC0 licensed. No samples requiring attribution in binary. |

#### 5. Library Ambiance (`tempo_ambient_library`)

| Property | Value |
|----------|-------|
| **Description** | The sonic environment of a quiet university library. Distant soft murmur of voices (unintelligible), occasional page turning, very faint keyboard typing, the hum of air conditioning. All extremely subtle. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Low-frequency HVAC hum (60-120Hz), very subtle mid-range murmur (300Hz-1kHz), occasional high-frequency paper rustle (3-6kHz). |
| **Dynamics** | Very low overall. Occasional transients from page turns (< 6dB above baseline) spaced 15-30s apart. |
| **Volume relative to ambient slider** | 85% |

#### 6. Nature (`tempo_ambient_nature`)

| Property | Value |
|----------|-------|
| **Description** | Outdoor nature soundscape. Birdsong (occasional, not constant), gentle wind through leaves, a distant stream or brook. Morning-time energy. Peaceful but alive. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Birdsong: 2-8kHz (intermittent). Wind: 200Hz-2kHz (constant, gentle). Stream: broad-spectrum with emphasis on 1-4kHz (constant). |
| **Dynamics** | Moderate variation (< 8dB) from birdsong appearance/disappearance. Base layer (wind + stream) is constant. |
| **Volume relative to ambient slider** | 90% |

#### 7. Fireplace (`tempo_ambient_fireplace`)

| Property | Value |
|----------|-------|
| **Description** | Crackling fire in a fireplace. Steady low roar with intermittent crackles and pops. Warm, cozy, grounding. No music, no voices. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Low roar: 50-300Hz (constant). Crackles: broadband transients 500Hz-8kHz (intermittent). |
| **Dynamics** | Base roar is steady. Crackle transients (< 10dB above baseline) occur 3-8 times per minute at random intervals. |
| **Volume relative to ambient slider** | 90% |

#### 8. Silence with Ticks (`tempo_ambient_ticks`)

| Property | Value |
|----------|-------|
| **Description** | Near-silence punctuated by a single soft metronome tick every 30 seconds. For users who want minimal sound but a periodic reminder that the timer is running. The tick is identical to `tempo_timer_pomodoro_tick` but spaced at 30s intervals. |
| **Loop point** | 5:00.000 → crossfade to 0:00.000 |
| **Frequency spectrum** | Tick only: centered at 800Hz, unpitched transient. No continuous sound. |
| **Dynamics** | Silence at -infinity dB, tick transient at 40% of ambient volume slider setting. |
| **Volume relative to ambient slider** | 100% |

---

## 4. Complete Haptic Catalog

### 4.1 Haptic Design Principles

1. **Haptics always fire, even in silent mode.** Haptics are the primary feedback channel. Sound is secondary.
2. **Match intensity to importance.** Light taps for navigation, medium for completions, heavy for celebrations.
3. **Never use haptics alone for critical information.** Always pair with visual feedback. Haptics reinforce; they don't replace.
4. **Respect system settings.** Check `CHHapticEngine.capabilitiesForHardware().supportsHaptics` before playing custom patterns.
5. **Pre-warm haptic engines.** Call `prepare()` on generators before they're needed to avoid first-tap latency.

### 4.2 UIKit Feedback Generator Reference

| Generator | Styles | Use Case |
|-----------|--------|----------|
| `UIImpactFeedbackGenerator` | `.light`, `.medium`, `.heavy`, `.rigid`, `.soft` | Physical impacts: taps, collisions, weight |
| `UINotificationFeedbackGenerator` | `.success`, `.warning`, `.error` | Outcomes: completion, warning, failure |
| `UISelectionFeedbackGenerator` | (no style) | Selection changes: pickers, sliders, steppers |

### 4.3 Workout Haptics

#### `haptic_set_complete`

| Property | Value |
|----------|-------|
| **Trigger** | User taps to complete a set |
| **API** | `UINotificationFeedbackGenerator(.success)` |
| **Intensity** | System-defined (success = firm, satisfying double-tap) |
| **Timing** | Fires simultaneously with `tempo_workout_set_complete` sound |
| **Notes** | This is the most-played haptic in the app. UINotificationFeedbackGenerator.success provides the ideal "done" feel without custom complexity. Pre-warm the generator when WorkoutLogView appears. |

#### `haptic_exercise_complete`

| Property | Value |
|----------|-------|
| **Trigger** | All sets for an exercise marked complete |
| **API** | `UIImpactFeedbackGenerator(.medium)` |
| **Intensity** | 0.7 (via `impactOccurred(intensity:)`) |
| **Timing** | 50ms after `haptic_set_complete` fires (so the last set complete haptic plays first, then exercise complete stacks on top) |
| **Notes** | Slightly heavier than a normal set complete — user feels the "level up" in feedback weight. |

#### `haptic_weight_stepper`

| Property | Value |
|----------|-------|
| **Trigger** | Each tap of +/- weight stepper buttons |
| **API** | `UISelectionFeedbackGenerator()` |
| **Intensity** | System-defined (lightest available haptic) |
| **Timing** | Immediate on touch |
| **Notes** | The lightest possible haptic. Makes the stepper feel like a physical detent dial. Call `prepare()` when weight stepper appears, `selectionChanged()` on each step. |

#### `haptic_weight_stepper_long_press`

| Property | Value |
|----------|-------|
| **Trigger** | Long press on +/- weight stepper (continuous weight change) |
| **API** | `UIImpactFeedbackGenerator(.heavy)` at 100ms intervals |
| **Intensity** | 0.4 initially, increasing to 0.8 as speed increases |
| **Timing** | First haptic at 500ms hold, then every 100ms during continuous change |
| **Notes** | Creates a "motor running" feel during rapid weight adjustment. Intensity ramps up as the value changes faster. Implementation: use a Timer that fires every 100ms, increasing intensity by 0.05 each tick (clamped to 0.8). |

#### `haptic_rest_timer_tick`

| Property | Value |
|----------|-------|
| **Trigger** | Each second during final 5 seconds of rest timer |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | Tick 5: 0.3, Tick 4: 0.4, Tick 3: 0.5, Tick 2: 0.6, Tick 1: 0.8 (escalating) |
| **Timing** | Synchronized with `tempo_workout_rest_tick` sound |
| **Notes** | Escalating intensity creates urgency. Each tick hits harder than the last. |

#### `haptic_rest_timer_done`

| Property | Value |
|----------|-------|
| **Trigger** | Rest timer reaches zero |
| **API** | Core Haptics custom pattern (see Section 5) |
| **Pattern** | Three pulses: heavy(0.8) → 120ms pause → heavy(0.9) → 120ms pause → heavy(1.0) |
| **Timing** | Starts simultaneously with `tempo_workout_rest_done` sound |
| **Notes** | The triple-pulse pattern is distinct from any system haptic. User learns to associate this specific rhythm with "time to lift." Fallback for devices without Core Haptics: `UINotificationFeedbackGenerator(.warning)`. |

#### `haptic_pr_achieved`

| Property | Value |
|----------|-------|
| **Trigger** | Personal record detected |
| **API** | Core Haptics custom pattern (see Section 5) |
| **Pattern** | Celebration triple-hit: heavy(1.0) → 100ms → heavy(1.0) → 100ms → heavy(1.0), followed by 200ms pause, then a final sustained buzz (0.6 intensity, 300ms) |
| **Timing** | Starts 50ms before the `tempo_workout_pr_achieved` sound (haptic leads audio slightly for perceived immediacy) |
| **Notes** | The most intense haptic in the workout module. The sustained buzz at the end provides a "glow" feel. Fallback: `UINotificationFeedbackGenerator(.success)` played twice with 200ms gap. |

#### `haptic_workout_complete`

| Property | Value |
|----------|-------|
| **Trigger** | Entire workout marked complete |
| **API** | Core Haptics custom pattern (see Section 5) |
| **Pattern** | Crescendo: 5 impacts over 500ms with intensity 0.3 → 0.5 → 0.7 → 0.9 → 1.0, each 100ms apart. Followed by 200ms sustained buzz at 0.5 intensity. |
| **Timing** | Starts simultaneously with `tempo_workout_complete` sound |
| **Notes** | The building intensity mirrors the accomplishment. Fallback: `UINotificationFeedbackGenerator(.success)`. |

#### `haptic_rep_tap`

| Property | Value |
|----------|-------|
| **Trigger** | Each rep counted (manual or auto) |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.3 |
| **Timing** | Immediate on rep registration |
| **Notes** | Barely perceptible. Just enough to confirm "that counted" without being distracting during high-rep sets. |

#### `haptic_superset_transition`

| Property | Value |
|----------|-------|
| **Trigger** | Transitioning between superset exercises |
| **API** | `UIImpactFeedbackGenerator(.rigid)` |
| **Intensity** | 0.6 |
| **Timing** | Simultaneous with `tempo_workout_superset_transition` sound |
| **Notes** | `.rigid` style gives a sharp, crisp feel distinct from `.medium` — signals a different kind of transition. |

#### `haptic_exercise_swipe`

| Property | Value |
|----------|-------|
| **Trigger** | Swiping between exercises |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.4 |
| **Timing** | Fires when swipe gesture crosses the exercise boundary threshold |
| **Notes** | Light physical feedback for spatial navigation. |

---

### 4.4 Timer Haptics

#### `haptic_pomodoro_start`

| Property | Value |
|----------|-------|
| **Trigger** | User starts a Pomodoro session |
| **API** | `UIImpactFeedbackGenerator(.medium)` |
| **Intensity** | 0.7 |
| **Timing** | Simultaneous with `tempo_timer_pomodoro_start` sound |

#### `haptic_pomodoro_complete`

| Property | Value |
|----------|-------|
| **Trigger** | Pomodoro timer reaches zero |
| **API** | `UINotificationFeedbackGenerator(.success)` |
| **Intensity** | System-defined |
| **Timing** | Simultaneous with `tempo_timer_pomodoro_complete` sound |

#### `haptic_pomodoro_warning`

| Property | Value |
|----------|-------|
| **Trigger** | 2 minutes remaining in Pomodoro |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.5 |
| **Timing** | Simultaneous with `tempo_timer_pomodoro_warning` sound |

#### `haptic_break_complete`

| Property | Value |
|----------|-------|
| **Trigger** | Break timer reaches zero |
| **API** | `UINotificationFeedbackGenerator(.warning)` |
| **Intensity** | System-defined |
| **Timing** | Simultaneous with `tempo_timer_break_complete` sound |
| **Notes** | `.warning` style is more assertive than `.success` — appropriate for "get back to work." |

#### `haptic_deep_work_complete`

| Property | Value |
|----------|-------|
| **Trigger** | Deep work session (50+ min) completes |
| **API** | Core Haptics: two heavy impacts with 150ms gap, followed by sustained buzz (200ms, 0.4 intensity) |
| **Timing** | Simultaneous with `tempo_timer_deep_work_complete` sound |

#### `haptic_session_tick`

| Property | Value |
|----------|-------|
| **Trigger** | Optional per-minute tick during focus session |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.2 (barely perceptible) |
| **Timing** | Simultaneous with `tempo_timer_pomodoro_tick` sound |
| **Notes** | Off by default. Enabled alongside the audio tick in settings. |

---

### 4.5 Navigation Haptics

#### `haptic_tab_switch`

| Property | Value |
|----------|-------|
| **Trigger** | Switching between main tab bar tabs |
| **API** | `UISelectionFeedbackGenerator()` |
| **Intensity** | System-defined |
| **Timing** | Immediate on tab selection |

#### `haptic_button_press`

| Property | Value |
|----------|-------|
| **Trigger** | Tapping any primary or secondary action button |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.5 |
| **Timing** | Immediate on touch-down |
| **Notes** | Only for significant action buttons (Start Workout, Save, Submit). Not for every tappable element. |

#### `haptic_long_press_activate`

| Property | Value |
|----------|-------|
| **Trigger** | Long press recognized (context menu, destructive action confirmation) |
| **API** | `UIImpactFeedbackGenerator(.medium)` |
| **Intensity** | 0.8 |
| **Timing** | Fires at the moment long press is recognized (after threshold, typically 500ms) |

#### `haptic_swipe_action`

| Property | Value |
|----------|-------|
| **Trigger** | Swipe gesture activates an action (swipe to delete, swipe to complete) |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | 0.4 |
| **Timing** | Fires when swipe crosses the action threshold |

#### `haptic_pull_refresh_trigger`

| Property | Value |
|----------|-------|
| **Trigger** | Pull-to-refresh crosses the trigger threshold |
| **API** | `UIImpactFeedbackGenerator(.medium)` |
| **Intensity** | 0.6 |
| **Timing** | Fires at the moment the threshold is crossed (before release) |

#### `haptic_scroll_boundary`

| Property | Value |
|----------|-------|
| **Trigger** | Scroll reaches the top or bottom boundary (rubber-band) |
| **API** | `UIImpactFeedbackGenerator(.soft)` |
| **Intensity** | 0.3 |
| **Timing** | Fires once when boundary is hit |
| **Notes** | Very subtle. Provides a physical "wall" sensation. Only fires once per boundary hit (not continuously during overscroll). |

---

### 4.6 Arena Haptics

#### `haptic_xp_earn`

| Property | Value |
|----------|-------|
| **Trigger** | XP awarded |
| **API** | `UIImpactFeedbackGenerator(.light)` |
| **Intensity** | Varies: small XP = 0.3, medium = 0.5, large = 0.7, bonus = 0.9 |
| **Timing** | Simultaneous with `tempo_arena_xp_earn` sound |

#### `haptic_level_up`

| Property | Value |
|----------|-------|
| **Trigger** | User reaches a new level |
| **API** | Core Haptics custom pattern (see Section 5) |
| **Pattern** | Building intensity over 1 second: 6 impacts at 0.3 → 0.4 → 0.5 → 0.7 → 0.9 → 1.0, spaced 150ms apart. Final impact followed by 300ms sustained buzz at 0.6 intensity. |
| **Timing** | Starts simultaneously with `tempo_arena_level_up` sound |

#### `haptic_achievement_unlock`

| Property | Value |
|----------|-------|
| **Trigger** | New achievement/badge earned |
| **API** | Core Haptics: sharp transient (1.0 intensity, 1.0 sharpness) followed by 200ms pause, then soft sustained buzz (0.3 intensity, 500ms) |
| **Timing** | Simultaneous with `tempo_arena_achievement_unlock` sound |
| **Notes** | The "pop then glow" pattern. Sharp impact for the badge appearing, gentle buzz for the shimmer animation. |

#### `haptic_challenge_win`

| Property | Value |
|----------|-------|
| **Trigger** | User wins a challenge |
| **API** | Core Haptics: 3 escalating impacts (0.5 → 0.8 → 1.0) at 200ms intervals, then 400ms sustained buzz at 0.5 intensity |
| **Timing** | Simultaneous with `tempo_arena_challenge_win` sound |

#### `haptic_challenge_lose`

| Property | Value |
|----------|-------|
| **Trigger** | User loses a challenge |
| **API** | `UINotificationFeedbackGenerator(.error)` |
| **Intensity** | System-defined (subtle negative feedback) |
| **Timing** | Simultaneous with `tempo_arena_challenge_lose` sound |

#### `haptic_leaderboard_pass`

| Property | Value |
|----------|-------|
| **Trigger** | User's rank improves on leaderboard |
| **API** | `UIImpactFeedbackGenerator(.medium)` |
| **Intensity** | 0.6 |
| **Timing** | Simultaneous with `tempo_arena_leaderboard_pass` sound |

#### `haptic_streak_milestone`

| Property | Value |
|----------|-------|
| **Trigger** | Streak reaches a milestone (7/14/30/60/100 days) |
| **API** | Core Haptics: number of impacts matches milestone tier (3 for 7-day, 4 for 14-day, etc.), each at 0.8 intensity, 120ms apart, followed by 200ms sustained buzz |
| **Timing** | Simultaneous with `tempo_arena_streak_milestone` sound |

---

### 4.7 Notification Haptics

#### `haptic_notif_gentle`

| Property | Value |
|----------|-------|
| **Trigger** | Tier 1 gentle notification |
| **API** | None (relies on standard system notification haptic) |
| **Notes** | Let iOS handle this. No custom haptic needed for gentle notifications. |

#### `haptic_notif_firm`

| Property | Value |
|----------|-------|
| **Trigger** | Tier 2 firm notification |
| **API** | `UINotificationFeedbackGenerator(.warning)` |
| **Notes** | Fires when user opens the notification or when the notification banner appears while app is foregrounded. |

#### `haptic_notif_urgent`

| Property | Value |
|----------|-------|
| **Trigger** | Tier 3 urgent notification |
| **API** | Core Haptics: double-pulse — heavy(0.9) → 80ms pause → heavy(1.0) |
| **Notes** | Custom double-pulse is distinct from any system haptic. User learns "two quick hits = urgent." |

#### `haptic_notif_critical`

| Property | Value |
|----------|-------|
| **Trigger** | Tier 4 critical notification |
| **API** | Core Haptics: triple-pulse with increasing intensity — medium(0.5) → 80ms → heavy(0.8) → 80ms → heavy(1.0) |
| **Notes** | Three hits with escalating force. Physically impossible to ignore. |

#### `haptic_unlock_leisure`

| Property | Value |
|----------|-------|
| **Trigger** | All non-negotiables complete, leisure unlocked |
| **API** | Core Haptics custom pattern (see Section 5) |
| **Pattern** | "Tension and release": sustained buzz building from 0.2 to 0.8 over 300ms (tension), then sharp release — single heavy impact (1.0) followed by soft decaying buzz (0.6 → 0.0 over 400ms) |
| **Timing** | Starts simultaneously with `tempo_system_unlock_leisure` sound |
| **Notes** | The haptic tells a story: building pressure (the daily grind) → release (freedom earned). The most emotionally designed haptic in the app. |

---

## 5. Core Haptics Patterns (AHAP Files)

### 5.1 AHAP File Format

AHAP (Apple Haptic Audio Pattern) files are JSON-based patterns that define precisely timed haptic and audio events. They are loaded via `CHHapticEngine` and offer far more control than UIKit feedback generators.

**Placement:** `Tempo/Resources/Haptics/`
**Naming:** `tempo_haptic_[name].ahap`

### 5.2 PR Celebration (`tempo_haptic_pr_celebration.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Personal record celebration — triple hit followed by sustained glow"
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.8 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.1,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.9 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.2,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 1.0 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.4,
        "EventType": "HapticContinuous",
        "EventDuration": 0.3,
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.6 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.3 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticIntensityControl",
        "Time": 0.4,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.6 },
          { "Time": 0.3, "ParameterValue": 0.0 }
        ]
      }
    }
  ]
}
```

### 5.3 Level Up (`tempo_haptic_level_up.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Level up — building intensity crescendo over 1 second with sustained buzz finale"
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.3 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.4 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.15,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.4 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.5 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.3,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.55 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.6 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.45,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.7 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.7 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.6,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.85 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.8 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.75,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 1.0 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.95,
        "EventType": "HapticContinuous",
        "EventDuration": 0.4,
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.6 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.2 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticIntensityControl",
        "Time": 0.95,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.6 },
          { "Time": 0.4, "ParameterValue": 0.0 }
        ]
      }
    }
  ]
}
```

### 5.4 Unlock Leisure (`tempo_haptic_unlock_leisure.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Leisure unlock — tension buildup followed by satisfying release. The reward haptic."
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticContinuous",
        "EventDuration": 0.35,
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.2 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.1 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticIntensityControl",
        "Time": 0.0,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.2 },
          { "Time": 0.15, "ParameterValue": 0.5 },
          { "Time": 0.35, "ParameterValue": 0.85 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticSharpnessControl",
        "Time": 0.0,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.1 },
          { "Time": 0.35, "ParameterValue": 0.6 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.4,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 1.0 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.5,
        "EventType": "HapticContinuous",
        "EventDuration": 0.45,
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.2 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticIntensityControl",
        "Time": 0.5,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.5 },
          { "Time": 0.2, "ParameterValue": 0.3 },
          { "Time": 0.45, "ParameterValue": 0.0 }
        ]
      }
    }
  ]
}
```

### 5.5 Workout Complete (`tempo_haptic_workout_complete.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Workout complete — 5-hit crescendo followed by sustained victory buzz"
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.3 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.5 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.1,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.6 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.2,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.7 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.7 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.3,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.9 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.85 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.4,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 1.0 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.6,
        "EventType": "HapticContinuous",
        "EventDuration": 0.3,
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.2 }
        ]
      }
    },
    {
      "ParameterCurve": {
        "ParameterID": "HapticIntensityControl",
        "Time": 0.6,
        "ParameterCurveControlPoints": [
          { "Time": 0.0, "ParameterValue": 0.5 },
          { "Time": 0.3, "ParameterValue": 0.0 }
        ]
      }
    }
  ]
}
```

### 5.6 Critical Notification (`tempo_haptic_critical_notification.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Critical notification — triple pulse with escalating intensity. Maximum urgency."
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.7 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.12,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.8 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.85 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.24,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 1.0 }
        ]
      }
    }
  ]
}
```

### 5.7 Rest Timer Done (`tempo_haptic_rest_timer_done.ahap`)

```json
{
  "Version": 1.0,
  "Metadata": {
    "Project": "Tempo",
    "Created": "2026-03-24",
    "Description": "Rest timer done — three evenly-spaced heavy hits. Time to lift."
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.8 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.7 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.12,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.9 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.8 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.24,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.9 }
        ]
      }
    }
  ]
}
```

---

## 6. Audio-Haptic Synchronization

### 6.1 Synchronization Principles

Audio and haptics must feel like a single event. The human body perceives haptic feedback ~10-20ms faster than audio (due to nerve conduction speed vs sound processing). For perfect synchronization:

1. **Fire haptic and sound at the same dispatch time.** Do NOT intentionally offset. The iOS audio pipeline adds ~10-15ms of inherent latency that naturally compensates for the perceptual difference.
2. **Use `DispatchQueue.main.async` for both.** Never fire haptic on one queue and sound on another.
3. **Pre-warm both systems.** Call `prepare()` on haptic generators and pre-load audio buffers before the moment they're needed.

### 6.2 Synchronization Timing Table

| Event | Visual (t=0) | Haptic Offset | Audio Offset | Notes |
|-------|-------------|---------------|-------------|-------|
| Set complete | Checkmark animates | t+0ms | t+0ms | Haptic and audio fire at animation start |
| Exercise complete | Card collapses | t+0ms | t+0ms | Fire at animation trigger |
| Workout complete | Summary screen transition starts | t+0ms | t+0ms | Fire when transition begins |
| PR achieved | PR badge appears | t-50ms (haptic leads) | t+0ms | Haptic fires 50ms BEFORE visual/audio for "impact" feel |
| Rest timer done | Timer text flashes red | t+0ms | t+0ms | Simultaneous |
| XP earned | XP float animation starts | t+0ms | t+0ms | Fire at animation spawn |
| Level up | Level-up modal appears | t+0ms | t+0ms | Fire at modal presentation |
| Unlock leisure | Lock icon animates open | t+0ms | t+0ms | Fire at animation start |
| Weight stepper | Number value changes | t+0ms | t+0ms | Immediate on value change |

### 6.3 Silent Mode Behavior

| System State | Sound | Haptic | Visual |
|-------------|-------|--------|--------|
| Ring mode ON | Plays | Plays | Plays |
| Silent mode ON (mute switch) | Muted | Plays | Plays |
| Silent mode + "Reduce Motion" ON | Muted | Simplified (see 6.4) | Simplified animations |
| Do Not Disturb (app foregrounded) | Plays (in-app sounds) | Plays | Plays |
| Do Not Disturb (app backgrounded) | Muted (notifications) | System default | Notification banner |

**Implementation:**
```swift
// Check ring/silent mode
let isSilentMode = !AVAudioSession.sharedInstance().isOtherAudioPlaying
// Better approach: check the ringer state
// Use AudioServicesAddSystemSoundCompletion or simply attempt playback
// with .ambient category — it will naturally be silent in mute mode.

// For in-app sounds, use AVAudioSession .ambient category.
// This automatically respects the mute switch.
// For notification sounds, iOS handles mute switch behavior.
```

### 6.4 Accessibility: Reduce Motion

When the user has "Reduce Motion" enabled (`UIAccessibility.isReduceMotionEnabled`):

| Original Haptic | Reduced Haptic |
|----------------|----------------|
| Core Haptics crescendo (workout complete) | Single `UINotificationFeedbackGenerator(.success)` |
| Core Haptics triple-hit (PR celebration) | Single `UIImpactFeedbackGenerator(.heavy)` |
| Core Haptics tension-release (unlock leisure) | `UINotificationFeedbackGenerator(.success)` |
| Core Haptics level up sequence | Single `UINotificationFeedbackGenerator(.success)` |
| Core Haptics critical notification | `UINotificationFeedbackGenerator(.warning)` |
| Escalating rest timer ticks | Flat intensity (all 0.5) |
| Weight stepper long press rapid fire | Single haptic at start, single at end |

**Rule:** Replace all multi-event Core Haptics patterns with a single UIKit feedback generator call. No sequential patterns, no crescendos, no sustained buzzes.

### 6.5 Latency Budget

| Component | Target Latency | Notes |
|-----------|---------------|-------|
| Touch event to haptic fire | < 10ms | Pre-warm generators; call `prepare()` in `viewDidAppear` |
| Touch event to audio fire | < 25ms | Pre-load audio with `AVAudioPlayer.prepareToPlay()` or use `AudioServicesPlaySystemSound` for < 30s sounds |
| Haptic-to-audio perceived sync | < 5ms perceived gap | Handled by firing both at same dispatch time |
| Visual-to-haptic sync | < 1 frame (16ms at 60fps, 8ms at 120fps) | Fire haptic in the same frame as the visual update |

### 6.6 Audio Engine Architecture

```
TempoAudioEngine (singleton)
├── SoundPlayer
│   ├── Pre-loaded sound pool (all mandatory sounds loaded at launch)
│   ├── On-demand loading for optional sounds
│   ├── AVAudioPlayer instances for each sound (reusable)
│   └── Volume scaling (applies per-sound volume × category volume × master volume)
├── AmbientPlayer
│   ├── AVAudioPlayer with numberOfLoops = -1 (infinite)
│   ├── Crossfade manager for seamless looping
│   ├── Duck manager (ducks for notifications, unducks after)
│   └── Independent volume control
├── HapticEngine
│   ├── CHHapticEngine instance (lazy-initialized)
│   ├── Pre-loaded AHAP patterns
│   ├── UIKit generator pool (pre-warmed)
│   └── Accessibility fallback logic
└── SyncCoordinator
    ├── Pairs sound + haptic calls for synchronized dispatch
    ├── Respects user settings (sound on/off per category)
    └── Handles silent mode gracefully
```

---

## 7. Sound Settings

### 7.1 Settings Structure

Located in: **Settings tab > Sound & Haptics**

```
Sound & Haptics
├── Master Sound Toggle ──────── [ON/OFF]
│   └── (when OFF, all sounds are disabled. Haptics unaffected.)
├── Master Haptic Toggle ─────── [ON/OFF]
│   └── (when OFF, all custom haptics disabled. System haptics unaffected.)
├── ─────────────────────────────
├── Sound Categories
│   ├── Workout Sounds ────────── [ON/OFF]  (default: ON)
│   ├── Timer Sounds ──────────── [ON/OFF]  (default: ON)
│   ├── Notification Sounds ───── [ON/OFF]  (default: ON)
│   ├── Arena Sounds ──────────── [ON/OFF]  (default: ON)
│   └── Navigation Sounds ────── [ON/OFF]  (default: OFF)
├── ─────────────────────────────
├── Volume
│   └── "Tempo uses your system volume. Adjust with your
│        device volume buttons."
│   └── [No custom volume slider — respects system volume only]
├── ─────────────────────────────
├── Focus Timer
│   ├── Ambient Sound ─────────── [Picker: None / Rain / White Noise /
│   │                               Brown Noise / Lo-fi / Library /
│   │                               Nature / Fireplace / Ticks]
│   ├── Ambient Volume ────────── [Slider: 0-100%]  (default: 40%)
│   ├── Minute Tick ───────────── [ON/OFF]  (default: OFF)
│   └── Rep Count Sound ───────── [ON/OFF]  (default: OFF)
├── ─────────────────────────────
├── Notifications
│   └── "Manage notification sounds in Settings > Notifications"
│   └── [Link to iOS Settings > Tempo > Notifications]
└── ─────────────────────────────
    └── Preview Sounds ────────── [Button: "Play Sample"]
        └── Plays: set_complete → exercise_complete →
            workout_complete in sequence with 500ms gaps
```

### 7.2 Persistence

All sound settings are stored in `UserDefaults` (via SwiftData `UserSettings` model):

```swift
// UserSettings properties
var masterSoundEnabled: Bool = true
var masterHapticEnabled: Bool = true
var workoutSoundsEnabled: Bool = true
var timerSoundsEnabled: Bool = true
var notificationSoundsEnabled: Bool = true
var arenaSoundsEnabled: Bool = true
var navigationSoundsEnabled: Bool = false
var ambientSound: AmbientTrack = .none
var ambientVolume: Double = 0.4  // 0.0 to 1.0
var minuteTickEnabled: Bool = false
var repCountSoundEnabled: Bool = false
```

### 7.3 Custom Notification Sound Registration

iOS allows custom notification sounds bundled with the app. To use Tempo's notification sounds:

1. Place all `tempo_notif_*.caf` files in the app bundle's root (or a `Sounds/` subdirectory)
2. Reference by filename in the push notification payload:

```json
{
  "aps": {
    "alert": {
      "title": "Lockdown",
      "body": "2 tasks incomplete. Evening approaching."
    },
    "sound": "tempo_notif_firm.caf"
  }
}
```

3. For Tier 4 (Final Warning), use Time Sensitive notification:

> **REMEDIATED (Technical Feasibility Audit Section 3.2):** Critical Alerts entitlement will NOT be approved for a productivity app. Tempo uses `.timeSensitive` interruption level instead.

```json
{
  "aps": {
    "alert": { "title": "Tempo", "body": "Another day lost." },
    "sound": "tempo_notif_critical.caf",
    "interruption-level": "time-sensitive"
  }
}
```

**Time Sensitive Notification Behavior:**
- Breaks through Scheduled Summary
- Appears immediately on the lock screen
- Stays visible for 1 hour
- Respects Silent Mode and DND (unlike Critical Alerts)
- For maximum accountability: instruct users to enable "Always Deliver" for Tempo in iOS Settings > Notifications, which bypasses Focus modes entirely (user-controlled, no entitlement needed).

### 7.4 Background Audio Mixing

| Scenario | Behavior |
|----------|----------|
| User playing Apple Music + Tempo in foreground | Tempo UI sounds play as `.ambient` overlay. Music unaffected. |
| User playing Apple Music + Focus timer ambient | Ambient does not play. Show "Music detected" indicator. |
| User playing Apple Music + Timer completes | Timer completion sound briefly ducks music (`.duckOthers` for 2s), then releases. |
| User playing Spotify + any Tempo sound | Same behavior as Apple Music (AVAudioSession handles all apps). |
| No music playing + Focus timer ambient | Ambient plays through `.playback` category for background support. |
| Phone call active | All Tempo audio silenced. Haptics continue. |

**Implementation pattern:**
```swift
func playSound(_ sound: TempoSound, category: SoundCategory) {
    guard settings.masterSoundEnabled else { return }
    guard settings.isCategoryEnabled(category) else { return }

    if sound.isPriority {
        // Timer completions, notifications — need to be heard over music
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            options: [.duckOthers]
        )
        // Play sound, then after completion:
        DispatchQueue.main.asyncAfter(deadline: .now() + sound.duration + 0.5) {
            try? AVAudioSession.sharedInstance().setCategory(
                .ambient,
                options: [.mixWithOthers]
            )
        }
    } else {
        // Normal UI sounds — mix with everything
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            options: [.mixWithOthers]
        )
    }

    soundPlayer.play(sound)
}
```

---

## 8. Audio File Specifications

### 8.1 Format Requirements

| Property | UI Sounds | Notification Sounds | Ambient Tracks |
|----------|-----------|-------------------|----------------|
| **Format** | CAF (Core Audio Format) | CAF (required by iOS) | M4A (AAC-LC) |
| **Sample rate** | 48kHz | 48kHz | 44.1kHz |
| **Bit depth** | 16-bit | 16-bit | 16-bit |
| **Channels** | Mono | Mono | Stereo |
| **Max duration** | 2.0s | 30s (iOS limit) | 5 min (loops) |
| **Compression** | None (linear PCM in CAF) | None (linear PCM in CAF) | AAC-LC 128kbps |

### 8.2 Naming Convention

```
tempo_[module]_[action].caf

Examples:
tempo_workout_set_complete.caf
tempo_workout_pr_achieved.caf
tempo_timer_pomodoro_complete.caf
tempo_notif_urgent.caf
tempo_arena_level_up.caf
tempo_system_unlock_leisure.caf
tempo_ambient_rain.m4a
tempo_ambient_brownnoise.m4a
```

### 8.3 File Size Budget

| Category | Count | Avg Size | Subtotal |
|----------|-------|----------|----------|
| Workout sounds | 12 files | 25KB | 300KB |
| Timer sounds | 9 files | 30KB | 270KB |
| Notification sounds | 7 files | 40KB | 280KB |
| Arena sounds (incl. variants) | 14 files | 40KB | 560KB |
| System sounds | 7 files | 15KB | 105KB |
| **UI sound total** | **49 files** | — | **~1.5MB** |
| Ambient tracks | 8 files | 1.8MB | 14.4MB |
| AHAP haptic patterns | 6 files | 2KB | 12KB |
| **Grand total** | **63 files** | — | **~16MB** |

**Notes:**
- UI sound budget target: under 2MB. Current estimate: 1.5MB. Comfortable margin.
- Ambient tracks are the bulk of audio assets. Consider hosting 4 ambient tracks on-device (Rain, White Noise, Brown Noise, Ticks) and downloading the others on first request. This reduces initial bundle by ~7MB.
- All ambient tracks except Ticks can be procedurally generated at runtime using `AVAudioEngine` + `AVAudioSourceNode` if bundle size is critical. White noise and brown noise are trivial to generate. Rain and fireplace require recorded samples.

### 8.4 File Organization in Xcode Project

```
Tempo/
└── Resources/
    ├── Sounds/
    │   ├── Workout/
    │   │   ├── tempo_workout_set_complete.caf
    │   │   ├── tempo_workout_exercise_complete.caf
    │   │   ├── tempo_workout_start.caf
    │   │   ├── tempo_workout_complete.caf
    │   │   ├── tempo_workout_rest_tick.caf
    │   │   ├── tempo_workout_rest_done.caf
    │   │   ├── tempo_workout_pr_achieved.caf
    │   │   ├── tempo_workout_weight_adjust.caf
    │   │   ├── tempo_workout_exercise_swipe.caf
    │   │   ├── tempo_workout_rep_count.caf
    │   │   ├── tempo_workout_superset_transition.caf
    │   │   └── tempo_workout_warmup_complete.caf
    │   ├── Timer/
    │   │   ├── tempo_timer_pomodoro_start.caf
    │   │   ├── tempo_timer_pomodoro_tick.caf
    │   │   ├── tempo_timer_pomodoro_warning.caf
    │   │   ├── tempo_timer_pomodoro_complete.caf
    │   │   ├── tempo_timer_break_start.caf
    │   │   ├── tempo_timer_break_complete.caf
    │   │   ├── tempo_timer_long_break_complete.caf
    │   │   ├── tempo_timer_deep_work_complete.caf
    │   │   └── tempo_timer_session_milestone.caf
    │   ├── Notifications/
    │   │   ├── tempo_notif_gentle.caf
    │   │   ├── tempo_notif_firm.caf
    │   │   ├── tempo_notif_urgent.caf
    │   │   ├── tempo_notif_critical.caf
    │   │   ├── tempo_notif_positive.caf
    │   │   ├── tempo_notif_morning.caf
    │   │   └── tempo_notif_evening_summary.caf
    │   ├── Arena/
    │   │   ├── tempo_arena_xp_earn_small.caf
    │   │   ├── tempo_arena_xp_earn_medium.caf
    │   │   ├── tempo_arena_xp_earn_large.caf
    │   │   ├── tempo_arena_xp_earn_bonus.caf
    │   │   ├── tempo_arena_level_up.caf
    │   │   ├── tempo_arena_achievement_unlock.caf
    │   │   ├── tempo_arena_challenge_start.caf
    │   │   ├── tempo_arena_challenge_win.caf
    │   │   ├── tempo_arena_challenge_lose.caf
    │   │   ├── tempo_arena_leaderboard_pass.caf
    │   │   ├── tempo_arena_streak_7.caf
    │   │   ├── tempo_arena_streak_14.caf
    │   │   ├── tempo_arena_streak_30.caf
    │   │   ├── tempo_arena_streak_60.caf
    │   │   ├── tempo_arena_streak_100.caf
    │   │   └── tempo_arena_xp_penalty.caf
    │   └── System/
    │       ├── tempo_system_unlock_leisure.caf
    │       ├── tempo_system_tab_switch.caf
    │       ├── tempo_system_pull_refresh.caf
    │       ├── tempo_system_error.caf
    │       ├── tempo_system_success.caf
    │       ├── tempo_system_toggle_on.caf
    │       ├── tempo_system_toggle_off.caf
    │       └── tempo_system_delete.caf
    ├── Ambient/
    │   ├── tempo_ambient_rain.m4a
    │   ├── tempo_ambient_whitenoise.m4a
    │   ├── tempo_ambient_brownnoise.m4a
    │   ├── tempo_ambient_lofi.m4a
    │   ├── tempo_ambient_library.m4a
    │   ├── tempo_ambient_nature.m4a
    │   ├── tempo_ambient_fireplace.m4a
    │   └── tempo_ambient_ticks.m4a
    └── Haptics/
        ├── tempo_haptic_pr_celebration.ahap
        ├── tempo_haptic_level_up.ahap
        ├── tempo_haptic_unlock_leisure.ahap
        ├── tempo_haptic_workout_complete.ahap
        ├── tempo_haptic_critical_notification.ahap
        └── tempo_haptic_rest_timer_done.ahap
```

### 8.5 Sound Production Pipeline

For creating the actual audio files:

1. **Synthesis:** Use a DAW (Logic Pro, Ableton) or programmatic synthesis (AudioKit, SuperCollider) to generate sounds matching the descriptions in Section 2.
2. **Processing chain:** Generate tone at target pitch > shape envelope (attack/sustain/decay per spec) > apply any filtering > normalize to -3dBFS peak > export as 48kHz/16-bit WAV.
3. **Format conversion:** Convert WAV to CAF using `afconvert`:
   ```
   afconvert input.wav output.caf -d LEI16 -f caff --soundcheck-generate
   ```
4. **Verification:** Play each sound on-device (not simulator) to verify haptic-audio sync and perceptual quality.
5. **A/B testing:** For the 5 most important sounds (set_complete, unlock_leisure, pr_achieved, level_up, pomodoro_complete), create 3 variants each and A/B test with real users during beta.

### 8.6 Runtime Sound Generation (Alternative)

For sounds that are simple enough to synthesize at runtime (reducing bundle size):

```swift
// Example: Generate weight_adjust click at runtime
func generateClick(frequency: Float = 3000, duration: Float = 0.05) -> AVAudioPCMBuffer {
    let sampleRate: Double = 48000
    let frameCount = AVAudioFrameCount(duration * Float(sampleRate))
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        let t = Float(i) / Float(sampleRate)
        let envelope = max(0, 1.0 - (t / duration)) // linear decay
        data[i] = sin(2.0 * .pi * frequency * t) * envelope * 0.5
    }
    return buffer
}
```

**Candidates for runtime generation:**
- `tempo_workout_weight_adjust` (simple click)
- `tempo_system_tab_switch` (simple click)
- `tempo_workout_rest_tick` (simple transient)
- `tempo_timer_pomodoro_tick` (simple transient)
- `tempo_ambient_whitenoise` (procedural noise)
- `tempo_ambient_brownnoise` (filtered procedural noise)

This would save approximately 200KB of bundle size for UI sounds and ~3.6MB for the two noise ambient tracks.

---

## Appendix A: Sound-to-Screen Mapping

Quick reference: which sounds play on which screens.

| Screen | Sounds Used |
|--------|-------------|
| `DashboardView` | `tab_switch`, `pull_refresh`, `xp_earn` |
| `WorkoutLogView` | `set_complete`, `exercise_complete`, `workout_start`, `workout_complete`, `rest_tick`, `rest_done`, `pr_achieved`, `weight_adjust`, `exercise_swipe`, `rep_count`, `superset_transition`, `warmup_complete` |
| `FocusTimerView` | `pomodoro_start`, `pomodoro_tick`, `pomodoro_warning`, `pomodoro_complete`, `break_start`, `break_complete`, `long_break_complete`, `deep_work_complete`, `session_milestone`, ambient tracks |
| `LockdownView` | `success` (task complete), `unlock_leisure` |
| `ArenaView` | `xp_earn`, `level_up`, `achievement_unlock`, `leaderboard_pass` |
| `ChallengesView` | `challenge_start`, `challenge_win`, `challenge_lose` |
| `AchievementsView` | `achievement_unlock` |
| `StreakCalendarView` | `streak_milestone` |
| Push Notifications | `notif_gentle`, `notif_firm`, `notif_urgent`, `notif_critical`, `notif_positive`, `notif_morning`, `notif_evening_summary` |
| All screens (navigation) | `tab_switch`, `button_press`, `toggle`, `error`, `success`, `delete` |

## Appendix B: Haptic Generator Pre-warming Schedule

To minimize first-use latency, pre-warm generators when their parent view appears:

| View | Generators to Pre-warm |
|------|----------------------|
| `WorkoutLogView.onAppear` | `UINotificationFeedbackGenerator` (success), `UISelectionFeedbackGenerator`, `UIImpactFeedbackGenerator` (light, medium, heavy), `CHHapticEngine` |
| `FocusTimerView.onAppear` | `UIImpactFeedbackGenerator` (light, medium), `UINotificationFeedbackGenerator` (success, warning) |
| `ArenaView.onAppear` | `UIImpactFeedbackGenerator` (light, medium), `CHHapticEngine` |
| `LockdownView.onAppear` | `UINotificationFeedbackGenerator` (success), `CHHapticEngine` |
| `MainTabView.onAppear` | `UISelectionFeedbackGenerator` |

**Implementation:**
```swift
// In any view that needs haptics
@State private var impactGenerator = UIImpactFeedbackGenerator(style: .medium)

var body: some View {
    ContentView()
        .onAppear {
            impactGenerator.prepare()
        }
}
```

## Appendix C: Mandatory vs Optional Sound Summary

**MANDATORY (ship without these = broken experience):** 31 sounds
- Workout: set_complete, exercise_complete, workout_start, workout_complete, rest_tick, rest_done, pr_achieved
- Timer: pomodoro_start, pomodoro_warning, pomodoro_complete, break_start, break_complete, long_break_complete, deep_work_complete
- Notifications: gentle, firm, urgent, critical, positive, morning
- Arena: xp_earn (4 variants), level_up, achievement_unlock, challenge_start, challenge_win, challenge_lose, streak_milestone
- System: unlock_leisure, error, success

**OPTIONAL (enhance experience, can ship without):** 18 sounds
- Workout: weight_adjust, exercise_swipe, rep_count, superset_transition, warmup_complete
- Timer: pomodoro_tick, session_milestone
- Notifications: evening_summary
- Arena: leaderboard_pass, xp_penalty
- System: tab_switch, pull_refresh, toggle_on, toggle_off, delete
- Ambient: all 8 tracks (can ship with 0, add incrementally)
