import SwiftUI

// MARK: - Number Stepper View
// Per DESIGN_SYSTEM.md Section 8.5 — Number Stepper:
// Minus/Plus buttons (36pt circle), value display (Data Medium), long press acceleration.

struct NumberStepperView: View {

    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let unit: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var timer: Timer?
    @State private var holdDuration: TimeInterval = 0

    init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...999,
        step: Double = 2.5,
        format: String = "%.1f",
        unit: String = "kg"
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.unit = unit
    }

    private var buttonBackground: Color {
        colorScheme == .dark
            ? Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
            : Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Minus button
            stepButton(icon: "minus", action: decrement)
                .simultaneousGesture(longPressGesture(action: decrement))

            // Value display
            HStack(spacing: TempoSpacing.xxs) {
                Text(String(format: format, value))
                    .font(.tempoDataMedium)
                    .foregroundStyle(Color.tempoTextPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .frame(minWidth: 60)

            // Plus button
            stepButton(icon: "plus", action: increment)
                .simultaneousGesture(longPressGesture(action: increment))
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(String(format: format, value)) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(width: 36, height: 36)
                .background(buttonBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }

    private func increment() {
        let newValue = min(value + step, range.upperBound)
        guard newValue != value else { return }
        value = newValue
        HapticManager.lightImpact()
    }

    private func decrement() {
        let newValue = max(value - step, range.lowerBound)
        guard newValue != value else { return }
        value = newValue
        HapticManager.lightImpact()
    }

    private func longPressGesture(action: @escaping () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                holdDuration = 0
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    holdDuration += 0.1
                    action()
                    // Accelerate after 2 seconds
                    if holdDuration > 2 {
                        timer?.invalidate()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                            action()
                        }
                    }
                }
            }
    }
}
