//
// MuscleHeatmapView.swift
// Tempo
//
// §11.5 — the interactive muscle heatmap. A stylized segmented body figure
// (front/back) heat-colored by the last 7 days' training volume per muscle
// (MuscleHeatEngine). Tapping a muscle opens a drill-down card: volume,
// sets, the exercises that trained it, and the trend vs the prior week.
// All geometry is normalized 0…1 body space drawn with pure SwiftUI paths —
// no image assets.
//

import SwiftData
import SwiftUI

// MARK: - Body geometry

/// One tappable segment of the figure, in normalized body space.
private struct MuscleRegion {
    enum Kind {
        case capsule
        case ellipse
        case rounded(CGFloat) // corner radius as fraction of region width
    }

    let muscle: MuscleGroup
    let frame: CGRect
    let kind: Kind

    func path(in body: CGRect) -> Path {
        let rect = CGRect(
            x: body.minX + frame.minX * body.width,
            y: body.minY + frame.minY * body.height,
            width: frame.width * body.width,
            height: frame.height * body.height
        )
        switch kind {
        case .capsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
        case .ellipse:
            return Path(ellipseIn: rect)
        case .rounded(let fraction):
            return Path(roundedRect: rect, cornerRadius: rect.width * fraction)
        }
    }

    /// Mirror across the body's vertical center line.
    var mirrored: MuscleRegion {
        MuscleRegion(
            muscle: muscle,
            frame: CGRect(x: 1 - frame.maxX, y: frame.minY, width: frame.width, height: frame.height),
            kind: kind
        )
    }
}

/// Non-trainable filler segments (head, pelvis, shins…) that make the blob
/// arrangement read as a human figure.
private struct NeutralRegion {
    let frame: CGRect
    let kind: MuscleRegion.Kind

    func path(in body: CGRect) -> Path {
        MuscleRegion(muscle: .core, frame: frame, kind: kind).path(in: body)
    }
}

private enum BodyFigure {
    /// Left-side regions are declared; right side mirrors automatically.
    static let front: [MuscleRegion] = expand([
        MuscleRegion(muscle: .shoulders, frame: CGRect(x: 0.255, y: 0.155, width: 0.105, height: 0.075), kind: .ellipse),
        MuscleRegion(muscle: .chest, frame: CGRect(x: 0.360, y: 0.165, width: 0.135, height: 0.095), kind: .rounded(0.35)),
        MuscleRegion(muscle: .biceps, frame: CGRect(x: 0.255, y: 0.240, width: 0.075, height: 0.120), kind: .capsule),
        MuscleRegion(muscle: .forearms, frame: CGRect(x: 0.235, y: 0.370, width: 0.070, height: 0.130), kind: .capsule),
        MuscleRegion(muscle: .core, frame: CGRect(x: 0.400, y: 0.275, width: 0.200, height: 0.155), kind: .rounded(0.20)),
        MuscleRegion(muscle: .quads, frame: CGRect(x: 0.375, y: 0.475, width: 0.110, height: 0.205), kind: .capsule),
    ])

    static let back: [MuscleRegion] = expand([
        MuscleRegion(muscle: .shoulders, frame: CGRect(x: 0.255, y: 0.155, width: 0.105, height: 0.075), kind: .ellipse),
        MuscleRegion(muscle: .back, frame: CGRect(x: 0.360, y: 0.150, width: 0.135, height: 0.170), kind: .rounded(0.30)),
        MuscleRegion(muscle: .triceps, frame: CGRect(x: 0.255, y: 0.240, width: 0.075, height: 0.120), kind: .capsule),
        MuscleRegion(muscle: .forearms, frame: CGRect(x: 0.235, y: 0.370, width: 0.070, height: 0.130), kind: .capsule),
        MuscleRegion(muscle: .back, frame: CGRect(x: 0.425, y: 0.330, width: 0.150, height: 0.085), kind: .rounded(0.25)),
        MuscleRegion(muscle: .glutes, frame: CGRect(x: 0.385, y: 0.425, width: 0.110, height: 0.085), kind: .rounded(0.40)),
        MuscleRegion(muscle: .hamstrings, frame: CGRect(x: 0.380, y: 0.520, width: 0.105, height: 0.165), kind: .capsule),
        MuscleRegion(muscle: .calves, frame: CGRect(x: 0.390, y: 0.700, width: 0.090, height: 0.150), kind: .capsule),
    ])

