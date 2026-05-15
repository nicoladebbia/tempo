# Tempo — Launch Punch List

> **Audience:** Nicola (the builder) + any future AI coding agent picking up the work.
> **Snapshot date:** 2026-05-15, end of the day the intelligence remediation shipped + the backend went live on Railway.
> **Reading order:** Top to bottom. Phase 1 must complete before Phase 2; Phase 3 can run in parallel once Phase 1 is mostly done.
>
> **Conventions:**
> - **You** = Nicola does this. Usually requires Apple Developer Console access, App Store Connect, or legal/marketing decisions.
> - **Me** = an AI coding agent can drive this from the repo.
> - **Both** = needs your input + agent's execution.
> - **Effort estimates** are deliberately rough. They're for sequencing, not deadlines.
> - Every checkbox has a `Done when:` line. Use it as the test for "is this actually finished?"

---

## State of the world (as of 2026-05-15)

### What's already done

| Layer | Status |
|---|---|
| Backend deployed (Railway, US East) | ✅ Live at `https://tempo-backend-production-39dc.up.railway.app` |
| Postgres + Redis | ✅ Managed services, all 22 migrations applied |
| Anthropic API key | ✅ Off iOS binary, on Railway env, real Haiku/Sonnet responses verified in prod |
| Subscription gate + AI consent middleware | ✅ Returns 402 with typed `code` per `INTELLIGENCE_REMEDIATION_PLAN.md §4` |
| AIBudgetTracker ($50/mo hard cap) | ✅ Postgres-backed, threshold ladder 50/80/95/100% |
| AICache (Postgres + Redis, typed keys, SWR API) | ✅ Verified Postgres + Redis HITs |
| 12 AI features per `AI_INTELLIGENCE_ENGINE.md §1` | ✅ All routes return 200 in prod (Haiku + Sonnet) |
| Onboarding (17 steps incl. daily-plan profile + AI consent) | ✅ Compiles, persists, **NOT click-tested on real device** |
| Daily time-blocked plan engine (`DayPlanner` + view + AI hydration + triggers) | ✅ Drag-to-reflow deferred |
| 5 modules (Dashboard / Training / Lockdown / Recovery / Arena) | ✅ Build clean, **NOT exercised with real Whoop/HealthKit data** |
| Nutrition: meal feedback, shift planner, pantry container units, multi-add | ✅ Shipped |

### What this document covers

Everything between "intelligence layer shipped" and "first paying customer in the App Store."

### What this document does NOT cover

- Re-litigating the intelligence remediation plan (`docs/INTELLIGENCE_REMEDIATION_PLAN.md`)
- Re-litigating Phase 15.1-15.9 in `docs/BUILD_PROGRESS.md`
- Marketing strategy beyond the bare minimum (`Phase 4` is the tactical floor, not a growth playbook)
- Apple Watch / iPad layouts (Phase 18 of build plan; out of scope for v1)

---

## Phase 1 — Make the app submittable

**Goal:** the Submit button in App Store Connect is no longer greyed out. Most of this is *paperwork*, not code.

**Estimated wall-clock:** 1–2 focused weeks. Most blocking item is Apple's 24-48h review of your developer enrollment.

### 1.1 Apple Developer enrollment

- [ ] **You.** Enroll at https://developer.apple.com/programs/enroll/
- $99/year. Individual or Sole Proprietor.
- 24-48h for Apple to approve.
- If you already have an account, skip — verify it's in good standing (no expired payment).

**Done when:** `developer.apple.com` shows your account as Active with team ID visible.

### 1.2 App Store Connect record

- [ ] **You.** App Store Connect → My Apps → + → New App
- Bundle ID: **`app.tempo.Tempo`** (must match `Tempo/Tempo/Configuration/Production.xcconfig:5`)
- Platform: iOS
- Primary language: English (US)
- SKU: anything unique. Suggest `tempo-ios-001`
- User access: Full
- Category: Health & Fitness (primary), Lifestyle (secondary)

