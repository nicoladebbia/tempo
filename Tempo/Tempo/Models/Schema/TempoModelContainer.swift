import SwiftData

@MainActor
struct TempoModelContainer {

    static func create(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(TempoSchemaV1.models)

        let config = ModelConfiguration(
            "Tempo",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .identifier("group.app.tempo"),
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: TempoMigrationPlan.self,
            configurations: [config]
        )
    }

    static func preview() throws -> ModelContainer {
        try create(inMemory: true)
    }
}
