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

struct RecoveryCoachView: View {
    let model: RecoveryCoachModel
    let onClose: () -> Void

    @State private var showWeighIn = false
    @State private var showFluids = false
    @State private var showWhy = false
    @State private var preMatchOn = RecoveryCoachStore.shared.read().preMatchReminderOn

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    if model.isOfflineResult { offlineBanner }
                    content
                    reminderRow
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe)
                .padding(.top, TempoSpacing.md)
            }
            // Own task: SwiftUI cancels a refreshable body when the view updates mid-load.
            .refreshable { await Task { await model.refresh(requestedID: model.session?.id) }.value }
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
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

    // MARK: Header (never scrolls)

    private var header: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: "drop.fill")
                .font(.tempoHeadline)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(Color.tempoElectric)
                .frame(width: 36, height: 36)
                .background(Color.tempoElectric.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text("RECOVERY")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                if let session = model.session {
                    Text(Self.sessionLine(session, now: Date()))
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: TempoSpacing.sm)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.tempoSubheadline.weight(.semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.tempoSurfaceElevated)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("coach.close")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.lg)
        .padding(.bottom, TempoSpacing.sm)
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
                    LoadingSteps(current: step, startedAt: model.loadStartedAt ?? Date(), title: "UPDATING YOUR NUMBERS")
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
        card {
            Text("No session to weigh")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("After a WHOOP workout of 20 minutes or more, I'll ask you to weigh in. Nothing from the last 2 days needs it.")
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .accessibilityIdentifier("coach.empty")
    }

    private func errorCard(_ message: String) -> some View {
        card {
            Text("Couldn't load your recovery")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(message)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
            Button("Try again") { Task { await model.refresh(requestedID: model.session?.id) } }
                .buttonStyle(.tempoSecondary)
                .accessibilityIdentifier("coach.retry")
        }
        .accessibilityIdentifier("coach.error")
    }

    private var offlineBanner: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "wifi.slash")
            Text(offlineText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.tempoCaption1)
        .foregroundStyle(Color.tempoTextSecondary)
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
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
            if let plan = result.plan { foodNow(plan) }
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("START HERE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoSignal)
            Text(start.title)
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(start.reason)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(result.status == .implausible ? "Enter my new weight" : "Enter my weight") {
                showWeighIn = true
            }
            .buttonStyle(.tempoPrimary)
            .accessibilityIdentifier("coach.enterWeight")
            if result.status == .needsWeighIn, result.missingPost {
                Text("Weigh before you drink or eat, after the toilet, in the same clothes (or none), towel-dry.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityIdentifier("coach.startHere")
    }

    /// What Apple Health returned for this session's window, so "why isn't it using my scale?" has an answer.
    private var healthReadings: some View {
        card {
            Text("WEIGHTS NEAR THE SESSION")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            if let note = model.healthNote {
                Text(note).font(.tempoSubheadline).foregroundStyle(Color.tempoWarning)
            }
            if model.weighIns.isEmpty {
                Text("Nothing from Apple Health or entered by hand between 3 hours before and 2.5 hours after the session. Your Withings scale sends a weight to Health after you step on it.")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(model.weighIns.enumerated()), id: \.offset) { _, w in
                    HStack(spacing: TempoSpacing.sm) {
                        Text(String(format: "%.1f kg", w.kg)).font(.tempoDataSmall)
                        Spacer()
                        Text("\(w.source == CoachWeighIn.sourceWithings ? "Withings" : "By hand"), \(w.time.formatted(date: .omitted, time: .shortened))")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        if w.source == CoachWeighIn.sourceManual {
                            Button("Remove") { Task { await model.removeManualWeighIn(at: w.time) } }
                                .font(.tempoCaption1.weight(.semibold))
                                .foregroundStyle(Color.tempoSignal)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("coach.removeWeight")
                        }
                    }
                }
            }
            HStack {
                Button("Check Health again") { Task { await model.recompute() } }
                    .buttonStyle(.tempoGhost)
                    .accessibilityIdentifier("coach.recheck")
                Button("Enter a weight") { showWeighIn = true }
                    .buttonStyle(.tempoGhost)
                    .accessibilityIdentifier("coach.enterAnother")
            }
        }
        .accessibilityIdentifier("coach.healthReadings")
    }

    /// Food does not need a weigh-in, so it is shown even while one is missing.
    private func foodNow(_ plan: CoachRecoveryResponse.Plan) -> some View {
        card {
            Text("FOOD CAN START NOW")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Text("About \(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h and \(Int(plan.proteinGrams.rounded())) g protein in one go. The fluid and salt numbers appear once both weigh-ins are in.")
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Ready

    private func sweatCard(_ sweat: CoachRecoveryResponse.Sweat) -> some View {
        let low = sweat.sweatLitersLow ?? sweat.sweatLitersRaw ?? 0
        let high = sweat.sweatLitersHigh ?? sweat.sweatLitersRaw ?? low
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("YOU SWEATED")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            if sweat.isLowerBound {
                Text("At least \(RecoveryCoachFormat.liters(low))")
                    .font(.tempoDataLarge)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .minimumScaleFactor(0.6)
                Text("I don't know what you drank, so this is a minimum. Tell me below and I'll narrow it.")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoWarning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("About \(RecoveryCoachFormat.litersRange(low: low, high: high))")
                    .font(.tempoDataLarge)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .minimumScaleFactor(0.6)
                if let margin = sweat.marginOfErrorPercent {
                    Text("\(RecoveryCoachFormat.margin(margin)) (95% range). An estimate, not a measurement.")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            Text("You lost \(String(format: "%.1f", sweat.massLostKg)) kg on the scale (\(String(format: "%.1f", sweat.percentBodyMassLost))% of your weight).")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
            if sweat.meetsFivePercentTarget {
                Label("Within 5% (95% range)", systemImage: "checkmark.seal")
                    .font(.tempoCaption1.weight(.semibold))
                    .foregroundStyle(Color.tempoSuccess)
            } else if sweat.protocolQuality == "loose" {
                Text("Your weigh-ins were far from the session, so the range is wider.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.sweat")
    }

    private func planCard(_ plan: CoachRecoveryResponse.Plan, sweat: CoachRecoveryResponse.Sweat) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Text("START HERE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoSignal)
            if let drink = plan.drinkLiters {
                planLine(
                    icon: "drop.fill", color: .tempoElectric,
                    title: "Drink \(RecoveryCoachFormat.liters(drink)) with a meal",
                    detail: "Over the next few hours, with food that has salt. Water alone leaves you short."
                )
            }
            if let sodium = plan.sodiumMgPlan, let low = plan.sodiumMgLow, let high = plan.sodiumMgHigh {
                planLine(
                    icon: "circle.hexagongrid.fill", color: .tempoAmber,
                    title: "Sodium about \(RecoveryCoachFormat.sodium(sodium))",
                    detail: "Could be \(RecoveryCoachFormat.sodiumRange(low: low, high: high)): sweat saltiness varies a lot between people."
                )
            }
            planLine(
                icon: "bolt.fill", color: .tempoMacroCarbs,
                title: "\(Int(plan.carbsGrams.rounded())) g carbs in the next \(Int(plan.carbWindowHours.rounded())) h",
                detail: nil
            )
            planLine(
                icon: "figure.strengthtraining.traditional", color: .tempoMacroProtein,
                title: "\(Int(plan.proteinGrams.rounded())) g protein in one go",
                detail: nil
            )
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityIdentifier("coach.plan")
    }

    private func planLine(icon: String, color: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.tempoSubheadline)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(title)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var fluidRow: some View {
        Button { showFluids = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("What you drank")
                        .font(.tempoSubheadline.weight(.semibold))
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(fluidSummary)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(model.fluids.liters.map { RecoveryCoachFormat.fluid($0) } ?? "Unknown")
                    .font(.tempoDataSmall)
                    .foregroundStyle(Color.tempoElectric)
                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.fluids")
    }

    private var fluidSummary: String {
        let f = model.fluids
        if let edited = f.editedLiters { return "You entered \(RecoveryCoachFormat.fluid(edited))." }
        var parts: [String] = []
        if f.loggedMl > 0 { parts.append("\(RecoveryCoachFormat.fluid(Double(f.loggedMl) / 1000)) logged in Tempo") }
        if let a = f.quickAnswerLiters { parts.append("\(RecoveryCoachFormat.fluid(a)) you answered") }
        return parts.isEmpty ? "Not known yet. Tap to tell me." : parts.joined(separator: " + ")
    }

    private func whyDisclosure(
        result: CoachRecoveryResponse, sweat: CoachRecoveryResponse.Sweat, plan: CoachRecoveryResponse.Plan
    ) -> some View {
        DisclosureGroup(isExpanded: $showWhy) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                bulletList("Why", plan.reasons)
                bulletList("What I assumed", sweat.assumptions + result.notes)
                bulletList("Evidence", plan.evidence)
            }
            .padding(.top, TempoSpacing.md)
        } label: {
            Text("Why these numbers")
                .font(.tempoSubheadline.weight(.semibold))
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .tint(Color.tempoTextSecondary)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityIdentifier("coach.why")
    }

    @ViewBuilder
    private func bulletList(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(title.uppercased())
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // Reminder toggle (quiet)

    private var reminderRow: some View {
        Toggle(isOn: $preMatchOn) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text("Remind me before football")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("A weigh-in nudge 1 hour before a scheduled session.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .tint(Color.tempoSignal)
        .onChange(of: preMatchOn) { _, on in
            RecoveryCoachStore.shared.update { $0.preMatchReminderOn = on }
            NotificationCenter.default.post(name: .tempoCoachSettingsChanged, object: nil)
        }
        .accessibilityIdentifier("coach.preMatchToggle")
    }

    // MARK: Shared card

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md, content: content)
            .padding(TempoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }
}

extension Notification.Name {
    /// The pre-match reminder toggle changed: the scheduler rebuilds.
    static let tempoCoachSettingsChanged = Notification.Name("tempoCoachSettingsChanged")
}

// MARK: - Loading steps with a clock

private struct LoadingSteps: View {
    let current: RecoveryCoachModel.Step
    let startedAt: Date
    var title = "WORKING ON IT"

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text(title)
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(RecoveryCoachFormat.clock(max(0, Int(context.date.timeIntervalSince(startedAt)))))
                        .font(.tempoDataSmall.monospacedDigit())
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            ForEach(RecoveryCoachModel.Step.allCases, id: \.rawValue) { step in
                HStack(spacing: TempoSpacing.md) {
                    if step.rawValue < current.rawValue {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tempoSuccess)
                    } else if step == current {
                        ProgressView()
                    } else {
                        Image(systemName: "circle").foregroundStyle(Color.tempoTextDisabled)
                    }
                    Text(step.title)
                        .font(.tempoSubheadline)
                        .foregroundStyle(step.rawValue <= current.rawValue ? Color.tempoTextPrimary : Color.tempoTextTertiary)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityIdentifier("coach.loading")
    }
}
