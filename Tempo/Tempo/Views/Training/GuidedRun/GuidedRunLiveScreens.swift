//
// GuidedRunLiveScreens.swift
// Tempo
//
// Guided run mode — the three live-coach screens: countdown, work (shaped
// by the current step's `GuidedRunWorkKind`), and rest (shows what's next).
// Full screen, dark, big type per docs/DESIGN_SYSTEM.md — design tokens
// only.
//

import SwiftUI

// MARK: - GuidedRunCountdownScreen

struct GuidedRunCountdownScreen: View {
    let secondsRemaining: Int
    let nextStepTitle: String

    @ScaledMetric(relativeTo: .largeTitle)
    private var figure: CGFloat = TideTrainSession.countdownFigure

    var body: some View {
        VStack(spacing: Tide.s5) {
            Spacer()
            Text("Get ready").tideLabel()
            TrainRing(
                progress: 1,
                tint: secondsRemaining > 0 ? nil : TideTrain.positive,
                diameter: TideTrainSession.restRing
            ) {
                Text(secondsRemaining > 0 ? "\(secondsRemaining)" : "GO")
                    .font(Tide.numeral(min(figure, TideTrainSession.restRing * 0.5), .heavy))
                    .foregroundStyle(secondsRemaining > 0 ? Tide.text : TideTrain.positive)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Tide.lively, value: secondsRemaining)
                    .lineLimit(1)
                    .minimumScaleFactor(TideTrainSession.clockShrink)
            }
            Text(nextStepTitle)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tide.edge)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(secondsRemaining > 0 ? "Starting in \(secondsRemaining)" : "Go")
        .accessibilityIdentifier("guidedRunCountdownScreen")
    }
}

// MARK: - GuidedRunWorkScreen

struct GuidedRunWorkScreen: View {
    @Bindable
    var session: GuidedRunSession
    var locationTracker: GuidedRunLocationTracker
    @Binding
    var isMuted: Bool
    var useMiles: Bool = false
    /// Apple Watch run mode — nil hides the badge entirely (no Watch, or the
    /// athlete hasn't set an age/override yet, is still a real max value per
    /// `HeartRateZoneCalculator`, so this is only nil before a session starts).
    var maxHeartRate: Double?
    let onExit: () -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var step: GuidedRunStep? {
        session.steps.indices.contains(session.stepIndex) ? session.steps[session.stepIndex] : nil
    }

    private var workKind: GuidedRunWorkKind? {
        guard case let .work(kind) = step?.kind else {
            return nil
        }
        return kind
    }

