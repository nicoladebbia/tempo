import SwiftUI

// MARK: - Stale Data Indicator
// Amber dot indicating data is older than 15 minutes.

struct StaleDataIndicator: View {

    let lastUpdated: Date
    let threshold: TimeInterval

    init(lastUpdated: Date, threshold: TimeInterval = 900) {
        self.lastUpdated = lastUpdated
        self.threshold = threshold
    }

    private var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > threshold
    }

    var body: some View {
        if isStale {
            HStack(spacing: TempoSpacing.xs) {
                Circle()
                    .fill(Color.tempoAmber)
                    .frame(width: 6, height: 6)
                Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .accessibilityLabel("Data is stale. Last updated \(lastUpdated, format: .relative(presentation: .named))")
        }
    }
}
