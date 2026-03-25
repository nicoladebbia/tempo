# USER JOURNEYS -- End-to-End System Flows

> **Document**: Complete User Journey Map
> **App**: Tempo (iOS, SwiftUI)
> **Version**: 1.0
> **Last Updated**: 2026-03-24
> **Author**: UX Research -- Cross-Module Integration Proof
> **Audience**: Developers, QA, Product. This document proves the 5 modules work as a unified system.

---

## How to Read This Document

Each journey is a second-by-second narrative told across all 5 modules simultaneously. The format:

- **Context**: Who, when, where, what state
- **Interaction Timeline**: Chronological events with exact screen names, notification copy, data flows, animations, haptics
- **Module Columns**: Dashboard (LifeOS), Training (RepForge), Accountability (Lockdown), Recovery (RecoverIQ), Arena (ClutchTime)
- **Emotional Arc**: How the user feels at each beat
- **Data Flows**: What gets written, what gets read, from which integration

**User profile for all journeys** (unless stated otherwise): Nicola, 22, university student in Miami. Trains 5x/week (PPL + football), Whoop 4.0, NutriTrack connected, 3 non-negotiables (Study 2h, Train, 3 Meals), PS5 time 7:30 PM weekdays / 9:00 PM weekends. Notification intensity: Drill Sergeant. Streak: 12 days. Level 14 (Warrior). Friend "Marco" on Arena.

---

## Journey 1: Perfect Monday

**Context**: Monday morning. Green recovery. Nicola executes every non-negotiable with time to spare. The system rewards discipline at every turn.

### 6:47 AM -- Whoop Detects Sleep End

| Module | Event |
|--------|-------|
| **Recovery** | Whoop API webhook fires to Tempo backend. Sleep data processed: 7.8h sleep, 92% sleep score, 1h 48m SWS, 2h 02m REM. Recovery score calculated: 82% (green zone). HRV: 72ms (up 15% from 30-day avg). RHR: 51bpm (down 3%). Backend stores data, triggers push notification. |
| **Dashboard** | `BodyQuadrantData` updated via background refresh: `recovery_score: 82`, `hrv_rmssd: 72.0`, `resting_heart_rate: 51`, `sleep_hours: 7.8`, `sleep_performance_percentage: 92`. |
| **Training** | Recovery-Based Adjustment Algorithm runs. 82% = green zone. Today's Push Day loaded at full volume. No adjustments. `adjustment_label: "Full Volume"`. Bench Press target: 85kg x 8 (up 2.5kg from last session -- progressive overload triggered). |
| **Accountability** | 3 non-negotiables initialized for today: Study 2h (0/120 min), Training (not started), Meals (0/3). Badge count set to 3. |
| **Arena** | Daily login XP pending (awarded on first app open). Monday bonus (+25 XP) queued. Streak multiplier: 1.5x (day 13). |

### 6:52 AM -- Morning Briefing Push Notification

**Notification (push, Time Sensitive):**
> **TEMPO** -- Morning Briefing
> "Recovery at 82%. Your body is ready. Push day on deck -- I want to see PRs on bench press. 3 non-negotiables today. No excuses. Let's go."

- **Copy source**: `notif.morning.green_recovery`, Drill Sergeant intensity
- **Sound**: Default system sound
- **Badge**: 3
- **Actions**: "View Day" (opens Dashboard), "Start Workout" (opens Training)
- **Emotional arc**: Nicola sees the notification on his lock screen. 82% recovery. Green. Feels energized before his feet hit the floor.

### 7:01 AM -- First App Open

Nicola taps the notification's "View Day" action.

**Dashboard (LifeOS) -- Main Dashboard View**:
- Header: "Mon, Mar 24" / "Rise and grind, Nicola."
- Score ring animates from 0 to 21 (only sleep data counted so far -- movement/study/nutrition still zero). Ring fill: red zone (21%). Counter rolls 0 -> 21 over 1.0s spring animation. Color: `tempo.red`.
- BODY quadrant: "82%" in `tempo.body.green`. HRV: 72.0, RHR: 51, Sleep: 7.8h. Strain bar empty (day just started).
- FUEL quadrant: "0 / 2,400 cal". All macro bars empty. "0/3 meals" indicator. Source: NutriTrack, last sync timestamp.
- MIND quadrant: "0m" study. "Calculus II in 18 days" exam countdown in `tempo.caption1`.
- MOVE quadrant: "Planned" badge. "Push Day" label. Steps: 342 (overnight).
- Non-Negotiables bar: 3 empty circles -- Study, Training, Meals. All unchecked.
- Insight banner: "Your recovery is 15% above average. Push hard today."

**Data flow**: HealthKit `HKObserverQuery` fires on app foreground -- step count updated (342). Whoop data from cache (5 min TTL, fresh). NutriTrack sync triggered (0 meals today).

**Arena (ClutchTime)**: +10 XP login bonus awarded. XP float animation: "+10 XP" in electric blue rises and fades (300ms). Today's XP card shows 10 XP. Monday bonus queued for first completed task.

**Haptic**: None (passive viewing).
**Emotional arc**: Dashboard is mostly empty but the green recovery score feels like a loaded weapon. The insight banner names the opportunity. Nicola feels ready.

### 7:15 AM -- Breakfast Logged via NutriTrack

Nicola opens NutriTrack (separate app), logs breakfast: 4 eggs, toast, banana. 520 cal, 36g protein, 48g carbs, 22g fat.

**Data flow**: NutriTrack API -> Tempo backend proxy -> Tempo iOS background refresh (3 min cache TTL). `FuelQuadrantData` updates: `calories_consumed: 520`, `protein_g: 36`, `meals_logged: 1`, `meal_statuses: [{name: "Breakfast", status: .logged}]`.

| Module | Event |
|--------|-------|
| **Dashboard** | FUEL quadrant updates with fade animation. Calorie ring fills slightly. "520 / 2,400 cal". Protein bar: 36g/180g (20%). "1/3 meals" text. |
| **Accountability** | Meals card: "1 / 3". Progress bar fills to 33%. Badge: "NUTRITRACK". Supporting text: "Next: Lunch". Status: In Progress. Border color changes to `progress.blue`. |
| **Arena** | +15 XP for logging breakfast (before 11:00 AM). XP float animation if app is open. |
| **Recovery** | Meal Timing prescription card: "Good start -- hit 30-40g protein within 1h after your morning session." (contextual, training planned). |

**Emotional arc**: First checkbox energy. The meals card going from "NOT STARTED" to "1 / 3" with the blue progress bar feels like momentum.

### 8:30 AM -- Arrives at Gym, Opens Training Tab

**Training (RepForge) -- Today's Workout View**:
- Date: "Monday, March 24"
- Title: "PUSH DAY" in `heroTitle`
- Recovery Badge Bar: "[green dot] 82% Recovery * Full Volume * [sync] 6:52 AM"
- Workout meta: "~52 min * 6 exercises * 24 sets"
- Exercise cards:
  1. BENCH PRESS -- 4 x 8 @ 85kg. "Last: 82.5kg x 8 [check]". Plates: 20+10+2.5 per side. Progressive overload arrow (`arrow.up.right` in primary color) visible.
  2. INCLINE DB PRESS -- 3 x 10 @ 32kg
  3A/3B. SUPERSET: Cable Fly 3x12 @ 15kg / Lateral Raise 3x15 @ 10kg
  4. OVERHEAD PRESS -- 4 x 8 @ 50kg
  5. TRICEP PUSHDOWN -- 3 x 12 @ 25kg
- START WORKOUT button pinned at bottom. Primary red background.

**Haptic**: `.light` on card tap when browsing exercises.

### 8:32 AM -- Taps START WORKOUT

**Training -- Active Workout View**:
- Full-screen push transition (500ms spring). Exercise list slides up. Start button morphs into workout timer bar.
- Timer starts: "00:00" in `metricSmall` (17pt, monospaced).
- First exercise: BENCH PRESS. Set 1 active. Weight pre-filled: 85kg. Reps pre-filled: 8.
- Plate hint: "Plates: 20 + 10 + 2.5 each side"

**Data flow**: `workout_status` changes to `.inProgress`. HealthKit workout session started (`HKWorkoutSession`). Apple Watch Live Activity begins (if Watch paired).

**Haptic**: `.medium` on workout start.

### 8:33-9:18 AM -- Workout Execution (45 minutes)

**Key moments during the workout**:

**8:38 AM -- Bench Press Set 3: PR Hit**
- Nicola logs 85kg x 8 (all 4 sets). On Set 3, this combination triggers a new estimated 1RM PR (e1RM: 107.5kg, previous best: 104.5kg).
- **Animation**: Gold shimmer on exercise name. PR badge pops in (scale 0 -> 1.15 -> 1.0, 400ms spring, `prGold` color). PR confetti burst (2000ms, gold particles).
- **Haptic**: `.success` + 200ms delay + `.success` (double tap for e1RM PR).
- **Sound**: None (gym -- user likely has earbuds).
- **Arena**: +75 XP queued for PR achievement.

**8:45 AM -- Superset 3A/3B**:
- After Cable Fly Set 1: NO rest timer. "SUPERSET -- No rest, go to Lateral Raise" banner. Immediate slide to Exercise 3B.
- **Haptic**: `.rigid` + `.rigid` rapid (urgency cue for superset transition).
- After Lateral Raise Set 1: Rest timer starts (60s for isolation superset). Round counter: "Round 1/3".

