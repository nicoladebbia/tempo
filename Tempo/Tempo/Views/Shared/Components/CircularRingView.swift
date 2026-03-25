import SwiftUI

// MARK: - Circular Ring View (Activity Ring Style)
// Per DESIGN_SYSTEM.md Section 8.6 — Score Ring (Activity Ring Style):
// Thin ring, configurable size/color, round end cap, gradient fill.

struct CircularRingView: View {

    let progress: Double
    let color: Color
    let size: CGFloat
    let strokeWidth: CGFloat
    let label: String
    let valueText: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress: Double = 0

    enum RingSize {
        case small, medium, large, extraLarge

        var diameter: CGFloat {
            switch self {
            case .small: 40
            case .medium: 64
            case .large: 120
            case .extraLarge: 200
            }
        }

        var stroke: CGFloat {
            switch self {
            case .small: 4
            case .medium: 6
            case .large: 8
            case .extraLarge: 12
            }
        }
    }

    init(
        progress: Double,
        color: Color = .tempoSignal,
        size: CGFloat = 64,
        strokeWidth: CGFloat = 6,
        label: String = "",
        valueText: String = ""
    ) {
        self.progress = min(max(progress, 0), 1.0)
        self.color = color
        self.size = size
        self.strokeWidth = strokeWidth
        self.label = label
        self.valueText = valueText
    }

    init(progress: Double, color: Color = .tempoSignal, ringSize: RingSize, label: String = "", valueText: String = "") {
        self.progress = min(max(progress, 0), 1.0)
        self.color = color
        self.size = ringSize.diameter
        self.strokeWidth = ringSize.stroke
        self.label = label
        self.valueText = valueText
    }

    private var trackColor: Color {
        color.opacity(0.20)
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

            // Fill
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Center content
            if !valueText.isEmpty || !label.isEmpty {
                VStack(spacing: 0) {
                    if !valueText.isEmpty {
                        Text(valueText)
                            .font(size >= 120 ? .tempoDataLarge : .tempoDataSmall)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    if !label.isEmpty {
                        Text(label)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                animatedProgress = progress
            }
            if progress >= 1.0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: progress) {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = progress
            }
        }
        .accessibilityLabel("\(label.isEmpty ? "Progress" : label): \(Int(progress * 100)) percent")
    }
}
