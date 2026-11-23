//
// TodaySections.swift
// Tempo
//
// The pieces of the Today page. Each one draws from a `TodaySnapshot` and
// reports taps through `TodayActions`; none of them loads anything.
//

import SwiftUI

// MARK: - TodayActions

struct TodayActions {
    var open: (TodayRoute) -> Void = { _ in }
    var openTab: (AppTab) -> Void = { _ in }
    var openScore: () -> Void = {}
    var startWorkout: () -> Void = {}
    var openMeal: (TodaySnapshot.Meal) -> Void = { _ in }
    var logMeal: () -> Void = {}
    var startFocus: () -> Void = {}
    var setUpTasks: () -> Void = {}
    var connectWearable: () -> Void = {}
    var allowHealth: () -> Void = {}
}

// MARK: - TodayHeader

struct TodayHeader: View {
    let snapshot: TodaySnapshot
    let dateLine: String
    var weather: (symbol: String, temperature: String)?

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                HStack(spacing: Tide.s2) {
                    Text(dateLine).tideLabel()
                    if let weather {
                        Label(weather.temperature, systemImage: weather.symbol)
                            .labelStyle(.titleAndIcon)
                            .tideLabel()
                            .accessibilityLabel("Weather \(weather.temperature)")
                    }
                }
                TimelineView(.everyMinute) { context in
                    Text(TodayGreeting.text(
                        hour: Calendar.current.component(.hour, from: context.date),
                        name: snapshot.firstName
                    ))
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tide.s2)
            if snapshot.streakDays > 0 {
                HStack(spacing: Tide.s1) {
                    Image(systemName: "flame.fill").font(Tide.bodyStrong).foregroundStyle(Tide.streak)
                    TideNumber("\(snapshot.streakDays)", size: Tide.numeralS, relativeTo: .headline)
                }
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .glassEffect(.regular.tint(Tide.ink.opacity(0.3)), in: .capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snapshot.streakDays) day streak")
                .accessibilityIdentifier("today.streak")
            }
        }
    }
}

// MARK: - TodayHero

struct TodayHero: View {
    let snapshot: TodaySnapshot
    let actions: TodayActions

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s5))
        layout {
            Button(action: actions.openScore) {
                TideDial(score: snapshot.score, caption: "Day score", diameter: Tide.dialHero)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot.score.map { "Day score \($0) of 100" } ?? "Day score, not enough data yet")
            .accessibilityHint("Shows what the score is made of")
            .accessibilityIdentifier("today.score")

            VStack(alignment: .leading, spacing: Tide.s2) {
                Text(snapshot.score == nil ? "Day one" : mood.word)
                    .font(Tide.title2)
                    .foregroundStyle(mood.accent)
                Text(TodayStatus.line(for: snapshot))
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.status")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, Tide.s2)
    }
}

// MARK: - TodayNextCard

struct TodayNextCard: View {
    let action: TodayNextAction
    let snapshot: TodaySnapshot
    let actions: TodayActions

    @State
    private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Next up", trailing: trailing)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(title)
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let button {
                Button {
                    taps += 1
                    run()
                } label: {
                    Label(button.title, systemImage: button.icon)
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("today.next.action")
            }
        }
        .tideCard()
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityIdentifier("today.next")
    }

    private var trailing: String? {
        switch action {
        case let .meal(meal): meal.time
        case .workout:
            snapshot.workout.durationMinutes.map { "\($0) min" }
        default: nil
        }
    }

    private var title: String {
        switch action {
        case let .workout(name, _): name
        case let .meal(meal): meal.name
        case .rest: "Rest day"
        case .focus: "Study block"
        case let .tasks(left): left == 1 ? "1 task left" : "\(left) tasks left"
        case .setUpTasks: "Set your daily tasks"
        case .allDone: "Day complete"
        }
    }

    private var detail: String {
        switch action {
        case let .workout(_, resume):
            resume ? "You started this session. Pick it up where you left off." : "Today's session is ready."
        case let .meal(meal):
            "\(meal.calories.formatted()) kcal · \(meal.protein) g protein"
        case .rest:
            "No session today. Recovery sets up tomorrow."
        case let .focus(left):
            "\(left) min left to reach today's study target."
        case .tasks:
            "Finish them to unlock the day."
        case .setUpTasks:
            "Pick the few things you do every day, no matter what."
        case .allDone:
            "Session, tasks and study are all done. Nothing else is due."
        }
    }

    private var button: (title: String, icon: String)? {
        switch action {
        case let .workout(_, resume): (resume ? "Resume session" : "Start session", "play.fill")
        case .meal: ("Open meal", "fork.knife")
        case .rest: ("Open recovery", "heart.fill")
        case .focus: ("Start focus timer", "timer")
        case .tasks: ("Open tasks", "checklist")
        case .setUpTasks: ("Choose tasks", "plus")
        case .allDone: nil
        }
    }

    private func run() {
        switch action {
        case .workout: actions.startWorkout()
        case let .meal(meal): actions.openMeal(meal)
        case .rest: actions.open(.recovery)
        case .focus: actions.startFocus()
        case .tasks: actions.open(.lockdown)
        case .setUpTasks: actions.setUpTasks()
        case .allDone: break
        }
    }
}

