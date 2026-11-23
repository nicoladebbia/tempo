//
// TrainingSettingsDetailView.swift
// Tempo
//
// Settings → Training (split, football days, custom split editor). Split out
// of DashboardSettingsView.swift to keep it under the SwiftLint file length cap.
//

import SwiftData
import SwiftUI

// MARK: - TrainingSettingsDetailView

// Note on the local save() in this view: after every successful save we post
// `Notification.Name.tempoTrainingSettingsChanged` so NutritionTabViewModel
// can regenerate its WeeklyMealPlan against the new trainingSplit /
// footballDays. Without this, the Nutrition Plan tab kept showing the
// previous schedule (e.g. Wednesday strength) until the user manually
// re-generated.
struct TrainingSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]
    @Query
    private var allProfiles: [UserProfile]

    private var settings: UserSettings? {
        allSettings.first
    }

    @Query(sort: \TrainingBlock.startDate)
    private var trainingBlocks: [TrainingBlock]

    /// The block emphasis in force today; no block declared → physique, the
    /// de-facto default (§14 Decision 1).
    private var currentEmphasis: BlockEmphasis {
        TrainingBlockSchedule.currentEmphasis(spans: trainingBlocks.map(\.span), on: Date()) ?? .physique
    }

    /// Mon-first to match the ActiveDays bitmask (index 0 = Monday = 1<<0).
    private let footballDayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    @State
    private var showWhoopImporter = false
    @State
    private var whoopImportResult: String?

    @State
    private var trainingSplit: TrainingSplit = .pushPullLegs
    @State
    private var autoDeload = true
    @State
    private var deloadStyle: DeloadStyle = .intensityCut
    @State
    private var deloadWeeks = 5
    @State
    private var autoStartRest = true
    @State
    private var defaultRestSeconds = 120

    private var footballCount: Int {
        settings?.footballDaysRaw.nonzeroBitCount ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                // Summary hero — what this config means at a glance.
                VStack(spacing: Tide.s1) {
                    Text(trainingSplit.displayName)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text(footballCount == 0
                        ? "No football days"
                        : "\(footballCount) football day\(footballCount == 1 ? "" : "s") / week")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tide.s5).tideCard(padding: 0)

                SettingsFormCard(title: "Programme") {
                    // Whole-row Menu — fixes the round-1 bug where the bare
                    // .labelsHidden() menu Picker had a tiny dead tap target.
                    // (Segmented is unusable here: 5 long split names won't fit.)
                    Menu {
                        Picker("Split", selection: $trainingSplit) {
                            ForEach(TrainingSplit.allCases, id: \.self) { split in
                                Text(split.displayName).tag(split)
                            }
                        }
                    } label: {
                        HStack(spacing: Tide.s3) {
                            SettingsIconTile(systemName: "dumbbell.fill", tint: Color.accentColor)
                            Text("Split")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                            Text(trainingSplit.displayName)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                        }
                        .padding(.horizontal, Tide.s4)
                        .padding(.vertical, Tide.s3)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .onChange(of: trainingSplit) { _, newValue in
                        settings?.trainingSplit = newValue
                        save()
                    }

                    if trainingSplit == .custom {
                        SettingsRowDivider()
                        NavigationLink {
                            CustomSplitEditorView()
                        } label: {
                            HStack(spacing: Tide.s3) {
                                SettingsIconTile(systemName: "calendar", tint: TideTrain.violet)
                                Text("Customise days")
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text)
                                Spacer(minLength: Tide.s2)
                                Image(systemName: "chevron.right")
                                    .font(Tide.label)
                                    .foregroundStyle(Tide.text3)
                            }
                            .padding(.horizontal, Tide.s4)
                            .padding(.vertical, Tide.s3)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                    }

                    SettingsRowDivider()

                    SettingsControlRow(label: "Weight Unit", icon: "scalemass.fill", iconTint: Tide.water) {
                        Picker("", selection: Binding(
                            get: { settings?.weightUnit ?? .kg },
                            set: { newValue in
                                settings?.weightUnit = newValue
                                save()
                            }
                        )) {
                            ForEach(WeightUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue.uppercased()).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }

                    SettingsRowDivider()

                    // Experience level — feeds the cold-start weight estimator.
                    // Shows Beginner when unset (matches the engine's default) so
                    // an intermediate/advanced lifter sees it's wrong and corrects
                    // it. Full-row Menu (same as Split) so a long value like
                    // "Intermediate" doesn't wrap in a cramped trailing control.
                    Menu {
                        Picker("Experience", selection: Binding(
                            get: { settings?.experienceLevelRaw ?? "Beginner" },
                            set: { newValue in
                                settings?.experienceLevelRaw = newValue
                                save()
                            }
                        )) {
                            ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                    } label: {
                        HStack(spacing: Tide.s3) {
                            SettingsIconTile(systemName: "figure.strengthtraining.traditional", tint: TideTrain.caution)
                            Text("Experience")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                            Text(settings?.experienceLevelRaw ?? "Beginner")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                        }
                        .padding(.horizontal, Tide.s4)
                        .padding(.vertical, Tide.s3)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }

                // Football days — editable chips (Mon=1<<0 … Sun=1<<6).
                SettingsFormCard(
                    title: "Football days",
                    footnote: "Tempo plans recovery and meal timing around your match/training days."
                ) {
                    HStack(spacing: Tide.s1) {
                        ForEach(Array(footballDayLabels.enumerated()), id: \.offset) { index, dayLabel in
                            let bit = 1 << index
                            let isOn = ((settings?.footballDaysRaw ?? 0) & bit) != 0
                            Button {
                                guard let s = settings else { return }
                                s.footballDaysRaw ^= bit
                                save()
                                HapticManager.selection()
                            } label: {
                                Text(dayLabel)
                                    .font(Tide.caption.weight(.semibold))
                            }
                            .buttonStyle(.trainChoice(isSelected: isOn))
                        }
                    }
                    .padding(Tide.s4)
                }

                // Training block — manual emphasis declaration (§14 Decision 1).
                // Drives the daily coach's CONTEXT line + the weekly AI goal;
                // deliberately does NOT touch the deterministic split/schedule.
                SettingsFormCard(
                    title: "Training block",
                    footnote: currentEmphasis == .physique
                        ? "Physique block — hypertrophy primary, soccer held at maintenance. Drives the daily coach and weekly AI plan."
                        : "Soccer block — speed and conditioning primary, strength held at maintenance. Drives the daily coach and weekly AI plan."
                ) {
                    SettingsControlRow(label: "Emphasis", icon: "target", iconTint: Tide.water) {
                        Picker("", selection: Binding(
                            get: { currentEmphasis },
                            set: { applyBlockEmphasis($0) }
                        )) {
                            ForEach(BlockEmphasis.allCases, id: \.self) { emphasis in
                                Text(emphasis.displayName).tag(emphasis)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }

                // Whoop history import — seeds a year of baselines/patterns
                // from the official account-data export (4 CSVs). Additive;
                // re-running is safe (existing days/workouts are skipped).
                SettingsFormCard(
                    title: "Whoop history",
                    footnote: whoopImportResult
                        ?? "Import your Whoop account-data export (CSV files). Seeds baselines, training history, venue patterns, and personal habit insights."
                ) {
                    Button {
                        showWhoopImporter = true
                    } label: {
                        HStack(spacing: Tide.s3) {
                            SettingsIconTile(systemName: "square.and.arrow.down", tint: Color.accentColor)
                            Text("Import Whoop export…")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                        }
                        .padding(.horizontal, Tide.s4)
                        .padding(.vertical, Tide.s3)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .fileImporter(
                    isPresented: $showWhoopImporter,
                    allowedContentTypes: [.commaSeparatedText, .plainText],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case let .success(urls):
                        let summary = WhoopExportImporter.importFiles(urls, modelContext: modelContext)
                        whoopImportResult = "Imported: \(summary.label)."
                    case let .failure(error):
                        whoopImportResult = "Import failed: \(error.localizedDescription)"
                    }
                }

                SettingsFormCard(
                    title: "Deload",
                    footnote: autoDeload
                        ? "Every \(deloadWeeks) weeks: \(deloadStyle.blurb)"
                        : "Auto-deload is off — you'll manage recovery weeks manually."
                ) {
                    SettingsControlRow(label: "Auto Deload", icon: "arrow.down.right.circle", iconTint: TideTrain.caution) {
                        Toggle("", isOn: $autoDeload)
                            .labelsHidden()
                            .tint(Color.accentColor)
                    }
                    .onChange(of: autoDeload) { _, newValue in
                        settings?.autoDeload = newValue
                        save()
                    }

                    if autoDeload {
                        SettingsRowDivider()
                        SettingsControlRow(label: "Every", icon: "calendar", iconTint: TideTrain.violet) {
                            Stepper("\(deloadWeeks) weeks", value: $deloadWeeks, in: 3 ... 8)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .fixedSize()
                        }
                        .onChange(of: deloadWeeks) { _, newValue in
                            settings?.deloadFrequencyWeeks = newValue
                            save()
                        }

                        SettingsRowDivider()
                        // §19.3 — the three deload styles.
                        SettingsControlRow(label: "Style", icon: "dial.low", iconTint: Color.accentColor) {
                            Picker("", selection: $deloadStyle) {
                                ForEach(DeloadStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .labelsHidden()
                            .tint(Tide.text2)
                        }
                        .onChange(of: deloadStyle) { _, newValue in
                            settings?.deloadStyle = newValue
                            save()
                        }
                    }
                }

                SettingsFormCard(
                    title: "Rest Timer",
                    footnote: autoStartRest
                        ? "Rest starts automatically after each set. Default \(formatRest(defaultRestSeconds)) — override it per exercise on any exercise's detail screen."
                        : "Rest timer is off — you advance to the next set yourself."
                ) {
                    SettingsControlRow(label: "Auto-start timer", icon: "timer", iconTint: Color.accentColor) {
                        Toggle("", isOn: $autoStartRest)
                            .labelsHidden()
                            .tint(Color.accentColor)
                    }
                    .onChange(of: autoStartRest) { _, newValue in
                        settings?.autoStartRestTimer = newValue
                        save()
                    }

                    if autoStartRest {
                        SettingsRowDivider()
                        SettingsControlRow(label: "Default rest", icon: "clock.arrow.circlepath", iconTint: TideTrain.violet) {
                            Stepper(formatRest(defaultRestSeconds), value: $defaultRestSeconds, in: 30 ... 300, step: 15)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .fixedSize()
                        }
                        .onChange(of: defaultRestSeconds) { _, newValue in
                            settings?.defaultRestSeconds = newValue
                            save()
                        }
                    }
                }
            }
            .padding(.horizontal, Tide.s5)
            .padding(.vertical, Tide.s4)
        }
        .scrollContentBackground(.hidden)
        .tidePage()
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            trainingSplit = settings?.trainingSplit ?? .pushPullLegs
            autoDeload = settings?.autoDeload ?? true
            deloadWeeks = settings?.deloadFrequencyWeeks ?? 5
            deloadStyle = settings?.deloadStyle ?? .intensityCut
            autoStartRest = settings?.autoStartRestTimer ?? true
            defaultRestSeconds = settings?.defaultRestSeconds ?? 120
        }
    }

    /// Compact m/s label for a rest duration (e.g. 45→"45s", 90→"1m 30s", 120→"2m").
    private func formatRest(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    /// Declares a new open-ended block starting today (§14 Decision 1). The
    /// previous open block closes at yesterday; one that started today (or
    /// later) never ran a day, so it's deleted instead of kept as an empty
    /// span. Closed past blocks stay as history. Uses save() — since the
    /// deterministic week became emphasis-aware (soccer → conditioning + pool
    /// spare days), an emphasis switch must replan This Week immediately,
    /// same path as a footballDays toggle.
    private func applyBlockEmphasis(_ emphasis: BlockEmphasis) {
        guard emphasis != currentEmphasis else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for block in trainingBlocks where block.endDate == nil {
            if cal.startOfDay(for: block.startDate) >= today {
                modelContext.delete(block)
            } else {
                block.endDate = cal.date(byAdding: .day, value: -1, to: today)
            }
        }
        modelContext.insert(TrainingBlock(emphasis: emphasis, startDate: today))
        save()
        HapticManager.selection()
    }

    private func save() {
        // Mirror the schedule inputs onto UserProfile (sync DTO parity) —
        // this screen is the single schedule editor (Week Plan's Edit opens it).
        if let s = settings, let profile = allProfiles.first {
            profile.footballDaysRaw = s.footballDaysRaw
            profile.trainingSplitRaw = s.trainingSplit.rawValue
        }
        modelContext.saveOrAlert("training settings")
        // Tell the Nutrition tab to regenerate its plan with the new
        // trainingSplit/footballDays. We intentionally post on EVERY save
        // (every chip toggle); the observer side debounces so a burst of
        // chip taps produces a single regen at the end.
        NotificationCenter.default.post(
            name: .tempoTrainingSettingsChanged,
            object: nil
        )
    }
}

// MARK: - CustomSplitEditorView

/// Advanced custom split — assign a session type to each weekday (Mon-first).
/// Football days lock automatically from the football-days setting; the engine
/// keeps them as football regardless of what's stored here. Persists to
/// UserSettings.customWeekdayPlan and replans the week on every change (recovery
/// and deload still adjust the result automatically).
struct CustomSplitEditorView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? { allSettings.first }

    private let dayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    /// Types the user can assign per day. Football is auto (from the football
    /// setting); run/sprint are covered by conditioning for a gym+football user.
    private let selectable: [WorkoutType] = [
        .push, .pull, .legs, .upper, .lower, .fullBody, .conditioning, .pool, .mobility, .rest,
    ]

    static let defaultPlan: [WorkoutType] = [.push, .pull, .legs, .upper, .lower, .rest, .rest]

    @State
    private var plan: [WorkoutType] = CustomSplitEditorView.defaultPlan

    /// Calendar weekday (1=Sun) for a Mon-first row index.
    private func calWeekday(_ index: Int) -> Int { (index + 1) % 7 + 1 }

    private func isFootballDay(_ index: Int) -> Bool {
        ActiveDays(rawValue: settings?.footballDaysRaw ?? 0).isActive(on: calWeekday(index))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s2) {
                SettingsFormCard(
                    title: "Your week",
                    footnote: "Assign each day. Football days are set on the Training screen and lock here. Recovery and deload still adjust these automatically."
                ) {
                    ForEach(0 ..< 7, id: \.self) { i in
                        if i > 0 { SettingsRowDivider() }
                        dayRow(i)
                    }
                }
            }
            .padding(.horizontal, Tide.s5)
            .padding(.vertical, Tide.s4)
        }
        .scrollContentBackground(.hidden)
        .tidePage()
        .navigationTitle("Custom Split")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let stored = settings?.customWeekdayPlan, stored.count == 7 {
                plan = stored
            } else {
                // Seed a sensible week so "Custom" isn't a blank/PPL fallback.
                plan = Self.defaultPlan
                persist()
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ i: Int) -> some View {
        SettingsControlRow(label: dayNames[i], icon: "calendar", iconTint: TideTrain.violet) {
            if isFootballDay(i) {
                Text("Football")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
            } else {
                Menu {
                    Picker("", selection: Binding(
                        get: { plan[i] },
                        set: { newValue in
                            plan[i] = newValue
                            persist()
                            HapticManager.selection()
                        }
                    )) {
                        ForEach(selectable, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } label: {
                    HStack(spacing: Tide.s1) {
                        Text(plan[i].displayName)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                    }
                }
            }
        }
    }

    private func persist() {
        guard let s = settings else { return }
        s.customWeekdayPlan = plan
        modelContext.saveOrAlert("custom split")
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }
}
