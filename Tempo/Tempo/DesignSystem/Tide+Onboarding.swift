//
// Tide+Onboarding.swift
// Tempo
//
// The pieces every onboarding step is built from: a scaffold with a big title,
// scrolling content and one primary capsule pinned to the bottom; selectable
// rows and chips; a large symbol tile for the permission steps.
//

import SwiftUI

// MARK: - OnboardingScaffold

/// One onboarding step: a large title (and an optional line under it), the
/// content scrolling beneath, and the primary action pinned at the bottom with
/// an optional quiet skip under it. The page field is drawn by the container.
struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var primaryTitle: String?
    var primaryEnabled = true
    var primaryAction: (() -> Void)?
    var skipTitle = "SKIP"
    var skipAction: (() -> Void)?
    /// Centre the title and content on the page (a hero step) instead of
    /// starting at the top.
    var centered = false
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var appeared = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: centered ? .center : .leading, spacing: Tide.s6) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, Tide.edge)
            .padding(.top, centered ? Tide.s6 : Tide.s4)
            .padding(.bottom, Tide.s6)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : Tide.s3)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(Tide.lively) { appeared = true }
            }
        }
    }

    private var header: some View {
        VStack(alignment: centered ? .center : .leading, spacing: Tide.s2) {
            Text(title)
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if primaryAction != nil || skipAction != nil {
            VStack(spacing: Tide.s1) {
                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.tidePrimary)
                        .disabled(!primaryEnabled)
                }
                if let skipAction {
                    Button(action: skipAction) {
                        Text(skipTitle)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s6)
            .padding(.bottom, Tide.s2)
            .background {
                // Lets scrolling content fade out under the button instead of
                // running into it.
                LinearGradient(
                    stops: [
                        .init(color: Tide.ink.opacity(0), location: 0),
                        .init(color: Tide.ink.opacity(0.94), location: 0.42),
                        .init(color: Tide.ink.opacity(0.97), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - OnboardingOptionRow

/// A selectable row: glass, with the accent ring and a check when chosen.
struct OnboardingOptionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Tide.headline)
                        .foregroundStyle(isSelected ? mood.accent : Tide.text2)
                        .frame(width: Tide.icon)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(isSelected ? Tide.text : Tide.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.headline)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s3, alignment: .leading)
            .glassEffect(
                .regular.tint(isSelected ? mood.accent.opacity(0.22) : Tide.glassControl),
                in: .rect(cornerRadius: Tide.tileRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(isSelected ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - OnboardingChip

/// A selectable pill ("Social Media"): accent fill with ink text when on.
struct OnboardingChip: View {
    let title: String
    let isSelected: Bool
    /// Share the row evenly with its siblings (a day number, YES / NO) instead
    /// of hugging the title.
    var expands = false
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(isSelected ? Tide.ink : Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(maxWidth: expands ? .infinity : nil)
                .padding(.horizontal, expands ? Tide.s1 : Tide.s4)
                .frame(minHeight: Tide.hit)
                .background(isSelected ? mood.accent : Tide.fill, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.clear : Tide.hairline, lineWidth: 1)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - OnboardingSectionLabel

/// The small tracked label over a group of fields or options.
struct OnboardingSectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        TideSectionLabel(title: text, trailing: trailing)
    }
}

// MARK: - OnboardingNote

/// A quiet footnote under a control.
struct OnboardingNote: View {
    let text: String
    var systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - OnboardingHeroTile

/// The large symbol on a permission or celebration step.
struct OnboardingHeroTile: View {
    let systemName: String
    var tint: Color?

    var body: some View {
        TideIconTile(systemName: systemName, tint: tint, size: Tide.tileLarge + Tide.s6)
    }
}

// MARK: - OnboardingBenefitRow

/// An icon and one line, for the "what you get" lists.
struct OnboardingBenefitRow: View {
    let systemImage: String
    let text: String
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.headline)
                .foregroundStyle(tint ?? mood.accent)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Tide.icon + Tide.s2)
        .accessibilityElement(children: .combine)
    }
}
