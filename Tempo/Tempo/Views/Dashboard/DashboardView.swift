import SwiftData
import SwiftUI

// MARK: - Dashboard View
// Per MODULE_DASHBOARD.md Section 3 — Main Dashboard View.
// ScrollView with: [A] Header, [B] Score Ring, [C] 2x2 Quadrant Grid,
// [D] Non-Negotiables Bar, [E] Quick Insights Banner.

struct DashboardView: View {

    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel?
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                if let viewModel {
                    switch viewModel.loadState {
                    case .loading where !hasAppeared:
                        // First load — show skeleton shimmer
                        DashboardLoadingView()

                    case .error(let message) where !hasAppeared:
                        // Error on first load — full-screen error
                        ErrorStateView(
                            title: "Sync failed.",
                            message: message,
                            retryAction: {
                                Task {
                                    await viewModel.refresh()
                                    viewModel.refreshTrainingStatus(modelContext: modelContext)
                    viewModel.refreshAccountability(modelContext: modelContext)
                                }
                            }
                        )

                    default:
                        // Loaded, or loading with previous data (pull-to-refresh keeps old data visible)
                        dashboardContent(viewModel)
                    }
                } else {
                    DashboardLoadingView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if viewModel == nil {
                let vm = DashboardViewModel(services: services)
                self.viewModel = vm
                await vm.refresh()
                vm.refreshTrainingStatus(modelContext: modelContext)
                hasAppeared = true
            }
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(_ vm: DashboardViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // [A] Header Bar
                headerBar(vm)

                // [B] Daily Score Section
                dailyScoreSection(vm)
                    .padding(.top, TempoSpacing.lg)

                // [C] Quadrant Grid
                quadrantGrid(vm)
                    .padding(.top, 20)

                // [D] Non-Negotiables Bar
                nonNegotiablesBar(vm)
                    .padding(.top, 20)

                // [E] Quick Insights Banner (placeholder for now)
                insightsBanner()
                    .padding(.top, TempoSpacing.lg)

                // Bottom breathing room
                Spacer()
                    .frame(height: 50)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
        .refreshable {
            await vm.refresh()
            vm.refreshTrainingStatus(modelContext: modelContext)
        }
    }

    // MARK: - [A] Header Bar
    // Per MODULE_DASHBOARD.md Section 3.2

    private func headerBar(_ vm: DashboardViewModel) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                // Date line
                Text(vm.formattedDate)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)

                // Greeting line
                Text(vm.greeting)
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Spacer()

            HStack(spacing: TempoSpacing.sm) {
                // Settings
                Button {
                    // Settings navigation — wired in later phase
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(width: 44, height: 44)

                // Notifications
                Button {
                    // Notifications navigation — wired in later phase
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(width: 44, height: 44)
            }
        }
        .padding(.top, TempoSpacing.sm)
    }

    // MARK: - [B] Daily Score Section
    // Per MODULE_DASHBOARD.md Section 3.3

    private func dailyScoreSection(_ vm: DashboardViewModel) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            if let score = vm.dailyScore {
                ScoreRingView(
                    score: Double(score),
                    maxScore: 100,
                    size: 100,
                    strokeWidth: 8
                )
            } else {
                // Insufficient data / loading — empty ring with "--"
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)

                    Text("--")
                        .font(.tempoScoreDisplay)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            Text("Daily Score")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(vm.formattedLastSync)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - [C] Quadrant Grid
    // Per MODULE_DASHBOARD.md Section 3.4

