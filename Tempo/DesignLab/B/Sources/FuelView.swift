import SwiftUI

struct FuelView: View {
    let day: DayModel
    let mood: Mood
    @State private var appeared = false
    @State private var relogged = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var left: Int { Sample.kcalTarget - day.kcalEaten }

    var body: some View {
        ZStack {
            TideBackground(mood: mood)
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text(Sample.dateLine).tideLabel()
                        Text("Fuel").font(Tide.largeTitle).foregroundStyle(Tide.text)
                    }
                    hero
                    capture
                    recents
                    waterCard
                    mealsCard
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .lastTextBaseline, spacing: Tide.s2) {
                Text(left.formatted()).font(Tide.numeral(60, .heavy)).foregroundStyle(Tide.text)
                    .contentTransition(.numericText(value: Double(left)))
                Text("kcal left").font(Tide.headline).foregroundStyle(Tide.text2)
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                Bar(progress: appeared ? Double(day.kcalEaten) / Double(Sample.kcalTarget) : 0, color: mood.accent, height: 8)
                Text("\(day.kcalEaten.formatted()) of \(Sample.kcalTarget.formatted()) eaten")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
            }
            HStack(spacing: Tide.s4) {
                macro(Sample.protein, Tide.protein)
                macro(Sample.carbs, Tide.carbs)
                macro(Sample.fat, Tide.fat)
            }
        }
        .padding(.vertical, Tide.s2)
    }

    private func macro(_ m: Sample.Macro, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.name).font(Tide.caption).foregroundStyle(Tide.text2)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(m.eaten)").font(Tide.numeral(22)).foregroundStyle(Tide.text)
                Text("/\(m.target) g").font(Tide.caption).foregroundStyle(Tide.text3)
            }
            Bar(progress: appeared ? Double(m.eaten) / Double(m.target) : 0, color: color, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.name) \(m.eaten) of \(m.target) grams")
    }

    private var capture: some View {
        HStack(spacing: 0) {
            Button {} label: {
                HStack(spacing: Tide.s3) {
                    Image(systemName: "magnifyingglass").font(Tide.headline).foregroundStyle(Tide.text2)
                    Text("Search or describe").font(Tide.body).foregroundStyle(Tide.text2).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Tide.s5)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            ForEach([("barcode.viewfinder", "Scan barcode"), ("camera.fill", "Photo"), ("mic.fill", "Voice")], id: \.0) { symbol, name in
                Button {} label: {
                    Image(systemName: symbol).font(Tide.headline).foregroundStyle(mood.accent)
                        .frame(width: Tide.hit, height: 56)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
        }
        .padding(.trailing, Tide.s2)
        .glassEffect(.regular.tint(Tide.ink.opacity(0.42)).interactive(), in: .capsule)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Log again").tideLabel().padding(.leading, Tide.s1)
            ScrollView(.horizontal) {
                HStack(spacing: Tide.s2) {
                    ForEach(Sample.recentFoods, id: \.self) { food in
                        Button { relogged += 1 } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(mood.accent)
                                Text(food).font(Tide.bodyStrong).foregroundStyle(Tide.text)
                            }
                            .padding(.horizontal, Tide.s4)
                            .frame(height: Tide.hit)
                            .background(Tide.fill, in: .capsule)
                            .overlay(Capsule().strokeBorder(Tide.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Tide.edge)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Tide.edge)
            .sensoryFeedback(.success, trigger: relogged)
        }
    }

    private var waterCard: some View {
        HStack(spacing: Tide.s4) {
            WaterVial(level: appeared ? Double(day.waterMl) / Double(Sample.waterTargetMl) : 0)
                .frame(width: 44, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Water").tideLabel()
                HStack(alignment: .lastTextBaseline, spacing: Tide.s1) {
                    Text(day.waterMl.formatted()).font(Tide.numeral(28)).foregroundStyle(Tide.text)
                        .contentTransition(.numericText(value: Double(day.waterMl)))
                    Text("ml").font(Tide.headline).foregroundStyle(Tide.text2)
                }
                Text("of \(Sample.waterTargetMl.formatted()) ml").font(Tide.caption).foregroundStyle(Tide.text2)
            }
            Spacer(minLength: Tide.s2)
            Button {
                withAnimation(reduceMotion ? nil : Tide.lively) { day.addWater() }
            } label: {
                Text("+250 ml").font(Tide.headline).foregroundStyle(Tide.ink)
                    .padding(.horizontal, Tide.s2).frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Tide.water)
            .sensoryFeedback(.impact(weight: .medium), trigger: day.waterMl)
        }
        .tideCard(padding: Tide.s4)
    }

    private var mealsCard: some View {
        let nextID = day.meals.first { !$0.eaten }?.id
        return VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Meals").tideLabel()
            VStack(spacing: 0) {
                ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, meal in
                    HStack(spacing: Tide.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Tide.s2) {
                                Text(meal.time).font(Tide.numeral(13, .semibold)).foregroundStyle(Tide.text2)
                                Text(meal.slot).tideLabel(meal.id == nextID ? mood.accent : Tide.text2)
                                if meal.id == nextID {
                                    Text("Next").font(Tide.label).tracking(1.1).textCase(.uppercase)
                                        .foregroundStyle(Tide.ink)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(mood.accent, in: .capsule)
                                }
                            }
                            Text(meal.title).font(Tide.bodyStrong)
                                .foregroundStyle(meal.eaten ? Tide.text2 : Tide.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(meal.kcal) kcal · \(meal.protein) g protein").font(Tide.caption).foregroundStyle(Tide.text3)
                        }
                        Spacer(minLength: Tide.s2)
                        Button {
                            withAnimation(reduceMotion ? nil : Tide.lively) { day.meals[index].eaten.toggle() }
                        } label: {
                            CheckDot(done: meal.eaten, color: mood.accent, size: 28)
                                .frame(width: Tide.hit, height: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(meal.eaten ? "Undo \(meal.slot)" : "Mark \(meal.slot) eaten")
                    }
                    .padding(.vertical, Tide.s3)
                    if index < day.meals.count - 1 {
                        Rectangle().fill(Tide.hairline).frame(height: 1)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: day.kcalEaten)
        }
        .tideCard()
    }
}

struct WaterVial: View {
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .colorEffect(ShaderLibrary.waterFill(
                        .float2(geo.size), .float(context.date.timeIntervalSince(start)),
                        .float(min(max(level, 0), 1)),
                        .color(Tide.water), .color(Color(red: 0.10, green: 0.36, blue: 0.86))))
            }
        }
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
