//
// AddProductView.swift
// Tempo
//
// A barcode nobody has catalogued yet: the user snaps the front of the pack
// (turned into a white-background studio shot on-device) and the nutrition
// label (read by AI when signed in with Pro — otherwise typed). Saved on this
// phone as the user's own product; the next scan of the same barcode opens it.
//

import SwiftData
import SwiftUI

// MARK: - AddProductView

struct AddProductView: View {
    let barcode: String?
    let catalog: FoodCatalog
    let onSaved: (FoodProduct) -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var name = ""
    @State
    private var brand = ""
    @State
    private var servingText = ""
    @State
    private var isBeverage = false
    @State
    private var kcal = ""
    @State
    private var protein = ""
    @State
    private var carbs = ""
    @State
    private var sugars = ""
    @State
    private var fat = ""
    @State
    private var saturatedFat = ""
    @State
    private var fiber = ""
    @State
    private var salt = ""
    @State
    private var ingredients = ""
    @State
    private var allergens: [String] = []

    @State
    private var photo: Data?
    @State
    private var photoIsCutOut = false
    @State
    private var isRenderingPhoto = false
    @State
    private var isReadingLabel = false
    @State
    private var labelMessage: String?
    @State
    private var picker: PickerTarget?

    private enum PickerTarget: Identifiable {
        case front(UIImagePickerController.SourceType)
        case label(UIImagePickerController.SourceType)

        var id: String {
            switch self {
            case let .front(source): "front-\(source.rawValue)"
            case let .label(source): "label-\(source.rawValue)"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                photoRow
            } header: {
                Text("Product photo")
            } footer: {
                Text("Tempo cuts the product out and puts it on a clean white background. Done on your phone.")
            }

            Section {
                labelRow
            } header: {
                Text("Nutrition label")
            } footer: {
                if let labelMessage {
                    Text(labelMessage)
                        .foregroundStyle(Color.tempoAmber)
                } else {
                    Text("Snap the table — AI fills in the values below. You can always type them.")
                }
            }

            Section("Product") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("addProductName")
                TextField("Brand (optional)", text: $brand)
                if let barcode {
                    LabeledContent("Barcode", value: barcode)
                }
                Toggle("It's a drink (values per 100 ml)", isOn: $isBeverage)
                numberField("Serving size (optional)", text: $servingText, unit: isBeverage ? "ml" : "g", id: "addProductServing")
            }

            Section {
                numberField("Calories", text: $kcal, unit: "kcal", id: "addProductKcal")
                numberField("Protein", text: $protein, unit: "g", id: "addProductProtein")
                numberField("Carbs", text: $carbs, unit: "g", id: "addProductCarbs")
                numberField("of which sugars", text: $sugars, unit: "g", id: "addProductSugars")
                numberField("Fat", text: $fat, unit: "g", id: "addProductFat")
                numberField("of which saturated", text: $saturatedFat, unit: "g", id: "addProductSatFat")
                numberField("Fiber", text: $fiber, unit: "g", id: "addProductFiber")
                numberField("Salt", text: $salt, unit: "g", id: "addProductSalt")
            } header: {
                Text("Per 100 \(isBeverage ? "ml" : "g")")
            } footer: {
                Text("Calories, protein, carbs and fat are needed to log it. Add salt (plus sugars and saturated fat) for a Tempo score.")
            }