**9:18 AM -- Last Set Complete, Taps FINISH**:
- Final rest timer (skippable). Nicola taps "Skip" on rest timer.
- **Workout Summary (Post-Workout) View** appears:
  - Ring animation fills to 100% (800ms easeInOut).
  - Duration: 45 min. Exercises: 6/6. Sets: 24/24. Volume: 8,420 kg.
  - PR SECTION: "NEW PR: Bench Press e1RM 107.5kg (+3kg)" with gold badge.
  - Recovery compliance: "Green recovery day -- full volume executed. Perfect."
- **Haptic**: `.success` + custom pattern (3 pulses) -- workout finished.

**Data flow (write)**:
- HealthKit: workout written (strength training, 45 min, 380 active cal).
- Local DB: all set data, PR record, workout summary.
- Whoop: strain will update on next sync (workout contributes to daily strain).

| Module | Event |
|--------|-------|
| **Dashboard** | MOVE quadrant updates: `workout_status: .completed`. "Push Day" with green checkmark. Active calories jump to ~380. Steps climbing (walked to gym). Daily score recalculates: now ~45 (recovery 82 contributes, workout done, no study/meals yet). |
| **Accountability** | Training card: "DONE [checkmark]" with green border. Progress bar: 100%. Badge: "WHOOP". Supporting text: "45 min strength recorded at 9:18 AM". Card has completion animation: checkmark draws itself (0.3s), card scales 1.0->1.03->1.0 (spring, 0.4s). Haptic `.success`. Leisure status: "Complete 2 more to unlock". Progress bar partially filled. |
| **Arena** | XP batch awarded: +100 (workout) +50 (recovery-adjusted compliance, green zone) +30 (intensity, heavy) +25 (Monday bonus) +75 (PR) = +280 XP base. With 1.5x streak multiplier = **+420 XP**. XP float animations stack. Level progress bar advances visibly. |
| **Recovery** | Strain data will update on next Whoop sync. Prescription: "Post-workout window open -- hit 30-40g protein within 1h." |

**Emotional arc**: The PR celebration is the dopamine peak of the morning. Gold confetti, double haptic, 420 XP flooding the Arena. The Accountability training card flipping to green with one tap makes the system feel effortless.

### 9:45 AM -- Post-Workout Meal (Lunch logged early)

NutriTrack: logs chicken breast, rice, vegetables. 680 cal, 52g protein, 72g carbs, 18g fat.

| Module | Event |
|--------|-------|
| **Dashboard** | FUEL: "1,200 / 2,400 cal". Protein: 88g/180g. "2/3 meals". |
| **Accountability** | Meals card: "2 / 3". Progress bar: 67%. Supporting text: "Next: Dinner before 8pm". |
| **Arena** | +15 XP (lunch logged before 15:00). |
| **Recovery** | Prescription update: "Good -- 52g protein post-workout. On track for daily target." |

### 10:30 AM -- Study Session 1 Begins

Nicola opens Accountability tab, taps "START STUDY TIMER" quick action button.

**Accountability -- Focus Timer View**:
- Full-screen modal slides up (`.fullScreenCover`).
- Session indicator: "Session 1 of 4" in `subheadline`.
- Subject selector: taps, selects "Calculus II" from recent subjects.
- Timer: 25:00 in `timer` font (72pt). Ring full. Phase: "READY".
- Taps PAUSE/RESUME button (now showing play icon + "START").
- **Haptic**: `.heavy` on start.
- Timer begins counting down. Ring drains clockwise. Phase: "FOCUS TIME" in `progress.blue`.
- Live Activity starts on lock screen and Dynamic Island: "[Book] Study: Calculus II -- 24:42 -- Session 1/4".
- Screen auto-lock disabled.

**10:55 AM -- Session 1 Complete**:
- Timer hits 0:00.
- **Sound**: completion chime.
- **Haptic**: `.success` + `.rigid`.
- Ring fills with celebration color, resets.
- "Break starts in 3..." auto-countdown. 5-minute break begins.
- Break screen: green gradient. Message: "Stand up. Stretch. You've earned it."
- Accumulated time display: "Today's total: 25m / 2h"

**11:00 AM -- Session 2 starts** (auto-start after break).
**11:25 AM -- Session 2 Complete**. Total: 50m / 2h.

**11:30 AM -- Session 3 starts**.
**11:55 AM -- Session 3 Complete**. Total: 1h 15m / 2h.

**12:00 PM -- Session 4 starts** (long break was 15 min after session 3).
**12:25 PM -- Session 4 Complete. All Sessions Done.**

**Completion celebration**:
- Longer sound (2s celebratory).
- **Haptic**: triple success.
- Full-screen overlay: Large checkmark draws itself (0.5s). "All Sessions Complete!" in `title1`, `unlocked.green`. "2h 07m of focused study" (includes 7 bonus minutes from session overruns). Focus Score: 91 ("Excellent").
- "DONE" button dismisses.

| Module | Event |
|--------|-------|
| **Dashboard** | MIND quadrant: "2h 07m" in `tempo.title1`. Study target met. Exam countdown: "Calculus II in 18 days". Daily score jumps to ~72 (recovery + workout + study). Counter rolls from 45 -> 72. Ring color crossfades from yellow to green. |
| **Accountability** | Study card: "DONE [checkmark]". "2h 07m total across 4 sessions". Green border. Completion animation fires. Leisure status: "Just 1 more. You're right there." in `progress.amber`. Lock icon shakes (rotateZ -3deg to 3deg, 0.15s, 3 times). |
| **Arena** | +80 XP (daily study target hit) +30 XP x4 (4 sessions of 25+ min) = +200 XP base. x1.5 = **+300 XP**. |

**Emotional arc**: "Just 1 more. You're right there." The shaking lock icon creates anticipation. One meal away from freedom.

### 12:30 PM -- No Gentle Reminder Fires

At 1:00 PM, the Tier 1 Gentle Reminder check runs. Completion is at 67% (2/3 non-negotiables done). Condition requires < 50%. **Notification suppressed.** The system is smart enough to not bother someone who is winning.

### 5:30 PM -- Dinner Logged

NutriTrack: logs salmon, sweet potato, salad. 720 cal, 48g protein, 62g carbs, 28g fat.

| Module | Event |
|--------|-------|
| **Dashboard** | FUEL: "1,920 / 2,400 cal". Protein: 136g/180g. "3/3 meals". All meals logged checkmark appears with scale-in spring (0.3s). Daily score recalculates: **84**. Ring fill: green. |
| **Accountability** | Meals card: "DONE [checkmark]". "All 3 meals logged today". All cards now green. |

### 5:30 PM -- ALL NON-NEGOTIABLES COMPLETE -- THE UNLOCK

**Tier 5 Completion Celebration fires immediately (in-app, foregrounded)**:
- **Confetti**: 80 particles, gold/green/blue, 3s duration, physics-based fall.
- **Green glow pulse**: Full-screen, 2 cycles.
- **Lock animation**: Lock icon transitions from locked (red) to unlocked (green) with spring animation. Shackle lifts, slight rotation (-5deg to 0deg), scale pulse 1.0 -> 1.2 -> 1.0.
- **Sound**: `tempo_clear.caf` -- bright ascending chime, 0.5s.
- **Haptic**: triple `.success`, 200ms apart.
- Leisure Status section: "You earned it. Enjoy your evening." in `unlocked.green`. Progress bar full, green, shimmer animation (2 cycles).

**Arena** XP burst:
- +10 XP x 3 individual non-negotiables = 30 XP
- +60 XP bonus (all non-negotiables complete)
- +200 XP Perfect Day bonus (workout + study target + all meals + all non-negotiables + sleep logged)
- Subtotal: +290 XP base x 1.5 = **+435 XP**

**Arena total for the day so far**: 10 (login) + 420 (workout/PR) + 300 (study) + 45 (meals) + 435 (completion) = **1,210 XP** (before step bonuses). This is an elite day.

**Notification (if app were backgrounded)**:
> **TEMPO** -- All Clear
> "ALL CLEAR. Non-negotiables: DONE. Leisure: UNLOCKED. You earned tonight. Enjoy it guilt-free."
> Sound: `tempo_clear.caf`

**Emotional arc**: This is the moment the entire app builds toward. The confetti, the lock opening, the chime. Nicola feels the earned relief. The PS5 is guilt-free tonight. 12-day streak becomes 13.

### 6:00 PM -- Checks Arena

**Arena (ClutchTime) -- Arena Main View**:
- Hero card: "LVL 14 -- WARRIOR" with streak fire "13" (orange flame, animated flicker).
- Today's XP card: large "1,210 XP" in SF Mono 48pt, electric blue. Counts up from 0 with slot-machine animation (1200ms). Multiplier: 1.5x.
- XP breakdown: Workout +420, Study +300, Meals +45, Tasks +435, Login +10.
- Leaderboard preview: "1. You -- 2,850 XP LV14" (ahead of Marco this week).
- Recent achievements: "Iron Will" badge glows (30-day streak approaching at day 13).

**Emotional arc**: Seeing the XP number and being #1 on the leaderboard. The competitive satisfaction of outpacing Marco.

### 9:15 PM -- Evening Wind-Down

**Recovery -- Bedtime Prescription** (viewed earlier but relevant now):
> "Target: 10:30 PM. Sleep debt: 0.3h. Maintain your current routine."

**Dashboard** at end of day:
- Daily Score: **84** (green ring, nearly full).
- BODY: 82% recovery, strain climbing to ~12.4 from workout.
- FUEL: 1,920/2,400 cal. 136g/180g protein.
- MIND: 2h 07m. 13-day streak.
- MOVE: Push Day complete. 9,847 steps. 380 active cal.
- Non-Negotiables: 3/3 green checkmarks.

