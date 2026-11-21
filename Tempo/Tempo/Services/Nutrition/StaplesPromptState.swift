//
// StaplesPromptState.swift
// Tempo
//
// The "Track your staples" prompt as a tiny state machine, persisted so it
// never nags: offered (peek card on Pantry) -> skipped / done (hidden, but a
// "Staples" chip stays on Pantry so it is always findable).
//

import Foundation

// MARK: - StaplesPromptPhase

enum StaplesPromptPhase: String, Codable, Sendable {
    /// Not answered yet: the peek card shows at the bottom of Pantry.
    case offered
    /// User tapped Skip. No peek card; chip stays.
    case skipped
    /// User finished the checklist. No peek card; chip stays.
    case done
}

enum StaplesPromptEvent: Sendable {
    case skip
    case complete
    /// Opened again from the chip / menu. Never changes the phase.
    case reopen
}

struct StaplesPromptMachine: Equatable, Sendable {
    private(set) var phase: StaplesPromptPhase = .offered

    init(phase: StaplesPromptPhase = .offered) {
        self.phase = phase
    }

    mutating func apply(_ event: StaplesPromptEvent) {
        switch (phase, event) {
        case (.offered, .skip): phase = .skipped
        case (_, .complete): phase = .done
        default: break
        }
    }

    /// Swiping the sheet down is NOT an event: the card stays as a peek until
    /// the user taps Done or Skip.
    var showsPeekCard: Bool {
        phase == .offered
    }
}

// MARK: - StaplesPromptStore

/// UserDefaults-backed persistence for the phase and the "don't have it"
/// answers (so a No isn't asked again).
struct StaplesPromptStore {
    private let defaults: UserDefaults
    private let phaseKey = "staples.prompt.phase"
    private let declinedKey = "staples.prompt.declined"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `false` until the user (or the legacy migration) first settles the prompt.
    var hasStoredPhase: Bool {
        defaults.string(forKey: phaseKey) != nil
    }

    var machine: StaplesPromptMachine {
        get {
            StaplesPromptMachine(phase: defaults.string(forKey: phaseKey).flatMap(StaplesPromptPhase.init(rawValue:)) ?? .offered)
        }
        nonmutating set {
            defaults.set(newValue.phase.rawValue, forKey: phaseKey)
        }
    }

    var declined: Set<String> {
        get { Set(defaults.stringArray(forKey: declinedKey) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: declinedKey) }
    }
}
