# Coach Agent

The Coach is Tempo's multi-turn, tool-using AI assistant for the
nutrition + recovery surface. Unlike the existing one-shot coaching
cards (daily summary, meal feedback, recovery tip), the Coach maintains
a conversation, remembers Nicola's preferences across sessions, and
actually mutates his schedule via on-device tools.

This doc is the source of truth for the agent's contract: tools,
prompts, memory schema, escalation rules, undo behavior. Code references
point at the files that implement each section.

---

## Architecture overview

```
┌──────────────────────────────────────────────────────────┐
│ CoachChatView (P7)                                       │
│   – bubbles, input bar, askUser chips, undo banner       │
└─────────────┬────────────────────────────────────────────┘
              │  Bindable
┌─────────────▼────────────────────────────────────────────┐
│ CoachViewModel (P7)                                      │
│   – inputText / isThinking / pendingQuestion             │
│   – displayTurns derived from CoachConversation          │
└─────────────┬────────────────────────────────────────────┘
              │
┌─────────────▼────────────────────────────────────────────┐
│ CoachService (P6)  — agent loop                          │
│   1. CoachContextAssembler.snapshot() → 3K-token memory  │
│   2. POST /v1/nutrition/ai/coach/chat with tools         │
│   3. dispatch tool_use blocks via CoachToolDispatcher    │
│   4. loop until stop_reason == end_turn                  │
└────────┬────────────────────────────────┬────────────────┘
         │                                │
         ▼                                ▼
  ┌──────────────┐              ┌─────────────────────┐
  │ CoachTools   │              │ NutritionClaudeProxy│
  │ (mutators)   │              │ (backend, P1)       │
  └──────────────┘              └─────────────────────┘
                                          │
                                  ┌───────▼────────┐
                                  │ Anthropic API  │
                                  └────────────────┘
```

After a conversation ends, **`PreferenceExtractor` (P4)** runs as a
single Haiku side-call that mines the transcript for durable
`LearnedPreference` entries.

Each night, **`BehaviorObserver` (P4)** scans planned-vs-actual meal
data to mint observed preferences and reinforce / decay existing ones.

---

## Backend contract (P1)

**Endpoint:** `POST /v1/nutrition/ai/coach/chat`

**Request** (`NutritionProxyChatRequest`):

| field            | type                              | notes |
|------------------|-----------------------------------|-------|
| `model`          | string                            | `"haiku"` or `"sonnet"` |
| `system`         | string                            | System prompt + memory snapshot |
| `messages`       | `[ChatMessage]`                   | Full transcript including tool_result blocks |
| `tools`          | `[ChatTool]` (optional)           | Tool schemas; forwarded verbatim to Claude |
| `tool_choice`    | `auto` / `any` / `{tool:name}`    | Defaults to `auto` |
| `max_tokens`     | int                               | Per-turn cap (default 1500) |
| `temperature`    | float                             | 0.4 for coach |
| `caller`         | string                            | `"coach"` — gates per-feature sub-budget |

**Response** (`NutritionProxyChatResponse`):

| field         | type        | notes |
|---------------|-------------|-------|
| `stop_reason` | string      | `end_turn` / `tool_use` / `max_tokens` |
| `blocks`      | `[Block]`   | Decoded text + tool_use blocks |
| `usage`       | `Usage`     | input_tokens / output_tokens for accounting |

**Budget gating:** `AIBudgetTracker` enforces both the global monthly
cap ($50 default) and a per-caller sub-budget. Coach defaults to
**$15/mo** via `COACH_MONTHLY_BUDGET_CENTS` env var. Hitting either cap
returns `503` with `NutritionProxyError.budgetExhausted`.

---

## Tools

All tools live in `CoachTools` / `CoachToolDispatcher`. Schemas exposed
to Claude come from `CoachToolSchema.allTools`.