**Arena end-of-day**: Streak extended to 13 days. Total XP: ~1,260 (with steps bonus at 8K tier: +35 base x 1.5 = +52). Perfect Day in the books.

**Emotional arc**: Nicola goes to bed feeling in control. The daily score of 84, the green dashboard, the leaderboard position -- all data confirming he is on track. Sleep comes easy.

---

## Journey 2: Red Recovery Day

**Context**: Tuesday. Nicola slept 4.8 hours (was up late with a group project). Recovery: 28% (red). The system adapts everything to protect him.

### 6:15 AM -- Whoop Processes Sleep

**Data flow**: Sleep: 4.8h, sleep score: 38%, HRV: 41ms (down 43% from average), RHR: 63bpm (elevated). Recovery: 28% (red zone).

| Module | Event |
|--------|-------|
| **Recovery** | RecoverIQ processes red zone. Prescription engine runs: Training -> "Swapped to Mobility". Bedtime -> "Target: 9:30 PM. Sleep debt: 3.2h. Get 9h tonight." Caffeine -> "No caffeine after 1:30 PM." |
| **Training** | Recovery-Based Adjustment Algorithm: 28% = red. Today was scheduled as Pull Day. **Swapped to Mobility Flow** (~25 min). Original Pull Day postponed to Wednesday (if recovery allows). Exercise list replaced with: Foam Roll (10 min), Dynamic Stretching (8 min), Yoga Flow (7 min). |
| **Accountability** | Training non-negotiable target adjusts: still binary "Training" but the expected session is now mobility, not weights. No penalty for red-day adaptation. |

### 6:20 AM -- Morning Briefing Push

> **TEMPO** -- Morning Briefing
> "Recovery at 28%. Your body is waving a white flag. Swapping to mobility work today -- you'll thank me tomorrow. But study and meals are still non-negotiable. Red recovery doesn't mean red on everything."

- **Copy source**: `notif.morning.red_recovery`, Drill Sergeant intensity
- **Emotional arc**: The tone is firm but protective. Not punishing. Nicola knows the system has his back.

### 7:30 AM -- Opens Dashboard

**Dashboard**:
- Score ring: low fill, red color. Score: 12 (only partial sleep credit).
- BODY quadrant: "28%" in `tempo.body.red`. HRV: 41.0 (red arrow down), RHR: 63 (red arrow up), Sleep: 4.8h.
- Insight banner: "Your HRV dropped 43%. Prioritize recovery today. Mobility only."

**Recovery -- Recovery Today View** (Nicola taps BODY quadrant to expand, then navigates to Recovery tab):
- Recovery Ring: 28% fill in `recovery.red.primary`. Red glow behind ring.
- Comparison label: "↓ 42% below your average" in red.
- MetricTiles: HRV 41ms (red, ↓43%), RHR 63 (red, ↑21%), SpO2 96% (normal), Temp +0.2C (normal).
- Prescription cards:
  - Training: "Easy day -- mobility, stretching, or light cardio. Your body needs full recovery."
  - Meal Timing: "Prioritize protein today -- aim for 2g/kg body weight. Include magnesium-rich foods."
  - Bedtime: "Target: 9:30 PM. Sleep debt: 3.2h. Get 9h tonight."
  - Caffeine: "No caffeine after 1:30 PM. 8h buffer before target bedtime."
  - Hydration: "Target: 2.8L today. No training adjustment needed."

**Training -- Today's Workout View**:
- Title: "MOBILITY FLOW"
- Recovery Badge Bar: "[red dot] 28% Recovery * Swapped to Mobility"
- Workout meta: "~25 min * 3 activities"
- Exercise cards: Foam Roll -- Lower Body (10 min), Dynamic Stretching (8 min), Yoga Flow (7 min).
- START button: "START MOBILITY SESSION"

**Emotional arc**: The red everywhere is sobering but not demoralizing. The system adapted. It did not say "skip everything." It said "do the right thing for today."

### 10:00 AM -- Completes Mobility Session

25 minutes of mobility work. Logs via Training module.

| Module | Event |
|--------|-------|
| **Accountability** | Training card: "DONE". 25 min mobility recorded. Green checkmark. |
| **Arena** | +100 XP (workout complete) +20 (recovery-adjusted compliance, red zone -- still trained = bonus) = +120 base x 1.5 = **+180 XP**. |
| **Dashboard** | MOVE: "Mobility Flow [checkmark]". |

### 10:30 AM -- 2:30 PM -- Study Sessions

Nicola studies in 25-min Pomodoro blocks. Focus Score is lower (74 -- "Fair") due to more pauses and distractions. The low recovery is affecting cognitive function.

| Module | Event |
|--------|-------|
| **Accountability** | Study card progresses: 25m, 50m, 1h15m, 1h40m, 2h05m. Target hit at ~2h mark. "DONE" status. |

### Throughout the Day -- Meals Logged

Breakfast, lunch, and dinner logged through NutriTrack. High protein emphasis per prescription.

### 6:45 PM -- All Complete

All 3 non-negotiables done. Unlock celebration fires. But the day feels different -- more about survival than domination.

