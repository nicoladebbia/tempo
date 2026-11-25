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

    var hasWeekData: Bool {
        week.map { !$0.thisWeek.isEmpty } ?? false
    }

    func reload(services: ServiceContainer, context: ModelContext, now: Date) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // Without calendar access this returns nothing; it never asks for it.
        let range = DateInterval(start: dayStart, end: dayEnd)
        let events = await (try? services.calendar.fetchEvents(for: range)) ?? []
        let input = DayTimelineLoader.input(now: now, calendar: calendar, events: events, in: context)
        items = DayTimeline.items(input)
        leisureMinutes = input.leisureMinutes

        if DayTimeline.isEvening(now: now, leisureMinutes: leisureMinutes, calendar: calendar) {
            tomorrow = tomorrowPreview(services: services, context: context, now: now, calendar: calendar)
        } else {
            tomorrow = nil
        }

        // Read again on every reload: the card shows on Sunday evening and must
        // count that day's meals, tasks and study, which land after an earlier load.
        let reference = calendar.startOfDay(for: WeekReviewBuilder.reference(for: now, calendar: calendar))
        week = WeekReviewLoader.review(now: reference, calendar: calendar, in: context)
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

// MARK: - TodayRowIcon

/// The icon at the start of a row. Every row gives it the same width, growing with
/// the text, so the words beside it line up whatever the symbol.
struct TodayRowIcon: View {
    let systemName: String
    /// nil is the quiet secondary text colour.
    let tint: Color?
    var font: Font = Tide.headline

    @ScaledMetric(relativeTo: .headline)
    private var width = Tide.icon

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(tint ?? Tide.text2)
            .frame(width: width, alignment: .leading)
            .accessibilityHidden(true)
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
            TodayRowIcon(systemName: icon, tint: tint)
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
        case .missed: String(localized: "Missed")
        case .skipped: String(localized: "Skipped")
        case .inProgress: String(localized: "Under way")
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
            TideSectionLabel(title: String(localized: "Later today"))
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

    @State
    private var explainer: Explainer?

    var body: some View {
        TideScrollPage(spacing: Tide.s4, spacer: Tide.s2) {
            if model.items.isEmpty {
                TideEmptyPanel(
                    systemImage: "calendar",
                    title: String(localized: "Nothing on the day yet"),
                    message: String(localized: "Meals, your session, study and calendar events show here as they are planned or done.")
                )
                .accessibilityIdentifier("day.empty")
            } else {
                let past = model.items.filter(\.isPast)
                let ahead = model.items.filter { !$0.isPast }
                if !past.isEmpty {
                    section(String(localized: "So far"), past)
                }
                if !ahead.isEmpty {
                    section(String(localized: "Still ahead"), ahead)
                }
            }
        }
        .navigationTitle("Your day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    explainer = Explainer.dayOrder
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How your day is ordered")
                .accessibilityIdentifier("day.info")
            }
        }
        .explainerSheet($explainer)
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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s2))
        VStack(alignment: .leading, spacing: Tide.s3) {
            layout {
                TideSectionLabel(title: String(localized: "Tomorrow"))
                // The wake time is the one setting-based number here: tap it to see where it comes from.
                Label("Wake \(preview.wakeTime)", systemImage: "info.circle")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                    .explains(Explainer.tomorrowWake.showing(preview.wakeTime))
                    .accessibilityIdentifier("today.tomorrow.wake")
            }
            VStack(alignment: .leading, spacing: Tide.s3) {
                if preview.isRestDay {
                    line("bed.double.fill", String(localized: "Rest day"), String(localized: "No session planned"))
                } else if let session = preview.sessionName {
                    line("dumbbell.fill", session, String(localized: "Session"))
                }
                if let meal = preview.firstMeal {
                    line("fork.knife", meal.name, String(localized: "First meal, \(meal.time)"))
                }
                if let task = preview.firstTask {
                    line("checklist", task, String(localized: "First task"))
                }
            }
        }
        .tideCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.tomorrow")
    }

    private func line(_ icon: String, _ title: String, _ caption: String) -> some View {
        HStack(spacing: Tide.s3) {
            TodayRowIcon(systemName: icon, tint: mood.accent)
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
                TideSectionLabel(title: String(localized: "Week in review"), trailing: WeekReviewFormat.range(of: review))
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
    /// "Nov 16 – 22", in the person's own format.
    static func range(of review: WeekReview, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: review.weekStart) ?? review.weekStart
        // Half-open, so the end is a moment later than the Sunday it names.
        return (review.weekStart ..< end.addingTimeInterval(60)).formatted(.interval.month(.abbreviated).day())
    }
}

