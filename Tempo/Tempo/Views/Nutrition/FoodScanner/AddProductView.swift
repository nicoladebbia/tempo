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
    /// An existing product whose label is being (re)photographed: its fields
    /// start filled in, and saving replaces it.
    var prefill: FoodProduct?
    let onSaved: (FoodProduct) -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood

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
    /// The label photo, cropped to the label, shown as a card after capture.
    @State
    private var labelImage: UIImage?
    @State
    private var labelMessage: String?
    @State
    private var labelBlocker: AIBlocker?
    @State
    private var picker: PickerTarget?
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric
    private var photoSize: CGFloat = Tide.Kitchen.heroDisc
    @ScaledMetric
    private var fieldWidth: CGFloat = Tide.Kitchen.thumb + Tide.s8
    @ScaledMetric
    private var unitWidth: CGFloat = Tide.s8
    @ScaledMetric
    private var labelMaxHeight: CGFloat = Tide.Kitchen.heroPicture

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
        KitchenForm {
            KitchenFormSection(
                String(localized: "Product photo"),
                footer: String(localized: "Tempo cuts the product out and puts it on a clean white background. Done on your phone.")
            ) {
                photoRow
            }

            Section {
                labelRow
                if let labelBlocker {
                    AIBlockerCard(
                        blocker: labelBlocker,
                        message: labelBlocker == .proRequired
                            ? String(localized: "Reading labels with AI is a Tempo Pro feature. You can still type the values below.")
                            : String(localized: "AI features are off. Turn them on to read labels, or type the values below.")
                    ) {
                        self.labelBlocker = nil
                        labelMessage = nil
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                Text("Nutrition label").tideLabel()
            } footer: {
                if let labelMessage {
                    Text(labelMessage)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.Kitchen.warn)
                } else {
                    Text("Snap the table and AI fills in the values below. You can always type them.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }

            KitchenFormSection(String(localized: "Product")) {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("addProductName")
                TextField("Brand (optional)", text: $brand)
                if let barcode {
                    LabeledContent("Barcode", value: barcode)
                }
                Toggle("It's a drink (values per 100 ml)", isOn: $isBeverage)
                numberField(String(localized: "Serving size (optional)"), text: $servingText, unit: isBeverage ? "ml" : "g", id: "addProductServing")
            }

            Section {
                valuesCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Per 100 \(isBeverage ? "ml" : "g")").tideLabel()
            }

            KitchenFormSection(String(localized: "Ingredients"), footer: String(localized: "E-numbers in the ingredients are used to rate additives.")) {
                TextField("Ingredients (optional)", text: $ingredients, axis: .vertical)
                    .lineLimit(3 ... 8)
            }
        }
        .kitchenPage()
        .kitchenBottomBar { saveBar }
        .onAppear(perform: applyPrefill)
        .navigationTitle(prefill == nil ? String(localized: "Add product") : String(localized: "Update label"))
        .navigationBarTitleDisplayMode(.inline)
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

    private func applyPrefill() {
        guard let product = prefill, name.isEmpty, kcal.isEmpty else {
            return
        }
        name = product.name
        brand = product.brand ?? ""
        servingText = Self.text(product.servingGrams)
        isBeverage = product.isBeverage
        let n = product.per100g
        kcal = Self.text(n.kcal)
        protein = Self.text(n.protein)
        carbs = Self.text(n.carbs)
        sugars = Self.text(n.sugars)
        fat = Self.text(n.fat)
        saturatedFat = Self.text(n.saturatedFat)
        fiber = Self.text(n.fiber)
        salt = Self.text(n.salt)
        ingredients = product.ingredientsText ?? ""
        allergens = product.allergens
    }

    // MARK: - Photo

    private var photoRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return layout {
            ZStack {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text3)
                }
                if isRenderingPhoto {
                    ProgressView()
                }
            }
            .frame(width: photoSize, height: photoSize)
            // White on purpose: the studio shot is a cut-out on white.
            .background(photo == nil ? Tide.fill : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous))

            VStack(alignment: .leading, spacing: Tide.s2) {
                if photo != nil {
                    Text(photoIsCutOut ? String(localized: "Studio photo ready") : String(localized: "Couldn't cut it out, cropped instead"))
                        .font(Tide.caption)
                        .foregroundStyle(photoIsCutOut ? Tide.Kitchen.good : Tide.text2)
                }
                captureButtons(camera: { picker = .front(.camera) }, library: { picker = .front(.photoLibrary) }, stacked: true)
            }
        }
        .padding(.vertical, Tide.s1)
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

    @ViewBuilder
    private var labelRow: some View {
        if let labelImage {
            // Captured: the capture buttons are gone; the label is a card and
            // the only control left is a small Retake.
            VStack(spacing: Tide.s2) {
                Image(uiImage: labelImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: labelMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
                    .overlay {
                        if isReadingLabel {
                            ZStack {
                                Tide.Kitchen.scrim
                                VStack(spacing: Tide.s2) {
                                    ProgressView().tint(Tide.text)
                                    Text("Reading the label…")
                                        .font(Tide.caption)
                                        .foregroundStyle(Tide.text)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
                        }
                    }
                    .accessibilityLabel("Photo of the nutrition label")
                    .accessibilityIdentifier("addProductLabelCard")
                if !isReadingLabel {
                    Button("Retake") { picker = .label(.camera) }
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(minHeight: Tide.hit)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("addProductLabelRetake")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tide.s1)
        } else if isReadingLabel {
            HStack(spacing: Tide.s3) {
                ProgressView()
                Text("Reading the label…")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer()
            }
            .padding(.vertical, Tide.s1)
        } else {
            captureButtons(camera: { picker = .label(.camera) }, library: { picker = .label(.photoLibrary) })
                .padding(.vertical, Tide.s1)
        }
    }

    private func readLabel(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return
        }
        isReadingLabel = true
        labelMessage = nil
        labelBlocker = nil
        Task {
            labelImage = await LabelCrop.cropped(image)
            do {
                let reading = try await NutritionLabelReader.read(imageJPEG: data, apiClient: services.apiClient)
                apply(reading)
                HapticManager.success()
            } catch let error as APIError {
                labelBlocker = AIBlocker(error)
                labelMessage = switch error {
                case .unauthorized: String(localized: "Sign in to read labels with AI — or type the values below.")
                case .subscriptionRequired,
                     .aiConsentRequired: nil
                default: error.userMessage
                }
            } catch {
                labelMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't read the label. Type the values below.")
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
        let trimmedIngredients = ingredients.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodProduct.userEdited(
            from: prefill,
            barcode: barcode,
            name: trimmedName,
            brand: brand,
            servingGrams: serving,
            isBeverage: isBeverage,
            per100g: nutrients,
            allergens: allergens,
            ingredients: trimmedIngredients
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

    private func captureButtons(camera: @escaping () -> Void, library: @escaping () -> Void, stacked: Bool = false) -> some View {
        let layout = stacked || typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return GlassEffectContainer(spacing: Tide.s2) {
            layout {
                Button(action: camera) {
                    Label("Camera", systemImage: "camera")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                Button(action: library) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.tideGlass)
        }
    }

    /// The four values needed to log it first, big, in the colours of Today's
    /// macro rings; salt, fiber and the two "of which" lines after.
    private var valuesCard: some View {
        let unit = "g"
        return VStack(alignment: .leading, spacing: Tide.s3) {
            coreMeter
            KitchenPair {
                KitchenNumberField(label: String(localized: "Calories"), unit: "kcal", placeholder: "—", tint: Tide.streak, text: $kcal, identifier: "addProductKcal")
            } second: {
                KitchenNumberField(label: String(localized: "Protein"), unit: unit, placeholder: "—", tint: Tide.protein, text: $protein, identifier: "addProductProtein")
            }
            KitchenPair {
                KitchenNumberField(label: String(localized: "Carbs"), unit: unit, placeholder: "—", tint: Tide.carbs, text: $carbs, identifier: "addProductCarbs")
            } second: {
                KitchenNumberField(label: String(localized: "Fat"), unit: unit, placeholder: "—", tint: Tide.fat, text: $fat, identifier: "addProductFat")
            }
            Text("Also on the label").tideLabel(Tide.text3)
                .padding(.top, Tide.s2)
            KitchenPair {
                KitchenNumberField(label: String(localized: "Sugars"), unit: unit, placeholder: "—", text: $sugars, identifier: "addProductSugars")
            } second: {
                KitchenNumberField(label: String(localized: "Saturated"), unit: unit, placeholder: "—", text: $saturatedFat, identifier: "addProductSatFat")
            }
            KitchenPair {
                KitchenNumberField(label: String(localized: "Fiber"), unit: unit, placeholder: "—", text: $fiber, identifier: "addProductFiber")
            } second: {
                KitchenNumberField(label: String(localized: "Salt"), unit: unit, placeholder: "—", text: $salt, identifier: "addProductSalt")
            }
            Text("Calories, protein, carbs and fat are needed to log it. Add salt (plus sugars and saturated fat) for a Tempo score.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
    }

    /// Save sits under the thumb. While it can't save, one line says what is
    /// still missing.
    private var saveBar: some View {
        VStack(spacing: Tide.s2) {
            if draft == nil {
                Text(missingHint)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tide.s3)
                    .padding(.vertical, Tide.s1)
                    .glassEffect(.regular, in: .rect(cornerRadius: Tide.controlRadius))
                    .transition(.opacity)
            }
            Button(action: save) {
                Text(prefill == nil ? String(localized: "Save product") : String(localized: "Save label"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kitchenBar)
            .disabled(draft == nil)
            .accessibilityIdentifier("addProductSave")
        }
        .animation(Tide.snap, value: draft == nil)
    }

    private var missingHint: String {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (hasName, coreFilled == 4) {
        case (false, false): return String(localized: "Add a name and the four values to save.")
        case (false, true): return String(localized: "Add a name to save.")
        default: return String(localized: "Add the four values to save.")
        }
    }

    private func numberField(_ label: String, text: Binding<String>, unit: String, id: String) -> some View {
        HStack {
            Text(label)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
            Spacer()
            TextField("—", text: text)
                .font(Tide.bodyStrong)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: fieldWidth)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(width: unitWidth, alignment: .leading)
        }
        .frame(minHeight: Tide.hit)
    }

    /// How many of the four values needed to log this product are filled in, as a live meter.
    private var coreFilled: Int {
        [kcal, protein, carbs, fat].filter { Self.number($0) != nil }.count
    }

    private var coreMeter: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needed to log it")
                    .tideLabel()
                Spacer()
                Text("\(coreFilled) of 4")
                    .font(Tide.numeral(Tide.numeralS))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(coreFilled == 4 ? Tide.Kitchen.good : Tide.text)
            }
            TideLevelBar(progress: Double(coreFilled) / 4, color: coreFilled == 4 ? Tide.Kitchen.good : mood.accent)
                .animation(Tide.snap, value: coreFilled)
        }
        .padding(.vertical, Tide.s1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coreFilled) of 4 values needed to log this product")
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
