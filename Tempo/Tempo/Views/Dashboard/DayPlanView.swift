//
// DayPlanView.swift
// Tempo
//
// Vertical 24h timeline rendering today's DayPlan. Per
// docs/INTELLIGENCE_REMEDIATION_PLAN.md §9 + LAUNCH_PUNCH_LIST.md §3.4.
//
// Tapping a block opens a detail sheet with the AI copy (or the title,
// when copy is nil). Non-fixed blocks (training/study/meal/recovery/free)
// can be dragged vertically; the drop snaps to 15-min cells, the block
// is clamped between wake (the first non-sleep boundary) and the sleep
// fence, and subsequent non-fixed blocks shift forward to make room.
// Fixed blocks (class/exam/work/football) and sleep are not draggable
// and cannot be displaced.
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

    /// Live drag preview: which block is being dragged, and the cumulative
    /// translation in minutes (already snapped to 15-min cells). Nil when
    /// no drag is in flight.
    @State private var dragState: (id: UUID, deltaMinutes: Int)?

    // 60 pixels per hour → a full day = 1440 pixels. Wide enough that
    // 15-min blocks (15 px) are still legible.
    private let pixelsPerMinute: CGFloat = 1.0
    private let snapMinutes: Int = 15

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
                            .accessibilityHidden(true)
                        Text("RE-PLAN")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color.tempoAmber)
                }
                .disabled(isRegenerating)
                .accessibilityLabel("Re-plan day")
                .accessibilityHint("Regenerates today's plan from your latest workouts, meals, and calendar.")
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
                    .offset(y: CGFloat(renderedStart(for: block)) * pixelsPerMinute)
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
        let isDraggable = isDraggable(block)
        let isActiveDrag = dragState?.id == block.id
        let displayStart = renderedStart(for: block)
        let displayEnd = displayStart + block.durationMinutes

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: block.kind.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(formatMinute(displayStart))–\(formatMinute(displayEnd))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if isDraggable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(20, CGFloat(block.durationMinutes) * pixelsPerMinute - 2), alignment: .top)
        .background(colorFor(kind: block.kind).opacity(isActiveDrag ? 0.32 : 0.18))
        .overlay(
            Rectangle()
                .fill(colorFor(kind: block.kind))
                .frame(width: 3)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .scaleEffect(isActiveDrag ? 1.02 : 1.0)
        .shadow(color: isActiveDrag ? .black.opacity(0.35) : .clear, radius: 6, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { selectedBlock = block }
        .gesture(isDraggable ? dragGesture(for: block) : nil)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: dragState?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(formatMinute(displayStart)) to \(formatMinute(displayEnd))")
        .accessibilityHint(isDraggable ? "Double-tap for details. Drag to reschedule." : "Double-tap for details.")
    }

    // MARK: - Drag interaction

    /// Class / exam / work / football come from the calendar; sleep is the
    /// fence at end-of-day. Neither is reflowable.
    private func isDraggable(_ block: TimeBlock) -> Bool {
        !block.kind.isFixed && block.kind != .sleep
    }

    /// Y position of a block accounting for the in-flight drag preview.
    private func renderedStart(for block: TimeBlock) -> Int {
        guard let drag = dragState, drag.id == block.id else {
            return block.startMinuteOfDay
        }
        return block.startMinuteOfDay + drag.deltaMinutes
    }

    private func dragGesture(for block: TimeBlock) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let snapped = snap(minutes: Int(value.translation.height / pixelsPerMinute))
                dragState = (block.id, snapped)
            }
            .onEnded { value in
                let snapped = snap(minutes: Int(value.translation.height / pixelsPerMinute))
                dragState = nil
                commitMove(block, deltaMinutes: snapped)
            }
    }

    private func snap(minutes: Int) -> Int {
        let rounded = Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
        return rounded
    }

    /// Apply a drag-end translation to `block` and cascade-shift subsequent
    /// non-fixed, non-sleep blocks forward to avoid overlaps. Fixed blocks
    /// and the sleep fence act as hard barriers: if the moved block can't
    /// fit before them, the move is clamped or refused.
    private func commitMove(_ block: TimeBlock, deltaMinutes delta: Int) {
        guard delta != 0, let plan = currentPlan else { return }
        let duration = block.durationMinutes
        let sorted = plan.blocks.sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay })

        // Sleep fence: the earliest sleep block boundary in the day (the
        // morning sleep tail ends at wake; the evening fence starts at
        // bedtime). We use the latest sleep block whose start is > noon
        // as the bedtime fence; fall back to 1440 if there isn't one.
        let bedtime = sorted
            .filter { $0.kind == .sleep && $0.startMinuteOfDay >= 12 * 60 }
            .map(\.startMinuteOfDay)
            .min() ?? (24 * 60)

        // Earliest legal start: the end of the morning sleep block, or 0.
        let wake = sorted
            .filter { $0.kind == .sleep && $0.endMinuteOfDay <= 12 * 60 }
            .map(\.endMinuteOfDay)
            .max() ?? 0

        let proposedStart = max(wake, min(block.startMinuteOfDay + delta, bedtime - duration))
        let proposedEnd = proposedStart + duration
        if proposedStart == block.startMinuteOfDay { return }

        // Snapshot original starts so we can roll back if reflow fails.
        let snapshot: [(TimeBlock, Int, Int)] = sorted.map { ($0, $0.startMinuteOfDay, $0.endMinuteOfDay) }

        // Apply the move first.
        block.startMinuteOfDay = proposedStart
        block.endMinuteOfDay = proposedEnd

        // Cascade-shift any subsequent non-fixed block that now overlaps.
        // We walk in order; each shift can in turn push the next one.
        var cursorEnd = proposedEnd
        for other in sorted where other.id != block.id {
            guard other.startMinuteOfDay < cursorEnd else { continue }
            if other.kind.isFixed || other.kind == .sleep {
                // Hard barrier — roll back the whole operation.
                for (b, s, e) in snapshot {
                    b.startMinuteOfDay = s
                    b.endMinuteOfDay = e
                }
                return
            }
            let dur = other.durationMinutes
            let newStart = cursorEnd
            let newEnd = newStart + dur
            if newEnd > bedtime {
                // Can't fit before the sleep fence — roll back.
                for (b, s, e) in snapshot {
                    b.startMinuteOfDay = s
                    b.endMinuteOfDay = e
                }
                return
            }
            other.startMinuteOfDay = newStart
            other.endMinuteOfDay = newEnd
            cursorEnd = newEnd
        }

        try? modelContext.save()
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
