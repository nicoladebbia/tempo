//
// FoodSuggestions.swift
// Tempo
//
// What the product screen shows under "suggestions": healthier swaps when
// something better exists, otherwise equally good picks from the same shelf.
// Works for every source — packaged (Open Food Facts), USDA and built-in
// foods — and never comes back empty when a peer exists anywhere (Open Food
// Facts, or Tempo's built-in table as an offline-safe fallback).
//

import Foundation

// MARK: - FoodSuggestions

struct FoodSuggestions: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Items that score higher than the product.
        case healthier
        /// The product is already great — peers of similar quality.
        case similar
    }

    var kind: Kind
    var items: [FoodProduct]

    static let empty = FoodSuggestions(kind: .similar, items: [])
}

// MARK: - FoodGroup

/// Broad shelf a food belongs to — drives placeholder art and suggestion fallbacks.
enum FoodGroup: String, CaseIterable, Sendable {
    case dairy
    case meat
    case fish
    case eggs
    case grains
    case bread
    case pasta
    case legumes
    case nuts
    case fruit
    case vegetables
    case snacks
    case sweets
    case drinks
    case oils
    case sauces
    case meals
    case other

    /// A representative search term used to find peers when nothing else
    /// (categories, name) turns up a result — e.g. a built-in "chicken
    /// thigh" with no Open Food Facts categories falls back to "chicken breast".
    var searchKeyword: String {
        switch self {
        case .dairy: "yogurt"
        case .meat: "chicken breast"
        case .fish: "salmon"
        case .eggs: "eggs"
        case .grains: "rice"
        case .bread: "bread"
        case .pasta: "pasta"
        case .legumes: "lentils"
        case .nuts: "almonds"
        case .fruit: "apple"
        case .vegetables: "broccoli"
        case .snacks: "crackers"
        case .sweets: "chocolate"
        case .drinks: "water"
        case .oils: "olive oil"
        case .sauces: "tomato sauce"
        case .meals: "salad"
        case .other: "food"
        }
    }
}

// MARK: - FoodProduct.foodGroup

extension FoodProduct {
    /// Shelf this food belongs to — from Open Food Facts categories first,
    /// then keyword-matched from the name (covers USDA and Tempo's built-in
    /// table, which carry no categories at all).
    var foodGroup: FoodGroup {
        if let fromCategories = Self.foodGroup(fromCategoryTags: categories) {
            return fromCategories
        }
        return Self.foodGroup(fromName: name) ?? .other
    }

