import SwiftUI
import SwiftData

// MARK: - NonNegotiable Setup/Edit View
// Per BUILD_PLAN step 10.5.
// Per MODULE_ACCOUNTABILITY.md — Setup flow for non-negotiables.

struct NonNegotiableSetupView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NonNegotiable.order) private var nonNegotiables: [NonNegotiable]

    @State private var showAddSheet = false
    @State private var editingItem: NonNegotiable?

    private let maxNonNegotiables = 7

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary.ignoresSafeArea()

                if nonNegotiables.isEmpty {
                    emptyState
                } else {
                    nonNegotiableList
                }
            }
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
        }
    }

    // MARK: - List

    private var nonNegotiableList: some View {
        List {
            // Active items
            Section {
                ForEach(nonNegotiables.filter(\.isActive)) { nn in
                    nonNegotiableRow(nn)
                }
                .onDelete { offsets in
                    deleteItems(at: offsets, from: nonNegotiables.filter(\.isActive))
                }
                .onMove { from, to in
                    moveItems(from: from, to: to)
                }
            } header: {
                HStack {
                    Text("ACTIVE")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Text("\(nonNegotiables.filter(\.isActive).count) / \(maxNonNegotiables)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            } footer: {
                if nonNegotiables.count >= maxNonNegotiables {
                    Text("Maximum \(maxNonNegotiables) non-negotiables. Keep it focused — too many dilutes accountability.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoAmber)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            // Inactive items
            let inactive = nonNegotiables.filter { !$0.isActive }
            if !inactive.isEmpty {
                Section {
                    ForEach(inactive) { nn in
                        nonNegotiableRow(nn)
                            .opacity(0.6)
                    }
                    .onDelete { offsets in
                        deleteItems(at: offsets, from: inactive)
                    }
                } header: {
                    Text("INACTIVE")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }

            // Default templates
            if nonNegotiables.isEmpty || nonNegotiables.count < 3 {
                templatesSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Row

    private func nonNegotiableRow(_ nn: NonNegotiable) -> some View {
        Button {
            editingItem = nn
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: nn.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(nn.isActive ? Color.tempoElectric : Color.tempoTextTertiary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(nn.name)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)

                    HStack(spacing: TempoSpacing.sm) {
                        Text(nn.type.displayName)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)

                        if let source = nn.integrationSourceName {
                            Text("·")
                                .foregroundStyle(Color.tempoTextTertiary)
                            Text(source)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoElectric)
                        }

                        Text("·")
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(targetDescription(nn))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func targetDescription(_ nn: NonNegotiable) -> String {
        switch nn.type {
        case .study:
            let hours = Int(nn.targetValue) / 60
            let mins = Int(nn.targetValue) % 60
            if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
            if hours > 0 { return "\(hours)h" }
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
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Set your non-negotiables")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.lg)

            Text("These are the things you MUST do every day. No excuses. No exceptions.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            Button("USE DEFAULT TEMPLATES") {
                addDefaultTemplates()
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)

            Button("CREATE FROM SCRATCH") {
                showAddSheet = true
            }
            .font(.tempoHeadline)
            .foregroundStyle(Color.tempoElectric)
            .padding(.top, TempoSpacing.md)

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        Section {
            Button {
                addDefaultTemplates()
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.tempoElectric)

                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Text("Add Default Templates")
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Study 2h · Train · 3 Meals · Sleep 7h")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        } header: {
            Text("QUICK START")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
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

    // Per MODULE_ACCOUNTABILITY.md — default templates.
    private func addDefaultTemplates() {
        let templates: [(String, NonNegotiableType, String, Double, TrackingMethod)] = [
            ("Study", .study, "book.fill", 120, .timer),
            ("Training", .train, "dumbbell.fill", 1, .autoWhoop),
            ("Meals", .meals, "fork.knife", 3, .autoNutritrack),
            ("Sleep", .sleep, "moon.fill", 7, .autoHealthkit),
        ]

        for (index, t) in templates.enumerated() {
            let existing = nonNegotiables.contains { $0.type == t.1 }
            guard !existing else { continue }

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

// MARK: - NonNegotiable Edit Sheet

struct NonNegotiableEditSheet: View {

    @Environment(\.dismiss) private var dismiss

    let editing: NonNegotiable?
    let existingCount: Int
    let onSave: (NonNegotiable) -> Void

    @State private var name: String
    @State private var selectedType: NonNegotiableType
    @State private var icon: String
    @State private var targetValue: Double
    @State private var trackingMethod: TrackingMethod
    @State private var activeDays: ActiveDays
    @State private var isActive: Bool

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
                        .font(.tempoBody)
                } header: {
                    Text("NAME")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Type
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(NonNegotiableType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .font(.tempoBody)
                } header: {
                    Text("TYPE")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Icon
                Section {
                    HStack {
                        Text("Icon")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundStyle(Color.tempoElectric)
                    }
                } header: {
                    Text("ICON")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Target
                Section {
                    targetEditor
                } header: {
                    Text("TARGET")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                } footer: {
                    Text(targetHelpText)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Tracking
                Section {
                    Picker("Tracking", selection: $trackingMethod) {
                        Text("Manual").tag(TrackingMethod.manual)
                        Text("Timer").tag(TrackingMethod.timer)
                        Text("Whoop (Auto)").tag(TrackingMethod.autoWhoop)
                        Text("NutriTrack (Auto)").tag(TrackingMethod.autoNutritrack)
                        Text("HealthKit (Auto)").tag(TrackingMethod.autoHealthkit)
                    }
                    .font(.tempoBody)
                } header: {
                    Text("TRACKING METHOD")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Active days
                Section {
                    activeDaysPicker
                } header: {
                    Text("ACTIVE DAYS")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Active toggle (edit only)
                if editing != nil {
                    Section {
                        Toggle(isOn: $isActive) {
                            Text("Active")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                        }
                        .tint(Color.tempoElectric)
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
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
        }
    }

    // MARK: - Target Editor

    @ViewBuilder
    private var targetEditor: some View {
        switch selectedType {
        case .study:
            Stepper(
                "Duration: \(Int(targetValue)) min",
                value: $targetValue,
                in: 15...480,
                step: 15
            )
            .font(.tempoBody)
        case .meals:
            Stepper(
                "Meals: \(Int(targetValue))",
                value: $targetValue,
                in: 1...6,
                step: 1
            )
            .font(.tempoBody)
        case .train:
            HStack {
                Text("Sessions per day")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(Int(targetValue))")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        case .sleep:
            Stepper(
                "Hours: \(Int(targetValue))",
                value: $targetValue,
                in: 4...12,
                step: 1
            )
            .font(.tempoBody)
        case .steps:
            Stepper(
                "Steps: \(Int(targetValue))",
                value: $targetValue,
                in: 1000...30000,
                step: 1000
            )
            .font(.tempoBody)
        case .hydration:
            Stepper(
                "Glasses: \(Int(targetValue))",
                value: $targetValue,
                in: 1...20,
                step: 1
            )
            .font(.tempoBody)
        case .custom:
            Stepper(
                "Target: \(Int(targetValue))",
                value: $targetValue,
                in: 1...1000,
                step: 1
            )
            .font(.tempoBody)
        }
    }

    private var targetHelpText: String {
        switch selectedType {
        case .study: return "Study time in minutes. Weekend targets are halved automatically."
        case .meals: return "Number of meals to log per day."
        case .train: return "Auto-tracked from Whoop or HealthKit."
        case .sleep: return "Minimum hours of sleep from HealthKit."
        case .steps: return "Daily step count from HealthKit."
        case .hydration: return "Number of glasses of water per day."
        case .custom: return "Set your own target value."
        }
    }

    // MARK: - Active Days Picker

    private var activeDaysPicker: some View {
        let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let dayValues: [ActiveDays] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        return HStack(spacing: TempoSpacing.sm) {
            ForEach(0..<7, id: \.self) { index in
                let day = dayValues[index]
                let isOn = (activeDays.rawValue & day.rawValue) != 0

                Button {
                    activeDays.toggle(day)
                } label: {
                    Text(dayLabels[index])
                        .font(.tempoCaption1)
                        .foregroundStyle(isOn ? .white : Color.tempoTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(isOn ? Color.tempoElectric : Color.tempoSurfaceElevated)
                        .clipShape(Circle())
                }
            }
        }
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
            trackingMethod = .autoNutritrack
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
        guard !trimmedName.isEmpty else { return }

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
