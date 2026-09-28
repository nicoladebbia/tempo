import Foundation

// MARK: - SupplementBuyLinks

//
// Generates the generic Amazon/iHerb *search* links (no affiliate tags —
// Nicola's instruction) plus, when known, the brand's own product page.
// Shared by the curated catalog and the AI-fallback path so buy links are
// built the same way regardless of source.

enum SupplementBuyLinks {
    static func make(brand: String, product: String, brandURL: String?) -> [SupplementPicksDTO.BuyLink] {
        var links: [SupplementPicksDTO.BuyLink] = []
        if let brandURL, !brandURL.isEmpty {
            links.append(.init(label: brand, url: brandURL))
        }
        let query = "\(brand) \(product)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return links }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        links.append(.init(label: "Amazon", url: "https://www.amazon.com/s?k=\(encoded)"))
        links.append(.init(label: "iHerb", url: "https://www.iherb.com/search?kw=\(encoded)"))
        return links
    }
}