**Done when:** the record exists in App Store Connect with the bundle ID Apple can match against your future TestFlight build.

### 1.3 StoreKit products

- [ ] **You.** App Store Connect → Subscriptions → + Create Subscription Group → "Tempo Pro"
- [ ] Create the 4 products with exact IDs (already hardcoded in iOS):

| Product ID | Price | Subscription duration |
|---|---|---|
| `com.tempo.pro.monthly` | $4.99 | 1 month |
| `com.tempo.pro.annual` | $39.99 | 1 year |
| `com.tempo.pro.student.monthly` | $3.99 | 1 month |
| `com.tempo.pro.student.annual` | $29.99 | 1 year |

- For each:
  - Localised display name + description (4 lines, sells the feature)
  - Review screenshot (1 of the paywall view)
  - Status: "Ready to Submit"
  - **DON'T** mark them "Cleared for Sale" until the app itself is approved — Apple reviews them together
- Student tier verification: Apple doesn't have a native flow for `.edu` checks. For v1, just price them lower and trust the user; add real verification later (SheerID, GetYourGuide-style flow).

**Done when:**
- All 4 products visible in App Store Connect with status "Ready to Submit"
- Running on a device, your `PaywallView` shows non-empty rows (StoreKit `Product.products(for: ids)` returns 4 products, not empty array)

**Where the iOS code expects them:** `Tempo/Tempo/Services/Subscriptions/SubscriptionServiceProtocol.swift`

### 1.4 Push notifications (APNs)

- [ ] **You.** Apple Developer → Certificates, IDs & Profiles → Keys → + → check **Apple Push Notifications service (APNs)**
- [ ] Download the `.p8` file (one-time download — can never download again, only re-generate)
- [ ] Note the **Key ID** (10 chars, visible after creation) and your **Team ID** (Apple Developer → Membership)
- [ ] Send `.p8` contents + both IDs to your AI agent (or store them in 1Password)
- [ ] **Me.** Set on Railway:
  ```bash
  railway variables \
    --set "APNS_KEY_P8=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----" \
    --set "APNS_KEY_ID=ABC1234567" \
    --set "APNS_TEAM_ID=XYZ7654321"
  ```
- [ ] **Me.** Verify backend boot log no longer shows "APNs not configured" warning

**Done when:**
- Railway env has all three APNs variables set
- Backend boots with "APNs configured" log line
- Test push delivered to a real device (use `POST /v1/devices/register` then trigger any push)

**Where the backend consumes them:** `tempo-backend/Sources/App/configure.swift:90-92`

### 1.5 Privacy Policy + Terms of Service

- [ ] **You.** Use a generator (Termly, iubenda, Free Privacy Policy) — ~20 min each
- [ ] **Mandatory clauses for Tempo specifically:**
  - Data sent to Anthropic (third-party AI processor) — explicit
  - HealthKit data usage (workouts, sleep, heart rate, HRV, RHR) — explicit per HealthKit guideline
  - Whoop integration (OAuth, biometric data)
  - EventKit calendar access (read-only, used for free-window detection)
  - Sign in with Apple — name + email + user ID
  - Subscription billing via Apple
  - Data retention policy (how long after deletion?)
  - Account deletion — required by Apple as of 2022, required by GDPR Article 17
- [ ] Host both URLs somewhere stable:
  - Option A: GitHub Pages (free, fast)
  - Option B: Notion public pages (`notion.so/...`)
  - Option C: Your future `tempo.app` site
- [ ] **You.** Paste both URLs into App Store Connect → App Information → Privacy Policy URL + EULA URL
- [ ] **You.** Paste them again into the Onboarding `.aiConsent` view as tappable links — currently the AI consent step explains AI data sharing but doesn't link to either doc

**Done when:**
- Both URLs return 200 with the actual policy text (not "coming soon")
- App Store Connect shows them under App Information
- The iOS onboarding screen renders them as tappable links opening Safari

### 1.6 App Privacy questionnaire

