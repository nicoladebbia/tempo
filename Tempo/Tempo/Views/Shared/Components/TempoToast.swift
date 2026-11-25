//
// TempoToast.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToast

// A glass capsule that rises from the bottom (or drops from the top): symbol, one
// or two lines, and an optional action ("Undo"). The ink tint keeps white text
// readable over any page. At accessibility sizes the action sits under the
// message, so neither has to squeeze the other, and the message stops at
// `accessibilityLineLimit` lines so a toast never takes over the screen.

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

// MARK: - ToastPlacement

/// Where a toast sits. `.top` is the original place and the default, so a screen that
/// does nothing keeps what it had. `.bottom` never covers a navigation bar (Cancel, Save),
/// a page title or the workout timer: use it on pages with no bottom bar of their own.
/// `.aboveTabBar` is for a toast hosted outside the tabs (the app shell), so it rests
/// above the floating tab bar instead of on it.
enum ToastPlacement {
    case top
    case bottom
    case aboveTabBar

    var alignment: Alignment {
        self == .top ? .top : .bottom
    }

    var edge: Edge {
        self == .top ? .top : .bottom
    }

    /// Space kept between the toast and the edge it sits on.
    var inset: CGFloat {
        switch self {
        case .top, .bottom: Tide.s2
        case .aboveTabBar: Tide.s2 + Tide.tabBarClearance
        }
    }
}

// MARK: - ToastModifier

// Attach with `.tempoToast($toast)`. Setting the binding shows the toast;
// it clears itself after `ToastData.duration`, or on a swipe back the way it came.

struct ToastModifier: ViewModifier {
    @Binding
    var toast: ToastData?
    var placement: ToastPlacement = .top

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: placement.alignment) {
                if let toast {
                    TempoToast(
                        message: toast.message,
                        style: toast.style,
                        actionTitle: toast.actionTitle,
                        action: toast.action.map { run in
                            {
                                // Clear first: run() may set its own (error) toast.
                                withAnimation(Tide.snap) {
                                    self.toast = nil
                                }
                                run()
                            }
                        }
                    )
                    .padding(placement == .top ? .top : .bottom, placement.inset)
                    // Per-toast identity so a replacement re-runs onAppear
                    // (haptic + its own auto-dismiss timer).
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: placement.edge).combined(with: .opacity))
                    .onAppear {
                        HapticManager.notification(toast.style.haptic)
                        // A toast is not focused, so VoiceOver would never read it.
                        AccessibilityNotification.Announcement(toast.spokenText).post()
                        // A toast with an action stays long enough to use it;
                        // a newer toast must not be dismissed by an older timer.
                        let shownID = toast.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                            guard self.toast?.id == shownID else {
                                return
                            }
                            withAnimation(Tide.snap) {
                                self.toast = nil
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                // Swipe it away the way it came in.
                                let away = placement == .top ? value.translation.height < -10 : value.translation.height > 10
                                if away {
                                    withAnimation(Tide.snap) {
                                        self.toast = nil
                                    }
                                }
                            }
                    )
                }
            }
            .animation(Tide.lively, value: toast?.id)
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
    func tempoToast(_ toast: Binding<ToastData?>, placement: ToastPlacement = .top) -> some View {
        modifier(ToastModifier(toast: toast, placement: placement))
    }
}
