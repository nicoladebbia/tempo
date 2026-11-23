//
// NonNegotiableSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - NonNegotiableSetupView

// Per BUILD_PLAN step 10.5.
// Per MODULE_ACCOUNTABILITY.md — Setup flow for non-negotiables.

struct NonNegotiableSetupView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Query(sort: \NonNegotiable.order)
    private var nonNegotiables: [NonNegotiable]

    @State
    private var showAddSheet = false
    @State
    private var editingItem: NonNegotiable?
    @State
    private var showDeleteConfirmation = false
    @State
    private var pendingDeleteItem: NonNegotiable?

    private let maxNonNegotiables = 7

    var body: some View {
        NavigationStack {
            Group {
                if nonNegotiables.isEmpty {
                    emptyState
                } else {
                    nonNegotiableList
                }
            }
            .tidePage()
            .navigationTitle("Non-Negotiables")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            }
            // The field rests while the edit sheet is over this page.
            .tideCovered(showAddSheet || editingItem != nil)
            .sheet(isPresented: $showAddSheet) {
                NonNegotiableEditSheet(
                    existingCount: nonNegotiables.count,
                    onSave: { nn in addNonNegotiable(nn) }
                )
            }
            .sheet(item: $editingItem) { item in
                NonNegotiableEditSheet(
                    editing: item,
                    existingCount: nonNegotiables.count,
                    onSave: { _ in try? modelContext.save() }
                )
            }
            .confirmationDialog(
                "Delete Non-Negotiable?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = pendingDeleteItem {
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                    pendingDeleteItem = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteItem = nil
                }
            } message: {
                Text(
                    "This will permanently delete \"\(pendingDeleteItem?.name ?? "this item")\" and all its historical progress data. This cannot be undone."
                )
            }
        }
    }

    // MARK: - List

    // A native List on purpose: swipe-to-delete and drag-to-reorder stay.

    private var nonNegotiableList: some View {
        List {
            // Active items
            Section {
                ForEach(nonNegotiables.filter(\.isActive)) { nn in
                    nonNegotiableRow(nn)
                }
                .onDelete { offsets in
                    let active = nonNegotiables.filter(\.isActive)
                    if let index = offsets.first {
                        pendingDeleteItem = active[index]
                        showDeleteConfirmation = true
                    }
                }
                .onMove { from, to in
                    moveItems(from: from, to: to)
                }
            } header: {
                HStack {
                    Text("Active").tideLabel(Tide.text3)
                    Spacer()
                    Text("\(nonNegotiables.filter(\.isActive).count) / \(maxNonNegotiables)")
                        .tideLabel(Tide.text3)
                        .monospacedDigit()
                }
            } footer: {
                if nonNegotiables.count >= maxNonNegotiables {
                    Text("Maximum \(maxNonNegotiables) non-negotiables. Keep it focused — too many dilutes accountability.")
                        .font(Tide.caption)
                        .foregroundStyle(TideTone.amber)
                }
            }
            .tideListRow()

            // Inactive items
            let inactive = nonNegotiables.filter { !$0.isActive }
            if !inactive.isEmpty {
                Section {
                    ForEach(inactive) { nn in
                        nonNegotiableRow(nn)
                            .opacity(0.6)
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            pendingDeleteItem = inactive[index]
                            showDeleteConfirmation = true
                        }
                    }
                } header: {
                    Text("Inactive").tideLabel(Tide.text3)
                }
                .tideListRow()
            }

            // Default templates
            if nonNegotiables.isEmpty || nonNegotiables.count < 3 {
                templatesSection
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Row

    private func nonNegotiableRow(_ nn: NonNegotiable) -> some View {
        Button {
            editingItem = nn
        } label: {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: nn.icon, tint: nn.isActive ? mood.accent : Tide.text3)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(nn.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)

                    rowSubtitle(nn)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Tide.s2)

                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit")
    }

    private func rowSubtitle(_ nn: NonNegotiable) -> Text {
        let type = Text(nn.type.displayName)
        let target = Text(targetDescription(nn)).foregroundStyle(Tide.text2)
        if let source = nn.integrationSourceName {
            return Text("\(type) · \(Text(source).foregroundStyle(mood.accent)) · \(target)")
        }
        return Text("\(type) · \(target)")
    }

    private func targetDescription(_ nn: NonNegotiable) -> String {
        switch nn.type {
        case .study:
            let hours = Int(nn.targetValue) / 60
            let mins = Int(nn.targetValue) % 60
            if hours > 0, mins > 0 {
                return "\(hours)h \(mins)m"
            }
            if hours > 0 {
                return "\(hours)h"
            }
            return "\(mins)m"
        case .meals:
            return "\(Int(nn.targetValue)) meals"
        case .train:
            return "1 session"
        case .sleep:
            return "\(Int(nn.targetValue))h"
        case .steps:
            return "\(Int(nn.targetValue)) steps"
        case .hydration:
            return "\(Int(nn.targetValue)) glasses"
        case .custom:
            return "\(Int(nn.targetValue))"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        TideScrollPage(spacing: Tide.s4, spacer: Tide.s8) {
            VStack(spacing: Tide.s4) {
                TideEmptyPanel(
                    systemImage: "checklist",
                    title: "Set your non-negotiables",
                    message: "These are the things you MUST do every day. No excuses. No exceptions."
                )

                Button("Use default templates") {
                    addDefaultTemplates()
                }
                .buttonStyle(.tidePrimary)

                Button("Create from scratch") {
                    showAddSheet = true
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
        }
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        Section {
            Button {
                addDefaultTemplates()
            } label: {
                HStack(spacing: Tide.s3) {
                    TideIconTile(systemName: "wand.and.stars", tint: mood.accent)

                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text("Add Default Templates")
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                        Text("Study 2h · Train · 3 Meals · Sleep 7h")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Tide.s2)
                }
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Quick start").tideLabel(Tide.text3)
        }
        .tideListRow()
    }

    // MARK: - Add Button

    @ViewBuilder
    private var addButton: some View {
        if nonNegotiables.filter(\.isActive).count < maxNonNegotiables {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add non-negotiable")
        }
    }

    // MARK: - Actions

    private func addNonNegotiable(_ nn: NonNegotiable) {
        nn.order = nonNegotiables.count
        modelContext.insert(nn)
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet, from items: [NonNegotiable]) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        try? modelContext.save()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var active = nonNegotiables.filter(\.isActive)
        active.move(fromOffsets: source, toOffset: destination)
        for (index, item) in active.enumerated() {
            item.order = index
        }
        try? modelContext.save()
    }

    /// Per MODULE_ACCOUNTABILITY.md — default templates.
    private func addDefaultTemplates() {
        let templates: [(String, NonNegotiableType, String, Double, TrackingMethod)] = [
            ("Study", .study, "book.fill", 120, .timer),
            ("Training", .train, "dumbbell.fill", 1, .autoWhoop),
            ("Meals", .meals, "fork.knife", 3, .manual),
            ("Sleep", .sleep, "moon.fill", 7, .autoHealthkit),
        ]

        for (index, t) in templates.enumerated() {
            let existing = nonNegotiables.contains { $0.type == t.1 }
            guard !existing else {
                continue
            }

            let nn = NonNegotiable(
                name: t.0,
                type: t.1,
                icon: t.2,
                targetValue: t.3,
                trackingMethod: t.4,
                order: nonNegotiables.count + index
            )
            modelContext.insert(nn)
        }
        try? modelContext.save()
    }
}

// MARK: - NonNegotiableEditSheet

struct NonNegotiableEditSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    let editing: NonNegotiable?
    let existingCount: Int
    let onSave: (NonNegotiable) -> Void

    @State
    private var name: String
    @State
    private var selectedType: NonNegotiableType
    @State
    private var icon: String
    @State
    private var targetValue: Double
    @State
    private var trackingMethod: TrackingMethod
    @State
    private var activeDays: ActiveDays
    @State
    private var isActive: Bool
    @State
    private var showIconPicker = false

    private let maxNonNegotiables = 7

    init(
        editing: NonNegotiable? = nil,
        existingCount: Int,
        onSave: @escaping (NonNegotiable) -> Void
    ) {
        self.editing = editing
        self.existingCount = existingCount
        self.onSave = onSave

        _name = State(initialValue: editing?.name ?? "")
        _selectedType = State(initialValue: editing?.type ?? .custom)
        _icon = State(initialValue: editing?.icon ?? "star.fill")
        _targetValue = State(initialValue: editing?.targetValue ?? 1)
        _trackingMethod = State(initialValue: editing?.trackingMethod ?? .manual)
        _activeDays = State(initialValue: editing?.activeDays ?? .everyday)
        _isActive = State(initialValue: editing?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            List {
                // Name
                Section {
                    TextField("Name", text: $name)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .frame(minHeight: Tide.hit)
                } header: {
                    Text("Name").tideLabel(Tide.text3)
                }
                .tideListRow()

                // Type
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(NonNegotiableType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .font(Tide.body)
                    .frame(minHeight: Tide.hit)
                } header: {
                    Text("Type").tideLabel(Tide.text3)
                }
                .tideListRow()

                // Icon
                Section {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                            Spacer()
                            Image(systemName: icon)
                                .font(Tide.title2)
                                .foregroundStyle(mood.accent)
                                .accessibilityHidden(true)
                            Image(systemName: "chevron.right")
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose an icon")
                } header: {
                    Text("Icon").tideLabel(Tide.text3)
                }
                .tideListRow()

                // Target
                Section {
                    targetEditor
                } header: {
                    Text("Target").tideLabel(Tide.text3)
                } footer: {
                    Text(targetHelpText)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                .tideListRow()

                // Tracking
                Section {
                    Picker("Tracking", selection: $trackingMethod) {
                        Text("Manual").tag(TrackingMethod.manual)
                        Text("Timer").tag(TrackingMethod.timer)
                        Text("Whoop (Auto)").tag(TrackingMethod.autoWhoop)
                        Text("HealthKit (Auto)").tag(TrackingMethod.autoHealthkit)
                    }
                    .font(Tide.body)
                    .frame(minHeight: Tide.hit)
                } header: {
                    Text("Tracking method").tideLabel(Tide.text3)
                }
                .tideListRow()

                // Active days
                Section {
                    activeDaysPicker
                } header: {
                    Text("Active days").tideLabel(Tide.text3)
                }
                .tideListRow()

                // Active toggle (edit only)
                if editing != nil {
                    Section {
                        Toggle(isOn: $isActive) {
                            Text("Active")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                        }
                        .tint(mood.accent)
                        .frame(minHeight: Tide.hit)
                    }
                    .tideListRow()
                }
            }
            .tidePage()
            .navigationTitle(editing != nil ? "Edit Non-Negotiable" : "Add Non-Negotiable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: selectedType) { _, newType in
                icon = newType.defaultIcon
                applyTypeDefaults(newType)
            }
            .tideCovered(showIconPicker)
            .sheet(isPresented: $showIconPicker) {
                IconPickerSheet(selectedIcon: $icon)
            }
        }
    }

    // MARK: - Target Editor

    @ViewBuilder
    private var targetEditor: some View {
        switch selectedType {
        case .study:
            targetStepper("Duration: \(Int(targetValue)) min", range: 15 ... 480, step: 15)
        case .meals:
            targetStepper("Meals: \(Int(targetValue))", range: 1 ... 6, step: 1)
        case .train:
            HStack {
                Text("Sessions per day")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                Spacer()
                Text("\(Int(targetValue))")
                    .font(Tide.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Tide.text2)
            }
            .frame(minHeight: Tide.hit)
            .accessibilityElement(children: .combine)
        case .sleep:
            targetStepper("Hours: \(Int(targetValue))", range: 4 ... 12, step: 1)
        case .steps:
            targetStepper("Steps: \(Int(targetValue))", range: 1000 ... 30000, step: 1000)
        case .hydration:
            targetStepper("Glasses: \(Int(targetValue))", range: 1 ... 20, step: 1)
        case .custom:
            targetStepper("Target: \(Int(targetValue))", range: 1 ... 1000, step: 1)
        }
    }

    private func targetStepper(_ title: String, range: ClosedRange<Double>, step: Double) -> some View {
        Stepper(title, value: $targetValue, in: range, step: step)
            .font(Tide.body)
            .monospacedDigit()
            .foregroundStyle(Tide.text)
            .frame(minHeight: Tide.hit)
    }

    private var targetHelpText: String {
        switch selectedType {
        case .study: "Study time in minutes. Weekend targets are halved automatically."
        case .meals: "Number of meals to log per day."
        case .train: "Auto-tracked from Whoop or HealthKit."
        case .sleep: "Minimum hours of sleep from HealthKit."
        case .steps: "Daily step count from HealthKit."
        case .hydration: "Number of glasses of water per day."
        case .custom: "Set your own target value."
        }
    }

    // MARK: - Active Days Picker

    private var activeDaysPicker: some View {
        let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayValues: [ActiveDays] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        return HStack(spacing: Tide.s1) {
            ForEach(0 ..< 7, id: \.self) { index in
                let day = dayValues[index]
                let isOn = (activeDays.rawValue & day.rawValue) != 0

                Button {
                    activeDays.toggle(day)
                } label: {
                    Text(dayLabels[index])
                        .font(Tide.label)
                        .foregroundStyle(isOn ? Tide.ink : Tide.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .background(
                            isOn ? mood.accent : Tide.fill,
                            in: .rect(cornerRadius: Tide.controlRadius)
                        )
                        .contentShape(.rect(cornerRadius: Tide.controlRadius))
                }
                // Several buttons share one list row: plain keeps each tap separate.
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .animation(Tide.snap, value: activeDays.rawValue)
    }

    // MARK: - Type Defaults

    private func applyTypeDefaults(_ type: NonNegotiableType) {
        switch type {
        case .study:
            targetValue = 120
            trackingMethod = .timer
        case .train:
            targetValue = 1
            trackingMethod = .autoWhoop
        case .meals:
            targetValue = 3
            trackingMethod = .manual
        case .sleep:
            targetValue = 7
            trackingMethod = .autoHealthkit
        case .steps:
            targetValue = 10000
            trackingMethod = .autoHealthkit
        case .hydration:
            targetValue = 8
            trackingMethod = .manual
        case .custom:
            targetValue = 1
            trackingMethod = .manual
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            return
        }

        if let existing = editing {
            existing.name = trimmedName
            existing.type = selectedType
            existing.icon = icon
            existing.targetValue = targetValue
            existing.trackingMethod = trackingMethod
            existing.activeDays = activeDays
            existing.isActive = isActive
            onSave(existing)
        } else {
            let nn = NonNegotiable(
                name: trimmedName,
                type: selectedType,
                icon: icon,
                targetValue: targetValue,
                trackingMethod: trackingMethod,
                activeDays: activeDays
            )
            onSave(nn)
        }

        dismiss()
    }
}

// MARK: - IconPickerSheet

struct IconPickerSheet: View {
    @Binding
    var selectedIcon: String
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    private let categories: [(name: String, icons: [String])] = [
        ("Fitness", [
            "dumbbell.fill", "figure.run", "figure.walk", "figure.cooldown",
            "figure.strengthtraining.traditional", "figure.boxing",
            "sportscourt.fill", "trophy.fill",
        ]),
        ("Food & Drink", [
            "fork.knife", "cup.and.saucer.fill", "waterbottle.fill",
            "carrot.fill", "leaf.fill", "flame.fill",
        ]),
        ("Study", [
            "book.fill", "pencil", "graduationcap.fill", "brain.head.profile",
            "text.book.closed.fill", "doc.text.fill", "lightbulb.fill",
        ]),
        ("Health", [
            "heart.fill", "bed.double.fill", "moon.fill", "cross.case.fill",
            "waveform.path.ecg", "lungs.fill", "pills.fill",
        ]),
        ("Lifestyle", [
            "star.fill", "bolt.fill", "clock.fill", "calendar",
            "checkmark.seal.fill", "target", "flag.fill", "medal.fill",
        ]),
        ("Mindfulness", [
            "sparkles", "wind", "drop.fill", "sun.max.fill",
            "cloud.fill", "eye.fill", "hands.sparkles.fill",
        ]),
    ]

    private let columns = [GridItem(.adaptive(minimum: Tide.hit + Tide.s2), spacing: Tide.s3)]

    var body: some View {
        NavigationStack {
            TideScrollPage(spacing: Tide.s5) {
                ForEach(categories, id: \.name) { category in
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        TideSectionLabel(title: category.name)

                        LazyVGrid(columns: columns, spacing: Tide.s3) {
                            ForEach(category.icons, id: \.self) { iconName in
                                iconButton(iconName)
                            }
                        }
                        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                    }
                }
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func iconButton(_ iconName: String) -> some View {
        let isSelected = iconName == selectedIcon
        return Button {
            HapticManager.selection()
            selectedIcon = iconName
            dismiss()
        } label: {
            Image(systemName: iconName)
                .font(Tide.headline)
                .foregroundStyle(isSelected ? mood.accent : Tide.text2)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                .background(
                    isSelected ? mood.accent.opacity(0.2) : Tide.fill,
                    in: .rect(cornerRadius: Tide.controlRadius)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Tide.controlRadius)
                            .strokeBorder(mood.accent, lineWidth: Tide.hair)
                    }
                }
                .contentShape(.rect(cornerRadius: Tide.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(iconName.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - NonNegotiableType Display Name

extension NonNegotiableType {
    var displayName: String {
        switch self {
        case .study: "Study"
        case .train: "Training"
        case .meals: "Meals"
        case .sleep: "Sleep"
        case .steps: "Steps"
        case .hydration: "Hydration"
        case .custom: "Custom"
        }
    }
}
