//
// GuidedRunActivityContentBuilder.swift
// Tempo
//
// Guided run mode — maps a `GuidedRunSession`'s CURRENT state onto the one
// `GuidedRunActivitySnapshot` fanned out to the Live Activity and the Watch
// mirror. Pure function of (session, locationTracker, live HR) — no
// ActivityKit/WatchConnectivity here, so it's trivially unit-testable against
// the same FakeGuidedRunClock-driven sessions GuidedRunSessionTests already
// builds (GuidedRunActivityContentBuilderTests).
//

import Foundation

@MainActor
enum GuidedRunActivityContentBuilder {
    /// nil during idle/finished/endedEarly — callers end the Activity /
    /// clear the Watch mirror instead of pushing a snapshot.
    static func build(
        session: GuidedRunSession,
        locationTracker: GuidedRunLocationTracker,
        useMiles: Bool,
        heartRateBPM: Double?,
        maxHeartRate: Double?,
        now: Date = Date()
    ) -> GuidedRunActivitySnapshot? {
        let heartRateText = heartRateBPM.map { "\(Int($0.rounded())) bpm" }
        let heartRateZone = heartRateBPM.flatMap { bpm in
            maxHeartRate.flatMap { HeartRateZoneCalculator.zone(bpm: bpm, maxHeartRate: $0) }
        }

        switch session.phase {
        case .idle,
             .finished,
             .endedEarly:
            return nil

        case let .countdown(remaining):
            return GuidedRunActivitySnapshot(
                stepTitle: "GET READY",
                detailText: nil,
                nextStepText: nil,
                distanceText: nil,
                paceText: nil,
                heartRateText: heartRateText,
                heartRateZone: heartRateZone,
                isRest: false,
                isCountdown: true,
                isPaused: false,
                countsDown: true,
                timerAnchor: now.addingTimeInterval(Double(remaining)),
                frozenText: nil,
                updatedAt: now
            )

        case let .work(index):
            guard session.steps.indices.contains(index),
                  case let .work(kind) = session.steps[index].kind
            else {
                return nil
            }
            let step = session.steps[index]
            let continuous = isContinuous(kind)
            let anchor = now.addingTimeInterval(-session.elapsedInCurrentStep)
            return GuidedRunActivitySnapshot(
                stepTitle: "\(step.blockName) · \(workLabel(kind))",
                detailText: workDetail(kind),
                nextStepText: nil,
                distanceText: continuous
                    ? GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles)
                    : nil,
                paceText: continuous
                    ? GuidedRunFormatting.pace(secondsPerKm: locationTracker.currentPaceSecondsPerKm, useMiles: useMiles)
                    : nil,
                heartRateText: heartRateText,
                heartRateZone: heartRateZone,
                isRest: false,
                isCountdown: false,
                isPaused: session.isPaused,
                countsDown: false,
                timerAnchor: anchor,
                frozenText: session.isPaused ? GuidedRunFormatting.clock(session.elapsedInCurrentStep) : nil,
                updatedAt: now
            )

        case let .rest(index):
            guard session.steps.indices.contains(index), case let .rest(restSeconds) = session.steps[index].kind else {
                return nil
            }
            // `remainingInCurrentStep` is nil the instant the rest phase is
            // entered (a tick() hasn't run yet to compute it) — this fires
            // from the SAME cueHandler call as `.restStart`, so fall back to
            // the step's own full rest duration rather than 0. 0 would anchor
            // the countdown at "now", and a countdown range starting exactly
            // at "now" trips `Text(timerInterval:)`'s lowerBound<=upperBound
            // precondition the instant any real propagation delay elapses
            // before the widget/watch actually renders it — a real crash,
            // not just a display quirk (see GuidedRunTimerText's own clamp
            // for the belt-and-suspenders half of this fix).
            let remaining = session.remainingInCurrentStep ?? restSeconds
            let anchor = now.addingTimeInterval(max(0, remaining))
            return GuidedRunActivitySnapshot(
                stepTitle: "REST",
                detailText: nil,
                nextStepText: nextStepText(session: session, restIndex: index),
                distanceText: nil,
                paceText: nil,
                heartRateText: heartRateText,
                heartRateZone: heartRateZone,
                isRest: true,
                isCountdown: false,
                isPaused: session.isPaused,
                countsDown: true,
                timerAnchor: anchor,
                frozenText: session.isPaused ? "Rest \(GuidedRunFormatting.clock(remaining))" : nil,
                updatedAt: now
            )
        }
    }

    // MARK: - Helpers

    private static func isContinuous(_ kind: GuidedRunWorkKind) -> Bool {
        switch kind {
        case .continuousDuration,
             .continuousDistance: true
        default: false
        }
    }

    /// Short current-step label — the part after "Block name · ".
    private static func workLabel(_ kind: GuidedRunWorkKind) -> String {
        switch kind {
        case let .timedRep(rep): "Rep \(rep.index + 1)/\(rep.of)"
        case let .round(index, of): "Round \(index + 1)/\(of)"
        case .continuousDuration,
             .continuousDistance,
             .freeform: "In progress"
        }
    }

    /// The cap/target line shown under the step title — nil when there's
    /// nothing beyond the label itself worth a second line.
    private static func workDetail(_ kind: GuidedRunWorkKind) -> String? {
        switch kind {
        case let .timedRep(rep):
            rep.capSeconds.map { "Cap \(GuidedRunFormatting.repTime($0))" }
        case let .continuousDuration(targetSeconds):
            "\(Int((targetSeconds / 60).rounded())) min target"
        case let .continuousDistance(_, targetLabel):
            "Target \(targetLabel)"
        case .round,
             .freeform:
            nil
        }
    }

    /// Rest screen's "Next: Rep 3" preview — the block name is already on
    /// screen from the step just finished, so this stays short.
    private static func nextStepText(session: GuidedRunSession, restIndex: Int) -> String? {
        let nextIndex = restIndex + 1
        guard session.steps.indices.contains(nextIndex),
              case let .work(kind) = session.steps[nextIndex].kind
        else {
            return "Next: Finish"
        }
        return "Next: \(workLabel(kind))"
    }
}
