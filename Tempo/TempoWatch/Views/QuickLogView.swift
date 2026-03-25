import SwiftUI

// MARK: - Quick Log View
// Per APPLE_WATCH_APP.md Section 3.5 — Rapid actions from wrist.
// Tap to check off non-negotiables. No keyboards, no text input.

struct QuickLogView: View {
    let connectivity: WatchConnectivityService

    var body: some View {
        let data = connectivity.latestSnapshot
        ScrollView {
            VStack(spacing: 8) {
                Text("QUICK LOG")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                // Non-negotiable items
                ForEach(0..<data.nnTotal, id: \.self) { idx in
                    Button {
                        WatchHapticService.playNonNegotiableComplete()
                        connectivity.sendAction(.markNonNegotiableDone, payload: [
                            "index": "\(idx)"
                        ])
                    } label: {
                        HStack {
                            Image(systemName: idx < data.nnCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(idx < data.nnCompleted ? .green : .secondary)
                            Text("Task \(idx + 1)")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(idx < data.nnCompleted)
                }

                // Log meal button
                Button {
                    connectivity.sendAction(.markMealEaten)
                } label: {
                    HStack {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.orange)
                        Text("Log Meal")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
    }
}
