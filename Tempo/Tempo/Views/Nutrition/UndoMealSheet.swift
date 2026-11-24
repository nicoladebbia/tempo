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
            VStack(spacing: Tide.s5) {
                VStack(spacing: Tide.s2) {
                    TideIconTile(
                        systemName: isLog ? "trash.fill" : "arrow.uturn.backward",
                        tint: Tide.danger,
                        size: Tide.tileLarge
                    )
                    .accessibilityHidden(true)
                    Text(isLog ? "Delete this log?" : "Mark as not eaten?")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                    Text("\(mealName) · \(kcal) kcal")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Tide.s3) {
                    consequence("minus.circle.fill", "Removes it from today's totals.")
                    consequence("refrigerator.fill", "Puts pantry items back.")
                    if !isLog {
                        consequence("calendar.badge.clock", "Goes back on the plan as planned.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s6)
            .padding(.bottom, Tide.s3)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The answers sit under the thumb, whatever the text size.
        .fuelBottomBar {
            VStack(spacing: Tide.s2) {
                Button(action: onConfirm) {
                    Text(isLog ? "Delete log" : "Mark as not eaten")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.fuelDestructive)
                .accessibilityIdentifier("undoMealConfirm")
                Button("Keep it", action: onCancel)
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("undoMealCancel")
            }
        }
        .tidePage()
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
    }

    private func consequence(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .frame(width: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
