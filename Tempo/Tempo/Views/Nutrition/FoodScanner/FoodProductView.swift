//
// FoodProductView.swift
// Tempo
//
// The "internal Yuka" screen for one product: Tempo score (nutrition,
// additives, organic), what it means for YOU today (calories left, allergies,
// clear-skin mode…), Nutri-Score + NOVA, additives with risk levels,
// nutrients per 100 g and per portion, better alternatives, favourite, and —
// when opened from meal logging — "Add to meal"; from Food check — Log,
// Add to pantry and Add to list.
//

import Charts
import SwiftData
import SwiftUI

// MARK: - FoodProductView

struct FoodProductView: View {
    enum Mode {
        /// Food check: score first, then Log / Add to pantry / Add to list.
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
    private var suggestions = FoodSuggestions.empty
    @State
    private var isLoadingSuggestions = true
    @State
    private var showIngredients = false
    @State
    private var photoSource: PhotoSource?
    @State
    private var isRenderingPhoto = false
    @State
    private var heroPage = 0
    @State
    private var showGalleryViewer = false
    /// Filled in when the search hit that opened this page came back with no
    /// allergen/ingredient data — see `FoodCatalog.enrichAllergensIfMissing`.
    @State
    private var enrichedAllergenSource: FoodProduct?
    @State
    private var toast: ToastData?

    private struct PhotoSource: Identifiable {
        let type: UIImagePickerController.SourceType
        var id: Int {
            type.rawValue
        }
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
                if let reason = product.implausibilityReason {
                    implausibilityBanner(reason)
                } else {
                    scoreCard
                }
                macroCard
                forYouCard
                gradesCard
                additivesCard
                nutritionCard
                suggestionsSection
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
            switch mode {
            case let .log(onAdd):
                addBar(onAdd)
            case .check:
                FoodProductActionBar(product: product, grams: grams, toast: $toast) {
                    catalog.rememberPortion(grams, for: product, in: modelContext)
                }
            }
        }
        .tempoToast($toast)
        .task(id: product.id) {
            if recordsView {
                catalog.recordView(product, in: modelContext)
            }
            isFavorite = catalog.isFavorite(product, in: modelContext)
            photo = catalog.photo(for: product, in: modelContext)
            fitContext = FoodFitContext.loadToday(in: modelContext, whoopAvgTDEE: services.whoop.weeklyTDEEAverage)
            if let remembered = catalog.lastPortionGrams(for: product, in: modelContext), remembered > 0 {
                grams = remembered
                gramsText = Self.format(remembered)
            }
            async let suggestionsTask: Void = loadSuggestions()
            async let enrichTask = catalog.enrichAllergensIfMissing(for: product)
            _ = await suggestionsTask
            enrichedAllergenSource = await enrichTask
        }
    }

    // MARK: - Implausible data

