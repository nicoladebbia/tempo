//
// ExerciseResearch.swift
// Tempo
//
// Trainer Program import: an exercise the library doesn't have (no
// ExerciseMatcher match) used to be saved as a bare custom row — "Full
// Body · Isolation", no instructions. Now the review screen looks every such
// name up with Claude in ONE call (muscles, equipment, movement pattern,
// instructions, form cues), shows it as NEW for the user to check or edit,
// and TrainerProgramSaver creates the Exercise from those details.
//
// The call goes through the program-import STRUCTURE route with the import's
// own session id, so it shares that import's quota slot — researching the
// exercises never costs a free user an extra import.
//

import Foundation
import os

// MARK: - ExerciseResearch

/// Researched library details for one exercise name.
struct ExerciseResearch: Equatable, Sendable {
    var muscleGroup: MuscleGroup
    var secondaryMuscles: [MuscleGroup]
    var equipment: Equipment
    var movementPattern: MovementPattern
    var isCompound: Bool
    var instructions: String
    var cues: [String]

    /// Short line for the review row: "Quads · Barbell · Squat".
    var summary: String {
        [muscleGroup.displayName, Self.label(equipment.rawValue), Self.label(movementPattern.rawValue)]
            .joined(separator: " · ")
    }

    /// "resistance_band" → "Resistance Band".
    static func label(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - ExerciseResearchParser

/// Prompt + tolerant JSON parsing. Pure — unit-tested without the network.
enum ExerciseResearchParser {
    /// Model output is capped per call; a longer list is split into batches.
    static let maxNamesPerCall = 20

    static let systemPrompt = """
    You are a strength and conditioning coach building an exercise library. \
    For each exercise name (from a personal trainer's program — may be \
    Italian or English, may use shorthand like DB, KB, SA, SL, RDL), identify \
    the exercise and describe it. Output ONLY valid JSON: no markdown, no \
    code fences, no commentary. Shape:
    {"exercises":[{"input":"<the name exactly as given>",\
    "muscle_group":"<one of: \(MuscleGroup.allCases.map(\.rawValue).joined(separator: ", "))>",\
    "secondary_muscles":["<same values>"],\
    "equipment":"<one of: \(Equipment.allCases.map(\.rawValue).joined(separator: ", "))>",\
    "movement_pattern":"<one of: \(MovementPattern.allCases.map(\.rawValue).joined(separator: ", "))>",\
    "is_compound":true,\
    "instructions":"<2-4 short sentences: setup and execution>",\
    "cues":["<3 short form cues>"]}]}
    Write instructions and cues in English. If a name is ambiguous, pick the \
    most common gym interpretation. Return one entry per input, same order.
    """

    static func userMessage(names: [String]) -> String {
        "Exercises:\n" + names.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Research keyed by `ExerciseMatcher.normalize(input)`. Entries with an
    /// unknown muscle group / pattern fall back to safe values rather than
    /// being dropped; entries with no usable input name are skipped.
    static func parse(_ raw: String) throws -> [String: ExerciseResearch] {
        guard let json = TrainerProgramParser.extractJSON(from: raw), let data = json.data(using: .utf8) else {
            throw ParseError.noJSON
        }
        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        var result: [String: ExerciseResearch] = [:]
        for entry in decoded.exercises {
            let key = ExerciseMatcher.normalize(entry.input ?? "")
            guard !key.isEmpty else {
                continue
            }
            let primary = entry.muscleGroup.flatMap(MuscleGroup.init(rawValue:)) ?? .fullBody
            let secondary = (entry.secondaryMuscles ?? [])
                .compactMap(MuscleGroup.init(rawValue:))
                .filter { $0 != primary }
            let cues = (entry.cues ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            result[key] = ExerciseResearch(
                muscleGroup: primary,
                secondaryMuscles: secondary,
                equipment: entry.equipment.flatMap(Equipment.init(rawValue:)) ?? .none,
                movementPattern: entry.movementPattern.flatMap(MovementPattern.init(rawValue:)) ?? .isolation,
                isCompound: entry.isCompound ?? false,
                instructions: (entry.instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                cues: Array(cues.prefix(5))
            )
        }
        return result
    }

    enum ParseError: Error, Equatable {
        case noJSON
        case invalidJSON
    }

    private struct Envelope: Decodable {
        let exercises: [Entry]
    }

    private struct Entry: Decodable {
        let input: String?
        let muscleGroup: String?
        let secondaryMuscles: [String]?
        let equipment: String?
        let movementPattern: String?
        let isCompound: Bool?
        let instructions: String?
        let cues: [String]?

        enum CodingKeys: String, CodingKey {
            case input
            case muscleGroup = "muscle_group"
            case secondaryMuscles = "secondary_muscles"
            case equipment
            case movementPattern = "movement_pattern"
            case isCompound = "is_compound"
            case instructions
            case cues
        }
    }
}

// MARK: - ExerciseResearchProviding

protocol ExerciseResearchProviding: Sendable {
    /// Researches `names` (≤ `ExerciseResearchParser.maxNamesPerCall`) in one
    /// call. Keys are `ExerciseMatcher.normalize(name)`.
    func research(names: [String], sessionID: String) async throws -> [String: ExerciseResearch]
}

// MARK: - ExerciseResearchService

/// Network wrapper: one Haiku call on the program-import structure route.
struct ExerciseResearchService: ExerciseResearchProviding {
    let apiClient: APIClient

    func research(names: [String], sessionID: String) async throws -> [String: ExerciseResearch] {
        let body = ProgramImportStructureRequestDTO(
            sessionID: sessionID,
            model: "haiku",
            system: ExerciseResearchParser.systemPrompt,
            userMessage: ExerciseResearchParser.userMessage(names: names),
            maxTokens: min(4096, 300 + names.count * 220),
            temperature: 0,
            caller: "trainer_program_exercise_research"
        )
        let response: ProgramImportStructureResponseDTO = try await apiClient.request(
            APIEndpoint<ProgramImportStructureResponseDTO>.trainerProgramImportStructure(),
            body: body
        )
        return try ExerciseResearchParser.parse(response.text)
    }
}

// MARK: - ExerciseResearchStore

/// Per-review-screen research state, keyed by normalized exercise name.
@Observable
@MainActor
final class ExerciseResearchStore {
    enum State: Equatable {
        case loading
        case done(ExerciseResearch)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    private var provider: (any ExerciseResearchProviding)?
    private let logger = Logger.training
    /// The import's session id (shares its quota slot). nil when editing a
    /// saved program — lookups are then manual only, and the first one mints
    /// a session that later manual lookups on this screen reuse.
    private(set) var sessionID: String?
    /// Look up unmatched names on their own (fresh import) vs only when the
    /// user taps "Look it up" (edit mode — each new session is a quota slot).
    var isAutomatic: Bool {
        importSessionID != nil
    }

    private let importSessionID: String?

    init(provider: (any ExerciseResearchProviding)? = nil, importSessionID: String?) {
        self.provider = provider
        self.importSessionID = importSessionID
        sessionID = importSessionID
    }

    func configure(provider: any ExerciseResearchProviding) {
        if self.provider == nil {
            self.provider = provider
        }
    }

    /// Manual lookup for one row (retry, or edit mode).
    func lookUp(_ name: String) async {
        let session = sessionID ?? UUID().uuidString
        sessionID = session
        await research(names: [name], sessionID: session, force: true)
    }

    func state(for name: String) -> State? {
        states[ExerciseMatcher.normalize(name)]
    }

    /// Finished research only — what Save hands to TrainerProgramSaver.
    var results: [String: ExerciseResearch] {
        states.compactMapValues {
            if case let .done(research) = $0 {
                return research
            }
            return nil
        }
    }

    /// The user's edits from the review screen replace the AI's answer.
    func update(_ research: ExerciseResearch, for name: String) {
        states[ExerciseMatcher.normalize(name)] = .done(research)
    }

    /// Looks up every name not already researched or in flight (`force`
    /// retries failures too). Batches of `maxNamesPerCall`, one after another.
    func research(names: [String], sessionID: String, force: Bool = false) async {
        guard let provider else {
            return
        }
        var seen = Set<String>()
        let pending = names.filter { name in
            let key = ExerciseMatcher.normalize(name)
            guard !key.isEmpty, seen.insert(key).inserted else {
                return false
            }
            switch states[key] {
            case .none: return true
            case .failed: return force
            case .loading,
                 .done: return false
            }
        }
        guard !pending.isEmpty else {
            return
        }
        for name in pending {
            states[ExerciseMatcher.normalize(name)] = .loading
        }
        for start in stride(from: 0, to: pending.count, by: ExerciseResearchParser.maxNamesPerCall) {
            let batch = Array(pending[start ..< min(start + ExerciseResearchParser.maxNamesPerCall, pending.count)])
            do {
                let found = try await provider.research(names: batch, sessionID: sessionID)
                for name in batch {
                    let key = ExerciseMatcher.normalize(name)
                    guard states[key] == .loading else {
                        continue // edited by the user meanwhile
                    }
                    states[key] = found[key].map(State.done) ?? .failed("Couldn't identify this exercise")
                }
            } catch {
                // Cancelled because the screen's name list changed (another
                // row edited mid-flight) — not a failure. Clear the rows so
                // the restarted automatic lookup picks them up again.
                if Task.isCancelled {
                    for name in pending where states[ExerciseMatcher.normalize(name)] == .loading {
                        states[ExerciseMatcher.normalize(name)] = nil
                    }
                    return
                }
                let message = if case APIError.unauthorized = error {
                    "Sign in to look up new exercises"
                } else {
                    "Couldn't look it up"
                }
                logger.warning("\(DebugTrace.prefix)[exercise_research] failed: \(String(describing: error))")
                for name in batch where states[ExerciseMatcher.normalize(name)] == .loading {
                    states[ExerciseMatcher.normalize(name)] = .failed(message)
                }
            }
        }
    }
}
