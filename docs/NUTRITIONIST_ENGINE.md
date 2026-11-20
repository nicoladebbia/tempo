# Nutritionist Engine — record

Started 2026-11-20 on branch `feat/nutritionist-engine` (backend first). Replaces the AI-only weekly plan as the source of truth once finished.

## Goal (Nicola, 2026-11-20)
A much deeper nutritionist: "this week you eat this, this and this", easy to read. It must say *why* from his own data: low on protein (needs ~20 g more), low sun so vitamin D3, and so on. All macros AND micronutrients of every food, not generic advice.

## Decisions
- **New engine replaces the old plan** (not a second tab).
- **Order:** data + gap detector first, then plan solver, then UI.
- **Supplements: full stack** (his choice). My advice recorded: ship it only with hard limits (UL, interactions, medical disclaimer), because a public app that doses people is an App Store and liability risk. Stage 4 builds those limits in.

## What already existed (do not rebuild)
- `MacroSolver` + `WeeklyPlanPipeline` (backend): deterministic gram scaling to calorie/protein/carb/fat targets, using verified USDA per-100g values. Macros only (kcal, protein, carbs, fat, fiber).
- `FoodNutritionResolver` + `food_nutrition_cache` (USDA Foundation + SR Legacy, cached).
- iOS: 418-food hand table `FoodMacroDatabase`, supplement catalog + AI picks, meal logging, grocery/pantry.
- Gap: no vitamin/mineral data, no targets, no gap analysis, no sun/sleep context. (Earlier chat claim "numbers are decorative" was too strong: macros are solver-verified.)

## Built (stage 1, backend, commit on this branch)
| File | What |
|---|---|
| `Nutrition/NutrientCatalog.swift` | 29 nutrients with USDA ids (checked against a live `foods/search` response 2026-11-20), units, names; `MicronutrientExtractor` |
| `Nutrition/NutrientTargets.swift` | NIH RDA/AI/UL for adults 19+ by sex and age band. Under 19 / pregnant / lactating return nil: not guessed |
| `Nutrition/GapDetector.swift` | Pure, deterministic: ignores half-logged days (<60% of kcal target), needs 3+ good days, severity bands (<50/<75/<90% of target), protein gap, total-UL and sodium overages, low-sun explanation + vitamin D escalation, ranking |
| Resolver + cache + migration `AddMicrosToFoodNutritionCache` | per-100g micros stored as jsonb; rows cached before this refetch once |
| `Tests/AppTests/NutritionistEngineTests.swift` | 20 tests incl. real Postgres round trip |

Verified: full backend suite 276/276 passing locally (own test DB). Not verified: nothing runs on a phone yet, no API route exposes this yet.

## Review findings (reviewer agent, 2026-11-20)
- FIXED: copper was typed as µg but USDA reports mg (every user would have shown a false copper gap). Now mg, target 0.9, UL 10, plus a test pinning every nutrient's unit to USDA's.
- FIXED and VERIFIED (2026-11-20, Docker back, full backend suite 320/320 passing after a test-DB reset): refreshing an old cache row could overwrite good cached macros with a miss, or lose them on a USDA 429/5xx. The old hit is now kept as fallback. Two new tests cover it (`legacyRowSurvivesAUSDAErrorDuringRefresh`, `legacyRowSurvivesAUSDAMissAndStopsRefreshing`) both pass.
- OPEN, vitamin A: NIH's UL (3000 µg RAE) is for preformed retinol, which liver can exceed from food alone. We mark it supplements-only and don't track retinol (USDA id 1105) yet. Add retinol with a `.total` limit before the supplement advisor ships.
- OPEN, stage 2: the gap detector treats a nutrient USDA didn't report as 0. The `DailyIntake` builder must track how much of each nutrient was actually reported (Foundation foods report fewer micros) or it will show false gaps.
- Source check: NIH fact-sheet pages return 403 to automated fetch, so the target table was checked against published DRI values, not the pages. Re-check against the pages by hand once.

## Editorial heuristics (not medical facts, tunable)
- Low daylight = under 20 min/day (`GapDetector.lowDaylightMinutes`); winter at |lat| >= 35.
- 60% log-coverage filter, 3-day minimum.
- Priority list for ranking equal-severity gaps.
- EPA/DHA: 125 mg each (EFSA 250 mg combined). Sodium treated as a limit (2300 mg).
- No athlete uplift on any micronutrient yet: no source I trust, so left at RDA.

