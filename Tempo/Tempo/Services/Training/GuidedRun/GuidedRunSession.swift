//
// GuidedRunSession.swift
// Tempo
//
// Guided run mode — the live coach's state machine: idle -> countdown
// (3-2-1) -> work -> rest -> ... -> finished, plus paused and ended early.
// Every timer is DATE-based off an injectable `GuidedRunClock` — `tick()`
// re-derives elapsed/remaining from stored `Date`s on every call rather than
// counting calls, so backgrounding/screen-lock/re-foregrounding never drifts
// and a fake clock can jump straight to any point for tests
// (GuidedRunSessionTests).
//
// Pure Swift + Foundation only — no AVFoundation/UIKit/CoreLocation. Cues
// are reported via `cueHandler`; live GPS distance is fed in from the
// outside (`markDone(liveDistanceMeters:)`) rather than owned here, so the
// engine stays trivially testable.
//

import Foundation

// MARK: - GuidedRunPhase

enum GuidedRunPhase: Equatable {
    case idle
    case countdown(secondsRemaining: Int)
    case work(stepIndex: Int)
    case rest(stepIndex: Int)
    case finished
    case endedEarly
}

// MARK: - GuidedRunSession

@MainActor
@Observable
final class GuidedRunSession {
    private static let countdownSeconds = 3

    /// Mutable working copy of the plan's steps — "add a rep" inserts into
    /// this, never into the immutable `plan`.
    private(set) var steps: [GuidedRunStep]
    let plan: GuidedRunPlan

    private let clock: GuidedRunClock
    var cueHandler: (GuidedRunCue) -> Void = { _ in }

    private(set) var phase: GuidedRunPhase = .idle
    private(set) var isPaused = false
    private(set) var stepIndex = 0
    private(set) var results: [UUID: GuidedRunBlockRecord] = [:]

    /// Recomputed every `tick()` — stored (not computed-on-read) so
    /// `@Observable` tracks the dependency and SwiftUI re-renders as the
    /// clock advances.
    private(set) var elapsedInCurrentStep: TimeInterval = 0
    /// nil when the current step has no countdown (a timed rep counts UP
    /// with no auto-end; a round has neither).
    private(set) var remainingInCurrentStep: TimeInterval?

    private var stepStartDate: Date?
    private var pausedAt: Date?
    private var accumulatedPause: TimeInterval = 0
    private var countdownStartDate: Date?
    private var lastFiredCountdownValue: Int?
    /// Live GPS distance for the CURRENT continuous-distance step, fed in
    /// by the view (GuidedRunLocationTracker) — the engine never talks to
    /// CoreLocation itself. Drives the halfway cue for a distance target;
    /// `markDone(liveDistanceMeters:)` is what actually gets logged.
    private var currentLiveDistanceMeters: Double = 0
    private var firedHalfwayForCurrentStep = false
    private var firedTenSecondsForCurrentStep = false

    init(plan: GuidedRunPlan, clock: GuidedRunClock = SystemClock()) {
        self.plan = plan
        steps = plan.steps
        self.clock = clock
    }

    // MARK: - Lifecycle

    func start() {
        guard phase == .idle, !steps.isEmpty else {
            if steps.isEmpty {
                phase = .finished
            }
            return
        }
        countdownStartDate = clock.now()
        lastFiredCountdownValue = nil
        phase = .countdown(secondsRemaining: Self.countdownSeconds)
    }

    /// Call periodically (a view-driven timer, ~4-5x/sec) to re-derive
    /// state from the clock. Never advances by counting calls — safe to
    /// call at any cadence, including after a long gap (background/lock).
    func tick() {
        switch phase {
        case .idle,
             .finished,
             .endedEarly:
            return
        case .countdown:
            tickCountdown()
        case let .work(index):
            tickWork(stepIndex: index)
        case let .rest(index):
            tickRest(stepIndex: index)
        }
    }

    func pause() {
        guard !isPaused, phase != .idle, phase != .finished, phase != .endedEarly else {
            return
        }
        isPaused = true
        pausedAt = clock.now()
    }

    func resume() {
        guard isPaused, let pausedAt else {
            return
        }
        accumulatedPause += clock.now().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        isPaused = false
    }

    /// Ends the session immediately, keeping whatever was already recorded.
    func endEarly() {
        guard phase != .finished, phase != .endedEarly else {
            return
        }
        phase = .endedEarly
    }

