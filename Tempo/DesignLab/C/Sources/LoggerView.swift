import SwiftUI

/// The live session. One exercise per screen, one tap per set.
struct LoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sets = Sample.exercises[0].sets
    @State private var weight = 95.0
    @State private var reps = 6
    @State private var resting = ProcessInfo.processInfo.arguments.contains("-rest")
    @State private var wipe: Double = ProcessInfo.processInfo.arguments.contains("-rest") ? 1 : 0
    @State private var restStart = Date()
    @State private var logged = 0

    private let ex = Sample.exercises[0]
    private var current: Int { sets.firstIndex { !$0.done } ?? sets.count }

    var body: some View {
        ZStack {
            Ink.ink.ignoresSafeArea()
            session
            rest
                .mask {
                    if reduceMotion {
                        Rectangle().opacity(wipe).ignoresSafeArea()
                    } else {
                        Rectangle().modifier(InkWipe(progress: wipe)).ignoresSafeArea()
                    }
                }
                .allowsHitTesting(resting)
                .accessibilityHidden(!resting)
        }
        .preferredColorScheme(resting ? .light : .dark)
        .sensoryFeedback(.impact(weight: .heavy), trigger: logged)
    }

    // MARK: Set entry

    private var session: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .black))
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                Spacer()
                Label11(Sample.elapsed)
                Spacer()
                Label11("1 / \(Sample.exercises.count)").frame(width: 44, height: 44, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines(ex.name.uppercased()), id: \.self) { Poster($0, 78) }
            }
            .foregroundStyle(Ink.acid)
            .padding(.top, Grid.gap)

            HStack {
                Label11("TARGET \(ex.target)")
                Spacer()
                Label11("BEST \(ex.lastBest.uppercased())")
            }
            .opacity(0.6)
            .padding(.top, 20)

            // Ledger
            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 0) {
                        Label11("\(i + 1)").frame(width: 28, alignment: .leading)
                        Poster("\(fmt(i == current ? weight : s.weight)) × \(i == current ? reps : s.reps)", 26, weight: .heavy)
                            .padding(.leading, 26 * 0.016)
                            .contentTransition(.numericText())
                        Spacer()
                        if s.done {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .black))
                        } else if i == current {
                            Label11("NOW").foregroundStyle(Ink.acid)
                        }
                    }
                    .opacity(s.done ? 0.45 : (i == current ? 1 : 0.7))
                    .frame(height: 40)
                    .overlay(alignment: .top) { Rule(weight: 1).opacity(0.25) }
                }
            }
            .padding(.top, 20)

            Spacer(minLength: Grid.gap)

            HStack(alignment: .bottom, spacing: Grid.margin) {
                dial(fmt(weight), "KG", minus: { weight -= 2.5 }, plus: { weight += 2.5 })
                dial("\(reps)", "REPS", minus: { reps = max(1, reps - 1) }, plus: { reps += 1 })
            }

            HStack {
                Label11("NEXT")
                Spacer()
                Label11("\(Sample.exercises[1].name.uppercased()) · \(Sample.exercises[1].target)")
            }
            .opacity(0.6)
            .padding(.top, 24)

            Button(action: log) {
                HStack {
                    Poster("LOG SET \(min(current + 1, sets.count))", 44).padding(.leading, 44 * 0.016)
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 26, weight: .black))
                }
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 20)
                .frame(height: 96)
                .background(Ink.acid)
            }
            .buttonStyle(BlockPress())
            .padding(.top, Grid.gap)
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.u * 2)
    }

    private func dial(_ value: String, _ unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Grid.gap) {
            HStack(alignment: .bottom, spacing: Grid.u * 2) {
                Poster(value, 104)
                    .contentTransition(.numericText())
                Label11(unit).opacity(0.6)
            }
            HStack(spacing: Grid.u) {
                step("minus", minus)
                step("plus", plus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { action() }
        } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .black))
                .frame(maxWidth: .infinity).frame(height: 48)
                .overlay { Rectangle().strokeBorder(lineWidth: 2) }
                .contentShape(Rectangle())
        }
        .buttonStyle(BlockPress())
        .sensoryFeedback(.selection, trigger: value(symbol))
    }

    private func value(_ symbol: String) -> Double { weight * 100 + Double(reps) }

    // MARK: Rest: the ink floods the page

    private var rest: some View {
        TimelineView(.periodic(from: restStart, by: 1)) { ctx in
            let remaining = max(0, Sample.restSeconds - Int(ctx.date.timeIntervalSince(restStart)))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label11("REST")
                    Spacer()
                    Label11("SET \(min(current, sets.count)) OF \(sets.count) DONE")
                }
                .frame(height: 44)

                Spacer()
                Poster(String(format: "%d:%02d", remaining / 60, remaining % 60), 216)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: remaining)
                FlatBar(value: Double(remaining) / Double(Sample.restSeconds), height: 12)
                    .padding(.top, 28)
                HStack {
                    Label11("UP NEXT")
                    Spacer()
                    Label11("\(fmt(weight)) KG × \(reps)")
                }
                .padding(.top, Grid.gap)
                Spacer()

                Button(action: endRest) {
                    HStack {
                        Poster("GO", 44).padding(.leading, 44 * 0.016)
                        Spacer()
                        Label11("SKIP REST")
                    }
                    .foregroundStyle(Ink.acid)
                    .padding(.horizontal, 20)
                    .frame(height: 96)
                    .background(Ink.ink)
                }
                .buttonStyle(BlockPress())
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, Grid.margin)
            .padding(.bottom, Grid.u * 2)
            .background(Ink.acid.ignoresSafeArea())
        }
    }

    // MARK: Actions

    private func log() {
        guard current < sets.count else { return }
        let i = current
        sets[i].weight = weight; sets[i].reps = reps; sets[i].done = true
        logged += 1
        restStart = Date()
        resting = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.42)) { wipe = 1 }
    }

    private func endRest() {
        resting = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.3)) { wipe = 0 }
    }

    private func fmt(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }

    /// Breaks a name into poster lines of at most 11 characters.
    private func lines(_ s: String) -> [String] {
        var out: [String] = []
        for word in s.split(separator: " ") {
            if let last = out.last, last.count + 1 + word.count <= 11 {
                out[out.count - 1] = last + " " + word
            } else {
                out.append(String(word))
            }
        }
        return out
    }
}

/// Animatable wrapper so the wipe shader follows SwiftUI animations and stays interruptible.
struct InkWipe: ViewModifier, @preconcurrency Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.visualEffect { c, proxy in
            c.colorEffect(ShaderLibrary.inkWipe(.float2(proxy.size), .float(progress), .float(9)))
        }
    }
}
