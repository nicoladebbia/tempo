//
// WeeklyUploadPromptCard.swift
// Tempo
//
// Weekly-upload feature — "New week — upload <program>'s next program".
// Shown on Today from Sunday 19:00 of the active WEEKLY program's served week
// onward (and every day after, while nothing covers the upcoming week —
// TrainerProgramWeeklyUpload/TrainingViewModel.weeklyUploadDue), so Nicola is
// never left wondering whether the old week is stale. Renders nothing for a
// `.block` program, or once the next week's program is uploaded. Self-
// contained, same pattern as MissedTrainerSessionCard.swift — dropped into
// TodayWorkoutView with a single line.
//

import Combine
import SwiftData
import SwiftUI

// MARK: - WeeklyUploadPromptCard

struct WeeklyUploadPromptCard: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var dueProgram: TrainerProgram?
    @State
    private var showImport = false

    /// Freshness for the Sunday-19:00 / week-rollover boundary while the app
    /// stays foregrounded — the same once-a-minute cadence Today's own
    /// countdown already uses elsewhere in this module.
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let dueProgram {
                card(for: dueProgram)
            }
        }
        .task(id: viewModel.todayPlan?.id) {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)) { _ in
            refresh()
        }
        .onReceive(refreshTimer) { _ in
            refresh()
        }
        .sheet(isPresented: $showImport, onDismiss: refresh) {
            TrainerProgramImportView()
        }
    }

    private func card(for program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoViolet)
                    .accessibilityHidden(true)
                Text("NEW WEEK")
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoViolet)
            }

            Text("Upload \(program.name)'s next program")
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your trainer sends a new one every week — get it in so Monday's ready.")
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)

            Button {
                showImport = true
            } label: {
                Label("Upload", systemImage: "square.and.arrow.up")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .background(Color.tempoViolet.opacity(TempoOpacity.o15))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, TempoSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoViolet.opacity(TempoOpacity.o15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .padding(.horizontal, TempoSpacing.lg)
    }

    private func refresh() {
        dueProgram = viewModel.weeklyUploadDue(modelContext: modelContext)
    }
}