| tool                | mutates state | what it does |
|---------------------|---------------|--------------|
| `record_preference` | yes           | Insert a `LearnedPreference` with `source=.explicit` |
| `update_preference` | yes           | supersede / deactivate / mark-one-off / confirm an existing pref |
| `ask_user`          | no            | Returns a `PendingQuestion` for the UI to render |
| `shift_bedtime`     | no (v1)       | Conversation-scoped override; v2 will persist |
| `move_meal`         | yes           | Reschedule a planned meal; downstream meals shift via `MealShiftPlanner` |
| `skip_meal`         | yes           | Mark a planned meal `.skipped` |

Tool dispatch is synchronous — every handler is non-async — so the loop
stays simple and the `inout undoStack` doesn't violate Swift 6 actor
isolation.

**Undo:** mutating tools push a `CoachService.Undo` entry onto the
single-step undo stack. The chat UI surfaces "Undo: <label>" while an
entry exists; pressing it pops + applies.

---

## Model selection (Haiku vs Sonnet)

`CoachService.selectModel(...)` defaults to Haiku 4.5 and escalates to
Sonnet 4.6 when:

- The message starts with `why `, `what should`, `how do i`, `how should i`,
  `explain `, or `compare `.
- The message length exceeds 240 characters (verbose framing usually
  signals an open-ended question).
- The conversation has already burned more than 2 tool turns on Haiku
  — Haiku is clearly struggling.

Haiku ≈ $0.001/turn; Sonnet ≈ $0.015/turn. The $15/mo sub-budget allows
~15,000 Haiku turns or ~1,000 Sonnet turns per month — well above any
realistic personal use.

---

## Memory: LearnedPreference

Stored in SwiftData (`LearnedPreference.swift`), additive to
`TempoSchemaV1` so no migration is required.

**Key fields:**

| field                  | role |
|------------------------|------|
| `text`                 | Short third-person statement (e.g. "Bedtime 23:00") |
| `subject`              | Canonical dot-string (`meal_timing.dinner`, `sleep.bedtime`, …) — see `LearnedPreferenceSubject` |
| `confidence`           | 0–1; decayed nightly, reinforced on evidence |
| `source`               | `.explicit` / `.observed` / `.inferred` / `.userVerified` |
| `userVerified`         | True once Nicola pins the pref in `CoachMemoryView` |
| `evidenceCount`        | Bumped each time `markReinforced` fires |
| `firstSeenAt` / `lastSeenAt` | Timestamps for recency ranking |
| `contradictedByID` / `supersededAt` | Supersession chain |
| `isActive`             | False = removed from active memory but kept for history |

**Decay rule** (`applyDailyDecay`): if a pref wasn't reinforced today,
multiply confidence by 0.99 (explicit/userVerified) or 0.97
(observed/inferred). Drop below 0.2 → deactivate.

---

## Preference extraction (P4)

`PreferenceExtractor.extract(transcript:conversationID:context:)` runs
after every `CoachService.end(...)`. Single Haiku call with this
contract:

```json
{
  "preferences": [
    {
      "text": "...",
      "subject": "<canonical subject>",
      "confidence": 0.0,
      "source": "explicit" | "observed" | "inferred",
      "supersedes": ["<8-char-id>", ...]
    }
  ]
}
```

- Caps at 8 inserts per call (`maxPreferencesPerCall`).
- Dedupes by (subject, case-insensitive text); duplicates trigger
  `markReinforced()` instead of insertion.
- `supersedes` short-IDs (first 8 chars of UUID) deactivate the matched
  prefs and link them via `contradictedByID`.
- Unknown `source` values are skipped with a log warning.

---

## Behavior observation (P4)

`BehaviorObserver.run(context:)` runs once per day from
`DailyResetCoordinator`. Pure-logic detection (`detectPatterns`) is
unit-tested separately from the persistence path (`apply`).

**Patterns:**

1. **Skipped meal** — meal type not logged on ≥3 of the last 7 days
   → mints `meal_timing.<type>` observed pref.
