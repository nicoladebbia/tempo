//
// TrainerProgramSourceNormalizer.swift
// Tempo
//
// Turns whatever the athlete adds to a Trainer Program import — photos, a
// PDF, an Office/iWork/RTF/HTML/text/CSV file, or pasted text — into a flat,
// ordered list of `ProgramNormalizedUnit`s the vision transcription step can
// send to the proxy: each unit is either a page image (+ an on-device text
// hint) or, for a file that's already plain digital text (pasted text/.txt/
// .csv), text that skips transcription entirely and goes straight into the
// structuring step.
//
// Routing: PDF → each page rendered to an image (2x) plus its position-aware
// text layer (ProgramTextExtractor.positionAwareText); image → as-is (plus a
// Vision OCR hint); plain text/CSV → read directly, no image; everything
// else (Word/Excel/PowerPoint/Pages/Numbers/RTF/HTML/legacy .doc/.xls) has no
// on-device parser, so it's rendered to PDF via an off-screen WKWebView
// (ProgramOfficeConverter) and then walked like any other PDF.
//
// Every page image is downscaled to <= maxImageEdge (JPEG, q=jpegQuality)
// before it's kept — the proxy body limit is 5MB and base64 adds ~33%, so a
// full-res photo or a 2x-rendered PDF page has to shrink long before it's
// sent. The whole import is capped at maxPages units so one huge/garbled
// source can't silently starve the vision budget on every other page.
//

import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

// MARK: - ProgramImportSource

/// One thing the athlete added to this import — a photo just taken/picked, a
/// file from Files/Photos, or pasted text. Several sources make up ONE
/// import (e.g. "LIFT SESSIONS.pdf" + "CONDITIONING SESSIONS.pdf").
struct ProgramImportSource: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var payload: Payload

    enum Payload: Equatable {
        case image(UIImage)
        case fileURL(URL)
        case pastedText(String)

        static func == (lhs: Payload, rhs: Payload) -> Bool {
            switch (lhs, rhs) {
            case let (.image(a), .image(b)): a === b
            case let (.fileURL(a), .fileURL(b)): a == b
            case let (.pastedText(a), .pastedText(b)): a == b
            default: false
            }
        }
    }

    init(id: UUID = UUID(), displayName: String, payload: Payload) {
        self.id = id
        self.displayName = displayName
        self.payload = payload
    }

    var systemImage: String {
        switch payload {
        case .image: "photo"
        case let .fileURL(url):
            switch TrainerProgramSourceNormalizer.routingKind(for: url) {
            case .pdf: "doc.richtext"
            case .image: "photo"
            case .text: "doc.plaintext"
            case .officeConvertible: "doc"
            }
        case .pastedText: "text.alignleft"
        }
    }
}

// MARK: - ProgramNormalizedUnit

/// One page-equivalent chunk ready for the STRUCTURE step. `.page` still
/// needs a vision call (TrainerProgramPageTranscriber); `.directText` is
/// already legible machine text (pasted text, a .txt/.csv file) and skips
/// transcription entirely.
enum ProgramNormalizedUnit: Sendable {
    /// `imageJPEG` is already downscaled/compressed — ready to base64 as-is.
    case page(imageJPEG: Data, hintText: String?, sourceLabel: String)
    case directText(String, sourceLabel: String)

    var sourceLabel: String {
        switch self {
        case let .page(_, _, label): label
        case let .directText(_, label): label
        }
    }
}

// MARK: - TrainerProgramSourceNormalizer

@MainActor
enum TrainerProgramSourceNormalizer {
    /// Roughly what a 20-page import costs in vision calls; well past what
    /// any real trainer sheet needs, so hitting it means something (a whole
    /// folder, a mis-picked file) went in by mistake.
    static let maxPages = 20
    static let maxImageEdge: CGFloat = 2000
    static let jpegQuality: CGFloat = 0.8

    enum NormalizeError: Error, LocalizedError, Equatable {
        case noSources
        case tooManyPages(Int)
        case unreadableSource(String)

        var errorDescription: String? {
            switch self {
            case .noSources:
                "Add at least one source first."
            case let .tooManyPages(max):
                "That's \(max)+ pages across your sources — split it up and import in a couple of batches."
            case let .unreadableSource(name):
                "Couldn't read \"\(name)\". Try a clearer photo or a different file."
            }
        }
    }

    // MARK: - Routing

    enum ProgramSourceKind: Equatable {
        case pdf
        case image
        case text
        /// Word/Excel/PowerPoint/Pages/Numbers/RTF/HTML/legacy .doc/.xls —
        /// no on-device parser, converted to PDF first.
        case officeConvertible
    }

