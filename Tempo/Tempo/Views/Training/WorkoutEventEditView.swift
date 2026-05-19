//
// WorkoutEventEditView.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import EventKitUI
import SwiftUI

// MARK: - WorkoutEventEditView

/// Wraps `EKEventEditViewController` so the user can add the suggested
/// workout window to their calendar with the system editor (they confirm
/// the calendar, can tweak time, and EventKit handles the write + access
/// prompt). Per build done_when #16–17.
struct WorkoutEventEditView: UIViewControllerRepresentable {
    let window: DateInterval
    let workoutTitle: String
    /// Called with the saved event's stable identifier (nil on
    /// cancel/delete) so the caller can persist it for ID-based countdown
    /// resolution.
    let onSaved: (String?) -> Void

    @Environment(\.dismiss)
    private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onSaved: onSaved)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store

        let event = EKEvent(eventStore: store)
        event.title = "\(workoutTitle) Workout"

        // Prefill must never land in the past. The suggested window can
        // start earlier than "now" (it's scanned from 08:00). Start at the
        // later of (window start) or (now rounded up to the next 5 min). If
        // the whole window is already gone, fall back to a now-anchored
        // 90-min slot so the editor still opens on a sensible future time.
        let now = Date()
        let roundedNow = Self.roundedUpToFiveMinutes(now)
        let proposedStart = max(window.start, roundedNow)
        let start: Date
        let end: Date
        if proposedStart < window.end {
            start = proposedStart
            end = min(window.end, proposedStart.addingTimeInterval(90 * 60))
        } else {
            // Window has passed — anchor to now.
            start = roundedNow
            end = roundedNow.addingTimeInterval(90 * 60)
        }
        event.startDate = start
        event.endDate = end
        event.calendar = store.defaultCalendarForNewEvents

        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    /// Rounds a date up to the next 5-minute mark so the prefilled slot
    /// looks intentional (13:26 → 13:30) rather than ragged.
    private static func roundedUpToFiveMinutes(_ date: Date) -> Date {
        let interval: TimeInterval = 5 * 60
        let rounded = (date.timeIntervalSinceReferenceDate / interval).rounded(.up) * interval
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    func updateUIViewController(_: EKEventEditViewController, context _: Context) {}

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let dismiss: DismissAction
        private let onSaved: (String?) -> Void

        init(dismiss: DismissAction, onSaved: @escaping (String?) -> Void) {
            self.dismiss = dismiss
            self.onSaved = onSaved
        }

        // EKEventEditViewDelegate (ObjC) is imported without a main-actor
        // annotation, so the protocol requirement is `nonisolated`. But
        // EventKitUI contractually delivers this callback on the main thread
        // (EKEventEditViewController.h: the delegate "will receive the
        // eventEditViewController:didCompleteWithAction: message" from the
        // presented UI). We satisfy the nonisolated requirement with a thin
        // shim that `assumeIsolated`-hops onto the main actor — the same
        // bridge Apple recommends for un-annotated UIKit delegates — then
        // does everything synchronously: read the @MainActor `controller`,
        // call the @MainActor `dismiss`, invoke `onSaved`. No Task, no
        // cross-isolation send, no non-Sendable capture.
        nonisolated func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            MainActor.assumeIsolated {
                let savedID: String? = action == .saved
                    ? controller.event?.eventIdentifier
                    : nil
                onSaved(savedID)
                dismiss()
            }
        }
    }
}
