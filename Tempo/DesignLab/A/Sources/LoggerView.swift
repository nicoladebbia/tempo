import SwiftUI

struct LoggerView: View {
    var close: () -> Void
    @State private var sets = Sample.exercises[0].sets
    @State private var weight = 95.0
    @State private var reps = 6
    @State private var restEnd: Date? = ProcessInfo.processInfo.arguments.contains("-rest") ? Date().addingTimeInterval(96) : nil
    @State private var logged = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let exercise = Sample.exercises[0]
    private var current: Int { sets.firstIndex { !$0.done } ?? sets.count }
    private var finished: Bool { current >= sets.count }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            VStack(alignment: .leading, spacing: 0) {
                StepBar(total: Sample.exercises.count, done: 0, current: 0, currentColor: S.accent).padding(.top, 8)
                SLabel("Exercise 1 of \(Sample.exercises.count)").padding(.top, 20)
                Text(exercise.name).font(.sTitle).foregroundStyle(S.text).padding(.top, 6)
                Text("Target \(exercise.target) · last \(exercise.lastBest)").font(.sNote).foregroundStyle(S.dim).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)
            dial
            Spacer(minLength: 12)
            setRows
            Spacer(minLength: 12)
            nextRow
            action.padding(.top, 12)
        }
        .padding(.horizontal, S.edge)
        .padding(.bottom, 8)
        .background(SBackground(lightY: 0.42))
        .sensoryFeedback(.impact(weight: .heavy), trigger: logged)
        .sensoryFeedback(.selection, trigger: weight)
        .sensoryFeedback(.selection, trigger: reps)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(S.text)
                    .frame(width: 44, height: 44)
                    .background(S.ink2, in: Circle())
            }
            .accessibilityLabel("Minimise workout")
            Spacer()
            VStack(spacing: 2) {
                Text(Sample.elapsed).font(.sNum(20, .semibold)).foregroundStyle(S.text)
                SLabel(Sample.workoutName)
            }
            Spacer()
            Button(action: close) {
                Text("End").font(.system(size: 15, weight: .semibold)).foregroundStyle(S.text)
                    .frame(width: 60, height: 44)
                    .background(S.ink2, in: Capsule())
            }
        }
        .frame(height: 52)
    }

    private var dial: some View {
        HStack(alignment: .center, spacing: 0) {
            valueColumn(label: "kg", value: weight.formatted(.number.precision(.fractionLength(0...1))), numeric: weight,
                        minus: { weight = max(0, weight - 2.5) }, plus: { weight += 2.5 })
            Text("×").font(.sNum(32, .regular)).foregroundStyle(S.faint).frame(width: 24).offset(y: -30)
            valueColumn(label: "reps", value: "\(reps)", numeric: Double(reps),
                        minus: { reps = max(1, reps - 1) }, plus: { reps += 1 })
        }
    }

    private func valueColumn(label: String, value: String, numeric: Double, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.sNum(120, .medium))
                .foregroundStyle(S.text)
                .contentTransition(.numericText(value: numeric))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(height: 112)
            SLabel(label)
            HStack(spacing: 12) {
                stepper("minus", action: minus)
                stepper("plus", action: plus)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(S.snap) { action() } } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(S.text)
                .frame(width: 64, height: 48)
                .background(S.ink1, in: Capsule())
                .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .buttonRepeatBehavior(.enabled)
    }

    private var setRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                let isCurrent = i == current
                HStack(spacing: 0) {
                    Text("\(i + 1)").font(.sNum(15, .semibold)).foregroundStyle(isCurrent ? S.accent : S.dim).frame(width: 28, alignment: .leading)
                    Text(isCurrent ? "\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg × \(reps)" : "\(set.weight.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps)")
                        .font(.sNum(17, .medium)).foregroundStyle(set.done || isCurrent ? S.text : S.faint)
                    Spacer()
                    if set.done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(S.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else if isCurrent {
                        SLabel("Now", color: S.accent)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, S.pad)
                if i < sets.count - 1 { Rectangle().fill(S.line).frame(height: 1).padding(.horizontal, S.pad) }
            }
        }
        .panel(padding: 0)

    }

    private var nextRow: some View {
        HStack {
            SLabel("Up next")
            Spacer()
            Text("\(Sample.exercises[1].name) · \(Sample.exercises[1].target)").font(.sNote).foregroundStyle(S.dim).lineLimit(1)
        }
        .frame(height: 28)
    }

    @ViewBuilder private var action: some View {
        if let end = restEnd, end > Date() {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SLabel("Rest")
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.sNum(28, .semibold)).foregroundStyle(S.text)
                    }
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { ctx in
                        LevelBar(progress: max(0, end.timeIntervalSince(ctx.date) / Double(Sample.restSeconds)))
                    }
                }
                Button { withAnimation(S.snap) { restEnd = nil } } label: {
                    Text("Skip").font(.system(size: 17, weight: .semibold)).foregroundStyle(S.text)
                        .frame(width: 88, height: 56)
                        .background(S.ink2, in: Capsule())
                        .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.leading, 20).padding(.trailing, 8)
            .frame(height: 72)
            .background(S.ink1, in: Capsule())
            .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            Button(action: logSet) {
                HStack(spacing: 10) {
                    Image(systemName: finished ? "arrow.right" : "checkmark").font(.system(size: 16, weight: .bold))
                    Text(finished ? "Next exercise" : "Log set \(current + 1)").font(.system(size: 19, weight: .semibold))
                }
                .foregroundStyle(S.onAccent)
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(S.accent, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func logSet() {
        guard !finished else { return }
        logged += 1
        withAnimation(S.settle) {
            sets[current].weight = weight
            sets[current].reps = reps
            sets[current].done = true
            restEnd = Date().addingTimeInterval(Double(Sample.restSeconds))
        }
    }
}


