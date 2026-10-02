//
// CameraPermission.swift
// Tempo
//
// One answer to "can the scanner use the camera?" for UniversalScanView.
// Denied/restricted (the user or a parent said no) is NOT the same as
// unsupported (this device or the simulator has no scanner camera): the first
// needs an "Open Settings" button, the second only needs the manual fallbacks.
//

import AVFoundation
import UIKit
import VisionKit

enum CameraPermission: Equatable {
    case authorized
    /// Never asked yet; the first Scan tap asks.
    case notDetermined
    case denied
    case restricted
    /// No usable scanner camera on this device (simulator, camera in use).
    case unsupported

    /// Pure mapping, so it can be tested without a camera.
    /// A "no" from the user always wins over "unsupported": Settings is the
    /// only fix for that and the message must say so.
    static func resolve(status: AVAuthorizationStatus, cameraSupported: Bool) -> CameraPermission {
        switch status {
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: cameraSupported ? .authorized : .unsupported
        case .notDetermined: cameraSupported ? .notDetermined : .unsupported
        @unknown default: .unsupported
        }
    }

    /// `needsLiveScanner` is true for the barcode viewfinder (DataScanner);
    /// photo modes only need a camera at all.
    @MainActor
    static func current(needsLiveScanner: Bool = true) -> CameraPermission {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        // DataScanner reports "unavailable" until access is granted, so only
        // trust that flag once the user has said yes.
        let supported = needsLiveScanner
            ? DataScannerViewController.isSupported && (status != .authorized || DataScannerViewController.isAvailable)
            : UIImagePickerController.isSourceTypeAvailable(.camera)
        return resolve(status: status, cameraSupported: supported)
    }

    /// Asks once; returns the state after the system sheet closes.
    @MainActor
    static func request(needsLiveScanner: Bool = true) async -> CameraPermission {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return current(needsLiveScanner: needsLiveScanner)
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    var isBlockedByUser: Bool {
        self == .denied || self == .restricted
    }
}
