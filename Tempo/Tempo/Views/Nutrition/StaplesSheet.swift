//
// StaplesSheet.swift
// Tempo
//
// "Track your staples": the peek card at the bottom of Pantry and the sheet
// it opens (detents ~140pt -> large). Yes / No per staple, plus a custom
// one. Swiping the sheet down keeps the peek card; Skip hides it (the
// Staples chip on Pantry still opens this).
//

import SwiftUI

// MARK: - StaplesPeekCard

struct StaplesPeekCard: View {
    let remaining: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "leaf.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track your staples")
                        .font(.tempoBody.weight(.semibold))
                    Text("\(remaining) quick yes/no taps. Salt, oil, spices.")
                        .font(.tempoCaption1)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(Color.tempoBone)
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSignal, in: RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("staplesPeekCard")
        .accessibilityHint("Opens the staples checklist")
    }
}

// MARK: - StaplesSheet

struct StaplesSheet: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Binding
    var detent: PresentationDetent

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var customName = ""
    @FocusState
    private var customFocused: Bool

    private var suggestions: [(canonicalName: String, displayName: String)] {
        viewModel.stapleSuggestions
    }

    private func answer(for key: String) -> Bool? {
        let canonical = FoodCanonicalizer.canonicalize(key)
        if viewModel.stapleState.staples.contains(where: { $0.canonicalName == canonical }) {
            return true
        }
        return viewModel.stapleState.declined.contains(key) ? false : nil
    }

    private var unanswered: Int {
        suggestions.filter { answer(for: $0.canonicalName) == nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if detent != .height(Self.peekHeight) {
                Divider()
                List {
                    Section {
                        ForEach(suggestions, id: \.canonicalName) { suggestion in
                            row(suggestion)
                        }
                    }
                    Section("Something else?") {
                        HStack {
                            TextField("Add your own staple", text: $customName)
                                .focused($customFocused)
                                .submitLabel(.done)
                                .onSubmit(addCustom)
                            Button("Add", action: addCustom)
                                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(Color.tempoBgPrimary)
    }

    static let peekHeight: CGFloat = 140

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track your staples")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(unanswered == 0 ? "All answered." : "\(unanswered) left. Do you have it?")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Button("Done") {
                    viewModel.applyStapleEvent(.complete)
                    dismiss()
                }
                .font(.tempoSubheadline.weight(.semibold))
            }
            HStack {
                Button("Skip for now") {
                    viewModel.applyStapleEvent(.skip)
                    dismiss()
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                Spacer()
                if detent == .height(Self.peekHeight) {
                    Button {
                        detent = .large
                    } label: {
                        Label("Open list", systemImage: "chevron.up")
                            .font(.tempoCaption1.weight(.semibold))
                    }
                    .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
    }

    // MARK: Row

    private func row(_ suggestion: (canonicalName: String, displayName: String)) -> some View {
        let current = answer(for: suggestion.canonicalName)
        return HStack(spacing: TempoSpacing.md) {
            Text(suggestion.displayName)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            answerButton("Yes", selected: current == true, tint: .tempoSuccess) {
                viewModel.answerStaple(suggestion, have: true)
                HapticManager.selection()
            }
            answerButton("No", selected: current == false, tint: .tempoTextSecondary) {
                viewModel.answerStaple(suggestion, have: false)
                HapticManager.selection()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func answerButton(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tempoCaption1.weight(.semibold))
                .foregroundStyle(selected ? Color.tempoBone : tint)
                .frame(width: 48, height: 32)
                .background(selected ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        viewModel.addStaple(canonicalName: name, displayName: name.prefix(1).uppercased() + name.dropFirst())
        customName = ""
        HapticManager.success()
    }
}
