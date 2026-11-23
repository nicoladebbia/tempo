//
// NumberStepperView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Number Stepper View

// A value with a round minus and plus either side. Buttons are 44 pt, the
// figure is a condensed tabular numeral that rolls as it changes. Hold a
// button to repeat; tap the value to type it when a handler is supplied.

struct NumberStepperView: View {
    @Binding
    var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let unit: String
    /// §4.3 — tap the value to type/wheel it instead of stepping. nil (the
    /// default) keeps the value display plain, matching every pre-existing
    /// call site.
    var onTapValue: (() -> Void)?

    @State
    private var timer: Timer?
    @State
    private var holdDuration: TimeInterval = 0
    @State
    private var steps = 0
    @ScaledMetric(relativeTo: .title3)
    private var figureSize: CGFloat = 22

    init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0 ... 999,
        step: Double = 2.5,
        format: String = "%.1f",
        unit: String = "kg",
        onTapValue: (() -> Void)? = nil
    ) {
        _value = value
        self.range = range
        self.step = step
        self.format = format
        self.unit = unit
        self.onTapValue = onTapValue
    }

    var body: some View {
        HStack(spacing: Tide.s1) {
            stepButton(icon: "minus", label: "Decrease", action: decrement)
                .simultaneousGesture(longPressGesture(action: decrement))

            // Tappable to type/wheel it when a handler is supplied (§4.3);
            // otherwise plain, unchanged text.
            Group {
                if let onTapValue {
                    Button(action: onTapValue) {
                        valueLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Type a value")
                } else {
                    valueLabel
                }
            }
            .frame(minWidth: 64)

            stepButton(icon: "plus", label: "Increase", action: increment)
                .simultaneousGesture(longPressGesture(action: increment))
        }
        .frame(minHeight: Tide.hit)
        .sensoryFeedback(.selection, trigger: steps)
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

    /// The number + unit text, shared by the tappable Button and the plain fallback.
    private var valueLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.hair) {
            Text(String(format: format, value))
                .font(Tide.numeral(figureSize))
                .foregroundStyle(Tide.text)
                .contentTransition(.numericText(value: value))
                .animation(Tide.snap, value: value)
                .underline(onTapValue != nil, color: Tide.text3)
            if !unit.isEmpty {
                Text(unit)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Tide.labelShrink)
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }

    private func stepButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func increment() {
        let newValue = min(value + step, range.upperBound)
        guard newValue != value else {
            return
        }
        value = newValue
        steps += 1
    }

    private func decrement() {
        let newValue = max(value - step, range.lowerBound)
        guard newValue != value else {
            return
        }
        value = newValue
        steps += 1
    }

    private func longPressGesture(action: @escaping @MainActor @Sendable () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                holdDuration = 0
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    Task { @MainActor in
                        holdDuration += 0.1
                        action()
                        // Accelerate after 2 seconds
                        if holdDuration > 2 {
                            timer?.invalidate()
                            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                                Task { @MainActor in
                                    action()
                                }
                            }
                        }
                    }
                }
            }
    }
}

#Preview {
    @Previewable @State
    var weight = 82.5

    NumberStepperView(value: $weight, onTapValue: {})
        .padding(Tide.edge)
        .tidePage()
}
