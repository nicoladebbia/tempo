//
// MarkEatenSheet.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import SwiftUI

/// Bottom sheet presented every time a user taps "Mark Eaten." Combines two
/// novel-for-this-category interactions:
///
/// 1. **Backward-fill timing.** The default time is "just now," but the
///    bar below scrubs the eat-time back up to 4 hours. Most apps pretend
///    the tap == the eat-time; this one acknowledges the gap and gives
///    the user a one-drag fix.
///
/// 2. **Meal feel chip.** A five-option post-meal sensation
///    (light / clean / energising / heavy / sluggish). Stored on
///    `MealFeedback.mealFeel`. Two seconds of input that compounds into
///    a signal the plan generator uses to bias recipes per day-type
///    ("sluggish on training days → drop").
///
/// Either lane saves the meal: tapping a chip commits time + feel,
/// hitting "Save" commits time + no feel. Cancel does nothing.
struct MarkEatenSheet: View {
    let meal: PlannedMeal
    /// Called with `(actualEatTime, mealFeel?, substitute?)` when the user
    /// confirms. The caller is responsible for calling `markMealEaten(at:)`,
    /// persisting any `MealFeedback` row, and zeroing the planned meal's
    /// macros when `substitute` is non-nil.
    let onCommit: (Date, MealFeel?, Substitute?) -> Void

    /// Captured when the user picks the "Ate something else" lane. Empty
    /// strings or nil are filtered out by the caller. Calories is optional
    /// — the planner is told "unknown" means user ate but didn't quantify.
    struct Substitute: Equatable, Sendable {
        let note: String
        let calories: Double?
    }

    @Environment(\.dismiss)
    private var dismiss

    /// Eat time being edited. Bound to the scrubber; `.now` by default.
    @State
    private var eatTime: Date = .now
    @State
    private var selectedFeel: MealFeel?
    /// True when the user expanded the "Ate something else" lane.
    /// Collapses the planned-meal context (feel chips remain — feel
    /// applies to the substitute too).
    @State
    private var ateSomethingElse: Bool = false
    @State
    private var substituteText: String = ""
    @State
    private var substituteCaloriesText: String = ""

    /// `startWithSubstitute: true` opens the sheet straight into the "Ate
    /// something else" lane — used by the meal screen's dedicated
    /// "Ate something else" button so the swap path is one tap, not buried.
    init(
        meal: PlannedMeal,
        startWithSubstitute: Bool = false,
        onCommit: @escaping (Date, MealFeel?, Substitute?) -> Void
    ) {
        self.meal = meal
        self.onCommit = onCommit
        _ateSomethingElse = State(initialValue: startWithSubstitute)
    }

