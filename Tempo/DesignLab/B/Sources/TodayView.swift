import SwiftUI

struct TodayView: View {
    let day: DayModel
    let mood: Mood
    let start: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TideBackground(mood: mood)
            ScrollView {
                VStack(spacing: Tide.s4) {
                    header
                    hero
                    nextCard
                    HStack(spacing: Tide.s3) {
                        recoveryCard
                        sleepCard
                    }
                    fuelCard
                    unlockCard
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.1)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(Sample.dateLine).tideLabel()
                Text("Today").font(Tide.largeTitle).foregroundStyle(Tide.text)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(Tide.bodyStrong).foregroundStyle(Tide.ember)
                Text("\(Sample.streakDays)").font(Tide.numeral(17)).foregroundStyle(Tide.text)
            }
            .padding(.horizontal, Tide.s4)
            .frame(height: Tide.hit)
            .glassEffect(.regular.tint(Tide.ink.opacity(0.3)).interactive(), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Sample.streakDays) day streak")
        }
    }

    private var hero: some View {
        HStack(spacing: Tide.s6) {
            ZStack {
                Ring(progress: appeared ? Double(Lab.score) / 100 : 0, width: 14, colors: [mood.accent.opacity(0.55), mood.accent])
                VStack(spacing: 0) {
                    Text("\(appeared ? Lab.score : 0)")
                        .font(Tide.numeral(60, .heavy))
                        .foregroundStyle(Tide.text)
                        .contentTransition(.numericText(value: Double(Lab.score)))
                    Text("Day score").tideLabel()
                }
            }
            .frame(width: 156, height: 156)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day score \(Lab.score) of 100")

            VStack(alignment: .leading, spacing: Tide.s2) {
                Text(mood.word).font(Tide.title2).foregroundStyle(mood.accent)
                Text("Train and hit protein to close the day.")
                    .font(Tide.body).foregroundStyle(Tide.text.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Tide.s3)
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack {
                Text("Next up").tideLabel()
                Spacer()
                Text(Sample.workoutTime).font(Tide.numeral(15, .semibold)).foregroundStyle(mood.accent)
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(Sample.workoutName).font(Tide.title).foregroundStyle(Tide.text)
                Text("\(Sample.workoutExerciseCount) exercises · \(Sample.workoutDuration) · Bench 95 kg today")
                    .font(Tide.body).foregroundStyle(Tide.text2)
            }
            Button(action: start) {
                HStack(spacing: Tide.s2) {
                    Image(systemName: "play.fill").font(Tide.bodyStrong)
                    Text("Start session").font(Tide.headline)
                }
                .foregroundStyle(Tide.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(mood.accent)
        }
        .tideCard()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Recovery").tideLabel()
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Sample.recovery)").font(Tide.numeral(40)).foregroundStyle(Tide.text)
                Text("%").font(Tide.headline).foregroundStyle(Tide.text2)
                Spacer(minLength: Tide.s2)
                weekBars
            }
            Text("HRV \(Sample.hrv) ms · RHR \(Sample.restingHR)").font(Tide.caption).foregroundStyle(Tide.text2)
        }
        .tideCard(padding: Tide.s4)
        .accessibilityElement(children: .combine)
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(Sample.recoveryWeek.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index == Sample.recoveryWeek.count - 1 ? mood.accent : Color.white.opacity(0.28))
                    .frame(width: 5, height: appeared ? CGFloat(value) / 100 * 32 : 4)
            }
        }
        .frame(height: 32, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Sleep").tideLabel()
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("7").font(Tide.numeral(40)).foregroundStyle(Tide.text)
                Text("h").font(Tide.headline).foregroundStyle(Tide.text2)
                Text("40").font(Tide.numeral(40)).foregroundStyle(Tide.text).padding(.leading, 5)
                Text("m").font(Tide.headline).foregroundStyle(Tide.text2)
                Spacer(minLength: 0)
            }
            HStack(spacing: Tide.s2) {
                Text("Score \(Sample.sleepScore)").font(Tide.caption).foregroundStyle(Tide.text2).fixedSize()
                Bar(progress: appeared ? Double(Sample.sleepScore) / 100 : 0, color: Tide.fat, height: 4)
            }
        }
        .tideCard(padding: Tide.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep \(Sample.sleepHours), score \(Sample.sleepScore)")
    }

    private var fuelCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack {
                Text("Fuel").tideLabel()
                Spacer()
                Text("\((Sample.kcalTarget - day.kcalEaten).formatted()) kcal left").font(Tide.caption).foregroundStyle(Tide.text2)
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(alignment: .lastTextBaseline, spacing: Tide.s1) {
                    Text(day.kcalEaten.formatted()).font(Tide.numeral(28)).foregroundStyle(Tide.text)
                        .contentTransition(.numericText(value: Double(day.kcalEaten)))
                    Text("/ \(Sample.kcalTarget.formatted()) kcal").font(Tide.body).foregroundStyle(Tide.text2)
                }
                Bar(progress: appeared ? Double(day.kcalEaten) / Double(Sample.kcalTarget) : 0, color: mood.accent, height: 8)
            }
            HStack(spacing: Tide.s4) {
                macro(Sample.protein, Tide.protein)
                macro(Sample.carbs, Tide.carbs)
                macro(Sample.fat, Tide.fat)
            }
            Rectangle().fill(Tide.hairline).frame(height: 1)
            HStack(spacing: Tide.s3) {
                Image(systemName: "drop.fill").font(Tide.bodyStrong).foregroundStyle(Tide.water)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(day.waterMl.formatted()) ml").font(Tide.numeral(17, .semibold)).foregroundStyle(Tide.text)
                        .contentTransition(.numericText(value: Double(day.waterMl)))
                    Text("of \(Sample.waterTargetMl.formatted()) ml water").font(Tide.caption).foregroundStyle(Tide.text2)
                }
                Spacer()
                Button {
                    withAnimation(Tide.snap) { day.addWater() }
                } label: {
                    Text("+250 ml").font(Tide.bodyStrong).foregroundStyle(Tide.text)
                        .padding(.horizontal, Tide.s2).frame(minHeight: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .sensoryFeedback(.impact(weight: .light), trigger: day.waterMl)
            }
        }
        .tideCard()
    }

    private func macro(_ m: Sample.Macro, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.name).font(Tide.caption).foregroundStyle(Tide.text2)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(m.eaten)").font(Tide.numeral(17, .semibold)).foregroundStyle(Tide.text)
                Text("/\(m.target) g").font(Tide.caption).foregroundStyle(Tide.text3)
            }
            Bar(progress: appeared ? Double(m.eaten) / Double(m.target) : 0, color: color, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.name) \(m.eaten) of \(m.target) grams")
    }

    private var unlockCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack {
                Text("Unlock tonight").tideLabel()
                Spacer()
                HStack(spacing: 5) {
                    ForEach(day.tasks) { task in
                        Capsule().fill(task.done ? mood.accent : Color.white.opacity(0.2)).frame(width: 14, height: 5)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(day.tasksLeft == 0 ? "Unlocked" : "\(day.tasksLeft) to go")
                .font(Tide.title2).foregroundStyle(Tide.text)
                .contentTransition(.numericText(value: Double(day.tasksLeft)))
            VStack(spacing: 0) {
                ForEach(day.tasks) { task in
                    Button {
                        guard let i = day.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                        withAnimation(Tide.lively) { day.tasks[i].done.toggle() }
                    } label: {
                        HStack(spacing: Tide.s3) {
                            CheckDot(done: task.done, color: mood.accent)
                            Text(task.title).font(Tide.body)
                                .foregroundStyle(task.done ? Tide.text3 : Tide.text)
                                .strikethrough(task.done, color: Tide.text3)
                            Spacer()
                        }
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.success, trigger: day.tasksLeft)
            HStack(spacing: Tide.s2) {
                Image(systemName: "flame.fill").font(Tide.caption).foregroundStyle(Tide.ember)
                Text("\(Sample.streakDays)-day streak. Finish by midnight to keep it.")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
            }
        }
        .tideCard()
    }
}
