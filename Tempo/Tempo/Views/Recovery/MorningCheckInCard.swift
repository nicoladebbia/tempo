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
    @Environment(\.tideMood) private var mood
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Default body-part list covering the lift + soccer groups. Item-agnostic
    /// storage (JSON) means this list can change with zero schema cost.
    private static let bodyParts = ["Quads", "Hamstrings", "Calves", "Glutes", "Lower back", "Shoulders", "Knees"]

    @State private var checkIn: MorningCheckIn?
    @State private var dismissed = false
    @State private var expandedSoreness = false
    /// A check-in that was already logged when the page opened folds to one
    /// line; Edit opens it again. While answering, the card stays open.
    @State private var editing = true
    @State private var explainer: Explainer?

    var body: some View {
        // The task MUST host on an always-present concrete view. A `Group` whose
        // first-realized child is EmptyView() swallows `.task` (no-op on EmptyView),
        // so loadOrCreate() never runs → permanent no-show. (Matches the working
        // sibling RecoveryAIInsightView, which roots its body in a real VStack.)
        VStack(spacing: 0) {
            if !dismissed, let checkIn {
                if checkIn.mood != nil, checkIn.stress != nil, !editing {
                    loggedRow(for: checkIn)
                } else {
                    card(for: checkIn)
                }
            }
        }
        .task { loadOrCreate() }
        .explainerSheet($explainer)
    }

    // MARK: - Logged

    /// Both answers are in: the card folds to what was logged, so the day's
    /// numbers come back above the fold. Edit opens it again.
    private func loggedRow(for checkIn: MorningCheckIn) -> some View {
        Button {
            withAnimation(Tide.snap) { editing = true }
        } label: {
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: "checkmark", tint: TideTone.mint)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Morning check-in").tideLabel(Tide.text3)
                    Text(loggedSummary(checkIn))
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Tide.s2)

                Text("Edit")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Morning check-in logged. \(loggedSummary(checkIn))")
        .accessibilityHint("Opens it to change your answers")
    }

    private func loggedSummary(_ checkIn: MorningCheckIn) -> String {
        let energy = checkIn.mood.map { "Energy \($0)/5" } ?? ""
        let stress = checkIn.stress.map { "Stress \($0)/10" } ?? ""
        return [energy, stress].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Card

    private func card(for checkIn: MorningCheckIn) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack {
                Text("Morning check-in").tideLabel()
                if checkIn.mood != nil, checkIn.stress != nil {
                    TideStatusPill(text: "Logged", tint: TideTone.mint, systemImage: "checkmark")
                        .transition(.opacity)
                }
                Button {
                    explainer = .morningCheckIn
                } label: {
                    Image(systemName: "info.circle")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About the morning check-in")
                .accessibilityIdentifier("explain.recovery-check-in")
                // The info target is 44pt; the row stays slim.
                .padding(.vertical, -Tide.s3)
                Spacer(minLength: Tide.s2)
                Button {
                    withAnimation(Tide.snap) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss check-in")
                // The close target is 44pt; the row stays slim.
                .padding(.vertical, -Tide.s3)
                .padding(.trailing, -Tide.s3)
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
                withAnimation(Tide.snap) { expandedSoreness.toggle() }
            } label: {
                HStack {
                    Text(sorenessSummary(checkIn))
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Tide.s2)
                    Image(systemName: expandedSoreness ? "chevron.up" : "chevron.down")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(expandedSoreness ? "Hides body parts" : "Shows body parts")

            if expandedSoreness {
                VStack(spacing: Tide.s2) {
                    ForEach(Self.bodyParts, id: \.self) { part in
                        sorenessRow(part: part, checkIn: checkIn)
                    }
                }
                .transition(.opacity)
            }
        }
        .tideCard()
    }

    // MARK: - Rows

    @ViewBuilder
    private func scaleRow(title: String, value: Int?, range: ClosedRange<Int>, onSet: @escaping (Int) -> Void) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Tide.s1),
            // Five to a row at most, so every button is a full 44 pt target.
            count: min(range.count, 5)
        )
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Spacer(minLength: Tide.s2)
                // The chosen value, read out as it changes.
                Text(value.map { "\($0) / \(range.upperBound)" } ?? "Tap to set")
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                    .foregroundStyle(value == nil ? Tide.text3 : mood.accent)
                    .contentTransition(.numericText())
                    .animation(Tide.snap, value: value)
                    .accessibilityHidden(true)
            }
            LazyVGrid(columns: columns, spacing: Tide.s1) {
                ForEach(Array(range), id: \.self) { i in
                    let selected = value == i
                    Button {
                        onSet(i)
                    } label: {
                        Text("\(i)")
                            .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                            .foregroundStyle(selected ? Tide.ink : Tide.text2)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .background(
                                selected ? mood.accent : Tide.fill,
                                in: .rect(cornerRadius: Tide.controlRadius)
                            )
                            .contentShape(.rect(cornerRadius: Tide.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(i)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(Tide.snap, value: value)
            .sensoryFeedback(.selection, trigger: value)
        }
    }

    @ViewBuilder
    private func sorenessRow(part: String, checkIn: MorningCheckIn) -> some View {
        let current = checkIn.soreness[part]
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        layout {
            Text(part)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(width: typeSize.isAccessibilitySize ? nil : Tide.s10 * 2.25, alignment: .leading)
            // 1–10 stepper-lite: tap level. 8+ = pain flag (red).
            HStack(spacing: Tide.hair) {
                ForEach(1 ... 10, id: \.self) { level in
                    Button {
                        var s = checkIn.soreness
                        if current == level {
                            s[part] = nil
                        } else {
                            s[part] = level
                        }
                        checkIn.soreness = s
                        persist()
                    } label: {
                        RoundedRectangle(cornerRadius: Tide.hair, style: .continuous)
                            .fill(fillFor(level: level, current: current))
                            .frame(height: Tide.s4)
                            .frame(minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(part) soreness \(level)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func fillFor(level: Int, current: Int?) -> Color {
        guard let current, level <= current else {
            return Tide.fill
        }
        return current >= 8 ? Tide.danger : TideTone.amber
    }

    private func sorenessSummary(_ checkIn: MorningCheckIn) -> String {
        let sore = checkIn.soreness
        if sore.isEmpty {
            return "Any soreness? Tap to add"
        }
        let flags = checkIn.snapshot.painFlags
        if !flags.isEmpty {
            return "Sore: \(flags.joined(separator: ", ")) (pain)"
        }
        return "Soreness logged (\(sore.count))"
    }

    // MARK: - Persistence

    private func loadOrCreate() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return
        }
        let descriptor = FetchDescriptor<MorningCheckIn>(
            predicate: #Predicate<MorningCheckIn> { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            checkIn = existing
            editing = existing.mood == nil || existing.stress == nil
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
