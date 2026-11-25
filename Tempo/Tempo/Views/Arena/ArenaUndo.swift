//
// ArenaUndo.swift
// Tempo
//
// The Undo toast for the Arena pages that remove something: a friend, a friend
// request, a challenge. The page calls `arena.removalToast(...)` instead of
// asking the server, keeps the toast in its own state and adds `.arenaUndoToast`.
// The rule itself (hide now, send when the window ends) lives in `ArenaService`.
//

import SwiftUI

extension ArenaService {
    /// Hides `removal` now and returns the toast that offers Undo for about 5 seconds.
    func removalToast(_ removal: ArenaRemoval, message: String) -> ToastData {
        beginRemoval(removal)
        return ToastData(message: message, style: .info, actionTitle: "Undo") { [self] in
            undoRemoval()
        }
    }
}

// MARK: - ArenaUndoHost

private struct ArenaUndoHost: ViewModifier {
    @Environment(ArenaService.self)
    private var arena
    @Binding
    var toast: ToastData?

    func body(content: Content) -> some View {
        content
            .tempoToast($toast)
            .onChange(of: toast) { _, newValue in
                // The window is over (or the toast was swiped away): the removal is final.
                if newValue == nil {
                    arena.finishRemoval()
                }
            }
            .onChange(of: arena.removalFailure) { _, message in
                // The server refused after the item left the screen. It is back; say why.
                if let message {
                    toast = ToastData(message: message, style: .error)
                    arena.clearRemovalFailure()
                }
            }
            .onDisappear { arena.finishRemoval() }
    }
}

extension View {
    /// Shows the page's Undo toast and makes a removal final when it ends.
    func arenaUndoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ArenaUndoHost(toast: toast))
    }
}
