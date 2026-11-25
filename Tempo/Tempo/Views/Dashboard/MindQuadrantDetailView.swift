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

// The Study page. Per MODULE_DASHBOARD.md Section 4.4 (Mind Expanded View),
// with the focus history folded in: the study target, today's sessions, the
// timer, exams, the week and the history behind it are one page. You start a
// session from it, the timer covers the screen while it runs, and you land
// back here with the session in the list.

struct MindQuadrantDetailView: View {
    let data: MindQuadrantData
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood

    /// The timer's own view model, alive while the timer covers the page. It must
    /// not be rebuilt when this page redraws, or a running timer would reset.
    @State
    private var focusModel: AccountabilityViewModel?
    @State
    private var showAddExam = false
    @State
    private var exams: [ExamData]
    @State
    private var toast: ToastData?
    /// A deleted session stays in the store until its Undo toast is over.
    @State
    private var pendingDeleteID: UUID?

    /// Every finished session, freshest first.
    @Query(
        filter: #Predicate<StudySession> { $0.endTime != nil },
        sort: [SortDescriptor(\StudySession.startTime, order: .reverse)]
    )
    private var allCompletedSessions: [StudySession]

    /// Today's accountability record: the same minutes the Today tile counts.
    @Query
    private var todayRecords: [DailyAccountability]

    init(data: MindQuadrantData) {
        self.data = data
        _exams = State(initialValue: data.exams)
        let start = Calendar.current.startOfDay(for: Date())
        _todayRecords = Query(
            filter: #Predicate<DailyAccountability> { $0.date >= start },
            sort: [SortDescriptor(\DailyAccountability.date, order: .reverse)]
        )
    }

    // MARK: Derived

    /// Sessions without the one waiting on its Undo.
    private var sessions: [StudySession] {
        allCompletedSessions.filter { $0.id != pendingDeleteID }
    }

    private var todaysSessions: [StudySession] {
        let start = Calendar.current.startOfDay(for: Date())
        return sessions.filter { $0.startTime >= start }
    }

    private var earlierSessions: [StudySession] {
        let start = Calendar.current.startOfDay(for: Date())
        return Array(sessions.filter { $0.startTime < start }.prefix(20))
    }

    private var entries: [StudyEntry] {
        sessions.map { StudyEntry(startTime: $0.startTime, durationMinutes: $0.durationMinutes, subject: $0.subject) }
    }

    /// The minutes the page counts today. The hidden session's minutes are
    /// already off, so the number and the list never disagree during the Undo.
    private var minutesToday: Int {
        let counted = todayRecords.first?.totalStudyMinutes ?? data.studyMinutesToday
        let hidden = allCompletedSessions.first { $0.id == pendingDeleteID }
        let hiddenToday = hidden.map {
            $0.startTime >= Calendar.current.startOfDay(for: Date()) ? StudySessionRemoval.creditedMinutes(of: $0) : 0
        } ?? 0
        return StudyTodayList.shownMinutes(counted: counted, removed: hiddenToday)
    }

    private var shown: MindQuadrantData {
        var copy = data
        copy.studyMinutesToday = minutesToday
        return copy
    }

    private var hasHistory: Bool {
        !sessions.isEmpty
    }

    // MARK: Body

