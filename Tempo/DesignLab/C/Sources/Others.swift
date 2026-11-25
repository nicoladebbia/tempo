import SwiftUI

// MARK: Capture sheet (the "+")

/// Not a floating system sheet: a paper block that prints up from the bottom edge,
/// full bleed, and follows the finger back down.
struct CaptureSheet: View {
    var close: () -> Void
    @State private var drag: CGFloat = 0

    private let rows: [(title: String, detail: String, ink: Color)] = [
        ("MEAL", "SCAN · SNAP · SAY", Ink.moss),
        ("WATER", "+250 ML", Ink.cobalt),
        ("SET", "BENCH 95 × 6", Ink.acid),
        ("FOCUS", "25 MIN BLOCK", Ink.flare),
        ("WEIGHT", "LAST 81.4 KG", Ink.ink),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label11("LOG")
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .black))
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .frame(height: 56)

            ForEach(rows, id: \.title) { r in
                Button(action: close) {
                    HStack(alignment: .center, spacing: Grid.gap) {
                        Rectangle().fill(r.ink).frame(width: 12, height: 40)
                        Poster(r.title, 52).padding(.leading, 52 * 0.016)
                        Spacer(minLength: Grid.gap)
                        Label11(r.detail).opacity(0.6)
                    }
                    .frame(height: 76)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BlockPress())
                .overlay(alignment: .top) { Rule() }
            }
            Rule()
        }
        .foregroundStyle(Ink.ink)
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.margin)
        .background(Ink.paper.ignoresSafeArea(edges: .bottom))
        .offset(y: drag)
        .gesture(
            DragGesture()
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { v in
                    if v.predictedEndTranslation.height > 160 { close() }
                    withAnimation(.snappy(duration: 0.25)) { drag = 0 }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: true)
    }
}

// MARK: Train (simple)

struct TrainView: View {
    var start: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Label11("TRAIN"); Spacer(); Label11("WEEK 47") }
                    .padding(.top, Grid.gap)
                VStack(alignment: .leading, spacing: 10) {
                    Poster("PUSH", 168)
                    Poster("DAY", 168)
                }
                .foregroundStyle(Ink.acid)
                .padding(.top, Grid.block)
                HStack(spacing: Grid.u) {
                    ForEach(Array(Sample.weekPlan.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: Grid.u * 2) {
                            Label11(d.day)
                            Rectangle().fill(d.done ? Ink.paper : Ink.acid).frame(height: d.done ? 4 : 12)
                            Text(d.label.uppercased())
                                .font(.system(size: 9, weight: .bold).width(.expanded))
                                .lineLimit(1).fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(d.done ? 0.5 : 1)
                    }
                }
                .padding(.top, Grid.block)
                Button(action: start) {
                    HStack {
                        Poster("START", 36).padding(.leading, 36 * 0.016)
                        Spacer()
                        Label11("\(Sample.workoutTime) · \(Sample.workoutDuration.uppercased())")
                    }
                    .foregroundStyle(Ink.ink)
                    .padding(.horizontal, 20)
                    .frame(height: 72)
                    .background(Ink.acid)
                }
                .buttonStyle(BlockPress())
                .padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array(Sample.exercises.enumerated()), id: \.element.id) { i, e in
                        HStack(spacing: 0) {
                            Label11("\(i + 1)").frame(width: 28, alignment: .leading).opacity(0.6)
                            Text(e.name).font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Label11(e.target)
                        }
                        .frame(height: 52)
                        .overlay(alignment: .top) { Rule(weight: 1).opacity(0.25) }
                    }
                }
                .padding(.top, Grid.block)
            }
            .foregroundStyle(Ink.paper)
            .padding(.horizontal, Grid.margin)
            .padding(.bottom, Grid.block)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 56, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Ink.ink.ignoresSafeArea())
    }
}

// MARK: Arena (simple)

struct ArenaView: View {
    private let board: [(String, Int)] = [("MARTA", 9120), ("JONAS", 8710), ("NICO", Sample.xp), ("ELIF", 7940), ("TOBI", 7305)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Label11("ARENA"); Spacer(); Label11("LEVEL \(Sample.level)") }
                    .padding(.top, Grid.gap)
                HStack(alignment: .bottom, spacing: Grid.gap) {
                    Poster("#\(Sample.rank)", 232)
                    VStack(alignment: .leading, spacing: Grid.u) {
                        Label11("OF \(Sample.rankOf)")
                        Label11("THIS WEEK").opacity(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Grid.block)
                VStack(spacing: 0) {
                    ForEach(Array(board.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 0) {
                            Label11("\(i + 1)").frame(width: 28, alignment: .leading).opacity(0.7)
                            Poster(row.0, 30, weight: .heavy).padding(.leading, 30 * 0.016)
                            Spacer()
                            Label11("\(thousands(row.1)) XP")
                        }
                        .frame(height: 56)
                        .padding(.horizontal, Grid.gap)
                        .background(row.0 == "NICO" ? Ink.paper : .clear)
                        .foregroundStyle(row.0 == "NICO" ? Ink.cobalt : Ink.paper)
                        .overlay(alignment: .top) { Rule(weight: 1).opacity(0.3) }
                    }
                }
                .padding(.horizontal, -Grid.gap)
                .padding(.top, Grid.block)
            }
            .foregroundStyle(Ink.paper)
            .padding(.horizontal, Grid.margin)
            .padding(.bottom, Grid.block)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 56, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Ink.cobalt.ignoresSafeArea())
    }
}
