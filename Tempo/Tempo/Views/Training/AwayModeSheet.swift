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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Tide.s5) {
                    if let activePause {
                        VStack(alignment: .leading, spacing: Tide.s3) {
                            Text("Currently paused")
                                .tideLabel()
                                .accessibilityLabel("Currently paused")
                                .accessibilityIdentifier("Currently paused")
                            statusCard(
                                icon: "leaf.fill", color: TideTrain.positive,
                                title: activePause.reason.reportLabel,
                                subtitle: activePause.plannedEndDate.map {
                                    "Until \($0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))"
                                } ?? "Until you resume",
                                actionTitle: "Resume now"
                            ) {
                                viewModel.resumePauseNow(activePause, modelContext: modelContext)
                                dismiss()
                            }
                        }
                    } else {
                        NavigationLink {
                            StartPauseView(viewModel: viewModel, onDone: { dismiss() })
                        } label: {
                            TrainRowLabel(
                                systemImage: "leaf.fill",
                                title: "I'm sick / taking a break",
                                tint: TideTrain.positive
                            )
                            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                        }
                        .buttonStyle(.plain)
                    }

                    if let activeTravel {
                        VStack(alignment: .leading, spacing: Tide.s3) {
                            Text("Limited equipment").tideLabel().accessibilityLabel("Limited equipment")
                            statusCard(
                                icon: "bag.fill", color: Tide.water,
                                title: activeTravel.scope.displayName,
                                subtitle: activeTravel.availableEquipment
                                    .map(\.travelDisplayName).sorted().joined(separator: ", "),
                                actionTitle: "End early"
                            ) {
                                viewModel.endTravelEquipmentPeriod(activeTravel, modelContext: modelContext)
                                dismiss()
                            }
                        }
                    } else {
                        NavigationLink {
                            StartTravelEquipmentView(viewModel: viewModel, onDone: { dismiss() })
                        } label: {
                            TrainRowLabel(
                                systemImage: "bag.fill",
                                title: "Limited equipment (travel)",
                                tint: Tide.water
                            )
                            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
            }
            .scrollBounceBehavior(.basedOnSize)
            .trainSheetRoot()
            .navigationTitle("Away from the gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func statusCard(
        icon: String, color: Color, title: String, subtitle: String,
        actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: icon, tint: color)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
    @FocusState
    private var otherFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("Why").tideLabel()
                    Picker("Reason", selection: $reason) {
                        ForEach(PauseReason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if reason == .other {
                        TextField("What's up?", text: $otherText)
                            .focused($otherFocused)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .tideFieldSurface(focused: otherFocused)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("How long").tideLabel()
                    Toggle("Until I resume", isOn: $untilResume)
                    if !untilResume {
                        TrainSessionRule()
                        Stepper("\(Int(days)) day\(Int(days) == 1 ? "" : "s")", value: $days, in: 1 ... 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .animation(Tide.snap, value: untilResume)

                Text("No trainer sessions, no reminders, and Nutrition switches to rest days while you're paused.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .tidePage()
        .navigationTitle("Take a break")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
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
                    .frame(minHeight: TideTrain.bigButton - Tide.s2)
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s3)
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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Tide.s2),
            count: typeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("Scope").tideLabel()
                    Picker("Scope", selection: $scope) {
                        ForEach(TravelEquipmentScope.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("What do you actually have?").tideLabel()
                    LazyVGrid(columns: columns, spacing: Tide.s2) {
                        ForEach(Self.pickable, id: \.self) { equipment in
                            let isOn = selected.contains(equipment)
                            Button {
                                if isOn {
                                    selected.remove(equipment)
                                } else {
                                    selected.insert(equipment)
                                }
                            } label: {
                                HStack(spacing: Tide.s2) {
                                    if isOn {
                                        Image(systemName: "checkmark")
                                            .font(Tide.label)
                                            .accessibilityHidden(true)
                                    }
                                    Text(equipment.travelDisplayName)
                                        .font(Tide.bodyStrong)
                                        .lineLimit(1)
                                        .minimumScaleFactor(Tide.labelShrink)
                                }
                                .frame(maxWidth: .infinity, minHeight: TideTrainSession.choiceHeight)
                            }
                            .buttonStyle(.trainChoice(isSelected: isOn))
                        }
                    }
                    Button("Full gym (no swaps needed)") {
                        selected = Set(Equipment.allCases)
                    }
                    .buttonStyle(.tideGlass)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    "Trainer exercises that need gear you don't have get swapped to the closest match on what you DO have — same sets and reps, labeled \"Hotel swap\"."
                )
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tidePage()
        .navigationTitle("Limited equipment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            Button {
                viewModel.startTravelEquipmentPeriod(scope: scope, availableEquipment: selected, modelContext: modelContext)
                onDone()
            } label: {
                Text("Start")
                    .frame(minHeight: TideTrain.bigButton - Tide.s2)
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s3)
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
