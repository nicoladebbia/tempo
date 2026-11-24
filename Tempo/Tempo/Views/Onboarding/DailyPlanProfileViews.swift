//
// DailyPlanProfileViews.swift
// Tempo
//
// Six onboarding steps that capture the daily-plan profile per
// docs/INTELLIGENCE_REMEDIATION_PLAN.md §8. Each step is intentionally small —
// the alternative (one mega-form) caused drop-off in earlier prototypes.
//
// Steps: dailyRhythm → classSchedule → eatingWindow → studyPreferences →
//        trainingPreferences → weekendMode.
//
// Every step is drawn for its question: times are big figures with a minus and
// a plus, the day as a bar, a session as a ring, and each choice has a symbol.
//

import SwiftUI

// MARK: - DailyRhythmView

struct DailyRhythmView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.tideMood) private var mood

    var body: some View {
        OnboardingScaffold(
            title: "YOUR DAILY\nRHYTHM.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
            RhythmSummary(wakeMinutes: viewModel.wakeTimeMinutes, sleepHours: viewModel.sleepTargetHours)

            OnboardingTimeControl(title: "Wake time", systemImage: "sunrise.fill", minutes: $viewModel.wakeTimeMinutes)

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Sleep target: \(OnboardingFormat.hours(viewModel.sleepTargetHours))")
                VStack(spacing: Tide.s2) {
                    TideNumber(
                        OnboardingFormat.hours(viewModel.sleepTargetHours),
                        size: Tide.numeralM,
                        relativeTo: .title
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.numericText())
                    .animation(Tide.snap, value: viewModel.sleepTargetHours)
                    .accessibilityHidden(true)
                    Slider(value: $viewModel.sleepTargetHours, in: 6.0 ... 10.0, step: 0.25)
                        .tint(mood.accent)
                        .frame(minHeight: Tide.hit)
                        .accessibilityLabel("Sleep target")
                        .accessibilityValue(OnboardingFormat.hours(viewModel.sleepTargetHours))
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .sensoryFeedback(.selection, trigger: viewModel.sleepTargetHours)
            }

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("When are you sharpest?")
                VStack(spacing: Tide.s2) {
                    ForEach(Chronotype.allCases, id: \.self) { option in
                        OnboardingOptionRow(
                            title: option.label,
                            systemImage: Self.symbol(for: option),
                            isSelected: viewModel.chronotype == option
                        ) {
                            viewModel.chronotype = option
                        }
                    }
                }
            }
        }
    }

    private static func symbol(for chronotype: Chronotype) -> String {
        switch chronotype {
        case .definitelyMorning: "sunrise.fill"
        case .moderatelyMorning: "sun.max.fill"
        case .neutral: "circle.lefthalf.filled"
        case .moderatelyEvening: "sunset.fill"
        case .definitelyEvening: "moon.stars.fill"
        }
    }
}

// MARK: - ClassScheduleView

