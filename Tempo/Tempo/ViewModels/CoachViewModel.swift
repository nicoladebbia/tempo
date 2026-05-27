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
// The view (Phase 7b) binds to this VM with @Bindable. The interview
// gate logic also lives here — `shouldPresentInterview()` returns true
// when both `coachInterviewCompleted` and `coachInterviewSkipped` are
// false.
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
    private let interviewGateProvider: () -> InterviewGate

    // MARK: - Init

    init(
        service: CoachService,
        interviewGateProvider: @escaping () -> InterviewGate = { .needsInterview }
    ) {
        self.service = service
        self.interviewGateProvider = interviewGateProvider
    }

    // MARK: - Public — lifecycle

    /// Returns true when the chat view should present the interview sheet
    /// before letting the user type. Wired against UserSettings flags by
    /// the caller (Phase 7b's CoachTabView).
    func shouldPresentInterview() -> Bool {
        switch interviewGateProvider() {
        case .needsInterview: return true
        case .skipped, .completed: return false
        }
    }

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
        guard let conversation = activeConversation else {
            pendingError = "No active conversation."
            return
        }
        pendingError = nil
        isThinking = true
        defer { isThinking = false }
        do {
            let report = try await service.sendMessage(
                text,
                conversation: conversation,
                systemPrompt: systemPrompt,
                context: context
            )
            refreshMirror()
            refreshUndoLabel()
            switch report.capReached {
            case .turns, .toolCalls:
                pendingError = "I've hit my limit for this chat. End it to start fresh."
            case nil:
                break
            }
        } catch {
            // 503 from the backend means sub-cap exhausted.
            pendingError = mapError(error)
            if case .critical = budgetState {
                // already shown
            } else if Self.is503(error) {
                budgetState = .critical
            }
        }
    }

    /// Pops the last undo entry from the service. UI refresh after.
    func undoLast() async {
        _ = await service.undoLast()
        refreshUndoLabel()
    }

    /// Closes the active conversation. Caller (Phase 8) wires the
    /// post-chat extractor invocation here.
    func endConversation(context: ModelContext) {
        guard let conv = activeConversation else { return }
        conv.isActive = false
        try? context.save()
        service.clearUndoStack()
        activeConversation = nil
        messages = []
        undoLabel = nil
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
        return "Couldn't reach Coach. Tap to retry."
    }

    private static func is503(_ error: Error) -> Bool {
        // Best-effort detection — APIClient surfaces HTTP codes through
        // its own error types; this matches the public surface for v2.1.
        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("503") || description.contains("service unavailable")
            || description.contains("budget")
    }
}

// MARK: - InterviewGate

/// Snapshot of the interview gating flags. Caller (Phase 7b's
/// CoachTabView) computes from UserSettings and passes through.
enum InterviewGate: Equatable, Sendable {
    case needsInterview
    case completed
    case skipped
}