// MARK: - TodayBodyRow

struct TodayBodyRow: View {
    let snapshot: TodaySnapshot
    let actions: TodayActions
    let namespace: Namespace.ID

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        layout {
            recovery
            sleep
        }
    }

    @ViewBuilder
    private var recovery: some View {
        let data = snapshot.recovery
        if data.score == nil, !data.hasSource {
            TodayTile(label: "Recovery", identifier: "today.shortcut.recovery", action: actions.connectWearable) {
                Text("No reading yet").font(Tide.headline).foregroundStyle(Tide.text)
                Text("Connect Whoop to see it.").font(Tide.caption).foregroundStyle(Tide.text2)
            }
        } else {
            TodayTile(label: "Recovery", identifier: "today.shortcut.recovery", action: { actions.open(.recovery) }) {
                if let score = data.score {
                    TideNumber("\(score)", unit: "%", size: Tide.numeralM)
                    TideLevelBar(progress: Double(score) / 100, height: Tide.barSlim)
                } else {
                    Text("Waiting for today").font(Tide.headline).foregroundStyle(Tide.text)
                }
                Text(vitals(data)).font(Tide.caption).foregroundStyle(Tide.text2)
            }
            .matchedTransitionSource(id: TodayRoute.recovery, in: namespace)
        }
    }

    private var sleep: some View {
        let data = snapshot.recovery
        return TodayTile(label: "Sleep", identifier: "today.sleep", action: { actions.open(.body) }) {
            if let hours = data.sleepHours {
                let whole = Int(hours), minutes = Int(((hours - Double(whole)) * 60).rounded())
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    TideNumber("\(whole)", unit: "h", size: Tide.numeralM)
                    TideNumber(String(format: "%02d", minutes), unit: "m", size: Tide.numeralM)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(whole) hours \(minutes) minutes")
                if let performance = data.sleepPerformance {
                    TideLevelBar(progress: Double(performance) / 100, color: Tide.fat, height: Tide.barSlim)
                }
                Text(data.sleepPerformance.map { "\($0)% of what you needed" } ?? "Last night")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
            } else {
                Text("No sleep data").font(Tide.headline).foregroundStyle(Tide.text)
                Text("Wear your tracker tonight.").font(Tide.caption).foregroundStyle(Tide.text2)
            }
        }
        .matchedTransitionSource(id: TodayRoute.body, in: namespace)
    }

    private func vitals(_ data: TodaySnapshot.Recovery) -> String {
        let parts = [data.hrv.map { "HRV \($0)" }, data.restingHR.map { "RHR \($0)" }].compactMap(\.self)
        return parts.isEmpty ? "Open recovery" : parts.joined(separator: " · ")
    }
}

// MARK: - TodayTile

