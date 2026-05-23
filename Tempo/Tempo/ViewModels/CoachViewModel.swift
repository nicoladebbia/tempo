//
// CoachViewModel.swift
// Tempo
//
// Drives `CoachChatView`. Owns the current `CoachConversation`, holds
// transient UI state (input text, isThinking, errorBanner, undoLabel),
// and delegates the heavy lifting to `CoachService`. View-model lives on
// the main actor because every property feeds straight into SwiftUI.
//
// Per `.plans/coach-agent-plan.md` Phase 7.
//

import Foundation
import OSLog
import SwiftData

@MainActor
@Observable
final class CoachViewModel {

    // MARK: - View state

    /// Current draft in the input bar.
    var inputText: String = ""

    /// True while a turn is in flight. UI disables the input bar and
    /// shows a thinking indicator.
    private(set) var isThinking: Bool = false

    /// Non-nil when the agent ran `ask_user` — UI surfaces the question
    /// + optional choice chips. The next user message is the answer.
    private(set) var pendingQuestion: PendingQuestion?

    /// Last error to surface as a dismissible banner.
    private(set) var errorBanner: String?

    /// Visible turns rendered as chat bubbles. Derived from
    /// `conversation.turns()` filtered to skip tool_result-only turns
    /// (those are agent plumbing, not user-facing content).
    private(set) var displayTurns: [DisplayTurn] = []

    /// Active conversation. Nil before `startConversation` runs.
    private(set) var conversation: CoachConversation?

    /// Cached undo label from the underlying service.
    var undoLabel: String? { service.undoLabel }

    // MARK: - Dependencies

    private let service: CoachService
    private let extractor: PreferenceExtractor
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.tempo.app", category: "CoachViewModel")

    // MARK: - Init

    init(
        apiClient: APIClient,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) {
        self.modelContext = modelContext
        self.service = CoachService(
            apiClient: apiClient,
            modelContext: modelContext,
            notifications: notifications
        )
        self.extractor = PreferenceExtractor(apiClient: apiClient)
    }

    // MARK: - Conversation lifecycle

    /// Start a new conversation. Persists the CoachConversation so it
    /// shows up in history even if the user backgrounds the app mid-session.
    func startConversation() {
        let convo = CoachConversation()
        modelContext.insert(convo)
        try? modelContext.save()
        self.conversation = convo
        self.displayTurns = []
        self.pendingQuestion = nil
        self.errorBanner = nil
    }

    /// End the current conversation. Fires the PreferenceExtractor in
    /// the background so the next session has fresh memory.
    func endConversation() async {
        guard let convo = conversation else { return }
        await service.end(conversation: convo, extractor: extractor)
        conversation = nil
        displayTurns = []
    }

    // MARK: - Send

    /// Send the current `inputText` (or `override` when provided, e.g.
    /// from a choice chip). Updates display turns + thinking flag.
    func send(_ override: String? = nil) async {
        let raw = (override ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if conversation == nil { startConversation() }
        guard let convo = conversation else { return }

        // Optimistic append so the bubble appears before the response.
        displayTurns.append(DisplayTurn(role: .user, text: raw, citedPreferenceIDs: []))
        inputText = ""
        isThinking = true
        pendingQuestion = nil
        errorBanner = nil

        do {
            let result = try await service.send(userMessage: raw, conversation: convo)
            displayTurns.append(DisplayTurn(
                role: .assistant,
                text: result.text,
                citedPreferenceIDs: result.citedPreferenceIDs
            ))
            pendingQuestion = result.pendingQuestion
        } catch {
            logger.error("Coach send failed: \(error.localizedDescription)")
            errorBanner = error.localizedDescription
        }
        isThinking = false
    }

    /// Apply the single-step undo and surface a toast label.
    @discardableResult
    func undoLast() -> String? {
        let label = service.undoLast()
        if let label {
            displayTurns.append(DisplayTurn(role: .system, text: "Undid: \(label)", citedPreferenceIDs: []))
        }
        return label
    }

    func dismissError() { errorBanner = nil }
}

// MARK: - Display types

struct DisplayTurn: Identifiable, Equatable {
    enum Role { case user, assistant, system }

    let id = UUID()
    let role: Role
    let text: String
    let citedPreferenceIDs: [UUID]
}
