//
// SettingsComponents.swift
// Tempo
//
// Reusable building blocks for Settings, in the Tide look: one glass card per
// group, hairlines under the row title, tinted icon tiles, small status
// capsules. Layout tokens come from Tide; shared pieces live in
// DesignSystem/Tide+Settings.swift.
//

import SwiftUI

// MARK: - SettingsGroupCard

/// A glass card that groups related rows, with hairline dividers between
/// them and a small tracked section label above.
///
/// Rows are supplied as an explicit array of type-erased views so the card
/// can insert a divider between each pair (but not after the last) without
/// relying on private SwiftUI variadic-view APIs.
struct SettingsGroupCard: View {
    var title: String?
    let rows: [AnyView]

    @ScaledMetric(relativeTo: .footnote)
    private var tile = Tide.icon

    /// Convenience: build from a result-builder of rows.
    init(title: String? = nil, @SettingsRowBuilder rows: () -> [AnyView]) {
        self.title = title
        self.rows = rows()
    }

    /// Divider inset: row padding + icon-tile width + icon-to-text gap, so
    /// the hairline starts under the row title, not the icon.
    private var dividerInset: CGFloat {
        Tide.s4 + tile + Tide.s3
    }

    var body: some View {
        TideSettingsSection(title: title) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                row
                if index < rows.count - 1 {
                    TideSettingsHairline(inset: dividerInset)
                }
            }
        }
    }
}

// MARK: - SettingsRowBuilder

/// A result builder that collects settings rows into `[AnyView]`, so callers
/// can write rows naturally inside a `SettingsGroupCard { … }` closure.
@resultBuilder
enum SettingsRowBuilder {
    static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        components.flatMap(\.self)
    }

    static func buildExpression(_ expression: some View) -> [AnyView] {
        [AnyView(expression)]
    }

    static func buildOptional(_ component: [AnyView]?) -> [AnyView] {
        component ?? []
    }

    static func buildEither(first component: [AnyView]) -> [AnyView] {
        component
    }

    static func buildEither(second component: [AnyView]) -> [AnyView] {
        component
    }

    static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.flatMap(\.self)
    }
}

// MARK: - SettingsIconTile

/// A small rounded-square SF Symbol tile, tinted per row. It is a fill, not
/// glass: it sits inside a glass card.
struct SettingsIconTile: View {
    let systemName: String
    let tint: Color

    @ScaledMetric(relativeTo: .footnote)
    private var size = Tide.icon

    var body: some View {
        Image(systemName: systemName)
            .font(Tide.settingsGlyph)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(Tide.settingsTileOpacity), in: .rect(cornerRadius: Tide.settingsTileRadius))
            .accessibilityHidden(true)
    }
}

// MARK: - SettingsRowTitle

/// A row's title, never truncated.
private struct SettingsRowTitle: View {
    let text: String
    var color: Color = Tide.text

    var body: some View {
        Text(text)
            .font(Tide.bodyStrong)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The padding every settings row shares.
private extension View {
    func settingsRowFrame(vertical: CGFloat = Tide.s3) -> some View {
        padding(.horizontal, Tide.s4)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, minHeight: Tide.settingsRow, alignment: .leading)
    }
}

// MARK: - SettingsNavRow

/// A tappable row that pushes a detail screen: icon tile + title +
/// optional live summary subtitle + chevron.
struct SettingsNavRow: View {
    let icon: String
    var iconTint: Color = .accentColor
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: Tide.s3) {
            SettingsIconTile(systemName: icon, tint: iconTint)

            VStack(alignment: .leading, spacing: Tide.hair) {
                SettingsRowTitle(text: title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
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
        .settingsRowFrame()
        .contentShape(.rect)
    }
}

// MARK: - SettingsStatusRow

/// Like `SettingsNavRow` but the trailing element is a status pill
/// (for integrations: Connected / Not Set Up / Error).
struct SettingsStatusRow: View {
    let icon: String
    var iconTint: Color = .accentColor
    let title: String
    let status: String
    let statusColor: Color
    var showsChevron = true

    var body: some View {
        TideSettingsRowLine {
            HStack(spacing: Tide.s3) {
                SettingsIconTile(systemName: icon, tint: iconTint)
                SettingsRowTitle(text: title)
            }
        } trailing: {
            HStack(spacing: Tide.s2) {
                SettingsStatusPill(text: status, color: statusColor)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
            }
        }
        .settingsRowFrame()
        .contentShape(.rect)
    }
}

// MARK: - SettingsStatusPill

/// A small tinted capsule used for integration status.
struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Tide.label)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Tide.s3)
            .padding(.vertical, Tide.s1)
            .background(color.opacity(Tide.settingsTileOpacity), in: .capsule)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - SettingsActionRow

