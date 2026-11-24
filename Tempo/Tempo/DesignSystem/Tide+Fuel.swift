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
        // Three in a row while they fit, stacked at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                figure("P", protein, Tide.protein)
                figure("C", carbs, Tide.carbs)
                figure("F", fat, Tide.fat)
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                figure("P", protein, Tide.protein)
                figure("C", carbs, Tide.carbs)
                figure("F", fat, Tide.fat)
            }
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

    /// The same, shown only while `isShown` (a meal that still needs its answer).
    func fuelBottomBar(isShown: Bool, @ViewBuilder _ bar: () -> some View) -> some View {
        let content = bar()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            if isShown {
                content
                    .tideCard(padding: Tide.s4)
                    .padding(.horizontal, Tide.s4)
                    .padding(.bottom, Tide.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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

// MARK: - FuelDestructiveButtonStyle

/// The main button of a "delete this" confirmation: same shape as the primary
/// button, filled with the danger colour.
struct FuelDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(Tide.ink)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Tide.danger.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == FuelDestructiveButtonStyle {
    static var fuelDestructive: FuelDestructiveButtonStyle {
        FuelDestructiveButtonStyle()
    }
}

// MARK: - Sizes

extension Tide {
    /// A macro ring in a trio of three, and the stroke it is drawn with.
    static let fuelRing: CGFloat = 76
    static let fuelRingLine: CGFloat = 7
    /// A tick box on an ingredient or a step.
    static let fuelCheck: CGFloat = 26
    /// Sheets of a fixed size: a time wheel, a "are you sure".
    static let fuelDetentPicker: CGFloat = 320
    static let fuelDetentConfirm: CGFloat = 480
    /// The loading skeleton: a text line and a row.
    static let fuelSkeletonLine: CGFloat = 12
    static let fuelSkeletonRow: CGFloat = 52
    /// A food or meal icon on a hero.
    static let fuelHeroIcon: CGFloat = 52
    /// A meal photo on its review screen, and a number field beside a unit.
    static let fuelPhoto: CGFloat = 240
    static let fuelAmountField: CGFloat = 80
    /// Height of an inline time wheel.
    static let fuelWheel: CGFloat = 100
    /// Smallest height of a free-text recipe box.
    static let fuelEditor: CGFloat = 220
    /// Height of the 7-day calorie chart.
    static let fuelChart: CGFloat = 160
    /// The big record button on the voice screen.
    static let fuelMic: CGFloat = 96
}

// MARK: - FuelSection

/// A card with a small-caps heading and, on the right, a short value
/// ("3/8"). The shape every list block of a Fuel page shares.
struct FuelSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: title, trailing: trailing)
            content
        }
        .tideCard()
    }
}

// MARK: - FuelMacroRings

/// Protein, carbs and fat as three lit rings with the grams inside. Two
/// readings: "share of this meal's calories" (a meal, a photo) and "how much
/// of the target" (a day). Stacks into rows at accessibility sizes.
struct FuelMacroRings: View {
    struct Item {
        let name: String
        let grams: Int
        let progress: Double
        let caption: String
        let color: Color
    }

    let items: [Item]

    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .headline)
    private var ring = Tide.fuelRing

    /// A meal or a food: each ring is that macro's share of the calories.
    init(protein: Int, carbs: Int, fat: Int) {
        let kcal = [Double(protein) * 4, Double(carbs) * 4, Double(fat) * 9]
        let total = kcal.reduce(0, +)
        func share(_ index: Int) -> Double {
            total > 0 ? kcal[index] / total : 0
        }
        func caption(_ index: Int) -> String {
            "\(Int((share(index) * 100).rounded()))% of kcal"
        }
        items = [
            Item(name: "Protein", grams: protein, progress: share(0), caption: caption(0), color: Tide.protein),
            Item(name: "Carbs", grams: carbs, progress: share(1), caption: caption(1), color: Tide.carbs),
            Item(name: "Fat", grams: fat, progress: share(2), caption: caption(2), color: Tide.fat),
        ]
    }

    /// A day: each ring is the macro against its target.
    init(protein: (Int, Int), carbs: (Int, Int), fat: (Int, Int)) {
        func item(_ name: String, _ pair: (Int, Int), _ color: Color) -> Item {
            Item(
                name: name, grams: pair.0,
                progress: pair.1 > 0 ? min(Double(pair.0) / Double(pair.1), 1) : 0,
                caption: pair.1 > 0 ? "of \(pair.1) g" : "g",
                color: color
            )
        }
        items = [
            item("Protein", protein, Tide.protein),
            item("Carbs", carbs, Tide.carbs),
            item("Fat", fat, Tide.fat),
        ]
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Tide.s4) {
                ForEach(items, id: \.name) { item in
                    HStack(spacing: Tide.s4) {
                        dial(item)
                        labels(item, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(item))
                }
            }
        } else {
            HStack(alignment: .top, spacing: Tide.s3) {
                ForEach(items, id: \.name) { item in
                    VStack(spacing: Tide.s2) {
                        dial(item)
                        labels(item, alignment: .center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(item))
                }
            }
        }
    }

    private func dial(_ item: Item) -> some View {
        ZStack {
            TideRing(progress: item.progress, color: item.color, lineWidth: Tide.fuelRingLine)
            TideNumber("\(item.grams)", unit: "g", size: Tide.numeralS, relativeTo: .headline)
                .padding(.horizontal, Tide.s3)
        }
        .frame(width: ring, height: ring)
    }

    private func labels(_ item: Item, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Tide.hair) {
            Text(item.name).tideLabel()
            Text(item.caption)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
    }

    private func spoken(_ item: Item) -> String {
        "\(item.name) \(item.grams) grams, \(item.caption)"
    }
}

