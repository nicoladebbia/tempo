//
// CoachConversation.swift
// Tempo
//
// SwiftData model for a Coach chat session. Stores the full transcript
// JSON-encoded so we can rehydrate the agent loop after app relaunch and
// feed prior turns to the PreferenceExtractor when the conversation ends.
//
// Additive to TempoSchemaV1 — no migration needed because no existing
// model gains a required field. See `.plans/coach-agent-plan.md` Phase 6
// + ADR note in `docs/COACH_AGENT.md`.
//

import Foundation
import SwiftData

@Model
final class CoachConversation {

    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Lifecycle

    var startedAt: Date
    var endedAt: Date?

    /// Short one-line summary minted at session end (or after the first
    /// few turns). Surfaced in the Coach memory UI and consumed by
    /// `CoachContextAssembler` to remind the agent of prior threads.
    var titleSummary: String?

    // MARK: - Transcript

    /// JSON-encoded `[ChatTurn]`. Stored as Data so SwiftData doesn't
    /// have to keep the array hot in memory for conversations the user
    /// never reopens. Decode via `turns()`.
    var messagesJSON: Data?

    /// Token tally for the entire conversation (input + output, summed
    /// across every turn). Used by the budget gate + memory UI's
    /// "this session cost X" debug surface.
    var totalTokensIn: Int
    var totalTokensOut: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        titleSummary: String? = nil,
        turns: [ChatTurn] = [],
        totalTokensIn: Int = 0,
        totalTokensOut: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.titleSummary = titleSummary
        self.messagesJSON = try? JSONEncoder().encode(turns)
        self.totalTokensIn = totalTokensIn
        self.totalTokensOut = totalTokensOut
    }

    // MARK: - Transcript codec

    func turns() -> [ChatTurn] {
        guard let data = messagesJSON,
              let decoded = try? JSONDecoder().decode([ChatTurn].self, from: data)
        else { return [] }
        return decoded
    }

    func setTurns(_ turns: [ChatTurn]) {
        messagesJSON = try? JSONEncoder().encode(turns)
    }

    func appendTurn(_ turn: ChatTurn) {
        var all = turns()
        all.append(turn)
        setTurns(all)
    }

    /// Compact plaintext rendering for the PreferenceExtractor.
    func transcriptText() -> String {
        turns().map { turn in
            let speaker = turn.role.capitalized
            let body = turn.blocks.compactMap { block -> String? in
                switch block {
                case let .text(s): return s
                case let .toolUse(name, _, _): return "[tool:\(name)]"
                case let .toolResult(_, _, text): return text.map { "[result] \($0)" }
                }
            }.joined(separator: " ")
            return "\(speaker): \(body)"
        }.joined(separator: "\n")
    }
}

// MARK: - ChatTurn (on-wire)

/// One turn in a Coach conversation. Mirrors Anthropic's message shape so
/// the multi-turn agent loop can pass turns straight to the backend chat
/// endpoint without an extra translation step.
struct ChatTurn: Codable, Sendable, Equatable {
    /// "user" or "assistant".
    let role: String
    let blocks: [ChatTurnBlock]
    let timestamp: Date

    init(role: String, blocks: [ChatTurnBlock], timestamp: Date = Date()) {
        self.role = role
        self.blocks = blocks
        self.timestamp = timestamp
    }
}

enum ChatTurnBlock: Codable, Sendable, Equatable {
    case text(String)
    case toolUse(name: String, id: String, inputJSON: String)
    case toolResult(toolUseID: String, isError: Bool, text: String?)

    private enum CodingKeys: String, CodingKey {
        case type, text, name, id, inputJSON, toolUseID, isError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                name: try c.decode(String.self, forKey: .name),
                id: try c.decode(String.self, forKey: .id),
                inputJSON: try c.decode(String.self, forKey: .inputJSON)
            )
        case "tool_result":
            self = .toolResult(
                toolUseID: try c.decode(String.self, forKey: .toolUseID),
                isError: try c.decode(Bool.self, forKey: .isError),
                text: try c.decodeIfPresent(String.self, forKey: .text)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown turn block type \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case let .toolUse(name, id, inputJSON):
            try c.encode("tool_use", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(id, forKey: .id)
            try c.encode(inputJSON, forKey: .inputJSON)
        case let .toolResult(toolUseID, isError, text):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseID, forKey: .toolUseID)
            try c.encode(isError, forKey: .isError)
            try c.encodeIfPresent(text, forKey: .text)
        }
    }
}