    var body: some View {
        VStack(spacing: 0) {
            GuidedRunTopBar(isMuted: $isMuted, onExit: onExit)

            if let step, let workKind {
                ScrollView {
                    VStack(spacing: Tide.s6) {
                        header(step)
                        workBody(workKind)
                    }
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s4)
                    .modifier(GuidedRunCentred(active: !typeSize.isAccessibilitySize))
                }
                .scrollBounceBehavior(.basedOnSize)
                controls(workKind)
            }
        }
    }

    private func header(_ step: GuidedRunStep) -> some View {
        VStack(spacing: Tide.hair) {
            Text("Block \(step.blockIndex + 1)/\(step.blockCount) · \(step.blockName)")
                .tideLabel(Color.accentColor)
            // A tick for every block of the run, filled as each one is done.
            TrainSetTicks(done: step.blockIndex, total: step.blockCount, label: "Blocks")
                .padding(.vertical, Tide.s1)
            Text(step.blockTrainerText)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            GuidedRunHeartRateBadge(bpm: session.currentHeartRateBPM, maxHeartRate: maxHeartRate)
        }
    }

    @ViewBuilder
    private func workBody(_ kind: GuidedRunWorkKind) -> some View {
        switch kind {
        case let .timedRep(rep):
            timedRepBody(index: rep.index, of: rep.of, capSeconds: rep.capSeconds, distanceLabel: rep.distanceLabel)
        case let .round(index, of):
            roundBody(index: index, of: of)
        case let .continuousDuration(targetSeconds):
            continuousBody(targetSeconds: targetSeconds, targetDistanceLabel: nil)
        case let .continuousDistance(targetMeters, targetLabel):
            continuousDistanceBody(targetMeters: targetMeters, targetLabel: targetLabel)
        case let .freeform(text):
            freeformBody(text: text)
        }
    }

    private func timedRepBody(index: Int, of: Int, capSeconds: Double?, distanceLabel: String?) -> some View {
        let elapsed = session.elapsedInCurrentStep
        let overCap = capSeconds.map { elapsed > $0 } ?? false
        return TrainSessionHero(
            label: "Rep \(index + 1)/\(of)",
            value: GuidedRunFormatting.clock(elapsed),
            progress: capSeconds.map { $0 > 0 ? elapsed / $0 : 0 },
            tint: overCap ? Tide.danger : nil,
            valueColor: overCap ? Tide.danger : Tide.text
        ) {
            VStack(spacing: Tide.s1) {
                if let capSeconds {
                    Text("Cap \(GuidedRunFormatting.repTime(capSeconds))")
                        .font(Tide.headline)
                        .foregroundStyle(overCap ? Tide.danger : TideTrain.positive)
                }
                if let distanceLabel {
                    Text(distanceLabel)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
        }
        .animation(Tide.snap, value: overCap)
    }

    private func roundBody(index: Int, of: Int) -> some View {
        TrainSessionHero(
            label: "Round",
            value: "\(index + 1)",
            progress: of > 0 ? Double(index + 1) / Double(of) : nil
        ) {
            Text("of \(of)")
                .font(Tide.headline)
                .foregroundStyle(Tide.text2)
        }
    }

    private func continuousBody(targetSeconds: Double, targetDistanceLabel: String?) -> some View {
        let elapsed = session.elapsedInCurrentStep
        return TrainSessionHero(
            value: GuidedRunFormatting.clock(elapsed),
            progress: targetSeconds > 0 ? elapsed / targetSeconds : nil
        ) {
            VStack(spacing: Tide.s3) {
                if let remaining = session.remainingInCurrentStep {
                    Text("\(GuidedRunFormatting.clock(remaining)) remaining")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text2)
                }
                distanceRow
            }
        }
    }

    private func continuousDistanceBody(targetMeters: Double, targetLabel: String) -> some View {
        TrainSessionHero(
            value: GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles),
            progress: targetMeters > 0 ? locationTracker.distanceMeters / targetMeters : nil
        ) {
            VStack(spacing: Tide.s2) {
                Text("Target \(targetLabel)")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
                Text(GuidedRunFormatting.clock(session.elapsedInCurrentStep))
                    .font(TideTrain.figure(.headline))
                    .foregroundStyle(Tide.text3)
                paceRow
            }
        }
    }

    private func freeformBody(text: String) -> some View {
        TrainSessionHero(value: GuidedRunFormatting.clock(session.elapsedInCurrentStep)) {
            VStack(spacing: Tide.s3) {
                Text(text)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                distanceRow
            }
        }
    }

    @ViewBuilder
    private var distanceRow: some View {
        if locationTracker.isTracking {
            VStack(spacing: Tide.hair) {
                Text(GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles))
                    .font(TideTrain.figure(.headline))
                    .foregroundStyle(Tide.text)
                paceRow
            }
        } else if !locationTracker.isAuthorized {
            Text("Timer only — location not available")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
    }

    @ViewBuilder
    private var paceRow: some View {
        if let pace = GuidedRunFormatting.pace(secondsPerKm: locationTracker.currentPaceSecondsPerKm, useMiles: useMiles) {
            Text(pace)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
    }

    // MARK: - Controls

    private func controls(_ kind: GuidedRunWorkKind) -> some View {
        VStack(spacing: Tide.s2) {
            LazyVGrid(columns: railColumns(kind), spacing: Tide.s2) {
                secondaryButton(title: session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                    session.isPaused ? session.resume() : session.pause()
                }
                secondaryButton(title: "Skip rep", systemImage: "forward.fill", disabled: session.isPaused) {
                    HapticManager.selection()
                    session.skipRep()
                }
                if isRepeatable(kind) {
                    secondaryButton(title: "Add rep", systemImage: "plus", disabled: session.isPaused) {
                        HapticManager.selection()
                        session.addRep()
                    }
                }
                secondaryButton(title: "Skip block", systemImage: "forward.end.fill", disabled: session.isPaused) {
                    HapticManager.selection()
                    session.skipBlock()
                }
            }
            doneButton
        }
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s3)
        .padding(.top, Tide.s2)
    }

    /// One row of rail buttons, two columns at large text sizes.
    private func railColumns(_ kind: GuidedRunWorkKind) -> [GridItem] {
        let count = typeSize.isAccessibilitySize ? 2 : (isRepeatable(kind) ? 4 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: Tide.s2), count: count)
    }

    private func isRepeatable(_ kind: GuidedRunWorkKind) -> Bool {
        switch kind {
        case .timedRep,
             .round: true
        default: false
        }
    }

    private var doneButton: some View {
        Button {
            HapticManager.impact(.heavy)
            session.markDone(liveDistanceMeters: locationTracker.isTracking ? locationTracker.distanceMeters : nil)
        } label: {
            Text("Done")
                .frame(minHeight: TideTrain.bigButton - Tide.s2)
        }
        .buttonStyle(.tidePrimary)
        .disabled(session.isPaused)
        .accessibilityIdentifier("guidedRunDoneButton")
    }

    private func secondaryButton(
        title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Tide.hair) {
                Image(systemName: systemImage)
                    .font(Tide.headline)
                Text(title)
                    .font(Tide.caption)
            }
        }
        .buttonStyle(.trainRail)
        .disabled(disabled)
    }
}

