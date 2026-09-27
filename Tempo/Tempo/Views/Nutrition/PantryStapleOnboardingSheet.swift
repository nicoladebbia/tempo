//
// PantryStapleOnboardingSheet.swift
// Tempo
//
// First-open checklist for the Staples section — a suggestion, not a
// forced seed. Nothing is added until the user confirms; a vegan or
// gluten-free kitchen can just skip the whole thing.
//

import SwiftUI

struct PantryStapleOnboardingSheet: View {
    /// Called once with the picked suggestions when the user taps Save.
    /// Never called if they tap Skip.
    let onConfirm: ([(canonicalName: String, displayName: String)]) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var selected: Set<String> = Set(
        PantryStaple.commonSuggestions.prefix(10).map(\.canonicalName)
    )

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Staples are tracked as have / running low / out — never a quantity. Pick the ones you keep stocked.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Section("Suggestions") {
                    ForEach(PantryStaple.commonSuggestions, id: \.canonicalName) { suggestion in
                        Button {
                            toggle(suggestion.canonicalName)
                        } label: {
                            HStack {
                                Text(suggestion.displayName)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Spacer()
                                if selected.contains(suggestion.canonicalName) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.tempoSignal)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(Color.tempoTextTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Track your staples?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add \(selected.count)") {
                        let picks = PantryStaple.commonSuggestions.filter { selected.contains($0.canonicalName) }
                        onConfirm(picks)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ canonicalName: String) {
        if selected.contains(canonicalName) {
            selected.remove(canonicalName)
        } else {
            selected.insert(canonicalName)
        }
    }
}
