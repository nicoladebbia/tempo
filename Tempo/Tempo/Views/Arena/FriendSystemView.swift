//
// FriendSystemView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - FriendSystemView

// Real friends from the server: people who asked to be your friend (answer
// them), people you are friends with (and their XP this week), and the way to
// add more, your invite link. A friend sees your name, level and weekly XP,
// nothing else; removing a friend takes you off each other's boards.

struct FriendSystemView: View {
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var showInvite = false
    @State
    private var friendToRemove: ArenaFriendDTO?
    @State
    private var errorMessage: String?
    @State
    private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            switch arena.phase {
            case .idle,
                 .loading:
                TideScrollPage {
                    ArenaListSkeleton(rows: 4, label: "Loading friends")
                }

            case let .failed(message):
                TideScrollPage {
                    TideEmptyPanel(
                        systemImage: "wifi.exclamationmark", title: "Could not load your friends",
                        message: message, actionTitle: "Try again"
                    ) { Task { await arena.refresh() } }
                        .tideCard()
                }

            case .ready:
                if arena.friends.isEmpty, arena.requests.isEmpty {
                    emptyPage
                } else {
                    list
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("arena.friends")
        .task { await arena.refresh() }
        .sheet(isPresented: $showInvite) {
            FriendInviteSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Remove \(friendToRemove?.displayName ?? "this friend")?",
            isPresented: Binding(get: { friendToRemove != nil }, set: {
                if !$0 {
                    friendToRemove = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Remove friend", role: .destructive) {
                if let friend = friendToRemove {
                    run(friend.id) { try await arena.remove(friend) }
                }
            }
            Button("Keep friend", role: .cancel) {}
        } message: {
            Text("You will both disappear from each other's leaderboard. You can add each other again with a link.")
        }
    }

    // MARK: - Empty

    private var emptyPage: some View {
        ArenaEmptyPage(
            title: "Race someone",
            message: "Send your link to a friend. When they say yes you are on each other's weekly leaderboard.",
            actionTitle: "Invite a friend",
            actionSystemImage: "person.badge.plus",
            action: { showInvite = true },
            art: { ArenaGhostAvatars() }
        )
    }

    // MARK: - List

    private var list: some View {
        TideScrollPage {
            if !arena.incomingRequests.isEmpty {
                section("Requests", count: arena.incomingRequests.count) {
                    ForEach(Array(arena.incomingRequests.enumerated()), id: \.element.id) { index, request in
                        if index > 0 {
                            TideDivider()
                        }
                        requestRow(request)
                    }
                }
            }

            if !arena.friends.isEmpty {
                section("Friends", count: arena.friends.count) {
                    ForEach(Array(arena.friends.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 {
                            TideDivider()
                        }
                        friendRow(friend)
                    }
                }
            }

            if !arena.outgoingRequests.isEmpty {
                section("Waiting for an answer", count: arena.outgoingRequests.count) {
                    ForEach(Array(arena.outgoingRequests.enumerated()), id: \.element.id) { index, request in
                        if index > 0 {
                            TideDivider()
                        }
                        waitingRow(request)
                    }
                }
            }

            if arena.isStale {
                Label("Showing the last list we got. Pull down to retry.", systemImage: "wifi.slash")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .refreshable { await arena.refresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showInvite = true
            } label: {
                Label("Invite a friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
            .accessibilityIdentifier("arena.inviteButton")
        }
    }

    private func section(_ title: String, count: Int, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: title, trailing: "\(count)")
            VStack(spacing: 0) {
                rows()
            }
        }
        .tideCard(padding: Tide.s4)
    }

    // MARK: - Rows

    private func friendRow(_ friend: ArenaFriendDTO) -> some View {
        HStack(spacing: Tide.s3) {
            TideInitialAvatar(name: friend.displayName)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(friend.displayName)
                    .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text("Level \(friend.level) · \(friend.weeklyXP.formatted()) XP this week")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                    friendToRemove = friend
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More for \(friend.displayName)")
            .accessibilityIdentifier("arena.friendMenu")
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .opacity(busyIDs.contains(friend.id) ? 0.5 : 1)
        .accessibilityElement(children: .contain)
    }

    private func requestRow(_ request: ArenaFriendRequestDTO) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        let busy = busyIDs.contains(request.id)
        return layout {
            HStack(spacing: Tide.s3) {
                TideInitialAvatar(name: request.displayName)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(request.displayName)
                        .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                        .lineLimit(stacked ? 3 : 1)
                    Text("Level \(request.level) · wants to be friends")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !stacked {
                Spacer(minLength: Tide.s2)
            }
            HStack(spacing: Tide.s2) {
                Button {
                    run(request.id) { try await arena.decline(request) }
                } label: {
                    Image(systemName: "xmark")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text2)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline \(request.displayName)")
                .accessibilityIdentifier("arena.requestDecline")

                Button {
                    run(request.id) { try await arena.accept(request) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.ink)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.tint(mood.accent).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept \(request.displayName)")
                .accessibilityIdentifier("arena.requestAccept")
            }
            .disabled(busy)
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .opacity(busy ? 0.5 : 1)
    }

    private func waitingRow(_ request: ArenaFriendRequestDTO) -> some View {
        HStack(spacing: Tide.s3) {
            TideInitialAvatar(name: request.displayName)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(request.displayName)
                    .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text("Level \(request.level)")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
            }
            Spacer(minLength: Tide.s2)
            TideStatusPill(text: "Sent", tint: Tide.text2, systemImage: "paperplane.fill")
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    /// Runs one answer, shows it as busy, and says plainly if it failed.
    private func run(_ id: String, _ work: @escaping () async throws -> Void) {
        guard !busyIDs.contains(id) else {
            return
        }
        busyIDs.insert(id)
        Task {
            defer { busyIDs.remove(id) }
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
