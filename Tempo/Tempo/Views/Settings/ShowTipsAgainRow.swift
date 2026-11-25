//
// ShowTipsAgainRow.swift
// Tempo
//
// The Settings row that brings every first-time tip back. The tips are one
// sentence each, shown once the first time a feature is opened; this is the way
// to see them again without reinstalling. The page that holds the row owns the
// toast, so the confirmation sits where every other toast on the page does.
//

import SwiftUI

struct ShowTipsAgainRow: View {
    @Binding
    var toast: ToastData?

    var body: some View {
        Button {
            FirstTips.resetAll()
            toast = ToastData(message: "Tips will show again the next time you open each feature.", style: .success)
        } label: {
            SettingsActionRow(icon: "lightbulb", title: "Show tips again", tint: Tide.text)
        }
        .buttonStyle(.tideSettingsRow)
        .accessibilityIdentifier("settingsShowTipsAgain")
    }
}
