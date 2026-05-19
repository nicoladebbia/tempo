# Tempo — Accessibility Specification

> **Module**: Accessibility (cross-cutting)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

> **One-line reality check:** Dynamic Type is solid (handled centrally in the font tokens). VoiceOver labels exist but partially (`accessibilityLabel` in ~25 files; traits/hints/values in ~8 view files) — nowhere near the exhaustive per-screen audit the original spec describes. Reduce Motion infra exists but is **built-but-unwired**: `tempoAnimation` has zero adoption, and ~41 view files animate with raw `.animation`/`withAnimation` that ignore Reduce Motion.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Utilities/Extensions/Font+Tempo.swift` — `UIFontMetrics` scaling + caps
- `Tempo/Tempo/Utilities/Extensions/View+Accessibility.swift` — `tempoAnimation`, `tempoDisplayCapped`
- `Tempo/Tempo/Views/Shared/Modifiers/MicroInteractionModifiers.swift` — reduce-motion-aware press/fade
- `Tempo/Tempo/Assets.xcassets/Colors/*` + `Color+Tempo.swift` — color tokens
- VoiceOver: ~25 files with `accessibilityLabel` (e.g. `Views/Dashboard/DayPlanView.swift`, `Views/Recovery/WhoopConnectionView.swift`)

---

## Table of Contents

1. [Accessibility Standards](#1-accessibility-standards)
2. [VoiceOver — Complete Screen-by-Screen Audit](#2-voiceover--complete-screen-by-screen-audit)
3. [Dynamic Type](#3-dynamic-type)
4. [Color and Visual Accessibility](#4-color-and-visual-accessibility)
5. [Motor Accessibility](#5-motor-accessibility)
6. [Reduce Motion](#6-reduce-motion)
7. [Cognitive Accessibility](#7-cognitive-accessibility)
8. [Audio Accessibility](#8-audio-accessibility)
9. [Accessibility Testing Checklist](#9-accessibility-testing-checklist)
10. [Accessibility Settings in Tempo](#10-accessibility-settings-in-tempo)
11. [Localization Accessibility](#11-localization-accessibility)

---

## 1. Accessibility Standards

Partial. The codebase ships accessibility helpers in `View+Accessibility.swift` and uses standard SwiftUI accessibility modifiers in places. The original §1.4 traits reference is partially realized: `accessibilityAddTraits`/`accessibilityValue`/`accessibilityHint`/`accessibilityElement` appear in ~8 view files.

> **Status: NOT IMPLEMENTED — compliance claims are QA assertions, not code.** Original §1.1/§1.2 (WCAG 2.2 AA conformance, Switch Control, Voice Control, Braille support matrices) cannot be verified from source — these are process/QA targets with no code artifact. Color contrast is *satisfiable* via the design tokens but not asserted in code.

---

## 2. VoiceOver — Complete Screen-by-Screen Audit

Partially implemented. `accessibilityLabel` is present in ~25 source files spanning Dashboard, Recovery, and shared components; explicit traits/values/hints/grouping appear in ~8 view files. Helper extensions live in `View+Accessibility.swift`.

> **Status: NOT IMPLEMENTED at the documented granularity.** The original §2.0–§2.10 is an exhaustive per-element reading-order / rotor / label-string audit (Dashboard reading order, Active Workout rotor, Leaderboard navigation, per-chart audio-graph descriptions, etc.). Code coverage is broad-but-shallow: many screens have labels, but the specific per-element label strings, custom rotors, and reading orders enumerated in original §2 are **not verifiable in code and largely not implemented as specified**. Treat the original §2 element tables as a target backlog, not an as-built description. Unverifiable per-screen claims are explicitly NOT confirmed.

---

## 3. Dynamic Type

Implemented — and architecturally correct. All typography tokens in `Font+Tempo.swift` are produced via `UIFontMetrics(...).scaledFont(for:)` with optional `maximumPointSize` caps, so Dynamic Type scaling is centralized at the token layer. `View+Accessibility.swift` provides `tempoDisplayCapped()` which clamps display text via `dynamicTypeSize(...accessibility1)`.

> **Divergence from original spec:** Original §3.2 specified a fixed per-token point-size scaling table and §3.5 implied per-view `@ScaledMetric`. Code instead scales relative system styles through the font tokens — semantically equivalent and cleaner. The absence of `@ScaledMetric` in views is expected, not a gap. The exact §3.2 numeric table and the §3.3 per-category layout-reflow rules are NOT IMPLEMENTED as written (SwiftUI reflows automatically); §3.4 truncation strategy is not codified.

---

## 4. Color and Visual Accessibility

Partial. The color system ships as asset-catalog colorsets with light/dark variants (see DESIGN_SYSTEM.md / `Color+Tempo.swift`), which makes the original §4.1 contrast ratios *achievable*.

> **Status: NOT IMPLEMENTED.** There is no code for Increase Contrast (§4.3), Reduce Transparency (§4.4), or Differentiate Without Color (§4.5) — no environment reads for `accessibilityDifferentiateWithoutColor` / `accessibilityReduceTransparency` were found driving alternate styling. Color-blind support (§4.2) relies on the palette only; no shape/pattern redundancy layer is implemented. Contrast ratios are not asserted in code.

---

## 5. Motor Accessibility

> **Status: NOT IMPLEMENTED in code.** Original §5 (44pt touch-target enforcement, Switch Control groupings, Voice Control labels, AssistiveTouch, one-handed reach, Dwell, external-keyboard focus) has no dedicated code path. Standard SwiftUI controls inherit default hit areas and keyboard/Switch behavior, but none of the §5 specifications are explicitly implemented or measured.

---

## 6. Reduce Motion

Infra exists but is **built-but-unwired (DIVERGED)**. `View+Accessibility.swift` defines `tempoAnimation(_:value:)` which reads `@Environment(\.accessibilityReduceMotion)` and drops the animation when enabled. `MicroInteractionModifiers.swift` similarly gates its press-scale and fade-up on `accessibilityReduceMotion`.

> **Status: DIVERGED — near-zero adoption.** `tempoAnimation` is used by **0** views. Only **1** view file consumes the reduce-motion-aware micro-interaction modifiers. Meanwhile **~41** view files animate with raw `.animation(...)` / `withAnimation` that do **not** respect Reduce Motion. So the capability is built but effectively not wired into the UI — most animation in the app plays regardless of the Reduce Motion setting. Original §6.1's complete per-animation replacement table and §6.3 auto-play rules are NOT IMPLEMENTED across the app.

---

## 7. Cognitive Accessibility

> **Status: NOT IMPLEMENTED as a code feature.** Original §7 (information-density modes, consistent-navigation guarantees, structured error recovery, reading-level targets, post-action focus management) describes UX principles. The shipped UI follows them informally at best; there is no code enforcing density modes, reading-level constraints, or programmatic focus restoration after actions.

---

## 8. Audio Accessibility

> **Status: NOT IMPLEMENTED.** Original §8 (closed captions, visual alternatives for sounds, hearing-aid/MFi, Mono Audio, audio-descriptions toggle) is moot — the app ships no sound effects (see SOUND_AND_HAPTICS.md). No caption or visual-sound-alternative code exists. Haptics provide an incidental non-audio channel but are not a designed §8 alternative.

---

## 9. Accessibility Testing Checklist

> **Status: NOT IMPLEMENTED — checklist is a QA process, not code.** Original §9.1/§9.2 are manual pre-release / regression checklists with no automated test target backing them in the codebase.

---

## 10. Accessibility Settings in Tempo

> **Status: NOT IMPLEMENTED.** No in-app accessibility settings screen was found. The app relies entirely on system-level iOS accessibility settings (Dynamic Type and — where wired — Reduce Motion via the environment). The original §10 in-app accessibility preferences are not built.

---

## 11. Localization Accessibility

> **Status: NOT IMPLEMENTED.** Strings are not localized (no `.strings`/`.xcstrings` localization catalogs driving accessibility text); RTL/locale-specific accessibility handling from original §11 is not implemented.

---

## Appendix — As-Built Summary

| Feature | Status |
|---------|--------|
| Dynamic Type (token-layer scaling + caps) | IMPLEMENTED |
| VoiceOver labels (broad) | DIVERGED — partial (~25 files), not the per-screen audit |
| VoiceOver traits/hints/values/grouping | DIVERGED — partial (~8 view files) |
| Reduce Motion infra | DIVERGED — built, ~0 adoption (1 view; ~41 ignore it) |
| Color tokens (contrast achievable) | IMPLEMENTED (tokens) / NOT verified (ratios) |
| Increase Contrast / Reduce Transparency / Differentiate w/o color | NOT IMPLEMENTED |
| Motor (touch targets, Switch/Voice Control, keyboard) | NOT IMPLEMENTED in code |
| Cognitive / Audio accessibility | NOT IMPLEMENTED |
| Testing checklist / in-app a11y settings / localization | NOT IMPLEMENTED |
