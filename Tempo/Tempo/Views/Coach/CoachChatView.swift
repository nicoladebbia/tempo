//
// CoachChatView.swift
// Tempo
//
// Coach v2.1 Phase 7b — the chat surface.
//
// Owns the transcript, the input bar, and the budget banner. Binds to
// CoachViewModel for state. Calls into the VM for sendMessage / undo /
// endConversation. Caller (Phase 7c CoachTabView) wires in the system
// prompt by assembling fresh on every tap via CoachContextAssembler.
//
// Voice input (mic button + recording state) lands in Phase 7c —
// CoachInputBar exposes a placeholder onMicTap handler so 7c can drop
// in the VoiceTranscriber adapter without re-touching this file.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §2.
//

import SwiftData
import SwiftUI

// MARK: - CoachChatView

struct CoachChatView: View {
    @Bindable var viewModel: CoachViewModel
    /// System prompt builder invoked at send-time. The owning view
    /// (Phase 7c CoachTabView) injects a closure that calls
    /// CoachContextAssembler with the live context.
    let systemPromptBuilder: () -> String
    /// Three empty-state seed prompts (mix: simple / deeper / preference-teach
    /// per the v2.1 plan answers). Caller can override; default below.
    var emptyStateSeeds: [String] = CoachChatView.defaultSeeds
    /// Voice controller. Defaults to the real VoiceTranscriber adapter;
    /// tests and previews inject `StubCoachVoiceController`.
    var voice: any CoachVoiceControlling
    /// Mic interaction mode. Sourced from UserSettings.coachVoiceMode
    /// at the call site; default tapToggle per the locked Q2 decision.
    var voiceMode: CoachVoiceMode = .tapToggle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @State private var endChatConfirm = false
    /// Snapshot of the last partial transcript pushed into the field so
    /// the user can still type alongside the live mic stream without
    /// having the field overwritten on every partial tick.
    @State private var lastVoicePartial: String = ""

    init(
        viewModel: CoachViewModel,
        systemPromptBuilder: @escaping () -> String,
        emptyStateSeeds: [String] = CoachChatView.defaultSeeds,
        voice: any CoachVoiceControlling = CoachVoiceController(),
        voiceMode: CoachVoiceMode = .tapToggle
    ) {
        self.viewModel = viewModel
        self.systemPromptBuilder = systemPromptBuilder
        self.emptyStateSeeds = emptyStateSeeds
        self.voice = voice
        self.voiceMode = voiceMode
    }

