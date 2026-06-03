//
// FoodCanonicalizer.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - FoodCanonicalizer

enum FoodCanonicalizer {
    // MARK: - Cooking descriptors

    /// Prefixes stripped from canonical form (only stripped from the start of the name).
    private static let cookingPrefixes: [String] = [
        "grilled", "baked", "roasted", "steamed", "boiled", "fried",
        "sauteed", "sautéed", "pan-fried", "air-fried", "braised",
        "smoked", "poached", "broiled", "blanched", "raw", "fresh",
        "frozen", "dried", "canned", "marinated", "seasoned", "sliced",
        "diced", "chopped", "minced", "shredded", "mashed", "whole",
        "organic", "natural", "homemade", "store-bought", "cooked",
        "uncooked", "prepped", "prepared",
    ]

    /// Suffixes stripped from canonical form.
    private static let cookingSuffixes: [String] = [
        "cooked", "raw", "grilled", "baked", "roasted", "steamed",
        "frozen", "dried", "canned", "fresh", "sliced", "diced",
        "chopped", "shredded", "prepped", "prepared",
    ]

    /// Single-word brand tokens and qualifiers that appear in receipts.
    /// NOTE: `salt` was previously included but removed — it's a real
    /// ingredient (and a staple in `FoodMacroDatabase.naturalPortions`).
    /// `unsalted` / `salted` are kept as descriptors (e.g. "salted butter"
    /// → "butter").
    private static let brandWords: Set<String> = [
        "publix", "kroger", "walmart", "trader", "joes", "kirkland",
        "vigo", "laytons", "layton", "great", "value", "market", "pantry",
        "bnls", "boneless", "skinless", "bnls/skls", "usda",
        "atlantic", "pacific", "premium", "select", "choice",
        "qt", "qk", "lt", "oz",
        "lightly", "unsalted", "salted", "plain",
        "dry", "uncooked", "natural",
    ]

    /// Multi-word brand patterns stripped after single-word filtering.
    private static let multiWordBrands: [String] = [
        "great value", "trader joes", "whole foods",
        "lightly salted", "market pantry",
    ]

    /// Per-token OCR shorthand → English. Applied BEFORE alias lookup so
    /// shrunk receipt strings (`CHKN BRST 1.32LB`) resolve through the
    /// regular pipeline. Keys are lowercase ASCII; the substitution is
    /// whole-token (split-on-space then replace), so we don't accidentally
    /// inflate `chkns` into `chickenns`.
    private static let ocrAbbreviations: [String: String] = [
        "chkn": "chicken",
        "chk": "chicken",
        "brst": "breast",
        "bf": "beef",
        "bns": "beans",
        "blk": "black",
        "wht": "white",
        "wh": "whole",
        "yog": "yogurt",
        "ygrt": "yogurt",
        "mlk": "milk",
        "evo": "evoo",
        "olv": "olive",
        "tom": "tomato",
        "veg": "vegetable",
        "pwdr": "powder",
        "swt": "sweet",
        "pot": "potato",
        "strawb": "strawberries",
        "blueb": "blueberries",
        "rasp": "raspberries",
        "bnna": "banana",
        "fzt": "frozen",
        "frz": "frozen",
        "pk": "pack",
        "pkg": "package",
        "vit": "vitamin",
    ]

    /// Multi-word packing-medium phrases stripped early (e.g. `tuna in
    /// olive oil` → `tuna`). Kept distinct from cooking prefix/suffix
    /// because they can appear ANYWHERE in the string.
    private static let packingMediumPhrases: [String] = [
        " in olive oil", " in oil", " in water", " in syrup",
        " in brine", " packed in oil", " packed in water",
        ", drained", " drained",
    ]

    /// Words stripped only for display formatting — keep cooking methods (grilled/baked/etc).
    private static let displayStrip: Set<String> = [
        "cooked", "raw", "frozen", "canned", "dried", "fresh",
        "prepped", "prepared", "uncooked", "organic", "natural",
        "homemade", "store-bought", "whole",
    ]

