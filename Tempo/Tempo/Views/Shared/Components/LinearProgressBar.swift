import SwiftUI

// MARK: - Linear Progress Bar
// Per DESIGN_SYSTEM.md Section 8.6 — Linear Progress Bar:
// 6pt default height, fully rounded, spring fill animation.

struct LinearProgressBar: View {

    let progress: Double
    let label: String
    let color: Color
    let height: CGFloat
    let showPercentage: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress: Double = 0

    init(
        progress: Double,
        label: String = "",
        color: Color = .tempoSignal,
        height: CGFloat = 6,
        showPercentage: Bool = true
    ) {
        self.progress = min(max(progress, 0), 1.5)  // Allow up to 150% for overfill
        self.label = label
        self.color = color
        self.height = height
        self.showPercentage = showPercentage
    }

    private var trackColor: Color {
        colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
            : Color.tempoBorder
    }

    private var fillColor: Color {
        progress > 1.0 ? Color.tempoSuccess : color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            if !label.isEmpty || showPercentage {
                HStack {
                    if !label.isEmpty {
                        Text(label)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    Spacer()
                    if showPercentage {
                        Text("\(Int(min(progress, 1.0) * 100))%")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(trackColor)
                        .frame(height: height)

                    // Fill
                    Capsule()
                        .fill(fillColor)
                        .frame(
                            width: min(animatedProgress, 1.0) * geometry.size.width,
                            height: height
                        )
                }
            }
            .frame(height: height)
        }
        .onAppear {
            withAnimation(TempoAnimation.springData.delay(0.1)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) {
            withAnimation(TempoAnimation.springData) {
                animatedProgress = progress
            }
        }
        .accessibilityLabel("\(label.isEmpty ? "Progress" : label): \(Int(min(progress, 1.0) * 100)) percent")
    }
}
