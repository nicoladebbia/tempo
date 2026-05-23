//
// CoachChatView.swift
// Tempo
//
// Multi-turn Coach chat UI. Embedded inside `NutritionCoachView` below
// the existing one-shot coaching cards. Transcript bubbles + input bar +
// askUser chips + cited-preference footnotes.
//
// Per `.plans/coach-agent-plan.md` Phase 7.
//

import SwiftUI

struct CoachChatView: View {

    @Bindable var viewModel: CoachViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.md) {
            header

            if let banner = viewModel.errorBanner {
                errorBanner(banner)
            }

            transcript

            if let q = viewModel.pendingQuestion {
                askUserPrompt(q)
            }

            inputBar

            if let undo = viewModel.undoLabel {
                undoBar(undo)
            }
        }
        .padding(TempoSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tempoSurfaceDeep)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: TempoSpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(Color.tempoViolet)
            Text("Coach Chat")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            if viewModel.conversation != nil {
                Button {
                    Task { await viewModel.endConversation() }
                } label: {
                    Label("End", systemImage: "stop.circle")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    if viewModel.displayTurns.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.displayTurns) { turn in
                            bubble(for: turn)
                                .id(turn.id)
                        }
                    }
                    if viewModel.isThinking {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.vertical, TempoSpacing.xs)
            }
            .frame(maxHeight: 360)
            .onChange(of: viewModel.displayTurns.count) {
                if let last = viewModel.displayTurns.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Start a session.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Text("Ask about meal timing, recovery tweaks, training conflicts. The coach can move planned meals and remember your preferences.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.vertical, TempoSpacing.sm)
    }

    private func bubble(for turn: DisplayTurn) -> some View {
        HStack(alignment: .top) {
            if turn.role == .user { Spacer(minLength: TempoSpacing.xl) }
            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 2) {
                Text(turn.text)
                    .font(turn.role == .system ? .tempoCaption1 : .tempoBody)
                    .foregroundStyle(textColor(for: turn.role))
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, TempoSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(bubbleColor(for: turn.role))
                    )
                if !turn.citedPreferenceIDs.isEmpty {
                    citationFootnote(turn.citedPreferenceIDs)
                }
            }
            if turn.role != .user { Spacer(minLength: TempoSpacing.xl) }
        }
    }

    private func citationFootnote(_ ids: [UUID]) -> some View {
        let codes = ids.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
        return Text("from memory: \(codes)")
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
            .padding(.horizontal, TempoSpacing.md)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: TempoSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.vertical, TempoSpacing.xs)
    }

    private func textColor(for role: DisplayTurn.Role) -> Color {
        switch role {
        case .user: return .white
        case .assistant: return Color.tempoTextPrimary
        case .system: return Color.tempoTextTertiary
        }
    }

    private func bubbleColor(for role: DisplayTurn.Role) -> Color {
        switch role {
        case .user: return Color.tempoViolet
        case .assistant: return Color.tempoSurfaceCard
        case .system: return Color.tempoSurfaceCard.opacity(0.6)
        }
    }

    // MARK: - askUser prompt + chips

    private func askUserPrompt(_ q: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(q.question)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            if let choices = q.choices, !choices.isEmpty {
                HStack(spacing: TempoSpacing.xs) {
                    ForEach(choices, id: \.self) { choice in
                        Button {
                            Task { await viewModel.send(choice) }
                        } label: {
                            Text(choice)
                                .font(.tempoCaption1)
                                .padding(.horizontal, TempoSpacing.md)
                                .padding(.vertical, TempoSpacing.xs)
                                .background(
                                    Capsule().fill(Color.tempoViolet.opacity(0.18))
                                )
                                .foregroundStyle(Color.tempoViolet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(TempoSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tempoViolet.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: TempoSpacing.sm) {
            TextField("Message the coach…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.tempoBody)
                .lineLimit(1...4)
                .padding(TempoSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color.tempoSurfaceCard)
                )
                .disabled(viewModel.isThinking)

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.tempoViolet : Color.tempoTextTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !viewModel.isThinking
            && !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Undo bar

    private func undoBar(_ label: String) -> some View {
        HStack {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(Color.tempoAmber)
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Button("Undo") {
                viewModel.undoLast()
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoAmber)
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.tempoAmber.opacity(0.10))
        )
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tempoError)
            Text(msg)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(TempoSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.tempoError.opacity(0.10))
        )
    }
}
