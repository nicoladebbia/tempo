import SwiftUI
import Charts

// MARK: - Mind Quadrant Detail View
// Per MODULE_DASHBOARD.md Section 4.4 — Mind Expanded View.
// Study progress hero, today's sessions, upcoming exams,
// study trend chart, streak display.

struct MindQuadrantDetailView: View {

    let data: MindQuadrantData

    // Stub session data
    private let sessions: [StudySessionItem] = [
        StudySessionItem(subject: "Calculus II", durationMinutes: 55, startTime: "9:00 AM", endTime: "9:55 AM"),
        StudySessionItem(subject: "Physics Lab", durationMinutes: 40, startTime: "2:00 PM", endTime: "2:40 PM"),
    ]

    // Stub 7-day study trend
    private let studyTrend: [StudyTrendPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let values = [130, 90, 110, 120, 80, 150, 95]
        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return StudyTrendPoint(date: date, minutes: values[offset + 6])
        }
    }()

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
            .padding(.bottom, 50)
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

            if sessions.isEmpty {
                Text("No study sessions yet")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TempoSpacing.lg)
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session)
                    if index < sessions.count - 1 {
                        Divider()
                            .background(Color.tempoDivider)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func sessionRow(_ session: StudySessionItem) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "book.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoElectric)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("\(session.startTime) — \(session.endTime)")
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

    // MARK: - Start Session Button
    // Per MODULE_DASHBOARD.md Section 4.4

    private var startSessionButton: some View {
        Button {} label: {
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
            Button {} label: {
                Text("+ Add Exam")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoElectric)
            }
            .padding(.top, TempoSpacing.sm)
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
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
        .padding(14)
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
        case ...7: return Color.tempoError
        case 8...14: return Color.tempoWarning
        default: return Color.tempoTextTertiary
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Supporting Types

struct StudySessionItem: Identifiable {
    let id = UUID()
    let subject: String
    let durationMinutes: Int
    let startTime: String
    let endTime: String
}

struct StudyTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int
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
    }
}
