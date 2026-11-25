//
// DayTimeline.swift
// Tempo
//
// The day as a timeline, and tomorrow as a short preview. Real data only: a
// meal appears at the time the plan set, a session when it was done, a
// calendar event at its own time. Nothing is invented to fill a gap.
//
// Pure: plain inputs in, items out. `DayTimelineLoader` below is the one
// place that reads SwiftData and the calendar to build those inputs.
//

import Foundation
import SwiftData

// MARK: - DayItem

struct DayItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case meal
        case workout
        case event
        case study
    }

    enum State: Equatable {
        case done
        /// The time passed and it was never done.
        case missed
        case skipped
        case upcoming
        case inProgress
        /// A calendar event that has ended: it happened, there is nothing to tick.
        case over
    }

    /// Where a tap goes.
    enum Target: Equatable {
        case workout
        case meal(UUID)
        case fuel
        case study
        /// Nothing to open (a calendar event).
        case none
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String?
    /// The clock time, when there is one.
    let at: Date?
    /// "Evening", "Any time": for a session that has a preferred window but no hour.
    let windowLabel: String?
    let state: State
    let target: Target
    /// Where the item sorts. Equal to `at` when there is one.
    let sortKey: Date

    var isPast: Bool {
        switch state {
        case .done,
             .missed,
             .skipped,
             .over: true
        case .upcoming,
             .inProgress: false
        }
    }
}

// MARK: - DayTimelineInput

struct DayTimelineInput {
    struct MealRow: Equatable {
        enum Status: Equatable {
            case planned
            case eaten
            case skipped
        }

        var id: UUID
        var name: String
        /// "HH:mm"
        var scheduledTime: String
        var status: Status
        var eatenAt: Date?
        var calories: Int
    }

    struct WorkoutRow: Equatable {
        enum Status: Equatable {
            case planned
            case inProgress
            case completed
            case skipped
        }

        var name: String
        var status: Status
        var startedAt: Date?
        var finishedAt: Date?
        var durationMinutes: Int?
        /// "Usual training time" from Settings, when one was chosen.
        var window: TrainingTimePreference?
    }

    struct EventRow: Equatable {
        var title: String
        var start: Date
        var end: Date
    }

    struct StudyRow: Equatable {
        var start: Date
        var minutes: Int
        var subject: String?
    }

    var now: Date
    var calendar: Calendar = .current
    /// Minutes after midnight.
    var wakeMinutes = 7 * 60
    var leisureMinutes = 19 * 60 + 30
    var bedtimeMinutes = 23 * 60
    var meals: [MealRow] = []
    var workout: WorkoutRow?
    var events: [EventRow] = []
    var study: [StudyRow] = []
}

// MARK: - DayTimeline

enum DayTimeline {
    /// A planned meal is "due" for this long after its time, then it counts as missed.
    static let mealGrace: TimeInterval = 90 * 60

    static func items(_ input: DayTimelineInput) -> [DayItem] {
        var items: [DayItem] = []
        items += input.meals.map { meal(for: $0, input) }
        if let workout = input.workout {
            items.append(session(for: workout, input))
        }
        items += input.events.map { event(for: $0, input) }
        items += input.study.map { study(for: $0, input) }
        return items.sorted { lhs, rhs in
            lhs.sortKey == rhs.sortKey ? lhs.id < rhs.id : lhs.sortKey < rhs.sortKey
        }
    }

    /// The items still ahead (or under way), at most `limit`, skipping the ones in `excluding`.
    static func upcoming(_ items: [DayItem], limit: Int, excluding: Set<String> = []) -> [DayItem] {
        Array(items.filter { !$0.isPast && !excluding.contains($0.id) }.prefix(limit))
    }

    /// After the schedule's wind-down (leisure) start: the evening.
    static func isEvening(now: Date, leisureMinutes: Int, calendar: Calendar = .current) -> Bool {
        minutes(of: now, calendar: calendar) >= leisureMinutes
    }

    // MARK: Rows

