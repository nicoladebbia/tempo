//
// MilestoneCelebrationView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftUI

struct MilestoneCelebrationView: View {
    let milestone: MilestoneService.Milestone
    let onDismiss: () -> Void
    let onShowProgress: (() -> Void)?

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

                    Button(action: {
                        MilestoneService.markShown(milestone)
                        onDismiss()
                    }) {
                        Text(milestone == .day30 ? "DISMISS" : "LET'S GO")
                            .font(.tempoHeadline)
                            .foregroundStyle(
                                milestone == .day30 ? Color.tempoTextSecondary : Color.tempoBgPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TempoSpacing.buttonPaddingV)
                            .background(
                                milestone == .day30 ? Color.tempoSurfaceCard : Color.tempoSignal
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
