//
// CaptureSheet.swift
// Tempo
//
// The "+" sheet: the quickest way to log something from anywhere. It only
// opens flows that already exist; nothing here has logic of its own.
//

import SwiftData
import SwiftUI

// MARK: - CaptureAction

/// What the capture sheet can start.
enum CaptureAction: String, CaseIterable, Identifiable {
    case meal
    case scan
    case workout
    case focus

    var id: String {
        rawValue
    }

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

// MARK: - CaptureSheet

struct CaptureSheet: View {
    /// Called with the chosen action; the host closes the sheet and opens the flow.
    let onAction: (CaptureAction) -> Void
    /// Called when "Ask Tempo" is tapped; the host closes the sheet and opens the chat.
    var onAsk: () -> Void = {}

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var waterTotal = 0
    @State
    private var waterTaps = 0
    /// "Added 250 ml" with its Undo. Hosted here, not on the shell, because
    /// this sheet covers the shell's own toast.
    @State
    private var toast: ToastData?

    nonisolated static let waterStepMl = 250

    /// Two tiles across; at accessibility sizes one full-width tile per row, so
    /// no title is broken mid-word.
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Tide.s3), GridItem(.flexible(), spacing: Tide.s3)]
    }

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

                askRow
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
        .tempoToast($toast)
        .firstTip("capture.sheet", "Tap +250 ml for a glass of water, or pick what you want to log.", systemImage: "plus.circle")
    }

    // MARK: Water

    private var waterRow: some View {
        // At accessibility sizes the button drops under the total and takes the
        // full width, so "+250 ml" never wraps inside its capsule.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return layout {
            HStack(spacing: Tide.s4) {
                TideIconTile(systemName: "drop.fill", tint: Tide.water, size: Tide.hit)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    TideLabel("Water today")
                    TideNumber(waterTotal.formatted(), unit: "ml", size: Tide.numeralSheet)
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            Button {
                addWater()
            } label: {
                Text("+\(Self.waterStepMl) ml")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Tide.s4)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: Tide.hit)
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
        let store = WaterStore(context: modelContext, healthKit: services.healthKit)
        guard let log = store.add(ml: Self.waterStepMl) else {
            toast = ToastData(message: "Couldn't save that. Try again.", style: .error)
            return
        }
        waterTaps += 1
        reloadWater()
        // Undo takes back exactly this entry, even if more were added since.
        let id = log.id
        toast = ToastData(
            message: "Added \(Self.waterStepMl) ml of water.",
            style: .success,
            actionTitle: "Undo"
        ) {
            if store.remove(id: id) {
                reloadWater()
            } else {
                toast = ToastData(message: "Couldn't undo that. Delete it from Water.", style: .error)
            }
        }
    }

    private func reloadWater() {
        withAnimation(Tide.snap) {
            waterTotal = WaterStore.total(in: modelContext)
        }
    }

    // MARK: Ask

    /// A full-width row under the tiles: it opens the Coach chat, which is no
    /// longer a tab of its own.
    private var askRow: some View {
        Button(action: onAsk) {
            HStack(alignment: .center, spacing: Tide.s3) {
                TideIconTile(systemName: "sparkles", tint: mood.accent, size: Tide.hit)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Ask Tempo").font(Tide.headline).foregroundStyle(Tide.text)
                    Text("Your day, your plan, your numbers").font(Tide.caption).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.right").font(Tide.label).foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.ask")
    }

    // MARK: Actions

    private func actionTile(_ action: CaptureAction) -> some View {
        // Icon beside the words at accessibility sizes (a full-width row), above
        // them in the two-across grid.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
        return Button {
            onAction(action)
        } label: {
            layout {
                TideIconTile(systemName: action.icon, tint: mood.accent, size: Tide.hit)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(action.title).font(Tide.headline).foregroundStyle(Tide.text)
                    Text(action.detail).font(Tide.caption).foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit * 2, alignment: .topLeading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.\(action.rawValue)")
    }
}

// MARK: - CaptureHost

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

    @Environment(\.dynamicTypeSize)
    private var typeSize

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
    @State
    private var pendingAsk = false
    @State
    private var showAsk = false

    func body(content: Content) -> some View {
        content
            .tideCovered(isPresented || showMeal || showScan || showFocus || showAsk)
            .sheet(isPresented: $isPresented, onDismiss: runPending) {
                CaptureSheet(
                    onAction: { action in
                        pending = action
                        isPresented = false
                    },
                    onAsk: {
                        pendingAsk = true
                        isPresented = false
                    }
                )
                .environment(\.tideMood, mood)
                // The short sheet cannot hold the tiles at accessibility sizes.
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(Tide.captureHeight), .large])
                .presentationDragIndicator(.visible)
                // Opaque field: plain glass let the page's colours (tab bar,
                // buttons) bleed through as a glow along the bottom edge.
                .presentationBackground {
                    TideBackground(energy: Tide.sheetEnergy).environment(\.tideMood, mood)
                }
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
            .sheet(isPresented: $showAsk) {
                CoachChat()
                    .environment(\.tideMood, mood)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
    }

    private func runPending() {
        if pendingAsk {
            pendingAsk = false
            showAsk = true
            return
        }
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
