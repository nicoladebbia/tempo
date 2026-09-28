import Foundation

// MARK: - SupplementCuratedCatalog

//
// Nicola's curated, human-researched supplement picks (feat/supplements-picks).
// Never a fabricated product or certification — every entry's certification
// was checked directly against the certifier's own site as of Sept 2026:
//   - NSF Certified for Sport   → nsfsport.com/certified-products (search by
//                                 brand/keyword, or a listing-detail page)
//   - Informed Sport            → sport.wetestyoutrust.com (Informed Sport's
//                                 own certified-product search)
//   - Informed Choice           → choice.wetestyoutrust.com
//   - USP Verified              → quality-supplements.org (USP's public
//                                 verified-products registry — each verified
//                                 product has its own page there)
//
// A few categories don't have a clean Certified-for-Sport/Informed-Sport/USP
// match on the US market right now (see `ashwagandha` below) — per Nicola's
// "fewer picks is better than a fake one" instruction, those entries carry
// only what could actually be verified, sometimes just one pick, with the
// exact (narrower) certification named rather than rounded up to something
// stronger.
//
// `sources`: research pass conducted via NSF/Informed Sport/USP's own sites
// plus brand product pages, Sept 2026. Prices are approximate (container
// price ÷ servings, rounded), not live.

enum SupplementCuratedCatalog {
    static let priceAsOf = "2026-09"

    struct Entry: Sendable {
        let lookFor: String
        let picks: [Product]
    }

    struct Product: Sendable {
        let brand: String
        let product: String
        let form: String?
        let certifications: [String]
        let why: String
        let approxPricePerServingUSD: Double?
        /// Brand's own product page, when known. Amazon/iHerb search links
        /// are generated from brand+product (see SupplementBuyLinks).
        let brandURL: String?

        func toWire() -> SupplementPicksDTO.Pick {
            SupplementPicksDTO.Pick(
                brand: brand,
                product: product,
                form: form,
                certifications: certifications,
                why: why,
                approxPricePerServingUSD: approxPricePerServingUSD,
                priceAsOf: SupplementCuratedCatalog.priceAsOf,
                buyLinks: SupplementBuyLinks.make(brand: brand, product: product, brandURL: brandURL)
            )
        }
    }

