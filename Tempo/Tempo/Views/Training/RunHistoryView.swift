//
// RunHistoryView.swift
// Tempo
//
// §13 running module — the run surface RunSession never had. History list
// with a trailing-30-day stats header, per-run detail with splits when
// present. Data arrives via RunImporter (HealthKit mirror) on appear and
// pull-to-refresh; no in-app GPS tracking (Watch/Whoop/other apps record,
// Tempo analyzes).
//

import SwiftData
import SwiftUI

// MARK: - RunHistoryView

struct RunHistoryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Query(sort: \RunSession.date, order: .reverse)
    private var runs: [RunSession]
    @Query
    private var userSettings: [UserSettings]

    @State
    private var didImport = false
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s3) {
                statsHeader

                if runs.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Tide.s2) {
                        ForEach(runs, id: \.id) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                runRow(run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, (Tide.s10 + Tide.s2) + (Tide.s10 + Tide.s2))
        }
        .tidePage()
        .navigationTitle("Runs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didImport else {
                return
            }
            didImport = true
            _ = await RunImporter.importRuns(healthKit: services.healthKit, modelContext: modelContext)
        }
        .refreshable {
            _ = await RunImporter.importRuns(healthKit: services.healthKit, modelContext: modelContext)
        }
    }

    // MARK: - Stats header (trailing 30 days)

    private var recentRuns: [RunSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return runs.filter { $0.date >= cutoff }
    }

    /// Distance as the number and the unit apart, so the number can be big.
    private func distanceParts(meters: Double, decimals: Int = 1) -> (value: String, unit: String) {
        let value = useMiles ? meters / 1609.344 : meters / 1000
        return (value.tempoDecimal(decimals), useMiles ? String(localized: "mi") : String(localized: "km"))
    }

    /// Distance per week for the last four weeks, oldest first.
    private var weeklyBars: [TrainPlanBarChart.Bar] {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0 ..< 4).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else {
                return nil
            }
            let meters = runs.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.distanceKm * 1000 }
            let value = useMiles ? meters / 1609.344 : meters / 1000
            return TrainPlanBarChart.Bar(
                id: "\(back)", label: start.formatted(.dateTime.day().month(.abbreviated)), value: value
            )
        }
    }

    private var statsHeader: some View {
        let totalKm = recentRuns.reduce(0) { $0 + $1.distanceKm }
        let total = distanceParts(meters: totalKm * 1000)
        let paces = recentRuns.compactMap(\.avgPaceSecondsPerKm)
        let bestPace = paces.min()
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideLabel(String(localized: "Last 30 days"))
            TideNumber(total.value, unit: total.unit, size: Tide.numeralL, relativeTo: .largeTitle)
                .contentTransition(.numericText())
            if !recentRuns.isEmpty {
                TrainPlanBarChart(bars: weeklyBars)
                    .accessibilityHidden(true)
            }
            layout {
                TrainStat(value: "\(recentRuns.count)", label: String(localized: "Runs"))
                TrainStat(
                    value: GuidedRunFormatting.pace(secondsPerKm: bestPace, useMiles: useMiles) ?? "—",
                    label: String(localized: "Best pace")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
        .padding(.top, Tide.s2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Rows

    /// One run: the distance big, the day and the time under it, the pace at the end.
    private func runRow(_ run: RunSession) -> some View {
        let distance = distanceParts(meters: run.distanceKm * 1000, decimals: 2)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        return layout {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(run.date, format: .dateTime.weekday(.wide).month().day())
                    .tideLabel(Tide.text3)
                TideNumber(distance.value, unit: distance.unit, size: Tide.numeralS, relativeTo: .title2)
                Text(run.durationFormatted)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            HStack(spacing: Tide.s2) {
                if let pace = paceText(run) {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Tide.hair) {
                        Text(pace)
                            .font(TideTrain.figure(.headline))
                            .foregroundStyle(Tide.text)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                        Text("pace").font(Tide.caption).foregroundStyle(Tide.text3)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    private func paceText(_ run: RunSession) -> String? {
        GuidedRunFormatting.pace(secondsPerKm: run.avgPaceSecondsPerKm, useMiles: useMiles)
    }

    private var emptyState: some View {
        TrainEmptyCard(
            systemImage: "figure.run",
            title: String(localized: "No runs yet"),
            message: String(localized: "Record a run with your Watch, Whoop, or any app that saves to Health — it shows up here.")
        )
        .padding(.top, Tide.s4)
    }

    private var useMiles: Bool {
        GuidedRunFormatting.useMiles(weightUnit: userSettings.first?.weightUnit)
    }

    static func paceLabel(_ secondsPerKm: Double) -> String {
        let mins = Int(secondsPerKm) / 60
        let secs = Int(secondsPerKm) % 60
        let clock = String(format: "%d:%02d", mins, secs)
        return String(localized: "\(clock) /km")
    }
}

// MARK: - RunDetailView

struct RunDetailView: View {
    let run: RunSession
    @Query
    private var userSettings: [UserSettings]
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .caption)
    private var splitLabelWidth: CGFloat = TideTrainSession.repLabel

    private var useMiles: Bool {
        GuidedRunFormatting.useMiles(weightUnit: userSettings.first?.weightUnit)
    }

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                heroCard
                    .padding(.top, Tide.s3)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Tide.s2),
                        count: typeSize.isAccessibilitySize ? 1 : 2
                    ),
                    spacing: Tide.s2
                ) {
                    if let hr = run.avgHR {
                        detailCell(icon: "heart.fill", label: String(localized: "Avg HR"), value: String(localized: "\(Int(hr)) bpm"))
                    }
                    if let max = run.maxHR {
                        detailCell(icon: "bolt.heart", label: String(localized: "Max HR"), value: String(localized: "\(Int(max)) bpm"))
                    }
                    if let cal = run.calories {
                        detailCell(icon: "flame", label: String(localized: "Calories"), value: "\(Int(cal))")
                    }
                    if let elev = run.elevationGainMeters {
                        detailCell(icon: "arrow.up.right", label: String(localized: "Elevation"), value: String(localized: "\(Int(elev)) m"))
                    }
                    if let cadence = run.avgCadence {
                        detailCell(icon: "metronome", label: String(localized: "Cadence"), value: String(localized: "\(Int(cadence)) spm"))
                    }
                }

                // Splits (when the source recorded them)
                if !run.splits.isEmpty {
                    splitsSection
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, (Tide.s10 + Tide.s2) + (Tide.s10 + Tide.s2))
        }
        .tidePage()
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The run in one card: the day, the distance big, then time and pace.
    private var heroCard: some View {
        let miles = useMiles
        let distance = miles ? run.distanceKm * 1000 / 1609.344 : run.distanceKm
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            Text(run.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                .tideLabel()
            TideNumber(
                distance.tempoDecimal(2), unit: miles ? String(localized: "mi") : String(localized: "km"),
                size: Tide.numeralL, relativeTo: .largeTitle
            )
            TrainSessionRule()
            layout {
                TrainStat(value: run.durationFormatted, label: String(localized: "Time"))
                TrainStat(
                    value: GuidedRunFormatting.pace(secondsPerKm: run.avgPaceSecondsPerKm, useMiles: miles) ?? "—",
                    label: String(localized: "Avg pace")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
        .accessibilityElement(children: .contain)
    }

    private func detailCell(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Tide.s3) {
            TideIconTile(systemName: icon, tint: mood.accent)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                Text(value)
                    .font(TideTrain.figure(.headline))
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    private var splitsSection: some View {
        let fastest = run.splits.min() ?? 0
        return VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Splits").tideLabel()

            VStack(spacing: 0) {
                ForEach(Array(run.splits.enumerated()), id: \.offset) { idx, split in
                    if idx > 0 {
                        TrainSessionRule()
                    }
                    let isFastest = split == fastest && run.splits.count > 1
                    // A faster split fills more of its bar, so the run's shape
                    // (a fast start, a fade) reads without doing the sums.
                    let speedShare = split > 0 ? min(fastest / split, 1) : 0
                    let row = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                        : AnyLayout(HStackLayout(spacing: Tide.s3))
                    row {
                        Text("KM \(idx + 1)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .frame(minWidth: splitLabelWidth, alignment: .leading)
                        Text(RunHistoryView.paceLabel(split))
                            .font(TideTrain.figure(.body))
                            .foregroundStyle(isFastest ? TideTrain.record : Tide.text)
                        TideLevelBar(
                            progress: speedShare,
                            color: isFastest ? TideTrain.record : nil,
                            height: Tide.barSlim
                        )
                        .frame(minWidth: Tide.s10)
                        if isFastest {
                            Image(systemName: "bolt.fill")
                                .font(Tide.caption)
                                .foregroundStyle(TideTrain.record)
                                .accessibilityLabel("Fastest split")
                        }
                    }
                    .padding(.vertical, Tide.s2)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
