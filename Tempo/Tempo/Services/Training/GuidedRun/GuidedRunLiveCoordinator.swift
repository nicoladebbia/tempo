//
// GuidedRunLiveCoordinator.swift
// Tempo
//
// Guided run mode — the one place that fans a `GuidedRunSession`'s state out
// to the Live Activity (ActivityKit) and the Apple Watch mirror
// (WatchConnectivity), and routes watch taps back onto the session. Owned by
// `GuidedRunView` as a stable `@State` reference (survives the view struct's
// own re-renders, unlike a plain closure capturing `self`).
//
// Deliberately NOT `@Observable` — nothing in the UI reads this; it's a pure
// side-effect coordinator the view drives from its own `.task`/`.onChange`/
// `.onReceive` hooks.
//
// Update cadence (per the feasibility audit's ActivityKit rate limit):
// pushed only on real state transitions — `session.phase`/`isPaused`
// changing, and the engine's own sparse cue moments (halfway, ten-seconds,
// countdown, go, rest-start, done) — never on a per-second timer. Both the
// Live Activity and the widget/watch UI still show a LIVE, ticking clock
// between pushes via `Text(timerInterval:)` (date-anchored, no polling).
//

import Foundation

// MARK: - GuidedRunLiveCoordinator

@MainActor
final class GuidedRunLiveCoordinator {
    /// Weak — `GuidedRunView`'s own `@State` is what keeps the session
    /// alive; this coordinator just observes it for the run's duration.
    weak var session: GuidedRunSession?
    weak var locationTracker: GuidedRunLocationTracker?

    var runTitle = ""
    var useMiles = false
    /// Watch → phone HR relay result, and the max HR used for the zone
    /// shown alongside it — set once by the view from `UserSettings`/
    /// `UserProfile` at session start.
    var maxHeartRate: Double?

    private var isActive = false
    /// Tracked locally so this coordinator always knows whether it has
    /// already requested the Activity, without querying the actor.
    private var activityStarted = false

    // MARK: - Lifecycle

    func start(session: GuidedRunSession, runTitle: String, useMiles: Bool, maxHeartRate: Double?) {
        self.session = session
        self.runTitle = runTitle
        self.useMiles = useMiles
        self.maxHeartRate = maxHeartRate
        isActive = true
        activityStarted = false
        LiveActivityCoordinator.shared.register(self, for: .guidedRun)
        sync()
    }

    func end() {
        guard isActive else {
            return
        }
        isActive = false
        activityStarted = false
        LiveActivityCoordinator.shared.end(.guidedRun) {
            await GuidedRunActivityManager.shared.endCurrent()
        }
        PhoneWatchConnectivityService.shared.endGuidedRun()
    }

    // MARK: - Transition hooks (called by GuidedRunView)

    /// `.onChange(of: session.phase)` / `.onChange(of: session.isPaused)`.
    func handleTransition() {
        guard isActive else {
            return
        }
        sync()
    }

    /// The engine's own cue moments (halfway, ten-seconds-left, countdown,
    /// go, rest-start, done) — sparse by construction, so piggy-backing the
    /// sync here adds richness (e.g. a fresher distance/pace mid continuous
    /// step) without ever approaching a per-second cadence.
    func handleCue(_ cue: GuidedRunCue) {
        guard isActive else {
            return
        }
        if cue == .done {
            end()
            return
        }
        sync()
    }

    // MARK: - Watch → phone actions

    /// Registered on `WatchActionRouter.setGuidedRunActionHandler` for
    /// exactly the lifetime of a live session. The phone's session is the
    /// sole source of truth — every case just calls the same method the
    /// on-screen button would, and each of those is already a guarded no-op
    /// outside its valid phase/pause state.
    func handleWatchAction(_ payload: WatchActionPayload) -> Bool {
        guard let session else {
            return false
        }
        switch payload.action {
        case .guidedRunMarkDone:
            session.markDone(liveDistanceMeters: locationTracker?.isTracking == true ? locationTracker?.distanceMeters : nil)
            return true
        case .guidedRunSkipRep:
            session.skipRep()
            return true
        case .guidedRunPause:
            session.pause()
            sync()
            return true
        case .guidedRunResume:
            session.resume()
            sync()
            return true
        case .guidedRunHeartRate:
            guard let bpm = payload.payload["bpm"].flatMap(Double.init) else {
                return false
            }
            session.updateLiveHeartRate(bpm)
            return true
        default:
            return false
        }
    }

    // MARK: - Snapshot fan-out

    private func sync() {
        guard let session, let locationTracker else {
            return
        }
        guard let snapshot = GuidedRunActivityContentBuilder.build(
            session: session,
            locationTracker: locationTracker,
            useMiles: useMiles,
            heartRateBPM: session.currentHeartRateBPM,
            maxHeartRate: maxHeartRate
        )
        else {
            return
        }
        if activityStarted {
            LiveActivityCoordinator.shared.update {
                await GuidedRunActivityManager.shared.update(state: snapshot)
            }
        } else {
            activityStarted = true
            let title = runTitle
            LiveActivityCoordinator.shared.start(.guidedRun) {
                await GuidedRunActivityManager.shared.start(runTitle: title, state: snapshot)
            }
        }
        PhoneWatchConnectivityService.shared.pushGuidedRun(snapshot)
    }
}

// MARK: LiveActivityParticipant

extension GuidedRunLiveCoordinator: LiveActivityParticipant {
    /// Guided run outranks the other two kinds, but it can still get
    /// suspended in the (currently theoretical, since the app has no UI path
    /// to start a workout mid-run) case another `LiveActivityCoordinator`
    /// caller registers something above it — kept honest so priority is
    /// enforced uniformly rather than guided run being a hardcoded special
    /// case.
    var hasActiveLiveSession: Bool {
        isActive
    }

    func suspendLiveActivity() async {
        await GuidedRunActivityManager.shared.endCurrent()
        activityStarted = false
    }

    func resumeLiveActivityIfNeeded() async {
        guard isActive, let session, let locationTracker,
              let snapshot = GuidedRunActivityContentBuilder.build(
                  session: session,
                  locationTracker: locationTracker,
                  useMiles: useMiles,
                  heartRateBPM: session.currentHeartRateBPM,
                  maxHeartRate: maxHeartRate
              )
        else {
            return
        }
        activityStarted = true
        await GuidedRunActivityManager.shared.start(runTitle: runTitle, state: snapshot)
    }
}
