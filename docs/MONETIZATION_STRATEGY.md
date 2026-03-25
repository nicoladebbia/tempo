# Tempo — Monetization & Business Strategy

> **Version:** 1.0
> **Last Updated:** 2026-03-24
> **Author:** Product Strategy Spec
> **Audience:** Founder, investors, future team members

---

## Table of Contents

1. [Market Analysis](#1-market-analysis)
2. [Monetization Model Options](#2-monetization-model-options)
3. [Free vs Premium Feature Split](#3-free-vs-premium-feature-split)
4. [Paywall Design](#4-paywall-design)
5. [Subscription Infrastructure](#5-subscription-infrastructure)
6. [Revenue Projections](#6-revenue-projections)
7. [Cost Structure](#7-cost-structure)
8. [Go-To-Market Strategy](#8-go-to-market-strategy)
9. [Growth Levers](#9-growth-levers)
10. [Retention Strategy](#10-retention-strategy)
11. [Legal Requirements for Monetization](#11-legal-requirements-for-monetization)

---

## 1. Market Analysis

### 1.1 Competitive Landscape

Tempo sits at the intersection of fitness tracking, nutrition, recovery intelligence, study accountability, and social gamification. No single competitor covers all five pillars, which is the core differentiation. However, users will compare Tempo against whichever slice they value most.

#### Direct Competitors — Detailed Breakdown

| App | Monthly Price | Annual Price | Free Tier | What's Gated Behind Paywall | Where Tempo Differentiates |
|-----|--------------|-------------|-----------|---------------------------|---------------------------|
| **Whoop** | $30/month (membership, includes band) | $239/year | No free tier — requires hardware purchase | Everything; the app is useless without the band | Tempo reads Whoop data but adds actionable prescriptions, training adjustments, and cross-domain intelligence. Whoop only shows metrics; Tempo tells you what to DO with them. |
| **Strong** | $4.99/month | $29.99/year | Log workouts (max 3 routines saved) | Unlimited routines, workout templates, export, Apple Watch, charts | Tempo's RepForge includes recovery-adjusted programming — Strong is a dumb logbook; Tempo is an intelligent coach that adapts every session to your Whoop data. |
| **Strava** | $11.99/month | $79.99/year | GPS tracking, activity logging, club feed | Route planning, training plans, segment leaderboards, beacon, heatmaps | Strava is cardio/endurance-focused. Tempo covers strength training, nutrition, and academics. Arena's social layer is tailored for accountability, not ride-sharing. |
| **Oura Ring** | $5.99/month (after hardware) | $69.99/year | Basic readiness score, sleep tracking | Sleep analysis details, long-term trends, blood oxygen, period prediction, guided meditations | Tempo integrates recovery data (from Whoop or HealthKit) and turns it into training/nutrition prescriptions. Oura shows you data; Tempo acts on it. |
| **Forest** | $3.99 one-time (iOS) | N/A | N/A (paid app) | N/A — full features included | Forest is a single-purpose focus timer. Tempo's Lockdown module integrates study time with your entire life system — non-negotiables, drill-sergeant escalation, and XP rewards for studying. |
| **Habitica** | $4.99/month (optional) | $47.99/year | Full gamification, habits, to-dos | Custom themes, extra drops, expanded group features | Habitica gamifies generic habits. Tempo gamifies real performance data — your actual workouts, actual meals, actual study hours. No self-reporting honor system. |
| **Streaks** | $4.99 one-time | N/A | N/A (paid app) | N/A | Streaks tracks up to 24 habits via manual check-off. Tempo auto-verifies completion via integrations (Whoop confirms training, NutriTrack confirms meals, timer confirms study). |
| **MyFitnessPal** | $9.99/month | $79.99/year | Calorie logging, basic macros | Barcode scanner, meal plans, nutrient breakdown, intermittent fasting tracker, premium recipes | Tempo delegates nutrition to NutriTrack (already built, AI-powered, Claude coaching). MFP is a food database; NutriTrack + Tempo is an intelligent nutrition system tied to your recovery and training. |
| **Fitbod** | $12.99/month | $79.99/year | 3 free workouts | Unlimited workouts, muscle recovery tracking, progressive overload, Apple Watch | Fitbod generates workouts but ignores your Whoop recovery, football schedule, and exam week. Tempo's RepForge adapts volume/intensity to your actual physiological state. |
| **Notion** | $10/month (Plus) | $96/year | Basic workspace | Unlimited blocks, file uploads, API access, databases | Some users build life dashboards in Notion. But Notion is manual — zero integration with biometric data, no push notifications, no gamification, no mobile-native experience. |
| **Rise (Sleep)** | $4.99/month | $59.99/year | 7-day trial | Sleep debt tracking, energy schedule, smart alarm | Rise focuses exclusively on sleep. Tempo's RecoverIQ integrates sleep with training, nutrition, and schedule to give holistic prescriptions. |
| **Gentler Streak** | $4.99/month | $19.99/year | Basic activity tracking | Readiness scores, workout suggestions, Apple Watch, rest day recommendations | Gentler Streak encourages rest. Tempo's drill-sergeant personality does the opposite — it pushes you while respecting recovery data. Different philosophy entirely. |
| **Centered** | $9.99/month | $79.99/year | Basic focus sessions | AI flow coach, music, team features | Focus app for deep work. Lacks fitness, nutrition, recovery, and social gamification. |

#### Competitive Positioning Summary

```
                    SINGLE-PURPOSE ←──────────────→ ALL-IN-ONE
                         │                               │
    PASSIVE DATA         │                               │
    (shows metrics)      │    Oura    Whoop             │
                         │    Rise    Strava             │
                         │                               │
                         │    MFP     Fitbod             │
                         │    Strong  Gentler Streak     │
                         │                               │
                         │    Forest  Notion             │
                         │    Streaks Habitica           │
    ACTIVE COACHING      │                               │
    (tells you what      │                               │
     to do)              │                     ★ TEMPO   │
                         │                               │
```

Tempo's unique position: **all-in-one + active coaching**. No competitor occupies this quadrant. The risk is that all-in-one apps often fail because they're mediocre at everything. Tempo must be genuinely good at each pillar to justify the breadth.

### 1.2 Pricing Benchmarks

| Category | Price Range (Monthly) | Price Range (Annual) | Notes |
|----------|----------------------|---------------------|-------|
| Fitness logging | $4.99 - $12.99 | $29.99 - $79.99 | Strong, Fitbod, Hevy |
| Recovery/sleep | $5.99 - $30.00 | $59.99 - $239.00 | Oura, Whoop, Rise |
| Focus/productivity | $3.99 - $9.99 (one-time to monthly) | $47.99 - $79.99 | Forest, Centered, Habitica |
| Nutrition tracking | $9.99 - $19.99 | $79.99 - $199.99 | MFP, MacroFactor, Carbon Diet |
| All-in-one fitness | $14.99 - $19.99 | $99.99 - $149.99 | Future, Caliber, Juggernaut AI |

**Key insight:** Apps that combine AI coaching with data integration charge $10-20/month (Caliber, Juggernaut AI, Future). Apps that are "just logging" charge $5-10/month. Tempo is closer to the AI coaching category but needs to price for students.

### 1.3 Target Demographic — Willingness to Pay

**Primary audience:** University students and young professionals (18-28), active, fitness-conscious, struggling with time management.

**Financial reality:**
- Average US college student disposable income: $200-400/month after essentials
- Already paying for: Spotify ($5.99 student), Netflix ($6.99-$15.49), gym ($10-50/month), maybe a meal delivery app
- "App subscription fatigue" is real — the average Gen Z user has 3-4 paid app subscriptions
- Price sensitivity threshold: $5/month is "no-brainer," $10/month requires justification, $15/month is "I'll think about it," $20/month is "probably not"

**Willingness-to-pay signals:**
- Students WILL pay for apps that directly impact their grade/body/social status
- Fitness apps have the highest retention and conversion rates in the App Store (Strava: 8% conversion, Calm: 5%)
- Social pressure (leaderboards, friends) dramatically increases willingness to pay
- A "student discount" signals respect for the demographic and reduces friction

**Conclusion:** $4.99/month ($39.99/year) is the sweet spot. It undercuts most fitness apps, feels manageable on a student budget, and the annual price ($3.33/month effective) is less than a single coffee at Starbucks.

---

## 2. Monetization Model Options

### Option A: Freemium + Subscription (RECOMMENDED)

**Description:** Core experience is free forever. Premium subscription unlocks AI features, unlimited social, advanced analytics, and power-user tools.

**Free tier includes:**
- Dashboard with basic quadrant view (today only)
- Basic workout logging (manual entry, no AI programming)
- 3 non-negotiables per day
- Basic focus timer
- Recovery score view (if Whoop connected)
- XP and levels
- Leaderboard (view only, 5 friend limit)
- 1 active challenge at a time
- Basic streak tracking

**Pro tier ($4.99/month or $39.99/year) includes:**
- Everything in Free, plus:
- AI-powered workout programming (recovery-adjusted)
- Weekly AI report with pattern detection
- Historical trends and correlation analysis
- Unlimited non-negotiables
- Drill sergeant savage mode (escalating notifications)
- Full recovery prescription engine
- Sleep detail analysis and trends
- Unlimited friends
- Unlimited active challenges
- Custom challenges (create your own)
- Full achievement collection
- Progress charts for all exercises
- Exercise library (full catalog)
- Exam mode
- Export data
- Priority support

**Pros:**
- Proven model in fitness (Strong, Strava, Fitbod all use this)
- Free tier builds word-of-mouth and user base
- Low barrier to entry — critical for students
- Recurring revenue is predictable and valued by investors
- Annual pricing reduces churn and increases LTV
- Free users still generate social value (more leaderboard participants = more fun for paying users)

**Cons:**
- Must deliver enough free value to retain users long enough to convert
- Feature split is delicate — too much free and nobody upgrades; too little and nobody stays
- Server costs exist for free users too (Claude API, backend, push notifications)

**Student discount option:** $3.99/month ($29.99/year) with .edu email verification. This captures the price-sensitive segment while maintaining a higher standard price for young professionals post-graduation. Apple supports educational pricing through promotional offers.

---

### Option B: One-Time Purchase

**Price point:** $14.99 - $29.99

**Pros:**
- Simple value proposition — pay once, own forever
- Attractive to students who hate subscriptions
- No "subscription fatigue" objection

**Cons:**
- Tempo requires a Vapor backend (PostgreSQL, push notifications, Whoop proxy, Arena leaderboards, Claude API). Server costs are ONGOING. A one-time purchase does not fund a backend.
- No recurring revenue means no sustainable business
- Claude API costs are per-call — every AI insight costs real money. With 10,000 users generating weekly reports, that is $500-2,000/month in API costs alone with zero recurring income after the initial purchase
- App Store visibility decays without ongoing revenue to fund marketing
- Updates and maintenance become charity work after 12 months

**Verdict:** Not viable for Tempo. The backend dependency makes this a non-starter. Every free user is a cost center, and without recurring revenue, the math never works.

---

### Option C: Free + Tips/Donations

**Price point:** N/A (voluntary)

**Pros:**
- Zero friction
- Builds goodwill

**Cons:**
- Typical tip conversion rates: 1-3% of users
- Average tip: $2-5
- At 10,000 users: maybe $200-500/month in donations. Backend alone costs more.
- Not a business model. This is a hobby funding strategy.
- Users do not tip productivity/fitness apps. They tip creators (Twitch, Patreon, YouTube). Different psychological contract.

**Verdict:** Not viable. Tempo has real infrastructure costs that goodwill cannot cover.

---

### Option D: Free Now, Monetize Later

**Description:** Launch 100% free. Build a user base. Add premium features in v2.

**Pros:**
- Maximum adoption speed
- No paywall friction during critical early growth
- Users become advocates before being asked to pay
- Can learn which features users value most before deciding what to gate

**Cons:**
- Users who get features for free will resist paying for them later. This is the #1 killer of this strategy. Reddit's IPO struggles, Twitter Blue's rocky launch, and countless indie apps prove this pattern.
- You must fund server costs during the free period. At 1,000 daily active users, that is $50-200/month with zero revenue.
- Setting the expectation of "free" creates a vocal minority who will 1-star review when you add a paywall
- The transition from free to paid is traumatic for communities. Goodwill evaporates.
- Clock is ticking: every month without revenue is runway burning

**Verdict:** Risky but partially viable as a SHORT-TERM strategy (4-8 weeks of TestFlight beta / soft launch with everything free). Then introduce the paywall before public launch. Never launch on the App Store with everything free if the plan is to charge later.

---

### RECOMMENDATION: Option A — Freemium + Subscription

**Price: $4.99/month | $39.99/year**

**Deep justification:**

1. **$4.99 hits the psychological sweet spot.** It is:
   - Below the "requires justification" threshold for students ($10+)
   - The same price as a single fancy coffee — easy to frame in marketing
   - Competitive with Strong ($4.99) and Gentler Streak ($4.99), which offer far less
   - Below Fitbod ($12.99), MFP ($9.99), and Strava ($11.99), which Tempo outscopes

2. **Annual pricing at $39.99 ($3.33/month effective) drives commitment.**
   - 33% discount vs monthly — standard in the industry
   - Annual subscribers churn at 20-30% vs 50-60% for monthly (industry data from RevenueCat's State of Subscriptions 2025)
   - $39.99 is below the $50 psychological barrier
   - Presented as "$3.33/month, billed annually" — cheaper than a protein bar

3. **The free tier must be genuinely useful** — not a crippled demo. A student should be able to use Tempo daily without paying and still get value. The premium tier adds intelligence (AI), depth (analytics), and social scale (unlimited friends/challenges). Free users are not second-class citizens; they are future customers and active participants in the social ecosystem.

4. **The AI features justify the subscription.** Claude API calls cost real money. Gating AI-powered features (weekly reports, workout programming, pattern detection, recovery prescriptions) behind Pro is both economically necessary and easy to justify to users — "the AI that makes Tempo smart" is a tangible value proposition.

5. **Social features create natural upgrade pressure.** When a free user hits the 5-friend limit or wants to create a custom challenge, the upgrade path is obvious and desire-driven, not arbitrary.

---

## 3. Free vs Premium Feature Split

The guiding philosophy: **Free gets you hooked. Pro makes you unstoppable.**

Free tier must pass the "would I use this every day?" test. Pro tier must pass the "is this worth $4.99 to me?" test.

### 3.1 Dashboard (LifeOS)

| Feature | Tier | Justification |
|---------|------|---------------|
| 4-quadrant view (today) | **Free** | This IS the app. Gating the home screen kills day-one retention. Users must see the value proposition immediately. |
| Daily score calculation | **Free** | The score is the core engagement loop. Every user needs to see their number and want it higher. |
| Tap to expand each quadrant (today's detail) | **Free** | Users need to drill into today's data to understand what's happening. Blocking this makes the dashboard feel hollow. |
| Weekly AI report | **Pro** | This is the killer feature — Claude analyzing your week, finding patterns, giving personalized advice. It costs real money (API calls) and delivers premium value. Show a blurred preview with "Unlock your weekly intelligence report" to create desire. |
| Pattern detection / correlation analysis | **Pro** | "Your sleep drops 14% on days you skip lunch" — this is the insight engine that justifies the subscription. Complex AI analysis that costs tokens and delivers genuine intelligence. |
| Historical trends (7/30/90 day views) | **Pro** | Free users see today. Pro users see the arc of their progress. This is a classic soft gate — show the 7-day chart with a blur on 30/90 day. |
| Daily timeline view | **Free** | Shows chronological view of the day. Low cost, high engagement. |
| Quick actions (log meal, start workout, start timer) | **Free** | These are entry points to core features. Blocking quick actions creates friction in the daily loop. |
| Home screen widgets | **Pro** | Widgets are a "pro" perk that is visible on the user's home screen — a constant reminder of premium status. Also reduces the need to open the app, which could hurt engagement metrics for free users (counterintuitively, gating widgets is fine). |

### 3.2 Training (RepForge)

| Feature | Tier | Justification |
|---------|------|---------------|
| Basic workout logging (manual entry) | **Free** | This is the minimum viable training feature. Users tap exercises, enter sets/reps/weight. Without this, Tempo is not a fitness app. Strong offers this free. |
| Exercise library (50 exercises) | **Free** | Enough to cover the basics: bench, squat, deadlift, pull-ups, rows, curls, etc. Users can build workouts from this starter set. |
| Exercise library (full catalog, 200+) | **Pro** | The full library with variations, alternatives, cable work, machines, isolation movements. "Unlock 150+ exercises" is an easy upsell. |
| AI-powered workout programming | **Pro** | This is the core Pro training feature. Claude/algorithm generates your PPL split, adjusts for recovery, avoids conflicts with football schedule. This is what makes RepForge different from Strong. Costs API tokens. |
| Recovery-based workout adjustment | **Pro** | "Your Whoop shows 42% recovery — reducing volume 20% today." This requires Whoop integration logic and is the signature intelligence feature. |
| Progressive overload tracking | **Free (basic) / Pro (smart)** | Free: see your last weight/reps for each exercise. Pro: algorithm suggests target weight increases, predicts 1RM, shows periodization. |
| Progress charts (per exercise) | **Pro** | Weight-over-time charts, volume trends, estimated 1RM curves. These are the visualizations that make training data meaningful over time. Retention-driving feature worth gating. |
| Week plan view | **Pro** | Seeing your 7-day training plan requires the AI programming engine to generate it. Free users log workouts ad-hoc; Pro users get a plan. |
| Running / cardio features | **Free (basic logging) / Pro (structured plans)** | Free: log a run manually with distance/time. Pro: interval plans, pace targets, running combined with strength periodization. |
| Workout history (last 30 days) | **Free** | Users need to see recent workouts. 30 days is enough for continuity. |
| Workout history (unlimited) | **Pro** | Full archive going back months/years. Low cost to store, meaningful for serious users. |
| Rest timer | **Free** | Basic utility during workouts. Blocking this makes the workout experience frustrating. |
| Superset support | **Pro** | Power-user feature that adds complexity to logging. Nice upsell for experienced lifters. |
| Workout templates (save up to 3) | **Free** | Same as Strong's model. 3 templates covers a basic PPL split. |
| Workout templates (unlimited) | **Pro** | Power users with many routines (summer/winter splits, deload weeks, etc.). |
| Post-workout summary with analytics | **Pro** | Total volume, muscle group breakdown, intensity metrics, comparison to last session. The summary screen becomes a reason to subscribe. |

### 3.3 Accountability (Lockdown)

| Feature | Tier | Justification |
|---------|------|---------------|
| Non-negotiables (up to 3) | **Free** | Three non-negotiables is the core experience: Train, Study, Eat. This covers the primary use case without overwhelming. |
| Unlimited non-negotiables | **Pro** | Power users who want to track 5-7 daily tasks. Natural expansion. |
| Focus timer (basic Pomodoro) | **Free** | 25/5 minute timer with session logging. This is the "hook" for students — they need this daily. Blocking it kills the study accountability value proposition. |
| Focus timer (custom durations, break ratios, ambient sounds) | **Pro** | Customization and polish. 45/15 timers, adjustable break ratios, white noise. |
| Drill sergeant notifications (basic — 2 per day) | **Free** | Two reminders at fixed times: afternoon check-in and evening warning. Enough to demonstrate the personality. |
| Drill sergeant notifications (savage mode — full escalation) | **Pro** | The complete 5-stage escalation system from gentle to aggressive. Custom notification times. This is the "personality" of Tempo and a strong Pro selling point. "Upgrade to unleash the full drill sergeant." |
| Streak tracking (current streak) | **Free** | See your current streak count. Essential for retention — the "don't break the chain" mechanic must be free. |
| Streak calendar heatmap (historical) | **Pro** | The full calendar view showing every day's completion status, longest streaks, patterns. Beautiful visualization that free users can glimpse but not access. |
| Auto-verification (Whoop confirms training, NutriTrack confirms meals) | **Pro** | This integration logic is what makes non-negotiables feel magical. Free users check off tasks manually; Pro users get auto-verification. "Your workout was automatically verified by Whoop" is a premium experience. |
| PS5/leisure unlock mechanism | **Free** | The "leisure earned, not default" concept is part of the free experience. It is the app's philosophy. |
| Exam mode | **Pro** | Temporary schedule override for exam weeks with increased study targets, reduced training expectations, and survival-mode XP. This is a premium feature targeting the exact moment students feel the most pain — exam season — when they are most likely to convert. |
| Study analytics (time per subject, trends) | **Pro** | Detailed study breakdowns. Which subjects get the most time? What time of day is most productive? Pro-level insights. |

### 3.4 Recovery (RecoverIQ)

| Feature | Tier | Justification |
|---------|------|---------------|
| Recovery score display (today) | **Free** | If a user connects Whoop, they should see today's number. This is data they already own. Blocking it would feel like holding their data hostage. |
| Recovery zone indicator (green/yellow/red) | **Free** | Simple traffic light. Low cost, high value. Part of the daily dashboard. |
| Full prescription engine | **Pro** | "Based on your 42% recovery, skip heavy legs today. Eat extra carbs. Be in bed by 10:30 PM. Cut caffeine by 2 PM." This is the intelligence layer that turns raw Whoop data into actionable prescriptions. Costs API processing and is the core RecoverIQ value prop. |
| Sleep detail (stages, efficiency, debt) | **Pro** | Granular sleep breakdown beyond what the free dashboard shows. Duration + quality chart, sleep stage pie chart, debt tracking. |
| Recovery trends (7/30/90 days) | **Pro** | Historical recovery patterns. "Your HRV has been declining for 2 weeks" — this kind of trend analysis requires data retention and visualization. |
| Bedtime recommendation | **Pro** | Calculated from sleep debt, next-day schedule, and recovery needs. Personalized and costs computation. |
| Caffeine cutoff time | **Pro** | Part of the prescription engine. Small feature but signals the depth of Pro. |
| Hydration target | **Free (basic)** | A static recommendation (2L/day) is free. The strain-adjusted, recovery-aware hydration target is Pro. |
| Recovery-nutrition cross-recommendations | **Pro** | "Your recovery is low — add 200 extra calories today, focus on carbs." Requires NutriTrack integration and AI reasoning. |
| Prescription follow-through tracking | **Pro** | "Did you follow yesterday's prescription?" with outcome analysis. "When you follow prescriptions, your next-day recovery is 12% higher." |

### 3.5 Arena (ClutchTime)

| Feature | Tier | Justification |
|---------|------|---------------|
| XP earning from all activities | **Free** | XP is the core gamification loop. Every user must earn XP to feel progress. Gating XP kills the game. |
| Levels and level-up animations | **Free** | Levels are the visible progression system. The dopamine hit of leveling up keeps users coming back. Must be free. |
| Personal stats view | **Free** | Your own XP, level, daily/weekly totals. This is your "player card." |
| Leaderboard (view, 5-friend limit) | **Free** | Enough friends for a small friend group. The leaderboard with 5 people is fun and creates competitive tension. The limit creates natural upgrade pressure when they want to add more friends. |
| Unlimited friends | **Pro** | Remove the 5-friend cap. For users in a larger friend group, frat, sports team, or study group. "Add your whole squad — unlimited friends with Pro." |
| Challenges (1 active at a time) | **Free** | One active challenge lets free users taste the competition feature. They can join a "Most Study Hours This Week" challenge and compete. |
| Unlimited active challenges | **Pro** | Serious competitors want to run multiple challenges simultaneously. Power users. |
| Custom challenges (create your own) | **Pro** | Creating challenges is a premium action. Free users can join challenges; Pro users can create them. This gives Pro users social power. |
| Achievements / badges (basic set, 10 badges) | **Free** | Starter achievements: "First Workout," "7-Day Streak," "100 XP Day." Enough to demonstrate the system. |
| Full achievement collection (50+ badges) | **Pro** | The complete badge collection with rare, secret, and challenge-specific badges. Completionists will pay for this. |
| Streak multiplier (XP bonus for consecutive days) | **Free (basic, up to 1.5x)** | Free users get a streak multiplier up to 1.5x (7-day streak). This drives daily retention without costing anything. |
| Extended streak multiplier (up to 3x) | **Pro** | Pro users can build multipliers up to 3x with 30+ day streaks. Higher ceiling, more reward for consistency. |
| Social feed (friend activity) | **Pro** | Seeing what friends are doing in real-time. "Marco just crushed a leg day." This is a retention powerhouse and a premium social feature. |
| Share cards (workout summary, achievement) | **Free** | Shareable cards are VIRAL MARKETING. Free users sharing their workout cards on Instagram/TikTok is free advertising. Never gate viral features. |
| Arena notifications ("Marco just passed you!") | **Pro** | Competitive pressure notifications that drive engagement. "You dropped to #3 on the weekly leaderboard." These require backend processing and are high-value. |
| Season rewards / end-of-month rankings | **Pro** | Monthly competitive season with rewards for top performers. Exclusive badges, streak protectors, etc. |

### 3.6 Feature Split Summary

| Module | Free Features | Pro Features |
|--------|--------------|-------------|
| **Dashboard** | 4-quadrant today view, daily score, quick actions, timeline | Weekly AI report, pattern detection, historical trends, widgets |
| **Training** | Manual logging, 50 exercises, 3 templates, rest timer, 30-day history | AI programming, full library, progress charts, week plan, superset, unlimited templates/history |
| **Accountability** | 3 non-negotiables, basic timer, 2 notifications/day, current streak, leisure lock | Unlimited non-negotiables, custom timer, savage mode, streak calendar, auto-verify, exam mode, study analytics |
| **Recovery** | Today's score + zone, basic hydration | Full prescriptions, sleep detail, trends, bedtime, caffeine cutoff, cross-recommendations |
| **Arena** | XP, levels, 5 friends, 1 challenge, 10 badges, share cards, 1.5x multiplier | Unlimited friends/challenges, custom challenges, 50+ badges, social feed, competitive notifications, 3x multiplier |

---

## 4. Paywall Design

### 4.1 When to Show the Paywall

**Primary trigger: Feature discovery moment** — Show the paywall the first time a user taps a Pro feature. This is the highest-intent moment because the user has self-selected interest.

**Secondary triggers:**
- After completing onboarding (soft paywall — "Start your 7-day free trial" as the last onboarding step, with a clear "Maybe Later" button)
- After completing their first full day (all non-negotiables done, daily score calculated) — "You scored 78 today. Want to see how you trend over time?"
- After their first weekly report would have been generated (Sunday evening) — "Your first weekly report is ready. Unlock it with Pro."
- When hitting the 5-friend limit — "Your squad is growing! Unlock unlimited friends."
- When attempting to create a challenge — "Create custom challenges with Pro."
- After 7 consecutive days of use — loyalty-based trigger. "You've been showing up for 7 days. You're serious. Upgrade to Pro and go all in."

**Never show the paywall:**
- During a workout (disruptive)
- During a focus timer session (disruptive)
- More than once per session unless the user actively taps a Pro feature
- On the very first app launch (before they've experienced any value)

### 4.2 Trial Strategy

**7-day free trial of Pro**, available once per Apple ID.

**Why 7 days (not 14):**
- Tempo's engagement loop is daily. 7 days = 1 full weekly cycle, which includes a weekly report.
- 14-day trials have higher trial-start rates but LOWER conversion rates (RevenueCat data: 7-day trials convert at 40-50%, 14-day trials at 30-40%). Users procrastinate evaluating the app and forget they're in a trial.
- 7 days creates urgency without feeling rushed.
- The trial ends right after the user receives their first weekly AI report — the "aha moment" — maximizing conversion probability.

**Trial flow:**
1. User taps a Pro feature (or reaches end of onboarding)
2. Paywall screen appears with trial offer
3. User opts in via StoreKit 2 (Apple handles billing)
4. Full Pro experience for 7 days
5. Day 5: Push notification — "Your Pro trial ends in 2 days. Here's what you'd lose: [weekly report, AI programming, unlimited friends]."
6. Day 7: If not converted, gracefully downgrade. Show a "Your trial ended" screen summarizing what they accomplished during the trial week.

### 4.3 Paywall Screen Design

**Layout (top to bottom):**

1. **Hero section:** Tempo Pro logo/badge at top. Gradient background (dark navy to deep blue). Feels premium but not gaudy.

2. **Headline** (see Section 4.5 for variants)

3. **Feature comparison** — Two columns:
   ```
   FREE                          PRO
   ----                          ---
   3 non-negotiables             Unlimited
   Basic workout logging         AI-powered programming
   Today's data                  Weekly AI reports
   5 friends                     Unlimited friends
   1 challenge                   Unlimited + custom
   Basic notifications           Full drill sergeant
   ```

4. **Social proof section:**
   - "Join 2,400+ students leveling up with Pro" (once there's scale)
   - A testimonial: "I went from studying 45 min/day to 3 hours. The drill sergeant doesn't let me slack." — Marco, 21, UM
   - Star rating from App Store (once available)

5. **Pricing cards** — Side by side:
   ```
   ┌──────────────────┐  ┌──────────────────┐
   │    MONTHLY        │  │  ANNUAL ★ BEST   │
   │    $4.99/mo       │  │    $3.33/mo       │
   │                   │  │  $39.99 billed    │
   │                   │  │  annually         │
   │                   │  │  SAVE 33%         │
   │  [Start Trial]    │  │  [Start Trial]    │
   └──────────────────┘  └──────────────────┘
   ```
   The annual plan is pre-selected (highlighted, slightly larger) with a "BEST VALUE" badge.

6. **Trial callout:** "Start your 7-day free trial. Cancel anytime."

7. **Fine print:** "Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period."

8. **"Maybe Later" link** at the very bottom — always visible, never hidden. Apple requires this.

9. **Restore Purchases** link — small text at bottom. Required by Apple.

### 4.4 Soft Paywall vs Hard Paywall

| Feature | Paywall Type | Experience for Free User |
|---------|-------------|------------------------|
| Weekly AI report | **Soft** | Show a blurred preview of the report with 1-2 visible insights. "Unlock full report" button overlaid. User can see it exists and has content — but can't read it. This is the most effective conversion driver. |
| Historical trends | **Soft** | Show the 7-day trend chart clearly. The 30-day and 90-day charts are visible but blurred with a lock icon. |
| Progress charts | **Soft** | Show one exercise's chart for the last 2 weeks. Full charts locked. |
| AI workout programming | **Hard** | "Today's Workout" tab shows "Get your personalized, recovery-adjusted workout plan with Pro." No preview — the AI hasn't generated anything for free users. |
| Recovery prescriptions | **Soft** | Show the prescription card with the first recommendation visible ("Training: Moderate day"). Remaining recommendations (bedtime, caffeine, meal timing) are blurred. |
| Savage mode notifications | **Hard** | Toggle exists in settings but is locked. Description explains what it does. |
| Unlimited friends | **Hard** | When tapping "Add Friend" beyond 5, paywall appears. |
| Custom challenges | **Hard** | "Create Challenge" button shows paywall. |
| Full achievement collection | **Soft** | Show all 50+ badges in a grid. Locked ones are grayed out with "Pro" tag. User can see what they're missing. |
| Exam mode | **Hard** | Button exists but triggers paywall when tapped. |
| Social feed | **Hard** | Tab or section shows "See what your friends are up to — upgrade to Pro." |
| Streak calendar | **Soft** | Show the current month with a few days filled in. Past months are blurred. |

### 4.5 Paywall Copy — 5 Headline Variants

Test these via A/B testing (use StoreKit 2 promotional offers to segment):

**Variant A (Aspirational):**
> **Your life, optimized.**
> AI-powered training. Intelligent recovery. Drill-sergeant accountability. One subscription to run your entire system.

**Variant B (Fear of Missing Out):**
> **You're leaving gains on the table.**
> Without Pro, you're training blind — no recovery adjustments, no AI insights, no weekly report showing what's actually working.

**Variant C (Social Proof):**
> **Join thousands of students who stopped winging it.**
> Pro members study 2.3x more, train smarter, and sleep better. The data proves it.

**Variant D (Math/Value):**
> **Less than a coffee. More than a coach.**
> $3.33/month for AI-powered training, recovery prescriptions, and a drill sergeant who won't let you skip. Your gym membership costs 10x more.

**Variant E (Direct / Drill Sergeant Tone):**
> **Stop half-assing it.**
> You showed up for 7 days. That's more than most people. Now go Pro and see what happens when you actually commit.

**Recommendation:** Start with Variant D (value-anchored) as the default. Test Variant E with users who have high engagement (7+ day streak) — the aggressive tone matches the app's personality and these users have already bought into the drill-sergeant ethos.

### 4.6 Restore Purchases Flow

Required by Apple App Store Review Guidelines (Section 3.1.2):

1. **Location:** Accessible from Settings > Subscription > "Restore Purchases" button AND on the paywall screen.
2. **Flow:**
   - User taps "Restore Purchases"
   - App calls `Transaction.currentEntitlements` (StoreKit 2)
   - If active subscription found: unlock Pro, show success message ("Pro restored! Welcome back.")
   - If no subscription found: show message ("No active subscription found. If you believe this is an error, contact support at support@tempo.app")
3. **Edge case:** User subscribed on another device. Restore should detect this via the same Apple ID.

---

## 5. Subscription Infrastructure

### 5.1 StoreKit 2 Implementation Strategy

StoreKit 2 is mandatory for new apps targeting iOS 17+. Use the modern async/await API exclusively.

**Product Configuration (App Store Connect):**

| Product ID | Type | Price | Duration | Trial |
|------------|------|-------|----------|-------|
| `com.tempo.pro.monthly` | Auto-Renewable Subscription | $4.99 | 1 month | 7-day free trial |
| `com.tempo.pro.annual` | Auto-Renewable Subscription | $39.99 | 1 year | 7-day free trial |

**Subscription Group:** `tempo_pro` (single group — monthly and annual are alternatives in the same group, so Apple handles upgrade/downgrade/crossgrade logic).

**Implementation Architecture:**

```swift
// SubscriptionManager.swift — @Observable service

@Observable
class SubscriptionManager {
    var isPro: Bool = false
    var currentSubscription: Transaction?
    var availableProducts: [Product] = []

    // On app launch: check entitlements
    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID.hasPrefix("com.tempo.pro") {
                    isPro = true
                    currentSubscription = transaction
                }
            }
        }
    }

    // Listen for real-time transaction updates
    func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await handleTransaction(transaction)
                await transaction.finish()
            }
        }
    }

    // Purchase flow
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                isPro = true
                // Sync to backend
                await syncSubscriptionToBackend(transaction)
                return transaction
            }
        case .pending:
            // Ask-to-Buy or requires approval
            break
        case .userCancelled:
            break
        @unknown default:
            break
        }
        return nil
    }
}
```

### 5.2 Receipt Validation (Server-Side with Vapor)

**Why server-side validation:** Client-side StoreKit 2 verification is sufficient for basic entitlement checks, but server-side validation is required for:
- Preventing jailbreak/tampered receipt fraud
- Tracking subscription metrics (MRR, churn, LTV) in your own database
- Triggering backend-side Pro feature unlocks (e.g., generating AI reports)
- Handling subscription status changes when the app is not running

**Implementation (Vapor):**

```
POST /v1/subscription/verify
Authorization: Bearer <jwt>
Body: {
    "transaction_id": "...",
    "original_transaction_id": "...",
    "product_id": "com.tempo.pro.annual",
    "environment": "production"  // or "sandbox"
}
```

**Server flow:**
1. iOS app sends the JWS-signed transaction to the backend after purchase
2. Vapor verifies the JWS signature using Apple's public keys (fetched from `https://appleid.apple.com/auth/keys`)
3. Decode the transaction payload: product ID, purchase date, expiration date, revocation status
4. Store in `user_subscriptions` table:
   ```sql
   CREATE TABLE user_subscriptions (
       id UUID PRIMARY KEY,
       user_id UUID REFERENCES users(id) NOT NULL,
       product_id TEXT NOT NULL,
       original_transaction_id TEXT UNIQUE NOT NULL,
       purchase_date TIMESTAMPTZ NOT NULL,
       expiration_date TIMESTAMPTZ NOT NULL,
       is_trial BOOLEAN DEFAULT false,
       is_active BOOLEAN DEFAULT true,
       environment TEXT NOT NULL,  -- 'production' or 'sandbox'
       raw_transaction JSONB,
       created_at TIMESTAMPTZ DEFAULT NOW(),
       updated_at TIMESTAMPTZ DEFAULT NOW()
   );
   ```
5. Return `{ "pro": true, "expires_at": "2027-03-24T..." }` to the iOS app

**App Store Server Notifications V2:**
Register a webhook URL in App Store Connect: `https://api.tempo.app/v1/subscription/webhook`

Handle these notification types:
- `DID_RENEW` — Subscription renewed. Update `expiration_date`.
- `DID_CHANGE_RENEWAL_STATUS` — User turned off auto-renew. Record it, trigger win-back campaign.
- `DID_FAIL_TO_RENEW` — Billing issue. Enter grace period.
- `EXPIRED` — Subscription expired. Set `is_active = false`. Downgrade to free.
- `REVOKE` — Refund granted. Immediately revoke Pro access.
- `OFFER_REDEEMED` — Promotional offer used. Track for analytics.
- `GRACE_PERIOD_EXPIRED` — Billing grace period ended without resolution. Downgrade.

### 5.3 Grace Period Handling

**Apple's billing grace period:** Apple provides a 6-day (for weekly) or 16-day (for monthly/annual) grace period when a subscription fails to renew due to billing issues (expired card, insufficient funds).

**Tempo's approach:**
- During grace period: maintain Pro access. User may not even know there's an issue.
- Day 1 of grace period: no notification. Apple handles retry silently.
- Day 6 (monthly/annual): if still unresolved, push notification — "There's a billing issue with your Tempo Pro subscription. Update your payment method in Settings > Apple ID to keep Pro features."
- Grace period expires: downgrade to free tier. Show a banner in-app — "Your Pro subscription has expired due to a billing issue. Tap here to resolve."

### 5.4 Subscription Status Checking

**On every app launch:**
1. Call `Transaction.currentEntitlements` to check for active subscription
2. If found and not yet synced today, verify with backend (`POST /v1/subscription/verify`)
3. Cache result locally: `UserDefaults.standard.set(true, forKey: "isPro")` with `expirationDate`
4. For offline support: honor cached `isPro` status if `expirationDate` is in the future. Re-verify when back online.

**When to re-check mid-session:**
- User returns from background after 1+ hour
- User navigates to a Pro feature and cached status is >24 hours old
- After any purchase or restore flow

### 5.5 Family Sharing

**Not recommended for launch.** Reasons:
- Family Sharing reduces revenue per household (1 subscription shared by up to 6 people)
- Tempo's value is personal (your workouts, your recovery, your study habits)
- The social/Arena features work better when each friend has their own account and subscription
- Enable Family Sharing in a future version if users request it

### 5.6 Promotional Offers Strategy

**Introductory Offer (new subscribers only):**
- 7-day free trial (configured per product in App Store Connect)
- This is the default for all new users

**Promotional Offers (existing/lapsed subscribers):**
- **Win-back offer:** $0.99 for the first month, then $4.99/month. Target users who:
  - Had a Pro subscription that expired 30-90 days ago
  - Used the app at least 10 times during their subscription
  - Signed with App Store Server API to generate the offer signature server-side
- **Seasonal offer:** $29.99/year (25% off) during back-to-school season (August-September). Target university students returning to campus.

**Offer Codes (redeemable in App Store):**
- Generate codes for:
  - Influencer partnerships (50-100 codes per campaign)
  - Campus ambassador program (20 codes per ambassador)
  - Friend referral rewards (see Growth Levers section)
- Each code grants 1 month free Pro

### 5.7 Price Localization

Apple handles currency conversion automatically, but you can set custom prices per storefront.

**Recommended price tiers by region:**

| Region | Monthly | Annual | Rationale |
|--------|---------|--------|-----------|
| United States | $4.99 | $39.99 | Base price |
| European Union | 4.99 EUR | 39.99 EUR | Rough parity. EUR is close to USD. |
| United Kingdom | 4.49 GBP | 34.99 GBP | Slightly lower due to higher perceived cost |
| Canada | $5.99 CAD | $44.99 CAD | Standard CAD markup |
| Australia | $7.99 AUD | $59.99 AUD | Standard AUD markup |
| Brazil | R$14.90 | R$99.90 | Significantly lower PPP. Brazil is a huge fitness market. |
| India | 149 INR | 999 INR | Very low PPP but massive potential user base. |
| Italy | 4.99 EUR | 39.99 EUR | Home market — same as EU |
| Japan | 600 JPY | 4,800 JPY | Standard JPY tier |
| Mexico | $79 MXN | $599 MXN | Latin America pricing |

**Note:** Apple lets you choose from predefined price tiers. Match as closely as possible to these targets. Review pricing quarterly as exchange rates shift.

---

## 6. Revenue Projections

### 6.1 Model Assumptions

- **Conversion rate decreases as user base grows** (early adopters convert higher; mass market converts lower)
- **Monthly churn:** 8% for monthly subscribers, 3% for annual subscribers (industry averages from RevenueCat 2025 report)
- **Annual/monthly split:** 60% annual, 40% monthly (industry standard when annual is prominently featured)
- **Apple's cut:** 15% (Small Business Program for developers earning <$1M/year; 30% above $1M)
- **Revenue = gross revenue minus Apple's cut**

### 6.2 Revenue at Scale

#### 100 Users (Soft Launch / TestFlight)

| Metric | Value |
|--------|-------|
| Pro conversion | 10% (10 users — friends and early believers) |
| Annual subscribers (60%) | 6 users x $39.99/year = $239.94/year = $20.00/month |
| Monthly subscribers (40%) | 4 users x $4.99/month = $19.96/month |
| **Gross monthly revenue** | **$39.96** |
| Apple's cut (15%) | -$5.99 |
| **Net monthly revenue** | **$33.97** |

#### 1,000 Users (Post-Launch, Growing)

| Metric | Value |
|--------|-------|
| Pro conversion | 8% (80 users) |
| Annual subscribers (60%) | 48 users x $39.99/year = $1,919.52/year = $159.96/month |
| Monthly subscribers (40%) | 32 users x $4.99/month = $159.68/month |
| **Gross monthly revenue** | **$319.64** |
| Apple's cut (15%) | -$47.95 |
| **Net monthly revenue** | **$271.69** |

#### 10,000 Users (Established Product)

| Metric | Value |
|--------|-------|
| Pro conversion | 5% (500 users) |
| Annual subscribers (60%) | 300 users x $39.99/year = $11,997/year = $999.75/month |
| Monthly subscribers (40%) | 200 users x $4.99/month = $998.00/month |
| **Gross monthly revenue** | **$1,997.75** |
| Apple's cut (15%) | -$299.66 |
| **Net monthly revenue** | **$1,698.09** |

#### 100,000 Users (Scale)

| Metric | Value |
|--------|-------|
| Pro conversion | 3% (3,000 users) |
| Annual subscribers (60%) | 1,800 users x $39.99/year = $71,982/year = $5,998.50/month |
| Monthly subscribers (40%) | 1,200 users x $4.99/month = $5,988.00/month |
| **Gross monthly revenue** | **$11,986.50** |
| Apple's cut (15%) | -$1,797.98 |
| **Net monthly revenue** | **$10,188.52** |

**Note:** At $10,188/month ($122K/year), you're still under the $1M Small Business Program threshold. Apple's cut stays at 15%.

### 6.3 Annual Revenue Summary

| Scale | Monthly Net | Annual Net |
|-------|------------|------------|
| 100 users | $34 | $408 |
| 1,000 users | $272 | $3,260 |
| 10,000 users | $1,698 | $20,377 |
| 100,000 users | $10,189 | $122,262 |

---

## 7. Cost Structure

### 7.1 Infrastructure Costs by Scale

#### Vapor Backend Hosting

Using a VPS provider (Hetzner, DigitalOcean, Railway, or Fly.io):

| Scale | Server Spec | Estimated Monthly Cost |
|-------|------------|----------------------|
| 100 users | Shared CPU, 1 vCPU, 1GB RAM (Hetzner CX22) | $4/month |
| 1,000 users | Shared CPU, 2 vCPU, 4GB RAM (Hetzner CX32) | $8/month |
| 10,000 users | Dedicated CPU, 4 vCPU, 8GB RAM (Hetzner CCX23) | $30/month |
| 100,000 users | Dedicated CPU, 8 vCPU, 32GB RAM + load balancer | $120/month |

#### PostgreSQL Hosting

| Scale | Hosting | Estimated Monthly Cost |
|-------|---------|----------------------|
| 100 users | Same server as Vapor (docker-compose) | $0 (included in Vapor server) |
| 1,000 users | Same server as Vapor | $0 (included) |
| 10,000 users | Managed PostgreSQL (Supabase free tier or Hetzner managed) | $15/month |
| 100,000 users | Managed PostgreSQL (dedicated, 4GB RAM, 100GB storage) | $50/month |

#### Redis (for rate limiting, caching, session management)

| Scale | Hosting | Estimated Monthly Cost |
|-------|---------|----------------------|
| 100-1,000 users | Same server, Redis in Docker | $0 |
| 10,000 users | Small managed Redis (Upstash free tier or 256MB) | $0-10/month |
| 100,000 users | Managed Redis (1GB) | $20/month |

#### Claude API (AI Features)

Estimated usage per Pro user per month:
- 1 weekly report: ~2,000 input tokens + ~1,500 output tokens
- Pattern detection (weekly): ~3,000 input tokens + ~1,000 output tokens
- Workout programming adjustments (daily, small): ~500 input tokens + ~300 output tokens x 30 = 15,000 + 9,000
- Recovery prescriptions (daily): ~400 input tokens + ~200 output tokens x 30 = 12,000 + 6,000

**Total per Pro user/month:** ~32,000 input tokens + ~17,500 output tokens

Using Claude 3.5 Haiku (best cost/quality for structured tasks):
- Input: $0.80/million tokens
- Output: $4.00/million tokens

**Per Pro user/month:** (32,000 x $0.80 / 1,000,000) + (17,500 x $4.00 / 1,000,000) = $0.026 + $0.070 = **$0.096/user/month**

| Scale | Pro Users | Claude API Cost/Month |
|-------|-----------|---------------------|
| 100 users | 10 | $0.96 |
| 1,000 users | 80 | $7.68 |
| 10,000 users | 500 | $48.00 |
| 100,000 users | 3,000 | $288.00 |

**Note:** Using Claude 3.5 Sonnet (better quality) would cost ~5x more. Start with Haiku, upgrade selectively (e.g., weekly reports use Sonnet, daily prescriptions use Haiku).

#### Apple Push Notification Service (APNs)

APNs is free. Apple does not charge for push notifications. The only cost is the server infrastructure to send them, which is included in the Vapor hosting cost.

#### Fixed Costs

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 | Annual |
| Domain (tempo.app or similar) | $12-40 | Annual |
| SSL Certificate | $0 (Let's Encrypt) | Auto-renewing |
| Email service (Postmark/Resend, transactional) | $0-10/month | Monthly |

### 7.2 Total Monthly Cost by Scale

| Scale | Hosting | Database | Redis | Claude API | Fixed (amortized) | **Total/Month** |
|-------|---------|----------|-------|-----------|-------------------|-----------------|
| 100 users | $4 | $0 | $0 | $1 | $10 | **$15** |
| 1,000 users | $8 | $0 | $0 | $8 | $10 | **$26** |
| 10,000 users | $30 | $15 | $10 | $48 | $10 | **$113** |
| 100,000 users | $120 | $50 | $20 | $288 | $10 | **$488** |

### 7.3 Break-Even Analysis

| Scale | Monthly Net Revenue | Monthly Cost | Profit/Loss | Status |
|-------|-------------------|-------------|-------------|--------|
| 100 users | $34 | $15 | **+$19** | Profitable (barely) |
| 1,000 users | $272 | $26 | **+$246** | Healthy |
| 10,000 users | $1,698 | $113 | **+$1,585** | Strong |
| 100,000 users | $10,189 | $488 | **+$9,701** | Very strong |

**Break-even point:** approximately 50 total users with 10% conversion (5 Pro users). At $4.99/month with 3 Pro users, gross revenue is ~$15, which covers the minimum hosting costs. Tempo becomes cash-flow positive almost immediately.

**Key insight:** The cost structure is extremely favorable. Claude API is the largest variable cost, and it only applies to Pro users who are already paying. Infrastructure costs are minimal thanks to modern VPS pricing. Tempo can be profitable from day one with even a small paying user base.

---

## 8. Go-To-Market Strategy

### 8.1 Phase 0: Pre-Launch (4-8 weeks before App Store)

**TestFlight Beta**
- Invite 50-100 friends, university classmates, gym buddies
- All features unlocked (no paywall during beta)
- Collect feedback via in-app feedback form and a private Discord/WhatsApp group
- Track which features are used most to validate the free/Pro split
- Fix critical bugs, polish UX, optimize performance

**Build in public:**
- Post development progress on Twitter/X with the hashtag #BuildInPublic
- Share screenshots, design decisions, technical challenges
- Target audience: indie dev community + fitness enthusiasts
- Platform priority: Twitter/X > Instagram > TikTok
- Document the journey: "How I built a life operating system in Swift" — this is content marketing that doubles as a developer portfolio piece

**Landing page:**
- Simple landing page at tempo.app (or tempoapp.co)
- Email signup for launch notification
- Show the 4-quadrant dashboard screenshot, key features, "Coming Soon to the App Store"
- Optimize for "life operating system app" and "student productivity fitness app" keywords

### 8.2 Phase 1: Soft Launch (Week 1-2 on App Store)

**App Store Optimization (ASO):**

**App name:** Tempo — Life Operating System

**Subtitle (30 chars):** Train. Study. Recover. Compete.

**Keywords (100 chars):** fitness,workout,study,timer,accountability,recovery,whoop,nutrition,habits,streak,student,gym,focus

**Description (first 3 lines — visible before "More"):**
> Tempo unifies your fitness, nutrition, recovery, and academics into one intelligent system. It adapts your training to your Whoop recovery, holds you accountable with drill-sergeant notifications, and lets you compete with friends on a real leaderboard.
>
> Stop using 5 apps to manage your life. One app. One score. Every day.

**Screenshots (6 required, prioritize):**
1. Dashboard — 4-quadrant view with real data (hero shot)
2. Training — Today's workout with recovery badge showing "Green — Full send"
3. Accountability — Non-negotiables checklist with drill-sergeant notification preview
4. Recovery — Prescription card showing bedtime, caffeine cutoff, training recommendation
5. Arena — Leaderboard with friends, XP animation
6. Weekly Report — AI-generated insights with trend charts

**App Preview Video (optional, high ROI):**
30-second screen recording showing: wake up > check recovery > see today's workout > log sets > focus timer > non-negotiables complete > XP earned > leaderboard position. Show the daily loop.

### 8.3 Phase 2: Launch Push (Week 2-4)

**Product Hunt Launch:**
- Submit on a Tuesday or Wednesday (highest traffic days)
- Title: "Tempo — The Life Operating System for Active Students"
- Hunter: self-submit or find a hunter with followers
- Prepare: GIF demos, respond to every comment within 30 minutes, have 10 friends ready to upvote and comment genuinely
- Expected outcome: 200-500 visitors, 50-150 installs, potential top-5 finish in Productivity category

**Reddit:**
- Post in: r/productivity, r/fitness, r/getdisciplined, r/iosapps, r/swiftui, r/college
- Do NOT spam-post. Write a genuine "I built this" story. Include what you learned, what's unique, how it works.
- The r/swiftui and r/iosprogramming posts double as developer marketing + hiring pipeline content

**Twitter/X:**
- Thread: "I built a life operating system for students who train. Here's what it does and why."
- Tag fitness influencers, productivity creators, indie dev accounts
- Post screenshots of the Arena leaderboard (social proof, competitive intrigue)

**Fitness Communities:**
- Bodybuilding.com forums (still active for gym culture)
- Whoop community Facebook groups (Tempo integrates with Whoop — relevant audience)
- University fitness club Discord servers

### 8.4 Phase 3: University Campus Strategy (Month 2-6)

**Target: Student athletes and fitness-oriented students at 5-10 universities**

**Campus Ambassador Program:**
- Recruit 2-3 ambassadors per campus (fitness-oriented students with social media presence)
- Each ambassador gets: free Pro for 1 year + 20 referral codes (each gives 1 month free Pro)
- Ambassador responsibilities: post about Tempo 2x/week on Instagram stories, get 5 friends to sign up, report feedback
- Compensation: free Pro + potential revenue share if program scales

**Tactics:**
- Partner with university gym/rec centers for screen time on gym TVs
- Sponsor a "Tempo Challenge" at campus fitness clubs — most XP in a week wins a prize
- Reach student government / student activity boards for app promotion
- Target Greek life (fraternities/sororities) — competitive group dynamics are perfect for Arena

**Referral System:**
- Existing user shares a referral link
- New user signs up and uses the app for 7 days
- Both users get 1 week of free Pro
- Cap: 4 referrals per user per month (prevents abuse, still powerful — 1 month free Pro for 4 referrals)

### 8.5 Content Marketing (Ongoing)

**Blog / Medium posts:**
- "How I Built a Life Operating System in SwiftUI" (developer audience)
- "Why I Combined Fitness and Study Tracking in One App" (product audience)
- "How Whoop Recovery Data Changed My Training" (fitness audience)
- "The Drill Sergeant Productivity Method" (productivity audience)

**YouTube (if time permits):**
- "I Tracked Every Aspect of My Life for 30 Days — Here's What Happened"
- Dev vlogs showing the build process
- App walkthroughs and feature demos

### 8.6 Press Kit

Prepare a /press page on the website with:
- App icon (1024x1024 PNG, with and without rounded corners)
- Screenshots (iPhone 15 Pro Max, light and dark mode)
- App Preview video (MP4, 1080x1920)
- Founder bio and headshot
- One-paragraph app description
- Three-bullet key differentiators
- Pricing information
- Contact email for press inquiries
- Download link (App Store badge)

---

## 9. Growth Levers

### 9.1 Viral Features (Built into the Product)

**Challenge Invites:**
- When a Pro user creates a challenge, they share a link: `tempo.app/challenge/abc123`
- Non-users who tap the link see a preview of the challenge and are directed to the App Store
- This is the #1 organic growth channel. Every challenge is a mini marketing campaign.

**Share Cards:**
- After every workout, the summary screen has a "Share" button that generates a beautiful card:
  ```
  ┌──────────────────────────┐
  │  TEMPO                   │
  │                          │
  │  LEG DAY CRUSHED         │
  │  12 sets | 45 min        │
  │  Recovery: 82% (Green)   │
  │  New PR: Squat 120kg     │
  │                          │
  │  Level 14 | 2,450 XP     │
  │  #TempoApp               │
  └──────────────────────────┘
  ```
- Optimized for Instagram Stories (9:16 ratio) and Twitter (16:9 ratio)
- Share cards are FREE for all users. This is advertising. Never gate viral features.

**Achievement Shares:**
- When a user earns a rare badge, prompt them to share it
- "You earned the Iron Mind badge (30-day study streak). Share it?"

**Leaderboard Screenshots:**
- The leaderboard view is designed to look great as a screenshot
- Weekly leaderboard resets create natural sharing moments ("I finished #1 this week!")

### 9.2 Network Effects

Tempo gets better with more friends:
- More friends = more competitive leaderboard = more engagement
- More friends = more challenge options = more variety
- More friends = more social proof in the feed = more motivation
- A user with 0 friends has a weaker experience than a user with 5 friends. This means growth is self-reinforcing.

**Critical mass per user:** 3-5 friends. Below 3, the Arena feels empty. Above 5, it feels alive. Every onboarding and growth effort should focus on getting each user to invite at least 3 friends.

### 9.3 Cross-Promotion with NutriTrack

NutriTrack (the existing nutrition app) can funnel users to Tempo:
- Add a "Powered by NutriTrack" badge in Tempo's Fuel quadrant, linking to NutriTrack
- Add a "Connect to Tempo" option in NutriTrack for users who want the full life OS
- Share the same user base — anyone using NutriTrack is a warm lead for Tempo

### 9.4 Influencer Strategy

**Target creators (micro-influencers, 5K-50K followers):**

| Niche | Platform | Approach |
|-------|----------|----------|
| Fitness YouTubers (college-age) | YouTube, Instagram | Free Pro + referral code. Ask for an honest review, not a scripted ad. |
| Student productivity creators | YouTube, TikTok | "How I use Tempo to balance gym and grades" content |
| Whoop community creators | Instagram, YouTube | Emphasis on RecoverIQ — "I finally know what to do with my recovery score" |
| SwiftUI/indie dev creators | Twitter, YouTube | Technical content about the build. Dev community supports indie apps. |

**Budget:** $0 at launch (give free Pro + referral codes). At 10,000+ users, consider $500-2,000 for sponsored content with 1-2 larger creators (50K-200K followers).

---

## 10. Retention Strategy

### 10.1 Push Notification Optimization

Push notifications are Tempo's most powerful retention tool — the drill-sergeant personality makes notifications a FEATURE, not an annoyance.

**Notification categories and timing:**

| Category | Timing | Free | Pro | Purpose |
|----------|--------|------|-----|---------|
| Morning briefing | 7:00 AM | Yes (simple) | Yes (detailed) | "Recovery: 72%. Training: Upper day. Study: 2h target." Start the day. |
| Accountability check-in | 2:00 PM | Yes | Yes | "3 tasks left today." Keep them on track. |
| Evening escalation | 6:30 PM | No | Yes (Savage mode) | "Study not done. No PS5 until you finish." The drill sergeant. |
| Workout reminder | 30 min before usual workout time | Yes | Yes | "Leg day in 30 min. Recovery is green — time to push." |
| Streak at risk | 9:00 PM (if non-negotiables incomplete) | Yes | Yes | "Your 14-day streak dies at midnight. 45 min of study saves it." |
| Friend passed you | Real-time | No | Yes | "Marco just took #2 on the leaderboard. You dropped to #3." |
| Weekly report ready | Sunday 8:00 PM | No | Yes | "Your weekly intelligence report is ready. Tap to see your patterns." |
| Challenge ending | 24h before end | Yes | Yes | "The Study Sprint challenge ends tomorrow. You're in 2nd place." |

**Key principle:** Never send a notification that doesn't drive action. Every notification should have a clear next step the user can take.

### 10.2 Streak Mechanics as Retention Driver

Streaks are the single most effective retention mechanic in consumer apps (Duolingo's entire business is built on streak anxiety).

**Tempo's streak design:**
- A "complete day" = all non-negotiables done
- Streak counter is prominently displayed on the Dashboard
- Streak milestones (7, 14, 30, 60, 90, 180, 365 days) trigger:
  - Achievement badges
  - XP multiplier increases (Pro)
  - Celebration animations
  - Shareable milestone cards

**Streak protection:**
- Pro users get 1 "streak freeze" per month (miss a day without breaking the streak)
- This is psychologically powerful: users protect their streak AND value the freeze (which is Pro-only)
- During exam mode, streak requirements are relaxed (only study non-negotiable counts)

**Loss aversion tactics:**
- "You're about to lose your 23-day streak" (evening notification)
- Show what the streak will look like at 0 on the dashboard (preview of loss)
- After a streak breaks: "Your streak was 23 days. Start rebuilding now." (immediate re-engagement)

### 10.3 Social Features as Retention Driver

**Friend activity as a check-in trigger:**
- Pro users see a social feed: "Marco completed Leg Day (+150 XP)"
- This creates a "I should open Tempo" impulse when they see a friend's activity
- Even without the feed, leaderboard position changes drive check-ins

**Accountability partnerships:**
- Two friends can become "accountability partners" — each sees the other's non-negotiable progress in real-time
- If your partner hasn't started studying by 3 PM, you get a notification: "Marco hasn't started studying yet. Send him a nudge?"
- This creates mutual obligation — a powerful retention mechanic

### 10.4 Weekly Report as Re-Engagement Driver

The weekly AI report (Pro) drops every Sunday evening. It:
- Summarizes the week's performance across all quadrants
- Highlights patterns ("You study 40% more on days you sleep 7+ hours")
- Celebrates wins ("3 PRs this week — your bench is up 5kg this month")
- Calls out gaps ("You missed 4 meals this week. Fuel is your weakest quadrant.")
- Sets next-week focus: "This week's focus: hit protein target every day"

**Re-engagement power:** Even users who haven't opened the app in a few days will open it for the weekly report. It is the "reason to come back" every week.

### 10.5 Win-Back Campaigns for Churned Users

**Definition of "churned":** No app open in 14+ days AND subscription expired/cancelled.

**Win-back sequence:**

| Day | Channel | Message |
|-----|---------|---------|
| Day 14 (no app open) | Push notification | "You've been quiet for 2 weeks. Your leaderboard position dropped to #8. Come back and reclaim your spot." |
| Day 21 | Push notification | "Your 47-day streak data is still here. Start a new streak today." |
| Day 30 | Email (if available) | "We miss you at Tempo. Here's what's new: [latest feature]. Come back with 50% off your first month: [offer code]." |
| Day 60 | Push notification (final) | "It's been 2 months. Tempo is still here when you're ready. One tap to restart." |
| Day 90+ | Stop outreach. Respect the user's decision. | — |

**Win-back pricing offer:** $0.99 for the first month back (StoreKit 2 promotional offer, generated server-side).

### 10.6 Feature Announcements for Dormant Users

When shipping new features, send a push notification to users who haven't opened the app in 7-30 days:
- "New: Exam Mode is here. Lock in your study habits for finals week."
- "New: Custom Challenges. Challenge your friends to anything."
- Feature announcements are a legitimate reason to re-engage dormant users. Use sparingly (max 1 per month for dormant users).

---

## 11. Legal Requirements for Monetization

### 11.1 App Store Review Guidelines (Subscriptions)

Reference: [Apple App Store Review Guidelines, Section 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions)

**Mandatory requirements:**

1. **Clear description of what the subscription includes.** The paywall must list exactly what users get with Pro. Vague language like "premium features" is insufficient — list specific features.

2. **Pricing must be clearly visible before purchase.** Show the exact price ($4.99/month, $39.99/year) on the paywall screen. No hidden costs.

3. **Free trial terms must be explicit.** If offering a 7-day free trial, state: "Free for 7 days, then $4.99/month" (or annual equivalent). The trial duration and subsequent charge must be on the same screen as the purchase button.

4. **Subscription auto-renewal disclosure.** Must include language like: "Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period."

5. **Easy access to manage/cancel subscription.** Apple requires that your app links to the system subscription management page. Include a "Manage Subscription" button in Settings that opens: `itms-apps://apps.apple.com/account/subscriptions`

6. **Restore Purchases button.** Must be accessible on the paywall screen and in Settings. Apple will reject apps that don't have this.

7. **No external purchase links.** You cannot direct users to a website to subscribe (unless you qualify for specific exemptions under the EU Digital Markets Act or US court rulings). All purchases must go through StoreKit / App Store.

### 11.2 Required Subscription Management UI

In the app's Settings screen, include:

```
┌─────────────────────────────┐
│ Subscription                 │
│                              │
│ Status: Pro (Active)         │
│ Plan: Annual ($39.99/year)   │
│ Renews: March 24, 2027      │
│                              │
│ [Manage Subscription]        │  ← Opens Apple's subscription manager
│ [Restore Purchases]          │
│                              │
│ Terms of Service             │  ← Link to terms
│ Privacy Policy               │  ← Link to privacy policy
└─────────────────────────────┘
```

For free users:
```
┌─────────────────────────────┐
│ Subscription                 │
│                              │
│ Status: Free                 │
│                              │
│ [Upgrade to Pro]             │  ← Opens paywall
│ [Restore Purchases]          │
│                              │
│ Terms of Service             │
│ Privacy Policy               │
└─────────────────────────────┘
```

### 11.3 Required Legal Documents

Before App Store submission, you need:

1. **Privacy Policy** (REQUIRED — Apple will reject without it)
   - Must disclose: data collected (HealthKit, Whoop, NutriTrack, study sessions), how it's used, third-party sharing (Claude API sends anonymized data to Anthropic), data retention policy
   - HealthKit-specific: Apple requires explicit disclosure that HealthKit data is not sold or shared for advertising. This is a hard requirement.
   - Host at: `tempo.app/privacy`

2. **Terms of Service / EULA**
   - Cover: subscription terms, auto-renewal, cancellation policy, acceptable use, content ownership, limitation of liability
   - Apple provides a standard EULA that you can use, but a custom one is recommended for subscription apps
   - Host at: `tempo.app/terms`

3. **Subscription Terms** (can be part of Terms of Service)
   - Auto-renewal terms
   - Cancellation policy (must reference Apple's subscription management)
   - Refund policy (Apple handles refunds, but you should state this clearly)
   - Price change notification policy

### 11.4 HealthKit-Specific Requirements

Apple has strict rules for apps that use HealthKit data:

1. **Do not use HealthKit data for advertising or user profiling.** Period.
2. **Do not sell HealthKit data to third parties.** Period.
3. **HealthKit data must not leave the device unless the user explicitly consents** and it's for a health-related purpose.
4. **You must have a privacy policy that specifically addresses HealthKit data handling.**
5. **HealthKit data must be encrypted in transit and at rest** if stored on a server.

Tempo compliance: HealthKit data is read locally on the device and stored in SwiftData. It is NOT sent to the Vapor backend (Whoop data comes from the Whoop API directly, not via HealthKit). This simplifies compliance significantly.

### 11.5 GDPR / Data Protection (If Serving EU Users)

If Tempo is available in EU App Stores:

1. **Right to access:** Users can request all data you have about them. Build an export endpoint: `GET /v1/user/me/export`
2. **Right to deletion:** Users can request account deletion. Build a delete endpoint: `DELETE /v1/user/me` — must cascade delete all data (XP events, friendships, achievements, Whoop tokens, subscriptions)
3. **Consent for data processing:** Onboarding must include consent checkboxes for HealthKit access, Whoop integration, NutriTrack integration, push notifications, and analytics
4. **Data Processing Agreement:** If using any third-party analytics (Mixpanel, PostHog), you need a DPA with them
5. **Cookie/tracking disclosure:** Not applicable for native iOS apps (no cookies), but if you have a website, comply with cookie laws

### 11.6 Auto-Renewable Subscription Tax Implications

- Apple collects and remits sales tax / VAT in most jurisdictions. You receive the net amount.
- Revenue from App Store subscriptions is taxable income. Track it for your tax returns.
- The Apple Small Business Program (15% commission) requires annual application/re-application. Apply at: [developer.apple.com/programs/small-business/](https://developer.apple.com/programs/small-business/)
- If you form an LLC or company for Tempo, App Store revenue flows to the business entity.

---

## Appendix: Decision Log

| Decision | Choice | Rationale | Date |
|----------|--------|-----------|------|
| Monetization model | Freemium + Subscription | Backend costs require recurring revenue; subscription is proven in fitness/productivity | 2026-03-24 |
| Price point | $4.99/mo, $39.99/yr | Student demographic sweet spot; competitive with Strong/Gentler Streak; covers costs | 2026-03-24 |
| Trial duration | 7 days | One full weekly cycle; includes first weekly report; higher conversion than 14-day | 2026-03-24 |
| Family Sharing | Disabled at launch | Reduces revenue, personal data doesn't share well, re-evaluate later | 2026-03-24 |
| Student discount | $3.99/mo, $29.99/yr (via promo codes) | Captures price-sensitive segment without lowering base price | 2026-03-24 |
| Apple commission | 15% (Small Business Program) | Revenue will be well under $1M for years | 2026-03-24 |
| AI model for features | Claude 3.5 Haiku (default), Sonnet (weekly reports) | Haiku is 5x cheaper; sufficient for daily prescriptions/programming; Sonnet for high-value weekly analysis | 2026-03-24 |
