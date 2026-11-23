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
    /// §11.6 Week Pulse — the scrubbed day (0 = Mon). Scrubbing also expands
    /// that day's detail card below.
    @State
    private var pulseIndex: Int?
    @State
    private var pulseGestureStart: Int?
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query
    private var userSettings: [UserSettings]
    @Query
    private var allMatches: [Match]

    /// Matches management only makes sense for someone who plays: football
    /// days configured, or matches already logged. Everyone else never sees it.
    private var playsFootball: Bool {
        (userSettings.first?.footballDaysRaw ?? 0) != 0 || !allMatches.isEmpty
    }

    private static let historyWeeksBack = 8

    private let dayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let calendar = Calendar.current

    var body: some View {
        TrainPlanPage {
            // Week header: the range and the previous/next buttons.
            weekHeader

            // §11.6 — the week strip. Drag across it to inspect any day; that
            // day's card expands in sync below.
            weekPulse

            // Live-week-only context cards — a history/preview week must
            // not wear this week's deload banner or coach review.
            if weekOffset == 0 {
                if viewModel.isDeloadWeek {
                    deloadBanner
                }

                // One weekly coach card: last week's graded outcome (Phase 4)
                // with this week's AI plan rationale (Phase 2) folded in.
                if let outcome = viewModel.lastWeekOutcome {
                    coachReviewCard(outcome, rationale: viewModel.aiWeekRationale)
                } else if let rationale = viewModel.aiWeekRationale {
                    aiRationaleCard(rationale)
                }

                if viewModel.aiWeekUnavailable, viewModel.aiWeekRationale == nil {
                    Label(
                        "Couldn't reach the AI coach — this is your standard plan. It'll retry shortly.",
                        systemImage: "wifi.exclamationmark"
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .padding(Tide.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                }
            }

            // Daily detail cards (per MODULE_TRAINING.md Section 9.3)
            dailyCards
        }
        .tidePage()
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
                        .font(Tide.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            if playsFootball {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMatchSchedule = true
                    } label: {
                        Label("Matches", systemImage: "calendar")
                            .font(Tide.body)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScheduleEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(Tide.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .sheet(isPresented: $showScheduleEditor) {
            // Same editor as Settings → Training (one place for split,
            // football days, deload and rest settings).
            NavigationStack {
                TrainingSettingsDetailView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showScheduleEditor = false }
                                .font(Tide.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
            }
            .persistenceAlert()
        }
        .sheet(isPresented: $showMatchSchedule) {
            MatchScheduleView()
                .persistenceAlert()
        }
        .onAppear {
            viewModel.loadWeekPlan(modelContext: modelContext)
        }
        .onChange(of: weekOffset) {
            // A different week is different data — drop the scrub selection.
            pulseIndex = nil
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

    /// Monday of the DISPLAYED week. Uses the locale-independent
    /// `TrainingCalendar` (not `calendar`/`Calendar.current`) — the old
    /// dateComponents+weekday=2 math resolved "this Monday" to TOMORROW on an
    /// en_US Sunday, since en_US's own week starts that Sunday.
    private var displayedMonday: Date {
        let thisMonday = TrainingCalendar.mondayOfWeek(containing: Date())
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
            guard let day = calendar.date(byAdding: .day, value: i, to: monday) else {
                return nil
            }
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
        let canGoBack = weekOffset > -Self.historyWeeksBack
        let canGoForward = weekOffset < 1

        return HStack(spacing: Tide.s2) {
            TrainIconButton(
                systemImage: "chevron.left",
                label: "Previous week",
                tint: canGoBack ? Tide.text : Tide.text3
            ) {
                weekOffset -= 1
                loadOffsetWeek()
                HapticManager.selection()
            }
            .disabled(!canGoBack)

            VStack(spacing: Tide.s1) {
                Text(dateText)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(Tide.labelShrink)
                if weekOffset != 0 {
                    // Tap the label to jump back to the live week.
                    Button {
                        weekOffset = 0
                        loadOffsetWeek()
                        HapticManager.selection()
                    } label: {
                        TrainTag(
                            text: weekOffset > 0 ? "PREVIEW — tap for this week" : "HISTORY — tap for this week",
                            color: TideTrain.caution
                        )
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            TrainIconButton(
                systemImage: "chevron.right",
                label: "Next week",
                tint: canGoForward ? Tide.text : Tide.text3
            ) {
                weekOffset += 1
                loadOffsetWeek()
                HapticManager.selection()
            }
            .disabled(!canGoForward)
        }
    }

    // MARK: - Week Pulse (§11.6)

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    /// A day's training load: completed days report real logged volume;
    /// planned days report the prescription (target weight × target reps,
    /// working sets only) so the strip previews the week's shape.
    private func dayVolume(_ plan: WorkoutPlan) -> Double {
        if plan.status == .completed {
            return plan.totalVolume
        }
        return (plan.exercises ?? []).reduce(0) { total, ex in
            // Fix #9 — a per-side exercise's prescribed reps are single-side;
            // the previewed tonnage must cover both sides, same as a logged
            // per-side set's real `volume` does.
            let sideMultiplier: Double = ex.perSide ? 2 : 1
            return total + (ex.sets ?? []).reduce(0) { setTotal, set in
                guard !set.isWarmup else {
                    return setTotal
                }
                let weight = set.actualWeight ?? set.targetWeight ?? 0
                if let left = set.actualRepsLeft, let right = set.actualRepsRight {
                    return setTotal + weight * Double(left + right)
                }
                let reps = set.actualReps ?? set.targetReps
                return setTotal + (weight * Double(reps) * sideMultiplier)
            }
        }
    }

    private func volumeLabel(_ kg: Double) -> String {
        WeightFormat.volumeText(kg: kg, unit: weightUnit)
    }

    private var weekPulse: some View {
        let slots = displayedSlots
        let volumes = slots.map { $0.map(dayVolume) ?? 0 }
        let peak = max(volumes.max() ?? 0, 1)
        let days: [TrainPlanWeekStrip.Day] = (0 ..< 7).map { idx in
            let plan = slots[safe: idx].flatMap(\.self)
            let volume = volumes[safe: idx] ?? 0
            let date = calendar.date(byAdding: .day, value: idx, to: displayedMonday) ?? displayedMonday
            return TrainPlanWeekStrip.Day(
                id: idx,
                weekday: dayAbbreviations[safe: idx] ?? "",
                code: plan.map { workoutAbbreviation($0.type) },
                // §21 (b) two-a-day — the "+SWM"/"+RUN" tag keeps the variety
                // visible in the week scan.
                extra: plan.flatMap { $0.isTwoADay ? $0.secondarySessionType : nil }.map { "+\(workoutAbbreviation($0))" },
                load: volume > 0 ? volume / peak : 0,
                barColor: pulseColor(plan: plan, hasLoad: volume > 0),
                isToday: calendar.isDateInToday(date),
                isDone: plan?.status == .completed,
                isMatch: plan?.type == .football && plan?.status != .completed
            )
        }

        return VStack(spacing: Tide.s2) {
            Group {
                if let idx = pulseIndex {
                    pulseCallout(index: idx)
                } else {
                    Text("Drag across the week to read any day.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tide.s1)
                }
            }
            .frame(minHeight: Tide.hit)

            TrainPlanWeekStrip(
                days: days,
                selected: pulseIndex,
                onScrub: { idx in
                    if pulseGestureStart == nil {
                        pulseGestureStart = pulseIndex
                    }
                    if pulseIndex != idx {
                        pulseIndex = idx
                        HapticManager.selection()
                        if let slot = displayedSlots[safe: idx], let plan = slot {
                            expandedPlanID = plan.id
                        }
                    }
                },
                onRelease: { idx, travel in
                    // A stationary tap on the already-selected day
                    // collapses the scrub.
                    if travel < 4, pulseGestureStart == idx {
                        pulseIndex = nil
                        expandedPlanID = nil
                    }
                    pulseGestureStart = nil
                }
            )
        }
        .animation(Tide.lively, value: pulseIndex)
    }

    private func pulseColor(plan: WorkoutPlan?, hasLoad: Bool) -> Color {
        guard let plan else {
            return Tide.text3.opacity(0.25)
        }
        if !hasLoad {
            // Non-lifting days (football, run, rest) — a neutral stub.
            return Tide.text3.opacity(0.4)
        }
        let base = recoveryDotColor(plan: plan)
        return plan.status == .completed ? base : base.opacity(0.45)
    }

    private func pulseCallout(index: Int) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            if let slot = displayedSlots[safe: index], let plan = slot {
                HStack(spacing: Tide.s2) {
                    Circle()
                        .fill(recoveryDotColor(plan: plan))
                        .frame(width: TideTrain.dot, height: TideTrain.dot)
                        .accessibilityHidden(true)
                    Text(dayName(for: plan.date))
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text(workoutAbbreviation(plan.type))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                if !stacked {
                    Spacer(minLength: Tide.s2)
                }
                HStack(spacing: Tide.s2) {
                    if dayVolume(plan) > 0 {
                        Text(volumeLabel(dayVolume(plan)))
                            .font(TideTrain.figure(.headline))
                            .foregroundStyle(Color.accentColor)
                    }
                    if plan.totalSets > 0 {
                        Text("\(plan.completedSets)/\(plan.totalSets) sets")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
            } else {
                Text("\(dayAbbreviations[safe: index] ?? "") — no data")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, stacked ? Tide.s2 : 0)
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .tideCard(padding: 0, radius: Tide.tileRadius)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Deload Banner

    private var deloadBanner: some View {
        TrainBanner(
            systemImage: "arrow.down.circle.fill",
            label: "Deload week",
            tint: TideTrain.caution,
            message: "\(viewModel.deloadStyle.blurb) Your body rebuilds stronger."
        ) {
            EmptyView()
        }
    }

    // MARK: - Coach Review (Phase 4)

    private func coachReviewCard(_ outcome: WeekOutcome, rationale: String?) -> some View {
        // Green when the week was productive without overreach; yellow when it
        // overreached or quality dipped. Every number below is real.
        let good = outcome.qualityScore >= 0.6 && outcome.overreachEvents == 0
        let accent = good ? TideTrain.positive : TideTrain.caution

        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: good ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(Tide.caption)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Last week").tideLabel(accent)
                Spacer(minLength: Tide.s2)
                TideNumber(
                    "\(Int((outcome.qualityScore * 100).rounded()))",
                    unit: "%",
                    size: Tide.numeralS,
                    relativeTo: .title2,
                    color: accent
                )
            }

            Text(coachReviewSummary(outcome))
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            if let rationale {
                Divider().overlay(Tide.hairline)
                rationaleRow(rationale)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .overlay {
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        }
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

    /// Rationale on its own — only when there's no graded last week yet.
    private func aiRationaleCard(_ rationale: String) -> some View {
        rationaleRow(rationale)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func rationaleRow(_ rationale: String) -> some View {
        HStack(alignment: .top, spacing: Tide.s2) {
            Image(systemName: "sparkles")
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.accentColor)
            Text(rationale)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Daily Detail Cards

    // Per MODULE_TRAINING.md Section 9.3

    private var dailyCards: some View {
        VStack(spacing: Tide.s2) {
            ForEach(displayedSlots.compactMap(\.self), id: \.id) { plan in
                dailyCard(plan: plan)
            }
            if weekOffset < 0, displayedSlots.allSatisfy({ $0 == nil }) {
                TrainEmptyCard(
                    systemImage: "calendar.badge.clock",
                    title: "No training recorded this week."
                )
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
                withAnimation(Tide.snap) {
                    expandedPlanID = isExpanded ? nil : plan.id
                }
            } label: {
                HStack(alignment: .top, spacing: Tide.s3) {
                    TideIconTile(systemName: workoutIcon(plan.type), tint: workoutTypeColor(plan: plan))

                    VStack(alignment: .leading, spacing: Tide.s1) {
                        // Day label
                        if isToday {
                            Text("Today").tideLabel(Color.accentColor)
                        } else {
                            Text(dayName).tideLabel(Tide.text3)
                        }

                        Text(plan.type.displayName)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)

                        // Meta line
                        if plan.type.isGymWorkout {
                            Text(
                                "~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min · \(plan.orderedExercises.count) exercises"
                            )
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                        } else if plan.type == .football {
                            // Engine note distinguishes a dated fixture
                            // ("Match day") from a recurring football
                            // weekday ("Football day") — §14.
                            Text(plan.notes ?? "Football day")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        } else if plan.type == .rest {
                            Text("Recovery day")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        } else if plan.type == .mobility {
                            Text("~25 min · Active recovery")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }

                        // §21 (b) two-a-day — name the cardio second session
                        // in the detail card so the plan reads honestly.
                        if plan.isTwoADay, let second = plan.secondarySessionType {
                            Text("+ easy \(second.displayName.lowercased()) · second session")
                                .font(Tide.caption)
                                .foregroundStyle(Color.accentColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isCompleted {
                            // A session saved early reads as partial, not "Completed".
                            TrainTag(
                                text: plan.completedSets < plan.totalSets && plan.totalSets > 0
                                    ? "Done \(plan.completedSets)/\(plan.totalSets) sets"
                                    : "Completed",
                                systemImage: "checkmark",
                                color: TideTrain.positive
                            )
                        }
                    }

                    Spacer(minLength: Tide.s2)

                    VStack(alignment: .trailing, spacing: Tide.s2) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                        if isCompleted, let seconds = plan.actualDurationSeconds {
                            Text(WorkoutPlan.durationLabel(seconds: seconds))
                                .font(TideTrain.figure(.footnote, weight: .medium))
                                .foregroundStyle(Tide.text3)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(Tide.s4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the details" : "Shows the details")

            // Expanded content — every day type renders something useful on tap.
            if isExpanded {
                Divider()
                    .overlay(Tide.hairline)
                    .padding(.horizontal, Tide.s4)

                expandedContent(for: plan)
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(isToday ? Color.accentColor.opacity(0.14) : Tide.glassCard),
            in: .rect(cornerRadius: Tide.tileRadius)
        )
    }

    // MARK: - Expanded Content

    /// Renders the per-day expand body. Gym days list the planned exercises;
    /// non-gym days (mobility, football, rest, run/sprint/conditioning) show
    /// activity-appropriate guidance so the expand never reads as empty.
    @ViewBuilder
    private func expandedContent(for plan: WorkoutPlan) -> some View {
        switch plan.type {
        case .push,
             .pull,
             .legs,
             .upper,
             .lower,
             .fullBody:
            gymExerciseList(plan: plan)
        case .mobility:
            mobilityRoutine
        case .football:
            footballContext(plan: plan)
        case .rest:
            restGuidance
        case .run,
             .sprint,
             .conditioning,
             .pool:
            conditioningGuidance(plan: plan)
        }
    }

    private func gymExerciseList(plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            if plan.orderedExercises.isEmpty {
                Text("No exercises planned yet.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                ForEach(Array(plan.orderedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                    HStack(spacing: Tide.s2) {
                        Text("\(index + 1)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .frame(minWidth: Tide.s4, alignment: .trailing)

                        Text(plannedEx.exercise?.name ?? "Exercise")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .lineLimit(1)

                        Spacer()

                        if let sets = plannedEx.sets {
                            Text("\(sets.count) sets")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
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
        return VStack(alignment: .leading, spacing: Tide.s1) {
            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                HStack(spacing: Tide.s2) {
                    Text("\(index + 1)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .frame(minWidth: Tide.s4, alignment: .trailing)

                    Text(move.name)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)

                    Spacer()

                    Text(move.dose)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
        }
    }

    private func footballContext(plan: WorkoutPlan) -> some View {
        let phase = footballPhase(for: plan.date)
        return VStack(alignment: .leading, spacing: Tide.s2) {
            Text(phase.headline)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text(phase.body)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restGuidance: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Full rest")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text("No lifting today. Light walk and mobility optional. Target 8h sleep — recovery is where adaptation happens.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
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
        return VStack(alignment: .leading, spacing: Tide.s2) {
            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            if !body.isEmpty {
                Text(body)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
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

        if isMatchToday, matchYesterday {
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
            return TideTrain.positive
        }
        switch plan.type {
        case .football: return TideTrain.caution
        case .rest: return Tide.text3
        case .mobility: return Tide.text2
        default: return Tide.text
        }
    }

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return TideTrain.positive
        }
        if adj >= 0.6 {
            return TideTrain.caution
        }
        return Tide.danger
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
