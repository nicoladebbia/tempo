# Tempo -- UX Copy Bible

> **Version**: 1.0
> **Last Updated**: 2026-03-24
> **Purpose**: Every string that appears in the Tempo app. Localization-ready. A translator should be able to translate the entire app from this document alone.
> **Format**: `string_key` | English text | Context note | Character limit (if applicable)

---

## 1. Voice & Tone Guide

### 1.1 Writing Personality

Tempo speaks like a **disciplined coach who respects your time**. Short. Direct. Imperative mood. The app has 4 intensity modes that affect notification copy and some in-app quips, but the core UI copy stays consistent.

| Mode | Personality | When Used |
|------|-------------|-----------|
| **Gentle Coach** | Supportive, warm, encouraging | User-selected notification intensity |
| **Firm Coach** | Direct, clear, no sugarcoating | User-selected notification intensity |
| **Drill Sergeant** | Tough love, escalating urgency, military edge | Default. Core app voice. |
| **Savage Mode** | Brutal honesty, maximum pressure, confrontational | User-selected notification intensity |

The **Drill Sergeant** voice is the default and defines the app's brand. All non-notification UI copy uses this voice unless otherwise noted.

### 1.2 Word List

**ALWAYS use:**
- "Locked in" (not "committed" or "ready")
- "Handle" (not "complete" or "finish" -- "Handle your business")
- "Earned" (not "unlocked" or "received")
- "Grind" / "Grinding" (effort as identity)
- "Move" (as a command, not a suggestion)
- "Target" (not "goal" or "objective")
- "Hit" (as in "hit your target")
- "Log" (not "record" or "enter")
- "Session" (for study blocks)
- "Rep" / "Set" (never spell out "repetition")
- "PR" (never "personal best" or "PB")
- "Rest day" (never "off day" or "day off")

