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
            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Wake time")
                minutesTimePicker(minutes: $viewModel.wakeTimeMinutes)
            }

            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("Sleep target: \(formatHours(viewModel.sleepTargetHours))")
                Slider(value: $viewModel.sleepTargetHours, in: 6.0 ... 10.0, step: 0.25)
                    .tint(mood.accent)
                    .frame(minHeight: Tide.hit)
                    .accessibilityLabel("Sleep target")
                    .accessibilityValue(formatHours(viewModel.sleepTargetHours))
            }

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("When are you sharpest?")
                VStack(spacing: Tide.s2) {
                    ForEach(Chronotype.allCases, id: \.self) { option in
                        OnboardingOptionRow(title: option.label, isSelected: viewModel.chronotype == option) {
                            viewModel.chronotype = option
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ClassScheduleView

struct ClassScheduleView: View {
    @Bindable var viewModel: OnboardingViewModel
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
                Text("No classes added yet.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showAdd) {
            ClassBlockEditor(
                existing: nil,
                onSave: { newBlocks in
                    viewModel.classBlocks.append(contentsOf: newBlocks)
                    showAdd = false
                },
                onCancel: { showAdd = false }
            )
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
        }
    }

    private var termWindow: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            OnboardingSectionLabel("Term window (optional)")
            HStack(alignment: .top, spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Starts")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                    DatePicker(
                        "Starts",
                        selection: Binding(
                            get: { viewModel.termStartDate ?? Date() },
                            set: { viewModel.termStartDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(minHeight: Tide.hit)
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Ends")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                    DatePicker(
                        "Ends",
                        selection: Binding(
                            get: { viewModel.termEndDate ?? Date().addingTimeInterval(90 * 86400) },
                            set: { viewModel.termEndDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(minHeight: Tide.hit)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func classRow(_ block: OnboardingClassBlock) -> some View {
        HStack(spacing: 0) {
            Button {
                editing = block
            } label: {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(block.courseCode)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text("\(weekdayLabel(block.weekday)) · \(formatTime(block.startMinuteOfDay))–\(formatTime(block.endMinuteOfDay))")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s3, alignment: .leading)
                .padding(.leading, Tide.s4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

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
                        // Equal-width cells always fit the row.
                        HStack(spacing: Tide.s1) {
                            ForEach(1 ... 7, id: \.self) { d in
                                OnboardingChip(title: weekdayShort(d), isSelected: weekdays.contains(d), expands: true) {
                                    if weekdays.contains(d) {
                                        weekdays.remove(d)
                                    } else {
                                        weekdays.insert(d)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        OnboardingSectionLabel("Time")
                        VStack(spacing: 0) {
                            minutesTimePickerRow("Starts", minutes: $startMinutes)
                            Divider().overlay(Tide.hairline)
                            minutesTimePickerRow("Ends", minutes: $endMinutes)
                        }
                        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
                    OnboardingOptionRow(title: preset.label, isSelected: viewModel.eatingWindowPreset == preset) {
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
                HStack(spacing: Tide.s3) {
                    minutesTimePicker(minutes: $viewModel.eatingWindowStartMinutes)
                    Text("to")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                    minutesTimePicker(minutes: $viewModel.eatingWindowEndMinutes)
                    Spacer(minLength: 0)
                }
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
}

// MARK: - StudyPreferencesView

struct StudyPreferencesView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.tideMood) private var mood

    private let presets: [Int] = [25, 50, 90]

    var body: some View {
        OnboardingScaffold(
            title: "STUDY\nSESSIONS.",
            subtitle: "How long do you focus before a break?",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
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
            VStack(spacing: Tide.s2) {
                ForEach(TrainingTimePreference.allCases, id: \.self) { pref in
                    OnboardingOptionRow(title: pref.label, isSelected: viewModel.trainingTimePreference == pref) {
                        viewModel.trainingTimePreference = pref
                    }
                }
            }
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
            VStack(spacing: Tide.s2) {
                ForEach(WeekendDifferential.allCases, id: \.self) { mode in
                    OnboardingOptionRow(title: mode.label, isSelected: viewModel.weekendDifferential == mode) {
                        viewModel.weekendDifferential = mode
                    }
                }
            }
        }
    }
}

// MARK: - Shared helpers

private func minutesTimePicker(minutes: Binding<Int>) -> some View {
    DatePicker(
        "",
        selection: Binding(
            get: {
                let cal = Calendar.current
                return cal.date(from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        ),
        displayedComponents: .hourAndMinute
    )
    .labelsHidden()
    .frame(minHeight: Tide.hit)
}

private func minutesTimePickerRow(_ label: String, minutes: Binding<Int>) -> some View {
    DatePicker(
        selection: Binding(
            get: {
                let cal = Calendar.current
                return cal.date(from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        ),
        displayedComponents: .hourAndMinute
    ) {
        Text(label)
            .font(Tide.body)
            .foregroundStyle(Tide.text)
    }
    .frame(minHeight: Tide.hit)
}

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

private func formatHours(_ hours: Double) -> String {
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}
