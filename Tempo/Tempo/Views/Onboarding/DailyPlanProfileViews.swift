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

// MARK: - DailyRhythmView (wake time + sleep target + chronotype)

struct DailyRhythmView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                title("YOUR DAILY\nRHYTHM.")

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    sectionLabel("Wake time")
                    minutesTimePicker(minutes: $viewModel.wakeTimeMinutes)
                }

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    sectionLabel("Sleep target: \(formatHours(viewModel.sleepTargetHours))")
                    Slider(value: $viewModel.sleepTargetHours, in: 6.0 ... 10.0, step: 0.25)
                        .tint(Color.tempoAmber)
                }

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    sectionLabel("When are you sharpest?")
                    ForEach(Chronotype.allCases, id: \.self) { option in
                        chronotypeRow(option)
                    }
                }

                Spacer().frame(height: TempoSpacing.xl)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                    viewModel.advance()
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.top, TempoSpacing.xl)
        }
    }

    private func chronotypeRow(_ option: Chronotype) -> some View {
        let selected = viewModel.chronotype == option
        return Button {
            viewModel.chronotype = option
        } label: {
            HStack {
                Text(option.label)
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.tempoAmber)
                }
            }
            .padding(TempoSpacing.md)
            .background(selected ? Color.tempoAmber.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - ClassScheduleView (term-bounded weekly classes)

struct ClassScheduleView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var editing: OnboardingClassBlock?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                title("CLASS\nSCHEDULE.")

                Text("Tempo schedules study + training around your classes. Add the ones that repeat weekly.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                termWindow

                if viewModel.classBlocks.isEmpty {
                    Text("No classes added yet.")
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, TempoSpacing.md)
                } else {
                    ForEach(viewModel.classBlocks) { block in
                        classRow(block)
                    }
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Add class", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.tempoAmber)
                }

                Spacer().frame(height: TempoSpacing.xl)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                    viewModel.advance()
                }
                Button("Skip — I'll add classes later") {
                    viewModel.skip()
                }
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.top, TempoSpacing.xl)
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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("Term window (optional)")
            HStack {
                DatePicker(
                    "Starts",
                    selection: Binding(
                        get: { viewModel.termStartDate ?? Date() },
                        set: { viewModel.termStartDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                Spacer()
                DatePicker(
                    "Ends",
                    selection: Binding(
                        get: { viewModel.termEndDate ?? Date().addingTimeInterval(90 * 86_400) },
                        set: { viewModel.termEndDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
    }

    private func classRow(_ block: OnboardingClassBlock) -> some View {
        Button {
            editing = block
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.courseCode)
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(weekdayLabel(block.weekday)) · \(formatTime(block.startMinuteOfDay))–\(formatTime(block.endMinuteOfDay))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button(role: .destructive) {
                    viewModel.classBlocks.removeAll { $0.id == block.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.tempoError)
                }
            }
            .padding(TempoSpacing.md)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Course code (e.g. STAT 101)", text: $courseCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("Full name (optional)", text: $courseName)
                    TextField("Location (optional)", text: $location)
                }
                Section("Days") {
                    // Tap each weekday the class meets (e.g. Mon/Wed/Fri).
                    HStack(spacing: 6) {
                        ForEach(1 ... 7, id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button {
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            } label: {
                                Text(weekdayShort(d))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(on ? Color.tempoAmber : Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section("Time") {
                    minutesTimePickerRow("Starts", minutes: $startMinutes)
                    minutesTimePickerRow("Ends", minutes: $endMinutes)
                }
            }
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
                    .disabled(
                        courseCode.trimmingCharacters(in: .whitespaces).isEmpty
                            || endMinutes <= startMinutes
                            || weekdays.isEmpty
                    )
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
}

// MARK: - EatingWindowView

struct EatingWindowView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                title("EATING\nWINDOW.")

                Text("Tempo plans meals inside this window. Pick a preset or set your own.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                VStack(spacing: TempoSpacing.sm) {
                    ForEach(EatingWindowPreset.allCases, id: \.self) { preset in
                        presetRow(preset)
                    }
                }

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    sectionLabel("Window")
                    HStack {
                        minutesTimePicker(minutes: $viewModel.eatingWindowStartMinutes)
                        Text("to")
                            .foregroundStyle(.white.opacity(0.5))
                        minutesTimePicker(minutes: $viewModel.eatingWindowEndMinutes)
                    }
                }

                Toggle("I skip breakfast", isOn: $viewModel.breakfastSkipped)
                    .tint(Color.tempoAmber)
                    .foregroundStyle(.white)

                Toggle("Post-workout meal is mandatory", isOn: $viewModel.postWorkoutMandatory)
                    .tint(Color.tempoAmber)
                    .foregroundStyle(.white)

                Spacer().frame(height: TempoSpacing.xl)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: viewModel.eatingWindowEndMinutes > viewModel.eatingWindowStartMinutes) {
                    viewModel.advance()
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.top, TempoSpacing.xl)
        }
    }

    private func presetRow(_ preset: EatingWindowPreset) -> some View {
        let selected = viewModel.eatingWindowPreset == preset
        return Button {
            viewModel.eatingWindowPreset = preset
            if let window = preset.defaultWindow {
                viewModel.eatingWindowStartMinutes = window.start
                viewModel.eatingWindowEndMinutes = window.end
            }
        } label: {
            HStack {
                Text(preset.label).foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.tempoAmber)
                }
            }
            .padding(TempoSpacing.md)
            .background(selected ? Color.tempoAmber.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - StudyPreferencesView

struct StudyPreferencesView: View {
    @Bindable var viewModel: OnboardingViewModel

    private let presets: [Int] = [25, 50, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            title("STUDY\nSESSIONS.")

            Text("How long do you focus before a break?")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: TempoSpacing.sm) {
                ForEach(presets, id: \.self) { p in
                    chip(label: "\(p) min", selected: viewModel.studySessionLengthMinutes == p) {
                        viewModel.studySessionLengthMinutes = p
                    }
                }
            }

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                sectionLabel("Custom: \(viewModel.studySessionLengthMinutes) min")
                Slider(
                    value: Binding(
                        get: { Double(viewModel.studySessionLengthMinutes) },
                        set: { viewModel.studySessionLengthMinutes = Int($0) }
                    ),
                    in: 5 ... 120,
                    step: 5
                )
                .tint(Color.tempoAmber)
            }

            Spacer()

            OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                viewModel.advance()
            }
        }
        .padding(.horizontal, TempoSpacing.xl)
        .padding(.top, TempoSpacing.xl)
    }
}

// MARK: - TrainingPreferencesView

struct TrainingPreferencesView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            title("TRAIN\nWHEN?")

            Text("When do you prefer to train? The planner respects this when free windows allow.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: TempoSpacing.sm) {
                ForEach(TrainingTimePreference.allCases, id: \.self) { pref in
                    let selected = viewModel.trainingTimePreference == pref
                    Button {
                        viewModel.trainingTimePreference = pref
                    } label: {
                        HStack {
                            Text(pref.label).foregroundStyle(.white)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Color.tempoAmber)
                            }
                        }
                        .padding(TempoSpacing.md)
                        .background(selected ? Color.tempoAmber.opacity(0.15) : Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Spacer()

            OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                viewModel.advance()
            }
        }
        .padding(.horizontal, TempoSpacing.xl)
        .padding(.top, TempoSpacing.xl)
    }
}

