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

// MARK: - MobilityFlowPickerView

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
                VStack(spacing: Tide.s2) {
                    ForEach(MobilityFlow.all) { flow in
                        Button {
                            activeFlow = flow
                        } label: {
                            flowRow(flow)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s3)
            }
            .trainSheetRoot()
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
        HStack(spacing: Tide.s3) {
            Image(systemName: "figure.flexibility")
                .font(Tide.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(flow.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text(flow.focus)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("\(flow.estimatedDuration) · \(flow.moves.count) moves")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        .tideCard(padding: Tide.s4)
    }
}

// MARK: - MobilityFlowPlayerView

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
            .trainSheetRoot()
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
            VStack(spacing: Tide.s5) {
                Text("Move \(moveIndex + 1) of \(flow.moves.count)").tideLabel(Tide.text3)
                    .padding(.top, Tide.s5)

                Text(move.name)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)

                Text(move.dose)
                    .font(Tide.headline)
                    .foregroundStyle(Color.accentColor)

                // Countdown for timed moves — wall-clock, survives backgrounding.
                if move.durationSeconds != nil, let end = moveEndDate {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(end.timeIntervalSince(context.date).rounded()))
                        Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                            .trainNumeral(56, weight: .bold)
                            .foregroundStyle(Tide.text)
                    }
                }

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text(move.howTo)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cue = move.cue {
                        HStack(alignment: .top, spacing: Tide.s1) {
                            Image(systemName: "lightbulb.fill")
                                .font(Tide.caption)
                                .foregroundStyle(Color.accentColor)
                            Text(cue)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tideCard(padding: Tide.s4)

                if move.durationSeconds == nil {
                    Button {
                        advance()
                    } label: {
                        Text("Done — next")
                    }
                    .buttonStyle(.tidePrimary)
                } else {
                    Button {
                        advance()
                    } label: {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
        }
    }

    // MARK: Completion

    private var completionContent: some View {
        VStack(spacing: Tide.s5) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .trainGlyph(72)
                .foregroundStyle(TideTrain.positive)

            Text("Flow complete")
                .font(Tide.title)
                .foregroundStyle(Tide.text)

            Text(dayMarkedDone
                ? "Mobility day logged. That counts."
                : "Recovery work done. Your future sessions thank you.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                dismiss()
                onFinished()
            } label: {
                Text("DONE")
                    .font(Tide.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.accentColor)
                    .foregroundStyle(Tide.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
            }
            .padding(.bottom, Tide.s6)
        }
        .padding(.horizontal, Tide.edge)
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
               viewModel.todayPlan?.status != .completed
            {
                dayMarkedDone = viewModel.persistNonGymCompletion(
                    whoop: nil, modelContext: modelContext
                )
            }
            completed = true
            HapticManager.notification(.success)
        }
    }
}