    // MARK: - Canonical alias map

    /// Variant → canonical. Keys must be lowercase, ASCII apostrophes only.
    /// Ported verbatim from NutriTrack food_matcher.py _CANONICAL.
    private static let canonicalMap: [String: String] = [
        // Proteins
        "chicken": "chicken breast",
        "grilled chicken": "chicken breast",
        "chicken breast fillet": "chicken breast",
        "chicken breast filet": "chicken breast",
        "small chicken breast": "chicken breast",
        "large chicken breast": "chicken breast",
        "boneless chicken breast": "chicken breast",
        "skinless chicken breast": "chicken breast",
        "chicken cutlet": "chicken breast",
        "chicken breast with rib meat": "chicken breast",
        "breast with rib meat": "chicken breast",
        "bnls breast": "chicken breast",
        "breast": "chicken breast",
        "atlantic salmon": "salmon",
        "atlantic salmon fillet": "salmon",
        "atlantic salmon fillets": "salmon",
        "salmon fillet": "salmon",
        "salmon fillets": "salmon",
        "salmone": "salmon",
        "turkey": "ground turkey",
        "turkey breast deli": "turkey breast",
        "ground beef": "ground beef",
        "lean ground beef": "ground beef",
        "beef mince": "ground beef",
        "minced beef": "ground beef",
        "whey protein": "protein powder",
        "whey isolate": "protein powder",
        "protein shake": "protein powder",
        "casein": "protein powder",
        "casein protein": "protein powder",
        "protein scoop": "protein powder",
        "scoop of protein": "protein powder",
        "petto di pollo": "chicken breast",
        "pollo": "chicken breast",
        "proteine in polvere": "protein powder",
        // Grains & carbs
        "white rice": "rice",
        "brown rice": "rice",
        "jasmine rice": "rice",
        "basmati rice": "rice",
        "oatmeal": "oats",
        "rolled oats": "oats",
        "porridge oats": "oats",
        "overnight oats": "oats",
        "fiocchi d'avena": "oats",
        "sweet potatoes": "sweet potato",
        "patata dolce": "sweet potato",
        "patate dolci": "sweet potato",
        "rice cake": "rice cakes",
        "r/cake": "rice cakes",
        "r/cakes": "rice cakes",
        "rice cakes lightly salted": "rice cakes",
        "gallette di riso": "rice cakes",
        "pre-made rice": "rice",
        "prepared rice": "rice",
        "cooked rice": "rice",
        "jasmine rice dry": "rice",
        // Dairy
        "greek yoghurt": "greek yogurt",
        "yoghurt": "greek yogurt",
        "yogurt greco": "greek yogurt",
        "plain yogurt": "greek yogurt",
        "natural yogurt": "greek yogurt",
        // Berries & fruits
        "blueberries": "berries",
        "blueberry": "berries",
        "frozen blueberries": "berries",
        "frozen berries": "berries",
        "mixed berries": "berries",
        "frozen mixed berries": "berries",
        "strawberries": "strawberries",
        "raspberries": "raspberries",
        "bananas": "banana",
        "kiwi fruit": "kiwi",
        "kiwis": "kiwi",
        "avocados": "avocado",
        "oranges": "orange",
        "lemons": "lemon",
        "mirtilli": "berries",
        // Nuts & seeds
        "almond": "almonds",
        "walnut": "walnuts",
        "pumpkin seed": "pumpkin seeds",
        // Greens & vegetables
        "baby spinach": "spinach",
        "fresh spinach": "spinach",
        "mixed greens": "spinach",
        "spinaci": "spinach",
        "asparagus spears": "asparagus",
        "broccoli florets": "broccoli",
        "bell peppers": "bell pepper",
        "red bell pepper": "bell pepper",
        "green bell pepper": "bell pepper",
        "peperoni": "bell pepper",
        // Oils & fats
        "extra virgin olive oil": "olive oil",
        "evoo": "olive oil",
        "olio d'oliva": "olive oil",
        // OCR abbreviation expansion runs FIRST and rewrites the "evo" token
        // to "evoo" ("olio evo" → "olio evoo"), so the alias must key on the
        // post-expansion form or it can never match.
        "olio evoo": "olive oil",
        // Milk alternatives
        "oat milk": "oat milk",
        "latte d'avena": "oat milk",
        // Other
        "fresh ginger root": "ginger",
        "fresh ginger": "ginger",
        "ginger root": "ginger",
        "miele": "honey",
        "acqua di cocco": "coconut water",
        "coconut water": "coconut water",
        // Italian extras
        "aglio": "garlic clove",
        "cipolla": "onion",
        "cipolle": "onion",
        "prezzemolo": "fresh parsley",
        "pomodoro": "tomato",
        "pomodori": "tomato",
        "pomodorini": "cherry tomato",
        "carota": "carrot",
        "carote": "carrot",
        "uova": "eggs",
        "uovo": "eggs",
        "latte": "whole milk",
        "burro": "butter",
        "formaggio": "cheddar",
        "tonno": "tuna canned",
        "tonno in scatola": "tuna canned",
        "fagioli neri": "black beans canned",
        "ceci": "chickpeas canned",
        "lenticchie": "lentils dry",
        "basilico": "fresh basil",
        "limone": "lemon",
        "limoni": "lemon",
        "zucchine": "zucchini",
        "funghi": "mushrooms",
        "spinacio": "spinach",
        // English synonyms / variants
        "yoghurt greek": "greek yogurt",
        "cilantro": "fresh cilantro",
        "coriander leaves": "fresh cilantro",
        "spring onion": "scallion",
        "green onion": "scallion",
        "scallion": "scallion",
        "scallions": "scallion",
        "tomatoes": "tomato",
        "onions": "onion",
        "carrots": "carrot",
        "mushrooms": "mushrooms",
        "zucchinis": "zucchini",
        "cucumbers": "cucumber",
        "potatoes": "potato",
        "shallots": "shallot",
        "leeks": "leek",
        "jalapenos": "jalapeno",
        "jalapeño": "jalapeno",
        "jalapeños": "jalapeno",
        "mangos": "mango",
        "mangoes": "mango",
        "grilled chicken breast": "chicken breast",
        "pb": "peanut butter",
        "ab": "almond butter",
        "sea salt": "salt",
        "kosher salt": "salt",
        "table salt": "salt",
    ]

