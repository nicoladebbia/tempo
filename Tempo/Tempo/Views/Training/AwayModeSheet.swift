//
// AwayModeSheet.swift
// Tempo
//
// Pause/travel-pain feature — the single entry point for both "I'm sick /
// taking a break" and "Limited equipment today/this week", reached from BOTH
// the Training tab's ☰ menu (`TrainingTabView.swift`) and the Program screen
// (`TrainerProgramView.swift`) — one sheet, two doors in, per the brief.
//

import SwiftData
import SwiftUI

// MARK: - AwayModeSheet

struct AwayModeSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @Query
    private var pauses: [TrainingPause]
    @Query
    private var travelPeriods: [TravelEquipmentPeriod]

    private var activePause: TrainingPause? {
        TrainingPauseSchedule.coveringPause(pauses, on: Date())
    }

    private var activeTravel: TravelEquipmentPeriod? {
        travelPeriods.filter { $0.covers(Date()) }.max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if let activePause {
                    Section("Currently paused") {
                        statusRow(
                            icon: "leaf.fill", color: .tempoSuccess,
                            title: activePause.reason.reportLabel,
                            subtitle: activePause.plannedEndDate.map {
                                "Until \($0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))"
                            } ?? "Until you resume"
                        )
                        Button("Resume now") {
                            viewModel.resumePauseNow(activePause, modelContext: modelContext)
                            dismiss()
                        }
                    }
                } else {
                    Section {
                        NavigationLink {
                            StartPauseView(viewModel: viewModel, onDone: { dismiss() })
                        } label: {
                            Label("I'm sick / taking a break", systemImage: "leaf.fill")
                        }
                    }
                }

                if let activeTravel {
                    Section("Limited equipment") {
                        statusRow(
                            icon: "bag.fill", color: .tempoElectric,
                            title: activeTravel.scope.displayName,
                            subtitle: activeTravel.availableEquipment
                                .map(\.travelDisplayName).sorted().joined(separator: ", ")
                        )
                        Button("End early") {
                            viewModel.endTravelEquipmentPeriod(activeTravel, modelContext: modelContext)
                            dismiss()
                        }
                    }
                } else {
                    Section {
                        NavigationLink {
                            StartTravelEquipmentView(viewModel: viewModel, onDone: { dismiss() })
                        } label: {
                            Label("Limited equipment (travel)", systemImage: "bag.fill")
                        }
                    }
                }
            }
            .navigationTitle("Away from the gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func statusRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tempoBodyBold)
                Text(subtitle).font(.tempoCaption1).foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }
}

// MARK: - StartPauseView

private struct StartPauseView: View {
    @Bindable
    var viewModel: TrainingViewModel
    var onDone: () -> Void
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var reason: PauseReason = .sick
    @State
    private var otherText = ""
    @State
    private var untilResume = false
    @State
    private var days: Double = 3

    var body: some View {
        Form {
            Section("Why") {
                Picker("Reason", selection: $reason) {
                    ForEach(PauseReason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if reason == .other {
                    TextField("What's up?", text: $otherText)
                }
            }
            Section("How long") {
                Toggle("Until I resume", isOn: $untilResume)
                if !untilResume {
                    Stepper("\(Int(days)) day\(Int(days) == 1 ? "" : "s")", value: $days, in: 1 ... 14)
                }
            }
            Section {
                Text("No trainer sessions, no reminders, and Nutrition switches to rest days while you're paused.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .navigationTitle("Take a break")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.startPause(
                    reason: reason,
                    otherReasonText: otherText.isEmpty ? nil : otherText,
                    days: untilResume ? nil : Int(days),
                    modelContext: modelContext
                )
                onDone()
            } label: {
                Text("Start")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Color.tempoTextInverse)
                    .background(Color.tempoSignal)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(TempoSpacing.md)
            .background(.bar)
        }
    }
}

// MARK: - StartTravelEquipmentView

private struct StartTravelEquipmentView: View {
    @Bindable
    var viewModel: TrainingViewModel
    var onDone: () -> Void
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var scope: TravelEquipmentScope = .today
    @State
    private var selected: Set<Equipment> = [.dumbbell]

    /// Practical hotel/travel equipment presets — the full `Equipment` list
    /// includes gym-only rigs (Smith machine, cable, EZ bar) that would just
    /// clutter a travel picker.
    private static let pickable: [Equipment] = [
        .bodyweight,
        .dumbbell,
        .resistanceBand,
        .kettlebell,
        .pullUpBar,
        .bench,
        .barbell,
        .machine,
    ]

    var body: some View {
        Form {
            Section("Scope") {
                Picker("Scope", selection: $scope) {
                    ForEach(TravelEquipmentScope.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("What do you actually have?") {
                ForEach(Self.pickable, id: \.self) { equipment in
                    Button {
                        if selected.contains(equipment) {
                            selected.remove(equipment)
                        } else {
                            selected.insert(equipment)
                        }
                    } label: {
                        HStack {
                            Text(equipment.travelDisplayName)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            if selected.contains(equipment) {
                                Image(systemName: "checkmark").foregroundStyle(Color.tempoSignal)
                            }
                        }
                    }
                }
                Button("Full gym (no swaps needed)") {
                    selected = Set(Equipment.allCases)
                }
                .font(.tempoCaption1)
            }
            Section {
                Text(
                    "Trainer exercises that need gear you don't have get swapped to the closest match on what you DO have — same sets and reps, labeled \"Hotel swap\"."
                )
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .navigationTitle("Limited equipment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.startTravelEquipmentPeriod(scope: scope, availableEquipment: selected, modelContext: modelContext)
                onDone()
            } label: {
                Text("Start")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Color.tempoTextInverse)
                    .background(Color.tempoElectric)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(TempoSpacing.md)
            .background(.bar)
            .disabled(selected.isEmpty)
        }
    }
}

// MARK: - Equipment travel display name

private extension Equipment {
    /// Short, gym-bag-friendly label — `Equipment`'s own naming (raw values
    /// like "resistance_band") isn't UI text; this file's own small mapping
    /// keeps that off the shared enum.
    var travelDisplayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbells"
        case .cable: "Cable machine"
        case .machine: "Machines"
        case .bodyweight: "Bodyweight only"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Resistance bands"
        case .smithMachine: "Smith machine"
        case .ezBar: "EZ bar"
        case .trapBar: "Trap bar"
        case .pullUpBar: "Pull-up bar"
        case .bench: "Bench"
        case .none: "None"
        }
    }
}
