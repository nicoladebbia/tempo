//
// TempoShortcuts.swift
// Tempo
//
// The phrases Siri understands out of the box, and the tiles the Shortcuts app
// and the Action button list for Tempo. Every phrase names the app, as the
// system requires.
//

import AppIntents

struct TempoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water in \(.applicationName)",
                "I drank water in \(.applicationName)",
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my workout in \(.applicationName)",
                "Start workout in \(.applicationName)",
            ],
            shortTitle: "Start workout",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "Start a focus timer in \(.applicationName)",
            ],
            shortTitle: "Start focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "What is next in \(.applicationName)",
            ],
            shortTitle: "What's next",
            systemImageName: "arrow.forward.circle.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .lightBlue
}
