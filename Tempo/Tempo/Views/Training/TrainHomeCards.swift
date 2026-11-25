//
// TrainHomeCards.swift
// Tempo
//
// The smaller objects on Train home, each its own card with one clear ask or
// one clear fact: the calendar window and its countdown, the monthly debrief,
// the effort rating after a session, a benched day, and the rest-day /
// non-gym-day cards. They take plain values and closures, so
// TodayWorkoutView.swift (already near the file-length cap) only decides when
// to show them.
//

import SwiftUI

// MARK: - TrainWindowCard

/// "Best window today 5:00 – 6:30 PM", with the one action that books it.
struct TrainWindowCard: View {
    let start: Date
    let end: Date
    let onAdd: () -> Void

    var body: some View {
        TrainAskCard(
            label: String(localized: "Best window today"),
            title: "\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))"
        ) {
            TideIconTile(systemName: "calendar.badge.clock", size: TideTrain.askTile)
        } actions: {
            Button(action: onAdd) {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }
            // Quiet: "Start workout" under the thumb is the one filled button here.
            .buttonStyle(.trainBanner(filled: false))
        }
    }
}

// MARK: - TrainCountdownCard

/// The saved workout, counting down: "Gym in 3h 32m — 5:00 PM".
struct TrainCountdownCard: View {
    let title: String

    var body: some View {
        TrainAskCard(label: String(localized: "Next workout"), title: title) {
            TideIconTile(systemName: "figure.run", size: TideTrain.askTile)
        }
    }
}

// MARK: - TrainMonthlyReviewCard

/// The month-boundary ritual, as an invitation with a button instead of a bare row.
struct TrainMonthlyReviewCard: View {
    let onOpen: () -> Void

    var body: some View {
        TrainAskCard(
            label: String(localized: "Monthly debrief"),
            title: String(localized: "Month's over. Debrief."),
            message: String(localized: "5 questions, then your report. 2 minutes.")
        ) {
            TideIconTile(systemName: "checklist.checked", size: TideTrain.askTile)
        } actions: {
            Button(action: onOpen) {
                Text("Start the debrief")
            }
            .buttonStyle(.trainBanner(filled: false))
        }
        // The whole card opens the debrief, as the old row did.
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - TrainBenchedCard

/// A day the recovery floor benched: why, and a deliberate way back in.
struct TrainBenchedCard: View {
    let onTrainAnyway: () -> Void

    var body: some View {
        TrainAskCard(
            label: String(localized: "Benched today"),
            tint: Tide.danger,
            title: String(localized: "Your body called it."),
            message: String(localized: "Today is recovery — walk, stretch, sleep. Doesn't count as a missed day.")
        ) {
            TideIconTile(systemName: "bed.double.fill", tint: Tide.danger, size: TideTrain.askTile)
        } actions: {
            Button(action: onTrainAnyway) {
                Text("Train anyway")
            }
            .buttonStyle(.trainBanner(filled: false))
            .accessibilityHint("Reopens today's workout so you can start it.")
        }
    }
}

// MARK: - TrainRPECard

/// How hard the whole session felt, 1 to 10: ten chips on a green-to-red ramp
/// while unanswered, one quiet row with the number once logged.
struct TrainRPECard: View {
    let logged: Int?
    let onPick: (Int) -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        Group {
            if let logged {
                loggedRow(logged)
            } else {
                ask
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func loggedRow(_ value: Int) -> some View {
        HStack(spacing: Tide.s3) {
            TrainFigureTile(label: String(localized: "RPE"), figure: "\(value)", tint: Self.tint(for: value))
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Session RPE logged: \(value)/10")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Text("Your coach reads it tomorrow.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .explains(TrainExplainers.rpe.showing(String(localized: "\(value) of 10")))
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("How hard was that?").tideLabel()
                Text("Whole session. 1 = nothing, 10 = max effort.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .explains(TrainExplainers.rpe)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s2), count: typeSize.isAccessibilitySize ? 3 : 5),
                spacing: Tide.s2
            ) {
                ForEach(1 ... 10, id: \.self) { value in
                    Button {
                        HapticManager.selection()
                        onPick(value)
                    } label: {
                        Text("\(value)")
                            .font(TideTrain.figure(.headline))
                            .foregroundStyle(Tide.text)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .background(
                                Self.tint(for: value).opacity(TideTrain.chipWash),
                                in: .rect(cornerRadius: Tide.controlRadius, style: .continuous)
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(TrainRPEChipStyle())
                }
            }
        }
    }

    /// Easy to hard: green, neutral, amber, red.
    private static func tint(for value: Int) -> Color {
        switch value {
        case ...3: TideTrain.positive
        case 4 ... 6: Tide.text2
        case 7 ... 8: TideTrain.caution
        default: Tide.danger
        }
    }
}

// MARK: - TrainRPEChipStyle

private struct TrainRPEChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - TrainDayCard

/// A day that is not a lifting session (a rest day, football, a run): one big
/// symbol, what today is, a line about it, what comes tomorrow, then whatever
/// action the day has.
struct TrainDayCard<Actions: View>: View {
    let label: String
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var message: String?
    var tomorrow: String?
    @ViewBuilder var actions: Actions

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let head = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        VStack(alignment: .leading, spacing: Tide.s4) {
            head {
                TideIconTile(systemName: symbol, tint: tint, size: TideTrainSession.stateTile)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(label).tideLabel(tint)
                    Text(title)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tomorrow {
                TrainSessionRule()
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Tomorrow").tideLabel()
                    Text(tomorrow)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5)
    }
}

// MARK: - TrainSkeleton

/// Train home while today's workout is being built: the shape of the day (a
/// hero, then a list of rows) as quiet pulsing blocks, so the page does not
/// jump when the real one arrives.
struct TrainSkeleton: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var dim = false

    var body: some View {
        VStack(spacing: Tide.s4) {
            VStack(alignment: .leading, spacing: Tide.s3) {
                block(width: TideTrain.askTile * 2, height: Tide.s3)
                block(width: TideTrain.askTile * 3, height: Tide.s10)
                block(width: TideTrain.skeletonLong, height: Tide.s3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s5)

            VStack(spacing: 0) {
                ForEach(0 ..< 3, id: \.self) { index in
                    if index > 0 {
                        TrainPlanDivider()
                    }
                    HStack(spacing: Tide.s3) {
                        RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                            .fill(Tide.fill)
                            .frame(width: TideTrain.rowPicture, height: TideTrain.rowPicture)
                        VStack(alignment: .leading, spacing: Tide.s2) {
                            block(width: TideTrain.skeletonMedium, height: Tide.s3)
                            block(width: TideTrain.skeletonShort, height: Tide.s2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Tide.s4)
                }
            }
            .tideCard(padding: 0, radius: Tide.tileRadius)

            Text("Generating your workout...")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
        }
        .opacity(dim ? TideTrain.skeletonDim : 1)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(TideTrain.skeletonPulse) {
                dim = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Generating your workout")
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Tide.fill)
            .frame(width: width, height: height)
    }
}
