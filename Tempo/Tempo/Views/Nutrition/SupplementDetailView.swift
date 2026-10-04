//
// SupplementDetailView.swift
// Tempo
//
// One supplement, everything about it: when you take it (today's resolved
// time + the timing/reminder controls), dose and stock with the reorder
// action, macros a tick counts, the "Took it" history and Delete. Opened from
// a Kitchen > Supplements row and from a row on Today's supplements card.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

struct SupplementDetailView: View {
    @Bindable var supplement: Supplement

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State private var refreshToken = 0
    @State private var showEdit = false
    @State private var showReorder = false
    @State private var confirmDelete = false

    var body: some View {
        let _ = refreshToken
        let dose = todayDose()
        let logs = recentLogs()
        let history = SupplementHistory.summary(logs: logs, supplementID: supplement.id, supplementName: supplement.name)
        let takenToday = SupplementIntakeStore.takenIDs(on: Date(), in: modelContext).contains(supplement.id)
        let daysLeft = SupplementReorderService.daysLeft(for: supplement, recentLogs: logs)
        let low = SupplementReorderService.needsReorder(for: supplement, recentLogs: logs)

        Form {
            hero
            tookItSection(takenToday: takenToday, dose: dose)
            scheduleSection(dose: dose)
            SupplementTimingSection(supplement: supplement)
            stockSection(daysLeft: daysLeft, low: low)
            macrosSection
            ingredientsSection
            historySection(history)
            Section {
                NavigationLink {
                    SupplementPicksView(supplement: supplement)
                } label: {
                    Label("Better products & where to buy", systemImage: "checkmark.seal")
                }
            }
            if let notes = supplement.userNotes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).font(.tempoBody)
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete from shelf", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("supplementDelete")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle(supplement.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityIdentifier("supplementEdit")
            }
        }
        .sheet(isPresented: $showEdit) {
            SupplementEditSheet(existing: supplement, prefillUPC: nil) { _ in
                try? modelContext.save()
                notify()
                refreshToken += 1
            }
        }
        .sheet(isPresented: $showReorder, onDismiss: { refreshToken += 1 }) {
            SupplementReorderSheet(supplement: supplement)
        }
        .confirmationDialog("Delete \(supplement.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                supplement.isArchived = true
                supplement.updatedAt = Date()
                try? modelContext.save()
                notify()
                HapticManager.warning()
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It leaves your shelf and your reminders. Your past history stays.")
        }
    }

    // MARK: - Sections

    private var hero: some View {
        Section {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: supplement.kind.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 52, height: 52)
                    .background(Color.tempoBgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if let brand = supplement.brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(.tempoModuleTag)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    Text(supplement.name)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text([supplement.kind.displayName, supplement.dosePerServing.isEmpty ? nil : supplement.dosePerServing]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func tookItSection(takenToday: Bool, dose: SupplementDose) -> some View {
        Section {
            Button {
                SupplementIntakeStore.toggle(supplementID: supplement.id, name: supplement.name, in: modelContext)
                notify()
                if !takenToday { HapticManager.success() } else { HapticManager.lightImpact() }
                refreshToken += 1
            } label: {
                Label(takenToday ? "Taken today. Tap to undo" : "Took it", systemImage: takenToday ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("supplementTookIt")
        } footer: {
            if !dose.take {
                Text("Your plan says skip it today. You can still log it.")
            }
        }
    }

    private func scheduleSection(dose: SupplementDose) -> some View {
        Section("Schedule") {
            LabeledContent("Today", value: dose.take ? "\(dose.timeLabel) · \(dose.timingLabel)" : "Skip today")
            LabeledContent("Why", value: dose.reason)
            LabeledContent("Dose", value: supplement.dosePerServing.isEmpty ? "Not set" : supplement.dosePerServing)
        }
    }

    private func stockSection(daysLeft: Int?, low: Bool) -> some View {
        Section("Stock") {
            LabeledContent("Left in container") {
                Text(supplement.servingsRemaining > 0 ? "\(Int(supplement.servingsRemaining)) servings" : "Not tracked")
            }
            if let daysLeft {
                LabeledContent("Lasts about") {
                    Text(daysLeft <= 0 ? "Out" : "\(daysLeft) days")
                        .foregroundStyle(low ? Color.tempoAmber : Color.tempoTextPrimary)
                }
            }
            if let per = supplement.servingsPerContainer, per > 0 {
                LabeledContent("Full container", value: "\(Int(per)) servings")
            }
            Button {
                showReorder = true
            } label: {
                Label(low ? "Reorder now" : "Reorder or restock", systemImage: "cart")
            }
            .foregroundStyle(low ? Color.tempoAmber : Color.tempoSignal)
            .accessibilityIdentifier("supplementReorder")
        }
    }

    @ViewBuilder
    private var macrosSection: some View {
        Section {
            if supplement.hasMacros {
                let m = supplement.macrosPerServing
                LabeledContent("Calories", value: "\(Int(m.calories.rounded())) kcal")
                LabeledContent("Protein", value: "\(Int(m.protein.rounded())) g")
                LabeledContent("Carbs", value: "\(Int(m.carbs.rounded())) g")
                LabeledContent("Fat", value: "\(Int(m.fat.rounded())) g")
            } else {
                Text("No calories or macros. Taking it adds nothing to your day.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        } header: {
            Text("Per serving")
        } footer: {
            if supplement.hasMacros {
                Text("Tick a dose and these count in today's totals.")
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if let text = supplement.ingredientsSummary, !text.isEmpty {
            Section("What's in it") {
                ForEach(Array(text.split(separator: "\n").map(String.init).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.tempoCaption1)
                }
            }
        }
    }

    private func historySection(_ history: SupplementHistory) -> some View {
        Section {
            if history.recent.isEmpty {
                Text("Not taken in the last \(history.windowDays) days.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(history.recent.prefix(10), id: \.self) { date in
                    Label(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()), systemImage: "checkmark.circle.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        } header: {
            Text("Took it · \(history.takenDays) of last \(history.windowDays) days")
        }
    }

    // MARK: - Data

    private func todayDose() -> SupplementDose {
        let context = SupplementDayContext.build(date: Date(), modelContext: modelContext)
        return SupplementScheduleEngine.dose(for: supplement, context: context)
    }

    private func recentLogs() -> [SupplementIntakeLog] {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(predicate: #Predicate<SupplementIntakeLog> { $0.day >= start })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func notify() {
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}
