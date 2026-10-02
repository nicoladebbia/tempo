import Foundation

// MARK: - Recorded Claude replies

//
// `scripts/testenv.sh up --real-ai --record` saves every real Claude reply
// (the raw Anthropic response body) under <dir>/<feature>/<time>.json.
// AI mode `replay` then answers each feature with its newest recording —
// real model output, at no cost and without a key — and falls back to the
// fake fixture for a feature that has none yet. Recordings live outside the
// repo (~/.tempo-testenv/ai-recordings): they can contain whatever was typed
// into the app.

struct AIRecordings: Sendable {
    let directory: URL

    static func defaultDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["TEMPO_TEST_AI_RECORDINGS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tempo-testenv/ai-recordings", isDirectory: true)
    }

    func save(feature: String, body: String, at date: Date = Date()) throws {
        let folder = directory.appendingPathComponent(Self.safe(feature), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        try Data(body.utf8).write(to: folder.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(6)).json"))
    }

    /// Newest recording for `feature`, or nil.
    func latest(feature: String) -> String? {
        let folder = directory.appendingPathComponent(Self.safe(feature), isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        // Names start with an ISO timestamp, so they sort by time.
        guard let newest = files.filter({ $0.pathExtension == "json" }).map(\.lastPathComponent).sorted().last else {
            return nil
        }
        return try? String(contentsOf: folder.appendingPathComponent(newest), encoding: .utf8)
    }

    /// Features with at least one recording → how many.
    func counts() -> [String: Int] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var out: [String: Int] = [:]
        for folder in folders {
            let n = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.count
            if n > 0 {
                out[folder.lastPathComponent] = n
            }
        }
        return out
    }

    private static func safe(_ feature: String) -> String {
        String(feature.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }
}