// MARK: - WeekendModeView

struct WeekendModeView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            title("WEEKENDS.")

            Text("How different are your weekends from weekdays?")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: TempoSpacing.sm) {
                ForEach(WeekendDifferential.allCases, id: \.self) { mode in
                    let selected = viewModel.weekendDifferential == mode
                    Button {
                        viewModel.weekendDifferential = mode
                    } label: {
                        HStack {
                            Text(mode.label).foregroundStyle(.white)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Color.tempoAmber)
                            }
                        }
                        .padding(TempoSpacing.md)
                        .background(selected ? Color.tempoAmber.opacity(0.15) : Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Spacer()

            OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                viewModel.advance()
            }
        }
        .padding(.horizontal, TempoSpacing.xl)
        .padding(.top, TempoSpacing.xl)
    }
}

// MARK: - Shared helpers

private func title(_ s: String) -> some View {
    Text(s)
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(.white)
}

private func sectionLabel(_ s: String) -> some View {
    Text(s)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
}

private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(selected ? Color.black : .white)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background(selected ? Color.tempoAmber : Color.white.opacity(0.08))
            .clipShape(Capsule())
    }
}

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
}

private func minutesTimePickerRow(_ label: String, minutes: Binding<Int>) -> some View {
    DatePicker(
        label,
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
