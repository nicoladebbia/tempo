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
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: geometry.size.height * 0.12)

                Text("WHO ARE YOU?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.xl)

                Spacer()
                    .frame(height: geometry.size.height * 0.08)

                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("Display Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("Your name", text: $viewModel.displayName)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .padding(TempoSpacing.md)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .displayName)
                }
                .padding(.horizontal, TempoSpacing.xl)

                Spacer()
                    .frame(height: geometry.size.height * 0.04)

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("Username")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("@username", text: $viewModel.username)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(TempoSpacing.md)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    usernameError != nil ? Color.tempoError.opacity(0.6) : Color.white.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                        .focused($focusedField, equals: .username)
                        .onChange(of: viewModel.username) { _, _ in
                            checkUsernameAvailability()
                        }

                    if let usernameError {
                        Text(usernameError)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoError)
                    } else if isUsernameValid {
                        Text("Available")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoSuccess)
                    }
                }
                .padding(.horizontal, TempoSpacing.xl)

                Spacer()

                OnboardingPrimaryButton(
                    title: "CONTINUE",
                    enabled: viewModel.canContinue && isUsernameValid && usernameError == nil
                ) {
                    viewModel.advance()
                }

                Spacer()
                    .frame(height: max(geometry.safeAreaInsets.bottom + 20, 40))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
        .background(Color.black)
        .preferredColorScheme(.dark)
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
        .background(Color.black)
        .preferredColorScheme(.dark)
}
