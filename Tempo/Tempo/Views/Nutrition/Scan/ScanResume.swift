//
// ScanResume.swift
// Tempo
//
// iOS can kill the app when camera access is switched on in Settings. Tapping
// "Open Settings" in the scanner leaves a small record; the next launch (or
// return to the app) within 10 minutes, with the camera now allowed, reopens
// the scanner in the same mode on the same Nutrition section. Only scanner
// contexts that can be rebuilt without caller closures are resumable
// (Today and Food check); the others just start from the Nutrition tab.
//

import Foundation
import SwiftUI

struct ScanResumeRecord: Codable, Equatable {
    var kind: String
    var mode: String
    var section: String
    var savedAt: Date

    var contextKind: ScanContextKind? {
        ScanContextKind.resumable(key: kind)
    }

    var scanMode: ScanMode {
        ScanMode(rawValue: mode) ?? .barcode
    }

    var nutritionSection: NutritionSection {
        NutritionSection(rawValue: section) ?? .today
    }
}

extension ScanContextKind {
    /// Stable key for contexts the scanner can rebuild on its own; nil otherwise.
    var resumeKey: String? {
        switch self {
        case .today: "today"
        case .foodCheck: "foodCheck"
        default: nil
        }
    }

    static func resumable(key: String) -> ScanContextKind? {
        allCases.first { $0.resumeKey == key }
    }
}

enum ScanResume {
    static let maxAge: TimeInterval = 10 * 60
    static let defaultsKey = "tempo.scan.pendingResume"

    /// Pure rule. The caller clears the stored record after every evaluation.
    static func decide(record: ScanResumeRecord?, cameraAuthorized: Bool, now: Date) -> ScanResumeRecord? {
        guard let record, cameraAuthorized,
              record.contextKind != nil,
              now.timeIntervalSince(record.savedAt) >= 0,
              now.timeIntervalSince(record.savedAt) <= maxAge
        else {
            return nil
        }
        return record
    }

    static func save(kind: ScanContextKind, mode: ScanMode, section: NutritionSection, now: Date = Date(), defaults: UserDefaults = .standard) {
        guard let key = kind.resumeKey,
              let data = try? JSONEncoder().encode(ScanResumeRecord(kind: key, mode: mode.rawValue, section: section.rawValue, savedAt: now))
        else {
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }

    static func load(defaults: UserDefaults = .standard) -> ScanResumeRecord? {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(ScanResumeRecord.self, from: $0) }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Reads, clears and decides in one step.
    @MainActor
    static func consume(now: Date = Date(), defaults: UserDefaults = .standard) -> ScanResumeRecord? {
        guard let record = load(defaults: defaults) else {
            return nil
        }
        clear(defaults: defaults)
        return decide(record: record, cameraAuthorized: AVAuthorized.isAuthorized, now: now)
    }
}

// MARK: - Environment

/// Set by the scanner so "Open Settings" knows what to remember.
struct ScanResumeInfo {
    var kind: ScanContextKind
    var mode: ScanMode
    var section: NutritionSection
}

private struct ScanResumeInfoKey: EnvironmentKey {
    static let defaultValue: ScanResumeInfo? = nil
}

private struct ScanResumeSectionKey: EnvironmentKey {
    static let defaultValue: NutritionSection = .today
}

extension EnvironmentValues {
    var scanResumeInfo: ScanResumeInfo? {
        get { self[ScanResumeInfoKey.self] }
        set { self[ScanResumeInfoKey.self] = newValue }
    }

    /// The Nutrition sub-tab the scanner was opened from.
    var scanResumeSection: NutritionSection {
        get { self[ScanResumeSectionKey.self] }
        set { self[ScanResumeSectionKey.self] = newValue }
    }
}
