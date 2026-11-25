//
// TodayExtras.swift
// Tempo
//
// The things Today shows beyond its core cards: what is still ahead in the
// day, tomorrow's preview, the week in review, and the quiet links under the
// page. `TodayDayModel` reads their data; `TodayPromptPlanner` decides which
// single card asks for attention.
//

import SwiftData
import SwiftUI

// MARK: - TodayDayModel

/// The day's items, tomorrow's preview and the week in review, read from the
/// app's real data. Reloaded when Today's snapshot changes.
@Observable
@MainActor
final class TodayDayModel {
    private(set) var items: [DayItem] = []
    private(set) var leisureMinutes = 19 * 60 + 30
    private(set) var tomorrow: TomorrowPreview?
    private(set) var week: WeekReview?
    /// The day the week was last read for, so it is not rebuilt on every refresh.
    private var weekFor: Date?

    var hasWeekData: Bool {
        week.map { !$0.thisWeek.isEmpty } ?? false
    }

    func reload(services: ServiceContainer, context: ModelContext, now: Date) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // Without calendar access this returns nothing; it never asks for it.
        let range = DateInterval(start: dayStart, end: dayEnd)
        let events = (try? await services.calendar.fetchEvents(for: range)) ?? []
        let input = DayTimelineLoader.input(now: now, calendar: calendar, events: events, in: context)
        items = DayTimeline.items(input)
        leisureMinutes = input.leisureMinutes

        if DayTimeline.isEvening(now: now, leisureMinutes: leisureMinutes, calendar: calendar) {
            tomorrow = tomorrowPreview(services: services, context: context, now: now, calendar: calendar)
        } else {
            tomorrow = nil
        }

        // The week changes slowly: once a day is enough.
        let reference = calendar.startOfDay(for: WeekReviewBuilder.reference(for: now, calendar: calendar))
        if weekFor != reference || week == nil {
            week = WeekReviewLoader.review(now: reference, calendar: calendar, in: context)
            weekFor = reference
        }
    }

    /// Forget the saved week so the next reload reads it again (a workout ended, a meal was logged).
    func invalidateWeek() {
        weekFor = nil
    }

    private func tomorrowPreview(
        services: ServiceContainer, context: ModelContext, now: Date, calendar: Calendar
    ) -> TomorrowPreview {
        let date = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let schedule = TrainingScheduleProvider.weekSchedule(
            containing: date,
            trainingEngine: services.trainingEngine,
            whoop: services.whoop,
            healthKit: services.healthKit,
            modelContext: context
        )
        let day = schedule.first { calendar.isDate($0.date, inSameDayAs: date) }
        return DayTimelineLoader.tomorrow(
            now: now,
            calendar: calendar,
            tomorrowSession: day.map(\.mainType.displayName),
            isRest: day?.mainType == .rest,
            in: context
        )
    }
}

// MARK: - DayItemRow

/// One line of the day: what, when and how it went. Used by the "later today"
/// card and by the full-day page.
struct DayItemRow: View {
    let item: DayItem
    /// Dim rows that are already behind.
    var dimsPast = true

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(tint)
                .frame(minWidth: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tide.s2)
            if item.target != .none {
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Tide.hit + Tide.s2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, caption, stateWord].compactMap(\.self).joined(separator: ", "))
    }

    /// "12:30 · 650 kcal", or the part of the day for a session with no hour.
    private var caption: String? {
        let when = item.at.map { $0.formatted(date: .omitted, time: .shortened) } ?? item.windowLabel
        let parts = [when, item.detail, stateWord].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Said only when it is worth saying: what was missed or skipped, what is under way.
    private var stateWord: String? {
        switch item.state {
        case .missed: "Missed"
        case .skipped: "Skipped"
        case .inProgress: "Under way"
        case .done,
             .upcoming,
             .over: nil
        }
    }

    private var icon: String {
        switch item.state {
        case .done,
             .over: "checkmark.circle.fill"
        case .missed: "exclamationmark.circle.fill"
        case .skipped: "minus.circle"
        case .upcoming,
             .inProgress:
            switch item.kind {
            case .meal: "fork.knife"
            case .workout: "dumbbell.fill"
            case .event: "calendar"
            case .study: "book.fill"
            }
        }
    }

    private var tint: Color {
        switch item.state {
        case .missed: TideTone.amber
        case .inProgress: mood.accent
        case .upcoming: Tide.text
        case .done,
             .skipped,
             .over: Tide.text2
        }
    }

    private var titleColor: Color {
        dimsPast && item.isPast ? Tide.text2 : Tide.text
    }
}

