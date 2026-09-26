import Foundation

// MARK: - HTML escaping

// Per feat/grocery-share-order — item names, titles and store names on the
// public shared-grocery-list page are all user-authored text embedded into
// server-rendered HTML, so they must be escaped before going into a text
// node or attribute.

extension String {
    /// Minimal HTML-entity escaping for untrusted text embedded in the
    /// public shared-grocery-list page. Escapes the five characters that
    /// matter for breaking out of text/attribute context. Not a general
    /// sanitizer, but sufficient here since the page never echoes this text
    /// back as raw HTML/script, only as text content or a quoted attribute.
    var htmlEscaped: String {
        var out = ""
        out.reserveCapacity(count)
        for char in self {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(char)
            }
        }
        return out
    }
}
