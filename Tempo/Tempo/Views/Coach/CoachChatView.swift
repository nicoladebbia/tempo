//
// CoachChatView.swift
// Tempo
//
// Coach v2.1 Phase 7b — the chat surface.
//
// Owns the transcript, the input bar, and the budget banner. Binds to
// CoachViewModel for state. Calls into the VM for sendMessage / undo /
// endConversation. `CoachChat` wires in the system prompt by assembling
// fresh on every send via CoachContextAssembler.
//
// Drawn in Tide: Coach talks in glass bubbles, you talk in accent-filled
// ones, and the input bar floats in glass over the transcript.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §2.
//

import SwiftData
import SwiftUI

// MARK: - CoachChatView

struct CoachChatView: View {
    @Bindable var viewModel: CoachViewModel
    /// System prompt builder invoked at send-time. The owning view
    /// (`CoachChat`) injects a closure that calls
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
    /// The name in the top bar and the empty state ("Ask Tempo" from the "+" sheet).
    var title: String = "Coach"

    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var inputText: String = ""
    /// "Chat cleared" with Undo, shown over the transcript, never over the input.
    @State
    private var toast: ToastData?
    /// Snapshot of the last partial transcript pushed into the field so
    /// the user can still type alongside the live mic stream without
    /// having the field overwritten on every partial tick.
    @State
    private var lastVoicePartial: String = ""
    /// What you just sent, shown until the transcript catches up (it only
    /// updates when Coach has answered), or kept if the answer never came.
    @State
    private var pendingText: String?
    @State
    private var pendingBaseCount = 0

