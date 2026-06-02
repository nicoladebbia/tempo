//
// InlineSetFeedbackView.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import SwiftData
import SwiftUI

// MARK: - InlineSetFeedbackView

/// Inline "How was that set?" panel rendered UNDER the rest timer (not a
/// modal sheet). The `SetFeedback` row is created eagerly in
/// `TrainingViewModel.logSet`; this panel edits it SAVE-ON-CHANGE via
/// `updateFeedback`, so the record survives the rest timer auto-advancing or
/// the user tapping "Skip Rest" instantly. No Save button — every tap/keystroke
/// persists. RPE is collected here only (the set-active screen no longer asks).
/// Strings from UX_COPY_BIBLE (`feedback_*`); colors from the design system.
struct InlineSetFeedbackView: View {
    @Bindable
    var viewModel: TrainingViewModel

    @Environment(\.modelContext)
    private var modelContext

    @State private var rpe: Int = 7
    @State private var breath: BreathDifficulty = .moderate
    @State private var form: FormQuality = .clean
    @State private var noteExpanded = false
    @State private var note: String = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Text("HOW WAS THAT SET?")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

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
                .onChange(of: breath) { _, newValue in
                    viewModel.updateFeedback(breath: newValue, modelContext: modelContext)
                }
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
                .onChange(of: form) { _, newValue in
                    viewModel.updateFeedback(form: newValue, modelContext: modelContext)
                }
            }

            // Optional note (collapsed by default) — write-through on edit.
            if noteExpanded {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack {
                        Text("Note")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Spacer()
                        // Explicit in-panel Done — the multi-line (axis: .vertical)
                        // field treats Return as a newline, and a .keyboard
                        // toolbar doesn't render reliably outside a NavigationStack
                        // (this panel lives under the rest timer). A visible button
                        // that resigns focus is the reliable dismiss.
                        if noteFocused {
                            Button("Done") { noteFocused = false }
                                .font(.tempoCaption1)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                    TextField(
                        "Anything worth remembering?",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .focused($noteFocused)
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .onChange(of: note) { _, newValue in
                        viewModel.updateFeedback(note: newValue, modelContext: modelContext)
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .padding(.horizontal, TempoSpacing.screenEdge)
        .onAppear(perform: seedFromFeedback)
    }

    /// Seed local controls from the eagerly-created feedback row so the panel
    /// reflects existing values (e.g. if the user returns to it).
    private func seedFromFeedback() {
        guard let feedback = viewModel.currentFeedback else {
            return
        }
        rpe = feedback.rpe
        breath = feedback.breathDifficulty
        form = feedback.formQuality
        note = feedback.note ?? ""
        noteExpanded = !(feedback.note ?? "").isEmpty
    }

    // MARK: - RPE Dial

    private var rpeDial: some View {
        // 6–10 only (below 6 is warmup-easy, not worth logging). Five large
        // buttons instead of ten cramped/stretched ones.
        HStack(spacing: TempoSpacing.sm) {
            ForEach(6 ... 10, id: \.self) { value in
                Button {
                    rpe = value
                    HapticManager.selection()
                    viewModel.updateFeedback(rpe: value, modelContext: modelContext)
                } label: {
                    Text("\(value)")
                        .font(.tempoTitle3)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(rpe == value ? Color.tempoSignal : Color.tempoSurfaceCard)
                        .foregroundStyle(rpe == value ? .white : Color.tempoTextPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
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

}
