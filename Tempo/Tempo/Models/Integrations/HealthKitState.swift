import Foundation
import SwiftData

@Model
final class HealthKitState {

    @Attribute(.unique)
    var id: UUID

    var authorizedReadTypesJSON: Data?

    var authorizedWriteTypesJSON: Data?

    var lastBackgroundDelivery: Date?

    var authorizationRequested: Bool

    // MARK: - Computed

    @Transient
    var authorizedReadTypes: [String] {
        get {
            guard let data = authorizedReadTypesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            authorizedReadTypesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var authorizedWriteTypes: [String] {
        get {
            guard let data = authorizedWriteTypesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            authorizedWriteTypesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        authorizedReadTypes: [String] = [],
        authorizedWriteTypes: [String] = [],
        lastBackgroundDelivery: Date? = nil,
        authorizationRequested: Bool = false
    ) {
        self.id = id
        self.authorizedReadTypesJSON = try? JSONEncoder().encode(authorizedReadTypes)
        self.authorizedWriteTypesJSON = try? JSONEncoder().encode(authorizedWriteTypes)
        self.lastBackgroundDelivery = lastBackgroundDelivery
        self.authorizationRequested = authorizationRequested
    }
}
