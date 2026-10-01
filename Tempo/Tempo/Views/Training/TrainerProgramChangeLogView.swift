//
// TrainerProgramChangeLogView.swift
// Tempo
//
// trainer-feedback-tests — read-only history of "Trainer sent changes"
// batches applied to this program (`TrainerProgram.changeLog`), newest
// first. Reached from `TrainerProgramView`'s "Changes from Trainer" row.
//

import SwiftData
import SwiftUI

struct TrainerProgramChangeLogView: View {
    let program: TrainerProgram

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var undoError: String?

    /// Dated skips that still matter (today or later), soonest first — each
    /// can be put back with Undo.
    private var upcomingSkips: [TrainerProgramSkip] {
        let today = Calendar.current.startOfDay(for: Date())
        return program.skippedSessions.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    private var entries: [TrainerProgramChangeLogEntry] {
        program.changeLog.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if !upcomingSkips.isEmpty {
                Section {
                    ForEach(upcomingSkips) { skip in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skip.summary)
                                    .font(.tempoBody)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(skip.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                            Spacer()
                            Button("Undo") { undo(skip) }
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoSignal)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("SKIPPED — ONLY THAT DAY")
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }
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
        .alert(
            "Couldn't undo",
            isPresented: Binding(get: { undoError != nil }, set: {
                if !$0 {
                    undoError = nil
                }
            })
        ) {
            Button("OK") {}
        } message: {
            Text(undoError ?? "")
        }
        .overlay {
            if entries.isEmpty, upcomingSkips.isEmpty {
                Text("No changes logged yet.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    private func undo(_ skip: TrainerProgramSkip) {
        do {
            try TrainerProgramSaver.undoSkip(
                skip,
                in: program,
                modelContext: modelContext,
                trainingEngine: services.trainingEngine,
                whoop: services.whoop,
                healthKit: services.healthKit
            )
        } catch {
            undoError = error.localizedDescription
        }
    }
}
