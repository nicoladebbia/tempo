//
// TempoToast.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToast

// Per DESIGN_SYSTEM.md Section 8.8 — Toast:
// Ink Black bg @95%, 14pt radius, slide from top, auto-dismiss 3s.

struct TempoToast: View {
    let message: String
    let style: ToastStyle

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

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: style.icon)
                .font(.system(size: 20))
                .foregroundStyle(style.iconColor)

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoBone)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.tempoInk.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        .padding(.horizontal, TempoSpacing.xl)
    }
}

// MARK: - ToastModifier

struct ToastModifier: ViewModifier {
    @Binding
    var toast: ToastData?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    TempoToast(message: toast.message, style: toast.style)
                        .padding(.top, TempoSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            HapticManager.notification(toast.style.haptic)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    self.toast = nil
                                }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onEnded { value in
                                    if value.translation.height < -10 {
                                        withAnimation(.easeIn(duration: 0.2)) {
                                            self.toast = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: toast?.id)
    }
}

// MARK: - ToastData

struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: TempoToast.ToastStyle

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    func tempoToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