struct ClassScheduleView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.tideMood) private var mood
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: OnboardingClassBlock?
    @State private var showAdd = false

    var body: some View {
        OnboardingScaffold(
            title: "CLASS\nSCHEDULE.",
            subtitle: "Tempo schedules study + training around your classes. Add the ones that repeat weekly.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() },
            skipTitle: "Skip — I'll add classes later",
            skipAction: { viewModel.skip() }
        ) {
            termWindow

            if viewModel.classBlocks.isEmpty {
                HStack(spacing: Tide.s3) {
                    TideIconTile(systemName: "books.vertical.fill", tint: Tide.text3, size: Tide.tile + Tide.s1)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Text("No classes added yet.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            } else {
                GlassEffectContainer(spacing: Tide.s2) {
                    VStack(spacing: Tide.s2) {
                        ForEach(viewModel.classBlocks) { block in
                            classRow(block)
                        }
                    }
                }
            }

            Button {
                showAdd = true
            } label: {
                Label("Add class", systemImage: "plus")
            }
            .buttonStyle(.tideGlass)
        }
        .animation(Tide.snap, value: viewModel.classBlocks.count)
        .sheet(isPresented: $showAdd) {
            ClassBlockEditor(
                existing: nil,
                onSave: { newBlocks in
                    viewModel.classBlocks.append(contentsOf: newBlocks)
                    showAdd = false
                },
                onCancel: { showAdd = false }
            )
            .environment(\.tideInsidePage, false)
        }
        .sheet(item: $editing) { block in
            ClassBlockEditor(
                existing: block,
                onSave: { updatedBlocks in
                    // Replace the edited block in place; if the user picked
                    // extra days, the additional blocks follow it.
                    if let idx = viewModel.classBlocks.firstIndex(where: { $0.id == block.id }) {
                        viewModel.classBlocks.remove(at: idx)
                        viewModel.classBlocks.insert(contentsOf: updatedBlocks, at: idx)
                    } else {
                        viewModel.classBlocks.append(contentsOf: updatedBlocks)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
            .environment(\.tideInsidePage, false)
        }
    }

    private var termWindow: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            OnboardingSectionLabel("Term window (optional)")
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            layout {
                dateTile(
                    "Starts",
                    selection: Binding(
                        get: { viewModel.termStartDate ?? Date() },
                        set: { viewModel.termStartDate = $0 }
                    )
                )
                dateTile(
                    "Ends",
                    selection: Binding(
                        get: { viewModel.termEndDate ?? Date().addingTimeInterval(90 * 86400) },
                        set: { viewModel.termEndDate = $0 }
                    )
                )
            }
        }
    }

    /// A date on a card: its label above the compact picker.
    private func dateTile(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(title).tideLabel()
                .accessibilityHidden(true)
            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .frame(minHeight: Tide.hit, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func classRow(_ block: OnboardingClassBlock) -> some View {
        HStack(spacing: 0) {
            Button {
                editing = block
            } label: {
                HStack(spacing: Tide.s3) {
                    // The weekday as a small badge: the schedule reads down the left edge.
                    Text(weekdayLabel(block.weekday).uppercased())
                        .font(Tide.label)
                        .foregroundStyle(mood.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .frame(width: Tide.tile + Tide.s1, height: Tide.tile + Tide.s1)
                        .background(mood.accent.opacity(0.16), in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(block.courseCode)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(weekdayLabel(block.weekday)) · \(formatTime(block.startMinuteOfDay))–\(formatTime(block.endMinuteOfDay))")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s3, alignment: .leading)
                .padding(.leading, Tide.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                viewModel.classBlocks.removeAll { $0.id == block.id }
            } label: {
                Image(systemName: "trash")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.danger)
                    .frame(width: Tide.hit + Tide.s2, height: Tide.hit + Tide.s3)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(block.courseCode)")
        }
        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.tileRadius))
    }
}

// MARK: - ClassBlockEditor

private struct ClassBlockEditor: View {
    let existing: OnboardingClassBlock?
    /// Returns one block per selected weekday (same course + time). In add
    /// mode all are appended; in edit mode they replace the edited block.
    let onSave: ([OnboardingClassBlock]) -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    // A class commonly recurs on several weekdays at the same time
    // (e.g. Mon/Wed/Fri 09:00–10:30). Multi-select the days; each becomes
    // its own ClassBlock so the scheduler can treat them per-day.
    @State private var weekdays: Set<Int> = [2] // Monday default
    @State private var startMinutes: Int = 9 * 60
    @State private var endMinutes: Int = 10 * 60 + 30
    @State private var courseCode: String = ""
    @State private var courseName: String = ""
    @State private var location: String = ""

    private var canSave: Bool {
        !courseCode.trimmingCharacters(in: .whitespaces).isEmpty
            && endMinutes > startMinutes
            && !weekdays.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s6) {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        OnboardingSectionLabel("Course")
                        field("Course code (e.g. STAT 101)", text: $courseCode)
                            .textInputAutocapitalization(.characters)
                        field("Full name (optional)", text: $courseName)
                        field("Location (optional)", text: $location)
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        OnboardingSectionLabel("Days")
                        // Tap each weekday the class meets (e.g. Mon/Wed/Fri).
                        // Equal-width cells always fit the row; at large text
                        // sizes the days wrap instead.
                        if typeSize.isAccessibilitySize {
                            FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                                ForEach(1 ... 7, id: \.self) { d in
                                    dayChip(d, expands: false)
                                }
                            }
                        } else {
                            HStack(spacing: Tide.s1) {
                                ForEach(1 ... 7, id: \.self) { d in
                                    dayChip(d, expands: true)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        OnboardingSectionLabel("Time")
                        VStack(spacing: Tide.s2) {
                            OnboardingTimeControl(title: "Starts", systemImage: "clock.fill", minutes: $startMinutes)
                            OnboardingTimeControl(title: "Ends", systemImage: "clock.badge.checkmark", minutes: $endMinutes)
                        }
                        if endMinutes <= startMinutes {
                            Label("Ends after it starts", systemImage: "exclamationmark.circle.fill")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.danger)
                        }
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .tidePage()
            .navigationTitle(existing == nil ? "Add class" : "Edit class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let code = courseCode.trimmingCharacters(in: .whitespaces)
                        // One block per selected weekday. The first reuses
                        // the edited block's id (so edit replaces in place);
                        // any extra days get fresh ids.
                        let sortedDays = weekdays.sorted()
                        let blocks = sortedDays.enumerated().map { idx, day in
                            OnboardingClassBlock(
                                id: idx == 0 ? (existing?.id ?? UUID()) : UUID(),
                                weekday: day,
                                startMinuteOfDay: startMinutes,
                                endMinuteOfDay: endMinutes,
                                courseCode: code,
                                courseName: courseName.isEmpty ? nil : courseName,
                                location: location.isEmpty ? nil : location
                            )
                        }
                        onSave(blocks)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let e = existing {
                weekdays = [e.weekday]
                startMinutes = e.startMinuteOfDay
                endMinutes = e.endMinuteOfDay
                courseCode = e.courseCode
                courseName = e.courseName ?? ""
                location = e.location ?? ""
            }
        }
    }

    private func dayChip(_ day: Int, expands: Bool) -> some View {
        OnboardingChip(title: weekdayShort(day), isSelected: weekdays.contains(day), expands: expands) {
            if weekdays.contains(day) {
                weekdays.remove(day)
            } else {
                weekdays.insert(day)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Tide.text3))
            .font(Tide.headline.weight(.regular))
            .foregroundStyle(Tide.text)
            .autocorrectionDisabled()
            .tideFieldSurface()
    }
}

// MARK: - EatingWindowView

struct EatingWindowView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            title: "EATING\nWINDOW.",
            subtitle: "Tempo plans meals inside this window. Pick a preset or set your own.",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.eatingWindowEndMinutes > viewModel.eatingWindowStartMinutes,
            primaryAction: { viewModel.advance() }
        ) {
            VStack(spacing: Tide.s2) {
                ForEach(EatingWindowPreset.allCases, id: \.self) { preset in
                    OnboardingOptionRow(
                        title: preset.label,
                        systemImage: Self.symbol(for: preset),
                        isSelected: viewModel.eatingWindowPreset == preset
                    ) {
                        viewModel.eatingWindowPreset = preset
                        if let window = preset.defaultWindow {
                            viewModel.eatingWindowStartMinutes = window.start
                            viewModel.eatingWindowEndMinutes = window.end
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Window")
                OnboardingTimeControl(title: "First meal", systemImage: "sunrise.fill", minutes: $viewModel.eatingWindowStartMinutes)
                // The old screen read "first meal to last meal"; keep the connector.
                Text("to")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                OnboardingTimeControl(title: "Last meal", systemImage: "moon.stars.fill", minutes: $viewModel.eatingWindowEndMinutes)
                EatingWindowBar(start: viewModel.eatingWindowStartMinutes, end: viewModel.eatingWindowEndMinutes)
                    .padding(.top, Tide.s1)
            }

            VStack(spacing: 0) {
                Toggle("I skip breakfast", isOn: $viewModel.breakfastSkipped)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .toggleStyle(.tempo)
                Divider().overlay(Tide.hairline)
                Toggle("Post-workout meal is mandatory", isOn: $viewModel.postWorkoutMandatory)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .toggleStyle(.tempo)
            }
            .onboardingCard()
        }
    }

    private static func symbol(for preset: EatingWindowPreset) -> String {
        switch preset {
        case .sixteenEight: "hourglass"
        case .fourteenTen: "timer"
        case .twelveTwelve: "fork.knife"
        case .custom: "slider.horizontal.3"
        }
    }
}

// MARK: - StudyPreferencesView

struct StudyPreferencesView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.tideMood) private var mood
    @ScaledMetric(relativeTo: .title)
    private var ringSize: CGFloat = Tide.dialSheet - Tide.s4

    private let presets: [Int] = [25, 50, 90]
    private let longest = 120.0

    var body: some View {
        OnboardingScaffold(
            title: "STUDY\nSESSIONS.",
            subtitle: "How long do you focus before a break?",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
            // The session as a ring: the longer the block, the fuller the circle.
            ZStack {
                TideRing(
                    progress: Double(viewModel.studySessionLengthMinutes) / longest,
                    color: mood.accent,
                    lineWidth: Tide.s2
                )
                TideNumber(
                    "\(viewModel.studySessionLengthMinutes)",
                    unit: "min",
                    size: Tide.numeralM,
                    relativeTo: .title
                )
                .contentTransition(.numericText())
                .padding(.horizontal, Tide.s4)
            }
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity)
            .animation(Tide.snap, value: viewModel.studySessionLengthMinutes)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session length")
            .accessibilityValue("\(viewModel.studySessionLengthMinutes) minutes")

            HStack(spacing: Tide.s2) {
                ForEach(presets, id: \.self) { p in
                    OnboardingChip(
                        title: "\(p) min",
                        isSelected: viewModel.studySessionLengthMinutes == p,
                        expands: true
                    ) {
                        viewModel.studySessionLengthMinutes = p
                    }
                }
            }

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Custom: \(viewModel.studySessionLengthMinutes) min")
                Slider(
                    value: Binding(
                        get: { Double(viewModel.studySessionLengthMinutes) },
                        set: { viewModel.studySessionLengthMinutes = Int($0) }
                    ),
                    in: 5 ... 120,
                    step: 5
                )
                .tint(mood.accent)
                .frame(minHeight: Tide.hit)
                .accessibilityLabel("Session length")
                .accessibilityValue("\(viewModel.studySessionLengthMinutes) minutes")
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.studySessionLengthMinutes)
    }
}

// MARK: - TrainingPreferencesView

struct TrainingPreferencesView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            title: "TRAIN\nWHEN?",
            subtitle: "When do you prefer to train? The planner respects this when free windows allow.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
            OnboardingChoiceGrid(items: TrainingTimePreference.allCases, stretchesLast: false) { pref in
                OnboardingChoiceCard(
                    title: pref.label,
                    systemImage: Self.symbol(for: pref),
                    isSelected: viewModel.trainingTimePreference == pref
                ) {
                    viewModel.trainingTimePreference = pref
                }
            }
        }
    }

    private static func symbol(for pref: TrainingTimePreference) -> String {
        switch pref {
        case .morning: "sunrise.fill"
        case .midday: "sun.max.fill"
        case .evening: "sunset.fill"
        case .anyFree: "clock.fill"
        }
    }
}

// MARK: - WeekendModeView

struct WeekendModeView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            title: "WEEKENDS.",
            subtitle: "How different are your weekends from weekdays?",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
            VStack(spacing: Tide.s3) {
                ForEach(WeekendDifferential.allCases, id: \.self) { mode in
                    OnboardingChoiceCard(
                        title: mode.label,
                        systemImage: Self.symbol(for: mode),
                        isSelected: viewModel.weekendDifferential == mode,
                        layout: .inline
                    ) {
                        viewModel.weekendDifferential = mode
                    }
                }
            }
        }
    }

    private static func symbol(for mode: WeekendDifferential) -> String {
        switch mode {
        case .sameAsWeekday: "calendar"
        case .lateWake: "bed.double.fill"
        case .fullOff: "moon.zzz.fill"
        }
    }
}

