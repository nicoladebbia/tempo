//
// ValueDemoView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - ValueDemoView

// The hook: a sample day score that lights up, and the four things Tempo
// tracks as live tiles. Everything on this page is sample data and says so.

struct ValueDemoView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var filled = false

    private struct Sample: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        var unit: String?
        let color: Color
        let progress: Double
        let detail: String
    }

    private let samples: [Sample] = [
        Sample(
            id: "recovery", icon: "heart.fill", title: String(localized: "RECOVERY"), value: "72", unit: "%",
            color: Tide.protein, progress: 0.72, detail: String(localized: "HRV 58 ms \u{00B7} Sleep \(7.2.tempoDecimal(1)) h")
        ),
        Sample(
            id: "training", icon: "dumbbell.fill", title: String(localized: "TRAINING"), value: String(localized: "Push Day"),
            color: Tide.fat, progress: 0.4, detail: String(localized: "2 of 5 lifts done")
        ),
        Sample(
            id: "nutrition", icon: "leaf.fill", title: String(localized: "NUTRITION"), value: 1840.formatted(), unit: "kcal",
            color: Color.tempoSuccess, progress: 0.75, detail: String(localized: "of \(2450.formatted()) kcal today")
        ),
        Sample(
            id: "accountability", icon: "lock.fill", title: String(localized: "NON-NEGOTIABLES"), value: "3/5", unit: String(localized: "done"),
            color: Tide.carbs, progress: 0.6, detail: String(localized: "Train \u{00B7} Study \u{00B7} Meals")
        ),
    ]

    var body: some View {
        OnboardingScaffold(
            title: String(localized: "THIS IS TEMPO"),
            subtitle: String(localized: "Your entire life \u{2014} training, nutrition, recovery, accountability \u{2014} in one app."),
            primaryTitle: String(localized: "SET UP MY TEMPO"),
            primaryAction: onContinue,
            skipTitle: String(localized: "Skip tour"),
            skipAction: onContinue,
            centered: true
        ) {
            hero

            VStack(spacing: Tide.s3) {
                GlassEffectContainer(spacing: Tide.s3) {
                    tiles
                }
                OnboardingNote(String(localized: "Sample data. Yours fills in as you use Tempo."), systemImage: "info.circle")
            }
        }
        .onAppear {
            if reduceMotion {
                filled = true
            } else {
                withAnimation(Tide.settle.delay(0.35)) { filled = true }
            }
        }
    }

    // MARK: - Tiles

    /// Two by two, or one column when the text is too big for half a screen.
    @ViewBuilder
    private var tiles: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Tide.s3) {
                ForEach(samples) { sampleTile($0) }
            }
        } else {
            Grid(horizontalSpacing: Tide.s3, verticalSpacing: Tide.s3) {
                GridRow {
                    sampleTile(samples[0])
                    sampleTile(samples[1])
                }
                GridRow {
                    sampleTile(samples[2])
                    sampleTile(samples[3])
                }
            }
        }
    }

    // MARK: - Hero

    /// A sample day score beside the pitch: what you get, and why it is one app.
    private var hero: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s4))
            : AnyLayout(HStackLayout(spacing: Tide.s5))
        return layout {
            // The dial keeps its size and its text stays inside the ring.
            TideDial(score: 72, caption: String(localized: "Sample"), diameter: Tide.dialSheet + Tide.s6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            VStack(alignment: typeSize.isAccessibilitySize ? .center : .leading, spacing: Tide.s1) {
                Text("One app. Not five.")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text("Replaces your workout tracker, meal planner, sleep app, habit tracker, and study timer.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sample Tile

    private func sampleTile(_ sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(spacing: Tide.s2) {
                Image(systemName: sample.icon)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(sample.color)
                    .accessibilityHidden(true)
                Text(sample.title)
                    .tideLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }

            TideNumber(
                sample.value, unit: sample.unit, size: Tide.numeralS + Tide.s2,
                relativeTo: .title2, color: sample.color
            )

            TideLevelBar(progress: filled ? sample.progress : 0, color: sample.color, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .accessibilityHidden(true)

            Text(sample.detail)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ValueDemoView(onContinue: {})
        .tidePage(energy: 1)
}
