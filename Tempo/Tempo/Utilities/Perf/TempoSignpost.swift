//
// TempoSignpost.swift
// Tempo
//
// Launch and tab timing, visible in Instruments (os_signpost, category
// "Speed") and printed in Debug builds.
//
//   LaunchToFirstContent  process start → Today has drawn real content
//   TabFirstContent       tab picked → that tab has drawn its first content
//

import Foundation
import os

@MainActor
enum TempoSignpost {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "app.tempo",
        category: "Speed"
    )

    private static var launchState: OSSignpostIntervalState?
    private static var launchDone = false
    private static var tabStates: [AppTab: (state: OSSignpostIntervalState, started: Date)] = [:]
    private static var tabsDone: Set<AppTab> = []

    /// Milliseconds from process start to Today's first content. Nil until it happens.
    private(set) static var launchToContentMs: Double?

    /// When the process was created, from the kernel: earlier than any code of ours.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else {
            return Date()
        }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    /// Call once, as early as possible in app start.
    static func launchBegan() {
        guard launchState == nil, !launchDone else {
            return
        }
        launchState = signposter.beginInterval("LaunchToFirstContent")
    }

    /// Today drew real content (`source` says whether it was saved or fresh).
    static func todayContentShown(source: String) {
        guard !launchDone else {
            return
        }
        launchDone = true
        if let launchState {
            signposter.endInterval("LaunchToFirstContent", launchState, "\(source, privacy: .public)")
        }
        launchState = nil
        let elapsed = Date().timeIntervalSince(processStart) * 1000
        launchToContentMs = elapsed
        #if DEBUG
            print("[Speed] launch → Today content (\(source)): \(String(format: "%.0f", elapsed)) ms")
        #endif
        tabContentShown(.today)
    }

    /// A tab was picked (or is the first one shown).
    static func tabPicked(_ tab: AppTab) {
        guard !tabsDone.contains(tab), tabStates[tab] == nil else {
            return
        }
        tabStates[tab] = (signposter.beginInterval("TabFirstContent", "\(tab.title, privacy: .public)"), Date())
    }

    /// That tab's first content is on screen.
    static func tabContentShown(_ tab: AppTab) {
        guard !tabsDone.contains(tab) else {
            return
        }
        tabsDone.insert(tab)
        guard let entry = tabStates.removeValue(forKey: tab) else {
            return
        }
        signposter.endInterval("TabFirstContent", entry.state, "\(tab.title, privacy: .public)")
        #if DEBUG
            let elapsed = Date().timeIntervalSince(entry.started) * 1000
            print("[Speed] \(tab.title) first content: \(String(format: "%.0f", elapsed)) ms")
        #endif
    }
}
