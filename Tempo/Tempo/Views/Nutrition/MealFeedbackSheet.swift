//
// MealFeedbackSheet.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import SwiftData
import SwiftUI

/// Inline feedback capture surfaced right after a meal is marked eaten,
/// and reusable for the past-meal review badge and the end-of-week review
/// screen.
///
/// Design notes:
/// - Everything is optional. The sheet never blocks the user.
/// - Captures structured nuance, not a single thumbs-up/down — see
///   `MealFeedback.swift` for the field-level rationale.
/// - Saves a new `MealFeedback` row on confirm; updates the existing row
///   when one is passed in (review flow).
struct MealFeedbackSheet: View {
    let meal: PlannedMeal
    /// When non-nil, the sheet edits this existing row instead of inserting
    /// a new one. Lets the same UI power inline-capture and review flows.
    var existing: MealFeedback?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State private var rating: Int = 0
    @State private var overallNote: String = ""
    @State private var portionNote: String = ""
    @State private var suggestedChange: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ForEach(1 ... 5, id: \.self) { star in
                            Button {
                                rating = (rating == star) ? 0 : star
                                HapticManager.lightImpact()
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.system(size: 22))
                                    .foregroundStyle(star <= rating ? Color.tempoAmber : Color.tempoTextTertiary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, TempoSpacing.xs)
                } header: {
                    Text("How was it?")
                } footer: {
                    Text("Skip the stars if you only want to leave a note.")
                }

                Section("Overall") {
                    TextField("Loved this. Or didn't.", text: $overallNote, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section {
                    TextField("Too big, too small, just right…", text: $portionNote, axis: .vertical)
                        .lineLimit(1 ... 3)
                } header: {
                    Text("Portion")
                } footer: {
                    Text("If 100g feels right instead of 300g, say so. Plans will adapt.")
                }

                Section {
                    TextField("Add lemon. Swap rice for quinoa. Less salt.", text: $suggestedChange, axis: .vertical)
                        .lineLimit(1 ... 3)
                } header: {
                    Text("Next time")
                } footer: {
                    Text("Specific changes you want applied when this dish comes around again.")
                }
            }
            .navigationTitle(meal.mealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Save" : "Update") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: hydrateFromExisting)
        }
    }

    private var canSave: Bool {
        rating > 0
            || !overallNote.trimmingCharacters(in: .whitespaces).isEmpty
            || !portionNote.trimmingCharacters(in: .whitespaces).isEmpty
            || !suggestedChange.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func hydrateFromExisting() {
        guard let existing else {
            return
        }
        rating = existing.rating ?? 0
        overallNote = existing.overallNote ?? ""
        portionNote = existing.portionNote ?? ""
        suggestedChange = existing.suggestedChange ?? ""
    }

    private func save() {
        let trimmedOverall = overallNote.trimmingCharacters(in: .whitespaces)
        let trimmedPortion = portionNote.trimmingCharacters(in: .whitespaces)
        let trimmedChange = suggestedChange.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.rating = rating > 0 ? rating : nil
            existing.overallNote = trimmedOverall.isEmpty ? nil : trimmedOverall
            existing.portionNote = trimmedPortion.isEmpty ? nil : trimmedPortion
            existing.suggestedChange = trimmedChange.isEmpty ? nil : trimmedChange
        } else {
            let feedback = MealFeedback(
                plannedMeal: meal,
                rating: rating > 0 ? rating : nil,
                overallNote: trimmedOverall.isEmpty ? nil : trimmedOverall,
                portionNote: trimmedPortion.isEmpty ? nil : trimmedPortion,
                suggestedChange: trimmedChange.isEmpty ? nil : trimmedChange
            )
            modelContext.insert(feedback)
        }
        try? modelContext.save()
        HapticManager.notification(.success)
    }
}
