//
// MobilityFlowView.swift
// Tempo
//
// §10 mobility flows — the real guided flows behind "Start a Mobility Flow"
// (previously a "coming soon" alert). Picker → timer-driven player over
// MobilityFlow/WarmupMove data: timed moves count down and auto-advance,
// rep-based moves wait for a tap — the same mechanics as the pre-lift warm-up
// block, but self-contained: no session state machine, nothing to crash-
// recover. On a MOBILITY day, finishing a flow completes the day through
// persistNonGymCompletion (same path as the manual mark-done); on a rest day
// it's pure recovery — nothing is written.
//

import SwiftData
import SwiftUI

// MARK: - Picker

struct MobilityFlowPickerView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var activeFlow: MobilityFlow?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.sm) {
                    ForEach(MobilityFlow.all) { flow in
                        Button {
                            activeFlow = flow
                        } label: {
                            flowRow(flow)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.md)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Mobility Flows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(item: $activeFlow) { flow in
                MobilityFlowPlayerView(flow: flow, viewModel: viewModel) {
                    // Flow finished → close the picker too.
                    dismiss()
                }
            }
        }
    }

    private func flowRow(_ flow: MobilityFlow) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "figure.flexibility")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoSignal)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(flow.name)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(flow.focus)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("\(flow.estimatedDuration) · \(flow.moves.count) moves")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }
}

// MARK: - Player

struct MobilityFlowPlayerView: View {
    let flow: MobilityFlow
    @Bindable
    var viewModel: TrainingViewModel
    /// Called after the completion screen is dismissed (closes the picker).
    var onFinished: () -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var moveIndex = 0
    @State
    private var moveEndDate: Date?
    @State
    private var completed = false
    /// Set when finishing the flow also completed a mobility DAY.
    @State
    private var dayMarkedDone = false

    private var currentMove: WarmupMove? {
        moveIndex < flow.moves.count ? flow.moves[moveIndex] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if completed {
                    completionContent
                } else if let move = currentMove {
                    moveContent(move)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.tempoBgPrimary)
            .navigationTitle(flow.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !completed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End") { dismiss() }
                    }
                }
            }
        }
        // Timed move: arm a wall-clock countdown that auto-advances. Changing
        // moveIndex cancels the previous move's task automatically.
        .task(id: moveIndex) {
            guard let secs = currentMove?.durationSeconds else {
                moveEndDate = nil
                return
            }
            moveEndDate = Date().addingTimeInterval(Double(secs))
            try? await Task.sleep(for: .seconds(secs))
            guard !Task.isCancelled else {
                return
            }
            advance()
        }
    }

    // MARK: Move screen

    private func moveContent(_ move: WarmupMove) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                Text("MOVE \(moveIndex + 1) OF \(flow.moves.count)")
                    .font(.tempoCaption1)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.xl)

                Text(move.name.uppercased())
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)

                Text(move.dose)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoSignal)

                // Countdown for timed moves — wall-clock, survives backgrounding.
                if move.durationSeconds != nil, let end = moveEndDate {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(end.timeIntervalSince(context.date).rounded()))
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text(move.howTo)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cue = move.cue {
                        HStack(alignment: .top, spacing: TempoSpacing.xs) {
                            Image(systemName: "lightbulb.fill")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoSignal)
                            Text(cue)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(TempoSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                Button {
                    advance()
                } label: {
                    Text(move.durationSeconds == nil ? "DONE — NEXT" : "SKIP")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(move.durationSeconds == nil ? Color.tempoSignal : Color.tempoSurfaceCard)
                        .foregroundStyle(move.durationSeconds == nil ? .white : Color.tempoTextPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.xxxl)
        }
    }

    // MARK: Completion

    private var completionContent: some View {
        VStack(spacing: TempoSpacing.xl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.tempoRecoveryGreen)

            Text("FLOW COMPLETE")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(dayMarkedDone
                ? "Mobility day logged. That counts."
                : "Recovery work done. Your future sessions thank you.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                dismiss()
                onFinished()
            } label: {
                Text("DONE")
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.tempoSignal)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .padding(.bottom, TempoSpacing.xxl)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: Advance

    private func advance() {
        HapticManager.selection()
        if moveIndex + 1 < flow.moves.count {
            moveIndex += 1
        } else {
            // On a mobility DAY the flow IS the session — complete the day
            // through the same guarded path as the manual mark-done. Rest
            // days write nothing.
            if viewModel.todayPlan?.type == .mobility,
               viewModel.todayPlan?.status != .completed {
                dayMarkedDone = viewModel.persistNonGymCompletion(
                    whoop: nil, modelContext: modelContext
                )
            }
            completed = true
            HapticManager.notification(.success)
        }
    }
}
