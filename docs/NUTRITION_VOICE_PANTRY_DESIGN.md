# Voice-to-Pantry — Design Doc

> **Status: PROPOSAL — needs Nicola's approval before any code.**
> Author: Claude (Opus 4.8), 2026-06-02. Companion to `NUTRITION_PERSONALIZATION_DESIGN.md`.
> Constraint: weekly plan stays the only Sonnet call. This feature uses **Haiku via the existing server-side nutrition proxy** (no Anthropic key in the binary), gated to at most 2 calls per voice session — same cost profile as `VoiceMealLogView`, which already ships.
>
> **How to read this:** each section is independently approvable — **Decision needed / Recommendation / Effort tier (FOUNDATIONAL / MEDIUM / HEAVY) / Keep-vs-build**. Annotate inline (✅ approve / ✏️ change / ❌ skip) and hand back.

---

## 0. The ask (Nicola, 2026-06-02)

> "A function where I talk and things get added to the pantry with an AI. I say the bottle / the total amount, and I say the amount I actually have now. E.g. a full pack of spaghetti (500 g) plus a half-full one → total 750 g of pasta."

In plain terms: **speak a free-form inventory sentence → it becomes correctly-summed pantry rows**, without typing.

---

## 1. What's ALREADY built — KEEP, do not rebuild [the headline finding]

The codebase already contains every structural piece. This is **not** a from-scratch feature; it's "do for the pantry what voice meal-logging already does for meals." Verified in code 2026-06-02:

- ✅ **`VoiceTranscriber`** (`Services/Speech/VoiceTranscriber.swift`) — on-device `SFSpeechRecognizer`, `@Observable`, `start()`/`stop()`, live `transcribedText`, 3 s silence auto-stop, permission handling. **FREE, no API cost, no network for the transcription itself.**
- ✅ **`VoiceMealLogView` + `VoiceMealLogService`** — the exact talk→AI→confirm→save pattern, already in production for meals. Phases (idle→recording→thinking→clarifying→confirming→failed), a 2-step Haiku flow (`extract()` → up to 4 tappable clarifying questions → `resolve()` → structured items + `confidence:"low"` fallback), retry/backoff, JSON parsing, and a per-call `feature` tag for cost attribution. **This is the blueprint to clone.**
- ✅ **Server-side Haiku proxy** — `NutritionProxyTextRequest(model:"haiku", maxTokens:800, caller:)` via `apiClient.nutritionProxyText()`. No key in the app; cost is bounded server-side. The CLAUDE.md AI-cost guardrail is already satisfied by this path.
- ✅ **`PantryItem`** model — `canonicalName`, `displayName`, `quantity: Double`, `unit`, `storageLocation`, `isArchived`, and crucially **`increment(by:)` / `decrement(by:)`** mutation helpers. `PantryPriceEntry` price-history hook exists from the last session.
- ✅ **`FoodCanonicalizer`** — maps spoken/typed variants ("spaghetti", "pasta") to a canonical food name. Already unit-tested. This is what lets "the spaghetti" merge into an existing pasta row.
- ✅ **`PantryViewModel.addPantryItem(...)`** + the manual Add-to-Pantry sheet — the save path that already persists a row (name, quantity, unit, storage, optional price).

**The work is wiring these together + one genuinely new piece: quantity aggregation.** Not new infrastructure.

---

## 2. The current mic button is a stub — this is the real gap [FOUNDATIONAL]

**Finding:** the Add-to-Pantry sheet ALREADY has a mic button (`PantryView.swift:435`). But it does the dumbest possible thing:

```swift
.onChange(of: transcriber.transcribedText) { _, newText in
    name = newText        // dumps the WHOLE raw sentence into the Name field
}
```

So today, saying "a full pack of spaghetti 500 grams and a half pack" makes the **Name field literally equal that entire sentence** — no item split, no quantity parse, no unit, no merge. It's voice-to-textfield, not voice-to-pantry.

