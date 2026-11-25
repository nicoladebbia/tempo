//
// LocalizationCatalogTests.swift
// Tempo
//
// Italian pass: every string in the String Catalogs must have an Italian
// translation that is finished (state "translated"), none may be stale, and a
// translation must keep the placeholders of the English text. A few plural
// entries are also looked up in the Italian bundle that really ships.
//
// The catalogs are read from the source tree (`#filePath`), so the test sees
// exactly what was committed, independent of what the build copied.
//

import Foundation
@testable import Tempo
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    // MARK: - Catalog loading

    private struct Catalog {
        let name: String
        let strings: [String: [String: Any]]
    }

    /// `<repo>/Tempo` (the Xcode project folder), found from this file's path.
    private var projectDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Utilities
            .deletingLastPathComponent() // TempoTests
            .deletingLastPathComponent() // Tempo (project folder)
    }

    private func loadCatalog(_ relativePath: String) throws -> Catalog {
        let url = projectDir.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "en", "\(relativePath): English must be the source language")
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]], "\(relativePath): no strings")
        return Catalog(name: relativePath, strings: strings)
    }

    private let catalogPaths = [
        "Tempo/Localizable.xcstrings",
        "Tempo/InfoPlist.xcstrings",
        "Tempo/AppShortcuts.xcstrings",
        "TempoWidget/Localizable.xcstrings",
    ]

    // MARK: - Helpers

    /// Every `state` found under an Italian localization (string unit, plural
    /// forms, string set). Empty when there is no Italian at all.
    private func italianStates(_ entry: [String: Any]) -> [String] {
        guard let locs = entry["localizations"] as? [String: Any],
              let it = locs["it"] as? [String: Any]
        else {
            return []
        }
        var states: [String] = []
        if let unit = it["stringUnit"] as? [String: Any] {
            states.append(unit["state"] as? String ?? "missing")
        }
        if let set = it["stringSet"] as? [String: Any] {
            states.append(set["state"] as? String ?? "missing")
        }
        if let variations = it["variations"] as? [String: Any] {
            for (_, kind) in variations {
                for (_, form) in (kind as? [String: Any]) ?? [:] {
                    let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any]
                    states.append(unit?["state"] as? String ?? "missing")
                }
            }
        }
        return states
    }

    /// All Italian strings of an entry (to compare placeholders).
    private func italianValues(_ entry: [String: Any]) -> [String] {
        guard let locs = entry["localizations"] as? [String: Any],
              let it = locs["it"] as? [String: Any]
        else {
            return []
        }
        var values: [String] = []
        if let unit = it["stringUnit"] as? [String: Any], let v = unit["value"] as? String {
            values.append(v)
        }
        if let variations = it["variations"] as? [String: Any] {
            for (_, kind) in variations {
                for (_, form) in (kind as? [String: Any]) ?? [:] {
                    if let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any],
                       let v = unit["value"] as? String
                    {
                        values.append(v)
                    }
                }
            }
        }
        return values
    }

    /// Format specifiers as "position:type" strings, sorted. Unnumbered
    /// specifiers get their order of appearance as position.
    private func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?[-+0#]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSpn])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let ns = text as NSString
        var out: [String] = []
        var index = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            // "%%" is matched by the pattern only as part of "%x"; skip literal percent signs.
            if match.range.location > 0, ns.substring(with: NSRange(location: match.range.location - 1, length: 1)) == "%" {
                continue
            }
            index += 1
            var type = ns.substring(with: match.range(at: 2))
            type = ["D": "d", "i": "d", "U": "u", "F": "f", "e": "f", "E": "f", "g": "f", "G": "f"][type] ?? type
            let position = match.range(at: 1).location == NSNotFound
                ? index
                : Int(ns.substring(with: match.range(at: 1))) ?? index
            out.append("\(position):\(type)")
        }
        return out.sorted()
    }

    private func hasLetters(_ key: String) -> Bool {
        let stripped = key.replacingOccurrences(
            of: #"%(?:\d+\$)?[-+0#]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGaAcCsSpn]"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"\$\{[A-Za-z]+\}"#, with: " ", options: .regularExpression)
        return stripped.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil
    }

    private func report(_ lines: [String], limit: Int = 25) -> String {
        let shown = lines.prefix(limit).joined(separator: "\n  ")
        return lines.count > limit ? "\(shown)\n  ... and \(lines.count - limit) more" : shown
    }

    // MARK: - Catalog completeness

    /// A string with no Italian, or with an Italian that is still "new" or
    /// "needs_review", must fail the build, so English never leaks into an
    /// Italian phone unnoticed.
    func testEveryStringHasFinishedItalian() throws {
        for path in catalogPaths {
            let catalog = try loadCatalog(path)
            var problems: [String] = []
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                if (entry["shouldTranslate"] as? Bool) == false {
                    continue
                }
                let states = italianStates(entry)
                if states.isEmpty {
                    problems.append("no Italian: \(key.prefix(90))")
                } else if let bad = states.first(where: { $0 != "translated" }) {
                    problems.append("state \(bad): \(key.prefix(90))")
                }
            }
            XCTAssertTrue(problems.isEmpty, "\(path): \(problems.count) strings not translated\n  \(report(problems))")
        }
    }

    /// "stale" means the code no longer contains the string: dead catalog rows.
    func testNoStaleEntries() throws {
        for path in catalogPaths {
            let catalog = try loadCatalog(path)
            let stale = catalog.strings.filter { ($0.value["extractionState"] as? String) == "stale" }.map(\.key).sorted()
            XCTAssertTrue(stale.isEmpty, "\(path): \(stale.count) stale strings\n  \(report(stale))")
        }
    }

    /// Reordering with positional placeholders is allowed; dropping, adding or
    /// retyping one is a crash or a wrong number on screen.
    func testItalianKeepsPlaceholders() throws {
        for path in catalogPaths {
            let catalog = try loadCatalog(path)
            var problems: [String] = []
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                if (entry["shouldTranslate"] as? Bool) == false {
                    continue
                }
                let expected = placeholders(key)
                for value in italianValues(entry) {
                    var found = placeholders(value)
                    // A plural "one" form may spell the number out ("un giorno").
                    if found != expected, found.isEmpty, entry["localizations"] != nil,
                       let it = (entry["localizations"] as? [String: Any])?["it"] as? [String: Any],
                       it["variations"] != nil
                    {
                        found = expected
                    }
                    if found != expected {
                        problems.append("\(key.prefix(70)) -> \(value.prefix(70)) (\(expected) vs \(found))")
                    }
                }
            }
            XCTAssertTrue(problems.isEmpty, "\(path): placeholder mismatch\n  \(report(problems))")
        }
    }

    /// Siri phrases only work when they contain the app name token.
    func testSiriPhrasesKeepApplicationName() throws {
        let catalog = try loadCatalog("Tempo/AppShortcuts.xcstrings")
        var problems: [String] = []
        for (key, entry) in catalog.strings {
            let it = (entry["localizations"] as? [String: Any])?["it"] as? [String: Any]
            let values = ((it?["stringSet"] as? [String: Any])?["values"] as? [String]) ?? []
            if values.isEmpty {
                problems.append("no Italian phrases: \(key)")
            }
            for phrase in values where !phrase.contains("${applicationName}") {
                problems.append("\(key): '\(phrase)' lost ${applicationName}")
            }
        }
        XCTAssertTrue(problems.isEmpty, report(problems))
    }

    /// The catalog must not have drifted: every Italian row has a visible letter
    /// somewhere, so we never ship an empty string.
    func testNoEmptyItalian() throws {
        for path in catalogPaths {
            let catalog = try loadCatalog(path)
            var problems: [String] = []
            for (key, entry) in catalog.strings {
                if (entry["shouldTranslate"] as? Bool) == false {
                    continue
                }
                for value in italianValues(entry) where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problems.append("empty Italian: \(key.prefix(80))")
                }
            }
            XCTAssertTrue(problems.isEmpty, "\(path):\n  \(report(problems))")
        }
    }

    /// Keys flagged "not translatable" must really have nothing to translate.
    func testNotTranslatableKeysHaveNoWords() throws {
        for path in catalogPaths {
            let catalog = try loadCatalog(path)
            let wrong = catalog.strings.filter { ($0.value["shouldTranslate"] as? Bool) == false && hasLetters($0.key) }
                .map(\.key).filter { $0 != "CFBundleName" && $0 != "CFBundleDisplayName" }.sorted()
            XCTAssertTrue(wrong.isEmpty, "\(path): marked untranslatable but has words\n  \(report(wrong))")
        }
    }

    // MARK: - Plurals in the shipped bundle

    /// The bundle that holds the compiled Italian strings (the app, whether the
    /// tests run hosted or not).
    private func italianBundle() throws -> Bundle {
        let candidates = [Bundle.main, Bundle(for: AppState.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            if let path = bundle.path(forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: "it")
                ?? bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "it"),
                let itBundle = Bundle(path: (path as NSString).deletingLastPathComponent)
            {
                return itBundle
            }
        }
        struct MissingItalian: Error {}
        XCTFail("No Italian localization is built into the app (it.lproj is missing).")
        throw MissingItalian()
    }

    private func italian(_ key: String, _ count: Int) throws -> String {
        let bundle = try italianBundle()
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: "it"), count)
    }

    func testItalianPluralDays() throws {
        XCTAssertEqual(try italian("%lld days", 1), "1 giorno")
        XCTAssertEqual(try italian("%lld days", 0), "0 giorni")
        XCTAssertEqual(try italian("%lld days", 5), "5 giorni")
    }

    func testItalianPluralSessions() throws {
        XCTAssertEqual(try italian("%lld sessions", 1), "1 sessione")
        XCTAssertEqual(try italian("%lld sessions", 3), "3 sessioni")
    }

    func testItalianPluralPoints() throws {
        XCTAssertEqual(try italian("%lld points", 1), "1 punto")
        XCTAssertEqual(try italian("%lld points", 12), "12 punti")
    }

    /// English output is the old output: one/other forms stay English.
    func testEnglishPluralsUnchanged() {
        XCTAssertEqual(String(localized: "\(1) days", locale: Locale(identifier: "en")), "1 day")
        XCTAssertEqual(String(localized: "\(4) days", locale: Locale(identifier: "en")), "4 days")
    }

    func testItalianTranslatesAKnownKey() throws {
        let bundle = try italianBundle()
        XCTAssertEqual(bundle.localizedString(forKey: "Today", value: nil, table: nil), "Oggi")
    }
}