// MARK: - FuelMacroSplitBar

/// One bar split in three: how a meal's calories divide between protein,
/// carbs and fat (4, 4 and 9 kcal per gram).
struct FuelMacroSplitBar: View {
    let protein: Int
    let carbs: Int
    let fat: Int
    var height: CGFloat = Tide.bar

    private var parts: [(Double, Color)] {
        [(Double(protein) * 4, Tide.protein), (Double(carbs) * 4, Tide.carbs), (Double(fat) * 9, Tide.fat)]
    }

    var body: some View {
        let parts = parts
        let total = parts.reduce(0) { $0 + $1.0 }
        GeometryReader { proxy in
            let usable = max(proxy.size.width - Tide.hair * 2, 0)
            HStack(spacing: Tide.hair) {
                if total > 0 {
                    ForEach(parts.indices, id: \.self) { index in
                        Capsule()
                            .fill(parts[index].1)
                            .frame(width: usable * parts[index].0 / total)
                    }
                } else {
                    Capsule().fill(Tide.track)
                }
            }
            .animation(Tide.settle, value: protein + carbs * 1000 + fat * 1_000_000)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - FuelCheckMark

/// The round tick of a checklist row.
struct FuelCheckMark: View {
    let isOn: Bool
    /// Shown inside the ring while it is not ticked (a step number).
    var number: Int?
    @ScaledMetric(relativeTo: .body)
    private var size = Tide.fuelCheck

    var body: some View {
        ZStack {
            Circle().fill(isOn ? Tide.good.opacity(0.2) : Color.clear)
            Circle().strokeBorder(isOn ? Tide.good : Tide.text3, lineWidth: Tide.focusLine)
            if isOn {
                Image(systemName: "checkmark")
                    .font(Tide.label)
                    .foregroundStyle(Tide.good)
                    .transition(.scale.combined(with: .opacity))
            } else if let number {
                Text("\(number)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .animation(Tide.snap, value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - FuelCheckRow

/// A checklist row: a tick, a title and a detail line. At least 44 pt.
struct FuelCheckRow: View {
    let title: String
    var detail: String?
    var icon: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Tide.s3) {
                FuelCheckMark(isOn: isOn)
                    .padding(.top, Tide.hair)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    HStack(spacing: Tide.s2) {
                        if let icon {
                            Image(systemName: icon)
                                .font(Tide.label)
                                .foregroundStyle(Tide.water)
                                .accessibilityHidden(true)
                        }
                        Text(title)
                            .font(Tide.body)
                            .foregroundStyle(isOn ? Tide.text3 : Tide.text)
                            .strikethrough(isOn, color: Tide.text3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let detail {
                        Text(detail)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Tide.hit, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - FuelActionRow

/// A row in a card that does one thing: icon, title, an optional detail, a
/// chevron. `isDestructive` paints it in the danger colour.
struct FuelActionRow: View {
    let icon: String
    let title: String
    var detail: String?
    var isDestructive = false
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.headline)
                    .foregroundStyle(isDestructive ? Tide.danger : mood.accent)
                    .frame(width: Tide.icon, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(isDestructive ? Tide.danger : Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FuelTimelineTrack

/// A lit track with three labelled stops (prep, eat, finish). The bar is the
/// day's clock between the first and last stop.
struct FuelTimelineTrack: View {
    struct Stop: Identifiable {
        let id: String
        let label: String
        let time: String
        let isNext: Bool
    }

    let stops: [Stop]
    let progress: Double
    var tone: Color?

    var body: some View {
        VStack(spacing: Tide.s2) {
            TideLevelBar(progress: progress, color: tone, height: Tide.barSlim)
                .animation(Tide.settle, value: progress)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: horizontal(index), spacing: Tide.hair) {
                        Text(stop.label).tideLabel(stop.isNext ? Tide.text : Tide.text3)
                        Text(stop.time)
                            .font(stop.isNext ? Tide.bodyStrong : Tide.caption)
                            .foregroundStyle(stop.isNext ? Tide.text : Tide.text2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                    }
                    .frame(maxWidth: .infinity, alignment: alignment(index))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stops.map { "\($0.label) \($0.time)" }.joined(separator: ", "))
    }

    private func horizontal(_ index: Int) -> HorizontalAlignment {
        index == 0 ? .leading : index == stops.count - 1 ? .trailing : .center
    }

    private func alignment(_ index: Int) -> Alignment {
        index == 0 ? .leading : index == stops.count - 1 ? .trailing : .center
    }
}

// MARK: - FuelSkeletonLine

/// A grey line that breathes: the shape of text that has not arrived yet.
struct FuelSkeletonLine: View {
    var width: CGFloat?
    var height: CGFloat = Tide.fuelSkeletonLine

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Tide.fillStrong)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - FuelSkeletonRows

/// A few rows of skeleton, for a list that is still loading.
struct FuelSkeletonRows: View {
    var count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            ForEach(0 ..< count, id: \.self) { index in
                VStack(alignment: .leading, spacing: Tide.s2) {
                    FuelSkeletonLine(width: index.isMultiple(of: 2) ? nil : Tide.fuelRing * 3)
                    FuelSkeletonLine(height: Tide.s2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - FuelAIState

/// What an AI screen shows when it has no result: working, slow, nothing
/// found or failed. One look for every AI screen, so a bad reply is never a
/// blank page.
struct FuelAIState: View {
    enum Kind {
        /// Waiting for the reply. After a few seconds it says it is still going.
        case working(String)
        /// A reply came back with nothing usable in it.
        case empty(title: String, message: String)
        /// The call failed.
        case failed(title: String, message: String)
    }

    let kind: Kind
    var actionTitle: String?
    var action: (() -> Void)?
    /// False when it already sits inside a card (no card in a card).
    var isCard = true

    @Environment(\.tideMood)
    private var mood
    @State
    private var isSlow = false

    var body: some View {
        if isCard {
            content.tideCard()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: Tide.s4) {
            switch kind {
            case let .working(message):
                FuelSkeletonRows(count: 2)
                HStack(spacing: Tide.s2) {
                    ProgressView().tint(mood.accent)
                    Text(isSlow ? "Still working. This one is taking a while." : message)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
            case let .empty(title, message):
                stateBlock(icon: "sparkle.magnifyingglass", tint: mood.accent, title: title, text: message)
            case let .failed(title, message):
                stateBlock(icon: "exclamationmark.triangle.fill", tint: Tide.warn, title: title, text: message)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tideGlass)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Tide.snap, value: isSlow)
        .task {
            if case .working = kind {
                try? await Task.sleep(for: .seconds(8))
                isSlow = true
            }
        }
    }

    private func stateBlock(icon: String, tint: Color, title: String, text: String) -> some View {
        VStack(spacing: Tide.s2) {
            TideIconTile(systemName: icon, tint: tint, size: Tide.tileLarge)
            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Tide.stateWidth)
    }
}

// MARK: - FuelChoiceSurface

private struct FuelChoiceSurface: ViewModifier {
    let selected: Bool
    let minHeight: CGFloat
    let capsule: Bool

    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? Tide.hit : Tide.controlRadius, style: .continuous)
        content
            .foregroundStyle(selected ? mood.accent : Tide.text)
            .frame(minHeight: minHeight)
            .background(selected ? mood.accent.opacity(0.2) : Tide.fill, in: shape)
            .overlay { shape.strokeBorder(selected ? mood.accent : Color.clear, lineWidth: Tide.focusLine) }
            .contentShape(shape)
            .animation(Tide.snap, value: selected)
    }
}

extension View {
    /// A choice in a row of choices (a meal type, a portion): soft fill, and
    /// an accent ring with a tinted fill when it is the one picked.
    func fuelChoice(selected: Bool, minHeight: CGFloat = Tide.hit) -> some View {
        modifier(FuelChoiceSurface(selected: selected, minHeight: minHeight, capsule: false))
    }

    /// The same, fully rounded: a toggle that sits in a line ("From my kitchen").
    func fuelChip(selected: Bool) -> some View {
        padding(.horizontal, Tide.s3)
            .modifier(FuelChoiceSurface(selected: selected, minHeight: Tide.hit, capsule: true))
    }
}

// MARK: - FuelShareBar

/// A quiet bar for "this much of the whole": one food's share of a meal.
struct FuelShareBar: View {
    let progress: Double
    var color: Color = Tide.plan

    var body: some View {
        Capsule()
            .fill(Tide.track)
            .frame(height: Tide.barSlim)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .animation(Tide.settle, value: progress)
            .accessibilityHidden(true)
    }
}

// MARK: - FuelMealStyle

/// How a meal looks wherever it appears: its symbol and the colour of its status.
enum FuelMealStyle {
    static func icon(forName name: String) -> String {
        // "Afternoon Snack", "Pre-workout snack" and "Snack" all read as a snack.
        let lowered = name.lowercased()
        if lowered.contains("breakfast") {
            return "sunrise.fill"
        }
        if lowered.contains("lunch") {
            return "sun.max.fill"
        }
        if lowered.contains("dinner") {
            return "moon.stars.fill"
        }
        if lowered.contains("snack") {
            return "carrot.fill"
        }
        return "fork.knife"
    }

    static func tone(for status: MealStatus, accent: Color) -> Color {
        switch status {
        case .eaten: Tide.good
        case .skipped: Tide.danger
        case .planned: accent
        case .modified: Tide.warn
        }
    }
}

// MARK: - Second wave: progress and grouped rows

extension Tide {
    /// The ring that leads a screen about "how far along" (setup, a weekly review).
    static let fuelHeroRing: CGFloat = 88
    static let fuelHeroRingLine: CGFloat = 8
}

// MARK: - FuelProgressHero

/// The head of a "how far along are you" screen: a lit ring with the count
/// inside, a title, and one sentence. Reads as one object, so a screen that
/// is mostly a list still opens with a figure.
struct FuelProgressHero: View {
    let done: Int
    let total: Int
    let title: String
    var caption: String?
    var tint: Color?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .title)
    private var ring = Tide.fuelHeroRing

    private var progress: Double {
        total > 0 ? min(Double(done) / Double(total), 1) : 0
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))
        layout {
            ZStack {
                TideRing(progress: progress, color: tint ?? mood.accent, lineWidth: Tide.fuelHeroRingLine)
                HStack(alignment: .firstTextBaseline, spacing: Tide.hair) {
                    TideNumber("\(done)", size: Tide.numeralS, relativeTo: .headline)
                    Text("/\(total)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .monospacedDigit()
                }
                .padding(.horizontal, Tide.s3)
            }
            .frame(width: ring, height: ring)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(title)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(done) of \(total)")
    }
}

// MARK: - FuelDecisionSheet

/// A small sheet that asks one question with two or three answers: a symbol,
/// the question, what it is about (as pills), the main answer as the one
/// filled button, a second answer in glass and a quiet cancel. Replaces a
/// system alert where the choice deserves a sentence of explanation.
struct FuelDecisionSheet: View {
    let icon: String
    var tint: Color?
    let title: String
    let message: String
    var chips: [String] = []
    let primaryTitle: String
    let primary: () -> Void
    var secondaryTitle: String?
    var secondary: (() -> Void)?
    var cancelTitle = "Cancel"
    let cancel: () -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                TideIconTile(systemName: icon, tint: tint ?? Tide.warn, size: Tide.tileLarge)
                    .padding(.top, Tide.s4)
                VStack(spacing: Tide.s2) {
                    Text(title)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !chips.isEmpty {
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                                .padding(.horizontal, Tide.s3)
                                .frame(minHeight: Tide.hit)
                                .background(Tide.fill, in: .capsule)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: Tide.stateWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.edge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fuelBottomBar {
            VStack(spacing: Tide.s2) {
                Button(action: primary) {
                    // A long title wraps, centred, instead of hugging the left edge.
                    Text(primaryTitle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                if let secondaryTitle, let secondary {
                    Button(action: secondary) {
                        Text(secondaryTitle)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                }
                Button(action: cancel) {
                    Text(cancelTitle)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .tidePage()
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
        // Large text needs the whole page: a short sheet would cut the message.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(Tide.fuelDetentConfirm), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - FuelRowGroup

/// A label over ONE glass card that holds several rows with hairlines
/// between them: the answer to a stack of identical cards.
struct FuelRowGroup<Content: View>: View {
    var title: String?
    var trailing: String?
    /// A quiet sentence under the card (what a setting does).
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            if let title {
                TideSectionLabel(title: title, trailing: trailing)
                    .padding(.horizontal, Tide.s1)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().overlay(Tide.hairline)
                        }
                        row.padding(.vertical, Tide.s2)
                    }
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            if let footnote {
                Text(footnote)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s1)
            }
        }
    }
}