    private func quadrantGrid(_ vm: DashboardViewModel) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: TempoSpacing.lg),
                GridItem(.flexible(), spacing: TempoSpacing.lg),
            ],
            spacing: TempoSpacing.lg
        ) {
            // Top-left: BODY
            bodyQuadrantCard(vm.body)

            // Top-right: FUEL
            fuelQuadrantCard(vm.fuel)

            // Bottom-left: MIND
            mindQuadrantCard(vm.mind)

            // Bottom-right: MOVE
            moveQuadrantCard(vm.move)
        }
    }

    // MARK: - Body Quadrant Card
    // Per MODULE_DASHBOARD.md Section 3.4.1

    private func bodyQuadrantCard(_ data: BodyQuadrantData) -> some View {
        quadrantCardShell(
            label: "BODY",
            icon: "heart.fill",
            iconColor: data.recoveryZone?.color ?? Color.tempoTextTertiary
        ) {
            if data.isConnected {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    // Primary: Recovery score
                    Text(data.formattedRecovery)
                        .font(.tempoTitle1)
                        .foregroundStyle(data.recoveryZone?.color ?? Color.tempoTextPrimary)

                    Text("Recovery")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)

                    // Secondary metrics row
                    HStack(spacing: 0) {
                        metricBlock(value: data.formattedHRV, label: "HRV")
                        Spacer()
                        metricBlock(value: data.formattedRHR, label: "RHR")
                        Spacer()
                        metricBlock(value: data.formattedSleep, label: "Sleep")
                    }

                    // Strain bar
                    strainBar(strain: data.strain)
                }
            } else {
                disconnectedState(
                    icon: "sensor.tag.radiowaves.forward.fill",
                    title: "Connect Whoop",
                    subtitle: "to track recovery"
                )
            }
        }
    }

    // MARK: - Fuel Quadrant Card
    // Per MODULE_DASHBOARD.md Section 3.4.2

    private func fuelQuadrantCard(_ data: FuelQuadrantData) -> some View {
        quadrantCardShell(
            label: "FUEL",
            icon: "flame.fill",
            iconColor: Color.tempoViolet
        ) {
            if data.isConnected {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    // Calorie ring + text
                    HStack(spacing: TempoSpacing.sm) {
                        // Mini calorie ring
                        ZStack {
                            Circle()
                                .stroke(Color.tempoBorder, lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: min(data.calorieProgress, 1.0))
                                .stroke(Color.tempoViolet, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(data.formattedCalories)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text(data.formattedCalories)
                                    .font(.tempoCallout)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(" / \(data.formattedCalorieTarget)")
                                    .font(.tempoCallout)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                            .minimumScaleFactor(0.8)

                            Text("kcal")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }

                    // Macro bars
                    macroBar(label: "P", current: data.formattedProtein, target: data.formattedProteinTarget,
                             progress: macroProgress(data.proteinGrams, data.proteinTarget),
                             color: Color(red: 90/255, green: 200/255, blue: 250/255)) // #5AC8FA

                    macroBar(label: "C", current: data.formattedCarbs, target: data.formattedCarbsTarget,
                             progress: macroProgress(data.carbsGrams, data.carbsTarget),
                             color: Color(red: 255/255, green: 214/255, blue: 10/255)) // #FFD60A

                    macroBar(label: "F", current: data.formattedFat, target: data.formattedFatTarget,
                             progress: macroProgress(data.fatGrams, data.fatTarget),
                             color: Color(red: 255/255, green: 159/255, blue: 10/255)) // #FF9F0A

                    // Meals logged
                    Text(data.formattedMeals)
                        .font(.tempoCaption1)
                        .foregroundStyle(
                            (data.mealsLogged ?? 0) >= (data.mealsPlanned ?? 1)
                                ? Color.tempoSuccess : Color.tempoTextSecondary
                        )
                }
            } else {
                disconnectedState(
                    icon: "fork.knife",
                    title: "Connect NutriTrack",
                    subtitle: "to track nutrition"
                )
            }
        }
    }

    // MARK: - Mind Quadrant Card
    // Per MODULE_DASHBOARD.md Section 3.4.3

    private func mindQuadrantCard(_ data: MindQuadrantData) -> some View {
        quadrantCardShell(
            label: "MIND",
            icon: "book.fill",
            iconColor: Color.tempoElectric
        ) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                // Primary: Study time
                Text(data.formattedStudyTime)
                    .font(.tempoTitle1)
                    .foregroundStyle(Color.tempoTextPrimary)

                // Subtitle: progress fraction
                if data.studyMinutesToday >= data.studyTargetMinutes && data.studyTargetMinutes > 0 {
                    Text("Target hit.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSuccess)
                } else {
                    Text("\(data.studyMinutesToday) / \(data.studyTargetMinutes) min")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tempoBorder).frame(height: 4)
                        Capsule().fill(Color.tempoElectric)
                            .frame(width: geo.size.width * min(data.studyProgress, 1.0), height: 4)
                    }
                }
                .frame(height: 4)

                // Exam countdown
                if let exam = data.exams.first {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text("\(exam.name) \(exam.formattedCountdown)")
                            .font(.tempoCaption1)
                            .foregroundStyle(examCountdownColor(exam.daysUntil))
                            .lineLimit(1)
                    }
                } else {
                    Text("No upcoming exams")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                // Streak badge
                if data.currentStreakDays >= 2 {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.tempoAmber)
                        Text("\(data.formattedStreak) streak")
                            .font(data.currentStreakDays >= 7 ? .tempoCaption1 : .tempoCaption2)
                            .foregroundStyle(data.currentStreakDays >= 7 ? Color.tempoAmber : Color.tempoTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Move Quadrant Card
    // Per MODULE_DASHBOARD.md Section 3.4.4

    private func moveQuadrantCard(_ data: MoveQuadrantData) -> some View {
        quadrantCardShell(
            label: "MOVE",
            icon: "figure.run",
            iconColor: Color.tempoAmber
        ) {
            if data.isConnected {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    // Primary: Workout status
                    switch data.workoutStatus {
                    case .completed:
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.tempoSuccess)
                            Text("Done")
                                .font(.tempoTitle1)
                                .foregroundStyle(Color.tempoSuccess)
                        }
                        if let name = data.workoutName {
                            Text("\(name) — \(data.formattedWorkoutDuration)")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .lineLimit(1)
                        }
                    case .planned:
                        Text(data.workoutName ?? "Workout")
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)
                        Text("Planned for today")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoAmber)
                    case .restDay:
                        Text("Rest Day")
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text("Recovery is training.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .italic()
                    case .none:
                        Text("No workout")
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text("Add one or skip — your call.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    // Secondary metrics: Steps + Active Cal
                    HStack(spacing: 0) {
                        metricBlock(
                            value: data.formattedSteps,
                            label: "Steps",
                            valueColor: stepsColor(data.steps, target: data.stepsTarget)
                        )
                        Spacer()
                        metricBlock(value: data.formattedActiveCalories, label: "Active Cal")
                    }

                    // Steps progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.tempoBorder).frame(height: 4)
                            Capsule().fill(Color.tempoAmber)
                                .frame(width: geo.size.width * min(data.stepsProgress, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Spacer()
                        Text("\(NumberFormatter.localizedString(from: NSNumber(value: data.stepsTarget), number: .decimal)) goal")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            } else {
                disconnectedState(
                    icon: "heart.text.square",
                    title: "Allow Health Access",
                    subtitle: "to track activity"
                )
            }
        }
    }

    // MARK: - [D] Non-Negotiables Bar
    // Per MODULE_DASHBOARD.md Section 3.5

    private func nonNegotiablesBar(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if vm.nonNegotiablesTotal > 0 {
                // Header line
                HStack(spacing: TempoSpacing.xs) {
                    Text("\(vm.nonNegotiablesDone)/\(vm.nonNegotiablesTotal) done — PS5 \(vm.nonNegotiablesDone >= vm.nonNegotiablesTotal ? "unlocked" : "locked")")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Image(systemName: vm.nonNegotiablesDone >= vm.nonNegotiablesTotal ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            vm.nonNegotiablesDone >= vm.nonNegotiablesTotal
                                ? Color.tempoSuccess : Color.tempoTextTertiary
                        )
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tempoBorder).frame(height: 6)
                        Capsule()
                            .fill(vm.nonNegotiablesDone >= vm.nonNegotiablesTotal ? Color.tempoSuccess : Color.tempoSignal)
                            .frame(width: geo.size.width * vm.nonNegotiableProgress, height: 6)
                            .animation(TempoAnimation.springMedium, value: vm.nonNegotiableProgress)
                    }
                }
                .frame(height: 6)

                // Non-negotiable pills — flow layout
                FlowLayout(spacing: 12, lineSpacing: 6) {
                    ForEach(vm.nonNegotiables) { item in
                        nonNegotiablePill(item)
                    }
                }
            } else {
                // Empty state
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Set your daily non-negotiables")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)

                    Text("+ Add non-negotiable")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func nonNegotiablePill(_ item: NonNegotiableItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(item.isCompleted ? Color.tempoSuccess : Color.tempoTextTertiary)

            Text(item.title)
                .font(.tempoCaption2)
                .foregroundStyle(item.isCompleted ? Color.tempoTextSecondary : Color.tempoTextPrimary)
                .strikethrough(item.isCompleted)
        }
    }

    // MARK: - [E] Quick Insights Banner (Placeholder)

    @ViewBuilder
    private func insightsBanner() -> some View {
        // Insights engine not yet implemented — placeholder
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoWarning)

            Text("When you sleep < 6.5h, you skip breakfast 67% of the time.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(2)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(14)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Quadrant Card Shell

    @Environment(\.colorScheme) private var colorScheme

    private func quadrantCardShell<Content: View>(
        label: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category label + icon row
            HStack {
                Text(label)
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
            }

            Spacer().frame(height: TempoSpacing.sm)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .shadow(
            color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
            radius: 4, x: 0, y: 2
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 0.5)
                .opacity(colorScheme == .dark ? 1 : 0)
        )
    }

    // MARK: - Helpers

    private func metricBlock(value: String, label: String, valueColor: Color = .tempoTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.tempoCallout)
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func strainBar(strain: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoBorder).frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.tempoSuccess, Color.tempoWarning, Color.tempoError],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (strain.map { min($0 / 21.0, 1.0) } ?? 0), height: 4)
                }
            }
            .frame(height: 4)

            Text("Strain \(strain.map { String(format: "%.1f", $0) } ?? "--")")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func macroBar(label: String, current: String, target: String, progress: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(label) \(current)")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoBorder).frame(height: 6)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 6)
                }
            }
            .frame(height: 6)

            Text(target)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func macroProgress(_ current: Int?, _ target: Int?) -> Double {
        guard let current, let target, target > 0 else { return 0 }
        return Double(current) / Double(target)
    }

    private func disconnectedState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.tempoTextTertiary)

            Text(title)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(subtitle)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Button("Connect") {}
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextInverse)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.tempoSignal)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func examCountdownColor(_ daysUntil: Int) -> Color {
        switch daysUntil {
        case ...3: return Color.tempoError
        case 4...7: return Color.tempoWarning
        default: return Color.tempoTextSecondary
        }
    }

    private func stepsColor(_ steps: Int?, target: Int) -> Color {
        guard let steps else { return .tempoTextSecondary }
        if steps >= target { return .tempoSuccess }
        if steps >= Int(Double(target) * 0.7) { return .tempoTextPrimary }
        return .tempoTextSecondary
    }
}

// MARK: - Flow Layout (for non-negotiable pills)

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

// MARK: - Recovery Zone Color

extension RecoveryZone {
    var color: Color {
        switch self {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environment(ServiceContainer.mock())
}