    /// Front view's non-trainable filler.
    static let frontNeutral: [NeutralRegion] = [
        NeutralRegion(frame: CGRect(x: 0.435, y: 0.030, width: 0.130, height: 0.100), kind: .ellipse),
        NeutralRegion(frame: CGRect(x: 0.415, y: 0.435, width: 0.170, height: 0.045), kind: .rounded(0.30)), // pelvis
        NeutralRegion(frame: CGRect(x: 0.390, y: 0.695, width: 0.090, height: 0.160), kind: .capsule), // left shin
        NeutralRegion(frame: CGRect(x: 0.520, y: 0.695, width: 0.090, height: 0.160), kind: .capsule), // right shin
    ]

    static let backNeutral: [NeutralRegion] = [
        NeutralRegion(frame: CGRect(x: 0.435, y: 0.030, width: 0.130, height: 0.100), kind: .ellipse),
    ]

    /// Mirror every asymmetric region across the center line; center pieces
    /// (frames spanning x = 0.5) stay single.
    private static func expand(_ half: [MuscleRegion]) -> [MuscleRegion] {
        half.flatMap { region -> [MuscleRegion] in
            let spansCenter = region.frame.minX < 0.5 && region.frame.maxX > 0.5
            return spansCenter ? [region] : [region, region.mirrored]
        }
    }
}

// MARK: - Heatmap View

struct MuscleHeatmapView: View {
    @Query(sort: \ExerciseHistory.date, order: .reverse)
    private var allHistory: [ExerciseHistory]
    @Query
    private var userSettings: [UserSettings]