// MARK: - TodayLaterCard

/// What is still ahead today, the next two or three items. The full day is one tap away.
struct TodayLaterCard: View {
    let items: [DayItem]
    let onOpen: (DayItem) -> Void
    let onFullDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: "Later today")
            VStack(spacing: 0) {
                ForEach(items) { item in
                    if item.target == .none {
                        DayItemRow(item: item)
                            .accessibilityIdentifier("today.later.\(item.id)")
                    } else {
                        Button { onOpen(item) } label: {
                            DayItemRow(item: item)
                        }
                        .buttonStyle(TodayPressStyle())
                        .accessibilityIdentifier("today.later.\(item.id)")
                    }
                }
            }
            Button(action: onFullDay) {
                Label("Full day", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.tideGlass)
            .accessibilityIdentifier("today.later.fullDay")
        }
        .tideCard()
        .accessibilityIdentifier("today.later")
    }
}

// MARK: - DayTimelineView

/// The whole day, in order. What is done, what was missed, what is still ahead.
struct DayTimelineView: View {
    let model: TodayDayModel
    let reload: () async -> Void
    let onOpen: (DayItem) -> Void

    var body: some View {
        TideScrollPage(spacing: Tide.s4, spacer: Tide.s2) {
            if model.items.isEmpty {
                TideEmptyPanel(
                    systemImage: "calendar",
                    title: "Nothing on the day yet",
                    message: "Meals, your session, study and calendar events show here as they are planned or done."
                )
                .accessibilityIdentifier("day.empty")
            } else {
                let past = model.items.filter(\.isPast)
                let ahead = model.items.filter { !$0.isPast }
                if !past.isEmpty {
                    section("So far", past)
                }
                if !ahead.isEmpty {
                    section("Still ahead", ahead)
                }
            }
        }
        .navigationTitle("Your day")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .accessibilityIdentifier("day.page")
    }

    private func section(_ title: String, _ items: [DayItem]) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: title, trailing: "\(items.count)")
            VStack(spacing: 0) {
                ForEach(items) { item in
                    if item.target == .none {
                        DayItemRow(item: item)
                            .accessibilityIdentifier("day.row.\(item.id)")
                    } else {
                        Button { onOpen(item) } label: {
                            DayItemRow(item: item)
                        }
                        .buttonStyle(TodayPressStyle())
                        .accessibilityIdentifier("day.row.\(item.id)")
                    }
                }
            }
        }
        .tideCard()
    }
}

// MARK: - TodayTomorrowCard

/// The evening preview: what tomorrow starts with. Lines without real data are left out.
struct TodayTomorrowCard: View {
    let preview: TomorrowPreview

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Tomorrow", trailing: "Wake \(preview.wakeTime)")
            VStack(alignment: .leading, spacing: Tide.s3) {
                if preview.isRestDay {
                    line("bed.double.fill", "Rest day", "No session planned")
                } else if let session = preview.sessionName {
                    line("dumbbell.fill", session, "Session")
                }
                if let meal = preview.firstMeal {
                    line("fork.knife", meal.name, "First meal, \(meal.time)")
                }
                if let task = preview.firstTask {
                    line("checklist", task, "First task")
                }
            }
        }
        .tideCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.tomorrow")
    }

    private func line(_ icon: String, _ title: String, _ caption: String) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(mood.accent)
                .frame(minWidth: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TodayWeekReviewCard

/// The prominent week-in-review card: Sunday evening and Monday morning.
struct TodayWeekReviewCard: View {
    let review: WeekReview
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Week in review", trailing: WeekReviewFormat.range(of: review))
                Text(review.headline)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Tide.s1) {
                    Text("See how it went")
                        .font(Tide.bodyStrong)
                    Image(systemName: "chevron.right")
                        .font(Tide.label)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Tide.text2)
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TodayPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.weekReview")
    }
}

