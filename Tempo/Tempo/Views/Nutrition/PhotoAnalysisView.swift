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
    /// False when the opener shows its own next screen on top of this one
    /// (Confirm Meal) and closes the flow itself once the meal is saved.
    var dismissesOnConfirm = true
    var onItemsConfirmed: (([FoodItem]) -> Void)?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
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
            TidePageBackground()
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
                    .font(Tide.body)
                    .foregroundStyle(mood.accent)
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
        .alert("What is it?", isPresented: Binding(get: { renameItemID != nil }, set: {
            if !$0 {
                renameItemID = nil
            }
        })) {
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
            VStack(spacing: Tide.s4) {
                // Captured photo
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
                    .padding(.horizontal, Tide.edge)

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
                    .padding(.horizontal, Tide.edge)
                }
            }
            .padding(.top, Tide.s3)
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
        VStack(spacing: Tide.s3) {
            Text("ANALYZING")
                .tideLabel()

            Text("Identifying food items...")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)

            // Shimmer skeleton items
            VStack(spacing: Tide.s3) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack(spacing: Tide.s3) {
                        RoundedRectangle(cornerRadius: Tide.s2)
                            .fill(Tide.text3.opacity(0.3))
                            .frame(width: 160, height: 16)
                        Spacer()
                        RoundedRectangle(cornerRadius: Tide.s2)
                            .fill(Tide.text3.opacity(0.3))
                            .frame(width: 60, height: 16)
                    }
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s3)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.cardRadius)
            .shimmer()
            .padding(.horizontal, Tide.edge)
        }
        .padding(.top, Tide.s4)
    }

    // MARK: - Identified Items List

    private var identifiedItemsList: some View {
        VStack(spacing: Tide.s3) {
            HStack {
                Text("IDENTIFIED ITEMS")
                    .tideLabel()

                Spacer()

                Text("\(identifiedItems.count) found")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            .padding(.horizontal, Tide.edge)

            VStack(spacing: 0) {
                ForEach($identifiedItems) { $item in
                    analyzedFoodRow(item: $item)

                    if item.id != identifiedItems.last?.id {
                        Divider()
                            .background(Tide.hairline)
                            .padding(.horizontal, Tide.s4)
                    }
                }
            }
            .tideCard(padding: 0, radius: Tide.cardRadius)
            .padding(.horizontal, Tide.edge)

            Button {
                showAddItem = true
            } label: {
                Label("Add a missing item", systemImage: "plus.circle")
                    .font(Tide.body)
                    .foregroundStyle(mood.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photoAddItem")

            if identifiedItems.isEmpty {
                Text("Nothing left. Add an item or retake the photo.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
    }

    private func analyzedFoodRow(item: Binding<AnalyzedFoodItem>) -> some View {
        let value = item.wrappedValue
        return VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .top, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Button {
                        renameText = value.name
                        renameItemID = value.id
                    } label: {
                        HStack(spacing: Tide.s1) {
                            Text(value.name)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(value.name)")

                    Text(value.estimatedPortion)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)

                    // Other guesses from the model, when it was unsure.
                    if !value.alternatives.isEmpty, !value.needsQuestion {
                        Button {
                            alternativesItemID = value.id
                            HapticManager.lightImpact()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(Tide.caption)
                                Text(
                                    "Not right? See \(value.alternatives.count) other \(value.alternatives.count == 1 ? "guess" : "guesses")"
                                )
                                .font(Tide.caption)
                            }
                            .foregroundStyle(mood.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photoOtherGuesses")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Tide.s1) {
                    confidenceBadge(value)
                    Button {
                        removeItem(value.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Tide.text3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(value.name)")
                }
            }

            if value.needsQuestion {
                clarifyingCard(value)
            }

            // Macros row
            HStack(spacing: Tide.s4) {
                macroLabel("\(value.scaledCalories) kcal", color: Tide.plan)
                macroLabel("P: \(Int(value.protein * value.servingMultiplier))g", color: Tide.protein)
                macroLabel("C: \(Int(value.carbs * value.servingMultiplier))g", color: Tide.carbs)
                macroLabel("F: \(Int(value.fat * value.servingMultiplier))g", color: Tide.fat)
            }

            // Portion chips
            HStack(spacing: Tide.s2) {
                Text("Portion")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                ForEach(MealReviewDraft.factorChoices, id: \.self) { choice in
                    let selected = abs(value.servingMultiplier - choice) < 0.001
                    Button {
                        HapticManager.lightImpact()
                        item.servingMultiplier.wrappedValue = choice
                    } label: {
                        Text(ParsedFoodReviewSheet.chipLabel(choice))
                            .font(Tide.caption)
                            .foregroundStyle(selected ? Tide.ink : Tide.text)
                            .frame(minWidth: 28)
                            .padding(.horizontal, Tide.s2)
                            .padding(.vertical, Tide.s1)
                            .background(selected ? mood.accent : Tide.fill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
    }

    /// Low confidence: ask instead of guessing. One tap answers.
    private func clarifyingCard(_ value: AnalyzedFoodItem) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(value.clarifyingQuestion)
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
            HStack(spacing: Tide.s2) {
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
        .padding(Tide.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tide.warn.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Tide.s2, style: .continuous))
        .accessibilityIdentifier("photoQuestion")
    }

    private func answerChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Tide.caption)
                .lineLimit(1)
                .foregroundStyle(Tide.text)
                .padding(.horizontal, Tide.s2)
                .padding(.vertical, Tide.s1)
                .background(Tide.fill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func confidenceBadge(_ item: AnalyzedFoodItem) -> some View {
        let confidence = item.confidence
        return HStack(spacing: Tide.s1) {
            Image(systemName: item.isVerified ? "checkmark.seal.fill" : confidence.icon)
                .font(Tide.caption)
            Text("\(item.confidencePercent)%")
                .font(Tide.caption.monospacedDigit())
        }
        .foregroundStyle(confidence.color)
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(confidence.color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("\(item.confidencePercent) percent sure\(item.isVerified ? ", macros checked against the food database" : "")")
    }

    private func macroLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Tide.caption)
            .foregroundStyle(color)
    }

    // MARK: - Error State

    private func analysisErrorState(message: String) -> some View {
        VStack(spacing: Tide.s4) {
            Image(systemName: "exclamationmark.triangle")
                .font(Tide.title)
                .foregroundStyle(Tide.text2)

            Text("Analysis failed")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)

            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("Retry") {
                analyzePhoto()
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.s10)
        }
        .padding(.top, Tide.s6)
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Add All Button

    private var addAllButton: some View {
        Button {
            confirmItems()
        } label: {
            Text("Add All to Meal")
        }
        .buttonStyle(.tidePrimary)
        .tideCard(padding: Tide.s4)
        .padding(.horizontal, Tide.s4)
        .padding(.bottom, Tide.s2)
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
        if dismissesOnConfirm {
            dismiss()
        }
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
                        Text("g").foregroundStyle(Tide.text2)
                    }
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty, !known {
                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("kcal", text: $kcalText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("kcal").foregroundStyle(Tide.text2)
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
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    explainer
                    currentRow
                    candidatesList
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .tidePage()
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
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var currentRow: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                Text("CURRENT")
                    .tideLabel()
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
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                Text("ALTERNATIVES")
                    .tideLabel()
                Spacer()
            }
            VStack(spacing: Tide.s1) {
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
        let content = VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                    Text(portion)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Spacer()
                Text(confidenceBadgeLabel(confidence))
                    .font(Tide.label).monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceBadgeColor(confidence).opacity(0.15))
                    .foregroundStyle(confidenceBadgeColor(confidence))
                    .clipShape(Capsule())
            }
            HStack(spacing: Tide.s4) {
                Text("\(calories) kcal")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(Tide.text2)
                Text("P \(Int(protein))g")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(Tide.protein)
                Text("C \(Int(carbs))g")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(Tide.carbs)
                Text("F \(Int(fat))g")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(Tide.fat)
            }
        }
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Tide.fill : Tide.fill)
        .clipShape(RoundedRectangle(cornerRadius: Tide.s2, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: Tide.s2, style: .continuous)
                    .stroke(mood.accent, lineWidth: 1)
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
        case 0.8...: Tide.good
        case 0.5 ..< 0.8: Tide.warn
        default: Tide.danger
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoAnalysisView()
        .environment(ServiceContainer.mock())
}
