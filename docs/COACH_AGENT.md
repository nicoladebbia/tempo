# Coach Agent — v2.1

Canonical reference for the Coach AI agent. This is the as-built doc;
`.plans/coach-v2.1/` holds the design rationale.

## Status

| Phase | Status | Branch |
|---|---|---|
| Pre-1 Pantry FIFO | shipped | `feat/coach-pre1-pantry-fifo` |
| 1 Backend tool-use | built, smoke-test pending | `feat/coach-phase1-backend-tooluse` |
| 2 LearnedPreference | shipped | `feat/coach-phase2-learnedpreference` |
| 3 CoachTools | shipped | `feat/coach-phase3-tools` |
| 4 Memory layer | shipped | `feat/coach-phase4-memory-layer` |
| 5 Context assembler | shipped | `feat/coach-phase5-context-assembler` |
| 6 Agent loop | shipped | `feat/coach-phase6-agent-loop` |
| 7 Chat UI | shipped | `feat/coach-phase7-chat-ui` |
| 7.5 Interview | shipped | `feat/coach-phase7.5-interview` |
| 8 Memory UI + polish | shipped | `feat/coach-phase8-memory-and-polish` |

## What Coach is

A conversational AI in the Coach tab that learns the user's habits over
time and reasons from rich context. Day 1 it works generically; day 30
it cites learned preferences ("Nicola needs 2.5h between dinner and
sleep") and reasons from outcomes ("last 3 times dinner was <90min
before sleep, HRV dropped 8%").

Voice + inline pills make Coach reachable from Training, Nutrition Today,
and Recovery — Coach is a verb, not a destination.

## Architecture at a glance

```
                              user message
                                   │
                                   ▼
                   ┌─────────────────────────────────┐
                   │   CoachViewModel (Phase 7a)     │
                   │   - active conversation         │
                   │   - thinking / undo / budget    │
                   └────────────┬────────────────────┘
                                │
                       sendMessage(text, systemPrompt, ctx)
                                │
                                ▼
        ┌──────────────────────────────────────────────────────┐
        │            CoachService (Phase 6b)                   │
        │                                                      │
        │  1. pickModel → haiku/sonnet                         │
        │  2. POST via CoachChatAIClient                       │
        │  3. parse stop_reason → end_turn OR tool_use         │
        │  4. dispatch tools (loop) → tool_result              │
        │  5. summarize at message 12                          │
        │  6. hard caps: 8 turns / 20 tool calls               │
        └────────┬──────────────────────────────┬──────────────┘
                 │                              │
                 ▼                              ▼
   ┌─────────────────────────┐        ┌────────────────────────────┐
   │ CoachContextAssembler   │        │ CoachToolDispatcher (Adapter)│
   │   (Phase 5)             │        │   wraps CoachTools (Phase 3)│
   │ - identity              │        │ - moveMeal / swapDayType /  │
   │ - PreferenceRetriever   │        │   skipMeal / insertActivity │
   │ - today live / cal / 7d │        │ - askUser / record/update   │
   │ - 3.7K-token budget     │        │   Preference / shiftBedtime │
   └─────────────────────────┘        │ - queues PendingOutcome     │
                                       └────────────┬────────────────┘
                                                    │
                                              SwiftData mutation
```

Background jobs (nightly via `DailyResetCoordinator.runCoachMaintenance`):

- **BehaviorObserver** — proposes/reinforces observed preferences,
  flags contradictions, applies daily decay
- **PreferenceHealthCheck** — flags high-confidence prefs whose recent
  outcomes are net-negative
- **OutcomeGrader** — turns `PendingOutcome` rows into `LearnedOutcome`
  rows using `OutcomeEvidenceProvider` (HK + SwiftData reads)
- **Conversation purge** — soft-deletes unstarred chats older than 30 days

## Tool reference

10 tools (8 production + 2 reserved). All live in
`Tempo/Tempo/Services/Coach/CoachTools.swift`. The dispatch adapter
(`CoachToolDispatcherAdapter`) translates Anthropic tool_use blocks
into these calls.

| Tool | Mutates | PendingOutcome | Undo |
|---|---|---|---|
| `moveMeal` | `PlannedMeal.scheduledTime` + status | yes (sameDay) | yes (restores time + status) |
| `swapDayType` | `WeeklyMealPlan.dayTypeAssignments` + meal macros | yes (next48h) | no (macro snapshot too expensive) |
| `insertActivity` | composite: swapDayType + moveMeal | yes (nextDay) | inherited from sub-tools |
| `skipMeal` | `PlannedMeal.status = .skipped` | yes (sameDay) | yes (restores .planned) |
| `swapToQuickerMeal` | none — returns suggestions only | no | n/a |
| `shiftBedtime` | conversation-scoped ack only | yes (nextDay) | no |
| `askUser` | none — emits PendingQuestion | no | n/a |
| `recordPreference` | inserts `LearnedPreference` | no | (memory UI delete) |
| `updatePreference` | mutates `LearnedPreference` (supersede/clarify/deactivate/markOneOff) | no | (memory UI revert) |
| `suggestExpiryAwareMeal` (Pre-1 plumb) | none — pantry FIFO rerank | no | n/a |

Tool input schemas live in `CoachToolCatalog.defaultCatalog`
(`Tempo/Tempo/Services/Coach/CoachAdapters.swift`).

## System prompt structure

Built fresh per turn by `CoachContextAssembler.assemble(...)`. Render
output is tag-delimited (`<identity>...</identity>`) so the agent can
reason about sections. Target budget 3700 tokens; prune order on
overflow: oldest conversation summaries → forward window → backward
window → preferences tail (floor at 5).

Sections (in render order):

1. `<identity>` — name, age, sport, primary goal, current weight, height
2. `<goal-progress>` — current vs target weight (target nil until schema gains the field)
3. `<preferences-relevant-to-this-message>` — top-30 from `PreferenceRetriever`,
   filtered by today's scope, with `pref_<short>` ID prefixes for citation
4. `<outcomes>` — graded `LearnedOutcome` rows from last 14 days
5. `<today-live>` — date, recovery, HRV, RHR, sleep, steps, planned meals,
   workout, calendar events
6. `<backward-7-days>` — compact daily strips
7. `<forward-7-days>` — planned meals + workouts
8. `<recent-conversations>` — last 5 summaries

## Model decision tree

`CoachService.pickModel`:

```
useSonnet =
    turnIndex >= 3
 OR toolCallsSoFarThisTurn >= 3
 OR escalationKeywords ∩ messageWords ≠ ∅
 OR contradictionFlagPresent
```

Haiku default for the hot path. Escalation keywords:
`plan, week, days, whole, everything, why, because, explain, reorganize`.

Cost expectation per conversation (5 turns avg, mostly Haiku): ~$0.045.
Backend sub-cap default $15/mo per user
(`AIConfig.coachMonthlyBudgetCents`, env-overridable).

## Memory layer

### `LearnedPreference` schema

Per `.plans/coach-v2.1/02-data-model.md` model 1. Fields:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `text` | String | third-person plain English |
| `subject` | String | dot.path.taxonomy |
| `source` | enum | `.explicit`, `.observed`, `.inferred`, `.userVerified` |
| `polarity` | enum | `.positive`, `.negative`, `.avoidAtAllCosts` |
| `scope` | enum | `.always`, `.weekday`, `.weekend`, `.dayTypeHard`, `.dayTypeRest`, `.eventTravel`, `.eventMatch`, `.seasonalSummer` |
| `confidence` | Double | source-default on creation, +0.05 per reinforce capped at 1.0 |
| `decayRate` | Double | subject-prefix-default (allergies/goals 1.0 = never; sleep 0.96; schedule 0.95; default 0.99) |
| `evidenceCount` | Int | reinforcements |
| `lastSeenAt` | Date | drives decay calc |
| `createdAt` | Date | audit |
| `needsReview` | Bool | set by `PreferenceHealthCheck` when behavior contradicts |
| `isActive` | Bool | soft-delete flag |
| `evidenceConvId`, `evidenceTurnIndex` | UUID?, Int? | provenance |
| `supersededBy` | UUID? | replacement chain |

### Decay defaults by subject prefix

| Prefix | Rate |
|---|---|
| `red_lines.*` / `goals.*` | 1.0 (never decay) |
| `digestion.*` | 0.99 |
| `meal_timing.*` | 0.98 |
| `meal_prefs.*` / `dislikes.food.*` | 0.97 / 0.98 |
| `training.*` | 0.97 |
| `sleep.*` | 0.96 |
| `schedule.*` | 0.95 |
| `tone.*` | 0.99 |
| (default) | 0.99 |

### `LearnedOutcome` schema

Per data-model doc model 2. One row per graded suggestion.

| Field | Notes |
|---|---|
| `decisionPrefID` | optional — drives confidence drag in retriever |
| `decisionConvID`, `decisionTurnIndex` | traceability |
| `actionToolName` | which tool fired |
| `outcome` | `.goodSleep`, `.badSleep`, `.goodWorkout`, `.badWorkout`, `.followedThrough`, `.abandoned`, `.unclear` |
| `evidence` | compact data snippet from grader |
| `userOverride` | Bool — user explicitly flagged regret; forces `isNegative=true` |

## Retriever ranking

`PreferenceRetriever.retrieve(...)` returns top-N rows ranked by:

```
score = confidence × recencyWeight × (1 + subjectRelevance) + outcomeAdjust

recencyWeight = 2^(-elapsedDays/14)  (floor 0.1)
subjectRelevance = |subjectTokens ∩ messageTokens| / |subjectTokens|
outcomeAdjust  = capped sum (+0.05 per positive, -0.10 per negative, clamp ±0.30)
```

`avoidAtAllCosts` preferences ALWAYS surface (safety rails), bypassing
scope filtering. Scope filter is the set
{`.always`, weekday/weekend, dayType-specific, season-specific} for
today's calendar position + dayType.

## Extraction prompt

Verbatim shape at `PreferenceExtractor.extractionPrompt(for:)`. Output
schema:

```json
[
  {
    "text": "user never eats before 11am",
    "subject": "meal_timing.breakfast.skipped",
    "confidence": 0.90,
    "source": "explicit",
    "polarity": "positive",
    "scope": "always",
    "turnIndex": 2,
    "evidence": "I never eat before 11"
  }
]
```

Confidence floors (enforced post-AI): `.explicit`/`.userVerified` ≥ 0.6,
`.inferred`/`.observed` ≥ 0.4. Cap 5 candidates per conversation.

## Observer logic

`BehaviorObserver.observe(...)` runs once per day. Sub-scans:

1. **Meal skip patterns** — count per-mealNumber skips in the last 7
   days. ≥4 of 7 → propose/reinforce `meal_timing.{slot}.skipped`. When
   <4 AND an existing high-confidence pref exists, sets `needsReview`.
2. **Timing variance** — for meals with `actualEatenAt`, compute mean
   signed offset from `scheduledTime`. If |mean| ≥ 30min, propose/refresh
   `meal_timing.{slot}.actual`.
3. **Daily decay** — applies `applyDailyDecay()` to every active row.
   Confidence < 0.2 → soft-delete.

## Health check

`PreferenceHealthCheck.scan(...)` flags high-confidence preferences (≥
0.70) whose recent outcomes are net-negative. Skip rules: userVerified
rows, `.avoidAtAllCosts` polarity, below-floor confidence. Threshold:
≥2 negatives in 14 days AND negatives > positives. Clears the flag when
behavior recovers.

`pendingReviewPreferences(in:)` is the queue the agent reads on
conversation open to surface contradictions via `askUser`.

## Cost ceilings

| Layer | Cap | Where enforced |
|---|---|---|
| max_tokens / call | 800 (Haiku) / 1024 (Sonnet) | request body |
| turns / conversation | 8 | CoachService loop |
| tool calls / conversation | 20 | CoachService loop |
| coach monthly budget | $15 (default) | backend `AIBudgetTracker` |
| global Anthropic monthly | $50 | backend `AIBudgetTracker` |
| extraction calls | 1 / conversation end | `PreferenceExtractor` |
| summarization calls | 1 / 6-message threshold | `CoachService` |

## Analytics events

All routed through `AnalyticsService.shared.track` via the
`CoachAnalytics` helper enum.

| Event | When | Properties |
|---|---|---|
| `coach.conversation_started` | new conversation opened | id, source (tab\|inlinePill), fromTab? |
| `coach.message_sent` | per turn | id, role, model_used, has_tool_calls, turn_count |
| `coach.tool_called` | per tool dispatch | name, success, duration_ms? |
| `coach.tool_error` | dispatch throw | name, error_type |
| `coach.undo_used` | undo button tap | name |
| `coach.cap_reached` | hard cap hit | cap_type (turns\|tool_calls\|budget) |
| `coach.budget_subcap_exhausted` | 503 from backend | (none) |
| `coach.preference_extracted` | post-chat extractor row inserted | source, subject, polarity |
| `coach.preference_corrected_by_user` | memory UI edit/delete/verify | pref_id, action |
| `coach.outcome_graded` | grader writes row | action_tool, outcome, days_from_decision |
| `coach.self_grade_dismissed` | weekly card X tap | week_iso |
| `coach.interview_completed` | interview save | skipped, questions_answered |
| `coach.inline_pill_tapped` | tab pill tap | source |

## What's NOT shipped in v2.1 (explicit deferrals)

Per `.plans/coach-v2.1/01-vision-and-success.md` "Out of scope":

- Proactive Coach (unsolicited push). v3.
- EventKit write-back (read OK; write defers). v3.
- Multi-device memory sync. v2.x.
- Preference export/import. v2.x.
- Full day regeneration on `swapDayType` (macros still scale). v2.x.
- Conversation search/filter. v2.x.
- Memory audit trail. v2.x.
- Photo input to Coach. v2.x — folds in once Pantry Scan ships.
- Manual preference input form (CUT in v2.1; the interview seeds priors).

## Tab integration — open product decision

`CoachTabView` is built and reachable as a value type, but is NOT yet
mounted in `ContentView.mainTabView`. The 5-slot tab structure is
fixed; adding Coach requires a product call:

**Option A — Modal sheet from Dashboard.**
Add a small "Ask Coach" entry on Dashboard that presents `CoachTabView`
as a full-screen sheet. Doesn't disturb the existing tab bar. Easiest
to roll back.

**Option B — Replace Lockdown with Coach.**
If Coach is more central than Lockdown for v2.1's user, swap the tab.
Higher visibility, harder to undo.

**Option C — Six-tab layout.**
iOS hides extras under "More" in a 6+ tab bar — degrades discoverability
of every tab. Don't recommend.

Recommend A for the v2.1 launch (lowest blast radius, highest
reversibility) until usage tells us Coach deserves a permanent slot.

## Regression test plan

See `docs/COACH_REGRESSION_SUITE.md` for the 8-script manual QA suite
that gates v2.1 ship.
