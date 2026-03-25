import SwiftUI

// MARK: - Prescription Card (Drill Sergeant Message)
// Per DESIGN_SYSTEM.md Section 8.2 — Prescription Card:
// Ink Black bg (BOTH modes), Signal Red left accent 4pt, drill sergeant glow shadow.

struct PrescriptionCardView: View {

    let message: String
    let timestamp: String

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Color.tempoSignal
                .frame(width: 4)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("DRILL SERGEANT")
                    .font(.tempoDrillLabel)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoAmber)

                Text(message)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoBone)

                HStack {
                    Spacer()
                    Text(timestamp)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoAsh)
                }
            }
            .padding(TempoSpacing.cardPadding)
        }
        .background(Color.tempoInk)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .shadow(
            color: Color.tempoSignal.opacity(0.15),
            radius: 8, x: 0, y: 0
        )
    }
}
