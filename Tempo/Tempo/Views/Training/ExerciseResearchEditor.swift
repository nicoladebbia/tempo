//
// ExerciseResearchEditor.swift
// Tempo
//
// Review-screen sheet for a NEW exercise: shows what research found
// (muscles, equipment, pattern, instructions, cues) and lets the user fix
// any of it before the program is saved and the exercise joins the library.
//

import SwiftUI

struct ExerciseResearchEditor: View {
    let name: String
    let onSave: (ExerciseResearch) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var draft: ExerciseResearch
    @State
    private var cuesText: String

    init(name: String, research: ExerciseResearch, onSave: @escaping (ExerciseResearch) -> Void) {
        self.name = name
        self.onSave = onSave
        _draft = State(initialValue: research)
        _cuesText = State(initialValue: research.cues.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Main muscle", selection: $draft.muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Equipment", selection: $draft.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text(ExerciseResearch.label($0.rawValue)).tag($0) }
                    }
                    Picker("Movement", selection: $draft.movementPattern) {
                        ForEach(MovementPattern.allCases, id: \.self) { Text(ExerciseResearch.label($0.rawValue)).tag($0) }
                    }
                    Toggle("Compound lift", isOn: $draft.isCompound)
                        .tint(Color.tempoSignal)
                    if !draft.secondaryMuscles.isEmpty {
                        LabeledContent("Also works", value: draft.secondaryMuscles.map(\.displayName).joined(separator: ", "))
                    }
                } footer: {
                    Text("Looked up with AI — check it before saving. It's added to your exercise library with the program.")
                }

                Section("How to do it") {
                    TextField("Instructions", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3 ... 8)
                }

                Section("Form cues (one per line)") {
                    TextField("Cues", text: $cuesText, axis: .vertical)
                        .lineLimit(2 ... 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var edited = draft
                        edited.cues = cuesText
                            .split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        edited.secondaryMuscles.removeAll { $0 == edited.muscleGroup }
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
