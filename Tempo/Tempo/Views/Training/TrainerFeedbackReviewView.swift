//
// TrainerFeedbackReviewView.swift
// Tempo
//
// trainer-feedback-tests — diff review for "Trainer sent changes": one row
// per resolved edit, each toggleable on/off (matched, defaults ON) or shown
// disabled with "couldn't match" (unmatched — left for the athlete to fix
// by hand elsewhere). Apply runs the accepted subset through
// `TrainerProgramSaver.applyFeedback` — the same in-place `update` path
// every other program edit takes, so today's plan re-applies and
// `.tempoTrainingSettingsChanged` posts.
//

import SwiftData
import SwiftUI

// MARK: - TrainerFeedbackReviewView

struct TrainerFeedbackReviewView: View {
    let program: TrainerProgram
    let sourceText: String
    let edits: [ResolvedTrainerFeedbackEdit]
    var onApplied: () -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var acceptedIDs: Set<UUID>
    @State
    private var applyError: String?

    init(program: TrainerProgram, sourceText: String, edits: [ResolvedTrainerFeedbackEdit], onApplied: @escaping () -> Void) {
        self.program = program
        self.sourceText = sourceText
        self.edits = edits
        self.onApplied = onApplied
        // Every matched edit starts ON — the athlete un-checks anything they
        // don't want, rather than having to opt every edit in one by one.
        _acceptedIDs = State(initialValue: Set(edits.filter(\.matched).map(\.id)))
    }

    private var matchedEdits: [ResolvedTrainerFeedbackEdit] {
        edits.filter(\.matched)
    }

    private var unmatchedEdits: [ResolvedTrainerFeedbackEdit] {
        edits.filter { !$0.matched }
    }

    var body: some View {
        NavigationStack {
            Form {
                if matchedEdits.isEmpty, unmatchedEdits.isEmpty {
                    Section {
                        Text("No changes found in that message.")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                    }
                    .listRowBackground(Tide.fill)
                }
                if !matchedEdits.isEmpty {
                    Section("Changes") {
                        ForEach(matchedEdits) { edit in
                            Toggle(isOn: binding(for: edit.id)) {
                                Text(edit.summary)
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text)
                            }
                            .tint(Color.accentColor)
                        }
                    }
                    .listRowBackground(Tide.fill)
                }
                if !unmatchedEdits.isEmpty {
                    Section {
                        ForEach(unmatchedEdits) { edit in
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text(edit.summary)
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text3)
                                Text(edit.matchFailureReason ?? "Couldn't match.")
                                    .font(Tide.caption)
                                    .foregroundStyle(TideTrain.caution)
                            }
                        }
                    } header: {
                        Text("COULDN'T MATCH")
                    } footer: {
                        Text("Fix these yourself on the program's Edit screen if you still want them.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(acceptedIDs.isEmpty)
                }
            }
            .alert(
                "Couldn't apply",
                isPresented: Binding(get: { applyError != nil }, set: {
                    if !$0 {
                        applyError = nil
                    }
                })
            ) {
                Button("OK") {}
            } message: {
                Text(applyError ?? "")
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { acceptedIDs.contains(id) },
            set: { isOn in
                if isOn {
                    acceptedIDs.insert(id)
                } else {
                    acceptedIDs.remove(id)
                }
            }
        )
    }

    private func apply() {
        do {
            try TrainerProgramSaver.applyFeedback(
                edits,
                acceptedIDs: acceptedIDs,
                to: program,
                sourceText: sourceText,
                modelContext: modelContext,
                trainingEngine: services.trainingEngine,
                whoop: services.whoop,
                healthKit: services.healthKit
            )
            onApplied()
        } catch {
            applyError = error.localizedDescription
        }
    }
}
