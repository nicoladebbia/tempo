import SwiftUI
import SwiftData

// MARK: - LockdownView (Non-Negotiable Cards)
// Per BUILD_PLAN step 10.3.
// Per MODULE_ACCOUNTABILITY.md — Lockdown Main View.
// Per WIREFRAMES.md Section 4 — Screen 65.
// Per UX_COPY_BIBLE.md Section 5 — Accountability strings.

struct LockdownMainView: View {

    @Bindable var viewModel: AccountabilityViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showUnlockCelebration = false
    @State private var expandedCardID: PersistentIdentifier?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main scrollable content
            ScrollView {
                VStack(spacing: TempoSpacing.md) {
                    // Date display
                    dateHeader

                    // Status banner
                    statusBanner

                    // Drill sergeant bubble
                    drillSergeantSection

                    // Non-negotiable cards
                    if viewModel.progressItems.isEmpty && !viewModel.isLoading {
                        emptyState
                    } else {
                        nonNegotiableCards
                    }

                    // Bottom padding for sticky elements
                    Spacer()
                        .frame(height: 160)
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
            }

            // Sticky bottom: Quick action + Leisure status
            VStack(spacing: 0) {
                // Quick action button
                if hasTimedNonNegotiable {
                    quickActionButton
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.bottom, TempoSpacing.md)
                }

                // Leisure status bar
                leisureStatusBar
            }
            .background(
                Color.tempoBgPrimary
                    .opacity(0.95)
                    .background(.ultraThinMaterial)
            )