    /// Composed dishes are checked first (a "cheeseburger" shouldn't land in
    /// dairy because of "cheese"), then ingredient groups from most to least
    /// specific, ending with the broadest catch-alls.
    private static let nameGroups: [(keywords: [String], group: FoodGroup)] = [
        ([
            "pizza",
            "burger",
            "sandwich",
            "burrito",
            "taco",
            "lasagna",
            "carbonara",
            "bolognese",
            "risotto",
            "hot dog",
            "sushi roll",
            "nuggets",
            "meal replacement",
            "tortilla wrap",
        ], .meals),
        ([
            "chocolate",
            "candy",
            "cake",
            "cookie",
            "brownie",
            "donut",
            "gelato",
            "ice cream",
            "frozen yogurt",
            "tiramisu",
            "cannoli",
            "biscotti",
            "cheesecake",
            "panna cotta",
            "sugar",
            "honey",
            "agave",
            "maple syrup",
        ], .sweets),
        ([
            "coffee",
            "espresso",
            "matcha",
            "green tea",
            "tea",
            "juice",
            "soda water",
            "soda",
            "cola",
            "coke",
            "sprite",
            "beer",
            "wine",
            "champagne",
            "prosecco",
            "vodka",
            "whiskey",
            "lemonade",
            "sports drink",
            "energy drink",
            "almond milk",
            "coconut milk",
            "oat milk",
            "soy milk",
            "kombucha",
            "smoothie",
            "protein shake",
        ], .drinks),
        (["olive oil", "coconut oil", "canola oil", "sesame oil", "sunflower oil", "vegetable oil", "evoo"], .oils),
        ([
            "ketchup",
            "mayonnaise",
            "mustard",
            "bbq sauce",
            "hot sauce",
            "salsa",
            "pesto",
            "marinara",
            "tomato sauce",
            "tomato paste",
            "vinaigrette",
            "dressing",
            "soy sauce",
            "sriracha",
            "tahini",
            "hummus",
            "guacamole",
            "gravy",
            "vinegar",
        ], .sauces),
        ([
            "peanut butter",
            "almond butter",
            "cashew butter",
            "almonds",
            "peanuts",
            "cashews",
            "walnuts",
            "pecans",
            "pistachios",
            "hazelnuts",
            "macadamia",
            "brazil nuts",
            "pine nuts",
            "chia seeds",
            "flax seeds",
            "hemp seeds",
            "pumpkin seeds",
            "sunflower seeds",
            "sesame seeds",
            "almond flour",
        ], .nuts),
        ([
            "lentils",
            "chickpeas",
            "edamame",
            "split peas",
            "snap peas",
            "snow peas",
            "beans",
            "tofu",
            "tempeh",
            "seitan",
            "peas",
        ], .legumes),
        (["egg"], .eggs),
        ([
            "salmon",
            "tuna",
            "cod",
            "shrimp",
            "crab",
            "lobster",
            "scallops",
            "clams",
            "mussels",
            "squid",
            "calamari",
            "octopus",
            "anchovies",
            "sardines",
            "mackerel",
            "halibut",
            "branzino",
            "sea bass",
            "sea bream",
            "swordfish",
            "trout",
        ], .fish),
        ([
            "chicken",
            "beef",
            "pork",
            "turkey",
            "lamb",
            "veal",
            "bacon",
            "ham",
            "prosciutto",
            "salami",
            "sausage",
            "mortadella",
            "pancetta",
            "bresaola",
            "soppressata",
            "duck",
            "burger patty",
        ], .meat),
        ([
            "bread",
            "bagel",
            "baguette",
            "ciabatta",
            "focaccia",
            "naan",
            "pita",
            "tortilla",
            "english muffin",
            "croissant",
            "breadcrumbs",
            "panko",
            "sourdough",
        ], .bread),
        ([
            "pasta",
            "spaghetti",
            "fettuccine",
            "linguine",
            "penne",
            "rigatoni",
            "fusilli",
            "orzo",
            "tagliatelle",
            "gnocchi",
            "ravioli",
            "tortellini",
            "couscous",
            "polenta",
        ], .pasta),
        ([
            "rice",
            "oats",
            "oat",
            "quinoa",
            "barley",
            "farro",
            "bulgur",
            "millet",
            "buckwheat",
            "cornmeal",
            "granola",
            "flour",
        ], .grains),
        ([
            "broccoli",
            "spinach",
            "carrot",
            "potato",
            "tomato",
            "onion",
            "garlic",
            "pepper",
            "cucumber",
            "lettuce",
            "kale",
            "cabbage",
            "cauliflower",
            "zucchini",
            "eggplant",
            "mushroom",
            "asparagus",
            "celery",
            "beet",
            "squash",
            "pumpkin",
            "artichoke",
            "radish",
            "turnip",
            "parsnip",
            "leek",
            "fennel",
            "arugula",
            "chard",
            "collard",
            "endive",
            "iceberg",
            "radicchio",
            "romaine",
            "scallion",
            "shallot",
            "corn",
        ], .vegetables),
        ([
            "apple",
            "banana",
            "orange",
            "grape",
            "strawberr",
            "blueberr",
            "raspberr",
            "blackberr",
            "mango",
            "pineapple",
            "watermelon",
            "cantaloupe",
            "honeydew",
            "kiwi",
            "lemon",
            "lime",
            "peach",
            "pear",
            "plum",
            "cherry",
            "apricot",
            "fig",
            "date",
            "pomegranate",
            "clementine",
            "mandarin",
            "grapefruit",
            "nectarine",
            "papaya",
            "prune",
            "raisin",
        ], .fruit),
        ([
            "chips",
            "crisps",
            "pretzels",
            "popcorn",
            "crackers",
            "saltines",
            "energy bar",
            "protein bar",
            "french fries",
        ], .snacks),
        ([
            "yogurt",
            "yoghurt",
            "cheese",
            "milk",
            "cream",
            "kefir",
            "skyr",
            "half and half",
            "ghee",
            "butter",
        ], .dairy),
    ]

