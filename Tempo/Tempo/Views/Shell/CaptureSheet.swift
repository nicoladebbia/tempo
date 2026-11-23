//
// CaptureSheet.swift
// Tempo
//
// The "+" sheet: the quickest way to log something from anywhere. It only
// opens flows that already exist; nothing here has logic of its own.
//

import SwiftData
import SwiftUI

/// What the capture sheet can start.
enum CaptureAction: String, CaseIterable, Identifiable {
    case meal
    case scan
    case workout
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meal: "Meal"
        case .scan: "Scan"
        case .workout: "Workout"
        case .focus: "Focus"
        }
    }

    var detail: String {
        switch self {
        case .meal: "Search, type or say it"
        case .scan: "Barcode, plate or label"
        case .workout: "Open today's session"
        case .focus: "Start the timer"
        }
    }

    var icon: String {
        switch self {
        case .meal: "fork.knife"
        case .scan: "barcode.viewfinder"
        case .workout: "dumbbell.fill"
        case .focus: "timer"
        }
    }
}

struct CaptureSheet: View {
    /// Called with the chosen action; the host closes the sheet and opens the flow.
    let onAction: (CaptureAction) -> Void

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood

    @State
    private var waterTotal = 0
    @State
    private var waterTaps = 0

    static let waterStepMl = 250

    private let columns = [GridItem(.flexible(), spacing: Tide.s3), GridItem(.flexible(), spacing: Tide.s3)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s4) {
                Text("Log").font(Tide.title).foregroundStyle(Tide.text)
                    .accessibilityAddTraits(.isHeader)

                waterRow

                LazyVGrid(columns: columns, spacing: Tide.s3) {
                    ForEach(CaptureAction.allCases) { action in
                        actionTile(action)
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s6)
            .padding(.bottom, Tide.s4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { reloadWater() }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWaterLogged)) { _ in
            reloadWater()
        }
        .sensoryFeedback(.success, trigger: waterTaps)
    }

    // MARK: Water

    private var waterRow: some View {
        HStack(spacing: Tide.s4) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(Tide.water)
                .frame(width: Tide.hit, height: Tide.hit)
            VStack(alignment: .leading, spacing: 2) {
                Text("Water today").tideLabel()
                TideNumber(waterTotal.formatted(), unit: "ml", size: 30)
            }
            Spacer(minLength: Tide.s2)
            Button {
                addWater()
            } label: {
                Text("+\(Self.waterStepMl) ml")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.ink)
                    .padding(.horizontal, Tide.s4)
                    .frame(minHeight: Tide.hit)
                    .background(Tide.water, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(Self.waterStepMl) millilitres of water")
            .accessibilityIdentifier("capture.water")
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    /// Same store the Fuel screen uses, so every screen shows the same total.
    private func addWater() {
        guard WaterStore(context: modelContext, healthKit: services.healthKit).add(ml: Self.waterStepMl) != nil else {
            return
        }
        waterTaps += 1
        reloadWater()
    }

    private func reloadWater() {
        withAnimation(Tide.snap) {
            waterTotal = WaterStore.total(in: modelContext)
        }
    }

    // MARK: Actions

    private func actionTile(_ action: CaptureAction) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundStyle(mood.accent)
                    .frame(height: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(Tide.headline).foregroundStyle(Tide.text)
                    Text(action.detail).font(Tide.caption).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.\(action.rawValue)")
    }
}

// MARK: - Host

/// Presents the capture sheet and, once it has closed, the flow that was picked.
private struct CaptureHost: ViewModifier {
    @Binding var isPresented: Bool
    let nutritionViewModel: NutritionTabViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood

    @State
    private var pending: CaptureAction?
    @State
    private var showMeal = false
    @State
    private var showScan = false
    @State
    private var focusModel: AccountabilityViewModel?
    @State
    private var showFocus = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: runPending) {
                CaptureSheet { action in
                    pending = action
                    isPresented = false
                }
                .environment(\.tideMood, mood)
                .presentationDetents([.height(430), .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showMeal, onDismiss: reloadFuel) {
                MealLoggingView()
            }
            .fullScreenCover(isPresented: $showScan, onDismiss: reloadFuel) {
                UniversalScanView(context: .today())
            }
            .fullScreenCover(isPresented: $showFocus) {
                if let focusModel {
                    FocusTimerView(viewModel: focusModel)
                }
            }
    }

    private func runPending() {
        guard let action = pending else {
            return
        }
        pending = nil
        switch action {
        case .meal: showMeal = true
        case .scan: showScan = true
        case .workout: services.appState.activeTab = .train
        case .focus:
            focusModel = AccountabilityViewModel(engine: services.accountabilityEngine)
            showFocus = true
        }
    }

    private func reloadFuel() {
        nutritionViewModel.loadToday(modelContext: modelContext)
    }
}

extension View {
    func captureHost(isPresented: Binding<Bool>, nutritionViewModel: NutritionTabViewModel) -> some View {
        modifier(CaptureHost(isPresented: isPresented, nutritionViewModel: nutritionViewModel))
    }
}
