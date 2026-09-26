//
// FoodProductView.swift
// Tempo
//
// The "internal Yuka" screen for one product: Tempo score (nutrition,
// additives, organic), what it means for YOU today (calories left, allergies,
// clear-skin mode…), Nutri-Score + NOVA, additives with risk levels,
// nutrients per 100 g and per portion, better alternatives, favourite, and —
// when opened from meal logging — "Add to meal".
//

import SwiftData
import SwiftUI

// MARK: - FoodProductView

struct FoodProductView: View {
    enum Mode {
        /// Scan-to-check: look only, nothing is logged.
        case check
        /// Opened from meal logging: shows "Add to meal".
        case log((FoodItem) -> Void)
    }

    let product: FoodProduct
    var mode: Mode = .check
    let catalog: FoodCatalog
    /// Adds it to scan history on open (the scanner already did on lookup).
    var recordsView = true

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var grams: Double
    @State
    private var gramsText: String
    @State
    private var isFavorite = false
    @State
    private var photo: Data?
    @State
    private var fitContext = FoodFitContext.none
    @State
    private var alternatives: [FoodProduct] = []
    @State
    private var isLoadingAlternatives = false
    @State
    private var showIngredients = false
    @State
    private var photoSource: PhotoSource?
    @State
    private var isRenderingPhoto = false

    private struct PhotoSource: Identifiable {
        let type: UIImagePickerController.SourceType
        var id: Int { type.rawValue }
    }

    private let score: FoodScore?