            // Unlock celebration overlay
            if showUnlockCelebration {
                unlockCelebrationOverlay
            }
        }
        .background(Color.tempoBgPrimary)
        .onChange(of: viewModel.isLeisureUnlocked) { _, unlocked in
            if unlocked {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    showUnlockCelebration = true
                }
                // Dismiss after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showUnlockCelebration = false }
                }
            }
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.tempoSubheadline)
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Status Banner
    // Per MODULE_ACCOUNTABILITY.md — 80pt status banner with progress ring.

    private var statusBanner: some View {
        HStack(spacing: TempoSpacing.lg) {
            // Progress ring
            CircularRingView(
                progress: viewModel.completionPercentage,
                color: statusRingColor,
                ringSize: .medium,
                valueText: "\(Int(viewModel.completionPercentage * 100))%"
            )

            // Status text
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: viewModel.isLeisureUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(viewModel.isLeisureUnlocked ? Color.tempoSuccess : Color.tempoSignal)
                        .symbolEffect(.bounce, value: viewModel.isLeisureUnlocked)

                    Text(viewModel.isLeisureUnlocked ? "UNLOCKED" : "LOCKED")
                        .font(.tempoHeadline)
                        .foregroundStyle(viewModel.isLeisureUnlocked ? Color.tempoSuccess : Color.tempoSignal)
                }

                Text(statusTimeContext)
                    .font(.tempoFootnote)
                    .foregroundStyle(statusTimeColor)
            }

            Spacer()
        }
        .padding(TempoSpacing.cardPadding)
        .frame(height: 80)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    private var statusRingColor: Color {
        if viewModel.isLeisureUnlocked { return .tempoSuccess }
        if viewModel.dailyState == .dayFailed { return .tempoSignal }
        let pct = viewModel.completionPercentage
        if pct >= 0.8 { return .tempoSuccess }
        if pct >= 0.5 { return .tempoAmber }
        return .tempoElectric
    }

    // Per UX_COPY_BIBLE.md — time context strings
    private var statusTimeContext: String {
        if viewModel.isLeisureUnlocked {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < 12 { return "All done by noon. Legend." }
            let early = viewModel.timeToPS5
            if early > 0 {
                return "Unlocked \(viewModel.formattedTimeToPS5) early. Ahead of schedule."
            }
            return "Unlocked. Better late than never."
        }

        if viewModel.dailyState == .dayFailed {
            return "PS5 time passed. Handle your business."
        }

        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 {
            return "Just 1 more. So close."
        }

        let timeToPS5 = viewModel.timeToPS5
        if timeToPS5 < 30 * 60 {
            return "\(viewModel.formattedTimeToPS5). Move."
        }
        if timeToPS5 < 60 * 60 {
            return "\(viewModel.formattedTimeToPS5). Clock's ticking."
        }
        if timeToPS5 < 2 * 3600 {
            return "\(viewModel.formattedTimeToPS5) left. Focus up."
        }
        return "\(viewModel.formattedTimeToPS5) until your usual PS5 time"
    }

    private var statusTimeColor: Color {
        if viewModel.isLeisureUnlocked { return .tempoSuccess }
        if viewModel.dailyState == .dayFailed { return .tempoSignal }
        if viewModel.timeToPS5 < 30 * 60 { return .tempoSignal }
        return .tempoTextSecondary
    }

    // MARK: - Drill Sergeant
    // Per MODULE_ACCOUNTABILITY.md — contextual drill sergeant message.

    private var drillSergeantSection: some View {
        Group {
            if let message = drillSergeantMessage {
                DrillSergeantBubble(message: message)
            }
        }
    }

    private var drillSergeantMessage: String? {
        switch viewModel.dailyState {
        case .morningSetup:
            return "New day, new chance to not be mediocre. Set your non-negotiables."
        case .tracking:
            let done = viewModel.completedCount
            let total = viewModel.totalCount
            if done == 0 {
                return "Zero progress. The day isn't going to handle itself."
            }
            return "\(done)/\(total) done. Keep moving."
        case .approachingDeadline:
            return "Clock's ticking. You're running out of daylight."
        case .finalWarning:
            return "Last chance. PS5 time is almost here and you're not done."
        case .dayFailed:
            return "PS5 time came and went. Tasks still incomplete. No excuses tomorrow."
        case .unlocked:
            return nil // No drill sergeant when unlocked — celebrate instead
        case .overrideActive:
            return "Rest day active. Recovery is part of the process. Don't make it a habit."
        case .review:
            return nil
        }
    }

    // MARK: - Non-Negotiable Cards

    private var nonNegotiableCards: some View {
        ForEach(viewModel.progressItems, id: \.persistentModelID) { progress in
            NonNegotiableCardView(
                progress: progress,
                isExpanded: expandedCardID == progress.persistentModelID,
                onTap: {
                    withAnimation(TempoAnimation.springMedium) {
                        expandedCardID = expandedCardID == progress.persistentModelID
                            ? nil
                            : progress.persistentModelID
                    }
                },
                onComplete: {
                    viewModel.completeItem(progress, modelContext: modelContext)
                },
                onSkip: {
                    viewModel.skipItem(progress, modelContext: modelContext)
                },
                onUpdateValue: { value in
                    viewModel.updateItemProgress(progress, value: value, modelContext: modelContext)
                }
            )
        }
    }

    // MARK: - Empty State
    // Per MODULE_ACCOUNTABILITY.md — empty state when no non-negotiables.

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.top, TempoSpacing.xxxxl)

            Text("No non-negotiables set")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.lg)

            Text("Define what you MUST do each day before you earn your downtime.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            Button("SET UP NON-NEGOTIABLES") {
                // Navigation to setup flow — will be connected in step 10.5
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)
        }
    }

    // MARK: - Quick Action Button
    // Per MODULE_ACCOUNTABILITY.md — sticky study timer CTA.

    private var hasTimedNonNegotiable: Bool {
        viewModel.progressItems.contains(where: { p in
            p.nonNegotiable?.trackingMethod == .timer
        })
    }

    private var studyComplete: Bool {
        viewModel.progressItems.allSatisfy { p in
            guard p.nonNegotiable?.type == .study else { return true }
            return p.isCompleted
        }
    }

    private var quickActionButton: some View {
        Button {
            HapticManager.impact(.heavy)
            viewModel.configureFocusTimer()
            // Navigation to focus timer — will be connected in step 10.4
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))

                Text(studyComplete ? "START ANOTHER SESSION" : "START STUDY TIMER")
                    .font(.tempoHeadline)
                    .tracking(1)
            }
            .foregroundStyle(studyComplete ? Color.tempoElectric : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                if studyComplete {
                    Color.clear
                } else {
                    LinearGradient(
                        colors: [Color.tempoElectric, Color.tempoElectric.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(
                        studyComplete ? Color.tempoElectric : .clear,
                        lineWidth: studyComplete ? 2 : 0
                    )
            )
            .shadow(
                color: studyComplete ? .clear : Color.tempoElectric.opacity(0.3),
                radius: 6, x: 0, y: 4
            )
        }
    }

    // MARK: - Leisure Status Bar
    // Per MODULE_ACCOUNTABILITY.md — pinned above tab bar.

    private var leisureStatusBar: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Divider()

            HStack(spacing: TempoSpacing.md) {
                // Lock icon
                Image(systemName: leisureLockIcon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(leisureLockColor)
                    .symbolEffect(.pulse, isActive: viewModel.dailyState == .dayFailed)

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("LEISURE STATUS")
                        .font(.tempoCaption1)
                        .tracking(1)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text(leisureStatusText)
                        .font(.tempoBody)
                        .foregroundStyle(leisureStatusTextColor)
                }

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.lg)

            // Progress bar
            if viewModel.activeOverride == nil {
                LinearProgressBar(
                    progress: viewModel.completionPercentage,
                    color: leisureProgressColor,
                    height: 8,
                    showPercentage: false
                )
                .padding(.horizontal, TempoSpacing.lg)
            }
        }
        .padding(.vertical, TempoSpacing.md)
        .background(
            leisureBackgroundTint
                .opacity(0.03)
                .background(Color.tempoBgPrimary)
        )
    }

    private var leisureLockIcon: String {
        if viewModel.isLeisureUnlocked || viewModel.activeOverride != nil {
            return "lock.open.fill"
        }
        return "lock.fill"
    }

    private var leisureLockColor: Color {
        if viewModel.isLeisureUnlocked { return .tempoSuccess }
        if viewModel.activeOverride != nil { return .tempoTextTertiary }
        if viewModel.dailyState == .dayFailed { return .tempoSignal }
        return .tempoSignal
    }

    private var leisureStatusText: String {
        if viewModel.activeOverride != nil {
            return "Rest day. No non-negotiables active."
        }
        if viewModel.isLeisureUnlocked {
            return "You earned it. Enjoy your evening."
        }
        if viewModel.dailyState == .dayFailed {
            return "PS5 time has passed. Tasks still incomplete."
        }
        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 {
            return "Just 1 more. You're right there."
        }
        return "Complete \(remaining) more to unlock"
    }

    private var leisureStatusTextColor: Color {
        if viewModel.isLeisureUnlocked { return .tempoSuccess }
        if viewModel.dailyState == .dayFailed { return .tempoSignal }
        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 { return .tempoAmber }
        return .tempoTextPrimary
    }

    private var leisureProgressColor: Color {
        let pct = viewModel.completionPercentage
        if pct >= 1.0 { return .tempoSuccess }
        if pct >= 0.5 { return .tempoAmber }
        return .tempoSignal
    }

    private var leisureBackgroundTint: Color {
        if viewModel.isLeisureUnlocked { return .tempoSuccess }
        if viewModel.dailyState == .dayFailed { return .tempoSignal }
        return .clear
    }

    // MARK: - Unlock Celebration
    // Per MODULE_ACCOUNTABILITY.md — confetti + glow on leisure unlock.
    // Per SOUND_AND_HAPTICS.md — triple success haptic.

    private var unlockCelebrationOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: TempoSpacing.lg) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Color.tempoSuccess)
                    .shadow(color: Color.tempoSuccess.opacity(0.5), radius: 20)

                Text("PS5 UNLOCKED")
                    .font(.tempoTitle1)
                    .foregroundStyle(Color.tempoSuccess)

                Text("You earned it. Enjoy your evening.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .transition(.scale.combined(with: .opacity))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tempoInk.opacity(0.6))
        .onTapGesture {
            withAnimation { showUnlockCelebration = false }
        }
    }
}

