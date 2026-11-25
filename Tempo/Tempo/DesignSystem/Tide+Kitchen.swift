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
                KitchenSegmentLayout {
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
                .padding(.horizontal, Tide.s2)
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

// MARK: - KitchenSegmentLayout

/// Lays the options of a segmented control side by side. Each gets the width
/// its label needs plus an equal share of what is left, so a long word like
/// "Supplements" is never squeezed to fit the same box as "Pantry".
private struct KitchenSegmentLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? ideal.reduce(0) { $0 + $1.width }
        return CGSize(width: width, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = ideal.reduce(0, +)
        let extra = max(bounds.width - total, 0) / CGFloat(max(subviews.count, 1))
        let squeeze = total > bounds.width && total > 0 ? bounds.width / total : 1
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = ideal[index] * squeeze + extra
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
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
    /// A quiet line under the list.
    var footer: String?
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
            if let footer {
                Text(footer)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s1)
            }
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
                .symbolEffect(.bounce, value: checked)
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
    /// 44 pt by default; the bottom bar uses the height of its primary button.
    var size: CGFloat = Tide.hit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
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

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(label).tideLabel()
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
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
            // The same tile as a failure, in the accent: an empty shelf and a
            // broken one are two states of one family.
            KitchenIconTile(systemName: systemImage, tint: mood.accent, size: Tide.tileLarge)
            Text(title)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
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
        scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom, spacing: 0) {
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

// MARK: - Tide.Kitchen: sizes for the rework

extension Tide.Kitchen {
    /// A leading tile in a row (an icon, a product picture).
    static let tile: CGFloat = 44
    /// The big glass disc with a symbol on an intro or permission screen.
    static let heroDisc: CGFloat = 96
    /// The product picture at the top of a product page.
    static let heroPicture: CGFloat = 208
    /// The height of the small sheet that picks the meal to log a product into.
    static let logSheet: CGFloat = 300
    /// The verdict ring next to the product picture.
    static let verdictDial: CGFloat = 112
    /// Arm length and stroke of the corner brackets on a camera frame.
    static let bracketArm: CGFloat = 28
    static let bracketStroke: CGFloat = 4
    /// Height of the light band that sweeps a frame while it looks.
    static let scanBand: CGFloat = 36
    /// A receipt thumbnail while it is being read.
    static let receiptThumbWidth: CGFloat = 150
    static let receiptThumbHeight: CGFloat = 190
    /// The thin freshness stripe at the edge of a pantry row.
    static let stripe: CGFloat = 4
    /// A small round legend dot.
    static let dot: CGFloat = 8
    /// A round button beside the primary one in a bottom bar (same height as it).
    static let barButton: CGFloat = 52
    /// Suggestion tile and the wide suggestion's picture on the product page.
    static let suggestion: CGFloat = 112
    static let suggestionWide: CGFloat = 72
    /// Stroke of the verdict ring and the number of ticks around it.
    static let ringStroke: CGFloat = 10
    static let tickCount = 60
    /// Ink laid outside the frame of a live camera.
    static let scrim = Tide.ink.opacity(0.5)
    /// Ink under a bar that floats over scrolling content: nearly solid, so
    /// the text behind it never competes with the buttons.
    static let barBacking = 0.94
    /// Where the solid part of that ink starts, from the soft edge.
    static let barBackingSolidFrom = 0.2
    /// How much of the screen a state page's hero fills before it scrolls.
    static let stateFill: CGFloat = 0.85
    /// A photo thumbnail that is not the shown one, and the ring on the shown one.
    static let thumbDimmed = 0.7
    static let thumbRing: CGFloat = 2
    /// The paper of a receipt sketch, its heading line and its item lines.
    static let paperOpacity = 0.92
    static let paperHeading = 0.4
    static let paperLine = 0.22
    /// The line between two finished stages of a timeline.
    static let connectorDone = 0.6
}

// MARK: - KitchenShelfBar

/// One bar split into coloured parts that add up to the whole: how many
/// items are fresh, how many are about to run out. Parts animate as they change.
struct KitchenShelfBar: View {
    struct Part: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let parts: [Part]
    var height: CGFloat = Tide.bar

    private var shown: [Part] {
        parts.filter { $0.value > 0 }
    }

    var body: some View {
        let total = shown.reduce(0) { $0 + $1.value }
        GeometryReader { proxy in
            let gaps = CGFloat(max(shown.count - 1, 0)) * Tide.hair
            let room = max(proxy.size.width - gaps, 0)
            HStack(spacing: Tide.hair) {
                ForEach(shown) { part in
                    Capsule()
                        .fill(part.color)
                        .frame(width: total > 0 ? room * part.value / total : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(Capsule().fill(Tide.track))
        .clipShape(Capsule())
        .animation(Tide.settle, value: shown.map(\.value))
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenBrackets

/// The corner brackets of a camera frame.
private struct KitchenBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(Tide.Kitchen.bracketArm, min(rect.width, rect.height) / 2)
        let radius = min(Tide.controlRadius, arm)
        var path = Path()
        for (corner, xs, ys) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + ys * arm))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + ys * radius))
            path.addQuadCurve(
                to: CGPoint(x: corner.x + xs * radius, y: corner.y),
                control: corner
            )
            path.addLine(to: CGPoint(x: corner.x + xs * arm, y: corner.y))
        }
        return path
    }
}

