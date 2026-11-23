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

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Tide.s3) {
                Image(systemName: "leaf.fill")
                    .font(Tide.headline)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Track your staples")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text("\(remaining) quick yes/no taps. Salt, oil, spices.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.up")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .tideCard(padding: Tide.s4)
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
    @Environment(\.tideMood)
    private var mood

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
        viewModel.unansweredStapleCount
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if detent != .height(Self.peekHeight) {
                KitchenList {
                    Section {
                        ForEach(suggestions, id: \.canonicalName) { suggestion in
                            row(suggestion)
                        }
                    }
                    KitchenFormSection("Something else?") {
                        HStack {
                            TextField("Add your own staple", text: $customName)
                                .font(Tide.body)
                                .focused($customFocused)
                                .submitLabel(.done)
                                .onSubmit(addCustom)
                            Button("Add", action: addCustom)
                                .font(Tide.bodyStrong)
                                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            } else {
                Spacer(minLength: 0)
            }
        }
        .kitchenSheet()
    }

    static let peekHeight: CGFloat = 140

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Track your staples")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text(unanswered == 0 ? "All answered." : "\(unanswered) left. Do you have it?")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                Spacer()
                Button("Done") {
                    viewModel.applyStapleEvent(.complete)
                    dismiss()
                }
                .buttonStyle(.tidePrimary)
                .fixedSize()
            }
            HStack {
                Button("Skip for now") {
                    viewModel.applyStapleEvent(.skip)
                    dismiss()
                }
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .frame(minHeight: Tide.hit)
                Spacer()
                if detent == .height(Self.peekHeight) {
                    Button {
                        detent = .large
                    } label: {
                        Label("Open list", systemImage: "chevron.up")
                            .font(Tide.caption)
                            .frame(minHeight: Tide.hit)
                    }
                    .foregroundStyle(mood.accent)
                }
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s5)
    }

    // MARK: Row

    private func row(_ suggestion: (canonicalName: String, displayName: String)) -> some View {
        let current = answer(for: suggestion.canonicalName)
        return HStack(spacing: Tide.s2) {
            Text(suggestion.displayName)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Spacer()
            answerButton("Yes", selected: current == true, tint: Tide.Kitchen.good) {
                viewModel.answerStaple(suggestion, have: true)
                HapticManager.selection()
            }
            answerButton("No", selected: current == false, tint: Tide.text2) {
                viewModel.answerStaple(suggestion, have: false)
                HapticManager.selection()
            }
        }
        .frame(minHeight: Tide.Kitchen.row - Tide.s3)
        .accessibilityElement(children: .combine)
    }

    private func answerButton(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(selected ? Tide.ink : tint)
                .frame(minWidth: Tide.hit + Tide.s2, minHeight: Tide.hit)
                .background(selected ? tint : tint.opacity(0.14), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
