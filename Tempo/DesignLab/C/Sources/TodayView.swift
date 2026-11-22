import SwiftUI

struct TodayView: View {
    var start: () -> Void
    var go: (TabID) -> Void
    @State private var tasks = Sample.tasks.map { TaskRow(title: $0.title, done: $0.done) }

    struct TaskRow: Identifiable { let id = UUID(); let title: String; var done: Bool }
    private var left: Int { tasks.filter { !$0.done }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                bodyBlock
                fuelBlock
                lockBlock
                streakBlock
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 56, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .top)
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
        .background(VStack(spacing: 0) { Ink.flare; Ink.acid }.ignoresSafeArea())
    }

    // MARK: Hero: the score and the one thing to do

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label11("SUN 22 NOV")
                Spacer()
                Label11("WEEK 47 · DAY 7")
            }
            .padding(.top, Grid.gap)

            HStack(alignment: .bottom, spacing: Grid.gap) {
                Poster("\(Sample.dayScore)", 232)
                VStack(alignment: .leading, spacing: Grid.u) {
                    Label11("DAY SCORE")
                    Label11("OF 100")
                    Label11("+6 ON SAT").opacity(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Grid.block)

            Rule().padding(.top, 24)

            HStack(alignment: .firstTextBaseline) {
                Label11("NEXT")
                Spacer()
                Label11("\(Sample.workoutExerciseCount) EXERCISES · \(Sample.workoutDuration.uppercased())")
            }
            .padding(.top, Grid.gap)

            HStack(alignment: .bottom) {
                Poster(Sample.workoutName.uppercased(), 84)
                Spacer(minLength: Grid.gap)
                Poster(Sample.workoutTime, 40, weight: .heavy)
            }
            .padding(.top, 20)

            Button(action: start) {
                HStack {
                    Poster("START", 36).padding(.leading, 36 * 0.016)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 24, weight: .black))
                }
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 20)
                .frame(height: 72)
                .background(Ink.ink)
            }
            .buttonStyle(BlockPress())
            .padding(.top, 24)
        }
        .foregroundStyle(Ink.ink)
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.margin)
        .background(Ink.flare.printed(ink: Ink.ink.opacity(0.16), amount: 0.9))
    }

    // MARK: Body

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("BODY", "GREEN LIGHT")
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: Grid.gap) {
                    Poster("\(Sample.recovery)", 136)
                    Label11("RECOVERY")
                }
                Spacer(minLength: Grid.gap)
                VStack(alignment: .leading, spacing: Grid.gap) {
                    stat(Sample.sleepHours.uppercased(), "SLEEP")
                    stat("\(Sample.hrv) MS", "HRV")
                    stat("\(Sample.restingHR) BPM", "RESTING")
                }
                .frame(width: 148, alignment: .leading)
            }
            .padding(.top, 28)

            HStack(alignment: .bottom, spacing: Grid.u) {
                ForEach(Array(Sample.recoveryWeek.enumerated()), id: \.offset) { i, v in
                    Rectangle()
                        .fill(i == Sample.recoveryWeek.count - 1 ? Ink.flare : Ink.ink)
                        .frame(height: CGFloat(v) * 0.56)
                }
            }
            .frame(height: 48, alignment: .bottom)
            .padding(.top, 28)
            HStack {
                Label11("7 DAYS")
                Spacer()
                Label11("TODAY")
            }
            .opacity(0.6)
            .padding(.top, Grid.u * 2)
        }
        .foregroundStyle(Ink.ink)
        .padding(.horizontal, Grid.margin)
        .padding(.vertical, Grid.block)
        .background(Ink.paper)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Poster(value, 30, weight: .heavy)
            Label11(label).opacity(0.6)
        }
    }

    // MARK: Fuel

    private var fuelBlock: some View {
        Button { go(.fuel) } label: {
            VStack(alignment: .leading, spacing: 0) {
                header("FUEL", "NEXT 16:00")
                HStack(alignment: .bottom, spacing: Grid.gap) {
                    Poster(thousands(Sample.kcalTarget - Sample.kcalEaten), 136)
                    VStack(alignment: .leading, spacing: Grid.u) {
                        Label11("KCAL")
                        Label11("LEFT")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 28)
                FlatBar(value: Double(Sample.kcalEaten) / Double(Sample.kcalTarget), height: 12)
                    .padding(.top, 24)
                HStack {
                    Label11("PROTEIN \(Sample.protein.eaten) / \(Sample.protein.target) G")
                    Spacer()
                    Label11("WATER 1.75 / 3.3 L")
                }
                .padding(.top, Grid.gap)
            }
            .foregroundStyle(Ink.paper)
            .padding(.horizontal, Grid.margin)
            .padding(.vertical, Grid.block)
            .background(Ink.moss.printed(ink: Ink.ink.opacity(0.22), amount: 0.8, angle: 1.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(BlockPress())
    }

    // MARK: Lock

    private var lockBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("LOCKED", "\(tasks.count - left) OF \(tasks.count) DONE")
            HStack(alignment: .bottom, spacing: Grid.gap) {
                Poster("\(left)", 136)
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(Ink.acid)
                VStack(alignment: .leading, spacing: Grid.u) {
                    Label11("TO GO")
                    Label11("THEN THE EVENING IS YOURS").opacity(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 28)

            VStack(spacing: 0) {
                ForEach($tasks) { $t in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { t.done.toggle() }
                    } label: {
                        HStack(spacing: Grid.gap) {
                            ZStack {
                                Rectangle().strokeBorder(lineWidth: 2)
                                if t.done { Rectangle().padding(5) }
                            }
                            .frame(width: 20, height: 20)
                            Poster(t.title.uppercased(), 26, weight: .heavy)
                                .padding(.leading, 26 * 0.016)
                            Spacer()
                        }
                        .opacity(t.done ? 0.45 : 1)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rule(weight: 1).opacity(0.25) }
                }
            }
            .padding(.top, 24)
            .sensoryFeedback(.impact(weight: .medium), trigger: left)
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, Grid.margin)
        .padding(.top, Grid.block)
        .padding(.bottom, Grid.margin)
        .background(Ink.ink)
    }

    // MARK: Streak

    private var streakBlock: some View {
        Button { go(.arena) } label: {
            VStack(alignment: .leading, spacing: 0) {
                header("STREAK", "RANK \(Sample.rank) OF \(Sample.rankOf)")
                HStack(alignment: .bottom, spacing: Grid.gap) {
                    Poster("\(Sample.streakDays)", 200)
                    VStack(alignment: .leading, spacing: Grid.u) {
                        Label11("DAYS")
                        Label11("STRAIGHT")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 28)
                HStack(spacing: Grid.u) {
                    ForEach(Array(Sample.weekPlan.enumerated()), id: \.offset) { _, d in
                        ZStack {
                            Rectangle().strokeBorder(lineWidth: 2)
                            if d.done { Rectangle() }
                            Text(d.day)
                                .font(.system(size: 11, weight: .bold).width(.expanded))
                                .foregroundStyle(d.done ? Ink.acid : Ink.ink)
                        }
                        .frame(height: 32)
                    }
                }
                .padding(.top, 24)
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, Grid.margin)
            .padding(.top, Grid.block)
            .padding(.bottom, Grid.block)
            .background(Ink.acid)
            .contentShape(Rectangle())
        }
        .buttonStyle(BlockPress())
    }

    private func header(_ l: String, _ r: String) -> some View {
        VStack(spacing: Grid.gap) {
            Rule()
            HStack { Label11(l); Spacer(); Label11(r) }
        }
    }
}
