//
// Tide+Kitchen.swift
// Tempo
//
// Pieces shared by the Kitchen, Scan and Supplements screens: a glass
// segmented control, divided glass lists, a big check circle, tags, empty
// states, camera panels and the sheet and form chrome. Built from the Tide
// tokens only.
//

import SwiftUI

// MARK: - Tide.Kitchen

extension Tide {
    /// Tokens of the Kitchen, Scan and Supplements screens.
    enum Kitchen {
        /// Meaning colours that keep their meaning whatever the mood is.
        static let good = Color(red: 0.42, green: 0.94, blue: 0.66)
        static let warn = Color(red: 1.00, green: 0.80, blue: 0.40)

        /// A list row that is easy to hit, and the tall one used in store mode.
        static let row: CGFloat = 56
        static let shopRow: CGFloat = 72
        /// An item name in store mode: large enough to read at arm's length.
        static let shopName = Font.system(.title3, weight: .semibold)
        /// A product picture in a row.
        static let thumb: CGFloat = 48
        /// The framing box on a camera.
        static let viewfinderWidth: CGFloat = 280
        static let viewfinderHeight: CGFloat = 180
        /// Ink laid under controls that float over a live camera, so they stay readable on any scene.
        static let cameraTint = Tide.ink.opacity(0.55)
    }
}

// MARK: - KitchenSegmented

/// A glass segmented control: one pill slides to the chosen option. At the
/// largest text sizes the options stack in two columns instead of shrinking.
struct KitchenSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding
    var selection: Value
    let title: (Value) -> String

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Namespace
    private var pill

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Tide.s1) {
                    ForEach(options, id: \.self, content: segment)
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self, content: segment)
                }
            }
        }
        .padding(Tide.s1)
        .glassEffect(
            .regular.tint(Tide.glassControl),
            in: .rect(cornerRadius: typeSize.isAccessibilitySize ? Tide.tileRadius : Tide.cardRadius)
        )
    }

    private func segment(_ option: Value) -> some View {
        let selected = option == selection
        return Button {
            withAnimation(Tide.snap) { selection = option }
        } label: {
            Text(title(option))
                .font(Tide.bodyStrong)
                .foregroundStyle(selected ? Tide.ink : Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .background {
                    if selected {
                        Capsule().fill(mood.accent).matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected) { _, new in new }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - KitchenRows

/// Rows in one glass card with a hairline between them. Every direct child
/// is a row; each gets the standard padding and a comfortable minimum height.
struct KitchenRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                        .padding(.horizontal, Tide.s4)
                        .padding(.vertical, Tide.s3)
                        .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.row, alignment: .leading)
                    if subview.id != subviews.last?.id {
                        Rectangle()
                            .fill(Tide.hairline)
                            .frame(height: 1)
                            .padding(.leading, Tide.s4)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.cardRadius))
    }
}

// MARK: - KitchenGroup

/// A small tracked label, an optional trailing value, and a glass list of rows.
struct KitchenGroup<Content: View>: View {
    let title: String
    var systemImage: String?
    var trailing: String?
    var tint: Color = Tide.text2
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Tide.label)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(title).tideLabel(tint)
                Spacer(minLength: Tide.s2)
                if let trailing {
                    Text(trailing).font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .padding(.horizontal, Tide.s1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            KitchenRows { content }
        }
    }
}

// MARK: - KitchenTag

/// A small pill: a brand, a status, "Used up".
struct KitchenTag: View {
    let text: String
    var tint: Color = Tide.text2

    var body: some View {
        Text(text)
            .font(Tide.label)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(tint.opacity(0.16), in: .capsule)
    }
}

// MARK: - KitchenCheck

/// A big circular check: the one thing to hit in a shop, with one hand.
struct KitchenCheck: View {
    let checked: Bool
    @ScaledMetric
    private var size: CGFloat
    @Environment(\.tideMood)
    private var mood