    /// Live GPS distance update for the current continuous-distance step —
    /// a no-op outside that shape. Called from the view on every location
    /// fix; does not itself record anything (markDone does that).
    func updateLiveDistance(_ meters: Double) {
        currentLiveDistanceMeters = meters
    }

    // MARK: - Athlete actions

    /// Completes the current WORK step, recording its result, and advances.
    /// A no-op outside a work phase.
    func markDone(liveDistanceMeters: Double? = nil) {
        guard case .work = phase, !isPaused, steps.indices.contains(stepIndex) else {
            return
        }
        record(step: steps[stepIndex], elapsed: currentElapsed(), liveDistanceMeters: liveDistanceMeters)
        advance()
    }

    /// Skips the current step (work or rest) without recording a value.
    func skipRep() {
        guard !isPaused, steps.indices.contains(stepIndex) else {
            return
        }
        let step = steps[stepIndex]
        if step.isWork {
            markSkipped(blockID: step.blockID, count: 1)
        }
        advance()
    }

    /// Skips every remaining step of the CURRENT block, landing on the
    /// first step of the next block (or `.finished`).
    func skipBlock() {
        guard !isPaused, steps.indices.contains(stepIndex) else {
            return
        }
        let blockID = steps[stepIndex].blockID
        var skippedWork = 0
        var cursor = stepIndex
        while cursor < steps.count, steps[cursor].blockID == blockID {
            if steps[cursor].isWork {
                skippedWork += 1
            }
            cursor += 1
        }
        if skippedWork > 0 {
            markSkipped(blockID: blockID, count: skippedWork)
        }
        stepIndex = cursor
        enterStep(at: stepIndex)
    }

    /// Inserts one more rep/round of the CURRENT block's own kind at the
    /// end of that block's step run (after whatever's left of it), with a
    /// rest ahead of it. A no-op if the current step isn't inside a block
    /// (shouldn't happen once the session has started).
    func addRep() {
        guard !isPaused, steps.indices.contains(stepIndex) else {
            return
        }
        let current = steps[stepIndex]
        guard let template = lastWorkStep(inBlockStartingAt: stepIndex, blockID: current.blockID) else {
            return
        }
        var insertionIndex = stepIndex
        while insertionIndex < steps.count, steps[insertionIndex].blockID == current.blockID {
            insertionIndex += 1
        }
        let block = plan.blocks.first { $0.id == current.blockID }
        let restSeconds = block?.restSeconds ?? 60
        let restStep = GuidedRunStep(
            blockID: template.blockID,
            blockIndex: template.blockIndex,
            blockCount: template.blockCount,
            blockName: template.blockName,
            blockTrainerText: template.blockTrainerText,
            kind: .rest(seconds: restSeconds)
        )
        let newWork = GuidedRunStep(
            blockID: template.blockID,
            blockIndex: template.blockIndex,
            blockCount: template.blockCount,
            blockName: template.blockName,
            blockTrainerText: template.blockTrainerText,
            kind: template.kind
        )
        steps.insert(contentsOf: [restStep, newWork], at: insertionIndex)
    }

    // MARK: - Countdown

    private func tickCountdown() {
        guard let countdownStartDate else {
            return
        }
        let elapsed = effectiveElapsed(since: countdownStartDate)
        let remaining = max(0, Self.countdownSeconds - Int(elapsed.rounded(.down)))
        if remaining != currentCountdownValue {
            phase = .countdown(secondsRemaining: remaining)
        }
        if remaining > 0, lastFiredCountdownValue != remaining {
            lastFiredCountdownValue = remaining
            cueHandler(.countdown(remaining))
        }
        if elapsed >= Double(Self.countdownSeconds) {
            cueHandler(.go)
            stepIndex = 0
            enterStep(at: 0)
        }
    }

    private var currentCountdownValue: Int? {
        if case let .countdown(remaining) = phase {
            return remaining
        }
        return nil
    }

    // MARK: - Work / rest ticking

    private func tickWork(stepIndex index: Int) {
        elapsedInCurrentStep = currentElapsed()
        guard steps.indices.contains(index) else {
            return
        }
        guard case let .work(kind) = steps[index].kind else {
            return
        }
        switch kind {
        case let .continuousDuration(targetSeconds):
            remainingInCurrentStep = max(0, targetSeconds - elapsedInCurrentStep)
            if !firedHalfwayForCurrentStep, elapsedInCurrentStep >= targetSeconds / 2 {
                firedHalfwayForCurrentStep = true
                cueHandler(.halfway)
            }
        case let .continuousDistance(targetMeters, _):
            remainingInCurrentStep = nil
            if targetMeters > 0, !firedHalfwayForCurrentStep, currentLiveDistanceMeters >= targetMeters / 2 {
                firedHalfwayForCurrentStep = true
                cueHandler(.halfway)
            }
        default:
            remainingInCurrentStep = nil
        }
    }