// MARK: - RhythmSummary

/// Wake time, sleep target and the bedtime they imply, live as the controls move.
private struct RhythmSummary: View {
    let wakeMinutes: Int
    let sleepHours: Double

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Minutes after midnight to be in bed by, wrapping past midnight.
    private var bedMinutes: Int {
        let day = 24 * 60
        return ((wakeMinutes - Int((sleepHours * 60).rounded())) % day + day) % day
    }

    var body: some View {
        // Three columns; one under the other at accessibility text sizes.
        let columns = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return columns {
            column("Wake", OnboardingFormat.clock(wakeMinutes))
            column("Sleep", OnboardingFormat.hours(sleepHours))
            column("In bed by", OnboardingFormat.clock(bedMinutes))
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .animation(reduceMotion ? nil : Tide.snap, value: wakeMinutes)
        .animation(reduceMotion ? nil : Tide.snap, value: sleepHours)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Wake \(OnboardingFormat.clock(wakeMinutes)), sleep \(OnboardingFormat.hours(sleepHours)), in bed by \(OnboardingFormat.clock(bedMinutes))"
        )
    }

    private func column(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            TideNumber(value, size: Tide.numeralS + Tide.s1, relativeTo: .title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - EatingWindowBar

/// The day as one bar, with the eating window lit.
private struct EatingWindowBar: View {
    let start: Int
    let end: Int

    private var eatingHours: Double {
        Double(max(end - start, 0)) / 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideDayBar(start: start, end: end)

            Text("Eating \(OnboardingFormat.hours(eatingHours)) \u{00B7} Fasting \(OnboardingFormat.hours(24 - eatingHours))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eating \(OnboardingFormat.hours(eatingHours)), fasting \(OnboardingFormat.hours(24 - eatingHours))")
    }
}

// MARK: - Shared helpers

private func weekdayLabel(_ weekday: Int) -> String {
    let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return names[max(1, min(7, weekday))]
}

/// Two-letter day label for the compact 7-across day selector.
private func weekdayShort(_ weekday: Int) -> String {
    let names = ["", "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    return names[max(1, min(7, weekday))]
}

private func formatTime(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}
