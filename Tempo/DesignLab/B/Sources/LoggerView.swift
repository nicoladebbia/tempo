import SwiftUI

@MainActor @Observable
final class Session {
    var exercises = Sample.exercises
    var exerciseIndex = 0
    var isActive = LabScreen.requested == .logger || Lab.flag("-live")
    var restEnds: Date? = Lab.flag("-rest") ? Date().addingTimeInterval(96) : nil
    var restTotal: TimeInterval = TimeInterval(Sample.restSeconds)
    var loggedCount = 0
    let startedAt = Date().addingTimeInterval(-1122)

    var current: Sample.Exercise { exercises[exerciseIndex] }
    var setIndex: Int? { current.sets.firstIndex { !$0.done } }
    var next: Sample.Exercise? { exercises.indices.contains(exerciseIndex + 1) ? exercises[exerciseIndex + 1] : nil }

    func logSet() {
        guard let i = setIndex else { return }
        exercises[exerciseIndex].sets[i].done = true
        loggedCount += 1
        restTotal = TimeInterval(Sample.restSeconds)
        restEnds = Date().addingTimeInterval(restTotal)
        if setIndex == nil, let n = next, !n.sets.isEmpty { exerciseIndex += 1 }
    }

    func nudgeWeight(_ delta: Double) {
        guard let i = setIndex else { return }
        exercises[exerciseIndex].sets[i].weight = max(0, exercises[exerciseIndex].sets[i].weight + delta)
    }

    func nudgeReps(_ delta: Int) {
        guard let i = setIndex else { return }
        exercises[exerciseIndex].sets[i].reps = max(1, exercises[exerciseIndex].sets[i].reps + delta)
    }

    func addRest(_ seconds: TimeInterval) {
        guard let end = restEnds else { return }
        restEnds = end.addingTimeInterval(seconds)
        restTotal += seconds
    }
}

func kg(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}

