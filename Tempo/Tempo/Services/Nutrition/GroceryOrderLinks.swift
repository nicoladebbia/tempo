//
// GroceryOrderLinks.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

// MARK: - GroceryOrderLink

/// One per-item "find it online" link shown in the fallback sheet when
/// Instacart isn't configured server-side (or the request fails).
struct GroceryOrderLink: Identifiable, Sendable {
    let id = UUID()
    let itemName: String
    let storeName: String
    let url: URL
}

// MARK: - GroceryOrderLinks

///
/// Per-item fallback search links for "Order/find online" when the backend
/// has no INSTACART_API_KEY configured. Nicola shops Publix and Aldi (both
/// Instacart-fulfilled) and Whole Foods (Amazon only).
///
/// Deliberately NOT including a direct Publix.com search URL: Publix doesn't
/// publish a stable, documented search-by-query URL scheme, and fabricating
/// one risked linking to a 404 or the wrong page. The generic Instacart
/// search link already covers Publix and Aldi (both are on Instacart), so
/// the only other verified, stable link is Amazon's `i=wholefoods`
/// department filter for Whole Foods. This is a deliberate scope decision —
/// see the Lane C handoff report.
enum GroceryOrderLinks {
    static func instacartSearchURL(for itemName: String) -> URL? {
        var components = URLComponents(string: "https://www.instacart.com/store/s")
        components?.queryItems = [URLQueryItem(name: "k", value: itemName)]
        return components?.url
    }

    static func amazonWholeFoodsSearchURL(for itemName: String) -> URL? {
        var components = URLComponents(string: "https://www.amazon.com/s")
        components?.queryItems = [
            URLQueryItem(name: "k", value: itemName),
            URLQueryItem(name: "i", value: "wholefoods"),
        ]
        return components?.url
    }

    /// Two links per item — Instacart (Publix/Aldi) and Amazon Fresh/Whole
    /// Foods — for every item name given, in the order supplied.
    static func fallbackLinks(for itemNames: [String]) -> [GroceryOrderLink] {
        itemNames.flatMap { name -> [GroceryOrderLink] in
            var links: [GroceryOrderLink] = []
            if let url = instacartSearchURL(for: name) {
                links.append(GroceryOrderLink(itemName: name, storeName: "Instacart (Publix/Aldi)", url: url))
            }
            if let url = amazonWholeFoodsSearchURL(for: name) {
                links.append(GroceryOrderLink(itemName: name, storeName: "Amazon (Whole Foods)", url: url))
            }
            return links
        }
    }
}