/// A half-width glass tile that is one button.
struct TodayTile<Content: View>: View {
    let label: String
    let identifier: String
    let action: () -> Void
    @ViewBuilder
    var content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack {
                    Text(label).tideLabel()
                    Spacer(minLength: Tide.s1)
                    Image(systemName: "chevron.right").font(Tide.label).foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
                content
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit * 2, alignment: .topLeading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TodayPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - TodayPressStyle

/// Cards that open something dip slightly under the finger.
struct TodayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - TodayFuelCard

struct TodayFuelCard: View {
    let fuel: TodaySnapshot.Fuel
    let actions: TodayActions

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Button {
                actions.openTab(.fuel)
            } label: {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    TideSectionLabel(title: "Fuel", trailing: caloriesLeft)
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                            TideNumber((fuel.calories ?? 0).formatted(), size: Tide.numeralL)
                            Text(fuel.calorieTarget.map { "of \($0.formatted()) kcal" } ?? "kcal")
                                .font(Tide.body).foregroundStyle(Tide.text2)
                        }
                        .accessibilityElement(children: .combine)
                        TideLevelBar(progress: progress(fuel.calories, fuel.calorieTarget), height: Tide.bar)
                    }
                    macros
                    water
                }
                .contentShape(.rect)
            }
            .buttonStyle(TodayPressStyle())
            .accessibilityIdentifier("today.fuel")

            Button(action: actions.logMeal) {
                Label("Log a meal", systemImage: "plus")
            }
            .buttonStyle(.tideGlass)
            .accessibilityIdentifier("today.fuel.log")
        }
        .tideCard()
        .contextMenu {
            Button("Today's nutrition in detail", systemImage: "chart.bar") { actions.open(.fuel) }
            Button("Open Fuel", systemImage: "fork.knife") { actions.openTab(.fuel) }
        }
    }

    private var caloriesLeft: String? {
        guard let target = fuel.calorieTarget, target > 0 else {
            return nil
        }
        let left = target - (fuel.calories ?? 0)
        return left >= 0 ? "\(left.formatted()) left" : "\((-left).formatted()) over"
    }

    private var macros: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s4))
        return layout {
            macro("Protein", fuel.protein, fuel.proteinTarget, Tide.protein)
            macro("Carbs", fuel.carbs, fuel.carbsTarget, Tide.carbs)
            macro("Fat", fuel.fat, fuel.fatTarget, Tide.fat)
        }
    }

    private func macro(_ name: String, _ value: Int?, _ target: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(name).tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                TideNumber("\(value ?? 0)", size: Tide.numeralS, relativeTo: .headline)
                Text(target.map { "/ \($0) g" } ?? "g").font(Tide.caption).foregroundStyle(Tide.text2)
            }
            TideLevelBar(progress: progress(value, target), color: color, height: Tide.barSlim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value ?? 0)\(target.map { " of \($0)" } ?? "") grams")
    }

    private var water: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: "drop.fill").font(Tide.caption).foregroundStyle(Tide.water)
                    .accessibilityHidden(true)
                Text("Water").tideLabel()
                Spacer(minLength: Tide.s2)
                TideNumber(fuel.waterMl.formatted(), size: Tide.numeralS, relativeTo: .headline)
                Text("/ \(fuel.waterTargetMl.formatted()) ml").font(Tide.caption).foregroundStyle(Tide.text2)
            }
            TideLevelBar(progress: progress(fuel.waterMl, fuel.waterTargetMl), color: Tide.water, height: Tide.barSlim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water \(fuel.waterMl) of \(fuel.waterTargetMl) millilitres")
        .accessibilityIdentifier("today.water")
    }

    private func progress(_ value: Int?, _ target: Int?) -> Double {
        guard let value, let target, target > 0 else {
            return 0
        }
        return min(Double(value) / Double(target), 1)
    }
}

// MARK: - TodayTasksCard

struct TodayTasksCard: View {
    let snapshot: TodaySnapshot
    let actions: TodayActions
    let namespace: Namespace.ID

    /// Rows shown before the rest collapse into "+ N more".
    private static let visibleRows = 4

    var body: some View {
        if snapshot.tasks.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Daily tasks")
                Text("Nothing set yet. Pick the few things you do every day and Tempo holds you to them.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: actions.setUpTasks) {
                    Label("Choose tasks", systemImage: "plus")
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.tasks.setup")
            }
            .tideCard()
        } else {
            Button {
                actions.open(.lockdown)
            } label: {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(
                        title: snapshot.tasksLeft == 0 ? "Day unlocked" : "Tasks to unlock",
                        trailing: "\(snapshot.tasksDone) of \(snapshot.tasks.count)"
                    )
                    TideLevelBar(
                        progress: Double(snapshot.tasksDone) / Double(snapshot.tasks.count),
                        height: Tide.bar
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ordered.prefix(Self.visibleRows)) { task in
                            row(task)
                        }
                        if ordered.count > Self.visibleRows {
                            Text("+ \(ordered.count - Self.visibleRows) more")
                                .font(Tide.caption).foregroundStyle(Tide.text2)
                                .padding(.top, Tide.s2)
                        }
                    }
                }
                .tideCard()
                .contentShape(.rect(cornerRadius: Tide.cardRadius))
            }
            .buttonStyle(TodayPressStyle())
            .matchedTransitionSource(id: TodayRoute.lockdown, in: namespace)
            .sensoryFeedback(.success, trigger: snapshot.tasksDone)
            .accessibilityIdentifier("today.shortcut.lockdown")
        }
    }

    /// Open tasks first: they are what is left to do.
    private var ordered: [TodaySnapshot.TaskItem] {
        snapshot.tasks.filter { !$0.done } + snapshot.tasks.filter(\.done)
    }

    private func row(_ task: TodaySnapshot.TaskItem) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(Tide.headline)
                .foregroundStyle(task.done ? Tide.text2 : Tide.text)
                .contentTransition(.symbolEffect(.replace))
            Text(task.title)
                .font(Tide.body)
                .foregroundStyle(task.done ? Tide.text2 : Tide.text)
                .strikethrough(task.done, color: Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Tide.s8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.title), \(task.done ? "done" : "to do")")
    }
}

// MARK: - TodayMindMoveRow