    init(product: FoodProduct, mode: Mode = .check, catalog: FoodCatalog, recordsView: Bool = true) {
        self.product = product
        self.mode = mode
        self.catalog = catalog
        self.recordsView = recordsView
        score = FoodScore.evaluate(product)
        let portion = product.defaultPortionGrams
        _grams = State(initialValue: portion)
        _gramsText = State(initialValue: Self.format(portion))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                header
                scoreCard
                forYouCard
                gradesCard
                additivesCard
                nutritionCard
                alternativesSection
                ingredientsCard
                attribution
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, TempoSpacing.xxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFavorite = catalog.toggleFavorite(product, in: modelContext)
                    HapticManager.lightImpact()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.tempoAmber : Color.tempoTextSecondary)
                }
                .accessibilityLabel(isFavorite ? "Remove from favourites" : "Add to favourites")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case let .log(onAdd) = mode {
                addBar(onAdd)
            }
        }
        .task(id: product.id) {
            if recordsView {
                catalog.recordView(product, in: modelContext)
            }
            isFavorite = catalog.isFavorite(product, in: modelContext)
            photo = catalog.photo(for: product, in: modelContext)
            fitContext = FoodFitContext.loadToday(in: modelContext, whoopAvgTDEE: services.whoop.weeklyTDEEAverage)
            await loadAlternatives()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: TempoSpacing.lg) {
            FoodProductThumbnail(product: product, photo: photo, size: 96)
                .overlay {
                    if isRenderingPhoto {
                        ProgressView()
                    }
                }
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text(product.name)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                if let quantity = product.quantityLabel {
                    Text(quantity)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                if product.imageURL == nil, product.imageSmallURL == nil {
                    addPhotoMenu
                }
            }
            Spacer(minLength: 0)
        }
        .fullScreenCover(item: $photoSource) { source in
            FoodImagePicker(sourceType: source.type) { image in
                photoSource = nil
                if let image {
                    savePhoto(image)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// No picture anywhere → let the user snap one; it gets the same white
    /// studio background as added products.
    private var addPhotoMenu: some View {
        Menu {
            Button {
                photoSource = PhotoSource(type: .camera)
            } label: {
                Label("Camera", systemImage: "camera")
            }
            Button {
                photoSource = PhotoSource(type: .photoLibrary)
            } label: {
                Label("Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "camera")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
        }
        .disabled(isRenderingPhoto)
        .padding(.top, TempoSpacing.xxs)
        .accessibilityIdentifier("foodAddPhoto")
    }

    private func savePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return
        }
        isRenderingPhoto = true
        Task {
            if let output = await ProductPhotoStudio.render(data) {
                photo = output.jpegData
                catalog.setPhoto(output.jpegData, for: product, in: modelContext)
            }
            isRenderingPhoto = false
        }
    }

    // MARK: - Score

    @ViewBuilder
    private var scoreCard: some View {
        if let score {
            HStack(spacing: TempoSpacing.xl) {
                FoodScoreRing(score: score)
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text(score.rating.label.uppercased())
                        .font(.tempoHeadline)
                        .foregroundStyle(score.rating.color)
                        .accessibilityIdentifier("foodScoreRating")
                    scorePart("Nutrition", score.nutritionPoints, of: 60)
                    scorePart("Additives", score.additivePoints, of: 30)
                    scorePart("Organic", score.organicPoints, of: 10)
                    if score.cappedByAdditive {
                        Text("Capped: contains a high-risk additive")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoError)
                    }
                }
                Spacer(minLength: 0)
            }
            .tempoCard()
        } else {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Not enough data to score")
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(missingForScore)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    private var missingForScore: String {
        let n = product.per100g
        let missing = [("calories", n.kcal), ("carbs or sugars", n.sugars ?? n.carbs), ("fat", n.saturatedFat ?? n.fat), ("salt", n.salt)]
            .filter { $0.1 == nil }
            .map(\.0)
        guard !missing.isEmpty else {
            return "The nutrition table is incomplete for this product."
        }
        return "Missing from the nutrition table: \(missing.joined(separator: ", "))."
    }

    private func scorePart(_ label: String, _ points: Int, of max: Int) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: Double(points), total: Double(max))
                .tint(score?.rating.color ?? Color.tempoSignal)
            Text("\(points)/\(max)")
                .font(.tempoCaption2)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - For you

    @ViewBuilder
    private var forYouCard: some View {
        let checks = FoodFit.checks(for: product, grams: grams, context: fitContext)
        if !checks.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                sectionTitle("FOR YOU · \(Self.format(grams)) \(product.unit)")
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Image(systemName: check.kind.icon)
                            .foregroundStyle(check.kind.color)
                        Text(check.text)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    // MARK: - Nutri-Score + NOVA

    @ViewBuilder
    private var gradesCard: some View {
        if score != nil || product.novaGroup != nil {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                if let score {
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        sectionTitle(score.nutriScoreEstimated ? "NUTRI-SCORE · ESTIMATED" : "NUTRI-SCORE")
                        HStack(spacing: TempoSpacing.xs) {
                            ForEach(NutriScore.grades, id: \.self) { grade in
                                let selected = grade == score.nutriScoreGrade
                                Text(grade.uppercased())
                                    .font(selected ? .tempoHeadline : .tempoCaption1)
                                    .foregroundStyle(selected ? Color.tempoTextInverse : Color.tempoTextTertiary)
                                    .frame(width: selected ? 40 : 30, height: selected ? 40 : 30)
                                    .background(selected ? Self.gradeColor(grade) : Color.tempoBgTertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Nutri-Score \(score.nutriScoreGrade.uppercased())")
                    }
                }
                if let nova = product.novaGroup {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        sectionTitle("PROCESSING · NOVA \(nova)")
                        Text(Self.novaText(nova))
                            .font(.tempoBody)
                            .foregroundStyle(nova == 4 ? Color.tempoAmber : Color.tempoTextPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    // MARK: - Additives

    @ViewBuilder
    private var additivesCard: some View {
        if let score, product.source == .openFoodFacts || product.source == .userAdded {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                sectionTitle("ADDITIVES · \(score.additives.count)")
                if score.additives.isEmpty {
                    Label("No additives", systemImage: "checkmark.circle.fill")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSuccess)
                } else {
                    ForEach(score.additives) { additive in
                        HStack(alignment: .top, spacing: TempoSpacing.sm) {
                            Circle()
                                .fill(additive.risk.color)
                                .frame(width: 10, height: 10)
                                .padding(.top, TempoSpacing.xs)
                            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                                Text("\(additive.displayCode) · \(additive.name)")
                                    .font(.tempoBodyBold)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(additive.note.map { "\(additive.risk.label) — \($0)" } ?? additive.risk.label)
                                    .font(.tempoCaption1)
                                    .foregroundStyle(additive.risk == .unknown ? Color.tempoTextSecondary : additive.risk.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    // MARK: - Nutrition

    private var nutritionCard: some View {
        let per100 = product.per100g
        let portion = product.nutrients(forGrams: grams)
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionTitle("NUTRITION")
            portionPicker
            Grid(alignment: .leading, horizontalSpacing: TempoSpacing.md, verticalSpacing: TempoSpacing.sm) {
                GridRow {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("100 \(product.unit)")
                        .gridColumnAlignment(.trailing)
                    Text("\(Self.format(grams)) \(product.unit)")
                        .gridColumnAlignment(.trailing)
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                Divider()
                nutrientRow("Calories", per100.kcal, portion.kcal, unit: "kcal", level: nil)
                nutrientRow("Protein", per100.protein, portion.protein, unit: "g", level: nil)
                nutrientRow("Carbs", per100.carbs, portion.carbs, unit: "g", level: nil)
                nutrientRow("  Sugars", per100.sugars, portion.sugars, unit: "g", level: Self.level(per100.sugars, medium: 5, high: 22.5))
                nutrientRow("Fat", per100.fat, portion.fat, unit: "g", level: Self.level(per100.fat, medium: 3, high: 17.5))
                nutrientRow(
                    "  Saturated",
                    per100.saturatedFat,
                    portion.saturatedFat,
                    unit: "g",
                    level: Self.level(per100.saturatedFat, medium: 1.5, high: 5)
                )
                nutrientRow("Fiber", per100.fiber, portion.fiber, unit: "g", level: nil)
                nutrientRow("Salt", per100.salt, portion.salt, unit: "g", level: Self.level(per100.salt, medium: 0.3, high: 1.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private var portionPicker: some View {
        HStack(spacing: TempoSpacing.sm) {
            if let serving = product.servingGrams, serving > 0, serving != 100 {
                portionChip(product.servingLabel.map { "Serving · \($0)" } ?? "Serving", grams: serving)
            }
            portionChip("100 \(product.unit)", grams: 100)
            Spacer(minLength: 0)
            HStack(spacing: TempoSpacing.xxs) {
                TextField("g", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.tempoBodyBold)
                    .frame(width: 56)
                    .accessibilityIdentifier("foodPortionGrams")
                    .onChange(of: gramsText) { _, text in
                        if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0, value <= 5000 {
                            grams = value
                        }
                    }
                Text(product.unit)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempoBgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }

    private func portionChip(_ label: String, grams value: Double) -> some View {
        let selected = abs(grams - value) < 0.5
        return Button {
            grams = value
            gramsText = Self.format(value)
        } label: {
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(selected ? Color.tempoTextInverse : Color.tempoTextPrimary)
                .lineLimit(1)
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.xs)
                .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func nutrientRow(_ label: String, _ per100: Double?, _ portion: Double?, unit: String, level: Color?) -> some View {
        GridRow {
            HStack(spacing: TempoSpacing.xs) {
                if let level {
                    Circle().fill(level).frame(width: 8, height: 8)
                }
                Text(label)
            }
            .font(.tempoBody)
            .foregroundStyle(Color.tempoTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.amount(per100, unit: unit))
                .foregroundStyle(Color.tempoTextSecondary)
            Text(Self.amount(portion, unit: unit))
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .font(.tempoBody)
        .monospacedDigit()
    }

    // MARK: - Alternatives

    @ViewBuilder
    private var alternativesSection: some View {
        if isLoadingAlternatives || !alternatives.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                sectionTitle("BETTER ALTERNATIVES")
                if isLoadingAlternatives {
                    HStack(spacing: TempoSpacing.sm) {
                        ProgressView()
                        Text("Finding healthier options…")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TempoSpacing.md) {
                            ForEach(alternatives) { alternative in
                                NavigationLink {
                                    FoodProductView(product: alternative, mode: mode, catalog: catalog)
                                } label: {
                                    alternativeCard(alternative)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func alternativeCard(_ alternative: FoodProduct) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                FoodProductThumbnail(product: alternative, size: 112)
                FoodScoreBadge(product: alternative)
                    .padding(TempoSpacing.xs)
            }
            Text(alternative.name)
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(2)
            if let brand = alternative.brand {
                Text(brand)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 112, alignment: .leading)
    }

    private func loadAlternatives() async {
        guard product.source == .openFoodFacts, !product.categories.isEmpty else {
            return
        }
        isLoadingAlternatives = true
        alternatives = await catalog.alternatives(for: product)
        isLoadingAlternatives = false
    }

    // MARK: - Ingredients / allergens

    @ViewBuilder
    private var ingredientsCard: some View {
        if product.ingredientsText != nil || !product.allergens.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                if !product.allergens.isEmpty {
                    sectionTitle("ALLERGENS")
                    Text(product.allergens.map(Self.humanize).joined(separator: ", "))
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                if let ingredients = product.ingredientsText {
                    DisclosureGroup(isExpanded: $showIngredients) {
                        Text(ingredients)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, TempoSpacing.xs)
                    } label: {
                        sectionTitle("INGREDIENTS")
                    }
                    .tint(Color.tempoTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    // MARK: - Attribution

    @ViewBuilder
    private var attribution: some View {
        switch product.source {
        case .openFoodFacts:
            if let code = product.barcode, let url = URL(string: "https://world.openfoodfacts.org/product/\(code)") {
                Link(destination: url) {
                    Text("Data: Open Food Facts contributors (ODbL) — view or fix this product")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        case .usda:
            footnote("Data: USDA FoodData Central")
        case .builtIn:
            footnote("Data: Tempo food table")
        case .userAdded:
            footnote("Added by you")
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    // MARK: - Add bar

    private func addBar(_ onAdd: @escaping (FoodItem) -> Void) -> some View {
        let kcal = Int((product.nutrients(forGrams: grams).kcal ?? 0).rounded())
        return Button {
            HapticManager.success()
            onAdd(product.foodItem(grams: grams))
        } label: {
            Text("Add \(Self.format(grams)) \(product.unit) · \(kcal) kcal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tempoPrimary)
        .disabled(!product.per100g.hasCoreMacros || grams <= 0)
        .accessibilityIdentifier("foodProductAdd")
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    static func format(_ grams: Double) -> String {
        grams == grams.rounded() ? "\(Int(grams))" : String(format: "%.1f", grams)
    }

    static func amount(_ value: Double?, unit: String) -> String {
        guard let value else {
            return "—"
        }
        if unit == "kcal" {
            return "\(Int(value.rounded()))"
        }
        return value < 10 ? String(format: "%.1f %@", value, unit) : "\(Int(value.rounded())) \(unit)"
    }

    /// UK front-of-pack thresholds per 100 g: green / amber / red dot.
    static func level(_ value: Double?, medium: Double, high: Double) -> Color? {
        guard let value else {
            return nil
        }
        if value > high {
            return .tempoError
        }
        return value > medium ? .tempoAmber : .tempoSuccess
    }

    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "a": .tempoSuccess
        case "b": .tempoRecoveryGreen
        case "c": .tempoWarning
        case "d": .tempoAmber
        default: .tempoError
        }
    }

    static func novaText(_ group: Int) -> String {
        switch group {
        case 1: "Unprocessed or minimally processed"
        case 2: "Processed culinary ingredient"
        case 3: "Processed food"
        default: "Ultra-processed food"
        }
    }

    static func humanize(_ tag: String) -> String {
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        return name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
