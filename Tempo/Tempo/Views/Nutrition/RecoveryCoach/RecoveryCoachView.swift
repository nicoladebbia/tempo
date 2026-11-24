//
// RecoveryCoachView.swift
// Tempo
//
// The Recovery Coach screen: after a big session, what you sweated out and what
// to drink and eat. One START HERE when something is missing; otherwise the
// result. Numbers are ranges with a +/- percent and are labelled as estimates.
// Opened from the weigh-in push and from the card on Nutrition Today.
//

import SwiftUI

// MARK: - RecoveryCoachView

struct RecoveryCoachView: View {
    let model: RecoveryCoachModel
    let onClose: () -> Void

    @Environment(\.tideMood) private var mood
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showWeighIn = false
    @State private var showFluids = false
    @State private var showWhy = false
    @State private var preMatchOn = RecoveryCoachStore.shared.read().preMatchReminderOn

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    if typeSize.isAccessibilitySize, let session = model.session {
                        Text(Self.sessionLine(session, now: Date()))
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isOfflineResult {
                        offlineBanner
                    }
                    content
                    reminderRow
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s8)
                .padding(.top, Tide.s3)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Own task: SwiftUI cancels a refreshable body when the view updates mid-load.
            .refreshable { await Task { await model.refresh(requestedID: model.session?.id) }.value }
        }
        .tidePage()
        .fuelBottomBar(isShown: needsWeighIn && !showWeighIn && !showFluids) {
            enterWeightBar
        }
        .tideCovered(showWeighIn || showFluids)
        .sheet(isPresented: $showWeighIn) {
            if let session = model.session {
                ManualWeighInSheet(session: session, startsWithAfter: model.result?.missingPost ?? true) { kg, time in
                    Task { await model.addManualWeighIn(kg: kg, at: time) }
                }
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showFluids) {
            FluidSheet(model: model)
                .presentationDetents([.large])
        }
        .accessibilityIdentifier("coach.screen")
    }

    /// Something is missing (a weigh-in): the one thing to do is the bar at the bottom.
    private var needsWeighIn: Bool {
        model.session != nil && model.result != nil && model.startHere != nil
    }

    /// The one action while a weigh-in is missing, in the thumb zone.
    private var enterWeightBar: some View {
        Button(model.result?.status == .implausible ? "Enter my new weight" : "Enter my weight") {
            showWeighIn = true
        }
        .buttonStyle(.tidePrimary)
        .accessibilityIdentifier("coach.enterWeight")
    }

    // MARK: Header (never scrolls)

    private var header: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: "drop.fill", tint: Tide.water)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Recovery")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .accessibilityAddTraits(.isHeader)
                // At accessibility sizes the session line moves into the scrolling
                // page, so the pinned header stays one line and leaves room.
                if let session = model.session, !typeSize.isAccessibilitySize {
                    Text(Self.sessionLine(session, now: Date()))
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Tide.s1)
            Spacer(minLength: Tide.s2)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("coach.close")
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s4)
        .padding(.bottom, Tide.s2)
    }

    static func sessionLine(_ s: CoachSession, now: Date) -> String {
        "\(s.label), \(s.durationMinutes) min, ended \(RecoveryCoachModel.ago(s.end, now: now))"
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case let .loading(step) where model.result == nil:
            LoadingSteps(current: step, startedAt: model.loadStartedAt ?? Date())
        case let .failed(message):
            errorCard(message)
        default:
            if model.session == nil {
                emptyCard
            } else if let result = model.result {
                if case let .loading(step) = model.phase {
                    // Old numbers stay visible but dimmed, with the real steps and a clock above them.
                    LoadingSteps(current: step, startedAt: model.loadStartedAt ?? Date(), title: "Updating your numbers")
                    resultContent(result)
                        .opacity(0.4)
                        .allowsHitTesting(false)
                } else {
                    resultContent(result)
                }
            } else {
                LoadingSteps(current: .coach, startedAt: model.loadStartedAt ?? Date())
            }
        }
    }

    private var emptyCard: some View {
        FuelEmptyState(
            icon: "scalemass",
            title: "No session to weigh",
            message: "After a WHOOP workout of 20 minutes or more, I'll ask you to weigh in. Nothing from the last 2 days needs it."
        )
        .accessibilityIdentifier("coach.empty")
    }

    private func errorCard(_ message: String) -> some View {
        FuelEmptyState(icon: "exclamationmark.triangle.fill", title: "Couldn't load your recovery", message: message) {
            Button("Try again") { Task { await model.refresh(requestedID: model.session?.id) } }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("coach.retry")
        }
        .accessibilityIdentifier("coach.error")
    }

    private var offlineBanner: some View {
        FuelBanner(icon: "wifi.slash", tint: Tide.text2, title: offlineText)
            .accessibilityIdentifier("coach.offline")
    }

    private var offlineText: String {
        let when = model.resultDate.map { RecoveryCoachModel.ago($0, now: Date()) } ?? "earlier"
        return "No connection. Showing your last result from \(when)."
    }

    // MARK: Result

    @ViewBuilder
    private func resultContent(_ result: CoachRecoveryResponse) -> some View {
        if let start = model.startHere {
            startHereCard(start, result: result)
            healthReadings
            if let plan = result.plan {
                foodNow(plan)
            }
        } else if let sweat = result.sweat, let plan = result.plan {
            sweatCard(sweat)
            planCard(plan, sweat: sweat)
            fluidRow
            healthReadings
            whyDisclosure(result: result, sweat: sweat, plan: plan)
        } else {
            errorCard("The coach returned no numbers. Pull down to try again.")
        }
    }

    // START HERE

    private func startHereCard(_ start: (title: String, reason: String), result: CoachRecoveryResponse) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Start here").tideLabel(mood.accent)
            Text(start.title)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(start.reason)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            if result.status == .needsWeighIn, result.missingPost {
                Text("Weigh before you drink or eat, after the toilet, in the same clothes (or none), towel-dry.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard()
        .accessibilityIdentifier("coach.startHere")
    }

    /// What Apple Health returned for this session's window, so "why isn't it using my scale?" has an answer.
    private var healthReadings: some View {
        card {
            Text("Weights near the session").tideLabel()
            if let note = model.healthNote {
                Text(note)
                    .font(Tide.body)
                    .foregroundStyle(Tide.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.weighIns.isEmpty {
                Text(
                    "Nothing from Apple Health or entered by hand between 3 hours before and 2.5 hours after the session. Your Withings scale sends a weight to Health after you step on it."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(model.weighIns.enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .center, spacing: Tide.s3) {
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            TideNumber(String(format: "%.1f", w.kg), unit: "kg", size: Tide.numeralS, relativeTo: .headline)
                            Text(
                                "\(w.source == CoachWeighIn.sourceWithings ? "Withings" : "By hand"), \(w.time.formatted(date: .omitted, time: .shortened))"
                            )
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Tide.s2)
                        if w.source == CoachWeighIn.sourceManual {
                            Button("Remove") { Task { await model.removeManualWeighIn(at: w.time) } }
                                .buttonStyle(.plain)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(mood.accent)
                                .frame(minHeight: Tide.hit)
                                .accessibilityIdentifier("coach.removeWeight")
                        }
                    }
                }
            }
            healthActions
        }
        .accessibilityIdentifier("coach.healthReadings")
    }

    private var healthActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return GlassEffectContainer(spacing: Tide.s2) {
            layout {
                Button { Task { await model.recompute() } } label: {
                    Text("Check Health again")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("coach.recheck")
                // While a weigh-in is missing, the bar at the bottom already is this button.
                if model.startHere == nil {
                    Button { showWeighIn = true } label: {
                        Text("Enter a weight")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("coach.enterAnother")
                }
            }
        }
    }

    /// Food does not need a weigh-in, so it is shown even while one is missing.
    private func foodNow(_ plan: CoachRecoveryResponse.Plan) -> some View {
        card {
            Text("Food can start now").tideLabel()
            Text(
                "About \(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h and \(Int(plan.proteinGrams.rounded())) g protein in one go. The fluid and salt numbers appear once both weigh-ins are in."
            )
            .font(Tide.body)
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Ready

    private func sweatCard(_ sweat: CoachRecoveryResponse.Sweat) -> some View {
        let low = sweat.sweatLitersLow ?? sweat.sweatLitersRaw ?? 0
        let high = sweat.sweatLitersHigh ?? sweat.sweatLitersRaw ?? low
        return VStack(alignment: .leading, spacing: Tide.s2) {
            Text("You sweated").tideLabel()
            if sweat.isLowerBound {
                VStack(alignment: .leading, spacing: 0) {
                    Text("At least")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                    TideNumber(RecoveryCoachFormat.liters(low), size: Tide.numeralL)
                }
                Text("I don't know what you drank, so this is a minimum. Tell me below and I'll narrow it.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("About")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                    TideNumber(RecoveryCoachFormat.litersRange(low: low, high: high), size: Tide.numeralL)
                }
                if let margin = sweat.marginOfErrorPercent {
                    Text("\(RecoveryCoachFormat.margin(margin)) (95% range). An estimate, not a measurement.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(
                "You lost \(String(format: "%.1f", sweat.massLostKg)) kg on the scale (\(String(format: "%.1f", sweat.percentBodyMassLost))% of your weight)."
            )
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
            .fixedSize(horizontal: false, vertical: true)
            // The same percentage drawn against a 0 to 5% scale, so "how much" is seen.
            VStack(spacing: Tide.s1) {
                TideLevelBar(
                    progress: min(max(sweat.percentBodyMassLost / 5, 0), 1),
                    color: sweat.percentBodyMassLost >= 5 ? Tide.danger : Tide.water,
                    height: Tide.bar
                )
                HStack {
                    Text("0%")
                    Spacer(minLength: Tide.s2)
                    Text("5% of your weight")
                }
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            }
            .padding(.top, Tide.s1)
            .accessibilityHidden(true)
            if sweat.meetsFivePercentTarget {
                Label("Within 5% (95% range)", systemImage: "checkmark.seal")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.good)
            } else if sweat.protocolQuality == "loose" {
                Text("Your weigh-ins were far from the session, so the range is wider.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.sweat")
    }

    private func planCard(_ plan: CoachRecoveryResponse.Plan, sweat: CoachRecoveryResponse.Sweat) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("Start here").tideLabel(mood.accent)
            if let drink = plan.drinkLiters {
                planLine(
                    icon: "drop.fill", color: Tide.water,
                    title: "Drink \(RecoveryCoachFormat.liters(drink)) with a meal",
                    detail: "Over the next few hours, with food that has salt. Water alone leaves you short."
                )
            }
            if let sodium = plan.sodiumMgPlan, let low = plan.sodiumMgLow, let high = plan.sodiumMgHigh {
                planLine(
                    icon: "circle.hexagongrid.fill", color: Tide.plan,
                    title: "Sodium about \(RecoveryCoachFormat.sodium(sodium))",
                    detail: "Could be \(RecoveryCoachFormat.sodiumRange(low: low, high: high)): sweat saltiness varies a lot between people."
                )
            }
            planLine(
                icon: "bolt.fill", color: Tide.carbs,
                title: "\(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h",
                detail: nil
            )
            planLine(
                icon: "figure.strengthtraining.traditional", color: Tide.protein,
                title: "\(Int(plan.proteinGrams.rounded())) g protein in one go",
                detail: nil
            )
        }
        .tideCard()
        .accessibilityIdentifier("coach.plan")
    }

    private func planLine(icon: String, color: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: icon, tint: color, size: Tide.hit - Tide.s2)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var fluidRow: some View {
        Button { showFluids = true } label: {
            // The value sits beside the words; under them at accessibility sizes.
            fluidRowLayout {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("What you drank")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                    Text(fluidSummary)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
                HStack(spacing: Tide.s2) {
                    if let liters = model.fluids.liters {
                        TideNumber(RecoveryCoachFormat.fluid(liters), size: Tide.numeralS, relativeTo: .headline, color: Tide.water)
                    } else {
                        Text("Unknown")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.water)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Image(systemName: "chevron.right")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Tide.hit)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(FuelPressStyle())
        .accessibilityIdentifier("coach.fluids")
    }

    /// The value sits beside the words; under them at accessibility sizes.
    private var fluidRowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
    }

    private var fluidSummary: String {
        let f = model.fluids
        if let edited = f.editedLiters {
            return "You entered \(RecoveryCoachFormat.fluid(edited))."
        }
        var parts: [String] = []
        if f.loggedMl > 0 {
            parts.append("\(RecoveryCoachFormat.fluid(Double(f.loggedMl) / 1000)) logged in Tempo")
        }
        if let a = f.quickAnswerLiters {
            parts.append("\(RecoveryCoachFormat.fluid(a)) you answered")
        }
        return parts.isEmpty ? "Not known yet. Tap to tell me." : parts.joined(separator: " + ")
    }

    private func whyDisclosure(
        result: CoachRecoveryResponse, sweat: CoachRecoveryResponse.Sweat, plan: CoachRecoveryResponse.Plan
    ) -> some View {
        DisclosureGroup(isExpanded: $showWhy) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                bulletList("Why", plan.reasons)
                bulletList("What I assumed", sweat.assumptions + result.notes)
                bulletList("Evidence", plan.evidence)
            }
            .padding(.top, Tide.s3)
        } label: {
            Text("Why these numbers")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
        }
        .tint(Tide.text2)
        .tideCard()
        .animation(Tide.snap, value: showWhy)
        .accessibilityIdentifier("coach.why")
    }

    @ViewBuilder
    private func bulletList(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text(title).tideLabel()
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // Reminder toggle (quiet)

    private var reminderRow: some View {
        Toggle(isOn: $preMatchOn) {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Remind me before football")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Text("A weigh-in nudge 1 hour before a scheduled session.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(mood.accent)
        .frame(minHeight: Tide.hit)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .onChange(of: preMatchOn) { _, on in
            RecoveryCoachStore.shared.update { $0.preMatchReminderOn = on }
            NotificationCenter.default.post(name: .tempoCoachSettingsChanged, object: nil)
        }
        .sensoryFeedback(.selection, trigger: preMatchOn)
        .accessibilityIdentifier("coach.preMatchToggle")
    }

    // MARK: Shared card

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3, content: content)
            .tideCard()
    }
}

extension Notification.Name {
    /// The pre-match reminder toggle changed: the scheduler rebuilds.
    static let tempoCoachSettingsChanged = Notification.Name("tempoCoachSettingsChanged")
}

// MARK: - LoadingSteps

private struct LoadingSteps: View {
    let current: RecoveryCoachModel.Step
    let startedAt: Date
    var title = "Working on it"

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).tideLabel()
                Spacer(minLength: Tide.s2)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    TideNumber(
                        RecoveryCoachFormat.clock(max(0, Int(context.date.timeIntervalSince(startedAt)))),
                        size: Tide.numeralS, relativeTo: .headline, color: Tide.text2
                    )
                }
            }
            ForEach(RecoveryCoachModel.Step.allCases, id: \.rawValue) { step in
                HStack(spacing: Tide.s3) {
                    Group {
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tide.good)
                        } else if step == current {
                            ProgressView().tint(Tide.text)
                        } else {
                            Image(systemName: "circle").foregroundStyle(Tide.text3)
                        }
                    }
                    .frame(width: Tide.icon, alignment: .leading)
                    .accessibilityHidden(true)
                    Text(step.title)
                        .font(Tide.body)
                        .foregroundStyle(step.rawValue <= current.rawValue ? Tide.text : Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .tideCard()
        .accessibilityIdentifier("coach.loading")
    }
}
