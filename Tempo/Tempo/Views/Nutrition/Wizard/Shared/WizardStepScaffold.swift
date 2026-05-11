//
// WizardStepScaffold.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct WizardStepScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let progress: Double
    let canGoBack: Bool
    let primaryButtonLabel: String
    let primaryButtonEnabled: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void
    let onCancel: () -> Void
    @ViewBuilder
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        progress: Double,
        canGoBack: Bool,
        primaryButtonLabel: String = "Next",
        primaryButtonEnabled: Bool = true,
        onBack: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
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
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        Text(title)
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                    content()
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.xxl)
            }
            footer
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack {
                Button {
                    HapticManager.selection()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Text("PLAN INTAKE")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.md)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.tempoDivider)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.tempoViolet)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(TempoAnimation.springMedium, value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
        .padding(.bottom, TempoSpacing.sm)
    }

    private var footer: some View {
        HStack(spacing: TempoSpacing.md) {
            if canGoBack {
                Button {
                    HapticManager.selection()
                    onBack()
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tempoTextPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
            }

            Button {
                HapticManager.lightImpact()
                onPrimary()
            } label: {
                Text(primaryButtonLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.tempoTextInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(primaryButtonEnabled ? Color.tempoSignal : Color.tempoSignal.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .disabled(!primaryButtonEnabled)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.sm)
        .padding(.bottom, TempoSpacing.bottomSafe)
        .background(Color.tempoBgPrimary)
    }
}
