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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
                .environment(\.tideInsidePage, false)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: stars)
    }

    // MARK: - List

    /// A heading and the chats under it.
    private struct DayGroup: Identifiable {
        let id: Int
        let title: String
        let conversations: [CoachConversation]
    }

    /// Chats bucketed by how long ago they ended, newest first: Today,
    /// Yesterday, This week, Earlier. Empty buckets are left out.
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let titles = ["Today", "Yesterday", "This week", "Earlier"]
        var buckets: [[CoachConversation]] = Array(repeating: [], count: titles.count)
        for conv in conversations {
            let day = calendar.startOfDay(for: conv.lastMessageAt)
            let index = if day >= startOfToday {
                0
            } else if calendar.isDateInYesterday(conv.lastMessageAt) {
                1
            } else if day >= weekAgo {
                2
            } else {
                3
            }
            buckets[index].append(conv)
        }
        return titles.enumerated().compactMap { index, title in
            buckets[index].isEmpty ? nil : DayGroup(id: index, title: title, conversations: buckets[index])
        }
    }

    private var list: some View {
        List {
            Text("Swipe a chat to star it")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: Tide.s2, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge)
                )
            ForEach(groups) { group in
                Section {
                    ForEach(group.conversations, id: \.id) { conv in
                        row(for: conv)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(top: Tide.s1, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge)
                            )
                    }
                } header: {
                    TideSectionLabel(title: group.title, trailing: "\(group.conversations.count)")
                        .padding(.horizontal, Tide.edge)
                        .padding(.top, Tide.s3)
                        .textCase(nil)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func row(for conv: CoachConversation) -> some View {
        Button { selectedConversation = conv } label: {
            HStack(spacing: Tide.s3) {
                if !typeSize.isAccessibilitySize {
                    TideIconTile(
                        systemName: conv.isStarred ? "star.fill" : "bubble.left.and.text.bubble.right.fill",
                        tint: conv.isStarred ? Tide.carbs : nil,
                        size: Tide.tileLarge - Tide.s2
                    ).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(conv.titleSummary.isEmpty ? "Untitled chat" : conv.titleSummary)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detailLabel(for: conv))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tide.s2)
                if conv.isStarred {
                    Image(systemName: "star.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.carbs)
                        .accessibilityLabel(Text("Starred"))
                }
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
                    .strokeBorder(Tide.hairline, lineWidth: TideCoach.rule)
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
            TideStateMark(systemName: "bubble.left.and.bubble.right")
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

    /// "5 messages · 14:20" for today and yesterday, "5 messages · 21 Nov" for older chats.
    private func detailLabel(for conv: CoachConversation) -> String {
        let count = conv.messages.count { msg in
            (msg.role == "user" || msg.role == "assistant") && msg.text?.isEmpty == false
        }
        let calendar = Calendar.current
        let recent = calendar.isDateInToday(conv.lastMessageAt) || calendar.isDateInYesterday(conv.lastMessageAt)
        let when = recent
            ? conv.lastMessageAt.formatted(date: .omitted, time: .shortened)
            : conv.lastMessageAt.formatted(.dateTime.day().month(.abbreviated))
        return "\(count) \(count == 1 ? "message" : "messages") \u{00B7} \(when)"
    }
}

// MARK: - CoachConversationDetailView

private struct CoachConversationDetailView: View {
    let conversation: CoachConversation
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(visibleMessages, id: \.id) { wrapper in
                        entry(wrapper)
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
        var dayHeading: Date?
        var startsRun = true
        var endsRun = true
    }

    /// The readable messages, each with where it sits in the page: a day
    /// heading above the first message of a day, Coach's mark on the first
    /// bubble of a run, the time under the last.
    private var visibleMessages: [IndexedMessage] {
        let kept = conversation.messages
            .enumerated()
            .filter { _, msg in
                (msg.role == "user" || msg.role == "assistant") && msg.text?.isEmpty == false
            }
        let calendar = Calendar.current
        return kept.enumerated().map { position, item in
            let message = item.element
            let previous = position > 0 ? kept[position - 1].element : nil
            let next = position + 1 < kept.count ? kept[position + 1].element : nil
            let startsDay = previous.map { !calendar.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? true
            let nextStartsDay = next.map { !calendar.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? false
            return IndexedMessage(
                id: item.offset,
                message: message,
                dayHeading: startsDay ? message.timestamp : nil,
                startsRun: previous?.role != message.role || startsDay,
                endsRun: next?.role != message.role || nextStartsDay
            )
        }
    }

    private func entry(_ item: IndexedMessage) -> some View {
        let hasText = item.message.text?.isEmpty == false
        let isUser = item.message.role == "user"
        return VStack(alignment: .leading, spacing: Tide.s1) {
            if let day = item.dayHeading {
                TideCoachDaySeparator(date: day)
                    .padding(.vertical, Tide.s2)
            }
            renderMessage(item.message, showsAvatar: item.startsRun)
            if item.endsRun, hasText, isUser || item.message.role == "assistant" {
                Text(item.message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    .padding(.leading, isUser ? 0 : TideCoachAvatar.inset(for: typeSize))
                    .padding(.bottom, Tide.s1)
            }
        }
    }

    @ViewBuilder
    private func renderMessage(_ msg: CoachMessage, showsAvatar: Bool) -> some View {
        switch msg.role {
        case "user":
            if let text = msg.text, !text.isEmpty {
                CoachUserBubble(text: text)
            }
        case "assistant":
            if let text = msg.text, !text.isEmpty {
                CoachAssistantBubble(text: text, showsAvatar: showsAvatar)
            }
        default:
            EmptyView()
        }
    }
}
