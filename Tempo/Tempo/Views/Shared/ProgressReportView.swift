//
// ProgressReportView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ProgressReportView

struct ProgressReportView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var stats = ProgressStats()

    /// Days with a recovery record, out of the 30-day window.
    private let windowDays = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    header
                    consistencySection
                    statGrid
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .tidePage()
            .navigationTitle("Progress report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .onAppear { loadStats() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text("Your first 30 days")
                .font(Tide.title)
                .foregroundStyle(Tide.text)
                .accessibilityAddTraits(.isHeader)
            Text("Here's what you've accomplished.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
    }

    // MARK: - Consistency Section

    /// The headline: how many of the 30 days you showed up, as a dial.
    private var consistencySection: some View {
        let pct = stats.daysActive * 100 / max(1, windowDays)
        return RecoveryHero {
            TideDial(score: min(pct, 100), caption: "of 100", diameter: Tide.dialHero)
                .environment(\.tideMood, consistencyMood(pct: pct))
        } side: {
            Text("Consistency").tideLabel()
            Text(consistencyMessage(pct: pct))
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consistency \(min(pct, 100)) out of 100. \(consistencyMessage(pct: pct))")
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Tide.s3), GridItem(.flexible(), spacing: Tide.s3)]
        return GlassEffectContainer(spacing: Tide.s3) {
            LazyVGrid(columns: columns, spacing: Tide.s3) {
                statCard(value: "\(stats.workoutsCompleted)", label: "Workouts", icon: "dumbbell.fill")
                statCard(value: "\(stats.mealsLogged)", label: "Meals logged", icon: "fork.knife")
                statCard(
                    value: "\(stats.streakBest)", unit: "days", label: "Best streak",
                    icon: "flame.fill", color: Tide.streak
                )
                statCard(value: stats.totalXP.formatted(), label: "XP earned", icon: "star.fill")
                statCard(
                    value: sleepValue, unit: sleepUnit, label: "Avg sleep", icon: "moon.fill"
                )
                statCard(
                    value: "\(stats.daysActive)", unit: "/\(windowDays)", label: "Days active",
                    icon: "calendar"
                )
            }
        }
    }

    // MARK: - Stat Card

    private func statCard(
        value: String, unit: String? = nil, label: String, icon: String, color: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(color ?? mood.accent)
                .frame(height: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            TideNumber(value, unit: unit, size: Tide.numeralM)
            Text(label).tideLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// "7.2h" is stored as one string; the figure and its unit are drawn apart.
    private var sleepValue: String {
        stats.avgSleep.hasSuffix("h") ? String(stats.avgSleep.dropLast()) : stats.avgSleep
    }

    private var sleepUnit: String? {
        stats.avgSleep.hasSuffix("h") ? "h" : nil
    }

    /// Same cut-offs as before (80 and 50), shown in the Tide moods.
    private func consistencyMood(pct: Int) -> TideMood {
        if pct >= 80 {
            return TideMood(level: .onPace)
        }
        if pct >= 50 {
            return TideMood(level: .behind)
        }
        return TideMood(level: .offTrack)
    }

    private func consistencyMessage(pct: Int) -> String {
        if pct >= 90 {
            return "Elite discipline. Top 5% of Tempo users show up like this. Keep it up."
        }
        if pct >= 75 {
            return "Strong consistency. You're building real habits. The results will follow."
        }
        if pct >= 50 {
            return "Solid start. You're showing up more days than not. Push for 80% next month."
        }
        return "Room to grow. But you're here, reading this. That counts. Show up more next month."
    }

    // MARK: - Data Loading

    private func loadStats() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        // Meals eaten in last 30 days — canonical eaten PlannedMeals (Mark
        // Eaten + Quick Log), not legacy MealLog. Day-aligned window so it
        // counts whole days, like the Dashboard's day boundary.
        let windowStart = Calendar.current.startOfDay(for: thirtyDaysAgo)
        let windowEnd = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        stats.mealsLogged = EatenMealHistory.fetch(
            from: windowStart, to: windowEnd, in: modelContext
        ).count(where: { !EatenMealRecorder.isSupplementDose($0) })

        // Best streak (all time)
        let streakDescriptor = FetchDescriptor<Streak>()
        if let streaks = try? modelContext.fetch(streakDescriptor) {
            stats.streakBest = streaks.map(\.longestCount).max() ?? 0
        }

        // XP earned in last 30 days
        let xpDescriptor = FetchDescriptor<XPEvent>(
            predicate: #Predicate<XPEvent> { $0.date >= thirtyDaysAgo }
        )
        if let xpEvents = try? modelContext.fetch(xpDescriptor) {
            stats.totalXP = xpEvents.reduce(0) { $0 + $1.amount }
        }

        // Daily recoveries in last 30 days (sleep + active day count)
        let recoveryDescriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { $0.date >= thirtyDaysAgo }
        )
        if let recoveries = try? modelContext.fetch(recoveryDescriptor) {
            stats.daysActive = recoveries.count
            let sleepHours = recoveries.compactMap(\.sleepHours).filter { $0 > 0 }
            if !sleepHours.isEmpty {
                let avg = sleepHours.reduce(0, +) / Double(sleepHours.count)
                stats.avgSleep = String(format: "%.1fh", avg)
            }
        }
    }
}

// MARK: - ProgressStats

private struct ProgressStats {
    var workoutsCompleted = 0
    var mealsLogged = 0
    var streakBest = 0
    var totalXP = 0
    var avgSleep = "--"
    var daysActive = 0
}
