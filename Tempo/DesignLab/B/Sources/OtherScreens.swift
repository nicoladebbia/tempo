import SwiftUI

struct TrainView: View {
    let mood: Mood
    let start: () -> Void

    var body: some View {
        ZStack {
            TideBackground(mood: mood)
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("Week 47").tideLabel()
                        Text("Train").font(Tide.largeTitle).foregroundStyle(Tide.text)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(Sample.weekPlan.enumerated()), id: \.offset) { index, day in
                            let today = index == Sample.weekPlan.count - 1
                            VStack(spacing: 6) {
                                Text(day.day).font(Tide.caption).foregroundStyle(today ? mood.accent : Tide.text2)
                                ZStack {
                                    Circle().fill(today ? mood.accent : Tide.fill)
                                    if day.done {
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tide.text2)
                                    } else {
                                        Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Tide.ink)
                                    }
                                }
                                .frame(width: 36, height: 36)
                                Text(day.label).font(Tide.label).foregroundStyle(today ? Tide.text : Tide.text3)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .tideCard(padding: Tide.s4)

                    VStack(alignment: .leading, spacing: Tide.s4) {
                        HStack {
                            Text("Today").tideLabel()
                            Spacer()
                            Text(Sample.workoutTime).font(Tide.numeral(15, .semibold)).foregroundStyle(mood.accent)
                        }
                        Text(Sample.workoutName).font(Tide.title).foregroundStyle(Tide.text)
                        VStack(spacing: 0) {
                            ForEach(Sample.exercises) { exercise in
                                HStack {
                                    Text(exercise.name).font(Tide.body).foregroundStyle(Tide.text)
                                    Spacer()
                                    Text(exercise.target).font(Tide.numeral(15, .medium)).foregroundStyle(Tide.text2)
                                }
                                .frame(minHeight: Tide.hit)
                            }
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
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct ArenaView: View {
    let mood: Mood
    private let board: [(name: String, xp: Int, you: Bool)] = [
        ("Mara", 9120, false), ("Leo", 8740, false), ("You", Sample.xp, true), ("Sam", 7950, false), ("Ines", 7410, false)]

    var body: some View {
        ZStack {
            TideBackground(mood: mood)
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("This week").tideLabel()
                        Text("Arena").font(Tide.largeTitle).foregroundStyle(Tide.text)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: Tide.s2) {
                        Text("#\(Sample.rank)").font(Tide.numeral(60, .heavy)).foregroundStyle(Tide.text)
                        Text("of \(Sample.rankOf)").font(Tide.headline).foregroundStyle(Tide.text2)
                        Spacer()
                        Text("Level \(Sample.level)").font(Tide.bodyStrong).foregroundStyle(mood.accent)
                    }
                    .padding(.vertical, Tide.s2)
                    VStack(spacing: 0) {
                        ForEach(Array(board.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: Tide.s3) {
                                Text("\(index + 1)").font(Tide.numeral(15, .semibold))
                                    .foregroundStyle(row.you ? Tide.ink : Tide.text2)
                                    .frame(width: 28, height: 28)
                                    .background(row.you ? mood.accent : Tide.fill, in: .circle)
                                Text(row.name).font(row.you ? Tide.headline : Tide.body).foregroundStyle(Tide.text)
                                Spacer()
                                Text("\(row.xp.formatted()) XP").font(Tide.numeral(15, .semibold))
                                    .foregroundStyle(row.you ? mood.accent : Tide.text2)
                            }
                            .frame(minHeight: 52)
                            if index < board.count - 1 { Rectangle().fill(Tide.hairline).frame(height: 1).padding(.leading, 40) }
                        }
                    }
                    .tideCard(padding: Tide.s4)
                    Text("440 XP behind Leo. One logged session passes him.")
                        .font(Tide.body).foregroundStyle(Tide.text2).padding(.horizontal, Tide.s1)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct CaptureSheet: View {
    let day: DayModel
    let mood: Mood
    let startSession: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var done = 0

    private struct Action: Identifiable {
        let id: String, symbol: String, title: String, detail: String, color: Color
    }

    private var actions: [Action] {
        [
            .init(id: "meal", symbol: "fork.knife", title: "Meal", detail: "Search, type", color: mood.accent),
            .init(id: "scan", symbol: "barcode.viewfinder", title: "Scan", detail: "Barcode", color: mood.accent),
            .init(id: "photo", symbol: "camera.fill", title: "Photo", detail: "Snap a plate", color: mood.accent),
            .init(id: "water", symbol: "drop.fill", title: "Water", detail: "+250 ml", color: Tide.water),
            .init(id: "train", symbol: "dumbbell.fill", title: Sample.workoutName, detail: "Start now", color: Tide.ember),
            .init(id: "focus", symbol: "timer", title: "Focus", detail: "25 min", color: Tide.fat),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("Log").font(Tide.title).foregroundStyle(Tide.text)
            HStack(spacing: Tide.s3) {
                Image(systemName: "sparkles").font(Tide.headline).foregroundStyle(mood.accent)
                Text("Say it or type it: 2 eggs and toast").font(Tide.body).foregroundStyle(Tide.text2)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").font(Tide.headline).foregroundStyle(Tide.ink)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .background(mood.accent, in: .circle)
                    .accessibilityLabel("Dictate")
            }
            .padding(.leading, Tide.s5).padding(.trailing, 6)
            .frame(minHeight: 56)
            .background(Tide.fill, in: .capsule)
            .overlay(Capsule().strokeBorder(Tide.hairline, lineWidth: 1))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: 3), spacing: Tide.s3) {
                ForEach(actions) { action in
                    Button {
                        switch action.id {
                        case "water": day.addWater(); done += 1; dismiss()
                        case "train": startSession()
                        default: done += 1
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Tide.s2) {
                            Image(systemName: action.symbol).font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(action.color)
                                .frame(height: 24, alignment: .leading)
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title).font(Tide.headline).foregroundStyle(Tide.text).lineLimit(1)
                                Text(action.detail).font(Tide.caption).foregroundStyle(Tide.text2).lineLimit(1)
                            }
                        }
                        .padding(Tide.s3)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous).strokeBorder(Tide.hairline, lineWidth: 1))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.success, trigger: done)

            VStack(alignment: .leading, spacing: Tide.s2) {
                Text("Log again").tideLabel()
                ScrollView(.horizontal) {
                    HStack(spacing: Tide.s2) {
                        ForEach(Sample.recentFoods, id: \.self) { food in
                            Text(food).font(Tide.bodyStrong).foregroundStyle(Tide.text)
                                .padding(.horizontal, Tide.s4).frame(height: Tide.hit)
                                .background(Tide.fill, in: .capsule)
                        }
                    }
                    .padding(.horizontal, Tide.edge)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Tide.edge)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s8)
        .background(Tide.ink.opacity(0.45).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