**NEVER use:**
- "Please" (we don't beg)
- "Maybe" / "Perhaps" / "Consider" (weak language)
- "Oops" / "Whoops" (juvenile)
- "Great job!" in isolation (empty praise)
- "Don't forget" (passive -- say "Do X" instead)
- "Journey" (overused wellness jargon)
- "Mindful" / "Mindfulness" (not the brand)
- "Awesome" / "Amazing" / "Incredible" (inflated)
- "Notification" in user-facing text (say "reminder" or "alert")
- "Settings" as a verb ("go to settings" -- say "open Settings")
- "Loading..." with ellipsis in labels (use specific status text)

### 1.3 Sentence Structure Rules

1. **Max 12 words per sentence in UI labels.** Dashboard copy: max 8.
2. **Active voice only.** "You missed your target" not "Your target was missed."
3. **Imperative mood for actions.** "Start workout" not "Begin your workout session."
4. **No articles where space is tight.** "Log meal" not "Log a meal" in button labels.
5. **Fragments are fine.** "3 left. Move." is valid copy.
6. **Present tense.** "You earn 50 XP" not "You will earn 50 XP."

### 1.4 Number Formatting Rules

- Always use digits, never words. "3 meals" not "three meals."
- Use locale-appropriate thousands separators: "1,842" (en_US), "1.842" (it_IT).
- Percentages: digit + `%`, no space. "72%" not "72 %".
- Time durations: `Xh Ym` format. "2h 15m" not "2 hours 15 minutes" or "2:15".
- For durations under 1 hour: `Xm` only. "45m" not "0h 45m".
- Weights: digit + unit, no space. "85kg" or "185lbs".
- Calories: digit + " kcal" with space. "2,400 kcal".
- Steps: digit with thousands separator. "8,432".
- Dates: short format "Mon, Mar 24". Full format "Monday, March 24".
- Countdown: "in 6 days", "TOMORROW", "TODAY".

### 1.5 User Reference

- Address by first name in greetings: "{firstName}" from profile.
- If no name set: omit the name entirely. "Rise and grind." not "Rise and grind, User."
- Use "you" / "your" in body copy and descriptions.
- Never use "we" -- Tempo is a singular entity, not a team.

### 1.6 Time Reference

- Use short time formats: "45 min left" not "45 minutes remaining."
- Relative time: "2m ago", "1h ago", "Yesterday 14:30", "Mar 22".
- Duration format: "Xh Ym" for compound, "Xm" for minutes-only.
- Clock times: "7:30 PM" in 12h format (locale-dependent).

### 1.7 Emoji Usage Rules

- **No emoji in core UI labels, buttons, or navigation.**
- Emoji are used ONLY in: notification body text, Arena feed item templates, social reactions.
- Maximum 1 emoji per notification.
- Arena XP breakdown uses category emoji: dumbbell, book, fork, shoe, checkmark, moon.
- Challenge template flavor text may use 0-1 emoji.

---

## 2. Onboarding Copy

### 2.1 Splash Screen

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `splash_wordmark` | `TEMPO` | App name, centered, animates in | 5 |
| `splash_tagline` | `YOUR LIFE OPERATING SYSTEM` | Below wordmark, uppercase | 30 |

### 2.2 Step 1: Welcome / Value Prop

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_welcome_headline` | `STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS.` | Main headline, center-aligned | 50 |
| `onb_welcome_subtext` | `Training. Nutrition. Recovery. Academics. One system. One score. Zero excuses.` | Below headline | 80 |
| `onb_welcome_cta` | `GET STARTED` | Primary button | 15 |

### 2.3 Step 2: Sign in with Apple

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_auth_headline` | `YOUR IDENTITY STAYS YOURS.` | Main headline | 30 |
| `onb_auth_subtext` | `Tempo uses Sign in with Apple. We never see your password. We never sell your data. Period.` | Privacy reassurance | 100 |
| `onb_auth_button` | `Sign in with Apple` | Apple-provided button label | -- |
| `onb_auth_why_link` | `Why is sign-in required?` | Expandable link | 30 |
| `onb_auth_why_title` | `Why we need an account` | Bottom sheet title | 25 |
| `onb_auth_why_body` | `Your account powers: (1) Arena -- compete with friends on leaderboards, (2) Cloud sync -- your data backed up securely, (3) Multi-device -- use Tempo on iPhone and iPad. Your Apple ID email is private by default. We store a unique identifier, your display name, and your Tempo data. Nothing else.` | Bottom sheet body | 300 |
| `onb_auth_why_dismiss` | `Got it` | Dismiss button | 10 |
| `onb_auth_hint` | `Sign-in is required to use Tempo. Your data stays private with Apple's relay system.` | Shown after 2 cancellations | 90 |
| `onb_auth_error_network` | `Connection failed. Check your internet and try again.` | Network error | 60 |
| `onb_auth_error_server` | `Something went wrong on our end. Try again in a moment.` | Backend error | 60 |
| `onb_auth_error_existing` | `This Apple ID is already linked to a Tempo account. You'll be signed into that account.` | Duplicate account | 80 |
| `onb_auth_retry` | `Retry` | Retry button | 10 |

### 2.4 Step 3: Profile Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_profile_headline` | `WHO ARE YOU, SOLDIER?` | Main headline | 25 |
| `onb_profile_photo_hint` | `Tap to add photo` | Photo circle placeholder | 20 |
| `onb_profile_name_label` | `Display Name` | Field label | 15 |
| `onb_profile_name_placeholder` | `Your name` | Empty field placeholder | 15 |
| `onb_profile_username_label` | `Username` | Field label | 10 |
| `onb_profile_username_placeholder` | `choose a username` | Empty field placeholder | 20 |
| `onb_profile_username_available` | `Available` | Green availability indicator | 10 |
| `onb_profile_username_taken` | `Taken` | Red availability indicator | 10 |
| `onb_profile_username_error_letter` | `Must start with a letter` | Validation error | 25 |
| `onb_profile_username_error_short` | `Too short` | Validation error, min 3 chars | 10 |
| `onb_profile_username_error_long` | `Too long` | Validation error, max 20 chars | 10 |
| `onb_profile_username_error_chars` | `Letters, numbers, and underscores only` | Validation error | 40 |
| `onb_profile_username_race` | `Someone just grabbed that username. Try another.` | Taken between check and submit | 55 |
| `onb_profile_error_network` | `Couldn't save your profile. Check your connection and try again.` | Network error | 70 |
| `onb_profile_error_photo` | `Photo upload failed -- you can add it later in Settings.` | Photo upload failure toast | 55 |
| `onb_profile_cta` | `CONTINUE` | Primary button | 10 |

### 2.5 Step 4: Training Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_training_headline` | `LET'S BUILD YOUR TRAINING PROFILE.` | Main headline | 40 |
| `onb_training_q1` | `Do you train?` | Question label | 15 |
| `onb_training_yes` | `YES` | Toggle button | 5 |
| `onb_training_no` | `NO` | Toggle button | 5 |
| `onb_training_no_note` | `No worries. You can set up training later.` | Shown if user selects NO | 45 |
| `onb_training_q2` | `What do you do?` | Multi-select question | 20 |
| `onb_training_q2_gym` | `Gym` | Option chip | 5 |
| `onb_training_q2_running` | `Running` | Option chip | 10 |
| `onb_training_q2_team` | `Team Sport` | Option chip | 12 |
| `onb_training_q2_other` | `Other` | Option chip | 8 |
| `onb_training_q2_sport` | `Which sport?` | Sub-question for Team Sport | 15 |
| `onb_training_q2_sport_football` | `Football (Soccer)` | Option | 20 |
| `onb_training_q2_sport_basketball` | `Basketball` | Option | 12 |
| `onb_training_q2_sport_rugby` | `Rugby` | Option | 8 |
| `onb_training_q2_sport_volleyball` | `Volleyball` | Option | 12 |
| `onb_training_q2_sport_other` | `Other` | Option with text input | 8 |
| `onb_training_q2_days` | `Which days do you play/practice?` | Sub-question for Team Sport | 35 |
| `onb_training_q3` | `How many days per week do you train?` | Question label | 40 |
| `onb_training_q4` | `Preferred split?` | Question label, gym only | 20 |
| `onb_training_q4_ppl` | `PPL (Push/Pull/Legs)` | Option | 22 |
| `onb_training_q4_upperlower` | `Upper/Lower` | Option | 12 |
| `onb_training_q4_fullbody` | `Full Body` | Option | 10 |
| `onb_training_q4_brosplit` | `Bro Split` | Option | 10 |
| `onb_training_q4_idk` | `I Don't Know` | Option | 14 |
| `onb_training_q4_idk_tip` | `We'll start you with Push/Pull/Legs -- the best split for building muscle and fitting around team sports.` | Tooltip for IDK | 100 |
| `onb_training_q5` | `Experience level` | Question label | 18 |
| `onb_training_q5_beginner` | `Beginner` | Option title | 10 |
| `onb_training_q5_beginner_desc` | `Less than 1 year of consistent training` | Option description | 45 |
| `onb_training_q5_intermediate` | `Intermediate` | Option title | 15 |
| `onb_training_q5_intermediate_desc` | `1-3 years, comfortable with compound lifts` | Option description | 45 |
| `onb_training_q5_advanced` | `Advanced` | Option title | 10 |
| `onb_training_q5_advanced_desc` | `3+ years, tracking progressive overload` | Option description | 45 |
| `onb_training_q6` | `Preferred workout duration` | Question label | 30 |
| `onb_training_q7` | `Equipment available` | Question label | 22 |
| `onb_training_q7_fullgym` | `Full Gym` | Option | 10 |
| `onb_training_q7_homegym` | `Home Gym` | Option | 10 |
| `onb_training_q7_bodyweight` | `Bodyweight Only` | Option | 16 |
| `onb_training_q7_dumbbells` | `Dumbbells` | Home gym checkbox | 12 |
| `onb_training_q7_barbell` | `Barbell + Rack` | Home gym checkbox | 15 |
| `onb_training_q7_pullup` | `Pull-up Bar` | Home gym checkbox | 12 |
| `onb_training_q7_bench` | `Bench` | Home gym checkbox | 8 |
| `onb_training_q7_bands` | `Resistance Bands` | Home gym checkbox | 18 |
| `onb_training_q7_cable` | `Cable Machine` | Home gym checkbox | 15 |
| `onb_training_q8` | `Weight unit` | Question label | 12 |
| `onb_training_q8_kg` | `kg` | Option | 3 |
| `onb_training_q8_lbs` | `lbs` | Option | 4 |

### 2.6 Step 5: Academics Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_academics_headline` | `NOW THE HARD PART. YOUR BRAIN.` | Main headline | 35 |
| `onb_academics_q1` | `Are you a student?` | Question label | 20 |
| `onb_academics_no_note` | `Got it. You can still set study goals or learning targets in Settings.` | Shown if NO | 70 |
| `onb_academics_school_label` | `School (optional)` | Field label | 20 |
| `onb_academics_school_placeholder` | `University name` | Placeholder | 18 |
| `onb_academics_courses_label` | `Your courses` | Section label | 15 |
| `onb_academics_course_add` | `+ Add a course` | Add button | 15 |
| `onb_academics_exams_label` | `Upcoming exams` | Section label | 18 |
| `onb_academics_exam_add` | `+ Add an exam` | Add button | 15 |
| `onb_academics_study_label` | `Daily study goal` | Section label | 18 |
| `onb_academics_calendar_label` | `Import your calendar?` | Section label | 25 |
| `onb_academics_calendar_cta` | `Import Calendar` | Button | 18 |
| `onb_academics_calendar_desc` | `Tempo reads your class schedule, exams, and practice times to plan your day. No events are modified.` | Description | 100 |
| `onb_academics_calendar_success` | `Calendar connected` | Success state | 20 |
| `onb_academics_calendar_denied` | `You can connect your calendar later in Settings. Tempo works without it, but scheduling will be more accurate with it.` | Denied state | 120 |

### 2.7 Step 6: Goals Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_goals_headline` | `WHAT ARE YOU FIGHTING FOR?` | Main headline | 30 |
| `onb_goals_primary_label` | `Primary goal` | Section label | 15 |
| `onb_goals_build_muscle` | `Build Muscle` | Option | 15 |
| `onb_goals_build_muscle_desc` | `Gain size and strength` | Option subtitle | 25 |
| `onb_goals_lose_fat` | `Lose Fat` | Option | 10 |
| `onb_goals_lose_fat_desc` | `Cut weight, keep muscle` | Option subtitle | 25 |
| `onb_goals_performance` | `Improve Performance` | Option | 22 |
| `onb_goals_performance_desc` | `Sport-specific, endurance, speed` | Option subtitle | 35 |
| `onb_goals_healthy` | `Stay Healthy` | Option | 14 |
| `onb_goals_healthy_desc` | `Maintain fitness, feel good` | Option subtitle | 30 |
| `onb_goals_allaround` | `All-Around` | Option | 12 |
| `onb_goals_allaround_desc` | `A bit of everything` | Option subtitle | 22 |
| `onb_goals_nn_label` | `YOUR NON-NEGOTIABLES` | Section label | 22 |
| `onb_goals_nn_desc` | `These are daily. No exceptions.` | Section description | 32 |
| `onb_goals_nn_add` | `+ Add custom` | Add button | 12 |
| `onb_goals_timewaster_label` | `What's your biggest time-waster?` | Section label | 35 |
| `onb_goals_timewaster_ps5` | `PS5/Gaming` | Option | 12 |
| `onb_goals_timewaster_social` | `Social Media` | Option | 14 |
| `onb_goals_timewaster_netflix` | `Netflix/Streaming` | Option | 20 |
| `onb_goals_timewaster_youtube` | `YouTube` | Option | 10 |
| `onb_goals_timewaster_other` | `Other` | Option with text input | 8 |
| `onb_goals_timewaster_note` | `No judgment. Knowing your weakness is the first step to controlling it.` | Subtext | 75 |
| `onb_goals_evening_label` | `When does your evening usually start?` | Section label | 40 |
| `onb_goals_evening_note` | `This is when the drill sergeant gets serious. All non-negotiables should be done before this time.` | Subtext | 100 |

### 2.8 Step 7: Connect Whoop

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_whoop_headline` | `YOUR BODY TALKS. LET'S LISTEN.` | Main headline | 35 |
| `onb_whoop_recovery` | `Recovery %` | Feature name | 12 |
| `onb_whoop_recovery_desc` | `Know how hard to push today` | Feature description | 30 |
| `onb_whoop_sleep` | `Sleep Score` | Feature name | 12 |
| `onb_whoop_sleep_desc` | `Track sleep debt and quality` | Feature description | 30 |
| `onb_whoop_strain` | `Daily Strain` | Feature name | 14 |
| `onb_whoop_strain_desc` | `See your training load in real-time` | Feature description | 35 |
| `onb_whoop_hrv` | `HRV Trends` | Feature name | 12 |
| `onb_whoop_hrv_desc` | `Detect overtraining before it's too late` | Feature description | 42 |
| `onb_whoop_cta` | `CONNECT WHOOP` | Primary button | 15 |
| `onb_whoop_skip` | `Skip for now` | Skip link | 14 |
| `onb_whoop_connecting` | `Connecting to Whoop...` | Loading overlay | 25 |
| `onb_whoop_success` | `Connected!` | Success state | 12 |
| `onb_whoop_success_no_data` | `Connected! Recovery data will appear after your first night of sleep.` | No data yet | 70 |
| `onb_whoop_skip_warning_title` | `Without Whoop, these features will be limited:` | Skip confirmation | 50 |
| `onb_whoop_skip_item1` | `Recovery-based training adjustments` | Limited feature | 40 |
| `onb_whoop_skip_item2` | `Sleep tracking and bedtime recommendations` | Limited feature | 45 |
| `onb_whoop_skip_item3` | `HRV trend analysis` | Limited feature | 20 |
| `onb_whoop_skip_confirm` | `Skip Anyway` | Skip button | 14 |
| `onb_whoop_error_fail` | `Couldn't connect to Whoop. Try again?` | OAuth failure | 40 |
| `onb_whoop_error_expired` | `Connection expired. Let's try again.` | Expired code | 40 |

### 2.9 Step 8: Connect NutriTrack

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_nutritrack_headline` | `FUEL IS NOT OPTIONAL.` | Main headline | 25 |
| `onb_nutritrack_desc_item1` | `Meals logged and planned` | Feature bullet | 25 |
| `onb_nutritrack_desc_item2` | `Calories and macros (protein, carbs, fat)` | Feature bullet | 42 |
| `onb_nutritrack_desc_item3` | `Meal timing compliance` | Feature bullet | 25 |
| `onb_nutritrack_desc_item4` | `Weekly nutrition trends` | Feature bullet | 25 |
| `onb_nutritrack_url_label` | `Server URL` | Field label | 12 |
| `onb_nutritrack_url_placeholder` | `https://your-nutritrack-server.com` | Placeholder | 40 |
| `onb_nutritrack_pin_label` | `PIN` | Field label | 5 |
| `onb_nutritrack_test_cta` | `TEST CONNECTION` | Test button | 18 |
| `onb_nutritrack_testing` | `Testing...` | Loading state | 12 |
| `onb_nutritrack_success` | `Connected!` | Success state | 12 |
| `onb_nutritrack_error_url` | `Couldn't reach that server. Check the URL and try again.` | Bad URL | 60 |
| `onb_nutritrack_error_pin` | `Invalid PIN. Check your NutriTrack settings.` | Bad PIN | 50 |
| `onb_nutritrack_error_unreachable` | `Server not responding. Is NutriTrack running?` | Server down | 50 |
| `onb_nutritrack_error_timeout` | `Connection timed out. Check that NutriTrack is accessible from the internet.` | Timeout | 70 |
| `onb_nutritrack_no_app_link` | `Don't have NutriTrack?` | Info link | 25 |
| `onb_nutritrack_no_app_body` | `NutriTrack is a self-hosted nutrition tracking app. Without NutriTrack, Tempo won't track your nutrition automatically. You can still set meal-count non-negotiables and check them off manually.` | Info sheet | 200 |
| `onb_nutritrack_skip` | `Skip for now` | Skip link | 14 |

### 2.10 Step 9: HealthKit Permissions

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_health_headline` | `TEMPO NEEDS ACCESS TO YOUR HEALTH DATA.` | Main headline | 45 |
| `onb_health_privacy` | `This stays on your device. Apple encrypts it. We never see your raw health data.` | Privacy note | 80 |
| `onb_health_steps` | `Steps & Distance` | Permission title | 18 |
| `onb_health_steps_desc` | `Track daily movement` | Permission description | 22 |
| `onb_health_steps_why` | `Tempo uses your step count for the Move quadrant on your Dashboard and to award daily XP. No step data is sent to any server.` | Expanded why | 120 |
| `onb_health_hr` | `Heart Rate & HRV` | Permission title | 18 |
| `onb_health_hr_desc` | `Monitor workout effort` | Permission description | 22 |
| `onb_health_hr_why` | `Heart rate during workouts helps Tempo assess training intensity. HRV supplements Whoop data for recovery insights.` | Expanded why | 110 |
| `onb_health_workouts` | `Workouts` | Permission title | 10 |
| `onb_health_workouts_desc` | `Auto-detect training` | Permission description | 22 |
| `onb_health_workouts_why` | `Tempo reads Apple Watch workouts to auto-detect training sessions. It also writes RepForge workouts back to HealthKit so they appear in your Activity rings.` | Expanded why | 150 |
| `onb_health_sleep` | `Sleep Analysis` | Permission title | 16 |
| `onb_health_sleep_desc` | `Supplement Whoop data` | Permission description | 22 |
| `onb_health_sleep_why` | `If you don't use Whoop, Tempo can read sleep data from Apple Watch. If you do use Whoop, this is a backup data source.` | Expanded why | 120 |
| `onb_health_energy` | `Active Energy` | Permission title | 16 |
| `onb_health_energy_desc` | `Calculate daily burn` | Permission description | 22 |
| `onb_health_energy_why` | `Used to calculate your total daily energy expenditure for the Dashboard.` | Expanded why | 70 |
| `onb_health_cta` | `AUTHORIZE HEALTH` | Primary button | 18 |
| `onb_health_success` | `Health data configured` | Confirmation | 25 |
| `onb_health_denied_banner` | `Some data is missing. Grant Health permissions in Settings > Privacy > Health > Tempo.` | Persistent banner | 80 |

### 2.11 Step 10: Notification Permissions

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_notif_headline` | `YOUR DRILL SERGEANT NEEDS YOUR PERMISSION TO YELL.` | Main headline | 55 |
| `onb_notif_intensity_label` | `How tough should I be?` | Section label | 25 |
| `onb_notif_gentle_title` | `Gentle Coach` | Option title | 14 |
| `onb_notif_gentle_desc` | `Supportive and encouraging. Reminders without the edge.` | Option description | 55 |
| `onb_notif_gentle_preview` | `Hey! You've got 3 tasks left today. You can totally do this!` | Preview notification | 60 |
| `onb_notif_firm_title` | `Firm Coach` | Option title | 12 |
| `onb_notif_firm_desc` | `Direct and clear. No sugarcoating, but no yelling.` | Option description | 55 |
| `onb_notif_firm_preview` | `3 tasks remaining. 5 hours left. Time to focus.` | Preview notification | 50 |
| `onb_notif_drill_title` | `Drill Sergeant` | Option title | 16 |
| `onb_notif_drill_desc` | `Tough love. Gets louder as the day goes on.` | Option description | 50 |
| `onb_notif_drill_badge` | `REC` | Recommended badge | 5 |
| `onb_notif_drill_preview` | `3 non-negotiables left. Clock's ticking. Move.` | Preview notification | 50 |
| `onb_notif_savage_title` | `Savage Mode` | Option title | 12 |
| `onb_notif_savage_desc` | `Maximum pressure. Not for the faint-hearted.` | Option description | 50 |
| `onb_notif_savage_preview` | `3 tasks undone. Another wasted day incoming. Prove me wrong.` | Preview notification | 65 |
| `onb_notif_savage_warning` | `This mode is intentionally uncomfortable. That's the point.` | Small warning | 60 |
| `onb_notif_cta` | `ENABLE NOTIFICATIONS` | Primary button | 22 |
| `onb_notif_success` | `Notifications enabled` | Success state | 25 |
| `onb_notif_denied_body` | `Without notifications, your drill sergeant can't reach you. The accountability system works best with notifications enabled.` | Denied state | 120 |
| `onb_notif_denied_settings` | `Open Settings` | Settings button | 15 |
| `onb_notif_denied_skip` | `Continue without` | Skip button | 18 |

### 2.12 Step 11: Arena Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_arena_headline` | `ACCOUNTABILITY IS BETTER WITH RIVALS.` | Main headline | 40 |
| `onb_arena_subtext` | `Compete with friends on weekly leaderboards. Turn discipline into a sport.` | Subtext | 75 |
| `onb_arena_share_link` | `Share Invite Link` | Button | 18 |
| `onb_arena_qr_code` | `Show My QR Code` | Button | 18 |
| `onb_arena_search_label` | `Find Friends by Username` | Section label | 28 |
| `onb_arena_share_text` | `Join me on Tempo -- the life OS for student-athletes. Download and add me: @{username}` | Share sheet text, {username} replaced | 100 |
| `onb_arena_request_sent` | `Friend request sent to @{username}` | Confirmation toast | 40 |
| `onb_arena_skip` | `Skip for now` | Skip link | 14 |

### 2.13 Step 12: Summary / First Day

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `onb_summary_headline` | `YOU'RE LOCKED IN.` | Main headline, typewriter effect | 20 |
| `onb_summary_briefing_title` | `TODAY'S BRIEFING` | Card header | 18 |
| `onb_summary_integrations_title` | `INTEGRATIONS` | Card header | 14 |
| `onb_summary_nn_title` | `NON-NEGOTIABLES` | Card header | 16 |
| `onb_summary_connected` | `Connected` | Integration status | 12 |
| `onb_summary_enabled` | `Enabled` | Integration status | 10 |
| `onb_summary_skipped` | `Skipped` | Integration status | 10 |
| `onb_summary_mission_cta` | `YOUR FIRST MISSION STARTS NOW.` | Final CTA button | 32 |
| `onb_summary_recovery_missing` | `Connect Whoop to see your recovery` | No Whoop connected | 40 |

---

## 3. Dashboard Copy

### 3.1 Tab Bar Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `tab_dashboard` | `Home` | Tab bar label | 6 |
| `tab_training` | `Train` | Tab bar label | 6 |
| `tab_accountability` | `Lockdown` | Tab bar label | 10 |
| `tab_recovery` | `Recover` | Tab bar label | 8 |
| `tab_arena` | `Arena` | Tab bar label | 6 |

### 3.2 Dashboard Greeting Messages

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `greeting_early_bird` | `Early bird gets the gains, {firstName}.` | 04:00-07:59 | 45 |
| `greeting_morning` | `Rise and grind, {firstName}.` | 08:00-11:59 | 35 |
| `greeting_midday` | `No half reps this afternoon, {firstName}.` | 12:00-13:59 | 45 |
| `greeting_afternoon` | `Keep the pressure on, {firstName}.` | 14:00-16:59 | 40 |
| `greeting_evening` | `Finish what you started, {firstName}.` | 17:00-20:59 | 40 |
| `greeting_night` | `Earn your sleep, {firstName}.` | 21:00-23:59 | 35 |
| `greeting_late_night` | `You should be asleep, {firstName}.` | 00:00-03:59 | 40 |

Omit `{firstName}` and the comma if no name is set.

### 3.3 Daily Score Section

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `score_label` | `Daily Score` | Below score ring | 12 |
| `score_last_sync` | `Last sync: {relative_time}` | Sync timestamp, e.g. "Last sync: 2m ago" | 30 |
| `score_calculating` | `Calculating...` | Loading state | 15 |
| `score_syncing` | `Syncing...` | Refresh state, dots animate | 12 |
| `score_connect_more` | `Connect more sources` | <2 sources connected | 22 |
| `score_sync_failed` | `Sync failed -- pull to retry` | All sources errored | 28 |
| `score_offline` | `Offline` | Offline with cached data | 10 |
| `score_no_data` | `--` | No score calculable | 2 |

### 3.4 Quadrant Headers and Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `quad_body` | `BODY` | Quadrant category label, uppercase | 6 |
| `quad_fuel` | `FUEL` | Quadrant category label, uppercase | 6 |
| `quad_mind` | `MIND` | Quadrant category label, uppercase | 6 |
| `quad_move` | `MOVE` | Quadrant category label, uppercase | 6 |
| `quad_body_primary_label` | `Recovery` | Below recovery percentage | 10 |
| `quad_body_hrv_label` | `HRV` | Metric label | 5 |
| `quad_body_rhr_label` | `RHR` | Metric label | 5 |
| `quad_body_sleep_label` | `Sleep` | Metric label | 8 |
| `quad_body_strain_label` | `Strain {value}` | Below strain bar, e.g. "Strain 14.2" | 15 |
| `quad_fuel_kcal_label` | `kcal` | Unit label below calorie display | 5 |
| `quad_fuel_protein_short` | `P` | Macro bar label, small screens | 1 |
| `quad_fuel_carbs_short` | `C` | Macro bar label, small screens | 1 |
| `quad_fuel_fat_short` | `F` | Macro bar label, small screens | 1 |
| `quad_fuel_protein_long` | `Protein` | Macro bar label, large screens | 8 |
| `quad_fuel_carbs_long` | `Carbs` | Macro bar label, large screens | 6 |
| `quad_fuel_fat_long` | `Fat` | Macro bar label, large screens | 4 |
| `quad_fuel_meals_progress` | `{logged}/{planned} meals` | Meals count, e.g. "2/4 meals" | 15 |
| `quad_fuel_meals_complete` | `All {planned} meals logged` | All meals done | 25 |
| `quad_fuel_over_target` | `+{overage} kcal over` | Calories over target | 20 |
| `quad_fuel_no_meals` | `No meals planned` | No meal plan set | 18 |
| `quad_mind_target_progress` | `{minutes} / {target} min` | Study progress, e.g. "45 / 120 min" | 20 |
| `quad_mind_target_hit` | `Target hit.` | Study target reached | 12 |
| `quad_mind_exam_countdown` | `{name} in {n} days` | Exam countdown, e.g. "Calculus II in 6 days" | 35 |
| `quad_mind_exam_tomorrow` | `{name} TOMORROW` | Exam is tomorrow | 25 |
| `quad_mind_exam_today` | `{name} TODAY` | Exam is today | 20 |
| `quad_mind_no_exams` | `No upcoming exams` | No exams set | 20 |
| `quad_mind_add_exam` | `+ Add exam` | Add exam link | 12 |
| `quad_mind_streak` | `{n}d streak` | Study streak, e.g. "12d streak" | 15 |
| `quad_mind_nudge` | `Open a book. NOW.` | 0 study minutes motivational nudge | 20 |
| `quad_move_done` | `Done` | Workout completed | 6 |
| `quad_move_planned` | `Planned for today` | Workout planned | 18 |
| `quad_move_rest_day` | `Rest Day` | Rest day | 10 |
| `quad_move_rest_quip` | `Recovery is training.` | Rest day italic quip | 22 |
| `quad_move_no_workout` | `No workout` | No workout planned | 12 |
| `quad_move_no_workout_sub` | `Add one or skip -- your call.` | No workout subtext | 30 |
| `quad_move_steps_label` | `Steps` | Metric label | 6 |
| `quad_move_active_cal_label` | `Active Cal` | Metric label, standard screens | 12 |
| `quad_move_active_cal_short` | `Act Cal` | Metric label, iPhone SE | 8 |
| `quad_move_steps_goal` | `{target} goal` | Below step bar, e.g. "10,000 goal" | 15 |

### 3.5 Quadrant Disconnected States

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `body_disconnected_title` | `Connect Whoop` | Disconnected state title | 15 |
| `body_disconnected_desc` | `to track recovery` | Disconnected state description | 20 |
| `body_disconnected_cta` | `Connect` | Connect button | 10 |
| `fuel_disconnected_title` | `Connect NutriTrack` | Disconnected state title | 20 |
| `fuel_disconnected_desc` | `to track nutrition` | Disconnected state description | 20 |
| `fuel_disconnected_cta` | `Connect` | Connect button | 10 |
| `move_disconnected_title` | `Allow Health Access` | Disconnected state title | 22 |
| `move_disconnected_desc` | `to track activity` | Disconnected state description | 20 |
| `move_disconnected_cta` | `Authorize` | Authorize button | 12 |

### 3.6 Quadrant Error States

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `quad_error_title` | `Sync failed` | Error state title | 12 |
| `quad_error_desc` | `Pull to refresh` | Error state description | 18 |
| `quad_no_data` | `--` | Nil value placeholder | 2 |

### 3.7 Non-Negotiables Bar

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_progress` | `{done}/{total} done -- {reward} {status}` | e.g. "3/5 done -- PS5 locked" | 40 |
| `nn_unlocked` | `unlocked` | All complete | 10 |
| `nn_locked` | `locked` | Not all complete | 8 |
| `nn_empty_title` | `Set your daily non-negotiables` | Empty state title | 35 |
| `nn_empty_cta` | `+ Add non-negotiable` | Empty state link | 22 |

### 3.8 Quick Insights Banner

No fixed strings -- insights are AI-generated. Container labels only:

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `insight_dismiss_a11y` | `Dismiss insight` | Accessibility label for swipe | 18 |

### 3.9 Pull-to-Refresh Status Messages

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `refresh_recovery` | `Pulling recovery data...` | Phase 1 | 28 |
| `refresh_meals` | `Syncing meals...` | Phase 2 | 18 |
| `refresh_activity` | `Reading activity...` | Phase 3 | 22 |
| `refresh_done` | `Locked in.` | Phase 4, all sources responded | 12 |
| `refresh_error_source` | `{source} sync failed` | Toast for failed source | 25 |
| `refresh_error_all` | `Sync failed. Check your connection.` | All sources failed | 40 |
| `refresh_up_to_date` | `Data is up to date` | Data <5 min old, no re-fetch | 22 |

### 3.10 Relative Timestamps

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `time_just_now` | `Just now` | <60 seconds ago | 10 |
| `time_minutes_ago` | `{n}m ago` | 1-59 minutes, e.g. "2m ago" | 10 |
| `time_hours_ago` | `{n}h ago` | 1-23 hours, e.g. "1h ago" | 10 |
| `time_yesterday` | `Yesterday {time}` | 24-48 hours, e.g. "Yesterday 14:30" | 20 |

---

## 4. Training Copy (RepForge)

### 4.1 Today's Workout View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `training_nav_title` | `Training` | Navigation bar title | 10 |
| `training_recovery_synced` | `Synced {time}` | Recovery badge, e.g. "Synced 6:42 AM" | 18 |
| `training_recovery_full` | `Full Volume` | Green recovery recommendation | 14 |
| `training_recovery_moderate` | `Moderate Volume` | Yellow recovery recommendation | 18 |
| `training_recovery_reduced` | `Reduced Volume` | Red recovery recommendation | 16 |
| `training_meta_duration` | `~{n} min` | Estimated duration, e.g. "~52 min" | 10 |
| `training_meta_exercises` | `{n} exercises` | Exercise count | 15 |
| `training_meta_sets` | `{n} sets` | Total sets | 10 |
| `training_add_exercise` | `+ Add Exercise` | Dashed border button | 16 |
| `training_start_cta` | `START WORKOUT` | Primary CTA | 15 |
| `training_rest_day_title` | `REST DAY` | Workout title for rest day | 10 |

### 4.2 Workout Titles

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `workout_push` | `PUSH DAY` | Workout type | 10 |
| `workout_pull` | `PULL DAY` | Workout type | 10 |
| `workout_legs` | `LEG DAY` | Workout type | 10 |
| `workout_upper` | `UPPER BODY` | Workout type | 12 |
| `workout_full` | `FULL BODY` | Workout type | 10 |
| `workout_easy_run` | `EASY RUN` | Workout type | 10 |
| `workout_interval_run` | `INTERVAL RUN` | Workout type | 14 |
| `workout_tempo_run` | `TEMPO RUN` | Workout type | 10 |
| `workout_long_run` | `LONG RUN` | Workout type | 10 |
| `workout_fartlek` | `FARTLEK` | Workout type | 10 |
| `workout_mobility` | `MOBILITY FLOW` | Workout type | 14 |
| `workout_football_prep` | `FOOTBALL PREP` | Workout type | 14 |
| `workout_deload_prefix` | `DELOAD --` | Deload week prefix, e.g. "DELOAD -- PUSH" | 12 |

### 4.3 Active Workout

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `active_set_label` | `Set {n}` | Set number, e.g. "Set 3" | 8 |
| `active_reps_label` | `Reps` | Column header | 6 |
| `active_weight_label` | `Weight` | Column header | 8 |
| `active_log_set` | `Log Set` | Button to log completed set | 10 |
| `active_skip_set` | `Skip` | Skip set button | 6 |
| `active_finish_workout` | `FINISH WORKOUT` | Finish button | 16 |
| `active_cancel_workout` | `Cancel Workout` | Cancel option | 16 |
| `active_cancel_confirm_title` | `Cancel workout?` | Confirmation dialog title | 18 |
| `active_cancel_confirm_body` | `Your logged sets will be saved.` | Confirmation dialog body | 35 |
| `active_cancel_confirm_yes` | `Cancel Workout` | Destructive button | 16 |
| `active_cancel_confirm_no` | `Keep Going` | Cancel button | 12 |
| `active_superset_label` | `SUPERSET {letter}` | e.g. "SUPERSET A" | 14 |

### 4.4 Rest Timer

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `rest_title` | `Rest` | Timer title | 6 |
| `rest_skip` | `Skip Rest` | Skip button | 10 |
| `rest_times_up` | `Time's up. Next set.` | Rest period complete | 22 |
| `rest_10s_warning` | `10 seconds` | Audio/haptic at 10s remaining | 12 |

### 4.5 PR Celebration Messages

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `pr_message_1` | `NEW PR! You just proved yesterday's you wrong.` | PR celebration, random | 50 |
| `pr_message_2` | `Personal record. The iron remembers.` | PR celebration, random | 40 |
| `pr_message_3` | `New max. Keep stacking.` | PR celebration, random | 28 |
| `pr_message_4` | `PR. That weight didn't stand a chance.` | PR celebration, random | 42 |
| `pr_message_5` | `Record broken. Build the next one.` | PR celebration, random | 38 |

### 4.6 Workout Summary

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `summary_title` | `Workout Complete` | Screen title | 18 |
| `summary_duration` | `Duration` | Stat label | 10 |
| `summary_total_volume` | `Total Volume` | Stat label | 14 |
| `summary_sets_completed` | `Sets Completed` | Stat label | 16 |
| `summary_prs` | `New PRs` | Stat label | 10 |
| `summary_exercises` | `Exercises` | Stat label | 12 |
| `summary_done_cta` | `Done` | Dismiss button | 6 |
| `summary_share_cta` | `Share` | Share button | 8 |

### 4.7 Week Plan View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `weekplan_title` | `Week Plan` | Navigation title | 12 |
| `weekplan_today` | `TODAY` | Today indicator | 6 |
| `weekplan_rest` | `Rest` | Rest day label | 6 |
| `weekplan_completed` | `Completed` | Completed status | 12 |
| `weekplan_planned` | `Planned` | Planned status | 10 |
| `weekplan_skipped` | `Skipped` | Skipped status | 10 |

### 4.8 Exercise Library

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `library_title` | `Exercises` | Navigation title | 12 |
| `library_search_placeholder` | `Search exercises...` | Search bar placeholder | 22 |
| `library_filter_all` | `All` | Filter option | 5 |
| `library_filter_chest` | `Chest` | Muscle group filter | 8 |
| `library_filter_back` | `Back` | Muscle group filter | 6 |
| `library_filter_shoulders` | `Shoulders` | Muscle group filter | 12 |
| `library_filter_arms` | `Arms` | Muscle group filter | 6 |
| `library_filter_legs` | `Legs` | Muscle group filter | 6 |
| `library_filter_core` | `Core` | Muscle group filter | 6 |
| `library_empty` | `No exercises found.` | Empty search result | 22 |

### 4.9 Training Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `training_settings_title` | `Training Settings` | Navigation title | 18 |
| `training_settings_unit` | `Weight Unit` | Setting label | 14 |
| `training_settings_rest` | `Default Rest Time` | Setting label | 18 |
| `training_settings_autostart` | `Auto-Start Rest Timer` | Toggle label | 22 |
| `training_settings_plates` | `Show Plate Calculator` | Toggle label | 22 |
| `training_settings_experience` | `Experience Level` | Setting label | 18 |
| `training_settings_split` | `Training Split` | Setting label | 16 |
| `training_settings_days` | `Training Days` | Setting label | 14 |
| `training_settings_duration` | `Workout Duration` | Setting label | 18 |
| `training_settings_deload` | `Auto-Deload` | Toggle label | 14 |
| `training_settings_deload_desc` | `Automatically schedule a deload week every 4-6 weeks` | Setting description | 55 |

### 4.10 Training Errors

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `training_error_no_workout` | `No workout available` | Error state title | 22 |
| `training_error_no_workout_desc` | `Check your training settings or add a workout manually.` | Error description | 55 |
| `training_error_generation_failed` | `Couldn't generate your workout. Pull to retry.` | Generation error | 50 |

---

## 5. Accountability Copy (Lockdown)

### 5.1 Lockdown Main View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `lockdown_nav_title` | `LOCKDOWN` | Nav bar, uppercase, tracked | 10 |
| `lockdown_locked` | `LOCKED` | Status banner, red | 8 |
| `lockdown_unlocked` | `UNLOCKED` | Status banner, green | 10 |

### 5.2 Status Banner Time Context

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `lockdown_time_until` | `{time} until your usual PS5 time` | >2h remaining, e.g. "4h 32m until..." | 45 |
| `lockdown_time_focus` | `{time} left. Focus up.` | 1-2h remaining | 25 |
| `lockdown_time_ticking` | `{time}. Clock's ticking.` | 30-60 min remaining | 25 |
| `lockdown_time_move` | `{time}. Move.` | <30 min remaining, red text | 15 |
| `lockdown_time_passed` | `PS5 time passed {n} min ago` | Past PS5 time | 30 |
| `lockdown_unlocked_early` | `Unlocked {time} early. Ahead of schedule.` | Unlocked before PS5 time | 45 |
| `lockdown_unlocked_late` | `Unlocked. Better late than never.` | Unlocked after PS5 time | 35 |
| `lockdown_unlocked_legend` | `All done by noon. Legend.` | Unlocked before noon | 28 |
| `lockdown_almost` | `Just 1 more. So close.` | 1 non-negotiable remaining | 24 |
| `lockdown_overdue` | `PS5 time passed. Handle your business.` | Past PS5 time, still locked | 42 |

### 5.3 Non-Negotiable Card Status

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_status_not_started` | `NOT STARTED` | No progress | 12 |
| `nn_status_done` | `DONE` | Completed | 6 |
| `nn_status_overdue` | `OVERDUE` | Past deadline, pulsing | 8 |
| `nn_status_skipped` | `SKIPPED` | User-skipped | 8 |

### 5.4 Non-Negotiable Card Supporting Text

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_study_hint` | `Start a focus session to begin tracking` | Study card, not started | 42 |
| `nn_study_progress` | `Last session: {duration} {subject}, {time}` | Study in progress | 50 |
| `nn_study_complete` | `{duration} total across {n} sessions` | Study complete | 40 |
| `nn_study_add_more` | `Add More` | Study complete, outlined button | 10 |
| `nn_training_waiting` | `Waiting for Whoop sync...` | Training, not started | 28 |
| `nn_training_complete` | `{duration} strength recorded at {time}` | Training done | 40 |
| `nn_training_manual` | `Log Manually` | Manual fallback after 6 PM | 14 |
| `nn_meals_next_breakfast` | `Next: Breakfast` | Before any meals | 18 |
| `nn_meals_next_lunch` | `Next: Lunch` | After breakfast | 14 |
| `nn_meals_next_dinner` | `Next: Dinner before 8pm` | After lunch | 28 |
| `nn_meals_all_logged` | `All meals logged today` | All done | 24 |
| `nn_meals_log_cta` | `Log in NutriTrack` | Deep link button | 16 |
| `nn_meals_install` | `Install NutriTrack to auto-track meals` | App not installed | 40 |

### 5.5 Card Interactions

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_context_complete` | `Mark as Complete` | Context menu | 18 |
| `nn_context_skip` | `Skip Today` | Context menu | 12 |
| `nn_context_edit` | `Edit Non-Negotiable` | Context menu | 20 |
| `nn_context_history` | `View History` | Context menu | 14 |

### 5.6 Leisure Status Section

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `leisure_title` | `LEISURE STATUS` | Section header, uppercase | 16 |
| `leisure_locked` | `Complete {n} more to unlock` | Locked, tasks remaining | 30 |
| `leisure_almost` | `Just 1 more. You're right there.` | 1 remaining, amber | 35 |
| `leisure_unlocked` | `You earned it. Enjoy your evening.` | All complete, green | 38 |
| `leisure_overdue` | `PS5 time has passed. Tasks still incomplete.` | Overdue, red | 50 |
| `leisure_rest_day` | `Rest day. No non-negotiables active.` | Rest/skip day | 40 |

### 5.7 Quick Action Button

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `quick_action_study` | `START STUDY TIMER` | Primary state, uppercase | 20 |
| `quick_action_study_more` | `START ANOTHER SESSION` | Study target already met | 24 |

### 5.8 Focus Timer View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `timer_session_label` | `Session {n} of {total}` | e.g. "Session 2 of 4" | 20 |
| `timer_bonus_session` | `Bonus Session` | After all planned sessions | 16 |
| `timer_subject_hint` | `Tap to tag subject` | No subject selected | 22 |
| `timer_default_subject` | `General Study` | Default subject | 14 |
| `timer_no_subject` | `No Subject` | Study without tagging | 12 |
| `timer_add_subject` | `Add New Subject` | Subject picker option | 18 |
| `timer_phase_ready` | `READY` | Before timer starts | 6 |
| `timer_phase_focus` | `FOCUS TIME` | During focus period | 12 |
| `timer_phase_break` | `BREAK TIME` | During break | 12 |
| `timer_phase_paused` | `PAUSED` | Timer paused | 8 |
| `timer_today_total` | `Today's total: {current} / {target}` | Accumulated time | 30 |
| `timer_focus_score` | `Focus Score: {score}` | Real-time focus score | 18 |
| `timer_distracted_label` | `Distracted` | Distraction button label | 12 |
| `timer_ambient_label` | `Ambient` | Ambient sound button label | 10 |
| `timer_stop` | `Stop` | Stop button a11y | 6 |
| `timer_pause` | `PAUSE` | Running state button | 8 |
| `timer_resume` | `RESUME` | Paused state button | 8 |
| `timer_skip` | `Skip` | Skip button a11y | 6 |
| `timer_all_complete_title` | `All Sessions Complete!` | Full celebration overlay | 22 |
| `timer_all_complete_body` | `{duration} of focused study` | Summary line | 30 |
| `timer_all_complete_cta` | `DONE` | Dismiss button | 6 |

### 5.9 Focus Timer Confirmations

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `timer_close_running_title` | `Timer is running.` | Close confirmation title | 20 |
| `timer_close_running_body` | `Stop and discard this session?` | Close confirmation body | 35 |
| `timer_close_running_keep` | `Keep Going` | Cancel button | 12 |
| `timer_close_running_discard` | `Stop & Discard` | Destructive button | 16 |
| `timer_close_paused_title` | `Discard this session?` | Close when paused | 24 |
| `timer_close_paused_resume` | `Resume` | Cancel button | 8 |
| `timer_close_paused_discard` | `Discard` | Destructive button | 10 |
| `timer_stop_confirm_title` | `Stop this session?` | Stop button confirmation | 22 |
| `timer_stop_confirm_body` | `{time} of study will be saved.` | Shows accumulated time | 35 |
| `timer_stop_keep` | `Keep Going` | Cancel button | 12 |
| `timer_stop_save` | `Stop & Save` | Save partial button | 12 |
| `timer_stop_discard` | `Stop & Discard` | Destructive button | 16 |
| `timer_skip_confirm_title` | `Skip with {time} remaining?` | Skip focus with >5 min left | 30 |
| `timer_skip_confirm_body` | `Completed time will still count.` | Reassurance | 35 |
| `timer_break_countdown` | `Break starts in {n}...` | Auto-start break countdown | 22 |
| `timer_start_break` | `Start Break` | Manual break start button | 14 |

### 5.10 Break Messages

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `break_msg_1` | `Stand up. Stretch. You've earned it.` | Rotated during breaks | 40 |
| `break_msg_2` | `Hydrate. Your brain needs water.` | Rotated | 35 |
| `break_msg_3` | `Look at something 20 feet away for 20 seconds.` | 20-20-20 rule | 50 |
| `break_msg_4` | `Roll your neck. Release the tension.` | Rotated | 38 |
| `break_msg_5` | `Deep breath in... hold... and out.` | Rotated | 38 |
| `break_msg_6` | `You're {percentage}% done with today's study goal.` | Dynamic, shows progress | 50 |

### 5.11 Focus Score Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `focus_excellent` | `Excellent` | Score 90-100 | 12 |
| `focus_good` | `Good` | Score 75-89 | 6 |
| `focus_fair` | `Fair` | Score 50-74 | 6 |
| `focus_needs_work` | `Needs work` | Score <50 | 12 |

### 5.12 Ambient Sound Options

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `ambient_none` | `None` | Option | 6 |
| `ambient_rain` | `Rain` | Option | 6 |
| `ambient_heavy_rain` | `Heavy Rain` | Option | 12 |
| `ambient_white_noise` | `White Noise` | Option | 12 |
| `ambient_brown_noise` | `Brown Noise` | Option | 12 |
| `ambient_coffee_shop` | `Coffee Shop` | Option | 12 |
| `ambient_library` | `Library` | Option | 10 |
| `ambient_fireplace` | `Fireplace` | Option | 12 |

### 5.13 Timer Session Types

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `session_pomodoro` | `Pomodoro` | 25/5 min | 10 |
| `session_long_focus` | `Long Focus` | 50/10 min | 12 |
| `session_deep_work` | `Deep Work` | 90/20 min | 12 |
| `session_custom` | `Custom` | User-defined | 8 |

### 5.14 Timer Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `timer_settings_type` | `Session Type` | Setting label | 14 |
| `timer_settings_focus` | `Focus Duration` | Setting label | 16 |
| `timer_settings_short_break` | `Short Break` | Setting label | 14 |
| `timer_settings_long_break` | `Long Break` | Setting label | 12 |
| `timer_settings_sessions` | `Sessions Before Long Break` | Setting label | 28 |
| `timer_settings_auto_break` | `Auto-Start Breaks` | Toggle label | 18 |
| `timer_settings_auto_focus` | `Auto-Start Focus` | Toggle label | 18 |
| `timer_settings_sound` | `End-of-Session Sound` | Setting label | 22 |
| `timer_settings_screen` | `Keep Screen On` | Toggle label | 16 |

### 5.15 Non-Negotiable Setup

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_setup_title` | `NON-NEGOTIABLES` | Navigation title | 18 |
| `nn_setup_desc` | `Your daily requirements. Complete these before leisure time is unlocked.` | Description | 72 |
| `nn_setup_active` | `ACTIVE ({count})` | Section header | 14 |
| `nn_setup_add` | `Add Non-Negotiable` | Add button | 20 |
| `nn_setup_max` | `Maximum reached (7)` | Max non-negotiables | 22 |
| `nn_setup_save` | `Done` | Save button | 6 |
| `nn_setup_new_title` | `NEW NON-NEGOTIABLE` | Create mode title | 22 |
| `nn_setup_edit_title` | `EDIT {NAME}` | Edit mode title | 20 |
| `nn_setup_name_label` | `Name` | Field label | 6 |
| `nn_setup_name_placeholder` | `e.g., Study, Read, Meditate` | Placeholder | 30 |
| `nn_setup_name_required` | `Name is required` | Validation error | 18 |
| `nn_setup_type_label` | `Type` | Field label | 6 |
| `nn_setup_type_timed` | `Timed` | Type option | 8 |
| `nn_setup_type_counter` | `Counter` | Type option | 10 |
| `nn_setup_type_binary` | `Binary` | Type option | 8 |
| `nn_setup_tracking_label` | `Tracking Method` | Field label | 18 |
| `nn_setup_tracking_manual_timer` | `Manual Timer` | Tracking option | 14 |
| `nn_setup_tracking_manual_check` | `Manual Check` | Tracking option | 14 |
| `nn_setup_tracking_manual_counter` | `Manual Counter` | Tracking option | 16 |
| `nn_setup_tracking_whoop` | `Whoop / HealthKit` | Tracking option | 20 |
| `nn_setup_tracking_nutritrack` | `NutriTrack` | Tracking option | 12 |
| `nn_setup_days_label` | `Days active` | Field label | 12 |
| `nn_setup_days_every` | `Every Day` | Preset | 10 |
| `nn_setup_days_weekdays` | `Weekdays` | Preset | 10 |
| `nn_setup_days_weekends` | `Weekends` | Preset | 10 |
| `nn_setup_days_custom` | `Custom` | Preset | 8 |
| `nn_setup_days_error` | `Select at least one day.` | Validation error | 28 |
| `nn_setup_delete_confirm` | `Delete '{name}'? Historical data will be preserved but this non-negotiable will no longer appear in your daily list.` | Delete confirmation | 120 |
| `nn_setup_remove_confirm` | `Remove '{name}'? This won't delete historical data.` | Remove from list | 55 |

### 5.16 Templates

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `template_student_athlete` | `Student Athlete` | Template title | 16 |
| `template_student_athlete_desc` | `Study 2h + Training + 3 Meals` | Template description | 35 |
| `template_exam_week` | `Exam Week` | Template title | 12 |
| `template_exam_week_desc` | `Study 4h + 3 Meals (no training)` | Template description | 35 |
| `template_light_day` | `Light Day` | Template title | 12 |
| `template_light_day_desc` | `Study 1h + 3 Meals` | Template description | 22 |
| `template_apply_confirm` | `Apply '{template}' template? This will replace your current non-negotiables.` | Confirmation | 80 |
| `template_apply_cta` | `Apply` | Confirm button | 8 |

### 5.17 Capacity Warning

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nn_capacity_warning` | `You have {n} non-negotiables. Research shows 3-5 is optimal. More risks burnout and reduces completion rates.` | Warning banner | 100 |
| `nn_capacity_dismiss` | `Dismiss` | Dismiss button | 10 |

### 5.18 Streak & Consistency View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `streak_title` | `CONSISTENCY` | Navigation title | 14 |
| `streak_day_label` | `day streak` | Below streak number | 12 |
| `streak_longest` | `Longest: {n} days` | Longest streak record | 20 |
| `streak_this_week` | `This Week` | Stat label | 12 |
| `streak_this_month` | `This Month` | Stat label | 12 |
| `streak_perfect_weeks` | `Perfect Weeks` | Stat label | 16 |
| `streak_per_nn` | `PER NON-NEGOTIABLE` | Section header | 22 |

### 5.19 Exam Mode

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `exam_mode_activate` | `Activate Exam Mode` | Button | 22 |
| `exam_mode_active` | `EXAM MODE ACTIVE` | Status indicator | 18 |
| `exam_mode_desc` | `Study target increased to 4h. Training is optional. Notifications intensify.` | Description | 72 |
| `exam_mode_deactivate` | `Deactivate Exam Mode` | Button | 24 |
| `exam_mode_celebration` | `Exam season survived. Back to normal.` | Post-exam message | 40 |

### 5.20 Sick Day / Rest Day

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `sick_day_activate` | `Activate Sick Day` | Button | 20 |
| `sick_day_active` | `Sick day active. Take care of yourself.` | Status | 42 |
| `sick_day_desc` | `Targets reduced. No penalties. Streak preserved.` | Description | 52 |
| `rest_day_activate` | `Mark as Rest Day` | Button | 18 |
| `rest_day_active` | `Rest day. Recovery counts.` | Status | 28 |

### 5.21 Empty State

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `lockdown_empty_title` | `No non-negotiables set` | Empty state headline | 28 |
| `lockdown_empty_body` | `Define what you MUST do each day before you earn your downtime.` | Empty state body | 65 |
| `lockdown_empty_cta` | `SET UP NON-NEGOTIABLES` | Setup button | 24 |

---

## 6. Recovery Copy (RecoverIQ)

### 6.1 Recovery Today View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `recovery_nav_title` | `Recovery` | Tab / nav title | 10 |

### 6.2 Recovery Quips by Zone

**Green Zone (67-100%)**

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `recovery_quip_green_1` | `Go break something. In a good way.` | 90-100% | 38 |
| `recovery_quip_green_2` | `Peak condition. No excuses today.` | 90-100% | 38 |
| `recovery_quip_green_3` | `Your body said yes. Don't waste it.` | 90-100% | 40 |
| `recovery_quip_green_4` | `You're good to push it.` | 67-89% | 26 |
| `recovery_quip_green_5` | `Green means go. Get after it.` | 67-89% | 32 |
| `recovery_quip_green_6` | `Solid recovery. Make it count.` | 67-89% | 34 |

**Yellow Zone (34-66%)**

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `recovery_quip_yellow_1` | `Ease up or pay for it tomorrow.` | 50-66% | 34 |
| `recovery_quip_yellow_2` | `Yellow zone. Choose your battles.` | 50-66% | 36 |
| `recovery_quip_yellow_3` | `Moderate effort. Save the fireworks.` | 50-66% | 40 |
| `recovery_quip_yellow_4` | `Your body is waving a yellow flag.` | 34-49% | 40 |
| `recovery_quip_yellow_5` | `Sub-50. Train smart, not hard.` | 34-49% | 34 |
| `recovery_quip_yellow_6` | `Recovery debt is building. Pay attention.` | 34-49% | 45 |

**Red Zone (0-33%)**

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `recovery_quip_red_1` | `Sit down. Seriously.` | 0-33% | 22 |
| `recovery_quip_red_2` | `Red zone. Walk, stretch, nothing more.` | 0-33% | 42 |
| `recovery_quip_red_3` | `Your body needs a ceasefire.` | 0-33% | 32 |

### 6.3 Recovery Metric Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `recovery_hrv_label` | `HRV` | Metric tile label | 5 |
| `recovery_hrv_unit` | `ms` | Unit | 3 |
| `recovery_rhr_label` | `RHR` | Metric tile label | 5 |
| `recovery_rhr_unit` | `bpm` | Unit | 5 |
| `recovery_sleep_label` | `Sleep` | Metric tile label | 8 |
| `recovery_spo2_label` | `SpO2` | Metric tile label | 6 |
| `recovery_spo2_normal` | `Normal` | SpO2 >= 95% | 8 |
| `recovery_spo2_low` | `Low` | SpO2 < 95% | 5 |
| `recovery_vs_avg` | `vs avg` | Comparison indicator | 8 |
| `recovery_trend_up` | `{n}%` | Trend up percentage (with up arrow icon) | 6 |
| `recovery_trend_down` | `{n}%` | Trend down percentage (with down arrow icon) | 6 |
| `recovery_trend_stable` | `stable` | Within +/- 2% | 8 |

### 6.4 Sleep Breakdown

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `sleep_deep` | `Deep` | Sleep stage | 6 |
| `sleep_rem` | `REM` | Sleep stage | 5 |
| `sleep_light` | `Light` | Sleep stage | 8 |
| `sleep_awake` | `Awake` | Sleep stage | 8 |
| `sleep_performance` | `Performance: {n}%` | Sleep performance score | 20 |
| `sleep_in_bed` | `In bed: {start} -> {end}` | Bedtime range | 30 |

### 6.5 Strain Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `strain_zone_low` | `Low` | Strain 0-9 | 5 |
| `strain_zone_moderate` | `Moderate` | Strain 10-13 | 10 |
| `strain_zone_high` | `High` | Strain 14-17 | 6 |
| `strain_zone_overreaching` | `Overreaching` | Strain 18-21 | 14 |
| `strain_recommended` | `Recommended: {level} (recovery {n}%)` | Strain recommendation | 40 |
| `strain_rec_push` | `Push it` | Recovery >= 80 | 8 |
| `strain_rec_moderate` | `Moderate` | Recovery 50-79 | 10 |
| `strain_rec_easy` | `Take it easy` | Recovery < 50 | 12 |

### 6.6 Prescription Card Categories

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `rx_training` | `Training` | Category label | 10 |
| `rx_nutrition` | `Nutrition` | Category label | 12 |
| `rx_sleep` | `Sleep` | Category label | 8 |
| `rx_hydration` | `Hydration` | Category label | 12 |
| `rx_caffeine` | `Caffeine` | Category label | 10 |
| `rx_why` | `Why this recommendation?` | Expand link | 28 |
| `rx_loading` | `Generating your prescription...` | Loading state | 35 |
| `rx_error` | `Couldn't generate this prescription.` | Error state | 40 |
| `rx_error_desc` | `Check your Whoop connection.` | Error description | 32 |

### 6.7 Recovery Trends

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `trends_title` | `Trends` | Navigation title | 8 |
| `trends_7d` | `7D` | Time range selector | 3 |
| `trends_30d` | `30D` | Time range selector | 4 |
| `trends_90d` | `90D` | Time range selector | 4 |
| `trends_recovery_title` | `RECOVERY TREND` | Chart section title | 16 |

### 6.8 Whoop Connection States

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `whoop_connected` | `Connected` | Connection status | 12 |
| `whoop_disconnected` | `Disconnected` | Connection status | 14 |
| `whoop_syncing` | `Syncing...` | Connection status | 12 |
| `whoop_error` | `Connection error` | Connection status | 18 |
| `whoop_reconnect` | `Reconnect Whoop` | Action button | 18 |
| `whoop_connect_banner` | `Connect Whoop to unlock recovery insights` | Persistent banner | 45 |

---

## 7. Arena Copy (ClutchTime)

### 7.1 Arena Main View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `arena_nav_title` | `ARENA` | Screen title | 8 |
| `arena_todays_xp` | `TODAY'S XP` | Section label | 12 |
| `arena_earned` | `Earned: +{n} XP` | XP earned today | 20 |
| `arena_potential` | `Potential: +{n} XP` | XP still earnable | 22 |
| `arena_multiplier` | `Multiplier: {n}x` | Streak multiplier | 18 |
| `arena_see_details` | `See Details >` | Link to XP breakdown | 16 |
| `arena_xp_format` | `+{n} XP` | Positive XP display | 12 |
| `arena_xp_penalty` | `-{n} XP` | Negative XP display | 12 |
| `arena_complete_hint` | `Complete activities to earn XP!` | First-time hint | 35 |

### 7.2 XP Categories (Arena Breakdown)

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `xp_workout` | `Workout` | Category label | 10 |
| `xp_study` | `Study` | Category label | 8 |
| `xp_meals` | `Meals` | Category label | 8 |
| `xp_steps` | `Steps` | Category label | 8 |
| `xp_tasks` | `Tasks` | Non-negotiables category | 8 |
| `xp_sleep` | `Sleep` | Category label | 8 |
| `xp_login` | `Login` | Category label | 8 |
| `xp_bonus` | `BONUS!` | Bonus XP indicator | 8 |
| `xp_perfect_day` | `Perfect Day` | Composite bonus | 14 |
| `xp_near_perfect` | `Near-Perfect Day` | Composite bonus | 18 |

### 7.3 XP Detail Sheet

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `xp_detail_title` | `TODAY'S XP BREAKDOWN` | Sheet title | 24 |
| `xp_detail_earned` | `EARNED` | Section header, green | 8 |
| `xp_detail_available` | `STILL AVAILABLE TODAY` | Section header, gray | 24 |
| `xp_detail_penalties` | `PENALTIES` | Section header, red | 12 |
| `xp_detail_subtotal` | `Subtotal` | Row label | 10 |
| `xp_detail_multiplier_row` | `Streak multiplier ({n}x)` | Multiplier row | 25 |
| `xp_detail_total` | `TOTAL EARNED` | Total row | 14 |
| `xp_detail_remaining` | `Potential remaining` | Remaining row | 22 |
| `xp_detail_no_penalties` | `None today` | No penalties | 12 |

### 7.4 Level Names (All 50)

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `level_rookie` | `Rookie` | Level 1-5 | 8 |
| `level_contender` | `Contender` | Level 6-10 | 12 |
| `level_warrior` | `Warrior` | Level 11-15 | 10 |
| `level_gladiator` | `Gladiator` | Level 16-20 | 12 |
| `level_centurion` | `Centurion` | Level 21-25 | 12 |
| `level_captain` | `Captain` | Level 26-30 | 10 |
| `level_commander` | `Commander` | Level 31-35 | 12 |
| `level_titan` | `Titan` | Level 36-40 | 8 |
| `level_warlord` | `Warlord` | Level 41-45 | 10 |
| `level_legend` | `Legend` | Level 46-50 | 8 |

### 7.5 Level Up

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `level_up_title` | `LEVEL UP!` | Celebration text | 10 |
| `level_up_continue` | `Continue` | Dismiss button | 10 |

### 7.6 Leaderboard

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `leaderboard_title` | `LEADERBOARD` | Navigation title | 14 |
| `leaderboard_weekly` | `WEEKLY` | Tab label | 8 |
| `leaderboard_monthly` | `MONTHLY` | Tab label | 10 |
| `leaderboard_alltime` | `ALL-TIME` | Tab label | 10 |
| `leaderboard_friends` | `FRIENDS` | Scope toggle | 10 |
| `leaderboard_league` | `MY LEAGUE` | Scope toggle | 12 |
| `leaderboard_filter_xp` | `Total XP` | Filter option | 10 |
| `leaderboard_filter_workouts` | `Workout Count` | Filter option | 15 |
| `leaderboard_filter_study` | `Study Hours` | Filter option | 14 |
| `leaderboard_filter_steps` | `Steps` | Filter option | 8 |
| `leaderboard_filter_streak` | `Longest Streak` | Filter option | 16 |
| `leaderboard_filter_challenges` | `Challenges Won` | Filter option | 16 |
| `leaderboard_gap` | `{n} XP behind #{rank}` | Gap to next rank | 25 |
| `leaderboard_invite` | `+ Invite Friends to Leaderboard` | Invite CTA | 34 |
| `leaderboard_see_all` | `See All >` | Link to full leaderboard | 12 |

### 7.7 Leaderboard Empty State

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `leaderboard_empty_title` | `It's lonely at the top...` | Empty headline | 28 |
| `leaderboard_empty_body` | `but it doesn't have to be. Add friends to see who's grinding harder this week.` | Empty body | 80 |
| `leaderboard_empty_invite` | `Invite Friends` | Primary button | 16 |
| `leaderboard_empty_share` | `Share Invite Link` | Secondary button | 18 |
| `leaderboard_single_user` | `You're currently the only one here. Invite friends to compete!` | Only user | 65 |

### 7.8 Leaderboard Psychology

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `leaderboard_personal_progress` | `You earned {n} XP this week. That's more than last week's {prev}!` | Last place encouragement | 65 |
| `leaderboard_close_gap` | `{n} XP behind {name}` | Gap to person above | 30 |
| `leaderboard_inactive_nudge` | `{name} hasn't logged any XP today. Catch up!` | Rival inactive | 55 |
| `leaderboard_another_level` | `On another level` | #1 has 2x+ gap | 18 |

### 7.9 League System

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `league_bronze` | `Bronze League` | Tier name | 14 |
| `league_silver` | `Silver League` | Tier name | 14 |
| `league_gold` | `Gold League` | Tier name | 14 |
| `league_platinum` | `Platinum League` | Tier name | 18 |
| `league_diamond` | `Diamond League` | Tier name | 16 |
| `league_diamond_elite` | `Diamond Elite` | Top 5 in Diamond | 16 |
| `league_promotion_zone` | `PROMOTION ZONE` | Zone label, green | 16 |
| `league_safe_zone` | `SAFE ZONE` | Zone label, neutral | 12 |
| `league_relegation_zone` | `RELEGATION ZONE` | Zone label, amber | 18 |
| `league_days_left` | `{n} days left in this league week` | Countdown | 35 |

### 7.10 Weekly Reset

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `week_review_title` | `LAST WEEK'S RESULTS` | Card header | 22 |
| `week_review_rank` | `Your rank: #{n} of {total} friends` | Rank summary | 30 |
| `week_review_total` | `Total XP: {n} XP` | XP summary | 20 |
| `week_review_best_day` | `Best day: {day} ({n} XP)` | Best day | 30 |
| `week_review_winner` | `{name} won the week: {n} XP` | Winner announcement | 35 |
| `week_review_reset` | `New week starts now. Everyone's at 0.` | Reset message | 40 |
| `week_review_full_cta` | `View Full Results` | Button | 20 |

### 7.11 Streak Display

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `streak_day_suffix` | `DAY STREAK` | After streak number | 12 |
| `streak_multiplier` | `{n}x MULTIPLIER ACTIVE` | Multiplier display | 24 |
| `streak_freezes` | `{available} Freezes Available` | Freeze count | 25 |
| `streak_freeze_saved` | `Your streak freeze saved your {n}-day streak yesterday!` | Freeze auto-consumed | 60 |
| `streak_freeze_pre_activate` | `Use Freeze Tomorrow` | Settings toggle | 22 |
| `streak_freeze_confirm` | `This will use 1 of your {n} freezes for tomorrow. Your streak will be preserved even if you don't complete any tasks.` | Freeze confirmation | 110 |

### 7.12 Challenges

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `challenges_title` | `CHALLENGES` | Navigation title | 12 |
| `challenges_active` | `ACTIVE ({n})` | Section header | 14 |
| `challenges_pending` | `PENDING` | Section header | 10 |
| `challenges_completed` | `COMPLETED` | Section header | 12 |
| `challenges_time_left` | `{n} days, {h}h remaining` | Time remaining | 25 |
| `challenges_losing` | `You're losing by {amount}` | Behind in challenge | 30 |
| `challenges_winning` | `You're winning by {amount}` | Ahead in challenge | 30 |
| `challenges_tied` | `Tied!` | Equal scores | 6 |
| `challenges_empty` | `No active challenges. Start one!` | Empty state | 35 |
| `challenges_locked` | `Challenges unlock at Level 7. You're {n} XP away!` | Pre-unlock | 55 |
| `challenges_create_cta` | `Challenge a Friend` | CTA button | 20 |
| `challenges_start_cta` | `Start a Challenge` | Alternative CTA | 18 |

### 7.13 Challenge Duration Labels

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `challenge_daily_duel` | `Daily Duel` | 1 day | 12 |
| `challenge_weekend_warrior` | `Weekend Warrior` | 3 days | 18 |
| `challenge_weekly_war` | `Weekly War` | 7 days | 12 |
| `challenge_fortnight_fight` | `Fortnight Fight` | 14 days | 18 |
| `challenge_monthly_marathon` | `Monthly Marathon` | 30 days | 18 |

### 7.14 Challenge Completion

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `challenge_victory` | `VICTORY!` | Win celebration | 10 |
| `challenge_defeated` | `Challenge complete` | Loss message | 20 |
| `challenge_win_xp` | `+{n} XP earned.` | Win XP reward | 16 |
| `challenge_loss_xp` | `+{n} XP for participating.` | Loss XP | 28 |
| `challenge_rematch` | `Rematch` | Rematch button | 10 |

### 7.15 Friend System

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `friends_title` | `FRIENDS` | Navigation title | 10 |
| `friends_add_title` | `ADD FRIENDS` | Sheet title | 12 |
| `friends_search_placeholder` | `Search by username...` | Search bar placeholder | 25 |
| `friends_or` | `-- OR --` | Divider text | 10 |
| `friends_qr_scan` | `QR Code Scan` | Action card | 14 |
| `friends_share_link` | `Share Link` | Action card | 12 |
| `friends_import_contacts` | `Import from Contacts` | Action card | 22 |
| `friends_search_results` | `SEARCH RESULTS` | Section header | 16 |
| `friends_pending_requests` | `PENDING REQUESTS` | Section header | 18 |
| `friends_no_results` | `No users found for '{query}'. Check the spelling or share your invite link instead.` | Empty search | 80 |
| `friends_add_btn` | `Add` | Add friend button | 5 |
| `friends_sent_btn` | `Sent` | Request sent state | 6 |
| `friends_friends_btn` | `Friends` | Already friends state | 10 |
| `friends_accept` | `Accept` | Accept request | 8 |
| `friends_decline` | `Decline` | Decline request | 10 |
| `friends_cancel_request` | `Cancel Request` | Cancel sent request | 16 |
| `friends_now_friends` | `Now Friends!` | Accept confirmation | 14 |
| `friends_request_sent` | `{name} wants to be your friend on Tempo.` | Incoming request | 50 |
| `friends_accepted` | `{name} accepted your friend request.` | Acceptance notification | 45 |
| `friends_online` | `ONLINE ({n})` | Section header | 14 |
| `friends_offline` | `OFFLINE ({n})` | Section header | 14 |
| `friends_pending` | `PENDING ({n})` | Section header | 14 |
| `friends_count` | `{n} Friends` | Total friend count | 14 |
| `friends_list_full` | `Friend list full. Remove a friend to add more.` | Max 50 friends | 50 |
| `friends_qr_instruction` | `Point at your friend's Tempo QR code` | Camera overlay instruction | 40 |
| `friends_qr_invalid` | `Not a Tempo QR code. Try again.` | Invalid QR | 35 |
| `friends_qr_title` | `Scan this to add me on Tempo` | Own QR code screen | 32 |
| `friends_contacts_denied` | `Enable Contacts access in Settings to find friends.` | Permission denied | 55 |
| `friends_contacts_settings` | `Open Settings` | Deep link button | 15 |

### 7.16 Remove / Block / Report

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `friends_remove_confirm` | `Remove @{username}? They won't be notified, but you'll be removed from each other's leaderboards and active challenges.` | Remove confirmation | 120 |
| `friends_remove_btn` | `Remove` | Destructive button | 8 |
| `friends_block_confirm` | `Block @{username}? They won't be able to find you, send requests, or see your profile.` | Block confirmation | 100 |
| `friends_block_btn` | `Block` | Destructive button | 8 |
| `friends_report_username` | `Inappropriate username` | Report option | 24 |
| `friends_report_harassment` | `Harassment` | Report option | 12 |
| `friends_report_spam` | `Spam` | Report option | 6 |
| `friends_report_other` | `Other` | Report option | 8 |
| `friends_report_thanks` | `Thanks. We'll review this.` | Report confirmation | 30 |

### 7.17 Social Feed

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `feed_title` | `FRIEND ACTIVITY` | Section label | 18 |
| `feed_workout` | `{name} completed a {workout} workout` | Feed template | 50 |
| `feed_study` | `{name} studied for {hours}h` | Feed template | 35 |
| `feed_streak` | `{name} hit a {n}-day streak!` | Feed template | 35 |
| `feed_achievement` | `{name} unlocked "{achievement}"` | Feed template | 45 |
| `feed_challenge_won` | `{name} won the {challenge}` | Feed template | 40 |
| `feed_level_up` | `{name} reached Level {n} -- {title}!` | Feed template | 45 |
| `feed_pr` | `{name} set a new PR: {exercise} {weight}` | Feed template | 50 |
| `feed_perfect_day` | `{name} had a Perfect Day` | Feed template | 35 |
| `feed_more` | `and {n} more activities` | Collapsed activities | 25 |
| `feed_see_all` | `See Feed >` | Link to full feed | 14 |
| `feed_empty_no_friends` | `Add friends to see their activity here!` | No friends | 42 |
| `feed_empty_no_activity` | `Your friends have been quiet today. Challenge someone to get things moving!` | No recent activity | 75 |
| `feed_end` | `You've seen everything. Pull down to refresh.` | End of feed | 48 |
| `feed_hide` | `Hide` | Swipe action | 6 |
| `feed_mute` | `Mute {name}` | Swipe action | 15 |

### 7.18 Reactions

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `reaction_strong` | `Strong` | Tooltip for flexed bicep reaction | 8 |
| `reaction_fire` | `Fire` | Tooltip for fire reaction | 6 |
| `reaction_respect` | `Respect` | Tooltip for respect reaction | 10 |
| `reaction_watching` | `Watching` | Tooltip for eyes reaction | 10 |
| `reaction_electric` | `Electric` | Tooltip for lightning reaction | 10 |
| `reaction_cold` | `Cold` | Tooltip for snowflake reaction | 6 |

### 7.19 All 108 Achievement Names and Descriptions

#### Category 1: Training (15)

| # | Key | Name | Description (Flavor Text) | Criteria Summary |
|---|-----|------|--------------------------|-----------------|
| 1 | `ach_first_rep` | `First Rep` | `Everyone starts somewhere. You started today.` | Complete 1 workout |
| 2 | `ach_getting_hooked` | `Getting Hooked` | `The habit is forming. Don't let go.` | Complete 10 workouts |
| 3 | `ach_gym_rat` | `Gym Rat` | `The staff knows your name. The weights know your grip.` | Complete 50 workouts |
| 4 | `ach_iron_temple` | `Iron Temple` | `This is your church. The barbell is your prayer.` | Complete 100 workouts |
| 5 | `ach_beast_mode` | `Beast Mode` | `You're not working out anymore. You're becoming something else.` | Complete 250 workouts |
| 6 | `ach_the_machine` | `The Machine` | `They don't even ask if you're going to the gym anymore.` | Complete 500 workouts |
| 7 | `ach_new_max` | `New Max` | `You just proved yesterday's you wrong.` | Set first PR |
| 8 | `ach_pr_machine` | `PR Machine` | `Records fall like dominos when you show up every day.` | Set 10 PRs |
| 9 | `ach_record_breaker` | `Record Breaker` | `At this point, the only person you're competing with is yesterday's you.` | Set 50 PRs |
| 10 | `ach_early_bird_lifter` | `Early Bird Lifter` | `While they sleep, you grow.` | Workout before 7 AM |
| 11 | `ach_night_owl_grind` | `Night Owl Grind` | `The gym is empty. The weights are all yours.` | Workout after 10 PM |
| 12 | `ach_recovery_listener` | `Recovery Listener` | `The strongest thing you did today was nothing.` | Rest on red recovery day |
| 13 | `ach_bodyweight_bencher` | `Bodyweight Bencher` | `You can officially press yourself off the ground. Both ways.` | Bench press bodyweight |
| 14 | `ach_double_bw_deadlift` | `Double Bodyweight Deadlift` | `The earth itself tried to hold that bar down.` | Deadlift 2x bodyweight |
| 15 | `ach_million_kilo_club` | `Million Kilo Club` | `You have literally moved a million kilograms. That's not a metaphor.` | 1,000,000 kg total volume |

#### Category 2: Study (12)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 16 | `ach_first_page` | `First Page` | `Every thesis begins with a single page.` | Log 1 study session |
| 17 | `ach_bookworm` | `Bookworm` | `You're starting to get that focused look.` | 10 total study hours |
| 18 | `ach_deep_focus` | `Deep Focus` | `Flow state achieved. The world disappeared for a while.` | 3+ hour single session |
| 19 | `ach_scholar` | `Scholar` | `100 hours of investment in your future self.` | 100 total hours |
| 20 | `ach_the_professor` | `The Professor` | `You could teach this course by now.` | 500 total hours |
| 21 | `ach_grandmaster` | `Grandmaster` | `10,000 hours to mastery. You're 10% of the way there. Keep going.` | 1,000 total hours |
| 22 | `ach_exam_survivor` | `Exam Survivor` | `You walked through fire and came out the other side.` | 5 days of 4h+ study |
| 23 | `ach_study_streak_pro` | `Study Streak Pro` | `Two weeks of discipline. This is who you are now.` | 14-day study target streak |
| 24 | `ach_dawn_scholar` | `Dawn Scholar` | `The world's most successful people have one thing in common.` | Study session before 6 AM |
| 25 | `ach_midnight_oil` | `Midnight Oil` | `When the deadline doesn't care about your sleep schedule.` | Study past 11 PM |
| 26 | `ach_five_hour_marathon` | `Five Hour Marathon` | `Your brain is sore in the best way.` | 5h study in one day |
| 27 | `ach_study_centurion` | `Study Centurion` | `One hundred days of showing up. That's not luck. That's character.` | Hit study target 100 days |

#### Category 3: Nutrition (12)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 28 | `ach_first_bite` | `First Bite` | `You are what you track.` | Log 1 meal |
| 29 | `ach_three_square` | `Three Square` | `Fuel in, performance out.` | Log all 3 meals in a day |
| 30 | `ach_macro_sniper` | `Macro Sniper` | `Precision nutrition. Your body thanks you.` | Hit all macros in one day |
| 31 | `ach_consistency_eater` | `Consistency Eater` | `A week of awareness. You see food differently now.` | All meals for 7 days |
| 32 | `ach_nutrition_machine` | `Nutrition Machine` | `Logging is no longer a chore. It's autopilot.` | All meals for 30 days |
| 33 | `ach_protein_king` | `Protein King` | `Your muscles are throwing a party in your honor.` | Protein target 30 days |
| 34 | `ach_macro_perfectionist` | `Macro Perfectionist` | `Seven days of nutritional perfection. Chef's kiss.` | All macros 7 days |
| 35 | `ach_hydration_master` | `Hydration Master` | `Your kidneys just wrote you a thank-you note.` | 3L water 14 days |
| 36 | `ach_year_round_logger` | `Year-Round Logger` | `You tracked every single day for a year. That's not discipline. That's identity.` | 2+ meals for 365 days |
| 37 | `ach_clean_streak` | `Clean Streak` | `Three in a row. Now make it four.` | Calorie target 3 days |
| 38 | `ach_snack_attack` | `Snack Attack` | `Snacking isn't cheating when you track it.` | Log 3 snacks in a day |
| 39 | `ach_macro_maestro` | `Macro Maestro` | `An entire month of macro perfection. You're operating on a different level.` | All macros 30 days |

#### Category 4: Recovery (10)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 40 | `ach_well_rested` | `Well Rested` | `This is what peak readiness feels like.` | First green recovery |
| 41 | `ach_green_machine` | `Green Machine` | `A full week in the green. Your body is a temple.` | 7 green days |
| 42 | `ach_sleep_champion` | `Sleep Champion` | `Sleep is the ultimate performance enhancer.` | Sleep score 90+ for 7 days |
| 43 | `ach_recovery_sage` | `Recovery Sage` | `A month in harmony. Your body and mind are aligned.` | 30 green days |
| 44 | `ach_machine_never_stops` | `The Machine Never Stops` | `Three months of perfect recovery. Scientists want to study you.` | 90 green days |
| 45 | `ach_hrv_pr` | `HRV PR` | `Your nervous system just peaked.` | New HRV high |
| 46 | `ach_sleep_pr` | `Sleep PR` | `Best night ever. Can you do it again?` | New sleep score high |
| 47 | `ach_consistent_bedtime` | `Consistent Bedtime` | `Your circadian rhythm just high-fived you.` | Same bedtime 14 days |
| 48 | `ach_early_to_bed` | `Early to Bed` | `You chose sleep over scrolling. Respect.` | Bedtime before 22:30 for 7 days |
| 49 | `ach_green_year` | `Green Year` | `One full year in the green. You might be the healthiest person on earth.` | 365 green days |

#### Category 5: Streaks (7)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 50 | `ach_spark` | `Spark` | `A spark becomes a fire.` | 3-day streak |
| 51 | `ach_on_fire` | `On Fire` | `One week down. Momentum is real.` | 7-day streak |
| 52 | `ach_inferno` | `Inferno` | `Two weeks. The habit is setting in.` | 14-day streak |
| 53 | `ach_iron_will` | `Iron Will` | `Thirty days of not quitting. That's iron will.` | 30-day streak |
| 54 | `ach_unbreakable` | `Unbreakable` | `Two months. They can't break what they can't catch.` | 60-day streak |
| 55 | `ach_forged_in_fire` | `Forged in Fire` | `Quarter of a year. You're forged in fire now.` | 90-day streak |
| 56 | `ach_immortal` | `Immortal` | `One full year. You didn't miss a single day. Immortal.` | 365-day streak |

#### Category 6: Social (12)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 57 | `ach_first_rival` | `First Rival` | `Competition begins now.` | Add first friend |
| 58 | `ach_squad_up` | `Squad Up` | `Your squad is forming.` | 5 friends |
| 59 | `ach_popular` | `Popular` | `You're the connector.` | 20 friends |
| 60 | `ach_full_house` | `Full House` | `Maximum capacity. Everyone wants to compete with you.` | 50 friends |
| 61 | `ach_first_blood` | `First Blood` | `First win. Many more to come.` | Win first challenge |
| 62 | `ach_challenge_dominator` | `Challenge Dominator` | `The throne is yours.` | Win 10 challenges |
| 63 | `ach_undefeated` | `Undefeated` | `They know better than to challenge you.` | Win 25 challenges |
| 64 | `ach_untouchable` | `Untouchable` | `Five straight wins. Untouchable.` | 5 wins in a row |
| 65 | `ach_win_streak_legend` | `Win Streak Legend` | `Ten consecutive victories. They write legends about less.` | 10 wins in a row |
| 66 | `ach_good_sport` | `Good Sport` | `It's not about winning. (It's a little about winning.)` | Complete 5 challenges |
| 67 | `ach_revenge` | `Revenge` | `Revenge is a dish best served with XP.` | Win rematch |
| 68 | `ach_group_commander` | `Group Commander` | `You beat them all.` | Win group challenge 5+ |

#### Category 7: Steps & Movement (10)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 69 | `ach_first_steps` | `First Steps` | `Every journey begins with a single step. You took 5,000.` | 5K steps |
| 70 | `ach_road_warrior` | `Road Warrior` | `10K steps is becoming second nature.` | 10K steps x7 |
| 71 | `ach_marathon_walker` | `Marathon Walker` | `A marathon on your feet. Respect.` | 42,195 steps in a day |
| 72 | `ach_step_millionaire` | `Step Millionaire` | `One million steps. Where did they all take you?` | 1M total steps |
| 73 | `ach_step_legend` | `Step Legend` | `A month of movement. Your legs are works of art.` | 10K steps for 30 days |
| 74 | `ach_15k_club` | `15K Club` | `Above and beyond.` | 15K steps in a day |
| 75 | `ach_20k_monster` | `20K Monster` | `Your step counter is scared of you.` | 20K steps in a day |
| 76 | `ach_25k_ultra` | `25K Ultra` | `You walked an ultra today and called it Tuesday.` | 25K steps in a day |
| 77 | `ach_weekend_warrior_walker` | `Weekend Warrior Walker` | `Weekends aren't for sitting.` | 10K+ on both Sat and Sun |
| 78 | `ach_step_centurion` | `Step Centurion` | `One hundred 10K days. Your Fitbit is proud.` | 10K+ on 100 days |

#### Category 8: Special / Composite (12)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 79 | `ach_perfect_day` | `Perfect Day` | `Every box checked. Flawless.` | 1 Perfect Day |
| 80 | `ach_perfect_week` | `Perfect Week` | `Seven perfect days. That's not luck. That's design.` | 7 consecutive Perfect Days |
| 81 | `ach_perfect_month` | `Perfect Month` | `An entire month of perfection. You're playing a different game.` | 30 consecutive Perfect Days |
| 82 | `ach_holiday_warrior` | `Holiday Warrior` | `Everyone else took the day off. Not you.` | Streak on a holiday |
| 83 | `ach_genesis` | `Genesis` | `Welcome to the Arena. Your journey begins now.` | Complete Arena tutorial |
| 84 | `ach_level_10` | `Level 10` | `Double digits. You're getting serious.` | Reach Level 10 |
| 85 | `ach_level_25` | `Level 25` | `Halfway to Legend. Keep climbing.` | Reach Level 25 |
| 86 | `ach_legend` | `Legend` | `You've reached the summit. But there's always higher.` | Reach Level 50 |
| 87 | `ach_prestige` | `Prestige` | `Back to Level 1, but you're not the same person.` | First prestige |
| 88 | `ach_triple_threat` | `Triple Threat` | `Body, mind, and fuel. All firing.` | 100+ XP from 3 categories in a day |
| 89 | `ach_the_comeback` | `The Comeback` | `You fell. But you got up faster.` | New 7-day streak within 3 days of breaking |
| 90 | `ach_weekend_warrior` | `Weekend Warrior` | `Weekends are for winners.` | 500+ XP on weekend |

#### Category 9: Hidden / Secret (10)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 91 | `ach_3am_club` | `3 AM Club` | `What are you doing awake? Whatever it is, we respect it.` | Activity between 3-4 AM |
| 92 | `ach_double_prestige` | `Double Prestige` | `You've been to the top twice. This is personal now.` | Prestige twice |
| 93 | `ach_streak_saver` | `The Streak Saver` | `That was close. The freeze caught you.` | Freeze saves streak |
| 94 | `ach_sunday_funday` | `Sunday Funday` | `Most people rest on Sunday. You're not most people.` | Workout + study on Sunday |
| 95 | `ach_new_years_grinder` | `New Year's Grinder` | `While everyone else was recovering, you were already ahead.` | 500+ XP on Jan 1 |
| 96 | `ach_birthday_gains` | `Birthday Gains` | `Happy birthday. You chose gains over cake.` | Earn XP on birthday |
| 97 | `ach_silent_assassin` | `Silent Assassin` | `You let the scoreboard do the talking.` | 3 wins without reactions |
| 98 | `ach_generous` | `Generous` | `You lift others up. That makes you a champion.` | 50 reactions sent |
| 99 | `ach_the_collector` | `The Collector` | `Your crew spans every league. Diverse taste.` | Friends in 5 league tiers |
| 100 | `ach_100_club` | `100 Club` | `One hundred achievements. Achievement hunter extraordinaire.` | 100 achievements |

#### Category 10: Meta (8)

| # | Key | Name | Description | Criteria |
|---|-----|------|-------------|---------|
| 101 | `ach_well_rounded` | `Well Rounded` | `A little bit of everything. The mark of a true competitor.` | 1+ in every category |
| 102 | `ach_training_elite` | `Training Elite` | `The gym is your kingdom.` | 10 Training achievements |
| 103 | `ach_scholar_elite` | `Scholar Elite` | `Knowledge is your superpower.` | 8 Study achievements |
| 104 | `ach_social_butterfly` | `Social Butterfly` | `Your social game is as strong as your grind.` | 8 Social achievements |
| 105 | `ach_achievement_hunter` | `Achievement Hunter` | `Halfway to catching them all.` | 50 total achievements |
| 106 | `ach_completionist_1` | `Completionist I` | `75 down. You're obsessed. We love it.` | 75 total achievements |
| 107 | `ach_completionist_2` | `Completionist II` | `The century mark. You did what most never will.` | 100 total achievements |
| 108 | `ach_tempo_mythic` | `Tempo Mythic` | `Every single achievement. You didn't just play the game. You completed it. Legend.` | All 107 other achievements |

### 7.20 Achievement Near-Completion Nudge

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `ach_almost` | `Almost there!` | Nudge card prefix | 15 |
| `ach_unlock` | `UNLOCK` | Nudge action label | 8 |

### 7.21 Arena Onboarding

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `arena_onb_welcome_title` | `Welcome to the Arena` | Screen 1 title | 25 |
| `arena_onb_welcome_body` | `This is where effort becomes competition. Earn XP for everything you do, level up, and prove you're grinding harder than your friends.` | Screen 1 body | 130 |
| `arena_onb_welcome_cta` | `Let's Go` | Screen 1 CTA | 10 |
| `arena_onb_enter_cta` | `Enter the Arena` | Screen 5 CTA | 18 |
| `arena_onb_username_placeholder` | `Choose your arena name` | Username field | 24 |
| `arena_onb_username_available` | `Available` | Green indicator | 10 |
| `arena_onb_username_taken` | `Already taken. Try another.` | Red indicator | 30 |

---

## 8. Settings Copy

### 8.1 Main Settings Sections

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `settings_title` | `Settings` | Navigation title | 10 |
| `settings_account` | `Account` | Section header | 10 |
| `settings_integrations` | `Integrations` | Section header | 14 |
| `settings_training` | `Training` | Section header | 10 |
| `settings_accountability` | `Accountability` | Section header | 16 |
| `settings_notifications` | `Notifications` | Section header | 16 |
| `settings_appearance` | `Appearance` | Section header | 12 |
| `settings_about` | `About` | Section header | 8 |

### 8.2 Account Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `settings_display_name` | `Display Name` | Row label | 14 |
| `settings_username` | `Username` | Row label | 10 |
| `settings_username_change_limit` | `You can change this once every 30 days.` | Username change warning | 45 |
| `settings_avatar` | `Profile Photo` | Row label | 14 |
| `settings_sign_out` | `Sign Out` | Row label, red text | 10 |
| `settings_sign_out_confirm` | `Sign out of Tempo?` | Confirmation title | 22 |
| `settings_sign_out_yes` | `Sign Out` | Confirm button | 10 |
| `settings_delete_account` | `Delete Account` | Row label, red text | 16 |
| `settings_delete_warning` | `This permanently deletes all your data, including XP, achievements, streaks, and workout history. You'll be removed from all leaderboards and active challenges. This cannot be undone.` | Delete warning | 200 |
| `settings_delete_confirm_prompt` | `Type DELETE to confirm.` | Confirmation input | 28 |
| `settings_delete_btn` | `Delete Account` | Destructive button | 16 |

### 8.3 Integration Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `settings_whoop` | `Whoop` | Row label | 8 |
| `settings_nutritrack` | `NutriTrack` | Row label | 12 |
| `settings_healthkit` | `Apple Health` | Row label | 14 |
| `settings_calendar` | `Apple Calendar` | Row label | 16 |
| `settings_integration_connected` | `Connected` | Status, green | 12 |
| `settings_integration_disconnected` | `Not Connected` | Status, gray | 15 |
| `settings_integration_error` | `Error -- Tap to reconnect` | Status, red | 28 |
| `settings_whoop_disconnect` | `Disconnect Whoop` | Action | 18 |
| `settings_whoop_disconnect_confirm` | `Disconnect Whoop? Recovery data will no longer sync. Historical data is preserved.` | Confirmation | 80 |

### 8.4 Notification Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `settings_notif_intensity` | `Notification Intensity` | Row label | 24 |
| `settings_notif_accountability` | `Accountability Reminders` | Toggle label | 28 |
| `settings_notif_training` | `Training Reminders` | Toggle label | 20 |
| `settings_notif_recovery` | `Recovery Updates` | Toggle label | 18 |
| `settings_notif_arena` | `Arena Notifications` | Toggle label | 22 |
| `settings_notif_weekly` | `Weekly Report` | Toggle label | 16 |

### 8.5 Arena Settings

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `arena_settings_title` | `Arena Settings` | Navigation title | 16 |
| `arena_settings_profile` | `PROFILE` | Section header | 10 |
| `arena_settings_privacy` | `PRIVACY` | Section header | 10 |
| `arena_settings_notifications` | `NOTIFICATIONS` | Section header | 16 |
| `arena_settings_streaks` | `STREAKS` | Section header | 10 |
| `arena_settings_leaderboard` | `LEADERBOARD` | Section header | 14 |
| `arena_settings_friends` | `FRIENDS` | Section header | 10 |
| `arena_settings_account` | `ACCOUNT` | Section header | 10 |
| `arena_settings_sound` | `Sound Effects` | Toggle label | 14 |
| `arena_settings_feed_opt_out` | `Post to Friends' Feed` | Toggle label | 24 |
| `arena_settings_feed_warning` | `Your activities won't appear in friends' feeds. You'll still see their activities.` | Warning when OFF | 80 |
| `arena_settings_leaderboard_opt` | `Participate in Leaderboard` | Toggle label | 28 |
| `arena_settings_leaderboard_warning` | `You won't appear on any leaderboard and won't see your ranking. Your friends won't see you in their leaderboards. You can re-join anytime.` | Warning when OFF | 130 |
| `arena_settings_my_qr` | `My QR Code` | Row label | 12 |
| `arena_settings_blocked` | `Blocked Users` | Row label | 16 |
| `arena_settings_muted` | `Muted Users` | Row label | 14 |
| `arena_settings_reset` | `Reset Arena Data` | Row label, red | 18 |
| `arena_settings_reset_warning` | `Reset Arena Data? This will reset your XP, level, streaks, and achievements to zero. Your friends and challenge history will be preserved. This cannot be undone.` | Confirmation | 160 |
| `arena_settings_reset_prompt` | `Type RESET to confirm.` | Input prompt | 25 |

---

## 9. Error Messages

### 9.1 Network Errors

| Key | Title | Body | Primary Action | Secondary Action |
|-----|-------|------|----------------|-----------------|
| `error_offline_title` | `You're offline` | `Check your internet connection and try again.` | `Retry` | `Dismiss` |
| `error_timeout_title` | `Request timed out` | `The server took too long to respond. Try again.` | `Retry` | `Dismiss` |
| `error_server_title` | `Something went wrong` | `We're having trouble on our end. Try again in a moment.` | `Retry` | `Dismiss` |

### 9.2 Auth Errors

| Key | Title | Body | Primary Action | Secondary Action |
|-----|-------|------|----------------|-----------------|
| `error_session_title` | `Session expired` | `Sign in again to continue.` | `Sign In` | -- |
| `error_auth_required_title` | `Sign-in required` | `This feature requires an account.` | `Sign In` | `Cancel` |

### 9.3 Data Errors

| Key | Title | Body | Primary Action | Secondary Action |
|-----|-------|------|----------------|-----------------|
| `error_sync_title` | `Sync failed` | `Your data couldn't sync. Changes are saved locally.` | `Retry` | `Dismiss` |
| `error_data_title` | `Data error` | `Something went wrong with your data. Try restarting the app.` | `OK` | -- |

### 9.4 Permission Errors

| Key | Title | Body | Primary Action | Secondary Action |
|-----|-------|------|----------------|-----------------|
| `error_healthkit_title` | `Health access denied` | `Tempo needs Health access to track your activity. Enable it in Settings.` | `Open Settings` | `Not Now` |
| `error_notif_title` | `Notifications disabled` | `Enable notifications to get accountability reminders.` | `Open Settings` | `Not Now` |
| `error_calendar_title` | `Calendar access denied` | `Tempo needs calendar access to detect classes and exams.` | `Open Settings` | `Not Now` |

---

## 10. Empty States

### 10.1 Dashboard Empty States

| Key | Headline | Body | CTA |
|-----|----------|------|-----|
| `empty_dashboard_no_data` | `Connect your sources` | `Link Whoop, NutriTrack, and Apple Health to see your data.` | `Set Up Integrations` |
| `empty_body_quad` | `No recovery data` | `Connect Whoop to start tracking.` | `Connect Whoop` |
| `empty_fuel_quad` | `No nutrition data` | `Connect NutriTrack to start tracking.` | `Connect NutriTrack` |
| `empty_mind_no_sessions` | `No study sessions yet` | `Start a focus session to begin.` | `Start Session` |
| `empty_move_no_data` | `No activity data` | `Authorize Apple Health to track.` | `Authorize` |

### 10.2 Training Empty States

| Key | Headline | Body | CTA |
|-----|----------|------|-----|
| `empty_training_no_plan` | `No workout plan` | `Set up your training profile to generate a plan.` | `Set Up Training` |
| `empty_training_no_history` | `No workouts recorded this week.` | -- | -- |

### 10.3 Arena Empty States

| Key | Headline | Body | CTA |
|-----|----------|------|-----|
| `empty_arena_no_friends` | `No friends yet` | `Add friends to compete on leaderboards.` | `Invite Friends` |
| `empty_challenges_none` | `No active challenges` | `Start a challenge to compete with friends.` | `Start a Challenge` |
| `empty_achievements_locked` | `All achievements locked` | `Complete tasks to start unlocking.` | -- |
| `empty_feed_no_friends` | `Add friends to see their activity here!` | -- | `Invite Friends` |

---

## 11. Confirmation Dialogs

### 11.1 Destructive Actions

| Key | Title | Body | Confirm (Red) | Cancel |
|-----|-------|------|--------------|--------|
| `confirm_delete_account` | `Delete your account?` | `This permanently deletes all your data. This cannot be undone.` | `Delete Account` | `Cancel` |
| `confirm_remove_friend` | `Remove @{username}?` | `They won't be notified, but you'll be removed from each other's leaderboards.` | `Remove` | `Cancel` |
| `confirm_block_user` | `Block @{username}?` | `They won't be able to find you, send requests, or see your profile.` | `Block` | `Cancel` |
| `confirm_cancel_workout` | `Cancel workout?` | `Your logged sets will be saved.` | `Cancel Workout` | `Keep Going` |
| `confirm_skip_nn` | `Skip this non-negotiable?` | `This counts against your daily progress.` | `Skip` | `Keep It` |
| `confirm_delete_nn` | `Delete '{name}'?` | `Historical data will be preserved.` | `Delete` | `Cancel` |
| `confirm_reset_arena` | `Reset Arena Data?` | `This resets your XP, level, streaks, and achievements to zero. This cannot be undone.` | `Reset` | `Cancel` |

### 11.2 Significant Actions

| Key | Title | Body | Confirm | Cancel |
|-----|-------|------|---------|--------|
| `confirm_streak_freeze` | `Use a streak freeze?` | `This will use 1 freeze to protect tomorrow's streak.` | `Use Freeze` | `Cancel` |
| `confirm_exam_mode` | `Activate Exam Mode?` | `Study target increases to 4h. Training becomes optional.` | `Activate` | `Cancel` |
| `confirm_sick_day` | `Activate Sick Day?` | `Targets reduced. No penalties. Streak preserved.` | `Activate` | `Cancel` |
| `confirm_template_apply` | `Apply template?` | `This will replace your current non-negotiables.` | `Apply` | `Cancel` |
| `confirm_sign_out` | `Sign out?` | `You can sign back in anytime.` | `Sign Out` | `Cancel` |

---

## 12. Accessibility Labels

### 12.1 Navigation & Tab Bar

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_tab_home` | `Home tab` |
| `a11y_tab_train` | `Training tab` |
| `a11y_tab_lockdown` | `Lockdown tab` |
| `a11y_tab_recover` | `Recovery tab` |
| `a11y_tab_arena` | `Arena tab. {n} new notifications.` |

### 12.2 Dashboard

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_score_ring` | `Daily score: {n} out of 100` |
| `a11y_score_loading` | `Daily score: calculating` |
| `a11y_body_quad` | `Body quadrant. Recovery {n} percent. Tap for details.` |
| `a11y_fuel_quad` | `Fuel quadrant. {consumed} of {target} calories. Tap for details.` |
| `a11y_mind_quad` | `Mind quadrant. {time} studied of {target} target. Tap for details.` |
| `a11y_move_quad` | `Move quadrant. {steps} steps. {status}. Tap for details.` |
| `a11y_nn_item_complete` | `{name}, completed` |
| `a11y_nn_item_incomplete` | `{name}, not completed. Double tap to mark complete.` |
| `a11y_settings_btn` | `Settings` |
| `a11y_notification_btn` | `Notifications. {n} unread.` |

### 12.3 Training

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_recovery_badge` | `Recovery {n} percent, {zone} zone. {recommendation}.` |
| `a11y_exercise_card` | `{name}. {sets} sets of {reps} at {weight}. Tap for details.` |
| `a11y_weight_input` | `Weight: {n} kilograms. Double tap to edit. Swipe up to increase by 2.5, swipe down to decrease.` |
| `a11y_start_workout` | `Start workout` |
| `a11y_rest_timer` | `Rest timer. {time} remaining. Double tap to skip.` |

### 12.4 Focus Timer

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_timer_running` | `Focus timer. {time} remaining. Session {n} of {total}.` |
| `a11y_timer_paused` | `Timer paused at {time}.` |
| `a11y_focus_score` | `Focus score: {n} out of 100. {quality}.` |

### 12.5 Recovery

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_recovery_ring` | `Recovery score: {n} percent. {zone} zone.` |
| `a11y_metric_tile` | `{label}: {value} {unit}. {trend} {percentage} compared to average.` |
| `a11y_sleep_bar` | `Sleep stages: {deep} hours deep, {rem} hours REM, {light} hours light, {awake} hours awake.` |
| `a11y_prescription_card` | `{category} recommendation: {headline}. Double tap for details.` |

### 12.6 Arena

| Element | VoiceOver Label |
|---------|----------------|
| `a11y_level_badge` | `Level {n}, {title}. {percent} percent to next level.` |
| `a11y_streak_display` | `{n} day streak. {multiplier}x multiplier active.` |
| `a11y_leaderboard_row` | `Rank {rank}, {name}, {xp} experience points, Level {level}.` |
| `a11y_achievement_badge` | `{name}. {description}. {rarity}. {locked_or_unlocked}.` |
| `a11y_xp_value` | `plus {n} experience points` |
| `a11y_challenge_card` | `Challenge versus {opponent}: {metric}. You: {your_score}. {opponent}: {their_score}. {time} remaining.` |

### 12.7 Progress Indicators

| Element | VoiceOver Value |
|---------|----------------|
| `a11y_progress_ring_value` | `{n} percent complete` |
| `a11y_progress_bar_value` | `{n} of {target}` |
| `a11y_streak_calendar_day` | `{date}. {completion} percent completed.` |

---

## 13. App Store Copy

### 13.1 Listing

| Key | Text | Limit |
|-----|------|-------|
| `appstore_name` | `Tempo` | 30 |
| `appstore_subtitle` | `Your Life Operating System` | 30 |
| `appstore_keywords` | `fitness,accountability,whoop,recovery,study,workout,nutrition,habits,discipline,college,athlete` | 100 |
| `appstore_promo_text` | `Stop wasting your potential. One app for training, nutrition, recovery, academics, and accountability.` | 170 |

### 13.2 Full Description

```
Stop wasting your potential.

You train. You study. You try to eat right. But every evening, you end up on the couch wondering where the time went. Tempo fixes that.

Tempo is a life operating system for student-athletes who refuse to be average. It connects your training, nutrition, recovery, academics, and daily habits into one system -- and holds you accountable with a drill-sergeant that never takes a day off.

HOW IT WORKS

Set your daily non-negotiables: study hours, meals, training. Tempo tracks them automatically through Whoop, Apple Health, and NutriTrack. Complete everything? You've earned your evening. Miss something? Tempo won't let you forget.

FIVE MODULES, ONE SYSTEM

DASHBOARD -- See your entire life at a glance. Recovery score, nutrition, study progress, and training -- all in one view.

TRAINING (RepForge) -- AI workout programming that adapts to your recovery. Never program heavy legs before football again. Progressive overload tracked automatically.

ACCOUNTABILITY (Lockdown) -- Daily non-negotiables with escalating reminders. PS5 time is earned, not default. Your drill sergeant gets louder as the evening approaches.

RECOVERY (RecoverIQ) -- Whoop-powered daily prescriptions. Training intensity, meal timing, bedtime, caffeine cutoff -- all calculated from your biometrics.

ARENA (ClutchTime) -- Compete with friends on weekly leaderboards. Earn XP for hitting targets. Lose XP for slacking. Challenge your training partners to study-hour battles.

INTEGRATIONS

- Whoop: Recovery, sleep, strain, HRV
- Apple Health: Steps, workouts, heart rate
- NutriTrack: Meals, macros, meal timing
- Apple Calendar: Class schedule, exams, football practice

WHO THIS IS FOR

University students who are athletes. People who have the ambition but struggle with the execution. If you want a coach who tells you what you want to hear, this isn't it. If you want a coach who tells you what you need to hear -- welcome to Tempo.

No subscriptions. No ads. Just results.
```

### 13.3 Screenshot Captions

| # | Key | Caption |
|---|-----|---------|
| 1 | `screenshot_1` | `Your entire life. One screen.` |
| 2 | `screenshot_2` | `PS5 is earned, not default.` |
| 3 | `screenshot_3` | `Your AI coach adapts to your recovery.` |
| 4 | `screenshot_4` | `Know exactly how hard to push.` |
| 5 | `screenshot_5` | `Compete with your friends.` |
| 6 | `screenshot_6` | `A drill sergeant in your pocket.` |

### 13.4 What's New Template

```
What's new in Tempo {version}:

- {feature_1}
- {feature_2}
- {feature_3}

Bug fixes and performance improvements.

Questions? Feedback? Let us know at tempo@support.com.
```

---

## 14. Weekly Report Copy

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `report_title` | `Weekly Report` | Navigation title | 16 |
| `report_date_range` | `{start} -- {end}, {year}` | e.g. "Mar 18 -- Mar 24, 2026" | 30 |
| `report_overall` | `OVERALL SCORE` | Section header | 16 |
| `report_body_section` | `BODY` | Section header | 6 |
| `report_fuel_section` | `FUEL` | Section header | 6 |
| `report_mind_section` | `MIND` | Section header | 6 |
| `report_move_section` | `MOVE` | Section header | 6 |
| `report_insights` | `AI INSIGHTS` | Section header | 12 |
| `report_patterns` | `PATTERNS DETECTED` | Section header | 18 |
| `report_share_cta` | `Share Report` | Share button | 14 |
| `report_prev` | `<- Previous Week` | Navigation | 18 |
| `report_next` | `Next Week ->` | Navigation | 14 |
| `report_share_text` | `My Tempo week: {score}/100 -- Body {body}, Fuel {fuel}, Mind {mind}, Move {move}` | Share text template | 80 |

### 14.1 Weekly Report Quips

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `report_quip_90` | `Dominant week. Keep the standard.` | Avg 90-100 | 36 |
| `report_quip_75` | `Solid week. Room to grow.` | Avg 75-89 | 28 |
| `report_quip_60` | `Average. You know you're better than this.` | Avg 60-74 | 45 |
| `report_quip_40` | `Below the line. Time to lock in.` | Avg 40-59 | 36 |
| `report_quip_0` | `Rough week. Reset starts now.` | Avg 0-39 | 32 |

---

## 15. Expanded View Quips

### 15.1 Fuel Expanded Quips

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `fuel_quip_low_1` | `You running on fumes?` | <50% of target | 24 |
| `fuel_quip_low_2` | `That's not enough to fuel a hamster.` | <50% | 40 |
| `fuel_quip_low_3` | `Eat. This isn't negotiable.` | <50% | 28 |
| `fuel_quip_mid_1` | `Still got room for {remaining} kcal.` | 50-79% | 35 |
| `fuel_quip_mid_2` | `Halfway there. Keep fueling.` | 50-79% | 28 |
| `fuel_quip_good_1` | `On track. Don't blow it at dinner.` | 80-100% | 36 |
| `fuel_quip_good_2` | `Dialed in. Keep it clean.` | 80-100% | 26 |
| `fuel_quip_over_1` | `Over by {overage}. Noted.` | 100-120% | 24 |
| `fuel_quip_over_2` | `Slight surplus. Not the end of the world.` | 100-120% | 44 |
| `fuel_quip_way_over_1` | `That's a surplus, not a strategy.` | >120% | 38 |
| `fuel_quip_way_over_2` | `{overage} over. Tomorrow, tighten up.` | >120% | 35 |

### 15.2 Mind Expanded Quips

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `mind_quip_zero_1` | `Zero minutes. The books miss you.` | 0% | 36 |
| `mind_quip_zero_2` | `Nothing logged. The clock is ticking.` | 0% | 40 |
| `mind_quip_under_1` | `Not done yet. Back to the desk.` | 1-49% | 34 |
| `mind_quip_under_2` | `Under half. Pick up the pace.` | 1-49% | 32 |
| `mind_quip_half_1` | `Halfway doesn't pass exams.` | 50-99% | 30 |
| `mind_quip_half_2` | `More than half. Keep going.` | 50-99% | 28 |
| `mind_quip_done_1` | `Target hit. Respect.` | 100% | 22 |
| `mind_quip_done_2` | `Full send. Well done.` | 100% | 22 |
| `mind_quip_extra_1` | `Going extra. That's elite.` | >120% | 28 |
| `mind_quip_extra_2` | `Overtime. You're building something.` | >120% | 38 |

### 15.3 Move Expanded Quips

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `move_quip_done_1` | `Solid session. Now recover.` | Workout completed | 28 |
| `move_quip_done_2` | `Done and dusted.` | Completed | 18 |
| `move_quip_done_3` | `Checked off. Next one's waiting.` | Completed | 34 |
| `move_quip_done_4` | `Work in the bank.` | Completed | 18 |
| `move_quip_planned` | `Planned. Tap to start.` | Planned | 22 |
| `move_quip_rest` | `Growth happens in the recovery.` | Rest day | 34 |
| `move_quip_none_cta` | `+ Plan Workout` | No workout, link | 16 |
| `move_step_pace` | `Step pace: On track for {projected}` | Step projection | 35 |
| `move_step_early` | `Too early to project` | Before 8 AM | 24 |
| `move_hr_current` | `Current: {hr} bpm` | Current heart rate | 18 |
| `move_hr_last` | `Last: {hr} bpm ({time_ago})` | Stale heart rate | 25 |
| `move_hr_range` | `Today's range: {min} -- {max} bpm` | HR range | 30 |
| `move_no_workouts_week` | `No workouts recorded this week.` | Empty workout history | 36 |

---

## 16. Patterns & Correlation View

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `patterns_title` | `Patterns` | Navigation title | 10 |
| `patterns_strong` | `STRONG CORRELATIONS` | Section header | 22 |
| `patterns_behavioral` | `BEHAVIORAL PATTERNS` | Section header | 22 |
| `patterns_recommendations` | `RECOMMENDATIONS` | Section header | 18 |
| `patterns_7d` | `7D` | Time range | 3 |
| `patterns_30d` | `30D` | Time range | 4 |
| `patterns_90d` | `90D` | Time range | 4 |
| `patterns_all` | `ALL` | Time range | 4 |
| `patterns_correlation_strong` | `Strong` | |r| >= 0.7 | 8 |
| `patterns_correlation_moderate` | `Moderate` | |r| >= 0.5 | 10 |
| `patterns_positive` | `positive` | Direction | 10 |
| `patterns_negative` | `negative` | Direction | 10 |
| `patterns_occurrences` | `Occurrences: {n} in {range} days` | Pattern occurrence count | 30 |

---

## 17. Nutrition · Intake Wizard

Drill-sergeant tone throughout. Wizard is invoked from "Generate New Plan" in the Plan tab; collects session-scoped intake before the meal-plan generator runs.

| Key | Text | Context | Limit |
|-----|------|---------|-------|
| `nutrition.wizard.header` | `PLAN INTAKE` | Header label | 12 |
| `nutrition.wizard.cancel` | `Cancel` | Header cancel button | 8 |
| `nutrition.wizard.step.next` | `Next` | Primary footer (mid-flow) | 8 |
| `nutrition.wizard.step.back` | `Back` | Secondary footer | 8 |
| `nutrition.wizard.cookingCapacity.title` | `Real cook count.` | Step title | 24 |
| `nutrition.wizard.cookingCapacity.subtitle` | `How many days this week can you actually cook? Not optimistic — real.` | Question | 120 |
| `nutrition.wizard.cookingCapacity.footer.0` | `Zero cooking days. Plan will lean on no-cook foods + leftovers.` | Footer hint | 100 |
| `nutrition.wizard.cookingCapacity.footer.1to2` | `Light cooking week. Batches and quick assemblies.` | Footer hint | 100 |
| `nutrition.wizard.cookingCapacity.footer.3to4` | `Standard. Most plans land here.` | Footer hint | 100 |
| `nutrition.wizard.cookingCapacity.footer.5to6` | `Heavy cook week. Variety will be high.` | Footer hint | 100 |
| `nutrition.wizard.cookingCapacity.footer.7` | `Cooking every day. Solid commitment.` | Footer hint | 100 |
| `nutrition.wizard.leftoverTolerance.title` | `Same meal, two days in a row?` | Step title | 36 |
| `nutrition.wizard.leftoverTolerance.subtitle` | `Tells me how aggressive I can be with batch prep.` | Question | 80 |
| `nutrition.wizard.leftoverTolerance.fresh` | `Fresh every day` | Option | 20 |
| `nutrition.wizard.leftoverTolerance.batches` | `2-3 day batches` | Option | 20 |
| `nutrition.wizard.leftoverTolerance.fullWeek` | `Full-week prep` | Option | 20 |
| `nutrition.wizard.eatingWindow.title` | `First meal, last meal.` | Step title | 28 |
| `nutrition.wizard.eatingWindow.subtitle` | `I anchor the plan around your eating window. Honesty pays off here.` | Question | 100 |
| `nutrition.wizard.eatingWindow.first` | `First meal` | Row label | 16 |
| `nutrition.wizard.eatingWindow.last` | `Last meal` | Row label | 16 |
| `nutrition.wizard.pantryGap.title` | `Pantry status.` | Step title | 20 |
| `nutrition.wizard.pantryGap.subtitle.empty` | `Your pantry shows zero items. Need a grocery run, or working from elsewhere?` | When pantry count == 0 | 120 |
| `nutrition.wizard.pantryGap.subtitle.stale` | `Pantry shows {N} items but hasn't been updated lately. Still accurate?` | When pantry stale | 120 |
| `nutrition.wizard.pantryGap.shop.title` | `I'm doing a grocery run.` | Option | 32 |
| `nutrition.wizard.pantryGap.shop.subtitle` | `Plan can include fresh purchases.` | Option detail | 60 |
| `nutrition.wizard.pantryGap.fromPantry.title` | `Work from what I already have.` | Option | 36 |
| `nutrition.wizard.pantryGap.fromPantry.subtitle` | `Plan stays within current pantry + small additions.` | Option detail | 80 |
| `nutrition.wizard.groceryIntent.title` | `Grocery limits.` | Step title | 24 |
| `nutrition.wizard.groceryIntent.subtitle` | `Budget cap and preferred stores. Skip what doesn't apply.` | Question | 80 |
| `nutrition.wizard.groceryIntent.budget.label` | `BUDGET CAP (USD)` | Field label | 24 |
| `nutrition.wizard.groceryIntent.budget.placeholder` | `e.g. 75` | Field placeholder | 12 |
| `nutrition.wizard.groceryIntent.stores.label` | `PREFERRED STORES` | Field label | 24 |
| `nutrition.wizard.groceryIntent.stores.placeholder` | `e.g. Publix, Trader Joe's` | Field placeholder | 32 |
| `nutrition.wizard.recoveryOverride.title` | `Adjust around training?` | Step title | 28 |
| `nutrition.wizard.recoveryOverride.subtitle.score` | `Yesterday's recovery: {score}. Want the plan to lean into that?` | Question (Whoop) | 100 |
| `nutrition.wizard.recoveryOverride.subtitle.noScore` | `Adjust calorie distribution based on training intensity this week?` | Question (fallback) | 100 |
| `nutrition.wizard.recoveryOverride.toggle.title` | `Skew fueling to training load` | Toggle label | 36 |
| `nutrition.wizard.recoveryOverride.toggle.subtitle` | `More fuel on training days, lighter on rest days.` | Toggle detail | 80 |
| `nutrition.wizard.recoveryOverride.badge` | `Whoop recovery yesterday` | Badge | 28 |
| `nutrition.wizard.temporaryExclusions.title` | `Off the table this week.` | Step title | 28 |
| `nutrition.wizard.temporaryExclusions.subtitle` | `Not allergies — just things you're not in the mood for. Skip if nothing.` | Question | 100 |
| `nutrition.wizard.temporaryExclusions.placeholder` | `e.g. broccoli` | Input placeholder | 16 |
| `nutrition.wizard.review.title` | `Lock it in.` | Step title | 16 |
| `nutrition.wizard.review.subtitle` | `Final read. Tap Generate when ready.` | Subtitle | 60 |
| `nutrition.wizard.review.cta` | `Generate Plan` | Primary CTA | 16 |
| `nutrition.wizard.review.row.cookable` | `Cookable days` | Summary label | 20 |
| `nutrition.wizard.review.row.leftovers` | `Leftovers` | Summary label | 12 |
| `nutrition.wizard.review.row.window` | `Eating window` | Summary label | 16 |
| `nutrition.wizard.review.row.grocery` | `Grocery` | Summary label | 10 |
| `nutrition.wizard.review.row.recovery` | `Recovery skew` | Summary label | 16 |
| `nutrition.wizard.review.row.excluding` | `Excluding` | Summary label | 12 |

---

*End of UX Copy Bible. Total unique string keys: ~950+. This document is the single source of truth for all text in the Tempo app.*
