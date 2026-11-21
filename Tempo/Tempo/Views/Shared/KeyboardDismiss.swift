//
// KeyboardDismiss.swift
// Tempo
//
// Tap anywhere that isn't a text input to close the keyboard, plus a
// keyboard-toolbar "Done" (number pads have no Return key).
//

import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard on a tap outside any text input, on interactive
    /// scroll, and adds a "Done" button above the keyboard.
    func dismissKeyboardOnTapOutside() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .background(TapOutsideKeyboardDismisser().frame(width: 0, height: 0))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { KeyboardDismisser.dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("keyboardDone")
                }
            }
    }
}

enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// True when a touch landed on (or inside) something that edits text.
    static func isTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView || candidate is UIControl {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

/// Installs a window-level tap recognizer that never cancels touches, so
/// buttons, rows and fields behave exactly as before.
private struct TapOutsideKeyboardDismisser: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.anchor = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.install() }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var anchor: UIView?
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func install() {
            guard recognizer == nil, let window = anchor?.window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.window = window
            recognizer = tap
        }

        func uninstall() {
            if let recognizer { window?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }

        @objc private func tapped() { KeyboardDismisser.dismiss() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !KeyboardDismisser.isTextInput(touch.view)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