    private static let categoryGroups: [(keywords: [String], group: FoodGroup)] = [
        (["pizzas", "sandwiches", "meals", "prepared-meals", "burgers"], .meals),
        ([
            "chocolates",
            "candies",
            "confectioneries",
            "biscuits",
            "cakes",
            "desserts",
            "pastries",
            "ice-creams",
            "sweet-snacks",
            "sweet-spreads",
        ], .sweets),
        ([
            "waters",
            "coffees",
            "teas",
            "hot-beverages",
            "alcoholic-beverages",
            "wines",
            "beers",
            "sodas",
            "carbonated-drinks",
            "juices",
            "fruit-juices",
            "beverages",
        ], .drinks),
        (["oils", "fats", "vegetable-oils"], .oils),
        (["sauces", "condiments", "dressings", "spreads"], .sauces),
        (["nuts", "seeds", "nut-butters", "peanut-butters"], .nuts),
        (["legumes", "beans", "lentils"], .legumes),
        (["eggs"], .eggs),
        (["fishes", "seafood"], .fish),
        (["meats", "sausages", "hams", "poultries"], .meat),
        (["breads"], .bread),
        (["pastas"], .pasta),
        (["cereals-and-potatoes", "cereals-and-their-products", "breakfast-cereals", "rices"], .grains),
        (["vegetables", "fruits-and-vegetables-based-foods"], .vegetables),
        (["fruits"], .fruit),
        (["salty-snacks", "crisps", "chips-and-fries", "popcorn"], .snacks),
        (["dairies", "cheeses", "yogurts", "milks", "skyrs"], .dairy),
    ]

    private static func foodGroup(fromCategoryTags tags: [String]) -> FoodGroup? {
        // Most specific category last — try it first.
        for tag in tags.reversed() {
            for entry in categoryGroups where entry.keywords.contains(where: { tag == $0 || tag.contains($0) }) {
                return entry.group
            }
        }
        return nil
    }

    static func foodGroup(fromName name: String) -> FoodGroup? {
        let lowered = name.lowercased()
        for entry in nameGroups where entry.keywords.contains(where: { lowered.contains($0) }) {
            return entry.group
        }
        return nil
    }
}

// MARK: - FoodProduct.displayAllergens

extension FoodProduct {
    /// Allergens as people read them ("Milk", "Gluten"), limited to the
    /// EU-14 / US-major allergens, de-duplicated, stable order. Handles junk
    /// tags Open Food Facts sometimes carries ("cultured-nonfat-milk") by
    /// keyword-matching rather than requiring an exact taxonomy tag.
    var displayAllergens: [String] {
        let matched = Set(allergens.compactMap(Self.displayAllergenName(for:)))
        return Self.allergenDisplayOrder.filter { matched.contains($0) }
    }

    /// "May contain" traces, same EU-14/US-major mapping as `displayAllergens`
    /// — shown as secondary chips, and excludes anything already a confirmed
    /// allergen (no point flagging both "contains milk" and "may contain milk").
    var displayTraces: [String] {
        let confirmed = Set(displayAllergens)
        let matched = Set((traces ?? []).compactMap(Self.displayAllergenName(for:)))
        return Self.allergenDisplayOrder.filter { matched.contains($0) && !confirmed.contains($0) }
    }

    private static let allergenDisplayOrder = [
        "Milk", "Eggs", "Fish", "Crustaceans", "Molluscs", "Tree nuts", "Peanuts",
        "Gluten", "Soy", "Sesame", "Celery", "Mustard", "Lupin", "Sulphites",
    ]

