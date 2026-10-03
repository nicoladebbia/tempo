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
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
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
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, TempoSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Color.tempoBgPrimary)
        .accessibilityIdentifier("scannedProductLabel")
        .safeAreaInset(edge: .bottom) {
            FoodProductActionBar(product: product, grams: grams, toast: $toast) {
                catalog.rememberPortion(grams, for: product, in: modelContext)
            }
        }
        .tempoToast($toast)
        .task(id: product.id) {
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
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            FoodRemoteImage(url: product.imageURL ?? product.imageSmallURL, product: product, contentMode: .fit)
                .frame(width: 96, height: 96)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text(product.name)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: TempoSpacing.xs) {
                    if let barcode = product.barcode {
                        Label(barcode, systemImage: "barcode")
                            .font(.tempoCaption1)
                            .monospacedDigit()
                            .foregroundStyle(Color.tempoTextTertiary)
                            .lineLimit(1)
                    }
                    if let quantity = product.quantityLabel {
                        Text("· \(quantity)")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .lineLimit(1)
                    }
                }
                gradeBadges
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var gradeBadges: some View {
        let score = FoodScore.evaluate(product)
        if score != nil || product.novaGroup != nil {
            HStack(spacing: TempoSpacing.xs) {
                if let score {
                    badge(
                        "Nutri-Score \(score.nutriScoreGrade.uppercased())\(score.nutriScoreEstimated ? "*" : "")",
                        color: FoodProductView.gradeColor(score.nutriScoreGrade)
                    )
                }
                if let nova = product.novaGroup {
                    badge("NOVA \(nova)", color: nova >= 4 ? .tempoAmber : (nova == 3 ? .tempoWarning : .tempoSuccess))
                }
            }
            .padding(.top, 2)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
            .lineLimit(1)
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
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionTitle("NUTRITION · \(basisLabel.uppercased())")
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.tempoAmber)
                    .accessibilityHidden(true)
                Text(FoodProductView.amount(shown.kcal, unit: "kcal"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextPrimary)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            if let split {
                splitBar(split)
                HStack(spacing: TempoSpacing.sm) {
                    macroTile("Protein", "dumbbell.fill", shown.protein, .tempoMacroProtein)
                    macroTile("Carbs", "bolt.fill", shown.carbs, .tempoMacroCarbs)
                    macroTile("Fat", "drop.fill", shown.fat, .tempoMacroFat)
                }
            }
            HStack(spacing: TempoSpacing.lg) {
                detail("Sugars", "cube.fill", shown.sugars)
                detail("Fiber", "leaf.fill", shown.fiber)
                detail("Salt", "circle.dotted", shown.salt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .animation(.snappy(duration: 0.25), value: basis)
    }

    private func splitBar(_ split: FoodMacroSplit) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(split.slices) { slice in
                    Capsule()
                        .fill(slice.color)
                        .frame(width: max(4, (proxy.size.width - 4) * slice.percent))
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.slices.map { "\($0.label) \(Int(($0.percent * 100).rounded())) percent of calories" }.joined(separator: ", "))
    }

    private func macroTile(_ name: String, _ icon: String, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(FoodProductView.amount(value, unit: "g"))
                .font(.tempoBodyBold)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(name)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(color.opacity(TempoOpacity.o15))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func detail(_ name: String, _ icon: String, _ value: Double?) -> some View {
        HStack(spacing: TempoSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.tempoTextTertiary)
                .accessibilityHidden(true)
            Text("\(name) \(FoodProductView.amount(value, unit: "g"))")
                .font(.tempoCaption1)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Traffic lights

    private var levelsCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionTitle("TRAFFIC LIGHTS · \(basisLabel.uppercased())")
            levelRow("Fat", "drop.fill", .fat, shown.fat)
            levelRow("Saturates", "drop.halffull", .saturatedFat, shown.saturatedFat)
            levelRow("Sugars", "cube.fill", .sugars, shown.sugars)
            levelRow("Salt", "circle.dotted", .salt, shown.salt)
            Text("Colours follow the UK traffic-light thresholds per 100 \(product.unit), whatever the view above.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private func levelRow(_ name: String, _ icon: String, _ nutrient: LabelFacts.Nutrient, _ value: Double?) -> some View {
        let level = LabelFacts.level(of: nutrient, in: product)
        let color = Self.color(for: level)
        return HStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(name)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer(minLength: TempoSpacing.sm)
            Text(FoodProductView.amount(value, unit: "g"))
                .font(.tempoBodyBold)
                .monospacedDigit()
                .foregroundStyle(Color.tempoTextPrimary)
            Text(level?.label ?? "n/a")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64)
                .padding(.vertical, 4)
                .background(color.opacity(TempoOpacity.o15))
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(FoodProductView.amount(value, unit: "g")), \(level?.label ?? "unknown") level")
    }

    private static func color(for level: LabelFacts.Level?) -> Color {
        switch level {
        case .low: .tempoSuccess
        case .medium: .tempoAmber
        case .high: .tempoError
        case nil: .tempoTextTertiary
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
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                sectionTitle("FITS YOUR PLAN? · \(FoodProductView.format(grams)) \(product.unit)")
                if let density {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(Color.tempoMacroProtein)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text("\(FoodProductView.format((density * 10).rounded() / 10)) g protein per 100 kcal")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }
                ForEach(checks.prefix(4)) { check in
                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Image(systemName: check.kind.icon)
                            .foregroundStyle(check.kind.color)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(check.text)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
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
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                if !allergens.isEmpty {
                    sectionTitle("ALLERGENS")
                    FlowChips(items: allergens.map { name in
                        let flagged = LabelFacts.isFlagged(displayAllergen: name, context: fitContext)
                        return (flagged ? "\(name) · your allergy" : name, flagged ? Color.tempoError : Color.tempoAmber, flagged)
                    })
                }
                if !traces.isEmpty {
                    sectionTitle("MAY CONTAIN")
                        .padding(.top, allergens.isEmpty ? 0 : TempoSpacing.xs)
                    FlowChips(items: traces.map { name in
                        let flagged = LabelFacts.isFlagged(displayAllergen: name, context: fitContext)
                        return (flagged ? "\(name) · your allergy" : name, flagged ? Color.tempoError : Color.tempoTextSecondary, flagged)
                    })
                }
                if !text.isEmpty {
                    DisclosureGroup(isExpanded: $showIngredients) {
                        Text(highlighted(text))
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, TempoSpacing.xs)
                    } label: {
                        Label("Ingredients", systemImage: "list.bullet")
                            .font(.tempoBodyBold)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .tint(Color.tempoTextSecondary)
                    .padding(.top, allergens.isEmpty && traces.isEmpty ? 0 : TempoSpacing.xs)
                    .accessibilityIdentifier("labelIngredients")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoCard()
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
                out[range].foregroundColor = Color.tempoError
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

    private var missingCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Label("No label data yet", systemImage: "doc.text.magnifyingglass")
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("We don't have the nutrition table for this product. Photograph its label and Tempo reads it for you.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Button("Photograph the label") { showEditor = true }
                .buttonStyle(.tempoPrimary)
                .padding(.top, TempoSpacing.xs)
                .accessibilityIdentifier("labelPhotograph")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tempoAmber)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoAmber.opacity(TempoOpacity.o15))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
    }

    private var secondaryActions: some View {
        VStack(spacing: TempoSpacing.xxs) {
            if hasLabel {
                Button {
                    showEditor = true
                } label: {
                    Label("Label looks wrong? Photograph it", systemImage: "camera.viewfinder")
                        .font(.tempoSubheadline.weight(.semibold))
                        .foregroundStyle(Color.tempoSignal)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("labelPhotograph")
            }
            Button(action: onScanAnother) {
                Label("Scan another", systemImage: "barcode.viewfinder")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("labelScanAnother")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoTextTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - FlowChips

/// Wrapping row of capsule chips (allergens).
private struct FlowChips: View {
    let items: [(text: String, color: Color, strong: Bool)]

    var body: some View {
        WrapLayout(spacing: TempoSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    if item.strong {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                    }
                    Text(item.text)
                }
                .font(.tempoCaption1.weight(.semibold))
                .foregroundStyle(item.color)
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.xs)
                .background(item.color.opacity(TempoOpacity.o15))
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
