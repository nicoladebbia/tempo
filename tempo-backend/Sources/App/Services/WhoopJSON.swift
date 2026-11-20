import Foundation
import Vapor

/// Decodes WHOOP API responses.
///
/// The app-wide JSON decoder converts snake_case keys itself (configure.swift), so a DTO that ALSO declares
/// snake_case `CodingKeys` fails to decode ("Key 'user_id' not found"). Every WHOOP DTO declares its own keys, so
/// WHOOP bodies must go through a plain decoder. Verified with WHOOP's own sample payload in WhoopIntegrationTests.
enum WhoopJSON {
    static func decode<T: Decodable>(_ type: T.Type, from response: ClientResponse) throws -> T {
        guard var body = response.body, let data = body.readData(length: body.readableBytes) else {
            throw Abort(.badGateway, reason: "WHOOP returned an empty response.")
        }
        return try decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
