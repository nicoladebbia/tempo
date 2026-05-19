# Tempo — UX Copy Bible

> **Module**: UX Copy (cross-cutting)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what copy actually ships in code, not the original aspirational copy bank. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

> **One-line reality check:** This was a massive aspirational copy bank. Most banks are NOT verifiable in code as discrete strings — copy is written inline at each call site. Spot-verified: the Dashboard greeting fallback bank (§3.2) ships **verbatim**; Accountability escalation copy ships **data-driven** from `AccountabilityCopy.json`. The PR Celebration bank (§4.5) is **absent** (generic count string only). Specific militaristic loading strings ("Assembling briefing", "Pulling your numbers") are **not in code**.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/ViewModels/DashboardViewModel.swift` — `greeting` (fallback time-based bank)
- `Tempo/Tempo/Resources/AccountabilityCopy.json` — escalation copy data
- `Tempo/Tempo/Services/Notifications/AccountabilityCopyPool.swift` — `pick(...)` loader
- `Tempo/Tempo/Services/Notifications/AccountabilityEscalationEngine.swift`
- `Tempo/Tempo/Views/Training/WorkoutSummaryView.swift` — PR summary string

> **Verification method:** strings were spot-checked by grepping the named string fragments against `Tempo/Tempo`. "NOT IMPLEMENTED" below means the documented strings/keys were **not found in code**; copy may still be authored inline differently. Where code copy was found, it is described. Per-bank exhaustive string-by-string parity was not attempted and is explicitly not claimed.

---

## Table of Contents

1. [Voice & Tone Guide](#1-voice--tone-guide)
2. [Onboarding Copy](#2-onboarding-copy)
3. [Dashboard Copy](#3-dashboard-copy)
4. [Training Copy (RepForge)](#4-training-copy-repforge)
5. [Accountability Copy (Lockdown)](#5-accountability-copy-lockdown)
6. [Recovery Copy (RecoverIQ)](#6-recovery-copy-recoveriq)
7. [Arena Copy (ClutchTime)](#7-arena-copy-clutchtime)
8. [Settings Copy](#8-settings-copy)
9. [Error Messages](#9-error-messages)
10. [Empty States](#10-empty-states)
11. [Confirmation Dialogs](#11-confirmation-dialogs)
12. [Accessibility Labels](#12-accessibility-labels)
13. [App Store Copy](#13-app-store-copy)
14. [Weekly Report Copy](#14-weekly-report-copy)
15. [Expanded View Quips](#15-expanded-view-quips)
16. [Patterns & Correlation View](#16-patterns--correlation-view)
17. [Nutrition · Intake Wizard](#17-nutrition--intake-wizard)

---

## 1. Voice & Tone Guide

> **Status: NOT IMPLEMENTED as a code artifact.** Original §1 (writing personality, word list, sentence rules, number/user/time reference, emoji rules) is an editorial style guide. It informs copy but is not encoded or enforced anywhere. Retain as authoring guidance. The number-formatting and `{firstName}`/`{name}` interpolation conventions are partially honored ad hoc (e.g. the greeting bank appends a name suffix), not via a central formatter.

---

## 2. Onboarding Copy

> **Status: NOT IMPLEMENTED as a verifiable bank.** The original §2.1–§2.13 splash/step copy keys were not found as discrete strings in code; onboarding view copy is authored inline per view and does not match the documented `string_key` table. Treat original §2 as the intended copy, not as-built strings.

---

## 3. Dashboard Copy

### 3.2 Dashboard Greeting Messages

**IMPLEMENTED — verbatim.** `DashboardViewModel.greeting` has a priority-based path, with a **time-based fallback bank** that matches original §3.2 exactly (name suffix interpolated):

| Hour range | String |
|------------|--------|
| 0–4 | "You should be asleep{name}." |
| 4–8 | "Early bird gets the gains{name}." |
| 8–12 | "Rise and grind{name}." |
| 12–14 | "No half reps this afternoon{name}." |
| 14–17 | "Keep the pressure on{name}." |
| 17–21 | "Finish what you started{name}." |
| 21–24 | "Earn your sleep{name}." |
| default | "Rise and grind{name}." |

> **Divergence from original spec:** This is the *fallback*; a higher-priority context-aware greeting path exists above it in `greeting`. The original §3.2 framed these 7 as the primary strings — in code they are the fallback tier.

### 3.1, 3.3–3.10 (other Dashboard copy)

> **Status: NOT IMPLEMENTED as a verifiable bank.** Tab labels, daily-score section, quadrant headers/disconnected/error states, non-negotiables bar, insights banner, pull-to-refresh status, relative timestamps — these are authored inline in the Dashboard views and do not map to the documented §3 string keys. Specific militaristic loading copy ("Assembling briefing", "Pulling your numbers") was **not found in code**. See MODULE_DASHBOARD.md for the as-built Dashboard behavior.

---

## 4. Training Copy (RepForge)

### 4.5 PR Celebration Messages

> **Status: NOT IMPLEMENTED.** The original §4.5 bank (`pr_message_1..5` — "iron remembers", "proved yesterday", "Keep stacking", "stand a chance", "Build the next", etc.) is **absent from code**. `WorkoutSummaryView` renders only a generic count string: `"\(count) Personal Record(s)!"` (pluralized). None of the 5 drill-sergeant variants exist.

### 4.1–4.4, 4.6–4.10 (other Training copy)

> **Status: NOT IMPLEMENTED as a verifiable bank.** Today's workout, workout titles, active-workout, rest-timer, summary, week-plan, exercise-library, settings, and error copy were not confirmed as the documented string keys; training view copy is authored inline. Not verified string-by-string.

---

## 5. Accountability Copy (Lockdown)

**IMPLEMENTED — data-driven.** Accountability escalation copy ships as a bundled resource `Tempo/Tempo/Resources/AccountabilityCopy.json` (version 1; `tiers.gentle/firm/...` arrays with `{remaining}`/`{done}`/`{total}` interpolation tokens). It is loaded and selected by `AccountabilityCopyPool.shared.pick(...)` and consumed by `AccountabilityEscalationEngine` (recency-tracked selection across escalation tiers).

> **Divergence from original spec:** Original §5 documented this copy as static prose tables. In code it is externalized JSON with token interpolation and tiered random selection — structurally richer than the doc, but the *exact* string set is whatever is in `AccountabilityCopy.json`, not the §5 tables. Read the JSON for ground truth. Non-notification §5 view copy (main view, status banner, card status/supporting text) is inline and not verified against the documented keys.

---

## 6. Recovery Copy (RecoverIQ)

> **Status: NOT IMPLEMENTED as a verifiable bank.** Recovery copy is generated/inline (see RecoveryEngine / RecoveryViewModel and the Recovery AI insight service); the documented §6 string keys were not confirmed as discrete strings. AI-generated prescription text is dynamic, not a static bank.

---

## 7. Arena Copy (ClutchTime)

> **Status: NOT IMPLEMENTED as a verifiable bank.** The large §7 Arena bank (XP/level/achievement/challenge/leaderboard strings) was not confirmed in code as the documented keys; Arena copy is authored inline per view. Not verified string-by-string.

---

## 8. Settings Copy

> **Status: NOT IMPLEMENTED as a verifiable bank.** Settings copy is inline in the settings views; documented §8 keys not confirmed.

---

## 9. Error Messages

> **Status: NOT IMPLEMENTED as a verifiable bank.** Error strings are authored inline at call sites / in service error types; the documented §9 standardized error copy table is not centralized in code.

---

## 10. Empty States

> **Status: NOT IMPLEMENTED as a verifiable bank.** Shared `EmptyStateView` / `LoadingStateView` components exist (see DESIGN_SYSTEM), but the specific drill-sergeant empty/loading copy from original §10 (and §1 voice rules) was **not found** wired in. Component scaffold exists; the exact copy bank does not.

---

## 11. Confirmation Dialogs

> **Status: NOT IMPLEMENTED as a verifiable bank.** Confirmation/alert copy is inline per call site; documented §11 keys not confirmed.

---

## 12. Accessibility Labels

> **Status: PARTIAL — see ACCESSIBILITY.md.** `accessibilityLabel` exists in ~25 source files, but the specific label strings here do not match the exhaustive §12 table. The documented per-element label bank is not implemented as written.

---

## 13. App Store Copy

> **Status: NOT IMPLEMENTED — out of app scope.** App Store listing copy is metadata, not shipped in the binary. Not a code artifact.

---

## 14. Weekly Report Copy

> **Status: NOT IMPLEMENTED as a verifiable bank.** `WeeklyReportView` exists (see MODULE_DASHBOARD.md) but its copy is inline and was not confirmed against the documented §14 keys.

---

## 15. Expanded View Quips

> **Status: NOT IMPLEMENTED as a verifiable bank.** Quadrant-detail "quip" strings from original §15 were not confirmed in code as a discrete bank.

---

## 16. Patterns & Correlation View

> **Status: NOT IMPLEMENTED.** The Patterns/Correlation view is itself not implemented (see MODULE_DASHBOARD.md §6); its copy bank is therefore unrealized.

---

## 17. Nutrition · Intake Wizard

> **Status: NOT IMPLEMENTED as a verifiable bank.** Nutrition intake-wizard step copy is authored inline in the wizard step views; the documented §17 keys were not confirmed string-by-string.

---

## Appendix — As-Built Summary

| Bank | Status |
|------|--------|
| §3.2 Dashboard greeting (fallback) | IMPLEMENTED — verbatim, 7 strings |
| §5 Accountability escalation copy | IMPLEMENTED — data-driven (`AccountabilityCopy.json`) |
| §4.5 PR celebration bank | NOT IMPLEMENTED — generic count string only |
| §10 / §1 militaristic loading/empty copy | NOT IMPLEMENTED — strings absent |
| §1, §2, §3 (non-greeting), §4 (non-PR), §6–§17 | NOT IMPLEMENTED as verifiable banks — inline copy, keys unconfirmed |
