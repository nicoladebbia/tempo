//
// RecoveryCoachSection.swift
// Tempo
//
// The "after your session" part of the one Fuel coach: what you sweated out and
// what to drink and eat. One START HERE when something is missing; otherwise the
// result. Numbers are ranges with a +/- percent and are labelled as estimates.
// Shown on top of the Coach page whenever a recent session needs a weigh-in or
// has a result; opened from the weigh-in push and from the card on Fuel Today.
//

import SwiftUI

// MARK: - RecoveryCoachSection

struct RecoveryCoachSection: View {
    let model: RecoveryCoachModel
    @Binding
    var showWeighIn: Bool
    @Binding
    var showFluids: Bool
    /// A hand-entered weight was removed: the page offers Undo.
    var onRemoveWeighIn: (CoachWeighIn) -> Void = { _ in }

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var showWhy = false

    /// Something is missing (a weigh-in): the one thing to do is the bar at the bottom.
    static func needsWeighIn(_ model: RecoveryCoachModel) -> Bool {
        model.session != nil && model.result != nil && model.startHere != nil
    }

    var body: some View {
        // Always-present container; the section inside is conditional.
        VStack(alignment: .leading, spacing: Tide.s4) {
            if let session = model.session {
                sessionHeader(session)
                if model.isOfflineResult {
                    offlineBanner
                }
                content
            }
        }
        .animation(Tide.snap, value: model.session?.id)
    }

    // MARK: Header

