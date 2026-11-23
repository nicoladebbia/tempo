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
                                    .font(Tide.title2)
                                    .foregroundStyle(star <= rating ? Tide.warn : Tide.text3)
                                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                        }
                    }
                    .fuelRow()
                } header: {
                    Text("How was it?").tideLabel()
                } footer: {
                    Text("Skip the stars if you only want to leave a note.")
                        .font(Tide.caption).foregroundStyle(Tide.text3)
                }

                Section {
                    TextField("Loved this. Or didn't.", text: $overallNote, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .fuelRow()
                } header: {
                    Text("Overall").tideLabel()
                }

                Section {
                    TextField("Too big, too small, just right…", text: $portionNote, axis: .vertical)
                        .lineLimit(1 ... 3)
                        .fuelRow()
                } header: {
                    Text("Portion").tideLabel()
                } footer: {
                    Text("If 100g feels right instead of 300g, say so. Plans will adapt.")
                        .font(Tide.caption).foregroundStyle(Tide.text3)
                }

                Section {
                    TextField("Add lemon. Swap rice for quinoa. Less salt.", text: $suggestedChange, axis: .vertical)
                        .lineLimit(1 ... 3)
                        .fuelRow()
                } header: {
                    Text("Next time").tideLabel()
                } footer: {
                    Text("Specific changes you want applied when this dish comes around again.")
                        .font(Tide.caption).foregroundStyle(Tide.text3)
                }
            }
            .font(Tide.body)
            .scrollContentBackground(.hidden)
            .tidePage()
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
