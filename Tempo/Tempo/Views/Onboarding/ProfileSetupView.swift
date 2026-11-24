//
// ProfileSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Profile Setup View

// Per STATE_MACHINES.md Section 10 — Display name, username. REQUIRED.
// Per BUILD_PLAN step 16.1 — Name, weight, height.
//
// Who you are, drawn live: a profile card at the top fills in as you type, so
// the two fields below it read as building something, not filling a form.

struct ProfileSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @FocusState
    private var focusedField: Field?
    @State
    private var usernameError: String?
    @ScaledMetric(relativeTo: .title)
    private var avatarSize: CGFloat = Tide.tileLarge + Tide.s2

    enum Field {
        case displayName
        case username
    }

    private var isUsernameValid: Bool {
        let username = viewModel.username.trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else {
            return false
        }
        if username.count < 3 {
            return false
        }
        if username.count > 30 {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func checkUsernameAvailability() {
        let username = viewModel.username.trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else {
            usernameError = nil
            return
        }
        if username.count < 3 {
            usernameError = "At least 3 characters"
            return
        }
        if username.count > 30 {
            usernameError = "Max 30 characters"
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if !username.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            usernameError = "Letters, numbers, and underscores only"
            return
        }

        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.username == username }
        )
        descriptor.fetchLimit = 1
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        usernameError = count > 0 ? "Username already taken" : nil
    }

    var body: some View {
        OnboardingScaffold(
            title: "WHO ARE YOU?",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.canContinue && isUsernameValid && usernameError == nil,
            primaryAction: { viewModel.advance() }
        ) {
            profileCard

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Display Name")

                TextField("", text: $viewModel.displayName, prompt: Text("Your name").foregroundStyle(Tide.text3))
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text)
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
                    .tideFieldSurface(focused: focusedField == .displayName)
            }

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Username")

                TextField("", text: $viewModel.username, prompt: Text("@username").foregroundStyle(Tide.text3))
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.done)
                    .onChange(of: viewModel.username) { _, _ in
                        checkUsernameAvailability()
                    }
                    .tideFieldSurface(focused: focusedField == .username, invalid: usernameError != nil)

                if let usernameError {
                    Label(usernameError, systemImage: "exclamationmark.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                } else if isUsernameValid {
                    Label("Available", systemImage: "checkmark.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.good)
                }
            }
            .animation(Tide.snap, value: usernameError)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = .displayName
            }
        }
    }

    // MARK: - Profile card

    private var trimmedName: String {
        viewModel.displayName.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedUsername: String {
        viewModel.username.trimmingCharacters(in: .whitespaces)
    }

    /// The card that fills in as you type: your initial, your name, your handle.
    private var profileCard: some View {
        HStack(spacing: Tide.s4) {
            avatar
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(trimmedName.isEmpty ? "Your name" : trimmedName)
                    .font(Tide.title2)
                    .foregroundStyle(trimmedName.isEmpty ? Tide.text3 : Tide.text)
                    .lineLimit(2)
                    .minimumScaleFactor(Tide.labelShrink)
                    .contentTransition(.interpolate)
                Text(trimmedUsername.isEmpty ? "@username" : "@\(trimmedUsername)")
                    .font(Tide.body)
                    .foregroundStyle(trimmedUsername.isEmpty ? Tide.text3 : Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            Spacer(minLength: 0)
        }
        .tideCard(padding: Tide.s4, radius: Tide.cardRadius)
        .animation(Tide.snap, value: trimmedName.isEmpty)
        .animation(Tide.snap, value: trimmedUsername.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile preview")
        .accessibilityValue(
            "\(trimmedName.isEmpty ? "No name yet" : trimmedName), \(trimmedUsername.isEmpty ? "no username yet" : "@\(trimmedUsername)")"
        )
    }

    private var avatar: some View {
        let initial = trimmedName.first.map { String($0).uppercased() }
        return ZStack {
            Circle()
                .fill(mood.accent.opacity(initial == nil ? 0.12 : 0.9))
                .shadow(color: mood.accent.opacity(initial == nil ? 0 : 0.5), radius: Tide.s3)
            if let initial {
                Text(initial)
                    .font(Tide.numeral(avatarSize * 0.5, .heavy))
                    .foregroundStyle(Tide.ink)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: avatarSize * 0.42, weight: .semibold))
                    .foregroundStyle(mood.accent)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .animation(Tide.snap, value: initial)
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    ProfileSetupView(viewModel: vm)
        .tidePage(energy: 1)
}

#Preview("Filled") {
    @Previewable @State
    var vm = {
        let vm = OnboardingViewModel()
        vm.displayName = "Nicola"
        vm.username = "nicola"
        return vm
    }()

    ProfileSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
