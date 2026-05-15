//
// TempoModelContainer.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

@MainActor
struct TempoModelContainer {
    static func create(inMemory: Bool = false) throws -> ModelContainer {
        // V1 is the live schema. The new recipe fields
        // (RecipeIngredient.storageLocation/defrostLeadTimeHours/expiryDate,
        // PlannedMeal.eatDurationMinutes + recipe relationship) evolve V1 rather
        // than spinning up V2: SwiftData's `VersionedSchema` requires V2 to
        // declare its OWN model classes (RecipeIngredientV2 etc), and the
        // app hasn't shipped to production yet — there's nothing to migrate.
        // A real V2 will be introduced post-launch when a breaking change lands.
        let schema = Schema(TempoSchemaV1.models)

        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.tempo.Tempo"
        )

        if let groupURL, !inMemory {
            let supportDir = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        }

        let groupContainer: ModelConfiguration.GroupContainer =
            (!inMemory && groupURL != nil) ? .identifier("group.app.tempo.Tempo") : .none

        let config = ModelConfiguration(
            "Tempo",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: groupContainer,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [config]
        )
    }

    static func preview() throws -> ModelContainer {
        try create(inMemory: true)
    }
}
