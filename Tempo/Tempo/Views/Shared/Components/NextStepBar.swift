//
// NextStepBar.swift
// Tempo
//
// One line, one button: what to do next, shown where something has just
// ended (a workout summary, a meal log, a focus session, Recovery, Lockdown).
// It asks `NextStepEngine`, the same place Today's Next card asks, so the two
// can never name different things. Dismissible; shows nothing when the day is done.
//
//     NextStepBar(place: .workoutSummary)
//

import SwiftData
import SwiftUI

// MARK: - NextStepBar

struct NextStepBar: View {
    let place: NextStepPlace
    /// Runs when the button is pressed, instead of going straight to the place
    /// (a screen that must save or close first does that here, then calls `NextStepRouter`).
    var onOpen: ((NextStep) -> Void)?
    /// Pinned to a page edge (`nextStepBar(place:)`): the bar brings its own margins, so an empty one takes no room.
    var pinned = false
    /// The screen itself is the moment right after (a focus review), so the 10 minute check is skipped.
    var ignoresFreshness = false

    /// A meal or a focus session only counts as "just now" for this long.
    private static let freshFor: TimeInterval = 10 * 60

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood

    @State
    private var step: NextStep?
    @State
    private var dismissed = false

    var body: some View {
        // A concrete container hosts the loading task, so it runs while nothing is drawn.
        VStack(spacing: 0) {
            if let step, !dismissed {
                bar(step)
                    .padding(.horizontal, pinned ? Tide.edge : 0)
                    .padding(.top, pinned ? Tide.s2 : 0)
                    .transition(.opacity)
            }
        }
        .animation(Tide.snap, value: dismissed)
        .task { await load() }
        // A log or a finished session posts these; the bar is looked at again then.
        .onReceive(NotificationCenter.default.publisher(for: .tempoMealLogToast)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoSessionEnded)) { _ in
            Task { await load() }
        }
    }

    private func bar(_ step: NextStep) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        return HStack(alignment: .top, spacing: Tide.s2) {
            layout {
                Text(step.line)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if typeSize.isAccessibilitySize == false {
                    Spacer(minLength: Tide.s2)
                }
                if let title = step.buttonTitle {
                    Button(title) {
                        if let onOpen {
                            onOpen(step)
                        } else {
                            NextStepRouter.perform(step.action, appState: services.appState)
                        }
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("nextStep.action")
                }
            }
            Button {
                dismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("nextStep.dismiss")
        }
        .padding(.leading, Tide.s4)
        .padding(.vertical, Tide.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(mood.accent.opacity(0.12)), in: .rect(cornerRadius: Tide.tileRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nextStep.\(place.rawValue)")
    }

    /// The saved copy of Today's snapshot is the last thing the page drew; the
    /// engine corrects the one fact that has just changed.
    private func load() async {
        guard isFresh else {
            step = nil
            return
        }
        dismissed = false
        let saved = await Task.detached { TodayCache.shared.load() }.value
        guard let saved else {
            return
        }
        step = NextStepEngine.next(
            for: saved, hour: Calendar.current.component(.hour, from: TodayClock.now), place: place
        )
    }
}

extension NextStepBar {
    /// After a meal or a focus session the bar is for the minutes just after it.
    /// Everywhere else it sits on a screen that is itself the end of something.
    fileprivate var isFresh: Bool {
        if ignoresFreshness {
            return true
        }
        let now = TodayClock.now
        switch place {
        case .afterMeal:
            let meals = CanonicalMeals.meals(on: now, in: modelContext)
            let last = meals.compactMap(\.actualEatenAt).max()
            return last.map { now.timeIntervalSince($0) < Self.freshFor } ?? false
        case .afterFocus:
            let start = Calendar.current.startOfDay(for: now)
            let sessions = (try? modelContext.fetch(FetchDescriptor<StudySession>(
                predicate: #Predicate<StudySession> { $0.endTime != nil && $0.startTime >= start }
            ))) ?? []
            let last = sessions.compactMap(\.endTime).max()
            return last.map { now.timeIntervalSince($0) < Self.freshFor } ?? false
        case .today,
             .workoutSummary,
             .recoveryEnd,
             .lockdownDone:
            return true
        }
    }
}

extension View {
    /// Pins a "what next" bar to the top of a page, taking no room when there is nothing to say.
    func nextStepBar(place: NextStepPlace) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            NextStepBar(place: place, pinned: true)
        }
    }
}

// MARK: - NextStepRouter

/// Takes the person to what a `TodayNextAction` names.
enum NextStepRouter {
    @MainActor
    static func perform(_ action: TodayNextAction, appState: AppState) {
        switch action {
        case .workout:
            appState.activeTab = .train
        case .meal,
             .firstMeal:
            appState.activeTab = .fuel
        case .rest:
            appState.openOnToday(.recovery)
        case .focus:
            appState.openOnToday(.mind)
        case .tasks,
             .setUpTasks:
            appState.openOnToday(.lockdown)
        case .allDone:
            break
        }
    }
}