    init(
        viewModel: CoachViewModel,
        systemPromptBuilder: @escaping () -> String,
        emptyStateSeeds: [String] = CoachChatView.defaultSeeds,
        voice: any CoachVoiceControlling = CoachVoiceController(),
        voiceMode: CoachVoiceMode = .tapToggle,
        title: String = "Coach"
    ) {
        self.viewModel = viewModel
        self.systemPromptBuilder = systemPromptBuilder
        self.emptyStateSeeds = emptyStateSeeds
        self.voice = voice
        self.voiceMode = voiceMode
        self.title = title
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
                // Top of the transcript: under the title bar, clear of the input bar.
                .tempoToast($toast, placement: .top)
                // On the transcript, so it rests above the input bar instead of under it.
                .firstTip("coach.chat", "Ask a question, or tell me something to remember, like \"I never eat before 11am\".", systemImage: "sparkles")
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        }
        .animation(reduceMotion ? nil : Tide.snap, value: viewModel.pendingError)
        .animation(reduceMotion ? nil : Tide.snap, value: viewModel.blocker)
        .onChange(of: viewModel.pendingError) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .tidePage()
        .onAppear {
            viewModel.loadOrStartConversation(context: modelContext)
        }
        // A toast that ran out (or was swiped away) without Undo makes the clear final.
        .onChange(of: toast) { _, newValue in
            if newValue == nil {
                viewModel.commitPendingEnd()
            }
        }
        // So does leaving the chat: there is no toast left to undo from.
        .onDisappear { viewModel.commitPendingEnd() }
    }

    /// Clears the chat at once; the toast brings it back. An empty chat has
    /// nothing to bring back, so the button just closes it.
    private func endChat() {
        if viewModel.endConversationWithUndo(context: modelContext) {
            // The message you were waiting on is in the transcript; what you were typing stays.
            pendingText = nil
            toast = ToastData(message: "Chat cleared.", style: .info, actionTitle: "Undo") {
                viewModel.undoEnd()
            }
        } else {
            dismiss()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Tide.s3) {
            TideCoachAvatar()
            Text(title)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tide.s2)
            GlassEffectContainer(spacing: Tide.s2) {
                HStack(spacing: Tide.s2) {
                    if let undoLabel = viewModel.undoLabel {
                        Button {
                            Task { await viewModel.undoLast() }
                        } label: {
                            Label(undoLabel, systemImage: "arrow.uturn.backward")
                                .labelStyle(.iconOnly)
                                .accessibilityLabel(Text(undoLabel))
                        }
                        .buttonStyle(.tideCoachCircle)
                    }
                    Button(role: .destructive) {
                        endChat()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel(Text("End chat"))
                    }
                    .buttonStyle(.tideCoachCircle)
                }
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.vertical, Tide.s2)
    }

    // MARK: - Budget banner

    private func budgetBanner(_ state: CoachViewModel.BudgetState) -> some View {
        let copy: String
        let tint: Color
        switch state {
        case .caution:
            copy = "Coach is at 80% of this month's budget."
            tint = Tide.streak
        case .critical:
            copy = "Coach hit this month's limit. Back in a few days."
            tint = Tide.danger
        }
        return HStack(spacing: Tide.s3) {
            Image(systemName: state == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(copy)
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.22)), in: .rect(cornerRadius: Tide.tileRadius))
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Transcript

    /// "Ask Coach anything", and "Ask Tempo anything" for a screen already titled "Ask Tempo".
    private var emptyHeading: String {
        title.hasPrefix("Ask ") ? "\(title) anything" : "Ask \(title) anything"
    }

    @ViewBuilder
    private var transcript: some View {
        if viewModel.messages.isEmpty, !viewModel.isThinking, pendingBubbleText == nil {
            CoachEmptyState(seeds: emptyStateSeeds, heading: emptyHeading) { seed in
                inputText = seed
                send()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tide.s3) {
                        ForEach(visibleMessages, id: \.id) { wrapper in
                            transcriptEntry(wrapper)
                                .id(wrapper.id)
                                .transition(rowTransition)
                        }
                        if let pendingBubbleText {
                            CoachUserBubble(text: pendingBubbleText)
                                .id("pending")
                                .transition(rowTransition)
                        }
                        if viewModel.isThinking {
                            CoachThinkingBubble()
                                .id("thinking")
                                .transition(rowTransition)
                        }
                    }
                    .animation(reduceMotion ? nil : Tide.snap, value: viewModel.messages.count)
                    .animation(reduceMotion ? nil : Tide.snap, value: viewModel.isThinking)
                    .padding(.horizontal, Tide.edge)
                    .padding(.vertical, Tide.s3)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(Tide.snap) { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: viewModel.isThinking) { _, newValue in
                    if newValue {
                        withAnimation(Tide.snap) { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
            }
        }
    }

    /// The message to show right now, if the transcript hasn't picked it up yet.
    private var pendingBubbleText: String? {
        guard let pendingText, viewModel.messages.count <= pendingBaseCount else {
            return nil
        }
        return pendingText
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Tide.s2))
    }

    // MARK: - Bottom bar

    /// The input bar and the disclaimer under it. Messages scroll beneath.
    private var bottomBar: some View {
        VStack(spacing: Tide.s2) {
            if let blocker = viewModel.blocker {
                // AI is off or needs Pro: say so here, with the one button
                // that fixes it. After consent the unanswered message is sent again.
                AIBlockerCard(blocker: blocker) {
                    Task {
                        await viewModel.retryLast(systemPrompt: systemPromptBuilder(), context: modelContext)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .transition(rowTransition)
            } else if let message = viewModel.pendingError {
                errorBanner(message)
                    .transition(rowTransition)
            }
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
                if !listening {
                    lastVoicePartial = ""
                }
            }
            aiDisclaimer
        }
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s1)
    }

    // MARK: - Error banner

    /// Why the last message didn't get an answer, in place of a pop-up. Your
    /// message stays in the transcript; the banner just says what happened.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tide.s2)
            if viewModel.canRetry {
                Button("Retry") {
                    Task {
                        await viewModel.retryLast(systemPrompt: systemPromptBuilder(), context: modelContext)
                    }
                }
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
                .accessibilityIdentifier("coachRetryButton")
            }
            Button {
                viewModel.pendingError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, Tide.s4)
        .padding(.vertical, Tide.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Tide.danger.opacity(0.22)), in: .rect(cornerRadius: Tide.tileRadius))
        .padding(.horizontal, Tide.edge)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Visible messages (filters system_summary)

    /// What the transcript shows, with where each message sits in the page: a
    /// day heading above the first message of a day, Coach's mark on the first
    /// bubble of a run, the time under the last.
    private var visibleMessages: [IdentifiedMessage] {
        // Only what draws something: runs and times are worked out over these,
        // so a hidden tool_result message never splits a run.
        let kept = viewModel.messages
            .enumerated()
            .filter { _, msg in
                (msg.role == "user" || msg.role == "assistant") && msg.text?.isEmpty == false
            }
        let calendar = Calendar.current
        return kept.enumerated().map { position, entry in
            let message = entry.element
            let previous = position > 0 ? kept[position - 1].element : nil
            let next = position + 1 < kept.count ? kept[position + 1].element : nil
            let startsDay = previous.map { !calendar.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? true
            return IdentifiedMessage(
                id: entry.offset,
                message: message,
                dayHeading: startsDay ? message.timestamp : nil,
                startsRun: previous?.role != message.role || startsDay,
                endsRun: next?.role != message.role
                    || next.map { !calendar.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? false
            )
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = visibleMessages.last else {
            return
        }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    // MARK: - One message row (dispatches by role)

    /// A message with the day heading and the time that belong to it.
    @ViewBuilder
    private func transcriptEntry(_ entry: IdentifiedMessage) -> some View {
        let isVisible = entry.message.text?.isEmpty == false
        VStack(alignment: .leading, spacing: Tide.s1) {
            if let day = entry.dayHeading {
                TideCoachDaySeparator(date: day)
                    .padding(.vertical, Tide.s2)
            }
            messageRow(entry.message, showsAvatar: entry.startsRun)
            if entry.endsRun, isVisible, entry.message.role == "user" || entry.message.role == "assistant" {
                Text(entry.message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: entry.message.role == "user" ? .trailing : .leading)
                    .padding(.leading, entry.message.role == "user" ? 0 : TideCoachAvatar.inset(for: typeSize))
                    .padding(.bottom, Tide.s1)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: CoachMessage, showsAvatar: Bool) -> some View {
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
                CoachAssistantBubble(text: text, showsAvatar: showsAvatar)
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
        guard let calls = toolCalls else {
            return nil
        }
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
            .font(Tide.label)
            .foregroundStyle(Tide.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Tide.edge)
            .frame(maxWidth: .infinity, alignment: .center)
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
        guard voiceMode == .holdToRecord else {
            return
        }
        voice.stop()
    }

    /// Merge live voice partials into the text field without clobbering
    /// what the user has already typed. We track the last partial we
    /// pushed in so subsequent partials replace just that suffix.
    private func pushVoicePartialIntoField(_ partial: String) {
        guard voice.isListening else {
            return
        }
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
        guard !text.isEmpty else {
            return
        }
        if voice.isListening {
            voice.stop()
        }
        inputText = ""
        lastVoicePartial = ""
        pendingText = text
        pendingBaseCount = viewModel.messages.count
        Task {
            await viewModel.sendMessage(
                text,
                systemPrompt: systemPromptBuilder(),
                context: modelContext
            )
            // Sent and answered: the real message is in the transcript now.
            if viewModel.pendingError == nil {
                pendingText = nil
            }
        }
    }
}

// MARK: - IdentifiedMessage

private struct IdentifiedMessage: Identifiable, Equatable {
    let id: Int
    let message: CoachMessage
    /// Set on the first message of a day: the day to show above it.
    var dayHeading: Date?
    /// First message of a run from the same speaker (Coach's mark goes here).
    var startsRun = true
    /// Last message of a run (the time goes under it).
    var endsRun = true
}

// MARK: - AskUserPayload

private struct AskUserPayload: Decodable {
    let question: String
    let choices: [String]?
}

// MARK: - CoachAskUserPayload

private struct CoachAskUserPayload {
    let question: String
    let choices: [String]
}

// MARK: - CoachUserBubble

struct CoachUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: TideCoach.bubbleGutter)
            Text(text)
                .tideCoachBubble(.user)
        }
    }
}

// MARK: - CoachAssistantBubble

struct CoachAssistantBubble: View {
    let text: String
    /// Coach's mark beside the bubble: on the first bubble of a run. Later
    /// bubbles keep the space free so the column stays straight.
    var showsAvatar = false

    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Strip [pref_xxxx] citation markers from the visible body so the
    /// text reads cleanly. Phase 7c (when citation chips are wired to
    /// real LearnedPreference lookups) renders them as tappable rows
    /// below the bubble.
    private var displayText: String {
        CoachMessageRenderer.strippingCitationMarkers(text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s2) {
            // No room for a column of marks at accessibility sizes.
            if !typeSize.isAccessibilitySize {
                if showsAvatar {
                    TideCoachAvatar()
                } else {
                    Color.clear.frame(width: TideCoachAvatar.width, height: Tide.hair)
                }
            }
            Text(displayText)
                .tideCoachBubble(.assistant)
            Spacer(minLength: TideCoach.bubbleGutter)
        }
    }
}

// MARK: - CoachToolResultCard

struct CoachToolResultCard: View {
    let summary: String
    let isError: Bool
    var detail: String?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var expanded = false

    private var tint: Color {
        isError ? Tide.danger : mood.accent
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(spacing: Tide.s3) {
                    TideIconTile(
                        systemName: isError ? "xmark.octagon.fill" : "checkmark.seal.fill",
                        tint: tint,
                        size: Tide.tile - Tide.s2
                    ).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Text(summary)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    if detail != nil {
                        Button {
                            withAnimation(Tide.snap) { expanded.toggle() }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .frame(width: Tide.hit, height: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? "Hide details" : "Show details")
                    }
                }
                if expanded, let detail {
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Tide.tile - Tide.s2 + Tide.s3)
                }
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .glassEffect(.regular.tint(tint.opacity(0.2)), in: .rect(cornerRadius: Tide.tileRadius))
            Spacer(minLength: TideCoach.bubbleGutter)
        }
        .padding(.leading, TideCoachAvatar.inset(for: typeSize))
    }
}

