import SwiftUI

@main
struct LabCApp: App {
    var body: some Scene {
        WindowGroup { Shell() }
    }
}

enum TabID: Hashable { case today, train, fuel, arena, plus }

struct Shell: View {
    @State private var tab: TabID = Shell.initialTab
    @State private var showPlus = ProcessInfo.processInfo.arguments.contains("-plus")
    @State private var liveSession = LabScreen.requested == .logger

    private static var initialTab: TabID {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-train") { return .train }
        if args.contains("-arena") { return .arena }
        return LabScreen.requested == .food ? .fuel : .today
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: TabID.today) {
                TodayView(start: { liveSession = true }, go: { tab = $0 }).toolbar(.hidden, for: .tabBar)
            }
            Tab(value: TabID.train) {
                TrainView(start: { liveSession = true }).toolbar(.hidden, for: .tabBar)
            }
            Tab(value: TabID.fuel) { FuelView().toolbar(.hidden, for: .tabBar) }
            Tab(value: TabID.arena) { ArenaView().toolbar(.hidden, for: .tabBar) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PosterBar(tab: $tab) { showPlus = true }
        }
        .overlay {
            ZStack(alignment: .bottom) {
                if showPlus {
                    Ink.ink.opacity(0.6).ignoresSafeArea()
                        .onTapGesture { showPlus = false }
                        .transition(.opacity)
                    CaptureSheet { showPlus = false }
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.snappy(duration: 0.28), value: showPlus)
        }
        .fullScreenCover(isPresented: $liveSession) { LoggerView() }
        .preferredColorScheme(tab == .train ? .dark : .light)
    }
}

/// The bar is printed, not floated: four words and one block. The "+" is always the same
/// acid square in the same corner, on every screen.
struct PosterBar: View {
    @Binding var tab: TabID
    var plus: () -> Void

    private let items: [(TabID, String)] = [(.today, "TODAY"), (.train, "TRAIN"), (.fuel, "FUEL"), (.arena, "ARENA")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { id, name in
                Button { tab = id } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Label11(name).opacity(tab == id ? 1 : 0.55)
                        Rectangle().fill(tab == id ? Ink.acid : .clear)
                            .frame(width: 24, height: 4)
                            .padding(.top, Grid.u * 2)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == id ? .isSelected : [])
            }
            Button(action: plus) {
                Image(systemName: "plus").font(.system(size: 22, weight: .black))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 72, height: 56)
                    .background(Ink.acid)
            }
            .buttonStyle(BlockPress())
            .accessibilityLabel("Log")
        }
        .foregroundStyle(Ink.paper)
        .background(Ink.ink.ignoresSafeArea(edges: .bottom))
        .animation(.snappy(duration: 0.18), value: tab)
        .sensoryFeedback(.selection, trigger: tab)
    }
}
