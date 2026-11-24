//
// MuscleHeatmapView.swift
// Tempo
//
// §11.5 — the interactive muscle heatmap. A stylized segmented body figure
// (front/back) heat-colored by the last 7 days' training volume per muscle
// (MuscleHeatEngine). Tapping a muscle opens a drill-down card: volume,
// sets, the exercises that trained it, and the trend vs the prior week.
// All geometry is normalized 0…1 body space drawn with pure SwiftUI paths —
// no image assets. Hosted at the top of the "Body" tab of ProgressChartsView,
// so it draws its content only (no page, background or title of its own).
//

import SwiftData
import SwiftUI

// MARK: - MuscleRegion

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
        case let .rounded(fraction):
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

// MARK: - NeutralRegion

/// Non-trainable filler segments (head, pelvis, shins…) that make the blob
/// arrangement read as a human figure.
private struct NeutralRegion {
    let frame: CGRect
    let kind: MuscleRegion.Kind

    func path(in body: CGRect) -> Path {
        MuscleRegion(muscle: .core, frame: frame, kind: kind).path(in: body)
    }
}

// MARK: - Limb

/// One round-capped segment of the mannequin under the muscles, in
/// normalized body space (`width` is a fraction of the figure's width).
private struct Limb {
    let from: CGPoint
    let to: CGPoint
    let width: CGFloat

    func path(in body: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: body.minX + from.x * body.width, y: body.minY + from.y * body.height))
        path.addLine(to: CGPoint(x: body.minX + to.x * body.width, y: body.minY + to.y * body.height))
        return path
    }

    var mirrored: Limb {
        Limb(from: CGPoint(x: 1 - from.x, y: from.y), to: CGPoint(x: 1 - to.x, y: to.y), width: width)
    }
}

// MARK: - BodyFigure

private enum BodyFigure {
    /// Width over height of the whole drawing space.
    static let aspect: CGFloat = 0.62
    /// The part of the drawing space the figure actually occupies.
    static let crop = CGRect(x: 0.21, y: 0, width: 0.58, height: 0.88)
    /// Width over height of that part.
    static let cropAspect: CGFloat = crop.width * aspect / crop.height

