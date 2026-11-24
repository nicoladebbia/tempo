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
    /// Called with `(actualEatTime, mealFeel?, satiety?, substitute?)` when the
    /// user confirms. The caller is responsible for calling `markMealEaten(at:)`,
    /// persisting any `MealFeedback` row, and — when `substitute` is non-nil —
    /// parsing the note through the NL pipeline to replace the planned meal's
    /// foods + macros with what was actually eaten.
    let onCommit: (Date, MealFeel?, MealSatiety?, Substitute?) -> Void

    /// Captured when the user picks the "Ate something else" lane. Empty
    /// strings are filtered out by the caller. Carries only the raw note —
    /// the caller parses it through the NL pipeline downstream to compute
    /// real macros from the food database.
    struct Substitute: Equatable, Sendable {
        let note: String
        /// True when the user confirms they ate this from their own pantry
        /// (so the parsed foods get decremented). Default false → "ate out" /
        /// unknown, pantry untouched. Only an explicit tap decrements stock.
        let usedPantry: Bool
    }

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Eat time being edited. Bound to the scrubber; `.now` by default.
    @State
    private var eatTime: Date = .now
    @State
    private var selectedFeel: MealFeel?
    @State
    private var selectedSatiety: MealSatiety?
    /// True when the user expanded the "Ate something else" lane.
    /// Collapses the planned-meal context (feel chips remain — feel
    /// applies to the substitute too).
    @State
    private var ateSomethingElse: Bool = false
    @State
    private var substituteText: String = ""
    /// "Did you use your pantry, or eat out?" — when true, the parsed foods
    /// are decremented from the pantry. Default false (ate out / unknown).
    @State
    private var usedPantry: Bool = false

    /// `startWithSubstitute: true` opens the sheet straight into the "Ate
    /// something else" lane — used by the meal screen's dedicated
    /// "Ate something else" button so the swap path is one tap, not buried.
    init(
        meal: PlannedMeal,
        startWithSubstitute: Bool = false,
        onCommit: @escaping (Date, MealFeel?, MealSatiety?, Substitute?) -> Void
    ) {
        self.meal = meal
        self.onCommit = onCommit
        _ateSomethingElse = State(initialValue: startWithSubstitute)
    }

    /// Largest amount of backward fill we allow. 4h was too tight — a meal
    /// eaten at 14:30 and logged at 19:00 (4.5h ago) fell off the left edge
    /// and couldn't be set at all. 10h covers "ate this morning, logging this
    /// evening" — wide enough for a real same-day delay without giving enough
    /// rope to backfill a different day's meal.
    private let maxBackwardSeconds: TimeInterval = 10 * 60 * 60

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    // When the user explicitly chose "Ate something else", the
                    // "what did you eat" field is the point: it sits right under
                    // the time, and the time has no scrubber (the eat time
                    // defaults to now), so the field is on screen at once.
                    whenHero
                    if ateSomethingElse {
                        substituteSection
                        feelAndFullness
                    } else {
                        feelAndFullness
                        substituteSection
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s3)
                .padding(.bottom, Tide.s4)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .fuelBottomBar { saveButton }
            .tidePage()
            // A sheet is its own page, even when it comes up from inside one.
            .environment(\.tideInsidePage, false)
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

    /// The meal, and when it was eaten: "Just now" or "X min ago" paired with
    /// the clock time, in the big numerals. The scrubber lives in the same
    /// card (unless the meal was something else), so dragging moves the number.
    private var whenHero: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: FuelMealStyle.icon(forName: meal.mealName))
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(meal.mealName)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                    if meal.totalCalories > 0 {
                        Text("\(Int(meal.totalCalories.rounded())) kcal planned")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }
                Spacer(minLength: Tide.s2)
                if !ateSomethingElse {
                    Button {
                        eatTime = .now
                        HapticManager.lightImpact()
                    } label: {
                        Text("Now")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                            .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(secondsAgo < 30)
                    .opacity(secondsAgo < 30 ? 0.4 : 1)
                }
            }
            header
            if !ateSomethingElse {
                timeScrubber
            }
        }
        .tideCard()
    }

    /// Two readings of the same moment: how long ago, and the clock.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(timeAgoLabel, size: Tide.numeralM)
                if secondsAgo >= 60 {
                    Text("·")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                    TideNumber(Self.clockFormatter.string(from: eatTime), size: Tide.numeralM, weight: .medium, color: Tide.text2)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Tide.hair) {
                TideNumber(timeAgoLabel, size: Tide.numeralM)
                if secondsAgo >= 60 {
                    TideNumber(Self.clockFormatter.string(from: eatTime), size: Tide.numeralS, weight: .medium, color: Tide.text2)
                }
            }
        }
        .animation(Tide.snap, value: timeAgoLabel)
        .accessibilityElement(children: .combine)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Slider scrubs eat-time backward from `.now`. Stops at `now`
    /// (no future eating). The numbers above tick live as the user drags.
    private var timeScrubber: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
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
            .tint(mood.accent)
            .onChange(of: eatTime) { _, _ in
                HapticManager.selection()
            }
            .accessibilityLabel("Eat time")
            .accessibilityValue(timeAgoLabel)

            HStack {
                Text("\(Int(maxBackwardSeconds / 3600)) h ago")
                Spacer()
                Text("Now")
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
            .accessibilityHidden(true)
        }
    }

    /// How the meal felt and how full you are: one card, two rows of chips.
    private var feelAndFullness: some View {
        VStack(alignment: .leading, spacing: Tide.s5) {
            feelChips
            Divider().overlay(Tide.hairline)
            satietyChips
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    /// Five chips, evenly spaced. Tapping a chip toggles selection;
    /// tapping the same chip again deselects (so a second tap doesn't
    /// commit accidentally — commits happen via Save).
    private var feelChips: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("How did it feel?").tideLabel()

            chipRow {
                ForEach(MealFeel.allCases, id: \.self) { feel in
                    feelChip(feel)
                }
            }
        }
    }

    /// Collapsible "Ate something else" section. Collapsed = a single
    /// toggle row, so it doesn't visually compete with the primary flow.
    /// Expanded = free-text "what did you eat?" field. Submitting a
    /// non-empty note triggers the substitute commit path in
    /// `saveButton.action` — the caller parses the note through the NL
    /// pipeline to compute real macros and swap the displayed foods.
    private var substituteSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Button {
                withAnimation(Tide.snap) {
                    ateSomethingElse.toggle()
                }
                HapticManager.lightImpact()
            } label: {
                HStack(spacing: Tide.s3) {
                    Image(systemName: ateSomethingElse ? "checkmark.circle.fill" : "arrow.triangle.swap")
                        .font(Tide.headline)
                        .foregroundStyle(ateSomethingElse ? mood.accent : Tide.text2)
                        // A minimum, not a fixed width: the symbol grows with the text.
                        .frame(minWidth: Tide.icon, alignment: .leading)
                        .accessibilityHidden(true)
                    Text("Ate something else")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Tide.s2)
                    Image(systemName: "chevron.down")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .rotationEffect(.degrees(ateSomethingElse ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(ateSomethingElse ? "Expanded" : "Collapsed")

            if ateSomethingElse {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("What did you eat?").tideLabel()
                        TextField(
                            "Chicken, rice, beans, olive oil…",
                            text: $substituteText,
                            axis: .vertical
                        )
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2 ... 4)
                        .padding(.vertical, Tide.s2)
                        .fuelField()
                    }
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("Where from?").tideLabel()
                        originLayout {
                            originChoice("Ate out", icon: "takeoutbag.and.cup.and.straw.fill", pantry: false)
                            originChoice("Used my pantry", icon: "refrigerator.fill", pantry: true)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Where from")
                    }
                    Text(usedPantry
                        ? "We'll take what you ate off your pantry stock and log the real macros for today."
                        : "We'll log the real macros for today. Your pantry stays as-is (you ate out / used something untracked).")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    /// Side by side; stacked at accessibility sizes so neither answer is squeezed.
    private var originLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
    }

    /// One of the two answers to "where from": soft fill, accent ring when picked.
    private func originChoice(_ title: String, icon: String, pantry: Bool) -> some View {
        let selected = usedPantry == pantry
        return Button {
            HapticManager.selection()
            usedPantry = pantry
        } label: {
            Label(title, systemImage: icon)
                .font(Tide.bodyStrong)
                .lineLimit(2)
                .minimumScaleFactor(Tide.labelShrink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Tide.s2)
                .fuelChoice(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Five chips side by side; stacked as full-width rows at accessibility
    /// text sizes so no name is squeezed or cut.
    private func chipRow(@ViewBuilder _ content: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s2))
        return layout { content() }
    }

    private func choiceChip(symbol: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(HStackLayout(spacing: Tide.s3))
            : AnyLayout(VStackLayout(spacing: Tide.s1))
        return Button(action: action) {
            layout {
                Image(systemName: symbol)
                    .font(Tide.headline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.label)
                    .lineLimit(stacked ? 2 : 1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .multilineTextAlignment(stacked ? .leading : .center)
                if stacked {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.s1)
            .fuelChoice(selected: isSelected, minHeight: Tide.hit + Tide.s3)
            .contentShape(.rect(cornerRadius: Tide.controlRadius))
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func feelChip(_ feel: MealFeel) -> some View {
        let isSelected = selectedFeel == feel
        return choiceChip(symbol: feel.symbolName, title: feel.displayName, isSelected: isSelected) {
            selectedFeel = isSelected ? nil : feel
            HapticManager.lightImpact()
        }
    }

    /// Satiety signal — mainly used to scale a slot's portion DOWN over time
    /// when the user repeatedly says "too much" / "didn't finish."
    private var satietyChips: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("How full are you?").tideLabel()

            chipRow {
                ForEach(MealSatiety.allCases, id: \.self) { satiety in
                    satietyChip(satiety)
                }
            }
        }
    }

    private func satietyChip(_ satiety: MealSatiety) -> some View {
        let isSelected = selectedSatiety == satiety
        return choiceChip(symbol: satiety.symbolName, title: satiety.displayName, isSelected: isSelected) {
            selectedSatiety = isSelected ? nil : satiety
            HapticManager.lightImpact()
        }
    }

    private var saveButton: some View {
        Button {
            onCommit(eatTime, selectedFeel, selectedSatiety, builtSubstitute)
            HapticManager.notification(.success)
            dismiss()
        } label: {
            HStack(spacing: Tide.s2) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text(saveLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.tidePrimary)
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
        guard ateSomethingElse else {
            return nil
        }
        let trimmed = substituteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Substitute(note: trimmed, usedPantry: usedPantry)
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