    /// Peanuts and tree nuts are checked before the generic dairy words so a
    /// junk tag like "peanut-butter" doesn't get swallowed by "nuts"/"butter".
    private static let allergenKeywordGroups: [(keywords: [String], name: String)] = [
        (["peanut", "groundnut", "arachide"], "Peanuts"),
        ([
            "almond",
            "hazelnut",
            "walnut",
            "cashew",
            "pecan",
            "pistachio",
            "macadamia",
            "brazil-nut",
            "brazilnut",
            "pine-nut",
            "pinenut",
            "chestnut",
            "tree-nut",
            "treenut",
            "nuts",
        ], "Tree nuts"),
        (["milk", "lactose", "casein", "whey"], "Milk"),
        (["egg"], "Eggs"),
        (["crustacean", "shrimp", "prawn", "crab", "lobster"], "Crustaceans"),
        (["mollusc", "mollusk", "squid", "octopus", "mussel", "oyster", "clam", "snail"], "Molluscs"),
        (["fish"], "Fish"),
        (["gluten", "wheat", "barley", "rye", "spelt", "kamut"], "Gluten"),
        (["soy", "soya"], "Soy"),
        (["sesame"], "Sesame"),
        (["celery", "celeriac"], "Celery"),
        (["mustard"], "Mustard"),
        (["lupin"], "Lupin"),
        (["sulphite", "sulfite", "sulphur-dioxide", "sulfur-dioxide"], "Sulphites"),
    ]

    /// nil when the tag matches none of the EU-14 / US-major allergens.
    static func displayAllergenName(for rawTag: String) -> String? {
        let tag = rawTag.split(separator: ":").last.map(String.init) ?? rawTag
        let normalized = tag.lowercased().replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else {
            return nil
        }
        for entry in allergenKeywordGroups where entry.keywords.contains(where: { normalized.contains($0) }) {
            return entry.name
        }
        return nil
    }
}

// MARK: - FoodCatalog.suggestions

extension FoodCatalog {
    /// Always-there suggestions for any product. Empty only when nothing at
    /// all could be found (offline and no built-in peers of the same shelf).
    func suggestions(for product: FoodProduct, limit: Int = 6) async -> FoodSuggestions {
        if let cached = suggestionsCache[product.id] {
            return cached
        }
        let result = await computeSuggestions(for: product, limit: limit)
        suggestionsCache[product.id] = result
        return result
    }

    private func computeSuggestions(for product: FoodProduct, limit: Int) async -> FoodSuggestions {
        let currentTotal = FoodScore.evaluate(product)?.total

        var candidates: [FoodProduct] = []
        do {
            candidates = try await products.peers(for: product, limit: limit + 14)
        } catch {
            logger.warning("[food] suggestions peers failed: \(String(describing: error), privacy: .public)")
        }
        if candidates.isEmpty {
            candidates = await (try? products.search(product.foodGroup.searchKeyword, limit: limit + 14)) ?? []
        }

        if !candidates.isEmpty {
            let ranked = Self.rank(candidates: candidates, excluding: product, currentTotal: currentTotal, limit: limit)
            if !ranked.items.isEmpty {
                return ranked
            }
        }
        return builtInFallback(for: product, currentTotal: currentTotal, limit: limit)
    }

    /// Peers from Tempo's own table, same shelf, scored the same way — works
    /// fully offline and whenever Open Food Facts has nothing to offer.
    private func builtInFallback(for product: FoodProduct, currentTotal: Int?, limit: Int) -> FoodSuggestions {
        let group = product.foodGroup
        let excludedName = product.name.lowercased()
        let peers = FoodMacroDatabase.macrosPer100g
            .filter { $0.key != excludedName }
            .map { FoodCatalog.builtInProduct(name: $0.key, macros: $0.value) }
            .filter { $0.foodGroup == group }
        guard !peers.isEmpty else {
            return .empty
        }
        return Self.rank(candidates: peers, excluding: product, currentTotal: currentTotal, limit: limit)
    }

