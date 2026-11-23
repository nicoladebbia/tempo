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
    @State
    private var start = Date()

    /// Seconds the burst plays before it holds its last, nearly empty, frame.
    private let burstSeconds = 4.5

    var body: some View {
        VStack(spacing: Tide.s6) {
            Spacer()

            // Animated icon
            Image(systemName: milestone.icon)
                .font(Tide.numeral(56, .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(mood.accent)
                .frame(width: 128, height: 128)
                .glassEffect(.regular.tint(Tide.glassCard), in: .circle)
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1.0 : 0)
                .accessibilityHidden(true)

            // Day count
            VStack(spacing: Tide.s2) {
                Text("DAY \(milestone.rawValue)")
                    .font(Tide.numeral(72, .heavy))
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .accessibilityAddTraits(.isHeader)

                Text(milestone.title)
                    .font(Tide.headline)
                    .tracking(2)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Tide.edge)
        .background { burst }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            buttons
        }
        .tidePage(energy: 1)
        .sensoryFeedback(.success, trigger: showIcon)
        .onAppear {
            start = Date()
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

    // MARK: - Burst

    private var burst: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? burstSeconds : min(context.date.timeIntervalSince(start), burstSeconds)
            Rectangle()
                .fill(.white)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.tideBurst(
                        .float2(proxy.size), .float(t), .color(mood.accent), .color(Tide.carbs)
                    ))
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