    /// `size` is the diameter at the default text size.
    init(checked: Bool, size: CGFloat = 32) {
        self.checked = checked
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(Tide.text3, lineWidth: 2)
                .opacity(checked ? 0 : 1)
            Circle().fill(mood.accent)
                .opacity(checked ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(.footnote, weight: .heavy))
                .foregroundStyle(Tide.ink)
                .scaleEffect(checked ? 1 : 0.4)
                .opacity(checked ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(Tide.snap, value: checked)
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenIconButton

/// A round 44 pt glass button with an icon.
struct KitchenIconButton: View {
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

// MARK: - KitchenStat

/// A big figure with a small label above it, for a summary on top of a page.
struct KitchenStat: View {
    let value: String
    var unit: String?
    let label: String
    var color: Color = Tide.text

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(label).tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            TideNumber(value, unit: unit, size: Tide.numeralM, relativeTo: .title, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - KitchenEmpty

/// Icon, title, a line of help and an optional action, centred in a glass card.
struct KitchenEmpty: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.largeTitle)
                .foregroundStyle(mood.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tidePrimary)
                    .padding(.top, Tide.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s2)
        .tideCard(padding: Tide.s6)
    }
}

// MARK: - Page, sheet and form chrome

extension View {
    /// The root of a full-screen cover or a pushed page. It always draws its
    /// own field, even when the page that presents it sits inside one (a page
    /// nested in a page draws nothing, and a cover would be left empty).
    func kitchenPage(energy: Double = Tide.sheetEnergy) -> some View {
        tidePage(energy: energy).environment(\.tideInsidePage, false)
    }

    /// The field behind a sheet, a calm drag handle, and no second field for
    /// anything nested inside. Goes on the sheet's root view.
    func kitchenSheet() -> some View {
        modifier(KitchenSheetModifier())
    }

    /// A Form or List that lets the field through. Its sections then take
    /// `kitchenSection()` so the rows sit on Tide fill, not the grey default.
    func kitchenForm() -> some View {
        scrollContentBackground(.hidden)
    }

    /// Goes on each Section of a Form or List (a row background is read per row).
    func kitchenSection() -> some View {
        listRowBackground(Tide.fill)
    }

    /// A text field laid on a Tide fill, for fields outside a Form.
    func kitchenField() -> some View {
        font(Tide.body)
            .foregroundStyle(Tide.text)
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.hit)
            .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
    }

    /// A button bar that floats over the bottom of a scroll view: no opaque
    /// strip, the content fades under it.
    func kitchenBottomBar(@ViewBuilder _ bar: () -> some View) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            bar()
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
        }
    }

    /// A panel that floats over a live camera: glass with extra ink so text
    /// stays readable on any scene.
    func kitchenCameraPanel(radius: CGFloat = Tide.cardRadius) -> some View {
        glassEffect(.regular.tint(Tide.Kitchen.cameraTint), in: .rect(cornerRadius: radius))
    }
}

// MARK: - KitchenForm

/// A Form whose rows sit on Tide fill and let the field show between them.
struct KitchenForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content.listRowBackground(Tide.fill)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - KitchenList

/// A List whose rows sit on Tide fill and let the field show between them.
struct KitchenList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            content.listRowBackground(Tide.fill)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - KitchenFormSection

/// A Form section with a tracked label above it and rows on Tide fill.
struct KitchenFormSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    /// A section with no title, only a footnote underneath.
    init(footer: String, @ViewBuilder content: () -> Content) {
        title = ""
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        Section {
            content.listRowBackground(Tide.fill)
        } header: {
            if !title.isEmpty {
                Text(title).tideLabel()
            }
        } footer: {
            if let footer {
                Text(footer).font(Tide.caption).foregroundStyle(Tide.text3)
            }
        }
    }
}

// MARK: - KitchenSheetModifier

private struct KitchenSheetModifier: ViewModifier {
    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .environment(\.tideInsidePage, true)
            .presentationBackground {
                TideBackground(energy: Tide.sheetEnergy).environment(\.tideMood, mood)
            }
            .presentationDragIndicator(.visible)
    }
}