    private static func meal(for row: DayTimelineInput.MealRow, _ input: DayTimelineInput) -> DayItem {
        let scheduled = time(row.scheduledTime, on: input.now, calendar: input.calendar)
        let eaten = row.status == .eaten ? (row.eatenAt ?? scheduled) : nil
        let at = eaten ?? scheduled ?? input.now
        let state: DayItem.State = switch row.status {
        case .eaten: .done
        case .skipped: .skipped
        case .planned: input.now >= at.addingTimeInterval(mealGrace) ? .missed : .upcoming
        }
        return DayItem(
            id: "meal.\(row.id.uuidString)",
            kind: .meal,
            title: row.name,
            detail: row.calories > 0 ? String(localized: "\(row.calories.formatted()) kcal") : nil,
            at: at,
            windowLabel: nil,
            state: state,
            target: .meal(row.id),
            sortKey: at
        )
    }

    private static func session(for row: DayTimelineInput.WorkoutRow, _ input: DayTimelineInput) -> DayItem {
        let calendar = input.calendar
        let dayStart = calendar.startOfDay(for: input.now)
        let done = row.finishedAt ?? row.startedAt
        let window = row.window.flatMap { $0 == .anyFree ? nil : $0 }
        let at: Date? = switch row.status {
        case .completed: done
        case .inProgress: row.startedAt
        case .planned,
             .skipped: nil
        }
        // No hour for a planned session: it sorts by the part of the day the
        // person said they train in, and "any time" comes before the rest.
        let sortKey = at ?? windowStart(window, input: input, dayStart: dayStart)
        let state: DayItem.State = switch row.status {
        case .completed: .done
        case .inProgress: .inProgress
        case .skipped: .skipped
        case .planned: pastBedtime(input, calendar: calendar) ? .missed : .upcoming
        }
        let detail: String? = switch row.status {
        case .completed: row.durationMinutes.map { String(localized: "\($0) min") }
        default: nil
        }
        return DayItem(
            id: "workout",
            kind: .workout,
            title: row.name,
            detail: detail,
            at: at,
            windowLabel: at == nil ? (window?.label ?? String(localized: "Any time")) : nil,
            state: state,
            target: .workout,
            sortKey: sortKey
        )
    }

    private static func windowStart(
        _ window: TrainingTimePreference?, input: DayTimelineInput, dayStart: Date
    ) -> Date {
        let minutes = switch window {
        case .morning: input.wakeMinutes + 60
        case .midday: 12 * 60
        case .evening: 18 * 60
        case .anyFree,
             nil: input.wakeMinutes
        }
        return input.calendar.date(byAdding: .minute, value: minutes, to: dayStart) ?? dayStart
    }

    private static func event(for row: DayTimelineInput.EventRow, _ input: DayTimelineInput) -> DayItem {
        let state: DayItem.State = if input.now >= row.end {
            .over
        } else if input.now >= row.start {
            .inProgress
        } else {
            .upcoming
        }
        return DayItem(
            id: "event.\(row.title).\(Int(row.start.timeIntervalSince1970))",
            kind: .event,
            title: row.title,
            detail: nil,
            at: row.start,
            windowLabel: nil,
            state: state,
            target: .none,
            sortKey: row.start
        )
    }

    private static func study(for row: DayTimelineInput.StudyRow, _ input: DayTimelineInput) -> DayItem {
        DayItem(
            id: "study.\(Int(row.start.timeIntervalSince1970))",
            kind: .study,
            title: row.subject.map { String(localized: "Study, \($0)") } ?? String(localized: "Study"),
            detail: String(localized: "\(row.minutes) min"),
            at: row.start,
            windowLabel: nil,
            state: .done,
            target: .study,
            sortKey: row.start
        )
    }

    // MARK: Clock helpers

    /// True once the person's bedtime has passed. A bedtime after midnight
    /// (00:30, stored as 30) is earlier on the clock than the wake time, so the
    /// day runs on past midnight and only the hours from bedtime to wake count.
    static func pastBedtime(_ input: DayTimelineInput, calendar: Calendar) -> Bool {
        let now = minutes(of: input.now, calendar: calendar)
        if input.bedtimeMinutes >= input.wakeMinutes {
            return now >= input.bedtimeMinutes
        }
        return now >= input.bedtimeMinutes && now < input.wakeMinutes
    }

