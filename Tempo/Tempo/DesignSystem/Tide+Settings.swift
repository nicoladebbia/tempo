//
// Tide+Settings.swift
// Tempo
//
// The pieces every Settings page is made of: one glass card per group of rows,
// hairlines inset under the row title, a pressed state that stays inside the
// card, and the page wrapper that puts them on the Tide field.
// Everything here is prefixed `TideSettings` so it cannot collide with the
// other areas' Tide extensions.
//

import SwiftUI

// MARK: - Tokens

extension Tide {
    /// Corner of the small icon tile at the start of a settings row.
    static let settingsTileRadius: CGFloat = 8
    /// How strongly a row's colour tints its icon tile.
    static let settingsTileOpacity = 0.18
    /// The symbol inside a tile. A text style, so it grows with the tile.
    static let settingsGlyph = Font.system(.footnote, weight: .semibold)
    /// A settings row: the smallest tap target plus a little air.
    static let settingsRow: CGFloat = hit + s2
    /// Gap between two groups on a settings page.
    static let settingsGroupGap: CGFloat = s6
    /// How far an icon tile may grow with the text size, so the title keeps its room.
    static let settingsTileCap: CGFloat = icon * 1.5
    /// The profile picture in the Settings header, and the large one on the Profile page.
    static let settingsAvatar: CGFloat = 56
    static let settingsAvatarLarge: CGFloat = 88
    /// "Connected", "Authorized": a green that keeps its meaning whatever the mood is.
    static let settingsOK = success
    /// "Needs attention": a warm amber, softer than the danger red.
    static let settingsAttention = streak
    /// The danger zone's glass: the card ink with a push of red.
    static let settingsDangerGlass = danger.opacity(0.2)
    /// The ring in a settings hero (the day dial, the focus cycle), at the default text size.
    static let settingsDial: CGFloat = 148
    /// How far the ring may grow with the text size before it crowds its legend.
    static let settingsDialCap: CGFloat = settingsDial * 1.4
    /// The stroke of that ring.
    static let settingsDialLine: CGFloat = 12
    /// The gap, in degrees, left between two arcs of a ring.
    static let settingsArcGap = 3.0
    /// The dot that marks a time on the day dial.
    static let settingsMarker: CGFloat = 12
    /// A big symbol tile at the head of a mode or a plan.
    static let settingsBigTile: CGFloat = 52
    /// A night: sleep reads as a cool, quiet colour on every mood.
    static let settingsNight = fat
    /// The waking part of the day dial: a quiet neutral, so wind-down and night stand out.
    static let settingsDay = Tide.text.opacity(0.28)
}

// MARK: - TideSettingsHairline

/// A one-pixel divider in the Tide hairline colour.
struct TideSettingsHairline: View {
    /// Space left of the line, so it starts under a row's title.
    var inset: CGFloat = 0

    @Environment(\.displayScale)
    private var displayScale

    var body: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(height: 1 / displayScale)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - Surface

extension View {
    /// The glass card behind a group of rows. Rows are clipped to the card, so
    /// a pressed row never pokes out of a rounded corner.
    func tideSettingsSurface(radius: CGFloat = Tide.cardRadius, tint: Color = Tide.glassCard) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(.rect(cornerRadius: radius))
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
    }
}

// MARK: - TideSettingsSection

/// A small tracked label, one glass card around the rows, and an optional
/// footnote. Both `SettingsGroupCard` and `SettingsFormCard` are this.
struct TideSettingsSection<Content: View>: View {
    var title: String?
    var footnote: String?
    var footnoteColor: Color = Tide.text2
    /// The destructive group at the bottom of a page: red label, red-tinted glass.
    var isDanger = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            if let title {
                Text(title)
                    .tideLabel(isDanger ? Tide.danger : Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s2)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                content
            }
            .tideSettingsSurface(tint: isDanger ? Tide.settingsDangerGlass : Tide.glassCard)

            if let footnote {
                Text(footnote)
                    .font(Tide.caption)
                    .foregroundStyle(footnoteColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s2)
            }
        }
    }
}

// MARK: - TideSettingsRowButtonStyle

