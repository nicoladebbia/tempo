//
// ProgramOfficeConverter.swift
// Tempo
//
// On-device Word/Excel/PowerPoint/Pages/Numbers/RTF/HTML → PDF conversion
// for the Trainer Program import pipeline: none of those formats have a
// first-party on-device parser, but WKWebView (QuickLook's own document
// preview engine underneath) can open all of them and `createPDF` renders
// whatever it's showing — so TrainerProgramSourceNormalizer treats the
// result exactly like any other PDF (page images + position-aware text).
//
// Not unit-tested (per the import-pipeline plan): it needs a real WebKit
// render pass, which doesn't run in the test target. TrainerProgramSourceNormalizerTests
// covers the type ROUTING that decides a file needs this path instead.
//

import Foundation
import WebKit

// MARK: - ProgramOfficeConverter

@MainActor
final class ProgramOfficeConverter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    enum ConverterError: Error, LocalizedError {
        case loadFailed(String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case let .loadFailed(detail): "Could not open that file: \(detail)"
            case .emptyOutput: "That file has no readable content."
            }
        }
    }

    /// Loads `fileURL` in an off-screen web view and renders the result to
    /// PDF data. One converter per call — the navigation delegate holds a
    /// single in-flight continuation, so a fresh instance avoids two
    /// concurrent conversions racing on it.
    func convertToPDF(fileURL: URL) async throws -> Data {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 816, height: 1056))
        webView.navigationDelegate = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(with: result)
            }
        }
        guard !data.isEmpty else {
            throw ConverterError.emptyOutput
        }
        return data
    }

    // MARK: - WKNavigationDelegate

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: ConverterError.loadFailed(error.localizedDescription))
        continuation = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: ConverterError.loadFailed(error.localizedDescription))
        continuation = nil
    }
}