    /// Every content type `fileImporter` should offer. Several of these have
    /// no `UTType` static constant, so they're resolved by extension.
    /// Nonisolated (unlike the rest of this enum's WKWebView/UIImage/PDFKit
    /// work): pure UTType lookups, called from `ProgramImportSource.
    /// systemImage`, a plain non-actor-isolated computed property.
    nonisolated static let allowedContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .image, .plainText, .rtf, .html, .commaSeparatedText, .spreadsheet, .presentation]
        let byExtension = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers"]
        for ext in byExtension {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }()

    nonisolated static func routingKind(for url: URL) -> ProgramSourceKind {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return .officeConvertible
        }
        if type.conforms(to: .pdf) {
            return .pdf
        }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .plainText) || type.conforms(to: .commaSeparatedText) {
            return .text
        }
        return .officeConvertible
    }

    // MARK: - Normalize

    /// Normalizes every source, in order, into a flat unit list. Throws
    /// `.tooManyPages` as soon as the running total crosses `maxPages` — no
    /// point converting the rest of a batch that's already over budget.
    static func normalize(_ sources: [ProgramImportSource]) async throws -> [ProgramNormalizedUnit] {
        guard !sources.isEmpty else {
            throw NormalizeError.noSources
        }
        var units: [ProgramNormalizedUnit] = []
        for source in sources {
            try await units.append(contentsOf: normalizeOne(source))
            if units.count > maxPages {
                throw NormalizeError.tooManyPages(maxPages)
            }
        }
        guard !units.isEmpty else {
            throw NormalizeError.unreadableSource(sources.first?.displayName ?? "that source")
        }
        return units
    }

    private static func normalizeOne(_ source: ProgramImportSource) async throws -> [ProgramNormalizedUnit] {
        switch source.payload {
        case let .image(image):
            return try await [pageUnit(from: image, label: source.displayName)]
        case let .pastedText(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw NormalizeError.unreadableSource(source.displayName)
            }
            return [.directText(trimmed, sourceLabel: source.displayName)]
        case let .fileURL(url):
            return try await normalizeFile(at: url, label: source.displayName)
        }
    }

    private static func normalizeFile(at url: URL, label: String) async throws -> [ProgramNormalizedUnit] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        switch routingKind(for: url) {
        case .pdf:
            guard let document = PDFDocument(url: url) else {
                throw NormalizeError.unreadableSource(label)
            }
            return try await units(from: document, label: label)

        case .image:
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                throw NormalizeError.unreadableSource(label)
            }
            return try await [pageUnit(from: image, label: label)]

        case .text:
            guard let text = readText(at: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NormalizeError.unreadableSource(label)
            }
            return [.directText(text, sourceLabel: label)]

        case .officeConvertible:
            let pdfData: Data
            do {
                pdfData = try await ProgramOfficeConverter().convertToPDF(fileURL: url)
            } catch {
                throw NormalizeError.unreadableSource(label)
            }
            guard let document = PDFDocument(data: pdfData) else {
                throw NormalizeError.unreadableSource(label)
            }
            return try await units(from: document, label: label)
        }
    }

    /// One page image + Vision OCR hint (no PDF text layer to prefer).
    private static func pageUnit(from image: UIImage, label: String) async throws -> ProgramNormalizedUnit {
        guard let jpeg = downscaledJPEG(image) else {
            throw NormalizeError.unreadableSource(label)
        }
        let hint = try? await ProgramTextExtractor.extractText(from: image)
        return .page(imageJPEG: jpeg, hintText: hint, sourceLabel: label)
    }

    /// Walks every page of a PDF (real or WKWebView-converted): render 2x,
    /// prefer the position-aware text layer as the hint, fall back to Vision
    /// OCR on the rendered image for a page with no text layer at all (a
    /// scanned sheet).
    private static func units(from document: PDFDocument, label: String) async throws -> [ProgramNormalizedUnit] {
        var result: [ProgramNormalizedUnit] = []
        let pageCount = document.pageCount
        for index in 0 ..< pageCount {
            guard let page = document.page(at: index), let rendered = ProgramTextExtractor.renderImage(for: page) else {
                continue
            }
            guard let jpeg = downscaledJPEG(rendered) else {
                continue
            }
            var hint = ProgramTextExtractor.positionAwareText(on: page)
            if hint == nil {
                hint = try? await ProgramTextExtractor.extractText(from: rendered)
            }
            let pageLabel = pageCount > 1 ? "\(label) — page \(index + 1)" : label
            result.append(.page(imageJPEG: jpeg, hintText: hint, sourceLabel: pageLabel))
        }
        return result
    }

    private static func downscaledJPEG(_ image: UIImage) -> Data? {
        image.downsampledJPEGData(maxEdge: maxImageEdge, quality: jpegQuality)
    }

    /// UTF-8 first, ISO Latin-1 fallback — a trainer's plain-text/CSV export
    /// isn't guaranteed to be UTF-8.
    private static func readText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
