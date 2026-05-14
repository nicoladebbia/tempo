//
// DayPlannerService.swift
// Tempo
//
// Impure side of the day planner. Reads SwiftData + CalendarService,
// builds a DayPlannerInput, runs the pure solver, persists the resulting
// DayPlan. Per docs/INTELLIGENCE_REMEDIATION_PLAN.md §9.
//
// Keep this thin — solver math lives in `DayPlanner`. Everything here is
// I/O glue that's hard to unit-test.
//

import Foundation
import SwiftData

@MainActor
final class DayPlannerService {

    private let modelContext: ModelContext
    private let calendar: any CalendarServiceProtocol
    private let recoveryEngine: any RecoveryEngineProtocol

    init(
        modelContext: ModelContext,
        calendar: any CalendarServiceProtocol,
        recoveryEngine: any RecoveryEngineProtocol
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.recoveryEngine = recoveryEngine
    }

    // MARK: - Public API

    /// Plan today (or another specific day). Idempotent: deletes any
    /// existing DayPlan for the same date first.
    @discardableResult
    func replan(for date: Date = Date(), reason: DayPlanReason = .userRequested) async -> DayPlan? {
        let day = Calendar.current.startOfDay(for: date)
        let dayInterval = DateInterval(start: day, end: day.addingTimeInterval(86_400))

        // 1. Fetch external events.
        let events = (try? await calendar.fetchEvents(for: dayInterval)) ?? []
        let fixedBlocks = Self.fixedBlocksFromEvents(events, dayStart: day, calendarService: calendar, dayDate: day)

        // 2. Fetch local sources.
        let meals = fetchMeals(on: day)
        let workout = fetchWorkout(on: day)
        let studyPrefMinutes = fetchStudySessionLength()
        let studyBlocks = generateStudyBlocks(
            length: studyPrefMinutes,
            dayStart: day,
            fixed: fixedBlocks,
            meals: meals,
            workout: workout
        )
        let (wake, bedtime) = fetchWakeBedtime()

        // 3. Build the solver input.
        let input = DayPlannerInput(
            date: day,
            wakeMinute: wake,
            bedtimeMinute: bedtime,
            fixedBlocks: fixedBlocks,
            mealBlocks: meals,
            workoutBlock: workout,
            studyBlocks: studyBlocks,
            recoveryBlock: nil
        )

        // 4. Solve.
        let timeBlocks = DayPlanner.solve(input)

        // 5. Persist (delete-then-insert).
        deleteExistingPlans(for: day)
        let plan = DayPlan(date: day, generatedAt: Date(), blocks: timeBlocks)
        // Wire the inverse relationship so cascade-delete works.
        for block in timeBlocks {
            block.plan = plan
        }
        modelContext.insert(plan)
        for block in timeBlocks {
            modelContext.insert(block)
        }
        try? modelContext.save()

        return plan
    }

    /// Lookup the latest DayPlan for the day. Nil when none exists.
    func currentPlan(for date: Date = Date()) -> DayPlan? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DayPlan>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Input gathering

