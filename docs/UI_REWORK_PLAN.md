# Tempo UI/UX rework plan

Started 2026-11-22. Branch `feat/ui-rework`. Everything below was decided with Nicola unless marked "proposed".

## Goal

A brand-new Tempo: new look, new navigation, far fewer screens, and an app that feels instant. Nothing of the current identity is fixed (tone, names, quadrants, colours, logo are all open).

## Decisions

| Topic               | Decision                                                                                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Look                | Three directions built as real screens in the simulator (Today, workout logger, food log, "+" sheet). Nicola picks one.                                   |
| Minimum iOS         | 26. One look, no fallback chrome.                                                                                                                         |
| Navigation          | 4 tabs: Today, Train, Fuel, Arena, plus a "+" capture button on every screen. Recovery and Lockdown open from Today.                                      |
| Screen count        | About 182 live screens today, target about 90. No feature removed.                                                                                        |
| Code limits         | Anything in the iOS app may change if it makes the app faster or better. Backend changes were not discussed, so none are planned.                         |
| Bugs met on the way | Navigation and wiring bugs are fixed by the rebuild. Logic and number bugs go to the Nutrition/Training sessions through the progress page `shared` list. |
| Rollout             | Foundation first, then one PR per area, each with a device-test page.                                                                                     |

## Where the app is today

Measured on 2026-11-22 (Debug build, simulator, local test backend).

- 182 live screens: Nutrition 62, Training 40, Onboarding 21, Settings 16, Lockdown 12, Dashboard 10, Arena 10, Recovery 7, Global 4. About 14 more are dead code (the whole Coach module, WeeklyReportView, DayPlanView, PrivacyInfoView, ArenaIntroView, SignInWithAppleView).
- Cold launch to Dashboard content: 1.4 to 1.8 s. Tab switches show a wrong state first (Training shows Rest Day before Push Day; Recovery shows 0 before 78).
- Taps: first working set 7, one meal 5 plus typing, water 2, onboarding about 27.
- Arena is only reachable from the bottom of the Dashboard, and every "See All" inside it bounces back to the Dashboard.
- The same number differs between screens (water target, protein, fat, rest day vs push day, Whoop state, subscription state).
- 723 literal font sizes and 95 literal corner radii bypass the design tokens. No shaders, no zoom transitions, no matched geometry. Lottie is linked and never used.
- What works and should survive in spirit: the at-a-glance home, the meal logging path, the set logger with pre-filled targets, the grams-first plan preview and Store Mode, fast tab switches.

## What the apps people use daily do

- Three or four tabs and one scrolling Today page (Whoop, Oura).
- One persistent capture action. Logging is judged by action count (MacroFactor: quick-add 3, barcode 5, search 10).
- Scores on top, detail one level down, slow-moving trends on their own page.
- Today changes through the day and points at one next action.
- Streaks that forgive. A widget or Live Activity tied to the next action.
- Mistakes to avoid: one tab per domain, hiding the start action, dense first-launch dashboards, punishing streaks.

## New structure (proposed map, about 85 screens)

**Today (10).** Today · Recovery (today, sleep, strain and trends in one page with a time-range switch) · Metric detail · Lockdown and tasks · Focus timer · Task editor · Streak calendar · Week in review (replaces 8 recap screens) · Study and exams · Score explained.

