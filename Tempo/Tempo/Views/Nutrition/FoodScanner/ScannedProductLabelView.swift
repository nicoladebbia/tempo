//
// ScannedProductLabelView.swift
// Tempo
//
// Label mode after a barcode scan: the product just scanned, its nutrition
// facts per 100 g or per serving, a calorie + macro split, UK traffic-light
// levels, what it means for the user's plan, and ingredients with the user's
// allergens highlighted. Log / Pantry / List sit in the same bottom bar as the
// product page. If the label is missing or wrong, "Photograph the label"
// re-reads it for THIS product (same barcode) instead of starting a new one.
//

import SwiftData
import SwiftUI

struct ScannedProductLabelView: View {
    let product: FoodProduct
    let catalog: FoodCatalog
    let onUpdated: (FoodProduct) -> Void
    let onScanAnother: () -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var showEditor = false
    @State
    private var basis: LabelFacts.Basis = .per100
    @State
    private var showIngredients = false
    @State
    private var fitContext = FoodFitContext.none
    @State
    private var toast: ToastData?
    @ScaledMetric
    private var thumb: CGFloat = Tide.Kitchen.heroDisc
    @ScaledMetric
    private var glyph: CGFloat = Tide.s5 + Tide.hair
    @ScaledMetric
    private var levelWidth: CGFloat = Tide.Kitchen.heroDisc - Tide.s8

    private var hasLabel: Bool {
        product.per100g.hasCoreMacros
    }

    private var grams: Double {
        LabelFacts.grams(for: basis, product: product)
    }

    private var shown: FoodProduct.Nutrients {
        LabelFacts.nutrients(for: basis, product: product)
    }

