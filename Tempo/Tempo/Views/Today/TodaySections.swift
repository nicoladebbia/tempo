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
    var openSearch: () -> Void = {}
    var openSettings: () -> Void = {}

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // The greeting needs the whole line: the controls go above it.
            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack(spacing: Tide.s2) {
                    streak
                    Spacer(minLength: Tide.s2)
                    controls
                }
                titleBlock
            }
        } else {
            // Controls on the top line with the date, the greeting and the streak below.
            VStack(alignment: .leading, spacing: Tide.s1) {
                HStack(alignment: .center, spacing: Tide.s2) {
                    dateBlock
                    Spacer(minLength: Tide.s2)
                    controls
                }
                HStack(alignment: .center, spacing: Tide.s2) {
                    greeting
                    Spacer(minLength: Tide.s2)
                    streak
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Tide.s2) {
            searchButton
            NotificationBell(glass: true)
            settingsButton
        }
    }

    private var dateBlock: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            TideLabel(dateLine)
            if let weather {
                Label(weather.temperature, systemImage: weather.symbol)
                    .labelStyle(.titleAndIcon)
                    .tideLabel()
                    .accessibilityLabel("Weather \(weather.temperature)")
            }
        }
    }

    private var greeting: some View {
        TimelineView(.everyMinute) { context in
            Text(TodayGreeting.text(
                hour: Calendar.current.component(.hour, from: context.date),
                name: snapshot.firstName
            ))
            .font(Tide.title)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// The date and the greeting together, for the stacked accessibility layout.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            dateBlock
            greeting
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var streak: some View {
        if snapshot.streakDays > 0 {
            HStack(spacing: Tide.s1) {
                Image(systemName: "flame.fill").font(Tide.bodyStrong).foregroundStyle(Tide.streak)
                TideNumber("\(snapshot.streakDays)", size: Tide.numeralS, relativeTo: .headline)
            }
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.streakDays) day streak")
            .explains(Explainer.streak(tasksLeft: snapshot.tasksLeft).showing(String(localized: "\(snapshot.streakDays) days")))
            .accessibilityIdentifier("today.streak")
        }
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("today.search")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("today.settings")
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
                TideDial(score: snapshot.score, caption: String(localized: "Day score"), diameter: Tide.dialHero)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot.score.map { String(localized: "Day score \($0) of 100") } ?? String(localized: "Day score, not enough data yet"))
            .accessibilityHint("Shows what the score is made of")
            .accessibilityIdentifier("today.score")

            VStack(alignment: .leading, spacing: Tide.s2) {
                Text(snapshot.score == nil ? String(localized: "No score yet") : mood.word)
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

    /// Every word comes from `NextStepEngine`, the same place the "what next"
    /// bar after a workout, a meal or a focus session takes its words from.
    private var step: NextStep {
        NextStepEngine.step(for: action, snapshot: snapshot)
    }

    var body: some View {
        let step = step
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: String(localized: "Next up"), trailing: trailing)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(step.title)
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let title = step.buttonTitle, let icon = step.buttonIcon {
                Button {
                    taps += 1
                    run()
                } label: {
                    Label(title, systemImage: icon)
                }
                .buttonStyle(.tidePrimary)
                .workoutZoomSource(.today)
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
            snapshot.workout.durationMinutes.map { String(localized: "\($0) min") }
        default: nil
        }
    }

    private func run() {
        switch action {
        case .workout: actions.startWorkout()
        case let .meal(meal): actions.openMeal(meal)
        case .rest: actions.open(.recovery)
        case .firstMeal: actions.logMeal()
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
        VStack(spacing: Tide.s3) {
            layout {
                recovery
                sleep
            }
            // The row is as tall as its taller tile; both tiles fill it.
            .fixedSize(horizontal: false, vertical: true)
            if !snapshot.recovery.hasSource {
                Button(action: actions.connectWearable) {
                    Label("Connect Whoop", systemImage: "waveform.path.ecg").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.connect")
            }
        }
    }

    @ViewBuilder
    private var recovery: some View {
        let data = snapshot.recovery
        TodayTile(label: String(localized: "Recovery"), identifier: "today.shortcut.recovery", action: { actions.open(.recovery) }) {
            if let score = data.score {
                TideNumber("\(score)", unit: "%", size: Tide.numeralM)
                TideLevelBar(progress: Double(score) / 100, height: Tide.barSlim)
                Text(vitals(data)).font(Tide.caption).foregroundStyle(Tide.text2)
            } else {
                Text(data.hasSource ? String(localized: "Waiting for today") : String(localized: "No reading yet"))
                    .font(Tide.headline).foregroundStyle(Tide.text)
                Text(data.hasSource ? String(localized: "Your tracker has not synced yet.") : String(localized: "Needs a tracker like Whoop."))
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .matchedTransitionSource(id: TodayRoute.recovery, in: namespace)
    }

    private var sleep: some View {
        let data = snapshot.recovery
        return TodayTile(label: String(localized: "Sleep"), identifier: "today.sleep", action: { actions.open(.body) }) {
            if let hours = data.sleepHours {
                let whole = Int(hours), minutes = Int(((hours - Double(whole)) * 60).rounded())
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber("\(whole)", unit: String(localized: "h"), size: Tide.numeralM)
                    TideNumber(String(format: "%02d", minutes), unit: String(localized: "m"), size: Tide.numeralM)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(whole) hours \(minutes) minutes")
                if let performance = data.sleepPerformance {
                    TideLevelBar(progress: Double(performance) / 100, color: Tide.fat, height: Tide.barSlim)
                }
                Text(data.sleepPerformance.map { String(localized: "\($0)% of what you needed") } ?? String(localized: "Last night"))
                    .font(Tide.caption).foregroundStyle(Tide.text2)
            } else {
                Text("No sleep data").font(Tide.headline).foregroundStyle(Tide.text)
                Text("Wear your tracker tonight.").font(Tide.caption).foregroundStyle(Tide.text2)
            }
        }
        .matchedTransitionSource(id: TodayRoute.body, in: namespace)
    }

    private func vitals(_ data: TodaySnapshot.Recovery) -> String {
        let parts = [data.hrv.map { String(localized: "HRV \($0)") }, data.restingHR.map { String(localized: "RHR \($0)") }].compactMap(\.self)
        return parts.isEmpty ? String(localized: "Open recovery") : parts.joined(separator: " · ")
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
                    TideLabel(label)
                    Spacer(minLength: Tide.s1)
                    Image(systemName: "chevron.right").font(Tide.label).foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
                content
            }
            // Fills the row's height, so two tiles side by side always match.
            .frame(maxWidth: .infinity, minHeight: Tide.hit * 2, maxHeight: .infinity, alignment: .topLeading)
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
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
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
                    TideSectionLabel(title: String(localized: "Fuel"), trailing: caloriesLeft)
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        // The figure and "of 3,130 kcal" go on two lines when one would wrap.
                        let calorieLayout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s2))
                        calorieLayout {
                            TideNumber((fuel.calories ?? 0).formatted(), size: Tide.numeralL)
                            Text(fuel.calorieTarget.map { String(localized: "of \($0.formatted()) kcal") } ?? String(localized: "kcal"))
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
        return left >= 0 ? String(localized: "\(left.formatted()) left") : String(localized: "\((-left).formatted()) over")
    }

    private var macros: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s4))
        return layout {
            macro(String(localized: "Protein"), fuel.protein, fuel.proteinTarget, Tide.protein)
            macro(String(localized: "Carbs"), fuel.carbs, fuel.carbsTarget, Tide.carbs)
            macro(String(localized: "Fat"), fuel.fat, fuel.fatTarget, Tide.fat)
        }
    }

    private func macro(_ name: String, _ value: Int?, _ target: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            TideLabel(name)
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
            if typeSize.isAccessibilitySize {
                // Name above, amount below: "/ 3,305 ml" never has to wrap.
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "drop.fill").font(Tide.caption).foregroundStyle(Tide.water)
                        .accessibilityHidden(true)
                    TideLabel(String(localized: "Water"))
                }
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber(fuel.waterMl.formatted(), size: Tide.numeralS, relativeTo: .headline)
                    Text("/ \(fuel.waterTargetMl.formatted()) ml").font(Tide.caption).foregroundStyle(Tide.text2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "drop.fill").font(Tide.caption).foregroundStyle(Tide.water)
                        .accessibilityHidden(true)
                    TideLabel(String(localized: "Water"))
                    Spacer(minLength: Tide.s2)
                    TideNumber(fuel.waterMl.formatted(), size: Tide.numeralS, relativeTo: .headline)
                    Text("/ \(fuel.waterTargetMl.formatted()) ml").font(Tide.caption).foregroundStyle(Tide.text2)
                }
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
                Button {
                    actions.open(.lockdown)
                } label: {
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        HStack {
                            TideLabel(String(localized: "Daily tasks"))
                            Spacer(minLength: Tide.s1)
                            Image(systemName: "chevron.right").font(Tide.label).foregroundStyle(Tide.text3)
                                .accessibilityHidden(true)
                        }
                        Text("Nothing set yet. Pick the few things you do every day and Tempo holds you to them.")
                            .font(Tide.body).foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(TodayPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.shortcut.lockdown")
                Button(action: actions.setUpTasks) {
                    Label("Choose tasks", systemImage: "plus")
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.tasks.setup")
            }
            .tideCard()
            .matchedTransitionSource(id: TodayRoute.lockdown, in: namespace)
        } else {
            Button {
                actions.open(.lockdown)
            } label: {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(
                        title: snapshot.tasksLeft == 0 ? String(localized: "Day unlocked") : String(localized: "Tasks to unlock"),
                        trailing: String(localized: "\(snapshot.tasksDone) of \(snapshot.tasks.count)")
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var study: some View {
        let data = snapshot.study
        return TodayTile(label: String(localized: "Study"), identifier: "today.study", action: { actions.open(.mind) }) {
            TideNumber("\(data.minutes)", unit: String(localized: "min"), size: Tide.numeralM)
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
    }

    private func studyCaption(_ data: TodaySnapshot.Study) -> String {
        if let exam = data.nextExam {
            return exam
        }
        return data.targetMinutes > 0 ? String(localized: "of \(data.targetMinutes) min today") : String(localized: "No target set")
    }

    @ViewBuilder
    private var move: some View {
        if snapshot.moveConnected {
            TodayTile(label: String(localized: "Move"), identifier: "today.move", action: { actions.open(.move) }) {
                if let steps = snapshot.steps {
                    TideNumber(steps.formatted(), unit: String(localized: "steps"), size: Tide.numeralM)
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
            .contextMenu {
                Button("Open training", systemImage: "dumbbell.fill") { actions.openTab(.train) }
            }
        } else {
            TodayTile(label: String(localized: "Move"), identifier: "today.health", action: actions.allowHealth) {
                Text("Allow Health").font(Tide.headline).foregroundStyle(Tide.text)
                Text("Steps and workouts come from the Health app.")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var workoutCaption: String {
        let workout = snapshot.workout
        switch workout.status {
        case .completed:
            let name = workout.name ?? String(localized: "Session")
            return workout.durationMinutes.map { String(localized: "\(name) done · \($0) min") } ?? String(localized: "\(name) done")
        case .planned:
            let plannedName = workout.name ?? String(localized: "Session")
            return String(localized: "\(plannedName) planned")
        case .rest: return String(localized: "Rest day")
        case .none: return String(localized: "No session planned")
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
                        .frame(minWidth: Tide.icon, alignment: .leading)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        TideLabel(label)
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
