//
// ChallengesView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - ChallengesView

// Real challenges, kept on the server: you and the friends you invite race on
// one number (XP, finished workouts or focus minutes) for a few days. The score
// is what each person's own phone pushed (ArenaStatsDayDTO), counted for the
// challenge's dates only, so the ranking is the same on every phone.

struct ChallengesView: View {
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var showCreate = false
    @State
    private var challengeToLeave: ArenaChallengeDTO?
    @State
    private var errorMessage: String?
    @State
    private var busyIDs: Set<String> = []

    var body: some View {
        Group {
            switch arena.phase {
            case .idle,
                 .loading:
                TideScrollPage {
                    ArenaListSkeleton(rows: 3, label: "Loading challenges")
                }

            case let .failed(message):
                TideScrollPage {
                    TideEmptyPanel(
                        systemImage: "wifi.exclamationmark", title: "Could not load your challenges",
                        message: message, actionTitle: "Try again"
                    ) { Task { await arena.refresh() } }
                        .tideCard()
                }

            case .ready:
                if arena.challenges.isEmpty {
                    emptyPage
                } else {
                    list
                }
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("arena.challenges")
        .task { await arena.refresh() }
        .tideCovered(showCreate)
        .sheet(isPresented: $showCreate) {
            ChallengeCreationSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Leave \(challengeToLeave?.title ?? "this challenge")?",
            isPresented: Binding(get: { challengeToLeave != nil }, set: {
                if !$0 {
                    challengeToLeave = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Leave challenge", role: .destructive) {
                if let challenge = challengeToLeave {
                    run(challenge.id) { try await arena.leave(challenge) }
                }
            }
            Button("Stay in", role: .cancel) {}
        } message: {
            Text("Your score leaves the board for this challenge.")
        }
    }

    // MARK: - Empty

    private var emptyPage: some View {
        ArenaEmptyPage(
            title: "Race for a week",
            message: "Pick a goal, invite friends or go solo, and see who gets the most XP, workouts or focus time.",
            actionTitle: "New challenge",
            actionSystemImage: "flag.2.crossed.fill",
            action: { showCreate = true },
            art: { ArenaEmptyArt(systemImage: "flag.2.crossed.fill", tint: TideTone.amber) }
        )
    }

    // MARK: - List

    private var list: some View {
        TideScrollPage {
            let invited = arena.invitedChallenges
            let running = arena.runningChallenges
            let finished = arena.finishedChallenges

            if !invited.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(title: "Invitations", trailing: "\(invited.count)")
                    ForEach(invited) { challenge in
                        invitationCard(challenge)
                    }
                }
            }

            if !running.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(title: "Running", trailing: "\(running.count)")
                    ForEach(running) { challenge in
                        runningCard(challenge)
                    }
                }
            }

            if !finished.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(title: "Finished")
                    VStack(spacing: 0) {
                        ForEach(Array(finished.prefix(5).enumerated()), id: \.element.id) { index, challenge in
                            if index > 0 {
                                TideDivider()
                            }
                            finishedRow(challenge)
                        }
                    }
                    .tideCard(padding: Tide.s4)
                }
            }

            if arena.isStale {
                Label("Showing the last scores we got. Pull down to retry.", systemImage: "wifi.slash")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .refreshable { await arena.refresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showCreate = true
            } label: {
                Label("New challenge", systemImage: "plus")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
            .accessibilityIdentifier("arena.newChallenge")
        }
    }

    // MARK: - Cards