    private func implausibilityBanner(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tempoAmber)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text("Not scored — these numbers look wrong")
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(reason)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoAmber.opacity(TempoOpacity.o15))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        .accessibilityIdentifier("foodImplausibilityBanner")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            hero
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
                if !hasAnyHeroImage {
                    addPhotoMenu
                }
            }
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

    // MARK: - Hero

    private var hasAnyHeroImage: Bool {
        photo != nil || product.imageURL != nil || product.imageSmallURL != nil || !(product.galleryImageURLs?.isEmpty ?? true)
    }

    private var heroHeight: CGFloat {
        280
    }

    /// Every page the full-screen viewer can show, in display order.
    private var heroSources: [FoodHeroSource] {
        if let photo {
            return [.local(photo)]
        }
        if let gallery = product.galleryImageURLs, !gallery.isEmpty {
            return gallery.map(FoodHeroSource.remote)
        }
        if let main = product.imageURL ?? product.imageSmallURL {
            return [.remote(main)]
        }
        return []
    }

    private var hero: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                heroImage(Image(uiImage: image))
                    .onTapGesture { showGalleryViewer = true }
            } else if let gallery = product.galleryImageURLs, !gallery.isEmpty {
                TabView(selection: $heroPage) {
                    ForEach(Array(gallery.enumerated()), id: \.offset) { index, url in
                        FoodRemoteImage(url: url, product: product, contentMode: .fit, showsBlurredBackdrop: true)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: gallery.count > 1 ? .always : .never))
                .onTapGesture { showGalleryViewer = true }
            } else {
                FoodRemoteImage(
                    url: product.imageURL ?? product.imageSmallURL,
                    product: product,
                    contentMode: .fit,
                    showsBlurredBackdrop: true
                )
                .onTapGesture {
                    if hasAnyHeroImage {
                        showGalleryViewer = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay {
            if isRenderingPhoto {
                ZStack {
                    Color.black.opacity(TempoOpacity.o40)
                    ProgressView().tint(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }
        }
        .fullScreenCover(isPresented: $showGalleryViewer) {
            FoodImageGalleryViewer(sources: heroSources, product: product, page: $heroPage)
        }
    }

    /// Aspect-fit photo over a blurred, scaled-to-fill copy of the same
    /// image as the backdrop (Apple-Music-style) instead of flat-colour
    /// letterboxing either side of a tall/narrow photo.
    private func heroImage(_ image: Image) -> some View {
        ZStack {
            Color.clear
                .overlay {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 24)
                }
                .overlay(Color.black.opacity(TempoOpacity.o40))
                .clipped()
            image
                .resizable()
                .scaledToFit()
                .padding(TempoSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Macros

    @ViewBuilder
    private var macroCard: some View {
        let portion = product.nutrients(forGrams: grams)
        if let split = FoodMacroSplit.compute(proteinGrams: portion.protein, carbsGrams: portion.carbs, fatGrams: portion.fat) {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                sectionTitle("MACROS · \(Self.format(grams)) \(product.unit)")
                HStack(spacing: TempoSpacing.xl) {
                    Chart(split.slices) { slice in
                        SectorMark(angle: .value("Calories", slice.kcal), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(slice.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 108, height: 108)
                    .chartLegend(.hidden)
                    .overlay {
                        VStack(spacing: 0) {
                            // Ring segments are macro shares (Atwater), but the
                            // number shown must always be the product's label
                            // kcal — the same figure as the nutrition table and
                            // the add bar — so the two never disagree (picky-QA
                            // item 2).
                            Text("\(Int((portion.kcal ?? split.totalKcal).rounded()))")
                                .font(.tempoHeadline)
                                .monospacedDigit()
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text("kcal")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(macroAccessibilityLabel(split, labelKcal: portion.kcal))
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        ForEach(split.slices) { slice in
                            macroLegendRow(slice)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
        }
    }

    private func macroLegendRow(_ slice: FoodMacroSplit.Slice) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Circle()
                .fill(slice.color)
                .frame(width: 8, height: 8)
            Text(slice.label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 52, alignment: .leading)
            Text("\(Int(slice.grams.rounded()))g")
                .font(.tempoBodyBold)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            Text("· \(Int((slice.percent * 100).rounded()))%")
                .font(.tempoCaption2)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func macroAccessibilityLabel(_ split: FoodMacroSplit, labelKcal: Double?) -> String {
        let macros = split.slices.map { "\($0.label) \(Int((($0.percent) * 100).rounded())) percent" }.joined(separator: ", ")
        guard let labelKcal else {
            return macros
        }
        return "\(Int(labelKcal.rounded())) kcal — \(macros)"
    }

    // MARK: - For you

    @ViewBuilder
    private var forYouCard: some View {
        let checks = FoodFit.checks(for: product.mergingAllergenData(from: enrichedAllergenSource), grams: grams, context: fitContext)
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

    private var showsPortionColumn: Bool {
        abs(grams - 100) >= 0.5
    }

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
                    // At exactly 100 g the portion column would repeat the first.
                    if showsPortionColumn {
                        Text("\(Self.format(grams)) \(product.unit)")
                            .gridColumnAlignment(.trailing)
                    }
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
            if showsPortionColumn {
                Text(Self.amount(per100, unit: unit))
                    .foregroundStyle(Color.tempoTextSecondary)
                Text(Self.amount(portion, unit: unit))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
            } else {
                Text(Self.amount(per100, unit: unit))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
        }
        .font(.tempoBody)
        .monospacedDigit()
    }

    // MARK: - Suggestions

    /// Always shown — healthier swaps when they exist, equally good peers
    /// otherwise. Never disappears: skeleton while loading, a friendly line
    /// if truly nothing turned up.
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionTitle(isLoadingSuggestions ? "SUGGESTIONS" : suggestions.kind.sectionTitle.uppercased())
            if isLoadingSuggestions {
                suggestionsSkeleton
            } else if suggestions.items.isEmpty {
                Text("Nothing else on the shelf right now — check back after your next scan.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else if suggestions.items.count == 1, let item = suggestions.items.first {
                // A single tile in a horizontal scroller reads as an orphaned
                // left-aligned card with dead space beside it — give it the
                // full row instead (picky-QA item 7).
                NavigationLink {
                    FoodProductView(product: item, mode: mode, catalog: catalog)
                } label: {
                    suggestionCardWide(item)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TempoSpacing.md) {
                        ForEach(suggestions.items) { item in
                            NavigationLink {
                                FoodProductView(product: item, mode: mode, catalog: catalog)
                            } label: {
                                suggestionCard(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionsSkeleton: some View {
        HStack(spacing: TempoSpacing.md) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    RoundedRectangle(cornerRadius: TempoRadius.md)
                        .fill(Color.tempoTextDisabled.opacity(0.3))
                        .frame(width: 112, height: 112)
                    RoundedRectangle(cornerRadius: TempoRadius.sm)
                        .fill(Color.tempoTextDisabled.opacity(0.3))
                        .frame(width: 90, height: 12)
                    RoundedRectangle(cornerRadius: TempoRadius.sm)
                        .fill(Color.tempoTextDisabled.opacity(0.3))
                        .frame(width: 60, height: 10)
                }
            }
        }
        .shimmer()
    }

    private func suggestionCard(_ item: FoodProduct) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                FoodProductThumbnail(product: item, size: 112)
                FoodScoreBadge(product: item)
                    .padding(TempoSpacing.xs)
            }
            Text(item.name)
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(2)
            if let brand = item.brand {
                Text(brand)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 112, alignment: .leading)
    }

    private func suggestionCardWide(_ item: FoodProduct) -> some View {
        HStack(spacing: TempoSpacing.md) {
            ZStack(alignment: .topTrailing) {
                FoodProductThumbnail(product: item, size: 72)
                FoodScoreBadge(product: item)
                    .padding(TempoSpacing.xxs)
            }
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(item.name)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                if let brand = item.brand {
                    Text(brand)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestions = await catalog.suggestions(for: product, context: fitContext)
        isLoadingSuggestions = false
    }

    // MARK: - Ingredients / allergens

    /// The search index (search-a-licious) frequently omits allergen/trace/
    /// ingredient fields that the full OFF record actually has — when that
    /// happened, `enrichedAllergenSource` carries the re-fetched record.
    /// Falls back to `product` once there's nothing left to fill in.
    private var effectiveAllergenSource: FoodProduct {
        enrichedAllergenSource ?? product
    }

    /// Only sources that plausibly ship allergen data at all (OFF and
    /// user-added labels) — a built-in/USDA table entry was never asked, so
    /// don't warn about it as if the maker stayed silent.
    private var claimsAllergenData: Bool {
        product.source == .openFoodFacts || product.source == .userAdded
    }

    @ViewBuilder
    private var ingredientsCard: some View {
        let source = effectiveAllergenSource
        let allergens = source.displayAllergens
        let traces = source.displayTraces
        let ingredients = source.ingredientsText ?? product.ingredientsText
        if claimsAllergenData || ingredients != nil {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                if claimsAllergenData {
                    sectionTitle("ALLERGENS")
                    if allergens.isEmpty, traces.isEmpty, ingredients == nil {
                        // Never silently omit the section — say plainly that
                        // the maker gave us nothing to go on (picky-QA item 3).
                        Text("No allergen info from the maker — check the pack.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else {
                        if !allergens.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: TempoSpacing.xs) {
                                    ForEach(allergens, id: \.self) { allergen in
                                        allergenChip(allergen)
                                    }
                                }
                            }
                        }
                        if !traces.isEmpty {
                            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                                Text("MAY CONTAIN")
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: TempoSpacing.xs) {
                                        ForEach(traces, id: \.self) { trace in
                                            traceChip(trace)
                                        }
                                    }
                                }
                            }
                        }
                        if allergens.isEmpty, traces.isEmpty {
                            Text("No allergens declared by the maker.")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
                if let ingredients {
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
            .accessibilityIdentifier("foodAllergensCard")
        }
    }

    private func allergenChip(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoError)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempoError.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
    }

    /// "May contain" trace chips — a softer, secondary treatment than a
    /// confirmed allergen: same shape, amber instead of red.
    private func traceChip(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoAmber)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempoAmber.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
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
            catalog.rememberPortion(grams, for: product, in: modelContext)
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
}

// MARK: - FoodHeroSource

/// One page the hero / full-screen viewer can show.
enum FoodHeroSource: Identifiable, Hashable {
    case local(Data)
    case remote(URL)

    var id: String {
        switch self {
        case let .local(data): "local-\(data.count)-\(data.hashValue)"
        case let .remote(url): url.absoluteString
        }
    }
}

// MARK: - FoodMacroSplit

/// Calories split three ways from portion grams (protein/carbs 4 kcal/g, fat
/// 9 kcal/g) — drives the product page's macro donut.
struct FoodMacroSplit: Equatable {
    struct Slice: Identifiable, Equatable {
        enum Macro: String {
            case protein
            case carbs
            case fat
        }

        let macro: Macro
        let kcal: Double
        let grams: Double
        let percent: Double
        let color: Color
        let label: String

        var id: String {
            macro.rawValue
        }
    }

    var proteinKcal: Double
    var carbsKcal: Double
    var fatKcal: Double

    var totalKcal: Double {
        proteinKcal + carbsKcal + fatKcal
    }

    var slices: [Slice] {
        guard totalKcal > 0 else {
            return []
        }
        return [
            Slice(
                macro: .protein,
                kcal: proteinKcal,
                grams: proteinKcal / 4,
                percent: proteinKcal / totalKcal,
                color: .tempoMacroProtein,
                label: "Protein"
            ),
            Slice(
                macro: .carbs,
                kcal: carbsKcal,
                grams: carbsKcal / 4,
                percent: carbsKcal / totalKcal,
                color: .tempoMacroCarbs,
                label: "Carbs"
            ),
            Slice(macro: .fat, kcal: fatKcal, grams: fatKcal / 9, percent: fatKcal / totalKcal, color: .tempoMacroFat, label: "Fat"),
        ]
    }

    /// `nil` when there isn't enough data (any macro missing) or all three are zero.
    static func compute(proteinGrams: Double?, carbsGrams: Double?, fatGrams: Double?) -> FoodMacroSplit? {
        guard let proteinGrams, let carbsGrams, let fatGrams,
              proteinGrams >= 0, carbsGrams >= 0, fatGrams >= 0
        else {
            return nil
        }
        let split = FoodMacroSplit(proteinKcal: proteinGrams * 4, carbsKcal: carbsGrams * 4, fatKcal: fatGrams * 9)
        return split.totalKcal > 0 ? split : nil
    }
}

// MARK: - FoodSuggestions.Kind copy

extension FoodSuggestions.Kind {
    /// Section title shown above the suggestions row.
    var sectionTitle: String {
        switch self {
        case .healthier: "Healthier swaps"
        case .similar: "Also great"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FoodProductView(
            product: FoodProduct(
                id: "0000000000017",
                barcode: "0000000000017",
                name: "Nonfat Greek Yogurt",
                brand: "Chobani",
                source: .openFoodFacts,
                quantityLabel: "32 oz",
                servingLabel: "150 g",
                servingGrams: 150,
                per100g: .init(kcal: 53, protein: 9.4, carbs: 3.5, sugars: 3.5, fat: 0, saturatedFat: 0, fiber: 0, salt: 0.1),
                nutriScoreGrade: "a",
                nutriScorePoints: -3,
                novaGroup: 3,
                additives: [],
                allergens: ["milk"],
                labels: [],
                categories: ["dairies", "yogurts"],
                ingredientsAnalysis: [],
                ingredientsText: "Cultured pasteurized nonfat milk."
            ),
            catalog: FoodCatalog(services: .mock())
        )
    }
    .environment(ServiceContainer.mock())
    .modelContainer(for: [ScannedFood.self], inMemory: true)
}