/// The pressed state of a tappable settings row: a soft fill that fills the
/// row edge to edge, and a dimmed row when the control is disabled.
struct TideSettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Tide.fill : Color.clear)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == TideSettingsRowButtonStyle {
    static var tideSettingsRow: TideSettingsRowButtonStyle {
        TideSettingsRowButtonStyle()
    }
}

// MARK: - TideSettingsRowLine

/// Puts a row's leading part and its trailing part side by side, or stacks
/// them when the text size is an accessibility size, so nothing truncates.
struct TideSettingsRowLine<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Tide.s2) {
                leading
                trailing
            }
        } else {
            HStack(spacing: Tide.s3) {
                leading
                Spacer(minLength: Tide.s2)
                trailing
            }
        }
    }
}

// MARK: - TideSettingsPage

/// The scaffold of a settings page: a scrolling column of glass groups on the
/// Tide field. The groups share one glass container so they render together.
struct TideSettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: Tide.s1) {
                VStack(spacing: Tide.settingsGroupGap) {
                    content
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .tidePage()
    }
}

// MARK: - TideSettingsHero

/// A glass card at the top of a settings page: one big figure or picture, a
/// small label under it, and room for a short line of support.
struct TideSettingsHero<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            content
        }
        .tideCard(padding: Tide.s5)
    }
}

// MARK: - TideSettingsCardPressStyle

/// A card that opens something dips a little under the finger.
struct TideSettingsCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - TideSettingsAvatar

