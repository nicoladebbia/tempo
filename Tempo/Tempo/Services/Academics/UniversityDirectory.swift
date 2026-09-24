//
// UniversityDirectory.swift
// Tempo
//
// Offline, searchable list of ~10k universities worldwide for the onboarding
// "University / School" picker. Data: Resources/Universities.json, generated
// from Hipo/university-domains-list (MIT) — `n` = name, `c` = ISO country code.
//

import Foundation

// MARK: - University

struct University: Hashable, Sendable, Decodable {
    let name: String
    let countryCode: String

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case countryCode = "c"
    }

    /// "United States" for "US"; falls back to the raw code.
    var countryName: String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }
}

// MARK: - UniversityDirectory

struct UniversityDirectory: Sendable {
    private struct Entry: Sendable {
        let university: University
        let folded: String
        let words: [String]
        let acronym: String
    }

    private let entries: [Entry]

    /// Bundled directory, decoded once on first use.
    static let shared = UniversityDirectory(universities: loadFromBundle())

    init(universities: [University]) {
        entries = universities.map { university in
            let folded = Self.fold(university.name)
            let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let acronym = String(words.filter { !Self.acronymStopWords.contains($0) }.compactMap(\.first))
            return Entry(university: university, folded: folded, words: words, acronym: acronym)
        }
    }

    /// Best matches for `query`, most relevant first: exact name, name
    /// prefix, acronym ("FIU"), word prefix, then substring. Ties prefer
    /// `preferredCountryCode`, then shorter names.
    func search(_ query: String, preferredCountryCode: String? = nil, limit: Int = 8) -> [University] {
        let needle = Self.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else {
            return []
        }
        let needleWords = needle.split(separator: " ").map(String.init)

        var ranked: [(rank: Int, entry: Entry)] = []
        for entry in entries {
            let rank: Int
            if entry.folded == needle {
                rank = 0
            } else if entry.folded.hasPrefix(needle) {
                rank = 1
            } else if entry.acronym == needle.filter({ $0 != "." }) {
                rank = 2
            } else if needleWords.allSatisfy({ word in entry.words.contains { $0.hasPrefix(word) } }) {
                rank = 3
            } else if entry.folded.contains(needle) {
                rank = 4
            } else {
                continue
            }
            ranked.append((rank, entry))
        }

        let preferred = preferredCountryCode?.uppercased()
        return ranked
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                let lhsPreferred = lhs.entry.university.countryCode == preferred
                let rhsPreferred = rhs.entry.university.countryCode == preferred
                if lhsPreferred != rhsPreferred {
                    return lhsPreferred
                }
                if lhs.entry.folded.count != rhs.entry.folded.count {
                    return lhs.entry.folded.count < rhs.entry.folded.count
                }
                return lhs.entry.folded < rhs.entry.folded
            }
            .prefix(limit)
            .map(\.entry.university)
    }

    // MARK: - Helpers

    private static let acronymStopWords: Set<String> = ["of", "the", "and", "at", "for", "in", "de", "la", "del", "di"]

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func loadFromBundle() -> [University] {
        guard let url = Bundle.main.url(forResource: "Universities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let universities = try? JSONDecoder().decode([University].self, from: data)
        else {
            return []
        }
        return universities
    }
}
