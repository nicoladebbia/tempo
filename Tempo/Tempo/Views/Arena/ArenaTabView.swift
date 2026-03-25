import SwiftUI

// MARK: - Arena Tab View
// Per MODULE_ARENA.md Section 5.1 — 5th tab, trophy.fill icon.
// Contains ArenaMainView with navigation to sub-views.

struct ArenaTabView: View {

    var body: some View {
        NavigationStack {
            ArenaMainView()
        }
    }
}
