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
        OnboardingViewModel.isValidUsername(viewModel.username)
    }

    private func checkUsernameAvailability() {
        let username = viewModel.username.trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else {
            usernameError = nil
            return
        }
        if username.count < 3 {
            usernameError = String(localized: "At least 3 characters")
            return
        }
        if username.count > 30 {
            usernameError = String(localized: "Max 30 characters")
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if !username.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            usernameError = String(localized: "Letters, numbers, and underscores only")
            return
        }

        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.username == username }
        )
        descriptor.fetchLimit = 1
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        usernameError = count > 0 ? String(localized: "Username already taken") : nil
    }

    var body: some View {
        OnboardingScaffold(
            title: String(localized: "ABOUT YOU."),
            primaryTitle: String(localized: "CONTINUE"),
            primaryEnabled: viewModel.canContinue && usernameError == nil,
            primaryAction: { viewModel.advance() }
        ) {
            profileCard

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel(String(localized: "Display Name"))

                TextField("", text: $viewModel.displayName, prompt: Text("Your name").foregroundStyle(Tide.text3))
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text)
                    .focused($focusedField, equals: .displayName)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
                    .tideFieldSurface(focused: focusedField == .displayName)
            }

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel(String(localized: "Username"))

                TextField("", text: usernameBinding, prompt: Text("@username").foregroundStyle(Tide.text3))
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

            identityMenu
        }
        .onAppear {
            if viewModel.displayName.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    focusedField = .displayName
                }
            }
            checkUsernameAvailability()
        }
    }

    /// Typing in the handle makes it the person's own: it stops following the name.
    private var usernameBinding: Binding<String> {
        Binding(
            get: { viewModel.username },
            set: { newValue in
                if newValue != viewModel.username {
                    viewModel.usernameEdited = true
                    viewModel.username = newValue
                }
            }
        )
    }

    // MARK: - Identity

    /// "What best describes you?" as one menu: 20 options do not need a page of their own.
    private var identityMenu: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            OnboardingSectionLabel(String(localized: "What best describes you?"))
            Menu {
                Picker("What best describes you?", selection: $viewModel.identityLabel) {
                    ForEach(OnboardingViewModel.identityLabels, id: \.self) { label in
                        Text(OnboardingViewModel.identityDisplayName(label)).tag(label)
                    }
                }
            } label: {
                HStack(spacing: Tide.s2) {
                    Text(OnboardingViewModel.identityDisplayName(viewModel.identityLabel))
                        .font(Tide.headline.weight(.regular))
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
                .tideFieldSurface(focused: false)
                .contentShape(.rect)
            }
            .accessibilityIdentifier("onboardingIdentityMenu")
            .accessibilityLabel("What best describes you")
            .accessibilityValue(OnboardingViewModel.identityDisplayName(viewModel.identityLabel))
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
                Text(trimmedName.isEmpty ? String(localized: "Your name") : trimmedName)
                    .font(Tide.title2)
                    .foregroundStyle(trimmedName.isEmpty ? Tide.text3 : Tide.text)
                    .lineLimit(2)
                    .minimumScaleFactor(Tide.labelShrink)
                    .contentTransition(.interpolate)
                Text(trimmedUsername.isEmpty ? String(localized: "@username") : "@\(trimmedUsername)")
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