    /// Default empty-state seeds — one simple action, one deeper ask,
    /// one preference-teaching example per the locked Q3 design.
    static let defaultSeeds: [String] = [
        "soccer at 7pm tonight",
        "I'm tired this week, help me ease off",
        "fyi I never eat before 11am",
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let state = viewModel.budgetState {
                budgetBanner(state)
            }
            transcript
            aiDisclaimer
            CoachInputBar(
                text: $inputText,
                isThinking: viewModel.isThinking,
                isRecording: voice.isListening,
                isDisabled: viewModel.budgetState == .critical,
                onSend: { send() },
                onMicPressBegan: { handleMicPressBegan() },
                onMicPressEnded: { handleMicPressEnded() }
            )
            .onChange(of: voice.transcribedText) { _, newValue in
                pushVoicePartialIntoField(newValue)
            }
            .onChange(of: voice.isListening) { _, listening in
                if !listening { lastVoicePartial = "" }
            }
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
        .alert("End this chat?", isPresented: $endChatConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                viewModel.endConversation(context: modelContext)
                dismiss()
            }
        } message: {
            Text("I'll save what we discussed and start fresh next time.")
        }
        .onAppear {
            viewModel.loadOrStartConversation(context: modelContext)
        }
        .alert(
            "Couldn't reach Coach",
            isPresented: .init(
                get: { viewModel.pendingError != nil },
                set: { if !$0 { viewModel.pendingError = nil } }
            )
        ) {
            Button("OK") { viewModel.pendingError = nil }
        } message: {
            Text(viewModel.pendingError ?? "")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: TempoSpacing.md) {
            Text("Coach")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            if let undoLabel = viewModel.undoLabel {
                Button {
                    Task { await viewModel.undoLast() }
                } label: {
                    Label(undoLabel, systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(Text(undoLabel))
                }
                .buttonStyle(.tempoGhost)
            }
            Button(role: .destructive) {
                endChatConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel(Text("End chat"))
            }
            .buttonStyle(.tempoGhost)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
    }

    // MARK: - Budget banner

    private func budgetBanner(_ state: CoachViewModel.BudgetState) -> some View {
        let copy: String
        let bg: Color
        let fg: Color
        switch state {
        case .caution:
            copy = "Coach is at 80% of this month's budget."
            bg = Color.tempoAmber.opacity(0.18)
            fg = Color.tempoAmber
        case .critical:
            copy = "Coach is at this month's limit — back in a few days."
            bg = Color.tempoError.opacity(0.18)
            fg = Color.tempoError
        }
        return HStack(spacing: TempoSpacing.sm) {
            Image(systemName: state == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(fg)
            Text(copy)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(bg)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if viewModel.messages.isEmpty && !viewModel.isThinking {
            CoachEmptyState(seeds: emptyStateSeeds) { seed in
                inputText = seed
                send()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TempoSpacing.md) {
                        ForEach(visibleMessages, id: \.id) { wrapper in
                            messageRow(wrapper.message)
                                .id(wrapper.id)
                        }
                        if viewModel.isThinking {
                            CoachThinkingBubble()
                                .id("thinking")
                        }
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.vertical, TempoSpacing.md)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: viewModel.isThinking) { _, newValue in
                    if newValue {
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Visible messages (filters system_summary)

    private var visibleMessages: [IdentifiedMessage] {
        viewModel.messages
            .enumerated()
            .filter { _, msg in msg.role != "system_summary" }
            .map { idx, msg in IdentifiedMessage(id: idx, message: msg) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = visibleMessages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    // MARK: - One message row (dispatches by role)

    @ViewBuilder
    private func messageRow(_ message: CoachMessage) -> some View {
        switch message.role {
        case "user":
            // User-role messages with toolResults are protocol housekeeping
            // (the agent's tool_result block) — don't render them.
            if let text = message.text, !text.isEmpty {
                CoachUserBubble(text: text)
            }
        case "assistant":
            // The agent may emit a text block + a tool_use; the text is shown
            // here, the tool_result card comes in a later message after dispatch.
            if let text = message.text, !text.isEmpty {
                // askUser tool calls present as a pending question bubble
                // ahead of the next-turn dispatch summary; the agent's
                // text usually mirrors the question already, so we just
                // render the assistant bubble + question chips if any
                // tool calls are askUser.
                CoachAssistantBubble(text: text)
                if let pending = extractAskUser(from: message.toolCalls) {
                    CoachPendingQuestionBubble(
                        question: pending.question,
                        choices: pending.choices
                    ) { choice in
                        inputText = choice
                        send()
                    }
                }
            }
        case "tool_result":
            // Tool-result bundles arrive as user-role messages with
            // toolResults, NOT as their own role. Kept here for future
            // dedicated tool-result inline rendering.
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func extractAskUser(from toolCalls: [PendingToolCall]?) -> CoachAskUserPayload? {
        guard let calls = toolCalls else { return nil }
        for call in calls where call.name == "askUser" {
            if let parsed = try? JSONDecoder().decode(AskUserPayload.self, from: call.inputJSON) {
                return CoachAskUserPayload(
                    question: parsed.question,
                    choices: parsed.choices ?? []
                )
            }
        }
        return nil
    }

    // MARK: - AI disclaimer footer

    private var aiDisclaimer: some View {
        Text("AI-generated guidance. Not medical advice. Consult a professional.")
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.tempoBgPrimary)
    }

    // MARK: - Voice

    /// `onMicPressBegan` is fired by the input bar:
    ///   - tap-toggle mode: on first tap (toggles start), on second tap
    ///     (signals stop — the input bar suppresses the began event).
    ///   - hold-to-record mode: on touch-down. The matching
    ///     `onMicPressEnded` fires on lift to stop.
    private func handleMicPressBegan() {
        if voice.isListening {
            // Already listening → tap-toggle stops; hold-to-record path
            // doesn't hit this branch because hold uses the gesture-end
            // callback to stop.
            voice.stop()
            return
        }
        Task { await voice.start() }
    }

    /// Fired only by hold-to-record mode when the user lifts their
    /// finger. Tap-toggle ignores this (start/stop both come through
    /// `onMicPressBegan`).
    private func handleMicPressEnded() {
        guard voiceMode == .holdToRecord else { return }
        voice.stop()
    }

    /// Merge live voice partials into the text field without clobbering
    /// what the user has already typed. We track the last partial we
    /// pushed in so subsequent partials replace just that suffix.
    private func pushVoicePartialIntoField(_ partial: String) {
        guard voice.isListening else { return }
        // Strip the previous partial off the tail (if present), then
        // append the new partial. This lets the user keep manual edits
        // on the prefix while voice continues to extend the tail.
        var base = inputText
        if !lastVoicePartial.isEmpty, base.hasSuffix(lastVoicePartial) {
            base.removeLast(lastVoicePartial.count)
        }
        inputText = base + partial
        lastVoicePartial = partial
    }

    // MARK: - Send action

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if voice.isListening { voice.stop() }
        inputText = ""
        lastVoicePartial = ""
        Task {
            await viewModel.sendMessage(
                text,
                systemPrompt: systemPromptBuilder(),
                context: modelContext
            )
        }
    }
}

// MARK: - IdentifiedMessage (stable id for ForEach)

private struct IdentifiedMessage: Identifiable, Equatable {
    let id: Int
    let message: CoachMessage
}

// MARK: - AskUserPayload (decode shape)

private struct AskUserPayload: Decodable {
    let question: String
    let choices: [String]?
}

private struct CoachAskUserPayload {
    let question: String
    let choices: [String]
}

// MARK: - CoachUserBubble

struct CoachUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: TempoSpacing.xxl)
            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextInverse)
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                        .fill(Color.tempoSignal)
                )
        }
    }
}

// MARK: - CoachAssistantBubble

struct CoachAssistantBubble: View {
    let text: String

    /// Strip [pref_xxxx] citation markers from the visible body so the
    /// text reads cleanly. Phase 7c (when citation chips are wired to
    /// real LearnedPreference lookups) renders them as tappable rows
    /// below the bubble.
    private var displayText: String {
        CoachMessageRenderer.strippingCitationMarkers(text)
    }

    var body: some View {
        HStack {
            Text(displayText)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                        .fill(Color.tempoSurfaceCard)
                )
            Spacer(minLength: TempoSpacing.xxl)
        }
    }
}

// MARK: - CoachToolResultCard

struct CoachToolResultCard: View {
    let summary: String
    let isError: Bool
    var detail: String?

