import SwiftUI

// MARK: - Weekly Report View
// Per BUILD_PLAN step 15.2 — Display weekly AI insights.
// Per WIREFRAMES.md Screen 10 — Overall score, 4-section breakdown, AI insights, share.
// Per AI_INTELLIGENCE_ENGINE.md Section 3.2 — Sonnet 4.6 generated report.

struct WeeklyReportView: View {

    @Environment(ServiceContainer.self) private var services

    @State private var report: WeeklyReportData?
    @State private var isLoading = true
    @State private var expandedInsight: String?

    // Per WIREFRAMES.md Screen 10 — Week period display
    let weekStart: Date
    let weekEnd: Date

    private var periodText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStart)
        formatter.dateFormat = "MMM d, yyyy"
        let end = formatter.string(from: weekEnd)
        return "\(start) - \(end)"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if isLoading {
                loadingState
            } else if let report {
                reportContent(report)
            } else {
                emptyState
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("WEEKLY REPORT")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadReport() }
    }

    // MARK: - Report Content
    // Per WIREFRAMES.md Screen 10 — Full layout

    private func reportContent(_ report: WeeklyReportData) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            // Period header
            Text(periodText)
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.top, TempoSpacing.sm)

            // Overall score ring
            // Per WIREFRAMES.md Screen 10 — 100pt ring, same style as daily score
            overallScoreRing(report)

            // Title / summary
            Text(report.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)

            Text(report.summary)
                .font(.system(size: 14))
                .italic()
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)

            // 2x2 mini-grid
            // Per WIREFRAMES.md Screen 10 — 2x2 with accent colors
            miniScoreGrid(report)

            // Section cards
            ForEach(report.sections, id: \.title) { section in
                sectionCard(section)
            }

            // AI Insights
            // Per WIREFRAMES.md Screen 10 — Expandable insight cards
            if !report.actionItems.isEmpty {
                aiInsightsSection(report.actionItems)
            }

            // Week-over-week deltas
            if let deltas = report.comparedToLastWeek {
                weekOverWeekSection(deltas)
            }

            // Share button
            // Per WIREFRAMES.md Screen 10 — accent, 44pt
            Button {} label: {
                Text("SHARE REPORT")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.tempoSignal)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, TempoSpacing.lg)

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    // MARK: - Overall Score Ring
    // Per WIREFRAMES.md Screen 10 — 100pt diameter, 8pt stroke

    private func overallScoreRing(_ report: WeeklyReportData) -> some View {
        ZStack {
            Circle()
                .stroke(Color.tempoBorder, lineWidth: 8)
                .frame(width: 100, height: 100)

            Circle()
                .trim(from: 0, to: CGFloat(report.overallScore) / 100.0)
                .stroke(
                    scoreColor(report.overallScore),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))

            Text("\(report.overallScore)")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Mini Score Grid
    // Per WIREFRAMES.md Screen 10 — 2x2 mini-grid, 10pt gap

    private func miniScoreGrid(_ report: WeeklyReportData) -> some View {
        let quadrants: [(String, Int, Color)] = [
            ("Body", report.bodyScore, Color.tempoSuccess),
            ("Fuel", report.fuelScore, Color.tempoAmber),
            ("Mind", report.mindScore, Color.tempoViolet),
            ("Move", report.moveScore, Color.tempoSignal),
        ]

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(quadrants, id: \.0) { name, score, color in
                HStack {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                    Text("\(score)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
    }

    // MARK: - Section Card
    // Per WIREFRAMES.md Screen 10 — Body/Fuel/Mind/Move sections with charts

    private func sectionCard(_ section: ReportSectionData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Section header with icon
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(sentimentColor(section.sentiment))
                Text(section.title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                // Sentiment indicator
                Circle()
                    .fill(sentimentColor(section.sentiment))
                    .frame(width: 8, height: 8)
            }

            Divider().background(Color.tempoDivider)

            // Body text
            Text(section.body)
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextPrimary)
                .lineSpacing(4)
        }
        .padding(TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, TempoSpacing.lg)
    }

    // MARK: - AI Insights Section
    // Per WIREFRAMES.md Screen 10 — Expandable insight cards

    private func aiInsightsSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoSignal)
                Text("AI INSIGHTS")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.lg)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoAmber)

                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineSpacing(3)
                }
                .padding(TempoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.tempoAmber.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, TempoSpacing.lg)
            }
        }
    }

    // MARK: - Week Over Week Deltas

    private func weekOverWeekSection(_ deltas: WeekOverWeekData) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("VS LAST WEEK")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.lg)

            VStack(spacing: 0) {
                deltaRow("Recovery Avg", value: deltas.recoveryAvgChange, suffix: "%")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("Sleep Avg", value: deltas.sleepAvgChangeMin, suffix: " min")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("Workouts", value: deltas.workoutCountChange, suffix: "")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("XP", value: deltas.xpChange, suffix: "")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("Protein Days", value: deltas.proteinAdherenceChange, suffix: "%")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("Study Avg", value: deltas.studyAvgChangeMin, suffix: " min")
                Divider().background(Color.tempoDivider).padding(.leading, TempoSpacing.lg)
                deltaRow("Completion", value: deltas.completionPctChange, suffix: "%")
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, TempoSpacing.lg)
        }
    }

    private func deltaRow(_ label: String, value: Int, suffix: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text("\(value >= 0 ? "+" : "")\(value)\(suffix)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(value > 0 ? Color.tempoSuccess : value < 0 ? Color.tempoError : Color.tempoTextSecondary)
        }
        .frame(height: 44)
        .padding(.horizontal, TempoSpacing.lg)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            ProgressView()
            Text("Analyzing your week...")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No report available")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Reports are generated every Sunday evening. Check back after your first full week.")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, TempoSpacing.xxl)
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return Color.tempoSuccess }
        if score >= 60 { return Color.tempoAmber }
        return Color.tempoError
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment {
        case "positive": return Color.tempoSuccess
        case "warning": return Color.tempoAmber
        case "negative": return Color.tempoError
        default: return Color.tempoTextSecondary
        }
    }

    private func loadReport() {
        // TODO: Fetch from API via services.apiClient
        // For now, show empty state after brief delay
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isLoading = false
        }
    }
}

// MARK: - View Models

struct WeeklyReportData {
    let title: String
    let summary: String
    let overallScore: Int
    let bodyScore: Int
    let fuelScore: Int
    let mindScore: Int
    let moveScore: Int
    let sections: [ReportSectionData]
    let actionItems: [String]
    let comparedToLastWeek: WeekOverWeekData?
}

struct ReportSectionData: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let body: String
    let sentiment: String
}

struct WeekOverWeekData {
    let recoveryAvgChange: Int
    let sleepAvgChangeMin: Int
    let workoutCountChange: Int
    let xpChange: Int
    let proteinAdherenceChange: Int
    let studyAvgChangeMin: Int
    let completionPctChange: Int
}