    private func tickRest(stepIndex index: Int) {
        elapsedInCurrentStep = currentElapsed()
        guard steps.indices.contains(index), case let .rest(seconds) = steps[index].kind else {
            return
        }
        let remaining = max(0, seconds - elapsedInCurrentStep)
        remainingInCurrentStep = remaining
        if !firedTenSecondsForCurrentStep, remaining <= 10, remaining > 0 {
            firedTenSecondsForCurrentStep = true
            cueHandler(.tenSecondsLeft)
        }
        if remaining <= 0 {
            advance()
        }
    }

    // MARK: - Recording

    private func record(step: GuidedRunStep, elapsed: TimeInterval, liveDistanceMeters: Double?) {
        var record = results[step.blockID] ?? GuidedRunBlockRecord(blockID: step.blockID)
        guard case let .work(kind) = step.kind else {
            results[step.blockID] = record
            return
        }
        switch kind {
        case .timedRep:
            record.repTimesSeconds.append(elapsed)
        case .round:
            record.roundsCompleted += 1
        case .continuousDuration:
            record.durationSeconds = (record.durationSeconds ?? 0) + elapsed
            if let liveDistanceMeters {
                record.distanceMeters = (record.distanceMeters ?? 0) + liveDistanceMeters
            }
        case .continuousDistance:
            record.durationSeconds = (record.durationSeconds ?? 0) + elapsed
            record.distanceMeters = (record.distanceMeters ?? 0) + (liveDistanceMeters ?? 0)
        case .freeform:
            record.durationSeconds = (record.durationSeconds ?? 0) + elapsed
            if let liveDistanceMeters {
                record.distanceMeters = (record.distanceMeters ?? 0) + liveDistanceMeters
            }
        }
        results[step.blockID] = record
    }

    private func markSkipped(blockID: UUID, count: Int) {
        var record = results[blockID] ?? GuidedRunBlockRecord(blockID: blockID)
        record.skippedCount += count
        results[blockID] = record
    }

    // MARK: - Step transitions

    private func advance() {
        stepIndex += 1
        enterStep(at: stepIndex)
    }

    private func enterStep(at index: Int) {
        guard steps.indices.contains(index) else {
            phase = .finished
            cueHandler(.done)
            return
        }
        stepStartDate = clock.now()
        accumulatedPause = 0
        pausedAt = isPaused ? clock.now() : nil
        elapsedInCurrentStep = 0
        remainingInCurrentStep = nil
        firedHalfwayForCurrentStep = false
        firedTenSecondsForCurrentStep = false
        currentLiveDistanceMeters = 0

        switch steps[index].kind {
        case .work:
            phase = .work(stepIndex: index)
        case .rest:
            phase = .rest(stepIndex: index)
            cueHandler(.restStart)
        }
    }

    // MARK: - Time helpers

    private func currentElapsed() -> TimeInterval {
        guard let stepStartDate else {
            return 0
        }
        return effectiveElapsed(since: stepStartDate)
    }

    private func effectiveElapsed(since start: Date) -> TimeInterval {
        let raw = clock.now().timeIntervalSince(start)
        let pauseSoFar = accumulatedPause + (pausedAt.map { clock.now().timeIntervalSince($0) } ?? 0)
        return max(0, raw - pauseSoFar)
    }

    private func lastWorkStep(inBlockStartingAt index: Int, blockID: UUID) -> GuidedRunStep? {
        var found: GuidedRunStep?
        var cursor = index
        // Scan forward from the current position to the end of the block —
        // covers both "still working through it" and "already past the
        // last rep" call sites.
        while cursor < steps.count, steps[cursor].blockID == blockID {
            if steps[cursor].isWork {
                found = steps[cursor]
            }
            cursor += 1
        }
        if found == nil {
            // Current position is itself past this block (e.g. mid-rest of
            // the NEXT block's lead-in) — scan backward instead.
            cursor = index
            while cursor >= 0, steps[cursor].blockID == blockID {
                if steps[cursor].isWork {
                    found = steps[cursor]
                    break
                }
                cursor -= 1
            }
        }
        return found
    }
}
