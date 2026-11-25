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
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    /// The donut and the grams field follow the text size, so the figure inside the ring and the grams never clip.
    @ScaledMetric(relativeTo: .title3)
    private var dial: CGFloat = Tide.Kitchen.verdictDial
    @ScaledMetric(relativeTo: .body)
    private var gramsFieldWidth: CGFloat = Tide.Kitchen.row

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
            VStack(spacing: Tide.s4) {
                header
                if let reason = product.implausibilityReason {
                    implausibilityBanner(reason)
                } else {
                    scoreCard
                }
                forYouCard
                gradesCard
                nutritionCard
                additivesCard
                suggestionsSection
                ingredientsCard
                attribution
            }
            .padding(.horizontal, Tide.s4)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s10)
        }
        .kitchenPage()
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFavorite = catalog.toggleFavorite(product, in: modelContext)
                    HapticManager.lightImpact()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Tide.Kitchen.warn : Tide.text2)
                }
                .accessibilityLabel(isFavorite ? String(localized: "Remove from favourites") : String(localized: "Add to favourites"))
            }
        }
        .safeAreaBar(edge: .bottom) {
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
        HStack(alignment: .top, spacing: Tide.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tide.Kitchen.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Not scored, these numbers look wrong")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Text(reason)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                .strokeBorder(Tide.Kitchen.warn.opacity(0.4), lineWidth: 1)
        )
        .explains(.fuelLabelCheck)
        .accessibilityIdentifier("foodImplausibilityBanner")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            hero
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(product.name)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                if let quantity = product.quantityLabel {
                    Text(quantity)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
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
        Tide.Kitchen.heroPicture * 0.85
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
        .background(Tide.fill)
        .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
        .overlay {
            if isRenderingPhoto {
                ZStack {
                    Tide.ink.opacity(0.55)
                    ProgressView().tint(Tide.text)
                }
                .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
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
                        .scaledToFill()
                        .blur(radius: Tide.s6)
                }
                .overlay(Tide.ink.opacity(0.55))
                .clipped()
            image
                .resizable()
                .scaledToFit()
                .padding(Tide.s4)
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
            Label(photo == nil ? String(localized: "Add a photo") : String(localized: "Change photo"), systemImage: "camera")
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(minHeight: Tide.hit)
        }
        .disabled(isRenderingPhoto)
        .padding(.top, Tide.hair)
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
            VStack(alignment: .leading, spacing: Tide.s4) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s5))
                layout {
                    FoodScoreRing(score: score)
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("Tempo score").tideLabel()
                        Text(score.rating.label)
                            .font(Tide.title)
                            .foregroundStyle(score.rating.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("foodScoreRating")
                        if score.cappedByAdditive {
                            Text("Capped: contains a high-risk additive")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: Tide.s3, verticalSpacing: Tide.s3) {
                    scorePart(String(localized: "Nutrition"), score.nutritionPoints, of: 60)
                    scorePart(String(localized: "Additives"), score.additivePoints, of: 30)
                    scorePart(String(localized: "Organic"), score.organicPoints, of: 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .explains(.fuelTempoScore.showing("\(score.total) / 100"))
        } else {
            KitchenNotice(
                systemImage: "questionmark.circle.fill",
                text: String(localized: "Not enough data to score. \(missingForScore)"),
                tint: Tide.Kitchen.warn
            )
        }
    }

    private var missingForScore: String {
        let n = product.per100g
        let missing = [(String(localized: "calories"), n.kcal), (String(localized: "carbs or sugars"), n.sugars ?? n.carbs), (String(localized: "fat"), n.saturatedFat ?? n.fat), (String(localized: "salt"), n.salt)]
            .filter { $0.1 == nil }
            .map(\.0)
        guard !missing.isEmpty else {
            return String(localized: "The nutrition table is incomplete for this product.")
        }
        return String(localized: "Missing from the nutrition table: \(missing.joined(separator: ", ")).")
    }

    private func scorePart(_ label: String, _ points: Int, of max: Int) -> some View {
        GridRow {
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .gridColumnAlignment(.leading)
            TideLevelBar(
                progress: max > 0 ? Double(points) / Double(max) : 0,
                color: score?.rating.color ?? mood.accent,
                height: Tide.bar
            )
            .accessibilityHidden(true)
            Text("\(points)/\(max)")
                .font(Tide.caption)
                .monospacedDigit()
                .foregroundStyle(Tide.text3)
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Macros

    /// The donut and its legend, inside the Nutrition card (it follows the portion picker above it).
    @ViewBuilder
    private func macroSummary(_ portion: FoodProduct.Nutrients) -> some View {
        if let split = FoodMacroSplit.compute(proteinGrams: portion.protein, carbsGrams: portion.carbs, fatGrams: portion.fat) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
                : AnyLayout(HStackLayout(spacing: Tide.s5))
            layout {
                Chart(split.slices) { slice in
                    SectorMark(angle: .value("Calories", slice.kcal), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(slice.color)
                        .cornerRadius(Tide.hair)
                }
                .frame(width: dial, height: dial)
                .chartLegend(.hidden)
                .overlay {
                    VStack(spacing: 0) {
                        // Ring segments are macro shares (Atwater), but the
                        // number shown must always be the product's label
                        // kcal — the same figure as the nutrition table and
                        // the add bar — so the two never disagree (picky-QA
                        // item 2).
                        TideNumber(
                            "\(Int((portion.kcal ?? split.totalKcal).rounded()))",
                            size: Tide.numeralS,
                            relativeTo: .title3
                        )
                        Text("kcal")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    // Whatever the text size, the figure stays inside the hole of the ring.
                    .minimumScaleFactor(Tide.labelShrink)
                    .lineLimit(1)
                    .frame(maxWidth: dial * 0.56)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(macroAccessibilityLabel(split, labelKcal: portion.kcal))
                Grid(alignment: .leading, horizontalSpacing: Tide.s3, verticalSpacing: Tide.s2) {
                    ForEach(split.slices) { slice in
                        macroLegendRow(slice)
                    }
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
            }
            .animation(Tide.settle, value: grams)
        }
    }

    private func macroLegendRow(_ slice: FoodMacroSplit.Slice) -> some View {
        GridRow {
            HStack(spacing: Tide.s2) {
                Circle()
                    .fill(slice.color)
                    .frame(width: Tide.Kitchen.dot, height: Tide.Kitchen.dot)
                Text(slice.label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            Text("\(Int(slice.grams.rounded()))g")
                .font(Tide.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(Tide.text)
                .gridColumnAlignment(.trailing)
            Text("\(Int((slice.percent * 100).rounded()))%")
                .font(Tide.caption)
                .monospacedDigit()
                .foregroundStyle(Tide.text3)
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func macroAccessibilityLabel(_ split: FoodMacroSplit, labelKcal: Double?) -> String {
        let macros = split.slices.map { String(localized: "\($0.label) \(Int((($0.percent) * 100).rounded())) percent") }.joined(separator: ", ")
        guard let labelKcal else {
            return macros
        }
        return String(localized: "\(Int(labelKcal.rounded())) kcal — \(macros)")
    }

    // MARK: - For you

    @ViewBuilder
    private var forYouCard: some View {
        let checks = FoodFit.checks(for: product.mergingAllergenData(from: enrichedAllergenSource), grams: grams, context: fitContext)
        if !checks.isEmpty {
            // The card wears the colour of its worst line, so a conflict is
            // seen before a word is read.
            let worst: FoodFitCheck.Kind = checks.contains { $0.kind == .conflict }
                ? .conflict
                : (checks.contains { $0.kind == .warning } ? .warning : .good)
            VStack(alignment: .leading, spacing: Tide.s3) {
                sectionTitle(String(localized: "For you · \(Self.format(grams)) \(product.unit)"))
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: Tide.s3) {
                        Image(systemName: check.kind.icon)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(check.kind.color)
                            .frame(width: Tide.icon, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(check.text)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .overlay(
                RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                    .strokeBorder(worst.color.opacity(0.45), lineWidth: 1)
            )
            .explains(.fuelForYou)
            .animation(Tide.snap, value: grams)
        }
    }

    // MARK: - Nutri-Score + NOVA

    /// A card of its own under the verdict, so the verdict card stays short enough
    /// to clear the action bar at the first scroll position.
    @ViewBuilder
    private var gradesCard: some View {
        if score != nil || product.novaGroup != nil {
            gradesContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard()
        }
    }

    private var gradesContent: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            if let score {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    sectionTitle(score.nutriScoreEstimated ? String(localized: "Nutri-Score · estimated") : "Nutri-Score")
                    HStack(spacing: Tide.s1) {
                        ForEach(NutriScore.grades, id: \.self) { grade in
                            let selected = grade == score.nutriScoreGrade
                            Text(grade.uppercased())
                                .font(selected ? Tide.headline : Tide.caption)
                                .foregroundStyle(selected ? Tide.ink : Tide.text3)
                                .frame(maxWidth: .infinity)
                                .frame(height: selected ? Tide.s10 : Tide.s8)
                                .background(selected ? Self.gradeColor(grade) : Tide.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(Tide.snap, value: score.nutriScoreGrade)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nutri-Score \(score.nutriScoreGrade.uppercased())")
                }
                .explains(.fuelNutriScore.showing(score.nutriScoreGrade.uppercased()))
            }
            if let nova = product.novaGroup {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    sectionTitle(String(localized: "Processing · NOVA \(nova)"))
                    Text(Self.novaText(nova))
                        .font(Tide.body)
                        .foregroundStyle(nova == 4 ? Tide.Kitchen.warn : Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .explains(.fuelNova.showing(String(localized: "Group \(nova)")))
            }
        }
    }

    // MARK: - Additives

    @ViewBuilder
    private var additivesCard: some View {
        if let score, product.source == .openFoodFacts || product.source == .userAdded {
            VStack(alignment: .leading, spacing: Tide.s2) {
                sectionTitle(String(localized: "Additives · \(score.additives.count)"))
                if score.additives.isEmpty {
                    Label("No additives", systemImage: "checkmark.circle.fill")
                        .font(Tide.body)
                        .foregroundStyle(Tide.Kitchen.good)
                } else {
                    ForEach(score.additives) { additive in
                        HStack(alignment: .top, spacing: Tide.s2) {
                            Circle()
                                .fill(additive.risk.color)
                                .frame(width: Tide.Kitchen.dot, height: Tide.Kitchen.dot)
                                .padding(.top, Tide.s1)
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text("\(additive.displayCode) · \(additive.name)")
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(Tide.text)
                                Text(additive.note.map { "\(additive.risk.label) — \($0)" } ?? additive.risk.label)
                                    .font(Tide.caption)
                                    .foregroundStyle(additive.risk == .unknown ? Tide.text2 : additive.risk.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .explains(.fuelAdditives)
        }
    }

    // MARK: - Nutrition

    private var showsPortionColumn: Bool {
        abs(grams - 100) >= 0.5
    }

    private var nutritionCard: some View {
        let per100 = product.per100g
        let portion = product.nutrients(forGrams: grams)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            sectionTitle(String(localized: "Nutrition"))
            portionPicker
            macroSummary(portion)
            Grid(alignment: .leading, horizontalSpacing: Tide.s3, verticalSpacing: Tide.s2) {
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
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                Rectangle().fill(Tide.hairline).frame(height: 1)
                    .accessibilityHidden(true)
                nutrientRow(String(localized: "Calories"), per100.kcal, portion.kcal, unit: "kcal", level: nil)
                nutrientRow(String(localized: "Protein"), per100.protein, portion.protein, unit: "g", level: nil)
                nutrientRow(String(localized: "Carbs"), per100.carbs, portion.carbs, unit: "g", level: nil)
                nutrientRow("  \(String(localized: "Sugars"))", per100.sugars, portion.sugars, unit: "g", level: Self.level(per100.sugars, medium: 5, high: 22.5))
                nutrientRow(String(localized: "Fat"), per100.fat, portion.fat, unit: "g", level: Self.level(per100.fat, medium: 3, high: 17.5))
                nutrientRow(
                    "  \(String(localized: "Saturated"))",
                    per100.saturatedFat,
                    portion.saturatedFat,
                    unit: "g",
                    level: Self.level(per100.saturatedFat, medium: 1.5, high: 5)
                )
                nutrientRow(String(localized: "Fiber"), per100.fiber, portion.fiber, unit: "g", level: nil)
                nutrientRow(String(localized: "Salt"), per100.salt, portion.salt, unit: "g", level: Self.level(per100.salt, medium: 0.3, high: 1.5))
            }
            .explains(.fuelTrafficLights)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
    }

    /// The portion the whole card is about: two quick chips and a free grams field.
    /// At the accessibility sizes the field drops under the chips.
    private var portionPicker: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            HStack(spacing: Tide.s2) {
                if let serving = product.servingGrams, serving > 0, serving != 100 {
                    portionChip(product.servingLabel.map { String(localized: "Serving · \($0)") } ?? String(localized: "Serving"), grams: serving)
                }
                portionChip("100 \(product.unit)", grams: 100)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            HStack(spacing: Tide.hair) {
                TextField("g", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Tide.bodyStrong)
                    .frame(width: gramsFieldWidth)
                    .accessibilityIdentifier("foodPortionGrams")
                    .onChange(of: gramsText) { _, text in
                        if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0, value <= 5000 {
                            grams = value
                        }
                    }
                Text(product.unit)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            .padding(.horizontal, Tide.s3)
            .frame(minHeight: Tide.hit)
            .background(Tide.fill)
            .clipShape(.capsule)
        }
    }

    private func portionChip(_ label: String, grams value: Double) -> some View {
        let selected = abs(grams - value) < 0.5
        return Button {
            grams = value
            gramsText = Self.format(value)
        } label: {
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(selected ? Tide.ink : Tide.text)
                .lineLimit(1)
                .padding(.horizontal, Tide.s3)
                .frame(minHeight: Tide.hit)
                .background(selected ? mood.accent : Tide.fill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func nutrientRow(_ label: String, _ per100: Double?, _ portion: Double?, unit: String, level: Color?) -> some View {
        GridRow {
            HStack(spacing: Tide.s1) {
                if let level {
                    Circle().fill(level).frame(width: Tide.Kitchen.dot, height: Tide.Kitchen.dot)
                }
                Text(label)
            }
            .font(Tide.body)
            .foregroundStyle(Tide.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsPortionColumn {
                Text(Self.amount(per100, unit: unit))
                    .foregroundStyle(Tide.text2)
                Text(Self.amount(portion, unit: unit))
                    .fontWeight(.semibold)
                    .foregroundStyle(Tide.text)
            } else {
                Text(Self.amount(per100, unit: unit))
                    .fontWeight(.semibold)
                    .foregroundStyle(Tide.text)
            }
        }
        .font(Tide.body)
        .monospacedDigit()
    }

    // MARK: - Suggestions

    /// Always shown — healthier swaps when they exist, equally good peers
    /// otherwise. Never disappears: skeleton while loading, a friendly line
    /// if truly nothing turned up.
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            sectionTitle(isLoadingSuggestions ? String(localized: "Suggestions") : suggestions.kind.sectionTitle)
            if isLoadingSuggestions {
                suggestionsSkeleton
            } else if suggestions.items.isEmpty {
                Text("Nothing else on the shelf right now — check back after your next scan.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
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
                    HStack(spacing: Tide.s3) {
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
        HStack(spacing: Tide.s3) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Tide.s1) {
                    RoundedRectangle(cornerRadius: Tide.controlRadius)
                        .fill(Tide.text3.opacity(0.3))
                        .frame(width: Tide.Kitchen.suggestion, height: Tide.Kitchen.suggestion)
                    RoundedRectangle(cornerRadius: Tide.controlRadius)
                        .fill(Tide.text3.opacity(0.3))
                        .frame(width: Tide.Kitchen.suggestion * 0.8, height: Tide.s3)
                    RoundedRectangle(cornerRadius: Tide.controlRadius)
                        .fill(Tide.text3.opacity(0.3))
                        .frame(width: Tide.Kitchen.suggestion * 0.5, height: Tide.s3)
                }
            }
        }
        .shimmer()
    }

    private func suggestionCard(_ item: FoodProduct) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            ZStack(alignment: .topTrailing) {
                FoodProductThumbnail(product: item, size: Tide.Kitchen.suggestion)
                FoodScoreBadge(product: item)
                    .padding(Tide.s1)
            }
            Text(item.name)
                .font(Tide.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Tide.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let brand = item.brand {
                Text(brand)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
        }
        .frame(width: Tide.Kitchen.suggestion, alignment: .leading)
    }

    private func suggestionCardWide(_ item: FoodProduct) -> some View {
        HStack(spacing: Tide.s3) {
            ZStack(alignment: .topTrailing) {
                FoodProductThumbnail(product: item, size: Tide.Kitchen.suggestionWide)
                FoodScoreBadge(product: item)
                    .padding(Tide.hair)
            }
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(item.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                if let brand = item.brand {
                    Text(brand)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
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
            VStack(alignment: .leading, spacing: Tide.s2) {
                if claimsAllergenData {
                    sectionTitle(String(localized: "Allergens"))
                    if allergens.isEmpty, traces.isEmpty, ingredients == nil {
                        // Never silently omit the section — say plainly that
                        // the maker gave us nothing to go on (picky-QA item 3).
                        Text("No allergen info from the maker — check the pack.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    } else {
                        if !allergens.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Tide.s1) {
                                    ForEach(allergens, id: \.self) { allergen in
                                        allergenChip(allergen)
                                    }
                                }
                            }
                        }
                        if !traces.isEmpty {
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text("May contain").tideLabel(Tide.text3)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: Tide.s1) {
                                        ForEach(traces, id: \.self) { trace in
                                            traceChip(trace)
                                        }
                                    }
                                }
                            }
                        }
                        if allergens.isEmpty, traces.isEmpty {
                            Text("No allergens declared by the maker.")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                }
                if let ingredients {
                    DisclosureGroup(isExpanded: $showIngredients) {
                        Text(ingredients)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Tide.s1)
                    } label: {
                        sectionTitle(String(localized: "Ingredients"))
                    }
                    .tint(Tide.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .accessibilityIdentifier("foodAllergensCard")
        }
    }

    private func allergenChip(_ text: String) -> some View {
        Text(text)
            .font(Tide.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Tide.danger)
            .padding(.horizontal, Tide.s3)
            .padding(.vertical, Tide.s1)
            .background(Tide.danger.opacity(0.15))
            .clipShape(Capsule())
    }

    /// "May contain" trace chips — a softer, secondary treatment than a
    /// confirmed allergen: same shape, amber instead of red.
    private func traceChip(_ text: String) -> some View {
        Text(text)
            .font(Tide.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Tide.Kitchen.warn)
            .padding(.horizontal, Tide.s3)
            .padding(.vertical, Tide.s1)
            .background(Tide.Kitchen.warn.opacity(0.15))
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
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .multilineTextAlignment(.center)
                }
            }
        case .usda:
            footnote(String(localized: "Data: USDA FoodData Central"))
        case .builtIn:
            footnote(String(localized: "Data: Tempo food table"))
        case .userAdded:
            footnote(String(localized: "Added by you"))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.tidePrimary)
        .disabled(!product.per100g.hasCoreMacros || grams <= 0)
        .accessibilityIdentifier("foodProductAdd")
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s3)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text).tideLabel()
    }

    static func format(_ grams: Double) -> String {
        grams == grams.rounded() ? "\(Int(grams))" : grams.tempoDecimal(1)
    }

    static func amount(_ value: Double?, unit: String) -> String {
        guard let value else {
            return "—"
        }
        if unit == "kcal" {
            return "\(Int(value.rounded()))"
        }
        return value < 10 ? "\(value.tempoDecimal(1)) \(unit)" : "\(Int(value.rounded())) \(unit)"
    }

    /// UK front-of-pack thresholds per 100 g: green / amber / red dot.
    static func level(_ value: Double?, medium: Double, high: Double) -> Color? {
        guard let value else {
            return nil
        }
        if value > high {
            return Tide.danger
        }
        return value > medium ? Tide.Kitchen.warn : Tide.Kitchen.good
    }

    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "a": Tide.Kitchen.good
        case "b": Tide.Kitchen.good
        case "c": Tide.Kitchen.warn
        case "d": Tide.Kitchen.warn
        default: Tide.danger
        }
    }

    static func novaText(_ group: Int) -> String {
        switch group {
        case 1: String(localized: "Unprocessed or minimally processed")
        case 2: String(localized: "Processed culinary ingredient")
        case 3: String(localized: "Processed food")
        default: String(localized: "Ultra-processed food")
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
                color: Tide.protein,
                label: String(localized: "Protein")
            ),
            Slice(
                macro: .carbs,
                kcal: carbsKcal,
                grams: carbsKcal / 4,
                percent: carbsKcal / totalKcal,
                color: Tide.carbs,
                label: String(localized: "Carbs")
            ),
            Slice(macro: .fat, kcal: fatKcal, grams: fatKcal / 9, percent: fatKcal / totalKcal, color: Tide.fat, label: String(localized: "Fat")),
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
        case .healthier: String(localized: "Healthier swaps")
        case .similar: String(localized: "Also great")
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
