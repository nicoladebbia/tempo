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
        VStack(spacing: TempoSpacing.xl) {
            Spacer()
            Text("GET READY")
                .font(.tempoOrdersLabel)
                .tracking(TempoTracking.ordersLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(secondsRemaining > 0 ? "\(secondsRemaining)" : "GO")
                .font(.system(size: 140, weight: .heavy, design: .rounded))
                .foregroundStyle(secondsRemaining > 0 ? Color.tempoTextPrimary : Color.tempoSignal)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: secondsRemaining)
            Text(nextStepTitle)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
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
                    VStack(spacing: TempoSpacing.xxl) {
                        header(step)
                        Spacer(minLength: TempoSpacing.xl)
                        workBody(workKind)
                        Spacer(minLength: TempoSpacing.xl)
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.lg)
                    .frame(minHeight: 480)
                }
                controls(workKind)
            }
        }
    }

    private func header(_ step: GuidedRunStep) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text("BLOCK \(step.blockIndex + 1)/\(step.blockCount) · \(step.blockName.uppercased())")
                .font(.tempoOrdersLabel)
                .tracking(TempoTracking.ordersLabel)
                .foregroundStyle(Color.tempoSignal)
            Text(step.blockTrainerText)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
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
        return VStack(spacing: TempoSpacing.md) {
            Text("REP \(index + 1)/\(of)")
                .font(.tempoDrillLabel)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(GuidedRunFormatting.clock(elapsed))
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(overCap ? Color.tempoError : Color.tempoTextPrimary)
                .animation(.easeOut(duration: 0.15), value: overCap)
            if let capSeconds {
                Text("Cap \(GuidedRunFormatting.repTime(capSeconds))")
                    .font(.tempoHeadline)
                    .foregroundStyle(overCap ? Color.tempoError : Color.tempoRecoveryGreen)
            }
            if let distanceLabel {
                Text(distanceLabel)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func roundBody(index: Int, of: Int) -> some View {
        VStack(spacing: TempoSpacing.md) {
            Text("ROUND")
                .font(.tempoDrillLabel)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            Text("\(index + 1)")
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            Text("of \(of)")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private func continuousBody(targetSeconds: Double, targetDistanceLabel: String?) -> some View {
        let elapsed = session.elapsedInCurrentStep
        return VStack(spacing: TempoSpacing.md) {
            Text(GuidedRunFormatting.clock(elapsed))
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            if let remaining = session.remainingInCurrentStep {
                Text("\(GuidedRunFormatting.clock(remaining)) remaining")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            distanceRow
        }
    }

    private func continuousDistanceBody(targetMeters: Double, targetLabel: String) -> some View {
        VStack(spacing: TempoSpacing.md) {
            Text(GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Target \(targetLabel)")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextSecondary)
            Text(GuidedRunFormatting.clock(session.elapsedInCurrentStep))
                .font(.tempoDataMedium)
                .foregroundStyle(Color.tempoTextTertiary)
            paceRow
        }
    }

    private func freeformBody(text: String) -> some View {
        VStack(spacing: TempoSpacing.md) {
            Text(GuidedRunFormatting.clock(session.elapsedInCurrentStep))
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            distanceRow
        }
    }

    @ViewBuilder
    private var distanceRow: some View {
        if locationTracker.isTracking {
            VStack(spacing: TempoSpacing.xxs) {
                Text(GuidedRunFormatting.distance(meters: locationTracker.distanceMeters, useMiles: useMiles))
                    .font(.tempoDataMedium)
                    .foregroundStyle(Color.tempoTextPrimary)
                paceRow
            }
        } else if !locationTracker.isAuthorized {
            Text("Timer only — location not available")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    @ViewBuilder
    private var paceRow: some View {
        if let pace = GuidedRunFormatting.pace(secondsPerKm: locationTracker.currentPaceSecondsPerKm, useMiles: useMiles) {
            Text(pace)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Controls

    private func controls(_ kind: GuidedRunWorkKind) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
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
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.xl)
        .padding(.top, TempoSpacing.sm)
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
                .font(.tempoHeadline)
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
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.tempoHeadline)
                Text(title)
                    .font(.tempoCaption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.tempoTextSecondary)
        }
        .buttonStyle(TempoSecondaryButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - GuidedRunRestScreen

struct GuidedRunRestScreen: View {
    @Bindable
    var session: GuidedRunSession
    @Binding
    var isMuted: Bool
    let onExit: () -> Void

    private var nextStep: GuidedRunStep? {
        let nextIndex = session.stepIndex + 1
        return session.steps.indices.contains(nextIndex) ? session.steps[nextIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            GuidedRunTopBar(isMuted: $isMuted, onExit: onExit)
            Spacer()
            VStack(spacing: TempoSpacing.lg) {
                Text("REST")
                    .font(.tempoOrdersLabel)
                    .tracking(TempoTracking.ordersLabel)
                    .foregroundStyle(Color.tempoAmber)
                Text(GuidedRunFormatting.clock(session.remainingInCurrentStep ?? 0))
                    .font(.system(size: 110, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextPrimary)

                if let nextStep, case let .work(kind) = nextStep.kind {
                    VStack(spacing: TempoSpacing.xxs) {
                        Text("UP NEXT")
                            .font(.tempoDrillLabel)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(nextStep.blockName)
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(GuidedRunFormatting.workDescription(kind))
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .padding(.top, TempoSpacing.xl)
                }
            }
            .accessibilityIdentifier("guidedRunRestScreen")
            Spacer()

            HStack(spacing: TempoSpacing.sm) {
                Button {
                    session.isPaused ? session.resume() : session.pause()
                } label: {
                    Text(session.isPaused ? "Resume" : "Pause")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TempoSecondaryButtonStyle())

                Button {
                    HapticManager.selection()
                    session.skipRep()
                } label: {
                    Text("Skip rest")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(session.isPaused)
                .accessibilityIdentifier("guidedRunSkipRestButton")
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.xl)
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
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End session")
            Spacer()
            Button {
                isMuted.toggle()
                HapticManager.selection()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isMuted ? "Unmute cues" : "Mute cues")
        }
        .padding(.horizontal, TempoSpacing.sm)
    }
}
