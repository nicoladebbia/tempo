import SwiftUI

// MARK: - Friend System View
// Per MODULE_ARENA.md Section 8 — Friend list, requests, search.
// Per WIREFRAMES.md Screen 41 — Friend list layout.

struct FriendSystemView: View {

    @Environment(ServiceContainer.self) private var services

    @State private var searchText = ""
    @State private var showAddFriend = false

    // Mock data — will be replaced with API calls
    @State private var friends: [FriendDisplayItem] = []
    @State private var pendingRequests: [FriendRequestItem] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                // Search bar
                searchBar

                // Pending requests
                if !pendingRequests.isEmpty {
                    pendingSection
                }

                // Online friends
                let online = friends.filter { $0.isOnline }
                if !online.isEmpty {
                    friendSection(title: "ONLINE (\(online.count))", friends: online, isOnline: true)
                }

                // Offline friends
                let offline = friends.filter { !$0.isOnline }
                if !offline.isEmpty {
                    friendSection(title: "OFFLINE (\(offline.count))", friends: offline, isOnline: false)
                }

                // Empty state
                if friends.isEmpty && pendingRequests.isEmpty {
                    emptyState
                }

                // Invite button
                inviteButton
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.xxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("FRIENDS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .sheet(isPresented: $showAddFriend) {
            addFriendSheet
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.tempoTextTertiary)
            TextField("Search friends...", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Pending Requests

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("PENDING (\(pendingRequests.count))")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.tempoWarning)

            ForEach(pendingRequests) { request in
                HStack(spacing: TempoSpacing.sm) {
                    Circle()
                        .fill(Color.tempoWarning.opacity(0.2))
                        .frame(width: 8, height: 8)

                    Circle()
                        .fill(Color.tempoSignal.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(request.username.prefix(1).uppercased()))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.tempoSignal)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(request.username)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(request.timeAgo)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Spacer()

                    Button("Accept") {}
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.tempoSignal)
                        .clipShape(Capsule())

                    Button("Decline") {}
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.tempoBorder, lineWidth: 0.5))
                }
                .frame(height: 56)
            }
        }
    }

    // MARK: - Friend Section (Online / Offline)

    private func friendSection(title: String, friends: [FriendDisplayItem], isOnline: Bool) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(isOnline ? Color.tempoSuccess : Color.tempoTextSecondary)

            ForEach(friends) { friend in
                HStack(spacing: TempoSpacing.sm) {
                    // Online dot
                    Circle()
                        .fill(isOnline ? Color.tempoSuccess : Color.tempoSteel)
                        .frame(width: 8, height: 8)

                    // Avatar
                    Circle()
                        .fill(Color.tempoSignal.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(friend.displayName.prefix(1)))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.tempoSignal)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Level \(friend.level)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Spacer()

                    Text("\(friend.weeklyXP) XP")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(height: 56)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No friends yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Add friends to see their activity and compete on the leaderboard.")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    // MARK: - Invite Button

    private var inviteButton: some View {
        Button {
            showAddFriend = true
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "person.badge.plus")
                Text("Invite More Friends")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.tempoSignal)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.tempoSignal, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
    }

    // MARK: - Add Friend Sheet

    private var addFriendSheet: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xxl) {
                // Search
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("ADD FRIENDS")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.tempoTextSecondary)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.tempoTextTertiary)
                        TextField("Search by username...", text: $searchText)
                            .font(.system(size: 15))
                    }
                    .padding(TempoSpacing.md)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.tempoBorder, lineWidth: 0.5)
                    )
                }

                Text("— OR —")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)

                // Alternative methods
                VStack(spacing: TempoSpacing.md) {
                    addMethodButton(icon: "qrcode.viewfinder", title: "QR Code Scan")
                    addMethodButton(icon: "link", title: "Share Link")
                    addMethodButton(icon: "person.crop.rectangle", title: "Import from Contacts")
                }

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.top, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAddFriend = false }
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func addMethodButton(icon: String, title: String) -> some View {
        Button {} label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 32)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Supporting Types

struct FriendDisplayItem: Identifiable {
    let id = UUID()
    let userID: String
    let username: String
    let displayName: String
    let level: Int
    let weeklyXP: Int
    let isOnline: Bool
}

struct FriendRequestItem: Identifiable {
    let id = UUID()
    let requestID: String
    let username: String
    let timeAgo: String
}