    private func sessionHeader(_ session: CoachSession) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            TideSectionLabel(title: String(localized: "After your session"))
            Text(Self.sessionLine(session, now: Date()))
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("coach.sessionHeader")
    }

    static func sessionLine(_ s: CoachSession, now: Date) -> String {
        String(localized: "\(s.label), \(s.durationMinutes) min, ended \(RecoveryCoachModel.ago(s.end, now: now))")
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
            if let result = model.result {
                if case let .loading(step) = model.phase {
                    // Old numbers stay visible but dimmed, with the real steps and a clock above them.
                    LoadingSteps(current: step, startedAt: model.loadStartedAt ?? Date(), title: String(localized: "Updating your numbers"))
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

    private func errorCard(_ message: String) -> some View {
        FuelEmptyState(icon: "exclamationmark.triangle.fill", title: String(localized: "Couldn't load your recovery"), message: message) {
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
        let when = model.resultDate.map { RecoveryCoachModel.ago($0, now: Date()) } ?? String(localized: "earlier", comment: "As in: showing your last result from earlier")
        return String(localized: "No connection. Showing your last result from \(when).")
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
            errorCard(String(localized: "The coach returned no numbers. Pull down to try again."))
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
                    String(localized: "Nothing from Apple Health or entered by hand between 3 hours before and 2.5 hours after the session. Your Withings scale sends a weight to Health after you step on it.")
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(model.weighIns.enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .center, spacing: Tide.s3) {
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            TideNumber(w.kg.tempoDecimal(1), unit: "kg", size: Tide.numeralS, relativeTo: .headline)
                            let weighTime = w.time.formatted(date: .omitted, time: .shortened)
                            Text(
                                w.source == CoachWeighIn.sourceWithings
                                    ? String(localized: "Withings, \(weighTime)")
                                    : String(localized: "By hand, \(weighTime)")
                            )
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Tide.s2)
                        if w.source == CoachWeighIn.sourceManual {
                            Button("Remove") { onRemoveWeighIn(w) }
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
                String(localized: "About \(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h and \(Int(plan.proteinGrams.rounded())) g protein in one go. The fluid and salt numbers appear once both weigh-ins are in.")
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
                .explains(.fuelSweatLoss.showing(RecoveryCoachFormat.liters(low)))
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
                .explains(.fuelSweatLoss.showing(RecoveryCoachFormat.litersRange(low: low, high: high)))
                if let margin = sweat.marginOfErrorPercent {
                    Text("\(RecoveryCoachFormat.margin(margin)) (95% range). An estimate, not a measurement.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .explains(.fuelSweatMargin)
                }
            }
            Text(
                String(localized: "You lost \(sweat.massLostKg.tempoDecimal(1)) kg on the scale (\(sweat.percentBodyMassLost.tempoDecimal(1))% of your weight).")
            )
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
            .fixedSize(horizontal: false, vertical: true)
            .explains(.fuelWeightLost)
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
                    .explains(.fuelSweatMargin)
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
                    title: String(localized: "Drink \(RecoveryCoachFormat.liters(drink)) with a meal"),
                    detail: String(localized: "Over the next few hours, with food that has salt. Water alone leaves you short.")
                )
            }
            if let sodium = plan.sodiumMgPlan, let low = plan.sodiumMgLow, let high = plan.sodiumMgHigh {
                planLine(
                    icon: "circle.hexagongrid.fill", color: Tide.plan,
                    title: String(localized: "Sodium about \(RecoveryCoachFormat.sodium(sodium))"),
                    detail: String(localized: "Could be \(RecoveryCoachFormat.sodiumRange(low: low, high: high)): sweat saltiness varies a lot between people.")
                )
            }
            planLine(
                icon: "bolt.fill", color: Tide.carbs,
                title: String(localized: "\(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h"),
                detail: nil
            )
            planLine(
                icon: "figure.strengthtraining.traditional", color: Tide.protein,
                title: String(localized: "\(Int(plan.proteinGrams.rounded())) g protein in one go"),
                detail: nil
            )
        }
        .tideCard()
        .explains(.fuelRecoveryPlan)
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
            return String(localized: "You entered \(RecoveryCoachFormat.fluid(edited)).")
        }
        var parts: [String] = []
        if f.loggedMl > 0 {
            parts.append(String(localized: "\(RecoveryCoachFormat.fluid(Double(f.loggedMl) / 1000)) logged in Tempo"))
        }
        if let a = f.quickAnswerLiters {
            parts.append(String(localized: "\(RecoveryCoachFormat.fluid(a)) you answered"))
        }
        return parts.isEmpty ? String(localized: "Not known yet. Tap to tell me.") : parts.joined(separator: " + ")
    }

    private func whyDisclosure(
        result: CoachRecoveryResponse, sweat: CoachRecoveryResponse.Sweat, plan: CoachRecoveryResponse.Plan
    ) -> some View {
        DisclosureGroup(isExpanded: $showWhy) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                bulletList(String(localized: "Why"), plan.reasons)
                bulletList(String(localized: "What I assumed"), sweat.assumptions + result.notes)
                bulletList(String(localized: "Evidence"), plan.evidence)
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

    // MARK: Shared card

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3, content: content)
            .tideCard()
    }
}

// MARK: - CoachEnterWeightBar

/// The one action while a weigh-in is missing, in the thumb zone.
struct CoachEnterWeightBar: View {
    let model: RecoveryCoachModel
    let action: () -> Void

    var body: some View {
        Button(model.result?.status == .implausible ? String(localized: "Enter my new weight") : String(localized: "Enter my weight"), action: action)
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("coach.enterWeight")
    }
}

// MARK: - CoachReminderRow

/// "Remind me before football": the pre-match weigh-in nudge (quiet toggle).
struct CoachReminderRow: View {
    @Environment(\.tideMood)
    private var mood
    @State
    private var preMatchOn = RecoveryCoachStore.shared.read().preMatchReminderOn

    var body: some View {
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
}

extension Notification.Name {
    /// The pre-match reminder toggle changed: the scheduler rebuilds.
    static let tempoCoachSettingsChanged = Notification.Name("tempoCoachSettingsChanged")
}

// MARK: - LoadingSteps

private struct LoadingSteps: View {
    let current: RecoveryCoachModel.Step
    let startedAt: Date
    var title = String(localized: "Working on it")

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