// MARK: - WeekReviewView

/// One page for the week: training, food, recovery, daily tasks and study, each with
/// the real number, last week's next to it, and one plain sentence.
struct WeekReviewView: View {
    let model: TodayDayModel
    let reload: () async -> Void

    @Environment(\.modelContext)
    private var modelContext

    private var hasReview: Bool {
        model.week.map { !$0.thisWeek.isEmpty } ?? false
    }

    var body: some View {
        // The tip only makes sense when there are numbers to tap: on the empty page it
        // would be spent (it shows once) before it could help.
        Group {
            if hasReview {
                page.firstTip("today.weekReview", "Tap any number to see how it is worked out.", systemImage: "chart.bar.fill")
            } else {
                page
            }
        }
        .task { await reload() }
    }

    private var page: some View {
        TideScrollPage(spacing: Tide.s4, spacer: Tide.s2) {
            if let review = model.week, !review.thisWeek.isEmpty {
                Text(WeekReviewFormat.range(of: review))
                    .tideLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                area(
                    String(localized: "Training"), icon: "dumbbell.fill", sentence: review.training,
                    value: "\(review.thisWeek.sessions)", unit: review.thisWeek.sessions == 1 ? String(localized: "session") : String(localized: "sessions"),
                    last: "\(review.lastWeek.sessions)", id: "training", explainer: Explainer.weekSessions
                )
                area(
                    String(localized: "Food"), icon: "fork.knife", sentence: review.food,
                    value: review.thisWeek.avgKcal.map { $0.formatted() } ?? "none", unit: String(localized: "kcal a day"),
                    last: review.lastWeek.avgKcal.map { $0.formatted() }, id: "food", explainer: Explainer.weekCalories
                )
                area(
                    String(localized: "Recovery"), icon: "heart.fill", sentence: review.recovery,
                    value: review.thisWeek.avgRecovery.map { "\($0)%" } ?? "none", unit: String(localized: "average"),
                    last: review.lastWeek.avgRecovery.map { "\($0)%" }, id: "recovery", explainer: Explainer.weekRecovery
                )
                area(
                    String(localized: "Tasks and study"), icon: "checklist", sentence: review.discipline,
                    value: review.thisWeek.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "none",
                    unit: String(localized: "tasks done"),
                    last: review.lastWeek.completionRate.map { "\(Int(($0 * 100).rounded()))%" }, id: "discipline",
                    explainer: Explainer.weekTasks
                )
                Button {
                    ShareCard.present(WeekShare.card(
                        for: review, xp: WeekShare.xp(in: modelContext, weekStart: review.weekStart)
                    ))
                } label: {
                    Label("Share this week", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("weekReview.share")
            } else {
                TideEmptyPanel(
                    systemImage: "chart.bar.fill",
                    title: String(localized: "Nothing to review yet"),
                    message: String(localized: "Log a session, a meal or your tasks and the week fills in here.")
                )
                .accessibilityIdentifier("weekReview.empty")
            }
        }
        .navigationTitle("Week in review")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("weekReview.page")
    }

    private func area(
        _ title: String, icon: String, sentence: String, value: String, unit: String, last: String?, id: String,
        explainer: Explainer
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Label(title, systemImage: icon)
                .tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                // The number explains itself: the card is not a link, so a tap here is free.
                TideNumber(value == "none" ? String(localized: "none") : value, unit: unit, size: Tide.numeralM, relativeTo: .title)
                    .frame(minHeight: Tide.hit, alignment: .leading)
                    .explains(explainer.showing(value == "none" ? nil : "\(value) \(unit)"))
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
        .accessibilityElement(children: .contain)
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
                            TodayRowIcon(systemName: link.icon, tint: nil, font: Tide.bodyStrong)
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
