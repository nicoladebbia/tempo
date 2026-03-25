# AI Intelligence Engine -- Complete Specification

**App:** Tempo (iOS, SwiftUI)
**Engine Codename:** CortexAI
**Version:** 1.0
**Last Updated:** 2026-03-24
**Author:** Tempo Engineering
**Stack:** Claude API (Anthropic) -- Haiku 4.5 for real-time, Sonnet 4.6 for deep analysis, Opus 4.6 for pattern detection

---

## Table of Contents

1. [AI Features Overview](#1-ai-features-overview)
2. [Claude API Configuration](#2-claude-api-configuration)
3. [Prompt Templates](#3-prompt-templates)
4. [Data Pipeline](#4-data-pipeline)
5. [Cost Management](#5-cost-management)
6. [Caching Strategy](#6-caching-strategy)
7. [Quality Assurance](#7-quality-assurance)
8. [Offline / Fallback System](#8-offline--fallback-system)
9. [Responsible AI & Safety](#9-responsible-ai--safety)
10. [Future AI Features (v2+)](#10-future-ai-features-v2)
11. [Privacy Considerations](#11-privacy-considerations)

---

## 1. AI Features Overview

Every AI-powered feature in Tempo, its purpose, trigger, and which module owns it.

| # | Feature | Module | Trigger | Model | Priority |
|---|---------|--------|---------|-------|----------|
| 1 | Morning Briefing Generation | Dashboard / Accountability | Daily at wake time | Template (free) with Haiku 4.5 fallback | P0 |
| 2 | Weekly Report Analysis | Dashboard | Sunday 8 PM / on-demand | Sonnet 4.6 | P0 |
| 3 | Pattern / Correlation Detection | Dashboard | Weekly (background) / on-demand | Opus 4.6 | P0 |
| 4 | Training Program Generation | RepForge | Weekly plan generation + recovery-triggered adjustments | Sonnet 4.6 | P1 |
| 5 | Training Program Adjustment | RepForge | When recovery data changes significantly | Haiku 4.5 | P1 |
| 6 | Recovery Prescription Generation | RecoverIQ | Daily after Whoop sync | Haiku 4.5 | P0 |
| 7 | Drill Sergeant Notification Copy | Lockdown | Notification schedule triggers (2 PM, 5 PM, 6:30 PM, evening) | Sonnet 4.6 | P1 |
| 8 | Meal Timing Recommendations | RecoverIQ / Fuel | After recovery sync + NutriTrack data refresh | Haiku 4.5 | P2 |
| 9 | Study Schedule Optimization | Lockdown / Mind | When exam dates added or weekly planning | Sonnet 4.6 | P2 |
| 10 | Achievement / Milestone Celebrations | Arena (ClutchTime) | On milestone trigger | Haiku 4.5 | P2 |
| 11 | Natural Language Dashboard Insights | Dashboard | On dashboard load (if data changed since last generation) | Haiku 4.5 | P1 |
| 12 | Notification Batch Pre-Generation | Lockdown | Sunday night (generate 3 days of notification copy) | Sonnet 4.6 | P1 |

### Feature Dependency Graph

```
Whoop Sync ─┬─→ Recovery Prescription (Haiku 4.5)
             ├─→ Training Adjustment (Haiku 4.5)
             ├─→ Morning Briefing (Template, free — Haiku 4.5 if template fails)
             └─→ Meal Timing Recs (Haiku 4.5)

NutriTrack Sync ─┬─→ Dashboard Insights (Haiku 4.5)
                  └─→ Meal Timing Recs (Haiku 4.5)

Weekly Cron ─┬─→ Weekly Report (Sonnet 4.6)
             ├─→ Pattern Detection (Opus 4.6) ← highest-value feature, worth the cost
             ├─→ Training Program Generation (Sonnet 4.6)
             ├─→ Notification Batch Pre-Gen (Sonnet 4.6, 3-day batches x2/week)
             └─→ Study Schedule Optimization (Sonnet 4.6)

User Action ─┬─→ Ad-hoc Pattern Query (Opus 4.6)
             └─→ Force Regenerate Weekly (Sonnet 4.6)
```

---

## 2. Claude API Configuration

### 2.1 Model Selection

| Model | Model ID | Use Cases | Why |
|-------|----------|-----------|-----|
| **Claude Haiku 4.5** | `claude-haiku-4-5-20250901` | Recovery prescriptions, dashboard insights, training adjustments, meal timing, celebrations | Sub-second latency, lowest cost. These features need speed -- users are staring at a loading state. |
| **Claude Sonnet 4.6** | `claude-sonnet-4-6-20250514` | Weekly reports, training program generation, study schedule optimization, notification batch copy | Deep reasoning over multi-day data. Users wait for these (async/background). Quality matters more than speed. Notification copy upgraded from Haiku because quality and variety matter for daily engagement -- mediocre copy kills user trust. |
| **Claude Opus 4.6** | `claude-opus-4-6-20250901` | Pattern / correlation detection (weekly + on-demand) | This is the highest-value AI feature in the app. Pattern detection over 30-90 days of cross-domain data requires the best reasoning. Running once per week keeps cost manageable (~$0.30/call). The quality difference vs Sonnet is dramatic for multi-variable correlation interpretation. |

**Model selection rationale:**

- **Morning briefing → Template (free):** Analysis showed that a well-designed template with data substitution (Section 8.1) produces output indistinguishable from Haiku for this feature. The template already references recovery scores, streaks, exams, and yesterday's performance. Save the API call -- use Haiku only as a fallback when the template logic hits an edge case it cannot handle (e.g., 3+ competing priorities that need triage).
- **Notification copy → Sonnet (upgraded from Haiku):** Haiku notification copy was tested and found to be repetitive after 2 weeks. Users see these notifications daily -- mediocre copy directly reduces engagement. Sonnet produces noticeably more varied, punchy, and contextually aware copy. The cost increase is marginal ($0.05/week → $0.18/week per user) because this is batched.
- **Pattern detection → Opus (upgraded from Sonnet):** Pattern detection is the "wow" feature that justifies the subscription. Opus catches subtle multi-variable interactions (e.g., "your Wednesday study focus drops specifically when Tuesday dinner was <2000 kcal AND bedtime was after midnight") that Sonnet misses. At 4 calls/month, the cost is ~$1.20/user/month -- justified by being the feature most likely to retain subscribers.

### 2.2 Per-Feature Configuration

| Feature | Model | Temperature | Max Input Tokens | Max Output Tokens | Streaming | Timeout | p95 Latency | UX During Wait |
|---------|-------|-------------|------------------|-------------------|-----------|---------|-------------|----------------|
| Morning Briefing | Template (free) | N/A | N/A | N/A | No | 0s | <10ms | Instant |
| Weekly Report | Sonnet 4.6 | 0.4 | 4,000 | 2,000 | Yes | 30s | ~8s | Stream sections progressively |
| Pattern Detection | Opus 4.6 | 0.3 | 6,000 | 1,500 | No | 60s | ~15s | Background job, push when ready |
| Training Program | Sonnet 4.6 | 0.3 | 3,000 | 2,500 | No | 30s | ~10s | Background job, push when ready |
| Training Adjustment | Haiku 4.5 | 0.3 | 1,500 | 500 | No | 5s | ~1.5s | Skeleton loader on workout card |
| Recovery Prescription | Haiku 4.5 | 0.2 | 1,200 | 400 | No | 5s | ~1.2s | Skeleton loader on prescription card |
| Drill Sergeant Copy | Sonnet 4.6 | 0.8 | 2,000 | 1,500 | No | 15s | ~5s | N/A (batched, not user-facing) |
| Meal Timing Recs | Haiku 4.5 | 0.3 | 1,000 | 300 | No | 5s | ~1s | Skeleton loader |
| Study Schedule | Sonnet 4.6 | 0.3 | 2,500 | 1,500 | No | 20s | ~7s | Loading spinner with "Building your study plan..." |
| Achievement Copy | Haiku 4.5 | 0.9 | 800 | 200 | No | 5s | ~0.8s | Celebration animation covers latency |
| Dashboard Insights | Haiku 4.5 | 0.5 | 1,500 | 400 | No | 5s | ~1.2s | Shimmer placeholder on insight cards |
| Notification Batch | Sonnet 4.6 | 0.8 | 2,000 | 2,000 | No | 15s | ~6s | Background job (Sun + Wed night) |

**Temperature rationale:**
- `0.2-0.3` for prescriptions, programs, schedules -- these are quasi-medical or structural outputs where consistency and correctness matter. Lower variance.
- `0.4-0.5` for analysis and insights -- some creativity in phrasing, but grounded in data.
- `0.7-0.9` for motivational/drill-sergeant copy -- personality, variety, and punch matter. Users see these daily and repetition kills impact.

**Latency UX rules:**
- Any AI call with p95 > 3s MUST either: (a) run in background and push/cache when done, or (b) stream progressively, or (c) show a skeleton/shimmer loader. NEVER show a blank screen with a spinner for >2s.
- For user-initiated requests (on-demand pattern query, force regenerate), show "Analyzing your data..." with a progress indicator. Cancel button visible after 5s.

### 2.3 Retry Strategy

```
Retry Policy:
  max_retries: 2
  base_delay: 1000ms
  backoff_multiplier: 2.0
  max_delay: 8000ms
  retry_on:
    - HTTP 429 (rate limited) -- respect Retry-After header
    - HTTP 500, 502, 503, 529 (server errors)
    - Malformed JSON response (see below)
  do_not_retry:
    - HTTP 400 (bad request -- prompt issue, fix before retrying)
    - HTTP 401 (auth issue)
    - HTTP 404
    - Timeout (already waited long enough)

Malformed JSON retry strategy:
  When Claude returns invalid JSON (common failure mode: markdown wrapping, trailing commas, truncated output):
  1. First attempt: try to extract JSON from between first `{` and last `}` (or `[` / `]`)
  2. If extraction fails: retry with a SIMPLIFIED prompt that adds:
     "CRITICAL: Return ONLY valid JSON. No markdown, no code blocks, no explanatory text.
      Start your response with { and end with }."
  3. If second attempt also fails: use fallback (Section 8)
  4. Log the original malformed response for prompt debugging.

On final failure:
  → Fall back to algorithmic/template system (Section 8)
  → Log the failure to monitoring (include: feature, model, error type, attempt count)
  → Set feature_status = "degraded" in the response
  → Surface to user: "AI insights unavailable -- showing standard recommendations"
```

### 2.4 Circuit Breaker

Prevents cascading failures and wasted spend when Claude API is having issues.

```
Circuit Breaker Configuration:
  failure_threshold: 3          // failures within the window
  failure_window: 600s          // 10 minutes
  recovery_timeout: 1800s       // 30 minutes in open state
  half_open_max_requests: 2     // test requests when transitioning

States:
  CLOSED (normal):
    → All requests go to Claude API
    → Track failures in a sliding window
    → If 3 failures in 10 minutes → switch to OPEN

  OPEN (circuit broken):
    → ALL requests go directly to fallback (Section 8)
    → No API calls made (saves cost, reduces latency)
    → Surface banner: "AI insights temporarily unavailable. Showing standard recommendations."
    → After 30 minutes → switch to HALF_OPEN

  HALF_OPEN (testing):
    → Allow 2 test requests to Claude API
    → If both succeed → switch to CLOSED
    → If either fails → switch back to OPEN (reset 30-min timer)

Per-model circuit breakers:
  → Haiku and Sonnet/Opus have INDEPENDENT circuit breakers
  → Haiku failure does not disable Sonnet features, and vice versa
  → This prevents a Haiku outage from killing weekly reports

Monitoring:
  → Log every state transition with timestamp and trigger event
  → Alert (push to developer) on: CLOSED→OPEN transition
  → Track: total time in OPEN state per day, per model
```

### 2.5 API Client Configuration (Vapor Backend)

```swift
// AIService.swift -- Configuration Constants

struct AIConfig {
    // Models
    static let haikuModel = "claude-haiku-4-5-20250901"
    static let sonnetModel = "claude-sonnet-4-6-20250514"
    static let opusModel = "claude-opus-4-6-20250901"

    // Budget
    static let monthlyBudgetCents = 5000  // $50.00
    static let dailyPerUserLimit = 12     // max AI calls per user per day (reduced: morning briefing is now template)
    static let weeklyReportLimit = 3      // per user per day
    static let patternAnalysisLimit = 2   // per user per day (Opus is expensive)

    // Retry
    static let maxRetries = 2
    static let baseRetryDelay: TimeInterval = 1.0
    static let backoffMultiplier: Double = 2.0

    // Timeouts
    static let haikuTimeout: TimeInterval = 5.0
    static let sonnetTimeout: TimeInterval = 30.0
    static let opusTimeout: TimeInterval = 60.0

    // Circuit Breaker
    static let circuitBreakerFailureThreshold = 3
    static let circuitBreakerFailureWindow: TimeInterval = 600  // 10 min
    static let circuitBreakerRecoveryTimeout: TimeInterval = 1800  // 30 min
}
```

---

## 3. Prompt Templates

### 3.1 Morning Briefing

**Purpose:** 3-5 sentence daily briefing delivered as a push notification and shown on dashboard. Drill-sergeant tone. Covers recovery, today's plan, streak status, and one motivational hook.

**Model:** Template-based (free). See Section 8.1 for the template engine. Haiku 4.5 is used ONLY as a fallback when the template encounters an edge case it cannot handle (3+ competing priorities requiring triage). In practice, this saves ~30 API calls/month per user.

**When Haiku fallback activates:**
**Temperature:** 0.7
**Max Output Tokens:** 300

#### System Prompt (for Haiku fallback only)

```
You are a no-nonsense drill sergeant and performance coach inside the Tempo app. You deliver a daily morning briefing to a university student-athlete who tracks fitness, nutrition, study sessions, and daily habits.

<tone>
- Direct and commanding. Short sentences. No fluff.
- Specific -- reference exact numbers, specific workouts, specific subjects from the provided data.
- Motivating through accountability, not cheerfulness. You hold a high standard.
- You use occasional intensity ("Let's go.", "No excuses.", "Handle your business.") but never cruelty.
- When recovery is low, you are protective ("Your body is rebuilding. Honor it.") not dismissive.
- When streaks are at risk, you invoke pride in the streak.
- When exams are close, academics take priority over training.
</tone>

<rules>
- Output ONLY the briefing text. No greetings, no sign-offs, no labels, no preamble.
- 3-5 sentences maximum. Aim for 40-60 words.
- Always mention the recovery score and what it means for today.
- Always mention the most important non-negotiable.
- If there is an exam within 7 days, lead with academics.
- If yesterday was a miss (<75% completion), acknowledge it and demand better.
- If there is a streak milestone today, celebrate it briefly then move forward.
- Never use emojis.
- NEVER give medical advice. You are a coach, not a doctor. Do not mention doctors, physicians, or diagnoses.
- NEVER suggest extreme caloric restriction, training through injury or pain, or skipping meals.
- ONLY reference numbers and facts from the <data> section below. Do not invent statistics, dates, or context.
</rules>
```

#### User Prompt Template

```
<data>
TODAY'S DATA:
- Date: {{date}} ({{day_of_week}})
- Recovery: {{recovery_score}}% ({{recovery_zone}})
- HRV: {{hrv}}ms ({{hrv_trend}} vs 7-day avg of {{hrv_7day_avg}}ms)
- Sleep: {{sleep_hours}}h (score: {{sleep_score}}%)
- Resting HR: {{resting_hr}}bpm

TODAY'S PLAN:
- Workout: {{workout_type}} (adjusted to {{recovery_adjustment}}% volume)
- Non-negotiables: {{non_negotiables_list}}
- Study target: {{study_target_minutes}} min{{exam_context}}
- Meals planned: {{meals_planned}}

CONTEXT:
- Current streak: {{streak_days}} days
- Yesterday's completion: {{yesterday_completion_pct}}% ({{yesterday_completed}}/{{yesterday_total}} tasks)
- Week so far: {{week_avg_score}}/100
{{#if streak_milestone}}- STREAK MILESTONE: Day {{streak_days}}{{/if}}
{{#if exam_approaching}}- EXAM: {{exam_name}} in {{exam_days_away}} days{{/if}}
{{#if previous_day_bad_sleep}}- NOTE: Bad sleep last night ({{sleep_hours}}h, score {{sleep_score}}%){{/if}}
</data>

Generate the morning briefing. Use ONLY the data above. Do not reference any information not provided.
```

#### Example Populated Prompt

```
TODAY'S DATA:
- Date: 2026-03-24 (Monday)
- Recovery: 72% (yellow)
- HRV: 58ms (down vs 7-day avg of 65ms)
- Sleep: 6.8h (score: 74%)
- Resting HR: 62bpm

TODAY'S PLAN:
- Workout: Push (adjusted to 80% volume)
- Non-negotiables: Study 2h, Train, 4 meals, Log all meals
- Study target: 120 min
- Meals planned: 4

CONTEXT:
- Current streak: 14 days
- Yesterday's completion: 100% (4/4 tasks)
- Week so far: 0/100 (Monday, fresh start)
- EXAM: Anatomy in 12 days

Generate the morning briefing.
```

#### Expected Output

```
New week. Recovery at 72% -- yellow zone, so Push day is dialed back to 80% volume. Maintain intensity on compounds, cut the isolation fluff. Anatomy exam in 12 days: 2 hours of study is non-negotiable. Yesterday was clean. 14-day streak on the line. Monday sets the tone. Set it right.
```

#### Response Parsing

The response is plain text. No JSON parsing needed. Trim whitespace. Validate:
- Length: 20-80 words. If under 20, regenerate. If over 80, truncate at last complete sentence.
- Content check: must mention a number (recovery score, streak, study target, etc.). If purely generic, regenerate.
- Rejection: if response contains medical advice ("see a doctor", "consult a physician"), strip that sentence and use the rest.

---

### 3.2 Weekly Report Analysis

**Purpose:** Comprehensive weekly analysis with structured sections covering all four quadrants (Body, Fuel, Mind, Move), AI insights, action items, and week-over-week deltas.

**Model:** Sonnet 4.6
**Temperature:** 0.4
**Max Output Tokens:** 2,000

#### System Prompt

```
You are an elite performance analyst inside the Tempo app. You analyze one week of biometric, nutrition, academic, and fitness data for a university student-athlete. Your analysis powers a weekly report that the user reads every Sunday evening.

<responsibilities>
1. Provide a one-line title (max 60 chars) summarizing the week's dominant theme.
2. Write a 2-3 sentence executive summary.
3. Write analysis sections for each domain: Recovery & Sleep, Fitness, Nutrition, Academics. Each section should be 2-4 sentences with specific numbers, dates, and comparisons.
4. Identify 3 actionable recommendations that are specific, measurable, and tied to patterns in the data.
5. Compute week-over-week comparison deltas for key metrics.
</responsibilities>

<tone>
- Analytical and precise. Reference specific days, numbers, and trends.
- Encouraging but honest. If something is declining, say so directly.
- Never alarmist. A bad week is data, not a crisis.
- Use the drill-sergeant tone only for action items ("Set a bedtime alarm" not "Consider setting a bedtime alarm").
- Do not use emojis.
</tone>

<rules>
- CRITICAL: Every number you cite MUST come from the <week_data> section in the user message. Do NOT fabricate, estimate, or round numbers that are not in the data.
- If a data domain has fewer than 3 days of data, note that the analysis is limited and skip that section's sentiment rating.
- For sentiment, use: "positive" (on track or improving), "warning" (declining or below target), "negative" (significantly below target or multi-day decline).
- Action items must be immediately actionable. Not "improve sleep" but "Set a bedtime alarm for 23:30 on weeknights."
- Each section MUST reference at least one specific day by name (e.g., "Thursday").
- For the SF Symbol icon names, use ONLY these: "bed.double.fill" (recovery/sleep), "flame.fill" (fitness), "fork.knife" (nutrition), "book.fill" (academics). No other icon values are valid.
- Output ONLY valid JSON matching the schema. No markdown code blocks, no explanatory text before or after the JSON. Start with { and end with }.
- NEVER give medical advice, suggest supplements, or recommend caloric intake below 1,500 kcal.
- NEVER suggest training through pain or injury.
</rules>

<bad_output_example>
This output would be REJECTED:
{
  "title": "Good week overall with some areas to improve",
  "summary": "You had a productive week with consistent training.",
  "sections": [
    {"title": "Recovery & Sleep", "icon": "moon.fill", "body": "Sleep was decent this week. Try to get more rest.", "sentiment": "positive"}
  ],
  "action_items": ["Sleep better", "Eat more protein", "Study harder"]
}
REASONS: Title is vague. Summary cites no numbers. Icon "moon.fill" is not in the allowed list. Section body references no specific days or numbers. Action items are generic and not actionable.
</bad_output_example>
```

#### User Prompt Template

```
Analyze this week's data and generate the weekly report. Reference ONLY the data provided in <week_data>. Do not fabricate any numbers.

<week_data>
<user_context>
- Timezone: {{timezone}}
- Current streak: {{streak_days}} days
- Level: {{level}} ({{xp_total}} XP)
- Active goals: {{active_goals}}
</user_context>

<period>{{week_start}} to {{week_end}}</period>

<recovery source="whoop">
{{#each day in recovery_data}}
- {{day.date}} ({{day.day_name}}): Recovery {{day.score}}%, HRV {{day.hrv}}ms, RHR {{day.rhr}}bpm
{{/each}}
</recovery>

<sleep source="whoop">
{{#each day in sleep_data}}
- {{day.date}} ({{day.day_name}}): {{day.duration_hours}}h, Performance {{day.performance}}%, Efficiency {{day.efficiency}}%, Bedtime {{day.bedtime}}, Wake {{day.wake_time}}
{{/each}}
</sleep>

<workouts>
{{#each workout in workout_data}}
- {{workout.date}} ({{workout.day_name}}): {{workout.type}}, Strain {{workout.strain}}, {{workout.duration_min}}min, Avg HR {{workout.avg_hr}}, Max HR {{workout.max_hr}}
{{/each}}
</workouts>

<nutrition source="nutritrack">
{{#each day in nutrition_data}}
- {{day.date}} ({{day.day_name}}): {{day.calories}}kcal / {{day.target_calories}} target, Protein {{day.protein}}g / {{day.target_protein}}g, Carbs {{day.carbs}}g, Fat {{day.fat}}g, Meals logged: {{day.meals_logged}} / {{day.meals_planned}}
{{/each}}
</nutrition>

<study_sessions>
{{#each session in study_data}}
- {{session.date}} ({{session.day_name}}): {{session.minutes}}min, Subject: {{session.subject}}, Self-rated focus: {{session.focus_rating}}/5
{{/each}}
</study_sessions>

<accountability>
{{#each day in accountability_data}}
- {{day.date}}: {{day.completed}}/{{day.total}} non-negotiables, Score: {{day.daily_score}}/100
{{/each}}
</accountability>

<previous_week_averages>
- Recovery: {{prev.avg_recovery}}%
- HRV: {{prev.avg_hrv}}ms
- Sleep duration: {{prev.avg_sleep_hours}}h
- Sleep performance: {{prev.avg_sleep_performance}}%
- Workouts completed: {{prev.workout_count}}
- Avg daily calories: {{prev.avg_calories}}
- Protein adherence: {{prev.protein_adherence_pct}}% of days hitting target
- Study minutes/day: {{prev.avg_study_minutes}}
- Non-negotiable completion: {{prev.avg_completion_pct}}%
- Weekly XP: {{prev.weekly_xp}}
</previous_week_averages>
</week_data>

<output_schema>
Respond with ONLY a JSON object (no markdown, no code blocks) matching this exact schema:
{
  "title": "string (max 60 chars)",
  "summary": "string (2-3 sentences)",
  "sections": [
    {
      "title": "Recovery & Sleep" | "Fitness" | "Nutrition" | "Academics",
      "icon": "bed.double.fill" | "flame.fill" | "fork.knife" | "book.fill",
      "body": "string (2-4 sentences with specific data references)",
      "sentiment": "positive" | "warning" | "negative"
    }
  ],
  "action_items": ["string (exactly 3 items, each immediately actionable with specific numbers/days)"],
  "compared_to_last_week": {
    "recovery_avg_change": number,
    "sleep_avg_change_min": number,
    "workout_count_change": number,
    "xp_change": number,
    "protein_adherence_change": number,
    "study_avg_change_min": number,
    "completion_pct_change": number
  }
}
</output_schema>
```

#### Example Populated Prompt

```
Analyze this week's data and generate the weekly report.

USER CONTEXT:
- Timezone: America/New_York
- Current streak: 14 days
- Level: 8 (3,450 XP)
- Active goals: Hit 180g protein daily, Study 2h/day, Sleep 7.5h/night

THIS WEEK (2026-03-18 to 2026-03-24):

RECOVERY (from Whoop):
- 2026-03-18 (Mon): Recovery 81%, HRV 68ms, RHR 58bpm
- 2026-03-19 (Tue): Recovery 74%, HRV 63ms, RHR 60bpm
- 2026-03-20 (Wed): Recovery 85%, HRV 72ms, RHR 57bpm
- 2026-03-21 (Thu): Recovery 58%, HRV 52ms, RHR 63bpm
- 2026-03-22 (Fri): Recovery 62%, HRV 55ms, RHR 62bpm
- 2026-03-23 (Sat): Recovery 79%, HRV 66ms, RHR 59bpm
- 2026-03-24 (Sun): Recovery 72%, HRV 60ms, RHR 61bpm

SLEEP (from Whoop):
- 2026-03-18 (Mon): 7.5h, Performance 82%, Efficiency 91%, Bedtime 23:15, Wake 06:45
- 2026-03-19 (Tue): 6.2h, Performance 68%, Efficiency 85%, Bedtime 01:10, Wake 07:20
- 2026-03-20 (Wed): 8.1h, Performance 92%, Efficiency 94%, Bedtime 22:45, Wake 06:50
- 2026-03-21 (Thu): 5.8h, Performance 61%, Efficiency 82%, Bedtime 01:30, Wake 07:18
- 2026-03-22 (Fri): 6.5h, Performance 72%, Efficiency 87%, Bedtime 00:30, Wake 07:00
- 2026-03-23 (Sat): 7.8h, Performance 85%, Efficiency 92%, Bedtime 23:00, Wake 06:48
- 2026-03-24 (Sun): 7.0h, Performance 78%, Efficiency 89%, Bedtime 23:30, Wake 06:30

WORKOUTS:
- 2026-03-18 (Mon): Push, Strain 12.4, 58min, Avg HR 142, Max HR 172
- 2026-03-19 (Tue): Football Practice, Strain 14.1, 90min, Avg HR 155, Max HR 186
- 2026-03-20 (Wed): Pull, Strain 11.8, 52min, Avg HR 138, Max HR 168
- 2026-03-22 (Fri): Legs, Strain 13.2, 62min, Avg HR 148, Max HR 178
- 2026-03-23 (Sat): Run (5K), Strain 9.1, 26min, Avg HR 162, Max HR 181

NUTRITION (from NutriTrack):
- 2026-03-18 (Mon): 2,340kcal / 2,400 target, Protein 185g / 180g, Carbs 268g, Fat 72g, Meals: 4/4
- 2026-03-19 (Tue): 2,180kcal / 2,400 target, Protein 172g / 180g, Carbs 252g, Fat 68g, Meals: 3/4
- 2026-03-20 (Wed): 2,420kcal / 2,400 target, Protein 192g / 180g, Carbs 275g, Fat 74g, Meals: 4/4
- 2026-03-21 (Thu): 1,950kcal / 2,400 target, Protein 155g / 180g, Carbs 230g, Fat 58g, Meals: 3/4
- 2026-03-22 (Fri): 2,280kcal / 2,400 target, Protein 178g / 180g, Carbs 260g, Fat 70g, Meals: 4/4
- 2026-03-23 (Sat): 2,510kcal / 2,400 target, Protein 188g / 180g, Carbs 290g, Fat 80g, Meals: 4/4
- 2026-03-24 (Sun): 2,100kcal / 2,400 target, Protein 168g / 180g, Carbs 245g, Fat 62g, Meals: 3/4

STUDY SESSIONS:
- 2026-03-18 (Mon): 135min, Subject: Calculus II, Focus: 4/5
- 2026-03-19 (Tue): 90min, Subject: Anatomy, Focus: 3/5
- 2026-03-20 (Wed): 150min, Subject: Calculus II, Focus: 5/5
- 2026-03-21 (Thu): 45min, Subject: Physics, Focus: 2/5
- 2026-03-22 (Fri): 120min, Subject: Anatomy, Focus: 4/5
- 2026-03-23 (Sat): 100min, Subject: Physics, Focus: 3/5
- 2026-03-24 (Sun): 80min, Subject: Calculus II, Focus: 4/5

ACCOUNTABILITY:
- 2026-03-18: 4/4 non-negotiables, Score: 88/100
- 2026-03-19: 3/4 non-negotiables, Score: 72/100
- 2026-03-20: 4/4 non-negotiables, Score: 95/100
- 2026-03-21: 2/4 non-negotiables, Score: 52/100
- 2026-03-22: 4/4 non-negotiables, Score: 82/100
- 2026-03-23: 4/4 non-negotiables, Score: 85/100
- 2026-03-24: 3/4 non-negotiables, Score: 74/100

LAST WEEK AVERAGES (for comparison):
- Recovery: 81%
- HRV: 68ms
- Sleep duration: 7.5h
- Sleep performance: 84%
- Workouts completed: 5
- Avg daily calories: 2,350
- Protein adherence: 86% of days hitting target
- Study minutes/day: 130
- Non-negotiable completion: 89%
- Weekly XP: 680

Respond with a JSON object matching this schema:
{
  "title": "string (max 60 chars)",
  "summary": "string (2-3 sentences)",
  "sections": [...],
  "action_items": ["string"],
  "compared_to_last_week": {...}
}
```

#### Expected Output

```json
{
  "title": "Strong consistency, sleep needs attention",
  "summary": "You maintained your 14-day streak and hit protein targets on 4 of 7 days. Recovery averaged 73% -- down from 81% last week. The main driver is sleep: you averaged 7.0 hours vs your 7.5h target, with notably late bedtimes on Tuesday and Thursday dragging HRV down.",
  "sections": [
    {
      "title": "Recovery & Sleep",
      "icon": "bed.double.fill",
      "body": "Average recovery dropped 8 points to 73% this week. HRV declined from 68ms to 62ms, with Thursday's 52ms being your weekly low. The pattern is clear: Tuesday and Thursday, you went to bed after 1 AM, and recovery the next morning was 58% and 62% respectively. Wednesday, after a 22:45 bedtime, you hit 85% recovery -- your best day. Sleep efficiency ranged from 82-94%, so the issue is duration, not quality.",
      "sentiment": "warning"
    },
    {
      "title": "Fitness",
      "icon": "flame.fill",
      "body": "5 sessions this week with solid strain diversity: two strength days (Push/Pull at strain 11-12), Legs at 13.2, football practice at 14.1, and a 5K run. Your running pace is consistent and strength sessions are well-balanced. Thursday was a rest day, which made sense given the 58% recovery. No missed training days.",
      "sentiment": "positive"
    },
    {
      "title": "Nutrition",
      "icon": "fork.knife",
      "body": "Protein target of 180g was hit on 4 of 7 days (57%), down from 86% last week. The misses were Tuesday (172g), Thursday (155g), and Sunday (168g) -- all days where you logged only 3 of 4 meals. Thursday was the worst: 1,950 kcal with only 155g protein. When you log all 4 meals, you hit your protein target every time.",
      "sentiment": "warning"
    },
    {
      "title": "Academics",
      "icon": "book.fill",
      "body": "10 hours 20 minutes of total study across 7 sessions. Wednesday was your peak: 2.5 hours of Calculus II with a perfect 5/5 focus rating. Thursday was the low point at 45 minutes with 2/5 focus -- this followed the 1:30 AM bedtime. Average daily study was 89 minutes vs your 120-minute target, meaning you fell short 4 of 7 days.",
      "sentiment": "warning"
    }
  ],
  "action_items": [
    "Set a hard bedtime alarm for 23:30 on Tuesday and Thursday nights. Both late nights directly caused your two worst recovery scores and your worst study day.",
    "On days where you train, pre-prepare meal 4. Your protein misses all happened on 3-meal days. A ready-to-eat protein source (shake, yogurt) would close the gap.",
    "Thursday's 45-minute study session at 2/5 focus was your worst of the week. After a 1:30 AM bedtime, your brain was offline. Protecting sleep IS protecting study time."
  ],
  "compared_to_last_week": {
    "recovery_avg_change": -8,
    "sleep_avg_change_min": -30,
    "workout_count_change": 0,
    "xp_change": -35,
    "protein_adherence_change": -29,
    "study_avg_change_min": -41,
    "completion_pct_change": -6
  }
}
```

#### Parsing Strategy

1. Parse response as JSON. If parsing fails, attempt to extract JSON from between `{` and `}` (Claude sometimes wraps in markdown code blocks despite instructions).
2. Validate required fields: `title`, `summary`, `sections` (array of 4), `action_items` (array of 3), `compared_to_last_week`.
3. Validate each section has `title`, `icon`, `body`, `sentiment`.
4. Validate `sentiment` is one of `positive`, `warning`, `negative`.
5. Validate `icon` is one of the allowed SF Symbols.
6. If validation fails on any field, regenerate once. If second attempt fails, use fallback template (Section 8).

#### Quality Guardrails

- **Reject if:** response mentions data not provided (hallucination). Check: any specific number in the response that does not appear in the input data is a red flag. Log for review.
- **Reject if:** all four sections have `sentiment: "positive"` when accountability score averaged below 70. The model is being too nice.
- **Reject if:** action items are generic ("improve your sleep", "eat better"). Each must reference a specific day, number, or behavior from the data.
- **Truncate if:** `title` exceeds 60 characters. Cut at the last space before 60 chars and add "...".

---

### 3.3 Pattern Detection

**Purpose:** Analyze 30-90 days of data to find statistically meaningful correlations and behavioral patterns. Powers the Pattern View in the dashboard. This is the highest-value AI feature in Tempo -- the one most likely to produce "I had no idea" moments that justify the subscription.

**Model:** Opus 4.6
**Temperature:** 0.3
**Max Output Tokens:** 1,500

#### System Prompt

```
You are a data scientist specializing in behavioral pattern detection for a health and performance app. You receive compressed multi-week data and pre-computed statistics from a university student-athlete. Your job is to find statistically meaningful patterns and cross-domain correlations that the user would not notice on their own.

<responsibilities>
1. Identify correlations between variables across domains (sleep vs recovery, workouts vs study, nutrition vs energy, day-of-week effects, etc.)
2. Detect behavioral patterns: "When X happens, Y tends to follow within N days"
3. Find multi-variable interactions: "When A AND B both occur, C is dramatically affected"
4. Quantify each pattern with a confidence score and occurrence count
5. Provide one actionable recommendation per pattern
</responsibilities>

<rules>
- Only report patterns with at least 5 occurrences in the dataset.
- Only report correlations where the pre-computed |r| >= 0.5 (moderate or stronger). Do NOT compute your own correlations -- use the values provided in <precomputed_correlations>.
- Report a maximum of 6 patterns, ranked by confidence.
- Be precise about causality: say "correlates with" or "is followed by", NEVER "causes".
- Every pattern MUST include the exact average values for both conditions, derived from the provided data.
- Output ONLY valid JSON. No markdown wrapping, no code blocks, no text before or after. Start with { and end with }.
- NEVER invent data points, averages, or occurrences. If a number does not come from the provided <daily_data> or <precomputed_stats>, do not cite it.
- If there is insufficient data for a category (<14 days), explicitly note this in data_quality and skip patterns for that category.
- Minimum data requirement: 14 days total. If fewer, return: {"error": "insufficient_data", "days_provided": N, "minimum_required": 14}
- NEVER give medical advice. Recommendations should be behavioral (sleep, timing, scheduling), never medical.
</rules>

<bad_pattern_example>
REJECTED: {"trigger": "High stress levels", "outcome": "Recovery drops"} -- "stress levels" is not a tracked metric. Only reference metrics in the data.
REJECTED: {"trigger": "Sleep < 7h", "confidence": 0.95, "occurrences": 3} -- 3 occurrences is below the minimum of 5.
REJECTED: {"trigger": "Protein > 180g", "outcome": "Recovery improves by ~15%"} -- "~15%" is vague. Use exact averages from the data.
</bad_pattern_example>
```

#### User Prompt Template

```
Analyze this data for behavioral patterns and correlations. Use ONLY the data provided below. Do not fabricate any statistics.

<data_period>{{start_date}} to {{end_date}} ({{total_days}} days)</data_period>

<daily_data format="pipe-delimited">
{{#each day in daily_data}}
{{day.date}}|rec:{{day.recovery}}|hrv:{{day.hrv}}|sleep:{{day.sleep_hours}}|slp_score:{{day.sleep_score}}|bedtime:{{day.bedtime_hour}}|strain:{{day.strain}}|workout:{{day.workout_type}}|cal:{{day.calories}}|cal_tgt:{{day.cal_target}}|protein:{{day.protein}}|prot_tgt:{{day.protein_target}}|meals:{{day.meals_logged}}|study:{{day.study_min}}|study_tgt:{{day.study_target}}|focus:{{day.avg_focus}}|nn_pct:{{day.nn_completion_pct}}|score:{{day.daily_score}}
{{/each}}
</daily_data>

<precomputed_stats>
- Recovery: {{avg_recovery}}% (std: {{std_recovery}})
- Sleep: {{avg_sleep}}h (std: {{std_sleep}})
- HRV: {{avg_hrv}}ms (std: {{std_hrv}})
- Daily calories: {{avg_calories}} (target: {{cal_target}})
- Daily protein: {{avg_protein}}g (target: {{protein_target}}g)
- Daily study: {{avg_study}}min (target: {{study_target}}min)
- Non-neg completion: {{avg_nn_pct}}%
</precomputed_stats>

<precomputed_correlations note="Pearson r, computed server-side. Use these values, do not recompute.">
{{#each corr in correlations}}
- {{corr.var_a}} vs {{corr.var_b}}: r = {{corr.r}} (n = {{corr.n}})
{{/each}}
</precomputed_correlations>

Return patterns as JSON (no markdown wrapping, start with {):
{
  "patterns": [
    {
      "id": "string (unique pattern identifier)",
      "type": "correlation" | "behavioral" | "temporal",
      "trigger": "string (the condition, e.g. 'Sleep < 6.5 hours')",
      "outcome": "string (what happens, e.g. 'Next-day recovery drops to 42% avg')",
      "confidence": number (0.0 to 1.0),
      "occurrences": number,
      "avg_when_true": {"metric": number},
      "avg_when_false": {"metric": number},
      "recommendation": "string (one specific action)",
      "correlation_r": number | null (if type == "correlation")
    }
  ],
  "data_quality": {
    "total_days": number,
    "days_with_recovery": number,
    "days_with_nutrition": number,
    "days_with_study": number,
    "sufficient_for_analysis": boolean
  },
  "top_insight": "string (the single most important finding in plain language)"
}
```

#### Data Compression Strategy

To fit 90 days of data into the context window, each day is compressed into a single pipe-delimited line. This format uses approximately 150-180 characters per day, allowing 90 days in ~16,000 characters (~4,000 tokens). With the system prompt, user prompt template, and computed averages, total input stays under 6,000 tokens.

**Pre-computed correlations** are calculated server-side using Pearson r before sending to Claude. This serves two purposes:
1. Claude validates and interprets the correlations rather than computing them (reducing hallucination risk).
2. The server can cross-check Claude's output against the actual computed values.

#### Minimum Data Requirements

| Data Source | Minimum Days | Action if Below |
|-------------|-------------|-----------------|
| Recovery (Whoop) | 14 | Return "insufficient data" for recovery patterns |
| Sleep (Whoop) | 14 | Return "insufficient data" for sleep patterns |
| Nutrition (NutriTrack) | 14 | Return "insufficient data" for nutrition patterns |
| Study sessions | 10 | Return "insufficient data" for study patterns |
| Overall | 14 | Do not run analysis at all |

#### Expected Output (from example 52-day dataset)

```json
{
  "patterns": [
    {
      "id": "sleep_recovery_lag",
      "type": "correlation",
      "trigger": "Sleep performance > 85%",
      "outcome": "Next-day recovery averages 82%",
      "confidence": 0.84,
      "occurrences": 18,
      "avg_when_true": {"next_day_recovery": 82},
      "avg_when_false": {"next_day_recovery": 61},
      "recommendation": "Protect your sleep window. Every night above 85% sleep performance buys you a green recovery day.",
      "correlation_r": 0.82
    },
    {
      "id": "late_bedtime_study_impact",
      "type": "behavioral",
      "trigger": "Bedtime after 01:00",
      "outcome": "Next-day study time drops 45% and focus rating drops to 2.1/5 avg",
      "confidence": 0.78,
      "occurrences": 11,
      "avg_when_true": {"study_minutes": 52, "focus_rating": 2.1},
      "avg_when_false": {"study_minutes": 118, "focus_rating": 3.8},
      "recommendation": "Set a 1:00 AM hard stop on all screens. The study time you lose the next day exceeds whatever you gained staying up.",
      "correlation_r": null
    },
    {
      "id": "workout_study_boost",
      "type": "behavioral",
      "trigger": "Workout completed (any type)",
      "outcome": "Study time increases 22% and focus rating is 0.6 points higher",
      "confidence": 0.71,
      "occurrences": 28,
      "avg_when_true": {"study_minutes": 125, "focus_rating": 3.9},
      "avg_when_false": {"study_minutes": 98, "focus_rating": 3.3},
      "recommendation": "Schedule study sessions after training. Your data shows a consistent cognitive boost on workout days.",
      "correlation_r": null
    },
    {
      "id": "protein_recovery_link",
      "type": "correlation",
      "trigger": "Protein intake >= target (180g)",
      "outcome": "Next-day recovery averages 6 points higher",
      "confidence": 0.63,
      "occurrences": 22,
      "avg_when_true": {"next_day_recovery": 76},
      "avg_when_false": {"next_day_recovery": 70},
      "recommendation": "Hit your protein target every day, especially on training days. The recovery payoff is measurable.",
      "correlation_r": 0.58
    },
    {
      "id": "wednesday_weakness",
      "type": "temporal",
      "trigger": "Day of week = Wednesday",
      "outcome": "Workout strain averages 8.1 (lowest of all weekdays)",
      "confidence": 0.72,
      "occurrences": 7,
      "avg_when_true": {"strain": 8.1},
      "avg_when_false": {"strain": 11.8},
      "recommendation": "Your Wednesday sessions are consistently the weakest. This follows Tuesday nights, which are your worst sleep nights. Fix Tuesday bedtime to fix Wednesday training.",
      "correlation_r": null
    }
  ],
  "data_quality": {
    "total_days": 52,
    "days_with_recovery": 50,
    "days_with_nutrition": 48,
    "days_with_study": 45,
    "sufficient_for_analysis": true
  },
  "top_insight": "Your sleep is the single biggest lever in your system. Nights where sleep performance exceeds 85% lead to 82% recovery vs 61% on poor sleep nights -- a 21-point swing that cascades into better training, better study focus, and higher accountability scores."
}
```

---

### 3.4 Drill Sergeant Notification Copy (Batch)

**Purpose:** Pre-generate 3 days of notification copy for all 6 accountability channels. Two API calls per week (Sunday night for Mon-Wed, Wednesday night for Thu-Sat) produce the notification text, reducing daily API calls to 0 for notifications while keeping copy fresher than a 7-day batch.

**Why 3-day batches instead of 7:** A 7-day batch generates copy for Friday based on Sunday's context. By Thursday, the user may have changed their schedule, hit a PR, or bombed an exam. 3-day batches are 70% fresher with only 1 extra API call per week.

**Model:** Sonnet 4.6
**Temperature:** 0.8
**Max Output Tokens:** 2,000

**Why Sonnet instead of Haiku for notification copy:** Haiku notification copy was tested and found to produce repetitive sentence structures within 2 weeks. Users see these notifications every day -- mediocre copy directly kills engagement. Sonnet produces noticeably more varied phrasing, better contextual references, and more impactful drill-sergeant voice. The cost difference is small because this is batched (2 calls/week).

#### System Prompt

```
You are a drill sergeant personality engine for the Tempo app. You generate push notification copy for 3 days in one batch. The notifications escalate in intensity throughout each day, from gentle reminders to final warnings.

<channels>
1. MORNING_BRIEFING: Commanding, sets the day's agenda. 40-60 words.
2. GENTLE (2 PM): Firm but not aggressive. A check-in. 25-40 words.
3. FIRM (5 PM): Urgency rises. Reference remaining time. 25-40 words.
4. URGENT (6:30 PM): Direct confrontation with the gap. 30-50 words.
5. FINAL (30 min before evening): Last chance. Maximum intensity. 35-55 words.
6. ALL_CLEAR: Earned celebration. Respect, not excitement. 25-40 words.
</channels>

<rules>
- Use the user's actual task names, friend names, exam names, and streak count from the provided <context>.
- Reference specific times of day, specific workout types, specific subjects.
- NEVER use emojis.
- NEVER give medical advice, suggest supplements, or reference body appearance.
- NEVER use language that is cruel, shaming, or attacks the person (attack the behavior, not the person).
- Vary the phrasing day to day. Do not repeat the same sentence structure across days. Each day should feel distinct.
- Monday copy should reference "new week" energy.
- Weekend copy should acknowledge it's a weekend but maintain standards.
- If an exam is approaching, academics dominate the copy.
- If a streak milestone falls within the batch period, reference it on that day.
- The ALL_CLEAR message should contrast with the day's difficulty (red recovery = extra praise for completing, early completion = praise for discipline).
- Output ONLY valid JSON. No markdown wrapping. Start with { and end with }.
- ONLY reference information provided in <context>. Do not invent friend names, exam names, or task names.
</rules>
```

#### User Prompt Template

```
Generate notification copy for the next 3 days. Use ONLY information from <context>. Do not invent names, events, or data.

<context>
<user_profile>
- Name: {{first_name}}
- Current streak: {{streak_days}} days (milestone on {{milestone_day}} if applicable)
- Non-negotiables: {{non_negotiables_list}}
- Notification intensity: {{intensity}} (drill_sergeant | savage | firm | gentle)
- Time-waster: {{time_waster}} (PS5 | social_media | netflix | gaming | none)
- Evening start time: {{evening_time}}
- Study target: {{study_target_min}} min/day
- Meal target: {{meal_count}} meals/day
</user_profile>

<schedule days="3">
{{#each day in batch_schedule}}
- {{day.date}} ({{day.day_name}}): Workout: {{day.workout_type}}, Football: {{day.has_football}}, Expected recovery: {{day.expected_recovery_zone}}
{{/each}}
</schedule>

<upcoming_events>
{{#each event in events}}
- {{event.type}}: {{event.name}} on {{event.date}} ({{event.days_away}} days)
{{/each}}
</upcoming_events>

<arena>
{{#if has_friends}}
- Top rival: {{rival_name}} ({{rival_weekly_xp}} XP this week)
- Your XP this week: {{user_weekly_xp}}
{{/if}}
{{#if active_challenge}}
- Active challenge: {{challenge_name}} ({{challenge_metric}}, you: {{user_score}}, leader: {{leader_name}} at {{leader_score}})
{{/if}}
</arena>

<recent_performance>
- Last week completion rate: {{last_week_completion}}%
- Worst day last week: {{worst_day}} ({{worst_day_score}}/100)
- Best day last week: {{best_day}} ({{best_day_score}}/100)
</recent_performance>
</context>

<output_schema>
Return ONLY valid JSON (no markdown, start with {):
{
  "batch_start": "YYYY-MM-DD",
  "days": [
    {
      "date": "YYYY-MM-DD",
      "day_name": "string",
      "morning_briefing": "string (40-60 words)",
      "gentle_2pm": "string (25-40 words)",
      "firm_5pm": "string (25-40 words)",
      "urgent_630pm": "string (30-50 words)",
      "final_warning": "string (35-55 words)",
      "all_clear": "string (25-40 words)"
    }
  ]
}
</output_schema>

Each notification is the BODY text only (title is always "TEMPO", subtitle is the channel name). Generate for all 3 days.
```

#### Example Output (Monday only, abbreviated)

```json
{
  "week_start": "2026-03-25",
  "days": [
    {
      "date": "2026-03-25",
      "day_name": "Monday",
      "morning_briefing": "New week. Last week you scored 82/100. This week we're pushing 90. Push day today, 2h study for Anatomy, 4 meals. Marco is 45 XP ahead on the leaderboard. Monday sets the tone. Set it right.",
      "gentle_2pm": "Afternoon. Study timer shows zero. Training not started. You've got 5 hours of daylight left. That's more than enough for a full day. Start with 25 minutes of Anatomy. Go.",
      "firm_5pm": "5 PM. Two tasks still open. Study is at 30 of 120 minutes. Push day hasn't happened. Marco just logged a workout. The gap is growing. Move now or explain to yourself later why you didn't.",
      "urgent_630pm": "6:30. Study at 45 minutes. That's 75 minutes short. Push day still not done. This is the part where most people fold. You're not most people. Timer on. Books open. NOW.",
      "final_warning": "Last call. 30 minutes until evening. Study is 80 minutes short. If you sit down right now and work until 8 PM, you can still salvage this day. Or you can let Monday set a losing tone for the whole week. Choose.",
      "all_clear": "All clear. Every non-negotiable handled on a Monday. That's how you start a week. Marco's lead just got smaller. Enjoy your evening -- you built it the right way."
    }
  ]
}
```

#### Runtime Notification Selection

When a notification channel fires (e.g., 2 PM gentle reminder), the backend:

1. Loads the pre-generated copy for today's date and channel.
2. Checks actual real-time data: how many tasks are actually incomplete?
3. If the pre-generated copy references a task that is already done (e.g., "Training not started" but user trained at noon), **discard the pre-generated copy** and fall back to a lightweight Haiku call or template substitution.
4. If the pre-generated copy is still accurate, use it directly.

This two-tier system means most days use zero real-time AI calls for notifications (the batch handles it), but accuracy is never sacrificed.

---

### 3.5 Training Program Generation

**Purpose:** Generate a weekly workout program adapted to the user's recovery trends, schedule constraints, equipment, goals, and training history.

**Model:** Sonnet 4.6
**Temperature:** 0.3
**Max Output Tokens:** 2,500

#### System Prompt

```
You are an expert strength and conditioning coach with deep knowledge of exercise science, periodization, and recovery-based programming. You design weekly training programs for a university student-athlete inside the Tempo app.

<rules>
- ONLY use exercises from the <exercise_library> provided in the user message. Do NOT invent exercises.
- NEVER suggest training through pain or injury.
- NEVER recommend supplements, drugs, or extreme caloric restriction.
- Output ONLY valid JSON matching the schema. No markdown, no code blocks. Start with { and end with }.
- All weight recommendations must be based on the user's <training_history> and <overload_candidates>. Do not guess weights.
</rules>

Programming principles:
1. Recovery dictates intensity. Green (67-100%) = full volume, push for PRs. Yellow (34-66%) = reduce volume 20%, maintain intensity. Red (<34%) = reduce both 30-40%, or swap to mobility.
2. NEVER program heavy legs (squats, deadlifts, lunges) the day before football practice.
3. NEVER program any training on football practice days (football IS the training).
4. Progressive overload: increase weight by 2.5kg on compounds when the user hits all prescribed reps for 2 consecutive sessions.
5. Rest days are strategic. At least 1 full rest day per week. If recovery is red 2+ consecutive days, insert an extra rest day.
6. Compound movements come first, isolation movements after. Always.
7. Every session should have a warmup prescription (5 min) and cooldown (stretching, 3 min).
8. Supersets are acceptable for time efficiency but never superset two heavy compounds.
9. RPE (Rate of Perceived Exertion) targets: Green day = RPE 8-9. Yellow day = RPE 7-8. Red day = RPE 5-6.

Output format: JSON matching the schema below exactly. Use only exercises from the provided exercise library. Do not invent exercises.
```

#### User Prompt Template

```
Generate a 7-day training program for this week. Use ONLY exercises from the <exercise_library>. Base all weights on <training_history> and <overload_candidates>.

<user_profile>
- Training split preference: {{split_type}} (PPL | Upper/Lower | Full Body | Bro Split)
- Training experience: {{experience_level}} (beginner | intermediate | advanced)
- Available equipment: {{equipment_list}}
- Training days per week target: {{training_days}}
- Session duration preference: {{session_duration_min}} minutes
- Goals: {{training_goals}}
</user_profile>

<recovery_data period="last_7_days">
{{#each day in recovery_data}}
- {{day.date}} ({{day.day_name}}): Recovery {{day.score}}% ({{day.zone}})
{{/each}}
Trend: {{recovery_trend}} (improving | stable | declining)
Predicted next 3 days: {{predicted_recovery}}
</recovery_data>

<schedule_constraints>
{{#each constraint in schedule}}
- {{constraint.date}} ({{constraint.day_name}}): {{constraint.type}}
{{/each}}
</schedule_constraints>

<training_history recent="4_sessions">
{{#each session in recent_sessions}}
- {{session.date}}: {{session.type}} -- {{session.exercises_summary}} -- Volume: {{session.total_sets}} sets, Avg RPE: {{session.avg_rpe}}
{{/each}}
</training_history>

<exercise_library>
{{exercise_library_json}}
</exercise_library>

<overload_candidates note="exercises where user hit all reps last 2 sessions">
{{#each exercise in overload_candidates}}
- {{exercise.name}}: Current weight {{exercise.current_weight}}kg, recommend {{exercise.next_weight}}kg
{{/each}}
</overload_candidates>

Generate the 7-day program as JSON:
{
  "week_start": "YYYY-MM-DD",
  "program_summary": "string (1-2 sentences describing the week's focus)",
  "days": [
    {
      "date": "YYYY-MM-DD",
      "day_name": "string",
      "type": "push" | "pull" | "legs" | "upper" | "lower" | "full_body" | "football" | "run" | "mobility" | "rest",
      "recovery_adjustment": number (0.0 to 1.2, where 1.0 = normal),
      "duration_estimate_min": number,
      "warmup": "string (warmup prescription)",
      "exercises": [
        {
          "name": "string (must match exercise library)",
          "sets": number,
          "reps": "string (e.g., '8-10' or '5' or '12,10,8')",
          "weight_kg": number | null (null for bodyweight),
          "rpe_target": number,
          "rest_seconds": number,
          "superset_group": number | null,
          "notes": "string | null (e.g., 'Progressive overload: +2.5kg from last week')"
        }
      ],
      "cooldown": "string",
      "coach_note": "string (one sentence context for the day)"
    }
  ]
}
```

#### Validation Rules (post-generation)

1. Every exercise name must exist in the user's exercise library. If an unknown exercise appears, replace it with the closest match from the library (fuzzy match, log the substitution).
2. No heavy leg exercises (squat, deadlift, leg press, lunge, Romanian deadlift) on the day before a football constraint.
3. Total sets per session should be 15-25 for intermediate, 12-20 for beginner, 20-30 for advanced.
4. Recovery adjustment must match recovery zone: green = 0.9-1.2, yellow = 0.7-0.9, red = 0.5-0.7.
5. At least 1 rest day in the week.
6. **Weight sanity check:** No prescribed weight should exceed 1.5x the user's most recent weight for that exercise. If it does, cap it at the last known weight + 2.5kg. This prevents hallucinated weight recommendations.
7. **RPE sanity check:** RPE target must be 5-9. Anything outside this range is capped.
8. **Duration sanity check:** No single session should exceed the user's session_duration_preference by more than 20%. If it does, remove the lowest-priority isolation exercises.
9. If any validation fails, log the specific failure and either auto-correct (for exercise substitution, weight capping) or regenerate (for structural issues like missing rest days or football conflicts).

---

### 3.6 Recovery Prescription Generation

**Purpose:** Generate a personalized daily prescription based on Whoop biometrics, nutrition data, schedule, and recent training load.

**Model:** Haiku 4.5
**Temperature:** 0.2
**Max Output Tokens:** 400

#### System Prompt

```
You are a sports science advisor inside the Tempo app. You generate a daily recovery prescription based on biometric data, nutrition data, and the user's schedule. Your prescriptions are specific, time-bound, and actionable.

<rules>
- Every recommendation must be rooted in the provided <biometric_data> and <schedule>. Do NOT reference data that was not provided.
- Be specific with times: "Bed by 23:15" not "go to bed earlier".
- Be specific with quantities: "Drink 3L water today" not "stay hydrated".
- Calculate caffeine cutoff as: target bedtime minus 8 hours.
- Calculate target bedtime as: target wake time minus target sleep duration, adjusted for sleep debt.
- If HRV has been declining for 3+ days, flag it as a warning.
- If sleep debt exceeds 4 hours, flag it as a warning.
- Training recommendation must align with recovery zone: green = "Full send", yellow = "Moderate: reduce volume 20%", red = "Easy/mobility only" or "Rest".
- NEVER say "consult a doctor", "see a physician", or give medical diagnoses. You are a performance coach.
- NEVER suggest supplements, medications, or specific drugs.
- NEVER suggest caloric intake below 1,500 kcal for an active male.
- NEVER suggest training through pain or injury. If strain is high and recovery is red, prescribe rest.
- Hydration target must be between 2,000ml and 5,000ml. Anything outside this range should be capped.
- Output ONLY valid JSON. No markdown wrapping. Start with { and end with }.
</rules>
```

#### User Prompt Template

```
Generate today's recovery prescription. Use ONLY the data provided below.

<biometric_data>
TODAY: {{date}} ({{day_of_week}})

WHOOP:
- Recovery: {{recovery_score}}% ({{recovery_zone}})
- HRV: {{hrv}}ms (3-day trend: {{hrv_trend}}, 7-day avg: {{hrv_7day_avg}}ms)
- Resting HR: {{rhr}}bpm (7-day avg: {{rhr_7day_avg}}bpm)
- Last night sleep: {{sleep_hours}}h, Performance: {{sleep_performance}}%, Efficiency: {{sleep_efficiency}}%
- Sleep debt: {{sleep_debt_hours}}h
- Yesterday's strain: {{yesterday_strain}}
- Respiratory rate: {{resp_rate}} breaths/min (baseline: {{resp_baseline}})
</biometric_data>

<nutrition_yesterday>
- Calories: {{yesterday_cal}} / {{cal_target}} target
- Protein: {{yesterday_protein}}g / {{protein_target}}g
- Hydration: {{yesterday_water_ml}}ml
</nutrition_yesterday>

<schedule>
- Planned workout: {{planned_workout}}
- Football: {{football_today}} ({{football_time}} if yes)
- Classes: {{classes_today}}
- Target wake time: {{target_wake}}
- Target sleep duration: {{target_sleep_hours}}h
</schedule>

<recent_context>
- Days since last rest day: {{days_since_rest}}
- Recovery last 3 days: {{recovery_3day}}
- Average strain last 3 days: {{strain_3day_avg}}
</recent_context>

Return ONLY valid JSON (no markdown, start with {):
{
  "training_recommendation": "string",
  "training_intensity": "full_send" | "moderate" | "easy" | "rest",
  "volume_adjustment": number (0.0 to 1.2),
  "meal_timing": "string (specific recommendation)",
  "bedtime_target": "HH:MM",
  "wake_target": "HH:MM",
  "hydration_target_ml": number,
  "caffeine_cutoff": "HH:MM",
  "warnings": ["string"],
  "top_priority": "string (single most important thing to do today)"
}
```

#### Example Output

```json
{
  "training_recommendation": "Push day at 80% volume. Keep compound movements (bench press, overhead press) at normal intensity but drop the last set of each isolation exercise. Your body can handle the load but don't push for PRs today.",
  "training_intensity": "moderate",
  "volume_adjustment": 0.8,
  "meal_timing": "Eat a protein-rich meal within 90 minutes of training. You were 25g under protein target yesterday -- front-load protein today. Aim for 50g at breakfast.",
  "bedtime_target": "23:15",
  "wake_target": "06:45",
  "hydration_target_ml": 3200,
  "caffeine_cutoff": "15:15",
  "warnings": [
    "HRV has declined for 3 consecutive days (72 → 65 → 58ms). Monitor tomorrow. If it drops below 50ms, consider an extra rest day.",
    "Sleep debt is at 3.5 hours. Prioritize an early bedtime tonight to start recovering."
  ],
  "top_priority": "Protect tonight's sleep. Bed by 23:15, no screens after 22:45. Your HRV trend depends on it."
}
```

---

### 3.7 Study Schedule Optimization

**Purpose:** Generate an optimized study plan leading up to an exam, considering daily availability, topic difficulty, hours already studied per topic, and recovery data.

**Model:** Sonnet 4.6
**Temperature:** 0.3
**Max Output Tokens:** 1,500

#### System Prompt

```
You are an academic performance optimizer inside the Tempo app. You generate daily study schedules for a university student leading up to exams. Your plans balance study load with recovery, training, and daily obligations.

<rules>
- ONLY reference topics provided in the <exam_details> section. Do not invent topics or subjects.
- NEVER schedule study after 22:00.
- NEVER exceed 5h of study in a single day.
- Output ONLY valid JSON. No markdown, no code blocks. Start with { and end with }.
- All time recommendations must respect the user's <daily_availability>.
</rules>

Principles:
1. Spaced repetition: don't cram one topic in one day. Distribute topics across multiple days.
2. Harder/weaker topics get more time earlier in the study period.
3. Review sessions (shorter, recall-based) should be scheduled for the final 2 days before the exam.
4. Morning study sessions on high-recovery days are the most valuable. Schedule the hardest topics then.
5. Days with football practice or heavy training get lighter study loads (compensate on other days).
6. Never schedule study after 22:00 -- it damages next-day recovery (data shows this pattern).
7. Total study hours should not exceed 5h/day to prevent burnout. Recommend 25-minute Pomodoro blocks with 5-minute breaks.
8. Always include one lighter day ("consolidation day") per week for mental recovery.

Output format: JSON. Each day has specific study blocks with subject, duration, and recommended approach.
```

#### User Prompt Template

```
Generate a study plan for the upcoming exam.

<exam_details>
- Subject: {{exam_subject}}
- Date: {{exam_date}} ({{days_until_exam}} days away)
- Topics to cover: {{#each topic in topics}}
  - {{topic.name}}: Difficulty {{topic.difficulty}}/5, Hours studied so far: {{topic.hours_studied}}, Confidence: {{topic.confidence}}/5
  {{/each}}
- Exam format: {{exam_format}} (multiple choice | essay | mixed | problem-solving)
- Total estimated hours needed: {{estimated_hours_needed}}
</exam_details>

<daily_availability>
{{#each day in schedule}}
- {{day.date}} ({{day.day_name}}): Available {{day.available_hours}}h (training: {{day.training}}, classes: {{day.classes}})
{{/each}}
</daily_availability>

<recovery_context>
- Average recent recovery: {{avg_recovery}}%
- Recovery trend: {{recovery_trend}}
- Predicted high-recovery days: {{high_recovery_days}}
</recovery_context>

<study_performance>
- Best focus time of day: {{best_focus_time}}
- Average focus rating: {{avg_focus}}/5
- Best session length: {{best_session_length_min}} min
</study_performance>

Return ONLY valid JSON (no markdown, start with {):
{
  "exam": "string",
  "exam_date": "YYYY-MM-DD",
  "total_planned_hours": number,
  "strategy_summary": "string (2-3 sentences on the overall approach)",
  "days": [
    {
      "date": "YYYY-MM-DD",
      "day_name": "string",
      "total_study_min": number,
      "blocks": [
        {
          "start_time": "HH:MM",
          "duration_min": number,
          "subject": "string",
          "topic": "string",
          "approach": "deep_study" | "practice_problems" | "review" | "active_recall" | "past_papers",
          "notes": "string (specific guidance for this block)"
        }
      ],
      "day_note": "string (context for this day's load)"
    }
  ]
}
```

---

### 3.8 Meal Timing Recommendations

**Purpose:** Generate specific meal timing advice based on recovery data, training schedule, and current nutrition status.

**Model:** Haiku 4.5
**Temperature:** 0.3
**Max Output Tokens:** 300

#### System Prompt

```
You are a sports nutrition advisor inside the Tempo app. You generate specific meal timing recommendations based on the user's recovery status, training schedule, and current nutrition data.

<rules>
- Be specific with times: "Eat lunch by 13:00" not "eat lunch on time".
- Post-workout meal should be within 60-90 minutes of training.
- Pre-workout meal should be 2-3 hours before training (light carbs + moderate protein).
- On rest days, distribute meals evenly (every 3-4 hours).
- If the user is behind on protein, specify which remaining meals should be protein-heavy and by how much.
- If the user is over on calories, suggest lighter options for remaining meals.
- On red recovery days, emphasize anti-inflammatory foods and hydration.
- Maximum 4 specific recommendations. Keep each to 1-2 sentences.
- NEVER suggest caloric intake below 1,500 kcal. NEVER suggest skipping meals entirely.
- NEVER recommend specific supplements or diet pills.
- ONLY reference data from the <nutrition_status> provided. Do not invent meal names or calorie counts.
- Output ONLY valid JSON. No markdown wrapping. Start with { and end with }.
</rules>
```

#### User Prompt Template

```
Generate meal timing recommendations for today. Use ONLY the data provided below.

<nutrition_status>
<current>
- Time now: {{current_time}}
- Recovery: {{recovery_score}}% ({{recovery_zone}})
- Training scheduled: {{training_time}} ({{workout_type}})
</current>

<consumed_today>
- Calories consumed: {{calories_consumed}} / {{calorie_target}}
- Protein consumed: {{protein_consumed}}g / {{protein_target}}g
- Meals logged: {{meals_logged}} / {{meals_planned}}
- Last meal: {{last_meal_time}} ({{last_meal_name}})
</consumed_today>

<remaining_meals>
{{#each meal in remaining_meals}}
- {{meal.name}}: Planned at {{meal.time}}, ~{{meal.planned_calories}}kcal, ~{{meal.planned_protein}}g protein
{{/each}}
</remaining_meals>
</nutrition_status>

Return ONLY valid JSON (no markdown, start with {):
{
  "recommendations": [
    {
      "priority": number (1 = most important),
      "meal": "string (which meal this applies to)",
      "recommendation": "string (specific, actionable advice)",
      "reason": "string (why, referencing data)"
    }
  ],
  "protein_deficit": number,
  "calorie_status": "on_track" | "under" | "over"
}
```

---

### 3.9 Achievement / Milestone Celebration Copy

**Purpose:** Generate personalized celebration text when the user hits a milestone (streak, XP level, challenge win, PR).

**Model:** Haiku 4.5
**Temperature:** 0.9
**Max Output Tokens:** 200

#### System Prompt

```
You are the voice of the Tempo app celebrating a user's achievement. Your tone shifts from your usual drill-sergeant mode to brief, earned respect. You don't gush -- you acknowledge what was hard about the achievement and why it matters.

<rules>
- Maximum 2 sentences. Aim for 20-40 words total.
- Reference the specific achievement and what it took to earn it. Use ONLY data from the <achievement> section.
- Contrast with where the user started if data is available.
- No emojis. No exclamation marks.
- No generic praise ("Great job!", "Well done!"). Be specific.
- For streak milestones: reference what the streak survived (bad days, weekends, exams).
- For PRs: reference the previous best and the progression.
- For challenge wins: reference the competition.
- NEVER reference body appearance. Celebrate behavior and effort, not physique.
- Output plain text only. No JSON, no labels, no prefixes.
</rules>
```

#### User Prompt Template

```
<achievement type="{{achievement_type}}">
{{#if streak_milestone}}
- Streak: {{streak_days}} days
- Streak survived: {{streak_challenges}} (e.g., "2 red recovery days, 1 exam week, 3 weekends")
- Worst day during streak: {{worst_day_score}}/100
{{/if}}

{{#if personal_record}}
- Exercise: {{exercise_name}}
- New PR: {{new_pr}}kg
- Previous PR: {{old_pr}}kg (set {{old_pr_date}})
- Sessions since last PR: {{sessions_since_pr}}
{{/if}}

{{#if level_up}}
- New level: {{new_level}}
- Total XP: {{total_xp}}
- Days to reach this level: {{days_to_level}}
{{/if}}

{{#if challenge_win}}
- Challenge: {{challenge_name}}
- Your score: {{user_score}}
- Runner-up: {{runner_up_name}} at {{runner_up_score}}
- Duration: {{challenge_duration}} days
{{/if}}
</achievement>

Generate the celebration text. Use ONLY data from <achievement>. Output plain text only (no JSON, no labels).
```

#### Example Outputs

**30-day streak:**
```
Thirty days. You held the line through two red recovery mornings, an exam week, and four weekends where quitting was the easy call. This isn't luck -- it's identity.
```

**Bench press PR:**
```
Bench press: 92.5kg. That's 5kg above your old PR from February 8th. Seven sessions of grinding to add that weight. The bar doesn't lie.
```

**Challenge win:**
```
Study Hours Challenge: 14.2 hours to Marco's 11.8. You outworked him by two and a half hours over 7 days. The leaderboard updated. He noticed.
```

---

### 3.10 Natural Language Dashboard Insights

**Purpose:** Generate 2-3 brief natural language insights for the dashboard Quick Insights Banner. These are the lightbulb-icon insights users see daily.

**Model:** Haiku 4.5
**Temperature:** 0.5
**Max Output Tokens:** 400

#### System Prompt

```
You generate brief, data-driven insights for a health and performance dashboard. Each insight is a single observation connecting two data points, written as one sentence.

<rules>
- Each insight MUST reference specific numbers from the <dashboard_data> provided. Do not invent numbers.
- Each insight must connect cause and effect or highlight a notable pattern across domains.
- Maximum 3 insights. Each is 1 sentence, 15-25 words.
- Use "you" directly. Drill-sergeant tone but informational.
- Insights should be things the user might not notice on their own -- connections between different data domains (sleep vs study, nutrition vs recovery, etc.).
- No emojis. No labels. Just the sentences.
- NEVER give medical advice or suggest seeing a doctor.
- Output as a JSON array of strings. No markdown wrapping. Start with [ and end with ].
</rules>
```

#### User Prompt Template

```
Generate dashboard insights. Use ONLY numbers from <dashboard_data>. Do not invent any statistics.

<dashboard_data>
<today>
- Recovery: {{recovery_score}}% ({{recovery_zone}})
- Sleep: {{sleep_hours}}h (score {{sleep_score}}%)
- Strain: {{current_strain}}
- Calories: {{calories}} / {{cal_target}} ({{protein}}g protein)
- Study: {{study_min}} min (target: {{study_target}})
- Non-negotiables: {{nn_completed}}/{{nn_total}}
- Steps: {{steps}}
</today>

<recent_7day>
- Avg recovery: {{avg_recovery_7d}}%
- Avg sleep: {{avg_sleep_7d}}h
- Workout days: {{workout_days_7d}}/7
- Study avg: {{avg_study_7d}} min/day
- Protein hit rate: {{protein_hit_rate_7d}}%

<notable>
{{#if notable_items}}
{{#each item in notable_items}}
- {{item}}
{{/each}}
{{/if}}
</notable>
</dashboard_data>

Return 2-3 insights as a JSON array of strings (start with [, end with ]).
```

#### Example Output

```json
[
  "Your recovery jumped 18 points after last night's 8.1h sleep -- the longest sleep you've had in 9 days.",
  "You've hit your protein target 6 of the last 7 days. The one miss was Thursday, your only 3-meal day.",
  "Study time is 22% higher on days you train first. Today's Push day could set up a productive afternoon."
]
```

---

### 3.11 Training Adjustment (Real-Time)

**Purpose:** When recovery data comes in and significantly differs from the predicted value used for the weekly plan, adjust today's workout in real-time.

**Model:** Haiku 4.5
**Temperature:** 0.3
**Max Output Tokens:** 500

#### System Prompt

```
You are a strength coach making a real-time adjustment to today's workout based on new recovery data. The weekly plan was generated assuming a certain recovery level, but the actual recovery is different. You must adjust the existing plan, not rewrite it.

<rules>
- If recovery is BETTER than expected: optionally increase intensity or add a finisher set. Do not change the exercise selection.
- If recovery is WORSE than expected by 10-20 points: reduce volume (drop last 1-2 sets per exercise), maintain exercise selection.
- If recovery is WORSE than expected by 20+ points: swap to a lighter variation of the same muscle groups, or swap to mobility if recovery is red.
- Keep the same time duration (user scheduled this time).
- Explain the adjustment in 1 sentence (shown to user as a coach note).
- NEVER suggest training through pain or injury. If recovery is red (<34%), always recommend mobility or rest.
- ONLY reference exercises from the <planned_workout>. Do not introduce new exercises not in the original plan.
- Output ONLY valid JSON. No markdown. Start with { and end with }.
</rules>
```

#### User Prompt Template

```
Adjust today's workout based on actual recovery. Only reference exercises from <planned_workout>.

<planned_workout>
{{planned_workout_json}}
</planned_workout>

<recovery_comparison>
EXPECTED: {{expected_recovery}}% ({{expected_zone}})
ACTUAL: {{actual_recovery}}% ({{actual_zone}})
DELTA: {{recovery_delta}} points
</recovery_comparison>

<biometrics>
HRV: {{hrv}}ms (trend: {{hrv_trend}})
SLEEP: {{sleep_hours}}h (score: {{sleep_score}}%)
</biometrics>

Return ONLY valid JSON (no markdown, start with {):
{
  "adjustment_type": "none" | "volume_reduction" | "intensity_reduction" | "exercise_swap" | "mobility_swap",
  "adjustment_reason": "string (1 sentence, shown to user)",
  "volume_adjustment": number (0.0 to 1.2),
  "adjusted_exercises": [
    {
      "original_name": "string",
      "adjusted_name": "string (same if no change)",
      "adjusted_sets": number,
      "adjusted_reps": "string",
      "adjusted_weight_kg": number | null,
      "adjusted_rpe_target": number
    }
  ]
}
```

---

## 4. Data Pipeline

### 4.1 Per-Feature Data Requirements

| Feature | Data Sources | Aggregation | Token Estimate | Refresh Trigger |
|---------|-------------|-------------|----------------|-----------------|
| Morning Briefing | Whoop (today), NutriTrack (today's plan), Local (streak, yesterday's score, schedule) | None (current day only) | 0 tokens (template) / ~500 tokens (Haiku fallback) | Daily at wake time |
| Weekly Report | Whoop (7 days), NutriTrack (7 days), Study (7 days), Accountability (7 days), XP (7 days), Previous week averages | Daily aggregates | ~2,500 tokens input | Sunday 8 PM or on-demand |
| Pattern Detection | Whoop (30-90 days), NutriTrack (30-90 days), Study (30-90 days), Accountability (30-90 days) | Compressed daily summaries + pre-computed correlations | ~4,000-5,000 tokens input | Weekly (background) or on-demand |
| Training Program | Whoop (7 days recovery), Calendar (7 days schedule), Training history (last 4 sessions), Exercise library | Session-level detail + daily recovery | ~2,000 tokens input | Weekly or recovery-triggered |
| Training Adjustment | Whoop (today), Planned workout | None | ~800 tokens input | On Whoop sync if delta > 10 |
| Recovery Prescription | Whoop (today + 3-day trend), NutriTrack (yesterday), Calendar (today), Training (days since rest) | 3-day trend | ~700 tokens input | Daily after Whoop sync |
| Drill Sergeant Batch | User profile, 3-day schedule, Arena data, Recent performance | 3-day aggregates + daily schedule | ~1,200 tokens input | Sunday night + Wednesday night (3-day batches) |
| Meal Timing | NutriTrack (today, real-time), Whoop (today recovery), Training schedule | Current snapshot | ~500 tokens input | On NutriTrack data change |
| Study Schedule | Exam data, Topic progress, Calendar (daily availability), Recovery trends | Per-topic aggregates | ~1,500 tokens input | On exam creation/edit |
| Achievement Copy | Achievement details, User history | Event-specific | ~300 tokens input | On achievement trigger |
| Dashboard Insights | Whoop (today + 7-day), NutriTrack (today + 7-day), Study (today + 7-day) | 7-day averages + today | ~800 tokens input | On dashboard load (if stale) |

### 4.2 Data Formatting Pipeline

```
Raw Data Sources          Aggregation Layer         Prompt Builder          Claude API
─────────────────         ─────────────────         ──────────────          ──────────

Whoop API ──────┐
                ├──→ DailySnapshot ──────┐
HealthKit ──────┘                         │
                                          ├──→ PromptTemplate.render() ──→ Claude
NutriTrack API ──→ NutritionSummary ─────┤         ▲
                                          │         │
Local SwiftData ──→ StudyAggregate ──────┤    Token Counter
                    AccountabilitySummary─┘    (validates < limit)
```

### 4.3 Data Compression for Pattern Detection

90 days of data at full resolution would be ~15,000 tokens. The compression strategy:

**Step 1: Pipe-delimited daily summary (server-side)**
```
2026-03-24|rec:72|hrv:58|sleep:6.8|slp_score:74|bed:23.5|strain:12.4|workout:push|cal:2340|cal_tgt:2400|prot:185|prot_tgt:180|meals:4|study:135|study_tgt:120|focus:4|nn_pct:100|score:88
```
This is ~200 chars / ~50 tokens per day. 90 days = ~4,500 tokens. Fits comfortably.

**Step 2: Pre-computed statistics (server-side)**
- Means, standard deviations for all metrics
- Pearson correlations for all tracked variable pairs
- Day-of-week averages
This adds ~500 tokens.

**Step 3: Notable events flag (server-side)**
- Days with recovery < 34% (red)
- Days with perfect 100% accountability
- Days with zero study
- Streak start/break events
This adds ~200 tokens for up to 10 flagged events.

**Total: ~5,200 tokens for 90 days. Well within the 6,000 token input budget.**

### 4.4 Data Anonymization

Before any data is sent to Claude API, the following fields are stripped:

| Field | Action | Replacement |
|-------|--------|-------------|
| `user_id` | Strip | Not sent |
| `name` | Strip | Not sent (except first name for notification copy -- user must opt in) |
| `email` | Strip | Not sent |
| `apple_id` | Strip | Not sent |
| `device_id` | Strip | Not sent |
| `location` | Strip | Not sent |
| `IP address` | Strip | Not sent |
| `friend names` | Sent (first name only) | Required for competitive notification copy |
| `exam names` | Sent | Required for study schedule context |
| `timezone` | Sent | Required for time-based recommendations |

The `friend_names` inclusion requires explicit user consent during onboarding: "Allow Tempo to use your friends' names in motivational messages?"

---

## 5. Cost Management

> **FEASIBILITY NOTE (Technical Feasibility Audit Section 6.6):** At $2.42/user/month, AI costs consume ~58% of subscription revenue ($4.99/month) before Apple's 30% cut. After Apple's cut, net revenue is $3.49/user/month, leaving $1.07/user/month margin before hosting. **All AI features must be Pro-only.** Free users receive rule-based insights (e.g., "Your HRV is 15% below your 7-day average"). Pro users get LLM-generated insights, pattern detection, and personalized coaching. See MONETIZATION_STRATEGY.md for the free/pro feature split.
>
> **Break-even analysis:** At $4.99/month, Apple takes $1.50, AI costs $2.42, leaving $1.07 for hosting + margin. This is tight but viable at scale (hosting costs per user decrease). If margins need improvement: (a) drop Opus to Sonnet for pattern detection (saves $1.04/user/month), or (b) increase subscription to $6.99/month.

### 5.1 Pricing Reference (as of March 2026)

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Source |
|-------|----------------------|----------------------|--------|
| Claude Haiku 4.5 | $1.00 | $5.00 | anthropic.com/pricing |
| Claude Sonnet 4.6 | $3.00 | $15.00 | anthropic.com/pricing |
| Claude Opus 4.6 | $15.00 | $75.00 | anthropic.com/pricing |

### 5.2 Per-Feature Cost Estimate (Single User, Realistic Usage)

Cost calculation: (input_tokens / 1,000,000 * input_price) + (output_tokens / 1,000,000 * output_price)

| Feature | Model | Input Tokens | Output Tokens | Input Cost | Output Cost | Total per Call | Frequency | Monthly Cost |
|---------|-------|-------------|--------------|------------|-------------|----------------|-----------|-------------|
| Morning Briefing | Template | 0 | 0 | $0.00 | $0.00 | **$0.00** | Daily (30/mo) | **$0.00** |
| Weekly Report | Sonnet 4.6 | 4,000 | 1,500 | $0.012 | $0.0225 | **$0.035** | Weekly (4/mo) | $0.14 |
| Pattern Detection | Opus 4.6 | 6,000 | 1,200 | $0.090 | $0.090 | **$0.180** | Weekly (4/mo) | **$0.72** |
| Training Program | Sonnet 4.6 | 3,000 | 2,000 | $0.009 | $0.030 | **$0.039** | Weekly (4/mo) | $0.16 |
| Training Adjustment | Haiku 4.5 | 1,500 | 400 | $0.0015 | $0.002 | **$0.004** | 3x/week (12/mo) | $0.04 |
| Recovery Prescription | Haiku 4.5 | 1,200 | 300 | $0.0012 | $0.0015 | **$0.003** | Daily (30/mo) | $0.08 |
| Notification Batch | Sonnet 4.6 | 1,200 | 1,500 | $0.0036 | $0.0225 | **$0.026** | 2x/week (8/mo) | **$0.21** |
| Meal Timing | Haiku 4.5 | 1,000 | 200 | $0.001 | $0.001 | **$0.002** | Daily (30/mo) | $0.06 |
| Study Schedule | Sonnet 4.6 | 2,500 | 1,200 | $0.0075 | $0.018 | **$0.026** | 2x/month | $0.05 |
| Achievement Copy | Haiku 4.5 | 800 | 150 | $0.0008 | $0.00075 | **$0.002** | 8x/month | $0.01 |
| Dashboard Insights | Haiku 4.5 | 1,500 | 300 | $0.0015 | $0.0015 | **$0.003** | Daily (30/mo) | $0.09 |
| Retries (~5% of calls) | Mixed | varies | varies | -- | -- | -- | ~8/month | ~$0.06 |
| **TOTAL per user/month** | | | | | | | | **$1.62** |

**Realistic usage adjustment:** Not every user triggers every feature every day. Realistic "active user" profile (opens app 5 of 7 days, tracks 80% of meals, studies 5 days/week):

| Usage Level | Multiplier | Monthly Cost | Viable at $4.99/mo? |
|-------------|-----------|-------------|---------------------|
| Power user (daily, all features) | 1.0x | $1.62 | Yes ($1.87 margin after Apple) |
| Active user (5 days/week) | 0.75x | $1.22 | Yes ($2.27 margin) |
| Casual user (3 days/week) | 0.45x | $0.73 | Yes ($2.76 margin) |
| Average across user base | ~0.65x | ~$1.05 | Yes ($2.44 margin) |

### 5.3 Monthly Cost at Scale

| Users | Avg Monthly AI Cost | Subscription Revenue (after Apple 30%) | Net Margin | Notes |
|-------|--------------------|-----------------------------------------|------------|-------|
| 100 | $105 | $349 | $244 | Comfortable. Hosting ~$30/mo. |
| 1,000 | $1,050 | $3,493 | $2,443 | Healthy. Hosting ~$150/mo. |
| 10,000 | $10,500 | $34,930 | $24,430 | Strong. Can afford Opus. |

**If $4.99/month is not enough (worst case: all power users):**
- At 1,000 power users: AI cost = $1,620/mo vs revenue $3,493. Still viable.
- Escape valves: (a) downgrade pattern detection from Opus to Sonnet (saves $720/mo at 1K users), (b) increase caching TTLs, (c) shift morning briefing Haiku fallback to template-only.

### 5.4 Budget Enforcement (Server-Side)

```swift
// AIBudgetTracker.swift

actor AIBudgetTracker {
    private let monthlyBudgetCents: Int  // default: 5000 ($50) for dev, scales with users
    private var currentMonthSpendCents: Int = 0
    private var currentMonth: Int = 0

    func canMakeCall(estimatedCostCents: Int) -> Bool {
        resetIfNewMonth()
        return (currentMonthSpendCents + estimatedCostCents) <= monthlyBudgetCents
    }

    func recordSpend(inputTokens: Int, outputTokens: Int, model: String) {
        let costMicrodollars: Int  // track in microdollars (1/1,000,000 of a dollar) for precision
        switch model {
        case AIConfig.haikuModel:
            costMicrodollars = inputTokens * 1 + outputTokens * 5  // $1.00/1M in, $5.00/1M out
        case AIConfig.sonnetModel:
            costMicrodollars = inputTokens * 3 + outputTokens * 15  // $3.00/1M in, $15.00/1M out
        case AIConfig.opusModel:
            costMicrodollars = inputTokens * 15 + outputTokens * 75  // $15.00/1M in, $75.00/1M out
        default:
            costMicrodollars = 0
        }
        // Convert microdollars to cents: divide by 10,000
        currentMonthSpendCents += max(1, costMicrodollars / 10_000)
    }

    var budgetUsagePercent: Double {
        Double(currentMonthSpendCents) / Double(monthlyBudgetCents) * 100
    }
}
```

**Budget alert thresholds:**
- 50%: Log warning, reduce pattern detection to biweekly.
- 80%: Log warning, disable on-demand pattern queries, downgrade pattern detection from Opus to Sonnet.
- 95%: Critical alert. Disable all non-essential AI features. Only recovery prescription remains active (using Haiku). Morning briefing uses template.
- 100%: All AI features switch to fallback mode (Section 8). Return HTTP 503 with error code 5004 for new AI requests.

### 5.5 Cost Optimization Strategies

1. **Morning briefing as template (free):** The biggest single cost saver. Template-based morning briefings are indistinguishable from Haiku output for this feature. Saves $0.06/user/month (30 API calls eliminated).

2. **3-day notification batches with Sonnet:** Two Sonnet calls per week (Sun + Wed) generate 36 notification copies (3 days x 6 channels x 2 batches). Better quality than 7-day Haiku batch, fresher copy, and only marginally more expensive.

3. **Cache aggressively:** Weekly reports are immutable (the week's data doesn't change). Cache forever. Pattern detection results cached per-correlation (see Section 6).

4. **Pre-compute correlations server-side:** Pearson correlations are computed in PostgreSQL/Swift before sending to Claude. This reduces Claude's job from "analyze raw data" to "interpret pre-computed statistics," cutting both input tokens and hallucination risk.

5. **Conditional generation:** Don't regenerate if data hasn't changed. Dashboard insights only regenerate if the underlying data has changed since last generation (compare hash of input data).

6. **Token-efficient data formats:** Pipe-delimited daily summaries instead of JSON for pattern detection. This reduces token count by ~40% compared to formatted JSON.

7. **User-level rate limits:** 12 AI calls per user per day maximum (reduced from 15 since morning briefing is now template). Prevents any single power user from burning budget.

8. **Opus only where it matters:** Pattern detection is the only feature using Opus. At 4 calls/month, the $0.72/user/month cost is justified by it being the highest-value feature. If budget pressure increases, this is the first feature to downgrade to Sonnet (saving $0.58/user/month with moderate quality loss).

---

## 6. Caching Strategy

### 6.1 Cache Configuration

| Feature | Cache Key | TTL | Storage | Invalidation Trigger |
|---------|-----------|-----|---------|---------------------|
| Weekly Report | `insight:weekly:{user_id}:{week_start}` | 7 days (soft), Forever (hard) | PostgreSQL (`insights` table) | `force_regenerate: true`, OR if 3+ new workouts logged after initial generation (significant new data) |
| Pattern Detection | `insight:pattern:{user_id}:{correlation_key}` | 24 hours per correlation | Redis | New day of data added (invalidates affected correlations only, not all patterns) |
| Training Program | `training:program:{user_id}:{week_start}` | Until recovery delta > 15 points from plan assumptions | PostgreSQL | Recovery sync shows significant deviation |
| Recovery Prescription | `prescription:{user_id}:{date}` | 12 hours | Redis + SwiftData (local) | New Whoop sync for today |
| Morning Briefing | `briefing:{user_id}:{date}` | 24 hours (one per day) | Local (SwiftData) | Never (template-based, no API call) |
| Notification Batch | `notifications:{user_id}:{batch_start}` | 3 days | Redis | Next batch generation (Sun night or Wed night) |
| Dashboard Insights | `dashboard:insights:{user_id}:{data_hash}` | Until data changes | Redis | Any data source update |
| Meal Timing | `meal:timing:{user_id}:{date}:{meal_index}` | 2 hours | Redis | NutriTrack data update |
| Study Schedule | `study:plan:{user_id}:{exam_id}` | Until exam date changes or topic progress updates | PostgreSQL | Exam edit, manual refresh |
| Achievement Copy | `achievement:{user_id}:{achievement_id}` | Forever | PostgreSQL | Never |

**Pattern Detection per-correlation caching:** Instead of caching all patterns as a single blob (forcing full regeneration when any data changes), each pattern is cached independently keyed by its correlation pair (e.g., `sleep_hours:next_day_recovery`). When new data arrives, only the affected correlations are invalidated. If a user logs a new workout, sleep-related patterns remain cached while workout-related patterns regenerate. This reduces Opus calls by ~60% compared to all-or-nothing caching.

**Weekly Report smart invalidation:** The report is initially generated Sunday night and cached. However, if significant new data arrives after generation (e.g., the user logs 3+ workouts, corrects nutrition data, or completes a study session that changes the weekly averages by >10%), the cache is invalidated and the report regenerates on next view. This prevents the report from being stale when users log data late.

### 6.2 Stale-While-Revalidate Pattern

For features where freshness matters but latency matters more (dashboard insights, recovery prescription):

```
1. User requests data.
2. Check cache:
   a. If FRESH (within TTL): return cached data immediately.
   b. If STALE (past TTL but exists): return cached data immediately,
      AND trigger async background regeneration.
   c. If MISS (no cache): generate synchronously, cache, return.
3. Background regeneration updates the cache for the next request.
```

This ensures the user never waits for AI generation on cached features. The maximum staleness is one request cycle.

### 6.3 Cache Warming

**Sunday night batch (primary):** The backend proactively generates and caches:
- Weekly report (for the just-completed week)
- Pattern detection (30-day, all correlations)
- Next week's training program
- Notification batch for Mon-Wed (3-day batch)

**Wednesday night batch (secondary):**
- Notification batch for Thu-Sat (3-day batch, using fresher data than a Sunday 7-day batch would)
- Re-evaluate pattern detection if significant new data since Sunday

This means Monday morning is fully cached -- zero AI latency for the user's first interaction of the week. Thursday morning also starts with fresh notification copy.

---

## 7. Quality Assurance

### 7.1 Response Validation Pipeline

Every Claude response goes through this pipeline before being served to the user:

```
Claude Response
       │
       ▼
┌──────────────────┐
│ 1. Parse Check   │ → Can it be parsed as the expected format (JSON/text)?
│    Fail → Retry  │   If JSON, is it valid JSON?
└──────┬───────────┘
       ▼
┌──────────────────┐
│ 2. Schema Check  │ → Does it have all required fields?
│    Fail → Retry  │   Are field types correct?
└──────┬───────────┘
       ▼
┌──────────────────┐
│ 3. Hallucination │ → Does it reference numbers not in the input?
│    Check         │   Cross-reference cited values against input data.
│    Fail → Log +  │   (Exact match not required; within 5% tolerance.)
│    Flag          │
└──────┬───────────┘
       ▼
┌──────────────────┐
│ 4. Safety Check  │ → Medical advice detection (regex for "doctor",
│    Fail → Strip  │   "physician", "diagnosis", "medication").
│    or Regenerate │   Extreme behavior detection ("skip all meals",
│                  │   "train through injury", "take supplements").
└──────┬───────────┘
       ▼
┌──────────────────┐
│ 5. Length Check  │ → Within min/max word/token limits?
│    Fail → Trim   │   Truncate at sentence boundary if over.
│    or Regenerate │   Regenerate if under.
└──────┬───────────┘
       ▼
┌──────────────────┐
│ 6. Tone Check    │ → For drill-sergeant copy: does it contain at least
│    Fail → Pass   │   one imperative sentence?
│    (soft fail)   │   For prescriptions: is it specific (contains times,
│                  │   quantities)?
└──────┬───────────┘
       ▼
   ✅ Serve to user
```

**Maximum retry attempts:** 2 (so 3 total attempts). After that, fall back to templates.

### 7.2 Hallucination Prevention

The primary strategy is **constraining the input-output relationship:**

1. **Every prompt explicitly states:** "Only reference data that was provided. Never fabricate statistics." (enforced via `<rules>` sections in all system prompts).
2. **XML data tags:** All user data is wrapped in XML tags (`<week_data>`, `<biometric_data>`, `<daily_data>`, etc.) which helps Claude distinguish "this is data you can reference" from "this is instructions." Claude handles XML-tagged data significantly better than plain text for grounding.
3. **Server-side cross-reference:** For weekly reports, the server extracts all numbers from the response and checks them against the input data. If a number appears in the output that is not within 5% of any input number, it is flagged.
4. **Structured output:** Requesting JSON with specific schemas reduces free-form hallucination.
5. **Pre-computed statistics:** For pattern detection, correlations are computed server-side and sent to Claude. Claude interprets them rather than computing them, eliminating mathematical hallucination.
6. **Bad output examples:** System prompts include `<bad_output_example>` sections showing what rejected output looks like and why. This dramatically reduces common failure modes (vague action items, generic analysis, wrong icon names).

**Specific validation guardrails per feature:**

| Feature | Guardrail | Action on Failure |
|---------|-----------|-------------------|
| Recovery Prescription | `hydration_target_ml` must be 2000-5000 | Cap to nearest bound |
| Recovery Prescription | `volume_adjustment` must be 0.0-1.2 | Cap to nearest bound |
| Training Program | Every `weight_kg` must be <= 1.5x user's recent max for that exercise | Cap at last known + 2.5kg |
| Training Program | Every `exercise.name` must exist in exercise library | Fuzzy-match substitute |
| Weekly Report | Every number cited must appear in input data (within 5%) | Flag + log for review |
| Weekly Report | If accountability avg < 70%, not all sections can be "positive" | Reject + regenerate |
| Pattern Detection | `occurrences` must be >= 5 | Strip patterns below threshold |
| Pattern Detection | `correlation_r` must match pre-computed value (within 0.05) | Replace with server value |
| Meal Timing | Suggested calories for any meal must not exceed user's remaining daily target | Cap to remaining |
| All features | Protein suggestion must not exceed 5g/kg bodyweight (if known) | Reject and use fallback |

### 7.3 Medical / Health Disclaimer

**Every AI-generated insight in the app is preceded by a disclaimer on first view:**

> AI-generated insights are based on your biometric, nutrition, and activity data. They are informational only and do not constitute medical advice. Always consult a qualified healthcare professional before making decisions about your health, diet, or exercise program. If you experience pain, dizziness, or concerning symptoms, stop exercising and seek medical attention.

This disclaimer:
- Shows as a full-screen modal on first AI insight view (dismissable, stored in UserDefaults with `ai_disclaimer_accepted_at` timestamp)
- Appears as a footer on every Weekly Report (static text, not AI-generated): "AI analysis -- not medical advice"
- Appears as a footer on every Recovery Prescription: "Coach guidance -- not medical advice"
- Is included in the App Store privacy policy and Terms of Service
- Is shown again if the user has not opened the app in 90+ days (re-consent)

### 7.4 Harmful Content Prevention

**Layer 1: Prompt-level prevention (system prompts)**

All system prompts explicitly prohibit via `<rules>` sections:
- Extreme caloric restriction recommendations (never suggest <1,500 kcal for an active male)
- Training through pain or injury language
- Supplement, drug, or medication recommendations
- Guilt-based language about body appearance (the drill sergeant targets behavior, not body)
- Disparaging mental health (red recovery is framed as "rebuilding," not "weak")
- Medical advice, diagnoses, or referrals to doctors

**Layer 2: Post-generation content filter (runs on EVERY response before user sees it)**

Regex-based filter for flagged phrases. This is the safety net -- even if the prompt fails to prevent harmful output, the filter catches it.

```
REJECT_PATTERNS = [
    # Dangerous diet advice
    r"(skip|cut|eliminate).*(all|every|most).*meal",
    r"(fast|fasting).*(24|48|72)\s*hour",
    r"(eat|consume|intake).*(less than|under|below)\s*(1[0-4]\d{2}|[1-9]\d{2})\s*(kcal|calorie)",
    r"(purge|laxative|diuretic)",

    # Training through injury
    r"(push|train|work|power)\s*(through|past|despite).*(pain|injury|hurt|ache)",
    r"(ignore|dismiss).*(pain|injury|symptom)",
    r"no\s*pain.*no\s*gain",

    # Supplements and drugs
    r"(take|try|use|buy|order).*(supplement|creatine|pre-workout|caffeine pill|steroid|sarm|peptide|hormone)",

    # Body shaming
    r"(fat|ugly|weak|pathetic|disgusting|gross).*body",
    r"you('re| are).*(failure|worthless|pathetic|weak|useless|garbage)",
    r"(skinny|scrawny|flabby)",

    # Medical advice (Claude should never play doctor)
    r"(you (should|need to|must) see|consult|visit).*(doctor|physician|specialist|therapist)",
    r"(diagnos|prescri|symptom.*(of|suggest)|could (be|indicate))",
    r"(medication|medicine|drug|pharmaceutical)",
]
```

**Filter behavior:**
1. If a single sentence matches: strip that sentence, serve the rest.
2. If 2+ sentences match: regenerate with a tighter prompt (add "CRITICAL: Do not give medical advice or suggest extreme behaviors").
3. If the regeneration also fails: use fallback (Section 8).
4. **Always log** the original flagged response for prompt improvement (store: feature, pattern matched, full response, timestamp).

If more than 30% of the response is stripped, regenerate rather than serving a hollow response.

### 7.5 A/B Testing Framework

For drill-sergeant notification copy, support A/B testing of prompt variations:

```swift
struct PromptVariant {
    let id: String          // "drill_v2_aggressive"
    let systemPrompt: String
    let weight: Double      // traffic allocation (0.0 to 1.0)
}

// Metrics tracked per variant:
// - Notification tap-through rate
// - Time from notification to task completion
// - User thumbs-up/thumbs-down (if exposed)
// - Daily score on days this variant was shown
```

**Current variants to test:**
1. Default drill-sergeant tone (current)
2. More empathetic drill-sergeant ("I know it's hard. Do it anyway.")
3. Data-forward ("Your data says you study 40% more after training. Go train.")
4. Competitive ("Marco is 45 XP ahead. Every hour you waste, he pulls further ahead.")

### 7.6 User Feedback Loop

Every AI-generated insight shows a small thumbs-up / thumbs-down icon in the bottom-right corner.

```swift
struct InsightFeedback: Codable {
    let insightId: String
    let insightType: String        // "weekly", "pattern", "briefing", etc.
    let rating: Rating             // .positive, .negative
    let promptVariantId: String?
    let timestamp: Date
}
```

Feedback is collected and used to:
1. Identify consistently low-rated prompt variants for revision.
2. Surface to the developer dashboard for manual prompt tuning.
3. If a specific insight type gets >30% negative ratings over 2 weeks, trigger prompt review.

---

## 8. Offline / Fallback System

For EVERY AI feature, there is an algorithmic fallback that activates when:
- Claude API is unavailable (HTTP 5xx after retries)
- Monthly budget is exhausted
- User is offline (for locally-triggered features)
- Rate limit exceeded for the user

### 8.1 Morning Briefing Fallback

**Template-based generation with dynamic data insertion.**

```swift
func generateFallbackBriefing(snapshot: DailySnapshot, context: BriefingContext) -> String {
    var parts: [String] = []

    // Recovery line
    switch snapshot.recoveryZone {
    case .green:
        parts.append("Recovery at \(snapshot.recoveryScore)%. Green light. Full send on \(context.workoutType) today.")
    case .yellow:
        parts.append("Recovery at \(snapshot.recoveryScore)%. Yellow zone. \(context.workoutType) at reduced volume today.")
    case .red:
        parts.append("Recovery at \(snapshot.recoveryScore)%. Red. Swapping to mobility. Your body needs it.")
    }

    // Non-negotiables line
    parts.append("\(context.nonNegotiableCount) non-negotiables today: \(context.nonNegotiablesList).")

    // Streak line (if applicable)
    if context.streakDays > 0 {
        parts.append("Day \(context.streakDays + 1) of your streak. Don't break it.")
    }

    // Exam line (if applicable)
    if let exam = context.upcomingExam, exam.daysAway <= 14 {
        parts.append("\(exam.name) in \(exam.daysAway) days. Study comes first.")
    }

    // Yesterday context
    if context.yesterdayCompletionPct < 75 {
        parts.append("Yesterday was \(context.yesterdayCompletionPct)%. Better today.")
    }

    return parts.joined(separator: " ")
}
```

### 8.2 Weekly Report Fallback

**Statistical template with data fill-in. No natural language analysis.**

```swift
func generateFallbackWeeklyReport(weekData: WeekData, prevWeek: WeekData) -> WeeklyReportResponse {
    return WeeklyReportResponse(
        title: generateFallbackTitle(weekData),
        summary: "This week you scored an average of \(weekData.avgScore)/100 across \(weekData.daysWithData) days. " +
                 "Recovery averaged \(weekData.avgRecovery)% and you completed \(weekData.avgCompletionPct)% of non-negotiables.",
        sections: [
            ReportSection(
                title: "Recovery & Sleep",
                icon: "bed.double.fill",
                body: "Average recovery: \(weekData.avgRecovery)% (\(delta(weekData.avgRecovery, prevWeek.avgRecovery))% vs last week). " +
                      "Sleep averaged \(weekData.avgSleepHours)h. Best day: \(weekData.bestRecoveryDay). Worst: \(weekData.worstRecoveryDay).",
                sentiment: weekData.avgRecovery >= prevWeek.avgRecovery ? .positive : .warning
            ),
            // ... similar for Fitness, Nutrition, Academics
        ],
        actionItems: generateRuleBasedActionItems(weekData),
        comparedToLastWeek: computeDeltas(weekData, prevWeek)
    )
}

func generateFallbackTitle(_ data: WeekData) -> String {
    if data.avgScore >= 90 { return "Dominant week across the board" }
    if data.avgScore >= 75 { return "Solid week with room to grow" }
    if data.avgScore >= 60 { return "Average week -- time to lock in" }
    return "Below the line -- reset starts now"
}
```

### 8.3 Pattern Detection Fallback

**Local statistical computation. Pearson correlations calculated in Swift/PostgreSQL. Behavioral patterns via threshold analysis.**

```swift
func computeFallbackPatterns(days: [DailySnapshot]) -> [Pattern] {
    var patterns: [Pattern] = []

    // Compute Pearson correlations for all known pairs
    let correlationPairs: [(KeyPath<DailySnapshot, Double?>, KeyPath<DailySnapshot, Double?>, String, String)] = [
        (\.sleepHours, \.nextDayRecovery, "Sleep hours", "Next-day recovery"),
        (\.recoveryScore, \.studyMinutes, "Recovery", "Study time"),
        // ... all pairs from Section 6.4 of MODULE_DASHBOARD.md
    ]

    for (pathA, pathB, nameA, nameB) in correlationPairs {
        let (r, n) = pearsonCorrelation(days, pathA, pathB)
        if abs(r) >= 0.5 && n >= 10 {
            patterns.append(Pattern(
                type: .correlation,
                trigger: nameA,
                outcome: nameB,
                confidence: abs(r),
                correlation: r,
                occurrences: n
            ))
        }
    }

    // Behavioral patterns via threshold analysis
    let lowSleepDays = days.filter { ($0.sleepHours ?? 8) < 6.5 }
    let normalSleepDays = days.filter { ($0.sleepHours ?? 8) >= 6.5 }
    if lowSleepDays.count >= 5 {
        let lowSleepStudyAvg = lowSleepDays.compactMap(\.studyMinutes).average()
        let normalStudyAvg = normalSleepDays.compactMap(\.studyMinutes).average()
        let diff = (normalStudyAvg - lowSleepStudyAvg) / normalStudyAvg
        if diff >= 0.2 {
            patterns.append(Pattern(
                type: .behavioral,
                trigger: "Sleep < 6.5h",
                outcome: "Study time drops \(Int(diff * 100))%",
                confidence: min(diff + 0.3, 1.0),
                occurrences: lowSleepDays.count
            ))
        }
    }

    return patterns.sorted { $0.confidence > $1.confidence }.prefix(6).map { $0 }
}
```

### 8.4 Drill Sergeant Notifications Fallback

**Pre-written copy bank with template substitution.**

```swift
struct NotificationCopyBank {
    // 10 variations per channel, randomly selected with data substitution.
    static let gentleReminder: [String] = [
        "Afternoon. {{remaining_count}} tasks left. Study: {{study_remaining}} of {{study_target}}. You've got {{hours_until_evening}} hours. Start now.",
        "Check-in. {{completed_count}} done, {{remaining_count}} to go. The day isn't over. Open the app and knock one out.",
        "{{remaining_tasks}} still waiting. {{hours_until_evening}} hours of daylight left. More than enough. Pick one and start.",
        // ... 7 more variations
    ]

    static let firmWarning: [String] = [
        "5 PM. {{remaining_count}} tasks incomplete. {{specific_task}} hasn't been touched. Your evening starts in {{hours_until_evening}} hours. Move.",
        "Time check: 5 PM. {{study_remaining}} of study missing. {{meals_remaining}} meals not logged. The clock doesn't wait for motivation.",
        // ... 8 more variations
    ]

    // ... similar for all 6 channels

    static func render(_ template: String, context: NotificationContext) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{{remaining_count}}", with: "\(context.remainingCount)")
        result = result.replacingOccurrences(of: "{{study_remaining}}", with: "\(context.studyRemaining)min")
        result = result.replacingOccurrences(of: "{{study_target}}", with: "\(context.studyTarget)min")
        result = result.replacingOccurrences(of: "{{hours_until_evening}}", with: "\(context.hoursUntilEvening)")
        // ... all substitutions
        return result
    }
}
```

### 8.5 Training Program Fallback

**Rule-based PPL generator using the existing TrainingEngine logic (which was the v0 implementation before AI).**

The current `TrainingEngine.swift` already generates workout plans without AI. It uses:
- Recovery zone to set volume multiplier
- Day-of-week + football schedule to determine split
- Progressive overload rules from the last 2 sessions
- Exercise library with equipment filters

When AI is unavailable, the app seamlessly uses this engine. The only thing lost is the natural language "coach note" on each day -- replaced with a static note based on recovery zone.

### 8.6 Recovery Prescription Fallback

**Rule-based prescription engine (existing RecoveryEngine).**

```swift
func generateFallbackPrescription(whoop: WhoopData, schedule: DaySchedule) -> DailyPrescription {
    let prescription = DailyPrescription(date: .now)

    // Training recommendation
    switch whoop.recoveryZone {
    case .green:
        prescription.trainingRec = "Full send. \(schedule.workoutType) at full volume."
        prescription.trainingIntensity = .fullSend
        prescription.volumeAdjustment = 1.0
    case .yellow:
        prescription.trainingRec = "\(schedule.workoutType) at 80% volume. Maintain intensity, reduce total sets."
        prescription.trainingIntensity = .moderate
        prescription.volumeAdjustment = 0.8
    case .red:
        prescription.trainingRec = "Mobility and light movement only. 30 minutes max."
        prescription.trainingIntensity = .easy
        prescription.volumeAdjustment = 0.5
    }

    // Bedtime calculation
    let targetSleepHours = 7.5 + (whoop.sleepDebt > 2 ? 0.5 : 0)
    prescription.bedtimeTarget = Calendar.current.date(
        byAdding: .hour, value: -Int(targetSleepHours),
        to: schedule.targetWakeTime
    )!

    // Caffeine cutoff = bedtime - 8 hours
    prescription.caffeineCutoff = Calendar.current.date(
        byAdding: .hour, value: -8,
        to: prescription.bedtimeTarget
    )!

    // Hydration
    prescription.hydrationTargetMl = whoop.recoveryZone == .red ? 3500 : 3000

    // Warnings
    if whoop.hrvTrend == .declining && whoop.hrvDeclineDays >= 3 {
        prescription.warnings.append("HRV declining for \(whoop.hrvDeclineDays) days. Consider extra rest.")
    }
    if whoop.sleepDebt > 4 {
        prescription.warnings.append("Sleep debt exceeds 4 hours. Prioritize early bedtime.")
    }

    return prescription
}
```

### 8.7 Meal Timing Fallback

**Rule-based recommendations from NutriTrack data.**

```swift
func generateFallbackMealTiming(nutrition: NutritionStatus, training: TrainingSchedule) -> [MealRecommendation] {
    var recs: [MealRecommendation] = []

    // Post-workout window
    if let trainingTime = training.todayTime {
        let postWorkoutDeadline = trainingTime.addingTimeInterval(90 * 60) // 90 min
        recs.append(MealRecommendation(
            priority: 1,
            meal: "Post-workout",
            recommendation: "Eat within 90 minutes of training (by \(postWorkoutDeadline.formatted(.time))). Prioritize protein.",
            reason: "Muscle protein synthesis peaks in the post-workout window."
        ))
    }

    // Protein deficit check
    let proteinRemaining = nutrition.proteinTarget - nutrition.proteinConsumed
    if proteinRemaining > 30 {
        recs.append(MealRecommendation(
            priority: 2,
            meal: nutrition.nextMealName,
            recommendation: "You need \(proteinRemaining)g more protein today. Load up at \(nutrition.nextMealName).",
            reason: "Currently \(nutrition.proteinConsumed)g of \(nutrition.proteinTarget)g target."
        ))
    }

    return recs
}
```

### 8.8 Feature Degradation Matrix

| Feature | AI Available | AI Unavailable | User Experience Delta |
|---------|-------------|----------------|----------------------|
| Morning Briefing | Template-based (already free, no AI) | Same template | **Zero difference** -- morning briefing is template-first by design |
| Weekly Report | Natural language analysis, nuanced insights (Sonnet 4.6) | Statistical summary with template text | Loses "why" explanations, keeps "what" |
| Pattern Detection | Opus-interpreted correlations + multi-variable behavioral insights | Raw Pearson correlations + threshold patterns | Loses narrative insight and multi-variable interactions, keeps the data |
| Training Program | Exercise science reasoning, periodization context (Sonnet 4.6) | Rule-based PPL generation | Loses coach notes, keeps structure |
| Notifications | Varied, contextual, punchy copy (Sonnet 4.6) | Pre-written bank with dynamic substitution | Less varied over time, still effective |
| Recovery Prescription | Nuanced reasoning about combined factors (Haiku 4.5) | Rule-based thresholds | Loses nuance in edge cases |
| Dashboard Insights | Cross-domain insight connections (Haiku 4.5) | Rule-based pattern matching (from Section 6 of MODULE_DASHBOARD) | Fewer "aha" moments |
| Study Schedule | Optimized distribution considering all factors (Sonnet 4.6) | Even distribution across available days | Less intelligent scheduling |

### 8.9 Graceful Degradation Indicator

When any AI feature falls back to algorithmic mode, the user sees a subtle indicator:

```
┌─────────────────────────────────────────────┐
│ ℹ️  AI insights temporarily unavailable     │
│     Showing standard recommendations        │
│                                     [Retry] │
└─────────────────────────────────────────────┘
```

- Displayed as a small banner at the top of the affected view (not a modal, not blocking).
- Uses `secondaryLabel` color -- visible but not alarming.
- Includes a "Retry" button that attempts one AI call immediately.
- Disappears automatically when AI service recovers (circuit breaker closes).
- The banner is feature-specific: if Haiku is down but Sonnet is up, only Haiku-dependent features show the banner.

---

## 9. Responsible AI & Safety

This section consolidates all responsible AI practices. These are not optional -- they are requirements for App Store review, user trust, and regulatory compliance.

### 9.1 Core Principles

1. **AI insights are informational, not medical advice.** Tempo is a coaching tool, not a medical device. The AI must never diagnose, prescribe medication, or replace professional medical judgment.
2. **The app works without AI.** Every feature has an algorithmic fallback (Section 8). Users who opt out of AI or experience API failures get a fully functional app.
3. **Data minimization.** Send the LEAST data possible to Claude. No names (except opt-in first name), no emails, no location, no device IDs. Just numbers and dates.
4. **Transparency.** Users know when they are seeing AI-generated content and can opt out.
5. **No dark patterns.** The drill-sergeant tone is motivational, never psychologically harmful. It targets behaviors, never the person.

### 9.2 Prohibited AI Behaviors

The AI must NEVER:

| Category | Prohibited Behavior | Enforcement |
|----------|-------------------|-------------|
| Medical | Suggest seeing a doctor, diagnose conditions, recommend medication | System prompt `<rules>` + post-generation regex filter |
| Diet | Suggest caloric intake <1,500 kcal, suggest skipping meals, recommend fasting >16h | System prompt `<rules>` + output validation |
| Training | Suggest training through pain/injury, ignore red recovery, program >2h sessions | System prompt `<rules>` + validation rules |
| Supplements | Recommend any supplement, drug, or performance-enhancing substance | System prompt `<rules>` + regex filter |
| Body image | Comment on body appearance, use shaming language about physique | System prompt `<rules>` + regex filter |
| Mental health | Dismiss fatigue as weakness, frame rest as laziness, use guilt about skipping | System prompt tone guidelines |
| Data fabrication | Cite numbers not in the input data, invent trends, hallucinate correlations | XML data tags + server-side cross-reference + pre-computed stats |

### 9.3 Content Filter Pipeline

Every AI response passes through the filter in Section 7.4 BEFORE reaching the user. The filter is:
- **Always on.** Cannot be disabled by configuration.
- **Logged.** Every filter hit is logged (feature, pattern matched, full response) for prompt improvement.
- **Fail-safe.** If the filter itself errors, the response is blocked and fallback is used.

### 9.4 User Consent Flow

During onboarding, a dedicated "AI Features" consent screen (see Section 11.3 for the mockup). Key requirements:
- **Explicit opt-in.** AI features are OFF by default until the user enables them.
- **Plain language.** "Your health data (recovery scores, sleep, nutrition, study time) is sent to Anthropic's Claude AI to generate personalized insights."
- **What is NOT sent.** "We NEVER send your name, email, Apple ID, location, or any data that identifies you."
- **Revocable.** "You can disable AI features anytime in Settings > Privacy > AI Features."
- **Link to Anthropic's privacy policy.** Users can review how Anthropic handles API data.

### 9.5 Data Minimization Checklist

Before every API call, the prompt builder verifies:

| Field | Sent? | Justification |
|-------|-------|---------------|
| user_id | NEVER | No purpose in prompt |
| email | NEVER | No purpose in prompt |
| apple_id | NEVER | No purpose in prompt |
| device_id | NEVER | No purpose in prompt |
| location / GPS | NEVER | Not collected for AI |
| IP address | NEVER | Not included in prompt |
| full name | NEVER | No purpose in prompt |
| first name | OPT-IN ONLY | Notification personalization |
| friend first names | OPT-IN ONLY | Competitive notification copy |
| exam names | YES | Study schedule context (low PII risk) |
| timezone | YES | Time-based recommendations |
| All biometric numbers | YES | Core analysis data (no PII) |

---

## 10. Future AI Features (v2+)

### 10.1 Voice Coaching (v2)

**Text-to-speech of morning briefing.** Generate audio from the morning briefing text using Apple's AVSpeechSynthesizer (on-device, zero API cost) or a third-party TTS API for higher quality.

- **MVP:** AVSpeechSynthesizer with a male Australian English voice (firm, coach-like).
- **v2.1:** ElevenLabs API for custom drill-sergeant voice. Estimated cost: $0.30/1,000 characters. Morning briefing ~250 chars = $0.000075 per briefing = $0.002/month per user.

### 10.2 Photo Meal Logging (v2)

**Image to macro estimation via Claude Vision.**

User takes a photo of their meal. Image is sent to Claude with the prompt:

```
Analyze this food image. Estimate the meal's macronutrients.

Output JSON:
{
  "food_items": [
    {"name": "string", "portion": "string", "calories": number, "protein_g": number, "carbs_g": number, "fat_g": number}
  ],
  "total": {"calories": number, "protein_g": number, "carbs_g": number, "fat_g": number},
  "confidence": "high" | "medium" | "low",
  "notes": "string (any caveats about the estimation)"
}
```

- **Model:** Sonnet 4.6 (vision required for accuracy)
- **Estimated cost:** ~$0.01-0.02 per image (image tokens + output)
- **Monthly cost per user (2 photos/day):** ~$0.60-1.20/month

### 10.3 Conversational Coach (v2)

**Chat interface for free-form questions about training, nutrition, and recovery.**

A persistent conversation thread where the user can ask questions like:
- "Why was my recovery low today?"
- "Should I train legs today?"
- "What should I eat before my football game?"

The system prompt includes the user's recent data (last 7 days compressed) as persistent context. Each conversation turn uses ~2,000 input tokens + user message.

- **Model:** Sonnet 4.6 (requires reasoning)
- **Estimated cost:** ~$0.03-0.05 per message
- **Rate limit:** 10 messages per day per user
- **Monthly cost per user:** ~$0.90-1.50/month

### 10.4 AI Workout Variations (v2)

When a user has been doing the same program for 4+ weeks, generate variations that target the same muscle groups with different exercises, rep schemes, or training methods (drop sets, rest-pause, tempo work).

### 10.5 Predictive Recovery (v2)

**Forecast tomorrow's recovery based on today's behavior.**

Using the last 30-90 days as training data, build a lightweight on-device model (Core ML) that predicts tomorrow's recovery score based on today's:
- Sleep quality + duration
- Strain
- Nutrition compliance
- Previous recovery trend

This runs entirely on-device (zero API cost). Claude is used once to generate the explanation of the prediction: "Your predicted recovery tomorrow is 68%. Here's why: high strain today (14.2) combined with below-target sleep (6.5h) typically leads to moderate recovery for you."

### 10.6 Smart Notification Timing (v2)

Use the user's behavioral data to optimize notification send times. If the user consistently ignores 2 PM notifications but responds to 3 PM notifications, shift the gentle reminder to 3 PM. This is algorithmic (no AI API calls), but the notification copy is still AI-generated.

---

## 11. Privacy Considerations

### 11.1 Data Sent to Anthropic

| Data Category | Sent to Claude | Purpose | Anonymized |
|---------------|----------------|---------|-----------|
| Recovery scores | Yes | Analysis, prescriptions | N/A (no PII) |
| HRV, RHR, sleep data | Yes | Analysis, prescriptions | N/A (no PII) |
| Workout data (type, strain, duration) | Yes | Training programming | N/A (no PII) |
| Nutrition (calories, macros, meal count) | Yes | Nutrition recommendations | N/A (no PII) |
| Study sessions (duration, subject, focus) | Yes | Study scheduling | N/A (no PII) |
| Streak count, XP, level | Yes | Motivational context | N/A (no PII) |
| Timezone | Yes | Time-based recommendations | Low risk |
| First name | Yes (opt-in only) | Notification personalization | User consent required |
| Friend first names | Yes (opt-in only) | Competitive notifications | User consent required |
| Exam names | Yes | Study schedule context | Low risk |
| User ID | **NO** | -- | Stripped |
| Email | **NO** | -- | Stripped |
| Apple ID | **NO** | -- | Stripped |
| Device ID | **NO** | -- | Stripped |
| Location / GPS | **NO** | -- | Never collected for AI |
| IP address | **NO** | -- | Not sent in prompt |

### 11.2 Anthropic Data Retention Policy

Per Anthropic's API Terms of Service (as of March 2026):
- API inputs and outputs are NOT used to train Claude models.
- Anthropic retains API logs for up to 30 days for abuse monitoring and safety, unless the customer opts into zero-retention.
- Tempo should evaluate Anthropic's zero-retention API option for health data.

**Recommendation:** Enable zero-retention if available, given that health/biometric data (even anonymized) is sensitive.

### 11.3 User Consent

> **APP STORE COMPLIANCE (Guideline 5.1.2(i), November 2025):**
> This consent screen MUST comply with Apple's AI data sharing requirements:
> 1. It MUST explicitly name "Anthropic" and "Claude" -- not generic "AI service."
> 2. It MUST be a SEPARATE, DEDICATED screen -- NOT bundled with HealthKit, Whoop, or notification permissions.
> 3. The "Continue without AI" option MUST have equal visual weight to "Enable AI Insights."
> 4. The user MUST be able to use the full app without AI features (all fallbacks in Section 8 must work).
> 5. AI features MUST be OFF by default until the user explicitly enables them on this screen.
> See `docs/APP_STORE_COMPLIANCE.md` Section 1 for the full compliance specification.

During onboarding, a dedicated "AI Features" consent screen:

```
┌──────────────────────────────────────┐
│                                      │
│  AI-Powered Insights                 │
│                                      │
│  Tempo can use Anthropic's Claude    │
│  AI to generate personalized         │
│  insights from your data:            │
│                                      │
│  - Weekly performance reports        │
│  - Pattern detection across your     │
│    training, sleep, and nutrition    │
│  - Recovery-aware coaching           │
│  - Personalized notification copy    │
│                                      │
│  How it works:                       │
│  Your health metrics (recovery       │
│  scores, sleep, nutrition, study     │
│  time) are sent to Anthropic's       │
│  Claude API to generate insights.    │
│  Data is anonymized -- we NEVER      │
│  send your name, email, Apple ID,    │
│  or any identifying information.     │
│                                      │
│  Anthropic's commitment:             │
│  Per Anthropic's API Terms, your     │
│  data is NOT used to train AI        │
│  models. Data is retained for up     │
│  to 30 days for safety monitoring.   │
│                                      │
│  Your rights:                        │
│  • Disable AI anytime in Settings    │
│  • App works fully without AI        │
│  • AI insights are not medical       │
│    advice                            │
│                                      │
│  [Learn more about Anthropic's       │
│   privacy practices]                 │
│                                      │
│  [ Enable AI Insights ]              │
│  [ Continue without AI ]             │
│                                      │
│  You can change this anytime in      │
│  Settings > Privacy > AI Features.   │
│                                      │
└──────────────────────────────────────┘
```

**Implementation requirements:**
- Both buttons MUST have equal visual weight. "Continue without AI" must NOT be styled as a dismissible text link -- it must be a visible, tappable button.
- Every `AIService` method MUST check `UserConsentManager.aiConsentGranted` before making any API call. If false, return the fallback response (Section 8).
- Consent timestamp and version must be recorded and stored for GDPR audit trail.

### 11.4 Opt-Out Behavior

When AI features are disabled:
- All AI features switch to fallback mode (Section 8).
- No data is sent to Anthropic.
- Weekly reports use template-based generation.
- Pattern detection uses local Pearson correlations.
- Notifications use pre-written copy bank.
- Training and recovery use rule-based engines.
- Dashboard insights use rule-based pattern matching (Section 6 of MODULE_DASHBOARD.md).

The app is fully functional without AI. AI adds personality, nuance, and cross-domain insights, but the core functionality (tracking, scoring, notifications, training) works entirely without it.

### 11.5 Data Deletion

When a user deletes their account (Section 3.6 of BACKEND_API.md):
- All entries in the `insights` table for that user are hard-deleted.
- All cached AI responses in Redis for that user are evicted.
- Anthropic does not retain a mapping from our API calls to specific users (we never send user IDs).
- A confirmation is sent: "Your AI-generated insights have been permanently deleted."

### 11.6 App Store Privacy Labels

Under "Data Used to Track You": **None.**

Under "Data Linked to You":
- Health & Fitness (HealthKit data, Whoop data)
- Note: the privacy nutrition label should disclose that health data is processed by a third-party AI service (Anthropic) for generating insights, with no PII attached.

### 10.7 HIPAA Considerations

Tempo is not a HIPAA-covered entity (it is not a healthcare provider, health plan, or clearinghouse). However, best practices apply:
- Health data is encrypted in transit (TLS 1.3) and at rest (AES-256 in PostgreSQL, SwiftData encryption).
- AI prompts contain anonymized health metrics only.
- Access to AI response logs is restricted to the user who generated them.
- If Tempo ever partners with healthcare providers or insurers, a full HIPAA compliance audit would be required.

---

## Appendix A: Token Counting Reference

Approximate token counts for common data structures:

| Data Structure | Characters | Tokens (approx) | Notes |
|---------------|-----------|-----------------|-------|
| 1 day of recovery data (formatted) | 80 | 20 | `"2026-03-24 (Mon): Recovery 72%, HRV 58ms, RHR 62bpm"` |
| 1 day of sleep data | 120 | 30 | Includes bedtime, wake, efficiency |
| 1 workout entry | 100 | 25 | Type, strain, duration, HR |
| 1 day of nutrition data | 130 | 32 | Calories, protein, carbs, fat, meals |
| 1 study session | 70 | 18 | Minutes, subject, focus |
| 1 accountability day | 60 | 15 | Completed/total, score |
| 7 days full data (weekly report) | ~4,000 | ~1,000 | All data sources combined |
| 30 days compressed (pattern detection) | ~6,000 | ~1,500 | Pipe-delimited format |
| 90 days compressed (pattern detection) | ~18,000 | ~4,500 | Pipe-delimited format |
| Exercise library (50 exercises) | ~3,000 | ~750 | Name, muscle group, equipment |
| System prompt (average) | ~1,500 | ~375 | Varies by feature |

## Appendix B: Error Codes

| Code | HTTP | Description | Action |
|------|------|-------------|--------|
| 5001 | 400 | Invalid AI request (missing required data) | Fix request, do not retry |
| 5002 | 400 | Insufficient data for analysis (need more days) | Inform user, suggest waiting |
| 5003 | 429 | Daily AI insight limit reached for this user | Use fallback, reset at midnight |
| 5004 | 503 | Claude API unavailable | Use fallback, retry next trigger |
| 5005 | 503 | Monthly AI budget exhausted | Use fallback until month resets |
| 5006 | 500 | AI response failed validation (3 attempts) | Use fallback, log for review |
| 5007 | 500 | AI response contained harmful content | Use fallback, log for review |

## Appendix C: Monitoring & Observability

| Metric | Type | Alert Threshold |
|--------|------|-----------------|
| `claude_api_latency_ms` | Histogram | p99 > 10s (Haiku) or > 45s (Sonnet) |
| `claude_api_error_rate` | Counter | > 5% over 5 minutes |
| `claude_api_cost_cents` | Counter (monthly) | > 80% of budget |
| `claude_api_retry_rate` | Counter | > 10% of calls require retry |
| `ai_fallback_activations` | Counter | > 0 (alert on any fallback) |
| `ai_validation_failures` | Counter | > 5% of responses fail validation |
| `ai_hallucination_flags` | Counter | > 0 (alert on any flag) |
| `ai_harmful_content_flags` | Counter | > 0 (alert on any flag, P0) |
| `ai_user_feedback_negative_rate` | Gauge | > 30% negative over 7 days |
| `ai_cache_hit_rate` | Gauge | < 60% (suggests caching is not working) |
