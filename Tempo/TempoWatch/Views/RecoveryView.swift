import SwiftUI

// MARK: - Recovery View
// Per APPLE_WATCH_APP.md — Recovery summary on Watch.
// Shows zone, recovery score, HRV, RHR, sleep hours.

struct RecoveryView: View {
    let connectivity: WatchConnectivityService

    var body: some View {
        let data = connectivity.latestSnapshot
        ScrollView {
            VStack(spacing: 12) {
                Text("RECOVERY")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                // Zone badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(zoneColor(data.recoveryZone))
                        .frame(width: 12, height: 12)
                    Text(data.recoveryZone.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(zoneColor(data.recoveryZone))
                }

                Text("\(data.recoveryScore)%")
                    .font(.system(size: 36, weight: .bold))

                // Stats
                VStack(spacing: 6) {
                    statRow(label: "HRV", value: String(format: "%.0f ms", data.hrv))
                    statRow(label: "RHR", value: "\(data.rhr) bpm")
                    statRow(label: "Sleep", value: String(format: "%.1fh", data.sleepHours))
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 4)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 10)
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        default: return .green
        }
    }
}
