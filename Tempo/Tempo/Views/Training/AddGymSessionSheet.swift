//
// AddGymSessionSheet.swift
// Tempo
//
// "Add gym session" on a soccer day. Tempo picks the focus + intensity from
// this morning's soccer and the week, shows WHY, and lets the athlete change
// the focus (blocked options say why). See ExtraGymSessionPlanner.
//

import SwiftUI

struct AddGymSessionSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var soccerTime = Date()
    @State
    private var gymTime = Date()
    @State
    private var requestedFocus: WorkoutType?
    @State
    private var decision: ExtraGymDecision?
    @State
    private var ready = false

    /// Football already logged (its time is fixed by the log / Whoop).
    private var footballLogged: Bool {
        viewModel.todayPlan?.status == .completed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    timesCard
                    if let decision {
                        decisionCard(decision)
                        focusChips(decision)
                        confirmButton(decision)
                    } else if ready {
                        Text("Gym sessions can be added on a football day.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Add Gym Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { setUp() }
        .onChange(of: gymTime) { recompute() }
        .onChange(of: soccerTime) { recompute() }
        .onChange(of: requestedFocus) { recompute() }
    }

    // MARK: - Sections

    private var timesCard: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack {
                Text("Football")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if footballLogged {
                    Text(viewModel.todayPlan?.companionPartText ?? loggedSoccerText)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoRecoveryGreen)
                        .accessibilityIdentifier("extragym.soccerLogged")
                } else {
                    DatePicker("Football time", selection: $soccerTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityIdentifier("extragym.soccerTime")
                }
            }
            Divider()
            HStack {
                Text("Gym at")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                DatePicker("Gym time", selection: $gymTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityIdentifier("extragym.gymTime")
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var loggedSoccerText: String {
        let facts = viewModel.soccerFacts(modelContext: modelContext)
        return "Football \(WorkoutPlan.clockText(facts?.startMin ?? 0)) ✓"
    }

    private func decisionCard(_ d: ExtraGymDecision) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(d.headline)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("extragym.headline")
                Spacer(minLength: TempoSpacing.sm)
                Text(d.intensity.rawValue.uppercased())
                    .font(.tempoCaption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 3)
                    .background(intensityColor(d.intensity).opacity(0.2))
                    .foregroundStyle(intensityColor(d.intensity))
                    .clipShape(Capsule())
            }
            Text("WHY")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            ForEach(d.reasons, id: \.self) { reason in
                Text("· \(reason)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private func focusChips(_ d: ExtraGymDecision) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("FOCUS")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TempoSpacing.sm) {
                    ForEach(d.options, id: \.focus) { option in
                        Button {
                            HapticManager.selection()
                            requestedFocus = option.focus
                        } label: {
                            Text(option.focus.displayName)
                                .font(.tempoSubheadline)
                                .padding(.horizontal, TempoSpacing.md)
                                .padding(.vertical, TempoSpacing.sm)
                                .background(d.focus == option.focus ? Color.tempoSignal : Color.tempoSurfaceCard)
                                .foregroundStyle(d.focus == option.focus ? Color.white : Color.tempoTextPrimary)
                                .clipShape(Capsule())
                                .opacity(option.allowed ? 1 : 0.4)
                        }
                        .disabled(!option.allowed)
                        .accessibilityIdentifier("extragym.focus.\(option.focus.rawValue)")
                    }
                }
            }
            if let warning = d.options.first(where: { $0.focus == d.focus })?.warning, d.focus != .mobility {
                Text(warning)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoWarning)
            }
            let blocked = d.options.filter { !$0.allowed }.compactMap(\.warning)
            if let first = blocked.first {
                Text(first)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func confirmButton(_ d: ExtraGymDecision) -> some View {
        Button {
            HapticManager.notification(.success)
            let gymMin = TrainingViewModel.minutesSinceMidnight(gymTime)
            if viewModel.addGymSession(
                decision: d, gymStartMin: gymMin,
                soccerStart: footballLogged ? nil : soccerTime, modelContext: modelContext
            ) {
                dismiss()
            }
        } label: {
            Text(d.focus == .mobility ? "ADD MOBILITY SESSION" : "ADD \(d.focus.displayName.uppercased()) SESSION")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
        .accessibilityIdentifier("extragym.confirm")
    }

    private func intensityColor(_ intensity: SessionIntensity) -> Color {
        switch intensity {
        case .recovery, .easy: Color.tempoRecoveryGreen
        case .moderate: Color.tempoRecoveryYellow
        case .hard, .max: Color.tempoRecoveryRed
        }
    }

    // MARK: - State

    private func setUp() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let gymMin = TrainingViewModel.defaultGymStartMin()
        gymTime = cal.date(byAdding: .minute, value: gymMin, to: today) ?? Date()
        let suggested = viewModel.suggestedSoccerStart(modelContext: modelContext)
            ?? cal.date(byAdding: .minute, value: -90, to: Date())
        soccerTime = max(today, suggested ?? Date())
        recompute()
        ready = true
    }

    private func recompute() {
        let gymMin = TrainingViewModel.minutesSinceMidnight(gymTime)
        guard let context = viewModel.extraGymContext(
            gymStartMin: gymMin,
            soccerStart: footballLogged ? nil : soccerTime,
            requestedFocus: requestedFocus,
            modelContext: modelContext
        ) else {
            decision = nil
            return
        }
        decision = ExtraGymSessionPlanner.decide(context)
    }
}
