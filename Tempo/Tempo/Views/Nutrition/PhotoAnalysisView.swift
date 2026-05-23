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

    private enum AnalysisState {
        case idle
        case analyzing
        case complete
        case error(String)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                if showCamera, capturedImage == nil {
                    // Camera capture
                    CameraPickerView(image: $capturedImage) {
                        dismiss()
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }

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
                    else { return nil }
                    return AlternativesSheetPayload(itemID: id, item: item)
                },
                set: { newValue in
                    if newValue == nil { alternativesItemID = nil }
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
        }
    }

    /// Replace the displayed identification for `itemID` with the chosen
    /// alternative. Macros + portion swap together — picking "pork" doesn't
    /// keep "chicken" calories. The original best-guess moves into the
    /// alternatives list so the user can change their mind.
    private func applyAlternative(
        _ candidate: PhotoAnalysisResult.FoodCandidate,
        to itemID: UUID
    ) {
        guard let index = identifiedItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let previous = identifiedItems[index]
        // Build a candidate from the previous primary so the user can swap
        // back. Keeps the alternatives list non-empty after a pick.
        let previousAsCandidate = PhotoAnalysisResult.FoodCandidate(
            id: UUID().uuidString,
            name: previous.name,
            estimatedPortion: previous.estimatedPortion,
            calories: Double(previous.calories),
            proteinGrams: previous.protein,
            carbsGrams: previous.carbs,
            fatGrams: previous.fat,
            confidence: previous.confidence.scoreApprox
        )
        var newAlternatives = previous.alternatives.filter { $0.id != candidate.id }
        newAlternatives.insert(previousAsCandidate, at: 0)
        identifiedItems[index] = AnalyzedFoodItem(
            id: previous.id,
            name: candidate.name,
            estimatedPortion: candidate.estimatedPortion,
            calories: Int(candidate.calories),
            protein: candidate.proteinGrams,
            carbs: candidate.carbsGrams,
            fat: candidate.fatGrams,
            confidence: ConfidenceLevel(score: candidate.confidence),
            servingMultiplier: previous.servingMultiplier,
            alternatives: newAlternatives
        )
        alternativesItemID = nil
        HapticManager.notification(.success)
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
        }
    }

    private func analyzedFoodRow(item: Binding<AnalyzedFoodItem>) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(item.wrappedValue.name)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(item.wrappedValue.estimatedPortion)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)

                    // Alternatives affordance — visible only when the model
                    // returned ranked candidates for this item ("could be
                    // chicken, or pork?"). Tap opens a sheet to swap.
                    if !item.wrappedValue.alternatives.isEmpty {
                        Button {
                            alternativesItemID = item.wrappedValue.id
                            HapticManager.lightImpact()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(.tempoCaption2)
                                Text("Not right? \(item.wrappedValue.alternatives.count) other guesses")
                                    .font(.tempoCaption2)
                            }
                            .foregroundStyle(Color.tempoSignal)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Confidence badge
                confidenceBadge(item.wrappedValue.confidence)
            }

            // Macros row
            HStack(spacing: TempoSpacing.lg) {
                macroLabel("\(item.wrappedValue.calories) kcal", color: Color.tempoViolet)
                macroLabel(
                    "P: \(Int(item.wrappedValue.protein))g",
                    color: Color.tempoMacroProtein
                )
                macroLabel(
                    "C: \(Int(item.wrappedValue.carbs))g",
                    color: Color.tempoMacroCarbs
                )
                macroLabel(
                    "F: \(Int(item.wrappedValue.fat))g",
                    color: Color.tempoMacroFat
                )
            }

            // Portion stepper
            HStack(spacing: TempoSpacing.sm) {
                Text("Servings:")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                NumberStepperView(
                    value: item.servingMultiplier,
                    range: 0.5 ... 5.0,
                    step: 0.5,
                    format: "%.1f",
                    unit: "x"
                )
            }
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.listItemVertical)
    }

    private func confidenceBadge(_ confidence: ConfidenceLevel) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Image(systemName: confidence.icon)
                .font(.system(size: 12))
            Text(confidence.label)
                .font(.tempoCaption2)
        }
        .foregroundStyle(confidence.color)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, TempoSpacing.xs)
        .background(confidence.color.opacity(0.12))
        .clipShape(Capsule())
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
                let result = try await services.nutrition.photoAnalysis
                    .analyzeMealPhoto(imageData, remainingBudget: nil)

                identifiedItems = result.items.map { item in
                    AnalyzedFoodItem(
                        id: UUID(),
                        name: item.name,
                        estimatedPortion: item.estimatedPortion,
                        calories: Int(item.calories),
                        protein: item.proteinGrams,
                        carbs: item.carbsGrams,
                        fat: item.fatGrams,
                        confidence: ConfidenceLevel(score: item.confidence),
                        servingMultiplier: 1.0,
                        alternatives: item.alternatives
                    )
                }

                analysisState = .complete
                HapticManager.notification(.success)
            } catch {
                analysisState = .error(error.localizedDescription)
                HapticManager.notification(.error)
            }
        }
    }

    private func confirmItems() {
        let foodItems = identifiedItems.map { item in
            let multiplier = item.servingMultiplier
            return FoodItem(
                id: UUID(),
                name: item.name,
                brand: nil,
                servingSize: item.estimatedPortion,
                servingQuantity: multiplier,
                calories: Int(Double(item.calories) * multiplier),
                protein: item.protein * multiplier,
                carbs: item.carbs * multiplier,
                fat: item.fat * multiplier
            )
        }
        HapticManager.notification(.success)
        onItemsConfirmed?(foodItems)
        dismiss()
    }
}

// MARK: - AnalyzedFoodItem

struct AnalyzedFoodItem: Identifiable {
    let id: UUID
    var name: String
    var estimatedPortion: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: ConfidenceLevel
    var servingMultiplier: Double
    /// Top alternative identifications from the vision model, ranked by
    /// descending confidence. Empty when the food is unambiguous. Tapping
    /// an alternative in the picker sheet swaps this row's name +
    /// estimatedPortion + macros to that alternative's values.
    var alternatives: [PhotoAnalysisResult.FoodCandidate] = []
}

extension ConfidenceLevel {
    init(score: Double) {
        if score >= 0.8 {
            self = .high
        } else if score >= 0.5 {
            self = .medium
        } else {
            self = .low
        }
    }

    /// Round-trip back to a numeric score when we need to push a
    /// ConfidenceLevel back into a candidate DTO (e.g. when the user
    /// swaps to an alternative and the previous primary becomes a
    /// candidate they could swap back to). Uses the midpoint of each
    /// bucket so the value re-decodes to the same level.
    var scoreApprox: Double {
        switch self {
        case .high: 0.9
        case .medium: 0.65
        case .low: 0.35
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

/// Identifiable wrapper so SwiftUI's .sheet(item:) can present the
/// alternatives picker from a non-Identifiable (UUID, AnalyzedFoodItem)
/// pair. New UUID per presentation so reopening the sheet for the same
/// item still fires the rebuild.
private struct AlternativesSheetPayload: Identifiable {
    let id = UUID()
    let itemID: UUID
    let item: AnalyzedFoodItem
}

// MARK: - PhotoAlternativesSheet

/// Modal picker showing the vision model's ranked alternative
/// identifications for one row of the photo analysis. The primary (the
/// model's best guess) appears at the top with a "Current" badge;
/// alternatives are listed below in descending-confidence order with
/// per-candidate macros so the user can see the full implication of
/// each swap. Tapping a row fires onPick with that candidate.
private struct PhotoAlternativesSheet: View {
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
                confidence: primary.confidence.scoreApprox,
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
