//
// SettingsComponents.swift
// Tempo
//
// Reusable building blocks for the redesigned Settings screen.
// All values come from the design tokens (TempoSpacing / TempoRadius /
// Color.tempo* / Font.tempo*) — no hardcoded magic numbers.
//

import SwiftUI

// MARK: - SettingsGroupCard

/// A rounded card that groups related rows, with hairline dividers between
/// them and an optional uppercased section title above. Replaces the flat
/// `List` section + `.listRowBackground` pattern.
///
/// Rows are supplied as an explicit array of type-erased views so the card
/// can insert a divider between each pair (but not after the last) without
/// relying on private SwiftUI variadic-view APIs.
struct SettingsGroupCard: View {
    var title: String?
    let rows: [AnyView]

    /// Convenience: build from a result-builder of rows.
    init(title: String? = nil, @SettingsRowBuilder rows: () -> [AnyView]) {
        self.title = title
        self.rows = rows()
    }

    /// Divider inset: card padding + icon-tile width + icon-to-text gap, so
    /// the hairline starts under the row title, not the icon.
    private var dividerInset: CGFloat { TempoSpacing.lg + 28 + TempoSpacing.md }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if let title {
                Text(title.uppercased())
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.leading, TempoSpacing.sm)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(Color.tempoDivider)
                            .padding(.leading, dividerInset)
                    }
                }
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }
}

// MARK: - SettingsRowBuilder

/// A result builder that collects settings rows into `[AnyView]`, so callers
/// can write rows naturally inside a `SettingsGroupCard { … }` closure.
@resultBuilder
enum SettingsRowBuilder {
    static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        components.flatMap { $0 }
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
        components.flatMap { $0 }
    }
}

// MARK: - SettingsIconTile

/// A 28×28 rounded-square SF Symbol tile, tinted per settings group.
struct SettingsIconTile: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(TempoOpacity.o15))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
    }
}

// MARK: - SettingsNavRow

/// A tappable row that pushes a detail screen: icon tile + title +
/// optional live summary subtitle + chevron.
struct SettingsNavRow: View {
    let icon: String
    var iconTint: Color = .tempoSignal
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            SettingsIconTile(systemName: icon, tint: iconTint)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(title)
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TempoSpacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - SettingsStatusRow

/// Like `SettingsNavRow` but the trailing element is a status pill
/// (for integrations: Connected / Not Set Up / Error).
struct SettingsStatusRow: View {
    let icon: String
    var iconTint: Color = .tempoElectric
    let title: String
    let status: String
    let statusColor: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            SettingsIconTile(systemName: icon, tint: iconTint)

            Text(title)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)

            Spacer(minLength: TempoSpacing.sm)

            SettingsStatusPill(text: status, color: statusColor)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A small tinted pill used for integration status.
struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, TempoSpacing.xxs)
            .background(color.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
    }
}

// MARK: - SettingsActionRow

/// A tappable row that performs an action (no chevron by default), used for
/// buttons like Subscribe / Restore / Delete. Tint colors the title + icon.
struct SettingsActionRow: View {
    let icon: String
    let title: String
    var tint: Color = .tempoTextPrimary
    var trailingText: String?

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            SettingsIconTile(systemName: icon, tint: tint)

            Text(title)
                .font(.tempoSubheadline)
                .foregroundStyle(tint)

            Spacer(minLength: TempoSpacing.sm)

            if let trailingText {
                Text(trailingText)
                    .font(.tempoDataSmall)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.tempoBgPrimary.ignoresSafeArea()
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                SettingsGroupCard(title: "You & your day") {
                    SettingsNavRow(
                        icon: "clock.fill", iconTint: .tempoAmber,
                        title: "Schedule", subtitle: "Wake 6:00 · Bed 22:30 · Leisure 60m"
                    )
                    SettingsNavRow(
                        icon: "dumbbell.fill", iconTint: .tempoSignal,
                        title: "Training", subtitle: "PPL · 2 football days · kg"
                    )
                }

                SettingsGroupCard(title: "Connections") {
                    SettingsStatusRow(
                        icon: "waveform.path.ecg", title: "Whoop",
                        status: "Connected", statusColor: .tempoSuccess
                    )
                    SettingsStatusRow(
                        icon: "fork.knife", title: "Diet Profile",
                        status: "Not Set Up", statusColor: .tempoTextTertiary
                    )
                }

                SettingsGroupCard(title: "Account") {
                    SettingsActionRow(
                        icon: "trash", title: "Delete Account", tint: .tempoError
                    )
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
    }
}

// MARK: - Detail-screen primitives
//
// Card-styled chrome around NATIVE controls (DatePicker/Picker/Toggle/Stepper)
// so detail screens match the redesigned root without rebuilding working
// inputs. Use SettingsFormCard as the container and the *Row wrappers inside.

/// A titled card that wraps a column of detail-screen rows. The detail-screen
/// analogue of SettingsGroupCard, but it accepts arbitrary control rows
/// (pickers, toggles) rather than just nav rows.
struct SettingsFormCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if let title {
                Text(title.uppercased())
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.leading, TempoSpacing.sm)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

            if let footnote {
                Text(footnote)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.horizontal, TempoSpacing.sm)
            }
        }
    }
}

/// A hairline divider inset to align under a row's label, for use between
/// rows inside a SettingsFormCard.
struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.tempoDivider)
            .padding(.leading, TempoSpacing.lg)
    }
}

/// Read-only label + value row — the workhorse for surfacing data.
struct SettingsInfoRow: View {
    let label: String
    let value: String
    var icon: String?
    var iconTint: Color = .tempoTextSecondary
    var valueColor: Color = .tempoTextSecondary

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            if let icon {
                SettingsIconTile(systemName: icon, tint: iconTint)
            }
            Text(label)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer(minLength: TempoSpacing.sm)
            Text(value)
                .font(.tempoDataSmall)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
        .frame(minHeight: 44)
    }
}

/// A card row hosting a trailing native control (DatePicker, Picker, Toggle,
/// Stepper). The control is passed in via the `control` builder so callers
/// keep full native behavior; this only provides the labeled card chrome.
struct SettingsControlRow<Control: View>: View {
    let label: String
    var icon: String?
    var iconTint: Color = .tempoTextSecondary
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            if let icon {
                SettingsIconTile(systemName: icon, tint: iconTint)
            }
            Text(label)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer(minLength: TempoSpacing.sm)
            control
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.sm)
        .frame(minHeight: 44)
    }
}
