//
// TrainerChangesSection.swift
// Tempo
//
// The "Changes from your trainer" part of the Trainer page: what the trainer
// has changed so far (`TrainerProgram.changeLog`, newest first), the one-off
// skipped days that can still be put back, and the button that takes a new
// message from the trainer. It used to be a page of its own; it now sits
// inside `TrainerProgramView` so the whole trainer loop is in one place.
//

import SwiftData
import SwiftUI

// MARK: - TrainerChangesSection

struct TrainerChangesSection: View {
    let program: TrainerProgram
    /// Opens the "Trainer Sent Changes" sheet.
    let onTrainerSentChanges: () -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var undoError: String?
    @State
    private var showsAll = false

    /// How many log entries show before "Show all".
    private static let collapsedEntryCount = 3

    /// Dated skips that still matter (today or later), soonest first. Each
    /// can be put back with Undo.
    private var upcomingSkips: [TrainerProgramSkip] {
        let today = Calendar.current.startOfDay(for: Date())
        return program.skippedSessions.filter { $0.date >= today }.sorted { $0.date < $1.date }
    }

    private var entries: [TrainerProgramChangeLogEntry] {
        program.changeLog.sorted { $0.date > $1.date }
    }

    private var visibleEntries: [TrainerProgramChangeLogEntry] {
        showsAll ? entries : Array(entries.prefix(Self.collapsedEntryCount))
    }

    private var totalEdits: Int {
        entries.reduce(0) { $0 + $1.editSummaries.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Changes from your trainer"))
                .padding(.top, Tide.s2)

            if entries.isEmpty, upcomingSkips.isEmpty {
                emptyCard
            } else {
                if !entries.isEmpty {
                    summaryCard
                }
                if !upcomingSkips.isEmpty {
                    skipsCard
                }
                ForEach(visibleEntries) { entry in
                    entryCard(entry)
                }
                if entries.count > Self.collapsedEntryCount {
                    showAllButton
                }
            }

            Button(action: onTrainerSentChanges) {
                Label("Trainer Sent Changes", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.trainPlanSecondary)
        }
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

    // MARK: - Empty

    private var emptyCard: some View {
        TrainEmptyCard(
            systemImage: "text.bubble",
            title: String(localized: "No changes yet"),
            message: String(localized: "When your trainer replies with changes, paste their message here and Tempo applies it to your program.")
        )
    }

    // MARK: - Summary

    /// How much the trainer has changed so far, and when it last happened.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Applied so far").tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber("\(totalEdits)", size: Tide.numeralM, relativeTo: .title)
                Text(totalEdits == 1 ? String(localized: "edit from your trainer") : String(localized: "edits from your trainer"))
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
                    text: String(localized: "\(upcomingSkips.count) days skipped ahead"),
                    systemImage: "forward.fill",
                    color: TideTrain.caution
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Skipped days

    private var skipsCard: some View {
        TrainPlanCard(label: String(localized: "Skipped, only that day")) {
            ForEach(Array(upcomingSkips.enumerated()), id: \.element.id) { index, skip in
                if index > 0 {
                    TrainPlanDivider()
                }
                skipRow(skip)
            }
        }
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
        .accessibilityLabel("Undo skip, \(skip.summary)")
    }

    // MARK: - Log entries

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

    private var showAllButton: some View {
        Button {
            withAnimation(Tide.snap) {
                showsAll.toggle()
            }
        } label: {
            Text(showsAll ? String(localized: "Show fewer") : String(localized: "Show all \(entries.count) changes"))
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Undo

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