**Train (20).** Train home (today's session and week strip) · Active workout · Workout summary · Week plan · Exercise library · Exercise detail · Progress (charts, muscle map and history in one) · Workout detail · Guided run · Run summary · Routines · Routine editor · Trainer program (with history and change log) · Program import · Program review · Trainer report · Away mode · Mobility player · Pain report · Conditioning log.

**Fuel (18).** Fuel home (today, water, next meal) · Week plan · Meal detail · Capture (search, scan, photo and voice in one screen) · Review what was recognised · Product page · Kitchen (pantry and groceries) · Store mode · Receipt capture and review · Receipts history · Supplements · Supplement detail · Add supplement · Recipes (suggest, write, ask AI) · Fuel setup · Coach · Weekly check-in · Grocery sharing and spend.

**Arena (6).** Arena home with the leaderboard inline · Friends · Challenges · New challenge · Achievements · Activity.

**"+" capture (1).** Meal, water, set or workout start, focus session, weigh-in, scan.

**You (9).** Settings · Profile · Schedule and training · Notifications · Connections (Whoop, Health, Calendar) · Subscription · Appearance · Data and account · Paywall.

**Onboarding (6).** Hook · Goal · Sign in · About you · Permissions · Ready. Everything else is asked later, in the place it is needed.

**Global (3).** Celebration · Requested meal · Post-session weigh-in.

## Budgets (what "instant" means)

| Measure                                       | Today                           | Target                                               |
| --------------------------------------------- | ------------------------------- | ---------------------------------------------------- |
| Cold launch to real content (Release, iPhone) | 1.4 to 1.8 s (Debug, simulator) | First frame under 400 ms, with last known data in it |
| Tab switch                                    | Wrong state for 0.15 to 0.2 s   | Correct content in the first frame, no spinner       |
| Scroll and transitions                        | Not measured                    | Hitch time under 5 ms per second                     |
| Log a set                                     | 7 taps to the first working set | 2 taps from Train, 1 tap per set after that          |
| Log a meal                                    | 5 taps plus typing              | 3 taps for a recent or planned meal                  |
| Log water                                     | 2 taps                          | 1 tap from "+"                                       |
| Onboarding                                    | About 27 taps                   | Under 10 taps to the first useful screen             |

How: every screen draws from a small saved snapshot first and refreshes quietly; launch work moves off the first frame; one navigation stack per tab; history screens load in pages; shaders are compiled at launch; formatters and heavy work leave `body`.

## Phases

Status on 2026-11-23:

0. **Direction lab.** Done. Nicola chose B ("Tide": glass on a living field) with A's numerals and live elements.
1. **Foundation.** Done (PR #88): Tide design system, 4-tab shell with "+", iOS 26 target, Lottie removed.
2. **Today.** Done (PR #88).
3. **Whole-app look ("Rework 2").** Done in code, on PR #88, waiting for Nicola's device test. Nicola asked on 2026-11-23 to finish the UI of every page first and to cut, merge and add features afterwards. So this pass restyled every screen in place and removed no feature:
   - A bridge maps the old `tempo*` colours, fonts, cards, buttons and page backgrounds onto Tide (`Color+Tempo.swift`, `TidePage.swift`), so no screen can fall back to the old look.
   - Each area was then rebuilt on Tide components: Train, Fuel, Kitchen/Scan/Supplements, Arena, Recovery, Lockdown, Settings, Paywall, Onboarding, Coach and the shared components. Area kits live in `DesignSystem/Tide+<Area>.swift`.
   - `Views/` now has no literal font size, no literal colour and no light/dark branch.
4. **Features (next, after the device test).** Remove what Nicola will never use, merge screens toward the ~85-screen map above, add and improve functions. Decisions go to Nicola first.
5. **Widgets, Live Activities, watch, accessibility pass, on-device speed pass.**

Each phase from 1 on: one PR, tests, simulator check against the local test backend, a device-test page for Nicola, and the cross-surface check for any shared model.

## The judge

Every screen passes a strict review before its PR:

- Screenshots at three phone sizes, at the largest and smallest text size, with a 4 pt grid overlay.
- A reviewer with no knowledge of the code scores hierarchy, alignment, spacing rhythm, contrast, tap targets (44 pt minimum, checked from accessibility frames), truncation and consistency with the system.
- Animation is reviewed frame by frame from a screen recording: no wrong first frame, no layout jump, nothing that blocks input.
- Snapshot tests lock the result so later changes show up as pixel differences.
- The design-token check must find zero literal sizes, colours or radii in new screens.

## Working with the Nutrition and Training sessions

The rework touches files both audit sessions edit. Before each area phase: check the progress page claims, claim the files, merge `origin/main` first. The foundation phase adds new files and the shell; the old screens keep working until their area is rebuilt.
