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

    private var statsHeader: some View {
        let totalKm = recentRuns.reduce(0) { $0 + $1.distanceKm }
        let useMiles = useMiles
        let paces = recentRuns.compactMap(\.avgPaceSecondsPerKm)
        let bestPace = paces.min()

        return HStack(spacing: Tide.s2) {
            statCell(label: "RUNS · 30D", value: "\(recentRuns.count)")
            statCell(
                label: "DISTANCE",
                value: GuidedRunFormatting.totalDistance(meters: totalKm * 1000, useMiles: useMiles)
            )
            statCell(
                label: "BEST PACE",
                value: GuidedRunFormatting.pace(secondsPerKm: bestPace, useMiles: useMiles) ?? "—"
            )
        }
        .padding(.top, Tide.s2)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: Tide.hair) {
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            Text(value)
                .font(Tide.headline)
                .monospacedDigit()
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s3).tideCard(padding: 0, radius: Tide.tileRadius)
    }

    // MARK: - Rows

    private func runRow(_ run: RunSession) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "figure.run")
                .font(Tide.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(run.date, format: .dateTime.weekday(.wide).month().day())
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                Text(
                    "\(GuidedRunFormatting.distance(meters: run.distanceKm * 1000, useMiles: useMiles)) · \(run.durationFormatted)"
                )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }

            Spacer()

            if let pace = GuidedRunFormatting.pace(secondsPerKm: run.avgPaceSecondsPerKm, useMiles: useMiles) {
                Text(pace)
                    .font(Tide.headline)
                    .monospacedDigit()
                    .foregroundStyle(Tide.text)
            }

            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    private var emptyState: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: "figure.run")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.text3)
            Text("No runs yet")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text("Record a run with your Watch, Whoop, or any app that saves to Health — it shows up here.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Tide.s8)
    }

    private var useMiles: Bool {
        GuidedRunFormatting.useMiles(weightUnit: userSettings.first?.weightUnit)
    }

    static func paceLabel(_ secondsPerKm: Double) -> String {
        let mins = Int(secondsPerKm) / 60
        let secs = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", mins, secs)
    }
}

// MARK: - RunDetailView

struct RunDetailView: View {
    let run: RunSession
    @Query
    private var userSettings: [UserSettings]

    private var useMiles: Bool {
        GuidedRunFormatting.useMiles(weightUnit: userSettings.first?.weightUnit)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                // Headline stats
                VStack(spacing: Tide.hair) {
                    Text(GuidedRunFormatting.distance(meters: run.distanceKm * 1000, useMiles: useMiles))
                        .trainNumeral(44, weight: .bold)
                        .foregroundStyle(Tide.text)
                    Text(run.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                .padding(.top, Tide.s5)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Tide.s2),
                    GridItem(.flexible(), spacing: Tide.s2),
                ], spacing: Tide.s2) {
                    detailCell(icon: "timer", label: "Duration", value: run.durationFormatted)
                    detailCell(
                        icon: "speedometer",
                        label: "Avg Pace",
                        value: GuidedRunFormatting.pace(secondsPerKm: run.avgPaceSecondsPerKm, useMiles: useMiles) ?? "—"
                    )
                    if let hr = run.avgHR {
                        detailCell(icon: "heart.fill", label: "Avg HR", value: "\(Int(hr)) bpm")
                    }
                    if let max = run.maxHR {
                        detailCell(icon: "bolt.heart", label: "Max HR", value: "\(Int(max)) bpm")
                    }
                    if let cal = run.calories {
                        detailCell(icon: "flame", label: "Calories", value: "\(Int(cal))")
                    }
                    if let elev = run.elevationGainMeters {
                        detailCell(icon: "arrow.up.right", label: "Elevation", value: "\(Int(elev)) m")
                    }
                    if let cadence = run.avgCadence {
                        detailCell(icon: "metronome", label: "Cadence", value: "\(Int(cadence)) spm")
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

    private func detailCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: Tide.s1) {
            Image(systemName: icon)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            Text(value)
                .font(Tide.headline)
                .monospacedDigit()
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s4).tideCard(padding: 0, radius: Tide.tileRadius)
    }

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Splits")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)

            let fastest = run.splits.min() ?? 0
            ForEach(Array(run.splits.enumerated()), id: \.offset) { idx, split in
                HStack {
                    Text("KM \(idx + 1)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .frame(width: 48, alignment: .leading)
                    Text(RunHistoryView.paceLabel(split))
                        .font(Tide.body)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text)
                    if split == fastest, run.splits.count > 1 {
                        Image(systemName: "bolt.fill")
                            .font(Tide.caption)
                            .foregroundStyle(TideTrain.record)
                    }
                    Spacer()
                }
                .padding(.vertical, Tide.s1)
                .padding(.horizontal, Tide.s3).tideCard(padding: 0, radius: Tide.tileRadius)
            }
        }
    }
}