## Coach: recovery math (started 2026-11-20, session 2)
Nicola's asks: after a hard session/match the coach says what to drink and eat with real physiology math and explains why; later a menu-photo mode that picks the best dish for the remaining macros. Decisions: weight from the Withings scale via Apple Health, manual entry when away; push right after a WHOOP workout; recovery math first, menu photo second.

Built (backend, pure code, `Nutrition/Recovery/`): `SweatBalance` (pairs pre/post weigh-ins, refuses to claim a number when one is missing or implausible, unknown fluid intake = lower bound) and `RecoveryPlanner` (sweat as a range, sodium as a range, fluid, carbs, protein, one evidence line per number). 17 tests, no database needed.

Constants, with provenance in `RecoveryConstants`:
| Constant | Value | Status |
|---|---|---|
| Non-sweat share of body-mass loss | 5-15% | VERIFIED, Baker 2017 (PMC5371639), full text read |
| Sweat sodium | mean 35, range 10-70 mmol/L | VERIFIED: ACSM 2007 (mean + range), Baker 2017 (range) |
| Rapid carb refuel (<4 h) | 1.2 g/kg/h, or 0.8 g/kg/h + 0.2-0.4 g/kg/h protein | VERIFIED, Kerksick 2017 ISSN nutrient timing (PMC5596471) |
| Very high load daily carbs | 8-12 g/kg/day (>= 8 h exercise/week) | VERIFIED, same |
| Protein per dose / day | 0.25 g/kg or 20-40 g, 700-3000 mg leucine, every 3-4 h; 1.4-2.0 g/kg/day | VERIFIED, Jäger 2017 ISSN protein (PMC5477153) |
| Rehydration multiple | 1.5 L/kg for rapid recovery, else 1.0 | VERIFIED: ACSM 2007 (Sawka) read in full + Maughan 1996 (PMID 8781863): water alone at 150% left ~0.35 L net negative at 6 h, with a meal balance was restored |
| WHOOP strain zones | High 14-17, All Out 18-21 | UNVERIFIED (snippet). Used for tone only, never in a calculation |

Design rules from the sources: Baker 2017 advises giving ranges or low/moderate/high categories, not pinpoint values; the coach follows that. The apple/magnesium example earlier was wrong by ~100x: an apple has ~9 mg magnesium, and sweat loses only mg-level magnesium; the real sweat loss is water and sodium.

Open: read ACSM 2007 / Thomas 2016 by hand to verify the rehydration multiple and daily carb bands; WHOOP zones from whoop.com; weather/humidity sweat-rate model not researched; route + push + WHOOP workout trigger not built; hydration quick-logging (Lock Screen/Control Center/Action Button/Siri/notification buttons, iPhone only) designed but not built; menu photo not built.

### Sweat calculator: accuracy audit and physics model (2026-11-20)
Goal asked: error <= 5% of the real sweat.

Papers Nicola supplied, all read in full (PDF text extracted and checked): Maughan, Shirreffs & Leiper 2007 (J Sports Sci 25:797-804; author order corrected, I had it as Leiper first), Mitchell, Nadel & Stolwijk 1972 (J Appl Physiol 32:474-476, scanned PDF, equations confirmed in two places), Sawka et al. 2007 ACSM position stand (MSSE 39:377-390).

