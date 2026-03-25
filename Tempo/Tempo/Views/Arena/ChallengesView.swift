import SwiftUI
import SwiftData

// MARK: - Challenges View
// Per MODULE_ARENA.md Section 9 — Challenge hub with active, invites, create new.
// Per WIREFRAMES.md Screens 38-39 — Challenge creation + active view.

struct ChallengesView: View {

    @Environment(ServiceContainer.self) private var services
    @Query(filter: #Predicate<ChallengeLocal> { $0.isActive }) private var activeChallenges: [ChallengeLocal]

    @State private var selectedTab: ChallengeTab = .active
    @State private var showCreateChallenge = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(ChallengeTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.vertical, TempoSpacing.sm)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.lg) {
                    switch selectedTab {
                    case .active:
                        activeSection
                    case .pending:
                        pendingSection
                    case .completed:
                        completedSection
                    }
                }
                .padding(.horizontal, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.xxxl)
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("CHALLENGES")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateChallenge = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .sheet(isPresented: $showCreateChallenge) {
            ChallengeCreationSheet(isPresented: $showCreateChallenge)
        }
    }

    // MARK: - Active Section

    private var activeSection: some View {
        Group {
            if activeChallenges.isEmpty {
                emptyState(
                    icon: "trophy",
                    title: "No active challenges",
                    message: "No active challenges. Start one!",
                    ctaTitle: "Start a Challenge"
                ) {
                    showCreateChallenge = true
                }
            } else {
                ForEach(activeChallenges, id: \.id) { challenge in
                    challengeCard(challenge)
                }
            }
        }
    }

    // MARK: - Pending Section

    private var pendingSection: some View {
        emptyState(
            icon: "envelope.badge",
            title: "No pending invites",
            message: "Challenge invites from friends will appear here.",
            ctaTitle: nil,
            action: {}
        )
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        emptyState(
            icon: "checkmark.circle",
            title: "No completed challenges yet",
            message: "Complete a challenge to see your history.",
            ctaTitle: nil,
            action: {}
        )
    }

    // MARK: - Challenge Card

    private func challengeCard(_ challenge: ChallengeLocal) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            // Header
            HStack {
                Text("⚔️")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.name.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("\(challenge.daysRemaining) days left")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                // Status badge
                Text(challenge.hasStarted ? "ACTIVE" : "UPCOMING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(challenge.hasStarted ? Color.tempoSuccess : Color.tempoWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((challenge.hasStarted ? Color.tempoSuccess : Color.tempoWarning).opacity(0.15))
                    .clipShape(Capsule())
            }

            // Score
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR SCORE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text(String(format: "%.0f", challenge.myScore))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoSignal)
                }
                Spacer()
                if let rank = challenge.myRank {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("RANK")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text("#\(rank)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(rank == 1 ? Color.tempoAmber : Color.tempoTextPrimary)
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.tempoBorder)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.tempoSignal)
                            .frame(width: geo.size.width * challenge.timelineProgress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("Day \(Int(challenge.timelineProgress * Double(challenge.totalDays)) + 1) of \(challenge.totalDays)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Text("\(Int(challenge.timelineProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
        .tempoCard()
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, message: String, ctaTitle: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer().frame(height: TempoSpacing.xxxxl)
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            if let ctaTitle {
                Button(action: action) {
                    Text(ctaTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, TempoSpacing.xxl)
                        .padding(.vertical, TempoSpacing.md)
                        .background(Color.tempoSignal)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Challenge Tab

enum ChallengeTab: String, CaseIterable {
    case active, pending, completed

    var label: String {
        switch self {
        case .active: return "ACTIVE"
        case .pending: return "PENDING"
        case .completed: return "COMPLETED"
        }
    }
}

// MARK: - Challenge Creation Sheet
// Per WIREFRAMES.md Screen 38 — Step-by-step creation.

struct ChallengeCreationSheet: View {

    @Binding var isPresented: Bool
    @State private var step = 1
    @State private var selectedMetric: String?
    @State private var selectedDuration: Int = 7

    private let metrics = [
        ("📖", "Most Study Hours", "study_minutes"),
        ("🏋️", "Most Workouts", "workout_count"),
        ("🦶", "Most Steps", "steps"),
        ("⭐", "Highest XP", "xp_total"),
        ("🔥", "Longest Streak", "streak_maintain"),
    ]

    private let durations = [3, 7, 14, 30]

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xxl) {
                // Step indicator
                Text("Step \(step) of 2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)

                if step == 1 {
                    metricSelection
                } else {
                    durationSelection
                }

                Spacer()

                // Next/Create button
                Button {
                    if step == 1 {
                        withAnimation { step = 2 }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Text(step == 1 ? "NEXT" : "CREATE CHALLENGE")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            selectedMetric != nil ?
                                LinearGradient(colors: [Color.tempoSignal, Color.tempoViolet], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [Color.tempoSteel], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(selectedMetric == nil)
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("START A CHALLENGE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Metric Selection

    private var metricSelection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("What are you competing on?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)

            ForEach(metrics, id: \.2) { emoji, title, key in
                Button {
                    selectedMetric = key
                } label: {
                    HStack(spacing: TempoSpacing.md) {
                        Text(emoji)
                            .font(.system(size: 24))
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        if selectedMetric == key {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                    .frame(height: 72)
                    .padding(.horizontal, TempoSpacing.lg)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedMetric == key ? Color.tempoSignal : Color.tempoBorder, lineWidth: selectedMetric == key ? 2 : 0.5)
                    )
                }
            }
        }
    }

    // MARK: - Step 2: Duration Selection

    private var durationSelection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("How long?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)

            HStack(spacing: TempoSpacing.sm) {
                ForEach(durations, id: \.self) { days in
                    Button {
                        selectedDuration = days
                    } label: {
                        Text("\(days)d")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selectedDuration == days ? .white : Color.tempoTextPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(selectedDuration == days ? Color.tempoSignal : Color.tempoSurfaceCard)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedDuration == days ? Color.clear : Color.tempoBorder, lineWidth: 0.5)
                            )
                    }
                }
            }

            // Duration label
            Text(durationLabel(selectedDuration))
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func durationLabel(_ days: Int) -> String {
        switch days {
        case 3: return "Weekend Warrior"
        case 7: return "Weekly War"
        case 14: return "Fortnight Fight"
        case 30: return "Monthly Marathon"
        default: return "\(days) days"
        }
    }
}