/// A tappable row that performs an action (no chevron by default), used for
/// buttons like Subscribe / Restore / Delete. Tint colors the title + icon.
struct SettingsActionRow: View {
    let icon: String
    let title: String
    var tint: Color = Tide.text
    var trailingText: String?

    var body: some View {
        TideSettingsRowLine {
            HStack(spacing: Tide.s3) {
                SettingsIconTile(systemName: icon, tint: tint)
                SettingsRowTitle(text: title, color: tint)
            }
        } trailing: {
            if let trailingText {
                Text(trailingText)
                    .font(Tide.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tide.text3)
            }
        }
        .settingsRowFrame()
        .contentShape(.rect)
    }
}

// MARK: - Preview

#Preview {
    TideSettingsPage {
        SettingsGroupCard(title: "You & your day") {
            SettingsNavRow(
                icon: "clock.fill",
                title: "Schedule", subtitle: "Wake 6:00 · Bed 22:30 · Leisure 19:30"
            )
            SettingsNavRow(
                icon: "dumbbell.fill",
                title: "Training", subtitle: "PPL · 2 football days · kg"
            )
        }

        SettingsGroupCard(title: "Connections") {
            SettingsStatusRow(
                icon: "waveform.path.ecg", title: "Whoop",
                status: "Connected", statusColor: Tide.water
            )
            SettingsStatusRow(
                icon: "fork.knife", title: "Diet Profile",
                status: "Not Set Up", statusColor: Tide.text3
            )
        }

        SettingsGroupCard(title: "Account") {
            SettingsActionRow(icon: "trash", title: "Delete Account", tint: Tide.danger)
        }
    }
}

// MARK: - SettingsFormCard

//
// Card-styled chrome around NATIVE controls (DatePicker/Picker/Toggle/Stepper)
// so detail screens match the root without rebuilding working inputs. Use
// SettingsFormCard as the container and the *Row wrappers inside.

/// A titled card that wraps a column of detail-screen rows. The detail-screen
/// analogue of SettingsGroupCard, but it accepts arbitrary control rows
/// (pickers, toggles) rather than just nav rows.
struct SettingsFormCard<Content: View>: View {
    var title: String?
    var footnote: String?
    var footnoteColor: Color = Tide.text2
    @ViewBuilder var content: Content

    var body: some View {
        TideSettingsSection(title: title, footnote: footnote, footnoteColor: footnoteColor) {
            content
        }
    }
}

// MARK: - SettingsRowDivider

/// A hairline divider between rows inside a SettingsFormCard. By default it
/// starts under the row's title (rows with an icon tile); pass `false` for
/// rows without one.
struct SettingsRowDivider: View {
    var underTitle = true

    @ScaledMetric(relativeTo: .footnote)
    private var tile = Tide.icon

    var body: some View {
        TideSettingsHairline(inset: underTitle ? Tide.s4 + tile + Tide.s3 : Tide.s4)
    }
}

// MARK: - SettingsInfoRow

/// Read-only label + value row — the workhorse for surfacing data.
struct SettingsInfoRow: View {
    let label: String
    let value: String
    var icon: String?
    var iconTint: Color = Tide.text2
    var valueColor: Color = Tide.text2

    var body: some View {
        TideSettingsRowLine {
            HStack(spacing: Tide.s3) {
                if let icon {
                    SettingsIconTile(systemName: icon, tint: iconTint)
                }
                SettingsRowTitle(text: label)
            }
        } trailing: {
            Text(value)
                .font(Tide.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsRowFrame()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SettingsControlRow

/// A card row hosting a trailing native control (DatePicker, Picker, Toggle,
/// Stepper). The control is passed in via the `control` builder so callers
/// keep full native behavior; this only provides the labeled card chrome.
struct SettingsControlRow<Control: View>: View {
    let label: String
    var icon: String?
    var iconTint: Color = .accentColor
    @ViewBuilder var control: Control

    var body: some View {
        TideSettingsRowLine {
            HStack(spacing: Tide.s3) {
                if let icon {
                    SettingsIconTile(systemName: icon, tint: iconTint)
                }
                SettingsRowTitle(text: label)
            }
        } trailing: {
            control
        }
        .settingsRowFrame(vertical: Tide.s2)
    }
}