    private func fetchMeals(on day: Date) -> [PlannedBlock] {
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.dayDate == day }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { meal -> PlannedBlock? in
            guard let (start, end) = Self.minutesOfDay(timeString: meal.scheduledTime, durationMinutes: meal.eatDurationMinutes) else {
                return nil
            }
            return PlannedBlock(
                startMinuteOfDay: start,
                endMinuteOfDay: end,
                title: meal.mealName,
                sourceId: meal.id.uuidString
            )
        }
    }

    private func fetchWorkout(on day: Date) -> PlannedBlock? {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= day && $0.date < next }
        )
        guard let workout = (try? modelContext.fetch(descriptor))?.first else { return nil }

        // Conservative default placement: 17:00–18:00 on training days,
        // skipped entirely on `.rest`. This is a v1 heuristic — once the
        // §7.6 training-program AI route is consulted by `replan`, it can
        // override these boundaries.
        if workout.type == .rest { return nil }
        let duration = workout.durationMinutes ?? 60
        let start = 17 * 60
        return PlannedBlock(
            startMinuteOfDay: start,
            endMinuteOfDay: start + duration,
            title: workout.type.displayName,
            sourceId: workout.id.uuidString
        )
    }

    private func fetchStudySessionLength() -> Int {
        let descriptor = FetchDescriptor<UserDailyPlanProfile>()
        let profile = (try? modelContext.fetch(descriptor))?.first
        return profile?.studySessionLengthMinutes ?? 50
    }

    private func generateStudyBlocks(
        length: Int,
        dayStart: Date,
        fixed: [FixedBlock],
        meals: [PlannedBlock],
        workout: PlannedBlock?
    ) -> [PlannedBlock] {
        // v1 heuristic: two study Pomodoros in the largest two free
        // windows between 09:00 and 21:00. Reserved a 15-min buffer
        // either side of fixed blocks so the user isn't sprinting
        // from class to a study session.
        let dayStartMin = 9 * 60
        let dayEndMin = 21 * 60
        let blocked = fixed.map { ($0.startMinuteOfDay - 15, $0.endMinuteOfDay + 15) }
            + meals.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
            + (workout.map { [($0.startMinuteOfDay, $0.endMinuteOfDay)] } ?? [])
        let merged = Self.mergeRanges(blocked)
        let free = Self.freeWindows(start: dayStartMin, end: dayEndMin, blockedRanges: merged)
        // Pick the two largest, place a session at the start of each.
        let top = free.sorted(by: { ($0.1 - $0.0) > ($1.1 - $1.0) }).prefix(2)
        return top.compactMap { (start, end) -> PlannedBlock? in
            guard end - start >= length else { return nil }
            return PlannedBlock(
                startMinuteOfDay: start,
                endMinuteOfDay: start + length,
                title: "Study (\(length) min)",
                sourceId: nil
            )
        }
    }

    private func fetchWakeBedtime() -> (Int, Int) {
        let descriptor = FetchDescriptor<UserDailyPlanProfile>()
        let profile = (try? modelContext.fetch(descriptor))?.first
        let wake = profile?.wakeTimeMinutes ?? 7 * 60
        let sleepTarget = profile?.sleepTargetHours ?? 8.0
        // Bedtime = wake - sleepTarget, snapped into the same day.
        // For wake=07:00, sleep=8h → bedtime=23:00.
        let bedtime = (wake - Int(sleepTarget * 60) + 1440) % 1440
        return (wake, bedtime)
    }

    private func deleteExistingPlans(for day: Date) {
        let descriptor = FetchDescriptor<DayPlan>(predicate: #Predicate { $0.date == day })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        for plan in existing {
            modelContext.delete(plan)
        }
    }

    // MARK: - Pure helpers

    private static func minutesOfDay(timeString: String, durationMinutes: Int) -> (Int, Int)? {
        // Accepts "HH:mm" or "HH:mm:ss".
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let start = parts[0] * 60 + parts[1]
        return (start, start + durationMinutes)
    }

    private static func mergeRanges(_ input: [(Int, Int)]) -> [(Int, Int)] {
        guard !input.isEmpty else { return [] }
        let sorted = input.sorted { $0.0 < $1.0 }
        var result: [(Int, Int)] = [sorted[0]]
        for r in sorted.dropFirst() {
            let last = result[result.count - 1]
            if r.0 <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, r.1))
            } else {
                result.append(r)
            }
        }
        return result
    }

    private static func freeWindows(start: Int, end: Int, blockedRanges: [(Int, Int)]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var cursor = start
        for r in blockedRanges {
            if r.0 > cursor {
                result.append((cursor, min(r.0, end)))
            }
            cursor = max(cursor, r.1)
            if cursor >= end { break }
        }
        if cursor < end {
            result.append((cursor, end))
        }
        return result.filter { $0.1 > $0.0 }
    }

    private static func fixedBlocksFromEvents(
        _ events: [CalendarEvent],
        dayStart: Date,
        calendarService: any CalendarServiceProtocol,
        dayDate: Date
    ) -> [FixedBlock] {
        // Resolve each non-all-day event into a FixedBlock. Kind
        // classification comes from CalendarService's existing
        // detectors (football / exam / class), defaulting to .work
        // for everything else.
        let footballDays = calendarService.detectFootballDays(
            in: DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        )
        let exams = calendarService.detectExamDates(
            in: DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        )
        let classes = calendarService.detectClassSchedule(for: dayDate)

        return events.compactMap { event -> FixedBlock? in
            if event.isAllDay { return nil }
            let startMin = Self.minuteOfDay(event.startDate, in: dayStart)
            let endMin = Self.minuteOfDay(event.endDate, in: dayStart)
            guard endMin > startMin else { return nil }

            let kind: TimeBlockKind
            if footballDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: event.startDate) }) {
                kind = .football
            } else if exams.contains(where: { Calendar.current.isDate($0.date, equalTo: event.startDate, toGranularity: .minute) }) {
                kind = .exam
            } else if classes.contains(where: { $0.startTime == event.startDate }) {
                kind = .class
            } else {
                kind = .work
            }

            return FixedBlock(
                startMinuteOfDay: startMin,
                endMinuteOfDay: endMin,
                title: event.title,
                kind: kind,
                sourceId: nil  // EKEvent.eventIdentifier not currently surfaced in CalendarEvent DTO
            )
        }
    }

    private static func minuteOfDay(_ date: Date, in dayStart: Date) -> Int {
        let secs = date.timeIntervalSince(dayStart)
        return max(0, min(1440, Int(secs / 60)))
    }
}
