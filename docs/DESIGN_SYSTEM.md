# Tempo Design System

> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Utilities/Constants/DesignTokens.swift` — `enum TempoSpacing`, `enum TempoRadius`, `enum TempoOpacity`, `enum TempoAnimation`, `struct TempoShadow`, `enum TempoElevation`
- `Tempo/Tempo/Utilities/Extensions/Color+Tempo.swift` — static `Color` accessors
- `Tempo/Tempo/Utilities/Extensions/Font+Tempo.swift` — static `Font` accessors, `enum TempoTracking`
- `Tempo/Tempo/Utilities/Extensions/View+Tempo.swift` — `.tempoShadow(_:)` modifier, `TempoShadowLevel`
- `Tempo/Tempo/Assets.xcassets/Colors/*.colorset` — color values (ground-truth hex lives here)
- `Tempo/Tempo/Views/Shared/Components/*`, `Views/Shared/Styles/*`, `Views/Shared/Modifiers/*` — component library

---

## Table of Contents

1. [Brand Identity](#1-brand-identity)
2. [Design Token Architecture](#2-design-token-architecture)
3. [Color System](#3-color-system)
4. [Typography](#4-typography)
5. [Spacing System](#5-spacing-system)
6. [Depth & Elevation System](#6-depth--elevation-system)
7. [Iconography](#7-iconography)
8. [Component Library](#8-component-library)
9. [Motion Design Language](#9-motion-design-language)
10. [Micro-Interaction Choreography](#10-micro-interaction-choreography)
11. [Loading State Patterns](#11-loading-state-patterns)
12. [Error State Design Patterns](#12-error-state-design-patterns)
13. [Touch Feedback Specifications](#13-touch-feedback-specifications)
14. [Responsive Breakpoints](#14-responsive-breakpoints)
15. [Layout Grid](#15-layout-grid)
16. [Accessibility](#16-accessibility)
17. [Dark Mode](#17-dark-mode)

---

## 1. Brand Identity

§1 is **design-intent narrative, not code-asserted**. It is not verifiable against Swift source and is preserved here as the canonical brand reference. There is no `BrandIdentity` type in code; voice/tone is enforced (where enforced) by `UX_COPY_BIBLE.md`-driven copy in view models, not by this section.

### 1.1 Brand Personality

| Adjective | Explanation |
|-----------|-------------|
| **Relentless** | Tempo never lets you off the hook. Every screen communicates forward momentum. Visual language is urgent, direct, unapologetic. |
| **Disciplined** | Clean lines, rigid grid, no visual clutter. Whitespace is intentional, not empty. |
| **Bold** | High-contrast typography, commanding color choices, oversized score displays. |
| **Tactical** | Military-grade precision in data presentation. Critical metrics first, context second, noise eliminated. |
| **Earned** | Achievement badges, XP totals, streak counters reflect real effort. Locked states are visible reminders of what you have not done yet. |

### 1.2 Voice & Tone Guidelines

Core principle: Tempo speaks like a drill sergeant who actually cares about you — tough love, zero fluff, occasional dark humor. Copy rules: <=12 words per notification; no exclamation marks; no emojis in primary UI (badges/achievements only); imperative mood; numeric numbers; 24h time; unit abbreviations allowed.

> **Divergence from original spec:** The original §1.2 example table is aspirational. Actual shipped copy lives in `UX_COPY_BIBLE.md` and is wired in specific view models (e.g. `DashboardViewModel` greeting bank). Loading/empty-state militaristic copy ("Assembling briefing...", "Pulling your numbers...") is **not** found wired in code — generic `LoadingStateView` / `EmptyStateView` components exist instead.

### 1.3 Logo Description & 1.4 App Icon Concept

Preserved as design intent (wordmark = modified SF Pro Display Heavy with progress-ring "O" at 75%; app icon = Commander Black squircle, Signal Red 270° ring, Bone White "T"). These are asset-production specs, not code. The shipped app icon is whatever ships in the Xcode `AppIcon` set; this doc does not assert pixel parity with the original concept.

---

## 2. Design Token Architecture

The original spec used a `tempo.color.primary.ink` dotted-token namespace accessed as `Color.Tempo.ink`, `Font.Tempo.*`, `TempoShadow.elevation2Light`. **That namespace does not exist in code.** The real system is:

- **Colors**: named **asset catalog colorsets** (`Assets.xcassets/Colors/*.colorset`, asset names like `tempo-ink`) plus literal-RGB `Color` values, all surfaced as flat static accessors on `Color` (e.g. `Color.tempoInk`).
- **Spacing / radius / opacity / animation / elevation**: Swift **enums** with flat static members in `DesignTokens.swift` (e.g. `TempoSpacing.cardPadding`, `TempoRadius.xxxl`, `TempoAnimation.springMedium`).
- **Typography**: static `Font` accessors in `Font+Tempo.swift`; tracking constants in `enum TempoTracking`.
- **Shadows**: `struct TempoShadow` + `enum TempoElevation` presets, applied via the `.tempoShadow(_:)` view modifier (`View+Tempo.swift`) which picks the light/dark variant by `colorScheme`.

> **Divergence from original spec:** Token *names and access pattern* changed entirely. The §2.3 `Color.Tempo.ink -> Color("tempo.color.primary.ink")` example and `TempoShadow.elevation2Light` are **not real**. Real is `Color.tempoInk -> Color("tempo-ink")` and `TempoElevation.cardLight`. Token *coverage* (spacing, radius, opacity, motion, elevation, type) is real and thorough — only the surface API and asset-name format diverged.

> **Divergence from original spec — token values not duplicated here.** Concrete color hex lives in each `.colorset` JSON; read the asset catalog for ground truth. This doc lists asset name + Swift accessor + role only, mirroring how `MODULE_DASHBOARD.md` §1 handles it.

---

## 3. Color System

Defined in `Color+Tempo.swift`: **52 static `Color` accessors** — **36 backed by asset colorsets** (`Assets.xcassets/Colors/`, 35 `.colorset` directories) and **16 literal-RGB** `Color(red:green:blue:)` values (training/macro/sleep/dark-mode-component colors with no colorset). Light/dark variants for asset-backed colors live inside each `.colorset` "Any/Dark appearance" JSON — the code has no separate dark accessor.

### 3.1–3.4 Asset-backed colors (35 colorsets)

| Asset Name (colorset) | Swift Accessor | Role |
|-----------------------|----------------|------|
| `tempo-bg-primary` / `-secondary` / `-tertiary` | `Color.tempoBgPrimary` / `…Secondary` / `…Tertiary` | Backgrounds |
| `tempo-surface-card` / `-sheet` / `-elevated` | `Color.tempoSurfaceCard` / `…Sheet` / `…Elevated` | Surfaces |
| `tempo-ink` | `Color.tempoInk` | Ink (shadow/scrim base) |
| `tempo-bone` | `Color.tempoBone` | Bone (light neutral) |
| `tempo-signal` / `tempo-signal-pressed` | `Color.tempoSignal` / `…SignalPressed` | Primary accent (drill-sergeant red) |
| `tempo-steel` / `tempo-concrete` / `tempo-ash` | `Color.tempoSteel` / `…Concrete` / `…Ash` | Secondary neutrals |
| `tempo-amber` / `tempo-electric` / `tempo-violet` | `Color.tempoAmber` / `…Electric` / `…Violet` | Accent (Move / Mind-info / Fuel) |
| `tempo-success` / `tempo-warning` / `tempo-error` / `tempo-info` | `Color.tempoSuccess` / `…Warning` / `…Error` / `…Info` | Semantic |
| `tempo-text-primary` / `-secondary` / `-tertiary` / `-disabled` / `-inverse` | `Color.tempoTextPrimary` / `…Secondary` / `…Tertiary` / `…Disabled` / `…Inverse` | Text |
| `tempo-border` / `-focused` / `-error` | `Color.tempoBorder` / `…Focused` / `…Error` | Borders |
| `tempo-divider` / `-heavy` | `Color.tempoDivider` / `…Heavy` | Dividers |
| `tempo-recovery-green` / `-bg` | `Color.tempoRecoveryGreen` / `…GreenBg` | Recovery high zone |
| `tempo-recovery-yellow` / `-bg` | `Color.tempoRecoveryYellow` / `…YellowBg` | Recovery moderate zone |
| `tempo-recovery-red` / `-bg` | `Color.tempoRecoveryRed` / `…RedBg` | Recovery low zone |

### 3.5 Literal-RGB colors (16, no colorset)

`Color.tempoPRGold` (#FFD700); macro bars `tempoMacroProtein` / `…Carbs` / `…Fat`; sleep stages `tempoSleepAwake` / `…Light` / `…Deep` / `…REM`; dark-mode component fills `tempoFillTertiary` / `tempoFillSecondary` / `tempoInputBgDark` / `tempoInputBgLight` / `tempoSignalHighlight` / `tempoErrorLight` / `tempoPlaceholder` / `tempoSurfaceDeep`. Hex is inline in `Color+Tempo.swift` doc-comments and is the ground truth for these (no asset to read).

> **Divergence from original spec:** The audit's "74 color tokens" is a loose pointer — the real count is **52 accessors / 35 colorsets**. The original §3.10 gradient definitions, §3.11 opacity quick-reference table, §3.13 WCAG AAA contrast verification matrix, and §3.12 full dark-mode hex mapping are **not** code artifacts — dark-mode values live per-colorset and are not centrally tabulated.

---

## 4. Typography

`Font+Tempo.swift`. Fonts are system (SF Pro / SF Pro Rounded / SF Mono). **All tokens are Dynamic-Type-aware via `UIFontMetrics.scaledFont`** — display/data/label tokens carry a base point size + text style + optional max-point cap; title/body tokens map straight to system text styles.

| Swift Accessor | Base / Mapping | Cap | Usage |
|----------------|----------------|-----|-------|
| `Font.tempoScoreDisplay` | SF Rounded 64 / `.largeTitle` | 83 | Daily composite score |
| `Font.tempoScoreDisplaySmall` | SF Rounded 48 / `.largeTitle` | 62 | Module scores |
| `Font.tempoXPDisplay` | SF Rounded 36 / `.title1` | 47 | XP total / quadrant value |
| `Font.tempoTimerDisplay` | SF Mono 56 / `.largeTitle` | 67 | Pomodoro / rest timer |
| `Font.tempoTimerDisplaySmall` | SF Mono 40 / `.title1` | 48 | Elapsed / set timer |
| `Font.tempoLargeTitle` | `.largeTitle.bold()` | — | Screen titles |
| `Font.tempoTitle1` / `Title2` / `Title3` | `.title.bold()` / `.title2.bold()` / `.title3.semibold` | — | Section / card / dialog headers |
| `Font.tempoHeadline` / `tempoSubheadline` | `.headline` / `.subheadline` | — | List row title / subtitle |
| `Font.tempoBody` / `tempoBodyBold` | `.body` / `.body.semibold` | — | Body text |
| `Font.tempoCallout` | `.callout` | — | Callout boxes |
| `Font.tempoCaption1` / `tempoCaption2` / `tempoFootnote` | `.caption` / `.caption2` / `.footnote` | — | Metadata, fine print, help text |
| `Font.tempoDataLarge` / `tempoDataMedium` / `tempoDataSmall` | SF Mono 24 / 17 / 13 (`.title2` / `.body` / `.footnote`) | 31 / — / — | Stat values, table cells |
| `Font.tempoDrillLabel` / `tempoOrdersLabel` / `tempoZoneLabel` / `tempoModuleTag` | SF Pro 12 / 12 / 12 / 10 (`.caption1` / `.caption2`) | — | All-caps tracked labels |

Letter-spacing: `enum TempoTracking` provides per-token tracking constants (e.g. `drillLabel: 1.5`, `ordersLabel: 2.0`, `body: -0.41`), applied via the `.tracking()` modifier at call sites — it is **not** baked into the `Font` accessor.

> **Divergence from original spec:** Spec specified fixed point sizes/weights/tracking enforced per token. Code uses **relative system text styles via `UIFontMetrics`** — the listed base sizes scale with Dynamic Type (capped where a `maxSize` is given). There is no fixed-pt scale enforced; tracking is opt-in at the call site. The §4.1 custom font-family claim is false — all system fonts.

---

## 5. Spacing System

`enum TempoSpacing` (`DesignTokens.swift`). Base unit 4pt (exception: `xxs` = 2pt). Scale **and** component-specific tokens are real and used.

| Token | Value | Token | Value |
|-------|-------|-------|-------|
| `xxs` | 2 | `cardPadding` | 16 |
| `xs` | 4 | `cardPaddingCompact` / `cardGap` | 12 |
| `sm` | 8 | `buttonPaddingH` / `…V` | 24 / 14 |
| `md` | 12 | `buttonPaddingHSmall` / `…VSmall` | 12 / 8 |
| `lg` | 16 | `screenEdge` / `…Compact` / `…IPad` | 20 / 16 / 24 |
| `xl` | 20 | `sectionGap` / `sectionHeaderTop` | 32 / 32 |
| `xxl` | 24 | `sectionHeaderBottom` | 8 |
| `xxxl` | 32 | `listItemVertical` / `…Horizontal` | 12 / 16 |
| `xxxxl` | 40 | `sheetHorizontal` / `…Top` / `…Bottom` | 20 / 16 / 34 |
| `xxxxxl` | 48 | `modalHorizontal` / `…Top` | 20 / 24 |

Plus `inputHorizontal`/`inputVertical` (12), `inputLabelGap` (8), `inputHelperGap` (4), `chartLegendGap` (16), `buttonStackVertical` (12), `buttonStackHorizontal` (8), `bottomSafe` (48).

> **Divergence from original spec:** `screenEdgeCompact` / `screenEdgeIPad` exist as constants but no size-class branching consumes them — spec's per-device margin rules are not enforced in code.

---

## 6. Depth & Elevation System

`struct TempoShadow` (color/radius/x/y) + `enum TempoElevation` presets, applied via `.tempoShadow(_ level:)` (`View+Tempo.swift`) which selects the light/dark variant by `@Environment(\.colorScheme)`.

| Preset | Light | Dark |
|--------|-------|------|
| `cardLight` (+ `cardDarkBorderWidth` 0.5) | ink @6%, r4, y2 | 0.5pt border, no shadow |
| `sheetLight` / `sheetDark` | ink @15%, r10, y-4 | black @40%, r2 |
| `fabLight` / `fabDark` | ink @20%, r6, y4 | black @40%, r6, y4 |
| `popoverLight` / `popoverDark` | ink @18%, r16, y8 | black @50%, r4, y2 |
| `scrimLight` / `scrimDark` | ink @40% (Color) | black @50% (Color) |

`TempoCardModifier` (`.tempoCard()`) applies the card recipe directly: `cardPadding` + `tempoSurfaceCard` + `TempoRadius.xxxl` corner + the card shadow inline (ink @6% light / 0 dark) + a `tempoBorder` stroke shown only in dark mode.

> **Status: NOT IMPLEMENTED.** §6.2 "Drill Sergeant Glow" special shadow and §6.3 dedicated stat-card shadow are not distinct presets — there is no glow shadow in `TempoElevation`.

---

## 7. Iconography

> **Status: NOT IMPLEMENTED — custom icon set.** `Assets.xcassets` contains **zero `.imageset`, `.svg`, or `.pdf` icon assets** (verified). All iconography is **SF Symbols** via `Image(systemName:)`. The original §7.3 complete icon inventory and §7.2 fixed icon-size scale do not exist in code. Icon sizing is per-call-site (`.font` / `.frame`), not a central token.

---

## 8. Component Library

Real shared components live in `Views/Shared/Components/`, `Views/Shared/Styles/`, `Views/Shared/Modifiers/`. Mapping per documented subsection:

| Spec § | Status | Real implementation |
|--------|--------|---------------------|
| 8.1 Buttons | IMPLEMENTED | `Views/Shared/Styles/TempoButtonStyle.swift` — `TempoPrimaryButtonStyle`, `TempoSecondaryButtonStyle`, `TempoDestructiveButtonStyle`, `TempoGhostButtonStyle`. `TempoIconButton` (`Components/`) for icon buttons. |
| 8.2 Cards | IMPLEMENTED | `Modifiers/TempoCardModifier.swift` (`.tempoCard()`); typed cards: `StatCardView`, `QuadrantCardView`, `WorkoutCardView`, `PrescriptionCardView`, `AchievementCardView`. |
| 8.3 Navigation | DIVERGED | No bespoke nav component. `Modifiers/TempoSettingsToolbarModifier.swift` standardizes the settings toolbar item; navigation is stock `NavigationStack` / `.toolbar`. |
| 8.4 Lists | NOT IMPLEMENTED | No `TempoList` component; screens use stock `List` / `ForEach`. |
| 8.5 Inputs | PARTIAL | `Components/TempoTextField.swift`, `Components/NumberStepperView.swift`. No date/select/search field components. |
| 8.6 Progress Indicators | IMPLEMENTED | `Components/ScoreRingView.swift`, `CircularRingView.swift` (with `RingSize`), `LinearProgressBar.swift`, `StreakDotsView.swift`. |
| 8.7 Charts | IMPLEMENTED | `Components/TempoBarChart.swift`, `TempoLineChart.swift`, `HeatmapCalendarView.swift` (Swift Charts based). |
| 8.8 Alerts & Notifications | PARTIAL | `Components/TempoToast.swift` (`TempoToast`, `ToastStyle`, `.tempoToast(_:)`). No custom alert/dialog component (stock `.alert`). |
| 8.9 Badges | NOT IMPLEMENTED | No standalone badge component; badges are inline view code per-screen. |
| 8.10 Timer Components | NOT IMPLEMENTED | No shared timer component in `Views/Shared`; timer UI is module-local. |
| 8.11 Empty States | IMPLEMENTED | `Components/EmptyStateView.swift` (generic; specific drill-sergeant copy not wired — see §1.2). |
| 8.12 Segmented Picker | NOT IMPLEMENTED | No `TempoSegmentedControl`; stock `Picker(.segmented)` where used. |
| 8.13 Sheet & Modal | DIVERGED | No central presentation component; stock `.sheet` / `.presentationDetents`. `TempoRadius.xxxxl` (20) is the sheet-corner convention. |
| 8.14 Toolbar Styling | IMPLEMENTED | `Modifiers/TempoSettingsToolbarModifier.swift`. |
| 8.15 Context Menu | NOT IMPLEMENTED | No styled context-menu wrapper; stock `.contextMenu` where used. |
| 8.16 Swipe Actions | NOT IMPLEMENTED | No shared swipe-action component. |
| 8.17 Pull-to-Refresh | DIVERGED | Stock SwiftUI `.refreshable` only — no custom 60pt-threshold control. |

Additional real shared components not in the original §8 taxonomy: `LoadingStateView` (with `LoadingStyle`), `ErrorStateView`, `OfflineBannerView`, `StaleDataIndicator`, `DrillSergeantBubble`, `TempoSectionHeader`, `MilestoneCelebrationView`, `PaywallView`, `ProgressReportView`, `NotificationSettingsView`. Toggle style: `Styles/TempoToggleStyle.swift`. Micro-interaction modifiers: `Modifiers/MicroInteractionModifiers.swift` (`PressScaleModifier`/`.pressScale()`, `AppearAnimationModifier`/`.appearAnimation()`, `ScoreRingAnimationModifier`).

> **Divergence from original spec:** `Components/TempoFAB.swift` exists but is **not used on the dashboard** (and per `MODULE_DASHBOARD.md` §8 there is no FAB fan-out anywhere). `OfflineBannerView` / `StaleDataIndicator` components exist but the dashboard does not consume them (`MODULE_DASHBOARD.md` §13).

---

## 9. Motion Design Language

`enum TempoAnimation` (`DesignTokens.swift`) — fully defined:

- Durations: `microDuration` 0.1, `smallDuration` 0.2, `mediumDuration` 0.3, `largeDuration` 0.5, `dataDuration` 0.7, `celebrationDuration` 1.0, `celebrationMajorDuration` 2.0, `celebrationEpicDuration` 3.0.
- Stagger: `staggerCard` 0.06, `staggerBar` 0.05, `staggerDot` 0.02, `staggerRing` 0.15.
- Springs: `springMedium` (0.3/0.8), `springLarge` (0.5/0.7), `springData` (0.6/0.8), `springCelebration` (0.4/0.5).
- Easing: `micro` (.easeOut 0.1), `small` (.easeInOut 0.2).

> **Divergence from original spec:** Tokens exist and match the spec's response/damping math, but adoption is sparse — per the audit and `MODULE_DASHBOARD.md`, stagger/celebration tokens are largely unused on key screens. §9.5 "Tempo Cadence" stagger rhythm and §9.6 interruptible-vs-committed rules are conventions, not enforced code.

---

## 10. Micro-Interaction Choreography

> **Status: NOT IMPLEMENTED — as a spec'd choreography system.** The only concrete code is `MicroInteractionModifiers.swift` (`pressScale`, `appearAnimation`, score-ring animation). The §10.1–10.9 per-interaction scripts (tab-switch, card-expansion matchedGeometry, score count-up, skeleton->content, achievement-unlock, error->retry, empty->populated, notification banner) are **not** built as a coordinated system — see `MODULE_DASHBOARD.md` §3.9 (no load choreography) and §4.1 (no matchedGeometry morph).

---

## 11. Loading State Patterns

Real: `Components/LoadingStateView.swift` (`LoadingStyle` enum). Skeleton opacity token `TempoOpacity.skeleton` exists.

> **Status: NOT IMPLEMENTED.** §11.1 shimmer-gradient spec, §11.2 per-component skeleton definitions, and §11.3 militaristic loading-text bank are not built. One generic loading view, not per-component skeletons; the specific copy is not in code.

---

## 12. Error State Design Patterns

Real: `Components/ErrorStateView.swift` (full-screen error + retry), `Components/TempoToast.swift` (`ToastStyle` includes an error variant).

> **Status: NOT IMPLEMENTED.** §12.1 severity-level taxonomy, §12.2 inline error, §12.4 persistent banner error, §12.6 drill-sergeant critical error are not distinct components. Error handling is screen-wide via `ErrorStateView` / toast (see `MODULE_DASHBOARD.md` §17 — no per-row error matrix).

---

## 13. Touch Feedback Specifications

Real: `.pressScale()` (`MicroInteractionModifiers.swift`, default scale 0.96) for press-scale; haptics via `Utilities/Helpers/HapticManager.swift` (UIKit feedback generators only — see `SOUND_AND_HAPTICS.md` audit).

> **Status: NOT IMPLEMENTED.** The per-component touch-feedback table (specific scale values, haptic mapping, timing per control) is not codified — `pressScale` is applied ad hoc. No custom Core Haptics patterns.

---

## 14. Responsive Breakpoints

> **Status: NOT IMPLEMENTED.** No breakpoint / size-class branching engine. `TempoSpacing` has `screenEdgeCompact` / `screenEdgeIPad` constants but nothing consumes them conditionally. SwiftUI adaptive layout (`LazyVGrid`, flexible grid items) handles sizing; see `MODULE_DASHBOARD.md` §1.4 (no per-device matrix).

---

## 15. Layout Grid

> **Status: NOT IMPLEMENTED — as a formal grid system.** No column-system type, no `(screenWidth - 2*edge - gap)/2` formula, no fixed dashboard layout spec in code. Layout is per-screen SwiftUI stacks/grids using `TempoSpacing` tokens. Screen-edge convention: `TempoSpacing.screenEdge` (20pt).

---

## 16. Accessibility

Real: Dynamic Type is handled correctly at the **font-token layer** — every display/data/label token uses `UIFontMetrics.scaledFont` with optional max caps (§4), so per-view `@ScaledMetric` is unnecessary by design. Reduce-Motion infra exists (`Utilities/Extensions/View+Accessibility.swift` — `.tempoAnimation` reads `accessibilityReduceMotion`; `tempoDisplayCapped()`). VoiceOver labels/traits/values present in ~25 source files.

> **Status: NOT IMPLEMENTED / PARTIAL.** §16.1 minimum-touch-target enforcement is not codified. Reduce-Motion adoption is near-zero — `.tempoAnimation` is essentially unused while ~40 Views use raw `.animation` / `withAnimation` that ignore Reduce Motion. §16.3 color-blind-safe and §16.2 exhaustive per-screen VoiceOver label table are QA/process assertions, not fully verifiable from source.

---

## 17. Dark Mode

Real: Dark mode is delivered per asset colorset (each `.colorset` carries an Any + Dark appearance). `TempoCardModifier` and `TempoElevation` branch on `@Environment(\.colorScheme)` for shadow-vs-border treatment. Literal-RGB colors (§3.5) include explicit dark-component fills.

> **Status: NOT IMPLEMENTED.** §17.2 surface-elevation model, §17.4 dark-mode gradient stops, §17.5 implementation checklist are not central code artifacts — dark values are decentralized in per-colorset JSON, and there is no gradient system (§3.10) to have dark stops.

---

*End of as-built description. Reconciled to code on 2026-05-19. Where this doc and the source disagree, the source is authoritative — fix the doc, not the code, unless the divergence is itself the bug.*
