//
// FuelSetupComponents.swift
// Tempo
//
// The building blocks of the Fuel setup flows: a one-question-per-screen
// scaffold with progress dots and Back/Next, compact tappable choice cards
// (~56 pt rows), steppers and number fields that sit several to a screen, a
// chip list, and the Apple Health badge. Everything uses the design tokens:
// title3 headings, body-size rows, 20 pt gutters, one primary button at the
// bottom and a quiet Skip for optional questions.
//

import SwiftUI

// MARK: - FuelFlowScaffold

struct FuelFlowScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    let index: Int
    let count: Int
    var canContinue = true
    var isSaving = false
    var isLast = false
    /// Label of the primary button on the last screen ("Save", "Save & next: Goal").
    var lastTitle = "Save"
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

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        Text(title)
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .font(.tempoCallout)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.md)
                .padding(.bottom, TempoSpacing.xl)
            }
            bottomBar
        }
        .background(Color.tempoBgPrimary)
        .dismissKeyboardOnTapOutside()
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fuelFlowClose")
            Spacer()
            HStack(spacing: TempoSpacing.xs) {
                ForEach(0 ..< max(count, 1), id: \.self) { dot in
                    Capsule()
                        .fill(dot <= index ? Color.tempoSignal : Color.tempoDivider)
                        .frame(width: dot == index ? 22 : 8, height: 8)
                        .animation(TempoAnimation.springMedium, value: index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(count)")
            Spacer()
            topTrailing
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        }
        .padding(.horizontal, TempoSpacing.sm)
    }

    @ViewBuilder
    private var topTrailing: some View {
        if let onSaveAndClose {
            Button("Save & close") {
                HapticManager.lightImpact()
                onSaveAndClose()
            }
            .font(.tempoCallout.weight(.semibold))
            .foregroundStyle(canSaveAndClose && !isSaving ? Color.tempoSignal : Color.tempoTextDisabled)
            .disabled(!canSaveAndClose || isSaving)
            .accessibilityIdentifier("fuelFlowSaveClose")
        } else if let onSkipSection {
            Button("Skip section", action: onSkipSection)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
                .accessibilityIdentifier("fuelFlowSkipSection")
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: TempoSpacing.md) {
                if index > 0 {
                    Button("Back") {
                        HapticManager.selection()
                        onBack()
                    }
                    .buttonStyle(.tempoSecondary)
                    .accessibilityIdentifier("fuelFlowBack")
                }
                Button {
                    HapticManager.lightImpact()
                    onNext()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(isLast ? lastTitle : "Next")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(!canContinue || isSaving)
                .accessibilityIdentifier(isLast ? "fuelFlowSave" : "fuelFlowNext")
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, onSkip == nil ? TempoSpacing.sm : 0)
            if let onSkip {
                Button(action: onSkip) {
                    Text("Optional · Skip")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Skip this question")
                .accessibilityIdentifier("fuelFlowSkip")
            }
        }
        .background(Color.tempoBgPrimary)
    }
}

// MARK: - FuelChoiceCard

/// A tall tappable answer (radio or multi-select look).
struct FuelChoiceCard: View {
    let title: String
    var subtitle: String?
    var icon: String?
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack(spacing: TempoSpacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.tempoBgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.tempoBodyBold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextTertiary)
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                    .stroke(isSelected ? Color.tempoSignal : Color.tempoBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var current: Int {
        value ?? defaultValue
    }

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            if let label {
                Text(label)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            button("minus", enabled: current - step >= range.lowerBound) {
                value = max(range.lowerBound, current - step)
            }
            VStack(spacing: 0) {
                Text("\(current)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(minWidth: 64, maxWidth: label == nil ? .infinity : 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label.map { "\($0) " } ?? "")\(current) \(unit)")
            .accessibilityIdentifier(id)
            button("plus", enabled: current + step <= range.upperBound) {
                value = min(range.upperBound, current + step)
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .animation(TempoAnimation.springMedium, value: current)
        .onAppear {
            if value == nil {
                value = defaultValue
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Color.tempoTextPrimary : Color.tempoTextDisabled)
                .frame(width: 44, height: 44)
                .background(Color.tempoBgTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "More" : "Less")
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
            if let label {
                Text(label)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer(minLength: TempoSpacing.sm)
            }
            TextField("—", value: $value, format: .number.precision(.fractionLength(0 ... 1)))
                .keyboardType(keyboard)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
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

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                TextField(placeholder, text: $draft)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier(id)
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.tempoTextInverse)
                        .frame(width: 36, height: 36)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.tempoTextDisabled : Color.tempoSignal)
                        .clipShape(Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add")
            }
            .padding(TempoSpacing.md)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))

            if !values.isEmpty {
                FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            HapticManager.selection()
                            values.removeAll { $0 == value }
                        } label: {
                            HStack(spacing: TempoSpacing.xs) {
                                Text(value)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.tempoCallout)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(.horizontal, TempoSpacing.md)
                            .padding(.vertical, TempoSpacing.sm)
                            .background(Color.tempoSignal.opacity(TempoOpacity.o15))
                            .clipShape(Capsule())
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
                Text("TAP TO ADD")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextTertiary)
                FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                    ForEach(open, id: \.self) { suggestion in
                        Button {
                            HapticManager.selection()
                            values.append(suggestion)
                        } label: {
                            Text("+ \(suggestion)")
                                .font(.tempoCallout)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .padding(.horizontal, TempoSpacing.md)
                                .padding(.vertical, TempoSpacing.sm)
                                .background(Color.tempoBgTertiary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
    var body: some View {
        Label("From Apple Health", systemImage: "heart.fill")
            .font(.tempoCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoSignal)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, 3)
            .background(Color.tempoSignal.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
    }
}

// MARK: - FuelHealthRow

/// A locked, read-only body stat.
struct FuelHealthRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.vertical, TempoSpacing.sm)
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

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(label)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
            HStack(spacing: TempoSpacing.sm) {
                ForEach(options, id: \.value) { option in
                    let on = selection == option.value
                    Button {
                        HapticManager.selection()
                        selection = on ? nil : option.value
                    } label: {
                        Text(option.title)
                            .font(.tempoBody.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.tempoTextInverse : Color.tempoTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Color.tempoSignal : Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                                    .stroke(on ? Color.clear : Color.tempoBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .accessibilityIdentifier(id)
        }
    }
}
