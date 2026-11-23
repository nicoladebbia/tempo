//
// ManualWeighInSheet.swift
// Tempo
//
// Big, simple weight entry for when the Withings reading isn't in Health.
// Before/after the session sets a sensible default time; kg or lb.
// Field errors are shown in the sheet, never in a system alert.
//

import SwiftUI

struct ManualWeighInSheet: View {
    enum When: String, CaseIterable {
        case before = "Before the session"
        case after = "After the session"
    }

    let session: CoachSession
    /// The weigh-in the screen asked for first: after the session when that one is missing.
    let startsWithAfter: Bool
    let onSave: (_ kg: Double, _ time: Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tideMood) private var mood
    @State private var text = ""
    @State private var useLb: Bool
    @State private var when: When
    @State private var time: Date
    @State private var error: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var weightSize: CGFloat = Tide.numeralL
    @ScaledMetric(relativeTo: .body) private var unitWidth: CGFloat = Tide.s10 * 3

    init(session: CoachSession, startsWithAfter: Bool, onSave: @escaping (Double, Date) -> Void) {
        self.session = session
        self.startsWithAfter = startsWithAfter
        self.onSave = onSave
        let startWhen: When = startsWithAfter ? .after : .before
        _when = State(initialValue: startWhen)
        _time = State(initialValue: Self.defaultTime(for: startWhen, session: session))
        _useLb = State(initialValue: Locale.current.measurementSystem == .us)
    }

    static func defaultTime(for when: When, session: CoachSession, now: Date = Date()) -> Date {
        switch when {
        case .before: session.start.addingTimeInterval(-10 * 60)
        case .after: max(now, session.end)
        }
    }

    /// kg from what was typed, or nil when it is not a plausible body weight.
    static func kg(from text: String, useLb: Bool) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else {
            return nil
        }
        let kg = useLb ? value * 0.45359237 : value
        return RecoveryWeighIns.plausibleKg.contains(kg) ? kg : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Tide.s3) {
                Text("Your weight")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tide.s2)
                FuelIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s4)

            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    Picker("When", selection: $when) {
                        ForEach(When.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: when) { _, new in time = Self.defaultTime(for: new, session: session) }
                    .sensoryFeedback(.selection, trigger: when)

                    HStack(alignment: .center, spacing: Tide.s3) {
                        TextField(useLb ? "172" : "78.0", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(Tide.numeral(weightSize))
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("coach.weightField")
                        Picker("Unit", selection: $useLb) {
                            Text("kg").tag(false)
                            Text("lb").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: unitWidth)
                        .sensoryFeedback(.selection, trigger: useLb)
                    }
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

                    DatePicker("Time", selection: $time, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .tint(mood.accent)
                        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

                    if let error {
                        Text(error)
                            .font(Tide.body)
                            .foregroundStyle(Tide.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coach.weightError")
                    }

                    Button("Save weight") { save() }
                        .buttonStyle(.tidePrimary)
                        .accessibilityIdentifier("coach.saveWeight")

                    Text(
                        "Same clothes (or none), towel-dry, after the toilet, before you drink. A weight from the 3 hours before the session works as your \"before\"."
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s5)
                .padding(.bottom, Tide.s8)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .tidePage()
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear { focused = true }
    }

    private func save() {
        guard let kg = Self.kg(from: text, useLb: useLb) else {
            error = "That doesn't look like a body weight. Enter \(useLb ? "pounds, like 172" : "kilograms, like 78.0")."
            return
        }
        onSave(kg, time)
        dismiss()
    }
}
