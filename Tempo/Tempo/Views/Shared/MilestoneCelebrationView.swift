//
// MilestoneCelebrationView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

struct MilestoneCelebrationView: View {
    let milestone: MilestoneService.Milestone
    let onDismiss: () -> Void
    let onShowProgress: (() -> Void)?
    /// Day-7/14/21: "LET'S GO" routes to the Streak Calendar so the popup leads somewhere
    /// instead of being a hollow dismiss. Day-30 keeps its progress-report route.
    /// See .plans/overnight-tempo-fixes-2026-05-26.md Phase 2.
    let onShowStreak: (() -> Void)?

    init(
        milestone: MilestoneService.Milestone,
        onDismiss: @escaping () -> Void,
        onShowProgress: (() -> Void)? = nil,
        onShowStreak: (() -> Void)? = nil
    ) {
        self.milestone = milestone
        self.onDismiss = onDismiss
        self.onShowProgress = onShowProgress
        self.onShowStreak = onShowStreak
    }

    @State
    private var showContent = false
    @State
    private var showIcon = false

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            VStack(spacing: TempoSpacing.xl) {
                Spacer()

                // Animated icon
                Image(systemName: milestone.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.tempoSignal)
                    .scaleEffect(showIcon ? 1.0 : 0.3)
                    .opacity(showIcon ? 1.0 : 0)

                // Day count
                VStack(spacing: TempoSpacing.sm) {
                    Text("DAY \(milestone.rawValue)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(milestone.title)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoSignal)
                        .tracking(2)
                }
                .opacity(showContent ? 1.0 : 0)
                .offset(y: showContent ? 0 : 20)

                // Message
                Text(milestone.message)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
                    .opacity(showContent ? 1.0 : 0)
                    .offset(y: showContent ? 0 : 20)

                Spacer()

                // Buttons
                VStack(spacing: TempoSpacing.sm) {
                    if milestone == .day30, let onShowProgress {
                        Button(action: {
                            MilestoneService.markShown(milestone)
                            onShowProgress()
                        }) {
                            Text("VIEW PROGRESS REPORT")
                                .font(.tempoHeadline)
                                .foregroundStyle(Color.tempoBgPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, TempoSpacing.buttonPaddingV)
                                .background(Color.tempoSignal)
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl))
                        }
                    }

                    // Day-7/14/21: primary action routes to Streak Calendar (the popup now
                    // leads somewhere instead of just dismissing). Day-30 keeps DISMISS as
                    // the secondary button after VIEW PROGRESS REPORT.
                    if milestone != .day30, let onShowStreak {
                        Button(action: {
                            MilestoneService.markShown(milestone)
                            onShowStreak()
                        }) {
                            Text("VIEW STREAK")
                                .font(.tempoHeadline)
                                .foregroundStyle(Color.tempoBgPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, TempoSpacing.buttonPaddingV)
                                .background(Color.tempoSignal)
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl))
                        }
                    }

                    Button(action: {
                        MilestoneService.markShown(milestone)
                        onDismiss()
                    }) {
                        // Secondary dismiss styling whenever a primary CTA exists above.
                        let hasPrimaryAbove = (milestone == .day30) || (onShowStreak != nil)
                        Text(milestone == .day30 ? "DISMISS" : (onShowStreak != nil ? "LATER" : "LET'S GO"))
                            .font(.tempoHeadline)
                            .foregroundStyle(
                                hasPrimaryAbove ? Color.tempoTextSecondary : Color.tempoBgPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TempoSpacing.buttonPaddingV)
                            .background(
                                hasPrimaryAbove ? Color.tempoSurfaceCard : Color.tempoSignal
                            )
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl))
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe)
                .opacity(showContent ? 1.0 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                showIcon = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                showContent = true
            }
        }
    }
}
