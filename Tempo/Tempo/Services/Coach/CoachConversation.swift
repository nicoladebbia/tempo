//
// CoachConversation.swift
// Tempo
//
// Coach v2.1 Phase 6a — chat-thread persistence.
//
// One SwiftData row per chat. The whole transcript is stored as one
// JSON blob (`messagesJSON`) because:
//   - a chat is read/written as a whole, not per message
//   - conversations are summarized + truncated at message 12, which is
//     a rewrite of the JSON in place
//   - in-conversation search is deferred to v2.x (per the plan's
//     out-of-scope section)
//
// Per .plans/coach-v2.1/02-data-model.md "Model 4 — CoachConversation"
// and the `CoachMessage` shape.
//

import Foundation
import SwiftData

// MARK: - CoachConversation

@Model
final class CoachConversation {
    @Attribute(.unique)
    var id: UUID

    /// First message timestamp.
    var startedAt: Date

    /// Sort key for History view. Advanced on every appended message.
    var lastMessageAt: Date

    /// Auto-generated 5-word summary written by a Haiku call on
    /// conversation end (Phase 6b's CoachService).
    var titleSummary: String

    /// One conversation is active at a time. Closing fires the extractor.
    var isActive: Bool

    /// Codable [CoachMessage] serialized to JSON. Empty array → empty bytes.
    /// Replace via the `messages` accessor below; do NOT write this field
    /// directly from outside.
    var messagesJSON: Data

    /// Starring exempts a row from the 30-day purge run by
    /// DailyResetCoordinator (Phase 6c).
    var isStarred: Bool

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        lastMessageAt: Date? = nil,
        titleSummary: String = "",
        isActive: Bool = true,
        messages: [CoachMessage] = [],
        isStarred: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.lastMessageAt = lastMessageAt ?? startedAt
        self.titleSummary = titleSummary
        self.isActive = isActive
        self.isStarred = isStarred
        if messages.isEmpty {
            self.messagesJSON = Data()
        } else {
            self.messagesJSON = (try? Self.encoder.encode(messages)) ?? Data()
        }
    }

    // MARK: - Accessors

    /// Decoded [CoachMessage]. Returns an empty array when the blob is
    /// missing or malformed (defensive — a corrupt blob shouldn't crash
    /// the agent loop).
    @Transient
    var messages: [CoachMessage] {
        get {
            guard !messagesJSON.isEmpty,
                  let decoded = try? Self.decoder.decode([CoachMessage].self, from: messagesJSON)
            else { return [] }
            return decoded
        }
        set {
            messagesJSON = (try? Self.encoder.encode(newValue)) ?? Data()
            lastMessageAt = newValue.last?.timestamp ?? lastMessageAt
        }
    }

    /// Append one message and advance lastMessageAt.
    func append(_ message: CoachMessage) {
        var current = messages
        current.append(message)
        messages = current
    }

    /// Replace messages[0..upTo] with a single system-summary pseudo
    /// message. Used by Phase 6b's summarizer at message 12.
    func collapseEarlyMessages(upTo: Int, with summary: CoachMessage) {
        guard upTo > 0 else { return }
        var current = messages
        guard upTo <= current.count else {
            messages = [summary]
            return
        }
        let preserved = Array(current[upTo...])
        current = [summary] + preserved
        messages = current
    }

    // MARK: - Codable plumbing

    /// Single shared encoder/decoder for the messagesJSON blob.
    /// ISO-8601 dates so messages are portable + diffable.
    fileprivate static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    fileprivate static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - CoachMessage

/// One turn in a CoachConversation. Stored as JSON inside
/// `CoachConversation.messagesJSON`. NOT a @Model — see the data-model
/// doc rationale ("read/written as a whole, summarization rewrites in
/// place").
struct CoachMessage: Codable, Equatable, Sendable {
    /// "user" | "assistant" | "tool_result" | "system_summary"
    /// (the last is the Haiku-generated digest the summarizer drops in).
    let role: String

    /// Plain-text content. nil when the message is tool-call/result only.
    let text: String?

    /// Set on assistant turns that emitted tool_use blocks. Each entry is
    /// the tool name + opaque-JSON input bytes the agent sent.
    let toolCalls: [PendingToolCall]?

    /// Set on user-role turns that bundle tool_result blocks for prior
    /// tool_use IDs.
    let toolResults: [ToolResult]?

    /// IDs of LearnedPreference rows the assistant cited via `[pref_<id>]`
    /// markers in the text. UI renders citation chips below the bubble.
    let citedPreferenceIDs: [UUID]?

    /// When this message was created.
    let timestamp: Date

    /// "haiku" | "sonnet" | "opus" | nil (nil for user messages).
    let model: String?

    init(
        role: String,
        text: String? = nil,
        toolCalls: [PendingToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        citedPreferenceIDs: [UUID]? = nil,
        timestamp: Date = Date(),
        model: String? = nil
    ) {
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.citedPreferenceIDs = citedPreferenceIDs
        self.timestamp = timestamp
        self.model = model
    }
}

// MARK: - PendingToolCall + ToolResult

/// Assistant-emitted tool_use intent. The opaque `inputJSON` carries the
/// per-tool arguments the agent loop deserializes + dispatches.
struct PendingToolCall: Codable, Equatable, Sendable {
    /// Anthropic-assigned id; round-trips back as `tool_use_id` on
    /// the matching `ToolResult`.
    let id: String
    let name: String
    /// Raw JSON bytes of the tool's input args (no shape constraint).
    let inputJSON: Data
}

/// User-role tool_result entry that closes the loop on a prior
/// PendingToolCall. `outputText` is the stringified output of the tool
/// (typically `ToolOutput.summary` + side-effects); `isError` flags
/// tool dispatch failures so the agent can self-recover next turn.
struct ToolResult: Codable, Equatable, Sendable {
    let toolUseID: String
    let outputText: String
    let isError: Bool
}
