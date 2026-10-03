//
// FuelSetupComponents.swift
// Tempo
//
// The building blocks of the Fuel setup flows: a one-question-per-screen
// scaffold with progress dots and Back/Next, big tappable choice cards, a big
// stepper, a big number field, a chip list, and the Apple Health badge.
// Everything uses the design tokens and the onboarding look: heavy title,
// tall rounded rows, one primary button at the bottom.
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
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text(title.uppercased())
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle {
                            Text(subtitle)
                                .font(.tempoBody)
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
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, TempoSpacing.sm)
    }

    private var bottomBar: some View {
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
                        Text(isLast ? "Save" : "Next")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .disabled(!canContinue || isSaving)
            .accessibilityIdentifier(isLast ? "fuelFlowSave" : "fuelFlowNext")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Color.tempoBgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
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
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(isSelected ? Color.tempoSignal : Color.tempoBorder, lineWidth: isSelected ? 2 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - FuelBigStepper

/// A huge number with − / + buttons. `defaultValue` shows (and commits on appear) when unset.
struct FuelBigStepper: View {
    @Binding
    var value: Int?
    let defaultValue: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit: String
    var id: String

    private var current: Int {
        value ?? defaultValue
    }

    var body: some View {
        HStack(spacing: TempoSpacing.lg) {
            button("minus", enabled: current - step >= range.lowerBound) {
                value = max(range.lowerBound, current - step)
            }
            VStack(spacing: 0) {
                Text("\(current)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(current) \(unit)")
            .accessibilityIdentifier(id)
            button("plus", enabled: current + step <= range.upperBound) {
                value = min(range.upperBound, current + step)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(enabled ? Color.tempoTextPrimary : Color.tempoTextDisabled)
                .frame(width: 56, height: 56)
                .background(Color.tempoBgTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "More" : "Less")
    }
}

// MARK: - FuelNumberField

/// A big numeric answer with its unit.
struct FuelNumberField: View {
    @Binding
    var value: Double?
    let unit: String
    var keyboard: UIKeyboardType = .decimalPad
    var id: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
            TextField("—", value: $value, format: .number.precision(.fractionLength(0 ... 1)))
                .keyboardType(keyboard)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .padding(TempoSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

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
