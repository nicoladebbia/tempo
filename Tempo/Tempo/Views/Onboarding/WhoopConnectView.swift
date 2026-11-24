//
// WhoopConnectView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Whoop Connect View

// Per WIREFRAMES.md Screen 47 — Whoop connection during onboarding. OPTIONAL.
// Per STATE_MACHINES.md Section 10 — Connected or Skip.
//
// The step shows what a connection gives you: a recovery ring that lights up,
// the sleep and strain bars under it, and the one line that says the workout
// follows.

struct WhoopConnectView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var isConnecting = false
    @State
    private var errorMessage: String?
    @State
    private var filled = false

    private let recovery = 0.72
    @ScaledMetric(relativeTo: .title)
    private var ringSize: CGFloat = Tide.dialSheet - Tide.s4

    var body: some View {
        OnboardingScaffold(
            title: "YOUR BODY TALKS.\nLET'S LISTEN.",
            primaryTitle: isConnecting ? "CONNECTING..." : "CONNECT WHOOP",
            primaryEnabled: !isConnecting,
            primaryAction: {
                Task {
                    isConnecting = true
                    errorMessage = nil
                    do {
                        try await services.whoop.connect()
                        viewModel.whoopConnected = true
                        viewModel.advance()
                    } catch {
                        errorMessage = "Connection failed. You can try again or skip."
                        isConnecting = false
                    }
                }
            },
            skipAction: { viewModel.skip() },
            errorMessage: errorMessage,
            centered: true
        ) {
            OnboardingPreviewFrame(title: "Recovery scores + HRV") {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Tide.s4))
                    : AnyLayout(HStackLayout(spacing: Tide.s5))
                layout {
                    ring
                    VStack(alignment: .leading, spacing: Tide.s4) {
                        bar(icon: "moon.fill", title: "Sleep analysis", value: "7.2", unit: "h", progress: 0.9)
                        bar(icon: "flame.fill", title: "Strain tracking", value: "11.4", unit: nil, progress: 0.55)
                    }
                }

                Divider().overlay(Tide.hairline)

                HStack(spacing: Tide.s3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.good)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: Tide.icon)
                        .accessibilityHidden(true)
                    Text("Auto-adjusted workouts")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    Text("Full session")
                        .tideLabel(Tide.good)
                        .lineLimit(1)
                        .padding(.horizontal, Tide.s2)
                        .padding(.vertical, Tide.s1)
                        .background(Tide.good.opacity(0.16), in: .capsule)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .task {
            if reduceMotion {
                filled = true
            } else {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(Tide.settle) { filled = true }
            }
        }
    }

    /// Recovery as a lit ring with HRV under the figure.
    private var ring: some View {
        ZStack {
            TideRing(progress: filled ? recovery : 0, color: Tide.good, lineWidth: Tide.s2)
            VStack(spacing: Tide.hair) {
                TideNumber(filled ? "72" : "00", unit: "%", size: Tide.numeralM, relativeTo: .title)
                Text("HRV 58 ms")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .padding(.horizontal, Tide.s4)
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recovery 72 percent, HRV 58 milliseconds")
    }

    private func bar(icon: String, title: String, value: String, unit: String?, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: icon)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.good)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
                TideNumber(value, unit: unit, size: Tide.numeralS, relativeTo: .headline)
            }
            TideLevelBar(progress: filled ? progress : 0, color: Tide.good, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    WhoopConnectView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
