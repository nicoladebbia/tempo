import SwiftData

enum TempoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            UserSettings.self,
            DailySnapshot.self,
            WorkoutPlan.self,
            PlannedExercise.self,
            PlannedSet.self,
            Exercise.self,
            ExerciseHistory.self,
            PersonalRecord.self,
            RunSession.self,
            NonNegotiable.self,
            DailyAccountability.self,
            NonNegotiableProgress.self,
            StudySession.self,
            Streak.self,
            DailyRecovery.self,
            DailyPrescription.self,
            RecoveryInsight.self,
            XPEvent.self,
            Achievement.self,
            ChallengeLocal.self,
            SyncState.self,
            PendingSync.self,
            WhoopConnection.self,
            NutriTrackConnection.self,
            HealthKitState.self,
        ]
    }
}