// MARK: - KitchenFrame

/// A camera frame: lit corner brackets, a soft glow and, while it is looking,
/// a band of light that sweeps it. Holds still under Reduce Motion. Decoration
/// only, so it is hidden from VoiceOver.
struct KitchenFrame: View {
    var width: CGFloat = Tide.Kitchen.viewfinderWidth
    var height: CGFloat = Tide.Kitchen.viewfinderHeight
    var looking = true

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var sweep = false

    var body: some View {
        ZStack(alignment: .top) {
            KitchenBrackets()
                .stroke(
                    mood.accent,
                    style: StrokeStyle(lineWidth: Tide.Kitchen.bracketStroke, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: mood.accent.opacity(0.5), radius: Tide.s2)
            if looking, !reduceMotion {
                LinearGradient(
                    colors: [mood.accent.opacity(0), mood.accent.opacity(0.4), mood.accent.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Tide.Kitchen.scanBand)
                .padding(.horizontal, Tide.s3)
                .offset(y: sweep ? height - Tide.Kitchen.scanBand : 0)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Dims a live camera everywhere except a rounded window in the middle.
    func kitchenScrim(width: CGFloat = Tide.Kitchen.viewfinderWidth, height: CGFloat = Tide.Kitchen.viewfinderHeight) -> some View {
        overlay {
            Tide.Kitchen.scrim
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                                .frame(width: width, height: height)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

// MARK: - KitchenHeroDisc

/// A big glass disc with one symbol: the picture on an intro or permission screen.
struct KitchenHeroDisc: View {
    let systemImage: String
    var tint: Color?

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric
    private var size: CGFloat = Tide.Kitchen.heroDisc

    var body: some View {
        Image(systemName: systemImage)
            .font(Tide.largeTitle)
            .imageScale(.large)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint ?? mood.accent)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Tide.glassCard), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - KitchenSheetHeader

/// The top of a sheet: what this is, in one icon, one title and one line.
struct KitchenSheetHeader: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color?

    var body: some View {
        HStack(alignment: .center, spacing: Tide.s3) {
            KitchenIconTile(systemName: systemImage, tint: tint, size: Tide.Kitchen.tile + Tide.s2)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.title2)
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - KitchenFailure

/// Something went wrong, in the same glass card as everything else: what
/// happened, one way to try again and an optional quieter second way out.
struct KitchenFailure: View {
    let title: String
    let message: String
    var retryTitle = "Try again"
    var retry: (() -> Void)?
    var secondaryTitle: String?
    var secondary: (() -> Void)?

    @State
    private var taps = 0

    var body: some View {
        VStack(spacing: Tide.s4) {
            KitchenIconTile(systemName: "exclamationmark.triangle.fill", tint: Tide.danger, size: Tide.tileLarge)
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
            if retry != nil || secondary != nil {
                VStack(spacing: Tide.s2) {
                    if let retry {
                        Button(retryTitle) {
                            taps += 1
                            retry()
                        }
                        .buttonStyle(.tidePrimary)
                    }
                    if let secondaryTitle, let secondary {
                        Button(secondaryTitle, action: secondary)
                            .buttonStyle(.tideGlass)
                    }
                }
                .padding(.top, Tide.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s6)
        .frame(maxWidth: Tide.stateWidth)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

// MARK: - KitchenHistoryStrip

/// A row of small marks, one per day, lit when the day counts: a month of doses at a glance.
struct KitchenHistoryStrip: View {
    /// Oldest first.
    let days: [Bool]
    var color: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.hair) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, on in
                Capsule()
                    .fill(on ? (color ?? mood.accent) : Tide.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: Tide.s5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenNotice

/// A short note inside a page: an icon, what is going on, and optionally one
/// action. For warnings, errors and things that changed.
struct KitchenNotice: View {
    let systemImage: String
    let text: String
    var tint: Color = Tide.Kitchen.warn
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(tint)
                .frame(width: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(tint)
                    .frame(minHeight: Tide.hit)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - KitchenRowPressStyle

/// A full-width row that lights softly under the finger.
struct KitchenRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Tide.fill : Color.clear)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - KitchenListeningRing

/// Soft rings that swell out from a mic button while it listens, so a quiet room still looks alive.
/// Holds still under Reduce Motion. Decoration only.
struct KitchenListeningRing: View {
    let active: Bool
    var tint: Color?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var swell = false

    var body: some View {
        ZStack {
            ForEach(0 ..< 2, id: \.self) { index in
                Circle()
                    .stroke(tint ?? mood.accent, lineWidth: Tide.hair)
                    .scaleEffect(swell ? 1.6 + CGFloat(index) * 0.3 : 1)
                    .opacity(swell ? 0 : (active ? 0.5 : 0))
                    .animation(
                        swell ? .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(index) * 0.7) : .default,
                        value: swell
                    )
            }
        }
        .onAppear { swell = active && !reduceMotion }
        .onChange(of: active) { _, isActive in
            swell = isActive && !reduceMotion
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenLevelMeter

/// Three pips that fill up to a low / medium / high level, so a traffic light reads at a glance.
/// `filled` is 0 to 3; the colour says whether that is good or bad.
struct KitchenLevelMeter: View {
    let filled: Int
    let tint: Color

    @ScaledMetric
    private var pipWidth: CGFloat = Tide.s4
    @ScaledMetric
    private var pipHeight: CGFloat = Tide.s1

    var body: some View {
        HStack(spacing: Tide.hair) {
            ForEach(0 ..< 3, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tint : Tide.track)
                    .frame(width: pipWidth, height: pipHeight)
            }
        }
        .animation(Tide.snap, value: filled)
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenChoiceChips

/// One choice out of a handful, as a row of chips that scrolls sideways: each
/// has an icon and a name. The chosen one fills with the mood accent.
struct KitchenChoiceChips<Value: Hashable>: View {
    let options: [Value]
    @Binding
    var selection: Value
    let title: (Value) -> String
    let icon: (Value) -> String

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tide.s2) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(Tide.snap) { selection = option }
                    } label: {
                        Label(title(option), systemImage: icon(option))
                            .font(Tide.bodyStrong)
                            .lineLimit(1)
                            .foregroundStyle(selected ? Tide.ink : Tide.text)
                            .padding(.horizontal, Tide.s4)
                            .frame(minHeight: Tide.hit)
                            .background(selected ? mood.accent : Tide.fill, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: selected) { _, new in new }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - KitchenNumberField

/// A labelled number you type, shown as a large figure on a tile: a macro per
/// serving, a quantity, a price. The whole tile is the hit area.
struct KitchenNumberField: View {
    let label: String
    var unit: String?
    var placeholder = "0"
    var tint: Color?
    @Binding
    var text: String
    var keyboard: UIKeyboardType = .decimalPad
    /// Set on the text field itself, for the tests that type into it.
    var identifier: String?

    @ScaledMetric
    private var size: CGFloat = Tide.numeralS
    @FocusState
    private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(spacing: Tide.s1) {
                if let tint {
                    Circle().fill(tint)
                        .frame(width: Tide.Kitchen.dot, height: Tide.Kitchen.dot)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .tideLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .focused($focused)
                    .font(Tide.numeral(size))
                    .foregroundStyle(Tide.text)
                    .minimumScaleFactor(Tide.labelShrink)
                    .accessibilityLabel(unit.map { "\(label) (\($0))" } ?? label)
                    .identified(identifier)
                if let unit {
                    Text(unit)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(Tide.s3)
        .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.row, alignment: .leading)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .strokeBorder((tint ?? Tide.text2).opacity(focused ? 0.8 : 0), lineWidth: 1)
        )
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .animation(Tide.snap, value: focused)
    }
}

// MARK: - KitchenBarButtonStyle

/// The main button of a bottom bar. Enabled, it is the Tide primary. Disabled,
/// it turns to glass with quiet text, so the rows scrolling under the bar never
/// show through a faded yellow and collide with its label.
struct KitchenBarButtonStyle: ButtonStyle {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(Tide.headline)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.barButton)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
        return Group {
            if isEnabled {
                label
                    .foregroundStyle(Tide.ink)
                    .background(mood.accent, in: .capsule)
            } else {
                label
                    .foregroundStyle(Tide.text2)
                    .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
            }
        }
        .animation(Tide.snap, value: isEnabled)
    }
}

extension ButtonStyle where Self == KitchenBarButtonStyle {
    static var kitchenBar: KitchenBarButtonStyle {
        KitchenBarButtonStyle()
    }
}

// MARK: - KitchenPair

/// Two fields side by side, equal width. At the accessibility text sizes they
/// stack, one per line. A plain stack layout (not a lazy grid), so a live
/// change of text size relays out every field at once.
struct KitchenPair<First: View, Second: View>: View {
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        layout {
            first.frame(maxWidth: .infinity)
            second.frame(maxWidth: .infinity)
        }
    }
}

// MARK: - KitchenIconTile

/// `TideIconTile` that keeps its size at the accessibility text sizes. The
/// tile is a fixed square but its glyph scales with the text, so left alone
/// the glyph outgrows the tile.
struct KitchenIconTile: View {
    let systemName: String
    var tint: Color?
    var size: CGFloat = Tide.Kitchen.tile

    var body: some View {
        TideIconTile(systemName: systemName, tint: tint, size: size)
            .dynamicTypeSize(.large)
    }
}

// MARK: - KitchenModeBar

/// The mode switch on top of the scanner: every mode is one tile with its
/// icon over its name, all in one glass bar, and a pill of accent slides to the
/// chosen one. All of them fit the screen, so none hides off to the side. At
/// the accessibility text sizes the tiles go two by two, icon beside name.
struct KitchenModeBar<Value: Hashable>: View {
    let options: [Value]
    @Binding
    var selection: Value
    let title: (Value) -> String
    let icon: (Value) -> String
    let identifier: (Value) -> String

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Namespace
    private var pill

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Tide.s1), GridItem(.flexible())], spacing: Tide.s1) {
                    ForEach(options, id: \.self, content: tile)
                }
            } else {
                HStack(spacing: Tide.s1) {
                    ForEach(options, id: \.self, content: tile)
                }
            }
        }
        .padding(Tide.s1)
        .glassEffect(
            .regular.tint(Tide.Kitchen.cameraTint),
            in: .rect(cornerRadius: typeSize.isAccessibilitySize ? Tide.tileRadius : Tide.cardRadius)
        )
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tile(_ option: Value) -> some View {
        let selected = option == selection
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: Tide.s2))
            : AnyLayout(VStackLayout(spacing: Tide.hair))
        return Button {
            withAnimation(Tide.snap) { selection = option }
        } label: {
            layout {
                Image(systemName: icon(option))
                    .font(Tide.bodyStrong)
                    .accessibilityHidden(true)
                Text(title(option))
                    .font(Tide.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .foregroundStyle(selected ? Tide.ink : Tide.text)
            .padding(.horizontal, Tide.s1)
            .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.barButton)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                        .fill(mood.accent)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier(option))
    }
}

// MARK: - KitchenStateAction

/// One way out of a `KitchenStatePage`: the main one, a second one, or a quiet
/// text link.
struct KitchenStateAction: Identifiable {
    enum Role {
        case primary
        case secondary
        case quiet
        /// A quiet link in the danger colour: stop, remove, delete.
        case destructive
    }

    let title: String
    var systemImage: String?
    var role: Role = .secondary
    var identifier: String?
    /// False while the action is running or has nothing to act on.
    var isEnabled = true
    let action: () -> Void

    let id = UUID()
}

// MARK: - KitchenStateHero

/// What a state of a scan flow is about: one big glass disc, a title and a line
/// of help, set straight on the field. While `working` a ring breathes behind
/// the disc.
struct KitchenStateHero: View {
    let systemImage: String
    var tint: Color?
    let title: String
    var message = ""
    var working = false

    var body: some View {
        VStack(spacing: Tide.s4) {
            KitchenHeroDisc(systemImage: systemImage, tint: tint)
                .background { KitchenListeningRing(active: working, tint: tint) }
                .padding(.vertical, working ? Tide.s5 : 0)
            KitchenStateText(title: title, message: message)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - KitchenStateText

/// The words of a state: a bold title and a line of help, centred.
struct KitchenStateText: View {
    let title: String
    var message = ""

    var body: some View {
        VStack(spacing: Tide.s2) {
            Text(title)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !message.isEmpty {
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - KitchenReceiptSketch

/// A drawn receipt inside the lit corners of the camera: the picture of the
/// receipt screens. It is the size of the receipt picture that comes up while
/// a scan is read, so capture and reading feel like one object.
struct KitchenReceiptSketch: View {
    /// Widths of the item lines, as multiples of the 40 pt step.
    private let lines: [CGFloat] = [2.1, 1.5, 2.3, 1.2, 1.9, 1.4, 2.0, 1.1]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        ZStack {
            shape
                .fill(Tide.text.opacity(Tide.Kitchen.paperOpacity))
                .frame(width: Tide.Kitchen.receiptThumbWidth, height: Tide.Kitchen.receiptThumbHeight)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Capsule()
                            .fill(Tide.ink.opacity(Tide.Kitchen.paperHeading))
                            .frame(width: Tide.s10 * 2, height: Tide.s2)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, Tide.s1)
                        ForEach(lines.indices, id: \.self) { index in
                            HStack(spacing: Tide.s2) {
                                Capsule()
                                    .fill(Tide.ink.opacity(Tide.Kitchen.paperLine))
                                    .frame(width: Tide.s10 * lines[index], height: Tide.s1 + Tide.hair)
                                Spacer(minLength: 0)
                                Capsule()
                                    .fill(Tide.ink.opacity(Tide.Kitchen.paperLine))
                                    .frame(width: Tide.s5, height: Tide.s1 + Tide.hair)
                            }
                        }
                    }
                    .padding(Tide.s4)
                }
            KitchenFrame(
                width: Tide.Kitchen.receiptThumbWidth,
                height: Tide.Kitchen.receiptThumbHeight,
                looking: true
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - KitchenStatePage

/// A whole screen for one state of a scan flow (nothing found, a lookup that
/// failed, a camera that is off): the hero sits in the upper middle, and every
/// way out is a full-width button in the bar at the bottom, where the thumb is.
/// The main action is the bar button, a pair of second choices share a row, and
/// a quiet link goes last. The hero scrolls when the text sizes grow.
struct KitchenStatePage<Hero: View>: View {
    var actions: [KitchenStateAction] = []
    @ViewBuilder var hero: Hero

    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        if actions.isEmpty {
            page
        } else {
            page.kitchenBottomBar {
                bar.background { backing }
            }
        }
    }

    /// At the accessibility text sizes the bar is tall and the hero scrolls
    /// under it, so the bar gets ink under it that fades out just above it.
    /// At the usual sizes the hero never reaches it.
    @ViewBuilder
    private var backing: some View {
        if typeSize.isAccessibilitySize {
            LinearGradient(
                stops: [
                    .init(color: Tide.ink.opacity(0), location: 0),
                    .init(color: Tide.ink, location: Tide.Kitchen.barBackingSolidFrom),
                    .init(color: Tide.ink, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -Tide.s8)
            .padding(.bottom, -Tide.s10)
            .padding(.horizontal, -Tide.edge)
            .allowsHitTesting(false)
        }
    }

    private var page: some View {
        GeometryReader { proxy in
            ScrollView {
                hero
                    .frame(maxWidth: Tide.stateWidth)
                    .padding(.horizontal, Tide.edge)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height * Tide.Kitchen.stateFill)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var bar: some View {
        let rows = secondaryRows
        return VStack(spacing: Tide.s3) {
            ForEach(actions.filter { $0.role == .primary }) { item in
                Button(action: item.action) {
                    label(item)
                }
                .buttonStyle(.kitchenBar)
                .disabled(!item.isEnabled)
                .identified(item.identifier)
            }
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Tide.s3) {
                    ForEach(rows[index]) { item in
                        Button(action: item.action) {
                            label(item).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tideGlass)
                        .disabled(!item.isEnabled)
                        .identified(item.identifier)
                    }
                }
            }
            ForEach(actions.filter { $0.role == .quiet || $0.role == .destructive }) { item in
                Button(action: item.action) {
                    label(item)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(item.role == .destructive ? Tide.danger : mood.accent)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .identified(item.identifier)
            }
        }
    }

    /// Second choices go two to a row; an odd one out takes the first row alone.
    /// At the accessibility text sizes each gets its own row.
    private var secondaryRows: [[KitchenStateAction]] {
        var rest = actions.filter { $0.role == .secondary }
        if typeSize.isAccessibilitySize {
            return rest.map { [$0] }
        }
        var rows: [[KitchenStateAction]] = []
        if rest.count % 2 == 1 {
            rows.append([rest.removeFirst()])
        }
        while !rest.isEmpty {
            rows.append(Array(rest.prefix(2)))
            rest.removeFirst(min(2, rest.count))
        }
        return rows
    }

    @ViewBuilder
    private func label(_ item: KitchenStateAction) -> some View {
        if let systemImage = item.systemImage {
            Label(item.title, systemImage: systemImage)
        } else {
            Text(item.title)
        }
    }
}

private extension View {
    /// Puts an accessibility identifier on a view only when there is one.
    @ViewBuilder
    func identified(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

// MARK: - KitchenGlassIcon

/// A round glass button face with one icon, for a Menu's label (a Button that
/// wants the same look uses `KitchenIconButton`). Shows a spinner while it works.
struct KitchenGlassIcon: View {
    let systemImage: String
    var isWorking = false
    var size: CGFloat = Tide.hit

    var body: some View {
        Group {
            if isWorking {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(Tide.bodyStrong)
            }
        }
        .foregroundStyle(Tide.text)
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        .contentShape(.circle)
    }
}

// MARK: - KitchenSpendTrend

/// Weeks of spend as bars, oldest first, the way the Spending page reads them:
/// tap a bar to read that week above. A week over its budget is red, the chosen
/// week is lit, and a dashed line marks the budget. Each bar is a button with
/// the week, the total and "over budget" in its VoiceOver label.
struct KitchenSpendTrend: View {
    let weeks: [GroceryWeeklySpend]
    /// The chosen week (its `id`).
    @Binding var selection: Date?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .body)
    private var plotHeight: CGFloat = 96

    private var cap: Double? {
        weeks.last?.budgetCapUSD.map(Double.init)
    }

    /// The tallest bar, or the budget when that is higher, so the budget line is always on the chart.
    private var scaleMax: Double {
        max(weeks.map(\.totalUSD).max() ?? 0, cap ?? 0, 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: Tide.s2) {
                ForEach(weeks) { week in
                    column(week)
                }
            }
            if let cap {
                BudgetLine()
                    .stroke(Tide.text3, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                    .offset(y: plotHeight * (1 - cap / scaleMax))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(Tide.snap, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly spend")
    }

    private func column(_ week: GroceryWeeklySpend) -> some View {
        let isSelected = week.id == selection
        return Button {
            selection = week.id
        } label: {
            VStack(spacing: Tide.s1) {
                ZStack(alignment: .bottom) {
                    Capsule().fill(Tide.track)
                    Capsule()
                        .fill(color(week, isSelected: isSelected))
                        .frame(height: week.totalUSD > 0 ? max(Tide.s1, plotHeight * week.totalUSD / scaleMax) : 0)
                }
                .frame(height: plotHeight)
                // The date of the week is in the line above when a week is chosen;
                // the day number only helps to tell the bars apart at normal sizes.
                if !typeSize.isAccessibilitySize {
                    Text(week.weekStartDate.formatted(.dateTime.day()))
                        .font(Tide.caption)
                        .foregroundStyle(isSelected ? Tide.text : Tide.text3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(for: week))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func color(_ week: GroceryWeeklySpend, isSelected: Bool) -> Color {
        let base = week.isOverBudget ? Tide.danger : mood.accent
        return isSelected ? base : base.opacity(0.4)
    }

    /// "Week of Nov 3, $73.45, over budget".
    static func accessibilityLabel(for week: GroceryWeeklySpend) -> String {
        let date = week.weekStartDate.formatted(date: .abbreviated, time: .omitted)
        let over = week.isOverBudget ? ", over budget" : ""
        return "Week of \(date), \(SpendingSummary.money(week.totalUSD))\(over)"
    }

    private struct BudgetLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
