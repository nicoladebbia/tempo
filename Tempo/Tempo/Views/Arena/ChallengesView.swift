//
// ChallengesView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ChallengeTemplate

// Pre-defined challenge templates users can start with one tap.

struct ChallengeTemplate: Identifiable {
    let id = UUID()
    let iconName: String
    let name: String
    let templateDescription: String
    let metric: String
    let durationDays: Int
    let color: Color

    static let templates: [ChallengeTemplate] = [
        ChallengeTemplate(
            iconName: "flame.fill",
            name: "7-Day Grind",
            templateDescription: "Complete all non-negotiables for 7 days straight",
            metric: "non_negotiable_streak",
            durationDays: 7,
            color: Color.tempoAmber
        ),
        ChallengeTemplate(
            iconName: "dumbbell.fill",
            name: "Volume King",
            templateDescription: "Highest total training volume in a week",
            metric: "training_volume",
            durationDays: 7,
            color: Color.tempoSuccess
        ),
        ChallengeTemplate(
            iconName: "moon.fill",
            name: "Sleep Better",
            templateDescription: "Highest average sleep score over 7 days",
            metric: "sleep_score",
            durationDays: 7,
            color: Color.tempoViolet
        ),
        ChallengeTemplate(
            iconName: "book.fill",
            name: "Study Marathon",
            templateDescription: "Most study minutes in a week",
            metric: "study_minutes",
            durationDays: 7,
            color: Color.tempoSignal
        ),
        ChallengeTemplate(
            iconName: "figure.walk",
            name: "Step Master",
            templateDescription: "Most steps in a week",
            metric: "steps",
            durationDays: 7,
            color: Color.tempoInfo
        ),
    ]
}

// MARK: - ChallengesView

// Per MODULE_ARENA.md Section 9 — Challenge hub with active, invites, create new.
// Per WIREFRAMES.md Screens 38-39 — Challenge creation + active view.
// Enhanced with Quick Start challenge templates.

