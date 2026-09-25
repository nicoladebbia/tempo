//
// ConditioningLogSheet.swift
// Tempo
//
// Fix #7 — logging how one trainer-program conditioning block actually went.
// The sheet's shape follows the parsed target (ConditioningTargetParser): a
// per-rep time grid against a cap, a duration + distance pair, a rounds
// counter, or (freeform) just RPE + notes. Saving calls
// TrainingViewModel.logConditioningBlock, which also bridges completion
// through the day's EXISTING path (see TrainingViewModel+ConditioningLogging).
//

import SwiftData
import SwiftUI

struct ConditioningLogSheet: View {
    let block: ProgramExercise
    let workoutPlanID: UUID
    let programSessionKey: String

    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    private let target: ConditioningTarget

    @State
    private var repTimeText: [String]
    @State
    private var durationText = ""
    @State
    private var distanceText = ""
    @State
    private var roundsText = ""
    @State
    private var rpe: Int?
    @State
    private var notes = ""
    @State
    private var isLoadingFill = false
    @State
    private var fillMessage: String?

    init(block: ProgramExercise, workoutPlanID: UUID, programSessionKey: String, viewModel: TrainingViewModel) {
        self.block = block
        self.workoutPlanID = workoutPlanID
        self.programSessionKey = programSessionKey
        self.viewModel = viewModel
        let parsed = ConditioningTargetParser.parse(detail: block.detail)
        target = parsed
        if case let .repsDistance(reps, _, _, _) = parsed.kind {
            _repTimeText = State(initialValue: Array(repeating: "", count: max(1, reps)))
        } else {
            _repTimeText = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    header

                    switch target.kind {
                    case let .repsDistance(_, distance, unit, capSeconds):
                        repsDistanceSection(distance: distance, unit: unit, capSeconds: capSeconds)
                    case .duration:
                        durationDistanceSection
                    case let .intervalSets(sets, reps):
                        roundsSection(sets: sets, reps: reps)
                    case .distance:
                        durationDistanceSection
                    case .freeform:
                        EmptyView()
                    }

                    if canFillFromDevice {
                        fillButton
                    }

                    rpeSection
                    notesSection
                }
                .padding(TempoSpacing.screenEdge)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Log Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(block.name)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            if let detail = block.detail, !detail.isEmpty {
                Text(detail)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - reps × distance (shuttle-style)

    private func repsDistanceSection(
        distance: Double,
        unit: ConditioningDistanceUnit,
        capSeconds: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel(
                capSeconds != nil
                    ? "EACH REP — \(formatDistance(distance, unit)) · cap \(formatSeconds(capSeconds!))"
                    : "EACH REP — \(formatDistance(distance, unit))"
            )
            VStack(spacing: TempoSpacing.xs) {
                ForEach(Array(repTimeText.indices), id: \.self) { index in
                    repTimeRow(index: index, capSeconds: capSeconds)
                }
            }
            Text("Type seconds (58) or m:ss (1:05).")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func repTimeRow(index: Int, capSeconds: Double?) -> some View {
        let parsed = Self.parseSeconds(repTimeText[index])
        let met = parsed.flatMap { time in capSeconds.map { time <= $0 } }
        return HStack(spacing: TempoSpacing.sm) {
            Text("Rep \(index + 1)")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 60, alignment: .leading)
            TextField("mm:ss or sec", text: $repTimeText[index])
                .keyboardType(.numbersAndPunctuation)
                .font(.tempoDataMedium)
                .monospacedDigit()
                .padding(.horizontal, TempoSpacing.inputHorizontal)
                .padding(.vertical, TempoSpacing.inputVertical)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
            if let met {
                Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(met ? Color.tempoRecoveryGreen : Color.tempoError)
            } else {
                Spacer().frame(width: 20)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rep \(index + 1)" + (met == nil ? "" : met == true ? ", under cap" : ", over cap")
        )
    }

    // MARK: - duration + distance (run / effort-style)

    private var durationDistanceSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if case let .duration(minutes) = target.kind {
                sectionLabel("DURATION — target \(formatMinutes(minutes))")
            } else if case let .distance(value, unit) = target.kind {
                sectionLabel("DISTANCE — target \(formatDistance(value, unit))")
            } else {
                sectionLabel("DURATION & DISTANCE")
            }
            labeledField(label: "Duration (min)", text: $durationText, keyboard: .decimalPad)
            labeledField(label: "Distance (m)", text: $distanceText, keyboard: .decimalPad)
        }
    }

    // MARK: - interval sets (drills)

    private func roundsSection(sets: Int, reps: Int) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("ROUNDS — target \(sets * reps) (\(sets) × \(reps))")
            labeledField(label: "Rounds completed", text: $roundsText, keyboard: .numberPad)
        }
    }

    // MARK: - Fill from Whoop/Health

    private var canFillFromDevice: Bool {
        switch target.kind {
        case .duration,
             .distance,
             .intervalSets: true
        default: false
        }
    }

    private var fillButton: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Button {
                Task { await fillFromDevice() }
            } label: {
                HStack(spacing: TempoSpacing.xs) {
                    if isLoadingFill {
                        ProgressView().tint(Color.tempoSignal)
                    } else {
                        Image(systemName: "heart.text.square")
                    }
                    Text("Fill from Whoop/Health")
                }
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoSignal)
            }
            .disabled(isLoadingFill)
            if let fillMessage {
                Text(fillMessage)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func fillFromDevice() async {
        isLoadingFill = true
        defer { isLoadingFill = false }
        guard let data = await viewModel.conditioningFillData(for: Date(), modelContext: modelContext) else {
            fillMessage = "No Whoop or Health activity found for today."
            return
        }
        if let minutes = data.durationMinutes {
            durationText = String(format: "%.0f", minutes)
        }
        if let distance = data.distanceMeters {
            distanceText = String(format: "%.0f", distance)
        }
        fillMessage = "Filled from \(data.source == "whoop" ? "Whoop" : "Health")."
    }

    // MARK: - RPE + notes

    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("EFFORT (RPE)")
            HStack(spacing: TempoSpacing.xs) {
                ForEach(1 ... 10, id: \.self) { value in
                    Button {
                        rpe = value
                    } label: {
                        Text("\(value)")
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(rpe == value ? Color.tempoSignal : Color.tempoBgSecondary)
                            .foregroundStyle(rpe == value ? Color.white : Color.tempoTextPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("NOTES")
            TextField("How did it feel?", text: $notes, axis: .vertical)
                .font(.tempoBody)
                .lineLimit(2 ... 4)
                .padding(TempoSpacing.inputHorizontal)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }

    // MARK: - Shared field pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    private func labeledField(label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.tempoDataMedium)
                .monospacedDigit()
                .frame(width: 100)
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, TempoSpacing.xs)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }

    // MARK: - Save

    private func save() {
        let repTimes: [Double]? = {
            let parsed = repTimeText.compactMap(Self.parseSeconds)
            return parsed.isEmpty ? nil : parsed
        }()
        let durationSeconds = Double(durationText).map { $0 * 60 }
        let distanceMeters = Double(distanceText)
        let rounds = Int(roundsText)

        viewModel.logConditioningBlock(
            workoutPlanID: workoutPlanID,
            programSessionKey: programSessionKey,
            blockID: block.id,
            detail: block.detail,
            repTimesSeconds: repTimes,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            roundsCompleted: rounds,
            rpe: rpe.map(Double.init),
            notes: notes.isEmpty ? nil : notes,
            source: fillMessage != nil ? (fillMessage!.contains("Whoop") ? "whoop" : "healthkit") : "manual",
            modelContext: modelContext
        )
        HapticManager.notification(.success)
        dismiss()
    }

    // MARK: - Formatting / parsing

    /// "58" → 58s. "1:05" → 65s. Anything else → nil (doesn't block save;
    /// that rep is simply left unlogged).
    static func parseSeconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1])
            else {
                return nil
            }
            return minutes * 60 + seconds
        }
        return Double(trimmed)
    }

    private func formatSeconds(_ seconds: Double) -> String {
        seconds >= 60
            ? String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
            : "\(Int(seconds))\""
    }

    private func formatMinutes(_ minutes: Double) -> String {
        "\(minutes.formatted(.number.precision(.fractionLength(0 ... 1))))'"
    }

    private func formatDistance(_ value: Double, _ unit: ConditioningDistanceUnit) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))\(unit.shortLabel)"
    }
}