- [ ] **You.** App Store Connect → App Privacy → Get Started
- For each data type Tempo collects, declare:
  - **What:** Health & Fitness (HealthKit), Identifiers (user ID), Contact Info (email from Apple ID), Usage Data (workout/meal/sleep logs), etc.
  - **Linked to user?** Yes (you store per-user)
  - **Used for tracking?** No (you don't track across apps for ad targeting)
  - **Purpose:** App Functionality, Analytics (if PostHog is enabled)
- Be **truthful**. Apple's automated checks will catch lies; rejection lands within 24h.
- Reference: https://developer.apple.com/app-store/app-privacy-details/

**Done when:** the questionnaire is complete; App Store Connect shows "App Privacy Details Complete."

### 1.7 App icon + screenshots + preview video

- [ ] **You** (design — Figma, etc.). **Me** can help with naming/sizing/asset catalogue.
- **App icon:** 1024×1024 PNG, no transparency, no rounded corners (Apple adds them automatically)
- **Screenshots — minimum required device sizes:**
  - 6.5" Display (iPhone 11 Pro Max, 12-15 Pro Max, etc.): **1284×2778** or **1290×2796**
  - 5.5" Display (iPhone 8 Plus): **1242×2208** — yes, still required. Apple's matrix is legacy.
  - Optional: 6.7" (1320×2868) — recommended for latest devices
- **3–10 screenshots per size**. Best practice: show different modules (Dashboard, Training, Daily Plan, Coach).
- **Tip:** use a Figma "iPhone frame" template + simulator screenshots, or services like ScreenshotMaker.
- **App preview video** (optional, 15-30s): boosts conversion ~5-10%. Defer to post-launch v1.1 if pressed for time.

**Done when:** App Store Connect → Media → Screenshots shows the full set for each required size.

### 1.8 App Store listing copy

- [ ] **You.** App Store Connect → App Information + Version Information
- **Subtitle** (30 chars): one-line hook. e.g. "Your athletic life, operationalised"
- **Promotional text** (170 chars): the App Store search snippet. Most read.
- **Description** (4000 chars max): full marketing copy. Lead with the problem (5 apps doing 1 each), then the modules, then the AI angle.
- **Keywords** (100 chars, comma-separated): for App Store search. Tools: AppFollow, AppTweak (free tier). Suggest: `fitness, nutrition, meal plan, recovery, whoop, training, study, accountability, life os, daily plan`
- **Support URL:** Notion page with your email or a real support site.
- **Marketing URL** (optional): your future tempo.app.
- **Copyright:** `© 2026 Nicola Debbia` (or your LLC if you have one)

**Done when:** all fields are non-empty in App Store Connect; no validation warnings.

### 1.9 Sign in with Apple — end-to-end test

- [ ] **Both.** Code exists (`Tempo/Tempo/Services/Auth/AppleSignInService.swift`); never verified in prod.
- [ ] **You.** TestFlight build to a real device.
- [ ] **You.** Tap "Sign in with Apple" — complete the flow.
- [ ] **Me.** SSH-equivalent — `railway logs --deployment` while you tap.
- [ ] **Me.** Query prod Postgres after the sign-in:
  ```sql
  SELECT id, apple_user_id, created_at FROM users ORDER BY created_at DESC LIMIT 5;
  ```
- [ ] **Me.** Verify JWT was minted, refresh token row exists in `refresh_tokens`, subsequent `GET /v1/user/me` returns 200.
- [ ] **If broken:** debug. Probably an Apple ID config issue in the Xcode capabilities tab or a missing `Sign In with Apple` entitlement.

**Done when:**
- A fresh Apple ID can sign in and a `users` row is created in prod
- Subsequent gated API calls return 200 (or 402 for non-Pro routes, which is correct)
- Token refresh works after the initial JWT expires

### 1.10 Whoop OAuth callback URL

- [ ] **Me.** Grep for the existing redirect URI: `grep -rn "redirect_uri\|callback" tempo-backend/Sources/App/Controllers/Whoop*`
- [ ] **You.** Log into the Whoop developer dashboard → your app → update Redirect URI to:
  ```
  https://tempo-backend-production-39dc.up.railway.app/v1/integrations/whoop/callback
  ```
  (or whatever the actual path is — confirm via grep first)
- [ ] **Both.** Test Whoop connection flow from a real device.

**Done when:** tapping "Connect Whoop" on the app completes the OAuth dance and `whoop_integrations` has a row for your test user.

---

## Phase 2 — Verify it actually works

**Goal:** stop assuming it works because the build is clean. Prove it on a real device.

**Estimated wall-clock:** 1 week of focused testing, more if bugs surface (they will).

### 2.1 Click-through onboarding on a real device

- [ ] **You** (TestFlight, after Phase 1).
- Install via TestFlight as a fresh user (uninstall first if you have a dev build).
- Walk through every step:
  - Splash → ValueDemo → Goals → HealthKit → Auth → Profile
  - Training Setup → Academic Setup → **Daily Rhythm** (NEW) → **Class Schedule** (NEW)
  - **Eating Window** (NEW) → **Study Preferences** (NEW) → **Training Preferences** (NEW)
  - **Weekend Mode** (NEW) → Whoop → Notifications → **AI Consent** (NEW) → Complete
- Note every layout bug, picker bug, copy bug, missing icon, broken navigation.
- The new steps (6 of them, added in Fix #6) have never been seen on a real device.

**Done when:** you reach the dashboard from a clean install without any visible bug. Bug list captured in GitHub issues (or a Notion doc) for follow-up.

### 2.2 Sandbox subscription purchase

- [ ] **You.** App Store Connect → Users & Access → Sandbox Testers → + Create
- Email: something you don't use (`nicola+sandbox@gmail.com` with `+` aliasing)
- Password: anything (just for sandbox)
- Country: US
- [ ] **You.** On your test device: Settings → App Store → Sandbox Account → sign in with sandbox ID (sign out of your real Apple ID for App Store only; iCloud stays signed in)
- [ ] **You.** Open Tempo → tap "Upgrade to Pro" → buy monthly tier → confirm receipt
- [ ] **Both.** Verify backend received the receipt:
  - `railway logs --deployment` should show `[subscription] Verified receipt for user X`
  - `psql ... -c "SELECT * FROM user_subscriptions WHERE user_id = '...';"` shows an active row
  - Subsequent AI route call returns 200 instead of 402

**Done when:** sandbox purchase round-trips: tap → Apple sandbox → backend → user marked Pro → AI route flips from 402 to 200.

**Failure modes to watch for:**
- StoreKit configuration file (`StoreKit.storekit`) in Xcode overrides App Store Connect — make sure Production scheme doesn't use it
- Sandbox receipts are signed differently; backend must call Apple's sandbox endpoint when verification fails on production endpoint

### 2.3 Real HealthKit + Whoop data ingestion

- [ ] **You.** Connect your real Whoop in the app (assumes 1.10 is done).
- [ ] **You.** Wait for the daily sync (or trigger manually if you've added a button).
- [ ] **You.** Verify on the dashboard:
  - Today's recovery score matches the Whoop app
  - HRV, RHR, sleep duration match
  - Strain is populated for yesterday
- [ ] **You.** Log a workout via the iPhone app:
  - Pick a workout type, log sets/reps
  - Mark complete
  - Verify it appears in `workouts` table in prod
  - Verify HealthKit shows it (Apple Health → Browse → Workouts)
- [ ] **Both.** If recovery score is `-1` or "—", debug the data flow:
  - `WhoopService.syncAll` is called
  - `whoop_recovery` row exists for today
  - `DashboardViewModel` reads from it

**Done when:** the dashboard reflects your real Whoop + HealthKit data for the current day, not placeholder values.

### 2.4 Real meal flow (the v1.0 nutrition shipping bar)

- [ ] **You.** Generate a weekly meal plan (`/v1/nutrition/ai/meal-plan/generate`, gated, Pro user only).
- [ ] **You.** Open today's plan, mark a meal eaten via `MarkEatenSheet`:
  - Backward-fill time slider works
  - MealFeel chip selection works
  - Save commits + dismisses
- [ ] **You.** Verify the next meal's time shifted (per `MealShiftPlanner`).
- [ ] **You.** Leave feedback via `MealFeedbackSheet`.
- [ ] **You.** Open `WeeklyMealReviewView` end-of-week.
- [ ] **You.** Verify pantry decrement happened (a few grams of the meal's ingredients should be subtracted from pantry).

**Done when:** the whole nutrition loop works without errors on a real device.

### 2.5 Real calendar integration

- [ ] **You.** Grant calendar permission on first prompt.
- [ ] **You.** Add a class event to Apple Calendar (e.g. "STAT 101" Monday 9-10am).
- [ ] **You.** Open the Day Plan view (`DayPlanView`).
- [ ] **You.** Verify the class shows as a `class`-kind TimeBlock in the timeline at the correct time.
- [ ] **You.** Edit the event → change the time.
- [ ] **You.** Wait ~1.5s (debounce window) → verify the timeline re-rendered with the new time.
- [ ] **You.** Add an event titled "Football practice" → verify it classifies as `football` kind.

**Done when:** calendar changes propagate to the timeline within 2s, classification works correctly (class/exam/football/work fallback).

### 2.6 Push notifications on a real device

- [ ] **You.** Grant notification permission during onboarding.
- [ ] **Me.** Trigger a test push: `railway run -- swift run App schedule-test-push --user user_smoke_test_001` (or whatever the existing helper is).
- [ ] **You.** Verify the push arrives, has the correct copy, the icon, the tap-to-open-app routing.
- [ ] **You.** Wait for the next scheduled drill sergeant batch (Sun + Wed 20:00 UTC) OR run `railway run -- swift run App queues -- --scheduled` to fire it on demand.
- [ ] **You.** Verify the batch generated 36 copies and they're cached in Redis.

**Done when:**
- Test push arrives within 10s of trigger
- Tapping it opens the app to the correct deep-link target
- Scheduled batch fires and copies appear in `ai_response_cache`

### 2.7 Crashlytics + PostHog firing

- [ ] **Me.** Verify Crashlytics dSYM upload is happening in Xcode's build phases.
- [ ] **You.** In a debug build, trigger a test crash: tap a button that calls `fatalError("test crash")`.
- [ ] **You.** Reopen the app, wait for next crash upload.
- [ ] **Both.** Verify it appears in Firebase Console → Crashlytics.
- [ ] **Both.** Verify PostHog events are showing up: `app_open`, `subscription_started`, `ai_route_called`, etc.

**Done when:** both dashboards show events from your test device.

### 2.8 Backend uptime monitoring

- [ ] **Me.** Set up Uptime Robot (free tier, 50 monitors): https://uptimerobot.com
  - Monitor `GET https://tempo-backend-production-39dc.up.railway.app/health`
  - 5-min interval
  - Alert email + Slack/SMS
- [ ] **Me.** Railway has its own "service down" notifications; verify they're enabled in project settings.

**Done when:** if you kill the prod backend manually (`railway service redeploy` and watch it fail), you get a notification within 5 min.

---

## Phase 3 — Production hardening

**Goal:** plug holes that don't block submission but will bite you in week 2 post-launch.

**Estimated wall-clock:** 1–2 weeks in parallel with Phase 2.

### 3.1 Account deletion flow — Apple-required

- [ ] **Me.** Build a "Delete account" button in Settings (`Tempo/Tempo/Views/Settings/SettingsView.swift`).
- [ ] **Me.** Add confirmation alert: "Permanently delete your Tempo account. This cancels your subscription and erases all data. Cannot be undone."
- [ ] **Me.** New endpoint: `DELETE /v1/user/me` on the backend.
  - Cancels any active subscription via Apple's server-to-server API (or marks `is_active = false`)
  - Soft-deletes user row (`deleted_at = NOW()`)
  - Cascade-deletes: workouts, meals, recovery rows, pantry, grocery, day plans
  - Wipes their AI cache rows
  - Invalidates JWT refresh tokens
- [ ] **Me.** Update iOS to call the endpoint then sign the user out.
- [ ] **Both.** Test: delete a sandbox account, verify backend rows are gone, verify re-signing in creates a fresh user.

**Apple's requirement (since 2022):** the deletion must be initiated *in-app*, not via email or support form. Reviewers test this.

**Done when:** the button works end-to-end and a deleted user can't sign back into the old account.

### 3.2 Subscription receipt webhook (App Store Server Notifications V2)

- [ ] **Verify** `SubscriptionController.handleWebhook` is implemented and JWT-signature-verifies Apple's payload.
- [ ] **You.** App Store Connect → App Information → App Store Server Notifications → URL:
  ```
  https://tempo-backend-production-39dc.up.railway.app/v1/subscription/webhook
  ```
- [ ] **You.** Pick **Version 2** (not V1 — V1 is deprecated).
- [ ] **Both.** Test with App Store Connect's "Request Test Notification" button → backend should log receipt, return 200.
- [ ] **Both.** Trigger a real lifecycle event in sandbox (cancel, renew) → verify backend updates `user_subscriptions` accordingly.

**Done when:** sandbox subscription state changes in the backend within 30s of an Apple-side event.

### 3.3 Anthropic budget calibration

- [ ] **Me.** Watch actual usage in Anthropic console for first 30 days.
- [ ] **Me.** Estimate per-user monthly cost from real data (not the back-of-envelope $0.50 we used).
- [ ] **Both.** Raise `CLAUDE_MONTHLY_BUDGET_CENTS` when actual spend hits 60% of cap. Default $50 is fine until ~100 users.
- [ ] **Me.** Add a Slack alert when monthly spend crosses 50/80/95% thresholds (the code already implements the threshold ladder; just needs an outbound notification).

**Done when:** spend stays under cap, no surprises, you have a renewal cadence (monthly check) and an alert when usage spikes.

### 3.4 Drag-to-reflow on DayPlanView

- [ ] **Me.** Currently the day plan timeline is read-only (deferred per advisor's call in §9).
- Spec wants: drag a block → subsequent blocks reflow → persist new boundaries.
- SwiftUI: `DragGesture` + `@State offset` + custom snapping to 15-min intervals.
- ~1-2 days of focused SwiftUI work.

**Done when:** dragging a meal block to 13:00 from 12:00 shifts dinner from 19:00 to 20:00 automatically; bedtime fence still enforced.

### 3.5 Legal copy in onboarding

- [ ] **Me.** Add a separate ToS-acceptance step before `.aiConsent`:
  - "I agree to the Terms of Service and Privacy Policy [tap to open]"
  - Tappable links → in-app SafariViewController
  - Required to continue (no skip)
- [ ] **Me.** Persist `tos_accepted_at` timestamp on `User`. New migration.
- [ ] **Me.** Backend middleware: any non-auth route returns 451 (Unavailable for Legal Reasons) if `tos_accepted_at IS NULL`.

**Done when:** GDPR + Apple compliance — every active user has a `tos_accepted_at` non-null.

### 3.6 Stale-while-revalidate for hot AI routes

- [ ] **Me.** `AICache.withSWR` exists but is unused — all routes use synchronous `lookup` + miss-generates.
- [ ] **Me.** Upgrade these routes to SWR (cache hit returns stale immediately, fires background regen):
  - `GET /v1/insights/morning-briefing` — daily cache, perfect for SWR
  - `GET /v1/insights/weekly-report` — 7-day cache
  - `POST /v1/insights/dashboard` — data-hashed
- [ ] **Me.** Verify the existing `Request` Sendability constraint (the comment in `AICache.swift` mentions it) is workable now.

**Done when:** repeat calls to these routes return < 100ms (cache hit) instead of 1-3s (Claude call).

### 3.7 Background task scheduler

- [ ] **Both.** Your runtime log showed `BGTaskScheduler error 1` in simulator (expected — simulator can't schedule background tasks).
- [ ] **You.** Test on a real device:
  - Schedule the daily reset task
  - Force-quit the app, wait 24h, see if it fired
- [ ] **Me.** Verify `Info.plist` has `BGTaskSchedulerPermittedIdentifiers` for the identifiers you register.

**Done when:** the daily reset, streak rollover, and any other background-only tasks fire on real devices.

### 3.8 Localization (deferred to v1.1)

- For v1 launch: **English-only is fine.**
- Italian would 2x your reachable audience (your overlap market).
- ~1 week to extract strings to `Localizable.strings` + translate.
- Defer until you have data showing >5% of users in Italian-speaking countries.

### 3.9 Accessibility audit

- [ ] **Me.** Run Xcode Accessibility Inspector against every screen.
- [ ] **Me.** Add VoiceOver labels to every Button/Image/icon that doesn't have visible text.
- [ ] **Me.** Test at 200% Dynamic Type — some custom views will break.
- [ ] **Me.** Test high-contrast mode — verify the amber-on-black palette stays legible.

**Done when:** VoiceOver can navigate every screen and announce every interactive element correctly. Apple sometimes rejects on this; cheap to fix in advance.

### 3.10 Delete the old Anthropic key

- [ ] **You.** Anthropic console → API Keys → trash the OLD key (the one that previously shipped on your device).
- The new key (set on Railway as of 2026-05-15) is what serves prod now.
- ~30 seconds.

**Why this matters:** the old key was burned the day it shipped in any iOS .ipa. Until you delete it from the Anthropic console, it's still capable of being used by anyone who extracted it. Deleting it makes the burn final.

**Done when:** Anthropic console shows only the production key + any other keys you actively use (one per project).

### 3.11 Custom domain (optional)

- [ ] **You.** Buy `tempo.app` or `usetempo.app` (~$15/year on Namecheap, GoDaddy, Cloudflare).
- [ ] **Me.** Railway → tempo-backend → Settings → Custom Domain → add `api.tempo.app`.
- [ ] **You.** DNS provider → add CNAME `api.tempo.app` → `tempo-backend-production-39dc.up.railway.app`.
- [ ] **Me.** Update `Tempo/Tempo/Configuration/Production.xcconfig:9` to point at `https://api.tempo.app`.
- [ ] **You.** Submit a new App Store build with the updated URL.

**Why bother:** the only real reason is **future-proofing migrations**. If you ever move off Railway, you don't need to ship a new iOS build — just point DNS elsewhere.

**Defer until:** you have ~100 users or you're seriously considering a host migration. ~30 min total.

**Done when:** `https://api.tempo.app/health` returns 200 and the Production iOS scheme talks to it.

---

## Phase 4 — Marketing / pre-launch minimum

**Goal:** launch into something other than silence. This is the tactical floor; not a growth playbook.

### 4.1 Landing page

- [ ] **You.** One page at `tempo.app` (or wherever).
  - Hero: "Your athletic life, operationalised" + 1-line subhead
  - 4-5 screenshots
  - "Coming soon to App Store" CTA with email capture
- Tools: Carrd ($19/year, drag-drop), Framer (free), Notion + Super.so, or hand-roll HTML.
- ~1 day.

**Done when:** real URL with real screenshots + working email signup form.

### 4.2 Social presence

- [ ] **You.** Twitter/X account: `@tempo_app` or `@usetempo`.
- [ ] **You.** Personal account post 2 weeks before launch: "I've been building this for 6 months. Beta starts next week. [screenshots]"
- [ ] **You.** TestFlight public link (10,000 testers max for free).

### 4.3 Pre-launch list

- [ ] **You.** ProductHunt submission scheduled for launch day (Sundays + Mondays are best).
- [ ] **You.** Email to subscribers from the landing page.
- [ ] **You.** DM 10-20 fitness/student-athlete creators with TestFlight access (most ignore; 1-2 might bite).
- [ ] **You.** Post in: r/Whoop, r/Fitness, r/GetMotivated, r/Productivity (read each sub's self-promo rules first — most require "[OC] I built this" framing).

### 4.4 Customer support

- [ ] **You.** Set up `support@tempo.app` (or use Gmail with a filter).
- [ ] **You.** Notion page for FAQ at `support.tempo.app` or under the marketing page.
- [ ] **You.** Commit to a 24-hour response SLA for paying customers.
- [ ] **You.** Have a refund policy you can quote (Apple makes refunds easy for the user; you mostly just need to not be a jerk about it).

---

## Realistic timeline

| Week | Focus | Outcome |
|---|---|---|
| 1 | Phase 1.1–1.4 (developer enrollment + StoreKit + APNs) | App Store Connect record exists, products created, APNs working |
| 2 | Phase 1.5–1.8 (legal + listing copy + icon/screenshots) | App Store Connect listing complete |
| 3 | Phase 2 (on-device testing) | TestFlight build, fix everything that breaks |
| 4 | Phase 3.1 (account deletion) + Phase 3.2 (webhook) + remaining bugs | Apple-compliance items shipped |
| 5 | Submit for review | Apple has the app; ~3-7 day review |
| 6 | First rejection cycle (assume one) + Phase 4 (marketing) | Resubmit with fixes; landing page live |
| 7 | Approval + launch | App in the App Store |

**Most common reasons indie launches stall here:**
1. Underestimating App Store paperwork. It's ~20-40 hours total. Block calendar time.
2. Sandbox StoreKit bugs. Always at least one weird thing.
3. Apple Review rejects on something minor (privacy policy clarity, accessibility, screenshot copyright). Plan for 1-2 cycles.

---

## The "what I'd do this week" prioritisation

Pasting the from-conversation list one more time so it's preserved:

**Today**
1. Apple Developer enrollment if not done. (Phase 1.1)
2. Delete old Anthropic key. (Phase 3.10)

**Tomorrow**
3. Create App Store Connect record. (Phase 1.2)
4. Create StoreKit products. (Phase 1.3)
5. Generate APNs key, send `.p8` + IDs to your AI agent. (Phase 1.4)

**This week**
6. Privacy policy via Termly. (Phase 1.5)
7. App Privacy questionnaire. (Phase 1.6)
8. App description, screenshots, icon. (Phase 1.7 + 1.8)

**Next week**
9. TestFlight build. Click through everything on your iPhone. (Phase 2.1–2.6)
10. Fix what breaks. Iterate.

**Following week**
11. Submit for review.
12. Phase 3 hardening in parallel.

---

## Where to ask for help

- **Apple Developer Forums** — for App Review rejection appeals
- **Hacking with Swift** + **Pointfree** — for SwiftUI questions
- **Vapor Discord** — for backend questions
- **Anthropic Discord** — for Claude API quotas/limits
- **Indie Hackers** — for pricing, marketing, launch strategy

---

## What this document is NOT

- Not a roadmap for v1.1+. Features beyond launch live in `docs/BUILD_PROGRESS.md` and any new ADRs.
- Not legal advice. Talk to a lawyer if you're unsure about LLC formation, ToS specifics, or international data transfer obligations (especially if you accept EU users).
- Not a guarantee. Apple Review is non-deterministic. Same app, different reviewer, different verdict. Plan for 1-2 rejection cycles minimum.

---

## Maintenance

Update this file as items complete. Mark a checkbox by replacing `[ ]` with `[x]` and add a date suffix:

```
- [x] **You.** Enroll at https://developer.apple.com/programs/enroll/ ✅ 2026-05-20
```

When all of Phase 1 + Phase 2 is checked, the next AI session should move launch-tracking to a new doc (`docs/POST_LAUNCH_PLAN.md`) and leave this one as historical record.

---

*End of launch punch list. Last edited 2026-05-15. Next review: weekly until launch.*
