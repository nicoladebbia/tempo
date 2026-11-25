//
// SetupChecklist.swift
// Tempo
//
// The "Get set up" checklist: what is still worth connecting or choosing after
// the short onboarding. Built from `docs/ONBOARDING_AND_NOTIFICATIONS.md` 2.2,
// the questions that were dropped from onboarding and are asked later.
//
// Pure: it takes plain facts read from the app's real state and says which
// lines are done, which are left and whether the card should show at all.
// Nothing here is stored; the card hides itself the moment the facts change.
//

import Foundation

// MARK: - SetupStep

enum SetupStep: String, CaseIterable, Identifiable {
    case health
    case whoop
    case food
    case training
    case tasks

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .health: "Allow Apple Health"
        case .whoop: "Connect Whoop"
        case .food: "Set up your food"
        case .training: "Set up training"
        case .tasks: "Choose daily tasks"
        }
    }

    var detail: String {
        switch self {
        case .health: "Steps, heart rate and sleep, read for you."
        case .whoop: "Recovery, sleep and strain from your band."
        case .food: "Your goal, diet and eating window set the targets."
        case .training: "Your level, split and training days."
        case .tasks: "The few things you do every day."
        }
    }

    var icon: String {
        switch self {
        case .health: "heart.text.square.fill"
        case .whoop: "waveform.path.ecg"
        case .food: "fork.knife"
        case .training: "dumbbell.fill"
        case .tasks: "checklist"
        }
    }

    /// The three steps only Tempo can do for you. Health and Whoop are
    /// optional hardware: the Today page already has its own button for each.
    var isCore: Bool {
        switch self {
        case .food,
             .training,
             .tasks: true
        case .health,
             .whoop: false
        }
    }
}

// MARK: - SetupChecklist

struct SetupChecklist: Equatable {
    /// Facts read from the app. Each one is a real signal, never a flag the
    /// checklist keeps for itself.
    struct Signals: Equatable {
        /// The app's Health permission flag.
        var healthAllowed = false
        /// A real Whoop account is connected (demo mode does not count).
        var whoopConnected = false
        /// An active diet profile exists.
        var hasDietProfile = false
        /// The training level was chosen, a trainer program exists, or a
        /// session has been logged.
        var hasChosenTraining = false
        /// Active daily tasks.
        var taskCount = 0
        /// The first refresh has finished, so connection states are known and
        /// a line is not shown as open for a moment and then ticked.
        var resolved = false
    }

    struct Line: Identifiable, Equatable {
        let step: SetupStep
        let done: Bool

        var id: String {
            step.id
        }
    }

    let signals: Signals
    let lines: [Line]

    init(_ signals: Signals) {
        self.signals = signals
        lines = SetupStep.allCases.map { step in
            Line(step: step, done: Self.isDone(step, signals))
        }
    }

    private static func isDone(_ step: SetupStep, _ signals: Signals) -> Bool {
        switch step {
        case .health: signals.healthAllowed
        case .whoop: signals.whoopConnected
        case .food: signals.hasDietProfile
        case .training: signals.hasChosenTraining
        case .tasks: signals.taskCount > 0
        }
    }

    var doneCount: Int {
        lines.count(where: \.done)
    }

    var total: Int {
        lines.count
    }

    /// What is left, in the order of the table in the docs.
    var remaining: [Line] {
        lines.filter { !$0.done }
    }

    /// Everything Tempo itself asks for is done: this person is set up, even
    /// without a band or Health.
    var isConfigured: Bool {
        lines.filter(\.step.isCore).allSatisfy(\.done)
    }

    /// Whether the card shows on Today. Never for someone who is set up,
    /// never after "Later", and not before the connection states are known.
    func isVisible(dismissed: Bool) -> Bool {
        signals.resolved && !dismissed && !isConfigured
    }
}
