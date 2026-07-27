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

struct RunHistoryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Query(sort: \RunSession.date, order: .reverse)
    private var runs: [RunSession]

    @State
    private var didImport = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.md) {
                statsHeader

                if runs.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: TempoSpacing.sm) {
                        ForEach(runs, id: \.id) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                runRow(run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
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
        let paces = recentRuns.compactMap(\.avgPaceSecondsPerKm)
        let bestPace = paces.min()

        return HStack(spacing: TempoSpacing.sm) {
            statCell(label: "RUNS · 30D", value: "\(recentRuns.count)")
            statCell(label: "DISTANCE", value: String(format: "%.1f km", totalKm))
            statCell(label: "BEST PACE", value: bestPace.map(Self.paceLabel) ?? "—")
        }
        .padding(.top, TempoSpacing.sm)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(value)
                .font(.tempoHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Rows

    private func runRow(_ run: RunSession) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "figure.run")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoSignal)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(run.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("\(String(format: "%.2f km", run.distanceKm)) · \(run.durationFormatted)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            if let pace = run.avgPaceFormatted {
                Text(pace)
                    .font(.tempoHeadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No runs yet")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Record a run with your Watch, Whoop, or any app that saves to Health — it shows up here.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, TempoSpacing.xxxl)
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.lg) {
                // Headline stats
                VStack(spacing: TempoSpacing.xxs) {
                    Text(String(format: "%.2f km", run.distanceKm))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(run.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .padding(.top, TempoSpacing.xl)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: TempoSpacing.sm),
                    GridItem(.flexible(), spacing: TempoSpacing.sm),
                ], spacing: TempoSpacing.sm) {
                    detailCell(icon: "timer", label: "Duration", value: run.durationFormatted)
                    detailCell(icon: "speedometer", label: "Avg Pace", value: run.avgPaceFormatted ?? "—")
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
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Image(systemName: icon)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(value)
                .font(.tempoTitle3)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Splits")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            let fastest = run.splits.min() ?? 0
            ForEach(Array(run.splits.enumerated()), id: \.offset) { idx, split in
                HStack {
                    Text("KM \(idx + 1)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(width: 48, alignment: .leading)
                    Text(RunHistoryView.paceLabel(split))
                        .font(.tempoBody)
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextPrimary)
                    if split == fastest, run.splits.count > 1 {
                        Image(systemName: "bolt.fill")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoPRGold)
                    }
                    Spacer()
                }
                .padding(.vertical, TempoSpacing.xs)
                .padding(.horizontal, TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
        }
    }
}