struct ChallengesView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Query(filter: #Predicate<ChallengeLocal> { $0.isActive })
    private var activeChallenges: [ChallengeLocal]

    @State
    private var selectedTab: ChallengeTab = .active
    @State
    private var showCreateChallenge = false

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
                        quickStartSection
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

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tempoAmber)
                Text("QUICK START")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TempoSpacing.md) {
                    ForEach(ChallengeTemplate.templates) { template in
                        quickStartCard(template)
                    }
                }
            }
        }
    }

    private func quickStartCard(_ template: ChallengeTemplate) -> some View {
        Button {
            startQuickChallenge(template)
        } label: {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack {
                    Image(systemName: template.iconName)
                        .font(.tempoTitle1)
                        .foregroundStyle(template.color)
                    Spacer()
                    Text("\(template.durationDays)d")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(template.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(template.color.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(template.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Text(template.templateDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("START")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        LinearGradient(
                            colors: [template.color, template.color.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(TempoSpacing.md)
            .frame(width: 160)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func startQuickChallenge(_ template: ChallengeTemplate) {
        let challenge = ChallengeLocal(
            name: template.name,
            metric: template.metric,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: template.durationDays, to: Date()) ?? Date(),
            myScore: 0,
            isActive: true,
            challengeDescription: template.templateDescription,
            participantCount: 1
        )
        modelContext.insert(challenge)
        try? modelContext.save()
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
                Image(systemName: "flag.2.crossed.fill")
                    .font(.tempoTitle3)
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

// MARK: - ChallengeTab

enum ChallengeTab: String, CaseIterable {
    case active
    case pending
    case completed

    var label: String {
        switch self {
        case .active: "ACTIVE"
        case .pending: "PENDING"
        case .completed: "COMPLETED"
        }
    }
}

// MARK: - ChallengeCreationSheet

// Per WIREFRAMES.md Screen 38 — Step-by-step creation.

struct ChallengeCreationSheet: View {
    @Environment(\.modelContext)
    private var modelContext
    @Binding
    var isPresented: Bool
    @State
    private var step = 1
    @State
    private var selectedMetric: String?
    @State
    private var selectedDuration: Int = 7
    @State
    private var selectedFriends: Set<String> = []
    @State
    private var isSoloChallenge: Bool = false

    /// Mock friends list — will be replaced with real friend data
    @State
    private var availableFriends: [FriendDisplayItem] = [
        FriendDisplayItem(userID: "demo1", username: "alex_fit", displayName: "Alex", level: 8, weeklyXP: 320, isOnline: true),
        FriendDisplayItem(userID: "demo2", username: "maria_run", displayName: "Maria", level: 12, weeklyXP: 580, isOnline: true),
        FriendDisplayItem(userID: "demo3", username: "jake_gym", displayName: "Jake", level: 5, weeklyXP: 150, isOnline: false),
    ]

    private let metrics = [
        ("book.fill", "Most Study Hours", "study_minutes"),
        ("dumbbell.fill", "Most Workouts", "workout_count"),
        ("figure.walk", "Most Steps", "steps"),
        ("star.fill", "Highest XP", "xp_total"),
        ("flame.fill", "Longest Streak", "streak_maintain"),
    ]

    private let durations = [3, 7, 14, 30]

    private let totalSteps = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xxl) {
                // Step indicator
                Text("Step \(step) of \(totalSteps)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)

                if step == 1 {
                    metricSelection
                } else if step == 2 {
                    friendSelection
                } else {
                    durationSelection
                }

                Spacer()

                // Next/Create button
                Button {
                    if step < totalSteps {
                        withAnimation { step += 1 }
                    } else {
                        createChallenge()
                        isPresented = false
                    }
                } label: {
                    Text(step < totalSteps ? "NEXT" : "CREATE CHALLENGE")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            canProceed ?
                                LinearGradient(colors: [Color.tempoSignal, Color.tempoViolet], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [Color.tempoSteel], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canProceed)
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("START A CHALLENGE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 1 {
                        Button {
                            withAnimation { step -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
        }
    }

    private var canProceed: Bool {
        switch step {
        case 1: selectedMetric != nil
        case 2: !selectedFriends.isEmpty || isSoloChallenge
        case 3: true
        default: false
        }
    }

    // MARK: - Create Challenge

    private func createChallenge() {
        guard let metricKey = selectedMetric else {
            return
        }
        let metricName = metrics.first(where: { $0.2 == metricKey })?.1 ?? metricKey

        let participantCount = isSoloChallenge ? 1 : selectedFriends.count + 1

        let challenge = ChallengeLocal(
            name: metricName,
            metric: metricKey,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: selectedDuration, to: Date()) ?? Date(),
            myScore: 0,
            isActive: true,
            participantCount: participantCount
        )
        modelContext.insert(challenge)
        try? modelContext.save()
    }

    // MARK: - Step 1: Metric Selection

    private var metricSelection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("What are you competing on?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)

            ForEach(metrics, id: \.2) { iconName, title, key in
                Button {
                    selectedMetric = key
                } label: {
                    HStack(spacing: TempoSpacing.md) {
                        Image(systemName: iconName)
                            .font(.tempoTitle1)
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
                            .stroke(
                                selectedMetric == key ? Color.tempoSignal : Color.tempoBorder,
                                lineWidth: selectedMetric == key ? 2 : 0.5
                            )
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

    // MARK: - Step 2: Friend Selection

    private var friendSelection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Who are you challenging?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)

            // Solo option
            Button {
                isSoloChallenge.toggle()
                if isSoloChallenge {
                    selectedFriends.removeAll()
                }
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.tempoSignal)
                        .frame(width: 40, height: 40)
                        .background(Color.tempoSignal.opacity(0.15))
                        .clipShape(Circle())
                    Text("Solo Challenge")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    if isSoloChallenge {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, TempoSpacing.lg)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSoloChallenge ? Color.tempoSignal : Color.tempoBorder, lineWidth: isSoloChallenge ? 2 : 0.5)
                )
            }

            if !availableFriends.isEmpty {
                Text("OR CHALLENGE FRIENDS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.xs)

                ForEach(availableFriends) { friend in
                    Button {
                        isSoloChallenge = false
                        if selectedFriends.contains(friend.userID) {
                            selectedFriends.remove(friend.userID)
                        } else {
                            selectedFriends.insert(friend.userID)
                        }
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            // Avatar
                            Circle()
                                .fill(Color.tempoSignal.opacity(0.15))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(friend.displayName.prefix(1)))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.tempoSignal)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text("Level \(friend.level)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }

                            Spacer()

                            // Online indicator
                            Circle()
                                .fill(friend.isOnline ? Color.tempoSuccess : Color.tempoSteel)
                                .frame(width: 8, height: 8)

                            if selectedFriends.contains(friend.userID) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.tempoSignal)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.tempoBorder)
                            }
                        }
                        .frame(height: 56)
                        .padding(.horizontal, TempoSpacing.lg)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    selectedFriends.contains(friend.userID) ? Color.tempoSignal : Color.tempoBorder,
                                    lineWidth: selectedFriends.contains(friend.userID) ? 2 : 0.5
                                )
                        )
                    }
                }
            }

            if availableFriends.isEmpty {
                VStack(spacing: TempoSpacing.sm) {
                    Text("No friends yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Add friends from the Arena to challenge them!")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, TempoSpacing.md)
            }
        }
    }

    private func durationLabel(_ days: Int) -> String {
        switch days {
        case 3: "Weekend Warrior"
        case 7: "Weekly War"
        case 14: "Fortnight Fight"
        case 30: "Monthly Marathon"
        default: "\(days) days"
        }
    }
}
