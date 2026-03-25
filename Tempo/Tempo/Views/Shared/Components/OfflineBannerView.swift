import SwiftUI

// MARK: - Offline Banner
// Per DESIGN_SYSTEM.md Section 8.8 — Banner:
// Warning style, full width, yellow tint bg, left accent bar.

struct OfflineBannerView: View {

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Color.tempoWarning
                .frame(width: 4)

            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoWarning)

                Text("You're offline. Data may be stale.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.vertical, TempoSpacing.md)
        }
        .frame(minHeight: 56)
        .background(Color.tempoRecoveryYellowBg)
    }
}
