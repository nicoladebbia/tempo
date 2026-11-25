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
        return ToastData(message: message, style: .info, actionTitle: String(localized: "Undo")) { [self] in
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
                    showFailureIfIdle()
                }
            }
            .onChange(of: arena.removalFailure) { _, _ in
                showFailureIfIdle()
            }
            .onDisappear {
                // Leaving the page makes the removal final, so no Undo is left to offer.
                arena.finishRemoval()
                toast = nil
            }
    }

    /// The server refused after the item left the screen. It is back; say why, but never
    /// in place of an Undo that is still up: that one is shown first.
    private func showFailureIfIdle() {
        guard let message = arena.removalFailure, toast == nil, !arena.hasPendingRemoval else {
            return
        }
        toast = ToastData(message: message, style: .error)
        arena.clearRemovalFailure()
    }
}

extension View {
    /// Shows the page's Undo toast and makes a removal final when it ends.
    func arenaUndoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ArenaUndoHost(toast: toast))
    }
}