// MARK: - GuidedRunRestScreen

struct GuidedRunRestScreen: View {
    @Bindable
    var session: GuidedRunSession
    @Binding
    var isMuted: Bool
    var maxHeartRate: Double?
    let onExit: () -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var nextStep: GuidedRunStep? {
        let nextIndex = session.stepIndex + 1
        return session.steps.indices.contains(nextIndex) ? session.steps[nextIndex] : nil
    }

    /// The rest the trainer (or Tempo) set for this step, for the ring.
    private var restTotal: Double {
        if session.steps.indices.contains(session.stepIndex), case let .rest(seconds) = session.steps[session.stepIndex].kind {
            return seconds
        }
        return 0
    }

    var body: some View {
        let remaining = session.remainingInCurrentStep ?? 0
        return VStack(spacing: 0) {
            GuidedRunTopBar(isMuted: $isMuted, onExit: onExit)
            ScrollView {
                VStack(spacing: Tide.s5) {
                    TrainSessionHero(
                        label: "Rest",
                        labelTint: TideTrain.caution,
                        value: GuidedRunFormatting.clock(remaining),
                        progress: restTotal > 0 ? remaining / restTotal : nil,
                        tint: TideTrain.caution
                    ) {
                        GuidedRunHeartRateBadge(bpm: session.currentHeartRateBPM, maxHeartRate: maxHeartRate)
                    }

                    if let nextStep, case let .work(kind) = nextStep.kind {
                        VStack(spacing: Tide.hair) {
                            Text("Up next").tideLabel()
                            Text(nextStep.blockName)
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                                .multilineTextAlignment(.center)
                            Text(GuidedRunFormatting.workDescription(kind))
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s4)
                .modifier(GuidedRunCentred(active: !typeSize.isAccessibilitySize))
                .accessibilityIdentifier("guidedRunRestScreen")
            }
            .scrollBounceBehavior(.basedOnSize)

            GlassEffectContainer(spacing: Tide.s2) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Tide.s2))
                    : AnyLayout(HStackLayout(spacing: Tide.s2))
                layout {
                    Button {
                        session.isPaused ? session.resume() : session.pause()
                    } label: {
                        Text(session.isPaused ? "Resume" : "Pause")
                            .frame(minHeight: TideTrain.bigButton - Tide.s2)
                    }
                    .buttonStyle(.tideGlass)

                    Button {
                        HapticManager.selection()
                        session.skipRep()
                    } label: {
                        Text("Skip rest")
                            .frame(minHeight: TideTrain.bigButton - Tide.s2)
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(session.isPaused)
                    .accessibilityIdentifier("guidedRunSkipRestButton")
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s3)
        }
    }
}

// MARK: - GuidedRunHeartRateBadge

/// Apple Watch run mode §2 — live BPM + Z1-Z5 zone on the phone screen,
/// mirroring what the Watch itself shows. Renders nothing without a live
/// reading (no Watch paired/reachable) rather than a placeholder dash — the
/// rest of the guided-run screen already works identically either way.
private struct GuidedRunHeartRateBadge: View {
    let bpm: Double?
    let maxHeartRate: Double?

    var body: some View {
        if let bpm {
            HStack(spacing: Tide.hair) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Tide.danger)
                Text("\(Int(bpm.rounded())) bpm")
                if let maxHeartRate, let zone = HeartRateZoneCalculator.zone(bpm: bpm, maxHeartRate: maxHeartRate) {
                    Text(HeartRateZoneCalculator.zoneLabel(zone))
                        .fontWeight(.bold)
                }
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            .accessibilityIdentifier("guidedRunHeartRateBadge")
            .explains(TrainExplainers.heartRateZone)
        }
    }
}

// MARK: - GuidedRunTopBar

private struct GuidedRunTopBar: View {
    @Binding
    var isMuted: Bool
    let onExit: () -> Void

    var body: some View {
        HStack {
            Button {
                HapticManager.selection()
                onExit()
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
            }
            .accessibilityLabel("End session")
            Spacer()
            Button {
                isMuted.toggle()
                HapticManager.selection()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
            }
            .accessibilityLabel(isMuted ? "Unmute cues" : "Mute cues")
        }
        .padding(.horizontal, Tide.s2)
    }
}

/// Centres the screen's content in the page at normal text sizes. At
/// accessibility sizes the content can be taller than the page, and a frame
/// pinned to the page height would cut off both ends with no way to scroll.
private struct GuidedRunCentred: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.containerRelativeFrame(.vertical, alignment: .center)
        } else {
            content
        }
    }
}
