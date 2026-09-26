import Foundation

// MARK: - JSONValue

//
// Generic, order-agnostic JSON value used to pass arbitrary AI-authored
// fields straight through a strongly-typed pipeline without modeling their
// shape. First consumer: WeeklyPlanJob's per-day `supplements` array, which
// the AI produces in whatever shape it likes and we must store/return
// untouched.
//
// IMPORTANT: this is Codable via a plain `singleValueContainer`, so it is
// only safe to encode with an encoder that has NO `keyEncodingStrategy` set
// (Foundation's `JSONEncoder.keyEncodingStrategy` rewrites the keys of ANY
// keyed container it touches, including the `[String: JSONValue]` case
// below — there is no way to exempt a subtree). WeeklyPlanController and
// WeeklyPlanJob both use a bare `JSONEncoder()` for anything that embeds a
// JSONValue, deliberately bypassing `ContentConfiguration.global`.

indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
