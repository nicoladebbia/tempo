import Foundation

enum TrainingSplit: String, Codable, CaseIterable, Sendable {
    case pushPullLegs = "ppl"
    case upperLower = "upper_lower"
    case fullBody = "full_body"
    case bro = "bro_split"
    case custom
}
