# Tempo -- Onboarding & Notification System Specification

> The complete specification for user onboarding, push notification strategy, and retention mechanics.
> This document is the authoritative reference for all onboarding screens and every notification the app sends.

---

## Table of Contents

- [Part 1: Onboarding Flow](#part-1-onboarding-flow)
  - [Pre-Onboarding](#pre-onboarding)
  - [Step-by-Step Onboarding](#step-by-step-onboarding)
  - [Onboarding UX Details](#onboarding-ux-details)
  - [Onboarding Funnel Optimization](#onboarding-funnel-optimization)
  - [Re-Onboarding](#re-onboarding)
- [Part 2: Notification System](#part-2-notification-system)
  - [Notification Architecture](#notification-architecture)
  - [Push Notification Infrastructure](#push-notification-infrastructure)
  - [Notification Channels — Full Copy Bank (All 4 Intensities)](#notification-channels)
  - [Notification Timing Engine](#notification-timing-engine)
  - [Notification Settings Deep Dive](#notification-settings-deep-dive)
  - [Notification Smart Logic](#notification-smart-logic)
  - [Re-Engagement Sequences](#re-engagement-sequences)
  - [First Week Experience — Hour by Hour](#first-week-experience)
  - [Localization Preparation](#localization-preparation)

---

# PART 1: ONBOARDING FLOW

## Pre-Onboarding

### App Store Listing

**App Name:** Tempo

**Subtitle (30 chars max):** Your Life Operating System

**Keywords (100 chars max):**
`fitness,accountability,whoop,recovery,study,workout,nutrition,habits,discipline,college,athlete`

**Description (4000 chars max):**

> **Stop wasting your potential.**
>
> You train. You study. You try to eat right. But every evening, you end up on the couch wondering where the time went. Tempo fixes that.
>
> Tempo is a life operating system for student-athletes who refuse to be average. It connects your training, nutrition, recovery, academics, and daily habits into one system -- and holds you accountable with a drill-sergeant that never takes a day off.
>
> **HOW IT WORKS**
>
> Set your daily non-negotiables: study hours, meals, training. Tempo tracks them automatically through Whoop, Apple Health, and NutriTrack. Complete everything? You've earned your evening. Miss something? Tempo won't let you forget.
>
> **FIVE MODULES, ONE SYSTEM**
>
> DASHBOARD -- See your entire life at a glance. Recovery score, nutrition, study progress, and training -- all in one view.
>
> TRAINING (RepForge) -- AI workout programming that adapts to your recovery. Never program heavy legs before football again. Progressive overload tracked automatically.
>
> ACCOUNTABILITY (Lockdown) -- Daily non-negotiables with escalating reminders. PS5 time is earned, not default. Your drill sergeant gets louder as the evening approaches.
>
> RECOVERY (RecoverIQ) -- Whoop-powered daily prescriptions. Training intensity, meal timing, bedtime, caffeine cutoff -- all calculated from your biometrics.
>
> ARENA (ClutchTime) -- Compete with friends on weekly leaderboards. Earn XP for hitting targets. Lose XP for slacking. Challenge your training partners to study-hour battles.
>
> **INTEGRATIONS**
>
> - Whoop: Recovery, sleep, strain, HRV
> - Apple Health: Steps, workouts, heart rate
> - NutriTrack: Meals, macros, meal timing
> - Apple Calendar: Class schedule, exams, football practice
>
> **WHO THIS IS FOR**
>
> University students who are athletes. People who have the ambition but struggle with the execution. If you want a coach who tells you what you want to hear, this isn't it. If you want a coach who tells you what you need to hear -- welcome to Tempo.
>
> No subscriptions. No ads. Just results.

**Screenshot Strategy (6.7" iPhone 15 Pro Max, 6 screenshots):**

| # | Screen | Caption | Content |
|---|--------|---------|---------|
| 1 | Dashboard | "Your entire life. One screen." | 4-quadrant dashboard with recovery 78%, macros at 60%, 1.5h study logged, workout completed |
| 2 | Lockdown | "PS5 is earned, not default." | Non-negotiables view with 3/4 complete, progress bars, escalation timer visible |
| 3 | Training | "Your AI coach adapts to your recovery." | Today's workout with recovery badge showing green, exercise list with sets/reps/weight |
| 4 | Recovery | "Know exactly how hard to push." | Recovery score ring at 84% green, daily prescription cards (training rec, bedtime, caffeine cutoff) |
| 5 | Arena | "Compete with your friends." | Leaderboard with 5 friends, XP scores, active challenge card |
| 6 | Notifications | "A drill sergeant in your pocket." | Stylized notification stack showing escalating messages from gentle to aggressive |

**App Store Category:** Primary: Health & Fitness. Secondary: Productivity.

**Age Rating:** 4+ (no objectionable content).

**Privacy Nutrition Labels:**
- Data Used to Track You: None
- Data Linked to You: Health & Fitness (HealthKit), Identifiers (Apple ID)
- Data Not Linked to You: Usage Data, Diagnostics

---

### First Launch: Splash Screen Animation

**Minimum iOS Version:** iOS 17.4

Rationale: SwiftData requires iOS 17. Swift 6 strict concurrency features target iOS 17+. The Observable macro is iOS 17+. This also covers iPhone XS and later, which represents >95% of active iPhones as of 2026.

**Splash Animation Sequence (1.8 seconds total):**

1. **0.0s -- 0.3s:** Black screen. The word `TEMPO` fades in, centered, in a heavy sans-serif (SF Pro Display Black, 48pt), tracking +6pt. White text on black.
2. **0.3s -- 0.8s:** A thin horizontal line expands from center outward beneath the wordmark, left-to-right reveal, white.
3. **0.8s -- 1.2s:** Beneath the line, the tagline "YOUR LIFE OPERATING SYSTEM" fades in (SF Pro Text Medium, 14pt, tracking +4pt, 60% white opacity).
4. **1.2s -- 1.8s:** Everything holds for 0.3s, then the entire composition scales up slightly (1.0x to 1.05x) and fades to the first onboarding screen.

**Implementation:** Use SwiftUI `withAnimation` and `TimelineView` or chained `.animation` modifiers. No Lottie dependency -- pure SwiftUI.

**If user has already onboarded:** Skip splash entirely. Launch directly to Dashboard with a 0.3s fade-in.

---

## Step-by-Step Onboarding

### Global Onboarding UX Rules

- **Progress indicator:** A segmented progress bar at the top of every screen. 13 segments (one per step -- updated from 12 to include the mandatory AI consent step per Guideline 5.1.2(i)). Filled segments use white, unfilled use 20% white. The bar is thin (3pt height) and spans the full width minus 32pt horizontal padding.
- **Navigation:** Every step has a back button (chevron.left) in the top-left corner EXCEPT Step 1. No "skip" on mandatory steps. Optional steps have a "Skip for now" text button in the bottom area.
- **Transitions:** Horizontal slide (push/pop), 0.35s ease-in-out. Back goes right-to-left, forward goes left-to-right. Standard iOS navigation pattern.
- **Data persistence:** All onboarding data is written to a local `OnboardingState` object (persisted to UserDefaults as JSON) after EACH step. If the user kills the app, they resume at the last completed step + 1.
- **Color scheme:** Dark mode only during onboarding. Background: `tempo.color.bg.primary` dark (#0D0D0D). Primary text: `tempo.color.text.primary` dark (#F5F2ED). Secondary text: 60% white. Accent: `tempo.color.accent.amber` (#F59E0B). Cards/inputs: 10% white background with 1pt 15% white border.
- **Typography:** SF Pro Display for headlines, SF Pro Text for body. No custom fonts.
- **Accessibility:** All screens support Dynamic Type (up to AX5). VoiceOver labels on all interactive elements. Minimum touch target 44x44pt. No information conveyed solely by color.

---

### Step 1: Welcome / Value Prop

**Purpose:** Emotional hook. Make the user feel seen. This screen must answer: "Is this app for me?"

**Screen Layout:**
```
┌──────────────────────────────┐
│ [progress bar: 1/12]         │
│                              │
│                              │
│         (animation)          │
│     4 rings converging       │
│     into 1 unified ring      │
│                              │
│                              │
│    STOP MANAGING YOUR LIFE   │
│      IN 5 DIFFERENT APPS.    │
│                              │
│   Training. Nutrition.       │
│   Recovery. Academics.       │
│   One system. One score.     │
│   Zero excuses.              │
│                              │
│                              │
│                              │
│                              │
│  ┌──────────────────────┐    │
│  │     GET STARTED       │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS."
- Font: SF Pro Display Black, 28pt
- Alignment: Center
- Color: White

**Subtext:**
"Training. Nutrition. Recovery. Academics. One system. One score. Zero excuses."
- Font: SF Pro Text Regular, 17pt
- Alignment: Center
- Color: 70% white
- Line height: 1.4x

**Animation:** Four thin concentric rings (representing fitness, nutrition, recovery, academics) start separated and drift toward center, merging into a single unified ring that pulses once with the amber accent color. Looping, subtle. Built with SwiftUI Canvas or custom Shape animations.

**CTA Button:** "GET STARTED"
- Full width minus 32pt horizontal padding
- Height: 56pt
- Background: Amber (#F59E0B)
- Text: Black, SF Pro Text Semibold, 17pt
- Corner radius: 14pt
- Haptic: light impact on tap

**Skip option:** None. This is the entry point.

**What makes the user want to continue:** The headline calls out their exact pain (fragmented apps). The subtext promises unification. The animation visually demonstrates convergence. The tone is confident and direct -- not corporate, not playful.

---

### Step 2: Sign in with Apple

**Purpose:** Create the user account. Required for Arena (social features) and backend sync.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 2/12]     │
│                              │
│                              │
│         (Tempo logo)         │
│                              │
│                              │
│     YOUR IDENTITY STAYS      │
│          YOURS.              │
│                              │
│   Tempo uses Sign in with    │
│   Apple. We never see your   │
│   password. We never sell     │
│   your data. Period.         │
│                              │
│                              │
│                              │
│                              │
│  ┌──────────────────────┐    │
│  │  Sign in with Apple   │    │
│  └──────────────────────┘    │
│                              │
│   Why is sign-in required?   │
│                              │
└──────────────────────────────┘
```

**Headline:** "YOUR IDENTITY STAYS YOURS."
- Font: SF Pro Display Bold, 26pt
- Center aligned, white

**Subtext:**
"Tempo uses Sign in with Apple. We never see your password. We never sell your data. Period."
- Font: SF Pro Text Regular, 16pt
- Center aligned, 70% white

**Button:** Standard Apple `SignInWithAppleButton` (`.signIn` style, `.white` scheme).
- Placement: centered, full width minus 32pt padding
- Height: 50pt (Apple's minimum)

**"Why is sign-in required?" link:**
- Font: SF Pro Text Regular, 14pt, amber color, underlined
- Tapping shows a bottom sheet:
  - Title: "Why we need an account"
  - Body: "Your account powers: (1) Arena -- compete with friends on leaderboards, (2) Cloud sync -- your data backed up securely, (3) Multi-device -- use Tempo on iPhone and iPad. Your Apple ID email is private by default. We store a unique identifier, your display name, and your Tempo data. Nothing else."
  - "Got it" dismiss button

**What happens if user cancels the Apple sign-in dialog:**
- The app remains on this screen. No error shown -- the Apple dialog simply dismisses.
- If the user taps "Sign in with Apple" again, the dialog re-appears.
- If the user taps back, they return to Step 1.
- After 2 cancellations, show a subtle hint below the button: "Sign-in is required to use Tempo. Your data stays private with Apple's relay system."

**User data collected:**
- `userIdentifier` (stable Apple ID token) -- ALWAYS provided
- `fullName` (given name + family name) -- provided on FIRST sign-in only, may be nil if user hides it
- `email` -- may be a relay address if user chose "Hide My Email"

**Guest mode:** No. Sign-in is mandatory. Rationale: Arena (leaderboards, challenges, friend system) is a core feature that requires a persistent identity. The backend stores Whoop OAuth tokens per user. A guest mode would create a second code path for every feature and degrade the social experience.

**Error states:**
- Network error during Apple sign-in: "Connection failed. Check your internet and try again." with a "Retry" button.
- Backend error during account creation: "Something went wrong on our end. Try again in a moment." with a "Retry" button.
- Apple ID already linked to another Tempo account (edge case): "This Apple ID is already linked to a Tempo account. You'll be signed into that account." -- proceed to Dashboard if onboarding was already completed, or resume onboarding where they left off.

---

### Step 3: Profile Setup

**Purpose:** Create the user's identity. Display name only -- username is deferred until Arena is first accessed (users who never use social features don't need a username, and username selection is a known friction point that causes onboarding drop-off).

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 3/12]     │
│                              │
│     WHO ARE YOU, SOLDIER?    │
│                              │
│        ┌─────────┐           │
│        │  photo   │           │
│        │  circle  │           │
│        │   +tap   │           │
│        └─────────┘           │
│                              │
│   Display Name               │
│   ┌────────────────────┐     │
│   │ (pre-filled from   │     │
│   │  Apple ID)         │     │
│   └────────────────────┘     │
│                              │
│  ┌──────────────────────┐    │
│  │       CONTINUE        │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "WHO ARE YOU, SOLDIER?"
- Font: SF Pro Display Bold, 26pt
- Center aligned, white

**Profile Photo:**
- Circular, 100pt diameter, centered
- Default state: dark gray circle with a camera.fill SF Symbol in 40% white
- Tapping opens an action sheet: "Take Photo" / "Choose from Library" / "Cancel"
- Uses PHPickerViewController (iOS 16+), no full photo library permission needed
- After selection: image is cropped to square, displayed in circle with a thin amber border
- Photo is optional -- user can proceed without one
- Max upload size: 512x512px, JPEG, compressed to <200KB

**Display Name field:**
- Label: "Display Name" in 14pt, 60% white, above the field
- Pre-filled with the name from Apple ID (if provided)
- If Apple ID name was hidden: field is empty, placeholder "Your name"
- Text field style: 10% white background, 1pt 15% white border, 14pt corner radius, 48pt height
- Font: SF Pro Text Regular, 17pt, white
- Validation: 2-30 characters, no leading/trailing whitespace, allows Unicode (accented names)
- Required field

**Username: DEFERRED to first Arena access.**
- A username is auto-generated on the backend from the display name (e.g., "Nicola Debbia" -> `nicola.debbia` or `nicola_debbia`, whichever is available). Stored silently.
- When the user first opens the Arena tab, a bottom sheet prompts: "Choose your Arena username" with the auto-generated suggestion pre-filled and editable.
- Username validation rules (applied at Arena first-access):
  - 3-20 characters, lowercase letters, numbers, underscores, periods only
  - Must start with a letter, no consecutive periods or underscores
  - Regex: `^[a-z][a-z0-9._]{2,19}$` (with no `..` or `__`)
  - Real-time availability check (debounced 500ms)
- Users who never open Arena never need to deal with username selection.

**Timezone:**
- Not shown on screen -- auto-detected from `TimeZone.current.identifier`
- Stored in user profile
- Used for notification scheduling

**Continue button:**
- Disabled (50% opacity) until Display Name is valid
- Enabled state: amber background, black text
- On tap: creates user profile on backend, uploads photo if present

**Error states:**
- Network error: "Couldn't save your profile. Check your connection and try again."
- Photo upload failure: Profile is created without photo, toast notification "Photo upload failed -- you can add it later in Settings."

---

### Step 4: Life Setup -- Training

**Purpose:** Configure the training module. This data feeds RepForge's workout programming engine.

**Screen Layout:** This step is a scrollable card-based form. Each question is a card with a question and selectable options.

```
┌──────────────────────────────┐
│ [<] [progress bar: 4/12]     │
│                              │
│     LET'S BUILD YOUR         │
│     TRAINING PROFILE.        │
│                              │
│  ┌────────────────────────┐  │
│  │ Do you train?          │  │
│  │  [YES]  [NO]           │  │
│  └────────────────────────┘  │
│                              │
│  (if YES, remaining cards    │
│   animate in from below)     │
│                              │
│  ┌────────────────────────┐  │
│  │ What do you do?        │  │
│  │  [Gym] [Running]       │  │
│  │  [Team Sport] [Other]  │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ How many days/week?    │  │
│  │  [3] [4] [5] [6] [7]  │  │
│  └────────────────────────┘  │
│  ...more cards...            │
│                              │
│  ┌──────────────────────┐    │
│  │       CONTINUE        │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "LET'S BUILD YOUR TRAINING PROFILE."
- Font: SF Pro Display Bold, 24pt, white

**Question 1: "Do you train?"**
- Two large toggle buttons: YES / NO
- Pill-shaped, side by side, 50% width each
- Selected state: amber background, black text, SF Pro Text Semibold
- Unselected: 10% white background, 60% white text
- If NO: skip to "Weight unit preference" only, then proceed to Step 5. Show a small note: "No worries. You can set up training later."
- If YES: remaining cards animate in with a staggered slide-up (0.1s delay between each card)

**Question 2: "What do you do?" (multi-select)**
- Chip-style buttons in a flow layout
- Options: Gym, Running, Team Sport, Other
- Multi-select allowed (a gym-goer who also plays football selects both)
- If "Team Sport" is selected: expand an inline sub-question "Which sport?" with common options: Football (Soccer), Basketball, Rugby, Volleyball, Other (text input)
- If "Team Sport" is selected: another sub-question "Which days do you play/practice?" with day-of-week toggle (Mon-Sun), multi-select

**Question 3: "How many days per week do you train?"**
- Horizontal row of circular buttons: 1, 2, 3, 4, 5, 6, 7
- Single select
- Default highlight: none (must choose)

**Question 4: "Preferred split?" (shown only if Gym is selected)**
- Options: PPL (Push/Pull/Legs), Upper/Lower, Full Body, Bro Split, I Don't Know
- Single select, pill buttons
- "I Don't Know" triggers a tooltip: "We'll start you with Push/Pull/Legs -- the best split for building muscle and fitting around team sports."

**Question 5: "Experience level"**
- Three large cards, vertically stacked:
  - **Beginner** -- "Less than 1 year of consistent training"
  - **Intermediate** -- "1-3 years, comfortable with compound lifts"
  - **Advanced** -- "3+ years, tracking progressive overload"
- Single select, card highlights with amber left border when selected

**Question 6: "Preferred workout duration"**
- Segmented control: 30 min / 45 min / 60 min / 75 min / 90 min
- Default: 60 min highlighted

**Question 7: "Equipment available"**
- Options: Full Gym, Home Gym, Bodyweight Only
- Single select, pill buttons
- If "Home Gym": expand inline checkboxes: Dumbbells, Barbell + Rack, Pull-up Bar, Bench, Resistance Bands, Cable Machine

**Question 8: "Weight unit"**
- Two toggle buttons: kg / lbs
- Auto-detect: default to kg if locale is metric, lbs if locale is imperial
- Always shown (even if user said they don't train -- needed for body weight display)

**Validation:** "Do you train?" must be answered. If YES, questions 2, 3, 5, and 8 are required. Questions 4, 6, 7 have defaults if not explicitly chosen.

**Continue button:** Enabled when all required questions are answered.

---

### Step 5: Life Setup -- Academics

**Purpose:** Configure the accountability and scheduling systems for academic life.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 5/12]     │
│                              │
│     NOW THE HARD PART.       │
│     YOUR BRAIN.              │
│                              │
│  ┌────────────────────────┐  │
│  │ Are you a student?     │  │
│  │  [YES]  [NO]           │  │
│  └────────────────────────┘  │
│                              │
│  (if YES, expand)            │
│                              │
│  ┌────────────────────────┐  │
│  │ School (optional)      │  │
│  │ ┌──────────────────┐   │  │
│  │ │                  │   │  │
│  │ └──────────────────┘   │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Your courses           │  │
│  │  + Add a course        │  │
│  │  [Anatomy] [x]         │  │
│  │  [Biochem] [x]         │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Upcoming exams         │  │
│  │  + Add an exam         │  │
│  │  [Anatomy - Jun 12] [x]│  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Daily study goal       │  │
│  │  [1h] [1.5h] [2h]     │  │
│  │  [2.5h] [3h] [4h+]    │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Import your calendar?  │  │
│  │  [Import Calendar]     │  │
│  │  Classes, exams, and   │  │
│  │  practice auto-detected│  │
│  └────────────────────────┘  │
│                              │
│  ┌──────────────────────┐    │
│  │       CONTINUE        │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "NOW THE HARD PART. YOUR BRAIN."
- Font: SF Pro Display Bold, 24pt, white

**Question 1: "Are you a student?"**
- YES / NO toggle (same style as training)
- If NO: show a small note "Got it. You can still set study goals or learning targets in Settings." Then skip to Step 6.
- If YES: remaining cards animate in

**School Name (optional):**
- Free text input field
- Placeholder: "University name"
- Optional -- no validation beyond max 100 chars
- Purpose: future feature (school-specific leaderboards), and personalization

**Courses:**
- "Add a course" button (+ icon, amber text)
- Tapping opens an inline text field. User types course name, presses return to add.
- Each course appears as a removable chip (course name + X button)
- Can add up to 12 courses
- Minimum: 0 (optional, but encouraged)
- Courses are used to label study sessions and associate exams

**Upcoming Exams:**
- "Add an exam" button (+ icon, amber text)
- Tapping opens an inline form:
  - Course selector (dropdown of added courses, or free text)
  - Date picker (minimum: today, default: 2 weeks from now)
- Each exam appears as a card: "[Course] -- [Date]" with X to remove
- Exams power countdown notifications and study priority

**Daily Study Goal:**
- Segmented selector: 1h, 1.5h, 2h, 2.5h, 3h, 4h+
- If "4h+" selected: show a numeric stepper (4.0 to 8.0 in 0.5h increments)
- Default: 2h highlighted
- This becomes the study non-negotiable target

**Calendar Import:**
- Card with "Import Calendar" button
- Subtext: "Tempo reads your class schedule, exams, and practice times to plan your day. No events are modified."
- Tapping triggers EventKit authorization request (`EKAuthorizationStatus`)
- If authorized: show confirmation "Calendar connected" with green checkmark, and list detected calendars with toggles (user can choose which calendars to sync)
- If denied: show "You can connect your calendar later in Settings. Tempo works without it, but scheduling will be more accurate with it."
- If the system dialog hasn't appeared yet: triggers `EKEventStore.requestFullAccessToEvents()`

**Validation:** "Are you a student?" must be answered. If YES, daily study goal must be selected. Everything else is optional.

---

### Step 6: Life Setup -- Goals

**Purpose:** Define daily non-negotiables and personalization data that powers the accountability engine and notification content.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 6/12]     │
│                              │
│     WHAT ARE YOU              │
│     FIGHTING FOR?            │
│                              │
│  ┌────────────────────────┐  │
│  │ Primary goal            │  │
│  │ [Build Muscle]          │  │
│  │ [Lose Fat]              │  │
│  │ [Improve Performance]   │  │
│  │ [Stay Healthy]          │  │
│  │ [All-Around]            │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ YOUR NON-NEGOTIABLES    │  │
│  │ These are daily. No     │  │
│  │ exceptions.             │  │
│  │                         │  │
│  │ [x] Train        [edit] │  │
│  │ [x] Study 2h     [edit] │  │
│  │ [x] Eat 3 meals  [edit] │  │
│  │ [ ] ............  [add] │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ What's your biggest     │  │
│  │ time-waster?            │  │
│  │ [PS5/Gaming]            │  │
│  │ [Social Media]          │  │
│  │ [Netflix/Streaming]     │  │
│  │ [YouTube]               │  │
│  │ [Other: ________ ]      │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ When does your evening  │  │
│  │ usually start?          │  │
│  │                         │  │
│  │   ┌──── 7:30 PM ────┐  │  │
│  │   │   (time picker)  │  │  │
│  │   └─────────────────┘  │  │
│  │                         │  │
│  │ This is when the drill  │  │
│  │ sergeant gets serious.  │  │
│  └────────────────────────┘  │
│                              │
│  ┌──────────────────────┐    │
│  │       CONTINUE        │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "WHAT ARE YOU FIGHTING FOR?"
- Font: SF Pro Display Bold, 24pt, white

**Primary Goal:**
- Single select, vertically stacked option cards
- Each option is a rounded rectangle, full width, 52pt height
- Selected: amber left border (4pt), white text, 15% white background
- Unselected: 10% white background, 60% white text
- Options:
  - **Build Muscle** -- "Gain size and strength"
  - **Lose Fat** -- "Cut weight, keep muscle"
  - **Improve Performance** -- "Sport-specific, endurance, speed"
  - **Stay Healthy** -- "Maintain fitness, feel good"
  - **All-Around** -- "A bit of everything"
- This selection affects: training programming priorities, recovery prescription emphasis, and notification copy

**Daily Non-Negotiables:**
- Pre-filled based on previous answers:
  - If user trains: "Train" (auto-tracked via Whoop/HealthKit)
  - If user is a student: "Study [X]h" (X = their daily study goal from Step 5)
  - If NutriTrack will be connected: "Eat [3] meals" (default 3, editable)
- Each non-negotiable is a row with:
  - Checkbox (pre-checked for suggested items)
  - Name
  - Edit button (pencil icon) to modify target value
  - Integration badge (auto-tracked icon if linked to Whoop/NutriTrack/HealthKit)
- "Add custom" button at the bottom:
  - Opens inline form: Name (free text, max 30 chars) + Target type (count, minutes, yes/no) + Target value
  - Examples of custom: "Read 30 min", "Drink 3L water", "No junk food", "Journal"
- Max 8 non-negotiables (UX research: more than 8 daily tasks causes overwhelm and abandonment)
- Minimum: 1 non-negotiable required

**Time-Waster:**
- Single select (multi-select allowed -- many people have multiple)
- Options: PS5/Gaming, Social Media, Netflix/Streaming, YouTube, Other (free text, max 40 chars)
- This data is used in notification copy: "Put down the controller" vs. "Close TikTok" vs. "Stop scrolling Netflix"
- At least one must be selected
- Subtext below: "No judgment. Knowing your weakness is the first step to controlling it."

**Evening Start Time:**
- Compact time picker (wheels or inline)
- Default: 7:30 PM
- Range: 5:00 PM to 11:00 PM in 15-minute increments
- This time is used to:
  - Schedule the "final warning" notification (30 min before this time)
  - Calculate when leisure is "unlocked" vs "locked"
  - Set the urgency escalation timeline
- Subtext: "This is when the drill sergeant gets serious. All non-negotiables should be done before this time."

**Validation:** Primary goal required. At least 1 non-negotiable. Time-waster required. Evening time has a default so it's always valid.

---

### Step 7: Connect Whoop

**Purpose:** Link the Whoop wearable for recovery, sleep, strain, and HRV data.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 7/12]     │
│                              │
│     YOUR BODY TALKS.         │
│     LET'S LISTEN.            │
│                              │
│       (Whoop band image      │
│        or illustration)      │
│                              │
│  Whoop gives Tempo your:     │
│                              │
│  [recovery icon] Recovery %  │
│  Know how hard to push today │
│                              │
│  [sleep icon] Sleep Score    │
│  Track sleep debt & quality  │
│                              │
│  [strain icon] Daily Strain  │
│  See your training load      │
│                              │
│  [hrv icon] HRV Trends       │
│  Detect overtraining early   │
│                              │
│                              │
│  ┌──────────────────────┐    │
│  │   CONNECT WHOOP       │    │
│  └──────────────────────┘    │
│                              │
│       Skip for now           │
│                              │
└──────────────────────────────┘
```

**Headline:** "YOUR BODY TALKS. LET'S LISTEN."
- Font: SF Pro Display Bold, 24pt, white

**Value Explanation:**
Four rows, each with an SF Symbol icon (in amber) and two lines of text:
1. **Recovery %** -- "Know how hard to push today"
2. **Sleep Score** -- "Track sleep debt and quality"
3. **Daily Strain** -- "See your training load in real-time"
4. **HRV Trends** -- "Detect overtraining before it's too late"

Font: SF Pro Text Semibold 16pt for the metric name (white), SF Pro Text Regular 14pt for the description (60% white).

**"Connect Whoop" button:**
- Amber background, black text, full width
- On tap: initiates ASWebAuthenticationSession to Whoop OAuth URL via the Tempo backend
- Flow: iOS opens in-app browser -> Whoop login -> authorize scopes -> redirect to `tempo://whoop-callback?code=XXX` -> backend exchanges code for tokens -> success returned to iOS
- During the OAuth flow: show a loading overlay with "Connecting to Whoop..."

**Success state:**
- Button transforms into a green card: "Connected!" with a checkmark
- Below: show the user's current recovery score if available: "Recovery: 72%" with the appropriate color zone
- If recovery data is not yet available (new Whoop user or no recent data): "Connected! Recovery data will appear after your first night of sleep."
- Auto-advance to Step 8 after 1.5 seconds

**"Skip for now" link:**
- Below the button, centered, 14pt, 60% white
- On tap: show a brief confirmation: "Got it. Without Whoop, these features will be limited:" followed by a short list:
  - Recovery-based training adjustments (will use default intensity)
  - Sleep tracking and bedtime recommendations
  - HRV trend analysis
- Two buttons: "Skip Anyway" / "Connect Whoop"
- If skipped: the RecoverIQ module shows "Connect Whoop to unlock recovery insights" as a persistent banner

**Error states:**
- OAuth cancelled by user: return to this screen, no error
- OAuth failed (network, Whoop server error): "Couldn't connect to Whoop. Try again?" with "Retry" and "Skip for now" options
- Invalid/expired OAuth code: "Connection expired. Let's try again." with Retry button

---

### Step 8: Connect NutriTrack

**Purpose:** Link NutriTrack for meal and macro data.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 8/12]     │
│                              │
│     FUEL IS NOT OPTIONAL.    │
│                              │
│  NutriTrack feeds Tempo your │
│  daily nutrition data:       │
│                              │
│  - Meals logged & planned    │
│  - Calories and macros       │
│  - Meal timing compliance    │
│  - Weekly nutrition trends   │
│                              │
│  Server URL                  │
│  ┌────────────────────────┐  │
│  │ https://               │  │
│  └────────────────────────┘  │
│                              │
│  PIN                         │
│  ┌────────────────────────┐  │
│  │ ● ● ● ● ● ●           │  │
│  └────────────────────────┘  │
│                              │
│  ┌──────────────────────┐    │
│  │   TEST CONNECTION     │    │
│  └──────────────────────┘    │
│                              │
│  Don't have NutriTrack?      │
│                              │
│       Skip for now           │
│                              │
└──────────────────────────────┘
```

**Headline:** "FUEL IS NOT OPTIONAL."
- Font: SF Pro Display Bold, 24pt, white

**Value explanation:**
Bullet list in SF Pro Text Regular 15pt, 70% white:
- Meals logged and planned
- Calories and macros (protein, carbs, fat)
- Meal timing compliance
- Weekly nutrition trends

**Server URL field:**
- Label: "Server URL" in 14pt, 60% white
- Placeholder: "https://your-nutritrack-server.com"
- Keyboard type: URL
- Autocorrect: off
- Autocapitalize: none
- Validation: must be a valid URL starting with `http://` or `https://`

**PIN field:**
- Label: "PIN" in 14pt, 60% white
- Secure text entry (dots)
- Keyboard type: numberPad
- 6 characters
- Validation: exactly 6 digits

**"Test Connection" button:**
- Amber outline (not filled), amber text
- On tap: sends a test request to the NutriTrack server via the Tempo backend
- During test: button shows spinner + "Testing..."
- Success: button transforms to green filled + "Connected!" and shows a data preview card:
  - "Today: 1,840 / 2,400 cal"
  - "Protein: 124g / 180g"
  - "Meals: 2 / 4 logged"
- After success: "Continue" button appears below (amber, filled)
- Failure scenarios:
  - Wrong URL: "Couldn't reach that server. Check the URL and try again."
  - Wrong PIN: "Invalid PIN. Check your NutriTrack settings."
  - Server unreachable: "Server not responding. Is NutriTrack running?"
  - Timeout (>10s): "Connection timed out. Check that NutriTrack is accessible from the internet."

**"Don't have NutriTrack?" link:**
- 14pt, amber, below the test button
- Opens a bottom sheet:
  - "NutriTrack is a self-hosted nutrition tracking app. You can set it up at github.com/your-repo/nutritrack."
  - "Without NutriTrack, Tempo won't track your nutrition automatically. You can still set meal-count non-negotiables and check them off manually."
  - "Got it" dismiss button

**"Skip for now" link:**
- Same style as Whoop skip
- If skipped: the Fuel quadrant on Dashboard shows "Connect NutriTrack to track nutrition" as a persistent card. Meal non-negotiables switch to manual check-off mode.

---

### Step 9: HealthKit Permissions

**Purpose:** Request HealthKit read/write access for steps, workouts, heart rate, sleep, and nutrition data passthrough.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 9/12]     │
│                              │
│     TEMPO NEEDS ACCESS       │
│     TO YOUR HEALTH DATA.     │
│                              │
│  This stays on your device.  │
│  Apple encrypts it. We       │
│  never see your raw health   │
│  data.                       │
│                              │
│  ┌────────────────────────┐  │
│  │ [steps icon]           │  │
│  │ Steps & Distance       │  │
│  │ Track daily movement   │  │
│  │ > Why?                 │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ [heart icon]           │  │
│  │ Heart Rate & HRV       │  │
│  │ Monitor workout effort │  │
│  │ > Why?                 │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ [workout icon]         │  │
│  │ Workouts               │  │
│  │ Auto-detect training   │  │
│  │ > Why?                 │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ [sleep icon]           │  │
│  │ Sleep Analysis         │  │
│  │ Supplement Whoop data  │  │
│  │ > Why?                 │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ [energy icon]          │  │
│  │ Active Energy          │  │
│  │ Calculate daily burn   │  │
│  │ > Why?                 │  │
│  └────────────────────────┘  │
│                              │
│  ┌──────────────────────┐    │
│  │   AUTHORIZE HEALTH    │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "TEMPO NEEDS ACCESS TO YOUR HEALTH DATA."
- Font: SF Pro Display Bold, 22pt, white

**Privacy reassurance:**
"This stays on your device. Apple encrypts it. We never see your raw health data."
- Font: SF Pro Text Regular, 15pt, 60% white
- This text appears directly below the headline

**Permission cards:**
Each card shows:
- Left: SF Symbol icon in amber (24pt)
- Title: permission type name, SF Pro Text Semibold 16pt, white
- Subtitle: brief explanation of why, SF Pro Text Regular 14pt, 60% white
- "Why?" expandable disclosure:
  - Steps & Distance: "Tempo uses your step count for the Move quadrant on your Dashboard and to award daily XP. No step data is sent to any server."
  - Heart Rate & HRV: "Heart rate during workouts helps Tempo assess training intensity. HRV supplements Whoop data for recovery insights."
  - Workouts: "Tempo reads Apple Watch workouts to auto-detect training sessions. It also writes RepForge workouts back to HealthKit so they appear in your Activity rings."
  - Sleep Analysis: "If you don't use Whoop, Tempo can read sleep data from Apple Watch. If you do use Whoop, this is a backup data source."
  - Active Energy: "Used to calculate your total daily energy expenditure for the Dashboard."

**"Authorize Health" button:**
- Amber, full width
- On tap: calls `HKHealthStore.requestAuthorization(toShare:read:)` with all types
- iOS presents its own HealthKit permission sheet (user can toggle each type)
- Important: HealthKit does NOT tell the app which specific permissions were denied -- `authorizationStatus` only distinguishes `.notDetermined` vs `.sharingAuthorized`/`.sharingDenied` for write types. For read types, the status is always `.notDetermined` even if denied (Apple privacy design).

**After system dialog dismisses:**
- Regardless of what the user chose: show a green confirmation card "Health data configured" and auto-advance after 1 second
- Rationale: we cannot know what was denied for read types. Gracefully degrade features that have no data rather than blocking onboarding.

**If user denies everything:**
- App still works. Dashboard shows "--" for steps, active energy, etc.
- A subtle banner appears on the Dashboard: "Some data is missing. Grant Health permissions in Settings > Privacy > Health > Tempo."
- No blocking, no nagging beyond the banner.

---

### Step 10: Notification Permissions

**Purpose:** Request notification permission and configure the drill-sergeant intensity.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 10/12]    │
│                              │
│     YOUR DRILL SERGEANT      │
│     NEEDS YOUR PERMISSION    │
│     TO YELL.                 │
│                              │
│  Preview:                    │
│  ┌────────────────────────┐  │
│  │ TEMPO            2:00PM│  │
│  │ 3 non-negotiables left.│  │
│  │ You've got 5 hours.    │  │
│  │ No excuses.            │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ TEMPO            6:30PM│  │
│  │ Study not done. 60 min │  │
│  │ missing. Your evening  │  │
│  │ is NOT earned yet.     │  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ TEMPO            9:00PM│  │
│  │ ALL CLEAR. You earned  │  │
│  │ your rest. Well done,  │  │
│  │ soldier.               │  │
│  └────────────────────────┘  │
│                              │
│  How tough should I be?      │
│                              │
│  ┌────────────────────────┐  │
│  │ Gentle Coach           │  │
│  │ Supportive, encouraging│  │
│  └────────────────────────┘  │
│  ┌────────────────────────┐  │
│  │ Firm Coach             │  │
│  │ Direct, no-nonsense    │  │
│  └────────────────────────┘  │
│  ┌═══════════════════════╗  │
│  ║ Drill Sergeant  [REC] ║  │
│  ║ Tough love, aggressive║  │
│  ╚═══════════════════════╝  │
│  ┌────────────────────────┐  │
│  │ Savage Mode            │  │
│  │ Brutal honesty, max    │  │
│  │ pressure               │  │
│  └────────────────────────┘  │
│                              │
│  ┌──────────────────────┐    │
│  │   ENABLE NOTIFICATIONS │    │
│  └──────────────────────┘    │
│                              │
└──────────────────────────────┘
```

**Headline:** "YOUR DRILL SERGEANT NEEDS YOUR PERMISSION TO YELL."
- Font: SF Pro Display Bold, 22pt, white

**Notification previews:**
Three mock notification banners stacked vertically, styled to look like real iOS notifications:
- Each has the Tempo app icon (small), "TEMPO" title, timestamp, and message body
- Background: 15% white with 8pt corner radius
- The previews update LIVE based on the intensity selector below -- when the user changes intensity, the copy in the previews changes with a crossfade animation

**Intensity Selector:**
Four vertically stacked option cards:

1. **Gentle Coach**
   - Subtitle: "Supportive and encouraging. Reminders without the edge."
   - Preview copy: "Hey! You've got 3 tasks left today. You can totally do this!"
   - Card style: 10% white bg, white text

2. **Firm Coach**
   - Subtitle: "Direct and clear. No sugarcoating, but no yelling."
   - Preview copy: "3 tasks remaining. 5 hours left. Time to focus."
   - Card style: 10% white bg, white text

3. **Drill Sergeant** (Recommended)
   - Subtitle: "Tough love. Gets louder as the day goes on."
   - Badge: "[REC]" in amber, top-right of card
   - Preview copy: "3 non-negotiables left. Clock's ticking. Move."
   - Card style: amber 2pt border, 10% white bg, white text
   - Default selected

4. **Savage Mode**
   - Subtitle: "Maximum pressure. Not for the faint-hearted."
   - Preview copy: "3 tasks undone. Another wasted day incoming. Prove me wrong."
   - Card style: 10% white bg, white text
   - Small warning below: "This mode is intentionally uncomfortable. That's the point."

**"Enable Notifications" button:**
- Amber, full width
- On tap: first saves the intensity preference locally, then calls `UNUserNotificationCenter.requestAuthorization(options: [.alert, .badge, .sound, .timeSensitive, .providesAppNotificationSettings])`
- Note: Critical Alerts entitlement will not be pursued (per Technical Feasibility Audit Section 3.2). `.timeSensitive` is the maximum interruption level used.
- After system dialog:
  - If **allowed**: green confirmation "Notifications enabled" + brief haptic success
  - If **denied**: show a card: "Without notifications, your drill sergeant can't reach you. The accountability system works best with notifications enabled." Two options: "Open Settings" (deep links to iOS Settings > Tempo > Notifications) / "Continue without" (proceeds but shows a persistent banner in Settings)

**What changes if notifications are denied:**
- All 13 notification channels are silent
- In-app alerts still work (banners within the app when opened)
- The accountability escalation system has no way to reach the user outside the app
- A persistent "Enable Notifications" card appears at the top of the Lockdown module
- Weekly prompt (in-app only) to enable notifications, max once per week, dismissible permanently after 3 dismissals

---

### Step 11: AI Features Consent (Required for App Store Compliance)

> **APP STORE COMPLIANCE (Guideline 5.1.2(i), November 2025):**
> This step is MANDATORY. Apple requires a SEPARATE, DEDICATED consent screen before ANY
> user data is sent to a third-party AI service. This screen MUST NOT be bundled with
> HealthKit (Step 9) or Notification (Step 10) permissions.

**Purpose:** Obtain explicit, informed consent before sending any user data to Anthropic's Claude API. Required by Apple's Guideline 5.1.2(i).

**Screen Layout:** See `AI_INTELLIGENCE_ENGINE.md` Section 11.3 for the full mockup and copy.

**Key requirements:**
- Names "Anthropic" and "Claude" explicitly (not "AI service")
- Lists what data categories are sent (recovery, sleep, nutrition, study time)
- States what data is NOT sent (name, email, Apple ID, device info)
- Two buttons with EQUAL visual weight:
  - "Enable AI Insights" (amber CTA) --> `aiConsent = true`
  - "Continue without AI" (visible button, not hidden text) --> `aiConsent = false`
- Links to Anthropic's privacy practices
- States the user can change this anytime in Settings > Privacy > AI Features

**Skip option:** "Continue without AI" IS the skip. The user explicitly declines. This is NOT an optional step -- the user MUST make a choice (enable or decline).

**Data persistence:** Write `aiConsentGranted: Bool`, `aiConsentTimestamp: Date`, `aiConsentVersion: String` to `OnboardingState`.

**Note:** Adding this step changes the total from 12 to 13 steps. Update the progress bar segments accordingly (13 segments). Renumber subsequent steps.

---

### Step 12: Arena Preview (Skip-Encouraged)

> **Note:** Previously Step 11. Renumbered to accommodate the mandatory AI consent step above.

**Purpose:** Show the social/competitive layer exists, but actively encourage skipping. Friend invites during onboarding are premature -- the user hasn't established their own routine yet. Research shows social features introduced before habit formation (Day 5+) create pressure without foundation.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [<] [progress bar: 11/12]    │
│                              │
│     ACCOUNTABILITY IS        │
│     BETTER WITH RIVALS.      │
│                              │
│  (illustration: two score    │
│   bars racing side by side)  │
│                              │
│  Compete with friends on     │
│  weekly leaderboards. Turn   │
│  discipline into a sport.    │
│                              │
│  ┌────────────────────────┐  │
│  │ Share Invite Link      │  │
│  │ (copy or share sheet)  │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Show My QR Code        │  │
│  │ (friend scans to add)  │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ Find Friends by        │  │
│  │ Username               │  │
│  │ ┌──────────────────┐   │  │
│  │ │ @                │   │  │
│  │ └──────────────────┘   │  │
│  └────────────────────────┘  │
│                              │
│                              │
│  ┌──────────────────────┐    │
│  │       CONTINUE        │    │
│  └──────────────────────┘    │
│                              │
│       Skip for now           │
│                              │
└──────────────────────────────┘
```

**Headline:** "ACCOUNTABILITY IS BETTER WITH RIVALS."
- Font: SF Pro Display Bold, 24pt, white

**Subtext:**
"Compete with friends on weekly leaderboards. Turn discipline into a sport."
- Font: SF Pro Text Regular, 16pt, 70% white

**Invite Options:**

1. **Share Invite Link:**
   - Button with link icon
   - Tapping opens iOS share sheet with a deep link: `https://tempo.app/invite/[username]`
   - Share text: "Join me on Tempo -- the life OS for student-athletes. Download and add me: @[username]"

2. **Show My QR Code:**
   - Button with QR code icon
   - Opens a full-screen modal with a large QR code encoding the invite deep link
   - QR code on dark background, white modules, amber corner markers
   - Username displayed below QR code
   - "Done" button to dismiss

3. **Find Friends by Username:**
   - Inline search field with "@" prefix
   - Debounced search (500ms)
   - Results appear below: avatar + display name + username + "Add" button
   - Adding sends a friend request (not instant -- requires acceptance)
   - Confirmation: "Friend request sent to @marco"

**Continue button:** Always enabled (this step is entirely optional). Label: "CONTINUE" (not "Skip" -- reducing friction).

**"I'll add friends later":** Below continue button, 14pt, 60% white. Same behavior as tapping Continue with no actions taken. This is the EXPECTED path for most users during onboarding.

**Deferred friend invites:** Friend invite functionality is surfaced on Day 5-7 via in-app card (see First Week Experience), after the user has established their routine and has something to compete about. During onboarding, the invite tools are present but not promoted.

**No contact import.** Rationale: importing contacts requires heavy permissions (Contacts access), creates privacy friction, and doesn't align with the "your data stays yours" philosophy. Username-based search and link sharing are sufficient.

---

### Step 13: Summary / First Day Briefing

> **Note:** Previously Step 12. Renumbered to accommodate the mandatory AI consent step (Step 11).

**Purpose:** Show the user everything that's set up, build excitement, and transition to the main app.

**Screen Layout:**
```
┌──────────────────────────────┐
│ [progress bar: 12/12 FULL]   │
│                              │
│     YOU'RE LOCKED IN.        │
│                              │
│  ┌────────────────────────┐  │
│  │ TODAY'S BRIEFING        │  │
│  │                         │  │
│  │ Recovery: 72% (yellow)  │  │
│  │ → Moderate training day │  │
│  │                         │  │
│  │ Training: Push Day      │  │
│  │ → Bench, OHP, Dips,    │  │
│  │   Lateral Raises        │  │
│  │                         │  │
│  │ Study: 2h target        │  │
│  │ → Anatomy exam in 18d  │  │
│  │                         │  │
│  │ Meals: 4 planned        │  │
│  │ → 2,400 cal target     │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ INTEGRATIONS            │  │
│  │ [x] Whoop     Connected│  │
│  │ [x] NutriTrack Connected│  │
│  │ [x] HealthKit Enabled  │  │
│  │ [ ] Calendar  Skipped  │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ NON-NEGOTIABLES         │  │
│  │ [ ] Train (Push)       │  │
│  │ [ ] Study 2h           │  │
│  │ [ ] Eat 4 meals        │  │
│  └────────────────────────┘  │
│                              │
│                              │
│  ┌══════════════════════╗    │
│  ║  YOUR FIRST MISSION   ║    │
│  ║   STARTS NOW.         ║    │
│  ╚══════════════════════╝    │
│                              │
└──────────────────────────────┘
```

**Headline:** "YOU'RE LOCKED IN."
- Font: SF Pro Display Black, 28pt, white
- Subtle entrance animation: text types in letter by letter (typewriter effect), 0.05s per character

**Today's Briefing Card:**
- Dynamically populated based on:
  - Whoop recovery score (if connected) with color zone indicator
  - Training plan generated by RepForge based on profile
  - Study target from onboarding
  - Meal plan from NutriTrack (if connected) or default meal count
- If Whoop not connected: Recovery line shows "Connect Whoop to see your recovery" in amber
- If NutriTrack not connected: Meals line shows "3 meals (manual tracking)"
- If no training: Training line is omitted

**Integrations Card:**
- Checklist of all integrations with status
- Connected: green checkmark + "Connected"
- Skipped: gray dash + "Skipped" (tapping opens a bottom sheet to connect now)
- Each row is tappable for skipped integrations

**Non-Negotiables Card:**
- List of the user's configured non-negotiables with empty checkboxes
- This is the first time they see the "real" checklist they'll interact with daily

**CTA: "YOUR FIRST MISSION STARTS NOW."**
- Large button, amber background, black text, SF Pro Display Bold 18pt
- Full width, 60pt height
- Haptic: medium impact on tap
- On tap: dismisses onboarding, transitions to the main app Dashboard
- Transition: the summary screen scales down and fades while the Dashboard scales up from behind it (0.5s spring animation)

**Post-onboarding:**
- `OnboardingState.isComplete` is set to `true`
- The `OnboardingState` object is transformed into `UserSettings` (SwiftData model) and persisted
- Backend is updated with the user's profile, preferences, and integration states
- First morning briefing notification is scheduled for tomorrow at the detected wake time (default: 8:30 AM if no data)
- If current time is before evening start minus 5.5 hours: schedule today's first accountability check (Gentle Reminder)
- If current time is later: schedule the next applicable escalation tier based on how close to evening start

---

## Onboarding UX Details

### Data Persistence Strategy

All onboarding state is stored in a `Codable` struct persisted to `UserDefaults`:

```swift
struct OnboardingState: Codable {
    var currentStep: Int = 1
    var appleUserID: String?
    var displayName: String?
    var username: String?
    var profilePhotoURL: URL?
    var trainsRegularly: Bool?
    var trainingTypes: [String] = []
    var trainingDaysPerWeek: Int?
    var trainingSplit: String?
    var teamSportDays: [Int] = []  // 1=Mon, 7=Sun
    var experienceLevel: String?
    var workoutDuration: Int?  // minutes
    var equipment: String?
    var weightUnit: String = "kg"
    var isStudent: Bool?
    var schoolName: String?
    var courses: [String] = []
    var exams: [ExamEntry] = []
    var dailyStudyGoalMinutes: Int?
    var calendarConnected: Bool = false
    var primaryGoal: String?
    var nonNegotiables: [NonNegotiableEntry] = []
    var timeWasters: [String] = []
    var eveningStartTime: String?  // "19:30" format
    var whoopConnected: Bool = false
    var nutriTrackConnected: Bool = false
    var nutriTrackURL: String?
    var healthKitAuthorized: Bool = false
    var notificationsEnabled: Bool = false
    var notificationIntensity: String = "drill_sergeant"
    var isComplete: Bool = false
}
```

Written after EVERY step completes. On app launch, if `isComplete == false`, resume at `currentStep`.

### Validation Rules Summary

| Field | Rules |
|-------|-------|
| Display Name | 2-30 chars, trimmed, no empty |
| Username | 3-20 chars, `^[a-z][a-z0-9._]{2,19}$`, no `..` or `__`, unique |
| School Name | 0-100 chars (optional) |
| Course Name | 1-50 chars per course, max 12 courses |
| Exam Date | Must be today or future |
| Custom Non-Negotiable Name | 1-30 chars |
| Non-Negotiable Target | Positive integer or decimal |
| NutriTrack URL | Valid URL, starts with http(s):// |
| NutriTrack PIN | Exactly 6 digits |
| Evening Start Time | 5:00 PM - 11:00 PM, 15-min increments |

### Error State Patterns

All error states follow the same visual pattern:
- Inline error text appears below the field, 13pt, SF Pro Text Regular, red (#EF4444)
- The field's border color changes to red
- The error text slides in from the top with a 0.2s animation
- Error clears as soon as the user begins editing the field

For network errors (API calls):
- A banner slides down from the top of the screen (below the progress bar)
- Background: red (#EF4444) at 90% opacity
- White text: error message
- "Retry" button on the right side
- Auto-dismisses after 5 seconds or on tap

### Accessibility

- All interactive elements have `accessibilityLabel` and `accessibilityHint`
- Progress bar: "Step [N] of 12" as accessibility value
- Option cards: "Selected" / "Not selected" traits
- Animations respect `UIAccessibility.isReduceMotionEnabled` -- all animations replaced with simple fades when reduce motion is on
- No time-limited interactions (no "choose within 10 seconds" patterns)
- All text supports Dynamic Type up to AX5 -- layout switches to scrollable single-column when text size exceeds `.accessibility1`
- Color is never the sole indicator. Recovery zones show text labels ("Green", "Yellow", "Red") alongside colored indicators.
- VoiceOver reads notification previews in Step 10 as: "Notification preview. [timestamp]. [message body]."

---

## Onboarding Funnel Optimization

### Funnel Metrics & Expected Drop-off

Total onboarding target time: **under 4 minutes** for the "Quick Start" path, **under 6 minutes** for "Full Setup."

| Step | Name | Time Target | Expected Completion Rate | Cumulative | Industry Benchmark |
|------|------|------------|------------------------|------------|-------------------|
| 1 | Welcome / Value Prop | 5s | 95% | 95% | 90-95% (splash screens) |
| 2 | Sign in with Apple | 15s | 88% | 83.6% | 70-85% (account creation) |
| 3 | Profile Setup | 30s | 94% | 78.6% | 85-92% (profile steps) |
| 4 | Training Profile | 40s | 92% | 72.3% | 80-90% (config steps) |
| 5 | Academics | 45s | 93% | 67.2% | 80-90% (config steps) |
| 6 | Goals / Non-Negotiables | 35s | 95% | 63.9% | 85-92% (personalization) |
| 7 | Connect Whoop | 20-45s | 90% (incl. skip) | 57.5% | 60-75% (3rd party OAuth) |
| 8 | Connect NutriTrack | 20-40s | 92% (incl. skip) | 52.9% | 60-75% (3rd party connect) |
| 9 | HealthKit | 15s | 96% | 50.8% | 85-95% (system dialog) |
| 10 | Notification Permissions | 20s | 94% | 47.7% | 55-70% (notification ask) |
| 11 | Arena Setup | 15-30s | 97% (incl. skip) | 46.3% | 85-95% (optional social) |
| 12 | Summary / Launch | 10s | 99% | 45.8% | 98%+ (final CTA) |

**Target: 50%+ completion rate** from download to fully onboarded. Industry average for 12-step onboarding: 30-40%. Our advantage: every screen has clear value, skip options on optional steps, and state persistence across kills.

### Quick Start vs Full Setup Paths

**Quick Start (5 steps, <2 minutes):**
For users who want to explore before committing to full setup. Gets the user to value (seeing the Dashboard with their data) as fast as possible.

1. Step 1: Welcome / Value Prop (5s)
2. Step 2: Sign in with Apple (15s)
3. Step 3: Display Name (20s)
4. Step 6: Goals / Non-Negotiables (45s) -- the ONE critical step. User must set at least 1 non-negotiable.
5. Step 10: Notification Permission + Intensity (20s) -- the drill sergeant IS the product.
6. Jump to Dashboard

**Why this order matters:** Steps 4-5 (Training/Academics) are configuration, not core experience. The user can train and study without detailed profiles. But non-negotiables and notifications are the core loop -- skip those and the app has no value on Day 1.

Deferred to post-onboarding (accessible from Dashboard "Complete Setup" card and Settings):
- Training profile (Step 4) -- defaults to general fitness
- Academics (Step 5) -- defaults to "not a student"
- Integrations (Steps 7-9) -- prompted contextually: Whoop when they tap Recovery, NutriTrack when they tap Fuel, HealthKit after first workout
- Arena (Step 11) -- prompted on Day 5-7 when user has a routine

**Trigger for Quick Start path:**
- Offered explicitly on Step 4 (first Life Setup screen): "Want to jump in now and configure later?" as a prominent secondary CTA
- Quick Start users get a "Complete your setup" card on Dashboard that persists for 14 days (not 7 -- give them time)
- Each incomplete section shows a progress ring: "Setup: 5/12 complete"
- The card disappears permanently after dismissal OR after 14 days, whichever comes first

**Full Setup (12 steps, <4 minutes):**
The default path. All steps as documented above.

### Recovery Flows for Each Drop-off Point

**Drop-off at Step 2 (Sign in with Apple) -- highest-risk step:**
- On next app launch: return directly to Step 2
- After 24h with no return: send provisional notification (if available): "Your Tempo setup is 90% ready. One tap to finish."
- After 48h: send a second: "Tempo works best with an account. Sign in takes 3 seconds with Face ID."
- After 72h: stop. User has chosen not to proceed.
- A/B test: try moving Apple sign-in to Step 4 (after user has invested time in setup, sunk cost increases conversion)

**Drop-off at Steps 4-6 (Life Setup -- longest steps):**
- State is persisted. On next launch: resume exactly where they left off.
- Show a "Welcome back! You're on step {N} of 12" toast.
- After 6h with no return: "Your training profile is 60% built. 2 more questions and you're done."
- After 24h: "Tempo is waiting for you. Pick up where you left off -- it takes 2 more minutes."
- After 72h: "Quick Start available -- skip the setup and dive in. You can configure later."

**Drop-off at Steps 7-8 (Integrations):**
- These are the most likely to cause confusion (OAuth, server URLs).
- On return: show the same screen with any previously entered data preserved.
- After 12h: "Don't have Whoop? No problem -- skip it and Tempo still tracks your training, study, and meals."
- Subtext shift: emphasize that integrations are optional enhancements, not requirements.

**Drop-off at Step 10 (Notification Permission):**
- If user backgrounds the app during the iOS permission dialog: on return, check notification status and advance if already granted.
- If denied: proceed without. Recover via provisional notifications and in-app prompts.
- After 24h: use provisional notification channel (if available): "Your drill sergeant is ready. Enable notifications to unlock accountability mode."

### A/B Test Suggestions

| Test | Hypothesis | Metric | Step |
|------|-----------|--------|------|
| Move Sign-in to Step 4 | Sunk cost after 3 screens of personalization increases sign-in rate | Sign-in completion rate | 2 |
| Single-screen vs multi-screen Life Setup | Combining Steps 4+5+6 into one scrollable screen reduces perceived length | Steps 4-6 completion rate, time-to-complete | 4-6 |
| Show Dashboard preview before integrations | Seeing a populated preview motivates integration connections | Whoop + NutriTrack connection rate | 7-8 |
| Pre-permission priming screen for notifications | An extra screen showing 3 real notification examples before the iOS dialog increases opt-in | Notification permission grant rate | 10 |
| Notification intensity default: Firm vs Drill Sergeant | Drill Sergeant may scare some users; Firm may feel too generic | Day-7 notification engagement rate | 10 |
| "Skip all integrations" single button | Reducing 3 integration screens to 1 skip-all option reduces drop-off | Step 7-9 completion rate | 7-9 |
| Social proof on Welcome screen | "12,847 student-athletes are already using Tempo" increases trust | Step 1 -> Step 2 conversion | 1 |
| Animated vs static notification previews | Animated previews (showing escalation in real-time) are more compelling | Notification opt-in rate | 10 |

### Progressive Disclosure — What to Defer

**Must be in onboarding (cannot defer):**
- Apple Sign-in (required for any backend interaction)
- Display name (required for identity; username deferred to first Arena access)
- At least 1 non-negotiable (core loop depends on it)
- Notification permission ask (iOS best practice: ask during onboarding with context)

**Should be in onboarding but can defer:**
- Training profile details (default to general fitness if skipped)
- Academic details (default to "not a student" if skipped)
- Evening start time (default to 7:30 PM)
- Time-waster selection (default to generic copy)

**Can safely defer to post-onboarding:**
- Username selection (defer to first Arena access -- users who never use social don't need it)
- Profile photo (can add anytime in Settings)
- Whoop connection (prompt contextually when user taps Recovery quadrant, or after first week)
- NutriTrack connection (prompt when user taps Fuel quadrant)
- Calendar import (prompt when user adds an exam or manually enters a class conflict)
- Arena friend invites (defer to Day 5-7, not Day 2-3 -- user needs to establish their own routine first)
- Detailed notification channel configuration (prompt after first notification interaction)

### Onboarding Analytics Events

Track these events to measure funnel performance:

```swift
enum OnboardingEvent: String {
    case onboarding_started           // Step 1 viewed
    case onboarding_step_completed    // params: step_number, time_spent_ms
    case onboarding_step_skipped      // params: step_number
    case onboarding_abandoned         // params: last_step, total_time_ms
    case onboarding_resumed           // params: resume_step, hours_since_abandon
    case onboarding_completed         // params: total_time_ms, steps_skipped, integrations_connected
    case quick_start_chosen           // params: step_number_when_chosen
    case integration_connected        // params: integration_name (whoop/nutritrack/healthkit/calendar)
    case integration_skipped          // params: integration_name
    case notification_permission      // params: granted (bool)
    case intensity_selected           // params: intensity_level
    case sign_in_cancelled            // params: cancellation_count
    case sign_in_error                // params: error_type
    case friend_invited               // params: method (link/qr/search)
}
```

---

## Re-Onboarding

### Prompting Skipped Integrations

**Whoop (skipped during onboarding):**
- RecoverIQ module shows a persistent banner: "Connect Whoop to unlock recovery insights."
- Tapping the banner opens the Whoop connection flow (same screens as onboarding Step 7, but presented as a modal sheet from within the app).
- After the first week of use, if still not connected: in-app card on Dashboard "Your training could be 40% smarter with recovery data. Connect Whoop?" with "Connect" and "Not now" buttons. This card appears once per week, max 3 times, then stops.

**NutriTrack (skipped during onboarding):**
- Fuel quadrant on Dashboard shows "Connect NutriTrack" card.
- Same prompting cadence as Whoop: weekly, max 3 times.

**Calendar (skipped during onboarding):**
- The first time the user manually enters a class time or football schedule conflict: "Save time -- import from your calendar?" with "Import" button.

**Notifications (denied during onboarding):**
- Persistent banner at top of Lockdown module: "Enable notifications so your drill sergeant can keep you on track."
- Deep link: tapping opens `UIApplication.openSettingsURLString` (iOS Settings > Tempo > Notifications).
- In-app prompt: once per week, max 3 times total, then a smaller text link in Settings.

### Late Integrations (User Gets Whoop After Setup)

- Settings > Integrations > Whoop: "Connect Whoop" row
- Tapping opens the same OAuth flow as onboarding
- After connection: RecoverIQ immediately populates, training adjustments begin within one sleep cycle, morning briefing adds recovery score
- A one-time celebratory notification: "Whoop connected. Tomorrow morning, you'll get your first recovery-powered briefing."

### Settings Deep Links

Every setup flow is re-accessible from Settings:

```
Settings
├── Profile
│   ├── Display Name (editable)
│   ├── Username (editable, with availability check)
│   ├── Profile Photo (editable)
│   └── Sign Out
├── Training Profile
│   ├── Training Types
│   ├── Days Per Week
│   ├── Split Preference
│   ├── Team Sport Schedule
│   ├── Experience Level
│   ├── Workout Duration
│   ├── Equipment
│   └── Weight Unit
├── Academics
│   ├── Student Status
│   ├── School
│   ├── Courses (add/remove)
│   ├── Exams (add/remove)
│   └── Daily Study Goal
├── Goals & Accountability
│   ├── Primary Goal
│   ├── Non-Negotiables (add/remove/edit)
│   ├── Time Waster
│   └── Evening Start Time
├── Integrations
│   ├── Whoop (connect/disconnect/status)
│   ├── NutriTrack (connect/disconnect/edit URL+PIN)
│   ├── Apple Health (status, link to Settings)
│   └── Apple Calendar (connect/disconnect, calendar selection)
├── Notifications
│   ├── Intensity Level
│   ├── Per-Channel Toggles (13 channels)
│   ├── Wake Time
│   ├── Bedtime
│   ├── Quiet Hours
│   └── Notification Sound
└── About
    ├── Version
    ├── Privacy Policy
    ├── Terms of Service
    └── Delete Account
```

---

# PART 2: NOTIFICATION SYSTEM -- COMPLETE SPECIFICATION

## Notification Architecture

### Accountability Escalation Timeline (Relative to Evening Start)

All accountability notification times are calculated relative to the user's configured **evening start time (E)**, not hardcoded clock times. This ensures the system works whether a user's evening starts at 6 PM or 10 PM.

| Channel | Formula | Example (E=7:30 PM) | Example (E=10:00 PM) |
|---------|---------|---------------------|----------------------|
| Ch 2: Gentle Reminder | E - 5.5h | 2:00 PM | 4:30 PM |
| Ch 3: Firm Warning | E - 2.5h | 5:00 PM | 7:30 PM |
| Ch 4: Urgent Alert | E - 1h | 6:30 PM | 9:00 PM |
| Ch 5: Final Warning | E - 30min | 7:00 PM | 9:30 PM |
| Ch 13: Streak Warning | E + 1.5h | 9:00 PM | 11:30 PM |

### Local vs. Push Notifications

| Notification Type | Delivery | Rationale |
|-------------------|----------|-----------|
| Morning Briefing | **Push** (APNs via backend) | Requires server-side data aggregation (Whoop recovery, NutriTrack data) |
| Accountability Reminders (Channels 2-6) | **Local** | Scheduled locally based on non-negotiable progress; no server needed |
| Meal Reminders | **Local** | Meal schedule stored locally from NutriTrack sync |
| Training Reminder | **Local** | Workout schedule is local |
| Recovery Report | **Push** (APNs) | Triggered by Whoop webhook on backend |
| Bedtime Reminder | **Local** | Calculated locally from prescription |
| Arena/Social | **Push** (APNs) | Triggered by other users' actions on backend |
| Weekly Summary | **Push** (APNs) | Requires server-side aggregation and AI insights |
| Streak Warning | **Local** | Based on local daily progress data |

**Local notification scheduling strategy:**
- Recalculate and reschedule all local notifications at these trigger points:
  1. App launch
  2. Non-negotiable status change (task completed or updated)
  3. Midnight (daily reset via background task)
  4. After receiving a push notification that updates local state
- Use `UNUserNotificationCenter.removePendingNotificationRequests(withIdentifiers:)` to clear outdated ones before scheduling new ones
- Maximum 64 pending local notifications (iOS hard limit). Scheduling strategy (per Technical Feasibility Audit Section 3.1):
  1. Always schedule ALL of today's notifications first (typically 24-32).
  2. Schedule tomorrow's morning briefing and first accountability tier.
  3. Fill remaining slots with tomorrow's remaining notifications.
  4. NEVER pre-schedule more than 48 hours out.
  5. Rest timer notifications must be scheduled one-at-a-time (not all rest timers for all exercises upfront).
  6. Re-schedule each morning: use the app foreground event (`scenePhase == .active`) or BGAppRefreshTask as a safety net to recalculate daily.
  7. Log the pending notification count on every schedule operation to catch limit violations during development.

### Notification Categories and Actions

Register these `UNNotificationCategory` objects at app launch:

| Category ID | Actions | Options |
|-------------|---------|---------|
| `MORNING_BRIEFING` | "View Day" (foreground), "Start Workout" (foreground) | -- |
| `ACCOUNTABILITY_GENTLE` | "Start Study" (foreground), "View Tasks" (foreground) | -- |
| `ACCOUNTABILITY_FIRM` | "Start Now" (foreground), "View Tasks" (foreground) | -- |
| `ACCOUNTABILITY_URGENT` | "Start Study Timer" (foreground), "I'm On It" (dismisses) | Time Sensitive |
| `ACCOUNTABILITY_FINAL` | "Start Now" (foreground), "Override" (foreground, destructive) | Time Sensitive |
| `ACCOUNTABILITY_CLEAR` | "View Stats" (foreground) | -- |
| `MEAL_REMINDER` | "Log Meal" (foreground), "Delay 30min" (background) | -- |
| `TRAINING_REMINDER` | "View Workout" (foreground), "Skip Today" (background, destructive) | -- |
| `RECOVERY_REPORT` | "View Recovery" (foreground), "View Workout" (foreground) | -- |
| `BEDTIME_REMINDER` | "Wind Down" (foreground) | Time Sensitive |
| `ARENA_SOCIAL` | "View Arena" (foreground) | -- |
| `WEEKLY_SUMMARY` | "View Report" (foreground) | -- | Scheduled: Sunday 8:00 PM |
| `STREAK_WARNING` | "Save Streak" (foreground), "View Tasks" (foreground) | Time Sensitive |

**Action behaviors:**
- "Start Study" / "Start Study Timer" / "Start Now": opens app directly to FocusTimerView and auto-starts the timer
- "View Tasks" / "View Day": opens app to LockdownView / DashboardView
- "View Workout" / "Start Workout": opens app to TodayWorkoutView
- "Log Meal": opens app to NutriTrack deep link or in-app meal logging. **TODO:** NutriTrack URL scheme not yet defined in INTEGRATION_SPECS.md.
- "Delay 30min": reschedules the meal reminder for 30 minutes later (background action, no app launch)
- "Skip Today": marks workout as skipped, triggers XP penalty (background action with confirmation dialog on next app launch)
- "I'm On It": dismisses the notification and logs an acknowledgment timestamp
- "Override": opens app and shows a confirmation dialog: "Override tonight's accountability? This will end your streak and cost you 50 XP." with "Override" (destructive) / "Cancel"
- "Wind Down": opens app to a wind-down screen (dimmed UI, sleep tips, caffeine check). **TODO:** Wind Down screen not yet specified in MODULE_RECOVERY.md or MODULE_ACCOUNTABILITY.md — needs a full spec.
- "View Recovery" / "View Arena" / "View Report" / "View Stats": opens respective module

### Notification Grouping Strategy

- Thread identifier format: `tempo.[channel].[date]`
- Example: `tempo.accountability.2026-03-24`
- All accountability notifications for the same day group under one thread
- Summary format: "Tempo Accountability -- 3 more notifications"
- Arena notifications group by sub-type: `tempo.arena.leaderboard`, `tempo.arena.challenge`
- Meal reminders: `tempo.meals.2026-03-24`

### Badge Count Logic

- Badge count = number of incomplete non-negotiables for today
- Updated at:
  - Each non-negotiable status change
  - When a new accountability notification fires
  - At midnight (reset to new day's total)
- When all non-negotiables are complete: badge clears to 0
- Arena notifications do NOT increment the badge (social notifications shouldn't create anxiety)
- Implementation: `UNUserNotificationCenter.setBadgeCount(_:)`

### Sound Strategy

| Channel | Sound |
|---------|-------|
| Morning Briefing | Default system sound |
| Accountability Gentle | Default system sound |
| Accountability Firm | Default system sound |
| Accountability Urgent | Custom: `tempo_urgent.caf` -- two short ascending tones, 0.8s total |
| Accountability Final | Custom: `tempo_final.caf` -- three sharp staccato tones, 1.2s total. Plays as Time Sensitive notification. |
| Accountability All Clear | Custom: `tempo_clear.caf` -- a single bright ascending chime, 0.5s |
| Meal Reminder | Default system sound |
| Training Reminder | Default system sound |
| Recovery Report | Default system sound |
| Bedtime Reminder | Custom: `tempo_bedtime.caf` -- soft, low-frequency tone, 0.6s |
| Arena Social | Default system sound |
| Weekly Summary | Default system sound |
| Streak Warning | Custom: `tempo_urgent.caf` (same as urgent) |

All custom sounds must be:
- Under 30 seconds (iOS requirement)
- In CAF, WAV, or AIFF format
- Bundled in the app's main bundle

### Time Sensitive Notifications for Final Warning

> **FEASIBILITY NOTE:** Critical Alerts (`com.apple.developer.usernotifications.critical-alerts`) will NOT be approved by Apple for a productivity/accountability app (per Technical Feasibility Audit Section 3.2). The entitlement is reserved for health/safety apps (medical devices, emergency alerts, home security). Tempo uses `.timeSensitive` interruption level instead, which achieves 90% of the goal without any special entitlement.

**What Time Sensitive achieves:**
- Breaks through Scheduled Summary
- Appears immediately on the lock screen
- Stays visible for 1 hour
- Works without any special entitlement

**For maximum accountability (user-controlled):** Instruct Drill Sergeant / Savage Mode users to enable "Always Deliver" for Tempo in Settings > Notifications. This bypasses Focus modes entirely and is user-controlled -- no entitlement needed.

**Usage policy (internal):**
- Channel 5 (Final Warning) uses `.timeSensitive` interruption level
- Maximum 1 Final Warning notification per day
- Only fires if the user has explicitly opted in to Drill Sergeant or Savage Mode intensity
- Gentle Coach and Firm Coach intensity levels use `.active` interruption level

### Time Sensitive Notifications (iOS 15+)

Used for: Morning Briefing, Accountability Firm, Accountability Urgent, Bedtime Reminder, Streak Warning.

These notifications:
- Break through Scheduled Summary
- Appear on the lock screen immediately
- Stay on the lock screen for 1 hour (vs. normal notifications which defer to summary)
- Set via `UNNotificationContent.interruptionLevel = .timeSensitive`

---

## Notification Channels — Full Copy Bank (All 4 Intensities)

Every channel below includes 30+ unique copy variations. Each variation is written for all 4 intensity levels. Copy uses dynamic variables (wrapped in `{braces}`) that are injected at send time.

**Intensity key:**
- **G** = Gentle Coach
- **F** = Firm Coach
- **D** = Drill Sergeant
- **S** = Savage Mode

---

### Channel 1: Morning Briefing

**Trigger:** Daily at user's detected or configured wake time. Adaptive logic (in priority order):
1. If Whoop is connected and provides sleep end time: fire 5 minutes after sleep end.
2. If Apple Health has sleep data: fire 5 minutes after last sleep sample ends.
3. If neither: use the user's configured wake time (default 8:30 AM -- university students don't consistently wake at 7 AM).
4. After 14 days of data: learn the user's median wake time and auto-adjust. Suggest the learned time in-app: "You usually wake around 9:15 AM. Want to update your briefing time?"
5. On weekends (Sat/Sun): add 1 hour to the wake time unless Whoop/HealthKit provides actual sleep end.

**Type:** Time Sensitive push notification.

**String key prefix:** `notif.morning.`

**Payload structure:**
```json
{
  "aps": {
    "alert": {
      "title": "TEMPO",
      "subtitle": "Morning Briefing",
      "body": "..."
    },
    "sound": "default",
    "interruption-level": "time-sensitive",
    "category": "MORNING_BRIEFING",
    "badge": 4
  },
  "data": {
    "channel": "morning_briefing",
    "recovery_score": 72,
    "recovery_zone": "yellow",
    "workout_type": "Push",
    "study_target": 120,
    "exam_days_away": 18,
    "streak_days": 7
  }
}
```

**Actions:** "View Day" (opens Dashboard), "Start Workout" (opens Training)

#### Copy Variations — 32 contexts x 4 intensities

> **APP STORE COMPLIANCE WARNING (Guideline 27.x / HealthKit / Lock Screen Safety):**
> The copy templates below contain health data placeholders (`{recovery_score}%`, `{sleep_hours}`,
> `{calories_current}`, `{hrv_trend_days}`, etc.). These templates are used for LOCAL notification
> rendering and in-app display ONLY. When generating PUSH notifications sent from the backend,
> the server MUST substitute zone-based language in the `alert.body` field:
>
> - `{recovery_score}%` --> "Green recovery" / "Yellow recovery" / "Red recovery"
> - `{sleep_hours}` --> "Great sleep" / "Rough night" / "Short night"
> - `{calories_current}/{calories_target}` --> "On track" / "Behind on fuel" / "Under-eating"
> - `{hrv_trend_days}` --> omit from alert body entirely
>
> Exact numeric values go in the `data` payload (not visible on lock screen).
> See the "Lock Screen Safety" section at the bottom of this document for the full rule.
> See `docs/APP_STORE_COMPLIANCE.md` Section 2.3 for compliance requirements.

**1. Green recovery day (recovery >= 67%)**

`notif.morning.green_recovery`

- **G:** Good morning, {name}! Recovery is at {recovery_score}% -- your body feels great today. {workout_type} day is on the schedule. You've got {tasks_total} things to take care of. You can do this!
- **F:** Morning. Recovery: {recovery_score}%. Green. {workout_type} day. {tasks_total} non-negotiables. Full effort today.
- **D:** Recovery at {recovery_score}%. Your body is ready. {workout_type} day on deck -- I want to see PRs on bench press. {tasks_total} non-negotiables today. No excuses. Let's go.
- **S:** {recovery_score}% recovery. Green light. If you don't go all out on {workout_type} day with numbers like these, you're leaving gains on the table like an amateur. {tasks_total} tasks. Get moving.

**2. Yellow recovery day (recovery 34-66%)**

`notif.morning.yellow_recovery`

- **G:** Morning, {name}. Recovery is {recovery_score}% today -- not your peak, but that's okay. {workout_type} day is lighter. Focus on good form and hit your {tasks_total} targets. You've got this.
- **F:** Recovery: {recovery_score}%. Yellow. {workout_type} day is on but volume is reduced 20%. Study {study_target}, {meals_target} meals, train. Adjust intensity, not commitment.
- **D:** Recovery at {recovery_score}%. Not your best, not your worst. {workout_type} day is still on but we're pulling back volume 20%. Study {study_target}, {meals_target} meals, train. The plan doesn't change because you're tired.
- **S:** {recovery_score}%. Mediocre recovery for a mediocre sleeper. {workout_type} day happens anyway -- lighter, not cancelled. {tasks_total} tasks don't care about your yellow score. Muoviti.

**3. Red recovery day (recovery < 34%)**

`notif.morning.red_recovery`

- **G:** Hey {name}, your body needs extra care today. Recovery is {recovery_score}%. I've swapped your workout to gentle mobility. Study and meals are still on -- just go easy on yourself physically.
- **F:** Recovery: {recovery_score}%. Red. Swapping to mobility. Study and meals remain non-negotiable. Rest is part of the plan, not a failure.
- **D:** Recovery at {recovery_score}%. Your body is waving a white flag. Swapping to mobility work today -- you'll thank me tomorrow. But study and meals are still non-negotiable. Red recovery doesn't mean red on everything.
- **S:** {recovery_score}%. Your body is wrecked. Mobility only -- heavy weights are off the table. But red recovery doesn't mean a red day for everything. Study and meals still happen. Books. Now.

**4. Exam approaching (within 7 days)**

`notif.morning.exam_approaching`

- **G:** Good morning! {exam_name} exam is in {exam_days} days. You've been preparing well. Today's study goal is {study_target} -- keep that momentum going. Training is lighter this week so you can focus.
- **F:** {exam_name} in {exam_days} days. That's {exam_days} x {study_target} of study if you hit every day. Training scaled back. Academics are the priority.
- **D:** {exam_name} exam in {exam_days} days. That's {exam_days} study sessions if you hit your target every day. Zero room for slacking. Training is light this week. Books come first. War mode.
- **S:** {exam_days} days until {exam_name}. Tick tock. Every hour you waste is an hour you'll wish you had the night before the exam. Training is irrelevant this week. If I catch you at the gym before your study hours are done, we have a problem.

**5. Streak milestone (7, 14, 30, 60, 90, 180, 365)**

`notif.morning.streak_milestone`

- **G:** {name}, today is day {streak_days} of your streak! That's incredible consistency. Keep going -- today's plan: {workout_type}, {study_target} study, {meals_target} meals. You're building something special.
- **F:** Day {streak_days}. Consistent. {workout_type} today, {study_target} study, {meals_target} meals. Don't break the chain.
- **D:** {streak_days} days straight. That's not luck, that's identity. You're the person who shows up now. Don't you dare break this today. {workout_type} + {study_target} study + {meals_target} meals. Standard operating procedure.
- **S:** {streak_days} days. Big deal. The real question is whether you have {streak_days} + 1 in you, or if today's the day you prove it was all a fluke. Same tasks as always. No special treatment for milestones. Vai.

**6. Monday (start of week)**

`notif.morning.monday`

- **G:** Happy Monday, {name}! Fresh week ahead. Last week's score: {weekly_score}. This week, let's aim even higher. {workout_type} day to start. You set the tone today!
- **F:** Monday. New week. Last week: {weekly_score}. This week's target: higher. {workout_type} today. {tasks_total} non-negotiables. Start strong.
- **D:** New week. Clean slate. Last week's score: {weekly_score}. This week we're hitting 90+. {workout_type} today, {study_target} study, {meals_target} meals. Monday sets the tone for everything. Set it right.
- **S:** Monday. Last week you scored {weekly_score}. Was that acceptable to you? Because it wasn't to me. New week, new chance to not be mediocre. {workout_type}. {study_target} study. {meals_target} meals. Basta scuse.

**7. Weekend (Saturday or Sunday)**

`notif.morning.weekend`

- **G:** Good morning, {name}! It's {day_of_week} -- enjoy your weekend, but remember your targets are still there. {workout_type} and {study_target} study are on the plan. Hit them early and enjoy the rest of your day!
- **F:** {day_of_week}. Weekend, not a holiday from your targets. {workout_type}. {study_target} study. {meals_target} meals. Same standards, different day.
- **D:** Weekend doesn't mean day off. Recovery is {recovery_score}% -- solid enough for {workout_type}. Study target stays at {study_target}. I don't care if your friends are at brunch. Hit your numbers first, then enjoy your {day_of_week}.
- **S:** {day_of_week}. While everyone else sleeps until noon and wastes the day, you have {tasks_total} non-negotiables waiting. Or you could join the average people. Your choice. But we both know what happens to your streak if you do.

**8. After bad sleep (sleep score < 60%)**

`notif.morning.bad_sleep`

- **G:** Tough night, {name}? {sleep_hours} of sleep isn't ideal. Recovery is at {recovery_score}%. Today's workout is lighter. Take it easy, but still hit your study and meal targets. Tonight, let's get to bed earlier.
- **F:** {sleep_hours} of sleep. Recovery: {recovery_score}%. Reduced training today. Study and meals unchanged. Prioritize an early bedtime tonight.
- **D:** {sleep_hours} of sleep. That's embarrassing. What time did you put the phone down last night? Recovery is tanked at {recovery_score}%. Mobility only today. But I want {study_target} of study since you'll have extra time. Fix your bedtime tonight.
- **S:** {sleep_hours}. Your phone screen time probably explains it. Recovery is {recovery_score}% because you chose doom-scrolling over discipline. No real training today. But you WILL study. And tonight, phone goes face-down by 10 PM. Your future self is begging you.

**9. After perfect previous day (100% completion)**

`notif.morning.after_perfect`

- **G:** Amazing work yesterday, {name}! 100% of everything done. Let's keep that energy going today. {workout_type}, {study_target} study, {meals_target} meals. You're on a roll!
- **F:** Yesterday: 100%. Clean sheet. Today: {workout_type}, {study_target} study, {meals_target} meals. Match yesterday's standard.
- **D:** Yesterday: 100%. Every non-negotiable crushed. That's the standard now. Today: {workout_type}, {study_target} study, {meals_target} meals. Repeat what you did yesterday. Champions don't have off days after on days.
- **S:** 100% yesterday. Congratulations, you did the bare minimum you promised yourself. Don't expect a trophy. Do it again today. And tomorrow. And every day until it stops feeling like an achievement and starts feeling like breathing. {workout_type}. Go.

**10. After missed targets yesterday (<75%)**

`notif.morning.after_miss`

- **G:** Yesterday was tough -- {tasks_done} of {tasks_total} done. That's okay, today is a new day. Let's bounce back. {workout_type}, {study_target} study, {meals_target} meals. One day at a time.
- **F:** Yesterday: {tasks_done}/{tasks_total}. Below standard. Today: reset. {workout_type}, {study_target} study, {meals_target} meals. Every task gets done.
- **D:** Yesterday: {tasks_done} out of {tasks_total} non-negotiables. Not good enough. You know it. I know it. Today we fix it. Every single task gets done. No negotiations, no "I'll do it tomorrow." Today.
- **S:** {tasks_done} out of {tasks_total} yesterday. That's a {completed_pct} completion rate. In what world is that acceptable? You made promises to yourself and broke them. Today you either prove yesterday was a fluke, or you prove it's who you are. Which is it?

**11. After multi-day miss (3+ days below 75%)**

`notif.morning.multi_day_miss`

- **G:** Hey {name}, I know it's been a rough few days. But every day is a chance to start fresh. Don't think about the streak -- just focus on today. What's one thing you can get done this morning?
- **F:** {streak_days} days below target. Pattern forming. Today: break it. Start with one task. Build from there.
- **D:** 3+ days of missed targets. This is becoming a habit, and not the good kind. Something needs to change. Open Tempo. Look at your non-negotiables. If they're too aggressive, recalibrate. If they're right and you're just slacking -- that ends today.
- **S:** Days of failure are stacking up. At some point you have to ask yourself: are you using this app, or is it just watching you fail? Either lower your targets to something you'll actually do, or grow a spine and hit them. No more in-between. Sveglia.

**12. High recovery + rest day scheduled**

`notif.morning.high_recovery_rest_day`

- **G:** Recovery is at {recovery_score}% today -- awesome! It's a scheduled rest day, so enjoy the physical recovery. Focus on study ({study_target}) and nutrition ({meals_target} meals). Recharge!
- **F:** Recovery: {recovery_score}%. Rest day. No training, but study and meals are full targets. Use the energy for focused academic work.
- **D:** Recovery at {recovery_score}%. Rest day on the schedule but your body is green-lit. If you want to throw in a light session, the gains are there. Otherwise, channel that energy into study. {study_target} minimum. No wasting a good recovery day on the couch.
- **S:** {recovery_score}% recovery and a rest day. How convenient. Your body is ready to work and you've given yourself permission to do nothing. Study better be exceptional today. I want {study_target} minimum and I want it done by 3 PM. No excuses when you're this rested.

**13. Game day / team sport day**

`notif.morning.game_day`

- **G:** Game day! Focus on fueling well -- your {meals_target} meals are extra important today. Keep study light if you need to. Good luck out there, {name}!
- **F:** Game day. No gym. Fuel properly: {meals_target} meals, prioritize carbs. Study: {study_target} still applies. Perform.
- **D:** Game day. No gym -- your strain comes from the pitch today. But {study_target} study still happens, and {meals_target} meals are mandatory. Eat carbs 3 hours before kickoff. Hydrate. Perform. No excuses for missing study because of a game.
- **S:** Game day. If you haven't eaten properly by now, you've already lost. {meals_target} meals. Study happens before the game, not "after" -- we both know "after" means never. Win or lose, your non-negotiables don't care about the score.

**14. Rainy/bad weather day (location-aware, if available)**

`notif.morning.bad_weather`

- **G:** Looks like it's not great weather today. Perfect for an indoor focus day! {workout_type} at the gym and a solid {study_target} study session. Make the most of it.
- **F:** Weather's bad. No excuse to skip the gym -- it's indoors. {workout_type}. {study_target} study. {meals_target} meals. Weather doesn't change the plan.
- **D:** Rain outside. Good. One less reason to be anywhere but the gym and the library. {workout_type}. {study_target} study. {meals_target} meals. Bad weather is a gift to disciplined people.
- **S:** Raining? Good. Now you can't pretend you were going to "go for a walk" instead of studying. Gym. Books. Food. That's your world today. The weather agrees with me: stay inside and get to work.

**15. First day of the month**

`notif.morning.first_of_month`

- **G:** New month, {name}! Fresh start. What do you want this month to look like? Set your intention and let's make it happen. Starting with today: {workout_type}, {study_target} study, {meals_target} meals.
- **F:** New month. Last month's average: {weekly_score}. This month: raise it. {workout_type} today. Full targets. Start strong.
- **D:** First of the month. Last month is dead. Whatever you did or didn't do -- irrelevant. What matters is what you do in the next 30 days. Starting today. {workout_type}. {study_target} study. {meals_target} meals. Set the standard.
- **S:** New month. Same you, unless you decide otherwise. Last month's score was {weekly_score}. Was that the best you could do? Really? 30 fresh days to prove you're not coasting through life. Day 1. Go.

**16. Friday (end of academic week)**

`notif.morning.friday`

- **G:** Happy Friday, {name}! Last push of the academic week. Finish strong with {study_target} study and {workout_type}. You've earned a great weekend -- almost there!
- **F:** Friday. End of the academic week. {workout_type}. {study_target} study. Finish the week at full capacity.
- **D:** Friday. I know you can smell the weekend. But today isn't the weekend yet. {workout_type}. {study_target} study. {meals_target} meals. Finish the week like you started it. Strong finishes build strong habits.
- **S:** Friday. The day everyone mentally checks out. Not you. {workout_type} gets done. {study_target} study gets done. You can celebrate when the scoreboard says 100%. Until then, it's just another day you need to prove something.

**17. User birthday (if known from Apple ID)**

`notif.morning.birthday`

- **G:** Happy birthday, {name}! Enjoy your day. Your non-negotiables are still here, but today's about balance. Hit what you can and celebrate.
- **F:** Happy birthday. Non-negotiables don't take the day off, but you've earned some flexibility. {workout_type} and {study_target} study. Make it a good one.
- **D:** Happy birthday. Here's your gift: the same {tasks_total} non-negotiables as every other day. Birthdays don't build muscle or pass exams. Get it done, then celebrate. You've earned it -- when the tasks are complete.
- **S:** Buon compleanno. Know what the best birthday gift is? Not breaking your {streak_days}-day streak because you decided cake is more important than discipline. Train. Study. Eat. Then celebrate. Or don't do any of it and add "wasted birthday" to the list.

**18. Day after user adjusted non-negotiables**

`notif.morning.new_targets`

- **G:** New targets are live! You adjusted your non-negotiables yesterday. Today is the first day with the new plan. {tasks_total} tasks. Let's see how it feels!
- **F:** New targets active. {tasks_total} non-negotiables today. The bar is set. Meet it.
- **D:** New targets, day one. You recalibrated -- good. But these new numbers are now the minimum. No adjusting again for at least a week. Prove you can hit them consistently first. {workout_type}. {study_target} study. Go.
- **S:** You changed your targets. Let's hope it's because you're raising the bar and not because you're looking for an easier life. {tasks_total} non-negotiables. New numbers, same expectations: 100%. No grace period.

**19. Low HRV trend (declining over 5+ days)**

`notif.morning.hrv_declining`

- **G:** Heads up, {name}: your HRV has been trending down for a few days. Your body might need extra rest. Today's workout is adjusted. Focus on recovery, sleep, and nutrition.
- **F:** HRV declining 5+ days. Could be overtraining, stress, or poor sleep. Reduced training today. Prioritize recovery. If this continues, consider a deload week.
- **D:** HRV trending down for 5 days straight. Your body is sending a warning. Today: reduced volume. Extra hydration. Caffeine cutoff at 1 PM. Bed by 10. If you ignore this pattern, you'll end up injured or sick. I'm not being dramatic. Listen.
- **S:** Your HRV is in free fall. 5 days of decline means something is seriously wrong with your recovery. Are you sleeping? Eating? Or just grinding yourself into dust? Light training only. If your ego can't handle a deload, your body will force one -- and it won't be on your terms.

**20. First morning after connecting Whoop**

`notif.morning.first_whoop`

- **G:** Your first recovery-powered morning briefing! Recovery: {recovery_score}% ({recovery_zone}). From now on, Tempo adjusts your training based on how your body actually feels. Welcome to smart training, {name}!
- **F:** First Whoop-powered briefing. Recovery: {recovery_score}%. {recovery_zone} zone. Training is now recovery-adaptive. Today: {workout_type}. Evidence-based programming starts now.
- **D:** First morning with Whoop data. Recovery: {recovery_score}%. Your body finally has a voice in this conversation. {workout_type} is calibrated to your actual recovery, not guesswork. {tasks_total} non-negotiables. Now we're operating with real intel.
- **S:** Recovery: {recovery_score}%. First real data point. No more "I feel fine" lies. The numbers don't negotiate. {recovery_zone} zone means {workout_type} at adjusted intensity. Welcome to accountability backed by biometrics. Nowhere to hide now.

**21. Morning after a PR or great workout**

`notif.morning.after_pr`

- **G:** You crushed it in the gym yesterday! That PR shows the hard work is paying off. Today: recovery matters. {workout_type} is scheduled. Keep the momentum going!
- **F:** PR yesterday. Good. Don't let it make you complacent. {workout_type} today. Same discipline as every day.
- **D:** PR yesterday. That's what happens when you show up consistently and push hard. Don't ride that high into a lazy day. {workout_type} is on deck. {study_target} study. The grind doesn't pause for celebrations.
- **S:** You hit a PR. One good day. Want a standing ovation? The weight room doesn't care about yesterday's numbers. It only cares about today's. {workout_type}. {study_target} study. Move.

**22. Morning after user overrode accountability (tapped Override)**

`notif.morning.after_override`

- **G:** Yesterday you used your override -- that's okay, it's there for a reason. Today is a fresh start. Let's get back to 100%. {workout_type}, {study_target} study, {meals_target} meals.
- **F:** Override used yesterday. Streak reset. Today: full commitment. {workout_type}, {study_target} study, {meals_target} meals. No override today.
- **D:** You hit the override button last night. Your streak is gone. Your XP took a hit. Was it worth it? Today you rebuild. From scratch. {workout_type}. {study_target} study. {meals_target} meals. Every. Single. One.
- **S:** Override used. Streak: gone. {streak_days} days erased. 50 XP lost. You chose to stop. Today the counter says zero. The only thing that matters now is whether zero stays zero or becomes one. {workout_type}. {study_target} study. {meals_target} meals. Rebuild.

**23. Whoop not connected, general morning**

`notif.morning.no_whoop`

- **G:** Good morning, {name}! No recovery data today (connect Whoop for personalized insights). {workout_type} day. {study_target} study. {meals_target} meals. Have a great day!
- **F:** Morning. No recovery data. {workout_type}. {study_target} study. {meals_target} meals. Default intensity. Connect Whoop for adaptive training.
- **D:** Morning briefing. No recovery data -- I'm flying blind on your body's readiness. {workout_type} at standard intensity. {study_target} study. {meals_target} meals. {tasks_total} non-negotiables. You'd get a better briefing if I could see your recovery score. Just saying.
- **S:** No recovery data. Again. You're training blind. I'm programming blind. If you had a Whoop, I'd know whether to push you or protect you. Instead, we're guessing. {workout_type} at default. If you gas out, that's on you for not connecting your data.

**24. Morning after leaderboard position change**

`notif.morning.leaderboard_change`

- **G:** Heads up: {friend_name} is now ahead of you on the weekly leaderboard! You're at {leaderboard_rank}. A strong day today could change that. {workout_type} + {study_target} study. Let's go!
- **F:** {friend_name} passed you on the leaderboard. You're {leaderboard_rank}. {xp_gap} XP behind. Full day of targets closes that gap.
- **D:** {friend_name} just took your spot on the leaderboard. You're {leaderboard_rank} now. {xp_gap} XP gap. That's one perfect day of difference. {workout_type}. {study_target} study. {meals_target} meals. Take it back.
- **S:** {friend_name} is ahead of you. Let that sting. While you were sleeping, they were earning XP. You're {leaderboard_rank} and falling. {xp_gap} XP gap. Are you going to let {friend_name} outwork you? Prove otherwise. Every task. No misses.

**25. Exam day**

`notif.morning.exam_day`

- **G:** Today's the day -- {exam_name} exam! You've prepared for this. Trust your work. Light training only. Eat well, stay hydrated, and go in confident. You've got this, {name}!
- **F:** {exam_name} exam today. You've put in the hours. Light training only. Good nutrition. Stay calm, stay focused. Perform.
- **D:** {exam_name} exam today. Everything you studied comes down to this. Light training only -- save your energy for your brain. Eat a solid breakfast. Hydrate. Walk in there knowing you did the work. Because you did. Now execute.
- **S:** {exam_name}. Today. If you studied, you're ready. If you didn't, that's your own fault and no morning briefing is going to save you. Light workout. Eat. Go crush it. Or don't. The grade you get is the grade you earned.

**26. After challenge accepted from friend**

`notif.morning.active_challenge`

- **G:** Reminder: you're in a challenge with {friend_name} this week! Current standing looks close. Give today your best to pull ahead. {workout_type} + {study_target} study.
- **F:** Active challenge vs {friend_name}. Every task today counts toward the score. {workout_type}. {study_target} study. No freebies.
- **D:** You accepted {friend_name}'s challenge. Today every non-negotiable is a weapon. {workout_type} -- XP. {study_target} study -- XP. {meals_target} meals -- XP. Dominate today and the challenge is yours.
- **S:** You told {friend_name} you could beat them. Day {streak_days} of the challenge. Are you winning? If not, today is the day that changes. Or the day you prove you were all talk. {tasks_total} tasks. All of them. No mercy.

**27. Semester break / no classes**

`notif.morning.break_period`

- **G:** No classes today! Great time to focus on training and personal goals. {workout_type} is on the plan. Maybe use extra time for deeper study or a passion project.
- **F:** Break period. No classes. Training: full intensity. Study: use the time for exam prep or skill building. {meals_target} meals. Discipline doesn't take breaks.
- **D:** No classes. That means MORE time for training and study, not less. {workout_type} at full intensity. {study_target} study -- no excuses about scheduling. {meals_target} meals. People improve during breaks. Lazy people fall behind during breaks. Choose.
- **S:** Break. No classes. The perfect excuse to waste an entire day. I've seen it before. You'll "relax" until 3 PM, panic, half-do a workout, skip studying, and order pizza. Or you could prove me wrong. {workout_type}. {study_target} study. {meals_target} meals. All done by 2 PM. Dai, muoviti.

**28. User returned after 1+ day absence (re-engagement)**

`notif.morning.welcome_back`

- **G:** Welcome back, {name}! We missed you. Whatever happened, today is what matters. {workout_type}, {study_target} study, {meals_target} meals. Let's pick up where you left off.
- **F:** You're back. {tasks_total} non-negotiables waiting. {workout_type}. {study_target} study. No looking backward. Forward.
- **D:** You've been gone. The streak is broken. The leaderboard moved on without you. But you're here now, and that's what matters. {workout_type}. {study_target} study. {meals_target} meals. Day 1 of the new streak starts now. Make it count.
- **S:** So you decided to show up. How generous of you. While you were away, {friend_name} climbed the leaderboard and your streak died. Day 0. Rock bottom. The only direction from here is up -- if you actually do the work this time. {tasks_total} non-negotiables. Go.

**29. End of semester / finals approaching**

`notif.morning.finals_season`

- **G:** Finals season is here. You've got this, {name}. Training is scaled back to prioritize study. Focus: {study_target} daily. Your health still matters -- keep eating well and getting enough sleep.
- **F:** Finals mode. Training: maintenance only. Study: {study_target} minimum. Nutrition: critical for brain function. Sleep: non-negotiable. This is the final push.
- **D:** Finals season. The next two weeks define your semester. Training is at maintenance -- 3 sessions max this week. Study is the priority. {study_target} is the MINIMUM. If you've been consistent all semester, you're ready. If you haven't, time to cram like your GPA depends on it. Because it does.
- **S:** Finals. The moment of truth. All those study hours either add up to something or they don't. Training is irrelevant -- maintenance only. If I see you at the gym for longer than 45 minutes this week, I'll know you're procrastinating. Books. {study_target}. Every single day. No days off until exams are done.

**30. Perfect sleep night (sleep score > 90%)**

`notif.morning.perfect_sleep`

- **G:** Wow -- {sleep_hours} of beautiful sleep! Recovery is at {recovery_score}%. Your body is fully charged. Today is going to be a great day. {workout_type} + {study_target} study.
- **F:** Sleep: {sleep_hours}, score above 90%. Recovery: {recovery_score}%. Peak conditions. Full intensity on everything today.
- **D:** {sleep_hours} of elite sleep. Recovery at {recovery_score}%. This is what happens when you follow the prescription. Today you have zero excuses. {workout_type} at full intensity. {study_target} study at full focus. {meals_target} meals on schedule. Days like this are where champions are built.
- **S:** {sleep_hours}. Recovery {recovery_score}%. Finally, a night where you didn't self-sabotage with your phone. Your body gave you everything today. If you waste this day, it's not because you were tired. It's because you're lazy. No hiding behind recovery scores today. Perform.

**31. Caffeine cutoff warning embedded in morning briefing**

`notif.morning.caffeine_note`

- **G:** Quick reminder: to sleep well tonight, try to have your last coffee before {caffeine_cutoff}. Recovery: {recovery_score}%. Have a great day!
- **F:** Caffeine cutoff today: {caffeine_cutoff}. Last night's sleep was affected by late caffeine. Recovery: {recovery_score}%. Adjust.
- **D:** Caffeine cutoff: {caffeine_cutoff}. I saw your recovery data -- last night's sleep quality dropped after you had coffee at 4 PM yesterday. The data doesn't lie. No caffeine after {caffeine_cutoff} today. Your tomorrow self is begging you.
- **S:** No coffee after {caffeine_cutoff}. Period. Your HRV crashed because you thought a 5 PM espresso was a good idea. It wasn't. Your Italian heritage doesn't give you caffeine immunity. Cut it off or keep waking up at {recovery_score}% recovery. Your choice.

**32. Generic fallback (no special conditions)**

`notif.morning.generic`

- **G:** Good morning, {name}! Here's today's plan: {workout_type}, {study_target} study, {meals_target} meals. {tasks_total} things to do. Take it one step at a time. You've got this!
- **F:** Morning. {workout_type}. {study_target} study. {meals_target} meals. {tasks_total} non-negotiables. Execute.
- **D:** Rise and grind. {workout_type} day. {study_target} study. {meals_target} meals. {tasks_total} non-negotiables. The day doesn't wait for you to feel ready. Start.
- **S:** Another day. Same {tasks_total} tasks you committed to. Will today be different from the last time you failed, or are we doing this again? {workout_type}. {study_target} study. {meals_target} meals. Prove something.

---

### Channel 2: Accountability -- Gentle Reminder

**Trigger:** Evening start time minus 5.5 hours (e.g., 2:00 PM if evening is 7:30 PM). Scales with user's configured evening. Only fires if less than 50% of non-negotiables are completed.

**Type:** Standard push (local notification).

**String key prefix:** `notif.accountability.gentle.`

**Logic:**
```
IF completedNonNegotiables / totalNonNegotiables < 0.5 THEN fire
ELSE suppress (no notification)
```

**Actions:** "Start Study" (opens FocusTimerView), "View Tasks" (opens LockdownView)

#### Copy Variations — 30 contexts x 4 intensities

**1. General (study + training remaining)**

`notif.accountability.gentle.general`

- **G:** Hey {name}, afternoon check-in! Study: {study_done} of {study_target} done. Training: not started. You've got {time_until_evening} before your evening. Plenty of time!
- **F:** 2 PM. Study: {study_done}/{study_target}. Training: pending. {time_until_evening} remaining. Time to focus.
- **D:** Afternoon check-in. Study: {study_done} of {study_target} done. Training: not started. You've got {time_until_evening} before your evening. That's more than enough. Start now.
- **S:** It's 2 PM. Study: {study_done}. Training: zero. {time_until_evening} left and you've done nothing meaningful. What exactly have you been doing all morning? Dai, muoviti.

**2. Only study remaining**

`notif.accountability.gentle.study_only`

- **G:** You trained today -- nice! Study is at {study_done} of {study_target} though. How about a 25-minute focus session to get started? You'll feel great after.
- **F:** Training done. Study: {study_done}/{study_target}. Start a 25-minute block now.
- **D:** You trained this morning. Good. But study is at {study_done}. {study_target} doesn't log itself. Open the timer. Start a 25-minute block. That's all I'm asking right now.
- **S:** Gym done, brain ignored. {study_done} of {study_target} study logged. Your muscles don't pass exams. Open the books or keep pretending the gym is the only thing that matters.

**3. Only training remaining**

`notif.accountability.gentle.training_only`

- **G:** Study and meals are looking good! Just training left on the board. A {workout_type} session whenever you're ready. You've got {time_until_evening}.
- **F:** Study done. Meals on track. Training: pending. {workout_type} needs to happen today.
- **D:** Meals are on track. Study is done. But you haven't trained. Your {workout_type} is waiting. Get to the gym or I'm bringing it up again at 5.
- **S:** Everything except training. How convenient that the hardest task is the one you're avoiding. {workout_type}. Get up. Go. Or admit you're scared of the barbell.

**4. Only meals remaining**

`notif.accountability.gentle.meals_only`

- **G:** Great job on training and study! Meals are at {meals_logged}/{meals_target}. Remember to eat well -- your body needs the fuel!
- **F:** Training and study: done. Meals: {meals_logged}/{meals_target}. Eat and log.
- **D:** You've trained and studied but only logged {meals_logged} of {meals_target} meals. Your body needs fuel. This isn't optional. Eat something real and log it.
- **S:** {meals_logged} meals logged out of {meals_target}. Recovery needs fuel. Training needs fuel. Your brain needs fuel. Eat something real and log it. Two minutes.

**5. Nothing done yet**

`notif.accountability.gentle.nothing_done`

- **G:** Hey {name}, the afternoon is here and we're at a fresh start. {tasks_total} things to tackle. Pick one -- even a small one -- and get the ball rolling.
- **F:** 2 PM. {tasks_done}/{tasks_total} complete. Everything is still ahead of you. Start with one task.
- **D:** It's 2 PM and you haven't started a single non-negotiable. Zero meals logged. Zero study. Zero training. The day is half gone. What are you waiting for?
- **S:** 2 PM. Zero done. Nothing. Niente. Half the day: gone. You set {tasks_total} non-negotiables this morning and haven't touched a single one. This is the kind of day you'll look back on with regret. Unless you change it right now.

**6. Exam approaching + study not done**

`notif.accountability.gentle.exam_study`

- **G:** Friendly reminder: {exam_name} is in {exam_days} days and study is at {study_done} today. Every session counts! How about starting a focus block now?
- **F:** {exam_name}: {exam_days} days away. Study today: {study_done}/{study_target}. Start now.
- **D:** {exam_name} exam in {exam_days} days and you haven't opened a book today. Do you want to walk in there unprepared? Open the study timer. Now.
- **S:** {exam_days} days until {exam_name}. Study today: {study_done}. That's not studying, that's pretending. You're going to bomb this exam and it won't be because you're not smart. It'll be because you chose {time_waster} over your future. Fix it.

**7. Low recovery, lighter training still pending**

`notif.accountability.gentle.low_recovery_training`

- **G:** Recovery is {recovery_score}% so today's session is lighter. Just mobility or a short walk. It's quick and your body will appreciate it!
- **F:** Recovery {recovery_score}%. Mobility session: ~30 minutes. Get it done.
- **D:** Recovery is at {recovery_score}% so today's workout is lighter. But lighter doesn't mean optional. Mobility session takes 30 minutes. Get it done and check it off.
- **S:** Your recovery is {recovery_score}%. I already gave you the easy version -- mobility. 30 minutes. And you still haven't done it? What's the excuse now? Too tired to stretch? Embarrassing.

**8. Weekend version**

`notif.accountability.gentle.weekend`

- **G:** {day_of_week} afternoon check-in! {tasks_done} of {tasks_total} done so far. Hit your targets and the rest of the weekend is all yours!
- **F:** {day_of_week}. {tasks_done}/{tasks_total} done. Weekends aren't exempt. Get to work.
- **D:** {day_of_week} afternoon. No classes to hide behind. {tasks_total} non-negotiables waiting. The weather outside is nice -- great, enjoy it after you've earned it.
- **S:** {day_of_week}. {tasks_done}/{tasks_total}. Your friends are out having fun. You know what they're not doing? Building discipline. Finish your tasks, then go. Or don't finish them and feel guilty all night. Your call.

**9. Streak at risk from laziness**

`notif.accountability.gentle.streak_risk`

- **G:** Your {streak_days}-day streak is still alive! Let's keep it going. {tasks_done}/{tasks_total} done. A solid afternoon session will keep you on track.
- **F:** {streak_days}-day streak. {tasks_done}/{tasks_total}. Don't let the afternoon undo your consistency.
- **D:** You're on a {streak_days}-day streak and only {tasks_done} of {tasks_total} tasks done at 2 PM. Don't let {streak_days} days of work die because of one lazy afternoon.
- **S:** {streak_days} days of discipline, and this is the afternoon that kills it? {tasks_done}/{tasks_total}. Pathetic pace. Your streak doesn't care about your mood. It only cares about results.

**10. Time-waster reference**

`notif.accountability.gentle.time_waster`

- **G:** Quick thought: {time_waster} will be even more enjoyable when your tasks are done! {study_remaining} of study left. Knock it out, then relax guilt-free.
- **F:** {time_waster} later. {study_remaining} study first. The deal is the deal.
- **D:** {time_waster} is not going anywhere. Your study target is. {study_remaining} of focused work now and you'll have the whole evening free. That's the deal. Stick to it.
- **S:** I know what you're doing right now. {time_waster}. While your {study_remaining} study target sits there untouched. You made a deal with yourself this morning. Are you a liar?

**11. After morning workout, study lagging**

`notif.accountability.gentle.post_workout_study_lag`

- **G:** Great workout this morning! Now channel that energy into study. {study_done}/{study_target} so far. Even 25 minutes would make a difference.
- **F:** Training: done. Study: {study_done}/{study_target}. Redirect your focus to academics.
- **D:** You crushed the gym this morning. Endorphins high. Now sit down and study. {study_done} of {study_target}. The physical work is done -- time for the mental work. No more stalling.
- **S:** You trained. Congratulations. Now do the harder thing. {study_done} study logged. You know what? The gym is easy. You lift, you leave. Studying requires actual concentration. That's why you're avoiding it. Stop.

**12. Protein deficit flagged by NutriTrack**

`notif.accountability.gentle.protein_low`

- **G:** NutriTrack shows you're at {protein_current}g of {protein_target}g protein. Your muscles need it! Try to get a high-protein meal or snack in soon.
- **F:** Protein: {protein_current}g/{protein_target}g. Below target. Prioritize protein in your next meal.
- **D:** {protein_current}g of {protein_target}g protein. You're behind. Your next meal needs to be protein-heavy. Chicken, eggs, Greek yogurt -- pick one. Your recovery depends on hitting this number.
- **S:** {protein_current}g protein. You need {protein_target}g. You're basically starving your muscles. That workout you did this morning? Wasted if you don't eat. But sure, skip lunch. See how that works out.

**13. Calendar shows class ending soon**

`notif.accountability.gentle.post_class`

- **G:** Class wrapping up soon? When you're free, {study_remaining} of study and {workout_type} are still on today's list. You've got {time_until_evening}!
- **F:** Class ending. Post-class window: ideal for study. {study_remaining} remaining. {time_until_evening} until evening.
- **D:** Your class ends in 15 minutes. Don't go home and sit on the couch. Go directly to the library. {study_remaining} of study is waiting. Momentum matters -- don't lose it.
- **S:** Class is almost over. The gap between class ending and you actually being productive is where your day dies. Don't go home. Don't check your phone. Library. Now. {study_remaining} of study. No detours.

**14. User is at gym (inferred from location/workout active)**

`notif.accountability.gentle.at_gym`

- *Suppressed* -- don't notify while user is working out. Queue for 15 minutes after workout ends.

**15. Multiple tasks remaining, close to evening**

`notif.accountability.gentle.time_crunch`

- **G:** Hey {name}, {tasks_total - tasks_done} tasks still to go and your evening starts at {evening_start}. Start with the quickest one to build momentum!
- **F:** {tasks_total - tasks_done} tasks. {time_until_evening} left. Prioritize. Start now.
- **D:** {tasks_total - tasks_done} tasks left. {time_until_evening} on the clock. That's going to be tight. Stop reading this notification and start doing something. Anything. NOW.
- **S:** {tasks_total - tasks_done} tasks. {time_until_evening}. You've engineered your own crisis. Every minute you spend not working is a minute you're choosing to fail. Is this really how you operate?

**16-30. Additional contextual variations:**

**16. Friend just completed all tasks (Arena trigger)**
- **G:** {friend_name} just hit 100% for today! You're at {completed_pct}. A little friendly competition never hurt.
- **F:** {friend_name}: 100% done. You: {completed_pct}. Step up.
- **D:** {friend_name} already cleared all non-negotiables today. You're at {completed_pct}. Are you going to let them outwork you? Move.
- **S:** {friend_name} is done. All tasks. Complete. Meanwhile you're at {completed_pct}. They're better than you today. Unless you change that in the next {time_until_evening}.

**17. User opened app but didn't start any task**
- **G:** You opened Tempo earlier but didn't start anything -- that's okay! Sometimes getting started is the hardest part. Try just 5 minutes of study.
- **F:** You checked in but didn't act. Action > awareness. Start one task.
- **D:** You opened the app, looked at your tasks, and closed it. Looking at a to-do list doesn't complete it. Start the study timer. 5 minutes. Then 5 more. That's how it works.
- **S:** You opened Tempo. You saw the tasks. You closed Tempo. Is that your strategy? Look at failure and walk away? Start something. ANYTHING. Or was opening the app the accomplishment for today?

**18. Day after traveling or disrupted schedule**
- **G:** Schedule a bit off today? That's fine! Adapt and do what you can. Even a partial day beats a zero day. {tasks_total} targets are flexible.
- **F:** Disrupted day. Adjust, don't abandon. Hit what you can.
- **D:** Weird schedule today? Doesn't matter. Adapt. The non-negotiables are called non-negotiable for a reason. Find the windows. Use them. Even a modified session counts more than nothing.
- **S:** Busy day? Welcome to adulthood. Everyone is busy. Winners find time. Losers find excuses. {tasks_total} tasks. Figure it out.

**19. Calorie deficit detected (NutriTrack)**
- **G:** You're at {calories_current} of {calories_target} calories. Make sure to eat enough -- under-eating hurts recovery and focus!
- **F:** Calories: {calories_current}/{calories_target}. Under-eating. Your next meal should make up the gap.
- **D:** {calories_current} of {calories_target} calories. You're in a deficit you didn't plan. That means less energy for training and less focus for study. Eat more. Now. Not later.
- **S:** {calories_current} calories out of {calories_target}. Your brain and muscles are running on fumes. That study session you're about to do? Half as effective without fuel. Eat something substantial. Now.

**20. Almost done (1 task remaining)**
- **G:** So close! Just 1 task left. {study_remaining} of study and you're at 100% for the day!
- **F:** 1 task remaining. Finish it.
- **D:** One task away from clearing the board. {study_remaining} left. Don't come this close and walk away. Finish.
- **S:** 1 task. One. And you're still not doing it. What's the holdup? It's literally one thing. Do it or admit you can't even handle the minimum.

**21. Humidity/heat advisory (weather-aware training)**
- **G:** Hot day! Stay hydrated during your {workout_type} session. Bring extra water and take breaks as needed.
- **F:** High temperature. Hydrate before, during, and after training. Reduce intensity if needed.
- **D:** It's hot out. That's not an excuse to skip training -- it's a reason to hydrate better. Extra water. Shorter rest periods. Get it done safely but get it done.
- **S:** It's hot. So what? Champions train in all conditions. Hydrate and go. If the heat scares you more than missing your targets, you have bigger problems than the weather.

**22. Study session partially done (>25% but <50%)**
- **G:** Good start on study! {study_done} done. Keep going -- the hardest part was starting. A couple more sessions and you're there.
- **F:** Study: {study_done}/{study_target}. Started but not finished. Keep the momentum.
- **D:** {study_done} of study logged. You started. Good. But starting doesn't earn the checkmark. Finishing does. Back to the books.
- **S:** {study_done}. Started and stopped. Classic. The starting wasn't the hard part -- the continuing is. But you already knew that, didn't you? Resume or reset to zero. Your choice.

**23-30. Rapid-fire contextual variations (Drill Sergeant only, other intensities follow same pattern):**

**23. After receiving a friend request:**
- **D:** Someone wants to compete with you. Better make sure today's numbers are worth showing. {tasks_done}/{tasks_total}. Let's make that profile look good.

**24. Monday after a bad week:**
- **D:** New week. Last week was {weekly_score}. That's behind you. But only if today is different. {tasks_total} non-negotiables. All of them. Start the week right.

**25. Afternoon after morning class:**
- **D:** Classes are done for the day. The rest is yours to use or waste. {study_remaining} study left. {workout_type} pending. Your campus library is open. Go.

**26. User's study app timer hasn't been started:**
- **D:** The study timer hasn't been opened today. Zero minutes. The books aren't going to open themselves. Tap "Start Study" on this notification. I made it easy for you.

**27. After a loss in Arena challenge:**
- **D:** You lost last week's challenge to {friend_name}. The only response to a loss is a better week. Start now. {tasks_total} non-negotiables. No repeat.

**28. Creatine/supplement reminder (if tracked):**
- **D:** Side note: did you take your creatine today? 5g. It takes 10 seconds. Don't skip the small things.

**29. Training day after rest day:**
- **D:** Yesterday was rest. Today your body is primed. {workout_type} at full intensity. No easing in. Hit it hard.

**30. End of add/drop period (academic milestone):**
- **D:** Course schedule is locked in. No more changes. {study_target} daily for each course you committed to. This is the lineup. Let's execute.

---

### Channel 3: Accountability -- Firm Warning

**Trigger:** Evening start time minus 2.5 hours (e.g., 5:00 PM if evening is 7:30 PM). Scales with user's configured evening. Only fires if less than 75% of non-negotiables are completed.

**Type:** Time Sensitive push (local notification).

**String key prefix:** `notif.accountability.firm.`

**Logic:**
```
IF completedNonNegotiables / totalNonNegotiables < 0.75 THEN fire
ELSE suppress
```

**Actions:** "Start Now" (opens FocusTimerView or appropriate module), "View Tasks" (opens LockdownView)

#### Copy Variations — 30 contexts x 4 intensities

**1. General (multiple tasks remaining)**
- **G:** Evening's approaching, {name}. {tasks_total - tasks_done} tasks still to go. It would be great to get them done before {evening_start}. Which one can you start right now?
- **F:** 5 PM. {tasks_total - tasks_done} tasks incomplete. Study: {study_done}/{study_target}. {time_until_evening} remaining. Time is running.
- **D:** It's 5 PM. {tasks_total - tasks_done} tasks incomplete. Study: {study_done} of {study_target} done. Training: skipped. Your evening starts in {time_until_evening}. You're running out of runway. Move.
- **S:** 5 PM. {tasks_total - tasks_done} tasks. {time_until_evening} left. At this rate, you're going to fail. Not might. Will. Unless you do something dramatic in the next 30 minutes. What's it going to be?

**2. Only study remaining**
- **G:** Training is done -- nice! {study_remaining} of study still to go. A couple of focused blocks and you're free for the evening!
- **F:** 5 PM. Study: {study_done}/{study_target}. {study_remaining} needed. Three 25-minute blocks. Start now.
- **D:** 5 PM. {study_done} of study logged. You need {study_remaining} more. That's three 25-minute blocks. Doable if you start right now. Not doable if you start in an hour. You see where this is going.
- **S:** 5 PM. {study_done} of {study_target}. You've been "about to study" all day, haven't you? The clock doesn't wait for motivation. {study_remaining} or failure. Choose in the next 60 seconds.

**3. Only training remaining**
- **G:** Study and meals look good! Just training left. A {workout_type} session before {evening_start}? You've still got time!
- **F:** 5 PM. Training: not done. {workout_type}. Gym is still open. Go.
- **D:** Still haven't trained. It's 5 PM. The gym closes in 4 hours. A 45-minute session is all you need. Staring at this notification is not a workout.
- **S:** 5 PM. No workout. You've had since 7 AM. Ten hours. And you couldn't find 45 minutes for the gym. Either go NOW or admit today is another day you chose comfort over growth.

**4. Only meals remaining**
- **G:** Training and study are handled! Meals are at {meals_logged}/{meals_target}. Remember to eat -- you've earned it!
- **F:** Meals: {meals_logged}/{meals_target}. Behind schedule. Eat and log your next meal now.
- **D:** {meals_logged} of {meals_target} meals logged. The macros aren't going to hit themselves. Meal 3 was planned for 3 PM. You're 2 hours late. Eat. Log. Move on.
- **S:** You can study but you can't eat? {meals_logged}/{meals_target} meals. Your protein is at {protein_current}g. Your muscles are cannibalizing themselves while you "forget" to eat. It's not hard. Put food in your mouth. Log it. Done.

**5. Everything remaining**
- **G:** It's been a slow start today, {name}. But there's still time! {time_until_evening} until your evening. Pick one thing and start there.
- **F:** 5 PM. {tasks_done}/{tasks_total} complete. Significant tasks remaining. Start immediately.
- **D:** 5 PM. Nothing done. Let that sink in. You set these non-negotiables. You said they were non-negotiable. Prove it wasn't just talk.
- **S:** 5 PM. Zero. You've accomplished literally nothing today. Not one task. Not one meal logged. Not one minute of study. This isn't a bad day. This is a choice. You chose to waste today. Still {time_until_evening} to prove me wrong. I dare you.

**6. Close to being done (1 task left, mostly complete)**
- **G:** You're so close -- {completed_pct}% done! One more push and you've got a perfect day. You can totally finish this!
- **F:** {completed_pct}%. One task away. Finish it.
- **D:** You're at {completed_pct}%. One task away from clearing the board. {study_remaining} of study left. That's one focused session. Finish what you started.
- **S:** {completed_pct}%. Almost there. Almost. The word of people who never quite get it done. Finish the last task or be the person who was "almost" disciplined. Your choice.

**7. Evening approaching fast (< 1h until evening)**
- **G:** Your evening starts soon! {time_until_evening} left. Any task you can squeeze in would be great. Every bit counts.
- **F:** {time_until_evening} until {evening_start}. Study still {study_remaining} short. Urgent.
- **D:** {time_until_evening} until your evening starts and your study is still {study_remaining} short. There's no world where this gets done unless you start THIS SECOND.
- **S:** {time_until_evening}. {study_remaining} of study missing. The math doesn't work. You've run out of time because you wasted it. This is what consequences feel like. Start anyway. Something is better than nothing. Barely.

**8. Light training still not done on red recovery day**
- **G:** Recovery was low today, so your session is light. Just {workout_type} -- it won't take long! You'll feel better after.
- **F:** Reduced session ({workout_type}) still pending. 25 minutes. No excuses.
- **D:** I gave you a lighter day because your recovery was bad. Mobility takes 25 minutes. You can't even do that? Open the app. Do the session. Check the box.
- **S:** I gave you the lightest possible session -- mobility, 25 minutes -- and it's still not done. This is the easiest day you'll ever have. Open the app. Start the session. Prove you can show up even when it's simple.

**9. Competitive angle (Arena friends exist)**
- **G:** FYI, {friend_name} finished all their tasks today! A little friendly rivalry can help. You're at {completed_pct}%.
- **F:** {friend_name}: 100%. You: {completed_pct}%. The leaderboard is watching.
- **D:** {friend_name} already hit 100% today. They're pulling ahead on the leaderboard. Are you really going to let them win because you couldn't do {study_remaining} of studying?
- **S:** {friend_name} is done. You're not. That's the leaderboard gap right there -- it's not talent, it's effort. {friend_name} showed up. You didn't. Still {time_until_evening} to change the story. Or don't, and lose again.

**10. Second consecutive day heading for miss**
- **G:** Yesterday was tough, and today's been slow too. That's okay -- but let's try to break the pattern. Even completing one more task would help.
- **F:** Second day trending toward a miss. Break the pattern now. One task. Start.
- **D:** Second day in a row heading for a miss. Yesterday: {completed_pct}%. Today: on track for worse. Is this who you are now? Two bad days become a habit faster than you think.
- **S:** Two days. Two failures. This is how you lose everything you built. One bad day is an accident. Two is a choice. Three is an identity. Don't become the person who gives up. {tasks_total - tasks_done} tasks. NOW.

**11-20. Additional context variations (Drill Sergeant, pattern applies to all intensities):**

**11. Exam within 48 hours:**
- **D:** {exam_name} is in {exam_days} days. Study is at {study_done}. This is the final stretch. Everything else can wait. Books. Timer. NOW.

**12. After a particularly good workout (high strain):**
- **D:** Great workout today -- strain was high. Now match that physical effort with mental effort. {study_remaining} of study remaining. Prove you're not just a gym bro.

**13. User snoozed or dismissed the Channel 2 notification:**
- **D:** You dismissed my 2 PM reminder. Here's another one. The tasks haven't completed themselves in the last 3 hours. {tasks_done}/{tasks_total}. Ignoring the notification doesn't ignore the deadline.

**14. Calendar shows no more events today:**
- **D:** Your calendar is clear for the rest of the day. No classes. No meetings. Just you and your non-negotiables. {tasks_total - tasks_done} tasks. No scheduling excuse available.

**15. High HRV today (physically primed for training):**
- **D:** HRV is up today -- your body is ready for a great session. Don't waste this physiological window. {workout_type} before {evening_start}. These high-HRV days don't come every day.

**16. First week user (softer even in Drill Sergeant):**
- **D:** Day {streak_days} of Tempo. You're still building the habit. {tasks_done}/{tasks_total} done. The next {time_until_evening} is key. Tip: start with the easiest task to build momentum.

**17. Weekend evening plans likely (Saturday 5 PM):**
- **D:** Saturday 5 PM. I know you're thinking about tonight's plans. {tasks_total - tasks_done} tasks standing between you and a guilt-free evening. Get them done first. Then go.

**18. Sleep debt accumulating (3+ days of bad sleep):**
- **D:** You've underslept 3 nights in a row. Training is lighter but not cancelled. Study still happens. And tonight: bed by {bedtime_target}. This debt compounds. Fix it.

**19. User recently added a new non-negotiable:**
- **D:** You added a new non-negotiable this week. It's still incomplete today. New habits are the hardest to maintain in the first 14 days. Don't let it die on week 1.

**20. Protein timing (post-workout window closing):**
- **D:** You trained 2 hours ago and haven't eaten. The post-workout nutrition window is closing. Protein. Now. At least {protein_target / meals_target}g.

**21-30. Rapid-fire Drill Sergeant variations for remaining contexts:**

**21.** Meal timing behind: "Meal 3 was scheduled for 2 PM. It's 5 PM. Three hours of your body waiting for fuel. Eat."
**22.** Study with Pomodoro suggestion: "{study_remaining} sounds like a lot. Break it down: that's {study_remaining_pomodoros} Pomodoro blocks. Start one. Just one."
**23.** After canceling a planned workout: "You cancelled today's {workout_type}. Fine. Replace it with a 20-min bodyweight session. Something. Anything. Don't make today a zero."
**24.** Hydration reminder embedded: "{tasks_done}/{tasks_total}. Also: have you had enough water today? Dehydration kills focus. Drink 500ml, then start studying."
**25.** Macro imbalance: "Carbs at 80% of target but protein at 40%. Your next meal needs to be pure protein. Fix the ratio."
**26.** Arena challenge day 5 of 7: "Day 5 of your challenge with {friend_name}. You're behind by {xp_gap} XP. Two days to close the gap. Perfect day required."
**27.** After a strong previous week: "Last week you scored {weekly_score}. This week you're trending lower. Don't let a great week be followed by a mediocre one."
**28.** Recovery trending up but tasks lagging: "Your recovery trend is up 12% this week. Your body is improving. Don't let your effort levels lag behind your biology."
**29.** Library/study location nearby (if location available): "You're near the library. Coincidence? I think not. {study_remaining} of study. Walk in. Sit down. Timer on."
**30.** Evening plans in calendar: "I see you have plans at 8 PM. That's {time_until_evening} from now with {tasks_total - tasks_done} tasks. Do the math. Start immediately."

---

### Channel 4: Accountability -- Urgent Alert

**Trigger:** Evening start time minus 1 hour (e.g., 6:30 PM if evening is 7:30 PM). Scales with user's configured evening. Only fires if critical non-negotiables (study, training) are incomplete.

**Type:** Time Sensitive push (local notification).

**Sound:** Custom `tempo_urgent.caf`

**String key prefix:** `notif.accountability.urgent.`

**Logic:**
```
IF any non-negotiable of type study OR train is incomplete THEN fire
// Meal reminders are separate -- this focuses on study and training
```

**Actions:** "Start Study Timer" (opens FocusTimerView, auto-starts), "I'm On It" (dismiss with acknowledgment)

#### Copy Variations — 30 contexts x 4 intensities

**1. Study not done, training done**
- **G:** Hey {name}, study is at {study_done}/{study_target}. Training was great though! Can you fit in a study session before {evening_start}? Even partial progress counts.
- **F:** 6:30. Study: {study_done}/{study_target}. {study_remaining} needed. {time_until_evening} left. Start now.
- **D:** 6:30. Study: {study_done} out of {study_target}. That's {study_remaining} missing. Your evening starts in {time_until_evening}. You are NOT going to make it at this pace. Drop everything. Timer on. NOW.
- **S:** {study_done} of {study_target}. It's 6:30 PM. You trained but you didn't study. Congratulations, you're building a body with nothing in its head. Books. Timer. Right now. Or don't, and explain to yourself tomorrow why you chose biceps over your degree.

**2. Training not done, study done**
- **G:** Study is done -- awesome! Training is still on the list though. Any chance for a quick {workout_type} session before the evening?
- **F:** Study: complete. Training: pending. {workout_type}. Go now or mark it as skipped.
- **D:** 6:30 and you haven't trained. You studied -- good. But the workout isn't going to do itself. 45 minutes. That's all. Go now or it's a skip on your record and -20 XP.
- **S:** Studied but didn't train. The gym was too hard? Too far? Too much effort? 45 minutes is all it takes. Or skip it, take the -20 XP hit, and explain to the leaderboard why {friend_name} is ahead of you. Again.

**3. Both study and training incomplete**
- **G:** Both study and training are still open. It's a lot, but {time_until_evening} is enough for at least one. Which would you like to tackle first?
- **F:** Study and training both incomplete. {time_until_evening} left. Pick one, start immediately, then do the other.
- **D:** 6:30. Study incomplete. Training incomplete. This is a disaster in slow motion. Pick one. Start it RIGHT NOW. Then do the other. You have {time_until_evening} to save this day.
- **S:** Study: not done. Training: not done. It's 6:30 PM. What have you accomplished today? Seriously. Name one thing. {time_until_evening} left and two major tasks. This is what failure looks like before it's official. Change it or own it.

**4. Close to study target (>75% done)**
- **G:** You're almost at your study target! {study_done} of {study_target}. Just {study_remaining} more. You're so close -- push through!
- **F:** Study: {study_done}/{study_target}. {study_remaining} remaining. One session. Finish.
- **D:** 6:30. You're at {study_done} of study. {study_remaining} more to hit target. That's ONE focused block. Don't come this close and quit. Finish.
- **S:** {study_done} out of {study_target}. You're {study_remaining} away. You did most of the work and now you're going to quit at the finish line? That's worse than not starting. Finish it or live with being a quitter who was {study_remaining} from success.

**5. Exam within 3 days**
- **G:** {exam_name} is in {exam_days} days! Study today is at {study_done}. Any extra study time you can get in will really help. You've got this.
- **F:** {exam_name} in {exam_days} days. Study today: {study_done}/{study_target}. Insufficient. Every hour counts. Start.
- **D:** Exam in {exam_days} days and you've studied {study_done} today. That's not preparation, that's pretending. Close everything else. Books. Now. Your grade depends on the next 2 hours.
- **S:** {exam_name} in {exam_days} days. {study_done} of study today. You're going to fail this exam. Not because you're stupid -- because you're lazy. Prove me wrong in the next {time_until_evening}. Or don't. The grade won't lie.

**6. Long streak at risk**
- **G:** Your {streak_days}-day streak might be at risk tonight. Completing study would save it. {study_remaining} to go. You've come so far!
- **F:** {streak_days}-day streak at risk. Study: incomplete. Time: limited. Act now.
- **D:** Your {streak_days}-day streak dies tonight if study isn't done. {streak_days} days of discipline, about to be erased by one lazy evening. Is that what you want on your record?
- **S:** {streak_days} days. Gone. Tonight. Because you couldn't study for {study_remaining}. All those mornings you showed up? Meaningless if you quit tonight. Every day of that streak is watching you right now. Don't make them regret existing.

**7. After bad previous day**
- **G:** Yesterday was rough, but today can still be different. There's still time to hit your targets. One task at a time.
- **F:** Missed targets yesterday. Today is trending the same way. Break the pattern. Start one task immediately.
- **D:** You missed targets yesterday. You're about to miss them again today. Two days is a pattern. Three days is a lifestyle. Break the pattern. Right now.
- **S:** Yesterday: failure. Today: heading for failure again. Congratulations, you're building a losing streak. Is this who you are? Two days of excuses becoming three? Or do you have enough spine to change this in the next {time_until_evening}? Sveglia.

**8. Weekend social pressure**
- **G:** It's {day_of_week} evening and I know you have plans! {study_remaining} of study would keep you on track. Even a shortened session helps.
- **F:** {day_of_week} 6:30 PM. Social plans don't override study targets. {study_remaining} first. Then go.
- **D:** It's {day_of_week} 6:30 PM. I know you want to go out. I know your friends are texting. But {study_remaining} of study is still on the board. Do it first. Go out after. That's the deal.
- **S:** Your friends are going out. And you're going with them. Without studying. Without training. Without earning it. You'll have fun tonight and regret tomorrow. Or you could do {study_remaining} of study, {workout_type}, and go out knowing you deserve it. But we both know which one you'll choose, don't we? Prove me wrong.

**9. High recovery wasted**
- **G:** Recovery was {recovery_score}% today -- amazing! But tasks are behind. Use that energy in the next couple hours.
- **F:** Recovery: {recovery_score}%. Tasks: behind. The energy is there. Use it.
- **D:** Recovery was {recovery_score}% today. Green. Your body gave you everything. And you've done almost nothing. That's wasting a good day. The worst kind of waste.
- **S:** {recovery_score}%. Green recovery. Peak readiness. And you've squandered it scrolling your phone. Your body handed you a gift today and you threw it in the trash. {time_until_evening} left to salvage something from the wreckage.

**10. Time-waster personalized**
- **G:** If you can step away from {time_waster} for a bit, {study_remaining} of study would get you to 100% today. It'll still be there when you're done!
- **F:** {time_waster} is not a priority. {study_remaining} of study is. Switch now.
- **D:** I know the {time_waster} is calling. But you haven't earned it. {study_remaining} of study missing. The {time_waster} doesn't move until the timer hits zero.
- **S:** How much {time_waster} time today? Be honest. Now compare that to your {study_done} of study. Your priorities are backwards. Put down the {time_waster}. Pick up the books. Or admit that {time_waster} matters more to you than your future. Basta.

**11-30. Additional Drill Sergeant variations (other intensities follow same pattern):**

**11.** Friend completing tasks: "{friend_name} just logged their {tasks_total}th task. All done. You: {tasks_done}/{tasks_total}. The gap is growing."
**12.** Calorie deficit: "You're {calories_target - calories_current} cal short AND study isn't done. Eat while you study. Two birds. One stone. Move."
**13.** Post-workout window: "You trained 3 hours ago. Still no post-workout meal. And study is at {study_done}. Eat. Study. In that order."
**14.** Good morning routine wasted: "You woke up early. You had the whole day. It's 6:30 PM and the tasks are still there. What happened between 7 AM and now?"
**15.** Active challenge with friend: "Challenge with {friend_name}: you're behind by {xp_gap} XP. Every incomplete task widens that gap. {study_remaining} study = {xp_gap} XP."
**16.** Calendar clear rest of evening: "No events on your calendar tonight. Zero scheduling conflicts. Only conflict is between your ambition and your laziness."
**17.** Third notification today (escalation awareness): "This is the third time today I've reminded you. Study: {study_done}/{study_target}. At what point does a reminder become a warning?"
**18.** Near perfect week except today: "6 days this week at 85%+. Don't let one bad evening ruin a great week. {study_remaining} study. One more push."
**19.** Humidity/weather keeping user from gym: "Can't get to the gym? Fine. Bodyweight in your room. 20 minutes. Push-ups, squats, lunges. No equipment needed. No excuse valid."
**20.** Study done but custom non-negotiable missing: "Study and training done, but your custom non-negotiable '{custom_task_name}' isn't checked. It's on the list for a reason. Do it."
**21.** Approaching personal record for weekly hours: "You're 45 minutes away from your best study week ever. {study_remaining} today would break the record. Legacy opportunity."
**22.** Low strain day despite training plan: "Strain is only at 8.2 and you haven't trained. Your body hasn't worked today. {workout_type}. Even a 30-minute session."
**23.** Multiple meals missed: "{meals_logged}/{meals_target} meals. You've basically fasted today. That's not a diet, that's neglect. Eat something substantial. Now."
**24.** User was active in Arena but not in tasks: "You've been checking the leaderboard but not doing the tasks that put you there. Arena is earned through action, not observation."
**25.** Italian motivational: "Dai, {name}. {study_remaining} di studio. Non puoi mollare adesso. [Translation: {study_remaining} of study. You can't give up now.]"
**26.** Night owl pattern detected: "I know you study better at night. But 'later' has been your excuse all day. Start now. You can continue late if you want. But START."
**27.** After receiving encouragement from friend: "{friend_name} sent you a nudge. Someone believes in you. Prove them right. {tasks_done}/{tasks_total}."
**28.** Pre-finals study intensity: "Finals in {exam_days} days. Study today: {study_done}. Target for finals prep should be {study_target} MINIMUM. This isn't normal mode."
**29.** Recovery prescription compliance: "RecoverIQ recommended light training and extra hydration today. Training: not done. Hydration: unknown. Follow the prescription."
**30.** Generic urgent fallback: "{time_until_evening}. {tasks_total - tasks_done} tasks. Clock is ticking. Every minute of delay is a minute stolen from your evening. Act."

---

### Channel 5: Accountability -- Final Warning

**Trigger:** User's configured evening start time minus 30 minutes. Only fires if any non-negotiable is incomplete.

**Type:** Time Sensitive notification (`.timeSensitive` interruption level). Per Technical Feasibility Audit: Critical Alerts entitlement will not be approved for Tempo.

**Sound:** Custom `tempo_final.caf` at system volume. Note: Time Sensitive notifications respect Silent Mode (unlike Critical Alerts). For users wanting maximum accountability, instruct them to enable "Always Deliver" for Tempo in iOS Settings.

**String key prefix:** `notif.accountability.final.`

**Logic:**
```
IF any non-negotiable is incomplete
AND notification intensity is drill_sergeant OR savage
THEN fire as time-sensitive notification
ELSE IF intensity is firm: fire as time-sensitive
ELSE IF intensity is gentle: fire as standard (or suppress)
```

**Actions:** "Start Now" (opens appropriate module), "Override" (opens confirmation dialog)

**Override flow:** If user taps "Override", app opens and shows:
- "Override tonight's accountability?"
- "Your streak will end. You'll lose 50 XP. Tomorrow starts at -10."
- [Override -- I'm done for today] (destructive red button)
- [Cancel -- I'll finish my tasks] (amber button)

#### Copy Variations — 30 contexts x 4 intensities

**1. Study not done (primary)**
- **G:** Evening's almost here, {name}. Study is at {study_done}/{study_target}. Any amount you can do now would be wonderful. No pressure for perfection.
- **F:** Final check. Study: {study_done}/{study_target}. 30 minutes to evening. Do what you can.
- **D:** FINAL WARNING. 30 minutes until your evening and study is at {study_done} of {study_target}. That's {study_remaining} you owe yourself. Either sit down and work or admit you're choosing to fail today. Your call.
- **S:** 30 minutes. {study_done} of {study_target}. You had ALL DAY. Sixteen waking hours. And you couldn't manage {study_target} of study. What did you do instead? Don't answer -- your screen time tells the story. Last chance. Timer. NOW. Or give up and carry this L into tomorrow.

**2. Training not done**
- **G:** Training is still on the list. Even a short bodyweight session would count! 15-20 minutes is all it takes.
- **F:** No workout logged. 30 minutes left. A bodyweight circuit in your room takes 20 minutes. Do it or skip it.
- **D:** 30 minutes. No workout logged. Not a single set. You can still do a 25-minute bodyweight circuit right now in your room. Or you can skip it. But we both know what that means for your streak.
- **S:** Zero training. Zero sets. Zero reps. Zero effort. You can still do a bodyweight session in your room right now. Or is that also too much to ask? Push-ups, squats, lunges. 20 minutes. Unless your couch has more gravity than your self-respect.

**3. Multiple tasks incomplete**
- **G:** A few tasks are still open. Do what feels manageable -- any progress is good progress. Tomorrow is always a fresh start.
- **F:** Multiple tasks incomplete. 30 minutes. Prioritize: start with the one closest to completion.
- **D:** 30 minutes out. Study incomplete. Meals short. This is what a wasted day looks like in real-time. You're watching yourself fail and doing nothing about it. Change that. RIGHT NOW.
- **S:** Study: incomplete. Training: incomplete. Meals: short. This is a total system failure. You are failing at every single thing you committed to this morning. 30 minutes left and nothing to show for the day. This is rock bottom. Either explode into action or hit Override and live with what that means.

**4. One small task remaining**
- **G:** Just one task left! {study_remaining} and you're done. You're SO close. Go for it!
- **F:** One task. {study_remaining}. 30 minutes. Finish it.
- **D:** One task. That's all that stands between you and a clean day. {study_remaining} of study. You can literally do this before the timer runs out. Don't overthink it. Just start.
- **S:** One task. ONE. {study_remaining}. And you're still not doing it. This is the easiest 100% day you'll ever have and you're about to blow it. Stop thinking. Start doing. NOW.

**5. Long streak about to break (14+ days)**
- **G:** Your incredible {streak_days}-day streak is at risk. Even a small effort now could save it. You've worked so hard for this!
- **F:** {streak_days}-day streak breaks tonight without action. {study_remaining} saves it. Choose.
- **D:** You're about to throw away a {streak_days}-day streak. {streak_days} DAYS. Do you know how many people would kill for that consistency? {study_remaining} of study stands between you and day {streak_days + 1}. Do not let this slip.
- **S:** {streak_days} days of discipline. About to become zero. Because of tonight. {streak_days} mornings you showed up. {streak_days} evenings you earned. All of it rides on {study_remaining} right now. This is the moment that defines whether {streak_days} was a phase or who you are. Finish.

**6-10. Intensity-specific expansions:**

**6. High recovery wasted (Drill Sergeant):**
> This morning, recovery was {recovery_score}%. I told you it was a green light day. It's almost evening now and you've done the bare minimum. You had every advantage today and you squandered it. Last chance to make it right.

**7. Time-waster: PS5/Gaming (all intensities):**
- **G:** I know gaming is tempting tonight. Finishing {study_remaining} of study first means guilt-free play time after!
- **F:** {time_waster} stays off until tasks are done. That's the rule. {study_remaining} study remaining.
- **D:** The {time_waster} stays OFF until these tasks are done. That was the deal you made with yourself. {study_remaining} of study remaining. You either honor your own word or you don't. What kind of person are you?
- **S:** The controller is right there. I know. So are your incomplete tasks. You will pick one up tonight. The question is: will it be the controller or the textbook? One builds your future. The other doesn't. You know which is which. Scegli.

**8. Time-waster: Social Media:**
- **G:** Maybe put the phone down for a bit? {study_remaining} of study and you're golden for the night.
- **F:** Screen time today: high. Study time: low. Close the apps. Open the books. 30 minutes.
- **D:** How much time did you spend scrolling today? Be honest. Now look at your study timer: {study_done} logged. Your screen time report has the receipts. Close the apps. Open the books. 30 minutes left to save this.
- **S:** Your screen time today is probably 4+ hours. Your study time is {study_done}. You're literally choosing to watch other people's lives instead of building your own. That's not relaxing. That's surrendering. Put the phone face-down. NOW.

**9. Time-waster: Netflix/Streaming:**
- **G:** One more episode can wait! {study_remaining} of study first, then you can enjoy streaming guilt-free.
- **F:** Pause the show. {study_remaining} of study. Then resume. The show isn't going anywhere.
- **D:** The next episode will still be there tomorrow. Your exam won't wait. Your study target won't complete itself. You've got 30 minutes and {study_remaining} of work to do. Pause the show. Start the timer.
- **S:** Netflix will still have every show tomorrow. Your {streak_days}-day streak won't exist tomorrow if you don't do {study_remaining} right now. You're choosing fictional characters over your real life. How does that make sense?

**10. Savage-only nuclear option:**
- **S:** Another night, another failure loading up. You set {tasks_total} goals this morning. You've hit {tasks_done}. That's {completed_pct}%. That's an F in any grading system. You have 30 minutes to turn this F into a pass. Or don't. And carry that failure into tomorrow. Again. Like yesterday. Like the day before. Becoming exactly the person you promised yourself you wouldn't be.

**11-30. Additional Drill Sergeant variations (other intensities follow same tone patterns):**

**11.** Exam tomorrow: "{exam_name} TOMORROW. Study: {study_done}. This is the night before the exam and you haven't hit target. Whatever you do in the next 30 minutes might be the difference between passing and failing."
**12.** Friend sent encouragement: "{friend_name} sent you a boost. They believe in you. Now believe in yourself. {study_remaining}. Do it for them if you can't do it for yourself."
**13.** Perfect week at stake: "6 perfect days this week. One evening away from a 7/7 week. {study_remaining}. Don't let perfection slip through your fingers."
**14.** Third consecutive day at risk: "Third day in a row. I'm watching you build a habit of failure. One more day and I can't call it a bad streak -- I'll have to call it who you are. Change it. NOW."
**15.** First week user: "Day {streak_days} of Tempo. This is the test. Most people quit in the first week. {study_remaining} of study stands between you and being most people. Or being different."
**16.** User was active in Arena today: "You checked the leaderboard 4 times today. You sent a challenge. You talked the talk. Now walk the walk. {tasks_done}/{tasks_total}. Finish."
**17.** Custom non-negotiable remaining: "Your '{custom_task_name}' is unchecked. You added it because it mattered. Did it stop mattering since this morning?"
**18.** Night before game day: "Game tomorrow. Your body needs fuel and rest. Log that last meal. Do {study_remaining} of study. Be in bed by {bedtime_target}. Champions prepare the night before."
**19.** End of month: "Last day of the month. Your monthly average is {monthly_avg}%. {study_remaining} of study would push it to {monthly_avg_projected}%. End the month strong."
**20.** User already acknowledged Channel 4: "You tapped 'I'm On It' an hour ago. That was a promise. Time to deliver. {study_remaining}."
**21.** Protein critically low: "Protein at {protein_current}g/{protein_target}g AND study incomplete. You're failing your body AND your brain simultaneously. Eat. Study. 30 minutes. Dual-task."
**22.** Sleep debt + incomplete tasks: "You have {sleep_debt}h of sleep debt and tasks undone. Do {study_remaining} of study and get to bed by {bedtime_target}. Tomorrow's recovery depends on tonight."
**23.** Macro goals met but study isn't: "Nutrition: on point. Training: done. Study: {study_done}/{study_target}. You've proven you can be disciplined today. Now prove it with the books too."
**24.** Italian savage: "Ultima chance. {study_remaining} di studio. O lo fai adesso, o domani te ne penti. Non ci sono altre opzioni. Muoviti."
**25.** Competing in active challenge: "Challenge with {friend_name}. If you miss today, you're mathematically eliminated. {study_remaining}. The challenge dies or you step up."
**26.** Weather kept user indoors all day: "You've been home all day. No commute, no errands, no weather excuses. Just you and your tasks. And still {tasks_done}/{tasks_total}. What's the excuse?"
**27.** Multiple study subjects needed: "You have {study_remaining} across {course_count} subjects. Split it: {study_remaining_per_course} each. Start with {nearest_exam_course}."
**28.** Post-workout but no post-workout meal: "You trained. Good. But no post-workout meal 3 hours later. Your muscles are screaming for protein. Eat AND study. Simultaneously. 30 minutes."
**29.** New personal worst day trending: "This could be your worst day in Tempo history. {completed_pct}%. Even completing ONE more task pulls you off the bottom. Don't set this record."
**30.** User has been on phone (screen time API if available): "Your phone screen time today: probably too many hours. Study time: {study_done}. The phone won. Unless you take 30 minutes right now to fight back."

---

### Channel 6: Accountability -- All Clear

**Trigger:** Immediately when all non-negotiables for the day are marked complete.

**Type:** Standard push (local notification).

**Sound:** Custom `tempo_clear.caf`

**String key prefix:** `notif.accountability.clear.`

**Actions:** "View Stats" (opens DashboardView with today's score)

#### Copy Variations — 30 contexts x 4 intensities

**1. Standard completion**
- **G:** All done, {name}! Every non-negotiable checked off. You've earned a wonderful evening. Enjoy it! You did great today.
- **F:** All clear. {tasks_total}/{tasks_total} complete. Evening earned. Well done.
- **D:** ALL CLEAR. Every non-negotiable done. You earned your evening. Whatever you do next, you do it knowing you handled your business first. Respect.
- **S:** Tasks done. Minimum achieved. Don't celebrate too hard -- this is supposed to be the baseline, not the highlight of your week. But fine. Evening's yours. Don't waste it.

**2. Completed early (before 4 PM)**
- **G:** You're done before 4 PM! Amazing. The rest of the day is completely yours. That planning paid off!
- **F:** All clear before 4 PM. Front-loaded. Efficient. The rest of the day is free.
- **D:** Done before 4 PM. That's the kind of day I like to see. The rest of the afternoon is yours. No guilt. No nagging. You front-loaded the work. That's discipline.
- **S:** Before 4 PM. Interesting -- so you CAN do it when you want to. Remember this energy tomorrow instead of dragging tasks until 7 PM like usual.

**3. Completed just before deadline**
- **G:** Made it! All tasks done right before the evening. Cutting it close, but you got there!
- **F:** All clear. Close to the wire, but complete. Tomorrow: aim for earlier.
- **D:** Cutting it close, but it counts. All tasks done with minutes to spare. A win is a win. But tomorrow, let's not make it a photo finish. Earlier is better.
- **S:** You did it. Barely. With the clock breathing down your neck. Not exactly a masterclass in time management, but technically a clean day. Tomorrow, try not to make it a cardiac event.

**4. Streak milestone**
- **G:** Day {streak_days} -- what a milestone! You should be so proud. {streak_days} days of showing up. That's extraordinary, {name}!
- **F:** Day {streak_days}. Milestone hit. All clear. Keep the streak alive.
- **D:** ALL CLEAR. Day {streak_days} of your streak. That's not luck, that's identity. You're not the same person who started this. The scoreboard proves it. Keep building.
- **S:** Day {streak_days}. The streak continues. You haven't impressed me yet -- talk to me at 100. But {streak_days} is {streak_days} more than most people manage. Keep going. Or don't. Your record doesn't care about my opinion.

**5. After a tough day (red recovery)**
- **G:** Recovery was only {recovery_score}% and you STILL got everything done. That takes real determination. Rest well tonight -- you've earned it.
- **F:** Recovery: {recovery_score}%. All tasks complete despite red zone. Disciplined. Rest well.
- **D:** Recovery was {recovery_score}% and you STILL got everything done. That's what separates you from everyone else. Easy days don't build character. Days like today do. Well done.
- **S:** {recovery_score}% recovery. Red. And you did it anyway. Fine. I'll admit it. That was hard and you didn't quit. Don't let it go to your head. But yeah. Respect. Tonight.

**6. Perfect macros (NutriTrack)**
- **G:** All tasks done AND your nutrition was on point today! Training, study, meals -- the whole package. Beautiful day, {name}!
- **F:** All clear. Macros at {macro_pct}% of target. Full system compliance. Textbook day.
- **D:** All tasks done AND macros are at {macro_pct}% of target. Training, study, nutrition -- the trifecta. This is what peak operation looks like. Enjoy your evening.
- **S:** Tasks done. Macros hit. Training logged. The machine worked today. This is what you're capable of when you stop making excuses. Remember this feeling tomorrow when you're tempted to slack.

**7. Comeback day (after multi-day miss)**
- **G:** Welcome back! First complete day in a while, and that's what matters. Every streak starts with day 1. This is yours!
- **F:** First clean day in {days_since_clean} days. The streak resets here. Build on it.
- **D:** There it is. First clean day in {days_since_clean} days. No lectures from me tonight. Just recognition: you got back on track. That matters more than the streak you lost. Now do it again tomorrow.
- **S:** Finally. A complete day. Took you long enough. {days_since_clean} days of failure and you finally remembered how to show up. Don't congratulate yourself too much. You're at day 1. The bar is literally on the floor. Step over it again tomorrow.

**8. Weekend completion**
- **G:** {day_of_week} and all done! What a way to spend the weekend. Enjoy your evening plans!
- **F:** {day_of_week}. All targets hit. Weekend discipline. Rare. Commendable.
- **D:** {day_of_week}, all non-negotiables done. While everyone else burned the day sleeping in, you handled your targets. The leaderboard notices. Your future self notices. Go have fun.
- **S:** {day_of_week}. All done. Your friends probably did zero productive things today. You did {tasks_total}. The gap between you and them just widened. Enjoy your evening. You've earned the right to be smug about it.

**9. Exam day**
- **G:** All done on exam day! You studied, trained, and ate well even with exam stress. That's real balance. Go crush that exam!
- **F:** Exam day. All targets met. Preparation complete. Perform.
- **D:** Non-negotiables done on exam day. You studied, you showed up, and you still trained. That's operating on a different level. Now go crush that exam.
- **S:** Exam day and all tasks done. Most people skip everything on exam day. You didn't. That's either discipline or stubbornness. Either way, it means you're more prepared than everyone else walking into that room.

**10. Maximum tasks completed (5+ non-negotiables)**
- **G:** {tasks_total} out of {tasks_total}! That's a LOT of tasks and you handled every single one. Incredible effort today!
- **F:** {tasks_total}/{tasks_total}. Full load. Every task complete. Strong day.
- **D:** {tasks_total} out of {tasks_total} non-negotiables. {study_target} study. Full workout. {meals_target} meals logged. That's not a to-do list, that's a statement. You don't just plan -- you execute. All clear, soldier.
- **S:** {tasks_total} tasks. All done. That's a heavy load and you carried it. Not going to lie -- that was a real day's work. Don't let tomorrow's you let today's you down. Stessa energia domani.

**11-30. Additional Drill Sergeant All Clear variations:**

**11.** Responded to urgent notification: "You saw my 6:30 warning and you acted. THAT is the response I want. Alert to action in under an hour. That's how it's done."
**12.** First day completing all tasks: "Your first 100% day on Tempo. This is what it feels like. Remember this. Chase this feeling every single day."
**13.** Competed and won daily against friend: "All clear. And you beat {friend_name} to completion today. +{xp_earned} XP. The leaderboard has been updated."
**14.** Completed despite bad weather/travel: "All tasks done despite a disrupted day. Discipline isn't about perfect conditions. It's about imperfect conditions with perfect effort."
**15.** Hit protein target exactly: "Protein: {protein_current}g of {protein_target}g. Bullseye. Training was effective. Study was effective. Nutrition was effective. Systems are working."
**16.** Completed custom non-negotiable for 7th day: "Your custom non-negotiable '{custom_task_name}' has been completed 7 days in a row. It's becoming a habit. Keep feeding it."
**17.** All clear during finals: "All tasks done during finals week. While everyone else is panic-cramming and neglecting their health, you're balanced. That's your edge."
**18.** First day back after override: "All clear. First complete day since your override. The streak is rebuilding. Day 1 logged. Keep going."
**19.** Completed with Arena challenge active: "All clear. Every task = XP toward your challenge with {friend_name}. Today's haul: +{xp_earned} XP. You're now {leaderboard_position}."
**20.** Evening free, suggesting reward: "All clear. You know what goes great with a clean conscience? Whatever you want. {time_waster}. Go for it. EARNED, not default."
**21.** Completed despite illness/low energy: "You felt terrible today and still showed up. Adjusted the workout. Hit study. Ate right. That's grit. Real grit. Rest well tonight."
**22.** New personal best completion time: "All clear at {completion_time}. That's your earliest all-clear ever. New record. The system is working."
**23.** All tasks + bonus steps/activity: "All clear PLUS you hit {steps_count} steps. Over-delivering. That's bonus XP territory."
**24.** Monday all-clear (week starts strong): "Monday. All clear. The week starts with a win. This is how you set the tone for the next 6 days."
**25.** All clear with 90%+ sleep score last night: "Last night: elite sleep. Today: elite execution. The correlation isn't coincidental. Same bedtime tonight."
**26.** All clear, suggesting tomorrow's prep: "All clear. Before you relax: check tomorrow's plan. {tomorrow_workout_type} is on deck. Meal prep if you can. Future you will be grateful."
**27.** Consecutive perfect day (3+): "{consecutive_perfect_days} perfect days in a row. A mini-streak within the streak. This is operational excellence."
**28.** All clear with high strain: "Strain: {strain_score}. That was a hard physical day. All tasks still done. Recovery tonight is critical. Bed by {bedtime_target}."
**29.** Italian celebration: "Tutto fatto. Bravo, {name}. Serata guadagnata."
**30.** Generic with XP summary: "All clear. +{xp_earned} XP today. Streak: {streak_days} days. Rank: {leaderboard_rank}. The scoreboard is updated. Evening: unlocked."

---

### Channel 7: Meal Reminders

**Trigger:** Pulled from NutriTrack meal schedule. Each planned meal has a scheduled time. Notification fires at that time.

**Type:** Standard push (local notification).

**String key prefix:** `notif.meal.`

**Logic:**
```
FOR each meal in today's NutriTrack plan:
  IF meal.status != "logged" AND currentTime >= meal.scheduledTime:
    schedule notification at meal.scheduledTime
```

**Actions:** "Log Meal" (opens NutriTrack or in-app meal log), "Delay 30min" (reschedules, background action)

#### Copy Variations — 30 contexts x 4 intensities

**1. Standard meal reminder**
- **G:** Time for meal {meal_number}! About {meal_calories} cal and {meal_protein}g protein planned. Enjoy your food, {name}!
- **F:** Meal {meal_number}: {meal_name}. {meal_calories} cal, {meal_protein}g protein. Eat and log.
- **D:** Meal {meal_number}: {meal_name}. Planned for now. ~{meal_calories} cal, {meal_protein}g protein. Your muscles don't grow on wishes. Eat.
- **S:** Meal {meal_number}. {meal_calories} cal. {meal_protein}g protein. Your body is a machine. Machines need fuel. Stop running on empty. Eat. Log. Move on. It takes 30 seconds to log.

**2. Post-workout meal**
- **G:** Great workout! Time to refuel. Your body needs protein right now. Aim for at least {post_workout_protein}g. You've earned a good meal!
- **F:** Post-workout window. {post_workout_protein}g protein minimum within the hour. Eat now.
- **D:** Post-workout meal. Your muscles are screaming for protein. {post_workout_protein}g minimum in the next hour. Don't waste the session by skipping the fuel.
- **S:** You just trained. The anabolic window is open. Every minute without protein is gains you're leaving on the table. {post_workout_protein}g. NOW. Or keep wondering why you don't grow despite training 5 days a week.

**3. Missed meal (30+ min late)**
- **G:** Your {meal_name} was planned for {meal_time}. When you get a chance, try to eat something and log it!
- **F:** Meal {meal_number} is overdue by 30 minutes. Eat and log.
- **D:** {meal_name} was 30 minutes ago. Still not logged. Skipping meals tanks your recovery and your daily score. Eat something and log it.
- **S:** {meal_name} was scheduled for {meal_time}. It's been 30 minutes. Are you fasting, or just lazy? Your protein target doesn't reach itself. Eat something real. Not a snack. A MEAL.

**4. Last meal of the day**
- **G:** Last meal of the day! You need about {remaining_protein}g more protein to hit target. How about some chicken or eggs?
- **F:** Final meal. Protein gap: {remaining_protein}g. Make it count. High-protein options recommended.
- **D:** Final meal of the day. You need {remaining_protein}g more protein to hit target. Make it count. Chicken, eggs, Greek yogurt -- pick your weapon.
- **S:** Last meal. {remaining_protein}g protein gap. If you eat cereal or pizza, you've failed your nutrition for the day. This meal is the difference between hitting your macros and not. Choose wisely. Actually, don't choose -- eat protein.

**5. Macros off track**
- **G:** Heads up on macros: protein is a bit low and carbs are higher than planned. Maybe focus this meal on lean protein?
- **F:** Macro imbalance: protein -{protein_deficit}g, carbs +{carb_surplus}g. Adjust this meal accordingly.
- **D:** {meal_name} time. You're {protein_deficit}g under on protein and over on carbs. Adjust this meal: prioritize lean protein, go easy on the bread. Check NutriTrack for a suggestion.
- **S:** Your macros are a disaster. Protein: {protein_current}g (need {protein_target}g). Carbs: over by {carb_surplus}g. You're eating like someone who doesn't track nutrition. Oh wait, you DO track it -- you're just ignoring the data. Fix it with this meal.

**6. Breakfast reminder**
- **G:** Good morning! Breakfast time. Starting the day with a good meal sets everything up right.
- **F:** Breakfast. Most important meal for morning energy and training performance. Eat.
- **D:** Breakfast. First meal of the day. Don't skip it. Your cortisol is high, your glycogen is depleted, and your brain needs glucose to function. Eat real food. Not just coffee.
- **S:** It's breakfast time. "I'm not hungry in the morning" is not a valid excuse. Your body has been fasting for {sleep_hours}. Feed it or watch your 10 AM energy crash and take your study session with it.

**7. Pre-workout meal (1-2h before training)**
- **G:** Training is in about an hour! Time for a pre-workout meal. Some carbs and moderate protein will fuel your session.
- **F:** Training in 1 hour. Pre-workout meal needed: carbs + moderate protein. ~300-400 cal.
- **D:** Training in an hour. Time for pre-workout fuel. 300-400 cal. Emphasize carbs for energy. Some protein. No heavy fat -- it'll sit in your stomach. Eat now or train on empty. Your choice, but one is smarter.
- **S:** {workout_type} in 1 hour and you haven't eaten your pre-workout meal. You're going to walk into the gym running on fumes. Eat carbs. Now. Or enjoy that lightheaded feeling during your third set of squats.

**8-15. Additional context variations (Drill Sergeant):**

**8.** Eating out: "Eating out today? Fine. But choose smart: protein first, skip the appetizer bread, and log an estimate. Restaurant meals don't excuse lazy nutrition."
**9.** Low calorie day: "You're at {calories_current}/{calories_target} cal. That's a significant deficit. This meal needs to be substantial. Not a snack. A real, calorie-dense meal."
**10.** High calorie day: "Already at {calories_current}/{calories_target} cal. This meal should be lighter: vegetables, lean protein, skip the carb-heavy sides."
**11.** Hydration note: "Meal time. Also: drink water. At least 500ml with this meal. Dehydration mimics hunger and kills recovery."
**12.** Before bed meal: "Evening meal. Keep it light on carbs, moderate protein. Heavy meals too close to bed tank your sleep quality. Whoop will notice."
**13.** Recovery day nutrition: "Recovery day nutrition is crucial. Your body is rebuilding. Protein: {protein_target}g target. Don't cut calories on rest days -- that's when the magic happens."
**14.** Italian meal reference: "Pranzo time. Make it substantial -- this isn't an American snack lunch. Real food. Real portions. {meal_protein}g protein."
**15.** Meal prep suggestion: "If you haven't prepped, now's a good time. 15 minutes of prep saves hours of bad decisions this week."

**16-30. Rapid-fire Drill Sergeant meal variations:**

**16.** Snack between meals: "Snack window. 150-200 cal. High protein. Greek yogurt, nuts, protein bar. Not chips."
**17.** Post-training delayed: "You trained 2 hours ago. Still no meal. The recovery window is closing. Eat within the next 30 minutes or the session efficiency drops."
**18.** Missed 2+ meals: "{meals_logged}/{meals_target} meals. You've skipped {meals_target - meals_logged} meals today. Your body can't perform on air. Eat."
**19.** Protein shake alternative: "No time for a full meal? Protein shake: {remaining_protein}g of whey + banana + milk. 2 minutes. No excuses."
**20.** Fiber reminder: "Low fiber today. Add vegetables to this meal. Digestion affects recovery."
**21.** Game day fueling: "Game in {hours_to_game} hours. Carb-focused meal. {meal_calories} cal. Performance fuel."
**22.** Late lunch: "Lunch is 90 minutes overdue. Afternoon study will suffer if you don't eat. Brain needs glucose."
**23.** Exam day nutrition: "{exam_name} today. Eat a balanced meal: steady glucose release. Avoid sugar spikes before the exam."
**24.** Weekend brunch: "Weekend brunch is fine. Just log it honestly. No pretending that stack of pancakes was 300 calories."
**25.** Lactose-free reminder: "Remember: lactose-free options. Greek yogurt (lactose-free), hard cheeses, or protein shake with plant milk."
**26.** Friend meal challenge: "{friend_name} hit their protein target 3 days straight. You've hit it {protein_streak} days. Keep up."
**27.** Macro balance praise: "Yesterday's macros were perfect. Match that today. This meal: {meal_protein}g protein, {meal_carbs}g carbs."
**28.** Dessert/treat context: "Want a treat? Earn it. Hit {protein_target}g protein first, then fit a treat into remaining macros. Flexible dieting, not chaos."
**29.** Meal timing for sleep: "Last meal 3+ hours before bed. You're aiming for {bedtime_target}. That means eating by {last_meal_time}."
**30.** Generic with NutriTrack data: "Meal {meal_number}. {meal_calories} cal planned. Current daily total: {calories_current}/{calories_target}. Protein: {protein_current}/{protein_target}g. Eat and log."

---

### Channel 8: Training Reminder

**Trigger:** 1 hour before the scheduled workout time. Workout time is either explicitly set by the user or inferred from training history patterns (e.g., user usually trains at 5 PM).

**Type:** Standard push (local notification).

**String key prefix:** `notif.training.`

**Actions:** "View Workout" (opens TodayWorkoutView), "Skip Today" (marks as skipped, -20 XP)

#### Copy Variations — 30 contexts x 4 intensities

**1. Standard gym day (green recovery)**
- **G:** {workout_type} day in about an hour! Recovery is {recovery_score}% -- you're good to go. Check your workout plan and warm up well!
- **F:** {workout_type} in 1 hour. Recovery: {recovery_score}%. Green. Full intensity. View your plan.
- **D:** {workout_type} in 1 hour. Recovery is green at {recovery_score}%. Full send today. Bench press, overhead press, lateral raises -- check TodayWorkout for the full plan. Warm up properly.
- **S:** {workout_type}. 1 hour. Recovery {recovery_score}%. No reason to hold back. If I don't see PRs attempted today, I'll know you sandbagged. Full intensity or why bother showing up?

**2. Yellow recovery, reduced volume**
- **G:** Training in about an hour. Recovery is {recovery_score}%, so the session is a bit lighter. Same exercises, just fewer sets. Listen to your body!
- **F:** Training in 1 hour. Recovery: {recovery_score}%. Yellow. Volume reduced 20%. Same movements, lighter load.
- **D:** Training in 1 hour. Recovery is yellow at {recovery_score}%, so volume is reduced 20%. Same exercises, fewer sets. Don't skip because it's lighter -- lighter still counts. Show up.
- **S:** {recovery_score}% recovery. Yellow. Volume is cut because your body can't handle full load. Don't use this as an excuse to coast. Reduced volume with full intensity on every rep. Lighter is not easier.

**3. Red recovery, mobility swap**
- **G:** Recovery is low today ({recovery_score}%). I've adjusted your session to gentle mobility. Take care of your body -- it needs it.
- **F:** Recovery: {recovery_score}%. Session swapped to mobility and light cardio. 30 minutes. Don't skip.
- **D:** Recovery is at {recovery_score}%. I've swapped your session to mobility and light cardio. 30 minutes. Non-negotiable. Your body needs movement, not destruction. Roll out, stretch, do the work.
- **S:** {recovery_score}%. Red. If you try to lift heavy today, you'll regret it. Mobility. 30 minutes. And don't pretend mobility is beneath you. The strongest athletes in the world stretch. You're not an exception.

**4. Team sport day**
- **G:** {sport_name} practice in an hour! Remember to eat a light snack if you haven't already. Stay hydrated and have fun!
- **F:** {sport_name} practice in 1 hour. Pre-fuel: 200 cal, carb-focused. Hydrate. Strain comes from practice today.
- **D:** {sport_name} practice in 1 hour. Eat a quick snack if you haven't -- 200 cal, mostly carbs. Hydrate. Today's strain target will come from practice, so no gym needed.
- **S:** {sport_name} in 1 hour. If you haven't eaten, you're going to perform like garbage. Carbs. Water. Now. And don't skip the warm-up because your teammates do.

**5. Rest day with high recovery (optional session)**
- **G:** It's a rest day, but your recovery is great ({recovery_score}%)! If you feel like doing a bonus session, it could be productive. Totally optional though.
- **F:** Scheduled rest day. Recovery: {recovery_score}%. Optional bonus session available if desired.
- **D:** Scheduled rest day, but your recovery is at {recovery_score}%. Highest in two weeks. If you want to get an extra session in, the gains are there for the taking. Optional, but the opportunity is real.
- **S:** Rest day. Recovery {recovery_score}%. Wasting a green recovery day on the couch. That's like having a full tank of gas and parking the car. If you won't train, at least do active recovery. Walk. Stretch. Something.

**6-15. Additional training variations (Drill Sergeant, pattern applies to all intensities):**

**6.** Leg day: "{workout_type}. Nobody's favorite. That's exactly why it matters. Squats, leg press, hamstring curls. Recovery is {recovery_score}%. No skipping. Nobody respects a chicken-legs athlete."
**7.** Pull day after push: "Pull day. Your chest got work yesterday. Now it's back and biceps. Balance matters. Check the plan. Warm up your rotator cuffs."
**8.** Deload week: "Deload week. 60% of normal weight. Technique focus. This isn't a week off -- it's strategic recovery. Every 4th week. Trust the process."
**9.** First session after new program: "New program starts today. First session: expect new movements. Film your form. Start conservative on weight. Build from here."
**10.** Gym partner available: "{friend_name} is also training today. Accountability partner. Don't let each other skip sets."
**11.** Progressive overload due: "Last session: bench at {last_weight}kg x {last_reps}. Today's target: {target_weight}kg x {target_reps}. Progressive overload. This is how you grow."
**12.** Training streak milestone: "{training_streak} training days in a row. Don't break it. {workout_type} today. Consistency > intensity."
**13.** Late evening training: "Evening session. Don't train too close to bed -- aim to finish 2h before {bedtime_target}. Keep stimulants away."
**14.** Morning training: "Morning session. Eat a light snack, hydrate, and warm up thoroughly. Cold muscles = injury risk."
**15.** Bodyweight alternative offered: "Can't get to the gym? Bodyweight alternative available. Push-ups, dips, pike push-ups. Tap 'View Workout' for the at-home plan."

**16-30. Rapid-fire Drill Sergeant variations:**

**16.** Pre-workout nutrition check: "Eat 1-2 hours before. If you haven't, grab a banana and 20g protein. Don't train fasted unless it's deliberate."
**17.** Weather-adjusted outdoor training: "Nice weather. If today's session allows it, outdoor training is an option. Runs, calisthenics, hill sprints."
**18.** After exam: "Exam done. Stress hormones high. Perfect time to channel that energy into {workout_type}. The gym is therapy today."
**19.** Friend completing workout: "{friend_name} just finished their workout. Your turn. {workout_type} is waiting."
**20.** Recovery from injury (modified): "Modified session today. Avoid {injured_area}. Alternative exercises programmed. Still show up. Working around injury IS training."
**21.** Muscle group focus: "Focus today: {primary_muscle_group}. Last session was {days_since_last} days ago. Fully recovered. Time to grow."
**22.** Cardio day: "Cardio day. 30 minutes moderate intensity. Zone 2 heart rate. Boring? Yes. Essential for recovery and heart health? Also yes."
**23.** Partner workout challenge: "Challenge: beat your last {workout_type} session total volume. Previous: {last_volume}kg. Let's go."
**24.** Quick session available: "Short on time? Express {workout_type}: compound movements only. 30 minutes. Effective. No excuses."
**25.** Superset suggestion: "Time-efficient: supersets today. Push/pull pairs. Same work, less time. Check the plan."
**26.** Stretching reminder: "Don't skip the cooldown. 5 minutes of stretching. Your 40-year-old self will thank you."
**27.** New exercise introduced: "New movement today: {new_exercise}. Watch the form video first. Ego-check the weight. Technique > numbers."
**28.** Training volume milestone: "You've lifted {monthly_volume}kg this month. That's a new record. Keep building."
**29.** Italian training motivation: "Allenamento tra un'ora. {workout_type}. Niente scuse. Il fisico non si costruisce da solo."
**30.** Generic with full plan preview: "{workout_type} in 1 hour. {exercise_count} exercises. Estimated duration: {duration} min. Recovery: {recovery_score}%. Tap to view full plan."

---

### Channel 9: Recovery Report

**Trigger:** When Whoop recovery score becomes available (pushed via webhook to backend, then pushed to device). Typically arrives between 6 AM and 9 AM, after the user's first sleep cycle data is processed.

**Type:** Standard push (APNs).

**String key prefix:** `notif.recovery.`

**Actions:** "View Recovery" (opens RecoveryTodayView), "View Workout" (opens TodayWorkoutView)

#### Copy Variations — 30 total (10 per zone x 3 zones, each with 4 intensities)

**GREEN (recovery >= 67%) — 10 variations:**

**1. Standard green**
- **G:** Great news! Recovery: {recovery_score}%. Your body recovered well. Perfect conditions for a solid {workout_type} session today.
- **F:** Recovery: {recovery_score}%. Green. Full training intensity today. No restrictions.
- **D:** Recovery: {recovery_score}%. Green. Your body recovered well. Today is a full-send day -- don't waste it on a half-effort workout. Push for a PR.
- **S:** {recovery_score}%. Green. Your body gave you permission to go hard. If you waste this with a mediocre workout, that's on you. PR or disappointment. No middle ground.

**2. HRV trending up**
- **G:** Recovery: {recovery_score}%! HRV has been climbing for {hrv_trend_days} days. Your body is responding beautifully to the program.
- **F:** Recovery: {recovery_score}%. HRV trending up {hrv_trend_days} days. Peak readiness.
- **D:** Recovery: {recovery_score}%. Green light across the board. HRV is trending up for {hrv_trend_days} days straight. This is the strongest you've been all week. Act like it.
- **S:** {recovery_score}% with HRV climbing {hrv_trend_days} days straight. This is your body begging you to push harder. If today isn't a top-3 training day, you're wasting biology.

**3. Good sleep metrics**
- **G:** Recovery: {recovery_score}%. Sleep was {sleep_hours} with {deep_sleep}h of deep sleep. Wonderful recovery, {name}!
- **F:** Recovery: {recovery_score}%. Sleep: {sleep_hours}, {deep_sleep}h deep. Adequate. Full training.
- **D:** Recovery: {recovery_score}%. Solid green. Sleep was {sleep_hours} with {deep_sleep}h deep sleep. Good enough. Training at full volume today. No excuses about being tired.
- **S:** {sleep_hours} of sleep. {deep_sleep}h deep. Recovery {recovery_score}%. You actually followed the bedtime prescription. Shocking. Now do the same thing tonight.

**4. Consistent sleep week**
- **D:** Recovery: {recovery_score}%. Green zone. You've been consistent with sleep this week and it shows. Maintain the routine -- same bedtime tonight.

**5. Best score this week**
- **D:** Recovery: {recovery_score}%. Your best score this week. RHR dropped to {rhr}. Everything is trending right. This is what happens when you follow the prescription.

**6. Recovery after deload week**
- **D:** Recovery: {recovery_score}%. Post-deload. Your body is recharged. This week: back to full intensity. The deload worked. Now capitalize on it.

**7. Green streak (3+ green days)**
- **D:** {green_streak_days} green days in a row. Your lifestyle is dialed in. Recovery is consistently high because you're sleeping right, eating right, and training smart. Don't change a thing.

**8. Green after previous red**
- **D:** Recovery bounced from red to {recovery_score}% green. The rest day worked. Your body responded. Now use this energy wisely. Full send but don't overdo it.

**9. High REM sleep**
- **D:** {rem_sleep}h of REM sleep -- well above average. That means learning consolidation from yesterday's study is strong. Recovery: {recovery_score}%. Brain AND body are recovered.

**10. Green with upcoming exam**
- **D:** Recovery: {recovery_score}%. Green. And {exam_name} in {exam_days} days. Your brain recovered well from yesterday's study. Conditions are perfect for a heavy study + training day.

**YELLOW (recovery 34-66%) — 10 variations:**

**1. Standard yellow**
- **G:** Recovery is {recovery_score}% today -- not peak, but totally workable. Just dial the intensity back a touch. You'll still have a productive day!
- **F:** Recovery: {recovery_score}%. Yellow. Training volume reduced 20%. Study and meals unchanged.
- **D:** Recovery: {recovery_score}%. Yellow. Not terrible, but not good enough for max effort. Training volume reduced 20% today. Focus on technique, not weight.
- **S:** {recovery_score}%. Yellow. Because of course it is. Your sleep was probably garbage. Training cut. But everything else stays. Don't use yellow as permission to be lazy.

**2. Poor sleep cause**
- **D:** Recovery: {recovery_score}%. Yellow zone. Sleep was only {sleep_hours} with low deep sleep. Today's workout is lighter. But don't use this as an excuse to skip entirely.

**3. HRV dropped**
- **D:** Recovery: {recovery_score}%. Just barely yellow. HRV dropped {hrv_drop}% from yesterday. Could be stress, could be poor nutrition. Stick to the plan today and let's see where tomorrow lands.

**4. Late bedtime cause**
- **D:** Recovery: {recovery_score}%. Yellow. You went to bed {late_by} minutes late last night. That's why. Today: reduced training, extra hydration, caffeine cutoff at 2 PM, and in bed by {bedtime_target}.

**5. Yellow pattern (3+ days)**
- **D:** Recovery: {recovery_score}%. {yellow_streak} yellow days in a row. This is a pattern, not a bad day. Something needs to change -- sleep, nutrition, or training load. Check RecoverIQ for the full prescription.

**6. Yellow but feeling good (subjective override)**
- **D:** Recovery: {recovery_score}%. Yellow. You might feel fine, but the data says moderate. Trust the numbers. Reduced volume. If you feel great mid-session, stay at the programmed level. Don't freelance."

**7. Yellow on exam day**
- **D:** Recovery: {recovery_score}%. Yellow. And {exam_name} today. Train light or skip. Save all cognitive energy for the exam. Nutrition on point. Hydrate."

**8. Yellow with high stress inferred**
- **D:** Recovery: {recovery_score}%. Elevated RHR suggests stress. If something's going on outside training, address it. Stress affects recovery more than most people realize."

**9. Yellow with alcohol suspected (late RHR spike)**
- **D:** Recovery: {recovery_score}%. Your RHR spiked late last night. The data doesn't judge, but it doesn't lie either. Whatever caused it -- less of that tonight. Hydrate. Light training."
- **S:** {recovery_score}%. Late-night RHR spike. We both know what that means. Your body isn't hiding your choices. Light training. Extra water. And maybe don't repeat last night.

**10. Yellow generic with prescription**
- **D:** Recovery: {recovery_score}%. Yellow. Today's prescription: moderate training, 2.5L water, caffeine before 2 PM, bed by {bedtime_target}. Follow it. Tomorrow will be green."

**RED (recovery < 34%) — 10 variations:**

**1. Standard red**
- **G:** Recovery is low today ({recovery_score}%). Please take it easy on training. Mobility or a gentle walk is perfect. Take care of yourself, {name}.
- **F:** Recovery: {recovery_score}%. Red. No heavy training. Mobility only. Eat well, hydrate, early bed.
- **D:** Recovery: {recovery_score}%. Red. Your body is telling you to back off. No heavy lifting today. Mobility only. Eat well, hydrate, and be in bed by {bedtime_target}. This is not a suggestion.
- **S:** {recovery_score}%. Red. Your body is waving a white flag. Mobility only. If you ignore this and lift heavy, the injury isn't bad luck -- it's a consequence. Fix your sleep. Fix your nutrition. Be smarter than your ego.

**2. Deep red with elevated markers**
- **D:** Recovery: {recovery_score}%. Deep red. HRV crashed. RHR elevated. Something is off -- could be illness, accumulated stress, or overtraining. Rest today. Train tomorrow if green.

**3. Poor sleep efficiency**
- **D:** Recovery: {recovery_score}%. Red zone. Sleep efficiency was {sleep_efficiency}% -- you were tossing and turning. Skip the gym. Do 20 minutes of walking and some stretching. Come back stronger tomorrow.

**4. Red pattern (3+ days)**
- **D:** Recovery: {recovery_score}%. {red_streak} red days this week. This is a warning sign. I'm recommending 2 full rest days. Push through this and you'll end up injured or sick. Listen to your body.

**5. Barely red**
- **D:** Recovery: {recovery_score}%. Barely red. You might feel okay, but the numbers don't lie. Light session only: bodyweight movements, no heavy compounds. Trust the data over your ego.

**6. Red after heavy training week**
- **D:** Recovery: {recovery_score}%. You pushed hard this week. Your body is asking for a break. Take it. The gains happen during rest, not during the workout."

**7. Red with upcoming important event**
- **D:** Recovery: {recovery_score}%. Red. And {exam_name} in {exam_days} days. Prioritize sleep and light activity. Your cognitive function is compromised at this recovery level."

**8. Red, potential illness**
- **D:** Recovery: {recovery_score}%. RHR is {rhr_delta} bpm above your baseline. This could be early illness. Monitor today. If you feel off, rest fully. Training sick extends the downtime."

**9. Red after travel**
- **D:** Recovery: {recovery_score}%. Travel took a toll. Jetlag, disrupted sleep, different food. Light movement only. Hydrate aggressively. 3L today minimum."

**10. Red recovery encouraging patience**
- **G:** Red days happen. Recovery is {recovery_score}%. Rest today, and tomorrow will likely be much better. Your body knows how to bounce back -- just give it what it needs.
- **D:** Red day. Not the end of the world. One rest day won't undo your progress. But one forced workout on red recovery might. Be patient. Be smart. Rest now, dominate tomorrow.

---

### Channel 10: Bedtime Reminder

**Trigger:** 30 minutes before calculated optimal bedtime. Optimal bedtime is calculated by RecoveryEngine based on: sleep debt, tomorrow's wake time, target 7.5-8.5h of sleep.

**Type:** Time Sensitive push (local notification).

**Sound:** Custom `tempo_bedtime.caf`

**String key prefix:** `notif.bedtime.`

**Actions:** "Wind Down" (opens a minimal wind-down screen with dimmed UI, sleep tips, and phone-down countdown)

#### Copy Variations — 30 contexts x 4 intensities

**1. Standard bedtime, no sleep debt**
- **G:** Time to start winding down, {name}. Bedtime in 30 minutes ({bedtime_target}). A good night's sleep makes tomorrow so much easier!
- **F:** Bedtime: {bedtime_target}. 30 minutes. Start winding down. Screens off soon.
- **D:** Bedtime in 30 minutes. Target: {bedtime_target}. You need 7.5 hours to wake up recovered. Start winding down. Phone face-down. Screens off. Tomorrow's score starts with tonight's sleep.
- **S:** {bedtime_target}. 30 minutes. Put the phone down. I know you won't. You'll "just check one more thing" until midnight. And then tomorrow you'll wonder why your recovery is yellow. This is why. Stop reading. Sleep.

**2. Sleep debt accumulated (>2h)**
- **G:** You're carrying some sleep debt ({sleep_debt}h). An earlier bedtime tonight would really help. Target: {bedtime_target}.
- **F:** Sleep debt: {sleep_debt}h. Bedtime moved earlier to {bedtime_target}. Prioritize recovery.
- **D:** You're carrying {sleep_debt} hours of sleep debt. Target bedtime: {bedtime_target} -- earlier than usual. Every hour of debt costs you recovery points tomorrow. Put the phone down.
- **S:** {sleep_debt}h of sleep debt. You've been robbing your future self for days. Every night you stay up late, tomorrow's recovery pays the price. {bedtime_target}. Non-negotiable. The phone goes face-down NOW. Not in 10 minutes. NOW.

**3. Before big training day**
- **G:** {tomorrow_workout} tomorrow! Good sleep tonight means better performance. Target bedtime: {bedtime_target}. Rest up!
- **F:** {tomorrow_workout} tomorrow. Recovery-dependent. Bedtime: {bedtime_target}. Sleep = performance.
- **D:** {tomorrow_workout} tomorrow. You need green recovery to hit those lifts properly. Bedtime in 30 minutes at {bedtime_target}. Sleep is literally where your muscles grow. Don't cheat yourself.
- **S:** {tomorrow_workout} tomorrow and you're still awake? Every minute past {bedtime_target} is a rep you won't be able to finish tomorrow. Your muscles recover while you sleep, not while you scroll Instagram. Lights. Off.

**4. Before an exam**
- **G:** {exam_name} exam tomorrow! Your brain consolidates everything you studied during sleep. An early, restful night is the best last-minute prep. Target: {bedtime_target}.
- **F:** {exam_name} tomorrow. Sleep consolidates learning. No late cramming. Bed by {bedtime_target}.
- **D:** {exam_name} exam tomorrow. Sleep is when your brain consolidates what you studied today. Target: {bedtime_target}. No late-night cramming. The science is clear: sleep beats extra study hours. Lights out.
- **S:** {exam_name} tomorrow. If you're studying right now, stop. Cramming at this hour does more harm than good. Your brain needs sleep to consolidate. Every study you've done today is being organized by your brain DURING SLEEP. Go to bed or watch all that studying evaporate.

**5. After hard training day (high strain)**
- **G:** Big training day! Strain was {strain_score}. Your body worked hard and needs great sleep to recover. Wind down, {name}. Target: {bedtime_target}.
- **F:** Strain: {strain_score}. High. Recovery demands sleep. Bedtime: {bedtime_target}. Aim for 8+ hours.
- **D:** Strain today: {strain_score}. Your body did serious work. It needs serious recovery. Bedtime: {bedtime_target}. Aim for 8+ hours. No screens in bed. Your recovery score tomorrow depends on the next 30 minutes.
- **S:** Strain: {strain_score}. You destroyed your body today. If you don't sleep at least 8 hours, that workout was a net negative. You'll wake up more broken than before. {bedtime_target}. No exceptions. No "one more episode."

**6-15. Additional bedtime variations (Drill Sergeant):**

**6.** After caffeine late: "You had caffeine at {last_caffeine_time}. It's still in your system. Sleep quality will suffer. Lesson for tomorrow: cutoff at {caffeine_cutoff}. For now: wind down. No more stimulants."
**7.** Weekend bedtime: "{day_of_week} night. I know the weekend temptation is to stay up late. Don't. Your Monday recovery depends on tonight's and tomorrow night's sleep. Same bedtime. {bedtime_target}."
**8.** After all-clear day: "Perfect day. Every task done. Now cap it with perfect sleep. {bedtime_target}. Tomorrow's morning briefing will be a celebration -- if you sleep well."
**9.** After missed tasks: "Tough day. Tasks weren't all completed. But you can still win tomorrow by sleeping well tonight. {bedtime_target}. Give your body the best chance."
**10.** Screen time warning: "Your screen time has been high today. Blue light suppresses melatonin. Put all screens away 30 minutes before bed. That means NOW. {bedtime_target}."
**11.** Cold room reminder: "Sleep tip: keep your room cool (65-68°F / 18-20°C). Your body needs to drop in temperature to fall asleep. Adjust the thermostat."
**12.** Hydration balance: "Hydrate now, but not too close to bed. A glass of water now, then nothing until morning. Waking up to pee kills deep sleep."
**13.** Italian bedtime: "Buonanotte tra 30 minuti. {bedtime_target}. Il sonno e' la tua arma segreta. Non buttarlo via."
**14.** Streak dependent on tomorrow: "Your streak depends on tomorrow's performance. Tomorrow's performance depends on tonight's sleep. The chain starts here."
**15.** Wind-down routine: "30-minute wind-down protocol: dim lights, no screens, light stretching or reading. Set yourself up for 90+ sleep score."

**16-30. Rapid-fire variations (all Drill Sergeant):**

**16.** Friend competition: "{friend_name}'s average sleep score: 82. Yours: {sleep_avg}. Sleep is a competitive advantage. Beat them."
**17.** Alcohol warning: "If you've had alcohol tonight: expect worse sleep quality. Alcohol fragments REM sleep. Tomorrow's recovery will reflect it."
**18.** Travel/time zone: "You're adjusting to a new time zone. Stick to {bedtime_target} local time. Consistency resets your circadian rhythm faster."
**19.** Hot night: "Warm night tonight. Use a fan or lighter sheets. Heat is the #1 sleep quality killer."
**20.** After late meal: "You ate late. Digestion disrupts deep sleep. Next time, last meal 3h before bed. For tonight: elevate your head slightly."
**21.** Consecutive good sleep: "{good_sleep_streak} nights of 85%+ sleep. Your recovery baseline is improving. Keep the routine."
**22.** After nap: "You napped today. That can push bedtime later. Stay disciplined: {bedtime_target}. Long naps steal from nighttime sleep."
**23.** Monday night: "Monday night. The week's tone starts tonight. Good sleep now means green recovery for Tuesday's session."
**24.** Before important class: "Important class at {class_time} tomorrow. You need to be sharp. That means 7.5+ hours. That means {bedtime_target}. Now."
**25.** Supplement reminder: "If you take magnesium or melatonin, now's the time. 30 minutes before bed. Then: phone down."
**26.** White noise: "Sleep tip: white noise or brown noise can improve sleep quality in noisy environments. Try it tonight."
**27.** Recovery prediction: "If you sleep by {bedtime_target} and get 7.5h, projected recovery: {projected_recovery}%. Worth it."
**28.** Body temperature: "Your body temperature drops before sleep. A warm shower 60 minutes before bed accelerates this. Counter-intuitive but scientifically proven."
**29.** After multi-day sleep debt: "You've underslept 4 of the last 5 nights. Your cognitive function is measurably impaired. Tonight: {bedtime_target}. No compromise."
**30.** Generic: "Bedtime countdown: 30 minutes. {bedtime_target}. Your future self is depending on present you. Don't let them down. Phone down. Lights off. Sleep."

---

### Channel 11: Arena -- Social

**String key prefix:** `notif.arena.`

**Type:** Standard push (APNs). Never critical, never time-sensitive. Social notifications should motivate, not stress.

#### Sub-type: Leaderboard Change — 10 variations x 4 intensities

**1. Passed by friend**
- **G:** {friend_name} just moved ahead of you! You're at {leaderboard_rank} now. A solid day could change that!
- **F:** {friend_name} passed you. {leaderboard_rank} now. {xp_gap} XP behind. Act.
- **D:** {friend_name} just passed you on the weekly leaderboard. {xp_gap} XP behind. You're not going to let that stand, are you?
- **S:** {friend_name} owns your spot now. They're better than you this week. Unless you make today a 100% day, get used to looking up at them on the board.

**2. Dropped multiple positions**
- **D:** You dropped to {leaderboard_rank} this week. {friend_name} and {friend_name_2} are both ahead now. Still {days_left} days left to reclaim the top spot. Complete every non-negotiable today.

**3. Leading but under pressure**
- **D:** You're {leaderboard_rank} this week with {xp_total} XP. But {friend_name} is {xp_gap} XP behind and closing fast. Don't coast. Finish strong.

**4. Comeback opportunity**
- **D:** You're {leaderboard_rank} but only {xp_gap} XP from {leaderboard_rank_above}. One perfect day closes that gap. Today could be the day.

**5. Dominant lead**
- **D:** You're {leaderboard_rank} by {xp_gap} XP. Commanding lead. Don't get lazy. Maintain the standard. Make the gap embarrassing.

**6. Friend hit 100% today**
- **D:** {friend_name} just hit 100% today. They're earning XP while you're at {completed_pct}%. Respond.

**7. End of week battle**
- **D:** Final day of the weekly leaderboard. You're {leaderboard_rank}. {xp_gap} XP from {leaderboard_rank_above}. Every task today = XP. Leave nothing on the table.

**8. New week, leaderboard reset**
- **D:** Leaderboard reset. Clean slate. Last week's {leaderboard_rank}: history. This week starts now. Earn your position.

**9. Friend on a streak**
- **D:** {friend_name} is on a {friend_streak}-day streak. Yours: {streak_days}. Closing the gap requires consistency, not one big day.

**10. Italian rivalry**
- **S:** {friend_name} ti ha superato. Dai, non puoi accettarlo. {xp_gap} XP. Recupera.

#### Sub-type: Challenge Invites — 10 variations

**1.** {friend_name} challenged you: "{challenge_name}." Starting {challenge_start}. Accept and show them what discipline looks like? [Accept] [Decline]
**2.** New challenge from {friend_name}: "{challenge_name}." {challenge_duration} sprint. You in? [Accept] [Decline]
**3.** {friend_name} wants a rematch: "{challenge_name}." You beat them last time by {last_margin}. They're hungry. Accept? [Accept] [Decline]
**4.** {friend_name} sent a challenge. Subject: {challenge_name}. Duration: {challenge_duration}. Do you have what it takes? [Accept] [Decline]
**5.** Bold move: {friend_name} challenged you to {challenge_name}. They must think they can win. Prove them wrong. [Accept] [Decline]
**6.** {friend_name} is calling you out. {challenge_name}. {challenge_duration}. The whole Arena is watching. [Accept] [Decline]
**7.** Double or nothing: {friend_name} wants a rematch after losing last time. Same challenge: {challenge_name}. Accept? [Accept] [Decline]
**8.** Group challenge from {friend_name}: {challenge_name}. {participant_count} people. Winner takes bragging rights. [Accept] [Decline]
**9.** {friend_name} thinks they study harder than you. Challenge: Most Study Hours, {challenge_duration}. Settle this. [Accept] [Decline]
**10.** Sfida da {friend_name}: "{challenge_name}." Ci stai o ti caghi sotto? [Accept] [Decline]

#### Sub-type: Challenge Updates — 10 variations

**1.** {challenge_name}: You're behind. {friend_name} has {friend_score}. You have {user_score}. {days_left} days left. {gap} to catch up. One good day does it.
**2.** {challenge_name} update: You're winning by {gap} with {days_left} days left. Don't get comfortable. One perfect day from {friend_name} and you're tied.
**3.** {challenge_name}: Day {challenge_day} of {challenge_duration}. Both tied. The next day decides it. Don't slip now.
**4.** {challenge_name}: You pulled ahead! {gap} lead over {friend_name}. Maintain it.
**5.** {challenge_name}: {friend_name} just took the lead. {gap} ahead. Respond today or accept defeat.
**6.** {challenge_name}: Final day. You: {user_score}. {friend_name}: {friend_score}. Everything comes down to today.
**7.** {challenge_name}: You won! Final score: {user_score} vs {friend_score}. +{xp_bonus} XP bonus. Well earned.
**8.** {challenge_name}: You lost. {friend_score} to {user_score}. {friend_name} outworked you. Rematch available.
**9.** {challenge_name}: Draw. Both at {user_score}. Sudden death: first to complete today's non-negotiables wins.
**10.** {challenge_name}: Halfway point. You're at {user_score}. On pace to {projected_outcome}. Adjust effort accordingly.

#### Sub-type: Achievement Unlock — 10 variations

**1.** New badge: **Iron Will**. {streak_days} consecutive days at 100%. Less than 2% of Tempo users achieve this. You're built different.
**2.** New badge: **Early Bird**. All tasks done before 3 PM, {early_streak} days straight. Front-loading effort is a superpower.
**3.** New badge: **Recovery Master**. Followed RecoverIQ's prescription for {rx_streak} consecutive days. Your body thanks you.
**4.** New badge: **Study Machine**. {study_hours_total}+ hours of study logged. Knowledge compounds. You're investing in yourself.
**5.** New badge: **Protein King**. Hit your protein target {protein_streak} days straight. Your gains have gains.
**6.** New badge: **Social Catalyst**. Invited {invite_count} friends to Tempo. Building a community of discipline.
**7.** New badge: **Comeback Kid**. Returned from a {days_absent}-day absence and completed 100% on your first day back. Resilience.
**8.** New badge: **Night Owl Tamed**. In bed by target {bedtime_streak} nights in a row. Sleep discipline is the hardest discipline.
**9.** New badge: **Centurion**. 100 days on Tempo. A hundred days of showing up. Whatever happens next, this can't be taken from you.
**10.** New badge: **Grand Slam**. 100% non-negotiables + 90%+ macros + green recovery + training PR. All in one day. The perfect day. Legendary.

#### Sub-type: Friend Requests — 5 variations

**1.** {friend_name} wants to join your circle. Accept and compete on the weekly leaderboard? [Accept] [Decline]
**2.** New friend request from @{friend_username}. More rivals, more accountability. [Accept] [Decline]
**3.** @{friend_username} sent you a friend request. They heard you're disciplined. Prove it. [Accept] [Decline]
**4.** {friend_name} wants in. Accept and they'll see your scores, your streak, your everything. No hiding. [Accept] [Decline]
**5.** Nuovo rivale: @{friend_username}. Accetta e sfidalo. [Accept] [Decline]

#### Sub-type: Friend Activity — 5 variations

**1.** {friend_name} just completed a {streak_days}-day streak. Send them a boost?
**2.** {friend_name} hit a PR on bench press. Acknowledge it or beat it.
**3.** {friend_name} hasn't been active in 3 days. Send them a nudge to come back?
**4.** {friend_name} earned the {badge_name} badge. They're leveling up. Are you?
**5.** {friend_name} scored {friend_weekly_score}/100 last week. Their best ever. The bar just got higher for everyone.

---

### Channel 12: Weekly Summary

**Trigger:** Sunday at 7:00 PM (local time).

**Type:** Standard push (APNs).

**String key prefix:** `notif.weekly.`

**Actions:** "View Report" (opens WeeklyReportView)

#### Copy Variations — 30 contexts x 4 intensities

**1. Great week (score >= 85%)**
- **G:** What a week, {name}! Score: {weekly_score}/100. {perfect_days}/7 days at 100%. Study: {study_hours_week}h. Training: {training_sessions} sessions. You should be really proud!
- **F:** Week in review. Score: {weekly_score}/100. {perfect_days} perfect days. Study: {study_hours_week}h. Training: {training_sessions} sessions. Strong week. Maintain.
- **D:** WEEK IN REVIEW: Score {weekly_score}/100. {perfect_days} of 7 days at 100% completion. Study: {study_hours_week}h (target: {study_target_week}h). Training: {training_sessions} sessions. Meals: {meal_compliance}% compliance. This is the standard. Maintain it.
- **S:** {weekly_score}/100. Good. Not perfect. {perfect_days}/7 perfect days means {7 - perfect_days} imperfect ones. Most people would celebrate this. You should be asking why it wasn't higher. Open the report. Find the weak days. Eliminate them.

**2. Good week (score 70-84%)**
- **G:** Solid week! Score: {weekly_score}/100. {perfect_days} great days. A few things to improve, but the trend is positive. Check the report for details.
- **F:** Week: {weekly_score}/100. {perfect_days} perfect, {miss_days} misses. Pattern detected: {weak_pattern}. Address it next week.
- **D:** WEEK IN REVIEW: Score {weekly_score}/100. {perfect_days} perfect days, {miss_days} misses. Study was solid. Training compliance dropped on {weak_days}. The pattern: you fade late-week. Let's fix that next week.
- **S:** {weekly_score}. Good enough for most people. Not good enough for someone who calls themselves disciplined. {miss_days} days of misses. On {weak_days} you chose comfort over commitment. The report has the details. Read them and feel the sting.

**3. Average week (score 50-69%)**
- **G:** This week scored {weekly_score}/100. There's room to grow, and that's okay. Every week is a learning opportunity. Check the report to see where you can improve.
- **F:** Week: {weekly_score}/100. Below your capability. {miss_days} days missed. Study target hit {study_hit_days}/7 days. Reset on Monday.
- **D:** WEEK IN REVIEW: Score {weekly_score}/100. Not your worst, but nowhere near your best. {miss_days} non-negotiable days fully missed. Study target hit only {study_hit_days} of 7 days. You know what you need to do. The question is whether you'll actually do it.
- **S:** {weekly_score}/100. Mediocre. You set targets and hit them barely half the time. What's the point of having non-negotiables if they're actually very negotiable? Open the report. Look at the damage. Then decide if next week is going to be different or if this is your new normal.

**4. Bad week (score < 50%)**
- **G:** Tough week -- {weekly_score}/100. That's okay, it happens. What matters is what you do next. Check the report, and let's plan a better week ahead.
- **F:** Week: {weekly_score}/100. Unacceptable by your own standards. {perfect_days} complete day(s). Analysis needed. Open the report. Recalibrate if necessary.
- **D:** WEEK IN REVIEW: Score {weekly_score}/100. Honest talk: this was a bad week. {perfect_days} complete day(s) out of 7. Study averaged {study_avg}/day against a {study_target} target. Something needs to change and it starts Monday. Open the report. Look at the numbers. Make a plan.
- **S:** {weekly_score}/100. Disaster. {perfect_days} clean day(s) in an entire week. Your study average was {study_avg} -- less than half your target. Your non-negotiables were entirely negotiable. Either you're burned out (recalibrate your targets), or you're lazy (fix your attitude). There's no third option. Decide which it is and fix it.

**5. Exam week**
- **G:** Exam week report! Score: {weekly_score}/100. {exam_name} was on {exam_day}. Study hours peaked before the exam. Hope it went well!
- **F:** Exam week. Score: {weekly_score}/100. {exam_name} on {exam_day}. Study distribution appropriate. Training maintained.
- **D:** WEEK IN REVIEW: Score {weekly_score}/100. {exam_name} exam on {exam_day} -- how'd it go? Study hours peaked {peak_day} ({peak_hours}h) and dropped after. Training stayed consistent. Recovery averaged {recovery_avg_zone}. Solid exam week.
- **S:** Exam week. {weekly_score}/100. The question isn't the score -- it's whether you passed {exam_name}. If you studied {study_hours_week}h this week and still fail, we need to talk about quality, not quantity. If you passed, the system works. Trust it.

**6-15. Additional Drill Sergeant weekly variations:**

**6.** Best week ever: "NEW PERSONAL BEST: {weekly_score}/100. Your highest weekly score. This is what your peak looks like. Screenshot it. Remember it. Chase it every week."
**7.** Worse than last week: "Last week: {last_weekly_score}. This week: {weekly_score}. Regression. Trending down is how people lose momentum. Reverse it Monday."
**8.** Better than last week: "Last week: {last_weekly_score}. This week: {weekly_score}. Improvement. Trending up. Keep the trajectory."
**9.** Leaderboard results: "Weekly leaderboard: {leaderboard_rank}. {leaderboard_rank == 1 ? 'You won. Dominant.' : friend_name + ' took the top spot this week. Next week is yours.'}"
**10.** Training volume milestone: "Total training volume this week: {weekly_volume}kg. {volume_trend} from last week. Your body is adapting."
**11.** Sleep quality average: "Average sleep score: {sleep_avg}%. {sleep_avg >= 80 ? 'Excellent sleep hygiene.' : 'Your sleep is holding you back. Fix it next week.'}"
**12.** Nutrition compliance: "Meal compliance: {meal_compliance}%. Protein target hit {protein_days}/7 days. {protein_days >= 5 ? 'Strong nutrition week.' : 'Under-eating is sabotaging your recovery.'}"
**13.** Challenge results: "Challenge with {friend_name}: {challenge_result}. {xp_bonus > 0 ? '+' + xp_bonus + ' XP bonus.' : 'No bonus. Win next time.'}"
**14.** Recovery trend: "Recovery trend: {recovery_trend}. Average: {recovery_avg}%. {recovery_trend == 'up' ? 'Your body is responding well to the program.' : 'Recovery declining. Review training load and sleep.'}"
**15.** Streak summary: "Streak: {streak_days} days. {streak_days >= 14 ? 'Building something real.' : 'Still fragile. Protect it next week.'}"

**16-30. Rapid-fire weekly variations (Drill Sergeant):**

**16.** Month-end summary embedded: "Also: monthly score for {month}: {monthly_score}/100. Rank: {monthly_rank}. Your best month was {best_month} ({best_monthly_score}). Chase it."
**17.** Friend comparison: "{friend_name} scored {friend_weekly_score} this week. You: {weekly_score}. {weekly_score > friend_weekly_score ? 'You won this round.' : 'They outworked you. Respond.'}"
**18.** Study hours deep dive: "Study breakdown: {course_1}: {c1_hours}h. {course_2}: {c2_hours}h. {study_imbalance ? 'Imbalance detected. Allocate more to ' + weak_course : 'Balanced.'}"
**19.** Weekend performance: "Weekend performance: {weekend_score}. {weekend_score >= 80 ? 'Strong weekends. Most people collapse on weekends.' : 'Weekends are your weak point. Saturday and Sunday need structure.'}"
**20.** Morning routine analysis: "Average task start time: {avg_start_time}. {avg_start_time <= '10:00' ? 'Early starts. That's discipline.' : 'Starting late costs you every day. Earlier mornings next week.'}"
**21.** Notification response rate: "You responded to {response_rate}% of notifications this week. {response_rate >= 70 ? 'Highly responsive.' : 'You're ignoring me. The notifications exist for a reason.'}"
**22.** XP earned: "XP earned: +{xp_earned}. Total: {xp_total}. Rank: {leaderboard_rank}. {xp_earned > xp_avg ? 'Above your average.' : 'Below average. Push harder.'}"
**23.** Hydration if tracked: "Average hydration: {hydration_avg}L/day. Target: 2.5L. {hydration_avg >= 2.5 ? 'Well hydrated.' : 'Drink more water. It affects everything.'}"
**24.** Training PRs: "{pr_count > 0 ? pr_count + ' PR(s) this week. Getting stronger.' : 'No PRs this week. Progressive overload requires... progress.'}"
**25.** Consistency score: "Consistency index: {consistency}%. This measures how evenly your effort is spread across the week. {consistency >= 80 ? 'Very consistent.' : 'Peaks and valleys. Aim for even output.'}"
**26.** Italian summary: "Settimana: {weekly_score}/100. {weekly_score >= 80 ? 'Bravo.' : 'Puoi fare di meglio. Lo sai.'}"
**27.** Year-to-date progress: "YTD: {ytd_score}/100 average. {ytd_trend} trend. {weeks_tracked} weeks tracked. You've been at this for {weeks_tracked} weeks. That's commitment regardless of the numbers."
**28.** Best day of the week: "Best day: {best_day} ({best_day_score}%). Worst: {worst_day} ({worst_day_score}%). The gap tells you where to focus."
**29.** New achievements earned: "{achievements_count > 0 ? achievements_count + ' new badge(s) earned this week. ' + achievement_names : 'No new achievements. Keep pushing for the next one.'}"
**30.** Looking ahead: "Next week preview: {next_exam ? exam_name + ' exam on ' + exam_day + '. Study priority.' : workout_type + ' starts Monday. Recovery target: green.'} Plan now."

---

### Channel 13: Streak Warning

**Trigger:** Evening start time plus 1.5 hours (e.g., 9:00 PM if evening is 7:30 PM), if the daily non-negotiable streak would break (i.e., at least one non-negotiable is incomplete and completing all tasks would extend the streak). Only fires if streak > 3 days (new streaks of 0-3 days are too fragile to warrant streak anxiety notifications).

**Type:** Time Sensitive push (local notification).

**Sound:** Custom `tempo_urgent.caf`

**String key prefix:** `notif.streak.`

**Actions:** "Save Streak" (opens LockdownView), "View Tasks" (opens LockdownView)

#### Copy Variations — 30 contexts x 4 intensities

**Short streaks (< 14 days) — 15 variations:**

**1. Generic short streak, study missing**
- **G:** Your {streak_days}-day streak is at risk! {study_remaining} of study would save it. You've been doing so well -- one more push!
- **F:** {streak_days}-day streak at risk. {study_remaining} study needed. Save it.
- **D:** Your {streak_days}-day streak breaks at midnight if study isn't done. {study_remaining} remaining. That's less than one Netflix episode. Choose wisely.
- **S:** {streak_days} days. About to be zero. Because you can't do {study_remaining} of study. That's how weak your commitment is? {study_remaining}. Do it or admit you never cared about the streak.

**2. Short streak, training missing**
- **G:** Quick heads up: your streak needs a workout to survive today. Even a short session counts!
- **F:** Streak at risk. Training incomplete. A 20-minute bodyweight session saves it.
- **D:** Streak at risk. Day {streak_days + 1} dies if you don't finish training. A 20-minute bodyweight session in your room saves it. No gym needed. Just effort.
- **S:** Can't even do a bodyweight workout in your room? Push-ups. Squats. 20 minutes. Your {streak_days}-day streak isn't worth 20 minutes of effort to you? That tells me everything about your commitment.

**3. Very short streak (1-3 days), meal missing**
- **G:** Your {streak_days}-day streak -- it may be small, but it's yours! Just logging a meal saves it.
- **F:** {streak_days}-day streak. One meal log saves it. Do it.
- **D:** {streak_days}-day streak, about to become zero. It's only {streak_days} days but it's YOUR {streak_days} days. Log that last meal and the streak survives. Don't let something this small beat you.
- **S:** {streak_days} days. Not even impressive yet. And you're about to lose it. Over a meal you didn't log. Apri NutriTrack. Log dinner. 60 seconds. Or start over tomorrow with zero. What a waste.

**4. Building momentum (days 4-7)**
- **D:** Day {streak_days}. You're building momentum. The habit is forming but it's fragile. {study_remaining} of study saves it. Don't let the foundation crack while it's still wet.

**5. One-week mark (day 7)**
- **D:** 7-day streak. One full week. You've never been more consistent. {study_remaining} keeps the streak alive. Breaking it now means restarting from day 1. Don't.

**6. Day 10 (double digits)**
- **D:** Double digits tomorrow if you finish {study_remaining} tonight. Day 10. Sounds better than day 0, doesn't it?

**7. After a missed day earlier this week (rebuild)**
- **D:** You rebuilt this streak from zero {streak_days} days ago. Are you going to reset again? {study_remaining}. Protect what you've rebuilt.

**8-15. Additional short streak variations (Drill Sergeant):**

**8.** Custom non-negotiable missing: "'{custom_task_name}' is unchecked. That's what kills your streak tonight. It takes 5 minutes. Save {streak_days} days of work."
**9.** Weekend streak risk: "Saturday night. {streak_days}-day streak. I know you're relaxing. {study_remaining} saves the streak. Then relax guilt-free."
**10.** Friend's streak comparison: "{friend_name} has a {friend_streak}-day streak. Yours is {streak_days}. If yours dies tonight and theirs doesn't, the gap becomes {friend_streak + 1} to 0."
**11.** Multiple tasks at risk: "{tasks_total - tasks_done} tasks left. Streak requires all of them. Prioritize by time: shortest task first. Build momentum."
**12.** Near bedtime: "It's 9 PM. Your bedtime is {bedtime_target}. {study_remaining} of study + bedtime means you need to start NOW. No margin left."
**13.** After good recovery: "Recovery was {recovery_score}% today. Green. Your body was ready. The streak dies because of effort, not biology. That's worse."
**14.** First streak ever: "This is your longest streak ever in Tempo. {streak_days} days. Every day you add is a new personal record. {study_remaining}. Protect your record."
**15.** Italian: "Il tuo streak di {streak_days} giorni muore stasera se non studi {study_remaining}. Non lasciarlo morire."

**Long streaks (>= 14 days) — 15 variations:**

**1. 14-day mark (2 weeks)**
- **G:** Two weeks of discipline! {streak_days}-day streak. You're SO close to saving it. {study_remaining} to go. You've got this!
- **F:** {streak_days}-day streak. Two weeks. {study_remaining} saves it. Don't break now.
- **D:** {streak_days}-day streak warning. Two weeks of clean days. This is where most people quit. This is the moment that separates the people who talk about discipline from the people who have it. {study_remaining}. Go.
- **S:** 14 days. The quitting point. Statistically, this is when most people give up on habits. You're a statistic waiting to happen. Prove the data wrong. {study_remaining}. Or be average. Your call.

**2. 21-day streak**
- **G:** 21 days -- they say that's when habits form! Your incredible streak is at risk. {study_remaining} would keep it alive. Please, {name}, you're so close!
- **F:** 21-day streak at risk. One task remaining. Habits form at 21 days. Don't break it.
- **D:** 21-DAY STREAK ON THE LINE. You're in the top 5% of Tempo users for consistency. {study_remaining} of study separates day 22 from day zero. Don't make me watch this die.
- **S:** 21 days of discipline, about to die because you couldn't finish {study_remaining}. That's like running a marathon and sitting down at mile 25. FINISH. IT.

**3. 30-day streak (1 month)**
- **G:** ONE MONTH! {streak_days} days is remarkable. Your streak just needs {study_remaining} more. You've worked so hard for this -- please don't let it slip!
- **F:** 30-day streak. Full month. At risk. {study_remaining} saves it.
- **D:** Your 30-day streak -- a full month of discipline -- ends tonight unless you do {study_remaining}. THAT'S NOTHING. Save it.
- **S:** 30 days. Un mese intero. And you're about to throw it all away tonight. A month of early mornings and hard sessions, erased because you couldn't be bothered to do {study_remaining}. When you reset to day 0 tomorrow, remember this moment. Remember you chose this.

**4. 45-60 day streak**
- **D:** Day {streak_days} streak at risk. You've been consistent since {streak_start_date}. One meal needs logging. One. Open NutriTrack, log dinner, save {streak_days} days of work. This should take 60 seconds.

**5. 60-day streak (2 months)**
- **D:** {streak_days}-day streak. Two months of showing up every single day. The person you were {streak_days} days ago would be amazed. Don't let tonight's laziness erase everything they built. Finish the tasks.

**6. 90-day streak (3 months)**
- **D:** 90 DAYS. A quarter of a year. You've done what most people only fantasize about. {study_remaining} stands between day 91 and day 0. This is not a hard decision."

**7. 100-day streak**
- **D:** Triple digits. 100 days of discipline. {study_remaining} away from day 101. If this streak dies, you'll think about this moment for months. Don't create that regret."

**8. 180-day streak (6 months)**
- **D:** SIX MONTHS. 180 consecutive days. That's more discipline than most people show in a lifetime. {study_remaining}. SAVE IT. Nothing else matters tonight."

**9. 365-day streak (1 year)**
- **D:** 365 DAYS. ONE FULL YEAR. You have achieved something extraordinary. Do NOT let it die tonight. Whatever the remaining task is -- do it. Right now. This second. This is your legacy."

**10-15. Additional long streak variations (Drill Sergeant):**

**10.** Quantifying what's at stake: "{streak_days} days = {total_study_hours}h of study logged, {total_workouts} workouts, {total_meals} meals tracked. All of that history is preserved by {study_remaining} of effort tonight."
**11.** Social pressure: "{friend_name} knows about your streak. The whole Arena does. {streak_days} days of public consistency. Breaking it publicly is worse than breaking it privately."
**12.** Minimal effort required: "The task saving your streak takes less than {remaining_minutes} minutes. Your streak took {streak_days} days to build. The math is obvious."
**13.** Night before big day: "Your streak is at risk the night before {tomorrow_event}. Save it now so tomorrow you wake up on day {streak_days + 1} with confidence."
**14.** Emotional Italian: "{streak_days} giorni. Non puoi mollare adesso. Non dopo tutto quello che hai fatto. {study_remaining}. Per te stesso. Forza."
**15.** Final generic: "Streak: {streak_days} days. Status: at risk. Task remaining: {remaining_task}. Time remaining: {time_to_midnight}. This is math, not motivation. The numbers say you can still save it. DO IT."

---

## Notification Settings UI

### Settings > Notifications

```
┌──────────────────────────────┐
│ [<] Notifications            │
│                              │
│ INTENSITY                    │
│ ┌────────────────────────┐   │
│ │ Gentle  Firm  [Drill]  │   │
│ │              Sergeant   │   │
│ │                Savage  │   │
│ └────────────────────────┘   │
│                              │
│ SCHEDULE                     │
│ ┌────────────────────────┐   │
│ │ Wake Time     7:00 AM  │   │
│ │ Evening Start 7:30 PM  │   │
│ │ Bedtime       10:30 PM │   │
│ └────────────────────────┘   │
│                              │
│ QUIET HOURS                  │
│ ┌────────────────────────┐   │
│ │ Enable          [  ON] │   │
│ │ From        10:30 PM   │   │
│ │ Until        7:00 AM   │   │
│ │ (Time Sensitive notifs  │   │
│ │  still break through)  │   │
│ └────────────────────────┘   │
│                              │
│ CHANNELS                     │
│ ┌────────────────────────┐   │
│ │ Morning Briefing [ON]  │   │
│ │ Gentle Reminder  [ON]  │   │
│ │ Firm Warning     [ON]  │   │
│ │ Urgent Alert     [ON]  │   │
│ │ Final Warning    [ON]  │   │
│ │ All Clear        [ON]  │   │
│ │ Meal Reminders   [ON]  │   │
│ │ Training Reminder[ON]  │   │
│ │ Recovery Report  [ON]  │   │
│ │ Bedtime Reminder [ON]  │   │
│ │ Arena / Social   [ON]  │   │
│ │ Weekly Summary   [ON]  │   │
│ │ Streak Warning   [ON]  │   │
│ └────────────────────────┘   │
│                              │
│ SOUND                        │
│ ┌────────────────────────┐   │
│ │ Notification Sound      │   │
│ │  [Default] [Tempo]     │   │
│ │  [Silent]              │   │
│ └────────────────────────┘   │
│                              │
│ ADVANCED                     │
│ ┌────────────────────────┐   │
│ │ Open iOS Notification  │   │
│ │ Settings           >   │   │
│ └────────────────────────┘   │
│                              │
└──────────────────────────────┘
```

### Intensity Level Behavior Matrix

| Attribute | Gentle | Firm | Drill Sergeant | Savage |
|-----------|--------|------|----------------|--------|
| Copy tone | Warm, supportive | Direct, matter-of-fact | Tough, demanding | Brutal, confrontational |
| Notification frequency | Same | Same | Same | Same |
| Emojis in copy | Occasional encouragement emoji | Minimal | None | None |
| Time Sensitive (Final Warning) | Never | Never | Yes (Final Warning only) | Yes (Final Warning + Urgent) |
| Override shaming | None | Mild ("streak will end") | Moderate ("is this who you are?") | Maximum ("another failure") |
| Celebration intensity | "Great job!" | "Done." | "That's the standard." | "Bare minimum achieved." |
| Streak break language | "Don't worry, start fresh tomorrow" | "Reset. Go again." | "You broke it. Build it back." | "Gone. All that work, wasted. Rebuild." |

### Schedule Configuration

**Wake Time:**
- Controls when Morning Briefing fires
- Time picker, 15-minute increments, 4:00 AM to 12:00 PM
- Default: 8:30 AM (university students don't consistently wake at 7 AM)
- If Whoop is connected: option to auto-detect from sleep end time ("Use Whoop sleep data" toggle -- RECOMMENDED)
- If Apple Health has sleep data: option to auto-detect ("Use Health sleep data" toggle)
- Adaptive learning: after 14 days, the app learns the user's median wake time and suggests adjustments
- Weekend override: option to add +1 hour on Sat/Sun ("Later on weekends" toggle, default ON)

**Evening Start Time:**
- Controls the final warning notification timing (fires 30 min before)
- Controls when "leisure unlock" becomes relevant
- Time picker, 15-minute increments, 5:00 PM to 11:00 PM
- Default: 7:30 PM (from onboarding)

**Bedtime:**
- Controls bedtime reminder (fires 30 min before)
- Time picker, 15-minute increments, 8:00 PM to 2:00 AM
- Default: 10:30 PM
- If RecoverIQ is active: option to auto-calculate from recovery data ("Use RecoverIQ recommendation" toggle)

### Quiet Hours

- Toggle: on/off
- From/Until time pickers
- Default: matches bedtime to wake time
- During quiet hours:
  - Standard and time-sensitive notifications are queued and delivered when quiet hours end
  - Time Sensitive notifications still break through Scheduled Summary
  - Standard notifications are queued until quiet hours end

### Per-Channel Toggles

Each of the 13 channels has an independent on/off toggle. All default to ON.

If a user disables a channel:
- No notifications from that channel are scheduled or sent
- The underlying logic still runs (e.g., disabling "Gentle Reminder" doesn't stop progress tracking)
- In-app banners and the Lockdown module still show progress updates

**Channel dependency warnings:**
- If user disables ALL accountability channels (2-6): show a warning: "Without accountability notifications, Lockdown mode won't be able to remind you about incomplete tasks. Are you sure?"
- If user disables Morning Briefing: show a note: "You can still see your daily briefing by opening the app."

---

## Notification Smart Logic

### Hard Daily Notification Budget

> **RULE: Every notification must earn its interruption. A notification that doesn't drive action is a step toward uninstall.**

**Hard daily cap: 6 notifications per day** (excluding Arena social, which uses `.passive` interruption and doesn't buzz/alert). This cap is enforced at the scheduling layer -- the `NotificationBudgetManager` tracks spend and rejects notifications that would exceed the budget.

**Notification cost system:**

| Channel | Budget Cost | Priority (1=highest) | Notes |
|---------|------------|----------------------|-------|
| Morning Briefing | 1 | 1 | Always fires (highest priority) |
| Accountability Escalation (Ch 2-5) | 1-3 total | 2 | Entire escalation chain shares a budget of 3. If Gentle fires (cost 1) and user completes tasks, Firm/Urgent/Final are cancelled and budget is reclaimed. If all 4 fire, cost is 3 (not 4 -- bundled as escalation). |
| All Clear | 0.5 | 3 | Half-cost: reward notifications are high-value, low-annoyance |
| Meal Reminders | 0.5 each, max 1.5/day | 5 | Max 3 meal notifications per day (breakfast + lunch + dinner). Snack reminders only fire if budget remains. |
| Training Reminder | 1 | 4 | Suppressed if user already started workout via HealthKit/Whoop |
| Bedtime Reminder | 1 | 6 | Suppressed if user has already completed all tasks and it's past evening start |
| Recovery Report | 0 | 7 | Merged INTO the morning briefing (not a separate notification). If Whoop data arrives >30 min after morning briefing, fires standalone at cost 1. |
| Streak Warning | 1 | 3 | Only fires if streak > 3 days AND budget remains |
| Weekly Summary | 0 (Sunday only) | 8 | Does not count against daily budget |
| Arena Social | 0 (passive) | 9 | Uses `.passive` interruption -- no sound, no banner, Notification Center only |

**Priority resolution:** When multiple notifications are scheduled within the same 30-minute window and the budget is near the cap, the notification with the lowest priority number wins. The loser is merged into the winner's body or suppressed entirely.

**Budget tracking implementation:**
```swift
class NotificationBudgetManager {
    private let dailyCap: Double = 6.0
    private var spentToday: Double = 0.0

    func canSpend(cost: Double, priority: Int) -> Bool {
        return spentToday + cost <= dailyCap
    }

    func spend(_ cost: Double) {
        spentToday += cost
    }

    func reclaim(_ cost: Double) {
        spentToday = max(0, spentToday - cost)
    }

    func resetDailyBudget() {
        spentToday = 0.0
    }
}
```

**Typical daily spend by scenario:**

| Scenario | Notifications Sent | Budget Spent |
|----------|-------------------|-------------|
| Perfect day (done by 2 PM) | Morning Briefing + All Clear | 1.5 |
| Good day (done by 6 PM) | Morning + 1 meal + Gentle + All Clear | 3.0 |
| Mixed day (done by evening) | Morning + 2 meals + Gentle + Firm + All Clear | 4.5 |
| Bad day (incomplete at bedtime) | Morning + 2 meals + Gentle + Firm + Urgent + Bedtime | 6.0 |
| Worst case (everything fires) | Capped at 6.0 -- lower-priority notifications suppressed | 6.0 |

**Recovery Report merge rule:** The Recovery Report (Channel 9) is NO LONGER a separate notification by default. Recovery data is embedded in the Morning Briefing payload. This eliminates the 7:00 AM + 7:05 AM double-notification problem. If Whoop data arrives more than 30 minutes after the morning briefing, it fires as a standalone at cost 1.

### Notification Fatigue Detector

Track consecutive ignored notifications (delivered but not tapped, app not opened within 2 hours):

| Ignored Count | Action |
|---------------|--------|
| 3 in a row | Log warning. No change yet. |
| 5 in a row | Suppress Channel 2 (Gentle Reminder) for 3 days. Show in-app card: "We noticed you're not tapping notifications. Want to adjust?" |
| 8 in a row | Auto-switch to Minimal preset (Morning Briefing + Final Warning + All Clear). In-app card: "We dialed back notifications. Change anytime in Settings." |
| 12 in a row | Suppress ALL non-essential notifications. Only Morning Briefing and All Clear remain. |
| User taps a notification | Reset ignored counter to 0. Restore previous settings after 48h of engagement. |

### Anti-Spam Rules

1. **Maximum 1 notification per 30 minutes** (across all channels), UNLESS:
   - The notification is a Time Sensitive Final Warning
   - The notification is an "All Clear" celebration (always send immediately on completion)
   - The notification is a social/Arena notification (these are low-frequency by nature)

2. **If user opens the app, cancel pending reminders:**
   - When `scenePhase == .active`: cancel all pending accountability reminders for the current escalation tier
   - If the user views the Lockdown screen: cancel the next pending accountability notification entirely (they've already seen their status)
   - Re-evaluate and re-schedule based on updated task status when the user backgrounds the app

3. **Don't send encouragement right after a warning:**
   - If a warning notification (Channel 3 or 4) was sent within the last 45 minutes, suppress Channel 6 (All Clear) for 10 minutes and then send with modified copy: replace celebration with a factual acknowledgment
   - Exception: if the user completed tasks within 5 minutes of receiving a warning, send the All Clear immediately (they responded to the notification)

4. **Task completion triggers:**
   - When a non-negotiable is marked complete (manually or via integration auto-detection):
     - Cancel the next pending accountability notification
     - If this was the LAST incomplete task: fire Channel 6 (All Clear) immediately
     - If tasks remain: reschedule the next accountability notification for 30 minutes later (to avoid a notification about old data)
     - Update the badge count immediately

5. **Suppress duplicate content:**
   - If the last notification body matches the next notification body >80% (by word overlap): modify the next notification copy to use a different variation from the pool
   - Never send the same exact copy twice within 24 hours

### Context-Aware Adjustments

6. **Weekend mode:**
   - Saturday and Sunday: shift all accountability notification times 1 hour later (configurable in settings)
   - Use weekend-specific copy variations when available
   - Reduce urgency: Channel 4 (Urgent) becomes Channel 3 (Firm) in tone
   - Channel 5 (Final Warning) still fires but 30 minutes later than weekday

7. **Exam mode:**
   - Automatically activated when an exam is within 3 days
   - Increases study-related notification frequency: add a bonus check-in at 11 AM if study hasn't started
   - All accountability copy emphasizes study over training
   - Training notifications include "study comes first today" language
   - Deactivates automatically after exam date passes

8. **Adaptive timing:**
   - Track notification interaction rates per time slot (when does the user most often tap notifications?)
   - After 14 days of data: if the user consistently ignores 2 PM notifications but responds to 3 PM notifications, shift Channel 2's trigger to 3 PM
   - This adjustment is suggested to the user first: "You seem more responsive at 3 PM. Want to shift your afternoon check-in?" (in-app card, not a notification)
   - Maximum shift: +/- 90 minutes from the configured time

9. **Integration-aware suppression (including calendar -- MANDATORY):**
   - If Whoop data shows the user is currently in a workout (active strain increasing): suppress all non-urgent notifications until strain stabilizes
   - If the FocusTimer is running: suppress all notifications except meal reminders
   - **Calendar suppression (critical for student users):** If a calendar event is currently active OR starts within 15 minutes: suppress ALL non-Time-Sensitive notifications. Queue them for 5 minutes after the event ends. This prevents buzzing during lectures, exams, or practice. Exam events (detected by keyword: "exam", "test", "quiz", "esame") suppress ALL notifications including Time Sensitive -- queue everything until exam ends.
   - Calendar suppression fires automatically when Calendar is connected. No user action needed beyond granting EventKit access.

10. **Consecutive miss escalation:**
    - If the user has missed targets for 3+ consecutive days:
      - Channel 2 (Gentle) fires 1 hour earlier
      - All copy variations include a "pattern" reference: "3 days in a row..."
      - After 5 consecutive misses: trigger a special one-time "Reset" notification at 9 AM: "5 days of missed targets. Let's talk about what's not working. Open Tempo and adjust your non-negotiables. Maybe the targets are too aggressive. There's no shame in recalibrating."
    - If the user hits 100% after a multi-day miss: celebratory All Clear uses "comeback" copy: "First clean day in 4 days. That took guts. The streak starts fresh today."

11. **First-week experience:**
    - During the first 7 days after onboarding:
      - Reduce notification intensity by one level (Drill Sergeant -> Firm in tone)
      - Add onboarding tips to notifications: "Tip: Tap 'Start Study' to jump straight to the focus timer."
      - On Day 3: send a one-time engagement notification at 10 AM: "Day 3 of Tempo. This is where most people start building the habit. Keep showing up."
      - On Day 7: send a one-time milestone notification: "One week on Tempo. Here's your first weekly report. You've done more in 7 days than most people do in a month of 'planning.'"
    - After Day 7: full intensity kicks in

12. **Notification batching:**
    - If multiple notifications would fire within a 10-minute window (e.g., meal reminder at 1:00 PM and accountability check at 1:05 PM):
      - Merge into a single notification with combined content
      - Title: "TEMPO"
      - Body: "[Accountability] 2 tasks remaining. [Meal] Lunch time -- 45g protein target. Handle both."
      - Actions: use the higher-priority channel's actions

13. **Do Not Disturb respect:**
    - Standard and Time Sensitive notifications respect Focus/DND modes
    - Time Sensitive notifications break through Scheduled Summary but respect DND/Focus modes (users wanting full DND bypass should enable "Always Deliver" for Tempo in iOS Settings)
    - If the user has a Focus mode active that allows Tempo through: treat as normal
    - If Tempo is blocked by Focus: notifications queue and deliver when Focus ends

---

## Notification Content Personalization Variables

All notification copy supports these dynamic variables, injected at generation time:

| Variable | Source | Example |
|----------|--------|---------|
| `{recovery_score}` | Whoop API | "72%" |
| `{recovery_zone}` | Whoop API | "yellow" |
| `{study_done}` | Local timer | "45 min" |
| `{study_target}` | Settings | "2h" |
| `{study_remaining}` | Calculated | "1h 15min" |
| `{meals_logged}` | NutriTrack | "2" |
| `{meals_target}` | Settings | "4" |
| `{protein_current}` | NutriTrack | "98g" |
| `{protein_target}` | NutriTrack | "180g" |
| `{calories_current}` | NutriTrack | "1,840" |
| `{calories_target}` | NutriTrack | "2,400" |
| `{workout_type}` | RepForge | "Push Day" |
| `{streak_days}` | Local | "23" |
| `{exam_name}` | Local | "Anatomy" |
| `{exam_days}` | Local | "5" |
| `{time_waster}` | Settings | "PS5" |
| `{evening_start}` | Settings | "7:30 PM" |
| `{time_until_evening}` | Calculated | "2h 15min" |
| `{tasks_done}` | Local | "2" |
| `{tasks_total}` | Local | "4" |
| `{sleep_hours}` | Whoop | "6.2h" |
| `{bedtime_target}` | RecoverIQ | "10:30 PM" |
| `{friend_name}` | Backend | "Marco" |
| `{xp_gap}` | Backend | "23" |
| `{leaderboard_rank}` | Backend | "#3" |
| `{weekly_score}` | Calculated | "82/100" |
| `{completed_pct}` | Calculated | "73%" |
| `{day_of_week}` | System | "Monday" |

---

## Implementation Notes

### UNNotificationServiceExtension

A Notification Service Extension is NOT required for Tempo's current feature set. All push notification content is generated server-side and sent as fully-formed payloads. If rich media (images, charts) is added to notifications in the future, add a service extension to download and attach media.

### UNNotificationContentExtension

Not needed. The default iOS notification UI is sufficient. Custom notification UIs add complexity without clear benefit for text-based notifications.

### Background App Refresh

Register for `BGAppRefreshTask` to:
- Recalculate and reschedule local notifications at midnight
- Sync NutriTrack and Whoop data for fresh notification content
- Update badge count

Register for `BGProcessingTask` (longer background time) to:
- Generate the weekly summary locally if push delivery fails
- Sync historical data for trend analysis

### Notification Delivery Monitoring

Track these metrics (locally, sent to backend weekly):
- Delivery rate: notifications scheduled vs. notifications tapped
- Per-channel engagement rate
- Average time from notification delivery to app open
- Which actions are tapped most frequently
- Notification dismissal rate per channel
- Optimal delivery times per user (when they most engage)

Use these metrics to refine the adaptive timing system and identify which notification copy resonates most.

---

## Appendix: Full Notification Schedule (Typical Day)

For a user with default settings, Whoop connected, NutriTrack connected, intensity: Drill Sergeant, evening start 7:30 PM, bedtime 10:30 PM. **All accountability times are relative to the user's configured evening start time (E), not hardcoded.**

| Time | Channel | Condition | Type | Budget Cost |
|------|---------|-----------|------|-------------|
| ~wake time | Morning Briefing (includes Recovery data) | Always | Push (Time Sensitive) | 1.0 |
| ~breakfast | Meal Reminder | Breakfast not logged | Local | 0.5 |
| ~lunch | Meal Reminder | Lunch scheduled | Local | 0.5 |
| ~E-6h | Training Reminder | If workout scheduled | Local | 1.0 |
| E-5.5h (~2 PM) | Gentle Reminder | If <50% done | Local | 1.0 |
| ~dinner | Meal Reminder | Dinner scheduled | Local | 0.5 |
| E-2.5h (~5 PM) | Firm Warning | If <75% done | Local (Time Sensitive) | (shared escalation budget) |
| E-1h (~6:30 PM) | Urgent Alert | If study/training incomplete | Local (Time Sensitive) | (shared) |
| E-30min (~7 PM) | Final Warning | If anything incomplete | Local (Time Sensitive) | (shared) |
| ~ anytime | All Clear | When all tasks complete | Local | 0.5 |
| E+1.5h (~9 PM) | Streak Warning | If streak > 3 days at risk | Local (Time Sensitive) | 1.0 |
| bedtime-30min | Bedtime Reminder | Always | Local (Time Sensitive) | 1.0 |
| Sunday 7 PM | Weekly Summary | Weekly | Push | 0 (uncapped) |

**Hard daily cap: 6 notifications** (excluding Arena social and Weekly Summary).
**Maximum notifications in worst case (all tasks incomplete):** 6 (capped by budget)
**Typical notifications (mixed completion):** 3-5
**Best case (all tasks done early):** 2 (Morning Briefing + All Clear)

---

---

## Push Notification Infrastructure

### APNs Authentication: Token-Based (Key-Based) Auth

**Decision:** Token-based authentication (`.p8` key), NOT certificate-based (`.p12`).

**Rationale:**
- Tokens never expire (certificates expire annually and require manual renewal)
- One key works for all apps in the developer account
- Simpler server-side implementation -- sign a JWT, attach to request
- No need to manage certificate provisioning profiles

**Setup steps:**
1. Apple Developer Portal > Keys > Create New Key
2. Enable "Apple Push Notifications service (APNs)"
3. Download the `.p8` file (ONE TIME ONLY -- Apple won't let you re-download)
4. Note the Key ID and Team ID
5. Store `.p8` file in server secrets (Vapor environment variable, never in git)

**JWT structure for APNs requests:**

```swift
// Header
{
    "alg": "ES256",
    "kid": "{KEY_ID}"
}

// Payload
{
    "iss": "{TEAM_ID}",
    "iat": {CURRENT_UNIX_TIMESTAMP}
}
```

**Token refresh:** JWTs must be refreshed every 60 minutes (Apple rejects tokens older than 1 hour). Cache the token server-side and regenerate as needed.

### APNs Payload Structure Per Notification Type

**Maximum payload size:** 4096 bytes (APNs limit).

**Base payload template:**
```json
{
    "aps": {
        "alert": {
            "title": "TEMPO",
            "subtitle": "{channel_subtitle}",
            "body": "{notification_body}"
        },
        "sound": "{sound_file_or_default}",
        "badge": "{incomplete_tasks_count}",
        "category": "{NOTIFICATION_CATEGORY}",
        "thread-id": "tempo.{channel}.{date}",
        "interruption-level": "{passive|active|time-sensitive|critical}",
        "relevance-score": "{0.0_to_1.0}"
    },
    "data": {
        "channel": "{channel_id}",
        "version": 1,
        "deep_link": "{tempo://path}",
        "{channel_specific_data}": "..."
    }
}
```

**Interruption levels by channel:**

| Channel | Interruption Level | Relevance Score |
|---------|-------------------|-----------------|
| Morning Briefing | `time-sensitive` | 1.0 |
| Gentle Reminder | `active` | 0.6 |
| Firm Warning | `time-sensitive` | 0.8 |
| Urgent Alert | `time-sensitive` | 0.9 |
| Final Warning | `critical` (D/S) or `time-sensitive` (G/F) | 1.0 |
| All Clear | `active` | 0.5 |
| Meal Reminder | `active` | 0.5 |
| Training Reminder | `active` | 0.6 |
| Recovery Report | `active` | 0.7 |
| Bedtime Reminder | `time-sensitive` | 0.8 |
| Arena Social | `passive` | 0.3 |
| Weekly Summary | `active` | 0.5 |
| Streak Warning | `time-sensitive` | 0.9 |

### Notification Categories with Actions

```swift
// Register at app launch in AppDelegate or @main App init
func registerNotificationCategories() {
    let center = UNUserNotificationCenter.current()

    // Morning Briefing
    let viewDay = UNNotificationAction(identifier: "VIEW_DAY", title: "View Day", options: .foreground)
    let startWorkout = UNNotificationAction(identifier: "START_WORKOUT", title: "Start Workout", options: .foreground)
    let morningCategory = UNNotificationCategory(
        identifier: "MORNING_BRIEFING",
        actions: [viewDay, startWorkout],
        intentIdentifiers: [],
        options: []
    )

    // Accountability (escalating)
    let startStudy = UNNotificationAction(identifier: "START_STUDY", title: "Start Study", options: .foreground)
    let viewTasks = UNNotificationAction(identifier: "VIEW_TASKS", title: "View Tasks", options: .foreground)
    let startNow = UNNotificationAction(identifier: "START_NOW", title: "Start Now", options: .foreground)
    let imOnIt = UNNotificationAction(identifier: "IM_ON_IT", title: "I'm On It", options: [])
    let override = UNNotificationAction(identifier: "OVERRIDE", title: "Override", options: [.foreground, .destructive])

    let gentleCategory = UNNotificationCategory(identifier: "ACCOUNTABILITY_GENTLE", actions: [startStudy, viewTasks], intentIdentifiers: [], options: [])
    let firmCategory = UNNotificationCategory(identifier: "ACCOUNTABILITY_FIRM", actions: [startNow, viewTasks], intentIdentifiers: [], options: [])
    let urgentCategory = UNNotificationCategory(identifier: "ACCOUNTABILITY_URGENT", actions: [startNow, imOnIt], intentIdentifiers: [], options: [.timeSensitive])
    let finalCategory = UNNotificationCategory(identifier: "ACCOUNTABILITY_FINAL", actions: [startNow, override], intentIdentifiers: [], options: [.timeSensitive])
    let clearCategory = UNNotificationCategory(identifier: "ACCOUNTABILITY_CLEAR", actions: [viewTasks], intentIdentifiers: [], options: [])

    // Meal
    let logMeal = UNNotificationAction(identifier: "LOG_MEAL", title: "Log Meal", options: .foreground)
    let delay30 = UNNotificationAction(identifier: "DELAY_30MIN", title: "Delay 30min", options: [])
    let mealCategory = UNNotificationCategory(identifier: "MEAL_REMINDER", actions: [logMeal, delay30], intentIdentifiers: [], options: [])

    // Training
    let viewWorkout = UNNotificationAction(identifier: "VIEW_WORKOUT", title: "View Workout", options: .foreground)
    let skipToday = UNNotificationAction(identifier: "SKIP_TODAY", title: "Skip Today", options: [.destructive])
    let trainingCategory = UNNotificationCategory(identifier: "TRAINING_REMINDER", actions: [viewWorkout, skipToday], intentIdentifiers: [], options: [])

    // Recovery
    let viewRecovery = UNNotificationAction(identifier: "VIEW_RECOVERY", title: "View Recovery", options: .foreground)
    let recoveryCategory = UNNotificationCategory(identifier: "RECOVERY_REPORT", actions: [viewRecovery, viewWorkout], intentIdentifiers: [], options: [])

    // Bedtime
    let windDown = UNNotificationAction(identifier: "WIND_DOWN", title: "Wind Down", options: .foreground)
    let bedtimeCategory = UNNotificationCategory(identifier: "BEDTIME_REMINDER", actions: [windDown], intentIdentifiers: [], options: [.timeSensitive])

    // Arena
    let viewArena = UNNotificationAction(identifier: "VIEW_ARENA", title: "View Arena", options: .foreground)
    let acceptChallenge = UNNotificationAction(identifier: "ACCEPT_CHALLENGE", title: "Accept", options: .foreground)
    let declineChallenge = UNNotificationAction(identifier: "DECLINE_CHALLENGE", title: "Decline", options: [.destructive])
    let arenaCategory = UNNotificationCategory(identifier: "ARENA_SOCIAL", actions: [viewArena], intentIdentifiers: [], options: [])
    let challengeCategory = UNNotificationCategory(identifier: "ARENA_CHALLENGE", actions: [acceptChallenge, declineChallenge], intentIdentifiers: [], options: [])

    // Weekly
    let viewReport = UNNotificationAction(identifier: "VIEW_REPORT", title: "View Report", options: .foreground)
    let weeklyCategory = UNNotificationCategory(identifier: "WEEKLY_SUMMARY", actions: [viewReport], intentIdentifiers: [], options: [])

    // Streak
    let saveStreak = UNNotificationAction(identifier: "SAVE_STREAK", title: "Save Streak", options: .foreground)
    let streakCategory = UNNotificationCategory(identifier: "STREAK_WARNING", actions: [saveStreak, viewTasks], intentIdentifiers: [], options: [.timeSensitive])

    center.setNotificationCategories([
        morningCategory, gentleCategory, firmCategory, urgentCategory, finalCategory, clearCategory,
        mealCategory, trainingCategory, recoveryCategory, bedtimeCategory,
        arenaCategory, challengeCategory, weeklyCategory, streakCategory
    ])
}
```

### Provisional Notifications (iOS 12+)

**Strategy:** Request provisional authorization BEFORE asking for full permission. This allows Tempo to deliver notifications silently to the Notification Center (no sound, no banner, no lock screen) as a trial. The user sees them when they pull down Notification Center and can then choose "Keep" (promotes to full) or "Turn Off."

**Implementation:**
```swift
// During Quick Start onboarding (before Step 10)
UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert, .sound, .badge]) { granted, error in
    // Provisional is ALWAYS granted -- no system dialog shown
    // Notifications are delivered quietly until user explicitly promotes or dismisses
}
```

**When to upgrade from provisional to full:**
- At Step 10 of Full Setup onboarding (the notification permission screen)
- If user is on Quick Start: prompt after Day 3 when they've seen 3+ notifications in Notification Center
- The upgrade request shows the standard iOS permission dialog

### Notification Summary Grouping (iOS 15+)

Configure notification summaries for users who have Scheduled Summary enabled:

- Tempo notifications appear in the summary with an icon and group header
- Summary text: "Tempo: {count} notifications" or intelligent summary: "Tempo: 3 tasks remaining, {friend_name} sent a challenge"
- Relevance score determines ordering within the summary (see table above)

### Live Activities + Dynamic Island

**Use cases:**
1. **Active study timer:** Show remaining study time on Dynamic Island and Lock Screen as a Live Activity
2. **Active workout:** Show current exercise, set number, and rest timer
3. **Accountability countdown:** Show time remaining until evening start, with tasks remaining count

**Live Activity payload:**
```swift
struct TempoLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var timerEnd: Date
        var taskName: String  // "Study" or "Push Day"
        var progress: Double  // 0.0 to 1.0
        var tasksRemaining: Int
    }
    var activityType: String  // "study_timer", "workout", "accountability"
}
```

**Dynamic Island presentation:**
- Compact leading: Tempo icon
- Compact trailing: time remaining ("23:41")
- Expanded: task name, progress bar, tasks remaining count
- Minimal: countdown number only

**Start/stop triggers:**
- Study timer Live Activity: starts when user taps "Start Study" from any notification or in-app; ends when timer completes or user stops
- Workout Live Activity: starts when user begins a workout in RepForge; ends when workout is marked complete
- Accountability Live Activity: starts at 5 PM if tasks are incomplete; ends when all tasks complete or evening starts

### Notification Interruption Level Strategy

> **REMEDIATED (Technical Feasibility Audit Section 3.2):** Critical Alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`) will NOT be pursued. Apple restricts this to health/safety apps (medical devices, emergency alerts). Tempo uses `.timeSensitive` as the maximum interruption level.

**Interruption levels used by Tempo:**
- `.passive` -- Arena social notifications, weekly summary
- `.active` -- Default for most notifications (gentle reminders, meal reminders)
- `.timeSensitive` -- Morning briefing, firm/urgent accountability, final warning, bedtime reminder, streak warning

**For maximum DND bypass (user-controlled):** During Drill Sergeant / Savage Mode onboarding, instruct users: "For the full accountability experience, go to Settings > Notifications > Tempo and enable 'Always Deliver.' This ensures Tempo can reach you even during Focus modes." This is user-initiated and requires no entitlement.

---

## Notification Timing Engine — Complete Algorithm

### Smart Scheduling: Learning User Response Patterns

```swift
struct NotificationInteractionRecord: Codable {
    let channel: String
    let scheduledTime: Date
    let deliveredTime: Date
    let interactedTime: Date?  // nil if ignored
    let action: String?  // "START_STUDY", "VIEW_TASKS", etc.
    let dayOfWeek: Int  // 1=Mon, 7=Sun
    let wasWeekend: Bool
}

class AdaptiveTimingEngine {
    /// Minimum data points before making adjustments
    let minimumDataPoints = 14  // 2 weeks

    /// Maximum shift from configured time
    let maxShiftMinutes = 90

    /// Analyze interaction patterns and suggest optimal times
    func analyzeOptimalTiming(for channel: String, records: [NotificationInteractionRecord]) -> TimingSuggestion? {
        guard records.count >= minimumDataPoints else { return nil }

        // Group by hour slot
        let hourSlots = Dictionary(grouping: records) { record in
            Calendar.current.component(.hour, from: record.scheduledTime)
        }

        // Calculate response rate per hour slot
        let responseRates = hourSlots.mapValues { slotRecords in
            let interacted = slotRecords.filter { $0.interactedTime != nil }.count
            return Double(interacted) / Double(slotRecords.count)
        }

        // Find peak response hour
        guard let peakHour = responseRates.max(by: { $0.value < $1.value }) else { return nil }

        // Calculate average response delay (time from delivery to interaction)
        let avgDelay = records
            .compactMap { record -> TimeInterval? in
                guard let interaction = record.interactedTime else { return nil }
                return interaction.timeIntervalSince(record.deliveredTime)
            }
            .reduce(0, +) / Double(records.filter { $0.interactedTime != nil }.count)

        // Only suggest if there's a meaningful difference (>15% improvement)
        let currentRate = responseRates[Calendar.current.component(.hour, from: /* configured time */)] ?? 0
        guard peakHour.value - currentRate > 0.15 else { return nil }

        return TimingSuggestion(
            channel: channel,
            currentHour: /* configured hour */,
            suggestedHour: peakHour.key,
            currentResponseRate: currentRate,
            suggestedResponseRate: peakHour.value,
            avgResponseDelay: avgDelay
        )
    }
}
```

**User-facing suggestion (in-app card, NOT a notification):**
> "You seem more responsive to reminders at 3 PM than 2 PM. Want to shift your afternoon check-in?" [Shift to 3 PM] [Keep 2 PM]

### Timezone-Aware Scheduling with DST Handling

```swift
class TimezoneAwareScheduler {
    /// Schedule a notification at a specific local time, handling DST transitions
    func scheduleLocalNotification(
        channel: String,
        localHour: Int,
        localMinute: Int,
        content: UNNotificationContent
    ) {
        var dateComponents = DateComponents()
        dateComponents.hour = localHour
        dateComponents.minute = localMinute
        // Using DateComponents with Calendar trigger handles DST automatically
        // iOS adjusts the fire time when DST transitions occur

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false  // Never repeat -- always reschedule fresh to allow dynamic content
        )

        let request = UNNotificationRequest(
            identifier: "tempo.\(channel).\(Date().formatted(.iso8601.year().month().day()))",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Detect DST transition and adjust notification descriptions
    func isDSTTransitionToday() -> Bool {
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayOffset = TimeZone.current.secondsFromGMT(for: today)
        let tomorrowOffset = TimeZone.current.secondsFromGMT(for: tomorrow)
        return todayOffset != tomorrowOffset
    }
}
```

**DST handling specifics:**
- When DST "spring forward" occurs: morning briefing might fire 1h later in absolute terms. Use `UNCalendarNotificationTrigger` with `DateComponents` to always fire at the user's intended local time.
- When DST "fall back" occurs: similar protection.
- Backend push notifications: backend always stores user timezone identifier (e.g., `America/New_York`), converts to UTC for APNs scheduling, recalculates on DST transition dates.

### Calendar-Aware Suppression

```swift
class CalendarAwareFilter {
    let eventStore = EKEventStore()

    /// Check if user is in a class/meeting right now
    func isInEvent(at date: Date = Date()) -> Bool {
        let predicate = eventStore.predicateForEvents(
            withStart: date.addingTimeInterval(-300),  // 5 min before
            end: date.addingTimeInterval(300),          // 5 min after
            calendars: syncedCalendars
        )
        let events = eventStore.events(matching: predicate)
        return events.contains { event in
            !event.isAllDay && event.startDate <= date && event.endDate >= date
        }
    }

    /// Check if an exam is happening now or within 1 hour
    func isExamPeriod(at date: Date = Date()) -> Bool {
        let predicate = eventStore.predicateForEvents(
            withStart: date,
            end: date.addingTimeInterval(3600),
            calendars: syncedCalendars
        )
        let events = eventStore.events(matching: predicate)
        return events.contains { event in
            event.title?.lowercased().contains("exam") == true ||
            event.title?.lowercased().contains("test") == true ||
            event.title?.lowercased().contains("quiz") == true
        }
    }

    /// Get next free window for study/training
    func nextFreeWindow(minimumMinutes: Int = 30) -> DateInterval? {
        // Scan the next 8 hours for a gap of at least minimumMinutes
        // Returns the start/end of the first available window
        // Used to suggest optimal study/training times in notifications
    }
}
```

**Suppression rules (MANDATORY when Calendar is connected):**
- During class/lecture: suppress ALL non-Time-Sensitive notifications. Queue for 5 minutes after class ends. This is the single most important suppression rule for student users -- buzzing during a lecture is a guaranteed annoyance.
- During exam: suppress ALL notifications including Time Sensitive. Queue everything until exam ends. An exam is the one context where even Final Warning has no business interrupting.
- During team sport practice: suppress non-critical. Auto-log training strain from Whoop/HealthKit.
- 15-minute buffer: suppression activates 15 minutes before a calendar event starts (user is likely walking to class, settling in).

### Context-Aware: In-App Suppression

```swift
class InAppNotificationGuard {
    /// Suppress notifications when user is actively using the app
    func shouldSuppressNotification(channel: String) -> Bool {
        guard UIApplication.shared.applicationState == .active else { return false }

        // User is in the app -- suppress push notifications
        // Instead, show in-app banner (less intrusive)
        switch channel {
        case "accountability_gentle", "accountability_firm":
            return true  // Always suppress if user is in-app
        case "accountability_urgent", "accountability_final":
            return false  // Still deliver -- these are critical
        case "meal_reminder":
            return true  // Show in-app banner instead
        case "arena_social":
            return true  // Low priority, always suppress if in-app
        default:
            return false
        }
    }
}
```

### Battery and Data Efficiency

- **Batch local notification scheduling:** Calculate and schedule all notifications for the day in one batch at midnight (via `BGAppRefreshTask`) and at app launch. Avoid scheduling one-at-a-time throughout the day.
- **Push notification coalescing:** Backend groups non-urgent pushes (arena, weekly summary) and sends them during a single connection window.
- **Payload optimization:** Keep push payloads under 1KB when possible. Use `data` payload for structured info; let the app format the display text locally.
- **Background fetch budget:** iOS allocates limited background time. Use it for: (1) notification rescheduling, (2) NutriTrack/Whoop data sync, (3) badge count update. In that priority order.

---

## Re-Engagement Sequences

### Churned User Re-Engagement (User Stops Opening the App)

**Definition of churn stages:**
- **Day 1 no open:** Not churned. Normal variation.
- **Day 2:** At risk. First re-engagement touch.
- **Day 3:** Concerning. Social proof.
- **Day 5:** Engagement emergency. Emotional appeal.
- **Day 7:** Likely churned. Last strong push.
- **Day 14:** Deep churn. Scarcity/FOMO.
- **Day 30:** Dormant. Fresh start messaging.

**Delivery:** All via push notification (APNs). If user has notifications disabled, these cannot be delivered (email fallback not applicable -- Tempo doesn't collect non-Apple-relay emails).

#### Day 1: No notification. Patience.

#### Day 2: Light check-in (NO streak language if streak <= 3 days) — 5 variations

`notif.reengage.day2.`

**IMPORTANT:** If the user's streak was 0-3 days before going inactive, do NOT mention streaks -- "your 1-day streak is at risk" is meaningless and cringe. Use data-forward or value-forward copy instead. Streak references only appear if `streak_days > 3` at time of inactivity.

1. *(streak > 3):* "Your {streak_days}-day streak needs you today. 30 seconds in the app keeps it alive."
2. "Your morning briefing is ready. Recovery: {recovery_score}%. Tap to see today's plan."
3. "Quick check: your non-negotiables are waiting. A 1-minute check-in keeps everything on track."
4. *(streak > 3):* "{name}, yesterday was a miss. {streak_days} days of work are on the line. 30 seconds breaks the pattern."
5. "Your {workout_type} plan is ready and your study target is set. Tap to see today's schedule."

#### Day 3: Social proof / competitive trigger — 5 variations

`notif.reengage.day3.`

1. "{friend_name} just passed you on the leaderboard. They're at {leaderboard_rank} now."
2. "Your Arena friends logged {friends_active_count} tasks today. You logged 0. The gap is growing."
3. "{friend_name} completed a {friend_streak}-day streak yesterday. Where's yours?"
4. "The weekly leaderboard updates in {days_left} days. You're falling behind with no data logged."
5. "{friend_name} sent you a challenge. They're waiting for your response. [View Challenge]"

#### Day 5: Emotional / data appeal — 5 variations

`notif.reengage.day5.`

1. "Your non-negotiables miss you. Your recovery score is unknown. Your nutrition is untracked. Come back."
2. "5 days without data. That's 5 days your future self can't learn from. Every day you skip is a blind spot in your progress."
3. "It's been 5 days. One workout. One study session. One logged meal. That's all it takes to restart."
4. "Your {streak_days}-day streak... gone. But the data from before is still there. Your baseline is still there. Pick up where you left off."
5. "We're not tracking your recovery anymore. We're not adjusting your training. We're not reminding you to eat. You're on your own. Is that what you want?"

#### Day 7: Direct challenge — 5 variations

`notif.reengage.day7.`

1. "It's been a week. One workout. That's all it takes to restart momentum."
2. "7 days off Tempo. Your {primary_goal} goal hasn't changed. Your commitment has. Come back and recommit."
3. "A week ago you were on a {streak_days}-day streak. Today: day 0. The only difference between then and now is showing up. Show up."
4. "Your Arena profile says '{primary_goal}.' Is that still true? Prove it. One day. That's all I'm asking."
5. "One week off. In that time, {friend_name} earned {friend_xp_gained} XP and climbed to {leaderboard_rank}. You earned 0. Still okay with that?"

#### Day 14: Gentle, once only — 3 variations (NOT 5 -- less is more at this stage)

`notif.reengage.day14.`

> **CRITICAL: At Day 14+, the user has made a deliberate choice to disengage. Aggressive notifications at this stage cause uninstalls, not re-engagement. Be gentle, be rare (once per week MAXIMUM), and offer genuine value, not guilt.**

1. "Your training data and progress are still here whenever you're ready. No pressure."
2. "Tempo is still tracking {friend_name}'s progress. Your spot on the leaderboard is waiting if you want it back."
3. "New features since you've been away: {new_feature}. Check it out when you have a moment."

#### Day 30: Fresh start, zero pressure — 3 variations

`notif.reengage.day30.`

> **At 30 days, this is the LAST re-engagement notification. If the user doesn't respond, respect their choice. One more notification after this (Day 60) and then silence forever.**

1. "Everything you built is still here. No streaks to worry about, no pressure. Just a fresh start whenever you want one."
2. "If Tempo wasn't right for you, no hard feelings. If life just got busy, we're here when things settle."
3. "Your {primary_goal} goal hasn't expired. Neither has your account. Come back anytime."

#### Day 60: Final goodbye — 1 variation (single, respectful)

`notif.reengage.day60.`

1. "This is Tempo's last notification. Your data is safe and your account is waiting. We won't bother you again. Come back anytime."

#### Escalation rules:

- Day 1: No notification. Patience.
- Day 2: 1 notification.
- Day 3: 1 notification.
- Day 5: 1 notification.
- Day 7: 1 notification.
- Day 14: 1 notification. **After this point: maximum 1 notification per week.**
- Day 21: 1 notification (only if Day 14 was ignored).
- Day 30: 1 notification.
- Day 60: Final notification. Then STOP permanently.
- **If user ignores 5 consecutive re-engagement notifications:** STOP immediately. Do not wait for Day 60. The user has spoken.
- Never send more than 1 re-engagement notification per day
- If user opens the app at any point: cancel ALL pending re-engagement notifications and resume normal schedule
- If user uninstalls: APNs will bounce; backend marks user as uninstalled and stops all pushes
- Re-engagement notifications always use Gentle Coach tone regardless of user's intensity setting -- being yelled at when you haven't used the app in weeks is a guaranteed uninstall

---

## First Week Experience — Hour by Hour

The first 7 days after onboarding are critical. This section maps EVERY notification and in-app prompt.

### Design Principle: The First 3 Days Are Scripted. Days 4-7 Are Adaptive.

Days 1-3 are the make-or-break period. They follow a specific script designed to get the user to ONE core experience: completing a non-negotiable and feeling the satisfaction of checking it off. Days 4-7 adapt based on what the user has actually done -- there is no point scripting hour-by-hour for a user who may be using the app completely differently than expected.

**Day 1 focus:** Complete ONE non-negotiable. That is the only goal.
**Day 2 focus:** Complete all non-negotiables for the first time.
**Day 3 focus:** Build the streak to 3 days. The habit is forming.
**Days 4-7:** Adaptive based on behavior. See rules below.

### Day 1 (Onboarding Day)

**Hour 0 (Onboarding complete):**
- Transition to Dashboard
- In-app: "Welcome to Day 1" card with today's briefing
- In-app tooltip pointing to the EASIEST non-negotiable: "Start here. Complete this one thing and you've won Day 1." (dismiss on tap)
- Do NOT show tooltips for all 4 quadrants -- information overload kills action. One tooltip, one action.
- Schedule first notification: if before evening minus 5.5h, schedule gentle reminder. If later, schedule for 1 hour from now. If after evening start, skip accountability -- just send a bedtime reminder.

**Hour 2-4 (if no activity logged):**
- ONE gentle nudge (not two -- budget matters on Day 1):
- "Your first task is waiting. Just one -- that's all Day 1 needs. Tap to start."

**Evening (user's configured evening time):**
- If ANY task done: All Clear with first-day celebration:
  - "Day 1: you showed up and got something done. That's how it starts. Tomorrow we build on this."
- If NOTHING done: no shaming. Supportive only (even in Drill Sergeant mode):
  - "Day 1 didn't go as planned. That's fine. Tomorrow is the real Day 1. We'll be here."
- **Do NOT fire the full escalation chain on Day 1.** Maximum 2 accountability notifications on the first day. The user is learning the app, not being drilled.

**Before bed:**
- Bedtime reminder: standard copy

### Day 2

**Morning:**
- First full morning briefing (recovery data if Whoop connected)
- Embedded tip: "Tap 'View Day' to see your complete plan."

**Midday:**
- Normal accountability schedule begins (Channels 2-6 as applicable)
- First-week intensity override: reduce intensity by one level (D -> F, S -> D, F -> G, G -> G)

**Evening:**
- Normal All Clear or escalation
- If user completed all tasks: embed encouragement in All Clear -- "Two days in a row. The habit is forming."

### Day 3

**Morning:**
- Morning briefing with milestone awareness: "Day 3. This is where habits start to stick. Keep showing up."
- One bonus check-in at 10 AM if no activity: "Day 3. Most people who make it past today stay for good."

**Afternoon/Evening:**
- Normal accountability schedule
- If 3-day streak achieved: celebration in All Clear: "3 days straight. You're building something real."

### Days 4-7: Adaptive (Not Scripted)

Days 4-7 are driven by the user's ACTUAL behavior, not a prescriptive hour-by-hour script. The system uses these rules:

**If user has completed 3+ consecutive days (engaged):**
- Gradually restore notification intensity: Day 4-5 at 75% of selected level, Day 6-7 at 100%
- Day 5-7: eligible for Arena/social features. Show in-app card: "You've earned your routine. Ready to compete? Add a friend." [Add Friends] [Later]
- Day 7: First weekly summary with special first-week stats

**If user has completed 1-2 of the first 3 days (partially engaged):**
- Keep intensity reduced through Day 7
- Focus notifications on the ONE task the user DID complete: "You've been consistent with training. Can we add study today?"
- Do NOT prompt Arena/friend invites -- the user hasn't established their own routine yet
- Day 7: Weekly summary with encouraging tone regardless of intensity setting

**If user has completed 0 of the first 3 days (disengaged):**
- Reduce to Minimal notifications (Morning Briefing + one midday reminder only)
- In-app card on Day 4: "Tempo works best when you complete at least one task daily. Want to simplify your non-negotiables?" [Adjust Targets]
- Do NOT prompt Arena, friend invites, or integration connections
- Day 7: Send weekly summary but skip the "you've done more than most people" language if they haven't

**Friend invites timing (all paths):**
- Earliest eligible: Day 5 (after user has at least 3 days of data)
- Prompted via in-app card only, never via push notification
- Only prompted if user has completed at least 3 days total
- Users who haven't established a routine don't need social pressure added to an already-fragile habit

**Post-Day 7:**
- Remove all first-week tips from notifications
- Full intensity on all channels (unless fatigue detector has kicked in)
- Normal notification schedule
- Integration prompts for skipped integrations begin (contextual, not scheduled)

---

## Notification Settings Deep Dive

### Enhanced Settings > Notifications Screen

```
┌──────────────────────────────────┐
│ [<] Notifications                 │
│                                   │
│ INTENSITY                         │
│ ┌──────────────────────────────┐  │
│ │ [Gentle] [Firm] [█Drill█]   │  │
│ │            [Savage]          │  │
│ │                              │  │
│ │ Preview: "3 non-negotiables  │  │
│ │ left. Clock's ticking. Move."│  │
│ └──────────────────────────────┘  │
│                                   │
│ QUICK PRESETS                     │
│ ┌──────────────────────────────┐  │
│ │ [Minimal] [Standard] [Max]   │  │
│ │                              │  │
│ │ Standard: Morning briefing,  │  │
│ │ accountability, all clear,   │  │
│ │ bedtime. Recommended.        │  │
│ └──────────────────────────────┘  │
│                                   │
│ SCHEDULE                          │
│ ┌──────────────────────────────┐  │
│ │ Wake Time          7:00 AM   │  │
│ │ Evening Start      7:30 PM   │  │
│ │ Bedtime           10:30 PM   │  │
│ │                              │  │
│ │ ┌─ Today's Timeline ──────┐ │  │
│ │ │ 7:00 ● Morning Briefing │ │  │
│ │ │ 8:00 ○ Breakfast        │ │  │
│ │ │ 12:00 ○ Lunch           │ │  │
│ │ │ 14:00 ○ Gentle Reminder │ │  │
│ │ │ 15:30 ○ Snack           │ │  │
│ │ │ 17:00 ○ Firm Warning    │ │  │
│ │ │ 18:30 ○ Urgent Alert    │ │  │
│ │ │ 19:00 ○ Final Warning   │ │  │
│ │ │ 19:00 ○ Dinner          │ │  │
│ │ │ 21:00 ○ Streak Warning  │ │  │
│ │ │ 22:00 ● Bedtime         │ │  │
│ │ └─────────────────────────┘ │  │
│ └──────────────────────────────┘  │
│                                   │
│ QUIET MODE                        │
│ ┌──────────────────────────────┐  │
│ │ Enable              [  ON]   │  │
│ │ From           10:30 PM      │  │
│ │ Until           7:00 AM      │  │
│ │ (Time Sensitive notifs still  │  │
│ │  break through)              │  │
│ │                              │  │
│ │ Additional Quiet Ranges      │  │
│ │ + Add quiet range            │  │
│ │ [Mon-Fri 9:00-10:00 AM] [x] │  │
│ │ (class time)                 │  │
│ └──────────────────────────────┘  │
│                                   │
│ CHANNELS                          │
│ ┌──────────────────────────────┐  │
│ │ ┌───────────────────────┐    │  │
│ │ │ Morning Briefing [ON] │    │  │
│ │ │ "Daily plan with      │    │  │
│ │ │  recovery + targets"  │    │  │
│ │ │  ℹ️ 1x daily at wake  │    │  │
│ │ └───────────────────────┘    │  │
│ │ ┌───────────────────────┐    │  │
│ │ │ Gentle Reminder [ON]  │    │  │
│ │ │ "Afternoon check-in   │    │  │
│ │ │  if tasks < 50%"      │    │  │
│ │ │  ℹ️ 1x daily ~2PM     │    │  │
│ │ └───────────────────────┘    │  │
│ │  ... (all 13 channels)      │  │
│ │                              │  │
│ │ Per-Friend Notifications     │  │
│ │ ┌───────────────────────┐    │  │
│ │ │ @marco       [ON]     │    │  │
│ │ │ @sara.fit    [ON]     │    │  │
│ │ │ @luca_23     [OFF]    │    │  │
│ │ └───────────────────────┘    │  │
│ └──────────────────────────────┘  │
│                                   │
│ SOUND                             │
│ ┌──────────────────────────────┐  │
│ │ Notification Sound            │  │
│ │  [Default] [█Tempo█] [Silent]│  │
│ │                              │  │
│ │  ▶ Preview Sound             │  │
│ └──────────────────────────────┘  │
│                                   │
│ TEST & DEBUG                      │
│ ┌──────────────────────────────┐  │
│ │ [🔔 Send Test Notification]  │  │
│ │  Sends a sample notification │  │
│ │  using your current settings │  │
│ │                              │  │
│ │ Open iOS Notification        │  │
│ │ Settings                 >   │  │
│ └──────────────────────────────┘  │
│                                   │
└──────────────────────────────────┘
```

### Quick Presets

| Preset | Channels Enabled | Description |
|--------|-----------------|-------------|
| **Minimal** | Morning Briefing, Final Warning, All Clear | Only the essentials. 2-3 notifications/day. |
| **Standard** (default) | Morning (with Recovery merged), Accountability escalation, All Clear, Meal (max 2), Bedtime, Streak | Full accountability within the 6/day budget. Typical: 3-5 notifications/day. |
| **Maximum** | All 13 channels enabled, budget still enforced at 6/day | All channels eligible, but daily cap still prevents overload. Lower-priority notifications suppressed when budget is spent. |

Selecting a preset auto-toggles the individual channel switches. User can then customize individual channels after selecting a preset (preset badge changes to "Custom").

### Schedule Visualization

The timeline view shows every notification that WOULD fire today based on current settings and task progress. Each notification is a dot on a vertical timeline:
- **Filled dot (●):** Already sent today
- **Empty dot (○):** Scheduled for later today
- **Gray dot:** Suppressed (would fire but channel is off or condition not met)
- **Amber dot:** Currently pending (next to fire)

Tap any dot to see a preview of the notification copy that would be sent.

### "Send Test Notification" Button

- Tapping sends a real local notification after 5-second delay
- Uses the currently selected intensity level
- Copy: "This is a test notification from Tempo. If you can see this, notifications are working. Intensity: {intensity_level}. Carry on, soldier."
- Includes sound based on current sound setting
- Includes actions based on a random channel category
- Shows a toast in-app: "Test notification sent. Check your lock screen in 5 seconds."

### Per-Friend Notification Toggle

In the Channels section, under "Per-Friend Notifications":
- Lists all Arena friends
- Each has an independent on/off toggle
- When OFF: no Arena notifications about that specific friend (leaderboard changes involving them, their challenges, their activity)
- When ON: all Arena notifications about that friend are delivered
- Default: all ON
- Use case: if a specific friend is too active and generating noise, user can mute just them

### Quiet Mode (Custom Ranges)

Beyond the main quiet hours (bedtime to wake):
- User can add up to 5 additional quiet time ranges
- Each range has: start time, end time, days of week (multi-select)
- Example: "Mon-Fri 9:00-10:30 AM" for a recurring morning class
- During quiet ranges: same behavior as main quiet hours (queue standard notifications; Time Sensitive notifications still break through Scheduled Summary)
- Ranges can be labeled: "Morning Class", "Football Practice", etc.

---

## Localization Preparation

### String Key Naming Convention

All notification strings follow this format:
```
notif.{channel}.{context}.{intensity}
```

Examples:
```
notif.morning.green_recovery.gentle
notif.morning.green_recovery.firm
notif.morning.green_recovery.drill
notif.morning.green_recovery.savage
notif.accountability.gentle.general.gentle
notif.accountability.gentle.general.drill
notif.meal.standard.drill
notif.streak.long.21day.savage
```

### Localizable.strings Structure

```
// en.lproj/Localizable.strings

// === MORNING BRIEFING ===
"notif.morning.green_recovery.gentle" = "Good morning, %@! Recovery is at %d%% -- your body feels great today. %@ day is on the schedule. You've got %d things to take care of. You can do this!";
// %1$@ = name, %2$d = recovery_score, %3$@ = workout_type, %4$d = tasks_total

"notif.morning.green_recovery.drill" = "Recovery at %d%%. Your body is ready. %@ day on deck -- I want to see PRs on bench press. %d non-negotiables today. No excuses. Let's go.";
// %1$d = recovery_score, %2$@ = workout_type, %3$d = tasks_total
```

### Pluralization Handling

Use `Localizable.stringsdict` for all plural forms:

```xml
<!-- Localizable.stringsdict -->
<key>notif.tasks_remaining</key>
<dict>
    <key>NSStringLocalizedFormatKey</key>
    <string>%#@tasks@</string>
    <key>tasks</key>
    <dict>
        <key>NSStringFormatSpecTypeKey</key>
        <string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key>
        <string>d</string>
        <key>one</key>
        <string>1 task remaining</string>
        <key>other</key>
        <string>%d tasks remaining</string>
    </dict>
</dict>

<key>notif.streak_days</key>
<dict>
    <key>NSStringLocalizedFormatKey</key>
    <string>%#@days@</string>
    <key>days</key>
    <dict>
        <key>NSStringFormatSpecTypeKey</key>
        <string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key>
        <string>d</string>
        <key>one</key>
        <string>1 day</string>
        <key>other</key>
        <string>%d days</string>
    </dict>
</dict>

<key>notif.study_hours</key>
<dict>
    <key>NSStringLocalizedFormatKey</key>
    <string>%#@hours@</string>
    <key>hours</key>
    <dict>
        <key>NSStringFormatSpecTypeKey</key>
        <string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key>
        <string>d</string>
        <key>one</key>
        <string>1 hour</string>
        <key>other</key>
        <string>%d hours</string>
    </dict>
</dict>
```

### Date/Time Formatting Per Locale

```swift
// Always use DateFormatter with the user's locale
let timeFormatter = DateFormatter()
timeFormatter.dateStyle = .none
timeFormatter.timeStyle = .short
timeFormatter.locale = Locale.current
// en_US: "7:30 PM"
// it_IT: "19:30"

let dateFormatter = DateFormatter()
dateFormatter.dateStyle = .medium
dateFormatter.timeStyle = .none
dateFormatter.locale = Locale.current
// en_US: "Mar 24, 2026"
// it_IT: "24 mar 2026"

// For relative dates in notifications
let relativeFormatter = RelativeDateTimeFormatter()
relativeFormatter.locale = Locale.current
relativeFormatter.unitsStyle = .full
// en: "in 5 days"
// it: "tra 5 giorni"
```

### Unit Formatting

```swift
// Weight (user preference stored in onboarding)
let massFormatter = MassFormatter()
massFormatter.unitStyle = .medium
// kg locale: "85 kg"
// lbs locale: "187 lb"

// Distance
let distanceFormatter = LengthFormatter()
distanceFormatter.unitStyle = .medium
// metric: "5.2 km"
// imperial: "3.2 mi"

// Energy
let energyFormatter = EnergyFormatter()
energyFormatter.unitStyle = .medium
// Always kcal in fitness context: "2,400 kcal"
// Use NumberFormatter for calories display: "2,400 cal"
```

### Italian Localization (First Additional Language)

**Priority:** Italian is the first localization target. The user (Nicola) is Italian, and the Italian student-athlete market is a natural expansion.

**Italian notification tone considerations:**
- "Savage Mode" Italian phrases are already embedded in the English copy (e.g., "Dai, muoviti!", "Sveglia!", "Basta scuse!", "Niente scuse")
- Full Italian localization: ALL notifications translated, maintaining the same intensity levels
- Italian has formal (Lei) and informal (tu) forms -- use **informal (tu)** exclusively. The drill-sergeant persona demands informality.
- Italian pluralization rules: singular (1), plural (other) -- same as English. No complex plural forms.

**Italian intensity naming:**
| English | Italian |
|---------|---------|
| Gentle Coach | Coach Gentile |
| Firm Coach | Coach Diretto |
| Drill Sergeant | Sergente di Ferro |
| Savage Mode | Modalita' Brutale |

**Sample Italian translations (Drill Sergeant):**

Morning Briefing (green recovery):
> "Recupero al {recovery_score}%. Il tuo corpo e' pronto. {workout_type} oggi -- voglio vedere dei record sulla panca. {tasks_total} non-negoziabili. Niente scuse. Andiamo."

Accountability Gentle:
> "Check pomeridiano. Studio: {study_done} su {study_target}. Allenamento: non iniziato. Hai {time_until_evening} prima di sera. Tempo piu' che sufficiente. Inizia adesso."

All Clear:
> "TUTTO FATTO. Ogni non-negoziabile completato. Ti sei guadagnato la serata. Qualsiasi cosa tu faccia adesso, la fai sapendo di aver fatto il tuo dovere. Rispetto."

### Localization Testing Checklist

- [ ] All dynamic variables render correctly in Italian (word order differs)
- [ ] Pluralization works for Italian (1 compito vs 2 compiti)
- [ ] Date formats use Italian locale (24 marzo 2026)
- [ ] Time formats use 24h clock for Italian (19:30 not 7:30 PM)
- [ ] Weight/distance units respect user preference, not locale
- [ ] Long Italian words don't truncate in notification banners (test with AX5 Dynamic Type)
- [ ] Notification actions are translated ("Visualizza Giorno", "Inizia Studio", etc.)
- [ ] Push notification payloads from backend include locale and format server-side
- [ ] Fallback: if Italian string is missing, fall back to English gracefully

---

## Legal & Compliance — Notification Privacy

### Opt-Out Mechanism

- **iOS-level:** iOS natively handles notification permissions. Users can disable notifications in Settings > Notifications > Tempo at any time. Tempo MUST respect this.
- **App-level:** Tempo's Settings > Notifications provides per-channel toggles that mirror and extend iOS settings. These are stored locally (SwiftData) AND synced to the backend.
- **Sync requirement:** If a user disables notifications in iOS Settings, the app must detect this on next launch via `UNUserNotificationCenter.current().getNotificationSettings()` and update the in-app UI to reflect the disabled state. Do NOT show in-app toggles as "ON" when iOS-level permission is denied.
- **Easy access:** Every notification settings screen must include a direct link to iOS notification settings ("Open iOS Notification Settings" button).

### Lock Screen Privacy — No Health Data in Payloads

> **CRITICAL: Notification content visible on the lock screen MUST NOT contain personal health information.**

The following data MUST NOT appear in the `alert.body` of any push notification payload:
- Exact recovery score percentages (e.g., "Recovery: 34%") -- use zone language instead ("Recovery is in the red zone today")
- Exact HRV values
- Exact heart rate values
- Exact sleep hours (e.g., "4.2h of sleep") -- use qualitative language ("Rough night")
- Calorie counts or macro numbers
- Body weight
- Any medical supplement or medication references

**Safe alternatives for lock screen:**
- Recovery zones: "Green / Yellow / Red" without percentages
- Sleep quality: "Great sleep" / "Rough night" / "Sleep needs work"
- General encouragement: "Your morning plan is ready" instead of "Recovery 34%, mobility only"

**Implementation:** Push notifications (sent from backend) must use lock-screen-safe copy in the `alert` payload. Detailed data (recovery %, exact sleep hours, macros) goes in the `data` payload, which is only visible when the user opens the notification or the app.

**Local notifications:** Since these are generated on-device and the user has already granted access to their own data, local notifications may include more specific information. However, the same principle applies -- assume the lock screen is visible to others.

### GDPR Compliance — Notification Preferences

- **Storage:** All notification preferences (intensity, per-channel toggles, quiet hours, schedule) are stored in the user's profile on the backend.
- **Export:** Notification preferences are included in any GDPR data export request (Settings > About > Export My Data).
- **Deletion:** When a user deletes their account (Settings > About > Delete Account), all notification preferences, interaction records, and adaptive timing data are permanently deleted from the backend within 30 days.
- **Consent:** The notification permission request during onboarding (Step 10) constitutes explicit consent for push notifications. The intensity selection constitutes consent for the chosen tone. Both can be changed at any time in Settings.
- **Data minimization:** Notification interaction records (used for adaptive timing) are stored for a maximum of 90 days, then aggregated into anonymous statistics and the raw records are deleted.
- **Third-party:** No notification data is shared with third parties. PostHog analytics receives anonymized notification engagement rates (channel, tap rate, time-to-action) but never notification content or personal data.

### Content Safety

- Savage Mode includes a disclaimer during onboarding: "This mode is intentionally uncomfortable. That's the point."
- No notification copy should reference specific mental health conditions, eating disorders, or self-harm
- Notifications about food/eating must never shame eating habits -- they should focus on performance and fuel, not appearance or weight
- If a user's completion rate drops below 25% for 7+ consecutive days, the system automatically softens tone to Gentle Coach regardless of setting, and shows an in-app card: "Things seem tough right now. Want to simplify your targets?" This prevents the app from relentlessly berating a user who may be going through a difficult period.

---

*This document is the authoritative specification for all onboarding and notification behavior in Tempo. All implementation must conform to this spec. Any deviations require updating this document first.*