    @State private var expanded = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                        .foregroundStyle(isError ? Color.tempoError : Color.tempoSuccess)
                    Text(summary)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    if detail != nil {
                        Button {
                            withAnimation { expanded.toggle() }
                        } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if expanded, let detail {
                    Text(detail)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                    .strokeBorder(
                        isError ? Color.tempoError.opacity(0.4) : Color.tempoSuccess.opacity(0.4),
                        lineWidth: 1
                    )
                    .background(Color.tempoSurfaceCard.opacity(0.6))
            )
            Spacer(minLength: TempoSpacing.xxl)
        }
    }
}

// MARK: - CoachPendingQuestionBubble

struct CoachPendingQuestionBubble: View {
    let question: String
    let choices: [String]
    let onChoiceTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text(question)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
            }
            if !choices.isEmpty {
                FlowLayout(spacing: TempoSpacing.xs, lineSpacing: TempoSpacing.xs) {
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { onChoiceTap(choice) }
                            .buttonStyle(.tempoSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                .strokeBorder(Color.tempoSignal.opacity(0.4), lineWidth: 1)
                .background(Color.tempoSurfaceCard)
        )
    }
}

// MARK: - CoachThinkingBubble

struct CoachThinkingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: TempoSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.tempoSignal)
                Text("Thinking…")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                    .fill(Color.tempoSurfaceCard)
            )
            Spacer(minLength: TempoSpacing.xxl)
        }
        .accessibilityLabel(Text("Coach is thinking"))
    }
}

// MARK: - CoachEmptyState

struct CoachEmptyState: View {
    let seeds: [String]
    let onSeedTap: (String) -> Void

    var body: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Text("👋")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("I know enough to start. Try one of these,\nor say something else.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)
            VStack(spacing: TempoSpacing.sm) {
                ForEach(seeds, id: \.self) { seed in
                    Button { onSeedTap(seed) } label: {
                        HStack {
                            Text(seed)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        .padding(.horizontal, TempoSpacing.md)
                        .padding(.vertical, TempoSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                                .strokeBorder(Color.tempoSteel.opacity(0.4), lineWidth: 1)
                                .background(Color.tempoSurfaceCard)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CoachInputBar

struct CoachInputBar: View {
    @Binding var text: String
    let isThinking: Bool
    /// Read-only flag mirroring the voice controller's `isListening`.
    let isRecording: Bool
    let isDisabled: Bool
    let onSend: () -> Void
    /// Fires on tap-down. Tap-toggle interprets this as start/stop.
    let onMicPressBegan: () -> Void
    /// Fires on touch release. Hold-to-record uses this to stop;
    /// tap-toggle ignores it.
    let onMicPressEnded: () -> Void

    var body: some View {
        HStack(spacing: TempoSpacing.sm) {
            micButton

            TextField("Type a message…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, TempoSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                        .fill(Color.tempoSurfaceCard)
                )
                .submitLabel(.send)
                .onSubmit { onSend() }
                .disabled(isDisabled || isThinking)

            Button { onSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(
                        canSend ? Color.tempoSignal : Color.tempoTextDisabled
                    )
                    .accessibilityLabel(Text("Send message"))
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isDisabled || isThinking)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.tempoSteel.opacity(0.2))
                .frame(height: 0.5)
        }
    }

    private var micButton: some View {
        // The same view powers both modes. Tap-toggle uses the regular
        // tap action (Began fires once). Hold-to-record relies on a
        // DragGesture(minimumDistance: 0) to differentiate press vs
        // release so the caller can map .ended → stop.
        Image(systemName: isRecording ? "mic.fill" : "mic")
            .foregroundStyle(isRecording ? Color.tempoError : Color.tempoTextSecondary)
            .imageScale(.large)
            .accessibilityLabel(Text(isRecording ? "Stop recording" : "Start recording"))
            .padding(.horizontal, TempoSpacing.xs)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressInFlight else { return }
                        pressInFlight = true
                        if !isDisabled { onMicPressBegan() }
                    }
                    .onEnded { _ in
                        pressInFlight = false
                        if !isDisabled { onMicPressEnded() }
                    }
            )
    }

    @State private var pressInFlight: Bool = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// Note: `FlowLayout` is defined in Tempo/Tempo/Views/Dashboard/DashboardView.swift
// and reused here for the askUser choice-chip row via `FlowLayout(spacing:
// lineSpacing:)`.