2. **Time drift** — ≥4 of 7 days the actual eat time is ≥30min off
   from planned, all in the same direction → mints "Eats <meal> ~Xmin
   <later|earlier> than planned".
3. **On-time reinforcement** — ≥5 of 7 days within ±15min of planned
   → reinforces a matching existing pref. Does NOT insert if no pref
   exists (we don't want to mint "on-time dinner" prefs unprompted).

User-stated prefs (`source=.explicit` / `userVerified`) are never
overwritten by observations — observations can only reinforce them when
they align.

---

## Retrieval ranking (P4)

`PreferenceRetriever.retrieve(for:from:limit:)` ranks active prefs by:

1. Subject-keyword overlap with the user message (×1.0 per hit).
2. `userVerified` pin bonus (+0.5).
3. Confidence × 0.2.
4. Recency: `exp(-daysSince/90) × 0.1`.

Tie-broken by `id.uuidString` so results are deterministic. Default
limit is 12 prefs per turn — enough context, cheap on tokens.

---

## Context assembly (P5)

`CoachContextAssembler.snapshot(userMessage:tokenBudget:)` builds the
per-turn memory snapshot (default ceiling: 3000 tokens):

1. **Identity** — name / age / kg / cm / timezone / level.
2. **Preferences** — top-N from PreferenceRetriever.
3. **Today** — planned meals + actuals.
4. **Last 7 days** — daily meal counts + calorie sums.
5. **Next 7 days** — upcoming planned meals.
6. **Conversation summaries** — (P6 hook; reserved for prior thread titles.)

Bands render greedily; the last partial band is truncated rather than
split mid-band, with a "(…truncated to fit context)" marker.

---

## System prompt

`CoachService.systemPrompt(snapshot:)` produces the system message:

```
You are the Tempo Coach — Nicola's life-operating-system assistant.
Voice: drill-sergeant honest, never sycophantic. ...

Use tools to actually change Nicola's schedule / preferences /
meal plan. ...

If the user request is genuinely ambiguous, call `askUser` with a
single sharp question + 2-3 choices. ...

Memory snapshot (identity + preferences + recent state):
<assembled snapshot>
```

Concrete production text lives in `CoachService.swift` —
`systemPrompt(snapshot:)` is `static` so tests can assert on it.

---

## Lifecycle hooks

| trigger                                    | side effect |
|--------------------------------------------|-------------|
| `CoachViewModel.startConversation()`       | Inserts a `CoachConversation` with `startedAt = now` |
| `CoachViewModel.send(_:)`                  | Appends user turn, runs agent loop, appends assistant turn |
| `CoachViewModel.endConversation()`         | Sets `endedAt`, derives `titleSummary`, fires `PreferenceExtractor` |
| `DailyResetCoordinator.runIfNeeded(...)`   | Runs `BehaviorObserver`, applies decay, **purges ended conversations >30 days** |

The 30-day purge keeps the SwiftData store from growing unbounded.
Extracted preferences survive — only the raw transcripts are deleted.

---

## Memory UI (P8)

`CoachMemoryView` lives at `Settings → Coach → Coach's Memory`. It
lists active preferences grouped by subject; swipe to forget (sets
`isActive = false`); tap to edit (text / confidence / pin toggle); `+`
to add a user-stated preference manually.

---

## Where to extend

| want to add… | edit |
|--------------|------|
| A new tool | `CoachTools.swift` + `CoachToolDispatcher.dispatch` + `CoachToolSchema.allTools` + a row in this doc's tools table |
| A new pref subject | `LearnedPreferenceSubject` + the extractor's allowed-subjects block in its system prompt |
| A new observation pattern | `BehaviorObserver.detectPatterns` (pure) + `apply` (mutation) + a test in `BehaviorObserverTests` |
| A new context band | `CoachContextAssembler` — add a method, call it from `snapshot(...)` |
| Sub-budget tuning | `AIBudgetTracker.subBudgetCapCents(for:)` or `COACH_MONTHLY_BUDGET_CENTS` env var |
