//
// PhotoAnalysisView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI
import UIKit

// MARK: - PhotoAnalysisView

// Camera capture + AI-powered food identification.
// Per DESIGN_SYSTEM.md — all tokens, confidence badges, editable items.

struct PhotoAnalysisView: View {
    /// Set when embedded in the scanner: cancelling the camera hands control
    /// back to it (mode chips) instead of dismissing the whole screen.
    var onCameraCancelled: (() -> Void)?
    var onItemsConfirmed: (([FoodItem]) -> Void)?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var capturedImage: UIImage?
    @State
    private var showCamera = true
    @State
    private var analysisState: AnalysisState = .idle
    @State
    private var identifiedItems: [AnalyzedFoodItem] = []
    /// When set, presents the alternatives sheet for the item with this ID
    /// so the user can swap the model's best-guess identification for one
    /// of the ranked candidates. Nil = sheet closed.
    @State
    private var alternativesItemID: UUID?
    /// Row being renamed (alert with a text field); nil = none.
    @State
    private var renameItemID: UUID?
    @State
    private var renameText = ""
    @State
    private var showAddItem = false

    private enum AnalysisState {
        case idle
        case analyzing
        case complete
        case error(String)
        /// Pro / AI-off: the card offers the fix.
        case blocked(AIBlocker)
    }

    // MARK: - Body