Verified equations and numbers now in code (`NonSweatLoss`, `RecoveryConstants`, `SweatElectrolytes`):
- sweat = body mass lost + fluid ingested - substrate oxidised + water of oxidation - respiratory water (Maughan 2007; the paper's marathon example 3 + 1 - 0.55 + 0.42 - 0.40 = 3.47 L is a test).
- respiratory water m = 0.019 * VO2 * (44 - Pa) g/min (Mitchell 1972 eq. 3; Maughan's 2.7 / 0.8 / 3 / 0.2 ml/min examples reproduce as tests). Mitchell found measured values 15-20% BELOW this at moderate loads (within 0.25 g/min); tested only in dry air (Pa 7-10 mmHg) on 4 subjects, so humid days are an extrapolation and the output says so.
- gas-exchange mass loss m = VO2 * (R*1.96 - 1.43) g/min (Mitchell eq. 4; R = 1 -> 0.53 * VO2; equals Maughan Table I: carbohydrate -0.40 g/g, fat +0.13 g/g).
- ACSM 2007: ~1.5 L per kg lost for RAPID recovery; otherwise replace the deficit (normal meals and drinks, 8-12 h); sodium helps retention. Sweat Na averages ~35 mEq/L (range 10-70) (replaces my midpoint 40); K 5 (3-15), Ca 1 (0.3-2), Mg 0.8 (0.2-1.5), Cl 30 (5-60) mEq/L. A 2 L sweat loses only ~19 mg magnesium (4-36 mg): the earlier "300 g" idea was wrong by orders of magnitude.

Accuracy result: with only a weigh-in and the generic 5-15% band, the floor is about +/-6% (95%) even with a perfect scale. With the physics model (WHOOP energy + weather) the non-sweat term shrinks to ~+/-0.04 kg absolute, so the scale becomes the limit. 5% (95% interval) is reachable only when ALL hold: measured scale repeatability (about 0.02 kg), tight weigh-in protocol, fluids logged, and a large loss (the test shows <5% at 3 kg lost, >5% at 1 kg). The app shows the +/- on every number and `meetsFivePercentTarget` is true only when it really is.

Bugs fixed: weigh-in rejected when taken minutes before WHOOP's recorded end/after its start (10 min slack); `sweatLiters` overstated sweat (now raw + corrected range); weigh-in protocol tag (tight = both within 30 min).
Still assumed (NOT verified): Withings scale repeatability 0.05 kg (stated precision 0.05 kg is verified; repeatability is measured by `ScaleCalibration`), WHOOP energy error within 20%, R 0.85-1.0 (mid 0.92), Weir energy-to-O2 formula 3.941 + 1.106 R (textbook), user fluid estimate within 10%, WHOOP kilojoules = total energy of the workout, the 15-20% Mitchell reading (scale 0.8-1.0, mid 0.9).
Still blocked/unread: a validation study of WHOOP energy expenditure (none found open-access); Thomas 2016 ACSM/AND/DC (daily carb bands, not needed: ISSN covers it); whoop.com strain zones; NIH fact sheets (target table checked against published DRIs, not the pages). Validation against ground truth (controlled drink-and-weigh test) not done.

### Devices, data and measured results (kept private)
Personal device facts, health-data analyses, backtests and where the research files live are NOT in this public repo. They are kept in the owner's private notes. Public facts only: the app supports WHOOP (v2 API), a Withings scale read through Apple Health, and manual weigh-ins; no Apple Watch is assumed. Scale precision 0.05 kg is Withings' stated figure; repeatability is unknown until measured by `ScaleCalibration`. No peer-reviewed validation of WHOOP energy was found; its error moves a sweat estimate only ~1-2%.

### Recovery coach pipeline (built 2026-11-20; backend done and tested, iPhone lane in progress on `feat/coach-ios`, stacked on Nutrition Round 3)
Goal (Nicola): after a match everything is detected automatically; nothing is uploaded by hand.
1. WHOOP finishes a big workout (>= 20 min and >= 150 kcal) -> webhook `workout.updated` (instant) and a 10-minute sweep (`CoachWorkoutWatchJob`, safety net) both call `CoachWorkoutWatch.check`. ONE push per session (`post_workout_weighin`, category `POST_WORKOUT_WEIGHIN`), idempotent through Redis `coach:notified:<user>:<workout>` (3 days), only 2 min to 4 h after the workout ended.
2. iPhone: reads Withings weights from Apple Health around the session, takes the fluids answer from the notification buttons or the in-app screen, calls `POST /v1/coach/recovery`.
3. Server: `SweatBalance` (weigh-ins, error budget) + `NonSweatLoss` (breathing water and fuel burn from WHOOP energy and weather) + `RecoveryPlanner` (drink with a meal, sodium, carbs, protein, evidence). Returns a RANGE with a margin of error; `meets_five_percent_target` is true only when it really is.
4. Weather: Open-Meteo behind `WeatherProviding` (free tier is NON-COMMERCIAL: swap for WeatherKit or a paid plan before a public release). Coordinates rounded to 0.1 degree; a weather failure never fails a request.
5. Pre-match reminder (iPhone local notification 60 min before a scheduled football session) and quick drink answers are in the iPhone lane.
Files: `tempo-backend/Sources/App/Coach/*`, `Nutrition/Recovery/*`; contract goldens `contracts/golden/coach-*.json` and `push-post_workout_weighin.json`; test server: `testenv.sh job run coach-workout-watch --as NAME` (a fake finished 80-min match, always available).
Not done / to decide: Pro vs free gating; deploying the backend and registering the WHOOP webhook in the WHOOP developer portal (unknown whether it is registered; the sweep covers it); real-iPhone verification; ACSM-style per-user sweat-rate learning.

### WHOOP integration: problems found and fixed (2026-11-20, verified against developer.whoop.com)
Found while reviewing the coach backend; all in code that existed BEFORE the coach:
1. **Decoder clash:** every WHOOP DTO declares its own snake_case `CodingKeys`, but the app-wide decoder (`configure.swift`) already converts snake_case, so a real WHOOP record failed with `Key 'user_id' not found`. Reproduced with WHOOP's own sample. Only empty fixture responses ever passed the tests. Fix: `WhoopJSON` (plain decoder) at the 8 decode sites in `WhoopAPIService`. NOT fixed: the same clash may exist in other DTOs that use explicit keys on app-decoded paths (the webhook event was fixed).
2. **v1 is being retired:** WHOOP states "v1 webhooks have been removed"; v2 uses UUID ids, `sport_name`, `zone_durations` (developer.whoop.com v1-v2 migration guide + changelog). The existing data endpoints (`/v1/whoop/recovery|sleep|workouts|cycles`, `WhoopDataController`) still call `/developer/v1`; WHOOP gives no sunset date for the v1 DATA endpoints and third parties disagree (one says 2025-10-01). Whether v1 data endpoints still answer for Tempo is UNVERIFIED (needs a real token). The coach uses v2 only.
3. **Webhook signature never matched WHOOP's scheme:** docs say headers `X-WHOOP-Signature` and `X-WHOOP-Signature-Timestamp` (milliseconds), signature = base64(HMAC-SHA256(timestamp + raw body, client secret)) with NO separator. The old code read other header names, treated the timestamp as seconds, put a dot between timestamp and body, and compared hex. Every real delivery was rejected. Rewritten to the docs (`WhoopWebhookMiddleware`), 5 tests. The secret is `WHOOP_WEBHOOK_SECRET`, falling back to `WHOOP_CLIENT_SECRET`.
4. Webhook event decoding: numeric (v1) and UUID (v2) ids both accepted; Redis idempotency key was using a field that never decoded.
To use the instant webhook: in the WHOOP Developer Dashboard set the webhook URL (https://<api>/v1/webhooks/whoop) with model version **v2**. Until then the 10-minute sweep does the detecting.
Open decision for Nicola: migrate the remaining v1 data endpoints (recovery, sleep, cycles, workouts) to v2 (the Tempo dashboard depends on them); needs a real WHOOP token to verify.

## Next stages
2. **Intake aggregation + API:** sum logged foods (and supplements) into `DailyIntake`; route `GET /v1/nutrition/gaps`; contract golden + iOS DTO. Nicola has NO Apple Watch (WHOOP + Withings scale + iPhone), so HealthKit `timeInDaylight` does not exist for him. Sun exposure must come from weather sunshine/UV for his location, outdoor WHOOP workouts and iPhone walking, and a one-tap manual 'did you get sun today?'. Sleep and strain come from the WHOOP API.
3. **Plan solver:** extend MacroSolver to a micronutrient-aware choice (pick foods that close the top gaps within calorie/macro targets); AI writes recipe names/steps only; every number from USDA data. Plain "this week you eat" view with the reason per line.
4. **Supplement advisor:** gap + context -> D3, magnesium, creatine, omega-3 etc. with dose, timing, UL check against food+supplement total, interactions, "see a doctor" rules. Replaces fixed 2000 IU quick-add.
5. **iOS UI** + device-test page for Nicola (required by CLAUDE.md for big changes).
6. Retire the old AI-only plan path; update docs/INDEX.md.

## Open questions
- Does Nicola want the Whoop recovery/strain used to scale needs? (data exists, evidence for scaling is weak)
- Pro/free split for the Nutritionist (docs/MONETIZATION_STRATEGY.md).
- Collisions: Nutrition audit session (PRs #78/#79, claims from Oct 2026 are stale) touches the supplement and meal files; stage 2+ will need claims on the progress page.

## Superseded
- The AI-only weekly plan description in `docs/NUTRITION_PERSONALIZATION_DESIGN.md` §0 stays valid for what exists, but its "feed more data into the prompt" direction is replaced by this engine.
