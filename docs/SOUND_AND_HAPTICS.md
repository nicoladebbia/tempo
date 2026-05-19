# Tempo — Sound Design & Haptics Specification

> **Module**: Sound & Haptics (cross-cutting)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

> **One-line reality check:** Haptics ship and work (UIKit generators only). **Sound does not ship at all** — `SoundManager` and a 21-case `TempoSound` enum exist, but zero audio assets are bundled, so every `play()` is a silent no-op. There is no Core Haptics / AHAP layer, no ambient library, and no functional sound settings toggle.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Utilities/Helpers/SoundManager.swift` — `SoundManager`, `TempoSound`
- `Tempo/Tempo/Utilities/Helpers/HapticManager.swift` — `HapticManager`
- `Tempo/Tempo/Services/Notifications/NotificationService.swift` — `sound(for:)`
- `Tempo/Tempo/Services/Notifications/AccountabilityEscalationEngine.swift`
- `Tempo/Tempo/Models/User/UserSettings.swift` — `soundEnabled`
- `Tempo/Tempo/Views/Accountability/FocusTimerView.swift` — ambient placeholder
- `Tempo/Tempo/Resources/Sounds/` — contains only `.gitkeep` (no audio)

---

## Table of Contents

1. [Audio Identity](#1-audio-identity)
2. [Complete Sound Effect Catalog](#2-complete-sound-effect-catalog)
3. [Ambient Sound Library](#3-ambient-sound-library)
4. [Complete Haptic Catalog](#4-complete-haptic-catalog)
5. [Core Haptics Patterns (AHAP Files)](#5-core-haptics-patterns-ahap-files)
6. [Audio-Haptic Synchronization](#6-audio-haptic-synchronization)
7. [Sound Settings](#7-sound-settings)
8. [Audio File Specifications](#8-audio-file-specifications)

---

## 1. Audio Identity

> **Status: NOT IMPLEMENTED — the sonic brand is aspirational only.** No audio assets ship, so the "military-industrial precision" palette, the transient/tonal/resonance layer model, the pitch language, and the reference-app direction exist only as design intent. None of it is observable at runtime. The original §1.1–§1.4 brand spec is preserved as a future audio-production brief, not an as-built description.

### 1.5 Master Volume Strategy

The only real audio-session behavior is in `SoundManager`:

- `configureAudioSession()` sets `AVAudioSession` category `.ambient` with `.mixWithOthers` and activates the session.
- `playImportant(_:)` temporarily switches to `.playback` + `.duckOthers`, plays at volume `1.0`, then restores `.ambient` after 2s (via `DispatchQueue.main.asyncAfter`).
- Per-sound default volumes exist on `TempoSound.defaultVolume` (e.g. `workoutRestTick` 0.5, `systemTabSwitch` 0.3, `workoutComplete`/`workoutPRachieved` 1.0).

> **Divergence from original spec:** The session strategy and per-sound volume ladder are coded correctly but **drive no audio** — there are no files to play. The spec's full per-channel volume mixing table is not implemented; only the `.ambient`/`.playback` duck-and-restore logic above exists.

---

## 2. Complete Sound Effect Catalog

`SoundManager.play(_:)` looks up `Bundle.main.url(forResource: sound.rawValue, withExtension: "caf")` (then `wav`) and **silently returns when the lookup fails**. `Tempo/Tempo/Resources/Sounds/` contains only `.gitkeep`; a project-wide search finds zero `.caf`/`.wav`/`.m4a` outside build artifacts.

> **Status: NOT FUNCTIONAL — code exists, audio assets do not.** Every sound playback in the app is a no-op. The catalog below is the *enum surface that exists in code*; none of it produces sound.

The shipped `TempoSound` enum has 20 cases (raw values are the file basenames the loader expects):

| Group | Cases (rawValue) |
|-------|------------------|
| Workout | `workoutSetComplete` (`tempo_workout_set_complete`), `workoutExerciseComplete`, `workoutStart`, `workoutComplete`, `workoutRestTick`, `workoutRestDone`, `workoutPRachieved` (`tempo_workout_pr_achieved`), `workoutWeightAdjust` |
| Timer | `timerStart`, `timerTick`, `timerComplete`, `timerBreakStart` |
| Arena | `arenaXPGain` (`tempo_arena_xp_gain`), `arenaLevelUp`, `arenaAchievement`, `arenaStreakFire`, `arenaChallengeWon` |
| System | `systemTabSwitch`, `systemNNComplete`, `systemLeisureUnlock` |

> **Divergence from original spec:** The original §2 catalog enumerated ~40 named sounds across workout/timer/arena/system. Code defines only these 20, and some raw values were renamed (e.g. `tempo_arena_xp_gain` vs the spec's `tempo_arena_xp_earn`). The full original catalog table is **NOT IMPLEMENTED** and is retained in version control history if needed for audio production.

### 2.4 Notification Sounds

> **Status: NOT IMPLEMENTED — referenced filenames do not exist.** `NotificationService.sound(for:)` and `AccountabilityEscalationEngine` build `UNNotificationSound(named:)` with `tempo_urgent.caf`, `tempo_final.caf`, `tempo_clear.caf`, and `tempo_bedtime.caf`. None of these files are in the bundle, so iOS silently falls back to the **default system notification sound**. The custom notification sound design from the original §2.4 is not delivered.

---

## 3. Ambient Sound Library

> **Status: NOT IMPLEMENTED.** No ambient `.m4a` loops ship and there is no ambient-track player. `FocusTimerView` renders an "Ambient" button explicitly marked as a placeholder with no playback wiring. The original §3 track catalog (rain, white noise, etc.) is entirely absent from code.

---

## 4. Complete Haptic Catalog

Haptics are **real and functional**, implemented in `HapticManager` (a `@MainActor enum` of static methods). All feedback uses UIKit generators only: `UIImpactFeedbackGenerator` (`light`/`medium`/`heavy`), `UINotificationFeedbackGenerator` (`success`/`warning`/`error`), and `UISelectionFeedbackGenerator`. Multi-pulse patterns are composed with `DispatchQueue.main.asyncAfter` delays.

### 4.1 Implemented Semantic Haptics

| Method | Pattern (as coded) |
|--------|--------------------|
| `setComplete()` | medium impact |
| `exerciseComplete()` | medium, then medium +0.15s |
| `workoutStart()` | heavy impact |
| `workoutComplete()` | success notification |
| `prAchieved()` | heavy, heavy +0.12s, success +0.24s |
| `restTick()` | light impact |
| `restDone()` | warning, then heavy +0.3s |
| `timerStart()` | medium impact |
| `timerComplete()` | success notification |
| `xpGain()` | light impact |
| `levelUp()` | success, then success +0.3s |
| `achievementUnlocked()` | success, then medium +0.15s |
| `nonNegotiableComplete()` | success notification |
| `leisureUnlocked()` | success, then success +0.2s |
| `streakFire()` | medium impact |

Plus primitives: `lightImpact()`/`mediumImpact()`/`heavyImpact()`, `success()`/`warning()`/`error()`, `selection()`. `HapticManager`/`SoundManager` are referenced from ~43 source files.

> **Divergence from original spec:** Semantic coverage broadly matches the original §4 intent, but every pattern is an approximation built from UIKit generator pulses with `asyncAfter` timing — **not** the bespoke Core Haptics curves the spec described. Exact intensities/sharpness/curves from the original §4 tables are not reproducible with this API and are NOT IMPLEMENTED.

---

## 5. Core Haptics Patterns (AHAP Files)

> **Status: NOT IMPLEMENTED.** There is no `CHHapticEngine` anywhere in the codebase and zero `.ahap` files ship. The original §5 patterns (`tempo_haptic_pr_celebration.ahap`, `level_up`, `unlock_leisure`, `workout_complete`, `critical_notification`, `rest_timer_done`) do not exist. The app uses only the documented UIKit-generator fallback path (see §4) for every haptic event.

---

## 6. Audio-Haptic Synchronization

> **Status: NOT IMPLEMENTED — synchronization is moot without audio.** Since no sounds play, there is no audio-haptic sync. Haptics fire standalone from their call sites. Reduce Motion is **not** consulted by `HapticManager` (haptics fire regardless). The original §6 sync timing table, latency budget, and audio-engine architecture are not built. Silent-mode behavior reduces to: haptics still fire; there is no sound to suppress.

---

## 7. Sound Settings

`UserSettings.soundEnabled` exists (defaults `true`, persisted, sent to backend as `sound_enabled`) and `NotificationSettingsView` exposes a toggle bound to it.

> **Divergence from original spec:** The toggle is **not wired to playback**. `SoundManager.setEnabled(_:)` exists but is **never called** from `soundEnabled` (no call site in code), so the setting has no runtime effect on sound — and there is no sound to gate anyway. There is no separate `hapticsEnabled` setting; haptics cannot be disabled in-app. The original §7 settings structure (granular per-category sound/haptic controls, custom notification sound registration UI, background mixing options) is NOT IMPLEMENTED beyond this single inert boolean.

---

## 8. Audio File Specifications

> **Status: NOT IMPLEMENTED.** No audio files ship, so format requirements, file-size budgets, the Xcode project organization layout, and the production pipeline from the original §8 are unrealized. `Tempo/Tempo/Resources/Sounds/` exists with only a `.gitkeep`. The original §8 spec stands as the production brief for if/when audio is added; `SoundManager` already expects `.caf` (preferred) then `.wav` at `Resources/Sounds/<rawValue>`.

> **Status: NOT IMPLEMENTED — runtime sound generation alternative.** The original §8.6 fallback (synthesizing tones at runtime instead of shipping files) is not implemented; `SoundManager` only loads bundled files via `AVAudioPlayer`.

---

## Appendix — As-Built Summary

| Layer | Status |
|-------|--------|
| Haptics (UIKit generators) | IMPLEMENTED — functional, ~15 semantic patterns |
| Audio-session strategy | IMPLEMENTED — logic correct, drives no audio |
| `TempoSound` enum + `SoundManager` | DIVERGED — code present, 20 cases, but non-functional (no assets) |
| Sound effect audio files | NOT IMPLEMENTED — zero assets |
| Notification sounds | NOT IMPLEMENTED — referenced `.caf` absent, default fallback |
| Ambient library | NOT IMPLEMENTED — placeholder button only |
| Core Haptics / AHAP | NOT IMPLEMENTED — no engine, no files |
| Audio-haptic sync | NOT IMPLEMENTED — no audio to sync |
| Sound settings | DIVERGED — inert toggle, `setEnabled` never called |