    // MARK: - Public API

    /// Normalize a food name to its canonical form.
    ///
    /// Steps:
    /// 1. Lowercase + trim
    /// 2. Strip noisy punctuation (periods, slashes-with-spaces, commas)
    /// 3. Expand OCR token abbreviations (chkn → chicken, brst → breast)
    /// 4. Strip packing-medium phrases (`in oil`, `in water`, `drained`)
    /// 5. Direct alias lookup (catches multi-word exact matches first)
    /// 6. Strip parenthetical notes
    /// 7. Strip cooking prefix (at most one)
    /// 8. Strip cooking suffix (at most one)
    /// 9. Strip brand tokens
    /// 10. Return the cleaned name (or alias-resolved canonical)
    ///
    /// Returns an empty string when the input is empty.
    static func canonicalize(_ raw: String) -> String {
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        // Pre-passes the original pipeline didn't have. Punctuation +
        // OCR expansion + packing-medium strip all turn ugly receipt
        // strings into something the alias map can match.
        let punctClean = stripNoisyPunctuation(trimmed)
        let ocrExpanded = expandOCRAbbreviations(punctClean)
        let packStripped = stripPackingMedium(ocrExpanded)

        if let direct = canonicalMap[packStripped] {
            return direct
        }

        var name = stripParentheticals(packStripped)
        if let aliased = canonicalMap[name] {
            return aliased
        }

        for prefix in cookingPrefixes {
            let token = prefix + " "
            if name.hasPrefix(token) {
                name = String(name.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        for suffix in cookingSuffixes {
            let token = " " + suffix
            if name.hasSuffix(token) {
                name = String(name.dropLast(token.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        if let aliased = canonicalMap[name] {
            return aliased
        }

        let stripped = stripBrands(name)
        if !stripped.isEmpty, stripped != name {
            if let aliased = canonicalMap[stripped] {
                return aliased
            }
            name = stripped
        }

        return name
    }

    /// Clean a food name for display — strip redundant state words, title-case the result.
    ///
    /// Unlike `canonicalize`, this preserves cooking methods ("grilled", "baked") because
    /// they carry meaning for recipe instructions.
    static func displayName(_ raw: String) -> String {
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var name = stripParentheticals(trimmed)

        for prefix in displayStrip {
            let token = prefix + " "
            if name.hasPrefix(token) {
                name = String(name.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        for suffix in displayStrip {
            let token = " " + suffix
            if name.hasSuffix(token) {
                name = String(name.dropLast(token.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return name.isEmpty
            ? raw.trimmingCharacters(in: .whitespaces).titleCased()
            : name.titleCased()
    }

    /// Returns true when two food names refer to the same canonical food.
    static func foodMatches(_ left: String, _ right: String) -> Bool {
        guard !left.isEmpty, !right.isEmpty else {
            return false
        }
        return canonicalize(left) == canonicalize(right)
    }

    // MARK: - Internal helpers

    /// Strip noisy punctuation that appears in receipt OCR strings —
    /// periods, slashes (when surrounded by letters they're typically
    /// abbreviation markers like `BNLS/SKLS`), commas, hyphens
    /// (so `ground-beef` matches `ground beef`). Apostrophes are kept
    /// for Italian / French aliases (`olio d'oliva`).
    private static func stripNoisyPunctuation(_ input: String) -> String {
        var result = input
        // Slashes between letters → space (BNLS/SKLS → bnls skls).
        result = result.replacingOccurrences(
            of: #"(?<=\w)/(?=\w)"#,
            with: " ",
            options: .regularExpression
        )
        // Periods are usually abbreviation dots; comma is a separator.
        // Hyphens between words flatten to spaces.
        result = result
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Expand OCR-shorthand tokens (`chkn` → `chicken`). Splits on
    /// whitespace, replaces matches token-by-token, rejoins. Tokens
    /// without a match pass through unchanged.
    private static func expandOCRAbbreviations(_ input: String) -> String {
        let tokens = input.split(separator: " ").map(String.init)
        let expanded = tokens.map { ocrAbbreviations[$0] ?? $0 }
        return expanded.joined(separator: " ")
    }

    /// Strip packing-medium phrases like `in olive oil`, `in water`,
    /// `drained`. Done after OCR expansion so `tonno in scatola`
    /// resolves via the alias map (intentional — that's an Italian
    /// idiom for "canned tuna," not a packing medium).
    private static func stripPackingMedium(_ input: String) -> String {
        var result = input
        for phrase in packingMediumPhrases {
            if let range = result.range(of: phrase) {
                result.removeSubrange(range)
            }
        }
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Remove parenthetical notes such as "(cooked)", "(1L bottle)", "(pre-cut)".
    /// Collapses repeated whitespace.
    private static func stripParentheticals(_ input: String) -> String {
        // Greedy paren removal — drop "(...)" segments.
        var result = input
        while let range = result.range(of: #"\s*\([^)]*\)?\s*"#, options: .regularExpression) {
            result.replaceSubrange(range, with: " ")
        }
        // Collapse repeated whitespace.
        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Remove brand tokens and multi-word brand patterns from a name.
    private static func stripBrands(_ input: String) -> String {
        let words = input.split(separator: " ").map(String.init)
        let cleaned = words.filter { !brandWords.contains($0) }
        var result = cleaned.joined(separator: " ")
        for brand in multiWordBrands {
            result = result.replacingOccurrences(of: brand, with: "")
        }
        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }
}

private extension String {
    func titleCased() -> String {
        split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
