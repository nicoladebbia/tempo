//
// CoachViewModel.swift
// Tempo
//
// Coach v2.1 Phase 7a — main-actor view model for the chat surface.
//
// Owns:
//   - The active CoachConversation (creates one on demand)
//   - A CoachService instance for the multi-turn loop
//   - Published messages / thinking / error / undo state for SwiftUI
//   - Budget banner state (caution / critical)
//
// The view (CoachChatView) binds to this VM with @Bindable.
//

import Foundation
import SwiftData

// MARK: - CoachViewModel

@MainActor
@Observable
final class CoachViewModel {
    // MARK: - State

    /// The chat thread the UI binds to. Lazily created on first
    /// `loadOrStartConversation` call. nil before that.
    private(set) var activeConversation: CoachConversation?

    /// Messages rendered by the chat view. Mirrors activeConversation.messages
    /// for SwiftUI reactivity (re-published on every sendMessage tick).
    private(set) var messages: [CoachMessage] = []

    /// True while a network turn is in flight.
    private(set) var isThinking: Bool = false

    /// Last error surfaced to the user (network / coding). nil when clear.
    var pendingError: String?

    /// Why the last turn was refused by the account rather than by the
    /// network: "AI is off" (consent) or "needs Pro". The chat shows an
    /// `AIBlockerCard` for it instead of the generic error banner.
    var blocker: AIBlocker?

    /// Label for the Undo button. nil when stack is empty.
    private(set) var undoLabel: String?

    /// Budget banner state. nil → no banner.
    private(set) var budgetState: BudgetState?

    /// "Pending review" preferences the agent should surface on next
    /// chat open (Phase 6c). Populated by `loadOrStartConversation`.
    private(set) var pendingReviewPreferenceIDs: [UUID] = []

    enum BudgetState: Equatable {
        /// Coach is approaching the monthly cap. UI shows a yellow banner.
        case caution
        /// Coach hit the cap. UI shows a red banner + disables input.
        case critical
    }

    // MARK: - Dependencies

    private let service: CoachService
    /// Post-chat preference extractor. Fired in a background Task on
    /// `endConversation`. nil → skip extraction (default; `CoachChat`
    /// injects a real APIClient-backed adapter).
    private let extractorClient: PreferenceExtractionAIClient?

    // MARK: - Init

    init(
        service: CoachService,
        extractorClient: PreferenceExtractionAIClient? = nil
    ) {
        self.service = service
        self.extractorClient = extractorClient
    }

    // MARK: - Public — lifecycle

    /// Loads or creates the active CoachConversation, refreshes the UI
    /// messages mirror, and reads the pending-review preferences queue
    /// so the agent can surface contradictions on the first turn.
    func loadOrStartConversation(context: ModelContext) {
        let descriptor = FetchDescriptor<CoachConversation>(
            predicate: #Predicate<CoachConversation> { $0.isActive }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            activeConversation = existing
        } else {
            let fresh = CoachConversation()
            context.insert(fresh)
            try? context.save()
            activeConversation = fresh
        }
        refreshMirror()
        pendingReviewPreferenceIDs = PreferenceHealthCheck
            .pendingReviewPreferences(in: context)
            .map(\.id)
    }

    // MARK: - Public — send

    /// Sends a user message through the agent loop. The system prompt
    /// is supplied by the caller (typically built by CoachContextAssembler
    /// at call time). Errors are captured into `pendingError`.
    func sendMessage(
        _ text: String,
        systemPrompt: String,
        context: ModelContext
    ) async {
        await send(text, systemPrompt: systemPrompt, context: context, appendUserMessage: true)
    }

    private func send(
        _ text: String,
        systemPrompt: String,
        context: ModelContext,
        appendUserMessage: Bool
    ) async {
        guard let conversation = activeConversation else {
            pendingError = "No active conversation."
            return
        }
        pendingError = nil
        blocker = nil
        isThinking = true
        defer { isThinking = false }
        do {
            let report = try await service.sendMessage(
                text,
                conversation: conversation,
                systemPrompt: systemPrompt,
                context: context,
                appendUserMessage: appendUserMessage
            )
            refreshMirror()
            refreshUndoLabel()
            switch report.capReached {
            case .turns,
                 .toolCalls:
                pendingError = "I've hit my limit for this chat. End it to start fresh."
            case nil:
                break
            }
        } catch {
            // The user's turn is already in the conversation (it is added
            // before the network call): show it, so a retry doesn't look like
            // a second message.
            refreshMirror()
            if let blocked = AIBlocker(error) {
                // Not a failure: the account has to allow it first. The
                // message stays in the transcript and is sent again after.
                blocker = blocked
                return
            }
            // 503 from the backend means sub-cap exhausted.
            pendingError = mapError(error)
            if case .critical = budgetState {
                // already shown
            } else if Self.is503(error) {
                budgetState = .critical
            }
        }
    }

