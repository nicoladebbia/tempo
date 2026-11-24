//
// MilestoneCelebrationView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// A streak milestone: a burst of rings and sparks (the `tideBurst` shader)
// opens from behind the icon, the day count rises under it, and the way out is
// pinned at the bottom. Reduce Motion shows the finished frame.

struct MilestoneCelebrationView: View {
    let milestone: MilestoneService.Milestone
    let onDismiss: () -> Void
    let onShowProgress: (() -> Void)?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var showContent = false
    @State
    private var showIcon = false

    var body: some View {
        // The scroll view only matters at the largest text sizes on a small
        // phone; otherwise the content fills the page and the spacers centre it.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, Tide.edge)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        // The same burst every moment in the app opens with (Tide+Arena kit).
        .background { ArenaBurst(accent: mood.accent).ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            buttons
        }
        .tidePage(energy: 1)
        .sensoryFeedback(.success, trigger: showIcon)
        .onAppear {
            if reduceMotion {
                showIcon = true
                showContent = true
            } else {
                withAnimation(Tide.lively.delay(0.2)) {
                    showIcon = true
                }
                withAnimation(Tide.settle.delay(0.5)) {
                    showContent = true
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: Tide.s6) {
            Spacer()

            // Animated icon
            Image(systemName: milestone.icon)
                .font(Tide.numeral(Tide.numeralL + Tide.s3, .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.dialSheet + Tide.s2, height: Tide.dialSheet + Tide.s2)
                .glassEffect(.regular.tint(Tide.glassCard), in: .circle)
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1.0 : 0)
                .accessibilityHidden(true)

            // Day count
            VStack(spacing: Tide.s2) {
                Text("DAY \(milestone.rawValue)")
                    .font(Tide.numeral(Tide.numeralHero, .heavy))
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .accessibilityAddTraits(.isHeader)

                Text(milestone.title)
                    .font(Tide.headline)
                    .tracking(Tide.hair)
                    .foregroundStyle(mood.accent)
            }
            .opacity(showContent ? 1.0 : 0)
            .offset(y: showContent || reduceMotion ? 0 : Tide.s5)

            // Message
            Text(milestone.message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tide.s4)
                .opacity(showContent ? 1.0 : 0)
                .offset(y: showContent || reduceMotion ? 0 : Tide.s5)

            Spacer()
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: Tide.s2) {
            if milestone == .day30, let onShowProgress {
                Button("VIEW PROGRESS REPORT") {
                    MilestoneService.markShown(milestone)
                    onShowProgress()
                }
                .buttonStyle(.tidePrimary)
            }

            if milestone == .day30 {
                Button {
                    MilestoneService.markShown(milestone)
                    onDismiss()
                } label: {
                    Text("DISMISS")
                        .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s2)
                }
                .buttonStyle(.tideGlass)
            } else {
                Button("LET'S GO") {
                    MilestoneService.markShown(milestone)
                    onDismiss()
                }
                .buttonStyle(.tidePrimary)
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s2)
        .opacity(showContent ? 1.0 : 0)
    }
}
