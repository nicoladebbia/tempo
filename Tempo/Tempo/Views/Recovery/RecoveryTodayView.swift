import SwiftUI
import SwiftData

// MARK: - Recovery Today View
// Per MODULE_RECOVERY.md Section 4 — Main screen of RecoverIQ module.
// Per WIREFRAMES.md Section 5 — Recovery layout.

struct RecoveryTodayView: View {

    @Bindable var viewModel: RecoveryViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {

                // Hero: Recovery Ring
                heroSection

                // Key Metrics Row
                metricsRow

                // Warnings (if any)
                if let prescription = viewModel.todayPrescription, !prescription.warnings.isEmpty {
                    warningsSection(prescription.warnings)
                }

                // Today's Prescription
                prescriptionSection

                // Quick Insights
                quickInsightsSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, 100)
        }
        .background(Color.tempoBgPrimary)
        .refreshable {
            await viewModel.refresh(modelContext: modelContext)
        }
        .task {
            if viewModel.loadState != .loaded {
                await viewModel.refresh(modelContext: modelContext)
            }
        }
    }

    // MARK: - Hero Section
    // Per MODULE_RECOVERY.md Section 4.2 — Recovery Ring + comparison label

    private var heroSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            // Recovery Ring with zone color
            ZStack {
                // Glow effect
                Circle()
                    .fill(zoneColor.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .blur(radius: 30)

                ScoreRingView(
                    score: viewModel.todayRecovery?.recoveryScore ?? 0,
                    maxScore: 100,
                    label: "RECOVERY",
                    size: 200,
                    strokeWidth: 14
                )
            }

            // Comparison label
            Text(viewModel.comparisonText)
                .font(.tempoCaption1)
                .foregroundStyle(
                    viewModel.comparisonIsPositive
                        ? Color.tempoRecoveryGreen
                        : Color.tempoRecoveryRed
                )

            // Date label
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Key Metrics Row
    // Per MODULE_RECOVERY.md Section 4.3 — HRV, RHR, SpO2, Temp

    private var metricsRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            metricTile(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: viewModel.formattedHRV,
                unit: "ms"
            )
            metricTile(
                icon: "heart.fill",
                label: "RHR",
                value: viewModel.formattedRHR,
                unit: "bpm"
            )
            metricTile(
                icon: "lungs.fill",
                label: "SpO2",
                value: viewModel.formattedSpO2,
                unit: "%"
            )
            metricTile(
                icon: "thermometer.medium",
                label: "Temp",
                value: viewModel.formattedSkinTemp,
                unit: "°C"
            )
        }
    }

    private func metricTile(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Image(systemName: icon)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)

            HStack(spacing: 2) {
                Text(value)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(unit)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Warnings Section
    // Per MODULE_RECOVERY.md — Warnings highlighted in red

    private func warningsSection(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoRecoveryRed)

                    Text(warning)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
                .padding(TempoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoRecoveryRedBg)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
        }
    }

    // MARK: - Prescription Section
    // Per MODULE_RECOVERY.md Section 4.4

    private var prescriptionSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            // Section header
            HStack(spacing: TempoSpacing.xs) {
                Circle()
                    .fill(zoneColor)
                    .frame(width: 8, height: 8)

                Text("Today's Prescription")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            if let prescription = viewModel.todayPrescription {
                // Training
                recoveryPrescriptionCard(
                    icon: "figure.strengthtraining.traditional",
                    category: "Training",
                    headline: prescription.trainingRec,
                    body: prescription.trainingDetail
                )

                // Nutrition
                if !prescription.nutritionRecs.isEmpty {
                    recoveryPrescriptionCard(
                        icon: "fork.knife",
                        category: "Meal Timing",
                        headline: prescription.nutritionRecs.first ?? "",
                        body: prescription.nutritionRecs.count > 1
                            ? prescription.nutritionRecs.dropFirst().joined(separator: " ")
                            : nil
                    )
                }

                // Bedtime
                recoveryPrescriptionCard(
                    icon: "bed.double.fill",
                    category: "Bedtime",
                    headline: "Target: \(viewModel.formattedBedtime)",
                    body: sleepDebtContext
                )

                // Caffeine cutoff
                recoveryPrescriptionCard(
                    icon: "cup.and.saucer.fill",
                    category: "Caffeine Cutoff",
                    headline: "No caffeine after \(viewModel.formattedCaffeineCutoff)",
                    body: "8-hour buffer before your target bedtime. This includes pre-workout, energy drinks, and tea."
                )

                // Hydration
                recoveryPrescriptionCard(
                    icon: "drop.fill",
                    category: "Hydration",
                    headline: "Target: \(viewModel.formattedHydration) today",
                    body: nil
                )
            } else {
                // Loading/empty state
                VStack(spacing: TempoSpacing.md) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text("Waiting for recovery data")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    Text("Connect your Whoop to see personalized prescriptions.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.xxxl)
            }
        }
    }

    // MARK: - Recovery Prescription Card
    // Per MODULE_RECOVERY.md Section 3.2

    private func recoveryPrescriptionCard(
        icon: String,
        category: String,
        headline: String,
        body: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Category header
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: icon)
                    .font(.tempoBody)
                    .foregroundStyle(zoneColor)

                Text(category)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Divider()
                .background(Color.tempoBorder)

            // Headline
            Text(headline)
                .font(.tempoBody)
                .fontWeight(.medium)
                .foregroundStyle(Color.tempoTextPrimary)

            // Body
            if let body, !body.isEmpty {
                Text(body)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Quick Insights Section
    // Per MODULE_RECOVERY.md Section 4.5

    private var quickInsightsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Quick Insights")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            // Recovery Trends Teaser
            if let avg = viewModel.avgRecovery7d {
                NavigationLink {
                    Text("Recovery Trends") // Placeholder — built in step 8.5
                } label: {
                    insightCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Recovery Trends",
                        detail: "7-day avg: \(Int(avg))%",
                        action: "See Trends"
                    )
                }
                .buttonStyle(.plain)
            }

            // Sleep Teaser
            if viewModel.todayRecovery?.sleepHours != nil {
                NavigationLink {
                    Text("Sleep Detail") // Placeholder — built in step 8.4
                } label: {
                    insightCard(
                        icon: "moon.zzz.fill",
                        title: "Last Night's Sleep",
                        detail: "\(viewModel.formattedSleepHours) · Score: \(viewModel.formattedSleepScore)",
                        action: "Details"
                    )
                }
                .buttonStyle(.plain)
            }

            // Strain Teaser
            if viewModel.todayRecovery?.strain != nil {
                NavigationLink {
                    Text("Strain Detail") // Placeholder — built in step 8.4
                } label: {
                    insightCard(
                        icon: "flame.fill",
                        title: "Yesterday's Strain",
                        detail: "\(viewModel.formattedStrain) · Calories: \(viewModel.formattedCalories)",
                        action: "Details"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func insightCard(icon: String, title: String, detail: String, action: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: icon)
                        .font(.tempoBody)
                        .foregroundStyle(zoneColor)

                    Text(title)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }

                Text(detail)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            HStack(spacing: TempoSpacing.xxs) {
                Text(action)
                    .font(.tempoCaption1)
                    .foregroundStyle(zoneColor)
                Image(systemName: "chevron.right")
                    .font(.tempoCaption2)
                    .foregroundStyle(zoneColor)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        switch viewModel.recoveryZone {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
    }

    private var sleepDebtContext: String? {
        guard let debt = viewModel.todayRecovery?.sleepDebt else { return nil }
        if debt < 0.5 {
            return "Sleep debt is minimal. Maintain your current routine."
        } else if debt < 2 {
            return "Sleep debt: \(String(format: "%.1f", debt))h. An extra 30-60 min tonight will help."
        } else if debt < 4 {
            return "Sleep debt: \(String(format: "%.1f", debt))h. Prioritize an early bedtime tonight."
        } else {
            return "Significant sleep debt (\(String(format: "%.1f", debt))h). Your body needs multiple nights of good sleep."
        }
    }
}

// MARK: - Comparison Helper for RecoveryLoadState

extension RecoveryLoadState: Equatable {
    static func == (lhs: RecoveryLoadState, rhs: RecoveryLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): true
        case (.loaded, .loaded): true
        case (.error(let a), .error(let b)): a == b
        default: false
        }
    }
}
