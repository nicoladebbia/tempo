//
// FriendSystemView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI
import UIKit

// MARK: - FriendSystemView

// Per MODULE_ARENA.md Section 8 — Friend list, requests, search.
// Per WIREFRAMES.md Screen 41 — Friend list layout.

struct FriendSystemView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var searchText = ""
    @State
    private var showAddFriend = false

    /// Mock data — will be replaced with API calls
    @State
    private var friends: [FriendDisplayItem] = []

    @State
    private var pendingRequests: [FriendRequestItem] = []

    @State
    private var showComingSoonAlert = false
    @State
    private var showShareSheet = false

    var body: some View {
        Group {
            if friends.isEmpty, pendingRequests.isEmpty {
                // Nobody here yet: one picture, one line, the one action under the thumb.
                ArenaEmptyPage(
                    title: "No friends yet",
                    message: "Add friends to see their activity and compete on the leaderboard.",
                    actionTitle: "Invite friends",
                    actionSystemImage: "person.badge.plus",
                    action: { showAddFriend = true },
                    art: { ArenaEmptyArt(systemImage: "person.2.fill") }
                )
            } else {
                friendsPage
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add friends")
            }
        }
        .tideCovered(showAddFriend)
        .sheet(isPresented: $showAddFriend) {
            addFriendSheet
        }
    }

    // MARK: - Friends

    private var friendsPage: some View {
        TideScrollPage {
            TextField("Search friends", text: $searchText)
                .tideField(systemImage: "magnifyingglass")

            // Pending requests
            if !pendingRequests.isEmpty {
                pendingSection
            }

            // Online friends
            let online = friends.filter(\.isOnline)
            if !online.isEmpty {
                friendSection(title: "Online", friends: online, isOnline: true)
            }

            // Offline friends
            let offline = friends.filter { !$0.isOnline }
            if !offline.isEmpty {
                friendSection(title: "Offline", friends: offline, isOnline: false)
            }
        }
        // Inviting is the page's action: it stays under the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showAddFriend = true
            } label: {
                Label("Invite friends", systemImage: "person.badge.plus")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        }
    }

    // MARK: - Pending Requests

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Requests", trailing: "\(pendingRequests.count)")

            ForEach(pendingRequests) { request in
                VStack(alignment: .leading, spacing: Tide.s3) {
                    HStack(spacing: Tide.s3) {
                        TideInitialAvatar(name: request.username, tint: Tide.streak)
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text("@\(request.username)")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                                .lineLimit(1)
                            Text(request.timeAgo)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)

                    // Side by side, or one under the other when the text is large.
                    let actions = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: Tide.s3))
                        : AnyLayout(HStackLayout(spacing: Tide.s3))
                    actions {
                        Button("Accept") { acceptRequest(request) }
                            .buttonStyle(.tidePrimary)
                            .frame(maxWidth: .infinity)
                        Button {
                            declineRequest(request)
                        } label: {
                            Text("Decline").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tideGlass)
                    }
                }
            }
        }
        .tideCard()
    }

    // MARK: - Friend Section (Online / Offline)

    private func friendSection(title: String, friends: [FriendDisplayItem], isOnline: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            TideSectionLabel(title: title, trailing: "\(friends.count)")
                .padding(.bottom, Tide.s1)

            ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                if index > 0 {
                    TideDivider()
                }
                // At large text the week's XP drops under the name instead of squeezing it.
                let row = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                    : AnyLayout(HStackLayout(spacing: Tide.s3))
                row {
                    HStack(spacing: Tide.s3) {
                        TideInitialAvatar(name: friend.displayName)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(isOnline ? TideTone.mint : Tide.text3)
                                    .frame(width: Tide.s3, height: Tide.s3)
                                    .overlay(Circle().strokeBorder(Tide.ink, lineWidth: Tide.hair))
                            }

                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(friend.displayName)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                            Text("Level \(friend.level)")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }

                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }

                    TideNumber(
                        friend.weeklyXP.formatted(), unit: "XP", size: Tide.numeralS, relativeTo: .headline,
                        weight: .semibold
                    )
                }
                .frame(minHeight: Tide.hit + Tide.s3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(friend.displayName), level \(friend.level), \(friend.weeklyXP) XP this week, \(isOnline ? "online" : "offline")"
                )
            }
        }
        .tideCard()
    }

    // MARK: - Add Friend Sheet

    private var addFriendSheet: some View {
        NavigationStack {
            TideScrollPage(spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("Find a friend").tideLabel()
                    TextField("Search by username", text: $searchText)
                        .tideField(systemImage: "magnifyingglass")
                }

                Text("or")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity)

                // Alternative methods
                VStack(spacing: 0) {
                    addMethodButton(icon: "qrcode.viewfinder", title: "Scan a QR code")
                    TideDivider()
                    addMethodButton(icon: "link", title: "Share a link")
                    TideDivider()
                    addMethodButton(icon: "person.crop.rectangle", title: "Import from contacts")
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .navigationTitle("Add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TideCloseButton(label: "Done") { showAddFriend = false }
                }
            }
        }
        .presentationDetents([.large])
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature is not yet available. Stay tuned!")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(activityItems: ["Join me on Tempo! Download the app and add me as a friend."])
        }
    }

    // MARK: - Friend Request Actions

    private func acceptRequest(_ request: FriendRequestItem) {
        withAnimation(Tide.snap) {
            // Move from pending to friends
            pendingRequests.removeAll { $0.id == request.id }
            friends.append(FriendDisplayItem(
                userID: request.requestID,
                username: request.username,
                displayName: request.username.capitalized,
                level: 1,
                weeklyXP: 0,
                isOnline: false
            ))
        }
    }

    private func declineRequest(_ request: FriendRequestItem) {
        withAnimation(Tide.snap) {
            pendingRequests.removeAll { $0.id == request.id }
        }
    }

    private func addMethodButton(icon: String, title: String) -> some View {
        Button {
            if title == "Share a link" {
                showShareSheet = true
            } else {
                showComingSoonAlert = true
            }
        } label: {
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: icon, tint: mood.accent)
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Tide.s2)
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FriendDisplayItem

struct FriendDisplayItem: Identifiable {
    let id = UUID()
    let userID: String
    let username: String
    let displayName: String
    let level: Int
    let weeklyXP: Int
    let isOnline: Bool
}

// MARK: - FriendRequestItem

struct FriendRequestItem: Identifiable {
    let id = UUID()
    let requestID: String
    let username: String
    let timeAgo: String
}

// MARK: - ShareSheetView

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
