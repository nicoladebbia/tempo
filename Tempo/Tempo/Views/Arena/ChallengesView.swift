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
            color: Tide.streak
        ),
        ChallengeTemplate(
            iconName: "dumbbell.fill",
            name: "Volume King",
            templateDescription: "Highest total training volume in a week",
            metric: "training_volume",
            durationDays: 7,
            color: TideTone.mint
        ),
        ChallengeTemplate(
            iconName: "moon.fill",
            name: "Sleep Better",
            templateDescription: "Highest average sleep score over 7 days",
            metric: "sleep_score",
            durationDays: 7,
            color: TideTone.violet
        ),
        ChallengeTemplate(
            iconName: "book.fill",
            name: "Study Marathon",
            templateDescription: "Most study minutes in a week",
            metric: "study_minutes",
            durationDays: 7,
            color: Tide.water
        ),
        ChallengeTemplate(
            iconName: "figure.walk",
            name: "Step Master",
            templateDescription: "Most steps in a week",
            metric: "steps",
            durationDays: 7,
            color: TideTone.sky
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
    @Environment(\.tideMood)
    private var mood
    @Query(filter: #Predicate<ChallengeLocal> { $0.isActive })
    private var activeChallenges: [ChallengeLocal]

    @State
    private var selectedTab: ChallengeTab = .active
    @State
    private var showCreateChallenge = false
    @State
    private var startedCount = 0

    var body: some View {
        TideScrollPage {
            TidePillPicker(
                options: ChallengeTab.allCases,
                selection: $selectedTab,
                title: \.label,
                label: "Challenges"
            )

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
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateChallenge = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New challenge")
            }
        }
        .sensoryFeedback(.success, trigger: startedCount)
        .tideCovered(showCreateChallenge)
        .sheet(isPresented: $showCreateChallenge) {
            ChallengeCreationSheet(isPresented: $showCreateChallenge)
        }
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Quick start")

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Tide.s3) {
                    HStack(alignment: .top, spacing: Tide.s3) {
                        ForEach(ChallengeTemplate.templates) { template in
                            quickStartCard(template)
                        }
                    }
                }
                .padding(.horizontal, Tide.edge)
            }
            .scrollIndicators(.hidden)
            // Cards run to the screen edge; the page's own padding is undone.
            .padding(.horizontal, -Tide.edge)
        }
    }

    private func quickStartCard(_ template: ChallengeTemplate) -> some View {
        Button {
            startQuickChallenge(template)
        } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack {
                    TideAreaIconTile(systemName: template.iconName, tint: template.color)
                    Spacer(minLength: Tide.s2)
                    TideStatusPill(text: "\(template.durationDays) days", tint: template.color)
                }

                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(template.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)

                    Text(template.templateDescription)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Label("Start", systemImage: "play.fill")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(template.color)
                    .frame(minHeight: Tide.hit - Tide.s3, alignment: .leading)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .frame(width: Tide.s10 * 4.5)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityLabel("Start \(template.name), \(template.durationDays) days")
        .accessibilityHint(template.templateDescription)
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
        startedCount += 1
    }

    // MARK: - Active Section

    @ViewBuilder
    private var activeSection: some View {
        if activeChallenges.isEmpty {
            TideEmptyPanel(
                systemImage: "trophy",
                title: "No active challenges",
                message: "Pick a quick start above, or set up your own.",
                actionTitle: "Start a challenge"
            ) {
                showCreateChallenge = true
            }
            .tideCard()
        } else {
            ForEach(activeChallenges, id: \.id) { challenge in
                challengeCard(challenge)
            }
        }
    }

    // MARK: - Pending Section

    private var pendingSection: some View {
        TideEmptyPanel(
            systemImage: "envelope.badge",
            title: "No pending invites",
            message: "Challenge invites from friends will appear here."
        )
        .tideCard()
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        TideEmptyPanel(
            systemImage: "checkmark.circle",
            title: "No completed challenges yet",
            message: "Finish a challenge to see your history."
        )
        .tideCard()
    }

    // MARK: - Challenge Card

    private func challengeCard(_ challenge: ChallengeLocal) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            // Header
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: "flag.2.crossed.fill", tint: mood.accent)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(challenge.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                    Text("\(challenge.daysRemaining) days left")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                TideStatusPill(
                    text: challenge.hasStarted ? "Active" : "Upcoming",
                    tint: challenge.hasStarted ? TideTone.mint : TideTone.amber
                )
            }

            // Score
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Your score").tideLabel()
                    TideNumber(
                        challenge.myScore.formatted(.number.precision(.fractionLength(0))),
                        size: Tide.numeralL, color: mood.accent
                    )
                }
                Spacer(minLength: Tide.s2)
                if let rank = challenge.myRank {
                    VStack(alignment: .trailing, spacing: Tide.s1) {
                        Text("Rank").tideLabel()
                        TideNumber("#\(rank)", size: Tide.numeralL, color: rank == 1 ? TideTone.gold : Tide.text)
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: Tide.s2) {
                TideLevelBar(progress: challenge.timelineProgress, height: Tide.bar)
                HStack {
                    Text("Day \(Int(challenge.timelineProgress * Double(challenge.totalDays)) + 1) of \(challenge.totalDays)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                    Spacer()
                    Text("\(Int(challenge.timelineProgress * 100))%")
                        .font(Tide.numeral(Tide.numeralS - Tide.s2, .semibold))
                        .foregroundStyle(Tide.text2)
                }
            }
        }
        .tideCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ChallengeTab

enum ChallengeTab: String, CaseIterable {
    case active
    case pending
    case completed

    var label: String {
        switch self {
        case .active: "Active"
        case .pending: "Pending"
        case .completed: "Completed"
        }
    }
}

// MARK: - ChallengeCreationSheet

// Per WIREFRAMES.md Screen 38 — Step-by-step creation.

struct ChallengeCreationSheet: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
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
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("Step \(step) of \(totalSteps)").tideLabel()
                        TideLevelBar(progress: Double(step) / Double(totalSteps), height: Tide.barSlim)
                    }

                    Group {
                        if step == 1 {
                            metricSelection
                        } else if step == 2 {
                            friendSelection
                        } else {
                            durationSelection
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .tidePage()
            // The next step is always in reach, on glass over the field.
            .safeAreaInset(edge: .bottom) {
                Button {
                    if step < totalSteps {
                        withAnimation(Tide.snap) { step += 1 }
                    } else {
                        createChallenge()
                        isPresented = false
                    }
                } label: {
                    Text(step < totalSteps ? "Next" : "Create challenge")
                }
                .buttonStyle(.tidePrimary)
                .disabled(!canProceed)
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
                .sensoryFeedback(.selection, trigger: step)
            }
            .navigationTitle("Start a challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 1 {
                        Button {
                            withAnimation(Tide.snap) { step -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TideCloseButton { isPresented = false }
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

    // MARK: - Option row

    /// One choice: a glass row that gets a mood-coloured outline when picked.
    private func optionRow(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: Tide.s3) {
                content()
                Spacer(minLength: Tide.s2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.headline)
                    .foregroundStyle(selected ? mood.accent : Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(selected ? mood.accent : .clear, lineWidth: Tide.hair)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .animation(Tide.snap, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Step 1: Metric Selection

    private var metricSelection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("What are you competing on?")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)

            ForEach(metrics, id: \.2) { iconName, title, key in
                optionRow(selected: selectedMetric == key) {
                    selectedMetric = key
                } content: {
                    TideAreaIconTile(systemName: iconName, tint: mood.accent)
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                }
            }
        }
    }

    // MARK: - Step 3: Duration Selection

    private var durationSelection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("How long?")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)

            TidePillPicker(
                options: durations,
                selection: $selectedDuration,
                title: { "\($0)d" },
                label: "Duration"
            )

            // Duration label
            Text(durationLabel(selectedDuration))
                .font(Tide.headline)
                .foregroundStyle(mood.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.opacity)
                .animation(Tide.snap, value: selectedDuration)

            summaryCard
        }
    }

    // MARK: - Summary

    /// What is about to start, in the order it was chosen.
    private var summaryCard: some View {
        let metricName = metrics.first(where: { $0.2 == selectedMetric })?.1 ?? "-"
        let who = isSoloChallenge
            ? "Just you"
            : availableFriends.filter { selectedFriends.contains($0.userID) }.map(\.displayName).joined(separator: ", ")
        let ends = Calendar.current.date(byAdding: .day, value: selectedDuration, to: Date()) ?? Date()
        return VStack(spacing: 0) {
            summaryRow("Competing on", metricName)
            TideDivider()
            summaryRow("With", who.isEmpty ? "-" : who)
            TideDivider()
            summaryRow("Ends", ends.formatted(date: .abbreviated, time: .omitted))
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
        return layout {
            Text(label).tideLabel()
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            Text(value)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
    }

    // MARK: - Step 2: Friend Selection

    private var friendSelection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Who are you challenging?")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)

            // Solo option
            optionRow(selected: isSoloChallenge) {
                isSoloChallenge.toggle()
                if isSoloChallenge {
                    selectedFriends.removeAll()
                }
            } content: {
                TideAreaIconTile(systemName: "person.fill", tint: mood.accent)
                Text("Solo challenge")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
            }

            if !availableFriends.isEmpty {
                Text("Or challenge friends").tideLabel()
                    .padding(.top, Tide.s2)

                ForEach(availableFriends) { friend in
                    optionRow(selected: selectedFriends.contains(friend.userID)) {
                        isSoloChallenge = false
                        if selectedFriends.contains(friend.userID) {
                            selectedFriends.remove(friend.userID)
                        } else {
                            selectedFriends.insert(friend.userID)
                        }
                    } content: {
                        TideInitialAvatar(name: friend.displayName)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(friend.isOnline ? TideTone.mint : Tide.text3)
                                    .frame(width: Tide.s3, height: Tide.s3)
                                    .overlay(Circle().strokeBorder(Tide.ink, lineWidth: Tide.hair))
                            }
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(friend.displayName)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                            Text("Level \(friend.level)")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                }
            }

            if availableFriends.isEmpty {
                TideEmptyPanel(
                    systemImage: "person.2",
                    title: "No friends yet",
                    message: "Add friends from the Arena to challenge them."
                )
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
