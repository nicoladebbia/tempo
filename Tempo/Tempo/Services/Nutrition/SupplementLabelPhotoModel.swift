//
// SupplementLabelPhotoModel.swift
// Tempo
//
// "Photograph the label": the photo is downscaled, sent to the backend
// (`POST /v1/supplements/read-label`, Claude vision) and the read-out lands on
// the normal review screen. This file holds the pure pieces so they are
// unit-testable without a camera: the image prep, the state machine that maps
// every failure (422 / 429 / offline / AI blockers) to a screen state, and the
// best-effort catalog submission built from the reviewed form.
//

import Foundation
import Observation
import UIKit

// MARK: - Image prep

enum SupplementLabelImage {
    /// Long edge handed to the AI: sharp enough for a facts panel, ~300 KB.
    static let maxEdge: CGFloat = 1600
    static let quality: CGFloat = 0.7
    static let mediaType = "image/jpeg"

    static func jpeg(from image: UIImage) -> Data? {
        image.downsampledJPEGData(maxEdge: maxEdge, quality: quality)
    }
}

// MARK: - Catalog submission mapping

extension SupplementCatalogSubmission {
    /// Maps the reviewed (possibly user-edited) shelf draft. Nil when the
    /// draft has no name — the backend would reject it anyway.
    init?(draft: Supplement, origin: SupplementCatalogOrigin) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        func positive(_ value: Double?) -> Double? {
            guard let value, value > 0 else { return nil }
            return value
        }
        /// An explicit 0 g is real data (0 g fat / 0 g carbs); only nil is dropped.
        func nonNegative(_ value: Double?) -> Double? {
            guard let value, value >= 0 else { return nil }
            return value
        }
        let lines = (draft.ingredientsSummary ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.init(
            upc: clean(draft.upc),
            brand: clean(draft.brand),
            name: name,
            kind: draft.kindRaw,
            dosePerServing: clean(draft.dosePerServing),
            servingsPerContainer: positive(draft.servingsPerContainer),
            proteinGramsPerServing: positive(draft.proteinGramsPerServing),
            caloriesPerServing: nonNegative(draft.caloriesPerServing),
            carbsGramsPerServing: nonNegative(draft.carbsGramsPerServing),
            fatGramsPerServing: nonNegative(draft.fatGramsPerServing),
            ingredients: lines.isEmpty ? nil : Array(lines.prefix(60)),
            origin: origin.rawValue
        )
    }
}

enum SupplementCatalogSubmitter {
    static let confirmation = "Added to Tempo's catalog — the next scan finds it."
    /// Shown on the review screen before saving, when the save will be shared.
    static let disclosure = "Saving also shares this product (not you) with Tempo's catalog."

    /// True when saving a fresh add from the review screen shares it (same rule as `origin`).
    static func willShare(isNew: Bool, prefill: SupplementLookupDTO?, prefillUPC: String?) -> Bool {
        guard isNew else { return false }
        let hadBarcode = prefill == nil && !(prefillUPC ?? "").isEmpty
        return origin(prefillSource: prefill?.source, hadBarcode: hadBarcode) != nil
    }

    static let reportThanks = "Thanks. We'll look at it."

    /// Which origin (if any) a freshly reviewed add should be shared under.
    /// Label photos always; a manual entry only when it came from a barcode
    /// nothing knew. Search / quick-add picks are already in a database.
    static func origin(prefillSource: String?, hadBarcode: Bool) -> SupplementCatalogOrigin? {
        if prefillSource == "label_photo" { return .labelPhoto }
        if prefillSource == nil, hadBarcode { return .manual }
        return nil
    }

    /// Never throws and never blocks the save: returns whether it landed so
    /// the caller can show the quiet confirmation line.
    @MainActor
    static func submit(
        draft: Supplement,
        origin: SupplementCatalogOrigin,
        using service: any SupplementLookupServicing
    ) async -> Bool {
        guard let submission = SupplementCatalogSubmission(draft: draft, origin: origin) else { return false }
        return (try? await service.submitToCatalog(submission)) != nil
    }
}

// MARK: - State machine

@MainActor
@Observable
final class SupplementLabelPhotoModel {
    enum Failure: Equatable {
        /// 422 / 415 — the photo isn't a readable label. Offer Retake.
        case unreadable
        /// 429 — AI budget or rate limit. Offer manual entry.
        case busy
        /// No connection. Offer retry + manual entry.
        case offline
        /// Pro / AI-consent gate.
        case blocked(AIBlocker)
        case other(String)

        var message: String {
            switch self {
            case .unreadable:
                "Couldn't read a supplement label in that photo. Try again closer, with the facts panel flat and lit."
            case .busy:
                "Label reading is maxed out for now. Type it in, or try again in a bit."
            case .offline:
                "You're offline. Reconnect to have Tempo read the label, or type it in now."
            case .blocked(.proRequired):
                "Reading labels with AI is a Tempo Pro feature. You can still search or type it."
            case .blocked(.aiConsentRequired):
                "AI features are off. Turn them on to read labels, or type it in."
            case let .other(message):
                message
            }
        }

        /// A same-photo retry can help (transient), vs needing a new photo.
        var canRetrySamePhoto: Bool {
            switch self {
            case .offline, .other: true
            case .unreadable, .busy, .blocked: false
            }
        }
    }

    enum State: Equatable {
        case idle
        case reading
        case done(SupplementLookupDTO)
        case failed(Failure)
    }

    private(set) var state: State = .idle
    private let service: any SupplementLookupServicing
    private let upc: String?
    private var lastBase64: String?

    init(service: any SupplementLookupServicing, upc: String?) {
        self.service = service
        self.upc = upc.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Downscale + encode + send. Safe to call again after a failure.
    func read(image: UIImage) async {
        guard let data = SupplementLabelImage.jpeg(from: image) else {
            state = .failed(.unreadable)
            return
        }
        lastBase64 = data.base64EncodedString()
        await send()
    }

    /// Re-sends the last photo (transient failures only).
    func retry() async {
        guard lastBase64 != nil else {
            state = .idle
            return
        }
        await send()
    }

    func reset() {
        lastBase64 = nil
        state = .idle
    }

    private func send() async {
        guard let base64 = lastBase64 else { return }
        state = .reading
        do {
            var dto = try await service.readLabel(imageBase64: base64, mediaType: SupplementLabelImage.mediaType, upc: upc)
            if let upc, dto.upc.isEmpty {
                dto = dto.withUPC(upc)
            }
            state = .done(dto)
        } catch {
            state = .failed(Self.failure(for: error))
        }
    }

    static func failure(for error: Error) -> Failure {
        if let blocker = AIBlocker(error) { return .blocked(blocker) }
        guard let api = error as? APIError else {
            return (error as? URLError) != nil ? .offline : .other(error.localizedDescription)
        }
        switch api {
        case let .unknown(status) where status == 422 || status == 415: return .unreadable
        case .rateLimited, .serverError(statusCode: 503): return .busy
        case .networkError, .connectionRefused, .timeout, .noResponse: return .offline
        case .unauthorized: return .other("Sign in to read labels with AI, or type it in.")
        case .payloadTooLarge: return .unreadable
        default: return .other(api.userMessage)
        }
    }
}
