//
// FriendInviteSheet.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import SwiftUI
import UIKit

// MARK: - FriendInviteSheet

// "Invite a friend": the user's own link, ready for the system share sheet.
// Whoever opens it sees your name and level and says yes; then you are friends.
// A new link kills the old one, for a link that went to the wrong chat.

struct FriendInviteSheet: View {
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    private enum Stage: Equatable {
        case loading
        case ready(ArenaInviteDTO)
        case failed(String)
    }

    @State
    private var stage: Stage = .loading
    @State
    private var copied = false
    @State
    private var confirmNewLink = false
    @State
    private var working = false

    var body: some View {
        NavigationStack {
            TideScrollPage {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Invite").tideLabel()
                    Text("Race a friend")
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Send your link. When they open it and say yes, you are on each other's leaderboard.")
                        .font(Tide.body).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tide.s4)

                content

                privacy
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s2)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("arena.inviteSheet")
        .task { await load() }
        .confirmationDialog("Make a new link?", isPresented: $confirmNewLink, titleVisibility: .visible) {
            Button("Make a new link", role: .destructive) { Task { await renew() } }
            Button("Keep this one", role: .cancel) {}
        } message: {
            Text("The old link stops working. Friends you already added stay friends.")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: Tide.s10 + Tide.s6)
                .tideCard()
                .accessibilityLabel("Making your link")

        case let .ready(invite):
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text("Your link").tideLabel()
                Text(invite.url)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("arena.inviteLink")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()

        case let .failed(message):
            TideEmptyPanel(
                systemImage: "wifi.exclamationmark", title: "Could not make your link", message: message,
                actionTitle: "Try again"
            ) { Task { await load() } }
                .tideCard()
        }
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: "lock.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            Text("Friends see your name, level and XP for the week. Nothing else, and only friends.")
                .font(Tide.caption).foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Tide.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if case let .ready(invite) = stage, let url = URL(string: invite.url) {
            VStack(spacing: Tide.s2) {
                ShareLink(
                    item: url,
                    subject: Text("Race me on Tempo"),
                    message: Text("Add me on Tempo and race me this week.")
                ) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("arena.inviteShare")

                HStack(spacing: Tide.s2) {
                    Button {
                        UIPasteboard.general.string = invite.url
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .sensoryFeedback(.success, trigger: copied)
                    .accessibilityIdentifier("arena.inviteCopy")

                    Button {
                        confirmNewLink = true
                    } label: {
                        Label("New link", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .disabled(working)
                    .accessibilityIdentifier("arena.inviteRenew")
                }
            }
        } else {
            Button("Close") { dismiss() }
                .buttonStyle(.tideGlass)
        }
    }

    // MARK: Loading

    private func load() async {
        stage = .loading
        copied = false
        do {
            stage = try await .ready(arena.inviteLink())
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func renew() async {
        working = true
        defer { working = false }
        do {
            try await arena.revokeInviteLink()
            await load()
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}
