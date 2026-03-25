import Foundation

// MARK: - String Random Hex
// Per VAPOR_PROJECT_STRUCTURE.md — Helper for generating random hex strings.

extension String {
    /// Generate a random hex string of the given length (in bytes, output is 2x length in chars).
    static func randomHex(length: Int) -> String {
        (0..<length).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
    }
}
