//
// FuelSetupComponents.swift
// Tempo
//
// The building blocks of the Fuel setup flows: a one-question-per-screen
// scaffold with progress dots and Back/Next, tappable choice tiles, steppers
// and number fields that sit several to a screen, a chip list, and the Apple
// Health badge. Built from the Tide tokens: glass tiles for choices, soft
// fills for inputs, one accent-filled button at the bottom and a quiet Skip
// for optional questions.
//

import SwiftUI

// MARK: - FuelFlowScaffold

struct FuelFlowScaffold<Content: View>: View {
    /// The section this question belongs to, small and tinted above the title.
    var eyebrow: String?
    let title: String
    var subtitle: String?
    let index: Int
    let count: Int
    var canContinue = true
    var isSaving = false
    var isLast = false
    /// Label of the primary button on the last screen ("Save", "Save & next: Goal").
    var lastTitle = String(localized: "Save")
    /// Optional questions can be skipped; nil hides the button.
    var onSkip: (() -> Void)?
    /// Shown in the top bar once something changed ("Save & close"); nil hides it.
    var onSaveAndClose: (() -> Void)?
    var canSaveAndClose = true
    /// "Skip section" in the top bar (finish chains, optional sections only).
    var onSkipSection: (() -> Void)?
    var onBack: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void
    @ViewBuilder
    var content: () -> Content

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s6) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        if let eyebrow, eyebrow.caseInsensitiveCompare(title) != .orderedSame {
                            Text(eyebrow)
                                .tideLabel(mood.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(title)
                            .font(Tide.title)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s3)
                .padding(.bottom, Tide.s5)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .fuelBottomBar { bottomBar }
        }
        .tidePage()
        .dismissKeyboardOnTapOutside()
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fuelFlowClose")
            Spacer()
            HStack(spacing: Tide.s1) {
                ForEach(0 ..< max(count, 1), id: \.self) { dot in
                    Capsule()
                        .fill(dot <= index ? mood.accent : Tide.text3.opacity(0.5))
                        .frame(width: dot == index ? Tide.s6 : Tide.s2, height: Tide.s2)
                        .animation(Tide.snap, value: index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(count)")
            Spacer()
            topTrailing
                .frame(minWidth: Tide.hit, minHeight: Tide.hit, alignment: .trailing)
        }
        .padding(.horizontal, Tide.s4)
        .padding(.top, Tide.s1)
    }

    @ViewBuilder
    private var topTrailing: some View {
        if let onSaveAndClose {
            Button("Save & close") {
                HapticManager.lightImpact()
                onSaveAndClose()
            }
            .buttonStyle(.tideGlass)
            .opacity(canSaveAndClose && !isSaving ? 1 : 0.45)
            .disabled(!canSaveAndClose || isSaving)
            .accessibilityIdentifier("fuelFlowSaveClose")
        } else if let onSkipSection {
            Button("Skip section", action: onSkipSection)
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("fuelFlowSkipSection")
        } else {
            Color.clear.frame(width: Tide.hit, height: Tide.hit)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Tide.s2) {
            HStack(spacing: Tide.s3) {
                if index > 0 {
                    Button {
                        HapticManager.selection()
                        onBack()
                    } label: {
                        Text("Back")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .padding(.horizontal, Tide.s5)
                            .frame(minHeight: Tide.hit + Tide.s2)
                            .background(Tide.fill, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(FuelPressStyle())
                    .accessibilityIdentifier("fuelFlowBack")
                }
                Button {
                    HapticManager.lightImpact()
                    onNext()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(Tide.ink)
                        } else {
                            Text(isLast ? lastTitle : String(localized: "Next"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .disabled(!canContinue || isSaving)
                .accessibilityIdentifier(isLast ? "fuelFlowSave" : "fuelFlowNext")
            }
            if let onSkip {
                Button(action: onSkip) {
                    Text("Optional · Skip")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Skip this question")
                .accessibilityIdentifier("fuelFlowSkip")
            }
        }
    }
}

// MARK: - FuelChoiceCard

/// A tall tappable answer (radio or multi-select look): one glass tile, an
/// accent outline and a tick when chosen.
struct FuelChoiceCard: View {
    let title: String
    var subtitle: String?
    var icon: String?
    let isSelected: Bool
    var action: () -> Void

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .headline)
    private var iconBox: CGFloat = Tide.icon + Tide.s2

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack(spacing: Tide.s3) {
                if let icon {
                    Image(systemName: icon)
                        .font(Tide.headline)
                        .foregroundStyle(isSelected ? mood.accent : Tide.text2)
                        .frame(width: iconBox, height: iconBox)
                        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.title2)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: iconBox)
            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(mood.accent, lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(FuelPressStyle())
        .animation(Tide.snap, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - FuelBigStepper

/// A compact number with − / + buttons. `defaultValue` shows (and commits on
/// appear) when unset. With a `label` it reads as one row of a multi-question
/// screen.
struct FuelBigStepper: View {
    @Binding
    var value: Int?
    let defaultValue: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit: String
    var label: String?
    var id: String

    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var current: Int {
        value ?? defaultValue
    }

    var body: some View {
        rowLayout {
            if let label {
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
            }
            controls
        }
        .padding(.vertical, Tide.s2)
        .frame(maxWidth: .infinity)
        .fuelField(radius: Tide.tileRadius)
        .animation(Tide.snap, value: current)
        .onAppear {
            if value == nil {
                value = defaultValue
            }
        }
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
    }

    private var controls: some View {
        GlassEffectContainer(spacing: Tide.s1) {
            HStack(spacing: Tide.s2) {
                button("minus", enabled: current - step >= range.lowerBound) {
                    value = max(range.lowerBound, current - step)
                }
                VStack(spacing: Tide.hair) {
                    TideNumber("\(current)", size: Tide.numeralM)
                    Text(unit)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(1)
                }
                .frame(minWidth: Tide.s8 * 2, maxWidth: label == nil ? CGFloat.infinity : nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label.map { "\($0) " } ?? "")\(current) \(unit)")
                .accessibilityIdentifier(id)
                button("plus", enabled: current + step <= range.upperBound) {
                    value = min(range.upperBound, current + step)
                }
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(Tide.bodyStrong)
                .foregroundStyle(enabled ? Tide.text : Tide.text3)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? String(localized: "More") : String(localized: "Less"))
    }
}

// MARK: - FuelNumberField

/// A numeric answer with its unit; with a `label` it is one row of a
/// multi-question screen.
struct FuelNumberField: View {
    @Binding
    var value: Double?
    let unit: String
    var label: String?
    var keyboard: UIKeyboardType = .decimalPad
    var id: String

    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .title)
    private var numeralSize: CGFloat = Tide.numeralSheet

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    labelView
                    valueRow
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    labelView
                    valueRow
                }
            }
        }
        .padding(.vertical, Tide.s2)
        .frame(maxWidth: .infinity)
        .fuelField(radius: Tide.tileRadius)
    }

    @ViewBuilder
    private var labelView: some View {
        if let label {
            Text(label)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            TextField("—", value: $value, format: .number.precision(.fractionLength(0 ... 1)))
                .keyboardType(keyboard)
                .font(Tide.numeral(numeralSize))
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - FuelChipListInput

/// Add-by-typing list ("Peanuts", "Shellfish") shown as removable chips, with
/// optional one-tap suggestions.
struct FuelChipListInput: View {
    @Binding
    var values: [String]
    var placeholder: String
    var suggestions: [String] = []
    var id: String

    @State
    private var draft = ""
    @FocusState
    private var focused: Bool
    @Environment(\.tideMood)
    private var mood

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                TextField(placeholder, text: $draft)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier(id)
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(canAdd ? Tide.ink : Tide.text3)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .background(canAdd ? mood.accent : Tide.fill, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .accessibilityLabel("Add")
            }
            .padding(.leading, Tide.s4)
            .padding(.trailing, Tide.s1)
            .padding(.vertical, Tide.s1)
            .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
            .animation(Tide.snap, value: canAdd)

            if !values.isEmpty {
                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            HapticManager.selection()
                            values.removeAll { $0 == value }
                        } label: {
                            HStack(spacing: Tide.s2) {
                                Text(value)
                                    .font(Tide.bodyStrong)
                                Image(systemName: "xmark")
                                    .font(Tide.label)
                            }
                            .foregroundStyle(Tide.text)
                            .padding(.horizontal, Tide.s4)
                            .frame(minHeight: Tide.hit)
                            .background(mood.accent.opacity(0.18), in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(value)")
                    }
                }
            }
            let open = suggestions.filter { suggestion in
                !values.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            }
            if !open.isEmpty {
                Text("Tap to add")
                    .tideLabel(Tide.text3)
                GlassEffectContainer(spacing: Tide.s1) {
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(open, id: \.self) { suggestion in
                            TideChip(title: "+ \(suggestion)") {
                                HapticManager.selection()
                                values.append(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        // Commas split ("peanuts, shellfish") so a pasted list works too.
        let items = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for item in items where !values.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
            values.append(item)
        }
        draft = ""
        if !items.isEmpty {
            HapticManager.lightImpact()
        }
    }
}

// MARK: - HealthBadge

/// "From Apple Health" marker for read-only values.
struct HealthBadge: View {
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Label("From Apple Health", systemImage: "heart.fill")
            .font(Tide.label)
            .foregroundStyle(mood.accent)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(mood.accent.opacity(0.16), in: .capsule)
    }
}

// MARK: - FuelHealthRow

/// A locked, read-only body stat.
struct FuelHealthRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Tide.s2) {
            Text(label)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
            Spacer(minLength: Tide.s2)
            Text(value)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
            Image(systemName: "lock.fill")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value), from Apple Health, can't be edited")
    }
}

// MARK: - FuelPillPicker

/// A labelled row of 2-4 equal pills for a small optional choice (spice,
/// breakfast style…). Tapping the selected pill clears it again, so "no
/// preference" is always one tap away.
struct FuelPillPicker<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding
    var selection: Value?
    var id: String

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
            layout {
                ForEach(options, id: \.value) { option in
                    let on = selection == option.value
                    Button {
                        HapticManager.selection()
                        selection = on ? nil : option.value
                    } label: {
                        Text(option.title)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(on ? Tide.ink : Tide.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Tide.s2)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .background(on ? mood.accent : Tide.fill, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .animation(Tide.snap, value: selection)
            .accessibilityIdentifier(id)
        }
    }
}
