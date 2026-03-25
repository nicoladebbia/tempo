import SwiftUI

// MARK: - Score Ring View
// Per DESIGN_SYSTEM.md Section 8.6 — Circular Progress Ring:
// Angular gradient fill, round end cap, center score display, spring animation.

struct ScoreRingView: View {

    let score: Double
    let maxScore: Double
    let label: String
    let size: CGFloat
    let strokeWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress: Double = 0

    init(
        score: Double,
        maxScore: Double = 100,
        label: String = "",
        size: CGFloat = 200,
        strokeWidth: CGFloat = 12
    ) {
        self.score = score
        self.maxScore = maxScore
        self.label = label
        self.size = size
        self.strokeWidth = strokeWidth
    }

    private var progress: Double {
        guard maxScore > 0 else { return 0 }
        return min(score / maxScore, 1.0)
    }

    private var trackColor: Color {
        colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)  // #38383A
            : Color.tempoBorder
    }

    /// Per MODULE_DASHBOARD.md — 100pt ring uses 34pt, larger rings use 64pt/48pt.
    private var scoreFont: Font {
        if size >= 200 {
            return .tempoScoreDisplay        // 64pt for large rings
        } else if size <= 120 {
            return .tempoXPDisplay            // 36pt for dashboard 100pt ring
        } else {
            return .tempoScoreDisplaySmall   // 48pt for medium rings
        }
    }

    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 1, green: 77 / 255, blue: 90 / 255), Color.tempoSignal]  // #FF4D5A → #E63946
            : [Color.tempoSignal, Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)]  // #E63946 → #DC2626
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

            // Fill
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(animatedProgress * 360 - 90)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: TempoSpacing.xxs) {
                Text("\(Int(score))")
                    .font(scoreFont)
                    .tracking(size >= 200 ? TempoTracking.scoreDisplay : TempoTracking.scoreDisplaySmall)
                    .foregroundStyle(Color.tempoTextPrimary)

                if !label.isEmpty {
                    Text(label)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animatedProgress = progress
            }
        }
        .onChange(of: score) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = progress
            }
        }
        .accessibilityLabel("\(label.isEmpty ? "Score" : label): \(Int(score)) out of \(Int(maxScore))")
    }
}
