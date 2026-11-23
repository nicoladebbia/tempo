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

struct ProfileSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @FocusState
    private var focusedField: Field?
    @State
    private var usernameError: String?

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
                    Text(usernameError)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                } else if isUsernameValid {
                    Text("Available")
                        .font(Tide.caption)
                        .foregroundStyle(Color.tempoSuccess)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = .displayName
            }
        }
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
