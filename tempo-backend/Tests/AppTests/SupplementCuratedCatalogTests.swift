@testable import App
import Foundation
import Testing

// Data-integrity checks on the curated, human-researched catalog — never a
// fabricated product: every pick must carry at least one certification and
// every URL (brand page + generated Amazon/iHerb search links) must parse.

struct SupplementCuratedCatalogTests {
    @Test func everySlugHasAtLeastOnePick() {
        for slug in SupplementCatalogSlug.allCases {
            let entry = SupplementCuratedCatalog.entries[slug]
            #expect(entry != nil, "missing catalog entry for \(slug.rawValue)")
            #expect((entry?.picks.isEmpty) == false, "\(slug.rawValue) has no picks")
        }
    }

    @Test func everyPickHasAtLeastOneCertification() {
        for (slug, entry) in SupplementCuratedCatalog.entries {
            for pick in entry.picks {
                #expect(!pick.certifications.isEmpty, "\(slug.rawValue) pick \(pick.brand) \(pick.product) has no certification")
            }
        }
    }

    @Test func everyPickHasNonEmptyBrandProductAndWhy() {
        for (slug, entry) in SupplementCuratedCatalog.entries {
            for pick in entry.picks {
                #expect(!pick.brand.trimmingCharacters(in: .whitespaces).isEmpty, "\(slug.rawValue) missing brand")
                #expect(!pick.product.trimmingCharacters(in: .whitespaces).isEmpty, "\(slug.rawValue) missing product")
                #expect(!pick.why.trimmingCharacters(in: .whitespaces).isEmpty, "\(slug.rawValue) missing why")
            }
        }
    }

    @Test func everyEntryHasALookForLine() {
        for (slug, entry) in SupplementCuratedCatalog.entries {
            #expect(!entry.lookFor.trimmingCharacters(in: .whitespaces).isEmpty, "\(slug.rawValue) missing look_for")
        }
    }

    @Test func everyWireBuyLinkIsAValidHTTPSURL() {
        for (slug, entry) in SupplementCuratedCatalog.entries {
            for product in entry.picks {
                let wire = product.toWire()
                #expect(!wire.buyLinks.isEmpty, "\(slug.rawValue) \(product.product) generated no buy links")
                for link in wire.buyLinks {
                    let url = URL(string: link.url)
                    #expect(url != nil, "\(slug.rawValue) \(product.product) invalid URL: \(link.url)")
                    #expect(url?.scheme == "https", "\(slug.rawValue) \(product.product) non-https URL: \(link.url)")
                }
            }
        }
    }

    @Test func generatedBuyLinksNeverCarryAffiliateTags() {
        // Nicola's instruction: plain search links, no affiliate tag params.
        let forbidden = ["tag=", "affid=", "ref=", "aff_id="]
        for entry in SupplementCuratedCatalog.entries.values {
            for product in entry.picks {
                for link in product.toWire().buyLinks {
                    for token in forbidden {
                        #expect(!link.url.contains(token), "buy link looks like it carries an affiliate tag: \(link.url)")
                    }
                }
            }
        }
    }

    @Test func wirePickCarriesPriceAsOfOnlyWhenPriceIsPresent() {
        for entry in SupplementCuratedCatalog.entries.values {
            for product in entry.picks {
                let wire = product.toWire()
                if wire.approxPricePerServingUSD != nil {
                    #expect(wire.priceAsOf == SupplementCuratedCatalog.priceAsOf)
                }
            }
        }
    }

    @Test func catalogCoversAllResearchedTypes() {
        // The brief named "20 supplement types" but the actual enumerated
        // list (creatine, whey/plant/casein protein, D3, omega-3, magnesium,
        // multivitamin, zinc, vitamin C, B12, iron, electrolytes, preworkout,
        // caffeine, melatonin, collagen, ashwagandha, beta-alanine,
        // citrulline, probiotic) is 21 distinct catalog slugs — every one of
        // them has a curated entry.
        #expect(SupplementCatalogSlug.allCases.count == 21)
        #expect(SupplementCuratedCatalog.entries.count == 21)
        #expect(Set(SupplementCatalogSlug.allCases) == Set(SupplementCuratedCatalog.entries.keys))
    }
}
