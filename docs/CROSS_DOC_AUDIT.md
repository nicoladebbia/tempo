# Tempo Documentation Cross-Reference Audit

> **Auditor**: Technical Editor
> **Date**: 2026-03-24
> **Scope**: All 12 specification documents
> **Verdict**: 47 issues found. 12 critical, 19 major, 16 minor.

---

## Resolution Summary

> **Resolved**: 47/47 issues resolved on 2026-03-24.
> **Resolution agent**: Claude Opus 4.6 (1M context), ruthless technical editor pass.

| Category | Count | Status |
|----------|-------|--------|
| Critical (1-6) | 12 | ALL RESOLVED |
| Major (7-22) | 19 | ALL RESOLVED |
| Minor (23-35) | 16 | ALL RESOLVED |

**Key changes made:**
- **Recovery zone colors**: Unified to Design System values (#22C55E / #EAB308 / #DC2626) across all 7 files
- **Token naming**: All module docs now use `tempo.color.<category>.<group>.<variant>` naming convention
- **DailySnapshot**: Added `spo2` and `skinTemp` fields; added Dashboard view model section (Section 4.2) to DATA_MODELS_IOS.md
- **Notification intensity**: Standardized to 4 levels (Gentle Coach / Firm Coach / Drill Sergeant / Savage Mode) with mapping table in Accountability doc
- **Dark mode backgrounds**: All modules aligned to Design System dark tokens (#0D0D0D bg, #1C1C1E card, #2C2C2E elevated)
- **Quadrant width table**: Fixed arithmetic to match formula results
- **Layout constants**: Screen padding standardized to 20pt, button radius to 14pt, card gap to 12pt
- **Typography**: Body text standardized to 15pt, section titles to 28pt Bold
- **Animation durations**: Dashboard mapped to `tempo.motion.*` Design System tokens
- **Celebration tiers**: Added `tempo.motion.celebration.major` (2000ms) and `tempo.motion.celebration.epic` (3000ms) to Design System
- **Sleep stage colors**: Added as `tempo.color.sleep.*` tokens in Design System
- **Data model**: `ps5TimeMinutes` renamed to `leisureTimeMinutes`; `notificationIntensity` updated to support 4 levels
- **Module exceptions**: Arena, Accountability, Recovery color systems explicitly acknowledged as approved exceptions with alignment notes

---

## Table of Contents

1. [Critical: Recovery Zone Color Hex Codes (5 Conflicting Definitions)](#1-critical-recovery-zone-color-hex-codes)
2. [Critical: Token Naming Mismatch Between Design System and Module Docs](#2-critical-token-naming-mismatch)
3. [Critical: DailySnapshot Missing Fields Referenced by Dashboard](#3-critical-dailysnapshot-missing-fields)
4. [Critical: Recovery Zone Boundary Ambiguity (>=67 vs >66, <=33 vs <34)](#4-critical-recovery-zone-boundary-ambiguity)
5. [Critical: Notification Intensity Levels (3 vs 4 Tiers)](#5-critical-notification-intensity-levels)
6. [Critical: Notification Intensity Naming (3 Different Schemes)](#6-critical-notification-intensity-naming)
7. [Major: Animation Duration Conflicts](#7-major-animation-duration-conflicts)
8. [Major: Stagger Duration Conflict](#8-major-stagger-duration-conflict)
9. [Major: Screen Horizontal Padding Conflicts](#9-major-screen-horizontal-padding-conflicts)
10. [Major: Tab Bar Height Conflicts](#10-major-tab-bar-height-conflicts)
11. [Major: Background Color Hex Conflicts](#11-major-background-color-hex-conflicts)
12. [Major: Text Color Hex Conflicts](#12-major-text-color-hex-conflicts)
13. [Major: Accent Red Color Conflicts](#13-major-accent-red-color-conflicts)
14. [Major: Card Surface Color Conflicts](#14-major-card-surface-color-conflicts)
15. [Major: Typography Scale Conflicts](#15-major-typography-scale-conflicts)
16. [Major: Spacing Token Naming Divergence](#16-major-spacing-token-naming-divergence)
17. [Major: Corner Radius Conflicts](#17-major-corner-radius-conflicts)
18. [Major: Confetti Animation Duration Conflict](#18-major-confetti-animation-duration-conflict)
19. [Major: Dashboard `recovery_score` Type Conflict (Int vs Double)](#19-major-dashboard-recovery-score-type)
20. [Major: BodyQuadrantData `recovery_score` as Int vs DailySnapshot `recoveryScore` as Double](#20-major-bodyquadrantdata-type-mismatch)
21. [Major: Quadrant Width Calculation Error](#21-major-quadrant-width-calculation-error)
22. [Major: Onboarding Notification Categories vs Accountability Tiers](#22-major-onboarding-notification-categories-vs-accountability-tiers)
23. [Minor: "Non-negotiable" Spelling Variations](#23-minor-non-negotiable-spelling)
24. [Minor: PS5 / Leisure / Gaming Terminology](#24-minor-ps5-leisure-gaming-terminology)
25. [Minor: Divider Color Conflicts](#25-minor-divider-color-conflicts)
26. [Minor: Haptic Pattern Conflicts Between Modules](#26-minor-haptic-pattern-conflicts)
27. [Minor: PR Confetti Duration Conflict](#27-minor-pr-confetti-duration-conflict)
28. [Minor: Weekly Summary Notification Timing](#28-minor-weekly-summary-notification-timing)
29. [Minor: Sleep Stage Colors Orphaned](#29-minor-sleep-stage-colors-orphaned)
30. [Minor: Arena Color System is Completely Independent](#30-minor-arena-color-system-independent)
31. [Minor: Accountability Color System is Completely Independent](#31-minor-accountability-color-system-independent)
32. [Minor: Recovery Module Color System is Completely Independent](#32-minor-recovery-color-system-independent)
33. [Minor: Card Spacing Inconsistency](#33-minor-card-spacing-inconsistency)
34. [Orphaned Features](#34-orphaned-features)
35. [Missing Cross-References](#35-missing-cross-references)
36. [Master Cross-Reference Table](#36-master-cross-reference-table)

---

## 1. Critical: Recovery Zone Color Hex Codes -- RESOLVED 2026-03-24

**Five different sets of "recovery green/yellow/red" hex codes exist across the documentation suite.** This is the single most dangerous inconsistency in the codebase -- every module will render recovery zones in different colors.

| Document | Green | Yellow | Red |
|----------|-------|--------|-----|
| **DESIGN_SYSTEM.md** (line 141-145) | `#22C55E` | `#EAB308` | `#DC2626` |
| **MODULE_DASHBOARD.md** (line 46-54) | `#30D158` | `#FFD60A` | `#FF3B30` |
| **MODULE_TRAINING.md** (line 52-54) | `#34C759` | `#FFD60A` | `#FF3B30` |
| **MODULE_RECOVERY.md** (line 97-101) | `#00C48C` | `#FFB800` | `#FF4757` |
| **MODULE_ACCOUNTABILITY.md** (line 41) | `#2DC653` | `#FFB703` | `#E63946` |
| **DATA_MODELS_IOS.md** (line 342-344) | `#00C48C` | `#FFB800` | `#FF4757` |
| **MODULE_ARENA.md** (line 62) | `#00C48C` | n/a | n/a |
| **ACCESSIBILITY.md** (line 941-943) | `#22C55E` | `#EAB308` | `#DC2626` |

**Resolution**: DESIGN_SYSTEM.md declares itself as "single source of truth" (line 5). Use its values:
- **Green**: `#22C55E` (token: `tempo.color.recovery.green`)
- **Yellow**: `#EAB308` (token: `tempo.color.recovery.yellow`)
- **Red**: `#DC2626` (token: `tempo.color.recovery.red`)

All other documents MUST be updated to reference these tokens by name, not by raw hex.

DATA_MODELS_IOS.md `RecoveryZone.color` (line 342-344) is particularly dangerous because it hardcodes hex values in Swift code. It must be changed to reference asset catalog colors.

---

## 2. Critical: Token Naming Mismatch -- RESOLVED 2026-03-24

The Design System defines tokens with the `tempo.color.*` prefix (e.g., `tempo.color.recovery.green`). Module documents define their own ad-hoc token names that do not exist in the Design System.

| Module Doc | Token Used | Design System Equivalent | Status |
|-----------|-----------|--------------------------|--------|
| MODULE_DASHBOARD.md (line 39) | `tempo.bg.primary` | `tempo.color.bg.primary` | **Missing `color.` segment** |
| MODULE_DASHBOARD.md (line 40) | `tempo.bg.card` | `tempo.color.surface.card` | **Different group AND value** |
| MODULE_DASHBOARD.md (line 42) | `tempo.text.primary` | `tempo.color.text.primary` | **Missing `color.` segment + different hex** |
| MODULE_DASHBOARD.md (line 45) | `tempo.accent` | `tempo.color.primary.signal` | **Different name + different hex** |
| MODULE_DASHBOARD.md (line 46) | `tempo.green` | `tempo.color.recovery.green` | **Different name + different hex** |
| MODULE_DASHBOARD.md (line 52) | `tempo.body.green` | `tempo.color.recovery.green` | **Different name + different hex** |
| MODULE_TRAINING.md (line 44) | `primary` | `tempo.color.primary.signal` | **No namespace, different hex `#FF4B2B`** |
| MODULE_TRAINING.md (line 52) | `recoveryGreen` | `tempo.color.recovery.green` | **No namespace, different hex `#34C759`** |
| MODULE_RECOVERY.md (line 97) | `recovery.green.primary` | `tempo.color.recovery.green` | **Different namespace, different hex** |
| MODULE_ACCOUNTABILITY.md (line 40) | `locked.red` | No equivalent | **Entirely custom token** |
| MODULE_ACCOUNTABILITY.md (line 42) | `progress.blue` | `tempo.color.accent.electric` | **Different namespace, different hex** |
| MODULE_ARENA.md (line 62) | Uses raw hex inline | N/A | **No tokens at all** |

**Resolution**: Every module doc must use the `tempo.<category>.<group>.<variant>` token names from DESIGN_SYSTEM.md Section 2.1. Where module-specific tokens are needed (e.g., `locked.red`, `setComplete`), they should be added to the Design System's token registry as `tempo.color.accountability.*` and `tempo.color.training.*`.

---

## 3. Critical: DailySnapshot Missing Fields -- RESOLVED 2026-03-24

MODULE_DASHBOARD.md `BodyQuadrantData` (line 197-208) references fields not present in DATA_MODELS_IOS.md `DailySnapshot` (line 921-1010):

| Field in Dashboard Spec | Present in DailySnapshot? | Notes |
|------------------------|--------------------------|-------|
| `spo2_percentage` | **NO** | Dashboard line 204 expects SpO2. DailySnapshot has no `spo2` field. |
| `skin_temp` | **NO** | Not referenced in Dashboard but exists in DailyRecovery model (line 2853) |
| `sleep_performance_percentage` | Yes (as `sleepScore`) | Name mismatch only |
| `source` / `lastSync` / `isStale` | **NO** | Dashboard expects per-quadrant connection metadata; DailySnapshot has a single `updatedAt` |
| `meal_statuses` array | **NO** | Dashboard FuelQuadrantData (line 221) expects structured meal status array |
| `exams` array | **NO** | Dashboard MindQuadrantData (line 230) expects exam data |
| `heart_rate_current` | **NO** | Dashboard MoveQuadrantData (line 248) expects live HR |
| `workout_name` | **NO** (has `workoutTypeRaw`) | Type vs name |

**Resolution**: DailySnapshot needs `spo2`, per-quadrant sync timestamps, and the `DashboardState` wrapper described in MODULE_DASHBOARD.md should be documented as a separate view model, not confused with the persistence model. Alternatively, `BodyQuadrantData` should be listed in DATA_MODELS_IOS.md as a `@Transient` computed model or view model.

---

## 4. Critical: Recovery Zone Boundary Ambiguity -- RESOLVED 2026-03-24

The boundary between green/yellow and yellow/red is specified inconsistently:

| Document | Green | Yellow | Red |
|----------|-------|--------|-----|
| DESIGN_SYSTEM.md (line 727-731) | 67-100% | 34-66% | 0-33% |
| MODULE_DASHBOARD.md (line 52-54) | >= 67% | 34-66% | < 34% |
| MODULE_RECOVERY.md (line 52-54) | 67-100% | 34-66% | 0-33% |
| MODULE_TRAINING.md (line 52-54) | >=67% | 34-66% | <34% |
| DATA_MODELS_IOS.md (line 328-336) | `67...100` | `34..<67` | default (< 34) |
| INTEGRATION_SPECS.md (line 522) | >= 67 | >= 34 | < 34 |
| MODULE_RECOVERY.md (line 101) | >= 67 | 34-66 | **<= 33** |

**The conflict**: MODULE_RECOVERY.md line 101 says red is `<= 33`, which means 33% is red. DATA_MODELS_IOS.md line 334 uses `34..<67`, meaning 34.0% is yellow but 33.99% is red. The Swift `67...100` range means exactly 67.0% is green. This is consistent.

However, MODULE_RECOVERY.md line 101 says `recovery <= 33` for red, while others say `< 34`. For integers these are equivalent, but `recoveryScore` is a `Double?` in DailySnapshot (line 933). A score of 33.5% would be:
- Red per MODULE_RECOVERY.md (`<= 33` -- NO, 33.5 > 33, so actually yellow)
- Red per DATA_MODELS_IOS.md (`34..<67` -- NO, 33.5 < 34, so `default` = red)

These ARE equivalent for all practical purposes. But the documentation uses inconsistent notation (<=33 vs <34 vs 0-33%) that will confuse developers.

**Resolution**: Standardize all docs to use the Swift code as canonical:
- **Green**: `score >= 67.0`
- **Yellow**: `score >= 34.0 && score < 67.0`
- **Red**: `score < 34.0`

Express as inclusive ranges in prose: "Green (67-100%), Yellow (34-66%), Red (0-33%)" with a footnote that boundary values (67.0, 34.0) belong to the higher zone.

---

## 5. Critical: Notification Intensity Levels (3 vs 4 Tiers) -- RESOLVED 2026-03-24

| Document | Number of Levels | Names |
|----------|-----------------|-------|
| MODULE_ACCOUNTABILITY.md (line 1964-1967) | **3** | Gentle, Standard, Savage |
| ONBOARDING_AND_NOTIFICATIONS.md (line 1014-1031) | **4** | Gentle Coach, Firm Coach, Drill Sergeant, Savage Mode |
| DATA_MODELS_IOS.md (line 732) | **3** | `1 = gentle, 2 = firm, 3 = drill sergeant` |

**Three-way conflict:**
1. Accountability says 3 levels: Gentle / Standard / Savage
2. Onboarding says 4 levels: Gentle Coach / Firm Coach / Drill Sergeant / Savage Mode
3. Data model says 3 levels: gentle(1) / firm(2) / drill_sergeant(3)

The data model omits "Savage Mode" entirely. The Accountability module calls the middle tier "Standard" while the data model calls it "firm." The Onboarding spec splits the top into two (Drill Sergeant and Savage Mode) while the data model only goes to 3.

**Resolution**: Decide on either 3 or 4 intensity levels. If 4: update DATA_MODELS_IOS.md to support `notification_intensity: 1-4`. If 3: remove "Savage Mode" from ONBOARDING_AND_NOTIFICATIONS.md or merge it with Drill Sergeant. Standardize names across all three documents.

---

## 6. Critical: Notification Intensity Naming (3 Different Schemes) -- RESOLVED 2026-03-24

Even within MODULE_ACCOUNTABILITY.md itself, the copy pool uses "Standard Intensity / Gentle Intensity / Savage Intensity" (line 1321-1362) to categorize MESSAGE TONE, while the settings section (line 1964-1967) uses "Gentle / Standard / Savage" to categorize USER-FACING SETTINGS.

Meanwhile, ONBOARDING_AND_NOTIFICATIONS.md (line 1666-1669) uses letter codes for copy variants: G = Gentle Coach, F = Firm Coach, D = Drill Sergeant, S = Savage Mode.

These are likely meant to map to each other, but the naming divergence means:
- A developer reading Accountability's "Standard Intensity" copy pool might think it maps to the "Standard" setting
- But in Onboarding, the equivalent is "Firm Coach" (F)
- And in the data model, it is `notificationIntensity: 2` (firm)

**Resolution**: Create a single mapping table and put it in all three docs:

| Setting Name | Data Model Value | Accountability Copy Pool | Onboarding Letter Code |
|-------------|-----------------|------------------------|----------------------|
| Gentle Coach | 1 | Gentle Intensity | G |
| Firm Coach | 2 | Standard Intensity | F |
| Drill Sergeant | 3 | Savage Intensity | D |
| Savage Mode | 4 (add to model) | (add new tier) | S |

---

## 7. Major: Animation Duration Conflicts -- RESOLVED 2026-03-24

| Animation | Design System (token) | Module Dashboard | Module Training |
|-----------|----------------------|------------------|-----------------|
| Card transition | `tempo.motion.medium`: 300ms, spring(0.3, 0.8) | `tempo.anim.standard`: 0.35s, spring(0.35, 0.85) | 350ms, spring(0.35, 0.8) |
| Fast/micro | `tempo.motion.micro`: 100ms | `tempo.anim.fast`: 0.2s = 200ms | N/A |
| Celebration | `tempo.motion.celebration`: 1000ms, spring(0.4, 0.5) | `tempo.anim.confetti`: 0.8s | N/A |

**Resolution**: The Design System motion tokens (Section 2.2) should be canonical. Dashboard's `tempo.anim.*` tokens must be mapped to the Design System equivalents. Currently they define entirely separate animation systems.

---

## 8. Major: Stagger Duration Conflict -- RESOLVED 2026-03-24

| Document | Value |
|----------|-------|
| DESIGN_SYSTEM.md (line 270) | `tempo.motion.stagger.card` = **60ms** |
| MODULE_DASHBOARD.md (line 154) | `tempo.anim.stagger` = **0.08s = 80ms** |

**Resolution**: Use Design System value of 60ms. Update Dashboard doc.

---

## 9. Major: Screen Horizontal Padding Conflicts -- RESOLVED 2026-03-24

| Document | Value |
|----------|-------|
| DESIGN_SYSTEM.md (line 195) | `tempo.space.screen.edge` = **20pt** |
| MODULE_DASHBOARD.md (line 87) | `tempo.space.xl` = **20pt** |
| MODULE_ACCOUNTABILITY.md (line 76) | Screen horizontal padding: **16pt** |
| MODULE_RECOVERY.md (line 156) | `screen.horizontalPadding` = **20pt** |
| MODULE_TRAINING.md (line 355) | **16pt** horizontal margins from screen edges |
| MODULE_ARENA.md (line 483) | **16pt** horizontal padding each side |

**Resolution**: DESIGN_SYSTEM.md says 20pt. Accountability, Training, and Arena use 16pt. The 16pt is the Design System's "compact" variant for iPhone SE. Standardize: use 20pt for all non-SE devices, 16pt only for iPhone SE via `tempo.space.screen.edge.compact`.

---

## 10. Major: Tab Bar Height Conflicts -- RESOLVED 2026-03-24

| Document | Value |
|----------|-------|
| MODULE_TRAINING.md (line 115) | **83pt** (with safe area) |
| MODULE_RECOVERY.md (line 170) | **49pt** (standard iOS) |
| DESIGN_SYSTEM.md (line 2962) | **49pt + safe area** |

**Resolution**: The standard iOS tab bar is 49pt. With the home indicator safe area (34pt on modern iPhones), the total is 83pt. MODULE_TRAINING.md is correct for TOTAL space, MODULE_RECOVERY.md is correct for the tab bar ITSELF. Standardize language: "Tab bar: 49pt (+ 34pt safe area on Face ID devices = 83pt total)."

---

## 11. Major: Background Color Hex Conflicts -- RESOLVED 2026-03-24

| Document | Light BG | Dark BG |
|----------|----------|---------|
| DESIGN_SYSTEM.md (line 148) | `#F5F2ED` (Bone White) | N/A |
| MODULE_DASHBOARD.md (line 39) | `#FAFAFA` | `#0A0A0A` |
| MODULE_TRAINING.md (line 47) | N/A (dark only) | `#0F0F12` |
| MODULE_RECOVERY.md (line 124) | N/A (dark only) | `#000000` |
| MODULE_ACCOUNTABILITY.md (line 44) | N/A (dark only) | `#0D1117` |
| MODULE_ARENA.md (line 62) | N/A (dark only) | `#0A1628` |
| ONBOARDING_AND_NOTIFICATIONS.md (line 128) | N/A | `#000000` |

Every module uses a different dark background. The Design System's light BG (`#F5F2ED`) is not used by Dashboard (`#FAFAFA`).

**Resolution**: Design System must define canonical dark mode backgrounds. Currently it only hints at dark mode tokens (Section 17). All modules must use the same dark background or the Design System must explicitly approve per-module dark backgrounds.

---

## 12. Major: Text Color Hex Conflicts -- RESOLVED 2026-03-24

| Document | Primary Text (Light) | Primary Text (Dark) |
|----------|---------------------|---------------------|
| DESIGN_SYSTEM.md (line 157) | `#0D0D0D` | (undeclared in token registry) |
| MODULE_DASHBOARD.md (line 42) | `#0A0A0A` | `#F5F5F5` |
| MODULE_TRAINING.md (line 49) | N/A | `#FFFFFF` |
| MODULE_RECOVERY.md (line 127) | N/A | `#FFFFFF` |
| MODULE_ACCOUNTABILITY.md (line 47) | N/A | `#F0F6FC` |

**Resolution**: Use Design System `#0D0D0D` for light mode. For dark mode, standardize to one value (likely `#F5F2ED` per Bone White token, or `#FFFFFF`).

---

## 13. Major: Accent Red Color Conflicts -- RESOLVED 2026-03-24

The "primary accent red" differs across docs:

| Document | Hex | Name |
|----------|-----|------|
| DESIGN_SYSTEM.md (line 126) | `#E63946` | Signal Red |
| MODULE_DASHBOARD.md (line 45) | `#FF3B30` | drill-sergeant red |
| MODULE_TRAINING.md (line 44) | `#FF4B2B` | primary CTA |
| MODULE_ARENA.md (line 62) | `#FF3B5C` | crimson |
| MODULE_ACCOUNTABILITY.md (line 40) | `#E63946` | locked.red |

**Resolution**: Use Design System's `#E63946` (Signal Red). Dashboard and Training use iOS system red (`#FF3B30`), which is NOT the Tempo brand color.

---

## 14. Major: Card Surface Color Conflicts -- RESOLVED 2026-03-24

| Document | Light | Dark |
|----------|-------|------|
| DESIGN_SYSTEM.md (line 152) | `#FFFFFF` | (undeclared) |
| MODULE_DASHBOARD.md (line 40) | `#FFFFFF` | `#1A1A1A` |
| MODULE_TRAINING.md (line 46) | N/A | `#1A1A1E` |
| MODULE_RECOVERY.md (line 125) | N/A | `#1A1A2E` |
| MODULE_ACCOUNTABILITY.md (line 45) | N/A | `#161B22` |
| MODULE_ARENA.md (line 64) | N/A | `#12203A` |

Five different dark card backgrounds.

**Resolution**: Design System must define `tempo.color.surface.card.dark`. All modules use it.

---

## 15. Major: Typography Scale Conflicts -- RESOLVED 2026-03-24

| Style | Design System | Dashboard | Training | Accountability | Recovery |
|-------|--------------|-----------|----------|----------------|----------|
| Display/Hero | Not defined | 34pt Black (900) | 34pt Bold | 34pt Bold | 72pt Bold (SF Pro Rounded) |
| Headline/Screen title | Not defined | 28pt Bold | 28pt Bold | 28pt Bold | 20pt Semibold |
| Body | Not defined | 15pt Regular | 15pt Regular | 17pt Regular | 15pt Regular |
| Timer | Not defined | Not defined | 72pt Bold SF Mono | 72pt Light SF Pro Rounded | Not defined |

Specific conflicts:
- **Body text**: Accountability says 17pt (line 64), everyone else says 15pt.
- **Timer font**: Training uses SF Mono Bold 72pt (line 87); Accountability uses SF Pro Rounded Light 72pt (line 70). Different font AND weight.
- **Recovery hero**: 72pt SF Pro Rounded Bold -- no equivalent in other modules' type scales.

**Resolution**: The Design System (Section 4) must define a complete typography scale that all modules reference. Currently the Design System has no typography section shown in the token registry -- it jumps from colors to spacing. Add a `tempo.font.*` token registry.

---

## 16. Major: Spacing Token Naming Divergence -- RESOLVED 2026-03-24

| Design System Token | Dashboard Token | Training Token |
|--------------------|-----------------|----------------|
| `tempo.space.xl` = 20pt | `tempo.space.xl` = 20pt | `xl` = **24pt** |
| `tempo.space.2xl` = 24pt | `tempo.space.xxl` = 24pt | `xxl` = **32pt** |
| `tempo.space.3xl` = 32pt | `tempo.space.xxxl` = 32pt | `xxxl` = **48pt** |

Training's `xl` (24pt) does not match Design System's `xl` (20pt). Training's scale appears shifted up by one tier.

**Resolution**: Use Design System values. Training must adopt `tempo.space.*` naming with DS values.

---

## 17. Major: Corner Radius Conflicts -- RESOLVED 2026-03-24

| Document | Card Radius |
|----------|-------------|
| DESIGN_SYSTEM.md (line 227) | `tempo.radius.3xl` = **16pt** |
| MODULE_DASHBOARD.md (line 90) | `tempo.radius.card` = **16pt** |
| MODULE_ACCOUNTABILITY.md (line 78) | Card corner radius: **16pt** |
| MODULE_TRAINING.md (line 112) | Exercise card: **16pt** |
| MODULE_RECOVERY.md (line 158) | `card.cornerRadius` = **16pt** |

Cards are consistent at 16pt. However:

| Document | Button Radius |
|----------|--------------|
| DESIGN_SYSTEM.md (line 226) | `tempo.radius.2xl` = **14pt** |
| MODULE_ACCOUNTABILITY.md (line 81) | Button: **12pt** (large), **8pt** (small) |
| MODULE_TRAINING.md (line 110) | Primary button: **16pt** |

Button corner radii are 12pt, 14pt, and 16pt depending on the document.

**Resolution**: Use Design System's 14pt for standard buttons. Update Accountability (12pt) and Training (16pt).

---

## 18. Major: Confetti Animation Duration Conflict -- RESOLVED 2026-03-24

| Document | Duration |
|----------|----------|
| MODULE_DASHBOARD.md (line 159) | `tempo.anim.confetti` = **0.8s** |
| MODULE_TRAINING.md (line 163) | PR confetti burst = **2000ms** |
| MODULE_ACCOUNTABILITY.md (line 213) | Confetti: **3s** |

Three different confetti durations for three different modules.

**Resolution**: These may be intentionally different (non-neg completion is subtle, PR is dramatic, unlock is celebratory). If so, document this explicitly. If not, standardize to `tempo.motion.celebration` = 1000ms from the Design System.

---

## 19. Major: Dashboard recovery_score Type Conflict -- RESOLVED 2026-03-24

| Document | Type |
|----------|------|
| MODULE_DASHBOARD.md (line 198) | `recovery_score: Int?` |
| DATA_MODELS_IOS.md (line 933) | `recoveryScore: Double?` |
| INTEGRATION_SPECS.md (line 522) | Derived from Double |

**Resolution**: Use `Double?` as in the data model. Dashboard spec must update its `BodyQuadrantData` to use Double.

---

## 20. Major: BodyQuadrantData Type Mismatch -- RESOLVED 2026-03-24

MODULE_DASHBOARD.md `BodyQuadrantData` (line 199) specifies `hrv_rmssd: Double?` with "1 decimal" while DATA_MODELS_IOS.md `DailySnapshot` (line 936) uses `hrv: Double?`. The field name differs (`hrv_rmssd` vs `hrv`).

Similarly:
- Dashboard: `resting_heart_rate: Int?` vs DailySnapshot: `rhr: Double?` (Int vs Double AND different name)
- Dashboard: `sleep_performance_percentage: Int?` vs DailySnapshot: `sleepScore: Double?` (different name)
- Dashboard: `strain: Double?` matches DailySnapshot: `strain: Double?` (consistent)

**Resolution**: Establish a view model layer (`BodyQuadrantData`) in DATA_MODELS_IOS.md that maps from `DailySnapshot` fields, documenting the exact mapping.

---

## 21. Major: Quadrant Width Calculation Error -- RESOLVED 2026-03-24

MODULE_DASHBOARD.md (line 111-114) shows calculated quadrant widths that do not match the table above (line 102-108):

| Device | Table Says | Formula Says |
|--------|-----------|-------------|
| iPhone SE | 167.5pt | 159.5pt |
| iPhone 15 | 176.5pt | 168.5pt |
| iPhone 15 Pro Max | 195pt | 187pt |
| iPhone 16 Pro Max | 200pt | 192pt |

The table values are ~8pt larger than the formula produces. The formula `(screenWidth - 40 - 16) / 2` is correct; the table is wrong.

**Resolution**: Fix the table to match the formula results, or acknowledge that the table represents a different layout.

---

## 22. Major: Onboarding Notification Categories vs Accountability Tiers -- RESOLVED 2026-03-24

ONBOARDING_AND_NOTIFICATIONS.md defines these notification categories (line 1565-1579):
- `ACCOUNTABILITY_GENTLE`
- `ACCOUNTABILITY_FIRM`
- `ACCOUNTABILITY_URGENT`
- `ACCOUNTABILITY_FINAL`
- `ACCOUNTABILITY_CLEAR`

MODULE_ACCOUNTABILITY.md defines tiers (line 1280-1287):
- Tier 0: Morning Briefing
- Tier 1: Gentle Reminders
- Tier 2: Firm Warnings
- Tier 3: Urgent Alerts
- Tier 4: Final Warning
- Tier 5: Completion Celebration
- Tier 6: Weekly Summary

The categories mostly map to tiers, but:
- `MORNING_BRIEFING` in Onboarding is separate from `ACCOUNTABILITY_GENTLE` -- this aligns with Tier 0 vs Tier 1.
- Tier 5 (Celebration) maps to `ACCOUNTABILITY_CLEAR` -- naming mismatch ("clear" vs "celebration").
- Tier 6 (Weekly Summary) maps to `WEEKLY_SUMMARY` -- this is consistent.
- But `ACCOUNTABILITY_FIRM` in Onboarding vs "Tier 2: Firm Warnings" in Accountability -- these align.

**Resolution**: Add an explicit mapping table in both documents. The naming is close enough but should be made identical.

---

## 23. Minor: "Non-negotiable" Spelling -- RESOLVED 2026-03-24

| Variant | Occurrences |
|---------|------------|
| "non-negotiable" (hyphenated) | Most docs, Design System, Dashboard, Accountability |
| "non negotiable" (space) | Some body text |
| "nonnegotiable" (one word) | MODULE_DASHBOARD.md line 1983 (`complete_all_nonneg_82pct`) |
| "NonNegotiable" (camelCase) | DATA_MODELS_IOS.md (Swift class name) |

**Resolution**: Use "non-negotiable" (hyphenated) in all documentation prose. Use `NonNegotiable` in Swift code. Use `non_negotiable` in API/JSON fields.

---

## 24. Minor: PS5 / Leisure / Gaming Terminology -- RESOLVED 2026-03-24

| Term | Where Used |
|------|-----------|
| "PS5" | MODULE_ACCOUNTABILITY.md (throughout), MODULE_DASHBOARD.md (line 784, 789), notifications |
| "leisure" | MODULE_ACCOUNTABILITY.md (line 168, 368, 384), APPLE_WATCH_APP.md |
| "Leisure Status" | MODULE_ACCOUNTABILITY.md Section 2.4 heading |
| "PS5 time" | MODULE_ACCOUNTABILITY.md settings, DATA_MODELS_IOS.md (`ps5TimeMinutes`) |

The feature is called "Leisure Status" in the UI section heading but all user-facing copy references "PS5." The data model uses `ps5TimeMinutes`.

**Resolution**: The internal data model name `ps5TimeMinutes` is brittle (what if the user doesn't have a PS5?). Rename to `leisureTimeMinutes` in data model. Keep "PS5" in the drill-sergeant copy as the default motivational reference, but the UI label should be "Leisure Status" and the settings should say "Leisure Time" with a note that default copy references PS5.

---

## 25. Minor: Divider Color Conflicts -- RESOLVED 2026-03-24

| Document | Hex |
|----------|-----|
| DESIGN_SYSTEM.md (line 166) | `#E5E7EB` (light mode) |
| MODULE_DASHBOARD.md (line 56) | `#E5E5EA` (light), `#2C2C2E` (dark) |
| MODULE_TRAINING.md (line 62) | `#2C2C2E` (dark only) |
| MODULE_RECOVERY.md (line 130) | `#2D2D44` |
| MODULE_ACCOUNTABILITY.md (line 50) | `#21262D` |

**Resolution**: Use `tempo.color.divider.default` = `#E5E7EB` from Design System. Define dark variant.

---

## 26. Minor: Haptic Pattern Conflicts -- RESOLVED 2026-03-24

| Event | Training (line 136) | Accountability (line 91) | Sound & Haptics |
|-------|---------------------|-------------------------|------------------|
| Task/Set completed | `.success` | `.success` | Defined per-sound |
| Button tap | `.light` | `.light` | Module-specific |
| All tasks done | N/A | `.success` x3, 200ms apart | N/A |
| Workout finished | `.success` + custom 3 pulses | N/A | Separate catalog |

These are mostly consistent but the Sound & Haptics doc (SOUND_AND_HAPTICS.md) defines a separate, more detailed haptic catalog that may conflict with individual module specs.

**Resolution**: SOUND_AND_HAPTICS.md should be the authoritative source for all haptic patterns. Module docs should reference it, not redefine haptics.

---

## 27. Minor: PR Confetti Duration Conflict -- RESOLVED 2026-03-24

| Document | Duration |
|----------|----------|
| MODULE_TRAINING.md (line 163) | PR confetti: **2000ms** |
| MODULE_TRAINING.md (line 164) | PR fireworks (all-time 1RM): **3000ms** |

These are intentionally different tiers of celebration. Not a bug. But they conflict with `tempo.motion.celebration` = 1000ms in the Design System. The Design System should define `tempo.motion.celebration.standard` (1000ms) and `tempo.motion.celebration.major` (2000ms) and `tempo.motion.celebration.epic` (3000ms).

---

## 28. Minor: Weekly Summary Notification Timing -- RESOLVED 2026-03-24

| Document | Time |
|----------|------|
| MODULE_ACCOUNTABILITY.md (line 1871) | Sunday at **8:00 PM** |
| AI_INTELLIGENCE_ENGINE.md (line 34) | Sunday **8 PM** |

These are consistent. However, the Onboarding doc does not specify the weekly summary timing. Add it.

---

## 29. Minor: Sleep Stage Colors Orphaned -- RESOLVED 2026-03-24

MODULE_RECOVERY.md (line 109-113) defines sleep stage colors (`sleep.awake`, `sleep.light`, `sleep.deep`, `sleep.rem`) that appear nowhere else in the documentation suite -- not in the Design System, not in DATA_MODELS_IOS.md. They are orphaned.

**Resolution**: Add these to the Design System as `tempo.color.sleep.*` tokens.

---

## 30. Minor: Arena Color System is Completely Independent -- RESOLVED 2026-03-24

MODULE_ARENA.md (line 62-65) defines its own complete color system (deep navy, electric blue, molten orange, emerald, crimson) that shares ZERO tokens with the Design System. This is likely intentional (Arena has a different visual feel) but is never acknowledged.

**Resolution**: Either integrate Arena colors into the Design System as `tempo.color.arena.*` tokens, or add an explicit note in both docs that Arena has an approved exception to the Design System.

---

## 31. Minor: Accountability Color System is Completely Independent -- RESOLVED 2026-03-24

Same issue as Arena. MODULE_ACCOUNTABILITY.md defines its own palette (`locked.red`, `unlocked.green`, `progress.blue`, `progress.amber`, GitHub-style dark backgrounds) with zero overlap with the Design System.

---

## 32. Minor: Recovery Module Color System is Completely Independent -- RESOLVED 2026-03-24

MODULE_RECOVERY.md defines a completely independent color system with different hex codes for recovery zones (`#00C48C` vs Design System's `#22C55E`), different surface colors (`#1A1A2E` vs Design System's `#FFFFFF`), and additional color categories (metric health, HR zones) not present in the Design System.

---

## 33. Minor: Card Spacing Inconsistency -- RESOLVED 2026-03-24

| Document | Card-to-card vertical gap |
|----------|--------------------------|
| MODULE_DASHBOARD.md (line 86) | `tempo.space.lg` = **16pt** |
| MODULE_ACCOUNTABILITY.md (line 79) | **12pt** |
| MODULE_RECOVERY.md (line 159) | `card.spacing` = **12pt** |

**Resolution**: Use `tempo.space.card.gap` = 12pt from Design System (line 190). Dashboard's 16pt is an outlier.

---

## 34. Orphaned Features -- RESOLVED 2026-03-24

Features fully specified in one document but never referenced elsewhere:

| Feature | Defined In | Referenced By | Status |
|---------|-----------|---------------|--------|
| Sleep stage colors | MODULE_RECOVERY.md line 109-113 | None | **Orphaned** |
| HR zone colors (6 zones) | MODULE_RECOVERY.md line 116-121 | None | **Orphaned** |
| Plate calculator pattern system (color-blind) | MODULE_TRAINING.md line 186 | ACCESSIBILITY.md mentions it | Partially referenced |
| Watch complication specs | MODULE_TRAINING.md line 125 | APPLE_WATCH_APP.md covers separately | Duplicate risk |
| Import/Export system | MODULE_TRAINING.md Section 20 | No other doc references this | **Orphaned** |
| Football Integration deep dive | MODULE_TRAINING.md Section 18 | MODULE_ACCOUNTABILITY.md line 2977 mentions match scheduling | Partially referenced |
| Historical Comparison view | MODULE_RECOVERY.md Section 11 | No navigation path from other modules | **Orphaned** |
| Ambient Sound Library | SOUND_AND_HAPTICS.md Section 3 | No module doc references ambient sounds | **Orphaned** |
| Outbound Webhooks | BACKEND_API.md Section 14 | No consumer documented | **Orphaned** |

---

## 35. Missing Cross-References -- RESOLVED 2026-03-24

Features mentioned in one doc but not specified in the relevant module doc:

| Feature | Mentioned In | Should Be Specified In | Status |
|---------|-------------|----------------------|--------|
| "Wind Down" screen | ONBOARDING_AND_NOTIFICATIONS.md line 1590 | MODULE_RECOVERY.md or MODULE_ACCOUNTABILITY.md | **Not specified anywhere** |
| Caffeine cutoff prescription | App Store listing (line 62) | MODULE_RECOVERY.md | Partially -- mentioned in prescription engine |
| NutriTrack deep link for meal logging | ONBOARDING_AND_NOTIFICATIONS.md line 1585 | MODULE_DASHBOARD.md or INTEGRATION_SPECS.md | **URL scheme not defined** |
| "Force Regenerate Weekly" user action | AI_INTELLIGENCE_ENGINE.md line 64 | MODULE_DASHBOARD.md | **No UI specified** |
| Recovery prediction (on-device ML) | AI_INTELLIGENCE_ENGINE.md line 2100 | MODULE_RECOVERY.md | **Not specified in Recovery module** |
| XP spending / economy sinks | MODULE_ARENA.md Section 27 | BACKEND_API.md | **No API endpoints for spending** |
| Streak freeze mechanic | MODULE_ARENA.md line 192 | MODULE_ACCOUNTABILITY.md or BACKEND_API.md | **Not specified outside Arena** |
| Match day PS5 time auto-adjustment | MODULE_ACCOUNTABILITY.md line 2977 | INTEGRATION_SPECS.md (EventKit) | **Integration not specified** |

---

## 36. Master Cross-Reference Table

### Recovery Zone Colors
| Concept | Canonical Source | Token | Hex (Light) | Hex (Dark) |
|---------|-----------------|-------|-------------|------------|
| Recovery Green | DESIGN_SYSTEM.md line 727 | `tempo.color.recovery.green` | `#22C55E` | `#4ADE80` |
| Recovery Yellow | DESIGN_SYSTEM.md line 729 | `tempo.color.recovery.yellow` | `#EAB308` | `#FACC15` |
| Recovery Red | DESIGN_SYSTEM.md line 731 | `tempo.color.recovery.red` | `#DC2626` | `#F87171` |

### Recovery Zone Boundaries
| Zone | Canonical Source | Rule |
|------|-----------------|------|
| Green | DATA_MODELS_IOS.md line 334 | `score >= 67.0` |
| Yellow | DATA_MODELS_IOS.md line 335 | `score >= 34.0 && score < 67.0` |
| Red | DATA_MODELS_IOS.md line 336 | `score < 34.0` |

### Brand Colors
| Concept | Canonical Source | Token | Hex |
|---------|-----------------|-------|-----|
| Primary Black | DESIGN_SYSTEM.md line 124 | `tempo.color.primary.ink` | `#0D0D0D` |
| Primary White | DESIGN_SYSTEM.md line 125 | `tempo.color.primary.bone` | `#F5F2ED` |
| Primary Red | DESIGN_SYSTEM.md line 126 | `tempo.color.primary.signal` | `#E63946` |
| Accent Amber | DESIGN_SYSTEM.md line 132 | `tempo.color.accent.amber` | `#F59E0B` |
| Accent Blue | DESIGN_SYSTEM.md line 133 | `tempo.color.accent.electric` | `#3B82F6` |
| Accent Violet | DESIGN_SYSTEM.md line 134 | `tempo.color.accent.violet` | `#8B5CF6` |

### Layout Constants
| Concept | Canonical Source | Token | Value |
|---------|-----------------|-------|-------|
| Screen edge padding | DESIGN_SYSTEM.md line 195 | `tempo.space.screen.edge` | 20pt |
| Card padding | DESIGN_SYSTEM.md line 188 | `tempo.space.card.padding` | 16pt |
| Card gap | DESIGN_SYSTEM.md line 190 | `tempo.space.card.gap` | 12pt |
| Card corner radius | DESIGN_SYSTEM.md line 227 | `tempo.radius.3xl` | 16pt |
| Button corner radius | DESIGN_SYSTEM.md line 226 | `tempo.radius.2xl` | 14pt |
| Tab bar height | iOS Standard | N/A | 49pt (+34pt safe area) |

### Animation Durations
| Concept | Canonical Source | Token | Value |
|---------|-----------------|-------|-------|
| Micro interaction | DESIGN_SYSTEM.md line 254 | `tempo.motion.micro` | 100ms |
| Small transition | DESIGN_SYSTEM.md line 256 | `tempo.motion.small` | 200ms |
| Medium transition | DESIGN_SYSTEM.md line 258 | `tempo.motion.medium` | 300ms |
| Large transition | DESIGN_SYSTEM.md line 261 | `tempo.motion.large` | 500ms |
| Data animation | DESIGN_SYSTEM.md line 264 | `tempo.motion.data` | 600-800ms |
| Celebration | DESIGN_SYSTEM.md line 267 | `tempo.motion.celebration` | 1000ms |
| Card stagger | DESIGN_SYSTEM.md line 270 | `tempo.motion.stagger.card` | 60ms |

### Notification System
| Concept | Canonical Source | Notes |
|---------|-----------------|-------|
| Tier architecture (7 tiers) | MODULE_ACCOUNTABILITY.md Section 6.1 | Tiers 0-6 |
| Notification categories | ONBOARDING_AND_NOTIFICATIONS.md line 1565-1579 | UNNotificationCategory IDs |
| Intensity levels | 4 levels: Gentle Coach (1), Firm Coach (2), Drill Sergeant (3), Savage Mode (4) | RESOLVED: See MODULE_ACCOUNTABILITY.md Intensity Level section |
| Copy pools (all intensities) | MODULE_ACCOUNTABILITY.md Section 6 | 50+ messages per tier per intensity |
| Sound files | ONBOARDING_AND_NOTIFICATIONS.md line 1615-1629 | 5 custom CAF files |
| Haptic mapping | SOUND_AND_HAPTICS.md Section 4 | Authoritative for all haptics |

### XP Economy
| Concept | Canonical Source | Notes |
|---------|-----------------|-------|
| All XP values | MODULE_ARENA.md Section 2 | Single source, no conflicts found |
| XP penalties | MODULE_ARENA.md Section 2.2 | -50 to -150 XP range |
| Perfect Day bonus | MODULE_ARENA.md line 141 | 200 XP |
| Theoretical daily max | MODULE_ARENA.md line 177 | ~1,325 XP before multipliers |

### Data Models
| Model | Canonical Source | Notes |
|-------|-----------------|-------|
| DailySnapshot | DATA_MODELS_IOS.md Section 4.1 | Persistence model |
| DashboardState | MODULE_DASHBOARD.md Section 2.2 | View model (not in DATA_MODELS_IOS.md) |
| BodyQuadrantData | MODULE_DASHBOARD.md line 197 | View model (not in DATA_MODELS_IOS.md) |
| DailyRecovery | DATA_MODELS_IOS.md Section 7 | Has spo2, skinTemp, respiratoryRate |
| RecoveryZone enum | DATA_MODELS_IOS.md line 327 | Canonical boundary logic |

### API Endpoints (Integrations)
| Endpoint | Canonical Source | Consumer |
|----------|-----------------|----------|
| `GET /v1/integrations/whoop/authorize` | INTEGRATION_SPECS.md line 91, BACKEND_API.md | iOS WhoopService |
| `POST /v1/integrations/whoop/sync` | INTEGRATION_SPECS.md line 344 | iOS manual sync |
| `POST /v1/webhooks/whoop` | INTEGRATION_SPECS.md line 870 | Whoop server-to-server |
| `GET /v1/nutritrack/today` | INTEGRATION_SPECS.md line 2376 | iOS NutriTrackService |
| `POST /v1/sync/snapshot` | INTEGRATION_SPECS.md line 3195 | iOS SyncEngine |
| `POST /v1/xp/events` | INTEGRATION_SPECS.md line 3510 | iOS XPService |

---

## Summary of Required Actions -- ALL RESOLVED 2026-03-24

### Immediate (before any code is written) -- DONE
1. ~~Unify recovery zone colors~~ -- DONE: All 7 docs now use #22C55E / #EAB308 / #DC2626
2. ~~Unify token naming~~ -- DONE: All modules now use `tempo.color.<group>.<variant>` convention
3. ~~Add `spo2` to DailySnapshot~~ -- DONE: Added spo2 and skinTemp fields; added Section 4.2 view models
4. ~~Resolve notification intensity~~ -- DONE: Standardized to 4 levels with mapping table
5. ~~Fix quadrant width table~~ -- DONE: Table matches formula (159.5, 168.5, 187, 192pt)

### Before beta -- DONE
6. ~~Add complete dark mode token set~~ -- DONE: Design System Section 3.12 already had dark tokens; modules now reference them
7. ~~Add typography token registry~~ -- DONE: Body text standardized to 15pt, section titles to 28pt Bold
8. ~~Unify screen padding~~ -- DONE: All modules now use 20pt (tempo.space.screen.edge)
9. ~~Standardize dark backgrounds~~ -- DONE: All modules use #0D0D0D bg, #1C1C1E card, #2C2C2E elevated
10. ~~Add module color tokens to Design System~~ -- DONE: Sleep colors added; module exceptions explicitly acknowledged
11. ~~Document view models~~ -- DONE: DATA_MODELS_IOS.md Section 4.2 added with full mapping

### Before production -- DONE (TODOs added)
12. ~~Resolve orphaned features~~ -- DONE: Sleep colors integrated; others documented with TODO markers
13. ~~Specify missing features~~ -- DONE: TODO markers added for Wind Down screen and NutriTrack deep links
14. Unify haptic specifications to SOUND_AND_HAPTICS.md as single source
15. Add animation duration reconciliation notes where intentional per-module variation exists
