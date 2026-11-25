//
// NumericEntrySheet.swift
// Tempo
//
// Tap-to-type / scroll-wheel entry for weight and reps (MODULE_TRAINING
// §4.2-4.4). Typed values are clamped and snapped by the caller (weight →
// WeightConverter.loadableKg) so only loadable numbers are ever logged.
//
// The keys are the sheet's own, big and already on screen when it opens: no
// system keyboard to wait for, no field to aim at between sets.
//

import SwiftUI

// MARK: - NumericEntrySheet

// Per MODULE_TRAINING.md §4.2-4.4 — tap-the-value-to-type entry (a number pad
// that is part of the sheet, validated + snapped) plus a scroll-wheel
// alternative, for the active-workout weight/reps fields. Generic over both
// fields so one component backs the weight stepper, the bodyweight added-load
// stepper, and the reps stepper; the mode toggle lives only for the life of
// the sheet — there's no persisted global "input method" setting (§4.4 kept
// minimal).

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
        _text = State(
            initialValue: initialValue == 0
                ? ""
                : Self.sanitize(String(format: displayFormat, initialValue), allowNegative: range.lowerBound < 0)
        )
        _replaceOnType = State(initialValue: initialValue != 0)
        _wheelSelection = State(initialValue: Self.nearest(initialValue, in: wheelValues))
    }

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var mode: Mode = .type
    @State
    private var text: String
    /// True while the value shown is the one the sheet opened with: the first
    /// key replaces it, like typing over a selection.
    @State
    private var replaceOnType: Bool
    @State
    private var wheelSelection: Double
    @State
    private var saved = 0
    @State
    private var keyTaps = 0
    @ScaledMetric(relativeTo: .largeTitle)
    private var readoutSize: CGFloat = Tide.numeralReadout
    @ScaledMetric(relativeTo: .title)
    private var keySize: CGFloat = Tide.numeralKey

    enum Mode: String, CaseIterable {
        case type = "Type"
        case wheel = "Wheel"
    }

    /// A key on the pad.
    private enum Key: Hashable {
        case digit(Character)
        case dot
        case delete
    }

    private static let maxLength = 7

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
        guard let raw = WeightFormat.parseDecimal(text) else {
            return nil
        }
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return snap(clamped)
    }

    private var allowsNegative: Bool {
        range.lowerBound < 0
    }

    /// A decimal key only where a fraction can survive: when every value on the
    /// wheel is whole (reps, pounds in whole steps) the key would do nothing.
    private var allowsDecimal: Bool {
        // No wheel to judge by (no step or an empty range): keep the key, as
        // the old decimal pad always had it.
        wheelValues.isEmpty || wheelValues.contains { $0 != $0.rounded() }
    }

    /// Nothing typed yet but a minus sign: not wrong, just not finished.
    private var isInvalid: Bool {
        !text.isEmpty && text != "-" && parsedValue == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tide.s4) {
                    Picker("Input method", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .type:
                        typeContent
                    case .wheel:
                        wheelContent
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    let value = mode == .type ? (parsedValue ?? initialValue) : snap(wheelSelection)
                    onSave(value)
                    saved += 1
                    dismiss()
                } label: {
                    Text("Set \(title)")
                }
                .buttonStyle(.tidePrimary)
                .disabled(saveDisabled)
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
                .sensoryFeedback(.success, trigger: saved)
            }
            .tidePage()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // At accessibility sizes the keypad needs the whole sheet to show its last row.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(Tide.keypadSheetHeight), .large])
        .presentationCornerRadius(Tide.cardRadius)
    }

    private var saveDisabled: Bool {
        mode == .type && parsedValue == nil
    }

    // MARK: Type

    private var typeContent: some View {
        VStack(spacing: Tide.s4) {
            readout
            keypad
        }
    }

    /// The number being typed, as big as the sheet allows, with what it will
    /// be saved as (or why it can't be) under it.
    private var readout: some View {
        VStack(spacing: Tide.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                if allowsNegative {
                    signKey
                }
                Text(text.isEmpty ? "0" : text)
                    .font(Tide.numeral(readoutSize))
                    .foregroundStyle(readoutColor)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .contentTransition(.numericText())
                    .animation(Tide.snap, value: text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)

            hint
                .font(Tide.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Tide.s5)
        }
        .padding(.vertical, Tide.s4)
        .tideFieldSurface(focused: true, invalid: isInvalid)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text.isEmpty ? "Empty" : "\(text) \(unit)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var readoutColor: Color {
        if text.isEmpty {
            return Tide.text3
        }
        return replaceOnType ? mood.accent : Tide.text
    }

    @ViewBuilder
    private var hint: some View {
        if let parsed = parsedValue {
            Text("Snaps to \(String(format: displayFormat, parsed)) \(unit)")
                .foregroundStyle(Tide.text2)
        } else if isInvalid {
            Text(
                "Enter a number between \(String(format: displayFormat, range.lowerBound)) and \(String(format: displayFormat, range.upperBound))"
            )
            .foregroundStyle(Tide.carbs)
        } else {
            Text(" ")
        }
    }

    /// Flips the minus sign, for the fields that can go below zero (added
    /// load on a bodyweight lift).
    private var signKey: some View {
        Button {
            keyTaps += 1
            // Flips the sign of what is shown, so the next digit adds to it.
            replaceOnType = false
            text = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text
        } label: {
            Image(systemName: "plusminus")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plus or minus")
    }

    // MARK: Keypad

    private var keypad: some View {
        Grid(horizontalSpacing: Tide.s2, verticalSpacing: Tide.s2) {
            ForEach(0 ..< 3) { row in
                GridRow {
                    ForEach(1 ... 3, id: \.self) { column in
                        keyButton(.digit(Character(String(row * 3 + column))))
                    }
                }
            }
            GridRow {
                if allowsDecimal {
                    keyButton(.dot)
                } else {
                    Color.clear.frame(height: Tide.keyHeight)
                }
                keyButton(.digit("0"))
                keyButton(.delete)
            }
        }
        // Digits stay a comfortable size at any text size; the keys do not grow past the sheet.
        .dynamicTypeSize(...Tide.dialTextCap)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.5), trigger: keyTaps)
    }

    private func keyButton(_ key: Key) -> some View {
        let button = Button {
            keyTaps += 1
            press(key)
        } label: {
            keyLabel(key)
                .frame(maxWidth: .infinity, minHeight: Tide.keyHeight)
        }
        .buttonStyle(TideKeyStyle())
        .accessibilityLabel(keyName(key))

        return Group {
            if key == .delete {
                // Hold to clear the whole number.
                button
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            keyTaps += 1
                            replaceOnType = false
                            text = ""
                        }
                    )
                    .accessibilityAction(named: "Clear") {
                        replaceOnType = false
                        text = ""
                    }
            } else {
                button
            }
        }
    }

    @ViewBuilder
    private func keyLabel(_ key: Key) -> some View {
        switch key {
        case let .digit(character):
            Text(String(character))
                .font(Tide.numeral(keySize, .semibold))
        case .dot:
            Text(".")
                .font(Tide.numeral(keySize, .semibold))
        case .delete:
            Image(systemName: "delete.left")
                .font(Tide.headline)
        }
    }

    private func keyName(_ key: Key) -> String {
        switch key {
        case let .digit(character): String(character)
        case .dot: "Decimal point"
        case .delete: "Delete"
        }
    }

    private func press(_ key: Key) {
        switch key {
        case let .digit(character):
            edit { current in
                // A lone zero is replaced, not followed ("05").
                if current == "0" || current == "-0" {
                    return String(current.dropLast()) + String(character)
                }
                return current + String(character)
            }
        case .dot:
            edit { current in
                if current.contains(".") {
                    return current
                }
                return current.isEmpty || current == "-" ? current + "0." : current + "."
            }
        case .delete:
            edit { String($0.dropLast()) }
        }
    }

    /// Applies a keypress to the typed text: the first one replaces the value
    /// the sheet opened with, and the result always goes through `sanitize`.
    private func edit(_ change: (String) -> String) {
        let start = replaceOnType ? "" : text
        replaceOnType = false
        let next = Self.sanitize(change(start), allowNegative: allowsNegative)
        if next.count <= Self.maxLength {
            text = next
        }
    }

    // MARK: Wheel

    private var wheelContent: some View {
        Picker(title, selection: $wheelSelection) {
            ForEach(wheelValues, id: \.self) { value in
                Text("\(String(format: displayFormat, value)) \(unit)")
                    // A wheel row has a fixed height: past this the digits overlap.
                    .font(Tide.numeral(min(keySize, Tide.numeralWheelMax), .semibold))
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: Tide.wheelHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .sensoryFeedback(.selection, trigger: wheelSelection)
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
