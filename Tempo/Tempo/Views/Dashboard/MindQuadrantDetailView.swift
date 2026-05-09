//
// MindQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                progressHeroSection
                todaySessionsSection
                startSessionButton
                upcomingExamsSection
                studyTrendSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Mind")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Progress Hero

    // Per MODULE_DASHBOARD.md Section 4.4 — Progress Hero

    private var progressHeroSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            // Study time + target
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Text(data.formattedStudyTime)
                    .font(.tempoScoreDisplay)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("/ \(data.formattedStudyTarget) target")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Full-width progress bar
            HStack(spacing: TempoSpacing.sm) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tempoBorder).frame(height: 8)
                        Capsule().fill(Color.tempoElectric)
                            .frame(width: geo.size.width * min(data.studyProgress, 1.0), height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(Int(min(data.studyProgress, 1.0) * 100))%")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Drill sergeant quip
            Text(studyQuip)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .italic()

            // Streak badge
            if data.currentStreakDays >= 2 {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoAmber)
                    Text("\(data.currentStreakDays)-day streak")
                        .font(.tempoCallout)
                        .foregroundStyle(data.currentStreakDays >= 7 ? Color.tempoAmber : Color.tempoTextSecondary)
                }
            }
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Today's Sessions

    // Per MODULE_DASHBOARD.md Section 4.4 — Today's Sessions

    private var todaySessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S SESSIONS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.bottom, TempoSpacing.md)

            if todaysSessions.isEmpty {
                Text("No study sessions yet")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                ForEach(Array(todaysSessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session)
                    if index < todaysSessions.count - 1 {
                        Divider()
                            .background(Color.tempoDivider)
                    }
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "book.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoElectric)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject ?? "Focus Session")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(rangeText(session))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()

            Text("\(session.durationMinutes)m")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(minHeight: 52)
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
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                Text("Start Study Session")
                    .font(.tempoCallout)
            }
            .foregroundStyle(Color.tempoTextInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.tempoElectric)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .sheet(isPresented: $showFocusTimer) {
            NavigationStack {
                FocusTimerView(viewModel: AccountabilityViewModel(engine: services.accountabilityEngine))
            }
        }
    }

    // MARK: - Upcoming Exams

    // Per MODULE_DASHBOARD.md Section 4.4 — Upcoming Exams

    private var upcomingExamsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UPCOMING EXAMS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.bottom, TempoSpacing.md)

            if data.exams.isEmpty {
                Text("No upcoming exams")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.vertical, TempoSpacing.sm)
            } else {
                ForEach(data.exams) { exam in
                    examRow(exam)
                }
            }

            // Add exam button
            Button {
                showAddExam = true
            } label: {
                Text("+ Add Exam")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoElectric)
            }
            .padding(.top, TempoSpacing.sm)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .sheet(isPresented: $showAddExam) {
            NavigationStack {
                AddExamSheet(calendar: services.calendar)
            }
        }
    }

    private func examRow(_ exam: ExamData) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Circle()
                .fill(examDotColor(exam.daysUntil))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(exam.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("\(TempoDateFormatters.dateOnly.string(from: exam.date)) (\(exam.formattedCountdown))")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()
        }
        .frame(minHeight: 44)
    }

    // MARK: - Study Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.4 — Study Trend Chart

    private var studyTrendSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("STUDY TREND")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Chart(studyTrend) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(Color.tempoElectric)
                .cornerRadius(4)

                RuleMark(y: .value("Target", data.studyTargetMinutes))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
            .frame(height: 160)

            // Weekly total
            let weekTotal = studyTrend.reduce(0) { $0 + $1.minutes }
            Text("Weekly total: \(formatMinutes(weekTotal))")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
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
        case ...7: Color.tempoError
        case 8 ... 14: Color.tempoWarning
        default: Color.tempoTextTertiary
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
            Section("Exam Details") {
                TextField("Exam name", text: $examName)
                DatePicker("Date", selection: $examDate, in: Date()..., displayedComponents: .date)
            }
            if let error = saveError {
                Section {
                    Text(error)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
            }
        }
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
