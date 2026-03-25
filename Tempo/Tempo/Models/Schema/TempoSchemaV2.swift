import SwiftData

enum TempoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    // IMPORTANT: When V2 is actually needed, you MUST duplicate the full model list
    // here with the V2 versions of each model. VersionedSchema requires each schema
    // version to declare its own model types. Using TempoSchemaV1.models as a placeholder
    // is acceptable ONLY while V2 has no actual schema differences.
    static var models: [any PersistentModel.Type] {
        TempoSchemaV1.models
    }
}
