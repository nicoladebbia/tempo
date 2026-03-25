import Foundation

enum TrainingSplit: String, Codable, CaseIterable, Sendable {
    case pushPullLegs = "ppl"
    case upperLower = "upper_lower"
    case fullBody = "full_body"
    case bro = "bro_split"
    case custom

    var displayName: String {
        switch self {
        case .pushPullLegs: "Push/Pull/Legs"
        case .upperLower: "Upper/Lower"
        case .fullBody: "Full Body"
        case .bro: "Bro Split"
        case .custom: "Custom"
        }
    }
}
