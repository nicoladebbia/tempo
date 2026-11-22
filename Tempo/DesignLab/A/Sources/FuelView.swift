import SwiftUI

struct FuelView: View {
    var openCapture: () -> Void
    @State private var meals = Sample.meals
    @State private var water = Sample.waterMl
    @State private var extraKcal = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var eaten: Int { meals.filter(\.eaten).reduce(0) { $0 + $1.kcal } + 120 + extraKcal }
    private var left: Int { max(0, Sample.kcalTarget - eaten) }

    var body: some View {
        ScrollView {
            VStack(spacing: S.gap) {
                HStack {
                    SLabel(Sample.dateLine)
                    Spacer()
                    SLabel("Plan · week 47")
                }
                .frame(height: 44)
                hero
                captureBar
                waterPanel
                mealsPanel
            }
            .padding(.horizontal, S.edge)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SBackground(lightY: 0.2))
        .sensoryFeedback(.impact(weight: .light), trigger: water)
        .sensoryFeedback(.success, trigger: eaten)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(S.sweep.delay(0.05)) { shown = true } }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(left.formatted())
                    .font(.sNum(96, .medium)).foregroundStyle(S.text)
                    .contentTransition(.numericText(value: Double(left)))
                    .frame(height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    SLabel("kcal left", color: S.accent)
                    SLabel("\(eaten.formatted()) of \(Sample.kcalTarget.formatted())")
                }
            }
            LevelBar(progress: shown ? Double(eaten) / Double(Sample.kcalTarget) : 0, height: 6).padding(.top, 12)
            HStack(spacing: 16) {
                macro(Sample.protein); macro(Sample.carbs); macro(Sample.fat)
            }
            .padding(.top, 24)
        }
        .padding(.bottom, 12)
    }

    private func macro(_ m: Sample.Macro) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SLabel(m.name)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(m.eaten)").font(.sNum(28, .medium)).foregroundStyle(S.text)
                Text("/\(m.target) g").font(.sNum(13, .medium)).foregroundStyle(S.dim)
            }
            LevelBar(progress: shown ? Double(m.eaten) / Double(m.target) : 0, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Button(action: openCapture) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(S.dim)
                        Text("What did you eat?").font(.sBody).foregroundStyle(S.dim).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                ForEach(["barcode.viewfinder", "camera", "mic"], id: \.self) { icon in
                    Button(action: openCapture) {
                        Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(S.text)
                            .frame(width: 44, height: 56)
                    }
                    .accessibilityLabel(icon == "mic" ? "Log by voice" : icon == "camera" ? "Log by photo" : "Scan a barcode")
                }
            }
            .padding(.leading, 16).padding(.trailing, 6)
            .background(S.ink2, in: Capsule())
            .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Sample.recentFoods, id: \.self) { food in
                        Button { withAnimation(S.snap) { extraKcal += 120 } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(S.accent)
                                Text(food).font(.system(size: 14, weight: .medium)).foregroundStyle(S.text)
                            }
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(S.ink1, in: Capsule())
                            .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
                            .frame(height: 44)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, S.edge)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -S.edge)
        }
    }

    private var waterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SLabel("Water")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(water.formatted()).font(.sNum(28, .medium)).foregroundStyle(S.text)
                            .contentTransition(.numericText(value: Double(water)))
                        Text("/ \(Sample.waterTargetMl.formatted()) ml").font(.sNum(15, .medium)).foregroundStyle(S.dim)
                    }
                }
                Spacer()
                ForEach([250, 500], id: \.self) { ml in
                    Button { withAnimation(S.snap) { water += ml } } label: {
                        Text("+ \(ml)").font(.sNum(15, .semibold)).foregroundStyle(S.text)
                            .frame(width: 72, height: 48)
                            .background(S.ink2, in: Capsule())
                            .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Add \(ml) millilitres of water")
                }
            }
            LevelBar(progress: shown ? min(1, Double(water) / Double(Sample.waterTargetMl)) : 0)
        }
        .panel()
    }

    private var mealsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SLabel("Meals").padding(.bottom, 8)
            ForEach($meals) { $meal in
                Button { withAnimation(S.snap) { meal.eaten.toggle() } } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.title).font(.system(size: 16, weight: .medium)).foregroundStyle(meal.eaten ? S.dim : S.text)
                                .multilineTextAlignment(.leading)
                            Text("\(meal.time) · \(meal.kcal) kcal · \(meal.protein) g protein").font(.sNum(14, .medium)).foregroundStyle(meal.eaten ? S.faint : S.dim)
                        }
                        Spacer(minLength: 0)
                        CheckDot(on: meal.eaten)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.trailing, -10)
                if meal.id != meals.last?.id { Rectangle().fill(S.line).frame(height: 1) }
            }
        }
        .padding(.bottom, -8)
        .panel()
    }
}
