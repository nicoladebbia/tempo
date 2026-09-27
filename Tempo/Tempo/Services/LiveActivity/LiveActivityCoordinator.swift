//
// LiveActivityCoordinator.swift
// Tempo
//
// The single choke point for every Live Activity start/update/end across
// the app's three independent activity kinds — gym workout
// (`WorkoutActivityManager`), focus timer (`FocusTimerActivityManager`) and
// guided run (`GuidedRunActivityManager`). Before this existed, the three
// managers had zero awareness of each other: two live at once could collide
// with ActivityKit's own limits and show competing lock-screen timers.
//
// Two responsibilities:
//
//  1. Priority. Only one kind is ever allowed to actually own the on-screen
//     Activity at a time — guided run > gym workout > focus timer (a run is
//     the most time-critical; a workout usually matters more than a study
//     timer, but a run in progress outranks both). Starting a higher-
//     priority kind suspends whichever lower-priority one currently owns the
//     screen (ends its `Activity`, but leaves its session running); when the
//     higher-priority one ends, the highest-priority SUSPENDED kind whose
//     session is still alive gets its Activity back, built fresh from
//     current state (the timers are date-based, so re-requesting with the
//     session's current end date is all "resume" needs).
//
//  2. Serialization. Every mutation — for all three kinds — is chained onto
//     one `Task`, so calls apply in the order they were issued rather than
//     completion order. This generalizes the pattern
//     `GuidedRunLiveCoordinator` used to run just for itself (see that
//     type's git history) instead of duplicating a second, separate
//     serializer.
//
// Deliberately ActivityKit-free: this file never imports ActivityKit. Each
// kind's actual `Activity<T>` calls stay behind the closures callers pass in
// and behind `LiveActivityParticipant` conformances on the owning view
// model/coordinator — which is what makes the priority/resume logic here
// unit-testable with a fake participant instead of the real framework.
//

import Foundation

// MARK: - LiveActivityKind

/// The three independent Live Activity kinds, ordered by priority
/// (ascending `rawValue` = ascending priority; `guidedRun` wins any clash).
enum LiveActivityKind: Int, CaseIterable, Comparable {
    case focusTimer
    case gymWorkout
    case guidedRun

