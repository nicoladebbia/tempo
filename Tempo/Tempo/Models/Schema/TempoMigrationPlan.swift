//
// TempoMigrationPlan.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData

enum TempoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TempoSchemaV1.self, TempoSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TempoSchemaV1.self,
        toVersion: TempoSchemaV2.self
    )
}