    var body: some View {
        TideScrollPage(spacing: Tide.s6, spacer: Tide.s2) {
            progressHeroSection
            todaySessionsSection
            // At accessibility sizes the button is two lines tall; pinned it would
            // eat the page, so it scrolls with the content there.
            if typeSize.isAccessibilitySize {
                startSessionButton
            }
            upcomingExamsSection
            if hasHistory {
                weekSection
                statsSection
                subjectSection
                timeOfDaySection
                earlierSessionsSection
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The one primary action stays under the thumb.
            if !typeSize.isAccessibilitySize {
                startSessionButton
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s3)
                    .padding(.bottom, Tide.s2)
                    // Content fades out under the button instead of showing through.
                    .pinnedBarScrim()
            }
        }
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
        // The page field rests while the timer or the exam sheet is over it.
        // This must sit on the page itself: it sets an environment value that
        // only reaches the views below it.
        .tideCovered(focusModel != nil || showAddExam)
        .fullScreenCover(isPresented: Binding(
            get: { focusModel != nil },
            set: {
                if !$0 {
                    focusModel = nil
                }
            }
        )) {
            if let focusModel {
                FocusTimerView(viewModel: focusModel)
            }
        }
        .sheet(isPresented: $showAddExam, onDismiss: reloadExams) {
            NavigationStack {
                AddExamSheet(calendar: services.calendar)
            }
        }
        .tempoToast($toast)
        .onChange(of: toast) { _, newValue in
            // The Undo window is over: the delete becomes final.
            if newValue == nil {
                commitPendingDeletion()
            }
        }
        .onDisappear { commitPendingDeletion() }
        .task { reloadExams() }
        .firstTip(
            "study.home",
            "Press Start to run a timer. Tap a score to see how it works.",
            systemImage: "book.fill"
        )
        .accessibilityIdentifier("study-page")
    }

    // MARK: - Progress Hero

    // Per MODULE_DASHBOARD.md Section 4.4 — Progress Hero

    private var progressHeroSection: some View {
        let hero = shown
        let percent = Int((min(hero.studyProgress, 1.0) * 100).rounded())
        return RecoveryHero {
            TideDial(score: percent, caption: "Target", diameter: Tide.dialHero)
                .accessibilityLabel("Study target")
                .accessibilityValue("\(percent) percent")
                .explains(Explainer.studyTarget.showing("\(percent) percent"))
        } side: {
            Text("Studied today").tideLabel()
            TideNumber(hero.formattedStudyTime, size: Tide.numeralL, relativeTo: .largeTitle)
            Text("of \(hero.formattedStudyTarget) target")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)

            // Drill sergeant quip
            Text(studyQuip(progress: hero.studyProgress))
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tide.s1)