    /// The mannequin both views share: the left side is declared and
    /// mirrored, the centre pieces stay single.
    static let limbs: [Limb] = {
        let side = [
            Limb(from: CGPoint(x: 0.295, y: 0.205), to: CGPoint(x: 0.285, y: 0.355), width: 0.080), // upper arm
            Limb(from: CGPoint(x: 0.272, y: 0.385), to: CGPoint(x: 0.265, y: 0.485), width: 0.066), // forearm
            Limb(from: CGPoint(x: 0.435, y: 0.485), to: CGPoint(x: 0.425, y: 0.675), width: 0.115), // thigh
            Limb(from: CGPoint(x: 0.430, y: 0.720), to: CGPoint(x: 0.435, y: 0.830), width: 0.090), // shin
        ]
        let centre = [
            Limb(from: CGPoint(x: 0.5, y: 0.130), to: CGPoint(x: 0.5, y: 0.165), width: 0.070), // neck
            Limb(from: CGPoint(x: 0.31, y: 0.190), to: CGPoint(x: 0.69, y: 0.190), width: 0.075), // shoulder line
            Limb(from: CGPoint(x: 0.5, y: 0.240), to: CGPoint(x: 0.5, y: 0.380), width: 0.220), // torso
            Limb(from: CGPoint(x: 0.44, y: 0.455), to: CGPoint(x: 0.56, y: 0.455), width: 0.100), // pelvis
        ]
        return centre + side + side.map(\.mirrored)
    }()

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

// MARK: - MuscleHeatmapView

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
        VStack(spacing: Tide.s4) {
            TrainPlanTabs(
                items: [(tag: false, label: "Front"), (tag: true, label: "Back")],
                selection: $showBack
            )
            .frame(maxWidth: TideTrain.tabsCompact)

            weekHero

            figureCard

            if let muscle = selectedMuscle {
                drillDown(for: muscle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap a muscle to drill into its week.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(Tide.lively, value: selectedMuscle)
    }

    // MARK: Week summary

    /// Every muscle the figure draws, front and back, once.
    private var trackedMuscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        return (BodyFigure.front + BodyFigure.back).compactMap { seen.insert($0.muscle).inserted ? $0.muscle : nil }
    }

    /// The week in one line of numbers, above the picture that shows where.
    private var weekHero: some View {
        let tracked = trackedMuscles
        let trained = tracked.filter { (heat[$0] ?? 0) > 0 }
        let hottest = trained.max { (heat[$0] ?? 0) < (heat[$1] ?? 0) }
        let untouched = tracked.filter { (heat[$0] ?? 0) == 0 }
        return VStack(alignment: .leading, spacing: Tide.s2) {
            TideLabel("Last 7 days")
            TideNumber(
                "\(trained.count)", unit: "of \(tracked.count) muscles trained",
                size: Tide.numeralL, relativeTo: .largeTitle
            )
            .contentTransition(.numericText())
            if let hottest {
                Text("Most worked: \(hottest.displayName)")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !untouched.isEmpty {
                Text("Not hit yet: \(untouched.map(\.displayName).joined(separator: ", "))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
        .accessibilityElement(children: .combine)
        .animation(Tide.snap, value: trained.count)
    }

    // MARK: Figure

    private var regions: [MuscleRegion] {
        showBack ? BodyFigure.back : BodyFigure.front
    }

    private var neutralRegions: [NeutralRegion] {
        showBack ? BodyFigure.backNeutral : BodyFigure.frontNeutral
    }

    private var figureCard: some View {
        TrainPlanCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tide.s5) {
                    bodyFigure
                    heatScale(vertical: true)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: Tide.s4) {
                    bodyFigure
                    heatScale(vertical: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The drawing space is bigger than the visible window: the figure is
    /// cropped to its own bounds so it fills the card.
    private func drawingRect(for size: CGSize) -> CGRect {
        let crop = BodyFigure.crop
        let width = size.width / crop.width
        let height = size.height / crop.height
        return CGRect(x: -crop.minX * width, y: -crop.minY * height, width: width, height: height)
    }

    private var bodyFigure: some View {
        GeometryReader { geo in
            let bodyRect = drawingRect(for: geo.size)
            Canvas { context, size in
                // The mannequin: limbs and filler drawn as ONE layer so the
                // overlaps never double up.
                var base = context
                base.opacity = 0.11
                base.drawLayer { layer in
                    for limb in BodyFigure.limbs {
                        layer.stroke(
                            limb.path(in: bodyRect),
                            with: .color(Tide.text),
                            style: StrokeStyle(lineWidth: limb.width * bodyRect.width, lineCap: .round)
                        )
                    }
                    for neutral in neutralRegions {
                        layer.fill(neutral.path(in: bodyRect), with: .color(Tide.text))
                    }
                }

                for region in regions {
                    let value = heat[region.muscle] ?? 0
                    let path = region.path(in: bodyRect)
                    let color = heatColor(value)
                    // Hot muscles glow.
                    if value >= 0.5 {
                        context.drawLayer { layer in
                            layer.addFilter(.shadow(color: color.opacity(0.65), radius: size.width * 0.04))
                            layer.fill(path, with: .color(color))
                        }
                    } else {
                        context.fill(path, with: .color(color))
                    }
                    let isSelected = region.muscle == selectedMuscle
                    context.stroke(
                        path,
                        with: .color(isSelected ? Tide.text : Tide.text3.opacity(0.3)),
                        lineWidth: isSelected ? 2 : 1
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let hit = regions.first(where: { $0.path(in: bodyRect).contains(location) }) {
                    selectedMuscle = selectedMuscle == hit.muscle ? nil : hit.muscle
                    HapticManager.selection()
                } else {
                    selectedMuscle = nil
                }
            }
            // The canvas is a picture: give VoiceOver one element per muscle.
            .overlay {
                ForEach(accessibleMuscles, id: \.muscle) { entry in
                    let rect = entry.region.path(in: bodyRect).boundingRect
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel(entry.muscle.displayName)
                        .accessibilityValue("heat \(Int(((heat[entry.muscle] ?? 0) * 100).rounded())) percent")
                        .accessibilityAddTraits(entry.muscle == selectedMuscle ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction {
                            selectedMuscle = selectedMuscle == entry.muscle ? nil : entry.muscle
                        }
                }
            }
        }
        .frame(width: TideTrain.figureWidth, height: TideTrain.figureWidth / BodyFigure.cropAspect)
        .animation(Tide.lively, value: showBack)
    }

    /// One accessibility target per muscle (the first region that draws it).
    private var accessibleMuscles: [(muscle: MuscleGroup, region: MuscleRegion)] {
        var seen = Set<MuscleGroup>()
        return regions.compactMap { region in
            seen.insert(region.muscle).inserted ? (region.muscle, region) : nil
        }
    }

    /// Cold → hot: base surface through amber to signal red.
    private func heatColor(_ value: Double) -> Color {
        guard value > 0 else {
            return Tide.fill
        }
        if value < 0.5 {
            return TideTrain.caution.opacity(0.35 + value * 0.9)
        }
        return Color.accentColor.opacity(0.45 + (value - 0.5) * 1.1)
    }

    /// A heat scale; the picked muscle's reading rides on it as a marker.
    /// Vertical beside the figure, horizontal under it at large text sizes.
    @ViewBuilder
    private func heatScale(vertical: Bool) -> some View {
        let reading = selectedMuscle.map { heat[$0] ?? 0 }
        let bar = LinearGradient(
            colors: [Tide.fill, TideTrain.caution, Color.accentColor],
            startPoint: vertical ? .bottom : .leading,
            endPoint: vertical ? .top : .trailing
        )
        .clipShape(Capsule())
        .overlay {
            GeometryReader { geo in
                if let reading {
                    let along = min(max(reading, 0.02), 0.98)
                    Circle()
                        .strokeBorder(Tide.text, lineWidth: Tide.focusLine)
                        .background(Circle().fill(Tide.ink.opacity(0.6)))
                        .frame(width: Tide.s4, height: Tide.s4)
                        .position(
                            x: vertical ? geo.size.width / 2 : geo.size.width * along,
                            y: vertical ? geo.size.height * (1 - along) : geo.size.height / 2
                        )
                        .animation(Tide.snap, value: reading)
                }
            }
        }

        if vertical {
            VStack(alignment: .center, spacing: Tide.s2) {
                Text("Hammered")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                bar
                    .frame(width: TideTrain.dot)
                Text("Rested")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            .frame(height: TideTrain.figureWidth / BodyFigure.cropAspect)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: Tide.s2) {
                bar
                    .frame(height: TideTrain.dot)
                HStack(spacing: Tide.s2) {
                    Text("Rested")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                    Spacer(minLength: Tide.s2)
                    Text("Hammered")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
            .accessibilityElement(children: .combine)
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

        return TrainPlanCard {
            // The muscle's name keeps its size; the change drops under it
            // when the two no longer fit side by side.
            let title = Text(muscle.displayName)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    title
                        .lineLimit(1)
                    Spacer(minLength: Tide.s2)
                    if let change {
                        TrainPlanDelta(fraction: change, suffix: "vs last week")
                    }
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    title
                        .fixedSize(horizontal: false, vertical: true)
                    if let change {
                        TrainPlanDelta(fraction: change, suffix: "vs last week")
                    }
                }
            }

            TrainStatGrid {
                TrainStat(value: volumeLabel(volume), label: "7-day volume", size: Tide.numeralS)
                TrainStat(value: "\(sets)", label: "working sets", size: Tide.numeralS)
                TrainStat(value: "\(exercises.count)", label: TrainCount.noun(exercises.count, "session"), size: Tide.numeralS)
            }

            if exercises.isEmpty {
                Text("Nothing this week — this muscle is fully rested.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TrainPlanDivider()
                ForEach(exercises.prefix(6), id: \.id) { row in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                            exerciseName(row)
                            Spacer(minLength: Tide.s2)
                            exerciseBest(row)
                        }
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            exerciseName(row)
                            exerciseBest(row)
                        }
                    }
                }
            }
        }
    }

    private func exerciseName(_ row: ExerciseHistory) -> some View {
        Text(row.exercise?.name ?? "—")
            .font(Tide.body)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func exerciseBest(_ row: ExerciseHistory) -> some View {
        if let reps = row.bestSetReps, reps > 0 {
            Text("\(historySetLoad(row)) × \(reps)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
    }

    private func volumeLabel(_ kg: Double) -> String {
        WeightFormat.volumeText(kg: kg, unit: weightUnit)
    }

    private func historySetLoad(_ row: ExerciseHistory) -> String {
        let bodyweight = row.exercise.map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false
        return WeightFormat.setLoad(
            kg: row.bestSetWeight, addedKg: row.bestSetAddedLoadKg, bodyweight: bodyweight, unit: weightUnit
        )
    }
}
