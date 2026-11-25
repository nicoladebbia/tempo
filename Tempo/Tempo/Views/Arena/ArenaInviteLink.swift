//
// ArenaInviteLink.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ArenaInviteLink

// An invite is a link: https://<server>/i/<token>, a public page whose button
// opens tempo://invite/<token>. The app takes either form. A link that arrives
// before the user is signed in is kept and shown once they are.

enum ArenaInviteLink {
    private static let storageKey = "tempo.arena.pendingInviteToken"

    /// The token inside `tempo://invite/<token>` or `https://host/i/<token>`.
    static func token(from url: URL) -> String? {
        let candidate: String?
        if url.scheme?.lowercased() == "tempo" {
            // tempo://invite/<token>: "invite" is the host.
            let pieces = ([url.host()] + url.pathComponents.map(Optional.init)).compactMap(\.self).filter { $0 != "/" }
            candidate = pieces.count >= 2 && pieces[0] == "invite" ? pieces[1] : nil
        } else {
            let pieces = url.pathComponents.filter { $0 != "/" }
            candidate = pieces.count >= 2 && pieces[0] == "i" ? pieces[1] : nil
        }
        guard let candidate, isValid(candidate) else {
            return nil
        }
        return candidate
    }

    /// Tokens are 16 lowercase letters and digits; anything else is not ours.
    static func isValid(_ token: String) -> Bool {
        (8 ... 64).contains(token.count) && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    static var pendingToken: String? {
        get { UserDefaults.standard.string(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

extension Notification.Name {
    /// Posted when a friend was added, so the Arena shows them straight away.
    static let arenaFriendsChanged = Notification.Name("tempo.arena.friendsChanged")
}

// MARK: - Root hook

extension View {
    /// Put this once at the app root. It opens invite links in a sheet and keeps
    /// the user's Arena totals fresh for friends whenever the app comes to the front.
    func arenaConnected() -> some View {
        modifier(ArenaConnectModifier())
    }
}

// MARK: - ArenaConnectModifier

private struct ArenaConnectModifier: ViewModifier {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.scenePhase)
    private var scenePhase
    @State
    private var pendingToken: String? = ArenaInviteLink.pendingToken

    private var isSignedIn: Bool {
        if case .authenticated = services.authService.authState {
            return true
        }
        return false
    }

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard let token = ArenaInviteLink.token(from: url) else {
                    return
                }
                ArenaInviteLink.pendingToken = token
                pendingToken = token
            }
            .sheet(item: sheetItem) { item in
                ArenaInviteSheet(token: item.token) {
                    ArenaInviteLink.pendingToken = nil
                    pendingToken = nil
                }
            }
            // Signed in, or back in front: write today's XP and tell the server.
            .task(id: isSignedIn) {
                guard isSignedIn else {
                    return
                }
                await ArenaSync.runFromRoot(context: modelContext, services: services)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, isSignedIn else {
                    return
                }
                Task { await ArenaSync.runFromRoot(context: modelContext, services: services) }
            }
    }

    /// The sheet shows only for a signed-in user; before that the token waits.
    private var sheetItem: Binding<InviteItem?> {
        Binding(
            get: { isSignedIn ? pendingToken.map(InviteItem.init) : nil },
            set: { newValue in
                if newValue == nil {
                    ArenaInviteLink.pendingToken = nil
                    pendingToken = nil
                }
            }
        )
    }

    private struct InviteItem: Identifiable {
        let token: String
        var id: String {
            token
        }
    }
}

// MARK: - ArenaInviteSheet

/// What opening someone's invite link shows: who it is, one tap to say yes.
struct ArenaInviteSheet: View {
    let token: String
    let onFinish: () -> Void

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private enum Stage: Equatable {
        case loading
        case ready(ArenaInvitePreviewDTO)
        case adding(ArenaInvitePreviewDTO)
        case joined(ArenaFriendDTO)
        case failed(String)
    }

    private var isAdding: Bool {
        if case .adding = stage {
            return true
        }
        return false
    }

    @State
    private var stage: Stage = .loading

    var body: some View {
        NavigationStack {
            TideScrollPage {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Friend invite").tideLabel()
                    Text(headline)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tide.s4)

                card
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s2)
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("arena.invite.sheet")
        .task { await load() }
    }

    // MARK: Content

    private var headline: String {
        switch stage {
        case .loading: "Opening the invite"
        case let .ready(preview),
             let .adding(preview):
            if preview.isOwn {
                "This is your own link"
            } else if preview.alreadyFriends {
                "You are already friends"
            } else {
                "\(preview.displayName) wants to race you"
            }
        case let .joined(friend): "You and \(friend.displayName) are friends"
        case .failed: "That invite did not work"
        }
    }

    @ViewBuilder
    private var card: some View {
        switch stage {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: Tide.s10)
                .tideCard()
                .accessibilityLabel("Loading the invite")

        case let .ready(preview),
             let .adding(preview):
            VStack(alignment: .leading, spacing: Tide.s4) {
                HStack(spacing: Tide.s3) {
                    TideInitialAvatar(name: preview.displayName, size: Tide.avatarLarge)
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text(preview.displayName)
                            .font(Tide.headline).foregroundStyle(Tide.text)
                            .lineLimit(2)
                        TideStatusPill(text: "Level \(preview.level)", tint: mood.accent)
                    }
                }
                .accessibilityElement(children: .combine)
                Text(explanation(preview))
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()

        case let .joined(friend):
            VStack(alignment: .leading, spacing: Tide.s3) {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(Tide.bodyStrong).foregroundStyle(TideTone.mint)
                Text("\(friend.displayName) is on your leaderboard now. Race them this week.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()

        case let .failed(message):
            TideEmptyPanel(systemImage: "link.badge.plus", title: "Could not open it", message: message)
                .tideCard()
        }
    }

    private func explanation(_ preview: ArenaInvitePreviewDTO) -> String {
        if preview.isOwn {
            "Send this link to a friend. Opening it on your own phone does nothing."
        } else if preview.alreadyFriends {
            "You can already see each other on the leaderboard."
        } else {
            "Friends see each other's name, level and XP for the week. Nothing else."
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch stage {
        case .loading:
            EmptyView()

        case let .ready(preview),
             let .adding(preview):
            if preview.isOwn || preview.alreadyFriends {
                Button("Close") { finish() }
                    .buttonStyle(.tidePrimary)
                    .accessibilityIdentifier("arena.invite.close")
            } else {
                VStack(spacing: Tide.s2) {
                    Button {
                        Task { await accept(preview) }
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Add \(preview.displayName)")
                        }
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(isAdding)
                    .accessibilityIdentifier("arena.invite.accept")
                    Button("Not now") { finish() }
                        .buttonStyle(.tideGlass)
                        .accessibilityIdentifier("arena.invite.dismiss")
                }
            }

        case .joined:
            VStack(spacing: Tide.s2) {
                Button("See the leaderboard") {
                    services.appState.activeTab = .arena
                    finish()
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("arena.invite.seeBoard")
                Button("Done") { finish() }
                    .buttonStyle(.tideGlass)
            }

        case .failed:
            VStack(spacing: Tide.s2) {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.tidePrimary)
                Button("Close") { finish() }
                    .buttonStyle(.tideGlass)
            }
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    private func load() async {
        stage = .loading
        do {
            let preview = try await services.apiClient.request(APIEndpoint<ArenaInvitePreviewDTO>.previewFriendInvite(token: token))
            stage = .ready(preview)
        } catch {
            stage = .failed(ArenaService.message(for: error))
        }
    }

    private func accept(_ preview: ArenaInvitePreviewDTO) async {
        stage = .adding(preview)
        do {
            let friend = try await services.apiClient.request(APIEndpoint<ArenaFriendDTO>.acceptFriendInvite(token: token))
            stage = .joined(friend)
            NotificationCenter.default.post(name: .arenaFriendsChanged, object: nil)
        } catch {
            stage = .failed(ArenaService.message(for: error))
        }
    }
}