    static let entries: [SupplementCatalogSlug: Entry] = [
        // MARK: - Creatine monohydrate

        .creatineMonohydrate: Entry(
            lookFor: "Creatine monohydrate, 3–5 g/day; NSF Certified for Sport or Informed Sport is a strong purity signal, and Creapure-sourced (German-made) is a good secondary quality signal.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Creatine (Creatine Monohydrate Powder)",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Micronized, unflavored, no fillers, independently batch-tested through NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.45,
                    brandURL: "https://www.thorne.com/products/dp/creatine"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Creatine",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Simple 5 g unflavored creatine monohydrate, NSF Certified for Sport, no added ingredients.",
                    approxPricePerServingUSD: 0.39,
                    brandURL: "https://www.kleanathlete.com/klean-creatine.html"
                ),
                Product(
                    brand: "Momentous",
                    product: "Creatine Monohydrate Powder",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "NSF Certified for Sport with added third-party PFAS/heavy-metal/microplastic testing beyond the certification's baseline.",
                    approxPricePerServingUSD: 0.43,
                    brandURL: "https://www.livemomentous.com/products/creatine-monohydrate"
                ),
            ]
        ),

        // MARK: - Whey protein

        .wheyProtein: Entry(
            lookFor: "20–30 g protein/serving, minimal added sugar. Certification is often flavor/SKU-specific, not brand-wide — check the exact product you're buying.",
            picks: [
                Product(
                    brand: "Optimum Nutrition",
                    product: "Gold Standard 100% Whey (NSF Certified for Sport line, e.g. Double Rich Chocolate)",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Widely available whey isolate/concentrate blend with a specific NSF Certified for Sport SKU, 24 g protein.",
                    approxPricePerServingUSD: 1.30,
                    brandURL: "https://www.optimumnutrition.com/en-us/products/gold-standard-100-whey-protein-powder"
                ),
                Product(
                    brand: "Momentous",
                    product: "Whey Protein Isolate (Grass-Fed)",
                    form: "powder",
                    certifications: ["NSF Certified for Sport", "Informed Sport"],
                    why: "Dual-certified, grass-fed European dairy, 20 g protein, minimal ingredients.",
                    approxPricePerServingUSD: 2.40,
                    brandURL: "https://www.livemomentous.com/products/essential-whey-protein"
                ),
                Product(
                    brand: "Ascent",
                    product: "Native Fuel Whey Protein (100% Whey)",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "Native whey (less processed), zero artificial sweeteners/flavors, Informed Sport certified.",
                    approxPricePerServingUSD: 1.35,
                    brandURL: "https://www.ascentprotein.com/products/chocolate-protein-powder"
                ),
            ]
        ),

        // MARK: - Plant protein

        .plantProtein: Entry(
            lookFor: "20–30 g plant protein/serving from a pea/rice/pumpkin-seed blend for a complete amino profile. Third-party sport certification is rare for plant protein, so a certified pick is a meaningful differentiator.",
            picks: [
                Product(
                    brand: "Vega",
                    product: "Vega Sport Premium Protein (Plant-Based)",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Rare NSF Certified for Sport plant protein; pea/pumpkin/sunflower/alfalfa blend with 30 g protein and added BCAAs.",
                    approxPricePerServingUSD: 2.00,
                    brandURL: "https://myvega.com/products/vega-protein-recovery-premium-protein"
                ),
                Product(
                    brand: "Momentous",
                    product: "100% Plant Protein (Pea & Rice)",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Pea+rice blend for a complete amino profile, no gums/fillers, NSF Certified for Sport.",
                    approxPricePerServingUSD: 2.25,
                    brandURL: "https://www.livemomentous.com/products/100-plant-protein-powder"
                ),
                Product(
                    brand: "Ascent",
                    product: "Organic Plant Protein",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "USDA Organic + Informed Sport certified pea/pumpkin-seed protein, vegan and soy-free.",
                    approxPricePerServingUSD: 2.20,
                    brandURL: "https://www.ascentprotein.com/"
                ),
            ]
        ),

        // MARK: - Casein protein

        .caseinProtein: Entry(
            lookFor: "Slow-digesting micellar casein, ~20–25 g protein/serving, best taken before bed. Verified certification is rare for casein — prefer these over uncertified options.",
            picks: [
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Casein Protein",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "One of the only mainstream NSF Certified for Sport micellar casein powders on the market, 24 g protein.",
                    approxPricePerServingUSD: 2.25,
                    brandURL: "https://www.kleanathlete.com/klean-casein.html"
                ),
                Product(
                    brand: "Ascent",
                    product: "Native Fuel Micellar Casein",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "100% micellar casein, Informed Sport certified, 25 g protein, zero artificial flavors/sweeteners.",
                    approxPricePerServingUSD: 1.80,
                    brandURL: "https://www.ascentprotein.com/products/chocolate-micellar-casein"
                ),
            ]
        ),

        // MARK: - Vitamin D3 (+K2)

        .vitaminD3: Entry(
            lookFor: "1000–5000 IU D3/day (higher doses under guidance). A D3+K2 combo helps direct calcium to bone rather than soft tissue.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Vitamin D-5,000",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Simple, high-potency D3-only capsule with no unnecessary fillers, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.33,
                    brandURL: "https://www.thorne.com/products/dp/d-5-000-vitamin-d-capsule"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean-D",
                    form: "tablet",
                    certifications: ["NSF Certified for Sport"],
                    why: "D3-only, dose-flexible (1,000 or 5,000 IU), NSF Certified for Sport, no artificial colors/flavors.",
                    approxPricePerServingUSD: 0.20,
                    brandURL: "https://www.kleanathlete.com/klean-d-trade-5000-iu.html"
                ),
                Product(
                    brand: "Spoken Nutrition",
                    product: "D3 + K1/K2",
                    form: "liquid capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "One of the few NSF Certified for Sport D3+K2 combo products; 2,000 IU D3 with K1 and K2 for calcium-transport support.",
                    approxPricePerServingUSD: 0.58,
                    brandURL: "https://spokennutrition.com/products/spoken-d3-k1-k2-60ct"
                ),
            ]
        ),

        // MARK: - Omega-3 fish oil

        .omega3FishOil: Entry(
            lookFor: "Combined EPA+DHA of roughly 1–2 g/day, molecularly distilled for heavy-metal/PCB removal. NSF Certified for Sport gives banned-substance/contaminant assurance.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Super EPA",
                    form: "softgel",
                    certifications: ["NSF Certified for Sport"],
                    why: "425 mg EPA / 270 mg DHA per gelcap, molecularly distilled, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.44,
                    brandURL: "https://www.thorne.com/products/dp/super-epa"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Omega",
                    form: "softgel",
                    certifications: ["NSF Certified for Sport"],
                    why: "Triglyceride-form fish oil tested for heavy metals/PCBs/dioxins, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.47,
                    brandURL: "https://www.kleanathlete.com/klean-omega.html"
                ),
                Product(
                    brand: "Nordic Naturals",
                    product: "Ultimate Omega 2X Sport",
                    form: "softgel",
                    certifications: ["NSF Certified for Sport"],
                    why: "High-potency 2,150 mg total omega-3s per serving, NSF Certified for Sport, widely available.",
                    approxPricePerServingUSD: 0.75,
                    brandURL: "https://www.nordic.com/products/ultimate-omega-2x-sport/"
                ),
            ]
        ),

        // MARK: - Magnesium

        .magnesium: Entry(
            lookFor: "Chelated forms (bisglycinate/glycinate, malate, or threonate) absorb better and cause less GI upset than magnesium oxide; 200–400 mg elemental magnesium/day is typical.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Magnesium Bisglycinate",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Well-tolerated chelated form, 200 mg/serving, lightly sweetened with monk fruit, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.47,
                    brandURL: "https://www.thorne.com/products/dp/magnesium-bisglycinate"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Magnesium",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "120 mg magnesium glycinate per capsule, NSF Certified for Sport, GMO/gluten-free.",
                    approxPricePerServingUSD: 0.28,
                    brandURL: "https://www.kleanathlete.com/klean-magnesium.html"
                ),
                Product(
                    brand: "Momentous",
                    product: "Magnesium Malate",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "220 mg highly absorbable magnesium malate, NSF Certified for Sport — good for energy/muscle recovery.",
                    approxPricePerServingUSD: 1.00,
                    brandURL: "https://www.livemomentous.com/products/magnesium-malate"
                ),
            ]
        ),

        // MARK: - Multivitamin

        .multivitamin: Entry(
            lookFor: "A broad-spectrum multi covering the major vitamins/minerals at reasonable (not mega) doses. NSF Certified for Sport multis are less common than single-ingredient products — these are good anchors.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Basic Nutrients 2/Day",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Well-rounded multi with bioavailable nutrient forms, 2 capsules/day, NSF Certified for Sport.",
                    approxPricePerServingUSD: 1.20,
                    brandURL: "https://www.thorne.com/products/dp/basic-nutrients-2-day"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Multivitamin",
                    form: "tablet",
                    certifications: ["NSF Certified for Sport"],
                    why: "25+ vitamins/minerals plus a fruit/veggie antioxidant blend, NSF Certified for Sport.",
                    approxPricePerServingUSD: 1.10,
                    brandURL: "https://www.kleanathlete.com/klean-multivitamin.html"
                ),
                Product(
                    brand: "Momentous",
                    product: "Essential Multivitamin",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Complete mineral complex for energy/immune support, NSF Certified for Sport.",
                    approxPricePerServingUSD: 1.90,
                    brandURL: "https://www.livemomentous.com/products/essential-multivitamin"
                ),
            ]
        ),

        // MARK: - Zinc

        .zinc: Entry(
            lookFor: "15–30 mg elemental zinc/day; picolinate or glycinate forms absorb well. Avoid mega-dosing long-term without also covering copper intake.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Zinc Picolinate 30 mg",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Well-absorbed picolinate form at a standard 30 mg dose, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.27,
                    brandURL: "https://www.thorne.com/products/dp/double-strength-zinc-picolinate-60-s"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Zinc",
                    form: "chewable tablet",
                    certifications: ["NSF Certified for Sport"],
                    why: "Chewable format for easier daily compliance, NSF Certified for Sport, natural orange flavor.",
                    approxPricePerServingUSD: 0.20,
                    brandURL: "https://www.kleanathlete.com/klean-zinc.html"
                ),
            ]
        ),

        // MARK: - Vitamin C

        .vitaminC: Entry(
            lookFor: "250–1000 mg/day is typical. Verified certification is uncommon for plain vitamin C, so these two are notable exceptions to prefer over uncertified options.",
            picks: [
                Product(
                    brand: "Klean Athlete",
                    product: "Klean-C",
                    form: "chewable tablet",
                    certifications: ["NSF Certified for Sport"],
                    why: "525 mg vitamin C chewable for antioxidant/immune/connective-tissue support, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.30,
                    brandURL: "https://www.kleanathlete.com/klean-c.html"
                ),
                Product(
                    brand: "Core Med Science",
                    product: "Vitamin C (500mg)",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Straightforward 500 mg vitamin C, third-party tested for NCAA/pro banned substances, NSF Certified for Sport.",
                    approxPricePerServingUSD: 0.35,
                    brandURL: "https://coremedscience.com/"
                ),
            ]
        ),

        // MARK: - B12

        .b12: Entry(
            lookFor: "Methylcobalamin or a mix of active forms (adenosylcobalamin/hydroxycobalamin), 500–1000 mcg/day. B12 itself isn't a doping risk, but manufacturing contamination is — third-party testing still matters.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Vitamin B12",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Methylcobalamin (active form) in a single-ingredient capsule, from the brand with the largest NSF Certified for Sport catalog.",
                    approxPricePerServingUSD: 0.20,
                    brandURL: "https://www.thorne.com/products/dp/vitamin-b12-90"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean B-Complex",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Covers all B-vitamins at once — 800 mcg B12 (adenosylcobalamin + hydroxycobalamin) plus the full B-complex, NSF-certified.",
                    approxPricePerServingUSD: 0.50,
                    brandURL: "https://www.kleanathlete.com/"
                ),
            ]
        ),

        // MARK: - Iron

        .iron: Entry(
            lookFor: "A gentle, well-absorbed form like iron bisglycinate (less GI distress than ferrous sulfate), 18–27 mg elemental iron/day — only supplement with a doctor-confirmed low ferritin.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Iron Bisglycinate",
                    form: "capsule",
                    certifications: ["NSF Certified for Sport"],
                    why: "Chelated bisglycinate form reduces the nausea/constipation common with ferrous sulfate; every batch screened for banned substances and label accuracy.",
                    approxPricePerServingUSD: 0.32,
                    brandURL: "https://www.thorne.com/products/dp/iron-bisglycinate"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Iron",
                    form: "tablet",
                    certifications: ["NSF Certified for Sport"],
                    why: "27 mg iron carbonyl, a low-toxicity, well-tolerated form, from an NSF Certified for Sport-only brand.",
                    approxPricePerServingUSD: 0.22,
                    brandURL: "https://www.kleanathlete.com/"
                ),
            ]
        ),

        // MARK: - Electrolytes

        .electrolytes: Entry(
            lookFor: "Meaningful sodium (300–700+ mg/serving) as the primary driver, not just a flavored sugar packet. NSF Certified for Sport matters more here than most categories — contaminated hydration powders are a real positive-test risk for athletes.",
            picks: [
                Product(
                    brand: "BUBS Naturals",
                    product: "Hydrate or Die Electrolytes",
                    form: "powder (stick packs)",
                    certifications: ["NSF Certified for Sport"],
                    why: "Every finished lot is sent to NSF for testing; clean ingredient list, no added sugar.",
                    approxPricePerServingUSD: 1.20,
                    brandURL: "https://www.bubsnaturals.com/products/electrolytes-hydrate-or-die"
                ),
                Product(
                    brand: "Klean Athlete",
                    product: "Klean Electrolytes",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Straightforward sodium/potassium/magnesium blend from an all-NSF-certified sports brand.",
                    approxPricePerServingUSD: 0.80,
                    brandURL: "https://www.kleanathlete.com/"
                ),
                Product(
                    brand: "BioSteel",
                    product: "Hydration Mix",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Widely available mainstream retail, zero sugar, full NSF certification.",
                    approxPricePerServingUSD: 0.65,
                    brandURL: "https://biosteel.com/"
                ),
            ]
        ),

        // MARK: - Pre-workout

        .preworkout: Entry(
            lookFor: "Effective doses of caffeine (150–300 mg), citrulline (6–8 g) and beta-alanine (3.2 g) rather than a huge \"proprietary blend\". NSF Certified for Sport is strongly recommended — pre-workouts are the most contaminated supplement category in independent testing.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Advanced Pre-Workout",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Transparent label: 5 g L-citrulline, 3.2 g CarnoSyn beta-alanine, 200 mg natural caffeine — no proprietary blend.",
                    approxPricePerServingUSD: 2.50,
                    brandURL: "https://www.thorne.com/products/dp/advanced-pre-workout"
                ),
                Product(
                    brand: "Cellucor",
                    product: "C4 Sport",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Widely available in Miami retail (GNC, Publix, Target); 200 mg caffeine + beta-alanine, athlete-friendly formula.",
                    approxPricePerServingUSD: 1.20,
                    brandURL: "https://cellucor.com/products/c4-sport"
                ),
                Product(
                    brand: "Bare Performance Nutrition",
                    product: "PRE",
                    form: "powder",
                    certifications: ["NSF Certified for Sport"],
                    why: "Clean label, no artificial dyes, full NSF Certified for Sport line.",
                    approxPricePerServingUSD: 1.67,
                    brandURL: "https://www.bareperformancenutrition.com/"
                ),
            ]
        ),

        // MARK: - Caffeine

        .caffeine: Entry(
            lookFor: "Plain caffeine anhydrous or natural (green coffee bean) extract, 100–200 mg/serving, nothing else in the capsule. Genuinely certified standalone caffeine pills are rare — Informed Sport is the best signal here.",
            picks: [
                Product(
                    brand: "Kaged",
                    product: "Caffeine (PurCaf Organic Green Coffee Bean)",
                    form: "capsule",
                    certifications: ["Informed Sport"],
                    why: "100 mg per capsule from natural green coffee bean, no fillers, batch-tested — a true standalone caffeine pill.",
                    approxPricePerServingUSD: 0.15,
                    brandURL: "https://www.kaged.com/products/caffeine"
                ),
                Product(
                    brand: "NOW Sports",
                    product: "Caffeine 200mg",
                    form: "tablet",
                    certifications: ["Informed Sport"],
                    why: "Low-cost, higher 200 mg dose option, batch-tested for banned substances.",
                    approxPricePerServingUSD: 0.09,
                    brandURL: "https://www.nowfoods.com/"
                ),
            ]
        ),

        // MARK: - Melatonin

        .melatonin: Entry(
            lookFor: "Low dose (0.5–3 mg is enough for most people; anything above 5–10 mg is overkill and increases grogginess). USP Verified matters a lot here — independent testing has repeatedly found gummy melatonin content wildly off-label.",
            picks: [
                Product(
                    brand: "Nature Made",
                    product: "Melatonin 2.5 mg Gummies",
                    form: "gummy",
                    certifications: ["USP Verified"],
                    why: "Moderate dose, gummy format for easy adherence, independently confirmed to contain what's on the label.",
                    approxPricePerServingUSD: 0.11,
                    brandURL: "https://www.naturemade.com/products/nature-made-melatonin-2-5-mg-gummies"
                ),
                Product(
                    brand: "Natrol",
                    product: "Melatonin 5mg Fast Dissolve Tablets",
                    form: "tablet",
                    certifications: ["USP Verified"],
                    why: "Fast-dissolve format, widely available, USP-verified for content accuracy.",
                    approxPricePerServingUSD: 0.10,
                    brandURL: "https://www.natrol.com/"
                ),
            ]
        ),

        // MARK: - Collagen

        .collagen: Entry(
            lookFor: "Hydrolyzed collagen peptides (Type I & III) from grass-fed bovine or marine sources, 10–20 g/day. Third-party certification is uncommon in this category, so the Informed Sport/Choice picks below stand out.",
            picks: [
                Product(
                    brand: "Fluid Sports Nutrition",
                    product: "100% Collagen Peptides Powder",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "21 g Type I & III collagen per serving, grass-fed, unflavored — one of the very few Informed Sport-certified collagen products on the US market.",
                    approxPricePerServingUSD: 0.87,
                    brandURL: "https://store.livefluid.com/products/100-percent-collagen-peptides"
                ),
                Product(
                    brand: "Sports Research",
                    product: "Collagen Peptides (Hydrolyzed)",
                    form: "powder",
                    certifications: ["Informed Choice"],
                    why: "Widely available mainstream brand (Costco/Amazon/Vitamin Shoppe), unflavored, verified batch-tested.",
                    approxPricePerServingUSD: 0.75,
                    brandURL: "https://www.sportsresearch.com/products/collagen-peptides-hydrolyzed-gelatin-2"
                ),
            ]
        ),

        // MARK: - Ashwagandha

        //
        // No current NSF Certified for Sport, Informed Sport, or full USP
        // Dietary Supplement Verified Mark product could be confirmed on the
        // certifiers' own sites for this category (some secondary sources
        // claim "Nature Made Ashwagandha is USP Verified" — that product line
        // is discontinued and never had its own USP registry page, so that
        // claim was dropped). "NSF Contents Certified" is a real but
        // NARROWER program than "NSF Certified for Sport" (label-accuracy +
        // contaminant screening, not the ~270-substance athletic banned-list
        // screen) — named exactly, not rounded up, so the app never overstates it.

        .ashwagandha: Entry(
            lookFor: "A standardized, clinically-studied extract (KSM-66 or Sensoril), 300–600 mg/day. This category currently has no NSF Certified for Sport / Informed Sport / full USP Verified Mark product on the US market — treat any such claim elsewhere with skepticism.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Ashwagandha (Shoden extract)",
                    form: "capsule",
                    certifications: ["NSF Contents Certified"],
                    why: "Highly concentrated Shoden extract with NSF-backed label/content verification — note this is a narrower program than \"NSF Certified for Sport\", not the athletic banned-substance screen.",
                    approxPricePerServingUSD: 0.93,
                    brandURL: "https://www.thorne.com/"
                ),
            ]
        ),

        // MARK: - Beta-alanine

        .betaAlanine: Entry(
            lookFor: "CarnoSyn or plain beta-alanine, 3.2–6.4 g/day split into smaller doses to reduce the harmless tingling (paresthesia) — sustained-release formats reduce it further.",
            picks: [
                Product(
                    brand: "Thorne",
                    product: "Beta Alanine-SR",
                    form: "tablet (sustained-release)",
                    certifications: ["NSF Certified for Sport"],
                    why: "Sustained-release delivery minimizes the tingling side effect while maintaining the full clinical dose.",
                    approxPricePerServingUSD: 0.43,
                    brandURL: "https://www.thorne.com/products/dp/beta-alanine-sr"
                ),
                Product(
                    brand: "NOW Sports",
                    product: "Beta-Alanine (750mg capsules)",
                    form: "capsule",
                    certifications: ["Informed Sport"],
                    why: "Budget-friendly, straightforward dosing, batch-tested for banned substances.",
                    approxPricePerServingUSD: 0.12,
                    brandURL: "https://www.nowfoods.com/"
                ),
            ]
        ),

        // MARK: - Citrulline

        .citrulline: Entry(
            lookFor: "Pure L-citrulline (not a citrulline-malate blend padded with malic-acid filler) dosed at 6–8 g/day. Check the Supplement Facts panel for grams of citrulline itself.",
            picks: [
                Product(
                    brand: "Kaged",
                    product: "Citrulline (Fermented L-Citrulline)",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "Pure fermented L-citrulline with zero malate filler, so you know exactly how much active ingredient is in each gram.",
                    approxPricePerServingUSD: 0.16,
                    brandURL: "https://www.kaged.com/products/citrulline"
                ),
                Product(
                    brand: "NOW Sports",
                    product: "Arginine & Citrulline Powder (1:1)",
                    form: "powder",
                    certifications: ["Informed Sport"],
                    why: "Budget-friendly certified option — note this is an arginine+citrulline blend, not pure citrulline, so check the label for actual citrulline grams per scoop.",
                    approxPricePerServingUSD: 0.30,
                    brandURL: "https://www.nowfoods.com/"
                ),
            ]
        ),

        // MARK: - Probiotic

        .probiotic: Entry(
            lookFor: "A clinically-studied single or few-strain formula (e.g. Lactobacillus rhamnosus GG) at 10+ billion CFU rather than a 20-strain blend with no dosing evidence. USP Verified matters a lot here — CFU counts are notoriously overstated industry-wide.",
            picks: [
                Product(
                    brand: "Culturelle",
                    product: "Digestive Daily Probiotic Vegetarian Capsules",
                    form: "capsule",
                    certifications: ["USP Verified"],
                    why: "Single well-studied strain (Lactobacillus rhamnosus GG) at a clinically-relevant 10 billion CFU dose, independently confirmed to contain what's on the label.",
                    approxPricePerServingUSD: 0.55,
                    brandURL: "https://culturelle.com/products/digestive-daily-probiotic"
                ),
                Product(
                    brand: "trunature",
                    product: "Advanced Digestive Probiotic Capsules",
                    form: "capsule",
                    certifications: ["USP Verified"],
                    why: "Costco house brand (widely available in Miami), multi-strain, independently CFU/potency verified through expiration.",
                    approxPricePerServingUSD: 0.30,
                    brandURL: "https://www.costco.com/"
                ),
            ]
        ),
    ]
}
