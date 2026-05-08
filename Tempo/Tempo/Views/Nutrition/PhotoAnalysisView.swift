//
// PhotoAnalysisView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
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

    @State
    private var capturedImage: UIImage?
    @State
    private var showCamera = true
    @State
    private var analysisState: AnalysisState = .idle
    @State
    private var identifiedItems: [AnalyzedFoodItem] = []

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
        }
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
        analysisState = .analyzing

        // Simulated AI analysis — in production, sends to Claude API
        Task {
            try? await Task.sleep(for: .seconds(2))

            identifiedItems = [
                AnalyzedFoodItem(
                    id: UUID(), name: "Grilled Chicken Breast", estimatedPortion: "~150g",
                    calories: 248, protein: 46, carbs: 0, fat: 5.4,
                    confidence: .high, servingMultiplier: 1.0
                ),
                AnalyzedFoodItem(
                    id: UUID(), name: "Steamed Broccoli", estimatedPortion: "~120g",
                    calories: 40, protein: 4.4, carbs: 6.6, fat: 0.4,
                    confidence: .high, servingMultiplier: 1.0
                ),
                AnalyzedFoodItem(
                    id: UUID(), name: "White Rice", estimatedPortion: "~180g cooked",
                    calories: 234, protein: 4.3, carbs: 51.5, fat: 0.4,
                    confidence: .medium, servingMultiplier: 1.0
                ),
            ]

            analysisState = .complete
            HapticManager.notification(.success)
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

// MARK: - Preview

#Preview {
    PhotoAnalysisView()
}
