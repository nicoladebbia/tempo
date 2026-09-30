//
// TodayWorkoutView+ExtraGym.swift
// Tempo
//
// Tomorrow card hosting, the composite-day parts card (soccer done + extra
// gym session), the "Add gym session" entry and the "Log that I played" time
// picker. Split out of TodayWorkoutView.swift to keep it under the SwiftLint
// file/type-body length caps.
//

import SwiftUI

extension TodayWorkoutView {
    // MARK: - Tomorrow

    /// Changes whenever today's plan (or the week) changes shape, so the
    /// preview follows an added/removed gym session and schedule edits.
    var tomorrowReloadKey: String {
        let plan = viewModel.todayPlan
        return "\(plan?.id.uuidString ?? "-")|\(plan?.typeRaw ?? "-")|\(plan?.statusRaw ?? "-")|\(plan?.companionCompleted ?? false)|\(viewModel.weekPlans.count)|\(viewModel.isLoading)"
    }

    func reloadTomorrowPreview() {
        guard !viewModel.isLoading, viewModel.todayPlan != nil else {
            tomorrowPreviewData = nil
            return
        }
        tomorrowPreviewData = viewModel.tomorrowPreview(modelContext: modelContext)
    }

    @ViewBuilder
    var tomorrowSection: some View {
        if !viewModel.isLoading, activePause == nil || isTodaySessionSacred,
           !showsBedtimeCard(showSessionAnyway: showSessionTonight),
           let preview = tomorrowPreviewData
        {
            TomorrowWorkoutCard(preview: preview)
        }
    }

    // MARK: - Composite day

    /// "Football 10:00 ✓" above the gym part ("Push 18:00 · moderate") with the
    /// planner's why, and a way back while the gym part is untouched.
    func compositePartsCard(plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if let companion = plan.companionPartText {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "sportscourt.fill")
                        .foregroundStyle(Color.tempoRecoveryGreen)
                    Text(companion)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .accessibilityIdentifier("today.companionPart")
                }
            }
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: plan.status == .completed ? "checkmark.circle.fill" : "dumbbell.fill")
                    .foregroundStyle(plan.status == .completed ? Color.tempoRecoveryGreen : Color.tempoSignal)
                Text(plan.anchorPartText + (plan.addedPartIntensityRaw.map { " · \($0)" } ?? ""))
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .accessibilityIdentifier("today.anchorPart")
            }
            if let why = plan.addedPartRationale {
                Text(why)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.status == .planned, viewModel.hasNoCompletedSets(plan) {
                Button("Remove gym session") {
                    HapticManager.impact(.light)
                    viewModel.removeGymSession(modelContext: modelContext)
                }
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextTertiary)
                .accessibilityIdentifier("today.removeGym")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Football day entry points

    var addGymSessionButton: some View {
        Button {
            HapticManager.impact(.light)
            showAddGymSession = true
        } label: {
            Label("Add gym session", systemImage: "dumbbell.fill")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.tempoSurfaceCard)
                .foregroundStyle(Color.tempoTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .padding(.horizontal, TempoSpacing.lg)
        .accessibilityIdentifier("today.addGym")
    }

    /// "What time did you play?" — stamped on the football log so the gap to
    /// a later gym session is real.
    var playedTimePicker: some View {
        HStack {
            Text("Played at")
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            DatePicker("Played at", selection: $playedTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityIdentifier("today.playedTime")
        }
        .padding(.horizontal, TempoSpacing.lg)
    }
}
