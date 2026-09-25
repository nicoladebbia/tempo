//
// TempoSchemaV1.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData

enum TempoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            UserSettings.self,
            UserDailyPlanProfile.self,
            ClassBlock.self,
            WorkBlock.self,
            DayPlan.self,
            TimeBlock.self,
            DailySnapshot.self,
            WorkoutPlan.self,
            WorkoutRoutine.self,
            TrainerProgram.self,
            PlannedExercise.self,
            PlannedSet.self,
            Exercise.self,
            ExerciseHistory.self,
            PersonalRecord.self,
            SetFeedback.self,
            AdaptiveProfile.self,
            PredictionLog.self,
            DailySession.self,
            Match.self,
            TrainingBlock.self,
            MonthlyReview.self,
            VenuePattern.self,
            VenueConfirmation.self,
            RunSession.self,
            ActivitySession.self,
            ConditioningBlockResult.self,
            NonNegotiable.self,
            DailyAccountability.self,
            NonNegotiableProgress.self,
            StudySession.self,
            Streak.self,
            DailyRecovery.self,
            DailyPrescription.self,
            RecoveryInsight.self,
            MorningCheckIn.self,
            BodyComposition.self,
            XPEvent.self,
            Achievement.self,
            ChallengeLocal.self,
            ActivityEvent.self,
            SyncState.self,
            PendingSync.self,
            WhoopConnection.self,
            HealthKitState.self,
            // Dashboard
            DailyScoreEntry.self,
            // Nutrition
            MealLog.self,
            MealFoodItem.self,
            NutritionTarget.self,
            CachedFood.self,
            ScannedFood.self,
            DietaryProfile.self,
            WeeklyMealPlan.self,
            PlannedMeal.self,
            MealPreset.self,
            MealFeedback.self,
            MacroCarryover.self,
            PantryItem.self,
            PantryPriceEntry.self,
            Supplement.self,
            SupplementIntakeLog.self,
            KitchenEquipment.self,
            Receipt.self,
            ReceiptLineItem.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            GroceryList.self,
            GroceryListItem.self,
            // Coach (v2.1)
            LearnedPreference.self,
            LearnedOutcome.self,
            CoachConversation.self,
            PendingOutcome.self,
        ]
    }
}