// MARK: - WeekReviewFormat

enum WeekReviewFormat {
    /// "16 to 22 Nov".
    static func range(of review: WeekReview, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: review.weekStart) ?? review.weekStart
        let day = review.weekStart.formatted(.dateTime.day())
        let last = end.formatted(.dateTime.day().month(.abbreviated))
        return "\(day) to \(last)"
    }
}

// MARK: - WeekReviewView

/// One page for the week: training, food, recovery, daily tasks and study, each with
/// the real number, last week's next to it, and one plain sentence.
struct WeekReviewView: View {
    let model: TodayDayModel
    let reload: () async -> Void

    var body: some View {
        TideScrollPage(spacing: Tide.s4, spacer: Tide.s2) {
            if let review = model.week, !review.thisWeek.isEmpty {
                // TODO(share): the "Share this week" action goes here:
                // ShareCard.present(.week(review)) once the share cards lane lands its `.week` card.
                Text(WeekReviewFormat.range(of: review))
                    .tideLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                area(
                    "Training", icon: "dumbbell.fill", sentence: review.training,
                    value: "\(review.thisWeek.sessions)", unit: review.thisWeek.sessions == 1 ? "session" : "sessions",
                    last: "\(review.lastWeek.sessions)", id: "training"
                )
                area(
                    "Food", icon: "fork.knife", sentence: review.food,
                    value: review.thisWeek.avgKcal.map { $0.formatted() } ?? "none", unit: "kcal a day",
                    last: review.lastWeek.avgKcal.map { $0.formatted() }, id: "food"
                )
                area(
                    "Recovery", icon: "heart.fill", sentence: review.recovery,
                    value: review.thisWeek.avgRecovery.map { "\($0)%" } ?? "none", unit: "average",
                    last: review.lastWeek.avgRecovery.map { "\($0)%" }, id: "recovery"
                )
                area(
                    "Tasks and study", icon: "checklist", sentence: review.discipline,
                    value: review.thisWeek.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "none",
                    unit: "tasks done",
                    last: review.lastWeek.completionRate.map { "\(Int(($0 * 100).rounded()))%" }, id: "discipline"
                )
            } else {
                TideEmptyPanel(
                    systemImage: "chart.bar.fill",
                    title: "Nothing to review yet",
                    message: "Log a session, a meal or your tasks and the week fills in here."
                )
                .accessibilityIdentifier("weekReview.empty")
            }
        }
        .navigationTitle("Week in review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .accessibilityIdentifier("weekReview.page")
    }

    private func area(
        _ title: String, icon: String, sentence: String, value: String, unit: String, last: String?, id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Label(title, systemImage: icon)
                .tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                TideNumber(value, unit: unit, size: Tide.numeralM, relativeTo: .title)
                Spacer(minLength: Tide.s2)
                if let last {
                    Text("Last week \(last)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            Text(sentence)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weekReview.\(id)")
    }
}

// MARK: - TodayQuietLinks

/// The links at the bottom of Today: what is not already a card above.
struct TodayQuietLinks: View {
    struct Link: Identifiable {
        let id: String
        let title: String
        let icon: String
        let action: () -> Void
    }

    let links: [Link]

    var body: some View {
        if !links.isEmpty {
            VStack(spacing: 0) {
                ForEach(links) { link in
                    Button(action: link.action) {
                        HStack(spacing: Tide.s3) {
                            Image(systemName: link.icon)
                                .font(Tide.bodyStrong)
                                .frame(minWidth: Tide.icon, alignment: .leading)
                                .accessibilityHidden(true)
                            Text(link.title)
                                .font(Tide.caption)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Tide.s2)
                            Image(systemName: "chevron.right")
                                .font(Tide.label)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Tide.text2)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(TodayPressStyle())
                    .accessibilityIdentifier("today.link.\(link.id)")
                }
            }
            .padding(.horizontal, Tide.s2)
        }
    }
}