    private var basisLabel: String {
        basis == .perServing ? "per serving · \(FoodProductView.format(grams)) \(product.unit)" : "per 100 \(product.unit)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s4) {
                header
                if let reason = product.implausibilityReason {
                    warning(reason + " Check the label and fix it if it's wrong.")
                }
                if hasLabel {
                    if LabelFacts.servingGrams(of: product) != nil {
                        basisPicker
                    }
                    caloriesCard
                    levelsCard
                    fitCard
                } else {
                    missingCard
                }
                ingredientsCard
                secondaryActions
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s5)
            .frame(maxWidth: .infinity)
        }
        .kitchenPage()
        .scrollEdgeEffectStyle(.soft, for: .all)
        .accessibilityIdentifier("scannedProductLabel")
        .safeAreaBar(edge: .bottom) {
            FoodProductActionBar(product: product, grams: grams, toast: $toast) {
                catalog.rememberPortion(grams, for: product, in: modelContext)
            }
        }
        .tempoToast($toast)
        .task(id: product.id) {
            basis = .per100
            fitContext = FoodFitContext.loadToday(in: modelContext, whoopAvgTDEE: services.whoop.weeklyTDEEAverage)
            if let remembered = catalog.lastPortionGrams(for: product, in: modelContext),
               let serving = LabelFacts.servingGrams(of: product), abs(remembered - serving) < 0.5
            {
                basis = .perServing
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AddProductView(barcode: product.barcode, catalog: catalog, prefill: product) { updated in
                    showEditor = false
                    onUpdated(updated)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditor = false }
                    }
                }
            }
            .kitchenSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return layout {
            FoodRemoteImage(url: product.imageURL ?? product.imageSmallURL, product: product, contentMode: .fit)
                .frame(width: thumb, height: thumb)
                .background(Tide.fill)
                .clipShape(RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(product.name)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(1)
                }
                let idLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.hair))
                    : AnyLayout(HStackLayout(spacing: Tide.s1))
                idLayout {
                    if let barcode = product.barcode {
                        Label(barcode, systemImage: "barcode")
                            .font(Tide.caption)
                            .monospacedDigit()
                            .foregroundStyle(Tide.text3)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                    }
                    if let quantity = product.quantityLabel {
                        Text(typeSize.isAccessibilitySize ? quantity : "· \(quantity)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .lineLimit(1)
                    }
                }
                gradeBadges
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var gradeBadges: some View {
        let score = FoodScore.evaluate(product)
        if score != nil || product.novaGroup != nil {
            HStack(spacing: Tide.s1) {
                if let score {
                    badge(
                        "Nutri-Score \(score.nutriScoreGrade.uppercased())\(score.nutriScoreEstimated ? "*" : "")",
                        color: FoodProductView.gradeColor(score.nutriScoreGrade)
                    )
                    .explains(.fuelNutriScore.showing(score.nutriScoreGrade.uppercased()))
                }
                if let nova = product.novaGroup {
                    badge("NOVA \(nova)", color: nova >= 4 ? Tide.Kitchen.warn : (nova == 3 ? Tide.Kitchen.warn : Tide.Kitchen.good))
                        .explains(.fuelNova.showing("Group \(nova)"))
                }
            }
            .padding(.top, Tide.hair)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        KitchenTag(text: text, tint: color)
            .fixedSize()
    }

    // MARK: - Basis

    private var basisPicker: some View {
        Picker("Show", selection: $basis) {
            Text("Per 100 \(product.unit)").tag(LabelFacts.Basis.per100)
            Text("Per serving").tag(LabelFacts.Basis.perServing)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("labelBasis")
    }

    // MARK: - Calories + macros

    private var caloriesCard: some View {
        let split = FoodMacroSplit.compute(proteinGrams: shown.protein, carbsGrams: shown.carbs, fatGrams: shown.fat)
        return VStack(alignment: .leading, spacing: Tide.s3) {
            sectionTitle("Nutrition · \(basisLabel)")
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: "flame.fill")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.Kitchen.warn)
                    .accessibilityHidden(true)
                TideNumber(
                    FoodProductView.amount(shown.kcal, unit: "kcal"),
                    unit: "kcal",
                    size: Tide.numeralL,
                    relativeTo: .largeTitle
                )
                .contentTransition(.numericText())
            }
            if let split {
                splitBar(split)
                HStack(spacing: Tide.s2) {
                    macroTile("Protein", "dumbbell.fill", shown.protein, Tide.protein)
                    macroTile("Carbs", "bolt.fill", shown.carbs, Tide.carbs)
                    macroTile("Fat", "drop.fill", shown.fat, Tide.fat)
                }
            }
            HStack(spacing: Tide.s4) {
                detail("Sugars", "cube.fill", shown.sugars)
                detail("Fiber", "leaf.fill", shown.fiber)
                detail("Salt", "circle.dotted", shown.salt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .animation(Tide.snap, value: basis)
    }

    private func splitBar(_ split: FoodMacroSplit) -> some View {
        GeometryReader { proxy in
            HStack(spacing: Tide.hair) {
                ForEach(split.slices) { slice in
                    Capsule()
                        .fill(slice.color)
                        .frame(width: max(4, (proxy.size.width - 4) * slice.percent))
                }
            }
        }
        .frame(height: Tide.Kitchen.ringStroke)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.slices.map { "\($0.label) \(Int(($0.percent * 100).rounded())) percent of calories" }.joined(separator: ", "))
    }

    private func macroTile(_ name: String, _ icon: String, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: Tide.hair) {
            Image(systemName: icon)
                .font(Tide.bodyStrong)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(FoodProductView.amount(value, unit: "g"))
                .font(Tide.numeral(Tide.numeralS))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(name)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s3)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func detail(_ name: String, _ icon: String, _ value: Double?) -> some View {
        HStack(spacing: Tide.hair) {
            Image(systemName: icon)
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            Text("\(name) \(FoodProductView.amount(value, unit: "g"))")
                .font(Tide.caption)
                .monospacedDigit()
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
        }
    }

    // MARK: - Traffic lights

    private var levelsCard: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            sectionTitle("Traffic lights · \(basisLabel)")
            levelRow("Fat", "drop.fill", .fat, shown.fat)
            levelRow("Saturates", "drop.halffull", .saturatedFat, shown.saturatedFat)
            levelRow("Sugars", "cube.fill", .sugars, shown.sugars)
            levelRow("Salt", "circle.dotted", .salt, shown.salt)
            Text("Colours follow the UK traffic-light thresholds per 100 \(product.unit), whatever the view above.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .explains(.fuelTrafficLights)
    }

    private func levelRow(_ name: String, _ icon: String, _ nutrient: LabelFacts.Nutrient, _ value: Double?) -> some View {
        let level = LabelFacts.level(of: nutrient, in: product)
        let color = Self.color(for: level)
        return HStack(spacing: Tide.s2) {
            Image(systemName: icon)
                .font(Tide.body)
                .foregroundStyle(color)
                .frame(width: glyph)
                .accessibilityHidden(true)
            Text(name)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
            Spacer(minLength: Tide.s2)
            Text(FoodProductView.amount(value, unit: "g"))
                .font(Tide.numeral(Tide.numeralS))
                .monospacedDigit()
                .foregroundStyle(Tide.text)
            VStack(alignment: .trailing, spacing: Tide.hair) {
                KitchenLevelMeter(filled: Self.pips(for: level), tint: color)
                Text(level?.label ?? "n/a")
                    .font(Tide.label)
                    .foregroundStyle(color)
            }
            .frame(width: levelWidth, alignment: .trailing)
        }
        .frame(minHeight: Tide.Kitchen.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(FoodProductView.amount(value, unit: "g")), \(level?.label ?? "unknown") level")
    }

    private static func pips(for level: LabelFacts.Level?) -> Int {
        switch level {
        case .low: 1
        case .medium: 2
        case .high: 3
        case nil: 0
        }
    }

    private static func color(for level: LabelFacts.Level?) -> Color {
        switch level {
        case .low: Tide.Kitchen.good
        case .medium: Tide.Kitchen.warn
        case .high: Tide.danger
        case nil: Tide.text3
        }
    }

    // MARK: - Fits your plan

    @ViewBuilder
    private var fitCard: some View {
        let density = FoodFit.proteinPer100Kcal(product)
        // The protein-density line below already says it; drop the duplicate.
        let checks = FoodFit.checks(for: product, grams: grams, context: fitContext)
            .filter { !$0.text.hasPrefix("High protein") && !$0.text.hasPrefix("Low protein") }
        if !checks.isEmpty || density != nil {
            VStack(alignment: .leading, spacing: Tide.s2) {
                sectionTitle("Fits your plan? · \(FoodProductView.format(grams)) \(product.unit)")
                if let density {
                    HStack(spacing: Tide.s2) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(Tide.protein)
                            .frame(width: glyph)
                            .accessibilityHidden(true)
                        Text("\(FoodProductView.format((density * 10).rounded() / 10)) g protein per 100 kcal")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                    }
                }
                ForEach(checks.prefix(4)) { check in
                    HStack(alignment: .top, spacing: Tide.s2) {
                        Image(systemName: check.kind.icon)
                            .foregroundStyle(check.kind.color)
                            .frame(width: glyph)
                            .accessibilityHidden(true)
                        Text(check.text)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
            .explains(.fuelForYou)
            .accessibilityIdentifier("labelFitCard")
        }
    }

    // MARK: - Ingredients

    @ViewBuilder
    private var ingredientsCard: some View {
        let allergens = product.displayAllergens
        let traces = product.displayTraces
        let text = product.ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !allergens.isEmpty || !traces.isEmpty || !text.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s2) {
                if !allergens.isEmpty {
                    sectionTitle("Allergens")
                    FlowChips(items: allergens.map { name in
                        let flagged = LabelFacts.isFlagged(displayAllergen: name, context: fitContext)
                        return (flagged ? "\(name) · your allergy" : name, flagged ? Tide.danger : Tide.Kitchen.warn, flagged)
                    })
                }
                if !traces.isEmpty {
                    sectionTitle("May contain")
                        .padding(.top, allergens.isEmpty ? 0 : Tide.s1)
                    FlowChips(items: traces.map { name in
                        let flagged = LabelFacts.isFlagged(displayAllergen: name, context: fitContext)
                        return (flagged ? "\(name) · your allergy" : name, flagged ? Tide.danger : Tide.text2, flagged)
                    })
                }
                if !text.isEmpty {
                    DisclosureGroup(isExpanded: $showIngredients) {
                        Text(highlighted(text))
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Tide.s1)
                    } label: {
                        Label("Ingredients", systemImage: "list.bullet")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                    }
                    .tint(Tide.text2)
                    .padding(.top, allergens.isEmpty && traces.isEmpty ? 0 : Tide.s1)
                    .accessibilityIdentifier("labelIngredients")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard()
        }
    }

    /// Ingredient text with the words behind the user's flagged allergens in
    /// bold red ("milk", "wheat"…), so the allergy is findable in the list.
    private func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let flaggedTags = product.allergens.filter { tag in
            Self.displayName(forTag: tag).map { LabelFacts.isFlagged(displayAllergen: $0, context: fitContext) } ?? false
        }
        let words = Set(flaggedTags.map { $0.replacingOccurrences(of: "-", with: " ") }).filter { $0.count >= 3 }
        for word in words {
            var searchStart = out.startIndex
            while let range = out[searchStart...].range(of: word, options: .caseInsensitive) {
                out[range].foregroundColor = Tide.danger
                out[range].font = .body.bold()
                searchStart = range.upperBound
            }
        }
        return out
    }

    /// Maps one raw allergen tag to its display name through a one-tag product,
    /// reusing the same EU-14 keyword table as the chips.
    private static func displayName(forTag tag: String) -> String? {
        var probe = FoodProduct(id: "probe", name: "", source: .userAdded, per100g: .init())
        probe.allergens = [tag]
        return probe.displayAllergens.first
    }

    // MARK: - Missing + warnings + actions

    /// No label for this product: not a card but a hero on the field, with the
    /// one way forward as the full-width bar button right under it.
    private var missingCard: some View {
        VStack(spacing: Tide.s5) {
            KitchenStateHero(
                systemImage: "doc.text.magnifyingglass",
                tint: Tide.Kitchen.warn,
                title: "No label data yet",
                message: "We don't have the nutrition table for this product. Photograph its label and Tempo reads it for you."
            )
            Button {
                showEditor = true
            } label: {
                Label("Photograph the label", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kitchenBar)
            .accessibilityIdentifier("labelPhotograph")
        }
        .frame(maxWidth: Tide.stateWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s6)
    }

    private func warning(_ text: String) -> some View {
        KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: text, tint: Tide.Kitchen.warn)
    }

    private var secondaryActions: some View {
        VStack(spacing: Tide.hair) {
            if hasLabel {
                Button {
                    showEditor = true
                } label: {
                    Label("Label looks wrong? Photograph it", systemImage: "camera.viewfinder")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                }
                .accessibilityIdentifier("labelPhotograph")
            }
            Button(action: onScanAnother) {
                Label("Scan another", systemImage: "barcode.viewfinder")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
            }
            .accessibilityIdentifier("labelScanAnother")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .tideLabel()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - FlowChips

/// Wrapping row of capsule chips (allergens).
private struct FlowChips: View {
    let items: [(text: String, color: Color, strong: Bool)]

    var body: some View {
        WrapLayout(spacing: Tide.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: Tide.s1) {
                    if item.strong {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Tide.label)
                    }
                    Text(item.text)
                }
                .font(Tide.caption.weight(.semibold))
                .foregroundStyle(item.color)
                .padding(.horizontal, Tide.s3)
                .padding(.vertical, Tide.s1)
                .background(item.color.opacity(0.15))
                .clipShape(Capsule())
                .overlay { item.strong ? Capsule().stroke(item.color, lineWidth: 1) : nil }
            }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
