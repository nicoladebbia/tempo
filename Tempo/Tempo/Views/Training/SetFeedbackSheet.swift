//
// SetFeedbackSheet.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import SwiftData
import SwiftUI

// MARK: - SetFeedbackSheet

/// Bottom sheet presented after a working set is logged (on "Finish Set").
/// Captures RPE, breathing difficulty, form quality, and an optional note,
/// then persists a `SetFeedback` linked to the set. Strings come from
/// UX_COPY_BIBLE (`feedback_*`); colors from the design system.
///
/// Per build done_when #12–13 and the Phase 2 decisions in findings:
/// triggered by Finish Set only (not rest-timer expiry); not re-prompted if
/// dismissed without saving; in-progress taps live in `@State` until Save
/// (accepted product gap — no draft model).
struct SetFeedbackSheet: View {
    /// The set this feedback is about.
    let plannedSet: PlannedSet

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State private var rpe: Int = 7
    @State private var breath: BreathDifficulty = .moderate
    @State private var form: FormQuality = .clean
    @State private var noteExpanded = false
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    // RPE
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("RPE")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        rpeDial
                    }

                    // Breathing
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("Breathing")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        segmentedRow(
                            options: BreathDifficulty.allCases,
                            selection: $breath,
                            label: { $0.displayName }
                        )
                    }

                    // Form
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("Form")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        segmentedRow(
                            options: FormQuality.allCases,
                            selection: $form,
                            label: { $0.displayName }
                        )
                    }

                    // Optional note (collapsed by default)
                    if noteExpanded {
                        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                            Text("Note")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                            TextField(
                                "Anything worth remembering?",
                                text: $note,
                                axis: .vertical
                            )
                            .lineLimit(2 ... 4)
                            .padding(TempoSpacing.cardPadding)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        }
                    } else {
                        Button {
                            withAnimation { noteExpanded = true }
                        } label: {
                            Text("+ Note")
                                .font(.tempoCallout)
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("How was that set?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - RPE Dial

    private var rpeDial: some View {
        HStack(spacing: TempoSpacing.xs) {
            ForEach(1 ... 10, id: \.self) { value in
                Button {
                    rpe = value
                    HapticManager.selection()
                } label: {
                    Text("\(value)")
                        .font(.tempoHeadline)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(rpe == value ? Color.tempoSignal : Color.tempoSurfaceCard)
                        .foregroundStyle(rpe == value ? .white : Color.tempoTextPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                }
            }
        }
    }

    // MARK: - Segmented Row

    private func segmentedRow<Option: Hashable>(
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                    HapticManager.selection()
                } label: {
                    Text(label(option))
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            selection.wrappedValue == option
                                ? Color.tempoSignal
                                : Color.tempoSurfaceCard
                        )
                        .foregroundStyle(
                            selection.wrappedValue == option
                                ? .white
                                : Color.tempoTextPrimary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedback = SetFeedback(
            plannedSet: plannedSet,
            rpe: rpe,
            breathDifficulty: breath,
            formQuality: form,
            note: trimmed.isEmpty ? nil : trimmed
        )
        modelContext.insert(feedback)
        try? modelContext.save()
        HapticManager.notification(.success)
        dismiss()
    }
}
