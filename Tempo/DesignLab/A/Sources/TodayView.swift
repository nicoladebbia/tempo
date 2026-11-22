import SwiftUI

struct TodayView: View {
    var startWorkout: () -> Void
    @State private var tasks = Sample.tasks.map { TaskItem(title: $0.title, done: $0.done) }
    @State private var water = Sample.waterMl
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct TaskItem: Identifiable { let id = UUID(); let title: String; var done: Bool }
    private var doneCount: Int { tasks.filter(\.done).count }

    var body: some View {
        ScrollView {
            VStack(spacing: S.gap) {
                header
                hero
                nextPanel
                lockPanel
                fuelPanel
                recoveryPanel
            }
            .padding(.horizontal, S.edge)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SBackground(lightY: 0.26))
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(S.sweep.delay(0.05)) { shown = true } }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            SLabel(Sample.dateLine)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(S.accent)
                Text("\(Sample.streakDays)").font(.sNum(17, .semibold)).foregroundStyle(S.text)
                SLabel("days")
            }
            .frame(height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Sample.streakDays) day streak")
        }
        .frame(height: 44)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { ctx in
                    SignalRing(progress: shown ? Double(Sample.dayScore) / 100 : 0,
                               time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
                }
                .frame(width: 350, height: 350)
                VStack(spacing: 0) {
                    SLabel("Day score")
                    Text("\(shown ? Sample.dayScore : 0)")
                        .font(.sNum(112, .medium))
                        .foregroundStyle(S.text)
                        .contentTransition(.numericText(value: Double(shown ? Sample.dayScore : 0)))
                        .frame(height: 112)
                    SLabel("+6 vs 7-day", color: S.accent)
                }
                .offset(y: -2)
            }
            .frame(height: 284)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day score \(Sample.dayScore) of 100")

            HStack(spacing: 0) {
                readout("Recovery", "\(Sample.recovery)", "%")
                divider
                readout("Sleep", Sample.sleepHours.replacingOccurrences(of: "h ", with: ":").replacingOccurrences(of: "m", with: ""), "h")
                divider
                readout("Strain", String(format: "%.1f", Sample.strain), "")
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }

    private var divider: some View { Rectangle().fill(S.line).frame(width: 1, height: 32) }

    private func readout(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.sNum(28, .medium)).foregroundStyle(S.text)
                if !unit.isEmpty { Text(unit).font(.sNum(15, .medium)).foregroundStyle(S.dim) }
            }
            SLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private var nextPanel: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SLabel("Next · \(Sample.workoutTime)", color: S.accent)
                Text(Sample.workoutName).font(.sTitle).foregroundStyle(S.text)
                Text("\(Sample.workoutExerciseCount) exercises · \(Sample.workoutDuration)").font(.sNote).foregroundStyle(S.dim)
            }
            Spacer(minLength: 0)
            Button(action: startWorkout) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                    Text("Start").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(S.onAccent)
                .padding(.horizontal, 24)
                .frame(height: 56)
                .background(S.accent, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .panel()
    }

    private var lockPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SLabel("Locked")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(tasks.count - doneCount)").font(.sNum(22, .semibold)).foregroundStyle(S.text)
                        .contentTransition(.numericText(value: Double(tasks.count - doneCount)))
                    SLabel("to unlock")
                }
            }
            StepBar(total: tasks.count, done: doneCount).padding(.top, 12).padding(.bottom, 8)
            ForEach($tasks) { $task in
                Button {
                    withAnimation(S.snap) { task.done.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        CheckDot(on: task.done)
                        Text(task.title).font(.sBody).foregroundStyle(task.done ? S.dim : S.text)
                        Spacer()
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.leading, -10)
            }
        }
        .padding(.bottom, -8)
        .panel()
        .sensoryFeedback(.success, trigger: doneCount)
    }

    private var fuelPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SLabel("Fuel")
                Spacer()
                SLabel("\(Sample.kcalTarget - Sample.kcalEaten) kcal left")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Sample.kcalEaten.formatted()).font(.sNum(44, .medium)).foregroundStyle(S.text)
                Text("/ \(Sample.kcalTarget.formatted()) kcal").font(.sNum(17, .medium)).foregroundStyle(S.dim)
            }
            .padding(.top, 8)
            LevelBar(progress: shown ? Double(Sample.kcalEaten) / Double(Sample.kcalTarget) : 0).padding(.top, 8)
            HStack(spacing: 16) {
                macro(Sample.protein); macro(Sample.carbs); macro(Sample.fat)
            }
            .padding(.top, 20)
            Rectangle().fill(S.line).frame(height: 1).padding(.top, 16)
            HStack(spacing: 12) {
                Image(systemName: "drop.fill").font(.system(size: 14)).foregroundStyle(S.dim).frame(width: 20)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(water.formatted()).font(.sNum(20, .medium)).foregroundStyle(S.text)
                        .contentTransition(.numericText(value: Double(water)))
                    Text("/ \(Sample.waterTargetMl.formatted()) ml").font(.sNum(15, .medium)).foregroundStyle(S.dim)
                }
                Spacer()
                Button { withAnimation(S.snap) { water += 250 } } label: {
                    Text("+ 250").font(.sNum(15, .semibold)).foregroundStyle(S.text)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(S.ink2, in: Capsule())
                        .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Add 250 millilitres of water")
            }
            .padding(.top, 12)
        }
        .panel()
        .sensoryFeedback(.impact(weight: .light), trigger: water)
    }

    private func macro(_ m: Sample.Macro) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(m.eaten)").font(.sNum(20, .medium)).foregroundStyle(S.text)
                Text("/\(m.target) g").font(.sNum(13, .medium)).foregroundStyle(S.dim)
            }
            LevelBar(progress: shown ? Double(m.eaten) / Double(m.target) : 0, height: 3)
            SLabel(m.name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recoveryPanel: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SLabel("Recovery · 7 days")
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(Sample.recoveryWeek.enumerated()), id: \.offset) { i, v in
                        let last = i == Sample.recoveryWeek.count - 1
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(last ? S.accent : Color.white.opacity(0.16))
                            .frame(width: 14, height: shown ? CGFloat(v) * 0.56 : 2)
                    }
                }
                .frame(height: 48, alignment: .bottom)
            }
            Spacer(minLength: 0)
            stat("\(Sample.hrv)", "ms", "HRV")
            stat("\(Sample.restingHR)", "bpm", "Rest HR")
        }
        .panel()
    }

    private func stat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.sNum(28, .medium)).foregroundStyle(S.text)
                Text(unit).font(.sNum(13, .medium)).foregroundStyle(S.dim)
            }
            SLabel(label)
        }
    }
}
