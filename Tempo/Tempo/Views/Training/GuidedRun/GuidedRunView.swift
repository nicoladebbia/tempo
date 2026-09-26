//
// GuidedRunView.swift
// Tempo
//
// Guided run mode — the live coach: full screen, dark, big type. Pre-start
// (edit Tempo's own default rests, then "Start"), a 3-2-1 countdown, a work
// screen shaped by the current step (timed rep / round / continuous
// duration / continuous distance / freeform), a rest screen showing what's
// next, and a summary once the session ends (GuidedRunSummaryView).
//
// Keeps the screen awake for the whole session and requests location only
// when a continuous step actually starts (GuidedRunLocationTracker).
//

import SwiftData
import SwiftUI

struct GuidedRunView: View {
    let day: ProgramDay
    let workoutPlanID: UUID
    let programSessionKey: String
    let heading: String
    var viewModel: TrainingViewModel

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query
    private var userSettings: [UserSettings]

    @State
    private var plan: GuidedRunPlan
    @State
    private var restOverrides: [UUID: Double] = [:]
    @State
    private var session: GuidedRunSession?
    @State
    private var cueService = GuidedRunCueService()
    @State
    private var locationTracker = GuidedRunLocationTracker()
    @State
    private var isMuted = false
    private let clock: GuidedRunClock

    init(
        day: ProgramDay,
        workoutPlanID: UUID,
        programSessionKey: String,
        heading: String,
        viewModel: TrainingViewModel
    ) {
        self.day = day
        self.workoutPlanID = workoutPlanID
        self.programSessionKey = programSessionKey
        self.heading = heading
        self.viewModel = viewModel
        let clock = Self.clockForLaunch()
        self.clock = clock
        _plan = State(initialValue: GuidedRunPlanBuilder.build(day: day))
    }

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            if let session, session.phase == .finished || session.phase == .endedEarly {
                GuidedRunSummaryView(
                    plan: plan,
                    results: session.results,
                    workoutPlanID: workoutPlanID,
                    programSessionKey: programSessionKey,
                    viewModel: viewModel,
                    onDone: { dismiss() },
                    onDiscard: { dismiss() }
                )
            } else if let session, session.phase != .idle {
                liveContent(session)
            } else {
                preStartContent
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            locationTracker.stop()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            session?.tick()
            syncLocationTracking()
        }
        .onChange(of: isMuted) { _, muted in cueService.isMuted = muted }
    }

    private static func clockForLaunch() -> GuidedRunClock {
        let args = ProcessInfo.processInfo.arguments
        if let arg = args.first(where: { $0.hasPrefix("--uitesting-time-scale=") }),
           let raw = arg.split(separator: "=").last,
           let scale = Double(raw)
        {
            return ScaledSystemClock(scale: scale)
        }
        return SystemClock()
    }

    // MARK: - Pre-start

    private var preStartContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    HapticManager.selection()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .padding(.horizontal, TempoSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Text("GUIDED RUN")
                            .font(.tempoDrillLabel)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoSignal)
                        Text(heading)
                            .font(.tempoLargeTitle)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }

                    VStack(alignment: .leading, spacing: TempoSpacing.md) {
                        ForEach(plan.blocks) { block in
                            preStartBlockRow(block)
                        }
                    }

                    if plan.isEmpty {
                        Text("Nothing to guide here — log this one manually.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .padding(TempoSpacing.screenEdge)
            }

            startButton
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.xl)
        }
    }

    private func preStartBlockRow(_ block: GuidedRunBlock) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(block.name.uppercased())
                .font(.tempoOrdersLabel)
                .tracking(TempoTracking.ordersLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(block.trainerText)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if block.restIsDefault {
                Stepper(
                    "Rest between: \(Int(effectiveRest(block)))s",
                    value: Binding(
                        get: { restOverrides[block.id] ?? block.restSeconds },
                        set: { restOverrides[block.id] = $0 }
                    ),
                    in: 10 ... 300,
                    step: 5
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Text("Rest: \(Int(block.restSeconds))s (trainer's)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private func effectiveRest(_ block: GuidedRunBlock) -> Double {
        restOverrides[block.id] ?? block.restSeconds
    }

    private var startButton: some View {
        Button {
            HapticManager.impact(.heavy)
            let builtPlan = GuidedRunPlanBuilder.build(day: day, restOverrides: restOverrides)
            plan = builtPlan
            let newSession = GuidedRunSession(plan: builtPlan, clock: clock)
            newSession.cueHandler = { [cueService] cue in cueService.handle(cue) }
            session = newSession
            newSession.start()
        } label: {
            Text(plan.isEmpty ? "Nothing to run" : "Start guided run")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(TempoPrimaryButtonStyle())
        .disabled(plan.isEmpty)
        .accessibilityIdentifier("guidedRunStartSessionButton")
    }

    // MARK: - Live content dispatch

    @ViewBuilder
    private func liveContent(_ session: GuidedRunSession) -> some View {
        switch session.phase {
        case .idle,
             .finished,
             .endedEarly:
            EmptyView()
        case let .countdown(remaining):
            GuidedRunCountdownScreen(secondsRemaining: remaining, nextStepTitle: currentStepTitle(session))
        case .work:
            GuidedRunWorkScreen(
                session: session,
                locationTracker: locationTracker,
                isMuted: $isMuted,
                useMiles: useMiles,
                onExit: { confirmEndEarly(session) }
            )
        case .rest:
            GuidedRunRestScreen(
                session: session,
                isMuted: $isMuted,
                onExit: { confirmEndEarly(session) }
            )
        }
    }

    /// The user's own unit settings say so (`UserSettings.weightUnit` is
    /// the closest existing signal — kg/lb tracks metric/imperial) with a
    /// locale fallback for a fresh install with no settings row yet.
    private var useMiles: Bool {
        if let unit = userSettings.first?.weightUnit {
            return unit == .lbs
        }
        return Locale.current.measurementSystem != .metric
    }

    private func currentStepTitle(_ session: GuidedRunSession) -> String {
        session.steps.first?.blockName ?? heading
    }

    private func confirmEndEarly(_ session: GuidedRunSession) {
        session.endEarly()
    }

    // MARK: - Location tracking

    /// Starts/stops GPS as the athlete enters/leaves a continuous
    /// duration/distance step, and feeds live distance back into the
    /// engine (for the halfway cue and the eventual logged value).
    private func syncLocationTracking() {
        guard let session, case let .work(index) = session.phase, session.steps.indices.contains(index) else {
            if locationTracker.isTracking {
                locationTracker.stop()
            }
            return
        }
        guard case let .work(kind) = session.steps[index].kind else {
            return
        }
        switch kind {
        case .continuousDuration,
             .continuousDistance:
            if !locationTracker.isTracking {
                locationTracker.start()
            }
            session.updateLiveDistance(locationTracker.distanceMeters)
        default:
            if locationTracker.isTracking {
                locationTracker.stop()
            }
        }
    }
}