    /// Scores every candidate, drops the product itself and duplicates
    /// (same barcode, same name+brand, or a near-identical name — "Coca-Cola
    /// by Coke" showing up as a swap for "Coca-Cola" is the same product, not
    /// a suggestion), then requires a *meaningful* improvement to call
    /// something "healthier" (see `isMeaningfulImprovement`); failing that,
    /// peers within 5 points or the same rating tier; failing that, whatever
    /// scored at all. Items with a photo sort first within each tier.
    private static func rank(candidates: [FoodProduct], excluding product: FoodProduct, currentTotal: Int?, limit: Int) -> FoodSuggestions {
        struct Scored {
            let product: FoodProduct
            let total: Int
            let rating: FoodScore.Rating
        }
        // Seeded with the product's own name+brand so a peer that's really
        // just the same product under a different id/barcode is excluded too.
        var seenKey = Set<String>(["\(product.name.lowercased())|\(product.brand?.lowercased() ?? "")"])
        let productTokens = nameTokens(product)
        let scored: [Scored] = candidates.compactMap { candidate in
            guard candidate.id != product.id, !candidate.name.isEmpty else {
                return nil
            }
            if let barcode = product.barcode, let candidateBarcode = candidate.barcode, candidateBarcode == barcode {
                return nil
            }
            let key = "\(candidate.name.lowercased())|\(candidate.brand?.lowercased() ?? "")"
            guard seenKey.insert(key).inserted else {
                return nil
            }
            // Same product, different listing ("Coca-Cola" vs "Coca-Cola by
            // Coke"): near-identical normalized name, regardless of brand.
            guard jaccard(nameTokens(candidate), productTokens) < 0.8 else {
                return nil
            }
            guard let score = FoodScore.evaluate(candidate) else {
                return nil
            }
            return Scored(product: candidate, total: score.total, rating: score.rating)
        }
        guard !scored.isEmpty else {
            return .empty
        }

        func take(_ items: [Scored]) -> [FoodProduct] {
            items
                .sorted { lhs, rhs in
                    let lhsHasPhoto = lhs.product.imageURL != nil
                    let rhsHasPhoto = rhs.product.imageURL != nil
                    return lhsHasPhoto != rhsHasPhoto ? lhsHasPhoto : lhs.total > rhs.total
                }
                .prefix(limit)
                .map(\.product)
        }

        if let currentTotal {
            let currentRating = FoodScore.Rating(score: currentTotal)
            // Already excellent → a peer needs to clear a higher bar (+8, not
            // +5) before "Also great" gets upgraded to a real swap.
            let requiredGain = currentRating == .excellent ? 8 : 5
            let healthier = scored.filter { $0.total >= currentTotal + requiredGain }
            if !healthier.isEmpty {
                return FoodSuggestions(kind: .healthier, items: take(healthier))
            }
            let similar = scored.filter { $0.total >= currentTotal - 5 || $0.rating == currentRating }
            if !similar.isEmpty {
                return FoodSuggestions(kind: .similar, items: take(similar))
            }
        }
        return FoodSuggestions(kind: .similar, items: take(scored))
    }

    /// Lowercased alphanumeric word tokens from the product's *name* only
    /// (brand deliberately excluded — that's exactly what let "Coca-Cola by
    /// Coke" slip past the old name+brand key as a "swap" for "Coca-Cola":
    /// same name, different brand string). Catches a near-duplicate listing
    /// of the same product under a different id/barcode/brand.
    static func nameTokens(_ product: FoodProduct) -> Set<String> {
        let words = product.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(words.map(String.init).filter { $0.count > 1 }.map(singular))
    }

    /// "bananas" → "banana", "tomatoes" → "tomato", so a USDA "Bananas" isn't
    /// offered as a swap for the built-in "Banana".
    static func singular(_ word: String) -> String {
        guard word.count > 3 else {
            return word
        }
        for suffix in ["oes", "xes", "ches", "shes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss") {
            return String(word.dropLast())
        }
        return word
    }

    /// Intersection over union — 1.0 for identical token sets, 0 for no
    /// overlap at all.
    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else {
            return 0
        }
        let union = a.union(b).count
        guard union > 0 else {
            return 0
        }
        return Double(a.intersection(b).count) / Double(union)
    }
}
