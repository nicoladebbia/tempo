//
// InlineSetFeedbackView.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import SwiftData
import SwiftUI
import UIKit

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

    /// nil = not answered yet. Nothing is pre-selected: a highlighted "7"
    /// looked like an answer the athlete never gave.
    @State
    private var rpe: Int?
    @State
    private var breath: BreathDifficulty?
    @State
    private var form: FormQuality?
    @State
    private var noteExpanded = false
    @State
    private var note: String = ""
    @FocusState
    private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("How was that set?").tideLabel()

            // RPE — 6–10 only (below 6 is warmup-easy, not worth logging).
            // Five large buttons instead of ten cramped/stretched ones.
            TrainSessionChoiceRow(
                title: String(localized: "RPE"),
                options: Array(6 ... 10),
                selection: rpe,
                label: { "\($0)" }
            ) { value in
                rpe = value
                viewModel.updateFeedback(rpe: value, modelContext: modelContext)
            }

            TrainSessionChoiceRow(
                title: String(localized: "Breathing"),
                options: BreathDifficulty.allCases,
                selection: breath,
                height: Tide.hit,
                label: { $0.displayName }
            ) { value in
                breath = value
                viewModel.updateFeedback(breath: value, modelContext: modelContext)
            }

            TrainSessionChoiceRow(
                title: String(localized: "Form"),
                options: FormQuality.allCases,
                selection: form,
                height: Tide.hit,
                label: { $0.displayName }
            ) { value in
                form = value
                viewModel.updateFeedback(form: value, modelContext: modelContext)
            }

            // Optional note (collapsed by default) — write-through on edit.
            if noteExpanded {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack {
                        Text("Note").tideLabel()
                        Spacer()
                        // Always-visible "Done" while editing — the field is
                        // multi-line (Return = newline) and the keyboard toolbar
                        // proved unreliable on-device, so this guaranteed button
                        // force-resigns the keyboard via UIKit.
                        if noteFocused {
                            Button("Done") {
                                noteFocused = false
                                Self.dismissKeyboard()
                            }
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Color.accentColor)
                            .frame(minHeight: Tide.hit)
                        }
                    }
                    TextField(
                        "Anything worth remembering?",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .focused($noteFocused)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .tideFieldSurface(focused: noteFocused)
                    .onChange(of: note) { _, newValue in
                        viewModel.updateFeedback(note: newValue, modelContext: modelContext)
                    }
                }
            } else {
                Button {
                    withAnimation(Tide.snap) { noteExpanded = true }
                } label: {
                    Label("Note", systemImage: "plus")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                        .contentShape(.rect)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .onAppear(perform: seedFromFeedback)
        // Keyboard-accessory "Done" as well (belt-and-suspenders with the visible
        // in-panel Done button above, which is the guaranteed path on device).
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    noteFocused = false
                    Self.dismissKeyboard()
                }
                .font(Tide.headline)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Force-resign the first responder via UIKit — reliable regardless of the
    /// SwiftUI view hierarchy (the @FocusState/keyboard-toolbar path proved
    /// flaky on device for this nested, non-Form panel).
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// Seed local controls from the eagerly-created feedback row so the panel
    /// reflects existing values (e.g. if the user returns to it).
    private func seedFromFeedback() {
        guard let feedback = viewModel.currentFeedback else {
            return
        }
        // Only fields the athlete already entered light up.
        rpe = feedback.hasEnteredRPE ? feedback.rpe : nil
        breath = feedback.hasEnteredBreath ? feedback.breathDifficulty : nil
        form = feedback.hasEnteredForm ? feedback.formQuality : nil
        note = feedback.note ?? ""
        noteExpanded = !(feedback.note ?? "").isEmpty
    }
}
