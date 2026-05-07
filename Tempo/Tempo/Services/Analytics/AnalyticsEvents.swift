//
// AnalyticsEvents.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - Analytics Events

// Per ANALYTICS_AND_METRICS.md — Typed event helpers for critical user journeys.
// Per BUILD_PLAN Step 20.2 — Track onboarding, workouts, focus sessions, XP, subscriptions.

extension AnalyticsService {
    // MARK: - Onboarding

    func trackOnboardingStarted() {
        track("onboarding_started")
    }

    func trackOnboardingStepViewed(step: Int, name: String) {
        track("onboarding_step_viewed", properties: [
            "step_number": step,
            "step_name": name,
        ])
    }

    func trackOnboardingStepCompleted(step: Int, name: String) {
        track("onboarding_step_completed", properties: [
            "step_number": step,
            "step_name": name,
        ])
    }

    func trackOnboardingCompleted(totalSteps: Int) {
        track("onboarding_completed", properties: [
            "total_steps": totalSteps,
        ])
    }

    func trackOnboardingAbandoned(lastStep: Int) {
        track("onboarding_abandoned", properties: [
            "last_step": lastStep,
        ])
    }

    // MARK: - Dashboard

    func trackDashboardViewed(nnCompleted: Int, nnTotal: Int) {
        track("dashboard_viewed", properties: [
            "non_negotiables_completed": nnCompleted,
            "non_negotiables_total": nnTotal,
        ])
    }

    func trackQuadrantTapped(quadrant: String) {
        track("dashboard_quadrant_tapped", properties: [
            "quadrant": quadrant,
        ])
    }

    // MARK: - Training (RepForge)

    func trackWorkoutStarted(planId: String, exerciseCount: Int) {
        track("workout_started", properties: [
            "plan_id": planId,
            "exercise_count": exerciseCount,
        ])
    }

    func trackWorkoutCompleted(planId: String, durationMinutes: Int, completionRate: Double) {
        track("workout_completed", properties: [
            "plan_id": planId,
            "duration_minutes": durationMinutes,
            "completion_rate": completionRate,
        ])
    }

    func trackWorkoutAbandoned(planId: String, completionRate: Double) {
        track("workout_abandoned", properties: [
            "plan_id": planId,
            "completion_rate": completionRate,
        ])
    }

    // MARK: - Accountability (Lockdown)

    func trackFocusTimerStarted(durationMinutes: Int, subject: String?) {
        var props: [String: Any] = ["duration_minutes": durationMinutes]
        if subject != nil {
            props["has_subject"] = true
        }
        track("focus_timer_started", properties: props)
    }

    func trackFocusTimerCompleted(durationMinutes: Int, focusScore: Int) {
        track("focus_timer_completed", properties: [
            "duration_minutes": durationMinutes,
            "focus_score": focusScore,
        ])
    }

    func trackNonNegotiableCompleted(completedCount: Int, totalCount: Int) {
        track("non_negotiable_completed", properties: [
            "completed_count": completedCount,
            "total_count": totalCount,
        ])
    }

    func trackStreakAchieved(days: Int) {
        track("streak_achieved", properties: [
            "streak_days": days,
        ])
    }

    // MARK: - Arena (ClutchTime)

    func trackXPEarned(amount: Int, source: String) {
        track("xp_earned", properties: [
            "amount": amount,
            "source": source,
        ])
    }

    func trackLevelUp(newLevel: Int, totalXP: Int) {
        track("level_up", properties: [
            "new_level": newLevel,
            "total_xp": totalXP,
        ])
    }

    func trackAchievementEarned(achievementId: String) {
        track("achievement_earned", properties: [
            "achievement_id": achievementId,
        ])
    }

    // MARK: - Recovery

    func trackRecoveryViewed(zone: String) {
        track("recovery_viewed", properties: [
            "recovery_zone": zone,
        ])
    }

    // MARK: - Subscription

    func trackSubscriptionTrialStarted(productId: String) {
        track("subscription_trial_started", properties: [
            "product_id": productId,
        ])
    }

    func trackSubscriptionPurchased(productId: String, isAnnual: Bool) {
        track("subscription_purchased", properties: [
            "product_id": productId,
            "is_annual": isAnnual,
        ])
    }

    func trackSubscriptionExpired(productId: String) {
        track("subscription_expired", properties: [
            "product_id": productId,
        ])
    }

    func trackPaywallViewed(trigger: String) {
        track("paywall_viewed", properties: [
            "trigger": trigger,
        ])
    }

    // MARK: - Screen Views

    func trackScreenViewed(_ screenName: String, module: String? = nil) {
        var props: [String: Any] = ["screen_name": screenName]
        if let module {
            props["module"] = module
        }
        track("screen_viewed", properties: props)
    }

    // MARK: - Errors

    func trackError(type: String, message: String, screen: String, isFatal: Bool = false) {
        track("error_occurred", properties: [
            "error_type": type,
            "error_message": message,
            "screen_name": screen,
            "is_fatal": isFatal,
        ])
    }
}