struct LoggerView: View {
    let session: Session
    let mood: Mood
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        ZStack {
            TideBackground(mood: mood, energy: 0.7)
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    progress
                    titleBlock
                    editor
                    setList
                    if let next = session.next { nextRow(next) }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s3)
                .padding(.bottom, Tide.s4)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .sensoryFeedback(.success, trigger: session.loggedCount)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(Tide.headline).foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
            }
            .glassEffect(.regular.tint(Tide.ink.opacity(0.3)).interactive(), in: .circle)
            .accessibilityLabel("Minimise session")
            Spacer()
            VStack(spacing: 2) {
                Text(Sample.workoutName).tideLabel()
                Text(session.startedAt, style: .timer).font(Tide.numeral(17, .semibold)).foregroundStyle(Tide.text)
            }
            Spacer()
            Button {
                session.isActive = false
                dismiss()
            } label: {
                Text("Finish").font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .padding(.horizontal, Tide.s4).frame(height: Tide.hit)
            }
            .glassEffect(.regular.tint(Tide.ink.opacity(0.3)).interactive(), in: .capsule)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.vertical, Tide.s2)
    }

    private var progress: some View {
        HStack(spacing: Tide.s1) {
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                let total = max(exercise.sets.count, 1)
                let done = exercise.sets.filter(\.done).count
                Bar(progress: index < session.exerciseIndex ? 1 : Double(done) / Double(total),
                    color: mood.accent, height: 4)
                    .opacity(index <= session.exerciseIndex ? 1 : 0.6)
            }
        }
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Exercise \(session.exerciseIndex + 1) of \(session.exercises.count)").tideLabel(mood.accent)
            Text(session.current.name).font(Tide.title).foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Target \(session.current.target) · Best \(session.current.lastBest)")
                .font(Tide.body).foregroundStyle(Tide.text2)
        }
    }

    private var editor: some View {
        let set = session.setIndex.map { session.current.sets[$0] }
        return HStack(spacing: 0) {
            stepper(value: kg(set?.weight ?? 0), unit: "kg", numeric: set?.weight ?? 0,
                    minus: { session.nudgeWeight(-2.5) }, plus: { session.nudgeWeight(2.5) })
            Rectangle().fill(Tide.hairline).frame(width: 1, height: 112)
            stepper(value: "\(set?.reps ?? 0)", unit: "reps", numeric: Double(set?.reps ?? 0),
                    minus: { session.nudgeReps(-1) }, plus: { session.nudgeReps(1) })
        }
        .tideCard(padding: Tide.s5)
    }

    private func stepper(value: String, unit: String, numeric: Double,
                         minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: Tide.s3) {
            VStack(spacing: 0) {
                Text(value).font(Tide.numeral(48)).foregroundStyle(Tide.text)
                    .contentTransition(.numericText(value: numeric))
                    .lineLimit(1)
                Text(unit).tideLabel()
            }
            HStack(spacing: Tide.s2) {
                stepButton("minus", action: minus).accessibilityLabel("Less \(unit)")
                stepButton("plus", action: plus).accessibilityLabel("More \(unit)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.s3)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Tide.snap) { action() }
        } label: {
            Image(systemName: symbol).font(Tide.headline).foregroundStyle(Tide.text)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .background(Tide.fill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private var setList: some View {
        VStack(spacing: 0) {
            ForEach(Array(session.current.sets.enumerated()), id: \.element.id) { index, set in
                let isCurrent = index == session.setIndex
                HStack(spacing: Tide.s3) {
                    Text("\(index + 1)").font(Tide.numeral(15, .semibold))
                        .foregroundStyle(isCurrent ? Tide.ink : Tide.text2)
                        .frame(width: 28, height: 28)
                        .background(isCurrent ? mood.accent : Tide.fill, in: .circle)
                    Text("\(kg(set.weight)) kg × \(set.reps)").font(Tide.numeral(17, .semibold))
                        .foregroundStyle(set.done || isCurrent ? Tide.text : Tide.text3)
                        .contentTransition(.numericText())
                    Spacer()
                    if isCurrent {
                        Text("Now").tideLabel(mood.accent)
                    } else {
                        CheckDot(done: set.done, color: mood.accent)
                    }
                }
                .frame(minHeight: Tide.hit)
                if index < session.current.sets.count - 1 {
                    Rectangle().fill(Tide.hairline).frame(height: 1).padding(.leading, 40)
                }
            }
        }
        .tideCard(padding: Tide.s4)
    }

    private func nextRow(_ next: Sample.Exercise) -> some View {
        HStack(spacing: Tide.s3) {
            Text("Next").tideLabel()
            Text(next.name).font(Tide.bodyStrong).foregroundStyle(Tide.text)
            Spacer()
            Text(next.target).font(Tide.numeral(15, .medium)).foregroundStyle(Tide.text2)
        }
        .padding(.horizontal, Tide.s1)
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            VStack(spacing: Tide.s3) {
                if let end = session.restEnds, end > Date() {
                    restStrip(end: end)
                        .glassEffectID("rest", in: glass)
                        .transition(.opacity)
                }
                logButton.glassEffectID("log", in: glass)
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s3)
        .padding(.bottom, Tide.s2)
        .animation(reduceMotion ? nil : Tide.lively, value: session.restEnds)
    }

    private var logButton: some View {
        let set = session.setIndex.map { session.current.sets[$0] }
        return Button {
            withAnimation(reduceMotion ? nil : Tide.lively) { session.logSet() }
        } label: {
            HStack(spacing: Tide.s3) {
                Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy))
                Text(session.setIndex.map { "Log set \($0 + 1)" } ?? "Finish exercise").font(Tide.headline)
                Spacer()
                if let set {
                    Text("\(kg(set.weight)) kg × \(set.reps)").font(Tide.numeral(17, .semibold))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(Tide.ink)
            .padding(.horizontal, Tide.s6)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(mood.accent).interactive(), in: .capsule)
    }

    private func restStrip(end: Date) -> some View {
        HStack(spacing: Tide.s3) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let left = max(0, end.timeIntervalSince(context.date))
                Ring(progress: left / max(session.restTotal, 1), width: 4, colors: [Tide.water, Tide.water])
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Rest").tideLabel()
                Text(timerInterval: Date()...max(end, Date()), countsDown: true)
                    .font(Tide.numeral(22)).foregroundStyle(Tide.text)
            }
            Spacer()
            Button { session.addRest(15) } label: {
                Text("+15 s").font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .padding(.horizontal, Tide.s3).frame(height: Tide.hit)
                    .background(Tide.fill, in: .capsule)
            }
            .buttonStyle(.plain)
            Button { session.restEnds = nil } label: {
                Text("Skip").font(Tide.bodyStrong).foregroundStyle(Tide.text)
                    .padding(.horizontal, Tide.s3).frame(height: Tide.hit)
                    .background(Tide.fill, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Tide.s5)
        .padding(.trailing, Tide.s2)
        .frame(maxWidth: .infinity, minHeight: 60)
        .glassEffect(.regular.tint(Tide.ink.opacity(0.42)), in: .capsule)
    }
}
