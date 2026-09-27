//
// TrainerProgramChangeLogView.swift
// Tempo
//
// trainer-feedback-tests — read-only history of "Trainer sent changes"
// batches applied to this program (`TrainerProgram.changeLog`), newest
// first. Reached from `TrainerProgramView`'s "Changes from Trainer" row.
//

import SwiftUI

struct TrainerProgramChangeLogView: View {
    let program: TrainerProgram

    private var entries: [TrainerProgramChangeLogEntry] {
        program.changeLog.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section {
                    ForEach(entry.editSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    if !entry.sourceText.isEmpty {
                        DisclosureGroup("Original message") {
                            Text(entry.sourceText)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                } header: {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Changes from Trainer")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if entries.isEmpty {
                Text("No changes logged yet.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }
}
