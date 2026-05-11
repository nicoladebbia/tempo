//
// WelcomeBannerView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - Welcome Banner View

// First-run dashboard experience — guided setup flow for new users.
// Cards disappear individually as each step is completed.
// Entire banner hides once all steps are done.

struct WelcomeBannerView: View {
    // Completion states — passed from parent
    let isWhoopConnected: Bool
    let hasTrainingSetup: Bool
    let hasNonNegotiables: Bool

    var onConnectWhoop: () -> Void
    var onSetUpTraining: () -> Void
    var onDefineNonNegotiables: () -> Void
    var onSkip: () -> Void

    private var remainingSteps: Int {
        var count = 0
        if !isWhoopConnected {
            count += 1
        }
        if !hasTrainingSetup {
            count += 1
        }
        if !hasNonNegotiables {
            count += 1
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            // MARK: - Welcome Header

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Welcome to Tempo")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(remainingSteps == 1
                    ? "One more step to go."
                    : "Let's set up your life OS.")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // MARK: - Setup Cards (only show incomplete ones)

            VStack(spacing: TempoSpacing.sm) {
                if !isWhoopConnected {
                    setupActionCard(
                        icon: "waveform.path.ecg",
                        iconColor: Color.tempoRecoveryGreen,
                        title: "Connect Whoop",
                        subtitle: "Unlock recovery, sleep, and strain data",
                        action: onConnectWhoop
                    )
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                if !hasTrainingSetup {
                    setupActionCard(
                        icon: "dumbbell.fill",
                        iconColor: Color.tempoAmber,
                        title: "Set Up Training",
                        subtitle: "Choose your split and training days",
                        action: onSetUpTraining
                    )
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                if !hasNonNegotiables {
                    setupActionCard(
                        icon: "lock.fill",
                        iconColor: Color.tempoSignal,
                        title: "Define Non-Negotiables",
                        subtitle: "Daily commitments you won't break",
                        action: onDefineNonNegotiables
                    )
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                // Completed items get a checkmark
                ForEach(completedItems, id: \.title) { item in
                    completedCard(icon: item.icon, title: item.title)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isWhoopConnected)
            .animation(.easeInOut(duration: 0.3), value: hasTrainingSetup)
            .animation(.easeInOut(duration: 0.3), value: hasNonNegotiables)

            // MARK: - Skip Button

            Button {
                onSkip()
            } label: {
                Text("Skip for now")
                    .font(.tempoFootnote)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Completed Items

    private struct CompletedItem: Hashable {
        let icon: String
        let title: String
    }

    private var completedItems: [CompletedItem] {
        var items: [CompletedItem] = []
        if isWhoopConnected {
            items.append(CompletedItem(icon: "waveform.path.ecg", title: "Whoop Connected"))
        }
        if hasTrainingSetup {
            items.append(CompletedItem(icon: "dumbbell.fill", title: "Training Set Up"))
        }
        if hasNonNegotiables {
            items.append(CompletedItem(icon: "lock.fill", title: "Non-Negotiables Defined"))
        }
        return items
    }

    private func completedCard(icon: String, title: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.tempoSuccess)
                .frame(width: 36, height: 36)

            Text(title)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoSuccess)
                .strikethrough()

            Spacer()
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSuccess.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Setup Action Card

    private func setupActionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(title)
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(subtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.tempoCaption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.md)
            .background(Color.tempoBgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
