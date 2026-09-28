//
// GuidedRunWatchView.swift
// Tempo
//
// Guided run mode — Apple Watch run mode. Mirrors whatever the phone's
// GuidedRunSession is doing (`connectivity.latestGuidedRun`), runs a real
// HKWorkoutSession for live heart rate, and relays a big "Done" tap / pause
// back to the phone — which stays the sole source of truth (§22 pattern: the
// watch never advances its own copy of the plan, it just asks the phone to).
//

import SwiftUI

// MARK: - GuidedRunWatchView

struct GuidedRunWatchView: View {
    let connectivity: WatchConnectivityService
    @State
    private var heartRateService = WatchGuidedRunHeartRateService()
    /// Local now/tick so the count-up/down timer redraws without waiting on
    /// the next phone push — same date-anchored math as the phone/widget.
    @State
    private var now = Date()

    private var snapshot: GuidedRunActivitySnapshot? {
        connectivity.latestGuidedRun
    }

    var body: some View {
        Group {
            if let snapshot {
                liveContent(snapshot)
            } else {
                emptyContent
            }
        }
        .onChange(of: snapshot != nil) { _, isActive in
            if isActive {
                startHeartRateServiceIfNeeded()
            } else {
                heartRateService.stop()
            }
        }
        .onAppear {
            if snapshot != nil {
                startHeartRateServiceIfNeeded()
            }
        }
        .onDisappear { heartRateService.stop() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Text("NO GUIDED RUN")
                .font(.system(size: 14, weight: .bold))
            Text("Start a guided run on your iPhone — it mirrors here automatically.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }

    private func liveContent(_ snapshot: GuidedRunActivitySnapshot) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(snapshot.isRest ? "REST" : "GUIDED RUN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(snapshot.stepTitle)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(timerText(snapshot))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timerColor(snapshot))

                if let next = snapshot.nextStepText {
                    Text(next)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let detail = snapshot.detailText {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let distance = snapshot.distanceText {
                    HStack(spacing: 6) {
                        Text(distance)
                        if let pace = snapshot.paceText {
                            Text(pace)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                heartRateRow(snapshot)

                if !snapshot.isRest {
                    doneButton
                }
                pauseButton(snapshot)
            }
            .padding(.horizontal, 4)
        }
    }

    private func heartRateRow(_ snapshot: GuidedRunActivitySnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            if let bpm = heartRateService.currentBPM {
                Text("\(Int(bpm.rounded())) bpm")
            } else if let text = snapshot.heartRateText {
                Text(text)
            } else {
                Text("—")
            }
            if let zone = snapshot.heartRateZone {
                Text(HeartRateZoneCalculator.zoneLabel(zone))
                    .fontWeight(.bold)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private var doneButton: some View {
        Button {
            connectivity.sendAction(.guidedRunMarkDone) { ack in
                switch ack {
                case .confirmed: WatchHapticService.playSetComplete()
                case .queued: WatchHapticService.playQueued()
                case .failed: WatchHapticService.playError()
                }
            }
        } label: {
            Text("✓  DONE")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func pauseButton(_ snapshot: GuidedRunActivitySnapshot) -> some View {
        Button {
            connectivity.sendAction(snapshot.isPaused ? .guidedRunResume : .guidedRunPause) { ack in
                switch ack {
                case .confirmed: WatchHapticService.playFocusTimerEnd()
                case .queued: WatchHapticService.playQueued()
                case .failed: WatchHapticService.playError()
                }
            }
        } label: {
            Text(snapshot.isPaused ? "RESUME" : "PAUSE")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func timerText(_ snapshot: GuidedRunActivitySnapshot) -> String {
        if snapshot.isPaused {
            return snapshot.frozenText ?? "--:--"
        }
        let seconds = snapshot.countsDown
            ? snapshot.timerAnchor.timeIntervalSince(now)
            : now.timeIntervalSince(snapshot.timerAnchor)
        return GuidedRunWatchFormatting.clock(seconds)
    }

    private func timerColor(_ snapshot: GuidedRunActivitySnapshot) -> Color {
        snapshot.isRest ? .yellow : .white
    }

    /// Screenshot/manual-QA aid — `GuidedRunWatchSeed` mirrors a sample run
    /// with no real phone session behind it, so requesting real HealthKit
    /// authorization there would just block the screen on a system prompt
    /// with nothing real to measure. Real guided runs (no seed argument)
    /// always start it.
    private func startHeartRateServiceIfNeeded() {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-guided-run-sample") {
                return
            }
        #endif
        heartRateService.start()
    }
}

// MARK: - GuidedRunWatchFormatting

/// Local stand-in for `GuidedRunFormatting.clock` — the app-target formatter
/// isn't shared with TempoWatch (it lives alongside SwiftUI view code that
/// pulls in the rest of the Training module), so this tiny mirror avoids
/// widening the shared-file surface for one string helper.
private enum GuidedRunWatchFormatting {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