    private func invitationCard(_ challenge: ArenaChallengeDTO) -> some View {
        let busy = busyIDs.contains(challenge.id)
        let inviter = challenge.participants.first(where: { !$0.isMe && $0.status == "joined" })?.displayName
        return VStack(alignment: .leading, spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(challenge.title)
                    .font(Tide.headline).foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(challenge))
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let inviter {
                    Text("From \(inviter)").font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            HStack(spacing: Tide.s2) {
                Button("Decline") {
                    run(challenge.id) { try await arena.leave(challenge) }
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("arena.challengeDecline")
                Button("Join") {
                    run(challenge.id) { try await arena.join(challenge) }
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("arena.challengeJoin")
            }
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .opacity(busy ? 0.5 : 1)
    }

    private func runningCard(_ challenge: ArenaChallengeDTO) -> some View {
        let metric = challenge.metricKind
        let parts = metric?.parts(challenge.myScore) ?? (value: "\(challenge.myScore)", unit: "")
        let joined = challenge.participants
            .filter { $0.status == "joined" }
            .sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
        let busy = busyIDs.contains(challenge.id)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .top, spacing: Tide.s2) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(challenge.title)
                        .font(Tide.headline).foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(challenge))
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Leave challenge", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        challengeToLeave = challenge
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text2)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More for \(challenge.title)")
                .accessibilityIdentifier("arena.challengeMenu")
            }

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
            layout {
                TideNumber(parts.value, unit: parts.unit, size: Tide.numeralL, color: mood.accent)
                if let rank = challenge.myRank, challenge.memberCount > 1 {
                    Text(ArenaText.rank(rank, of: challenge.memberCount))
                        .font(Tide.bodyStrong).foregroundStyle(Tide.text2)
                }
            }
            .accessibilityElement(children: .combine)

            TideLevelBar(progress: challenge.timelineProgress(), height: Tide.barSlim)