    /// Largest amount of backward fill we allow. 4h covers "I ate
    /// breakfast at 7:30, tapped at 11:30" without giving the user enough
    /// rope to backfill a different day's meal.
    private let maxBackwardSeconds: TimeInterval = 4 * 60 * 60

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    header
                    timeScrubber
                    feelChips
                    substituteSection
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.md)
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.md)
                    .background(Color.tempoBgPrimary)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle(meal.mealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    /// Just-now / X-min-ago label paired with the absolute clock time so
    /// the user reads both signals at a glance. The "MARK EATEN" eyebrow
    /// from the prior iteration was redundant with the nav title and ate
    /// vertical space below the toolbar — dropped.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
            Text(timeAgoLabel)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if secondsAgo >= 60 {
                Text("·")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(Self.clockFormatter.string(from: eatTime))
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Slider scrubs eat-time backward from `.now`. Stops at `now`
    /// (no future eating). The label above ticks live as the user drags.
    private var timeScrubber: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text("WHEN")
                    .font(.tempoCaption2)
                    .fontWeight(.semibold)
                    .tracking(0.4)
                    .foregroundStyle(Color.tempoTextTertiary)
                Spacer()
                Button {
                    eatTime = .now
                    HapticManager.lightImpact()
                } label: {
                    Text("Now")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoSignal)
                }
                .buttonStyle(.plain)
                .disabled(secondsAgo < 30)
            }

            Slider(
                value: Binding(
                    get: { -secondsAgo },
                    set: { value in
                        // value ranges from -maxBackwardSeconds (oldest)
                        // to 0 (now). Clamp and translate back to a Date.
                        let clamped = min(0, max(-maxBackwardSeconds, value))
                        eatTime = Date().addingTimeInterval(clamped)
                    }
                ),
                in: -maxBackwardSeconds ... 0
            )
            .tint(Color.tempoSignal)
            .onChange(of: eatTime) { _, _ in
                HapticManager.selection()
            }

            HStack {
                Text("4 h ago")
                Spacer()
                Text("Now")
            }
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    /// Five chips, evenly spaced. Tapping a chip toggles selection;
    /// tapping the same chip again deselects (so a second tap doesn't
    /// commit accidentally — commits happen via Save).
    private var feelChips: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("HOW DID IT FEEL?")
                .font(.tempoCaption2)
                .fontWeight(.semibold)
                .tracking(0.4)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: 8) {
                ForEach(MealFeel.allCases, id: \.self) { feel in
                    feelChip(feel)
                }
            }
        }
    }

    /// Collapsible "Ate something else" section. Collapsed = a single
    /// toggle row, so it doesn't visually compete with the primary flow.
    /// Expanded = free-text "what did you eat?" + optional kcal field.
    /// Submitting a non-empty note triggers the substitute commit path
    /// in `saveButton.action` — the planned meal's macros are zeroed by
    /// the caller's onCommit handler.
    private var substituteSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    ateSomethingElse.toggle()
                }
                HapticManager.lightImpact()
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: ateSomethingElse ? "checkmark.circle.fill" : "arrow.triangle.swap")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ateSomethingElse ? Color.tempoSignal : Color.tempoTextSecondary)
                    Text("Ate something else")
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.tempoTextTertiary)
                        .rotationEffect(.degrees(ateSomethingElse ? 180 : 0))
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)

            if ateSomethingElse {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHAT DID YOU EAT?")
                            .font(.tempoCaption2)
                            .fontWeight(.semibold)
                            .tracking(0.4)
                            .foregroundStyle(Color.tempoTextTertiary)
                        TextField(
                            "Chicken, rice, beans, olive oil…",
                            text: $substituteText,
                            axis: .vertical
                        )
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(2 ... 4)
                        .padding(TempoSpacing.sm)
                        .background(Color.tempoBgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUGH CALORIES (OPTIONAL)")
                            .font(.tempoCaption2)
                            .fontWeight(.semibold)
                            .tracking(0.4)
                            .foregroundStyle(Color.tempoTextTertiary)
                        TextField("e.g. 650", text: $substituteCaloriesText)
                            .keyboardType(.numberPad)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(TempoSpacing.sm)
                            .background(Color.tempoBgPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                    }
                    Text("Saving with a substitute zeros the planned meal's macros for today. The planner will see that you swapped this dish.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func feelChip(_ feel: MealFeel) -> some View {
        let isSelected = selectedFeel == feel
        return Button {
            selectedFeel = isSelected ? nil : feel
            HapticManager.lightImpact()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: feel.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                Text(feel.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TempoSpacing.sm)
            .background(isSelected ? Color.tempoSignal.opacity(0.20) : Color.tempoSurfaceCard)
            .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.tempoSignal : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feel.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var saveButton: some View {
        Button {
            onCommit(eatTime, selectedFeel, builtSubstitute)
            HapticManager.notification(.success)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(saveLabel)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.tempoCallout)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(Color.tempoTextInverse)
            .background(Color.tempoSignal)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Save-button copy adapts to the lane the user chose. Substitute
    /// wins over feel when both are set — it's the higher-signal action.
    private var saveLabel: String {
        if let sub = builtSubstitute {
            return "Save substitute (\(sub.note.prefix(20))…)"
        }
        if let feel = selectedFeel {
            return "Save with \(feel.displayName.lowercased())"
        }
        return "Save"
    }

    /// Returns a non-nil substitute only when the toggle is on AND the
    /// note has real content. Whitespace-only notes are dropped.
    private var builtSubstitute: Substitute? {
        guard ateSomethingElse else { return nil }
        let trimmed = substituteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cals = Double(substituteCaloriesText.trimmingCharacters(in: .whitespacesAndNewlines))
        return Substitute(note: trimmed, calories: cals)
    }

    // MARK: - Helpers

    private var secondsAgo: TimeInterval {
        max(0, Date().timeIntervalSince(eatTime))
    }

    /// Live "X min ago" label that updates as the slider moves. Reads
    /// straight from `eatTime` so we don't need a `TimelineView` here.
    private var timeAgoLabel: String {
        let minutes = Int(secondsAgo / 60)
        if minutes < 1 {
            return "Just now"
        }
        if minutes < 60 {
            return "\(minutes) min ago"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours) h ago" : "\(hours) h \(remMin) min ago"
    }
}