**Decision needed:** replace the raw-dump mic with a structured voice→pantry flow (the `VoiceMealLogView` pattern), keeping the manual sheet as the fallback/edit surface?

**Recommendation:** YES. The stub proves the entry point and permissions already work; we're upgrading what happens to the transcript, not adding a new affordance.

**Effort:** FOUNDATIONAL (the decision; the build is §4–§6 below).

---

## 3. Architecture — clone the meal-log flow, point it at the pantry [MEDIUM]

A new `VoicePantryView` + `VoicePantryService`, near-mirrors of the meal-log pair. The ONE thing the meal flow doesn't do that we need is **multi-source quantity math** (full + half pack → sum), so the resolve step returns aggregated quantities, not per-mention rows.

**Flow:**
1. **Record** (`VoiceTranscriber`, free, on-device) → transcript: *"a full pack of spaghetti, 500 grams, and another half pack, plus a litre bottle of olive oil that's about a third left."*
2. **`extract()`** (Haiku call #1) → up to 4 tappable clarifying questions ONLY when genuinely ambiguous (e.g. "The olive oil bottle — what's its full size?" → [500 ml] [750 ml] [1 L] [other]). If nothing's ambiguous → skip to resolve.
3. **`resolve(transcript, answers)`** (Haiku call #2) → structured JSON array of **aggregated** pantry items:
   ```json
   {"items":[
     {"name":"spaghetti","canonical_hint":"pasta","quantity":750,"unit":"g",
      "storage":"pantry","components":["1 full pack 500g","1 half pack 250g"],"confidence":"high"},
     {"name":"olive oil","canonical_hint":"olive oil","quantity":333,"unit":"ml",
      "storage":"pantry","components":["~1/3 of a 1L bottle"],"confidence":"low"}
   ]}
   ```
   The `components` array is shown in the confirm card so the user can SEE the math the AI did ("500 g + 250 g = 750 g") before saving — trust + correctability.
4. **Confirm card** — one row per item, editable quantity/unit/storage, low-confidence badge + "edit manually" escape (mirrors meal-log's "Search instead").
5. **Save** — for each confirmed item: `FoodCanonicalizer` → canonical name → **if a non-archived PantryItem with that canonical name + unit exists, MERGE via `increment(by:)`; else create a new row** via `addPantryItem`.

**Effort:** MEDIUM (one view + one service, both cloned; the save/merge logic is the new part).

**Reuse-vs-build:**
- REUSE: `VoiceTranscriber`, the proxy `send()`/retry/`parseJSON` helpers, the phase-machine UI scaffold, `PantryItem.increment`, `FoodCanonicalizer`, `addPantryItem`.
- BUILD: `VoicePantryService` prompts (extract + resolve, pantry-flavored), `VoiceResolvedPantryItem` wire model, the merge-or-create save logic, the quantity-aggregation handling.

---

## 4. Quantity aggregation — the one genuinely hard part + its landmines [MEDIUM]

This is where the feature earns its keep, and where it can silently produce wrong numbers. Decisions:

- **Where does the math happen?** → **In the AI resolve step, but VERIFIED in the confirm card.** Haiku is good at "500 g + a half of a 500 g pack = 750 g"; it is NOT reliable at it silently. So the AI returns both the total AND the `components` breakdown, and the UI shows the breakdown so the user catches a bad sum before it's saved. Never auto-save a voice quantity the user didn't see.
- **LANDMINE — unit mismatch on merge.** "750 g of pasta" must NOT merge into an existing "2 packs of pasta" row (count vs. mass). **Merge ONLY when canonical name AND unit match.** Different unit → create a separate row and surface it ("you already have pasta tracked in 'packs' — adding this as grams separately"). This is the pantry analogue of the §4 double-count rule: never combine quantities that aren't the same dimension.
- **LANDMINE — fractional/approximate amounts.** "about a third of a 1 L bottle" → 333 ml, but mark `confidence:"low"` and pre-flag for review. Approximations are fine for "what can I cook" but must be visibly approximate, never presented as precise.
- **LANDMINE — merge vs. replace.** Voice "I have 750 g of pasta" is almost always **state-now ("I currently hold 750 g")**, NOT **delta ("add 750 g to what's there")**. The meal-log flow is additive; pantry voice is more often a stock-take. **Decision needed:** default voice pantry entry to SET (replace the canonical row's quantity) or ADD (increment)? Recommendation: **SET when the user phrases a current total ("I have…"), ADD when they phrase a purchase ("I bought…")** — and let the confirm card toggle per item, defaulting to SET (the stock-take reading matches the spoken example).
- **Units vocabulary.** The resolve prompt must constrain `unit` to Tempo's `FoodUnit` enum (g, ml, pieces, packs, …) so it round-trips into `PantryItem.unit` cleanly. Unknown unit → low confidence → manual edit.

**Effort:** MEDIUM. Needs its own unit tests: full+half sum, unit-mismatch-no-merge, approximate→low-confidence, SET-vs-ADD phrasing, canonical merge into existing stock.

---

## 5. Cost + safety posture [FOUNDATIONAL — already satisfied]

- **Transcription:** on-device `SFSpeechRecognizer` — zero API cost, works offline.
- **AI:** ≤2 Haiku calls per voice session (extract + resolve), `maxTokens: 800`, through the server proxy with a `caller:"voice_pantry_extract"` / `"voice_pantry_resolve"` tag. Same envelope as the shipped meal-log flow → no new cost guardrail needed, but the `caller` tags let the backend meter it.
- **No per-utterance streaming to Claude.** The user speaks a full sentence, stops (3 s silence), THEN one extract call. This is the safe pattern; the early-idea risk ("stream every sentence to an LLM") is explicitly avoided.

---

## 6. Proposed sequencing (after approval)

**Tier 1 — MEDIUM (the core):** §3 `VoicePantryView` + `VoicePantryService` cloned from the meal-log pair; §4 aggregation + merge-or-create save with the unit-match guard; replace the §2 stub mic. Unit tests for the aggregation landmines. Ships the spoken example end-to-end.

**Tier 2 — polish:** per-item SET/ADD toggle in the confirm card; price capture in the same flow (reuse `PantryPriceEntry`); "you already have X" merge notices; tie into the grocery generator (voice "I'm out of rice" → grocery list).

**Tier 3 — later:** voice-driven pantry EDIT/REMOVE ("I used up the chicken"), and location-aware stock (the deferred §9 school/microwave case from the personalization doc).

Each tier tested + verified before the next. Weekly Sonnet call stays the only heavy paid path.

---

## Open questions for Nicola

- §4: default voice entry to **SET** (stock-take: "I have 750 g") or **ADD** (purchase: "I bought 750 g")? Recommendation: phrase-driven default, per-item toggle in confirm.
- §4: when a spoken item's unit differs from the existing tracked unit (grams vs. packs), keep them as **two separate rows** (recommended) or force a conversion?
- §3: brand-new `VoicePantryView` screen reached from the Pantry tab's "Scan"-style button, or keep it inside the existing Add-to-Pantry sheet (upgrade the stub mic in place)? Recommendation: a dedicated full-screen flow like `VoiceMealLogView`, with the sheet's mic as a secondary entry.
- Scope check: is the spoken-example (multi-pack pasta + fractional bottle) the Tier 1 acceptance test, or do you want a broader first cut?
```
**Verdict:** STRONG — build it; ~80% is reuse of shipped code, the new 20% (aggregation + merge) is well-bounded.
**Confidence:** high
**If I'm wrong:** if `VoiceResolvedItem`'s schema or the proxy prompt is too meal-specific to generalize, the pantry service needs fully independent prompts (still same architecture, slightly more code).
**What I'm NOT saying:** not zero-effort — the quantity-aggregation + merge logic is real new code that needs its own tests; the reuse is structural, not a copy-paste of behavior.
```
