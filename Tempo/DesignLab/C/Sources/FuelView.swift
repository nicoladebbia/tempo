import SwiftUI

struct FuelView: View {
    @State private var water = Sample.waterMl
    @State private var meals = Sample.meals
    @State private var extraKcal = 0
    @State private var logTick = 0

    private var eaten: Int { meals.filter(\.eaten).reduce(0) { $0 + $1.kcal } + 120 + extraKcal }
    private var left: Int { max(0, Sample.kcalTarget - eaten) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                capture
                waterBlock
                mealsBlock
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 56, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .top)
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
        .background(VStack(spacing: 0) { Ink.moss; Ink.paper }.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: logTick)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label11("FUEL")
                Spacer()
                Label11("SUN 22 NOV")
            }
            .padding(.top, Grid.gap)

            HStack(alignment: .bottom, spacing: Grid.gap) {
                Poster(thousands(left), 168)
                    .contentTransition(.numericText(countsDown: true))
                VStack(alignment: .leading, spacing: Grid.u) {
                    Label11("KCAL")
                    Label11("LEFT")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Grid.block)

            FlatBar(value: Double(eaten) / Double(Sample.kcalTarget), height: 12)
                .padding(.top, 40)
            HStack {
                Label11("\(thousands(eaten)) EATEN")
                Spacer()
                Label11("\(thousands(Sample.kcalTarget)) TARGET")
            }
            .padding(.top, Grid.gap)

            VStack(spacing: 0) {
                macro(Sample.protein)
                macro(Sample.carbs)
                macro(Sample.fat)
            }
            .padding(.top, 28)
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, Grid.margin)
        .padding(.bottom, Grid.block)
        .background(Ink.moss.printed(ink: Ink.ink.opacity(0.22), amount: 0.9, angle: 1.05))
    }

    private func macro(_ m: Sample.Macro) -> some View {
        VStack(spacing: Grid.u * 2) {
            HStack(alignment: .bottom) {
                Label11(m.name.uppercased())
                Spacer()
                Poster("\(m.eaten)", 26, weight: .heavy)
                Label11("/ \(m.target) G").opacity(0.6)
            }
            FlatBar(value: Double(m.eaten) / Double(m.target), height: 4)
        }
        .frame(height: 52, alignment: .bottom)
    }

    // MARK: Capture

    private var capture: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label11("LOG IT")
                Spacer()
                Label11("ONE TAP").opacity(0.6)
            }
            HStack(spacing: Grid.u * 2) {
                tile("SEARCH", "magnifyingglass")
                tile("SCAN", "barcode.viewfinder")
                tile("PHOTO", "camera.fill")
                tile("VOICE", "waveform")
            }
            .padding(.top, Grid.gap)

            VStack(spacing: 0) {
                ForEach(Sample.recentFoods.prefix(3), id: \.self) { food in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { extraKcal += 140 }
                        logTick += 1
                    } label: {
                        HStack(spacing: Grid.gap) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .black))
                                .foregroundStyle(Ink.acid)
                            Text(food).font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Label11("AGAIN").opacity(0.6)
                        }
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rule(weight: 1).opacity(0.25) }
                }
            }
            .padding(.top, 20)
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, Grid.margin)
        .padding(.top, Grid.block)
        .padding(.bottom, Grid.margin)
        .background(Ink.ink)
    }

    private func tile(_ name: String, _ symbol: String) -> some View {
        Button {} label: {
            VStack(alignment: .leading) {
                Image(systemName: symbol).font(.system(size: 22, weight: .bold))
                Spacer()
                Text(name).font(.system(size: 10, weight: .bold).width(.expanded)).tracking(0.6)
            }
            .foregroundStyle(Ink.ink)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .background(Ink.acid)
        }
        .buttonStyle(BlockPress())
    }

    // MARK: Water

    private var waterBlock: some View {
        HStack(alignment: .bottom, spacing: Grid.gap) {
            VStack(alignment: .leading, spacing: Grid.gap) {
                Label11("WATER")
                Poster(String(format: "%.2f", Double(water) / 1000), 96)
                    .contentTransition(.numericText())
                Label11("OF 3.3 L").opacity(0.7)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy(duration: 0.25)) { water += 250 }
                logTick += 1
            } label: {
                VStack(alignment: .leading) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .black))
                    Spacer()
                    Poster("250", 40).padding(.leading, 40 * 0.016)
                    Label11("ML").padding(.top, Grid.u)
                }
                .foregroundStyle(Ink.cobalt)
                .padding(Grid.gap)
                .frame(width: 112, height: 132, alignment: .leading)
                .background(Ink.paper)
            }
            .buttonStyle(BlockPress())
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, Grid.margin)
        .padding(.vertical, Grid.block)
        .background(Ink.cobalt.printed(ink: Ink.ink.opacity(0.25), amount: 0.8, angle: 0.2))
    }

    // MARK: Meals

    private var mealsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule()
            HStack {
                Label11("TODAY'S PLATES")
                Spacer()
                Label11("\(meals.filter(\.eaten).count) OF \(meals.count)")
            }
            .padding(.top, Grid.gap)
            .padding(.bottom, 20)

            ForEach($meals) { $m in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { m.eaten.toggle() }
                    logTick += 1
                } label: {
                    HStack(alignment: .top, spacing: Grid.gap) {
                        Poster(m.time, 26, weight: .heavy)
                            .padding(.leading, 26 * 0.016)
                            .frame(width: 60, alignment: .leading)
                        VStack(alignment: .leading, spacing: Grid.u) {
                            Label11(m.slot.uppercased()).opacity(0.6)
                            Text(m.title)
                                .font(.system(size: 17, weight: .semibold))
                                .strikethrough(m.eaten)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Grid.u * 2)
                        VStack(alignment: .trailing, spacing: Grid.u) {
                            Label11("\(m.kcal)")
                            Label11("\(m.protein) P").opacity(0.6)
                        }
                    }
                    .opacity(m.eaten ? 0.45 : 1)
                    .padding(.vertical, 14)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rule(weight: 1).opacity(0.2) }
            }
        }
        .foregroundStyle(Ink.ink)
        .padding(.horizontal, Grid.margin)
        .padding(.top, Grid.block)
        .padding(.bottom, Grid.block)
        .background(Ink.paper)
    }
}
