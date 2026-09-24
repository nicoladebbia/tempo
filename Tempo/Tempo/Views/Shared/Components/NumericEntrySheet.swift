//
// NumericEntrySheet.swift
// Tempo
//
// Tap-to-type / scroll-wheel entry for weight and reps (MODULE_TRAINING
// §4.2-4.4). Typed values are clamped and snapped by the caller (weight →
// WeightConverter.loadableKg) so only loadable numbers are ever logged.
//

import SwiftUI

// MARK: - NumericEntrySheet

// Per MODULE_TRAINING.md §4.2-4.4 — tap-the-value-to-type entry (decimal
// keypad, validated + snapped) plus a scroll-wheel alternative, for the
// active-workout weight/reps fields. Generic over both fields so one
// component backs the weight stepper, the bodyweight added-load stepper, and
// the reps stepper; the mode toggle lives only for the life of the sheet —
// there's no persisted global "input method" setting (§4.4 kept minimal).

struct NumericEntrySheet: View {
    let title: String
    let unit: String
    let initialValue: Double
    let range: ClosedRange<Double>
    /// Values the wheel picker scrolls through — already loadable/snapped
    /// (e.g. built from `WeightConverter.increment(for:unit:)`).
    let wheelValues: [Double]
    let displayFormat: String
    /// Applied to whatever the keypad parses before it reaches `onSave` —
    /// e.g. `WeightConverter.loadableKg` for weight, identity for reps.
    let snap: (Double) -> Double
    let onSave: (Double) -> Void

    init(
        title: String,
        unit: String,
        initialValue: Double,
        range: ClosedRange<Double>,
        wheelValues: [Double],
        displayFormat: String = "%.1f",
        snap: @escaping (Double) -> Double = { $0 },
        onSave: @escaping (Double) -> Void
    ) {
        self.title = title
        self.unit = unit
        self.initialValue = initialValue
        self.range = range
        self.wheelValues = wheelValues
        self.displayFormat = displayFormat
        self.snap = snap
        self.onSave = onSave
        _text = State(initialValue: initialValue == 0 ? "" : String(format: displayFormat, initialValue))
        _wheelSelection = State(initialValue: Self.nearest(initialValue, in: wheelValues))
    }

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.colorScheme)
    private var colorScheme
    @State
    private var mode: Mode = .type
    @State
    private var text: String
    @State
    private var wheelSelection: Double
    @FocusState
    private var keypadFocused: Bool

    enum Mode: String, CaseIterable {
        case type = "Type"
        case wheel = "Wheel"
    }

    private static func nearest(_ value: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else {
            return value
        }
        return values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    /// Parsed + range-clamped + snapped preview value, nil while the field is
    /// empty or unparsable.
    private var parsedValue: Double? {
        Self.parseAndSnap(text, range: range, snap: snap)
    }

    /// Parse typed text into a range-clamped, snapped value — pure and
    /// testable independent of SwiftUI state; `parsedValue` above is just
    /// this applied to the live `text`/`range`/`snap`. nil for empty or
    /// unparsable input.
    static func parseAndSnap(_ text: String, range: ClosedRange<Double>, snap: (Double) -> Double) -> Double? {
        guard let raw = Double(text) else {
            return nil
        }
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return snap(clamped)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.tempoInputBgDark : Color.tempoInputBgLight
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.lg) {
                Picker("Input method", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.sm)

                switch mode {
                case .type: typeContent
                case .wheel: wheelContent
                }

                Spacer(minLength: 0)

                Button {
                    let value = mode == .type ? (parsedValue ?? initialValue) : snap(wheelSelection)
                    onSave(value)
                    dismiss()
                } label: {
                    Text("Set \(title)")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(saveDisabled ? Color.tempoTextTertiary.opacity(0.3) : Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .disabled(saveDisabled)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.md)
            }
            .background(Color.tempoBgPrimary.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { keypadFocused = false }
                }
            }
            .onAppear {
                if mode == .type {
                    keypadFocused = true
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(TempoRadius.xxxxl)
    }

    private var saveDisabled: Bool {
        mode == .type && parsedValue == nil
    }

    private var typeContent: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($keypadFocused)
                    .font(.tempoDataLarge)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize()
                    .onChange(of: text) { _, newValue in
                        let sanitized = Self.sanitize(newValue, allowNegative: range.lowerBound < 0)
                        if sanitized != newValue {
                            text = sanitized
                        }
                    }
                if !unit.isEmpty {
                    Text(unit)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            .padding(.horizontal, TempoSpacing.screenEdge)

            if let parsed = parsedValue {
                Text("Snaps to \(String(format: displayFormat, parsed)) \(unit)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else if !text.isEmpty {
                Text(
                    "Enter a number between \(String(format: displayFormat, range.lowerBound)) and \(String(format: displayFormat, range.upperBound))"
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoWarning)
            }
        }
    }

    private var wheelContent: some View {
        Picker(title, selection: $wheelSelection) {
            ForEach(wheelValues, id: \.self) { value in
                Text("\(String(format: displayFormat, value)) \(unit)")
                    .font(.tempoBody)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxHeight: 180)
        .clipped()
    }

    /// Keep only digits, at most one decimal separator (comma normalized to
    /// dot), and a leading minus when the range allows negatives (the
    /// bodyweight added-load field) — a hand-rolled filter so a bad paste
    /// can never wedge the field into an unparsable state.
    static func sanitize(_ input: String, allowNegative: Bool) -> String {
        var seenDot = false
        var result = ""
        for (index, ch) in input.enumerated() {
            if ch == "-", index == 0, allowNegative {
                result.append(ch)
            } else if ch == "." || ch == ",", !seenDot {
                result.append(".")
                seenDot = true
            } else if ch.isNumber {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Wheel Value Builders

extension NumericEntrySheet {
    /// Loadable weight values from 0 (or a negative floor, for added-load
    /// fields) up to `max`, stepped by the equipment/unit-aware increment —
    /// every value on the wheel is already a real, plate-loadable number.
    static func weightWheelValues(
        step: Double,
        lowerBound: Double = 0,
        upperBound: Double
    ) -> [Double] {
        guard step > 0, upperBound > lowerBound else {
            return []
        }
        var values: [Double] = []
        var v = lowerBound
        while v <= upperBound + 0.001 {
            values.append((v / step).rounded() * step)
            v += step
        }
        return values
    }

    /// Whole-number wheel values (reps).
    static func intWheelValues(_ range: ClosedRange<Int>) -> [Double] {
        range.map(Double.init)
    }
}