/// The initial of the person's name on the mood colour. Text on the accent is
/// ink, because the accent is a light colour.
struct TideSettingsAvatar: View {
    let initial: String
    var diameter: CGFloat = Tide.settingsAvatar

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .title)
    private var scaledScale = 1.0

    /// The picture grows with the text, but never past one and a half times.
    private var scale: CGFloat {
        min(scaledScale, 1.5)
    }

    var body: some View {
        Text(initial)
            .font(diameter > Tide.settingsAvatar ? Tide.largeTitle : Tide.title2)
            .foregroundStyle(Tide.ink)
            .frame(width: diameter * scale, height: diameter * scale)
            .background(mood.accent, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - SettingsArc

/// One coloured stretch of a ring, as fractions of the full turn from the top.
struct SettingsArc: Identifiable {
    let id: String
    /// Where it starts: 0 is the top, 0.25 is three o'clock.
    let start: Double
    /// How much of the turn it covers, 0...1.
    let length: Double
    let color: Color
}

// MARK: - SettingsRingMarker

/// A time marked on a ring: a dot sitting on the line.
struct SettingsRingMarker: Identifiable {
    let id: String
    let position: Double
    let color: Color
}

// MARK: - SettingsRing

/// Arcs of colour round a dark track, dots on the line, and whatever the
/// caller puts in the middle. Moving an arc animates with the Tide snap.
struct SettingsRing<Center: View>: View {
    let arcs: [SettingsArc]
    var markers: [SettingsRingMarker] = []
    @ViewBuilder var center: Center

    @ScaledMetric(relativeTo: .largeTitle)
    private var scaledDiameter = Tide.settingsDial
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var diameter: CGFloat {
        min(scaledDiameter, Tide.settingsDialCap)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tide.track, lineWidth: Tide.settingsDialLine)
            ForEach(arcs) { arc in
                ForEach(Array(Self.pieces(of: arc).enumerated()), id: \.offset) { _, piece in
                    Circle()
                        .trim(from: piece.lowerBound, to: piece.upperBound)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: Tide.settingsDialLine, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            ForEach(markers) { marker in
                Circle()
                    .fill(Tide.text)
                    .overlay(Circle().strokeBorder(marker.color, lineWidth: Tide.hair * 2))
                    .frame(width: Tide.settingsMarker, height: Tide.settingsMarker)
                    // On the middle of the stroke, not its outer edge.
                    .offset(Self.offset(of: marker.position, radius: (diameter - Tide.settingsDialLine) / 2))
            }
            center
                .padding(Tide.settingsDialLine + Tide.s2)
        }
        .padding(Tide.settingsDialLine / 2)
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : Tide.snap, value: arcs.map(\.length))
        .animation(reduceMotion ? nil : Tide.snap, value: arcs.map(\.start))
    }

    /// An arc as one or two `trim` ranges (it may run past the top), with a
    /// small gap taken off each end so neighbours never touch.
    private static func pieces(of arc: SettingsArc) -> [Range<Double>] {
        let gap = Tide.settingsArcGap / 360
        guard arc.length > gap * 2 else {
            return []
        }
        let from = arc.start + gap / 2
        let to = arc.start + arc.length - gap / 2
        let wrapped = from.truncatingRemainder(dividingBy: 1)
        let end = wrapped + (to - from)
        if end <= 1 {
            return [wrapped ..< end]
        }
        return [wrapped ..< 1, 0 ..< end - 1]
    }

    private static func offset(of position: Double, radius: CGFloat) -> CGSize {
        let angle = (position * 360 - 90) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

// MARK: - SettingsLegendRow

/// A colour dot, a name and a value: one line of the key beside a ring.
struct SettingsLegendRow: View {
    let color: Color
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Circle()
                .fill(color)
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(Tide.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Spacer(minLength: Tide.s1)
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SettingsRingHero

/// The ring on the left, its key on the right; stacked at accessibility sizes.
struct SettingsRingHero<Ring: View, Key: View>: View {
    @ViewBuilder var ring: Ring
    @ViewBuilder var key: Key

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s5))
        layout {
            ring
            VStack(alignment: .leading, spacing: Tide.s3) {
                key
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - SettingsModeCard

/// A switch that deserves more than a row: a big symbol tile, what it is, what
/// it does, and the switch. Whatever else belongs to the mode (a date) goes
/// in `extra` and shows under a hairline.
struct SettingsModeCard<Extra: View>: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color?
    /// The switch's accessibility identifier, where a test drives it.
    var identifier: String?
    var isDisabled = false
    @Binding var isOn: Bool
    @ViewBuilder var extra: Extra

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// The switch, carrying an identifier only where a test drives it.
    @ViewBuilder
    private var switchControl: some View {
        let control = Toggle(title, isOn: $isOn)
            .labelsHidden()
            .disabled(isDisabled)
        if let identifier {
            control.accessibilityIdentifier(identifier)
        } else {
            control
        }
    }

    var body: some View {
        let color = tint ?? mood.accent
        VStack(alignment: .leading, spacing: Tide.s3) {
            let head = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
            head {
                TideIconTile(systemName: icon, tint: isOn ? color : Tide.text3, size: Tide.settingsBigTile)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
                switchControl
            }
            extra
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .animation(reduceMotion ? nil : Tide.snap, value: isOn)
    }
}

extension SettingsModeCard where Extra == EmptyView {
    init(
        icon: String, title: String, detail: String, tint: Color? = nil,
        identifier: String? = nil, isDisabled: Bool = false, isOn: Binding<Bool>
    ) {
        self.init(
            icon: icon, title: title, detail: detail, tint: tint,
            identifier: identifier, isDisabled: isDisabled, isOn: isOn
        ) { EmptyView() }
    }
}

// MARK: - SettingsConnectionCard

/// One outside service on the Connections page: its mark, its name, a status
/// pill, a line about it and exactly one button. At accessibility sizes the
/// parts stack so nothing truncates.
struct SettingsConnectionCard: View {
    let icon: String
    let title: String
    let statusText: String
    let statusColor: Color
    let detail: String
    let buttonTitle: String
    /// The request is in flight: the button shows a spinner and waits.
    var isBusy = false
    /// What went wrong the last time the button was pressed.
    var errorText: String?
    /// Identifier for the button, where a test drives it.
    var identifier: String?
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSettingsRowLine {
                HStack(spacing: Tide.s3) {
                    TideIconTile(systemName: icon, tint: statusColor == Tide.settingsOK ? mood.accent : Tide.text3, size: Tide.settingsBigTile)
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } trailing: {
                SettingsStatusPill(text: statusText, color: statusColor)
            }

            Text(detail)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Button(action: action) {
                HStack(spacing: Tide.s2) {
                    if isBusy {
                        ProgressView()
                    }
                    Text(buttonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
            .disabled(isBusy)
            .accessibilityIdentifier(identifier ?? "connectionButton")
        }
        .tideCard(padding: Tide.s5, radius: Tide.cardRadius)
        .accessibilityElement(children: .contain)
    }
}
