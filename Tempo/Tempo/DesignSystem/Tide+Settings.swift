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
    /// The profile picture in the Settings header, and the large one on the Profile page.
    static let settingsAvatar: CGFloat = 56
    static let settingsAvatarLarge: CGFloat = 88
    /// "Connected", "Authorized": a green that keeps its meaning whatever the mood is.
    static let settingsOK = Color.tempoSuccess
    /// The danger zone's glass: the card ink with a push of red.
    static let settingsDangerGlass = danger.opacity(0.2)
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

// MARK: - Press (cards)

/// A card that opens something dips a little under the finger.
struct TideSettingsCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - Avatar

/// The initial of the person's name on the mood colour. Text on the accent is
/// ink, because the accent is a light colour.
struct TideSettingsAvatar: View {
    let initial: String
    var diameter: CGFloat = Tide.settingsAvatar

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .title)
    private var scale = 1.0

    var body: some View {
        Text(initial)
            .font(diameter > Tide.settingsAvatar ? Tide.largeTitle : Tide.title2)
            .foregroundStyle(Tide.ink)
            .frame(width: diameter * scale, height: diameter * scale)
            .background(mood.accent, in: .circle)
            .accessibilityHidden(true)
    }
}