// MARK: - Non-Negotiable Card View
// Per MODULE_ACCOUNTABILITY.md — Individual card for each non-negotiable.
// Per WIREFRAMES.md Section 4 — Card states: notStarted, inProgress, completed, overdue, skipped.

struct NonNegotiableCardView: View {

    let progress: NonNegotiableProgress
    let isExpanded: Bool
    let onTap: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onUpdateValue: (Double) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var nn: NonNegotiable? { progress.nonNegotiable }
    private var cardState: CardState { resolveCardState() }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Row 1: Icon + Name + Status
            headerRow

            // Row 2: Progress bar
            if cardState != .skipped {
                progressRow
            }

            // Row 3: Supporting text + Action
            supportingRow

            // Expanded detail
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(cardBorder)
        .shadow(
            color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
            radius: 4, x: 0, y: 2
        )
        .opacity(cardState == .skipped ? 0.6 : 1.0)
        .scaleEffect(cardState == .completed ? 1.0 : 1.0)
        .onTapGesture { onTap() }
        .contextMenu { cardContextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: TempoSpacing.md) {
            // Icon
            Image(systemName: nn?.icon ?? "star.fill")
                .font(.system(size: 28))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            // Name
            Text(nn?.name ?? "Task")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .strikethrough(cardState == .skipped)

            Spacer()

            // Status indicator
            statusIndicator
        }
    }

    private var iconColor: Color {
        switch cardState {
        case .notStarted: return .tempoTextTertiary
        case .inProgress: return .tempoElectric
        case .completed: return .tempoSuccess
        case .overdue: return .tempoSignal
        case .skipped: return .tempoTextTertiary
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch cardState {
        case .notStarted:
            Text("NOT STARTED")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        case .inProgress:
            Text(progressText)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        case .completed:
            HStack(spacing: TempoSpacing.xs) {
                Text("DONE")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSuccess)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoSuccess)
            }
        case .overdue:
            Text("OVERDUE")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
        case .skipped:
            Text("SKIPPED")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private var progressText: String {
        guard let nn else { return "" }
        switch nn.trackingMethod {
        case .timer:
            let current = Int(progress.currentValue)
            let target = Int(progress.targetValue)
            let currentH = current / 60
            let currentM = current % 60
            let targetH = target / 60
            let targetM = target % 60
            if targetH > 0 {
                return "\(currentH)h \(currentM)m / \(targetH)h \(targetM)m"
            }
            return "\(currentM)m / \(targetM)m"
        case .manual:
            return "\(Int(progress.currentValue)) / \(Int(progress.targetValue))"
        case .autoWhoop, .autoNutritrack, .autoHealthkit:
            return "\(Int(progress.currentValue)) / \(Int(progress.targetValue))"
        }
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            // Source badge
            sourceBadge

            // Progress bar
            LinearProgressBar(
                progress: progress.targetValue > 0
                    ? progress.currentValue / progress.targetValue
                    : 0,
                color: progressBarColor,
                height: 6,
                showPercentage: false
            )

            // Percentage
            Text("\(Int(min(1, progress.targetValue > 0 ? progress.currentValue / progress.targetValue : 0) * 100))%")
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var progressBarColor: Color {
        let pct = progress.targetValue > 0 ? progress.currentValue / progress.targetValue : 0
        if pct >= 0.8 { return .tempoSuccess }
        if pct >= 0.5 { return .tempoAmber }
        return .tempoElectric
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let nn {
            let badgeText: String = {
                switch nn.type {
                case .train: return "WHOOP"
                case .meals: return "NUTRITRACK"
                case .study: return "MANUAL"
                case .sleep: return "HEALTHKIT"
                case .steps: return "HEALTHKIT"
                case .hydration: return "MANUAL"
                case .custom: return "MANUAL"
                }
            }()

            Text(badgeText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tempoBorder)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
        }
    }

    // MARK: - Supporting Row

    private var supportingRow: some View {
        HStack {
            Text(supportingText)
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)

            Spacer()

            // Action button
            actionButton
        }
    }

    private var supportingText: String {
        guard let nn else { return "" }
        switch nn.type {
        case .study:
            if !progress.isCompleted && progress.currentValue == 0 {
                return "Start a focus session to begin tracking"
            }
            if progress.isCompleted {
                return "\(Int(progress.currentValue))m total"
            }
            return "In progress"
        case .train:
            if !progress.isCompleted {
                return "Waiting for Whoop sync..."
            }
            return "Training recorded"
        case .meals:
            let logged = Int(progress.currentValue)
            let total = Int(progress.targetValue)
            if logged == 0 { return "Next: Breakfast" }
            if logged == 1 { return "Next: Lunch" }
            if logged < total { return "Next: Dinner before 8pm" }
            return "All meals logged today"
        case .sleep:
            if !progress.isCompleted { return "Syncs from HealthKit" }
            return "Sleep tracked"
        case .steps:
            if !progress.isCompleted { return "Syncs from HealthKit" }
            return "Steps goal met"
        case .hydration:
            if !progress.isCompleted && progress.currentValue == 0 {
                return "Tap to log water intake"
            }
            if progress.isCompleted { return "Hydration goal met" }
            return "In progress"
        case .custom:
            if !progress.isCompleted && progress.currentValue == 0 {
                return "Tap to start tracking"
            }
            if progress.isCompleted { return "Completed" }
            return "In progress"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let nn {
            switch nn.type {
            case .study:
                if progress.isCompleted {
                    pillButton(title: "Add More", style: .outline) {}
                } else {
                    pillButton(title: "Start Timer", style: .filled) {}
                }
            case .train:
                if !progress.isCompleted {
                    pillButton(title: "Log Manually", style: .filled) {
                        onComplete()
                    }
                }
            case .meals:
                if !progress.isCompleted {
                    pillButton(title: "Log in NutriTrack", style: .filled) {}
                }
            case .sleep, .steps:
                // Auto-tracked from HealthKit — no manual action
                EmptyView()
            case .hydration:
                if !progress.isCompleted {
                    pillButton(title: "+", style: .filled) {
                        onUpdateValue(progress.currentValue + 1)
                    }
                }
            case .custom:
                switch nn.trackingMethod {
                case .timer:
                    if !progress.isCompleted {
                        pillButton(title: "Start Timer", style: .filled) {}
                    }
                case .manual:
                    if !progress.isCompleted {
                        pillButton(title: "+", style: .filled) {
                            onUpdateValue(progress.currentValue + 1)
                        }
                    }
                case .autoWhoop, .autoNutritrack, .autoHealthkit:
                    EmptyView()
                }
            }
        }
    }

    enum PillStyle { case filled, outline }

    private func pillButton(title: String, style: PillStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tempoCaption1)
                .foregroundStyle(style == .filled ? .white : Color.tempoElectric)
                .padding(.horizontal, TempoSpacing.md)
                .frame(height: 28)
                .background(style == .filled ? Color.tempoElectric : .clear)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                .overlay(
                    style == .outline
                        ? RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
                            .stroke(Color.tempoElectric, lineWidth: 1)
                        : nil
                )
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Divider()

            // Quick actions
            HStack(spacing: TempoSpacing.md) {
                if !progress.isCompleted {
                    Button {
                        HapticManager.notification(.success)
                        onComplete()
                    } label: {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoSuccess)
                    }

                    Button {
                        onSkip()
                    } label: {
                        Label("Skip Today", systemImage: "forward.fill")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
        .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Card Visual State

    private var cardBackground: Color {
        switch cardState {
        case .completed: return Color.tempoSuccess.opacity(0.05)
        case .overdue: return Color.tempoSignal.opacity(0.03)
        default: return Color.tempoSurfaceCard
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch cardState {
        case .notStarted, .skipped: return .tempoBorder
        case .inProgress: return .tempoElectric
        case .completed: return .tempoSuccess
        case .overdue: return .tempoSignal
        }
    }

    // MARK: - Context Menu
    // Per UX_COPY_BIBLE.md — context menu strings.

    @ViewBuilder
    private var cardContextMenu: some View {
        if !progress.isCompleted {
            Button {
                HapticManager.notification(.success)
                onComplete()
            } label: {
                Label("Mark as Complete", systemImage: "checkmark.circle")
            }

            Button {
                onSkip()
            } label: {
                Label("Skip Today", systemImage: "forward.fill")
            }
        }

        Button {
            // Edit — will be connected in step 10.5
        } label: {
            Label("Edit Non-Negotiable", systemImage: "pencil")
        }

        Button {
            // History — will be connected in step 10.6
        } label: {
            Label("View History", systemImage: "clock.arrow.circlepath")
        }
    }

    // MARK: - State Resolution

    enum CardState {
        case notStarted, inProgress, completed, overdue, skipped
    }

    private func resolveCardState() -> CardState {
        // Skipped: completed but currentValue < targetValue
        if progress.isCompleted && progress.currentValue < progress.targetValue {
            return .skipped
        }
        if progress.isCompleted {
            return .completed
        }
        if progress.currentValue > 0 {
            return .inProgress
        }
        // Check if overdue (past PS5 time)
        let now = Date()
        let ps5 = Calendar.current.date(
            bySettingHour: Calendar.current.isDateInWeekend(now) ? 21 : 19,
            minute: Calendar.current.isDateInWeekend(now) ? 0 : 30,
            second: 0,
            of: now
        ) ?? now
        if now > ps5 && !progress.isCompleted {
            return .overdue
        }
        return .notStarted
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let name = nn?.name ?? "Task"
        let state = cardState
        let pct = progress.targetValue > 0
            ? Int(progress.currentValue / progress.targetValue * 100)
            : 0
        switch state {
        case .notStarted: return "\(name), not started"
        case .inProgress: return "\(name), \(pct) percent complete"
        case .completed: return "\(name), completed"
        case .overdue: return "\(name), overdue"
        case .skipped: return "\(name), skipped"
        }
    }
}
