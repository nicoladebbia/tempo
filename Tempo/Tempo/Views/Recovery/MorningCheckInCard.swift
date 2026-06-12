//
// MorningCheckInCard.swift
// Tempo
//
// The 5-second subjective morning check-in (docs/INTELLIGENT_TRAINING_SYSTEM.md §4.2, Decision #8).
// A dismissible Today-screen card that writes a same-day MorningCheckIn. Feeds
// the ReadinessPicture (one-way DOWNGRADE only, §15.5 — it can soften the
// prescription, never upgrade past the floor).
//
// Soreness uses the 1–10 scale by contract: MorningCheckInSnapshot.painFlags
// fires at >= 8, so a body part rated 8+ routes load away from it (§15.5).
//

import SwiftData
import SwiftUI

struct MorningCheckInCard: View {
    @Environment(\.modelContext) private var modelContext

    /// Default body-part list covering the lift + soccer groups. Item-agnostic
    /// storage (JSON) means this list can change with zero schema cost.
    private static let bodyParts = ["Quads", "Hamstrings", "Calves", "Glutes", "Lower back", "Shoulders", "Knees"]

    @State private var checkIn: MorningCheckIn?
    @State private var dismissed = false
    @State private var expandedSoreness = false

    var body: some View {
        // The task MUST host on an always-present concrete view. A `Group` whose
        // first-realized child is EmptyView() swallows `.task` (no-op on EmptyView),
        // so loadOrCreate() never runs → permanent no-show. (Matches the working
        // sibling RecoveryAIInsightView, which roots its body in a real VStack.)
        VStack(spacing: 0) {
            if !dismissed, let checkIn {
                card(for: checkIn)
            }
        }
        .task { loadOrCreate() }
    }

    // MARK: - Card

    @ViewBuilder
    private func card(for checkIn: MorningCheckIn) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("MORNING CHECK-IN")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                Spacer()
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .accessibilityLabel("Dismiss check-in")
            }

            // Mood 1–5
            scaleRow(title: "Energy / mood", value: checkIn.mood, range: 1 ... 5) { v in
                checkIn.mood = v
                persist()
            }

            // Stress 1–10
            scaleRow(title: "Stress", value: checkIn.stress, range: 1 ... 10) { v in
                checkIn.stress = v
                persist()
            }

            // Soreness (expandable — keeps the card 5-second by default)
            Button {
                withAnimation { expandedSoreness.toggle() }
            } label: {
                HStack {
                    Text(sorenessSummary(checkIn))
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                    Image(systemName: expandedSoreness ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .buttonStyle(.plain)

            if expandedSoreness {
                ForEach(Self.bodyParts, id: \.self) { part in
                    sorenessRow(part: part, checkIn: checkIn)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Rows

    @ViewBuilder
    private func scaleRow(title: String, value: Int?, range: ClosedRange<Int>, onSet: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(title)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            HStack(spacing: TempoSpacing.xs) {
                ForEach(range, id: \.self) { i in
                    Button {
                        onSet(i)
                    } label: {
                        Text("\(i)")
                            .font(.tempoCaption1)
                            .frame(width: 28, height: 28)
                            .background(value == i ? Color.tempoRecoveryGreen : Color.tempoSurfaceCard)
                            .foregroundStyle(value == i ? Color.tempoBgPrimary : Color.tempoTextSecondary)
                            .overlay(
                                Circle().stroke(Color.tempoTextTertiary.opacity(0.3), lineWidth: value == i ? 0 : 1)
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func sorenessRow(part: String, checkIn: MorningCheckIn) -> some View {
        let current = checkIn.soreness[part]
        HStack {
            Text(part)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 90, alignment: .leading)
            // 1–10 stepper-lite: tap level. 8+ = pain flag (red).
            HStack(spacing: 2) {
                ForEach(1 ... 10, id: \.self) { level in
                    Button {
                        var s = checkIn.soreness
                        if current == level { s[part] = nil } else { s[part] = level }
                        checkIn.soreness = s
                        persist()
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillFor(level: level, current: current))
                            .frame(height: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fillFor(level: Int, current: Int?) -> Color {
        guard let current, level <= current else { return Color.tempoTextTertiary.opacity(0.15) }
        return current >= 8 ? Color.tempoRecoveryRed : Color.tempoRecoveryYellow
    }

    private func sorenessSummary(_ checkIn: MorningCheckIn) -> String {
        let sore = checkIn.soreness
        if sore.isEmpty { return "Any soreness? Tap to add" }
        let flags = checkIn.snapshot.painFlags
        if !flags.isEmpty { return "Sore: \(flags.joined(separator: ", ")) (pain)" }
        return "Soreness logged (\(sore.count))"
    }

    // MARK: - Persistence

    private func loadOrCreate() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return }
        let descriptor = FetchDescriptor<MorningCheckIn>(
            predicate: #Predicate<MorningCheckIn> { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            checkIn = existing
        } else {
            let fresh = MorningCheckIn(date: today)
            modelContext.insert(fresh)
            checkIn = fresh
        }
    }

    private func persist() {
        checkIn?.capturedAt = Date()
        try? modelContext.save()
    }
}
