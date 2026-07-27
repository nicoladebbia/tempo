//
// WeekPlanView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - WeekPlanView

// Per MODULE_TRAINING.md Section 9 — 7-day training plan grid.
// Per WIREFRAMES.md Section 3 — Week plan layout.

struct WeekPlanView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var expandedPlanID: UUID?
    @State
    private var showScheduleEditor = false
    @State
    private var showMatchSchedule = false

    /// §9.4 week navigation. 0 = this week (the live, persisted-today week);
    /// negative = HISTORY (persisted rows only — past weeks are what happened,
    /// never regenerated fiction); +1 = NEXT WEEK preview (ephemeral engine
    /// output, nothing persisted).
    @State
    private var weekOffset = 0
    /// Aligned Mon..Sun slots for a non-zero offset; nil slot = no data that day.
    @State
    private var offWeekSlots: [WorkoutPlan?] = []

    private static let historyWeeksBack = 8

    private let dayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let calendar = Calendar.current

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Week header
                weekHeader

                // Live-week-only context cards — a history/preview week must
                // not wear this week's deload banner or coach review.
                if weekOffset == 0 {
                    // Deload week indicator
                    if viewModel.isDeloadWeek {
                        deloadBanner
                    }

                    // Coach Review — last week's graded outcome (Phase 4).
                    if let outcome = viewModel.lastWeekOutcome {
                        coachReviewCard(outcome)
                    }

                    // AI plan rationale (Phase 2) — only when the AI ran this week.
                    if let rationale = viewModel.aiWeekRationale {
                        aiRationaleCard(rationale)
                    }
                }

                // 7-day grid
                // Per MODULE_TRAINING.md Section 9.2
                dayGrid

                // Daily detail cards
                dailyCards
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // §9.4 — regenerate this week from current inputs on demand
                // (same path the settings-changed observer runs).
                Button {
                    viewModel.repersonalizeSchedule(modelContext: modelContext)
                    HapticManager.selection()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMatchSchedule = true
                } label: {
                    Label("Matches", systemImage: "calendar")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScheduleEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .sheet(isPresented: $showScheduleEditor) {
            ScheduleEditorView()
        }
        .sheet(isPresented: $showMatchSchedule) {
            MatchScheduleView()
        }
        .onAppear {
            viewModel.loadWeekPlan(modelContext: modelContext)
        }
    }

    // MARK: - Week Header / Navigation (§9.4)

    private var navTitle: String {
        switch weekOffset {
        case 0: "This Week"
        case 1: "Next Week"
        default: "History"
        }
    }

    /// Monday of the DISPLAYED week.
    private var displayedMonday: Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        let thisMonday = calendar.date(from: comps) ?? Date()
        return calendar.date(byAdding: .day, value: weekOffset * 7, to: thisMonday) ?? thisMonday
    }

    /// Mon..Sun slots for whatever week is displayed. Offset 0 aligns the
    /// live weekPlans (defensive against a short generation); other offsets
    /// use the loaded history/preview slots.
    private var displayedSlots: [WorkoutPlan?] {
        weekOffset == 0 ? aligned(viewModel.weekPlans, to: displayedMonday) : offWeekSlots
    }

    private func aligned(_ plans: [WorkoutPlan], to monday: Date) -> [WorkoutPlan?] {
        (0 ..< 7).map { i in
            guard let day = calendar.date(byAdding: .day, value: i, to: monday) else { return nil }
            let candidates = plans.filter { calendar.isDate($0.date, inSameDayAs: day) }
            // Completed row wins (a history week can hold a completed row next
            // to leftover planned scaffolding for the same day).
            return candidates.first { $0.status == .completed } ?? candidates.first
        }
    }

    private func loadOffsetWeek() {
        guard weekOffset != 0 else {
            offWeekSlots = []
            return
        }
        let monday = calendar.startOfDay(for: displayedMonday)
        if weekOffset > 0 {
            offWeekSlots = aligned(
                viewModel.previewWeekPlans(startingMonday: monday, modelContext: modelContext),
                to: monday
            )
        } else {
            // History = persisted truth only. Never regenerate the past.
            guard let end = calendar.date(byAdding: .day, value: 7, to: monday) else {
                offWeekSlots = []
                return
            }
            let descriptor = FetchDescriptor<WorkoutPlan>(
                predicate: #Predicate<WorkoutPlan> { $0.date >= monday && $0.date < end },
                sortBy: [SortDescriptor(\.date)]
            )
            offWeekSlots = aligned((try? modelContext.fetch(descriptor)) ?? [], to: monday)
        }
    }

    private var weekHeader: some View {
        let dateText: String = {
            guard let last = calendar.date(byAdding: .day, value: 6, to: displayedMonday) else {
                return ""
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: displayedMonday)) – \(formatter.string(from: last)), \(calendar.component(.year, from: displayedMonday))"
        }()

        return HStack(spacing: TempoSpacing.md) {
            Button {
                weekOffset -= 1
                loadOffsetWeek()
                HapticManager.selection()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(weekOffset > -Self.historyWeeksBack ? Color.tempoSignal : Color.tempoTextTertiary)
                    .frame(width: 32, height: 32)
            }
            .disabled(weekOffset <= -Self.historyWeeksBack)

            Spacer()

            VStack(spacing: 2) {
                Text(dateText)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                if weekOffset != 0 {
                    // Tap the label to jump back to the live week.
                    Button {
                        weekOffset = 0
                        loadOffsetWeek()
                        HapticManager.selection()
                    } label: {
                        Text(weekOffset > 0 ? "PREVIEW — tap for this week" : "HISTORY — tap for this week")
                            .font(.tempoCaption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoAmber)
                    }
                }
            }

            Spacer()

            Button {
                weekOffset += 1
                loadOffsetWeek()
                HapticManager.selection()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(weekOffset < 1 ? Color.tempoSignal : Color.tempoTextTertiary)
                    .frame(width: 32, height: 32)
            }
            .disabled(weekOffset >= 1)
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Deload Banner

    private var deloadBanner: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoRecoveryYellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("DELOAD WEEK")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoRecoveryYellow)

                Text("\(viewModel.deloadStyle.blurb) Your body rebuilds stronger.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoRecoveryYellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoRecoveryYellow.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Coach Review (Phase 4)

    private func coachReviewCard(_ outcome: WeekOutcome) -> some View {
        // Green when the week was productive without overreach; yellow when it
        // overreached or quality dipped. Every number below is real.
        let good = outcome.qualityScore >= 0.6 && outcome.overreachEvents == 0
        let accent = good ? Color.tempoRecoveryGreen : Color.tempoRecoveryYellow

        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: good ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                Text("LAST WEEK")
                    .font(.tempoHeadline)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(Int((outcome.qualityScore * 100).rounded()))%")
                    .font(.tempoHeadline)
                    .foregroundStyle(accent)
            }

            Text(coachReviewSummary(outcome))
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func coachReviewSummary(_ outcome: WeekOutcome) -> String {
        var parts: [String] = []
        parts.append("\(outcome.progressionHits) \(outcome.progressionHits == 1 ? "lift" : "lifts") up")
        if outcome.overreachEvents > 0 {
            parts.append("\(outcome.overreachEvents) overreach")
        } else {
            parts.append("0 overreach")
        }
        if outcome.missedSessions > 0 {
            parts.append("\(outcome.missedSessions) missed")
        }
        let trend = outcome.netVolumeChange >= 0 ? "volume up" : "volume down"
        parts.append(trend)
        return parts.joined(separator: " · ")
    }

    // MARK: - AI Plan Rationale (Phase 2)

    private func aiRationaleCard(_ rationale: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoAccent)
            Text(rationale)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - 7-Day Grid

    // Per MODULE_TRAINING.md Section 9.2

    private var dayGrid: some View {
        HStack(spacing: TempoSpacing.xxs) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { index, slot in
                if let plan = slot {
                    dayCell(plan: plan, dayLabel: dayAbbreviations[safe: index] ?? "")
                } else {
                    emptyDayCell(dayLabel: dayAbbreviations[safe: index] ?? "")
                }
            }
        }
    }

    /// A day with no data (history week before the app existed, or a gap).
    private func emptyDayCell(dayLabel: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(dayLabel)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Circle()
                .fill(Color.tempoTextTertiary.opacity(0.25))
                .frame(width: 8, height: 8)
            Text("—")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Color.clear.frame(width: 10, height: 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
    }

    private func dayCell(plan: WorkoutPlan, dayLabel: String) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed

        return VStack(spacing: TempoSpacing.xxs) {
            // Day label
            Text(dayLabel)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            // Recovery dot
            Circle()
                .fill(recoveryDotColor(plan: plan))
                .frame(width: 8, height: 8)

            // Workout type abbreviation
            Text(workoutAbbreviation(plan.type))
                .font(.tempoCaption2)
                .fontWeight(.medium)
                .foregroundStyle(workoutTypeColor(plan: plan))

            // §21 (b) two-a-day — the day carries a cardio SECOND session; show a
            // "+SWM"/"+RUN" tag so the variety is visible in the week scan, not
            // hidden until the Today card opens.
            if plan.isTwoADay, let second = plan.secondarySessionType {
                Text("+\(workoutAbbreviation(second))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Status indicator
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.tempoRecoveryGreen)
            } else if plan.type == .football {
                Image(systemName: "sportscourt")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Color.clear.frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(
            isToday
                ? Color.tempoSurfaceCard
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(isToday ? Color.tempoSignal : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    // MARK: - Daily Detail Cards

    // Per MODULE_TRAINING.md Section 9.3

    private var dailyCards: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(displayedSlots.compactMap { $0 }, id: \.id) { plan in
                dailyCard(plan: plan)
            }
            if weekOffset < 0, displayedSlots.allSatisfy({ $0 == nil }) {
                Text("No training recorded this week.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.top, TempoSpacing.md)
            }
        }
    }

    private func dailyCard(plan: WorkoutPlan) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed
        let dayName = dayName(for: plan.date)
        let isExpanded = expandedPlanID == plan.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedPlanID = isExpanded ? nil : plan.id
                }
            } label: {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    // Day label
                    HStack(spacing: TempoSpacing.sm) {
                        if isToday {
                            Text("TODAY")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoSignal)
                        } else {
                            Text(dayName)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }

                    // Workout info
                    HStack {
                        // Icon
                        Image(systemName: workoutIcon(plan.type))
                            .font(.tempoBody)
                            .foregroundStyle(workoutTypeColor(plan: plan))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: TempoSpacing.xs) {
                                Text(plan.type.displayName.uppercased())
                                    .font(.tempoHeadline)
                                    .foregroundStyle(Color.tempoTextPrimary)

                                if isCompleted {
                                    Text("— Completed")
                                        .font(.tempoCaption1)
                                        .foregroundStyle(Color.tempoRecoveryGreen)
                                }
                            }

                            // Meta line
                            if plan.type.isGymWorkout {
                                Text(
                                    "~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min · \(plan.orderedExercises.count) exercises"
                                )
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .football {
                                // Engine note distinguishes a dated fixture
                                // ("Match day") from a recurring football
                                // weekday ("Football day") — §14.
                                Text(plan.notes ?? "Football day")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .rest {
                                Text("Recovery day")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .mobility {
                                Text("~25 min · Active recovery")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }

                            // §21 (b) two-a-day — name the cardio second session
                            // in the detail card so the plan reads honestly.
                            if plan.isTwoADay, let second = plan.secondarySessionType {
                                Text("+ easy \(second.displayName.lowercased()) · second session")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoSignal)
                            }
                        }

                        Spacer()

                        if isCompleted, let duration = plan.actualDurationMinutes {
                            Text("\(duration) min")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .padding(TempoSpacing.cardPadding)
            }
            .buttonStyle(.plain)

            // Expanded content — every day type renders something useful on tap.
            if isExpanded {
                Divider()
                    .padding(.horizontal, TempoSpacing.cardPadding)

                expandedContent(for: plan)
                    .padding(.horizontal, TempoSpacing.cardPadding)
                    .padding(.vertical, TempoSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Expanded Content

    /// Renders the per-day expand body. Gym days list the planned exercises;
    /// non-gym days (mobility, football, rest, run/sprint/conditioning) show
    /// activity-appropriate guidance so the expand never reads as empty.
    @ViewBuilder
    private func expandedContent(for plan: WorkoutPlan) -> some View {
        switch plan.type {
        case .push, .pull, .legs, .upper, .lower, .fullBody:
            gymExerciseList(plan: plan)
        case .mobility:
            mobilityRoutine
        case .football:
            footballContext(plan: plan)
        case .rest:
            restGuidance
        case .run, .sprint, .conditioning, .pool:
            conditioningGuidance(plan: plan)
        }
    }

    private func gymExerciseList(plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            if plan.orderedExercises.isEmpty {
                Text("No exercises planned yet.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(Array(plan.orderedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                    HStack(spacing: TempoSpacing.sm) {
                        Text("\(index + 1)")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .frame(width: 16, alignment: .trailing)

                        Text(plannedEx.exercise?.name ?? "Exercise")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        if let sets = plannedEx.sets {
                            Text("\(sets.count) sets")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
            }
        }
    }

    private var mobilityRoutine: some View {
        // Single source of warm-up/mobility content (shared with the in-session
        // warm-up block). A mobility day uses the full-body routine.
        let moves = WarmupRoutine.routine(for: .fullBody).moves
        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                HStack(spacing: TempoSpacing.sm) {
                    Text("\(index + 1)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(width: 16, alignment: .trailing)

                    Text(move.name)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(move.dose)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    private func footballContext(plan: WorkoutPlan) -> some View {
        let phase = footballPhase(for: plan.date)
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(phase.headline)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(phase.body)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restGuidance: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Full rest")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("No lifting today. Light walk and mobility optional. Target 8h sleep — recovery is where adaptation happens.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func conditioningGuidance(plan: WorkoutPlan) -> some View {
        let title: String
        let body: String
        switch plan.type {
        case .run:
            title = "Run"
            body = "Steady Z2 effort, conversational pace. Aim for ~30–45 min."
        case .sprint:
            title = "Sprint session"
            body = "6–8 × 30–60m sprints with full recovery. Warm up thoroughly before max effort."
        case .conditioning:
            title = "Conditioning"
            body = "Mixed-modal aerobic work — bike intervals, sled pushes, or circuits. 20–30 min."
        default:
            title = plan.type.displayName
            body = ""
        }
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            if !body.isEmpty {
                Text(body)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Classify a football day relative to surrounding planned matches.
    /// Looks at the loaded weekPlans for other .football entries within ±1 day.
    private func footballPhase(for date: Date) -> (headline: String, body: String) {
        let cal = calendar
        let today = cal.startOfDay(for: date)

        let footballDates = viewModel.weekPlans
            .filter { $0.type == .football }
            .map { cal.startOfDay(for: $0.date) }

        let isMatchToday = footballDates.contains(today)
        let dayAfter = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let dayBefore = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let matchTomorrow = footballDates.contains(dayAfter)
        let matchYesterday = footballDates.contains(dayBefore)

        if isMatchToday && matchYesterday {
            return ("Back-to-back match", "Second game in 24h. Focus on hydration, mobility between games, and active recovery walks.")
        }
        if isMatchToday {
            return ("Match day", "Game is the workout. Stick to your pre-match routine: light warm-up, hydrate, fuel ~3h before kick-off.")
        }
        if matchTomorrow {
            return ("Match tomorrow (T-1)", "Light technical work only. Hydrate, eat clean carbs, sleep 8h. No heavy lifting.")
        }
        if matchYesterday {
            return ("Post-match (T+1)", "Active recovery: 20 min Z2 walk + full mobility flow. No lifting, no sprints.")
        }
        return ("Football session", "Training session — sprint patterns, ball work, and small-sided games. Treat as a high-intensity day.")
    }

    // MARK: - Helpers

    private func workoutAbbreviation(_ type: WorkoutType) -> String {
        switch type {
        case .push: "PSH"
        case .pull: "PUL"
        case .legs: "LEG"
        case .upper: "UPR"
        case .lower: "LWR"
        case .fullBody: "FUL"
        case .football: "FTB"
        case .run: "RUN"
        case .mobility: "MOB"
        case .rest: "RST"
        case .sprint: "SPR"
        case .conditioning: "CON"
        case .pool: "SWM"
        }
    }

    private func workoutIcon(_ type: WorkoutType) -> String {
        switch type {
        case .push,
             .pull,
             .legs,
             .upper,
             .lower,
             .fullBody:
            "figure.strengthtraining.traditional"
        case .football: "sportscourt"
        case .run,
             .sprint: "figure.run"
        case .conditioning: "flame"
        case .pool: "figure.pool.swim"
        case .mobility: "figure.flexibility"
        case .rest: "bed.double"
        }
    }

    private func workoutTypeColor(plan: WorkoutPlan) -> Color {
        if plan.status == .completed {
            return Color.tempoRecoveryGreen
        }
        switch plan.type {
        case .football: return Color.tempoRecoveryYellow
        case .rest: return Color.tempoTextTertiary
        case .mobility: return Color.tempoTextSecondary
        default: return Color.tempoTextPrimary
        }
    }

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return Color.tempoRecoveryGreen
        }
        if adj >= 0.6 {
            return Color.tempoRecoveryYellow
        }
        return Color.tempoRecoveryRed
    }

    private func dayName(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        guard !exercises.isEmpty else {
            return 20
        }

        var totalMinutes = 5.0 // Warmup period

        for (index, plannedEx) in exercises.enumerated() {
            let sets = plannedEx.orderedSets
            let isCompound = plannedEx.exercise?.isCompound ?? false

            for set in sets {
                if set.isWarmup {
                    totalMinutes += 1.0
                } else if isCompound {
                    totalMinutes += 2.5
                } else {
                    totalMinutes += 1.5
                }
            }

            if index < exercises.count - 1 {
                totalMinutes += 1.0 // Between-exercise transition
            }
        }

        totalMinutes += 3.0 // Cooldown

        return max(20, Int(totalMinutes.rounded()))
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
