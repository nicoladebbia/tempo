//
// MindQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - MindQuadrantDetailView

// Per MODULE_DASHBOARD.md Section 4.4 — Mind Expanded View.
// Study progress hero, today's sessions, upcoming exams,
// study trend chart, streak display.

struct MindQuadrantDetailView: View {
    let data: MindQuadrantData
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood
    @State
    private var showFocusTimer = false
    @State
    private var showAddExam = false

    /// Today's completed study sessions, freshest first.
    @Query(
        filter: #Predicate<StudySession> { $0.endTime != nil },
        sort: [SortDescriptor(\StudySession.startTime, order: .reverse)]
    )
    private var allCompletedSessions: [StudySession]

    /// Sessions whose startTime falls in today's calendar day.
    private var todaysSessions: [StudySession] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allCompletedSessions.filter { $0.startTime >= start && $0.startTime < end }
    }

    /// 7-day rolling study minutes per day (oldest → today).
    private var studyTrend: [StudyTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recent = allCompletedSessions.filter { $0.startTime >= weekStart }
        var bucket = [Date: Int]()
        for session in recent {
            let day = calendar.startOfDay(for: session.startTime)
            bucket[day, default: 0] += session.durationMinutes
        }
        return (-6 ... 0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return StudyTrendPoint(date: day, minutes: bucket[day, default: 0])
        }
    }

    var body: some View {
        TideScrollPage(spacing: Tide.s6, spacer: Tide.s2) {
            progressHeroSection
            todaySessionsSection
            startSessionButton
            upcomingExamsSection
            studyTrendSection
        }
        .navigationTitle("Mind")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Progress Hero

    // Per MODULE_DASHBOARD.md Section 4.4 — Progress Hero

    private var progressHeroSection: some View {
        let percent = Int((min(data.studyProgress, 1.0) * 100).rounded())
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))

        return VStack(alignment: .leading, spacing: Tide.s4) {
            layout {
                // Study time + target
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Studied today").tideLabel()
                    TideNumber(data.formattedStudyTime, size: Tide.numeralL, relativeTo: .largeTitle)
                    Text("of \(data.formattedStudyTarget) target")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: Tide.s2)

                TideDial(score: percent, caption: "Target", diameter: Tide.dialSheet)
                    .accessibilityLabel("Study target")
                    .accessibilityValue("\(percent) percent")
            }

            // Drill sergeant quip
            Text(studyQuip)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            // Streak badge
            if data.currentStreakDays >= 2 {
                TideStatusPill(
                    text: "\(data.currentStreakDays)-day streak",
                    tint: data.currentStreakDays >= 7 ? Tide.streak : Tide.text2,
                    systemImage: "flame.fill"
                )
            }
        }
        .tideCard()
    }

    // MARK: - Today's Sessions

    // Per MODULE_DASHBOARD.md Section 4.4 — Today's Sessions

    private var todaySessionsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Today's sessions")

            let sessions = todaysSessions
            if sessions.isEmpty {
                TideEmptyPanel(systemImage: "book.closed", title: "No study sessions yet")
                    .tideCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session)
                        if index < sessions.count - 1 {
                            TideDivider().padding(.leading, Tide.s4)
                        }
                    }
                }
                .tideCard(padding: 0)
            }
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack(spacing: Tide.s3) {
            TideIconTile(systemName: "book.fill", tint: mood.accent)

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(session.subject ?? "Focus Session")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                Text(rangeText(session))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            Spacer(minLength: Tide.s2)

            TideNumber(
                "\(session.durationMinutes)", unit: "m", size: Tide.numeralS, relativeTo: .headline,
                weight: .semibold
            )
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    private func rangeText(_ session: StudySession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: session.startTime)
        guard let end = session.endTime else {
            return start
        }
        return "\(start) — \(formatter.string(from: end))"
    }

    // MARK: - Start Session Button

    // Per MODULE_DASHBOARD.md Section 4.4

    private var startSessionButton: some View {
        Button {
            showFocusTimer = true
        } label: {
            Label("Start Study Session", systemImage: "play.fill")
        }
        .buttonStyle(.tidePrimary)
        .tideCovered(showFocusTimer)
        .sheet(isPresented: $showFocusTimer) {
            NavigationStack {
                FocusTimerView(viewModel: AccountabilityViewModel(engine: services.accountabilityEngine))
            }
        }
    }

    // MARK: - Upcoming Exams

    // Per MODULE_DASHBOARD.md Section 4.4 — Upcoming Exams

    private var upcomingExamsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Upcoming exams")

            VStack(alignment: .leading, spacing: Tide.s3) {
                if data.exams.isEmpty {
                    Text("No upcoming exams")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                } else {
                    ForEach(data.exams) { exam in
                        examRow(exam)
                    }
                }

                // Add exam button
                Button {
                    showAddExam = true
                } label: {
                    Label("Add exam", systemImage: "plus")
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
            .tideCovered(showAddExam)
            .sheet(isPresented: $showAddExam) {
                NavigationStack {
                    AddExamSheet(calendar: services.calendar)
                }
            }
        }
    }

    private func examRow(_ exam: ExamData) -> some View {
        HStack(spacing: Tide.s3) {
            Circle()
                .fill(examDotColor(exam.daysUntil))
                .frame(width: Tide.s3, height: Tide.s3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(exam.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)

                Text("\(TempoDateFormatters.dateOnly.string(from: exam.date)) (\(exam.formattedCountdown))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }

            Spacer(minLength: Tide.s2)
        }
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Study Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.4 — Study Trend Chart

    private var studyTrendSection: some View {
        let trend = studyTrend
        let weekTotal = trend.reduce(0) { $0 + $1.minutes }
        let bars = trend.map {
            TempoBarChartSeries<String>.Bar(
                label: TempoDateFormatters.shortDayOfWeek.string(from: $0.date), value: Double($0.minutes)
            )
        }
        let series = TempoBarChartSeries(id: "study", label: "Study", color: mood.accent, bars: bars)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Study trend", trailing: "Weekly total \(formatMinutes(weekTotal))")

            VStack(alignment: .leading, spacing: Tide.s3) {
                TideBarChart(
                    series: [series],
                    height: Tide.chartHeight,
                    emphasis: bars.last?.label,
                    target: Double(data.studyTargetMinutes)
                )
                .accessibilityLabel("Study minutes, last 7 days")
                .accessibilityValue(bars.map { "\($0.label) \(Int($0.value))" }.joined(separator: ", "))

                HStack(spacing: Tide.s2) {
                    RoundedRectangle(cornerRadius: Tide.hair)
                        .fill(Tide.text3)
                        .frame(width: Tide.s4, height: Tide.rule)
                    Text("Daily target \(data.formattedStudyTarget)")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                }
                .accessibilityHidden(true)
            }
            .tideCard()
        }
    }

    // MARK: - Helpers

    private var studyQuip: String {
        let progress = data.studyProgress
        switch progress {
        case 0: return "Zero minutes. The books miss you."
        case ..<0.5: return "Not done yet. Back to the desk."
        case ..<1.0: return "More than half. Keep going."
        case 1.0: return "Target hit. Respect."
        default: return "Going extra. That's elite."
        }
    }

    private func examDotColor(_ daysUntil: Int) -> Color {
        switch daysUntil {
        case ...7: Tide.danger
        case 8 ... 14: TideTone.amber
        default: Tide.text3
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0, m > 0 {
            return "\(h)h \(m)m"
        }
        if h > 0 {
            return "\(h)h"
        }
        return "\(m)m"
    }
}

// MARK: - StudyTrendPoint

struct StudyTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int
}

// MARK: - AddExamSheet

struct AddExamSheet: View {
    let calendar: any CalendarServiceProtocol

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var examName = ""
    @State
    private var examDate = Date().addingTimeInterval(86400 * 7)
    @State
    private var isSaving = false
    @State
    private var saveError: String?

    var body: some View {
        Form {
            Section {
                TextField("Exam name", text: $examName)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .frame(minHeight: Tide.hit)
                DatePicker("Date", selection: $examDate, in: Date()..., displayedComponents: .date)
                    .font(Tide.body)
                    .frame(minHeight: Tide.hit)
            } header: {
                Text("Exam details").tideLabel(Tide.text3)
            }
            .tideListRow()

            if let error = saveError {
                Section {
                    Text(error)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                }
                .tideListRow()
            }
        }
        .tidePage()
        .navigationTitle("Add Exam")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await saveExam() } }
                    .disabled(examName.isEmpty || isSaving)
                    .fontWeight(.semibold)
            }
        }
    }

    private func saveExam() async {
        isSaving = true
        saveError = nil
        do {
            let saved = try await calendar.addExam(name: examName, date: examDate)
            if saved {
                dismiss()
            } else {
                saveError = "Calendar access is required to save exams. Enable it in Settings."
            }
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MindQuadrantDetailView(
            data: MindQuadrantData(
                studyMinutesToday: 95,
                studyTargetMinutes: 120,
                currentStreakDays: 12,
                exams: [
                    ExamData(name: "Calculus II", date: Date().addingTimeInterval(86400 * 6)),
                    ExamData(name: "Physics Lab", date: Date().addingTimeInterval(86400 * 14)),
                ]
            )
        )
        .environment(ServiceContainer.mock())
    }
}
