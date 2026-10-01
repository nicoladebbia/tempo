//
// SwipeToDeleteRow.swift
// Tempo
//
// Swipe-left-to-delete for rows that live in a ScrollView/VStack (SwiftUI's
// `.swipeActions` only works inside a List). Drag left to reveal a Delete
// button; tap it to delete. Vertical drags are ignored so scrolling and the
// row's own tap target keep working.
//

import SwiftUI

private struct SwipeToDeleteModifier: ViewModifier {
    let enabled: Bool
    let label: String
    let onDelete: () -> Void

    @State
    private var offset: CGFloat = 0
    @State
    private var isOpen = false

    private let revealWidth: CGFloat = 84

    func body(content: Content) -> some View {
        if enabled {
            ZStack(alignment: .trailing) {
                Button {
                    close()
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextInverse)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.tempoError)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(offset < -4 ? 1 : 0)
                .accessibilityHidden(true)

                content
                    .offset(x: offset)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }
                                let base: CGFloat = isOpen ? -revealWidth : 0
                                offset = min(0, max(-revealWidth - 16, base + value.translation.width))
                            }
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    if offset < -revealWidth / 2 {
                                        offset = -revealWidth
                                        isOpen = true
                                    } else {
                                        offset = 0
                                        isOpen = false
                                    }
                                }
                            }
                    )
            }
            .accessibilityAction(named: label, onDelete)
        } else {
            content
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            isOpen = false
        }
    }
}

extension View {
    /// Adds swipe-left-to-delete (plus a VoiceOver action named `label`).
    func swipeToDelete(enabled: Bool = true, label: String = "Delete", onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(enabled: enabled, label: label, onDelete: onDelete))
    }
}