// MARK: - CoachPendingQuestionBubble

struct CoachPendingQuestionBubble: View {
    let question: String
    let choices: [String]
    let onChoiceTap: (String) -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .top, spacing: Tide.s2) {
                if !typeSize.isAccessibilitySize {
                    Color.clear.frame(width: TideCoachAvatar.width, height: Tide.hair)
                }
                Text(question)
                    .tideCoachBubble(.assistant)
                Spacer(minLength: TideCoach.bubbleGutter)
            }
            if !choices.isEmpty {
                // Suggested answers, aligned under the question's bubble.
                GlassEffectContainer(spacing: Tide.s2) {
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(choices, id: \.self) { choice in
                            Button(choice) { onChoiceTap(choice) }
                                .buttonStyle(.tideCoachReply)
                        }
                    }
                }
                .padding(.leading, TideCoachAvatar.inset(for: typeSize))
            }
        }
    }
}

// MARK: - CoachThinkingBubble

struct CoachThinkingBubble: View {
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s2) {
            if !typeSize.isAccessibilitySize {
                TideCoachAvatar()
            }
            HStack(spacing: Tide.s3) {
                TideCoachTypingDots()
                Text("Thinking…")
                    .foregroundStyle(Tide.text2)
                    .tideCoachShimmer()
            }
            .tideCoachBubble(.assistant)
            Spacer(minLength: TideCoach.bubbleGutter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Coach is thinking"))
    }
}

