//
// CoachHistoryView.swift
// Tempo
//
// Coach v2.1 Phase 8c — past-conversations list. Tap a row to view a
// read-only transcript. Swipe to star (exempts from the 30-day purge
// that runs in DailyResetCoordinator.purgeStaleCoachConversations).
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §5.
//

import SwiftData
import SwiftUI

// MARK: - CoachHistoryView

struct CoachHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// All conversations except the currently-active one. Newer first.
    @Query(
        filter: #Predicate<CoachConversation> { !$0.isActive },
        sort: [SortDescriptor(\CoachConversation.lastMessageAt, order: .reverse)]
    )
    private var conversations: [CoachConversation]

    @State private var selectedConversation: CoachConversation?

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.tempoBgPrimary.ignoresSafeArea())
            .navigationTitle("Past Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedConversation) { conv in
            CoachConversationDetailView(conversation: conv)
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(conversations, id: \.id) { conv in
                row(for: conv)
                    .listRowBackground(Color.tempoSurfaceCard)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func row(for conv: CoachConversation) -> some View {
        Button { selectedConversation = conv } label: {
            HStack(spacing: TempoSpacing.sm) {
                if conv.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.tempoAmber)
                        .accessibilityLabel(Text("Starred"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.titleSummary.isEmpty ? "Untitled chat" : conv.titleSummary)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)
                    Text(dateLabel(for: conv.lastMessageAt))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                conv.isStarred.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    conv.isStarred ? "Unstar" : "Star",
                    systemImage: conv.isStarred ? "star.slash" : "star"
                )
            }
            .tint(Color.tempoAmber)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Color.tempoTextTertiary)
                .accessibilityHidden(true)
            Text("No past conversations yet.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Text("Chats you end will show up here.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, TempoSpacing.lg)
    }

    // MARK: - Helpers

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - CoachConversationDetailView (read-only transcript)

private struct CoachConversationDetailView: View {
    let conversation: CoachConversation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TempoSpacing.md) {
                    ForEach(visibleMessages, id: \.id) { wrapper in
                        renderMessage(wrapper.message)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.md)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle(conversation.titleSummary.isEmpty ? "Chat" : conversation.titleSummary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private struct IndexedMessage: Identifiable, Equatable {
        let id: Int
        let message: CoachMessage
    }

    private var visibleMessages: [IndexedMessage] {
        conversation.messages
            .enumerated()
            .filter { _, msg in msg.role != "system_summary" }
            .filter { _, msg in (msg.text?.isEmpty == false) || msg.toolCalls != nil }
            .map { idx, msg in IndexedMessage(id: idx, message: msg) }
    }

    @ViewBuilder
    private func renderMessage(_ msg: CoachMessage) -> some View {
        switch msg.role {
        case "user":
            if let text = msg.text, !text.isEmpty {
                CoachUserBubble(text: text)
            }
        case "assistant":
            if let text = msg.text, !text.isEmpty {
                CoachAssistantBubble(text: text)
            }
        default:
            EmptyView()
        }
    }
}
