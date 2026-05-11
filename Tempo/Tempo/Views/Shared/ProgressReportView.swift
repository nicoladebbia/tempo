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

    @State
    private var stats = ProgressStats()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    // Header
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("YOUR FIRST 30 DAYS")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Here's what you've accomplished.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }

                    // Stats grid
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: TempoSpacing.md
                    ) {
                        statCard(
                            value: "\(stats.workoutsCompleted)",
                            label: "Workouts",
                            icon: "dumbbell.fill",
                            color: Color.tempoSignal
                        )
                        statCard(
                            value: "\(stats.mealsLogged)",
                            label: "Meals Logged",
                            icon: "leaf.fill",
                            color: Color.tempoSuccess
                        )
                        statCard(
                            value: "\(stats.streakBest)",
                            label: "Best Streak",
                            icon: "flame.fill",
                            color: Color.tempoAmber
                        )
                        statCard(
                            value: "\(stats.totalXP)",
                            label: "XP Earned",
                            icon: "star.fill",
                            color: Color.tempoViolet
                        )
                        statCard(
                            value: stats.avgSleep,
                            label: "Avg Sleep",
                            icon: "moon.fill",
                            color: Color.tempoAmber
                        )
                        statCard(
                            value: "\(stats.daysActive)/30",
                            label: "Days Active",
                            icon: "calendar",
                            color: Color.tempoSignal
                        )
                    }

                    // Consistency score
                    consistencySection
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Progress Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.tempoSignal)
                }
            }
            .onAppear { loadStats() }
        }
    }

    // MARK: - Consistency Section

    private var consistencySection: some View {
        let pct = stats.daysActive * 100 / max(1, 30)
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("CONSISTENCY SCORE")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                .tracking(1.2)

            HStack {
                Text("\(pct)%")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(consistencyColor(pct: pct))
                Spacer()
            }

            Text(consistencyMessage(pct: pct))
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl))
    }

    // MARK: - Stat Card

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl))
    }

    // MARK: - Helpers

    private func consistencyColor(pct: Int) -> Color {
        if pct >= 80 {
            return Color.tempoSuccess
        }
        if pct >= 50 {
            return Color.tempoAmber
        }
        return Color.tempoError
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

        // Meals logged in last 30 days
        let mealDescriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.loggedAt >= thirtyDaysAgo }
        )
        stats.mealsLogged = (try? modelContext.fetch(mealDescriptor).count) ?? 0

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
