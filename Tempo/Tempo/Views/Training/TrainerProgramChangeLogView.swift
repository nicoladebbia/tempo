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
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text(skip.summary)
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text)
                                Text(skip.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text3)
                            }
                            Spacer()
                            Button("Undo") { undo(skip) }
                                .font(Tide.body)
                                .foregroundStyle(Color.accentColor)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Skipped — only that day")
                }
                .listRowBackground(Tide.fill)
            }
            ForEach(entries) { entry in
                Section {
                    ForEach(entry.editSummaries, id: \.self) { summary in
                        if entry.isUndone(summary) {
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text(summary)
                                    .font(Tide.body)
                                    .strikethrough()
                                    .foregroundStyle(Tide.text3)
                                Text("Skip undone")
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text3)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            Text(summary)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                        }
                    }
                    if !entry.sourceText.isEmpty {
                        DisclosureGroup("Original message") {
                            Text(entry.sourceText)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                } header: {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                .listRowBackground(Tide.fill)
            }
        }
        .scrollContentBackground(.hidden)
        .tidePage()
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
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
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
