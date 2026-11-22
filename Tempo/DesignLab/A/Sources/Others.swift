import SwiftUI

struct CaptureSheet: View {
    var startWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var water = 0

    private struct Item: Identifiable { let id: String; let icon, title, detail: String }
    private let items: [Item] = [
        .init(id: "meal", icon: "fork.knife", title: "Meal", detail: "Search or say it"),
        .init(id: "scan", icon: "barcode.viewfinder", title: "Scan", detail: "Barcode, label"),
        .init(id: "water", icon: "drop.fill", title: "Water", detail: "+ 250 ml"),
        .init(id: "train", icon: "play.fill", title: "Push Day", detail: "Start now"),
        .init(id: "focus", icon: "timer", title: "Focus", detail: "45 min block"),
        .init(id: "weight", icon: "scalemass.fill", title: "Weigh in", detail: "Last 78.4 kg"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill").font(.system(size: 15, weight: .medium)).foregroundStyle(S.accent)
                Text("Say or type anything").font(.sBody).foregroundStyle(S.dim)
                Spacer()
                Image(systemName: "keyboard").font(.system(size: 15, weight: .medium)).foregroundStyle(S.dim)
            }
            .padding(.horizontal, 16).frame(height: 56)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(items) { item in
                    Button {
                        if item.id == "train" { startWorkout() } else if item.id == "water" { water += 1; dismiss() } else { dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.system(size: 17, weight: .medium))
                                .foregroundStyle(item.id == "train" ? S.onAccent : S.text)
                                .frame(width: 40, height: 40)
                                .background(item.id == "train" ? S.accent : Color.white.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.sHead).foregroundStyle(S.text).lineLimit(1)
                                Text(item.detail).font(.system(size: 13)).foregroundStyle(S.dim).lineLimit(1).minimumScaleFactor(0.9)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 68)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(S.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(.horizontal, S.edge)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(324)])
        .presentationBackground(S.ink1)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .light), trigger: water)
    }
}

struct TrainView: View {
    var startWorkout: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: S.gap) {
                HStack { SLabel("Week 47 · 5 of 6 done"); Spacer() }.frame(height: 44)
                HStack(spacing: 6) {
                    ForEach(Array(Sample.weekPlan.enumerated()), id: \.offset) { i, d in
                        let today = i == Sample.weekPlan.count - 1
                        VStack(spacing: 8) {
                            SLabel(d.day, color: today ? S.accent : S.dim)
                            Text(d.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(today ? S.text : S.dim).lineLimit(1).fixedSize()
                            Circle().fill(d.done ? S.accent : Color.white.opacity(0.14)).frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity).frame(height: 76)
                        .background(today ? S.ink2 : S.ink1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(today ? S.accent.opacity(0.5) : S.line, lineWidth: 1))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            SLabel("Today · \(Sample.workoutTime)", color: S.accent)
                            Text(Sample.workoutName).font(.sTitle).foregroundStyle(S.text)
                        }
                        Spacer()
                        Button(action: startWorkout) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                                Text("Start").font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(S.onAccent).padding(.horizontal, 24).frame(height: 56)
                            .background(S.accent, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(.bottom, 12)
                    ForEach(Array(Sample.exercises.enumerated()), id: \.element.id) { i, ex in
                        Rectangle().fill(S.line).frame(height: 1)
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.sNum(15, .semibold)).foregroundStyle(S.dim).frame(width: 20, alignment: .leading)
                            Text(ex.name).font(.system(size: 16, weight: .medium)).foregroundStyle(S.text)
                            Spacer(minLength: 8)
                            Text(ex.target).font(.sNum(15, .medium)).foregroundStyle(S.dim)
                        }
                        .frame(height: 48)
                    }
                }
                .padding(.bottom, -8)
                .panel()
            }
            .padding(.horizontal, S.edge).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SBackground(lightY: 0.2))
    }
}

struct ArenaView: View {
    private let board: [(rank: Int, name: String, xp: Int)] = [(1, "Marta", 9420), (2, "Leo", 8710), (3, "Nico", 8300), (4, "Dani", 7980), (5, "Sam", 7105)]
    var body: some View {
        ScrollView {
            VStack(spacing: S.gap) {
                HStack { SLabel("This week · 12 friends"); Spacer() }.frame(height: 44)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("#\(Sample.rank)").font(.sNum(96, .medium)).foregroundStyle(S.text).frame(height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        SLabel("of \(Sample.rankOf)", color: S.accent)
                        SLabel("Level \(Sample.level) · \(Sample.xp.formatted()) XP")
                    }
                    Spacer()
                }
                LevelBar(progress: 0.64, height: 6)
                HStack { SLabel("410 XP to pass Leo"); Spacer() }.padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(board.enumerated()), id: \.offset) { i, row in
                        let me = row.name == Sample.name
                        HStack(spacing: 12) {
                            Text("\(row.rank)").font(.sNum(17, .semibold)).foregroundStyle(me ? S.accent : S.dim).frame(width: 24, alignment: .leading)
                            Text(row.name).font(.system(size: 16, weight: me ? .semibold : .medium)).foregroundStyle(S.text)
                            Spacer()
                            Text(row.xp.formatted()).font(.sNum(17, .medium)).foregroundStyle(me ? S.text : S.dim)
                        }
                        .frame(height: 52)
                        if i < board.count - 1 { Rectangle().fill(S.line).frame(height: 1) }
                    }
                }
                .padding(.vertical, -12)
                .panel()
            }
            .padding(.horizontal, S.edge).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SBackground(lightY: 0.2))
    }
}