            // Streak badge
            if hero.currentStreakDays >= 2 {
                TideStatusPill(
                    text: "\(hero.currentStreakDays)-day streak",
                    tint: hero.currentStreakDays >= 7 ? Tide.streak : Tide.text2,
                    systemImage: "flame.fill"
                )
                .explains(Explainer.studyStreak.showing("\(hero.currentStreakDays) days"))
            }
        }
        .accessibilityIdentifier("study-hero")
    }

    // MARK: - Today's Sessions

    // Per MODULE_DASHBOARD.md Section 4.4 — Today's Sessions

    private var todaySessionsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Today's sessions")

            let today = todaysSessions
            if let empty = StudyTodayList.empty(minutesToday: minutesToday, sessionCount: today.count) {
                switch empty {
                case .nothingYet:
                    TideEmptyPanel(
                        systemImage: "book.closed",
                        title: "No study sessions yet",
                        message: "Start one below and it lands here."
                    )
                    .tideCard()
                case .minutesWithoutSessions:
                    TideEmptyPanel(
                        systemImage: "book.closed",
                        title: "No session to list",
                        message: "Today's study time was counted without the focus timer."
                    )
                    .tideCard()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(today.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session, showsDate: false)
                        if index < today.count - 1 {
                            TideDivider().padding(.leading, Tide.s4)
                        }
                    }
                }
                .tideCard(padding: 0)
            }
        }
    }

    private func sessionRow(_ session: StudySession, showsDate: Bool) -> some View {
        // At accessibility sizes the icon goes and the duration drops under the name.
        let stacks = typeSize.isAccessibilitySize
        let score = session.effectiveFocusScore > 0
            ? TideNumber(
                "\(session.effectiveFocusScore)", unit: "%", size: Tide.numeralS, relativeTo: .headline,
                weight: .semibold, color: focusScoreColor(session.effectiveFocusScore)
            )
            .explains(Explainer.focusScore.showing("\(session.effectiveFocusScore) percent"))
            : nil

        return HStack(alignment: stacks ? .top : .center, spacing: Tide.s3) {
            if !stacks {
                TideAreaIconTile(systemName: "book.fill", tint: mood.accent)
            }

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(session.subject ?? "Focus session")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(stacks ? 4 : 2)
                Group {
                    if showsDate {
                        Text(session.startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                    } else {
                        Text(rangeText(session))
                    }
                }
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)

                if stacks {
                    durationAndScore(session, score: score)
                }
            }

            if !stacks {
                Spacer(minLength: Tide.s2)
                durationAndScore(session, score: score)
            }

            sessionMenu(session)
        }
        .padding(.leading, Tide.s4)
        .padding(.trailing, Tide.s2)
        .padding(.vertical, Tide.s2)
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study-session-row")
    }

    @ViewBuilder
    private func durationAndScore(_ session: StudySession, score: (some View)?) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        layout {
            TideNumber(
                "\(session.durationMinutes)", unit: "m", size: Tide.numeralS, relativeTo: .headline,
                weight: .semibold
            )
            // Its own element, so the score's explainer can be reached on its own.
            if let score {
                score
            }
        }
    }

    private func sessionMenu(_ session: StudySession) -> some View {
        Menu {
            Button(role: .destructive) {
                removeWithUndo(session)
            } label: {
                Label("Delete session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.rect)
        }
        .accessibilityLabel("Session options")
        .accessibilityIdentifier("study-session-menu")
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
            // The timer needs today's tasks loaded: without them its Start button does nothing.
            let model = AccountabilityViewModel(engine: services.accountabilityEngine)
            model.loadToday(modelContext: modelContext)
            focusModel = model
        } label: {
            Label("Start study session", systemImage: "play.fill")
        }
        .buttonStyle(.tidePrimary)
        .accessibilityIdentifier("study-start-session")
    }

    // MARK: - Upcoming Exams

    // Per MODULE_DASHBOARD.md Section 4.4 — Upcoming Exams

    private var upcomingExamsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Upcoming exams")

            if exams.isEmpty {
                TideEmptyPanel(
                    systemImage: "calendar.badge.clock",
                    title: "No upcoming exams",
                    message: "Add one and the countdown shows up on Today.",
                    actionTitle: "Add exam"
                ) {
                    showAddExam = true
                }
                .tideCard()
            } else {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    VStack(spacing: 0) {
                        ForEach(Array(exams.enumerated()), id: \.element.id) { index, exam in
                            if index > 0 {
                                TideDivider()
                            }
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
            }
        }
    }

    private func examRow(_ exam: ExamData) -> some View {
        HStack(spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(exam.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)

                Text(TempoDateFormatters.dateOnly.string(from: exam.date))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }

            Spacer(minLength: Tide.s2)

            TideStatusPill(text: exam.formattedCountdown, tint: examDotColor(exam.daysUntil))
        }
        .padding(.vertical, Tide.s2)
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    /// Exams come from the calendar. Reload them when the page opens and after
    /// one is added, so a new exam shows here without leaving the page.
    private func reloadExams() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .weekOfYear, value: 3, to: Date()) ?? Date()
        let found = services.calendar
            .detectExamDates(in: DateInterval(start: start, end: end))
            .map { ExamData(name: $0.subject, date: $0.date) }
        if !found.isEmpty {
            exams = found
        }
    }

    // MARK: - This Week

    // Per MODULE_DASHBOARD.md Section 4.4 — Study Trend Chart

    private var weekSection: some View {
        let days = StudyHistory.lastDays(entries, endingOn: Date())
        let weekTotal = days.reduce(0) { $0 + $1.minutes }
        let bars = days.map {
            TempoBarChartSeries<String>.Bar(
                label: TempoDateFormatters.shortDayOfWeek.string(from: $0.date), value: Double($0.minutes)
            )
        }
        let series = TempoBarChartSeries(id: "study", label: "Study", color: mood.accent, bars: bars)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Last 7 days", trailing: StudyHistory.formatMinutes(weekTotal))

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

    // MARK: - Stats

    private var statsSection: some View {
        let best = StudyHistory.bestDay(entries)
        let total = entries.reduce(0) { $0 + $1.durationMinutes }
        let average = averageFocusScore
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "All time")

            LazyVGrid(
                // One tile per row at accessibility sizes, so the numbers keep their width.
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tide.s3),
                    count: typeSize.isAccessibilitySize ? 1 : 2
                ),
                spacing: Tide.s3
            ) {
                TideMetricTile(
                    label: "Sessions", value: "\(sessions.count)", tint: Tide.text, systemImage: "clock.fill"
                )
                TideMetricTile(
                    label: "Total time", value: StudyHistory.formatMinutes(total), tint: Tide.text,
                    systemImage: "timer"
                )
                TideMetricTile(
                    label: "Avg focus",
                    value: average.map { "\($0)" } ?? "--",
                    unit: average == nil ? nil : "%",
                    tint: average.map(focusScoreColor) ?? Tide.text3,
                    systemImage: "brain.head.profile"
                )
                .explains(Explainer.averageFocus.showing(average.map { "\($0) percent" }))
                TideMetricTile(
                    label: "Best day",
                    value: best.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) } ?? "--",
                    detail: best.map { StudyHistory.formatMinutes($0.minutes) },
                    tint: TideTone.gold,
                    systemImage: "trophy.fill"
                )
                .explains(Explainer.bestDay.showing(best.map { StudyHistory.formatMinutes($0.minutes) }))
            }
        }
        .accessibilityIdentifier("study-stats")
    }

    /// The average over sessions that have a focus score or a recorded
    /// distraction. Nil when none does, so the tile says "--" and not 0%.
    private var averageFocusScore: Int? {
        let scored = sessions.filter { $0.focusScore != nil || $0.distractions > 0 }
        guard !scored.isEmpty else {
            return nil
        }
        return scored.reduce(0) { $0 + $1.effectiveFocusScore } / scored.count
    }

    // MARK: - By Subject

    private var subjectSection: some View {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let totals = StudyHistory.subjectTotals(entries, since: weekStart)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "By subject", trailing: "This week")

            if totals.isEmpty {
                TideEmptyPanel(systemImage: "books.vertical", title: "No subjects logged this week")
                    .tideCard()
            } else {
                VStack(spacing: Tide.s4) {
                    let total = max(1, totals.reduce(0) { $0 + $1.minutes })
                    ForEach(totals, id: \.subject) { row in
                        subjectRow(row, total: total)
                    }
                }
                .tideCard()
            }
        }
    }

    private func subjectRow(_ row: StudyHistory.SubjectTotal, total: Int) -> some View {
        let fraction = Double(row.minutes) / Double(total)
        let stacks = typeSize.isAccessibilitySize
        let head = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(alignment: .leading, spacing: Tide.s2) {
            head {
                Text(row.subject)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(stacks ? 3 : 1)
                if !stacks {
                    Spacer(minLength: Tide.s2)
                }
                Text(StudyHistory.formatMinutes(row.minutes))
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                    .foregroundStyle(Tide.text2)
            }
            TideLevelBar(progress: fraction, color: mood.accent.opacity(0.5 + 0.5 * fraction), height: Tide.barSlim)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Time of Day

    @ScaledMetric(relativeTo: .caption2)
    private var heatCell: CGFloat = 14

    private var timeOfDaySection: some View {
        let grid = StudyHistory.heatmap(entries, now: Date())
        let maxValue = max(1, grid.flatMap(\.self).max() ?? 1)
        let hasData = grid.contains { $0.contains { $0 > 0 } }
        let hours = Array(StudyHistory.heatmapHours)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Time of day", trailing: "Last 30 days")

            if hasData {
                VStack(spacing: Tide.hair) {
                    // Day-of-week header
                    HStack(spacing: Tide.hair) {
                        Color.clear.frame(width: Tide.s6, height: Tide.rule)
                        ForEach(Array(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                                .lineLimit(1)
                                .minimumScaleFactor(Tide.labelShrink)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)

                    ForEach(Array(hours.enumerated()), id: \.offset) { row, hour in
                        HStack(spacing: Tide.hair) {
                            Text(hour % 3 == 0 ? "\(hour)" : "")
                                .font(Tide.axisFont)
                                .foregroundStyle(Tide.text3)
                                .frame(width: Tide.s6, alignment: .trailing)
                                .padding(.trailing, Tide.s1)
                                .accessibilityHidden(true)
                            ForEach(0 ..< 7, id: \.self) { column in
                                heatmapCell(value: grid[column][row], max: maxValue)
                            }
                        }
                    }
                }
                .tideCard(padding: Tide.s4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Study time by weekday and hour, last 30 days")
                .accessibilityValue("Busiest slot \(busiestSlot(grid))")
                .explains(.studyHeatmap)
            } else {
                TideEmptyPanel(systemImage: "clock", title: "No sessions in the last 30 days")
                    .tideCard()
            }
        }
    }

    private func heatmapCell(value: Int, max: Int) -> some View {
        let intensity = Double(value) / Double(max)
        let color = value == 0 ? Tide.fill : mood.accent.opacity(0.2 + 0.8 * intensity)
        return RoundedRectangle(cornerRadius: Tide.hair)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: heatCell)
    }

    private func busiestSlot(_ grid: [[Int]]) -> String {
        var best = (column: 0, row: 0, value: -1)
        for column in 0 ..< 7 {
            for row in 0 ..< grid[column].count where grid[column][row] > best.value {
                best = (column, row, grid[column][row])
            }
        }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return "\(names[best.column]) at \(best.row + StudyHistory.heatmapHours.lowerBound):00"
    }

    // MARK: - Earlier Sessions

    @ViewBuilder
    private var earlierSessionsSection: some View {
        let earlier = earlierSessions
        if !earlier.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Earlier sessions")

                VStack(spacing: 0) {
                    ForEach(Array(earlier.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session, showsDate: true)
                        if index < earlier.count - 1 {
                            TideDivider().padding(.leading, Tide.s4)
                        }
                    }
                }
                .tideCard(padding: 0)
            }
        }
    }

    // MARK: - Delete with Undo

    /// Hides the session and offers Undo. It is only deleted when the toast is over.
    private func removeWithUndo(_ session: StudySession) {
        // A second delete while the first toast is up makes the first final.
        commitPendingDeletion()
        let id = session.id
        withAnimation(Tide.snap) {
            pendingDeleteID = id
        }
        toast = ToastData(
            message: "Session deleted.",
            style: .info,
            actionTitle: "Undo"
        ) {
            withAnimation(Tide.snap) {
                if pendingDeleteID == id {
                    pendingDeleteID = nil
                }
            }
        }
    }

    private func commitPendingDeletion() {
        guard let id = pendingDeleteID else {
            return
        }
        pendingDeleteID = nil
        guard let session = allCompletedSessions.first(where: { $0.id == id }) else {
            return
        }
        // Its minutes come off the day's total and the Study task, so Today,
        // Lockdown and this page agree.
        StudySessionRemoval.remove(session, modelContext: modelContext)
        // Today and Lockdown reload when study progress changes.
        NotificationCenter.default.post(name: .tempoNonNegotiableChanged, object: nil)
    }

    // MARK: - Helpers

    private func studyQuip(progress: Double) -> String {
        switch progress {
        case 0: "Zero minutes. The books miss you."
        case ..<0.5: "Not done yet. Back to the desk."
        case ..<1.0: "More than half. Keep going."
        case 1.0: "Target hit. Respect."
        default: "Going extra. That's elite."
        }
    }

    private func examDotColor(_ daysUntil: Int) -> Color {
        switch daysUntil {
        case ...7: Tide.danger
        case 8 ... 14: TideTone.amber
        default: Tide.text3
        }
    }

    private func focusScoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return TideTone.mint
        }
        if score >= 50 {
            return TideTone.amber
        }
        return Tide.danger
    }
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
            } footer: {
                Text("Saved to your calendar, with a countdown on Today.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            .tideListRow()

            if let error = saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                }
                .tideListRow()
            }
        }
        .tidePage()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
