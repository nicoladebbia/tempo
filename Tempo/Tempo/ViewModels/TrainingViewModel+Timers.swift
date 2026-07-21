//
// TrainingViewModel+Timers.swift
// Tempo
//
// Rest / warm-up / elapsed timers, audio cues, rest notifications, and the
// reset/rest-duration helpers, split out of TrainingViewModel.swift to keep
// that file under the SwiftLint length caps. Pure VM behavior — same
// instance members, hosted in an extension. (Members are internal rather
// than private so they remain reachable from the main file and vice versa.)
//

import AudioToolbox
import AVFoundation
import Foundation
import SwiftData
import UserNotifications

extension TrainingViewModel {
    // MARK: - Rest Timer

    // Per STATE_MACHINES.md Section 1 — Rest timer with haptic on completion

    static let restTimerNotificationID = "tempo.rest.timer"

    func startRestTimer(duration: TimeInterval, nextAction: RestNextAction) {
        stopRestTimer()
        restTimerTotal = duration
        restTimerRemaining = duration
        pendingRestAction = nextAction

        // Anchor to a wall-clock end instant. Every tick (and every foreground
        // re-sync) recomputes `restTimerRemaining` from this Date, so the timer
        // never freezes while the app is backgrounded.
        let end = Date().addingTimeInterval(duration)
        restEndDate = end
        // Arm the countdown cues: nothing has fired yet for this rest period.
        lastCuedSecond = Int(duration.rounded(.up)) + 1

        // Configure the audio session so voice/beep cues play (and duck music)
        // even when the screen is locked.
        Self.activateRestAudioSession()
        // Preload the countdown clips so playback at fire-time has no disk
        // latency (loading on the T-3 tick would reintroduce the lag we avoid).
        CueAudioPlayer.shared.preload([.tenSeconds, .three, .two, .one, .go])

        // Schedule a local notification so the user can lock their phone.
        scheduleRestTimerNotification(seconds: duration)

        restTimerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.tickRestTimer() {
                    // Reached zero — tear the timer down BEFORE advancing so a
                    // foreground event during the next set can't see a stale
                    // restEndDate/restTimerTask and fire advanceAfterRest a
                    // second time (which would silently skip that set).
                    self.stopRestTimer()
                    self.advanceAfterRest()
                    return
                }
            }
        }
    }

    /// Recomputes `restTimerRemaining` from the wall-clock anchor and fires any
    /// countdown cues that were crossed since the last tick. Returns `true` when
    /// the rest period has elapsed (caller should advance).
    @discardableResult
    func tickRestTimer() -> Bool {
        guard let end = restEndDate else {
            return false
        }
        let remaining = max(0, end.timeIntervalSinceNow)
        restTimerRemaining = remaining
        fireCuesIfNeeded(remaining: remaining)
        return remaining <= 0
    }

    /// Re-sync the rest timer after returning to the foreground. If the rest
    /// period already elapsed while backgrounded, advance immediately.
    func syncRestTimer() {
        guard restEndDate != nil, restTimerTask != nil else {
            return
        }
        if tickRestTimer() {
            stopRestTimer()
            advanceAfterRest()
        }
    }

    // MARK: - Guided Warm-Up Flow

    /// The move the user is currently on in the guided warm-up, if any.
    var currentWarmupMove: WarmupMove? {
        guard let moves = warmupRoutine?.moves, warmupMoveIndex < moves.count else {
            return nil
        }
        return moves[warmupMoveIndex]
    }

    /// Start (or arm) the timer for the current warm-up move. Timed moves run a
    /// Date-anchored countdown that auto-advances and survives backgrounding;
    /// rep-based moves run no timer (the user taps Next). Announces the move by
    /// voice so the user knows what to do without looking.
    func startWarmupMoveTimerForCurrent() {
        stopWarmupMoveTimer()
        guard let move = currentWarmupMove else {
            return
        }
        // Audio session is activated once in startWorkout for the whole warm-up.
        // The voice is intentionally SILENT on move announcements — Harry only
        // speaks the rest-timer countdown (T-10 warning + 3-2-1-go). Move names
        // are shown on screen, not spoken.

        guard let seconds = move.durationSeconds, seconds > 0 else {
            // Rep-based move — no countdown, advance is manual.
            warmupMoveRemaining = 0
            warmupMoveEndDate = nil
            return
        }
        warmupMoveRemaining = TimeInterval(seconds)
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        warmupMoveEndDate = end
        warmupMoveTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.tickWarmupMove() {
                    // Tear down BEFORE advancing so a scenePhase resync can't
                    // double-advance the same move (mirrors the rest-timer fix).
                    self.stopWarmupMoveTimer()
                    self.advanceWarmupMove()
                    return
                }
            }
        }
    }

    @discardableResult
    func tickWarmupMove() -> Bool {
        guard let end = warmupMoveEndDate else {
            return false
        }
        warmupMoveRemaining = max(0, end.timeIntervalSinceNow)
        return warmupMoveRemaining <= 0
    }

    /// Re-sync the warm-up move timer after returning to the foreground.
    /// A nil `warmupMoveTask` means the current move is rep-based (no timer was
    /// created), so there is nothing to re-sync — this no-op is correct, not a
    /// missed paused/crashed timer.
    func syncWarmupTimer() {
        guard warmupMoveEndDate != nil, warmupMoveTask != nil else {
            return
        }
        if tickWarmupMove() {
            stopWarmupMoveTimer()
            advanceWarmupMove()
        }
    }

    /// Advance to the next warm-up move, or into the working sets when the
    /// routine is finished. Idempotent: guarded on still being in .warmup.
    func advanceWarmupMove() {
        guard case .warmup = sessionState else {
            return
        }
        let moveCount = warmupRoutine?.moves.count ?? 0
        let next = warmupMoveIndex + 1
        if next < moveCount {
            warmupMoveIndex = next
            startWarmupMoveTimerForCurrent()
        } else {
            // Routine done — fall through to the ramp-set preview / working sets.
            stopWarmupMoveTimer()
            // Stay in .warmup so the ramp preview + "Start Working Sets" shows;
            // the view switches to the ramp preview once moves are exhausted.
            warmupMoveIndex = moveCount
        }
    }

    /// Skip the current warm-up move immediately.
    func skipWarmupMove() {
        stopWarmupMoveTimer()
        advanceWarmupMove()
    }

    func stopWarmupMoveTimer() {
        warmupMoveTask?.cancel()
        warmupMoveTask = nil
        warmupMoveRemaining = 0
        warmupMoveEndDate = nil
    }

    // MARK: Rest Audio Cues
    //
    // Voice cues are played by CueAudioPlayer (premium pre-rendered clips for
    // the closed vocabulary; Apple-speech fallback for dynamic exercise names).
    // This VM owns only the audio-session activation and the system beep.

    /// Configure the shared audio session so cues are audible and DUCK (not stop)
    /// any music the user is playing, including when the screen is locked.
    static func activateRestAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .duckOthers lowers (not stops) the user's music while a cue plays.
        // It is mutually exclusive with .mixWithOthers, so we use it alone.
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? session.setActive(true, options: [])
    }

    /// Release the audio session so the user's music returns to full volume.
    static func deactivateRestAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static func playBeep() {
        AudioServicesPlaySystemSound(1057)
    }

    /// Fire countdown cues exactly once as the remaining time crosses each
    /// threshold. Driven from the wall-clock tick, so cues still fire on the
    /// correct second after the app returns from the background.
    func fireCuesIfNeeded(remaining: TimeInterval) {
        // Only consider whole-second thresholds we have not already cued.
        let current = Int(remaining.rounded(.up))
        guard current < lastCuedSecond else {
            return
        }
        defer { lastCuedSecond = current }

        let target = max(current, 0)
        // Normal 0.2s ticks cross one threshold at a time. If many thresholds
        // were crossed at once (the app was backgrounded), DON'T replay them as
        // a misleading "ten… three… two" burst — fire only the single most
        // urgent cue for where we actually are now.
        if lastCuedSecond - 1 - target > 1 {
            cue(for: target)
            return
        }
        for second in stride(from: lastCuedSecond - 1, through: target, by: -1) {
            cue(for: second)
        }
    }

    func cue(for second: Int) {
        switch second {
        case 11:
            // Premium clip path: "Almost time... ten seconds, get set." is ~3.3s
            // with "ten seconds" landing ~1.3s in, so firing at T-11 puts the
            // words "ten seconds" right at the 10s mark. Clip plays in ms.
            if CueAudioPlayer.shared.hasClip(.tenSeconds) {
                CueAudioPlayer.shared.play(.tenSeconds)
            }
        case 12:
            // Apple-speech fallback only (no clip): speech needs ~2s spin-up, so
            // fire at T-12 with a beep.
            if !CueAudioPlayer.shared.hasClip(.tenSeconds) {
                Self.playBeep()
                CueAudioPlayer.shared.play(.tenSeconds)
            }
        case 3:
            CueAudioPlayer.shared.play(.three)
        case 2:
            CueAudioPlayer.shared.play(.two)
        case 1:
            CueAudioPlayer.shared.play(.one)
        case 0:
            // Countdown only: "Go". Exercise name is shown on the next screen,
            // not spoken (voice is scoped to the countdown). Haptic at T-0 is
            // owned by advanceAfterRest to avoid a double buzz.
            CueAudioPlayer.shared.play(.go)
        default:
            break
        }
    }

    func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restTimerRemaining = 0
        restEndDate = nil
        lastCuedSecond = Int.max
        cancelRestTimerNotification()
        Self.deactivateRestAudioSession()
    }

    // MARK: - Rest Timer Notifications

    /// IDs for the multi-cue rest notifications (T-10, T-3, T-2, T-1, T-0).
    static let restCueNotificationIDs = [
        "tempo.rest.cue.10",
        "tempo.rest.cue.3",
        "tempo.rest.cue.2",
        "tempo.rest.cue.1",
        "tempo.rest.timer", // T-0 — keeps the original ID
    ]

    /// Schedule notification SOUNDS at each countdown beat so the cues are
    /// audible through earphones even with the phone LOCKED / in a pocket —
    /// the app's in-process AVSpeechSynthesizer cues only fire while the app is
    /// foregrounded (iOS suspends the timer Task on lock). These notifications
    /// are the locked-phone path; the in-app voice is the screen-on path.
    func scheduleRestTimerNotification(seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.restCueNotificationIDs)

        // (offsetFromEnd, id, title, body) — fire each at `seconds - offset`.
        let cues: [(Double, String, String, String)] = [
            (10, "tempo.rest.cue.10", "10 seconds", "Get ready — 10 seconds left."),
            (3, "tempo.rest.cue.3", "3", "Rest ending…"),
            (2, "tempo.rest.cue.2", "2", "Rest ending…"),
            (1, "tempo.rest.cue.1", "1", "Rest ending…"),
            (0, Self.restTimerNotificationID, "Rest Over", "Time to hit your next set."),
        ]

        for (offset, id, title, body) in cues {
            let fireAt = seconds - offset
            // Skip cues whose fire time is in the past (short rests have no T-10).
            guard fireAt >= 1 || offset == 0 else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireAt),
                repeats: false
            )
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
        }
    }

    func cancelRestTimerNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.restCueNotificationIDs)
    }

    // MARK: - Elapsed Timer

    func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else {
                    return
                }
                if let start = workoutStartTime {
                    elapsedSeconds = Date().timeIntervalSince(start) - totalPauseDuration
                }
            }
        }
    }

    func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    // MARK: - Private Helpers

    func resetState() {
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = nil
        elapsedSeconds = 0
        totalPauseDuration = 0
        detectedPRs = []
        warmupRoutine = nil
        warmupMoveIndex = 0
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
    }

    func restDuration(for exercise: PlannedExercise) -> TimeInterval {
        // Per MODULE_TRAINING.md Section 15.6 — Rest between sets.
        guard let ex = exercise.exercise else {
            return TimeInterval(defaultRestSeconds)
        }

        // Per-exercise custom rest wins, verbatim — the conditioning-debt
        // multiplier below applies ONLY to the global default, never to a value
        // the user set explicitly on this exercise.
        if let preferred = ex.preferredRestSeconds {
            return TimeInterval(preferred)
        }

        // Global default (user-set in Training settings), lengthened by
        // conditioning debt: when recent sessions on this exercise repeatedly
        // gassed the user, the engine adds +25% so the next set isn't
        // under-recovered. 1.0 when there's no breath signal.
        let base = TimeInterval(defaultRestSeconds)
        let multiplier = trainingEngine.restMultiplier(history: ex.history ?? [])
        return base * multiplier
    }
}