    /// Embedded in UniversalScanView's NavigationStack (Meal photo mode): a
    /// plain `Group`, so the title/toolbar attach to the scanner's stack.
    var body: some View {
        ZStack {
            Color.tempoBgPrimary
                .ignoresSafeArea()

            if showCamera, capturedImage == nil {
                // Camera capture
                CameraPickerView(image: $capturedImage) {
                    if let onCameraCancelled {
                        onCameraCancelled()
                    } else {
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            } else if let image = capturedImage {
                // Analysis view
                analysisContent(image: image)
            }
        }
        .navigationTitle("Photo Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if capturedImage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Retake") {
                        capturedImage = nil
                        showCamera = true
                        identifiedItems = []
                        analysisState = .idle
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .onChange(of: capturedImage) { _, newValue in
            if newValue != nil {
                showCamera = false
                analyzePhoto()
            }
        }
        // Alternatives picker — appears when the user taps "Not right?"
        // on a row that has model-returned candidates. Swap fires
        // applyAlternative(...) which mutates the row in-place.
        .sheet(item: Binding<AlternativesSheetPayload?>(
            get: {
                guard let id = alternativesItemID,
                      let item = identifiedItems.first(where: { $0.id == id })
                else {
                    return nil
                }
                return AlternativesSheetPayload(itemID: id, item: item)
            },
            set: { newValue in
                if newValue == nil {
                    alternativesItemID = nil
                }
            }
        )) { payload in
            PhotoAlternativesSheet(
                primary: payload.item,
                onPick: { candidate in
                    applyAlternative(candidate, to: payload.itemID)
                },
                onCancel: { alternativesItemID = nil }
            )
        }
        .alert("What is it?", isPresented: Binding(get: { renameItemID != nil }, set: { if !$0 { renameItemID = nil } })) {
            TextField("e.g. grilled chicken", text: $renameText)
            Button("Cancel", role: .cancel) { renameItemID = nil }
            Button("Save") { commitRename() }
        } message: {
            Text("Tempo updates the calories when it knows the food. Otherwise the old numbers stay as an estimate.")
        }
        .sheet(isPresented: $showAddItem) {
            AddMissingItemSheet { item in
                withAnimation(.easeOut(duration: 0.2)) { identifiedItems.append(item) }
                HapticManager.notification(.success)
            }
            .presentationDetents([.medium])
        }
    }

    /// Swap row `itemID` to the chosen alternative (see `AnalyzedFoodItem.applying`).
    private func applyAlternative(
        _ candidate: PhotoAnalysisResult.FoodCandidate,
        to itemID: UUID
    ) {
        guard let index = identifiedItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        identifiedItems[index] = identifiedItems[index].applying(candidate)
        alternativesItemID = nil
        HapticManager.notification(.success)
    }

    private func confirmGuess(_ itemID: UUID) {
        guard let index = identifiedItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { identifiedItems[index].confirm() }
        HapticManager.lightImpact()
    }

    private func removeItem(_ itemID: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { identifiedItems.removeAll { $0.id == itemID } }
    }

    private func commitRename() {
        defer { renameItemID = nil }
        guard let id = renameItemID, let index = identifiedItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        identifiedItems[index] = identifiedItems[index].renamed(to: renameText)
    }

    // MARK: - Analysis Content

    private func analysisContent(image: UIImage) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.lg) {
                // Captured photo
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // Analysis results
                switch analysisState {
                case .idle:
                    EmptyView()

                case .analyzing:
                    analyzingState

                case .complete:
                    identifiedItemsList

                case let .error(message):
                    analysisErrorState(message: message)

                case let .blocked(blocker):
                    AIBlockerCard(blocker: blocker) {
                        analyzePhoto()
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }
            }
            .padding(.top, TempoSpacing.md)
            .padding(.bottom, 120) // Room for bottom button
        }

        // Bottom action bar
        .overlay(alignment: .bottom) {
            if case .complete = analysisState, !identifiedItems.isEmpty {
                addAllButton
            }
        }
    }

    // MARK: - Analyzing State (Shimmer)

    private var analyzingState: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("ANALYZING")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("Identifying food items...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            // Shimmer skeleton items
            VStack(spacing: TempoSpacing.cardGap) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack(spacing: TempoSpacing.md) {
                        RoundedRectangle(cornerRadius: TempoRadius.sm)
                            .fill(Color.tempoTextDisabled.opacity(0.3))
                            .frame(width: 160, height: 16)
                        Spacer()
                        RoundedRectangle(cornerRadius: TempoRadius.sm)
                            .fill(Color.tempoTextDisabled.opacity(0.3))
                            .frame(width: 60, height: 16)
                    }
                    .padding(.horizontal, TempoSpacing.cardPadding)
                    .padding(.vertical, TempoSpacing.listItemVertical)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
            .shimmer()
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Identified Items List

    private var identifiedItemsList: some View {
        VStack(spacing: TempoSpacing.md) {
            HStack {
                Text("IDENTIFIED ITEMS")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.moduleTag)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                Text("\(identifiedItems.count) found")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            VStack(spacing: 0) {
                ForEach($identifiedItems) { $item in
                    analyzedFoodRow(item: $item)

                    if item.id != identifiedItems.last?.id {
                        Divider()
                            .background(Color.tempoDivider)
                            .padding(.horizontal, TempoSpacing.cardPadding)
                    }
                }
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
            .padding(.horizontal, TempoSpacing.screenEdge)

            Button {
                showAddItem = true
            } label: {
                Label("Add a missing item", systemImage: "plus.circle")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoSignal)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photoAddItem")

            if identifiedItems.isEmpty {
                Text("Nothing left. Add an item or retake the photo.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    private func analyzedFoodRow(item: Binding<AnalyzedFoodItem>) -> some View {
        let value = item.wrappedValue
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Button {
                        renameText = value.name
                        renameItemID = value.id
                    } label: {
                        HStack(spacing: TempoSpacing.xs) {
                            Text(value.name)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(value.name)")

                    Text(value.estimatedPortion)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)

                    // Other guesses from the model, when it was unsure.
                    if !value.alternatives.isEmpty, !value.needsQuestion {
                        Button {
                            alternativesItemID = value.id
                            HapticManager.lightImpact()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(.tempoCaption2)
                                Text("Not right? See \(value.alternatives.count) other \(value.alternatives.count == 1 ? "guess" : "guesses")")
                                    .font(.tempoCaption2)
                            }
                            .foregroundStyle(Color.tempoSignal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photoOtherGuesses")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: TempoSpacing.xs) {
                    confidenceBadge(value)
                    Button {
                        removeItem(value.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(value.name)")
                }
            }

            if value.needsQuestion {
                clarifyingCard(value)
            }

            // Macros row
            HStack(spacing: TempoSpacing.lg) {
                macroLabel("\(value.scaledCalories) kcal", color: Color.tempoViolet)
                macroLabel("P: \(Int(value.protein * value.servingMultiplier))g", color: Color.tempoMacroProtein)
                macroLabel("C: \(Int(value.carbs * value.servingMultiplier))g", color: Color.tempoMacroCarbs)
                macroLabel("F: \(Int(value.fat * value.servingMultiplier))g", color: Color.tempoMacroFat)
            }

            // Portion chips
            HStack(spacing: TempoSpacing.sm) {
                Text("Portion")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                ForEach(MealReviewDraft.factorChoices, id: \.self) { choice in
                    let selected = abs(value.servingMultiplier - choice) < 0.001
                    Button {
                        HapticManager.lightImpact()
                        item.servingMultiplier.wrappedValue = choice
                    } label: {
                        Text(ParsedFoodReviewSheet.chipLabel(choice))
                            .font(.tempoCaption1)
                            .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
                            .frame(minWidth: 28)
                            .padding(.horizontal, TempoSpacing.sm)
                            .padding(.vertical, TempoSpacing.xs)
                            .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.listItemVertical)
    }

    /// Low confidence: ask instead of guessing. One tap answers.
    private func clarifyingCard(_ value: AnalyzedFoodItem) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(value.clarifyingQuestion)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            HStack(spacing: TempoSpacing.sm) {
                answerChip(value.name) { confirmGuess(value.id) }
                ForEach(value.alternatives.prefix(2)) { alt in
                    answerChip(alt.name) { applyAlternative(alt, to: value.id) }
                }
                answerChip("Other…") {
                    renameText = ""
                    renameItemID = value.id
                }
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoWarning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        .accessibilityIdentifier("photoQuestion")
    }

    private func answerChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tempoCaption1)
                .lineLimit(1)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, TempoSpacing.xs)
                .background(Color.tempoSurfaceCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func confidenceBadge(_ item: AnalyzedFoodItem) -> some View {
        let confidence = item.confidence
        return HStack(spacing: TempoSpacing.xs) {
            Image(systemName: item.isVerified ? "checkmark.seal.fill" : confidence.icon)
                .font(.system(size: 12))
            Text("\(item.confidencePercent)%")
                .font(.tempoCaption2.monospacedDigit())
        }
        .foregroundStyle(confidence.color)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, TempoSpacing.xs)
        .background(confidence.color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("\(item.confidencePercent) percent sure\(item.isVerified ? ", macros checked against the food database" : "")")
    }

    private func macroLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .foregroundStyle(color)
    }

    // MARK: - Error State

    private func analysisErrorState(message: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Analysis failed")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("Retry") {
                analyzePhoto()
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.xxxxl)
        }
        .padding(.top, TempoSpacing.xxl)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Add All Button

    private var addAllButton: some View {
        VStack(spacing: 0) {
            Button {
                confirmItems()
            } label: {
                Text("Add All to Meal")
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.md)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .background(
            Color.tempoSurfaceCard
                .shadow(color: Color.tempoInk.opacity(0.08), radius: 8, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func analyzePhoto() {
        guard let image = capturedImage,
              let imageData = image.jpegData(compressionQuality: 0.8)
        else {
            analysisState = .error("Could not read photo data.")
            return
        }

        analysisState = .analyzing

        Task {
            do {
                #if DEBUG
                // Simulator QA has no signed-in AI backend: `--uitesting-mock-photo` uses the mock.
                let analyzer: any PhotoAnalysisServiceProtocol = ProcessInfo.processInfo.arguments
                    .contains("--uitesting-mock-photo") ? MockPhotoAnalysisService() : services.nutrition.photoAnalysis
                #else
                let analyzer = services.nutrition.photoAnalysis
                #endif
                let result = try await analyzer.analyzeMealPhoto(imageData, remainingBudget: nil)

                identifiedItems = result.items.map { item in
                    AnalyzedFoodItem(
                        id: UUID(),
                        name: item.name,
                        estimatedPortion: item.estimatedPortion,
                        calories: Int(item.calories),
                        protein: item.proteinGrams,
                        carbs: item.carbsGrams,
                        fat: item.fatGrams,
                        score: item.confidence,
                        servingMultiplier: 1.0,
                        alternatives: item.alternatives,
                        isVerified: item.isVerified,
                        question: item.question
                    )
                }

                analysisState = .complete
                HapticManager.notification(.success)
            } catch {
                if let blocker = AIBlocker(error) {
                    analysisState = .blocked(blocker)
                } else {
                    analysisState = .error(AIBlocker.readableDescription(error))
                }
                HapticManager.notification(.error)
            }
        }
    }

    private func confirmItems() {
        let foodItems = identifiedItems.map { $0.asFoodItem() }
        HapticManager.notification(.success)
        onItemsConfirmed?(foodItems)
        dismiss()
    }
}

// MARK: - AddMissingItemSheet

/// Adds a food the photo analysis missed. Macros come from the built-in food
/// table; a food it doesn't know needs calories typed in.
private struct AddMissingItemSheet: View {
    let onAdd: (AnalyzedFoodItem) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var name = ""
    @State
    private var gramsText = "100"
    @State
    private var kcalText = ""

    private var grams: Double {
        Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var kcal: Double? {
        Double(kcalText.replacingOccurrences(of: ",", with: "."))
    }

    private var known: Bool {
        FoodMacroDatabase.lookup(name.trimmingCharacters(in: .whitespaces)) != nil
    }

    private var item: AnalyzedFoodItem? {
        AnalyzedFoodItem.manual(name: name, grams: grams, kcal: kcal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food (e.g. olive oil)", text: $name)
                        .accessibilityIdentifier("photoAddName")
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("g", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g").foregroundStyle(Color.tempoTextSecondary)
                    }
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty, !known {
                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("kcal", text: $kcalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("kcal").foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                } footer: {
                    Text(known || name.isEmpty
                        ? "Calories and macros come from Tempo's food table."
                        : "Not in Tempo's food table. Type the calories for that amount.")
                }
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let item {
                            onAdd(item)
                            dismiss()
                        }
                    }
                    .disabled(item == nil)
                    .accessibilityIdentifier("photoAddConfirm")
                }
            }
        }
    }
}

// MARK: - CameraPickerView

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding
    var image: UIImage?
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator

        // Use camera if available, otherwise fall back to photo library for simulator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }

        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - AlternativesSheetPayload

/// Identifiable wrapper so `.sheet(item:)` can present the alternatives picker.
/// The id is the row's own id and nothing else: SwiftUI reads the sheet binding
/// on every re-render, and a fresh UUID per read looked like a new item each
/// time, so the sheet dismissed and re-presented itself in a loop.
struct AlternativesSheetPayload: Identifiable {
    let itemID: UUID
    let item: AnalyzedFoodItem

    var id: UUID {
        itemID
    }
}

// MARK: - PhotoAlternativesSheet

/// Modal picker showing the vision model's ranked alternative
/// identifications for one row of the photo analysis. The primary (the
/// model's best guess) appears at the top with a "Current" badge;
/// alternatives are listed below in descending-confidence order with
/// per-candidate macros so the user can see the full implication of
/// each swap. Tapping a row fires onPick with that candidate.
struct PhotoAlternativesSheet: View {
    let primary: AnalyzedFoodItem
    let onPick: (PhotoAnalysisResult.FoodCandidate) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    explainer
                    currentRow
                    candidatesList
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Other Guesses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private var explainer: some View {
        Text("Pick the closest match. The macros below assume the model is right about portion size; tap a row to swap.")
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var currentRow: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text("CURRENT")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
            }
            candidateCard(
                name: primary.name,
                portion: primary.estimatedPortion,
                calories: primary.calories,
                protein: primary.protein,
                carbs: primary.carbs,
                fat: primary.fat,
                confidence: primary.score,
                isCurrent: true,
                action: nil
            )
        }
    }

    private var candidatesList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text("ALTERNATIVES")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
            }
            VStack(spacing: TempoSpacing.xs) {
                ForEach(primary.alternatives) { alt in
                    candidateCard(
                        name: alt.name,
                        portion: alt.estimatedPortion,
                        calories: Int(alt.calories),
                        protein: alt.proteinGrams,
                        carbs: alt.carbsGrams,
                        fat: alt.fatGrams,
                        confidence: alt.confidence,
                        isCurrent: false,
                        action: {
                            onPick(alt)
                            dismiss()
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func candidateCard(
        name: String,
        portion: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        confidence: Double,
        isCurrent: Bool,
        action: (() -> Void)?
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(portion)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                Text(confidenceBadgeLabel(confidence))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceBadgeColor(confidence).opacity(0.15))
                    .foregroundStyle(confidenceBadgeColor(confidence))
                    .clipShape(Capsule())
            }
            HStack(spacing: TempoSpacing.lg) {
                Text("\(calories) kcal")
                    .font(.tempoCaption2.monospacedDigit())
                    .foregroundStyle(Color.tempoTextSecondary)
                Text("P \(Int(protein))g")
                    .font(.tempoCaption2.monospacedDigit())
                    .foregroundStyle(Color.tempoMacroProtein)
                Text("C \(Int(carbs))g")
                    .font(.tempoCaption2.monospacedDigit())
                    .foregroundStyle(Color.tempoMacroCarbs)
                Text("F \(Int(fat))g")
                    .font(.tempoCaption2.monospacedDigit())
                    .foregroundStyle(Color.tempoMacroFat)
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.tempoBgSecondary : Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
                    .stroke(Color.tempoSignal, lineWidth: 1)
            }
        }

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func confidenceBadgeLabel(_ score: Double) -> String {
        switch score {
        case 0.8...: "HIGH"
        case 0.5 ..< 0.8: "MED"
        default: "LOW"
        }
    }

    private func confidenceBadgeColor(_ score: Double) -> Color {
        switch score {
        case 0.8...: Color.tempoSuccess
        case 0.5 ..< 0.8: Color.tempoWarning
        default: Color.tempoError
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoAnalysisView()
        .environment(ServiceContainer.mock())
}
