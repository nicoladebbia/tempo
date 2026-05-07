//
// ExerciseDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - Exercise Detail View

// Per MODULE_TRAINING.md Section 10 — Exercise detail with stats and progress.
// Per WIREFRAMES.md Screen 20 — Name, info pills, stats card, progress chart, instructions.

struct ExerciseDetailView: View {
    @Bindable
    var exercise: Exercise

    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]
    @State
    private var chartRange: ChartRange = .thirtyDays

    private var settings: UserSettings? {
        allSettings.first
    }

    private var weightUnit: WeightUnit {
        settings?.weightUnit ?? .kg
    }

    enum ChartRange: String, CaseIterable {
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "ALL"

        var days: Int? {
            switch self {
            case .thirtyDays: 30
            case .ninetyDays: 90
            case .all: nil
            }
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Demo area placeholder
                // Per WIREFRAMES.md Screen 20 — 200pt demo area
                demoArea

                // Exercise name
                Text(exercise.name.uppercased())
                    .font(.tempoTitle1)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)

                // Info pills
                // Per WIREFRAMES.md Screen 20 — muscle group, equipment, compound/isolation
                infoPills

                // Secondary muscles
                if !exercise.secondaryMuscles.isEmpty {
                    Text("Secondary: \(exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                // Stats card
                // Per WIREFRAMES.md Screen 20 — YOUR STATS section
                statsCard

                // Progress chart
                // Per WIREFRAMES.md Screen 20 — e1RM line chart with time range picker
                progressChart

                // Instructions
                if let instructions = exercise.instructions, !instructions.isEmpty {
                    instructionsSection(instructions)
                }

                // Coaching cues
                if !exercise.cues.isEmpty {
                    cuesSection
                }

                // Rest timer customization
                restTimerSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Demo Area

    // Per WIREFRAMES.md Screen 20 — 200pt height, surface bg

    private var demoArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .fill(Color.tempoSurfaceCard)

            Image(systemName: exerciseIcon)
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(height: 200)
    }

    // MARK: - Info Pills

    // Per WIREFRAMES.md Screen 20 — 24pt height pill chips

    private var infoPills: some View {
        HStack(spacing: TempoSpacing.sm) {
            infoPill(exercise.muscleGroup.displayName)
            infoPill(equipmentLabel)
            infoPill(exercise.isCompound ? "Compound" : "Isolation")
        }
    }

    private func infoPill(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextSecondary)
            .padding(.horizontal, TempoSpacing.sm)
            .frame(height: 24)
            .background(Color.tempoSurfaceElevated)
            .clipShape(Capsule())
    }

    // MARK: - Stats Card

    // Per WIREFRAMES.md Screen 20 — Current 1RM, Best Set, Volume (30d), Sessions (30d)

    private var statsCard: some View {
        let history = sortedHistory
        let thirtyDayHistory = history.filter {
            $0.date > Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        }
        let current1RM = exercise.currentEstimated1RM
        let bestWeight = history.compactMap(\.bestSetWeight).max()
        let bestReps = history.compactMap(\.bestSetReps).max()
        let volume30d = thirtyDayHistory.reduce(0.0) { $0 + $1.totalVolume }
        let sessions30d = thirtyDayHistory.count

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("YOUR STATS")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm),
            ], spacing: TempoSpacing.sm) {
                statItem(
                    label: "Current 1RM",
                    value: current1RM
                        .map { String(format: "%.1f %@", WeightUnit.kg.convert($0, to: weightUnit), weightUnit.abbreviation) } ?? "—"
                )
                statItem(
                    label: "Best Set",
                    value: bestSetText(weight: bestWeight, reps: bestReps)
                )
                statItem(
                    label: "Volume (30d)",
                    value: volume30d > 0 ? formatVolume(volume30d) : "—"
                )
                statItem(
                    label: "Sessions (30d)",
                    value: sessions30d > 0 ? "\(sessions30d)" : "—"
                )
            }

            // PR display
            if let allTimePR = exercise.allTimePR {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "trophy.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoPRGold) // prGold

                    Text(
                        "All-Time 1RM PR: \(String(format: "%.1f", WeightUnit.kg.convert(allTimePR, to: weightUnit))) \(weightUnit.abbreviation)"
                    )
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                }
                .padding(.top, TempoSpacing.xs)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Progress Chart

    // Per WIREFRAMES.md Screen 20 — e1RM line chart, 200pt, with 30D/90D/ALL picker

    private var progressChart: some View {
        let chartHistory = filteredHistory(for: chartRange)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("PROGRESS (e1RM)")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                Spacer()

                // Per WIREFRAMES.md Screen 20 — [ 30D | 90D | ALL ] picker
                Picker("Range", selection: $chartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if chartHistory.isEmpty {
                VStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text("No history yet")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                let data = TempoLineChartData<String>(
                    id: "e1RM",
                    label: "Estimated 1RM",
                    color: Color.tempoSignal,
                    points: chartHistory.compactMap { entry in
                        guard let e1rm = entry.estimated1RM else {
                            return nil
                        }
                        return TempoLineChartData<String>.DataPoint(
                            date: entry.date,
                            value: e1rm
                        )
                    }
                )
                TempoLineChart(data: [data], height: 200)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Instructions

    // Per WIREFRAMES.md Screen 20 — Numbered step-by-step instructions

    private func instructionsSection(_ instructions: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("INSTRUCTIONS")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(instructions)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Coaching Cues

    private var cuesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("COACHING CUES")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            ForEach(Array(exercise.cues.enumerated()), id: \.offset) { index, cue in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Text("\(index + 1).")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(width: 20, alignment: .trailing)

                    Text(cue)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Rest Timer Customization

    private var restTimerSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("REST TIMER")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            HStack {
                Text("Preferred rest between sets")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                if let rest = exercise.preferredRestSeconds {
                    Text(formatRestDuration(rest))
                        .font(.tempoBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .monospacedDigit()
                }
            }

            Stepper(
                value: Binding(
                    get: { exercise.preferredRestSeconds ?? 90 },
                    set: { newValue in
                        exercise.preferredRestSeconds = newValue
                        try? modelContext.save()
                    }
                ),
                in: 30 ... 300,
                step: 15
            ) {
                Text(formatRestDuration(exercise.preferredRestSeconds ?? 90))
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .monospacedDigit()
            }

            // Reset to default
            if exercise.preferredRestSeconds != nil {
                Button {
                    exercise.preferredRestSeconds = nil
                    try? modelContext.save()
                } label: {
                    Text("Reset to Default")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func formatRestDuration(_ seconds: Int) -> String {
        let min = seconds / 60
        let sec = seconds % 60
        if min > 0, sec > 0 {
            return "\(min)m \(sec)s"
        } else if min > 0 {
            return "\(min)m"
        }
        return "\(sec)s"
    }

    // MARK: - Helpers

    private var sortedHistory: [ExerciseHistory] {
        (exercise.history ?? []).sorted { $0.date > $1.date }
    }

    private func filteredHistory(for range: ChartRange) -> [ExerciseHistory] {
        let history = (exercise.history ?? []).sorted { $0.date < $1.date }
        guard let days = range.days else {
            return history
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return history.filter { $0.date > cutoff }
    }

    private func bestSetText(weight: Double?, reps: Int?) -> String {
        guard let w = weight, let r = reps else {
            return "—"
        }
        let converted = WeightUnit.kg.convert(w, to: weightUnit)
        return "\(Int(converted))\(weightUnit.abbreviation) x \(r)"
    }

    private func formatVolume(_ volume: Double) -> String {
        let converted = WeightUnit.kg.convert(volume, to: weightUnit)
        if converted >= 1000 {
            return String(format: "%.1fk %@", converted / 1000, weightUnit.abbreviation)
        }
        return "\(Int(converted)) \(weightUnit.abbreviation)"
    }

    private var equipmentLabel: String {
        switch exercise.equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Band"
        case .smithMachine: "Smith"
        case .ezBar: "EZ Bar"
        case .trapBar: "Trap Bar"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .none: "None"
        }
    }

    private var exerciseIcon: String {
        switch exercise.muscleGroup {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.strengthtraining.traditional"
        case .shoulders: "figure.strengthtraining.traditional"
        case .biceps,
             .triceps,
             .forearms: "figure.strengthtraining.traditional"
        case .quads,
             .hamstrings,
             .glutes,
             .calves: "figure.strengthtraining.traditional"
        case .core: "figure.core.training"
        case .fullBody: "figure.strengthtraining.functional"
        case .cardio: "figure.run"
        }
    }
}