    @State
    private var showBack = false
    @State
    private var selectedMuscle: MuscleGroup?

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    /// History flattened for the pure engine. 14 days is all both windows need.
    private var rows: [MuscleHeatEngine.ContributionRow] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return allHistory
            .filter { $0.date >= cutoff }
            .compactMap { row in
                guard let exercise = row.exercise else {
                    return nil
                }
                return MuscleHeatEngine.ContributionRow(
                    primary: exercise.muscleGroup,
                    secondaries: exercise.secondaryMuscles,
                    volume: row.totalVolume,
                    sets: row.setsPerformed ?? 0,
                    date: row.date
                )
            }
    }

    private var currentWindow: (from: Date, to: Date) {
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return (from, now)
    }

    private var currentVolumes: [MuscleGroup: Double] {
        MuscleHeatEngine.volumes(rows: rows, from: currentWindow.from, to: currentWindow.to)
    }

    private var previousVolumes: [MuscleGroup: Double] {
        let to = currentWindow.from
        let from = Calendar.current.date(byAdding: .day, value: -7, to: to) ?? to
        return MuscleHeatEngine.volumes(rows: rows, from: from, to: to)
    }

    private var heat: [MuscleGroup: Double] {
        MuscleHeatEngine.heat(currentVolumes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                Picker("Side", selection: $showBack) {
                    Text("Front").tag(false)
                    Text("Back").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TempoSpacing.screenEdge)

                bodyFigure
                    .frame(maxWidth: 320)
                    .aspectRatio(0.62, contentMode: .fit)
                    .padding(.horizontal, TempoSpacing.xl)
                    .animation(.spring(duration: 0.35), value: showBack)

                legend

                if let muscle = selectedMuscle {
                    drillDown(for: muscle)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("Tap a muscle to drill into its week.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(.vertical, TempoSpacing.lg)
            .animation(.spring(duration: 0.3), value: selectedMuscle)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Muscle Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Figure

    private var regions: [MuscleRegion] {
        showBack ? BodyFigure.back : BodyFigure.front
    }

    private var neutralRegions: [NeutralRegion] {
        showBack ? BodyFigure.backNeutral : BodyFigure.frontNeutral
    }

    private var bodyFigure: some View {
        GeometryReader { geo in
            let bodyRect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                Canvas { context, _ in
                    for neutral in neutralRegions {
                        context.fill(
                            neutral.path(in: bodyRect),
                            with: .color(Color.tempoBgSecondary.opacity(0.6))
                        )
                    }
                    for region in regions {
                        let value = heat[region.muscle] ?? 0
                        let path = region.path(in: bodyRect)
                        context.fill(path, with: .color(heatColor(value)))
                        let isSelected = region.muscle == selectedMuscle
                        context.stroke(
                            path,
                            with: .color(isSelected ? Color.tempoAccent : Color.tempoTextTertiary.opacity(0.25)),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let bodyRect = CGRect(origin: .zero, size: geo.size)
                if let hit = regions.first(where: { $0.path(in: bodyRect).contains(location) }) {
                    selectedMuscle = selectedMuscle == hit.muscle ? nil : hit.muscle
                    HapticManager.selection()
                } else {
                    selectedMuscle = nil
                }
            }
        }
    }

    /// Cold → hot: base surface through amber to signal red.
    private func heatColor(_ value: Double) -> Color {
        guard value > 0 else {
            return Color.tempoBgSecondary
        }
        if value < 0.5 {
            return Color.tempoAmber.opacity(0.35 + value * 0.9)
        }
        return Color.tempoSignal.opacity(0.45 + (value - 0.5) * 1.1)
    }

    private var legend: some View {
        HStack(spacing: TempoSpacing.sm) {
            Text("Rested")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            LinearGradient(
                colors: [Color.tempoBgSecondary, Color.tempoAmber, Color.tempoSignal],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 120, height: 8)
            .clipShape(Capsule())
            Text("Hammered")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: Drill-down

    /// The window's history rows that trained this muscle (primary or listed
    /// secondary), newest first.
    private func contributions(for muscle: MuscleGroup) -> [ExerciseHistory] {
        let window = currentWindow
        return allHistory.filter { row in
            guard row.date >= window.from, row.date < window.to, let exercise = row.exercise else {
                return false
            }
            return exercise.muscleGroup == muscle || exercise.secondaryMuscles.contains(muscle)
        }
    }

    private func drillDown(for muscle: MuscleGroup) -> some View {
        let volume = currentVolumes[muscle] ?? 0
        let sets = MuscleHeatEngine.setCounts(
            rows: rows, from: currentWindow.from, to: currentWindow.to
        )[muscle] ?? 0
        let deltas = MuscleHeatEngine.delta(current: currentVolumes, previous: previousVolumes)
        let change = deltas[muscle, default: nil]
        let exercises = contributions(for: muscle)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text(muscle.displayName.uppercased())
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if let change {
                    Label(
                        String(format: "%+.0f%%", change * 100),
                        systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.tempoCaption1)
                    .foregroundStyle(change >= 0 ? Color.tempoAccent : Color.tempoAmber)
                }
            }

            HStack(spacing: TempoSpacing.xl) {
                statBlock(value: volumeLabel(volume), caption: "7-day volume")
                statBlock(value: "\(sets)", caption: "working sets")
                statBlock(value: "\(exercises.count)", caption: "sessions")
            }

            if exercises.isEmpty {
                Text("Nothing this week — this muscle is fully rested.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(exercises.prefix(6), id: \.id) { row in
                    HStack {
                        Text(row.exercise?.name ?? "—")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        if let best = row.bestSetWeight {
                            Text("\(volumeLabel(best)) × \(row.bestSetReps ?? 0)")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
            }
        }
        .padding(TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func statBlock(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(caption)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func volumeLabel(_ kg: Double) -> String {
        let display = WeightUnit.kg.convert(kg, to: weightUnit)
        let formatted = display >= 1000
            ? String(format: "%.1fk", display / 1000)
            : String(format: "%.0f", display)
        return "\(formatted) \(weightUnit.abbreviation)"
    }
}