    static func minutes(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// "HH:mm" on the day of `day`.
    static func time(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0 ..< 24).contains(hour), (0 ..< 60).contains(minute)
        else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

// MARK: - TomorrowPreview

/// What tomorrow starts with, in four lines. Any line without real data is nil.
struct TomorrowPreview: Equatable {
    struct Meal: Equatable {
        var name: String
        var time: String
    }

    /// "Push", or nil when the plan for tomorrow is not known yet.
    var sessionName: String?
    var isRestDay: Bool
    var firstMeal: Meal?
    var firstTask: String?
    /// "07:00"
    var wakeTime: String

    /// A preview with nothing real to say is not shown.
    var hasContent: Bool {
        sessionName != nil || isRestDay || firstMeal != nil || firstTask != nil
    }

    /// "07:00" from minutes after midnight.
    static func clock(minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

// MARK: - DayTimelineLoader

/// Reads the app's real data into a `DayTimelineInput` / `TomorrowPreview`.
@MainActor
enum DayTimelineLoader {
    static func input(
        now: Date,
        calendar: Calendar = .current,
        events: [CalendarEvent],
        in context: ModelContext
    ) -> DayTimelineInput {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        var input = DayTimelineInput(now: now, calendar: calendar)
        if let settings {
            input.wakeMinutes = settings.wakeTimeMinutes
            input.leisureMinutes = settings.leisureTimeMinutes
            input.bedtimeMinutes = settings.bedtimeTargetMinutes
        }

        input.meals = CanonicalMeals.meals(on: now, in: context)
            .filter { !EatenMealRecorder.isSupplementDose($0) }
            .sorted { $0.mealNumber < $1.mealNumber }
            .map { meal in
                let status: DayTimelineInput.MealRow.Status = switch meal.status {
                case .eaten,
                     .modified: .eaten
                case .skipped: .skipped
                case .planned: .planned
                }
                return DayTimelineInput.MealRow(
                    id: meal.id,
                    name: meal.displayMealName,
                    scheduledTime: meal.scheduledTime,
                    status: status,
                    eatenAt: meal.actualEatenAt,
                    calories: Int(meal.totalCalories.rounded())
                )
            }

        if let plan = DashboardViewModel.todayWorkoutPlan(in: context), plan.type != .rest {
            let status: DayTimelineInput.WorkoutRow.Status = switch plan.status {
            case .completed: .completed
            case .inProgress: .inProgress
            case .skipped: .skipped
            case .planned: .planned
            }
            input.workout = DayTimelineInput.WorkoutRow(
                name: plan.type.displayName,
                status: status,
                startedAt: plan.startedAt,
                finishedAt: plan.finishedAt,
                durationMinutes: plan.actualDurationMinutes,
                window: UserDailyPlanProfile.current(in: context)?.trainingTimePreference
            )
        }

        input.events = events
            .filter { !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: now) }
            .map { DayTimelineInput.EventRow(title: $0.title, start: $0.startDate, end: $0.endDate) }

        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>(
            predicate: #Predicate<StudySession> { $0.startTime >= dayStart && $0.startTime < dayEnd }
        ))) ?? []
        input.study = sessions
            .filter { !$0.isInProgress && $0.durationMinutes > 0 }
            .map { DayTimelineInput.StudyRow(start: $0.startTime, minutes: $0.durationMinutes, subject: $0.subject) }
        return input
    }

    /// Tomorrow's four lines. `tomorrowSession` is the session name the Train
    /// week plan holds for tomorrow (nil when the plan is not loaded), with
    /// `isRest` when that plan is a rest day.
    static func tomorrow(
        now: Date,
        calendar: Calendar = .current,
        tomorrowSession: String?,
        isRest: Bool,
        in context: ModelContext
    ) -> TomorrowPreview {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first

        let firstMeal = CanonicalMeals.meals(on: tomorrow, in: context)
            .filter { !EatenMealRecorder.isSupplementDose($0) && !$0.isUnplannedLog }
            .min { $0.scheduledTime < $1.scheduledTime }
            .map { TomorrowPreview.Meal(name: $0.displayMealName, time: $0.scheduledTime) }

        let weekday = calendar.component(.weekday, from: tomorrow)
        let tasks = (try? context.fetch(FetchDescriptor<NonNegotiable>(
            predicate: #Predicate<NonNegotiable> { $0.isActive == true },
            sortBy: [SortDescriptor(\.order)]
        ))) ?? []
        let firstTask = tasks.first { $0.activeDays.isActive(on: weekday) }?.name

        return TomorrowPreview(
            sessionName: isRest ? nil : tomorrowSession,
            isRestDay: isRest,
            firstMeal: firstMeal,
            firstTask: firstTask,
            wakeTime: TomorrowPreview.clock(minutes: settings?.wakeTimeMinutes ?? 7 * 60)
        )
    }
}
