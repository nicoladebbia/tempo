import SwiftUI
import SwiftData

// MARK: - Week Plan View
// Per MODULE_TRAINING.md Section 9 — 7-day training plan grid.
// Per WIREFRAMES.md Section 3 — Week plan layout.

struct WeekPlanView: View {

    @Bindable var viewModel: TrainingViewModel
    @Environment(\.modelContext) private var modelContext

    private let dayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let calendar = Calendar.current

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Week header
                weekHeader

                // 7-day grid
                // Per MODULE_TRAINING.md Section 9.2
                dayGrid

                // Daily detail cards
                dailyCards
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, 100)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadWeekPlan(modelContext: modelContext)
        }
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        let plans = viewModel.weekPlans
        let dateText: String = {
            guard let first = plans.first?.date, let last = plans.last?.date else {
                return ""
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: first)) – \(formatter.string(from: last)), \(calendar.component(.year, from: first))"
        }()

        return Text(dateText)
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .padding(.top, TempoSpacing.md)
    }

    // MARK: - 7-Day Grid
    // Per MODULE_TRAINING.md Section 9.2

    private var dayGrid: some View {
        HStack(spacing: TempoSpacing.xxs) {
            ForEach(Array(viewModel.weekPlans.enumerated()), id: \.element.id) { index, plan in
                dayCell(plan: plan, dayLabel: dayAbbreviations[safe: index] ?? "")
            }
        }
    }

    private func dayCell(plan: WorkoutPlan, dayLabel: String) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed

        return VStack(spacing: TempoSpacing.xxs) {
            // Day label
            Text(dayLabel)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            // Recovery dot
            Circle()
                .fill(recoveryDotColor(plan: plan))
                .frame(width: 8, height: 8)

            // Workout type abbreviation
            Text(workoutAbbreviation(plan.type))
                .font(.tempoCaption2)
                .fontWeight(.medium)
                .foregroundStyle(workoutTypeColor(plan: plan))

            // Status indicator
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.tempoRecoveryGreen)
            } else if plan.type == .football {
                Image(systemName: "sportscourt")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Color.clear.frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(
            isToday
                ? Color.tempoSurfaceCard
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(isToday ? Color.tempoSignal : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    // MARK: - Daily Detail Cards
    // Per MODULE_TRAINING.md Section 9.3

    private var dailyCards: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(viewModel.weekPlans, id: \.id) { plan in
                dailyCard(plan: plan)
            }
        }
    }

    private func dailyCard(plan: WorkoutPlan) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed
        let dayName = dayName(for: plan.date)

        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            // Day label
            HStack(spacing: TempoSpacing.sm) {
                if isToday {
                    Text("TODAY")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoSignal)
                } else {
                    Text(dayName)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            // Workout info
            HStack {
                // Icon
                Image(systemName: workoutIcon(plan.type))
                    .font(.tempoBody)
                    .foregroundStyle(workoutTypeColor(plan: plan))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TempoSpacing.xs) {
                        Text(plan.type.displayName.uppercased())
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)

                        if isCompleted {
                            Text("— Completed")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoRecoveryGreen)
                        }
                    }

                    // Meta line
                    if plan.type.isGymWorkout {
                        Text("~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min · \(plan.orderedExercises.count) exercises")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else if plan.type == .football {
                        Text("Match day")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else if plan.type == .rest {
                        Text("Recovery day")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else if plan.type == .mobility {
                        Text("~25 min · Active recovery")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                Spacer()

                if isCompleted, let duration = plan.actualDurationMinutes {
                    Text("\(duration) min")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private func workoutAbbreviation(_ type: WorkoutType) -> String {
        switch type {
        case .push: "PSH"
        case .pull: "PUL"
        case .legs: "LEG"
        case .upper: "UPR"
        case .lower: "LWR"
        case .fullBody: "FUL"
        case .football: "FTB"
        case .run: "RUN"
        case .mobility: "MOB"
        case .rest: "RST"
        case .sprint: "SPR"
        case .conditioning: "CON"
        }
    }

    private func workoutIcon(_ type: WorkoutType) -> String {
        switch type {
        case .push, .pull, .legs, .upper, .lower, .fullBody:
            "figure.strengthtraining.traditional"
        case .football: "sportscourt"
        case .run, .sprint: "figure.run"
        case .conditioning: "flame"
        case .mobility: "figure.flexibility"
        case .rest: "bed.double"
        }
    }

    private func workoutTypeColor(plan: WorkoutPlan) -> Color {
        if plan.status == .completed { return Color.tempoRecoveryGreen }
        switch plan.type {
        case .football: return Color.tempoRecoveryYellow
        case .rest: return Color.tempoTextTertiary
        case .mobility: return Color.tempoTextSecondary
        default: return Color.tempoTextPrimary
        }
    }

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 { return Color.tempoRecoveryGreen }
        if adj >= 0.6 { return Color.tempoRecoveryYellow }
        return Color.tempoRecoveryRed
    }

    private func dayName(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        let totalSets = exercises.reduce(0) { $0 + ($1.sets?.count ?? 0) }
        return max(20, totalSets * 2 + exercises.count * 2)
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