            Section {
                TextField("Ingredients (optional)", text: $ingredients, axis: .vertical)
                    .lineLimit(3 ... 8)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("E-numbers in the ingredients are used to rate additives.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Add product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(draft == nil)
                    .accessibilityIdentifier("addProductSave")
            }
        }
        .fullScreenCover(item: $picker) { target in
            switch target {
            case let .front(source):
                FoodImagePicker(sourceType: source) { image in
                    picker = nil
                    if let image {
                        renderPhoto(image)
                    }
                }
                .ignoresSafeArea()
            case let .label(source):
                FoodImagePicker(sourceType: source) { image in
                    picker = nil
                    if let image {
                        readLabel(image)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Photo

    private var photoRow: some View {
        HStack(spacing: TempoSpacing.lg) {
            ZStack {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                if isRenderingPhoto {
                    ProgressView()
                }
            }
            .frame(width: 88, height: 88)
            .background(photo == nil ? Color.tempoBgTertiary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                if photo != nil {
                    Text(photoIsCutOut ? "Studio photo ready" : "Couldn't cut it out — cropped instead")
                        .font(.tempoCaption1)
                        .foregroundStyle(photoIsCutOut ? Color.tempoSuccess : Color.tempoTextSecondary)
                }
                captureButtons(camera: { picker = .front(.camera) }, library: { picker = .front(.photoLibrary) })
            }
        }
        .padding(.vertical, TempoSpacing.xs)
    }

    private func renderPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return
        }
        isRenderingPhoto = true
        Task {
            let output = await ProductPhotoStudio.render(data)
            photo = output?.jpegData
            photoIsCutOut = output?.isCutOut ?? false
            isRenderingPhoto = false
        }
    }

    // MARK: - Label

    private var labelRow: some View {
        HStack(spacing: TempoSpacing.md) {
            if isReadingLabel {
                ProgressView()
                Text("Reading the label…")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
            } else {
                captureButtons(camera: { picker = .label(.camera) }, library: { picker = .label(.photoLibrary) })
            }
        }
        .padding(.vertical, TempoSpacing.xs)
    }

    private func readLabel(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return
        }
        isReadingLabel = true
        labelMessage = nil
        Task {
            do {
                let reading = try await NutritionLabelReader.read(imageJPEG: data, apiClient: services.apiClient)
                apply(reading)
                HapticManager.success()
            } catch let error as APIError {
                labelMessage = switch error {
                case .unauthorized: "Sign in to read labels with AI — or type the values below."
                case .subscriptionRequired: "Reading labels with AI is a Tempo Pro feature — type the values below."
                case .aiConsentRequired: "Turn on AI features in Settings to read labels — or type the values below."
                default: error.userMessage
                }
            } catch {
                labelMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't read the label. Type the values below."
            }
            isReadingLabel = false
        }
    }

    private func apply(_ reading: NutritionLabelReading) {
        if name.isEmpty, let value = reading.name {
            name = value
        }
        if brand.isEmpty, let value = reading.brand {
            brand = value
        }
        if let serving = reading.servingGrams {
            servingText = Self.text(serving)
        }
        isBeverage = reading.isBeverage
        let n = reading.per100g
        kcal = Self.text(n.kcal)
        protein = Self.text(n.protein)
        carbs = Self.text(n.carbs)
        sugars = Self.text(n.sugars)
        fat = Self.text(n.fat)
        saturatedFat = Self.text(n.saturatedFat)
        fiber = Self.text(n.fiber)
        salt = Self.text(n.salt)
        if let text = reading.ingredients {
            ingredients = text
        }
        allergens = reading.allergens
    }

    // MARK: - Save

    /// The product as currently filled in; nil until name + core macros are there.
    private var draft: FoodProduct? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutrients = FoodProduct.Nutrients(
            kcal: Self.number(kcal), protein: Self.number(protein), carbs: Self.number(carbs),
            sugars: Self.number(sugars), fat: Self.number(fat), saturatedFat: Self.number(saturatedFat),
            fiber: Self.number(fiber), salt: Self.number(salt)
        )
        guard !trimmedName.isEmpty, nutrients.hasCoreMacros else {
            return nil
        }
        let serving = Self.number(servingText).flatMap { $0 > 0 ? $0 : nil }
        let unit = isBeverage ? "ml" : "g"
        let trimmedIngredients = ingredients.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodProduct(
            id: barcode ?? "user:\(trimmedName.lowercased())",
            barcode: barcode,
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand
                .trimmingCharacters(in: .whitespacesAndNewlines),
            source: .userAdded,
            servingLabel: serving.map { "\(Self.text($0)) \(unit)" },
            servingGrams: serving,
            isBeverage: isBeverage,
            per100g: nutrients,
            additives: NutritionLabelReader.additiveCodes(in: trimmedIngredients),
            allergens: allergens,
            ingredientsText: trimmedIngredients.isEmpty ? nil : trimmedIngredients
        )
    }

    private func save() {
        guard let product = draft else {
            return
        }
        catalog.saveUserAdded(product, photo: photo, in: modelContext)
        HapticManager.success()
        onSaved(product)
    }

    // MARK: - Helpers

    private func captureButtons(camera: @escaping () -> Void, library: @escaping () -> Void) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Button(action: camera) {
                Label("Camera", systemImage: "camera")
            }
            Button(action: library) {
                Label("Library", systemImage: "photo.on.rectangle")
            }
        }
        .buttonStyle(.bordered)
        .tint(Color.tempoSignal)
        .font(.tempoCaption1)
    }

    private func numberField(_ label: String, text: Binding<String>, unit: String, id: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0 else {
            return nil
        }
        return value
    }

    static func text(_ value: Double?) -> String {
        guard let value else {
            return ""
        }
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
