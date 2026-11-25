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
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    stars
                    noteField(
                        String(localized: "Overall"), prompt: "Loved this. Or didn't.", text: $overallNote, lines: 2 ... 4
                    )
                    noteField(
                        String(localized: "Portion"), prompt: "Too big, too small, just right…", text: $portionNote, lines: 1 ... 3,
                        footnote: String(localized: "If 100g feels right instead of 300g, say so. Plans will adapt.")
                    )
                    noteField(
                        String(localized: "Next time"), prompt: "Add lemon. Swap rice for quinoa. Less salt.", text: $suggestedChange,
                        lines: 1 ... 3,
                        footnote: String(localized: "Specific changes you want applied when this dish comes around again.")
                    )
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            // The one action sits under the thumb, in the standard button.
            .fuelBottomBar {
                Button(existing == nil ? String(localized: "Save") : String(localized: "Update")) {
                    save()
                    dismiss()
                }
                .buttonStyle(.tidePrimary)
                .disabled(!canSave)
                .accessibilityIdentifier("mealFeedbackSave")
            }
            .tidePage()
            .navigationTitle(meal.displayMealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .onAppear(perform: hydrateFromExisting)
        }
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
    }

    /// Five big stars in one card: the quickest way to say how it was.
    private var stars: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: String(localized: "How was it?"))
                .padding(.horizontal, Tide.s1)
            HStack(spacing: Tide.s1) {
                ForEach(1 ... 5, id: \.self) { star in
                    Button {
                        rating = (rating == star) ? 0 : star
                        HapticManager.lightImpact()
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(Tide.title)
                            .foregroundStyle(star <= rating ? Tide.warn : Tide.text3)
                            .symbolEffect(.bounce, value: rating == star)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s2)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                }
            }
            .animation(Tide.snap, value: rating)
            .tideCard(padding: Tide.s2, radius: Tide.tileRadius)
            Text("Skip the stars if you only want to leave a note.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .padding(.horizontal, Tide.s1)
        }
    }

    private func noteField(
        _ title: String, prompt: String, text: Binding<String>, lines: ClosedRange<Int>, footnote: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: title)
                .padding(.horizontal, Tide.s1)
            TextField(prompt, text: text, axis: .vertical)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .lineLimit(lines)
                .padding(.vertical, Tide.s2)
                .fuelField(radius: Tide.tileRadius)
            if let footnote {
                Text(footnote)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s1)
            }
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
