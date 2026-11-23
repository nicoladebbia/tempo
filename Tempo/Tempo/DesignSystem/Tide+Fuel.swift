//
// Tide+Fuel.swift
// Tempo
//
// The pieces the Fuel screens (eating, logging, plan) share. They are built
// from the Tide tokens and components only; the numbers they show come from
// the same sources as the Today tab's Fuel card.
//

import SwiftUI

// MARK: - Tones

extension Tide {
    /// "Fine": on time, on target, done.
    static let good = Color(red: 0.42, green: 0.96, blue: 0.80)
    /// "Look at this": a little off, waiting, estimated.
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.40)
    /// Plans, estimates and anything that is "the plan" rather than "what happened".
    static let plan = Color(red: 0.72, green: 0.62, blue: 1.00)
}

// MARK: - FuelPressStyle

/// Cards that open something dip slightly under the finger.
struct FuelPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - FuelCalorieHero

/// The hero number of a day: calories eaten, "of N kcal", a level bar.
/// Same structure and sizes as the Fuel card on Today.
struct FuelCalorieHero: View {
    let consumed: Int
    let target: Int
    var barHeight: CGFloat = Tide.bar

    private var progress: Double {
        target > 0 ? min(Double(consumed) / Double(target), 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(consumed.formatted(), size: Tide.numeralL)
                Text("of \(target.formatted()) kcal")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .accessibilityElement(children: .combine)
            TideLevelBar(progress: progress, color: consumed > target && target > 0 ? Tide.danger : nil, height: barHeight)
                .animation(Tide.settle, value: progress)
        }
    }

    /// "420 left" / "80 over", the trailing words of a calories label.
    static func remaining(consumed: Int, target: Int) -> String? {
        guard target > 0 else {
            return nil
        }
        let left = target - consumed
        return left >= 0 ? "\(left.formatted()) left" : "\((-left).formatted()) over"
    }
}

// MARK: - FuelMacroColumns

/// Protein, carbs and fat side by side (stacked at accessibility sizes).
/// Identical in structure to the macro row of the Today tab's Fuel card.
struct FuelMacroColumns: View {
    struct Item {
        let name: String
        let value: Int
        let target: Int
        let color: Color
    }

    let items: [Item]
    var barHeight: CGFloat = Tide.barSlim

    @Environment(\.dynamicTypeSize)
    private var typeSize

    init(protein: (Int, Int), carbs: (Int, Int), fat: (Int, Int), barHeight: CGFloat = Tide.barSlim) {
        items = [
            Item(name: "Protein", value: protein.0, target: protein.1, color: Tide.protein),
            Item(name: "Carbs", value: carbs.0, target: carbs.1, color: Tide.carbs),
            Item(name: "Fat", value: fat.0, target: fat.1, color: Tide.fat),
        ]
        self.barHeight = barHeight
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s4))
        layout {
            ForEach(items, id: \.name) { item in
                column(item)
            }
        }
    }

    private func column(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(item.name).tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                TideNumber("\(item.value)", size: Tide.numeralS, relativeTo: .headline)
                Text(item.target > 0 ? "/ \(item.target) g" : "g")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
            TideLevelBar(
                progress: item.target > 0 ? min(Double(item.value) / Double(item.target), 1) : 0,
                color: item.color, height: barHeight
            )
            .animation(Tide.settle, value: item.value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name) \(item.value)\(item.target > 0 ? " of \(item.target)" : "") grams")
    }
}

// MARK: - FuelMacroInline

/// Three small macro figures for a meal or an item: "P 32 · C 40 · F 12", each in its own colour.
struct FuelMacroInline: View {
    let protein: Int
    let carbs: Int
    let fat: Int

    var body: some View {
        HStack(spacing: Tide.s3) {
            figure("P", protein, Tide.protein)
            figure("C", carbs, Tide.carbs)
            figure("F", fat, Tide.fat)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(protein) grams, carbs \(carbs) grams, fat \(fat) grams")
    }

    private func figure(_ letter: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: Tide.s1) {
            Circle().fill(color).frame(width: Tide.s2, height: Tide.s2)
            Text("\(letter) \(value) g")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - FuelPill

/// A short status word in a tinted capsule ("Eaten", "Skipped").
struct FuelPill: View {
    let text: String
    var color: Color = Tide.text2

    var body: some View {
        Text(text)
            .font(Tide.label)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(color.opacity(0.16), in: .capsule)
    }
}

// MARK: - FuelIconButton

/// A round glass icon button for toolbars and headers (44 pt).
struct FuelIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Tide.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(tint)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - FuelEmptyState

/// Nothing here yet: an icon, one line, one sentence, and optionally the next step.
struct FuelEmptyState<Action: View>: View {
    let icon: String
    let title: String
    var message: String?
    @ViewBuilder var action: Action

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.title)
                .foregroundStyle(mood.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
        }
        .frame(maxWidth: .infinity)
        .tideCard()
    }
}

extension FuelEmptyState where Action == EmptyView {
    init(icon: String, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

// MARK: - FuelBanner

/// A note above the content: what changed, with one action and a dismiss.
struct FuelBanner: View {
    let icon: String
    var tint: Color?
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.headline)
                    .foregroundStyle(tint ?? mood.accent)
                    .frame(width: Tide.icon, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -Tide.s3)
                    .padding(.top, -Tide.s3)
                    .accessibilityLabel("Dismiss")
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tideGlass)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}

// MARK: - Fields and bars

extension View {
    /// A text field's surface: soft fill, 44 pt tall.
    func fuelField(radius: CGFloat = Tide.controlRadius) -> some View {
        padding(.horizontal, Tide.s3)
            .frame(minHeight: Tide.hit)
            .background(Tide.fill, in: .rect(cornerRadius: radius))
    }

    /// A glass bar floating at the bottom of a screen (totals, the main button).
    func fuelBottomBar(@ViewBuilder _ bar: () -> some View) -> some View {
        let content = bar()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            content
                .tideCard(padding: Tide.s4)
                .padding(.horizontal, Tide.s4)
                .padding(.bottom, Tide.s2)
        }
    }

    /// A row on a Form or List: a soft fill instead of the grey grouped look.
    func fuelRow() -> some View {
        listRowBackground(Tide.fill)
            .listRowSeparatorTint(Tide.hairline)
    }
}

// MARK: - FuelActionTile

/// A glass tile that is one button: an icon over a short label.
struct FuelActionTile: View {
    let icon: String
    let label: String
    var tint: Color?
    let identifier: String
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tide.s1) {
                Image(systemName: icon)
                    .font(Tide.headline)
                    .foregroundStyle(tint ?? mood.accent)
                Text(label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s4)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .rect(cornerRadius: Tide.tileRadius))
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
