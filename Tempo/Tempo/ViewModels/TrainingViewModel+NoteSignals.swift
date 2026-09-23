//
// TrainingViewModel+NoteSignals.swift
// Tempo
//
// Free-text note signals (pain / too hard / too easy / form) and feedback
// aggregation (Tier 2.1 / 2.3) — pure helpers that nudge prescriptions.
// Split out of TrainingViewModel.swift to keep it under the SwiftLint
// file/type-body length caps — same instance methods, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Note signals (free-text feedback → prescription nudges)

    /// Coarse signals extracted from an exercise's recent free-text notes. Used
    /// to nudge the next prescription: conservative signals cap the weight, an
    /// "easy" signal nudges it up. PAIN DOMINATES — any pain note makes the
    /// exercise conservative regardless of an "easy" note elsewhere.
    struct NoteSignalSummary {
        var pain = false // injury/pain → hold conservative until it clears
        var tooHard = false // failed / too heavy / grind → hold conservative
        var tooEasy = false // too light / could do more → allow a nudge up
        var formIssue = false // form broke / sloppy → hold conservative

        /// Any signal that should PREVENT a weight increase this session.
        var isConservative: Bool {
            pain || tooHard || formIssue
        }

        /// OR another row's signals into this summary (an exercise's notes across
        /// several sets combine; any positive signal sticks).
        mutating func merge(_ other: NoteSignalSummary) {
            pain = pain || other.pain
            tooHard = tooHard || other.tooHard
            tooEasy = tooEasy || other.tooEasy
            formIssue = formIssue || other.formIssue
        }
    }

    // Pure keyword tables — immutable, so `nonisolated` lets the pure
    // `classifyNote` classifier read them off the main actor.

    /// Pain/injury keywords scanned in user notes. Lowercased, substring match.
    private nonisolated static let painKeywords = [
        "hurt", "pain", "painful", "tweak", "strain", "pinch", "pinched",
        "sore", "injury", "injured", "tendon", "ache", "aching", "sharp",
    ]

    /// "Too hard / failed" keywords → hold conservative next session.
    private nonisolated static let tooHardKeywords = [
        "too heavy", "too hard", "failed", "couldn't", "could not", "grind",
        "grinder", "grindy", "missed", "struggled", "barely", "way too heavy",
    ]

    /// Form-breakdown keywords → hold conservative next session.
    private nonisolated static let formIssueKeywords = [
        "form broke", "form broke down", "sloppy", "bad form", "lost form",
        "cheated", "cheat rep", "cheat reps",
    ]

    /// "Too easy / too light" keywords → nudge next session UP. Deliberately
    /// STRICT (explicit phrasing only) — bare "easy"/"light" false-trips
    /// ("easy on the knees", "light headed"), and this is the riskier upward
    /// direction, so we require the user to have clearly said it.
    private nonisolated static let tooEasyKeywords = [
        "too easy", "too light", "way too light", "way too easy",
        "felt too light", "could do more", "could've done more",
        "could have done more", "sandbagged", "sandbag", "left reps",
    ]

    /// Negators that cancel an "easy" match in the same note.
    private nonisolated static let easyNegators = ["not easy", "wasn't easy", "not light", "n't easy", "far from easy"]

    /// Classify a single already-lowercased note into coarse signals. Pure — the
    /// unit of the keyword logic, independently testable. Pain/too-hard/form all
    /// stack; "too easy" is dropped when a negator is present in the same note.
    nonisolated static func classifyNote(_ note: String) -> NoteSignalSummary {
        var s = NoteSignalSummary()
        if painKeywords.contains(where: { note.contains($0) }) {
            s.pain = true
        }
        if tooHardKeywords.contains(where: { note.contains($0) }) {
            s.tooHard = true
        }
        if formIssueKeywords.contains(where: { note.contains($0) }) {
            s.formIssue = true
        }
        if tooEasyKeywords.contains(where: { note.contains($0) }),
           !easyNegators.contains(where: { note.contains($0) })
        {
            s.tooEasy = true
        }
        return s
    }

    /// Scan recent (last `days`) USER-PROVIDED SetFeedback notes and classify
    /// each exercise's free text into coarse prescription signals. Deterministic
    /// keyword matching — the honest floor, not full comprehension (that is the
    /// batched AI coach review's job). Transient (scanned fresh each call, no
    /// stored flag) so it always reflects the latest notes and adds no
    /// migration. Feedback whose plannedSet relationship is nil is skipped.
    func noteSignals(within days: Int = 21, modelContext: ModelContext) -> [UUID: NoteSignalSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<SetFeedback>(
            predicate: #Predicate<SetFeedback> { $0.userProvidedFeedback && $0.capturedAt >= cutoff }
        )
        guard let rows = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        var out: [UUID: NoteSignalSummary] = [:]
        for row in rows {
            // Read the denormalized exercise id — NEVER traverse row.plannedSet
            // here. That relationship is one-way and its .nullify does not fire,
            // so after a set is deleted it dangles and faults on invalidated
            // backing (crash). Rows captured before exerciseID existed read nil
            // and are simply skipped (they're old feedback, not a regression).
            guard let exID = row.exerciseID else {
                continue
            }
            guard let note = row.note?.lowercased(), !note.isEmpty else {
                continue
            }
            var summary = out[exID] ?? NoteSignalSummary()
            summary.merge(Self.classifyNote(note))
            out[exID] = summary
        }
        return out
    }

    /// Recently (last `days`) flagged exercise IDs — any USER-PROVIDED note
    /// mentioning pain. Thin wrapper over `noteSignals` (pain subset), kept for
    /// existing call sites.
    func painFlaggedExerciseIDs(within days: Int = 21, modelContext: ModelContext) -> Set<UUID> {
        Set(noteSignals(within: days, modelContext: modelContext).filter(\.value.pain).map(\.key))
    }

    // MARK: - Feedback Aggregation (Tier 2.1, pure + unit-tested)

    /// Aggregate a session's USER-PROVIDED feedback for one exercise's completed
    /// working sets into the values stored on ExerciseHistory. Pure (no context,
    /// no VM state) so it's unit-testable without a device. `enteredFeedback` is
    /// keyed by `PlannedSet.id` and must already be filtered to
    /// userProvidedFeedback==true rows. Zero matches → (nil, nil, 0) = "no signal".
    nonisolated static func aggregateFeedback(
        completedSets: [PlannedSet],
        enteredFeedback: [UUID: SetFeedback]
    ) -> (avgRPE: Double?, worstFormRaw: String?, count: Int, gassedFraction: Double?) {
        let fb = completedSets.compactMap { enteredFeedback[$0.id] }
        guard !fb.isEmpty else {
            return (nil, nil, 0, nil)
        }
        let avgRPE = Double(fb.map(\.rpe).reduce(0, +)) / Double(fb.count)
        let worstForm = fb.map(\.formQuality).max { $0.severityRank < $1.severityRank }
        // Conditioning-debt signal: fraction of entered rows the user tagged
        // `.gassed`. Read by TrainingEngine.restMultiplier.
        let gassedCount = fb.filter(\.breathDifficulty.isNegativeSignal).count
        let gassedFraction = Double(gassedCount) / Double(fb.count)
        return (avgRPE, worstForm?.rawValue, fb.count, gassedFraction)
    }

    // assignSupersetGroups / muscleGroups / selectExercises /
    // exercisePriorityOrder / defaultWeight moved to
    // TrainingViewModel+ExercisePopulation.swift.
}
