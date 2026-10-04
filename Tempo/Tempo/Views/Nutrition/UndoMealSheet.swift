//
// UndoMealSheet.swift
// Tempo
//
// Confirmation for "Mark as not eaten" / "Delete log" on the meal page. A
// bottom sheet instead of a confirmationDialog: on iOS 26 the dialog rendered
// as a small clipped bubble with no Cancel. This one says what will happen.
//

import SwiftUI

struct UndoMealSheet: View {
    let mealName: String
    let kcal: Int
    /// An unplanned log (Quick Log, photo, scan) is deleted; a plan slot goes
    /// back to "planned".
    let isLog: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
        VStack(spacing: TempoSpacing.lg) {
            VStack(spacing: TempoSpacing.xs) {
                Image(systemName: isLog ? "trash.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.tempoError)
                    .accessibilityHidden(true)
                Text(isLog ? "Delete this log?" : "Mark as not eaten?")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("\(mealName) · \(kcal) kcal")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                consequence("minus.circle.fill", "Removes it from today's totals.")
                consequence("refrigerator.fill", "Puts pantry items back.")
                if !isLog {
                    consequence("calendar.badge.clock", "Goes back on the plan as planned.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()

            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button(action: onConfirm) {
                    Text(isLog ? "Delete log" : "Mark as not eaten")
                        .font(.tempoSubheadline.weight(.semibold))
                        .foregroundStyle(Color.tempoTextInverse)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.tempoError)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("undoMealConfirm")
                Button("Keep it", action: onCancel)
                    .buttonStyle(.tempoGhost)
                    .accessibilityIdentifier("undoMealCancel")
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.xl)
        .padding(.bottom, TempoSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.tempoBgPrimary)
    }

    private func consequence(_ icon: String, _ text: String) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 22)
            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
