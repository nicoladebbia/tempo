//
// TempoToast.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToast

// A glass capsule that drops in from the top: symbol, one or two lines, and an
// optional action ("Undo"). The ink tint keeps white text readable over any page.

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
            case .success: .tempoSuccess
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

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: style.icon)
                .font(Tide.headline)
                .foregroundStyle(style.iconColor)
                .accessibilityHidden(true)

            Text(message)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Tide.s2)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .padding(.horizontal, Tide.s2)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, Tide.s5)
        .padding(.trailing, actionTitle == nil ? Tide.s5 : Tide.s3)
        .padding(.vertical, Tide.s2)
        .frame(minHeight: Tide.hit + Tide.s2)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Tide.glassCard), in: .capsule)
        .padding(.horizontal, Tide.edge)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ToastModifier

// Attach with `.tempoToast($toast)`. Setting the binding shows the toast;
// it clears itself after `ToastData.duration`, or on an upward swipe.

struct ToastModifier: ViewModifier {
    @Binding
    var toast: ToastData?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
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
                    .padding(.top, Tide.s2)
                    // Per-toast identity so a replacement re-runs onAppear
                    // (haptic + its own auto-dismiss timer).
                    .id(toast.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        HapticManager.notification(toast.style.haptic)
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
                                if value.translation.height < -10 {
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

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    func tempoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
