//
//  AccountDetailView.swift
//  Tempo
//
//  Account: who is signed in, and the account deletion Apple requires.
//

import SwiftData
import SwiftUI

// MARK: - AccountDetailView

/// Surfaces account identity (sign-in method, user ID, member-since) and
/// houses the Apple-required in-app account deletion.
struct AccountDetailView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query
    private var allProfiles: [UserProfile]

    @State
    private var showDeleteConfirm = false
    @State
    private var isDeleting = false
    @State
    private var deleteError: String?

    private var profile: UserProfile? {
        allProfiles.first
    }

    var body: some View {
        TideSettingsPage {
            identityHero

            if !isSignedIn {
                SettingsSignInCard()
            }

            SettingsFormCard(title: "Identity") {
                SettingsInfoRow(
                    label: "Sign-in",
                    value: isSignedIn ? "Apple" : "Not signed in",
                    icon: "applelogo",
                    iconTint: Tide.text
                )
                SettingsRowDivider()
                SettingsInfoRow(label: "Member since", value: memberSince, icon: "calendar")
                if let id = userIDShort {
                    SettingsRowDivider()
                    SettingsInfoRow(label: "User ID", value: id, icon: "number")
                }
            }

            // The destructive group sits alone at the bottom, apart from the rest.
            TideSettingsSection(
                title: "Danger zone",
                footnote: "Deleting your account permanently removes all data — XP, achievements, streaks, and workout history. You'll be removed from all leaderboards and active challenges. This cannot be undone.",
                isDanger: true
            ) {
                Button { showDeleteConfirm = true } label: {
                    SettingsActionRow(icon: "trash", title: "Delete Account", tint: Tide.danger)
                }
                .buttonStyle(.tideSettingsRow)
                .disabled(isDeleting)
            }
            .padding(.top, Tide.s4)
        }
        .sensoryFeedback(.warning, trigger: showDeleteConfirm) { _, isShown in isShown }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) { Task { await performDeletion() } }
        } message: {
            Text("This permanently deletes all your data. This cannot be undone.")
        }
        .alert("Could not delete account", isPresented: Binding(
            get: { deleteError != nil }, set: {
                if !$0 {
                    deleteError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Who this is and whether the data is backed up, before the details.
    private var identityHero: some View {
        let name = profile?.displayName.isEmpty == false ? (profile?.displayName ?? "Athlete") : "Athlete"
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return TideSettingsHero {
            layout {
                TideSettingsAvatar(initial: String(name.prefix(1)).uppercased(), diameter: Tide.settingsAvatarLarge)
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text(name)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Tide.s2) {
                        Circle()
                            .fill(isSignedIn ? mood.accent : Tide.text3)
                            .frame(width: Tide.s2, height: Tide.s2)
                            .shadow(color: isSignedIn ? mood.accent : .clear, radius: Tide.s1)
                            .accessibilityHidden(true)
                        Text(isSignedIn ? "Backed up to your account" : "Only on this phone")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if let days = daysWithTempo {
                TideSettingsHairline(inset: 0)
                    .padding(.vertical, Tide.s1)
                TideNumber(
                    "\(days)", unit: days == 1 ? "day with Tempo" : "days with Tempo",
                    size: Tide.numeralM, relativeTo: .title
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Days since the profile was created, counting the first day as day one.
    private var daysWithTempo: Int? {
        guard let created = profile?.createdAt else {
            return nil
        }
        let start = Calendar.current.startOfDay(for: created)
        let today = Calendar.current.startOfDay(for: Date())
        return max(0, Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0) + 1
    }

    private var memberSince: String {
        guard let created = profile?.createdAt else {
            return "—"
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: created)
    }

    private var isSignedIn: Bool {
        if case .authenticated = services.authService.authState {
            return true
        }
        return false
    }

    private var userIDShort: String? {
        if case let .authenticated(userID) = services.authService.authState {
            return String(userID.prefix(8)) + "…"
        }
        return nil
    }

    @MainActor
    private func performDeletion() async {
        guard !isDeleting else {
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.authService.deleteAccount()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