    /// True when the last turn went unanswered: the conversation ends on the
    /// user's own message (or a tool result) and an error is showing, so
    /// "Retry" has something to resend.
    var canRetry: Bool {
        (pendingError != nil || blocker != nil) && !isThinking
            && Self.lastUnansweredUserText(in: activeConversation?.messages ?? []) != nil
    }

    /// Asks again for the turn that failed, without adding the user's message
    /// a second time (it is already in the transcript).
    func retryLast(systemPrompt: String, context: ModelContext) async {
        guard !isThinking,
              let conversation = activeConversation,
              let text = Self.lastUnansweredUserText(in: conversation.messages)
        else {
            return
        }
        await send(text, systemPrompt: systemPrompt, context: context, appendUserMessage: false)
    }

    /// The text of the user's last typed message when nothing answered it.
    /// nil when the conversation ends on an assistant turn (nothing to retry).
    static func lastUnansweredUserText(in messages: [CoachMessage]) -> String? {
        guard let last = messages.last, last.role == "user" else {
            return nil
        }
        return messages.last(where: { $0.role == "user" && $0.text?.isEmpty == false })?.text
    }

    /// Pops the last undo entry from the service. UI refresh after.
    func undoLast() async {
        _ = await service.undoLast()
        refreshUndoLabel()
    }

    /// Closes the active conversation. Caller (Phase 8) wires the
    /// post-chat extractor invocation here.
    func endConversation(context: ModelContext) {
        guard let conv = activeConversation else {
            return
        }
        conv.isActive = false
        // Snapshot the transcript before clearing — extractor runs in a
        // background Task and shouldn't race UI state.
        let transcript = Self.transcript(from: conv)
        try? context.save()
        service.clearUndoStack()
        activeConversation = nil
        messages = []
        undoLabel = nil

        if let extractorClient {
            // Silent fire-and-forget per the Phase 4c spec ("silent log +
            // skip, don't retry"). RunReport is logged for debugging but
            // not surfaced to UI — Phase 8 PostHog logs the count.
            Task { [extractorClient] in
                _ = try? await PreferenceExtractor.extract(
                    from: transcript,
                    using: extractorClient,
                    context: context
                )
            }
        }
    }

    /// Builds a CoachTranscript from a finished conversation. Skips any
    /// system_summary pseudo-messages — they're not user/agent turns.
    static func transcript(from conversation: CoachConversation) -> CoachTranscript {
        let turns = conversation.messages.compactMap { msg -> CoachTranscript.Turn? in
            guard msg.role == "user" || msg.role == "assistant" else {
                return nil
            }
            guard let text = msg.text, !text.isEmpty else {
                return nil
            }
            return CoachTranscript.Turn(role: msg.role, text: text)
        }
        return CoachTranscript(id: conversation.id, turns: turns)
    }

    /// Manually set budget state (e.g., from a "AI usage" event coming
    /// off the backend log). UI binds to this.
    func setBudgetState(_ state: BudgetState?) {
        budgetState = state
    }

    // MARK: - Private

    private func refreshMirror() {
        messages = activeConversation?.messages ?? []
    }

    private func refreshUndoLabel() {
        undoLabel = service.undoStack.last?.description
    }

    private func mapError(_ error: Error) -> String {
        if Self.is503(error) {
            return "Coach is at this month's limit — back in a few days."
        }
        return "Couldn't reach Coach."
    }

    private static func is503(_ error: Error) -> Bool {
        // Best-effort detection — APIClient surfaces HTTP codes through
        // its own error types; this matches the public surface for v2.1.
        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("503") || description.contains("service unavailable")
            || description.contains("budget")
    }
}