**Arena total**: ~650 XP (lower than yesterday's 1,260 -- no PR, lower workout XP, lower study quality). But streak extends to 14 days. Multiplier stays at 1.5x.

**Recovery prescription check-in (evening)**: "Feedback: Was today's prescription helpful?" appears after 6 PM. Nicola taps thumbs up.

### 9:15 PM -- In Bed Per Prescription

Nicola follows the 9:30 PM bedtime target. Phone face-down.

**Emotional arc**: The day was hard. But the system made it manageable by adapting the physical load while maintaining the mental and nutritional standards. The 14-day streak survives. Tomorrow's recovery should bounce back.

---

## Journey 3: Exam Week Crisis

**Context**: Wednesday. Calculus II exam in 3 days (Saturday). Exam Mode auto-activated. Study target increased from 2h to 3h. PS5 time moved from 7:30 PM to 6:30 PM. Notification intensity forced to Savage.

### 7:00 AM -- Morning Briefing

> **TEMPO** -- Morning Briefing
> "Calculus II exam in 3 days. That's 3 study sessions if you hit your target every day. Zero room for slacking. Training is light this week. Books come first. War mode."

- **Copy source**: `notif.morning.exam_approaching`, Drill Sergeant intensity

**Accountability -- Lockdown Main View**:
- **Exam Mode banner** at top: "[!] EXAM MODE ACTIVE -- Calculus II Final in 3 days -- Study target: 2h -> 3h [Deactivate]". Red-tinted background, red border.
- Study card: "0h 00m / 3h (exam mode: +1h)". Badge: "MANUAL". Action: "Start Timer".
- PS5 countdown: "11h 30m until your usual PS5 time" (now 6:30 PM).
- Exam countdown in study card: "CALCULUS II IN 3 DAYS" in `locked.red`.

### 9:00 AM -- 12:00 PM -- Marathon Study Block

Nicola uses Deep Work sessions (90 min focus, 20 min break) instead of Pomodoro. Timer settings sheet: selects "Deep Work".

**Session 1**: 90 min, Calculus II. Focus Score: 88.
**Break**: 20 min. Eats lunch.
**Session 2**: 90 min, Calculus II. Focus Score: 82.

**Accumulated time**: 3h 00m / 3h. Target hit by noon.

**Accountability**: Study card: "DONE". Supporting text: "3h 00m total across 2 sessions". But the exam countdown remains visible: "3 DAYS".

**Arena**: +80 XP (study target) + 30x2 (two 25+ min sessions -- actually these are 90 min sessions, so 30x6 for each 25-min block within the 90? No -- study session XP is per discrete session started, min 25 min. Two sessions = +60 XP). Exam mode survival bonus queued for end of exam week.

### 1:00 PM -- No Gentle Reminder (Suppressed)

Study done. Training light. Meals on track. System recognizes the user is ahead.

### 2:00 PM -- Accountability Notification (Context-Aware)

Even though study is done, an exam-context notification fires because overall completion is < 50% (training and 1 meal remaining):

> "Calculus II in 3 days. Study target hit -- good. Now eat and do your light session. Don't let the small stuff slide."

### 5:00 PM -- All Complete Before Exam-Adjusted PS5 Time

Training (light 30-min session) and all 3 meals done by 5:00 PM. Unlock at 5:00 PM -- 1.5 hours before the exam-adjusted 6:30 PM deadline.

**Celebration notification variant**:
> "Exam mode. Enhanced targets. You still finished 100%. 14 days. This is built different. Calculus II doesn't stand a chance."

**Emotional arc**: Exam mode is stressful but the structure helps. 3 hours of focused study done by noon means the afternoon is free for review, food, and a light session. The system compressed the pressure into the morning.

---

## Journey 4: Football Day

**Context**: Wednesday. Football match at 8:00 PM. No gym today. The system has been preparing since yesterday.

### Day Before (T-1): Tuesday's Training View

**Training -- Today's Workout View (Tuesday)**:
- Info banner between recovery badge and workout meta: "[ball] Football tomorrow -- legs protected. Upper body focus." Yellow left border accent. `info.circle` icon.
- Workout: UPPER BODY (no heavy legs).

### Match Day: Wednesday 7:00 AM -- Morning Briefing

> **TEMPO** -- Morning Briefing
> "Game day. No gym -- your strain comes from the pitch today. But 2h study still happens, and 3 meals are mandatory. Eat carbs 3 hours before kickoff. Hydrate. Perform. No excuses for missing study because of a game."

- **Copy source**: `notif.morning.game_day`, Drill Sergeant intensity

### 7:30 AM -- Dashboard

**Training -- Football Day View**:
- Title: "FOOTBALL DAY"
- Recovery Badge Bar: "[green dot] 72% Recovery * Match Day"
- Event card: "[ball] Football @ 8:00 PM -- Location: Campo Sportivo -- Duration: ~90 min"
- PRE-MATCH PREP section: Foam Roll (10 min), Dynamic Stretching (8 min), Activation -- Glutes/Core (7 min).
- "START PRE-MATCH PREP" button.
- Bottom text: "Tomorrow: REST or UPPER BODY (depends on recovery after match)"

**Recovery -- Prescription cards**:
- Training: "Match day -- strain comes from the pitch. No additional gym training."
- Meal Timing: "High-carb meal 3-4h before kickoff. 1-1.5g/kg carbs." (For 8 PM kickoff: eat by 5 PM.)
- Hydration: "Target: 3.5L today. +750ml for match."

### 10:00 AM -- 12:30 PM -- Study Sessions

2h 15m of study logged. Calculus II focus.

### 5:00 PM -- Pre-Match Meal

NutriTrack: Pasta with chicken. High carb (120g carbs, 45g protein). Recovery prescription followed.

### 6:30 PM -- Pre-Match Prep

Nicola opens Training, taps "START PRE-MATCH PREP". 25-minute session: foam roll, stretching, activation. Logged as training for the day.

**Accountability**: Training card flips to "DONE". All 3 non-negotiables complete by 6:30 PM.

**Unlock celebration fires**. PS5 time irrelevant -- Nicola is heading to the pitch, not the couch. But the unlock means no guilt, no notifications during the match.

### 8:00 PM - 9:30 PM -- Football Match

Whoop tracks the match as high strain (estimated 15-18 strain for 90 min of football). Heart rate data streams to HealthKit. No Tempo interaction during the match.

### 10:00 PM -- Post-Match

**Dashboard** (opened briefly): Strain bar nearly full. Daily strain: 16.2. Steps: 14,800 (including match). Active calories: 890.

**Arena**: Steps hit 10K tier (+50 XP base, replacing 8K), hit 15K tier later (+75 XP, replacing 10K). Workout XP from pre-match prep already counted.

**Recovery**: Bedtime prescription updates: "High strain day (16.2). Target bedtime: 10:00 PM. Your body needs 8.5-9h sleep to recover from the match."

### T+1: Thursday Morning

Recovery will likely be yellow (50-65%) due to high match strain. Training auto-adjusts Thursday's workout: lighter pull session or rest day, depending on recovery score.

**Emotional arc**: The system choreographed the entire day around the match -- carb timing, pre-match prep, no heavy legs the day before. Nicola went to the pitch prepared and came back knowing tomorrow's plan adjusts automatically.

---

## Journey 5: The PS5 Trap

**Context**: Thursday afternoon. Nicola has done his training but study is at 22 minutes (of 2h target) and only 1 meal logged. He is playing PS5 at 3:30 PM. The system escalates.

### 1:00 PM -- Tier 1: Gentle Reminder

Completion: 33% (1/3 done -- training only). Study at 0%. Meals at 1/3.

> **TEMPO** -- Accountability
> "Afternoon check-in. You haven't started studying yet. There's still time -- start a 25-minute session."

- **Copy source**: `notif.accountability.gentle.general`, Drill Sergeant intensity: "Afternoon check-in. Study: 0 of 2h done. Training: done. You've got 6h 30m before your evening. That's more than enough. Start now."

Nicola dismisses the notification. Keeps playing PS5.

### 3:00 PM -- Brief Study Attempt

Nicola starts a Pomodoro session. Studies 22 minutes. Gets distracted. Stops. Goes back to PS5.

### 3:15 PM -- Tier 2: Firm Warning

Completion: 33% (study at 22/120 min = 18%). Triggers at 3 PM window.

> **TEMPO** -- Accountability (Time Sensitive)
> "It's 3 PM. Study: 22 min of 2h. That's not going to cut it. PS5 time is in 4h 30m. Pick up the pace or tonight is locked."

- **Sound**: `firm_warning.caf` -- double-tap tone.
- Nicola sees it. Feels a pang of guilt. Keeps playing.

### 4:30 PM -- Tier 2: Second Firm Warning

> "You've been 'about to start' for 3 hours. Start. PS5 time in 3h. Study at 22 min. Your 14-day streak is in danger."

### 5:30 PM -- Tier 3: Urgent Alert

Completion: ~40%. Study: 22/120 min. Meals: 1/3. Time sensitive.

> **TEMPO** -- URGENT
> "URGENT. 2 hours until PS5 time. You still need: 1h 38m study, 2 meals. No excuses."

- **Sound**: `tempo_urgent.caf` -- three ascending tones, 1s. Impossible to ignore.
- **Haptic**: stronger notification vibration.
- **Actions**: "Start Study Timer" (auto-starts), "I'm On It"

Nicola's hands twitch on the controller. He looks at the notification. The math is clear: 1h 38m of study in 2 hours. It is barely possible.

### 5:35 PM -- Nicola Gives In

He puts down the controller. Opens Tempo via "Start Study Timer" notification action. Focus Timer auto-starts. Deep Work mode: 50-minute session.

**Focus Timer View**: Timer running. "Calculus II". Ring draining. "Today's total: 22m / 2h".

### 6:25 PM -- Session 1 Complete

Study total: 1h 12m / 2h. Nicola eats quickly (logs lunch and dinner in NutriTrack -- 2 meals added).

### 6:30 PM -- Tier 3: Second Urgent Alert

> "6:30. Study: 1h 12m out of 2h. 48 min missing. Your evening starts in 1 hour. You are NOT going to make it at this pace. Drop everything. Timer on. NOW."

Nicola starts another session. 50 minutes.

### 7:10 PM -- Study Complete

Study: 2h 02m / 2h. Meals: 3/3 (logged the third meal at 7:00 PM).

### 7:10 PM -- ALL COMPLETE -- The Comeback Unlock

**Celebration fires** (20 minutes before PS5 time):

Special context-aware variant:
> "THE COMEBACK. You were at 40% when the urgent alerts hit. You finished at 100%. That's clutch. 15 days."

- Confetti, lock animation, chime, triple haptic.
- Leisure Status: "Unlocked 20m early. Ahead of schedule." (barely, but technically true)

**Arena**: Perfect Day bonus applies. All non-negotiables done. +200 XP bonus.

**Emotional arc**: This is the journey that proves the notification escalation works. Gentle at 1 PM, firm at 3 PM, urgent at 5:30 PM. The tone got progressively sharper. Nicola resisted through Tier 1 and Tier 2. Tier 3's sound and copy broke through. He came back from the brink. The "COMEBACK" celebration acknowledges the struggle -- it does not pretend he was on time.

---

## Journey 6: First Day Ever

**Context**: Brand new user. Just downloaded Tempo from the App Store. Zero data. Zero integrations. The first 15 minutes.

### 0:00 -- App Launch: Splash Animation

- 0.0-0.3s: Black screen. "TEMPO" fades in (SF Pro Display Black, 48pt, white, tracking +6pt).
- 0.3-0.8s: Thin horizontal line expands from center beneath wordmark.
- 0.8-1.2s: "YOUR LIFE OPERATING SYSTEM" fades in (14pt, 60% white).
- 1.2-1.8s: Hold, then scale 1.0 -> 1.05x, fade to first onboarding screen.

### 0:02 -- Step 1: Welcome / Value Prop

- Screen: Four concentric rings animation (fitness/nutrition/recovery/academics) merge into one unified ring pulsing amber.
- Headline: "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS."
- Subtext: "Training. Nutrition. Recovery. Academics. One system. One score. Zero excuses."
- CTA: "GET STARTED" (amber, 56pt height).
- **Haptic**: `.light` on tap.

### Steps 2-12 -- Onboarding Flow (Summary)

Key moments:
- **Step 2**: Sign in with Apple. Face ID. 3 seconds.
- **Step 3**: Profile: "Nicola", "@nicola.debbia". Photo optional.
- **Step 4**: Training: Yes, Gym + Team Sport (Football), 5 days/week, PPL, Intermediate, 60 min, Full Gym, kg.
- **Step 5**: Academics: Yes, University of Miami, Calculus II + Organic Chemistry, Calculus II exam Jun 12, 2h daily study goal, Calendar imported.
- **Step 6**: Goals: Build Muscle, Non-negotiables: Train/Study 2h/Eat 3 meals, Time-waster: PS5/Gaming, Evening: 7:30 PM.
- **Step 7**: Connect Whoop: OAuth flow. "Connected! Recovery: 72%." Auto-advance.
- **Step 8**: Connect NutriTrack: server URL + PIN. "Connected! Today: 1,840/2,400 cal."
- **Step 9**: HealthKit: Authorize. Green confirmation.
- **Step 10**: Notifications: Drill Sergeant (recommended, pre-selected). Live preview updates. "ENABLE NOTIFICATIONS". System dialog: Allow.
- **Step 11**: Arena: shares invite link to Marco via iMessage.
- **Step 12**: Summary: "YOU'RE LOCKED IN." Typewriter effect.

### Step 12 -- First Dashboard With Real Data

**Dashboard** loads with the transition: summary screen scales down and fades, Dashboard scales up from behind (0.5s spring).

- Score ring: animates from 0 to 48 (partial data from Whoop + NutriTrack).
- BODY: 72% Recovery (yellow zone) -- Whoop data instant.
- FUEL: 1,840/2,400 cal from NutriTrack (meals already logged today in the other app).
- MIND: 0m study. "Calculus II in 80 days".
- MOVE: No workout yet. Steps: 4,212 (from HealthKit).
- Non-Negotiables: 3 items, none checked. Study, Training, 3 Meals.
- Insight banner: "Welcome to Tempo! Complete your first non-negotiable to start your streak."

**Arena**: Level 1 (Rookie). 0 XP. +10 login bonus. Empty leaderboard ("Add friends to compete!").

**Emotional arc**: The dashboard is alive. Data from Whoop and NutriTrack populated instantly. It feels like the app already knows Nicola. The "Welcome" insight makes it personal. The empty non-negotiable checkboxes are a clear call to action.

---

## Journey 7: Streak Milestone (30 Days)

**Context**: Saturday morning. Day 30 of consecutive non-negotiable completion. This is a major milestone.

### 7:00 AM -- Morning Briefing (Special)

> **TEMPO** -- Morning Briefing
> "30 days straight. That's not luck, that's identity. You're the person who shows up now. Don't you dare break this today. Push day + 1h study + 3 meals. Standard operating procedure."

- **Copy source**: `notif.morning.streak_milestone`, Drill Sergeant intensity

### Throughout the Day -- Normal Execution

Nicola completes all non-negotiables by 5:00 PM.

### 5:00 PM -- 30-Day Unlock Celebration (Enhanced)

**Standard unlock celebration PLUS milestone-specific**:

**Accountability -- Streak & Consistency View** (auto-navigated):
- Streak counter: "30" in `streakNumber` (56pt). Odometer animation: each digit slides up independently (0.3s stagger per digit, spring).
- Flame icon: **Blue flame with particle trail** (30-day tier upgrade from orange). New animation loads.
- "Longest: 30 days" with trophy icon -- **new record!**
- Calendar heatmap: 30 consecutive dark green cells. Visual proof of consistency.

**Arena milestone events**:
- Streak multiplier upgrades: 1.5x -> **1.75x** (30-59 day tier). The multiplier change is announced with a special XP animation.
- Achievement unlocked: **"Iron Will" badge** -- "30 consecutive days of discipline." Gold badge with sword icon. Badge pops in with scale 0->1.15->1.0 (400ms spring). Haptic: `.success` x2.
- +150 XP achievement bonus x 1.75 multiplier = **+262 XP**.
- Notification to friends: "Nicola just hit a 30-day streak!" appears in Marco's social feed.

**Celebration notification (context-aware)**:
> "NEW RECORD. 30 days. Your longest streak EVER. You just made history. Enjoy tonight -- you're in uncharted territory."

**Weekly Summary (Sunday)**: Will feature the milestone prominently: "PERFECT WEEK. 7 for 7. 30-day streak milestone. You're building a legacy."

**Emotional arc**: 30 days is the first truly meaningful milestone. The blue flame upgrade is visible everywhere -- on the Dashboard, in Arena, on the profile. It is a status symbol. The 1.75x multiplier makes every future action worth more XP.

---

## Journey 8: Friend Challenge

**Context**: Monday. Marco sends Nicola a challenge: "Most Study Hours This Week." 7-day challenge.

### Monday 10:00 AM -- Challenge Invite Arrives

**Push notification (Arena)**:
> **TEMPO** -- Arena
> "Marco challenged you: Most Study Hours (7 days). Think you can beat him? Accept or decline."

- **Actions**: "Accept" (foreground), "View Details" (foreground)

Nicola taps "Accept".

**Arena -- Challenges View**:
- Challenge card appears: "vs Marco: Most Study Hours"
- Score: "You: 0h | Marco: 0h"
- Progress bar: empty. "7 days left."
- +25 XP for joining the challenge.

### Throughout the Week -- Daily Tracking

Each day, the morning briefing includes challenge context:
> "You accepted Marco's challenge. Today every non-negotiable is a weapon. 2h study -- XP. Dominate today and the challenge is yours."

**Arena Main View** updates in real-time:
- Score comparison updates as study sessions are logged.
- Wednesday: "You: 6.5h | Marco: 7.2h" -- Nicola is behind. Score in red.
- The gap text: "0.7h behind" creates urgency.

**Social notifications throughout the week**:
- "Marco just logged 2h of study today. You've logged 1h. Step up."
- "You pulled ahead! 10.5h vs Marco's 10.2h. Don't let up."

### Friday Afternoon -- Nicola Pushes Extra

Seeing Marco at 12.5h, Nicola does an extra 30-min session bringing him to 13.2h.

### Sunday 11:59 PM -- Challenge Ends

**Final result**: Nicola 14.8h vs Marco 14.2h. **Nicola wins.**

**Arena celebration**:
- +200 XP (win 1v1 challenge) x 1.75 multiplier = **+350 XP**.
- Challenge result card: "VICTORY! You studied 14.8h vs Marco's 14.2h. 0.6h margin."
- Victory animation: challenge card transforms with a gold border, trophy appears, confetti.
- Achievement: "Challenge Accepted" badge if this is first challenge win.

**Push to Marco**:
> "Nicola beat you in Most Study Hours: 14.8h to 14.2h. Rematch?"

**Emotional arc**: The challenge turned study into a competitive sport. Nicola studied 14.8h instead of his normal ~14h because the competition pushed him. The system weaponized social pressure for good.

---

## Journey 9: Sick Day

**Context**: Wednesday. Nicola wakes up feeling terrible. Sore throat, fatigue. Doesn't want to break his streak.

### 7:30 AM -- Activates Sick Day

Opens Accountability settings. Navigates to Rest Day / Sick Day system.

**Accountability -- Lockdown Main View**: Long-press context menu on any card -> "Activate Sick Day" option.

**Confirmation dialog**: "Activate Sick Day? Targets will be reduced. Your streak will be preserved. You can still complete tasks if you feel up to it."

Nicola confirms.

**System changes**:
- Non-negotiables adjust: Study target halved (2h -> 1h). Training: optional (marked as skipped, no penalty). Meals: reduced to 2 (vs 3).
- Leisure Status: "Sick day. Reduced targets active." in `text.secondary`. Lock icon: unlocked, grey.
- Notifications: intensity drops to Gentle regardless of setting. Only morning briefing and completion fire. No firm/urgent/final warnings.
- **Streak preserved**: Sick day counts as a completed day for streak purposes.

**Arena**: No XP penalties applied. Sick day flag prevents penalty calculation at end-of-day.

### Throughout the Day

Nicola manages 45 minutes of light study and 2 meals. The reduced targets mean he still hits 100% on the adjusted plan.

**Celebration (adjusted)**: "All done on a sick day. Rest up. Your streak is safe at 31 days."

**Recovery prescription (auto-adjusted)**:
- "Rest is the priority. No training today. Hydrate extra: 3L minimum. Early bedtime: 9:00 PM."

**Emotional arc**: The sick day system prevents the worst-case scenario: losing a 31-day streak because of illness. The reduced targets feel achievable even while feeling terrible. The streak survives, and the system does not pretend it was a normal day.

---

## Journey 10: Sunday Weekly Review

**Context**: Sunday 8:00 PM. End of week. The weekly summary fires.

### 8:00 PM -- Weekly Summary Push Notification

> **TEMPO** -- Weekly Summary
> "Almost perfect. 19/21 non-negotiables (90%). Study: 14.2h. Missed: Wednesday dinner skipped, Friday study 30 min short. Meals was the weak link at 81%. Streak: 32 days."

- **Copy source**: `notif.weekly.near_perfect`, Standard intensity
- **Actions**: "View Full Report" (opens Weekly Report View), "Dismiss"

### 8:01 PM -- Opens Weekly Report

**Dashboard -- Weekly Report View**:

**Hero section**:
- Week score: "90%" in large type. Color: green (>80%).
- Trend arrow: "↑ 5% from last week"

**Per-module breakdown**:
| Category | Score | Detail |
|----------|-------|--------|
| Study | 93% | 14.2h of 15.2h target. Best day: Monday (2h 45m). Worst: Friday (1h 30m). |
| Training | 100% | 5/5 sessions. 1 PR (Bench Press). Mobility day honored on Tuesday (red recovery). |
| Meals | 81% | 17/21 meals logged. Missed: Wed dinner, Sat breakfast, Sun snack. |
| Recovery | Avg 68% | 3 green days, 3 yellow, 1 red (Tuesday). HRV trending up 8%. |

**AI Insights** (Claude API-powered):
- "Your study peaks on Monday mornings (avg Focus Score: 91) and dips on Fridays (avg: 72). Consider front-loading study earlier in the week."
- "Dinner is your most-skipped meal (skipped 3x this month). Set a 6 PM reminder specifically for dinner prep."
- "Your Tuesday red recovery correlated with Monday's late bedtime (11:45 PM vs target 10:30 PM). Protecting Monday sleep protects Tuesday training."

**Calendar heatmap** (this week):
- Mon: dark green (100%)
- Tue: dark green (100% -- sick day adjusted)
- Wed: medium green (89% -- dinner skipped)
- Thu: dark green (100%)
- Fri: light green (78% -- study short)
- Sat: dark green (100%)
- Sun: dark green (100%)

**Next week planning section**:
- "Next week: Calculus II exam Saturday. Exam Mode will activate Wednesday. Study targets increase to 3h/day."
- "Suggested focus: Shore up dinner consistency. Your protein suffers most when you skip it."

**Arena**: Weekly leaderboard finalizes. Nicola: #1 (3,240 XP). Marco: #2 (2,980 XP). Leaderboard resets Monday at midnight.

**Emotional arc**: The weekly review is the reflective moment. It is honest ("meals was the weak link") but constructive ("here's exactly what to fix"). The AI insights connect dots Nicola would not see on his own (Monday sleep -> Tuesday recovery). It sets up next week with concrete expectations.

---

## Journey 11: PR Day at the Gym

**Context**: Thursday. Leg Day. Nicola feels strong. Recovery: 88% (green). The stars align for a PR on squat.

### During Workout -- Squat Set 4

**Training -- Active Workout View**:
- Exercise: BARBELL SQUAT. Prescription: 4 x 6 @ 120kg.
- Sets 1-3: 120kg x 6 completed. RPE: 7, 7, 8.
- Set 4: Nicola adjusts weight to 125kg using the +2.5 quick-add button twice. Taps reps stepper to 5.
- **Haptic**: `.medium` on each quick-add tap.
- Performs the set. Logs: 125kg x 5.
- Taps DONE.

**PR Detection** (runs immediately on DONE):
- New e1RM calculated: 125 x 5 = estimated 1RM of ~145kg.
- Previous best e1RM for squat: 140kg.
- **ALL-TIME 1RM PR DETECTED.**

**Celebration sequence**:
1. **Haptic**: `.success` x3 rapid pulses + 500ms delay + `.success` x2 (all-time 1RM pattern).
2. **Animation**: PR fireworks -- full-screen, 3000ms custom keyframe animation. Gold particles explode from center.
3. **Badge**: Gold "NEW ALL-TIME PR" badge pops in (scale 0->1.15->1.0, 400ms spring). `prGold` (#FFD700) shimmer.
4. **Text**: "ALL-TIME PR: Squat e1RM 145kg (+5kg)" flashes below exercise name.
5. **Sound**: (if earbuds) Faint celebration chime.

**Arena**:
- +75 XP (Personal Record). This is one of 3 allowed PR bonuses per day.
- Social feed: "Nicola just set a new squat PR: 145kg e1RM" posted to friends' feeds.
- Marco receives notification: "Nicola just hit a squat PR. Can you beat 145kg?"

**Workout Summary** (end of session):
- PR section highlighted: "NEW PR: Squat e1RM 145kg (+5kg)" with gold badge.
- Recovery compliance: "Green recovery day -- full volume executed with PR. Peak performance."

**Next morning's briefing** will include:
> "PR yesterday. That's what happens when you show up consistently and push hard. Don't ride that high into a lazy day."

**Emotional arc**: The PR celebration is the most intense dopamine moment in the app. Full-screen fireworks, rapid haptic bursts, gold everywhere. The social broadcast adds external validation. Nicola will screenshot this and send it to friends.

---

## Journey 12: Late Night Study

**Context**: Thursday 11:00 PM. Calculus II exam tomorrow (Friday). Nicola has studied 4h today (exam mode target: 4h -- already met) but wants to do one more review session. All non-negotiables are done.

### 11:00 PM -- Opens Accountability

**Lockdown Main View**:
- All cards: DONE (green). Leisure: UNLOCKED.
- Study card: "4h 12m total across 6 sessions". Status: "DONE".
- Action button changed to: "Add More" (outlined style, blue border).

Nicola taps "Add More". Navigated to Focus Timer View.

### 11:02 PM -- Starts Bonus Session

**Focus Timer View**:
- Session indicator: "Bonus Session" in `streak.gold` (all planned sessions already complete).
- Subject: "Calculus II" pre-selected.
- Selects "Long Focus" (50 min) to avoid going past midnight.
- Taps START.
- **Haptic**: `.heavy`.
- Ambient sound: selects "Rain" at 30% volume. Gentle rainfall fills earbuds.

**Recovery prescription (passive)**: Bedtime card earlier said "Target: 10:30 PM." Nicola is already past it. The system does not nag -- he is an adult. But the data is recorded: this late session will show as a sleep debt contributor tomorrow.

### 11:52 PM -- Session Complete

- Timer hits 0:00. **Sound**: completion chime. **Haptic**: `.success` + `.rigid`.
- "Session complete! Total today: 5h 02m"
- Focus Score: 85 (Good). Late-night sessions historically have lower focus.

**Arena**: +30 XP for the additional session. Study time scaling bonus: +10 XP (for the 5th hour beyond target). These are base -- multiplied by 1.75 = +70 XP.

**Dashboard**: MIND quadrant: "5h 02m" (well above the 4h exam mode target). Daily Score reflects the extra effort.

### 11:55 PM -- Recovery Bedtime Alert

**Bedtime reminder notification** (if configured):
> "It's past your target bedtime. Tomorrow is exam day. Put the phone down. Your brain consolidates what you studied during sleep. Go."

- **Sound**: `tempo_bedtime.caf` -- soft, low-frequency tone.

**Emotional arc**: The bonus session was Nicola's choice, not the system's demand. The app supported it without judgment (no "you should be sleeping" modal blocker). The bedtime reminder at the end is gentle but data-driven: sleep consolidates memory. The balance between supporting ambition and protecting health.

---

## Journey 13: Travel Day

**Context**: Friday. Nicola flies from Miami to New York for a family weekend. 3-hour flight. Timezone change: EST stays EST (same zone in this case). But the schedule is disrupted.

### 5:00 AM -- Unusually Early Wake-Up

Whoop detects sleep end at 4:45 AM (only 5.2h sleep). Recovery: 52% (yellow).

**Morning briefing fires at 5:05 AM** (5 min after Whoop sleep end):
> "5.2 hours of sleep. Recovery: 52%. Today's workout is lighter. Study and meals unchanged. Prioritize an early bedtime tonight."

### 6:00 AM -- Airport

Nicola opens Tempo. Dashboard shows yellow recovery, adjusted training (lighter Upper Body session, -20% volume).

**Accountability**: Nicola knows he is traveling. He long-presses the Training card -> context menu -> "Log Manually" -> does a bodyweight circuit in the airport gym (20 min). Marks training as complete manually. Badge changes to "MANUAL".

### 8:00 AM -- 11:00 AM -- In-Flight Study

No internet. Nicola opens Focus Timer for offline study.

**Offline behavior**: Timer works normally (local-only, no server dependency). Study time accumulates locally. NutriTrack sync will fail (no internet) -- meal logging uses manual check-off mode.

**Dashboard in offline mode**:
- Offline banner: "You're offline. Some data may be stale." in `tempo.offline.bg` / `tempo.offline.text`.
- Score ring: dashed stroke pattern (5pt dash, 3pt gap) rotating slowly clockwise (1 revolution/10s).
- BODY quadrant: cached Whoop data from morning. Yellow stale border appears after 30 min.
- FUEL quadrant: "Connect NutriTrack" message (sync failed). Manual meal logging available.
- MIND quadrant: updates in real-time (local data). "1h 30m / 2h".

### 11:30 AM -- Lands, Internet Restores

**Background refresh triggers**: Whoop sync, NutriTrack sync (if meals were logged in NutriTrack app separately), HealthKit catch-up.

- Offline banner disappears.
- Stale data indicators clear.
- Dashboard refreshes with animation.

### Evening -- Family Dinner

Nicola logs meals manually (NutriTrack may not have the restaurant food). Marks meals as complete via manual check-off.

**Accountability**: All 3 non-negotiables hit despite travel. Unlock fires.

**Emotional arc**: The app handled travel gracefully. Offline mode worked. No crash, no data loss. Study logged locally synced when internet returned. Manual fallbacks for meals and training covered the gaps. The system bent without breaking.

---

## Journey 14: Whoop Battery Dies

**Context**: Wednesday 2:00 PM. Nicola's Whoop band runs out of battery. The Body quadrant goes stale.

### 2:15 PM -- Stale Data Detected

**Dashboard**:
- BODY quadrant: data stops updating. After 30 min, a yellow 4pt dot appears next to "BODY" label. Timestamp: "Last sync: 32m ago" changes color from `tempo.text.tertiary` to `tempo.stale` (yellow).
- After 2 hours: timestamp pulses (opacity 0.5 -> 1.0, 2s cycle). "Last sync: 2h ago".
- Stale overlay: 1pt yellow border appears around the BODY card at 40% opacity.

**Recovery -- Recovery Today View**:
- Data from this morning is still displayed (recovery score, HRV, etc.) but with stale indicators.
- Prescription cards still show, but prefix: "Based on this morning's data (stale):"

**Training** (if workout not yet done):
- Recovery Badge Bar: "[sync] Stale -- tap to sync" in yellow.
- Adjustment label: unchanged from morning's data. If recovery was green at morning, training stays at full volume.
- If Nicola pulls to refresh: "Whoop data unavailable. Using last known recovery (82%, 6h ago)."

**Edge case**: If Whoop data is stale for 24h+, Training defaults to yellow (moderate) programming with a note: "No recovery data -- using moderate defaults."

**Accountability**: No impact. Non-negotiables do not depend on real-time Whoop data. The training card uses HealthKit as fallback for workout detection.

### 8:00 PM -- Nicola Charges Whoop

Whoop comes back online. Background sync fires. Data backfill happens for the gap period (strain, heart rate). Dashboard refreshes. Stale indicators clear. Strain bar updates with afternoon activity.

**Emotional arc**: The system degrades gracefully. No crashes, no broken screens. Stale indicators are honest ("here is old data, marked as old"). Fallback to HealthKit for step/workout data means the MOVE quadrant and training detection never broke. The user is not punished for hardware failure.

---

## Journey 15: Comeback After 2 Weeks Off

**Context**: Monday morning. Nicola has not opened Tempo in 14 days. Streak: broken (was 32 days). Last activity: two Mondays ago. Re-engagement sequence has been running.

### Day 3 of Absence -- Re-Engagement Notification

> "Your Tempo setup is ready. Pick up where you left off -- it takes 2 more minutes."

### Day 7 -- Second Re-Engagement

> "Your 32-day streak is gone, but your data isn't. When you're ready, Tempo is here."

### Day 14 (Today) -- Nicola Opens App

**Dashboard loads**:
- Score ring: animates to 0. "–" displayed (no data for today yet -- but Whoop data is fresh because band never stopped).
- Streak: 0 (displayed in `tempo.text.secondary`, not orange -- no fire icon).
- BODY: Recovery data populates from Whoop (it was collecting all along). Recovery: 78% (green).
- Non-Negotiables: fresh for today. 3 items, all at 0%.
- Insight banner: "Welcome back. Your body is ready (78% recovery). Let's rebuild."

**Morning briefing** (context-aware):
> "You've been gone. The streak is broken. The leaderboard moved on without you. But you're here now, and that's what matters. Push day. 2h study. 3 meals. Day 1 of the new streak starts now. Make it count."

- **Copy source**: `notif.morning.welcome_back`, Drill Sergeant intensity

**Arena**:
- XP was accumulating penalties during absence (capped at -150/day for first 3 days, then stopped -- penalty cap prevents catastrophic loss).
- Leaderboard position: dropped significantly. Marco is now #1 by a wide margin.
- Level: unchanged (XP doesn't decrease below level threshold).
- Streak: 0 days. Multiplier: 1.0x. Flame icon: grey, static.
- "Day 0" feels like rock bottom.

**Accountability -- Lockdown Main View**:
- Clean slate. Today's non-negotiables are fresh.
- No historical shame -- the past two weeks are visible in the calendar heatmap (14 red cells) but today is a blue-bordered "today" cell waiting to be filled.

### Throughout the Day -- Rebuilding

Nicola completes all non-negotiables. First day back: 100%.

**Celebration (context-aware)**:
> "You failed for 14 days. Today you didn't. THAT is the response. Day 1 of the new streak. 3/3. Keep this energy."

**Arena**: Streak counter: 1. Small flame icon appears (grey -> orange transition). Multiplier: 1.0x. But the XP from a full day starts rebuilding. +~450 XP (base, no multiplier bonus yet).

**Emotional arc**: The comeback is honest. The app does not pretend the absence did not happen (14 red cells on the calendar, broken streak, XP gap). But it does not punish beyond what has already happened. "Day 1 of the new streak starts now" is forward-looking. The system invites return; it does not shame.

---

## Journey 16: Multiple Exams Overlap

**Context**: Tuesday. Two exams in 3 days: Calculus II on Thursday, Organic Chemistry on Friday. Exam mode active for both.

### 7:00 AM -- Morning Briefing

> "Calculus II in 2 days. Organic Chemistry in 3. This is the final stretch. Training is at maintenance -- 3 sessions max this week. Study is the priority. 4h minimum. Zero room for slacking."

**Accountability -- Lockdown Main View**:
- Exam Mode banner: "[!] EXAM MODE ACTIVE -- Calculus II (2d) / Organic Chemistry (3d)"
- Study target: increased to 4h (double the normal 2h -- multiple exams compound the increase).
- PS5 time: 6:00 PM (moved 1.5h earlier for dual exam crunch).

### Study Session Management

**Focus Timer View** -- Subject switching:
- Session 1-2: "Calculus II" (90 min Deep Work blocks). 3h Calculus.
- Session 3: "Organic Chemistry" (50 min Long Focus). 50 min OrChem.
- Session 4: "Organic Chemistry" (50 min Long Focus). 1h 40m OrChem total.

**Study Analytics** (exam-linked planning):
- Calculus II countdown: "Total hours studied: 28h. Projected remaining: 6h. At your pace, you'll have 34h by exam day. On track." (Green verdict)
- Organic Chemistry countdown: "Total hours studied: 12h. Projected remaining: 5h. Tight -- increase to 3h/day starting now." (Amber verdict)

**Accountability prioritization**: The system weights notifications toward the weaker subject:
> "Organic Chemistry needs more time. You've put 28h into Calculus but only 12h into OrChem. Rebalance."

### Wednesday -- Day Before Calculus

Final Calculus review day. Study: 3h Calculus, 1.5h OrChem.

### Thursday Morning -- Exam Day (Calculus II)

**Morning briefing**:
> "Calculus II exam today. Everything you studied comes down to this. Light training only -- save your energy for your brain. Eat a solid breakfast. Hydrate. Walk in there knowing you did the work. Because you did. Now execute."

- **Copy source**: `notif.morning.exam_day`

**Accountability**: Study target reduced on exam day (focus shifts to the exam itself, not more cramming). Training: optional light session only.

### Friday Morning -- Exam Day (Organic Chemistry)

Same pattern. Modified briefing references OrChem specifically.

### Friday Evening -- Both Exams Done

Nicola marks both exams as complete in the exam system.

**Exam mode deactivates**: Banner disappears. Study target reverts to 2h. PS5 time returns to 7:30 PM. Notification intensity returns to user's configured level (Drill Sergeant).

**Celebration**: "Exam season survived. 2 exams, 38 total study hours. Time to breathe."

**Emotional arc**: The dual-exam system never panicked. It split attention based on preparation levels, adjusted the subject balance via notifications, and gave exam-day-specific briefings. The priority system prevented Nicola from over-preparing for one exam at the expense of the other.

---

## Journey 17: Social Shame

**Context**: Wednesday afternoon. Marco passes Nicola on the weekly leaderboard. Competitive response triggered.

### 2:15 PM -- Arena Push Notification

> **TEMPO** -- Arena
> "Marco just took your spot on the leaderboard. You're #2 now. 130 XP gap. That's one perfect day of difference. Push day. 2h study. 3 meals. Take it back."

- **Copy source**: `notif.morning.leaderboard_change` (adapted for mid-day context)

### 2:16 PM -- Nicola Opens Arena Tab

**Arena -- Arena Main View**:
- Leaderboard preview: "CROWN 1. Marco -- 2,450 XP LV18" (gold crown icon). "2. You -- 2,320 XP LV14" (blue highlight row).
- Gap text: "130 XP behind #1" in orange (#FF6B2C).
- The "2. You" row has a subtle red background tint (losing position).

Nicola taps "See All" -> **Leaderboard View**:
- Full weekly standings. Marco's row has a crown. Nicola's row: blue border, "130 XP behind" badge.
- Week progress timeline: shows when Marco pulled ahead (Tuesday evening, logged a late study session).

### 2:20 PM -- Competitive Response

Nicola immediately opens the study timer. Studies for 2 extra hours beyond his target. Logs all meals meticulously (protein target bonus: +30 XP). Goes to the gym for Push Day with extra intensity.

### Accountability notification at 5:00 PM (context-aware):

> "Marco: 100%. You: 85%. The leaderboard is watching. Are you going to let them win because you couldn't do 30 more minutes of studying?"

### By End of Day

Nicola's daily XP: ~780 (higher than average, driven by extra study sessions and meticulous meal logging). Gap narrows to 40 XP.

### Thursday -- Overtakes

Nicola outperforms Marco on Thursday. Takes back #1.

**Push to Nicola**:
> "You're back on top. #1 on the weekly leaderboard. 2,950 XP. Don't get comfortable -- Marco is 80 XP behind."

**Emotional arc**: The leaderboard position loss stung. The notification naming Marco specifically made it personal. The competitive response was real behavior change: more study, better nutrition tracking, harder gym session. This is the Strava effect -- you do not just train, you train knowing your friends will see it.

---

## Journey 18: Deload Week

**Context**: Monday. After 3 weeks of progressive overload, the system triggers a deload week. Nicola has been training hard; his HRV has been trending down for 5 days.

### Sunday Night -- Deload Trigger

**Training -- Progressive Overload Logic** detects:
- 3 consecutive weeks of volume increases.
- HRV declining 5 consecutive days (from 72ms to 58ms).
- Recovery averaging 55% (yellow, down from 75% average).

**System decision**: Trigger deload week. All training volume reduced 40%. All weights reduced 20%. No PRs expected.

**Haptic** (on decision): `.warning` + 300ms + `.light` (deload trigger haptic).

### Monday 7:00 AM -- Morning Briefing

> "HRV trending down for 5 days straight. Your body is sending a warning. Today: reduced volume. Extra hydration. Caffeine cutoff at 1 PM. Bed by 10. If you ignore this pattern, you'll end up injured or sick. I'm not being dramatic. Listen."

- **Copy source**: `notif.morning.hrv_declining`, Drill Sergeant intensity

### 7:30 AM -- Opens Training Tab

**Training -- Today's Workout View**:
- Title: "DELOAD -- PUSH" (in `deloadBlue` instead of white).
- Recovery Badge Bar: "[yellow dot] 55% Recovery * -40% Volume"
- Deload banner at top: "DELOAD WEEK -- Strategic recovery. Lighter weights, fewer sets." in `deloadBlue` background.
- All exercise cards: left accent bar in `deloadBlue`.
- Exercise cards show reduced prescriptions: Bench Press 3x8 @ 68kg (vs normal 4x8 @ 85kg). "-20% weight, -1 set" noted.
- START button: "START DELOAD SESSION" in `deloadBlue`.

### During Workout

- Set logging rows: target RPE noted as "Target RPE: 5-6 this week" in `deloadBlue`.
- DONE button: `deloadBlue` instead of primary red.
- No PR attempts. If Nicola tries to increase weight beyond deload prescription, a warning: "Deload week -- keep it light. Save your PRs for next week."

### Throughout the Week

- Training volume is 40% lower every day.
- Recovery prescription emphasizes sleep, nutrition, hydration.
- By Wednesday: HRV starts recovering (62ms, up from 58ms). Recovery: 65% (still yellow but trending up).
- By Friday: HRV: 68ms. Recovery: 74% (green).

### Following Monday -- Post-Deload

- HRV: 75ms (new personal high for 30-day window).
- Recovery: 85% (green).
- Training returns to full volume. Progressive overload resumes.
- Morning briefing: "Deload week paid off. Recovery at 85%. HRV at a 30-day high. Full volume is back. Time to push."

**Emotional arc**: The deload week feels counterintuitive -- Nicola wants to train hard. But the data (declining HRV, lower recovery) is undeniable. The blue visual treatment throughout the app makes deload feel intentional, not lazy. When HRV bounces back by Friday, the system proves it was right. The post-deload Monday feels like a fresh start with a fully charged body.

---

## Journey 19: Weekend Warrior

**Context**: Saturday. Nicola wants to sleep in, play football in the afternoon, go to the beach, see friends in the evening. Weekend mode active.

### 9:30 AM -- Weekend Morning Briefing

Morning briefing shifted to 9:30 AM (weekend setting).

> "Weekend doesn't mean day off. Recovery is 76% -- solid enough for training. Study target stays at 1h. I don't care if your friends are at brunch. Hit your numbers first, then enjoy your Saturday."

- **Copy source**: `notif.morning.weekend`, Drill Sergeant intensity

**Accountability -- Lockdown Main View**:
- Study card: "0h 00m / 1h" (weekend target, reduced from 2h). "Weekend target" indicator in `caption2`.
- Training card: "NOT STARTED".
- Meals card: "0 / 3".
- PS5 time: 9:00 PM (weekend extended from 7:30 PM).
- Countdown: "11h 30m until your usual PS5 time."

### 10:00 AM -- Quick Study Session

One 50-minute Long Focus session. Subject: Organic Chemistry review. Target hit by 10:50 AM.

### 11:30 AM -- Gym Session

Quick 45-minute Push session. Logged via Whoop/HealthKit. Training card: DONE.

### 12:30 PM -- Brunch (Meal 1)

Logs in NutriTrack. Meals: 1/3.

### 2:00 PM -- Tier 1 Check: Suppressed

Completion: 67% (2/3 done). Only meals remaining. < 50% condition not met. No notification fires.

### 3:00 PM -- Football Match

90-minute match. Whoop tracks strain. HealthKit logs workout.

### 5:00 PM -- Beach / Friends

Nicola logs a quick meal (snack/light dinner) at the beach. Meals: 2/3.

### 7:30 PM -- Dinner with Friends

Third meal logged. Meals: 3/3.

### 7:30 PM -- ALL COMPLETE

Unlock fires. PS5 time is 9:00 PM but all tasks done 1.5 hours early.

**Celebration**:
> "UNLOCKED at 7:30 PM. 1h 30m before PS5 time. Efficient. 33-day streak extended."

**Arena**: Normal XP accumulation. Football match contributes to step count (15K+ steps) for top-tier step XP.

**Emotional arc**: The weekend felt free. Study was 1h (not 2h). PS5 time was 9:00 PM (not 7:30 PM). The adjusted targets respected the weekend rhythm. Nicola hit everything by 7:30 PM and spent the evening guilt-free with friends. The system flexed without breaking.

---

## Journey 20: End of Semester Celebration

**Context**: Friday. Last final exam just completed. Semester is over. Nicola has been on Tempo for 4 months. Streak: 87 days.

### 11:00 AM -- Marks Last Exam as Complete

In Accountability settings, marks the Organic Chemistry exam as complete. No more exams in the system.

**Exam Mode deactivates**: Banner disappears. Study target reverts to 2h (or user can adjust). PS5 time returns to normal. Notification intensity returns to configured level.

**System generates Semester Review** (triggered by last exam completion + no future exams):

### 12:00 PM -- Semester Review Push

> **TEMPO** -- Semester Review
> "Semester complete. 4 months. 87-day streak. Here's your report."

### Opens Dashboard -- Special Semester Review View

**Hero stats**:
| Metric | Value |
|--------|-------|
| Days on Tempo | 122 |
| Current Streak | 87 days |
| Longest Streak | 87 days (current!) |
| Total Study Hours | 312h |
| Total Workouts | 98 |
| Total Meals Logged | 348 |
| Personal Records | 14 |
| Perfect Days | 78 |
| Perfect Weeks | 9 |

**Academic summary**:
- Calculus II: 142h studied across 4 months. 68 sessions. Avg Focus Score: 84.
- Organic Chemistry: 98h studied. 52 sessions. Avg Focus Score: 79.
- Peak study week: Week 14 (exam week) -- 28.5h.
- Study consistency: 89% of days met target.

**Training summary**:
- 98 workouts in 122 days (80% training compliance).
- 14 PRs set. Key PRs: Bench 107.5kg e1RM, Squat 145kg e1RM, Deadlift 180kg e1RM.
- Deload weeks: 3 (all recovery-triggered, all followed by PR weeks).
- Football matches: 16.

**Recovery summary**:
- Average recovery: 71% (green zone majority).
- HRV trend: started at 58ms, current 30-day avg: 72ms (+24% improvement).
- Average sleep: 7.1h. Best month: March (7.4h avg).

**Arena summary**:
- Level: 28 (Captain). Started at Level 1.
- Total XP: 13,069.
- Challenges won: 8 out of 12.
- Weekly leaderboard #1: 9 weeks.

**AI reflection (Claude-powered)**:
> "You arrived 4 months ago managing your life in 5 different apps. Today you have an 87-day streak, 14 PRs, and 312 hours of focused study. Your HRV improved 24% -- your body is measurably healthier. Your study consistency at 89% put you in the top percentile of Tempo users. The pattern that defined your semester: Monday mornings are your superpower (avg score 94). Friday evenings are your weakness (avg 71). Next semester, protect Friday evenings and you'll be unstoppable."

**Share card**: Generates a shareable image (1080x1350px):
- Tempo branding
- 87-day streak with blue flame
- Key stats (study hours, workouts, PRs)
- "Tracked with Tempo" watermark

**Emotional arc**: This is the payoff. Four months of data, distilled into a single view that proves the system worked. The numbers are undeniable: 312 study hours, 14 PRs, 24% HRV improvement. The AI reflection connects the dots in a way that feels like having a coach review game tape. The share card goes to Instagram. The semester review is the proof that Tempo is not just an app -- it is a life operating system that delivered results.

---

## Cross-Module Data Flow Summary

Every journey above demonstrates that no module operates in isolation. Here is the unified data flow map:

```
Whoop API ──────────────┐
                        v
              ┌─── RecoverIQ ───┐
              │   (Recovery)     │
              │                  │
              │   recovery_score─┼──> RepForge (workout adjustment)
              │   hrv_rmssd     │──> LifeOS Dashboard (BODY quadrant)
              │   sleep_hours   │──> Lockdown (notification copy)
              │   prescriptions │──> All modules (bedtime, caffeine, hydration)
              └─────────────────┘
                        │
NutriTrack API ─────────┤
              │         v
              │  ┌─── LifeOS ──────┐
              │  │  (Dashboard)     │
              │  │                  │
              │  │  daily_score ───┼──> ClutchTime (XP calculation context)
              │  │  quadrant_data  │──> All views (unified state)
              │  └─────────────────┘
              │         │
              v         v
         ┌─── Lockdown ────────┐
         │  (Accountability)    │
         │                      │
         │  completion_%  ─────┼──> ClutchTime (Perfect Day XP)
         │  streak_days  ─────┼──> ClutchTime (multiplier calculation)
         │  study_minutes ────┼──> LifeOS (MIND quadrant)
         │  focus_score  ─────┼──> Notifications (copy personalization)
         │  non_neg_status ───┼──> Notifications (tier triggering)
         └──────────────────────┘
                        │
HealthKit ──────────────┤
              │         v
              │  ┌─── RepForge ────┐
              │  │  (Training)      │
              │  │                  │
              │  │  workout_data ──┼──> Lockdown (training card auto-complete)
              │  │  PR_records ───┼──> ClutchTime (PR XP)
              │  │  strain_est ───┼──> RecoverIQ (strain detail view)
              │  └─────────────────┘
              │         │
              v         v
         ┌─── ClutchTime ─────┐
         │  (Arena)             │
         │                      │
         │  XP_total ──────────┼──> Notifications (leaderboard copy)
         │  streak_multiplier ─┼──> All XP calculations
         │  challenge_status ──┼──> Notifications (competitive copy)
         │  friend_activity ───┼──> Notifications (social proof copy)
         └──────────────────────┘
```

Every notification references data from multiple modules. Every screen transition moves data between modules. Every celebration considers the full picture. This is one system, not five features.
