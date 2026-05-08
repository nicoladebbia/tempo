//
// FocusHistoryView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - Focus History View

// Shows study session history with daily bar chart and aggregate stats.

struct FocusHistoryView: View {
    @Query(sort: \StudySession.startTime, order: .reverse)
    private var sessions: [StudySession]

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.xxl) {
                // 7-day bar chart
                weeklyChartSection

                // Aggregate stats
                statsSection

                // Session list
                sessionListSection

                Spacer().frame(height: TempoSpacing.bottomSafe + 60)
            }
            .padding(.top, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Focus History")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Weekly Chart

    private var weeklyChartSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("LAST 7 DAYS")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, TempoSpacing.screenEdge)

            Chart {
                ForEach(last7DaysData, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(
                        day.isToday
                            ? Color.tempoElectric
                            : Color.tempoElectric.opacity(0.5)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 4
                        )
                    )
                }
            }
            .chartYAxisLabel("min")
            .frame(height: 200)
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STATS")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, TempoSpacing.screenEdge)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: TempoSpacing.md),
                    GridItem(.flexible(), spacing: TempoSpacing.md),
                ],
                spacing: TempoSpacing.md
            ) {
                statCard(
                    title: "Total Sessions",
                    value: "\(sessions.count)",
                    icon: "clock.fill"
                )
                statCard(
                    title: "Total Minutes",
                    value: formattedTotalMinutes,
                    icon: "timer"
                )
                statCard(
                    title: "Avg Focus Score",
                    value: "\(averageFocusScore)%",
                    icon: "brain.head.profile"
                )
                statCard(
                    title: "Best Day",
                    value: bestDayLabel,
                    icon: "trophy.fill"
                )
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.tempoElectric)

            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(title)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Session List

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("RECENT SESSIONS")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, TempoSpacing.screenEdge)

            if sessions.isEmpty {
                Text("No sessions yet. Start a focus timer to begin tracking.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.xxl)
                    .padding(.horizontal, TempoSpacing.screenEdge)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(20)) { session in
                        sessionRow(session)

                        if session.id != sessions.prefix(20).last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "book.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.tempoElectric)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(session.subject ?? "Focus Session")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                HStack(spacing: TempoSpacing.sm) {
                    Text(session.durationFormatted)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)

                    Text("\u{00B7}")
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text(session.startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            Spacer()

            if session.effectiveFocusScore > 0 {
                Text("\(session.effectiveFocusScore)%")
                    .font(.tempoCallout)
                    .foregroundStyle(focusScoreColor(session.effectiveFocusScore))
            }
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.md)
    }

    private func focusScoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return .tempoSuccess
        }
        if score >= 50 {
            return .tempoAmber
        }
        return .tempoSignal
    }

    // MARK: - Data

    private struct DayData {
        let date: Date
        let label: String
        let minutes: Int
        let isToday: Bool
    }

    private var last7DaysData: [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        return (0 ..< 7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let dayMinutes = sessions
                .filter { $0.startTime >= dayStart && $0.startTime < nextDay }
                .reduce(0) { $0 + $1.durationMinutes }

            return DayData(
                date: date,
                label: dayFormatter.string(from: date),
                minutes: dayMinutes,
                isToday: daysAgo == 0
            )
        }
    }

    private var formattedTotalMinutes: String {
        let total = sessions.reduce(0) { $0 + $1.durationMinutes }
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private var averageFocusScore: Int {
        let scored = sessions.filter { $0.focusScore != nil || $0.distractions > 0 }
        guard !scored.isEmpty else {
            return 0
        }
        let total = scored.reduce(0) { $0 + $1.effectiveFocusScore }
        return total / scored.count
    }

    private var bestDayLabel: String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var bestDay: Date?
        var bestMinutes = 0

        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }

        for (date, daySessions) in grouped {
            let totalMinutes = daySessions.reduce(0) { $0 + $1.durationMinutes }
            if totalMinutes > bestMinutes {
                bestMinutes = totalMinutes
                bestDay = date
            }
        }

        guard let best = bestDay else {
            return "--"
        }

        let hours = bestMinutes / 60
        let mins = bestMinutes % 60
        let dayName = dayFormatter.string(from: best)
        if hours > 0 {
            return "\(dayName) (\(hours)h \(mins)m)"
        }
        return "\(dayName) (\(mins)m)"
    }
}
