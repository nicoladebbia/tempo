//
// TempoToast.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToast

// A glass capsule: symbol, one or two lines, and an optional action ("Undo"). The ink
// tint keeps white text readable over any page. At accessibility sizes the action sits
// under the message, so neither has to squeeze the other, and the message stops at
// `accessibilityLineLimit` lines so a toast never takes over the screen. It is shown
// by `.tempoToast`, which gives it its own room (see `ToastModifier`).

struct TempoToast: View {
    let message: String
    let style: ToastStyle
    /// Optional trailing button ("Undo"). Tapping runs `action` and dismisses.
    var actionTitle: String?
    var action: (() -> Void)?

    enum ToastStyle {
        case success
        case warning
        case error
        case info

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            case .info: "info.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .success: Tide.success
            case .warning: .tempoWarning
            case .error: .tempoError
            case .info: .tempoInfo
            }
        }

        var haptic: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: .success
            case .warning: .warning
            case .error: .error
            case .info: .success
            }
        }
    }

    /// Two lines at normal sizes, three at accessibility sizes (where each line is huge).
    static let lineLimit = 2
    static let accessibilityLineLimit = 3

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        // The action sits beside a short message, and under a long one at accessibility sizes.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        layout {
            HStack(spacing: Tide.s3) {
                Image(systemName: style.icon)
                    .font(Tide.headline)
                    .foregroundStyle(style.iconColor)
                    .accessibilityHidden(true)

                Text(message)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(typeSize.isAccessibilitySize ? Self.accessibilityLineLimit : Self.lineLimit)
                    .fixedSize(horizontal: false, vertical: true)

                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .padding(.horizontal, Tide.s2)
                        .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toast.action")
            }
        }
        .padding(.leading, Tide.s5)
        .padding(.trailing, actionTitle == nil || typeSize.isAccessibilitySize ? Tide.s5 : Tide.s3)
        .padding(.vertical, Tide.s2)
        .frame(minHeight: Tide.hit + Tide.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(Tide.glassCard),
            // A capsule cuts into a message that runs to several lines.
            in: typeSize.isAccessibilitySize ? AnyShape(.rect(cornerRadius: Tide.tileRadius)) : AnyShape(.capsule)
        )
        .padding(.horizontal, Tide.edge)
        // The whole footprint is one solid hit shape, so a tap beside the button never reaches the page.
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

// MARK: - ToastPresence

/// Whether any toast is up (or still holding its room). A first-time tip waits while one is,
/// so the two never share the bottom edge and a tip's close button is never under the toast.
@MainActor
@Observable
final class ToastPresence {
    static let shared = ToastPresence()

    private(set) var liveToasts = 0

    var isUp: Bool {
        liveToasts > 0
    }

    func enter() {
        liveToasts += 1
    }

    func leave() {
        liveToasts = max(0, liveToasts - 1)
    }

    /// When each toast first showed. A page that is covered (a push, another tab) or swapped for
    /// another one (the workout's set page for its rest page) cancels and restarts the slot's timer:
    /// the toast must then keep only what is left of its time, with no second haptic or announcement.
    @ObservationIgnored
    private var shownTimes: [UUID: Date] = [:]

    func firstShown(_ id: UUID, now: Date = Date()) -> (at: Date, isNew: Bool) {
        // A toast lasts 5 s at most: anything older is gone, so the table never grows.
        shownTimes = shownTimes.filter { now.timeIntervalSince($0.value) < 60 }
        if let at = shownTimes[id] {
            return (at, false)
        }
        shownTimes[id] = now
        return (now, true)
    }
}

// MARK: - ToastSlot

enum ToastSlot {
    /// How long a toast's room stays, empty and not tappable, after the toast is gone.
    static let shield: Duration = .milliseconds(600)
}

// MARK: - ToastModifier

// Attach with `.tempoToast($toast)`. Setting the binding shows the toast; it clears itself after
// `ToastData.duration`, or on a swipe down.
//
// The toast takes its own room at the bottom edge (a bottom `safeAreaInset`) instead of floating
// over the page. Floating was the bug: it slid in over rows, bars and tips, and while it moved a
// tap on its Undo reached whatever it was passing over. Now it never overlaps the page, it does not
// travel (it fades and grows a little where it rests), and its whole footprint is solid, so a tap
// next to the button is absorbed too. It rests above the tab bar or a bottom bar that is in the
// safe area, and never on a navigation bar (Cancel, Save) or a timer.
//
// When the toast goes, its room stays for `ToastSlot.shield` as an empty gap that swallows taps,
// then closes. A late tap on where Undo was lands on nothing, not on the delete button or the row
// the page shows there a moment later.