// MARK: - CoachEmptyState

struct CoachEmptyState: View {
    let seeds: [String]
    var heading = "Ask Coach anything"
    let onSeedTap: (String) -> Void

    /// One symbol per seed, in order: a plan, a feeling, something to remember.
    private static let seedIcons = ["calendar.badge.clock", "bed.double.fill", "brain.head.profile"]

    @State
    private var taps = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s6) {
                VStack(spacing: Tide.s3) {
                    TideStateMark(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text(heading)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text("I know enough to start. Try one of these, or say something else.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                GlassEffectContainer(spacing: Tide.s3) {
                    VStack(spacing: Tide.s3) {
                        ForEach(Array(seeds.enumerated()), id: \.element) { index, seed in
                            Button {
                                taps += 1
                                onSeedTap(seed)
                            } label: {
                                HStack(spacing: Tide.s3) {
                                    TideIconTile(
                                        systemName: Self.seedIcons[index % Self.seedIcons.count],
                                        size: Tide.tile - Tide.s2
                                    ).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    Text(seed)
                                        .font(Tide.bodyStrong)
                                        .foregroundStyle(Tide.text)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: Tide.s2)
                                    Image(systemName: "arrow.up.right")
                                        .font(Tide.caption)
                                        .foregroundStyle(Tide.text2)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: Tide.hit - Tide.s5)
                                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                                .contentShape(.rect(cornerRadius: Tide.tileRadius))
                            }
                            .buttonStyle(TideCoachPressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s6)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
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

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var pressInFlight: Bool = false
    @State
    private var sends = 0

    var body: some View {
        GlassEffectContainer(spacing: Tide.s2) {
            HStack(alignment: .bottom, spacing: Tide.s2) {
                micButton
                field
                sendButton
            }
        }
        .padding(.horizontal, Tide.edge)
        .sensoryFeedback(.impact(weight: .medium), trigger: sends)
    }

    private var field: some View {
        TextField(
            text: $text,
            prompt: Text(isRecording ? "Listening…" : "Type a message…").foregroundStyle(Tide.text3),
            axis: .vertical
        ) {
            Text("Message Coach")
        }
        .lineLimit(1 ... 4)
        .textFieldStyle(.plain)
        .font(Tide.body)
        .foregroundStyle(Tide.text)
        .tint(mood.accent)
        .submitLabel(.send)
        .onSubmit { fire() }
        .disabled(isDisabled || isThinking)
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.hit / 2))
        .opacity(isDisabled ? 0.5 : 1)
    }

    private var sendButton: some View {
        Button {
            fire()
        } label: {
            Image(systemName: "arrow.up")
                .font(Tide.headline)
                .foregroundStyle(canSend ? Tide.ink : Tide.text3)
                .frame(width: Tide.hit, height: Tide.hit)
                .background {
                    if canSend {
                        Circle().fill(mood.accent)
                    }
                }
                .glassEffect(canSend ? .identity : .regular.tint(Tide.glassControl), in: .circle)
                .contentShape(.circle)
                .animation(reduceMotion ? nil : Tide.snap, value: canSend)
                .accessibilityLabel(Text("Send message"))
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isDisabled || isThinking)
    }

    private var micButton: some View {
        // The same view powers both modes. Tap-toggle uses the regular
        // tap action (Began fires once). Hold-to-record relies on a
        // DragGesture(minimumDistance: 0) to differentiate press vs
        // release so the caller can map .ended → stop.
        Image(systemName: isRecording ? "mic.fill" : "mic")
            .font(Tide.headline)
            .foregroundStyle(isRecording ? Tide.danger : Tide.text)
            .symbolEffect(.pulse, isActive: isRecording && !reduceMotion)
            .frame(width: Tide.hit, height: Tide.hit)
            .glassEffect(
                .regular.tint(isRecording ? Tide.danger.opacity(0.28) : Tide.glassControl),
                in: .circle
            )
            .scaleEffect(pressInFlight ? Tide.pressButton : 1)
            .animation(reduceMotion ? nil : Tide.snap, value: pressInFlight)
            .opacity(isDisabled ? 0.5 : 1)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressInFlight else {
                            return
                        }
                        pressInFlight = true
                        if !isDisabled {
                            onMicPressBegan()
                        }
                    }
                    .onEnded { _ in
                        pressInFlight = false
                        if !isDisabled {
                            onMicPressEnded()
                        }
                    }
            )
            .accessibilityLabel(Text(isRecording ? "Stop recording" : "Start recording"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !isDisabled {
                    onMicPressBegan()
                }
            }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func fire() {
        if canSend {
            sends += 1
        }
        onSend()
    }
}

// Note: `FlowLayout` is defined in Tempo/Tempo/Views/Shared/FlowLayout.swift
// and reused here for the askUser choice-chip row via `FlowLayout(spacing:
// lineSpacing:)`.
