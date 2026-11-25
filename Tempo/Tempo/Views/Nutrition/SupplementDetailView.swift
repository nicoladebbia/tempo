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
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let dose = todayDose()
        let logs = recentLogs()
        let history = SupplementHistory.summary(logs: logs, supplementID: supplement.id, supplementName: supplement.name)
        let takenToday = SupplementIntakeStore.takenIDs(on: Date(), in: modelContext).contains(supplement.id)
        let daysLeft = SupplementReorderService.daysLeft(for: supplement, recentLogs: logs)
        let low = SupplementReorderService.needsReorder(for: supplement, recentLogs: logs)

        KitchenForm {
            hero(daysLeft: daysLeft, low: low, history: history)
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
                KitchenFormSection("Notes") {
                    Text(notes).font(Tide.body)
                }
            }
            Section {
                Button(role: .destructive) {
                    deleteFromShelf()
                } label: {
                    Label("Delete from shelf", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("supplementDelete")
            }
        }
        .kitchenPage()
        .kitchenBottomBar {
            tookItBar(takenToday: takenToday, dose: dose)
        }
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
        .tideCovered(showEdit || showReorder)
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
    }

    /// Takes it off the shelf and its reminders at once. Undo puts it back; its history was never touched.
    private func deleteFromShelf() {
        let id = supplement.id
        let name = supplement.name
        let context = modelContext
        supplement.isArchived = true
        supplement.updatedAt = Date()
        try? modelContext.save()
        notify()
        HapticManager.warning()
        dismiss()
        KitchenUndo.offer("\(name) deleted.") {
            KitchenUndo.restoreSupplement(id: id, in: context)
        }
    }

    // MARK: - Sections

    private func hero(daysLeft: Int?, low: Bool, history: SupplementHistory) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let strip: [Bool] = (0 ..< history.windowDays).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return history.recent.contains { calendar.isDate($0, inSameDayAs: day) }
        }
        let tone = low ? Tide.Kitchen.warn : Tide.text
        return Section {
            VStack(alignment: .leading, spacing: Tide.s5) {
                HStack(spacing: Tide.s4) {
                    Image(systemName: supplement.kind.icon)
                        .font(Tide.title2)
                        .foregroundStyle(mood.accent)
                        .frame(width: Tide.s10 + Tide.s3, height: Tide.s10 + Tide.s3)
                        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.tileRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        if let brand = supplement.brand, !brand.isEmpty {
                            Text(brand).tideLabel(Tide.text3)
                        }
                        Text(supplement.name)
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text)
                        Text([supplement.kind.displayName, supplement.dosePerServing.isEmpty ? nil : supplement.dosePerServing]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }
                if let daysLeft {
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        TideSectionLabel(title: "Stock", trailing: low ? "Reorder soon" : nil)
                        TideNumber(
                            daysLeft <= 0 ? "Out" : "\(daysLeft)",
                            unit: daysLeft <= 0 ? nil : "days left",
                            size: Tide.numeralL, relativeTo: .largeTitle, color: tone
                        )
                        if let per = supplement.servingsPerContainer, per > 0, supplement.servingsRemaining > 0 {
                            TideLevelBar(
                                progress: min(supplement.servingsRemaining / per, 1),
                                color: low ? Tide.Kitchen.warn : mood.accent,
                                height: Tide.bar
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideSectionLabel(title: "Last \(history.windowDays) days", trailing: "\(history.takenDays) taken")
                    KitchenHistoryStrip(days: strip)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// The one primary action, under the thumb. A tick here is what Today shows.
    private func tookItBar(takenToday: Bool, dose: SupplementDose) -> some View {
        VStack(spacing: Tide.s2) {
            if !dose.take {
                Text("Your plan says skip it today. You can still log it.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                KitchenUndo.toggleSupplementTaken(
                    supplementID: supplement.id, name: supplement.name, in: modelContext
                )
                if !takenToday { HapticManager.success() }
                refreshToken += 1
            } label: {
                Label(takenToday ? "Taken today. Tap to undo" : "Took it", systemImage: takenToday ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("supplementTookIt")
        }
    }

    private func scheduleSection(dose: SupplementDose) -> some View {
        KitchenFormSection("Schedule") {
            LabeledContent("Today", value: dose.take ? "\(dose.timeLabel) · \(dose.timingLabel)" : "Skip today")
            LabeledContent("Why", value: dose.reason)
            LabeledContent("Dose", value: supplement.dosePerServing.isEmpty ? "Not set" : supplement.dosePerServing)
        }
    }

    private func stockSection(daysLeft: Int?, low: Bool) -> some View {
        KitchenFormSection("Stock") {
            LabeledContent("Left in container") {
                Text(supplement.servingsRemaining > 0 ? FuelWords.count(Int(supplement.servingsRemaining), "serving") : "Not tracked")
            }
            if let daysLeft {
                LabeledContent("Lasts about") {
                    Text(daysLeft <= 0 ? "Out" : FuelWords.count(daysLeft, "day"))
                        .foregroundStyle(low ? Tide.Kitchen.warn : Tide.text)
                }
            }
            if let per = supplement.servingsPerContainer, per > 0 {
                LabeledContent("Full container", value: FuelWords.count(Int(per), "serving"))
            }
            Button {
                showReorder = true
            } label: {
                Label(low ? "Reorder now" : "Reorder or restock", systemImage: "cart")
            }
            .foregroundStyle(low ? Tide.Kitchen.warn : mood.accent)
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
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        } header: {
            Text("Per serving").tideLabel()
        } footer: {
            if supplement.hasMacros {
                Text("Tick a dose and these count in today's totals.")
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if let text = supplement.ingredientsSummary, !text.isEmpty {
            KitchenFormSection("What's in it") {
                ForEach(Array(text.split(separator: "\n").map(String.init).enumerated()), id: \.offset) { _, line in
                    Text(line).font(Tide.caption)
                }
            }
        }
    }

    private func historySection(_ history: SupplementHistory) -> some View {
        Section {
            if history.recent.isEmpty {
                Text("Not taken in the last \(history.windowDays) days.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                ForEach(history.recent.prefix(10), id: \.self) { date in
                    Label(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()), systemImage: "checkmark.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        } header: {
            Text("Took it · \(history.takenDays) of last \(history.windowDays) days").tideLabel()
        }
    }

    // MARK: - Data

    private func todayDose() -> SupplementDose {
        let context = SupplementDayContext.build(date: Date(), modelContext: modelContext)
        return SupplementScheduleEngine.dose(for: supplement, context: context)
    }

    private func recentLogs() -> [SupplementIntakeLog] {
        // Read here (body calls this) so bumping the token re-runs `body`:
        // the SwiftData fetch below is not observed.
        _ = refreshToken
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(predicate: #Predicate<SupplementIntakeLog> { $0.day >= start })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func notify() {
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}