struct ToastModifier: ViewModifier {
    @Binding
    var toast: ToastData?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    /// The last toast shown: drawn (invisible, not tappable) while its room is held after `toast` clears.
    @State
    private var last: ToastData?
    private var displayed: ToastData? {
        toast ?? last
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                slot
            }
            .animation(reduceMotion ? nil : Tide.snap, value: displayed?.id)
            .task(id: toast?.id) {
                await follow()
            }
            .modifier(ToastPresenceMark(isUp: displayed != nil))
            // A covered page keeps no empty gap for a toast that is already gone.
            .onDisappear {
                if toast == nil {
                    last = nil
                }
            }
    }

    @ViewBuilder
    private var slot: some View {
        if let shown = displayed {
            let live = toast?.id == shown.id
            TempoToast(
                message: shown.message,
                style: shown.style,
                actionTitle: shown.actionTitle,
                action: shown.action.map { run in
                    {
                        // A tap on a toast that is already gone does nothing.
                        guard self.toast?.id == shown.id else {
                            return
                        }
                        // Clear first: run() may set its own (error) toast.
                        withAnimation(Tide.snap) {
                            self.toast = nil
                        }
                        run()
                    }
                }
            )
            .opacity(live ? 1 : 0)
            .animation(reduceMotion ? nil : Tide.snap, value: live)
            .allowsHitTesting(live)
            .accessibilityHidden(!live)
            .overlay {
                if !live {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {}
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Tide.s2)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        // Swipe it back down, the way a bottom bar goes.
                        if value.translation.height > 10 {
                            withAnimation(Tide.snap) {
                                self.toast = nil
                            }
                        }
                    },
                isEnabled: live
            )
            // Per-toast identity so a replacement is a new toast (its own transition).
            .id(shown.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
        }
    }

    /// Runs for each toast (and once when it clears): feedback, the auto-dismiss timer, then the room.
    private func follow() async {
        guard let current = toast else {
            guard last != nil else {
                return
            }
            try? await Task.sleep(for: ToastSlot.shield)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(reduceMotion ? nil : Tide.snap) {
                last = nil
            }
            return
        }
        last = current
        let started = ToastPresence.shared.firstShown(current.id)
        if started.isNew {
            HapticManager.notification(current.style.haptic)
            // A toast is not focused, so VoiceOver would never read it.
            AccessibilityNotification.Announcement(current.spokenText).post()
        }
        // On a page that was covered or swapped: only what is left of its time.
        let remaining = current.duration - Date().timeIntervalSince(started.at)
        // A toast with an action stays long enough to use it. A newer toast is never
        // dismissed by an older timer: this task is cancelled when the id changes.
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard !Task.isCancelled, toast?.id == current.id else {
            return
        }
        withAnimation(Tide.snap) {
            toast = nil
        }
    }
}

// MARK: - ToastSlotModifier

extension EnvironmentValues {
    /// A toast a host keeps but a page shows in its own room (see `toastSlot`): the app shell's, for the
    /// tab on screen, and the workout's, for a page with a bottom bar.
    @Entry var pageToast: Binding<ToastData?>?
}

extension View {
    /// Shows the toast a host keeps (`pageToast`) in this view's own room at the bottom. Put it on a
    /// tab's root, or on a page just before its bottom bar so the bar stays where it is; `active` is
    /// whether this is the slot that should show it, so only one does.
    func toastSlot(active: Bool) -> some View {
        modifier(ToastSlotModifier(active: active))
    }
}

// MARK: - ToastSlotModifier

private struct ToastSlotModifier: ViewModifier {
    let active: Bool
    @Environment(\.pageToast)
    private var pageToast

    func body(content: Content) -> some View {
        content.tempoToast(
            Binding(
                get: { active ? pageToast?.wrappedValue : nil },
                set: { pageToast?.wrappedValue = $0 }
            )
        )
    }
}

// MARK: - ToastPresenceMark

/// Counts this toast slot in `ToastPresence` while it is up.
private struct ToastPresenceMark: ViewModifier {
    let isUp: Bool
    @State
    private var counted = false

    func body(content: Content) -> some View {
        content
            .onAppear { sync(isUp) }
            .onChange(of: isUp) { _, now in sync(now) }
            .onDisappear { sync(false) }
    }

    private func sync(_ up: Bool) {
        if up, !counted {
            counted = true
            ToastPresence.shared.enter()
        } else if !up, counted {
            counted = false
            ToastPresence.shared.leave()
        }
    }
}

// MARK: - ToastData

struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: TempoToast.ToastStyle
    /// Optional action button (e.g. "Undo") — see `TempoToast`.
    var actionTitle: String?
    var action: (() -> Void)?

    /// 5 s when there is an action to tap, 3 s otherwise.
    var duration: TimeInterval {
        actionTitle == nil ? 3 : 5
    }

    /// What VoiceOver says when it appears: the message, and that there is an action to take.
    var spokenText: String {
        guard let actionTitle else {
            return message
        }
        return String(localized: "\(message) \(actionTitle) is available.")
    }

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    /// Shows `toast` in its own room at the bottom of this view (see `ToastModifier`).
    func tempoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
