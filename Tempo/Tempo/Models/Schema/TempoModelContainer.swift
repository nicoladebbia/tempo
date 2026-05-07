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
        let schema = Schema(TempoSchemaV1.models)

        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.tempo"
        )

        if let groupURL, !inMemory {
            let supportDir = groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        }

        let groupContainer: ModelConfiguration.GroupContainer =
            (!inMemory && groupURL != nil) ? .identifier("group.app.tempo") : .none

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
