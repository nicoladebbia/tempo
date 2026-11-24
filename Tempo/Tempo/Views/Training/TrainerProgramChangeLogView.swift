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
        TrainPlanPage {
            if entries.isEmpty, upcomingSkips.isEmpty {
                TrainEmptyCard(
                    systemImage: "text.bubble",
                    title: "No changes logged yet.",
                    message: "Changes you apply from a trainer message are listed here, newest first."
                )
                .padding(.top, Tide.s4)
            }
            if !entries.isEmpty {
                logHero
            }
            if !upcomingSkips.isEmpty {
                TrainPlanCard(label: "Skipped — only that day") {
                    ForEach(Array(upcomingSkips.enumerated()), id: \.element.id) { index, skip in
                        if index > 0 {
                            TrainPlanDivider()
                        }
                        skipRow(skip)
                    }
                }
            }
            ForEach(entries) { entry in
                entryCard(entry)
            }
        }
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
    }

    private var totalEdits: Int {
        entries.reduce(0) { $0 + $1.editSummaries.count }
    }

    /// How much the trainer has changed so far, and when it last happened.
    private var logHero: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Applied so far").tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber("\(totalEdits)", size: Tide.numeralM, relativeTo: .title)
                Text(totalEdits == 1 ? "edit from your trainer" : "edits from your trainer")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = entries.first {
                Text("Last change \(last.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            if !upcomingSkips.isEmpty {
                TrainTag(
                    text: upcomingSkips.count == 1 ? "1 day skipped ahead" : "\(upcomingSkips.count) days skipped ahead",
                    systemImage: "forward.fill",
                    color: TideTrain.caution
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
        .accessibilityElement(children: .combine)
    }

    private func skipRow(_ skip: TrainerProgramSkip) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                skipInfo(skip)
                Spacer(minLength: Tide.s2)
                undoButton(skip)
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                skipInfo(skip)
                undoButton(skip)
            }
        }
    }

    private func skipInfo(_ skip: TrainerProgramSkip) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(skip.summary)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(skip.date.formatted(date: .abbreviated, time: .omitted))
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
    }

    private func undoButton(_ skip: TrainerProgramSkip) -> some View {
        Button {
            undo(skip)
        } label: {
            Text("Undo")
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func entryCard(_ entry: TrainerProgramChangeLogEntry) -> some View {
        TrainPlanCard(label: entry.date.formatted(date: .abbreviated, time: .shortened)) {
            ForEach(Array(entry.editSummaries.enumerated()), id: \.offset) { index, summary in
                if index > 0 {
                    TrainPlanDivider()
                }
                if entry.isUndone(summary) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(summary)
                            .font(Tide.body)
                            .strikethrough()
                            .foregroundStyle(Tide.text3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Skip undone")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(summary)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !entry.sourceText.isEmpty {
                TrainPlanDivider()
                DisclosureGroup("Original message") {
                    Text(entry.sourceText)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Tide.s1)
                }
                .font(Tide.body)
                .tint(Tide.text2)
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
