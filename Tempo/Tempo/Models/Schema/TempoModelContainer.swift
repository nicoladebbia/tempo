import Foundation
import SwiftData

@MainActor
struct TempoModelContainer {

    static func create(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(TempoSchemaV1.models)

        // Use App Group container for production builds; fall back to default
        // container when the App Group isn't available (e.g., simulator without
        // provisioning profile, or unit tests).
        let hasAppGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.tempo"
        ) != nil

        let groupContainer: ModelConfiguration.GroupContainer =
            (!inMemory && hasAppGroup) ? .identifier("group.app.tempo") : .none

        let config = ModelConfiguration(
            "Tempo",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: groupContainer,
            cloudKitDatabase: .none
        )

        // When the App Group is available, use migration plan for data upgrades.
        // Otherwise (simulator/tests), skip migration to avoid SwiftData issues.
        if hasAppGroup {
            return try ModelContainer(
                for: schema,
                migrationPlan: TempoMigrationPlan.self,
                configurations: [config]
            )
        } else {
            return try ModelContainer(
                for: schema,
                configurations: [config]
            )
        }
    }

    static func preview() throws -> ModelContainer {
        try create(inMemory: true)
    }
}
