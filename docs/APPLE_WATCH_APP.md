# Tempo — Apple Watch Companion App Specification

> **Module**: Apple Watch Companion (`TempoWatch`)
> **App**: Tempo — watchOS 10.0 companion to the iOS app
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS/watchOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

> **One-line reality check:** A real watchOS application target ships (`TempoWatch`, companion-bundled). It has 5 wired screens, WCSession connectivity, WatchKit haptics, and snapshot models. Complication **views + a `TimelineProvider` exist but are not registered as an actual complication** (no `WidgetBundle`/`@main` widget and no widget extension target). One screen file (`ArenaGlanceView`) exists but is not wired into the app.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/project.yml` — `TempoWatch` target
- `Tempo/TempoWatch/TempoWatchApp.swift` — `@main TempoWatchApp`
- `Tempo/TempoWatch/Views/*.swift` — screen views
- `Tempo/TempoWatch/Services/WatchConnectivityService.swift`, `WatchHapticService.swift`
- `Tempo/TempoWatch/Models/WatchSnapshot.swift`, `WatchWorkoutState.swift`, `WatchTimerState.swift`, `WatchQuickAction.swift`
- `Tempo/TempoWatch/Complications/TempoComplicationProvider.swift`, `ComplicationViews.swift`
- `Tempo/Tempo/Services/Integrations/PhoneWatchConnectivityService.swift` — phone side

---

## Table of Contents

1. [Watch App Strategy](#1-watch-app-strategy)
2. [Watch Complications](#2-watch-complications)
3. [Watch App Screens](#3-watch-app-screens)
4. [Haptics](#4-haptics)
5. [Watch-iPhone Communication](#5-watch-iphone-communication)
6. [Performance Targets](#6-performance-targets)
7. [Watch Notifications](#7-watch-notifications)
8. [Live Activities on Watch](#8-live-activities-on-watch)
9. [Screen Specifications](#9-screen-specifications)

---

## 1. Watch App Strategy

The companion-app architecture decision is **implemented**. `project.yml` defines target `TempoWatch`: `type: application`, `platform: watchOS`, `deploymentTarget watchOS 10.0`, Swift 6, `INFOPLIST_KEY_WKCompanionAppBundleIdentifier: app.tempo.Tempo`, bundle id `app.tempo.Tempo.watchkitapp`. Entry point is `@main struct TempoWatchApp` (a SwiftUI `App`).

> **Divergence from original spec:** Original §1.4 targeted watchOS specifics and §1.5 enumerated a project structure; the shipped target is watchOS **10.0** companion-bundled with the source layout `TempoWatch/{Views,Models,Services,Complications,Resources}`. The Watch app has **no HealthKit entitlement and no `HKWorkoutSession`** — it is a connectivity-driven remote/logger, not a standalone health tracker. The original "wrist-native workout tracking with on-watch heart rate" intent is NOT IMPLEMENTED.

---

## 2. Watch Complications

Partially implemented. `TempoComplicationProvider` is a WidgetKit `TimelineProvider` (`placeholder`/`getSnapshot`/`getTimeline`) over `TempoComplicationEntry`/`TempoComplicationData`. Three complication views exist in `ComplicationViews.swift`:

- `CircularComplicationView` (uses `AccessoryWidgetBackground()`) → accessory **Circular**
- `RectangularComplicationView` (recovery color mapping green/yellow/red) → accessory **Rectangular**
- `InlineComplicationView` → accessory **Inline**

> **Status: NOT IMPLEMENTED — complications are not registered.** There is **no `@main` widget, no `WidgetBundle`, no `StaticConfiguration`, and no watch widget-extension target** in `project.yml`. The provider + views exist but nothing wires them to a real complication surface, so no complication can actually be installed on a watch face from this code. The original §2.1–§2.4 data model, refresh strategy, and any families beyond the 3 accessory views above are NOT IMPLEMENTED.

> **Divergence from original spec:** Original §2.3 enumerated a broader family set (corner/other surfaces). Code provides only the 3 accessory views listed above, and even those are not registered (see above).

---

## 3. Watch App Screens

`TempoWatchApp` hosts a vertically-paging `TabView` (`.tabViewStyle(.verticalPage)`) with **5 wired screens**, all injected with the shared `WatchConnectivityService`:

| Order | View | Role |
|-------|------|------|
| 1 | `GlanceHomeView` | Glance/home summary |
| 2 | `WorkoutView` | Set/rep logging from wrist (primary use case) |
| 3 | `FocusTimerView` | Focus timer mirror |
| 4 | `QuickLogView` | Quick log actions |
| 5 | `RecoveryView` | Recovery readout |

`WorkoutView` logs reps × weight and sends actions over connectivity and runs a local rest `Timer.scheduledTimer`; it does **not** drive a HealthKit workout session.

> **Status: NOT IMPLEMENTED — Arena Glance screen not wired.** `TempoWatch/Views/ArenaGlanceView.swift` exists and defines `ArenaGlanceView`, but it is **not referenced anywhere** (absent from the `TabView` and any navigation). The original §3.7 Arena Glance screen is present as dead code only.

> **Divergence from original spec:** Original §3.1 specified `NavigationStack` + paging `TabView`; code uses a bare paging `TabView` with no `NavigationStack`. The per-screen layout/typography detail in original §3.2–§3.7 and §9 is far more granular than the actual minimal SwiftUI views; those exhaustive per-screen specs are NOT IMPLEMENTED as written and should be treated as design intent.

---

## 4. Haptics

Implemented as `enum WatchHapticService` using `WKInterfaceDevice.current().play(_:)`:

| Method | WatchKit haptic |
|--------|-----------------|
| `playSetComplete()` | `.success` |
| `playRestTimerEnd()` | `.notification` |
| `playFocusTimerEnd()` | `.directionUp` |
| `playWorkoutStart()` | `.start` |
| `playWorkoutEnd()` | `.stop` |
| `playNonNegotiableComplete()` | `.click` |
| `playError()` | `.failure` |

> **Divergence from original spec:** Original §4.1 defined custom haptic semantics; code maps each to a stock `WKHapticType`. No custom Core Haptics on watch. Functional, but the bespoke definitions are NOT IMPLEMENTED.

---

## 5. Watch-iPhone Communication

Implemented. `WatchConnectivityService` (watch side, `WCSessionDelegate`) activates `WCSession`, sends via `sendMessage` when `isReachable` else falls back to `transferUserInfo`. Phone side is `PhoneWatchConnectivityService`. Payload/state models: `WatchSnapshot` (`Codable`), `WatchWorkoutState`, `WatchTimerState`, `WatchQuickAction` (`String, Codable`) + `WatchActionPayload` (`Codable`).

> **Divergence from original spec:** The reachable/unreachable fallback and snapshot models match original §5.1/§5.3/§5.4 intent. The detailed payload schemas, bandwidth-optimization rules, and explicit sync protocol of original §5.2/§5.5 are not codified beyond the structs above; treat the verbose schemas as design intent (NOT IMPLEMENTED at that granularity).

---

## 6. Performance Targets

> **Status: NOT IMPLEMENTED — targets are not enforced in code.** Original §6 launch/view/memory/battery budgets are aspirational QA targets, not code artifacts. Nothing measures or asserts them.

---

## 7. Watch Notifications

> **Status: NOT IMPLEMENTED.** There is no watch-specific notification controller, routing layer, or actionable-notification scene in `TempoWatch`. watchOS forwards iPhone notifications by default; the original §7 custom routing/actionable-notification design is not built on the watch.

---

## 8. Live Activities on Watch

> **Status: NOT IMPLEMENTED.** No Live Activity / `ActivityKit` code exists in `TempoWatch`. The original §8 workout/focus Live Activities on watchOS are not delivered. (iOS-side Live Activity widgets, if any, live in the phone `TempoWidget` target and are out of scope for this watch doc.)

---

## 9. Screen Specifications

> **Status: NOT IMPLEMENTED at documented granularity.** Original §9 (display sizes, safe-area math, per-screen typography tables, button specs, OLED color rules, navigation patterns) is a pixel-level design spec. The shipped views are minimal SwiftUI built from shared tokens and SwiftUI defaults; none of the §9 numeric tables are encoded. Retain §9 as design reference only.

---

## Appendix — As-Built Summary

| Feature | Status |
|---------|--------|
| watchOS companion target | IMPLEMENTED — watchOS 10.0, companion-bundled |
| App entry + paging TabView | IMPLEMENTED — 5 wired screens |
| Arena Glance screen | NOT IMPLEMENTED — file exists, unwired (dead code) |
| WCSession connectivity + snapshot models | IMPLEMENTED |
| WatchKit haptics | IMPLEMENTED — stock `WKHapticType` mappings |
| Complication views + TimelineProvider | DIVERGED — code exists, 3 accessory views |
| Complication registration (widget bundle/target) | NOT IMPLEMENTED — nothing registers it |
| On-watch HealthKit / workout session | NOT IMPLEMENTED — no entitlement, connectivity-only |
| Watch notifications / Live Activities | NOT IMPLEMENTED |
| Performance / screen-spec numeric tables | NOT IMPLEMENTED — design intent only |
