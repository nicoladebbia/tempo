---
paths:
  - "Tempo/**/*.swift"
  - "Tempo/**/*.xcassets/**"
  - "Tempo/project.yml"
---

# Tempo iOS — Swift/SwiftUI rules

## Hot Reload (Inject) — what auto-applies vs what needs ⌘R (IMPORTANT)
Tempo has Inject hot-reload wired (dev-only; `@ObserveInjection`+`.enableInjection()` in `ContentView.swift`, `-interposable` Debug linker flag in `project.yml`). When the InjectionIII app is running and watching `Tempo/`, **saving a `.swift` file injects it into the running simulator in ~1s — including saves made by your Edit/Write tools.** It only works for a narrow class of change, and you MUST tell Nicola which case applies after every UI edit:

- **Injects live (no rebuild):** changes confined to a SwiftUI view `body` — colors, padding, fonts, text, spacing, conditional layout, card↔list swaps. Tell Nicola: "saved — should hot-reload in the sim."
- **Needs ⌘R rebuild (Inject will NOT catch it):** new/changed stored properties or `@State`, new types, changed function signatures, new files, `@Model`/SwiftData schema changes, anything in services/view-models structure, or anything touching app launch / data loading / navigation state. Tell Nicola explicitly: "this needs a ⌘R — Inject won't pick it up."
- **Multi-file edits:** after editing 2+ files in one change (e.g. a view AND its view model), do NOT trust the partial injection — tell Nicola to ⌘R once. Inject may inject one file mid-edit and show a broken intermediate state.
- **Never call a hot-injected screen "verified."** Inject reloads view code but does not restart the app or re-run launch logic. Only a full ⌘R relaunch exercises the real path. For anything structural, state "necessary but not sufficient — needs a clean ⌘R to verify".

## Stale Build on Device — CHECK FIRST when "it's still broken" (CRITICAL)
Nicola runs Tempo on his **physical iPhone** ("iPhone di Nicola"), not the simulator. `xcodebuild -destination 'platform=iOS Simulator'` (or `generic/platform=iOS`) **compiles but installs NOTHING on the device** — the phone keeps running whatever Xcode last ⌘R'd. So a "still broken / my change isn't showing / all the old problems persist" report is, by default, a **stale binary**, NOT a code bug. This trap cost ~half a session (2026-05-31): repeated code-spelunking on a device running pre-change code.

Before diagnosing any "still broken" / "didn't work" / "nothing changed" report:
1. **Confirm the build is fresh on the device.** The deterministic tell: a DEBUG `print` you added produces **zero log lines** when it should fire (e.g. zero `[Workout]` lines after starting a workout) → the instrumented code is NOT on the device → stale build. Stop; tell Nicola to ⌘R (device destination); do not touch code.
2. **CLI builds prove compilation ONLY.** `xcodebuild ... build` succeeding ≠ the change is on the phone ≠ runtime-verified. NEVER write "verified"/"fixed"/"working" off a CLI build — only off an on-device observation after a confirmed fresh ⌘R.
3. `xcrun devicectl list devices` reveals a connected physical device; if one is present, assume device-not-sim is the run target unless Nicola says otherwise.

## Never attach `.task`/`.onAppear` to a `Group` whose first branch is `EmptyView()`
`Group` forwards modifiers to its *current* child; at first render that child is the `EmptyView()` branch, and `.task`/`.onAppear` on `EmptyView` is a **no-op** — so a self-loading view that gates on its own loaded state (`Group { if let x { card } else { EmptyView() } }.task { load() }`) **never loads**: a permanent, silent, compiles-clean no-show. **Root any self-loading card's `body` in an always-present concrete container that hosts the lifecycle modifier** — `VStack(spacing: 0) { if let x { card } }.task { load() }`. Diagnosis: when a view that should self-populate renders nothing, **diff a working sibling in the same parent FIRST** (e.g. `MorningCheckInCard` was fixed by diffing `RecoveryAIInsightView` — same VStack, rendered fine — not by theorizing). Paid lesson: D1 `MorningCheckInCard`, 2026-06-09.

## One asset catalog per target
Tempo target = `Tempo/Tempo/Assets.xcassets` only. New colors go in `Tempo/Tempo/Assets.xcassets/Colors/`. Multiple `.xcassets` in the same target generate duplicate symbols in `GeneratedAssetSymbols.swift`. Every catalog folder needs a `Contents.json` at its root.
