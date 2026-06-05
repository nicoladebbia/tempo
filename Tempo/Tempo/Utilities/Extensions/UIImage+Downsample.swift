//
// UIImage+Downsample.swift
// Tempo
//
// Shared image-downsampling used by every path that uploads a photo to the
// backend (food photo analysis, receipt structuring). Capping the long edge at
// Claude's documented max vision edge (1568px) keeps memory + the uploaded
// base64 payload bounded regardless of camera resolution — full-res iPhone
// JPEGs base64-encode to ~2MB+ and trip the backend's request-body limit (413).
//

import Foundation

#if canImport(UIKit)
import UIKit

/// Claude's max vision pixel edge. Images larger than this are downsized before
/// upload; anything bigger is wasted bytes the model never reads.
let maxClaudeVisionPixelEdge: CGFloat = 1568

extension UIImage {
    /// Resize-to-fit (long edge ≤ `maxEdge`) → JPEG `Data`. This is the raw
    /// payload both upload paths send; persist it for retry or base64-encode it
    /// for the request body via `.base64EncodedString()`.
    func downsampledJPEGData(
        maxEdge: CGFloat = maxClaudeVisionPixelEdge,
        quality: CGFloat = 0.8
    ) -> Data? {
        let longEdge = max(size.width, size.height)
        let target: UIImage
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            target = renderer.image { _ in
                draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            target = self
        }
        return target.jpegData(compressionQuality: quality)
    }

    /// Convenience: downsampled JPEG as base64 plus its raw byte count, for
    /// callers that only upload and don't persist.
    func downsampledJPEGBase64(
        maxEdge: CGFloat = maxClaudeVisionPixelEdge,
        quality: CGFloat = 0.8
    ) -> (base64: String, byteCount: Int)? {
        guard let jpeg = downsampledJPEGData(maxEdge: maxEdge, quality: quality) else {
            return nil
        }
        return (jpeg.base64EncodedString(), jpeg.count)
    }
}
#endif
