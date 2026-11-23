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
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    /// All conversations except the currently-active one. Newer first.
    @Query(
        filter: #Predicate<CoachConversation> { !$0.isActive },
        sort: [SortDescriptor(\CoachConversation.lastMessageAt, order: .reverse)]
    )
    private var conversations: [CoachConversation]

    @State
    private var selectedConversation: CoachConversation?
    @State
    private var stars = 0

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .tidePage()
            .navigationTitle("Past chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .tideCovered(selectedConversation != nil)
        .sheet(item: $selectedConversation) { conv in
            CoachConversationDetailView(conversation: conv)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: stars)
    }

    // MARK: - List

    private var list: some View {
        List {
            TideSectionLabel(title: "Swipe a chat to star it", trailing: "\(conversations.count)")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: Tide.s2, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge)
                )
            ForEach(conversations, id: \.id) { conv in
                row(for: conv)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(top: Tide.s1, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge)
                    )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func row(for conv: CoachConversation) -> some View {
        Button { selectedConversation = conv } label: {
            HStack(spacing: Tide.s3) {
                if conv.isStarred {
                    Image(systemName: "star.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.carbs)
                        .accessibilityLabel(Text("Starred"))
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(conv.titleSummary.isEmpty ? "Untitled chat" : conv.titleSummary)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(dateLabel(for: conv.lastMessageAt))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(minHeight: Tide.hit)
            .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(Tide.hairline, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                conv.isStarred.toggle()
                try? modelContext.save()
                stars += 1
            } label: {
                Label(
                    conv.isStarred ? "Unstar" : "Star",
                    systemImage: conv.isStarred ? "star.slash" : "star"
                )
            }
            .tint(Tide.carbs)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            VStack(spacing: Tide.s1) {
                Text("No past conversations yet.")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text("Chats you end will show up here.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Helpers

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - CoachConversationDetailView

private struct CoachConversationDetailView: View {
    let conversation: CoachConversation
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(visibleMessages, id: \.id) { wrapper in
                        renderMessage(wrapper.message)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .tidePage()
            .navigationTitle(conversation.titleSummary.isEmpty ? "Chat" : conversation.titleSummary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
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