    static func < (lhs: LiveActivityKind, rhs: LiveActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - LiveActivityParticipant

/// Conformed to by whatever owns a Live-Activity-backed session — the view
/// model or coordinator that knows whether its session is still logically
/// running and can rebuild an Activity request from current state. The
/// `LiveActivityCoordinator` only ever talks to participants through this
/// protocol, never to ActivityKit directly.
@MainActor
protocol LiveActivityParticipant: AnyObject {
    /// True while this participant's underlying session (workout in
    /// progress, focus timer ticking, guided run active) is still alive —
    /// even while its on-screen Activity is suspended for a higher-priority
    /// one. Read only from inside the coordinator's serialized queue.
    var hasActiveLiveSession: Bool { get }

    /// End this participant's own on-screen Activity, but leave its session
    /// state untouched so `resumeLiveActivityIfNeeded` can bring it back
    /// later with the correct remaining time.
    func suspendLiveActivity() async

    /// Re-request the Activity from current session state. Must no-op if
    /// `hasActiveLiveSession` is false (the session ended while suspended).
    func resumeLiveActivityIfNeeded() async
}

// MARK: - LiveActivityCoordinator

/// Single serializer + priority arbiter for all Live Activity traffic. A
/// process-wide singleton (like the three managers it sits above) — there is
/// exactly one lock screen, so exactly one coordinator.
@MainActor
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private var participants: [LiveActivityKind: LiveActivityParticipant] = [:]
    /// The kind currently believed to own the on-screen Activity, if any.
    private(set) var activeKind: LiveActivityKind?
    /// Kinds whose session is alive but whose Activity was suspended for a
    /// higher-priority one (or never shown, because a higher one was already
    /// active when they tried to start) — candidates to resume once
    /// `activeKind` frees up.
    private(set) var suspendedKinds: Set<LiveActivityKind> = []
    /// Chains every queued mutation so it runs strictly after the previous
    /// one finishes, regardless of which kind either belongs to.
    private var pendingTask: Task<Void, Never>?

    private init() {}

    /// Registers (or replaces) the participant that owns `kind`'s session.
    /// Safe to call every time a new session of that kind starts.
    func register(_ participant: LiveActivityParticipant, for kind: LiveActivityKind) {
        participants[kind] = participant
    }

    /// Removes a participant, e.g. in tests between cases. Production
    /// code never needs this — `register` overwriting a stale entry is
    /// enough, since a stale participant's `hasActiveLiveSession` will read
    /// false once its own session actually ends.
    func unregister(_ kind: LiveActivityKind) {
        participants[kind] = nil
    }

    /// Call immediately before requesting a brand-new Activity for `kind`
    /// (i.e. right where the caller would otherwise call
    /// `XActivityManager.shared.start(...)` directly). Enqueues:
    ///  - if a LOWER-priority kind currently owns the screen, suspends it
    ///    first, then runs `startWork`;
    ///  - if a HIGHER-priority kind currently owns the screen, does NOT run
    ///    `startWork` at all — `kind`'s session keeps running regardless,
    ///    and `end(_:endWork:)` will resume it once the higher one finishes;
    ///  - otherwise (nothing active, or restarting the same kind), just
    ///    runs `startWork`.
    func start(_ kind: LiveActivityKind, startWork: @escaping @MainActor () async -> Void) {
        enqueue { [weak self] in
            guard let self else {
                await startWork()
                return
            }
            switch self.activeKind {
            case let active? where active > kind:
                self.suspendedKinds.insert(kind)
                return
            case let active? where active < kind:
                if let loser = self.participants[active] {
                    await loser.suspendLiveActivity()
                }
                self.suspendedKinds.insert(active)
            default:
                break
            }
            self.activeKind = kind
            self.suspendedKinds.remove(kind)
            await startWork()
        }
    }

    /// Call for an ordinary content update on whichever kind is calling —
    /// no priority change. Safe to call even while `kind` is suspended: the
    /// underlying manager's `update` already no-ops when it has no current
    /// Activity, so an update queued for a suspended kind is simply inert
    /// until it resumes.
    func update(_ work: @escaping @MainActor () async -> Void) {
        enqueue(work)
    }

    /// Call when `kind`'s OWN session has genuinely ended (finished,
    /// discarded, cancelled) — NOT merely suspended for a higher-priority
    /// one. Runs `endWork` (tearing down `kind`'s Activity, if it has one),
    /// then, only if `kind` was the one actually on screen, resumes the
    /// highest-priority suspended participant whose session is still alive.
    func end(_ kind: LiveActivityKind, endWork: @escaping @MainActor () async -> Void) {
        enqueue { [weak self] in
            await endWork()
            guard let self else {
                return
            }
            let wasActive = self.activeKind == kind
            if wasActive {
                self.activeKind = nil
            }
            self.suspendedKinds.remove(kind)
            guard wasActive else {
                return
            }
            guard let next = LiveActivityKind.allCases
                .filter({ self.suspendedKinds.contains($0) })
                .sorted(by: >)
                .first(where: { self.participants[$0]?.hasActiveLiveSession == true })
            else {
                return
            }
            self.suspendedKinds.remove(next)
            self.activeKind = next
            if let participant = self.participants[next] {
                await participant.resumeLiveActivityIfNeeded()
            }
        }
    }

    /// Chains `work` onto the pending task so every start/update/end call —
    /// across all three kinds — applies in the order it was issued.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingTask
        pendingTask = Task { @MainActor in
            _ = await previous?.value
            await work()
        }
    }

    // MARK: - Testing

    /// Awaits every currently queued operation. Production code never needs
    /// this — Live Activity work is fire-and-forget by design — but tests
    /// driving fake participants need a deterministic point to assert from.
    func waitUntilIdle() async {
        await pendingTask?.value
    }

    /// Clears all state so a test starts from a blank coordinator. There is
    /// exactly one process-wide coordinator in production, so nothing but
    /// tests should ever call this.
    func resetForTesting() {
        participants = [:]
        activeKind = nil
        suspendedKinds = []
        pendingTask = nil
    }
}
