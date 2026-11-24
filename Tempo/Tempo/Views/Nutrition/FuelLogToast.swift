//
// FuelLogToast.swift
// Tempo
//
// The toast every Fuel log ends with: "Lunch logged. 640 kcal." and a few
// seconds to Undo it. It is the app's own Undo toast (`ToastData` with an
// action), not a second one. The log screens close the moment a meal is saved,
// so the toast is posted as a notification and shown by whichever screen is
// still under them: `fuelLogToastHost()` on the Fuel tab, or on the app shell
// so it also shows after a log made from the "+" sheet.
//

import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// True below a view that already shows Fuel log toasts, so a log screen
    /// knows it can close at once and leave the toast to that host.
    @Entry var fuelLogToastHosted: Bool = false
}

// MARK: - FuelLogToast

@MainActor
enum FuelLogToast {
    /// How long a toast with an Undo stays up (`ToastData.duration`).
    static let undoWindow: TimeInterval = 5

    /// The toast for a meal that was just saved: the message plus an Undo that
    /// takes back exactly that log (see `EatenMealRecorder.undoLog`).
    static func logged(
        _ message: String,
        result: EatenMealRecorder.Result,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?
    ) -> ToastData {
        ToastData(message: message, style: .success, actionTitle: "Undo") {
            let env = MealOutcomeService.Env(modelContext: modelContext, notifications: notifications)
            do {
                if try EatenMealRecorder.undoLog(result, env: env) {
                    NotificationCenter.default.post(name: .tempoFuelLogUndone, object: nil)
                    post(ToastData(message: "Log taken back.", style: .info))
                }
            } catch {
                post(ToastData(message: "Couldn't undo that log. Delete it from Logged today.", style: .error))
            }
        }
    }

    /// Hands a toast to whichever host is showing Fuel toasts.
    static func post(_ toast: ToastData) {
        var info: [String: Any] = ["message": toast.message, "error": toast.style == .error]
        if let title = toast.actionTitle, let action = toast.action {
            info["actionTitle"] = title
            info["action"] = action
        }
        NotificationCenter.default.post(name: .tempoMealLogToast, object: nil, userInfo: info)
    }

    /// The toast a `post` carried.
    static func toast(from note: Notification) -> ToastData? {
        guard let message = note.userInfo?["message"] as? String else {
            return nil
        }
        let isError = note.userInfo?["error"] as? Bool ?? false
        var toast = ToastData(message: message, style: isError ? .error : .success)
        if let title = note.userInfo?["actionTitle"] as? String, let action = note.userInfo?["action"] as? () -> Void {
            toast.actionTitle = title
            toast.action = action
        }
        return toast
    }
}

// MARK: - FuelLogToastHost

struct FuelLogToastHost: ViewModifier {
    @Environment(\.fuelLogToastHosted)
    private var alreadyHosted
    @State
    private var toast: ToastData?

    func body(content: Content) -> some View {
        if alreadyHosted {
            content
        } else {
            content
                .environment(\.fuelLogToastHosted, true)
                .tempoToast($toast)
                .onReceive(NotificationCenter.default.publisher(for: .tempoMealLogToast)) { note in
                    if let next = FuelLogToast.toast(from: note) {
                        toast = next
                        dismissLater(next)
                    }
                }
        }
    }

    /// The toast's own timer does not run for one posted from inside another toast's
    /// Undo ("Log taken back." stayed up for ever), so the host also takes it down.
    /// A newer toast is never dismissed by an older timer.
    private func dismissLater(_ shown: ToastData) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(shown.duration + 0.5))
            if toast?.id == shown.id {
                withAnimation(Tide.snap) {
                    toast = nil
                }
            }
        }
    }
}

extension View {
    /// Shows the toasts Fuel logs post (with Undo) on top of this screen. A
    /// second host inside a first one does nothing, so the Fuel tab and the app
    /// shell can both use it without double toasts.
    func fuelLogToastHost() -> some View {
        modifier(FuelLogToastHost())
    }
}
