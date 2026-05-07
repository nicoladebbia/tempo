//
// PushRegistrationService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os
import UIKit
import UserNotifications

// MARK: - PushRegistrationService

// Per BUILD_PLAN step 12.1 — Register for remote notifications, send device token to backend.
// Per ADR-019 — Direct APNs with P8 token-based authentication.
// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 5.4 — apnswift is production-ready.

@Observable
final class PushRegistrationService: @unchecked Sendable {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "PushRegistration")

    private(set) var isRegistered: Bool = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Request Authorization & Register

    /// Request notification authorization and register for remote notifications.
    /// Per ONBOARDING_AND_NOTIFICATIONS.md — Push Notification Infrastructure.
    @MainActor
    func requestAuthorizationAndRegister() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

        if granted {
            UIApplication.shared.registerForRemoteNotifications()
            logger.info("Push notification authorization granted, registering for remote notifications")
        } else {
            logger.info("Push notification authorization denied by user")
        }

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        return granted
    }

    // MARK: - Device Token Callbacks

    /// Handle device token received from APNs via AppDelegate.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("Received APNs device token (\(tokenString.count) chars)")

        Task {
            await sendTokenToBackend(token: tokenString)
        }
    }

    /// Handle registration failure.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Backend Registration

    /// Send device token to backend for push notification delivery.
    private func sendTokenToBackend(token: String) async {
        let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = await UIDevice.current.name
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        let body = DeviceTokenRegisterBody(
            token: token,
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: appVersion
        )

        do {
            let _: DeviceTokenEnvelope<DeviceTokenRegisterResponseDTO> = try await apiClient.request(
                .registerDeviceToken(),
                body: body
            )
            await MainActor.run { isRegistered = true }
            logger.info("Device token registered with backend")
        } catch {
            logger.error("Failed to register device token with backend: \(error.localizedDescription)")
        }
    }

    /// Remove device token from backend (e.g., on logout).
    func unregister() async {
        let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        do {
            let _: DeviceTokenEnvelope<EmptyResponse> = try await apiClient.request(
                .removeDeviceToken(deviceID: deviceID)
            )
            await MainActor.run { isRegistered = false }
            logger.info("Device token removed from backend")
        } catch {
            logger.error("Failed to unregister device token: \(error.localizedDescription)")
        }
    }

    // MARK: - Status Check

    /// Check current notification authorization status.
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
        }
    }
}

// MARK: - API Endpoints

extension APIEndpoint where Response == DeviceTokenEnvelope<DeviceTokenRegisterResponseDTO> {
    static func registerDeviceToken() -> Self {
        APIEndpoint(path: "/v1/devices/register", method: .post)
    }
}

extension APIEndpoint where Response == DeviceTokenEnvelope<EmptyResponse> {
    static func removeDeviceToken(deviceID: String) -> Self {
        APIEndpoint(path: "/v1/devices/\(deviceID)", method: .delete)
    }
}

// MARK: - DeviceTokenRegisterBody

struct DeviceTokenRegisterBody: Codable {
    let token: String
    let deviceID: String
    let deviceName: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case token
        case deviceID = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
    }
}

// MARK: - DeviceTokenRegisterResponseDTO

struct DeviceTokenRegisterResponseDTO: Codable {
    let id: String
    let registered: Bool
}

// MARK: - DeviceTokenEnvelope

/// Envelope DTO matching backend Envelope<T>.
struct DeviceTokenEnvelope<T: Codable & Sendable>: Codable {
    let ok: Bool
    let data: T
}
