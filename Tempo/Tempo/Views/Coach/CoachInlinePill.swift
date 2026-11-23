//
// CoachInlinePill.swift
// Tempo
//
// Coach v2.1 Phase 7c — small "Ask Coach" pill rendered on Training,
// Nutrition Today, and Recovery tab headers. Tapping opens
// `CoachChatView` in a half-height bottom sheet with a hidden context
// message preset for the tab. Continues the active conversation
// rather than forking a new one — same `CoachConversation`, same VM.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §6 + the locked Q7 decision
// (3 pills only: Training, Nutrition Today, Recovery — not Dashboard
// / Lockdown / Arena).
//

import SwiftData
import SwiftUI

// MARK: - CoachInlinePillSource

/// Identifies which tab opened the pill. The chat sheet uses this to
/// inject a one-time hidden context message ("user opened Coach from
/// Training tab. Today's planned workout: …").
enum CoachInlinePillSource: String, Sendable, CaseIterable {
    case training
    case nutritionToday
    case recovery

    var tabLabel: String {
        switch self {
        case .training: return "Training"
        case .nutritionToday: return "Nutrition Today"
        case .recovery: return "Recovery"
        }
    }
}

// MARK: - CoachInlinePill

/// Small reusable pill. Drop into a tab header HStack:
///
///     HStack {
///         Text("Training").font(Tide.title)
///         Spacer()
///         CoachInlinePill(source: .training) { snapshot, viewModel in
///             // Build the system prompt for chat — caller wires the
///             // assembler. Snapshot is the per-tab context blurb.
///             return chatSheet(prompt: snapshot, viewModel: viewModel)
///         }
///     }
struct CoachInlinePill: View {
    let source: CoachInlinePillSource
    /// Tapped → sheet open.
    let onTap: () -> Void

    var body: some View {
        TideChip(title: "Ask Coach", systemImage: "bubble.left.and.bubble.right.fill", action: onTap)
            .accessibilityLabel(Text("Ask Coach about \(source.tabLabel)"))
    }
}

// MARK: - CoachInlineChatSheet

/// Half-height sheet wrapping CoachChatView with a "Asking from …"
/// subtitle banner. Caller passes:
///   • a CoachViewModel (continues the active conversation)
///   • a context blurb string the assembler/system-prompt should
///     prepend so the agent knows which tab the user came from.
struct CoachInlineChatSheet: View {
    let source: CoachInlinePillSource
    let contextBlurb: String
    @Bindable var viewModel: CoachViewModel
    let systemPromptBuilder: () -> String
    var voice: any CoachVoiceControlling = CoachVoiceController()
    var voiceMode: CoachVoiceMode = .tapToggle

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Asking from \(source.tabLabel)").tideLabel()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s5)
            .padding(.bottom, Tide.s1)

            CoachChatView(
                viewModel: viewModel,
                systemPromptBuilder: { contextAwareSystemPrompt() },
                voice: voice,
                voiceMode: voiceMode
            )
        }
        .tidePage()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Prepends the per-tab hint to whatever the base builder returns.
    /// One-shot per sheet open is enforced by the caller wiring this
    /// onAppear-once — but even if it fires multiple times the agent
    /// sees the same hint and the cost is one cached token block.
    private func contextAwareSystemPrompt() -> String {
        let base = systemPromptBuilder()
        let hint = """
        <inline_context>
        \(contextBlurb)
        </inline_context>
        """
        return hint + "\n\n" + base
    }
}
