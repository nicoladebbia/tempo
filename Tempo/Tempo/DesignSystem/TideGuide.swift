//
// TideGuide.swift
// Tempo
//
// Two small teaching tools every area shares.
//
// `.explains(_:)` makes a score or number tappable: a sheet says what it is,
// how it is worked out and what to do about it.
//
// `.firstTip(_:_:)` shows one sentence the first time a feature is opened,
// and never again.
//

import SwiftUI

// MARK: - Explainer

/// What a number means, in three short answers.
struct Explainer: Identifiable, Equatable {
    /// Stable key, e.g. "day-score". Also the accessibility identifier suffix.
    let id: String
    let title: LocalizedStringResource
    /// What it is.
    let what: LocalizedStringResource
    /// How it is worked out.
    let how: LocalizedStringResource
    /// What to do about it.
    let action: LocalizedStringResource
    /// The value being explained, as shown on screen ("82", "7.4 h"). Optional.
    var value: String?
    var systemImage: String = "questionmark.circle"

    /// The same explainer carrying the value the user just tapped.
    func showing(_ value: String?) -> Explainer {
        var copy = self
        copy.value = value
        return copy
    }
}

// MARK: - ExplainsModifier

private struct ExplainsModifier: ViewModifier {
    let explainer: Explainer
    @State private var shown = false
    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        Button {
            shown = true
        } label: {
            content
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityHint(Text("Explains this number"))
        .accessibilityIdentifier("explain.\(explainer.id)")
        .sheet(isPresented: $shown) {
            ExplainerSheet(explainer: explainer)
                .environment(\.tideMood, mood)
        }
    }
}

extension View {
    /// Tap to open a sheet explaining this score or number. Use on the number
    /// itself (a dial, a stat tile), not on a row that already navigates.
    func explains(_ explainer: Explainer) -> some View {
        modifier(ExplainsModifier(explainer: explainer))
    }

    /// Presents an explainer chosen elsewhere (a row with several numbers, an
    /// info button): set the binding to show the sheet.
    func explainerSheet(_ explainer: Binding<Explainer?>) -> some View {
        sheet(item: explainer) { ExplainerSheet(explainer: $0) }
    }
}

// MARK: - ExplainerSheet

/// The sheet behind `.explains(_:)`.
struct ExplainerSheet: View {
    let explainer: Explainer
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                HStack(alignment: .center, spacing: Tide.s3) {
                    TideIconTile(systemName: explainer.systemImage)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(explainer.title)
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text)
                        if let value = explainer.value {
                            Text(value)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: Tide.s4) {
                    part("What it is", explainer.what)
                    Divider().overlay(Tide.hairline)
                    part("How it's worked out", explainer.how)
                    Divider().overlay(Tide.hairline)
                    part("What to do", explainer.action)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard()
                Button("Got it") { dismiss() }
                    .buttonStyle(.tidePrimary)
                    .accessibilityIdentifier("explain.done")
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s6)
            .padding(.bottom, Tide.s4)
        }
        .tidePage()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func part(_ label: LocalizedStringKey, _ text: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - FirstTips

/// Remembers which first-time tips were already shown.
enum FirstTips {
    private static let prefix = "tip.seen."

    /// Off in UI tests and scripted runs (`-noTips`), so tips never cover a tap target.
    static var disabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-noTips")
    }

    static func seen(_ id: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: prefix + id)
    }

    static func markSeen(_ id: String, in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: prefix + id)
    }

    /// "Show tips again" in Settings.
    static func resetAll(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - FirstTipModifier

private struct FirstTipModifier: ViewModifier {
    let id: String
    let text: LocalizedStringResource
    let systemImage: String
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    tip
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                guard !FirstTips.disabled, !FirstTips.seen(id) else {
                    return
                }
                // Let the page settle first; the tip is the last thing to arrive.
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else {
                    return
                }
                // Seen as soon as it shows: leaving the page must not bring it back.
                FirstTips.markSeen(id)
                withAnimation(Tide.lively) { visible = true }
            }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: systemImage)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(Tide.snap) { visible = false }
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Dismiss tip"))
            .accessibilityIdentifier("tip.dismiss.\(id)")
        }
        .padding(.leading, Tide.s4)
        .padding(.vertical, Tide.s2)
        // A tip is a hint, not the page: at the largest text sizes it would fill half the
        // screen and cover the very button it explains. Cap it at a large normal size
        // (the page itself keeps growing, and the dismiss button stays a full tap target).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .glassEffect(.regular, in: .rect(cornerRadius: Tide.tileRadius, style: .continuous))
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tip.\(id)")
    }
}

extension View {
    /// One sentence on how to use this feature, the first time it is opened.
    /// Put it on the feature's root page. `id` is stable and unique ("train.logger").
    func firstTip(
        _ id: String,
        _ text: LocalizedStringResource,
        systemImage: String = "lightbulb"
    ) -> some View {
        modifier(FirstTipModifier(id: id, text: text, systemImage: systemImage))
    }
}
