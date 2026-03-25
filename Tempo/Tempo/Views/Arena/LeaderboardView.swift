import SwiftUI

// MARK: - Leaderboard View
// Per MODULE_ARENA.md Section 7 — Full weekly leaderboard.
// Per WIREFRAMES.md Screen 37 — Period tabs, podium, ranked list.

struct LeaderboardView: View {

    @Environment(ServiceContainer.self) private var services

    @State private var selectedPeriod: LeaderboardPeriod = .weekly
    @State private var rankings: [LeaderboardEntry] = []
    @State private var myRank: Int = 0
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Period selector
            periodPicker

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rankings.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if rankings.count >= 3 {
                            podiumView
                        }
                        rankedList
                    }
                }
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("LEADERBOARD")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadMockData() }
    }

    // MARK: - Period Picker
    // Per WIREFRAMES.md Screen 37 — 36pt segmented control.

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                Text(period.label).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Podium (Top 3)
    // Per WIREFRAMES.md Screen 37 — 180pt total, pillar heights 120/100/85.

    private var podiumView: some View {
        HStack(alignment: .bottom, spacing: TempoSpacing.lg) {
            // #2
            if rankings.count > 1 {
                podiumEntry(rankings[1], pillarHeight: 100)
            }
            // #1
            if !rankings.isEmpty {
                podiumEntry(rankings[0], pillarHeight: 120)
            }
            // #3
            if rankings.count > 2 {
                podiumEntry(rankings[2], pillarHeight: 85)
            }
        }
        .frame(height: 180)
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.top, TempoSpacing.lg)
    }

    private func podiumEntry(_ entry: LeaderboardEntry, pillarHeight: CGFloat) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            // Avatar
            ZStack {
                Circle()
                    .fill(entry.rank == 1 ? Color.tempoAmber.opacity(0.2) : Color.tempoSignal.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(String(entry.displayName.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(entry.rank == 1 ? Color.tempoAmber : Color.tempoSignal)
            }

            Text(entry.isMe ? "You" : entry.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.isMe ? Color.tempoSignal : Color.tempoTextPrimary)
                .lineLimit(1)

            Text("\(entry.xp) XP")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.tempoTextSecondary)

            // Pillar
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.rank == 1 ? Color.tempoAmber.opacity(0.3) :
                      entry.rank == 2 ? Color.tempoSteel.opacity(0.3) :
                      Color.tempoAmber.opacity(0.15))
                .frame(height: pillarHeight)
                .overlay(alignment: .top) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextPrimary)
                        .padding(.top, TempoSpacing.sm)
                }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ranked List (4+)
    // Per WIREFRAMES.md Screen 37 — 56pt rows, movement arrows.

    private var rankedList: some View {
        LazyVStack(spacing: 0) {
            ForEach(rankings.dropFirst(3)) { entry in
                HStack(spacing: TempoSpacing.sm) {
                    // Rank
                    Text("#\(entry.rank)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(width: 36, alignment: .leading)

                    // Avatar
                    Circle()
                        .fill(Color.tempoSignal.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(entry.displayName.prefix(1)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.tempoSignal)
                        )

                    // Name
                    Text(entry.isMe ? "You" : entry.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(entry.isMe ? Color.tempoSignal : Color.tempoTextPrimary)

                    Spacer()

                    // XP
                    Text("\(entry.xp) XP")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color.tempoTextSecondary)

                    // Level badge
                    Text("Lv\(entry.level)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.tempoSignal.opacity(0.1))
                        .clipShape(Capsule())
                }
                .frame(height: 56)
                .padding(.horizontal, TempoSpacing.lg)
                .background(
                    entry.isMe ?
                        Color.tempoSignal.opacity(0.1) : Color.clear
                )
                .overlay(alignment: .leading) {
                    if entry.isMe {
                        Rectangle()
                            .fill(Color.tempoSignal)
                            .frame(width: 3)
                    }
                }

                Divider()
                    .background(Color.tempoDivider)
                    .padding(.leading, TempoSpacing.lg + 36 + TempoSpacing.sm)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("It's lonely at the top...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
            Text("but it doesn't have to be. Add friends to see who's grinding harder this week.")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, TempoSpacing.xxl)
    }

    // MARK: - Mock Data (until backend sync is wired)

    private func loadMockData() {
        // Placeholder data — will be replaced with real API calls
        isLoading = false
    }
}

// MARK: - Leaderboard Period

enum LeaderboardPeriod: String, CaseIterable {
    case weekly, monthly, alltime

    var label: String {
        switch self {
        case .weekly: return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .alltime: return "ALL-TIME"
        }
    }
}
