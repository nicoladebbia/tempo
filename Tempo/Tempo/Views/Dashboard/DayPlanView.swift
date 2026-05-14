//
// DayPlanView.swift
// Tempo
//
// Vertical 24h timeline rendering today's DayPlan. Per
// docs/INTELLIGENCE_REMEDIATION_PLAN.md §9.
//
// Read-only first pass — drag-to-reflow is deferred to a later commit.
// Tapping a block opens a detail sheet with the AI copy (or the title,
// when copy is nil).
//

import SwiftData
import SwiftUI

struct DayPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ServiceContainer.self) private var services

    @Query(sort: \DayPlan.generatedAt, order: .reverse)
    private var allPlans: [DayPlan]

    @State private var selectedBlock: TimeBlock?
    @State private var isRegenerating = false
    @State private var scheduler: DayPlanScheduler?

    // 60 pixels per hour → a full day = 1440 pixels. Wide enough that
    // 15-min blocks (15 px) are still legible.
    private let pixelsPerMinute: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                timeline
            }
        }
        .background(Color.tempoBgPrimary)
        .sheet(item: $selectedBlock) { block in
            BlockDetailSheet(block: block)
        }
        .task {
            // Lazy-init the scheduler on first appearance — it observes
            // foreground / EventKit change / replan-request notifications
            // for the lifetime of the view. Per
            // INTELLIGENCE_REMEDIATION_PLAN.md §9.3.
            if scheduler == nil {
                let service = DayPlannerService(
                    modelContext: modelContext,
                    calendar: services.calendar,
                    recoveryEngine: services.recoveryEngine,
                    apiClient: services.apiClient
                )
                scheduler = DayPlanScheduler(service: service)
                if currentPlan == nil {
                    await scheduler?.replanNow(reason: .initial)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DAY PLAN")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
            HStack {
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    Task { await regenerate() }
                } label: {
                    HStack(spacing: 6) {
                        if isRegenerating {
                            ProgressView().scaleEffect(0.7)
                        }
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("RE-PLAN")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color.tempoAmber)
                }
                .disabled(isRegenerating)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var timeline: some View {
        // Two columns: hour rail (fixed-width) + block lanes.
        HStack(alignment: .top, spacing: 0) {
            hourRail
            blockLanes
        }
        .padding(.horizontal, 12)
    }

    private var hourRail: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0 ..< 24, id: \.self) { hour in
                Text(formatHour(hour))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 36, height: 60, alignment: .topTrailing)
                    .padding(.trailing, 8)
            }
        }
    }

    private var blockLanes: some View {
        ZStack(alignment: .topLeading) {
            // Hour grid lines.
            VStack(spacing: 0) {
                ForEach(0 ..< 24, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                        .frame(height: 60, alignment: .top)
                }
            }
            // Blocks.
            ForEach(currentPlan?.blocks.sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay }) ?? []) { block in
                blockCard(block)
                    .offset(y: CGFloat(block.startMinuteOfDay) * pixelsPerMinute)
            }
            // Now marker.
            if currentPlan != nil {
                Rectangle()
                    .fill(Color.tempoAmber)
                    .frame(height: 1)
                    .offset(y: CGFloat(currentMinuteOfDay) * pixelsPerMinute)
            }
        }
        .frame(height: 1440 * pixelsPerMinute)
    }

    private func blockCard(_ block: TimeBlock) -> some View {
        Button {
            selectedBlock = block
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: block.kind.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(formatMinute(block.startMinuteOfDay))–\(formatMinute(block.endMinuteOfDay))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(20, CGFloat(block.durationMinutes) * pixelsPerMinute - 2), alignment: .top)
            .background(colorFor(kind: block.kind).opacity(0.18))
            .overlay(
                Rectangle()
                    .fill(colorFor(kind: block.kind))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity),
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    private var currentPlan: DayPlan? {
        let today = Calendar.current.startOfDay(for: Date())
        return allPlans.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
    }

    private var headerSubtitle: String {
        guard let plan = currentPlan else {
            return "No plan yet — tap RE-PLAN to generate."
        }
        let blocks = plan.blocks.count
        return "\(blocks) blocks · generated \(relativeTime(plan.generatedAt))"
    }

    private var currentMinuteOfDay: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        let planner = DayPlannerService(
            modelContext: modelContext,
            calendar: services.calendar,
            recoveryEngine: services.recoveryEngine,
            apiClient: services.apiClient
        )
        _ = await planner.replan(for: Date(), reason: .userRequested)
    }

    private func formatHour(_ h: Int) -> String {
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }

    private func formatMinute(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func colorFor(kind: TimeBlockKind) -> Color {
        switch kind {
        case .class, .exam: Color.blue
        case .work: Color.gray
        case .football: Color.green
        case .training: Color.red
        case .study: Color.purple
        case .meal: Color.orange
        case .recovery: Color.mint
        case .sleep: Color.indigo
        case .free: Color.white.opacity(0.3)
        }
    }
}

// MARK: - BlockDetailSheet

private struct BlockDetailSheet: View {
    let block: TimeBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: block.kind.symbolName)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.tempoAmber.opacity(0.3))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(formatMinute(block.startMinuteOfDay))–\(formatMinute(block.endMinuteOfDay)) · \(block.durationMinutes) min")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if let copy = block.copy, !copy.isEmpty {
                Text(copy)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("No AI rationale yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Button { dismiss() } label: {
                Text("Close")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.tempoAmber)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
            }
        }
        .padding(24)
        .background(Color.tempoBgPrimary.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func formatMinute(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }
}
