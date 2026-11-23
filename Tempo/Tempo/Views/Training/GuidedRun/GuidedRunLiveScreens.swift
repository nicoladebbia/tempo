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

    var body: some View {
        VStack(spacing: Tide.s5) {
            Spacer()
            Text("Get ready").tideLabel()
            Text(secondsRemaining > 0 ? "\(secondsRemaining)" : "GO")
                .trainNumeral(140, weight: .heavy)
                .foregroundStyle(secondsRemaining > 0 ? Tide.text : Color.accentColor)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(Tide.lively, value: secondsRemaining)
            Text(nextStepTitle)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
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
                        Spacer(minLength: Tide.s5)
                        workBody(workKind)
                        Spacer(minLength: Tide.s5)
                    }
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s4)
                    .frame(minHeight: 480)
                }
                controls(workKind)
            }
        }
    }

    private func header(_ step: GuidedRunStep) -> some View {
        VStack(spacing: Tide.hair) {
            Text("Block \(step.blockIndex + 1)/\(step.blockCount) · \(step.blockName)")
                .tideLabel(Color.accentColor)
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
        return VStack(spacing: Tide.s3) {
            Text("Rep \(index + 1)/\(of)").tideLabel()
            Text(GuidedRunFormatting.clock(elapsed))
                .trainNumeral(96, weight: .bold)
                .foregroundStyle(overCap ? Tide.danger : Tide.text)
                .animation(Tide.snap, value: overCap)
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

    private func roundBody(index: Int, of: Int) -> some View {
        VStack(spacing: Tide.s3) {
            Text("Round")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
            Text("\(index + 1)")
                .trainNumeral(120, weight: .heavy)
                .foregroundStyle(Tide.text)
            Text("of \(of)")
                .font(Tide.headline)
                .foregroundStyle(Tide.text2)
        }
    }

    private func continuousBody(targetSeconds: Double, targetDistanceLabel: String?) -> some View {
        let elapsed = session.elapsedInCurrentStep
        return VStack(spacing: Tide.s3) {
            Text(GuidedRunFormatting.clock(elapsed))
                .trainNumeral(88, weight: .bold)
                .foregroundStyle(Tide.text)
            if let remaining = session.remainingInCurrentStep {
                Text("\(GuidedRunFormatting.clock(remaining)) remaining")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
            }
            distanceRow
        }
    }

    private func continuousDistanceBody(targetMeters: Double, targetLabel: String) -> some View {
        VStack(spacing: Tide.s3) {
            Text(GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles))
                .trainNumeral(72, weight: .bold)
                .foregroundStyle(Tide.text)
            Text("Target \(targetLabel)")
                .font(Tide.headline)
                .foregroundStyle(Tide.text2)
            Text(GuidedRunFormatting.clock(session.elapsedInCurrentStep))
                .font(TideTrain.figure(.headline))
                .foregroundStyle(Tide.text3)
            paceRow
        }
    }

    private func freeformBody(text: String) -> some View {
        VStack(spacing: Tide.s3) {
            Text(GuidedRunFormatting.clock(session.elapsedInCurrentStep))
                .trainNumeral(88, weight: .bold)
                .foregroundStyle(Tide.text)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            distanceRow
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
            HStack(spacing: Tide.s2) {
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
        .padding(.bottom, Tide.s5)
        .padding(.top, Tide.s2)
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
                .font(Tide.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
        .buttonStyle(TempoPrimaryButtonStyle())
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

    private var nextStep: GuidedRunStep? {
        let nextIndex = session.stepIndex + 1
        return session.steps.indices.contains(nextIndex) ? session.steps[nextIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            GuidedRunTopBar(isMuted: $isMuted, onExit: onExit)
            Spacer()
            VStack(spacing: Tide.s4) {
                Text("Rest").tideLabel(TideTrain.caution)
                Text(GuidedRunFormatting.clock(session.remainingInCurrentStep ?? 0))
                    .trainNumeral(110, weight: .heavy)
                    .foregroundStyle(Tide.text)
                GuidedRunHeartRateBadge(bpm: session.currentHeartRateBPM, maxHeartRate: maxHeartRate)

                if let nextStep, case let .work(kind) = nextStep.kind {
                    VStack(spacing: Tide.hair) {
                        Text("Up next").tideLabel()
                        Text(nextStep.blockName)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                        Text(GuidedRunFormatting.workDescription(kind))
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                    }
                    .padding(.top, Tide.s5)
                }
            }
            .accessibilityIdentifier("guidedRunRestScreen")
            Spacer()

            HStack(spacing: Tide.s2) {
                Button {
                    session.isPaused ? session.resume() : session.pause()
                } label: {
                    Text(session.isPaused ? "Resume" : "Pause")
                        .font(Tide.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TempoSecondaryButtonStyle())

                Button {
                    HapticManager.selection()
                    session.skipRep()
                } label: {
                    Text("Skip rest")
                        .font(Tide.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(session.isPaused)
                .accessibilityIdentifier("guidedRunSkipRestButton")
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s5)
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
                    .frame(width: 44, height: 44)
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
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isMuted ? "Unmute cues" : "Mute cues")
        }
        .padding(.horizontal, Tide.s2)
    }
}
