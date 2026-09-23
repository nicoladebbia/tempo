//
// PersistenceAlert.swift
// Tempo
//
// One app-wide "that didn't save" signal for Training screens that write
// SwiftData directly (settings, match/venue cards, library, history).
// Replaces `try? modelContext.save()`, which dropped failures while the UI
// showed success. Views call `modelContext.saveOrAlert("…")`; any screen with
// `.persistenceAlert()` in its hierarchy shows the message.
//

import SwiftData
import SwiftUI

@MainActor
@Observable
final class PersistenceAlert {
    static let shared = PersistenceAlert()

    var message: String?

    func report(_ operation: String) {
        message = "Couldn't save your \(operation). Try it again — if this keeps happening, free up iPhone storage."
    }
}

extension ModelContext {
    /// Save with one retry; on failure raise the shared alert. Returns
    /// whether the save landed.
    @MainActor
    @discardableResult
    func saveOrAlert(_ operation: String) -> Bool {
        for _ in 0 ..< 2 {
            if (try? save()) != nil {
                return true
            }
        }
        PersistenceAlert.shared.report(operation)
        return false
    }
}

private struct PersistenceAlertModifier: ViewModifier {
    @State
    private var alert = PersistenceAlert.shared

    func body(content: Content) -> some View {
        content.alert(
            "Save failed",
            isPresented: Binding(
                get: { alert.message != nil },
                set: { if !$0 { alert.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alert.message ?? "")
        }
    }
}

extension View {
    /// Present PersistenceAlert failures raised anywhere below/around this view.
    func persistenceAlert() -> some View {
        modifier(PersistenceAlertModifier())
    }
}