            if joined.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(joined.enumerated()), id: \.element.id) { index, person in
                        if index > 0 {
                            TideDivider()
                        }
                        participantRow(person, metric: metric)
                    }
                }
            } else {
                Text("Just you so far. Invite a friend from the Friends page.")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .opacity(busy ? 0.5 : 1)
        .accessibilityIdentifier("arena.challengeCard")
    }

    private func participantRow(_ person: ArenaChallengeParticipantDTO, metric: ArenaChallengeMetric?) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        return layout {
            HStack(spacing: Tide.s3) {
                TideNumber(
                    person.rank.map { "\($0)" } ?? "-", size: Tide.numeralS, relativeTo: .headline,
                    color: Tide.text2
                )
                .frame(minWidth: Tide.s6)
                Text(person.isMe ? "You" : person.displayName)
                    .font(Tide.body)
                    .foregroundStyle(person.isMe ? mood.accent : Tide.text)
                    .lineLimit(stacked ? 3 : 1)
            }
            if !stacked {
                Spacer(minLength: Tide.s2)
            }
            Text(metric?.format(person.score) ?? "\(person.score)")
                .font(Tide.bodyStrong).foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func finishedRow(_ challenge: ArenaChallengeDTO) -> some View {
        let result: String = {
            guard let rank = challenge.myRank, challenge.memberCount > 1 else {
                return challenge.metricKind?.format(challenge.myScore) ?? "\(challenge.myScore)"
            }
            return "\(ArenaText.rank(rank, of: challenge.memberCount)) · \(challenge.metricKind?.format(challenge.myScore) ?? "")"
        }()
        return HStack(spacing: Tide.s3) {
            TideAreaIconTile(
                systemName: challenge.myRank == 1 && challenge.memberCount > 1 ? "trophy.fill" : "flag.checkered",
                tint: challenge.myRank == 1 && challenge.memberCount > 1 ? TideTone.gold : Tide.text2
            )
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(challenge.title)
                    .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(result).font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .accessibilityElement(children: .combine)
    }

    /// "Most XP · 4 days left".
    private func subtitle(_ challenge: ArenaChallengeDTO) -> String {
        let what = challenge.metricKind?.title ?? "Challenge"
        return "\(what) · \(challenge.timeLine())"
    }

    // MARK: - Actions

    private func run(_ id: String, _ work: @escaping () async throws -> Void) {
        guard !busyIDs.contains(id) else {
            return
        }
        busyIDs.insert(id)
        Task {
            defer { busyIDs.remove(id) }
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - ChallengeTemplate

/// A starting point for a new challenge: only goals the app really measures.
struct ChallengeTemplate: Identifiable, Equatable {
    let title: String
    let metric: ArenaChallengeMetric
    let days: Int

    var id: String {
        title
    }

    static let all: [ChallengeTemplate] = [
        ChallengeTemplate(title: "XP race", metric: .xpTotal, days: 7),
        ChallengeTemplate(title: "Gym week", metric: .workoutCount, days: 7),
        ChallengeTemplate(title: "Focus week", metric: .studyMinutes, days: 7),
    ]

    static let durations = [3, 7, 14, 30]
}

// MARK: - ChallengeCreationSheet

struct ChallengeCreationSheet: View {
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var title = ChallengeTemplate.all[0].title
    @State
    private var metric = ChallengeTemplate.all[0].metric
    @State
    private var days = ChallengeTemplate.all[0].days
    @State
    private var invited: Set<String> = []
    @State
    private var isCreating = false
    @State
    private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The server needs 3 to 100 characters.
    private var canCreate: Bool {
        (3 ... 100).contains(trimmedTitle.count) && !isCreating
    }

    var body: some View {
        NavigationStack {
            TideScrollPage {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Challenge").tideLabel()
                    Text("New challenge")
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tide.s4)

                templates

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("Name").tideLabel()
                    TextField("Name your challenge", text: $title)
                        .tideField()
                        .submitLabel(.done)
                        .accessibilityIdentifier("arena.challengeTitle")
                }

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("Who wins").tideLabel()
                    TidePillPicker(
                        options: ArenaChallengeMetric.allCases, selection: $metric,
                        title: \.shortTitle, label: "What counts"
                    )
                }

                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text("For how long").tideLabel()
                    TidePillPicker(
                        options: ChallengeTemplate.durations, selection: $days,
                        title: { ArenaText.count($0, "day") }, label: "Duration"
                    )
                }

                friendsSection

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("arena.challengeError")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    Task { await create() }
                } label: {
                    Label(isCreating ? "Starting" : "Start challenge", systemImage: "flag.2.crossed.fill")
                }
                .buttonStyle(.tidePrimary)
                .disabled(!canCreate)
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
                .accessibilityIdentifier("arena.challengeCreate")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("arena.challengeSheet")
    }

    // MARK: - Templates

    private var templates: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tide.s2) {
                ForEach(ChallengeTemplate.all) { template in
                    TideFilterChip(
                        title: template.title,
                        isSelected: title == template.title && metric == template.metric && days == template.days
                    ) {
                        title = template.title
                        metric = template.metric
                        days = template.days
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
        }
        .scrollIndicators(.hidden)
        // Chips run to the screen edge; the page's own padding is undone.
        .padding(.horizontal, -Tide.edge)
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Invite friends").tideLabel()
            if arena.friends.isEmpty {
                Text(
                    "No friends yet, so this one is just you against the clock. Add friends from the Friends page and invite them to the next one."
                )
                .font(Tide.body).foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(arena.friends.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 {
                            TideDivider()
                        }
                        friendRow(friend)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
        }
    }

    private func friendRow(_ friend: ArenaFriendDTO) -> some View {
        let selected = invited.contains(friend.userId)
        return Button {
            if selected {
                invited.remove(friend.userId)
            } else {
                invited.insert(friend.userId)
            }
        } label: {
            HStack(spacing: Tide.s3) {
                TideInitialAvatar(name: friend.displayName, size: Tide.avatar - Tide.s1)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(friend.displayName)
                        .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    Text("Level \(friend.level)").font(Tide.caption).foregroundStyle(Tide.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.headline)
                    .foregroundStyle(selected ? mood.accent : Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit + Tide.s2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "Double tap to uninvite" : "Double tap to invite")
        .accessibilityIdentifier("arena.challengeFriend")
    }

    // MARK: - Create

    private func create() async {
        guard canCreate else {
            return
        }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        let body = ArenaChallengeCreateDTO(
            title: trimmedTitle, description: nil, metric: metric.rawValue, durationDays: days,
            startsOn: nil, maxParticipants: nil, inviteUserIds: Array(invited)
        )
        do {
            try await arena.createChallenge(body)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
