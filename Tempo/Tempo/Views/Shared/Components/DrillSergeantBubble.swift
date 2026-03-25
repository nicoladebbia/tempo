import SwiftUI

// MARK: - Drill Sergeant Speech Bubble
// Per DESIGN_SYSTEM.md Section 8.2 — Prescription Card variant:
// Ink Black bg, Signal Red accent, bold drill-sergeant copy.

struct DrillSergeantBubble: View {

    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.tempoSignal)

                Text("ORDERS")
                    .font(.tempoOrdersLabel)
                    .tracking(TempoTracking.ordersLabel)
                    .foregroundStyle(Color.tempoAmber)
            }

            Text(message)
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoBone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoInk)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .shadow(
            color: Color.tempoSignal.opacity(0.15),
            radius: 8, x: 0, y: 0
        )
    }
}