struct TodayMindMoveRow: View {
    let snapshot: TodaySnapshot
    let actions: TodayActions
    let namespace: Namespace.ID

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        layout {
            study
            move
        }
    }

    private var study: some View {
        let data = snapshot.study
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TodayTile(label: "Study", identifier: "today.study", action: { actions.open(.mind) }) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    TideNumber("\(data.minutes)", unit: "min", size: Tide.numeralM)
                }
                if data.targetMinutes > 0 {
                    TideLevelBar(
                        progress: min(Double(data.minutes) / Double(data.targetMinutes), 1),
                        color: Tide.carbs, height: Tide.barSlim
                    )
                }
                Text(studyCaption(data)).font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .matchedTransitionSource(id: TodayRoute.mind, in: namespace)
            Button(action: actions.startFocus) {
                Label("Focus", systemImage: "timer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
            .accessibilityLabel("Start focus timer")
            .accessibilityIdentifier("today.focus")
        }
    }

    private func studyCaption(_ data: TodaySnapshot.Study) -> String {
        if let exam = data.nextExam {
            return exam
        }
        return data.targetMinutes > 0 ? "of \(data.targetMinutes) min today" : "No target set"
    }

    private var move: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TodayTile(label: "Move", identifier: "today.move", action: { actions.open(.move) }) {
                if let steps = snapshot.steps {
                    TideNumber(steps.formatted(), unit: "steps", size: Tide.numeralM)
                    TideLevelBar(
                        progress: min(Double(steps) / Double(max(snapshot.stepsTarget, 1)), 1),
                        color: Tide.water, height: Tide.barSlim
                    )
                } else {
                    Text("No steps yet").font(Tide.headline).foregroundStyle(Tide.text)
                }
                Text(workoutCaption).font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .matchedTransitionSource(id: TodayRoute.move, in: namespace)
            if snapshot.moveConnected {
                Button {
                    actions.openTab(.train)
                } label: {
                    Label("Train", systemImage: "dumbbell.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityLabel("Open training")
                .accessibilityIdentifier("today.train")
            } else {
                Button(action: actions.allowHealth) {
                    Label("Allow Health", systemImage: "heart.text.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.health")
            }
        }
    }

    private var workoutCaption: String {
        let workout = snapshot.workout
        switch workout.status {
        case .completed:
            let name = workout.name ?? "Session"
            return workout.durationMinutes.map { "\(name) done · \($0) min" } ?? "\(name) done"
        case .planned: return "\(workout.name ?? "Session") planned"
        case .rest: return "Rest day"
        case .none: return "No session planned"
        }
    }
}

// MARK: - TodayNoteCard

struct TodayNoteCard: View {
    let label: String
    let icon: String
    let text: String
    var pageCount = 0
    var onOpen: (() -> Void)?
    var onNext: (() -> Void)?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(alignment: .center, spacing: Tide.s3) {
            Button {
                onOpen?()
            } label: {
                HStack(alignment: .top, spacing: Tide.s3) {
                    Image(systemName: icon)
                        .font(Tide.headline)
                        .foregroundStyle(mood.accent)
                        .frame(width: Tide.icon, alignment: .leading)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text(label).tideLabel()
                        Text(text)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Tide.hit, alignment: .top)
                .contentShape(.rect)
            }
            .buttonStyle(TodayPressStyle())
            .disabled(onOpen == nil)
            .accessibilityElement(children: .combine)

            if let onNext, pageCount > 1 {
                Button(action: onNext) {
                    Image(systemName: "arrow.forward")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next insight")
                .accessibilityIdentifier("today.insight.next")
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}

// MARK: - TodaySetupCard

/// First-days checklist: what is still worth connecting or choosing.
struct TodaySetupCard: View {
    struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let done: Bool
        let action: () -> Void
    }

    let steps: [Step]
    let onSkip: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline) {
                TideSectionLabel(
                    title: "Finish setting up",
                    trailing: "\(steps.count(where: \.done)) of \(steps.count)"
                )
            }
            VStack(spacing: 0) {
                ForEach(steps) { step in
                    Button(action: step.action) {
                        HStack(spacing: Tide.s3) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : step.icon)
                                .font(Tide.headline)
                                .foregroundStyle(step.done ? Tide.text2 : mood.accent)
                                .frame(width: Tide.icon, alignment: .leading)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(step.title).font(Tide.bodyStrong)
                                    .foregroundStyle(step.done ? Tide.text2 : Tide.text)
                                if !step.done {
                                    Text(step.detail).font(Tide.caption).foregroundStyle(Tide.text2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: Tide.s2)
                            if !step.done {
                                Image(systemName: "chevron.right").font(Tide.label).foregroundStyle(Tide.text3)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: Tide.hit + Tide.s2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(TodayPressStyle())
                    .disabled(step.done)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.setup.\(step.id)")
                }
            }
            Button("Skip for now", action: onSkip)
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.setup.skip")
        }
        .tideCard()
    }
}
