//
// WizardStepScaffold.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

// MARK: - WizardStepScaffold

struct WizardStepScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    /// The line above the title ("Step 2 of 4").
    let eyebrow: String?
    let progress: Double
    let canGoBack: Bool
    let primaryButtonLabel: String
    let primaryButtonEnabled: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void
    let onCancel: () -> Void
    @ViewBuilder
    let content: () -> Content

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    init(
        title: String,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        progress: Double,
        canGoBack: Bool,
        primaryButtonLabel: String = String(localized: "Next"),
        primaryButtonEnabled: Bool = true,
        onBack: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.progress = progress
        self.canGoBack = canGoBack
        self.primaryButtonLabel = primaryButtonLabel
        self.primaryButtonEnabled = primaryButtonEnabled
        self.onBack = onBack
        self.onPrimary = onPrimary
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s6) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        if let eyebrow {
                            Text(eyebrow)
                                .tideLabel(mood.accent)
                                .contentTransition(.numericText())
                        }
                        Text(title)
                            .font(Tide.title)
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
                    content()
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s4)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .fuelBottomBar { footer }
        }
        .tidePage()
    }

    private var header: some View {
        VStack(spacing: Tide.s2) {
            HStack {
                Button {
                    HapticManager.selection()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(minWidth: Tide.hit, minHeight: Tide.hit, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
                // At large text the title would crowd Cancel; the eyebrow below says where you are.
                if !typeSize.isAccessibilitySize {
                    Text("Plan intake")
                        .tideLabel()
                    Spacer()
                    Color.clear.frame(width: Tide.hit, height: Tide.hair)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s1)

            TideLevelBar(progress: progress, height: Tide.barSlim)
                .animation(Tide.settle, value: progress)
                .padding(.horizontal, Tide.edge)
        }
        .padding(.bottom, Tide.s2)
    }

    private var footer: some View {
        HStack(spacing: Tide.s3) {
            if canGoBack {
                Button {
                    HapticManager.selection()
                    onBack()
                } label: {
                    // At accessibility sizes Back shrinks to an arrow so the main
                    // button keeps room and its label never breaks mid-word.
                    Group {
                        if typeSize.isAccessibilitySize {
                            Image(systemName: "chevron.left")
                                .font(Tide.bodyStrong)
                                .frame(width: Tide.hit + Tide.s2)
                        } else {
                            Text(String(localized: "nav.back", defaultValue: "Back", comment: "Back button in a step-by-step flow (not the muscle group)"))
                                .font(Tide.bodyStrong)
                                .padding(.horizontal, Tide.s5)
                        }
                    }
                    .foregroundStyle(Tide.text)
                    .frame(minHeight: Tide.hit + Tide.s2)
                    .background(Tide.fill, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(FuelPressStyle())
                .accessibilityLabel(String(localized: "nav.back", defaultValue: "Back", comment: "Back button in a step-by-step flow (not the muscle group)"))
            }

            Button {
                HapticManager.lightImpact()
                onPrimary()
            } label: {
                Text(primaryButtonLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidePrimary)
            .disabled(!primaryButtonEnabled)
        }
    }
}

// MARK: - Step caption

extension WizardCoordinator {
    /// "Step 2 of 4", for the line above each step's title.
    var stepCaption: String {
        guard let index = visibleSteps.firstIndex(of: currentStep) else {
            return ""
        }
        return String(localized: "Step \(index + 1) of \(visibleSteps.count)")
    }
}
